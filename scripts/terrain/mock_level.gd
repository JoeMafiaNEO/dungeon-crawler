extends Node3D
## Issue #103 mock level scenes — TEST SCENES ONLY, no integration into
## dungeon.gd / procgen / level themes. One driver, five flavors selected
## by the exported `flavor` in the .tscn (field / docks / highlands /
## dungeon / depths). Each builds a HeightmapTerrain with per-flavor
## params, dresses it with existing repo props (PropBuilder) snapped to
## get_ground_height(), and drops a walker + perf units in for scale.
## The depths flavor additionally stands the REAL ProcGen maze layout
## (theme_depths, read-only) on the terrain, one mazewall per solid cell.
##
## Run modes:
##   shots: Xvfb screenshots (overview + low angle) — INSPECT the PNGs
##     xvfb-run godot --path . res://scenes/terrain/mock_field.tscn \
##       --resolution 1920x1080 -- --mode=shots --shot-dir=/tmp/shots
##   (default): builds the scene and idles — open in the editor / F6 to look.

@export_enum("field", "docks", "highlands", "dungeon", "depths") var flavor: String = "field"

var _terrain: HeightmapTerrain
var _units: Array[TerrainPerfUnit] = []
var _cam: Camera3D
var _mode := "run"
var _shot_dir := "/tmp/terrain_mock_shots"
var _fails := 0
## Depths flavor: real maze layout (read-only) + corridor view for shots.
var _maze_layout: LevelLayout
var _depths_low: Array = []


func _config() -> Dictionary:
	match flavor:
		"field":
			return {
				"seed": 7101, "freq": 0.034, "amp": 3.0, "water": -0.55,
				"smooth": 2, "flatten_r": 9.0,
				"pois": [Vector3(0, 0, 0), Vector3(16, 0, -14)],
				"ponds": [Vector3(20, 0, 16), Vector3(-22, 0, -14)],
				"pond_r": 6.0, "pond_depth": 1.8,
				"bg": Color(0.35, 0.55, 0.75), "sun_energy": 1.15,
				"sun_color": Color(1.0, 0.95, 0.85), "fog": 0.0,
				"amb_energy": 0.9,
			}
		"docks":
			return {
				"seed": 4202, "freq": 0.024, "amp": 1.8, "water": -0.30,
				"smooth": 3, "flatten_r": 9.0,
				"pois": [Vector3(0, 0, -10)],
				"ponds": [Vector3(0, 0, 28), Vector3(15, 0, 32), Vector3(-15, 0, 32),
						Vector3(28, 0, 24), Vector3(-28, 0, 24)],
				"pond_r": 10.0, "pond_depth": 2.2,
				"bg": Color(0.55, 0.62, 0.68), "sun_energy": 0.85,
				"sun_color": Color(0.9, 0.95, 1.0), "fog": 0.005,
				"amb_energy": 0.85,
			}
		"dungeon":
			return {
				"seed": 6106, "freq": 0.05, "amp": 3.4, "water": -0.85,
				"smooth": 2, "flatten_r": 8.0, "points": 49,
				"pois": [Vector3(0, 0, 0)],
				"ponds": [Vector3(16, 0, 12)],
				"pond_r": 5.5, "pond_depth": 1.7,
				"bg": Color(0.03, 0.03, 0.05), "sun_energy": 0.35,
				"sun_color": Color(0.8, 0.8, 0.9), "fog": 0.028,
				"fog_color": Color(0.04, 0.04, 0.07),
				"amb_energy": 0.5,
				"tint_bed": Color(0.10, 0.10, 0.12),
				"tint_low": Color(0.20, 0.20, 0.23),
				"tint_mid": Color(0.30, 0.30, 0.33),
				"tint_high": Color(0.42, 0.41, 0.45),
				"water_shallow": Color(0.10, 0.16, 0.22, 0.9),
				"water_deep": Color(0.02, 0.05, 0.09, 0.95),
				"ov_pos": Vector3(0, 44, 46),
			}
		"depths":
			return {
				# Terrain sized to the real depths arena: 24 cells x 2m = 48m.
				"seed": 777, "maze_seed": 20240, "freq": 0.035, "amp": 2.4,
				"water": -3.2, "smooth": 2, "flatten_r": 8.0, "points": 49,
				"pois": [Vector3(0, 0, 0)],
				"ponds": [],
				"pond_r": 5.0, "pond_depth": 1.5,
				"bg": Color(0.02, 0.01, 0.04), "sun_energy": 0.45,
				"sun_color": Color(0.7, 0.6, 1.0), "fog": 0.012,
				"fog_color": Color(0.08, 0.05, 0.14),
				"amb_energy": 0.6,
				"tint_bed": Color(0.08, 0.07, 0.11),
				"tint_low": Color(0.13, 0.11, 0.17),
				"tint_mid": Color(0.18, 0.16, 0.24),
				"tint_high": Color(0.27, 0.25, 0.35),
				"ov_pos": Vector3(0, 44, 46),
			}
		_: # highlands
			return {
				"seed": 9303, "freq": 0.055, "amp": 8.5, "water": -3.4,
				"smooth": 1, "flatten_r": 6.0,
				"pois": [Vector3(0, 0, 4)],
				"ponds": [],
				"pond_r": 5.0, "pond_depth": 1.5,
				"bg": Color(0.10, 0.10, 0.18), "sun_energy": 0.8,
				"sun_color": Color(0.8, 0.85, 1.0), "fog": 0.0,
				"amb_energy": 0.55,
			}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	var cfg := _config()
	_setup_env(cfg)
	_build_terrain(cfg)
	_dress(cfg)
	_populate(cfg)
	if _mode == "shots":
		await _run_shots(cfg)
		print("[MOCK] done ", flavor, " fails=", _fails)
		get_tree().quit(_fails)
	# Run mode: park the camera on the overview; _process ticks the units.
	_cam.position = Vector3(0, 60, 64)
	_cam.look_at(Vector3(0, 0, 0))


func _process(delta: float) -> void:
	if _mode == "shots":
		return
	for u in _units:
		u.tick(delta)


func _setup_env(cfg: Dictionary) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = cfg["sun_energy"]
	sun.light_color = cfg["sun_color"]
	sun.shadow_enabled = false
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = cfg["bg"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = cfg["amb_energy"]
	if float(cfg["fog"]) > 0.0:
		e.fog_enabled = true
		e.fog_light_color = cfg.get("fog_color", Color(0.62, 0.68, 0.75))
		e.fog_density = cfg["fog"]
	env.environment = e
	add_child(env)
	_cam = Camera3D.new()
	_cam.name = "MockCam"
	_cam.fov = 55.0
	add_child(_cam)


func _build_terrain(cfg: Dictionary) -> void:
	_terrain = HeightmapTerrain.new()
	_terrain.map_points = int(cfg.get("points", 97))
	_terrain.cell_size = 1.0
	_terrain.terrain_seed = cfg["seed"]
	_terrain.noise_frequency = cfg["freq"]
	_terrain.amplitude = cfg["amp"]
	_terrain.water_level = cfg["water"]
	if cfg.has("tint_bed"):
		_terrain.tint_bed = cfg["tint_bed"]
		_terrain.tint_low = cfg["tint_low"]
		_terrain.tint_mid = cfg["tint_mid"]
		_terrain.tint_high = cfg["tint_high"]
	if cfg.has("water_shallow"):
		_terrain.water_shallow = cfg["water_shallow"]
		_terrain.water_deep = cfg["water_deep"]
	_terrain.smooth_passes = cfg["smooth"]
	_terrain.flatten_radius = cfg["flatten_r"]
	_terrain.pond_radius = cfg["pond_r"]
	_terrain.pond_depth = cfg["pond_depth"]
	for p in cfg["pois"]:
		_terrain.poi_points.append(p)
	for p in cfg["ponds"]:
		_terrain.pond_centers.append(p)
	add_child(_terrain)
	_terrain.generate()


# --- helpers ---------------------------------------------------------------

func _ground(p: Vector3) -> float:
	return _terrain.get_ground_height(p)


func _slope(p: Vector3) -> float:
	var e := 0.9
	var dx := _ground(p + Vector3(e, 0, 0)) - _ground(p + Vector3(-e, 0, 0))
	var dz := _ground(p + Vector3(0, 0, e)) - _ground(p + Vector3(0, 0, -e))
	return sqrt(dx * dx + dz * dz) / (2.0 * e)


func _place(type: String, p: Vector3, rot_y: float = 0.0, size: float = 1.0) -> Node3D:
	var prop := PropBuilder.build(type, size, {"pos": p})
	prop.position = Vector3(p.x, _ground(p), p.z)
	prop.rotation.y = rot_y
	add_child(prop)
	return prop


func _far_enough(p: Vector3, placed: Array, min_dist: float) -> bool:
	for q in placed:
		if Vector2(p.x - q.x, p.z - q.z).length() < min_dist:
			return false
	return true


## Scatter dry-land props: not in water, slope-capped, min-dist spaced.
func _scatter(type: String, count: int, rng: RandomNumberGenerator, placed: Array,
		min_dist: float, max_slope: float, r_min: float = 0.0, r_max: float = 44.0) -> void:
	r_max = minf(r_max, _terrain.half_extent() - 2.0)
	var done := 0
	var guard := 0
	while done < count and guard < count * 60:
		guard += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (r_max - r_min) + r_min
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if _terrain.is_water(p):
			continue
		if _slope(p) > max_slope:
			continue
		if not _far_enough(p, placed, min_dist):
			continue
		placed.append(p)
		_place(type, p, rng.randf() * TAU)
		done += 1


## Scatter along the shoreline band (reeds): ground just above/below water.
func _scatter_shore(type: String, count: int, rng: RandomNumberGenerator) -> void:
	var done := 0
	var guard := 0
	while done < count and guard < count * 200:
		guard += 1
		var p := Vector3(rng.randf_range(-44, 44), 0, rng.randf_range(-44, 44))
		var h := _ground(p)
		if h < _terrain.water_level - 0.05 or h > _terrain.water_level + 0.3:
			continue
		_place(type, p, rng.randf() * TAU)
		done += 1


func _dry_points(rng: RandomNumberGenerator, count: int, max_slope: float,
		center := Vector3.ZERO, r_max := 44.0) -> Array[Vector3]:
	r_max = minf(r_max, _terrain.half_extent() - 2.0)
	var pts: Array[Vector3] = []
	var guard := 0
	while pts.size() < count and guard < 600:
		guard += 1
		var p := center + Vector3(rng.randf_range(-r_max, r_max), 0, rng.randf_range(-r_max, r_max))
		if absf(p.x) > 46.0 or absf(p.z) > 46.0:
			continue
		if _terrain.is_water(p) or _slope(p) > max_slope:
			continue
		pts.append(p)
	return pts


# --- dressing per flavor ---------------------------------------------------

func _dress(cfg: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg["seed"]) * 31 + 7
	var placed: Array = [] # shared min-dist registry for big props
	match flavor:
		"field": _dress_field(rng, placed)
		"docks": _dress_docks(rng, placed)
		"dungeon": _dress_dungeon(rng, placed)
		"depths": _dress_depths(rng, placed)
		_: _dress_highlands(rng, placed)


func _dress_field(rng: RandomNumberGenerator, placed: Array) -> void:
	# Village cluster on the flattened POI at (16,-14).
	for hp in [Vector3(12, 0, -17), Vector3(19, 0, -12), Vector3(15, 0, -8)]:
		placed.append(hp)
		_place("house", hp, rng.randf_range(-0.4, 0.4))
	_place("well", Vector3(3.5, 0, 3.5))
	_place("cart", Vector3(13, 0, -18), 0.7)
	_place("cart", Vector3(-4, 0, 6), -1.2)
	# Fence line flanking the arena -> village path.
	for i in 6:
		var t := float(i) / 5.0
		var base := Vector3(6, 0, -5).lerp(Vector3(12, 0, -10), t)
		_place("fence", base + Vector3(0, 0, 1.6), 0.9)
		_place("fence", base + Vector3(0, 0, -1.6), 0.9)
	# Street lamps: arena corners + village.
	for lp in [Vector3(6, 0, 6), Vector3(-6, 0, 6), Vector3(6, 0, -6), Vector3(-6, 0, -6),
			Vector3(16, 0, -11), Vector3(11, 0, -13)]:
		_place("lamp", lp)
	_scatter("haybale", 4, rng, placed, 4.0, 0.5, 10.0, 30.0)
	_scatter("tree", 26, rng, placed, 4.0, 0.55, 13.0)
	_scatter("pine", 6, rng, placed, 4.0, 0.6, 18.0)
	_scatter("rock", 8, rng, placed, 5.0, 0.8, 12.0)
	_scatter("mushroom", 4, rng, placed, 2.0, 0.6)
	_scatter("grass", 40, rng, [], 1.2, 0.7)


func _dress_docks(rng: RandomNumberGenerator, placed: Array) -> void:
	var flat := Vector3(0, 0, -10)
	# Settlement on the flattened POI: two huts, crates, barrels, a cart.
	for hp in [Vector3(-5, 0, -13), Vector3(5, 0, -14)]:
		placed.append(hp)
		_place("house", hp, rng.randf_range(-0.3, 0.3))
	_scatter("barrel", 5, rng, placed, 1.6, 0.3, 0.0, 12.0)
	_scatter("crate", 4, rng, placed, 1.8, 0.3, 0.0, 12.0)
	_place("cart", Vector3(2, 0, -6), 2.4)
	# Two piers reaching into the lake: find the shoreline walking from a
	# lake point back toward the settlement, pier faces the water.
	for lake_pt in [Vector3(6, 0, 30), Vector3(-10, 0, 30)]:
		var shore_v: Variant = _find_shore(lake_pt, flat)
		if shore_v != null:
			var shore: Vector3 = shore_v
			var dir: Vector3 = lake_pt - shore
			dir.y = 0
			dir = dir.normalized()
			var pier := PropBuilder.build("pier", 1.0, {"pos": shore})
			pier.position = Vector3(shore.x, _ground(shore), shore.z)
			pier.rotation.y = atan2(dir.x, dir.z)
			add_child(pier)
			_place("dock_lantern", shore + Vector3(1.2, 0, -1.0))
	_place("dock_lantern", Vector3(-4, 0, -3))
	_place("dock_lantern", Vector3(3, 0, -16))
	# Waterwheel at the shore east of the settlement.
	var wheel_shore_v: Variant = _find_shore(Vector3(24, 0, 20), flat)
	if wheel_shore_v != null:
		var wheel_shore: Vector3 = wheel_shore_v
		_place("waterwheel", wheel_shore, 0.8)
	_scatter_shore("reed", 26, rng)
	_scatter("tree", 8, rng, placed, 5.0, 0.4, 16.0)
	_scatter("rock", 5, rng, placed, 5.0, 0.5)
	_scatter("grass", 30, rng, [], 1.2, 0.5)


## Walk from a water point toward `toward` until dry land; return that point.
func _find_shore(in_water: Vector3, toward: Vector3) -> Variant:
	var steps := 80
	for i in steps + 1:
		var p := in_water.lerp(toward, float(i) / float(steps))
		if not _terrain.is_water(p):
			return p
	return null


func _dress_highlands(rng: RandomNumberGenerator, placed: Array) -> void:
	var camp := Vector3(0, 0, 4)
	# Camp on the flattened POI: tents, torches, crates.
	_place("tent", camp + Vector3(-2.5, 0, -1.5), 0.5)
	_place("tent", camp + Vector3(2.5, 0, 1.0), -2.2)
	for tp in [camp + Vector3(0, 0, -3), camp + Vector3(-3.5, 0, 1.5), camp + Vector3(3.5, 0, -2)]:
		_place("torch", tp)
	_place("crate", camp + Vector3(0.5, 0, 3.0), 0.3)
	_place("barrel", camp + Vector3(-1.2, 0, 3.2), 0.0)
	# Ruined pillars on a shoulder.
	_scatter("pillar", 2, rng, placed, 8.0, 0.7, 14.0, 30.0)
	_scatter("pine", 38, rng, placed, 3.2, 1.0, 8.0)
	_scatter("rock", 22, rng, placed, 4.0, 1.4, 6.0)
	_scatter("stalagmite", 6, rng, placed, 4.0, 1.2)
	_scatter("crystal", 3, rng, placed, 7.0, 0.9, 12.0)
	_scatter("rubble", 5, rng, placed, 3.0, 1.0)
	_scatter("bones", 3, rng, placed, 6.0, 0.8)
	_scatter("mushroom", 5, rng, placed, 2.0, 0.9)


func _dress_dungeon(rng: RandomNumberGenerator, placed: Array) -> void:
	# Pillar hall: two rows flanking the flattened center, like the real
	# dungeon theme's pillar obstacles.
	for side in [-6.0, 6.0]:
		for z in [-14.0, -7.0, 0.0, 7.0, 14.0]:
			var pp := Vector3(side, 0, z)
			placed.append(pp)
			_place("pillar", pp)
	# Torch ring around the hall + a pair at the pool shore.
	for tp in [Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(-10, 0, 10),
			Vector3(10, 0, 10), Vector3(0, 0, -16), Vector3(0, 0, 16),
			Vector3(-16, 0, 0), Vector3(16, 0, -2), Vector3(11, 0, 8), Vector3(21, 0, 5)]:
		_place("torch", tp)
	_scatter("rubble", 10, rng, placed, 3.0, 0.9)
	_scatter("bones", 6, rng, placed, 3.0, 0.8)
	_scatter("crate", 6, rng, placed, 3.0, 0.7)
	_scatter("stalagmite", 7, rng, placed, 4.0, 1.1)
	_scatter("rock", 8, rng, placed, 4.0, 1.0)
	_scatter("mushroom", 4, rng, placed, 2.0, 0.8)


## Depths: stand the REAL maze layout on the terrain. The layout comes
## from ProcGen.generate(theme_depths, seed) — read-only, procgen itself
## is untouched. Every solid cell (border WALL + maze OBSTACLE) gets one
## PropBuilder mazewall whose base y is the LOWEST terrain sample under
## its 2m footprint, so no wall floats; the box sinks into the high side.
func _dress_depths(rng: RandomNumberGenerator, placed: Array) -> void:
	var theme := load("res://data/levels/theme_depths.tres") as LevelTheme
	_maze_layout = ProcGen.generate(theme, int(_config()["maze_seed"]))
	var n := _maze_layout.grid_size
	var cell := _maze_layout.cell_size
	var walls := 0
	var worst_range := 0.0
	var worst_slope := 0.0
	for cz in n:
		for cx in n:
			var kind := _maze_layout.cell_at(cx, cz)
			if kind == LevelLayout.FLOOR:
				# Steepest step between adjacent floor cells = corridor read.
				for d in [Vector2i(1, 0), Vector2i(0, 1)]:
					if _maze_layout.cell_at(cx + d.x, cz + d.y) == LevelLayout.FLOOR:
						var a := _maze_layout.cell_to_world(cx, cz)
						var b := _maze_layout.cell_to_world(cx + d.x, cz + d.y)
						worst_slope = maxf(worst_slope,
							absf(_ground(a) - _ground(b)) / cell)
				continue
			var wp := _maze_layout.cell_to_world(cx, cz)
			# 3x3 samples over the footprint (terrain grid is 1m, cell 2m).
			var hmin := INF
			var hmax := -INF
			for dz in [-1.0, 0.0, 1.0]:
				for dx in [-1.0, 0.0, 1.0]:
					var h := _ground(wp + Vector3(dx, 0, dz))
					hmin = minf(hmin, h)
					hmax = maxf(hmax, h)
			worst_range = maxf(worst_range, hmax - hmin)
			var wall := PropBuilder.build("mazewall", 1.0, {"pos": wp})
			wall.position = Vector3(wp.x, hmin, wp.z)
			add_child(wall)
			walls += 1
	# The layout's own dressing props (crystals, bones, ...) on floor cells.
	var dressed := 0
	for p in _maze_layout.props:
		if str(p["type"]) == "mazewall":
			continue
		var pp: Vector3 = p["pos"]
		var prop := PropBuilder.build(str(p["type"]), float(p["scl"]), {"pos": pp})
		prop.position = Vector3(pp.x, _ground(pp), pp.z)
		prop.rotation.y = float(p["rot"])
		add_child(prop)
		dressed += 1
	# Torches at dead ends (the real game's key spots) + around the arena.
	var torch_spots: Array[Vector3] = []
	for i in mini(6, _maze_layout.maze_dead_ends.size()):
		torch_spots.append(_maze_layout.maze_dead_ends[i])
	for tp in [Vector3(5, 0, 5), Vector3(-5, 0, 5), Vector3(5, 0, -5), Vector3(-5, 0, -5)]:
		torch_spots.append(tp)
	for tp in torch_spots:
		_place("torch", tp, 0.0)
	# Corridor low-view: farthest E-W corridor run from the center.
	_depths_low = _find_corridor_view()
	print("[MOCK] depths maze: walls=", walls, " dressed=", dressed,
		" worst under-wall height range=", snappedf(worst_range, 0.01), "m",
		" worst corridor step slope=", snappedf(worst_slope, 0.01))


## Find a horizontal corridor segment (FLOOR with FLOOR east+west, solid
## north+south) far from the arena; return [cam_pos, look_target].
func _find_corridor_view() -> Array:
	var n := _maze_layout.grid_size
	var best := Vector2i(-1, -1)
	var best_d := -1.0
	for cz in n:
		for cx in n:
			if _maze_layout.cell_at(cx, cz) != LevelLayout.FLOOR:
				continue
			if _maze_layout.cell_at(cx + 1, cz) != LevelLayout.FLOOR:
				continue
			if _maze_layout.cell_at(cx - 1, cz) != LevelLayout.FLOOR:
				continue
			if _maze_layout.cell_at(cx, cz - 1) == LevelLayout.FLOOR:
				continue
			if _maze_layout.cell_at(cx, cz + 1) == LevelLayout.FLOOR:
				continue
			var d := Vector2(cx - n / 2, cz - n / 2).length()
			if d > best_d:
				best_d = d
				best = Vector2i(cx, cz)
	if best.x < 0:
		var c := Vector3(0, 0, -6)
		return [Vector3(c.x, _ground(c) + 1.7, c.z), Vector3(0, _ground(Vector3.ZERO) + 1.0, 6)]
	var wp := _maze_layout.cell_to_world(best.x, best.y)
	var east := _maze_layout.cell_to_world(best.x + 2, best.y)
	return [Vector3(wp.x, _ground(wp) + 1.7, wp.z),
		Vector3(east.x, _ground(east) + 1.2, east.z)]


## BFS path over FLOOR cells from the center cell to the farthest dead
## end — the walker's route through the real corridors (depths flavor).
func _maze_path_waypoints() -> Array[Vector3]:
	var n := _maze_layout.grid_size
	var start := Vector2i(n / 2, n / 2)
	var prev := {start: start}
	var queue: Array[Vector2i] = [start]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in dirs:
			var nb := cur + d
			if prev.has(nb) or not _maze_layout.in_bounds(nb.x, nb.y):
				continue
			if _maze_layout.cell_at(nb.x, nb.y) != LevelLayout.FLOOR:
				continue
			prev[nb] = cur
			queue.append(nb)
	# Target: the reachable dead end farthest (BFS depth) from the start.
	var target := start
	var target_d := -1.0
	for de in _maze_layout.maze_dead_ends:
		var c := _maze_layout.world_to_cell(de)
		if not prev.has(c):
			continue
		var wp0 := _maze_layout.cell_to_world(c.x, c.y)
		var dist := wp0.distance_to(_maze_layout.cell_to_world(start.x, start.y))
		if dist > target_d:
			target_d = dist
			target = c
	var cells: Array[Vector2i] = []
	var cur2 := target
	while cur2 != start:
		cells.append(cur2)
		cur2 = prev[cur2]
	cells.append(start)
	cells.reverse()
	var pts: Array[Vector3] = []
	for c in cells:
		pts.append(_maze_layout.cell_to_world(c.x, c.y))
	# Walk out and back so the patrol loops.
	var back := pts.duplicate()
	back.reverse()
	pts.append_array(back)
	return pts


# --- population --------------------------------------------------------------

func _populate(cfg: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg["seed"]) * 17 + 3
	var counts := {"field": 20, "docks": 10, "highlands": 12, "dungeon": 14, "depths": 8}
	var max_slope := 0.55 if flavor != "highlands" else 0.7
	if flavor == "depths":
		# Units hold position in the spawn arena (they have no wall
		# avoidance; the maze corridors are the walker's job below).
		for s in _maze_layout.player_spawns:
			_spawn_unit(Vector3(s.x, 0, s.z), 0.0)
		for off in [Vector3(3, 0, 2), Vector3(-3, 0, -2), Vector3(2, 0, -3), Vector3(-2, 0, 3)]:
			_spawn_unit(off, 0.0)
	else:
		for p in _dry_points(rng, counts[flavor], max_slope):
			_spawn_unit(p, 3.0)
	if flavor == "field":
		# A party cluster standing in the spawn arena.
		for off in [Vector3(1, 0, 1), Vector3(-1.5, 0, 0.5), Vector3(0.5, 0, -1.5), Vector3(-0.5, 0, -0.5)]:
			_spawn_unit(off, 3.0)
	# One walker patrolling: the real maze path (depths), else dry waypoints.
	var w := TerrainWalker.new()
	w.terrain = _terrain
	if flavor == "depths":
		w.waypoints = _maze_path_waypoints()
	else:
		var center := Vector3(0, 0, -10) if flavor == "docks" else Vector3.ZERO
		var r_max := 30.0 if flavor != "highlands" else 14.0
		r_max = minf(r_max, _terrain.half_extent() - 4.0)
		w.waypoints = _dry_points(rng, 4, 0.6, center, r_max)
	var spawn := w.waypoints[0] if not w.waypoints.is_empty() else Vector3.ZERO
	w.position = Vector3(spawn.x, _ground(spawn) + 2.0, spawn.z)
	add_child(w)


func _spawn_unit(p: Vector3, spd: float) -> void:
	var u := TerrainPerfUnit.new()
	u.terrain = _terrain
	u.speed = spd
	u.position = Vector3(p.x, _ground(p), p.z)
	add_child(u)
	_units.append(u)


# --- screenshots -------------------------------------------------------------

func _run_shots(cfg: Dictionary) -> void:
	# CRT shader curves the viewport; disable for clean inspection shots.
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	print("[MOCK] shots start ", flavor)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	# Let the walker settle and the units wander off their spawn points.
	for i in 90:
		await get_tree().physics_frame
		for u in _units:
			u.tick(1.0 / 60.0)
	# View 1: overview.
	_cam.position = cfg.get("ov_pos", Vector3(0, 60, 64))
	_cam.look_at(Vector3(0, 0, 0))
	await _settle(20)
	await _snap("mock_" + flavor + "_overview.png")
	# View 2: low angle, per flavor.
	var low := _low_view()
	_cam.position = low[0]
	_cam.look_at(low[1])
	await _settle(20)
	await _snap("mock_" + flavor + "_low.png")
	print("[MOCK] shots done ", flavor)


func _low_view() -> Array:
	match flavor:
		"field":
			var from := Vector3(-11, 0, 11)
			return [Vector3(from.x, _ground(from) + 2.4, from.z), Vector3(16, _ground(Vector3(16, 0, -14)) + 1.0, -14)]
		"docks":
			var from := Vector3(-8, 0, -6)
			return [Vector3(from.x, _ground(from) + 2.6, from.z), Vector3(10, _terrain.water_level + 0.3, 26)]
		"dungeon":
			# Stand by the dark pool, look across the pillar hall.
			var from := Vector3(10, 0, 18)
			return [Vector3(from.x, _ground(from) + 2.2, from.z), Vector3(-4, _ground(Vector3(-4, 0, -6)) + 1.4, -6)]
		"depths":
			if not _depths_low.is_empty():
				return _depths_low
			var c := Vector3(0, 0, -6)
			return [Vector3(c.x, _ground(c) + 1.7, c.z), Vector3(0, _ground(Vector3.ZERO) + 1.0, 6)]
		_: # highlands: stand at camp, look up the valley at the peaks.
			var from := Vector3(2, 0, 12)
			return [Vector3(from.x, _ground(from) + 2.2, from.z), Vector3(-18, _ground(Vector3(-18, 0, -20)) + 5.0, -20)]


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fails += 1
		printerr("[MOCK] FAIL empty image for ", file_name)
		return
	img.save_png(_shot_dir + "/" + file_name)
	print("[MOCK] saved ", _shot_dir + "/" + file_name)
