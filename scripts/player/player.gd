class_name Player
extends CharacterBody3D
## First-person hack-and-slash character, client-authoritative.
## The owning peer simulates movement, mouse-look and attacks; snapshots are
## broadcast unreliably so remote peers can interpolate the billboard sprite.
## Loot goes into an inventory (E to pick up, I to manage); equipped items
## grant flat bonuses plus stacking multipliers.

signal health_changed(hp: float, max_hp: float)
signal xp_changed(xp: int, xp_next: int, level: int)
signal died
signal leveled_up(level: int)

const GRAVITY := 20.0
const JUMP_VELOCITY := 7.0
const SNAPSHOT_INTERVAL := 0.1
const MOUSE_SENS := 0.0025
const EYE_HEIGHT := 1.6
const INVENTORY_MAX := 12
const PICKUP_RANGE := 4.5
const FIREBALL_SPEED := 22.0

@export var class_id: String = "warrior"

## RTS faction in the Warlord's Domain (-1 = not in RTS mode).
var rts_faction := -1

var class_data: ClassData
var level := 1
var xp := 0
var xp_next := 25
var max_hp := 100.0
var hp := 100.0
var damage := 10.0
var attack_cooldown := 0.5
var move_speed := 5.0
var attack_range := 2.8
var xp_mult := 1.0
# Every carried item applies its bonuses and multipliers. Death wipes them all.
# Inventory is an Array of stacks: { "item": ItemData, "count": int }.
# Same-type items combine into one stack; every copy contributes fully.
var inventory: Array = []
# Permanent stat points earned from leveling (kept through death).
var stat_points := 0
var bonus_damage := 0.0
var bonus_health := 0.0
var bonus_speed := 0.0
var bonus_aura := 0.0 # mage only: staff glow brightness per point
var supermarket_cash := 0 # cash from selling supermarket loot
var alive := true
var hud: CanvasLayer
## Downed (co-op only): not dead yet — a teammate can revive. Bleed out
## after REVIVE_WINDOW seconds, then it's a real death.
var downed := false
var _bleedout := 0.0
var _revive_channel := 0.0
const REVIVE_WINDOW := 30.0
const REVIVE_CHANNEL := 3.0
const REVIVE_RANGE := 3.5

# --- Run statistics (shown on the death screen) ---
var run_start_msec := 0
var run_kills := 0
var run_damage_dealt := 0.0
var run_death_cause := ""

# --- Class abilities ---
# Unlocked by character level. Mage cycles spells (1-4/Q, cast with click).
# Warrior cycles totems (Q) and places with T. Rogue cycles (Q), uses with F.
var unlocked_abilities: Array = []
var selected_ability := 0
var totem_charges := 0
var ability_cds := {}  # ability id -> cooldown remaining
var eagle_eye_used_wave := -1
## Affinity Families: specialization in one skill, family collections.
var specialization := ""  # skill_id, or "" for none
var affinity := {}  # skill_id -> float (0-100)
var family_collection := {}  # family_id -> {"traits": [trait_ids], "signature": bool}
## Anti-cheese: per-enemy cooldowns for affinity gain.
var _affinity_enemy_cd := {}  # "%s:%d" % [skill_id, enemy_id] -> msec
## Per-cast caps: cast_id -> points granted so far.
var _affinity_cast_total := {}
const FOCUS_MULT := 2.0
const AFFINITY_ENEMY_CD := 5000
## Global tuning: scales all affinity gains. 0.25 = 4x slower than Appendix A
## starting values. Target ~15-20 min focused play to reach 100.
const AFFINITY_RATE := 0.25
## Smoke Veil stealth: mobs can't target you while stealthed.
var stealthed := false
var _stealth_t := 0.0
## Unseen trait: next attack after veil/blink crits (2x). Set on veil expiry / blink land.
var unseen_crit_ready := false
## Co-op ping: MMB / G drops a "!" marker visible to the whole party.
var _ping_cd := 0.0
const PING_COOLDOWN := 1.5
const PING_RANGE := 30.0
const PING_LIFETIME := 5.0
const PING_MAX := 6
var _pings: Array = []

var _cooldown := 0.0
var _jump_queued := false
var _was_on_floor := true
var _step_timer := 0.0
## Dash: Shift for a quick burst. _dash_t > 0 while dashing (i-frames),
## _dash_cd is the cooldown before the next dash.
var _dash_t := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
const DASH_TIME := 0.18
const DASH_COOLDOWN := 2.0
const DASH_SPEED := 16.0
## Temporary potion buffs: stat -> {"mult": float, "until": float (unix sec)}.
var _buffs := {
	"speed": {"mult": 1.0, "until": 0.0},
	"damage": {"mult": 1.0, "until": 0.0},
}
var _buff_announced := {"speed": false, "damage": false}
var _snapshot := 0.0
var _remote_pos := Vector3.ZERO
var _has_remote := false
var _sprite: AnimatedSprite3D
var _yaw := 0.0
var _pitch := 0.0
var _camera: Camera3D
var _cam_base := Vector3(0, EYE_HEIGHT, 0)
var _shake := 0.0
var _viewmodel: Node3D
var _vm_base := Vector3(0.32, -0.34, -0.55)
var _vm_base_rot := Vector3(0.15, -0.25, 0.1)
var _cast_seq := 0
var _staff_glow: OmniLight3D
var _staff_crystal_mat: StandardMaterial3D
# Team-visible aura: world-space glow every peer renders. Synced via RPC.
var _aura_light: OmniLight3D
var net_aura_level := 1
var net_bonus_aura := 0.0
var _bob_t := 0.0
var _prompt_pickup: ItemPickup = null


func _ready() -> void:
	add_to_group("players")
	run_start_msec = Time.get_ticks_msec()
	class_data = load("res://data/classes/%s.tres" % class_id) as ClassData
	if class_data == null:
		push_error("[Player] Unknown class: %s" % class_id)
		return
	_recalc_stats()
	hp = max_hp
	_sprite = $AnimatedSprite3D
	_build_sprite()
	$Label3D.text = _display_name()
	_remote_pos = global_position
	_give_starter_kit()
	_build_aura_visual()
	refresh_abilities()
	# Push initial aura so the team sees the glow from the start.
	if is_multiplayer_authority() and class_id == "mage":
		_push_aura.call_deferred()
	if class_id == "warrior":
		totem_charges = 1  # start with one totem charge
	if is_multiplayer_authority():
		_sprite.visible = false
		$Label3D.visible = false
		_camera = Camera3D.new()
		_camera.position = _cam_base
		_camera.far = 120.0
		add_child(_camera)
		_camera.current = true
		_build_viewmodel()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_bob_t = randf() * 10.0


func _display_name() -> String:
	var pid := get_multiplayer_authority()
	if SteamManager.initialized:
		return Steam.getFriendPersonaName(pid)
	return "Player %d" % pid


func _build_sprite() -> void:
	var frames := SpriteFrames.new()
	for tex in class_data.frames:
		frames.add_frame("default", tex)
	frames.set_animation_speed("default", 4.0)
	frames.set_animation_loop("default", true)
	_sprite.frames = frames
	_sprite.modulate = class_data.tint
	_sprite.play("default")


func _give_starter_kit() -> void:
	if not class_data.starting_weapon.is_empty():
		var item := ItemDB.get_item(class_data.starting_weapon)
		if item != null:
			inventory.append({"item": item, "count": 1})
			_recalc_stats()
			hp = max_hp


func _recalc_stats() -> void:
	if class_data == null:
		return
	var dmg_m := 1.0
	var hp_m := 1.0
	var spd_m := 1.0
	xp_mult = 1.0
	max_hp = class_data.base_health + float(level - 1) * 15.0 + bonus_health
	damage = class_data.base_damage + float(level - 1) * 2.0 + bonus_damage
	move_speed = class_data.base_move_speed + bonus_speed
	attack_cooldown = class_data.base_attack_cooldown
	attack_range = class_data.base_attack_range
	for entry in inventory:
		var item := entry["item"] as ItemData
		var count := int(entry["count"])
		max_hp += item.health_bonus * count
		damage += item.damage_bonus * count
		move_speed += item.speed_bonus * count
		dmg_m *= pow(item.damage_mult, count)
		hp_m *= pow(item.health_mult, count)
		spd_m *= pow(item.speed_mult, count)
		xp_mult *= pow(item.xp_mult, count)
	max_hp *= hp_m
	damage *= dmg_m
	move_speed *= spd_m
	# Milestone passives: 25/50/75/100.
	var ms := milestone_mult()
	damage *= ms
	max_hp *= ms
	hp = minf(hp, max_hp)


## Milestone bonuses: +10% at 25, +10% at 50, +15% at 75, +25% at 100.
func milestone_mult() -> float:
	var m := 1.0
	if level >= 25:
		m *= 1.10
	if level >= 50:
		m *= 1.10
	if level >= 75:
		m *= 1.15
	if level >= 100:
		m *= 1.25
	return m


func milestone_tier() -> int:
	if level >= 100:
		return 4
	if level >= 75:
		return 3
	if level >= 50:
		return 2
	if level >= 25:
		return 1
	return 0


# --- First-person viewmodels ---

func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	_viewmodel.position = _vm_base
	_viewmodel.rotation = _vm_base_rot
	_camera.add_child(_viewmodel)
	match class_id:
		"mage":
			_build_staff()
		"rogue":
			_build_dagger()
		_:
			_build_sword()


func _vm_model(path: String, model_scale: float, y_off: float, holder_pos: Vector3) -> Node3D:
	var packed := load(path) as PackedScene
	var holder := Node3D.new()
	holder.position = holder_pos
	if packed != null:
		var inst := packed.instantiate() as Node3D
		inst.scale = Vector3.ONE * model_scale
		inst.position.y = y_off * model_scale
		holder.add_child(inst)
	_viewmodel.add_child(holder)
	return holder


func _build_sword() -> void:
	# KayKit sword_1handed: 1.78m tall, handle bottom at y=-0.37 in model space.
	_vm_model("res://assets/models/kaykit/weapons/sword_1handed.gltf", 0.55, 0.37, Vector3(0, -0.12, 0))


func _build_dagger() -> void:
	# KayKit dagger: 1.2m tall, handle bottom at y=-0.225 in model space.
	_vm_model("res://assets/models/kaykit/weapons/dagger.gltf", 0.5, 0.225, Vector3(0, -0.08, 0))


func _build_staff() -> void:
	# KayKit staff: 2.15m tall, bottom at y=-0.9 in model space.
	var holder := _vm_model("res://assets/models/kaykit/weapons/staff.gltf", 0.5, 0.9, Vector3(0, -0.25, 0))
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.2)
	glow.light_energy = 0.5
	glow.omni_range = 3.5
	glow.position = Vector3(0, 0.8, 0)
	holder.add_child(glow)
	# Arcane crystal: grows brighter with mage level.
	var crystal := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.09
	cm.height = 0.18
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.6, 0.2)
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.5, 0.15)
	cmat.emission_energy_multiplier = 2.0
	cm.material = cmat
	crystal.mesh = cm
	crystal.position = Vector3(0, 0.82, 0)
	holder.add_child(crystal)
	_staff_glow = glow
	_staff_crystal_mat = cmat
	_update_staff_glow()


## Mage staff brightens with level and aura investment: light energy and
## crystal emission scale. Each aura point is +50% brightness.
func _update_staff_glow() -> void:
	if _staff_glow == null:
		return
	var f := _aura_factor()
	_staff_glow.light_energy = 0.5 * f
	_staff_glow.omni_range = 3.5 + float(level) * 0.15 + bonus_aura * 0.5
	if _staff_crystal_mat != null:
		_staff_crystal_mat.emission_energy_multiplier = 2.0 * f


## Shared aura brightness factor (level + invested aura points).
func _aura_factor() -> float:
	return 1.0 + float(maxi(0, level - 1)) * 0.25 + bonus_aura * 0.5


## Team-visible aura: a world-space light every peer renders, so the
## whole party can see how much aura a mage has invested.
func _build_aura_visual() -> void:
	_clear_aura_visual()
	if class_id != "mage":
		return
	_aura_light = OmniLight3D.new()
	_aura_light.position = Vector3(0, 1.2, 0)
	_aura_light.light_color = Color(0.5, 0.8, 1.0)
	_aura_light.shadow_enabled = false
	add_child(_aura_light)
	_update_aura_visual()


func _clear_aura_visual() -> void:
	if _aura_light != null and is_instance_valid(_aura_light):
		_aura_light.queue_free()
	_aura_light = null


## Refresh the world-space aura from the synced (level, aura) values.
func _update_aura_visual() -> void:
	if _aura_light == null:
		return
	var f := 1.0 + float(maxi(0, net_aura_level - 1)) * 0.25 + net_bonus_aura * 0.5
	_aura_light.light_energy = 0.6 * f
	_aura_light.omni_range = 4.0 + net_bonus_aura * 1.0


## Broadcast aura changes so every peer sees the team glow.
@rpc("any_peer", "call_local")
func sync_aura(p_level: int, p_aura: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	net_aura_level = p_level
	net_bonus_aura = p_aura
	_update_aura_visual()


func _push_aura() -> void:
	if not is_multiplayer_authority():
		return
	net_aura_level = level
	net_bonus_aura = bonus_aura
	_update_aura_visual()
	rpc("sync_aura", level, bonus_aura)


# --- Co-op ping ---

## Place a party-wide ping at whatever the crosshair is pointing at (MMB / G).
func _try_ping() -> void:
	if _ping_cd > 0.0 or _camera == null or not alive or downed:
		return
	_ping_cd = PING_COOLDOWN
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * PING_RANGE)
	params.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	var target: Vector3 = hit["position"] if not hit.is_empty() else from + dir * PING_RANGE
	var pname := NetworkManager.member_name(int(multiplayer.get_unique_id()))
	rpc("spawn_ping", target, pname)


## Host: R starts the next wave (the HUD button can't be clicked while the
## mouse is captured for FPS look).
func _try_start_wave() -> void:
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if dungeons.is_empty():
		return
	dungeons[0].rpc("request_next_wave")


## Show a bouncing "!" marker + player name at a pinged position for everyone.
@rpc("any_peer", "call_local")
func spawn_ping(pos: Vector3, from_player: String) -> void:
	var root := Node3D.new()
	root.name = "Ping"
	get_parent().add_child(root)
	root.global_position = pos + Vector3(0, 1.5, 0)
	var mark := Label3D.new()
	mark.text = "!"
	mark.font_size = 96
	mark.pixel_size = 0.01
	mark.modulate = Color(1.0, 0.85, 0.1)
	mark.outline_size = 12
	mark.outline_modulate = Color(0.1, 0.08, 0.0)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	root.add_child(mark)
	var who := Label3D.new()
	who.text = from_player
	who.font_size = 32
	who.pixel_size = 0.008
	who.modulate = Color(1.0, 0.9, 0.4)
	who.outline_size = 8
	who.outline_modulate = Color(0.1, 0.08, 0.0)
	who.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	who.no_depth_test = true
	who.position = Vector3(0, 1.0, 0)
	root.add_child(who)
	AudioManager.sfx("ping", pos)
	# Bounce up and down.
	var base_y := root.position.y
	var tw := root.create_tween().set_loops()
	tw.tween_property(root, "position:y", base_y + 0.5, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(root, "position:y", base_y, 0.4).set_trans(Tween.TRANS_SINE)
	# Cap active pings: drop the oldest.
	_pings.append(root)
	while _pings.size() > PING_MAX:
		var old: Node3D = _pings.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	# Fade out and clean up after the lifetime.
	var fade := root.create_tween()
	fade.tween_interval(PING_LIFETIME)
	fade.tween_property(mark, "modulate:a", 0.0, 0.5)
	fade.parallel().tween_property(who, "modulate:a", 0.0, 0.5)
	fade.tween_callback(root.queue_free)


func _attack_anim() -> void:
	if _viewmodel == null:
		return
	if class_id == "mage":
		var tw := create_tween()
		tw.tween_property(_viewmodel, "position:z", _vm_base.z - 0.3, 0.1)
		tw.tween_property(_viewmodel, "position:z", _vm_base.z, 0.22)
	else:
		var tw2 := create_tween()
		tw2.tween_property(_viewmodel, "rotation:z", -0.9, 0.08)
		tw2.tween_property(_viewmodel, "rotation:z", _vm_base_rot.z, 0.18)
		var tw3 := create_tween()
		tw3.tween_property(_viewmodel, "position:z", _vm_base.z - 0.28, 0.08)
		tw3.tween_property(_viewmodel, "position:z", _vm_base.z, 0.18)


# --- Input ---

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not alive:
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm := event as InputEventMouseMotion
			_yaw -= mm.relative.x * MOUSE_SENS
			_pitch = clampf(_pitch - mm.relative.y * MOUSE_SENS, -1.2, 1.2)
			rotation.y = _yaw
			if _camera != null:
				_camera.rotation.x = _pitch
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				if hud == null or not hud.is_paused:
					# Don't steal the mouse back while in RTS command view.
					var rts_cam := get_tree().get_first_node_in_group("rts_camera")
					if rts_cam == null or not bool(rts_cam.get("active")):
						Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif _cooldown <= 0.0:
				_do_attack()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_MIDDLE:
			if alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_try_ping()
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.physical_keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				if hud != null:
					hud.show_pause()
			get_viewport().set_input_as_handled()
		elif k.physical_keycode == KEY_SPACE:
			if alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_jump_queued = true
		elif k.physical_keycode == KEY_E:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_try_pickup()
		elif k.physical_keycode == KEY_SHIFT:
			if alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_try_dash()
		elif k.physical_keycode == KEY_Q:
			if alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_cycle_ability()
		elif k.physical_keycode == KEY_T:
			if alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_use_class_ability()
		elif k.physical_keycode == KEY_F:
			if alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_use_class_ability()
		elif k.physical_keycode == KEY_G:
			if alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_try_ping()
		elif k.physical_keycode == KEY_R:
			if alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_try_start_wave()
		elif k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_6:
			if class_id == "mage" and alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_select_ability(k.physical_keycode - KEY_1)
		elif k.physical_keycode == KEY_8:
			if class_id == "mage" and alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (hud == null or not hud.is_paused):
				_activate_mage_signature()
		elif k.physical_keycode == KEY_I or k.physical_keycode == KEY_TAB:
			if hud != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				# In Warlord's Domain, Tab toggles the RTS command view.
				if k.physical_keycode == KEY_TAB and get_tree().get_first_node_in_group("rts_camera") != null:
					return
				hud.toggle_inventory()


## Downed bleed-out (runs on the downed player's authority).
func _tick_downed(delta: float) -> void:
	_bleedout -= delta
	if hud != null:
		hud.update_downed(_bleedout)
	if _bleedout <= 0.0:
		_do_death()


## Teammate revive: hold E near a downed ally to channel a revive.
func _tick_revive_channel(delta: float) -> void:
	var mate := _nearest_downed_teammate()
	if mate != null and Input.is_physical_key_pressed(KEY_E) and (hud == null or not hud.is_paused):
		_revive_channel += delta
		if hud != null:
			hud.show_revive_progress(_revive_channel / REVIVE_CHANNEL)
		if _revive_channel >= REVIVE_CHANNEL:
			_revive_channel = 0.0
			if hud != null:
				hud.hide_revive_progress()
			mate.rpc_id(mate.get_multiplayer_authority(), "revive")
	else:
		if _revive_channel > 0.0 and hud != null:
			hud.hide_revive_progress()
		_revive_channel = 0.0


func _nearest_downed_teammate() -> Node3D:
	var best: Node3D = null
	var best_d := REVIVE_RANGE
	for n in get_tree().get_nodes_in_group("players"):
		if n == self:
			continue
		var p := n as Node3D
		if p == null:
			continue
		if p.get("downed") != true:
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


static func class_abilities(cid: String) -> Array:
	match cid:
		"mage":
			return [
				{"id": "fireball", "name": "Fireball", "unlock": 1, "key": "1", "desc": "Fiery bolt, small blast"},
				{"id": "frost", "name": "Frost Shard", "unlock": 3, "key": "2", "desc": "Fast shard, slows enemies"},
				{"id": "lightning", "name": "Chain Lightning", "unlock": 5, "key": "3", "desc": "Zaps 3 chained targets"},
				{"id": "meteor", "name": "Meteor", "unlock": 8, "key": "4", "desc": "Delayed fiery impact"},
				{"id": "barrage", "name": "Arcane Barrage", "unlock": 15, "key": "5", "desc": "Triple bolt spread"},
				{"id": "blizzard", "name": "Blizzard", "unlock": 30, "key": "6", "desc": "Freezing storm, DoT + slow"},
				{"id": "holy_light", "name": "Holy Light", "unlock": 999, "key": "7", "desc": "Lights up the whole map 10s (20s cd)", "aura_req": 20},
			]
		"warrior":
			return [
				{"id": "reciprocity", "name": "Reciprocity", "unlock": 1, "key": "T", "desc": "Healing totem aura"},
				{"id": "bulwark", "name": "Bulwark", "unlock": 4, "key": "T", "desc": "Totem that slows enemies"},
				{"id": "warhorn", "name": "War Horn", "unlock": 7, "key": "T", "desc": "Totem boosting ally damage"},
				{"id": "stoneskin", "name": "Stoneskin", "unlock": 15, "key": "T", "desc": "Totem reducing damage taken"},
				{"id": "rally", "name": "Rally", "unlock": 30, "key": "T", "desc": "Totem boosting move speed"},
			]
		"rogue":
			return [
				{"id": "eagle_eye", "name": "Eagle Eye", "unlock": 1, "key": "F", "desc": "Reveal all enemies 4s, 1/wave"},
				{"id": "smoke_veil", "name": "Smoke Veil", "unlock": 4, "key": "F", "desc": "Untargetable 6s"},
				{"id": "mark", "name": "Mark Target", "unlock": 7, "key": "F", "desc": "Marked foe takes +50% dmg"},
				{"id": "shadow_step", "name": "Shadow Step", "unlock": 15, "key": "F", "desc": "Blink 8m forward"},
				{"id": "fan", "name": "Fan of Knives", "unlock": 30, "key": "F", "desc": "Blades hit all nearby foes"},
			]
	return []


## Affinity families: theme groups of skills. Specializing in a skill unlocks
## its family's collection track: traits at 25/50/75, signature skill at 100.
## Holy Light is excluded (special track).
static func families() -> Dictionary:
	return {
		"fire": {
			"name": "Fire", "class": "mage",
			"skills": ["fireball", "meteor"],
			"traits": {
				25: {"id": "kindled", "name": "Kindled", "desc": "+10% damage on fire skills"},
				50: {"id": "wildfire", "name": "Wildfire", "desc": "Fire hits apply burn (3s DoT)"},
				75: {"id": "conflagration", "name": "Conflagration", "desc": "+25% blast radius on fire skills"},
			},
			"signature": {"id": "inferno", "name": "Inferno", "key": "8",
				"desc": "Firestorm descends on a target location: huge AoE burn zone for 5s"},
		},
		"frost": {
			"name": "Frost", "class": "mage",
			"skills": ["frost", "blizzard"],
			"traits": {
				25: {"id": "deep_chill", "name": "Deep Chill", "desc": "+10% damage on frost skills"},
				50: {"id": "brittle", "name": "Brittle", "desc": "Slowed enemies take +15% damage (team)"},
				75: {"id": "permafrost", "name": "Permafrost", "desc": "Slows last +2s"},
			},
			"signature": {"id": "glacial_prison", "name": "Glacial Prison", "key": "8",
				"desc": "Freeze all enemies within 8m solid for 3s"},
		},
		"storm": {
			"name": "Storm", "class": "mage",
			"skills": ["lightning", "barrage"],
			"traits": {
				25: {"id": "charged", "name": "Charged", "desc": "+10% damage on storm skills"},
				50: {"id": "arc_conduit", "name": "Arc Conduit", "desc": "Lightning chains +1 target"},
				75: {"id": "overcharge", "name": "Overcharge", "desc": "Storm hits 15% chance to double-strike"},
			},
			"signature": {"id": "tempest", "name": "Tempest", "key": "8",
				"desc": "6s channeled storm: lightning strikes random nearby enemies"},
		},
		"warden": {
			"name": "Warden", "class": "warrior",
			"skills": ["reciprocity", "stoneskin"],
			"traits": {
				25: {"id": "wardens_oath", "name": "Warden's Oath", "desc": "+15% aura strength on Warden totems"},
				50: {"id": "shared_vitality", "name": "Shared Vitality", "desc": "Stoneskin also grants +10% move speed"},
				75: {"id": "wide_ward", "name": "Wide Ward", "desc": "+25% aura radius on Warden totems"},
			},
			"signature": {"id": "sanctuary_totem", "name": "Sanctuary Totem", "key": "T",
				"desc": "Totem: allies in radius immune to damage for 3s (long cooldown)"},
		},
		"conqueror": {
			"name": "Conqueror", "class": "warrior",
			"skills": ["bulwark", "warhorn", "rally"],
			"traits": {
				25: {"id": "commanding_presence", "name": "Commanding Presence", "desc": "+15% aura strength on Conqueror totems"},
				50: {"id": "relentless", "name": "Relentless", "desc": "Bulwark-slowed enemies deal -10% damage"},
				75: {"id": "war_drums", "name": "War Drums", "desc": "Rally also grants +10% attack speed"},
			},
			"signature": {"id": "doom_totem", "name": "Doom Totem", "key": "T",
				"desc": "Totem: enemies in radius take +30% damage from all sources"},
		},
		"shadow": {
			"name": "Shadow", "class": "rogue",
			"skills": ["smoke_veil", "shadow_step"],
			"traits": {
				25: {"id": "longer_shadows", "name": "Longer Shadows", "desc": "Shadow Step +2m range, Smoke Veil +1s"},
				50: {"id": "unseen", "name": "Unseen", "desc": "First attack after veil/blink crits"},
				75: {"id": "double_take", "name": "Double Take", "desc": "Shadow Step leaves a decoy for 3s"},
			},
			"signature": {"id": "assassinate", "name": "Assassinate", "key": "F",
				"desc": "Blink to a target enemy and strike for 300% damage"},
		},
		"precision": {
			"name": "Precision", "class": "rogue",
			"skills": ["eagle_eye", "mark", "fan"],
			"traits": {
				25: {"id": "true_aim", "name": "True Aim", "desc": "+10% damage to marked/revealed enemies"},
				50: {"id": "hamstring_mark", "name": "Hamstring Mark", "desc": "Marked targets also slowed 20%"},
				75: {"id": "ricochet", "name": "Ricochet", "desc": "Fan of Knives hits +2 targets"},
			},
			"signature": {"id": "execution", "name": "Execution", "key": "F",
				"desc": "Instantly kill a non-boss below 15% HP (bosses take heavy damage)"},
		},
	}


## The family a skill belongs to, or "" if none (e.g. holy_light).
static func family_of(skill_id: String) -> String:
	for fid in families():
		if skill_id in families()[fid]["skills"]:
			return fid
	return ""


## Ability rank 1-5 based on character level. Each rank is +25% effectiveness.
func ability_rank() -> int:
	if level >= 80:
		return 5
	if level >= 60:
		return 4
	if level >= 40:
		return 3
	if level >= 20:
		return 2
	return 1


func rank_mult() -> float:
	return 1.0 + float(ability_rank() - 1) * 0.25


func rank_roman() -> String:
	return ["", "I", "II", "III", "IV", "V"][ability_rank()]


## Refresh the unlocked ability list for the current level. Returns the
## newly unlocked ability dict, if any.
func refresh_abilities() -> Dictionary:
	var result := {}
	var fresh: Array = []
	for a in Player.class_abilities(class_id):
		var unlocked := level >= int(a["unlock"])
		# Holy Light unlocks at 20 Aura, not by level.
		if a.has("aura_req"):
			unlocked = bonus_aura >= float(a["aura_req"])
		if unlocked:
			fresh.append(a)
			if not unlocked_abilities.any(func(x): return x["id"] == a["id"]):
				result = a
	# Signature skills join the cycle when their family hits 100 (warrior/rogue).
	# Mage signatures are on key 8, not in the cycle.
	if class_id != "mage":
		var fams := Player.families()
		for fid in fams:
			var sig: Dictionary = family_signature(fid)
			if not sig.is_empty():
				# Only include signatures for this class's families.
				var class_fams := {"warrior": ["warden", "conqueror"], "rogue": ["shadow", "precision"]}
				if class_fams.has(class_id) and fid in class_fams[class_id]:
					if not fresh.any(func(x): return x["id"] == sig["id"]):
						fresh.append(sig)
	unlocked_abilities = fresh
	if selected_ability >= unlocked_abilities.size():
		selected_ability = 0
	# Warrior gains a totem charge on every level-up (max 3).
	if class_id == "warrior":
		totem_charges = mini(3, totem_charges + 1)
	if hud != null:
		hud.refresh_abilities(self)
	return result


# (duplicate _can_act removed; canonical version is near _use_class_ability)


# --- Class ability selection ---

func _cycle_ability() -> void:
	if unlocked_abilities.size() < 2:
		return
	selected_ability = (selected_ability + 1) % unlocked_abilities.size()
	AudioManager.sfx("ui_click")
	if hud != null:
		hud.refresh_abilities(self)


func _select_ability(idx: int) -> void:
	if idx < unlocked_abilities.size() and idx != selected_ability:
		selected_ability = idx
		AudioManager.sfx("ui_click")
		if hud != null:
			hud.refresh_abilities(self)


func _selected_ability_id() -> String:
	if selected_ability < unlocked_abilities.size():
		return String(unlocked_abilities[selected_ability]["id"])
	return ""


## T/F: use the selected class ability (warrior totem / rogue trick).
## Mage casts via left-click instead.
func _use_class_ability() -> void:
	if class_id == "warrior":
		_place_totem()
	elif class_id == "rogue":
		_activate_rogue_ability()


## Warrior totem placement (implemented in the totem task).
func _place_totem() -> void:
	var totem_id := _selected_ability_id()
	if totem_id == "":
		totem_id = "reciprocity"
	# Signature totems have their own activation.
	if totem_id in ["sanctuary_totem", "doom_totem"]:
		_activate_signature_totem(totem_id)
		return
	if totem_charges <= 0:
		if hud != null:
			hud.toast("No totem charges! Level up to earn more.")
			AudioManager.sfx("ui_error")
		return
	totem_charges -= 1
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon != null:
		dungeon.rpc("place_totem", totem_id, global_position, int(multiplayer.get_unique_id()), ability_rank())
	if hud != null:
		hud.refresh_abilities(self)


## Rogue ability activation (implemented in the rogue task).
func _activate_rogue_ability() -> void:
	match _selected_ability_id():
		"eagle_eye":
			_activate_eagle_eye()
		"smoke_veil":
			_activate_smoke_veil()
		"mark":
			_activate_mark()
		"shadow_step":
			_activate_shadow_step()
		"fan":
			_activate_fan()
		"assassinate":
			_activate_assassinate()
		"execution":
			_activate_execution()


## Eagle Eye: reveal all enemies through walls for 4s. Once per wave.
func _activate_eagle_eye() -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	var wave := 0
	if dungeon != null and "wave" in dungeon:
		wave = int(dungeon.get("wave"))
	if eagle_eye_used_wave == wave:
		if hud != null:
			hud.toast("Eagle Eye already used this wave.")
			AudioManager.sfx("ui_error")
		return
	eagle_eye_used_wave = wave
	AudioManager.sfx("eagle_eye")
	if hud != null:
		hud.toast("Eagle Eye! Enemies revealed.")
		hud.refresh_abilities(self)
	# X-ray all mobs on every peer.
	var cast_id := "eagle_%d" % _cast_seq
	var revealed := 0
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m != null and m.alive:
			m.rpc("set_xray", true)
			# Affinity: +1 normal, +5 elite/boss, max +10/activation.
			var pts := 5.0 if (m.is_elite or m.data.is_boss) else 1.0
			gain_affinity_capped("eagle_eye", pts, -1, cast_id, 10.0)
			revealed += 1
	await get_tree().create_timer(4.0).timeout
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m != null and is_instance_valid(m):
			m.rpc("set_xray", false)


## Smoke Veil: mobs can't target you for 6s. 30s cooldown.
func _activate_smoke_veil() -> void:
	if float(ability_cds.get("smoke_veil", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Smoke Veil on cooldown.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["smoke_veil"] = 30.0
	stealthed = true
	_stealth_t = 7.0 if has_trait("longer_shadows") else 6.0
	rpc("set_stealthed", true)
	AudioManager.sfx("smoke_veil")
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.5, 0.5, 0.55), 20, 4.0)
	# Affinity: +5 if ≥1 enemy within 10m.
	var near := false
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m != null and m.alive and m.global_position.distance_to(global_position) < 10.0:
			near = true
			break
	if near:
		gain_affinity("smoke_veil", 5.0)
	if hud != null:
		hud.toast("Smoke Veil! You vanish.")
		hud.refresh_abilities(self)


## Mark Target: the enemy under your crosshair takes +50% damage for 10s. 25s cooldown.
func _activate_mark() -> void:
	if float(ability_cds.get("mark", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Mark on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := _nearest_mob_aimed(from, dir, 25.0)
	if target == null:
		if hud != null:
			hud.toast("No target in sight.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["mark"] = 25.0
	# Hamstring Mark trait: marked targets are also slowed 20%.
	var hamstring := 0.8 if has_trait("hamstring_mark") else 1.0
	target.rpc_id(NetworkManager.server_id, "apply_mark", 10.0, hamstring)
	AudioManager.sfx("mark")
	if hud != null:
		hud.toast("Target marked! +50% damage.")
		hud.refresh_abilities(self)


func _nearest_mob_aimed(from: Vector3, dir: Vector3, max_dist: float) -> Mob:
	var best: Mob = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m == null or not m.alive:
			continue
		var to: Vector3 = m.global_position + Vector3(0, 1.0, 0) - from
		var dist := to.length()
		if dist > max_dist or dist < 0.5:
			continue
		if dir.angle_to(to / dist) > 0.15:
			continue
		if dist < best_d:
			best_d = dist
			best = m
	return best


## Shadow Step: blink 8m in the facing direction. 15s cooldown.
func _activate_shadow_step() -> void:
	if float(ability_cds.get("shadow_step", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Shadow Step on cooldown.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["shadow_step"] = 15.0
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Longer Shadows trait: +2m blink range.
	var blink_dist := 10.0 if has_trait("longer_shadows") else 8.0
	var origin := global_position
	var target := global_position + fwd * blink_dist
	# Don't blink through walls: raycast and stop short.
	var params := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), target + Vector3(0, 1.0, 0))
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	if not hit.is_empty():
		target = global_position + fwd * (global_position.distance_to(hit["position"]) - 1.0)
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.3, 0.3, 0.35), 20, 5.0)
	global_position = target
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.6, 0.5, 0.9), 20, 5.0)
	AudioManager.sfx("shadow_step")
	# Unseen trait: next attack after the blink crits.
	if has_trait("unseen"):
		unseen_crit_ready = true
	# Double Take trait: leave a decoy at the origin for 3s.
	if has_trait("double_take"):
		var dungeon := get_tree().get_first_node_in_group("dungeon")
		if dungeon != null:
			dungeon.rpc("spawn_decoy", origin, int(multiplayer.get_unique_id()))
	# Affinity: +3 if landing within 5m of an enemy, else +1.
	var pts := 1.0
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m != null and m.alive and m.global_position.distance_to(global_position) < 5.0:
			pts = 3.0
			break
	gain_affinity("shadow_step", pts)
	if hud != null:
		hud.refresh_abilities(self)


## Fan of Knives: blades damage all enemies within 5m. 20s cooldown.
func _activate_fan() -> void:
	if float(ability_cds.get("fan", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Fan of Knives on cooldown.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["fan"] = 20.0
	var dmg := damage * _buff_mult("damage") * rank_mult() * 1.2
	# Unseen trait: first attack after veil/blink crits for 2x.
	if unseen_crit_ready:
		dmg *= 2.0
		unseen_crit_ready = false
	AudioManager.sfx("fan")
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.8, 0.85, 0.9), 30, 7.0)
	# Ricochet trait: fan radius 5m → 6m (hits more targets).
	var fan_radius := 6.0 if has_trait("ricochet") else 5.0
	if multiplayer.is_server():
		var from := int(multiplayer.get_unique_id())
		var cast_id := "fan_%d" % _cast_seq
		for n in get_tree().get_nodes_in_group("mobs"):
			var m := n as Mob
			if m == null or not m.alive:
				continue
			if m.global_position.distance_to(global_position) < fan_radius:
				m.rpc_id(NetworkManager.server_id, "take_damage", dmg, from, global_position)
				# Affinity: +2 per enemy hit, max +8/cast.
				gain_affinity_capped("fan", 2.0, m.get_instance_id(), cast_id, 8.0)
	else:
		rpc("fan_fx", global_position)
	if hud != null:
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func fan_fx(pos: Vector3) -> void:
	Effects.burst(get_parent(), pos + Vector3(0, 1.0, 0), Color(0.8, 0.85, 0.9), 30, 7.0)
	AudioManager.sfx("fan", pos)


# --- Signature skills (Phase 4) ---
# Implemented by subagents; stubs here for parse integrity.

## Mage: key 8 activates the signature of the specialized skill's family.
func _activate_mage_signature() -> void:
	if specialization == "":
		if hud != null:
			hud.toast("Specialize in a skill first (pause menu).")
		return
	var fid := Player.family_of(specialization)
	var sig := family_signature(fid)
	if sig.is_empty():
		if hud != null:
			hud.toast("Signature not unlocked yet (reach 100 affinity).")
			AudioManager.sfx("ui_error")
		return
	match String(sig["id"]):
		"inferno":
			_activate_inferno()
		"glacial_prison":
			_activate_glacial_prison()
		"tempest":
			_activate_tempest()


## INFERNO (fire signature): target a location — a massive firestorm descends,
## huge AoE burn zone for 5s. 60s cooldown. ~1.5x rank-V meteor total.
func _activate_inferno() -> void:
	if float(ability_cds.get("inferno", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Inferno on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := from + dir * 25.0
	var params := PhysicsRayQueryParameters3D.create(from, target)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	var point: Vector3 = hit["position"] if not hit.is_empty() else target
	point.y = maxf(point.y, 0.1)
	ability_cds["inferno"] = 60.0
	_cast_seq += 1
	# 10 ticks x 0.6 = 6.0x base ≈ 1.5x rank-V meteor (4.0x), plus burn.
	var dmg := damage * _buff_mult("damage") * 0.6 * trait_damage_mult("fireball")
	rpc("cast_inferno", point, dmg, int(multiplayer.get_unique_id()), _cast_seq)
	AudioManager.sfx("milestone")
	if hud != null:
		hud.toast("INFERNO!")
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func cast_inferno(point: Vector3, dmg: float, owner: int, seq: int) -> void:
	Effects.telegraph_ring(get_parent(), point, 8.0, Color(1.0, 0.4, 0.1))
	Effects.burst(get_parent(), point + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.1), 60, 10.0)
	Effects.scorch(get_parent(), point, 8.0)
	var flames := Effects.make_flame()
	flames.amount = 60
	get_parent().add_child(flames)
	flames.global_position = point + Vector3(0, 1.0, 0)
	flames.emitting = true
	AudioManager.sfx("explosion", point)
	AudioManager.sfx("meteor_incoming", point)
	# 10 ticks over 5 seconds.
	for i in 10:
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree():
			break
		if multiplayer.is_server():
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m == null or not m.alive:
					continue
				if m.global_position.distance_to(point) < 8.0:
					m.rpc_id(NetworkManager.server_id, "take_damage", dmg, owner, point)
					m.apply_burn(3.0, dmg * 0.3, owner)
		if i % 3 == 2 and is_inside_tree():
			Effects.burst(get_parent(), point + Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.1), 20, 7.0)
	flames.emitting = false
	get_parent().get_tree().create_timer(1.0).timeout.connect(flames.queue_free)


## GLACIAL PRISON (frost signature): freeze all enemies within 8m solid for 3s.
## 60s cooldown. Frozen enemies also trigger Shatter (+25% team damage).
func _activate_glacial_prison() -> void:
	if float(ability_cds.get("glacial_prison", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Glacial Prison on cooldown.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["glacial_prison"] = 60.0
	_cast_seq += 1
	rpc("cast_glacial_prison", global_position, int(multiplayer.get_unique_id()), _cast_seq)
	AudioManager.sfx("milestone")
	if hud != null:
		hud.toast("GLACIAL PRISON!")
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func cast_glacial_prison(center: Vector3, owner: int, seq: int) -> void:
	Effects.telegraph_ring(get_parent(), center, 8.0, Color(0.6, 0.85, 1.0))
	Effects.burst(get_parent(), center + Vector3(0, 1.0, 0), Color(0.7, 0.9, 1.0), 50, 9.0)
	AudioManager.sfx("frost_hit", center)
	AudioManager.sfx("blizzard_cast", center)
	if multiplayer.is_server():
		for n in get_tree().get_nodes_in_group("mobs"):
			var m := n as Mob
			if m == null or not m.alive:
				continue
			if m.global_position.distance_to(center) < 8.0:
				# 0.0 mult = frozen solid; also sets shatter for team synergy.
				m.apply_slow(3.0, 0.0)


## TEMPEST (storm signature): 6s channeled storm — lightning strikes random
## nearby enemies every 0.5s. 90s cooldown. Per-strike 1.5x chain lightning.
func _activate_tempest() -> void:
	if float(ability_cds.get("tempest", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Tempest on cooldown.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["tempest"] = 90.0
	_cast_seq += 1
	var dmg := damage * _buff_mult("damage") * 0.8 * 1.5 * trait_damage_mult("lightning")
	rpc("cast_tempest", dmg, int(multiplayer.get_unique_id()), _cast_seq)
	AudioManager.sfx("milestone")
	if hud != null:
		hud.toast("TEMPEST!")
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func cast_tempest(dmg: float, owner: int, seq: int) -> void:
	AudioManager.sfx("lightning_cast", global_position)
	Effects.telegraph_ring(get_parent(), global_position, 15.0, Color(0.7, 0.9, 1.0))
	# 12 strikes over 6 seconds; the storm follows the caster.
	for i in 12:
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree():
			break
		if multiplayer.is_server():
			var candidates: Array = []
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m != null and m.alive and m.global_position.distance_to(global_position) < 15.0:
					candidates.append(m)
			if candidates.is_empty():
				continue
			var target: Mob = candidates[randi() % candidates.size()]
			var sky: Vector3 = target.global_position + Vector3(0, 8.0, 0)
			var hit_pos: Vector3 = target.global_position + Vector3(0, 1.0, 0)
			target.rpc_id(NetworkManager.server_id, "take_damage", dmg, owner, global_position)
			rpc("chain_fx", sky, hit_pos)
			AudioManager.sfx("lightning_zap", hit_pos)


## Warrior: signature totems via T (uses totem charges).
## Sanctuary: 120s cooldown. Doom: 90s cooldown. Fixed power (rank 1).
func _activate_signature_totem(totem_id: String) -> void:
	var cd_key := totem_id
	var cd := 120.0 if totem_id == "sanctuary_totem" else 90.0
	if float(ability_cds.get(cd_key, 0.0)) > 0.0:
		if hud != null:
			hud.toast("Signature on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if totem_charges <= 0:
		if hud != null:
			hud.toast("No totem charges! Level up to earn more.")
			AudioManager.sfx("ui_error")
		return
	totem_charges -= 1
	ability_cds[cd_key] = cd
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon != null:
		dungeon.rpc("place_totem", totem_id, global_position, int(multiplayer.get_unique_id()), 1)
	AudioManager.sfx("milestone")
	if hud != null:
		var sig_name := "Sanctuary Totem" if totem_id == "sanctuary_totem" else "Doom Totem"
		hud.toast("%s placed!" % sig_name)
		hud.refresh_abilities(self)


## Sanctuary Totem (Warden signature): damage immunity while in the aura.
var _sanctuary_t := 0.0


@rpc("any_peer", "call_local")
func apply_sanctuary(duration: float) -> void:
	if not is_multiplayer_authority():
		return
	_sanctuary_t = maxf(_sanctuary_t, duration)


## Rogue: F-cycle signatures.
func _activate_assassinate() -> void:
	if float(ability_cds.get("assassinate", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Assassinate on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := _nearest_mob_aimed(from, dir, 25.0)
	if target == null:
		if hud != null:
			hud.toast("No target in sight.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["assassinate"] = 45.0
	var origin := global_position
	# Blink to behind the target (far side relative to our position).
	var away: Vector3 = target.global_position - global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -global_transform.basis.z
	var dest := target.global_position + away * 1.8
	# Don't blink through walls: raycast and stop short.
	var params := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), dest + Vector3(0, 1.0, 0))
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	if not hit.is_empty():
		var hit_dist: float = global_position.distance_to(hit["position"]) - 1.0
		dest = global_position + (dest - global_position).normalized() * maxf(hit_dist, 0.5)
	Effects.burst(get_parent(), origin + Vector3(0, 1.0, 0), Color(0.2, 0.2, 0.25), 25, 6.0)
	global_position = dest
	Effects.burst(get_parent(), dest + Vector3(0, 1.0, 0), Color(0.6, 0.5, 0.9), 25, 6.0)
	AudioManager.sfx("shadow_step")
	# Strike for 300% damage (server-authoritative).
	var strike := damage * _buff_mult("damage") * rank_mult() * 3.0
	var me := int(multiplayer.get_unique_id())
	target.rpc_id(NetworkManager.server_id, "take_damage", strike, me, global_position)
	Effects.burst(get_parent(), target.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.9), 30, 7.0)
	AudioManager.sfx("fan")
	if hud != null:
		hud.toast("Assassinate!")
		hud.refresh_abilities(self)


func _activate_execution() -> void:
	if float(ability_cds.get("execution", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Execution on cooldown.")
			AudioManager.sfx("ui_error")
		return
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := _nearest_mob_aimed(from, dir, 25.0)
	if target == null:
		if hud != null:
			hud.toast("No target in sight.")
			AudioManager.sfx("ui_error")
		return
	ability_cds["execution"] = 60.0
	var me := int(multiplayer.get_unique_id())
	var base := damage * _buff_mult("damage") * rank_mult()
	var is_boss: bool = (target.get("data") as MobData).is_boss
	var frac := target.hp / maxf(target.max_hp, 0.01)
	var dmg := base * 2.0
	var executed := false
	if not is_boss and frac < 0.15:
		# Instant kill: overwhelming damage routes through the normal death path.
		dmg = 999999.0
		executed = true
	elif is_boss:
		dmg = base * 5.0
	target.rpc_id(NetworkManager.server_id, "take_damage", dmg, me, global_position)
	Effects.burst(get_parent(), target.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.15, 0.1), 35, 8.0)
	if executed:
		AudioManager.sfx("mob_die")
		if hud != null:
			hud.toast("EXECUTED!")
	else:
		AudioManager.sfx("fan")
		if hud != null:
			hud.toast("Execution!")
	if hud != null:
		hud.refresh_abilities(self)


@rpc("any_peer", "call_local")
func heal(amount: float) -> void:
	if not is_multiplayer_authority():
		return
	if not alive:
		return
	hp = minf(max_hp, hp + amount)
	health_changed.emit(hp, max_hp)
	Effects.burst(get_parent(), global_position + Vector3(0, 1.2, 0), Color(0.4, 1.0, 0.5), 8, 3.0)


## War Horn totem: +25% damage while inside the aura (scaled by aura strength).
var _warhorn_t := 0.0
var _warhorn_strength := 1.0


@rpc("any_peer", "call_local")
func apply_warhorn(duration: float, strength: float = 1.0) -> void:
	if not is_multiplayer_authority():
		return
	_warhorn_t = maxf(_warhorn_t, duration)
	_warhorn_strength = strength


@rpc("any_peer", "call_local")
func set_stealthed(s: bool) -> void:
	stealthed = s
	# Visual: translucent for other players' views.
	if _sprite != null:
		_sprite.modulate.a = 0.35 if s else 1.0


## Stoneskin totem: -30% damage taken while in the aura (scaled by aura strength).
var _stoneskin_t := 0.0
var _stoneskin_strength := 1.0


@rpc("any_peer", "call_local")
func apply_stoneskin(duration: float, strength: float = 1.0) -> void:
	if not is_multiplayer_authority():
		return
	_stoneskin_t = maxf(_stoneskin_t, duration)
	_stoneskin_strength = strength


## Rally totem: +30% move speed while in the aura (scaled by aura strength).
var _rally_t := 0.0
var _rally_strength := 1.0


@rpc("any_peer", "call_local")
func apply_rally(duration: float, strength: float = 1.0) -> void:
	if not is_multiplayer_authority():
		return
	_rally_t = maxf(_rally_t, duration)
	_rally_strength = strength


## Shared Vitality (Warden trait): Stoneskin also grants +10% move speed.
var _shared_vitality_t := 0.0


@rpc("any_peer", "call_local")
func apply_shared_vitality(duration: float) -> void:
	if not is_multiplayer_authority():
		return
	_shared_vitality_t = maxf(_shared_vitality_t, duration)


## War Drums (Conqueror trait): Rally also grants +10% attack speed.
var _war_drums_t := 0.0


@rpc("any_peer", "call_local")
func apply_war_drums(duration: float) -> void:
	if not is_multiplayer_authority():
		return
	_war_drums_t = maxf(_war_drums_t, duration)


func _can_act() -> bool:
	return (_cooldown <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and (hud == null or not hud.is_paused))


## Solo-only: switch class. Resets level to 1, clears stat points and
## bonus stats. Inventory is kept.
func switch_class(new_class: String) -> void:
	if not is_multiplayer_authority():
		return
	if multiplayer.get_peers().size() > 0:
		return  # solo only
	class_id = new_class
	class_data = load("res://data/classes/%s.tres" % class_id) as ClassData
	# Reset progression.
	level = 1
	xp = 0
	xp_next = int(25.0 * pow(1, 1.4))
	stat_points = 0
	bonus_damage = 0.0
	bonus_health = 0.0
	bonus_speed = 0.0
	bonus_aura = 0.0
	selected_ability = 0
	ability_cds.clear()
	totem_charges = 1 if class_id == "warrior" else 0
	eagle_eye_used_wave = -1
	# Affinity resets on class switch (collections are per-class anyway).
	specialization = ""
	affinity.clear()
	family_collection.clear()
	_affinity_enemy_cd.clear()
	_recalc_stats()
	hp = max_hp
	health_changed.emit(hp, max_hp)
	xp_changed.emit(xp, xp_next, level)
	# Rebuild visuals.
	_build_sprite()
	_build_aura_visual()
	$Label3D.text = _display_name()
	if _viewmodel != null:
		_viewmodel.queue_free()
		_build_viewmodel()
	_update_staff_glow()
	_push_aura()


# --- Affinity Families ---

## Specialize in a skill. Must be level-unlocked.
func specialize(skill_id: String) -> void:
	var found := false
	for a in Player.class_abilities(str(get("class_id"))):
		if str(a["id"]) == skill_id and int(a["unlock"]) <= level:
			found = true
			break
	if not found:
		return
	specialization = skill_id
	if hud != null:
		hud.toast("Specialized in %s (2x affinity gain)" % skill_id.capitalize())


## Respec: clear specialization, reset the old skill's affinity to 0.
## Family collections persist (they're collections, not builds).
func respec() -> void:
	if specialization != "":
		affinity[specialization] = 0.0
		specialization = ""
		if hud != null:
			hud.toast("Specialization cleared")


## Grant affinity for a skill, with lockout/focus and anti-cheese.
## enemy_id: use -1 for non-enemy events (still requires the skill be specialized).
## Returns the actual points granted (0 if locked out or on cooldown).
func gain_affinity(skill_id: String, points: float, enemy_id: int = -1) -> float:
	# Lockout: only the specialized skill gains.
	if specialization == "" or specialization != skill_id:
		return 0.0
	# No gain while dead.
	if not alive:
		return 0.0
	# Per-enemy 5s cooldown.
	if enemy_id >= 0:
		var key := "%s:%d" % [skill_id, enemy_id]
		var now := Time.get_ticks_msec()
		if _affinity_enemy_cd.has(key) and now - int(_affinity_enemy_cd[key]) < AFFINITY_ENEMY_CD:
			return 0.0
		_affinity_enemy_cd[key] = now
	var gained := points * FOCUS_MULT * AFFINITY_RATE
	var cur := float(affinity.get(skill_id, 0.0))
	affinity[skill_id] = minf(100.0, cur + gained)
	print("[Affinity] %s +%.1f (%.0f/100)" % [skill_id, gained, affinity[skill_id]])
	_check_family_milestones(skill_id)
	return gained


## Grant affinity with a per-cast cap. cast_id groups hits from one cast.
func gain_affinity_capped(skill_id: String, points: float, enemy_id: int, cast_id: String, cap: float) -> float:
	var so_far := float(_affinity_cast_total.get(cast_id, 0.0))
	if so_far >= cap:
		return 0.0
	var granted := gain_affinity(skill_id, minf(points, cap - so_far), enemy_id)
	# Track pre-mult points for the cap.
	_affinity_cast_total[cast_id] = so_far + minf(points, cap - so_far)
	return granted


## Check for family milestone grants after an affinity gain.
func _check_family_milestones(skill_id: String) -> void:
	var fid := Player.family_of(skill_id)
	if fid == "":
		return
	var aff := float(affinity.get(skill_id, 0.0))
	if not family_collection.has(fid):
		family_collection[fid] = {"traits": [], "signature": false}
	var coll: Dictionary = family_collection[fid]
	var fams := Player.families()
	for milestone in [25, 50, 75]:
		if aff >= milestone and not _has_trait(coll, milestone, fams, fid):
			var tdata: Dictionary = fams[fid]["traits"][milestone]
			(coll["traits"] as Array).append(tdata["id"])
			if hud != null:
				hud.toast("Family trait earned: %s — %s" % [tdata["name"], tdata["desc"]])
				AudioManager.sfx("milestone")
	if aff >= 100.0 and not bool(coll.get("signature", false)):
		coll["signature"] = true
		var sig: Dictionary = fams[fid]["signature"]
		if hud != null:
			hud.toast("SIGNATURE SKILL UNLOCKED: %s!" % sig["name"])


func _has_trait(coll: Dictionary, milestone: int, fams: Dictionary, fid: String) -> bool:
	var tid: String = fams[fid]["traits"][milestone]["id"]
	return tid in (coll.get("traits", []) as Array)


## True if the player has a family trait (collections persist across respecs).
func has_trait(trait_id: String) -> bool:
	for fid in family_collection:
		var coll: Dictionary = family_collection[fid]
		if trait_id in (coll.get("traits", []) as Array):
			return true
	return false


## Damage multiplier from family traits for a skill (1.1 if its family's +10% damage trait owned).
func trait_damage_mult(skill_id: String) -> float:
	var fid := Player.family_of(skill_id)
	# Only families with a direct +damage trait are listed; others return 1.0.
	var dmg_traits := {"fire": "kindled", "frost": "deep_chill", "storm": "charged",
		"precision": "true_aim"}
	if dmg_traits.has(fid) and has_trait(dmg_traits[fid]):
		# true_aim only applies to marked/revealed; handled at the hit site, not here.
		if fid == "precision":
			return 1.0
		return 1.1
	return 1.0


## True if the player has unlocked a family's signature skill.
func has_signature(sig_id: String) -> bool:
	for fid in family_collection:
		var coll: Dictionary = family_collection[fid]
		if bool(coll.get("signature", false)):
			var fams := Player.families()
			if fams.has(fid) and str(fams[fid]["signature"]["id"]) == sig_id:
				return true
	return false


## Returns the signature skill dict for a family, or {} if not unlocked.
func family_signature(fid: String) -> Dictionary:
	if not family_collection.has(fid):
		return {}
	var coll: Dictionary = family_collection[fid]
	if not bool(coll.get("signature", false)):
		return {}
	var fams := Player.families()
	if fams.has(fid):
		return fams[fid]["signature"]
	return {}
	refresh_abilities()
	if hud != null:
		hud.refresh_stats()
		hud.refresh_loadout(self)
		hud.refresh_inventory(self)
		hud.set_level(1, self)
		hud.toast("Switched to %s! Level reset to 1." % class_id.capitalize())
	AudioManager.sfx("ability_unlock")


func _physics_process(delta: float) -> void:
	if downed:
		if is_multiplayer_authority():
			_tick_downed(delta)
		return
	if not alive:
		return
	if is_multiplayer_authority():
		_tick_revive_channel(delta)
		var ix := 0.0
		var iz := 0.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			ix -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			ix += 1.0
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			iz -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			iz += 1.0
		var wish := Vector3(ix, 0, iz)
		if wish.length() > 1.0:
			wish = wish.normalized()
		var move_vec: Vector3 = global_transform.basis * wish
		move_vec.y = 0.0
		_dash_cd = maxf(0.0, _dash_cd - delta)
		_warhorn_t = maxf(0.0, _warhorn_t - delta)
		_stoneskin_t = maxf(0.0, _stoneskin_t - delta)
		_rally_t = maxf(0.0, _rally_t - delta)
		_shared_vitality_t = maxf(0.0, _shared_vitality_t - delta)
		_war_drums_t = maxf(0.0, _war_drums_t - delta)
		_sanctuary_t = maxf(0.0, _sanctuary_t - delta)
		# Stealth expires.
		if _stealth_t > 0.0:
			_stealth_t -= delta
			if _stealth_t <= 0.0 and stealthed:
				stealthed = false
				rpc("set_stealthed", false)
				# Unseen trait: first attack after the veil ends crits.
				if has_trait("unseen"):
					unseen_crit_ready = true
		# Ability cooldowns tick.
		var expired := []
		for id in ability_cds:
			ability_cds[id] = maxf(0.0, float(ability_cds[id]) - delta)
			if ability_cds[id] <= 0.0:
				expired.append(id)
		for id in expired:
			ability_cds.erase(id)
		if not expired.is_empty() and hud != null:
			hud.refresh_abilities(self)
		if _dash_t > 0.0:
			_dash_t -= delta
			velocity.x = _dash_dir.x * DASH_SPEED
			velocity.z = _dash_dir.z * DASH_SPEED
			# FOV kick while dashing.
			if _camera != null:
				_camera.fov = lerpf(_camera.fov, 82.0, delta * 12.0)
		else:
			velocity.x = move_vec.x * move_speed * _buff_mult("speed")
			velocity.z = move_vec.z * move_speed * _buff_mult("speed")
			if _camera != null:
				_camera.fov = lerpf(_camera.fov, 75.0, delta * 8.0)
		if _jump_queued:
			_jump_queued = false
			if is_on_floor():
				velocity.y = JUMP_VELOCITY
				AudioManager.sfx("jump")
		var fall_speed := -velocity.y
		if is_on_floor():
			if velocity.y <= 0.0:
				velocity.y = -0.5
		else:
			velocity.y -= GRAVITY * delta
		move_and_slide()
		# Landing thud scaled by fall speed.
		if not _was_on_floor and is_on_floor():
			AudioManager.sfx("land", null, 1.0, clampf(fall_speed / 12.0, 0.25, 1.0))
			if fall_speed > 6.0:
				Effects.burst(get_parent(), global_position + Vector3(0, 0.2, 0), Color(0.7, 0.65, 0.6), 14, 4.0)
		_was_on_floor = is_on_floor()
		# Footsteps while moving on the ground.
		var h_speed := Vector2(velocity.x, velocity.z).length()
		if is_on_floor() and h_speed > 1.5:
			_step_timer -= delta * h_speed
			if _step_timer <= 0.0:
				_step_timer = 4.5
				AudioManager.sfx("footstep", null, randf_range(0.9, 1.1), 0.45)
		else:
			_step_timer = 0.0
		_cooldown = maxf(0.0, _cooldown - delta)
		_update_pickup_prompt()
		_snapshot -= delta
		if _snapshot <= 0.0:
			_snapshot = SNAPSHOT_INTERVAL
			rpc("push_snapshot", global_position, hp, level, alive)
	else:
		if _has_remote:
			global_position = global_position.lerp(_remote_pos, clampf(delta * 10.0, 0.0, 1.0))


func _process(delta: float) -> void:
	if is_multiplayer_authority():
		if _streak_timer > 0.0:
			_streak_timer -= delta
			if _streak_timer <= 0.0:
				_streak_kills = 0
		if _camera != null and _shake > 0.0:
			_shake -= delta
			var s := _shake * 0.3
			_camera.position = _cam_base + Vector3(randf_range(-s, s), randf_range(-s, s), 0.0)
			if _shake <= 0.0:
				_camera.position = _cam_base
		_ping_cd = maxf(0.0, _ping_cd - delta)
		_check_buff_expiry()
	else:
		_bob_t += delta
		if alive:
			_sprite.position.y = 1.0 + sin(_bob_t * 2.2) * 0.04


# --- Combat ---

## Shift dash: burst of speed in the current move direction (or facing
## if standing still), with i-frames for the dash duration.
func _try_dash() -> void:
	if _dash_cd > 0.0 or _dash_t > 0.0:
		return
	var ix := 0.0
	var iz := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		ix -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		ix += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		iz -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		iz += 1.0
	var wish := Vector3(ix, 0, iz)
	if wish.length() < 0.1:
		wish = Vector3(0, 0, -1)  # dash forward when standing still
	_dash_dir = (global_transform.basis * wish.normalized())
	_dash_dir.y = 0.0
	_dash_dir = _dash_dir.normalized()
	_dash_t = DASH_TIME
	_dash_cd = DASH_COOLDOWN
	AudioManager.sfx("dash")
	Effects.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.85, 0.9, 1.0), 10, 3.0)
	if hud != null:
		hud.flash_dash()


func _do_attack() -> void:
	# War Drums: +10% attack speed while the trait buff is active.
	_cooldown = attack_cooldown / (1.1 if _war_drums_t > 0.0 else 1.0)
	_attack_anim()
	if class_id == "mage":
		_cast_spell()
		return
	AudioManager.sfx("swing")
	var from := int(multiplayer.get_unique_id())
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# Unseen trait: first attack after veil/blink crits for 2x.
	var melee_dmg := damage * _buff_mult("damage")
	if unseen_crit_ready:
		melee_dmg *= 2.0
		unseen_crit_ready = false
		Effects.burst(get_parent(), global_position + Vector3(0, 1.2, 0), Color(1.0, 0.9, 0.4), 15, 4.0)
	for node in get_tree().get_nodes_in_group("mobs"):
		var mob := node as Mob
		if mob == null or not mob.alive:
			continue
		var to_mob: Vector3 = mob.global_position - global_position
		to_mob.y = 0.0
		var dist := to_mob.length()
		if dist > attack_range or dist < 0.001:
			continue
		if fwd.angle_to(to_mob / dist) > 0.75:
			continue
		mob.rpc_id(NetworkManager.server_id, "take_damage", melee_dmg, from, global_position)
		# Affinity: hit on marked target → +1 mark, per-enemy 5s cd.
		if mob.is_marked():
			gain_affinity("mark", 1.0, mob.get_instance_id())
	# RTS: damage enemy units and buildings in the Warlord's Domain.
	if rts_faction >= 0:
		_damage_rts_targets(fwd, from)


func _damage_rts_targets(fwd: Vector3, from: int) -> void:
	var dmg := damage * _buff_mult("damage")
	for node in get_tree().get_nodes_in_group("rts_units"):
		if int(node.get("faction")) == rts_faction:
			continue
		if not bool(node.get("alive")):
			continue
		var to: Vector3 = node.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > attack_range or dist < 0.001:
			continue
		if fwd.angle_to(to / dist) > 0.75:
			continue
		node.rpc_id(NetworkManager.server_id, "rpc_take_damage", dmg,
			multiplayer.get_unique_id())
	for node in get_tree().get_nodes_in_group("rts_buildings"):
		if int(node.get("faction")) == rts_faction:
			continue
		var to: Vector3 = node.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > attack_range + 1.0 or dist < 0.001:
			continue
		if fwd.angle_to(to / dist) > 0.75:
			continue
		node.rpc_id(NetworkManager.server_id, "rpc_take_damage", dmg,
			multiplayer.get_unique_id())


func _cast_spell() -> void:
	match _selected_ability_id():
		"frost":
			AudioManager.sfx("frost_cast")
			_cast_frost_shard()
		"lightning":
			AudioManager.sfx("lightning_cast")
			_cast_chain_lightning()
		"meteor":
			AudioManager.sfx("meteor_cast")
			_cast_meteor()
		"barrage":
			AudioManager.sfx("barrage_cast")
			_cast_barrage()
		"blizzard":
			AudioManager.sfx("blizzard_cast")
			_cast_blizzard()
		"holy_light":
			AudioManager.sfx("holy_light_cast")
			_cast_holy_light()
		_:
			AudioManager.sfx("fireball_cast")
			_cast_fireball()


## Holy Light: bathes the whole map in radiant light for 10s. 20s cooldown.
func _cast_holy_light() -> void:
	if float(ability_cds.get("holy_light", 0.0)) > 0.0:
		if hud != null:
			hud.toast("Holy Light on cooldown!")
		return
	ability_cds["holy_light"] = 20.0
	rpc("spawn_holy_light")


@rpc("any_peer", "call_local")
func spawn_holy_light() -> void:
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if dungeons.is_empty():
		return
	var dungeon = dungeons[0]
	var layout = dungeon.get("_layout")
	var center := Vector3.ZERO
	var map_size := 60.0
	if layout != null:
		map_size = float(layout.grid_size) * layout.cell_size
	# Brilliant light from above, covering the entire map.
	var light := OmniLight3D.new()
	light.name = "HolyLight"
	light.position = center + Vector3(0, 25.0, 0)
	light.light_color = Color(1.0, 0.95, 0.8)
	light.light_energy = 0.0
	light.omni_range = map_size * 1.5
	light.shadow_enabled = false
	dungeon.add_child(light)
	AudioManager.sfx("holy_light", center)
	if hud != null:
		hud.toast("HOLY LIGHT!")
	# Fade in, hold 10s, fade out.
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 4.0, 1.0)
	tw.tween_interval(10.0)
	tw.tween_property(light, "light_energy", 0.0, 2.0)
	tw.tween_callback(light.queue_free)


func _cast_fireball() -> void:
	if _camera == null:
		return
	_cast_seq += 1
	var basis := _camera.global_transform.basis
	var dir := -basis.z
	var origin: Vector3 = _camera.global_position + dir * 0.7 + Vector3(0, -0.15, 0)
	var dmg := damage * _buff_mult("damage") * rank_mult() * trait_damage_mult("fireball")
	rpc("cast_fireball", origin, dir.normalized(), dmg, int(multiplayer.get_unique_id()), _cast_seq)


@rpc("any_peer", "call_local")
func cast_fireball(origin: Vector3, dir: Vector3, dmg: float, owner: int, seq: int, skill_tag := "fireball") -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon == null:
		return
	var fb := Fireball.new()
	fb.name = "Proj_%d_%d" % [owner, seq]
	fb.setup(dir * FIREBALL_SPEED, dmg, owner, skill_tag)
	dungeon.get_node("Projectiles").add_child(fb)
	fb.global_position = origin


func _cast_frost_shard() -> void:
	if _camera == null:
		return
	_cast_seq += 1
	var basis := _camera.global_transform.basis
	var dir := -basis.z
	var origin: Vector3 = _camera.global_position + dir * 0.7 + Vector3(0, -0.15, 0)
	var dmg := damage * _buff_mult("damage") * rank_mult() * trait_damage_mult("frost")
	rpc("cast_frost", origin, dir.normalized(), dmg, int(multiplayer.get_unique_id()), _cast_seq)


@rpc("any_peer", "call_local")
func cast_frost(origin: Vector3, dir: Vector3, dmg: float, owner: int, seq: int) -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon == null:
		return
	var fs := FrostShard.new()
	fs.name = "Frost_%d_%d" % [owner, seq]
	fs.setup(dir * 22.0, dmg * 0.7, owner)
	dungeon.get_node("Projectiles").add_child(fs)
	fs.global_position = origin


func _cast_chain_lightning() -> void:
	# Instant: zap nearest mob in 18m, chain to 2 more within 8m of each hit.
	if not multiplayer.is_server():
		# Client predicts the visual; server does damage.
		_chain_lightning_fx(global_position + Vector3(0, 1.2, 0), global_position + Vector3(0, 1.2, 0) + Vector3(0, 0.1, 0))
		return
	_cast_seq += 1
	var from := int(multiplayer.get_unique_id())
	var hit: Array = []
	var current := _nearest_mob(global_position, 18.0, hit)
	var last_pos := global_position + Vector3(0, 1.2, 0)
	var dmg := damage * _buff_mult("damage") * rank_mult() * 0.8 * trait_damage_mult("lightning")
	var cast_id := "lightning_%d" % _cast_seq
	# Arc Conduit: lightning chains +1 target.
	var max_chains := 4 if has_trait("arc_conduit") else 3
	for i in max_chains:
		if current == null:
			break
		hit.append(current)
		var mob_pos: Vector3 = current.global_position + Vector3(0, 1.0, 0)
		# Overcharge: 15% chance to double-strike.
		var zap_dmg := dmg * 2.0 if has_trait("overcharge") and randf() < 0.15 else dmg
		current.rpc_id(NetworkManager.server_id, "take_damage", zap_dmg, from, global_position)
		# Affinity: +2 per enemy zapped, max +8/cast.
		gain_affinity_capped("lightning", 2.0, current.get_instance_id(), cast_id, 8.0)
		rpc("chain_fx", last_pos, mob_pos)
		last_pos = mob_pos
		dmg *= 0.75
		current = _nearest_mob(mob_pos, 8.0, hit)
	if hit.is_empty():
		rpc("chain_fx", last_pos, last_pos + Vector3(0, 0.1, 0))


func _nearest_mob(pos: Vector3, max_dist: float, exclude: Array) -> Mob:
	var best: Mob = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m == null or not m.alive or m in exclude:
			continue
		var d: float = pos.distance_to(m.global_position)
		if d < best_d and _has_los(pos, m.global_position + Vector3(0, 1.0, 0)):
			best_d = d
			best = m
	return best


## Line-of-sight check: true if no wall cells block the segment.
## Used by Chain Lightning so it can't zap through walls.
func _has_los(from: Vector3, to: Vector3) -> bool:
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if dungeons.is_empty():
		return true
	var layout = dungeons[0].get("_layout")
	if layout == null:
		return true
	var dist := from.distance_to(to)
	# Sample every ~0.75m along the segment.
	var steps := maxi(2, int(dist / 0.75))
	for i in range(1, steps):
		var p: Vector3 = from.lerp(to, float(i) / float(steps))
		p.y = 1.0  # check at torso height
		if layout.is_solid_world(p):
			return false
	return true


@rpc("any_peer", "call_local")
func chain_fx(a: Vector3, b: Vector3) -> void:
	_chain_lightning_fx(a, b)


func _chain_lightning_fx(a: Vector3, b: Vector3) -> void:
	# Jagged lightning bolt visual.
	var pts := PackedVector3Array()
	var segments := 6
	for i in segments + 1:
		var t := float(i) / float(segments)
		var p: Vector3 = a.lerp(b, t)
		if i > 0 and i < segments:
			p += Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))
		pts.append(p)
	Effects.lightning(get_parent(), pts, Color(0.7, 0.9, 1.0))
	AudioManager.sfx("lightning_zap", a)


func _cast_meteor() -> void:
	# Target the point under the crosshair (up to 25m); impact after 1s.
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := from + dir * 25.0
	var params := PhysicsRayQueryParameters3D.create(from, target)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	var point: Vector3 = hit["position"] if not hit.is_empty() else target
	point.y = maxf(point.y, 0.1)
	_cast_seq += 1
	var dmg := damage * _buff_mult("damage") * rank_mult() * 2.0 * trait_damage_mult("meteor")
	rpc("cast_meteor", point, dmg, int(multiplayer.get_unique_id()), _cast_seq)


@rpc("any_peer", "call_local")
func cast_meteor(point: Vector3, dmg: float, owner: int, seq: int) -> void:
	# Telegraph ring, then a flaming rock streaks down and impacts.
	Effects.telegraph_ring(get_parent(), point, Meteor.BLAST_RADIUS, Color(1.0, 0.4, 0.1))
	AudioManager.sfx("meteor_incoming", point)
	var meteor := Meteor.new()
	meteor.name = "Meteor_%d_%d" % [owner, seq]
	meteor.setup(point, dmg, owner)
	get_parent().add_child(meteor)


## Arcane Barrage: three fireballs in a spread pattern.
func _cast_barrage() -> void:
	if _camera == null:
		return
	_cast_seq += 1
	var basis := _camera.global_transform.basis
	var base_dir := -basis.z
	var origin: Vector3 = _camera.global_position + base_dir * 0.7 + Vector3(0, -0.15, 0)
	var dmg := damage * _buff_mult("damage") * rank_mult() * 0.6 * trait_damage_mult("barrage")
	for i in [-1, 0, 1]:
		var dir := base_dir.rotated(Vector3.UP, i * 0.12).normalized()
		# Overcharge: 15% chance per bolt to double-strike.
		var bolt_dmg := dmg * 2.0 if has_trait("overcharge") and randf() < 0.15 else dmg
		rpc("cast_fireball", origin, dir, bolt_dmg, int(multiplayer.get_unique_id()), _cast_seq + i, "barrage")


## Blizzard: freezing storm at target point, 4s of damage + slow ticks.
func _cast_blizzard() -> void:
	if _camera == null:
		return
	var from: Vector3 = _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var target := from + dir * 20.0
	var params := PhysicsRayQueryParameters3D.create(from, target)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	var point: Vector3 = hit["position"] if not hit.is_empty() else target
	point.y = maxf(point.y, 0.1)
	_cast_seq += 1
	var blizz_dmg := damage * _buff_mult("damage") * rank_mult() * 0.4 * trait_damage_mult("blizzard")
	rpc("cast_blizzard", point, blizz_dmg, int(multiplayer.get_unique_id()), _cast_seq)


@rpc("any_peer", "call_local")
func cast_blizzard(point: Vector3, dmg: float, owner: int, seq: int) -> void:
	# Snowy visual: blue-white particles falling in the radius.
	var storm := Effects.make_snow()
	storm.amount = 60
	get_parent().add_child(storm)
	storm.global_position = point + Vector3(0, 3.0, 0)
	storm.emitting = true
	AudioManager.sfx("blizzard_loop", point)
	Effects.telegraph_ring(get_parent(), point, 4.0, Color(0.6, 0.85, 1.0))
	# 8 ticks over 4 seconds.
	var cast_id := "blizzard_%d" % seq
	var granted_mobs := {}
	for i in 8:
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree():
			break
		if multiplayer.is_server():
			var dungeon := get_tree().get_first_node_in_group("dungeon")
			var caster: Player = dungeon.get_player_node(owner) as Player if dungeon != null else null
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m == null or not m.alive:
					continue
				if m.global_position.distance_to(point) < 4.0:
					m.rpc_id(NetworkManager.server_id, "take_damage", dmg, owner, point)
					# Permafrost: slows last +2s.
					var bdur := 1.0
					if caster != null and caster.has_trait("permafrost"):
						bdur += 2.0
					m.apply_slow(bdur, 0.5)
					# Affinity: +2 per enemy, once per enemy per cast.
					if caster != null and not granted_mobs.has(m.get_instance_id()):
						granted_mobs[m.get_instance_id()] = true
						caster.gain_affinity("blizzard", 2.0, m.get_instance_id())
	get_parent().get_tree().create_timer(0.5).timeout.connect(storm.queue_free)


# --- Pickups & inventory ---

func _nearest_pickup() -> ItemPickup:
	var best: ItemPickup = null
	var best_d := PICKUP_RANGE
	for node in get_tree().get_nodes_in_group("pickups"):
		var pickup := node as ItemPickup
		if pickup == null or not pickup.is_available():
			continue
		var to: Vector3 = pickup.global_position - global_position
		to.y = 0.0 # horizontal distance only; the loot's hover height shouldn't matter
		var d := to.length()
		if d < best_d:
			best_d = d
			best = pickup
	return best


func _update_pickup_prompt() -> void:
	if hud == null:
		return
	# Revive prompt takes priority over loot.
	if _nearest_downed_teammate() != null:
		if _prompt_pickup != null:
			_prompt_pickup = null
		hud.set_hint("Hold E to revive teammate")
		return
	var p := _nearest_pickup()
	if p != _prompt_pickup:
		_prompt_pickup = p
		if p != null:
			if p.is_key:
				hud.set_pickup_prompt(true, "Take Key")
			elif p.item != null:
				hud.set_pickup_prompt(true, p.item.display_name)
			else:
				hud.set_pickup_prompt(false, "")
		else:
			hud.set_pickup_prompt(false, "")


func _try_pickup() -> void:
	# In supermarket mode, the checkout auto-sells on walk-through;
	# E at a shop pedestal buys potions.
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if not dungeons.is_empty():
		var dungeon = dungeons[0]
		if bool(dungeon.get("is_supermarket")):
			# Check shop pedestals.
			for child in dungeon.get_node_or_null("Pickups").get_children():
				if child.name.begins_with("Shop_") and child.global_position.distance_to(global_position) < 2.5:
					dungeon.rpc("buy_potion", child.get_meta("item_id"), child.get_meta("price"))
					return
	var best := _nearest_pickup()
	if best != null:
		_prompt_pickup = null
		if hud != null:
			hud.set_pickup_prompt(false, "")
		best.request_claim(int(multiplayer.get_unique_id()))
	elif hud != null:
		hud.toast("No loot in reach.")


@rpc("any_peer", "call_local")
func on_sold(amount: int) -> void:
	if not is_multiplayer_authority():
		return
	supermarket_cash += 0  # already added server-side; just toast here
	if hud != null:
		hud.toast("Sold loot for $%d!" % amount)
		AudioManager.sfx("cash_register")


@rpc("any_peer", "call_local")
func on_bought(item_id: String, price: int) -> void:
	if not is_multiplayer_authority():
		return
	if hud != null:
		hud.toast("Bought %s for $%d!" % [item_id.replace("_", " ").capitalize(), price])
		AudioManager.sfx("cash_register")


@rpc("any_peer", "call_local")
func on_buy_failed(price: int) -> void:
	if not is_multiplayer_authority():
		return
	if hud != null:
		hud.toast("Not enough cash! Need $%d." % price)


@rpc("any_peer", "call_local")
func receive_item(item_id: String) -> void:
	if not is_multiplayer_authority():
		return
	var item := ItemDB.get_item(item_id)
	if item == null:
		return
	# Same-type items combine into the existing stack.
	for entry in inventory:
		var e_item := entry["item"] as ItemData
		if e_item != null and e_item.id == item.id:
			entry["count"] = int(entry["count"]) + 1
			_recalc_stats()
			health_changed.emit(hp, max_hp)
			var rare := _pickup_feedback(item)
			if hud != null:
				hud.toast("Picked up: %s (x%d)" % [item.display_name, int(entry["count"])])
				hud.refresh_inventory(self)
				hud.refresh_loadout(self)
				if rare:
					hud.toast("%s %s!" % [ItemData.rarity_name(item.rarity).to_upper(), item.display_name.to_upper()])
			return
	if inventory.size() >= INVENTORY_MAX:
		if hud != null:
			hud.toast("Inventory full! Press I to manage it.")
		return
	inventory.append({"item": item, "count": 1})
	_recalc_stats()
	health_changed.emit(hp, max_hp)
	var rare := _pickup_feedback(item)
	if hud != null:
		hud.toast("Picked up: %s  (I: inventory)" % item.display_name)
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)
		if rare:
			hud.toast("%s %s!" % [ItemData.rarity_name(item.rarity).to_upper(), item.display_name.to_upper()])


## Pickup sound pitched by rarity. Returns true for rare+ finds (caller shows
## a special toast after the normal pickup message).
func _pickup_feedback(item: ItemData) -> bool:
	AudioManager.sfx("pickup", null, 1.0 + float(item.rarity) * 0.12)
	return item.rarity >= ItemData.Rarity.RARE


## Destroy the selected stack entirely.
func dispose_item(index: int) -> void:
	if not is_multiplayer_authority():
		return
	if index < 0 or index >= inventory.size():
		return
	var entry: Dictionary = inventory[index]
	var item := entry["item"] as ItemData
	inventory.remove_at(index)
	_recalc_stats()
	health_changed.emit(hp, max_hp)
	if hud != null:
		hud.toast("Disposed: %s x%d" % [item.display_name, int(entry["count"])])
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)


## Use one consumable from the selected inventory stack.
func use_item(index: int) -> void:
	if not is_multiplayer_authority():
		return
	if not alive:
		return
	if index < 0 or index >= inventory.size():
		return
	var entry: Dictionary = inventory[index]
	var item := entry["item"] as ItemData
	if item == null or not item.consumable:
		if hud != null:
			hud.toast("That item can't be used.")
		return
	var now := Time.get_ticks_msec() / 1000.0
	var effect := ""
	if item.heal_fraction > 0.0:
		var amount := max_hp * item.heal_fraction
		hp = minf(max_hp, hp + amount)
		effect = "+%d HP" % int(amount)
		Effects.burst(get_parent(), global_position + Vector3(0, 1.2, 0), Color(0.3, 1.0, 0.4), 18, 4.0)
	if item.buff_stat != "" and _buffs.has(item.buff_stat):
		_buffs[item.buff_stat]["mult"] = item.buff_mult
		_buffs[item.buff_stat]["until"] = now + item.buff_duration
		_buff_announced[item.buff_stat] = true
		effect += (" " if effect != "" else "") + "+%d%% %s (%ds)" % [
			int((item.buff_mult - 1.0) * 100.0), item.buff_stat, int(item.buff_duration)]
	entry["count"] = int(entry["count"]) - 1
	if int(entry["count"]) <= 0:
		inventory.remove_at(index)
	_recalc_stats()
	health_changed.emit(hp, max_hp)
	AudioManager.sfx("drink")
	if hud != null:
		hud.toast("Used %s: %s" % [item.display_name, effect])
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)


func _buff_mult(stat: String) -> float:
	var mult := 1.0
	var b: Dictionary = _buffs.get(stat, {"mult": 1.0, "until": 0.0})
	if Time.get_ticks_msec() / 1000.0 < float(b["until"]):
		mult *= float(b["mult"])
	# War Horn totem aura: +25% damage, scaled by Warden/Conqueror aura strength.
	if stat == "damage" and _warhorn_t > 0.0:
		mult *= 1.0 + 0.25 * _warhorn_strength
	# Rally totem aura: +30% speed, scaled by aura strength.
	if stat == "speed" and _rally_t > 0.0:
		mult *= 1.0 + 0.3 * _rally_strength
	# Shared Vitality: Stoneskin also grants +10% move speed.
	if stat == "speed" and _shared_vitality_t > 0.0:
		mult *= 1.1
	return mult


func _check_buff_expiry() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for stat in ["speed", "damage"]:
		if _buff_announced.get(stat, false) and now >= float(_buffs[stat]["until"]):
			_buff_announced[stat] = false
			if hud != null:
				hud.toast("%s boost wore off." % stat.capitalize())


@rpc("any_peer", "call_local")
func take_damage(amount: float, attacker_name: String = "") -> void:
	if not is_multiplayer_authority():
		return
	if not alive:
		return
	# Pause menu = breather: mobs keep acting, but a paused player's
	# health doesn't budge. Per-peer, so multiplayer keeps working.
	if hud != null and hud.is_paused:
		return
	# Dash i-frames.
	if _dash_t > 0.0:
		return
	# Sanctuary Totem (Warden signature): complete damage immunity.
	if _sanctuary_t > 0.0:
		return
	# Stoneskin: -30% damage taken, scaled by Warden aura strength.
	if _stoneskin_t > 0.0:
		amount *= 1.0 - 0.3 * _stoneskin_strength
	# Remember who hit us so the death screen can name the killer.
	if not attacker_name.is_empty():
		run_death_cause = attacker_name
	hp = maxf(0.0, hp - amount)
	_shake = 0.3
	health_changed.emit(hp, max_hp)
	AudioManager.sfx("player_hurt")
	if hud != null:
		hud.flash_damage()
	if hp <= 0.0:
		_die()


func _die() -> void:
	# In co-op, go down instead of dying outright — a teammate can revive.
	if not downed and multiplayer.get_peers().size() > 0:
		_enter_downed()
		return
	_do_death()


func _enter_downed() -> void:
	downed = true
	alive = false
	_bleedout = REVIVE_WINDOW
	_revive_channel = 0.0
	died.emit()
	AudioManager.sfx("player_die")
	rpc("set_downed", true)
	if hud != null:
		hud.show_downed(REVIVE_WINDOW)


@rpc("any_peer", "call_local")
func set_downed(d: bool) -> void:
	downed = d
	if not d:
		return
	# Remote visual: handled by nameplate/HUD on each peer's own instance.


## Called on the downed player's authority by a teammate's revive channel.
@rpc("any_peer", "call_local")
func revive() -> void:
	if not is_multiplayer_authority():
		return
	if not downed:
		return
	downed = false
	_bleedout = 0.0
	alive = true
	hp = max_hp * 0.5
	health_changed.emit(hp, max_hp)
	rpc("set_downed", false)
	AudioManager.sfx("revive")
	if hud != null:
		hud.hide_downed()
		hud.toast("Revived! Back in the fight.")


func _do_death() -> void:
	downed = false
	alive = false
	died.emit()
	AudioManager.sfx("player_die")
	inventory.clear()
	_recalc_stats()
	if hud != null:
		hud.hide_downed()
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)
	die()


## Death presentation. In solo the run ends here: show the death screen
## with run stats (no auto-respawn). In co-op the party keeps playing, so
## the toast + 3s respawn path is kept.
func die() -> void:
	if multiplayer.get_peers().size() == 0:
		# Solo run over: the save point is gone.
		# Record daily attempt if this was today's seed.
		if Dungeon.next_seed == DailyRun.get_today_seed():
			var stats := run_stats()
			var score := int(stats.get("cycle", 1)) * 1000 + int(stats.get("level", 1)) * 10 + int(stats.get("kills", 0))
			DailyRun.record_attempt(score)
		SaveManager.clear_run(str(get("class_id")))
		if hud != null:
			hud.show_death_screen(run_stats())
		return
	# Multiplayer: check for party wipe (server clears the run).
	# Route through the server since die() runs on the player's authority.
	var dgn := get_tree().get_first_node_in_group("dungeon")
	if dgn != null and dgn.has_method("notify_player_died"):
		dgn.rpc_id(NetworkManager.server_id, "notify_player_died")
	if hud != null:
		hud.toast("You died! You lost all your items.")
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon != null:
		global_position = dungeon.get_spawn_point()
	hp = max_hp
	alive = true
	health_changed.emit(hp, max_hp)


## Run statistics for the death screen. Persists across level transitions
## (saved in get_state), resets on a new run (play_solo clears the save).
func run_stats() -> Dictionary:
	var cycle := 1
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if dungeon != null:
		cycle = dungeon.get_cycle_number()
	var secs := maxi(0, int((Time.get_ticks_msec() - run_start_msec) / 1000))
	return {
		"time_sec": secs,
		"kills": run_kills,
		"level": level,
		"cycle": cycle,
		"damage": run_damage_dealt,
		"cause": run_death_cause,
	}


@rpc("any_peer", "call_local")
func gain_xp(amount: int) -> void:
	if not is_multiplayer_authority():
		return
	xp += int(amount * xp_mult)
	_register_kill()
	var grew := false
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = int(25.0 * pow(level, 1.4))
		stat_points += 3
		grew = true
		leveled_up.emit(level)
	_recalc_stats()
	xp_changed.emit(xp, xp_next, level)
	if grew:
		Effects.burst(get_parent(), global_position + Vector3(0, 1.2, 0), Color(1.0, 0.8, 0.2), 26, 6.0)
		AudioManager.sfx("levelup")
		var new_ability := refresh_abilities()
		_update_staff_glow()
		_push_aura()
		_check_milestone()
		if hud != null:
			hud.toast("Level up! +3 stat points (Esc to spend).")
			if not new_ability.is_empty():
				hud.toast("New ability unlocked: %s!" % String(new_ability["name"]))
				AudioManager.sfx("ability_unlock")
			hud.refresh_loadout(self)


func _check_milestone() -> void:
	var names := {25: "Milestone: +10% damage & health!", 50: "Milestone: +10% damage & health!",
		75: "Milestone: +15% damage & health!", 100: "PARAGON! +25% to everything!"}
	if names.has(level):
		_recalc_stats()
		AudioManager.sfx("milestone")
		if hud != null:
			hud.announce(String(names[level]))


var _streak_kills := 0
var _streak_timer := 0.0


## Multi-kill announcements: 2 = Double Kill, 3 = Triple Kill, 4+ = Rampage.
func _register_kill() -> void:
	run_kills += 1
	_streak_kills += 1
	_streak_timer = 3.0
	# Affinity: kill while veiled → +1 smoke_veil, max +10/activation.
	if stealthed:
		gain_affinity_capped("smoke_veil", 1.0, -1, "veil_%d" % _cast_seq, 10.0)
	if hud == null:
		return


@rpc("any_peer", "call_local")
func notify_mark_kill() -> void:
	if not is_multiplayer_authority():
		return
	gain_affinity("mark", 3.0)
	match _streak_kills:
		2:
			hud.announce("DOUBLE KILL!")
			AudioManager.sfx("pickup", null, 1.3)
		3:
			hud.announce("TRIPLE KILL!")
			AudioManager.sfx("pickup", null, 1.45)
		4:
			hud.announce("RAMPAGE!")
			AudioManager.sfx("levelup", null, 1.2)


## Spend one stat point. Returns false when there is nothing to spend.
func spend_point(stat: String) -> bool:
	if stat_points <= 0:
		return false
	match stat:
		"damage":
			bonus_damage += 2.0
		"health":
			bonus_health += 12.0
			hp += 12.0
		"speed":
			bonus_speed += 0.15
		"aura":
			if class_id != "mage":
				return false
			if bonus_aura >= 20.0:
				return false  # capped at 20
			bonus_aura += 1.0
			_update_staff_glow()
			_push_aura()
			if bonus_aura >= 20.0 and hud != null:
				hud.toast("Aura MAXED! Holy Light unlocked!")
				AudioManager.sfx("ability_unlock")
				refresh_abilities()
		_:
			return false
	stat_points -= 1
	_recalc_stats()
	hp = minf(hp, max_hp)
	health_changed.emit(hp, max_hp)
	if hud != null:
		hud.refresh_stats()
		hud.refresh_loadout(self)
	return true


## Serialize run-persistent state so it survives procedural level transitions.
func get_state() -> Dictionary:
	var inv: Array = []
	for entry in inventory:
		var item := entry["item"] as ItemData
		if item != null:
			inv.append({"id": item.id, "count": int(entry["count"])})
	return {
		"level": level,
		"xp": xp,
		"xp_next": xp_next,
		"stat_points": stat_points,
		"bonus_damage": bonus_damage,
		"bonus_health": bonus_health,
		"bonus_speed": bonus_speed,
		"bonus_aura": bonus_aura,
		"inventory": inv,
		"run_start_msec": run_start_msec,
		"run_kills": run_kills,
		"run_damage_dealt": run_damage_dealt,
		"supermarket_cash": supermarket_cash,
		"totem_charges": totem_charges,
		"specialization": specialization,
		"affinity": affinity.duplicate(true),
		"family_collection": family_collection.duplicate(true),
	}


## Restore state after a level transition. Full heal on arrival.
func apply_state(s: Dictionary) -> void:
	level = int(s.get("level", 1))
	xp = int(s.get("xp", 0))
	xp_next = int(s.get("xp_next", 25))
	stat_points = int(s.get("stat_points", 0))
	bonus_damage = float(s.get("bonus_damage", 0.0))
	bonus_health = float(s.get("bonus_health", 0.0))
	bonus_speed = float(s.get("bonus_speed", 0.0))
	bonus_aura = float(s.get("bonus_aura", 0.0))
	run_start_msec = int(s.get("run_start_msec", Time.get_ticks_msec()))
	run_kills = int(s.get("run_kills", 0))
	run_damage_dealt = float(s.get("run_damage_dealt", 0.0))
	supermarket_cash = int(s.get("supermarket_cash", 0))
	totem_charges = int(s.get("totem_charges", 0))
	specialization = str(s.get("specialization", ""))
	affinity = (s.get("affinity", {}) as Dictionary).duplicate(true)
	family_collection = (s.get("family_collection", {}) as Dictionary).duplicate(true)
	inventory.clear()
	for e in s.get("inventory", []):
		var item := ItemDB.get_item(str(e.get("id", "")))
		if item != null:
			inventory.append({"item": item, "count": maxi(1, int(e.get("count", 1)))})
	alive = true
	_recalc_stats()
	_update_staff_glow()
	_push_aura()
	refresh_abilities()
	hp = max_hp
	health_changed.emit(hp, max_hp)
	xp_changed.emit(xp, xp_next, level)
	if hud != null:
		hud.refresh_inventory(self)
		hud.refresh_loadout(self)
		hud.refresh_stats()


@rpc("any_peer", "call_local", "unreliable")
func push_snapshot(pos: Vector3, hp_v: float, lvl: int, alive_v: bool) -> void:
	if is_multiplayer_authority():
		return
	_remote_pos = pos
	_has_remote = true
	hp = hp_v
	level = lvl
	alive = alive_v


@rpc("any_peer", "call_local", "reliable")
func show_achievement_unlock(achievement_ids: Array) -> void:
	# Shows achievement unlock toasts.
	if hud == null:
		return
	for ach_id in achievement_ids:
		var progress: Dictionary = SaveManager.get_achievement_progress(str(ach_id))
		if not progress.is_empty():
			hud.show_toast("ACHIEVEMENT: %s — %s" % [progress["name"], progress["desc"]])
			AudioManager.sfx("unlock")
