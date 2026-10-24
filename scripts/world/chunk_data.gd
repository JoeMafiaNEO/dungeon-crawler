extends RefCounted
## ChunkData (issue #197): the full description of one world chunk,
## produced by WorldGen.generate_chunk as a PURE function of
## (seed, cx, cz). Carries everything the scene side needs so the
## streamer never re-runs generation logic: the lot class grid, the
## building list, and the terrain corner heights.

## Lot classes.
const EMPTY := 0
const ROAD := 1
const BUILDING := 2
const PLAZA := 3
const GREEN := 4

var cx := 0
var cz := 0
## 16x16 lot classes, index = lz * 16 + lx (PackedByteArray of the
## class constants above).
var lots := PackedByteArray()
## Buildings: Array of [lot_x, lot_z, floors, style_index].
var buildings: Array = []
## Terrain heights at lot corners: 17x17, index = iz * 17 + ix,
## sampled from the generator's world-space height function.
var heights := PackedFloat32Array()


func lot_class(lx: int, lz: int) -> int:
	return int(lots[lz * 16 + lx])


func building_count() -> int:
	return buildings.size()


func max_floors() -> int:
	var m := 0
	for b in buildings:
		m = maxi(m, int(b[2]))
	return m


func road_lot_count() -> int:
	var n := 0
	for v in lots:
		if int(v) == ROAD:
			n += 1
	return n


## Canonical serialization for the determinism pins: identical
## inputs must produce identical strings on any machine.
func serialize() -> String:
	var parts: Array = []
	parts.append("%d,%d" % [cx, cz])
	parts.append(lots.hex_encode())
	var bs: Array = []
	for b in buildings:
		bs.append("%d:%d:%d:%d" % [int(b[0]), int(b[1]), int(b[2]), int(b[3])])
	parts.append(";".join(bs))
	var hs: Array = []
	for h in heights:
		hs.append("%.3f" % h)
	parts.append(",".join(hs))
	return "|".join(parts)
