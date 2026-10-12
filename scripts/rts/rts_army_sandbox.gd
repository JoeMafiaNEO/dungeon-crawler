class_name RTSArmySandbox
extends Node3D
## RTS Army Sandbox (Jesse 2026-10-12): a standalone test scene for spawning
## huge armies and commanding them around. Open in the editor and press F6
## (play scene), or run headless for smoke tests.
##
## Bootstraps the RTS stack without the dungeon: RTSManager, RTSUnitRenderer,
## RTSCamera, two factions (red west / blue east). The camera gives the full
## command set: drag left-click = selection box, right-click = move/attack
## (orders of 25+ units route through the adaptive squad path), wheel = zoom,
## WASD = pan, TAB = toggle top-down/FPS view.
##
## The bottom bar spawns armies at the camera's focus point (red spawns west
## of focus, blue east). Spawn queue is processed a few hundred units per
## frame so even 4000-unit spawns don't hitch the editor.

const SPAWN_PER_FRAME := 250
const FORMATION_SPACING := 1.4
const CIVS := {0: "iron_vanguard", 1: "shadow_covenant"}
const TYPES := ["spearman", "archer", "knight", "villager", "catapult", "ram", "monk"]
const COUNTS := [50, 100, 250, 500, 1000, 2000]

var _mgr: RTSManager = null
var _cam: RTSCamera = null
var _renderer: RTSUnitRenderer = null
var _armies: Node3D = null
var _spawn_queue: Array = []  # {faction, type, pos}
var _faction_opt: OptionButton = null
var _type_opt: OptionButton = null
var _stats_label: Label = null
var _spawn_buttons: Array = []


func _ready() -> void:
	_build_world()
	_build_rts_stack()
	_build_ui()
	# Start in command view above the map center.
	_cam.active = true
	_cam.current = true
	_cam.position = Vector3(0, 40, 0)
	_cam.rotation = Vector3(-PI / 2, 0, 0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_world() -> void:
	# Flat 200x200 test ground.
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.38, 0.20)
	mat.roughness = 1.0
	ground.material_override = mat
	add_child(ground)
	# Spawn-zone markers: red ring west, blue ring east.
	_add_zone_marker(Vector3(-30, 0.05, 0), Color(0.9, 0.2, 0.2))
	_add_zone_marker(Vector3(30, 0.05, 0), Color(0.2, 0.4, 0.9))
	# Daylight.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-35), 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "Environment"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky_mat.ground_bottom_color = Color(0.15, 0.2, 0.12)
	sky_mat.ground_horizon_color = Color(0.6, 0.7, 0.65)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)


func _add_zone_marker(pos: Vector3, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 9.5
	tm.outer_radius = 10.0
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position = pos
	add_child(ring)


func _build_rts_stack() -> void:
	_mgr = RTSManager.new()
	_mgr.name = "RTSManager"
	add_child(_mgr)
	_armies = Node3D.new()
	_armies.name = "Armies"
	add_child(_armies)
	# Register both test factions. Faction 0 is the local player (red, west),
	# faction 1 is the enemy (blue, east).
	_mgr.register_faction(0, multiplayer.get_unique_id(), "warrior")
	_mgr.register_faction(1, -1, "rogue")
	_renderer = RTSUnitRenderer.new()
	_renderer.name = "RTSUnitRenderer"
	add_child(_renderer)
	_cam = RTSCamera.new()
	_cam.name = "RTSCamera"
	_cam.add_to_group("rts_camera")
	add_child(_cam)
	_cam.setup(_mgr, 0)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SandboxUI"
	add_child(layer)
	# Dummy HUD host for the camera's drag-selection box.
	var hud := Control.new()
	hud.name = "SandboxHUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_to_group("hud")
	layer.add_child(hud)
	# Stats readout (top-left).
	var stats_panel := PanelContainer.new()
	stats_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stats_panel.position = Vector2(10, 10)
	stats_panel.add_theme_constant_override("separation", 4)
	layer.add_child(stats_panel)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	stats_panel.add_child(_stats_label)
	# Spawn bar (bottom-left).
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.position = Vector2(10, -64)
	bar.grow_horizontal = Control.GROW_DIRECTION_END
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	bar.add_child(h)
	_faction_opt = OptionButton.new()
	_faction_opt.add_item("Red (mine)", 0)
	_faction_opt.add_item("Blue (enemy)", 1)
	h.add_child(_faction_opt)
	_type_opt = OptionButton.new()
	for i in TYPES.size():
		_type_opt.add_item(TYPES[i], i)
	h.add_child(_type_opt)
	for c in COUNTS:
		var b := Button.new()
		b.text = str(c)
		b.tooltip_text = "Queue %d units" % c
		b.pressed.connect(_on_count_pressed.bind(c))
		h.add_child(b)
		_spawn_buttons.append(b)
	var spawn := Button.new()
	spawn.text = "Spawn"
	spawn.tooltip_text = "Spawn the selected count at the camera focus (red west, blue east of it)"
	spawn.pressed.connect(_on_spawn_pressed)
	h.add_child(spawn)
	var select_all := Button.new()
	select_all.text = "Select all mine"
	select_all.pressed.connect(_on_select_all)
	h.add_child(select_all)
	var attack := Button.new()
	attack.text = "F0 attack F1"
	attack.tooltip_text = "Order every red unit to attack-move to the blue spawn zone (exercises adaptive squads)"
	attack.pressed.connect(_on_attack_order.bind(0, 1))
	h.add_child(attack)
	var attack2 := Button.new()
	attack2.text = "F1 attack F0"
	attack2.tooltip_text = "Order every blue unit to attack-move to the red spawn zone"
	attack2.pressed.connect(_on_attack_order.bind(1, 0))
	h.add_child(attack2)
	var kill := Button.new()
	kill.text = "Kill all"
	kill.pressed.connect(_on_kill_all)
	h.add_child(kill)
	# Controls hint (bottom-right).
	var hint := Label.new()
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-10, -60)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 13)
	hint.text = "Drag LMB: select box | RMB: move / attack\nWheel: zoom | WASD: pan | TAB: top-down / FPS"
	layer.add_child(hint)


func _process(delta: float) -> void:
	_drain_spawn_queue()
	_update_stats()


## Queue formation positions around the camera focus (faction-offset).
func _queue_spawn(faction: int, unit_type: String, count: int) -> void:
	var focus := _camera_focus()
	var side := -1.0 if faction == 0 else 1.0
	var center := Vector3(focus.x + side * 12.0, 0, focus.z)
	var per_row := int(ceil(sqrt(float(count))))
	var idx := 0
	for i in count:
		var row := idx / per_row
		var col := idx % per_row
		var pos := center + Vector3(
			(col - per_row * 0.5) * FORMATION_SPACING, 0,
			(row - per_row * 0.5) * FORMATION_SPACING)
		_spawn_queue.append({"faction": faction, "type": unit_type, "pos": pos})
		idx += 1


func _drain_spawn_queue() -> void:
	var n := mini(SPAWN_PER_FRAME, _spawn_queue.size())
	for i in n:
		var job: Dictionary = _spawn_queue.pop_front()
		_spawn_one(int(job["faction"]), str(job["type"]), job["pos"] as Vector3)


func _spawn_one(faction: int, unit_type: String, pos: Vector3) -> void:
	var civ := CivData.for_civ_id(str(CIVS[faction]))
	var u := RTSUnit.new()
	u.setup(faction, unit_type, civ)
	u.unit_id = _mgr.alloc_unit_id()
	u.name = "RTSUnit_%d" % u.unit_id
	u.position = pos
	_armies.add_child(u)


func _camera_focus() -> Vector3:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var from := _cam.project_ray_origin(size * 0.5)
	var dir := _cam.project_ray_normal(size * 0.5)
	var hit = Plane(Vector3.UP, 0).intersects_ray(from, dir)
	return hit if hit else Vector3.ZERO


func _update_stats() -> void:
	var units := get_tree().get_nodes_in_group("rts_units")
	var alive := 0
	for u in units:
		if bool(u.get("alive")):
			alive += 1
	var selected := 0
	if _cam != null:
		selected = (_cam.get("_selected") as Array).size()
	var squads := _mgr.squads.size() if _mgr != null else 0
	var queued := _spawn_queue.size()
	_stats_label.text = "Units: %d alive (%d queued) | Selected: %d | Squads: %d | FPS: %d" % [
		alive, queued, selected, squads, Engine.get_frames_per_second()]


func _on_count_pressed(count: int) -> void:
	_selected_count = count


var _selected_count := 100


func _on_spawn_pressed() -> void:
	_queue_spawn(_faction_opt.selected, str(TYPES[_type_opt.selected]), _selected_count)


func _on_select_all() -> void:
	for u in get_tree().get_nodes_in_group("rts_units"):
		if int(u.get("faction")) == 0 and bool(u.get("alive")):
			u.rpc("set_selected", true)
			(_cam.get("_selected") as Array).append(u)


func _on_attack_order(from_faction: int, to_faction: int) -> void:
	var ids: Array = []
	for u in get_tree().get_nodes_in_group("rts_units"):
		if int(u.get("faction")) == from_faction and bool(u.get("alive")):
			ids.append(int(u.get("unit_id")))
	if ids.is_empty():
		return
	var dest := Vector3(30, 0, 0) if to_faction == 1 else Vector3(-30, 0, 0)
	# Local call: exercises the same squad-partition path as the camera's RPC.
	_mgr.order_move_squad(ids, dest)


func _on_kill_all() -> void:
	for u in get_tree().get_nodes_in_group("rts_units"):
		if _renderer != null:
			_renderer.unregister_unit(u)
		if _mgr != null and _mgr.spatial_hash != null:
			_mgr.spatial_hash.remove(u)
		u.queue_free()
	if _mgr != null:
		_mgr.squads.clear()
	(_cam.get("_selected") as Array).clear()
