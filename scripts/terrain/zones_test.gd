extends Node3D
## Issue #103: ELEVATED-ZONES terrain mock (Jesse's design proposal).
## TEST SCENE ONLY — no production code is modified.
##
## Instead of rolling noise hills: the terrain stays relatively FLAT
## and the height lives in discrete plateau zones — a mid tier at +3m
## and a peak tier at +6m stamped onto the heightmap as irregular
## blobs. The flats carry real surface roughness (Jesse's follow-up:
## the first pass read too smooth/machined): a ±0.3m low-frequency
## base plus a ±0.45m higher-frequency texture noise, damped inside
## the ramps and the plateau edge bands (ZonesTerrain._rough_scale).
## Steepness concentrates at the plateau edges
## (2.5m terrace bands peaking ~180% grade — over the 119% physics
## floor limit, so walkers CANNOT climb them) and at two carved ramps
## (the only way up, smoothstep channels capped near 45% grade).
##
## Proofs (probe mode, [ZONES] lines):
##   * tier flatness: interior samples vs tier height (max dev/stddev)
##   * edge block: physics walker driven at the mid plateau's west
##     edge stalls; the same walker climbs ramp 1 to the mid top
##   * ramp grades: max grade along both ramp centrelines
##   * buildings: one per tier via the production-mirror spawn +
##     min-basing (footprint ranges should be far under the 1.2m cap
##     the cliff test derived)
##   * units: 60 real RTS units ordered lowland -> ramp 1 -> mid ->
##     ramp 2 -> peak on the real order_move_squad path (waypoint
##     legs managed by this driver)
##
## Run modes:
##   probe: headless measurements
##     godot --headless --path . res://scenes/terrain/zones_test.tscn -- --mode=probe
##   shots: Xvfb screenshots (INSPECT the PNGs)
##     xvfb-run godot --path . res://scenes/terrain/zones_test.tscn \
##       --resolution 1920x1080 -- --mode=shots --shot-dir=/tmp/shots
##   (default): interactive top-down view, march auto-starts.

const CIVS := {0: "iron_vanguard", 1: "shadow_covenant"}
const SPACING := 1.4
const FOOTPRINTS := {
	"town_hall": Vector2(3.4, 3.4),
	"house": Vector2(2.2, 2.0),
	"barracks": Vector2(4.6, 2.4),
	"tower": Vector2(2.4, 2.4),
}
const PAD := 0.2
const MID_CENTER := Vector2(-10, -4)
const PEAK_CENTER := Vector2(2, -8)
const RAMP1_BASE := Vector2(-10, 19)
const RAMP2_BASE := Vector2(-11, -8)
const GATHER := Vector3(5, 0, -8)
const LEGS: Array[Vector3] = [
	Vector3(-10, 0, 12), Vector3(-10.5, 0, -6),
	Vector3(-1, 0, -8), GATHER,
]

var _terrain: ZonesTerrain
var _mgr: RTSManager
var _renderer: RTSUnitRenderer
var _cam: RTSCamera
var _armies: Node3D
var _bases_node: Node3D
var _units: Array = []
var _buildings: Array = []
var _walker: TerrainWalker
var _mode := "run"
var _shot_dir := "/tmp/zones_shots"
var _fails := 0


func _ready() -> void:
	process_priority = -100 # unit snap before the renderer (companions)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	_setup_env()
	_build_terrain()
	_build_rts_stack()
	_place_buildings()
	_dress()
	_spawn_army()
	_spawn_walker(Vector3(-36, 0, -4))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match _mode:
		"probe":
			await _run_probe()
			print("[ZONES] done fails=", _fails)
			get_tree().quit(_fails)
		"shots":
			_cam.set_process(false)
			_cam.set_process_input(false)
			await _run_shots()
			print("[ZONES] done fails=", _fails)
			get_tree().quit(_fails)
		_:
			_set_view(true)
			_cam.position = Vector3(0, 85, 0.001)
			_cam.rotation = Vector3(-PI / 2, 0, 0)
			_walker.waypoints = [Vector3(-10, 0, -4)]
			_run_march()


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


func _build_terrain() -> void:
	_terrain = ZonesTerrain.new()
	_terrain.name = "Terrain"
	_terrain.map_points = 97
	_terrain.cell_size = 1.0
	_terrain.terrain_seed = 4242
	_terrain.noise_frequency = 0.045
	_terrain.amplitude = 0.6 # ±0.3m low-freq base; +±0.45m rough texture on top (ZonesTerrain)
	_terrain.water_level = -0.45 # below the noise floor: pond-only water
	_terrain.smooth_passes = 1
	_terrain.pond_radius = 6.0
	_terrain.pond_depth = 1.7
	# Mid tier +3m (phases tuned so the outline radius at the ramp 1
	# crossing, due south, is the nominal 18m) and peak tier +6m
	# nested against its east side (radius exact due east for ramp 2).
	_terrain.zones = [
		{"center": MID_CENTER, "radius": 18.0, "height": 3.0,
			"phase1": -4.712, "phase2": -1.571},
		{"center": PEAK_CENTER, "radius": 11.0, "height": 6.0,
			"phase1": 0.0, "phase2": 0.0},
	]
	_terrain.ramps = [
		{"base": RAMP1_BASE, "dir": Vector2(0, -1), "length": 10.0,
			"width": 5.0, "h0": 0.0, "h1": 3.0},
		{"base": RAMP2_BASE, "dir": Vector2(1, 0), "length": 10.0,
			"width": 5.0, "h0": 3.0, "h1": 6.0},
	]
	_terrain.pond_centers.append(Vector3(28, 0, 24))
	add_child(_terrain)
	_terrain.generate()


func _build_rts_stack() -> void:
	_mgr = RTSManager.new()
	_mgr.name = "RTSManager"
	add_child(_mgr)
	_bases_node = Node3D.new()
	_bases_node.name = "Bases"
	add_child(_bases_node)
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


func _ground(p: Vector3) -> float:
	return _terrain.get_ground_height(p)


func _grade(p: Vector3) -> float:
	var e := 0.9
	var dx := _ground(p + Vector3(e, 0, 0)) - _ground(p + Vector3(-e, 0, 0))
	var dz := _ground(p + Vector3(0, 0, e)) - _ground(p + Vector3(0, 0, -e))
	return sqrt(dx * dx + dz * dz) / (2.0 * e)


# --- measurements --------------------------------------------------------------

## Interior flatness of one tier: grid samples well inside the flat
## (optionally excluding a second zone's footprint and ramp channels).
func _tier_stats(center: Vector2, radius: float, tier: float,
		excl_center: Vector2, excl_radius: float) -> Dictionary:
	var n := 0
	var mean := 0.0
	var vals: Array[float] = []
	var step := 1.5
	var gx := center.x - radius
	while gx <= center.x + radius:
		var gz := center.y - radius
		while gz <= center.y + radius:
			var d := Vector2(gx - center.x, gz - center.y).length()
			if d <= radius:
				var p := Vector3(gx, 0, gz)
				var near_ramp := false
				for rp in _terrain.ramps:
					var b: Vector2 = rp["base"]
					var dir: Vector2 = rp["dir"]
					var rel := Vector2(gx - b.x, gz - b.y)
					var s := rel.dot(dir)
					var lat := rel.dot(Vector2(-dir.y, dir.x))
					if s > -2.0 and s < float(rp["length"]) + 2.0 \
							and absf(lat) < 4.5:
						near_ramp = true
				var excluded := excl_radius > 0.0 and \
					Vector2(gx - excl_center.x, gz - excl_center.y).length() < excl_radius
				if not near_ramp and not excluded:
					var h := _ground(p)
					vals.append(h)
					mean += h
					n += 1
			gz += step
		gx += step
	mean /= float(maxi(n, 1))
	var var_sum := 0.0
	var max_dev := 0.0
	for h in vals:
		var_sum += (h - mean) * (h - mean)
		max_dev = maxf(max_dev, absf(h - tier))
	return {"n": n, "mean": mean, "stddev": sqrt(var_sum / float(maxi(n, 1))),
		"max_dev": max_dev}


func _report_tiers() -> void:
	var low := _tier_stats(Vector2(30, 6), 13.0, 0.0, Vector2(28, 24), 10.0)
	print("[ZONES] lowland flatness: n=", low["n"],
		" mean=", snappedf(float(low["mean"]), 0.01),
		" stddev=", snappedf(float(low["stddev"]), 0.01),
		" max_dev_from_0=", snappedf(float(low["max_dev"]), 0.01))
	var mid := _tier_stats(MID_CENTER, 11.0, 3.0, PEAK_CENTER, 13.5)
	print("[ZONES] mid tier flatness: n=", mid["n"],
		" mean=", snappedf(float(mid["mean"]), 0.01),
		" stddev=", snappedf(float(mid["stddev"]), 0.01),
		" max_dev_from_3=", snappedf(float(mid["max_dev"]), 0.01))
	var peak := _tier_stats(PEAK_CENTER, 6.5, 6.0, Vector2.ZERO, 0.0)
	print("[ZONES] peak tier flatness: n=", peak["n"],
		" mean=", snappedf(float(peak["mean"]), 0.01),
		" stddev=", snappedf(float(peak["stddev"]), 0.01),
		" max_dev_from_6=", snappedf(float(peak["max_dev"]), 0.01))
	for st in [low, mid, peak]:
		if float(st["max_dev"]) > 0.9:
			_fails += 1
			printerr("[ZONES] FAIL tier max_dev ", st["max_dev"], " > 0.9 (roughness bound)")


func _report_grades() -> void:
	# Edge transect: due west across the mid edge at z = -4 (no ramp).
	var edge_max := 0.0
	var fx := -36.0
	while fx <= -18.0:
		edge_max = maxf(edge_max, _grade(Vector3(fx, 0, -4)))
		fx += 0.25
	print("[ZONES] mid west edge max grade=",
		snappedf(edge_max * 100.0, 0), "% (physics limit 119%)")
	if edge_max < 1.19:
		_fails += 1
		printerr("[ZONES] FAIL edge grade below physics limit — walkers could climb it")
	# Ramp centrelines.
	for ri in 2:
		var rp: Dictionary = _terrain.ramps[ri]
		var b: Vector2 = rp["base"]
		var dir: Vector2 = rp["dir"]
		var gmax := 0.0
		var s := -1.0
		while s <= float(rp["length"]) + 1.0:
			var p := b + dir * s
			var ahead := b + dir * (s + 0.5)
			var behind := b + dir * (s - 0.5)
			var g := absf(_ground(Vector3(ahead.x, 0, ahead.y))
				- _ground(Vector3(behind.x, 0, behind.y)))
			gmax = maxf(gmax, g)
			s += 0.5
		print("[ZONES] ramp ", ri + 1, " centreline max grade=",
			snappedf(gmax * 100.0, 0), "% (design cap ~50%)")
		if gmax > 0.7:
			_fails += 1
			printerr("[ZONES] FAIL ramp grade ", gmax, " over cap")


# --- buildings -------------------------------------------------------------------

func _footprint_stats(center: Vector3, size: Vector2) -> Dictionary:
	var hx := size.x * 0.5 + PAD
	var hz := size.y * 0.5 + PAD
	var step := 0.4
	var nx := maxi(2, int(ceil(hx * 2.0 / step)))
	var nz := maxi(2, int(ceil(hz * 2.0 / step)))
	var mn := INF
	var mx := -INF
	for iz in nz + 1:
		for ix in nx + 1:
			var p := Vector3(
				center.x - hx + hx * 2.0 * float(ix) / float(nx), 0,
				center.z - hz + hz * 2.0 * float(iz) / float(nz))
			var hh := _terrain.get_ground_height(p)
			mn = minf(mn, hh)
			mx = maxf(mx, hh)
	return {"min": mn, "max": mx, "range": mx - mn,
		"dry": mn >= _terrain.water_level + 0.02}


## Production-mirror spawn (dungeon.gd via rts_buildings_terrain.gd),
## pos.y = footprint minimum. One building per tier.
func _spawn_building(btype: String, center: Vector3, label: String) -> void:
	var st := _footprint_stats(center, FOOTPRINTS[btype])
	var civ := CivData.for_civ_id(str(CIVS[0]))
	var b := RTSBuilding.new()
	b.setup(0, btype, civ)
	b.building_id = _mgr.alloc_building_id()
	b.name = "RTSBuilding_%d" % b.building_id
	b.rts_manager = _mgr
	b.position = Vector3(center.x, float(st["min"]), center.z)
	_bases_node.add_child(b)
	b.start_construction()
	_buildings.append({"node": b, "type": btype, "label": label,
		"center": center, "range": float(st["range"])})
	print("[ZONES] building ", label, " (", btype, ") at (",
		center.x, ", ", center.z, ") footprint range=",
		snappedf(float(st["range"]), 0.01), "m placed_y=",
		snappedf(float(st["min"]), 0.01), " dry=", bool(st["dry"]))
	if float(st["range"]) > 1.2:
		_fails += 1
		printerr("[ZONES] FAIL building footprint range over the 1.2m cap")
	if not bool(st["dry"]):
		_fails += 1
		printerr("[ZONES] FAIL building in water")


func _place_buildings() -> void:
	_spawn_building("town_hall", Vector3(26, 0, 6), "lowland")
	_spawn_building("house", Vector3(-17, 0, 1), "mid")
	_spawn_building("barracks", Vector3(4, 0, -13), "peak")


# --- dressing (light) ------------------------------------------------------------

func _place_prop(type: String, p: Vector3, rot_y: float, sink: float = 0.0) -> void:
	var prop := PropBuilder.build(type, 1.0, {"pos": p})
	prop.position = Vector3(p.x, _ground(p) - sink, p.z)
	prop.rotation.y = rot_y
	add_child(prop)


func _dress() -> void:
	var trees: Array[Vector2] = [
		Vector2(-24, 12), Vector2(-30, -16), Vector2(3, 27),
		Vector2(8, 18), Vector2(20, -2), Vector2(34, 6),
		Vector2(38, -18), Vector2(-38, 8), Vector2(-20, -14),
		Vector2(-6, -16), Vector2(6, -16), Vector2(0, 2),
		Vector2(24, 34), Vector2(-26, 30), Vector2(40, 16),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in trees.size():
		_place_prop("tree", Vector3(trees[i].x, 0, trees[i].y),
			rng.randf() * TAU)
	var rocks: Array[Vector2] = [
		Vector2(-30, 0), Vector2(15.5, -8), Vector2(-16, 15),
		Vector2(10, -20), Vector2(-29, -10), Vector2(14, -14),
	]
	for i in rocks.size():
		_place_prop("rock", Vector3(rocks[i].x, 0, rocks[i].y),
			rng.randf() * TAU, 0.15)


# --- units -------------------------------------------------------------------

func _spawn_one(faction: int, unit_type: String, pos: Vector3) -> void:
	var civ := CivData.for_civ_id(str(CIVS[faction]))
	var u := RTSUnit.new()
	u.setup(faction, unit_type, civ)
	u.unit_id = _mgr.alloc_unit_id()
	u.name = "RTSUnit_%d" % u.unit_id
	u.position = Vector3(pos.x, _ground(pos), pos.z)
	_armies.add_child(u)
	_units.append(u)


## 60 units staged on the lowland due south of ramp 1: a 5-wide
## column (40 spearmen + 20 archers) that fits the ramp channel.
func _spawn_army() -> void:
	var anchor := Vector3(-10, 0, 29)
	for row in 12:
		for col in 5:
			var utype := "spearman" if row < 8 else "archer"
			_spawn_one(0, utype, anchor + Vector3(
				(float(col) - 2.0) * SPACING, 0, float(row) * SPACING))
	print("[ZONES] army spawned: ", _units.size(), " units")


func _centroid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in _units:
		if is_instance_valid(u):
			c += (u as Node3D).global_position
			n += 1
	return c / float(maxi(n, 1)) if n > 0 else Vector3.ZERO


## March the squad through the waypoint legs. `on_ramp` fires once
## when the centroid enters ramp 1 (shots mode poses the ascent).
func _run_march(on_ramp := Callable()) -> Dictionary:
	var ramp_fired := false
	var total_frames := 0
	for li in LEGS.size():
		var tgt: Vector3 = LEGS[li]
		var ids: Array = []
		for u in _units:
			ids.append(int(u.get("unit_id")))
		_mgr.order_move_squad(ids, tgt)
		var frames := 0
		var best := INF
		var since_improve := 0
		while frames < 1500:
			await get_tree().physics_frame
			frames += 1
			total_frames += 1
			var c := _centroid()
			var d := Vector2(c.x - tgt.x, c.z - tgt.z).length()
			if d < best - 0.2:
				best = d
				since_improve = 0
			else:
				since_improve += 1
			if not ramp_fired and li == 0 and c.z < 17.5:
				ramp_fired = true
				if on_ramp.is_valid():
					await on_ramp.call()
			if d < 2.5 or since_improve > 300:
				break
		print("[ZONES] march leg ", li + 1, " -> (", tgt.x, ", ", tgt.z,
			") frames=", frames, " centroid_dist=",
			snappedf(best if best != INF else -1.0, 0.1))
	for i in 2:
		await get_tree().process_frame
	var arrived := 0
	var on_steep := 0
	var wet := 0
	var max_dev := 0.0
	for u in _units:
		if not is_instance_valid(u):
			continue
		var p := (u as Node3D).global_position
		max_dev = maxf(max_dev, absf(p.y - _ground(p)))
		if _terrain.is_water(p):
			wet += 1
		if Vector2(p.x - GATHER.x, p.z - GATHER.z).length() < 7.0:
			arrived += 1
		elif _grade(p) > 1.0:
			on_steep += 1
	var stats := {"frames": total_frames, "arrived": arrived,
		"on_steep": on_steep, "wet": wet, "max_dev": max_dev}
	print("[ZONES] march done: frames=", total_frames,
		" arrived_at_peak=", arrived, "/", _units.size(),
		" left_on_steep=", on_steep, " in_water=", wet,
		" max |y-ground|=", snappedf(max_dev, 0.001))
	if arrived < 55:
		_fails += 1
		printerr("[ZONES] FAIL only ", arrived, " units reached the peak")
	if on_steep > 3:
		_fails += 1
		printerr("[ZONES] FAIL ", on_steep, " units left hanging on steep ground")
	return stats


# --- walker -------------------------------------------------------------------

func _spawn_walker(spawn: Vector3) -> void:
	_walker = TerrainWalker.new()
	_walker.terrain = _terrain
	_walker.position = Vector3(spawn.x, _ground(spawn) + 1.5, spawn.z)
	add_child(_walker)


func _reset_walker(spawn: Vector3, target: Vector3) -> void:
	_walker.position = Vector3(spawn.x, _ground(spawn) + 1.5, spawn.z)
	_walker.velocity = Vector3.ZERO
	_walker.waypoints = [target]
	_walker.distance_walked = 0.0
	_walker.max_deviation = 0.0


## Let the walker walk for up to max_frames, tracking progress along
## +x (edge run) or -z (ramp run) via `progress` Callable.
func _walk_until(progress: Callable, goal: float, max_frames: int) -> Dictionary:
	var best := -INF
	var since := 0
	var frames := 0
	while frames < max_frames:
		await get_tree().physics_frame
		frames += 1
		var v := float(progress.call(_walker.global_position))
		if v > best + 0.05:
			best = v
			since = 0
		else:
			since += 1
		if best >= goal:
			break
		if since > 300 and frames > 400:
			break
	var p := _walker.global_position
	return {"frames": frames, "best": best, "final": p,
		"height": p.y, "grade": _grade(p),
		"distance": _walker.distance_walked}


func _run_walker_proofs() -> void:
	# Edge block: from the lowland due west, straight at the mid top.
	_reset_walker(Vector3(-36, 0, -4), Vector3(-10, 0, -4))
	var edge := await _walk_until(
		func(p: Vector3) -> float: return p.x, -20.0, 1500)
	print("[ZONES] walker vs edge: frames=", edge["frames"],
		" max_x=", snappedf(float(edge["best"]), 0.1),
		" stopped_at=(", snappedf((edge["final"] as Vector3).x, 0.1),
		", ", snappedf((edge["final"] as Vector3).z, 0.1), ")",
		" height=", snappedf(float(edge["height"]), 0.01),
		" grade_at_stop=", snappedf(float(edge["grade"]) * 100.0, 0), "%",
		" distance=", snappedf(float(edge["distance"]), 0.1), "m")
	if float(edge["height"]) > 1.5:
		_fails += 1
		printerr("[ZONES] FAIL walker climbed the plateau edge")
	# Ramp climb: from ramp 1's base straight up to the mid top.
	_reset_walker(Vector3(-10, 0, 23.5), Vector3(-10, 0, 0))
	var ramp := await _walk_until(
		func(p: Vector3) -> float: return -p.z, 0.0, 1500)
	print("[ZONES] walker up ramp 1: frames=", ramp["frames"],
		" min_z=", snappedf(-float(ramp["best"]), 0.1),
		" final_height=", snappedf(float(ramp["height"]), 0.01),
		" (mid tier = 3.0) distance=",
		snappedf(float(ramp["distance"]), 0.1), "m")
	if float(ramp["height"]) < 2.4 or (ramp["final"] as Vector3).z > 6.0:
		_fails += 1
		printerr("[ZONES] FAIL walker did not climb ramp 1 to the mid tier")


# --- modes -------------------------------------------------------------------

func _run_probe() -> void:
	for i in 30:
		await get_tree().physics_frame
	_report_tiers()
	_report_grades()
	await _run_walker_proofs()
	await _run_march()
	for rec in _buildings:
		var b: RTSBuilding = rec["node"]
		print("[ZONES] building final ", str(rec["label"]),
			" range=", snappedf(float(rec["range"]), 0.01), "m",
			" node_y==footprint_min: ",
			absf(b.position.y - _footprint_stats(rec["center"],
				FOOTPRINTS[str(rec["type"])])["min"]) < 0.01)


func _set_view(command: bool) -> void:
	_cam.active = command
	_cam.current = true
	get_tree().call_group("rts_units", "_on_command_view_toggled", command)


func _pose(pos: Vector3, target: Vector3) -> void:
	_cam.position = pos
	_cam.look_at(target)


func _run_shots() -> void:
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	print("[ZONES] shots start units=", _units.size(),
		" buildings=", _buildings.size())
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	for i in 30:
		await get_tree().physics_frame
	for rec in _buildings:
		(rec["node"] as RTSBuilding).add_build_work(1000.0)
	for i in 10:
		await get_tree().process_frame
	# Walker presses against the west edge for the edge shot.
	_walker.waypoints = [Vector3(-10, 0, -4)]
	# View 1: overview — high SE angle: tiers, ramps, pond all read.
	_set_view(true)
	_pose(Vector3(40, 40, 46), Vector3(-2, 1, -4))
	await _settle(15)
	await _snap("zones_overview.png")
	# March; mid-ascent shot on ramp 1 from its SE shoulder.
	_set_view(false)
	var ramp_shot := {"done": false}
	var on_ramp := func() -> void:
		_pose(Vector3(-2.5, _ground(Vector3(-2.5, 0, 24.5)) + 2.4, 24.5),
			Vector3(-10.5, 2.2, 11))
		await _settle(6)
		await _snap("zones_ramp.png")
		ramp_shot["done"] = true
	await _run_march(on_ramp)
	if not bool(ramp_shot["done"]):
		_pose(Vector3(-2.5, _ground(Vector3(-2.5, 0, 24.5)) + 2.4, 24.5),
			Vector3(-10.5, 2.2, 11))
		await _settle(6)
		await _snap("zones_ramp.png")
	# View 3: on the peak, looking west across mid + lowland.
	_pose(Vector3(11.5, _ground(Vector3(11.5, 0, -1.5)) + 2.4, -1.5),
		Vector3(1, 4.4, -9))
	await _settle(12)
	await _snap("zones_top.png")
	# View 4: the west edge as a terrace wall, walker stalled at base.
	var wp := _walker.global_position
	var ep := Vector3(-35, 0, 3.5)
	_pose(Vector3(ep.x, _ground(ep) + 1.9, ep.z),
		Vector3(maxf(wp.x, -28.0), 1.6, -4))
	await _settle(12)
	await _snap("zones_edge.png")
	print("[ZONES] shots done")


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fails += 1
		printerr("[ZONES] FAIL empty image for ", file_name)
		return
	img.save_png(_shot_dir + "/" + file_name)
	print("[ZONES] saved ", _shot_dir + "/" + file_name)
