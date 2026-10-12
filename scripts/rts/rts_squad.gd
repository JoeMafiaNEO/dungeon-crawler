class_name RTSSquad
extends RefCounted
## Jesse 2026-10-11: adaptive squad for thousands-scale RTS movement.
## When the player orders many units at once, they form squads that
## share one pathfind and move in formation. Squads dissolve in combat
## (units fight individually) or on deselect.
##
## Squad size scales with the order size:
##   1-24 units: no squads (full individuals)
##   25-100: squads of ~12
##   100+: squads of ~25

const NO_SQUAD_THRESHOLD := 24
const MEDIUM_SQUAD_SIZE := 12
const LARGE_SQUAD_SIZE := 25
const LARGE_THRESHOLD := 100

var units: Array = []  # Array[RTSUnit]
var leader: Node3D = null
var target: Vector3 = Vector3.INF
var faction: int = 0
# Formation offsets per unit (relative to squad target).
var _offsets: Dictionary = {}  # unit instance id -> Vector3


static func squad_size_for(count: int) -> int:
	if count <= NO_SQUAD_THRESHOLD:
		return 0  # no squads
	if count < LARGE_THRESHOLD:
		return MEDIUM_SQUAD_SIZE
	return LARGE_SQUAD_SIZE


static func partition(units: Array) -> Array:
	## Split units into squads. Returns Array[RTSSquad].
	## If under threshold, returns empty (caller uses individuals).
	var size := squad_size_for(units.size())
	if size == 0:
		return []
	var squads: Array = []
	var i := 0
	while i < units.size():
		var squad := RTSSquad.new()
		var chunk: Array = units.slice(i, i + size)
		squad.units = chunk
		if not chunk.is_empty():
			squad.leader = chunk[0]
			var f = chunk[0].get("faction")
			squad.faction = int(f) if f != null else 0
		squads.append(squad)
		i += size
	return squads


func set_target(pos: Vector3) -> void:
	target = pos
	_compute_formation()


func _compute_formation() -> void:
	## Arrange members in a grid around the target.
	_offsets.clear()
	var n := units.size()
	var cols := int(ceil(sqrt(n)))
	var spacing := 2.0
	for idx in units.size():
		var u = units[idx]
		var row := idx / cols
		var col := idx % cols
		# Center the grid on the target.
		var ox: float = (col - cols / 2.0) * spacing
		var oz: float = (row - ceil(float(n) / cols) / 2.0) * spacing
		_offsets[u.get_instance_id()] = Vector3(ox, 0, oz)
		# Order each member to its formation slot.
		if u != leader and u.has_method("order_move"):
			u.order_move(target + Vector3(ox, 0, oz))
	# Leader goes to the center.
	if leader != null and leader.has_method("order_move"):
		leader.order_move(target)


func dissolve() -> void:
	## Break the squad; units keep their current orders as individuals.
	units.clear()
	_offsets.clear()
	leader = null
	target = Vector3.INF


func is_valid() -> bool:
	# Squad is valid if leader is alive and at least half the units remain.
	if leader == null or not is_instance_valid(leader):
		return false
	if not bool(leader.get("alive")):
		return false
	var alive_count := 0
	for u in units:
		if is_instance_valid(u) and bool(u.get("alive")):
			alive_count += 1
	return alive_count >= units.size() / 2


func check_combat(mgr: RTSManager) -> bool:
	## Returns true if the squad met enemies (squad should dissolve).
	## Jesse 2026-10-12: was every member scanning every frame (~317ms/frame
	## at 1500 units). Now checks the leader plus two sampled members — the
	## spearhead is what meets the enemy first, and members auto-attack on
	## their own staggered scans anyway.
	if mgr == null or mgr.spatial_hash == null:
		return false
	var sample: Array = []
	if leader != null and is_instance_valid(leader):
		sample.append(leader)
	var step := maxi(1, units.size() / 3)
	var i := 0
	while i < units.size() and sample.size() < 3:
		var u = units[i]
		if is_instance_valid(u) and u != leader:
			sample.append(u)
		i += step
	for u in sample:
		var enemies: Array = mgr.spatial_hash.query((u as Node3D).global_position, 8.0)
		for e in enemies:
			# Jesse 2026-10-12: typed access (see RTSUnit._find_nearest_enemy).
			var eu := e as RTSUnit
			if eu != null and eu != u and eu.faction != faction and eu.alive:
				return true
	return false
