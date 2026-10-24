extends Node3D
## WorldStreamer (issue #197): the scene side of the procedural
## world prototype. Keeps chunk nodes alive within LOAD_RADIUS of
## the target and unloads beyond UNLOAD_RADIUS, building at most
## BUILD_PER_FRAME chunks per step, nearest first. A chunk is
## generated ONLY when the target enters proximity — nothing here
## pre-generates the world.
##
## Per chunk node: one terrain mesh from the generator's height
## sampler (vertex colors mark road lots) + ONE MultiMeshInstance3D
## of a unit box for every building in the chunk (scaled to
## footprint x floors, per-instance color from the style index).
## Prototype visuals by design — Jesse is testing generation and
## culling, not art.

const LOAD_RADIUS := 6
const UNLOAD_RADIUS := 8
const BUILD_PER_FRAME := 2

const WorldGen := preload("res://scripts/world/world_gen.gd")
const ChunkData := preload("res://scripts/world/chunk_data.gd")

## Building palette by style index (ChunkData style 0..5).
const STYLE_COLORS: Array = [
	Color(0.72, 0.68, 0.62), Color(0.62, 0.58, 0.66),
	Color(0.70, 0.55, 0.45), Color(0.55, 0.62, 0.68),
	Color(0.66, 0.64, 0.50), Color(0.58, 0.52, 0.55),
]

var _target_node: Node3D = null
var _target_pos := Vector3.ZERO
var _has_target := false
var _active := {} ## "cx,cz" -> Node3D

var _box_mesh: BoxMesh = null
var _building_mat: StandardMaterial3D = null
var _terrain_mat: StandardMaterial3D = null


## Pins + the test scene drive the target through here (the scene
## also resolves a "fly_rig" group member automatically).
func set_target_position(pos: Vector3) -> void:
	_target_pos = pos
	_has_target = true


func set_target_node(n: Node3D) -> void:
	_target_node = n
	if n != null:
		_has_target = true


func active_chunks() -> Array:
	var out: Array = []
	for k in _active.keys():
		var parts := str(k).split(",")
		out.append(Vector2i(int(parts[0]), int(parts[1])))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


func _process(_delta: float) -> void:
	if _target_node == null:
		var rig := get_tree().get_first_node_in_group("fly_rig")
		if rig is Node3D:
			_target_node = rig
	if _target_node != null and is_instance_valid(_target_node):
		_target_pos = _target_node.global_position
		_has_target = true
	if _has_target:
		update_streaming()


func _key(cx: int, cz: int) -> String:
	return "%d,%d" % [cx, cz]


## One streaming step: unload beyond UNLOAD_RADIUS (immediate),
## then build up to BUILD_PER_FRAME missing chunks inside
## LOAD_RADIUS, nearest first.
func update_streaming() -> void:
	if not _has_target:
		return
	var tcx := int(floor(_target_pos.x / WorldGen.CHUNK_SIZE))
	var tcz := int(floor(_target_pos.z / WorldGen.CHUNK_SIZE))
	for k in _active.keys():
		var parts := str(k).split(",")
		var cx := int(parts[0])
		var cz := int(parts[1])
		if maxi(absi(cx - tcx), absi(cz - tcz)) > UNLOAD_RADIUS:
			(_active[k] as Node).queue_free()
			_active.erase(k)
	var missing: Array = []
	for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var cx := tcx + dx
			var cz := tcz + dz
			if not _active.has(_key(cx, cz)):
				missing.append(Vector2i(cx, cz))
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x - tcx), absi(a.y - tcz))
		var db := maxi(absi(b.x - tcx), absi(b.y - tcz))
		if da != db:
			return da < db
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	for i in mini(BUILD_PER_FRAME, missing.size()):
		_build_chunk(missing[i].x, missing[i].y)


func _build_chunk(cx: int, cz: int) -> void:
	_ensure_assets()
	var data := WorldGen.generate_chunk(cx, cz)
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [cx, cz]
	node.position = Vector3(float(cx) * WorldGen.CHUNK_SIZE, 0,
		float(cz) * WorldGen.CHUNK_SIZE)
	add_child(node)
	_active[_key(cx, cz)] = node
	# --- terrain ---
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = _terrain_mesh(data)
	node.add_child(terrain)
	# --- buildings: ONE MultiMesh of a unit box ---
	if not data.buildings.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _box_mesh
		mm.instance_count = data.buildings.size()
		for i in data.buildings.size():
			var b: Array = data.buildings[i]
			var lx := int(b[0])
			var lz := int(b[1])
			var floors := int(b[2])
			var style := int(b[3])
			var wx := (float(cx * 16 + lx) + 0.5) * WorldGen.LOT_SIZE
			var wz := (float(cz * 16 + lz) + 0.5) * WorldGen.LOT_SIZE
			var ground := WorldGen.height_at(WorldGen.WORLD_SEED, wx, wz)
			var h := float(floors) * WorldGen.FLOOR_HEIGHT
			var basis := Basis.from_scale(Vector3(6.4, h, 6.4))
			var origin := Vector3((float(lx) + 0.5) * WorldGen.LOT_SIZE,
				ground + h * 0.5, (float(lz) + 0.5) * WorldGen.LOT_SIZE)
			mm.set_instance_transform(i, Transform3D(basis, origin))
			mm.set_instance_color(i, STYLE_COLORS[style % STYLE_COLORS.size()])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Buildings"
		mmi.multimesh = mm
		mmi.material_override = _building_mat
		node.add_child(mmi)


func _terrain_mesh(data: RefCounted) -> ArrayMesh:
	var n := WorldGen.LOTS_PER_CHUNK + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var heights: PackedFloat32Array = data.heights
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	for iz in n:
		for ix in n:
			var idx := iz * n + ix
			var h := heights[idx]
			verts[idx] = Vector3(float(ix) * WorldGen.LOT_SIZE, h,
				float(iz) * WorldGen.LOT_SIZE)
			# Normal from central differences of the height grid.
			var hl := heights[iz * n + maxi(ix - 1, 0)]
			var hr := heights[iz * n + mini(ix + 1, n - 1)]
			var hd := heights[maxi(iz - 1, 0) * n + ix]
			var hu := heights[mini(iz + 1, n - 1) * n + ix]
			normals[idx] = Vector3(hl - hr, 2.0 * WorldGen.LOT_SIZE,
				hd - hu).normalized()
			# Vertex color: the lot this corner belongs to (road lots
			# read as asphalt), else a height-tinted grass.
			var lx := mini(ix, WorldGen.LOTS_PER_CHUNK - 1)
			var lz := mini(iz, WorldGen.LOTS_PER_CHUNK - 1)
			match data.lot_class(lx, lz):
				ChunkData.ROAD:
					colors[idx] = Color(0.16, 0.16, 0.17)
				ChunkData.PLAZA:
					colors[idx] = Color(0.45, 0.42, 0.38)
				ChunkData.GREEN:
					colors[idx] = Color(0.22, 0.44, 0.18)
				_:
					var t := clampf((h + 24.0) / 48.0, 0.0, 1.0)
					colors[idx] = Color(0.24 + 0.10 * t, 0.42, 0.20)
	var indices := PackedInt32Array()
	for iz in WorldGen.LOTS_PER_CHUNK:
		for ix in WorldGen.LOTS_PER_CHUNK:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _terrain_mat)
	return mesh


func _ensure_assets() -> void:
	if _box_mesh != null:
		return
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.roughness = 1.0
	_building_mat = StandardMaterial3D.new()
	_building_mat.albedo_texture = _window_texture()
	_building_mat.roughness = 0.9


## A window-band texture: rows of lit/unlit windows give the
## multi-story read on the unit-box instances.
func _window_texture() -> ImageTexture:
	var img := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.92, 0.90, 0.86))
	for floor_i in 16:
		for wx_i in 4:
			var lit := (floor_i * 7 + wx_i * 13) % 3 != 0
			var c := Color(0.15, 0.18, 0.25) if not lit else Color(0.85, 0.78, 0.55)
			for y in range(floor_i * 16 + 4, floor_i * 16 + 12):
				for x in range(wx_i * 16 + 3, wx_i * 16 + 13):
					img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
