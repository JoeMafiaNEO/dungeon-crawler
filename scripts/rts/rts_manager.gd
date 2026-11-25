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

## Faction colors (Jesse 2026-10-10): unique per faction so units/buildings
## are visually distinct. Code-generated (no art assets). 12 entries for the
## 12-player cap; wraps if more ever exist.
const FACTION_COLORS: Array[Color] = [
	Color(0.90, 0.20, 0.20), # red
	Color(0.20, 0.40, 0.90), # blue
	Color(0.20, 0.80, 0.30), # green
	Color(0.95, 0.85, 0.20), # yellow
	Color(0.60, 0.30, 0.85), # purple
	Color(0.95, 0.55, 0.15), # orange
	Color(0.20, 0.85, 0.85), # cyan
	Color(0.95, 0.40, 0.65), # pink
	Color(0.90, 0.90, 0.90), # white
	Color(0.55, 0.35, 0.20), # brown
	Color(0.60, 0.90, 0.20), # lime
	Color(0.20, 0.60, 0.55), # teal
]


static func faction_color(faction_id: int) -> Color:
	return FACTION_COLORS[abs(faction_id) % FACTION_COLORS.size()]

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
	"town_hall": {"wood": 400, "food": 0, "gold": 0, "stone": 200},
	"house": {"wood": 300, "food": 0, "gold": 0, "stone": 0},
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
## Jesse 2026-10-11: spatial hash grid for unit neighborhood queries.
var spatial_hash: RTSSpatialHash = null
# Jesse 2026-10-11: batched network sync (replaces per-unit 12Hz RPCs).
var _sync_tick := 0.0
const SYNC_INTERVAL := 0.12  # ~8Hz
# Jesse 2026-10-11: active squads for adaptive squad movement.
var squads: Array = []
# faction_id -> peer_id (for players). AI factions have peer_id = -1.
var faction_peers: Dictionary = {}
## Deterministic network IDs for RTS entities (Jesse 2026-10-10: units/buildings
## used Godot's @ClassName@N auto-naming — a global monotonic counter — so client
## and server node paths diverged and client order RPCs missed. Server allocates
## an ID per entity and passes it in the spawn RPC; clients name their copy
## identically. Clients never allocate.)
var _next_unit_id := 1
var _next_building_id := 1
var _next_node_id := 1


## Server-side: allocate a deterministic unit ID. Clients must use the ID from
## the spawn RPC, never allocate.
func alloc_unit_id() -> int:
	_next_unit_id += 1
	return _next_unit_id - 1


## Server-side: allocate a deterministic building ID.
func alloc_building_id() -> int:
	_next_building_id += 1
	return _next_building_id - 1


## Server-side: allocate a deterministic resource-node ID.
func alloc_node_id() -> int:
	_next_node_id += 1
	return _next_node_id - 1
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


## Issue #266 (standalone Warlord, P1): the match_host seam. The scene node
## that owns this manager — the dungeon in the dungeon loop, the match
## controller in a standalone match. Consumers that used to reach the
## dungeon through the "dungeon" group resolve through here instead; when
## match_host is null the legacy group lookup applies, so dungeon behavior
## is unchanged.
var match_host: Node = null


func host_node() -> Node:
	if match_host != null and is_instance_valid(match_host):
		return match_host
	return get_tree().get_first_node_in_group("dungeon")


## Ground height at a position, from the host's terrain (0.0 on the
## dungeon's flat floor — identical behavior there).
func host_ground_height(pos: Vector3) -> float:
	var host := host_node()
	if host != null and host.has_method("ground_height_at"):
		return float(host.call("ground_height_at", pos))
	return 0.0


## Water test at a position, from the host (river band in the dungeon,
## map ponds in a standalone match).
func host_is_on_water(pos: Vector3) -> bool:
	var host := host_node()
	if host != null and host.has_method("is_on_water"):
		return bool(host.call("is_on_water", pos))
	return false


## Issue #266: per-faction match stats + timeline for a standalone match
## (spec §3.7). Server-side only; recorded at the same sites that bump
## sim_stats (plus new kill/loss hooks). sim_stats itself is untouched —
## stat 12 (trade/conversions/fish) is mirrored from sim_stats at results
## time, not re-recorded. Every record function no-ops unless a match is
## in progress (the faction was zeroed by match_begin), so dungeon play
## is unaffected.
var match_stats: Dictionary = {}
var match_timeline: Array = []
var match_clock_sec: float = 0.0
var match_eliminations: Array = []
var match_last_killer: Dictionary = {}
var match_first_blood_done: bool = false


func _match_stat(faction_id: int) -> Dictionary:
	return match_stats.get(faction_id, {})


## Zero every §3.7 stat for the match's factions and open the timeline.
## Server-only; the controller calls this once at launch.
func match_begin(faction_ids: Array) -> void:
	if not multiplayer.is_server():
		return
	match_stats = {}
	match_timeline = []
	match_clock_sec = 0.0
	match_eliminations = []
	match_last_killer = {}
	match_first_blood_done = false
	var facs: Array = []
	for fid in faction_ids:
		var id := int(fid)
		match_stats[id] = {
			"units_trained": {}, "units_killed": 0, "units_lost": 0,
			"buildings_built": 0, "buildings_destroyed": 0, "buildings_lost": 0,
			"resources_gathered": {"wood": 0, "food": 0, "gold": 0, "stone": 0},
			"ages": [], "peak_population": 0, "peak_military": 0,
		}
		facs.append({"faction": id, "color": faction_color(id).to_html(false)})
	match_timeline.append({"event": "match_start", "t": 0.0, "factions": facs})


func record_unit_trained(faction_id: int, unit_type: String) -> void:
	if not multiplayer.is_server():
		return
	var s := _match_stat(faction_id)
	if s.is_empty():
		return
	var trained: Dictionary = s.get("units_trained", {})
	trained[unit_type] = int(trained.get(unit_type, 0)) + 1
	s["units_trained"] = trained
	match_sample_peaks()


## Killer -1 = unknown, no kill credit. The first credited kill of the
## match emits the first_blood timeline event once.
func record_unit_killed(victim_faction: int, killer_faction: int) -> void:
	if not multiplayer.is_server():
		return
	var s := _match_stat(victim_faction)
	if s.is_empty():
		return
	s["units_lost"] = int(s.get("units_lost", 0)) + 1
	if killer_faction >= 0:
		match_last_killer[victim_faction] = killer_faction
		var k := _match_stat(killer_faction)
		if not k.is_empty():
			k["units_killed"] = int(k.get("units_killed", 0)) + 1
		if not match_first_blood_done:
			match_first_blood_done = true
			match_timeline.append({"event": "first_blood", "t": match_clock_sec,
				"killer": killer_faction, "victim": victim_faction})
	match_sample_peaks()


func record_building_built(faction_id: int, _btype: String) -> void:
	if not multiplayer.is_server():
		return
	var s := _match_stat(faction_id)
	if s.is_empty():
		return
	s["buildings_built"] = int(s.get("buildings_built", 0)) + 1


func record_building_destroyed(victim_faction: int, killer_faction: int, btype: String) -> void:
	if not multiplayer.is_server():
		return
	var s := _match_stat(victim_faction)
	if s.is_empty():
		return
	s["buildings_lost"] = int(s.get("buildings_lost", 0)) + 1
	if killer_faction >= 0:
		match_last_killer[victim_faction] = killer_faction
		var k := _match_stat(killer_faction)
		if not k.is_empty():
			k["buildings_destroyed"] = int(k.get("buildings_destroyed", 0)) + 1
	if btype == "town_hall":
		var ev := {"event": "town_hall_destroyed", "t": match_clock_sec, "faction": victim_faction}
		if killer_faction >= 0:
			ev["by"] = killer_faction
		match_timeline.append(ev)


func record_resource_gathered(faction_id: int, res_type: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var s := _match_stat(faction_id)
	if s.is_empty():
		return
	var gathered: Dictionary = s.get("resources_gathered", {})
	if not gathered.has(res_type):
		return
	gathered[res_type] = int(gathered.get(res_type, 0)) + amount
	s["resources_gathered"] = gathered


func record_age_up(faction_id: int, new_age: int) -> void:
	if not multiplayer.is_server():
		return
	var s := _match_stat(faction_id)
	if s.is_empty():
		return
	var ages: Array = s.get("ages", [])
	ages.append({"age": new_age, "t": match_clock_sec})
	s["ages"] = ages


## A conversion counts as "lost" for the victim and never as a kill
## (gate ruling); the converter's conversions mirror lives in sim_stats
## and is read at results time, not re-recorded here.
func record_conversion(from_faction: int, _to_faction: int) -> void:
	if not multiplayer.is_server():
		return
	var s := _match_stat(from_faction)
	if s.is_empty():
		return
	s["units_lost"] = int(s.get("units_lost", 0)) + 1
	match_sample_peaks()


## Census living units per faction; update peak population / peak military.
func match_sample_peaks() -> void:
	if match_stats.is_empty():
		return
	var pop := {}
	var mil := {}
	for fid in match_stats:
		pop[fid] = 0
		mil[fid] = 0
	for n in get_tree().get_nodes_in_group("rts_units"):
		var u := n as RTSUnit
		if u == null or not u.alive:
			continue
		if not pop.has(u.faction):
			continue
		pop[u.faction] = int(pop[u.faction]) + 1
		if u.unit_type != "villager":
			mil[u.faction] = int(mil[u.faction]) + 1
	for fid in match_stats:
		var s: Dictionary = match_stats[fid]
		s["peak_population"] = maxi(int(s.get("peak_population", 0)), int(pop[fid]))
		s["peak_military"] = maxi(int(s.get("peak_military", 0)), int(mil[fid]))


## Build the §3.7 results payload: placements, per-faction stats (stat 12
## mirrored from sim_stats), timeline + match_end. Winner -1 is the
## mutual-wipe draw (the controller's path): placements are the reverse
## elimination order starting at 1.
func match_results(winner_faction: int) -> Dictionary:
	var placements: Array = []
	if winner_faction >= 0:
		placements.append({"faction": winner_faction, "placement": 1})
	var elim_rev := match_eliminations.duplicate()
	elim_rev.reverse()
	var place := 2 if winner_faction >= 0 else 1
	for fid in elim_rev:
		if int(fid) == winner_faction:
			continue
		placements.append({"faction": int(fid), "placement": place})
		place += 1
	var stats := {}
	for fid in match_stats:
		var s: Dictionary = (match_stats[fid] as Dictionary).duplicate(true)
		var sim: Dictionary = sim_stats.get(fid, {})
		s["trade_deliveries"] = int(sim.get("trade_deliveries", 0))
		s["trade_gold"] = int(sim.get("trade_gold", 0))
		s["conversions"] = int(sim.get("conversions", 0))
		s["fish_food"] = int(sim.get("fish_food", 0))
		stats[fid] = s
	var tl := match_timeline.duplicate()
	tl.append({"event": "match_end", "t": match_clock_sec, "winner": winner_faction})
	return {"winner": winner_faction, "duration_sec": match_clock_sec,
		"placements": placements, "stats": stats, "timeline": tl}


func _ready() -> void:
	add_to_group("rts_manager")
	# Jesse 2026-10-11: spatial hash for O(1) neighborhood lookups.
	spatial_hash = RTSSpatialHash.new()


func _process(delta: float) -> void:
	# Jesse 2026-10-11: batched army sync. Server collects all unit
	# transforms per faction and sends ONE rpc per faction per tick,
	# instead of each unit rpc'ing individually at 12Hz.
	if not multiplayer.is_server():
		return
	_sync_tick += delta
	if _sync_tick < SYNC_INTERVAL:
		return
	_sync_tick = 0.0
	_broadcast_army_sync()
	# Jesse 2026-10-11: check squads for combat/dissolution.
	_update_squads()


## Jesse 2026-10-11: squad management.
@rpc("any_peer", "call_local")
func rpc_order_move_squad(unit_ids: Array, target: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		# Server-authority (bug sweep 2026-10-13): a remote peer may only
		# move units of factions it owns — mirrors RTSUnit._owns_me().
		# Previously any client could order ANY player's squad by id.
		# Local calls (sender 0: server itself, AI) skip the filter.
		var wanted := {}
		for id in unit_ids:
			wanted[int(id)] = true
		var owned: Array = []
		for n in get_tree().get_nodes_in_group("rts_units"):
			var u := n as RTSUnit
			if u != null and wanted.has(u.unit_id):
				var owner := int(faction_peers.get(u.faction, -2))
				if owner == sender or owner == -1:
					owned.append(u.unit_id)
		unit_ids = owned
		if unit_ids.is_empty():
			return
	order_move_squad(unit_ids, target)


func order_move_squad(unit_ids: Array, target: Vector3) -> void:
	# Resolve IDs to units.
	# Jesse 2026-10-12: was O(n*m) — `id in unit_ids` linear-scanned the
	# whole order array per unit (~550ms for 1500 units). Dictionary set
	# makes it O(n), plus typed unit_id access instead of .get().
	var id_set := {}
	for id in unit_ids:
		id_set[int(id)] = true
	var units: Array = []
	for n in get_tree().get_nodes_in_group("rts_units"):
		var u := n as RTSUnit
		if u != null and id_set.has(u.unit_id):
			units.append(u)
	# Issue #116: dissolve-before-repartition. Any squad already covering
	# these units must retire before new squads form, or every repeated
	# move order appends fresh squads while the stale ones stay registered
	# for the rest of the session (probe: 5 re-issues grew 3 -> 18).
	# Lossless: dissolve() leaves members' current orders intact, and the
	# partition below (or the individual-order path) re-issues from here.
	dissolve_squads_for(units)
	var new_squads: Array = RTSSquad.partition(units)
	if new_squads.is_empty():
		# Under threshold: individual orders.
		for u in units:
			if u.has_method("order_move"):
				var offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
				u.order_move(target + offset)
	else:
		# Form squads.
		for s in new_squads:
			(s as RTSSquad).set_target(target)
			squads.append(s)


func _update_squads() -> void:
	var to_remove: Array = []
	for s in squads:
		var squad := s as RTSSquad
		if not squad.is_valid():
			to_remove.append(s)
		elif squad.check_combat(self):
			# Combat: dissolve, units fight individually.
			squad.dissolve()
			to_remove.append(s)
	for s in to_remove:
		squads.erase(s)


func dissolve_squads_for(units: Array) -> void:
	## Call when units are deselected or given individual orders.
	var to_remove: Array = []
	for s in squads:
		var squad := s as RTSSquad
		for u in units:
			if u in squad.units:
				squad.dissolve()
				to_remove.append(s)
				break
	for s in to_remove:
		squads.erase(s)


## Issue #178: the packing half of _broadcast_army_sync, extracted
## into a value-returning helper so the suite can drive the site
## directly. Gathers all living units by faction into packed
## per-faction payloads.
func _pack_army_sync() -> Dictionary:
	var by_faction: Dictionary = {}
	for n in get_tree().get_nodes_in_group("rts_units"):
		# Jesse 2026-10-12: typed access instead of .get() (see unit.gd).
		var u := n as RTSUnit
		if u == null or not u.alive:
			continue
		var f := u.faction
		if not by_faction.has(f):
			by_faction[f] = {"ids": PackedInt32Array(), "pos": PackedVector3Array(),
				"rot": PackedFloat32Array(), "hp": PackedFloat32Array()}
		var d: Dictionary = by_faction[f]
		# Write-back accumulation: packed arrays are VALUE types,
		# so each array is fetched into a local, appended, and
		# stored back. Appending through the Dictionary indexer
		# (the old form) grew a throwaway copy and every payload
		# shipped empty — replicas never moved (issue #178).
		var ids: PackedInt32Array = d["ids"]
		ids.append(u.unit_id)
		d["ids"] = ids
		var pos: PackedVector3Array = d["pos"]
		pos.append(u.global_position)
		d["pos"] = pos
		var rot: PackedFloat32Array = d["rot"]
		rot.append(u.rotation.y)
		d["rot"] = rot
		var hp: PackedFloat32Array = d["hp"]
		hp.append(u.hp)
		d["hp"] = hp
	return by_faction


## Gather all living units by faction and broadcast packed transforms.
func _broadcast_army_sync() -> void:
	var by_faction := _pack_army_sync()
	for f in by_faction:
		rpc("client_sync_army", f, by_faction[f])


## Runtime NetworkManager lookup (the unit.gd pattern — this
## script sits in compile chains where the autoload
## identifier does not resolve at compile time).
func _network_manager() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null:
		return loop.root.get_node_or_null("NetworkManager")
	return null


@rpc("any_peer", "unreliable")
func client_sync_army(faction_id: int, data: Dictionary) -> void:
	if multiplayer.is_server():
		return
	# Issue #165 Part B (D7): server-origin guard — replica-
	# consistency hygiene, not an authoritative-state guard
	# (the server returns above before any write, so this
	# writer reaches client replicas only). Only the server's
	# own sync tick may write them; any other sender is
	# refused and logged. The server peer is resolved through
	# the runtime lookup (this script sits in early compile
	# chains where the autoload identifier does not resolve).
	var sender := multiplayer.get_remote_sender_id()
	var nm := _network_manager()
	var server_peer := int(nm.get("server_peer_id")) if nm != null else 1
	if sender != 0 and sender != server_peer:
		push_warning("[D7] refused army sync from non-server peer %d" % sender)
		return
	# Build a quick id->unit map for this faction.
	var units := {}
	for n in get_tree().get_nodes_in_group("rts_units"):
		if int(n.get("faction")) == faction_id:
			units[int(n.get("unit_id"))] = n
	var ids: PackedInt32Array = data["ids"]
	var pos: PackedVector3Array = data["pos"]
	var rot: PackedFloat32Array = data["rot"]
	var hp: PackedFloat32Array = data["hp"]
	for i in ids.size():
		var u = units.get(ids[i])
		if u != null and is_instance_valid(u):
			(u as Node3D).global_position = pos[i]
			(u as Node3D).rotation.y = rot[i]
			u.set("hp", hp[i])
			if u.has_method("_update_hp_bar"):
				u.call("_update_hp_bar")


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
	record_age_up(faction_id, current_age + 1)
	return true


func get_pop_cap(faction_id: int) -> int:
	var caps := RTSTuning.get_array("ages", "pop_caps", POP_CAPS)
	var cap := int(caps[get_age(faction_id)])
	# Jesse 2026-10-11: each completed house adds +5 pop cap.
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if int(b.get("faction")) == faction_id \
				and str(b.get("building_type")) == "house" \
				and not bool(b.get("under_construction")) \
				and not bool(b.get("destroyed")):
			cap += 5
	return cap


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
	var uid := alloc_unit_id()
	_spawn_unit_local(unit_type, faction_id, pos, civ.civ_id, uid)
	rpc("client_spawn_unit", unit_type, faction_id, pos, civ.civ_id, uid)


func _spawn_unit_local(unit_type: String, faction_id: int, pos: Vector3, civ_id: String, unit_id: int) -> void:
	# Issue #266: the holder resolves through the match_host seam
	# (the dungeon's "RTS" child, or the match controller's) — the
	# legacy dungeon-group lookup applies when match_host is null.
	var host := host_node()
	if host == null:
		return
	var holder := host.get_node_or_null("RTS")
	if holder == null:
		return
	var civ := CivData.for_civ_id(civ_id)
	var u := RTSUnit.new()
	u.setup(faction_id, unit_type, civ)
	u.unit_id = unit_id
	u.name = "RTSUnit_%d" % unit_id
	u.position = pos
	holder.add_child(u)
	sim_bump(faction_id, "units_trained", 1, unit_type)
	record_unit_trained(faction_id, unit_type)


@rpc("any_peer", "call_local")
func client_spawn_unit(unit_type: String, faction_id: int, pos: Vector3, civ_id: String, unit_id: int) -> void:
	if multiplayer.is_server():
		return
	_spawn_unit_local(unit_type, faction_id, pos, civ_id, unit_id)


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
			# Issue #266: match bookkeeping (no-op outside a match —
			# the faction is only tracked after match_begin). Recorded
			# before the emit so signal handlers see consistent state.
			if match_stats.has(faction_id):
				match_eliminations.append(faction_id)
				var ev := {"event": "faction_eliminated", "t": match_clock_sec,
					"faction": faction_id}
				var by := int(match_last_killer.get(faction_id, -1))
				if by >= 0:
					ev["by"] = by
				match_timeline.append(ev)
			faction_eliminated.emit(faction_id)
			_check_winner()


func _check_winner() -> void:
	var alive_factions := []
	for faction_id in factions:
		if bool(factions[faction_id]["alive"]):
			alive_factions.append(faction_id)
	if alive_factions.size() == 1:
		winner_declared.emit(alive_factions[0])
