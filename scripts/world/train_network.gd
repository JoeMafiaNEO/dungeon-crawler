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
