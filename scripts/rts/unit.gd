class_name RTSUnit
extends CharacterBody3D
## Small-scale RTS unit (~0.6m tall). Villagers gather, troops fight.
## Server-authoritative for HP and state.

var faction: int = 0
var unit_type: String = "villager"
var civ: CivData = null

var hp: float = 50.0
var max_hp: float = 50.0
var damage: float = 5.0
var attack_range: float = 1.5
var move_speed: float = 3.0
var alive: bool = true
var _sync_tick := 0.0

# Orders.
var _move_target: Vector3 = Vector3.INF
var _sprite: Sprite3D = null
var _attack_target: Node3D = null
var _gather_node: RTSResourceNode = null
var _gather_tick := 0.0
# Trade route state (trade_cart only).
var _home_market: Node3D = null
var _trade_target: Node3D = null
var _trade_heading_out := true # true = going to target, false = returning home.
# Construction state.
var _build_target: Node3D = null
# Monk conversion state.
var _convert_target: Node3D = null
var _convert_timer := 0.0
var _convert_ring: MeshInstance3D = null
# Fishing ship passive gather.
var _fish_tick := 0.0
# Selection ring (RTS command view).
var _select_ring: MeshInstance3D = null
var _select_t := 0.0
# Floating HP bar.
var _hp_fill: MeshInstance3D = null
var _hp_bg: MeshInstance3D = null
var _hp_bar_w := 1.0


@rpc("any_peer", "call_local")
func set_selected(on: bool) -> void:
	if on:
		if _select_ring == null or not is_instance_valid(_select_ring):
			_select_ring = MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.42
			tm.outer_radius = 0.58
			_select_ring.mesh = tm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.25, 1.0, 0.35)
			mat.emission_enabled = true
			mat.emission = Color(0.25, 1.0, 0.35)
			mat.emission_energy_multiplier = 1.5
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_select_ring.material_override = mat
			# Flat on the ground (not billboarded) so it reads as a ring from top-down.
			_select_ring.rotation = Vector3.ZERO
			_select_ring.position = Vector3(0, 0.08, 0)
			add_child(_select_ring)
		_select_ring.visible = true
		_select_t = 0.0
	elif _select_ring != null and is_instance_valid(_select_ring):
		_select_ring.visible = false


## Gentle pulse on the selection ring so it catches the eye.
func _process_select_ring(delta: float) -> void:
	if _select_ring == null or not is_instance_valid(_select_ring) or not _select_ring.visible:
		return
	_select_t += delta
	var s := 1.0 + 0.12 * sin(_select_t * 6.0)
	_select_ring.scale = Vector3(s, 1.0, s)

# AoE-style conversion: channel time and leash range (tunable via [monks]).
const CONVERT_TIME := 5.0
const CONVERT_RANGE := 6.0


func _convert_time() -> float:
	return RTSTuning.get_float("monks", "convert_time", CONVERT_TIME)


func _convert_range() -> float:
	return RTSTuning.get_float("monks", "convert_range", CONVERT_RANGE)

# Base stats per type.
const BASE_STATS := {
	"villager": {"hp": 40.0, "dmg": 3.0, "range": 1.2, "speed": 3.2},
	"spearman": {"hp": 80.0, "dmg": 8.0, "range": 1.5, "speed": 3.0},
	"archer": {"hp": 50.0, "dmg": 10.0, "range": 8.0, "speed": 3.0},
	"knight": {"hp": 140.0, "dmg": 14.0, "range": 1.8, "speed": 3.8},
	"trade_cart": {"hp": 60.0, "dmg": 0.0, "range": 0.0, "speed": 4.0},
	"catapult": {"hp": 80.0, "dmg": 40.0, "range": 15.0, "speed": 2.0},
	"ram": {"hp": 200.0, "dmg": 25.0, "range": 2.0, "speed": 2.5},
	"monk": {"hp": 40.0, "dmg": 0.0, "range": 0.0, "speed": 2.8},
	"fishing_ship": {"hp": 80.0, "dmg": 0.0, "range": 0.0, "speed": 3.5},
	"war_galley": {"hp": 120.0, "dmg": 15.0, "range": 10.0, "speed": 3.0},
}

# Unit types that never auto-attack (economic units).
const NO_AUTO_ATTACK := ["villager", "trade_cart", "monk", "fishing_ship"]


func _ready() -> void:
	add_to_group("rts_units")
	# setup() already built the visual; only rebuild if it wasn't.
	if _sprite == null or not is_instance_valid(_sprite):
		_build_visual()


func setup(p_faction: int, p_type: String, p_civ: CivData) -> void:
	faction = p_faction
	unit_type = p_type
	civ = p_civ
	var stats: Dictionary = RTSTuning.get_dict(
		"unit_stats", p_type, BASE_STATS.get(p_type, BASE_STATS["villager"]))
	max_hp = float(stats["hp"])
	damage = float(stats["dmg"])
	attack_range = float(stats["range"])
	move_speed = float(stats["speed"])
	# Apply civ bonuses.
	if civ:
		if p_type == "spearman":
			max_hp *= civ.spearman_hp_mult
			damage *= civ.spearman_dmg_mult
		elif p_type == "archer":
			damage *= civ.archer_dmg_mult
			attack_range *= civ.archer_range_mult
		elif p_type == "knight":
			damage *= civ.knight_dmg_mult
			max_hp *= civ.knight_hp_mult
		move_speed *= civ.move_speed_mult
	hp = max_hp
	# Rebuild visual now that we know the type and civ.
	_build_visual()


func _build_visual() -> void:
	# Remove old visual if rebuilding.
	if _sprite and is_instance_valid(_sprite):
		_sprite.get_parent().remove_child(_sprite)
		_sprite.queue_free()
		_sprite = null
	# Free old HP bar nodes too (convert_to rebuilds the visual).
	if _hp_bg and is_instance_valid(_hp_bg):
		_hp_bg.get_parent().remove_child(_hp_bg)
		_hp_bg.queue_free()
		_hp_bg = null
	if _hp_fill and is_instance_valid(_hp_fill):
		_hp_fill.get_parent().remove_child(_hp_fill)
		_hp_fill.queue_free()
		_hp_fill = null
	# Billboard 3D sprite (~0.9m tall). Civ-specific: iron_vanguard_spearman.png etc.
	var sprite := Sprite3D.new()
	sprite.name = "UnitSprite"
	var tex_path := ""
	if civ:
		tex_path = "res://assets/sprites/rts/%s_%s.png" % [civ.civ_id, unit_type]
	# Fallback to generic sprite.
	if tex_path == "" or not ResourceLoader.exists(tex_path):
		tex_path = "res://assets/sprites/rts/%s.png" % unit_type
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path) as Texture2D
	sprite.pixel_size = 0.0035  # ~0.9m tall for a 256px sprite.
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position.y = 0.45
	add_child(sprite)
	_sprite = sprite

	# Collision (small capsule) — only create once.
	if get_node_or_null("UnitCollision") == null:
		var col := CollisionShape3D.new()
		col.name = "UnitCollision"
		var shape := CapsuleShape3D.new()
		shape.radius = 0.15
		shape.height = 0.5
		col.shape = shape
		col.position.y = 0.25
		add_child(col)

	# Floating HP bar (billboarded, hidden at full HP).
	_hp_bar_w = 1.0
	var ubg := MeshInstance3D.new()
	var ubgm := BoxMesh.new()
	ubgm.size = Vector3(_hp_bar_w, 0.09, 0.02)
	ubg.mesh = ubgm
	var ubgmat := StandardMaterial3D.new()
	ubgmat.albedo_color = Color(0.08, 0.08, 0.08, 0.85)
	ubgmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ubgmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ubg.material_override = ubgmat
	ubg.position = Vector3(0, 1.05, 0)
	add_child(ubg)
	_hp_bg = ubg
	_hp_fill = MeshInstance3D.new()
	var ufm := BoxMesh.new()
	ufm.size = Vector3(_hp_bar_w - 0.08, 0.06, 0.02)
	_hp_fill.mesh = ufm
	var ufmat := StandardMaterial3D.new()
	ufmat.albedo_color = Color(0.25, 0.85, 0.3)
	ufmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ufmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill.material_override = ufmat
	_hp_fill.position = Vector3(0, 1.05, 0.005)
	add_child(_hp_fill)
	_update_hp_bar()


## Refresh the unit HP bar; hidden at full HP.
func _update_hp_bar() -> void:
	if _hp_fill == null:
		return
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_hp_fill.scale.x = maxf(frac, 0.001)
	_hp_fill.position.x = -(_hp_bar_w - 0.08) * 0.5 * (1.0 - frac)
	var mat := _hp_fill.material_override as StandardMaterial3D
	if mat != null:
		if frac > 0.5:
			mat.albedo_color = Color(0.25, 0.85, 0.3)
		elif frac > 0.25:
			mat.albedo_color = Color(0.95, 0.8, 0.2)
		else:
			mat.albedo_color = Color(0.9, 0.25, 0.2)
	var show := frac < 1.0 and alive
	_hp_fill.visible = show
	if _hp_bg != null and is_instance_valid(_hp_bg):
		_hp_bg.visible = show


func order_move(pos: Vector3) -> void:
	_move_target = pos
	_attack_target = null
	_gather_node = null
	_build_target = null
	_clear_trade()
	_cancel_convert()


## Verify the RPC sender owns this unit's faction. AI (peer -1) always passes.
func _owns_me() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:  # local call
		return true
	var mgr := get_tree().get_first_node_in_group("rts_manager") as RTSManager
	if mgr == null:
		return false
	var owner := int(mgr.faction_peers.get(faction, -2))
	return owner == sender or owner == -1


## RPC version for the RTS camera (clients can't pass nodes over the network).
@rpc("any_peer", "call_local")
func rpc_order_move(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if not _owns_me():
		return
	order_move(pos)


func order_gather(node: RTSResourceNode) -> void:
	if unit_type != "villager":
		return
	_gather_node = node
	_attack_target = null
	_build_target = null
	_move_target = Vector3.INF
	_clear_trade()
	_cancel_convert()


## RPC version for the RTS camera.
@rpc("any_peer", "call_local")
func rpc_order_gather(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if not _owns_me():
		return
	var node := get_node_or_null(target_path) as RTSResourceNode
	if node != null:
		order_gather(node)


func order_attack(target: Node3D) -> void:
	_attack_target = target
	_move_target = Vector3.INF
	_gather_node = null
	_build_target = null
	_clear_trade()
	_cancel_convert()


## RPC version for the RTS camera.
@rpc("any_peer", "call_local")
func rpc_order_attack(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if not _owns_me():
		return
	var target := get_node_or_null(target_path) as Node3D
	if target != null:
		order_attack(target)


## Monk conversion: channel on an enemy unit for CONVERT_TIME seconds.
## Monks cannot convert buildings, other monks, or trade carts.
@rpc("any_peer", "call_local")
func order_convert(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if unit_type != "monk" or not alive:
		return
	var target := get_node_or_null(target_path) as Node3D
	if target == null or not is_instance_valid(target):
		return
	if not target.is_in_group("rts_units"):
		return
	if int(target.get("faction")) == faction:
		return
	if not bool(target.get("alive")):
		return
	var ttype := str(target.get("unit_type"))
	if ttype == "monk" or ttype == "trade_cart":
		return
	_cancel_convert()
	_attack_target = null
	_gather_node = null
	_move_target = Vector3.INF
	_clear_trade()
	_convert_target = target
	_convert_timer = 0.0
	target.rpc("set_convert_highlight", true)


## Called on the conversion target: show/hide the golden channel ring.
@rpc("any_peer", "call_local")
func set_convert_highlight(on: bool) -> void:
	if on:
		if _convert_ring == null or not is_instance_valid(_convert_ring):
			_convert_ring = MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.3
			tm.outer_radius = 0.42
			_convert_ring.mesh = tm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.85, 0.3)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			_convert_ring.material_override = mat
			_convert_ring.position = Vector3(0, 0.15, 0)
			add_child(_convert_ring)
		_convert_ring.visible = true
	elif _convert_ring != null and is_instance_valid(_convert_ring):
		_convert_ring.visible = false


func _cancel_convert() -> void:
	if _convert_target != null and is_instance_valid(_convert_target):
		_convert_target.rpc("set_convert_highlight", false)
	_convert_target = null
	_convert_timer = 0.0


## Switch this unit to a new faction (monk conversion). Server-side.
func convert_to(new_faction: int, new_civ: CivData) -> void:
	if not multiplayer.is_server():
		return
	_apply_convert(new_faction, new_civ.civ_id)
	rpc("client_convert", new_faction, new_civ.civ_id)


@rpc("any_peer", "call_local")
func client_convert(new_faction: int, new_civ_id: String) -> void:
	if multiplayer.is_server():
		return
	_apply_convert(new_faction, new_civ_id)


func _apply_convert(new_faction: int, new_civ_id: String) -> void:
	_cancel_convert()
	_attack_target = null
	_gather_node = null
	_move_target = Vector3.INF
	_clear_trade()
	faction = new_faction
	civ = CivData.for_civ_id(new_civ_id)
	_build_visual()


@rpc("any_peer", "call_local")
func convert_fx() -> void:
	Effects.burst(get_parent(), global_position + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.3), 24, 5.0)
	AudioManager.sfx("revive", global_position)


## Trade cart: shuttle between home market and target market, generating gold.
func order_trade(target_market: Node3D) -> void:
	if unit_type != "trade_cart":
		return
	if target_market == null or not is_instance_valid(target_market):
		return
	# No self-trading: routing a cart to your own market would be a
	# zero-distance loop printing min_payout gold every trip (infinite gold).
	if int(target_market.get("faction")) == faction:
		return
	# Home market = nearest friendly market to current position.
	_home_market = _find_nearest_market(faction)
	_trade_target = target_market
	_trade_heading_out = true
	_attack_target = null
	_gather_node = null
	_build_target = null
	_move_target = Vector3.INF


## RPC version for the RTS camera.
@rpc("any_peer", "call_local")
func rpc_order_trade(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if not _owns_me():
		return
	var market := get_node_or_null(target_path) as Node3D
	if market != null:
		order_trade(market)


## Villager: walk to a building under construction and build it.
func order_build(building: Node3D) -> void:
	if unit_type != "villager":
		return
	_build_target = building
	_attack_target = null
	_gather_node = null
	_move_target = Vector3.INF
	_clear_trade()
	_cancel_convert()


## RPC version for construction orders.
@rpc("any_peer", "call_local")
func rpc_order_build(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if not _owns_me():
		return
	var building := get_node_or_null(target_path) as Node3D
	if building != null:
		order_build(building)


func _clear_trade() -> void:
	_home_market = null
	_trade_target = null
	_trade_heading_out = true


func _find_nearest_market(p_faction: int) -> Node3D:
	var best: Node3D = null
	var best_d := 999999.0
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if int(b.get("faction")) != p_faction:
			continue
		if str(b.get("building_type")) != "market":
			continue
		var d := global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func take_damage(amount: float, attacker: Node3D = null) -> void:
	if not multiplayer.is_server():
		# Client: route to server.
		rpc_id(NetworkManager.server_peer_id, "rpc_take_damage", amount,
			attacker.get_multiplayer_authority() if attacker != null else 0)
		return
	_apply_damage(amount)


@rpc("any_peer", "call_local")
func rpc_take_damage(amount: float, attacker_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_apply_damage(amount)


func _apply_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		alive = false
		_die()
		return
	_update_hp_bar()
	rpc("sync_unit_hp", hp)


@rpc("any_peer", "call_local")
func sync_unit_hp(new_hp: float) -> void:
	hp = new_hp
	_update_hp_bar()


func _die() -> void:
	# Small poof, then free. Broadcast so clients despawn too.
	_cancel_convert()
	rpc("set_selected", false)
	rpc("client_unit_died")
	var mgr := get_tree().get_first_node_in_group("rts_manager") as RTSManager
	if mgr:
		mgr.check_elimination()
	queue_free()


@rpc("any_peer", "call_local")
func client_unit_died() -> void:
	if multiplayer.is_server():
		return
	# Play death FX locally, then free.
	_cancel_convert()
	set_selected(false)
	queue_free()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not alive:
		return

	# Ships float at water level (river surface is at y=0.08).
	if _is_ship():
		global_position.y = 0.08
	# Safety: the map is flat — never let land units leave the ground plane.
	# Dense crowds can pop units skyward via collision resolution (units have
	# no gravity); without this they'd hover forever, out of attack range.
	if not _is_ship() and (global_position.y < -1.0 or global_position.y > 1.5):
		global_position = Vector3(global_position.x, 0.0, global_position.z)
		velocity.y = 0.0

	# Trade cart behavior: shuttle between markets.
	if unit_type == "trade_cart" and _trade_target != null:
		_process_trade(delta)
		return

	# Monk conversion behavior.
	if _convert_target != null:
		_convert_tick(delta)
		return

	# Villager construction behavior.
	if _build_target != null and is_instance_valid(_build_target):
		var bdist := global_position.distance_to(_build_target.global_position)
		if bdist <= 3.0:
			# In range: build.
			if _build_target.has_method("add_build_work") and bool(_build_target.get("under_construction")):
				_build_target.add_build_work(delta)
			else:
				_build_target = null  # done or destroyed
			velocity = Vector3.ZERO
			move_and_slide()
			return
		else:
			# Walk to the site.
			var bdir := (_build_target.global_position - global_position).normalized()
			velocity = Vector3(bdir.x, 0, bdir.z) * move_speed
			move_and_slide()
			return
	elif _build_target != null:
		_build_target = null  # target freed

	# Fishing ships passively gather food while on water.
	if unit_type == "fishing_ship":
		_fish_tick -= delta
		if _fish_tick <= 0.0:
			_fish_tick = RTSTuning.get_float("naval", "fish_interval", 2.0)
			if _is_on_water(global_position):
				var mgr := get_tree().get_first_node_in_group("rts_manager") as RTSManager
				if mgr != null:
					var amt := RTSTuning.get_int("naval", "fish_amount", 5)
					mgr.add_resource(faction, "food", amt)
					mgr.sim_bump(faction, "fish_food", amt)

	# Auto-attack nearest enemy (combat units only).
	if not unit_type in NO_AUTO_ATTACK and _attack_target == null:
		_attack_target = _find_nearest_enemy(8.0)

	# Attack behavior.
	if is_instance_valid(_attack_target):
		var dist := global_position.distance_to(_attack_target.global_position)
		if dist <= attack_range:
			# In range: attack.
			velocity = Vector3.ZERO
			_attack_tick(delta, _attack_target)
		else:
			# Move toward target. If the target is a building, don't let
			# building-avoidance push us away from it (see _move_toward).
			var skip_b: Node3D = _attack_target if _attack_target.is_in_group("rts_buildings") else null
			_move_toward(_attack_target.global_position, delta, skip_b)
		move_and_slide()
		return
	elif _attack_target != null:
		_attack_target = null

	# Gather behavior (villagers).
	if _gather_node != null and is_instance_valid(_gather_node):
		var dist := global_position.distance_to(_gather_node.global_position)
		if dist <= 1.5:
			velocity = Vector3.ZERO
			_gather_tick -= delta
			if _gather_tick <= 0.0:
				_gather_tick = RTSTuning.get_float("economy", "gather_tick", 1.0)
				_do_gather()
		else:
			_move_toward(_gather_node.global_position, delta)
		move_and_slide()
		return
	elif _gather_node != null:
		_gather_node = null

	# Move behavior.
	if _move_target != Vector3.INF:
		var dist := global_position.distance_to(_move_target)
		if dist < 0.3:
			_move_target = Vector3.INF
			velocity = Vector3.ZERO
		else:
			_move_toward(_move_target, delta)
		move_and_slide()
	else:
		velocity = Vector3.ZERO
		move_and_slide()
	# Replicate transform to clients ~12 Hz (unreliable).
	_sync_tick += delta
	if _sync_tick >= 0.08:
		_sync_tick = 0.0
		rpc("sync_transform", global_position, rotation.y, hp)


@rpc("any_peer", "unreliable")
func sync_transform(pos: Vector3, rot_y: float, new_hp: float) -> void:
	if multiplayer.is_server():
		return
	global_position = pos
	rotation.y = rot_y
	if absf(hp - new_hp) > 0.01:
		hp = new_hp
		_update_hp_bar()


var _attack_cd := 0.0

func _attack_tick(delta: float, target: Node3D) -> void:
	_attack_cd -= delta
	if _attack_cd > 0.0:
		return
	_attack_cd = RTSTuning.get_float("units", "attack_cooldown", 1.0)
	if target.has_method("take_damage"):
		var dmg := damage
		var is_bldg := target.is_in_group("rts_buildings")
		# Siege bonuses vs buildings.
		if unit_type == "catapult" and is_bldg:
			dmg *= RTSTuning.get_float("siege", "catapult_vs_building", 3.0)
		elif unit_type == "ram":
			if is_bldg:
				dmg *= RTSTuning.get_float("siege", "ram_vs_building", 4.0)
			else:
				dmg *= RTSTuning.get_float("siege", "ram_vs_unit", 0.25)
		target.take_damage(dmg, self)


func _do_gather() -> void:
	if _gather_node == null or not is_instance_valid(_gather_node):
		return
	var mgr := get_tree().get_first_node_in_group("rts_manager") as RTSManager
	if mgr == null:
		return
	var rate := RTSTuning.get_float("economy", "gather_rate", 8.0) * mgr.get_gather_mult(faction)
	var gathered: int = _gather_node.gather(int(rate))
	if gathered > 0:
		mgr.add_resource(faction, _gather_node.resource_type, gathered)


## Trade loop: head to target market, earn gold by distance, return home, repeat.
func _process(_delta: float) -> void:
	_process_select_ring(_delta)


func _process_trade(delta: float) -> void:
	var dest: Node3D = _trade_target if _trade_heading_out else _home_market
	if dest == null or not is_instance_valid(dest):
		# Market destroyed: stop trading.
		_clear_trade()
		velocity = Vector3.ZERO
		move_and_slide()
		return
	var dist := global_position.distance_to(dest.global_position)
	if dist <= 2.5:
		# Arrived.
		if _trade_heading_out:
			# Deliver: gold based on one-way distance (min payout from [trade]).
			var mgr := get_tree().get_first_node_in_group("rts_manager") as RTSManager
			if mgr != null and _home_market != null and is_instance_valid(_home_market):
				var trip := _home_market.global_position.distance_to(_trade_target.global_position)
				if trip >= 1.0:
					var gold := maxi(RTSTuning.get_int("trade", "min_payout", 20),
						int(trip / RTSTuning.get_float("trade", "distance_divisor", 2.0)))
					mgr.add_resource(faction, "gold", gold)
					mgr.sim_bump(faction, "trade_deliveries", 1)
					mgr.sim_bump(faction, "trade_gold", gold)
			_trade_heading_out = false
		else:
			# Back home: head out again.
			_trade_heading_out = true
		velocity = Vector3.ZERO
	else:
		_move_toward(dest.global_position, delta)
	move_and_slide()


## Monk conversion channel. Server-side, called from _physics_process.
func _convert_tick(delta: float) -> void:
	var conv_range := _convert_range()
	var conv_time := _convert_time()
	if _convert_target == null or not is_instance_valid(_convert_target):
		_cancel_convert()
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if not bool(_convert_target.get("alive")):
		_cancel_convert()
		velocity = Vector3.ZERO
		move_and_slide()
		return
	var dist := global_position.distance_to(_convert_target.global_position)
	if dist > conv_range + 2.0:
		# Target escaped the leash: cancel.
		_cancel_convert()
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if dist > 4.5:
		# Chase to stay in channel range.
		_move_toward(_convert_target.global_position, delta)
		move_and_slide()
		return
	velocity = Vector3.ZERO
	move_and_slide()
	if dist <= conv_range:
		_convert_timer += delta
		if _convert_timer >= conv_time:
			_complete_conversion()


func _complete_conversion() -> void:
	var target := _convert_target
	_cancel_convert()
	if target == null or not is_instance_valid(target):
		return
	if int(target.get("faction")) == faction:
		return
	if not bool(target.get("alive")):
		return
	target.convert_to(faction, civ)
	target.rpc("convert_fx")
	var mgr := get_tree().get_first_node_in_group("rts_manager") as RTSManager
	if mgr != null:
		mgr.sim_bump(faction, "conversions", 1)
		mgr.check_elimination()


func _is_ship() -> bool:
	return unit_type == "fishing_ship" or unit_type == "war_galley"


func _is_on_water(pos: Vector3) -> bool:
	var d := get_tree().get_first_node_in_group("dungeon")
	if d != null:
		return bool(d.call("is_on_water", pos))
	return false


# Stuck detection: position sampled periodically while moving.
var _stuck_sample_pos := Vector3.ZERO
var _stuck_sample_time := 0.0


func _move_toward(pos: Vector3, delta: float, skip_avoid_building: Node3D = null) -> void:
	var to_goal := pos - global_position
	to_goal.y = 0.0
	if to_goal.length() > 0.1:
		var dir := to_goal.normalized()
		# Steering: separation from nearby units + slide around buildings
		# and resource nodes. The tangent is chosen toward the goal.
		# skip_avoid_building: when attacking a building, don't get pushed
		# away from the very target we're trying to reach (avoidance radius
		# exceeds melee range, so units would otherwise orbit forever).
		var avoid := _building_avoid_steer(dir, skip_avoid_building) + _resource_avoid_steer(dir)
		dir = (dir + _separation_steer() * 1.5 + avoid * 2.5).normalized()
		# Stuck? If we barely moved in the last 0.8s, force a hard sidestep.
		_stuck_sample_time += delta
		if _stuck_sample_time >= 0.8:
			if global_position.distance_to(_stuck_sample_pos) < 0.6 and avoid.length() > 0.1:
				var side := Vector3(-dir.z, 0, dir.x)
				dir = (dir * 0.3 + side * 1.5).normalized()
			_stuck_sample_pos = global_position
			_stuck_sample_time = 0.0
		var spd := move_speed
		if _is_ship() and _is_on_water(global_position):
			spd *= RTSTuning.get_float("naval", "water_speed_mult", 1.5)
		velocity = dir * spd
		# Face movement direction.
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 10.0 * delta)
	else:
		_stuck_sample_time = 0.0


## Push away from nearby units so groups don't clump into a blob.
func _separation_steer() -> Vector3:
	var push := Vector3.ZERO
	var count := 0
	for other in get_tree().get_nodes_in_group("rts_units"):
		if other == self:
			continue
		var onode := other as Node3D
		if onode == null:
			continue
		var diff: Vector3 = global_position - onode.global_position
		diff.y = 0.0
		var d: float = diff.length()
		if d > 0.01 and d < 1.2:
			push += diff.normalized() * (1.2 - d)
			count += 1
	if count > 0:
		push /= float(count)
	return push


## Push away from nearby buildings. The tangential slide picks the side
## that points most toward the unit's goal, so units flow around corners
## instead of grinding into walls or sliding the wrong way.
func _building_avoid_steer(want_dir: Vector3, skip: Node3D = null) -> Vector3:
	var push := Vector3.ZERO
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if not is_instance_valid(b) or bool(b.get("destroyed")):
			continue
		var bnode := b as Node3D
		if bnode == null or bnode == skip:
			continue
		var diff: Vector3 = global_position - bnode.global_position
		diff.y = 0.0
		var d: float = diff.length()
		if d > 0.01 and d < 4.0:
			var away: Vector3 = diff.normalized() * (4.0 - d)
			# Two tangent options; take the one most aligned with the goal.
			var t1 := Vector3(-away.z, 0, away.x).normalized()
			var tangent := t1 if t1.dot(want_dir) >= -t1.dot(want_dir) else -t1
			push += away + tangent * 1.2
	return push


## Same avoidance for resource nodes — units get wedged between them.
## Skips the node this unit is actively gathering so it can still approach.
func _resource_avoid_steer(want_dir: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("rts_resources"):
		if n == _gather_node:
			continue
		var nnode := n as Node3D
		if nnode == null or not is_instance_valid(n):
			continue
		var diff: Vector3 = global_position - nnode.global_position
		diff.y = 0.0
		var d: float = diff.length()
		if d > 0.01 and d < 2.0:
			var away: Vector3 = diff.normalized() * (2.0 - d)
			var t1 := Vector3(-away.z, 0, away.x).normalized()
			var tangent := t1 if t1.dot(want_dir) >= -t1.dot(want_dir) else -t1
			push += away + tangent * 1.0
	return push


func _find_nearest_enemy(max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for n in get_tree().get_nodes_in_group("rts_units"):
		if n == self:
			continue
		if int(n.get("faction")) == faction:
			continue
		if not bool(n.get("alive")):
			continue
		var d := global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	# Also check buildings.
	for n in get_tree().get_nodes_in_group("rts_buildings"):
		if int(n.get("faction")) == faction:
			continue
		var d := global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best
