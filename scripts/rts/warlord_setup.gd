class_name WarlordSetup
extends RefCounted
## Issue #266 P1 — baseplate faction setup, shared by the dungeon loop's
## Warlord's Domain and the standalone Warlord match (§2.4 split).
##
## These are PURE functions: they compute what to spawn (positions,
## cluster/node placements) and return it. They own no scene, no RPCs,
## no dungeon reads — the CALLER performs the spawning through its own
## RPC surface (dungeon.gd's spawn_rts_base/spawn_rts_node, or the
## match controller's equivalents). The dungeon loop's _setup_warlord
## becomes a thin caller over these with UNCHANGED behavior; the match
## controller calls the same functions.
##
## ORDER-DEPENDENCE (load-bearing, do not "fix"): _faction_spawn_pos
## divides by factions.size() AT CALL TIME, and _setup_warlord calls it
## immediately after each registration — so faction 0 is placed with
## divisor 2, faction 1 with divisor 2, faction 2 with divisor 3, and
## so on. register_and_place preserves that register-then-place order
## exactly. Any caller that registers all factions first and places
## afterwards changes the dungeon's spawn positions.

## Faction spawn position for one faction — call AFTER that faction's
## register_faction, with the manager's CURRENT faction set.
static func spawn_pos(manager: RTSManager, faction_id: int, map_scale: float) -> Vector3:
	var angle := TAU * float(faction_id) / float(maxi(2, manager.factions.size()))
	var radius := RTSTuning.get_float("map", "faction_radius", 30.0) * map_scale
	return Vector3(cos(angle) * radius, 0, sin(angle) * radius)


## Register one faction, then return its spawn position (preserves the
## dungeon's register-then-place order).
static func register_and_place(manager: RTSManager, faction_id: int,
		peer_id: int, class_id: String, map_scale: float) -> Vector3:
	manager.register_faction(faction_id, peer_id, class_id)
	return spawn_pos(manager, faction_id, map_scale)


## Map scale for a faction count (dungeon _warlord_map_scale, with the
## roster-dependent expected-players input made explicit).
static func map_scale_for(faction_count: int) -> float:
	return sqrt(maxi(2, faction_count) / 2.0)


## Grid size for a faction count (dungeon _warlord_grid_size, with the
## count made explicit): 48/72/96/96 for 1/2/3/4+ factions.
static func grid_size_for(faction_count: int) -> int:
	return mini(96, 48 + 24 * (maxi(1, faction_count) - 1))


## Guaranteed starting cluster near a faction's town center (the
## _spawn_faction_base cluster, extracted verbatim): RTSTuning
## map.starting_cluster {wood 6, food 4, gold 3, stone 2}, each node at
## 8–14 m, mirrored to the opposite side when it lands on water.
## is_water is a Callable(pos: Vector3) -> bool — the dungeon passes
## Callable(Dungeon, "is_on_water"), the match passes its pond check.
static func starting_cluster_positions(pos: Vector3, rng: RandomNumberGenerator,
		is_water: Callable) -> Array:
	var out: Array = []
	var cluster := RTSTuning.get_dict("map", "starting_cluster",
		{"wood": 6, "food": 4, "gold": 3, "stone": 2})
	for t in cluster:
		for n in int(cluster[t]):
			var angle := rng.randf() * TAU
			var dist := 8.0 + rng.randf() * 6.0
			var npos := pos + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
			if bool(is_water.call(npos)):
				npos = pos + Vector3(cos(angle + PI) * dist, 0, sin(angle + PI) * dist)
			out.append({"type": str(t), "pos": npos})
	return out


## Resource-node scatter (the _spawn_resource_nodes rules, extracted
## verbatim): per resource per faction, per_res = 8 + 2*cycle nodes in
## the 14*ms–42*ms band; plus the contested centre ring of 12 nodes
## alternating gold/stone at 4–12 m. Dungeon calls it with
## cycle = loop_index_for(level_number); the Standard bake calls it
## with cycle 0 and a seeded RNG.
static func scatter_positions(map_scale: float, faction_count: int, cycle: int,
		rng: RandomNumberGenerator, is_water: Callable) -> Array:
	var out: Array = []
	var per_res: int = RTSTuning.get_int("map", "nodes_per_resource_per_faction", 8) \
		+ RTSTuning.get_int("map", "nodes_cycle_bonus", 2) * cycle
	var types := ["wood", "food", "gold", "stone"]
	var ms := map_scale
	for fi in maxi(2, faction_count):
		for t in types:
			for n in per_res:
				out.append({"type": t,
					"pos": _random_land_pos(14.0 * ms, 42.0 * ms, rng, is_water)})
	for i in RTSTuning.get_int("map", "center_ring_nodes", 12):
		var t: String = "gold" if i % 2 == 0 else "stone"
		out.append({"type": t,
			"pos": _random_land_pos(4.0, 12.0, rng, is_water)})
	return out


## Random position on land (not water), within a radius band — the
## dungeon _random_land_pos, extracted verbatim (20 attempts, then a
## radius-20 fallback).
static func _random_land_pos(min_r: float, max_r: float,
		rng: RandomNumberGenerator, is_water: Callable) -> Vector3:
	for attempt in 20:
		var angle := rng.randf() * TAU
		var radius := min_r + rng.randf() * (max_r - min_r)
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if not bool(is_water.call(pos)):
			return pos
	var angle2 := rng.randf() * TAU
	return Vector3(cos(angle2) * 20.0, 0, sin(angle2) * 20.0)
