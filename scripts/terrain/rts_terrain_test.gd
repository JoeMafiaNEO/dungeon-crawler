extends Node3D
## Issue #103: the REAL RTS stack on the experimental heightmap terrain.
## TEST SCENE ONLY — no production code is modified. Bootstraps the same
## stack as the army sandbox (RTSManager + RTSUnitRenderer + RTSCamera +
## RTSUnit, same spawn path) over a HeightmapTerrain built with the mock
## field flavor's parameters, spawns two armies on opposite hillsides,
## and seats every unit on the ground.
##
## How seating works: unit.gd's movement code hard-clamps land units to
## y=0 (production maps are flat). This driver re-snaps each unit's y to
## HeightmapTerrain.get_ground_height() in _process — which runs AFTER
## the physics step (where the clamp happens) and, via process_priority,
## BEFORE RTSUnitRenderer._process reads the unit positions into the
## MultiMesh instances. The rendered armies therefore follow the terrain
## even though the units' own physics still thinks the world is flat.
##
## Run modes:
##   shots: Xvfb screenshots (top-down / low / close) — INSPECT the PNGs
##     xvfb-run godot --path . res://scenes/terrain/rts_terrain_test.tscn \
##       --resolution 1920x1080 -- --mode=shots --shot-dir=/tmp/shots
##   (default): interactive — TAB toggles command (flat) / FPS (upright).

const CIVS := {0: "iron_vanguard", 1: "shadow_covenant"}
const SPACING := 1.4

var _terrain: HeightmapTerrain
var _mgr: RTSManager
var _renderer: RTSUnitRenderer
var _cam: RTSCamera
var _armies: Node3D
var _units: Array = []
var _mode := "run"
var _shot_dir := "/tmp/rts_terrain_shots"
var _fails := 0
var _skipped_water := 0
var _red_anchor := Vector3(-22, 0, 8)
var _blue_anchor := Vector3(24, 0, -8)


func _ready() -> void:
	# Snap runs before every other _process (notably the renderer's).
	process_priority = -100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	_setup_env()
	_build_terrain()
	_build_rts_stack()
	_dress_light()
	_red_anchor = _find_anchor(_red_anchor)
	_blue_anchor = _find_anchor(_blue_anchor)
	_spawn_army(0, _red_anchor, 1.0)
	_spawn_army(1, _blue_anchor, -1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _mode == "shots":
		# Freeze the RTS camera: shots pose it explicitly per view.
		_cam.set_process(false)
		_cam.set_process_input(false)
		await _run_shots()
		print("[RTST] done fails=", _fails)
		get_tree().quit(_fails)
	else:
		_set_view(true)
		_cam.position = Vector3(0, 70, 0.001)
		_cam.rotation = Vector3(-PI / 2, 0, 0)


func _process(_delta: float) -> void:
	if _terrain == null:
		return
	for u in _units:
		if not is_instance_valid(u):
			continue
		var n := u as Node3D
		var p := n.global_position
		var gy := _terrain.get_ground_height(p)
		if absf(p.y - gy) > 0.0005:
			n.global_position = Vector3(p.x, gy, p.z)


# --- world -------------------------------------------------------------------

func _setup_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = false
	add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "Environment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.55, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)


## Mock-field parameters (scripts/terrain/mock_level.gd "field" flavor).
func _build_terrain() -> void:
	_terrain = HeightmapTerrain.new()
	_terrain.name = "Terrain"
	_terrain.map_points = 97
	_terrain.cell_size = 1.0
	_terrain.terrain_seed = 7101
	_terrain.noise_frequency = 0.034
	_terrain.amplitude = 3.0
	_terrain.water_level = -0.55
	_terrain.smooth_passes = 2
	_terrain.flatten_radius = 9.0
	_terrain.pond_radius = 6.0
	_terrain.pond_depth = 1.8
	_terrain.poi_points.append(Vector3(0, 0, 0))
	_terrain.poi_points.append(Vector3(16, 0, -14))
	_terrain.pond_centers.append(Vector3(20, 0, 16))
	_terrain.pond_centers.append(Vector3(-22, 0, -14))
	add_child(_terrain)
	_terrain.generate()


## Same bootstrap as RTSArmySandbox._build_rts_stack().
func _build_rts_stack() -> void:
	_mgr = RTSManager.new()
	_mgr.name = "RTSManager"
	add_child(_mgr)
	_armies = Node3D.new()
	_armies.name = "Armies"
	add_child(_armies)
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


# --- helpers -----------------------------------------------------------------

func _ground(p: Vector3) -> float:
	return _terrain.get_ground_height(p)


func _slope(p: Vector3) -> float:
	var e := 0.9
	var dx := _ground(p + Vector3(e, 0, 0)) - _ground(p + Vector3(-e, 0, 0))
	var dz := _ground(p + Vector3(0, 0, e)) - _ground(p + Vector3(0, 0, -e))
	return sqrt(dx * dx + dz * dz) / (2.0 * e)


## Prefer a dry, moderate-slope hillside near the preferred anchor so the
## armies visibly follow the ground instead of standing on the flat POIs.
func _find_anchor(preferred: Vector3) -> Vector3:
	var best := preferred
	var best_score: float = -1000.0
	var radii: Array[float] = [0.0, 3.0, 6.0, 9.0, 12.0]
	for r in radii:
		var steps := 1 if r == 0.0 else 10
		for i in steps:
			var a := TAU * float(i) / float(steps)
			var p := preferred + Vector3(cos(a) * r, 0, sin(a) * r)
			if absf(p.x) > 42.0 or absf(p.z) > 42.0:
				continue
			if _terrain.is_water(p):
				continue
			var s := _slope(p)
			if s > 0.8:
				continue
			var score: float = 6.0 - absf(s - 0.28) * 3.0 - r * 0.15
			if score > best_score:
				best_score = score
				best = p
	return best


## Light dressing for scale (same PropBuilder path as the mock levels),
## kept clear of both army anchors.
func _dress_light() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var placed: Array = []
	_scatter("tree", 22, rng, placed, 4.5, 0.6, 12.0)
	_scatter("pine", 6, rng, placed, 4.5, 0.65, 16.0)
	_scatter("rock", 8, rng, placed, 5.0, 0.9, 10.0)


func _scatter(type: String, count: int, rng: RandomNumberGenerator, placed: Array,
		min_dist: float, max_slope: float, r_min: float) -> void:
	var r_max := _terrain.half_extent() - 2.0
	var done := 0
	var guard := 0
	while done < count and guard < count * 60:
		guard += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (r_max - r_min) + r_min
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if _terrain.is_water(p) or _slope(p) > max_slope:
			continue
		if p.distance_to(_red_anchor) < 13.0 or p.distance_to(_blue_anchor) < 13.0:
			continue
		var far := true
		for q in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < min_dist:
				far = false
				break
		if not far:
			continue
		placed.append(p)
		var prop := PropBuilder.build(type, 1.0, {"pos": p})
		prop.position = Vector3(p.x, _ground(p), p.z)
		prop.rotation.y = rng.randf() * TAU
		add_child(prop)
		done += 1


# --- armies --------------------------------------------------------------------

## Formation in local space: spearman block up front, archer rows behind,
## a knight column on the south flank. `forward` is +1 (red, faces east)
## or -1 (blue, faces west). Water slots are nudged toward the anchor;
## slots that stay wet are skipped (counted in _skipped_water).
func _spawn_army(faction: int, anchor: Vector3, forward: float) -> void:
	var slots: Array = []
	for row in 8:
		for col in 12:
			slots.append({"type": "spearman", "off": Vector3(
				(float(row) - 3.5) * SPACING * forward, 0,
				(float(col) - 5.5) * SPACING)})
	for row in 2:
		for col in 12:
			slots.append({"type": "archer", "off": Vector3(
				-forward * (6.3 + float(row) * SPACING), 0,
				(float(col) - 5.5) * SPACING)})
	for col in 10:
		slots.append({"type": "knight", "off": Vector3(
			(float(col) - 4.5) * SPACING * forward, 0, 10.5)})
	for job in slots:
		var pos: Variant = _dry_pos(anchor + (job["off"] as Vector3), anchor)
		if pos == null:
			_skipped_water += 1
			continue
		_spawn_one(faction, str(job["type"]), pos as Vector3)


## Walk a spawn slot toward the anchor until it is dry; null if it never is.
func _dry_pos(pos: Vector3, anchor: Vector3) -> Variant:
	var p := pos
	for i in 9:
		if not _terrain.is_water(p):
			return p
		p = p.move_toward(anchor, 1.0)
		p.y = 0.0
	return null if _terrain.is_water(p) else p


## Same spawn path as RTSArmySandbox._spawn_one().
func _spawn_one(faction: int, unit_type: String, pos: Vector3) -> void:
	var civ := CivData.for_civ_id(str(CIVS[faction]))
	var u := RTSUnit.new()
	u.setup(faction, unit_type, civ)
	u.unit_id = _mgr.alloc_unit_id()
	u.name = "RTSUnit_%d" % u.unit_id
	u.position = Vector3(pos.x, _ground(pos), pos.z)
	_armies.add_child(u)
	_units.append(u)


# --- screenshots ---------------------------------------------------------------

func _set_view(command: bool) -> void:
	_cam.active = command
	_cam.current = true
	get_tree().call_group("rts_units", "_on_command_view_toggled", command)


func _run_shots() -> void:
	# CRT shader curves the viewport; disable for clean inspection shots.
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	print("[RTST] shots start units=", _units.size(),
		" skipped_water=", _skipped_water,
		" red_anchor=", _red_anchor, " blue_anchor=", _blue_anchor)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	# Let the armies settle (separation/aggro staggers run, units sleep).
	for i in 60:
		await get_tree().physics_frame
	# View 1: top-down command view (sprites lie flat, as in the TAB view).
	_set_view(true)
	_cam.position = Vector3(0, 80, 0.001)
	_cam.rotation = Vector3(-PI / 2, 0, 0)
	await _settle(15)
	await _snap("rts_terrain_topdown.png")
	# View 2: low angle across the valley (sprites upright, Y-billboarded).
	_set_view(false)
	var lp := _red_anchor + Vector3(-11, 0, 12)
	_cam.position = Vector3(lp.x, _ground(lp) + 2.4, lp.z)
	_cam.look_at(Vector3(_blue_anchor.x, _ground(_blue_anchor) + 1.0, _blue_anchor.z))
	await _settle(15)
	await _snap("rts_terrain_low.png")
	# View 3: red army marches up toward the central flattened hill on the
	# real squad path; close camera watches the column on the slope.
	var ids: Array = []
	for u in _units:
		if int(u.get("faction")) == 0:
			ids.append(int(u.get("unit_id")))
	_mgr.order_move_squad(ids, Vector3(-3, 0, 3))
	for i in 130:
		await get_tree().physics_frame
	# Tight frame on the column head climbing the west slope. (Wider framings
	# catch the archer tail at the pond shore west of the red start, where
	# the flat transparent water plane tints the shoreline units.)
	_cam.fov = 55.0
	var cp := Vector3(-7, 0, 9)
	_cam.position = Vector3(cp.x, _ground(cp) + 1.9, cp.z)
	_cam.look_at(Vector3(-14, _ground(Vector3(-14, 0, 4)) + 0.8, 4))
	await _settle(10)
	await _snap("rts_terrain_close.png")
	_report_seating()
	print("[RTST] shots done")


func _report_seating() -> void:
	var max_dev := 0.0
	var wet := 0
	for u in _units:
		if not is_instance_valid(u):
			continue
		var p := (u as Node3D).global_position
		max_dev = maxf(max_dev, absf(p.y - _ground(p)))
		if _terrain.is_water(p):
			wet += 1
	print("[RTST] seating: units=", _units.size(),
		" max |y-ground|=", snappedf(max_dev, 0.001),
		" units standing in water=", wet)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fails += 1
		printerr("[RTST] FAIL empty image for ", file_name)
		return
	img.save_png(_shot_dir + "/" + file_name)
	print("[RTST] saved ", _shot_dir + "/" + file_name)
