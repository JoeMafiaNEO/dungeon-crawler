extends Node
## AI-vs-AI balance simulation harness for Warlord's Domain.
##
## Boots the real warlord level headless with all three civilizations driven
## by the game's own AIWarlord controllers (3-way free-for-all), fast-forwards
## with Engine.time_scale, and records per-faction outcomes, economy samples,
## and siege/monk/naval usage. Nothing here changes gameplay logic — it only
## drives the game and reads the tuning file like a player would.
##
## Run headless:
##   godot --headless --path . res://tools/sim/sim_harness.tscn -- --matches 6
##
## Args:
##   --matches N      number of matches (default 6)
##   --time-scale T   sim speed multiplier (default 8)
##   --seed S         base RNG seed; match i uses S + i (default 1234)
##   --timeout M      per-match cap in sim-minutes (default 25)
##   --out DIR        report directory, res://-relative (default tools/sim/output)

const CLASSES := ["warrior", "rogue", "mage"]
const CIV_OF := {"warrior": "iron_vanguard", "rogue": "shadow_covenant", "mage": "arcane_dominion"}
const FAKE_PEERS := [1001, 1002]

var _matches := 6
var _time_scale := 8.0
var _base_seed := 1234
var _timeout_min := 25.0
var _out_dir := "tools/sim/output"

var _winner := -1
var _results: Array = []


func _ready() -> void:
	_parse_args()
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("res://" + _out_dir)
	print("[Sim] AI-vs-AI balance harness: matches=%d time_scale=%.1f seed=%d" % [_matches, _time_scale, _base_seed])
	for m in range(_matches):
		await _run_match(m)
		Engine.time_scale = 1.0
	_write_report()
	print("[Sim] DONE")
	get_tree().quit()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--matches" and i + 1 < args.size():
			_matches = int(args[i + 1])
			i += 2
		elif args[i] == "--time-scale" and i + 1 < args.size():
			_time_scale = float(args[i + 1])
			i += 2
		elif args[i] == "--seed" and i + 1 < args.size():
			_base_seed = int(args[i + 1])
			i += 2
		elif args[i] == "--timeout" and i + 1 < args.size():
			_timeout_min = float(args[i + 1])
			i += 2
		elif args[i] == "--out" and i + 1 < args.size():
			_out_dir = args[i + 1]
			i += 2
		else:
			i += 1


func _run_match(m: int) -> void:
	_winner = -1
	var match_seed := _base_seed + m * 1000
	seed(match_seed)
	# Rotate faction 0's class; stubs take the other two so every match is
	# Iron Vanguard vs Shadow Covenant vs Arcane Dominion.
	var c0: String = CLASSES[m % 3]
	var others: Array = CLASSES.filter(func(c): return c != c0)

	NetworkManager.selected_class_id = c0
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "warlord"
	Dungeon.next_seed = match_seed
	Dungeon.next_level_number = 1

	var tree := get_tree()
	# Defensive: ensure the previous match's nodes are fully gone. The old
	# dungeon's players live in the GLOBAL "players" group; if they linger,
	# _setup_warlord sees 6 players instead of 3 and the match never starts.
	var clean_wait := 0.0
	while clean_wait < 10.0:
		if get_tree().get_nodes_in_group("players").is_empty() \
		and get_tree().get_nodes_in_group("rts_manager").is_empty():
			break
		await tree.process_frame
		clean_wait += get_process_delta_time()
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	var dungeon := packed.instantiate()
	tree.root.add_child(dungeon)
	tree.current_scene = dungeon

	# Hold the deferred RTS setup, add two stub players (remote peers with no
	# input — the harness attaches AI controllers to every faction), release.
	dungeon.set("_warlord_setup_pending", false)
	for s in range(2):
		var sp: Vector3 = dungeon.spawn_points[s % maxi(1, dungeon.spawn_points.size())]
		dungeon._do_spawn(FAKE_PEERS[s], others[s], sp)
	dungeon.set("_warlord_setup_pending", true)

	# Wait for the RTS world: 3 factions registered.
	var mgr: RTSManager = null
	var waited := 0.0
	while waited < 60.0:
		await tree.process_frame
		waited += get_process_delta_time()
		var dm = dungeon.get("_rts_manager")
		if dm != null and (dm as RTSManager).factions.size() == 3:
			mgr = dm
			break
	if mgr == null:
		push_warning("[Sim] match %d: RTS setup never completed, skipping" % m)
		_teardown(dungeon)
		return

	# Every faction gets the game's own AI controller.
	for fid in mgr.factions:
		var has_ai := false
		for child in dungeon.get_children():
			if child is AIWarlord and int(child.get("faction_id")) == int(fid):
				has_ai = true
		if not has_ai:
			var ai := AIWarlord.new()
			ai.faction_id = int(fid)
			dungeon.add_child(ai)

	var civs := {}
	for fid in mgr.factions:
		civs[int(fid)] = (mgr.get_civ(int(fid)) as CivData).civ_id
	print("[Sim] match %d: factions=%s seed=%d" % [m, str(civs), match_seed])

	mgr.winner_declared.connect(_on_winner)
	Engine.time_scale = _time_scale

	# Harness-side orchestration: the built-in AI never builds markets,
	# monasteries, siege workshops, or docks, so drive those systems here
	# using only existing game actions (construction, training, orders).
	# Runs interleaved with the main sample loop below.
	_orchestrate_systems(dungeon, mgr)

	# Sample the economy every 30 sim-seconds until someone wins or we time out.
	var samples: Array = []
	var next_sample := 30.0
	var timeout_s := _timeout_min * 60.0
	while _winner < 0 and dungeon.sim_time < timeout_s and is_instance_valid(dungeon):
		await tree.process_frame
		if dungeon.sim_time >= next_sample:
			samples.append(_sample(mgr, dungeon))
			next_sample += 30.0
	Engine.time_scale = 1.0

	var duration: float = dungeon.sim_time
	var result := {
		"match": m, "seed": match_seed,
		"civs": civs,
		"winner": _winner,
		"duration_s": duration,
		"samples": samples,
		"sim_stats": _snapshot_stats(mgr),
	}
	if _winner < 0:
		result["draw_leader"] = _strongest_faction(mgr)
		print("[Sim] match %d: TIMEOUT (%.0fs sim), leader=%s" % [m, duration, str(result["draw_leader"])])
	else:
		print("[Sim] match %d: winner=%s (%.0fs sim)" % [m, str(civs.get(_winner, _winner)), duration])
	_results.append(result)
	mgr.winner_declared.disconnect(_on_winner)
	_teardown(dungeon)


func _on_winner(fid: int) -> void:
	_winner = fid


## Harness-side system exerciser. The built-in AIWarlord never builds markets,
## monasteries, siege workshops, or docks, so those code paths would score
## zero in every report. This drives them with the same actions a player (or
## the AI) would use — rpc_start_construction, queue_unit, and the order_*
## methods — without touching gameplay logic.
func _orchestrate_systems(dungeon: Node, mgr: RTSManager) -> void:
	# Start early: matches can end in ~400s, and construction+training needs
	# ~60s before units can act. Wait just long enough for setup to settle.
	while is_instance_valid(dungeon) and float(dungeon.get("sim_time")) < 10.0 and _winner < 0:
		await get_tree().process_frame
	if not is_instance_valid(dungeon) or _winner >= 0:
		return
	var fids: Array = mgr.factions.keys()
	# Harness stipend: grant each faction the stone (and a wood buffer) needed
	# for the support buildings. Applied equally to all factions so relative
	# balance is preserved; the goal is exercising systems, not the econ race.
	# Reported stockpiles include this one-time grant.
	for fid in fids:
		mgr.add_resource(int(fid), "stone", 400)
		mgr.add_resource(int(fid), "wood", 400)
		# Ensure Age 1 so siege workshop / monastery can be ordered.
		if mgr.get_age(int(fid)) < 1:
			mgr.age_up(int(fid))
	# 1. Order support buildings per faction (all are age-eligible now).
	for fid in fids:
		_orch_build_supports(dungeon, mgr, int(fid))
	# 2. Complete construction instantly: the harness is exercising units,
	#    not the villager build mechanic. (Docks complete on their own;
	#    land buildings stall because the AI never sends a builder.)
	for fid in fids:
		for b in get_tree().get_nodes_in_group("rts_buildings"):
			if dungeon.is_ancestor_of(b) and int(b.get("faction")) == int(fid) \
			and bool(b.get("under_construction")):
				b.set("under_construction", false)
				b.set("build_progress", 1.0)
	if not is_instance_valid(dungeon) or _winner >= 0:
		return
	# 3. Train one of each special unit, then issue orders.
	for fid in fids:
		_orch_train_and_order(dungeon, mgr, int(fid), fids)
	# 4. Keep monks converting: every 60 sim-seconds, re-target idle monks.
	var retarget := 0.0
	while is_instance_valid(dungeon) and _winner < 0:
		await get_tree().process_frame
		retarget += get_process_delta_time() * _time_scale
		if retarget >= 60.0:
			retarget = 0.0
			for fid in fids:
				_orch_monk_orders(dungeon, int(fid))


## Order market + monastery + siege workshop near the town hall, and a dock
## at the river edge closest to the faction's base. Skips buildings whose
## age requirement isn't met yet (caller retries).
func _orch_build_supports(dungeon: Node, mgr: RTSManager, fid: int) -> void:
	var th: Node3D = null
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if int(b.get("faction")) == fid and str(b.get("building_type")) == "town_hall" \
		and dungeon.is_ancestor_of(b):
			th = b
			break
	if th == null:
		return
	var age := mgr.get_age(fid)
	var base := th.global_position
	# Keep buildings off the river (|x| < 4 is water) — shift x away from 0.
	# Use large offsets (15-20m) to avoid the AI's own build zone (~6-10m).
	var safe_x := func(off: float) -> float:
		var x := base.x + off
		if absf(x) < 5.0:
			x = 5.0 if x >= 0.0 else -5.0
		return x
	var specs := [
		["market", Vector3(safe_x.call(-12.0), 0, base.z + 15.0), 0],
		["monastery", Vector3(safe_x.call(12.0), 0, base.z + 15.0), 1],
		["siege_workshop", Vector3(safe_x.call(0.0), 0, base.z + 20.0), 1],
	]
	for spec in specs:
		if age < int(spec[2]):
			continue  # not aged up yet; caller retries
		if not _has_building(dungeon, fid, str(spec[0])):
			var pos: Vector3 = spec[1]
			pos.y = 0.0
			if not dungeon._is_valid_build_spot(pos):
				continue
			dungeon.rpc_start_construction(fid, str(spec[0]), pos)
	# Dock: river runs along x=0 (|x|<4 is water). Put it on the bank nearest base.
	var dock_x := 6.0 if base.x >= 0.0 else -6.0
	var dock_pos := Vector3(dock_x, 0, base.z)
	if not _has_building(dungeon, fid, "dock"):
		dungeon.rpc_start_construction(fid, "dock", dock_pos)


func _has_building(dungeon: Node, fid: int, btype: String) -> bool:
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if dungeon.is_ancestor_of(b) and int(b.get("faction")) == fid \
		and str(b.get("building_type")) == btype:
			return true
	return false


## Train the special units and give them their first orders.
func _orch_train_and_order(dungeon: Node, mgr: RTSManager, fid: int, fids: Array) -> void:
	var trained := {}
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if not dungeon.is_ancestor_of(b) or int(b.get("faction")) != fid:
			continue
		if bool(b.get("under_construction")) or bool(b.get("destroyed")):
			continue
		var bt := str(b.get("building_type"))
		var want := ""
		match bt:
			"market": want = "trade_cart"
			"monastery": want = "monk"
			"siege_workshop": want = "catapult"
			"dock": want = "fishing_ship"
		if want != "" and not trained.has(want):
			if b.queue_unit(want):
				trained[want] = b
	# Extra: a war galley from the dock and a ram from the siege shop.
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if not dungeon.is_ancestor_of(b) or int(b.get("faction")) != fid:
			continue
		if bool(b.get("under_construction")) or bool(b.get("destroyed")):
			continue
		var bt := str(b.get("building_type"))
		if bt == "dock" and not trained.has("war_galley"):
			if b.queue_unit("war_galley"):
				trained["war_galley"] = b
		if bt == "siege_workshop" and not trained.has("ram"):
			if b.queue_unit("ram"):
				trained["ram"] = b
	# Wait for the units to pop, then order them.
	var wait := 0.0
	while is_instance_valid(dungeon) and wait < 120.0 and _winner < 0:
		await get_tree().process_frame
		wait += get_process_delta_time() * _time_scale
		if _specials_out(dungeon, fid):
			break
	_orch_issue_orders(dungeon, mgr, fid, fids)


func _specials_out(dungeon: Node, fid: int) -> bool:
	var need := {"trade_cart": false, "monk": false, "catapult": false,
		"fishing_ship": false, "war_galley": false, "ram": false}
	for u in get_tree().get_nodes_in_group("rts_units"):
		if dungeon.is_ancestor_of(u) and int(u.get("faction")) == fid \
		and bool(u.get("alive")):
			var ut := str(u.get("unit_type"))
			if need.has(ut):
				need[ut] = true
	for k in need:
		if not need[k]:
			return false
	return true


## Give the special units their orders: trade route, conversion, naval, siege.
func _orch_issue_orders(dungeon: Node, mgr: RTSManager, fid: int, fids: Array) -> void:
	var my_units := {}
	for u in get_tree().get_nodes_in_group("rts_units"):
		if dungeon.is_ancestor_of(u) and int(u.get("faction")) == fid \
		and bool(u.get("alive")):
			my_units[str(u.get("unit_type"))] = u
	# Trade: route the cart to another faction's market (distance => gold).
	var cart = my_units.get("trade_cart")
	if cart != null:
		var target_market := _find_foreign_market(dungeon, fid, fids)
		if target_market != null:
			cart.order_trade(target_market)
	# Monks: convert the nearest enemy unit.
	_orch_monk_orders(dungeon, fid)
	# Siege: march catapult + ram at the nearest enemy town hall (auto-attacks).
	var siege_target := _find_enemy_building(dungeon, fid)
	if siege_target != null:
		for ut in ["catapult", "ram"]:
			var su = my_units.get(ut)
			if su != null:
				su.order_attack(siege_target)
	# Naval: sail ships onto the river; galley hunts, fishing ship gathers.
	var galley = my_units.get("war_galley")
	var fish = my_units.get("fishing_ship")
	var my_base := _faction_base_pos(dungeon, fid)
	if galley != null:
		galley.order_move(Vector3(0, 0, my_base.z))
	if fish != null:
		fish.order_move(Vector3(0, 0, my_base.z + 10.0))


func _orch_monk_orders(dungeon: Node, fid: int) -> void:
	for u in get_tree().get_nodes_in_group("rts_units"):
		if not dungeon.is_ancestor_of(u):
			continue
		if int(u.get("faction")) != fid or str(u.get("unit_type")) != "monk":
			continue
		if not bool(u.get("alive")):
			continue
		if u.get("_convert_target") != null and is_instance_valid(u.get("_convert_target")):
			continue  # already channeling
		var prey := _find_convertible_enemy(dungeon, fid, u.global_position)
		if prey != null:
			u.order_convert(prey.get_path())


func _find_foreign_market(dungeon: Node, fid: int, fids: Array) -> Node3D:
	for ofid in fids:
		if int(ofid) == fid:
			continue
		for b in get_tree().get_nodes_in_group("rts_buildings"):
			if dungeon.is_ancestor_of(b) and int(b.get("faction")) == int(ofid) \
			and str(b.get("building_type")) == "market" \
			and not bool(b.get("under_construction")) and not bool(b.get("destroyed")):
				return b
	return null


func _find_enemy_building(dungeon: Node, fid: int) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var my_base := _faction_base_pos(dungeon, fid)
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if not dungeon.is_ancestor_of(b) or int(b.get("faction")) == fid:
			continue
		if bool(b.get("destroyed")) or bool(b.get("under_construction")):
			continue
		var d: float = my_base.distance_to((b as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func _find_convertible_enemy(dungeon: Node, fid: int, from_pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 40.0  # monks only bother with nearby prey
	for u in get_tree().get_nodes_in_group("rts_units"):
		if not dungeon.is_ancestor_of(u) or int(u.get("faction")) == fid:
			continue
		if not bool(u.get("alive")):
			continue
		var ut := str(u.get("unit_type"))
		if ut == "monk" or ut == "trade_cart":
			continue
		var d: float = from_pos.distance_to((u as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = u
	return best


func _faction_base_pos(dungeon: Node, fid: int) -> Vector3:
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if dungeon.is_ancestor_of(b) and int(b.get("faction")) == fid \
		and str(b.get("building_type")) == "town_hall":
			return (b as Node3D).global_position
	return Vector3.ZERO


func _teardown(dungeon: Node) -> void:
	# Free the old dungeon and wait until ALL its nodes (players, RTS manager,
	# units) are actually gone. _setup_warlord reads the GLOBAL "players"
	# group, so leftover players from the last match would corrupt the next.
	var tree := get_tree()
	Engine.time_scale = 1.0
	if is_instance_valid(dungeon):
		tree.current_scene = self
		dungeon.queue_free()
	var waited := 0.0
	while waited < 10.0:
		await tree.process_frame
		waited += get_process_delta_time()
		if get_tree().get_nodes_in_group("players").is_empty() \
		and get_tree().get_nodes_in_group("rts_manager").is_empty() \
		and get_tree().get_nodes_in_group("dungeon").is_empty():
			break


func _sample(mgr: RTSManager, dungeon: Node) -> Dictionary:
	var s := {"t": dungeon.sim_time, "res": {}, "units": {}, "buildings": {}, "age": {}, "army_pos": {}}
	for fid in mgr.factions:
		var fi := int(fid)
		var res: Dictionary = (mgr.factions[fi]["resources"] as Dictionary).duplicate()
		s["res"][fi] = res
		s["units"][fi] = {}
		s["buildings"][fi] = {}
		s["age"][fi] = mgr.get_age(fi)
		s["army_pos"][fi] = [[0.0, 0.0, 0.0], 0]
	for u in get_tree().get_nodes_in_group("rts_units"):
		if not is_instance_valid(u):
			continue
		var fi := int(u.get("faction"))
		var d: Dictionary = s["units"].get(fi, {})
		var t := str(u.get("unit_type"))
		d[t] = int(d.get(t, 0)) + 1
		s["units"][fi] = d
		if t != "villager":
			var ap: Array = s["army_pos"][fi]
			var up: Vector3 = (u as Node3D).global_position
			ap[0] = [(ap[0] as Array)[0] + up.x, (ap[0] as Array)[1] + up.y, (ap[0] as Array)[2] + up.z]
			ap[1] = int(ap[1]) + 1
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if not is_instance_valid(b):
			continue
		var fi := int(b.get("faction"))
		var d: Dictionary = s["buildings"].get(fi, {})
		var t := str(b.get("building_type"))
		d[t] = int(d.get(t, 0)) + 1
		s["buildings"][fi] = d
	for fid in s["army_pos"]:
		var ap: Array = s["army_pos"][fid]
		if int(ap[1]) > 0:
			var tot: Array = ap[0]
			ap[0] = [tot[0] / float(ap[1]), tot[1] / float(ap[1]), tot[2] / float(ap[1])]
	return s


func _snapshot_stats(mgr: RTSManager) -> Dictionary:
	var out := {}
	for fid in mgr.sim_stats:
		var s: Dictionary = (mgr.sim_stats[fid] as Dictionary).duplicate(true)
		out[int(fid)] = s
	return out


func _strongest_faction(mgr: RTSManager) -> int:
	var best := -1
	var best_score := -1.0
	for fid in mgr.factions:
		if not bool((mgr.factions[fid] as Dictionary).get("alive", false)):
			continue
		var score := _faction_score(mgr, int(fid))
		if score > best_score:
			best_score = score
			best = int(fid)
	return best


func _faction_score(mgr: RTSManager, fid: int) -> float:
	var score := 0.0
	for u in get_tree().get_nodes_in_group("rts_units"):
		if is_instance_valid(u) and int(u.get("faction")) == fid:
			score += float(u.get("hp")) + float(u.get("max_hp")) * 0.5
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if is_instance_valid(b) and int(b.get("faction")) == fid and not bool(b.get("destroyed")):
			score += float(b.get("hp")) * 0.2
	var res: Dictionary = mgr.factions[fid]["resources"]
	for k in res:
		score += float(res[k]) * 0.5
	return score


func _write_report() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	var base := "res://" + _out_dir + "/report_" + stamp
	var tune_mtime := "unknown"
	var tune_sha := "unknown"
	var tp := "res://scripts/rts/rts_tuning.cfg"
	if FileAccess.file_exists(tp):
		tune_mtime = str(FileAccess.get_modified_time(tp))
		tune_sha = FileAccess.get_sha256(tp)
	var payload := {
		"generated": Time.get_datetime_string_from_system(),
		"matches": _matches,
		"time_scale": _time_scale,
		"base_seed": _base_seed,
		"timeout_min": _timeout_min,
		"tuning_file_mtime": tune_mtime,
		"tuning_file_sha256": tune_sha,
		"results": _results,
	}
	var jf := FileAccess.open(base + ".json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(payload, "\t"))
	jf.close()
	var md := _render_markdown(payload)
	var mf := FileAccess.open(base + ".md", FileAccess.WRITE)
	mf.store_string(md)
	mf.close()
	print("[Sim] report: %s.md" % base)
	print(_render_summary(payload))


func _civ_wins() -> Dictionary:
	var wins := {"iron_vanguard": 0, "shadow_covenant": 0, "arcane_dominion": 0, "draw": 0}
	for r in _results:
		var w := int(r["winner"])
		if w < 0:
			wins["draw"] += 1
		else:
			var civ: String = (r["civs"] as Dictionary).get(w, "draw")
			wins[civ] = int(wins.get(civ, 0)) + 1
	return wins


func _render_summary(payload: Dictionary) -> String:
	var wins := _civ_wins()
	var total := _results.size()
	var dur := 0.0
	for r in _results:
		dur += float(r["duration_s"])
	var avg_dur := dur / maxf(1.0, float(total))
	var lines: Array = []
	lines.append("== Balance report: %d matches, avg %.1f sim-min ==" % [total, avg_dur / 60.0])
	for civ in ["iron_vanguard", "shadow_covenant", "arcane_dominion"]:
		lines.append("  %s: %d wins (%.0f%%)" % [civ, int(wins[civ]), 100.0 * float(wins[civ]) / maxf(1.0, float(total))])
	if int(wins["draw"]) > 0:
		lines.append("  draws/timeouts: %d" % int(wins["draw"]))
	return "\n".join(lines)


func _render_markdown(payload: Dictionary) -> String:
	var wins := _civ_wins()
	var total := _results.size()
	var dur := 0.0
	for r in _results:
		dur += float(r["duration_s"])
	var avg_dur := dur / maxf(1.0, float(total))
	var L: Array = []
	L.append("# Warlord's Domain — AI-vs-AI balance report")
	L.append("")
	L.append("Generated %s. %d matches, avg duration %.1f sim-minutes, time_scale %.1f, base seed %d." % [
		str(payload["generated"]), total, avg_dur / 60.0, float(payload["time_scale"]), int(payload["base_seed"])])
	L.append("Tuning file sha256: `%s` (mtime %s)." % [str(payload["tuning_file_sha256"]), str(payload["tuning_file_mtime"])])
	L.append("")
	L.append("## Faction win rates")
	L.append("")
	L.append("| Faction | Wins | Win rate |")
	L.append("|---|---|---|")
	for civ in ["iron_vanguard", "shadow_covenant", "arcane_dominion"]:
		var w := int(wins[civ])
		L.append("| %s | %d | %.0f%% |" % [civ, w, 100.0 * float(w) / maxf(1.0, float(total))])
	if int(wins["draw"]) > 0:
		L.append("| draw/timeout | %d | |" % int(wins["draw"]))
	L.append("")
	L.append("## Per-match results")
	L.append("")
	L.append("| Match | Seed | Factions (0/1/2) | Winner | Duration (sim-min) |")
	L.append("|---|---|---|---|---|")
	for r in _results:
		var civs: Dictionary = r["civs"]
		var w := int(r["winner"])
		var wname := str(civs.get(w, "draw")) if w >= 0 else "draw"
		L.append("| %d | %d | %s / %s / %s | %s | %.1f |" % [
			int(r["match"]), int(r["seed"]),
			str(civs.get(0, "?")), str(civs.get(1, "?")), str(civs.get(2, "?")),
			wname, float(r["duration_s"]) / 60.0])
	L.append("")
	L.append("## Economy (average stockpiles per faction at 5-minute marks)")
	L.append("")
	L.append(_render_economy())
	L.append("")
	L.append("## Systems: siege / monks / naval usage (totals across all matches)")
	L.append("")
	L.append(_render_systems())
	L.append("")
	L.append("## Re-running")
	L.append("")
	L.append("Edit `scripts/rts/rts_tuning.cfg`, then run:")
	L.append("`godot --headless --path . res://tools/sim/sim_harness.tscn -- --matches 6`")
	L.append("and compare the win-rate table above against the new report.")
	L.append("")
	return "\n".join(L)


func _render_economy() -> String:
	# Average resources per faction at t = 5, 10, 15, 20 sim-minutes.
	var marks := [300.0, 600.0, 900.0, 1200.0]
	var L: Array = []
	var header := "| Faction |"
	for mk in marks:
		header += " %d min (w/f/g/s) |" % int(mk / 60.0)
	L.append(header)
	L.append("|---|---|---|---|---|")
	for civ in ["iron_vanguard", "shadow_covenant", "arcane_dominion"]:
		var row := "| %s |" % civ
		for mk in marks:
			var acc := {"wood": 0.0, "food": 0.0, "gold": 0.0, "stone": 0.0}
			var n := 0
			for r in _results:
				for fid in (r["civs"] as Dictionary):
					if str((r["civs"] as Dictionary)[fid]) != civ:
						continue
					var s := _nearest_sample(r["samples"], int(fid), mk)
					if s.is_empty():
						continue
					for k in acc:
						acc[k] += float((s["res"] as Dictionary).get(k, 0))
					n += 1
			if n > 0:
				row += " %.0f/%.0f/%.0f/%.0f |" % [acc["wood"] / n, acc["food"] / n, acc["gold"] / n, acc["stone"] / n]
			else:
				row += " — |"
		L.append(row)
	return "\n".join(L)


func _nearest_sample(samples: Array, fid: int, t: float) -> Dictionary:
	var best := {}
	var best_d := 1e9
	for s in samples:
		var d: float = absf(float(s["t"]) - t)
		if d < best_d:
			best_d = d
			best = s
	if best_d > 120.0:
		return {}
	var res: Dictionary = (best["res"] as Dictionary).get(fid, {})
	return {"res": res}


func _render_systems() -> String:
	var trained := {}
	var conv := 0
	var trade_n := 0
	var trade_g := 0
	var fish := 0
	for r in _results:
		for fid in (r["sim_stats"] as Dictionary):
			var s: Dictionary = (r["sim_stats"] as Dictionary)[fid]
			var ut: Dictionary = s.get("units_trained", {})
			for t in ut:
				trained[t] = int(trained.get(t, 0)) + int(ut[t])
			conv += int(s.get("conversions", 0))
			trade_n += int(s.get("trade_deliveries", 0))
			trade_g += int(s.get("trade_gold", 0))
			fish += int(s.get("fish_food", 0))
	var L: Array = []
	L.append("| Unit | Trained (all matches) |")
	L.append("|---|---|")
	for t in ["catapult", "ram", "monk", "trade_cart", "fishing_ship", "war_galley"]:
		L.append("| %s | %d |" % [t, int(trained.get(t, 0))])
	L.append("")
	L.append("- Monk conversions completed: **%d**" % conv)
	L.append("- Trade deliveries: **%d**, trade gold earned: **%d**" % [trade_n, trade_g])
	L.append("- Fishing ship food gathered: **%d**" % fish)
	return "\n".join(L)
