extends Node3D
## Issue #103: CLIFF stress test for the experimental heightmap terrain.
## TEST SCENE ONLY — no production code is modified.
##
## The previous terrain proofs were gentle (steepest building seat:
## 0.51m across a ~5m footprint, ~10% grade). This scene pushes the
## terrain steep on purpose — a 10m escarpment whose face peaks near
## 190% grade, over noise with amplitude 7 — and honestly measures
## where the #103 tech holds and where it breaks:
##
##   * UNITS: 100 real RTS units (same stack + driver y-snap as
##     rts_terrain_test.gd) ordered across the face on the real
##     order_move_squad path. Unit movement is manual 2D with y
##     hard-clamped to 0 (unit.gd _apply_movement) — there is NO slope
##     resistance or terrain collision for units, so the questions are
##     behavioral (sticking / bunching) and visual (upright billboard
##     sprites on near-vertical ground).
##   * BUILDINGS: production-mirror spawns (rts_buildings_terrain.gd
##     sequence) at three slope classes — moderate, steep, and a
##     cliff-edge footprint straddling the crest — all min-based.
##   * WALKER: the CharacterBody3D probe (floor_max_angle 50deg, i.e.
##     ~119% grade) walking valley -> plateau straight at the face.
##
## Run modes:
##   probe: headless measurements, prints [CLIFF] report lines
##     godot --headless --path . res://scenes/terrain/cliff_test.tscn -- --mode=probe
##   shots: Xvfb screenshots (INSPECT the PNGs)
##     xvfb-run godot --path . res://scenes/terrain/cliff_test.tscn \
##       --resolution 1920x1080 -- --mode=shots --shot-dir=/tmp/shots
##   (default): interactive top-down view, march auto-starts.

const CIVS := {0: "iron_vanguard", 1: "shadow_covenant"}
const SPACING := 1.4
## Ground-contact footprints (xz) = the collision shapes in building.gd
## (same table as rts_buildings_terrain.gd).
const FOOTPRINTS := {
	"town_hall": Vector2(3.4, 3.4),
	"house": Vector2(2.2, 2.0),
	"barracks": Vector2(4.6, 2.4),
	"tower": Vector2(2.4, 2.4),
}
const PAD := 0.2
const MIN_SPACING := 6.5
const RIDGE_HEIGHT := 10.0
const RIDGE_HALF_WIDTH := 4.0
const MARCH_TARGET := Vector3(26, 0, 0)
const MARCH_MAX_FRAMES := 2700
const ARRIVE_RADIUS := 13.0

var _terrain: CliffTerrain
var _mgr: RTSManager
var _renderer: RTSUnitRenderer
var _cam: RTSCamera
var _armies: Node3D
var _bases_node: Node3D
var _units: Array = []
var _buildings: Array = [] # {node, type, center, mn, mx, grade}
var _placed: Array = []
var _walker: TerrainWalker
var _mode := "run"
var _shot_dir := "/tmp/cliff_test_shots"
var _fails := 0
var _anchor := Vector3(-34, 0, 0)
var _cliff_rec: Dictionary = {}
var _units_snapped := false


func _ready() -> void:
	# Unit snap runs before the renderer's _process (same as companions).
	process_priority = -100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	_setup_env()
	_build_terrain()
	_build_rts_stack()
	_report_slopes()
	_place_buildings()
	_anchor = _find_anchor(_anchor)
	_spawn_army(_anchor)
	_spawn_walker(Vector3(-32, 0, 2), Vector3(26, 0, 2))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match _mode:
		"probe":
			await _run_probe()
			print("[CLIFF] done fails=", _fails)
			get_tree().quit(_fails)
		"shots":
			_cam.set_process(false)
			_cam.set_process_input(false)
			await _run_shots()
			print("[CLIFF] done fails=", _fails)
			get_tree().quit(_fails)
		_:
			_set_view(true)
			_cam.position = Vector3(0, 85, 0.001)
			_cam.rotation = Vector3(-PI / 2, 0, 0)
			_start_march()


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
	_terrain = CliffTerrain.new()
	_terrain.name = "Terrain"
	_terrain.map_points = 97
	_terrain.cell_size = 1.0
	_terrain.terrain_seed = 90210
	_terrain.noise_frequency = 0.05
	_terrain.amplitude = 7.0
	_terrain.water_level = -3.0
	_terrain.smooth_passes = 0 # keep the face sharp — no relax passes
	_terrain.flatten_radius = 8.0
	_terrain.pond_radius = 6.0
	_terrain.pond_depth = 1.8
	_terrain.ridge_height = RIDGE_HEIGHT
	_terrain.ridge_center_x = 0.0
	_terrain.ridge_half_width = RIDGE_HALF_WIDTH
	# One flattened pad on the plateau (control building ground).
	_terrain.poi_points.append(Vector3(30, 0, -22))
	# One carved lake in the valley, south of the crossing lane.
	_terrain.pond_centers.append(Vector3(-30, 0, 28))
	add_child(_terrain)
	_terrain.generate()


## Same bootstrap as the army sandbox / units-on-terrain scene.
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


## Gradient magnitude (rise/run) at a point, finite differences on the
## height array — the same _slope() the companion scenes use.
func _grade(p: Vector3) -> float:
	var e := 0.9
	var dx := _ground(p + Vector3(e, 0, 0)) - _ground(p + Vector3(-e, 0, 0))
	var dz := _ground(p + Vector3(0, 0, e)) - _ground(p + Vector3(0, 0, -e))
	return sqrt(dx * dx + dz * dz) / (2.0 * e)


# --- slope report ---------------------------------------------------------------

func _report_slopes() -> void:
	var h := _terrain.heights_copy()
	var mp := _terrain.map_points
	var cs := _terrain.cell_size
	var total := 0
	var over30 := 0
	var over50 := 0
	var over100 := 0
	var over150 := 0
	var gmax := 0.0
	var gsum := 0.0
	for z in range(1, mp - 1):
		for x in range(1, mp - 1):
			var dx := (h[z * mp + x + 1] - h[z * mp + x - 1]) / (2.0 * cs)
			var dz := (h[(z + 1) * mp + x] - h[(z - 1) * mp + x]) / (2.0 * cs)
			var g := sqrt(dx * dx + dz * dz)
			total += 1
			gsum += g
			gmax = maxf(gmax, g)
			if g > 0.3: over30 += 1
			if g > 0.5: over50 += 1
			if g > 1.0: over100 += 1
			if g > 1.5: over150 += 1
	print("[CLIFF] slope distribution over ", total, " samples:",
		" mean=", snappedf(gsum / float(total), 0.01),
		" max=", snappedf(gmax, 0.01),
		" (", snappedf(gmax * 100.0, 0), "% grade, ",
		snappedf(rad_to_deg(atan(gmax)), 0), " deg)")
	print("[CLIFF]   >30%: ", snappedf(100.0 * over30 / total, 0.1), "%",
		"  >50%: ", snappedf(100.0 * over50 / total, 0.1), "%",
		"  >100%: ", snappedf(100.0 * over100 / total, 0.1), "%",
		"  >150%: ", snappedf(100.0 * over150 / total, 0.1), "%")
	var prof := ""
	for fx in [-10.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 10.0]:
		prof += " x=" + str(int(fx)) + ":" + str(snappedf(_ground(Vector3(fx, 0, 0)), 0.1))
	print("[CLIFF] face profile at z=0:", prof)
	print("[CLIFF] face grade at (0,0): ", snappedf(_grade(Vector3.ZERO), 0.01),
		"  valley water points exist: ", _terrain.is_water(Vector3(-30, 0, 28)))


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


func _spacing_ok(c: Vector3) -> bool:
	for p in _placed:
		var q: Vector3 = p
		if Vector2(c.x - q.x, c.z - q.z).length() < MIN_SPACING:
			return false
	return true


## Find a dry, spacing-legal spot whose footprint height range falls in
## [lo, hi], preferring ranges near `target`. `anchor`/`max_r` confine
## the search (max_r < 0 = whole map); `x_band` >= 0 requires
## |center.x| <= x_band (used to force a crest-straddling placement).
func _find_spot(size: Vector2, lo: float, hi: float, target: float,
		anchor: Vector3, max_r: float, x_band: float) -> Dictionary:
	var best := {}
	var best_score := INF
	var ext := _terrain.half_extent() - 5.0
	var gx := -ext
	while gx <= ext:
		var gz := -ext
		while gz <= ext:
			var c := Vector3(gx, 0, gz)
			if max_r >= 0.0 and Vector2(c.x - anchor.x, c.z - anchor.z).length() > max_r:
				gz += 1.0
				continue
			if x_band >= 0.0 and absf(c.x) > x_band:
				gz += 1.0
				continue
			var st: Dictionary = _footprint_stats(c, size)
			if bool(st["dry"]) and float(st["range"]) >= lo \
					and float(st["range"]) <= hi and _spacing_ok(c):
				var score := absf(float(st["range"]) - target)
				if x_band >= 0.0:
					score += absf(c.x) * 0.05
				if score < best_score:
					best_score = score
					best = {"center": c, "stats": st}
			gz += 1.0
		gx += 1.0
	return best


## The production spawn sequence (dungeon.gd _spawn_building_local via
## rts_buildings_terrain.gd), pos.y = footprint minimum.
func _spawn_building(btype: String, spot: Dictionary, label: String) -> void:
	var center: Vector3 = spot["center"]
	var st: Dictionary = spot["stats"]
	var civ := CivData.for_civ_id(str(CIVS[0]))
	var b := RTSBuilding.new()
	b.setup(0, btype, civ)
	b.building_id = _mgr.alloc_building_id()
	b.name = "RTSBuilding_%d" % b.building_id
	b.rts_manager = _mgr
	b.position = Vector3(center.x, float(st["min"]), center.z)
	_bases_node.add_child(b)
	b.start_construction()
	_placed.append(center)
	var rec := {"node": b, "type": btype, "label": label, "center": center,
		"mn": float(st["min"]), "mx": float(st["max"]),
		"grade": _grade(center)}
	_buildings.append(rec)
	if label == "cliff-edge":
		_cliff_rec = rec
	print("[CLIFF] building ", label, " (", btype, ") at (",
		snappedf(center.x, 0.1), ", ", snappedf(center.z, 0.1), ")",
		" footprint range=", snappedf(float(st["range"]), 0.01), "m",
		" center grade=", snappedf(float(rec["grade"]) * 100.0, 0), "%",
		" placed_y=", snappedf(float(st["min"]), 0.01))


func _place_buildings() -> void:
	# Control: town hall on the flattened plateau POI pad.
	var th := _find_spot(FOOTPRINTS["town_hall"], 0.0, 0.4, 0.15,
		Vector3(30, 0, -22), 10.0, -1.0)
	if th.is_empty():
		_fails += 1
		printerr("[CLIFF] FAIL no town_hall spot")
	else:
		_spawn_building("town_hall", th, "control-flat")
	# Moderate (~20% grade class): house, footprint range 0.7–1.3m.
	var hs := _find_spot(FOOTPRINTS["house"], 0.7, 1.3, 1.0,
		Vector3.ZERO, -1.0, -1.0)
	if hs.is_empty():
		_fails += 1
		printerr("[CLIFF] FAIL no moderate house spot")
	else:
		_spawn_building("house", hs, "moderate")
	# Steep (~45% class): barracks, footprint range 1.8–2.8m.
	var st := _find_spot(FOOTPRINTS["barracks"], 1.8, 2.8, 2.3,
		Vector3.ZERO, -1.0, -1.0)
	if st.is_empty():
		_fails += 1
		printerr("[CLIFF] FAIL no steep barracks spot")
	else:
		_spawn_building("barracks", st, "steep")
	# Cliff-edge: barracks straddling the crest, range >= 3.5m.
	var ce := _find_spot(FOOTPRINTS["barracks"], 3.5, 99.0, 5.0,
		Vector3.ZERO, -1.0, 3.0)
	if ce.is_empty():
		# Honest fallback: take the biggest range in the crest band and
		# report what it actually is.
		ce = _find_spot(FOOTPRINTS["barracks"], 0.0, 99.0, 99.0,
			Vector3.ZERO, -1.0, 3.0)
		if not ce.is_empty():
			print("[CLIFF] NOTE: no crest spot reached 3.5m range;",
				" using max available")
	if ce.is_empty():
		_fails += 1
		printerr("[CLIFF] FAIL no cliff-edge spot")
	else:
		_spawn_building("barracks", ce, "cliff-edge")


# --- units -------------------------------------------------------------------

## Prefer a dry, moderate-slope valley anchor near the preferred point.
func _find_anchor(preferred: Vector3) -> Vector3:
	var best := preferred
	var best_score := -1000.0
	var radii: Array[float] = [0.0, 3.0, 6.0, 9.0]
	for r in radii:
		var steps := 1 if r == 0.0 else 10
		for i in steps:
			var a := TAU * float(i) / float(steps)
			var p := preferred + Vector3(cos(a) * r, 0, sin(a) * r)
			if absf(p.x) > 42.0 or absf(p.z) > 42.0:
				continue
			if _terrain.is_water(p):
				continue
			var s := _grade(p)
			if s > 0.8:
				continue
			var score: float = 6.0 - absf(s - 0.25) * 3.0 - r * 0.15
			if score > best_score:
				best_score = score
				best = p
	return best


func _dry_pos(pos: Vector3, anchor: Vector3) -> Variant:
	var p := pos
	for i in 9:
		if not _terrain.is_water(p):
			return p
		p = p.move_toward(anchor, 1.0)
		p.y = 0.0
	return null if _terrain.is_water(p) else p


func _spawn_one(faction: int, unit_type: String, pos: Vector3) -> void:
	var civ := CivData.for_civ_id(str(CIVS[faction]))
	var u := RTSUnit.new()
	u.setup(faction, unit_type, civ)
	u.unit_id = _mgr.alloc_unit_id()
	u.name = "RTSUnit_%d" % u.unit_id
	u.position = Vector3(pos.x, _ground(pos), pos.z)
	_armies.add_child(u)
	_units.append(u)


## 100 units in the valley: 80 spearmen (8x10) + 20 archers behind.
func _spawn_army(anchor: Vector3) -> void:
	var slots: Array = []
	for row in 8:
		for col in 10:
			slots.append({"type": "spearman", "off": Vector3(
				(float(row) - 3.5) * SPACING, 0,
				(float(col) - 4.5) * SPACING)})
	for row in 2:
		for col in 10:
			slots.append({"type": "archer", "off": Vector3(
				-5.6 - float(row) * SPACING, 0,
				(float(col) - 4.5) * SPACING)})
	var skipped := 0
	for job in slots:
		var pos: Variant = _dry_pos(anchor + (job["off"] as Vector3), anchor)
		if pos == null:
			skipped += 1
			continue
		_spawn_one(0, str(job["type"]), pos as Vector3)
	print("[CLIFF] army spawned: ", _units.size(), " units at anchor ",
		anchor, " skipped_water=", skipped)


func _start_march() -> void:
	var ids: Array = []
	for u in _units:
		ids.append(int(u.get("unit_id")))
	_mgr.order_move_squad(ids, MARCH_TARGET)


func _centroid_x() -> float:
	var sx := 0.0
	var n := 0
	for u in _units:
		if is_instance_valid(u):
			sx += (u as Node3D).global_position.x
			n += 1
	return sx / float(maxi(n, 1))


func _arrived_count() -> int:
	var n := 0
	for u in _units:
		if not is_instance_valid(u):
			continue
		var p := (u as Node3D).global_position
		if Vector2(p.x - MARCH_TARGET.x, p.z - MARCH_TARGET.z).length() < ARRIVE_RADIUS:
			n += 1
	return n


## Run the march, sampling as we go. Returns the stats dictionary.
## `on_face_crossing` (optional Callable) fires once when the squad
## centroid enters the face band — the shots mode uses it to pose the
## mid-crossing screenshot while the march continues.
func _run_march(on_face_crossing := Callable()) -> Dictionary:
	_start_march()
	var max_face_grade := 0.0
	var frames := 0
	var crossed := false
	var series := ""
	while frames < MARCH_MAX_FRAMES:
		await get_tree().physics_frame
		frames += 1
		if frames % 30 == 0:
			for u in _units:
				if not is_instance_valid(u):
					continue
				var p := (u as Node3D).global_position
				if absf(p.x) <= RIDGE_HALF_WIDTH + 1.0:
					max_face_grade = maxf(max_face_grade, _grade(p))
		if frames % 300 == 0:
			series += " f" + str(frames) + ":arr=" + str(_arrived_count()) \
				+ ",cx=" + str(snappedf(_centroid_x(), 0.1))
		if not crossed and _centroid_x() > -3.0:
			crossed = true
			if on_face_crossing.is_valid():
				await on_face_crossing.call()
		if _arrived_count() >= 97:
			break
	# Stall probe: how far do the not-arrived units move in 60 frames?
	var before: Dictionary = {}
	for u in _units:
		if is_instance_valid(u):
			before[u.get_instance_id()] = (u as Node3D).global_position
	for i in 60:
		await get_tree().physics_frame
	# Let the driver's _process snap run before measuring deviations:
	# a sample taken between a physics tick (units clamp y toward 0)
	# and the next snap reads a transient the renderer never shows.
	for i in 2:
		await get_tree().process_frame
	var arrived := 0
	var on_face := 0
	var elsewhere := 0
	var stalled := 0
	var wet := 0
	var max_dev := 0.0
	var max_stand_grade := 0.0
	for u in _units:
		if not is_instance_valid(u):
			continue
		var p := (u as Node3D).global_position
		max_dev = maxf(max_dev, absf(p.y - _ground(p)))
		if _terrain.is_water(p):
			wet += 1
		var d := Vector2(p.x - MARCH_TARGET.x, p.z - MARCH_TARGET.z).length()
		if d < ARRIVE_RADIUS:
			arrived += 1
			max_stand_grade = maxf(max_stand_grade, _grade(p))
		elif absf(p.x) <= RIDGE_HALF_WIDTH + 2.0:
			on_face += 1
		else:
			elsewhere += 1
		if d >= ARRIVE_RADIUS:
			var bp: Vector3 = before.get(u.get_instance_id(), p)
			if Vector2(p.x - bp.x, p.z - bp.z).length() < 0.3:
				stalled += 1
	var stats := {"frames": frames, "arrived": arrived, "on_face": on_face,
		"elsewhere": elsewhere, "stalled": stalled, "wet": wet,
		"max_dev": max_dev, "max_face_grade": max_face_grade,
		"max_stand_grade": max_stand_grade, "series": series}
	print("[CLIFF] march: frames=", frames,
		" (", snappedf(frames / 60.0, 0.1), "s) arrived=", arrived,
		"/", _units.size(), " on_face=", on_face, " elsewhere=", elsewhere,
		" stalled_not_arrived=", stalled, " in_water=", wet)
	print("[CLIFF] march series:", series)
	print("[CLIFF] units: steepest grade occupied in face band=",
		snappedf(max_face_grade * 100.0, 0), "%",
		" steepest grade among arrived units' final spots=",
		snappedf(max_stand_grade * 100.0, 0), "%",
		" max |y-ground| after snap=", snappedf(max_dev, 0.001))
	return stats


# --- walker -------------------------------------------------------------------

func _spawn_walker(spawn: Vector3, target: Vector3) -> void:
	_walker = TerrainWalker.new()
	_walker.terrain = _terrain
	_walker.waypoints = [target]
	_walker.position = Vector3(spawn.x, _ground(spawn) + 1.5, spawn.z)
	add_child(_walker)


## Reset the walker to the valley and let it walk at the face for up to
## max_frames physics frames, watching how far east it gets.
func _run_walker_probe(max_frames: int) -> Dictionary:
	_walker.position = Vector3(-32, _ground(Vector3(-32, 0, 2)) + 1.5, 2)
	_walker.velocity = Vector3.ZERO
	_walker.waypoints = [Vector3(26, 0, 2)]
	_walker.distance_walked = 0.0
	_walker.max_deviation = 0.0
	var max_x := -32.0
	var since_improve := 0
	var on_floor := 0
	var frames := 0
	while frames < max_frames:
		await get_tree().physics_frame
		frames += 1
		var p := _walker.global_position
		if _walker.is_on_floor():
			on_floor += 1
		if p.x > max_x + 0.05:
			max_x = p.x
			since_improve = 0
		else:
			since_improve += 1
		if p.x > 8.0:
			break # crossed the crest band — it climbed
		if since_improve > 600 and frames > 700:
			break # stalled
	var p := _walker.global_position
	var stats := {"frames": frames, "max_x": max_x, "final": p,
		"distance": _walker.distance_walked,
		"on_floor_pct": 100.0 * on_floor / float(maxi(frames, 1)),
		"max_dev": _walker.max_deviation, "grade_at_stop": _grade(p)}
	print("[CLIFF] walker: frames=", frames, " max_x=", snappedf(max_x, 0.1),
		" final=(", snappedf(p.x, 0.1), ", ", snappedf(p.z, 0.1), ")",
		" distance=", snappedf(_walker.distance_walked, 0.1), "m",
		" on_floor=", snappedf(stats["on_floor_pct"], 0), "%",
		" grade_at_stop=", snappedf(float(stats["grade_at_stop"]) * 100.0, 0), "%",
		" max_dev_from_array=", snappedf(_walker.max_deviation, 0.01))
	return stats


# --- modes -------------------------------------------------------------------

func _run_probe() -> void:
	for i in 30:
		await get_tree().physics_frame
	await _run_march()
	await _run_walker_probe(1800)
	_report_buildings()


func _report_buildings() -> void:
	for rec in _buildings:
		var b: RTSBuilding = rec["node"]
		print("[CLIFF] building final ", str(rec["label"]), " (",
			str(rec["type"]), ") range=",
			snappedf(float(rec["mx"]) - float(rec["mn"]), 0.01), "m",
			" buried_depth_uphill=", snappedf(float(rec["mx"]) - float(rec["mn"]), 0.01), "m",
			" node_y=", snappedf(b.position.y, 0.01),
			" == footprint_min: ", absf(b.position.y - float(rec["mn"])) < 0.01)


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
	print("[CLIFF] shots start units=", _units.size(),
		" buildings=", _buildings.size())
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	for i in 30:
		await get_tree().physics_frame
	# Complete all construction so buildings read fully in the shots.
	for rec in _buildings:
		(rec["node"] as RTSBuilding).add_build_work(1000.0)
	for i in 10:
		await get_tree().process_frame
	# Reposition the walker to the cliff base for the low shot; it will
	# press against the face while the march runs.
	_walker.position = Vector3(-8, _ground(Vector3(-8, 0, -5)) + 1.5, -5)
	_walker.velocity = Vector3.ZERO
	_walker.waypoints = [Vector3(26, 0, -5)]
	# View 1: overview — from due west so the escarpment face reads
	# frontally: valley in the foreground, plateau behind it.
	_set_view(true)
	_pose(Vector3(-50, 25, 14), Vector3(8, 3, -2))
	await _settle(15)
	await _snap("cliff_overview.png")
	# March + mid-crossing shot from the south, face in profile.
	_set_view(false)
	var face_mid := _ground(Vector3(0, 0, 0))
	var shot_taken := {"done": false}
	var on_cross := func() -> void:
		var cp := Vector3(1.0, 0, 17)
		_pose(Vector3(cp.x, _ground(cp) + 3.2, cp.z),
			Vector3(-1, face_mid + 1.0, -6))
		await _settle(6)
		await _snap("cliff_units.png")
		shot_taken["done"] = true
	await _run_march(on_cross)
	if not bool(shot_taken["done"]):
		# Centroid never reached the face (would itself be a finding);
		# take the units shot from the same pose anyway.
		var cp := Vector3(1.0, 0, 17)
		_pose(Vector3(cp.x, _ground(cp) + 3.2, cp.z),
			Vector3(-1, face_mid + 1.0, -6))
		await _settle(6)
		await _snap("cliff_units.png")
	_report_buildings()
	# View 3: cliff-edge building from downhill (west). Camera height
	# must clear the terrain AT THE CAMERA — the footprint minimum is
	# the valley-side low point, and the ground west of the crest can
	# still be above it (an earlier framing shot from inside the hill).
	if not _cliff_rec.is_empty():
		var c: Vector3 = _cliff_rec["center"]
		var mn := float(_cliff_rec["mn"])
		var cp2 := c + Vector3(-9.0, 0, 4.5)
		var cam_y := maxf(_ground(cp2) + 1.7, mn + 2.4)
		_pose(Vector3(cp2.x, cam_y, cp2.z),
			Vector3(c.x, mn + 1.3, c.z))
		await _settle(12)
		await _snap("cliff_building.png")
	# View 4: the stalled walker in PROFILE against the face — camera
	# south of it at its own height, looking north, so the slope runs
	# low (west) to high (east) across the frame and the capsule's
	# contact with the steep ground can be judged.
	var wp := _walker.global_position
	var lp := Vector3(wp.x - 1.0, 0, wp.z + 10.0)
	var cam_y := maxf(_ground(lp) + 1.2, wp.y + 0.3)
	_pose(Vector3(lp.x, cam_y, lp.z),
		Vector3(wp.x + 1.0, wp.y + 0.8, wp.z - 2.0))
	await _settle(12)
	await _snap("cliff_low.png")
	print("[CLIFF] shots done")


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fails += 1
		printerr("[CLIFF] FAIL empty image for ", file_name)
		return
	img.save_png(_shot_dir + "/" + file_name)
	print("[CLIFF] saved ", _shot_dir + "/" + file_name)
