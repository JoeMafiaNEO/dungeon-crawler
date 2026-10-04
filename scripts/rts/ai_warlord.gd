extends Node
## AIWarlord: solo opponent for the Warlord's Domain.
## Simple state machine: gather -> age up -> build troops -> attack.
## Beatable but threatening (not a stomp, not brutal).

class_name AIWarlord

var manager: RTSManager = null
var faction_id: int = 1
var _think_tick := 0.0
var _attack_wave := 0

# AI tuning: beatable but threatening. All values live in rts_tuning.cfg [ai].
const THINK_INTERVAL := 3.0
const VILLAGER_TARGET := 12
const ARMY_TARGET := [10, 16, 24] # Per age.


func _think_interval() -> float:
	return RTSTuning.get_float("ai", "think_interval", THINK_INTERVAL)


func _villager_target() -> int:
	return RTSTuning.get_int("ai", "villager_target", VILLAGER_TARGET)


func _army_target(age: int) -> int:
	var arr := RTSTuning.get_array("ai", "army_target", ARMY_TARGET)
	return int(arr[clampi(age, 0, arr.size() - 1)])


func _ready() -> void:
	manager = get_tree().get_first_node_in_group("rts_manager") as RTSManager


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if manager == null:
		return
	_think_tick -= delta
	if _think_tick <= 0.0:
		_think_tick = _think_interval()
		_think()


func _think() -> void:
	var f: Dictionary = manager.factions.get(faction_id, {})
	if f.is_empty() or not bool(f["alive"]):
		return

	var age := manager.get_age(faction_id)
	var civ: CivData = f.get("civ")
	var civ_id := str(civ.civ_id) if civ != null else "iron_vanguard"

	# 0. Assign idle villagers to gather.
	_assign_gatherers()

	# 1. Train villagers up to target (Vanguard wants more army, fewer vils).
	var vil_target := _villager_target()
	if civ_id == "iron_vanguard":
		vil_target = RTSTuning.get_int("ai", "vanguard_villager_target", 10)
	elif civ_id == "arcane_dominion":
		vil_target = RTSTuning.get_int("ai", "dominion_villager_target", 14)
	var villagers := _count_units("villager")
	if villagers < vil_target:
		_try_train("villager")

	# 2. Age up when we can afford it (Dominion prioritizes).
	if age < 2:
		if civ_id == "arcane_dominion" or villagers >= 8:
			manager.age_up(faction_id)

	# 3. Build production.
	_ensure_buildings(civ_id)

	# 4. Train army up to target for our age.
	var army := _count_army()
	var army_target := _army_target(age)
	if civ_id == "iron_vanguard":
		army_target += RTSTuning.get_int("ai", "vanguard_army_bonus", 4)  # Vanguard fields larger armies
	if army < army_target:
		_try_train(_pick_unit(civ_id, age))

	# 5. Attack when we have a decent force (Fortress+).
	# Vanguard attacks earlier and more aggressively.
	var attack_threshold := RTSTuning.get_float("ai", "attack_threshold", 0.7)
	if civ_id == "iron_vanguard":
		attack_threshold = RTSTuning.get_float("ai", "vanguard_attack_threshold", 0.5)
	if age >= 1 and army >= army_target * attack_threshold:
		_attack(civ_id)


func _pick_unit(civ_id: String, age: int) -> String:
	# Civ-flavored unit composition.
	match civ_id:
		"iron_vanguard":
			# Heavy infantry focus.
			var picks := ["spearman", "spearman", "knight"]
			if age >= 1:
				picks.append("ram")
			return picks[randi() % picks.size()]
		"shadow_covenant":
			# Ranged harassment.
			var picks := ["archer", "archer", "spearman"]
			if age >= 1:
				picks.append("monk")
			return picks[randi() % picks.size()]
		"arcane_dominion":
			# Balanced with siege.
			var picks := ["spearman", "archer", "knight"]
			if age >= 1:
				picks.append("catapult")
			return picks[randi() % picks.size()]
	return "spearman"


func _assign_gatherers() -> void:
	# Idle villagers go gather the nearest resource.
	for u in get_tree().get_nodes_in_group("rts_units"):
		if u.get("faction") != faction_id or u.get("unit_type") != "villager":
			continue
		# Skip if busy (has orders).
		if u.get("_move_target") != Vector3.INF:
			continue
		if u.get("_attack_target") != null:
			continue
		if u.get("_gather_node") != null:
			continue
		if u.get("_build_target") != null:
			continue
		# Find nearest resource node.
		var best: Node3D = null
		var best_d := 9999.0
		for n in get_tree().get_nodes_in_group("rts_resources"):
			var d: float = u.global_position.distance_to(n.global_position)
			if d < best_d:
				best_d = d
				best = n
		if best != null and u.has_method("order_gather"):
			u.order_gather(best)


func _count_units(unit_type: String) -> int:
	var count := 0
	for u in get_tree().get_nodes_in_group("rts_units"):
		if u.get("faction") == faction_id and u.get("unit_type") == unit_type:
			count += 1
	return count


func _count_army() -> int:
	var count := 0
	for u in get_tree().get_nodes_in_group("rts_units"):
		if u.get("faction") == faction_id and u.get("unit_type") != "villager":
			count += 1
	return count


func _try_train(unit_type: String) -> void:
	# Find a building that can train this unit.
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if b.get("faction") != faction_id:
			continue
		if bool(b.get("under_construction")):
			continue
		var btype := str(b.get("building_type"))
		var can_train := false
		match unit_type:
			"villager":
				can_train = btype == "town_hall"
			"spearman":
				can_train = btype == "barracks"
			"archer":
				can_train = btype == "archery_range"
			"knight":
				can_train = btype == "town_hall" and manager.get_age(faction_id) >= 1
			"catapult", "ram":
				can_train = btype == "siege_workshop"
			"monk":
				can_train = btype == "monastery"
		if can_train and b.has_method("queue_unit"):
			b.queue_unit(unit_type)
			break


func _ensure_buildings(civ_id: String) -> void:
	var has_barracks := false
	var has_range := false
	var has_siege := false
	var has_monastery := false
	var is_building := false
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if b.get("faction") != faction_id:
			continue
		if bool(b.get("under_construction")):
			is_building = true
		if b.get("building_type") == "barracks":
			has_barracks = true
		if b.get("building_type") == "archery_range":
			has_range = true
		if b.get("building_type") == "siege_workshop":
			has_siege = true
		if b.get("building_type") == "monastery":
			has_monastery = true
	if is_building:
		return  # one at a time
	var age := manager.get_age(faction_id)
	# Covenant skips barracks, rushes archers. Dominion wants monastery early.
	if civ_id == "shadow_covenant":
		if not has_range:
			_order_build("archery_range")
		elif not has_barracks:
			_order_build("barracks")
		elif not _has_building("tower"):
			_order_build("tower")
		elif age >= 1 and not has_monastery:
			_order_build("monastery")
		elif age >= 1 and not has_siege:
			_order_build("siege_workshop")
	else:
		# Standard: barracks -> archery range -> tower -> (Fortress) siege -> monastery.
		if not has_barracks:
			_order_build("barracks")
		elif not has_range:
			_order_build("archery_range")
		elif not _has_building("tower"):
			_order_build("tower")
		elif age >= 1 and not has_siege:
			_order_build("siege_workshop")
		elif age >= 1 and not has_monastery:
			_order_build("monastery")


func _has_building(btype: String) -> bool:
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if b.get("faction") == faction_id and b.get("building_type") == btype:
			return true
	return false


func _order_build(btype: String) -> void:
	# Find the faction's town hall for a build location.
	var th: Node3D = null
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if b.get("faction") == faction_id and b.get("building_type") == "town_hall":
			th = b
			break
	if th == null:
		return
	# Build near the town hall with some randomness.
	var pos := th.global_position + Vector3(randf_range(-8, 8), 0, randf_range(6, 10))
	pos.y = 0.0
	var dungeon = get_tree().get_first_node_in_group("dungeon")
	if dungeon != null and dungeon.has_method("rpc_start_construction"):
		# Call directly (we're the server).
		dungeon.rpc_start_construction(faction_id, btype, pos)


func _attack(civ_id: String = "") -> void:
	_attack_wave += 1
	# Covenant harasses with a small raiding party; others send everything.
	var target := _find_enemy_townhall()
	if target == null:
		# No town hall? Attack nearest enemy building.
		target = _find_enemy_building()
	if target == null:
		# No buildings left? Hunt down remaining enemy units so the game can end.
		target = _find_enemy_unit()
	if target == null:
		return
	var troops := []
	for u in get_tree().get_nodes_in_group("rts_units"):
		if u.get("faction") == faction_id and u.get("unit_type") != "villager":
			troops.append(u)
	# Covenant sends half as raiders, keeps half home.
	if civ_id == "shadow_covenant" and troops.size() > 4:
		troops = troops.slice(0, troops.size() / 2)
	for u in troops:
		if u.has_method("order_attack"):
			u.order_attack(target)


func _find_enemy_townhall() -> Node3D:
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if b.get("faction") != faction_id and b.get("building_type") == "town_hall":
			return b as Node3D
	return null


func _find_enemy_building() -> Node3D:
	# Fallback: nearest enemy building.
	var best: Node3D = null
	var best_d := 9999.0
	var my_pos := Vector3.ZERO
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if b.get("faction") == faction_id and b.get("building_type") == "town_hall":
			my_pos = b.global_position
			break
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if b.get("faction") == faction_id:
			continue
		var d: float = my_pos.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func _find_enemy_unit() -> Node3D:
	# Last resort: nearest living enemy unit (hunt stragglers so the game ends).
	var best: Node3D = null
	var best_d := 9999.0
	var my_pos := Vector3.ZERO
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if b.get("faction") == faction_id:
			my_pos = b.global_position
			break
	for u in get_tree().get_nodes_in_group("rts_units"):
		if int(u.get("faction")) == faction_id or not bool(u.get("alive")):
			continue
		var d: float = my_pos.distance_to((u as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = u
	return best
