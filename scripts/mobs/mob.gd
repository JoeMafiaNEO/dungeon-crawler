class_name Mob
extends CharacterBody3D
## Server-authoritative monster with a billboarded 2D sprite.
## The host simulates AI and health; snapshots keep remote peers in sync.

const GRAVITY := 20.0
## Issue #113 Phase 1: masterwork kit drop chances for _try_masterwork_drop.
## PLACEHOLDERS (Jesse tunes balance).
const MASTERWORK_DROP_CHANCE_BOSS := 0.25
const MASTERWORK_DROP_CHANCE_ELITE := 0.10

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
## Issue #148: shoot-cycle state (mobs with shoot_frames data — the
## goblin archer). _draw_t counts the wind-up down to the loose;
## _follow_t is the release frame's follow-through (presentation
## only). Frame times are the Art Director's table: the first four
## sum to the 1.25s wind-up; the arrow leaves when frame 5 activates.
const SHOOT_FRAME_TIMES: Array[float] = [0.30, 0.25, 0.25, 0.45, 0.65]
const SHOOT_WINDUP := 1.25
var _draw_t := 0.0
var _follow_t := 0.0
var _shoot_playing := false
var _snapshot := 0.0
var _retarget := 0.0
var _remote_pos := Vector3.ZERO
var _has_remote := false
var _knockback := Vector3.ZERO
var _sprite: AnimatedSprite3D
## Jesse 2026-10-11: floating health bar (single dynamic texture).
var _hb_fill: Sprite3D = null
var _hb_full_w: float = 1.0
var _hb_bar_h: float = 0.22
var _hb_image: Image = null
var _hb_tex: ImageTexture = null
var _hb_img_w: int = 200
var _hb_img_h: int = 22
var _flash_tween: Tween
var _bob_t := 0.0
var _base_scale := Vector3.ONE
## Shieldbearer (issue #67): frontal block state machine (server-authoritative).
## _shield_up: shield is raised (blocks frontal). _shield_drop_t: timer for
## windup opening (0.9s). _stagger_t: timer for flank stagger (1.5s).
var _shield_up := true
var _shield_drop_t := 0.0
var _stagger_t := 0.0
var _shield_visual: Node3D
## Shieldbearer windup: 0.9s opening where shield is down before the strike.
var _windup_t := 0.0
## Elite mobs: 2.5x HP, 1.25x size, +1.5 loot luck, gold nameplate.
var is_elite := false
## Champion (Jesse 2026-10-10): second upgrade tier above elite — 4x HP,
## +25% damage, purple label.
var is_champion := false
## Slow debuff (frost): _slow_t seconds remaining at _slow_mult speed.
var _slow_t := 0.0
var _slow_mult := 1.0
## Issue #210 Amendment 1 (Brittle Ice): the shatter value
## Glacial Prison stores on each mob it freezes. Zero for
## every non-owner's game — the field is never read for
## effect at zero.
var prison_shatter := 0.0
var prison_shatter_owner := 0
## Issue #210 Amendment 1 (Arcing Brand): the branded
## status — a storm caster's mark. Reapplication takes the
## stronger amp and refreshes (the apply_burn precedent).
var _brand_amp := 0.0
var _brand_until := 0
var _brand_owner := 0
## Stun (issue #113 Phase 4, Hammer Smash): while _stun_t > 0 the mob
## cannot move or attack. Server-side state, mirroring the slow pattern;
## boss special-think is NOT paused (movement/basic attacks only).
var _stun_t := 0.0
## Smoke Bombard (combo finisher): blinded mobs miss 50% of attacks.
var _blind_t := 0.0
## Shatter: slowed enemies take +25% damage (mage opens windows for team).
var _shatter_t := 0.0
## Burn (wildfire trait): damage over time.
var _burn_t := 0.0
var _burn_dps := 0.0
var _burn_attacker := 0
var _burn_tick := 0.0
## Gravewarden (issue #67 Phase 3): support aura tick (0.5s server-side).
var _aura_tick := 0.0
var _aura_ring: MeshInstance3D
## Gravewarden buff: damage multiplier from ally aura (ticks down).
var _support_dmg_t := 0.0
var _support_dmg_mult := 1.0
## Relentless (Conqueror trait): while bulwark-slowed, this mob deals -10% damage.
var bulwark_slow_t := 0.0
## Doom Totem (Conqueror signature): mob takes +30% damage from all sources.
var doom_t := 0.0
## Issue #210 (section 2.4): the doom magnitude stored by
## the refreshing totem (the caster's vuln_pct fold);
## 0.30 is the shipped base value.
var doom_vuln := 0.30
## Issue #173: status-effect rings (presentation ONLY — no
## gameplay state lives here). A server-computed status_mask
## rides the mob snapshot; each replica renders one ground
## ring per active effect in a CANONICAL slot (the slot never
## changes while effects come and go, so radius alone
## identifies the effect). Bits, in slot order:
const STATUS_SLOW := 1
const STATUS_STUN := 2
const STATUS_BLIND := 4
const STATUS_BURN := 8
const STATUS_MARK := 16
const STATUS_DOOM := 32
## Jesse-approved colors (2026-10-17), alpha ~0.55: Slow ice
## cyan #6FD3FF, Stun bright yellow #FFD94A, Blind smoky
## gray-violet #9A8FB0, Burn ember orange #FF7A33, Mark
## crimson #FF5A6E, Doom deep purple #8B4DFF.
const STATUS_COLORS: Array = [
	Color8(0x6F, 0xD3, 0xFF, 140), Color8(0xFF, 0xD9, 0x4A, 140),
	Color8(0x9A, 0x8F, 0xB0, 140), Color8(0xFF, 0x7A, 0x33, 140),
	Color8(0xFF, 0x5A, 0x6E, 140), Color8(0x8B, 0x4D, 0xFF, 140),
]
## Shared rendering assets (built once): ONE annulus mesh and
## SIX materials serve every mob in the world. (The motes'
## process materials + draw quads are likewise shared per
## color, cached by their factory in effects.gd.)
static var _status_mesh: Mesh = null
static var _status_mats: Array = []
## The lazy rings container (null until the first non-zero
## mask) and the mask it currently renders.
var _status_rings: Node3D = null
var _status_mask_applied := 0
# --- Boss state ---
var _special_cd := 4.0
var _telegraph := 0.0
var _pending_special := ""
var _charge_t := 0.0
var _charge_dir := Vector3.ZERO
var _charge_hit: Array = []
## Frenzy override: charge this target instead of _target (farthest player).
var _charge_target: Node3D = null
## Second boss special (special_id_2): own cooldown, shares the telegraph slot.
var _special2_cd := 10.0
## Third/fourth specials (HP-gated): own cooldowns, share the telegraph slot.
var _special3_cd := 14.0
var _special4_cd := 18.0
## Blood Frenzy (Boar): latched below 30% HP.
var _frenzied := false
var _frenzy_charge_cd := 0.0
## Soft enrage: fight timer; +1 stack per 30s after 180s.
var _fight_t := 0.0
var _enrage_stacks := 0
## Gilded Cage (Warden): trapped player + cage mob + expiry timer.
var _cage_target: Node3D = null
var _cage_mob: Node3D = null
var _cage_t := 0.0
## Mud Wall: sequence counter for deterministic mound UIDs.
var _mound_seq := 0
## Judgment (Warden): [{positions: Array[Vector3], timer: float}] awaiting eruption.
var _pending_judgments: Array = []
## Void rifts (Horror): [{pos: Vector3, ticks: int, tick_t: float, batch: int}].
var _rifts: Array = []
var _rift_batch := 0
## Client-side rift visuals: batch id -> Array[Node3D]. Built from rift_spawn RPC.
var _rift_nodes := {}
## Issue #127: pulse-claim timestamps per rift disc (instance id ->
## msec) — see rift_pulse_fx's round-claim discipline.
var _rift_disc_claimed := {}
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


func setup(p_id: int, p_data: MobData, p_hp_scale: float = 1.0, p_dmg_scale: float = 1.0, p_elite: bool = false, p_reward_scale: float = 1.0, p_champion: bool = false) -> void:
	mob_id = p_id
	data = p_data
	hp_scale = p_hp_scale
	dmg_scale = p_dmg_scale
	reward_scale = p_reward_scale
	is_elite = p_elite and not p_data.is_boss
	is_champion = p_champion and not p_data.is_boss
	# Stagger the second boss special off the first so they don't sync up.
	_special2_cd = data.special_cooldown_2 * 0.7
	if is_champion:
		hp_scale *= 4.0
		dmg_scale *= 1.25
	elif is_elite:
		hp_scale *= 2.5
	# Shieldbearer (issue #67, #82 Phase 2): tower-shield overlay.
	# Visible when shield is up. Art Director's .glb (1.2m x 1.6m,
	# centered pivot, front-facing +Z).
	if data.frontal_block:
		var shield_scene: PackedScene = load("res://assets/models/shieldbearer_tower_shield.glb")
		_shield_visual = shield_scene.instantiate()
		_shield_visual.name = "ShieldOverlay"
		_shield_visual.position = Vector3(0, 1.0, 0.35)
		add_child(_shield_visual)
		_shield_up = true
	# Gravewarden (issue #67 Phase 3): pulsing gold-green aura ring.
	# Reuses totem ring visual style.
	if data.support_aura_radius > 0.0:
		_aura_ring = MeshInstance3D.new()
		_aura_ring.name = "SupportAuraRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = data.support_aura_radius - 0.3
		ring_mesh.outer_radius = data.support_aura_radius
		_aura_ring.mesh = ring_mesh
		var ring_mat := StandardMaterial3D.new()
		ring_mat.albedo_color = Color(0.8, 0.9, 0.3, 0.6)  # Gold-green.
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_aura_ring.material_override = ring_mat
		_aura_ring.position = Vector3(0, 0.1, 0)
		add_child(_aura_ring)


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
	# Issue #148: the draw-and-loose cycle as a second animation,
	# per-frame durations from the art timing table, no loop — the
	# last frame (release) holds until the snapshot flag clears.
	if not data.shoot_frames.is_empty():
		frames.add_animation("shoot")
		for i in data.shoot_frames.size():
			var dur := SHOOT_FRAME_TIMES[i] if i < SHOOT_FRAME_TIMES.size() else 1.0
			frames.add_frame("shoot", data.shoot_frames[i], dur)
		frames.set_animation_speed("shoot", 1.0)
		frames.set_animation_loop("shoot", false)
	_sprite.frames = frames
	_sprite.play("default")
	if data.is_boss:
		$Label3D.text = data.boss_title
		$Label3D.font_size = 64
		$Label3D.modulate = Color(1.0, 0.45, 0.4)
		_base_scale = Vector3.ONE * data.scale_mult
	elif is_champion:
		$Label3D.text = "Champion " + data.display_name
		$Label3D.modulate = Color(0.75, 0.4, 1.0)
		_base_scale = Vector3.ONE * 1.4
	elif is_elite:
		$Label3D.text = "Elite " + data.display_name
		$Label3D.modulate = Color(1.0, 0.85, 0.3)
		_base_scale = Vector3.ONE * 1.25
	else:
		$Label3D.text = data.display_name
	# Flat data tint (e.g. dread mirrors render purple).
	if data.tint != Color.WHITE:
		_sprite.modulate = data.tint
	# Gilded Cage: gold dome mesh over the sprite.
	if data.id == "gold_cage":
		_build_cage_dome()
	# Jesse 2026-10-11: floating health bar above the mob.
	_build_health_bar()
	_sprite.scale = _base_scale
	_remote_pos = global_position
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not alive:
		return
	# Shieldbearer (issue #67): stagger timer ticks down; shield raises when done.
	if _stagger_t > 0.0:
		_stagger_t -= delta
		if _stagger_t <= 0.0:
			_stagger_t = 0.0
			_shield_up = true
			_update_shield_visual()
	# Slow debuff ticks down (server-side).
	if _slow_t > 0.0:
		_slow_t -= delta
		if _slow_t <= 0.0:
			_slow_mult = 1.0
			_sprite.modulate = Color.WHITE
	# Stun ticks down (server-side).
	if _stun_t > 0.0:
		_stun_t -= delta
	# Blind debuff ticks down (server-side).
	if _blind_t > 0.0:
		_blind_t -= delta
	# Gravewarden (issue #67 Phase 3): 0.5s server tick heals/buffs allies (not self).
	if data.support_aura_radius > 0.0 and multiplayer.is_server():
		_aura_tick += delta
		if _aura_tick >= 0.5:
			_aura_tick = 0.0
			_support_tick()
	# Support damage buff ticks down.
	if _support_dmg_t > 0.0:
		_support_dmg_t -= delta
		if _support_dmg_t <= 0.0:
			_support_dmg_mult = 1.0
	# Gravewarden aura ring pulses (visual only, all peers).
	if _aura_ring != null and is_instance_valid(_aura_ring):
		var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
		_aura_ring.scale = Vector3(pulse, 1.0, pulse)
	# Issue #82 Phase 2: shield yaws with the sprite. The mob root never
	# rotates — only _sprite does — so mirror its yaw onto the shield.
	if _shield_visual != null and is_instance_valid(_shield_visual) and _sprite != null:
		_shield_visual.rotation.y = _sprite.rotation.y
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
	# Stunned mobs skip the move/attack block entirely (the elif below
	# zeroes their velocity); boss specials above still cadence.
	if not boss_busy and _stun_t <= 0.0 and _target != null and is_instance_valid(_target):
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
			# Shieldbearer windup: 0.9s opening (shield down) before the strike.
			if _windup_t > 0.0:
				_windup_t -= delta
				if _windup_t <= 0.0:
					_windup_t = 0.0
					_do_attack()
					# Shield raises after the strike (unless staggered).
					if _stagger_t <= 0.0:
						_shield_up = true
			elif _attack_cd <= 0.0:
				_attack_cd = data.attack_cooldown
				if data.frontal_block and _shield_up:
					# Start windup: shield drops for 0.9s (the opening).
					_windup_t = 0.9
					_shield_up = false
					_update_shield_visual()
				else:
					_do_attack()
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
	if _follow_t > 0.0:
		_follow_t -= delta
	_snapshot -= delta
	if _snapshot <= 0.0:
		_snapshot = 0.15
		rpc("push_snapshot", global_position, hp, alive, _draw_t > 0.0 or _follow_t > 0.0, status_mask())


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
	var mult := 1.0
	if bulwark_slow_t > 0.0:
		mult *= 0.9
	# Gravewarden support aura buff.
	if _support_dmg_t > 0.0:
		mult *= _support_dmg_mult
	return mult


## Apex enrage: +40% movement speed below 30% HP (Bristleback).
## Blood Frenzy: +50% movement speed. Soft enrage: +10% per stack.
func _move_speed_mult() -> float:
	var m := 1.4 if _enraged else 1.0
	if _frenzied:
		m *= 1.5
	m *= pow(1.1, _enrage_stacks)
	return m


## Special cooldown: enraged apex Bristleback recharges in 4s instead of 7s.
func _special_cooldown() -> float:
	if _enraged:
		return 4.0
	# Soft enrage: each stack cuts special cooldowns 10% (multiplicative).
	return data.special_cooldown * pow(0.9, _enrage_stacks)


## Ranged attackers hold their preferred distance: back off when crowded,
## close in when too far, strafe sideways, and fire when roughly in range.
func _ranged_think(delta: float, to: Vector3, dist: float) -> void:
	var ideal := data.preferred_range
	var dir := Vector3.ZERO
	if dist > 0.01:
		dir = to / dist
	# Issue #148: a committed draw counts down here (any range — the
	# shot, once committed, looses on schedule) and fires at the
	# release moment, aimed at the target's current position.
	if _draw_t > 0.0:
		_draw_t -= delta
		if _draw_t <= 0.0:
			_draw_t = 0.0
			_follow_t = SHOOT_FRAME_TIMES[SHOOT_FRAME_TIMES.size() - 1]
			_fire_arrow(dir)
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
		if _attack_cd <= 0.0 and _draw_t <= 0.0:
			_attack_cd = data.attack_cooldown
			if data.shoot_frames.is_empty():
				_fire_arrow(dir)
			else:
				# Issue #148: commit the shot — the draw animation is
				# the wind-up/telegraph; the arrow leaves 1.25s later
				# at the release frame. The cooldown already runs
				# from the commit, so the sustained cycle (and shots
				# per minute) is unchanged — only the first arrow of
				# an engagement arrives one wind-up later.
				_draw_t = SHOOT_WINDUP


func _fire_arrow(dir: Vector3) -> void:
	if _misses():
		return  # Blinded (Smoke Bombard): the shot goes wide.
	var from := global_position + Vector3(0, 1.4, 0) + dir * 0.6
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null:
		dungeon.rpc("spawn_arrow", from, dir, data.damage * dmg_scale * _dmg_mult(), data.projectile_speed, data.display_name)
	AudioManager.sfx("bow_shot", global_position)


## Applies a slow debuff (frost). Server-side; visual tint included.
## Issue #113 Phase 4: stun (Hammer Smash). Server-side only — the
## timer lives beside the slow timer and gates movement/attacks in
## _physics_process. Re-stunning refreshes to the longer duration.
func apply_stun(duration: float) -> void:
	if not multiplayer.is_server():
		return
	if not alive:
		return
	_stun_t = maxf(_stun_t, duration)


func is_stunned() -> bool:
	return _stun_t > 0.0


## Issue #210 (Choking Veil): apply_slow is server-context
## only; this is its RPC route for owner-local casts, in
## the apply_mark pattern. Claimed-value discipline (the
## request_chain_lightning posture): only the server
## executes, and the claimed values are sanity-clamped
## server-side — a slow's duration lives in [0, 15] s and
## its multiplier in [0, 1].
@rpc("any_peer", "call_local")
func rpc_apply_slow(duration: float, mult: float) -> void:
	if not multiplayer.is_server():
		return
	apply_slow(clampf(duration, 0.0, 15.0),
		clampf(mult, 0.0, 1.0))


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


## Issue #210 Amendment 1: brand this mob for `duration`
## seconds at `amp` (a damage fraction, e.g. 0.2 = +20%).
func apply_brand(duration: float, amp: float,
		attacker: int) -> void:
	if not alive:
		return
	if not multiplayer.is_server():
		return
	var now := Time.get_ticks_msec()
	_brand_amp = maxf(_brand_amp, amp) \
		if now < _brand_until else amp
	_brand_until = now + int(duration * 1000.0)
	_brand_owner = attacker


## The stored brand amp while the window is live, else 0.
func brand_amp_now() -> float:
	if Time.get_ticks_msec() < _brand_until:
		return _brand_amp
	return 0.0


## Applies blind (Smoke Bombard): the mob misses 50% of attacks while blind.
func apply_blind(duration: float) -> void:
	if not alive:
		return
	_blind_t = maxf(_blind_t, duration)


## Blind miss roll, checked at each attack site (server-side).
func _misses() -> bool:
	return _blind_t > 0.0 and randf() < 0.5


## Execute the melee attack (extracted for Shieldbearer windup).
func _do_attack() -> void:
	if _misses():
		pass  # Blinded (Smoke Bombard): the swing misses.
	elif _target.is_in_group("decoys"):
		# Shadow decoy: direct damage, server-side (no RPC target).
		_target.damage(data.damage * dmg_scale * _dmg_mult())
	elif _target.is_in_group("structures"):
		# Architect structure: direct damage, server-side (no RPC target).
		_target.take_structure_damage(data.damage * dmg_scale * _dmg_mult(), NetworkManager.server_peer_id)
	else:
		_target.rpc_id(_target.get_multiplayer_authority(), "take_damage", data.damage * dmg_scale * _dmg_mult(), data.display_name)


## Gravewarden (issue #67 Phase 3): 0.5s server tick.
## Heals and buffs allies in support_aura_radius (not itself).
func _support_tick() -> void:
	if not alive:
		return
	for n in get_tree().get_nodes_in_group("mobs"):
		var ally := n as Mob
		if ally == null or ally == self or not ally.alive:
			continue
		var dist: float = global_position.distance_to(ally.global_position)
		if dist <= data.support_aura_radius:
			# Heal (0.5s worth).
			ally.hp = minf(ally.hp + data.support_heal_ps * 0.5, ally.max_hp)
			# Damage buff: refresh timer.
			ally._support_dmg_t = 0.6
			ally._support_dmg_mult = data.support_dmg_mult


## Shieldbearer (issue #67): update the tower-shield overlay visibility.
## Shield up = visible (blocking); shield down = hidden (opening/stagger).
func _update_shield_visual() -> void:
	if _shield_visual != null and is_instance_valid(_shield_visual):
		_shield_visual.visible = _shield_up
	# Sync to clients.


## Gilded Cage: translucent gold dome mesh (2.5m radius) over the mob.
func _build_cage_dome() -> void:
	var dome := SphereMesh.new()
	dome.radius = 2.5
	dome.height = 5.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.25, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 1.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = dome
	add_child(mi)
	mi.position.y = 1.2
	if multiplayer.is_server():
		rpc("_sync_shield", _shield_up)


@rpc("any_peer", "call_local")
func _sync_shield(up: bool) -> void:
	_shield_up = up
	if _shield_visual != null and is_instance_valid(_shield_visual):
		_shield_visual.visible = up


## Shieldbearer (issue #67): clang + spark on frontal block (all peers).
@rpc("any_peer", "call_local")
func shield_clang(pos: Vector3) -> void:
	# TODO: Art — spark particles at pos.
	AudioManager.sfx("shield_clang", pos)


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
		# Issue #189 (section 3): kill-decision site 2 of 2 —
		# burn kills skip _drop_and_reward entirely, so the
		# marker notification hooks HERE, not the reward path.
		_notify_marked_death()
		# Issue #210: kill-decision site 2 of 2 for Coup de
		# Grâce (checked for symmetry; see _notify_coup).
		_notify_coup(_burn_attacker)
		_notify_tree_kill(_burn_attacker)


## Issue #189 (section 3): tell the MARKER's player that
## their marked target died. Server-only, fires once per death
## from the two kill-decision sites (take_damage's death
## block and _take_burn_tick's) — _play_death is per-peer
## presentation and is NOT a hook site. Distinct from
## _drop_and_reward's notify_mark_kill, which addresses the
## KILLER for affinity; this one addresses the marker.
func _notify_marked_death() -> void:
	if not multiplayer.is_server():
		return
	if _marked_by_peer == 0 or not is_marked():
		return
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null or not dungeon.has_method("get_player_node"):
		return
	var marker = dungeon.get_player_node(_marked_by_peer)
	if marker == null or not marker.has_method("notify_marked_target_died"):
		return
	if _marked_by_peer == int(multiplayer.get_unique_id()):
		marker.notify_marked_target_died()
	else:
		marker.rpc_id(_marked_by_peer, "notify_marked_target_died")


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

## Issue #210 (section 2.6, the spec's one API extension):
## the marking caster's Deep Tree vuln_add, stored on the
## mark at application time (the caster's aggregate THEN,
## never re-read from a possibly-changed build) and added
## to the 1.5 amplification at the damage read. A re-mark
## overwrites it — the last applier owns the mark.
var _mark_vuln_add := 0.0

## Issue #189 (section 1): the permanent mark — the cast passes
## this in place of a duration. INF lives in the existing
## _mark_t: every consumer (damage +50%, True Aim, the status
## mask, turret preference, dagger synergy, Orbital keying)
## reads only positivity, so nothing migrates — the mark ends
## only when the mob dies.
const MARK_PERMANENT := INF

## Issue #189 (section 3): who marked this mob (peer id),
## recorded server-side in apply_mark; the LAST applier owns
## it. 0 = unmarked. The mob's death notifies THIS peer's
## player (the marker), never the killer.
var _marked_by_peer := 0

## Issue #210 (Coup de Grâce): the peer whose Assassinate
## strike is currently being applied (see assassinate_hit)
## — set only for the duration of that one damage call, so
## the kill-decision sites can attribute the kill exactly.
var _coup_from := 0


## The Assassinate strike's damage route: identical damage
## discipline to a direct take_damage call, with the strike
## tagged for the duration of the call.
@rpc("any_peer", "call_local")
func assassinate_hit(amount: float, attacker: int,
		attacker_pos: Vector3) -> void:
	_coup_from = attacker
	take_damage(amount, attacker, attacker_pos)
	_coup_from = 0


## Issue #210: tell the Assassinate striker's player that
## their strike killed (Coup de Grâce). Mirrors
## _notify_marked_death's addressing; fires from the two
## kill-decision sites when the killing source carries the
## strike tag (the burn site is checked for symmetry — a
## burn tick never carries the tag, whose lifetime is one
## take_damage call, so in practice the strike's own site
## is the one that fires).
## Issue #210 slice B5 (spec section 3): Adrenaline kill
## credit — the general form of the coup notification,
## fired at BOTH death sites for the credited killer.
func _notify_tree_kill(killer: int) -> void:
	if not multiplayer.is_server() or killer == 0:
		return
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null or not dungeon.has_method("get_player_node"):
		return
	var striker = dungeon.get_player_node(killer)
	if striker == null or not striker.has_method("notify_tree_kill"):
		return
	if killer == int(multiplayer.get_unique_id()):
		striker.notify_tree_kill()
	else:
		striker.rpc_id(killer, "notify_tree_kill")


func _notify_coup(killer: int) -> void:
	if not multiplayer.is_server():
		return
	if _coup_from == 0 or _coup_from != killer:
		return
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null or not dungeon.has_method("get_player_node"):
		return
	var striker = dungeon.get_player_node(_coup_from)
	if striker == null or not striker.has_method("notify_coup_kill"):
		return
	if _coup_from == int(multiplayer.get_unique_id()):
		striker.notify_coup_kill()
	else:
		striker.rpc_id(_coup_from, "notify_coup_kill")


func is_marked() -> bool:
	return _mark_t > 0.0


@rpc("any_peer", "call_local")
func apply_mark(duration: float, slow_mult: float = 1.0,
		vuln_add: float = 0.0) -> void:
	_mark_t = duration
	_mark_vuln_add = vuln_add
	# Issue #189 (section 3): record the marker on the server
	# (sender resolution, house pattern; a local server cast
	# reports sender 0 -> the server's own id). A re-mark
	# overwrites: the last applier owns the death refresh.
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		_marked_by_peer = sender if sender != 0 else int(multiplayer.get_unique_id())
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
	# Pending Judgment eruptions and active void rifts tick independently of
	# whatever the boss is doing (telegraphing, charging, phaseshifting).
	if not _pending_judgments.is_empty():
		_process_judgments(delta)
	if not _rifts.is_empty():
		_process_rifts(delta)
	# Soft enrage: after 180s, +1 stack per 30s (10% faster specials, 10% speed).
	if data.is_boss:
		_fight_t += delta
		if _fight_t >= 180.0:
			var want := int((_fight_t - 180.0) / 30.0) + 1
			if want > _enrage_stacks:
				_enrage_stacks = want
				rpc("enrage_stack_fx", global_position, _enrage_stacks)
	# Blood Frenzy (Boar): latch below 30% HP.
	if data.is_boss and not _frenzied and data.special_id_2 == "seismic_slam" \
			and max_hp > 0.0 and hp / max_hp <= 0.30:
		_frenzied = true
		_frenzy_charge_cd = 2.0
		rpc("frenzy_fx", global_position)
	# Gilded cage: expiry timer, plus break detection (teammates kill the dome).
	if _cage_t > 0.0:
		_cage_t -= delta
		var cage_alive := false
		if _cage_target != null and is_instance_valid(_cage_target):
			for m in get_tree().get_nodes_in_group("mobs"):
				var mm := m as Node3D
				if mm != null and mm.get("alive") != false \
						and str(mm.get("data").get("id")) == "gold_cage" \
						and mm.global_position.distance_to(_cage_target.global_position) < 4.0:
					cage_alive = true
					break
		if not cage_alive:
			_break_cage(true)
		elif _cage_t <= 0.0:
			_break_cage(false)
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
		# Blood Frenzy: same trail while frenzied.
		if data.apex_id == "enrage" or _frenzied:
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
	# Second boss special (special_id_2): own cooldown, shares the telegraph.
	_special2_cd -= delta
	if _special2_cd <= 0.0 and _target != null and is_instance_valid(_target):
		match data.special_id_2:
			"seismic_slam":
				_begin_telegraph("seismic_slam", 1.0)
				return true
			"judgment":
				_begin_telegraph("judgment", 1.2)
				return true
			"void_rift":
				_begin_telegraph("void_rift", 0.8)
				return true
	# Blood Frenzy: every 6s, charge the FARTHEST player.
	if _frenzied:
		_frenzy_charge_cd -= delta
		if _frenzy_charge_cd <= 0.0:
			_frenzy_charge_cd = 6.0
			var far: Node3D = null
			var far_d := 0.0
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Node3D
				if p == null or p.get("alive") == false:
					continue
				var d: float = global_position.distance_to(p.global_position)
				if d > far_d:
					far_d = d
					far = p
			if far != null and far_d > 4.0:
				_charge_target = far
				_begin_telegraph("charge", 0.6)
				return true
	# Third/fourth specials: HP-gated phase thresholds.
	var frac := 1.0
	if max_hp > 0.0:
		frac = hp / max_hp
	_special3_cd -= delta
	if _special3_cd <= 0.0 and not data.special_id_3.is_empty() \
			and frac <= data.special_hp_gate_3 \
			and _target != null and is_instance_valid(_target):
		_begin_telegraph(data.special_id_3, 1.0)
		return true
	_special4_cd -= delta
	if _special4_cd <= 0.0 and not data.special_id_4.is_empty() \
			and frac <= data.special_hp_gate_4 \
			and _target != null and is_instance_valid(_target):
		# Jesse 2026-10-11: gilded cage needs at least 2 players.
		if data.special_id_4 == "gilded_cage":
			var alive := 0
			for n in get_tree().get_nodes_in_group("players"):
				if n.get("alive") != false:
					alive += 1
			if alive < 2:
				return false
		_begin_telegraph(data.special_id_4, 1.0)
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
		"seismic_slam":
			_special2_cd = data.special_cooldown_2
			_do_seismic_slam()
		"judgment":
			_special2_cd = data.special_cooldown_2
			_do_judgment()
		"void_rift":
			_special2_cd = data.special_cooldown_2
			_do_void_rift()
		"mud_wall":
			_special3_cd = data.special_cooldown_3
			_do_mud_wall()
		"aegis_phalanx":
			_special3_cd = data.special_cooldown_3
			_do_aegis_phalanx()
		"dread_mirror":
			_special3_cd = data.special_cooldown_3
			_do_dread_mirror()
		"gilded_cage":
			_special4_cd = data.special_cooldown_4
			_do_gilded_cage()
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
	var base_dmg := data.damage * data.special_damage_mult * dmg_scale * _dmg_mult()
	var done: Array = []
	for w in _shockwaves:
		w["radius"] = float(w["radius"]) + float(w["speed"]) * delta
		var dmg: float = float(w.get("dmg", base_dmg))
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


## --- Boss second specials (special_id_2). Server-side only; visuals fan out
## via any_peer call_local RPCs. Damage always goes through the victim's
## multiplayer authority (take_damage), never through RPC authority mode. ---

## Boar: seismic slam — a bigger, slower shockwave than the Warden's.
## 12m at 6 m/s, 1.5x special damage. Dodge by outrunning the ring.
func _do_seismic_slam() -> void:
	rpc("seismic_fx", global_position)
	if _misses():
		return  # Blinded (Smoke Bombard): the slam misses.
	var dmg := data.damage * data.special_damage_mult * 1.5 * dmg_scale * _dmg_mult()
	_shockwaves.append({"radius": 1.0, "max_radius": 12.0, "speed": 6.0,
		"hit": [], "dmg": dmg})


## Warden: judgment — up to 3 living players are marked with gold rings;
## after 1.2s holy pillars erupt at the marked spots (3m radius each).
func _do_judgment() -> void:
	var positions: Array = []
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p == null or p.get("alive") == false:
			continue
		positions.append(p.global_position)
		if positions.size() >= 3:
			break
	if positions.is_empty():
		return
	rpc("judgment_telegraph", positions)
	_pending_judgments.append({"positions": positions, "timer": 1.2})


func _process_judgments(delta: float) -> void:
	var base_dmg := data.damage * data.special_damage_mult * dmg_scale * _dmg_mult()
	var done: Array = []
	for j in _pending_judgments:
		j["timer"] = float(j["timer"]) - delta
		if float(j["timer"]) > 0.0:
			continue
		done.append(j)
		var positions: Array = j["positions"]
		var dmg: float = base_dmg * float(j.get("dmg_mult", 1.0))
		var radius: float = float(j.get("radius", 3.0))
		var is_storm: bool = bool(j.get("storm", false))
		if is_storm:
			rpc("afterimage_fx", positions[0])
		else:
			rpc("judgment_fx", positions)
		if _misses():
			continue
		for pos in positions:
			var pv: Vector3 = pos
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Node3D
				if p == null or p.get("alive") == false:
					continue
				if pv.distance_to(p.global_position) <= radius:
					p.rpc_id(p.get_multiplayer_authority(), "take_damage", dmg, data.display_name)
	for j in done:
		_pending_judgments.erase(j)


## Issue #127: void-rift grounding (the #120 flat-y FX family).
## Samples the dungeon's ground height at a position; with no
## dungeon (bare test trees) or no sampler on it, returns the
## fallback — the pre-fix value at each call site. (The lookup
## takes the first dungeon-group node WITH the sampler: the one
## real dungeon always has it; bare stand-ins without it must not
## shadow it.)
func _rift_ground_y(pos: Vector3, fallback: float) -> float:
	for n in get_tree().get_nodes_in_group("dungeon"):
		if n.has_method("ground_height_at"):
			return float(n.call("ground_height_at", pos))
	return fallback


## Horror: void rifts — 3 zones spawn near random players, drift toward the
## nearest living player at 1.2 m/s, and pulse every second for 15s
## (2.5m radius, 0.5x special damage per pulse).
func _do_void_rift() -> void:
	var players: Array = []
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p != null and p.get("alive") != false:
			players.append(p)
	if players.is_empty():
		return
	var positions: Array = []
	for i in 3:
		var p: Node3D = players[randi() % players.size()]
		var pos: Vector3 = p.global_position + Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
		# Issue #127: ground the spawn anchor (the ±3m offset can
		# cross relief even though the player anchor is grounded).
		pos.y = _rift_ground_y(pos, pos.y)
		positions.append(pos)
	_rift_batch += 1
	rpc("rift_spawn", _rift_batch, positions)
	for pos in positions:
		_rifts.append({"pos": pos, "ticks": 15, "tick_t": 0.0, "batch": _rift_batch})


## Boar: mud wall — 3 destructible dirt mounds in a line facing the nearest
## player. They block movement for everyone (players and mobs).
func _do_mud_wall() -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null or _target == null or not is_instance_valid(_target):
		return
	rpc("mud_wall_fx", global_position)
	var to: Vector3 = _target.global_position - global_position
	to.y = 0.0
	var fwd := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP).normalized()
	for i in [-1, 0, 1]:
		var pos: Vector3 = global_position + fwd * 4.0 + side * (i * 3.0)
		pos.y = 0.5
		_mound_seq += 1
		var uid := "mound_%d_%d" % [mob_id, _mound_seq]
		dungeon.rpc("place_structure", "mud_mound", pos, NetworkManager.server_peer_id, 1, uid)


## Warden: aegis phalanx — 4 elite shieldbearers spawn in a line between the
## Warden and the nearest player, shields up.
func _do_aegis_phalanx() -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null or _target == null or not is_instance_valid(_target):
		return
	rpc("summon_fx", global_position)
	dungeon.rpc("announce_text", "%s RAISES THE PHALANX!" % [data.boss_title.to_upper()])
	var to: Vector3 = _target.global_position - global_position
	to.y = 0.0
	var fwd := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP).normalized()
	for i in [-1.5, -0.5, 0.5, 1.5]:
		var pos: Vector3 = global_position + fwd * 3.0 + side * (i * 2.0)
		pos.y = 0.5
		dungeon.server_spawn_mob("shieldbearer", pos, true)


## Horror: dread mirror — 2 shadow clones (purple-tinted knight sprites)
## spawn beside random players and hunt them.
func _do_dread_mirror() -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return
	var players: Array = []
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p != null and p.get("alive") != false:
			players.append(p)
	if players.is_empty():
		return
	rpc("mirror_fx", global_position)
	for i in 2:
		var p: Node3D = players[randi() % players.size()]
		var pos: Vector3 = p.global_position + Vector3(randf_range(-2.0, 2.0), 0.5, randf_range(-2.0, 2.0))
		dungeon.server_spawn_mob("dread_mirror", pos, false)


## Warden: gilded cage — the lowest-HP living player is caged: rooted inside
## a golden dome (a killable mob). Break the dome to free them; after 4s the
## dome collapses and the trapped player takes a heavy hit.
func _do_gilded_cage() -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return
	var victim: Node3D = null
	var lowest := 1e9
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p == null or p.get("alive") == false:
			continue
		var hp_frac := 1.0
		var mhp = p.get("max_hp")
		if mhp != null and float(mhp) > 0.0:
			var chp = p.get("hp")
			hp_frac = float(chp) / float(mhp) if chp != null else 1.0
		if hp_frac < lowest:
			lowest = hp_frac
			victim = p
	if victim == null:
		return
	_cage_target = victim
	_cage_t = 4.0
	dungeon.server_spawn_mob("gold_cage", victim.global_position + Vector3(0, 0.5, 0), false)
	# Track the cage mob so we know when teammates break it.
	# (server_spawn_mob is async; resolve on next think via proximity scan.)
	rpc("cage_fx", victim.global_position)
	victim.rpc_id(victim.get_multiplayer_authority(), "apply_caged", 4.0)


## Gilded cage cleanup. broken=true when teammates killed the dome.
## Server-side; visuals fan out via RPC.
func _break_cage(broken: bool) -> void:
	_cage_t = 0.0
	if _cage_target != null and is_instance_valid(_cage_target):
		_cage_target.rpc_id(_cage_target.get_multiplayer_authority(), "clear_caged")
		if not broken:
			var dmg := data.damage * data.special_damage_mult * 1.5 * dmg_scale * _dmg_mult()
			_cage_target.rpc_id(_cage_target.get_multiplayer_authority(),
				"take_damage", dmg, data.display_name)
	rpc("cage_break_fx", global_position)
	_cage_target = null
	_cage_mob = null


## Apex Horror phaseshift storm: the teleport leaves an exploding afterimage
## at the departure point (telegraphed, erupts after 1s).
func _do_phaseshift_storm(from_pos: Vector3) -> void:
	rpc("afterimage_telegraph", from_pos)
	_pending_judgments.append({"positions": [from_pos], "timer": 1.0,
		"dmg_mult": 1.5, "radius": 4.0, "storm": true})


func _process_rifts(delta: float) -> void:
	var dmg := data.damage * 0.5 * data.special_damage_mult * dmg_scale * _dmg_mult()
	var done: Array = []
	var done_batches: Array = []
	for r in _rifts:
		# Drift toward the nearest living player.
		var best: Node3D = null
		var best_d := 1e9
		for n in get_tree().get_nodes_in_group("players"):
			var p := n as Node3D
			if p == null or p.get("alive") == false:
				continue
			var d: float = (r["pos"] as Vector3).distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
		if best != null and best_d > 0.5:
			var dir: Vector3 = best.global_position - (r["pos"] as Vector3)
			dir.y = 0.0
			r["pos"] = (r["pos"] as Vector3) + dir.normalized() * 1.2 * delta
		# Issue #127: the anchor tracks the ground as the rift drifts
		# (a spawn-only fix would re-bury or float it crossing
		# relief). Flat themes sample 0.0 — the pre-fix anchor was
		# the player's spawn y, i.e. the same surface within its
		# sub-mm physics settle.
		var rp: Vector3 = r["pos"]
		rp.y = _rift_ground_y(rp, rp.y)
		r["pos"] = rp
		r["tick_t"] = float(r["tick_t"]) + delta
		if float(r["tick_t"]) >= 1.0:
			r["tick_t"] = 0.0
			r["ticks"] = int(r["ticks"]) - 1
			var pos: Vector3 = r["pos"]
			rpc("rift_pulse_fx", int(r["batch"]), pos)
			if not _misses():
				for n in get_tree().get_nodes_in_group("players"):
					var p := n as Node3D
					if p == null or p.get("alive") == false:
						continue
					if pos.distance_to(p.global_position) <= 2.5:
						p.rpc_id(p.get_multiplayer_authority(), "take_damage", dmg, data.display_name)
		if int(r["ticks"]) <= 0:
			done.append(r)
			if not done_batches.has(r["batch"]):
				done_batches.append(r["batch"])
	for r in done:
		_rifts.erase(r)
	for b in done_batches:
		rpc("rift_despawn", b)


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
					dungeon.rpc("announce_text", "%s IS ENRAGED!" % [data.boss_title.to_upper()])
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
	dungeon.rpc("announce_text", "%s CALLS ITS GUARD!" % [data.boss_title.to_upper()])
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
	var from_pos := global_position
	var dest: Vector3 = dungeon.random_arena_pos()
	if dest != Vector3.INF:
		global_position = Vector3(dest.x, 0.5, dest.z)
	_sprite.modulate.a = 0.35
	rpc("phaseshift_fx", global_position)
	# Phaseshift Storm: the departure point detonates 1s later.
	_do_phaseshift_storm(from_pos)


func _do_charge() -> void:
	var tgt := _charge_target if (_charge_target != null and is_instance_valid(_charge_target)) else _target
	_charge_target = null
	if tgt == null or not is_instance_valid(tgt):
		return
	var to: Vector3 = tgt.global_position - global_position
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
	# Issue #130: pass the position through — Effects.scorch seats
	# the decal on the ground itself (was: pre-flattened to y=0.06).
	Effects.scorch(get_parent(), pos, 1.4)


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
	mi.global_position = Vector3(pos.x, pos.y + 0.35, pos.z)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(9, 1, 9), 1.1).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.1)
	tw.chain().tween_callback(mi.queue_free)


## Boar seismic slam: dust-brown expanding ring, 2s out to 12m (matches the
## server-side 6 m/s expansion). Damage is server-side only.
@rpc("any_peer", "call_local")
func seismic_fx(pos: Vector3) -> void:
	AudioManager.sfx("boss_slam", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 0.4, 0), Color(0.55, 0.42, 0.25), 40, 9.0)
	var parent := get_parent()
	if parent == null:
		return
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.55, 0.3, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.45, 0.2)
	mat.emission_energy_multiplier = 2.0
	torus.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, pos.y + 0.35, pos.z)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(12, 1, 12), 2.0).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(mat, "albedo_color:a", 0.0, 2.0)
	tw.chain().tween_callback(mi.queue_free)


## Warden judgment: gold telegraph rings on the marked spots (1.2s warning).
@rpc("any_peer", "call_local")
func judgment_telegraph(positions: Array) -> void:
	if positions.is_empty():
		return
	AudioManager.sfx("boss_roar", positions[0])
	for pos in positions:
		Effects.telegraph_ring(get_parent(), pos, 3.0, Color(1.0, 0.8, 0.2))


## Warden judgment: holy pillars erupt at the marked spots.
@rpc("any_peer", "call_local")
func judgment_fx(positions: Array) -> void:
	var parent := get_parent()
	for pos in positions:
		AudioManager.sfx("boss_slam", pos)
		Effects.burst(parent, pos + Vector3(0, 1.0, 0), Color(1.0, 0.75, 0.25), 30, 8.0)
		if parent == null:
			continue
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.6
		cyl.height = 7.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.85, 0.35, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.8, 0.3)
		mat.emission_energy_multiplier = 3.0
		cyl.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		parent.add_child(mi)
		mi.global_position = Vector3(pos.x, pos.y + 3.5, pos.z)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "scale", Vector3(0.2, 1.4, 0.2), 0.45).set_trans(Tween.TRANS_LINEAR)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
		tw.chain().tween_callback(mi.queue_free)


## Horror void rift: persistent purple zones. The server owns the lifecycle;
## clients build/free the visuals from the spawn/despawn RPCs.
@rpc("any_peer", "call_local")
func rift_spawn(batch: int, positions: Array) -> void:
	AudioManager.sfx("wave_horn", global_position)
	var parent := get_parent()
	if parent == null:
		return
	var nodes: Array = []
	for pos in positions:
		var disc := CylinderMesh.new()
		disc.top_radius = 2.5
		disc.bottom_radius = 2.5
		disc.height = 0.1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.1, 0.7, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.15, 0.8)
		mat.emission_energy_multiplier = 1.5
		disc.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		parent.add_child(mi)
		# Issue #127: the disc sits on the ground at its position
		# (pre-fix it was pinned to flat y=0.12 and buried whole on
		# heightmap themes). No sampler -> ground 0 -> the exact
		# pre-fix 0.12.
		mi.global_position = Vector3(pos.x, _rift_ground_y(pos, 0.0) + 0.12, pos.z)
		# Slow spin while the rift lives; freed on rift_despawn.
		var tw := mi.create_tween()
		tw.set_loops()
		tw.tween_property(mi, "rotation:y", TAU, 4.0).set_trans(Tween.TRANS_LINEAR)
		nodes.append(mi)
	_rift_nodes[batch] = nodes


## Horror void rift: pulse flash each server damage tick.
@rpc("any_peer", "call_local")
func rift_pulse_fx(batch: int, pos: Vector3) -> void:
	Effects.burst(get_parent(), pos + Vector3(0, 0.5, 0), Color(0.6, 0.2, 0.9), 12, 4.0)
	# Issue #127: the marker tracks its rift. Each pulse carries the
	# server's (grounded) rift position; a disc OF THE PULSE'S OWN
	# BATCH follows it, re-grounded off the carried y. Two
	# disciplines, both measured live on the Depths: (1) batch —
	# with two casts alive, one batch's pulses must not steal the
	# other's discs; (2) round claims — when a batch's rifts
	# converge on one point, a plain nearest-disc rule lets one
	# disc win every pulse and strands its siblings, so a pulse
	# prefers the nearest disc not claimed within the last 0.5s
	# (a batch's pulses land in the same tick, ~a frame apart).
	var now := Time.get_ticks_msec()
	var best: Node3D = null
	var best_d := 1e18
	var best_any: Node3D = null
	var best_any_d := 1e18
	for n in _rift_nodes.get(batch, []):
		if is_instance_valid(n):
			var np := (n as Node3D).global_position
			var dd := Vector2(np.x - pos.x, np.z - pos.z).length()
			if dd < best_any_d:
				best_any_d = dd
				best_any = n
			var claimed_at := int(_rift_disc_claimed.get(n.get_instance_id(), -100000))
			if now - claimed_at > 500 and dd < best_d:
				best_d = dd
				best = n
	if best == null:
		best = best_any
	if best != null:
		best.global_position = Vector3(pos.x, pos.y + 0.12, pos.z)
		_rift_disc_claimed[best.get_instance_id()] = now
		if _rift_disc_claimed.size() > 64: # prune freed discs' entries
			var live: Dictionary = {}
			for b2 in _rift_nodes:
				for n2 in _rift_nodes[b2]:
					if is_instance_valid(n2) and _rift_disc_claimed.has(n2.get_instance_id()):
						live[n2.get_instance_id()] = _rift_disc_claimed[n2.get_instance_id()]
			_rift_disc_claimed = live


@rpc("any_peer", "call_local")
func rift_despawn(batch: int) -> void:
	if not _rift_nodes.has(batch):
		return
	for n in _rift_nodes[batch]:
		if is_instance_valid(n):
			n.queue_free()
	_rift_nodes.erase(batch)


## Boar mud wall: dust burst where the mounds erupt.
@rpc("any_peer", "call_local")
func mud_wall_fx(pos: Vector3) -> void:
	AudioManager.sfx("boss_slam", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 0.5, 0), Color(0.5, 0.38, 0.22), 36, 8.0)


## Horror dread mirror: purple burst as the clones form.
@rpc("any_peer", "call_local")
func mirror_fx(pos: Vector3) -> void:
	AudioManager.sfx("wave_horn", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(0.6, 0.3, 0.9), 30, 6.0)


## Warden gilded cage: golden flash on the victim.
@rpc("any_peer", "call_local")
func cage_fx(pos: Vector3) -> void:
	AudioManager.sfx("boss_roar", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(1.0, 0.8, 0.25), 24, 5.0)


@rpc("any_peer", "call_local")
func cage_break_fx(pos: Vector3) -> void:
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.4), 20, 6.0)


## Boar blood frenzy: red burst as it enrages.
@rpc("any_peer", "call_local")
func frenzy_fx(pos: Vector3) -> void:
	AudioManager.sfx("boss_roar", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(1.0, 0.2, 0.1), 40, 7.0)


## Soft enrage: small burst + stack count (visual only).
@rpc("any_peer", "call_local")
func enrage_stack_fx(pos: Vector3, stacks: int) -> void:
	AudioManager.sfx("boss_roar", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 1.5, 0), Color(1.0, 0.4, 0.1), 12 + stacks * 4, 5.0)


## Phaseshift storm: purple telegraph at the departure point.
@rpc("any_peer", "call_local")
func afterimage_telegraph(pos: Vector3) -> void:
	Effects.telegraph_ring(get_parent(), pos, 4.0, Color(0.6, 0.2, 0.9))


## Phaseshift storm: the afterimage detonates.
@rpc("any_peer", "call_local")
func afterimage_fx(pos: Vector3) -> void:
	AudioManager.sfx("boss_slam", pos)
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(0.65, 0.25, 0.95), 36, 8.0)


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


## Issue #173: the server's status truth for this mob, as one
## int. Shatter folds into SLOW (apply_slow sets it), and so
## does the bulwark-slow rider. 0 when dead — death clears
## every ring on every peer with the same snapshot.
func status_mask() -> int:
	if not alive:
		return 0
	var m := 0
	if _slow_t > 0.0 or bulwark_slow_t > 0.0:
		m |= STATUS_SLOW
	if _stun_t > 0.0:
		m |= STATUS_STUN
	if _blind_t > 0.0:
		m |= STATUS_BLIND
	if _burn_t > 0.0:
		m |= STATUS_BURN
	if _mark_t > 0.0:
		m |= STATUS_MARK
	if doom_t > 0.0:
		m |= STATUS_DOOM
	return m


## Issue #173: build the shared ring assets once (one annulus
## mesh at radius 1 — slots scale it — and the six materials).
static func _status_shared() -> void:
	if _status_mesh != null:
		return
	var torus := TorusMesh.new()
	torus.inner_radius = 0.93
	torus.outer_radius = 1.07
	torus.rings = 48
	torus.ring_segments = 8
	_status_mesh = torus
	for i in range(6):
		var c: Color = STATUS_COLORS[i]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = c
		_status_mats.append(mat)


## Issue #173: this mob's ground footprint radius (its
## collision capsule), the base every slot radius builds on.
func _footprint_radius() -> float:
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null:
		if cs.shape is CapsuleShape3D:
			return (cs.shape as CapsuleShape3D).radius
		if cs.shape is SphereShape3D:
			return (cs.shape as SphereShape3D).radius
		if cs.shape is CylinderShape3D:
			return (cs.shape as CylinderShape3D).radius
	return 0.5


## Issue #173: build the lazy StatusRings container: six slot
## nodes in canonical order. Slot i sits at radius footprint
## + 0.32 + i*0.22 (the slot node scales the shared unit
## annulus) and height 0.03 + i*0.012. Slots are NEVER
## re-slotted: an effect's ring keeps its radius for the
## mob's whole life, however its neighbours come and go.
func _ensure_status_rings() -> void:
	if _status_rings != null:
		return
	_status_shared()
	_status_rings = Node3D.new()
	_status_rings.name = "StatusRings"
	add_child(_status_rings)
	var footprint := _footprint_radius()
	for i in range(6):
		var slot := Node3D.new()
		slot.name = "StatusRing_%d" % i
		var r := footprint + 0.32 + float(i) * 0.22
		slot.scale = Vector3(r, 1.0, r)
		slot.position = Vector3(0, 0.03 + float(i) * 0.012, 0)
		slot.visible = false
		var mi := MeshInstance3D.new()
		mi.name = "Ring"
		mi.mesh = _status_mesh
		mi.material_override = _status_mats[i]
		slot.add_child(mi)
		slot.add_child(Effects.make_status_motes(STATUS_COLORS[i]))
		_status_rings.add_child(slot)


## Issue #173: reconcile the rings with a snapshot mask. A
## ring (and its motes) is present exactly while its effect
## is active; the mask is the ONLY input, so a late joiner's
## first snapshot renders the full truth.
func _apply_status_mask(mask_v: int) -> void:
	if mask_v == _status_mask_applied and _status_rings != null:
		return
	if mask_v == 0 and _status_rings == null:
		_status_mask_applied = 0
		return
	_ensure_status_rings()
	_status_mask_applied = mask_v
	for i in range(6):
		var on := (mask_v & (1 << i)) != 0
		var slot := _status_rings.get_child(i)
		slot.visible = on
		(slot.get_node("Motes") as GPUParticles3D).emitting = on


@rpc("any_peer", "call_local", "unreliable")
func push_snapshot(pos: Vector3, hp_v: float, alive_v: bool, shoot_v: bool = false, status_mask_v: int = 0) -> void:
	_remote_pos = pos
	_has_remote = true
	# Issue #173: status rings derive from the snapshot mask —
	# the only channel, correct from a late joiner's first one.
	_apply_status_mask(status_mask_v)
	# Issue #167: redraw the bar when the replicated hp moves —
	# take_damage (the only other redraw) runs server-side only,
	# so client bars froze at the spawn fraction. The fraction's
	# max source is this replica's own max_hp, fixed at spawn
	# (data x hp_scale in the spawn rpc) for the mob's whole life.
	if hp_v != hp:
		hp = hp_v
		_update_health_bar()
	if alive and not alive_v:
		_shoot_playing = false
		_play_death()
	alive = alive_v
	# Issue #148: the shoot cycle rides the snapshot — the draw plays
	# on every peer from the same flag, no parallel channel.
	if shoot_v and not _shoot_playing:
		_shoot_playing = true
		if _sprite != null and _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation("shoot"):
			_sprite.play("shoot")
	elif not shoot_v and _shoot_playing:
		_shoot_playing = false
		if _sprite != null:
			_sprite.play("default")


@rpc("any_peer", "call_local")
func take_damage(amount: float, attacker: int, attacker_pos: Vector3, bypass_block: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if not alive:
		return
	# Phaseshift: the apex Horror is untargetable during its 2s window.
	if untargetable:
		return
	# Brittle Ice (issue #210 Amendment 1): a hit on a
	# FROZEN mob (active slow multiplier 0.0) with a stored
	# prison shatter breaks the ice — the shatter is added
	# to the hit, the freeze is consumed (the expiry reset,
	# applied early), and the value clears. One shatter per
	# freeze application.
	if prison_shatter > 0.0 and _slow_t > 0.0 \
			and _slow_mult == 0.0:
		amount += prison_shatter
		prison_shatter = 0.0
		prison_shatter_owner = 0
		_slow_t = 0.0
		_slow_mult = 1.0
		_sprite.modulate = Color.WHITE
	# Marked targets take +50% damage (plus the marking
	# caster's stored Deep Tree vuln add, issue #210).
	if _mark_t > 0.0:
		amount *= 1.5 + _mark_vuln_add
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
	# Doom Totem (Conqueror signature): +30% damage from
	# all sources. Issue #210: the magnitude is stored on
	# the mob by the totem that refreshed it (doom_vuln,
	# default 0.30 = the shipped value).
	if doom_t > 0.0:
		amount *= 1.0 + doom_vuln
	# Shieldbearer (issue #67): frontal block. If the shield is up and the
	# attacker is within the frontal arc, reduce damage. Meteor bypasses.
	var blocked := false
	if data.frontal_block and not bypass_block and _shield_up:
		var to_attacker: Vector3 = attacker_pos - global_position
		to_attacker.y = 0.0
		if to_attacker.length() > 0.01:
			# Mob's forward: sprite faces target via rotation.y = atan2(dir.x, dir.z).
			var fwd := Vector3(sin(_sprite.rotation.y), 0.0, cos(_sprite.rotation.y))
			var angle_deg := rad_to_deg(fwd.angle_to(to_attacker.normalized()))
			if angle_deg <= data.block_arc_deg * 0.5:
				blocked = true
				amount *= data.block_mult
				rpc("shield_clang", global_position)
	if data.frontal_block and not blocked and not bypass_block:
		# Flank/rear hit: 1.5s stagger (shield drops).
		_stagger_t = 1.5
		_shield_up = false
	hp -= amount
	_update_health_bar()
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
		# Shieldbearer: blocked hits have zero knockback.
		if not blocked:
			_knockback = away.normalized() * 6.0
	rpc("hit_react", global_position, amount, attacker)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		rpc("play_death")
		# Issue #189 (section 3): kill-decision site 1 of 2 —
		# the marker hears of the death here, whatever the
		# damage source was.
		_notify_marked_death()
		# Issue #210: kill-decision site 1 of 2 for Coup de
		# Grâce — an Assassinate strike's own kill.
		_notify_coup(attacker)
		_notify_tree_kill(attacker)
		_drop_and_reward(attacker)
		# Splitter (issue #67 Phase 2): server-side spawn-on-death.
		# Children have split_on_death=false (hard cap, no cascade).
		if data.split_on_death and multiplayer.is_server():
			var dungeon := get_tree().get_first_node_in_group("dungeon")
			if dungeon != null and dungeon.has_method("server_spawn_mob"):
				for i in data.split_count:
					var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
					dungeon.server_spawn_mob(data.split_id, global_position + offset)
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
			dungeon.rpc("announce_text", "%s SLAIN!" % [data.boss_title.to_upper()])
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
	# Issue #205 (F2): on a replayed floor, drops pay
	# consumables only — gear entries leave the pool (XP
	# above is untouched). Stubs without the method read as
	# a first clear.
	var replay: bool = dungeon.has_method("is_floor_replay") \
		and bool(dungeon.call("is_floor_replay"))
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
			if replay and not d.item.consumable:
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
			if replay and not d.item.consumable:
				continue
			roll -= d.weight * _luck_weight(d.item.rarity)
			if roll <= 0.0:
				dungeon.spawn_pickup_allocated(d.item.id, global_position + Vector3(0, 0.8, 0), reward_scale)
				break
	# Meta items from elites/bosses.
	_try_meta_drop(dungeon)
	# Issue #113 Phase 1: masterwork kits drop from elites and bosses
	# (apex bosses included — they are bosses), mirroring the meta-drop
	# pattern. Chances are PLACEHOLDERS (Jesse tunes balance).
	_try_masterwork_drop(dungeon)
	# Apex relic (issue #5 Phase 3): the apex boss ALWAYS drops its relic,
	# outside the weighted pool — a 100% forced drop, not a table entry.
	if data.apex_id != "":
		var relic_id := SpecialData.relic_item_for_apex(data.id)
		if relic_id != "":
			dungeon.spawn_pickup_allocated(relic_id, global_position + Vector3(0, 0.8, 0), 1.0)


## Potion/consumable item IDs (village-only drops).
func _is_potion(item_id: String) -> bool:
	return item_id in ["health_potion", "swift_potion", "power_elixir"]


## Meta-unlocked items can drop from elites and bosses once unlocked.
func _try_meta_drop(dungeon) -> void:
	if not (data.is_boss or is_elite):
		return
	# Issue #205 (F2): meta items are gear — a replayed
	# floor never pays them.
	if dungeon.has_method("is_floor_replay") \
			and bool(dungeon.call("is_floor_replay")):
		return
	var unlocked := SaveManager.get_unlocked_items()
	if unlocked.is_empty():
		return
	# 15% chance for bosses, 5% for elites.
	var chance := 0.15 if data.is_boss else 0.05
	if randf() > chance:
		return
	var item_id: String = unlocked[randi() % unlocked.size()]
	dungeon.spawn_pickup_allocated(item_id, global_position + Vector3(0, 0.8, 0), reward_scale)


## Issue #113 Phase 1: masterwork kits (+2 upgrade levels) drop from
## elites and bosses.
func _try_masterwork_drop(dungeon) -> void:
	if not (data.is_boss or is_elite):
		return
	var chance := MASTERWORK_DROP_CHANCE_BOSS if data.is_boss else MASTERWORK_DROP_CHANCE_ELITE
	if randf() > chance:
		return
	dungeon.spawn_pickup_allocated("masterwork_kit", global_position + Vector3(0, 0.8, 0), reward_scale)


## Higher luck multiplies the weight of rarer items (rarity 0..4).
func _luck_weight(rarity: int) -> float:
	var luck := data.loot_luck + (1.5 if is_elite else 0.0)
	return 1.0 + luck * float(rarity) * 0.4


## Jesse 2026-10-11: floating health bar above the mob.
## Single billboarded Sprite3D with a dynamically drawn texture:
## code-generated border + red fill, fill width = HP percent.
## (No PNG frames, no separate quads — one sprite, no clip/misalign bugs.)
func _build_health_bar() -> void:
	var bar := Node3D.new()
	bar.name = "HealthBar"
	# Above the name Label3D (y=1.9); bosses are bigger so offset more.
	var y_off := 2.6 * _base_scale.x if _base_scale.x > 1.0 else 2.3
	bar.position = Vector3(0, y_off, 0)
	add_child(bar)
	_hb_full_w = 2.0 if data.is_boss else 1.4
	_hb_bar_h = 0.30 if data.is_boss else 0.22
	_hb_img_w = 200
	_hb_img_h = 22
	_hb_image = Image.create(_hb_img_w, _hb_img_h, false, Image.FORMAT_RGBA8)
	_hb_tex = ImageTexture.create_from_image(_hb_image)
	var spr := Sprite3D.new()
	spr.texture = _hb_tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.no_depth_test = false  # depth-tested (Jesse #195): bars occlude behind walls
	# Sprite3D pixel_size=0.01: world size = px * 0.01 * scale.
	spr.scale = Vector3(_hb_full_w / (_hb_img_w * 0.01), _hb_bar_h / (_hb_img_h * 0.01), 1)
	bar.add_child(spr)
	_hb_fill = spr
	_update_health_bar()


## Redraw the bar texture: dark border + red fill proportional to HP.
func _update_health_bar() -> void:
	if _hb_fill == null or not is_instance_valid(_hb_fill) or _hb_image == null:
		return
	var frac := 0.0
	if max_hp > 0.0:
		frac = clampf(hp / max_hp, 0.0, 1.0)
	var border := 3
	# Border.
	_hb_image.fill(Color(0.05, 0.05, 0.07, 0.92))
	# Red fill inside the border, width = HP percent.
	var iw := _hb_img_w - border * 2
	var ih := _hb_img_h - border * 2
	var fill_w := int(iw * frac)
	if fill_w > 0:
		# Vertical gradient: brighter top, darker bottom.
		for y in range(ih):
			var t := float(y) / float(maxi(ih - 1, 1))
			var col := Color(0.85, 0.12, 0.10).lerp(Color(0.55, 0.05, 0.05), t)
			for x in range(fill_w):
				_hb_image.set_pixel(border + x, border + y, col)
	_hb_tex.update(_hb_image)
