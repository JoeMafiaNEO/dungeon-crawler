extends Node3D
## Issue #103: the REAL RTS buildings on the experimental heightmap
## terrain. TEST SCENE ONLY — no production code is modified.
##
## Production places buildings from a y=0 mouse-ray plane and sets
## `b.position = pos` verbatim (dungeon.gd _spawn_building_local), so on
## real terrain a building would float or sink. This driver mirrors the
## production spawn sequence exactly (RTSBuilding.new() -> setup ->
## alloc_building_id -> named node -> rts_manager -> position ->
## add_child -> start_construction) but computes pos.y from the terrain:
## the MINIMUM get_ground_height() sampled over the building's footprint
## — the same basing trick the depths-maze mock proved for its 2m walls
## (scripts/terrain/mock_level.gd). The low side sits flush, the high
## side is buried, no corner ever floats. Spots are rejected when any
## footprint sample is wet (stricter than production's center-only
## _is_valid_build_spot) or when spacing to a placed building is < 6.5m
## (production: 5m).
##
## Each faction gets town_hall + house + barracks + tower. Red's
## barracks is DELIBERATELY placed on a slope (footprint height range
## 0.5–1.25m) — the case that proves footprint seating. One red house is
## left under construction so the dimmed construction state is visible
## in the shots; every other building is completed via add_build_work.
##
## Run modes:
##   shots: Xvfb screenshots (top-down / low / slope close-up)
##     xvfb-run godot --path . res://scenes/terrain/rts_buildings_terrain.tscn \
##       --resolution 1920x1080 -- --mode=shots --shot-dir=/tmp/shots
##   (default): interactive top-down view.

const CIVS := {0: "iron_vanguard", 1: "shadow_covenant"}
## Ground-contact footprints (xz) = the collision shapes in building.gd.
const FOOTPRINTS := {
	"town_hall": Vector2(3.4, 3.4),
	"house": Vector2(2.2, 2.0),
	"barracks": Vector2(4.6, 2.4),
	"tower": Vector2(2.4, 2.4),
}
const PAD := 0.2 ## footprint sampling margin past the collision box
const MIN_SPACING := 6.5
const SEARCH_R := 16

var _terrain: HeightmapTerrain
var _mgr: RTSManager
var _renderer: RTSUnitRenderer
var _cam: RTSCamera
var _bases_node: Node3D
var _armies: Node3D
var _units: Array = []
var _buildings: Array = [] # {node, faction, type, center, mn, mx}
var _placed: Array = [] # Array[Vector3] building centers, both factions
var _mode := "run"
var _shot_dir := "/tmp/rts_buildings_shots"
var _fails := 0
var _slope_node: RTSBuilding = null
var _slope_center := Vector3.ZERO
var _red_th_center := Vector3.ZERO
var _unfinished: RTSBuilding = null


func _ready() -> void:
	# Unit snap runs before the renderer's _process (same as units scene).
	process_priority = -100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	_setup_env()
	_build_terrain()
	_build_rts_stack()
	_place_base(0, Vector3(-20, 0, 6), true)
	_place_base(1, Vector3(21, 0, -4), false)
	_spawn_units()
	_dress_light()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _mode == "shots":
		_cam.set_process(false)
		_cam.set_process_input(false)
		await _run_shots()
		print("[RTSB] done fails=", _fails)
		get_tree().quit(_fails)
	else:
		_set_view(true)
		_cam.position = Vector3(0, 78, 0.001)
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


## Same mock-field parameters as the units-on-terrain scene.
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


func _slope(p: Vector3) -> float:
	var e := 0.9
	var dx := _ground(p + Vector3(e, 0, 0)) - _ground(p + Vector3(-e, 0, 0))
	var dz := _ground(p + Vector3(0, 0, e)) - _ground(p + Vector3(0, 0, -e))
	return sqrt(dx * dx + dz * dz) / (2.0 * e)


# --- placement -----------------------------------------------------------------

## Sample the heightmap over a building footprint: min / max / range and
## whether every sample is dry land.
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
			var h := _terrain.get_ground_height(p)
			mn = minf(mn, h)
			mx = maxf(mx, h)
	return {"min": mn, "max": mx, "range": mx - mn,
		"dry": mn >= _terrain.water_level + 0.02}


func _spacing_ok(c: Vector3) -> bool:
	for p in _placed:
		var q: Vector3 = p
		if Vector2(c.x - q.x, c.z - q.z).length() < MIN_SPACING:
			return false
	return true


## Find a dry, spacing-legal spot near `anchor` whose footprint height
## range falls in [lo, hi], preferring ranges near `target` and spots
## near the anchor. Falls back to any dry spot with range <= 1.6.
func _find_spot(anchor: Vector3, size: Vector2, lo: float, hi: float,
		target: float) -> Dictionary:
	var offsets: Array = []
	for dz in range(-SEARCH_R, SEARCH_R + 1):
		for dx in range(-SEARCH_R, SEARCH_R + 1):
			offsets.append(Vector2(dx, dz))
	offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.length() < b.length())
	for pass_no in 2:
		var band_lo := lo if pass_no == 0 else 0.0
		var band_hi := hi if pass_no == 0 else 1.6
		var best := {}
		var best_score := INF
		for off in offsets:
			var o: Vector2 = off
			var c := anchor + Vector3(o.x, 0, o.y)
			if absf(c.x) > _terrain.half_extent() - 4.0 \
					or absf(c.z) > _terrain.half_extent() - 4.0:
				continue
			var st: Dictionary = _footprint_stats(c, size)
			if not bool(st["dry"]):
				continue
			var rng := float(st["range"])
			if rng < band_lo or rng > band_hi:
				continue
			if not _spacing_ok(c):
				continue
			var score := o.length() + absf(rng - target) * 4.0
			if score < best_score:
				best_score = score
				best = {"center": c, "stats": st}
		if not best.is_empty():
			return best
	return {}


## The production spawn sequence (dungeon.gd _spawn_building_local),
## with pos.y = minimum terrain height under the footprint.
func _spawn_building(faction: int, btype: String, spot: Dictionary) -> RTSBuilding:
	var center: Vector3 = spot["center"]
	var st: Dictionary = spot["stats"]
	var civ := CivData.for_civ_id(str(CIVS[faction]))
	var b := RTSBuilding.new()
	b.setup(faction, btype, civ)
	b.building_id = _mgr.alloc_building_id()
	b.name = "RTSBuilding_%d" % b.building_id
	b.rts_manager = _mgr
	b.position = Vector3(center.x, float(st["min"]), center.z)
	_bases_node.add_child(b)
	b.start_construction()
	_placed.append(center)
	_buildings.append({"node": b, "faction": faction, "type": btype,
		"center": center, "mn": float(st["min"]), "mx": float(st["max"])})
	print("[RTSB] placed faction=", faction, " ", btype,
		" at (", snappedf(center.x, 0.1), ", ", snappedf(center.z, 0.1), ")",
		" footprint min=", snappedf(float(st["min"]), 0.01),
		" max=", snappedf(float(st["max"]), 0.01),
		" range=", snappedf(float(st["range"]), 0.01),
		" placed_y=", snappedf(float(st["min"]), 0.01))
	return b


func _place_base(faction: int, anchor: Vector3, slope_barracks: bool) -> void:
	# Town hall first: flattest dry spot near the anchor.
	var th_spot := _find_spot(anchor, FOOTPRINTS["town_hall"], 0.0, 0.35, 0.1)
	if th_spot.is_empty():
		_fails += 1
		printerr("[RTSB] FAIL no town_hall spot for faction ", faction)
		return
	_spawn_building(faction, "town_hall", th_spot)
	if faction == 0:
		_red_th_center = th_spot["center"]
	# Barracks: red's goes on a deliberate slope; blue's takes a mild one.
	var b_lo := 0.5 if slope_barracks else 0.2
	var b_hi := 1.25 if slope_barracks else 0.9
	var b_target := 0.85 if slope_barracks else 0.5
	var bar_spot := _find_spot(anchor, FOOTPRINTS["barracks"], b_lo, b_hi, b_target)
	if bar_spot.is_empty():
		_fails += 1
		printerr("[RTSB] FAIL no barracks spot for faction ", faction)
	else:
		var bar := _spawn_building(faction, "barracks", bar_spot)
		if slope_barracks:
			_slope_node = bar
			_slope_center = bar_spot["center"]
	# House: gentle ground. Red's house stays under construction for the
	# shots (proof the construction state reads on terrain).
	var h_spot := _find_spot(anchor, FOOTPRINTS["house"], 0.0, 0.45, 0.15)
	if h_spot.is_empty():
		_fails += 1
		printerr("[RTSB] FAIL no house spot for faction ", faction)
	else:
		var house := _spawn_building(faction, "house", h_spot)
		if faction == 0:
			_unfinished = house
	# Tower: gentle-to-mild ground.
	var t_spot := _find_spot(anchor, FOOTPRINTS["tower"], 0.0, 0.6, 0.2)
	if t_spot.is_empty():
		_fails += 1
		printerr("[RTSB] FAIL no tower spot for faction ", faction)
	else:
		_spawn_building(faction, "tower", t_spot)


# --- units (scale only; same spawn + snap as the units scene) ------------------

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


func _spawn_units() -> void:
	for rec in _buildings:
		if str(rec["type"]) != "town_hall":
			continue
		var faction := int(rec["faction"])
		var c: Vector3 = rec["center"]
		# 3 villagers around the hall (mirrors spawn_rts_base).
		for i in 3:
			var a := TAU * float(i) / 3.0 + 0.5
			var pos: Variant = _dry_pos(c + Vector3(cos(a) * 3.4, 0, sin(a) * 3.4), c)
			if pos != null:
				_spawn_one(faction, "villager", pos)
		# A few spearmen standing off the hall's front.
		for i in 3:
			var pos2: Variant = _dry_pos(c + Vector3(-2.0 + 2.0 * float(i), 0, 5.5), c)
			if pos2 != null:
				_spawn_one(faction, "spearman", pos2)


## Light prop dressing for scale, kept clear of the bases.
func _dress_light() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var placed: Array = []
	_scatter("tree", 18, rng, placed)
	_scatter("rock", 7, rng, placed)


func _scatter(type: String, count: int, rng: RandomNumberGenerator,
		placed: Array) -> void:
	var r_max := _terrain.half_extent() - 2.0
	var done := 0
	var guard := 0
	while done < count and guard < count * 60:
		guard += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * r_max
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if _terrain.is_water(p) or _slope(p) > 0.7:
			continue
		var clear := true
		for rec in _buildings:
			var c: Vector3 = rec["center"]
			if Vector2(p.x - c.x, p.z - c.z).length() < 8.0:
				clear = false
				break
		if not clear:
			continue
		for q in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < 5.0:
				clear = false
				break
		if not clear:
			continue
		placed.append(p)
		var prop := PropBuilder.build(type, 1.0, {"pos": p})
		prop.position = Vector3(p.x, _ground(p), p.z)
		prop.rotation.y = rng.randf() * TAU
		add_child(prop)
		done += 1


# --- screenshots -----------------------------------------------------------------

func _set_view(command: bool) -> void:
	_cam.active = command
	_cam.current = true
	get_tree().call_group("rts_units", "_on_command_view_toggled", command)


func _run_shots() -> void:
	# CRT shader curves the viewport; disable for clean inspection shots.
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	print("[RTSB] shots start buildings=", _buildings.size(),
		" units=", _units.size())
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	# Let buildings/units settle a few frames in their construction state.
	for i in 30:
		await get_tree().physics_frame
	# Complete every building except red's house (left mid-construction so
	# the dimmed state + 10% HP bar read in the shots).
	for rec in _buildings:
		var b: RTSBuilding = rec["node"]
		if b == _unfinished:
			continue
		b.add_build_work(1000.0)
	for i in 10:
		await get_tree().process_frame
	_report()
	# View 1: top-down command view of both bases.
	_set_view(true)
	_cam.position = Vector3(0, 80, 0.001)
	_cam.rotation = Vector3(-PI / 2, 0, 0)
	await _settle(15)
	await _snap("buildings_topdown.png")
	# View 2: low angle across the red base.
	_set_view(false)
	var th := _red_th_center
	var lp := th + Vector3(-10.5, 0, 10.5)
	_cam.position = Vector3(lp.x, _ground(lp) + 2.3, lp.z)
	_cam.look_at(Vector3(th.x, _ground(th) + 1.3, th.z))
	await _settle(15)
	await _snap("buildings_low.png")
	# View 3: close on the slope barracks, from downhill — the side where
	# min-height basing must sit flush (the uphill side is buried).
	if _slope_node != null:
		var c := _slope_center
		var e := 1.5
		var gx := _ground(c + Vector3(e, 0, 0)) - _ground(c + Vector3(-e, 0, 0))
		var gz := _ground(c + Vector3(0, 0, e)) - _ground(c + Vector3(0, 0, -e))
		var down := Vector2(-gx, -gz)
		if down.length() < 0.01:
			down = Vector2(0, 1)
		down = down.normalized()
		var cp := c + Vector3(down.x * 7.5, 0, down.y * 7.5)
		_cam.position = Vector3(cp.x, _ground(cp) + 1.7, cp.z)
		_cam.look_at(Vector3(c.x, float(_slope_node.position.y) + 1.0, c.z))
		await _settle(15)
		await _snap("buildings_slope.png")
	print("[RTSB] shots done")


func _report() -> void:
	for rec in _buildings:
		var b: RTSBuilding = rec["node"]
		print("[RTSB] faction=", int(rec["faction"]), " ", str(rec["type"]),
			" range=", snappedf(float(rec["mx"]) - float(rec["mn"]), 0.01),
			" placed_y=", snappedf(float(rec["mn"]), 0.01),
			" node_y=", snappedf(b.position.y, 0.01),
			" under_construction=", b.under_construction,
			" build_progress=", snappedf(b.build_progress, 0.01))


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fails += 1
		printerr("[RTSB] FAIL empty image for ", file_name)
		return
	img.save_png(_shot_dir + "/" + file_name)
	print("[RTSB] saved ", _shot_dir + "/" + file_name)
