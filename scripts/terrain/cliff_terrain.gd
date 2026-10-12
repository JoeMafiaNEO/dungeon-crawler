class_name CliffTerrain
extends HeightmapTerrain
## Issue #103 cliff stress variant of HeightmapTerrain: blends a steep
## escarpment into the noise field — a smoothstep ridge running along
## the z axis, so the map has a low valley (west), a cliff face, and a
## high plateau (east). TEST SCENE ONLY — not wired into production.

## Total rise of the escarpment (plateau height above the valley field).
var ridge_height: float = 10.0
## World x of the face centerline.
var ridge_center_x: float = 0.0
## Half-width of the face band: the profile runs from
## ridge_center_x - ridge_half_width (valley side) to
## ridge_center_x + ridge_half_width (plateau side). Peak grade is
## ridge_height * 1.5 / (2 * ridge_half_width).
var ridge_half_width: float = 4.0


func ridge_offset(wx: float) -> float:
	var span := 2.0 * ridge_half_width
	var t := clampf((wx - (ridge_center_x - ridge_half_width)) / span, 0.0, 1.0)
	return ridge_height * (t * t * (3.0 - 2.0 * t))


func generate() -> void:
	# Mirrors HeightmapTerrain.generate(), with the ridge offset added to
	# every sample before POI flattening / pond carving. (The parent's
	# generate() has no mid-generation hook; test scenes only.)
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
			_heights[z * map_points + x] = n * amplitude - amplitude * 0.5 + ridge_offset(wx)
	_flatten_pois()
	_carve_ponds()
	for i in smooth_passes:
		_relax()
	_min_height = _heights[0]
	for h in _heights:
		_min_height = minf(_min_height, h)
	_build_mesh()
	_build_collision()
	_build_water()
