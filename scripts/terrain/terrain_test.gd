extends Node3D
## Issue #103 test-scene driver. Run modes:
##   verify: headless proofs (determinism, height accuracy, water, walker)
##     godot --headless --path . res://scenes/terrain/terrain_test.tscn -- --mode=verify
##   perf: RTS sampling-path timings at N units
##     godot --headless --path . res://scenes/terrain/terrain_test.tscn -- --mode=perf --units=1500
##   shots: Xvfb screenshots (INSPECT the PNGs)
##     xvfb-run godot --path . res://scenes/terrain/terrain_test.tscn --resolution 1920x1080 -- --mode=shots --shot-dir=/tmp/ts

var _mode := "verify"
var _shot_dir := "/tmp/terrain_shots"
var _hide_water := false
var _units := 1500
var _fails := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[TERRAIN] PASS: ", label)
	else:
		_fails += 1
		printerr("[TERRAIN] FAIL: ", label)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--units="):
			_units = int(arg.get_slice("=", 1))
		elif arg.begins_with("--hide-water"):
			_hide_water = true
	_setup_camera_light()
	match _mode:
		"verify":
			await _run_verify()
		"perf":
			await _run_perf()
		"shots":
			await _run_shots()
		_:
			printerr("[TERRAIN] unknown mode: ", _mode)
			_fails += 1
	print("[TERRAIN] done, fails=", _fails)
	get_tree().quit(_fails)


func _setup_camera_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.10, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.name = "TestCam"
	cam.fov = 55.0
	add_child(cam)


func _make_terrain(seed_value: int) -> HeightmapTerrain:
	var t := HeightmapTerrain.new()
	t.map_points = 65
	t.cell_size = 1.0
	t.terrain_seed = seed_value
	t.noise_frequency = 0.035
	t.amplitude = 3.5
	t.water_level = -0.5
	t.pond_centers = [Vector3(12, 0, 10), Vector3(-14, 0, -8)]
	t.poi_points = [Vector3(0, 0, 0)]
	add_child(t)
	t.generate()
	return t


func _dry_waypoints(t: HeightmapTerrain, rng: RandomNumberGenerator, count: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var guard := 0
	while pts.size() < count and guard < 400:
		guard += 1
		var p := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-24, 24))
		if t.is_water(p):
			continue
		var ok := true
		for q in pts:
			if p.distance_to(q) < 12.0:
				ok = false
		if ok:
			pts.append(p)
	return pts


func _run_verify() -> void:
	print("[TERRAIN] verify start")
	var t := _make_terrain(1234)
	await get_tree().physics_frame
	# 1. Determinism: same seed -> identical heights; different seed -> different.
	# NOTE: t2/t3 stay OUT of the tree — their StaticBodies would corrupt the
	# raycast pass below. generate() works fine off-tree.
	var t2 := HeightmapTerrain.new()
	t2.terrain_seed = 1234
	t2.pond_centers = t.pond_centers
	t2.poi_points = t.poi_points
	t2.water_level = t.water_level
	t2.generate()
	_check(t.heights_copy() == t2.heights_copy(), "deterministic heights for same seed")
	var t3 := HeightmapTerrain.new()
	t3.terrain_seed = 999
	t3.generate()
	_check(t.heights_copy() != t3.heights_copy(), "different seed gives different heights")
	t2.free()
	t3.free()
	# 2. get_ground_height vs physics collision surface (200 random points).
	var space := get_world_3d().direct_space_state
	var max_err := 0.0
	var hits := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 200:
		var x := rng.randf_range(-28.0, 28.0)
		var z := rng.randf_range(-28.0, 28.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 30, z), Vector3(x, -30, z))
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		hits += 1
		var err := absf(float(hit["position"].y) - t.get_ground_height(Vector3(x, 0, z)))
		max_err = maxf(max_err, err)
	print("[TERRAIN] raycast hits=", hits, " max_err=", max_err)
	_check(hits >= 190, "raycasts hit terrain")
	_check(max_err < 0.05, "array height matches collision surface (5cm tolerance)")
	# 3. Water: plane exists, ponds are real water, is_water consistent.
	var water = t.get_node_or_null("WaterPlane")
	_check(water != null and water.visible, "water plane renders")
	var water_pts := 0
	var consistent := true
	for i in 400:
		var x := rng.randf_range(-28.0, 28.0)
		var z := rng.randf_range(-28.0, 28.0)
		var p := Vector3(x, 0, z)
		if t.is_water(p):
			water_pts += 1
		if t.is_water(p) != (t.get_ground_height(p) < t.water_level):
			consistent = false
	print("[TERRAIN] water sample points below level: ", water_pts, "/400")
	_check(water_pts > 10, "ponds carved real water zones")
	_check(consistent, "is_water consistent with height < water_level")
	# 4. Walker: physics body rides terrain via gravity, stays glued.
	var w := TerrainWalker.new()
	w.terrain = t
	w.waypoints = _dry_waypoints(t, rng, 4)
	w.position = Vector3(0, t.get_ground_height(Vector3.ZERO) + 2.0, 0)
	# Spawn must also be dry or the walker starts inside water.
	for attempt in 40:
		var p := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-24, 24))
		if not t.is_water(p):
			w.position = Vector3(p.x, t.get_ground_height(p) + 2.0, p.z)
			break
	add_child(w)
	var entered_water := false
	for i in 600:
		await get_tree().physics_frame
		if t.is_water(w.global_position):
			entered_water = true
	print("[TERRAIN] walker distance=", w.distance_walked, " max_dev=", w.max_deviation)
	_check(w.distance_walked > 5.0, "walker actually walked")
	_check(w.max_deviation < 0.6, "walker stays glued to terrain")
	_check(not entered_water, "walker never entered water (blocked like a wall)")
	print("[TERRAIN] verify done")


func _run_perf() -> void:
	print("[TERRAIN] perf start units=", _units)
	var t := _make_terrain(777)
	await get_tree().physics_frame
	var units: Array[TerrainPerfUnit] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in _units:
		var u := TerrainPerfUnit.new()
		u.terrain = t
		# Scatter on dry land.
		for attempt in 40:
			var p := Vector3(rng.randf_range(-26, 26), 0, rng.randf_range(-26, 26))
			if not t.is_water(p):
				u.position = Vector3(p.x, t.get_ground_height(p), p.z)
				break
		add_child(u)
		units.append(u)
	# Warm up.
	for i in 30:
		await get_tree().physics_frame
		for u in units:
			u.tick(1.0 / 60.0)
	# Measure the sampling path.
	var total_us := 0
	var frames := 300
	for i in frames:
		await get_tree().physics_frame
		var t0 := Time.get_ticks_usec()
		for u in units:
			u.tick(1.0 / 60.0)
		total_us += Time.get_ticks_usec() - t0
	var avg_us := float(total_us) / float(frames)
	print("[TERRAIN] PERF units=", _units, " avg_us_per_frame=", snappedf(avg_us, 1),
			" ns_per_unit=", snappedf(avg_us * 1000.0 / float(_units), 1))
	print("[TERRAIN] perf done")


func _run_shots() -> void:
	# Clean screenshots: the CRT shader curves the viewport; disable for inspection.
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	print("[TERRAIN] shots start")
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var t := _make_terrain(20261012)
	if _hide_water:
		t.get_node("WaterPlane").hide()
	var cam: Camera3D = $TestCam
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Walkers + slope units for the scene.
	var w := TerrainWalker.new()
	w.terrain = t
	w.waypoints = _dry_waypoints(t, rng, 4)
	w.position = Vector3(0, t.get_ground_height(Vector3.ZERO) + 2.0, 0)
	# Spawn must also be dry or the walker starts inside water.
	for attempt in 40:
		var p := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-24, 24))
		if not t.is_water(p):
			w.position = Vector3(p.x, t.get_ground_height(p) + 2.0, p.z)
			break
	add_child(w)
	for i in 40:
		var u := TerrainPerfUnit.new()
		u.terrain = t
		for attempt in 40:
			var p := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-24, 24))
			if not t.is_water(p):
				u.position = Vector3(p.x, t.get_ground_height(p), p.z)
				break
		add_child(u)
	await get_tree().physics_frame
	# View 1: overview.
	cam.position = Vector3(0, 42, 46)
	cam.look_at(Vector3(0, 0, 0))
	await _settle(20)
	await _snap("terrain_overview.png")
	# View 2: water close-up (pond at 12,10).
	cam.position = Vector3(12, 8, 22)
	cam.look_at(Vector3(12, 0, 8))
	await _settle(20)
	await _snap("terrain_water.png")
	# View 3: low angle on slopes with units.
	cam.position = Vector3(-24, 5, 20)
	cam.look_at(Vector3(-6, 1, 2))
	await _settle(20)
	await _snap("terrain_slope_units.png")
	print("[TERRAIN] shots done")


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir + "/" + name)
	print("[TERRAIN] saved ", _shot_dir + "/" + name)
