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
const MIN_LOAD_RADIUS := 1 ## Jesse's ruling 2026-10-26: radius 1 is the floor AND the default (his PC feel test at 1 beat the #219 default of 2).
const MAX_LOAD_RADIUS := 8
const DEFAULT_LOAD_RADIUS := 1
var load_radius: int = DEFAULT_LOAD_RADIUS
var unload_radius: int = DEFAULT_LOAD_RADIUS + 2
const BUILD_PER_FRAME := 1 ## Terrain ASSEMBLIES per streaming step (anti-hitch package, Jesse 2026-10-26): data generation itself no longer happens on this thread at all (worker pool + disk cache), but assembly (mesh + heightfield, ~7-11 ms VM) still does, so it stays capped at one per step. The 197(7) pin's "at most 2 per step" still holds.
## Staged detail building (Jesse's order 2026-10-26): the
## detail pass (buildings + scatter) no longer runs whole
## per chunk in one streaming step. It advances in bounded
## steps — BUILDINGS_PER_STEP buildings, or a slice of one
## scatter type — under a per-step TIME allowance
## granted per streaming step, so no single frame pays
## for a whole dense chunk.
const DETAIL_BUDGET_USEC := 4000 ## Anti-hitch package (Jesse 2026-10-26): the detail pass is budgeted by TIME, not step counts — it works until the allowance is spent, so the cap means the same thing on a fast PC and a slow VM. Halved on a step that also assembled terrain (stacking is the spike being flattened); the first eligible chunk always gets one step, so progress never stalls.
const DETAIL_BUDGET_BUSY_USEC := 2000
const GEN_DISPATCH_WINDOW := 4 ## Chunk generations in flight per streamer on the worker pool.
const BUILDINGS_PER_STEP := 2
const SCATTER_ITEMS_PER_STEP := 200
const SCATTER_CANDIDATES_PER_STEP := 64 ## Anti-hitch package: was 256 (~19 ms VM per slice — too coarse for the time budget to bind); 64 is ~5 ms VM / ~1 ms on Jesse's PC.
const BUILDING_RADIUS := 3
const BUILDING_DESPAWN_MSEC := 5000 ## tuning placeholder (#198)
const EDGE_FORCE_DIST := 16.0 ## Issue #231 (Jesse's ruling): a player this close to the border of an unbuilt neighbor chunk should not wait on the async pipeline - the chunk generates IN FRAME (data + terrain assembly; detail stays staged). A feel number - Jesse's staging test judges it.
const EDGE_FORCE_PER_STEP := 1 ## The #231 bound: at most one forced in-frame generation per streaming step (worst case one ~50-70 ms sync build); a corner's remaining neighbors force on the following steps.
const CONE_COS := 0.4226 ## cos(65 deg): the view-cone priority band

const WorldGen := preload("res://scripts/world/world_gen.gd")
const ChunkData := preload("res://scripts/world/chunk_data.gd")
const BuildingGen := preload("res://scripts/world/building_gen.gd")
const BuildingSelect := preload("res://scripts/world/building_select.gd")
const ScatterGen := preload("res://scripts/world/scatter_gen.gd")
const WorldCache := preload("res://scripts/world/world_cache.gd")
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
## Anti-hitch package: generations in flight (key ->
## {"task": int, "data": ChunkData-or-null}) and data
## harvested but not yet assembled (key -> ChunkData).
var _pending := {}
var _ready_data := {}
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


## Worker-thread generation (Jesse's anti-hitch package,
## 2026-10-26): generate_chunk is a pure function of
## (seed, cx, cz) — hash-seeded, no shared mutable state
## (audited first-hand) — so it runs on the worker pool.
## The main thread only polls for completion and assembles
## the result; the lambda writes into a slot dictionary,
## and the slot is read only after the pool reports the
## task complete.
func _dispatch_gen(cx: int, cz: int) -> void:
	var slot := {"task": -1, "data": null}
	var task := WorkerThreadPool.add_task(
		func() -> void:
			slot["data"] = WorldGen.generate_chunk(
				cx, cz, WorldGen.WORLD_SEED),
		false, "chunk gen %d,%d" % [cx, cz])
	slot["task"] = task
	_pending[_key(cx, cz)] = slot


func _exit_tree() -> void:
	# Never leave the pool holding tasks whose slots die
	# with this streamer. In-flight generations are few
	# (dispatch window) and short.
	for k in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(
			int(_pending[k]["task"]))
	_pending.clear()


## Issue #231: the desired-but-unbuilt chunks sharing a
## border (or, at a corner, a corner point) with the
## target's chunk whose shared edge lies within
## EDGE_FORCE_DIST of the target - nearest first.
func _edge_force_candidates(tcx: int, tcz: int) -> Array:
	var cs := WorldGen.CHUNK_SIZE
	var lx := _target_pos.x - float(tcx) * cs
	var lz := _target_pos.z - float(tcz) * cs
	var scored: Array = []
	var axes: Array = []
	if lx <= EDGE_FORCE_DIST:
		axes.append(Vector3(-1, 0, lx))
	if cs - lx <= EDGE_FORCE_DIST:
		axes.append(Vector3(1, 0, cs - lx))
	if lz <= EDGE_FORCE_DIST:
		axes.append(Vector3(0, -1, lz))
	if cs - lz <= EDGE_FORCE_DIST:
		axes.append(Vector3(0, 1, cs - lz))
	var has_x := false
	var has_z := false
	for a in axes:
		if int(a.x) != 0:
			has_x = true
		if int(a.y) != 0:
			has_z = true
	for a in axes:
		var cx := tcx + int(a.x)
		var cz := tcz + int(a.y)
		if _active.has(_key(cx, cz)):
			continue
		if maxi(absi(cx - tcx), absi(cz - tcz)) > load_radius:
			continue
		scored.append([a.z, Vector2i(cx, cz)])
	if has_x and has_z:
		for a in axes:
			if int(a.x) == 0:
				continue
			for b in axes:
				if int(b.y) == 0:
					continue
				var dx := tcx + int(a.x)
				var dz := tcz + int(b.y)
				if _active.has(_key(dx, dz)):
					continue
				if maxi(absi(dx - tcx),
						absi(dz - tcz)) > load_radius:
					continue
				var dcorner := Vector2(
					lx if a.x < 0 else cs - lx,
					lz if b.y < 0 else cs - lz).length()
				scored.append([dcorner, Vector2i(dx, dz)])
	scored.sort_custom(func(p: Array, q: Array) -> bool:
		return float(p[0]) < float(q[0]))
	var out: Array = []
	for e in scored:
		out.append(e[1])
	return out


## Issue #231: build one chunk NOW, on this thread - a
## pending pool task is landed (never duplicated), ready
## data is assembled, anything else generates through
## the synchronous cache-or-generate path. Terrain +
## collision only: buildings and scatter still arrive
## through the budgeted detail pass (detail_done stays
## false on the fresh record).
func _force_build_chunk(cx: int, cz: int) -> void:
	var k := _key(cx, cz)
	if _active.has(k):
		return
	if _pending.has(k):
		var slot: Dictionary = _pending[k]
		WorkerThreadPool.wait_for_task_completion(
			int(slot["task"]))
		_pending.erase(k)
		var pdata: RefCounted = slot["data"]
		if pdata != null:
			WorldCache.write_data(pdata)
			_assemble_chunk(cx, cz, pdata)
		return
	if _ready_data.has(k):
		var rdata: RefCounted = _ready_data[k]
		_ready_data.erase(k)
		_assemble_chunk(cx, cz, rdata)
		return
	_build_chunk(cx, cz)


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
	for k in _ready_data.keys():
		var rparts := str(k).split(",")
		if maxi(absi(int(rparts[0]) - tcx),
				absi(int(rparts[1]) - tcz)) > unload_radius:
			_ready_data.erase(k)
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
	# Issue #231 (Jesse's ruling): proximity overrides the
	# pipeline - force the nearest qualifying neighbor
	# chunks in-frame before the queue ordering runs, so
	# the queue below simply never sees them as missing.
	var edge_forced := 0
	for c in _edge_force_candidates(tcx, tcz):
		if edge_forced >= EDGE_FORCE_PER_STEP:
			break
		_force_build_chunk(c.x, c.y)
		edge_forced += 1
	# Build queue by priority (unchanged ordering).
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
	# Anti-hitch data pipeline: request data for every
	# missing chunk — from the disk cache when present
	# (~0.05 ms), else from the worker pool (bounded by
	# the dispatch window; the rest queue as slots free).
	var inflight := _pending.size()
	for c in missing:
		var k := _key(c.x, c.y)
		if _ready_data.has(k) or _pending.has(k):
			continue
		var cached := WorldCache.read_data(c.x, c.y)
		if cached != null:
			_ready_data[k] = cached
		elif inflight < GEN_DISPATCH_WINDOW:
			_dispatch_gen(c.x, c.y)
			inflight += 1
	# Harvest completed generations: cache the output,
	# keep it for assembly only while the chunk is wanted.
	for k in _pending.keys():
		var slot: Dictionary = _pending[k]
		if WorkerThreadPool.is_task_completed(int(slot["task"])):
			WorkerThreadPool.wait_for_task_completion(
				int(slot["task"]))
			_pending.erase(k)
			var gdata: RefCounted = slot["data"]
			if gdata != null:
				WorldCache.write_data(gdata)
				if desired.has(k):
					_ready_data[k] = gdata
	# Assemble at most BUILD_PER_FRAME terrains, priority
	# order (assembly is the only generation cost left on
	# this thread, ~7-11 ms VM / ~2-3 ms on Jesse's PC).
	var built_now := 0
	for c in missing:
		if built_now >= BUILD_PER_FRAME:
			break
		var k := _key(c.x, c.y)
		if _ready_data.has(k):
			_assemble_chunk(c.x, c.y, _ready_data[k])
			_ready_data.erase(k)
			built_now += 1
	# Detail pass, TIME-budgeted — halved on a step that
	# paid for a terrain assembly (stacking both full
	# budgets in one step is the compound spike the
	# staging exists to flatten; a zero grant would starve
	# the near chunks' detail for the whole fill — the
	# 198(4) pin measured exactly that starvation against
	# the step-count form of this rule).
	_update_buildings(tcx, tcz, now,
		DETAIL_BUDGET_USEC if built_now == 0
			else DETAIL_BUDGET_BUSY_USEC)
	# Catch-up wait: nothing assembled this step but
	# generations are in flight — wait for the nearest
	# one and assemble it. A caller looping
	# update_streaming (the suite's build loops, the
	# world entry ready-gate) therefore always makes
	# progress. In live play this fires only when the
	# ring is actually behind (a missing chunk whose
	# generation has not landed), where a bounded wait
	# beats a hole in the world; when the ring is full,
	# nothing is pending and it never fires.
	if built_now == 0 and not _pending.is_empty():
		for c in missing:
			var k := _key(c.x, c.y)
			if _pending.has(k):
				var slot: Dictionary = _pending[k]
				WorkerThreadPool.wait_for_task_completion(
					int(slot["task"]))
				_pending.erase(k)
				var wdata: RefCounted = slot["data"]
				if wdata != null:
					WorldCache.write_data(wdata)
					_assemble_chunk(c.x, c.y, wdata)
				break


## Buildings: materialize inside BUILDING_RADIUS when not reported
## hidden; despawn outside the ring or after BUILDING_DESPAWN_MSEC
## of sustained off-screen time.
func _update_buildings(tcx: int, tcz: int, now: int,
		allowance_usec: int = DETAIL_BUDGET_USEC) -> bool:
	var deadline := Time.get_ticks_usec() + allowance_usec
	var advanced := false
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
		if (bool(rec.get("detail_done", false)) \
				or rec.get("detail_job") != null) \
				and (not in_ring or hidden_long):
			# A mid-flight job sheds its partial nodes
			# too (they are not rec["buildings"] /
			# rec["scatter"] yet — those land only when
			# a stage completes).
			var dj = rec.get("detail_job")
			if dj != null:
				var jb = dj["b"]["bnode"]
				if jb != null and jb != rec["buildings"]:
					(jb as Node).queue_free()
				var js = dj["s"]["snode"]
				if js != null and js != rec["scatter"]:
					(js as Node).queue_free()
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
			rec["detail_job"] = null
		elif not bool(rec.get("detail_done", false)) \
				and in_ring and vis != 0:
			# Staged detail (Jesse's order 2026-10-26),
			# time-budgeted (anti-hitch package): advance
			# this chunk's job until the allowance is
			# spent or the pass completes — the first
			# eligible chunk always gets one step, so
			# progress never stalls. The despawn checks
			# above still run for every chunk on every
			# call, budget or not.
			while not bool(rec.get("detail_done", false)) \
					and (not advanced \
						or Time.get_ticks_usec() < deadline):
				_detail_step(rec)
				advanced = true
	return advanced


## The staged detail job for a chunk record, created on
## first use: a buildings sub-job ("b") and a scatter
## sub-job ("s"), each resumable across streaming steps.
## The Buildings node joins the chunk immediately, so
## collision bodies come online building by building;
## rec["buildings"] itself is assigned only when the
## buildings stage completes, keeping has_buildings'
## meaning (buildings ASSEMBLED). Same for scatter.
func _detail_job(rec: Dictionary) -> Dictionary:
	var dj = rec.get("detail_job")
	if dj == null:
		dj = {"b": {"b_done": false, "cursor": 0, "bnode": null,
				"buckets": {}, "door_xforms": [], "shell_total": 0,
				"collision_shapes": 0, "playable_doors": 0,
				"solid_buildings": 0},
			"s": {"s_done": false, "started": false,
				"gen": null, "gen_done": false,
				"scatter": null, "snode": null,
				"type_idx": 0, "item_idx": 0, "mm": null,
				"total": 0}}
		rec["detail_job"] = dj
		var data: RefCounted = rec["data"]
		if not (data.buildings as Array).is_empty():
			var bnode := Node3D.new()
			bnode.name = "Buildings"
			(rec["node"] as Node).add_child(bnode)
			dj["b"]["bnode"] = bnode
	return dj


## Advance one chunk's staged detail pass by ONE bounded
## step: a slice of the buildings stage, or a slice of the
## scatter stage. detail_done is set only when BOTH stages
## complete — the completion meaning chunk_fully_built
## has always read.
func _detail_step(rec: Dictionary) -> void:
	var dj := _detail_job(rec)
	if not bool(dj["b"]["b_done"]):
		_buildings_job_step(rec, dj["b"])
	elif not bool(dj["s"]["s_done"]):
		_scatter_job_step(rec, dj["s"])
	if bool(dj["b"]["b_done"]) and bool(dj["s"]["s_done"]):
		rec["detail_done"] = true
		rec["detail_job"] = null


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


## Synchronous chunk build (the direct-call contract the
## pins use): data from cache or generation, then terrain
## assembly. The streaming path normally reaches assembly
## through the threaded pipeline (update_streaming).
func _build_chunk(cx: int, cz: int) -> void:
	_assemble_chunk(cx, cz, _chunk_data_sync(cx, cz))


## Chunk data the synchronous way: cache first (a ~0.05 ms
## roundtrip against generation's 42-62 ms), generating —
## and caching — on a miss.
func _chunk_data_sync(cx: int, cz: int) -> RefCounted:
	var cached := WorldCache.read_data(cx, cz)
	if cached != null:
		return cached
	var data := WorldGen.generate_chunk(cx, cz)
	WorldCache.write_data(data)
	return data


func _assemble_chunk(cx: int, cz: int, data: RefCounted) -> void:
	_ensure_assets()
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
		"detail_job": null, "plans": {}, "shell_pieces": 0, "interior_pieces": 0,
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
	# One-shot form (pins + standalone callers): drain the
	# staged buildings job synchronously and return the
	# finished node — the same contract this function has
	# always had. The streaming driver uses the stepped
	# form (_buildings_job_step) instead.
	var dj := _detail_job(rec)
	while not bool(dj["b"]["b_done"]):
		_buildings_job_step(rec, dj["b"])
	return rec["buildings"]


## One bounded step of a chunk's buildings stage: up to
## BUILDINGS_PER_STEP buildings assembled (plans, shell
## buckets, collision bodies, doors) into the job's
## Buildings node. Returns true when the stage completes
## (counts written, shell batches flushed, rec["buildings"]
## assigned). State lives in the job dict so the pass can
## pause and resume across frames.
func _buildings_job_step(rec: Dictionary, job: Dictionary) -> bool:
	if bool(job["b_done"]):
		return true
	var data: RefCounted = rec["data"]
	var buildings: Array = data.buildings
	if buildings.is_empty():
		job["b_done"] = true
		return true
	var node: Node3D = job["bnode"]
	var cx: int = data.cx
	var cz: int = data.cz
	var shell_buckets: Dictionary = job["buckets"]
	var door_xforms: Array = job["door_xforms"]
	var shell_total := int(job["shell_total"])
	var collision_shapes := int(job["collision_shapes"])
	var playable_doors := int(job["playable_doors"])
	var solid_buildings := int(job["solid_buildings"])
	var idx := 0
	for b in buildings:
		if idx < int(job["cursor"]):
			idx += 1
			continue
		if idx >= int(job["cursor"]) + BUILDINGS_PER_STEP:
			break
		idx += 1
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
	job["cursor"] = idx
	job["shell_total"] = shell_total
	job["collision_shapes"] = collision_shapes
	job["playable_doors"] = playable_doors
	job["solid_buildings"] = solid_buildings
	if idx < buildings.size():
		return false
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
	rec["buildings"] = node
	job["b_done"] = true
	return true


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
## (the building-piece collision path).
func _add_box_shape(body: StaticBody3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = xf.basis.get_scale()
	cs.shape = box
	# The piece size lives in the shape ALONE: the node
	# transform must carry only the position. (Setting
	# cs.transform = xf here double-applied the scale —
	# every collision box came out piece-size-squared:
	# a 6.4 m wall collided as a 41 m slab. Found by
	# Jesse's feet, 2026-10-27: centers were always
	# exact, sizes never were. Pieces are axis-aligned
	# by construction, so dropping the basis loses
	# nothing.)
	cs.transform = Transform3D(Basis.IDENTITY, xf.origin)
	body.add_child(cs)


## Issue #204 (P4): the chunk's nature scatter — MultiMesh per
## asset type from ScatterGen's pure output. ALL nature is
## visual-only (Jesse's ruling 2026-10-26 removed the N6
## collision shapes: no bodies for trees or rocks). Spill
## rects come from the
## west / north neighbors' buildings (their +x/+z spans can
## cross into this chunk) when those chunks are loaded.
func _make_scatter(rec: Dictionary) -> Node:
	# One-shot form (pins + standalone callers): drain the
	# staged scatter job synchronously and return the
	# finished node — the same contract this function has
	# always had. The streaming driver uses the stepped
	# form (_scatter_job_step) instead.
	var dj := _detail_job(rec)
	while not bool(dj["s"]["s_done"]):
		_scatter_job_step(rec, dj["s"])
	return rec["scatter"]


## One bounded step of a chunk's scatter stage. The first
## step runs the pure generation (spill rects +
## ScatterGen) and creates the Scatter node; later steps
## fill one scatter type's MultiMesh in slices of
## SCATTER_ITEMS_PER_STEP instances, adding the type's
## MultiMeshInstance3D when the type completes. Returns true when every type
## is done (counts written, rec["scatter"] assigned).
func _scatter_job_step(rec: Dictionary, job: Dictionary) -> bool:
	if bool(job["s_done"]):
		return true
	var data: RefCounted = rec["data"]
	var cx: int = data.cx
	var cz: int = data.cz
	if not bool(job["started"]):
		_ensure_assets()
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
		var cached_scatter = WorldCache.read_scatter(cx, cz)
		if cached_scatter != null:
			# Cache hit: the pure walk already ran in
			# some earlier visit — adopt its output
			# wholesale (identical by construction).
			job["gen_done"] = true
			job["scatter"] = cached_scatter
			var ctotal := 0
			for t in ScatterGen.TYPES:
				ctotal += (cached_scatter[t] as Array).size()
			job["total"] = ctotal
		else:
			job["gen"] = ScatterGen.scatter_start(
				WorldGen.WORLD_SEED, cx, cz, data, spill)
		var snode := Node3D.new()
		snode.name = "Scatter"
		(rec["node"] as Node).add_child(snode)
		job["snode"] = snode
		job["started"] = true
		return false
	# Generation stage: the pure candidate walk, sliced
	# across steps — it is the scatter pass's largest
	# single cost on a dense chunk, so it never runs
	# whole inside one streaming step either.
	if not bool(job["gen_done"]):
		job["gen_done"] = ScatterGen.scatter_step(job["gen"],
			SCATTER_CANDIDATES_PER_STEP)
		if bool(job["gen_done"]):
			job["scatter"] = job["gen"]["out"]
			WorldCache.write_scatter(cx, cz, job["scatter"])
			var total := 0
			for t in ScatterGen.TYPES:
				total += (job["scatter"][t] as Array).size()
			job["total"] = total
		return false
	var scatter: Dictionary = job["scatter"]
	var types: Array = ScatterGen.TYPES
	if int(job["type_idx"]) >= types.size():
		rec["scatter_count"] = int(job["total"])
		rec["scatter"] = job["snode"]
		job["s_done"] = true
		return true
	var t: String = types[int(job["type_idx"])]
	var items: Array = scatter[t]
	if items.is_empty():
		job["type_idx"] = int(job["type_idx"]) + 1
		return false
	var mesh: Mesh = _scatter_meshes.get(t)
	if mesh == null:
		job["type_idx"] = int(job["type_idx"]) + 1
		job["item_idx"] = 0
		return false
	var mm: MultiMesh = job["mm"]
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = items.size()
		job["mm"] = mm
	var node: Node3D = job["snode"]
	var chunk_origin := Vector3(float(cx) * WorldGen.CHUNK_SIZE,
		0, float(cz) * WorldGen.CHUNK_SIZE)
	var end := mini(int(job["item_idx"]) + SCATTER_ITEMS_PER_STEP,
		items.size())
	var i := int(job["item_idx"])
	while i < end:
		var it: Dictionary = items[i]
		var local := (it["p"] as Vector3) - chunk_origin
		var basis := Basis(Vector3.UP, float(it["r"])) \
			.scaled(Vector3.ONE * float(it["s"]))
		mm.set_instance_transform(i, Transform3D(basis,
			local))
		i += 1
	job["item_idx"] = i
	if i >= items.size():
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		node.add_child(mmi)
		job["mm"] = null
		job["item_idx"] = 0
		job["type_idx"] = int(job["type_idx"]) + 1
	return false


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
