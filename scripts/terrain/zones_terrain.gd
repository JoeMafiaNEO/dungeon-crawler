class_name ZonesTerrain
extends HeightmapTerrain
## Issue #103 ELEVATED-ZONES variant of HeightmapTerrain (Jesse's design
## proposal): instead of rolling noise hills everywhere, the terrain
## stays relatively FLAT and the height lives in discrete plateau zones
## (tiers). Steepness is concentrated at plateau edges (short terrace
## walls physics bodies cannot climb) and carved ramps (the only way
## up, grade-capped). TEST SCENE ONLY — not wired into production.
##
## Height model (zone-only height, before the ±noise base is added):
##   zone_h(p) = max over zones of tier_height * smoothstep across the
##   zone's edge band, where the zone boundary radius wobbles with
##   angle (irregular blob, not a circle). Ramps then blend the zone
##   height toward a smooth ramp profile inside an oriented channel:
##   crossing an edge inside a ramp channel follows the ramp's capped
##   grade instead of the steep band.

## Half-width of a plateau edge band: the full rise happens over
## 2 * edge_falloff metres (~2.5m total). A 3m tier over 2.5m peaks
## near 180% grade — over the 119% physics floor limit, so edges
## block walkers like walls.
var edge_falloff: float = 1.25
## Zones: {center: Vector2 (xz), radius: float, height: float,
## phase1/phase2: float — angular wobble phases for the blob outline}.
var zones: Array[Dictionary] = []
## Ramps: {base: Vector2 (xz, lower-tier end), dir: Vector2 (unit,
## uphill), length: float, width: float, h0/h1: tier heights}.
var ramps: Array[Dictionary] = []


## Zone-only height at a world position (no base noise). Used by the
## generate pass and by the test driver for flatness proofs.
func zone_height_at(wx: float, wz: float) -> float:
	var best := 0.0
	for zn in zones:
		var c: Vector2 = zn["center"]
		var dx := wx - c.x
		var dz := wz - c.y
		var dist := sqrt(dx * dx + dz * dz)
		var ang := atan2(dz, dx)
		var r := float(zn["radius"]) * (1.0 \
			+ 0.16 * sin(3.0 * ang + float(zn["phase1"])) \
			+ 0.10 * sin(5.0 * ang + float(zn["phase2"])))
		var t := smoothstep(-edge_falloff, edge_falloff, r - dist)
		best = maxf(best, float(zn["height"]) * t)
	for rp in ramps:
		var b: Vector2 = rp["base"]
		var dir: Vector2 = rp["dir"]
		var rx := wx - b.x
		var rz := wz - b.y
		var s := rx * dir.x + rz * dir.y
		var lat := rx * -dir.y + rz * dir.x
		var len := float(rp["length"])
		if s < -1.5 or s > len + 1.5:
			continue
		var half_w := float(rp["width"]) * 0.5
		var m_lat := 1.0 - smoothstep(half_w - 1.0, half_w + 1.0, absf(lat))
		if m_lat <= 0.0:
			continue
		var m_end := smoothstep(-1.5, 1.5, s) \
			* (1.0 - smoothstep(len - 1.5, len + 1.5, s))
		var u := clampf(s / len, 0.0, 1.0)
		var rh := lerpf(float(rp["h0"]), float(rp["h1"]),
			u * u * (3.0 - 2.0 * u))
		best = lerpf(best, rh, m_lat * m_end)
	return best


func generate() -> void:
	# Mirrors HeightmapTerrain.generate() (the parent has no
	# mid-generation hook): gentle base noise first, relaxed while the
	# field is still zone-free so plateau edges stay crisp, then the
	# zone heights are added on top, then ponds are carved.
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = noise_frequency
	_noise.fractal_octaves = 3
	_heights.resize(map_points * map_points)
	for z in map_points:
		for x in map_points:
			var wx := (float(x) - float(map_points - 1) * 0.5) * cell_size
			var wz := (float(z) - float(map_points - 1) * 0.5) * cell_size
			var n := _noise.get_noise_2d(wx, wz) * 0.5 + 0.5
			_heights[z * map_points + x] = n * amplitude - amplitude * 0.5
	for i in smooth_passes:
		_relax()
	for z in map_points:
		for x in map_points:
			var wx := (float(x) - float(map_points - 1) * 0.5) * cell_size
			var wz := (float(z) - float(map_points - 1) * 0.5) * cell_size
			_heights[z * map_points + x] += zone_height_at(wx, wz)
	_carve_ponds()
	_min_height = _heights[0]
	for h in _heights:
		_min_height = minf(_min_height, h)
	_build_mesh()
	_build_collision()
	_build_water()


## Tier palette: grass on the flats (slightly drier with altitude),
## dirt shoulders on moderate slopes, rock on the steep edge bands.
func _vertex_color(h: float, slope: float) -> Color:
	if h < water_level:
		return tint_bed
	if slope > 0.85:
		return tint_high
	var t := clampf(h / 7.0, 0.0, 1.0)
	var c := tint_low.lerp(tint_mid, t * 0.5)
	if slope > 0.4:
		c = c.lerp(tint_high, clampf((slope - 0.4) / 0.45, 0.0, 1.0) * 0.55)
	return c
