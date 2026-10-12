class_name LevelLayout
extends Resource
## The output of ProcGen.generate(): everything needed to build a level's
## static geometry identically on every peer, from a single seed.

const FLOOR := 0
const WALL := 1
const OBSTACLE := 2

var grid_size: int = 24
var cell_size: float = 2.0
var grid: PackedByteArray = PackedByteArray() ## row-major, size grid_size*grid_size
var props: Array[Dictionary] = [] ## { "type": String, "pos": Vector3, "rot": float, "scl": float }
var torches: Array[Vector3] = []
var player_spawns: Array[Vector3] = []
var mob_spawns: Array[Vector3] = []
## Dead-end corridor positions (maze themes) -- ideal key hiding spots.
var maze_dead_ends: Array[Vector3] = []
## Fishing ponds: { "center": Vector3, "radius": float, "cell": Vector2i }.
## Visual + zone flag only; pond cells stay FLOOR (water never blocks).
var ponds: Array[Dictionary] = []
## E-interact fishing spot positions (pier ends), one per pond.
var fishing_spots: Array[Vector3] = []
## E-interact farm plot positions (soil patch centers).
var farm_plots: Array[Vector3] = []


func idx(cx: int, cz: int) -> int:
	return cz * grid_size + cx


func in_bounds(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < grid_size and cz < grid_size


func cell_at(cx: int, cz: int) -> int:
	if not in_bounds(cx, cz):
		return WALL
	return grid[idx(cx, cz)]


func is_floor(cx: int, cz: int) -> bool:
	return cell_at(cx, cz) == FLOOR


func cell_to_world(cx: int, cz: int) -> Vector3:
	var half := float(grid_size) * cell_size * 0.5
	return Vector3((float(cx) + 0.5) * cell_size - half, 0.0, (float(cz) + 0.5) * cell_size - half)


func world_to_cell(pos: Vector3) -> Vector2i:
	var half := float(grid_size) * cell_size * 0.5
	var cx := int(floor((pos.x + half) / cell_size))
	var cz := int(floor((pos.z + half) / cell_size))
	return Vector2i(cx, cz)


## True if a world position is inside a wall or obstacle cell.
func is_solid_world(pos: Vector3) -> bool:
	var c := world_to_cell(pos)
	return cell_at(c.x, c.y) != FLOOR


func arena_half_size() -> float:
	return float(grid_size) * cell_size * 0.5


## Deterministic fingerprint used by tests to prove multiplayer-safe generation.
func fingerprint() -> String:
	var parts: PackedStringArray = []
	parts.append(str(grid_size))
	var hex := ""
	for b in grid:
		hex += "%x" % b
	parts.append(hex)
	for p in props:
		var pos: Vector3 = p["pos"]
		parts.append("%s|%.2f,%.2f,%.2f|%.2f|%.2f" % [p["type"], pos.x, pos.y, pos.z, float(p["rot"]), float(p["scl"])])
	for t in torches:
		parts.append("torch|%.2f,%.2f,%.2f" % [t.x, t.y, t.z])
	for s in player_spawns:
		parts.append("pspawn|%.2f,%.2f" % [s.x, s.z])
	for s in mob_spawns:
		parts.append("mspawn|%.2f,%.2f" % [s.x, s.z])
	for d in maze_dead_ends:
		parts.append("deadend|%.2f,%.2f" % [d.x, d.z])
	for pd in ponds:
		var pc: Vector3 = pd["center"]
		parts.append("pond|%.2f,%.2f|%.2f" % [pc.x, pc.z, float(pd["radius"])])
	for s in fishing_spots:
		parts.append("fspot|%.2f,%.2f" % [s.x, s.z])
	for s in farm_plots:
		parts.append("fplot|%.2f,%.2f" % [s.x, s.z])
	return "|".join(parts)
