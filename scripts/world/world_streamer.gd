extends Node3D
## WorldStreamer (issues #197/#198): the scene side of the
## procedural world prototype. Keeps chunk nodes alive within
## the load radius of the target and unloads beyond it,
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

## Issue #219 (Jesse's order): the terrain ring radius is
## a player setting - the main menu's "Chunk load distance"
## slider, persisted via SaveManager settings
## (world/load_radius). Read ONCE here at world init; the
## unload ring is DERIVED (load + 2), never a second
## control. The vars carry the default so an untreed
## streamer behaves as the default too.
const MIN_LOAD_RADIUS := 2
const MAX_LOAD_RADIUS := 8
const DEFAULT_LOAD_RADIUS := 2
var load_radius: int = DEFAULT_LOAD_RADIUS
var unload_radius: int = DEFAULT_LOAD_RADIUS + 2
const BUILD_PER_FRAME := 2
const BUILDING_RADIUS := 3
const BUILDING_DESPAWN_MSEC := 5000 ## tuning placeholder (#198)
const CONE_COS := 0.4226 ## cos(65 deg): the view-cone priority band

const WorldGen := preload("res://scripts/world/world_gen.gd")
const ChunkData := preload("res://scripts/world/chunk_data.gd")
const BuildingGen := preload("res://scripts/world/building_gen.gd")
const BuildingSelect := preload("res://scripts/world/building_select.gd")
const ScatterGen := preload("res://scripts/world/scatter_gen.gd")
const TransferTrigger := preload("res://scripts/world/transfer_trigger.gd")

## Issue #204 (P4): Kenney nature pack, one mesh per scatter
## type ("shipped scales" — instance scale jitters around 1).
const SCATTER_MODELS := {
	"oak": "res://assets/models/kenney/nature/tree_oak.glb",
	"detailed": "res://assets/models/kenney/nature/tree_detailed.glb",
	"pine": "res://assets/models/kenney/nature/tree_cone.glb",
	"rock_big": "res://assets/models/kenney/nature/rock_largeA.glb",
	"rock_small": "res://assets/models/kenney/nature/rock_smallA.glb",
	"grass": "res://assets/models/kenney/nature/grass.glb",
	"mushroom": "res://assets/models/kenney/nature/mushroom_red.glb",
	"fence": "res://assets/models/kenney/nature/fence_simple.glb",
}

## Building palette by style index (ChunkData style 0..5).
const STYLE_COLORS: Array = [
	Color(0.72, 0.68, 0.62), Color(0.62, 0.58, 0.66),
	Color(0.70, 0.55, 0.45), Color(0.55, 0.62, 0.68),
	Color(0.66, 0.64, 0.50), Color(0.58, 0.52, 0.55),
]

## Issue #208: facade variance streams (hash discriminators
## on the universal WORLD_SEED, like every other stream).
const SALT_TINT := 4201 ## per-building hue/sat/value roll
const SALT_BAND := 4202 ## per-floor band (salt + floor)
const SALT_TEXV := 4203 ## per-building texture variant


## Issue #208: one building's facade color on one floor —
## the style palette color rolled within a bounded arc
## (hue ±0.025, saturation ±0.06, value ±0.07) by the
## building's own hash stream, then rippled per floor
## (value × [0.94, 1.03]) so the banding breaks up. A pure
## function of (seed, building, style, floor): the same
## building wears the same face on every peer.
static func facade_color(seed: int, wlx: int, wlz: int,
		style: int, floor_idx: int) -> Color:
	var base: Color = STYLE_COLORS[style % STYLE_COLORS.size()]
	var h := base.h + (WorldGen.rand01(seed, wlx, wlz,
		SALT_TINT) - 0.5) * 0.05
	var s := clampf(base.s + (WorldGen.rand01(seed, wlx,
		wlz, SALT_TINT + 1) - 0.5) * 0.12, 0.0, 1.0)
	var v := clampf(base.v + (WorldGen.rand01(seed, wlx,
		wlz, SALT_TINT + 2) - 0.5) * 0.14, 0.0, 1.0)
	v *= 0.94 + 0.09 * WorldGen.rand01(seed, wlx, wlz,
		SALT_BAND + floor_idx)
	return Color.from_hsv(h, s, clampf(v, 0.0, 1.0))


## Issue #208: which of the six texture variants (three
## window-grid phases × the shipped texture and its
## 180°-rotated twin) a building wears.
static func facade_variant(seed: int, wlx: int, wlz: int) -> int:
	return mini(5, int(WorldGen.rand01(seed, wlx, wlz,
		SALT_TEXV) * 6.0))


## A shell piece's floor, from its center height (wall
## centers sit at floor * PITCH + WALL_H/2; plates ride the
## floor boundaries) — the band the facade color reads.
static func facade_floor(c: Vector3, floors: int) -> int:
	return clampi(int(floor(c.y / 3.0)), 0, maxi(0, floors - 1))

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
var _building_mats: Array = [] ## #208: the six facade variants
var _interior_mat: StandardMaterial3D = null
var _terrain_mat: StandardMaterial3D = null
var _door_mat: StandardMaterial3D = null
var _scatter_meshes := {}


## Issue #204 (P4): is the chunk FULLY built — terrain,
## buildings and scatter — for the world-entry ready-gate.
## (A chunk with no buildings still counts once its detail
## pass has run; the pass is what the gate waits on.)
func chunk_fully_built(cx: int, cz: int) -> bool:
	var k := _key(cx, cz)
	if not _active.has(k):
		return false
	var rec: Dictionary = _active[k]
	return bool(rec.get("detail_done", false))


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
		"interior_pieces": int(rec.get("interior_pieces", 0)),
		"collision_shapes": int(rec.get("collision_shapes", 0)),
		"scatter_count": int(rec.get("scatter_count", 0)),
		"playable_doors": int(rec.get("playable_doors", 0)),
		"solid_buildings": int(rec.get("solid_buildings", 0))}


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
func _ready() -> void:
	var v := int(SaveManager.get_setting("world",
		"load_radius", DEFAULT_LOAD_RADIUS))
	load_radius = clampi(v, MIN_LOAD_RADIUS,
		MAX_LOAD_RADIUS)
	unload_radius = load_radius + 2


func update_streaming(now_msec: int = -1) -> void:
	if not _has_target:
		return
	var now := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	var tcx := int(floor(_target_pos.x / WorldGen.CHUNK_SIZE))
	var tcz := int(floor(_target_pos.z / WorldGen.CHUNK_SIZE))
	# Unload chunks beyond the unload ring (immediate).
	for k in _active.keys():
		var parts := str(k).split(",")
		if maxi(absi(int(parts[0]) - tcx), absi(int(parts[1]) - tcz)) > unload_radius:
			(_active[k]["node"] as Node).queue_free()
			_active.erase(k)
			_vis.erase(k)
	# Desired set + scouts for the unbuilt.
	var desired := {}
	for dx in range(-load_radius, load_radius + 1):
		for dz in range(-load_radius, load_radius + 1):
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
		# The detail pass is DONE when detail_done is set —
		# NOT when a Buildings node exists: a building-free
		# chunk's _make_buildings legitimately returns null,
		# and keying completion on the node would re-run the
		# whole pass (scatter included) every tick for such
		# chunks — starving the rest of the ring of detail
		# budget and leaking the rebuilt scatter nodes.
		# (Found by the #204 entry ready-gate pin.)
		if bool(rec.get("detail_done", false)) \
				and (not in_ring or hidden_long):
			if rec["buildings"] != null:
				(rec["buildings"] as Node).queue_free()
				rec["buildings"] = null
			rec["shell_pieces"] = 0
			rec["interior_pieces"] = 0
			rec["collision_shapes"] = 0
			rec["scatter_count"] = 0
			rec["playable_doors"] = 0
			rec["solid_buildings"] = 0
			if rec.get("scatter") != null:
				(rec["scatter"] as Node).queue_free()
				rec["scatter"] = null
			rec["detail_done"] = false
		elif not bool(rec.get("detail_done", false)) \
				and in_ring and vis != 0 and budget > 0:
			rec["buildings"] = _make_buildings(rec)
			rec["scatter"] = _make_scatter(rec)
			rec["detail_done"] = true
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
	# Issue #204 (P4): the terrain collides — a heightfield
	# shape over the chunk's own height grid, so the world is
	# walkable (in P3's rooftop vista this body sits 18 m under
	# the slab and is never touched; in the world scene it IS
	# the ground).
	var tbody := StaticBody3D.new()
	tbody.name = "TerrainCollision"
	tbody.collision_layer = 1
	tbody.collision_mask = 0
	var tshape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = WorldGen.LOTS_PER_CHUNK + 1
	hm.map_depth = WorldGen.LOTS_PER_CHUNK + 1
	hm.map_data = data.heights
	tshape.shape = hm
	tshape.scale = Vector3(WorldGen.LOT_SIZE, 1.0,
		WorldGen.LOT_SIZE)
	tshape.position = Vector3(WorldGen.CHUNK_SIZE * 0.5, 0,
		WorldGen.CHUNK_SIZE * 0.5)
	tbody.add_child(tshape)
	node.add_child(tbody)
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-4, -40, -4), Vector3(136, 160, 136))
	node.add_child(notifier)
	notifier.screen_entered.connect(_note_visible.bind(cx, cz))
	notifier.screen_exited.connect(_note_hidden.bind(cx, cz))
	_active[_key(cx, cz)] = {"node": node, "data": data,
		"buildings": null, "scatter": null, "off_since": -1,
		"plans": {}, "shell_pieces": 0, "interior_pieces": 0,
		"collision_shapes": 0, "scatter_count": 0,
		"playable_doors": 0, "solid_buildings": 0,
		"detail_done": false}
	if _scouts.has(_key(cx, cz)):
		(_scouts[_key(cx, cz)] as Node).queue_free()
		_scouts.erase(_key(cx, cz))


## The chunk's buildings as ONE node (issue #199's MultiMesh
## batching, amended by #204): SHELLS ONLY — no building's
## interior is ever assembled in-world (interiors live behind
## P5's transfers); the plan still derives in full and the
## assembly filters to shell pieces. Every building also gets
## piece-derived collision (one StaticBody3D per building,
## one box shape per shell piece — the shipped overlap hazard
## closes: buildings are solid now). The selection roll
## (BuildingSelect) decides the door: PLAYABLE buildings keep
## the plan's door gap and gain a door slab + the P5
## transfer-trigger stub at their doorstep; EMPTY buildings
## get a filler piece over the gap and build SOLID — no gap,
## no door, no trigger. Plans are cached in the chunk record,
## so a despawn / rematerialize cycle rebuilds the identical
## structures.
func _make_buildings(rec: Dictionary) -> Node:
	var data: RefCounted = rec["data"]
	if data.buildings.is_empty():
		return null
	var node := Node3D.new()
	node.name = "Buildings"
	(rec["node"] as Node).add_child(node)
	var cx: int = data.cx
	var cz: int = data.cz
	var shell_buckets := {}
	var shell_total := 0
	var door_xforms: Array = []
	var collision_shapes := 0
	var playable_doors := 0
	var solid_buildings := 0
	for b in data.buildings:
		var lx := int(b[0])
		var lz := int(b[1])
		var floors := int(b[2])
		var style := int(b[3])
		var span_x := int(b[4]) if b.size() > 4 else 1
		var span_z := int(b[5]) if b.size() > 5 else 1
		var massing := int(b[6]) if b.size() > 6 else 0
		var wlx := cx * 16 + lx
		var wlz := cz * 16 + lz
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
		var playable := BuildingSelect.is_playable(
			WorldGen.WORLD_SEED, wlx, wlz)
		var door := BuildingGen.door_world(plan, origin)
		var body := StaticBody3D.new()
		body.name = "Collision_%d_%d" % [lx, lz]
		body.collision_layer = 1
		body.collision_mask = 0
		node.add_child(body)
		var variant := facade_variant(WorldGen.WORLD_SEED,
			wlx, wlz)
		for p in plan["pieces"]:
			if not bool(p["shell"]):
				continue
			var xf := Transform3D(Basis.from_scale(p["s"]), origin + (p["c"] as Vector3))
			_bucket_add(shell_buckets, variant, xf,
				facade_color(WorldGen.WORLD_SEED, wlx, wlz,
					style, facade_floor(p["c"], floors)))
			shell_total += 1
			_add_box_shape(body, xf)
			collision_shapes += 1
		# The door beat: a slab in the gap (playable) or a
		# filler over it (empty — the wall reads solid). Either
		# way the doorway collides in P4: no interiors exist
		# yet to walk into.
		var gap_c: Vector3 = door["gap_center"]
		var wall := int(door["wall"])
		var slab_size := Vector3(BuildingGen.DOOR_W,
			BuildingGen.DOOR_H, BuildingGen.WALL_T) if wall < 2 \
			else Vector3(BuildingGen.WALL_T, BuildingGen.DOOR_H,
				BuildingGen.DOOR_W)
		var slab_xf := Transform3D(Basis.from_scale(slab_size),
			gap_c + Vector3(0, BuildingGen.DOOR_H * 0.5, 0))
		_add_box_shape(body, slab_xf)
		collision_shapes += 1
		if playable:
			playable_doors += 1
			door_xforms.append(Transform3D(
				Basis.from_scale(slab_size * Vector3(1, 1, 0.3)),
				slab_xf.origin - (door["normal"] as Vector3) * 0.05))
			var step_local: Vector3 = door["doorstep"]
			var step_world := Vector3(float(cx)
				* WorldGen.CHUNK_SIZE, 0, float(cz)
				* WorldGen.CHUNK_SIZE) + step_local + position
			var trig := TransferTrigger.new()
			trig.name = "TransferTrigger_%d_%d" % [lx, lz]
			trig.building_key = "%d,%d" % [wlx, wlz]
			trig.doorstep = step_world
			trig.record = {"key": trig.building_key,
				"floors": floors, "style": style,
				"span_x": span_x, "span_z": span_z,
				"massing": massing, "playable": true,
				"doorstep": [step_world.x, step_world.y,
					step_world.z]}
			trig.position = step_local
			trig.monitoring = false
			trig.add_to_group("transfer_trigger")
			var tshape := CollisionShape3D.new()
			var tbox := BoxShape3D.new()
			tbox.size = Vector3(2.6, 2.6, 2.6)
			tshape.shape = tbox
			tshape.position = Vector3(0, 1.1, 0)
			trig.add_child(tshape)
			node.add_child(trig)
		else:
			solid_buildings += 1
			_bucket_add(shell_buckets, variant, slab_xf,
				facade_color(WorldGen.WORLD_SEED, wlx, wlz,
					style, 0))
			shell_total += 1
	rec["shell_pieces"] = shell_total
	rec["interior_pieces"] = 0
	rec["collision_shapes"] = collision_shapes
	rec["playable_doors"] = playable_doors
	rec["solid_buildings"] = solid_buildings
	for v in shell_buckets:
		var pair: Array = shell_buckets[v]
		node.add_child(_piece_multimesh(pair[0], pair[1],
			_building_mats[v]))
	if not door_xforms.is_empty():
		var whites: Array = []
		for i in door_xforms.size():
			whites.append(Color.WHITE)
		node.add_child(_piece_multimesh(door_xforms, whites,
			_door_mat))
	return node


## Issue #204 (P4): assemble ONE building standalone, in the
## caller's frame at `origin` — the home building on the
## reveal's reserved plot, which the chunk system suppresses
## and the world root therefore builds itself. The same
## shells-only / collision / door treatment as a chunk
## building (the chunk path batches across buildings for
## draw calls; this path serves a single building). Returns
## the node; the caller adds it.
func build_standalone_building(plan: Dictionary,
		origin: Vector3, playable: bool, key: String) -> Node3D:
	_ensure_assets()
	var style := int(plan["style"])
	var node := Node3D.new()
	node.name = "Building_" + key.replace(",", "_")
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	var kp := key.split(",")
	var kwx := int(kp[0]) if kp.size() == 2 else 0
	var kwz := int(kp[1]) if kp.size() == 2 else 0
	var variant := facade_variant(WorldGen.WORLD_SEED, kwx, kwz)
	var shell_buckets := {}
	for p in plan["pieces"]:
		if not bool(p["shell"]):
			continue
		var xf := Transform3D(Basis.from_scale(p["s"]),
			origin + (p["c"] as Vector3))
		_bucket_add(shell_buckets, variant, xf,
			facade_color(WorldGen.WORLD_SEED, kwx, kwz, style,
				facade_floor(p["c"], int(plan["floors"]))))
		_add_box_shape(body, xf)
	var door := BuildingGen.door_world(plan, origin)
	var gap_c: Vector3 = door["gap_center"]
	var wall := int(door["wall"])
	var slab_size := Vector3(BuildingGen.DOOR_W,
		BuildingGen.DOOR_H, BuildingGen.WALL_T) if wall < 2 \
		else Vector3(BuildingGen.WALL_T, BuildingGen.DOOR_H,
			BuildingGen.DOOR_W)
	var slab_xf := Transform3D(Basis.from_scale(slab_size),
		gap_c + Vector3(0, BuildingGen.DOOR_H * 0.5, 0))
	_add_box_shape(body, slab_xf)
	if playable:
		var door_xf := Transform3D(Basis.from_scale(
			slab_size * Vector3(1, 1, 0.3)),
			slab_xf.origin - (door["normal"] as Vector3) * 0.05)
		node.add_child(_piece_multimesh([door_xf], [Color.WHITE],
			_door_mat))
		var step: Vector3 = door["doorstep"]
		var trig := TransferTrigger.new()
		trig.name = "TransferTrigger"
		trig.building_key = key
		trig.doorstep = step
		trig.record = {"key": key,
			"floors": int(plan["floors"]), "style": style,
			"span_x": int(plan["span_x"]),
			"span_z": int(plan["span_z"]),
			"massing": int(plan["massing"]), "playable": true,
			"doorstep": [step.x, step.y, step.z]}
		trig.position = step
		trig.monitoring = false
		trig.add_to_group("transfer_trigger")
		var tshape := CollisionShape3D.new()
		var tbox := BoxShape3D.new()
		tbox.size = Vector3(2.6, 2.6, 2.6)
		tshape.shape = tbox
		tshape.position = Vector3(0, 1.1, 0)
		trig.add_child(tshape)
		node.add_child(trig)
	else:
		_bucket_add(shell_buckets, variant, slab_xf,
			facade_color(WorldGen.WORLD_SEED, kwx, kwz, style,
				0))
	for v in shell_buckets:
		var pair: Array = shell_buckets[v]
		node.add_child(_piece_multimesh(pair[0], pair[1],
			_building_mats[v]))
	return node


## One collision box on a building body, from a piece transform
## (the building-piece collision path — scatter's collidables
## use the same helper).
func _add_box_shape(body: StaticBody3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = xf.basis.get_scale()
	cs.shape = box
	cs.transform = xf
	body.add_child(cs)


## Issue #204 (P4): the chunk's nature scatter — MultiMesh per
## asset type from ScatterGen's pure output, plus collision
## for the collidable kinds (N6: large trees + big rocks on
## the building-piece path; grass / mushrooms / fences /
## small rocks are visual-only). Spill rects come from the
## west / north neighbors' buildings (their +x/+z spans can
## cross into this chunk) when those chunks are loaded.
func _make_scatter(rec: Dictionary) -> Node:
	_ensure_assets()
	var data: RefCounted = rec["data"]
	var cx: int = data.cx
	var cz: int = data.cz
	var spill: Array = []
	for off in [Vector2i(-1, 0), Vector2i(0, -1),
			Vector2i(-1, -1)]:
		var nk := _key(cx + off.x, cz + off.y)
		if not _active.has(nk):
			continue
		var ndata: RefCounted = _active[nk]["data"]
		for b in ndata.buildings:
			var bx := float((cx + off.x) * 16 + int(b[0])) \
				* WorldGen.LOT_SIZE
			var bz := float((cz + off.y) * 16 + int(b[1])) \
				* WorldGen.LOT_SIZE
			spill.append(Rect2(bx - 0.6, bz - 0.6,
				float(int(b[4])) * WorldGen.LOT_SIZE + 1.2,
				float(int(b[5])) * WorldGen.LOT_SIZE + 1.2))
	if suppress_enabled:
		spill.append(Rect2(suppress_rect.position - Vector2(0.6,
			0.6), suppress_rect.size + Vector2(1.2, 1.2)))
	var scatter := ScatterGen.scatter_for_chunk(
		WorldGen.WORLD_SEED, cx, cz, data, spill)
	var node := Node3D.new()
	node.name = "Scatter"
	(rec["node"] as Node).add_child(node)
	var chunk_origin := Vector3(float(cx) * WorldGen.CHUNK_SIZE,
		0, float(cz) * WorldGen.CHUNK_SIZE)
	var body := StaticBody3D.new()
	body.name = "ScatterCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	var shapes := 0
	var total := 0
	for t in ScatterGen.TYPES:
		var items: Array = scatter[t]
		if items.is_empty():
			continue
		total += items.size()
		var mesh: Mesh = _scatter_meshes.get(t)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = items.size()
		for i in items.size():
			var it: Dictionary = items[i]
			var local := (it["p"] as Vector3) - chunk_origin
			var basis := Basis(Vector3.UP, float(it["r"])) \
				.scaled(Vector3.ONE * float(it["s"]))
			mm.set_instance_transform(i, Transform3D(basis,
				local))
			if t == "oak" or t == "detailed" or t == "pine":
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cyl.radius = 0.35
				cyl.height = 2.2
				cs.shape = cyl
				cs.position = local + Vector3(0, 1.1, 0)
				body.add_child(cs)
				shapes += 1
			elif t == "rock_big":
				_add_box_shape(body, Transform3D(
					Basis.from_scale(Vector3(1.6, 1.2, 1.6)
						* float(it["s"])),
					local + Vector3(0, 0.5, 0)))
				shapes += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		node.add_child(mmi)
	rec["scatter_count"] = total
	rec["collision_shapes"] = int(rec.get("collision_shapes", 0)) \
		+ shapes
	return node


## Issue #208: accumulate a shell piece into its texture
## variant's batch (xforms + colors kept parallel).
func _bucket_add(buckets: Dictionary, variant: int,
		xf: Transform3D, col: Color) -> void:
	if not buckets.has(variant):
		buckets[variant] = [[], []]
	(buckets[variant][0] as Array).append(xf)
	(buckets[variant][1] as Array).append(col)


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
	# Issue #208: six facade texture variants — three
	# window-grid phase offsets x the shipped texture and
	# its 180-degree rotation (the texture is near-symmetric
	# under that rotation: trim bands swap, windows stay
	# upright). Same shipped art, no new assets; buildings
	# hash-pick a variant and batch by it.
	var wimg := _window_image()
	var wimg_flip := wimg.duplicate() as Image
	wimg_flip.flip_x()
	wimg_flip.flip_y()
	var tex_a := ImageTexture.create_from_image(wimg)
	var tex_b := ImageTexture.create_from_image(wimg_flip)
	var offs := [Vector2(0.0, 0.0), Vector2(0.13, 0.07),
		Vector2(0.38, 0.13)]
	_building_mats.clear()
	for i in 6:
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex_b if i >= 3 else tex_a
		m.uv1_offset = Vector3(offs[i % 3].x, offs[i % 3].y, 0.0)
		m.roughness = 0.9
		_building_mats.append(m)
	_interior_mat = StandardMaterial3D.new()
	_interior_mat.albedo_color = Color(0.84, 0.80, 0.74)
	_interior_mat.roughness = 1.0
	_door_mat = StandardMaterial3D.new()
	_door_mat.albedo_color = Color(0.36, 0.24, 0.14)
	_door_mat.roughness = 0.95
	for t in SCATTER_MODELS:
		_scatter_meshes[t] = _glb_mesh(SCATTER_MODELS[t])


## The render Mesh inside a Kenney GLB scene (the pack's
## models are single-mesh scenes; the mesh's own surfaces
## carry the authored materials).
func _glb_mesh(path: String) -> Mesh:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var mesh: Mesh = null
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			mesh = (n as MeshInstance3D).mesh
			break
		for c in n.get_children():
			stack.append(c)
	inst.free()
	return mesh


## A ONE-FLOOR window band (#199; contrast bumped #200): shell
## pieces are single-story boxes, so each carries one row of
## windows and a tower reads as stacked stories from outside.
## The #199 acceptance found the band averaged out pale at
## distance — the windows are TALLER and the glass DARKER now,
## with a structural band above and below the row, so the
## features survive mip averaging from the air.
func _window_texture() -> ImageTexture:
	return ImageTexture.create_from_image(_window_image())


func _window_image() -> Image:
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
	return img
