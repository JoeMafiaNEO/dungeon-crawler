extends Node3D
## Issue #116 regression driver (scene-based; run headless, NOT via -s —
## unit.gd cannot compile in the -s playtest suite, see playtest.gd's
## _test_rts_squad_reorder_no_leak note).
##
## Real RTSManager + 36 real spearmen on flat ground:
##   1. order_move_squad to a target -> registry must hold 3 squads.
##   2. Re-issue the IDENTICAL order 5 times during the march (the
##      probe's repro shape) -> registry must stay 3 after every issue.
##      Pre-fix it grew 3 -> 6 -> 9 -> 12 -> 15 -> 18.
##   3. Coverage: every unit in exactly one squad.
##   4. The units actually ARRIVE at the target (orders not eaten).
##   5. Subset re-order (exactly one squad's members, to a new target):
##      registry 3 -> 2, the other 24 stay covered exactly once, and
##      the subset arrives at its new target.
## Prints [SQUAD116] lines and quits with exit code = failure count.

var _fails := 0
var _mgr: RTSManager = null
var _armies: Node3D = null
var _units: Array = []

const TARGET_A := Vector3(20, 0, 0)
const TARGET_B := Vector3(-20, 0, 14)
const ARRIVE_RADIUS := 6.0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[SQUAD116] PASS: ", label)
	else:
		_fails += 1
		print("[SQUAD116] FAIL: ", label)


func _ready() -> void:
	_mgr = RTSManager.new()
	_mgr.name = "RTSManager"
	add_child(_mgr)
	_armies = Node3D.new()
	_armies.name = "Armies"
	add_child(_armies)
	_mgr.register_faction(0, multiplayer.get_unique_id(), "warrior")
	_spawn_army()
	# Let _ready/spatial-hash registration settle.
	for i in 10:
		await get_tree().physics_frame
	await _run()


func _spawn_army() -> void:
	var civ := CivData.for_civ_id("warrior")
	for i in 36:
		var u := RTSUnit.new()
		u.setup(0, "spearman", civ)
		u.unit_id = _mgr.alloc_unit_id()
		u.name = "RTSUnit_%d" % u.unit_id
		u.position = Vector3(-24.0 + float(i % 6) * 1.2, 0, -4.0 + float(i / 6) * 1.2)
		_armies.add_child(u)
		_units.append(u)
	print("[SQUAD116] spawned ", _units.size(), " spearmen")


func _ids(units: Array) -> Array:
	var out: Array = []
	for u in units:
		out.append(int(u.get("unit_id")))
	return out


func _coverage_ok(pool: Array) -> bool:
	var coverage := {}
	for s in _mgr.squads:
		for u in s.units:
			coverage[u] = int(coverage.get(u, 0)) + 1
	if coverage.size() != pool.size():
		return false
	for u in pool:
		if int(coverage.get(u, 0)) != 1:
			return false
	return true


func _wait_arrival(pool: Array, target: Vector3, max_frames: int) -> bool:
	var frames := 0
	while frames < max_frames:
		var ok := true
		for u in pool:
			if not is_instance_valid(u):
				ok = false
				break
			if (u as Node3D).global_position.distance_to(target) > ARRIVE_RADIUS:
				ok = false
				break
		if ok:
			return true
		for i in 30:
			await get_tree().physics_frame
		frames += 30
	return false


func _run() -> void:
	var ids := _ids(_units)
	_mgr.order_move_squad(ids, TARGET_A)
	_check(_mgr.squads.size() == 3,
		"initial order forms 3 squads (got %d)" % _mgr.squads.size())
	# Re-issue the identical order 5 times while the march is underway.
	var sizes: Array = []
	for r in 5:
		for i in 20:
			await get_tree().physics_frame
		_mgr.order_move_squad(ids, TARGET_A)
		sizes.append(_mgr.squads.size())
	print("[SQUAD116] registry size after each re-issue: ", sizes)
	_check(_mgr.squads.size() == 3,
		"registry unchanged after 5 re-issues (got %d, want 3)" % _mgr.squads.size())
	_check(_coverage_ok(_units), "each of 36 units covered by exactly one squad")
	# Orders execute: the whole formation reaches target A.
	var arrived := await _wait_arrival(_units, TARGET_A, 3600)
	_check(arrived, "all 36 units arrived at target A")
	var centroid := Vector3.ZERO
	for u in _units:
		centroid += (u as Node3D).global_position
	centroid /= _units.size()
	# Loose bound: the three squads share identical formation slots, so
	# separation spreads the stack (slot centroid alone sits ~1.4m off).
	_check(centroid.distance_to(TARGET_A) <= 3.5,
		"formation centroid on target A (off by %.2f)" % centroid.distance_to(TARGET_A))
	# Subset re-order: exactly one live squad's members, new destination.
	var subset: Array = (_mgr.squads[0] as RTSSquad).units.duplicate()
	_mgr.order_move_squad(_ids(subset), TARGET_B)
	_check(_mgr.squads.size() == 2,
		"subset re-order retires its squad (registry %d, want 2)" % _mgr.squads.size())
	var rest: Array = []
	for u in _units:
		if not (u in subset):
			rest.append(u)
	_check(_coverage_ok(rest), "un-ordered 24 remain covered exactly once")
	var sub_arrived := await _wait_arrival(subset, TARGET_B, 3600)
	_check(sub_arrived, "subset of 12 arrived at target B")
	print("[SQUAD116] done fails=", _fails)
	get_tree().quit(_fails)
