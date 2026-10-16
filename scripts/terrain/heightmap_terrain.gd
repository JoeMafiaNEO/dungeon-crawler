class_name HeightmapTerrain
extends Node3D
## Issue #103 test-scene tech: FastNoiseLite heightmap terrain with
## HeightMapShape3D collision, a cheap bilinear get_ground_height() array
## path (the perf rule for 1500 RTS units), vertex-color SNES placeholder
## tinting, and an animated water plane. ISOLATED TEST ONLY — not wired
## into dungeon.gd / procgen / level themes.

@export var map_points: int = 65 ## grid points per side (64 cells)
@export var cell_size: float = 1.0
@export var terrain_seed: int = 1234
@export var noise_frequency: float = 0.035
@export var amplitude: float = 3.5
## Constant lift applied to every generated height (default 0 = the
## original test-scene behavior). Lets a profile sit its whole noise
## range above the water plane so only carved ponds become water.
@export var height_offset: float = 0.0
@export var water_level: float = 0.6
@export var smooth_passes: int = 2
@export var flatten_radius: float = 8.0 ## POI flatten radius (spec: layout-constrained gen)
@export var pond_radius: float = 5.0
@export var pond_depth: float = 1.6
## Vertex-color palette (defaults = the original grass/dirt/rock look;
## cave flavors override toward dark rock).
@export var tint_bed: Color = Color(0.72, 0.66, 0.47) ## under water
@export var tint_low: Color = Color(0.28, 0.52, 0.24)
@export var tint_mid: Color = Color(0.50, 0.40, 0.28)
@export var tint_high: Color = Color(0.45, 0.45, 0.48)
## Vertex-tint ramp anchor: the height t=0 sits at. NAN (default) =
## anchor at water_level, the original behavior. Dry profiles whose
## water is parked below the terrain set this to their design floor so
## the low/mid/high bands can express (issue #118 follow-up).
@export var tint_anchor: float = NAN
## Water plane shader colors.
@export var water_shallow: Color = Color(0.25, 0.55, 0.72, 0.88)
@export var water_deep: Color = Color(0.10, 0.28, 0.48, 0.92)

## [QA] #124: depth of the perimeter skirt band appended by _build_mesh.
## The sheet is zero-thickness; where the perimeter is not backed by a
## wall (the station-annex door span), the residual edge height above
## the y=0 apron left a see-through slot under the sheet. The skirt
## hangs this far below every edge vertex so no in-play sightline can
## pass under the sheet. 2.0 matches dungeon.gd's wall-bottom drop,
## which exists for the same anti-gap purpose.
const SKIRT_DEPTH := 2.0

## Flatten targets: terrain relaxes toward the center height near these.
var poi_points: Array[Vector3] = []
## Explicit-height flatten targets: { "pos": Vector3, "height": float,
## "radius": float }. Terrain relaxes toward the GIVEN height (e.g. meet
## a doorway floor at y=0) instead of the sampled center height. A NAN
## height instead samples the local grid height at the target's center
## (POI-style local flatten at an explicit radius — issue #122).
var flatten_targets: Array[Dictionary] = []
## Carved basins (become real water where below water_level).
var pond_centers: Array[Vector3] = []
## Per-pond carve specs: { "center": Vector3, "radius": float } — each
## basin carved at its own radius instead of the global pond_radius.
var pond_specs: Array[Dictionary] = []

var _heights := PackedFloat32Array()
var _min_height := 0.0
var _noise := FastNoiseLite.new()
var _mesh_instance: MeshInstance3D
var _water_mesh: MeshInstance3D


func half_extent() -> float:
	return float(map_points - 1) * cell_size * 0.5


func generate() -> void:
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
			_heights[z * map_points + x] = n * amplitude - amplitude * 0.5 + height_offset
	_flatten_pois()
	_flatten_targets()
	_carve_ponds()
	for i in smooth_passes:
		_relax()
	_min_height = _heights[0]
	for h in _heights:
		_min_height = minf(_min_height, h)
	_build_mesh()
	_build_collision()
	_build_water()


## Cheap bilinear sample of the stored heightmap array. NEVER a physics
## query — this is the per-frame path for thousands of RTS units.
func get_ground_height(pos: Vector3) -> float:
	var half := half_extent()
	var max_g := float(map_points - 1) - 0.001
	var gx := clampf((pos.x + half) / cell_size, 0.0, max_g)
	var gz := clampf((pos.z + half) / cell_size, 0.0, max_g)
	var x0 := int(gx)
	var z0 := int(gz)
	var fx := gx - float(x0)
	var fz := gz - float(z0)
	var h00 := _heights[z0 * map_points + x0]
	var h10 := _heights[z0 * map_points + x0 + 1]
	var h01 := _heights[(z0 + 1) * map_points + x0]
	var h11 := _heights[(z0 + 1) * map_points + x0 + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func is_water(pos: Vector3) -> bool:
	return get_ground_height(pos) < water_level


func heights_copy() -> PackedFloat32Array:
	return _heights.duplicate()


## Issue #138: rebuild the surface from a baked height array instead of
## generating it. Pregenerated scenes whose scene file would bust the
## size budget ship heights-as-data only (LevelData.heights); at load
## the mesh / collision / water are regenerated from those heights by
## this same single-sourced build code, so the surface is identical
## to the generated one. The profile exports (amplitude, tints, water
## level, ...) must already carry the theme's values — the baked
## scene's terrain node serializes them from the bake run.
## Issue #138 Phase 2: adopt a baked height array as this terrain's
## query data WITHOUT rebuilding the surface — the mesh-mode baked
## scene already froze mesh + collision into the scene; only the
## (non-serialized) height array needs restoring so
## get_ground_height() answers identically to the generation run.
func load_heights(baked: PackedFloat32Array) -> void:
	_heights = baked.duplicate()
	_min_height = _heights[0] if not _heights.is_empty() else 0.0
	for h in _heights:
		_min_height = minf(_min_height, h)


func build_from_heights(baked: PackedFloat32Array, points: int, cell: float) -> void:
	map_points = points
	cell_size = cell
	_heights = baked.duplicate()
	_min_height = _heights[0] if not _heights.is_empty() else 0.0
	for h in _heights:
		_min_height = minf(_min_height, h)
	_build_mesh()
	_build_collision()
	_build_water()


func _sample_grid(x: int, z: int) -> float:
	return _heights[clampi(z, 0, map_points - 1) * map_points + clampi(x, 0, map_points - 1)]


func _flatten_pois() -> void:
	for poi in poi_points:
		var cx := int(round((poi.x / cell_size) + float(map_points - 1) * 0.5))
		var cz := int(round((poi.z / cell_size) + float(map_points - 1) * 0.5))
		var target := _sample_grid(cx, cz)
		var r := int(ceil(flatten_radius / cell_size))
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var dist := sqrt(float(dx * dx + dz * dz)) * cell_size
				if dist > flatten_radius:
					continue
				var t := 1.0 - smoothstep(0.0, flatten_radius, dist)
				var gx := cx + dx
				var gz := cz + dz
				if gx < 0 or gz < 0 or gx >= map_points or gz >= map_points:
					continue
				var i := gz * map_points + gx
				_heights[i] = lerpf(_heights[i], target, t)


func _flatten_targets() -> void:
	for spec in flatten_targets:
		var pos: Vector3 = spec["pos"]
		var radius := float(spec.get("radius", flatten_radius))
		var cx := int(round((pos.x / cell_size) + float(map_points - 1) * 0.5))
		var cz := int(round((pos.z / cell_size) + float(map_points - 1) * 0.5))
		# A NAN height means "the local terrain height here" — the target
		# relaxes toward the height sampled at its own center, exactly
		# like POI flattening (issue #122: the apex arena's center disc).
		var target := float(spec["height"])
		if is_nan(target):
			target = _sample_grid(cx, cz)
		var r := int(ceil(radius / cell_size))
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var dist := sqrt(float(dx * dx + dz * dz)) * cell_size
				if dist > radius:
					continue
				var t := 1.0 - smoothstep(0.0, radius, dist)
				var gx := cx + dx
				var gz := cz + dz
				if gx < 0 or gz < 0 or gx >= map_points or gz >= map_points:
					continue
				var i := gz * map_points + gx
				_heights[i] = lerpf(_heights[i], target, t)


func _carve_ponds() -> void:
	for pond in pond_centers:
		_carve_pond_at(pond, pond_radius)
	for spec in pond_specs:
		_carve_pond_at(spec["center"], float(spec["radius"]))


func _carve_pond_at(pond: Vector3, radius: float) -> void:
	var cx := int(round((pond.x / cell_size) + float(map_points - 1) * 0.5))
	var cz := int(round((pond.z / cell_size) + float(map_points - 1) * 0.5))
	var r := int(ceil(radius / cell_size))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var dist := sqrt(float(dx * dx + dz * dz)) * cell_size
			if dist > radius:
				continue
			var t := 1.0 - smoothstep(0.0, radius, dist)
			var gx := cx + dx
			var gz := cz + dz
			if gx < 0 or gz < 0 or gx >= map_points or gz >= map_points:
				continue
			var i := gz * map_points + gx
			_heights[i] = minf(_heights[i], water_level - pond_depth * t)


func _relax() -> void:
	var out := _heights.duplicate()
	for z in map_points:
		for x in map_points:
			var s := _sample_grid(x, z)
			s += _sample_grid(x + 1, z)
			s += _sample_grid(x - 1, z)
			s += _sample_grid(x, z + 1)
			s += _sample_grid(x, z - 1)
			out[z * map_points + x] = s / 5.0
	_heights = out


func _slope_at(x: int, z: int) -> float:
	var dx := (_sample_grid(x + 1, z) - _sample_grid(x - 1, z)) / (2.0 * cell_size)
	var dz := (_sample_grid(x, z + 1) - _sample_grid(x, z - 1)) / (2.0 * cell_size)
	return sqrt(dx * dx + dz * dz)


func _vertex_color(h: float, slope: float) -> Color:
	if h < water_level:
		return tint_bed # sand (or cave bed) under water
	var anchor := tint_anchor if not is_nan(tint_anchor) else water_level
	var t := clampf((h - anchor) / maxf(amplitude * 0.5, 0.01), 0.0, 1.0)
	var c := tint_low.lerp(tint_mid, clampf(t * 2.0, 0.0, 1.0))
	c = c.lerp(tint_high, clampf((t - 0.5) * 2.0, 0.0, 1.0))
	if slope > 0.9:
		c = tint_high.lerp(c, 0.3)
	return c


func _build_mesh() -> void:
	if _mesh_instance != null:
		_mesh_instance.queue_free()
	# Plain ArrayMesh path (no SurfaceTool): verts, normals from central
	# differences, uvs, vertex colors. Two triangles per quad: (0,1,2),(1,3,2).
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var debug_red := OS.get_cmdline_user_args().has("--debug-red")
	for z in range(map_points - 1):
		for x in range(map_points - 1):
			var quad := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x, z + 1), Vector2i(x + 1, z + 1)]
			for tri in [[0, 1, 2], [1, 3, 2]]:
				for k in tri:
					var q: Vector2i = quad[k]
					verts.append(_grid_vert(q.x, q.y))
					normals.append(_grid_normal(q.x, q.y))
					uvs.append(Vector2(float(q.x) / float(map_points - 1), float(q.y) / float(map_points - 1)))
					colors.append(Color(1, 0, 0) if debug_red else _vertex_color(_sample_grid(q.x, q.y), _slope_at(q.x, q.y)))
	# [QA] #124: perimeter skirt — appended AFTER the grid arrays, so
	# every grid vertex/normal/uv/color above stays bit-identical.
	_append_skirt(verts, normals, uvs, colors, debug_red)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	if not debug_red:
		mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	_mesh_instance.name = "TerrainMesh"
	add_child(_mesh_instance)


## [QA] #124: append a vertical skirt band around the sheet perimeter.
## For every boundary segment a quad hangs from the edge vertices down
## SKIRT_DEPTH. Both windings are emitted: the sheet material culls
## back faces, and the two in-play viewpoints see opposite sides of the
## band (inside the annex looking out / inside the arena looking at the
## door), so each side needs its own front face. Top-row colors are the
## edge grid vertices' own colors (no seam at the sheet edge); the
## bottom row darkens toward a soil/shadow tone. Appended only — the
## grid arrays built above are never touched.
func _append_skirt(verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, colors: PackedColorArray, debug_red: bool) -> void:
	var mp := map_points
	var edges: Array = []
	for x in range(mp - 1):
		edges.append([Vector2i(x, 0), Vector2i(x + 1, 0)]) # north row
		edges.append([Vector2i(x, mp - 1), Vector2i(x + 1, mp - 1)]) # south row
	for z in range(mp - 1):
		edges.append([Vector2i(0, z), Vector2i(0, z + 1)]) # west column
		edges.append([Vector2i(mp - 1, z), Vector2i(mp - 1, z + 1)]) # east column
	for seg in edges:
		var a: Vector2i = seg[0]
		var b: Vector2i = seg[1]
		var top_a := _grid_vert(a.x, a.y)
		var top_b := _grid_vert(b.x, b.y)
		var bot_a := top_a - Vector3(0.0, SKIRT_DEPTH, 0.0)
		var bot_b := top_b - Vector3(0.0, SKIRT_DEPTH, 0.0)
		var col_a := Color(1, 0, 0) if debug_red else _vertex_color(_sample_grid(a.x, a.y), _slope_at(a.x, a.y))
		var col_b := Color(1, 0, 0) if debug_red else _vertex_color(_sample_grid(b.x, b.y), _slope_at(b.x, b.y))
		var col_a_bot := col_a if debug_red else col_a.darkened(0.5)
		var col_b_bot := col_b if debug_red else col_b.darkened(0.5)
		# Winding 1 and its exact reverse (diagonal top_b–bot_a).
		_skirt_tri(verts, normals, uvs, colors, top_a, top_b, bot_a, col_a, col_b, col_a_bot)
		_skirt_tri(verts, normals, uvs, colors, top_b, bot_b, bot_a, col_b, col_b_bot, col_a_bot)
		_skirt_tri(verts, normals, uvs, colors, top_a, bot_a, top_b, col_a, col_a_bot, col_b)
		_skirt_tri(verts, normals, uvs, colors, top_b, bot_a, bot_b, col_b, col_a_bot, col_b_bot)


## Append one skirt triangle with a flat normal facing the side the
## triangle is visible from (Godot front faces wind clockwise, so the
## visible side is opposite the right-hand-rule normal — the same
## convention the grid triangles above rely on).
func _skirt_tri(verts: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, colors: PackedColorArray,
		p0: Vector3, p1: Vector3, p2: Vector3,
		c0: Color, c1: Color, c2: Color) -> void:
	var n := -(p1 - p0).cross(p2 - p0)
	n = n.normalized() if n.length() > 0.000001 else Vector3.DOWN
	verts.append(p0)
	verts.append(p1)
	verts.append(p2)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	uvs.append(Vector2.ZERO)
	uvs.append(Vector2.ZERO)
	uvs.append(Vector2.ZERO)
	colors.append(c0)
	colors.append(c1)
	colors.append(c2)


func _grid_vert(x: int, z: int) -> Vector3:
	return Vector3((float(x) - float(map_points - 1) * 0.5) * cell_size,
			_sample_grid(x, z),
			(float(z) - float(map_points - 1) * 0.5) * cell_size)


func _grid_normal(x: int, z: int) -> Vector3:
	var dx := (_sample_grid(x + 1, z) - _sample_grid(x - 1, z)) / (2.0 * cell_size)
	var dz := (_sample_grid(x, z + 1) - _sample_grid(x, z - 1)) / (2.0 * cell_size)
	return Vector3(-dx, 1.0, -dz).normalized()



func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := HeightMapShape3D.new()
	shape.map_width = map_points
	shape.map_depth = map_points
	shape.map_data = _heights.duplicate()
	var col := CollisionShape3D.new()
	col.shape = shape
	# HeightMapShape3D cells are 1 unit; scale x/z for larger cell sizes.
	col.scale = Vector3(cell_size, 1.0, cell_size)
	body.add_child(col)
	add_child(body)


func _build_water() -> void:
	if _water_mesh != null:
		_water_mesh.queue_free()
		_water_mesh = null
	# A plane fully below the terrain can never be seen in play — skip it
	# (dry flavors like the depths would otherwise show a rim under the
	# terrain slab in flyover views).
	if water_level <= _min_height:
		return
	var plane := PlaneMesh.new()
	var ext := half_extent() * 2.0
	plane.size = Vector2(ext, ext)
	_water_mesh = MeshInstance3D.new()
	_water_mesh.mesh = plane
	_water_mesh.position.y = water_level
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec4 shallow : source_color = vec4(0.25, 0.55, 0.72, 0.88);
uniform vec4 deep : source_color = vec4(0.10, 0.28, 0.48, 0.92);
void fragment() {
	float bands = sin(UV.x * 60.0 + TIME * 2.2) * sin(UV.y * 52.0 - TIME * 1.7);
	float shimmer = smoothstep(0.2, 0.95, bands);
	ALBEDO = mix(deep.rgb, shallow.rgb, shimmer * 0.55 + 0.2);
	ALPHA = mix(deep.a, shallow.a, shimmer * 0.5);
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	smat.set_shader_parameter("shallow", water_shallow)
	smat.set_shader_parameter("deep", water_deep)
	_water_mesh.material_override = smat
	_water_mesh.name = "WaterPlane"
	add_child(_water_mesh)
