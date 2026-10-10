class_name RTSBuilding
extends StaticBody3D
## AoE4-style RTS building for the Warlord's Domain level.
## Small scale (~2-3m tall) so FPS players can read the battlefield.
## Server-authoritative: the host sims HP and production; RPCs sync visuals.
##
## Expected RTS manager API (guarded with has_method so the building also
## works standalone in tests):
##   rts_manager.spawn_unit(unit_type: String, faction: int, pos: Vector3, civ: CivData)
##   rts_manager.can_train(faction: int, unit_type: String) -> bool  (pop space etc.)
##   rts_manager.on_building_destroyed(b: RTSBuilding)

const TRAIN_TIMES := {
	"villager": 8.0,
	"spearman": 10.0,
	"archer": 12.0,
	"knight": 15.0,
	"trade_cart": 12.0,
	"catapult": 20.0,
	"ram": 18.0,
	"monk": 12.0,
	"fishing_ship": 14.0,
	"war_galley": 18.0,
}
const MAX_QUEUE := 5

# Base HP per building type (town hall gets civ.townhall_hp_mult).
const BASE_HP := {
	"town_hall": 1500.0,
	"barracks": 600.0,
	"archery_range": 600.0,
	"market": 500.0,
	"siege_workshop": 700.0,
	"monastery": 700.0,
	"dock": 500.0,
	"tower": 800.0,
}
# Which unit types each building may train.
const PRODUCTION := {
	"town_hall": ["villager", "knight"],
	"barracks": ["spearman"],
	"archery_range": ["archer"],
	"market": ["trade_cart"],
	"siege_workshop": ["catapult", "ram"],
	"monastery": ["monk"],
	"dock": ["fishing_ship", "war_galley"],
}

var faction := 0
var building_type := "town_hall"
var hp := 100.0
var max_hp := 100.0
var civ: CivData = null
var production_queue: Array = [] # Array[String] unit type ids
var rally_point := Vector3.ZERO
## Set by the spawner (the RTS manager). Knights need Fortress age+.
var knights_unlocked := false
var rts_manager: Node = null
var destroyed := false
# Construction state.
var under_construction := false
var build_progress := 1.0
const BUILD_TIME := 20.0  # seconds of villager channeling to complete
var _select_ring: MeshInstance3D = null
var _select_t := 0.0

var _train_t := 0.0
var _body_root: Node3D
var _hp_fill: MeshInstance3D
var _hp_bg: MeshInstance3D
var _sync_t := 0.0


func setup(p_faction: int, p_type: String, p_civ: CivData) -> void:
	faction = p_faction
	building_type = p_type
	civ = p_civ
	var base: float = RTSTuning.get_float("building_hp", p_type, BASE_HP.get(p_type, 600.0))
	if p_type == "town_hall" and civ != null:
		base *= civ.townhall_hp_mult
	max_hp = base
	hp = max_hp


func _ready() -> void:
	add_to_group("rts_buildings")
	if civ == null:
		civ = CivData.new()
	if rally_point == Vector3.ZERO:
		if building_type == "dock":
			# Rally ships onto the water (river at x=0).
			var dir := -signf(global_position.x)
			if dir == 0.0:
				dir = 1.0
			rally_point = Vector3(global_position.x + dir * 6.0, 0, global_position.z)
		else:
			rally_point = global_position + Vector3(0, 0, 3.0)
	_build_visuals()
	_build_hp_bar()
	_build_select_ring()
	if not multiplayer.is_server():
		set_process(false)


func _build_select_ring() -> void:
	_select_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.6
	tm.outer_radius = 1.95
	_select_ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 1.0, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 1.0, 0.35)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_select_ring.material_override = mat
	_select_ring.position = Vector3(0, 0.12, 0)
	_select_ring.visible = false
	add_child(_select_ring)


@rpc("any_peer", "call_local")
func set_selected(on: bool) -> void:
	if _select_ring != null and is_instance_valid(_select_ring):
		_select_ring.visible = on


func _train_time_for(unit_type: String) -> float:
	var base: float = RTSTuning.get_float("train_times", unit_type, TRAIN_TIMES.get(unit_type, 10.0))
	var mult := 1.0
	if civ != null:
		mult = civ.train_time_mult
	return base * mult


func queue_unit(unit_type: String) -> bool:
	#Add a unit to the production queue. Returns false if rejected.#
	#Payment is taken upfront (standard RTS).
	if destroyed:
		return false
	var allowed: Array = PRODUCTION.get(building_type, [])
	if not unit_type in allowed:
		return false
	if unit_type == "knight":
		# Check live age — the cached knights_unlocked goes stale on age-up.
		var age := 0
		if rts_manager != null and rts_manager.has_method("get_age"):
			age = int(rts_manager.call("get_age", faction))
		if age < 1:
			return false
	if production_queue.size() >= RTSTuning.get_int("buildings", "max_queue", MAX_QUEUE):
		return false
	# Pop space / cost checks belong to the manager.
	var cost: Dictionary = RTSTuning.get_cost(
		"unit_costs", unit_type, RTSManager.UNIT_COSTS.get(unit_type, {}))
	if rts_manager != null and rts_manager.has_method("can_train"):
		if not bool(rts_manager.call("can_train", faction, unit_type)):
			return false
	if rts_manager != null and rts_manager.has_method("spend"):
		if not bool(rts_manager.call("spend", faction, cost)):
			return false
	production_queue.append(unit_type)
	if _train_t <= 0.0:
		_train_t = _train_time_for(unit_type)
		rpc("train_fx", unit_type)
	return true


## RPC wrapper so clients can queue units from the training panel.
@rpc("any_peer", "call_local")
func rpc_queue_unit(unit_type: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		var owner := int(rts_manager.faction_peers.get(faction, -2)) if rts_manager else -2
		if owner != sender and owner != -1:
			return
	queue_unit(unit_type)


var _tower_cd := 0.0
const TOWER_RANGE := 12.0
const TOWER_DAMAGE := 8.0
const TOWER_COOLDOWN := 1.5


func _tower_range() -> float:
	return RTSTuning.get_float("buildings", "tower_range", TOWER_RANGE)


func _tower_damage() -> float:
	return RTSTuning.get_float("buildings", "tower_damage", TOWER_DAMAGE)


func _tower_cooldown() -> float:
	return RTSTuning.get_float("buildings", "tower_cooldown", TOWER_COOLDOWN)


func _process(delta: float) -> void:
	# Server-only: production timer.
	if not multiplayer.is_server():
		return
	# Tower defense: shoot nearby enemies.
	if building_type == "tower" and not under_construction and not destroyed:
		_tower_cd -= delta
		if _tower_cd <= 0.0:
			_tower_cd = _tower_cooldown()
			_tower_shoot()
	if production_queue.is_empty():
		_train_t = 0.0
		return
	_train_t -= delta
	# Periodic HP sync for clients (cheap, unreliable).
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 1.0
		rpc("sync_hp", hp)
	if _train_t > 0.0:
		return
	var unit_type := str(production_queue.pop_front())
	if not production_queue.is_empty():
		_train_t = _train_time_for(str(production_queue[0]))
	else:
		_train_t = 0.0
	_spawn_unit(unit_type)
	# Pulse the selection ring.
	if _select_ring != null and is_instance_valid(_select_ring) and _select_ring.visible:
		_select_t += delta
		var s := 1.0 + 0.06 * sin(_select_t * 6.0)
		_select_ring.scale = Vector3(s, 1.0, s)


func _tower_shoot() -> void:
	var t_range := _tower_range()
	var best: Node3D = null
	var best_d := t_range
	for u in get_tree().get_nodes_in_group("rts_units"):
		if int(u.get("faction")) == faction:
			continue
		var d: float = global_position.distance_to(u.global_position)
		if d < best_d:
			best_d = d
			best = u
	if best != null and best.has_method("take_damage"):
		best.take_damage(_tower_damage(), self)
		rpc("tower_fx", best.global_position)


@rpc("any_peer", "call_local")
func tower_fx(target_pos: Vector3) -> void:
	Effects.burst(get_parent(), target_pos + Vector3(0, 0.5, 0), Color(1.0, 0.9, 0.5), 4, 2.0)


func _spawn_unit(unit_type: String) -> void:
	if rts_manager != null and rts_manager.has_method("spawn_unit"):
		rts_manager.call("spawn_unit", unit_type, faction, rally_point, civ)
	else:
		push_warning("[RTSBuilding] No rts_manager.spawn_unit; dropping trained %s." % unit_type)
	rpc("spawn_fx", rally_point)


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
	# Server-authoritative damage.
	if destroyed:
		return
	hp -= amount
	rpc("sync_hp", hp)
	rpc("hit_fx", amount)
	if hp <= 0.0:
		hp = 0.0
		destroyed = true
		rpc("destroy_fx")
		if rts_manager != null and rts_manager.has_method("on_building_destroyed"):
			rts_manager.call("on_building_destroyed", self)


func display_name() -> String:
	match building_type:
		"town_hall":
			return "Town Hall"
		"barracks":
			return "Barracks"
		"archery_range":
			return "Archery Range"
		"market":
			return "Market"
		"siege_workshop":
			return "Siege Workshop"
		"monastery":
			return "Monastery"
		"dock":
			return "Dock"
	return building_type


# --- Visuals (primitives, ~2-3m tall) ---

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_visuals() -> void:
	_body_root = Node3D.new()
	_body_root.name = "Body"
	add_child(_body_root)
	var wood := Color(0.45, 0.3, 0.16)
	var stone := Color(0.55, 0.55, 0.58)
	var roof_c := Color(0.5, 0.16, 0.12)
	# Faction banner: unique per-faction color (Jesse 2026-10-10), not the
	# civ color, so every player's buildings are visually distinct.
	var accent: Color = RTSManager.faction_color(faction)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	match building_type:
		"town_hall":
			# Large hall: 3.4 x 2.2 x 3.4 + pyramid roof.
			_box(_body_root, Vector3(3.4, 2.2, 3.4), Vector3(0, 1.1, 0), stone)
			_box(_body_root, Vector3(3.7, 0.25, 3.7), Vector3(0, 2.3, 0), wood)
			var pyr := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.radial_segments = 4
			cm.top_radius = 0.05
			cm.bottom_radius = 2.6
			cm.height = 1.2
			pyr.mesh = cm
			pyr.material_override = _mat(roof_c)
			pyr.position = Vector3(0, 3.0, 0)
			pyr.rotation.y = PI / 4.0
			_body_root.add_child(pyr)
			# Faction banner on the front face.
			_box(_body_root, Vector3(0.9, 1.2, 0.08), Vector3(0, 1.4, 1.72), accent)
			shape.size = Vector3(3.4, 2.6, 3.4)
			col.position = Vector3(0, 1.3, 0)
		"barracks":
			# Long hall: 4.6 x 1.7 x 2.4 + flat slab roof.
			_box(_body_root, Vector3(4.6, 1.7, 2.4), Vector3(0, 0.85, 0), wood)
			_box(_body_root, Vector3(5.0, 0.22, 2.8), Vector3(0, 1.8, 0), roof_c)
			# Faction trim along the roof edge.
			_box(_body_root, Vector3(5.0, 0.12, 0.15), Vector3(0, 1.68, 1.35), accent)
			_box(_body_root, Vector3(5.0, 0.12, 0.15), Vector3(0, 1.68, -1.35), accent)
			shape.size = Vector3(4.6, 2.0, 2.4)
			col.position = Vector3(0, 1.0, 0)
		"archery_range":
			# Compact range: 2.6 x 1.6 x 2.6 + target decoration.
			_box(_body_root, Vector3(2.6, 1.6, 2.6), Vector3(0, 0.8, 0), wood)
			_box(_body_root, Vector3(2.9, 0.2, 2.9), Vector3(0, 1.7, 0), roof_c)
			# Target: post + white disc + red center.
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.06
			pm.bottom_radius = 0.06
			pm.height = 1.0
			post.mesh = pm
			post.material_override = _mat(wood)
			post.position = Vector3(0, 2.3, 0)
			_body_root.add_child(post)
			var disc := MeshInstance3D.new()
			var dm := CylinderMesh.new()
			dm.top_radius = 0.45
			dm.bottom_radius = 0.45
			dm.height = 0.08
			disc.mesh = dm
			disc.material_override = _mat(Color(0.92, 0.92, 0.92))
			disc.rotation.x = PI / 2.0
			disc.position = Vector3(0, 2.6, 0.1)
			_body_root.add_child(disc)
			var bull := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.16
			bm.bottom_radius = 0.16
			bm.height = 0.1
			bull.mesh = bm
			bull.material_override = _mat(Color(0.85, 0.15, 0.15))
			bull.rotation.x = PI / 2.0
			bull.position = Vector3(0, 2.6, 0.12)
			_body_root.add_child(bull)
			shape.size = Vector3(2.6, 2.0, 2.6)
			col.position = Vector3(0, 1.0, 0)
		"market":
			# Open stall: counter + striped awning on posts + crates beside.
			_box(_body_root, Vector3(3.0, 0.9, 1.6), Vector3(0, 0.45, 0), wood)
			# Awning posts.
			for px in [-1.4, 1.4]:
				for pz in [-0.7, 0.7]:
					var post := MeshInstance3D.new()
					var pm := CylinderMesh.new()
					pm.top_radius = 0.05
					pm.bottom_radius = 0.05
					pm.height = 2.2
					post.mesh = pm
					post.material_override = _mat(wood)
					post.position = Vector3(px, 1.1, pz)
					_body_root.add_child(post)
			# Striped awning: alternating accent/white slats.
			for i in 6:
				var slat_c := accent if i % 2 == 0 else Color(0.93, 0.9, 0.82)
				_box(_body_root, Vector3(0.55, 0.08, 2.0), Vector3(-1.375 + i * 0.55, 2.25, 0), slat_c)
			# Crates stacked beside the stall.
			_box(_body_root, Vector3(0.7, 0.7, 0.7), Vector3(2.0, 0.35, 0.4), wood)
			_box(_body_root, Vector3(0.55, 0.55, 0.55), Vector3(2.0, 0.97, 0.4), wood)
			_box(_body_root, Vector3(0.6, 0.6, 0.6), Vector3(-2.0, 0.3, -0.3), wood)
			shape.size = Vector3(3.2, 2.4, 2.0)
			col.position = Vector3(0, 1.2, 0)
		"siege_workshop":
			# Workshop hall: 3.6 x 2.0 x 2.8 + catapult parts parked outside.
			_box(_body_root, Vector3(3.6, 2.0, 2.8), Vector3(0, 1.0, 0), wood)
			_box(_body_root, Vector3(4.0, 0.22, 3.2), Vector3(0, 2.1, 0), roof_c)
			# Faction trim.
			_box(_body_root, Vector3(4.0, 0.12, 0.15), Vector3(0, 1.98, 1.55), accent)
			# Catapult frame outside: two wheels + arm.
			for wx in [-0.5, 0.5]:
				var wheel := MeshInstance3D.new()
				var wm := CylinderMesh.new()
				wm.top_radius = 0.35
				wm.bottom_radius = 0.35
				wm.height = 0.1
				wheel.mesh = wm
				wheel.material_override = _mat(Color(0.35, 0.25, 0.15))
				wheel.rotation.z = PI / 2.0
				wheel.position = Vector3(2.6 + wx, 0.35, 0.8)
				_body_root.add_child(wheel)
			_box(_body_root, Vector3(1.4, 0.15, 0.5), Vector3(2.6, 0.55, 0.8), wood)
			var arm := MeshInstance3D.new()
			var am := CylinderMesh.new()
			am.top_radius = 0.06
			am.bottom_radius = 0.06
			am.height = 1.6
			arm.mesh = am
			arm.material_override = _mat(wood)
			arm.rotation.z = -0.7
			arm.position = Vector3(2.9, 1.2, 0.8)
			_body_root.add_child(arm)
			shape.size = Vector3(3.6, 2.4, 2.8)
			col.position = Vector3(0, 1.2, 0)
		"monastery":
			# Small chapel: stone nave + steeple tower + gold cross.
			_box(_body_root, Vector3(2.6, 1.8, 3.2), Vector3(0, 0.9, 0), stone)
			_box(_body_root, Vector3(2.9, 0.2, 3.5), Vector3(0, 1.9, 0), roof_c)
			# Steeple tower at the front.
			_box(_body_root, Vector3(1.0, 2.6, 1.0), Vector3(0, 1.3, 1.8), stone)
			var spire := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.radial_segments = 4
			sm.top_radius = 0.05
			sm.bottom_radius = 0.7
			sm.height = 1.0
			spire.mesh = sm
			spire.material_override = _mat(roof_c)
			spire.position = Vector3(0, 3.1, 1.8)
			spire.rotation.y = PI / 4.0
			_body_root.add_child(spire)
			# Gold cross on top of the steeple.
			_box(_body_root, Vector3(0.08, 0.5, 0.08), Vector3(0, 3.85, 1.8), Color(0.95, 0.8, 0.3))
			_box(_body_root, Vector3(0.3, 0.08, 0.08), Vector3(0, 3.95, 1.8), Color(0.95, 0.8, 0.3))
			# Dark arched doorway.
			_box(_body_root, Vector3(0.8, 1.2, 0.1), Vector3(0, 0.6, 1.62), Color(0.15, 0.1, 0.08))
			shape.size = Vector3(2.6, 2.6, 4.4)
			col.position = Vector3(0, 1.3, 0.4)
		"dock":
			# Wooden pier: platform on posts + loading crane.
			_box(_body_root, Vector3(4.0, 0.25, 2.4), Vector3(0, 0.35, 0), wood)
			for px in [-1.8, -0.6, 0.6, 1.8]:
				for pz in [-1.0, 1.0]:
					var post := MeshInstance3D.new()
					var pm2 := CylinderMesh.new()
					pm2.top_radius = 0.09
					pm2.bottom_radius = 0.09
					pm2.height = 0.9
					post.mesh = pm2
					post.material_override = _mat(wood.darkened(0.2))
					post.position = Vector3(px, 0.0, pz)
					_body_root.add_child(post)
			# Loading crane at the corner.
			_box(_body_root, Vector3(0.15, 1.6, 0.15), Vector3(1.6, 1.2, 0.8), wood.darkened(0.1))
			_box(_body_root, Vector3(1.2, 0.12, 0.12), Vector3(1.1, 1.9, 0.8), wood.darkened(0.1))
			# Faction trim on the platform edge.
			_box(_body_root, Vector3(4.0, 0.08, 0.12), Vector3(0, 0.5, 1.15), accent)
			shape.size = Vector3(4.0, 1.0, 2.4)
			col.position = Vector3(0, 0.5, 0)
		"tower":
			# Stone watchtower: tapered shaft + crenellated top + faction banner.
			var shaft := MeshInstance3D.new()
			var sm := CylinderMesh.new()
			sm.top_radius = 0.9
			sm.bottom_radius = 1.2
			sm.height = 3.0
			sm.radial_segments = 8
			shaft.mesh = sm
			shaft.material_override = _mat(stone)
			shaft.position = Vector3(0, 1.5, 0)
			_body_root.add_child(shaft)
			# Top platform.
			_box(_body_root, Vector3(2.4, 0.3, 2.4), Vector3(0, 3.1, 0), stone.darkened(0.1))
			# Crenellations.
			for cx in [-1.0, -0.33, 0.33, 1.0]:
				for cz in [-1.0, 1.0]:
					_box(_body_root, Vector3(0.3, 0.4, 0.3), Vector3(cx, 3.45, cz), stone.darkened(0.15))
				for cx2 in [-1.0, 1.0]:
					_box(_body_root, Vector3(0.3, 0.4, 0.3), Vector3(cx2, 3.45, cx), stone.darkened(0.15))
			# Faction banner.
			_box(_body_root, Vector3(0.7, 0.9, 0.06), Vector3(0, 2.2, 1.15), accent)
			shape.size = Vector3(2.4, 3.6, 2.4)
			col.position = Vector3(0, 1.8, 0)
	add_child(col)
	# Faction flag on top of every building.
	_build_flag(accent)


func _build_flag(accent: Color) -> void:
	var top_y := 3.6
	match building_type:
		"barracks":
			top_y = 2.1
		"archery_range":
			top_y = 2.9
		"market":
			top_y = 2.4
		"siege_workshop":
			top_y = 2.4
		"monastery":
			top_y = 4.2
		"dock":
			top_y = 2.2
		"tower":
			top_y = 3.9
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.03
	pm.bottom_radius = 0.03
	pm.height = 1.0
	pole.mesh = pm
	pole.material_override = _mat(Color(0.3, 0.22, 0.14))
	pole.position = Vector3(0, top_y + 0.5, 0)
	_body_root.add_child(pole)
	# Waving banner: thin faction-colored box.
	_box(_body_root, Vector3(0.55, 0.35, 0.04), Vector3(0.3, top_y + 0.78, 0), accent)


func _build_hp_bar() -> void:
	# Floating HP bar above the building (billboarded, ~1.6m wide).
	var h := 3.8
	match building_type:
		"barracks":
			h = 2.6
		"archery_range":
			h = 3.2
		"market":
			h = 2.8
		"siege_workshop":
			h = 3.0
		"monastery":
			h = 4.6
		"dock":
			h = 2.6
		"tower":
			h = 4.4
	var bg := MeshInstance3D.new()
	_hp_bg = bg
	var bgm := BoxMesh.new()
	bgm.size = Vector3(1.7, 0.14, 0.02)
	bg.mesh = bgm
	var bgmat := StandardMaterial3D.new()
	bgmat.albedo_color = Color(0.08, 0.08, 0.08, 0.85)
	bgmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bgmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg.material_override = bgmat
	bg.position = Vector3(0, h, 0)
	add_child(bg)
	_hp_fill = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.6, 0.09, 0.02)
	_hp_fill.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.25, 0.85, 0.3)
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill.material_override = fmat
	_hp_fill.position = Vector3(0, h, 0.005)
	add_child(_hp_fill)
	_update_hp_bar()


func _update_hp_bar() -> void:
	if _hp_fill == null:
		return
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_hp_fill.scale.x = maxf(frac, 0.001)
	_hp_fill.position.x = -0.8 * (1.0 - frac)
	var mat := _hp_fill.material_override as StandardMaterial3D
	if mat != null:
		if frac > 0.5:
			mat.albedo_color = Color(0.25, 0.85, 0.3)
		elif frac > 0.25:
			mat.albedo_color = Color(0.95, 0.8, 0.2)
		else:
			mat.albedo_color = Color(0.9, 0.25, 0.2)
	_hp_fill.visible = frac < 1.0 and not destroyed
	if _hp_bg != null and is_instance_valid(_hp_bg):
		_hp_bg.visible = frac < 1.0 and not destroyed


# --- Networked visuals ---

@rpc("any_peer", "call_local")
func sync_hp(new_hp: float) -> void:
	hp = new_hp
	_update_hp_bar()


@rpc("any_peer", "call_local")
func hit_fx(amount: float) -> void:
	Effects.burst(get_parent(), global_position + Vector3(0, 1.2, 0), Color(1.0, 0.8, 0.25), 10, 5.0)
	Effects.damage_number(get_parent(), global_position + Vector3(0, 2.0, 0), amount)


@rpc("any_peer", "call_local")
func train_fx(unit_type: String) -> void:
	AudioManager.sfx("ui_click", global_position)
	Effects.burst(get_parent(), rally_point + Vector3(0, 0.4, 0), Color(0.4, 0.8, 1.0), 8, 3.0)


## Begin construction: building starts at 10% HP, completes via villager work.
func start_construction() -> void:
	under_construction = true
	build_progress = 0.0
	hp = max_hp * 0.1
	_set_construction_dim(true)


## Villager work tick: advance construction.
func add_build_work(amount: float) -> void:
	if not under_construction or destroyed:
		return
	var build_time := RTSTuning.get_float("buildings", "build_time", BUILD_TIME)
	build_progress = minf(1.0, build_progress + amount / build_time)
	hp = max_hp * lerpf(0.1, 1.0, build_progress)
	if build_progress >= 1.0:
		under_construction = false
		_set_construction_dim(false)
		rpc("build_complete_fx")


# Original albedo colors, for restoring after construction completes.
var _orig_albedos: Dictionary = {}


## Dim (or restore) all meshes under Body while under construction.
## Node3D has no modulate, so we fade each mesh's own material instead.
func _set_construction_dim(dim: bool) -> void:
	var body := get_node_or_null("Body")
	if body == null:
		return
	var stack: Array = [body]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mat := (n as MeshInstance3D).material_override as StandardMaterial3D
			if mat != null:
				if dim:
					if not _orig_albedos.has(n):
						_orig_albedos[n] = mat.albedo_color
					var c: Color = mat.albedo_color
					c.a = 0.55
					mat.albedo_color = c
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				else:
					if _orig_albedos.has(n):
						mat.albedo_color = _orig_albedos[n]
					mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		for c in n.get_children():
			stack.append(c)
	if not dim:
		_orig_albedos.clear()


@rpc("any_peer", "call_local")
func build_complete_fx() -> void:
	AudioManager.sfx("ui_click", global_position)
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.5, 1.0, 0.5), 16, 4.0)


@rpc("any_peer", "call_local")
func spawn_fx(pos: Vector3) -> void:
	Effects.burst(get_parent(), pos + Vector3(0, 0.4, 0), Color(0.5, 0.9, 0.5), 12, 4.0)
	AudioManager.sfx("revive", pos)


@rpc("any_peer", "call_local")
func destroy_fx() -> void:
	var base := global_position
	# Rubble poof: dust + stone chunks + faction-colored banner shreds.
	Effects.burst(get_parent(), base + Vector3(0, 1.0, 0), Color(0.55, 0.5, 0.45), 40, 8.0)
	Effects.burst(get_parent(), base + Vector3(0, 1.6, 0), Color(0.35, 0.33, 0.32), 24, 6.0)
	if civ != null:
		Effects.burst(get_parent(), base + Vector3(0, 2.2, 0), civ.color, 16, 7.0)
	AudioManager.sfx("explosion", base)
	if _body_root != null:
		_body_root.visible = false
	if _hp_fill != null:
		_hp_fill.visible = false
	# Let the poof play, then remove the husk.
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(queue_free)
