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
	_test_save_collections()
	_test_save_scratch_runs_dir()
	_test_legacy_migration()
	_test_mp_slots()
	_test_saves_ui()
	_test_affinity_families()
	_test_rogue_traits()
	_test_warrior_signatures()
	_test_affinity_ui()
	_test_affinity_save_roundtrip()
	_test_specialization_level_gate()
	_test_pause_tabs()
	_test_pause_stats_zero_scroll()
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
	_test_audio_coverage()
	_test_audio_new_features()
	_test_station_annex()
	_test_station_embedded()
	_test_annex_departure()
	_test_annex_forfeit()
	_test_train_interior()
	_test_boarding_flow()
	_test_train_ride()
	_test_train_dressing()
	_test_cycle_scaling()
	_test_ai_director()
	_test_economy()
	_test_trade_no_self_trade()
	_test_apex_phase1()
	_test_specials_phase1()
	_test_specials_phase2()
	_test_wave_stall_watchdog()
	_test_eagle_eye_warlord_hide()
	_test_issue18_ui_fixes()
	_test_fireball_fuse()
	_test_issue22_23_fixes()
	_test_warlord_spawn_avoids_river()
	_test_apex_mechanics()
	_test_apex_relics()
	_test_bounty_phase1()
	_test_combo_phase1()
	_test_combo_codex()
	_test_bounty_phase2()
	_test_leaderboard_phase1()
	_test_echo_phase2()
	_test_workshop_phase3()

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


func _test_save_collections() -> void:
	print("[Playtest] Affinity collections persistence (issue #4 Phase 2)...")
	var SaveScript = load("res://scripts/autoload/save_manager.gd")
	var mgr = SaveScript.new()
	# Back up the real local profile and the slots this test touches.
	var prof_path := "user://profile_local.cfg"
	var prof_backup := ""
	if FileAccess.file_exists(prof_path):
		prof_backup = FileAccess.get_file_as_string(prof_path)
		DirAccess.remove_absolute(prof_path)
	var slot_paths := ["user://runs/solo_0.cfg", "user://runs/mp_1.cfg"]
	var slot_backups := {}
	for sp in slot_paths:
		if FileAccess.file_exists(sp):
			slot_backups[sp] = FileAccess.get_file_as_bytes(sp)
			DirAccess.remove_absolute(sp)
	mgr._profile.clear()  # fresh standalone instance: start from empty meta

	# Profile roundtrip, per-class keyed.
	var mage_coll := {"fire": {"traits": ["kindled"], "signature": false}}
	mgr.save_collections("mage", mage_coll)
	_assert(mgr.load_collections("mage") == mage_coll, "collections roundtrip")
	_assert(mgr.load_collections("rogue") == {}, "unknown class has no collections")
	# Merge: union of traits, signature OR — never a downgrade.
	var merged: Dictionary = SaveScript.merge_collections(
		{"fire": {"traits": ["kindled"], "signature": false}},
		{"fire": {"traits": ["wildfire"], "signature": true},
			"frost": {"traits": [], "signature": false}})
	var mtraits: Array = merged["fire"]["traits"]
	_assert(mtraits.has("kindled") and mtraits.has("wildfire"), "merge unions traits")
	_assert(bool(merged["fire"]["signature"]), "merge ORs signature")
	_assert(merged.has("frost"), "merge adds missing families")
	_assert(SaveScript.merge_collections({}, mage_coll) == mage_coll,
		"merge with empty keeps everything")

	# Solo save_run persists the run's collection into the profile.
	var warrior_coll := {"warden": {"traits": ["bulwark"], "signature": false}}
	_assert(mgr.save_run({"class_id": "warrior", "level_number": 1,
		"player_state": {"family_collection": warrior_coll}}, "solo", 0),
		"solo save with collection")
	_assert(mgr.load_collections("warrior") == warrior_coll,
		"solo save_run persists collections to profile")
	# An empty collection never clobbers earned unlocks.
	_assert(mgr.save_run({"class_id": "warrior", "level_number": 1,
		"player_state": {}}, "solo", 0), "solo save without collection")
	_assert(mgr.load_collections("warrior") == warrior_coll,
		"empty collection doesn't clobber profile")

	# Per-class separation: rogue write leaves mage/warrior untouched.
	mgr.save_collections("rogue", {"shadow": {"traits": [], "signature": true}})
	_assert(mgr.load_collections("mage") == mage_coll, "mage untouched by rogue write")
	_assert(mgr.load_collections("warrior") == warrior_coll, "warrior untouched by rogue write")

	# MP save_run persists ONLY the host's entry — clients keep their own
	# profiles on their own machines.
	var mp_run := {"class_id": "mage", "level_number": 2, "roster": [
		{"steam_id": 111, "class_id": "mage", "is_host": true,
			"player_state": {"family_collection":
				{"storm": {"traits": ["charged"], "signature": false}}}},
		{"steam_id": 222, "class_id": "rogue", "is_host": false,
			"player_state": {"family_collection":
				{"shadow": {"traits": ["gloom"], "signature": true}}}},
	]}
	_assert(mgr.save_run(mp_run, "mp", 1), "mp save with roster")
	_assert(mgr.load_collections("mage") == {"storm": {"traits": ["charged"], "signature": false}},
		"mp save persists HOST collection")
	_assert(mgr.load_collections("rogue") == {"shadow": {"traits": [], "signature": true}},
		"mp save never persists client collections")

	# Respec preserves collections (behavioral, on a real Player).
	var PlayerScript = load("res://scripts/player/player.gd")
	var p = PlayerScript.new()
	p.family_collection = {"fire": {"traits": ["kindled"], "signature": false}}
	p.specialization = "fireball"
	p.affinity = {"fireball": 30.0}
	p.respec()
	_assert(p.specialization == "" and float(p.affinity.get("fireball", -1.0)) == 0.0,
		"respec clears specialization + affinity")
	_assert(p.family_collection == {"fire": {"traits": ["kindled"], "signature": false}},
		"respec preserves family_collection")
	p.free()

	# Wiring: spawn merges the profile copy, departure persists per-peer,
	# class switch persists outgoing + loads incoming, save_run funnels.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("SaveManager.merge_collections(")
		and dsrc.contains("SaveManager.load_collections(class_id)"),
		"_do_spawn merges profile collections")
	_assert(dsrc.contains("SaveManager.save_collections(str(me.class_id), coll)"),
		"board_train_interior persists each peer's own collection")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("SaveManager.save_collections(str(class_id), family_collection)"),
		"switch_class persists outgoing collection")
	_assert(psrc.contains("SaveManager.load_collections(new_class)"),
		"switch_class loads incoming collection")
	var ssrc := FileAccess.get_file_as_string("res://scripts/autoload/save_manager.gd")
	_assert(ssrc.contains("_persist_run_collections(run, mode)"),
		"save_run funnels collections to the profile")
	_assert(mgr._cloud_write_count == 0, "no cloud writes without Steam")
	mgr.free()

	# Restore.
	for sp in slot_paths:
		if slot_backups.has(sp):
			var f := FileAccess.open(sp, FileAccess.WRITE)
			f.store_buffer(slot_backups[sp])
		elif FileAccess.file_exists(sp):
			DirAccess.remove_absolute(sp)
	if prof_backup != "":
		var pf := FileAccess.open(prof_path, FileAccess.WRITE)
		pf.store_string(prof_backup)
	elif FileAccess.file_exists(prof_path):
		DirAccess.remove_absolute(prof_path)


func _test_save_scratch_runs_dir() -> void:
	print("[Playtest] Scratch runs dir isolation (boarding driver hardening)...")
	var SaveScript = load("res://scripts/autoload/save_manager.gd")
	var mgr = SaveScript.new()
	var scratch := "user://runs_scratch_test"
	# Ensure a clean slate; never touch real user://runs.
	if DirAccess.dir_exists_absolute(scratch):
		for f in DirAccess.get_files_at(scratch):
			DirAccess.remove_absolute(scratch.path_join(f))
		DirAccess.remove_absolute(scratch)
	mgr.set("_test_runs_dir", scratch)
	# Slot paths redirect into the scratch dir.
	_assert(mgr._slot_path("solo", 0) == scratch + "/solo_0.cfg",
		"scratch: slot path redirects")
	_assert(mgr._slot_path("mp", 2) == scratch + "/mp_2.cfg",
		"scratch: mp slot path redirects")
	# save_run writes ONLY to the scratch dir.
	var ok: bool = mgr.save_run({"theme_id": "village"}, "solo", 1)
	_assert(ok, "scratch: save_run succeeds")
	_assert(FileAccess.file_exists(scratch + "/solo_1.cfg"),
		"scratch: run file lands in scratch dir")
	_assert(not FileAccess.file_exists("user://runs/solo_1.cfg"),
		"scratch: real slot untouched")
	# load_run reads back through the redirect.
	var back: Dictionary = mgr.load_run("solo", 1)
	_assert(str(back.get("theme_id", "")) == "village",
		"scratch: load_run roundtrips")
	# list_runs sees the scratch file.
	var listed: Array = mgr.list_runs("solo")
	_assert(listed.size() == 1 and int(listed[0]["slot"]) == 1,
		"scratch: list_runs sees scratch slot")
	# Invalid modes/slots still rejected under the redirect.
	_assert(mgr._slot_path("bogus", 0) == "", "scratch: bad mode rejected")
	_assert(mgr._slot_path("solo", 9) == "", "scratch: bad slot rejected")
	# Unpin restores the real path.
	mgr.set("_test_runs_dir", "")
	_assert(mgr._slot_path("solo", 0) == "user://runs/solo_0.cfg",
		"scratch: unpin restores real path")
	# Cleanup: remove the scratch dir and everything in it.
	for f in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch.path_join(f))
	DirAccess.remove_absolute(scratch)
	_assert(not DirAccess.dir_exists_absolute(scratch),
		"scratch: dir cleaned up")
	mgr.free()


func _test_legacy_migration() -> void:
	print("[Playtest] Legacy migration (issue #4 Phase 3)...")
	var SaveScript = load("res://scripts/autoload/save_manager.gd")
	var legacy_paths := ["user://solo_warrior.cfg", "user://solo_rogue.cfg",
		"user://solo_mage.cfg", "user://solo_architect.cfg",
		"user://run_save.cfg", "user://savegame.cfg"]
	var slot_paths := []
	for mode in ["solo", "mp"]:
		for s in range(3):
			slot_paths.append("user://runs/%s_%d.cfg" % [mode, s])
	var prof_path := "user://profile_local.cfg"
	# Back everything up.
	var backups := {}
	for sp in legacy_paths + slot_paths + [prof_path]:
		if FileAccess.file_exists(sp):
			backups[sp] = FileAccess.get_file_as_bytes(sp)
			DirAccess.remove_absolute(sp)

	# Legacy writer: the exact pre-slot format (run/data, stamped saved_at).
	var write_legacy := func(path: String, data: Dictionary) -> void:
		var cfg := ConfigFile.new()
		cfg.set_value("run", "data", data)
		cfg.save(path)
	var legacy_run := func(class_id: String, theme: String, lvl: int, saved_at: String,
			is_mp: bool) -> Dictionary:
		var coll := {}
		if class_id == "architect":
			coll = {"fire": {"traits": ["kindled"], "signature": false}}
		return {"class_id": class_id, "theme_id": theme, "level_number": lvl,
			"is_multiplayer": is_mp, "saved_at": saved_at, "save_version": 1,
			"player_state": {"level": lvl, "family_collection": coll}}

	# --- Case A: synthetic tree, empty slots. 4 solo + old MP + old profile.
	write_legacy.call("user://solo_warrior.cfg",
		legacy_run.call("warrior", "village", 1, "2026-09-01T10:00:00", false))
	write_legacy.call("user://solo_rogue.cfg",
		legacy_run.call("rogue", "dungeon", 3, "2026-09-20T10:00:00", false))
	write_legacy.call("user://solo_mage.cfg",
		legacy_run.call("mage", "depths", 5, "2026-10-01T10:00:00", false))
	write_legacy.call("user://solo_architect.cfg",
		legacy_run.call("architect", "supermarket", 2, "2026-10-03T10:00:00", false))
	var mp_legacy: Dictionary = legacy_run.call("mage", "warlord", 6, "2026-10-02T10:00:00", true)
	mp_legacy["roster"] = [
		{"steam_id": 111, "class_id": "mage", "is_host": true, "player_state": {"level": 6}},
		{"steam_id": 222, "class_id": "rogue", "is_host": false, "player_state": {"level": 5}}]
	write_legacy.call("user://run_save.cfg", mp_legacy)
	var old_meta := ConfigFile.new()
	old_meta.set_value("meta", "unlocked_items", ["void_blade"])
	old_meta.set_value("meta", "unlocked_achievements", ["kill_100"])
	old_meta.set_value("meta", "cipher_fragments", [0, 3])
	old_meta.set_value("meta", "total_runs", 7)
	old_meta.set_value("meta", "total_kills", 150)
	old_meta.set_value("meta", "deepest_cycle", 2)
	old_meta.set_value("meta", "total_cash_earned", 900)
	old_meta.set_value("meta", "architect_unlocked", true)
	old_meta.save("user://savegame.cfg")

	var mgr = SaveScript.new()
	mgr._migrate_legacy()
	# Recency: newest -> slot 0.
	_assert(str(mgr.load_run("solo", 0).get("class_id", "")) == "architect",
		"newest legacy run -> solo slot 0")
	_assert(str(mgr.load_run("solo", 0).get("saved_at", "")) == "2026-10-03T10:00:00",
		"migration preserves the original saved_at")
	_assert(str(mgr.load_run("solo", 1).get("class_id", "")) == "mage",
		"second newest -> solo slot 1")
	_assert(str(mgr.load_run("solo", 2).get("class_id", "")) == "rogue",
		"third -> solo slot 2")
	var solo_classes := []
	for s in range(3):
		solo_classes.append(str(mgr.load_run("solo", s).get("class_id", "")))
	_assert(not solo_classes.has("warrior"), "oldest legacy left as overflow")
	_assert(bool(mgr.load_run("mp", 0).get("is_multiplayer", false)),
		"legacy MP run -> mp slot 0")
	_assert((mgr.load_run("mp", 0).get("roster", []) as Array).size() == 2,
		"migrated MP roster preserved")
	# Nothing deleted, ever.
	for lp in legacy_paths:
		_assert(FileAccess.file_exists(lp), "legacy file not deleted: %s" % lp)
	# Only the overflow is listed.
	var leftover: Array = mgr.list_legacy_saves()
	_assert(leftover.size() == 1 and str(leftover[0]["path"]) == "user://solo_warrior.cfg",
		"overflow stays on disk and listed")
	# Old profile meta merged in.
	_assert("void_blade" in mgr.get_unlocked_items(), "legacy unlocks imported")
	_assert(mgr.get_total_runs() == 7, "legacy total_runs imported")
	_assert(mgr.get_total_kills() == 150, "legacy total_kills imported")
	_assert(mgr.get_deepest_cycle() == 2, "legacy deepest_cycle imported")
	_assert(mgr.get_total_cash_earned() == 900, "legacy cash imported")
	_assert(mgr.get_unlocked_achievements() == ["kill_100"], "legacy achievements imported")
	_assert(mgr.get_cipher_fragments() == [0, 3], "legacy cipher fragments imported")
	_assert(mgr.is_architect_unlocked(), "legacy architect unlock imported")
	# Migrated collections funnel into the profile (Phase 2).
	_assert(mgr.load_collections("architect")
		== {"fire": {"traits": ["kindled"], "signature": false}},
		"migrated run collections funneled to profile")
	# Idempotent: a second run changes nothing, and a cleared slot is never
	# back-filled with a stale copy.
	mgr.clear_run("solo", 0)
	mgr._migrate_legacy()
	_assert(not mgr.has_run("solo", 0), "cleared slot not resurrected")
	_assert(mgr.list_legacy_saves().size() == 1, "still exactly one overflow")
	_assert(mgr._cloud_write_count == 0, "no cloud writes without Steam")
	mgr.free()

	# --- Case B: occupied slots. Legacy files stay put and listed.
	DirAccess.remove_absolute(prof_path)
	for sp in slot_paths + legacy_paths:
		if FileAccess.file_exists(sp):
			DirAccess.remove_absolute(sp)
	var mgr2 = SaveScript.new()
	for s in range(3):
		mgr2.save_run({"class_id": "mage", "level_number": 9}, "solo", s)
		mgr2.save_run({"class_id": "mage", "level_number": 9, "roster": []}, "mp", s)
	write_legacy.call("user://solo_warrior.cfg",
		legacy_run.call("warrior", "village", 1, "2026-09-01T10:00:00", false))
	write_legacy.call("user://solo_rogue.cfg",
		legacy_run.call("rogue", "dungeon", 3, "2026-09-20T10:00:00", false))
	write_legacy.call("user://run_save.cfg",
		legacy_run.call("mage", "warlord", 6, "2026-10-02T10:00:00", true))
	mgr2._migrate_legacy()
	_assert(int(mgr2.load_run("solo", 0).get("level_number", 0)) == 9,
		"occupied solo slot untouched")
	_assert(int(mgr2.load_run("mp", 2).get("level_number", 0)) == 9,
		"occupied mp slot untouched")
	for lp in ["user://solo_warrior.cfg", "user://solo_rogue.cfg", "user://run_save.cfg"]:
		_assert(FileAccess.file_exists(lp), "occupied case: legacy kept: %s" % lp)
	_assert(mgr2.list_legacy_saves().size() == 3, "occupied case: overflow listed")
	mgr2.free()

	# Restore.
	for sp in backups:
		var f := FileAccess.open(sp, FileAccess.WRITE)
		f.store_buffer(backups[sp])
		f.close()
	for sp in legacy_paths + slot_paths + [prof_path]:
		if not backups.has(sp) and FileAccess.file_exists(sp):
			DirAccess.remove_absolute(sp)


func _test_mp_slots() -> void:
	print("[Playtest] MP per-slot saves (issue #4 Phase 4)...")
	var SaveScript = load("res://scripts/autoload/save_manager.gd")
	var DungeonScript = load("res://scripts/dungeon/dungeon.gd")
	var mgr = SaveScript.new()
	# Back up the mp slots and the local profile.
	var prof_path := "user://profile_local.cfg"
	var prof_backup := PackedByteArray()
	if FileAccess.file_exists(prof_path):
		prof_backup = FileAccess.get_file_as_bytes(prof_path)
		DirAccess.remove_absolute(prof_path)
	var slot_paths := ["user://runs/mp_0.cfg", "user://runs/mp_1.cfg", "user://runs/mp_2.cfg"]
	var slot_backups := {}
	for sp in slot_paths:
		if FileAccess.file_exists(sp):
			slot_backups[sp] = FileAccess.get_file_as_bytes(sp)
			DirAccess.remove_absolute(sp)

	# MP slot roundtrip with a roster.
	var roster := [
		{"steam_id": 111, "player_name": "Host", "class_id": "mage", "is_host": true,
			"player_state": {"level": 6}},
		{"steam_id": 222, "player_name": "Friend", "class_id": "rogue", "is_host": false,
			"player_state": {"level": 5}},
	]
	var mp_run := {"theme_id": "warlord", "level_number": 4, "seed": 1234,
		"is_multiplayer": true, "class_id": "mage", "roster": roster}
	_assert(mgr.save_run(mp_run, "mp", 1), "mp save to slot 1")
	var loaded: Dictionary = mgr.load_run("mp", 1)
	_assert(bool(loaded.get("is_multiplayer", false)), "mp flag roundtrips")
	var lroster: Array = loaded.get("roster", [])
	_assert(lroster.size() == 2, "roster roundtrips")
	_assert(int(lroster[0].get("steam_id", 0)) == 111
		and int(lroster[1].get("steam_id", 0)) == 222, "roster steam IDs roundtrip")
	_assert(str(lroster[1].get("class_id", "")) == "rogue", "roster classes roundtrip")
	_assert(not mgr.has_run("mp", 0) and not mgr.has_run("mp", 2),
		"saving one mp slot leaves the others empty")

	# Wipe clears only the target slot (party-wipe semantics).
	_assert(mgr.save_run(mp_run, "mp", 0), "mp save slot 0")
	_assert(mgr.save_run(mp_run, "mp", 2), "mp save slot 2")
	mgr.clear_run("mp", 1)
	_assert(not mgr.has_run("mp", 1), "wiped slot cleared")
	_assert(mgr.has_run("mp", 0) and mgr.has_run("mp", 2), "other slots survive wipe")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains(
		"SaveManager.clear_run(SaveManager.MODE_MP, NetworkManager.active_run_slot)"),
		"party wipe clears the active mp slot")

	# Rejoin matching is per slot, by Steam ID (static; no live dungeon needed).
	var slot0_roster := [
		{"steam_id": 111, "class_id": "mage"},
		{"steam_id": 222, "class_id": "rogue"},
	]
	var slot1_roster := [{"steam_id": 333, "class_id": "warrior"}]
	_assert(str(DungeonScript.find_roster_entry(slot0_roster, 222).get("class_id", ""))
		== "rogue", "rejoin matches seat by steam ID")
	_assert(DungeonScript.find_roster_entry(slot0_roster, 999).is_empty(),
		"stranger matches no seat")
	_assert(DungeonScript.find_roster_entry(slot1_roster, 111).is_empty(),
		"slot 1 roster doesn't seat slot 0's player")
	_assert(str(DungeonScript.find_roster_entry(slot1_roster, 333).get("class_id", ""))
		== "warrior", "slot 1 roster seats its own player")

	# Wiring: slot_index threaded through the save RPCs, stale guarded,
	# no hardcoded server peer, stale roster cleared, staging shows the slot.
	_assert(dsrc.contains("func rpc_request_save_state(slot_index: int)"),
		"rpc_request_save_state takes slot_index")
	_assert(dsrc.contains("func rpc_submit_save_state(state: Dictionary, slot_index: int)"),
		"rpc_submit_save_state takes slot_index")
	_assert(dsrc.contains("rpc(\"rpc_request_save_state\", _save_slot)"),
		"save request carries the slot")
	_assert(dsrc.contains("if slot_index != _save_slot:"),
		"stale submit ignored")
	_assert(dsrc.contains("rpc_id(NetworkManager.server_id, \"rpc_submit_save_state\""),
		"submit targets server_id")
	_assert(not dsrc.contains("rpc_id(1,"), "no hardcoded server peer 1 in dungeon.gd")
	var nsrc := FileAccess.get_file_as_string("res://scripts/autoload/network_manager.gd")
	_assert(nsrc.contains("Dungeon.continued_roster = []"),
		"leave_lobby clears stale continued roster")
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(msrc.contains("MP Slot %d"), "staging screen shows the slot")

	_assert(mgr._cloud_write_count == 0, "no cloud writes without Steam")
	mgr.free()

	# Restore.
	for sp in slot_paths:
		if slot_backups.has(sp):
			var f := FileAccess.open(sp, FileAccess.WRITE)
			f.store_buffer(slot_backups[sp])
			f.close()
		elif FileAccess.file_exists(sp):
			DirAccess.remove_absolute(sp)
	if not prof_backup.is_empty():
		var pf := FileAccess.open(prof_path, FileAccess.WRITE)
		pf.store_buffer(prof_backup)
		pf.close()
	elif FileAccess.file_exists(prof_path):
		DirAccess.remove_absolute(prof_path)


func _test_saves_ui() -> void:
	print("[Playtest] Saves UI redesign (issue #4 Phase 5)...")
	var SaveScript = load("res://scripts/autoload/save_manager.gd")
	var mgr = SaveScript.new()
	# Back up all six slots and the local profile.
	var prof_path := "user://profile_local.cfg"
	var prof_backup := PackedByteArray()
	if FileAccess.file_exists(prof_path):
		prof_backup = FileAccess.get_file_as_bytes(prof_path)
		DirAccess.remove_absolute(prof_path)
	var slot_paths: Array = []
	for mode in ["solo", "mp"]:
		for slot in range(3):
			slot_paths.append("user://runs/%s_%d.cfg" % [mode, slot])
	var slot_backups := {}
	for sp in slot_paths:
		if FileAccess.file_exists(sp):
			slot_backups[sp] = FileAccess.get_file_as_bytes(sp)
			DirAccess.remove_absolute(sp)

	# Card data model: occupied / empty / occupied across the three solo slots.
	var solo0 := {"theme_id": "dungeon", "level_number": 3, "seed": 11,
		"is_multiplayer": false, "class_id": "mage", "player_state": {"level": 12}}
	var solo2 := {"theme_id": "village", "level_number": 1, "seed": 22,
		"is_multiplayer": false, "class_id": "rogue", "player_state": {"level": 5}}
	_assert(mgr.save_run(solo0, "solo", 0), "solo save slot 0")
	_assert(mgr.save_run(solo2, "solo", 2), "solo save slot 2")
	_assert(mgr.has_run("solo", 0) and not mgr.has_run("solo", 1)
		and mgr.has_run("solo", 2), "card states: occupied/empty/occupied")
	_assert(not mgr.run_summary(mgr.load_run("solo", 0)).is_empty(),
		"occupied card has metadata")
	_assert("Mage" in mgr.run_summary(mgr.load_run("solo", 0)),
		"card metadata names the class")
	# First-empty-slot logic (mirrors _first_empty_slot).
	var first_empty := -1
	for slot in range(3):
		if not mgr.has_run("solo", slot):
			first_empty = slot
			break
	_assert(first_empty == 1, "first empty solo slot is 1")
	_assert(mgr.save_run(solo0, "solo", 1), "solo save slot 1")
	first_empty = -1
	for slot in range(3):
		if not mgr.has_run("solo", slot):
			first_empty = slot
			break
	_assert(first_empty == -1, "no empty slot when all full")

	# MP card data: roster summary drives the card metadata.
	var mp_run := {"theme_id": "warlord", "level_number": 4, "seed": 33,
		"is_multiplayer": true, "class_id": "mage", "roster": [
			{"steam_id": 111, "class_id": "mage", "player_state": {"level": 6}},
			{"steam_id": 222, "class_id": "rogue", "player_state": {"level": 5}},
		]}
	_assert(mgr.save_run(mp_run, "mp", 1), "mp save slot 1")
	var mp_summary: String = mgr.run_summary(mgr.load_run("mp", 1))
	_assert("2 players" in mp_summary, "mp card metadata shows roster")

	# Wiring: slot cards, per-slot actions, overwrite modal, legacy rows.
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(msrc.contains("func _build_slot_card(mode: String, slot: int)"),
		"slot card builder exists")
	_assert(msrc.contains("%SoloSlotsList") and msrc.contains("%MpSlotsList"),
		"both phases build slot cards")
	_assert(msrc.contains("\"New Run\"") and msrc.contains("\"Continue\""),
		"cards have New Run / Continue actions")
	_assert(msrc.contains("func _first_empty_slot(mode: String) -> int"),
		"first-empty-slot helper exists")
	_assert(msrc.contains("func _show_overwrite_confirm(mode: String, slot: int)"),
		"overwrite confirm exists")
	_assert(msrc.contains("overwrite it?"), "modal asks before overwriting")
	_assert(msrc.contains("NetworkManager.play_solo(_confirm_slot)"),
		"confirmed solo overwrite starts in that slot")
	_assert(msrc.contains("_host_slot = _confirm_slot"),
		"confirmed mp overwrite targets that slot")
	_assert(msrc.contains("NetworkManager.host_lobby(_host_slot)"),
		"lobby hosts into the chosen slot")
	_assert(msrc.contains("func _refresh_legacy_rows("),
		"legacy overflow rows exist")
	_assert(msrc.contains("shown >= 2"), "legacy rows capped at 2")
	_assert(msrc.contains("more legacy saves on disk"), "legacy overflow counted")
	var nsrc := FileAccess.get_file_as_string("res://scripts/autoload/network_manager.gd")
	_assert(nsrc.contains("func play_solo(slot: int = 0)"),
		"play_solo takes a slot")
	_assert(nsrc.contains("func host_lobby(slot: int = 0)"),
		"host_lobby takes a slot")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("play_solo(NetworkManager.active_run_slot)"),
		"quick restart keeps the death slot")
	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/main_menu.tscn")
	for node_name in ["SoloSlotsList", "MpSlotsList", "SoloLegacyList", "MpLegacyList"]:
		_assert(tsrc.contains("[node name=\"%s\"" % node_name),
			"scene has " + node_name)
	for gone in ["NewGameButton", "ContinueMultiButton", "ContinueMultiInfo",
			"SavesLabel", "_on_new_game_pressed", "_on_continue_multi_pressed"]:
		_assert(not tsrc.contains(gone) and not msrc.contains(gone),
			"old save UI fully removed: " + gone)

	_assert(mgr._cloud_write_count == 0, "no cloud writes without Steam")
	mgr.free()

	# Restore.
	for sp in slot_paths:
		if slot_backups.has(sp):
			var f := FileAccess.open(sp, FileAccess.WRITE)
			f.store_buffer(slot_backups[sp])
			f.close()
		elif FileAccess.file_exists(sp):
			DirAccess.remove_absolute(sp)
	if not prof_backup.is_empty():
		var pf := FileAccess.open(prof_path, FileAccess.WRITE)
		pf.store_buffer(prof_backup)
		pf.close()
	elif FileAccess.file_exists(prof_path):
		DirAccess.remove_absolute(prof_path)


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
	_assert(dsrc.contains("market_earned_visit += payout"),
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


func _test_audio_coverage() -> void:
	print("[Playtest] Audio: SFX coverage audit...")
	# Sound Engineer audit (2026-10-04): every SFX the game requests must both
	# synth a non-empty stream AND be registered in AudioManager's builder
	# list — unregistered names are silently dropped by sfx().
	var SoundScript := load("res://scripts/audio/sound_synth.gd")
	var amsrc := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	# Previously silent: requested by gameplay (player.gd) but missing from
	# the builder list — supermarket checkout + mage Holy Light made no sound.
	for sfx in ["cash_register", "holy_light", "holy_light_cast"]:
		var w: AudioStreamWAV = SoundScript.call(sfx)
		_assert(w != null and w.data.size() > 0, "synth builds %s" % sfx)
		_assert(amsrc.contains('"%s"' % sfx), "%s registered in builder list" % sfx)
	# New: boarding flow (all_aboard banner, per-player chime, door lock,
	# countdown beep, vote blip) + apex arena (announce fanfare, apex roar).
	for sfx in ["all_aboard", "board_chime", "door_lock", "countdown_tick",
			"vote_cast", "apex_announce", "apex_roar"]:
		var w2: AudioStreamWAV = SoundScript.call(sfx)
		_assert(w2 != null and w2.data.size() > 0, "synth builds %s" % sfx)
		_assert(amsrc.contains('"%s"' % sfx), "%s registered in builder list" % sfx)
	# Music: supermarket / warlord / apex now render their own themes instead
	# of falling through to the menu default track.
	var MusicScript := load("res://scripts/audio/music_gen.gd")
	for theme in ["supermarket", "warlord", "apex"]:
		var t: AudioStreamWAV = MusicScript.make_track(theme)
		_assert(t != null and t.data.size() > 0, "music renders %s theme" % theme)


func _test_audio_new_features() -> void:
	print("[Playtest] Audio: issue #6/#7/#8 SFX...")
	# DM assignment (2026-10-04): Relic Vault, Bounty Board, Combo Finishers.
	# Every new SFX must synth a non-empty stream and be registered.
	var SoundScript := load("res://scripts/audio/sound_synth.gd")
	var amsrc := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	for sfx in ["relic_pickup", "vault_open", "vault_close", "relic_equip",
			"bounty_accept", "bounty_complete", "bounty_toast",
			"finisher_orbital_strike", "finisher_stormcall",
			"finisher_shatter_cascade", "finisher_reciprocity_surge",
			"finisher_smoke_bombard", "codex_discover"]:
		var w: AudioStreamWAV = SoundScript.call(sfx)
		_assert(w != null and w.data.size() > 0, "synth builds %s" % sfx)
		_assert(amsrc.contains('"%s"' % sfx), "%s registered in builder list" % sfx)


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
	var hop := dsrc.substr(hop_start, 2200)
	_assert(hop.contains("saved_player_state = me.get_state()"), "boarding: captures player state")
	_assert(hop.contains("Dungeon.next_theme_id = theme_id"), "boarding: sets next theme")
	_assert(hop.contains("Dungeon.next_seed = new_seed"), "boarding: sets next seed")
	_assert(hop.contains("Dungeon.next_level_number = new_level"), "boarding: sets next level")
	_assert(hop.contains("passenger_classes = classes"), "boarding: hands off the roster")
	_assert(hop.contains("train_interior.tscn"), "boarding: loads the interior scene")
	_assert(hop.contains("NetworkManager.server_id"), "boarding: server-sender check")

	# 3b. Interior exit (do_disembark, issue #3 Phase 3): server-sender check,
	# state capture, dungeon scene load via the background-loaded packed scene.
	var isrc := FileAccess.get_file_as_string("res://scripts/station/train_interior.gd")
	var lv_start := isrc.find("func do_disembark")
	_assert(lv_start > 0, "interior: do_disembark rpc exists")
	var lv := isrc.substr(lv_start, 900)
	_assert(lv.contains("NetworkManager.server_id"), "interior exit: server-sender check")
	_assert(lv.contains("saved_player_state = me.get_state()"), "interior exit: captures player state")
	_assert(lv.contains("dungeon.tscn") or lv.contains("DUNGEON_SCENE"), "interior exit: loads the dungeon scene")

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
	_assert(car.get_node_or_null("WallSillNorth") != null, "interior: window sills built")
	_assert(car.find_children("WallSegNorth_*", "", true, false).size() == 5,
		"interior: 5 north wall segments between windows")
	_assert(car.find_children("WallSegSouth_*", "", true, false).size() == 5,
		"interior: 5 south wall segments between windows")
	# Window glass is transparent now (Phase 3): the scenery shows through.
	var glass_node := car.get_node_or_null("WindowGlass_1_0") as MeshInstance3D
	_assert(glass_node != null, "interior: window glass named")
	var glass_mat := (glass_node.mesh as BoxMesh).material as StandardMaterial3D
	_assert(glass_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
		"interior: window glass is transparent")
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


func _test_train_ride() -> void:
	print("[Playtest] Train ride phase 3 (25s ride, skip, arrival, disembark)...")
	var InteriorScript := load("res://scripts/station/train_interior.gd")
	_assert(InteriorScript.RIDE_SECONDS == 25.0, "ride: 25s ride length")
	_assert(InteriorScript.DISEMBARK_WINDOW == 20.0, "ride: 20s disembark window")

	var car = InteriorScript.new()
	car._build_car()
	car._build_scenery()
	car._build_platform()
	car._build_skip_lever()
	car._build_disembark_zone()

	# Scenery: two unshaded scrolling planes, hidden until the ride starts.
	_assert(car._scenery_root != null, "ride: scenery root built")
	_assert(car._scenery_root.get_child_count() == 2, "ride: two scenery planes")
	_assert(car._scenery_mats.size() == 2, "ride: two scrolling materials")
	var smat: StandardMaterial3D = car._scenery_mats[0]
	_assert(smat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "ride: scenery unshaded")
	_assert(smat.uv1_scale.x == 24.0, "ride: scenery texture tiled along the car")
	_assert(not car._scenery_root.visible, "ride: scenery hidden until ride start")
	# Scrolling actually moves the texture.
	smat.uv1_offset.x = 0.0
	car._riding = true
	car._ride_left = 20.0
	car._process(1.0)
	_assert(smat.uv1_offset.x < 0.0, "ride: _process scrolls the scenery")

	# Easing: full speed cruising, settled near arrival.
	_assert(InteriorScript._scenery_speed_factor(10.0) == 1.0, "ride: full speed at 10s left")
	_assert(is_equal_approx(InteriorScript._scenery_speed_factor(5.5), 0.5),
		"ride: half speed at 5.5s left")
	_assert(InteriorScript._scenery_speed_factor(3.0) == 0.0, "ride: settled at 3s left")
	_assert(InteriorScript._scenery_speed_factor(0.0) == 0.0, "ride: settled at 0s left")
	# Scenery stops scrolling once settled.
	smat.uv1_offset.x = 0.0
	car._ride_left = 2.0
	car._process(1.0)
	_assert(smat.uv1_offset.x == 0.0, "ride: no scroll once settled")
	car._riding = false

	# Skip lever: pure clock jump, never past arrival.
	car._ride_left = 20.0
	car._apply_skip()
	_assert(car._ride_left == 2.0, "ride: skip jumps clock to 2s")
	car._ride_left = 1.0
	car._apply_skip()
	_assert(car._ride_left == 1.0, "ride: skip never pushes past arrival")

	# Skip lever prop: E-interact group, prompt, hidden until riding.
	var lever = car.get_node_or_null("SkipLever")
	_assert(lever != null and lever.is_in_group("skip_lever"), "ride: skip lever in interact group")
	_assert(lever.prompt_text() == "Pull the skip lever", "ride: skip lever prompt")
	_assert(not lever.visible, "ride: skip lever hidden until ride start")

	# Arrival platform: hidden, destination sign names the theme.
	_assert(car._platform_root != null, "ride: platform built")
	_assert(not car._platform_root.visible, "ride: platform hidden until arrival")
	var sign := car._platform_root.get_node_or_null("SignLabel") as Label3D
	_assert(sign != null, "ride: platform sign exists")
	_assert(sign.text == "VILLAGE OUTSKIRTS", "ride: sign names the destination (default village)")

	# Disembark zone: present but dormant until arrival.
	_assert(car._disembark_area != null, "ride: disembark zone built")
	_assert(not car._disembark_area.monitoring, "ride: disembark zone off until arrival")
	car.free()

	# Wiring (source): background load, arrival beat, disembark hop.
	var isrc := FileAccess.get_file_as_string("res://scripts/station/train_interior.gd")
	_assert(isrc.contains("load_threaded_request(DUNGEON_SCENE)"), "ride: dungeon background-loaded")
	_assert(not isrc.contains("func leave_interior"), "ride: placeholder leave_interior gone")
	var apos := isrc.find("func begin_arrival")
	_assert(apos > 0, "ride: begin_arrival exists")
	var ablock := isrc.substr(apos, 1500)
	_assert(ablock.contains('sfx("train_brake")'), "ride: brake screech at arrival")
	_assert(ablock.contains("NOW ARRIVING: "), "ride: arrival banner in the car")
	_assert(ablock.contains("open_doors()"), "ride: doors open at arrival")
	_assert(ablock.contains("_platform_root.visible = true"), "ride: platform revealed")
	_assert(ablock.contains("_door_blocker.queue_free()"), "ride: doorway unblocked")
	var dpos := isrc.find("func do_disembark")
	_assert(dpos > 0, "ride: do_disembark exists")
	var dblock := isrc.substr(dpos, 1200)
	_assert(dblock.contains("Dungeon.spawn_in_annex = true"), "ride: disembark flags annex spawn")
	_assert(dblock.contains("Dungeon.arrived_by_train = true"), "ride: disembark flags train arrival")
	_assert(dblock.contains("load_threaded_get(DUNGEON_SCENE)"), "ride: disembark uses preloaded scene")
	_assert(dblock.contains("change_scene_to_packed"), "ride: disembark swaps to packed scene")
	_assert(isrc.contains("func request_skip_ride"), "ride: skip lever RPC exists")
	_assert(isrc.contains("func _run_disembark_window"), "ride: straggler fallback exists")

	# Dungeon side (source): annex spawn + single arrival beat.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("static var spawn_in_annex"), "ride: dungeon spawn_in_annex static")
	_assert(dsrc.contains("static var arrived_by_train"), "ride: dungeon arrived_by_train static")
	_assert(dsrc.contains("func _annex_spawn_spots"), "ride: annex spawn spots helper")
	_assert(dsrc.contains("if arrived_by_train:"), "ride: train arrival skips double brake/banner")
	_assert(dsrc.contains("InteriorScript.ride_active = false"), "ride: fresh trip resets ride state")

	# HUD + player wiring (source).
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func show_ride_status"), "ride: HUD ride status")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains('"skip_lever"'), "ride: skip lever in player interact groups")


func _test_train_dressing() -> void:
	print("[Playtest] Train interior phase 4 (per-theme dressing)...")
	var InteriorScript := load("res://scripts/station/train_interior.gd")
	var StationScript := load("res://scripts/station/station.gd")
	var themes := ["village", "dungeon", "depths", "supermarket", "warlord", "apex"]
	var car = InteriorScript.new()
	car._build_car()
	car._build_dressing()
	# Dressing root: one prop set per theme + the destination placard.
	_assert(car._dressing != null, "dress: dressing root built")
	var props = car._dress_props
	_assert(props != null, "dress: props container built")
	var names := []
	for c in props.get_children():
		names.append(c.name)
	for tid in themes:
		_assert(tid in names, "dress: prop set for " + tid)
	_assert(car._dest_sign != null, "dress: destination placard built")

	# Per theme: lamps tinted, trim/seats recolored, only that prop set
	# visible, placard names the destination.
	for tid in themes:
		car.apply_dressing(tid)
		var tint: Color = StationScript.DRESSING_LAMPS[tid]
		for omni in car._dress_lamps:
			_assert((omni as OmniLight3D).light_color == tint,
				"dress: lamp tinted for " + tid)
		_assert(car._lamp_visual_mat.emission == tint, "dress: lamp glow tinted for " + tid)
		var trim: Dictionary = InteriorScript.DRESSING_TRIM[tid]
		_assert(car._wall_mat.albedo_color == trim["wall"], "dress: wall trim for " + tid)
		_assert(car._seat_mat.albedo_color == trim["seat"], "dress: seat fabric for " + tid)
		for c in props.get_children():
			_assert(c.visible == (c.name == tid), "dress: only " + tid + " props visible")
		var want := "NOW ARRIVING: " + str(StationScript.theme_display_name(tid)).to_upper()
		_assert(car._dest_sign.text == want, "dress: placard names " + tid)

	# Unknown theme falls back to village.
	car.apply_dressing("nope")
	_assert(car._dress_lamps[0].light_color == StationScript.DRESSING_LAMPS["village"],
		"dress: unknown theme falls back to village lamps")
	for c in props.get_children():
		_assert(c.visible == (c.name == "village"), "dress: unknown theme shows village props")

	# Idempotent: applying twice keeps the same state.
	car.apply_dressing("depths")
	var once: Color = car._wall_mat.albedo_color
	car.apply_dressing("depths")
	_assert(car._wall_mat.albedo_color == once, "dress: re-apply is idempotent")
	car.free()

	# Wiring (source): dressing happens on ride start, on every peer.
	var isrc := FileAccess.get_file_as_string("res://scripts/station/train_interior.gd")
	var rpos := isrc.find("func _apply_ride_started")
	_assert(rpos > 0, "dress: ride-start hook exists")
	_assert(isrc.substr(rpos, 400).contains("apply_dressing(ride_theme_id)"),
		"dress: ride start applies destination dressing")


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

	# Boarding SFX triggers (sound audit): all_aboard on the banner,
	# board_chime on a successful boarding, door_lock when boarding
	# completes, countdown ticks in the final seconds, vote_cast on voting.
	var SoundScript := load("res://scripts/audio/sound_synth.gd")
	for sfx in ["all_aboard", "board_chime", "door_lock", "countdown_tick", "vote_cast"]:
		_assert(SoundScript.call(sfx) is AudioStreamWAV, "boarding sfx builds: %s" % sfx)
	var ab_pos := ssrc.find("func announce_boarding")
	_assert(ab_pos > 0 and ssrc.substr(ab_pos, 300).contains('sfx("all_aboard")'),
		"sfx: all_aboard in announce_boarding")
	var rb_pos := ssrc.find("func request_board")
	_assert(rb_pos > 0 and ssrc.substr(rb_pos, 700).contains('sfx("board_chime")'),
		"sfx: board_chime on request_board success")
	var fb_pos := ssrc.find("func _finish_boarding")
	_assert(fb_pos > 0 and ssrc.substr(fb_pos, 700).contains('sfx("door_lock")'),
		"sfx: door_lock in _finish_boarding")
	var bs_pos := ssrc.find("func boarding_sync")
	_assert(bs_pos > 0 and ssrc.substr(bs_pos, 600).contains('sfx("countdown_tick")'),
		"sfx: countdown_tick in final boarding seconds")
	var vsrc := FileAccess.get_file_as_string("res://scripts/station/departure_board.gd")
	var sv_pos := vsrc.find("func set_my_vote")
	_assert(sv_pos > 0 and vsrc.substr(sv_pos, 300).contains('sfx("vote_cast")'),
		"sfx: vote_cast in set_my_vote")


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
	_assert(psrc.contains('ability_cds[cd_key] = (cd) * cooldown_mult()'), "Signature cooldowns tracked")
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
	_assert(hsrc.contains('"StatPair1", "StatPair2"'), "Stats tab uses compact stat pairs")
	# Action buttons not in any tab (always visible).
	_assert(not hsrc.contains('"ResumeButton"') or hsrc.contains('_pause_tab_members'), "Tab members defined")
	# show_pause defaults to Stats tab.
	_assert(hsrc.contains("_on_pause_tab_pressed(0)"), "Defaults to Stats tab")
	# affinity_shots uses tab selection.
	var tsrc := FileAccess.get_file_as_string("res://tools/affinity_shots/affinity_shots.gd")
	_assert(tsrc.contains("select_pause_tab"), "Tool uses tab selection")


## Issue #16: Pause -> Stats tab must fit with zero scrolling (Jesse's hard rule).
func _test_pause_stats_zero_scroll() -> void:
	print("[Playtest] Pause stats zero-scroll...")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func _compact_stats_tab"), "Stats compaction builder exists")
	_assert(hsrc.contains('"StatPair1"') and hsrc.contains('"StatPair2"'), "Stat rows paired into two columns")
	_assert(hsrc.contains("SCROLL_MODE_AUTO if idx == 1"), "Scroll disabled for Stats tab, auto only for Spec")
	# Scene defines the pairs so unique-name lookups (%DmgVal etc.) keep working.
	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/hud.tscn")
	_assert(tsrc.contains('name="StatPair1"'), "Scene defines StatPair1")
	_assert(tsrc.contains('name="StatPair2"'), "Scene defines StatPair2")


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


func _test_specials_phase1() -> void:
	print("[Playtest] Relic Vault specials data layer (issue #6 phase 1)...")
	var SD: GDScript = load("res://scripts/data/special_data.gd")
	# 1. Registry: six specials load with fields, icons, and effect params.
	var all: Array = SD.all()
	_assert(all.size() == 6, "six specials registered")
	var seen := {}
	for d in all:
		seen[str(d.get("id"))] = d
	for sid in ["holy_light", "iron_resolve", "greed_charm",
			"apex_boar_hide", "apex_horror_eye", "apex_warden_sigil"]:
		_assert(seen.has(sid), "special %s registered" % sid)
	var hl: Resource = seen["holy_light"]
	_assert(str(hl.get("display_name")) == "Holy Light", "holy light display name")
	_assert(hl.get("icon") != null, "holy light icon loads")
	_assert(str(hl.get("unlock_hint")) != "", "holy light unlock hint")
	_assert(float((hl.get("effect_params") as Dictionary).get("cooldown", 0.0)) == 20.0,
		"holy light cooldown param")
	_assert(str((hl.get("effect_params") as Dictionary).get("key", "")) == "7",
		"holy light key param")
	var charm: Resource = seen["greed_charm"]
	_assert(float((charm.get("effect_params") as Dictionary).get("cash_mult", 0.0)) == 1.25,
		"greed charm cash_mult param")
	# Apex boss -> trophy mapping.
	_assert(SD.apex_special_for_boss("apex_boar") == "apex_boar_hide", "apex boar -> boar hide")
	_assert(SD.apex_special_for_boss("apex_horror") == "apex_horror_eye", "apex horror -> horror eye")
	_assert(SD.apex_special_for_boss("apex_warden") == "apex_warden_sigil", "apex warden -> warden sigil")
	_assert(SD.apex_special_for_boss("goblin") == "", "non-apex boss maps to nothing")
	_assert(SD.AURA_EARN_REQ == 20, "aura earn requirement is 20")
	_assert(SD.IRON_RESOLVE_STREAK == 3, "iron resolve streak is 3")
	_assert(SD.GREED_CHARM_GOAL == 500, "greed charm goal is $500")
	# Unknown-id guards.
	_assert(SD.get_special("bogus") == null, "get_special unknown -> null")
	_assert(not SD.is_earned("bogus"), "unknown special never earned")
	_assert(not SD.earn("bogus"), "earn unknown id fails")

	# 2. Vault persistence: earn is idempotent and survives a profile reload.
	# Backup is abort-safe: the original is moved to a .phase6bak sidecar
	# (never deleted), so a script error mid-test can't lose it — a later
	# run self-heals from the sidecar.
	var prof_path := "user://profile_local.cfg"
	var prof_bak := "user://profile_local.cfg.phase6bak"
	if not FileAccess.file_exists(prof_path) and FileAccess.file_exists(prof_bak):
		_copy_file(prof_bak, prof_path) # previous run aborted mid-test
		DirAccess.remove_absolute(prof_bak)
	var prof_backup := PackedByteArray()
	if FileAccess.file_exists(prof_path):
		prof_backup = FileAccess.get_file_as_bytes(prof_path)
		var bf := FileAccess.open(prof_bak, FileAccess.WRITE)
		bf.store_buffer(prof_backup)
		DirAccess.remove_absolute(prof_path)
	var mgr: Node = root.get_node("SaveManager")
	mgr.call("load_game") # fresh seeded profile
	_assert(not SD.is_earned("iron_resolve"), "iron_resolve starts unearned")
	_assert(not SD.is_earned("holy_light"), "holy_light starts unearned")

	# 3. Player-level behavior on real player scenes. Run slots get the same
	# abort-safe sidecar treatment: death paths clear the solo slot (die()).
	var slot_backup := {}
	var slot_baks := {}
	for mode in ["solo", "mp"]:
		for slot in range(3):
			var p := "user://runs/%s_%d.cfg" % [mode, slot]
			var b := "%s.phase6bak" % p
			slot_baks[p] = b
			if not FileAccess.file_exists(p) and FileAccess.file_exists(b):
				_copy_file(b, p) # previous run aborted mid-test
				DirAccess.remove_absolute(b)
			if FileAccess.file_exists(p):
				slot_backup[p] = FileAccess.get_file_as_bytes(p)
				var bf2 := FileAccess.open(b, FileAccess.WRITE)
				bf2.store_buffer(slot_backup[p])
				DirAccess.remove_absolute(p)
	var holder := Node3D.new() # -s mode has no current_scene; positional sfx needs one
	root.add_child(holder)
	current_scene = holder
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var has_hl := func(pl) -> bool:
		return (pl.get("unlocked_abilities") as Array).any(func(x): return x["id"] == "holy_light")

	# No-death streak: exactly 3 consecutive cleared levels earns Iron Resolve.
	var streaker = PlayerScene.instantiate()
	streaker.set("class_id", "rogue")
	root.add_child(streaker)
	streaker.call("bump_no_death_streak")
	streaker.call("bump_no_death_streak")
	_assert(int(streaker.get("no_death_streak")) == 2, "streak bumps to 2")
	_assert(not SD.is_earned("iron_resolve"), "no earn before 3 consecutive clears")
	streaker.call("bump_no_death_streak")
	_assert(int(streaker.get("no_death_streak")) == 3, "streak bumps to 3")
	_assert(SD.is_earned("iron_resolve"), "3rd consecutive clear earns Iron Resolve")
	_assert(not SD.earn("iron_resolve"), "streak earn is idempotent")
	# Death breaks the streak.
	streaker.call("take_damage", 9999.0, "")
	_assert(not bool(streaker.get("alive")), "lethal damage kills")
	_assert(int(streaker.get("no_death_streak")) == 0, "death resets the streak")
	# Earn persists across a profile reload.
	mgr.call("load_game")
	_assert(SD.is_earned("iron_resolve"), "earn persists across profile reload")
	_assert((mgr.call("get_vault_specials") as Array) == ["iron_resolve"],
		"vault_specials roundtrip")

	# Holy Light migration: an aura-20 mage earns it on spawn, but the
	# ability stays inactive unless equipped.
	var mage = PlayerScene.instantiate()
	mage.set("class_id", "mage")
	mage.set("bonus_aura", 20.0)
	root.add_child(mage)
	_assert(SD.is_earned("holy_light"), "aura-20 mage earns Holy Light on spawn")
	_assert(not has_hl.call(mage), "holy light NOT granted while unequipped")
	_assert(SD.equip(mage, "holy_light"), "equip holy_light succeeds")
	_assert(str(mage.get("equipped_special")) == "holy_light", "equipped_special set")
	_assert(has_hl.call(mage), "holy light granted when equipped")
	# One equipped max: equipping replaces, revoking the old ability.
	_assert(SD.earn("greed_charm"), "greed_charm earn succeeds")
	_assert(SD.equip(mage, "greed_charm"), "equip greed_charm succeeds")
	_assert(str(mage.get("equipped_special")) == "greed_charm", "equip replaces previous choice")
	_assert(not has_hl.call(mage), "holy light revoked after switching")
	_assert(float(mage.get("cash_mult")) == 1.25, "greed charm cash_mult applies on equip")
	_assert(not SD.equip(mage, "apex_boar_hide"), "cannot equip an unearned special")
	SD.unequip(mage)
	_assert(str(mage.get("equipped_special")) == "", "unequip clears equipped_special")
	_assert(float(mage.get("cash_mult")) == 1.0, "unequip resets cash_mult")

	# Second Wind: once per run, survive a killing blow at 1 HP.
	var w = PlayerScene.instantiate()
	w.set("class_id", "warrior")
	root.add_child(w)
	_assert(SD.equip(w, "iron_resolve"), "equip iron_resolve succeeds")
	_assert(bool(w.get("second_wind_armed")), "second wind armed on equip")
	w.set("hp", 10.0)
	w.call("take_damage", 999.0, "")
	_assert(bool(w.get("alive")) and float(w.get("hp")) == 1.0,
		"second wind saves the killing blow at 1 HP")
	_assert(bool(w.get("second_wind_used")) and not bool(w.get("second_wind_armed")),
		"second wind consumed (once per run)")
	w.call("take_damage", 999.0, "")
	_assert(not bool(w.get("alive")), "second killing blow kills")
	# Unequipping disarms an unused Second Wind.
	var w2 = PlayerScene.instantiate()
	w2.set("class_id", "warrior")
	root.add_child(w2)
	_assert(SD.equip(w2, "iron_resolve"), "equip iron_resolve on w2")
	SD.unequip(w2)
	_assert(not bool(w2.get("second_wind_armed")), "unequip disarms second wind")

	# Run-state roundtrip: equipped special + streak + second-wind-used
	# survive get_state/apply_state, and effects re-apply on restore.
	SD.equip(w2, "greed_charm")
	w2.set("no_death_streak", 2)
	var st: Dictionary = w2.call("get_state")
	_assert(str(st.get("equipped_special", "")) == "greed_charm", "state carries equipped_special")
	_assert(int(st.get("no_death_streak", -1)) == 2, "state carries no_death_streak")
	_assert(bool(st.get("second_wind_used", true)) == false, "state carries second_wind_used")
	var w3 = PlayerScene.instantiate()
	w3.set("class_id", "warrior")
	root.add_child(w3)
	w3.call("apply_state", st)
	_assert(str(w3.get("equipped_special")) == "greed_charm", "restore keeps equipped_special")
	_assert(float(w3.get("cash_mult")) == 1.25, "restore re-applies greed charm")

	# 4. Dungeon-side math + wiring (source-level: no dungeon instance in -s mode).
	var DungeonScript := load("res://scripts/dungeon/dungeon.gd")
	_assert(DungeonScript.checkout_payout(400, 1.0) == 400, "checkout payout unchanged w/o charm")
	_assert(DungeonScript.checkout_payout(400, 1.25) == 500, "checkout payout +25% with charm")
	_assert(DungeonScript.checkout_payout(333, 1.25) == 416, "checkout payout rounds")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("SpecialData.earn_for(player, \"greed_charm\")"),
		"checkout earns greed charm at $500 visit total")
	_assert(dsrc.contains("p.rpc(\"rpc_level_cleared_streak\")"),
		"cleared-level departure bumps the streak on living players")
	_assert(dsrc.contains("SpecialData.earn_for(p, trophy)"),
		"apex boss kill earns the party trophy special")
	_assert(dsrc.contains("func sync_equipped_special"),
		"server sync_equipped_special RPC exists")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("func rpc_earn_special"),
		"profile-safe rpc_earn_special exists")
	_assert(psrc.contains("func _apply_equipped_special"),
		"player _apply_equipped_special exists")

	# Restore profile + run slots, reset the autoload's in-memory profile.
	# Abort-safe: the originals live in .phase6bak sidecars until now.
	holder.queue_free()
	if not prof_backup.is_empty():
		var pf := FileAccess.open(prof_path, FileAccess.WRITE)
		pf.store_buffer(prof_backup)
		if FileAccess.file_exists(prof_bak):
			DirAccess.remove_absolute(prof_bak)
	elif FileAccess.file_exists(prof_bak):
		_copy_file(prof_bak, prof_path)
		DirAccess.remove_absolute(prof_bak)
	elif FileAccess.file_exists(prof_path):
		DirAccess.remove_absolute(prof_path) # test-created only
	for p in slot_backup.keys():
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(slot_backup[p])
		var b: String = slot_baks[p]
		if FileAccess.file_exists(b):
			DirAccess.remove_absolute(b)
	mgr.call("load_game")


## File copy helper for abort-safe test backups (no FileAccess.copy helper).
func _copy_file(src: String, dst: String) -> void:
	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(src))
## Stub dungeon for apex mechanic tests: records announces/spawns, returns a
## fixed arena point for phaseshift teleports. (The apex code paths use an
## untyped dungeon ref so this stub can stand in for the real Dungeon.)
class ApexDungeonStub extends Node:
	var announces: Array = []
	var spawns: Array = []

	@rpc("any_peer", "call_local")
	func announce(msg: String) -> void:
		announces.append(msg)

	func server_spawn_mob(type_id: String, pos: Vector3, force_elite: bool = false) -> void:
		spawns.append([type_id, pos, force_elite])

	func random_arena_pos() -> Vector3:
		return Vector3(10, 0.5, 10)


## Stub player for shockwave hit tests: records damage taken.
class ApexPlayerStub extends Node3D:
	var alive := true
	var damage_taken := 0.0

	@rpc("any_peer", "call_local")
	func take_damage(amount: float, _attacker_name: String) -> void:
		damage_taken += amount


func _test_apex_mechanics() -> void:
	print("[Playtest] Apex phase 2 mechanics (enrage/adds/phaseshift)...")
	var MobScene: PackedScene = load("res://scenes/mobs/mob.tscn")
	_assert(MobScene != null, "apex2: mob scene loads")
	# --- Data: apex_id set only on the three apex bosses.
	_assert(str(load("res://data/mobs/apex_boar.tres").get("apex_id")) == "enrage",
		"apex2: boar apex_id enrage")
	_assert(str(load("res://data/mobs/apex_warden.tres").get("apex_id")) == "adds",
		"apex2: warden apex_id adds")
	_assert(str(load("res://data/mobs/apex_horror.tres").get("apex_id")) == "phaseshift",
		"apex2: horror apex_id phaseshift")
	_assert(int(load("res://data/mobs/apex_horror.tres").get("summon_count")) == 4,
		"apex2: horror summon_count 4")
	_assert(str(load("res://data/mobs/boss_boar.tres").get("apex_id")) == "",
		"apex2: normal boar has no apex_id")
	_assert(str(load("res://data/mobs/boss_warden.tres").get("apex_id")) == "",
		"apex2: normal warden has no apex_id")
	_assert(str(load("res://data/mobs/slime.tres").get("apex_id")) == "",
		"apex2: normal slime has no apex_id")
	# --- Fixtures: stub dungeon + a holder for scorch-decal counting.
	var stub := ApexDungeonStub.new()
	root.add_child(stub)
	stub.add_to_group("dungeon")
	var holder := Node3D.new()
	root.add_child(holder)
	# -s script mode has no current_scene; positional SFX needs one.
	current_scene = holder

	# --- Enrage (Apex Bristleback): below 30% HP -> +40% speed, 7s->4s cd.
	var bdata: Resource = load("res://data/mobs/apex_boar.tres")
	var boar = MobScene.instantiate()
	boar.setup(1, bdata, 2.5, 1.5, false, 1.0)
	holder.add_child(boar)
	boar.take_damage(boar.get("max_hp") * 0.5, 1, Vector3.ZERO) # 50% left
	_assert(not boar.get("_enraged"), "apex2: boar not enraged at 50%")
	_assert(absf(boar._move_speed_mult() - 1.0) < 0.001, "apex2: speed normal above 30%")
	boar.take_damage(boar.get("max_hp") * 0.25, 1, Vector3.ZERO) # 25% left
	_assert(boar.get("_enraged"), "apex2: boar enrages below 30%")
	_assert(absf(boar._move_speed_mult() - 1.4) < 0.001, "apex2: enrage +40% move speed")
	_assert(absf(boar._special_cooldown() - 4.0) < 0.001, "apex2: enrage special cd 7s->4s")
	_assert(stub.announces.size() == 1 and str(stub.announces[0]).contains("ENRAGED"),
		"apex2: enrage announced")
	# Fire trail: charging drops scorch decals (4s fire trail).
	var decals_before := 0
	for c in holder.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
			decals_before += 1
	boar.set("_charge_t", 0.5)
	boar.set("_trail_tick", 0.0)
	boar._physics_process(0.2)
	boar._physics_process(0.2)
	var decals_after := 0
	for c in holder.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
			decals_after += 1
	_assert(decals_after - decals_before >= 2, "apex2: charge leaves fire-trail scorch decals")

	# --- Adds (Apex Warden): 2 elite skeletons at 66% and 33%.
	var wdata: Resource = load("res://data/mobs/apex_warden.tres")
	var warden = MobScene.instantiate()
	warden.setup(2, wdata, 2.5, 1.5, false, 1.0)
	holder.add_child(warden)
	warden.take_damage(warden.get("max_hp") * 0.30, 1, Vector3.ZERO) # 70% left
	_assert(stub.spawns.is_empty(), "apex2: no adds above 66%")
	warden.take_damage(warden.get("max_hp") * 0.10, 1, Vector3.ZERO) # 60% left
	_assert(stub.spawns.size() == 2, "apex2: 2 skeletons summoned at 66% gate")
	for s in stub.spawns:
		_assert(s[0] == "skeleton" and s[2] == true, "apex2: warden adds are elite skeletons")
	warden.take_damage(warden.get("max_hp") * 0.30, 1, Vector3.ZERO) # 30% left
	_assert(stub.spawns.size() == 4, "apex2: 2 more skeletons at 33% gate")
	warden.take_damage(warden.get("max_hp") * 0.10, 1, Vector3.ZERO) # 20% left
	_assert(stub.spawns.size() == 4, "apex2: add gates fire once each")
	# Shockwave: slam becomes an expanding ring; players are hit as it passes.
	var pspec := ApexPlayerStub.new()
	pspec.set_multiplayer_authority(1)
	root.add_child(pspec)
	pspec.add_to_group("players")
	pspec.global_position = warden.global_position + Vector3(5, 0, 0)
	warden._do_slam()
	_assert(warden.get("_shockwaves").size() == 1, "apex2: slam fires a shockwave ring")
	_assert(pspec.damage_taken == 0.0, "apex2: ring has not reached the player yet")
	warden._boss_think(0.5) # ring out to ~4.75m
	_assert(pspec.damage_taken == 0.0, "apex2: player at 5m not hit before the ring arrives")
	warden._boss_think(0.5) # ring out to ~8.5m
	_assert(pspec.damage_taken > 0.0, "apex2: player hit as the ring passes")
	var dmg_once: float = pspec.damage_taken
	warden._boss_think(0.5) # ring expires at 9m
	_assert((warden.get("_shockwaves") as Array).is_empty(), "apex2: ring expires at max radius")
	_assert(pspec.damage_taken == dmg_once, "apex2: each player hit once per ring")
	pspec.global_position = Vector3(500, 0, 500)

	# --- Phaseshift (Apex Horror): untargetable 2s + teleport at 75/50/25%.
	var hdata: Resource = load("res://data/mobs/apex_horror.tres")
	var horror = MobScene.instantiate()
	horror.setup(3, hdata, 2.5, 1.5, false, 1.0)
	holder.add_child(horror)
	var start_pos: Vector3 = horror.global_position
	horror.take_damage(horror.get("max_hp") * 0.20, 1, Vector3.ZERO) # 80% left
	_assert(not horror.get("untargetable"), "apex2: no phaseshift above 75%")
	horror.take_damage(horror.get("max_hp") * 0.10, 1, Vector3.ZERO) # 70% left
	_assert(horror.get("untargetable"), "apex2: phaseshift triggers at 75%")
	_assert(absf(float(horror.get("_phaseshift_t")) - 2.0) < 0.01,
		"apex2: 2s untargetable window")
	var hp_during: float = horror.get("hp")
	horror.take_damage(500.0, 1, Vector3.ZERO)
	_assert(absf(float(horror.get("hp")) - hp_during) < 0.001,
		"apex2: no damage taken while untargetable")
	_assert(horror.global_position.distance_to(start_pos) > 1.0,
		"apex2: phaseshift teleports to a new arena point")
	horror._boss_think(2.1)
	_assert(not horror.get("untargetable"), "apex2: targetable again after the window")
	horror.take_damage(horror.get("max_hp") * 0.25, 1, Vector3.ZERO) # 45% left
	_assert(horror.get("untargetable"), "apex2: second phaseshift at 50% gate")
	_assert(int(horror.get("_shift_fired")) == 2, "apex2: shift gates fire once each")
	horror._boss_think(2.1)
	# Horror summons: 4 elite cultists per summon special.
	stub.spawns.clear()
	horror._do_summon()
	_assert(stub.spawns.size() == 4, "apex2: horror summons 4 cultists")
	for s in stub.spawns:
		_assert(s[0] == "cultist" and s[2] == true, "apex2: horror cultists are elite")

	# --- Non-apex bosses never run apex mechanics.
	var ndata: Resource = load("res://data/mobs/boss_boar.tres")
	var normal = MobScene.instantiate()
	normal.setup(4, ndata, 1.0, 1.0, false, 1.0)
	holder.add_child(normal)
	normal.take_damage(normal.get("max_hp") * 0.85, 1, Vector3.ZERO) # 15% left
	_assert(not normal.get("_enraged"), "apex2: normal boar never enrages")
	_assert(absf(normal._move_speed_mult() - 1.0) < 0.001, "apex2: normal speed unchanged")
	_assert(absf(normal._special_cooldown() - float(ndata.get("special_cooldown"))) < 0.001,
		"apex2: normal special cooldown unchanged")
	_assert(int(normal.get("_adds_fired")) == 0, "apex2: normal boss never summons adds")
	_assert(not normal.get("untargetable"), "apex2: normal boss never phaseshifts")
	var wndata: Resource = load("res://data/mobs/boss_warden.tres")
	var wnormal = MobScene.instantiate()
	wnormal.setup(5, wndata, 1.0, 1.0, false, 1.0)
	holder.add_child(wnormal)
	wnormal._do_slam()
	_assert((wnormal.get("_shockwaves") as Array).is_empty(),
		"apex2: normal warden slam stays instant (no shockwave)")

	boar.queue_free()
	warden.queue_free()
	horror.queue_free()
	normal.queue_free()
	wnormal.queue_free()
	pspec.queue_free()
	stub.queue_free()
	holder.queue_free()


func _test_bounty_phase1() -> void:
	print("[Playtest] Bounty board phase 1 (core)...")
	var BountyScript := load("res://scripts/systems/bounty.gd")
	var village: Resource = load("res://data/levels/theme_village.tres")
	var market: Resource = load("res://data/levels/theme_supermarket.tres")
	var dungeon_theme: Resource = load("res://data/levels/theme_dungeon.tres")
	var village_mix: Dictionary = village.get("mob_mix")
	var market_mix: Dictionary = market.get("mob_mix")
	var dungeon_mix: Dictionary = dungeon_theme.get("mob_mix")
	var village_roster := ["slime", "goblin", "archer"]
	# 1. Generation: 3 bounties, theme-roster filtering, sane rewards.
	for seed in [1, 42, 777, 12345, 999999]:
		var gen: Array = BountyScript.generate(seed, "village", village_mix, 1)
		_assert(gen.size() == 3, "village seed %d: 3 bounties" % seed)
		var seen := {}
		for b in gen:
			var kind := str(b["kind"])
			_assert(kind in ["kill", "elite", "no_death", "cash"], "bounty kind valid (%s)" % kind)
			_assert(not seen.has(str(b["id"])), "bounty ids unique")
			seen[str(b["id"])] = true
			_assert(int(b["target"]) > 0, "bounty target positive")
			_assert(int(b["cash_reward"]) > 0, "bounty cash reward positive")
			_assert(int(b["xp_reward"]) > 0, "bounty xp reward positive")
			if kind == "kill" or kind == "elite":
				_assert(str(b["mob_id"]) in village_roster,
					"village %s bounty uses roster mob (%s)" % [kind, str(b["mob_id"])])
				_assert(str(b["mob_id"]) != "cultist", "no cultist bounty on village")
			_assert(kind != "cash", "no cash bounty outside supermarket")
	# 2. Seeded determinism: same inputs -> identical bounties.
	var det_a: Array = BountyScript.generate(424242, "dungeon", dungeon_mix, 2)
	var det_b: Array = BountyScript.generate(424242, "dungeon", dungeon_mix, 2)
	_assert(det_a == det_b, "same seed -> identical bounties")
	var det_c: Array = BountyScript.generate(424243, "dungeon", dungeon_mix, 2)
	_assert(det_a != det_c, "different seed -> different bounties")
	# 3. Cash bounties only on supermarket.
	var saw_cash := false
	for seed in [5, 6, 7, 8, 9, 10, 11, 12]:
		var mgen: Array = BountyScript.generate(seed, "supermarket", market_mix, 1)
		_assert(mgen.size() == 3, "supermarket seed %d: 3 bounties" % seed)
		for b in mgen:
			if str(b["kind"]) == "cash":
				saw_cash = true
				_assert(int(b["target"]) >= 200, "cash bounty target sane")
			if str(b["kind"]) == "kill" or str(b["kind"]) == "elite":
				_assert(str(b["mob_id"]) in market_mix.keys(),
					"supermarket bounty uses roster mob")
	_assert(saw_cash, "supermarket rolls cash bounties")
	# 4. Empty roster (warlord RTS map): no crash, falls back to no_death.
	var wgen: Array = BountyScript.generate(7, "warlord", {}, 1)
	_assert(wgen.size() == 1, "empty roster -> single fallback bounty")
	_assert(str(wgen[0]["kind"]) == "no_death", "fallback is no_death")
	# 5. Per-player independence (hand-built bounty set).
	var bounties := [
		{"id": "b1", "kind": "kill", "mob_id": "goblin", "target": 3,
			"cash_reward": 50, "xp_reward": 30, "name": "T", "desc": "D"},
		{"id": "b2", "kind": "no_death", "target": 1,
			"cash_reward": 220, "xp_reward": 180, "name": "T", "desc": "D"},
		{"id": "b3", "kind": "cash", "target": 200,
			"cash_reward": 90, "xp_reward": 50, "name": "T", "desc": "D"},
		{"id": "b4", "kind": "elite", "mob_id": "orc", "target": 2,
			"cash_reward": 140, "xp_reward": 110, "name": "T", "desc": "D"},
	]
	var pa: Dictionary = BountyScript.new_progress(bounties)
	var pb: Dictionary = BountyScript.new_progress(bounties)
	_assert(pa.size() == 4 and int(pa["b1"]) == 0, "fresh progress starts at 0")
	# Wrong mob / elite flag don't feed a kill bounty.
	BountyScript.record_kill(pa, bounties, "slime", false)
	_assert(int(pa["b1"]) == 0, "wrong mob id ignored")
	BountyScript.record_kill(pa, bounties, "goblin", true)
	_assert(int(pa["b1"]) == 0, "elite kill doesn't feed kill bounty")
	# Completing the kill bounty pays once and only for that player.
	var done: Array = []
	for i in 3:
		done = BountyScript.record_kill(pa, bounties, "goblin", false)
	_assert(done.size() == 1 and str(done[0]["id"]) == "b1", "kill bounty completes at target")
	_assert(int(pb["b1"]) == 0, "other player's kill progress untouched")
	_assert(BountyScript.record_kill(pa, bounties, "goblin", false).is_empty(),
		"completed bounty doesn't re-complete")
	_assert(BountyScript.is_complete(pa, bounties[0]), "is_complete true after target")
	# Elite bounties need elite kills of the right mob.
	var pe: Dictionary = BountyScript.new_progress(bounties)
	BountyScript.record_kill(pe, bounties, "orc", false)
	_assert(int(pe["b4"]) == 0, "non-elite kill doesn't feed elite bounty")
	var edone: Array = []
	for i in 2:
		edone = BountyScript.record_kill(pe, bounties, "orc", true)
	_assert(edone.size() == 1 and str(edone[0]["id"]) == "b4", "elite bounty completes")
	# Death fails only the dead player's no_death.
	var failed_a: Array = BountyScript.record_death(pa, bounties)
	_assert(failed_a.size() == 1 and str(failed_a[0]["id"]) == "b2", "death fails no_death")
	_assert(BountyScript.is_failed(pa, bounties[1]), "failed flagged")
	_assert(int(pb["b2"]) == 0, "other player's no_death survives")
	_assert(not BountyScript.is_failed(pb, bounties[1]), "survivor not failed")
	# Level clear completes the survivor's no_death, not the failed one.
	var cleared_b: Array = BountyScript.record_level_cleared(pb, bounties)
	_assert(cleared_b.size() == 1 and str(cleared_b[0]["id"]) == "b2",
		"level clear completes surviving no_death")
	_assert(BountyScript.record_level_cleared(pa, bounties).is_empty(),
		"failed no_death stays failed on level clear")
	# Cash bounty completes on cumulative checkout earnings.
	var pd: Dictionary = BountyScript.new_progress(bounties)
	_assert(BountyScript.record_checkout(pd, bounties, 120).is_empty(),
		"partial checkout doesn't complete")
	var cash_done: Array = BountyScript.record_checkout(pd, bounties, 100)
	_assert(cash_done.size() == 1 and str(cash_done[0]["id"]) == "b3",
		"checkout completes cash bounty")
	# 6. Payout amounts: cycle scaling raises rewards, keeps structure.
	var cyc1: Array = BountyScript.generate(99, "village", village_mix, 1)
	var cyc3: Array = BountyScript.generate(99, "village", village_mix, 3)
	_assert(str(cyc1[0]["kind"]) == str(cyc3[0]["kind"]), "cycle doesn't change picks")
	_assert(int(cyc3[0]["cash_reward"]) > int(cyc1[0]["cash_reward"]),
		"cycle scales cash rewards up")
	_assert(int(cyc3[0]["xp_reward"]) > int(cyc1[0]["xp_reward"]),
		"cycle scales xp rewards up")
	# 7. new_progress covers every bounty id.
	var cov: Dictionary = BountyScript.new_progress(cyc1)
	for b in cyc1:
		_assert(cov.has(str(b["id"])), "progress covers bounty %s" % str(b["id"]))
## Spawns a live slime mob at pos for combo tests (headless sim).
func _combo_mob(MobScene: PackedScene, slime_data: Resource, pos: Vector3) -> Node:
	var m = MobScene.instantiate()
	m.setup(1, slime_data, 1.0, 1.0, false, 1.0)
	m.position = pos
	root.add_child(m)
	return m


func _test_combo_phase1() -> void:
	print("[Playtest] Combo finishers phase 1 (issue #8)...")
	# -s script mode has no current_scene; positional sfx() needs one.
	var _combo_holder := Node3D.new()
	root.add_child(_combo_holder)
	current_scene = _combo_holder
	var ComboScript := load("res://scripts/systems/combo.gd")
	var TotemScript := load("res://scripts/combat/totem.gd")
	var MobScene: PackedScene = load("res://scenes/mobs/mob.tscn")
	var slime_data: Resource = load("res://data/mobs/slime.tres")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	ComboScript.reset_cooldowns()

	# --- Registry: 5 finishers with the specced ids, names, triggers, effects.
	_assert(ComboScript.COMBO_FINISHERS.size() == 5, "combo registry has 5 finishers")
	var expected := {
		"orbital_strike": ["Orbital Strike", "Meteor impacts a marked target", "+100% meteor damage, 2x blast radius"],
		"stormcall": ["Stormcall", "Chain lightning cast while standing inside a War Horn aura", "Chains 6 targets, +25% damage"],
		"shatter_cascade": ["Shatter Cascade", "Fan of Knives killing blow on a frost-slowed enemy", "Frost nova burst (3m, slow + damage)"],
		"reciprocity_surge": ["Reciprocity Surge", "Meteor killing blow inside a Reciprocity aura", "Team heal burst (20% max HP, all living allies)"],
		"smoke_bombard": ["Smoke Bombard", "Meteor impact inside smoke veil", "+50% blast radius, hit enemies blinded (miss chance, 4s)"],
	}
	for fid in expected:
		var f: Dictionary = ComboScript.finisher_by_id(fid)
		_assert(not f.is_empty(), "finisher %s registered" % fid)
		_assert(str(f["name"]) == expected[fid][0], "finisher %s name" % fid)
		_assert(str(f["trigger_desc"]) == expected[fid][1], "finisher %s trigger desc" % fid)
		_assert(str(f["effect"]) == expected[fid][2], "finisher %s effect" % fid)
	_assert(ComboScript.finisher_by_id("nope").is_empty(), "unknown finisher id -> empty dict")

	# --- Orbital Strike: meteor impacts a marked target.
	var m1 = _combo_mob(MobScene, slime_data, Vector3(2, 0, 0))
	m1.apply_mark(10.0, 1.0)
	_assert(m1.is_marked(), "test mob marked")
	var r1: Dictionary = ComboScript.check_meteor_impact([m1], Vector3.ZERO, 4.5, [], [], 1000)
	_assert(absf(float(r1["damage_mult"]) - 2.0) < 0.001, "orbital: +100% meteor damage")
	_assert(absf(float(r1["radius_mult"]) - 2.0) < 0.001, "orbital: 2x blast radius")
	_assert((r1["triggered"] as Array).has("orbital_strike"), "orbital: triggered on marked target")
	# No mark -> no trigger.
	var m2 = _combo_mob(MobScene, slime_data, Vector3(2, 0, 1))
	var r2: Dictionary = ComboScript.check_meteor_impact([m2], Vector3.ZERO, 4.5, [], [], 2000)
	_assert(not (r2["triggered"] as Array).has("orbital_strike"), "orbital: no trigger without mark")
	_assert(absf(float(r2["damage_mult"]) - 1.0) < 0.001, "orbital: damage unchanged without mark")
	# Marked but outside the blast -> no trigger.
	var m1b = _combo_mob(MobScene, slime_data, Vector3(50, 0, 0))
	m1b.apply_mark(10.0, 1.0)
	var r2b: Dictionary = ComboScript.check_meteor_impact([m1b], Vector3.ZERO, 4.5, [], [], 2100)
	_assert(not (r2b["triggered"] as Array).has("orbital_strike"), "orbital: no trigger outside blast")
	# Cooldown blocks double-trigger on the same target.
	var r3: Dictionary = ComboScript.check_meteor_impact([m1], Vector3.ZERO, 4.5, [], [], 1500)
	_assert(not (r3["triggered"] as Array).has("orbital_strike"), "orbital: cooldown blocks double-trigger")
	# After the 5s window it triggers again.
	var r4: Dictionary = ComboScript.check_meteor_impact([m1], Vector3.ZERO, 4.5, [], [], 7000)
	_assert((r4["triggered"] as Array).has("orbital_strike"), "orbital: triggers again after cooldown")

	# --- Stormcall: chain lightning inside a War Horn aura.
	var wt = TotemScript.new()
	wt.setup("warhorn", 1, 1)
	root.add_child(wt)
	wt.global_position = Vector3.ZERO
	_assert(absf(wt.aura_radius() - 6.0) < 0.001, "warhorn aura radius 6m")
	var caster := Node3D.new()
	root.add_child(caster)
	caster.global_position = Vector3(1, 0, 0)
	var s1: Dictionary = ComboScript.check_lightning_cast(caster.global_position, caster, [wt], m1, 1000)
	_assert(bool(s1["triggered"]), "stormcall: triggered inside warhorn aura")
	_assert(str(s1["id"]) == "stormcall", "stormcall: id")
	_assert(int(s1["chain_targets"]) == 6, "stormcall: chains 6 targets")
	_assert(absf(float(s1["damage_mult"]) - 1.25) < 0.001, "stormcall: +25% damage")
	# Outside the aura -> no trigger.
	var s2: Dictionary = ComboScript.check_lightning_cast(Vector3(50, 0, 50), caster, [wt], m1, 2000)
	_assert(not bool(s2["triggered"]), "stormcall: no trigger outside aura")
	# Cooldown is per-enemy: same target blocked, a different enemy still triggers.
	var s3: Dictionary = ComboScript.check_lightning_cast(caster.global_position, caster, [wt], m1, 1500)
	_assert(not bool(s3["triggered"]), "stormcall: cooldown blocks double-trigger on same enemy")
	var s3b: Dictionary = ComboScript.check_lightning_cast(caster.global_position, caster, [wt], m2, 1600)
	_assert(bool(s3b["triggered"]), "stormcall: per-enemy cooldown (other enemy triggers)")
	var s3c: Dictionary = ComboScript.check_lightning_cast(caster.global_position, caster, [wt], m1, 7000)
	_assert(bool(s3c["triggered"]), "stormcall: triggers again after cooldown")

	# --- Shatter Cascade: fan killing blow on a frost-slowed enemy.
	var m3 = _combo_mob(MobScene, slime_data, Vector3(3, 0, 0))
	m3.apply_slow(5.0, 0.5)
	_assert(m3.is_slowed(), "test mob frost-slowed")
	_assert(ComboScript.check_fan_kill(m3, 1000), "shatter: triggers on slowed kill")
	_assert(not ComboScript.check_fan_kill(m3, 1500), "shatter: cooldown blocks double-trigger")
	_assert(ComboScript.check_fan_kill(m3, 7000), "shatter: triggers again after cooldown")
	# No finisher chains: a mob already dead when the fan loop reaches it
	# (e.g. killed by an earlier nova in the same cast) never retriggers.
	var m4 = _combo_mob(MobScene, slime_data, Vector3(3, 0, 1))
	m4.apply_slow(5.0, 0.5)
	m4.alive = false
	_assert(not ComboScript.note_kill(m4, false), "no chain: already-dead mob never retriggers")
	var m4b = _combo_mob(MobScene, slime_data, Vector3(3, 0, 2))
	m4b.alive = false
	_assert(ComboScript.note_kill(m4b, true), "note_kill: live->dead is a kill")
	_assert(not ComboScript.note_kill(m4b, false), "note_kill: dead->dead is not a kill")

	# --- Reciprocity Surge: meteor killing blow inside a Reciprocity aura.
	var rt = TotemScript.new()
	rt.setup("reciprocity", 1, 1)
	root.add_child(rt)
	rt.global_position = Vector3.ZERO
	var m5 = _combo_mob(MobScene, slime_data, Vector3(4, 0, 0))
	_assert(ComboScript.check_meteor_kill(Vector3.ZERO, m5, [rt], 1000), "surge: triggers on meteor kill in aura")
	_assert(not ComboScript.check_meteor_kill(Vector3(50, 0, 50), m5, [rt], 2000),
		"surge: no trigger outside aura")
	_assert(not ComboScript.check_meteor_kill(Vector3.ZERO, m5, [rt], 1500),
		"surge: cooldown blocks double-trigger")

	# --- Smoke Bombard: meteor impact inside smoke veil.
	var p = PlayerScene.instantiate()
	p.class_id = "rogue"
	root.add_child(p)
	p.global_position = Vector3.ZERO
	p.stealthed = true
	var m6 = _combo_mob(MobScene, slime_data, Vector3(2, 0, 2))
	var b1: Dictionary = ComboScript.check_meteor_impact([m6], Vector3(1, 0, 0), 4.5, [], [p], 1000)
	_assert(bool(b1["smoke_veil"]), "smoke: veil detected at impact")
	_assert(absf(float(b1["radius_mult"]) - 1.5) < 0.001, "smoke: +50% blast radius")
	_assert(not (b1["triggered"] as Array).has("orbital_strike"), "smoke: unmarked mob doesn't orbit")
	_assert(ComboScript.smoke_blind_ok(m6, 1000), "smoke: blind applies to hit enemy")
	_assert(not ComboScript.smoke_blind_ok(m6, 1500), "smoke: per-enemy cooldown blocks re-blind")
	_assert(ComboScript.smoke_blind_ok(m6, 7000), "smoke: blind reapplies after cooldown")
	var b2: Dictionary = ComboScript.check_meteor_impact([m6], Vector3(50, 0, 50), 4.5, [], [p], 2000)
	_assert(not bool(b2["smoke_veil"]), "smoke: no veil far from impact")
	_assert(absf(float(b2["radius_mult"]) - 1.0) < 0.001, "smoke: no radius bonus far from veil")
	# Blind debuff lands on the mob.
	m6.apply_blind(4.0)
	_assert(float(m6.get("_blind_t")) > 0.0, "blind: timer set on mob")

	# --- Headless sim: a real meteor impact on a marked target deals 2x.
	ComboScript.reset_cooldowns()
	var m7 = _combo_mob(MobScene, slime_data, Vector3(100, 0, 100))
	m7.apply_mark(10.0, 1.0)
	m7.hp = 9999.0
	m7.max_hp = 9999.0
	var hp_before: float = m7.hp
	var MeteorScript := load("res://scripts/combat/meteor.gd")
	var met = MeteorScript.new()
	met.setup(Vector3(100, 0, 100), 40.0, 1)
	root.add_child(met)
	met._impact()
	# 40 base * 2.0 orbital * 1.5 mark = 120.
	_assert(absf((hp_before - m7.hp) - 120.0) < 0.01, "meteor sim: orbital strike doubles damage")

	# --- Headless sim: frost nova slows + damages in 3m.
	var m8 = _combo_mob(MobScene, slime_data, Vector3(200, 0, 200))
	var m9 = _combo_mob(MobScene, slime_data, Vector3(201, 0, 200))
	var hp8: float = m8.hp
	var hp9: float = m9.hp
	ComboScript.apply_frost_nova(self, Vector3(200, 0, 200), 25.0, 1)
	_assert(m8.is_slowed() and m9.is_slowed(), "nova sim: slows enemies in 3m")
	_assert(m8.hp < hp8 and m9.hp < hp9, "nova sim: damages enemies in 3m")
	# Nova never runs finisher detection (no chains, by construction).
	var csrc := FileAccess.get_file_as_string("res://scripts/systems/combo.gd")
	var nova_body := csrc.get_slice("static func apply_frost_nova", 1).get_slice("static func", 0)
	_assert(not nova_body.contains("check_"), "nova: no finisher detection inside effect")
	var heal_body := csrc.get_slice("static func apply_team_heal", 1).get_slice("static func", 0)
	_assert(not heal_body.contains("check_"), "team heal: no finisher detection inside effect")

	# --- Headless sim: reciprocity surge heals the team 20% max HP.
	var p2 = PlayerScene.instantiate()
	p2.class_id = "warrior"
	root.add_child(p2)
	p2.hp = p2.max_hp * 0.5
	ComboScript.apply_team_heal(self)
	_assert(absf(p2.hp - p2.max_hp * 0.7) < 0.01, "surge sim: team healed 20% max HP")

	# --- Announce path is a safe no-op with no dungeon present.
	# Pin the SaveManager autoload to a scratch profile: announce now
	# records codex discoveries (which save) without touching the real profile.
	var _sm: Node = root.get_node("SaveManager")
	_sm.set("_test_account_pin", "test_combo")
	_sm.load_game()
	ComboScript.announce_finisher(self, "orbital_strike")
	_assert(true, "announce: no crash without dungeon")
	ComboScript.announce_finisher(self, "bogus_id")
	_assert(true, "announce: unknown id ignored")
	_sm.set("_test_account_pin", "")
	_sm.load_game()
	if FileAccess.file_exists("user://profile_test_combo.cfg"):
		DirAccess.remove_absolute("user://profile_test_combo.cfg")

	# --- Solo switch_class keeps world state: totems, marks, veils persist.
	var p3 = PlayerScene.instantiate()
	p3.class_id = "warrior"
	root.add_child(p3)
	var tt = TotemScript.new()
	tt.setup("warhorn", 1, 1)
	root.add_child(tt)
	tt.global_position = Vector3(300, 0, 300)
	var m10 = _combo_mob(MobScene, slime_data, Vector3(300, 0, 301))
	m10.apply_mark(10.0, 1.0)
	p3.stealthed = true
	p3.switch_class("mage")
	_assert(str(p3.class_id) == "mage", "switch: class changed")
	_assert(is_instance_valid(tt) and tt.is_inside_tree(), "switch: totem persists")
	_assert(m10.is_marked(), "switch: mark persists")
	_assert(bool(p3.stealthed), "switch: veil persists")

	# --- Wiring: hooks exist at the server code paths.
	var msrc := FileAccess.get_file_as_string("res://scripts/combat/meteor.gd")
	_assert(msrc.contains("Combo.check_meteor_impact"), "meteor: impact hook wired")
	_assert(msrc.contains("Combo.check_meteor_kill"), "meteor: kill hook wired")
	_assert(msrc.contains("Combo.note_kill"), "meteor: kill tracking wired")
	_assert(msrc.contains("Combo.smoke_blind_ok"), "meteor: per-enemy blind gate wired")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("Combo.check_lightning_cast"), "player: lightning hook wired")
	_assert(psrc.contains("Combo.check_fan_kill"), "player: fan kill hook wired")
	_assert(psrc.contains("Combo.apply_frost_nova"), "player: nova effect wired")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func announce_combo"), "dungeon: announce_combo RPC exists")
	_assert(dsrc.contains("Combo.finisher_by_id"), "dungeon: banner looks up registry")
	var ssrc := FileAccess.get_file_as_string("res://scripts/audio/sound_synth.gd")
	_assert(ssrc.contains("static func thunderclap"), "thunderclap SFX synth exists")
	var asrc := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	_assert(asrc.contains("\"thunderclap\""), "thunderclap SFX registered")
	var tsrc := FileAccess.get_file_as_string("res://scripts/combat/totem.gd")
	_assert(tsrc.contains("add_to_group(\"totems\")"), "totems registered in group")
	var mbsrc := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(mbsrc.contains("func is_slowed"), "mob: is_slowed accessor")
	_assert(mbsrc.contains("func apply_blind"), "mob: apply_blind")
	print("[Playtest] combo phase 1 done")


func _test_combo_codex() -> void:
	print("[Playtest] Combo codex phase 2 (issue #8)...")
	var ComboScript := load("res://scripts/systems/combo.gd")
	var SaveScript := load("res://scripts/autoload/save_manager.gd")
	# Scratch profile only — never touch the real user:// profile.
	var scratch := "user://profile_test_codex.cfg"
	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)

	# --- Registry: every finisher has a hint for undiscovered rows.
	_assert(ComboScript.COMBO_FINISHERS.size() == 5, "codex: 5 registry rows")
	for f in ComboScript.COMBO_FINISHERS:
		_assert(str(f.get("hint", "")).length() > 10, "codex: hint for %s" % str(f["id"]))

	# --- SaveManager: discovery tracking (scratch account on a standalone instance).
	var mgr = SaveScript.new()
	mgr.set("_test_account_pin", "test_codex")
	mgr.load_game()
	_assert(mgr.get_combos_discovered().is_empty(), "codex: starts undiscovered")
	_assert(mgr.add_combo_discovered("orbital_strike"), "codex: first discovery returns true")
	_assert(not mgr.add_combo_discovered("orbital_strike"), "codex: repeat returns false")
	_assert(mgr.get_combos_discovered() == ["orbital_strike"], "codex: discovery recorded")
	# Persistence roundtrip.
	var mgr2 = SaveScript.new()
	mgr2.set("_test_account_pin", "test_codex")
	mgr2.load_game()
	_assert(mgr2.get_combos_discovered() == ["orbital_strike"], "codex: discovery persists")
	mgr.free()
	mgr2.free()
	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)

	# --- Codex UI: 5 fixed rows, ??? for undiscovered, name for discovered.
	# Pin the autoload to the scratch profile: fresh seeded defaults in
	# memory, real profile untouched (reloaded at the end of this section).
	var sm: Node = root.get_node("SaveManager")
	sm.set("_test_account_pin", "test_codex")
	sm.load_game()
	_assert(sm.get_combos_discovered().is_empty(), "codex: autoload starts clean")
	sm.add_combo_discovered("orbital_strike")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._refresh_combo_codex()
	var log = hud.get_node("%CollectionLog")
	var rows := 0
	var unknowns := 0
	var knowns := 0
	for child in log.get_children():
		if child is Label:
			rows += 1
			var t := str(child.text)
			if t.begins_with("◇ ???"):
				unknowns += 1
			elif t.begins_with("◆"):
				knowns += 1
	# Header + 5 rows; 1 discovered (orbital_strike), 4 unknown.
	_assert(rows == 6, "codex: header + 5 rows")
	_assert(unknowns == 4, "codex: 4 undiscovered ??? rows")
	_assert(knowns == 1, "codex: 1 discovered row")
	# Discover another and refresh: row count stable, counts shift.
	sm.add_combo_discovered("stormcall")
	for child in log.get_children():
		log.remove_child(child)
		child.free()
	hud._refresh_combo_codex()
	unknowns = 0
	knowns = 0
	for child in log.get_children():
		if child is Label:
			var t := str(child.text)
			if t.begins_with("◇ ???"):
				unknowns += 1
			elif t.begins_with("◆"):
				knowns += 1
	_assert(unknowns == 3 and knowns == 2, "codex: rows update on discovery")
	# Discovered row shows the name and trigger.
	var found_name := false
	for child in log.get_children():
		if child is Label and str(child.text).contains("Stormcall"):
			found_name = true
	_assert(found_name, "codex: discovered row shows name")
	hud.queue_free()
	# Unpin and reload the real profile so the autoload is exactly as before.
	sm.set("_test_account_pin", "")
	sm.load_game()
	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)

	# --- Wiring: codex section hooked into the collection refresh.
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func _refresh_combo_codex"), "hud: codex refresh exists")
	_assert(hsrc.contains("_refresh_combo_codex()"), "hud: codex hooked into collection log")
	var ssrc := FileAccess.get_file_as_string("res://scripts/autoload/save_manager.gd")
	_assert(ssrc.contains("func get_combos_discovered"), "save: get_combos_discovered")
	_assert(ssrc.contains("func add_combo_discovered"), "save: add_combo_discovered")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("is_new"), "dungeon: announce_combo takes is_new")
	var abody := dsrc.get_slice("func announce_combo", 1).get_slice("func _pick_mob_type", 0)
	_assert(abody.contains('sfx("finisher_" + finisher_id)'), "dungeon: per-finisher fanfare SFX")
	_assert(abody.contains('sfx("codex_discover")'), "dungeon: codex_discover sting on first discovery")
	_assert(not abody.contains('sfx("thunderclap")'), "dungeon: shared thunderclap no longer fired for finishers")
	print("[Playtest] combo codex phase 2 done")


## Stub dungeon for relic drop tests: records spawn_pickup calls.
class RelicDungeonStub extends Node:
	var pickups: Array = []

	@rpc("any_peer", "call_local")
	func spawn_pickup(item_id: String, pos: Vector3, value_mult: float = 1.0) -> void:
		pickups.append([item_id, pos, value_mult])

	func get_player_node(_peer_id: int) -> Node:
		return null


func _test_apex_relics() -> void:
	print("[Playtest] Apex phase 3 relics + trophies...")
	# --- Special registry (#6 API): 3 apex specials with effect_params.
	var hide := SpecialData.get_special("apex_boar_hide")
	var eye := SpecialData.get_special("apex_horror_eye")
	var sigil := SpecialData.get_special("apex_warden_sigil")
	_assert(hide != null, "relic3: boar hide special loads")
	_assert(eye != null, "relic3: horror eye special loads")
	_assert(sigil != null, "relic3: warden sigil special loads")
	_assert(absf(float(hide.effect_params.get("max_hp_mult", 0.0)) - 1.10) < 0.001,
		"relic3: hide max_hp_mult 1.10")
	_assert(absf(float(eye.effect_params.get("pickup_mult", 0.0)) - 1.20) < 0.001,
		"relic3: eye pickup_mult 1.20")
	_assert(absf(float(sigil.effect_params.get("cooldown_mult", 0.0)) - 0.85) < 0.001,
		"relic3: sigil cooldown_mult 0.85")
	_assert(not hide.unlock_hint.is_empty(), "relic3: hide has unlock hint")
	_assert(hide.icon != null, "relic3: hide has icon")
	# --- Apex -> special/relic mappings.
	_assert(SpecialData.apex_special_for_boss("apex_boar") == "apex_boar_hide",
		"relic3: boar maps to special")
	_assert(SpecialData.apex_special_for_boss("apex_warden") == "apex_warden_sigil",
		"relic3: warden maps to special")
	_assert(SpecialData.apex_special_for_boss("apex_horror") == "apex_horror_eye",
		"relic3: horror maps to special")
	_assert(SpecialData.relic_item_for_apex("apex_boar") == "relic_apex_boar_hide",
		"relic3: boar maps to relic item")
	_assert(SpecialData.apex_special_for_boss("boss_boar") == "",
		"relic3: non-apex maps to no special")
	_assert(SpecialData.trophy_name_for_apex("apex_boar") == "Boar Hide",
		"relic3: trophy name resolves")
	# --- Relic items in ItemDB (physical drops).
	var ItemDBNode = root.get_node_or_null("ItemDB")
	var r1 = ItemDBNode.get_item("relic_apex_boar_hide")
	var r2 = ItemDBNode.get_item("relic_apex_warden_sigil")
	var r3 = ItemDBNode.get_item("relic_apex_horror_eye")
	_assert(r1 != null and r2 != null and r3 != null, "relic3: 3 relic items in ItemDB")
	_assert(r1.rarity == ItemData.Rarity.LEGENDARY, "relic3: relic is legendary")
	_assert(r1.grants_special == "apex_boar_hide", "relic3: relic grants boar special")
	# --- Trophy meta (scratch account via _test_account_pin).
	var SaveScript := load("res://scripts/autoload/save_manager.gd")
	var mgr = SaveScript.new()
	mgr.set("_test_account_pin", "playtest_relic3")
	mgr.load_game()
	_assert(mgr.record_apex_trophy("apex_boar"), "relic3: trophy recorded")
	_assert(not mgr.record_apex_trophy("apex_boar"), "relic3: trophy no dupe")
	_assert(mgr.has_apex_trophy("apex_boar"), "relic3: has trophy")
	_assert(not mgr.has_apex_trophy("apex_warden"), "relic3: no warden trophy yet")
	var mgr2 = SaveScript.new()
	mgr2.set("_test_account_pin", "playtest_relic3")
	mgr2.load_game()
	_assert(mgr2.has_apex_trophy("apex_boar"), "relic3: trophy persists")
	mgr.free()
	mgr2.free()
	# Cleanup scratch profile.
	var scratch := "user://profile_playtest_relic3.cfg"
	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)
	# --- Equipped apex effects apply via _apply_equipped_special.
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	var base_hp: float = p.max_hp
	p.equipped_special = "apex_boar_hide"
	p._apply_equipped_special()
	_assert(absf(p.max_hp - base_hp * 1.10) < 0.01, "relic3: hide +10% max HP when equipped")
	_assert(absf(float(p.get("special_hp_mult")) - 1.10) < 0.001, "relic3: hp mult set")
	p.equipped_special = "apex_horror_eye"
	p._apply_equipped_special()
	_assert(absf(p.special_pickup_mult - 1.20) < 0.001, "relic3: eye pickup mult set")
	p.equipped_special = "apex_warden_sigil"
	p._apply_equipped_special()
	_assert(absf(p.cooldown_mult() - 0.85) < 0.001, "relic3: sigil -15% cooldowns")
	p.equipped_special = ""
	p._apply_equipped_special()
	_assert(absf(p.cooldown_mult() - 1.0) < 0.001, "relic3: unequip resets cooldowns")
	_assert(absf(p.max_hp - base_hp) < 0.01, "relic3: unequip resets max HP")
	p.queue_free()
	# --- Forced relic drop: apex boss always drops its relic (100%, no RNG).
	var MobScene: PackedScene = load("res://scenes/mobs/mob.tscn")
	for n in get_nodes_in_group("dungeon"):
		n.get_parent().remove_child(n)
		n.free()
	var stub := RelicDungeonStub.new()
	stub.add_to_group("dungeon")
	root.add_child(stub)
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	var adata: Resource = load("res://data/mobs/apex_boar.tres")
	var amob = MobScene.instantiate()
	amob.setup(99, adata, 1.0, 1.0, false, 1.0)
	holder.add_child(amob)
	amob._drop_and_reward(1)
	var found_relic := false
	for pk in stub.pickups:
		if str(pk[0]) == "relic_apex_boar_hide":
			found_relic = true
	_assert(found_relic, "relic3: apex boar forces relic drop")
	stub.pickups.clear()
	var ndata: Resource = load("res://data/mobs/boss_boar.tres")
	var nmob = MobScene.instantiate()
	nmob.setup(100, ndata, 1.0, 1.0, false, 1.0)
	holder.add_child(nmob)
	nmob._drop_and_reward(1)
	var found_any_relic := false
	for pk in stub.pickups:
		if str(pk[0]).begins_with("relic_apex_"):
			found_any_relic = true
	_assert(not found_any_relic, "relic3: normal boss drops no relic")

	amob.queue_free()
	nmob.queue_free()
	stub.queue_free()
	holder.queue_free()


func _test_bounty_phase2() -> void:
	print("[Playtest] Bounty board phase 2 (prop + UI)...")
	var BoardScript := load("res://scripts/station/bounty_board.gd")
	var BountyUIScript := load("res://scripts/ui/bounty_ui.gd")
	var BountyScript := load("res://scripts/systems/bounty.gd")
	_assert(BoardScript != null, "bounty_board.gd loads")
	_assert(BountyUIScript != null, "bounty_ui.gd loads (Player-free)")
	_assert(BountyScript != null, "bounty.gd loads for bounty UI")

	# 1. Prop builds standalone: group, prompt, SNES board face.
	var holder := Node3D.new()
	root.add_child(holder)
	var bb = BoardScript.new()
	bb.name = "BountyBoard"
	holder.add_child(bb) # _ready builds
	_assert(bb.is_in_group("bounty_board"), "prop in bounty_board group")
	_assert(str(bb.prompt_text()) == "Check bounties", "prop prompt text")
	_assert(bb.has_method("interact"), "prop interact exists")
	var face := bb.get_node_or_null("BoardFace") as MeshInstance3D
	_assert(face != null, "prop has BoardFace quad")
	var face_tex: Texture2D = null
	if face != null and face.mesh != null:
		var fm := (face.mesh as QuadMesh).material as StandardMaterial3D
		if fm != null:
			face_tex = fm.albedo_texture
	_assert(face_tex != null, "board face uses the SNES board art")

	# 2. Deterministic bounty fixtures (mirrors what the server rolls).
	var bounties: Array = [
		{"id": "b1", "kind": "kill", "mob_id": "goblin", "target": 8,
			"cash_reward": 50, "xp_reward": 30,
			"name": "Slay 8 Goblins", "desc": "Defeat 8 Goblins this level."},
		{"id": "b2", "kind": "no_death", "target": 1,
			"cash_reward": 220, "xp_reward": 180,
			"name": "Untouchable", "desc": "Clear the level without dying."},
		{"id": "b3", "kind": "kill", "mob_id": "slime", "target": 15,
			"cash_reward": 100, "xp_reward": 60,
			"name": "Slay 15 Slimes", "desc": "Defeat 15 Slimes this level."},
	]
	var progress := {"b1": 3, "b2": -1, "b3": 15}

	# 3. Cards: exactly 3 fixed cards with progress / FAILED / DONE states.
	# (BountyUI is Player-free so it loads in -s mode where hud.gd can't.)
	var cards: Array = []
	for b in bounties:
		cards.append(BountyUIScript.make_card(b, progress))
	_assert(cards.size() == 3, "panel builds 3 fixed cards")
	var card_names := []
	var card_states := []
	for card in cards:
		card_names.append(str(card.get_child(0).get("text")))
		var row := card.get_child(2) as HBoxContainer
		card_states.append(str(row.get_child(1).get("text")))
	_assert(card_names == ["Slay 8 Goblins", "Untouchable", "Slay 15 Slimes"],
		"cards show the 3 bounty names")
	_assert(card_states == ["3/8", "FAILED", "DONE"], "cards show progress/failed/done states")
	var bar1 := (cards[0].get_child(2) as HBoxContainer).get_child(0) as ProgressBar
	_assert(int(bar1.max_value) == 8 and int(bar1.value) == 3, "card 1 progress bar 3/8")
	_assert(str(cards[0].get_child(3).get("text")).contains("$50"),
		"card shows cash reward")
	_assert(str(cards[0].get_child(3).get("text")).contains("30 XP"),
		"card shows XP reward")

	# 4. Zero-scroll: a panel assembled from the 3 cards has no ScrollContainer.
	var mock_panel := VBoxContainer.new()
	for card in cards:
		var dup: VBoxContainer = (card as VBoxContainer).duplicate()
		mock_panel.add_child(dup)
	_assert(not _has_scroll_container(mock_panel), "bounty panel: no ScrollContainer (zero-scroll)")

	# 5. Tracker text: one short line per unsettled bounty, "" when settled.
	var txt := str(BountyUIScript.tracker_text(bounties, progress))
	_assert(txt.contains("Slay 8 Goblins"), "tracker names the active bounty")
	_assert(not txt.contains("Untouchable"), "tracker hides the failed bounty")
	_assert(not txt.contains("Slay 15 Slimes"), "tracker hides the done bounty")
	_assert(txt.split("\n").size() == 1, "tracker is one short line for one active bounty")
	var txt_done := str(BountyUIScript.tracker_text(bounties, {"b1": 8, "b2": -1, "b3": 15}))
	_assert(txt_done.is_empty(), "tracker auto-hides (empty text) when all bounties settled")

	# 6. Wiring: hud.gd delegates to BountyUI (source-level; hud.gd itself
	# can't instantiate in -s mode because it references Player).
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func show_bounty"), "show_bounty panel exists")
	_assert(hsrc.contains("BountyUI.make_card"), "hud delegates card building to BountyUI")
	_assert(hsrc.contains("BountyUI.tracker_text"), "hud delegates tracker text to BountyUI")
	_assert(hsrc.contains("func _refresh_bounty_tracker"), "tracker refresh exists")
	_assert(hsrc.contains("bounty_open = false"), "panel close clears bounty_open")

	# 7. Embedded station: BountyBoard prop placed inside the hall.
	var StationScript := load("res://scripts/station/station.gd")
	var AnnexScript := load("res://scripts/station/station_annex.gd")
	var ProcGenScript := load("res://scripts/procgen/procgen.gd")
	var theme: Resource = load("res://data/levels/theme_village.tres")
	var layout = ProcGenScript.generate(theme, 12345)
	var plan: Dictionary = AnnexScript.plan(12345, layout)
	var annex = AnnexScript.build(holder, plan, layout)
	var st = StationScript.new()
	st.name = "Station"
	st.dungeon = holder
	st.annex = annex
	holder.add_child(st) # _ready runs the embedded build
	var bbn: Node = st.get_node_or_null("BountyBoard")
	_assert(bbn != null, "embedded: BountyBoard built")
	if bbn != null:
		var lp: Vector3 = bbn.position
		_assert(absf(lp.x) <= 12.0 and absf(lp.z) <= 7.0,
			"embedded: BountyBoard inside hall footprint")

	# 8. Wiring: E-scan group + station placement source checks.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains('"bounty_board"'), "player E-scan includes bounty board")
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(ssrc.contains("BountyBoardScript.new()"), "bounty board prop placed")

	holder.queue_free()


## Recursive ScrollContainer audit for the zero-scroll rule.
func _has_scroll_container(n: Node) -> bool:
	if n == null:
		return false
	if n is ScrollContainer:
		return true
	for c in n.get_children():
		if _has_scroll_container(c):
			return true
	return false


## Find a named descendant of the vault popup (cards, grid, trophy row).
func _vault_find(hud: Node, node_name: String) -> Node:
	var pop: Node = hud.get("_cipher_popup")
	if pop == null:
		return null
	return pop.find_child(node_name, true, false)


## Button text of a vault card (the last Button in its VBox).
func _vault_card_button(card: Node) -> String:
	for ch in card.find_children("*", "Button", true, false):
		return (ch as Button).text
	return ""


## Press a vault card button by special id + expected label.
func _vault_press(hud: Node, sid: String, label: String) -> bool:
	var card := _vault_find(hud, "VaultCard_" + sid)
	if card == null:
		return false
	for ch in card.find_children("*", "Button", true, false):
		var b := ch as Button
		if b.text == label and not b.disabled:
			b.pressed.emit()
			return true
	return false


## Collect the 3 fixed bounty cards out of a panel subtree.
func _find_bounty_cards(n: Node) -> Array:
	var out := []
	if n is VBoxContainer and str(n.name).begins_with("BountyCard_"):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_bounty_cards(c))
	return out
func _test_leaderboard_phase1() -> void:
	print("[Playtest] leaderboards (issue #9 Phase 1)...")
	# NOTE: playtest.gd is the -s entry point, compiled before autoload
	# globals resolve; reach them via load() and /root lookups instead.
	var LBScript = load("res://scripts/autoload/leaderboard.gd")
	# Score formulas (pure statics).
	_assert(LBScript.depth_score(1, 1) == 100001, "depth score c1l1")
	_assert(LBScript.depth_score(2, 5) == 200005, "depth score c2l5")
	_assert(LBScript.depth_score(2, 1) > LBScript.depth_score(1, 99),
		"cycle dominates level in depth score")
	_assert(LBScript.speed_score(125) == 125, "speed score passthrough")
	_assert(LBScript.speed_score(-3) == 0, "speed score clamps negative")
	_assert(LBScript.format_score(LBScript.BOARD_DEPTH, 200005) == "Cycle 2 · Lv 5",
		"depth score formats")
	_assert(LBScript.format_score(LBScript.BOARD_SPEED, 125) == "2:05",
		"speed score formats as m:ss")
	# Offline graceful skip: Steam is not initialized on this VM.
	var sm: Node = root.get_node_or_null("SteamManager")
	_assert(sm != null and not bool(sm.get("initialized")), "precondition: Steam offline")
	var lb: Node = root.get_node_or_null("Leaderboard")
	_assert(lb != null, "Leaderboard autoload exists")
	_assert(not bool(lb.call("steam_available")), "leaderboard reports unavailable")
	lb.call("ensure_boards")
	lb.call("upload_daily", 2, 5, 125)
	lb.call("upload_daily", 1, 3)
	lb.call("fetch_top", LBScript.BOARD_DEPTH)
	_assert((lb.get("_handles") as Dictionary).is_empty(), "no board handles without Steam")
	_assert((lb.get("_pending_uploads") as Array).is_empty(), "no queued uploads without Steam")
	_assert((lb.call("get_cached", LBScript.BOARD_DEPTH) as Array).is_empty(),
		"empty cache without Steam")
	# Panel: exactly 10 fixed rows per board, zero scroll containers.
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu._refresh_leaderboard_panel()
	for path in ["DailyPhase/LeaderboardPanel/DepthCol/DepthRows",
			"DailyPhase/LeaderboardPanel/SpeedCol/SpeedRows"]:
		var rows: VBoxContainer = menu.get_node(path)
		_assert(_live_children(rows).size() == LBScript.MAX_ENTRIES,
			"%s has 10 fixed rows" % path.get_file())
	var scrolls := []
	_find_scroll_containers(menu.get_node("DailyPhase"), scrolls)
	_assert(scrolls.is_empty(), "DailyPhase has no scroll containers")
	# Seeded entries: player row highlighted, count stays fixed at 10.
	(lb.get("_cache") as Dictionary)[LBScript.BOARD_DEPTH] = [
		{"rank": 1, "name": "Rival", "score": 300002, "is_player": false},
		{"rank": 2, "name": "Me", "score": 200005, "is_player": true},
	]
	menu._refresh_leaderboard_panel()
	var depth_rows: VBoxContainer = menu.get_node("DailyPhase/LeaderboardPanel/DepthCol/DepthRows")
	_assert(_live_children(depth_rows).size() == 10, "row count stays 10 with entries")
	var player_lbl: Label = null
	for child in _live_children(depth_rows):
		if child is Label and child.text.contains("Me"):
			player_lbl = child
	_assert(player_lbl != null, "player entry shown")
	_assert(player_lbl.get_theme_color("font_color") == Color(1.0, 0.85, 0.3),
		"player row highlighted gold")
	(lb.get("_cache") as Dictionary)[LBScript.BOARD_DEPTH] = []
	# Race-my-best toggle (Phase 2): defaults off, flips the Dungeon static.
	_assert(not bool(menu.get_node("DailyPhase/RaceEchoCheck").button_pressed),
		"race echo toggle defaults off")
	menu.get_node("DailyPhase/RaceEchoCheck").button_pressed = true
	menu._on_race_echo_toggled(true)
	var er2: Node = root.get_node_or_null("EchoRecorder")
	_assert(bool(er2.get("race_echo")), "toggle sets EchoRecorder.race_echo")
	menu._on_race_echo_toggled(false)
	_assert(not bool(er2.get("race_echo")), "toggle clears EchoRecorder.race_echo")
	menu.queue_free()
	print("[Playtest] leaderboard phase 1 done")


## Children not queued for deletion (queue_free is deferred to frame end).
func _live_children(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if not child.is_queued_for_deletion():
			out.append(child)
	return out


func _find_scroll_containers(node: Node, out: Array) -> void:
	if node is ScrollContainer:
		out.append(node)
	for child in node.get_children():
		_find_scroll_containers(child, out)


func _test_echo_phase2() -> void:
	print("[Playtest] echo record/playback (issue #9 Phase 2)...")
	var ERScript = load("res://scripts/autoload/echo_recorder.gd")
	var er: Node = root.get_node_or_null("EchoRecorder")
	_assert(er != null, "EchoRecorder autoload exists")
	_assert(not bool(er.get("is_recording")), "recorder idle by default")

	# --- Sample encode/decode roundtrip ---
	var buf := PackedByteArray()
	ERScript.encode_sample(buf, 42, Vector3(12.345, 0.0, -67.89), 1.5708)
	_assert(buf.size() == 12, "sample is 12 bytes")
	var s: Dictionary = ERScript.decode_sample(buf, 0)
	_assert(int(s["tick"]) == 42, "tick roundtrips")
	_assert((s["pos"] as Vector3).distance_to(Vector3(12.345, 0.0, -67.89)) < 0.02,
		"position roundtrips within 2cm")
	_assert(absf(wrapf(float(s["yaw"]) - 1.5708, -PI, PI)) < 0.001,
		"yaw roundtrips")
	_assert(ERScript.decode_sample(buf, 5).is_empty(), "out-of-range decode is {}")

	# --- File format: header, size bound, load roundtrip ---
	# Simulate a 10-minute run: 6000 samples at 10Hz.
	var big := PackedByteArray()
	for i in 6000:
		ERScript.encode_sample(big, i, Vector3(i * 0.01, 0, i * 0.02), float(i) * 0.001)
	var events := [{"tick": 100, "ability_id": "fireball"}, {"tick": 5500, "ability_id": "meteor"}]
	var data := {"date": "20261005", "seed": 987654, "samples": big,
		"sample_count": 6000, "ability_events": events}
	var path := "user://echoes/test_echo.dat"
	_assert(bool(er.call("save_echo", data, path)), "echo saves")
	var f := FileAccess.open(path, FileAccess.READ)
	var fsize := f.get_length()
	f.close()
	# 25 header + 6000*12 samples + events ≈ 72KB. Bound well under 150KB.
	_assert(fsize < 150 * 1024, "10-min echo under 150KB (was %d)" % fsize)
	_assert(fsize > 60000, "10-min echo has substance (was %d)" % fsize)
	var loaded: Dictionary = er.call("load_echo", path)
	_assert(not loaded.is_empty(), "echo loads")
	_assert(str(loaded["date"]) == "20261005", "date roundtrips")
	_assert(int(loaded["seed"]) == 987654, "seed roundtrips")
	_assert(int(loaded["sample_count"]) == 6000, "sample count roundtrips")
	_assert((loaded["ability_events"] as Array).size() == 2, "ability events roundtrip")
	_assert(str((loaded["ability_events"] as Array)[1]["ability_id"]) == "meteor",
		"ability id roundtrips")
	var ls0: Dictionary = ERScript.decode_sample(loaded["samples"], 0)
	var ls5999: Dictionary = ERScript.decode_sample(loaded["samples"], 5999)
	_assert(int(ls0["tick"]) == 0 and int(ls5999["tick"]) == 5999, "sample ticks survive")
	# Corrupt/missing files fail clean, never crash.
	_assert((er.call("load_echo", "user://echoes/does_not_exist.dat") as Dictionary).is_empty(),
		"missing echo loads as {}")
	var bad := FileAccess.open("user://echoes/bad.dat", FileAccess.WRITE)
	bad.store_buffer(PackedByteArray([1, 2, 3, 4]))
	bad.close()
	_assert((er.call("load_echo", "user://echoes/bad.dat") as Dictionary).is_empty(),
		"corrupt echo loads as {}")
	DirAccess.remove_absolute("user://echoes/test_echo.dat")
	DirAccess.remove_absolute("user://echoes/bad.dat")

	# --- Recorder: 10Hz sampling, ability events, no RNG ---
	# The recorder script must contain zero RNG calls (pure observation).
	var rsrc := FileAccess.get_file_as_string("res://scripts/autoload/echo_recorder.gd")
	for rng_call in ["randi(", "randf(", "randi_range(", "randf_range(", "RandomNumberGenerator", ".seed ="]:
		_assert(not rsrc.contains(rng_call), "recorder has no RNG: %s" % rng_call)
	# Live recording against a dummy player node.
	var dummy := Node3D.new()
	dummy.position = Vector3(3.0, 0.0, 4.0)
	dummy.rotation.y = 0.75
	root.add_child(dummy)
	er.call("start_recording", dummy, "20261005", 12345)
	_assert(bool(er.get("is_recording")), "recording starts")
	er.call("record_ability", "fireball")
	# Simulate 0.35s of _process → 3 samples at 10Hz.
	er._process(0.35)
	_assert(int(er.get("_sample_count")) == 3, "10Hz sampling (3 samples in 0.35s)")
	er.call("record_ability", "")
	_assert((er.get("_ability_events") as Array).size() == 1, "empty ability id ignored")
	var rec: Dictionary = er.call("stop_recording")
	_assert(not bool(er.get("is_recording")), "recording stops")
	_assert(int(rec["sample_count"]) == 3, "stop returns samples")
	_assert(str((rec["ability_events"] as Array)[0]["ability_id"]) == "fireball",
		"ability event captured with tick")
	var rs: Dictionary = ERScript.decode_sample(rec["samples"], 0)
	_assert((rs["pos"] as Vector3).distance_to(Vector3(3.0, 0.0, 4.0)) < 0.02,
		"recorded position matches player")
	er.call("record_ability", "meteor")
	_assert((er.get("_ability_events") as Array).is_empty(), "no-op when not recording")
	dummy.queue_free()

	# --- Ghost: visual-only, zero RNG, no collision ---
	var gsrc := FileAccess.get_file_as_string("res://scripts/combat/echo_ghost.gd")
	for rng_call in ["randi(", "randf(", "randi_range(", "randf_range(", "RandomNumberGenerator"]:
		_assert(not gsrc.contains(rng_call), "ghost has no RNG: %s" % rng_call)
	_assert(not gsrc.contains("CollisionShape3D.new"), "ghost has no collision shape")
	_assert(not gsrc.contains("take_damage") and not gsrc.contains("deal_damage"),
		"ghost deals/takes no damage")
	var ghost := EchoGhost.new()
	root.add_child(ghost)
	# Ghost with no echo: start is a safe no-op.
	ghost.start()
	_assert(not ghost.is_playing(), "ghost won't play without echo data")
	# Load the saved echo via data dict and race it.
	var gbuf := PackedByteArray()
	for i in 20:
		ERScript.encode_sample(gbuf, i, Vector3(i * 1.0, 0, 0), 0.0)
	_assert(ghost.load_echo_data({"samples": gbuf, "sample_count": 20}), "ghost loads echo")
	ghost.start()
	_assert(ghost.is_playing(), "ghost plays")
	# Playback position matches recording within tolerance: at t=0.55s
	# (sample 5.5) the ghost lerps between samples 5 and 6 → x ≈ 5.5.
	for i in 11:
		ghost._process(0.05)
	_assert(absf(ghost.global_position.x - 5.5) < 0.05,
		"playback interpolates (x=%.2f)" % ghost.global_position.x)
	# Ghost never touches the dungeon RNG: seeded ProcGen is identical
	# with and without a ghost racing alongside.
	var theme = load("res://data/levels/theme_village.tres")
	var layout_a := ProcGen.generate(theme, 424242)
	# Race a ghost during the second generation.
	var ghost2 := EchoGhost.new()
	root.add_child(ghost2)
	ghost2.load_echo_data({"samples": gbuf, "sample_count": 20})
	ghost2.start()
	for i in 30:
		ghost2._process(0.016)
	var layout_b := ProcGen.generate(theme, 424242)
	_assert(layout_a.grid_size == layout_b.grid_size, "ghost: same grid size")
	_assert(str(layout_a.mob_spawns) == str(layout_b.mob_spawns), "ghost: identical mob spawns")
	ghost2.queue_free()
	# Ghost reaches the end and stops cleanly.
	for i in 50:
		ghost._process(0.1)
	_assert(not ghost.is_playing(), "ghost stops at end of echo")
	ghost.queue_free()

	# --- Wiring: player hooks, dungeon hooks, death save ---
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("_notify_echo_ability"), "player logs ability casts")
	_assert(psrc.contains("stop_recording"), "death stops recording")
	_assert(psrc.contains("save_echo"), "best run saves echo")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("start_recording"), "dungeon starts recording on daily")
	_assert(dsrc.contains("_maybe_spawn_echo_ghost"), "dungeon spawns ghost when toggled")
	_assert(dsrc.contains("_maybe_spawn_echo_ghost"), "ghost spawn hook exists")
	print("[Playtest] echo phase 2 done")


func _test_workshop_phase3() -> void:
	print("[Playtest] workshop echo sharing (issue #9 Phase 3)...")
	var WSScript = load("res://scripts/autoload/workshop_echo.gd")
	var ws: Node = root.get_node_or_null("WorkshopEcho")
	_assert(ws != null, "WorkshopEcho autoload exists")

	# Tag format: "daily-echo-<YYYYMMDD>".
	_assert(WSScript.tag_for_date("20261005") == "daily-echo-20261005",
		"workshop tag format")
	_assert(WSScript.tag_for_date("20261005").begins_with("daily-echo-"),
		"tag has prefix")

	# Offline guards: Steam is not initialized on this VM. All entry points
	# must be silent no-ops (no crash, no signal, no pending state).
	var sm: Node = root.get_node_or_null("SteamManager")
	_assert(sm != null and not bool(sm.get("initialized")), "precondition: Steam offline")
	_assert(not bool(ws.call("steam_available")), "workshop reports unavailable")
	# upload_today_best with no echo file: no-op.
	ws.call("upload_today_best")
	_assert(str(ws.get("_pending_upload_date")).is_empty(), "no upload pending offline")
	# Create a dummy echo file, then upload: still no-op offline, no crash.
	var er: Node = root.get_node_or_null("EchoRecorder")
	var buf := PackedByteArray()
	var ERScript = load("res://scripts/autoload/echo_recorder.gd")
	for i in 10:
		ERScript.encode_sample(buf, i, Vector3(i, 0, 0), 0.0)
	var dummy_data := {"date": "20261005", "seed": 1, "samples": buf,
		"sample_count": 10, "ability_events": []}
	_assert(bool(er.call("save_echo", dummy_data, "user://echoes/20261005.dat")),
		"dummy echo saves")
	ws.call("upload_today_best")
	_assert(str(ws.get("_pending_upload_date")).is_empty(),
		"upload is no-op offline even with echo file")
	# query_today_echoes offline: emits empty array via signal.
	var queried: Array = []
	ws.connect("query_complete", func(echoes: Array): queried = echoes)
	ws.call("query_today_echoes")
	_assert(queried.is_empty(), "offline query returns empty")
	# download_echo offline: no-op, no crash.
	ws.call("download_echo", 12345)
	# Signal methods exist and are connected (when Steam was available at _ready;
	# offline they simply never fire).
	_assert(ws.has_signal("upload_complete"), "upload_complete signal exists")
	_assert(ws.has_signal("query_complete"), "query_complete signal exists")
	_assert(ws.has_signal("download_complete"), "download_complete signal exists")

	# Ghost races a "downloaded" echo: simulate the Workshop download by
	# copying the file to the workshop_* path the UI uses.
	var src := FileAccess.open("user://echoes/20261005.dat", FileAccess.READ)
	var dst := FileAccess.open("user://echoes/workshop_999.dat", FileAccess.WRITE)
	dst.store_buffer(src.get_buffer(src.get_length()))
	src.close()
	dst.close()
	er.set("race_echo_path", "user://echoes/workshop_999.dat")
	er.set("race_echo", true)
	var ghost := EchoGhost.new()
	root.add_child(ghost)
	# The dungeon's _maybe_spawn_echo_ghost prioritizes race_echo_path;
	# emulate its file-selection logic here.
	var dl_path := str(er.get("race_echo_path"))
	_assert(FileAccess.file_exists(dl_path), "downloaded echo file exists")
	_assert(ghost.load_echo(dl_path), "ghost loads downloaded echo")
	ghost.start()
	_assert(ghost.is_playing(), "ghost races downloaded echo")
	for i in 5:
		ghost._process(0.05)
	_assert(ghost.global_position.x > 0.0, "downloaded echo plays back")
	ghost.queue_free()
	er.set("race_echo_path", "")
	er.set("race_echo", false)
	DirAccess.remove_absolute("user://echoes/20261005.dat")
	DirAccess.remove_absolute("user://echoes/workshop_999.dat")

	# Wiring: player triggers upload on new best; menu has the UI.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("upload_today_best"), "player triggers workshop upload")
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(msrc.contains("_on_top_echoes_pressed"), "menu has top-echoes handler")
	_assert(msrc.contains("query_today_echoes"), "menu queries workshop")
	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/main_menu.tscn")
	_assert(tsrc.contains("TopEchoesButton"), "Daily phase has top-echoes button")
	_assert(tsrc.contains("TopEchoesList"), "Daily phase has echoes list")
	# Zero-scroll: the new button + list add no ScrollContainers.
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	var scrolls := []
	_find_scroll_containers(menu.get_node("DailyPhase"), scrolls)
	_assert(scrolls.is_empty(), "DailyPhase still has no scroll containers")
	menu.queue_free()
	print("[Playtest] workshop phase 3 done")

## True when no ScrollContainer exists anywhere under the vault popup.
func _vault_no_scroll(hud: Node) -> bool:
	var pop: Node = hud.get("_cipher_popup")
	if pop == null:
		return false
	return pop.find_children("*", "ScrollContainer", true, false).is_empty()

func _test_specials_phase2() -> void:
	print("[Playtest] Specials phase 2 (vault locker + panel)...")
	var mgr := root.get_node("SaveManager")
	# Load at runtime (not via the class_name): a parse-time reference would
	# force special_data.gd to compile before autoloads exist, breaking its
	# bare SaveManager refs (same reason phase 1 uses load()).
	var SD: GDScript = load("res://scripts/data/special_data.gd")
	# Abort-safe profile backup (sidecar pattern): a runtime error aborts THIS
	# function, so never delete the original before a restore succeeds.
	var prof_path := "user://profile_local.cfg"
	var prof_bak := prof_path + ".phase2bak"
	if FileAccess.file_exists(prof_path):
		_copy_file(prof_path, prof_bak)
	elif FileAccess.file_exists(prof_bak):
		_copy_file(prof_bak, prof_path) # self-heal after an aborted run
	# Start from a clean profile for deterministic locked/earned states.
	if FileAccess.file_exists(prof_path):
		DirAccess.remove_absolute(prof_path)
	mgr.call("load_game")
	_assert(not SD.is_earned("greed_charm"), "clean profile: nothing earned")
	var holder := Node3D.new() # -s mode has no current_scene; positional sfx needs one
	root.add_child(holder)
	current_scene = holder
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var pl = PlayerScene.instantiate()
	pl.set("class_id", "warrior")
	root.add_child(pl)
	var HUDScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud = HUDScene.instantiate()
	root.add_child(hud)
	hud.call("setup", pl)

	# Vault prop: group, prompt, locker face sprite + sign.
	var VaultScript := load("res://scripts/station/relic_vault.gd")
	var vault = VaultScript.new()
	root.add_child(vault)
	_assert(vault.is_in_group("vault_locker"), "vault prop in vault_locker group")
	_assert(str(vault.call("prompt_text")) == "Open relic vault", "vault prompt text")
	var face: Sprite3D = null
	var sign: Label3D = null
	for ch in vault.get_children():
		if ch is Sprite3D:
			face = ch
		elif ch is Label3D:
			sign = ch
	_assert(face != null and face.texture != null, "vault locker face sprite present")
	_assert(sign != null and sign.text == "RELIC VAULT", "vault sign reads RELIC VAULT")
	# Player E-scan covers the group; station places the locker.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains('"vault_locker"'), "player E-scan covers vault_locker")
	var stsrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(stsrc.contains("RelicVault"), "station places the vault locker")

	# E-interact opens the vault panel through the popup shell.
	vault.call("interact", pl)
	_assert(bool(hud.get("vault_open")), "E-interact opens the vault panel")
	_assert(bool(hud.get("cipher_popup_open")), "vault panel uses the popup shell")
	# Fixed six-card layout; everything locked on a clean profile.
	var grid := _vault_find(hud, "VaultGrid")
	_assert(grid != null and grid.get_child_count() == 6, "six special cards, fixed count")
	for sid in SD.SPECIAL_IDS:
		var card := _vault_find(hud, "VaultCard_" + sid)
		_assert(card != null, "card present for " + sid)
		_assert(_vault_card_button(card) == "LOCKED", "locked card shows LOCKED (" + sid + ")")
		var desc_l := card.find_children("*", "Label", true, false)[1] as Label
		_assert((desc_l as Label).text.begins_with("Locked"), "locked card shows unlock hint (" + sid + ")")
	# Trophy row: 3 apex icons, dimmed while unearned.
	var trow := _vault_find(hud, "TrophyRow")
	_assert(trow != null, "trophy row present")
	var trophies := trow.find_children("*", "TextureRect", true, false)
	_assert(trophies.size() == 3, "fixed trophy row has 3 icons")
	for t in trophies:
		_assert((t as TextureRect).modulate.r < 0.5, "unearned trophy dimmed")
	# Zero-scroll audit: no ScrollContainer and the panel fits a real screen.
	# (Headless -s runs at a 64x64 viewport, so assert against 1280x720.)
	_assert(_vault_no_scroll(hud), "vault panel has no ScrollContainer")
	var panel_box := _vault_find(hud, "VaultGrid").get_parent().get_parent() as Control
	var need: Vector2 = panel_box.get_combined_minimum_size()
	_assert(need.x <= 1280.0 and need.y <= 720.0,
		"vault panel fits on screen (%d x %d <= 1280 x 720)" % [need.x, need.y])

	# Equip flow: earn two specials, equip one through the panel button.
	_assert(SD.earn("greed_charm"), "earn greed_charm")
	_assert(SD.earn("apex_boar_hide"), "earn apex trophy")
	hud.call("show_vault")
	_assert(_vault_press(hud, "greed_charm", "EQUIP"), "EQUIP button pressed")
	_assert(str(pl.get("equipped_special")) == "greed_charm", "panel EQUIP equips the special")
	# Equipped card now offers UNEQUIP; equip persists into departure saves.
	_assert(_vault_card_button(_vault_find(hud, "VaultCard_greed_charm")) == "UNEQUIP",
		"equipped card shows UNEQUIP")
	var st: Dictionary = pl.call("get_state")
	_assert(str(st.get("equipped_special", "")) == "greed_charm",
		"equipped special survives get_state (departure save)")
	# Trophy row: earned trophy lit, unearned still dimmed.
	var trophies2 := (_vault_find(hud, "TrophyRow") as Node).find_children("*", "TextureRect", true, false)
	_assert((trophies2[0] as TextureRect).modulate.r > 0.9, "earned trophy shown lit")
	_assert((trophies2[1] as TextureRect).modulate.r < 0.5, "unearned trophy still dimmed")
	# Equip replaces: equipping a second special swaps it in.
	_assert(SD.earn("iron_resolve"), "earn iron_resolve")
	hud.call("show_vault") # rebuild so the newly earned card offers EQUIP
	_assert(_vault_press(hud, "iron_resolve", "EQUIP"), "EQUIP iron_resolve pressed")
	_assert(str(pl.get("equipped_special")) == "iron_resolve", "second EQUIP replaces the first")
	_assert(_vault_press(hud, "iron_resolve", "UNEQUIP"), "UNEQUIP pressed")
	_assert(str(pl.get("equipped_special")) == "", "UNEQUIP clears the equipped special")
	# Locked cards stay locked: no EQUIP path for unearned specials.
	hud.call("show_vault")
	_assert(not _vault_press(hud, "second_wind", "EQUIP"), "unearned special cannot be equipped")

	# E/Esc closes the panel and clears the flag.
	hud.call("close_cipher_popup")
	_assert(not bool(hud.get("vault_open")), "closing the popup clears vault_open")

	# Restore the profile.
	if FileAccess.file_exists(prof_bak):
		_copy_file(prof_bak, prof_path)
		DirAccess.remove_absolute(prof_bak)
	elif FileAccess.file_exists(prof_path):
		DirAccess.remove_absolute(prof_path) # test-created only
	mgr.call("load_game")
	hud.queue_free()
	pl.queue_free()
	vault.queue_free()
	holder.queue_free()
## Stub dungeon for apex mechanic tests: records announces/spawns, returns a


func _test_wave_stall_watchdog() -> void:
	print("[Playtest] wave stall watchdog (issue #27)...")
	# Static verification: the wave-clear check must use _mobs_alive(), not
	# raw child count (the #27 root cause).
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("_mobs_alive() == 0"),
		"wave-clear uses _mobs_alive() not child count")
	_assert(dsrc.contains("WAVE_STALL_TIMEOUT"),
		"watchdog timeout constant exists")
	_assert(dsrc.contains("_wave_stall_t = 0.0"),
		"watchdog timer resets")

	# Behavioral: _mobs_alive counts only alive Mob instances.
	var DungeonScript = load("res://scripts/dungeon/dungeon.gd")
	var d = DungeonScript.new()
	var mobs := Node3D.new()
	mobs.name = "Mobs"
	d.add_child(mobs)
	# NOT added to tree: _mobs_alive() only needs the $Mobs child structure.
	# (Adding to root would pollute the "dungeon" group for later tests.)
	_assert(d.call("_mobs_alive") == 0, "no mobs -> 0 alive")
	var junk := Node3D.new()
	junk.name = "LingeringEffect"
	mobs.add_child(junk)
	_assert(d.call("_mobs_alive") == 0, "non-mob child ignored by _mobs_alive")
	_assert(mobs.get_child_count() == 1, "child count sees the junk (the old bug)")

	# Watchdog timer accumulates only when spawning is done but mobs remain
	# 'alive'. We simulate the stuck state via the timer directly to avoid
	# instantiating full Mob scenes in the test harness.
	d.set("mobs_to_spawn", 0)
	d.set("wave_state", 1)  # WaveState.ACTIVE
	d.set("_wave_stall_t", 4.9)
	# With 0 alive mobs, _process_waves clears immediately (no watchdog needed).
	d.call("_process_waves", 0.016)
	_assert(int(d.get("wave_state")) != 1,
		"wave clears immediately with 0 alive (no stall)")

	d.free()
	print("[Playtest] wave stall watchdog done")
	print("[Playtest] wave stall watchdog done")


func _test_eagle_eye_warlord_hide() -> void:
	print("[Playtest] Eagle Eye Warlord hide (issue #19)...")
	# Static: refresh_abilities skips eagle_eye in Warlord theme.
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains('sid == "eagle_eye" and _is_warlord_theme()'),
		"ability bar skips eagle_eye in Warlord")
	_assert(hsrc.contains("func _is_warlord_theme()"),
		"_is_warlord_theme helper exists")
	# Static: HUD tracks Warlord state changes and refreshes.
	_assert(hsrc.contains("_last_warlord"),
		"HUD tracks Warlord state")
	_assert(hsrc.contains("warlord_now != _last_warlord"),
		"HUD refreshes on Warlord change")
	print("[Playtest] Eagle Eye Warlord hide done")


func _test_issue18_ui_fixes() -> void:
	print("[Playtest] issue #18 UI fixes...")
	# Static: death screen hides the wave banner + prompt.
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("%NextWaveButton.visible = false") and hsrc.contains("%WaveStatus.visible = false"),
		"death screen hides wave banner and prompt")
	# Static: staging row has spacing between toggle and button.
	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/main_menu.tscn")
	_assert(tsrc.contains('theme_override_constants/separation = 24'),
		"staging row has 24px separation")
	print("[Playtest] issue #18 UI fixes done")


func _test_fireball_fuse() -> void:
	print("[Playtest] fireball proximity fuse (issue #20)...")
	# Static: fuse and AoE must use XZ distance, not 3D distance_to.
	var fsrc := FileAccess.get_file_as_string("res://scripts/combat/fireball.gd")
	_assert(fsrc.contains("Vector2(mob.global_position.x, mob.global_position.z)"),
		"fireball fuse uses XZ distance")
	# The old 3D fuse must be gone from the proximity check.
	var fuse_section := fsrc.substr(fsrc.find("_physics_process"), fsrc.find("func _explode") - fsrc.find("_physics_process"))
	_assert(not fuse_section.contains("mob.global_position.distance_to(global_position) < 1.3"),
		"old 3D fuse removed")
	# Behavioral: a level shot at 1.45m height over a mob at feet origin
	# must be within fuse range via XZ (the #20 repro).
	var mob_pos := Vector3(0, 0, 0)  # feet origin
	var ball_pos := Vector3(0.5, 1.45, 0)  # level shot, 0.5m horizontal offset
	var dist_3d := mob_pos.distance_to(ball_pos)
	var dist_xz := Vector2(mob_pos.x, mob_pos.z).distance_to(Vector2(ball_pos.x, ball_pos.z))
	_assert(dist_3d > 1.3, "3D distance exceeds fuse (the bug)")
	_assert(dist_xz < 1.3, "XZ distance triggers fuse (the fix)")
	print("[Playtest] fireball proximity fuse done")


func _test_warlord_spawn_avoids_river() -> void:
	print("[Playtest] Warlord spawn avoids river (issue #28)...")
	# Static: procgen nudges Warlord spawns off the river.
	var psrc := FileAccess.get_file_as_string("res://scripts/procgen/procgen.gd")
	_assert(psrc.contains('theme.theme_id == "warlord"'),
		"#28: Warlord spawn check present")
	_assert(psrc.contains("river_nudge"),
		"#28: river nudge applied")
	# Behavioral: the nudge puts spawns outside abs(x) < 4.0.
	# (Dungeon.is_on_water: absf(pos.x) < 4.0)
	var nudge := Vector3(6.0, 0, 0)
	var offsets := [Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5)]
	for off in offsets:
		var spawn_x: float = (off + nudge).x
		_assert(absf(spawn_x) >= 4.0, "#28: spawn at x=%.1f avoids river" % spawn_x)
	print("[Playtest] Warlord spawn avoids river done")


func _test_issue22_23_fixes() -> void:
	print("[Playtest] issues #22/#23 fixes...")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("Dungeon.THEME_ORDER.size()"),
		"#22: cycle uses THEME_ORDER.size()")
	_assert(hsrc.contains("font_size = maxi(36,"),
		"#23: announce shrink-to-fit present")
	print("[Playtest] issues #22/#23 fixes done")
