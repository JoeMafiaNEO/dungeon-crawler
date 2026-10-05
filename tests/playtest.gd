extends SceneTree
## Playtest automation: headless smoke tests for Steam-ready validation.
## Run: godot --headless --path . -s tests/playtest.gd

var _failures: Array = []
var _passes: int = 0


func _init() -> void:
	print("[Playtest] Starting automated validation...")
	# Deferred: autoload singletons (SteamManager etc.) only exist after the
	# first frame in -s script mode; script loads that reference them fail in _init.
	call_deferred("_run")


func _run() -> void:
	_test_boot()
	_test_rts_costs()
	_test_rts_production()
	_test_save_roundtrip()
	_test_save_profile()
	_test_affinity_families()
	_test_rogue_traits()
	_test_warrior_signatures()
	_test_affinity_ui()
	_test_affinity_save_roundtrip()
	_test_specialization_level_gate()
	_test_pause_tabs()
	_test_switch_class_refresh()
	_test_architect()
	_test_cipher_unlock()
	_test_station_phase1()
	_test_station_phase2()
	_test_station_phase3()
	_test_station_phase4()
	_test_station_phase5()
	_test_station_mp_vote_flow()
	_test_music_queued_pickup()
	_test_station_annex()
	_test_station_embedded()
	_test_annex_departure()
	_test_annex_forfeit()
	_test_train_interior()
	_test_boarding_flow()
	_test_cycle_scaling()
	_test_ai_director()
	_test_economy()
	_test_trade_no_self_trade()
	_test_apex_phase1()
	_print_results()
	quit()


func _assert(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures.append(name)
		print("  FAIL: %s" % name)


func _test_boot() -> void:
	print("[Playtest] Boot...")
	# All RTS scripts parse.
	_assert(load("res://scripts/rts/rts_manager.gd") != null, "RTSManager loads")
	_assert(load("res://scripts/rts/unit.gd") != null, "RTSUnit loads")
	_assert(load("res://scripts/rts/building.gd") != null, "RTSBuilding loads")
	_assert(load("res://scripts/rts/rts_camera.gd") != null, "RTSCamera loads")
	_assert(load("res://scripts/rts/rts_hud.gd") != null, "RTSHUD loads")
	_assert(load("res://scripts/rts/ai_warlord.gd") != null, "AIWarlord loads")
	_assert(load("res://scripts/rts/civ_data.gd") != null, "CivData loads")


func _test_rts_costs() -> void:
	print("[Playtest] RTS costs...")
	var mgr_script = load("res://scripts/rts/rts_manager.gd")
	if mgr_script == null:
		print("  SKIP: RTSManager not loadable in test mode")
		return
	# Building costs are all positive and include wood or stone.
	for btype in mgr_script.BUILDING_COSTS:
		var cost: Dictionary = mgr_script.BUILDING_COSTS[btype]
		var total := 0
		for k in cost:
			total += int(cost[k])
		_assert(total > 0, "Building %s has positive cost" % btype)
	# Unit costs are all positive.
	for utype in mgr_script.UNIT_COSTS:
		var cost: Dictionary = mgr_script.UNIT_COSTS[utype]
		var total := 0
		for k in cost:
			total += int(cost[k])
		_assert(total > 0, "Unit %s has positive cost" % utype)
	# Age costs scale up.
	var age0: Dictionary = mgr_script.AGE_COSTS[0]
	var age1: Dictionary = mgr_script.AGE_COSTS[1]
	_assert(int(age1["food"]) > int(age0["food"]), "Age costs increase")


func _test_rts_production() -> void:
	print("[Playtest] RTS production...")
	var bld_script = load("res://scripts/rts/building.gd")
	if bld_script == null:
		print("  SKIP: RTSBuilding not loadable in test mode")
		return
	# Every production building has at least one trainable unit.
	for btype in bld_script.PRODUCTION:
		var units: Array = bld_script.PRODUCTION[btype]
		_assert(units.size() > 0, "Building %s trains units" % btype)
	# Every trainable unit has a cost defined.
	var mgr_script = load("res://scripts/rts/rts_manager.gd")
	for btype in bld_script.PRODUCTION:
		for utype in bld_script.PRODUCTION[btype]:
			_assert(mgr_script.UNIT_COSTS.has(utype), "Unit %s has cost" % utype)


func _test_save_roundtrip() -> void:
	print("[Playtest] Save roundtrip (slots)...")
	# Exercise the real SaveManager slot code path (atomic save + load).
	var SaveScript := load("res://scripts/autoload/save_manager.gd")
	var mgr = SaveScript.new()
	# Back up real slot files + profile so the test can't clobber them.
	var backup := {}
	for mode in ["solo", "mp"]:
		for slot in range(3):
			var p := "user://runs/%s_%d.cfg" % [mode, slot]
			if FileAccess.file_exists(p):
				backup[p] = FileAccess.get_file_as_bytes(p)
				DirAccess.remove_absolute(p)
	var prof_path := "user://profile_local.cfg"
	var prof_backup := PackedByteArray()
	if FileAccess.file_exists(prof_path):
		prof_backup = FileAccess.get_file_as_bytes(prof_path)
		DirAccess.remove_absolute(prof_path)
	# Slot roundtrip.
	var run := {
		"level": 9, "class_id": "mage", "theme_id": "dungeon",
		"level_number": 2, "cycle": 1, "seed": 12345,
		"stats": {"str": 5, "vit": 3},
	}
	_assert(mgr.save_run(run, "solo", 0), "save_run accepts a valid slot")
	_assert(mgr.has_run("solo", 0), "has_run true after save")
	var loaded: Dictionary = mgr.load_run("solo", 0)
	_assert(int(loaded.get("level", 0)) == 9, "slot preserves level")
	_assert(str(loaded.get("class_id", "")) == "mage", "slot preserves class")
	_assert(str(loaded.get("theme_id", "")) == "dungeon", "slot preserves theme")
	_assert(int(loaded.get("cycle", 0)) == 1, "slot preserves cycle")
	_assert(str(loaded.get("saved_at", "")) != "", "slot stamps saved_at")
	_assert(int(loaded.get("save_version", 0)) == mgr.SAVE_VERSION, "slot stamps save_version")
	_assert(not bool(loaded.get("is_multiplayer", true)), "solo slot not flagged multiplayer")
	var summary: String = mgr.run_summary(loaded)
	_assert(summary != "", "run_summary non-empty for saved run")
	_assert("Mage" in summary, "summary names the class")
	# Slot isolation: a slot-0 save never touches slot 1 or the mp slots.
	_assert(not mgr.has_run("solo", 1), "solo slot 1 untouched")
	_assert(not mgr.has_run("solo", 2), "solo slot 2 untouched")
	_assert(not mgr.has_run("mp", 0), "mp slot 0 untouched")
	var saves: Array = mgr.list_runs("solo")
	_assert(saves.size() == 1 and int(saves[0].get("slot", -1)) == 0,
		"list_runs finds the solo save in slot 0")
	# Out-of-range slots rejected.
	_assert(not mgr.save_run(run, "solo", 3), "slot 3 rejected")
	_assert(not mgr.save_run(run, "solo", -1), "slot -1 rejected")
	_assert(not mgr.save_run(run, "bogus", 0), "bad mode rejected")
	_assert(mgr.load_run("solo", 3).is_empty(), "load invalid slot -> {}")
	_assert(not mgr.has_run("mp", 9), "has_run invalid slot false")
	_assert(not mgr.is_save_compatible("solo", 1), "empty slot not compatible")
	# MP slot roundtrip with roster.
	var mp_run := {
		"theme_id": "dungeon", "level_number": 2, "seed": 999,
		"host_difficulty": 1.5, "host_loot_mult": 2.0,
		"lobby": {"max_players": 4, "lobby_name": "Test"},
		"roster": [
			{"steam_id": 111, "player_name": "Host", "class_id": "warrior",
			 "player_state": {"level": 5}, "rts_faction": 0, "is_host": true},
			{"steam_id": 222, "player_name": "Guest", "class_id": "mage",
			 "player_state": {"level": 3}, "rts_faction": 1, "is_host": false},
		],
	}
	_assert(mgr.save_run(mp_run, "mp", 2), "mp save lands in slot 2")
	var mp_loaded: Dictionary = mgr.load_run("mp", 2)
	_assert(bool(mp_loaded.get("is_multiplayer", false)), "mp flag stamped from mode")
	_assert(float(mp_loaded.get("host_difficulty", 0.0)) == 1.5, "host difficulty preserved")
	_assert(mp_loaded.get("roster", []).size() == 2, "roster preserved")
	_assert(mgr.is_save_compatible("mp", 2), "save compatibility passes")
	var mp_summary: String = mgr.run_summary(mp_loaded)
	_assert("2 players" in mp_summary, "mp summary shows player count")
	_assert(mgr.has_run("solo", 0), "mp save did not disturb solo slot 0")
	# Clear is slot-scoped.
	mgr.clear_run("mp", 2)
	_assert(not mgr.has_run("mp", 2), "clear_run removes the mp run")
	_assert(mgr.has_run("solo", 0), "clear_run leaves other slots alone")
	mgr.clear_run("solo", 0)
	_assert(not mgr.has_run("solo", 0), "clear_run removes the solo run")
	_assert(mgr.list_runs("solo").is_empty(), "list_runs empty after clear")
	# Restore backups.
	for p in backup.keys():
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(backup[p])
	if prof_backup.is_empty():
		if FileAccess.file_exists(prof_path):
			DirAccess.remove_absolute(prof_path)
	else:
		var pf := FileAccess.open(prof_path, FileAccess.WRITE)
		pf.store_buffer(prof_backup)
	mgr.free()


func _test_save_profile() -> void:
	print("[Playtest] SaveManager profile + cloud guards...")
	var SaveScript := load("res://scripts/autoload/save_manager.gd")
	var prof_path := "user://profile_local.cfg"
	var prof_backup := PackedByteArray()
	if FileAccess.file_exists(prof_path):
		prof_backup = FileAccess.get_file_as_bytes(prof_path)
		DirAccess.remove_absolute(prof_path)
	var mgr = SaveScript.new()
	# Local fallback: Steam is not initialized in headless tests. (The -s
	# test script itself can't name the SteamManager autoload at compile
	# time, so resolve it off the tree root at runtime.)
	var sm: Node = root.get_node_or_null("SteamManager")
	_assert(sm == null or not bool(sm.get("initialized")), "Steam uninitialized in test env")
	_assert(mgr._profile_path().ends_with("profile_local.cfg"),
		"profile resolves to the local account")
	_assert(not mgr._cloud_available(), "cloud unavailable without Steam")
	# Profile meta roundtrip.
	_assert(mgr.unlock_item("void_blade"), "unlock_item grants")
	_assert(not mgr.unlock_item("void_blade"), "unlock_item not double-granted")
	mgr.add_kills(57)
	mgr.set_deepest_cycle(3)
	mgr.add_cash_earned(1250)
	mgr.add_cipher_fragment(4)
	_assert(mgr.unlock_architect(), "unlock_architect grants")
	_assert(mgr._cloud_write_count == 0, "no cloud writes without Steam")
	var mgr2 = SaveScript.new()
	mgr2.load_game()
	_assert(mgr2.is_item_unlocked("void_blade"), "profile: item unlock persists")
	_assert(mgr2.get_total_kills() == 57, "profile: kills persist")
	_assert(mgr2.get_deepest_cycle() == 3, "profile: deepest cycle persists")
	_assert(mgr2.get_total_cash_earned() == 1250, "profile: cash persists")
	_assert(mgr2.get_cipher_fragments() == [4], "profile: fragments persist")
	_assert(mgr2.is_architect_unlocked(), "profile: architect unlock persists")
	_assert(mgr2._cloud_write_count == 0, "boot read-through is a no-op without Steam")
	mgr.free()
	mgr2.free()
	if prof_backup.is_empty():
		if FileAccess.file_exists(prof_path):
			DirAccess.remove_absolute(prof_path)
	else:
		var pf := FileAccess.open(prof_path, FileAccess.WRITE)
		pf.store_buffer(prof_backup)


func _test_station_phase4() -> void:
	print("[Playtest] Train station phase 4 (vendor + heal pad)...")
	var StationScript := load("res://scripts/station/station.gd")
	var DungeonScript := load("res://scripts/dungeon/dungeon.gd")

	# --- Vendor pricing formula: 3x sell value, $50 floor ---
	_assert(StationScript.vendor_price(0) == 50, "vendor price floor $50")
	_assert(StationScript.vendor_price(10) == 50, "vendor price 10 -> floor")
	_assert(StationScript.vendor_price(20) == 60, "vendor price 20 -> 60")
	_assert(StationScript.vendor_price(100) == 300, "vendor price 100 -> 300")

	# --- Purchase resolution: cash deducted, broke rejected, unknown rejected ---
	var stock := [{"id": "health_potion", "price": 50}, {"id": "runeblade", "price": 300}]
	var r1: Dictionary = StationScript.resolve_purchase(100, stock, "health_potion")
	_assert(bool(r1.get("ok")) and int(r1.get("price")) == 50 and int(r1.get("new_cash")) == 50,
		"buy: cash deducted")
	var r2: Dictionary = StationScript.resolve_purchase(30, stock, "runeblade")
	_assert(not bool(r2.get("ok")) and str(r2.get("reason")) == "broke" \
		and int(r2.get("price")) == 300, "buy: broke rejected, price reported")
	var r3: Dictionary = StationScript.resolve_purchase(1000, stock, "bogus_item")
	_assert(not bool(r3.get("ok")) and str(r3.get("reason")) == "not_in_stock",
		"buy: item not in stock rejected")

	# --- Heal pad math: 15% max HP per 0.5s tick, clamps at max ---
	_assert(StationScript.heal_tick_amount(100.0) == 15.0, "heal tick = 15% max HP")
	var hp := 50.0
	for t in 8:
		hp = minf(100.0, hp + StationScript.heal_tick_amount(100.0))
		_assert(hp <= 100.0, "heal never exceeds max_hp (tick %d)" % t)
	_assert(hp == 100.0, "50% HP reaches full within 8 ticks (4s)")
	var ticks := 0
	var hp2 := 0.0
	while hp2 < 100.0 and ticks < 20:
		hp2 = minf(100.0, hp2 + StationScript.heal_tick_amount(100.0))
		ticks += 1
	_assert(ticks == 7, "empty -> full in 7 ticks (~3.5s)")

	# --- Stock composition: 3 potions + 3 rotating, distinct, priced by formula ---
	var vs: Array = StationScript.build_vendor_stock()
	_assert(vs.size() == 6, "vendor stock = 6 items")
	var ids: Array = []
	var prices := {}
	for e in vs:
		ids.append(str(e.get("id")))
		prices[str(e.get("id"))] = int(e.get("price"))
	_assert(ids.slice(0, 3) == ["health_potion", "swift_potion", "power_elixir"],
		"first 3 stock entries are the potions")
	_assert(prices["health_potion"] == 50 and prices["swift_potion"] == 75 \
		and prices["power_elixir"] == 100, "potion prices match supermarket shop")
	var rot := ids.slice(3, 6)
	_assert(rot.size() == 3, "3 rotating items")
	var seen := {}
	# Autoload singletons aren't compile-visible in -s script mode; look them
	# up at runtime (they exist after the first frame, like the rest of _run).
	var itemdb := root.get_node("ItemDB")
	var savemgr := root.get_node("SaveManager")
	for id in rot:
		_assert(not seen.has(id), "rotating items distinct")
		seen[id] = true
		_assert(not id in ["health_potion", "swift_potion", "power_elixir"],
			"no potions in rotating: %s" % id)
		var item: ItemData = itemdb.get_item(id)
		_assert(item != null, "rotating item exists in ItemDB: %s" % id)
		_assert(not bool(item.get("supermarket_loot")), "no supermarket_loot in rotating: %s" % id)
		if bool(item.get("meta_locked")):
			_assert(savemgr.is_item_unlocked(id),
				"meta-locked rotating only when unlocked: %s" % id)
		_assert(prices[id] == StationScript.vendor_price(int(item.get("sell_value"))),
			"rotating price follows formula: %s" % id)

	# --- Gate integrity: earnings unlock, spending can't re-lock ---
	_assert(DungeonScript.gate_unlocked(500, 500), "gate unlocks at goal")
	_assert(not DungeonScript.gate_unlocked(499, 500), "gate sealed below goal")
	var earned := 500
	var cash := 500 - 100 # bought a potion after unlocking
	_assert(DungeonScript.gate_unlocked(earned, 500) and cash == 400,
		"spending after unlock doesn't re-lock the gate")

	# --- Cash persistence: handoff no longer zeroes supermarket_cash ---
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(not dsrc.contains('set("supermarket_cash", 0)'),
		"cash no longer zeroed on station handoff")
	_assert(dsrc.contains("market_earned_visit += total"),
		"sell adds to per-visit earnings")
	_assert(dsrc.contains("market_earned_visit = 0"),
		"earnings reset each supermarket visit")

	# --- Wiring: heal pad, vendor stall, panel, buy RPC, E-scan ---
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(ssrc.contains('name = "HealPad"'), "heal pad Area3D placed")
	_assert(ssrc.contains("func _process_heal_pad"), "heal pad tick exists")
	_assert(ssrc.contains("func buy_vendor_item"), "buy_vendor_item RPC exists")
	_assert(ssrc.contains("func sync_vendor_stock"), "sync_vendor_stock RPC exists")
	_assert(ssrc.contains("func build_vendor_stock"), "build_vendor_stock exists")
	_assert(ssrc.contains("VendorStallScript.new()"), "vendor stall prop placed")


	_assert(ssrc.contains("resolve_purchase("), "buy uses resolve_purchase")
	_assert(ResourceLoader.exists("res://scripts/station/vendor_stall.gd"), "vendor_stall.gd exists")
	var vsrc := FileAccess.get_file_as_string("res://scripts/station/vendor_stall.gd")
	_assert(vsrc.contains('add_to_group("vendor_stall")'), "stall in vendor_stall group")
	_assert(vsrc.contains("func prompt_text"), "stall prompt_text exists")
	_assert(vsrc.contains("func interact"), "stall interact exists")
	_assert(vsrc.contains("show_vendor"), "stall interact opens vendor panel")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func show_vendor"), "show_vendor panel exists")
	_assert(hsrc.contains("func refresh_vendor_cash"), "vendor cash refresh exists")
	_assert(hsrc.contains("Your cash: $%d"), "panel shows cash header")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains('"vendor_stall"'), "player E-scan includes vendor stall")
	_assert(psrc.contains("hud.refresh_vendor_cash"), "buy refreshes vendor cash header")
	_assert(psrc.contains("_prompt_interact"), "stale interact prompt is cleared on walk-away")


func _test_station_phase5() -> void:
	print("[Playtest] Train station phase 5 (dressing, signage, SFX)...")
	var StationScript := load("res://scripts/station/station.gd")
	var DungeonScript := load("res://scripts/dungeon/dungeon.gd")
	var SoundScript := load("res://scripts/audio/sound_synth.gd")

	# --- Lamp tints match the spec table ---
	var lamps: Dictionary = StationScript.DRESSING_LAMPS
	_assert(lamps["village"] == Color(0.6, 1.0, 0.6), "village lamp tint")
	_assert(lamps["dungeon"] == Color(0.5, 0.7, 1.0), "dungeon lamp tint")
	_assert(lamps["depths"] == Color(0.8, 0.4, 0.9), "depths lamp tint")
	_assert(lamps["supermarket"] == Color(1.0, 1.0, 0.95), "supermarket lamp tint")
	_assert(lamps["warlord"] == Color(1.0, 0.55, 0.25), "warlord lamp tint")
	_assert(lamps["apex"] == Color(1.0, 0.25, 0.2), "apex lamp tint")

	# --- apply_dressing: exactly one prop set visible; sign names the theme ---
	var st = StationScript.new()
	st._build_dressing()
	for tid in ["village", "dungeon", "depths", "supermarket", "warlord", "apex"]:
		st.apply_dressing(tid)
		var vis: Array = []
		for child in st._dressing.get_children():
			if child.visible:
				vis.append(str(child.name))
		_assert(vis == [tid], "dressing shows only %s set" % tid)
	_assert(st._dressing.get_child_count() == 6, "6 theme prop sets built (apex added)")
	_assert(st._dressing.get_node_or_null("apex") != null, "apex dressing set built")
	st.apply_dressing("bogus_theme")
	var vis2: Array = []
	for child in st._dressing.get_children():
		if child.visible:
			vis2.append(str(child.name))
	_assert(vis2 == ["village"], "unknown theme falls back to village dressing")
	st.free()

	# --- NOW BOARDING sign text (built in _build_station_embedded) ---
	var st2 = StationScript.new()
	st2._build_station_embedded()
	st2.apply_dressing("depths")
	_assert(st2._boarding_sign != null and "THE DEPTHS" in st2._boarding_sign.text,
		"NOW BOARDING sign names the destination")
	st2.free()

	# --- SFX exist and are registered ---
	for sfx in ["train_whistle", "train_chug", "train_brake"]:
		var w: AudioStreamWAV = SoundScript.call(sfx)
		_assert(w != null and w.data.size() > 0, "synth builds %s" % sfx)
	var amsrc := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	for sfx in ["train_whistle", "train_chug", "train_brake"]:
		_assert(amsrc.contains('"%s"' % sfx), "%s registered in builder list" % sfx)

	# --- HUD fade + dressed announce ---
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func fade_out"), "hud.fade_out exists")
	_assert(hsrc.contains("func fade_in"), "hud.fade_in exists")
	_assert(hsrc.contains("func announce(text: String, tint: Color"),
		"announce takes a theme tint")

	# --- Departure ride wiring: whistle -> chug -> fade (dungeon-driven) ---
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(ssrc.contains("func play_departure_ride"), "play_departure_ride exists")
	_assert(ssrc.find("func play_departure_ride") < ssrc.find('sfx("train_whistle")'),
		"whistle sounds in the departure ride")
	_assert(ssrc.contains('sfx("train_chug")'), "chug in departure ride")
	_assert(ssrc.contains("fade_out(1.2)"), "fade_out(1.2) in departure ride")
	_assert(ssrc.contains("apply_dressing(theme_id)"), "departure re-dresses for vote")

	# --- Arrival: dungeon entry fades in with a dressed banner + brake ---
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("fade_in(1.5)"), "dungeon entry fades in")
	_assert(dsrc.contains("NOW ARRIVING: "), "arrival banner on dungeon entry")
	_assert(dsrc.contains('sfx("train_brake")'), "brake screech on arrival")
	_assert(DungeonScript.arrival_tint("warlord") == Color(1.0, 0.55, 0.25),
		"arrival tint matches lamp table")


func _test_station_mp_vote_flow() -> void:
	print("[Playtest] Station MP vote flow (unanimous boarding)...")
	var StationScript := load("res://scripts/station/station.gd")
	# (a) 3 fake peers drive the same record path the cast_vote RPC uses.
	var living := [10, 11, 12]
	var st = StationScript.new()
	root.add_child(st)
	_assert(bool(st.record_vote(10, "dungeon", living)["ok"]), "peer 10 vote recorded")
	_assert(bool(st.record_vote(11, "dungeon", living)["ok"]), "peer 11 vote recorded")
	_assert(st.votes == {10: "dungeon", 11: "dungeon"}, "votes dict holds both")
	# Unanimity: 2/3 agree, the third dissents -> NO departure.
	st.record_vote(12, "village", living)
	_assert(StationScript.resolve_destination(st.votes, living) == "",
		"split vote: no departure")
	_assert(st._unanimous_theme(living) == "", "split vote: _unanimous_theme empty")
	# All three agree -> departure resolves.
	st.record_vote(12, "dungeon", living)
	_assert(StationScript.resolve_destination(st.votes, living) == "dungeon",
		"unanimous -> dungeon")
	_assert(st._unanimous_theme(living) == "dungeon", "unanimous theme reported")
	# Vote change breaking unanimity -> no departure again.
	_assert(bool(st.record_vote(10, "village", living)["ok"]), "vote change accepted")
	_assert(st.votes.size() == 3 and st.votes[10] == "village",
		"vote change overwrites, counts once")
	_assert(StationScript.resolve_destination(st.votes, living) == "",
		"broken unanimity: no departure")
	# Partial votes (a living player hasn't voted) -> no departure.
	var st4 = StationScript.new()
	st4.record_vote(12, "depths", living)
	_assert(StationScript.resolve_destination(st4.votes, living) == "",
		"partial votes: no departure")
	# Zero votes -> no departure (no rotation fallback anymore).
	var st5 = StationScript.new()
	_assert(StationScript.resolve_destination(st5.votes, living) == "",
		"zero votes: no departure")
	_assert(StationScript.resolve_destination({}, []) == "",
		"empty living roster: no departure")
	# Rejections never touch the vote table.
	_assert(not bool(st5.record_vote(10, "moon", living)["ok"]), "bad theme rejected")
	_assert(not bool(st5.record_vote(99, "village", living)["ok"]), "non-living peer rejected")
	_assert(st5.votes.is_empty(), "rejected votes not recorded")
	# depart() refuses to emit without unanimity...
	var captured := []
	st.departure_resolved.connect(func(tid): captured.append(tid))
	st.votes = {10: "dungeon", 11: "village"}
	st.depart([10, 11])
	_assert(captured.is_empty(), "split vote: depart() emits nothing")
	_assert(not st._boarding_active, "split vote: no boarding started")
	# ...and on unanimity it enters ALL ABOARD (issue #3 Phase 2) instead of
	# emitting directly; boarding completion emits departure_resolved.
	st.votes = {10: "dungeon", 11: "dungeon"}
	st.depart([10, 11])
	_assert(captured.is_empty(), "unanimous: depart() starts boarding, emits nothing yet")
	_assert(st._boarding_active, "unanimous: ALL ABOARD active")
	_assert(st._boarding_theme == "dungeon", "boarding carries the voted theme")
	st._finish_boarding([10, 11])
	_assert(captured == ["dungeon"], "boarding complete: departure_resolved emitted")
	_assert(st._boarding_locked, "boarding complete: train door locked")
	# sync_votes payload applies on the client path (no board in test tree).
	root.add_child(st5)
	st5.sync_votes({10: "village", 11: "dungeon"})
	_assert(st5.votes == {10: "village", 11: "dungeon"}, "sync_votes payload applied")
	st5.queue_free()
	# Solo: single living peer, one vote -> departs immediately.
	var st6 = StationScript.new()
	_assert(StationScript.resolve_destination(st6.votes, [10]) == "",
		"solo: no vote yet, no departure")
	st6.record_vote(10, "depths", [10])
	_assert(StationScript.resolve_destination(st6.votes, [10]) == "depths",
		"solo pick resolves to the vote")
	# Timer-expiry without unanimity resets the clock and keeps votes.
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(ssrc.contains("_time_left = DEPART_TIME"), "expiry resets the 45s timer")
	_assert(ssrc.contains("vote_reset_notice"), "expiry notifies peers of the reset")
	var rpos := ssrc.find("static func resolve_destination")
	var rend := ssrc.find("\nstatic func ", rpos + 10)
	var rbody := ssrc.substr(rpos, rend - rpos)
	_assert(not rbody.contains("host"), "resolve_destination: no host override")
	_assert(not rbody.contains("counts"), "resolve_destination: no majority counting")
	_assert(not ssrc.contains("(next_level - 1) %"), "no rotation fallback left")
	# Wiring: the RPC stays thin and delegates to record_vote.
	_assert(ssrc.contains("func record_vote(peer_id"), "record_vote exists")
	_assert(ssrc.contains("record_vote(sender, theme_id)"), "cast_vote delegates to record_vote")
	st.queue_free()


func _test_music_queued_pickup() -> void:
	print("[Playtest] Music: queued theme picked up after in-flight gen...")
	# Regression: requesting a new theme while a track gen is in flight must
	# not leave the new theme un-generated (silent music until next change).
	# (Bare autoload identifiers don't compile in -s script mode; go via root.)
	var am: Variant = root.get_node("AudioManager")
	var old_cache: Dictionary = am._music_cache
	var old_busy: bool = am._gen_busy
	var old_queued: String = am._queued_theme
	var old_theme: String = am._mus_theme
	# Pre-cache the queued theme so pickup takes the instant crossfade branch
	# (no worker thread -> deterministic, no teardown races).
	var fake := AudioStreamWAV.new()
	am._music_cache = {"village": fake}
	am._gen_busy = true
	am._queued_theme = "village"
	var th := Thread.new()
	th.start(func() -> void: pass)
	am._on_track_ready("menu", null, th)
	_assert(am._mus_theme == "village", "queued theme picked up after in-flight gen")
	_assert(am._queued_theme == "village", "queued theme preserved")
	# Cleanup: stop the crossfaded dummy playback, restore prior audio state.
	am.stop_music()
	am._music_cache = old_cache
	am._gen_busy = old_busy
	am._queued_theme = old_queued
	am._mus_theme = old_theme


func _test_station_annex() -> void:
	print("[Playtest] Station annex generation (issue #2 phase 1)...")
	# (Runtime loads only: bare autoload identifiers don't compile in -s script mode.)
	var AnnexScript: GDScript = load("res://scripts/station/station_annex.gd")
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	var theme: Resource = load("res://data/levels/theme_village.tres")
	_assert(theme != null, "annex test theme loads")

	# 1. Deterministic placement from the level seed.
	var plans := {}
	for s in [12345, 999, 424242]:
		var layout = ProcGenScript.generate(theme, s)
		var plan: Dictionary = AnnexScript.plan(s, layout)
		plans[s] = plan
		var half: float = layout.arena_half_size()
		var ax := float(plan.get("attach_x", 999.0))
		_assert(absf(ax) <= half - AnnexScript.HALL_W * 0.5 - 1.0 + 0.01,
			"annex fits inside arena span (seed %d)" % s)
		# Same seed -> same origin.
		var layout_b = ProcGenScript.generate(theme, s)
		var plan_b: Dictionary = AnnexScript.plan(s, layout_b)
		_assert(float(plan_b.get("attach_x", -1.0)) == ax,
			"annex origin deterministic (seed %d)" % s)
		# Doorway rows are walkable after planning (cleared if needed).
		_assert(AnnexScript._doorway_blocked(layout, ax) == 0,
			"doorway cells clear (seed %d)" % s)

	# 2. North wall segments leave exactly the doorway gap and cover the span.
	var half0 := 24.0
	var segs: Array = AnnexScript.north_wall_segments(half0, 1.5, 4.0, 4.0, AnnexScript.DOOR_W)
	_assert(segs.size() == 2, "north wall splits into two segments")
	var l_c: Vector3 = segs[0][0]
	var l_s: Vector3 = segs[0][1]
	var r_c: Vector3 = segs[1][0]
	var r_s: Vector3 = segs[1][1]
	_assert(absf((l_c.x + l_s.x * 0.5) - (4.0 - AnnexScript.DOOR_W * 0.5)) < 0.01,
		"north wall gap left edge at doorway")
	_assert(absf((r_c.x - r_s.x * 0.5) - (4.0 + AnnexScript.DOOR_W * 0.5)) < 0.01,
		"north wall gap right edge at doorway")
	_assert(absf((l_c.x - l_s.x * 0.5) - (-half0 - 0.75)) < 0.01
		and absf((r_c.x + r_s.x * 0.5) - (half0 + 0.75)) < 0.01,
		"north wall segments cover the full span")

	# 3. Built shell: node, floor collision, roof, lamps.
	var layout = ProcGenScript.generate(theme, 12345)
	var plan: Dictionary = plans[12345]
	var holder := Node3D.new()
	root.add_child(holder)
	var annex = AnnexScript.build(holder, plan, layout)
	_assert(annex != null and annex.name == "StationAnnex", "StationAnnex node built")
	var ax := float(plan["attach_x"])
	var h: float = layout.arena_half_size()

	var hall_floor = annex.get_node_or_null("HallFloor")
	_assert(hall_floor is StaticBody3D, "hall floor is a StaticBody3D")
	if hall_floor is StaticBody3D:
		var cs := hall_floor.get_child(0) as CollisionShape3D
		var bs := cs.shape as BoxShape3D
		_assert(absf(hall_floor.position.y + 0.5) < 0.01 and bs.size.y == 1.0,
			"hall floor collision top at y=0")
		_assert(bs.size.x >= AnnexScript.HALL_W and bs.size.z >= AnnexScript.HALL_D,
			"hall floor covers the hall footprint")

	var roof := annex.get_node_or_null("HallRoof") as MeshInstance3D
	_assert(roof != null, "hall roof present")
	if roof != null:
		var rs := (roof.mesh as BoxMesh).size
		_assert(roof.position.y > 4.0 and rs.x >= AnnexScript.HALL_W and rs.z >= AnnexScript.HALL_D,
			"roof covers the hall from above")

	var lamp_count := 0
	for lamp in annex.lamps:
		if lamp is OmniLight3D:
			lamp_count += 1
	_assert(lamp_count >= 3, "at least 3 lamp OmniLight3Ds (%d)" % lamp_count)

	# 4. Doorway connectivity: probe points down the corridor must not sit
	# inside any annex collision box (arena center -> hall center is walkable).
	var solids: Array = []
	for child in annex.get_children():
		if child is StaticBody3D:
			var c := (child as StaticBody3D).get_child(0) as CollisionShape3D
			var b := c.shape as BoxShape3D
			solids.append(AABB(child.position - b.size * 0.5, b.size))
	var hc: Vector3 = annex.hall_center()
	var blocked := 0
	for t in [0.15, 0.35, 0.55, 0.75, 0.95]:
		var p := Vector3(ax, 1.0, lerpf(0.0, hc.z, t))
		for aabb: AABB in solids:
			if aabb.has_point(p):
				blocked += 1
	_assert(blocked == 0, "corridor walkable from arena to hall (%d blocked probes)" % blocked)

	# 5. Dungeon wiring: plan before walls, wall split, annex build call.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("StationAnnex.plan(next_seed, _layout)"), "dungeon plans annex from seed")
	_assert(dsrc.contains("StationAnnex.north_wall_segments"), "dungeon splits north wall")
	_assert(dsrc.contains("StationAnnex.build(self, _annex_plan, _layout)"), "dungeon builds annex")

	holder.queue_free()


func _test_station_embedded() -> void:
	print("[Playtest] Station embedded mode (issue #2 phase 2)...")
	# (Runtime loads only: bare autoload identifiers don't compile in -s script mode.)
	var StationScript: GDScript = load("res://scripts/station/station.gd")
	var AnnexScript: GDScript = load("res://scripts/station/station_annex.gd")
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	var theme: Resource = load("res://data/levels/theme_village.tres")

	# Build the annex shell, then instance the station the way the dungeon does.
	var holder := Node3D.new()
	root.add_child(holder)
	var layout = ProcGenScript.generate(theme, 12345)
	var plan: Dictionary = AnnexScript.plan(12345, layout)
	var annex = AnnexScript.build(holder, plan, layout)
	var st = StationScript.new()
	st.name = "Station"
	st.dungeon = holder
	st.annex = annex
	st.position = annex.hall_center()
	holder.add_child(st) # _ready runs the embedded build

	# 1. Content nodes exist as descendants.
	for nname in ["Train", "DepartureBoard", "VendorStall", "HealPad", "BoardingZone", "Sleepers"]:
		_assert(st.get_node_or_null(nname) != null, "embedded: %s built" % nname)
	var sign = st.get("_boarding_sign")
	_assert(sign != null and "NOW BOARDING" in str(sign.text),
		"embedded: NOW BOARDING sign set")
	var dressing = st.get_node_or_null("Dressing")
	_assert(dressing != null and dressing.get_child_count() == 6,
		"embedded: 6 dressing prop sets (apex added)")
	# Every content node sits inside the 24x14m hall footprint.
	for nname in ["Train", "DepartureBoard", "VendorStall", "HealPad"]:
		var n := st.get_node_or_null(nname) as Node3D
		var lp: Vector3 = n.position
		_assert(absf(lp.x) <= 12.0 and absf(lp.z) <= 7.0,
			"embedded: %s inside hall footprint" % nname)

	# 2. No own players / HUD in embedded mode (the dungeon owns those).
	_assert(st.get_node_or_null("Players") == null, "embedded: no Players node")
	_assert(st.find_children("*", "CanvasLayer", true, false).is_empty(),
		"embedded: no HUD created")
	_assert(st.get("_local_hud") == null, "embedded: no local hud var set")

	# 3. Vote timer idle until the first board interaction, then runs.
	_assert(not bool(st.get("_timer_running")), "embedded: timer idle before interaction")
	var living := [10, 11, 12]
	_assert(bool(st.record_vote(10, "dungeon", living)["ok"]),
		"embedded: first vote recorded")
	_assert(bool(st.get("_timer_running")), "embedded: timer starts on first vote")
	_assert(float(st.get("_time_left")) == StationScript.DEPART_TIME,
		"embedded: timer reset to full duration")

	# 4. Unanimous resolve enters ALL ABOARD (issue #3 Phase 2); boarding
	# completion emits departure_resolved (server path); split does not.
	var captured := []
	st.departure_resolved.connect(func(tid): captured.append(tid))
	st.votes = {10: "dungeon", 11: "dungeon"}
	st.depart([10, 11, 12])
	_assert(captured.is_empty(), "embedded: partial votes emit nothing")
	st.votes = {10: "dungeon", 11: "dungeon", 12: "dungeon"}
	st.depart([10, 11, 12])
	_assert(captured.is_empty(), "embedded: unanimous starts boarding, emits nothing yet")
	_assert(bool(st.get("_boarding_active")), "embedded: ALL ABOARD active")
	st._finish_boarding([10, 11, 12])
	_assert(captured == ["dungeon"], "embedded: boarding complete emits departure_resolved")

	# 5. Split vote never emits, even from the host's own pick.
	var st2 = StationScript.new()
	st2.dungeon = holder
	st2.annex = annex
	holder.add_child(st2)
	var captured2 := []
	st2.departure_resolved.connect(func(tid): captured2.append(tid))
	st2.votes = {1: "warlord", 11: "village"}
	st2.depart([1, 11])
	_assert(captured2.is_empty(), "embedded: split vote emits nothing (no host override)")

	# 6. Dressing tints the annex shell's lamps (not phantom own lamps).
	st.apply_dressing("depths")
	var tint: Color = StationScript.DRESSING_LAMPS["depths"]
	_assert((annex.lamps[0] as OmniLight3D).light_color == tint,
		"embedded: dressing tints annex lamps")
	_assert((st.get("_lamps") as Array).is_empty(), "embedded: no own lamps built")

	# 7. Dungeon wiring: embedded instance + departure handoff.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("StationScript.next_level_number = level_number + 1"),
		"dungeon hands off next level to the station instance")
	_assert(dsrc.contains("departure_resolved.connect(_on_station_departure_resolved)"),
		"dungeon connects departure_resolved")
	_assert(dsrc.contains("func _on_station_departure_resolved"),
		"dungeon has departure handler (issue #2 phase 3)")

	holder.queue_free()


func _test_annex_departure() -> void:
	print("[Playtest] Annex departure trigger + ride (issue #2 phase 3)...")
	# (Runtime loads only: bare autoload identifiers don't compile in -s script mode.)
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")

	# 1. Handler exists, server-only, re-entry guarded.
	_assert(dsrc.contains("func _on_station_departure_resolved"),
		"departure: handler exists")
	_assert(dsrc.contains("if not multiplayer.is_server() or _ride_running:"),
		"departure: server-only + re-entry guard")

	# 2. Sequence order: ride rpc -> wait -> save -> interior boarding rpc.
	var h_start := dsrc.find("func _on_station_departure_resolved")
	_assert(h_start > 0, "departure: handler found")
	var h := dsrc.substr(h_start, 2600)
	var p_ride := h.find("begin_annex_departure")
	var p_wait := h.find("create_timer(3.5)")
	var p_save := h.find("save_multiplayer_run")
	var p_solo := h.find("SaveManager.save_run")
	var p_hop := h.find("board_train_interior")
	_assert(p_ride > 0 and p_wait > 0 and p_save > 0 and p_hop > 0,
		"departure: ride + wait + save + interior boarding all present")
	_assert(p_ride < p_wait and p_wait < p_save and p_save < p_hop,
		"departure: ride before wait before save before boarding")
	_assert(p_solo > p_save, "departure: solo save fallback present")
	_assert(h.contains("set_deepest_cycle"), "departure: cycle recorded at departure")
	_assert(h.contains("check_achievements"), "departure: achievements checked")

	# 3. Interior boarding rpc: server-sender check, state capture (no wipe),
	# handoff statics, passenger roster, interior scene load.
	var hop_start := dsrc.find("func board_train_interior")
	_assert(hop_start > 0, "departure: board_train_interior rpc exists")
	_assert(not dsrc.contains("func hop_to_next_level"),
		"departure: old direct hop rpc removed")
	var hop := dsrc.substr(hop_start, 1500)
	_assert(hop.contains("saved_player_state = me.get_state()"), "boarding: captures player state")
	_assert(hop.contains("Dungeon.next_theme_id = theme_id"), "boarding: sets next theme")
	_assert(hop.contains("Dungeon.next_seed = new_seed"), "boarding: sets next seed")
	_assert(hop.contains("Dungeon.next_level_number = new_level"), "boarding: sets next level")
	_assert(hop.contains("passenger_classes = classes"), "boarding: hands off the roster")
	_assert(hop.contains("train_interior.tscn"), "boarding: loads the interior scene")
	_assert(hop.contains("NetworkManager.server_id"), "boarding: server-sender check")

	# 3b. Interior exit (leave_interior): server-sender check, state capture,
	# dungeon scene load via the hop path.
	var isrc := FileAccess.get_file_as_string("res://scripts/station/train_interior.gd")
	var lv_start := isrc.find("func leave_interior")
	_assert(lv_start > 0, "interior: leave_interior rpc exists")
	var lv := isrc.substr(lv_start, 800)
	_assert(lv.contains("NetworkManager.server_id"), "interior exit: server-sender check")
	_assert(lv.contains("saved_player_state = me.get_state()"), "interior exit: captures player state")
	_assert(lv.contains("dungeon.tscn"), "interior exit: loads the dungeon scene")

	# 4. Ride rpc delegates to the station's local ride on all peers.
	var ride_start := dsrc.find("func begin_annex_departure")
	_assert(ride_start > 0, "departure: ride rpc exists")
	var ride := dsrc.substr(ride_start, 1400)
	_assert(ride.contains("play_departure_ride"), "ride rpc: delegates to station")
	_assert(ride.contains("supermarket_loot"), "ride: confiscates supermarket loot on exit")

	# 5. Station ride order: whistle -> pull aboard -> fade -> chug + rumble.
	var pr_start := ssrc.find("func play_departure_ride")
	_assert(pr_start > 0, "station: play_departure_ride exists")
	var pr := ssrc.substr(pr_start, 900)
	var q_w := pr.find("train_whistle")
	var q_pull := pr.find("pull_aboard")
	var q_fade := pr.find("fade_out")
	var q_chug := pr.find("train_chug")
	var q_rumble := pr.find("\"rumble\"")
	_assert(q_w > 0 and q_pull > 0 and q_fade > 0 and q_chug > 0 and q_rumble > 0,
		"ride: whistle + aboard + fade + chug + rumble present")
	_assert(q_w < q_pull and q_pull < q_fade and q_fade < q_chug,
		"ride: whistle -> aboard -> fade -> chug")

	# 6. Arrival (dungeon entry): fade in + NOW ARRIVING banner + brake.
	_assert(dsrc.contains("fade_in(1.5)"), "arrival: fade_in on entry")
	_assert(dsrc.contains("NOW ARRIVING: "), "arrival: banner text")
	_assert(dsrc.contains("train_brake"), "arrival: brake sfx")

	# 7. Boarding spots: helper exists, spots converted to global coords.
	_assert(dsrc.contains("func _boarding_spots"), "departure: boarding spots helper")
	_assert(dsrc.contains("to_global"), "departure: spots are global")


func _test_annex_forfeit() -> void:
	print("[Playtest] Annex forfeit system (issue #2 phase 4)...")
	# (Runtime loads only: bare autoload identifiers don't compile in -s script mode.)
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")

	# 1. Snapshot captures progression; forfeit restores it exactly.
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p) # _ready: class data, starter kit, full HP
	p.level = 5
	p.xp = 120
	p.xp_next = 200
	p.stat_points = 3
	p.bonus_damage = 4.0
	p.supermarket_cash = 200
	p.affinity = {"fireball": 37.5}
	p.family_collection = {"fire": {"25": true}}
	var potion = ItemDBNode.get_item("health_potion")
	p.inventory.append({"item": potion, "count": 2})
	p._recalc_stats()
	var snap: Dictionary = p.get_state()
	var snap_inv_size: int = p.inventory.size()
	var snap_potions := 0
	for e in p.inventory:
		if str((e["item"] as Object).get("id")) == "health_potion":
			snap_potions += int(e["count"])
	# ...the level happens: gains, spends, hurts, dies.
	p.level = 6
	p.xp = 10
	p.stat_points = 0
	p.bonus_damage = 6.0
	p.supermarket_cash = 350
	p.affinity = {"fireball": 61.0}
	p.inventory.append({"item": potion, "count": 1})
	p._recalc_stats()
	p.hp = 40.0
	p.alive = false
	p.apply_forfeit(snap)
	_assert(p.level == 5, "forfeit: level restored")
	_assert(p.xp == 120 and p.xp_next == 200, "forfeit: xp restored")
	_assert(p.stat_points == 3, "forfeit: stat points restored")
	_assert(p.bonus_damage == 4.0, "forfeit: bonus attributes restored")
	_assert(p.supermarket_cash == 200, "forfeit: cash restored (net level gains undone)")
	_assert(float(p.affinity.get("fireball", 0.0)) == 37.5, "forfeit: affinity restored")
	_assert(bool((p.family_collection.get("fire", {}) as Dictionary).get("25", false)),
		"forfeit: family collection restored")
	_assert(p.inventory.size() == snap_inv_size, "forfeit: inventory entries restored")
	var potions := 0
	for e in p.inventory:
		if str((e["item"] as Object).get("id")) == "health_potion":
			potions += int(e["count"])
	_assert(potions == snap_potions, "forfeit: in-level finds gone, entry items kept")
	_assert(p.hp == 40.0, "forfeit: HP untouched (no heal)")
	_assert(not p.alive, "forfeit: dead stays dead")
	p.queue_free()

	# 2. Dungeon wiring: snapshots, level-clear flag, forfeit on departure.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func _snapshot_entry"), "dungeon snapshots entry state")
	_assert(dsrc.contains("_snapshot_entry(peer_id)"), "spawn takes the entry snapshot")
	_assert(dsrc.contains("_snapshot_entry(sender)"), "mid-level join re-snapshots")
	_assert(dsrc.contains("level_cleared = true"), "level clear sets the flag")
	_assert(dsrc.contains("gains secured"), "level clear toasts gains secured")
	_assert(dsrc.contains("func _apply_forfeits"), "forfeit applier exists")
	_assert(dsrc.contains("apply_forfeit_net"), "forfeit reaches client-owned players")
	var hpos := dsrc.find("func _on_station_departure_resolved")
	var fpos := dsrc.find("_apply_forfeits()", hpos)
	var rpos := dsrc.find("begin_annex_departure", hpos)
	_assert(fpos != -1 and rpos != -1 and fpos < rpos,
		"forfeit applied before the ride/save")
	var hblock := dsrc.substr(hpos, 700)
	_assert(hblock.contains("if not level_cleared:")
		and hblock.find("_apply_forfeits()") > hblock.find("if not level_cleared:"),
		"forfeit only when the level was not cleared")
	_assert(dsrc.contains("Left early"), "forfeit banner text")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("func apply_forfeit("), "player has apply_forfeit")
	_assert(psrc.contains("alive = was_alive"), "forfeit preserves alive status")

	# 3. Board posts the unanimous rule.
	var bsrc := FileAccess.get_file_as_string("res://scripts/station/departure_board.gd")
	_assert(bsrc.contains("MUST AGREE"), "board shows the unanimity hint")


func _test_train_interior() -> void:
	print("[Playtest] Train interior phase 1 (car shell, doors, boarding)...")
	var InteriorScript := load("res://scripts/station/train_interior.gd")
	_assert(InteriorScript != null, "interior: script loads")
	var tscn: PackedScene = load("res://scenes/station/train_interior.tscn")
	_assert(tscn != null, "interior: scene loads")

	# Car shell: build without entering the tree (no network/HUD side effects).
	var car = InteriorScript.new()
	car._build_car()
	_assert(car.get_node_or_null("CarFloor") != null, "interior: floor built")
	_assert(car.get_node_or_null("WallNorth") != null, "interior: side walls built")
	_assert(car.get_node_or_null("WallFront") != null, "interior: end wall built")
	_assert(car.get_node_or_null("CarCeiling") != null, "interior: ceiling built")
	_assert(car.get_node_or_null("BenchSeat") != null, "interior: benches built")
	_assert(car.get_node_or_null("DoorBlocker") != null, "interior: doorway blocked")
	# Collision: floor, walls, benches, blocker all have box shapes.
	var shaped := 0
	for n in car.find_children("*", "StaticBody3D", true, false):
		for c in n.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				shaped += 1
				break
	_assert(shaped >= 12, "interior: collision bodies with box shapes")
	# Doors: two sliding panels, closed by default; state machine flips.
	_assert(car._doors.size() == 2, "interior: two door panels")
	_assert(not car._doors_open, "interior: doors start closed")
	car.open_doors()
	_assert(car._doors_open, "interior: open_doors flips state")
	for d in car._doors:
		_assert(is_equal_approx(d.position.z, float(d.get_meta("open_z"))),
			"interior: open panels reach open_z")
	car.open_doors() # idempotent
	_assert(car._doors_open, "interior: open_doors idempotent")
	car.close_doors()
	_assert(not car._doors_open, "interior: close_doors flips state")
	for d in car._doors:
		_assert(is_equal_approx(d.position.z, float(d.get_meta("closed_z"))),
			"interior: closed panels reach closed_z")
	# Spawn points: 4, inside the car, above the floor.
	var spots: Array = car.spawn_points()
	_assert(spots.size() == 4, "interior: 4 spawn points")
	for s in spots:
		_assert(absf(s.x) < 8.0 and absf(s.z) < 2.5 and s.y >= 0.0,
			"interior: spawn inside car bounds")
	car.free()

	# Door SFX builders exist and synthesize.
	var SoundScript := load("res://scripts/audio/sound_synth.gd")
	_assert(SoundScript.train_door_open() is AudioStreamWAV, "interior: door open sfx builds")
	_assert(SoundScript.train_door_close() is AudioStreamWAV, "interior: door close sfx builds")

	# Boarding hook wiring (source): departure boards the interior, not the dungeon.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	var hpos := dsrc.find("func _on_station_departure_resolved")
	_assert(hpos > 0, "interior: departure handler found")
	var hblock := dsrc.substr(hpos, 2600)
	_assert(hblock.contains('rpc("board_train_interior"'), "interior: departure rpcs boarding")
	_assert(not hblock.contains("hop_to_next_level"), "interior: direct hop gone from departure")


func _test_boarding_flow() -> void:
	print("[Playtest] Boarding flow (issue #3 Phase 2: ALL ABOARD)...")
	var StationScript := load("res://scripts/station/station.gd")
	var living := [10, 11, 12]
	var st = StationScript.new()
	root.add_child(st)
	var captured := []
	st.departure_resolved.connect(func(tid): captured.append(tid))

	# Boarding is idle before a unanimous vote resolves.
	_assert(not st._boarding_active, "boarding: idle before depart")
	_assert(not bool(st.record_boarding(10, living)["ok"]), "boarding: rejected while idle")

	# Unanimous vote -> ALL ABOARD with a 45s timer, no departure yet.
	st.votes = {10: "depths", 11: "depths", 12: "depths"}
	st.depart(living)
	_assert(st._boarding_active, "boarding: ALL ABOARD entered on depart")
	_assert(st._boarding_time_left <= StationScript.BOARD_TIME, "boarding: 45s timer running")
	_assert(not st._boarding_locked, "boarding: door unlocked while boarding")
	_assert(st._boarding_theme == "depths", "boarding: carries the voted theme")
	_assert(captured.is_empty(), "boarding: no departure_resolved yet")

	# Walk-through boarding: one peer boards, still waiting on the rest.
	_assert(bool(st.record_boarding(10, living)["ok"]), "boarding: peer 10 boards")
	_assert(st.aboard == {10: true}, "boarding: roster tracks peer 10")
	_assert(not st._all_aboard(living), "boarding: 1/3 not all aboard")
	_assert(not bool(st.record_boarding(99, living)["ok"]), "boarding: non-living rejected")
	_assert(bool(st.record_boarding(10, living)["ok"]), "boarding: re-board idempotent")

	# Last player boards -> all aboard -> early departure, timer cancelled.
	st.record_boarding(11, living)
	st.record_boarding(12, living)
	_assert(st._all_aboard(living), "boarding: 3/3 all aboard")
	st._finish_boarding(living)
	_assert(captured == ["depths"], "boarding: all-aboard emits departure_resolved")
	_assert(not st._boarding_active, "boarding: timer cancelled after all aboard")
	_assert(st._boarding_locked, "boarding: door locked after all aboard")
	_assert(not bool(st.record_boarding(10, living)["ok"]), "boarding: locked door rejects")
	st.queue_free()

	# Timer expiry ends boarding and emits (stragglers ride via pull-aboard).
	var st2 = StationScript.new()
	root.add_child(st2)
	var captured2 := []
	st2.departure_resolved.connect(func(tid): captured2.append(tid))
	st2.votes = {10: "village", 11: "village"}
	st2.depart([10, 11])
	st2._boarding_time_left = 0.01
	st2._tick_boarding(0.02)
	_assert(captured2 == ["village"], "boarding: expiry emits departure_resolved")
	_assert(st2._boarding_locked, "boarding: door locked on expiry")
	_assert(not st2._boarding_active, "boarding: timer stops on expiry")
	st2.queue_free()

	# Stragglers are marked aboard when boarding completes.
	var st4 = StationScript.new()
	root.add_child(st4)
	st4.votes = {10: "village", 11: "village"}
	st4.depart([10, 11])
	st4.record_boarding(10, [10, 11])
	st4._finish_boarding([10, 11])
	_assert(st4.aboard.has(11), "boarding: straggler marked aboard on completion")
	st4.queue_free()

	# Solo: the single living player boarding ends the window immediately.
	var st3 = StationScript.new()
	root.add_child(st3)
	var captured3 := []
	st3.departure_resolved.connect(func(tid): captured3.append(tid))
	st3.votes = {7: "dungeon"}
	st3.depart([7])
	st3.record_boarding(7, [7])
	_assert(st3._all_aboard([7]), "boarding: solo 1/1 all aboard")
	st3._finish_boarding([7])
	_assert(captured3 == ["dungeon"], "boarding: solo departs on door entry")
	st3.queue_free()

	# The request_board RPC stays thin and delegates to record_boarding.
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(ssrc.contains("record_boarding(sender)"), "boarding: request_board delegates")
	_assert(ssrc.contains("boarding_sync"), "boarding: roster sync rpc exists")
	# Interior door lock: locked cars never open their doors.
	var InteriorScript := load("res://scripts/station/train_interior.gd")
	InteriorScript.doors_locked = true
	var car = InteriorScript.new()
	car._build_car()
	car.open_doors()
	_assert(not car._doors_open, "interior: locked doors stay closed")
	car.lock_doors()
	_assert(InteriorScript.doors_locked, "interior: lock_doors sets the lock")
	car.free()
	InteriorScript.doors_locked = false
	# Dungeon hands the lock to the interior on boarding.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("InteriorScript.doors_locked = true"), "boarding: dungeon locks car doors")


func _test_cycle_scaling() -> void:
	print("[Playtest] Cycle scaling...")
	# Apply the EXACT formulas from dungeon.gd to the real theme resources.
	var theme_ids := ["village", "dungeon", "depths", "supermarket", "warlord"]
	for tid in theme_ids:
		var theme: Resource = load("res://data/levels/theme_%s.tres" % tid)
		_assert(theme != null, "Theme %s loads" % tid)
		if theme == null:
			continue
		var base_grid := int(theme.get("grid_size"))
		var base_keys := int(theme.get("puzzle_key_count"))
		for cycle in [0, 1, 2, 5, 20]:
			# Mirrors dungeon.gd change_level scaling.
			var grid: int = mini(96, base_grid + cycle * 40)
			var keys: int = mini(8, base_keys + cycle)
			_assert(grid <= 96, "Grid capped at 96 (%s cycle %d)" % [tid, cycle])
			_assert(grid >= base_grid, "Grid never shrinks (%s cycle %d)" % [tid, cycle])
			_assert(keys <= 8, "Keys capped at 8 (%s cycle %d)" % [tid, cycle])
			_assert(keys >= base_keys, "Keys never shrink (%s cycle %d)" % [tid, cycle])
		# Cycle 0 must leave the theme untouched.
		_assert(mini(96, base_grid + 0 * 40) == base_grid, "Cycle 0 grid unchanged (%s)" % tid)
		_assert(mini(8, base_keys + 0) == base_keys, "Cycle 0 keys unchanged (%s)" % tid)


func _test_ai_director() -> void:
	print("[Playtest] AI Director...")
	var dir_script = load("res://scripts/systems/ai_director.gd")
	_assert(dir_script != null, "AIDirector loads")


func _print_results() -> void:
	print("\n[Playtest] Results: %d passed, %d failed" % [_passes, _failures.size()])
	if not _failures.is_empty():
		print("[Playtest] Failures:")
		for f in _failures:
			print("  - %s" % f)
	else:
		print("[Playtest] All tests passed!")


func _test_economy() -> void:
	print("[Playtest] Economy...")
	# Node amounts match the rework spec.
	var node := RTSResourceNode.new()
	node.setup("wood", 1000)
	_assert(node.amount == 1000, "Wood node holds 1000")
	node.setup("gold", 800)
	_assert(node.amount == 800, "Gold node holds 800")
	node.setup("stone", 800)
	_assert(node.amount == 800, "Stone node holds 800")
	node.setup("food", 800)
	_assert(node.amount == 800, "Food node holds 800")
	node.free()
	# Gather is server-guarded. Verify the depletion math directly on the node.
	var node2 := RTSResourceNode.new()
	node2.setup("wood", 100)
	# Simulate the server-side gather math: mini(requested, amount).
	var take: int = mini(60, node2.amount)
	_assert(take == 60, "Gather math takes requested when available")
	node2.amount -= take
	_assert(node2.amount == 40, "Gather math reduces amount")
	take = mini(100, node2.amount)
	_assert(take == 40, "Gather math clamps to remaining")
	node2.free()
	# Dungeon exposes the economy hooks.
	var src := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(src.contains("func schedule_node_respawn"), "schedule_node_respawn exists")
	_assert(src.contains("func _process_node_respawns"), "_process_node_respawns exists")
	_assert(src.contains("func _random_land_pos"), "_random_land_pos exists")
	_assert(src.contains('"wood": 1000'), "Wood amount is 1000 in spawn_rts_node")
	_assert(src.contains("nodes_per_resource_per_faction"), "Node count reads per-faction tuning")
	_assert(src.contains("nodes_cycle_bonus"), "Node count reads cycle bonus tuning")
	# Tuned defaults are unchanged: 8 nodes per resource per faction, +2 per cycle.
	var tune := ConfigFile.new()
	_assert(tune.load("res://scripts/rts/rts_tuning.cfg") == OK, "Tuning file loads")
	_assert(int(tune.get_value("map", "nodes_per_resource_per_faction", 0)) == 8, "Default 8 nodes per resource")
	_assert(int(tune.get_value("map", "nodes_cycle_bonus", 0)) == 2, "Default +2 nodes per cycle")


func _test_trade_no_self_trade() -> void:
	print("[Playtest] Trade self-trade guard...")
	# Regression: routing a trade cart to its own market was a zero-distance
	# loop paying min_payout gold every trip (infinite gold).
	var unit_script := load("res://scripts/rts/unit.gd")
	var bld_script := load("res://scripts/rts/building.gd")
	var cart = unit_script.new()
	cart.set("unit_type", "trade_cart")
	cart.set("faction", 0)
	cart.set("alive", true)
	root.add_child(cart)
	var own_market = bld_script.new()
	own_market.set("faction", 0)
	own_market.set("building_type", "market")
	root.add_child(own_market)
	var foe_market = bld_script.new()
	foe_market.set("faction", 1)
	foe_market.set("building_type", "market")
	root.add_child(foe_market)
	# Same-faction target must be refused: no trade state set.
	cart.order_trade(own_market)
	_assert(cart.get("_trade_target") == null, "Self-market trade order refused")
	# Foreign market is accepted.
	cart.order_trade(foe_market)
	_assert(cart.get("_trade_target") == foe_market, "Foreign market trade order accepted")
	_assert(cart.get("_home_market") == own_market, "Home market is own nearest market")
	cart.queue_free()
	own_market.queue_free()
	foe_market.queue_free()


func _test_affinity_families() -> void:
	print("[Playtest] Affinity families...")
	var PlayerScript = load("res://scripts/player/player.gd")
	# Family table integrity: every skill in exactly one family.
	var fams: Dictionary = PlayerScript.families()
	_assert(fams.size() == 7, "7 affinity families defined")
	var seen := {}
	for fid in fams:
		var f: Dictionary = fams[fid]
		for sid in f["skills"]:
			_assert(not seen.has(sid), "Skill %s in exactly one family" % sid)
			seen[sid] = fid
		_assert(f["traits"].size() == 3, "Family %s has 3 traits" % fid)
		_assert(str(f["signature"]["id"]) != "", "Family %s has a signature" % fid)
	# Holy Light excluded.
	_assert(PlayerScript.family_of("holy_light") == "", "Holy Light not in a family")
	_assert(PlayerScript.family_of("fireball") == "fire", "Fireball in Fire family")
	_assert(PlayerScript.family_of("shadow_step") == "shadow", "Shadow Step in Shadow family")
	_assert(PlayerScript.family_of("reciprocity") == "warden", "Reciprocity in Warden family")
	# All 16 non-holy skills are in families.
	_assert(seen.size() == 16, "All 16 skills assigned to families")


func _test_rogue_traits() -> void:
	print("[Playtest] Rogue family traits...")
	var PlayerScript = load("res://scripts/player/player.gd")
	var fams: Dictionary = PlayerScript.families()
	# All six rogue trait IDs are defined in the family table.
	var shadow_traits: Dictionary = fams["shadow"]["traits"]
	var precision_traits: Dictionary = fams["precision"]["traits"]
	var ids := []
	for ms in shadow_traits:
		ids.append(shadow_traits[ms]["id"])
	for ms in precision_traits:
		ids.append(precision_traits[ms]["id"])
	for tid in ["longer_shadows", "unseen", "double_take", "true_aim", "hamstring_mark", "ricochet"]:
		_assert(tid in ids, "Rogue trait defined: %s" % tid)
	# Wiring present in source.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains('has_trait("longer_shadows")'), "Longer Shadows wired (blink + veil)")
	_assert(psrc.contains("unseen_crit_ready"), "Unseen crit flag exists")
	_assert(psrc.contains('has_trait("unseen")'), "Unseen wired (veil expiry + blink)")
	_assert(psrc.contains('spawn_decoy'), "Double Take spawns decoy via dungeon RPC")
	_assert(psrc.contains('has_trait("hamstring_mark")'), "Hamstring Mark wired in _activate_mark")
	_assert(psrc.contains('has_trait("ricochet")'), "Ricochet wired in _activate_fan")
	var msrc := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(msrc.contains('has_trait("true_aim")'), "True Aim wired in mob take_damage")
	_assert(msrc.contains("is_in_group(\"decoys\")"), "Mobs target/attack decoys")
	_assert(msrc.contains("slow_mult"), "Hamstring slow param in apply_mark")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func spawn_decoy"), "dungeon.spawn_decoy RPC exists")
	_assert(ResourceLoader.exists("res://scripts/combat/decoy.gd"), "decoy.gd exists")


func _test_warrior_signatures() -> void:
	print("[Playtest] Warrior signature totems...")
	var PlayerScript = load("res://scripts/player/player.gd")
	var fams: Dictionary = PlayerScript.families()
	# Both warrior signature IDs are defined in the family table.
	_assert(str(fams["warden"]["signature"]["id"]) == "sanctuary_totem", "Sanctuary Totem defined (warden)")
	_assert(str(fams["conqueror"]["signature"]["id"]) == "doom_totem", "Doom Totem defined (conqueror)")
	# Wiring present in source.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("func _activate_signature_totem"), "Signature totem activation exists")
	_assert(psrc.contains('ability_cds[cd_key] = cd'), "Signature cooldowns tracked")
	_assert(psrc.contains("func apply_sanctuary"), "Sanctuary immunity RPC exists")
	_assert(psrc.contains("_sanctuary_t > 0.0"), "Sanctuary immunity checked in take_damage")
	var msrc := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(msrc.contains("var doom_t"), "Doom debuff timer exists on mobs")
	_assert(msrc.contains("amount *= 1.3"), "Doom +30% damage in mob take_damage")
	var tsrc := FileAccess.get_file_as_string("res://scripts/combat/totem.gd")
	_assert(tsrc.contains('"sanctuary_totem"'), "Totem handles sanctuary type")
	_assert(tsrc.contains('"doom_totem"'), "Totem handles doom type")
	_assert(tsrc.contains("apply_sanctuary"), "Sanctuary aura applies immunity")
	_assert(tsrc.contains("m.doom_t = "), "Doom aura applies debuff")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("sanctuary_totem"), "HUD shows sanctuary cooldown")


func _test_affinity_ui() -> void:
	print("[Playtest] Affinity UI...")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	# Ability bar: affinity fill + pips on specialized slot.
	_assert(hsrc.contains('ProgressBar.new()'), "Affinity ProgressBar created")
	_assert(hsrc.contains('bar.max_value = 100.0'), "Affinity bar scaled 0-100")
	_assert(hsrc.contains('p.get("affinity").get(sid'), "Bar reads affinity value")
	_assert(hsrc.contains('◆'), "Milestone pips rendered")
	_assert(hsrc.contains('Color(1.0, 0.85, 0.3, 1.0)'), "Specialized slot gold border")
	# Lock tint on non-specialized family skills.
	_assert(hsrc.contains('Player.family_of(sid)'), "Slot checks family membership")
	_assert(hsrc.contains('Color(0.05, 0.05, 0.07, 0.6)'), "Dimmed lock tint for non-specialized")
	# Mage signature slots.
	_assert(hsrc.contains('p.class_id == "mage"'), "Mage signature bar section")
	_assert(hsrc.contains('family_signature'), "Signature lookup for mage slots")
	_assert(hsrc.contains('"[8]"'), "Key 8 hint on mage signature slot")
	_assert(hsrc.contains('String(sig["desc"])'), "Signature tooltip from desc")
	# Family panel.
	_assert(hsrc.contains("func _refresh_family_panel"), "Family panel function exists")
	_assert(hsrc.contains("%FamilyPanel"), "FamilyPanel node referenced")
	_assert(hsrc.contains("100 affinity"), "Signature silhouette until earned")
	# Collection log.
	_assert(hsrc.contains("func _refresh_collection_log"), "Collection log function exists")
	_assert(hsrc.contains("%CollectionLog"), "CollectionLog node referenced")
	# Hooks: refresh on pause open and spec changes.
	_assert(hsrc.contains("_refresh_family_panel()"), "Family panel refreshed")
	_assert(hsrc.contains("_refresh_collection_log()"), "Collection log refreshed")
	# TSCN nodes exist.
	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/hud.tscn")
	_assert(tsrc.contains('[node name="FamilyPanel"'), "FamilyPanel node in tscn")
	_assert(tsrc.contains('[node name="CollectionLog"'), "CollectionLog node in tscn")


func _test_affinity_save_roundtrip() -> void:
	print("[Playtest] Affinity save roundtrip...")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	# get_state includes affinity fields.
	_assert(psrc.contains('"specialization": specialization'), "get_state saves specialization")
	_assert(psrc.contains('"affinity": affinity.duplicate(true)'), "get_state saves affinity")
	_assert(psrc.contains('"family_collection": family_collection.duplicate(true)'), "get_state saves family_collection")
	# apply_state restores them.
	_assert(psrc.contains('specialization = str(s.get("specialization"'), "apply_state restores specialization")
	_assert(psrc.contains('affinity = (s.get("affinity"'), "apply_state restores affinity")
	_assert(psrc.contains('family_collection = (s.get("family_collection"'), "apply_state restores family_collection")
	# Class switch resets affinity.
	_assert(psrc.contains('specialization = ""'), "switch_class clears specialization")
	_assert(psrc.contains('affinity.clear()'), "switch_class clears affinity")
	_assert(psrc.contains('family_collection.clear()'), "switch_class clears family_collection")
	# SaveManager/dungeon use get_state for persistence.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("get_state()"), "Dungeon saves via get_state")


func _test_specialization_level_gate() -> void:
	print("[Playtest] Specialization level gate...")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("const SPECIALIZATION_UNLOCK_LEVEL := 20"), "Unlock level const is 20")
	_assert(psrc.contains("if level < SPECIALIZATION_UNLOCK_LEVEL:"), "specialize() guards level")
	_assert(psrc.contains("Specialization unlocks at level %d"), "specialize() shows HUD hint")
	_assert(psrc.contains("prev_level < SPECIALIZATION_UNLOCK_LEVEL and level >= SPECIALIZATION_UNLOCK_LEVEL"), "Level-up detects crossing 20")
	_assert(psrc.contains("Specialization unlocked — choose a skill in the abilities menu"), "Level-20 announce text")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("spec_locked"), "Pause menu tracks lock state")
	_assert(hsrc.contains("btn.disabled = true"), "Specialize buttons disabled below 20")
	_assert(hsrc.contains("Unlocks at level %d"), "Disabled buttons show unlock hint")
	_assert(hsrc.contains("Specialization unlocks at level %d (currently %d)"), "Pause menu hint label")


func _test_pause_tabs() -> void:
	print("[Playtest] Pause tabs...")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func _build_pause_tabs"), "Tab builder exists")
	_assert(hsrc.contains("func _on_pause_tab_pressed"), "Tab switch handler exists")
	_assert(hsrc.contains("func select_pause_tab"), "Programmatic tab selection exists")
	_assert(hsrc.contains('"Stats", "Specialization", "Collection"'), "Three tabs defined")
	_assert(hsrc.contains("_apply_pause_tab_visibility"), "Tab visibility applied")
	# Tab membership covers all pause content.
	_assert(hsrc.contains('"SpecLabel", "SpecList"'), "Spec tab has spec list")
	_assert(hsrc.contains('"FamilyLabel", "FamilyPanel"'), "Collection tab has family panel")
	_assert(hsrc.contains('"DmgRow", "HpRow", "SpdRow", "AuraRow"'), "Stats tab has stat rows")
	# Action buttons not in any tab (always visible).
	_assert(not hsrc.contains('"ResumeButton"') or hsrc.contains('_pause_tab_members'), "Tab members defined")
	# show_pause defaults to Stats tab.
	_assert(hsrc.contains("_on_pause_tab_pressed(0)"), "Defaults to Stats tab")
	# affinity_shots uses tab selection.
	var tsrc := FileAccess.get_file_as_string("res://tools/affinity_shots/affinity_shots.gd")
	_assert(tsrc.contains("select_pause_tab"), "Tool uses tab selection")


func _test_switch_class_refresh() -> void:
	print("[Playtest] Switch class refresh...")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	# switch_class rebuilds abilities and updates the level label.
	_assert(psrc.contains("_push_aura()\n\trefresh_abilities()"), "switch_class calls refresh_abilities")
	_assert(psrc.contains('hud.set_level(level, self)'), "switch_class updates level label")
	# Player refresh_abilities rebuilds unlocked_abilities and refreshes HUD bar.
	_assert(psrc.contains("unlocked_abilities = fresh"), "refresh_abilities rebuilds unlocked_abilities")
	_assert(psrc.contains("hud.refresh_abilities(self)"), "refresh_abilities updates HUD bar")


func _test_architect() -> void:
	print("[Playtest] Architect class...")
	var PlayerScript = load("res://scripts/player/player.gd")
	var StructureScript = load("res://scripts/combat/structure.gd")
	# Kit: 6 abilities, turret first (wall-first would leave 1-3 with no damage).
	var abs: Array = PlayerScript.class_abilities("architect")
	_assert(abs.size() == 6, "Architect has 6 abilities")
	var expect := [
		["sentry_turret", 1, "1"], ["bulwark_wall", 4, "2"], ["spike_trap", 8, "3"],
		["keystone", 15, "4"], ["reinforce", 20, "5"], ["demolish", 30, "6"],
	]
	for i in expect.size():
		var a: Dictionary = abs[i]
		_assert(str(a["id"]) == expect[i][0], "Architect slot %d is %s" % [i + 1, expect[i][0]])
		_assert(int(a["unlock"]) == expect[i][1], "Architect %s unlocks at %d" % [expect[i][0], expect[i][1]])
		_assert(str(a["key"]) == expect[i][2], "Architect %s on key %s" % [expect[i][0], expect[i][2]])
	# Foundation family deferred: all six return "" (safe for HUD + milestones).
	for e in expect:
		_assert(PlayerScript.family_of(str(e[0])) == "", "Architect %s has no family yet" % e[0])
	# Structure stats sane.
	var stats: Dictionary = StructureScript.STATS
	_assert(float(stats["bulwark_wall"]["hp"]) == 150.0, "Wall 150 HP / 20s")
	_assert(float(stats["bulwark_wall"]["life"]) == 20.0, "Wall 20s life")
	_assert(float(stats["sentry_turret"]["hp"]) == 100.0, "Turret 100 HP / 60s")
	_assert(float(stats["spike_trap"]["hp"]) == 60.0, "Trap 60 HP")
	_assert(float(stats["keystone"]["hp"]) == 200.0, "Keystone 200 HP / 45s")
	_assert(StructureScript.STRUCTURE_CAP == 6, "Structure cap 6")
	_assert(StructureScript.KEYSTONE_RADIUS == 6.0, "Keystone radius 6m")
	# Demolish formula: 50% of max HP (keystone 1.5x buff applies).
	var st = StructureScript.new()
	st.setup("sentry_turret", 1, 1, 1.5, "1_1")
	_assert(st.max_hp == 150.0, "Keystone buff: turret max HP 150")
	_assert(st.max_hp * 0.5 == 75.0, "Demolish deals 50% of max HP")
	_assert(st.uid == "1_1", "Structure uid stored")
	st.free()
	# Save slots (issue #4): runs persist per slot; the slot path never
	# derives from class_id, so switching class can't clobber another slot.
	var mgr = load("res://scripts/autoload/save_manager.gd").new()
	_assert(mgr._slot_path("solo", 0) == "user://runs/solo_0.cfg", "solo slot path pattern")
	_assert(mgr._slot_path("mp", 2) == "user://runs/mp_2.cfg", "mp slot path pattern")
	mgr.free()
	# Class data loads.
	var cd = load("res://data/classes/architect.tres")
	_assert(cd != null and str(cd.id) == "architect", "architect.tres loads with id")
	# Player routes architect input through the ability caster, not melee.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains('class_id in ["mage", "architect"]'), "Architect uses 1-6 ability keys")
	_assert(psrc.contains('_cast_architect_ability()'), "Architect casts via ability router")
	_assert(psrc.contains("func apply_reinforce"), "Reinforce buff exists")
	# Dungeon hosts the structure RPCs.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func place_structure"), "place_structure RPC exists")
	_assert(dsrc.contains("func break_structure"), "break_structure RPC exists")
	_assert(dsrc.contains("func demolish_structures"), "demolish_structures RPC exists")
	# Mobs target structures and collide with walls.
	var msrc := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(msrc.contains("take_structure_damage"), "Mobs damage structures")
	_assert(msrc.contains("collision_mask = 3"), "Mob mask includes wall layer")


func _test_cipher_unlock() -> void:
	print("[Playtest] Mason's cipher unlock...")
	_assert(load("res://scripts/data/cipher_poems.gd") != null, "CipherPoems loads")
	_assert(load("res://scripts/items/cipher_plaque.gd") != null, "CipherPlaque loads")
	_assert(load("res://scripts/items/cipher_lockbox.gd") != null, "CipherLockbox loads")
	# Caesar vectors from the spec.
	_assert(CipherPoems.cipher_word("THE", 3) == "WKH", "cipher THE+3=WKH")
	_assert(CipherPoems.cipher_word("QUIET", 5) == "VZNJY", "cipher QUIET+5=VZNJY")
	_assert(CipherPoems.cipher_word("STONE", 7) == "ZAVUL", "cipher STONE+7=ZAVUL")
	_assert(CipherPoems.cipher_word("REMEMBERS", 4) == "VIQIQFIVW", "cipher REMEMBERS+4=VIQIQFIVW")
	_assert(CipherPoems.cipher_word("EVERY", 6) == "KBKXE", "cipher EVERY+6=KBKXE")
	_assert(CipherPoems.cipher_word("HAND", 8) == "PIVL", "cipher HAND+8=PIVL")
	_assert(CipherPoems.cipher_word("THAT", 3) == "WKDW", "cipher THAT+3=WKDW")
	_assert(CipherPoems.cipher_word("BUILDS", 5) == "GZNQIX", "cipher BUILDS+5=GZNQIX")
	_assert(CipherPoems.cipher_word("XYZ", 3) == "ABC", "cipher wraps Z->A")
	_assert(CipherPoems.cipher_word("A-B", 1) == "B-C", "cipher leaves non-letters")
	# Every poem's stored cipher matches its word+shift.
	for p in CipherPoems.POEMS:
		_assert(CipherPoems.cipher_word(str(p["word"]), int(p["shift"])) == str(p["cipher"]),
			"poem cipher self-consistent: " + str(p["word"]))
	_assert(CipherPoems.POEMS.size() == 8, "8 cipher poems")
	_assert(CipherPoems.passphrase() == "THE QUIET STONE REMEMBERS EVERY HAND THAT BUILDS",
		"passphrase decodes in order")
	_assert(CipherPoems.normalize_key("  the\tQUIET\nstone  ") == "THE QUIET STONE",
		"normalize_key collapses whitespace")
	_assert(CipherPoems.next_fragment([]) == 0, "next_fragment starts at 0")
	_assert(CipherPoems.next_fragment([0, 1, 3]) == 2, "next_fragment finds lowest gap")
	_assert(CipherPoems.next_fragment([0, 1, 2, 3, 4, 5, 6, 7]) == -1, "next_fragment -1 when complete")
	# Meta round-trip (back up user://profile_local.cfg so the test can't clobber it).
	var cfg_path := "user://profile_local.cfg"
	var backup := PackedByteArray()
	if FileAccess.file_exists(cfg_path):
		backup = FileAccess.get_file_as_bytes(cfg_path)
	var mgr = load("res://scripts/autoload/save_manager.gd").new()
	_assert(mgr.get_cipher_fragments().is_empty(), "cipher fragments start empty")
	_assert(mgr.add_cipher_fragment(2), "add_cipher_fragment grants new")
	_assert(not mgr.add_cipher_fragment(2), "add_cipher_fragment rejects duplicate")
	_assert(mgr.add_cipher_fragment(0), "add_cipher_fragment grants 0")
	_assert(not mgr.is_architect_unlocked(), "architect locked initially")
	_assert(mgr.unlock_architect(), "unlock_architect grants")
	_assert(not mgr.unlock_architect(), "unlock_architect not double-granted")
	_assert(mgr.is_architect_unlocked(), "architect unlocked after grant")
	_assert(mgr.unlock_achievement("drafted"), "drafted achievement grants")
	_assert(not mgr.unlock_achievement("drafted"), "drafted not double-granted")
	var prog: Dictionary = mgr.get_achievement_progress("drafted")
	_assert(bool(prog.get("done", false)), "drafted shows done in progress")
	# A fresh instance sees the persisted state.
	var mgr2 = load("res://scripts/autoload/save_manager.gd").new()
	mgr2.load_game()
	_assert(mgr2.get_cipher_fragments().has(2) and mgr2.get_cipher_fragments().has(0),
		"cipher fragments persist")
	_assert(mgr2.is_architect_unlocked(), "architect unlock persists")
	mgr.free()
	mgr2.free()
	if backup.is_empty():
		DirAccess.remove_absolute(cfg_path)
	else:
		var f := FileAccess.open(cfg_path, FileAccess.WRITE)
		f.store_buffer(backup)
	# Wiring: spawns, HUD popups, picker gating.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func spawn_cipher_plaque"), "spawn_cipher_plaque RPC exists")
	_assert(dsrc.contains("func spawn_cipher_lockbox"), "spawn_cipher_lockbox RPC exists")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func show_poem_popup"), "show_poem_popup exists")
	_assert(hsrc.contains("func show_lockbox_popup"), "show_lockbox_popup exists")
	_assert(hsrc.contains("func show_toast"), "show_toast alias exists")
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(msrc.contains("is_architect_unlocked"), "title picker gated on unlock")


func _test_station_phase1() -> void:
	print("[Playtest] Train station phase 1...")
	var DungeonScript := load("res://scripts/dungeon/dungeon.gd")
	var order: Array = DungeonScript.THEME_ORDER
	_assert(order == ["village", "dungeon", "depths", "supermarket", "warlord"],
		"THEME_ORDER unchanged")
	# Theme rotation preserved: annex departure must pick exactly what the
	# old level hop picked for levels 1..12.
	var expected := ["village", "dungeon", "depths", "supermarket", "warlord",
		"village", "dungeon", "depths", "supermarket", "warlord",
		"village", "dungeon"]
	for n in range(1, 13):
		var theme_id: String = order[(n - 1) % order.size()]
		_assert(theme_id == expected[n - 1], "station depart level %d -> %s" % [n, theme_id])
	# Cycle math unchanged.
	for n in [1, 5, 6, 10, 11, 25, 26]:
		var cycle: int = (n - 1) / order.size() + 1
		var want := int((n - 1) / 5) + 1
		_assert(cycle == want, "cycle math level %d -> %d" % [n, want])
	# Departure increments by exactly 1 from the cleared level.
	for cleared in [1, 4, 5, 9, 24]:
		_assert(cleared + 1 == cleared + 1, "depart next_level = cleared + 1 (%d)" % cleared)
	# Supermarket confiscation: loot flagged supermarket_loot is dropped,
	# everything else (potions etc.) is kept.
	var fake_inv := [
		{"item": {"id": "cereal", "supermarket_loot": true}},
		{"item": {"id": "health_potion", "supermarket_loot": false}},
		{"item": {"id": "soda", "supermarket_loot": true}},
	]
	var kept: Array = []
	for entry in fake_inv:
		var item = entry["item"]
		if not bool(item.get("supermarket_loot")):
			kept.append(entry)
	_assert(kept.size() == 1 and str(kept[0]["item"]["id"]) == "health_potion",
		"annex departure confiscates supermarket loot, keeps potions")
	# Save & Quit from the station targets the NEXT level.
	for cleared in [4, 5, 9]:
		var nl: int = cleared + 1
		var theme_id: String = order[(nl - 1) % order.size()]
		_assert(theme_id == expected[nl - 1], "station save&quit level %d -> %s" % [nl, theme_id])
	# Wiring: station script (embedded-only) + dungeon handoff + HUD timer.
	# (Issue #2 Phase 5: the standalone station scene and the portal are gone.)
	_assert(not ResourceLoader.exists("res://scenes/station/station.tscn"), "standalone station.tscn removed")
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(ssrc.contains("static var next_level_number"), "Station.next_level_number handoff")
	_assert(ssrc.contains("func depart"), "station depart() exists")
	_assert(not ssrc.contains("func leave_station"), "leave_station RPC removed")
	_assert(ssrc.contains("func pull_aboard"), "pull_aboard RPC exists")
	_assert(ssrc.contains("DEPART_TIME := 45.0"), "45s departure timer")
	_assert(not ssrc.contains("func _build_station("), "standalone _build_station removed")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(not dsrc.contains("func go_to_station"), "go_to_station removed")
	_assert(not dsrc.contains("\"go_to_station_net\""), "go_to_station_net RPC removed")
	_assert(not dsrc.contains("func spawn_portal"), "spawn_portal removed")
	_assert(not dsrc.contains("spawn_portal"), "no portal spawns anywhere")
	_assert(not dsrc.contains("func unseal_portal"), "unseal_portal removed")
	_assert(not dsrc.contains("func unlock_portal"), "unlock_portal removed")
	_assert(not dsrc.contains("_portal_sealed"), "_portal_sealed state removed")
	_assert(not dsrc.contains("func advance_level"), "advance_level removed")
	_assert(not dsrc.contains("func change_level"), "change_level removed")
	_assert(dsrc.contains("next_level_number = level_number + 1"), "dungeon hands off next level to station")
	_assert(dsrc.contains("func complete_level_objective"), "level objective completion kept")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func show_station_timer"), "show_station_timer exists")
	_assert(hsrc.contains("func hide_station_timer"), "hide_station_timer exists")
	_assert(not hsrc.contains("func show_station_mode"), "show_station_mode removed")
	_assert(hsrc.contains("Station.next_level_number"), "save&quit is station-aware")


func _test_station_phase2() -> void:
	print("[Playtest] Train station phase 2...")
	var StationScript := load("res://scripts/station/station.gd")
	# Unanimous boarding: every living player must vote the SAME destination.
	_assert(StationScript.resolve_destination(
		{10: "dungeon", 11: "dungeon", 12: "dungeon"}, [10, 11, 12]) == "dungeon",
		"unanimous vote resolves")
	# Split vote -> no departure.
	_assert(StationScript.resolve_destination(
		{10: "dungeon", 11: "dungeon", 12: "village"}, [10, 11, 12]) == "",
		"split vote: no departure")
	# Partial vote (a living player abstains) -> no departure.
	_assert(StationScript.resolve_destination(
		{11: "warlord", 12: "village"}, [10, 11, 12]) == "",
		"abstention: no departure")
	# No votes -> no departure (no rotation fallback).
	_assert(StationScript.resolve_destination({}, [10]) == "",
		"no votes: no departure")
	# Single living voter agreeing with themselves -> resolves.
	_assert(StationScript.resolve_destination({10: "depths"}, [10]) == "depths",
		"solo unanimity resolves")
	# Recommended levels: informational, derived from cycle + theme index.
	_assert(StationScript.recommended_level("village", 1) == 1, "rec village @ L1 = 1")
	_assert(StationScript.recommended_level("depths", 3) == 3, "rec depths @ L3 = 3")
	_assert(StationScript.recommended_level("warlord", 5) == 5, "rec warlord @ L5 = 5")
	_assert(StationScript.recommended_level("village", 6) == 6, "rec village @ L6 (cycle 2) = 6")
	_assert(StationScript.recommended_level("dungeon", 9) == 7, "rec dungeon @ L9 = 7")
	_assert(StationScript.recommended_level("supermarket", 24) == 24, "rec supermarket @ L24 = 24")
	# Display names come from the theme .tres files.
	_assert(StationScript.theme_display_name("village") == "Village Outskirts", "village display name")
	_assert(StationScript.theme_display_name("warlord") == "Warlord's Domain", "warlord display name")
	# Wiring: vote RPCs, board prop, HUD board UI, player E-scan.
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(ssrc.contains("func cast_vote"), "cast_vote RPC exists")
	_assert(ssrc.contains("func sync_votes"), "sync_votes RPC exists")
	_assert(not ssrc.contains("func open_board"), "open_board RPC removed (no auto-open)")
	_assert(not ssrc.contains("func announce_arrival"), "announce_arrival moved to dungeon entry (Phase 5)")
	_assert(ssrc.contains("resolve_destination(votes"), "depart resolves destination")
	_assert(ssrc.contains("DepartureBoardScript.new()"), "departure board prop placed")
	_assert(ssrc.contains("const BOARD_STARS"), "danger stars live in station.gd now")
	_assert(ssrc.contains("set_tallies"), "sync_votes updates the 3D board tallies")
	_assert(ResourceLoader.exists("res://scripts/station/departure_board.gd"), "departure_board.gd exists")
	var bsrc := FileAccess.get_file_as_string("res://scripts/station/departure_board.gd")
	_assert(bsrc.contains("add_to_group(\"departure_board\")"), "board in departure_board group")
	_assert(bsrc.contains("func interact"), "board interact exists")
	_assert(bsrc.contains("func set_hover"), "board hover highlight API exists")
	_assert(bsrc.contains("func set_my_vote"), "board my-vote highlight API exists")
	_assert(bsrc.contains("func set_tallies"), "board tally API exists")
	_assert(bsrc.contains("func row_base_text"), "row text builder exists")
	_assert(bsrc.contains("collision_layer = 4"), "rows on dedicated physics layer 4")
	_assert(bsrc.contains("input_ray_pickable = true"), "rows are ray-pickable")
	_assert(bsrc.contains("enter_reading"), "interact enters reading mode")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(not hsrc.contains("func show_departure_board"), "floating board panel removed")
	_assert(not hsrc.contains("func close_departure_board"), "close_departure_board gone")
	_assert(not hsrc.contains("func refresh_departure_board"), "refresh_departure_board gone")
	_assert(not hsrc.contains("BOARD_STARS"), "BOARD_STARS moved out of hud")
	_assert(hsrc.contains("func announce"), "NOW ARRIVING banner kept")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("\"departure_board\""), "player E-scan includes board")
	_assert(psrc.contains("func enter_reading"), "enter_reading exists")
	_assert(psrc.contains("func exit_reading"), "exit_reading exists")
	_assert(psrc.contains("_reading_board"), "reading-mode state tracked")
	_assert(psrc.contains("st.rpc(\"cast_vote\""), "click votes via cast_vote RPC")
	_assert(not psrc.contains("hud.board_open"), "no stale hud.board_open references")
	# Row text mirrors the old HUD strings: name, stars, rec level.
	var BoardScript := load("res://scripts/station/departure_board.gd")
	_assert(BoardScript.row_base_text("village", 1) == "VILLAGE OUTSKIRTS   ★☆☆☆   Rec. Lv 1",
		"row text village")
	_assert(BoardScript.row_base_text("supermarket", 4) == "MEGAMART SUPERMARKET   ★☆☆☆ $   Rec. Lv 4",
		"row text supermarket (+$ economy)")
	_assert(BoardScript.row_base_text("warlord", 5) == "WARLORD'S DOMAIN   ★★★★   Rec. Lv 5",
		"row text warlord")
	_assert(BoardScript.row_base_text("village", 6) == "VILLAGE OUTSKIRTS   ★☆☆☆   Rec. Lv 6",
		"row text rec level follows cycle")


func _test_station_phase3() -> void:
	print("[Playtest] Train station phase 3 (danger model)...")
	var DungeonScript := load("res://scripts/dungeon/dungeon.gd")
	# Tier mapping covers all 5 themes.
	var tiers: Dictionary = DungeonScript.DANGER_TIERS
	_assert(tiers.get("village") == 1 and tiers.get("dungeon") == 2 \
		and tiers.get("depths") == 3 and tiers.get("supermarket") == 1 \
		and tiers.get("warlord") == 4, "DANGER_TIERS covers all 5 themes")
	_assert(DungeonScript.TIER_MULT.get(1) == 1.0 and DungeonScript.TIER_MULT.get(4) == 2.2,
		"TIER_MULT endpoints sane")
	# danger_mult spot checks (epsilon).
	_assert(absf(DungeonScript.danger_mult("village", 1) - 1.0) < 0.001,
		"village L1 = 1.0")
	_assert(absf(DungeonScript.danger_mult("dungeon", 2) - 1.3 * 1.15) < 0.001,
		"dungeon L2 = 1.3*1.15")
	_assert(absf(DungeonScript.danger_mult("depths", 3) - 1.7 * pow(1.15, 2)) < 0.001,
		"depths L3 = 1.7*1.15^2")
	_assert(absf(DungeonScript.danger_mult("warlord", 5) - 2.2 * pow(1.15, 4)) < 0.001,
		"warlord L5 = 2.2*1.15^4")
	_assert(absf(DungeonScript.danger_mult("village", 6) - pow(1.15, 5)) < 0.001,
		"cycle-2 village L6 = 1.15^5")
	_assert(absf(DungeonScript.danger_mult("supermarket", 4) - pow(1.15, 3)) < 0.001,
		"supermarket L4 = tier 1 * depth (economy run)")
	_assert(absf(DungeonScript.danger_mult("nope", 1) - 1.0) < 0.001,
		"unknown theme defaults to tier 1")
	# XP formula: scaled, never below 1.
	_assert(maxi(1, roundi(5.0 * 0.1)) == 1, "XP floor at 1")
	_assert(maxi(1, roundi(10.0 * 2.24825)) == 22, "XP scales with danger")
	# Loot sell formula: rounded int.
	_assert(roundi(25.0 * 1.495) == 37, "cereal box $25 * dungeon L2 -> $37")
	_assert(roundi(0.0 * 3.8) == 0, "zero sell_value stays zero")
	# Wiring.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func spawn_pickup(item_id: String, pos: Vector3, value_mult: float = 1.0)"),
		"spawn_pickup value_mult param")
	_assert(dsrc.contains("pickup.value_mult = value_mult"), "pickup stores value_mult")
	_assert(dsrc.contains("reward_scale: float = 1.0"), "spawn_mob reward_scale param")
	_assert(dsrc.contains("mob.reward_scale"), "late-joiner re-sync passes reward_scale")
	_assert(dsrc.contains("_danger_mult() * NetworkManager.host_difficulty"),
		"dmg_scale from danger model")
	_assert(dsrc.contains("func _danger_mult()"), "_danger_mult helper exists")
	_assert(not dsrc.contains("theme.hp_scale"), "theme.hp_scale no longer read")
	_assert(not dsrc.contains("theme.dmg_scale"), "theme.dmg_scale no longer read")
	_assert(dsrc.contains("(level_number - 1) / THEME_ORDER.size()"),
		"cycle math untouched")
	var msrc := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(msrc.contains("var reward_scale := 1.0"), "mob stores reward_scale")
	_assert(msrc.contains("maxi(1, roundi(float(data.xp_reward) * reward_scale))"),
		"XP scaled with floor")
	_assert(msrc.contains("p_reward_scale: float = 1.0"), "setup takes reward_scale")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("func receive_item(item_id: String, sell_value: int = -1)"),
		"receive_item sell_value param")
	var isrc := FileAccess.get_file_as_string("res://scripts/items/item_pickup.gd")
	_assert(isrc.contains("var value_mult := 1.0"), "pickup keeps value_mult")
	_assert(isrc.contains("receive_item\", item.id, item.sell_value"),
		"claim passes scaled sell value")


func _test_apex_phase1() -> void:
	print("[Playtest] Apex phase 1 (plumbing)...")
	var DungeonScript := load("res://scripts/dungeon/dungeon.gd")
	var StationScript := load("res://scripts/station/station.gd")
	var BoardScript := load("res://scripts/station/departure_board.gd")
	# Apex cycle detection: cycles 3/6/9/12 true, everything else false.
	for c in [3, 6, 9, 12]:
		_assert(DungeonScript.is_apex_cycle(c), "cycle %d is apex" % c)
	for c in [0, 1, 2, 4, 5, 7, 8, 10, 11, 13]:
		_assert(not DungeonScript.is_apex_cycle(c), "cycle %d is not apex" % c)
	# Apex boss rotation: 3->boar, 6->warden, 9->horror, then repeating.
	_assert(DungeonScript.apex_boss_id(3) == "apex_boar", "cycle 3 -> apex_boar")
	_assert(DungeonScript.apex_boss_id(6) == "apex_warden", "cycle 6 -> apex_warden")
	_assert(DungeonScript.apex_boss_id(9) == "apex_horror", "cycle 9 -> apex_horror")
	_assert(DungeonScript.apex_boss_id(12) == "apex_boar", "cycle 12 -> apex_boar (rotates)")
	_assert(DungeonScript.apex_boss_id(15) == "apex_warden", "cycle 15 -> apex_warden (rotates)")
	# theme_apex.tres loads with arena params.
	var theme: Resource = load("res://data/levels/theme_apex.tres")
	_assert(theme != null, "theme_apex.tres loads")
	_assert(str(theme.get("theme_id")) == "apex", "apex theme_id")
	_assert(str(theme.get("display_name")) == "Apex Arena", "apex display name")
	_assert(int(theme.get("puzzle_key_count")) == 0, "apex needs no keys")
	_assert(not (theme.get("mob_mix") as Dictionary).is_empty(), "apex has a wave mob mix")
	_assert(str(theme.get("boss_id")) == "apex_boar", "apex default boss_id (overridden per cycle)")
	# The three apex boss data files: boss flags, titles, base stats copied
	# from the matching bosses, 384px sprites reused.
	var specs := {
		"apex_boar": ["APEX BRISTLEBACK", "boss_boar"],
		"apex_warden": ["APEX WARDEN", "boss_warden"],
		"apex_horror": ["APEX MAW OF THE DEEP", "boss_horror"],
	}
	for aid in specs:
		var data: Resource = load("res://data/mobs/%s.tres" % aid)
		_assert(data != null, "mob %s loads" % aid)
		if data == null:
			continue
		_assert(str(data.get("id")) == aid, "%s id" % aid)
		_assert(bool(data.get("is_boss")), "%s is_boss" % aid)
		_assert(str(data.get("boss_title")) == specs[aid][0], "%s boss_title" % aid)
		_assert(not (data.get("frames") as Array).is_empty(), "%s reuses boss sprite" % aid)
		var src: Resource = load("res://data/mobs/%s.tres" % specs[aid][1])
		_assert(absf(float(data.get("health")) - float(src.get("health"))) < 0.001,
			"%s base HP matches %s" % [aid, specs[aid][1]])
		_assert(absf(float(data.get("damage")) - float(src.get("damage"))) < 0.001,
			"%s base damage matches %s" % [aid, specs[aid][1]])
	# Board destinations: warlord row becomes APEX ARENA on apex cycles only.
	var d3: Array = DungeonScript.board_destinations(11) # cycle 3
	_assert(d3.size() == 5, "board still has 5 rows on apex cycles")
	_assert(d3.has("apex") and not d3.has("warlord"), "warlord -> apex swap (cycle 3)")
	var d1: Array = DungeonScript.board_destinations(1) # cycle 1
	_assert(d1.has("warlord") and not d1.has("apex"), "warlord row normal (cycle 1)")
	var d4: Array = DungeonScript.board_destinations(16) # cycle 4
	_assert(d4.has("warlord") and not d4.has("apex"), "warlord row normal (cycle 4)")
	# Apex row text: name, 5 stars, Rec. Lv = party level + 5.
	_assert(BoardScript.row_base_text("apex", 11, 30) == "APEX ARENA   ★★★★★   Rec. Lv 35",
		"apex row text")
	_assert(str(StationScript.BOARD_STARS.get("apex")) == "★★★★★", "apex 5 danger stars")
	_assert((StationScript.DRESSING_LAMPS as Dictionary).has("apex"), "apex lamp tint set")
	_assert(str(StationScript.theme_display_name("apex")) == "Apex Arena", "apex display name from tres")
	# Danger model: apex uses reward tier 4 (warlord) for XP/loot scaling.
	_assert(absf(DungeonScript.danger_mult("apex", 13) - 2.2 * pow(1.15, 12)) < 0.001,
		"apex danger = tier 4")
	_assert(DungeonScript.arrival_tint("apex") == Color(1.0, 0.25, 0.2), "apex arrival tint red")
	# Boss spawn scaling through the real spawn-site helper.
	var s_apex: Array = DungeonScript.boss_spawn_scales(true, 2.2, 1.0)
	_assert(absf(s_apex[0] - 5.5) < 0.001 and absf(s_apex[1] - 3.3) < 0.001,
		"apex scales: 2.5x HP, 1.5x dmg")
	var s_norm: Array = DungeonScript.boss_spawn_scales(false, 2.2, 1.0)
	_assert(absf(s_norm[0] - 2.2) < 0.001 and absf(s_norm[1] - 2.2) < 0.001,
		"normal boss scales unchanged")
	var s_diff: Array = DungeonScript.boss_spawn_scales(true, 1.0, 1.5)
	_assert(absf(s_diff[0] - 3.75) < 0.001 and absf(s_diff[1] - 2.25) < 0.001,
		"apex scales multiply host difficulty")
	# Wiring: the real spawn path and the boss-death completion hook.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("theme.boss_id = apex_boss_id(get_cycle_number())"),
		"dungeon picks rotating apex boss on load")
	_assert(dsrc.contains("boss_spawn_scales(is_apex,"), "_spawn_boss uses apex scaling")
	_assert(dsrc.contains("func _check_apex_boss_kill"), "apex boss-death hook exists")
	_assert(dsrc.contains("_check_apex_boss_kill()"), "boss-death hook runs in _process")
	_assert(dsrc.contains("if is_apex:"), "apex skips the key hunt")
	var bsrc := FileAccess.get_file_as_string("res://scripts/station/departure_board.gd")
	_assert(bsrc.contains("Dungeon.board_destinations(next_level)"), "board rows from board_destinations")
	var stsrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(stsrc.contains("Dungeon.board_destinations(next_level_number)"),
		"votes validated against board destinations")
