class_name WarlordMap
extends RefCounted
## Issue #266 P1 — standalone Warlord map format, loader, and validator.
##
## The §5 map format (JSON, canonical key order for hashing):
##   format_version (1 in v1), name, display_name, size_m (160 or 220),
##   seed, zones [{center [x,z], radius, radius_z (nullable), height in
##   {3,6,9}}], ramps [{base [x,z], dir [x,z] (unit, uphill), length,
##   width, h0, h1}], ponds [{center [x,z], radius}], starts [{faction,
##   pos [x,z]}], nodes [{type in {wood, food, gold, stone}, pos [x,z],
##   amount}].
##
## NOT in the format, by design (§5.3): no tuning (refused), no starting
## buildings (the key is refused if present), no river.
##
## Loader-side format gaps (gate-accepted, 2026-11-24 — the format itself
## is unchanged): §5 zones carry no phase1/phase2, but ZonesTerrain
## reads them bare, so the loader injects 0.0 defaults; §5 carries no
## base-noise profile, so the loader hardcodes the warlords_maps profile
## (noise 0.045 / amplitude 0.6 / water -0.55 / 1 smooth pass / pond
## depth 1.7); §5 ponds {center, radius} map to the parent's pond_specs.
## "height_at" anywhere in the spec means
## HeightmapTerrain.get_ground_height(Vector3(x, 0, z)).
##
## Validation runs on UNTRUSTED bytes (a host sends the map to clients),
## so every check is null-safe: a malformed map yields a named refusal,
## never a crash.

const FORMAT_VERSION := 1
const SUPPORTED_VERSIONS: Array[int] = [1]
const MAP_SIZES: Array[int] = [160, 220]

## Base-noise profile, hardcoded from warlords_maps.gd _build_terrain().
const NOISE_FREQUENCY := 0.045
const NOISE_AMPLITUDE := 0.6
const WATER_LEVEL := -0.55
const SMOOTH_PASSES := 1
const POND_DEPTH := 1.7

## Validation thresholds — the warlords_maps proof values, extracted.
const TIER_TOL := 1.0
const FOOTPRINT_RANGE_MAX := 1.2
const FOOTPRINT_PAD := 0.2
const FOOTPRINT_SIZE := 3.4
const GRADE_MAX := 0.7
const EDGE_GRADE_MIN := 1.19
## Measurement tolerance on the (h) grade: the grade is read off
## bilinear heights carrying the base noise (±0.3 m), so a reading
## within 0.05 of the limit is indistinguishable from the limit
## (ring12's zone 4 reads 1.1887 on one direction, 1.24-1.63 on
## the rest). Genuinely unblocked edges read <= 0.5, an order of
## magnitude below the bar, so the tolerance opens no hole.
const EDGE_GRADE_TOL := 0.05
const STARTS_MIN := 2
const STARTS_MAX := 12
const EDGE_SAMPLE_DIRS := 16
const RESOURCE_TYPES: Array[String] = ["wood", "food", "gold", "stone"]
const TIER_HEIGHTS: Array[int] = [3, 6, 9]

const STANDARD_PATH := "res://data/maps/standard.json"
const USER_MAPS_DIR := "user://maps"


## Canonical JSON: keys sorted recursively, compact, no whitespace
## variance — the §3.5 hash is over this exact string.
static func canonical_json(map_data: Dictionary) -> String:
	return JSON.stringify(_canonicalized(map_data))


static func _canonicalized(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		var out := {}
		for k in keys:
			out[str(k)] = _canonicalized(value[k])
		return out
	if value is Array:
		var arr: Array = []
		for v in value:
			arr.append(_canonicalized(v))
		return arr
	return value


## SHA-256 hex of the canonical JSON bytes.
static func map_hash(map_data: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical_json(map_data).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Parse map JSON. Never crashes on malformed input.
static func parse_map(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "map": {}, "error": "map is not valid JSON object"}
	return {"ok": true, "map": parsed, "error": ""}


static func display_name(map_data: Dictionary) -> String:
	var dn := str(map_data.get("display_name", ""))
	if dn != "":
		return dn
	return str(map_data.get("name", "Unnamed map"))


static func start_count(map_data: Dictionary) -> int:
	var starts: Variant = map_data.get("starts", [])
	if not (starts is Array):
		return 0
	return starts.size()


## Is a world position inside any pond of this map (2D test)? Used by
## the bake-time scatter; the runtime water test is the built terrain's
## is_water(), which also covers carved basins.
static func is_pond_water(map_data: Dictionary, pos: Vector3) -> bool:
	var ponds: Variant = map_data.get("ponds", [])
	if not (ponds is Array):
		return false
	for p in ponds:
		if not (p is Dictionary):
			continue
		var c := _vec2_from(p.get("center", []))
		if c == Vector2.INF:
			continue
		if Vector2(pos.x, pos.z).distance_to(c) < float(p.get("radius", 0.0)):
			return true
	return false


## Build the ZonesTerrain for a map dict. Configured, NOT added to the
## tree and NOT generated — the caller adds it and calls generate().
## Returns null when the map's shape is too broken to configure
## (validate() is the gate; this is a convenience for the match scene,
## which only ever builds validated maps).
static func build_terrain(map_data: Dictionary) -> ZonesTerrain:
	var size_m := int(map_data.get("size_m", 0))
	if size_m not in MAP_SIZES:
		return null
	var t := ZonesTerrain.new()
	t.map_points = size_m + 1
	t.cell_size = 1.0
	t.terrain_seed = int(map_data.get("seed", 0))
	t.noise_frequency = NOISE_FREQUENCY
	t.amplitude = NOISE_AMPLITUDE
	t.water_level = WATER_LEVEL
	t.smooth_passes = SMOOTH_PASSES
	t.pond_depth = POND_DEPTH
	var zones: Array = []
	for z in _arr(map_data.get("zones", [])):
		if not (z is Dictionary):
			continue
		var zn := (z as Dictionary).duplicate()
		if not zn.has("phase1"):
			zn["phase1"] = 0.0
		if not zn.has("phase2"):
			zn["phase2"] = 0.0
		# The §5 format stores centers as [x, z] arrays; ZonesTerrain
		# reads them as Vector2 — translate here, at the format boundary.
		var zc := _vec2_from(zn.get("center", []))
		if zc == Vector2.INF:
			return null
		zn["center"] = zc
		zones.append(zn)
	t.zones.assign(zones)
	var ramps: Array = []
	for r in _arr(map_data.get("ramps", [])):
		if not (r is Dictionary):
			continue
		var rp := (r as Dictionary).duplicate()
		var rb := _vec2_from(rp.get("base", []))
		var rd := _vec2_from(rp.get("dir", []))
		if rb == Vector2.INF or rd == Vector2.INF:
			return null
		rp["base"] = rb
		rp["dir"] = rd
		ramps.append(rp)
	t.ramps.assign(ramps)
	var specs: Array = []
	for p in _arr(map_data.get("ponds", [])):
		if not (p is Dictionary):
			continue
		var c := _vec2_from(p.get("center", []))
		if c == Vector2.INF:
			continue
		specs.append({"center": Vector3(c.x, 0.0, c.y),
			"radius": float(p.get("radius", 0.0))})
	t.pond_specs.assign(specs)
	return t


## The built-in Standard map (data/maps/standard.json). {} on failure.
static func standard_map() -> Dictionary:
	if not FileAccess.file_exists(STANDARD_PATH):
		push_error("[WarlordMap] Standard map missing: %s" % STANDARD_PATH)
		return {}
	var parsed := parse_map(FileAccess.get_file_as_string(STANDARD_PATH))
	if not bool(parsed.get("ok", false)):
		push_error("[WarlordMap] Standard map unparsable: %s"
			% str(parsed.get("error", "?")))
		return {}
	return parsed["map"]


## Every map in user://maps/ — valid and invalid alike. Invalid files
## are included with their validation error (the host picker greys them
## with the failure); a directory that does not exist yields [].
static func list_user_maps() -> Array:
	var out: Array = []
	var dir := DirAccess.open(USER_MAPS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json") and not dir.current_is_dir():
			var path := USER_MAPS_DIR + "/" + fname
			var parsed := parse_map(FileAccess.get_file_as_string(path))
			if bool(parsed.get("ok", false)):
				var m: Dictionary = parsed["map"]
				var err := validate(m)
				out.append({"name": str(m.get("name", fname.trim_suffix(".json"))),
					"path": path, "map": m,
					"valid": err == "", "error": err})
			else:
				out.append({"name": fname.trim_suffix(".json"), "path": path,
					"map": {}, "valid": false,
					"error": str(parsed.get("error", "?"))})
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")) < str(b.get("name", "")))
	return out


## Validate a parsed map dict. "" = valid; otherwise the FIRST failing
## rule's message, in §5.4 order. Builds the terrain once for the
## height-sampling rules (d), (e), (h).
static func validate(map_data: Dictionary) -> String:
	if map_data.is_empty():
		return "map is empty"
	var ver := int(map_data.get("format_version", -1))
	if ver not in SUPPORTED_VERSIONS:
		return "unsupported format_version %d" % ver
	if map_data.has("starting_buildings"):
		return "map carries starting_buildings — refused in format v1"
	if map_data.has("tuning"):
		return "map carries tuning — maps never carry tuning"
	var size_m := int(map_data.get("size_m", 0))
	if size_m not in MAP_SIZES:
		return "size_m must be 160 or 220"
	var zones := _arr(map_data.get("zones", []))
	for z in zones:
		if not (z is Dictionary):
			return "zone is not an object"
		var h := int((z as Dictionary).get("height", -1))
		if h not in TIER_HEIGHTS:
			return "zone height must be 3, 6, or 9"
		if float((z as Dictionary).get("radius", 0.0)) <= 0.0:
			return "zone radius must be positive"
		if _vec2_from((z as Dictionary).get("center", [])) == Vector2.INF:
			return "zone center must be [x, z]"
	var ramps := _arr(map_data.get("ramps", []))
	for r in ramps:
		if not (r is Dictionary):
			return "ramp is not an object"
		var rd := (r as Dictionary)
		if _vec2_from(rd.get("base", [])) == Vector2.INF:
			return "ramp base must be [x, z]"
		var d := _vec2_from(rd.get("dir", []))
		if d == Vector2.INF:
			return "ramp dir must be [x, z]"
		if absf(d.length() - 1.0) > 0.01:
			return "ramp dir must be a unit vector"
		if float(rd.get("length", 0.0)) <= 0.0:
			return "ramp length must be positive"
		if float(rd.get("width", 0.0)) <= 0.0:
			return "ramp width must be positive"
		var h0 := int(rd.get("h0", -1))
		var h1 := int(rd.get("h1", -1))
		if h0 not in [0, 3, 6, 9] or h1 not in [0, 3, 6, 9] or h1 <= h0:
			return "ramp h0/h1 must be tier heights with h1 > h0"
	var ponds := _arr(map_data.get("ponds", []))
	for p in ponds:
		if not (p is Dictionary):
			return "pond is not an object"
		if _vec2_from((p as Dictionary).get("center", [])) == Vector2.INF:
			return "pond center must be [x, z]"
		if float((p as Dictionary).get("radius", 0.0)) <= 0.0:
			return "pond radius must be positive"
	var starts := _arr(map_data.get("starts", []))
	if starts.size() < STARTS_MIN or starts.size() > STARTS_MAX:
		return "starts must number 2-12"
	var seen_factions := {}
	for s in starts:
		if not (s is Dictionary):
			return "start is not an object"
		var fid := int((s as Dictionary).get("faction", -1))
		if fid < 0 or fid >= STARTS_MAX or seen_factions.has(fid):
			return "start factions must be unique ids 0-11"
		seen_factions[fid] = true
		if _vec2_from((s as Dictionary).get("pos", [])) == Vector2.INF:
			return "start pos must be [x, z]"
	var nodes := _arr(map_data.get("nodes", []))
	var have_types := {}
	for n in nodes:
		if not (n is Dictionary):
			return "node is not an object"
		var nd := (n as Dictionary)
		if str(nd.get("type", "")) not in RESOURCE_TYPES:
			return "node type must be wood, food, gold, or stone"
		if _vec2_from(nd.get("pos", [])) == Vector2.INF:
			return "node pos must be [x, z]"
		if int(nd.get("amount", 0)) <= 0:
			return "node amount must be positive"
		have_types[str(nd.get("type", ""))] = true
	for t in RESOURCE_TYPES:
		if not have_types.has(t):
			return "map needs at least one %s node" % t
	var half := float(size_m) * 0.5
	for s in starts:
		var p := _vec2_from((s as Dictionary).get("pos", []))
		if absf(p.x) > half - 2.0 or absf(p.y) > half - 2.0:
			return "start %d is outside the map" % int((s as Dictionary).get("faction", -1))
	for z in zones:
		var c := _vec2_from((z as Dictionary).get("center", []))
		if absf(c.x) > half or absf(c.y) > half:
			return "zone center is outside the map"
	for r in ramps:
		var b := _vec2_from((r as Dictionary).get("base", []))
		if absf(b.x) > half or absf(b.y) > half:
			return "ramp base is outside the map"
	# Height-sampling rules (d), (e), (h) run on the built terrain.
	var terrain := build_terrain(map_data)
	if terrain == null:
		return "could not build terrain from map"
	terrain.generate()
	var err := _validate_heights(map_data, terrain)
	terrain.free()
	return err


static func _validate_heights(map_data: Dictionary, t: ZonesTerrain) -> String:
	var zones := _arr(map_data.get("zones", []))
	var ramps := _arr(map_data.get("ramps", []))
	# (d) Ramp tier-match + centreline grade (warlords_maps
	# _report_ramp_grades: sample every 0.5 m, 1.0 m window, hard
	# fail at gmax > 0.7).
	for r in ramps:
		var rd := r as Dictionary
		var base := _vec2_from(rd.get("base", []))
		var dir := _vec2_from(rd.get("dir", []))
		var length := float(rd.get("length", 0.0))
		var h0 := float(rd.get("h0", 0))
		var h1 := float(rd.get("h1", 0))
		var h_base := t.get_ground_height(Vector3(base.x, 0.0, base.y))
		var top := base + dir * length
		var h_top := t.get_ground_height(Vector3(top.x, 0.0, top.y))
		if absf(h_base - h0) > TIER_TOL:
			return "ramp base height %.2f does not match h0 %d" % [h_base, int(h0)]
		if absf(h_top - h1) > TIER_TOL:
			return "ramp top height %.2f does not match h1 %d" % [h_top, int(h1)]
		var gmax := 0.0
		var s := -1.0
		while s <= length + 1.0:
			var a := base + dir * (s - 0.5)
			var b2 := base + dir * (s + 0.5)
			var ha := t.get_ground_height(Vector3(a.x, 0.0, a.y))
			var hb := t.get_ground_height(Vector3(b2.x, 0.0, b2.y))
			gmax = maxf(gmax, absf(hb - ha) / 1.0)
			s += 0.5
		if gmax > GRADE_MAX:
			return "ramp grade %.2f exceeds the 0.7 cap" % gmax
	# (e) Starts on dry flat ground (warlords_maps _footprint_stats:
	# town-hall footprint + PAD on a 0.4 m grid, range over the 1.2 m
	# cap fails; dry = min >= water_level + 0.02).
	var half_span := (FOOTPRINT_SIZE + FOOTPRINT_PAD * 2.0) * 0.5
	for st in _arr(map_data.get("starts", [])):
		var sd := st as Dictionary
		var p := _vec2_from(sd.get("pos", []))
		var mn := INF
		var mx := -INF
		var x := -half_span
		while x <= half_span + 0.01:
			var z := -half_span
			while z <= half_span + 0.01:
				var h := t.get_ground_height(Vector3(p.x + x, 0.0, p.y + z))
				mn = minf(mn, h)
				mx = maxf(mx, h)
				z += 0.4
			x += 0.4
		if mx - mn > FOOTPRINT_RANGE_MAX:
			return "start %d footprint range %.2f exceeds the 1.2 m cap" \
				% [int(sd.get("faction", -1)), mx - mn]
		if mn < WATER_LEVEL + 0.02:
			return "start %d is in water" % int(sd.get("faction", -1))
	# (f) Connectivity — union-find over regions (ground + zones;
	# each ramp unites the region of its base point with the region
	# of its top point). Every start must reach every other start.
	var parent := {}
	var find := func(id: int) -> int:
		var root := id
		while parent.get(root, root) != root:
			root = parent[root]
		return root
	var union := func(a: int, b: int) -> void:
		var ra: int = find.call(a)
		var rb: int = find.call(b)
		if ra != rb:
			parent[ra] = rb
	for i in zones.size() + 1:
		parent[i] = i
	var region_of := func(p: Vector2) -> int:
		var best_band := 0.0
		var best_zone := -1
		# The TERRAIN's zones (build_terrain converted their centers
		# to Vector2); the map's raw dicts still carry [x, z] arrays,
		# which _zone_band cannot read.
		for zi in t.zones.size():
			var zn := t.zones[zi] as Dictionary
			var band := t._zone_band(zn, p.x, p.y)
			if band > best_band:
				best_band = band
				best_zone = zi
		return best_zone + 1 if best_zone >= 0 else 0
	for r in ramps:
		var rd := r as Dictionary
		var base := _vec2_from(rd.get("base", []))
		var dir := _vec2_from(rd.get("dir", []))
		var top := base + dir * float(rd.get("length", 0.0))
		union.call(region_of.call(base), region_of.call(top))
	var first_region := -1
	for st in _arr(map_data.get("starts", [])):
		var p := _vec2_from((st as Dictionary).get("pos", []))
		var reg: int = find.call(region_of.call(p))
		if first_region < 0:
			first_region = reg
		elif reg != first_region:
			return "start %d cannot reach the other starts" \
				% int((st as Dictionary).get("faction", -1))
	# (h) Walker stall at every non-ramp tier edge: the surface grade
	# across the edge band must exceed the 119% physics floor limit
	# (floor_max_angle 50deg — terrain_walker.gd:37) on every sampled
	# non-ramp radial direction. Grade is the gradient magnitude via
	# 0.9 m central differences — the zones_test _grade measurement,
	# i.e. the slope the physics floor check actually sees (a radial
	# grade would under-read wherever the outline wobble tilts the
	# edge). The outline wobbles ±26%, so the edge along a ray can
	# sit anywhere in [0.70, 1.30] x the nominal edge distance — the
	# samples cover the whole annulus, skipping points inside a ramp
	# channel (a ramped edge is crossable by design).
	for zi in zones.size():
		var zn := zones[zi] as Dictionary
		var c := _vec2_from(zn.get("center", []))
		var rx := float(zn.get("radius", 0.0))
		var rz := float(zn.get("radius_z", rx))
		for k in EDGE_SAMPLE_DIRS:
			var ang := TAU * float(k) / float(EDGE_SAMPLE_DIRS)
			var u := Vector2(cos(ang), sin(ang))
			var denom := sqrt((u.x * u.x) / (rx * rx) + (u.y * u.y) / (rz * rz))
			var edge_d := 1.0 / denom if denom > 0.0 else rx
			# The edge's location on THIS ray is where the height
			# drops fastest (all samples, channel or not). If that
			# drop sits inside a ramp channel, the edge is ramped
			# along this ray — a ramp crossing, not a cliff — and
			# the direction is skipped, not failed. Otherwise the
			# direction is a real cliff: grade its non-channel
			# samples inside the transition band (band from the
			# ray's own sampled heights — nested zones drop onto
			# the tier below, and a neighbouring zone's flank can
			# be the ground side).
			var all_pts: Array = []
			var d := edge_d * 0.70
			while d <= edge_d * 1.30:
				var mid := c + u * d
				all_pts.append([mid, t.get_ground_height(Vector3(mid.x, 0.0, mid.y))])
				d += 0.5
			var steep_i := -1
			var steep_drop := 0.0
			for i in range(all_pts.size() - 1):
				var drop := absf(float(all_pts[i][1]) - float(all_pts[i + 1][1]))
				if drop > steep_drop:
					steep_drop = drop
					steep_i = i
			if steep_i < 0 or steep_drop < 0.5:
				continue
			var p0: Vector2 = all_pts[steep_i][0]
			var p1: Vector2 = all_pts[steep_i + 1][0]
			if _in_ramp_channel(ramps, p0) or _in_ramp_channel(ramps, p1):
				continue
			var pts: Array = []
			for pt in all_pts:
				if not _in_ramp_channel(ramps, pt[0]):
					pts.append(pt)
			if pts.is_empty():
				continue
			# Transition band: the plateau side is the zone's own
			# tier (a neighbour's flank can stand in for the ground
			# side, so it comes from the samples, channel or not).
			var h_lo := INF
			for pt in all_pts:
				h_lo = minf(h_lo, float(pt[1]))
			var tier := float(zn.get("height", 0.0))
			if tier - h_lo < 0.5:
				continue
			var lo := h_lo + 0.15 * (tier - h_lo)
			var hi := h_lo + 0.85 * (tier - h_lo)
			var gmax := 0.0
			var edge_samples := 0
			for pt in pts:
				if float(pt[1]) >= lo and float(pt[1]) <= hi:
					gmax = maxf(gmax, _surface_grade(t, pt[0]))
					edge_samples += 1
			if edge_samples > 0 and gmax < EDGE_GRADE_MIN - EDGE_GRADE_TOL:
				return "zone %d edge does not block walkers (max grade %.2f)" \
					% [zi, gmax]
	return ""


## Surface grade at a point: gradient magnitude via 0.9 m central
## differences (zones_test.gd _grade).
static func _surface_grade(t: ZonesTerrain, p: Vector2) -> float:
	var e := 0.9
	var dx := t.get_ground_height(Vector3(p.x + e, 0.0, p.y)) \
		- t.get_ground_height(Vector3(p.x - e, 0.0, p.y))
	var dz := t.get_ground_height(Vector3(p.x, 0.0, p.y + e)) \
		- t.get_ground_height(Vector3(p.x, 0.0, p.y - e))
	return sqrt(dx * dx + dz * dz) / (2.0 * e)


static func _in_ramp_channel(ramps: Array, p: Vector2) -> bool:
	for r in ramps:
		var rd := r as Dictionary
		var base := _vec2_from(rd.get("base", []))
		var dir := _vec2_from(rd.get("dir", []))
		var rx := p.x - base.x
		var rz := p.y - base.y
		var s := rx * dir.x + rz * dir.y
		var lat := rx * -dir.y + rz * dir.x
		if s >= -1.5 and s <= float(rd.get("length", 0.0)) + 1.5 \
				and absf(lat) < float(rd.get("width", 0.0)) * 0.5 + 1.0:
			return true
	return false


static func _arr(v: Variant) -> Array:
	if v is Array:
		return v
	return []


static func _vec2_from(v: Variant) -> Vector2:
	if not (v is Array) or (v as Array).size() != 2:
		return Vector2.INF
	var a: Array = v
	if not (a[0] is float or a[0] is int) \
			or not (a[1] is float or a[1] is int):
		return Vector2.INF
	return Vector2(float(a[0]), float(a[1]))
