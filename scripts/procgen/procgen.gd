class_name ProcGen
extends RefCounted
## Seeded procedural level generator.
##
## MULTIPLAYER CONTRACT: generate() is a pure function of (theme, seed).
## It uses exactly one RandomNumberGenerator created from the seed, never
## touches the global RNG, and never iterates Dictionaries (key order is not
## guaranteed). Given the same seed, every peer builds a byte-identical
## LevelLayout, so only the seed (one int) needs to cross the network.

const _MOB_SPAWN_COUNT := 14
const _PLAYER_SPAWN_COUNT := 4


static func generate(theme: LevelTheme, seed_value: int) -> LevelLayout:
	var rng := RandomNumberGenerator.new()
	# Salt the seed with the theme id so the same numeric seed yields a
	# distinct map per theme. unicode_at() is deterministic across platforms.
	var salt := 0
	for i in theme.theme_id.length():
		salt = salt * 31 + theme.theme_id.unicode_at(i)
	rng.seed = seed_value + salt

	var layout := LevelLayout.new()
	layout.grid_size = theme.grid_size
	layout.cell_size = theme.cell_size
	var n := theme.grid_size
	layout.grid = PackedByteArray()
	layout.grid.resize(n * n) # zeroed = FLOOR

	# Border walls.
	for c in n:
		for k in [0, n - 1]:
			layout.grid[layout.idx(c, k)] = LevelLayout.WALL
			layout.grid[layout.idx(k, c)] = LevelLayout.WALL

	_place_obstacles(layout, theme, rng)
	if theme.maze_walls:
		_carve_maze(layout, theme, rng)
	_enforce_connectivity(layout)
	_place_props(layout, theme, rng)
	_place_torches(layout, theme, rng)
	_place_spawns(layout, theme, rng)

	return layout


# --- Obstacles ---

static func _place_obstacles(layout: LevelLayout, theme: LevelTheme, rng: RandomNumberGenerator) -> void:
	if theme.maze_walls:
		return # the maze carver owns all obstacles for this theme
	if theme.obstacle_entries.is_empty():
		return
	var n := layout.grid_size
	var center := float(n - 1) * 0.5
	var count := rng.randi_range(theme.obstacle_blobs_min, theme.obstacle_blobs_max)
	for i in count:
		var entry := _pick_weighted(rng, theme.obstacle_entries)
		var size: int = maxi(1, int(entry.get("size", 1)))
		# Try several positions; keep the first fully-free convex block.
		for attempt in 24:
			var cx := rng.randi_range(1, n - 1 - size)
			var cz := rng.randi_range(1, n - 1 - size)
			if not _block_is_free(layout, cx, cz, size, center, theme.clear_radius):
				continue
			for dx in size:
				for dz in size:
					layout.grid[layout.idx(cx + dx, cz + dz)] = LevelLayout.OBSTACLE
			layout.props.append({
				"type": str(entry.get("type", "rock")),
				"pos": _block_center_world(layout, cx, cz, size),
				"rot": rng.randf_range(0.0, TAU),
				"scl": float(size),
				"obstacle_visual": true,
			})
			break


static func _block_is_free(layout: LevelLayout, cx: int, cz: int, size: int, center: float, clear_radius: int) -> bool:
	for dx in size:
		for dz in size:
			var x := cx + dx
			var z := cz + dz
			if layout.cell_at(x, z) != LevelLayout.FLOOR:
				return false
			# Keep the spawn clearing free.
			var dcx := float(x) - center
			var dcz := float(z) - center
			if dcx * dcx + dcz * dcz < float(clear_radius * clear_radius):
				return false
	return true


static func _block_center_world(layout: LevelLayout, cx: int, cz: int, size: int) -> Vector3:
	var a := layout.cell_to_world(cx, cz)
	var b := layout.cell_to_world(cx + size - 1, cz + size - 1)
	return (a + b) * 0.5


# --- Maze (backrooms-style labyrinth for maze_walls themes) ---

## Fills the interior with solid rock, then carves winding 1-cell corridors
## with a recursive backtracker starting at the center. Everything carved is
## connected to the center by construction. Dead ends are recorded for key
## placement. Maze cells render as dark "mazewall" obstacle boxes.
static func _carve_maze(layout: LevelLayout, theme: LevelTheme, rng: RandomNumberGenerator) -> void:
	var n := layout.grid_size
	var center := n / 2
	# Fill interior with rock (keep the border walls).
	for cz in range(1, n - 1):
		for cx in range(1, n - 1):
			layout.grid[layout.idx(cx, cz)] = LevelLayout.OBSTACLE
	# Carve on a 2-cell room grid; rooms sit at odd coordinates.
	var mw := n / 2 - 1 # rooms per side
	var visited := {}
	var start := Vector2i(mw / 2, mw / 2)
	var stack: Array[Vector2i] = [start]
	visited[start] = true
	_carve_room(layout, start)
	var dead_rooms: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var cur: Vector2i = stack[stack.size() - 1]
		var options: Array[Vector2i] = []
		for d in dirs:
			var nb := cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= mw or nb.y >= mw:
				continue
			if not visited.has(nb):
				options.append(nb)
		if options.is_empty():
			stack.pop_back()
			# Dead end (not the start): candidate key spot.
			if cur != start and _room_open_count(layout, cur) == 1:
				dead_rooms.append(cur)
			continue
		var next: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		visited[next] = true
		# Knock through the wall between cur and next.
		var wall := Vector2i(cur.x * 2 + 1 + (next.x - cur.x), cur.y * 2 + 1 + (next.y - cur.y))
		layout.grid[layout.idx(wall.x, wall.y)] = LevelLayout.FLOOR
		_carve_room(layout, next)
		stack.append(next)
	# Wide-open arena around the spawn.
	var cr := theme.clear_radius + 1
	for dz in range(-cr, cr + 1):
		for dx in range(-cr, cr + 1):
			var cx := center + dx
			var cz := center + dz
			if layout.in_bounds(cx, cz):
				layout.grid[layout.idx(cx, cz)] = LevelLayout.FLOOR
	# Record dead-end world positions for key placement.
	for r in dead_rooms:
		var wx := r.x * 2 + 1
		var wz := r.y * 2 + 1
		if layout.in_bounds(wx, wz) and layout.grid[layout.idx(wx, wz)] == LevelLayout.FLOOR:
			layout.maze_dead_ends.append(layout.cell_to_world(wx, wz))
	# One dark wall visual per rock cell.
	for cz in range(1, n - 1):
		for cx in range(1, n - 1):
			if layout.grid[layout.idx(cx, cz)] == LevelLayout.OBSTACLE:
				layout.props.append({
					"type": "mazewall",
					"pos": layout.cell_to_world(cx, cz),
					"rot": 0.0,
					"scl": 1.0,
					"obstacle_visual": true,
				})


static func _carve_room(layout: LevelLayout, room: Vector2i) -> void:
	var cx := room.x * 2 + 1
	var cz := room.y * 2 + 1
	if layout.in_bounds(cx, cz):
		layout.grid[layout.idx(cx, cz)] = LevelLayout.FLOOR


static func _room_open_count(layout: LevelLayout, room: Vector2i) -> int:
	# Counts carved PASSAGES (adjacent wall cells), not neighbor rooms: every
	# room is visited/carved by the DFS, so the maze structure lives in the
	# walls between rooms. A dead end has exactly one open passage.
	var cx := room.x * 2 + 1
	var cz := room.y * 2 + 1
	var count := 0
	var dirs2: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs2:
		var nx := cx + d.x
		var nz := cz + d.y
		if layout.in_bounds(nx, nz) and layout.grid[layout.idx(nx, nz)] == LevelLayout.FLOOR:
			count += 1
	return count


## Key spots for non-maze themes: floor cells far from the center and from
## each other (greedy). Deterministic on the passed rng.
static func key_spots(layout: LevelLayout, count: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var n := layout.grid_size
	var center := float(n - 1) * 0.5
	var candidates: Array[Vector2i] = []
	for cz in range(1, n - 1):
		for cx in range(1, n - 1):
			if layout.grid[layout.idx(cx, cz)] != LevelLayout.FLOOR:
				continue
			var dx := float(cx) - center
			var dz := float(cz) - center
			if dx * dx + dz * dz < 64.0: # at least 8 cells out
				continue
			candidates.append(Vector2i(cx, cz))
	# Shuffle deterministically, then greedily keep spread-out cells.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	var spots: Array[Vector3] = []
	for c in candidates:
		if spots.size() >= count:
			break
		var wp := layout.cell_to_world(c.x, c.y)
		var ok := true
		for s in spots:
			if wp.distance_to(s) < 10.0:
				ok = false
				break
		if ok:
			spots.append(wp)
	return spots


# --- Connectivity ---

static func _enforce_connectivity(layout: LevelLayout) -> void:
	# Flood fill from the center over walkable cells; any unreachable floor
	# cell becomes a wall so mobs and players can always reach every floor tile.
	var n := layout.grid_size
	var seen := PackedByteArray()
	seen.resize(n * n)
	var start := n / 2
	var stack: Array[Vector2i] = [Vector2i(start, start)]
	seen[layout.idx(start, start)] = 1
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cell.x + d.x
			var nz: int = cell.y + d.y
			if not layout.in_bounds(nx, nz):
				continue
			var id := layout.idx(nx, nz)
			if seen[id] == 1:
				continue
			if layout.grid[id] != LevelLayout.FLOOR:
				continue
			seen[id] = 1
			stack.append(Vector2i(nx, nz))
	for cz in n:
		for cx in n:
			var id := layout.idx(cx, cz)
			if layout.grid[id] == LevelLayout.FLOOR and seen[id] == 0:
				layout.grid[id] = LevelLayout.WALL


# --- Props ---

static func _place_props(layout: LevelLayout, theme: LevelTheme, rng: RandomNumberGenerator) -> void:
	if theme.prop_entries.is_empty():
		return
	var n := layout.grid_size
	var center := float(n - 1) * 0.5
	var count := rng.randi_range(theme.props_min, theme.props_max)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 12:
		attempts += 1
		var cx := rng.randi_range(1, n - 2)
		var cz := rng.randi_range(1, n - 2)
		if layout.cell_at(cx, cz) != LevelLayout.FLOOR:
			continue
		var dcx := float(cx) - center
		var dcz := float(cz) - center
		if dcx * dcx + dcz * dcz < float(theme.clear_radius * theme.clear_radius):
			continue
		var entry := _pick_weighted(rng, theme.prop_entries)
		layout.props.append({
			"type": str(entry.get("type", "rock")),
			"pos": layout.cell_to_world(cx, cz),
			"rot": rng.randf_range(0.0, TAU),
			"scl": rng.randf_range(0.85, 1.25),
			"obstacle_visual": false,
		})
		placed += 1


static func _place_torches(layout: LevelLayout, theme: LevelTheme, rng: RandomNumberGenerator) -> void:
	if theme.torch_count <= 0:
		return
	var n := layout.grid_size
	# Walk the inner wall ring in a fixed order, starting at a random offset,
	# taking evenly spaced cells. Fully deterministic.
	var ring: Array[Vector2i] = []
	for c in range(1, n - 1):
		ring.append(Vector2i(c, 1))
	for c in range(1, n - 1):
		ring.append(Vector2i(n - 2, c))
	for c in range(n - 2, 0, -1):
		ring.append(Vector2i(c, n - 2))
	for c in range(n - 2, 0, -1):
		ring.append(Vector2i(1, c))
	var step: int = maxi(1, ring.size() / theme.torch_count)
	var offset := rng.randi_range(0, step - 1) if step > 1 else 0
	var taken := 0
	var i := offset
	while taken < theme.torch_count and i < ring.size():
		var cell: Vector2i = ring[i]
		var pos := layout.cell_to_world(cell.x, cell.y)
		pos.y = 1.6
		layout.torches.append(pos)
		taken += 1
		i += step


# --- Spawns ---

static func _place_spawns(layout: LevelLayout, theme: LevelTheme, rng: RandomNumberGenerator) -> void:
	var n := layout.grid_size
	var center := layout.cell_to_world(n / 2, n / 2)
	# Player spawns: center plus small offsets.
	var offsets := [Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5)]
	# Issue #28: Warlord's river runs down x=0 (abs(x) < 4.0). Nudge spawns
	# off the water so players don't start standing in the river.
	var river_nudge := Vector3.ZERO
	if theme.theme_id == "warlord":
		river_nudge = Vector3(6.0, 0, 0)
	for k in mini(_PLAYER_SPAWN_COUNT, offsets.size()):
		layout.player_spawns.append(center + offsets[k] + river_nudge)
	# Mob spawns: random floor cells far from the center.
	var placed := 0
	var attempts := 0
	while placed < _MOB_SPAWN_COUNT and attempts < 400:
		attempts += 1
		var cx := rng.randi_range(1, n - 2)
		var cz := rng.randi_range(1, n - 2)
		if layout.cell_at(cx, cz) != LevelLayout.FLOOR:
			continue
		var pos := layout.cell_to_world(cx, cz)
		var flat := Vector2(pos.x - center.x, pos.z - center.z)
		if flat.length() < 9.0:
			continue
		layout.mob_spawns.append(pos)
		placed += 1


# --- Helpers ---

static func _pick_weighted(rng: RandomNumberGenerator, entries: Array[Dictionary]) -> Dictionary:
	var total := 0.0
	for e in entries:
		total += float(e.get("weight", 1.0))
	var r := rng.randf_range(0.0, total)
	for e in entries:
		r -= float(e.get("weight", 1.0))
		if r <= 0.0:
			return e
	return entries[entries.size() - 1]


## Sorted mob mix for deterministic weighted picks (dict order is not stable).
static func sorted_mob_mix(theme: LevelTheme) -> Array[Dictionary]:
	var keys := theme.mob_mix.keys()
	keys.sort()
	var out: Array[Dictionary] = []
	for k in keys:
		out.append({"id": str(k), "weight": float(theme.mob_mix[k])})
	return out


static func pick_mob_id(rng: RandomNumberGenerator, mix: Array[Dictionary]) -> String:
	return str(_pick_weighted(rng, mix).get("id", "slime"))
