## Issue #253: the Act 1 cache warmer (Jesse's ruling
## 2026-11-21: "Pre-generate in-game during Act 1 (no
## shipped files)"). While a run climbs Act 1, this
## driver pre-generates the starting railway's chunks
## into the local WorldCache — data + scatter — so world
## entry and the first train rides run warm. The cache
## stays purely local and disposable: every peer warms
## its own, nothing is synced, nothing ships.
##
## The target set derives ONCE from the game's own
## functions (see target_chunks): the home disc, each
## initial-ring city's disc, and the home->city rail
## corridors. Generation runs on the worker pool (the
## streamer's audited-pure generate_chunk); scatter runs
## on the main thread through ScatterGen's budgeted
## stepper at the streamer's own slice size; WorldCache
## writes happen on the main thread only (the cache's
## discipline). The driver mutates NO run statics and
## stops the moment its stop_check fires (the Dungeon
## wires that to the reveal). Leftover unwarm chunks are
## harmless — the world still generates live; there is
## no correctness dependency on completion.
extends Node

const WorldGen := preload("res://scripts/world/world_gen.gd")
const WorldCache := preload("res://scripts/world/world_cache.gd")
const TrainNetwork := preload("res://scripts/world/train_network.gd")

const GEN_WINDOW := 2 ## worker generations in flight
const SCATTER_CANDIDATES_PER_STEP := 64 ## the streamer's slice
const MAX_EXAMINE_PER_STEP := 8 ## pending candidates checked per pump

var _pending: Array = []
var _inflight := {}
var _ready: Array = []
var _memo := {}
var _scatter_job := {}
var _home_rect := Rect2()
var _stop_check: Callable
var _is_setup := false


## The deterministic warm set for a home center: chunks
## within radius 3 of home; for each city in the initial
## ring, chunks within (its radius_chunks + 1) of the
## city center; and chunks within one chunk of each
## home->city edge's routed polyline (the geometry the
## track stage lays). Membership is by chunk-center
## distance for the discs (the cities_within idiom) and
## by chunk-rect distance for the corridors. The routed
## polylines are derived with the home center standing
## in for the home station: the doorstep sits inside the
## home disc, and the corridor is dilated a full chunk,
## so the derived set is the doorstep geometry's set.
static func target_chunks(home_center: Vector2) -> Array:
	var seed: int = WorldGen.WORLD_SEED
	var set := {}
	var ring := TrainNetwork.initial_ring(seed, home_center)
	_disc(set, home_center, 3.0 * WorldGen.CHUNK_SIZE)
	var graph := TrainNetwork.derive_graph(seed, ring, home_center)
	var centers: Dictionary = graph["nodes"]
	for key in ring:
		var k := str(key)
		if k == TrainNetwork.HOME_KEY:
			continue
		var cell = TrainNetwork.key_cell(k)
		if cell == null:
			continue
		var s := WorldGen.settlement_in_cell(seed,
			(cell as Vector2i).x, (cell as Vector2i).y)
		if s.is_empty():
			continue
		_disc(set, s["center"],
			(float(s["radius_chunks"]) + 1.0) \
				* WorldGen.CHUNK_SIZE)
	for e in graph["edges"]:
		var a := str(e[0])
		var b := str(e[1])
		var other := ""
		if a == TrainNetwork.HOME_KEY:
			other = b
		elif b == TrainNetwork.HOME_KEY:
			other = a
		else:
			continue
		if not centers.has(other):
			continue
		var pts := TrainNetwork.routed_points(seed, ring,
			home_center, home_center,
			centers[TrainNetwork.HOME_KEY] as Vector2,
			centers[other] as Vector2)
		_corridor(set, pts)
	var out: Array = set.keys()
	out.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return p.x < q.x or (p.x == q.x and p.y < q.y))
	return out


static func _disc(set: Dictionary, point: Vector2,
		radius_m: float) -> void:
	var cs: float = WorldGen.CHUNK_SIZE
	var x0 := int(floor((point.x - radius_m) / cs))
	var x1 := int(floor((point.x + radius_m) / cs))
	var z0 := int(floor((point.y - radius_m) / cs))
	var z1 := int(floor((point.y + radius_m) / cs))
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var cc := Vector2((float(cx) + 0.5) * cs,
				(float(cz) + 0.5) * cs)
			if cc.distance_to(point) <= radius_m:
				set[Vector2i(cx, cz)] = true


static func _corridor(set: Dictionary, pts: Array) -> void:
	var cs: float = WorldGen.CHUNK_SIZE
	for i in range(pts.size() - 1):
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		var x0 := int(floor((minf(p.x, q.x) - 2.0 * cs) / cs))
		var x1 := int(floor((maxf(p.x, q.x) + 2.0 * cs) / cs))
		var z0 := int(floor((minf(p.y, q.y) - 2.0 * cs) / cs))
		var z1 := int(floor((maxf(p.y, q.y) + 2.0 * cs) / cs))
		for cx in range(x0, x1 + 1):
			for cz in range(z0, z1 + 1):
				var r := Rect2(float(cx) * cs, float(cz) * cs,
					cs, cs)
				if _seg_rect_dist(p, q, r) <= cs:
					set[Vector2i(cx, cz)] = true


static func _seg_rect_dist(p: Vector2, q: Vector2,
		r: Rect2) -> float:
	if r.has_point(p) or r.has_point(q):
		return 0.0
	var corners: Array = [
		r.position,
		r.position + Vector2(r.size.x, 0.0),
		r.position + r.size,
		r.position + Vector2(0.0, r.size.y)]
	var best := INF
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		if Geometry2D.segment_intersects_segment(p, q, a, b) != null:
			return 0.0
		best = minf(best, _seg_seg_dist(p, q, a, b))
	return best


static func _seg_seg_dist(p1: Vector2, p2: Vector2,
		p3: Vector2, p4: Vector2) -> float:
	return minf(
		minf(_point_seg_dist(p1, p3, p4),
			_point_seg_dist(p2, p3, p4)),
		minf(_point_seg_dist(p3, p1, p2),
			_point_seg_dist(p4, p1, p2)))


static func _point_seg_dist(pt: Vector2, a: Vector2,
		b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	var len2 := ab.length_squared()
	if len2 > 0.0:
		t = clampf((pt - a).dot(ab) / len2, 0.0, 1.0)
	return pt.distance_to(a + ab * t)


## Arm the warmer: derive the target set for the anchor
## and remember the home plot's rect (the scatter spill
## suppress, mirroring the world streamer's) and the
## stop condition (the reveal, in production).
func setup(home_center: Vector2, home_rect: Rect2,
		stop_check: Callable) -> void:
	_home_rect = home_rect
	_stop_check = stop_check
	_pending = target_chunks(home_center)
	_is_setup = true


func is_done() -> bool:
	return _is_setup and _pending.is_empty() \
		and _inflight.is_empty() and _ready.is_empty() \
		and _scatter_job.is_empty()


## One production pump (called per frame by the owner):
## harvest finished generations, advance the scatter
## job by one slice, dispatch up to the window. Never
## blocks, never generates on the main thread.
func pump_step() -> void:
	_pump(false)


## The synchronous form for pins and standalone callers
## (the streamer's _make_scatter duality): pump until
## the set is warm or the stop condition fires.
func pump_blocking() -> void:
	while _is_setup and not is_done():
		if _stopped():
			return
		_pump(true)


func _stopped() -> bool:
	return _stop_check.is_valid() and bool(_stop_check.call())


func _pump(blocking: bool) -> void:
	if not _is_setup or _stopped():
		return
	# Harvest completed generations into the ready queue.
	# A waited task's ID is dead afterwards and must never
	# be queried again, so every harvest reaps its task in
	# the same breath (the streamer's discipline).
	var harvested_any := false
	for task in _inflight.keys():
		if WorkerThreadPool.is_task_completed(task):
			_harvest(task)
			harvested_any = true
	if blocking and not harvested_any \
			and not _inflight.is_empty():
		# Guarantee progress for synchronous callers: wait
		# on the oldest task and harvest it immediately.
		_harvest(int(_inflight.keys()[0]))
	# Advance the scatter job, one at a time. The spill
	# mirrors the streamer's: the west/north/northwest
	# neighbours' building rects (from this session's
	# generations or the cache; a neighbour not yet
	# available contributes nothing, exactly as an
	# inactive neighbour contributes nothing there) plus
	# the home plot's suppress rect.
	if _scatter_job.is_empty() and not _ready.is_empty():
		var nxt: Dictionary = _ready.pop_front()
		var data2: RefCounted = nxt["data"]
		_scatter_job = {"key": nxt["key"], "data": data2,
			"state": ScatterGen.scatter_start(
				WorldGen.WORLD_SEED, data2.cx, data2.cz,
				data2, _spill_for(data2.cx, data2.cz))}
	if not _scatter_job.is_empty():
		var budget := (1 << 30) if blocking \
			else SCATTER_CANDIDATES_PER_STEP
		if ScatterGen.scatter_step(_scatter_job["state"], budget):
			var data3: RefCounted = _scatter_job["data"]
			WorldCache.write_data(data3)
			WorldCache.write_scatter(data3.cx, data3.cz,
				_scatter_job["state"]["out"])
			_scatter_job = {}
	# Dispatch new generations up to the window. A chunk
	# whose payload already validates is warm — it is
	# skipped and never rewritten.
	var examined := 0
	while _inflight.size() < GEN_WINDOW \
			and not _pending.is_empty():
		if not blocking and examined >= MAX_EXAMINE_PER_STEP:
			break
		examined += 1
		var key: Vector2i = _pending.pop_back()
		if not WorldCache.read_payload(key.x, key.y).is_empty():
			continue
		var slot := {"data": null}
		var cx := key.x
		var cz := key.y
		var task := WorkerThreadPool.add_task(
			func() -> void:
				slot["data"] = WorldGen.generate_chunk(
					cx, cz, WorldGen.WORLD_SEED),
			false, "cache warm %d,%d" % [cx, cz])
		_inflight[task] = {"key": key, "slot": slot}


## Reap one in-flight generation: wait for it (returns
## at once when it already completed), drop its record,
## and queue its data for the scatter stage. The task ID
## is never touched again after this call.
func _harvest(task: int) -> void:
	WorkerThreadPool.wait_for_task_completion(task)
	var rec: Dictionary = _inflight[task]
	_inflight.erase(task)
	var data: RefCounted = rec["slot"]["data"]
	if data != null:
		_memo[rec["key"]] = data
		_ready.append({"key": rec["key"], "data": data})


func _spill_for(cx: int, cz: int) -> Array:
	var spill: Array = []
	for off in [Vector2i(-1, 0), Vector2i(0, -1),
			Vector2i(-1, -1)]:
		var nk := Vector2i(cx + off.x, cz + off.y)
		var ndata: RefCounted = null
		if _memo.has(nk):
			ndata = _memo[nk]
		else:
			ndata = WorldCache.read_data(nk.x, nk.y)
		if ndata == null:
			continue
		for b in ndata.buildings:
			var bx := float(nk.x * 16 + int(b[0])) \
				* WorldGen.LOT_SIZE
			var bz := float(nk.y * 16 + int(b[1])) \
				* WorldGen.LOT_SIZE
			spill.append(Rect2(bx - 0.6, bz - 0.6,
				float(int(b[4])) * WorldGen.LOT_SIZE + 1.2,
				float(int(b[5])) * WorldGen.LOT_SIZE + 1.2))
	spill.append(Rect2(_home_rect.position - Vector2(0.6, 0.6),
		_home_rect.size + Vector2(1.2, 1.2)))
	return spill


func _exit_tree() -> void:
	# Never leave the pool holding tasks whose slots die
	# with this driver (the streamer's discipline).
	for task in _inflight.keys():
		WorkerThreadPool.wait_for_task_completion(task)
	_inflight.clear()
