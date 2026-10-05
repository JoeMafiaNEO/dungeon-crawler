class_name Mob
extends CharacterBody3D
## Server-authoritative monster with a billboarded 2D sprite.
## The host simulates AI and health; snapshots keep remote peers in sync.

const GRAVITY := 20.0

var mob_id := 0
var data: MobData
var hp := 10.0
var max_hp := 10.0
var alive := true
var hp_scale := 1.0
var dmg_scale := 1.0
## Danger-model reward scale (tier × depth at spawn): drives XP and loot
## sell values. Server-authoritative, synced like hp/dmg scale.
var reward_scale := 1.0

var _target: Node3D
var _attack_cd := 0.0
var _snapshot := 0.0
var _retarget := 0.0
var _remote_pos := Vector3.ZERO
var _has_remote := false
var _knockback := Vector3.ZERO
var _sprite: AnimatedSprite3D
var _flash_tween: Tween
var _bob_t := 0.0
var _base_scale := Vector3.ONE
## Elite mobs: 2.5x HP, 1.25x size, +1.5 loot luck, gold nameplate.
var is_elite := false
## Slow debuff (frost): _slow_t seconds remaining at _slow_mult speed.
var _slow_t := 0.0
var _slow_mult := 1.0
## Smoke Bombard (combo finisher): blinded mobs miss 50% of attacks.
var _blind_t := 0.0
## Shatter: slowed enemies take +25% damage (mage opens windows for team).
var _shatter_t := 0.0
## Burn (wildfire trait): damage over time.
var _burn_t := 0.0
var _burn_dps := 0.0
var _burn_attacker := 0
var _burn_tick := 0.0
## Relentless (Conqueror trait): while bulwark-slowed, this mob deals -10% damage.
var bulwark_slow_t := 0.0
## Doom Totem (Conqueror signature): mob takes +30% damage from all sources.
var doom_t := 0.0
# --- Boss state ---
var _special_cd := 4.0
var _telegraph := 0.0
var _pending_special := ""
var _charge_t := 0.0
var _charge_dir := Vector3.ZERO
var _charge_hit: Array = []
# --- Apex mechanics (issue #5 Phase 2; only active when data.apex_id != "") ---
## Phaseshift untargetability: take_damage ignores all hits while true.
var untargetable := false
## Enrage (Bristleback): latched below 30% HP.
var _enraged := false
## Adds (Warden): HP gates that each summon 2 elite skeletons once.
var _adds_gates := [0.66, 0.33]
var _adds_fired := 0
## Phaseshift (Horror): HP gates that each trigger a 2s untargetable teleport once.
var _shift_gates := [0.75, 0.50, 0.25]
var _shift_fired := 0
var _phaseshift_t := 0.0
## Fire trail (enrage charge): seconds until the next scorch decal drop.
var _trail_tick := 0.0
## Expanding shockwave rings (apex slam): [{radius, max_radius, speed, hit}].
var _shockwaves: Array = []


func setup(p_id: int, p_data: MobData, p_hp_scale: float = 1.0, p_dmg_scale: float = 1.0, p_elite: bool = false, p_reward_scale: float = 1.0) -> void:
	mob_id = p_id
	data = p_data
	hp_scale = p_hp_scale
	dmg_scale = p_dmg_scale
	reward_scale = p_reward_scale
	is_elite = p_elite and not p_data.is_boss
	if is_elite:
		hp_scale *= 2.5


func _ready() -> void:
	add_to_group("mobs")
	# Mask layers 1+2: dungeon geometry/players AND architect walls (layer 2).
	# Players keep mask 1, so walls block enemies but not allies.
	collision_mask = 3
	hp = data.health * hp_scale
	max_hp = hp
	_sprite = $AnimatedSprite3D
	var frames := SpriteFrames.new()
	for tex in data.frames:
		frames.add_frame("default", tex)
	frames.set_animation_speed("default", 3.0)
	frames.set_animation_loop("default", true)
	_sprite.frames = frames
	_sprite.play("default")
	if data.is_boss:
		$Label3D.text = data.boss_title
		$Label3D.font_size = 64
		$Label3D.modulate = Color(1.0, 0.45, 0.4)
		_base_scale = Vector3.ONE * data.scale_mult
	elif is_elite:
		$Label3D.text = "Elite " + data.display_name
		$Label3D.modulate = Color(1.0, 0.85, 0.3)
		_base_scale = Vector3.ONE * 1.25
	else:
		$Label3D.text = data.display_name
	_sprite.scale = _base_scale
	_remote_pos = global_position
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	# Slow debuff ticks down (server-side).
	if _slow_t > 0.0:
		_slow_t -= delta
		if _slow_t <= 0.0:
			_slow_mult = 1.0
			_sprite.modulate = Color.WHITE
	# Blind debuff ticks down (server-side).
	if _blind_t > 0.0:
		_blind_t -= delta
	# Relentless marker ticks down alongside the slow.
	if bulwark_slow_t > 0.0:
		bulwark_slow_t -= delta
	# Doom Totem debuff ticks down.
	if doom_t > 0.0:
		doom_t -= delta
	if _shatter_t > 0.0:
		_shatter_t -= delta
	# Burn ticks (server-side).
	if _burn_t > 0.0 and multiplayer.is_server():
		_burn_t -= delta
		_burn_tick += delta
		if _burn_tick >= 0.5:
			_burn_tick = 0.0
			_take_burn_tick()
	# Mark ticks down.
	if _mark_t > 0.0:
		_mark_t -= delta
		if _mark_t <= 0.0 and _slow_t <= 0.0:
			_sprite.modulate = Color.WHITE
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.5
		_target = _nearest_player()
	var boss_busy := false
	if data.is_boss:
		boss_busy = _boss_think(delta)
	if not boss_busy and _target != null and is_instance_valid(_target):
		var to: Vector3 = _target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if data.ranged:
			_ranged_think(delta, to, dist)
		elif dist > data.attack_range:
			var dir := to / dist
			velocity.x = dir.x * data.move_speed * _slow_mult * _move_speed_mult()
			velocity.z = dir.z * data.move_speed * _slow_mult * _move_speed_mult()
			_sprite.rotation.y = atan2(dir.x, dir.z)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			_attack_cd -= delta
			if _attack_cd <= 0.0:
				_attack_cd = data.attack_cooldown
				if _misses():
					pass  # Blinded (Smoke Bombard): the swing misses.
				elif _target.is_in_group("decoys"):
					# Shadow decoy: direct damage, server-side (no RPC target).
					_target.damage(data.damage * dmg_scale * _dmg_mult())
				elif _target.is_in_group("structures"):
					# Architect structure: direct damage, server-side (no RPC target).
					_target.take_structure_damage(data.damage * dmg_scale * _dmg_mult(), NetworkManager.server_id)
				else:
					_target.rpc_id(_target.get_multiplayer_authority(), "take_damage", data.damage * dmg_scale * _dmg_mult(), data.display_name)
	elif not boss_busy:
		velocity.x = 0.0
		velocity.z = 0.0
	if _knockback.length() > 0.05:
		velocity.x += _knockback.x
		velocity.z += _knockback.z
		_knockback = _knockback.move_toward(Vector3.ZERO, delta * 18.0)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_snapshot -= delta
	if _snapshot <= 0.0:
		_snapshot = 0.15
		rpc("push_snapshot", global_position, hp, alive)


func _process(delta: float) -> void:
	_bob_t += delta
	_sprite.position.y = 0.9 + sin(_bob_t * 3.0) * 0.06
	if multiplayer.is_server():
		return
	if _has_remote:
		global_position = global_position.lerp(_remote_pos, clampf(delta * 8.0, 0.0, 1.0))


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p == null:
			continue
		if p.get("alive") == false:
			continue
		if p.get("stealthed") == true:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	# Shadow decoys (Double Take trait) also draw aggro.
	for n in get_tree().get_nodes_in_group("decoys"):
		var dec := n as Node3D
		if dec == null:
			continue
		var dd := global_position.distance_to(dec.global_position)
		if dd < best_d:
			best_d = dd
			best = dec
	# Architect structures draw aggro (traps are hidden).
	for n in get_tree().get_nodes_in_group("structures"):
		var st := n as Structure
		if st == null:
			continue
		if st.structure_id == "spike_trap":
			continue
		if st.hp <= 0.0:
			continue
		var sd := global_position.distance_to(st.global_position)
		if sd < best_d:
			best_d = sd
			best = st
	return best


# --- Ranged AI (server-side) ---

var _strafe_dir := 1.0
var _strafe_t := 0.0


## Outgoing damage multiplier: Relentless makes bulwark-slowed mobs deal -10%.
func _dmg_mult() -> float:
	return 0.9 if bulwark_slow_t > 0.0 else 1.0


## Apex enrage: +40% movement speed below 30% HP (Bristleback).
func _move_speed_mult() -> float:
	return 1.4 if _enraged else 1.0


## Special cooldown: enraged apex Bristleback recharges in 4s instead of 7s.
func _special_cooldown() -> float:
	if _enraged:
		return 4.0
	return data.special_cooldown


## Ranged attackers hold their preferred distance: back off when crowded,
## close in when too far, strafe sideways, and fire when roughly in range.
func _ranged_think(delta: float, to: Vector3, dist: float) -> void:
	var ideal := data.preferred_range
	var dir := Vector3.ZERO
	if dist > 0.01:
		dir = to / dist
	_sprite.rotation.y = atan2(dir.x, dir.z)
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.0, 2.5)
		_strafe_dir = -_strafe_dir if randf() < 0.7 else _strafe_dir
	var move := Vector3.ZERO
	if dist < ideal * 0.7:
		move = -dir  # too close: back away
	elif dist > ideal * 1.3:
		move = dir  # too far: close in
	# Always add a strafing component so they don't stand still.
	var side := Vector3(-dir.z, 0, dir.x) * _strafe_dir
	move = (move + side * 0.8).normalized()
	velocity.x = move.x * data.move_speed * _slow_mult
	velocity.z = move.z * data.move_speed * _slow_mult
	# Fire when within a generous band of the ideal range.
	if dist < ideal * 1.6:
		_attack_cd -= delta
		if _attack_cd <= 0.0:
			_attack_cd = data.attack_cooldown
			_fire_arrow(dir)


func _fire_arrow(dir: Vector3) -> void:
	if _misses():
		return  # Blinded (Smoke Bombard): the shot goes wide.
	var from := global_position + Vector3(0, 1.4, 0) + dir * 0.6
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null:
		dungeon.rpc("spawn_arrow", from, dir, data.damage * dmg_scale * _dmg_mult(), data.projectile_speed, data.display_name)
	AudioManager.sfx("bow_shot", global_position)


## Applies a slow debuff (frost). Server-side; visual tint included.
func apply_slow(duration: float, mult: float) -> void:
	if not alive:
		return
	_slow_t = maxf(_slow_t, duration)
	_slow_mult = minf(_slow_mult, mult)
	# Shatter: slowed enemies take +25% damage (class interdependence).
	_shatter_t = maxf(_shatter_t, duration)
	_sprite.modulate = Color(0.7, 0.85, 1.0)
	rpc("slow_fx", duration, mult)


## Frost-slowed right now (combo-finisher world state).
func is_slowed() -> bool:
	return _slow_t > 0.0


## Applies blind (Smoke Bombard): the mob misses 50% of attacks while blind.
func apply_blind(duration: float) -> void:
	if not alive:
		return
	_blind_t = maxf(_blind_t, duration)


## Blind miss roll, checked at each attack site (server-side).
func _misses() -> bool:
	return _blind_t > 0.0 and randf() < 0.5


## Applies a burn DoT (wildfire trait). Server-side; refreshes duration.
func apply_burn(duration: float, dps: float, attacker: int) -> void:
	if not alive:
		return
	if not multiplayer.is_server():
		return
	_burn_t = maxf(_burn_t, duration)
	_burn_dps = maxf(_burn_dps, dps)
	_burn_attacker = attacker
	_sprite.modulate = Color(1.0, 0.6, 0.3)


func _take_burn_tick() -> void:
	if not alive or _burn_t <= 0.0:
		return
	hp -= _burn_dps * 0.5
	# Credit the attacking player.
	for n in get_tree().get_nodes_in_group("players"):
		var pl := n as Player
		if pl != null and pl.get_multiplayer_authority() == _burn_attacker:
			pl.run_damage_dealt += _burn_dps * 0.5
			break
	if hp <= 0.0:
		hp = 0.0
		alive = false
		rpc("play_death")


@rpc("any_peer", "call_local")
func slow_fx(_duration: float, _mult: float) -> void:
	if _sprite != null:
		_sprite.modulate = Color(0.7, 0.85, 1.0)


## Eagle Eye x-ray: render through walls for recon.
var _xray := false


@rpc("any_peer", "call_local")
func set_xray(enabled: bool) -> void:
	_xray = enabled
	if _sprite != null:
		_sprite.no_depth_test = enabled
		if enabled:
			_sprite.modulate = Color(1.0, 0.9, 0.5)
		elif _slow_t <= 0.0:
			_sprite.modulate = Color.WHITE


## Marked target: takes +50% damage from everyone while marked.
var _mark_t := 0.0


func is_marked() -> bool:
	return _mark_t > 0.0


@rpc("any_peer", "call_local")
func apply_mark(duration: float, slow_mult: float = 1.0) -> void:
	_mark_t = duration
	if _sprite != null:
		# Red pulsing outline effect via modulate.
		_sprite.modulate = Color(1.0, 0.6, 0.6)
	# Hamstring Mark trait: marked targets are also slowed 20% (no shatter synergy).
	if slow_mult < 1.0:
		_slow_t = maxf(_slow_t, duration)
		_slow_mult = minf(_slow_mult, slow_mult)
		rpc("slow_fx", duration, slow_mult)
	AudioManager.sfx("mark_applied", global_position)


# --- Boss specials (server-side) ---

## Returns true while the boss is telegraphing or charging (normal AI paused).
func _boss_think(delta: float) -> bool:
	# Expanding shockwave rings keep moving even while the Warden telegraphs.
	if not _shockwaves.is_empty():
		_process_shockwaves(delta)
	# Phaseshift window: the Horror holds still, untargetable, for 2s.
	if _phaseshift_t > 0.0:
		_phaseshift_t -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _phaseshift_t <= 0.0:
			untargetable = false
			_sprite.modulate.a = 1.0
			rpc("phaseshift_end")
		return true
	if _telegraph > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_telegraph -= delta
		# Pulsing red wind-up.
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 60.0)
		_sprite.modulate = Color(1.0, 0.35 * pulse, 0.35 * pulse)
		_sprite.scale = _base_scale * (1.0 + 0.08 * pulse)
		if _telegraph <= 0.0:
			_fire_special()
		return true
	if _charge_t > 0.0:
		_charge_t -= delta
		# Apex enrage: the charge leaves a 4s fire trail (visual scorch decals).
		if data.apex_id == "enrage":
			_trail_tick -= delta
			if _trail_tick <= 0.0:
				_trail_tick = 0.15
				rpc("trail_scorch", global_position)
		velocity.x = _charge_dir.x * data.move_speed * 4.5 * _move_speed_mult()
		velocity.z = _charge_dir.z * data.move_speed * 4.5 * _move_speed_mult()
		_check_charge_hits()
		if _charge_t <= 0.0:
			velocity.x = 0.0
			velocity.z = 0.0
		return true
	_special_cd -= delta
	if _special_cd <= 0.0 and _target != null and is_instance_valid(_target):
		var dist := global_position.distance_to(_target.global_position)
		match data.special_id:
			"slam":
				if dist < 9.0:
					_begin_telegraph("slam", 0.8)
					return true
			"summon":
				_do_summon()
			"charge":
				if dist > 4.0 and dist < 22.0:
					_begin_telegraph("charge", 0.6)
					return true
	return false


func _begin_telegraph(special: String, duration: float) -> void:
	_pending_special = special
	_telegraph = duration
	AudioManager.sfx("boss_roar", global_position)


func _fire_special() -> void:
	_special_cd = _special_cooldown()
	_sprite.modulate = Color.WHITE
	_sprite.scale = _base_scale
	match _pending_special:
		"slam":
			_do_slam()
		"charge":
			_do_charge()
	_pending_special = ""


func _do_slam() -> void:
	# Apex Warden: the slam's damage travels as an expanding shockwave ring
	# instead of an instant AoE — dodge by getting clear of its path.
	if data.apex_id == "adds":
		_fire_shockwave()
		return
	rpc("slam_fx", global_position)
	if _misses():
		return  # Blinded (Smoke Bombard): the slam misses.
	var dmg := data.damage * data.special_damage_mult * dmg_scale * _dmg_mult()
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p == null or p.get("alive") == false:
			continue
		if global_position.distance_to(p.global_position) > 6.5:
			continue
		p.rpc_id(p.get_multiplayer_authority(), "take_damage", dmg, data.display_name)


## Apex Warden shockwave: expanding ring, 7.5 m/s out to 9m, hitting each
## player once as the ring passes them. Server-side damage, shared visual.
func _fire_shockwave() -> void:
	rpc("shockwave_fx", global_position)
	_shockwaves.append({"radius": 1.0, "max_radius": 9.0, "speed": 7.5, "hit": []})


func _process_shockwaves(delta: float) -> void:
	var dmg := data.damage * data.special_damage_mult * dmg_scale * _dmg_mult()
	var done: Array = []
	for w in _shockwaves:
		w["radius"] = float(w["radius"]) + float(w["speed"]) * delta
		var hit: Array = w["hit"]
		for n in get_tree().get_nodes_in_group("players"):
			var p := n as Node3D
			if p == null or p.get("alive") == false or n in hit:
				continue
			if global_position.distance_to(p.global_position) <= float(w["radius"]):
				hit.append(n)
				p.rpc_id(p.get_multiplayer_authority(), "take_damage", dmg, data.display_name)
		if float(w["radius"]) >= float(w["max_radius"]):
			done.append(w)
	for w in done:
		_shockwaves.erase(w)


## Apex HP-gated triggers (issue #5 Phase 2). Server-side, called from
## take_damage after a surviving hit. Each gate fires exactly once.
func _check_apex_triggers() -> void:
	if data.apex_id == "" or not alive:
		return
	var frac := hp / max_hp
	match data.apex_id:
		"enrage":
			if not _enraged and frac <= 0.30:
				_enraged = true
				rpc("apex_enrage_fx", global_position)
				var dungeon := get_tree().get_first_node_in_group("dungeon")
				if dungeon != null:
					dungeon.rpc("announce", "%s IS ENRAGED!" % data.boss_title.to_upper())
		"adds":
			while _adds_fired < _adds_gates.size() and frac <= _adds_gates[_adds_fired]:
				_adds_fired += 1
				_summon_apex_adds()
		"phaseshift":
			while _shift_fired < _shift_gates.size() and frac <= _shift_gates[_shift_fired]:
				_shift_fired += 1
				_do_phaseshift()


## Apex Warden: each HP gate summons 2 elite skeletons beside the boss.
func _summon_apex_adds() -> void:
	# Untyped dungeon ref: the headless test swaps in a stub node.
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return
	rpc("summon_fx", global_position)
	dungeon.rpc("announce", "%s CALLS ITS GUARD!" % data.boss_title.to_upper())
	for i in 2:
		var pos := global_position + Vector3(randf_range(-3.0, 3.0), 0.5, randf_range(-3.0, 3.0))
		dungeon.server_spawn_mob("skeleton", pos, true)


## Apex Horror: 2s untargetable + teleport to a random arena point.
func _do_phaseshift() -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return
	untargetable = true
	_phaseshift_t = 2.0
	_target = null
	var dest: Vector3 = dungeon.random_arena_pos()
	if dest != Vector3.INF:
		global_position = Vector3(dest.x, 0.5, dest.z)
	_sprite.modulate.a = 0.35
	rpc("phaseshift_fx", global_position)


func _do_charge() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var to: Vector3 = _target.global_position - global_position
	to.y = 0.0
	if to.length() < 0.1:
		return
	_charge_dir = to.normalized()
	_sprite.rotation.y = atan2(_charge_dir.x, _charge_dir.z)
	_charge_t = 0.55
	_charge_hit.clear()
	rpc("charge_fx", global_position)


func _check_charge_hits() -> void:
	if _misses():
		return  # Blinded (Smoke Bombard): the charge misses.
	var dmg := data.damage * data.special_damage_mult * dmg_scale * _dmg_mult()
	for n in get_tree().get_nodes_in_group("players"):
		if n in _charge_hit:
			continue
		var p := n as Node3D
		if p == null or p.get("alive") == false:
			continue
		if global_position.distance_to(p.global_position) > 2.4:
			continue
		_charge_hit.append(n)
		p.rpc_id(p.get_multiplayer_authority(), "take_damage", dmg, data.display_name)


func _do_summon() -> void:
	_special_cd = _special_cooldown()
	var minions := 0
	for m in get_tree().get_nodes_in_group("mobs"):
		if m != self and not (m.get("data") as MobData).is_boss:
			minions += 1
	if minions >= 6:
		return
	# Untyped dungeon ref: the headless test swaps in a stub node.
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return
	rpc("summon_fx", global_position)
	# Apex Horror: its cultists always spawn elite (summon_count is 4 in data).
	var force_elite := data.apex_id == "phaseshift"
	for i in data.summon_count:
		var pos := global_position + Vector3(randf_range(-3.0, 3.0), 0.5, randf_range(-3.0, 3.0))
		dungeon.server_spawn_mob(data.summon_id, pos, force_elite)


@rpc("any_peer", "call_local")
func slam_fx(pos: Vector3) -> void:
	AudioManager.sfx("boss_slam", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 0.4, 0), Color(0.55, 0.45, 0.35), 40, 9.0)
	Effects.burst(get_parent(), pos + Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.2), 24, 7.0)


@rpc("any_peer", "call_local")
func summon_fx(pos: Vector3) -> void:
	AudioManager.sfx("wave_horn", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 1.2, 0), Color(0.6, 0.2, 0.9), 30, 6.0)


@rpc("any_peer", "call_local")
func charge_fx(pos: Vector3) -> void:
	AudioManager.sfx("boss_slam", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 0.5, 0), Color(0.7, 0.6, 0.5), 16, 6.0)


## Apex Bristleback enrage: drops a scorch decal while charging (4s fire trail).
@rpc("any_peer", "call_local")
func trail_scorch(pos: Vector3) -> void:
	Effects.scorch(get_parent(), Vector3(pos.x, 0.06, pos.z), 1.4)


## Apex Bristleback enrage announcement burst.
@rpc("any_peer", "call_local")
func apex_enrage_fx(pos: Vector3) -> void:
	AudioManager.sfx("boss_roar", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(1.0, 0.25, 0.1), 40, 7.0)


## Apex Warden shockwave: expanding ring visual, 1.1s out to 9m (matches
## the server-side 7.5 m/s expansion). Damage is server-side only.
@rpc("any_peer", "call_local")
func shockwave_fx(pos: Vector3) -> void:
	AudioManager.sfx("boss_slam", pos)
	var parent := get_parent()
	if parent == null:
		return
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.15, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 2.0
	torus.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.35, pos.z)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(9, 1, 9), 1.1).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.1)
	tw.chain().tween_callback(mi.queue_free)


## Apex Horror phaseshift: teleport burst + phased-out fade (clients apply it).
@rpc("any_peer", "call_local")
func phaseshift_fx(pos: Vector3) -> void:
	AudioManager.sfx("wave_horn", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(0.6, 0.2, 0.9), 40, 7.0)
	if not multiplayer.is_server():
		global_position = pos
		_sprite.modulate.a = 0.35


## Apex Horror phaseshift end: restore full opacity (clients).
@rpc("any_peer", "call_local")
func phaseshift_end() -> void:
	if not multiplayer.is_server():
		_sprite.modulate.a = 1.0


@rpc("any_peer", "call_local", "unreliable")
func push_snapshot(pos: Vector3, hp_v: float, alive_v: bool) -> void:
	_remote_pos = pos
	_has_remote = true
	hp = hp_v
	if alive and not alive_v:
		_play_death()
	alive = alive_v


@rpc("any_peer", "call_local")
func take_damage(amount: float, attacker: int, attacker_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if not alive:
		return
	# Phaseshift: the apex Horror is untargetable during its 2s window.
	if untargetable:
		return
	# Marked targets take +50% damage.
	if _mark_t > 0.0:
		amount *= 1.5
	# True Aim trait: attacker's +10% damage vs marked or revealed targets.
	if _mark_t > 0.0 or _xray:
		for n in get_tree().get_nodes_in_group("players"):
			var pl := n as Player
			if pl != null and pl.get_multiplayer_authority() == attacker and pl.has_trait("true_aim"):
				amount *= 1.1
				break
	# Shattered (slowed) targets take +25% damage.
	if _shatter_t > 0.0:
		amount *= 1.25
		# Brittle (frost trait): slowed enemies take +15% more (team-wide).
		for n in get_tree().get_nodes_in_group("players"):
			var pl := n as Player
			if pl != null and pl.has_trait("brittle"):
				amount *= 1.15
				break
	# Doom Totem (Conqueror signature): +30% damage from all sources.
	if doom_t > 0.0:
		amount *= 1.3
	hp -= amount
	# Credit run stats: the attacking player tracks total damage dealt.
	# Covers every source (melee, spells, projectiles, totems) in one place.
	for n in get_tree().get_nodes_in_group("players"):
		var pl := n as Player
		if pl != null and pl.get_multiplayer_authority() == attacker:
			pl.run_damage_dealt += amount
			break
	# Hit feedback, seen by everyone.
	var away: Vector3 = global_position - attacker_pos
	away.y = 0.0
	if away.length() > 0.01:
		_knockback = away.normalized() * 6.0
	rpc("hit_react", global_position, amount, attacker)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		rpc("play_death")
		_drop_and_reward(attacker)
		# Track kills for achievements (server-side).
		if multiplayer.is_server():
			SaveManager.add_kills(1)
			var new_unlocks: Array = SaveManager.check_achievements()
			if not new_unlocks.is_empty():
				# Notify the killer.
				for p in get_tree().get_nodes_in_group("players"):
					if int(p.get_multiplayer_authority()) == attacker:
						p.rpc_id(attacker, "show_achievement_unlock", new_unlocks)
	if alive:
		_check_apex_triggers()


@rpc("any_peer", "call_local")
func hit_react(pos: Vector3, amount: float, attacker: int) -> void:
	if not alive:
		return
	AudioManager.sfx("hit", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(1.0, 0.8, 0.25), 12, 5.0)
	Effects.damage_number(get_parent(), pos, amount)
	# Hitmarker for the player who landed the hit.
	if attacker == multiplayer.get_unique_id():
		var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
		if dungeon != null:
			var pn := dungeon.get_player_node(attacker)
			var hud = pn.get("hud") if pn != null else null
			if hud != null and hud.has_method("show_hitmarker"):
				hud.show_hitmarker()
	# Red flash + squash-and-stretch.
	_sprite.modulate = Color(1.0, 0.35, 0.35)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "modulate", Color.WHITE, 0.18)
	_sprite.scale = _base_scale * Vector3(1.18, 0.82, 1.18)
	var squash := create_tween()
	squash.tween_property(_sprite, "scale", _base_scale, 0.22).set_trans(Tween.TRANS_BACK)


@rpc("any_peer", "call_local")
func play_death() -> void:
	_play_death()


func _play_death() -> void:
	alive = false
	remove_from_group("mobs")
	if data.is_boss:
		AudioManager.sfx("boss_die", global_position)
		Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(1.0, 0.75, 0.25), 60, 8.0)
		Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.8, 0.15, 0.1), 40, 6.0)
		var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
		if dungeon != null:
			dungeon.rpc("announce", "%s SLAIN!" % data.boss_title.to_upper())
	else:
		AudioManager.sfx("mob_die", global_position)
		Effects.burst(get_parent(), global_position + Vector3(0, 0.8, 0), Color(0.5, 0.1, 0.1), 22, 4.5)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.6)
	tween.tween_property(_sprite, "scale", _base_scale * Vector3(1.3, 0.4, 1.3), 0.5)
	tween.chain().tween_callback(queue_free)


func _drop_and_reward(attacker: int) -> void:
	# Untyped dungeon ref (like the apex paths): lets test stubs stand in.
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return
	var player_node: Node = dungeon.get_player_node(attacker)
	if player_node != null:
		# Danger model: XP scales with tier × depth (never less than 1).
		player_node.rpc_id(attacker, "gain_xp", maxi(1, roundi(float(data.xp_reward) * reward_scale)))
		# Bounty Board (issue #7): server-side kill tracking per player.
		if multiplayer.is_server():
			dungeon.notify_bounty_kill(attacker, data.id, is_elite)
		# Affinity: marked target killed → +3 mark.
		if is_marked():
			player_node.rpc_id(attacker, "notify_mark_kill")
	if data.drops.is_empty():
		return
	# 1 + bonus_drops rolls. Luck shifts weight toward rarer items, so
	# tougher mobs and bosses naturally drop better loot.
	# Potions only drop in Village Outskirts.
	# Meta-locked items only drop if unlocked.
	var theme_id := ""
	var theme_res = dungeon.get("theme")
	if theme_res != null:
		theme_id = str(theme_res.get("theme_id"))
	var is_village := theme_id == "village"
	var rolls := 1 + data.bonus_drops
	for r in rolls:
		if randf() > data.drop_chance * NetworkManager.host_loot_mult:
			continue
		var total := 0.0
		for d in data.drops:
			if not is_village and _is_potion(d.item.id):
				continue
			if d.item.meta_locked and not SaveManager.is_item_unlocked(d.item.id):
				continue
			total += d.weight * _luck_weight(d.item.rarity)
		if total <= 0.0:
			continue
		var roll := randf() * total
		for d in data.drops:
			if not is_village and _is_potion(d.item.id):
				continue
			if d.item.meta_locked and not SaveManager.is_item_unlocked(d.item.id):
				continue
			roll -= d.weight * _luck_weight(d.item.rarity)
			if roll <= 0.0:
				dungeon.rpc("spawn_pickup", d.item.id, global_position + Vector3(0, 0.8, 0), reward_scale)
				break
	# Meta items from elites/bosses.
	_try_meta_drop(dungeon)
	# Apex relic (issue #5 Phase 3): the apex boss ALWAYS drops its relic,
	# outside the weighted pool — a 100% forced drop, not a table entry.
	if data.apex_id != "":
		var relic_id := SpecialData.relic_item_for_apex(data.id)
		if relic_id != "":
			dungeon.rpc("spawn_pickup", relic_id, global_position + Vector3(0, 0.8, 0), 1.0)


## Potion/consumable item IDs (village-only drops).
func _is_potion(item_id: String) -> bool:
	return item_id in ["health_potion", "swift_potion", "power_elixir"]


## Meta-unlocked items can drop from elites and bosses once unlocked.
func _try_meta_drop(dungeon) -> void:
	if not (data.is_boss or is_elite):
		return
	var unlocked := SaveManager.get_unlocked_items()
	if unlocked.is_empty():
		return
	# 15% chance for bosses, 5% for elites.
	var chance := 0.15 if data.is_boss else 0.05
	if randf() > chance:
		return
	var item_id: String = unlocked[randi() % unlocked.size()]
	dungeon.rpc("spawn_pickup", item_id, global_position + Vector3(0, 0.8, 0), reward_scale)


## Higher luck multiplies the weight of rarer items (rarity 0..4).
func _luck_weight(rarity: int) -> float:
	var luck := data.loot_luck + (1.5 if is_elite else 0.0)
	return 1.0 + luck * float(rarity) * 0.4
