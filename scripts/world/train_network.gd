extends RefCounted

## Issue #244 (Act 2 train, spec section 2): the network
## model as PURE derivation. Every function here takes the
## seed, the discovered set, and the home center as
## ARGUMENTS and reads no run state — the same inputs on
## any peer derive the identical graph, which is what lets
## the server own only the discovered set (progression)
## while the graph itself is never saved or shipped.
##
## Nodes (section 2.1): one per discovered city, keyed by
## its lattice cell "gx,gz", plus the home node, key
## "home". Edges (section 2.3): each node's 2 nearest
## neighbours by (distance, gx, gz) — the road_targets
## pattern over the discovered set — then connectivity
## completion by union-find, so the discovered graph is
## connected BY CONSTRUCTION: a single track to any
## destination is a theorem of this derivation, not a
## hope. Interchanges are the nodes themselves. Routing
## is Dijkstra over edge lengths, identical on any peer.

const WorldGen := preload("res://scripts/world/world_gen.gd")

## Ruled radii (Fork F2, Jesse 2026-11-01): the initial
## discovery ring around the home building, and the
## expansion ring around each first-arrived city.
const DISCOVERY_RADIUS_CHUNKS := 24
const EXPANSION_RADIUS_CHUNKS := 16

const HOME_KEY := "home"


static func city_key(gx: int, gz: int) -> String:
	return "%d,%d" % [gx, gz]


## "gx,gz" -> the cell, or null for a malformed key (the
## home key included — it is not a cell).
static func key_cell(key: String) -> Variant:
	var parts := key.split(",")
	if parts.size() != 2:
		return null
	if not (parts[0].is_valid_int() and parts[1].is_valid_int()):
		return null
	return Vector2i(int(parts[0]), int(parts[1]))


## A node's sort cell: a city's own lattice cell; the
## home node's is the cell containing its center. Node
## order and every tie-break run on (gx, gz, key), so
## the derivation's output order never depends on the
## discovered set's storage order.
static func _sort_cell(seed: int, key: String,
		home_center: Vector2) -> Vector2i:
	if key == HOME_KEY:
		var cell_m := float(WorldGen.CELL_CHUNKS) \
			* WorldGen.CHUNK_SIZE
		return Vector2i(int(floor(home_center.x / cell_m)),
			int(floor(home_center.y / cell_m)))
	var cell = key_cell(key)
	return cell if cell != null else Vector2i.ZERO


## A node's center: the city's settlement center from
## the lattice; the home node's is the home center the
## caller passes. Vector2.ZERO for a key that resolves
## to no city (a corrupt discovered entry — derivation
## skips those rather than placing them at the origin).
static func node_center(seed: int, key: String,
		home_center: Vector2) -> Vector2:
	if key == HOME_KEY:
		return home_center
	var cell = key_cell(key)
	if cell == null:
		return Vector2.ZERO
	var s := WorldGen.settlement_in_cell(seed,
		(cell as Vector2i).x, (cell as Vector2i).y)
	if str(s.get("kind", "")) != "city":
		return Vector2.ZERO
	return s["center"]


static func _node_order(seed: int, keys: Array,
		home_center: Vector2) -> Array:
	var cells := {}
	for key in keys:
		cells[key] = _sort_cell(seed, key, home_center)
	var out := keys.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var ca: Vector2i = cells[a]
		var cb: Vector2i = cells[b]
		if ca.x != cb.x:
			return ca.x < cb.x
		if ca.y != cb.y:
			return ca.y < cb.y
		return a < b)
	return out


## Every city whose center lies within radius_chunks of
## center — a direct read of the lattice over the disc's
## bounding cells. Keys in (gx, gz) order.
static func cities_within(seed: int, center: Vector2,
		radius_chunks: int) -> Array:
	var radius_m := float(radius_chunks) * WorldGen.CHUNK_SIZE
	var cell_m := float(WorldGen.CELL_CHUNKS) * WorldGen.CHUNK_SIZE
	var gx0 := int(floor((center.x - radius_m) / cell_m))
	var gx1 := int(floor((center.x + radius_m) / cell_m))
	var gz0 := int(floor((center.y - radius_m) / cell_m))
	var gz1 := int(floor((center.y + radius_m) / cell_m))
	var out: Array = []
	for gx in range(gx0, gx1 + 1):
		for gz in range(gz0, gz1 + 1):
			var s := WorldGen.settlement_in_cell(seed, gx, gz)
			if str(s.get("kind", "")) != "city":
				continue
			if center.distance_to(s["center"]) <= radius_m:
				out.append(city_key(gx, gz))
	return out


## The initial ring (section 2.2): every city within
## DISCOVERY_RADIUS_CHUNKS of the home building's center.
static func initial_ring(seed: int, home_center: Vector2) -> Array:
	return cities_within(seed, home_center,
		DISCOVERY_RADIUS_CHUNKS)


## The expansion ring (section 2.2): every city within
## EXPANSION_RADIUS_CHUNKS of the arrived city's center.
## Includes the arrived city itself; the union/diff
## against the discovered set is the caller's beat.
static func expansion_ring(seed: int, arrived_key: String) -> Array:
	var cell = key_cell(arrived_key)
	if cell == null:
		return []
	var s := WorldGen.settlement_in_cell(seed,
		(cell as Vector2i).x, (cell as Vector2i).y)
	if str(s.get("kind", "")) != "city":
		return []
	return cities_within(seed, s["center"],
		EXPANSION_RADIUS_CHUNKS)


## The derived graph for a discovered set:
##   {nodes: {key: center}, order: [keys in node order],
##    edges: [[keyA, keyB, length], ...] canonical}
## Edges are undirected; each pair appears once, A before
## B in node order, the list sorted by node order.
static func derive_graph(seed: int, discovered: Array,
		home_center: Vector2) -> Dictionary:
	# The node set: home plus every discovered key that
	# resolves to a city, deduplicated.
	var centers := {HOME_KEY: home_center}
	for key in discovered:
		var k := str(key)
		if k == HOME_KEY or centers.has(k):
			continue
		var cell = key_cell(k)
		if cell == null:
			continue
		var s := WorldGen.settlement_in_cell(seed,
			(cell as Vector2i).x, (cell as Vector2i).y)
		if str(s.get("kind", "")) != "city":
			continue
		centers[k] = s["center"]
	var order := _node_order(seed, centers.keys(), home_center)
	var rank := {}
	for i in order.size():
		rank[order[i]] = i
	# Neighbour ranking per node: every other node by
	# (distance, gx, gz, key) — the road_targets sort.
	var cells := {}
	for key in order:
		cells[key] = _sort_cell(seed, key, home_center)
	var nearest := {}
	for key in order:
		var cands: Array = []
		for other in order:
			if other == key:
				continue
			var oc: Vector2i = cells[other]
			cands.append({"key": other,
				"d": (centers[key] as Vector2).distance_to(
					centers[other]),
				"gx": oc.x, "gz": oc.y})
		cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a["d"]) != float(b["d"]):
				return float(a["d"]) < float(b["d"])
			if int(a["gx"]) != int(b["gx"]):
				return int(a["gx"]) < int(b["gx"])
			if int(a["gz"]) != int(b["gz"]):
				return int(a["gz"]) < int(b["gz"])
			return str(a["key"]) < str(b["key"]))
		nearest[key] = cands
	# The 2-nearest edge set.
	var edge_set := {}
	for key in order:
		var cands: Array = nearest[key]
		for i in mini(2, cands.size()):
			_add_edge(edge_set, rank, key,
				str(cands[i]["key"]), centers)
	# Connectivity completion (section 2.3): nodes in
	# node order with union-find; a node stranded outside
	# the main component (the first node's) gains its
	# single nearest edge into that component; repeat
	# until one component. Each added edge merges a
	# component into the main one, so this terminates.
	var parent := {}
	for key in order:
		parent[key] = key
	var find_root := func(x: String) -> String:
		var r := x
		while parent[r] != r:
			r = parent[r]
		return r
	for e in edge_set.keys():
		var pair: Array = e
		var ra: String = find_root.call(pair[0])
		var rb: String = find_root.call(pair[1])
		if ra != rb:
			parent[rb] = ra
	var main_root: String = find_root.call(order[0])
	var guard := 0
	while guard < order.size():
		guard += 1
		var stranded := false
		for key in order:
			if find_root.call(key) == main_root:
				continue
			stranded = true
			# The nearest node inside the main component.
			for cand in nearest[key]:
				if find_root.call(str(cand["key"])) == main_root:
					_add_edge(edge_set, rank, key,
						str(cand["key"]), centers)
					parent[find_root.call(key)] = main_root
					break
		if not stranded:
			break
	var edges: Array = []
	for e in edge_set.keys():
		var pair: Array = e
		edges.append([pair[0], pair[1],
			(centers[pair[0]] as Vector2).distance_to(
				centers[pair[1]])])
	edges.sort_custom(func(a: Array, b: Array) -> bool:
		if int(rank[a[0]]) != int(rank[b[0]]):
			return int(rank[a[0]]) < int(rank[b[0]])
		return int(rank[a[1]]) < int(rank[b[1]]))
	return {"nodes": centers, "order": order, "edges": edges}


static func _add_edge(edge_set: Dictionary, rank: Dictionary,
		a: String, b: String, centers: Dictionary) -> void:
	if a == b:
		return
	var pair := [a, b] if int(rank[a]) < int(rank[b]) else [b, a]
	edge_set[pair] = true


## Shortest path (section 2.3): Dijkstra over the
## derived graph's edge lengths. Returns the node keys
## from from_key to to_key inclusive, [] when either
## is not a node of the graph. Deterministic: nodes
## settle in node order and relaxation is strict, so
## equal-length alternatives resolve identically on
## every peer.
static func route(seed: int, discovered: Array,
		home_center: Vector2, from_key: String,
		to_key: String) -> Array:
	var g := derive_graph(seed, discovered, home_center)
	var nodes: Dictionary = g["nodes"]
	if not nodes.has(from_key) or not nodes.has(to_key):
		return []
	if from_key == to_key:
		return [from_key]
	var adj := {}
	for key in nodes.keys():
		adj[key] = []
	for e in g["edges"]:
		var a := str(e[0])
		var b := str(e[1])
		var len := float(e[2])
		adj[a].append([b, len])
		adj[b].append([a, len])
	var order: Array = g["order"]
	var rank := {}
	for i in order.size():
		rank[order[i]] = i
	for key in adj.keys():
		var lst: Array = adj[key]
		lst.sort_custom(func(x: Array, y: Array) -> bool:
			return int(rank[x[0]]) < int(rank[y[0]]))
		adj[key] = lst
	var dist := {from_key: 0.0}
	var prev := {}
	var settled := {}
	while true:
		var cur := ""
		var best := INF
		for key in order:
			if settled.has(key) or not dist.has(key):
				continue
			if float(dist[key]) < best:
				best = float(dist[key])
				cur = key
		if cur == "":
			break
		if cur == to_key:
			break
		settled[cur] = true
		for nb in adj[cur]:
			var nk := str(nb[0])
			if settled.has(nk):
				continue
			var nd := best + float(nb[1])
			if not dist.has(nk) or nd < float(dist[nk]):
				dist[nk] = nd
				prev[nk] = cur
	if not dist.has(to_key):
		return []
	var path: Array = [to_key]
	var at := to_key
	while at != from_key:
		at = str(prev[at])
		path.push_front(at)
	return path


# ------------------------------------------------------------------
# Physical layer (T2): station points, per-chunk segments,
# the smoothed grade, and the resting consist — the graph
# made geometry. Still pure: everything derives from
# (seed, discovered, home_center, home_station).
#
# Placement note: the spec names this family WorldGen's,
# but the graph it reads is T1's derivation, which lives
# here — world_gen.gd cannot host it without a preload
# cycle (this file preloads world_gen) or a second
# derivation. The road idiom is kept exactly: [Vector2,
# Vector2] world-space endpoint pairs, per-chunk questions.
# ------------------------------------------------------------------

## Chunk-inclusion margin for segment queries: a segment
## counts for a chunk when it comes within this distance of
## the chunk's rect — TRACK_HALF_WIDTH (4) plus two lots
## (16), so lot-candidacy distances (generate_chunk) and
## span claims reaching one lot past the border stay exact.
## Phase T3: TRAIN_SPEED (spec §4.2, fork F7 — 28 m/s
## placeholder). Ride duration is path length / TRAIN_SPEED.
const TRAIN_SPEED := 28.0

const SEGMENT_CHUNK_MARGIN := 20.0

## Grade (spec §3.3): terrain sampled every GRADE_SAMPLE_M
## along a segment, box-smoothed over +-GRADE_SMOOTH_RADIUS
## samples. One function, two consumers (bed, motion).
const GRADE_SAMPLE_M := 16.0
const GRADE_SMOOTH_RADIUS := 2

## Track cross-section (shared by the renderer's ribbons
## and the consist's stance, so the wheels sit on the
## rails by construction).
const BED_WIDTH := 4.4
const BED_LIFT := 0.18 ## bed top above grade
const RAIL_GAUGE_HALF := 0.75
const RAIL_WIDTH := 0.09
const RAIL_TOP := 0.30 ## rail top above grade


## Every node's station point (spec §3.2): the home node's
## is the caller-supplied doorstep point; a city's is its
## center snapped by WorldGen's lot search.
static func station_points(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2) -> Dictionary:
	var graph := derive_graph(seed, discovered, home_center)
	return _points_for_graph(graph, seed, home_station)


static func _points_for_graph(graph: Dictionary, seed: int,
		home_station: Vector2) -> Dictionary:
	var nodes: Dictionary = graph["nodes"]
	var out := {}
	for key in graph["order"]:
		if key == HOME_KEY:
			out[key] = home_station
		else:
			out[key] = WorldGen.station_point_for(
				seed, nodes[key])
	return out


## The graph's edges as physical segments: station point to
## station point (spec §2.4), in graph edge order.
static func edge_segments(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2) -> Array:
	var graph := derive_graph(seed, discovered, home_center)
	var pts := _points_for_graph(graph, seed, home_station)
	var out: Array = []
	for e in graph["edges"]:
		out.append([pts[e[0]], pts[e[1]]])
	return out


## --- Issue #246: building-avoiding routing. Jesse's
## ruling (2026-11-02): the track BENDS around buildings
## — the graph, its edges, and the stations are
## unchanged; each edge's GEOMETRY becomes a polyline
## that keeps the consist's bed clear of every derived
## building footprint. Nothing is cleared or moved.
## The router is a pure function of (seed, discovered
## set, endpoints): the obstacle field is the SHIPPED
## derivation itself — building_at fed exactly the
## per-chunk straight-segment cache generate_chunk
## receives, plus the streamer's home-plot suppression
## (the anchor rect, 96 x 96 at the home center) — so
## the router avoids precisely the buildings the world
## builds, and every peer derives the identical bend.

## Footprints are inflated by this much for the search
## simplifications (bed half-width + margin).
const ROUTE_INFLATE := 3.5
## The verification floor: no final segment may come
## closer than this to a raw footprint (the bed's half
## width — what the consist sweeps).
const ROUTE_BED_CLEAR := 2.2
## The search corridor's half width (perpendicular to
## the straight edge); failures widen it x2, twice.
const ROUTE_BAND := 64.0
## The obstacle field reaches this far past the corridor
## so verification sees every footprint a bent segment
## could approach.
const ROUTE_FIELD_PAD := 24.0

static var _route_memo := {}
## Edges that exhausted every band and fell back to the
## straight segment (with a push_error at compute time).
## The suite pins this empty over the real networks.
static var route_failures: Array = []


## The routed polyline for one graph edge, station
## point to station point (both included). Memoized;
## the value is pure in (seed, discovered, a, b).
static func routed_points(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		a: Vector2, b: Vector2) -> Array:
	# Direction-canonical (issue #246, caught by the
	# T2(E) pin): the search is not symmetric, so every
	# edge is routed in ONE canonical direction —
	# lexicographically smaller endpoint first — and
	# reversed for the caller when asked the other way.
	# Dressing (graph direction), motion (course
	# direction), and the chart therefore share the
	# identical bend on every peer.
	var flipped := false
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		var tmp := a
		a = b
		b = tmp
		flipped = true
	var out := _routed_points_canonical(seed, discovered,
		home_center, home_station, a, b)
	if flipped:
		out.reverse()
	return out


static func _routed_points_canonical(seed: int,
		discovered: Array, home_center: Vector2,
		home_station: Vector2, a: Vector2,
		b: Vector2) -> Array:
	var straight := edge_segments(seed, discovered,
		home_center, home_station)
	# The memo key names what the route actually depends
	# on: this edge plus the straight segments that come
	# within the widest possible field of it (they alone
	# shape its obstacle field). A discovery wave on the
	# far side of the world therefore does NOT invalidate
	# this edge's bend — only a nearby change re-routes.
	var near: Array = []
	for seg in straight:
		var p: Vector2 = seg[0]
		var q: Vector2 = seg[1]
		var d := 1.0e9
		if Geometry2D.segment_intersects_segment(
				a, b, p, q) != null:
			d = 0.0
		else:
			d = minf(minf(
				WorldGen._dist_to_segment(p, a, b),
				WorldGen._dist_to_segment(q, a, b)), minf(
				WorldGen._dist_to_segment(a, p, q),
				WorldGen._dist_to_segment(b, p, q)))
		if d <= 300.0:
			near.append("%f,%f,%f,%f" % [p.x, p.y, q.x, q.y])
	near.sort()
	var key := "%d|%f,%f|%f,%f|%s" % [seed, a.x, a.y,
		b.x, b.y, ",".join(near)]
	if _route_memo.has(key):
		return (_route_memo[key] as Array).duplicate()
	var out := _route_compute(seed, straight, home_center,
		a, b)
	_route_memo[key] = out.duplicate()
	return out


## Every graph edge as routed sub-segments — the track
## dressing's form of routed_points (the derivation
## keeps using the straight edge_segments: the field is
## defined against them, never against routed output).
static func routed_edge_segments(seed: int,
		discovered: Array, home_center: Vector2,
		home_station: Vector2) -> Array:
	var out: Array = []
	for seg in edge_segments(seed, discovered,
			home_center, home_station):
		var rp := routed_points(seed, discovered,
			home_center, home_station, seg[0], seg[1])
		for i in rp.size() - 1:
			out.append([rp[i], rp[i + 1]])
	return out


static func _route_compute(seed: int, straight: Array,
		home_center: Vector2, a: Vector2, b: Vector2) -> Array:
	if a.distance_to(b) < 1.0:
		return [a, b]
	var band := ROUTE_BAND
	for attempt in 3:
		var rects := _route_field(seed, straight,
			home_center, a, b, band + ROUTE_FIELD_PAD)
		if _seg_rect_dist(a, b, rects) >= ROUTE_BED_CLEAR:
			return [a, b]  # the straight edge already clears
		var raw := _route_astar(a, b, band,
			_route_blocked(rects))
		if raw.is_empty():
			band *= 2.0
			continue
		var inflated: Array = []
		for r in rects:
			inflated.append((r as Rect2).grow(ROUTE_INFLATE))
		var pulled := _route_pull(raw, inflated)
		var smoothed := _route_smooth(pulled, rects)
		var decimated := _route_decimate(smoothed, rects)
		if _route_verify(decimated, rects):
			return decimated
		if _route_verify(smoothed, rects):
			return smoothed
		if _route_verify(pulled, rects):
			return pulled
		band *= 2.0
	route_failures.append([a, b])
	push_error("[TrainNetwork] no routed path for edge ",
		a, " -> ", b, "; straight segment kept")
	return [a, b]


## The obstacle field near one edge: derived building
## footprints (anchor rects) whose lots' centers lie
## within pad of the straight segment, minus the
## home-plot suppression. Mirrors generate_chunk's own
## inputs per chunk (its seg cache + stash), so the
## field IS the built world.
static func _route_field(seed: int, straight: Array,
		home_center: Vector2, a: Vector2, b: Vector2,
		pad: float) -> Array:
	var suppress := Rect2(home_center - Vector2(48, 48),
		Vector2(96, 96))
	var out: Array = []
	var caches := {}
	var mn := a.min(b) - Vector2(pad + 16.0, pad + 16.0)
	var mx := a.max(b) + Vector2(pad + 16.0, pad + 16.0)
	for lz in range(int(floor(mn.y / WorldGen.LOT_SIZE)),
			int(floor(mx.y / WorldGen.LOT_SIZE)) + 1):
		for lx in range(int(floor(mn.x / WorldGen.LOT_SIZE)),
				int(floor(mx.x / WorldGen.LOT_SIZE)) + 1):
			var ctr := Vector2((float(lx) + 0.5)
				* WorldGen.LOT_SIZE, (float(lz) + 0.5)
				* WorldGen.LOT_SIZE)
			if WorldGen._dist_to_segment(ctr, a, b) > pad + 12.0:
				continue
			var ccx := lx >> 4
			var ccz := lz >> 4
			var ckey := "%d,%d" % [ccx, ccz]
			if not caches.has(ckey):
				caches[ckey] = {"__track_segs":
					filter_segments_for_chunk(straight,
						ccx, ccz)}
			var bb: Dictionary = WorldGen.building_at(seed,
				lx, lz, {}, caches[ckey])
			if bb.is_empty():
				continue
			var r := Rect2(Vector2(lx, lz) * WorldGen.LOT_SIZE,
				Vector2(int(bb["span_x"]), int(bb["span_z"]))
					* WorldGen.LOT_SIZE)
			if suppress.intersects(r):
				continue
			out.append(r)
	return out


## Footprint lots, stamped blocked for the search.
static func _route_blocked(rects: Array) -> Dictionary:
	var blocked := {}
	for r in rects:
		var x0 := int(floor((r as Rect2).position.x
			/ WorldGen.LOT_SIZE))
		var y0 := int(floor((r as Rect2).position.y
			/ WorldGen.LOT_SIZE))
		var x1 := int(floor(((r as Rect2).end.x - 0.01)
			/ WorldGen.LOT_SIZE))
		var y1 := int(floor(((r as Rect2).end.y - 0.01)
			/ WorldGen.LOT_SIZE))
		for ly in range(y0, y1 + 1):
			for lx in range(x0, x1 + 1):
				blocked[Vector2i(lx, ly)] = true
	return blocked


## Lot-grid A* in the edge's corridor frame. Endpoints'
## lots are always enterable (the train ends there by
## definition); diagonal steps never cut a blocked
## orthogonal neighbor (no corner squeezing). The
## heuristic is weighted (x1.25) — determinism does not
## ride on optimality: the shipped path is defined by
## the verified geometry downstream.
static func _route_astar(a: Vector2, b: Vector2,
		band_v: float, blocked: Dictionary) -> Array:
	var start_lot := Vector2i(int(floor(a.x
		/ WorldGen.LOT_SIZE)), int(floor(a.y
		/ WorldGen.LOT_SIZE)))
	var goal_lot := Vector2i(int(floor(b.x
		/ WorldGen.LOT_SIZE)), int(floor(b.y
		/ WorldGen.LOT_SIZE)))
	if start_lot == goal_lot:
		return [a, b]
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var length := a.distance_to(b)
	var gscore := {start_lot: 0.0}
	var came := {}
	var closed := {}
	var heap: Array = []  # [f, lot] with (f, x, y) order
	_route_heap_push(heap, 0.0, start_lot)
	var found := false
	var expansions := 0
	while not heap.is_empty() and expansions < 40000:
		expansions += 1
		var cur: Vector2i = _route_heap_pop(heap)
		if closed.has(cur):
			continue
		if cur == goal_lot:
			found = true
			break
		closed[cur] = true
		for d in [Vector2i(-1, -1), Vector2i(0, -1),
				Vector2i(1, -1), Vector2i(-1, 0),
				Vector2i(1, 0), Vector2i(-1, 1),
				Vector2i(0, 1), Vector2i(1, 1)]:
			var nl: Vector2i = cur + d
			if closed.has(nl):
				continue
			if blocked.has(nl) and nl != goal_lot \
					and nl != start_lot:
				continue
			if d.x != 0 and d.y != 0:
				var ox := Vector2i(cur.x + d.x, cur.y)
				var oy := Vector2i(cur.x, cur.y + d.y)
				if (blocked.has(ox) and ox != goal_lot
						and ox != start_lot) \
						or (blocked.has(oy)
						and oy != goal_lot
						and oy != start_lot):
					continue  # no corner squeezing
			var nc := Vector2((float(nl.x) + 0.5)
				* WorldGen.LOT_SIZE, (float(nl.y) + 0.5)
				* WorldGen.LOT_SIZE)
			var rel := nc - a
			if rel.dot(dir) < -24.0 \
					or rel.dot(dir) > length + 24.0 \
					or absf(rel.dot(perp)) > band_v:
				continue
			var step := 8.0 if (d.x == 0 or d.y == 0) \
				else 11.3137
			var ng := float(gscore[cur]) + step
			if ng < float(gscore.get(nl, INF)):
				gscore[nl] = ng
				came[nl] = cur
				_route_heap_push(heap,
					ng + nc.distance_to(b) * 1.25, nl)
	if not found:
		return []
	var centers: Array = [a]
	var chain: Array = []
	var cur2 := goal_lot
	while cur2 != start_lot:
		chain.push_front(cur2)
		cur2 = came[cur2]
	for l in chain:
		centers.append(Vector2((float(l.x) + 0.5)
			* WorldGen.LOT_SIZE, (float(l.y) + 0.5)
			* WorldGen.LOT_SIZE))
	centers.append(b)
	var out: Array = []
	for p in centers:
		if out.is_empty() or (out[out.size() - 1] as Vector2).distance_to(p) > 0.01:
			out.append(p)
	return out


## Binary heap over (f, lot.x, lot.y) — a total order,
## so extraction order is insertion-independent and the
## search is identical on every peer.
static func _route_heap_push(heap: Array, f: float,
		lot: Vector2i) -> void:
	heap.append([f, lot])
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _route_heap_less(heap[i], heap[parent]):
			break
		var tmp = heap[i]
		heap[i] = heap[parent]
		heap[parent] = tmp
		i = parent


static func _route_heap_pop(heap: Array) -> Vector2i:
	var top: Vector2i = heap[0][1]
	var last = heap[heap.size() - 1]
	heap.resize(heap.size() - 1)
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := i * 2 + 2
			var smallest := i
			if l < heap.size() and _route_heap_less(
					heap[l], heap[smallest]):
				smallest = l
			if r < heap.size() and _route_heap_less(
					heap[r], heap[smallest]):
				smallest = r
			if smallest == i:
				break
			var tmp = heap[i]
			heap[i] = heap[smallest]
			heap[smallest] = tmp
			i = smallest
	return top


static func _route_heap_less(x: Array, y: Array) -> bool:
	if float(x[0]) != float(y[0]):
		return float(x[0]) < float(y[0])
	var xl: Vector2i = x[1]
	var yl: Vector2i = y[1]
	if xl.x != yl.x:
		return xl.x < yl.x
	return xl.y < yl.y


## Greedy farthest-visible simplification against the
## inflated field. Visibility is a preference, never a
## trap: when even the next raw point is not visible
## (an exempt endpoint lot's approach), the raw step is
## kept and the raw-rect verification decides.
static func _route_pull(pts: Array, inflated: Array) -> Array:
	var out: Array = [pts[0]]
	var i := 0
	while i < pts.size() - 1:
		var hi := mini(i + 64, pts.size() - 1)
		var j := hi
		while j > i + 1 and _seg_hits_any(pts[i], pts[j],
				inflated):
			j -= 1
		out.append(pts[j])
		i = j
	return out


## Corner rounding: each interior vertex is replaced by
## a quadratic Bezier arc (the vertex as control point,
## samples at .25/.5/.75) whose radius starts at
## min(14 m, 40% of the shorter leg) and halves while
## any arc segment would breach the bed clearance — a
## corner the geometry cannot round keeps its vertex.
## Two rounds compose arcs on shared legs. The
## candidate as a whole is still accepted only through
## _route_verify; Chaikin-style uniform cuts were tried
## first and measurably stalled at city corners (the
## 25% cut dips a hair past the floor and is rejected
## whole, leaving the grid's 90-degree turns standing).
static func _route_smooth(pts: Array, rects: Array) -> Array:
	var cur := pts.duplicate()
	for round_i in 2:
		var out: Array = [cur[0]]
		for i in range(1, cur.size() - 1):
			var v: Vector2 = cur[i]
			var pin := v - (cur[i - 1] as Vector2)
			var pout := (cur[i + 1] as Vector2) - v
			var lin := pin.length()
			var lout := pout.length()
			if lin < 0.01 or lout < 0.01:
				out.append(v)
				continue
			var din := pin / lin
			var dout := pout / lout
			var d := minf(14.0, 0.4 * minf(lin, lout))
			var placed := false
			while d >= 1.5:
				var a1 := v - din * d
				var a2 := v + dout * d
				var samples := [a1,
					_route_bez(a1, v, a2, 0.25),
					_route_bez(a1, v, a2, 0.5),
					_route_bez(a1, v, a2, 0.75), a2]
				var ok := true
				for j in samples.size() - 1:
					if _seg_rect_dist(samples[j],
							samples[j + 1], rects) \
							< ROUTE_BED_CLEAR:
						ok = false
						break
				if ok:
					for s in samples:
						out.append(s)
					placed = true
					break
				d *= 0.5
			if not placed:
				out.append(v)
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


static func _route_bez(a: Vector2, c: Vector2,
		b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * (u * u) + c * (2.0 * u * t) + b * (t * t)


## The sharpest direction change along a point list,
## in degrees.
static func _route_max_turn(pts: Array) -> float:
	var worst := 0.0
	for i in range(1, pts.size() - 1):
		var d1 := ((pts[i] as Vector2)
			- (pts[i - 1] as Vector2)).normalized()
		var d2 := ((pts[i + 1] as Vector2)
			- (pts[i] as Vector2)).normalized()
		if d1 == Vector2.ZERO or d2 == Vector2.ZERO:
			continue
		worst = maxf(worst, rad_to_deg(acos(
			clampf(d1.dot(d2), -1.0, 1.0))))
	return worst


## Point-count cleanup that respects the smoothing: a
## point is dropped only when it is close to the last
## kept point, the merged segment keeps the bed
## clearance, AND the point deviates from the merged
## chord by at most 35 degrees on both sides — merging
## across a rounded corner's samples would re-sharpen
## the very turn the arc spent itself softening.
static func _route_decimate(pts: Array, rects: Array) -> Array:
	if pts.size() < 3:
		return pts.duplicate()
	var out: Array = [pts[0]]
	for i in range(1, pts.size() - 1):
		var p: Vector2 = pts[i]
		var last: Vector2 = out[out.size() - 1]
		var nxt: Vector2 = pts[i + 1]
		if last.distance_to(p) >= 4.0 \
				or _seg_rect_dist(last, nxt, rects) \
					< ROUTE_BED_CLEAR:
			out.append(p)
			continue
		# The merge is allowed only if the turns it
		# CREATES stay plausible: at `last` (its incoming
		# segment against the merged chord) and at `nxt`
		# (the merged chord against its outgoing one).
		var turn_ok := true
		if out.size() >= 2:
			turn_ok = _route_angle(out[out.size() - 2],
				last, last, nxt) <= 40.0
		if turn_ok and i + 2 < pts.size():
			turn_ok = _route_angle(last, nxt, nxt,
				pts[i + 2]) <= 40.0
		if not turn_ok:
			out.append(p)
	out.append(pts[pts.size() - 1])
	return out


## The angle between two segments, in degrees.
static func _route_angle(a1: Vector2, a2: Vector2,
		b1: Vector2, b2: Vector2) -> float:
	var d1 := (a2 - a1).normalized()
	var d2 := (b2 - b1).normalized()
	if d1 == Vector2.ZERO or d2 == Vector2.ZERO:
		return 0.0
	return rad_to_deg(acos(clampf(d1.dot(d2), -1.0, 1.0)))


## The verification pass (pinned behavior, issue #246):
## every segment of the candidate path keeps at least
## ROUTE_BED_CLEAR from every raw footprint.
static func _route_verify(pts: Array, rects: Array) -> bool:
	for i in pts.size() - 1:
		if _seg_rect_dist(pts[i], pts[i + 1], rects) \
				< ROUTE_BED_CLEAR - 0.001:
			return false
	return true


## Minimum distance from a segment to a set of rects
## (bbox-pruned per rect).
static func _seg_rect_dist(a: Vector2, b: Vector2,
		rects: Array) -> float:
	var best := 1.0e9
	var bb := Rect2(a.min(b), (b - a).abs()).grow(64.0)
	for r in rects:
		if not bb.intersects(r):
			continue
		best = minf(best, _seg_one_rect_dist(a, b, r))
	return best


static func _seg_one_rect_dist(a: Vector2, b: Vector2,
		r: Rect2) -> float:
	if _seg_hits_rect(a, b, r):
		return 0.0
	var best := 1.0e9
	var corners := [r.position,
		r.position + Vector2(r.size.x, 0), r.end,
		r.position + Vector2(0, r.size.y)]
	for c in corners:
		best = minf(best, WorldGen._dist_to_segment(c, a, b))
	for p in [a, b]:
		var cl := Vector2(clampf(p.x, r.position.x, r.end.x),
			clampf(p.y, r.position.y, r.end.y))
		best = minf(best, p.distance_to(cl))
	return best


static func _seg_hits_any(a: Vector2, b: Vector2,
		rects: Array) -> bool:
	var bb := Rect2(a.min(b), (b - a).abs())
	for r in rects:
		if bb.intersects(r) and _seg_hits_rect(a, b, r):
			return true
	return false


static func _seg_hits_rect(a: Vector2, b: Vector2,
		r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var corners := [r.position,
		r.position + Vector2(r.size.x, 0), r.end,
		r.position + Vector2(0, r.size.y)]
	for i in 4:
		var c: Vector2 = corners[i]
		var d: Vector2 = corners[(i + 1) % 4]
		if Geometry2D.segment_intersects_segment(
				a, b, c, d) != null:
			return true
	return false


## The road function's per-chunk question, track-shaped:
## the segments that can cross (or come within margin of)
## chunk (cx, cz).
static func track_segments_near_chunk(seed: int, cx: int,
		cz: int, discovered: Array, home_center: Vector2,
		home_station: Vector2) -> Array:
	return filter_segments_for_chunk(edge_segments(seed,
		discovered, home_center, home_station), cx, cz)


## The geometric half of the per-chunk question, over a
## precomputed segment list (the streamer's cached form).
static func filter_segments_for_chunk(segments: Array,
		cx: int, cz: int) -> Array:
	var rect := Rect2(float(cx) * WorldGen.CHUNK_SIZE,
		float(cz) * WorldGen.CHUNK_SIZE,
		WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE)
	rect = rect.grow(SEGMENT_CHUNK_MARGIN)
	var out: Array = []
	for seg in segments:
		var t := _clip_t(seg[0], seg[1], rect)
		if t.x <= t.y:
			out.append(seg)
	return out


## A segment's parameter range inside a rect, as
## Vector2(t0, t1); empty (t0 > t1) when it misses. The
## streamer clips geometry with the same math, so the
## query and the built bed always agree.
static func _clip_t(a: Vector2, b: Vector2,
		rect: Rect2) -> Vector2:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	if absf(d.x) < 0.000001:
		if a.x < rect.position.x or a.x > rect.end.x:
			return Vector2(1.0, 0.0)
	else:
		var ta := (rect.position.x - a.x) / d.x
		var tb := (rect.end.x - a.x) / d.x
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if absf(d.y) < 0.000001:
		if a.y < rect.position.y or a.y > rect.end.y:
			return Vector2(1.0, 0.0)
	else:
		var ta := (rect.position.y - a.y) / d.y
		var tb := (rect.end.y - a.y) / d.y
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)


## The segment clipped to a chunk's own rect (no margin),
## as [Vector2, Vector2] world points, or [] when the
## segment does not cross the chunk.
static func clip_segment_to_chunk(a: Vector2, b: Vector2,
		cx: int, cz: int) -> Array:
	var rect := Rect2(float(cx) * WorldGen.CHUNK_SIZE,
		float(cz) * WorldGen.CHUNK_SIZE,
		WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE)
	var t := _clip_t(a, b, rect)
	if t.x > t.y:
		return []
	return [a + (b - a) * t.x, a + (b - a) * t.y]


static func _grade_raw(seed: int, a: Vector2, dir: Vector2,
		d: float) -> float:
	var p := a + dir * d
	return WorldGen.height_at(seed, p.x, p.y)


static func _grade_smoothed(seed: int, a: Vector2,
		dir: Vector2, length: float, n: int, k: int) -> float:
	var sum := 0.0
	var count := 0
	for j in range(maxi(0, k - GRADE_SMOOTH_RADIUS),
			mini(n, k + GRADE_SMOOTH_RADIUS) + 1):
		sum += _grade_raw(seed, a, dir,
			minf(float(j) * GRADE_SAMPLE_M, length))
		count += 1
	return sum / float(count)


## THE grade function (spec §3.3): the smoothed height of
## the track bed's centerline at `dist_along` meters from
## a toward b. The rendered bed and (T3) the train's
## motion profile both read this, so they agree exactly.
static func grade_height(seed: int, a: Vector2, b: Vector2,
		dist_along: float) -> float:
	var length := a.distance_to(b)
	if length <= 0.001:
		return WorldGen.height_at(seed, a.x, a.y)
	var dir := (b - a) / length
	var n := maxi(1, int(ceil(length / GRADE_SAMPLE_M)))
	var d := clampf(dist_along, 0.0, length)
	var i := mini(int(floor(d / GRADE_SAMPLE_M)), n - 1)
	var d0 := float(i) * GRADE_SAMPLE_M
	var d1 := minf(float(i + 1) * GRADE_SAMPLE_M, length)
	var f := 0.0
	if d1 > d0:
		f = (d - d0) / (d1 - d0)
	return lerpf(_grade_smoothed(seed, a, dir, length, n, i),
		_grade_smoothed(seed, a, dir, length, n, i + 1), f)


## The resting consist (T2): locomotive + car as pure box
## facts on the home node's first edge (graph order), at
## the home station — {kind, at (XZ center), grade, size,
## y_off (center height above rail top), yaw, color} per
## box, frames/roofs/chimney included. The streamer builds
## the boxes whose center lies in its chunk; T3 takes the
## train over from here.
## Issue #247 C1: the consist's rearmost point, in metres
## behind the train's reference point (the station point /
## path point train_position reports) — the caboose
## platform deck's rear face (-16.2 centre, 1.2 long).
## The walk-out landing derives from this one constant,
## so the box geometry and the exit math cannot drift.
const CABOOSE_REAR_OFFSET := 16.8


## The mid-ride walk-out landing (issue #247 C1, spec
## §4.5): the caboose's rear, then ~3 m perpendicular
## from the track centerline, beside the track — from the
## train's CURRENT parametric position + direction at exit
## time. Pure (seed, discovered, state, elapsed); the
## caller validates it through clear_spawn_point and
## re-samples Y — never carried from the rail grade.
static func walkout_point(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		state: Dictionary, elapsed_msec: int) -> Vector2:
	var tp := train_position(seed, discovered, home_center,
		home_station, state, elapsed_msec)
	var pos2 := Vector2((tp["pos"] as Vector3).x,
		(tp["pos"] as Vector3).z)
	var yaw := float(tp["yaw"])
	var fwd := Vector2(sin(yaw), cos(yaw))
	var perp := Vector2(-fwd.y, fwd.x)
	var rear := pos2 - fwd * CABOOSE_REAR_OFFSET
	return rear + perp * 3.0


static func consist_boxes(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2) -> Array:
	var graph := derive_graph(seed, discovered, home_center)
	var pts := _points_for_graph(graph, seed, home_station)
	var other := ""
	for e in graph["edges"]:
		if e[0] == HOME_KEY:
			other = e[1]
			break
		if e[1] == HOME_KEY:
			other = e[0]
			break
	if other == "":
		return []
	var target: Vector2 = pts[other]
	var dir := (target - home_station).normalized()
	var yaw := atan2(dir.x, dir.y)
	var out: Array = []
	# kind, dist along dir, size, center height above rail
	# top, color — the consist centered on the station:
	# locomotive ahead (+), car behind (-).
	var parts := [
		["loco_frame", 4.6, Vector3(2.6, 0.5, 7.0), 0.25,
			Color(0.07, 0.07, 0.08)],
		["loco", 4.6, Vector3(2.9, 2.6, 7.6), 1.8,
			Color(0.13, 0.24, 0.16)],
		["loco_roof", 4.6, Vector3(2.5, 0.35, 7.0), 3.28,
			Color(0.08, 0.08, 0.09)],
		["loco_chimney", 7.2, Vector3(0.55, 0.8, 0.55), 3.85,
			Color(0.05, 0.05, 0.05)],
		["car_frame", -5.0, Vector3(2.6, 0.5, 8.6), 0.25,
			Color(0.07, 0.07, 0.08)],
		["car", -5.0, Vector3(2.9, 2.4, 9.2), 1.7,
			Color(0.42, 0.20, 0.13)],
		["car_roof", -5.0, Vector3(2.6, 0.3, 8.6), 3.05,
			Color(0.25, 0.13, 0.09)],
		# Issue #247 C1 (Amendment 1, open caboose): a rear
		# car behind the passenger car — same cross-section,
		# shorter, with an open rear platform deck (no rear
		# wall) so riders can walk out the back mid-ride.
		# Centers: caboose body -12.6 (spans -15.6..-9.6,
		# flush against the car's rear face at -9.6);
		# platform deck -16.2 (spans -16.8..-15.6).
		["caboose_frame", -12.6, Vector3(2.6, 0.5, 6.0), 0.25,
			Color(0.07, 0.07, 0.08)],
		["caboose", -12.6, Vector3(2.9, 2.4, 6.0), 1.7,
			Color(0.30, 0.16, 0.10)],
		["caboose_roof", -12.6, Vector3(2.6, 0.3, 6.0), 3.05,
			Color(0.20, 0.11, 0.08)],
		["caboose_platform", -16.2, Vector3(2.6, 0.3, 1.2),
			0.15, Color(0.20, 0.14, 0.10)],
	]
	for p in parts:
		var at: Vector2 = home_station + dir * float(p[1])
		out.append({"kind": p[0], "at": at,
			"grade": grade_height(seed, home_station,
				target, float(p[1])),
			"size": p[2], "y_off": float(p[3]),
			"yaw": yaw, "color": p[4]})
	return out


## --- Phase T3: the ride ------------------------------------
## The train's state is a plain Dictionary owned by the
## server (Dungeon.train_state; NetworkManager carries its
## rpcs): {status: "idle"|"moving", at, course, path,
## duration_msec, riders, empty_run}. Peers never share a
## clock: every state send carries the server's elapsed
## msec and each receiver stamps its own local departure
## tick, so position is a pure function of (state, elapsed)
## computed identically everywhere — client-compute applied
## to motion (spec §4.3), no per-frame position RPCs.

## The state of a fresh run: idle at home, nobody aboard.
static func initial_state() -> Dictionary:
	return {"status": "idle", "at": "home", "course": [],
		"path": [], "duration_msec": 0, "riders": {},
		"empty_run": false, "legs": []}


## Route a plotted course (spec §2.3 applied per leg):
## consecutive nodes routed over the graph, joints
## deduplicated. Returns {nodes, length} with length the
## summed station-point distance; an unroutable course
## yields length -1.
static func route_path(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		course: Array) -> Dictionary:
	var nodes: Array = []
	var length := 0.0
	if course.size() < 2:
		return {"nodes": nodes, "length": -1.0}
	var pts := station_points(seed, discovered, home_center,
		home_station)
	for i in course.size() - 1:
		var leg := route(seed, discovered, home_center,
			str(course[i]), str(course[i + 1]))
		if leg.size() < 2:
			return {"nodes": [], "length": -1.0}
		for k in leg:
			if nodes.is_empty() or str(nodes[nodes.size() - 1]) != str(k):
				nodes.append(str(k))
	if nodes.size() < 2:
		return {"nodes": [], "length": -1.0}
	# Length in station-point meters (route() measures
	# center-to-center; the physical path runs point to
	# point — recompute on the points so duration and
	# position share one metric).
	var ppts := _path_points(seed, discovered,
		home_center, home_station, pts, nodes)
	length = 0.0
	for i in ppts.size() - 1:
		length += (ppts[i] as Vector2).distance_to(ppts[i + 1])
	return {"nodes": nodes, "length": length}


## The physical point list of a node path: station
## points with each edge's routed bend in between
## (issue #246 — position, grade, duration, and the
## chart's ridden polyline all share this one metric).
static func _path_points(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		pts: Dictionary, nodes: Array) -> Array:
	var out: Array = []
	var prev := Vector2.ZERO
	for k in nodes:
		var p: Vector2 = pts[str(k)]
		if not out.is_empty():
			var rp := routed_points(seed, discovered,
				home_center, home_station, prev, p)
			for j in range(1, rp.size() - 1):
				out.append(rp[j])
		out.append(p)
		prev = p
	return out


## Ride duration for a path length at TRAIN_SPEED (spec
## §4.2: duration is real).
static func duration_msec_for(length_m: float) -> int:
	return int(round(length_m / TRAIN_SPEED * 1000.0))


## A node's station frame: {pt, dir, perp, side} — dir
## along its first incident edge, side toward its
## settlement center (the platform side). Shared by the
## streamer's station builder, the disembark point and
## WorldRoot's placement so all three agree by construction.
static func station_frame(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		key: String) -> Dictionary:
	var g := derive_graph(seed, discovered, home_center)
	var pts := _points_for_graph(g, seed, home_station)
	var pt: Vector2 = pts.get(key, home_station)
	var dir := Vector2(0, 1)
	for e in g["edges"]:
		var a := str(e[0])
		var b := str(e[1])
		if a == key or b == key:
			var other: Vector2 = pts[b] if a == key else pts[a]
			dir = (other - pt).normalized()
			break
	var perp := Vector2(-dir.y, dir.x)
	var center2: Vector2 = (g["nodes"] as Dictionary).get(
		key, pt)
	var side := 1.0
	if (center2 - pt).dot(perp) < 0.0:
		side = -1.0
	return {"pt": pt, "dir": dir, "perp": perp, "side": side}


## The platform slab's center for a node (the streamer's
## builder and the disembark placement read the same point).
## Issue #246 fix 2: the plain offset — frame side, fixed
## 4.1 m — can land inside the building beside the station
## (the characterization's station "0,2" platform sat at
## distance 0.0 from a 23-floor footprint; "0,-2" at
## 0.03 m). The center is VALIDATED against the derived
## footprints: the frame side first, then the flipped
## side, then deterministic shifts along the track; the
## first candidate whose slab rect (3.6 x 16, the built
## size) keeps 0.6 m from every footprint wins. When no
## candidate clears, the plain offset stands and the
## WorldRoot disembark backstop is the last line.
static func platform_center(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		key: String) -> Vector2:
	var f := station_frame(seed, discovered, home_center,
		home_station, key)
	var pt: Vector2 = f["pt"]
	var dir: Vector2 = f["dir"]
	var perp: Vector2 = f["perp"]
	var side := float(f["side"])
	var plain := pt + perp * (side * (BED_WIDTH * 0.5 + 1.9))
	var straight := edge_segments(seed, discovered,
		home_center, home_station)
	var rects := _route_field(seed, straight, home_center,
		pt - dir * 72.0, pt + dir * 72.0, 40.0)
	if rects.is_empty():
		return plain
	for shift in [0.0, 8.0, -8.0, 16.0, -16.0, 24.0, -24.0,
			28.0, -28.0, 32.0, -32.0, 40.0, -40.0, 48.0,
			-48.0, 56.0, -56.0, 64.0, -64.0]:
		for s in [side, -side]:
			var c: Vector2 = pt + perp * (s * (BED_WIDTH * 0.5 + 1.9)) \
				+ dir * shift
			if _plat_clear(c, dir, perp, rects):
				return c
	return plain


## A platform candidate's clearance: the slab rect
## (half extents 8.0 along dir, 1.8 along perp — the
## built 16.0 x 3.6) keeps >= 0.6 m from every footprint.
static func _plat_clear(c: Vector2, dir: Vector2,
		perp: Vector2, rects: Array) -> bool:
	for r in rects:
		if _obb_aabb_dist(c, dir, perp, 8.0, 1.8, r) < 0.6:
			return false
	return true


## Exact distance between an oriented rect (center,
## axes, half extents) and an axis-aligned rect: zero on
## overlap (SAT over both rects' axes), else the least
## vertex-to-rect distance over both directions.
static func _obb_aabb_dist(c: Vector2, dir: Vector2,
		perp: Vector2, hd: float, hp: float, r: Rect2) -> float:
	var oc: Array = []
	for su in [-1.0, 1.0]:
		for sv in [-1.0, 1.0]:
			oc.append(c + dir * (su * hd) + perp * (sv * hp))
	var rc := [r.position, r.position + Vector2(r.size.x, 0),
		r.end, r.position + Vector2(0, r.size.y)]
	for axis in [dir, perp, Vector2(1, 0), Vector2(0, 1)]:
		var mn_o := 1.0e9
		var mx_o := -1.0e9
		var mn_r := 1.0e9
		var mx_r := -1.0e9
		for p in oc:
			var d := (p as Vector2).dot(axis)
			mn_o = minf(mn_o, d)
			mx_o = maxf(mx_o, d)
		for p in rc:
			var d := (p as Vector2).dot(axis)
			mn_r = minf(mn_r, d)
			mx_r = maxf(mx_r, d)
		if mx_o < mn_r or mx_r < mn_o:
			break  # separated on this axis: not overlapping
		if axis == Vector2(0, 1):
			return 0.0  # overlapped on every axis
	var best := 1.0e9
	for p in oc:
		best = minf(best, _point_rect_dist(p, r))
	for p in rc:
		var rel := (p as Vector2) - c
		var u := rel.dot(dir)
		var v := rel.dot(perp)
		var du := maxf(absf(u) - hd, 0.0)
		var dv := maxf(absf(v) - hp, 0.0)
		if du == 0.0 and dv == 0.0:
			return 0.0
		best = minf(best, Vector2(du, dv).length())
	return best


static func _point_rect_dist(p: Vector2, r: Rect2) -> float:
	var cl := Vector2(clampf(p.x, r.position.x, r.end.x),
		clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(cl)


## The disembark backstop's question (issue #246 fix 2,
## WorldRoot's half): p itself when it keeps 0.7 m from
## every footprint near it, else the first clear point
## on a deterministic ring scan (2 m steps to 12 m, 8
## directions), else p unchanged — placement next to a
## station should never need the far rings; the scan is
## a guarantee of effort, not an expectation.
static func clear_spawn_point(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		p: Vector2) -> Vector2:
	var straight := edge_segments(seed, discovered,
		home_center, home_station)
	var rects := _route_field(seed, straight, home_center,
		p, p + Vector2(0.01, 0.0), 20.0)
	if _point_clear(p, rects):
		return p
	for ring in [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]:
		for k in 8:
			var ang := float(k) * PI * 0.25
			var c: Vector2 = p + Vector2(cos(ang), sin(ang)) * ring
			if _point_clear(c, rects):
				return c
	return p


static func _point_clear(p: Vector2, rects: Array) -> bool:
	for r in rects:
		if _point_rect_dist(p, r) < 0.7:
			return false
	return true


## Where a rider steps out: on the destination platform,
## standing on the slab (grade + platform height).
static func platform_point(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		key: String) -> Vector3:
	var c := platform_center(seed, discovered, home_center,
		home_station, key)
	return Vector3(c.x, WorldGen.height_at(seed, c.x, c.y)
		+ 0.55, c.y)


## The train's world position for a state at an elapsed
## time: {mode, pos (Vector3, on the rails), yaw, pitch,
## at (when idle), leg}. Idle reads the station point;
## moving walks the routed path's station points at
## TRAIN_SPEED along T2's grade profile.
static func train_position(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		state: Dictionary, elapsed_msec: int) -> Dictionary:
	var pts := station_points(seed, discovered, home_center,
		home_station)
	if str(state.get("status", "idle")) != "moving":
		var at := str(state.get("at", "home"))
		var f := station_frame(seed, discovered, home_center,
			home_station, at)
		var pt: Vector2 = pts.get(at, home_station)
		return {"mode": "idle", "at": at,
			"pos": Vector3(pt.x, WorldGen.height_at(seed,
				pt.x, pt.y) + RAIL_TOP, pt.y),
			"yaw": atan2((f["dir"] as Vector2).x,
				(f["dir"] as Vector2).y),
			"pitch": 0.0, "leg": 0}
	var path: Array = state.get("path", [])
	var ppts := _path_points(seed, discovered,
		home_center, home_station, pts, path)
	if ppts.size() < 2:
		return {"mode": "idle", "at": "home",
			"pos": Vector3(home_station.x, WorldGen.height_at(
				seed, home_station.x, home_station.y)
				+ RAIL_TOP, home_station.y),
			"yaw": 0.0, "pitch": 0.0, "leg": 0}
	var total := 0.0
	for i in ppts.size() - 1:
		total += (ppts[i] as Vector2).distance_to(ppts[i + 1])
	var traveled := clampf(elapsed_msec / 1000.0
		* TRAIN_SPEED, 0.0, total)
	return _position_at(seed, ppts, traveled)


## Position + grade + heading at a traveled distance along
## a point path (the pitch samples the same function 9 m
## either side, so the consist's tilt is the grade's own).
static func _position_at(seed: int, ppts: Array,
		traveled: float) -> Dictionary:
	var acc := 0.0
	var seg := 0
	var local := 0.0
	for i in ppts.size() - 1:
		var seglen := (ppts[i] as Vector2).distance_to(
			ppts[i + 1])
		if traveled <= acc + seglen or i == ppts.size() - 2:
			seg = i
			local = clampf(traveled - acc, 0.0, seglen)
			break
		acc += seglen
	var a: Vector2 = ppts[seg]
	var b: Vector2 = ppts[seg + 1]
	var seglen2 := a.distance_to(b)
	var pos2 := a.lerp(b, local / maxf(seglen2, 0.001))
	var grade := grade_height(seed, a, b, local)
	var dir := (b - a).normalized()
	var total := 0.0
	for i in ppts.size() - 1:
		total += (ppts[i] as Vector2).distance_to(ppts[i + 1])
	var back := clampf(traveled - 9.0, 0.0, total)
	var ahead := clampf(traveled + 9.0, 0.0, total)
	var pitch := 0.0
	if ahead > back:
		pitch = atan2(_grade_along(seed, ppts, ahead)
			- _grade_along(seed, ppts, back), ahead - back)
	return {"mode": "moving", "at": "",
		"pos": Vector3(pos2.x, grade + RAIL_TOP, pos2.y),
		"yaw": atan2(dir.x, dir.y), "pitch": pitch, "leg": seg}


## The grade at a traveled distance along a point path.
static func _grade_along(seed: int, ppts: Array,
		traveled: float) -> float:
	var acc := 0.0
	for i in ppts.size() - 1:
		var seglen := (ppts[i] as Vector2).distance_to(
			ppts[i + 1])
		if traveled <= acc + seglen or i == ppts.size() - 2:
			return grade_height(seed, ppts[i], ppts[i + 1],
				clampf(traveled - acc, 0.0, seglen))
		acc += seglen
	return 0.0


## --- Issue #244 T4: the chart model (§5). The chart is
## a consumer: nodes at their city CENTERS (schematic,
## not station points), edges from the derived graph, and
## the train's marker — at a node, or on its current leg
## interpolated over the path's station-point lengths.
## Undiscovered cities are absent by construction: the
## model is built from the discovered set alone.
static func chart_model(seed: int, discovered: Array,
		home_center: Vector2, home_station: Vector2,
		train_state: Dictionary, elapsed_msec: int) \
		-> Dictionary:
	var g := derive_graph(seed, discovered, home_center)
	var train: Dictionary = {"mode": "at",
		"at": String(train_state.get("at", HOME_KEY)),
		"a": "", "b": "", "t": 0.0}
	if String(train_state.get("status", "idle")) \
			== "moving":
		var path: Array = train_state.get("path", [])
		if path.size() >= 2:
			var pts := station_points(seed, discovered,
				home_center, home_station)
			var traveled := clampf(
				float(elapsed_msec) / 1000.0 * TRAIN_SPEED,
				0.0, 1.0e12)
			var acc := 0.0
			for i in path.size() - 1:
				var pa: Vector2 = pts.get(path[i],
					Vector2.ZERO)
				var pb: Vector2 = pts.get(path[i + 1],
					Vector2.ZERO)
				# The leg's length is its ROUTED length
				# (issue #246), so the marker's fraction
				# tracks the train's real progress even
				# though the chart draws it schematically.
				var seglen := 0.0
				var rp := routed_points(seed, discovered,
					home_center, home_station, pa, pb)
				for j in rp.size() - 1:
					seglen += (rp[j] as Vector2).distance_to(rp[j + 1])
				if traveled <= acc + seglen \
						or i == path.size() - 2:
					train = {"mode": "leg",
						"a": String(path[i]),
						"b": String(path[i + 1]),
						"t": clampf((traveled - acc)
							/ maxf(seglen, 0.001),
							0.0, 1.0)}
					break
				acc += seglen
	return {"nodes": g["nodes"], "order": g["order"],
		"edges": g["edges"], "train": train}
