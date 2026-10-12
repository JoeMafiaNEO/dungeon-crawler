class_name RTSUnit
extends Node3D
## Jesse 2026-10-11: converted from CharacterBody3D to Node3D for
## thousands-scale performance. Movement is manual position integration;
## separation uses the spatial hash, building avoidance uses steering.
## The physics engine was the bottleneck at 3000+ units.
## Small-scale RTS unit (~0.6m tall). Villagers gather, troops fight.
## Server-authoritative for HP and state.

var faction: int = 0
var unit_type: String = "villager"
var civ: CivData = null
## Deterministic network ID (Jesse 2026-10-10). Set by the spawner; the node is
## named "RTSUnit_<id>" so client and server paths match for order RPCs.
var unit_id: int = 0

var hp: float = 50.0
var max_hp: float = 50.0
var damage: float = 5.0
var attack_range: float = 1.5
var move_speed: float = 3.0
var alive: bool = true
# Jesse 2026-10-11: manual velocity (was CharacterBody3D.velocity).
var velocity: Vector3 = Vector3.ZERO

# Orders.
var _move_target: Vector3 = Vector3.INF
var _sprite: Sprite3D = null
var _attack_target: Node3D = null
var _gather_node: RTSResourceNode = null
var _gather_tick := 0.0
# Jesse 2026-10-11: cached manager + spatial hash (avoid per-frame lookups).
var _rts_mgr: RTSManager = null
# Jesse 2026-10-11: dormancy — idle units skip per-frame work.
var _dormant := false
var _dormant_check := 0.0
# Jesse 2026-10-12: staggered aggro scan — every unit scanning for enemies
# every physics frame was the biggest per-frame cost at 1500 units.
var _aggro_tick := 0.0
# Jesse 2026-10-12: staggered separation — the 3x3-cell neighbor scan every
# frame was the remaining per-frame bottleneck in dense crowds. Separation
# is cached and refreshed ~5x/sec per unit, staggered.
var _sep_cache := Vector3.ZERO
var _sep_tick := 0.0
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
			_select_ring.mesh = _select_mesh()
			_select_ring.material_override = _select_mat()
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

# Jesse 2026-10-12: shared ring meshes/materials. Creating a unique
# TorusMesh + StandardMaterial3D per unit made selecting 1500 units hitch
# ~450ms; now one mesh/material is built once and reused by every ring.
static var _shared_select_mesh: TorusMesh = null
static var _shared_select_mat: StandardMaterial3D = null
static var _shared_faction_mesh: TorusMesh = null
static var _shared_faction_mats: Dictionary = {}
static var _shared_convert_mesh: TorusMesh = null
static var _shared_convert_mat: StandardMaterial3D = null


static func _select_mesh() -> TorusMesh:
	if _shared_select_mesh == null:
		_shared_select_mesh = TorusMesh.new()
		_shared_select_mesh.inner_radius = 0.42
		_shared_select_mesh.outer_radius = 0.58
	return _shared_select_mesh


static func _select_mat() -> StandardMaterial3D:
	if _shared_select_mat == null:
		_shared_select_mat = StandardMaterial3D.new()
		_shared_select_mat.albedo_color = Color(0.25, 1.0, 0.35)
		_shared_select_mat.emission_enabled = true
		_shared_select_mat.emission = Color(0.25, 1.0, 0.35)
		_shared_select_mat.emission_energy_multiplier = 1.5
		_shared_select_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _shared_select_mat


static func _faction_mesh() -> TorusMesh:
	if _shared_faction_mesh == null:
		_shared_faction_mesh = TorusMesh.new()
		_shared_faction_mesh.inner_radius = 0.32
		_shared_faction_mesh.outer_radius = 0.44
	return _shared_faction_mesh


static func _faction_mat(p_faction: int) -> StandardMaterial3D:
	if not _shared_faction_mats.has(p_faction):
		var fcol := RTSManager.faction_color(p_faction)
		var m := StandardMaterial3D.new()
		m.albedo_color = fcol
		m.emission_enabled = true
		m.emission = fcol
		m.emission_energy_multiplier = 0.6
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_faction_mats[p_faction] = m
	return _shared_faction_mats[p_faction]


static func _convert_mesh() -> TorusMesh:
	if _shared_convert_mesh == null:
		_shared_convert_mesh = TorusMesh.new()
		_shared_convert_mesh.inner_radius = 0.3
		_shared_convert_mesh.outer_radius = 0.42
	return _shared_convert_mesh


static func _convert_mat() -> StandardMaterial3D:
	if _shared_convert_mat == null:
		_shared_convert_mat = StandardMaterial3D.new()
		_shared_convert_mat.albedo_color = Color(1.0, 0.85, 0.3)
		_shared_convert_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_convert_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return _shared_convert_mat


func _convert_time() -> float:
	return RTSTuning.get_float("monks", "convert_time", CONVERT_TIME)


func _convert_range() -> float:
	return RTSTuning.get_float("monks", "convert_range", CONVERT_RANGE)

# Base stats per type.
const BASE_STATS := {
	"villager": {"hp": 400.0, "dmg": 30.0, "range": 1.2, "speed": 3.2},
	"spearman": {"hp": 800.0, "dmg": 80.0, "range": 1.5, "speed": 3.0},
	"archer": {"hp": 500.0, "dmg": 100.0, "range": 8.0, "speed": 3.0},
	"knight": {"hp": 1400.0, "dmg": 140.0, "range": 1.8, "speed": 3.8},
	"trade_cart": {"hp": 600.0, "dmg": 0.0, "range": 0.0, "speed": 4.0},
	"catapult": {"hp": 800.0, "dmg": 400.0, "range": 15.0, "speed": 2.0},
	"ram": {"hp": 2000.0, "dmg": 250.0, "range": 2.0, "speed": 2.5},
	"monk": {"hp": 400.0, "dmg": 0.0, "range": 0.0, "speed": 2.8},
	"fishing_ship": {"hp": 800.0, "dmg": 0.0, "range": 0.0, "speed": 3.5},
	"war_galley": {"hp": 1200.0, "dmg": 150.0, "range": 10.0, "speed": 3.0},
}

# Unit types that never auto-attack (economic units).
const NO_AUTO_ATTACK := ["villager", "trade_cart", "monk", "fishing_ship"]


func _ready() -> void:
	add_to_group("rts_units")
	# setup() already built the visual; only rebuild if it wasn't.
	if _sprite == null or not is_instance_valid(_sprite):
		_build_visual()
	# Jesse 2026-10-11: register in the spatial hash.
	_rts_mgr = get_tree().get_first_node_in_group("rts_manager") as RTSManager
	if _rts_mgr != null and _rts_mgr.spatial_hash != null:
		_rts_mgr.spatial_hash.insert(self)
	# Jesse 2026-10-12: stagger the first aggro scan so all units don't
	# scan on the same frame after a mass order.
	_aggro_tick = float(get_instance_id() % 30) * 0.01
	_sep_tick = float(get_instance_id() % 12) * 0.016
	# Jesse 2026-10-11: register with the MultiMesh renderer.
	var renderer := get_tree().get_first_node_in_group("rts_unit_renderer")
	if renderer != null and renderer.has_method("register_unit"):
		renderer.call("register_unit", self)


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
	_update_sprite_orientation()
	sprite.position.y = 0.45
	add_child(sprite)
	_sprite = sprite

	# Faction ring: slight visual cue (Jesse 2026-10-10) — unique color per
	# faction, code-generated (no art assets). Sits below the selection ring.
	var fring := MeshInstance3D.new()
	fring.name = "FactionRing"
	fring.mesh = _faction_mesh()
	fring.material_override = _faction_mat(faction)
	fring.rotation = Vector3.ZERO
	fring.position = Vector3(0, 0.05, 0)
	add_child(fring)

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


## Jesse 2026-10-11: sprite faces the active camera. Command (top-down)
## view lays it flat with feet toward the screen bottom; FPS view stands
## it upright with Y-fixed billboard (matches dungeon mobs).
func _update_sprite_orientation() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	var command_view := false
	var cam := get_tree().get_first_node_in_group("rts_camera")
	if cam != null and bool(cam.get("active")):
		command_view = true
	if command_view:
		_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		_sprite.rotation = Vector3(PI / 2, 0, PI)
	else:
		_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_sprite.rotation = Vector3.ZERO


## Called by the RTS camera when TAB toggles command view.
func _on_command_view_toggled(_active: bool) -> void:
	_update_sprite_orientation()


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
	_wake()
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
	_wake()
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
	_wake()
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
	_wake()
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
			_convert_ring.mesh = _convert_mesh()
			_convert_ring.material_override = _convert_mat()
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
	_wake()
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
	_wake()
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
	_wake()
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
	# Jesse 2026-10-11: remove from spatial hash.
	var mgr2 := get_tree().get_first_node_in_group("rts_manager") as RTSManager
	if mgr2 != null and mgr2.spatial_hash != null:
		mgr2.spatial_hash.remove(self)
	# Jesse 2026-10-11: unregister from MultiMesh renderer.
	var renderer := get_tree().get_first_node_in_group("rts_unit_renderer")
	if renderer != null and renderer.has_method("unregister_unit"):
		renderer.call("unregister_unit", self)
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


## Jesse 2026-10-11: dormancy helpers.
func _is_idle() -> bool:
	return _move_target == Vector3.INF and _attack_target == null \
		and _gather_node == null and _build_target == null \
		and _trade_target == null and _convert_target == null


func _wake() -> void:
	_dormant = false
	set_physics_process(true)


func _sleep() -> void:
	if _dormant:
		return
	_dormant = true
	_dormant_check = 0.0  # check immediately on next frame
	# Don't disable physics_process entirely — we need the staggered check.
	# The early return in _physics_process handles the skip.


## Jesse 2026-10-11: manual movement integration (replaces move_and_slide).
## Applies velocity, keeps units on the ground plane, clamps to map bounds.
func _apply_movement(delta: float) -> void:
	global_position += velocity * delta
	# Keep on ground plane (ships at water level).
	if _is_ship():
		global_position.y = 0.08
	else:
		global_position.y = 0.0
	# Clamp to reasonable map bounds (200x200).
	global_position.x = clampf(global_position.x, -100.0, 100.0)
	global_position.z = clampf(global_position.z, -100.0, 100.0)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not alive:
		return
	# Jesse 2026-10-11: dormancy — idle units do a cheap staggered
	# enemy check instead of full processing.
	if _dormant:
		_dormant_check -= delta
		if _dormant_check <= 0.0:
			# Stagger by instance id to avoid thundering herd.
			_dormant_check = 0.5 + float(get_instance_id() % 10) * 0.05
			if _find_nearest_enemy(8.0) != null:
				_wake()
		return

	# Jesse 2026-10-12: refresh the cached separation vector on a stagger.
	if not _dormant:
		_sep_tick -= delta
		if _sep_tick <= 0.0:
			_sep_tick = 0.2
			_sep_cache = _compute_separation()

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
			_apply_movement(delta)
			return
		else:
			# Walk to the site.
			var bdir := (_build_target.global_position - global_position).normalized()
			velocity = Vector3(bdir.x, 0, bdir.z) * move_speed
			_apply_movement(delta)
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
	# Jesse 2026-10-12: staggered — scanning every physics frame for every
	# unit was the dominant per-frame cost at 1500 units (3.7s/frame total).
	# A 0.3s reaction delay is imperceptible in practice.
	if not unit_type in NO_AUTO_ATTACK and _attack_target == null:
		_aggro_tick -= delta
		if _aggro_tick <= 0.0:
			_aggro_tick = 0.3
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
		_apply_movement(delta)
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
		_apply_movement(delta)
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
		_apply_movement(delta)
	else:
		velocity = Vector3.ZERO
		_apply_movement(delta)
	# Replicate transform to clients ~12 Hz (unreliable).
	# Jesse 2026-10-11: per-unit sync removed — RTSManager broadcasts
	# batched army transforms per faction at ~8Hz instead.
	# Jesse 2026-10-11: update spatial hash cell after movement.
	if _rts_mgr != null and _rts_mgr.spatial_hash != null:
		_rts_mgr.spatial_hash.update(self)
	# Jesse 2026-10-11: sleep if idle after processing.
	if _is_idle():
		_sleep()


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
		# Jesse 2026-10-11: RTS units can be ordered to attack players.
		# Player.take_damage expects (float, String); units/buildings take (float, Node3D).
		if target.is_in_group("players"):
			target.take_damage(dmg, "RTS " + unit_type)
		else:
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
		_apply_movement(delta)
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
	_apply_movement(delta)


## Monk conversion channel. Server-side, called from _physics_process.
func _convert_tick(delta: float) -> void:
	var conv_range := _convert_range()
	var conv_time := _convert_time()
	if _convert_target == null or not is_instance_valid(_convert_target):
		_cancel_convert()
		velocity = Vector3.ZERO
		_apply_movement(delta)
		return
	if not bool(_convert_target.get("alive")):
		_cancel_convert()
		velocity = Vector3.ZERO
		_apply_movement(delta)
		return
	var dist := global_position.distance_to(_convert_target.global_position)
	if dist > conv_range + 2.0:
		# Target escaped the leash: cancel.
		_cancel_convert()
		velocity = Vector3.ZERO
		_apply_movement(delta)
		return
	if dist > 4.5:
		# Chase to stay in channel range.
		_move_toward(_convert_target.global_position, delta)
		_apply_movement(delta)
		return
	velocity = Vector3.ZERO
	_apply_movement(delta)
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
		dir = (dir + _sep_cache * 1.5 + avoid * 2.5).normalized()
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
## Jesse 2026-10-11: uses spatial hash instead of O(n) group scan.
## Jesse 2026-10-12: result is cached; callers use _sep_cache (refreshed on
## a stagger in _physics_process).
func _compute_separation() -> Vector3:
	var push := Vector3.ZERO
	var count := 0
	var neighbors: Array = []
	if _rts_mgr != null and _rts_mgr.spatial_hash != null:
		neighbors = _rts_mgr.spatial_hash.query(global_position, 1.2)
	else:
		neighbors = get_tree().get_nodes_in_group("rts_units")
	for other in neighbors:
		if other == self:
			continue
		# Jesse 2026-10-12: typed access (see _find_nearest_enemy).
		var onode := other as RTSUnit
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
	# Jesse 2026-10-11: spatial hash query instead of O(n) group scan.
	var candidates: Array = []
	if _rts_mgr != null and _rts_mgr.spatial_hash != null:
		candidates = _rts_mgr.spatial_hash.query(global_position, max_dist)
	else:
		candidates = get_tree().get_nodes_in_group("rts_units")
	for n in candidates:
		if n == self:
			continue
		# Jesse 2026-10-12: typed access — .get("faction") on 270+ dense
		# neighbors every frame was a major cost; direct member access is
		# far cheaper. The spatial hash only holds RTSUnits.
		var u := n as RTSUnit
		if u == null:
			continue
		if u.faction == faction:
			continue
		if not u.alive:
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
