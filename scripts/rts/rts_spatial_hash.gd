class_name RTSSpatialHash
extends RefCounted
## Jesse 2026-10-11: spatial hash grid for RTS units. Replaces O(n^2)
## all-pairs scans (enemy targeting, separation, selection) with O(1)
## neighborhood lookups. Cell size matches the 8m aggro radius.

const CELL_SIZE := 8.0

# Vector2i cell -> Array[RTSUnit]
var _cells: Dictionary = {}
# unit instance id -> Vector2i cell (for fast updates/removals)
var _unit_cells: Dictionary = {}


func _cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.z / CELL_SIZE))


func insert(unit: Node3D) -> void:
	var cell := _cell_of(unit.global_position)
	if not _cells.has(cell):
		_cells[cell] = []
	(_cells[cell] as Array).append(unit)
	_unit_cells[unit.get_instance_id()] = cell


func remove(unit: Node3D) -> void:
	var id := unit.get_instance_id()
	if not _unit_cells.has(id):
		return
	var cell: Vector2i = _unit_cells[id]
	if _cells.has(cell):
		(_cells[cell] as Array).erase(unit)
		if (_cells[cell] as Array).is_empty():
			_cells.erase(cell)
	_unit_cells.erase(id)


## Call when a unit moves; re-buckets only if it crossed a cell boundary.
func update(unit: Node3D) -> void:
	var id := unit.get_instance_id()
	var new_cell := _cell_of(unit.global_position)
	if _unit_cells.get(id) == new_cell:
		return
	remove(unit)
	insert(unit)


## All units within radius of pos (unsorted). Caller filters by faction/alive.
func query(pos: Vector3, radius: float) -> Array:
	var result: Array = []
	var r := int(ceili(radius / CELL_SIZE))
	var center := _cell_of(pos)
	for cx in range(center.x - r, center.x + r + 1):
		for cz in range(center.y - r, center.y + r + 1):
			var cell := Vector2i(cx, cz)
			if _cells.has(cell):
				result.append_array(_cells[cell])
	return result


func clear() -> void:
	_cells.clear()
	_unit_cells.clear()
