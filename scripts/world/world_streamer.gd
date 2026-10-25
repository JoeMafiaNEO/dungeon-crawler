extends Node3D
## WorldStreamer (issues #197/#198): the scene side of the
## procedural world prototype. Keeps chunk nodes alive within
## LOAD_RADIUS of the target and unloads beyond UNLOAD_RADIUS,
## building at most BUILD_PER_FRAME chunks per step. A chunk is
## generated ONLY when the target enters proximity — nothing here
## pre-generates the world.
##
## #198 presentation rules (ChunkData stays pure/deterministic —
## all of this is scene-side state only):
## - Build priority: VisibleOnScreenNotifier3D scouts watch the
##   unbuilt desired chunks and built chunks carry their own
##   notifiers; reported-visible and near chunks win the build
##   budget, in-cone chunks next, reported-off-screen last but
##   ALWAYS drained eventually (no starvation holes).
## - Buildings materialize only for chunks within BUILDING_RADIUS
##   that are not reported hidden, and despawn after
##   BUILDING_DESPAWN_MSEC of sustained off-screen time (a tuning
##   placeholder). Terrain is the wide ring; buildings are the
##   near, visible ring.
##
## Per chunk node: one terrain mesh from the generator's height
## sampler (vertex colors mark road lots) + ONE MultiMeshInstance3D
## of a unit box for every building in the chunk (scaled to
## footprint x floors, per-instance color from the style index).
## Prototype visuals by design — Jesse is testing generation and
## culling, not art.

const LOAD_RADIUS := 8
const UNLOAD_RADIUS := 10
const BUILD_PER_FRAME := 2
const BUILDING_RADIUS := 3
const BUILDING_DESPAWN_MSEC := 5000 ## tuning placeholder (#198)
const CONE_COS := 0.4226 ## cos(65 deg): the view-cone priority band

const WorldGen := preload("res://scripts/world/world_gen.gd")
const ChunkData := preload("res://scripts/world/chunk_data.gd")
const BuildingGen := preload("res://scripts/world/building_gen.gd")

## Building palette by style index (ChunkData style 0..5).
const STYLE_COLORS: Array = [
	Color(0.72, 0.68, 0.62), Color(0.62, 0.58, 0.66),
	Color(0.70, 0.55, 0.45), Color(0.55, 0.62, 0.68),
	Color(0.66, 0.64, 0.50), Color(0.58, 0.52, 0.55),
]

var _target_node: Node3D = null
var _target_pos := Vector3.ZERO
var _has_target := false
## "cx,cz" -> {node, data, buildings (Node or null), off_since}
var _active := {}
## "cx,cz" -> Node3D scout (unbuilt chunks in the desired set)
var _scouts := {}
## "cx,cz" -> int visibility: 1 visible, 0 hidden, absent = unknown
var _vis := {}

## Issue #203 (P3): building construction inside this rect is
## suppressed (the reserved home-building plot around the reveal
## anchor). Build-layer only — the generator's deterministic data
## is never modified; the skip is a scene-side choice, identical
## on every peer because the rect derives from the same record.
var suppress_rect := Rect2()
var suppress_enabled := false

var _box_mesh: BoxMesh = null
var _building_mat: StandardMaterial3D = null
var _interior_mat: StandardMaterial3D = null
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


## Data-level state for pins: {built, has_buildings, vis}.
func debug_chunk_state(cx: int, cz: int) -> Dictionary:
	var k := _key(cx, cz)
	if not _active.has(k):
		return {"built": false, "has_buildings": false,
			"vis": int(_vis.get(k, -1))}
	var rec: Dictionary = _active[k]
	return {"built": true, "has_buildings": rec["buildings"] != null,
		"vis": int(_vis.get(k, -1)),
		"shell_pieces": int(rec.get("shell_pieces", 0)),
		"interior_pieces": int(rec.get("interior_pieces", 0))}


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


# ------------------------------------------------------------------
# Visibility reporting (notifier signals AND pins enter here).
# ------------------------------------------------------------------

func _note_visible(cx: int, cz: int) -> void:
	_vis[_key(cx, cz)] = 1
	if _active.has(_key(cx, cz)):
		_active[_key(cx, cz)]["off_since"] = -1


func _note_hidden(cx: int, cz: int, at_msec: int = -1) -> void:
	_vis[_key(cx, cz)] = 0
	var k := _key(cx, cz)
	if _active.has(k) and int(_active[k]["off_since"]) < 0:
		_active[k]["off_since"] = at_msec if at_msec >= 0 \
			else Time.get_ticks_msec()


func _view_forward() -> Vector3:
	if _target_node is Camera3D and is_instance_valid(_target_node):
		var f := -(_target_node as Camera3D).global_transform.basis.z
		f.y = 0
		return f.normalized() if f.length() > 0.01 else Vector3.ZERO
	return Vector3.ZERO


## Build priority as a comparable key: [tier, chebyshev, cx, cz].
## Tier 0: reported visible, or the near ring (about to be seen).
## Tier 1: inside the view cone. Tier 2: unknown. Tier 3: reported
## off-screen — last, but the queue always drains to it.
func _priority_key(cx: int, cz: int, tcx: int, tcz: int) -> Array:
	var cheb := maxi(absi(cx - tcx), absi(cz - tcz))
	var vis := int(_vis.get(_key(cx, cz), -1))
	var tier := 2
	if vis == 1 or cheb <= 2:
		tier = 0
	elif vis == 0:
		tier = 3
	else:
		var fwd := _view_forward()
		if fwd != Vector3.ZERO:
			var center := Vector2((float(cx) + 0.5) * WorldGen.CHUNK_SIZE,
				(float(cz) + 0.5) * WorldGen.CHUNK_SIZE)
			var to := center - Vector2(_target_pos.x, _target_pos.z)
			if to.length() < 1.0 or \
					to.normalized().dot(Vector2(fwd.x, fwd.z)) > CONE_COS:
				tier = 1
	return [tier, cheb, cx, cz]


# ------------------------------------------------------------------
# Streaming.
# ------------------------------------------------------------------

## One streaming step. `now_msec` is injectable so the building
## hysteresis is pinnable headlessly; -1 uses the real clock.
func update_streaming(now_msec: int = -1) -> void:
	if not _has_target:
		return
	var now := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	var tcx := int(floor(_target_pos.x / WorldGen.CHUNK_SIZE))
	var tcz := int(floor(_target_pos.z / WorldGen.CHUNK_SIZE))
	# Unload chunks beyond UNLOAD_RADIUS (immediate).
	for k in _active.keys():
		var parts := str(k).split(",")
		if maxi(absi(int(parts[0]) - tcx), absi(int(parts[1]) - tcz)) > UNLOAD_RADIUS:
			(_active[k]["node"] as Node).queue_free()
			_active.erase(k)
			_vis.erase(k)
	# Desired set + scouts for the unbuilt.
	var desired := {}
	for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			desired[_key(tcx + dx, tcz + dz)] = Vector2i(tcx + dx, tcz + dz)
	for k in _scouts.keys():
		if not desired.has(k) or _active.has(k):
			(_scouts[k] as Node).queue_free()
			_scouts.erase(k)
	for k in desired.keys():
		if not _active.has(k) and not _scouts.has(k):
			_make_scout(desired[k].x, desired[k].y)
	# Build queue by priority, budget BUILD_PER_FRAME.
	var missing: Array = []
	for k in desired.keys():
		if not _active.has(k):
			missing.append(desired[k])
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ka := _priority_key(a.x, a.y, tcx, tcz)
		var kb := _priority_key(b.x, b.y, tcx, tcz)
		for i in 4:
			if ka[i] != kb[i]:
				return ka[i] < kb[i]
		return false)
	for i in mini(BUILD_PER_FRAME, missing.size()):
		_build_chunk(missing[i].x, missing[i].y)
	_update_buildings(tcx, tcz, now)


## Buildings: materialize inside BUILDING_RADIUS when not reported
## hidden; despawn outside the ring or after BUILDING_DESPAWN_MSEC
## of sustained off-screen time.
func _update_buildings(tcx: int, tcz: int, now: int) -> void:
	var budget := 2
	for k in _active.keys():
		var parts := str(k).split(",")
		var cx := int(parts[0])
		var cz := int(parts[1])
		var rec: Dictionary = _active[k]
		var cheb := maxi(absi(cx - tcx), absi(cz - tcz))
		var vis := int(_vis.get(k, -1))
		var in_ring := cheb <= BUILDING_RADIUS
		var hidden_long := vis == 0 and int(rec["off_since"]) >= 0 \
			and now - int(rec["off_since"]) >= BUILDING_DESPAWN_MSEC
		if rec["buildings"] != null and (not in_ring or hidden_long):
			(rec["buildings"] as Node).queue_free()
			rec["buildings"] = null
			rec["shell_pieces"] = 0
			rec["interior_pieces"] = 0
		elif rec["buildings"] == null and in_ring and vis != 0 and budget > 0:
			rec["buildings"] = _make_buildings(rec)
			budget -= 1


func _make_scout(cx: int, cz: int) -> void:
	var node := Node3D.new()
	node.name = "Scout_%d_%d" % [cx, cz]
	node.position = Vector3((float(cx) + 0.5) * WorldGen.CHUNK_SIZE, 0,
		(float(cz) + 0.5) * WorldGen.CHUNK_SIZE)
	add_child(node)
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-68, -40, -68), Vector3(136, 160, 136))
	node.add_child(notifier)
	notifier.screen_entered.connect(_note_visible.bind(cx, cz))
	notifier.screen_exited.connect(_note_hidden.bind(cx, cz))
	_scouts[_key(cx, cz)] = node


func _build_chunk(cx: int, cz: int) -> void:
	_ensure_assets()
	var data := WorldGen.generate_chunk(cx, cz)
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [cx, cz]
	node.position = Vector3(float(cx) * WorldGen.CHUNK_SIZE, 0,
		float(cz) * WorldGen.CHUNK_SIZE)
	add_child(node)
	var terrain := MeshInstance3D.new()
	terrain.name = "Terrain"
	terrain.mesh = _terrain_mesh(data)
	node.add_child(terrain)
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-4, -40, -4), Vector3(136, 160, 136))
	node.add_child(notifier)
	notifier.screen_entered.connect(_note_visible.bind(cx, cz))
	notifier.screen_exited.connect(_note_hidden.bind(cx, cz))
	_active[_key(cx, cz)] = {"node": node, "data": data,
		"buildings": null, "off_since": -1, "plans": {},
		"shell_pieces": 0, "interior_pieces": 0}
	if _scouts.has(_key(cx, cz)):
		(_scouts[_key(cx, cz)] as Node).queue_free()
		_scouts.erase(_key(cx, cz))


## The chunk's buildings as ONE node holding two MultiMeshes
## (#199): shell pieces under the exterior window material,
## interior pieces under a plain material — every building in the
## chunk planned by BuildingGen from the CACHED ChunkData, plans
## themselves cached in the chunk record, so a despawn /
## rematerialize cycle rebuilds the identical structures.
func _make_buildings(rec: Dictionary) -> Node:
	var data: RefCounted = rec["data"]
	if data.buildings.is_empty():
		return null
	var node := Node3D.new()
	node.name = "Buildings"
	(rec["node"] as Node).add_child(node)
	var cx: int = data.cx
	var cz: int = data.cz
	var shell_xforms: Array = []
	var shell_colors: Array = []
	var int_xforms: Array = []
	for b in data.buildings:
		var lx := int(b[0])
		var lz := int(b[1])
		var floors := int(b[2])
		var style := int(b[3])
		var span_x := int(b[4]) if b.size() > 4 else 1
		var span_z := int(b[5]) if b.size() > 5 else 1
		var massing := int(b[6]) if b.size() > 6 else 0
		if suppress_enabled:
			# The building's world lot rect vs the reserved plot
			# (issue #203): an intersecting building never builds.
			var brect := Rect2(
				Vector2(float(cx * 16 + lx), float(cz * 16 + lz)) * WorldGen.LOT_SIZE,
				Vector2(float(span_x), float(span_z)) * WorldGen.LOT_SIZE)
			if suppress_rect.intersects(brect):
				continue
		var pkey := "%d,%d" % [lx, lz]
		var plans: Dictionary = rec["plans"]
		if not plans.has(pkey):
			plans[pkey] = BuildingGen.plan_for(WorldGen.WORLD_SEED,
				cx * 16 + lx, cz * 16 + lz, floors, style,
				span_x, span_z, massing)
		var plan: Dictionary = plans[pkey]
		# The plan is centered on the merged span's center (#200):
		# the anchor lot is the span's min corner, so the origin
		# shifts half the extra lots in +x/+z, and the ground is
		# sampled at the span center.
		var wx := (float(cx * 16 + lx) + float(span_x) * 0.5) * WorldGen.LOT_SIZE
		var wz := (float(cz * 16 + lz) + float(span_z) * 0.5) * WorldGen.LOT_SIZE
		var ground := WorldGen.height_at(WorldGen.WORLD_SEED, wx, wz)
		var origin := Vector3(
			(float(lx) + float(span_x) * 0.5) * WorldGen.LOT_SIZE, ground,
			(float(lz) + float(span_z) * 0.5) * WorldGen.LOT_SIZE)
		for p in plan["pieces"]:
			var xf := Transform3D(Basis.from_scale(p["s"]), origin + (p["c"] as Vector3))
			if bool(p["shell"]):
				shell_xforms.append(xf)
				shell_colors.append(STYLE_COLORS[style % STYLE_COLORS.size()])
			else:
				int_xforms.append(xf)
	rec["shell_pieces"] = shell_xforms.size()
	rec["interior_pieces"] = int_xforms.size()
	if not shell_xforms.is_empty():
		node.add_child(_piece_multimesh(shell_xforms, shell_colors, _building_mat))
	if not int_xforms.is_empty():
		var whites: Array = []
		for i in int_xforms.size():
			whites.append(Color.WHITE)
		node.add_child(_piece_multimesh(int_xforms, whites, _interior_mat))
	return node


func _piece_multimesh(xforms: Array, colors: Array, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _box_mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


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
			# Winding (#198): clockwise seen from above, matching the
			# engine's own upward faces — the previous [a, c, b] /
			# [b, c, d] order was backface-culled from above.
			indices.append_array([a, b, c, b, d, c])
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
	_interior_mat = StandardMaterial3D.new()
	_interior_mat.albedo_color = Color(0.84, 0.80, 0.74)
	_interior_mat.roughness = 1.0


## A ONE-FLOOR window band (#199; contrast bumped #200): shell
## pieces are single-story boxes, so each carries one row of
## windows and a tower reads as stacked stories from outside.
## The #199 acceptance found the band averaged out pale at
## distance — the windows are TALLER and the glass DARKER now,
## with a structural band above and below the row, so the
## features survive mip averaging from the air.
func _window_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.84, 0.80, 0.74))
	for y in range(6, 12):
		for x in 64:
			img.set_pixel(x, y, Color(0.52, 0.49, 0.45))
	for y in range(52, 58):
		for x in 64:
			img.set_pixel(x, y, Color(0.52, 0.49, 0.45))
	for wx_i in 4:
		var lit := wx_i % 3 != 0
		var c := Color(0.07, 0.09, 0.16) if not lit else Color(0.98, 0.88, 0.62)
		for y in range(14, 50):
			for x in range(wx_i * 16 + 3, wx_i * 16 + 13):
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
