extends Node
## RTSManager: core of the Warlord's Domain level.
## Tracks factions, resources, ages, population, and win detection.
## Each player is a faction. Solo gets an AI warlord opponent.

class_name RTSManager

signal resources_changed(faction: int)
signal age_changed(faction: int, new_age: int)
signal faction_eliminated(faction: int)
signal winner_declared(faction: int)

const AGES := ["Settlement", "Fortress", "Empire"]
const AGE_COSTS := [
	{"wood": 0, "food": 0, "gold": 0, "stone": 0},       # Settlement (start)
	{"wood": 300, "food": 300, "gold": 0, "stone": 100},   # Fortress
	{"wood": 600, "food": 600, "gold": 400, "stone": 300}, # Empire
]
const POP_CAPS := [30, 45, 60]
const GATHER_BONUS := [1.0, 1.25, 1.5] # Per age.

const UNIT_COSTS := {
	"villager": {"wood": 0, "food": 50, "gold": 0, "stone": 0},
	"spearman": {"wood": 0, "food": 60, "gold": 20, "stone": 0},
	"archer": {"wood": 50, "food": 40, "gold": 0, "stone": 0},
	"knight": {"wood": 0, "food": 100, "gold": 80, "stone": 0},
	"trade_cart": {"wood": 100, "food": 0, "gold": 0, "stone": 0},
	"catapult": {"wood": 150, "food": 0, "gold": 0, "stone": 100},
	"ram": {"wood": 200, "food": 0, "gold": 0, "stone": 50},
	"monk": {"wood": 0, "food": 0, "gold": 100, "stone": 0},
	"fishing_ship": {"wood": 100, "food": 0, "gold": 0, "stone": 0},
	"war_galley": {"wood": 150, "food": 0, "gold": 50, "stone": 0},
}
const BUILDING_COSTS := {
	"barracks": {"wood": 150, "food": 0, "gold": 0, "stone": 0},
	"archery_range": {"wood": 150, "food": 0, "gold": 0, "stone": 0},
	"market": {"wood": 200, "food": 0, "gold": 0, "stone": 50},
	"siege_workshop": {"wood": 250, "food": 0, "gold": 0, "stone": 150},
	"monastery": {"wood": 200, "food": 0, "gold": 100, "stone": 100},
	"dock": {"wood": 200, "food": 0, "gold": 0, "stone": 0},
	"tower": {"wood": 0, "food": 0, "gold": 0, "stone": 100},
}

# faction_id -> {resources: {wood, food, gold}, age: int, civ: CivData, alive: bool}
var factions: Dictionary = {}
# faction_id -> peer_id (for players). AI factions have peer_id = -1.
var faction_peers: Dictionary = {}
# Additive instrumentation for the balance sim harness. Never affects gameplay:
# faction_id -> {"units_trained": {type: count}, "conversions": int,
#                "trade_deliveries": int, "trade_gold": int, "fish_food": int}
var sim_stats: Dictionary = {}


## Bump a sim-harness counter (no-op if the faction isn't tracked).
func sim_bump(faction_id: int, key: String, amount: int = 1, subkey: String = "") -> void:
	var s: Dictionary = sim_stats.get(faction_id, {})
	if s.is_empty():
		return
	if subkey != "":
		var d: Dictionary = s.get(key, {})
		d[subkey] = int(d.get(subkey, 0)) + amount
		s[key] = d
	else:
		s[key] = int(s.get(key, 0)) + amount


func _ready() -> void:
	add_to_group("rts_manager")


func register_faction(faction_id: int, peer_id: int, class_id: String) -> void:
	var civ := CivData.for_class(class_id)
	factions[faction_id] = {
		"resources": {
			"wood": RTSTuning.get_int("starting_resources", "wood", 200) + civ.start_wood,
			"food": RTSTuning.get_int("starting_resources", "food", 200) + civ.start_food,
			"gold": RTSTuning.get_int("starting_resources", "gold", 100) + civ.start_gold,
			"stone": RTSTuning.get_int("starting_resources", "stone", 100),
		},
		"age": 0,
		"civ": civ,
		"alive": true,
	}
	sim_stats[faction_id] = {
		"units_trained": {}, "conversions": 0,
		"trade_deliveries": 0, "trade_gold": 0, "fish_food": 0,
	}
	faction_peers[faction_id] = peer_id
	_sync_resources(faction_id)


## Sync resources to all peers (server -> clients).
func _sync_resources(faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	var f: Dictionary = factions.get(faction_id, {})
	if f.is_empty():
		return
	var res: Dictionary = f.get("resources", {})
	rpc("client_sync_resources", faction_id, res["wood"], res["food"], res["gold"], res["stone"], int(f.get("age", 0)))
	resources_changed.emit(faction_id)


@rpc("any_peer", "call_local")
func client_sync_resources(faction_id: int, wood: int, food: int, gold: int, stone: int, age: int = -1) -> void:
	# Clients: update local copy.
	if multiplayer.is_server():
		return
	var f: Dictionary = factions.get(faction_id, {})
	if f.is_empty():
		return
	var res: Dictionary = f.get("resources", {})
	res["wood"] = wood
	res["food"] = food
	res["gold"] = gold
	res["stone"] = stone
	if age >= 0 and int(f.get("age", 0)) != age:
		f["age"] = age
		age_changed.emit(faction_id, age)
	# Emit directly: _sync_resources early-returns on clients.
	resources_changed.emit(faction_id)


func get_resources(faction_id: int) -> Dictionary:
	return factions.get(faction_id, {}).get("resources", {"wood": 0, "food": 0, "gold": 0})


func get_age(faction_id: int) -> int:
	return int(factions.get(faction_id, {}).get("age", 0))


func get_civ(faction_id: int) -> CivData:
	return factions.get(faction_id, {}).get("civ") as CivData


func can_afford(faction_id: int, cost: Dictionary) -> bool:
	var res := get_resources(faction_id)
	for key in cost:
		if int(res.get(key, 0)) < int(cost[key]):
			return false
	return true


func spend(faction_id: int, cost: Dictionary) -> bool:
	if not can_afford(faction_id, cost):
		return false
	var res := get_resources(faction_id)
	for key in cost:
		res[key] = int(res[key]) - int(cost[key])
	_sync_resources(faction_id)
	return true


func add_resource(faction_id: int, res_type: String, amount: int) -> void:
	var res := get_resources(faction_id)
	res[res_type] = int(res.get(res_type, 0)) + amount
	_sync_resources(faction_id)


@rpc("any_peer", "call_local")
func rpc_age_up(faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Ownership check: only the faction's owner (or AI) can age up.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		var owner := int(faction_peers.get(faction_id, -2))
		if owner != sender and owner != -1:
			return
	if age_up(faction_id):
		_sync_resources(faction_id)


func age_up(faction_id: int) -> bool:
	var f: Dictionary = factions.get(faction_id, {})
	var current_age := int(f.get("age", 0))
	if current_age >= 2:
		return false
	var cost: Dictionary = RTSTuning.get_cost(
		"age_costs", "age_%d" % (current_age + 1),
		AGE_COSTS[current_age + 1]).duplicate()
	var civ := get_civ(faction_id)
	if civ:
		for key in cost:
			cost[key] = int(float(cost[key]) * civ.age_cost_mult)
	if not spend(faction_id, cost):
		return false
	f["age"] = current_age + 1
	age_changed.emit(faction_id, current_age + 1)
	return true


func get_pop_cap(faction_id: int) -> int:
	var caps := RTSTuning.get_array("ages", "pop_caps", POP_CAPS)
	return int(caps[get_age(faction_id)])


func get_gather_mult(faction_id: int) -> float:
	var civ := get_civ(faction_id)
	var civ_mult := civ.gather_rate_mult if civ else 1.0
	var bonus := RTSTuning.get_array("ages", "gather_bonus", GATHER_BONUS)
	return float(bonus[get_age(faction_id)]) * civ_mult


func get_population(faction_id: int) -> int:
	var count := 0
	for u in get_tree().get_nodes_in_group("rts_units"):
		if u.get("faction") == faction_id and u.get("unit_type") != "villager":
			count += 1
		elif u.get("faction") == faction_id:
			count += 1
	return count


## Pop space + affordability check used by RTSBuilding.queue_unit.
func can_train(faction_id: int, unit_type: String) -> bool:
	if get_population(faction_id) >= get_pop_cap(faction_id):
		return false
	var cost: Dictionary = RTSTuning.get_cost(
		"unit_costs", unit_type, UNIT_COSTS.get(unit_type, {}))
	return can_afford(faction_id, cost)


## Server-side unit production. The cost was already paid when queued.
func spawn_unit(unit_type: String, faction_id: int, pos: Vector3, civ: CivData) -> void:
	if not multiplayer.is_server():
		return
	var f: Dictionary = factions.get(faction_id, {})
	if f.is_empty() or not bool(f.get("alive", false)):
		return
	_spawn_unit_local(unit_type, faction_id, pos, civ.civ_id)
	rpc("client_spawn_unit", unit_type, faction_id, pos, civ.civ_id)


func _spawn_unit_local(unit_type: String, faction_id: int, pos: Vector3, civ_id: String) -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return
	var holder := dungeon.get_node_or_null("RTS")
	if holder == null:
		return
	var civ := CivData.for_civ_id(civ_id)
	var u := RTSUnit.new()
	u.setup(faction_id, unit_type, civ)
	u.position = pos
	holder.add_child(u)
	sim_bump(faction_id, "units_trained", 1, unit_type)


@rpc("any_peer", "call_local")
func client_spawn_unit(unit_type: String, faction_id: int, pos: Vector3, civ_id: String) -> void:
	if multiplayer.is_server():
		return
	_spawn_unit_local(unit_type, faction_id, pos, civ_id)


## Called by RTSBuilding when destroyed: re-check elimination/win.
func on_building_destroyed(_b: Node3D) -> void:
	check_elimination()


func check_elimination() -> void:
	#Called when a building/unit dies. Eliminates factions with nothing left.#
	#NOTE: dead units (alive=false) and destroyed buildings are still in their
	#groups until queue_free() processes, so filter them explicitly — otherwise
	#a faction is never eliminated when its last unit/building dies.
	for faction_id in factions:
		var f: Dictionary = factions[faction_id]
		if not bool(f["alive"]):
			continue
		var has_buildings := false
		var has_units := false
		for b in get_tree().get_nodes_in_group("rts_buildings"):
			if b.get("faction") == faction_id and not bool(b.get("destroyed")):
				has_buildings = true
				break
		for u in get_tree().get_nodes_in_group("rts_units"):
			if u.get("faction") == faction_id and bool(u.get("alive")):
				has_units = true
				break
		if not has_buildings and not has_units:
			f["alive"] = false
			faction_eliminated.emit(faction_id)
			_check_winner()


func _check_winner() -> void:
	var alive_factions := []
	for faction_id in factions:
		if bool(factions[faction_id]["alive"]):
			alive_factions.append(faction_id)
	if alive_factions.size() == 1:
		winner_declared.emit(alive_factions[0])
