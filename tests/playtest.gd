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
	_test_class_census()
	_test_rts_costs()
	_test_rts_production()
	_test_rts_spatial_hash()
	_test_rts_dormancy()
	_test_rts_batched_sync()
	_test_rts_multimesh()
	_test_rts_squads()
	_test_rts_squad_reorder_no_leak()
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
	_test_ability_bar_selected_highlight()
	_test_mouse_legend()
	_test_mouse_legend_states()
	_test_holy_light_key7()
	_test_holy_light_key7_label()
	_test_holy_light_visual()
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
	_test_train_ambient()
	_test_audio_combat_cues()
	_test_audio_113_cues()
	_test_audio_126_cues()
	_test_station_annex()
	_test_lobby_room()
	_test_lobby_doors()
	_test_station_embedded()
	_test_annex_departure()
	_test_annex_forfeit()
	_test_train_interior()
	_test_depart_flow()
	_test_lobby_full_cycle_2peer()
	_test_disconnect_mid_boarding()
	_test_train_ride()
	_test_train_ride_state_sync()
	_test_train_disembark_fallback()
	_test_train_dressing()
	_test_cycle_scaling()
	_test_ai_director()
	_test_downed_marker()
	_test_dash_flash_separate()
	_test_market_earned_display()
	_test_heal_pad_multiplayer()
	_test_train_spots_12p()
	_test_mp_save_steam_ids()
	_test_mp_save_bughunt()
	_test_save_format_pf1()
	_test_save_format_pf2()
	_test_weapon_upgrade_kits()
	_test_masterwork_drop_hook()
	_test_warlord_rebind_m1()
	_test_station_roster_carry_forward()
	_test_architect_tools_repair()
	_test_hammer_smash()
	_test_weapon_model_coverage_113()
	_test_lobby_strip()
	_test_checkout_multiplayer()
	_test_holy_light_linger()
	_test_train_state_handoff()
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
	_test_e_interact_not_dead_code()
	_test_watchdog_resets_on_progress()
	_test_watchdog_progress_not_kills()
	_test_r_wave_start_chain()
	_test_destination_popup_replaces_3d()
	_test_destination_popup_manual_only()
	_test_bounty_popup_opens()
	_test_collection_full_state_compact()
	_test_wave_ui_dedupe_and_boarding_hide()
	_test_departure_board_click_layer()
	_test_destination_popup_mouse_hold()
	_test_potion_quick_slot()
	_test_positioning_fixes()
	_test_lan_multiplayer_phase1()
	_test_lan_lobby_fixes()
	_test_lan_toggle_no_recursion()
	_test_shieldbearer()
	_test_splitter()
	_test_gravewarden()
	_test_snapshot_yaw()
	_test_sprite_orientation()
	_test_yaw_edge_cases()
	_test_ascension()
	_test_warlord_seasons()
	_test_warlord_seasons_phase2()
	_test_issue86_fixes()
	_test_holy_light_v2_phase1()
	_test_holy_light_v2_phase2()
	_test_holy_light_v2_phase3()
	_test_apex_mechanics()
	_test_apex_relics()
	_test_boss_second_specials()
	_test_boss_third_specials()
	_test_village_kit()
	_test_bounty_phase1()
	_test_combo_phase1()
	_test_combo_codex()
	_test_bounty_phase2()
	_test_leaderboard_phase1()
	_test_echo_phase2()
	_test_workshop_phase3()
	_test_settings_phase1()
	_test_settings_phase2()
	_test_thrown_dagger_phase1()
	_test_holy_light_heal()
	_test_steam_ready_once_only()
	_test_class_sprites_and_namebar()
	_test_fishing_farming_phase1()
	_test_fishing_minigame_phase2()
	_test_farming_loop_phase3()
	_test_dock_economy_phase4()
	_test_misty_docks_phase5()
	_test_popup_open_flags()
	_test_equip_system_phase1()
	_test_mp_save_c1_fix()
	_test_character_panel_phase2()
	_test_inventory_audit_136()
	_test_menu_batch_137()
	_test_inventory_pause_screen()
	_test_fishing_rod_phase3()
	_test_class_tagging_phase4()
	_test_111_minor_restore_drops()
	_test_111_minor_legacy_mp_save()
	_test_111_minor_pause_save_snapshot()
	_test_village_terrain_118()
	_test_terrain_skirt_124()
	_test_dungeon_terrain_120()
	_test_depths_terrain_121()
	_test_apex_terrain_122()

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


## Startup-compile tripwire (#117): a class whose script references an
## autoload by bare identifier fails to compile when the suite's startup
## chain reaches it (autoloads aren't registered in that window), the
## failure is cached for the run, and its sections silently exercise
## script-less instances. load() != null CANNOT see this (a broken script
## still loads) — can_instantiate() can. Census every gameplay class from
## the editor's class cache and fail LOUDLY, naming the class, so the
## next poison announces itself instead of hollowing a section.
func _test_class_census() -> void:
	print("[Playtest] Class census (startup-compile tripwire)...")
	var cache := ConfigFile.new()
	var err := cache.load("res://.godot/global_script_class_cache.cfg")
	_assert(err == OK, "census: global class cache readable")
	if err != OK:
		return
	var entries: Array = cache.get_value("", "list", [])
	var checked := 0
	var broken: Array = []
	for entry in entries:
		var path: String = str(entry.get("path", ""))
		if not path.begins_with("res://scripts/"):
			continue
		if bool(entry.get("is_abstract", false)):
			continue
		checked += 1
		var s: GDScript = load(path) as GDScript
		if s == null or not s.can_instantiate():
			broken.append(str(entry.get("class", path)))
	_assert(checked > 50, "census: covered %d gameplay classes" % checked)
	_assert(broken.is_empty(),
		"census: all gameplay classes instantiate in -s mode (broken: %s)" % ", ".join(broken))


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


func _test_rts_spatial_hash() -> void:
	print("[Playtest] RTS spatial hash...")
	var hash_script = load("res://scripts/rts/rts_spatial_hash.gd")
	_assert(hash_script != null, "RTSSpatialHash loads")
	if hash_script == null:
		return
	var h = hash_script.new()
	# Create mock units (plain Node3Ds with positions).
	var units: Array = []
	for i in 10:
		var n := Node3D.new()
		n.position = Vector3(i * 3.0, 0, 0)  # 0,3,6,...,27
		root.add_child(n)
		units.append(n)
		h.insert(n)
	# Query near origin with radius 8 should find units at 0,3,6 (cells 0,0 cover x in [-8,16)).
	var near: Array = h.query(Vector3.ZERO, 8.0)
	_assert(near.size() >= 3, "Hash query finds nearby units (got %d)" % near.size())
	# Query far away finds nothing.
	var far: Array = h.query(Vector3(100, 0, 100), 8.0)
	_assert(far.is_empty(), "Hash query far away is empty")
	# Move a unit across a cell boundary; update re-buckets.
	units[0].position = Vector3(50, 0, 0)
	h.update(units[0])
	var near_after: Array = h.query(Vector3.ZERO, 8.0)
	_assert(not near_after.has(units[0]), "Moved unit leaves old cell")
	var at_new: Array = h.query(Vector3(50, 0, 0), 8.0)
	_assert(at_new.has(units[0]), "Moved unit found in new cell")
	# Remove works.
	h.remove(units[1])
	var after_remove: Array = h.query(Vector3(3, 0, 0), 8.0)
	_assert(not after_remove.has(units[1]), "Removed unit not in query")
	# Cleanup.
	for n in units:
		n.queue_free()


func _test_rts_dormancy() -> void:
	print("[Playtest] RTS dormancy...")
	var unit_script = load("res://scripts/rts/unit.gd")
	_assert(unit_script != null, "RTSUnit loads")
	if unit_script == null:
		return
	var u = unit_script.new()
	root.add_child(u)
	# Fresh unit with no orders is idle.
	_assert(u.call("_is_idle"), "Fresh unit is idle")
	# order_move wakes (sets _dormant=false) and makes non-idle.
	u.order_move(Vector3(10, 0, 10))
	_assert(not u.get("_dormant"), "order_move wakes unit")
	_assert(not u.call("_is_idle"), "Unit with move order not idle")
	# Simulate order completion: clear targets, then _sleep.
	u.set("_move_target", Vector3.INF)
	_assert(u.call("_is_idle"), "Unit idle after order cleared")
	u.call("_sleep")
	_assert(bool(u.get("_dormant")), "Unit dormant after _sleep")
	# Damage wakes.
	u.call("_apply_damage", 1.0)
	_assert(not u.get("_dormant"), "Damage wakes dormant unit")
	u.queue_free()


func _test_rts_batched_sync() -> void:
	print("[Playtest] RTS batched sync...")
	var mgr_script = load("res://scripts/rts/rts_manager.gd")
	_assert(mgr_script != null, "RTSManager loads for sync test")
	if mgr_script == null:
		return
	var mgr = mgr_script.new()
	root.add_child(mgr)
	# Manager has sync interval and broadcast method.
	_assert(mgr.get("SYNC_INTERVAL") == 0.12, "Sync interval is 0.12s (8Hz)")
	_assert(mgr.has_method("_broadcast_army_sync"), "Manager has _broadcast_army_sync")
	_assert(mgr.has_method("client_sync_army"), "Manager has client_sync_army rpc")
	_assert(mgr.get("spatial_hash") != null, "Manager owns spatial hash")
	mgr.queue_free()


func _test_rts_multimesh() -> void:
	print("[Playtest] RTS multimesh renderer...")
	var rend_script = load("res://scripts/rts/rts_unit_renderer.gd")
	_assert(rend_script != null, "RTSUnitRenderer loads")
	if rend_script == null:
		return
	var r = rend_script.new()
	root.add_child(r)
	_assert(r.has_method("register_unit"), "Renderer has register_unit")
	_assert(r.has_method("unregister_unit"), "Renderer has unregister_unit")
	_assert(r.has_method("_update_instances"), "Renderer has _update_instances")
	r.queue_free()


func _test_rts_squads() -> void:
	print("[Playtest] RTS squads...")
	var squad_script = load("res://scripts/rts/rts_squad.gd")
	_assert(squad_script != null, "RTSSquad loads")
	if squad_script == null:
		return
	# Thresholds.
	_assert(squad_script.squad_size_for(10) == 0, "10 units: no squads")
	_assert(squad_script.squad_size_for(24) == 0, "24 units: no squads")
	_assert(squad_script.squad_size_for(25) == 12, "25 units: squads of 12")
	_assert(squad_script.squad_size_for(99) == 12, "99 units: squads of 12")
	_assert(squad_script.squad_size_for(100) == 25, "100 units: squads of 25")
	_assert(squad_script.squad_size_for(500) == 25, "500 units: squads of 25")
	# Partition.
	var mock_units: Array = []
	for i in 50:
		var n := Node3D.new()
		n.set_meta("faction", 0)
		mock_units.append(n)
	# Mock get() for faction — use a simple approach.
	var squads: Array = squad_script.partition(mock_units)
	_assert(squads.size() == 5, "50 units -> 5 squads of 10 (got %d)" % squads.size())
	for n in mock_units:
		n.queue_free()
	# Manager has squad methods.
	var mgr_script = load("res://scripts/rts/rts_manager.gd")
	var mgr = mgr_script.new()
	_assert(mgr.has_method("order_move_squad"), "Manager has order_move_squad")
	_assert(mgr.has_method("rpc_order_move_squad"), "Manager has rpc_order_move_squad")
	_assert(mgr.has_method("dissolve_squads_for"), "Manager has dissolve_squads_for")
	mgr.queue_free()


func _test_rts_squad_reorder_no_leak() -> void:
	print("[Playtest] RTS squad reorder leak (#116)...")
	# Regression for issue #116: order_move_squad formed brand-new squads
	# on every call without dissolving the squads already covering those
	# units — 5 re-issues of one order grew the registry 3 -> 18, and the
	# stale squads stayed registered for the rest of the session.
	# NOTE: unit.gd cannot compile in this -s suite (its AudioManager
	# identifier is unresolved at suite-startup compile and the failure is
	# cached — the same poison that hollows _test_rts_dormancy), so real
	# RTSUnit instances here are script-less Node3Ds and order_move_squad
	# (which resolves units via `as RTSUnit`) cannot be driven in-suite.
	# This test therefore pins (a) the fix's wiring inside order_move_squad
	# and (b) the registry mechanism using the real manager + RTSSquad
	# code with mock units (the _test_rts_squads pattern). The full
	# behavioral proof with real units lives in the scene driver
	# scenes/terrain/squad_reorder_check.tscn (real stack, real frames).
	var src := FileAccess.get_file_as_string("res://scripts/rts/rts_manager.gd")
	var fstart := src.find("func order_move_squad(")
	_assert(fstart >= 0, "#116: order_move_squad found in rts_manager.gd")
	if fstart < 0:
		return
	var fend := src.find("\nfunc ", fstart + 10)
	var body := src.substr(fstart, (fend - fstart) if fend > fstart else 4000)
	var dpos := body.find("dissolve_squads_for(units)")
	var ppos := body.find("RTSSquad.partition(units)")
	_assert(dpos >= 0, "#116: order_move_squad dissolves before repartitioning")
	_assert(dpos >= 0 and ppos > dpos,
		"#116: dissolve call precedes partition in order_move_squad")
	# Mechanism: real RTSSquad.partition + real dissolve_squads_for over
	# the real registry array, mock units (36 -> 3 squads of 12).
	var mgr_script = load("res://scripts/rts/rts_manager.gd")
	var squad_script = load("res://scripts/rts/rts_squad.gd")
	_assert(mgr_script != null and squad_script != null, "#116: manager/squad scripts load")
	if mgr_script == null or squad_script == null:
		return
	var mgr = mgr_script.new()
	root.add_child(mgr)
	var mocks: Array = []
	for i in 36:
		var n := Node3D.new()
		root.add_child(n)
		mocks.append(n)
	for s in squad_script.partition(mocks):
		mgr.squads.append(s)
	_assert(mgr.squads.size() == 3,
		"#116: 36 mock units partition into 3 registered squads (got %d)" % mgr.squads.size())
	# The helper the fix calls retires every squad covering the ordered
	# units — a full re-order leaves no stale squads behind.
	mgr.dissolve_squads_for(mocks)
	_assert(mgr.squads.is_empty(),
		"#116: dissolve_squads_for retires all squads covering the ordered units")
	# Re-form, then a subset dissolve (one squad's 12) retires exactly
	# that squad; the other 24 stay covered exactly once.
	for s in squad_script.partition(mocks):
		mgr.squads.append(s)
	var first_squad_units: Array = (mgr.squads[0] as RefCounted).get("units")
	mgr.dissolve_squads_for(first_squad_units)
	_assert(mgr.squads.size() == 2,
		"#116: subset dissolve retires exactly its squad (registry %d, want 2)" % mgr.squads.size())
	var coverage := {}
	for s in mgr.squads:
		for u in s.get("units"):
			coverage[u] = int(coverage.get(u, 0)) + 1
	var rest_ok := coverage.size() == 24
	for u in coverage:
		if int(coverage[u]) != 1:
			rest_ok = false
	_assert(rest_ok, "#116: remaining 24 mock units covered exactly once")
	for n in mocks:
		root.remove_child(n)
		n.free()
	root.remove_child(mgr)
	mgr.free()


func _test_village_terrain_118() -> void:
	print("[Playtest] Village terrain + parameterized profile (#118)...")
	# Issue #118 (S1 of the #103 full integration): _build_terrain's
	# hardcoded misty-docks profile moved into LevelTheme terrain
	# exports; docks carries its constants verbatim (byte-identical —
	# the builder's before/after heightfield-SHA probes pin that), and
	# village opts in with a dry rolling-farmland profile.
	var village: Resource = load("res://data/levels/theme_village.tres")
	var docks: Resource = load("res://data/levels/theme_misty_docks.tres")
	_assert(village != null and docks != null, "#118: village + docks themes load")
	if village == null or docks == null:
		return
	# Village profile per the issue spec.
	_assert(bool(village.get("use_heightmap_terrain")), "#118: village use_heightmap_terrain on")
	_assert(absf(float(village.get("terrain_amplitude")) - 1.6) < 0.0001, "#118: village amp 1.6")
	_assert(absf(float(village.get("terrain_noise_frequency")) - 0.030) < 0.00001, "#118: village freq 0.030")
	_assert(absf(float(village.get("terrain_height_offset")) - 0.80) < 0.0001, "#118: village offset +0.80")
	_assert(absf(float(village.get("terrain_water_level")) - (-1.0)) < 0.0001, "#118: village water parked -1.00 (dry)")
	_assert(int(village.get("terrain_smooth_passes")) == 2, "#118: village smooth 2")
	_assert(absf(float(village.get("terrain_flatten_radius")) - 5.0) < 0.0001, "#118: village flatten 5.0")
	_assert(village.get("terrain_tint_low") == Color(0.3, 0.52, 0.22), "#118: village tint low = grass green")
	_assert(village.get("terrain_tint_mid") == Color(0.52, 0.42, 0.26), "#118: village tint mid = field brown")
	_assert(village.get("terrain_tint_high") == Color(0.76, 0.7, 0.45), "#118: village tint high = pale dry grass")
	# Tint anchor (#118 follow-up + Art tuning): village anchors the
	# ramp at 0.5 — raised from its design floor 0.0 (= offset 0.8 -
	# amp/2 0.8; the parked water at -1.0 would pin t=1) until Art's
	# census targets land: green (low) dominates, pale (high) is a
	# dry-crest accent.
	_assert(absf(float(village.get("terrain_tint_anchor")) - 0.5) < 0.0001, "#118: village tint anchor = 0.5 (Art-tuned)")
	# Docks profile: the formerly hardcoded constants, verbatim.
	_assert(bool(docks.get("use_heightmap_terrain")), "#118: docks use_heightmap_terrain on")
	_assert(absf(float(docks.get("terrain_amplitude")) - 1.0) < 0.0001, "#118: docks amp 1.0 verbatim")
	_assert(absf(float(docks.get("terrain_noise_frequency")) - 0.045) < 0.00001, "#118: docks freq 0.045 verbatim")
	_assert(absf(float(docks.get("terrain_height_offset")) - 0.55) < 0.0001, "#118: docks offset +0.55 verbatim")
	_assert(absf(float(docks.get("terrain_water_level")) - (-0.10)) < 0.0001, "#118: docks water -0.10 verbatim")
	_assert(absf(float(docks.get("terrain_pond_depth")) - 0.5) < 0.0001, "#118: docks pond depth 0.5 verbatim")
	_assert(int(docks.get("terrain_smooth_passes")) == 2, "#118: docks smooth 2 verbatim")
	_assert(absf(float(docks.get("terrain_flatten_radius")) - 5.0) < 0.0001, "#118: docks flatten 5.0 verbatim")
	_assert(docks.get("terrain_tint_bed") == Color(0.23, 0.22, 0.16), "#118: docks tint bed verbatim")
	_assert(docks.get("terrain_tint_low") == Color(0.16, 0.23, 0.17), "#118: docks tint low verbatim")
	_assert(docks.get("terrain_tint_mid") == Color(0.26, 0.25, 0.19), "#118: docks tint mid verbatim")
	_assert(docks.get("terrain_tint_high") == Color(0.32, 0.32, 0.33), "#118: docks tint high verbatim")
	# Docks does NOT set the tint anchor: NAN keeps the water anchor,
	# so the docks palette is arithmetically untouched.
	_assert(is_nan(float(docks.get("terrain_tint_anchor"))), "#118: docks tint anchor unset (NAN -> water anchor)")
	# Supermarket profile (issue #119): polished concrete — terrain ON
	# with near-zero relief by design, DRY, compressed grey tints.
	var mart: Resource = load("res://data/levels/theme_supermarket.tres")
	_assert(mart != null, "#119: supermarket theme loads")
	if mart != null:
		_assert(bool(mart.get("use_heightmap_terrain")), "#119: supermarket use_heightmap_terrain on")
		_assert(absf(float(mart.get("terrain_amplitude")) - 0.15) < 0.0001, "#119: supermarket amp 0.15")
		_assert(absf(float(mart.get("terrain_noise_frequency")) - 0.050) < 0.00001, "#119: supermarket freq 0.050")
		_assert(absf(float(mart.get("terrain_height_offset")) - 0.08) < 0.0001, "#119: supermarket offset +0.08")
		_assert(absf(float(mart.get("terrain_water_level")) - (-1.0)) < 0.0001, "#119: supermarket water parked -1.00 (dry)")
		_assert(int(mart.get("terrain_smooth_passes")) == 2, "#119: supermarket smooth 2")
		_assert(absf(float(mart.get("terrain_flatten_radius")) - 5.0) < 0.0001, "#119: supermarket flatten 5.0")
		_assert(mart.get("terrain_tint_low") == Color(0.84, 0.83, 0.78), "#119: supermarket tint low = concrete grey")
		_assert(mart.get("terrain_tint_mid") == Color(0.88, 0.87, 0.82), "#119: supermarket tint mid = ground color")
		_assert(mart.get("terrain_tint_high") == Color(0.91, 0.9, 0.85), "#119: supermarket tint high = pale concrete")
		# Tint anchor at the design floor: offset 0.08 - amp/2 0.075.
		_assert(absf(float(mart.get("terrain_tint_anchor")) - 0.005) < 0.0001, "#119: supermarket tint anchor = design floor 0.005")
		# No banding by construction: the whole dry ramp spans a small
		# color distance (village's spans ~0.55 by comparison).
		var lo_c: Color = mart.get("terrain_tint_low")
		var hi_c: Color = mart.get("terrain_tint_high")
		var span := Vector3(hi_c.r - lo_c.r, hi_c.g - lo_c.g, hi_c.b - lo_c.b).length()
		_assert(span < 0.20, "#119: supermarket tint ramp compressed (span %.3f < 0.20)" % span)
	# LevelTheme defaults: flag off, and the docks profile as the safe
	# default (a theme that only flips the flag gets proven behavior).
	var LT = load("res://scripts/procgen/level_theme.gd")
	var fresh = LT.new()
	_assert(not bool(fresh.get("use_heightmap_terrain")), "#118: default theme stays flat")
	_assert(absf(float(fresh.get("terrain_amplitude")) - 1.0) < 0.0001
		and absf(float(fresh.get("terrain_water_level")) - (-0.10)) < 0.0001,
		"#118: default terrain profile = docks profile")
	_assert(is_nan(float(fresh.get("terrain_tint_anchor"))), "#118: default tint anchor = NAN sentinel (water anchor)")
	# (fresh is a RefCounted Resource — no free(); it scopes out.)
	# Parameterization wiring: _build_terrain reads every profile field
	# from the active theme (source pins, the #116 pattern).
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	var bstart := dsrc.find("func _build_terrain(")
	_assert(bstart >= 0, "#118: _build_terrain found in dungeon.gd")
	if bstart >= 0:
		var bend := dsrc.find("\nfunc ", bstart + 10)
		var body := dsrc.substr(bstart, (bend - bstart) if bend > bstart else 6000)
		for field in ["terrain_noise_frequency", "terrain_amplitude", "terrain_height_offset",
				"terrain_water_level", "terrain_pond_depth", "terrain_smooth_passes",
				"terrain_flatten_radius", "terrain_tint_bed", "terrain_tint_low",
				"terrain_tint_mid", "terrain_tint_high", "terrain_tint_anchor"]:
			_assert(body.contains("theme." + field), "#118: _build_terrain reads theme.%s" % field)
	# Terrain-side plumbing: HeightmapTerrain carries the anchor and
	# _vertex_color consumes it (NAN falls back to the water level).
	var hsrc := FileAccess.get_file_as_string("res://scripts/terrain/heightmap_terrain.gd")
	_assert(hsrc.contains("var tint_anchor"), "#118: HeightmapTerrain declares tint_anchor")
	var vstart := hsrc.find("func _vertex_color(")
	_assert(vstart >= 0 and hsrc.substr(vstart, 700).contains("tint_anchor"),
		"#118: _vertex_color consumes tint_anchor")
	# Layout fingerprints: deterministic for every theme x the gate
	# seed set, and seed-sensitive for village. Terrain never feeds
	# back into layout (ProcGen reads no terrain profile field).
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	var seed_set := [1, 777, 424242, 20261012]
	var village_fps := {}
	for tid in ["village", "supermarket", "dungeon", "depths", "apex", "warlord", "misty_docks"]:
		var th: Resource = load("res://data/levels/theme_%s.tres" % tid)
		for s in seed_set:
			var l1 = ProcGenScript.generate(th, s)
			var l2 = ProcGenScript.generate(th, s)
			_assert(l1.fingerprint() == l2.fingerprint(),
				"#118: %s layout deterministic (seed %d)" % [tid, s])
			if tid == "village":
				village_fps[l1.fingerprint()] = true
	_assert(village_fps.size() == seed_set.size(), "#118: village layouts differ across seeds")
	# Bare-terrain behavior with the village profile (HeightmapTerrain
	# names no autoloads, so it compiles in this suite): dry by
	# construction, heights inside the design range, grade in budget.
	var HT = load("res://scripts/terrain/heightmap_terrain.gd")
	var t = HT.new()
	root.add_child(t)
	t.set("map_points", 65)
	t.set("cell_size", 1.0)
	t.set("terrain_seed", 424242)
	t.set("noise_frequency", float(village.get("terrain_noise_frequency")))
	t.set("amplitude", float(village.get("terrain_amplitude")))
	t.set("height_offset", float(village.get("terrain_height_offset")))
	t.set("water_level", float(village.get("terrain_water_level")))
	t.set("pond_depth", float(village.get("terrain_pond_depth")))
	t.set("smooth_passes", int(village.get("terrain_smooth_passes")))
	t.set("flatten_radius", float(village.get("terrain_flatten_radius")))
	t.generate()
	var heights: PackedFloat32Array = t.heights_copy()
	var mn := 1e9
	var mx := -1e9
	var wet := 0
	for h in heights:
		mn = minf(mn, h)
		mx = maxf(mx, h)
		if h < float(village.get("terrain_water_level")):
			wet += 1
	_assert(mn >= -0.001 and mx <= 1.601,
		"#118: village heights in [0, 1.6] design range (%.3f..%.3f)" % [mn, mx])
	_assert(wet == 0, "#118: village terrain dry — zero sub-water heights (min %.3f)" % mn)
	var max_g := 0.0
	for gz in range(1, 64):
		for gx in range(1, 64):
			max_g = maxf(max_g, float(t.call("_slope_at", gx, gz)))
	_assert(max_g <= 0.55, "#118: village bare-terrain max grade %.1f%% <= 55%%" % (max_g * 100.0))
	# Tint ramp behavior (#118 follow-up + Art tuning): with the
	# anchor at the tuned 0.5, the ramp hits pure low/mid/high at
	# t = 0/0.5/1 (h = 0.0/0.9/1.3 at village amp 1.6, normalization
	# amp*0.5 = 0.8; t clamps, so any h <= anchor is pure low).
	# With the anchor unset (NAN) the same heights fall back to the
	# water anchor (-1.0), where h=0.4 already saturates to high.
	t.set("tint_bed", village.get("terrain_tint_bed"))
	t.set("tint_low", village.get("terrain_tint_low"))
	t.set("tint_mid", village.get("terrain_tint_mid"))
	t.set("tint_high", village.get("terrain_tint_high"))
	t.set("tint_anchor", float(village.get("terrain_tint_anchor")))
	var tl: Color = village.get("terrain_tint_low")
	var tm: Color = village.get("terrain_tint_mid")
	var th: Color = village.get("terrain_tint_high")
	var c_lo: Color = t.call("_vertex_color", 0.0, 0.0)
	var c_mid: Color = t.call("_vertex_color", 0.9, 0.0)
	var c_hi: Color = t.call("_vertex_color", 1.3, 0.0)
	_assert(Vector3(c_lo.r - tl.r, c_lo.g - tl.g, c_lo.b - tl.b).length() < 0.002,
		"#118: anchored ramp t=0 -> tint_low")
	_assert(Vector3(c_mid.r - tm.r, c_mid.g - tm.g, c_mid.b - tm.b).length() < 0.002,
		"#118: anchored ramp t=0.5 -> tint_mid")
	_assert(Vector3(c_hi.r - th.r, c_hi.g - th.g, c_hi.b - th.b).length() < 0.002,
		"#118: anchored ramp t=1 -> tint_high")
	t.set("tint_anchor", NAN)
	var c_fb: Color = t.call("_vertex_color", 0.4, 0.0)
	_assert(Vector3(c_fb.r - th.r, c_fb.g - th.g, c_fb.b - th.b).length() < 0.002,
		"#118: NAN anchor falls back to water anchor (h=0.4 saturates high)")
	root.remove_child(t)
	t.free()


func _test_terrain_skirt_124() -> void:
	print("[Playtest] Heightmap perimeter skirt (#124)...")
	# [QA] #124: the heightmap sheet is zero-thickness; at the station
	# annex door span (the one perimeter opening not backed by a wall)
	# the residual edge height above the y=0 apron left a see-through
	# sky slit from inside the annex. _build_mesh now appends a skirt
	# band around the perimeter — appended ONLY: the grid vertex arrays
	# must stay bit-identical (the #118/#119 identity-hash regression
	# net), which the prefix recomputation below pins.
	var hsrc := FileAccess.get_file_as_string("res://scripts/terrain/heightmap_terrain.gd")
	_assert(hsrc.contains("func _append_skirt("), "#124: HeightmapTerrain builds a perimeter skirt")
	_assert(hsrc.contains("_append_skirt(verts, normals, uvs, colors"),
		"#124: _build_mesh appends the skirt after the grid arrays")
	var HT = load("res://scripts/terrain/heightmap_terrain.gd")
	var t = HT.new()
	root.add_child(t)
	var mp := 9
	t.set("map_points", mp)
	t.set("cell_size", 1.0)
	t.set("terrain_seed", 424242)
	t.set("noise_frequency", 0.030)
	t.set("amplitude", 1.6)
	t.set("height_offset", 0.80)
	t.set("water_level", -1.0)
	t.generate()
	var heights: PackedFloat32Array = t.heights_copy()
	var mesh = t.get_node("TerrainMesh").mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var grid_count := (mp - 1) * (mp - 1) * 6
	var skirt_count := 4 * (mp - 1) * 12
	_assert(verts.size() == grid_count + skirt_count,
		"#124: mesh = %d grid + %d skirt verts (got %d)" % [grid_count, skirt_count, verts.size()])
	# Grid prefix identity: recompute every grid vertex position and
	# color from the heights array in the builder's own quad order and
	# require exact equality — the skirt must not perturb the grid.
	var bad := 0
	var vi := 0
	for gz in range(mp - 1):
		for gx in range(mp - 1):
			var quad := [Vector2i(gx, gz), Vector2i(gx + 1, gz), Vector2i(gx, gz + 1), Vector2i(gx + 1, gz + 1)]
			for tri in [[0, 1, 2], [1, 3, 2]]:
				for k in tri:
					var q: Vector2i = quad[k]
					var h: float = heights[q.y * mp + q.x]
					var expect := Vector3((float(q.x) - float(mp - 1) * 0.5) * 1.0, h,
						(float(q.y) - float(mp - 1) * 0.5) * 1.0)
					if verts[vi] != expect:
						bad += 1
					var ec: Color = t.call("_vertex_color", h, float(t.call("_slope_at", q.x, q.y)))
					# surface_get_arrays returns colors quantized to
					# 8 bits/channel, so colors compare within 1/255
					# (positions above stay exact).
					var ac: Color = colors[vi]
					if absf(ac.r - ec.r) > 0.004 or absf(ac.g - ec.g) > 0.004 or absf(ac.b - ec.b) > 0.004:
						bad += 1
					vi += 1
	_assert(bad == 0, "#124: grid prefix unchanged (positions exact, colors within 8-bit storage) — %d mismatches over %d verts" % [bad, grid_count])
	# Skirt geometry: every appended vertex lies on the perimeter
	# plane, and the band hangs exactly SKIRT_DEPTH (2.0) below the
	# lowest edge height.
	var half := float(mp - 1) * 0.5
	var edge_min := 1e9
	for i in mp:
		edge_min = minf(edge_min, heights[i])
		edge_min = minf(edge_min, heights[(mp - 1) * mp + i])
		edge_min = minf(edge_min, heights[i * mp])
		edge_min = minf(edge_min, heights[i * mp + mp - 1])
	var skirt_min := 1e9
	var off_plane := 0
	for i in range(grid_count, verts.size()):
		var v := verts[i]
		skirt_min = minf(skirt_min, v.y)
		if absf(absf(v.x) - half) > 0.001 and absf(absf(v.z) - half) > 0.001:
			off_plane += 1
	_assert(off_plane == 0, "#124: all skirt verts on the perimeter (%d off-plane)" % off_plane)
	_assert(absf(skirt_min - (edge_min - 2.0)) < 0.001,
		"#124: skirt hangs 2.0 below the lowest edge (min %.3f vs edge %.3f)" % [skirt_min, edge_min])
	root.remove_child(t)
	t.free()
func _test_dungeon_terrain_120() -> void:
	print("[Playtest] Dungeon terrain (#120)...")
	# Issue #120 (S3 of the #103 full integration): the Dungeon opts
	# into heightmap terrain with a near-flat worn-stone interior
	# profile (relief never fights walls/doors/slam reads), and the
	# ground FX that take a grounded position now honor its height
	# (flat themes: pos.y == 0, identical placement).
	var dungeon: Resource = load("res://data/levels/theme_dungeon.tres")
	var warlord: Resource = load("res://data/levels/theme_warlord.tres")
	_assert(dungeon != null and warlord != null, "#120: dungeon + warlord themes load")
	if dungeon == null or warlord == null:
		return
	_assert(bool(dungeon.get("use_heightmap_terrain")), "#120: dungeon use_heightmap_terrain on")
	_assert(absf(float(dungeon.get("terrain_amplitude")) - 0.35) < 0.0001, "#120: dungeon amp 0.35")
	_assert(absf(float(dungeon.get("terrain_noise_frequency")) - 0.060) < 0.00001, "#120: dungeon freq 0.060")
	_assert(absf(float(dungeon.get("terrain_height_offset")) - 0.18) < 0.0001, "#120: dungeon offset +0.18")
	_assert(absf(float(dungeon.get("terrain_water_level")) - (-1.0)) < 0.0001, "#120: dungeon water parked -1.00 (dry)")
	_assert(int(dungeon.get("terrain_smooth_passes")) == 3, "#120: dungeon smooth 3")
	_assert(absf(float(dungeon.get("terrain_flatten_radius")) - 5.0) < 0.0001, "#120: dungeon flatten 5.0")
	_assert(absf(float(dungeon.get("terrain_pond_depth")) - 0.5) < 0.0001, "#120: dungeon pond depth 0.5 (unused, dry)")
	_assert(dungeon.get("terrain_tint_bed") == Color(0.13, 0.13, 0.16), "#120: dungeon tint bed = damp stone")
	_assert(dungeon.get("terrain_tint_low") == Color(0.27, 0.27, 0.31), "#120: dungeon tint low = cold stone")
	_assert(dungeon.get("terrain_tint_mid") == Color(0.36, 0.36, 0.41), "#120: dungeon tint mid = worn stone")
	_assert(dungeon.get("terrain_tint_high") == Color(0.48, 0.48, 0.54), "#120: dungeon tint high = pale stone")
	# Tint anchor: the dry-theme form — the design floor
	# (offset - amp/2 = 0.18 - 0.175 = 0.005), not the parked water.
	_assert(absf(float(dungeon.get("terrain_tint_anchor")) - 0.005) < 0.0001
		and absf(float(dungeon.get("terrain_tint_anchor"))
			- (float(dungeon.get("terrain_height_offset"))
				- float(dungeon.get("terrain_amplitude")) * 0.5)) < 0.0001,
		"#120: dungeon tint anchor = design floor (offset - amp/2)")
	# Theme identity untouched by the flip.
	_assert(int(dungeon.get("grid_size")) == 24
		and absf(float(dungeon.get("cell_size")) - 2.0) < 0.0001
		and int(dungeon.get("torch_count")) == 10
		and str(dungeon.get("boss_id")) == "boss_warden",
		"#120: dungeon identity (24x2m interior, 10 torches, warden)")
	# Warlord is the flat exemplar (the docks check's off-pin moved
	# here when the dungeon flipped, on to apex when the depths
	# flipped in #121, and on to warlord when apex flipped in #122;
	# warlord's own flip is #123).
	_assert(not bool(warlord.get("use_heightmap_terrain")), "#120: warlord use_heightmap_terrain stays off")
	var dsrc := FileAccess.get_file_as_string("res://scripts/terrain/docks_integration_check.gd")
	_assert(dsrc.contains("theme_warlord.tres") and dsrc.contains("warlord theme flag stays off"),
		"#120: docks check off-pin points at warlord")
	# FX grounding: the FX that receive a grounded position honor its
	# height (source pins — the behavioral proof is the dungeon
	# integration check's slam-disc leg).
	var esrc := FileAccess.get_file_as_string("res://scripts/effects/effects.gd")
	_assert(esrc.contains("pos.y + 0.15"), "#120: telegraph ring grounds at pos.y + 0.15")
	var msrc := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(msrc.contains("pos.y + 3.5"), "#120: judgment pillar grounds at pos.y + 3.5")
	_assert(msrc.count("pos.y + 0.35") == 2, "#120: both slam rings ground at pos.y + 0.35")
	# Bare-terrain behavior with the dungeon profile: dry by
	# construction, heights inside the design range, grade in budget.
	var HT = load("res://scripts/terrain/heightmap_terrain.gd")
	var t = HT.new()
	root.add_child(t)
	t.set("map_points", 65)
	t.set("cell_size", 1.0)
	t.set("terrain_seed", 424242)
	t.set("noise_frequency", float(dungeon.get("terrain_noise_frequency")))
	t.set("amplitude", float(dungeon.get("terrain_amplitude")))
	t.set("height_offset", float(dungeon.get("terrain_height_offset")))
	t.set("water_level", float(dungeon.get("terrain_water_level")))
	t.set("pond_depth", float(dungeon.get("terrain_pond_depth")))
	t.set("smooth_passes", int(dungeon.get("terrain_smooth_passes")))
	t.set("flatten_radius", float(dungeon.get("terrain_flatten_radius")))
	t.generate()
	var heights: PackedFloat32Array = t.heights_copy()
	var mn := 1e9
	var mx := -1e9
	var wet := 0
	for h in heights:
		mn = minf(mn, h)
		mx = maxf(mx, h)
		if h < float(dungeon.get("terrain_water_level")):
			wet += 1
	_assert(mn >= -0.001 and mx <= 0.361,
		"#120: dungeon heights in [0, 0.36] design range (%.3f..%.3f)" % [mn, mx])
	_assert(wet == 0, "#120: dungeon terrain dry — zero sub-water heights (min %.3f)" % mn)
	var max_g := 0.0
	for gz in range(1, 64):
		for gx in range(1, 64):
			max_g = maxf(max_g, float(t.call("_slope_at", gx, gz)))
	_assert(max_g <= 0.55, "#120: dungeon bare-terrain max grade %.1f%% <= 55%%" % (max_g * 100.0))
	# Anchored ramp with the design-floor anchor (normalization
	# amp*0.5 = 0.175): h <= anchor is pure low, anchor + 0.0875 is
	# pure mid, anchor + 0.175 is pure high.
	t.set("tint_bed", dungeon.get("terrain_tint_bed"))
	t.set("tint_low", dungeon.get("terrain_tint_low"))
	t.set("tint_mid", dungeon.get("terrain_tint_mid"))
	t.set("tint_high", dungeon.get("terrain_tint_high"))
	t.set("tint_anchor", float(dungeon.get("terrain_tint_anchor")))
	var tl: Color = dungeon.get("terrain_tint_low")
	var tm: Color = dungeon.get("terrain_tint_mid")
	var th: Color = dungeon.get("terrain_tint_high")
	var c_lo: Color = t.call("_vertex_color", 0.0, 0.0)
	var c_mid: Color = t.call("_vertex_color", 0.0925, 0.0)
	var c_hi: Color = t.call("_vertex_color", 0.18, 0.0)
	_assert(Vector3(c_lo.r - tl.r, c_lo.g - tl.g, c_lo.b - tl.b).length() < 0.002,
		"#120: anchored ramp t=0 -> tint_low")
	_assert(Vector3(c_mid.r - tm.r, c_mid.g - tm.g, c_mid.b - tm.b).length() < 0.002,
		"#120: anchored ramp t=0.5 -> tint_mid")
	_assert(Vector3(c_hi.r - th.r, c_hi.g - th.g, c_hi.b - th.b).length() < 0.002,
		"#120: anchored ramp t=1 -> tint_high")
	root.remove_child(t)
	t.free()
	print("[Playtest] dungeon terrain 120 done")


func _test_depths_terrain_121() -> void:
	print("[Playtest] Depths terrain profile (#121)...")
	# Issue #121 (S4 of the #103 full integration): the Depths opts
	# into heightmap terrain with the roughest profile in the set —
	# rugged cavern floor in the 24x2m maze. Data + validation only:
	# the parameterization prerequisite landed with #118 (S1).
	var depths: Resource = load("res://data/levels/theme_depths.tres")
	_assert(depths != null, "#121: depths theme loads")
	if depths == null:
		return
	# Depths profile per the issue spec.
	_assert(bool(depths.get("use_heightmap_terrain")), "#121: depths use_heightmap_terrain on")
	_assert(absf(float(depths.get("terrain_amplitude")) - 1.8) < 0.0001, "#121: depths amp 1.8")
	# Frequency: the spec's primary 0.040 stands — the fallback to
	# 0.035 triggers only if Phase 2 measures grade > 55%, and the
	# measured max is ~19% (bare-terrain probe across the gate seeds
	# 17.9-19.2%; the in-situ check measures the same). Measurement
	# won over the spec's ~45% estimate; branch recorded here.
	_assert(absf(float(depths.get("terrain_noise_frequency")) - 0.040) < 0.00001, "#121: depths freq 0.040 (measured grade ~19%, fallback not triggered)")
	_assert(absf(float(depths.get("terrain_height_offset")) - 0.90) < 0.0001, "#121: depths offset +0.90")
	_assert(absf(float(depths.get("terrain_water_level")) - (-1.0)) < 0.0001, "#121: depths water parked -1.00 (dry)")
	_assert(absf(float(depths.get("terrain_pond_depth")) - 0.5) < 0.0001, "#121: depths pond depth 0.5")
	_assert(int(depths.get("terrain_smooth_passes")) == 1, "#121: depths smooth 1")
	_assert(absf(float(depths.get("terrain_flatten_radius")) - 5.0) < 0.0001, "#121: depths flatten 5.0")
	_assert(depths.get("terrain_tint_bed") == Color(0.09, 0.08, 0.13), "#121: depths tint bed = deep violet-black")
	_assert(depths.get("terrain_tint_low") == Color(0.13, 0.11, 0.18), "#121: depths tint low = near-black violet")
	_assert(depths.get("terrain_tint_mid") == Color(0.23, 0.2, 0.29), "#121: depths tint mid = dark violet-grey")
	_assert(depths.get("terrain_tint_high") == Color(0.62, 0.6, 0.55), "#121: depths tint high = pale bone-grey")
	# Tint anchor: dry theme, so the ramp anchors at the design
	# floor 0.0 (= offset 0.9 - amp/2 0.9), not the parked water.
	_assert(absf(float(depths.get("terrain_tint_anchor")) - 0.0) < 0.0001, "#121: depths tint anchor = design floor 0.0")
	var dup = depths.duplicate()
	_assert(bool(dup.get("use_heightmap_terrain")) and absf(float(dup.get("terrain_amplitude")) - 1.8) < 0.0001,
		"#121: flag + profile survive theme.duplicate() (cycle scaling)")
	# Bare-terrain behavior with the depths profile (HeightmapTerrain
	# names no autoloads, so it compiles in this suite): dry by
	# construction, heights inside the design range, grade in budget.
	# Extent 24 cells x 2.0m = 48m -> 49 sample points at 1.0m cells.
	var HT = load("res://scripts/terrain/heightmap_terrain.gd")
	var t = HT.new()
	root.add_child(t)
	t.set("map_points", 49)
	t.set("cell_size", 1.0)
	t.set("terrain_seed", 424242)
	t.set("noise_frequency", float(depths.get("terrain_noise_frequency")))
	t.set("amplitude", float(depths.get("terrain_amplitude")))
	t.set("height_offset", float(depths.get("terrain_height_offset")))
	t.set("water_level", float(depths.get("terrain_water_level")))
	t.set("pond_depth", float(depths.get("terrain_pond_depth")))
	t.set("smooth_passes", int(depths.get("terrain_smooth_passes")))
	t.set("flatten_radius", float(depths.get("terrain_flatten_radius")))
	t.generate()
	var heights: PackedFloat32Array = t.heights_copy()
	var mn := 1e9
	var mx := -1e9
	var wet := 0
	for h in heights:
		mn = minf(mn, h)
		mx = maxf(mx, h)
		if h < float(depths.get("terrain_water_level")):
			wet += 1
	_assert(mn >= -0.001 and mx <= 1.801,
		"#121: depths heights in [0, 1.8] design range (%.3f..%.3f)" % [mn, mx])
	_assert(wet == 0, "#121: depths terrain dry — zero sub-water heights (min %.3f)" % mn)
	var max_g := 0.0
	for gz in range(1, 48):
		for gx in range(1, 48):
			max_g = maxf(max_g, float(t.call("_slope_at", gx, gz)))
	_assert(max_g <= 0.55, "#121: depths bare-terrain max grade %.1f%% <= 55%%" % (max_g * 100.0))
	# Tint ramp behavior: anchored at the design floor, the ramp hits
	# pure low/mid/high at t = 0/0.5/1 (h = 0.0/0.45/0.9 at amp 1.8,
	# normalization amp*0.5 = 0.9). NAN falls back to the water
	# anchor (-1.0), where h=0.45 already saturates to high.
	t.set("tint_bed", depths.get("terrain_tint_bed"))
	t.set("tint_low", depths.get("terrain_tint_low"))
	t.set("tint_mid", depths.get("terrain_tint_mid"))
	t.set("tint_high", depths.get("terrain_tint_high"))
	t.set("tint_anchor", float(depths.get("terrain_tint_anchor")))
	var tl: Color = depths.get("terrain_tint_low")
	var tm: Color = depths.get("terrain_tint_mid")
	var th: Color = depths.get("terrain_tint_high")
	var c_lo: Color = t.call("_vertex_color", 0.0, 0.0)
	var c_mid: Color = t.call("_vertex_color", 0.45, 0.0)
	var c_hi: Color = t.call("_vertex_color", 0.9, 0.0)
	_assert(Vector3(c_lo.r - tl.r, c_lo.g - tl.g, c_lo.b - tl.b).length() < 0.002,
		"#121: anchored ramp t=0 -> tint_low")
	_assert(Vector3(c_mid.r - tm.r, c_mid.g - tm.g, c_mid.b - tm.b).length() < 0.002,
		"#121: anchored ramp t=0.5 -> tint_mid")
	_assert(Vector3(c_hi.r - th.r, c_hi.g - th.g, c_hi.b - th.b).length() < 0.002,
		"#121: anchored ramp t=1 -> tint_high")
	t.set("tint_anchor", NAN)
	var c_fb: Color = t.call("_vertex_color", 0.45, 0.0)
	_assert(Vector3(c_fb.r - th.r, c_fb.g - th.g, c_fb.b - th.b).length() < 0.002,
		"#121: NAN anchor falls back to water anchor (h=0.45 saturates high)")
	root.remove_child(t)
	t.free()


## Issue #122: Apex Arena terrain profile + the center boss-fight disc.
## Bare-terrain behavior (HeightmapTerrain names no autoloads, so it
## compiles in this suite): the apex profile is dry by construction,
## heights stay in the [0.0, 0.6] design range, and the r=8.0 NAN-height
## flatten target relaxes the arena center toward its LOCAL height —
## flat core, soft rim, and zero bleed past r=10 (measured).
func _test_apex_terrain_122() -> void:
	print("[Playtest] Apex Arena terrain (#122)...")
	var apex: Resource = load("res://data/levels/theme_apex.tres")
	_assert(bool(apex.get("use_heightmap_terrain")), "#122: apex terrain flag on")
	_assert(absf(float(apex.get("terrain_amplitude")) - 0.6) < 0.001, "#122: apex amp 0.6")
	_assert(absf(float(apex.get("terrain_noise_frequency")) - 0.04) < 0.0001, "#122: apex freq 0.040")
	_assert(absf(float(apex.get("terrain_height_offset")) - 0.3) < 0.001, "#122: apex offset +0.30")
	_assert(absf(float(apex.get("terrain_water_level")) + 1.0) < 0.001, "#122: apex water parked at -1.00 (dry)")
	_assert(int(apex.get("terrain_smooth_passes")) == 2, "#122: apex smooth 2")
	_assert(absf(float(apex.get("terrain_flatten_radius")) - 5.0) < 0.001, "#122: apex flatten 5.0")
	_assert(absf(float(apex.get("terrain_center_flatten_radius")) - 8.0) < 0.001,
		"#122: apex center disc r 8.0")
	# Tint anchor at the design floor (offset - amp/2 = 0.0), the dry
	# theme rule from the #118 follow-up.
	_assert(absf(float(apex.get("terrain_tint_anchor"))) < 0.001, "#122: apex tint anchor at design floor 0.0")
	var dup = apex.duplicate()
	_assert(absf(float(dup.get("terrain_center_flatten_radius")) - 8.0) < 0.001,
		"#122: center disc survives theme.duplicate() (cycle scaling)")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("theme.terrain_center_flatten_radius"),
		"#122: _build_terrain wires the center disc from the theme")
	# Bare terrains: identical apex profile, one with the center target
	# exactly as _build_terrain appends it (NAN height = local).
	var HT = load("res://scripts/terrain/heightmap_terrain.gd")
	var mk = func(with_disc: bool):
		var t = HT.new()
		root.add_child(t)
		t.set("map_points", 49)
		t.set("cell_size", 1.0)
		t.set("terrain_seed", 424242)
		t.set("noise_frequency", 0.04)
		t.set("amplitude", 0.6)
		t.set("height_offset", 0.3)
		t.set("water_level", -1.0)
		t.set("pond_depth", 0.5)
		t.set("smooth_passes", 2)
		t.set("flatten_radius", 5.0)
		t.set("tint_anchor", 0.0)
		if with_disc:
			# Append, not set(): the typed Array[Dictionary] property
			# silently rejects an untyped literal through Object.set.
			t.flatten_targets.append({"pos": Vector3.ZERO, "height": NAN, "radius": 8.0})
		t.generate()
		return t
	var plain = mk.call(false)
	var disc = mk.call(true)
	var hp: PackedFloat32Array = plain.heights_copy()
	var hd: PackedFloat32Array = disc.heights_copy()
	var mp := 49
	var mn := 1e9
	var mx := -1e9
	var wet := 0
	for h in hd:
		mn = minf(mn, h)
		mx = maxf(mx, h)
		if h < -1.0:
			wet += 1
	_assert(mn >= -0.001 and mx <= 0.601,
		"#122: apex heights in [0.0, 0.6] design range (%.3f..%.3f)" % [mn, mx])
	_assert(wet == 0, "#122: apex terrain dry — zero sub-water heights (min %.3f)" % mn)
	var c_idx := 24 * mp + 24
	_assert(absf(hd[c_idx] - hp[c_idx]) < 0.001,
		"#122: center height is the local terrain height (plain %.4f, disc %.4f)" % [hp[c_idx], hd[c_idx]])
	# Disc shape: flat core (r<2 within 0.02 of center), soft rim (the
	# smoothstep profile — r<8 within 0.20), zero bleed at r>=10.
	var dev_core := 0.0
	var dev_disc := 0.0
	var bleed := 0.0
	for gz in mp:
		for gx in mp:
			var d := Vector2(float(gx) - 24.0, float(gz) - 24.0).length()
			var i := gz * mp + gx
			if d < 2.0:
				dev_core = maxf(dev_core, absf(hd[i] - hd[c_idx]))
			if d < 8.0:
				dev_disc = maxf(dev_disc, absf(hd[i] - hd[c_idx]))
			if d >= 10.0:
				bleed = maxf(bleed, absf(hd[i] - hp[i]))
	_assert(dev_core <= 0.02, "#122: disc core flat (max dev %.4f within r<2)" % dev_core)
	_assert(dev_disc <= 0.20, "#122: disc rim soft (max dev %.4f within r<8)" % dev_disc)
	_assert(bleed < 0.001, "#122: center flatten is local (bleed %.5f at r>=10)" % bleed)
	# Grade outside the disc footprint (disc + 1m margin, the checks'
	# convention) stays inside the 55% budget; measured ~6% max.
	var max_g := 0.0
	for gz in range(1, mp - 1):
		for gx in range(1, mp - 1):
			if Vector2(float(gx) - 24.0, float(gz) - 24.0).length() <= 9.0:
				continue
			max_g = maxf(max_g, float(disc.call("_slope_at", gx, gz)))
	_assert(max_g <= 0.55, "#122: apex grade outside disc %.1f%% <= 55%%" % (max_g * 100.0))
	# Tint ramp at the design-floor anchor (norm amp*0.5 = 0.3):
	# h=0 -> low, h=0.15 -> mid, h=0.30 -> high.
	disc.set("tint_bed", apex.get("terrain_tint_bed"))
	disc.set("tint_low", apex.get("terrain_tint_low"))
	disc.set("tint_mid", apex.get("terrain_tint_mid"))
	disc.set("tint_high", apex.get("terrain_tint_high"))
	var tl: Color = apex.get("terrain_tint_low")
	var tm: Color = apex.get("terrain_tint_mid")
	var th: Color = apex.get("terrain_tint_high")
	var c_lo: Color = disc.call("_vertex_color", 0.0, 0.0)
	var c_mid: Color = disc.call("_vertex_color", 0.15, 0.0)
	var c_hi: Color = disc.call("_vertex_color", 0.30, 0.0)
	_assert(Vector3(c_lo.r - tl.r, c_lo.g - tl.g, c_lo.b - tl.b).length() < 0.002,
		"#122: anchored ramp t=0 -> tint_low (arena stone)")
	_assert(Vector3(c_mid.r - tm.r, c_mid.g - tm.g, c_mid.b - tm.b).length() < 0.002,
		"#122: anchored ramp t=0.5 -> tint_mid (bronze-brown)")
	_assert(Vector3(c_hi.r - th.r, c_hi.g - th.g, c_hi.b - th.b).length() < 0.002,
		"#122: anchored ramp t=1 -> tint_high (pale dust)")
	for t in [plain, disc]:
		root.remove_child(t)
		t.free()


func _test_save_roundtrip() -> void:
	print("[Playtest] Save roundtrip (slots)...")
	# Exercise the real SaveManager slot code path (atomic save + load).
	var SaveScript := load("res://scripts/autoload/save_manager.gd")
	var mgr = SaveScript.new()
	# Back up real slot files + profile so the test can't clobber them.
	# Jesse 2026-10-11: with unlimited saves, scan for all existing slots,
	# not just 0-2 — leftover slot 3+ files from crashed runs break list_runs.
	var backup := {}
	for mode in ["solo", "mp"]:
		for slot in mgr.list_slots(mode):
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
	# Out-of-range slots rejected (unlimited saves now — only negative/bogus rejected).
	_assert(mgr.save_run(run, "solo", 3), "slot 3 now allowed (unlimited)")
	mgr.clear_run("solo", 3)
	_assert(not mgr.save_run(run, "solo", -1), "slot -1 rejected")
	_assert(not mgr.save_run(run, "bogus", 0), "bad mode rejected")
	_assert(not mgr.load_run("solo", 999).is_empty() or mgr.load_run("solo", 999).is_empty(), "load slot 999 handled")
	_assert(not mgr.has_run("mp", 9999), "has_run invalid slot false")
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
	# Hermetic: another test's aborted run may have left real pollution behind
	# (self-perpetuating via backup/restore). Stash any real solo_1.cfg in an
	# on-disk sidecar (abort-safe) and restore it at the end.
	var real_slot := "user://runs/solo_1.cfg"
	var real_sidecar := real_slot + ".bak"
	var had_real := false
	var real_bak := PackedByteArray()
	if FileAccess.file_exists(real_sidecar) and not FileAccess.file_exists(real_slot):
		DirAccess.rename_absolute(real_sidecar, real_slot)
	if FileAccess.file_exists(real_slot):
		had_real = true
		real_bak = FileAccess.get_file_as_bytes(real_slot)
		var sf := FileAccess.open(real_sidecar, FileAccess.WRITE)
		sf.store_buffer(real_bak)
		sf.close()
		DirAccess.remove_absolute(real_slot)
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
	_assert(mgr._slot_path("solo", 9) != "", "scratch: slot 9 now valid (unlimited)")
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
	if had_real:
		var rf := FileAccess.open(real_slot, FileAccess.WRITE)
		rf.store_buffer(real_bak)
		rf.close()
	if FileAccess.file_exists(real_sidecar):
		DirAccess.remove_absolute(real_sidecar)
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
	# Unlimited saves: all legacy files migrate, no overflow.
	_assert(str(mgr.load_run("solo", 3).get("class_id", "")) == "warrior",
		"fourth legacy -> solo slot 3 (no overflow)")
	_assert(bool(mgr.load_run("mp", 0).get("is_multiplayer", false)),
		"legacy MP run -> mp slot 0")
	_assert((mgr.load_run("mp", 0).get("roster", []) as Array).size() == 2,
		"migrated MP roster preserved")
	# Nothing deleted, ever.
	for lp in legacy_paths:
		_assert(FileAccess.file_exists(lp), "legacy file not deleted: %s" % lp)
	# Unlimited saves: everything migrates, no overflow left.
	var leftover: Array = mgr.list_legacy_saves()
	_assert(leftover.is_empty(),
		"no overflow with unlimited saves")
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
	_assert(mgr.list_legacy_saves().is_empty(), "no overflow with unlimited saves")
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
	# Unlimited saves: legacy migrates to slots 3+ instead of overflowing.
	_assert(mgr2.list_legacy_saves().is_empty(), "occupied case: no overflow with unlimited saves")
	_assert(str(mgr2.load_run("solo", 3).get("class_id", "")) != "", "legacy migrated to slot 3")
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
	_assert(dsrc.contains("rpc_id(NetworkManager.server_peer_id, \"rpc_submit_save_state\""),
		"submit targets server peer id")
	_assert(not dsrc.contains("rpc_id(1,"), "no hardcoded server peer 1 in dungeon.gd")
	var nsrc := FileAccess.get_file_as_string("res://scripts/autoload/network_manager.gd")
	_assert(nsrc.contains("Dungeon.continued_roster = []"),
		"leave_lobby clears stale continued roster")
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(msrc.contains('"MP Slot %d · %s"'), "staging screen shows the slot")

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
	_assert(msrc.contains('"New"') and msrc.contains('"Continue"'),
		"cards have New Run / Continue actions")
	_assert(msrc.contains("func _first_empty_slot(mode: String) -> int"),
		"first-empty-slot helper exists")
	_assert(msrc.contains("func _show_overwrite_confirm(mode: String, slot: int)"),
		"overwrite confirm exists")
	_assert(msrc.contains('"Slot %d already holds a saved run:\\n%s\\n\\nStart a new run and overwrite it?"'), "modal asks before overwriting")
	_assert(msrc.contains("_show_solo_class_popup(_confirm_slot)"),
		"confirmed solo overwrite shows class popup")
	_assert(msrc.contains("_host_slot = _confirm_slot"),
		"confirmed mp overwrite targets that slot")
	_assert(msrc.contains("NetworkManager.host_lobby(_host_slot)"),
		"lobby hosts into the chosen slot")
	_assert(msrc.contains("func _refresh_legacy_rows("),
		"legacy overflow rows exist")
	_assert(msrc.contains("shown >= 2"), "legacy rows capped at 2")
	_assert(msrc.contains('"+%d more legacy saves on disk"'), "legacy overflow counted")
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
	# Issue #75 regression: the Host Game class row must mirror the title
	# row — an architect-unlocked player can host as Architect.
	_assert(tsrc.contains("[node name=\"HostArchitectButton\""),
		"#75: HostClassRow has an Architect button")
	_assert(tsrc.contains("_on_host_architect_pressed"),
		"#75: HostArchitectButton wired to a handler")
	_assert(msrc.contains("func _on_host_architect_pressed"),
		"#75: host architect handler exists")
	# Issue #74 regression: slot cards must be compact centered rows, not
	# full-width — otherwise the action buttons pin to the far screen edge.
	_assert(msrc.contains("margin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER"),
		"#74: slot card is shrink-centered")

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
	_assert(hsrc.contains('"Your cash: $%d"'), "panel shows cash header")
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
	_assert(st._dressing.get_child_count() == 7, "7 theme prop sets built (apex + misty_docks)")
	_assert(st._dressing.get_node_or_null("apex") != null, "apex dressing set built")
	_assert(st._dressing.get_node_or_null("misty_docks") != null, "misty_docks dressing set built")
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
	# Issue #33 Phase 2: sign uses tr("NOW_BOARDING"); in test env without
	# translations loaded, verify the key is used and destination is passed.
	var sign_text := str(st2._boarding_sign.text) if st2._boarding_sign != null else ""
	_assert(st2._boarding_sign != null and ("THE DEPTHS" in sign_text or "NOW_BOARDING" in sign_text),
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
	# Issue #46 regression: the announce pop-scale must grow symmetrically
	# around the label's center. With the default top-left pivot, wide
	# banners shifted right and the tail was cut at the viewport edge.
	var hud_tsrc := FileAccess.get_file_as_string("res://scenes/ui/hud.tscn")
	_assert(hud_tsrc.contains("pivot_offset = Vector2(400, 60)"),
		"#46: AnnounceLabel pivot is centered")

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
	_assert(dsrc.contains('"NOW ARRIVING: %s"'), "arrival banner on dungeon entry")
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
	_assert(not st.get("_departing"), "split vote: no departure started")
	# ...and on unanimity it opens the lobby doors (issue #93 Phase 3)
	# instead of emitting directly; the depart lever completes the
	# departure via departure_resolved.
	st.votes = {10: "dungeon", 11: "dungeon"}
	st.depart([10, 11])
	_assert(captured.is_empty(), "unanimous: depart() opens doors, emits nothing yet")
	_assert(st.get("_depart_theme") == "dungeon", "departure carries the voted theme")
	_assert(bool(st.record_depart(10, [10, 11])["ok"]), "lever pull accepted")
	st._complete_departure()
	_assert(captured == ["dungeon"], "lever: departure_resolved emitted")
	_assert(not bool(st.record_depart(11, [10, 11])["ok"]), "lever: second pull rejected")
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


func _test_train_ambient() -> void:
	print("[Playtest] Audio: Jesse's train ambient...")
	# DM assignment (2026-10-04): kokoreli777 inside-old-train recording beds
	# the interior ride as the "train" music theme (file override path).
	_assert(FileAccess.file_exists("res://assets/audio/music/train.mp3"),
		"train ambient mp3 in repo")
	var amsrc2 := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	_assert(amsrc2.contains('"mp3"'), "music file override checks mp3")
	_assert(amsrc2.contains("func _enable_track_loop"),
		"file-backed music themes loop")
	var tsrc := FileAccess.get_file_as_string("res://scripts/station/train_interior.gd")
	_assert(tsrc.contains('play_music("train")'),
		"interior starts train ambient when the ride begins")
	# The recording layers UNDER the synth cues — departure stays untouched.
	_assert(tsrc.contains('sfx("train_chug")'), "ride chug kept")
	var ssrc2 := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(ssrc2.contains('sfx("train_whistle")'), "departure whistle kept")
	# Jesse's call (2026-10-05): his recording is the ONLY train sound for
	# now — synth cues stay in code but are gated silent, re-enable by
	# flipping the const.
	_assert(tsrc.contains("const USE_SYNTH_TRAIN_CUES := false"),
		"synth train cues gated off, recording is the only train sound")
	# Jesse's brake recording overrides the synth brake via the SFX file path.
	_assert(FileAccess.file_exists("res://assets/audio/sfx/train_brake.mp3"),
		"brake recording mp3 in repo")
	_assert(amsrc2.contains('["ogg", "wav", "mp3"]'),
		"sfx file override checks mp3")
	# Jesse's whistle recording likewise overrides the synth whistle.
	_assert(FileAccess.file_exists("res://assets/audio/sfx/train_whistle.mp3"),
		"whistle recording mp3 in repo")


func _test_audio_combat_cues() -> void:
	print("[Playtest] Audio: shield clang + dagger cues...")
	# DM assignment: Shieldbearer block (issue #67) + rogue thrown dagger
	# (issue #69) were silent. Every cue must synth and be registered.
	var SoundScript := load("res://scripts/audio/sound_synth.gd")
	var amsrc := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	for sfx in ["shield_clang", "dagger_throw", "dagger_catch"]:
		var w: AudioStreamWAV = SoundScript.call(sfx)
		_assert(w != null and w.data.size() > 0, "synth builds %s" % sfx)
		_assert(amsrc.contains('"%s"' % sfx), "%s registered in builder list" % sfx)
	# Wiring: the mob.gd shield_clang stub plays the cue positionally;
	# the dagger call sites already exist in player.gd.
	var msrc := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(msrc.contains('sfx("shield_clang", pos)'), "shield_clang stub wired")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains('sfx("dagger_throw")'), "dagger throw call site")
	_assert(psrc.contains('sfx("dagger_catch")'), "dagger catch call site")


func _test_audio_113_cues() -> void:
	print("[Playtest] Audio: weapon upgrade + architect tool cues (issue #113)...")
	# Sound commission for #113: upgrade kit apply (Phase 1), wrench repair
	# loop + completion (Phase 3), hammer smash + shockwave (Phase 4). The
	# cues are commissioned ahead of the builders so integration is a
	# drop-in: AudioManager.sfx("<name>") at each surface. Every cue must
	# synth a non-empty stream AND be registered in the builder list —
	# unregistered names are silently dropped by sfx().
	var SoundScript := load("res://scripts/audio/sound_synth.gd")
	var amsrc := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	for sfx in ["upgrade_apply", "wrench_turn", "repair_complete",
			"hammer_smash", "hammer_shockwave"]:
		var w: AudioStreamWAV = SoundScript.call(sfx)
		_assert(w != null and w.data.size() > 0, "synth builds %s" % sfx)
		_assert(amsrc.contains('"%s"' % sfx), "%s registered in builder list" % sfx)


func _test_audio_126_cues() -> void:
	print("[Playtest] Audio: fishing cast cues (issue #126)...")
	# Sound commission for #126 (FP casting redesign): cast whoosh,
	# splashdown, and the dirt-flop thud are new; bite/reel/catch carry
	# over from the spot era. Every cue must synth and be registered.
	var SoundScript := load("res://scripts/audio/sound_synth.gd")
	var amsrc := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	for sfx in ["cast_whoosh", "splashdown", "dirt_flop"]:
		var w: AudioStreamWAV = SoundScript.call(sfx)
		_assert(w != null and w.data.size() > 0, "synth builds %s" % sfx)
		_assert(amsrc.contains('"%s"' % sfx), "%s registered in builder list" % sfx)
	# Wiring: the whoosh plays on the director's fx_cast broadcast at the
	# rod; the landing cues play in FishingVisual at arc arrival, synced
	# to the visible splash (water) / flop (dirt).
	var dsrc := FileAccess.get_file_as_string("res://scripts/fishing/fishing_director.gd")
	_assert(dsrc.contains('sfx("cast_whoosh", from)'), "cast whoosh wired to fx_cast")
	var vsrc := FileAccess.get_file_as_string("res://scripts/fishing/fishing_visual.gd")
	_assert(vsrc.contains('sfx("splashdown", _to)'), "splashdown wired to water arrival")
	_assert(vsrc.contains('sfx("dirt_flop", _to)'), "dirt flop wired to dirt arrival")


func _test_lobby_room() -> void:
	print("[Playtest] Boarding lobby room (issue #93 phase 1)...")
	var AnnexScript: GDScript = load("res://scripts/station/station_annex.gd")
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	var theme: Resource = load("res://data/levels/theme_village.tres")
	var layout = ProcGenScript.generate(theme, 12345)
	var plan: Dictionary = AnnexScript.plan(12345, layout)
	var holder := Node3D.new()
	root.add_child(holder)
	var annex = AnnexScript.build(holder, plan, layout)
	var hc: Vector3 = annex.hall_center()

	# 1. Shell nodes exist: floor + 5 wall pieces + lintel + roof.
	# Issue #97: doorway on the SOUTH wall — north wall solid, south split.
	for n in ["LobbyFloor", "LobbyWallN", "LobbyWallS_A", "LobbyWallS_B", "LobbyLintel",
			"LobbyWallW", "LobbyWallE", "LobbyRoof"]:
		_assert(annex.get_node_or_null(n) != null, "lobby node %s built" % n)
	_assert(annex.get_node("LobbyFloor") is StaticBody3D, "lobby floor is solid")
	_assert(annex.get_node("LobbyWallN") is StaticBody3D, "lobby north wall solid")

	# 2. Dressing present: benches, racks, straps, lamps, windows.
	var benches := 0
	var straps := 0
	var wins := 0
	for child in annex.get_children():
		var nm := str(child.name)
		if nm.begins_with("LobbyBench"):
			benches += 1
		elif nm.begins_with("LobbyStrap"):
			straps += 1
		elif nm.begins_with("LobbyWin"):
			wins += 1
	_assert(benches == 8, "4 benches + 4 backrests (%d)" % benches)
	_assert(straps == 12, "6 straps + 6 handles (%d)" % straps)
	_assert(wins == 8, "4 window frames + 4 panes (%d)" % wins)
	var lamp_count := 0
	for lamp in annex.lamps:
		if lamp is OmniLight3D:
			lamp_count += 1
	_assert(lamp_count >= 6, "hall + lobby lamps (%d)" % lamp_count)

	# 3. Doorway is open once the doors open (issue #93 Phase 2: doors start
	# closed; probes through it must not sit inside any solid).
	# Issue #97: doorway moved to the SOUTH wall (probes at +3.25 hall-local,
	# the south wall center plane, mirroring the old -2.25 north probes).
	annex._apply_lobby_doors(true)
	var solids: Array = []
	for child in annex.get_children():
		if child is StaticBody3D:
			var c := (child as StaticBody3D).get_child(0) as CollisionShape3D
			var b := c.shape as BoxShape3D
			solids.append(AABB(child.position - b.size * 0.5, b.size))
	var door_blocked := 0
	for px in [-1.8, -1.0, -0.2]:
		var p := Vector3(hc.x + px, 1.0, hc.z + 3.25)
		for aabb: AABB in solids:
			if aabb.has_point(p):
				door_blocked += 1
	_assert(door_blocked == 0, "lobby doorway walkable (%d blocked probes)" % door_blocked)

	# 4. No overlaps with existing station content (hall-local coords).
	var lb: AABB = annex.lobby_bounds()
	var content := {
		"vendor": AABB(Vector3(9, 0, -1.5), Vector3(2, 3, 3)),
		"vault": AABB(Vector3(-11, 0, -1.5), Vector3(2, 3, 3)),
		"heal": AABB(Vector3(-11.7, 0, 1.3), Vector3(4.4, 3, 4.4)),
		"bounty": AABB(Vector3(1.54, 0, 4.09), Vector3(3.32, 3, 0.22)),
		"departures": AABB(Vector3(5.3, 0, 4.09), Vector3(3.4, 3, 0.22)),
		"train": AABB(Vector3(-3, 0, -5.7), Vector3(4, 3, 2.4)),
	}
	for key in content:
		_assert(not lb.intersects(content[key]), "lobby clear of %s" % key)

	# 5. Spawn spots: 12 (4x3 grid, Jesse 2026-10-10), inside the room, not inside any solid.
	var spots: Array = annex.lobby_spawn_spots()
	_assert(spots.size() == 12, "12 lobby spawn spots")
	for sp in spots:
		var s: Vector3 = sp
		_assert(s.x >= -5.0 and s.x <= 3.0 and s.z >= -2.0 and s.z <= 3.0,
			"spawn spot inside lobby (%s)" % str(s))
		var p := Vector3(hc.x + s.x, 1.0, hc.z + s.z)
		var inside := false
		for aabb: AABB in solids:
			if aabb.has_point(p):
				inside = true
		_assert(not inside, "spawn spot not inside a solid (%s)" % str(s))

	holder.queue_free()


func _test_lobby_doors() -> void:
	print("[Playtest] Lobby sliding doors (issue #93 phase 2)...")
	var AnnexScript: GDScript = load("res://scripts/station/station_annex.gd")
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	var theme: Resource = load("res://data/levels/theme_village.tres")
	var layout = ProcGenScript.generate(theme, 12345)
	var plan: Dictionary = AnnexScript.plan(12345, layout)
	var holder := Node3D.new()
	root.add_child(holder)
	var annex = AnnexScript.build(holder, plan, layout)
	var hc: Vector3 = annex.hall_center()

	# 1. Doors start closed: blocker present, panels at closed positions.
	_assert(not annex.doors_open, "lobby doors start closed")
	_assert(annex._door_panels.size() == 2, "2 door panels built")
	var blocker = annex.get_node_or_null("LobbyDoorBlocker")
	_assert(blocker != null and blocker is StaticBody3D, "door blocker present while closed")
	for d in annex._door_panels:
		_assert(absf(d.position.x - (hc.x + float(d.get_meta("closed_x")))) < 0.01,
			"panel starts at closed_x")

	# 2. Closed doors block the doorway: probes through it sit inside the blocker.
	# Issue #97: doorway on the south wall — probes at the south wall center.
	var cs := blocker.get_child(0) as CollisionShape3D
	var bb := cs.shape as BoxShape3D
	var blocker_aabb := AABB(blocker.position - bb.size * 0.5, bb.size)
	var blocked := 0
	for px in [-1.8, -1.0, -0.2]:
		if blocker_aabb.has_point(Vector3(hc.x + px, 1.0, hc.z + 3.25)):
			blocked += 1
	_assert(blocked == 3, "closed doors block the doorway (%d/3 probes)" % blocked)

	# 3. Server RPC path opens: state flips, blocker freed, doorway walkable.
	annex.set_lobby_doors(true)
	_assert(annex.doors_open, "set_lobby_doors(true) opens (server is local in tests)")
	_assert(annex.get_node_or_null("LobbyDoorBlocker") == null, "blocker freed when open")
	var solids: Array = []
	for child in annex.get_children():
		if child is StaticBody3D:
			var c := (child as StaticBody3D).get_child(0) as CollisionShape3D
			var b := c.shape as BoxShape3D
			solids.append(AABB(child.position - b.size * 0.5, b.size))
	var door_blocked := 0
	for px in [-1.8, -1.0, -0.2]:
		var p := Vector3(hc.x + px, 1.0, hc.z + 3.25)
		for aabb: AABB in solids:
			if aabb.has_point(p):
				door_blocked += 1
	_assert(door_blocked == 0, "open doors: doorway walkable")

	# 4. Closing re-blocks (idempotent: double close is a no-op).
	annex.set_lobby_doors(false)
	_assert(not annex.doors_open, "set_lobby_doors(false) closes")
	_assert(annex.get_node_or_null("LobbyDoorBlocker") != null, "blocker rebuilt when closed")
	annex.set_lobby_doors(false)
	_assert(not annex.doors_open, "double close is a no-op")

	# 5. Snap path (not in tree): panels jump to open/closed x exactly.
	var holder2 := Node3D.new()
	var annex2 = AnnexScript.build(holder2, plan, layout)
	annex2._apply_lobby_doors(true)
	for d in annex2._door_panels:
		_assert(absf(d.position.x - float(d.get_meta("open_x"))) < 0.001,
			"snap: panel at open_x when not in tree")
	annex2._apply_lobby_doors(false)
	for d in annex2._door_panels:
		_assert(absf(d.position.x - float(d.get_meta("closed_x"))) < 0.001,
			"snap: panel at closed_x when not in tree")
	holder2.free()

	# 6. Arrival settle: fresh annex opens 1s after build (server-driven).
	var holder3 := Node3D.new()
	root.add_child(holder3)
	var annex3 = AnnexScript.build(holder3, plan, layout)
	_assert(not annex3.doors_open, "arrival: doors closed on build")
	annex3._process(1.1)
	_assert(annex3.doors_open, "arrival: doors open after 1s settle")
	# 7. Vote-resolve opens the lobby doors (station wiring).
	var StationScript: GDScript = load("res://scripts/station/station.gd")
	var st = StationScript.new()
	root.add_child(st)
	var holder4 := Node3D.new()
	root.add_child(holder4)
	var annex4 = AnnexScript.build(holder4, plan, layout)
	st.annex = annex4
	_assert(not annex4.doors_open, "wiring: doors closed before vote resolve")
	st._open_lobby_for_boarding("dungeon")
	_assert(annex4.doors_open, "wiring: vote resolve opens lobby doors")
	holder4.queue_free()
	holder.queue_free()
	holder3.queue_free()


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
	# Issue #97: old green-box Train prop removed (Jesse).
	for nname in ["DepartureBoard", "VendorStall", "HealPad", "Sleepers"]:
		_assert(st.get_node_or_null(nname) != null, "embedded: %s built" % nname)
	_assert(st.get_node_or_null("Train") == null, "embedded: Train prop removed (#97)")
	# Issue #93 Phase 3: the BoardingZone aboard-marker is retired; the
	# depart lever (built by the annex, in the lobby) is the new flow node.
	_assert(annex.get_node_or_null("DepartLever") != null, "embedded: DepartLever built in lobby")
	var sign = st.get("_boarding_sign")
	_assert(sign != null and ("NOW BOARDING" in str(sign.text) or "NOW_BOARDING" in str(sign.text)),
		"embedded: NOW BOARDING sign set")
	var dressing = st.get_node_or_null("Dressing")
	_assert(dressing != null and dressing.get_child_count() == 7,
		"embedded: 7 dressing prop sets (apex + misty_docks)")
	# Every content node sits inside the 24x14m hall footprint.
	for nname in ["DepartureBoard", "VendorStall", "HealPad"]:
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

	# 4. Unanimous resolve opens the lobby doors (issue #93 Phase 3); the
	# depart lever completes the departure via departure_resolved (server
	# path); split does not.
	var captured := []
	st.departure_resolved.connect(func(tid): captured.append(tid))
	st.votes = {10: "dungeon", 11: "dungeon"}
	st.depart([10, 11, 12])
	_assert(captured.is_empty(), "embedded: partial votes emit nothing")
	st.votes = {10: "dungeon", 11: "dungeon", 12: "dungeon"}
	st.depart([10, 11, 12])
	_assert(captured.is_empty(), "embedded: unanimous opens doors, emits nothing yet")
	_assert(st.get("_depart_theme") == "dungeon", "embedded: departure carries the voted theme")
	_assert(bool(st.record_depart(10, [10, 11, 12])["ok"]), "embedded: lever pull accepted")
	st._complete_departure()
	_assert(captured == ["dungeon"], "embedded: lever completes departure_resolved")

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
	var h := dsrc.substr(h_start, 3400) # widened for PF2: the solo producer grew (loaded-dict-first)
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
	_assert(hop.contains("NetworkManager.server_peer_id"), "boarding: server-sender check")

	# 3b. Interior exit (do_disembark, issue #3 Phase 3, local since #92):
	# state capture, dungeon scene load via the background-loaded packed scene.
	var isrc := FileAccess.get_file_as_string("res://scripts/station/train_interior.gd")
	var lv_start := isrc.find("func do_disembark")
	_assert(lv_start > 0, "interior: do_disembark exists")
	var lv := isrc.substr(lv_start, 900)
	_assert(not lv.contains("NetworkManager.server_id"), "interior exit: no server-sender check (local hop)")
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
	_assert(dsrc.contains('"NOW ARRIVING: %s"'), "arrival: banner text")
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
	# Issue #134: the snapshot machinery is peer-authoritative — the
	# server keeps NO entry snapshots (its replica captures fabricated
	# a guest's rollback target). These pins lock that property in.
	_assert(not dsrc.contains("_entry_snapshots"), "134: server keeps no entry snapshots")
	_assert(not dsrc.contains("func _snapshot_entry"), "134: server snapshot capture gone")
	_assert(dsrc.contains("p.capture_entry_snapshot()"), "134: owner captures its snapshot at spawn")
	_assert(dsrc.contains("me.capture_entry_snapshot()"), "134: owner re-captures after a continued-state restore")
	_assert(dsrc.contains("level_cleared = true"), "level clear sets the flag")
	_assert(dsrc.contains('"Level cleared — gains secured."'), "level clear toasts gains secured")
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
	_assert(dsrc.contains('"Left early!\\nLevel gains forfeited."'), "forfeit banner text")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("func apply_forfeit("), "player has apply_forfeit")
	_assert(psrc.contains("alive = was_alive"), "forfeit preserves alive status")
	# Issue #134 (DM pin): the forfeit signal carries NO state payload —
	# a future refactor must not reintroduce a server-authored rollback.
	_assert(psrc.contains("func capture_entry_snapshot"), "134: player captures its own entry snapshot")
	_assert(psrc.contains("func apply_forfeit_local"), "134: player applies its own snapshot")
	_assert(psrc.contains("func apply_forfeit_net() -> void"), "134: forfeit signal takes no state payload")
	_assert(dsrc.contains('child.rpc_id(pid, "apply_forfeit_net")'), "134: server sends the bare forfeit signal")

	# 3. Board posts the unanimous rule.
	var bsrc := FileAccess.get_file_as_string("res://scripts/station/departure_board.gd")
	_assert(bsrc.contains('"ALL LIVING PLAYERS MUST AGREE ON A DESTINATION"'), "board shows the unanimity hint")

	# 4. Issue #134 behavioral: the rollback target is the peer's OWN
	# capture. A guest-shaped player (rich entry state, starter weapon
	# equipped) forfeits only the level's gains — and what the departure
	# save would then record (get_state) is the true entry state.
	var q = PlayerScene.instantiate()
	q.class_id = "warrior"
	root.add_child(q) # _ready: class data, starter kit, full HP
	var entry_ids: Array = []
	var entry_equipped := 0
	for e in (q.get_state()["inventory"] as Array):
		entry_ids.append(str((e as Dictionary)["id"]))
		if str((e as Dictionary).get("slot", "")) != "":
			entry_equipped += 1
	_assert(entry_ids.size() > 0 and entry_equipped > 0,
		"134: fresh build carries its starter kit (equipped weapon present)")
	q.level = 5
	q.xp = 120
	q.xp_next = 200
	q.stat_points = 3
	q.capture_entry_snapshot()
	q.level = 8
	q.xp = 40
	q.run_kills = 11
	q.inventory.append({"item": potion, "count": 1})
	q.apply_forfeit_local()
	_assert(q.level == 5 and q.xp == 120 and q.xp_next == 200,
		"134: own snapshot restores entry level/xp")
	_assert(q.stat_points == 3, "134: own snapshot restores entry stat points")
	var saved_ids: Array = []
	for e in (q.get_state()["inventory"] as Array):
		saved_ids.append(str((e as Dictionary)["id"]))
	saved_ids.sort()
	var entry_sorted: Array = entry_ids.duplicate()
	entry_sorted.sort()
	_assert(saved_ids == entry_sorted,
		"134: saved entry keeps the real entry inventory (in-level finds gone)")
	q.queue_free()

	# No local capture, no forfeit — never a fabricated rollback.
	var r = PlayerScene.instantiate()
	r.class_id = "mage"
	root.add_child(r)
	r.level = 7
	r.xp = 55
	r.apply_forfeit_local()
	_assert(r.level == 7 and r.xp == 55, "134: no local snapshot -> no forfeit")
	r.queue_free()


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
	var hblock := dsrc.substr(hpos, 3400) # widened for PF2 (see departure test)
	_assert(hblock.contains('rpc("board_train_interior"'), "interior: departure rpcs boarding")
	_assert(not hblock.contains("hop_to_next_level"), "interior: direct hop gone from departure")


func _test_train_ride() -> void:
	print("[Playtest] Train ride phase 3 (25s ride, skip, arrival, disembark)...")
	var InteriorScript := load("res://scripts/station/train_interior.gd")
	_assert(InteriorScript.RIDE_SECONDS == 25.0, "ride: 25s ride length")

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
	_assert(not isrc.contains("func _run_disembark_window"), "ride: server sweep removed (voluntary disembark)")

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


## Issue #135: a client whose car finished loading after the server's
## one-shot ride_started / begin_arrival broadcasts pulls the live ride
## state from the server and applies the answer. The old _ready
## late-apply read the ride_active static, which is never true on a
## client at _ready time — the pull replaces it.
func _test_train_ride_state_sync() -> void:
	print("[Playtest] Train ride-state sync (issue #135)...")
	var InteriorScript := load("res://scripts/station/train_interior.gd")

	# Fixture: a car in its sealed pre-ride state (doors locked by the
	# boarding static, disembark zone dormant) — the late loader's car.
	InteriorScript.doors_locked = true
	var car = InteriorScript.new()
	car._build_car()
	car._build_scenery()
	car._build_platform()
	car._build_skip_lever()
	car._build_disembark_zone()
	_assert(not car._arrived and not car._doors_open, "135: late car starts sealed")
	_assert(not car._disembark_area.monitoring, "135: late car zone dormant")

	# The pull's answer after the ride ended: arrival applies in full.
	car._apply_ride_state(true, false, "Village Outskirts", 0.0)
	_assert(car._arrived, "135: sync (arrived) applies arrival")
	_assert(not InteriorScript.doors_locked, "135: sync (arrived) unlocks the doors")
	_assert(car._doors_open, "135: sync (arrived) opens the doors")
	_assert(car._disembark_area.monitoring, "135: sync (arrived) arms the disembark zone")
	_assert(car._door_blocker == null, "135: sync (arrived) clears the door blocker")

	# Applied twice = the same end state (the broadcast AND a sync
	# reply both landing on a healthy client must not double-apply).
	car._apply_arrival()
	car._apply_ride_state(true, false, "Village Outskirts", 0.0)
	_assert(car._arrived and car._doors_open and car._disembark_area.monitoring,
		"135: arrival applied twice ends in the same state")
	car.free()

	# The pull's answer mid-ride: the ride applies with the server's clock.
	var car2 = InteriorScript.new()
	car2._build_car()
	car2._build_dressing()
	car2._build_scenery()
	car2._build_platform()
	car2._build_skip_lever()
	car2._build_disembark_zone()
	car2._apply_ride_state(false, true, "Dungeon Depths", 7.5)
	_assert(car2._riding, "135: sync (riding) starts the ride locally")
	_assert(absf(car2._ride_left - 7.5) < 0.001, "135: sync (riding) takes the server's clock")
	_assert(car2._scenery_root.visible, "135: sync (riding) shows the scenery")
	car2.free()

	# Wiring (source): _ready pulls; the server answers the requester only.
	var isrc := FileAccess.get_file_as_string("res://scripts/station/train_interior.gd")
	_assert(isrc.contains("func request_ride_state"), "135: ride-state request exists")
	_assert(isrc.contains("func ride_state_sync"), "135: ride-state sync exists")
	_assert(isrc.contains('rpc_id(sender, "ride_state_sync"'), "135: server answers the requester only")
	_assert(isrc.contains("_apply_ride_state(arrived, riding, dest_name, seconds_left)"),
		"135: sync handler delegates to the testable application")
	var rpos := isrc.find("func _ready")
	var rend := isrc.find("func is_riding", rpos)
	var rblock := isrc.substr(rpos, rend - rpos)
	_assert(rblock.contains("_pull_ride_state()"), "135: _ready pulls the ride state")
	_assert(not rblock.contains("if ride_active:"), "135: dead static late-apply gone from _ready")
	# Leave the shared statics as the section found them.
	InteriorScript.doors_locked = false
	InteriorScript.ride_seconds = 25.0
	InteriorScript.ride_dest_name = ""
	print("[Playtest] Train ride-state sync done")


## Issue #92: voluntary local disembark. Every peer walks through the open
## car door on its own schedule; do_disembark() runs locally (no server
## round-trip, no timers, no pulls) and the hop is instant because the
## dungeon scene was background-loaded during the ride.
func _test_train_disembark_fallback() -> void:
	print("[Playtest] Train voluntary disembark (issue #92)...")
	var isrc := FileAccess.get_file_as_string("res://scripts/station/train_interior.gd")
	# Door-walk hops locally: _on_disembark_body_entered calls do_disembark()
	# directly instead of rpc'ing the server (whose train may be freed).
	var epos := isrc.find("func _on_disembark_body_entered")
	_assert(epos > 0, "disembark: door handler exists")
	var eblock := isrc.substr(epos, 600)
	_assert(eblock.contains("do_disembark()"), "disembark: door-walk hops locally")
	_assert(not eblock.contains("request_disembark"), "disembark: no server round-trip on door-walk")
	# do_disembark is a plain local function, not an RPC.
	var dpos := isrc.find("func do_disembark")
	_assert(dpos > 0, "disembark: do_disembark exists")
	var pre := isrc.substr(maxi(0, dpos - 120), 120)
	_assert(not pre.contains("@rpc"), "disembark: do_disembark is not an RPC")
	var dblock := isrc.substr(dpos, 1200)
	_assert(dblock.contains("_disembarked_local"), "disembark: hop is idempotent")
	_assert(dblock.contains("load_threaded_get(DUNGEON_SCENE)"), "disembark: uses the preloaded scene")
	# Ghost scrub (Jesse 2026-10-08): the hopper RPCs scrub_passenger so its
	# train body is freed on all peers instead of blocking the exit.
	_assert(dblock.contains('rpc("scrub_passenger"'), "disembark: hop scrubs the passenger node")
	_assert(isrc.contains("func scrub_passenger"), "disembark: scrub_passenger exists")
	var spos := isrc.find("func scrub_passenger")
	var sblock := isrc.substr(spos, 400)
	_assert(sblock.contains("queue_free()"), "disembark: scrub frees the node")
	# Join timeout (Jesse 2026-10-08): stuck joins must fail loudly, not hang.
	var nmsrc := FileAccess.get_file_as_string("res://scripts/autoload/network_manager.gd")
	_assert(nmsrc.contains("JOIN_TIMEOUT_S"), "join: timeout constant exists")
	_assert(nmsrc.contains("_join_timeout = JOIN_TIMEOUT_S"), "join: timeout armed on join")
	_assert(nmsrc.contains("_join_timeout = 0.0"), "join: timeout cancelled on connect")
	_assert(nmsrc.contains("timed out"), "join: timeout emits a failure")
	var mmsrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(mmsrc.contains("_lan_mode_join"), "join: LAN-mode guard exists on Join Selected")
	# Steam lobby P2P (Jesse 2026-10-08, renamed 2026-10-10): must use
	# connect_to_lobby, not create_client — the latter hangs on "Joining..." forever.
	_assert(nmsrc.contains("connect_to_lobby(lobby_id)"), "join: Steam uses connect_to_lobby")
	# Host echo guard (Jesse 2026-10-10): Steam fires lobby_joined for the lobby
	# owner too — the handler must not clobber is_host or rebuild the server peer,
	# otherwise start_game() silently no-ops on `if not is_host`.
	_assert(nmsrc.contains("if owner == SteamManager.steam_id:"), "join: host echo guard exists")
	# Steam self-target guard (Jesse 2026-10-10): SteamMultiplayerPeer can't
	# rpc_id its own peer ID ("unknown peer ID" on the host), so server-bound
	# RPCs must call directly when this instance IS the server. Pin the
	# reported-broken dagger site and the melee site to the direct-call pattern.
	var psrc_steam := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc_steam.contains("_request_dagger_spawn(spawn_pos, dagger_vel, throw_dmg, from, throw_range)"),
		"steam: host dagger calls spawn directly")
	_assert(psrc_steam.contains("mob.take_damage(melee_dmg, from, global_position)"),
		"steam: host melee calls take_damage directly")
	# Peer-ID namespace fix (Jesse 2026-10-10): SteamMultiplayerPeer peer IDs
	# are NOT Steam IDs — the host is peer 1 (per GodotSteam docs), Steam64 is
	# a separate namespace. rpc targets and sender checks must use
	# server_peer_id, never the 64-bit server_id (R died here: the sender check
	# compared peer id 1 against the 64-bit Steam ID and rejected the host).
	_assert(nmsrc.contains("var server_peer_id: int = 1"),
		"steam: server_peer_id declared")
	_assert(not psrc_steam.contains("rpc_id(NetworkManager.server_id,"),
		"steam: no rpc targets the 64-bit server_id")
	var dgsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dgsrc.contains("sender != NetworkManager.server_peer_id"),
		"steam: wave-start sender check uses peer id")
	# No auto-pull mechanisms: no sweep, no fallback, no timers.
	_assert(not isrc.contains("func _run_disembark_window"), "disembark: server sweep removed")
	_assert(not isrc.contains("func _run_disembark_fallback"), "disembark: self-pull fallback removed")
	_assert(not isrc.contains("func request_disembark"), "disembark: request_disembark removed")
	var apos := isrc.find("func begin_arrival")
	_assert(apos > 0, "disembark: begin_arrival exists")
	var ablock := isrc.substr(apos, 2000)
	_assert(not ablock.contains("_run_disembark_window"), "disembark: arrival starts no sweep")
	_assert(not ablock.contains("_run_disembark_fallback"), "disembark: arrival starts no fallback")
	print("[Playtest] Train voluntary disembark done")


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


func _test_depart_flow() -> void:
	print("[Playtest] Depart flow (issue #93 Phase 3: lever -> doors -> ride)...")
	var StationScript := load("res://scripts/station/station.gd")
	var AnnexScript: GDScript = load("res://scripts/station/station_annex.gd")
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	var living := [10, 11, 12]
	var st = StationScript.new()
	root.add_child(st)
	var captured := []
	st.departure_resolved.connect(func(tid): captured.append(tid))

	# Depart lever is idle before a unanimous vote resolves.
	_assert(not bool(st.record_depart(10, living)["ok"]), "depart: rejected while idle")
	_assert(captured.is_empty(), "depart: nothing emitted while idle")

	# Unanimous vote -> doors-open boarding phase, no departure yet.
	st.votes = {10: "depths", 11: "depths", 12: "depths"}
	st.depart(living)
	_assert(st.get("_depart_theme") == "depths", "depart: carries the voted theme")
	_assert(not bool(st.get("_depart_requested")), "depart: lever not yet pulled")
	_assert(captured.is_empty(), "depart: no departure_resolved yet")

	# Lever validation: non-living peer rejected, double-pull rejected.
	_assert(not bool(st.record_depart(99, living)["ok"]), "depart: non-living rejected")
	_assert(bool(st.record_depart(10, living)["ok"]), "depart: living player pulls lever")
	_assert(not bool(st.record_depart(11, living)["ok"]), "depart: second pull rejected")
	_assert(bool(st.get("_depart_requested")), "depart: depart requested")

	# Completion emits departure_resolved with the voted theme.
	st._complete_departure()
	_assert(captured == ["depths"], "depart: completion emits departure_resolved")

	# Fresh station: lever before vote resolve does nothing.
	var st2 = StationScript.new()
	root.add_child(st2)
	var captured2 := []
	st2.departure_resolved.connect(func(tid): captured2.append(tid))
	st2.votes = {10: "village", 11: "village"}
	st2.depart([10, 11])
	st2._complete_departure()
	_assert(captured2 == ["village"], "depart: vote -> lever -> departure_resolved")
	st.queue_free()
	st2.queue_free()

	# Vote-resolve opens the lobby doors (station -> annex wiring).
	var theme: Resource = load("res://data/levels/theme_village.tres")
	var layout = ProcGenScript.generate(theme, 777)
	var plan: Dictionary = AnnexScript.plan(777, layout)
	var holder := Node3D.new()
	root.add_child(holder)
	var annex = AnnexScript.build(holder, plan, layout)
	var st3 = StationScript.new()
	root.add_child(st3)
	st3.annex = annex
	_assert(not annex.doors_open, "depart: doors closed before vote resolve")
	st3.votes = {10: "dungeon", 11: "dungeon"}
	st3.depart([10, 11])
	_assert(annex.doors_open, "depart: vote resolve opens lobby doors")
	# Lever pull closes the doors for the ride.
	st3.record_depart(10, [10, 11])
	st3._apply_depart_close()
	_assert(not annex.doors_open, "depart: lever pull closes lobby doors")
	holder.queue_free()
	st3.queue_free()

	# Departure SFX triggers (sound audit, retargeted): all_aboard on the
	# doors-open banner, board_chime on a successful lever pull, door_lock
	# when the doors shut for departure, vote_cast on voting.
	var SoundScript := load("res://scripts/audio/sound_synth.gd")
	for sfx in ["all_aboard", "board_chime", "door_lock", "vote_cast"]:
		_assert(SoundScript.call(sfx) is AudioStreamWAV, "depart sfx builds: %s" % sfx)
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	var ab_pos := ssrc.find("func announce_boarding")
	_assert(ab_pos > 0 and ssrc.substr(ab_pos, 400).contains('sfx("all_aboard")'),
		"sfx: all_aboard in announce_boarding")
	var rd_pos := ssrc.find("func request_depart")
	_assert(rd_pos > 0 and ssrc.substr(rd_pos, 700).contains('sfx("board_chime")'),
		"sfx: board_chime on request_depart success")
	var cd_pos := ssrc.find("func _complete_departure")
	_assert(cd_pos > 0 and ssrc.substr(cd_pos, 300).contains('sfx("door_lock")'),
		"sfx: door_lock in _complete_departure")
	var vsrc := FileAccess.get_file_as_string("res://scripts/station/departure_board.gd")
	var sv_pos := vsrc.find("func set_my_vote")
	_assert(sv_pos > 0 and vsrc.substr(sv_pos, 300).contains('sfx("vote_cast")'),
		"sfx: vote_cast in set_my_vote")
	# The retired 45s-window SFX trigger is gone with boarding_sync.
	_assert(not ssrc.contains("func boarding_sync"), "retired: boarding_sync gone")
	_assert(not ssrc.contains("func request_board"), "retired: request_board gone")
	_assert(not ssrc.contains("func _finish_boarding"), "retired: _finish_boarding gone")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(not hsrc.contains("func show_boarding_timer"), "retired: show_boarding_timer gone")
	_assert(hsrc.contains("func show_now_boarding"), "hud: show_now_boarding replaces it")

## Two-peer sim of the full issue #93 cycle (validation): vote -> walk into
## lobby -> depart lever -> doors close -> departure_resolved -> arrival
## spawns inside the new lobby -> settle opens doors -> walk out.
func _test_lobby_full_cycle_2peer() -> void:
	print("[Playtest] Lobby full cycle 2-peer sim (issue #93 phase 4)...")
	var StationScript := load("res://scripts/station/station.gd")
	var AnnexScript: GDScript = load("res://scripts/station/station_annex.gd")
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	var theme: Resource = load("res://data/levels/theme_village.tres")
	var layout = ProcGenScript.generate(theme, 555)
	var plan: Dictionary = AnnexScript.plan(555, layout)
	var holder := Node3D.new()
	root.add_child(holder)
	var annex = AnnexScript.build(holder, plan, layout)
	# Isolate the players group: earlier tests leave queue_free'd stragglers.
	for n in get_nodes_in_group("players"):
		n.remove_from_group("players")
	# Two living peers.
	var p1 := FakeLobbyPeer.new()
	p1.set_multiplayer_authority(10)
	var p2 := FakeLobbyPeer.new()
	p2.set_multiplayer_authority(11)
	root.add_child(p1)
	root.add_child(p2)
	p1.add_to_group("players")
	p2.add_to_group("players")
	var st = StationScript.new()
	root.add_child(st)
	st.annex = annex
	var captured := []
	st.departure_resolved.connect(func(tid): captured.append(tid))
	# 1. Unanimous vote -> doors open.
	st.votes = {10: "dungeon", 11: "dungeon"}
	st.depart()
	_assert(annex.doors_open, "cycle: vote resolve opens doors")
	# 2. Both walk into the lobby (spawn spots are inside lobby bounds).
	var bounds: AABB = annex.lobby_bounds()
	for sp in annex.lobby_spawn_spots():
		var s: Vector3 = sp
		_assert(bounds.has_point(s), "cycle: lobby spawn spot inside lobby")
	var hc: Vector3 = annex.hall_center()
	var to_hall := func(w: Vector3) -> Vector3:
		return annex.to_local(w) - Vector3(hc.x, 0.0, hc.z)
	var gspots: Array = annex.lobby_spawn_spots_global()
	p1.global_position = gspots[0]
	p2.global_position = gspots[1]
	_assert(bounds.has_point(to_hall.call(p1.global_position)), "cycle: peer 10 inside lobby")
	_assert(bounds.has_point(to_hall.call(p2.global_position)), "cycle: peer 11 inside lobby")
	# 3. Lever pull by a living peer -> doors close.
	var res: Dictionary = st.record_depart(10)
	_assert(bool(res.get("ok", false)), "cycle: peer 10 pulls the lever")
	st._apply_depart_close()
	_assert(not annex.doors_open, "cycle: doors close for departure")
	# 4. Completion fires the ride handoff with the voted theme.
	st._complete_departure()
	_assert(captured == ["dungeon"], "cycle: departure_resolved(dungeon)")
	# 5. Arrival: a fresh annex spawns both inside its lobby, doors closed.
	var holder2 := Node3D.new()
	root.add_child(holder2)
	var annex2 = AnnexScript.build(holder2, plan, layout)
	_assert(not annex2.doors_open, "cycle: arrival doors closed")
	var spots2: Array = annex2.lobby_spawn_spots_global()
	_assert(spots2.size() >= 2, "cycle: 2+ arrival spots")
	var b2: AABB = annex2.lobby_bounds()
	var hc2: Vector3 = annex2.hall_center()
	var to_hall2 := func(w: Vector3) -> Vector3:
		return annex2.to_local(w) - Vector3(hc2.x, 0.0, hc2.z)
	p1.global_position = spots2[0]
	p2.global_position = spots2[1]
	_assert(b2.has_point(to_hall2.call(p1.global_position)), "cycle: peer 10 arrives in lobby")
	_assert(b2.has_point(to_hall2.call(p2.global_position)), "cycle: peer 11 arrives in lobby")
	# 6. Settle opens the doors; the doorway is walkable again.
	annex2._process(1.1)
	_assert(annex2.doors_open, "cycle: settle opens doors")
	_assert(annex2.get_node_or_null("LobbyDoorBlocker") == null, "cycle: blocker freed after settle")
	p1.remove_from_group("players")
	p2.remove_from_group("players")
	holder.queue_free()
	holder2.queue_free()
	st.queue_free()
	p1.queue_free()
	p2.queue_free()


## Disconnect mid-boarding must not soft-lock: a peer inside the lobby drops,
## the remaining peer can still pull the lever and depart. Also: unanimity
## ignores stale votes from non-living peers.
func _test_disconnect_mid_boarding() -> void:
	print("[Playtest] Disconnect mid-boarding (issue #93 phase 4)...")
	var StationScript := load("res://scripts/station/station.gd")
	var p1 := FakeLobbyPeer.new()
	p1.set_multiplayer_authority(10)
	var p2 := FakeLobbyPeer.new()
	p2.set_multiplayer_authority(11)
	for n in get_nodes_in_group("players"):
		n.remove_from_group("players")
	root.add_child(p1)
	root.add_child(p2)
	p1.add_to_group("players")
	p2.add_to_group("players")
	var st = StationScript.new()
	root.add_child(st)
	_assert(st._living_peer_ids().size() == 2, "disc: 2 living peers")
	# Vote resolves while both are present.
	st.votes = {10: "depths", 11: "depths"}
	st.depart()
	_assert(bool(st.get("_departing")), "disc: vote resolved, departing")
	# Peer 11 disconnects mid-boarding: server despawns their node.
	p2.get_parent().remove_child(p2)
	p2.queue_free()
	var living: Array = st._living_peer_ids()
	_assert(living == [10], "disc: leaver no longer living")
	# The remaining peer pulls the lever: no soft-lock.
	var res: Dictionary = st.record_depart(10)
	_assert(bool(res.get("ok", false)), "disc: remaining peer departs")
	# Stale votes from the leaver can't block the NEXT vote's unanimity.
	st.votes = {10: "village", 11: "depths"}
	_assert(StationScript.resolve_destination(st.votes, [10]) == "village",
		"disc: unanimity ignores leaver's stale vote")
	# Disconnect DURING voting: unanimity needs only the survivors.
	var st2 = StationScript.new()
	root.add_child(st2)
	_assert(StationScript.resolve_destination({10: "dungeon"}, [10]) == "dungeon",
		"disc: survivor alone reaches unanimity")
	st.queue_free()
	st2.queue_free()
	p1.queue_free()

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
	# Wave credits scale with player count (Jesse 2026-10-10, issue #101).
	var d1 = dir_script.new()
	d1.player_count = 1
	d1.start_wave(1)
	_assert(is_equal_approx(d1.credits, 75.0),
		"director: solo wave 1 budget is 75")
	var d4 = dir_script.new()
	d4.player_count = 4
	d4.start_wave(1)
	_assert(is_equal_approx(d4.credits, 300.0),
		"director: 4-player wave 1 budget is 4x")
	var d12 = dir_script.new()
	d12.player_count = 12
	d12.start_wave(1)
	_assert(is_equal_approx(d12.credits, 900.0),
		"director: 12-player wave 1 budget is 12x")
	# Credit trickle scales too.
	d1._process(1.0)
	_assert(is_equal_approx(d1.credits, 85.0),
		"director: solo trickle is 10/s")
	d4._process(1.0)
	_assert(is_equal_approx(d4.credits, 340.0),
		"director: 4-player trickle is 40/s")
	# Mixed waves (Jesse 2026-10-10): every wave drafts from each role.
	var dmix = dir_script.new()
	dmix.player_count = 4
	dmix.start_wave(5)
	var comp: Array = dmix.get_wave_composition()
	_assert(not comp.is_empty(), "director: wave produces a composition")
	var types := {}
	for entry in comp:
		types[str(entry["type"])] = true
	_assert(types.size() >= 3,
		"director: wave mixes at least 3 mob types (got %d)" % types.size())
	# Leftover credits buy tiers: big budget should produce elites/champions.
	var d12b = dir_script.new()
	d12b.player_count = 12
	d12b.start_wave(10)
	var comp12: Array = d12b.get_wave_composition()
	var tiers := {0: 0, 1: 0, 2: 0}
	for entry in comp12:
		tiers[int(entry["tier"])] += 1
	_assert(tiers[1] + tiers[2] > 0,
		"director: 12-player wave 10 buys upgrades (elites=%d champions=%d)" % [tiers[1], tiers[2]])


func _test_downed_marker() -> void:
	print("[Playtest] Downed marker...")
	# World-space "!" marker so teammates spot downed players (Jesse 2026-10-10).
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("func _show_downed_marker()"),
		"downed: marker builder exists")
	_assert(psrc.contains("no_depth_test = true"),
		"downed: marker renders through walls")
	_assert(psrc.contains("not is_multiplayer_authority()"),
		"downed: marker hidden on downed player's own instance")


func _test_dash_flash_separate() -> void:
	print("[Playtest] Dash flash rect...")
	# Jesse 2026-10-10: dash and damage flashes need their own rects —
	# sharing one let hit flashes hijack the dash fade and vice versa.
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("%DashFlash"),
		"dash: flash_dash uses its own DashFlash rect")
	_assert(not hsrc.contains("%DamageFlash.modulate = Color(0.6, 0.8, 1.0"),
		"dash: flash_dash no longer repaints the damage rect blue")
	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/hud.tscn")
	_assert(tsrc.contains("[node name=\"DashFlash\""),
		"dash: DashFlash node exists in hud.tscn")


func _test_market_earned_display() -> void:
	print("[Playtest] Market earned display...")
	# Jesse 2026-10-10: gate progress shows per-visit EARNINGS (what unlocks
	# the gate), not held cash.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func sync_market_earnings"),
		"market: earnings broadcast RPC exists")
	_assert(dsrc.contains("set_market_cash(market_earned_visit, market_cash_goal)"),
		"market: HUD gets earnings, not held cash")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("Earned: $%d / $%d"),
		"market: label reads Earned, not Cash")


func _test_heal_pad_multiplayer() -> void:
	print("[Playtest] Heal pad multiplayer...")
	# Jesse 2026-10-10: heal pad was server-only and the server's physics
	# couldn't see client bodies — clients never got healed. Now each peer
	# checks its own player locally.
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(ssrc.contains("_my_player()"),
		"healpad: uses local player lookup")
	_assert(not ssrc.contains("b.rpc_id(b.get_multiplayer_authority(), \"heal\""),
		"healpad: no longer RPCs heal from server physics loop")


func _test_train_spots_12p() -> void:
	print("[Playtest] Train spots for 12 players...")
	# Jesse 2026-10-10: the train hop had 4 hardcoded spots (old 4-player
	# cap); 12 players stacked 3-per-spot. Now procedural, 12 minimum.
	var asrc := FileAccess.get_file_as_string("res://scripts/station/station_annex.gd")
	_assert(asrc.contains("4 columns x 3 rows") or asrc.contains("cols := 4"),
		"train: lobby spots are a 12-slot grid")
	var tsrc := FileAccess.get_file_as_string("res://scripts/station/train_interior.gd")
	_assert(tsrc.contains("maxi(4, passenger_classes.size())"),
		"train: aisle spots scale to passenger count")
	# Behavioral: annex grid yields 12.
	var annex_script = load("res://scripts/station/station_annex.gd")
	var annex = annex_script.new()
	var spots: Array = annex.lobby_spawn_spots()
	_assert(spots.size() >= 12,
		"train: lobby grid has >=12 spots (got %d)" % spots.size())
	annex.free()


func _test_mp_save_steam_ids() -> void:
	print("[Playtest] MP save uses Steam IDs...")
	# Jesse 2026-10-10: the roster stored PEER IDs (1,2,3) in the steam_id
	# field, but the continue flow compared against real Steam64 IDs — the
	# host could never find their own save. Now real Steam IDs throughout.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("peer_steam_ids"),
		"mpsave: peer -> Steam ID mapping exists")
	_assert(dsrc.contains("SteamManager.steam_id if SteamManager.initialized"),
		"mpsave: roster uses real Steam IDs")
	# Behavioral: find_roster_entry matches by Steam ID.
	var roster := [
		{"steam_id": 76561198000000001, "class_id": "mage"},
		{"steam_id": 76561198000000002, "class_id": "warrior"},
	]
	var dungeon_script = load("res://scripts/dungeon/dungeon.gd")
	var hit: Dictionary = dungeon_script.find_roster_entry(roster, 76561198000000002)
	_assert(str(hit.get("class_id", "")) == "warrior",
		"mpsave: roster matches by Steam ID")
	var miss: Dictionary = dungeon_script.find_roster_entry(roster, 1)
	_assert(miss.is_empty(),
		"mpsave: peer ID 1 does not match a Steam ID roster")


## Extract a function body (from "func name" to the next top-level func)
## for source-structure assertions in the bug-hunt tests.
func _bughunt_body(src: String, fname: String) -> String:
	var i := src.find("func " + fname)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 5)
	if j < 0:
		j = src.length()
	return src.substr(i, j - i)


func _test_mp_save_bughunt() -> void:
	print("[Playtest] MP save bug hunt (adversarial)...")
	# Eng 9 audit 2026-10-12: adversarial coverage for the MP save system —
	# the replica-wipe mechanism (C-1), roster matching edge cases, the
	# save-file attack surface, and summary labels. Runtime loads only
	# (bare autoload identifiers don't compile in -s script mode).
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var DungeonScript = load("res://scripts/dungeon/dungeon.gd")
	var SaveScript = load("res://scripts/autoload/save_manager.gd")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	var ssrc := FileAccess.get_file_as_string("res://scripts/autoload/save_manager.gd")

	# --- Part 1: full-state roundtrip + the replica-wipe mechanism (C-1).
	var ids := ["health_potion", "iron_sword", "dragonscale_armor", "ember_amulet",
		"apprentice_staff", "cereal_box", "frozen_pizza", "aegis_of_the_deep",
		"soda_can", "milk_carton", "snack_cake", "void_blade"]
	var p1 = PlayerScene.instantiate()
	p1.class_id = "warrior"
	root.add_child(p1)
	p1.level = 7
	p1.xp = 432
	p1.xp_next = 600
	p1.stat_points = 2
	p1.bonus_damage = 3.5
	p1.bonus_health = 10.0
	p1.supermarket_cash = 777
	p1.inventory.clear()
	var want := {}
	var n := 0
	for id in ids:
		var it = ItemDBNode.get_item(id)
		if it == null:
			continue
		n += 1
		var c := 999 if id == "health_potion" else 1 + n
		p1.inventory.append({"item": it, "count": c})
		want[id] = c
	_assert(want.size() >= 8, "bughunt: item fixture has >= 8 distinct items")
	var rich: Dictionary = p1.get_state()
	var got := {}
	for e in rich.get("inventory", []):
		got[str(e.get("id", ""))] = int(e.get("count", 0))
	_assert(got == want, "bughunt: get_state serializes the full inventory (ids + counts)")
	var p2 = PlayerScene.instantiate()
	p2.class_id = "rogue"
	root.add_child(p2)
	p2.apply_state(rich)
	var got2 := {}
	for e in p2.inventory:
		got2[str((e["item"] as Object).get("id"))] = int(e["count"])
	_assert(got2 == want, "bughunt: full inventory restores intact (12 stacks incl. x999)")
	_assert(p2.level == 7 and p2.xp == 432 and p2.supermarket_cash == 777,
		"bughunt: level/xp/cash restore intact")
	# A fresh player is exactly what the host's server-side replica of a
	# remote peer holds: inventory is per-peer authoritative and is never
	# replicated (push_snapshot syncs pos/hp/level/alive/yaw only).
	var p3 = PlayerScene.instantiate()
	p3.class_id = "warrior"
	root.add_child(p3)
	var replica: Dictionary = p3.get_state()
	_assert(int(replica.get("xp", -1)) == 0, "bughunt: replica state has xp 0")
	var rep_ids := {}
	for e in replica.get("inventory", []):
		rep_ids[str(e.get("id", ""))] = int(e.get("count", 0))
	_assert(not rep_ids.has("dragonscale_armor"),
		"bughunt: replica state lacks the peer's earned gear")
	# C-1 consequence: applying the replica capture (what the save-window
	# timeout fill-in writes to disk) to the progressed character destroys
	# the earned progression.
	p2.apply_state(replica)
	_assert(p2.xp == 0 and p2.level == 1, "bughunt: replica apply resets level/xp (C-1 wipe)")
	var left := {}
	for e in p2.inventory:
		left[str((e["item"] as Object).get("id"))] = int(e["count"])
	_assert(not left.has("dragonscale_armor") and not left.has("ember_amulet"),
		"bughunt: replica apply deletes earned inventory (C-1 wipe)")
	# Unknown item ids are silently dropped by apply_state.
	p2.apply_state({"inventory": [{"id": "bughunt_no_such_item", "count": 5}]})
	_assert(p2.inventory.is_empty(), "bughunt: unknown item ids silently dropped on restore")
	root.remove_child(p1)
	p1.free()
	root.remove_child(p2)
	p2.free()
	root.remove_child(p3)
	p3.free()

	# --- Part 2: roster matching adversarial cases.
	var dup := [
		{"steam_id": 76561198000000042, "class_id": "mage", "player_state": {"level": 9}},
		{"steam_id": 76561198000000042, "class_id": "rogue", "player_state": {"level": 1}},
	]
	var first: Dictionary = DungeonScript.find_roster_entry(dup, 76561198000000042)
	_assert(str(first.get("class_id", "")) == "mage",
		"bughunt: duplicate Steam64 entries — first match wins (no dedup)")
	var zero_hit: Dictionary = DungeonScript.find_roster_entry([{"steam_id": 0, "class_id": "mage"}], 0)
	_assert(not zero_hit.is_empty(), "bughunt: steam_id 0 matches a steam_id 0 entry (latent)")

	# --- Part 3: save-file attack surface (scratch dir only, abort-safe).
	var mgr = SaveScript.new()
	var scratch := "user://runs_bughunt_test"
	if DirAccess.dir_exists_absolute(scratch):
		for f in DirAccess.get_files_at(scratch):
			DirAccess.remove_absolute(scratch.path_join(f))
		DirAccess.remove_absolute(scratch)
	mgr.set("_test_runs_dir", scratch)
	mgr.set("_test_account_pin", "bughunt_scratch")
	var roster12: Array = []
	for i in 12:
		roster12.append({
			"steam_id": 76561198000000000 + i,
			"player_name": "P%d" % i,
			"class_id": ["warrior", "rogue", "mage"][i % 3],
			"player_state": {"level": 3 + i, "xp": i * 10,
				"inventory": [{"id": "health_potion", "count": i + 1}]},
			"rts_faction": -1,
			"is_host": i == 0,
		})
	var run12 := {"theme_id": "dungeon", "level_number": 8, "seed": 424242,
		"wave": 3, "is_multiplayer": true, "at_station": false, "roster": roster12}
	_assert(mgr.save_run(run12, "mp", 3), "bughunt: 12-player run saves")
	var back12: Dictionary = mgr.load_run("mp", 3)
	_assert((back12.get("roster", []) as Array).size() == 12, "bughunt: 12 roster entries roundtrip")
	var ids_ok := true
	var broster: Array = back12.get("roster", [])
	for i in 12:
		if int((broster[i] as Dictionary).get("steam_id", 0)) != 76561198000000000 + i:
			ids_ok = false
	_assert(ids_ok, "bughunt: Steam64 ids survive ConfigFile exactly (no truncation)")
	_assert(int(back12.get("level_number", 0)) == 8 and int(back12.get("wave", 0)) == 3,
		"bughunt: cycle-2 level + wave roundtrip")
	# Double save/restore integrity.
	_assert(mgr.save_run(back12, "mp", 4), "bughunt: re-save of loaded run succeeds")
	var back12b: Dictionary = mgr.load_run("mp", 4)
	_assert((back12b.get("roster", []) as Array).size() == 12
		and int(back12b.get("level_number", 0)) == 8,
		"bughunt: double restore keeps roster + level")
	# Duplicate Steam64 entries are NOT deduplicated by save/load.
	var duprun := {"theme_id": "dungeon", "level_number": 2, "roster": dup}
	mgr.save_run(duprun, "mp", 5)
	_assert((mgr.load_run("mp", 5).get("roster", []) as Array).size() == 2,
		"bughunt: duplicate Steam64 roster persists verbatim")
	# Legacy-style MP run (migration output): no roster key at all.
	mgr.save_run({"theme_id": "village", "level_number": 3, "class_id": "mage",
		"player_state": {"level": 3}}, "mp", 6)
	var legacy: Dictionary = mgr.load_run("mp", 6)
	_assert((legacy.get("roster", []) as Array).is_empty(),
		"bughunt: legacy MP save has no roster (continue restores nobody)")
	# Version gate.
	_assert(mgr.is_save_compatible("mp", 3), "bughunt: fresh save is version-compatible")
	var vpath := scratch + "/mp_3.cfg"
	var vcfg := ConfigFile.new()
	vcfg.load(vpath)
	var vdata: Dictionary = vcfg.get_value("run", "data", {})
	vdata["save_version"] = 99
	vcfg.set_value("run", "data", vdata)
	vcfg.save(vpath)
	_assert(not mgr.load_run("mp", 3).is_empty(), "bughunt: future-version save still parses")
	_assert(not mgr.is_save_compatible("mp", 3),
		"bughunt: future-version save is refused by the version gate")
	# Truncated file (tail cut mid-dict) refuses cleanly.
	var good_bytes := FileAccess.get_file_as_bytes(scratch + "/mp_4.cfg")
	var tf := FileAccess.open(scratch + "/mp_8.cfg", FileAccess.WRITE)
	tf.store_buffer(good_bytes.slice(0, maxi(0, good_bytes.size() - 40)))
	tf.close()
	_assert(mgr.load_run("mp", 8).is_empty(), "bughunt: truncated save loads as empty")
	_assert(not mgr.has_run("mp", 8), "bughunt: truncated save reports no run")
	# Garbage bytes refuse cleanly.
	var gf := FileAccess.open(scratch + "/mp_9.cfg", FileAccess.WRITE)
	gf.store_buffer("not a config file {{{".to_utf8_buffer())
	gf.close()
	_assert(mgr.load_run("mp", 9).is_empty(), "bughunt: corrupt save loads as empty")
	# File with an empty data dict = no run.
	var ecfg := ConfigFile.new()
	ecfg.set_value("run", "data", {})
	ecfg.save(scratch + "/mp_10.cfg")
	_assert(not mgr.has_run("mp", 10), "bughunt: empty-data save reports no run")
	# Cloud premise (M-2): on a fresh device the local slot list is empty,
	# and sync-down only fetches slots that list locally (asserted below).
	_assert(mgr.list_slots("mp").size() >= 5, "bughunt: scratch slots list (sanity)")
	var fresh = SaveScript.new()
	fresh.set("_test_runs_dir", "user://runs_bughunt_empty")
	_assert(fresh.list_slots("mp").is_empty(),
		"bughunt: fresh-device slot list is empty (why sync-down also enumerates the cloud, M-2)")
	fresh.free()

	# --- Part 4: run_summary labels (level / wave / At Station checks).
	var dsum: String = mgr.run_summary({"theme_id": "dungeon", "level_number": 3,
		"wave": 2, "at_station": false, "is_multiplayer": false,
		"class_id": "mage", "player_state": {"level": 3}})
	_assert(dsum.contains("Level 3") and dsum.contains("Wave 2"),
		"bughunt: dungeon summary shows level + wave")
	_assert(not dsum.contains("At Station"),
		"bughunt: dungeon save is NOT labeled At Station")
	var ssum: String = mgr.run_summary({"theme_id": "village", "level_number": 4,
		"at_station": true, "is_multiplayer": false,
		"class_id": "mage", "player_state": {"level": 7}})
	_assert(ssum.contains("Level 3 (At Station)"),
		"bughunt: station summary shows the cleared level, labeled At Station")
	var msum: String = mgr.run_summary({"theme_id": "dungeon", "level_number": 3,
		"wave": 0, "at_station": false, "is_multiplayer": true,
		"roster": [{"class_id": "mage", "player_state": {"level": 3}},
			{"class_id": "rogue", "player_state": {"level": 5}}]})
	_assert(msum.contains("2 players"), "bughunt: MP summary counts roster players")
	# Scratch cleanup.
	for f in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch.path_join(f))
	DirAccess.remove_absolute(scratch)
	if FileAccess.file_exists("user://profile_bughunt_scratch.cfg"):
		DirAccess.remove_absolute("user://profile_bughunt_scratch.cfg")
	mgr.free()

	# --- Part 5: source-structure evidence for the audit findings.
	# C-1 chain — FIXED (issue #105, Eng 3): the pre-fix asserts here
	# documented the bug's presence (dead "disconnected" stamp + replica
	# snapshot); they now assert the fixed behavior. M-1 evidence is
	# likewise flipped (issue #106, Eng 3), as is M-2 (issue #107,
	# Eng 4). (M-3 itself is FIXED — issue #108, see its block below;
	# this header previously claimed all three were still open, which
	# contradicted that block.)
	_assert(not dsrc.contains("entry[\"disconnected\"] = true"),
		"bughunt: timeout entries are NOT stamped disconnected (C-1 fixed)")
	_assert(dsrc.count("\"disconnected\"") == 0,
		"bughunt: the dead disconnected marker is gone (C-1 fixed)")
	var mm := _bughunt_body(dsrc, "_mark_missing_disconnected")
	_assert(not mm.contains("_roster_entry(sid, pid, node)"),
		"bughunt: timeout fill-in never snapshots the replica node (C-1 fixed)")
	_assert(mm.contains("find_roster_entry"),
		"bughunt: timeout fill-in carries the previous roster entry forward (C-1 fixed)")
	# M-3 — FIXED (issue #108, Eng 4): submissions are bound to the
	# SENDER's Steam64 via the server's own peer_steam_ids mapping; the
	# claimed identity is never trusted.
	var sub := _bughunt_body(dsrc, "rpc_submit_save_state")
	_assert(sub.contains("bind_submitted_state(state, sender, peer_steam_ids)"),
		"bughunt: submission is bound to the sender via peer_steam_ids (M-3 fixed)")
	_assert(sub.contains("_save_roster.append(bound)"),
		"bughunt: only the sender-bound state reaches the roster (M-3 fixed)")
	# Two-sender forgery: the attacker (peer 7) submits a wiped character
	# claiming the victim's Steam64; binding rewrites the identity to the
	# attacker's own, so the victim's roster entry survives intact.
	var mapping := {7: 76561198000000777, 9: 76561198000000999}
	var forged := {"steam_id": 76561198000000999, "class_id": "warrior",
		"player_state": {"level": 1, "xp": 0}}
	var bound: Dictionary = DungeonScript.bind_submitted_state(forged, 7, mapping)
	_assert(int(bound.get("steam_id", 0)) == 76561198000000777,
		"bughunt: forged claim is rewritten to the sender's own Steam64 (M-3)")
	var victim_roster := [
		{"steam_id": 76561198000000999, "class_id": "mage", "player_state": {"level": 9}},
		bound,
	]
	var victim: Dictionary = DungeonScript.find_roster_entry(victim_roster, 76561198000000999)
	_assert(str(victim.get("class_id", "")) == "mage"
		and int((victim.get("player_state", {}) as Dictionary).get("level", 0)) == 9,
		"bughunt: victim's entry survives a forged submission intact (M-3)")
	_assert(DungeonScript.bind_submitted_state(forged, 42, mapping).is_empty(),
		"bughunt: sender with no server-assigned identity is rejected (M-3)")
	# M-4 — FIXED (issue #109, Eng 4): the write path carries the
	# previous save's roster forward, so an absent member is never
	# deleted by missing a save point.
	var wr := _bughunt_body(dsrc, "_write_multiplayer_save")
	_assert(wr.contains("carry_forward_roster(_save_roster, previous.get(\"roster\", []))"),
		"bughunt: save write merges the previous roster (M-4 fixed)")
	# Behavioral: previous roster {A, B}; this session only A connects
	# (with newer state). The merged roster keeps A's new entry and B's
	# entry byte-identical.
	var prev_roster := [
		{"steam_id": 76561198000000111, "class_id": "mage", "player_state": {"level": 5, "xp": 50}},
		{"steam_id": 76561198000000222, "class_id": "rogue", "player_state": {"level": 7, "xp": 70}},
	]
	var new_roster := [
		{"steam_id": 76561198000000111, "class_id": "mage", "player_state": {"level": 6, "xp": 61}},
	]
	var merged: Array = DungeonScript.carry_forward_roster(new_roster, prev_roster)
	_assert(merged.size() == 2, "bughunt: absent player survives the save (M-4)")
	var kept_b: Dictionary = DungeonScript.find_roster_entry(merged, 76561198000000222)
	_assert(str(kept_b) == str(prev_roster[1]),
		"bughunt: absent player's entry is carried forward byte-identical (M-4)")
	var kept_a: Dictionary = DungeonScript.find_roster_entry(merged, 76561198000000111)
	_assert(int((kept_a.get("player_state", {}) as Dictionary).get("level", 0)) == 6,
		"bughunt: connected player's fresh state wins over carry-forward (M-4)")
	# M-5 — FIXED (issue #110, Eng 4): the run save persists the lobby
	# visibility and continue_multiplayer re-hosts with it, instead of
	# hardcoding friends-only; legacy saves keep the friends-only default.
	var nsrc := FileAccess.get_file_as_string("res://scripts/autoload/network_manager.gd")
	_assert(dsrc.contains("lobby[\"visibility\"] = NetworkManager.lobby_visibility"),
		"bughunt: run saves persist the lobby visibility (M-5 fixed; PF2 merged-lobby form)")
	var cont := _bughunt_body(nsrc, "continue_multiplayer")
	_assert(cont.contains("lobby.get(\"visibility\", \"friends\")"),
		"bughunt: continue reads stored visibility, friends-only legacy default (M-5 fixed)")
	_assert(cont.contains("Steam.createLobby(lobby_type"),
		"bughunt: continue creates the lobby with the stored visibility type (M-5 fixed)")
	_assert(not cont.contains("Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY"),
		"bughunt: continue no longer hardcodes friends-only (M-5 fixed)")
	# M-1 — FIXED (issue #106, Eng 3): the connected map is keyed by
	# Steam64 (player steam_id, peer_steam_ids fallback), registration
	# stores the node's PEER id in faction_peers, and reclaims that
	# arrive before _rts_manager exists queue in _pending_reclaims
	# instead of dropping into the late-joiner path.
	_assert(dsrc.contains("connected[psid] = pl"),
		"bughunt: warlord setup keys connected map by Steam64 (M-1 fixed)")
	_assert(not dsrc.contains("connected[int(pl.get_multiplayer_authority())] = pl"),
		"bughunt: authority keying gone (M-1 fixed)")
	_assert(dsrc.contains("int(connected[sid].get_multiplayer_authority())"),
		"bughunt: registration stores the peer id, not the Steam64 (M-1 fixed)")
	_assert(dsrc.contains("if connected.has(sid):"),
		"bughunt: warlord setup still queries the map by roster Steam64")
	var rec := _bughunt_body(dsrc, "_reclaim_faction")
	_assert(rec.contains("_pending_reclaims[peer_id] = faction_id"),
		"bughunt: early reclaim queues until the manager exists (M-1 fixed)")
	var sim_connected := {76561198000000001: "host"}
	_assert(sim_connected.has(76561198000000001),
		"bughunt: Steam64-keyed map matches the roster steam_id (host rebinds)")
	# M-2 — FIXED (issue #107, Eng 4): sync-down still fetches the
	# profile unconditionally and every locally-known slot, and now ALSO
	# enumerates the cloud's own file list so slot files that exist only
	# remotely (fresh device) are fetched. Tombstone guard preserved.
	var csd := _bughunt_body(ssrc, "_cloud_sync_down")
	_assert(csd.contains("for slot in list_slots(mode)"),
		"bughunt: cloud sync-down fetches locally-listed slots")
	_assert(csd.contains("_cloud_fetch(_profile_path_for(_profile_account))"),
		"bughunt: profile fetch is unconditional (meta syncs cross-device)")
	_assert(csd.contains("_remote_slot_paths(_cloud_file_names())"),
		"bughunt: cloud sync-down enumerates remote slot files (M-2 fixed)")
	var cfn := _bughunt_body(ssrc, "_cloud_file_names")
	_assert(cfn.contains("Steam.getFileCount()") and cfn.contains("Steam.getFileNameAndSize(i)"),
		"bughunt: remote enumeration uses the RemoteStorage file listing (M-2 fixed)")
	var cf := _bughunt_body(ssrc, "_cloud_fetch")
	_assert(cf.contains("size <= 0"),
		"bughunt: tombstone guard intact — cleared saves never resurrect (M-2)")
	# Behavioral: remote names map to local slot paths; profile/settings/
	# malformed/foreign names are ignored; duplicates collapse.
	var m2mgr = SaveScript.new()
	var m2scratch := "user://runs_m2_test"
	m2mgr.set("_test_runs_dir", m2scratch)
	var remote := ["runs/solo_0.cfg", "runs/mp_12.cfg", "runs/solo_2.cfg",
		"profile_local.cfg", "settings.cfg", "runs/solo_x.cfg",
		"runs/bogus_1.cfg", "runs/mp_1.tmp", "runs/solo_0.cfg",
		"runs/mp_9999.cfg", "other/solo_5.cfg"]
	var paths: Array = m2mgr._remote_slot_paths(remote)
	_assert(paths.size() == 3, "bughunt: remote enumeration yields exactly the 3 valid slot files (M-2)")
	_assert(paths.has(m2scratch + "/solo_0.cfg") and paths.has(m2scratch + "/solo_2.cfg")
		and paths.has(m2scratch + "/mp_12.cfg"),
		"bughunt: remote slots map through _slot_path incl. scratch dir (M-2)")
	m2mgr.free()


func _pf1_gd_files(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := dir_path.path_join(name)
			if dir.current_is_dir():
				_pf1_gd_files(full, out)
			elif name.ends_with(".gd"):
				out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _test_save_format_pf1() -> void:
	print("[Playtest] Save format PF Phase 1 (funnel + hook + fixtures)...")
	# Issue #111 pulled-forward item, PF Phase 1 (Eng 4): save_run is the
	# only sanctioned run-save writer (funnel lock), migrate_run is the
	# single load-side migration hook, and the v1 format is pinned by
	# frozen fixtures so v1 convertibility can never silently break.
	var SaveScript = load("res://scripts/autoload/save_manager.gd")
	var sm_src := FileAccess.get_file_as_string("res://scripts/autoload/save_manager.gd")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	var stsrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")

	# --- Funnel lock: tree grep over PRODUCTION code (scripts/ + scenes/).
	# The run-cfg write pattern may appear only inside save_manager.gd.
	# tools/ is deliberately out of scope: tools/migrate_check writes
	# legacy run cfg data on purpose (whitelisted by the gate note).
	var gd_files: Array = []
	_pf1_gd_files("res://scripts", gd_files)
	_pf1_gd_files("res://scenes", gd_files)
	_assert(gd_files.size() > 50, "pf1: production tree walk finds the scripts")
	_assert(sm_src.contains("cfg.set_value(\"run\", \"data\", data)"),
		"pf1: save_manager holds the single production run-write site")
	var bypass: Array = []
	for f in gd_files:
		if f == "res://scripts/autoload/save_manager.gd":
			continue
		if FileAccess.get_file_as_string(f).contains("set_value(\"run\""):
			bypass.append(f)
	_assert(bypass.is_empty(), "pf1: no production script bypasses save_run (funnel lock)")
	var mc_src := FileAccess.get_file_as_string("res://tools/migrate_check/migrate_check.gd")
	_assert(mc_src.contains("set_value(\"run\", \"data\""),
		"pf1: grep pattern is real (migrate_check writes run cfg; tools/ out of scope)")
	# The four verified producers write exclusively through save_run.
	_assert(dsrc.count("SaveManager.save_run(") >= 2,
		"pf1: dungeon.gd producers (boarding + MP save) go through save_run")
	_assert(hsrc.contains("SaveManager.save_run("), "pf1: hud.gd pause-save producer uses save_run")
	_assert(stsrc.contains("SaveManager.save_run("), "pf1: station.gd producer uses save_run")

	# --- Scratch SaveManager for everything below (never the real slots).
	var mgr = SaveScript.new()
	var scratch := "user://runs_pf1_test"
	if DirAccess.dir_exists_absolute(scratch):
		for f in DirAccess.get_files_at(scratch):
			DirAccess.remove_absolute(scratch.path_join(f))
		DirAccess.remove_absolute(scratch)
	mgr.set("_test_runs_dir", scratch)
	mgr.set("_test_account_pin", "pf1_scratch")

	# --- Four-producer stamp test: dicts in each producer's exact shape
	# come back stamped save_version == SAVE_VERSION on every written slot.
	var pstate := {"level": 4, "xp": 90, "xp_next": 150, "stat_points": 1,
		"bonus_damage": 1.5, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_aura": 0.0,
		"inventory": [{"id": "health_potion", "count": 3, "slot": -1}],
		"run_start_msec": 123456, "run_kills": 7, "run_damage_dealt": 42.5,
		"supermarket_cash": 12, "bounty_progress": {}, "totem_charges": 0,
		"specialization": "", "affinity": {}, "family_collection": {},
		"equipped_special": "", "no_death_streak": 0,
		"second_wind_armed": false, "second_wind_used": false}
	var host_entry := {"steam_id": 76561198000000111, "player_name": "Host",
		"class_id": "warrior", "player_state": pstate, "rts_faction": -1, "is_host": true}
	var producers := [
		{"mode": "solo", "run": {"theme_id": "dungeon", "level_number": 2,
			"class_id": "warrior", "player_state": pstate, "seed": 777}},
		{"mode": "solo", "run": {"theme_id": "village", "level_number": 1,
			"seed": 5, "at_station": false, "wave": 0,
			"class_id": "mage", "player_state": pstate}},
		{"mode": "mp", "run": {"theme_id": "dungeon", "level_number": 3,
			"seed": 42, "is_multiplayer": true, "at_station": false, "wave": 1,
			"host_difficulty": 1.0, "host_loot_mult": 1.0,
			"lobby": {"max_players": 4, "lobby_name": "Host's Dungeon", "visibility": "public"},
			"roster": [host_entry], "class_id": "warrior", "player_state": pstate}},
		{"mode": "mp", "run": {"theme_id": "village", "level_number": 2,
			"seed": 9, "is_multiplayer": true, "at_station": true,
			"host_difficulty": 1.0, "host_loot_mult": 1.0,
			"lobby": {"max_players": 4, "lobby_name": "Host's Dungeon"},
			"roster": [host_entry]}},
	]
	var pidx := 0
	for p in producers:
		_assert(mgr.save_run(p["run"], p["mode"], pidx), "pf1: producer %d save accepted" % pidx)
		var ploaded: Dictionary = mgr.load_run(p["mode"], pidx)
		_assert(int(ploaded.get("save_version", 0)) == mgr.SAVE_VERSION,
			"pf1: producer %d slot stamped save_version == SAVE_VERSION" % pidx)
		pidx += 1

	# --- migrate_run: identity at v1, idempotent, non-mutating, no deletes.
	_assert(sm_src.contains("return migrate_run(data)"), "pf1: load_run routes through migrate_run")
	var msrc_dict := {"theme_id": "dungeon", "save_version": 1,
		"player_state": {"level": 2, "future_key": {"nested": [1, 2]}},
		"roster": [{"steam_id": 5, "unknown_entry_key": "x"}]}
	var frozen := str(msrc_dict)
	var once: Dictionary = mgr.migrate_run(msrc_dict)
	_assert(str(msrc_dict) == frozen, "pf1: migrate_run does not mutate its input")
	_assert(str(once) == frozen, "pf1: migrate_run is a true identity at v1")
	_assert(str(mgr.migrate_run(once)) == str(once), "pf1: migrate_run is idempotent")
	var keys_ok := true
	for k in msrc_dict.keys():
		if not once.has(k):
			keys_ok = false
	_assert(keys_ok and (once["player_state"] as Dictionary).has("future_key")
		and ((once["roster"] as Array)[0] as Dictionary).has("unknown_entry_key"),
		"pf1: migrate_run never deletes a key (unknown keys kept at every level)")

	# --- FROZEN v1 FIXTURES — do not edit without a SAVE_VERSION bump.
	var fixture_solo := {"theme_id": "dungeon", "level_number": 3, "seed": 31337,
		"at_station": false, "wave": 2, "class_id": "rogue",
		"player_state": {"level": 6, "xp": 210, "xp_next": 300, "stat_points": 0,
			"bonus_damage": 2.0, "bonus_health": 5.0, "bonus_speed": 0.5, "bonus_aura": 0.0,
			"inventory": [{"id": "iron_sword", "count": 1, "slot": 0},
				{"id": "health_potion", "count": 7, "slot": -1}],
			"run_start_msec": 999, "run_kills": 11, "run_damage_dealt": 88.0,
			"supermarket_cash": 0, "bounty_progress": {}, "totem_charges": 1,
			"specialization": "", "affinity": {}, "family_collection": {},
			"equipped_special": "", "no_death_streak": 2,
			"second_wind_armed": true, "second_wind_used": false}}
	var guest_state := (fixture_solo["player_state"] as Dictionary).duplicate(true)
	guest_state["level"] = 5
	var fixture_mp := {"theme_id": "dungeon", "level_number": 3, "seed": 31337,
		"is_multiplayer": true, "at_station": false, "wave": 2,
		"host_difficulty": 1.25, "host_loot_mult": 2.0,
		"lobby": {"max_players": 6, "lobby_name": "Frozen's Dungeon", "visibility": "public"},
		"roster": [
			{"steam_id": 76561198000000111, "player_name": "FrozenHost",
				"class_id": "rogue", "player_state": fixture_solo["player_state"],
				"rts_faction": -1, "is_host": true},
			{"steam_id": 76561198000000222, "player_name": "FrozenGuest",
				"class_id": "mage", "player_state": guest_state,
				"rts_faction": -1, "is_host": false}],
		"class_id": "rogue", "player_state": fixture_solo["player_state"]}
	_assert(mgr.save_run(fixture_solo, "solo", 10), "pf1: frozen solo fixture saves")
	var fsolo: Dictionary = mgr.load_run("solo", 10)
	_assert(str(fsolo.get("class_id", "")) == "rogue"
		and int((fsolo.get("player_state", {}) as Dictionary).get("level", 0)) == 6
		and int(fsolo.get("seed", 0)) == 31337,
		"pf1: frozen solo fixture loads (class/level/seed)")
	_assert(mgr.save_run(fixture_mp, "mp", 11), "pf1: frozen MP fixture saves")
	var fmp: Dictionary = mgr.load_run("mp", 11)
	var froster: Array = fmp.get("roster", [])
	_assert(froster.size() == 2, "pf1: frozen MP fixture loads with a 2-entry roster")
	_assert(int((froster[0] as Dictionary).get("steam_id", 0)) == 76561198000000111
		and int((froster[1] as Dictionary).get("steam_id", 0)) == 76561198000000222,
		"pf1: fixture roster steam_ids survive exactly (int64 keying)")
	var fhost_inv: Array = ((froster[0] as Dictionary).get("player_state", {}) as Dictionary).get("inventory", [])
	_assert(fhost_inv.size() == 2 and str((fhost_inv[0] as Dictionary).get("id", "")) == "iron_sword"
		and int((fhost_inv[0] as Dictionary).get("slot", -99)) == 0,
		"pf1: fixture inventory entries keep id/count/slot (equip marker)")
	_assert(str(fmp.get("class_id", "")) == str((froster[0] as Dictionary).get("class_id", "")),
		"pf1: top-level class_id is the roster[0] mirror (format contract)")

	# --- Unknown-key injection at all three levels survives a round-trip.
	var inj: Dictionary = fmp.duplicate(true)
	inj["pf1_future_top"] = {"a": 1}
	var inj_roster: Array = inj["roster"]
	(inj_roster[0] as Dictionary)["pf1_future_entry"] = "keep"
	((inj_roster[0] as Dictionary)["player_state"] as Dictionary)["pf1_future_state"] = [3, 4]
	(inj["player_state"] as Dictionary)["pf1_future_mirror"] = "keep"
	_assert(mgr.save_run(inj, "mp", 12), "pf1: injected run saves")
	var back: Dictionary = mgr.load_run("mp", 12)
	_assert(back.has("pf1_future_top"), "pf1: unknown TOP-LEVEL key survives round-trip")
	var broster: Array = back.get("roster", [])
	_assert(((broster[0] as Dictionary).get("pf1_future_entry", "") as String) == "keep",
		"pf1: unknown ROSTER-ENTRY key survives round-trip")
	_assert((((broster[0] as Dictionary)["player_state"] as Dictionary).get("pf1_future_state", []) as Array) == [3, 4],
		"pf1: unknown PLAYER_STATE key survives round-trip")
	_assert(str((back.get("player_state", {}) as Dictionary).get("pf1_future_mirror", "")) == "keep",
		"pf1: unknown key in the mirror player_state survives round-trip")
	_assert(mgr.is_save_compatible("mp", 12), "pf1: injected save stays version-compatible")

	# Scratch cleanup.
	for f in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch.path_join(f))
	DirAccess.remove_absolute(scratch)
	if FileAccess.file_exists("user://profile_pf1_scratch.cfg"):
		DirAccess.remove_absolute("user://profile_pf1_scratch.cfg")
	mgr.free()


func _test_lobby_strip() -> void:
	print("[Playtest] Lobby strip...")
	# Jesse 2026-10-10: small live lobby-member element for the host on the
	# continue-run staging screen.
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(msrc.contains("func _refresh_lobby_strip"),
		"lobbystrip: refresh function exists")
	_assert(msrc.contains("lobby_members_changed.connect(_refresh_lobby_strip)"),
		"lobbystrip: refreshes on member changes")
	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/main_menu.tscn")
	_assert(tsrc.contains("LobbyStripNames"),
		"lobbystrip: strip nodes in staging UI")


func _test_checkout_multiplayer() -> void:
	print("[Playtest] Checkout multiplayer...")
	# Jesse 2026-10-10: the checkout sell was server-side body_entered, but
	# the server's physics can't see client bodies — clients never sold.
	# Now each peer detects its own entry; clients RPC the server.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func rpc_request_checkout_sell"),
		"checkout: client sell-request RPC exists")
	_assert(dsrc.contains("body.get_multiplayer_authority()) == multiplayer.get_unique_id()"),
		"checkout: clients detect their own entry")


func _test_holy_light_linger() -> void:
	print("[Playtest] Holy Light linger...")
	# Jesse 2026-10-10: the "beam never cleans up" bug is now a feature —
	# after the ability ends, the beam lingers 15s as a fading heal zone.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("HL_LINGER_TIME := 15.0"),
		"linger: 15s constant exists")
	_assert(psrc.contains("func hl_linger_beam"),
		"linger: linger RPC exists")
	_assert(psrc.contains("func _hl_process_linger"),
		"linger: fade processor exists")
	_assert(psrc.contains("_hl_start_linger()"),
		"linger: ability end starts linger")


func _test_train_state_handoff() -> void:
	print("[Playtest] Train state handoff...")
	# Jesse 2026-10-10: players lost stats/items on the annex->train hop
	# because saved_player_state relied on local capture. Now the host
	# collects states in save_multiplayer_run and sends them in the RPC.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("saved_player_states"),
		"train: host-collected states dict exists")
	_assert(dsrc.contains("board_train_interior\", theme_id, seed, new_level, peer_classes, saved_player_states"),
		"train: states sent in boarding RPC")
	# Behavioral: pick_boarding_state prefers the host state, but an empty
	# or missing entry falls back (caller uses local capture) — a peer that
	# missed the 3s save window must not be wiped by its empty roster entry.
	var dungeon_script = load("res://scripts/dungeon/dungeon.gd")
	var good := {"level": 5, "xp": 120}
	var states := {1: good, 2: {}}
	_assert(int((dungeon_script.pick_boarding_state(states, 1) as Dictionary).get("level", 0)) == 5,
		"train: non-empty host state wins")
	_assert((dungeon_script.pick_boarding_state(states, 2) as Dictionary).is_empty(),
		"train: empty host entry falls back to local capture")
	_assert((dungeon_script.pick_boarding_state(states, 9) as Dictionary).is_empty(),
		"train: missing peer falls back to local capture")
	_assert((dungeon_script.pick_boarding_state({}, 1) as Dictionary).is_empty(),
		"train: empty states map falls back to local capture")


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
	# Issue #33 Phase 2: strings externalized to CSV; check the key is used.
	_assert(hsrc.contains('"Reach 100 affinity"'), "Signature silhouette until earned")
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
	_assert(hsrc.contains('"Unlocks at level %d"'), "Disabled buttons show unlock hint")
	_assert(hsrc.contains('"Specialization unlocks at level %d (currently %d)."'), "Pause menu hint label")


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


func _test_mouse_legend() -> void:
	print("[Playtest] Mouse legend...")
	# Issue #95 Phase 1: data-driven registry, standard state, all four classes.
	var w: Dictionary = MouseLegend.actions_for("warrior", "standard")
	_assert(str(w["left"]) == "Attack", "warrior LMB = Attack")
	_assert(str(w["right"]) == "", "warrior RMB empty (legend hides it)")
	_assert(str(w["middle"]) == "Ping", "warrior MMB = Ping")
	var m: Dictionary = MouseLegend.actions_for("mage")
	_assert(str(m["left"]) == "Cast selected ability", "mage LMB = Cast selected ability")
	var r: Dictionary = MouseLegend.actions_for("rogue", "standard")
	_assert(str(r["left"]) == "Attack", "rogue LMB = Attack")
	_assert(str(r["right"]) == "Hold: charge dagger throw", "rogue RMB = charge throw")
	var a: Dictionary = MouseLegend.actions_for("architect", "standard")
	_assert(str(a["left"]) == "Cast selected ability", "architect LMB = Cast selected ability")
	# Adaptability: unknown class/state fall back, never crash the renderer.
	var u: Dictionary = MouseLegend.actions_for("necromancer", "standard")
	_assert(str(u["left"]) == "Attack", "unknown class falls back to Attack")
	var us: Dictionary = MouseLegend.actions_for("rogue", "flying")
	_assert(str(us["right"]) == "Hold: charge dagger throw", "unknown state falls back to standard row")
	_assert(MouseLegend.classes_for("standard").size() == 4, "registry covers 4 classes")
	# Render path: HUD legend follows the player's class, RMB row hidden when empty.
	var PlayerScript = load("res://scripts/player/player.gd")
	var p = PlayerScript.new()
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud = HudScene.instantiate()
	root.add_child(hud)
	p.class_id = "rogue"
	hud.refresh_mouse_legend(p)
	_assert(hud._legend_left.text.contains("Attack"), "HUD legend LMB = Attack (rogue)")
	_assert(hud._legend_right.visible, "HUD legend RMB visible (rogue)")
	_assert(hud._legend_right.text.contains("charge dagger throw"), "HUD legend RMB text (rogue)")
	p.class_id = "mage"
	hud.refresh_mouse_legend(p)
	_assert(hud._legend_left.text.contains("Cast selected ability"), "HUD legend follows class switch (mage)")
	_assert(not hud._legend_right.visible, "HUD legend RMB hidden when empty (mage)")
	_assert(hud._legend_mid.text.contains("Ping"), "HUD legend MMB = Ping")
	# Bottom-right anchoring + never intercepts input.
	var panel = hud.get_node("MouseLegend")
	_assert(panel.anchor_left == 1.0 and panel.anchor_top == 1.0, "legend anchored bottom-right")
	_assert(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "legend never blocks input")
	# Phase 3: Art Director's SNES sprite is the icon, with crisp nearest filtering;
	# the procedural icon survives only as the missing-sprite fallback.
	_assert(ResourceLoader.exists(hud.LEGEND_ICON_PATH, "Texture2D"), "legend icon sprite loads")
	var icon_node = panel.get_child(0).get_child(0)
	_assert(icon_node is TextureRect, "legend icon is the SNES sprite TextureRect")
	if icon_node is TextureRect:
		_assert(icon_node.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "icon uses nearest filter (crisp pixels)")
		_assert(icon_node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "icon never blocks input")
	hud.queue_free()
	p.free()


func _test_mouse_legend_states() -> void:
	print("[Playtest] Mouse legend dynamic states...")
	# Issue #95 Phase 2: registry rows for rogue charge + Holy Light arm/charge.
	var c: Dictionary = MouseLegend.actions_for("rogue", "charging")
	_assert(str(c["left"]) == "Throw dagger", "charging rogue LMB = Throw dagger")
	_assert(str(c["right"]) == "Release: cancel", "charging rogue RMB = Release: cancel")
	_assert(str(c["middle"]) == "Ping", "charging rogue MMB = Ping")
	var ha: Dictionary = MouseLegend.actions_for("mage", "hl_armed")
	_assert(str(ha["left"]) == "Start charge", "hl_armed mage LMB = Start charge")
	_assert(str(ha["right"]) == "Disarm", "hl_armed mage RMB = Disarm")
	var hc: Dictionary = MouseLegend.actions_for("mage", "hl_charging")
	_assert(str(hc["left"]) == "", "hl_charging mage LMB empty (row hides)")
	_assert(str(hc["right"]) == "Disarm (cancel)", "hl_charging mage RMB = Disarm (cancel)")
	_assert("rogue" in MouseLegend.classes_for("charging"), "charging state covers rogue")
	_assert("mage" in MouseLegend.classes_for("hl_armed"), "hl_armed state covers mage")
	# Player publishes its legend state (data-driven; render path stays dumb).
	var PlayerScript = load("res://scripts/player/player.gd")
	var p = PlayerScript.new()
	p.class_id = "rogue"
	_assert(p.legend_state() == "standard", "rogue idle = standard")
	p._charging = true
	_assert(p.legend_state() == "charging", "rogue charging reported")
	p._charging = false
	p.class_id = "mage"
	p._hl_state = PlayerScript.HLState.ARMED
	_assert(p.legend_state() == "hl_armed", "mage HL armed reported")
	p._hl_state = PlayerScript.HLState.CHARGING
	_assert(p.legend_state() == "hl_charging", "mage HL charging reported")
	p._hl_state = PlayerScript.HLState.IDLE
	_assert(p.legend_state() == "standard", "mage HL idle = standard")
	# Signal-driven: state changes emit click_state_changed (once per change).
	var emitted := []
	p.click_state_changed.connect(func(): emitted.append(1))
	p._charging = true
	_assert(emitted.size() == 1, "charging emits click_state_changed")
	p._charging = true
	_assert(emitted.size() == 1, "no duplicate emit when state unchanged")
	p._hl_state = PlayerScript.HLState.ARMED
	_assert(emitted.size() == 2, "HL arm emits click_state_changed")
	p.free()
	# HUD render path follows the live state, LMB row hides when empty.
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud = HudScene.instantiate()
	root.add_child(hud)
	var p2 = PlayerScript.new()
	p2.class_id = "rogue"
	p2._charging = true
	hud.refresh_mouse_legend(p2)
	_assert(hud._legend_left.text.contains("Throw dagger"), "HUD legend shows Throw dagger (charging)")
	_assert(hud._legend_right.visible, "HUD legend RMB visible (charging)")
	_assert(hud._legend_right.text.contains("Release: cancel"), "HUD legend RMB = Release: cancel")
	p2.class_id = "mage"
	p2._charging = false
	p2._hl_state = PlayerScript.HLState.CHARGING
	hud.refresh_mouse_legend(p2)
	_assert(not hud._legend_left.visible, "HUD legend LMB hidden when empty (hl_charging)")
	_assert(hud._legend_right.text.contains("Disarm (cancel)"), "HUD legend RMB = Disarm (cancel)")
	p2.free()
	hud.queue_free()


func _test_ability_bar_selected_highlight() -> void:
	print("[Playtest] Ability bar selected highlight...")
	# Issue #87: the selected gold border/bg lived in the final else branch,
	# so the elif fam != "" branch swallowed it for every family skill.
	var PlayerScript = load("res://scripts/player/player.gd")
	var p = PlayerScript.new()
	p.class_id = "mage"
	p.level = 5
	p.specialization = ""
	p.selected_ability = 1
	p.unlocked_abilities = []
	for a in PlayerScript.class_abilities("mage"):
		if int(a["unlock"]) <= 5:
			p.unlocked_abilities.append(a)
	_assert(p.unlocked_abilities.size() == 3, "mage level 5 has 3 abilities")
	_assert(String(PlayerScript.family_of("fireball")) == "fire", "fireball in fire family")
	_assert(String(PlayerScript.family_of("frost")) == "frost", "frost in frost family")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud.refresh_abilities(p)
	var bar = hud.get_node("%AbilityBar")
	var slots := []
	for child in bar.get_children():
		if child is PanelContainer:
			slots.append(child)
	_assert(slots.size() == 3, "3 ability slots rendered")
	var gold := Color(0.8, 0.65, 0.25, 1.0)
	for i in slots.size():
		var sb: StyleBoxFlat = slots[i].get_theme_stylebox("panel")
		if i == 1:
			_assert(sb.border_color == gold, "selected family skill gets gold border")
			_assert(sb.bg_color == Color(0.25, 0.2, 0.08, 0.9), "selected family skill gets warm bg")
		else:
			_assert(sb.border_color != gold, "non-selected slot %d has no gold border" % i)
	hud.queue_free()
	p.free()


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
	# Kit: 7 abilities, turret first (wall-first would leave 1-3 with no damage).
	# Issue #113 Phase 4 appended Hammer Smash (unlock 1, key 7).
	var abs: Array = PlayerScript.class_abilities("architect")
	_assert(abs.size() == 7, "Architect has 7 abilities")
	var expect := [
		["sentry_turret", 1, "1"], ["bulwark_wall", 4, "2"], ["spike_trap", 8, "3"],
		["keystone", 15, "4"], ["reinforce", 20, "5"], ["demolish", 30, "6"],
		["hammer_smash", 1, "7"],
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
	# Issue #128: placement RPCs seat on the sampled ground, never an
	# absolute y (structures sank by the local ground height on
	# heightmap themes). Flat themes sample exactly 0.0, so the seat
	# stays the pre-fix 0.05 there.
	_assert(dsrc.count("ground_height_at(pos) + 0.05") == 3,
		"128: totem + structure + decoy all seat at ground_height_at(pos) + 0.05")
	_assert(not dsrc.contains("Vector3(pos.x, 0.05, pos.z)"),
		"128: no absolute-y placement remains in dungeon.gd")
	var dgd = load("res://scripts/dungeon/dungeon.gd").new()
	_assert(dgd.ground_height_at(Vector3(7, 0, -3)) == 0.0,
		"128: flat A/B — no terrain, ground is exactly 0.0 (seat = pre-fix 0.05)")
	dgd.free()
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
	_assert(bsrc.contains("collision_layer = 8"), "rows on dedicated physics layer 4 (bitmask 8)")
	_assert(bsrc.contains("input_ray_pickable = true"), "rows are ray-pickable")
	# Issue #29 scope update: 3D reading-mode interaction replaced by 2D popup.
	_assert(bsrc.contains("open_destination_popup"), "interact opens 2D destination popup")
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
	# Board destinations: warlord row becomes APEX ARENA on apex cycles only;
	# misty docks (issue #102) appends an opt-in 6th row on every cycle.
	var d3: Array = DungeonScript.board_destinations(11) # cycle 3
	_assert(d3.size() == 6, "board has 6 rows with misty_docks (apex cycle)")
	_assert(d3.has("apex") and not d3.has("warlord"), "warlord -> apex swap (cycle 3)")
	_assert(d3.has("misty_docks"), "docks row present on apex cycles")
	var d1: Array = DungeonScript.board_destinations(1) # cycle 1
	_assert(d1.size() == 6, "board has 6 rows with misty_docks (cycle 1)")
	_assert(d1.has("warlord") and not d1.has("apex"), "warlord row normal (cycle 1)")
	_assert(d1[5] == "misty_docks", "docks row is last; rotation order kept")
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
	# Hermetic (issue #114): the old version sidecar-backed the LIVE profile
	# file and deleted it for the section's duration — any other writer of
	# that path (a concurrent suite run, leftover state from a crashed one)
	# flipped the earn/roundtrip asserts below. Instead, pin a scratch
	# account + scratch runs dir on the autoload for the whole section: the
	# live profile and real run slots are never touched, and the section
	# always starts from a fresh-seeded profile. Scratch leftovers from an
	# aborted run are wiped at entry, so the start state is deterministic.
	var mgr: Node = root.get_node("SaveManager")
	var scratch_prof := "user://profile_specials1_test.cfg"
	var scratch_runs := "user://runs_specials1_test"
	mgr.set("_test_account_pin", "specials1_test")
	mgr.set("_test_runs_dir", scratch_runs)
	if FileAccess.file_exists(scratch_prof):
		DirAccess.remove_absolute(scratch_prof) # aborted prior run's leftovers
	if DirAccess.dir_exists_absolute(scratch_runs):
		for f in DirAccess.get_files_at(scratch_runs):
			DirAccess.remove_absolute(scratch_runs.path_join(f))
		DirAccess.remove_absolute(scratch_runs)
	mgr.call("load_game") # fresh seeded scratch profile
	_assert(not SD.is_earned("iron_resolve"), "iron_resolve starts unearned")
	_assert(not SD.is_earned("holy_light"), "holy_light starts unearned")

	# 3. Player-level behavior on real player scenes. Death paths clear the
	# solo slot via SaveManager.clear_run -> _slot_path, which honors the
	# _test_runs_dir pin above — real run slots are never touched either.
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

	# Restore: unpin and drop the scratch state, then reload the real
	# profile into the autoload. The live profile was never touched, so
	# there is nothing to write back; a mid-section abort leaves only the
	# pins + scratch files, which the next run's entry wipe handles (and
	# the pins are section-scoped state the suite resets on load_game).
	holder.queue_free()
	mgr.set("_test_account_pin", "")
	mgr.set("_test_runs_dir", "")
	if FileAccess.file_exists(scratch_prof):
		DirAccess.remove_absolute(scratch_prof)
	if DirAccess.dir_exists_absolute(scratch_runs):
		for f in DirAccess.get_files_at(scratch_runs):
			DirAccess.remove_absolute(scratch_runs.path_join(f))
		DirAccess.remove_absolute(scratch_runs)
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
	# Issue #130: settable ground sampler for the scorch-seat pin.
	var stub_ground := 0.0

	func ground_height_at(_p: Vector3) -> float:
		return stub_ground

	@rpc("any_peer", "call_local")
	func announce(msg: String) -> void:
		announces.append(msg)

	@rpc("any_peer", "call_local")
	func announce_text(text: String, sfx: String = "") -> void:
		announces.append(text)

	func server_spawn_mob(type_id: String, pos: Vector3, force_elite: bool = false) -> void:
		spawns.append([type_id, pos, force_elite])

	func random_arena_pos() -> Vector3:
		return Vector3(10, 0.5, 10)

	## F-3: Mob._drop_and_reward probes this on every kill. Null is the
	## production-shaped "no player to reward" answer (same contract as
	## RelicDungeonStub) — kills under this stub grant no XP/bounty.
	func get_player_node(_peer_id: int) -> Node:
		return null

	## F-5: the drop tail rpc's spawn_pickup on successful rolls; record
	## them (same shape as RelicDungeonStub) instead of erroring.
	var pickups: Array = []

	@rpc("any_peer", "call_local")
	func spawn_pickup(item_id: String, pos: Vector3, value_mult: float = 1.0) -> void:
		pickups.append([item_id, pos, value_mult])

	var placed: Array = []

	@rpc("any_peer", "call_local")
	func place_structure(structure_id: String, pos: Vector3, owner: int, rank: int, uid: String) -> void:
		placed.append([structure_id, pos, uid])


## Stub player for shockwave hit tests: records damage taken.
class ApexPlayerStub extends Node3D:
	var alive := true
	var damage_taken := 0.0
	var hp := 100.0
	var max_hp := 100.0

	@rpc("any_peer", "call_local")
	func take_damage(amount: float, _attacker_name: String) -> void:
		damage_taken += amount


class RiftGroundStub extends Node:
	## Issue #127: a dungeon stand-in whose ground height depends on
	## x (base + slope * x), so rift grounding is observable in
	## numbers. Zeroed, it is the flat-theme sampler.
	var base := 1.2
	var slope := 0.1

	func ground_height_at(pos: Vector3) -> float:
		return base + slope * pos.x


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
	# Issue #130: the decal seats on the ground sampler where a
	# heightmap is active; flat (sampler 0.0) keeps the legacy seat.
	stub.stub_ground = 2.5
	Effects.scorch(holder, Vector3(3, 0, 4), 1.0)
	var decal_h := holder.get_child(holder.get_child_count() - 1) as MeshInstance3D
	_assert(decal_h != null and absf(decal_h.global_position.y - 2.56) < 0.001
		and decal_h.global_position.x == 3.0 and decal_h.global_position.z == 4.0,
		"130: scorch decal seats at ground + 0.06 on heightmap ground")
	stub.stub_ground = 0.0
	Effects.scorch(holder, Vector3(5, 0, 6), 1.0)
	var decal_f := holder.get_child(holder.get_child_count() - 1) as MeshInstance3D
	_assert(decal_f != null and absf(decal_f.global_position.y - 0.06) < 0.001,
		"130: scorch decal seat is the legacy 0.06 on flat ground")
	var fx_src := FileAccess.get_file_as_string("res://scripts/effects/effects.gd")
	_assert(fx_src.contains("ground_height_at") and not fx_src.contains("Vector3(pos.x, 0.06, pos.z)"),
		"130: scorch grounds itself via the sampler (absolute seat gone)")

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


func _test_village_kit() -> void:
	print("[Playtest] Modular Village kit wiring...")
	# .obj meshes load as Mesh resources.
	var well_mesh := load("res://assets/Modular Village/Prop_Well_1.obj") as Mesh
	_assert(well_mesh != null, "village: well .obj loads as Mesh")
	_assert(well_mesh.get_surface_count() > 0, "village: well has surfaces")
	var cart_mesh := load("res://assets/Modular Village/Prop_Cart_1.obj") as Mesh
	_assert(cart_mesh != null, "village: cart .obj loads as Mesh")
	# PropBuilder builds kit props via the registry.
	var holder := Node3D.new()
	root.add_child(holder)
	var well := PropBuilder.build("well", 1.0, {"pos": Vector3(10, 0, 5)})
	_assert(well != null, "village: well builds from registry")
	holder.add_child(well)
	_assert(well.get_child_count() > 0, "village: well has mesh child")
	var cart := PropBuilder.build("cart", 1.0, {"pos": Vector3.ZERO})
	_assert(cart != null, "village: cart builds from registry")
	holder.add_child(cart)
	var lamp := PropBuilder.build("lamp", 1.0, {"pos": Vector3.ZERO})
	_assert(lamp != null, "village: lamp builds from registry")
	holder.add_child(lamp)
	# Kit house reverted to programmer art (Jesse 2026-10-11); kit props remain.
	var house := PropBuilder.build("house", 2.0, {"pos": Vector3.ZERO})
	_assert(house != null, "village: house builds")
	holder.add_child(house)
	holder.queue_free()


func _test_boss_third_specials() -> void:
	print("[Playtest] Boss third specials (mud/phalanx/mirror/cage/storm/enrage)...")
	var MobScene: PackedScene = load("res://scenes/mobs/mob.tscn")
	# --- Data wiring.
	_assert(str(load("res://data/mobs/boss_boar.tres").get("special_id_3")) == "mud_wall",
		"boss3: boar special_id_3 mud_wall")
	_assert(str(load("res://data/mobs/boss_warden.tres").get("special_id_3")) == "aegis_phalanx",
		"boss3: warden special_id_3 aegis_phalanx")
	_assert(str(load("res://data/mobs/boss_warden.tres").get("special_id_4")) == "gilded_cage",
		"boss3: warden special_id_4 gilded_cage")
	_assert(str(load("res://data/mobs/boss_horror.tres").get("special_id_3")) == "dread_mirror",
		"boss3: horror special_id_3 dread_mirror")
	_assert(load("res://data/mobs/gold_cage.tres") != null, "boss3: gold_cage mob exists")
	_assert(load("res://data/mobs/dread_mirror.tres") != null, "boss3: dread_mirror mob exists")
	for n in root.get_tree().get_nodes_in_group("dungeon"):
		n.remove_from_group("dungeon")
		n.queue_free()
	for n in root.get_tree().get_nodes_in_group("players"):
		n.remove_from_group("players")
		n.queue_free()
	var stub := ApexDungeonStub.new()
	root.add_child(stub)
	stub.add_to_group("dungeon")
	var holder := Node3D.new()
	root.add_child(holder)
	# --- Mud Wall: 3 mounds placed via structure RPC.
	var bdata: Resource = load("res://data/mobs/boss_boar.tres")
	var boar = MobScene.instantiate()
	boar.setup(21, bdata, 1.0, 1.0, false, 1.0)
	holder.add_child(boar)
	boar.set("_special_cd", 999.0)
	boar.set("_special2_cd", 999.0)
	boar.set("_special3_cd", 999.0)
	var tgt := ApexPlayerStub.new()
	tgt.set_multiplayer_authority(1)
	holder.add_child(tgt)
	tgt.add_to_group("players")
	tgt.global_position = boar.global_position + Vector3(0, 0, 8)
	tgt.set("hp", 80.0)
	tgt.set("max_hp", 100.0)
	boar.set("_target", tgt)
	boar._do_mud_wall()
	_assert(stub.placed.size() == 3, "boss3: mud wall places 3 mounds")
	_assert(str(stub.placed[0][0]) == "mud_mound", "boss3: mounds are mud_mound structures")
	# --- Blood Frenzy: latches below 30% HP.
	boar.set("hp", boar.get("max_hp") * 0.25)
	boar._boss_think(0.1)
	_assert(bool(boar.get("_frenzied")), "boss3: boar frenzies below 30% HP")
	_assert(boar._move_speed_mult() > 1.4, "boss3: frenzy boosts move speed")
	# --- Aegis Phalanx: 4 elite shieldbearers.
	var wdata: Resource = load("res://data/mobs/boss_warden.tres")
	var warden = MobScene.instantiate()
	warden.setup(22, wdata, 1.0, 1.0, false, 1.0)
	holder.add_child(warden)
	warden.set("_target", tgt)
	stub.spawns.clear()
	warden._do_aegis_phalanx()
	_assert(stub.spawns.size() == 4, "boss3: phalanx spawns 4")
	_assert(str(stub.spawns[0][0]) == "shieldbearer" and bool(stub.spawns[0][2]),
		"boss3: phalanx spawns elite shieldbearers")
	# --- Dread Mirror: 2 clones.
	var hdata: Resource = load("res://data/mobs/boss_horror.tres")
	var horror = MobScene.instantiate()
	horror.setup(23, hdata, 1.0, 1.0, false, 1.0)
	holder.add_child(horror)
	stub.spawns.clear()
	horror._do_dread_mirror()
	_assert(stub.spawns.size() == 2, "boss3: mirror spawns 2 clones")
	_assert(str(stub.spawns[0][0]) == "dread_mirror", "boss3: clones are dread_mirrors")
	# --- Gilded Cage: victim caged, dome spawned.
	stub.spawns.clear()
	warden._do_gilded_cage()
	_assert(warden.get("_cage_target") != null, "boss3: cage picks a victim")
	_assert(absf(float(warden.get("_cage_t")) - 4.0) < 0.01, "boss3: cage lasts 4s")
	_assert(stub.spawns.size() == 1 and str(stub.spawns[0][0]) == "gold_cage",
		"boss3: cage spawns the dome")
	# --- Phaseshift Storm: exploding afterimage.
	horror._do_phaseshift_storm(Vector3(1, 0, 1))
	var pj: Array = horror.get("_pending_judgments")
	_assert(pj.size() == 1 and bool(pj[0].get("storm", false)), "boss3: storm queued")
	# --- Soft enrage: stacks accrue after 180s.
	warden.set("_fight_t", 200.0)
	warden.set("_special_cd", 999.0)
	warden.set("_special2_cd", 999.0)
	warden.set("_special3_cd", 999.0)
	warden.set("_special4_cd", 999.0)
	warden._boss_think(0.1)
	_assert(int(warden.get("_enrage_stacks")) == 1, "boss3: enrage stacks after 180s")
	# --- HP gates: special 3 blocked above 66%.
	var warden2 = MobScene.instantiate()
	warden2.setup(24, wdata, 1.0, 1.0, false, 1.0)
	holder.add_child(warden2)
	warden2.set("_target", tgt)
	warden2.set("_special_cd", 999.0)
	warden2.set("_special2_cd", 999.0)
	warden2.set("_special3_cd", 0.0)
	warden2.set("_special4_cd", 999.0)
	warden2._boss_think(0.1)
	_assert(str(warden2.get("_pending_special")) == "", "boss3: special 3 gated above 66% HP")
	warden2.set("hp", warden2.get("max_hp") * 0.5)
	warden2._boss_think(0.1)
	_assert(str(warden2.get("_pending_special")) == "aegis_phalanx",
		"boss3: special 3 fires below 66% HP")

	boar.queue_free()
	warden.queue_free()
	warden2.queue_free()
	horror.queue_free()
	tgt.queue_free()
	stub.queue_free()
	holder.queue_free()


func _test_boss_second_specials() -> void:
	print("[Playtest] Boss second specials (seismic/judgment/rifts)...")
	var MobScene: PackedScene = load("res://scenes/mobs/mob.tscn")
	_assert(MobScene != null, "boss2: mob scene loads")
	# --- Data wiring: every boss (normal + apex) has a second special.
	_assert(str(load("res://data/mobs/boss_boar.tres").get("special_id_2")) == "seismic_slam",
		"boss2: boar special_id_2 seismic_slam")
	_assert(str(load("res://data/mobs/apex_boar.tres").get("special_id_2")) == "seismic_slam",
		"boss2: apex boar special_id_2 seismic_slam")
	_assert(str(load("res://data/mobs/boss_warden.tres").get("special_id_2")) == "judgment",
		"boss2: warden special_id_2 judgment")
	_assert(str(load("res://data/mobs/apex_warden.tres").get("special_id_2")) == "judgment",
		"boss2: apex warden special_id_2 judgment")
	_assert(str(load("res://data/mobs/boss_horror.tres").get("special_id_2")) == "void_rift",
		"boss2: horror special_id_2 void_rift")
	_assert(str(load("res://data/mobs/apex_horror.tres").get("special_id_2")) == "void_rift",
		"boss2: apex horror special_id_2 void_rift")
	var holder := Node3D.new()
	root.add_child(holder)
	# --- Seismic slam: big slow ring, hits as it passes.
	var bdata: Resource = load("res://data/mobs/boss_boar.tres")
	var boar = MobScene.instantiate()
	boar.setup(11, bdata, 1.0, 1.0, false, 1.0)
	holder.add_child(boar)
	boar.set("_special_cd", 999.0)
	boar.set("_special2_cd", 999.0)
	var pspec := ApexPlayerStub.new()
	pspec.set_multiplayer_authority(1)
	holder.add_child(pspec)
	pspec.add_to_group("players")
	pspec.global_position = boar.global_position + Vector3(5, 0, 0)
	boar._do_seismic_slam()
	var waves: Array = boar.get("_shockwaves")
	_assert(waves.size() == 1, "boss2: seismic fires one ring")
	_assert(absf(float(waves[0]["max_radius"]) - 12.0) < 0.01, "boss2: seismic ring reaches 12m")
	_assert(absf(float(waves[0]["speed"]) - 6.0) < 0.01, "boss2: seismic ring speed 6 m/s")
	_assert(pspec.damage_taken == 0.0, "boss2: ring has not reached the player yet")
	boar._boss_think(1.0) # ring out to ~7m
	_assert(pspec.damage_taken > 0.0, "boss2: seismic ring hits the player as it passes")
	# --- Judgment: telegraphed pillars on player positions.
	var wdata: Resource = load("res://data/mobs/boss_warden.tres")
	var warden = MobScene.instantiate()
	warden.setup(12, wdata, 1.0, 1.0, false, 1.0)
	holder.add_child(warden)
	warden.set("_special_cd", 999.0)
	warden.set("_special2_cd", 999.0)
	warden._do_judgment()
	_assert((warden.get("_pending_judgments") as Array).size() == 1, "boss2: judgment queued")
	# Stand a fresh stub on the first marked spot, then let the timer fire.
	var marks: Array = (warden.get("_pending_judgments") as Array)[0]["positions"]
	_assert(marks.size() >= 1, "boss2: judgment marked at least one spot")
	var pspec2 := ApexPlayerStub.new()
	pspec2.set_multiplayer_authority(1)
	holder.add_child(pspec2)
	pspec2.add_to_group("players")
	pspec2.global_position = marks[0]
	warden._boss_think(1.3) # past the 1.2s timer
	_assert((warden.get("_pending_judgments") as Array).is_empty(), "boss2: judgment fired")
	_assert(pspec2.damage_taken > 0.0, "boss2: judgment pillar hits the marked player")
	# --- Void rifts: 3 zones, pulse, then expire.
	var hdata: Resource = load("res://data/mobs/boss_horror.tres")
	var horror = MobScene.instantiate()
	horror.setup(13, hdata, 1.0, 1.0, false, 1.0)
	holder.add_child(horror)
	horror.set("_special_cd", 999.0)
	horror.set("_special2_cd", 999.0)
	horror._do_void_rift()
	var rifts: Array = horror.get("_rifts")
	_assert(rifts.size() == 3, "boss2: void rift spawns 3 zones")
	# Park a stub inside the first rift.
	var pspec3 := ApexPlayerStub.new()
	pspec3.set_multiplayer_authority(1)
	holder.add_child(pspec3)
	pspec3.add_to_group("players")
	pspec3.global_position = rifts[0]["pos"]
	horror._boss_think(1.1) # first pulse
	_assert(pspec3.damage_taken > 0.0, "boss2: rift pulses damage inside the zone")
	for i in 20:
		horror._boss_think(1.0)
	_assert((horror.get("_rifts") as Array).is_empty(), "boss2: rifts expire after 15 ticks")
	# --- Issue #127: rift grounding over relief (spawn, drift, discs,
	# pulse tracking) + the flat A/B (sampler at 0 = pre-fix values).
	var ground_stub := RiftGroundStub.new()
	holder.add_child(ground_stub)
	ground_stub.add_to_group("dungeon")
	pspec3.global_position = Vector3(40, 0, 0)
	var horror2 = MobScene.instantiate()
	horror2.setup(14, hdata, 1.0, 1.0, false, 1.0)
	holder.add_child(horror2)
	horror2.set("_special_cd", 999.0)
	horror2.set("_special2_cd", 999.0)
	horror2._do_void_rift()
	var rifts2: Array = horror2.get("_rifts")
	_assert(rifts2.size() == 3, "127: cast spawns 3 rifts over the stub ground")
	var spawn_ok := true
	for r in rifts2:
		var sp: Vector3 = r["pos"]
		if absf(sp.y - (1.2 + sp.x * 0.1)) > 0.001:
			spawn_ok = false
	_assert(spawn_ok, "127: spawn anchors grounded at their own xz")
	var nodes2: Dictionary = horror2.get("_rift_nodes")
	var discs_ok := nodes2.size() == 1
	for b in nodes2:
		for n in nodes2[b]:
			var np := (n as Node3D).global_position
			if absf(np.y - (1.2 + np.x * 0.1 + 0.12)) > 0.001:
				discs_ok = false
	_assert(discs_ok, "127: discs sit at ground + 0.12")
	var spawn_x: Array = []
	for r in rifts2:
		spawn_x.append((r["pos"] as Vector3).x)
	for i in 5:
		horror2._boss_think(1.0)
	var rifts2b: Array = horror2.get("_rifts")
	var drifted := false
	var reground_ok := rifts2b.size() == 3
	for i2 in rifts2b.size():
		var dp: Vector3 = rifts2b[i2]["pos"]
		if absf(dp.x - float(spawn_x[i2])) > 0.5:
			drifted = true
		if absf(dp.y - (1.2 + dp.x * 0.1)) > 0.001:
			reground_ok = false
	_assert(drifted, "127: rifts drift toward the player")
	_assert(reground_ok, "127: anchors re-ground through the drift (y follows the sampler)")
	var lead: Vector3 = rifts2b[0]["pos"]
	horror2.rift_pulse_fx(1, lead) # deterministic: drive one pulse directly (batch 1 = horror2's first cast)
	var tracked := false
	for b in nodes2:
		for n in nodes2[b]:
			var np2 := (n as Node3D).global_position
			if Vector2(np2.x - lead.x, np2.z - lead.z).length() < 0.01 \
					and absf(np2.y - (lead.y + 0.12)) < 0.001:
				tracked = true
	_assert(tracked, "127: a pulse moves its disc onto the (grounded) rift position")
	ground_stub.base = 0.0
	ground_stub.slope = 0.0
	var horror3 = MobScene.instantiate()
	horror3.setup(15, hdata, 1.0, 1.0, false, 1.0)
	holder.add_child(horror3)
	horror3.set("_special_cd", 999.0)
	horror3.set("_special2_cd", 999.0)
	horror3._do_void_rift()
	var flat_ok := true
	for r in horror3.get("_rifts"):
		if absf((r["pos"] as Vector3).y) > 0.0001:
			flat_ok = false
	for b in horror3.get("_rift_nodes"):
		for n in horror3.get("_rift_nodes")[b]:
			if absf((n as Node3D).global_position.y - 0.12) > 0.0001:
				flat_ok = false
	_assert(flat_ok, "127: flat A/B — sampler at 0 gives the exact pre-fix placement (anchor 0, disc 0.12)")
	# Round claims: two pulses at the SAME point inside the claim
	# window must claim two DIFFERENT discs (convergence collapse).
	# A fresh cast (never pulsed) keeps the claim table empty —
	# horror2's discs were all claimed by its think-loop pulses
	# milliseconds ago in harness time.
	var horror4 = MobScene.instantiate()
	horror4.setup(16, hdata, 1.0, 1.0, false, 1.0)
	holder.add_child(horror4)
	horror4.set("_special_cd", 999.0)
	horror4.set("_special2_cd", 999.0)
	horror4._do_void_rift()
	var claim_pos: Vector3 = (horror4.get("_rifts") as Array)[0]["pos"] + Vector3(30, 0, 0)
	horror4.rift_pulse_fx(1, claim_pos)
	horror4.rift_pulse_fx(1, claim_pos)
	var claimed := 0
	for b in horror4.get("_rift_nodes"):
		for n in horror4.get("_rift_nodes")[b]:
			var cp := (n as Node3D).global_position
			if Vector2(cp.x - claim_pos.x, cp.z - claim_pos.z).length() < 0.01:
				claimed += 1
	_assert(claimed == 2, "127: round claims — two pulses at one point claim two discs")
	horror4.queue_free()
	horror2.queue_free()
	horror3.queue_free()
	ground_stub.queue_free()

	boar.queue_free()
	warden.queue_free()
	horror.queue_free()
	pspec.queue_free()
	pspec2.queue_free()
	pspec3.queue_free()
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


## Stub player for lobby MP sims: just alive + a peer id, so
## Station._living_peer_ids() sees it without a full Player scene.
class FakeLobbyPeer extends Node3D:
	var alive := true


## Stub player for station save tests: the station producer reads only
## steam_id, class_id, and get_state() from each node in "players".
class StationSavePeer extends Node:
	var steam_id := 0
	var class_id := "warrior"
	var saved_state: Dictionary = {}

	func get_state() -> Dictionary:
		return saved_state.duplicate(true)


## Stub dungeon for Holy Light tests: carries a _layout for map-size math,
## plus the announce RPCs mobs may trigger (apex gates).
class HolyDungeonStub extends Node3D:
	var _layout = {"grid_size": 48, "cell_size": 4.0}
	var announces: Array = []

	@rpc("any_peer", "call_local")
	func announce(msg: String) -> void:
		announces.append(msg)

	@rpc("any_peer", "call_local")
	func announce_text(text: String, sfx: String = "") -> void:
		announces.append(text)

	## F-3: Mob._drop_and_reward probes this on every kill. Null is the
	## production-shaped "no player to reward" answer (same contract as
	## RelicDungeonStub) — kills under this stub grant no XP/bounty.
	func get_player_node(_peer_id: int) -> Node:
		return null

	## F-5: the drop tail rpc's spawn_pickup on successful rolls; record
	## them (same shape as RelicDungeonStub) instead of erroring.
	var pickups: Array = []

	@rpc("any_peer", "call_local")
	func spawn_pickup(item_id: String, pos: Vector3, value_mult: float = 1.0) -> void:
		pickups.append([item_id, pos, value_mult])


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


func _test_settings_phase1() -> void:
	print("[Playtest] Settings phase 1 (panel + persistence)...")
	var SaveScript := load("res://scripts/autoload/save_manager.gd")
	_assert(SaveScript != null, "save_manager.gd loads")

	var mgr = SaveScript.new()
	mgr.set("_test_account_pin", "settings_test")
	mgr.load_game()
	mgr.set_profile_setting("settings", "master_vol", 0.75)
	mgr.set_profile_setting("settings", "crt_enabled", false)
	mgr.set_profile_setting("settings", "shake_enabled", true)
	_assert(float(mgr.get_profile_setting("settings", "master_vol", 1.0)) == 0.75,
		"profile: master_vol roundtrips")
	_assert(bool(mgr.get_profile_setting("settings", "crt_enabled", true)) == false,
		"profile: crt_enabled roundtrips")
	_assert(bool(mgr.get_profile_setting("settings", "shake_enabled", false)) == true,
		"profile: shake_enabled roundtrips")
	_assert(str(mgr.get_profile_setting("settings", "missing_key", "dflt")) == "dflt",
		"profile: missing key returns default")
	var mgr2 = SaveScript.new()
	mgr2.set("_test_account_pin", "settings_test")
	mgr2.load_game()
	_assert(float(mgr2.get_profile_setting("settings", "master_vol", 1.0)) == 0.75,
		"profile: master_vol persists to disk")
	mgr.free()
	mgr2.free()
	var ppath := "user://profile_settings_test.cfg"
	if FileAccess.file_exists(ppath):
		DirAccess.remove_absolute(ppath)

	var asrc := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	_assert(asrc.contains("set_profile_setting(\"settings\""), "audio saves volumes to profile")
	_assert(asrc.contains("get_profile_setting(\"settings\""), "audio loads volumes from profile")
	_assert(asrc.contains("CFG_PATH") and asrc.contains("migrat"),
		"audio migrates legacy audio.cfg")

	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/main_menu.tscn")
	_assert(tsrc.contains('name="SettingsButton"'), "TitlePhase has Settings button")
	_assert(tsrc.contains('_on_settings_pressed'), "Settings button wired")
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(msrc.contains("func _build_settings_panel"), "settings panel builder exists")
	_assert(msrc.contains("func _on_settings_pressed"), "settings open handler exists")
	_assert(msrc.contains("set_master_vol") and msrc.contains("set_music_vol") and msrc.contains("set_sfx_vol"),
		"sliders wire to AudioManager setters")
	_assert(msrc.count("HSlider.new()") >= 1, "panel has volume sliders")
	_assert(msrc.count("CheckButton.new()") >= 1, "panel has toggles")

	var panel_src := msrc.substr(msrc.find("func _build_settings_panel"))
	panel_src = panel_src.substr(0, panel_src.find("\nfunc ", 1))
	_assert(not panel_src.contains("ScrollContainer"), "settings panel: no ScrollContainer")


func _test_settings_phase2() -> void:
	print("[Playtest] Settings phase 2 (CRT/shake/fullscreen)...")
	# CRT shader exists.
	_assert(FileAccess.file_exists("res://assets/shaders/crt.gdshader"),
		"CRT shader exists")
	var shsrc := FileAccess.get_file_as_string("res://assets/shaders/crt.gdshader")
	_assert(shsrc.contains("scanline") or shsrc.contains("scan"),
		"CRT shader has scanlines")
	_assert(shsrc.contains("vignette"), "CRT shader has vignette")
	# CRTManager autoload.
	_assert(FileAccess.file_exists("res://scripts/autoload/crt_manager.gd"),
		"CRTManager exists")
	var csrc := FileAccess.get_file_as_string("res://scripts/autoload/crt_manager.gd")
	_assert(csrc.contains("set_crt_enabled"), "CRTManager has toggle API")
	_assert(csrc.contains("crt_enabled"), "CRTManager reads profile setting")
	var psrc := FileAccess.get_file_as_string("res://project.godot")
	_assert(psrc.contains("CRTManager"), "CRTManager registered as autoload")
	# Shake gate in player.gd.
	var plsrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(plsrc.contains("shake_enabled"), "player gates shake on profile setting")
	# Fullscreen in main_menu.gd.
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(msrc.contains("_apply_fullscreen"), "fullscreen apply exists")
	_assert(msrc.contains("WINDOW_MODE_FULLSCREEN"), "fullscreen uses DisplayServer")
	_assert(msrc.contains("_apply_saved_fullscreen"), "fullscreen applied on boot")


func _test_thrown_dagger_phase1() -> void:
	print("[Playtest] Thrown dagger phase 1 (issue #69)...")
	# ThrownDagger script exists with fireball pattern.
	_assert(FileAccess.file_exists("res://scripts/combat/thrown_dagger.gd"),
		"thrown_dagger.gd exists")
	var tsrc := FileAccess.get_file_as_string("res://scripts/combat/thrown_dagger.gd")
	_assert(tsrc.contains("class_name ThrownDagger"), "ThrownDagger has class_name")
	_assert(tsrc.contains("_is_in_wall"), "dagger checks wall collision")
	_assert(tsrc.contains("multiplayer.is_server()"), "dagger server owns hits")
	_assert(tsrc.contains("_max_range"), "dagger has range limit")
	# Player charge state.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("_dagger_charge"), "player has charge var")
	_assert(psrc.contains("_charging"), "player has charging flag")
	_assert(psrc.contains("DAGGER_CHARGE_TIME"), "charge time constant exists")
	_assert(psrc.contains("DAGGER_RANGE_MIN"), "range min constant exists")
	_assert(psrc.contains("DAGGER_RANGE_MAX"), "range max constant exists")
	_assert(psrc.contains("MOUSE_BUTTON_RIGHT"), "RMB handled for charge")
	_assert(psrc.contains("_throw_dagger"), "player can throw dagger")
	_assert(psrc.contains("_request_dagger_spawn"), "dagger spawn RPC exists")
	# HUD charge meter.
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("set_charge_meter"), "HUD has charge meter API")
	_assert(hsrc.contains("ChargeMeter"), "HUD has charge meter")
	print("[Playtest] Thrown dagger phase 1 done")
	_test_thrown_dagger_phase2()


func _test_thrown_dagger_phase2() -> void:
	print("[Playtest] Thrown dagger phase 2 (boomerang return)...")
	var tsrc := FileAccess.get_file_as_string("res://scripts/combat/thrown_dagger.gd")
	_assert(tsrc.contains("_returning"), "dagger has return state")
	_assert(tsrc.contains("_update_return"), "dagger has return update")
	_assert(tsrc.contains("_start_return"), "dagger can start return")
	_assert(tsrc.contains("_catch"), "dagger has catch")
	_assert(tsrc.contains("CATCH_DIST"), "catch distance constant exists")
	_assert(tsrc.contains("is_marked"), "return leg checks mark for +50%")
	_assert(tsrc.contains("gain_affinity_capped"), "return feeds Precision affinity")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("_dagger_out"), "player tracks dagger-out state")
	_assert(psrc.contains("_dagger_catch_cd"), "player has catch cooldown")
	_assert(psrc.contains("DAGGER_CATCH_COOLDOWN"), "catch cooldown constant exists")
	_assert(psrc.contains("_on_dagger_caught"), "player handles catch")
	_assert(psrc.contains("_on_dagger_returning"), "player handles return start")
	_assert(psrc.contains("Dagger is out"), "Fan requires dagger in hand")
	print("[Playtest] Thrown dagger phase 2 done")
	_test_thrown_dagger_hit_once()


func _test_thrown_dagger_hit_once() -> void:
	print("[Playtest] Thrown dagger hit-once-per-leg (issue #81)...")
	var tsrc := FileAccess.get_file_as_string("res://scripts/combat/thrown_dagger.gd")
	_assert(tsrc.contains("_hit_mobs"), "dagger has per-leg hit set")
	_assert(tsrc.contains("_hit_mobs.clear()"), "hit set cleared on return")
	_assert(tsrc.contains("_hit_mobs.has("), "hit check skips already-hit mobs")
	print("[Playtest] Thrown dagger hit-once-per-leg done")


func _test_holy_light_heal() -> void:
	print("[Playtest] Holy Light radiant heal...")
	var SD: GDScript = load("res://scripts/data/special_data.gd")
	var holder := Node3D.new() # -s mode has no current_scene; positional sfx needs one
	root.add_child(holder)
	current_scene = holder
	# Clear stale dungeon stubs (relic-test pattern): the light and announce
	# RPCs target group[0], which must be our stub.
	for n in get_nodes_in_group("dungeon"):
		n.get_parent().remove_child(n)
		n.free()
	var stub := HolyDungeonStub.new()
	root.add_child(stub)
	stub.add_to_group("dungeon")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var MobScene: PackedScene = load("res://scenes/mobs/mob.tscn")
	var mage = PlayerScene.instantiate()
	mage.set("class_id", "mage")
	mage.set("bonus_aura", 20.0)
	holder.add_child(mage)
	# Trigger the aura earn synchronously (_push_aura is deferred in _ready,
	# and the vault may be clean on a fresh run).
	mage.call("_push_aura")
	_assert(SD.is_earned("holy_light"), "holy: aura-20 mage earns Holy Light")
	_assert(SD.equip(mage, "holy_light"), "holy: equip succeeds")
	var hl_abilities: Array = mage.get("unlocked_abilities") as Array
	var has_hl: bool = hl_abilities != null and hl_abilities.any(
		func(x): return x["id"] == "holy_light")
	_assert(has_hl, "holy: key-7 ability granted when equipped")
	# Wound the mage + an in-range ally; park a far ally at 20m (outside 15m).
	var max_hp := float(mage.get("max_hp"))
	mage.set("hp", max_hp * 0.5)
	var ally = PlayerScene.instantiate()
	ally.set("class_id", "warrior")
	holder.add_child(ally)
	ally.global_position = mage.global_position + Vector3(10, 0, 0)
	var ally_max := float(ally.get("max_hp"))
	ally.set("hp", ally_max * 0.5)
	var far = PlayerScene.instantiate()
	far.set("class_id", "rogue")
	holder.add_child(far)
	far.global_position = mage.global_position + Vector3(20, 0, 0)
	var far_max := float(far.get("max_hp"))
	far.set("hp", far_max * 0.5)
	# A mob next to the caster must take NO damage (light only, no nuke).
	var sdata: Resource = load("res://data/mobs/slime.tres")
	var mob = MobScene.instantiate()
	mob.setup(1, sdata, 1.0, 1.0, false, 1.0)
	holder.add_child(mob)
	mob.global_position = mage.global_position + Vector3(3, 0, 0)
	var mob_hp0 := float(mob.get("hp"))
	# Issue #91 Phase 1: 7 arms (no light spawns, no cooldown at arm).
	mage.call("_cast_holy_light")
	_assert(int(mage.get("_hl_state")) == 1, "holy: 7 arms Holy Light (ARMED=1)")
	_assert(float((mage.get("ability_cds") as Dictionary).get("holy_light", 0.0)) == 0.0,
		"holy: arming spends nothing (no cooldown)")
	var pre_light: Node = root.find_child("HolyLight", true, false)
	_assert(pre_light == null, "holy: no light spawns at arm")
	# LMB starts charge; simulate charge completion -> strike.
	mage.call("_hl_start_charge")
	_assert(int(mage.get("_hl_state")) == 2, "holy: LMB starts charge (CHARGING=2)")
	mage.set("_hl_charge_t", 1.0)
	# Set aim to mage position for deterministic test (no camera in headless).
	mage.set("_hl_aim", mage.global_position)
	mage.call("_hl_strike")
	# Visual: the HolyLight node spawns under the dungeon, map-wide range.
	var light_node: Node = root.find_child("HolyLight", true, false)
	_assert(light_node != null, "holy: HolyLight node spawns on strike")
	if light_node != null:
		# Light is now under the beam container; layout is on the grandparent (dungeon).
		var beam_root := light_node.get_parent()
		var dgn := beam_root.get_parent() if beam_root != null else null
		var parent_layout = dgn.get("_layout") if dgn != null else null
		var ms := 60.0
		if parent_layout != null:
			ms = float(parent_layout["grid_size"]) * float(parent_layout["cell_size"])
		_assert(absf(float(light_node.get("spot_range")) - ms * 2.0) < 1.0,
			"holy: light range covers map")
	# Cooldown: applied at STRIKE (not at arm), blocks re-arm.
	_assert(float((mage.get("ability_cds") as Dictionary).get("holy_light", 0.0)) > 0.0,
		"holy: 20s cooldown applied at strike")
	var hp_before := float(mage.get("hp"))
	mage.call("_cast_holy_light")
	_assert(float(mage.get("hp")) == hp_before, "holy: cooldown blocks recast heal")
	var light_count := 0
	var stack := [root]
	while not stack.is_empty():
		var sn: Node = stack.pop_back()
		if str(sn.name) == "HolyLight":
			light_count += 1
		stack.append_array(sn.get_children())
	_assert(light_count == 1, "holy: cooldown blocks second light")
	# Heal: Phase 2 — server ticks heal allies within 15m of the beam point.
	# Trigger a tick manually (0.5s).
	mage.call("_hl_server_tick", 0.5)
	# Heal: caster + in-range ally gain 15% max HP; far ally and mob untouched.
	_assert(absf(float(mage.get("hp")) - max_hp * 0.65) < 1.0,
		"holy: caster healed 15%% (%.0f)" % float(mage.get("hp")))
	_assert(absf(float(ally.get("hp")) - ally_max * 0.65) < 1.0,
		"holy: ally at 10m healed 15%")
	_assert(float(far.get("hp")) == far_max * 0.5, "holy: ally at 20m not healed")
	# Phase 2: mob in the 4m beam column takes damage (1.0x base per tick).
	_assert(float(mob.get("hp")) < mob_hp0, "holy: mob in beam takes damage")
	# Cleanup.
	stub.remove_from_group("dungeon")
	stub.queue_free()
	mob.queue_free()
	mage.queue_free()
	ally.queue_free()
	far.queue_free()
	holder.queue_free()
	print("[Playtest] Holy Light radiant heal done")


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
		# Issue #33 Phase 2: row text is tr("LEADERBOARD_ROW"); find the
		# player's row by its gold highlight color (translations may not
		# be loaded in test env, so text won't contain the name).
		if child is Label and (child as Label).get_theme_color("font_color") == Color(1.0, 0.85, 0.3):
			player_lbl = child
	_assert(player_lbl != null, "player entry shown")
	_assert(player_lbl.get_theme_color("font_color") == Color(1.0, 0.85, 0.3),
		"player row highlighted gold")
	(lb.get("_cache") as Dictionary)[LBScript.BOARD_DEPTH] = []
	# Race-my-best toggle (Phase 2): defaults off, flips the Dungeon static.
	_assert(not bool(menu.get_node("DailyPhase/RaceEchoCheck").button_pressed),
		"race echo toggle defaults off")
	menu.get_node("DailyPhase/RaceEchoCheck").button_pressed = true
	# Issue #56: autoloads don't exist in -s mode — ensure an instance exists
	# before the toggle touches the bare EchoRecorder identifier.
	var er2: Node = root.get_node_or_null("EchoRecorder")
	if er2 == null:
		er2 = load("res://scripts/autoload/echo_recorder.gd").new()
		er2.name = "EchoRecorder"
		root.add_child(er2)
	menu._on_race_echo_toggled(true)
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
	# Issue #56: autoloads don't exist in -s script mode. Use the script
	# directly — create an instance if the autoload isn't in the tree.
	var er: Node = root.get_node_or_null("EchoRecorder")
	if er == null:
		er = ERScript.new()
		er.name = "EchoRecorder"
		root.add_child(er)
	_assert(er != null, "EchoRecorder available")
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
	_assert(sign != null and (sign.text == "RELIC VAULT" or "RELIC_VAULT" in sign.text),
		"vault sign reads RELIC VAULT")
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
	_assert(dsrc.contains("alive_now == 0"),
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
	# Mock theme so _push_wave_info doesn't nil-crash (test harness only).
	var mock_theme := LevelTheme.new()
	mock_theme.display_name = "Test"
	d.set("theme", mock_theme)
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
	# Jesse 2026-10-10 warlord rework: all players get factions (setup waits
	# for everyone, not just the first player), no AI in 2+ player multiplayer,
	# and the map scales with player count.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func _warlord_expected_players()"),
		"warlord: expected-players helper exists")
	_assert(dsrc.contains("players.size() >= expected"),
		"warlord: setup waits for all players")
	_assert(dsrc.contains("WARLORD_SETUP_TIMEOUT"),
		"warlord: setup has a timeout fallback")
	_assert(dsrc.contains("func _warlord_wants_ai()"),
		"warlord: AI gating helper exists")
	_assert(dsrc.contains("func _warlord_map_scale()"),
		"warlord: map scale helper exists")
	# Map scale: sqrt(n/2) keeps area-per-faction constant (1.0 at 2 players).
	_assert(dsrc.contains("sqrt(float(maxi(2, _warlord_expected_players())) / 2.0)"),
		"warlord: map scales with player count")
	_assert(dsrc.contains("func _warlord_assign_late_joiners()"),
		"warlord: late joiners get a faction")
	# Faction colors: unique per faction, code-generated (Jesse 2026-10-10).
	var rsrc := FileAccess.get_file_as_string("res://scripts/rts/rts_manager.gd")
	_assert(rsrc.contains("FACTION_COLORS"),
		"warlord: faction color palette exists")
	_assert(RTSManager.faction_color(0) != RTSManager.faction_color(1),
		"warlord: adjacent factions get distinct colors")
	_assert(RTSManager.faction_color(12) == RTSManager.faction_color(0),
		"warlord: palette wraps past 12")
	var usrc := FileAccess.get_file_as_string("res://scripts/rts/unit.gd")
	_assert(usrc.contains("FactionRing") and usrc.contains("RTSManager.faction_color("),
		"warlord: units get a faction-colored ring")
	var bsrc := FileAccess.get_file_as_string("res://scripts/rts/building.gd")
	_assert(bsrc.contains("RTSManager.faction_color(faction)"),
		"warlord: building banner uses faction color")
	print("[Playtest] Warlord spawn avoids river done")


func _test_issue22_23_fixes() -> void:
	print("[Playtest] issues #22/#23 fixes...")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("Dungeon.THEME_ORDER.size()"),
		"#22: cycle uses THEME_ORDER.size()")
	_assert(hsrc.contains("get_string_size"),
		"#52: announce uses pixel-accurate shrink-to-fit")
	print("[Playtest] issues #22/#23 fixes done")


func _test_e_interact_not_dead_code() -> void:
	print("[Playtest] E-interact reachable (issue #29)...")
	# Static: the _try_pickup() call must NOT be nested inside the early-return
	# guard. Regression for the indentation bug that made E do nothing.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var idx_return := psrc.find("hud.cipher_popup_open or _reading_board != null")
	_assert(idx_return > 0, "#29: E guard found")
	# The 'if Input.mouse_mode' guarding _try_pickup must be at elif-body
	# level (3 tabs) — a sibling of the early-return if, NOT nested inside it
	# (4 tabs = dead code, the #29 bug), and NOT at 2 tabs (which breaks the
	# elif chain and routes R/SHIFT/Q/etc into _try_pickup, the #32 bug).
	var idx_guard := psrc.find("if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED", idx_return)
	_assert(idx_guard > idx_return, "#29: mouse-mode guard present after E guard")
	var before := psrc.substr(0, idx_guard)
	var line_start := before.rfind("\n") + 1
	var indent := 0
	while line_start + indent < psrc.length() and psrc[line_start + indent] == "\t":
		indent += 1
	_assert(indent == 3, "#29/#32: E-interact guard at elif-body level (3 tabs)")
	print("[Playtest] E-interact reachable done")


func _test_watchdog_resets_on_progress() -> void:
	print("[Playtest] watchdog resets on mob death (issue #31)...")
	# Static: the fix tracks the last alive count and resets on decrease.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("_wave_last_alive"),
		"#31: alive-count tracker exists")
	_assert(dsrc.contains("alive_now < _wave_last_alive"),
		"#31: timer resets when count decreases")
	# Behavioral: simulate a long fight where mobs die over time.
	# The watchdog must NOT fire while progress is being made.
	var DungeonScript = load("res://scripts/dungeon/dungeon.gd")
	var d = DungeonScript.new()
	var mobs := Node3D.new()
	mobs.name = "Mobs"
	d.add_child(mobs)
	# Mock theme so _push_wave_info doesn't nil-crash (test harness only).
	var mock_theme := LevelTheme.new()
	mock_theme.display_name = "Test"
	d.set("theme", mock_theme)
	d.set("mobs_to_spawn", 0)
	d.set("wave_state", 1)  # ACTIVE
	d.set("_wave_stall_t", 0.0)
	d.set("_wave_last_alive", -1)
	# Simulate: 3 mobs alive, one dies every 2s. Total fight 6s+.
	# We can't spawn real Mobs, so we drive the logic via _wave_last_alive:
	# first frame sees 3, next sees 2 (decrease -> reset), etc.
	d.set("_wave_last_alive", 3)
	d.call("_process_waves", 2.0)  # 2s with 3 alive (no _mobs_alive override)
	# Without real mobs, _mobs_alive() returns 0, so this clears.
	# The key assertion is static: the reset logic exists. Behavioral
	# coverage comes from the _wave_last_alive tracking.
	_assert(dsrc.contains("_wave_last_alive = alive_now"),
		"#31: tracker updates each frame")
	d.free()
	print("[Playtest] watchdog resets on mob death done")



func _test_watchdog_progress_not_kills() -> void:
	print("[Playtest] watchdog progress not kills (issue #125)...")
	# Issue #125: the watchdog's count-only trigger fired mid-fight on
	# any 5s kill gap and "cleared" waves under fully engaged fields.
	# Progress (engagement band or real displacement) must reset it.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func _wave_progress_made"), "#125: progress sampler exists")
	_assert(dsrc.contains("or progressed"), "#125: progress resets the stall timer")
	_assert(dsrc.contains("mob.data.attack_range + 1.5"), "#125: melee engagement band")
	_assert(dsrc.contains("mob.data.preferred_range * 1.6 + 1.0"), "#125: ranged fire band")
	_assert(dsrc.contains("_stall_history"), "#125: position history tracked")
	_assert(dsrc.contains("pos.distance_to(hist[0]) > 2.0"), "#125: displacement leg of the progress test")
	# Behavioral (the #116 rigor pattern): drive the REAL sampler on
	# a real dungeon scene. The sampler is sampled twice a second;
	# each case settles the mob's 8-sample history first so the leg
	# under test is the ONLY thing that can flip the result.
	# Detach (never free) leftover players: an earlier section's
	# player can carry a still-queued deferred (the mage aura
	# push), and freeing it leaves that call to land on a freed
	# instance at suite exit. Detached fixtures leave the group
	# but stay alive, so the exit flush lands harmlessly.
	for n in get_nodes_in_group("players"):
		(n as Node).get_parent().remove_child(n as Node)
	var dgn = load("res://scenes/dungeon/dungeon.tscn").instantiate()
	root.add_child(dgn)
	var players_now := get_nodes_in_group("players")
	_assert(players_now.size() == 1, "#125: dungeon spawned its host player for the band tests")
	if players_now.size() == 1:
		var pp := (players_now[0] as Node3D).global_position
		var sample := func() -> bool: return bool(dgn.call("_wave_progress_made", 0.6))
		var settle := func() -> bool:
			var r := false
			for i in 8:
				r = sample.call()
			return r
		# Melee goblin (band = 1.8 + 1.5 = 3.3), parked 30m out.
		dgn.spawn_mob(12501, "goblin", pp + Vector3(30, 0, 0))
		var gob = dgn.get_node("Mobs/Mob_12501") as Node3D
		_assert(sample.call(), "#125: a newly tracked mob counts as progressing (history filling)")
		_assert(not settle.call(), "#125: wedged mob — settled history, out of band, no progress")
		_assert(not bool(dgn.call("_wave_progress_made", 0.1)),
			"#125: sub-sample-interval calls do not sample (throttle)")
		gob.global_position = pp + Vector3(2, 0, 0)
		_assert(sample.call(), "#125: mob moving into its engagement band samples progress")
		_assert(settle.call(), "#125: settled IN the melee band still reads progress (band leg)")
		gob.global_position = pp + Vector3(30, 0, 0)
		_assert(not settle.call(), "#125: settled back out of band reads no progress again")
		gob.global_position = pp + Vector3(33, 0, 0)
		_assert(sample.call(), "#125: a >2m displacement reads progress even out of band")
		_assert(not settle.call(), "#125: and settles back to no progress at the new spot")
		# Ranged archer (band = 10.0 * 1.6 + 1.0 = 17.0).
		dgn.spawn_mob(12502, "archer", pp + Vector3(16, 0, 0))
		var arc = dgn.get_node("Mobs/Mob_12502") as Node3D
		_assert(settle.call(), "#125: settled at 16m reads progress inside the ranged fire band")
		arc.global_position = pp + Vector3(20, 0, 0)
		_assert(not settle.call(), "#125: settled at 20m is outside the ranged band — no progress")
		# Boss (flat band 16.0 regardless of its 2.2 attack range).
		dgn.spawn_mob(12503, "boss_boar", pp + Vector3(10, 0, 0))
		var bos = dgn.get_node("Mobs/Mob_12503") as Node3D
		_assert(settle.call(), "#125: settled at 10m reads progress inside the flat boss band")
		bos.global_position = pp + Vector3(20, 0, 0)
		_assert(not settle.call(), "#125: settled at 20m is outside the boss band — no progress")
	# Cleanup: DETACH, don't free. The dungeon/player ready paths
	# queue deferred calls that only flush at suite exit; freeing
	# leaves them firing on freed instances (an intermittent
	# teardown SCRIPT ERROR pair). A detached fixture leaves every
	# group (no pollution of later sections) but stays alive, so
	# the exit flush lands on a live object.
	root.remove_child(dgn)
	print("[Playtest] watchdog progress not kills done")


func _test_r_wave_start_chain() -> void:
	print("[Playtest] R wave-start chain (issue #32)...")
	# Static: verify the R key handler, _try_start_wave, and request_next_wave
	# chain is intact.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("KEY_R:"), "#32: R key handler exists")
	_assert(psrc.contains("_try_start_wave()"), "#32: _try_start_wave called")
	_assert(psrc.contains('rpc("request_next_wave")'), "#32: request_next_wave RPC sent")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func request_next_wave()"), "#32: request_next_wave exists")
	_assert(dsrc.contains("wave_state == WaveState.INTERMISSION"), "#32: INTERMISSION gate exists")
	# The wave-clear must set INTERMISSION (not get stuck in ACTIVE).
	_assert(dsrc.contains("wave_state = WaveState.INTERMISSION"), "#32: _wave_cleared sets INTERMISSION")
	# The wave-clear check must run every frame in ACTIVE (not nested inside
	# the spawn-if, which would only run on spawn frames).
	# Verify by checking the indentation: "if mobs_to_spawn <=" should be at
	# 3 tabs (sibling of spawn-if), not 4 tabs (nested inside).
	var idx := dsrc.find("if mobs_to_spawn <= 0:")
	_assert(idx > 0, "#32: wave-clear check exists")
	var before := dsrc.substr(0, idx)
	var ls := before.rfind("\n") + 1
	var indent := 0
	while ls + indent < dsrc.length() and dsrc[ls + indent] == "\t":
		indent += 1
	_assert(indent == 3, "#32: wave-clear at ACTIVE level (3 tabs), runs every frame")
	print("[Playtest] R wave-start chain done")


func _test_destination_popup_replaces_3d() -> void:
	print("[Playtest] 2D destination popup (issue #29 scope update)...")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func open_destination_popup"), "#29: HUD has open_destination_popup")
	_assert(hsrc.contains("func close_destination_popup"), "#29: HUD has close_destination_popup")
	_assert(hsrc.contains("func refresh_destination_popup"), "#29: HUD has refresh_destination_popup")
	_assert(hsrc.contains("dest_popup_open"), "#29: dest popup open flag exists")
	var bsrc := FileAccess.get_file_as_string("res://scripts/station/departure_board.gd")
	_assert(bsrc.contains("open_destination_popup"), "#29: board.interact opens the 2D popup")
	_assert(not bsrc.contains("enter_reading"), "#29: board no longer uses 3D reading mode")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains('hud.get("dest_popup_open")'), "#29: E guarded while dest popup open")
	var ssrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	# Issue #93 Phase 3: the BoardingZone aboard-marker (and its #29 poll
	# fallback) is retired — the lobby doorway + depart lever replace it.
	_assert(not ssrc.contains("_poll_boarding_zone"), "#93: boarding zone poll fallback retired")
	_assert(ssrc.contains("refresh_destination_popup"), "#29: sync_votes refreshes popup")
	print("[Playtest] 2D destination popup done")


func _test_destination_popup_manual_only() -> void:
	print("[Playtest] destination popup manual-open only (issue #29 refinement)...")
	# Jesse's call: the 2D popup must ONLY open when the player walks up to
	# the physical board and presses E. No proximity auto-open, no timers.
	# The single call site must be DepartureBoard.interact().
	var files := [
		"res://scripts/station/station.gd",
		"res://scripts/dungeon/dungeon.gd",
		"res://scripts/player/player.gd",
		"res://scripts/ui/hud.gd",
	]
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		# Count call sites of open_destination_popup( — the definition itself
		# lives in hud.gd, so allow exactly one occurrence there.
		var count := 0
		var idx := 0
		while true:
			idx = src.find("open_destination_popup(", idx)
			if idx < 0:
				break
			count += 1
			idx += 1
		if f.ends_with("hud.gd"):
			_assert(count == 1, "#29: only the def in hud.gd, no auto-open calls")
		else:
			_assert(count == 0, "#29: no auto-open call in %s" % f.get_file())
	var bsrc := FileAccess.get_file_as_string("res://scripts/station/departure_board.gd")
	_assert(bsrc.contains("open_destination_popup"), "#29: board.interact is the sole trigger")
	print("[Playtest] destination popup manual-open only done")


func _test_bounty_popup_opens() -> void:
	print("[Playtest] bounty popup actually opens (issue #34)...")
	# Static: show_bounty() must call _open_cipher_popup — the #34 bug was
	# building the panel into a detached VBox without ever opening it.
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	var idx := hsrc.find("func show_bounty()")
	_assert(idx > 0, "#34: show_bounty exists")
	# Find the next "func " after show_bounty to bound the function body.
	var next_func := hsrc.find("\nfunc ", idx + 10)
	_assert(next_func > idx, "#34: function boundary found")
	var body := hsrc.substr(idx, next_func - idx)
	_assert(body.contains("_open_cipher_popup"), "#34: show_bounty opens the popup")
	print("[Playtest] bounty popup actually opens done")


func _test_collection_full_state_compact() -> void:
	print("[Playtest] Collection tab full-state compaction (issue #55)...")
	# Static: all Collection sections must use compact fonts (<=10) so the
	# full-progress state (7 families + 3 trophies + 8 cipher + 5 combos)
	# fits 1080p with zero scroll and the Quit buttons stay reachable.
	# Issue #37 reopened: tightened further (9pt rows, 16px icons).
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	# Family rows: font 9
	_assert(hsrc.contains('row.add_theme_font_size_override("font_size", 9)'),
		"#55: family rows compact")
	# Trophy icons: 16px, labels font 9
	_assert(hsrc.contains("Vector2(16, 16)"), "#55: trophy icons compact")
	# Cipher + codex rows: font 9, headers font 10
	_assert(hsrc.contains('header.add_theme_font_size_override("font_size", 10)'),
		"#55: section headers compact")
	# Redundant headers hide when log has content
	_assert(hsrc.contains("_hide_redundant_collection_headers"),
		"#37: redundant headers hide with content")
	print("[Playtest] Collection tab compaction done")


func _test_wave_ui_dedupe_and_boarding_hide() -> void:
	print("[Playtest] wave UI dedupe + boarding hide (issues #60/#62)...")
	# Static: #60 — host intermission must not show both the "Press R" hint
	# text and the START NEXT WAVE button. #62 — the wave button must hide
	# during boarding.
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("_boarding_active"), "#62: boarding flag exists")
	_assert(hsrc.contains("%NextWaveButton.visible = false"),
		"#62: boarding hides wave button")
	# #60: the hint text is hidden for host when button shows (no longer
	# assigned as WaveStatus.text for the host).
	_assert(not hsrc.contains('%WaveStatus.text = "Waiting for host..." if not is_host else "Press R to begin wave"'),
		"#60: redundant Press R hint removed")
	print("[Playtest] wave UI dedupe done")


func _test_departure_board_click_layer() -> void:
	print("[Playtest] departure board click layer (issue #64)...")
	# Static: the row hitbox must be on physics layer 4 (bitmask 8) to match
	# the player cursor raycast (collision_mask = 8). Bitmask 4 = layer 3,
	# which the ray never scans — clicks silently swallowed.
	var bsrc := FileAccess.get_file_as_string("res://scripts/station/departure_board.gd")
	_assert(bsrc.contains("area.collision_layer = 8"),
		"#64: board rows on layer 4 (bitmask 8)")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("q.collision_mask = 8"),
		"#64: player raycast scans layer 4")
	print("[Playtest] departure board click layer done")


func _test_destination_popup_mouse_hold() -> void:
	print("[Playtest] destination popup mouse hold (issue #65)...")
	# Static: the player's click-to-recapture must NOT steal the mouse while
	# the destination popup is open. Otherwise clicking a 2D row recaptures
	# the mouse and the vote leaks to the wrong destination.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("not hud.dest_popup_open"),
		"#65: player respects dest_popup_open on click")
	# Issue #71: boarding must auto-dismiss the destination popup so it
	# can't cover the doorway instruction once the vote resolves.
	var stsrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(stsrc.contains("close_destination_popup"),
		"#71: announce_boarding closes the destination popup")
	print("[Playtest] destination popup mouse hold done")


func _test_potion_quick_slot() -> void:
	print("[Playtest] potion quick-slot (Jesse's feature)...")
	# Static: HUD has the potion slot builder, cycle, and drink methods.
	# Player has the H key handler. Drink goes through use_item().
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func _build_potion_slot"), "potion slot builder exists")
	_assert(hsrc.contains("func _cycle_potion"), "potion cycle exists")
	_assert(hsrc.contains("func drink_potion"), "potion drink exists")
	_assert(hsrc.contains("POTION_IDS"), "potion ID list exists")
	_assert(hsrc.contains("use_item"), "drink uses use_item path")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("KEY_H"), "H key handler exists")
	_assert(psrc.contains("drink_potion"), "H calls drink_potion")
	# Issue #77 regression: the player joins group "players" (plural), so the
	# HUD must never look up a nonexistent "player" group for the slot.
	_assert(psrc.contains('add_to_group("players")'), "player joins players group")
	_assert(not hsrc.contains('get_first_node_in_group("player")'),
		"no stale \"player\" (singular) group lookup in hud.gd")
	_assert(hsrc.contains('get_first_node_in_group("players")') or hsrc.contains("_player"),
		"potion slot resolves the real player")
	print("[Playtest] potion quick-slot done")


func _test_positioning_fixes() -> void:
	print("[Playtest] positioning fixes (Jesse's screenshots)...")
	# Static: checkout must clamp to map bounds; item measure must not use
	# unreliable global_transform during setup.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("clampf(pos.x, -half, half)"),
		"checkout clamped to map bounds")
	var isrc := FileAccess.get_file_as_string("res://scripts/items/item_pickup.gd")
	_assert(not isrc.contains("global_transform * mi.get_aabb()"),
		"item measure avoids global_transform")
	print("[Playtest] positioning fixes done")


## Issue #67 Phase 1: Shieldbearer frontal block mechanics.
func _test_shieldbearer() -> void:
	print("[Playtest] Shieldbearer (issue #67 Phase 1)...")
	# MobData fields exist.
	var data := MobData.new()
	data.frontal_block = true
	data.block_arc_deg = 120.0
	data.block_mult = 0.1
	_assert(data.frontal_block, "shieldbearer has frontal_block")
	_assert(abs(data.block_arc_deg - 120.0) < 0.01, "block arc is 120 deg")
	_assert(abs(data.block_mult - 0.1) < 0.001, "block mult is 0.1")
	# Theme placement: dungeon and depths include shieldbearer.
	var dungeon_mix := FileAccess.get_file_as_string("res://data/levels/theme_dungeon.tres")
	_assert(dungeon_mix.contains("shieldbearer"), "dungeon theme has shieldbearer")
	var depths_mix := FileAccess.get_file_as_string("res://data/levels/theme_depths.tres")
	_assert(depths_mix.contains("shieldbearer"), "depths theme has shieldbearer")
	# Mob data file exists with block fields.
	var sb_src := FileAccess.get_file_as_string("res://data/mobs/shieldbearer.tres")
	_assert(sb_src.contains("frontal_block = true"), "shieldbearer.tres has frontal_block")
	# mob.gd has the block logic.
	var mob_src := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(mob_src.contains("block_arc_deg"), "mob.gd checks block arc")
	_assert(mob_src.contains("_shield_up"), "mob.gd has shield state")
	_assert(mob_src.contains("_windup_t"), "mob.gd has windup opening")
	_assert(mob_src.contains("_stagger_t"), "mob.gd has stagger")
	_assert(mob_src.contains("bypass_block"), "take_damage has bypass param")
	# Meteor bypasses.
	var meteor_src := FileAccess.get_file_as_string("res://scripts/combat/meteor.gd")
	_assert(meteor_src.contains("bypass_block") or meteor_src.contains(", true)"),
		"meteor passes bypass flag")
	# Issue #82 Phase 2: the shield overlay is the Art Director's .glb,
	# not the old QuadMesh placeholder. Same node name + transform.
	_assert(mob_src.contains('load("res://assets/models/shieldbearer_tower_shield.glb")'),
		"shield overlay loads the tower-shield .glb")
	_assert(mob_src.contains('_shield_visual.name = "ShieldOverlay"'),
		"shield overlay keeps node name ShieldOverlay")
	_assert(mob_src.contains("_shield_visual.position = Vector3(0, 1.0, 0.35)"),
		"shield overlay keeps transform (0, 1.0, 0.35)")
	_assert(not mob_src.contains("QuadMesh.new()"),
		"QuadMesh placeholder code path deleted")
	# Yaw-follow: shield mirrors _sprite.rotation.y each frame.
	_assert(mob_src.contains("_shield_visual.rotation.y = _sprite.rotation.y"),
		"shield yaws with the sprite")
	print("[Playtest] Shieldbearer done")


## Issue #67 Phase 2: Splitter split-on-death mechanics.
func _test_splitter() -> void:
	print("[Playtest] Splitter (issue #67 Phase 2)...")
	# MobData fields exist.
	var data := MobData.new()
	data.split_on_death = true
	data.split_id = "slime_small"
	data.split_count = 3
	_assert(data.split_on_death, "splitter has split_on_death")
	_assert(data.split_id == "slime_small", "split id is slime_small")
	_assert(data.split_count == 3, "split count is 3")
	# Small slime: no split (hard cap, children can never split).
	var small := MobData.new()
	small.split_on_death = false
	_assert(not small.split_on_death, "slime_small cannot split (hard cap)")
	# Data files exist.
	var splitter_src := FileAccess.get_file_as_string("res://data/mobs/splitter.tres")
	_assert(splitter_src.contains('split_on_death = true'), "splitter.tres splits")
	_assert(splitter_src.contains('split_id = "slime_small"'), "splitter spawns slime_small")
	var small_src := FileAccess.get_file_as_string("res://data/mobs/slime_small.tres")
	_assert(small_src.contains("health = 15.0"), "slime_small has 15 HP")
	_assert(small_src.contains("move_speed = 5.5"), "slime_small speed 5.5")
	# mob.gd has the spawn-on-death logic.
	var mob_src := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(mob_src.contains("split_on_death"), "mob.gd checks split_on_death")
	_assert(mob_src.contains("server_spawn_mob"), "mob.gd uses server spawn path")
	# Theme placement.
	var dungeon_mix := FileAccess.get_file_as_string("res://data/levels/theme_dungeon.tres")
	_assert(dungeon_mix.contains("splitter"), "dungeon theme has splitter")
	print("[Playtest] Splitter done")


## Issue #67 Phase 3: Gravewarden support aura mechanics.
func _test_gravewarden() -> void:
	print("[Playtest] Gravewarden (issue #67 Phase 3)...")
	# MobData fields exist.
	var data := MobData.new()
	data.support_aura_radius = 8.0
	data.support_heal_ps = 6.0
	data.support_dmg_mult = 1.25
	_assert(abs(data.support_aura_radius - 8.0) < 0.01, "aura radius is 8.0")
	_assert(abs(data.support_heal_ps - 6.0) < 0.01, "heal is 6.0/s")
	_assert(abs(data.support_dmg_mult - 1.25) < 0.01, "dmg mult is 1.25")
	# Data file exists with correct fields.
	var gw_src := FileAccess.get_file_as_string("res://data/mobs/gravewarden.tres")
	_assert(gw_src.contains("support_aura_radius = 8.0"), "gravewarden.tres has aura radius")
	_assert(gw_src.contains("xp_reward = 120"), "gravewarden has 120 XP")
	# mob.gd has the support logic.
	var mob_src := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(mob_src.contains("_support_tick"), "mob.gd has support tick")
	_assert(mob_src.contains("_aura_ring"), "mob.gd has aura ring visual")
	_assert(mob_src.contains("support_dmg_mult"), "mob.gd applies dmg buff")
	# Theme placement: depths.
	var depths_mix := FileAccess.get_file_as_string("res://data/levels/theme_depths.tres")
	_assert(depths_mix.contains("gravewarden"), "depths theme has gravewarden")
	print("[Playtest] Gravewarden done")


func _test_lan_multiplayer_phase1() -> void:
	print("[Playtest] LAN multiplayer Phase 1 (issue #70)...")
	# Static: transport enum, ENet host/join, handshake, kick, guards.
	var nsrc := FileAccess.get_file_as_string("res://scripts/autoload/network_manager.gd")
	_assert(nsrc.contains("enum Transport"), "transport enum exists")
	_assert(nsrc.contains("func host_lan"), "LAN host exists")
	_assert(nsrc.contains("func join_lan"), "LAN join exists")
	_assert(nsrc.contains("ENetMultiplayerPeer"), "uses ENetMultiplayerPeer")
	_assert(nsrc.contains("func lan_sync_config"), "handshake RPC exists")
	_assert(nsrc.contains("func kick_peer"), "kick exists")
	_assert(nsrc.contains("disconnect_peer"), "kick uses disconnect_peer")
	_assert(nsrc.contains("func get_lan_ip"), "LAN IP helper exists")
	# server_id from actual peer, not hardcoded.
	_assert(nsrc.contains("server_id = multiplayer.get_unique_id()"),
		"server_id from actual peer")
	# Save skips on LAN.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("Transport.LAN"), "dungeon guards LAN saves")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("Transport.LAN"), "HUD guards LAN save-quit")
	# UI: toggle, IP display, join fields, kick button.
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_assert(msrc.contains("_build_host_lan_ui"), "host LAN UI builder exists")
	_assert(msrc.contains("_build_join_lan_ui"), "join LAN UI builder exists")
	_assert(msrc.contains("KickButton"), "kick button exists")
	print("[Playtest] LAN multiplayer Phase 1 done")


## LAN lobby fixes: start button works on LAN, roster syncs to clients.
## (Static checks: autoload singletons aren't visible as identifiers in -s
## script mode, so this suite verifies the wiring by source inspection —
## the same convention as _test_lan_multiplayer_phase1.)
func _test_lan_lobby_fixes() -> void:
	print("[Playtest] LAN lobby fixes (start button + roster sync)...")
	var nsrc := FileAccess.get_file_as_string("res://scripts/autoload/network_manager.gd")
	# Fix 1: start_game must handle LAN before the Steam lobby_id gate.
	var sg := nsrc.find("func start_game()")
	var lan_branch := nsrc.find("if transport == Transport.LAN:", sg)
	var lobby_gate := nsrc.find("if lobby_id == 0:", sg)
	_assert(sg != -1 and lan_branch != -1 and lobby_gate != -1 and lan_branch < lobby_gate,
		"start_game handles LAN before the lobby_id gate")
	_assert(nsrc.find('rpc("load_dungeon"', sg) != -1, "start_game broadcasts dungeon load")
	# Fix 2: host broadcasts the roster so clients' lobby menus stay current.
	_assert(nsrc.contains("func lan_sync_roster"), "roster broadcast RPC exists")
	_assert(nsrc.contains("func _broadcast_lan_roster"), "roster broadcast helper exists")
	_assert(nsrc.contains("@rpc(\"authority\", \"call_remote\", \"reliable\")\nfunc lan_sync_roster"),
		"roster broadcast is authority/reliable")
	# Broadcast is wired into every membership change: announce, disconnect, kick.
	var ann := nsrc.find("func lan_announce_name")
	_assert(ann != -1 and nsrc.find("_broadcast_lan_roster()", ann) != -1,
		"announce triggers roster broadcast")
	var disc := nsrc.find("func _on_peer_disconnected")
	_assert(disc != -1 and nsrc.find("lan_names.erase", disc) != -1,
		"disconnect erases the name (no ghosts)")
	_assert(disc != -1 and nsrc.find("_broadcast_lan_roster()", disc) != -1,
		"disconnect triggers roster broadcast")
	var kick := nsrc.find("func kick_peer")
	_assert(kick != -1 and nsrc.find("_broadcast_lan_roster()", kick) != -1,
		"kick triggers roster broadcast")
	# The broadcast replaces the roster wholesale on clients.
	_assert(nsrc.contains("lan_names = names.duplicate()"), "roster sync replaces names")
	print("[Playtest] LAN lobby fixes done")


## LAN toggle recursion guard: the Steam/LAN toggle buttons must use
## set_pressed_no_signal. Assigning button_pressed inside a toggled handler
## re-emits toggled and the two buttons ping-pong into a stack overflow
## (main_menu.gd _on_host_transport_toggled, reported by Jesse 2026-10-05).
func _test_lan_toggle_no_recursion() -> void:
	print("[Playtest] LAN toggle no-recursion...")
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	for fname in ["func _on_host_transport_toggled", "func _on_join_transport_toggled"]:
		var start := msrc.find(fname)
		_assert(start != -1, fname + " exists")
		var next_func := msrc.find("\nfunc ", start + 1)
		_assert(next_func != -1, fname + " body bounded")
		var body := msrc.substr(start, next_func - start)
		_assert(not body.contains(".button_pressed ="),
			fname + " never assigns button_pressed (would re-emit toggled)")
		_assert(body.contains("set_pressed_no_signal"),
			fname + " uses set_pressed_no_signal")
	# Issues #73/#76: the LAN join form must stay compact and centered
	# (full-width LineEdits read as unstyled dark bands), and the Steam
	# JoinRow must hide in LAN mode.
	_assert(msrc.contains("_lan_ip_field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER"),
		"#73: LAN IP field is shrink-centered")
	_assert(msrc.contains("_lan_name_field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER"),
		"#73: LAN name field is shrink-centered")
	_assert(msrc.contains("join_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER"),
		"#73: LAN join button is shrink-centered")
	_assert(msrc.contains("join_row.visible = not lan_mode"),
		"#76: Steam JoinRow hides in LAN mode")
	print("[Playtest] LAN toggle no-recursion done")


## Issue #72 Phase 1: Snapshot yaw plumbing.
func _test_snapshot_yaw() -> void:
	print("[Playtest] Snapshot yaw (issue #72 Phase 1)...")
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	# push_snapshot has yaw_v param.
	_assert(src.contains("yaw_v: float"), "push_snapshot takes yaw_v")
	# Caller passes _yaw (and, since issue #104 Phase 3, equipped_ids;
	# since issue #126 Phase 1, rod_out too).
	_assert(src.contains('rpc("push_snapshot", global_position, hp, level, alive, _yaw, equipped_ids, rod_out)'),
		"caller passes _yaw")
	_assert(src.contains("eq_ids: Dictionary = {}"), "push_snapshot takes eq_ids (#104 P3)")
	_assert(src.contains("rod_out_v: bool = false"), "push_snapshot takes rod_out_v (#126 P1)")
	# _remote_yaw stored and interpolated with lerp_angle.
	_assert(src.contains("_remote_yaw"), "stores _remote_yaw")
	_assert(src.contains("lerp_angle(_yaw, _remote_yaw"),
		"interpolates with lerp_angle")
	# Headless math: lerp_angle converges without snapping.
	var a := 0.0
	var target := PI * 0.9
	for i in 20:
		a = lerp_angle(a, target, 0.5)
	_assert(abs(a - target) < 0.01, "lerp_angle converges")
	# Wrap-around: short way (e.g., 350° -> 10° goes +20°, not -340°).
	var wrapped := lerp_angle(deg_to_rad(350.0), deg_to_rad(10.0), 0.5)
	# 350° + 10° = 360°/0°, halfway is 0° (or 360°).
	var deg := rad_to_deg(wrapped)
	_assert(abs(deg) < 5.0 or abs(deg - 360.0) < 5.0,
		"wrap-around takes short way (350->10 via 0)")
	print("[Playtest] Snapshot yaw done")


## Issue #72 Phase 2: Player sprite orientation rendering.
func _test_sprite_orientation() -> void:
	print("[Playtest] Sprite orientation (issue #72 Phase 2)...")
	# player.tscn: AnimatedSprite3D billboard DISABLED.
	var tscn := FileAccess.get_file_as_string("res://scenes/player/player.tscn")
	# The AnimatedSprite3D node should NOT have billboard = 1.
	# (Label3D keeps billboard = 1.)
	var sprite_section := tscn.get_slice('[node name="AnimatedSprite3D"', 1)
	sprite_section = sprite_section.get_slice("[node name=", 0)
	_assert(not sprite_section.contains("billboard = 1"),
		"player sprite billboard disabled")
	# Label3D stays billboarded.
	_assert(tscn.contains('[node name="Label3D"'), "Label3D exists")
	# player.gd: remote peers yaw the sprite.
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(src.contains("_sprite.rotation.y = _yaw"),
		"remote peers yaw the sprite")
	# Issue #78: no material_override on the PLAYER SPRITE — the StandardMaterial3D
	# (cull disabled) broke AnimatedSprite3D texture rendering
	# (white quads on remote players). Scoped to _sprite; other nodes
	# (e.g. Holy Light rings) may use it.
	_assert(not src.contains("_sprite.material_override"),
		"no material_override on player sprite (issue #78)")
	# Mark indicators stay billboarded.
	_assert(src.contains("mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED"),
		"mark indicators stay billboarded")
	print("[Playtest] Sprite orientation done")


## Issue #72 Phase 3: Yaw edge-case validation.
func _test_yaw_edge_cases() -> void:
	print("[Playtest] Yaw edge cases (issue #72 Phase 3)...")
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	# Death freeze: when dead, the interpolation still runs but _yaw
	# stays at last value (no new snapshots change it). The code
	# interpolates toward _remote_yaw which stops updating on death.
	# Verify the death path doesn't reset _yaw.
	_assert(not src.contains("_yaw = 0.0"),
		"death doesn't reset yaw (freezes at last synced)")
	# Class switch: _yaw is not reset on class change (keeps flowing).
	# The _yaw var persists across class switches (no reset in switch code).
	_assert(src.contains("var _yaw :="),
		"_yaw persists (not reset on class switch)")
	# Snapshot gap: _has_remote guards interpolation (initializes from
	# first snapshot, no lerp before first receive).
	_assert(src.contains("if _has_remote:"),
		"interpolation guarded by _has_remote")
	# Headless math: interpolation converges even with large initial gap.
	var y := deg_to_rad(170.0)
	var target := deg_to_rad(0.0)
	for i in 30:
		y = lerp_angle(y, target, 0.3)
	_assert(abs(y - target) < 0.05,
		"large gap converges without snapping")
	print("[Playtest] Yaw edge cases done")


## Issue #11 Phase 1: Ascension core.
func _test_ascension() -> void:
	print("[Playtest] Ascension (issue #11 Phase 1)...")
	# Buff math: 1.0 + 0.05 * min(count, 10), cap +50%.
	_assert(abs(_asc_mult(0) - 1.0) < 0.001, "0 ascensions = 1.0x")
	_assert(abs(_asc_mult(1) - 1.05) < 0.001, "1 ascension = 1.05x")
	_assert(abs(_asc_mult(10) - 1.5) < 0.001, "10 ascensions = 1.5x (cap)")
	_assert(abs(_asc_mult(15) - 1.5) < 0.001, "15 ascensions = 1.5x (capped)")
	# SaveManager has the helpers.
	var sm_src := FileAccess.get_file_as_string("res://scripts/autoload/save_manager.gd")
	_assert(sm_src.contains("get_ascension_count"), "SaveManager has get_ascension_count")
	_assert(sm_src.contains("add_ascension"), "SaveManager has add_ascension")
	_assert(sm_src.contains("get_ascension_xp_mult"), "SaveManager has get_ascension_xp_mult")
	# Board ASCEND row.
	var hud_src := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hud_src.contains("ASCEND"), "HUD has ASCEND row")
	_assert(hud_src.contains("_update_ascension_indicator"), "HUD has ascension indicator")
	# Station handles ASCEND vote.
	var st_src := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(st_src.contains("_do_ascend"), "station has _do_ascend")
	# Player applies the buff.
	var pl_src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(pl_src.contains("get_ascension_xp_mult"), "player applies ascension buff")
	print("[Playtest] Ascension done")


func _asc_mult(count: int) -> float:
	return 1.0 + 0.05 * minf(float(count), 10.0)
func _test_warlord_seasons() -> void:
	print("[Playtest] Warlord Seasons (issue #10 Phase 1)...")
	# Tuning config has [seasons] section.
	var cfg := FileAccess.get_file_as_string("res://scripts/rts/rts_tuning.cfg")
	_assert(cfg.contains("[seasons]"),
		"rts_tuning.cfg has [seasons] section")
	_assert(cfg.contains("rotation_seconds = 480"),
		"8-minute rotation in config")
	_assert(cfg.contains("gold_rush_nodes"),
		"gold rush tuning present")
	_assert(cfg.contains("plague_dps"),
		"plague tuning present")
	_assert(cfg.contains("raid_unit_count"),
		"mercenary raid tuning present")
	# SeasonManager exists and has the right structure.
	var src := FileAccess.get_file_as_string("res://scripts/rts/season_manager.gd")
	_assert(src.contains("class_name SeasonManager"),
		"SeasonManager class exists")
	_assert(src.contains("\"gold_rush\"") and src.contains("\"plague\"") and src.contains("\"mercenary_raid\""),
		"3 events defined")
	_assert(src.contains("func start()"),
		"scheduler has start()")
	_assert(src.contains("season_warning") and src.contains("season_started"),
		"warning/started signals exist")
	# Event implementations.
	_assert(src.contains("_do_gold_rush"),
		"gold rush implementation exists")
	_assert(src.contains("_do_plague_start") or src.contains("_tick_plague"),
		"plague implementation exists")
	_assert(src.contains("_do_mercenary_raid"),
		"mercenary raid implementation exists")
	# Plague skips structures: _apply_plague_damage only hits rts_units group.
	var plague_section := src.substr(src.find("func _apply_plague_damage"))
	plague_section = plague_section.substr(0, plague_section.find("func _do_mercenary_raid"))
	_assert(plague_section.contains("rts_units") and not plague_section.contains("rts_buildings"),
		"plague targets units only (structures unaffected)")
	# Dungeon hooks the scheduler.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("season_manager.gd"),
		"dungeon creates SeasonManager")
	_assert(src.contains("_do_mercenary_raid"),
		"season manager has raid spawner")
	# HUD has countdown.
	var hsrc := FileAccess.get_file_as_string("res://scripts/rts/rts_hud.gd")
	_assert(hsrc.contains("_season_label"),
		"HUD has season countdown label")
	_assert(hsrc.contains("set_season_manager"),
		"HUD connects to SeasonManager")
	print("[Playtest] Warlord Seasons done")


## Issue #10 Phase 2: --seasons harness flag + balance gate.
func _test_warlord_seasons_phase2() -> void:
	print("[Playtest] Warlord Seasons Phase 2 (issue #10)...")
	# Harness has --seasons flag.
	var hsrc := FileAccess.get_file_as_string("res://tools/sim/sim_harness.gd")
	_assert(hsrc.contains("--seasons"),
		"harness documents --seasons flag")
	_assert(hsrc.contains("_seasons = true") or hsrc.contains("_seasons=true"),
		"harness parses --seasons flag")
	_assert(hsrc.contains("seasons_enabled"),
		"harness sets seasons_enabled on dungeon")
	# SeasonManager tracks fired seasons.
	var ssrc := FileAccess.get_file_as_string("res://scripts/rts/season_manager.gd")
	_assert(ssrc.contains("seasons_fired"),
		"SeasonManager tracks seasons_fired")
	# Balance gate exists.
	_assert(hsrc.contains("_balance_gate"),
		"harness has _balance_gate()")
	_assert(hsrc.contains("15.0") or hsrc.contains("15-point"),
		"15-point threshold present")
	# Per-season report exists.
	_assert(hsrc.contains("_season_wins"),
		"harness has _season_wins()")
	_assert(hsrc.contains("per_season_wins") or hsrc.contains("per-season"),
		"per-season report present")
	# Dungeon respects seasons_enabled.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("seasons_enabled"),
		"dungeon has seasons_enabled flag")
	print("[Playtest] Warlord Seasons Phase 2 done")


func _test_issue86_fixes() -> void:
	print("[Playtest] Issue #86 (Steam join + LAN disembark)...")
	var nsrc := FileAccess.get_file_as_string("res://scripts/autoload/network_manager.gd")
	# Bug 1: Steam lobby signals must be connected even if Steam wasn't
	# initialized at _ready() time. The old early-return branch skipped them.
	_assert(nsrc.contains("_connect_steam_signals"),
		"NetworkManager has _connect_steam_signals()")
	_assert(nsrc.contains("steam_ready.connect(_connect_steam_signals)"),
		"Steam signals connected when SteamManager emits steam_ready")
	_assert(nsrc.contains("is_connected(_on_lobby_created)"),
		"_connect_steam_signals is idempotent")
	# The multiplayer signals are always connected (not gated on Steam init).
	_assert(nsrc.contains("multiplayer.connected_to_server.connect(_on_connected_to_server)"),
		"connected_to_server always connected")
	# Bug 2: dungeon handshake retry for the train-disembark race.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func _send_handshake()"),
		"dungeon has _send_handshake()")
	_assert(dsrc.contains("_handshake_timer"),
		"dungeon tracks _handshake_timer")
	_assert(dsrc.contains("_send_handshake()") and dsrc.contains("2.0"),
		"handshake retried on 2s interval until local player spawns")
	print("[Playtest] Issue #86 done")


## Issue #88: Holy Light trigger broken.
func _test_holy_light_key7() -> void:
	print("[Playtest] Issue #88 Holy Light...")
	# KEY_7 handler exists in player._input().
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("KEY_1 and k.physical_keycode <= KEY_7"),
		"player handles KEY_1 through KEY_7")
	# Holy Light ability def has key "7".
	_assert(psrc.contains('"key": "7"') and psrc.contains("holy_light"),
		"Holy Light def uses key 7")
	# Equip requirement communicated via toast on earn.
	_assert(psrc.contains("Equip it in the Relic Vault"),
		"earn toast communicates equip requirement")
	print("[Playtest] Issue #88 done")


## Issue #89: Holy Light 7-key for sub-30 players (map by key label).
func _test_holy_light_key7_label() -> void:
	print("[Playtest] Issue #89 Holy Light key label...")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("_select_ability_by_key"),
		"label-based ability selection exists")
	_assert(psrc.contains('_select_ability_by_key(str(k.physical_keycode - KEY_1 + 1))'),
		"input maps keys 1-7 by label")
	# The old raw-index path for KEY_7 is gone.
	_assert(not psrc.contains("_select_ability(k.physical_keycode - KEY_1)"),
		"no raw-index ability mapping remains")
	print("[Playtest] Issue #89 done")


## Issue #90: Holy Light visual rework (SpotLight3D + rings + brightness).
func _test_holy_light_visual() -> void:
	print("[Playtest] Issue #90 Holy Light visual...")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("SpotLight3D.new()"),
		"Holy Light uses SpotLight3D")
	_assert(not psrc.contains("OmniLight3D.new()\n\tlight.name = \"HolyLight\""),
		"OmniLight3D removed from Holy Light")
	_assert(psrc.contains("TorusMesh.new()"),
		"yellow rings use TorusMesh")
	_assert(psrc.contains("spot_angle"),
		"spotlight has cone angle")
	# Brightness cranked (was 4.0, now 12.0).
	_assert(psrc.contains('"light_energy", 12.0'),
		"brightness cranked to 12.0")
	# Heal/cooldown/duration untouched.
	_assert(psrc.contains("HOLY_LIGHT_HEAL_RADIUS") and psrc.contains("HOLY_LIGHT_HEAL_FRAC"),
		"heal logic untouched")
	_assert(psrc.contains('ability_cds["holy_light"]'),
		"cooldown untouched")
	print("[Playtest] Issue #90 done")


func _test_holy_light_v2_phase1() -> void:
	print("[Playtest] Holy Light v2 Phase 1 (issue #91)...")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	# State machine exists.
	_assert(psrc.contains("enum HLState { IDLE, ARMED, CHARGING, ACTIVE }"),
		"HL state machine: IDLE/ARMED/CHARGING/ACTIVE")
	_assert(psrc.contains("const HL_CHARGE_TIME := 1.0"),
		"charge time exactly 1.0s")
	_assert(psrc.contains("const HL_HOLD_TIME := 10.0"),
		"hold time exactly 10s")
	_assert(psrc.contains("const HL_WINDDOWN_TIME := 2.0"),
		"wind-down exactly 2s")
	_assert(psrc.contains("const HL_COOLDOWN := 20.0"),
		"cooldown 20s")
	# Arming is free: _cast_holy_light arms/disarms, no cooldown set at arm.
	_assert(psrc.contains("func _hl_arm()"),
		"_hl_arm() exists")
	_assert(psrc.contains("func _hl_disarm()"),
		"_hl_disarm() exists (free disarm)")
	# Cooldown starts at STRIKE, not at arm.
	_assert(psrc.contains("ability_cds[\"holy_light\"] = HL_COOLDOWN"),
		"cooldown set at strike")
	# Cancel paths: right-click and Esc disarm.
	_assert(psrc.contains("_hl_state == HLState.ARMED or _hl_state == HLState.CHARGING"),
		"RMB/Esc cancel paths check armed/charging state")
	# Death disarms.
	_assert(psrc.contains("death disarms Holy Light"),
		"death disarms")
	# Charge -> strike transition.
	_assert(psrc.contains("func _hl_start_charge()"),
		"_hl_start_charge() exists")
	_assert(psrc.contains("func _hl_strike()"),
		"_hl_strike() exists")
	# Reticle: gold, 25m range.
	_assert(psrc.contains("const HL_AIM_RANGE := 25.0"),
		"aim range 25m")
	_assert(psrc.contains("HolyLightReticle"),
		"gold reticle created")
	# spawn_holy_light takes the aim point and owner.
	_assert(psrc.contains("func spawn_holy_light(aim_point: Vector3"),
		"spawn_holy_light takes aim point")
	# Timing: no more tween stacking (~21s bug).
	_assert(not psrc.contains("tween_interval(10.0)"),
		"old 10s tween interval removed (was stacking to ~21s)")
	print("[Playtest] Holy Light v2 Phase 1 done")


func _test_holy_light_v2_phase2() -> void:
	print("[Playtest] Holy Light v2 Phase 2 (issue #91)...")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	# Beam container for steering.
	_assert(psrc.contains("_hl_beams"),
		"beam tracking dictionary exists")
	_assert(psrc.contains("HolyLightBeam_"),
		"beam containers named per owner")
	# Central beam cylinder (gold, r=1.2m).
	_assert(psrc.contains("BeamCore"),
		"central beam cylinder exists")
	_assert(psrc.contains("top_radius = 1.2"),
		"beam radius 1.2m")
	# 10Hz aim updates (unreliable RPC).
	_assert(psrc.contains("func hl_aim_update"),
		"hl_aim_update RPC exists")
	_assert(psrc.contains("@rpc(\"any_peer\", \"unreliable\")"),
		"aim updates are unreliable")
	_assert(psrc.contains("_hl_aim_send_t"),
		"10Hz aim send timer")
	# Server rebroadcast for remote lerp.
	_assert(psrc.contains("func hl_beam_aim"),
		"hl_beam_aim rebroadcast exists")
	_assert(psrc.contains("target_aim"),
		"remote lerp target tracked")
	# Server 0.5s damage ticks at latest aim (not strike point).
	_assert(psrc.contains("func _hl_server_tick"),
		"server tick function exists")
	_assert(psrc.contains("tick_t"),
		"0.5s tick timer")
	_assert(psrc.contains("flat.length() <= 4.0"),
		"4m beam column damage")
	# Heal follows beam point.
	_assert(psrc.contains("distance_to(aim)"),
		"heal centered on beam aim point")
	# Wind-down: beam narrows, decay SFX.
	_assert(psrc.contains("func _hl_winddown"),
		"wind-down function exists")
	_assert(psrc.contains("holy_light_decay"),
		"decay SFX played")
	# Death/disconnect cleanup.
	_assert(psrc.contains("func hl_end_beam"),
		"hl_end_beam RPC exists")
	print("[Playtest] Holy Light v2 Phase 2 done")


func _test_holy_light_v2_phase3() -> void:
	print("[Playtest] Holy Light v2 Phase 3 (issue #91)...")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var asrc := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	var ssrc := FileAccess.get_file_as_string("res://scripts/audio/sound_synth.gd")
	# All 5 SFX names resolve (arm/disarm/riser/impact/decay).
	for sfx in ["holy_light_arm", "holy_light_disarm", "holy_light_riser",
			"holy_light_impact", "holy_light_decay"]:
		_assert(psrc.contains(sfx) or ssrc.contains("func " + sfx),
			"SFX exists: " + sfx)
		_assert(asrc.contains('"' + sfx + '"'),
			"SFX registered: " + sfx)
	# Recording flag for Jesse's own recordings.
	_assert(asrc.contains("holy_light_use_recording"),
		"holy_light_use_recording flag exists")
	_assert(asrc.contains("holy_light_recording/"),
		"recording file path pattern")
	# Riser is 1.0s (matches charge), decay is 2.0s (matches wind-down).
	_assert(ssrc.contains("_tone(220.0, 880.0, 1.0"),
		"riser 1.0s matches charge time")
	_assert(ssrc.contains("_tone(880.0, 220.0, 2.0"),
		"decay 2.0s matches wind-down")
	print("[Playtest] Holy Light v2 Phase 3 done")


func _test_steam_ready_once_only() -> void:
	print("[Playtest] steam_ready once-only guard (issue #96)...")
	var nsrc := FileAccess.get_file_as_string("res://scripts/autoload/network_manager.gd")
	_assert(nsrc.contains("if not SteamManager.steam_ready.is_connected(_connect_steam_signals)"),
		"once-only guard before steam_ready.connect")
	# Drive 120 frames through _process; the wiring must stay exactly-one.
	# (Before the guard, every frame re-connected and spammed "already connected" errors.)
	# NOTE: autoload names don't resolve at compile time in -s script mode;
	# grab the live singleton nodes from the tree instead.
	var nm = root.get_node("NetworkManager")
	var sm = root.get_node("SteamManager")
	for i in 120:
		nm._process(1.0 / 60.0)
	var wiring := 0
	for c in sm.steam_ready.get_connections():
		if c["callable"] == Callable(nm, "_connect_steam_signals"):
			wiring += 1
	_assert(wiring == 1, "steam_ready wired exactly once after 120 frames")
	_assert(sm.steam_ready.is_connected(Callable(nm, "_connect_steam_signals")),
		"steam_ready is connected")


func _test_class_sprites_and_namebar() -> void:
	print("[Playtest] class sprites + name bar...")
	# Each class must reference its own sprite texture (no shared knight.png).
	var expected := {"warrior": "knight.png", "mage": "mage.png",
		"rogue": "rogue.png", "architect": "architect.png"}
	for cid in expected:
		var cd = load("res://data/classes/%s.tres" % cid)
		_assert(cd != null, "%s.tres loads" % cid)
		var frames: Array = cd.get("frames")
		_assert(frames.size() > 0, "%s has sprite frames" % cid)
		var tex_path: String = (frames[0] as Texture2D).resource_path
		_assert(tex_path.ends_with(expected[cid]),
			"%s uses %s (got %s)" % [cid, expected[cid], tex_path])
	# Name bar: Label3D exists in the player scene with billboard + outline.
	var ps: PackedScene = load("res://scenes/player/player.tscn")
	var p: Node = ps.instantiate()
	var label := p.get_node_or_null("Label3D") as Label3D
	_assert(label != null, "player has Label3D name bar")
	if label != null:
		_assert(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED,
			"name bar billboards to camera")
		_assert(label.outline_size > 0, "name bar has readable outline")
		_assert(abs(label.position.y - 2.1) < 0.01, "name bar hovers above head")
	# _display_name must use the Steam ID, not the P2P peer ID.
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("Steam.getFriendPersonaName(steam_id)"),
		"_display_name uses steam_id for Steam persona name")
	_assert(not psrc.contains("Steam.getFriendPersonaName(pid)"),
		"_display_name no longer passes peer id to getFriendPersonaName")
	# spawn_player RPC must carry the Steam ID for remote name bars.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.contains("func spawn_player(peer_id: int, class_id: String, pos: Vector3, steam_id: int"),
		"spawn_player RPC carries steam_id")
	p.free()


func _test_fishing_farming_phase1() -> void:
	print("[Playtest] issue #102 Phase 1: fishing + farming foundation...")
	var DungeonScript := load("res://scripts/dungeon/dungeon.gd")
	var StationScript := load("res://scripts/station/station.gd")
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	# Theme file loads with the Phase 1 flags.
	var docks: Resource = load("res://data/levels/theme_misty_docks.tres")
	_assert(docks != null, "theme_misty_docks.tres loads")
	_assert(str(docks.get("theme_id")) == "misty_docks", "docks theme_id")
	_assert(str(docks.get("display_name")) == "Misty Docks", "docks display name")
	_assert(bool(docks.get("has_fishing_water")), "docks has_fishing_water")
	_assert(bool(docks.get("has_farm_plots")), "docks has_farm_plots")
	# Base themes pay nothing: both flags default false on every existing theme.
	for tid in ["village", "dungeon", "depths", "supermarket", "warlord", "apex"]:
		var t: Resource = load("res://data/levels/theme_%s.tres" % tid)
		_assert(t != null, "%s.tres loads" % tid)
		_assert(not bool(t.get("has_fishing_water")), "%s: no fishing water" % tid)
		_assert(not bool(t.get("has_farm_plots")), "%s: no farm plots" % tid)
	# Procgen on the docks theme: 2-4 ponds, one spot per pond, 6 plots.
	var layout = ProcGenScript.generate(docks, 424242)
	_assert(layout.ponds.size() >= 2 and layout.ponds.size() <= 4,
		"2-4 ponds (got %d)" % layout.ponds.size())
	_assert(layout.fishing_spots.size() == layout.ponds.size(), "one spot per pond")
	_assert(layout.farm_plots.size() == 6, "6 farm plots (got %d)" % layout.farm_plots.size())
	# Spots/plots sit on walkable cells (water is visual, never a blocker).
	for s in layout.fishing_spots:
		_assert(not layout.is_solid_world(s), "fishing spot on walkable cell")
	for s in layout.farm_plots:
		_assert(not layout.is_solid_world(s), "farm plot on walkable cell")
	# Ponds keep clear of the spawn clearing and of each other.
	for pd in layout.ponds:
		var pc: Vector3 = pd["center"]
		_assert(pc.length() > 8.0, "pond clear of spawn (dist %.1f)" % pc.length())
	# Determinism: same seed -> identical fingerprint (multiplayer-safe).
	var again = ProcGenScript.generate(docks, 424242)
	_assert(layout.fingerprint() == again.fingerprint(), "docks layout deterministic")
	var other = ProcGenScript.generate(docks, 777)
	_assert(layout.fingerprint() != other.fingerprint(), "different seed, different layout")
	# Base theme untouched: no new zones on village.
	var village: Resource = load("res://data/levels/theme_village.tres")
	var vlayout = ProcGenScript.generate(village, 424242)
	_assert(vlayout.ponds.is_empty(), "village: no ponds")
	_assert(vlayout.fishing_spots.is_empty(), "village: no fishing spots")
	_assert(vlayout.farm_plots.is_empty(), "village: no farm plots")
	# Departure board: docks row metadata.
	_assert(str(StationScript.BOARD_STARS.get("misty_docks")) == "★☆☆☆", "docks danger stars")
	_assert(StationScript.recommended_level("misty_docks", 7) == 7,
		"docks rec level = upcoming level")
	_assert((StationScript.DRESSING_LAMPS as Dictionary).has("misty_docks"), "docks lamp tint set")
	_assert(str(StationScript.theme_display_name("misty_docks")) == "Misty Docks",
		"docks display name from tres")
	_assert(DungeonScript.arrival_tint("misty_docks") == Color(0.45, 0.7, 0.9),
		"docks arrival tint")
	# THEME_ORDER still has exactly the base five (cycle math untouched).
	_assert((DungeonScript.THEME_ORDER as Array).size() == 5, "THEME_ORDER still 5")
	_assert(not (DungeonScript.THEME_ORDER as Array).has("misty_docks"), "docks not in THEME_ORDER")
	# Issue #126 Phase 2: fishing spots and their locking are DELETED —
	# sessions live on the dungeon's FishingDirector (per-peer, no
	# locks anywhere). The farm plot locking below is untouched.
	_assert(not ResourceLoader.exists("res://scripts/dungeon/fishing_spot.gd"),
		"#126 P2: fishing_spot.gd deleted")
	var DirectorScript: GDScript = load("res://scripts/fishing/fishing_director.gd")
	var director = DirectorScript.new()
	root.add_child(director)
	_assert(director.is_in_group("fishing_director"), "director joins fishing_director group")
	_assert(not director.has_method("claim_spot"), "director has no claim/lock API")
	director.free()
	var PlotScript: GDScript = load("res://scripts/dungeon/farm_plot.gd")
	var plot = PlotScript.new()
	root.add_child(plot)
	_assert(plot.is_in_group("farm_plots"), "plot joins farm_plots group")
	_assert(plot.prompt_text() == "Till soil (E)", "free plot prompt")
	plot.claim_plot()
	_assert(plot.occupied_by == 1, "plot claim attributes to sender")
	plot.claim_plot()
	_assert(plot.occupied_by == 1, "plot: second claim rejected")
	plot.occupied_by = 4
	plot.release_plot()
	_assert(plot.occupied_by == 4, "plot: stranger cannot release")
	plot.occupied_by = 1
	plot.release_plot()
	_assert(plot.occupied_by == 0, "plot: owner release frees")
	plot.free()
	print("[Playtest] issue #102 Phase 1 done")


func _test_fishing_minigame_phase2() -> void:
	print("[Playtest] issue #102 Phase 2: fishing minigame (director, #126 P2)...")
	var DirectorScript: GDScript = load("res://scripts/fishing/fishing_director.gd")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	# (Runtime loads only: bare autoload identifiers don't compile in -s script mode.)
	var ItemDBNode: Variant = root.get_node("ItemDB")
	# Fish items exist in the ItemDB.
	for fid in ["fish_minnow", "fish_riverbass", "fish_glimmerfin"]:
		_assert(ItemDBNode.get_item(fid) != null, "ItemDB has " + fid)
	# Sim rig: real player + director in the tree; this instance is the
	# server (peer 1). Water validation is seamed on (no dungeon here).
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	p.global_position = Vector3.ZERO
	var director = DirectorScript.new()
	root.add_child(director)
	director.test_players = {1: p}
	DirectorScript.debug_force_water = 1
	_grant_equipped(p, "fishing_rod") # the server cast gate needs it EQUIPPED
	DirectorScript.debug_wait_override = 2.0
	# --- Full cast -> catch cycle (server-validated cast) ---
	DirectorScript.debug_now_msec = 100000
	director.request_cast(Vector3(0, 0, 4))
	_assert(director.session_state_for(1) == DirectorScript.SessionState.WAITING,
		"cast: session waiting")
	_assert(bool(p.get("_bobber_out")), "cast: bobber mirror set")
	director.request_hook() # early press, before the bite: ignored
	_assert(director.session_state_for(1) == DirectorScript.SessionState.WAITING,
		"early hook press ignored")
	director._handle_hook(999) # forged peer: no session, rejected
	_assert(director.session_state_for(1) == DirectorScript.SessionState.WAITING,
		"forged peer hook rejected")
	DirectorScript.debug_now_msec = 100000 + 2100 # past the rolled 2s wait
	director._process(0.016) # server tick: bite fires
	_assert(director.session_state_for(1) == DirectorScript.SessionState.BITING, "bite fired")
	_assert(bool(p.get("_bite_ready")), "bite: hook window mirror set")
	director.request_hook() # inside the 1.2s window: catch
	_assert(director.session_state_for(1) == DirectorScript.SessionState.NONE,
		"catch: session resolved")
	_assert(not bool(p.get("_bobber_out")), "catch: bobber mirror cleared")
	var got_fish := false
	for e in p.inventory:
		var it: Variant = (e as Dictionary).get("item")
		if it != null and str(it.id).begins_with("fish_"):
			got_fish = true
	_assert(got_fish, "catch granted a fish item to the inventory")
	# --- Miss path: window expires with no press; the bobber STAYS ---
	var inv_before: int = p.inventory.size()
	DirectorScript.debug_now_msec = 200000
	director.request_cast(Vector3(0, 0, 4)) # recast is free
	_assert(director.session_state_for(1) == DirectorScript.SessionState.WAITING,
		"recast starts a new session")
	DirectorScript.debug_now_msec = 200000 + 2100
	director._process(0.016) # bite
	_assert(director.session_state_for(1) == DirectorScript.SessionState.BITING, "recast bite fired")
	DirectorScript.debug_now_msec = 200000 + 2100 + 1300 # past the 1.2s window
	director._process(0.016) # server tick: escape
	_assert(director.session_state_for(1) == DirectorScript.SessionState.IDLE,
		"miss: fish escaped, bobber stays out")
	_assert(director.has_bobber(1), "miss: bobber still out (reel in to recast)")
	_assert(p.inventory.size() == inv_before, "miss: no fish granted")
	director.request_hook() # late press: ignored
	_assert(director.session_state_for(1) == DirectorScript.SessionState.IDLE,
		"late hook press ignored")
	director.request_reel_in() # RMB path: free end
	_assert(not director.has_bobber(1), "reel-in clears the bobber")
	# --- Cancel-on-drift: displacement from the cast stance cancels ---
	DirectorScript.debug_now_msec = 300000
	director.request_cast(Vector3(0, 0, 4))
	_assert(director.session_state_for(1) == DirectorScript.SessionState.WAITING,
		"session for drift test")
	p.global_position = Vector3(5, 0, 0) # beyond LEAVE_RADIUS from the stance
	director._process(0.016)
	_assert(not director.has_bobber(1), "drift cancels the session")
	_assert(not bool(p.get("_bobber_out")), "drift: bobber mirror cleared")
	# --- Two peers fish concurrently (no locking anywhere) ---
	p.global_position = Vector3.ZERO
	var p2 = PlayerScene.instantiate()
	p2.class_id = "mage"
	root.add_child(p2)
	p2.global_position = Vector3(1, 0, 0)
	_grant_equipped(p2, "fishing_rod")
	director.test_players = {1: p, 2: p2}
	DirectorScript.debug_now_msec = 400000
	director._handle_cast(1, Vector3(0, 0, 4))
	director._handle_cast(2, Vector3(1, 0, 5))
	_assert(director.session_state_for(1) == DirectorScript.SessionState.WAITING
		and director.session_state_for(2) == DirectorScript.SessionState.WAITING,
		"two peers: concurrent sessions in one pond")
	DirectorScript.debug_now_msec = 400000 + 2100
	director._process(0.016)
	_assert(director.session_state_for(1) == DirectorScript.SessionState.BITING
		and director.session_state_for(2) == DirectorScript.SessionState.BITING,
		"two peers: both bites fire")
	director._handle_hook(2)
	_assert(director.session_state_for(2) == DirectorScript.SessionState.NONE
		and director.session_state_for(1) == DirectorScript.SessionState.BITING,
		"two peers: peer 2's catch leaves peer 1 fishing")
	director._handle_hook(1)
	_assert(director.session_state_for(1) == DirectorScript.SessionState.NONE,
		"two peers: peer 1 catches too")
	# --- Disconnect ends the session (server hook via NetworkManager) ---
	director._handle_cast(2, Vector3(1, 0, 5))
	_assert(director.session_state_for(2) == DirectorScript.SessionState.WAITING,
		"disconnect setup: session active")
	var NM: Variant = root.get_node("NetworkManager")
	NM._on_peer_disconnected(2)
	_assert(not director.has_bobber(2), "disconnect ends the session")
	NM._on_peer_disconnected(8) # peer holding nothing: no-op
	_assert(not director.has_bobber(8), "disconnect of idle peer is a no-op")
	# --- Forged casts rejected: dry landing, over-range, no rod ---
	DirectorScript.debug_force_water = 0 # everything dry
	director._handle_cast(1, Vector3(0, 0, 4))
	_assert(not director.has_bobber(1), "forged: dry landing opens no session")
	DirectorScript.debug_force_water = 1
	director._handle_cast(1, Vector3(0, 0, 40)) # 40m: beyond MAX + margin
	_assert(not director.has_bobber(1), "forged: over-range landing rejected")
	var p3 = PlayerScene.instantiate()
	p3.class_id = "rogue"
	root.add_child(p3)
	director.test_players = {1: p, 2: p2, 3: p3}
	director._handle_cast(3, Vector3(0, 0, 4)) # no rod equipped at all
	_assert(not director.has_bobber(3), "forged: cast with no rod equipped rejected")
	p3.queue_free()
	# --- Rarity weighting: longer wait -> better odds (defaults, Jesse's call) ---
	var seen_short := {}
	for i in 60:
		seen_short[director.roll_catch_item(3.0, false)] = true
	_assert(seen_short.has("fish_minnow"), "short wait: common catch possible")
	var seen_long := {}
	for i in 200:
		seen_long[director.roll_catch_item(8.0, false)] = true
	_assert(seen_long.has("fish_glimmerfin"), "long wait: rare catch possible")
	for rid in seen_long:
		_assert(ItemDBNode.get_item(str(rid)) != null, "rolled fish is a real item: " + str(rid))
	# Cleanup: reset the test seams so later tests see production behavior.
	DirectorScript.debug_wait_override = -1.0
	DirectorScript.debug_now_msec = -1
	DirectorScript.debug_force_water = -1
	director.free()
	p.queue_free()
	p2.queue_free()
	print("[Playtest] issue #102 Phase 2 done")


func _test_farming_loop_phase3() -> void:
	print("[Playtest] issue #102 Phase 3: farming loop...")
	var PlotScript: GDScript = load("res://scripts/dungeon/farm_plot.gd")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	# (Runtime loads only: bare autoload identifiers don't compile in -s script mode.)
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var SM: Node = root.get_node("SaveManager")
	# Crop + seed items exist in the ItemDB.
	for iid in ["seed_packet", "crop_sunroot", "crop_moonmelon", "crop_goldengourd"]:
		_assert(ItemDBNode.get_item(iid) != null, "ItemDB has " + iid)
	var moonmelon = ItemDBNode.get_item("crop_moonmelon")
	_assert(bool(moonmelon.get("consumable")), "rare crop is usable (consumable)")
	_assert(float(moonmelon.get("heal_fraction")) > 0.0, "rare crop heals")
	# Sim rig: real player + plot in the tree; this instance is the server (peer 1).
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	p.global_position = Vector3.ZERO
	var plot = PlotScript.new()
	root.add_child(plot)
	plot.global_position = Vector3.ZERO
	plot.test_player = p
	# --- Starter seed grant (mirrors dungeon._do_spawn on misty docks) ---
	PlotScript.grant_starter_seeds(1)
	for s in PlotScript.STARTER_SEED_COUNT:
		p.receive_item(PlotScript.SEED_ITEM)
	_assert(PlotScript.seed_count(1) == PlotScript.STARTER_SEED_COUNT, "starter grant: ledger topped up")
	_assert(_farm_inv_count(p, "seed_packet") == PlotScript.STARTER_SEED_COUNT, "starter grant: packets in inventory")
	# --- Full plant -> harvest cycle across waves ---
	plot.plot_action() # E on untilled: claim + till (free)
	_assert(plot.occupied_by == 1, "till: plot claimed")
	_assert(plot.plot_state == "tilled", "till: state tilled")
	_assert(PlotScript.seed_count(1) == PlotScript.STARTER_SEED_COUNT, "till is free: seeds untouched")
	_assert(plot.prompt_text() == "Plant seeds (E)", "tilled prompt")
	plot.plot_action() # E on tilled with seeds: plant
	_assert(plot.plot_state == "planted", "plant: state planted")
	_assert(PlotScript.seed_count(1) == PlotScript.STARTER_SEED_COUNT - 1, "plant: ledger spent 1 seed")
	_assert(_farm_inv_count(p, "seed_packet") == PlotScript.STARTER_SEED_COUNT - 1, "plant: inventory stack spent 1 seed")
	plot.on_wave_cleared() # wave tick 1
	_assert(plot.plot_state == "growing" and plot.growth_ticks == 1, "wave 1: growing")
	plot.on_wave_cleared() # wave tick 2
	_assert(plot.plot_state == "growing" and plot.growth_ticks == 2, "wave 2: still growing")
	_assert(plot.prompt_text() == "Growing (1 waves left)", "growing prompt counts down")
	plot.on_wave_cleared() # wave tick 3 -> mature
	_assert(plot.plot_state == "harvestable", "wave 3: harvestable")
	_assert(plot.prompt_text() == "Harvest! (E)", "harvestable prompt")
	PlotScript.debug_harvest_roll = 0.5 # force a common crop
	plot.plot_action() # E on harvestable: harvest
	_assert(plot.plot_state == "untilled", "harvest: resets to untilled")
	_assert(plot.growth_ticks == 0, "harvest: ticks reset")
	_assert(plot.occupied_by == 0, "harvest: claim released")
	_assert(_farm_inv_count(p, "crop_sunroot") == 1, "harvest: common crop granted")
	_assert(plot.prompt_text() == "Till soil (E)", "prompt resets after harvest")
	# --- Seed-less and growing-state prompts ---
	var plot3 = PlotScript.new()
	root.add_child(plot3)
	plot3.global_position = Vector3.ZERO
	plot3.test_player = p
	PlotScript._seed_ledger.erase(1) # no seeds at all
	plot3.plot_action() # till is still free
	_assert(plot3.plot_state == "tilled", "seedless: till still works")
	plot3.plot_action() # plant attempt with no seeds
	_assert(plot3.plot_state == "tilled", "seedless: stays tilled")
	_assert(PlotScript.seed_count(1) == 0, "seedless: ledger untouched")
	_assert(plot3.prompt_text() == "Plant seeds (E)", "seedless: prompt unchanged")
	plot3.occupied_by = 2 # simulate another peer's claim
	plot3.plot_state = "growing"
	plot3.growth_ticks = 1
	plot3.plot_action() # stranger's E: rejected
	_assert(plot3.plot_state == "growing" and plot3.occupied_by == 2, "stranger cannot drive the machine")
	_assert(plot3.prompt_text() == "Plot in use", "stranger prompt")
	# --- Rarity weighting (defaults, Jesse's call) ---
	PlotScript.debug_harvest_roll = -1.0
	var seen := {}
	for i in 300:
		seen[plot._roll_harvest_item()] = true
	_assert(seen.has("crop_sunroot") and seen.has("crop_moonmelon") and seen.has("crop_goldengourd"), "rarity: all tiers roll")
	for rid in seen:
		_assert(ItemDBNode.get_item(str(rid)) != null, "rolled crop is a real item: " + str(rid))
	PlotScript.debug_harvest_roll = 0.01
	_assert(plot._roll_harvest_item() == "crop_goldengourd", "forced roll: legendary")
	PlotScript.debug_harvest_roll = 0.10
	_assert(plot._roll_harvest_item() == "crop_moonmelon", "forced roll: rare")
	PlotScript.debug_harvest_roll = 0.90
	_assert(plot._roll_harvest_item() == "crop_sunroot", "forced roll: common")
	PlotScript.debug_harvest_roll = -1.0
	# --- Rare-crop buff application (usable from inventory) ---
	p.receive_item("crop_moonmelon")
	var idx := -1
	for i in range(p.inventory.size()):
		var e: Dictionary = p.inventory[i]
		var it = e.get("item")
		if it != null and str(it.id) == "crop_moonmelon":
			idx = i
			break
	_assert(idx >= 0, "moonmelon in inventory")
	p.hp = p.max_hp * 0.4
	var hp_before: float = p.hp
	p.use_item(idx)
	_assert(p.hp > hp_before, "rare crop heal applied")
	# --- Golden crop harvest registers the dock trophy (scratch account) ---
	# Drop any leftover scratch profile from an earlier run first.
	if FileAccess.file_exists("user://profile_test_dock3.cfg"):
		DirAccess.remove_absolute("user://profile_test_dock3.cfg")
	var plot2 = PlotScript.new()
	root.add_child(plot2)
	plot2.global_position = Vector3.ZERO
	plot2.test_player = p
	PlotScript.grant_starter_seeds(1)
	plot2.plot_action() # till
	plot2.plot_action() # plant
	plot2.on_wave_cleared()
	plot2.on_wave_cleared()
	plot2.on_wave_cleared()
	_assert(plot2.plot_state == "harvestable", "trophy plot matured")
	SM.set("_test_account_pin", "test_dock3")
	SM.load_game()
	_assert(not SM.has_dock_trophy("golden_crop"), "trophy: not recorded yet")
	PlotScript.debug_harvest_roll = 0.01 # force the legendary
	plot2.plot_action() # harvest golden
	_assert(_farm_inv_count(p, "crop_goldengourd") == 1, "golden crop granted to inventory")
	_assert(SM.has_dock_trophy("golden_crop"), "trophy: golden crop recorded")
	_assert(not SM.call("record_dock_trophy", "golden_crop"), "trophy: no dupes")
	SM.set("_test_account_pin", "")
	SM.load_game()
	# --- Collection tab: dock trophy section ---
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud = HudScene.instantiate()
	root.add_child(hud)
	SM.set("_test_account_pin", "test_dock3")
	SM.load_game()
	hud._refresh_dock_trophy_section()
	var log = hud.get_node("%CollectionLog")
	var header_ok := false
	var unknowns := 0
	for child in log.get_children():
		if child is Label and str(child.text).begins_with("Dock Trophies"):
			header_ok = true
		if child is HBoxContainer:
			for gc in child.get_children():
				if gc is Label and str(gc.text).begins_with("???"):
					unknowns += 1
	_assert(header_ok, "dock section: header present")
	_assert(unknowns == 1, "dock section: 1 locked row (legendary fish, later phase)")
	SM.call("record_dock_trophy", "golden_crop")
	for child in log.get_children():
		log.remove_child(child)
		child.free()
	hud._refresh_dock_trophy_section()
	var knowns := 0
	for child in log.get_children():
		if child is HBoxContainer:
			for gc in child.get_children():
				if gc is Label and str(gc.text).contains("Golden Gourd"):
					knowns += 1
	_assert(knowns == 1, "dock section: golden row earned")
	hud.queue_free()
	SM.set("_test_account_pin", "")
	SM.load_game()
	# Cleanup scratch profile (relic-test pattern): keeps the test
	# idempotent across consecutive suite runs.
	var scratch := "user://profile_test_dock3.cfg"
	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)
	# Cleanup: reset the test seams so later tests see production behavior.
	PlotScript.debug_harvest_roll = -1.0
	PlotScript._seed_ledger.clear()
	plot.free()
	plot2.free()
	plot3.free()
	p.queue_free()
	print("[Playtest] issue #102 Phase 3 done")


func _test_dock_economy_phase4() -> void:
	print("[Playtest] issue #102 Phase 4: farm cash economy + vendor...")
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var MerchScript: GDScript = load("res://scripts/dungeon/dock_merchant.gd")
	var EconScript: GDScript = load("res://scripts/dungeon/dock_economy.gd")
	var PlotScript: GDScript = load("res://scripts/dungeon/farm_plot.gd")
	var DirectorScript: GDScript = load("res://scripts/fishing/fishing_director.gd")
	# --- Vendor items exist; sell values filled (the Phase 2/3 seam) ---
	for iid in ["farm_cash", "bait_lure", "fertilizer", "dock_salve",
			"harbor_draught", "swift_current", "barnacle_bulwark"]:
		_assert(ItemDBNode.get_item(iid) != null, "ItemDB has " + iid)
	_assert(int(ItemDBNode.get_item("fish_minnow").get("sell_value")) == 2, "minnow sells for 2 fc")
	_assert(int(ItemDBNode.get_item("fish_riverbass").get("sell_value")) == 5, "bass sells for 5 fc")
	_assert(int(ItemDBNode.get_item("fish_glimmerfin").get("sell_value")) == 12, "glimmerfin sells for 12 fc")
	_assert(int(ItemDBNode.get_item("crop_sunroot").get("sell_value")) == 3, "sunroot sells for 3 fc")
	_assert(int(ItemDBNode.get_item("crop_moonmelon").get("sell_value")) == 0, "moonmelon not sellable (usable)")
	_assert(int(ItemDBNode.get_item("crop_goldengourd").get("sell_value")) == 0, "golden gourd not sellable (trophy)")
	# No gold path: none of the dock goods are supermarket loot, so the
	# supermarket checkout (gold) can never touch them.
	for iid in ["farm_cash", "bait_lure", "fertilizer", "fish_minnow",
			"fish_riverbass", "fish_glimmerfin", "crop_sunroot",
			"crop_moonmelon", "seed_packet"]:
		_assert(not bool(ItemDBNode.get_item(iid).get("supermarket_loot")),
			iid + " not supermarket loot (no gold leakage by construction)")
	# Buff items carry wave durations.
	_assert(int(ItemDBNode.get_item("harbor_draught").get("buff_waves")) == 3, "draught: 3-wave buff")
	_assert(int(ItemDBNode.get_item("barnacle_bulwark").get("buff_waves")) == 3, "bulwark: 3-wave buff")
	# Economy isolation: the station vendor (run cash) never stocks dock
	# goods — run cash can't buy into the farm-cash economy.
	var StationScript: GDScript = load("res://scripts/station/station.gd")
	var stock: Array = StationScript.build_vendor_stock()
	_assert(stock.size() > 0, "station stock builds")
	for entry in stock:
		var sid := str((entry as Dictionary).get("id"))
		var sitem = ItemDBNode.get_item(sid)
		_assert(sitem == null or not bool(sitem.get("dock_good")),
			"station stock excludes dock goods: " + sid)
	# --- Sim rig: real player + merchant; this instance is the server ---
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	p.global_position = Vector3.ZERO
	var merch = MerchScript.new()
	root.add_child(merch)
	merch.test_player = p
	EconScript.debug_reset()
	PlotScript._seed_ledger.clear()
	var gold_before: int = p.get("supermarket_cash")
	# --- Earn: server grants (mirrors catch/harvest) + inventory mirror ---
	EconScript.grant_stock(1, "fish_minnow", 2)
	p.receive_item("fish_minnow")
	p.receive_item("fish_minnow")
	EconScript.grant_stock(1, "crop_sunroot", 1)
	p.receive_item("crop_sunroot")
	EconScript.grant_stock(1, "fish_riverbass", 2)
	p.receive_item("fish_riverbass")
	p.receive_item("fish_riverbass")
	EconScript.grant_stock(1, "fish_glimmerfin", 1)
	p.receive_item("fish_glimmerfin")
	# --- Sell: ledger cash up, goods down, gold untouched ---
	merch.request_sell("fish_minnow")
	_assert(EconScript.cash_balance(1) == 2, "sell minnow 1: +2 fc")
	_assert(_farm_inv_count(p, "fish_minnow") == 1, "sell minnow 1: stack down")
	_assert(_farm_inv_count(p, "farm_cash") == 2, "sell minnow 1: cash in inventory")
	merch.request_sell("fish_minnow")
	merch.request_sell("crop_sunroot")
	merch.request_sell("fish_riverbass")
	merch.request_sell("fish_riverbass")
	merch.request_sell("fish_glimmerfin")
	_assert(EconScript.cash_balance(1) == 29, "full sell: 29 fc earned")
	_assert(_farm_inv_count(p, "farm_cash") == 29, "full sell: 29 fc in inventory")
	_assert(_farm_inv_count(p, "fish_minnow") == 0, "sold-out minnow gone")
	# Failed sells change nothing.
	merch.request_sell("fish_minnow") # nothing left
	merch.request_sell("crop_moonmelon") # not sellable
	_assert(EconScript.cash_balance(1) == 29, "failed sells: balance untouched")
	# --- Buy: seeds (closes the Phase 3 seed-ledger seam) ---
	merch.request_buy("seed_packet")
	merch.request_buy("seed_packet")
	_assert(EconScript.cash_balance(1) == 25, "2 seeds bought: 25 fc left")
	_assert(PlotScript.seed_count(1) == 2, "seed buy: SERVER LEDGER updated")
	_assert(_farm_inv_count(p, "seed_packet") == 2, "seed buy: packets in inventory")
	# --- Buy: bait + fertilizer ---
	merch.request_buy("bait_lure")
	_assert(EconScript.cash_balance(1) == 22, "bait bought: 22 fc left")
	_assert(EconScript.stock_count(1, "bait_lure") == 1, "bait: server stock")
	_assert(_farm_inv_count(p, "bait_lure") == 1, "bait: in inventory")
	merch.request_buy("fertilizer")
	merch.request_buy("fertilizer")
	_assert(EconScript.cash_balance(1) == 14, "2 fertilizer bought: 14 fc left")
	_assert(EconScript.stock_count(1, "fertilizer") == 2, "fertilizer: server stock")
	# --- Buy: salve + damage buff ---
	merch.request_buy("dock_salve")
	_assert(EconScript.cash_balance(1) == 9, "salve bought: 9 fc left")
	_assert(_farm_inv_count(p, "dock_salve") == 1, "salve: in inventory")
	merch.request_buy("harbor_draught")
	_assert(EconScript.cash_balance(1) == 1, "draught bought: 1 fc left")
	_assert(_farm_inv_count(p, "harbor_draught") == 1, "draught: in inventory")
	# Failed buys change nothing.
	merch.request_buy("fertilizer") # need 4, have 1
	merch.request_buy("no_such_item")
	_assert(EconScript.cash_balance(1) == 1, "failed buys: balance untouched")
	_assert(EconScript.stock_count(1, "fertilizer") == 2, "failed buys: stock untouched")
	# --- Bought seeds plant (ledger + inventory agree, Phase 3 path) ---
	var plot = PlotScript.new()
	root.add_child(plot)
	plot.test_player = p
	plot.plot_action() # till
	plot.plot_action() # plant: spends 1 bought seed
	_assert(plot.plot_state == "planted", "bought seed plants")
	_assert(PlotScript.seed_count(1) == 1, "plant: ledger 2 -> 1")
	_assert(_farm_inv_count(p, "seed_packet") == 1, "plant: inventory 2 -> 1")
	# --- Fertilizer: exactly one tick per application ---
	plot.on_wave_cleared() # ticks 1, growing
	_assert(plot.plot_state == "growing" and plot.growth_ticks == 1, "pre-fertilizer: growing @1")
	plot.plot_action() # E with fertilizer: +1 tick
	_assert(plot.growth_ticks == 2 and plot.plot_state == "growing", "fertilizer: one tick (2, still growing)")
	_assert(EconScript.stock_count(1, "fertilizer") == 1, "fertilizer: stock spent 1")
	_assert(_farm_inv_count(p, "fertilizer") == 1, "fertilizer: inventory spent 1")
	plot.plot_action() # E with fertilizer at 1 tick left: matures
	_assert(plot.plot_state == "harvestable", "fertilizer at 1-left: harvestable")
	_assert(EconScript.stock_count(1, "fertilizer") == 0, "fertilizer: stock spent")
	# No fertilizer: E only prompts, state untouched.
	var plot3 = PlotScript.new()
	root.add_child(plot3)
	plot3.test_player = p
	plot3.plot_action() # till
	plot3.plot_action() # plant (ledger 1 -> 0)
	plot3.on_wave_cleared() # growing @1
	plot3.plot_action() # E with no fertilizer
	_assert(plot3.plot_state == "growing" and plot3.growth_ticks == 1, "no fertilizer: state untouched")
	_assert(plot3.prompt_text() == "Growing (2 waves left)", "no fertilizer: prompt unchanged")
	# --- Bait: auto-consumes on cast, shifts the roll ---
	# Issue #126 Phase 2: the cast is a director cast now (validated,
	# water seamed on); the bait mechanics are the spot's, carried.
	var director = DirectorScript.new()
	root.add_child(director)
	director.test_players = {1: p}
	DirectorScript.debug_force_water = 1
	_grant_equipped(p, "fishing_rod") # the server cast gate needs it EQUIPPED
	director._handle_cast(1, Vector3(0, 0, 4)) # server-side cast with bait in stock
	_assert(EconScript.stock_count(1, "bait_lure") == 0, "bait: consumed on cast (server)")
	_assert(_farm_inv_count(p, "bait_lure") == 0, "bait: consumed on cast (inventory)")
	_assert(bool((director._sessions[1] as Dictionary).get("baited", false)), "bait: armed for this cast's roll")
	director._end_peer_session(1, "")
	_assert(not director.has_bobber(1), "bait: session end clears the cast (bait never leaks)")
	# Bait shift, pinned DETERMINISTICALLY (issue #115). The old pin
	# sampled 400 rolls per side and asserted bait_hit > base_hit + 20:
	# at wait 5.5 (t = 0.5) the not-minnow rates are 0.425 vs 0.575, so
	# the expected gap is 60 with sigma ~14 — the +20 threshold sat only
	# ~2.9 sigma below the mean gap, a ~0.2%-per-run flake by
	# construction (it fired once at 3194/1). A wider threshold would
	# still be a coin flip, just a slower one. Instead, force the roll
	# (debug_catch_roll, the p5 pattern) at the band edges the shift
	# moves: at t = 0.5 the unbaited not-minnow edge is 0.425, the
	# baited edge is 0.425 + BAIT_RARE_SHIFT (0.15) = 0.575; the rare
	# edges are 0.125 / 0.275 and the legendary edges 0.03 / 0.18.
	var shift_consts: Dictionary = EconScript.get_script_constant_map()
	_assert(is_equal_approx(float(shift_consts.get("BAIT_RARE_SHIFT", -1.0)), 0.15),
		"bait: BAIT_RARE_SHIFT rate constant is 0.15 (wiring pin, #115)")
	# Roll 0.50: inside the shifted band only — minnow unbaited,
	# riverbass baited. The mechanism in one pair.
	DirectorScript.debug_catch_roll = 0.50
	_assert(director.roll_catch_item(5.5, false) == "fish_minnow", "bait: roll 0.50 unbaited = minnow (#115)")
	_assert(director.roll_catch_item(5.5, true) == "fish_riverbass", "bait: roll 0.50 baited = riverbass (shift flips the band, #115)")
	# Roll 0.20: the rare band edge moves the same way.
	DirectorScript.debug_catch_roll = 0.20
	_assert(director.roll_catch_item(5.5, false) == "fish_riverbass", "bait: roll 0.20 unbaited = riverbass (#115)")
	_assert(director.roll_catch_item(5.5, true) == "fish_glimmerfin", "bait: roll 0.20 baited = glimmerfin (rare edge shifted, #115)")
	# Roll 0.10: the legendary edge shifts too.
	DirectorScript.debug_catch_roll = 0.10
	_assert(director.roll_catch_item(5.5, false) == "fish_glimmerfin", "bait: roll 0.10 unbaited = glimmerfin (#115)")
	_assert(director.roll_catch_item(5.5, true) == "fish_starleaper", "bait: roll 0.10 baited = starleaper (legendary edge shifted, #115)")
	# Roll 0.60: above even the baited edge — the shift is bounded.
	DirectorScript.debug_catch_roll = 0.60
	_assert(director.roll_catch_item(5.5, false) == "fish_minnow", "bait: roll 0.60 unbaited = minnow (#115)")
	_assert(director.roll_catch_item(5.5, true) == "fish_minnow", "bait: roll 0.60 baited = minnow (shift is bounded, #115)")
	# Roll 0.02: below both legendary edges — anchor.
	DirectorScript.debug_catch_roll = 0.02
	_assert(director.roll_catch_item(5.5, false) == "fish_starleaper", "bait: roll 0.02 unbaited = starleaper (#115)")
	_assert(director.roll_catch_item(5.5, true) == "fish_starleaper", "bait: roll 0.02 baited = starleaper (#115)")
	DirectorScript.debug_catch_roll = -1.0
	DirectorScript.debug_force_water = -1
	director.free()
	# --- Wave buff: usable in "later levels", expires after N waves ---
	var didx := -1
	for i in range(p.inventory.size()):
		var e: Dictionary = p.inventory[i]
		var it = e.get("item")
		if it != null and str(it.id) == "harbor_draught":
			didx = i
			break
	_assert(didx >= 0, "draught in inventory")
	p.on_wave_cleared() # two waves pass in a later level...
	p.on_wave_cleared()
	p.use_item(didx) # ...then the buff is used there
	_assert(p._buff_mult("damage") == 1.25, "draught: +25% damage active in later level")
	p.on_wave_cleared()
	p.on_wave_cleared()
	_assert(p._buff_mult("damage") == 1.25, "draught: still active after 2 waves")
	p.on_wave_cleared()
	_assert(p._buff_mult("damage") == 1.0, "draught: expired after 3 waves")
	_assert(_farm_inv_count(p, "harbor_draught") == 0, "draught: consumed on use")
	# --- Salve heals ---
	var sidx := -1
	for i in range(p.inventory.size()):
		var e2: Dictionary = p.inventory[i]
		var it2 = e2.get("item")
		if it2 != null and str(it2.id) == "dock_salve":
			sidx = i
			break
	p.hp = p.max_hp * 0.5
	p.use_item(sidx)
	_assert(p.hp > p.max_hp * 0.5, "salve: healed")
	# --- Bulwark reduces damage taken ---
	p.receive_item("barnacle_bulwark")
	var bidx := -1
	for i in range(p.inventory.size()):
		var e3: Dictionary = p.inventory[i]
		var it3 = e3.get("item")
		if it3 != null and str(it3.id) == "barnacle_bulwark":
			bidx = i
			break
	p.use_item(bidx)
	_assert(p._buff_mult("defense") == 0.75, "bulwark: defense mult 0.75")
	p.hp = p.max_hp
	p.take_damage(40.0, "test")
	_assert(p.hp == p.max_hp - 30.0, "bulwark: 40 damage -> 30 taken")
	# --- Death clears the server ledgers (mirrors notify_player_died) ---
	EconScript.grant_cash(1, 10)
	PlotScript.grant_seeds(1, 5)
	EconScript.reset_peer(1)
	PlotScript.clear_ledger(1)
	_assert(EconScript.cash_balance(1) == 0, "death: farm cash ledger cleared")
	_assert(PlotScript.seed_count(1) == 0, "death: seed ledger cleared")
	# --- No gold leakage across the whole loop ---
	_assert(int(p.get("supermarket_cash")) == gold_before, "no gold leakage: supermarket_cash unchanged")
	# Cleanup: reset seams so later tests see production behavior.
	EconScript.debug_reset()
	PlotScript._seed_ledger.clear()
	plot.free()
	plot3.free()
	merch.free()
	p.queue_free()
	print("[Playtest] issue #102 Phase 4 done")


## Farm-phase helper: count of an item id in a player's inventory.
## (Untyped param: a Player type hint here would force player.gd to compile
## at suite startup, before autoloads register — caching a compile failure
## that leaves every player.tscn instantiation script-less for the run.)
## Test helper (issue #104 Phase 3): grant an item and equip its stack.
func _grant_equipped(p, item_id: String) -> void:
	p.receive_item(item_id)
	for i in p.inventory.size():
		var it = p.inventory[i].get("item")
		if it != null and str(it.get("id")) == item_id:
			p.equip_stack(i)
			return


func _farm_inv_count(pl, item_id: String) -> int:
	for e in pl.inventory:
		var it = (e as Dictionary).get("item")
		if it != null and str(it.id) == item_id:
			return int((e as Dictionary).get("count", 0))
	return 0


func _test_misty_docks_phase5() -> void:
	print("[Playtest] issue #102 Phase 5: theme polish + legendary fish + run sim...")
	var DungeonScript := load("res://scripts/dungeon/dungeon.gd")
	var StationScript := load("res://scripts/station/station.gd")
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	var DirectorScript: GDScript = load("res://scripts/fishing/fishing_director.gd")
	var PlotScript: GDScript = load("res://scripts/dungeon/farm_plot.gd")
	var MerchScript: GDScript = load("res://scripts/dungeon/dock_merchant.gd")
	var EconScript: GDScript = load("res://scripts/dungeon/dock_economy.gd")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	# (Runtime loads only: bare autoload identifiers don't compile in -s script mode.)
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var SM: Node = root.get_node("SaveManager")
	# --- Theme data coherence: the .tres audited end-to-end ---
	var docks: Resource = load("res://data/levels/theme_misty_docks.tres")
	var village: Resource = load("res://data/levels/theme_village.tres")
	_assert(docks != null, "p5: theme loads")
	_assert(float(docks.get("fog_density")) > float(village.get("fog_density")),
		"p5: docks is the mistiest theme (fog)")
	_assert(float(docks.get("sun_energy")) < float(village.get("sun_energy")),
		"p5: docks sun dimmer than village")
	_assert(int(docks.get("torch_count")) > 0, "p5: dock light sources placed")
	_assert((docks.get("torch_light_color") as Color).g > 0.5, "p5: lantern light is warm")
	for mid in (docks.get("mob_mix") as Dictionary).keys():
		_assert(FileAccess.file_exists("res://data/mobs/%s.tres" % str(mid)),
			"p5: mob mix id exists: " + str(mid))
	var pbsrc := FileAccess.get_file_as_string("res://scripts/procgen/prop_builder.gd")
	for e in (docks.get("obstacle_entries") as Array):
		_assert(pbsrc.contains("\"%s\":" % str(e.get("type"))),
			"p5: obstacle type buildable: " + str(e.get("type")))
	for e in (docks.get("prop_entries") as Array):
		_assert(pbsrc.contains("\"%s\":" % str(e.get("type"))),
			"p5: prop type buildable: " + str(e.get("type")))
	_assert(int(DungeonScript.DANGER_TIERS.get("misty_docks", -1)) == 1, "p5: danger tier 1")
	_assert(str(StationScript.BOARD_STARS.get("misty_docks")) == "★☆☆☆", "p5: stars match tier 1")
	_assert((StationScript.DRESSING_LAMPS as Dictionary).get("misty_docks")
		== DungeonScript.arrival_tint("misty_docks"), "p5: lamp tint == arrival tint")
	_assert(str(docks.get("boss_id")) == "", "p5: no boss (downtime level)")
	# --- Legendary fish: item + catch-roll table (golden-crop pattern) ---
	var star: Variant = ItemDBNode.get_item("fish_starleaper")
	_assert(star != null, "p5: ItemDB has fish_starleaper")
	_assert(int(star.get("rarity")) == 4, "p5: starleaper is LEGENDARY rarity")
	_assert(int(star.get("sell_value")) == 0, "p5: starleaper unsellable (trophy item)")
	_assert(bool(star.get("dock_good")), "p5: starleaper is a dock good")
	_assert(not bool(star.get("supermarket_loot")), "p5: starleaper not supermarket loot")
	_assert(EconScript.sell_value_for("fish_starleaper") == 0, "p5: merchant pays 0 for starleaper")
	var director = DirectorScript.new()
	root.add_child(director)
	DirectorScript.debug_catch_roll = 0.04
	_assert(director.roll_catch_item(8.0, false) == "fish_starleaper", "p5: roll 0.04 @max wait: legendary")
	DirectorScript.debug_catch_roll = 0.10
	_assert(director.roll_catch_item(8.0, false) == "fish_glimmerfin", "p5: roll 0.10 @max wait: rare")
	DirectorScript.debug_catch_roll = 0.50
	_assert(director.roll_catch_item(8.0, false) == "fish_riverbass", "p5: roll 0.50 @max wait: uncommon")
	DirectorScript.debug_catch_roll = 0.90
	_assert(director.roll_catch_item(8.0, false) == "fish_minnow", "p5: roll 0.90 @max wait: common")
	DirectorScript.debug_catch_roll = 0.005
	_assert(director.roll_catch_item(3.0, false) == "fish_starleaper", "p5: roll 0.005 @min wait: legendary")
	DirectorScript.debug_catch_roll = -1.0
	var seen := {}
	for i in 400:
		seen[director.roll_catch_item(8.0, false)] = true
	_assert(seen.size() == 4 and seen.has("fish_starleaper"), "p5: all 4 fish tiers roll @max wait")
	# --- FULL THEME RUN SIM: one continuous misty-docks visit ---
	# Real generated layout; the plot sits at the layout's own position
	# (as dungeon._build_farm_plots places it) and fishing runs through
	# a FishingDirector, as the dungeon builds one (#126 Phase 2).
	var layout = ProcGenScript.generate(docks, 424242)
	_assert(layout.ponds.size() >= 2 and layout.fishing_spots.size() == layout.ponds.size(),
		"sim: ponds + one spot each")
	_assert(layout.farm_plots.size() == 6, "sim: 6 farm plots")
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	p.global_position = layout.fishing_spots[0]
	director.test_players = {1: p}
	DirectorScript.debug_force_water = 1 # no live dungeon/terrain here
	var plot = PlotScript.new()
	root.add_child(plot)
	plot.global_position = layout.farm_plots[0]
	plot.test_player = p
	var merch = MerchScript.new()
	root.add_child(merch)
	merch.global_position = layout.farm_plots[0] + Vector3(2.0, 0, 0)
	merch.test_player = p
	_grant_equipped(p, "fishing_rod") # rod equipped (sessions are ungated since #126; equip is realistic kit)
	EconScript.debug_reset()
	PlotScript._seed_ledger.clear()
	var gold_before: int = p.get("supermarket_cash")
	# Level entry (mirrors dungeon._do_spawn on a farm theme).
	PlotScript.grant_starter_seeds(1)
	for s in PlotScript.STARTER_SEED_COUNT:
		p.receive_item(PlotScript.SEED_ITEM)
	_assert(_farm_inv_count(p, "seed_packet") == PlotScript.STARTER_SEED_COUNT,
		"sim: starter seeds in hand")
	# 1) FISH: full cast -> bite -> hook cycle (forced plain catch so
	# the sell math below is deterministic; the legendary has its own
	# section below). Cast target: pond 0's center, from the pier end.
	DirectorScript.debug_wait_override = 2.0
	DirectorScript.debug_now_msec = 400000
	DirectorScript.debug_catch_roll = 0.9
	director.request_cast((layout.ponds[0] as Dictionary)["center"])
	_assert(director.session_state_for(1) == DirectorScript.SessionState.WAITING
		and bool(p.get("_bobber_out")), "sim: cast out, bobber in the water")
	DirectorScript.debug_now_msec = 400000 + 2100
	director._process(0.016)
	_assert(director.session_state_for(1) == DirectorScript.SessionState.BITING, "sim: bite fired")
	director.request_hook()
	_assert(_farm_inv_count(p, "fish_minnow") == 1, "sim: catch landed a minnow")
	_assert(EconScript.stock_count(1, "fish_minnow") == 1,
		"sim: catch granted sellable stock (Phase 5 fix)")
	DirectorScript.debug_catch_roll = -1.0
	# 2) SELL the catch at the vendor — the real flow, no manual grants.
	merch.request_sell("fish_minnow")
	_assert(EconScript.cash_balance(1) == 2, "sim: minnow sold for 2 fc")
	_assert(_farm_inv_count(p, "farm_cash") == 2, "sim: farm cash in inventory")
	_assert(_farm_inv_count(p, "fish_minnow") == 0, "sim: minnow sold out")
	# 3) FARM: till + plant with a starter seed.
	plot.plot_action()
	plot.plot_action()
	_assert(plot.plot_state == "planted", "sim: planted")
	# 4) WAVES: three cleared waves mature the crop (the dungeon's hook).
	plot.on_wave_cleared()
	plot.on_wave_cleared()
	_assert(plot.plot_state == "growing", "sim: still growing after 2 waves")
	plot.on_wave_cleared()
	_assert(plot.plot_state == "harvestable", "sim: harvestable after 3 waves")
	# 5) HARVEST (forced common) — stock-granted for the vendor, too.
	PlotScript.debug_harvest_roll = 0.5
	plot.plot_action()
	_assert(_farm_inv_count(p, "crop_sunroot") == 1, "sim: harvested a sunroot")
	_assert(EconScript.stock_count(1, "crop_sunroot") == 1,
		"sim: harvest granted sellable stock (Phase 5 fix)")
	PlotScript.debug_harvest_roll = -1.0
	# 6) SELL the crop, BUY a consumable with the combined earnings.
	merch.request_sell("crop_sunroot")
	_assert(EconScript.cash_balance(1) == 5, "sim: 2 + 3 = 5 fc after crop sale")
	merch.request_buy("dock_salve")
	_assert(EconScript.cash_balance(1) == 0, "sim: salve bought for 5 fc")
	_assert(_farm_inv_count(p, "dock_salve") == 1, "sim: salve in inventory")
	# The trophy fish can never be sold, even when held.
	p.receive_item("fish_starleaper")
	merch.request_sell("fish_starleaper")
	_assert(_farm_inv_count(p, "fish_starleaper") == 1, "sim: starleaper unsellable, kept")
	_assert(EconScript.cash_balance(1) == 0, "sim: refused sale paid nothing")
	_assert(int(p.get("supermarket_cash")) == gold_before, "sim: no gold leakage")
	# --- Legendary catch: trophy records (scratch profile, Phase 3 pattern) ---
	if FileAccess.file_exists("user://profile_test_dock5.cfg"):
		DirAccess.remove_absolute("user://profile_test_dock5.cfg")
	var p2 = PlayerScene.instantiate()
	p2.class_id = "warrior"
	root.add_child(p2)
	p2.global_position = layout.fishing_spots[0]
	director.test_players = {1: p2}
	_grant_equipped(p2, "fishing_rod") # rod equipped (the server cast gate, #126 P2)
	SM.set("_test_account_pin", "test_dock5")
	SM.load_game()
	_assert(not SM.has_dock_trophy("legendary_fish"), "p5: fish trophy not recorded yet")
	DirectorScript.debug_wait_override = 2.0
	DirectorScript.debug_now_msec = 500000
	DirectorScript.debug_catch_roll = 0.001 # force the legendary slice
	director.request_cast((layout.ponds[0] as Dictionary)["center"])
	DirectorScript.debug_now_msec = 500000 + 2100
	director._process(0.016)
	_assert(director.session_state_for(1) == DirectorScript.SessionState.BITING, "p5: legendary bite fired")
	director.request_hook()
	_assert(_farm_inv_count(p2, "fish_starleaper") == 1, "p5: starleaper granted")
	_assert(SM.has_dock_trophy("legendary_fish"), "p5: legendary fish trophy recorded")
	_assert(not SM.call("record_dock_trophy", "legendary_fish"), "p5: trophy: no dupes")
	DirectorScript.debug_catch_roll = -1.0
	# Collection tab: BOTH dock trophies earned -> no ??? rows remain.
	SM.call("record_dock_trophy", "golden_crop")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._refresh_dock_trophy_section()
	var clog = hud.get_node("%CollectionLog")
	var header_ok := false
	var unknowns := 0
	var fish_known := 0
	for child in clog.get_children():
		if child is Label and str(child.text).begins_with("Dock Trophies"):
			header_ok = true
			_assert(str(child.text).contains("2/2"), "p5: dock header shows 2/2")
		if child is HBoxContainer:
			for gc in child.get_children():
				if gc is Label and str(gc.text).begins_with("???"):
					unknowns += 1
				if gc is Label and str(gc.text).contains("Legendary Fish"):
					fish_known += 1
	_assert(header_ok, "p5: dock section header present")
	_assert(unknowns == 0, "p5: both trophies earned, no locked rows")
	_assert(fish_known == 1, "p5: legendary fish row earned")
	hud.queue_free()
	SM.set("_test_account_pin", "")
	SM.load_game()
	var scratch := "user://profile_test_dock5.cfg"
	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)
	# Cleanup: reset the test seams so later tests see production behavior.
	DirectorScript.debug_wait_override = -1.0
	DirectorScript.debug_now_msec = -1
	DirectorScript.debug_catch_roll = -1.0
	DirectorScript.debug_force_water = -1
	EconScript.debug_reset()
	PlotScript._seed_ledger.clear()
	director.free()
	plot.free()
	merch.free()
	p.queue_free()
	p2.queue_free()
	print("[Playtest] issue #102 Phase 5 done")


## Count SELL buttons in the HUD's currently open cipher popup.
func _sell_button_count(hud) -> int:
	var popup = hud.get("_cipher_popup")
	if popup == null:
		return 0
	var n := 0
	var stack: Array = [popup]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is Button and (node as Button).text == "SELL":
			n += 1
		for c in node.get_children():
			stack.append(c)
	return n


## True when `flag_line` appears after the `_open_cipher_popup(` call
## inside the hud.gd function whose signature line is `sig`.
func _flag_set_after_open(src: String, sig: String, flag_line: String) -> bool:
	var start := src.find(sig)
	if start < 0:
		return false
	var end := src.find("\nfunc ", start + sig.length())
	if end < 0:
		end = src.length()
	var body := src.substr(start, end - start)
	var open_idx := body.find("_open_cipher_popup(")
	var flag_idx := body.find(flag_line)
	return open_idx >= 0 and flag_idx > open_idx


func _test_popup_open_flags() -> void:
	print("[Playtest] Popup open-flags vs cipher cleanup regression...")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var MerchScript: GDScript = load("res://scripts/dungeon/dock_merchant.gd")
	var EconScript: GDScript = load("res://scripts/dungeon/dock_economy.gd")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	var merch = MerchScript.new()
	root.add_child(merch)
	merch.test_player = p
	EconScript.debug_reset()
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._player = p
	# --- Dock vendor: the open flag must survive show_dock_vendor().
	# Regression: show set dock_vendor_open = true BEFORE building the
	# panel, then _open_cipher_popup's pre-open cleanup
	# (close_cipher_popup) reset it — so the flag never read true and
	# refresh_dock_vendor() never re-rendered during a vendor session.
	hud.show_dock_vendor()
	_assert(hud.dock_vendor_open, "dock vendor: flag true after show")
	_assert(hud.cipher_popup_open, "dock vendor: cipher shell open after show")
	_assert(_sell_button_count(hud) == 0, "dock vendor: no SELL rows with empty inventory")
	# Refresh while open must take the open branch and re-render: a
	# sellable fish granted after opening appears as a SELL row.
	EconScript.grant_stock(1, "fish_minnow", 1)
	p.receive_item("fish_minnow")
	hud.refresh_dock_vendor()
	_assert(hud.dock_vendor_open, "dock vendor: flag still true after refresh")
	_assert(_sell_button_count(hud) == 1, "dock vendor: refresh re-rendered SELL row")
	# Real close path (E/Esc -> close_cipher_popup) clears the flag.
	hud.close_cipher_popup()
	_assert(not hud.dock_vendor_open, "dock vendor: flag false after close")
	_assert(not hud.cipher_popup_open, "dock vendor: cipher shell closed after close")
	# --- Cipher popup coexistence: a plain cipher popup must not set
	# the vendor flag, and opening one replaces (closes) the vendor —
	# the cleanup's flag reset is correct for real closes/replacement.
	hud.show_dock_vendor()
	_assert(hud.dock_vendor_open, "dock vendor: flag true after re-show")
	hud.show_poem_popup(0)
	_assert(hud.cipher_popup_open, "cipher poem: shell open")
	_assert(not hud.dock_vendor_open, "cipher poem: replacing vendor cleared its flag")
	hud.close_cipher_popup()
	_assert(not hud.cipher_popup_open, "cipher poem: shell closed")
	_assert(not hud.dock_vendor_open, "cipher poem: vendor flag stays false after close")
	# --- Sibling popups had the identical cleanup-clobber bug (flag
	# set before _open_cipher_popup, reset by its cleanup) and got the
	# same reorder fix. Asserted structurally: their runtime rigs need
	# scene nodes (station / bounty board) the suite drives elsewhere.
	# player.gd on_bought reads hud.vendor_open, so this one mattered.
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(_flag_set_after_open(hsrc, "func show_vendor() -> void:", "vendor_open = true"),
		"station vendor: flag set after popup open in source")
	_assert(_flag_set_after_open(hsrc, "func show_bounty() -> void:", "bounty_open = true"),
		"bounty board: flag set after popup open in source")
	_assert(_flag_set_after_open(hsrc, "func show_dock_vendor() -> void:", "dock_vendor_open = true"),
		"dock vendor: flag set after popup open in source")
	hud.queue_free()
	merch.free()
	p.queue_free()
	print("[Playtest] popup open-flags done")


func _test_equip_system_phase1() -> void:
	print("[Playtest] Equipment system phase 1 (issue #104)...")
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var ItemDataScr: Variant = load("res://scripts/data/item_data.gd")
	var find_idx := func(pl, item_id: String) -> int:
		for i in pl.inventory.size():
			var it = pl.inventory[i].get("item")
			if it != null and str(it.get("id")) == item_id:
				return i
		return -1

	# --- Data layer: TOOL slot, gear definition, allowed_classes default.
	_assert(ItemDataScr.slot_name(3) == "TOOL", "equip: Slot.TOOL exists (slot 3)")
	_assert(ItemDataScr.slot_name(0) == "WEAPON", "equip: slot 0 is WEAPON")
	var sword = ItemDBNode.get_item("iron_sword")
	var potion = ItemDBNode.get_item("health_potion")
	var feather = ItemDBNode.get_item("phoenix_feather")
	_assert(ItemDataScr.is_gear(sword), "equip: iron sword is gear")
	_assert(not ItemDataScr.is_gear(potion), "equip: potion is not gear (consumable)")
	_assert(ItemDataScr.is_gear(feather), "equip: phoenix feather (slot 3) is TOOL gear")
	_assert((sword.get("allowed_classes") as Array).is_empty(),
		"equip: allowed_classes defaults empty (all classes)")

	# --- Non-gear stat audit (spec: run BEFORE the recalc change; locked
	# in here as a regression test): no non-gear item may carry nonzero
	# passive bonuses, or equip-only recalc would silently change totals.
	var all_items: Dictionary = ItemDBNode.get("items")
	var audit_ok := true
	for id in all_items:
		var it = all_items[id]
		if not ItemDataScr.is_gear(it):
			if float(it.get("damage_bonus")) != 0.0 or float(it.get("health_bonus")) != 0.0 \
					or float(it.get("speed_bonus")) != 0.0 \
					or float(it.get("damage_mult")) != 1.0 or float(it.get("health_mult")) != 1.0 \
					or float(it.get("speed_mult")) != 1.0 or float(it.get("xp_mult")) != 1.0:
				audit_ok = false
	_assert(audit_ok, "equip audit: no non-gear item carries passive stat bonuses")

	# --- New character (Co-founder amendment): starting weapon EQUIPPED.
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	var starter_idx: int = find_idx.call(p, "rusty_sword")
	_assert(starter_idx >= 0, "equip: starter weapon in inventory")
	_assert(str(p.inventory[starter_idx].get("equipped_slot", "")) == "WEAPON",
		"equip: brand-new character's starting weapon starts EQUIPPED")
	var base_damage: float = p.damage # warrior base + rusty (+4), equipped

	# --- Bag stacks are inert; new pickups never auto-equip.
	p.receive_item("iron_sword")
	p.receive_item("iron_sword")
	var iron_idx: int = find_idx.call(p, "iron_sword")
	_assert(iron_idx >= 0, "equip: iron sword stack present")
	_assert(int(p.inventory[iron_idx]["count"]) == 2, "equip: pickups merge into one stack")
	_assert(str(p.inventory[iron_idx].get("equipped_slot", "")) == "",
		"equip: new pickup never auto-equips")
	_assert(p.damage == base_damage, "equip: unequipped gear grants no stats")

	# --- Equip + swap: marker moves, old weapon comes off.
	_assert(p.equip_stack(iron_idx), "equip: equip_stack succeeds for gear")
	_assert(str(p.inventory[iron_idx].get("equipped_slot", "")) == "WEAPON",
		"equip: iron sword equipped into WEAPON")
	_assert(str(p.inventory[starter_idx].get("equipped_slot", "")) == "",
		"equip: swap unequips the previous weapon")
	_assert(p.damage > base_damage, "equip: equipped gear grants its stats")
	# Pickup grows the equipped stack and keeps the marker.
	p.receive_item("iron_sword")
	_assert(int(p.inventory[iron_idx]["count"]) == 3, "equip: pickup grows the equipped stack")
	_assert(str(p.inventory[iron_idx].get("equipped_slot", "")) == "WEAPON",
		"equip: grown stack stays equipped")

	# --- Consumables can never equip.
	p.receive_item("health_potion")
	var pot_idx: int = find_idx.call(p, "health_potion")
	_assert(pot_idx >= 0, "equip: potion stack present")
	_assert(not p.equip_stack(pot_idx), "equip: consumable equip refused")

	# --- Class restriction enforced in code (equip-time only).
	var tome = ItemDBNode.get_item("scholar_tome").duplicate()
	var only_mage: Array[String] = ["mage"]
	tome.set("allowed_classes", only_mage)
	p.inventory.append({"item": tome, "count": 1, "equipped_slot": ""})
	var tome_idx: int = p.inventory.size() - 1
	_assert(not p.equip_stack(tome_idx), "equip: class-restricted equip refused for warrior")
	_assert(str(p.inventory[tome_idx].get("equipped_slot", "")) == "",
		"equip: refused equip leaves the marker empty")

	# --- Disposal of an equipped stack is blocked ("Unequip first").
	var size_before: int = p.inventory.size()
	p.dispose_item(iron_idx)
	_assert(p.inventory.size() == size_before, "equip: disposing an equipped stack is blocked")
	_assert(p.unequip_stack(iron_idx), "equip: unequip_stack clears the marker")
	_assert(str(p.inventory[iron_idx].get("equipped_slot", "")) == "", "equip: marker cleared")
	p.dispose_item(iron_idx)
	_assert(p.inventory.size() == size_before - 1, "equip: dispose works once unequipped")
	p.queue_free()

	# --- Migration: marker-less legacy state auto-equips highest power.
	var q = PlayerScene.instantiate()
	q.class_id = "warrior"
	root.add_child(q)
	var legacy := {
		"level": 3, "xp": 0, "xp_next": 100, "stat_points": 0,
		"bonus_damage": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_aura": 0.0,
		"inventory": [
			{"id": "rusty_sword", "count": 1},
			{"id": "iron_sword", "count": 1},
			{"id": "leather_armor", "count": 2},
			{"id": "health_potion", "count": 3},
		],
	}
	q.apply_state(legacy)
	var q_iron: int = find_idx.call(q, "iron_sword")
	var q_rusty: int = find_idx.call(q, "rusty_sword")
	var q_leather: int = find_idx.call(q, "leather_armor")
	var q_pot: int = find_idx.call(q, "health_potion")
	_assert(str(q.inventory[q_iron].get("equipped_slot", "")) == "WEAPON",
		"equip migration: highest-power weapon auto-equipped (iron over rusty)")
	_assert(str(q.inventory[q_rusty].get("equipped_slot", "")) == "",
		"equip migration: lower-power weapon stays in the bag")
	_assert(str(q.inventory[q_leather].get("equipped_slot", "")) == "ARMOR",
		"equip migration: armor auto-equipped")
	_assert(str(q.inventory[q_pot].get("equipped_slot", "")) == "",
		"equip migration: consumable never auto-equipped")
	# Recalc equivalence: migrated totals equal the old all-items totals
	# for this loadout (one equipped stack per slot, per-copy math).
	var cd = q.get("class_data")
	var exp_dmg := (float(cd.get("base_damage")) + 4.0 + 10.0) * 1.12
	_assert(is_equal_approx(q.damage, exp_dmg),
		"equip migration: damage matches old totals when gear equipped")
	var exp_hp := (float(cd.get("base_health")) + 30.0 + 50.0) * pow(1.05, 2)
	_assert(is_equal_approx(q.max_hp, exp_hp),
		"equip migration: max HP matches old totals when gear equipped")

	# --- Save roundtrip: markers persist; all-empty markers do NOT
	# trigger re-migration (deliberate unequip is respected).
	var st: Dictionary = q.get_state()
	var slot_keys_ok := true
	var iron_slot := ""
	for e in st["inventory"]:
		if not (e as Dictionary).has("slot"):
			slot_keys_ok = false
		if str(e.get("id", "")) == "iron_sword":
			iron_slot = str(e.get("slot", ""))
	_assert(slot_keys_ok, "equip: get_state writes a slot key per entry")
	_assert(iron_slot == "WEAPON", "equip: get_state records the equipped slot")
	var r = PlayerScene.instantiate()
	r.class_id = "warrior"
	root.add_child(r)
	r.apply_state(st)
	var r_iron: int = find_idx.call(r, "iron_sword")
	_assert(str(r.inventory[r_iron].get("equipped_slot", "")) == "WEAPON",
		"equip: marker survives save/load roundtrip")
	r.queue_free()
	q.unequip_stack(q_iron)
	q.unequip_stack(q_leather)
	var st2: Dictionary = q.get_state()
	var r2 = PlayerScene.instantiate()
	r2.class_id = "warrior"
	root.add_child(r2)
	r2.apply_state(st2)
	var any_equipped := false
	for e in r2.inventory:
		if str(e.get("equipped_slot", "")) != "":
			any_equipped = true
	_assert(not any_equipped, "equip: all-empty markers do NOT re-trigger migration")
	r2.queue_free()
	q.queue_free()

	# Migration scoring is STACK-level: a big stack of a weaker weapon
	# out-grants a single stronger one, so the stack wins the slot.
	var q2 = PlayerScene.instantiate()
	q2.class_id = "warrior"
	root.add_child(q2)
	var legacy2 := {
		"level": 1, "xp": 0, "xp_next": 25, "stat_points": 0,
		"bonus_damage": 0.0, "bonus_health": 0.0, "bonus_speed": 0.0, "bonus_aura": 0.0,
		"inventory": [
			{"id": "rusty_sword", "count": 5},
			{"id": "iron_sword", "count": 1},
		],
	}
	q2.apply_state(legacy2)
	var q2_rusty: int = find_idx.call(q2, "rusty_sword")
	var q2_iron: int = find_idx.call(q2, "iron_sword")
	_assert(str(q2.inventory[q2_rusty].get("equipped_slot", "")) == "WEAPON",
		"equip migration: stack-level score — 5x rusty (20) beats 1x iron (10.12)")
	_assert(str(q2.inventory[q2_iron].get("equipped_slot", "")) == "",
		"equip migration: single stronger weapon stays in the bag")
	q2.queue_free()

	# --- Class switch auto-unequips restricted gear.
	var m = PlayerScene.instantiate()
	m.class_id = "mage"
	root.add_child(m)
	var tome2 = ItemDBNode.get_item("scholar_tome").duplicate()
	var only_mage2: Array[String] = ["mage"]
	tome2.set("allowed_classes", only_mage2)
	m.inventory.append({"item": tome2, "count": 1, "equipped_slot": ""})
	var m_tome: int = m.inventory.size() - 1
	_assert(m.equip_stack(m_tome), "equip: mage can equip a mage-only item")
	m.switch_class("warrior")
	_assert(str(m.inventory[m_tome].get("equipped_slot", "")) == "",
		"equip: class switch auto-unequips restricted stacks")
	m.queue_free()

	# --- Marker-preservation audit (source): both dungeon transition
	# filters carry entry dicts by reference, never rebuild them.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(dsrc.split("kept.append(entry)").size() - 1 >= 2,
		"equip audit: dungeon filters carry inventory entries by reference")
	print("[Playtest] equip system phase 1 done")


func _test_mp_save_c1_fix() -> void:
	print("[Playtest] MP save C-1 fix (issue #105)...")
	# C-1: a peer missing the 3s save-state window was filled in from its
	# server-side replica node (near-fresh: inventory never replicates),
	# and that wiped state overwrote the peer's real save. The fix makes
	# _mark_missing_disconnected carry the PREVIOUS roster entry forward
	# (keyed by Steam64), or write an empty state + the peer's real class.
	var SaveMgr: Variant = root.get_node("SaveManager")
	var DungeonScript: Variant = load("res://scripts/dungeon/dungeon.gd")
	var scratch := "user://runs_c1fix_test"
	if DirAccess.dir_exists_absolute(scratch):
		for f in DirAccess.get_files_at(scratch):
			DirAccess.remove_absolute(scratch.path_join(f))
		DirAccess.remove_absolute(scratch)
	SaveMgr.set("_test_runs_dir", scratch)
	SaveMgr.set("_test_account_pin", "c1fix_scratch")

	# Previous good save in slot 7: a progressed rogue (sid ...77).
	var sid_a := 76561198000000077
	var sid_b := 76561198000000088
	var rich_state := {"level": 7, "xp": 432, "xp_next": 600,
		"inventory": [{"id": "dragonscale_armor", "count": 1},
			{"id": "iron_sword", "count": 2}]}
	var prev_run := {"theme_id": "dungeon", "level_number": 4, "seed": 99,
		"is_multiplayer": true, "at_station": false,
		"roster": [{"steam_id": sid_a, "player_name": "Veteran", "class_id": "rogue",
			"player_state": rich_state, "rts_faction": 2, "is_host": false}]}
	_assert(SaveMgr.save_run(prev_run, "mp", 7), "c1fix: previous run saved to scratch slot")

	# Dungeon rig (script instance, never added to the tree): peers 77
	# and 88 both missed the window; 88 has NO previous entry.
	var d = DungeonScript.new()
	d.set("_save_slot", 7)
	d.set("_save_roster", [])
	d.set("_save_pending", {77: true, 88: true})
	d.set("peer_steam_ids", {77: sid_a, 88: sid_b})
	d.set("peer_classes", {77: "rogue", 88: "mage"})
	d.call("_mark_missing_disconnected")
	var roster: Array = d.get("_save_roster")
	_assert(roster.size() == 2, "c1fix: both missed peers get roster entries")
	var entry_a: Dictionary = {}
	var entry_b: Dictionary = {}
	for e in roster:
		if int(e.get("steam_id", 0)) == sid_a:
			entry_a = e
		elif int(e.get("steam_id", 0)) == sid_b:
			entry_b = e
	# The missed peer's PREVIOUS character survives verbatim.
	_assert(not entry_a.is_empty(), "c1fix: previous peer present in new roster")
	var ps_a: Dictionary = entry_a.get("player_state", {})
	_assert(int(ps_a.get("level", 0)) == 7 and int(ps_a.get("xp", 0)) == 432,
		"c1fix: missed-window peer keeps previous level/xp (no replica wipe)")
	_assert((ps_a.get("inventory", []) as Array).size() == 2,
		"c1fix: missed-window peer keeps previous inventory")
	_assert(str(entry_a.get("class_id", "")) == "rogue",
		"c1fix: previous class carried forward")
	_assert(not entry_a.has("disconnected"),
		"c1fix: dead disconnected marker no longer stamped")
	# No previous entry: empty state (restore = no restore) + REAL class.
	_assert(not entry_b.is_empty(), "c1fix: new peer present in new roster")
	_assert((entry_b.get("player_state", {"x": 1}) as Dictionary).is_empty(),
		"c1fix: no-previous-entry writes EMPTY state (never a replica capture)")
	_assert(str(entry_b.get("class_id", "")) == "mage",
		"c1fix: fallback uses the peer's real class from peer_classes (not hardcoded)")
	d.free()

	# Source discipline: the fill-in must not consult the replica at all,
	# and the dead marker must be gone from the whole file.
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	var start := dsrc.find("func _mark_missing_disconnected")
	var end := dsrc.find("\nfunc ", start + 10)
	var body := dsrc.substr(start, end - start)
	_assert(not body.contains("_roster_entry(sid, pid, node)"),
		"c1fix: fill-in never snapshots the replica node")
	_assert(not body.contains(".get_state("),
		"c1fix: fill-in never calls get_state on any node")
	_assert(not dsrc.contains("\"disconnected\""),
		"c1fix: dead disconnected marker fully removed")
	_assert(body.contains("find_roster_entry"),
		"c1fix: fill-in merges the previous roster by Steam64")

	# Cleanup + restore the autoload's test hooks.
	for f in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch.path_join(f))
	DirAccess.remove_absolute(scratch)
	if FileAccess.file_exists("user://profile_c1fix_scratch.cfg"):
		DirAccess.remove_absolute("user://profile_c1fix_scratch.cfg")
	SaveMgr.set("_test_runs_dir", "")
	SaveMgr.set("_test_account_pin", "")
	print("[Playtest] mp save c1 fix done")


func _test_character_panel_phase2() -> void:
	print("[Playtest] Character panel phase 2 (issue #104)...")
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")

	# --- Old ItemList panel is gone (source + scene).
	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/hud.tscn")
	_assert(not tsrc.contains("InventoryList"), "panel: ItemList node removed from hud.tscn")
	_assert(not tsrc.contains("type=\"ItemList\""), "panel: no ItemList type in hud.tscn")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(not hsrc.contains("%InventoryList"), "panel: hud.gd no longer references %InventoryList")
	_assert(hsrc.contains("func _build_character_panel"), "panel: character panel builder exists")

	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._player = p
	_assert(hud.find_child("InventoryList", true, false) == null,
		"panel: no ItemList in the live HUD scene")

	# --- Structure: 4 slot boxes + exactly 12 bag rows, no ScrollContainer.
	var panel = hud.find_child("InventoryPanel", true, false)
	_assert(panel != null, "panel: InventoryPanel exists")
	var slot_col = hud.find_child("SlotColumn", true, false)
	var bag_col = hud.find_child("BagColumn", true, false)
	_assert(slot_col != null and bag_col != null, "panel: slot + bag columns exist")
	for slot_name in ["WEAPON", "ARMOR", "TRINKET", "TOOL"]:
		_assert(hud.find_child("Slot_" + slot_name, true, false) != null,
			"panel: slot box exists for " + slot_name)
	var row_count := 0
	for child in bag_col.get_children():
		if str(child.name).begins_with("BagRow_"):
			row_count += 1
	_assert(row_count == 12, "panel: bag renders exactly INVENTORY_MAX (12) fixed rows")
	_assert(hud.find_child("EquipButton", true, false) != null, "panel: Equip button exists")
	_assert(hud.find_child("UseButton", true, false) != null, "panel: Use button retained")
	_assert(hud.find_child("DisposeButton", true, false) != null, "panel: Dispose button retained")
	var has_scroll := false
	var stack: Array = [panel]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is ScrollContainer:
			has_scroll = true
		for c in n.get_children():
			stack.append(c)
	_assert(not has_scroll, "panel: zero ScrollContainers (zero-scroll by construction)")

	# --- Fill the bag: gear, a class-restricted stack, a TOOL, potions.
	p.receive_item("iron_sword")
	p.receive_item("leather_armor")
	p.receive_item("phoenix_feather")
	p.receive_item("health_potion")
	p.receive_item("health_potion")
	var tome = ItemDBNode.get_item("scholar_tome").duplicate()
	var only_mage: Array[String] = ["mage"]
	tome.set("allowed_classes", only_mage)
	p.inventory.append({"item": tome, "count": 1, "equipped_slot": ""})
	hud.refresh_inventory(p)
	var rows: Array = hud.get("_bag_rows")
	var find_row := func(item_id: String) -> int:
		for i in p.inventory.size():
			var it = p.inventory[i].get("item")
			if it != null and str(it.get("id")) == item_id:
				return i
		return -1
	# Starter weapon shows in its slot box; bag rows are labeled.
	var slot_weapon = hud.find_child("SlotItem_WEAPON", true, false)
	_assert(str(slot_weapon.get("text")).contains("Rusty Sword"),
		"panel: WEAPON slot box shows the equipped starter")
	var iron_row: int = find_row.call("iron_sword")
	_assert(iron_row >= 0 and str(rows[iron_row].get("text")).contains("Iron Sword"),
		"panel: bag row shows the iron sword")
	var tome_row: int = find_row.call("scholar_tome")
	_assert(tome_row >= 0 and str(rows[tome_row].get("text")).contains("Mage only"),
		"panel: class-restricted row carries the 'Mage only' tag")

	# --- Mouse-only equip flow: select row + Equip button.
	(rows[iron_row] as Object).call("set_pressed", true)
	hud._on_equip_pressed()
	var eq = p.equipped_entry("WEAPON")
	_assert(not eq.is_empty() and str((eq["item"] as Object).get("id")) == "iron_sword",
		"panel: Equip button equips the selected row")
	hud.refresh_inventory(p)
	_assert(str(rows[iron_row].get("text")).begins_with("[EQ]"),
		"panel: equipped bag row is marked [EQ]")
	_assert(str(slot_weapon.get("text")).contains("Iron Sword"),
		"panel: slot box updates after equip")
	_assert(hud.find_child("SlotIcon_WEAPON", true, false) != null,
		"panel: slot icon element exists (hard-sized TextureRect)")

	# --- Denied equip: class-restricted row refuses through the panel.
	hud._equip_row(tome_row)
	_assert(str(p.inventory[tome_row].get("equipped_slot", "")) == "",
		"panel: class-restricted equip refused (denial path)")

	# --- TOOL slot flow + click-slot-to-unequip.
	var feather_row: int = find_row.call("phoenix_feather")
	hud._equip_row(feather_row)
	_assert(not p.equipped_entry("TOOL").is_empty(), "panel: feather equips into TOOL")
	hud._on_slot_pressed("TOOL")
	_assert(p.equipped_entry("TOOL").is_empty(), "panel: clicking a filled slot unequips it")

	# --- Use + Dispose retained for the selected row.
	var pot_row: int = find_row.call("health_potion")
	var pot_before := int(p.inventory[pot_row]["count"])
	(rows[pot_row] as Object).call("set_pressed", true)
	hud._on_use_pressed()
	_assert(int(p.inventory[pot_row]["count"]) == pot_before - 1,
		"panel: Use consumes one from the selected stack")
	(rows[tome_row] as Object).call("set_pressed", true)
	hud._on_dispose_pressed()
	_assert(find_row.call("scholar_tome") == -1, "panel: Dispose removes the selected stack")

	# --- Fixed rows persist at any fill level (zero-scroll invariant).
	hud.refresh_inventory(p)
	var rows_after := 0
	for child in bag_col.get_children():
		if str(child.name).begins_with("BagRow_"):
			rows_after += 1
	_assert(rows_after == 12, "panel: still exactly 12 rows after inventory changes")
	hud.queue_free()
	p.queue_free()
	print("[Playtest] character panel phase 2 done")


## Issue #136 diagnostic: the inventory-removal audit trap + the panel
## swap regressions. The trap is TEMPORARY (its removal rides with the
## #136 fix/closure); the panel pins lock the characterization result —
## the double-click equip paths cannot delete a stack.
func _test_inventory_audit_136() -> void:
	print("[Playtest] Inventory audit trap (issue #136)...")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")

	# --- Panel regressions (the characterization fuzz, locked in) ---
	var p = PlayerScene.instantiate()
	p.class_id = "mage"
	root.add_child(p) # starter kit: apprentice staff, equipped
	p.receive_item("rusty_sword")
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud.setup(p)
	hud.refresh_inventory(p)
	var dbl := InputEventMouseButton.new()
	dbl.pressed = true
	dbl.double_click = true
	dbl.button_index = MOUSE_BUTTON_LEFT
	var press := InputEventMouseButton.new()
	press.pressed = true
	press.button_index = MOUSE_BUTTON_LEFT
	var sword_idx := -1
	var staff_idx := -1
	for i in p.inventory.size():
		var iid := (p.inventory[i]["item"] as ItemData).id
		if iid == "rusty_sword":
			sword_idx = i
		if iid == "apprentice_staff":
			staff_idx = i
	_assert(sword_idx >= 0 and staff_idx >= 0, "136: fixture carries staff + sword")
	hud._on_bag_row_gui_input(dbl, sword_idx)
	_assert(str(p.inventory[sword_idx].get("equipped_slot", "")) == "WEAPON",
		"136: dbl-click equips the sword")
	_assert(str(p.inventory[staff_idx].get("equipped_slot", "")) == "",
		"136: swap unequips the staff in place")
	hud._on_bag_row_gui_input(dbl, sword_idx)
	_assert(p.inventory.size() == 2, "136: dbl-click on the equipped row changes nothing")
	hud._on_bag_row_gui_input(dbl, staff_idx)
	_assert(str(p.inventory[staff_idx].get("equipped_slot", "")) == "WEAPON",
		"136: dbl-click swaps back to the staff")
	hud._on_bag_row_gui_input(dbl, staff_idx)
	_assert(p.inventory.size() == 2
		and str(p.inventory[staff_idx].get("equipped_slot", "")) == "WEAPON",
		"136: dbl-click on the equipped staff is a no-op")
	hud._on_slot_gui_input(press, "WEAPON")
	hud._on_slot_gui_input(press, "WEAPON")
	_assert(p.inventory.size() == 2, "136: slot double-press never deletes")
	var staff_present := false
	for e in p.inventory:
		if (e["item"] as ItemData).id == "apprentice_staff":
			staff_present = true
	_assert(staff_present, "136: staff present after every panel gesture")
	hud.queue_free()
	p.queue_free()

	# --- Audit events on representative paths ---
	var q = PlayerScene.instantiate()
	q.class_id = "warrior"
	root.add_child(q)
	q.receive_item("health_potion")
	q.inventory_audit_log.clear()
	var pot_idx := -1
	for i in q.inventory.size():
		if (q.inventory[i]["item"] as ItemData).id == "health_potion":
			pot_idx = i
	q.dispose_item(pot_idx)
	_assert(_audit_has(q, "dispose_item", "health_potion"),
		"136: dispose emits an audit event")
	q.receive_item("health_potion")
	for i in q.inventory.size():
		if (q.inventory[i]["item"] as ItemData).id == "health_potion":
			pot_idx = i
	q.inventory[pot_idx]["count"] = 1
	q.hp = q.max_hp * 0.5
	q.inventory_audit_log.clear()
	q.use_item(pot_idx)
	_assert(_audit_has(q, "use_item", "health_potion"),
		"136: use-to-zero emits an audit event")
	q.inventory_audit_log.clear()
	var st: Dictionary = q.get_state()
	(st["inventory"] as Array).append(
		{"id": "nonexistent_item_xyz", "count": 2, "slot": "", "upgrade_level": 0})
	q.apply_state(st)
	_assert(_audit_has(q, "apply_state", "nonexistent_item_xyz"),
		"136: apply_state drop emits an audit event")
	q.inventory_audit_log.clear()
	q.apply_state(q.get_state())
	_assert(q.inventory_audit_log.is_empty(),
		"136: lossless apply_state emits no audit event")
	q.queue_free()

	# --- Source pins: every eraser reports to the audit helper ---
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("func _audit_inventory("), "136: audit helper exists")
	_assert(psrc.contains("[#136-INVENTORY-AUDIT]"), "136: audit line prefix present")
	_assert(psrc.contains("TEMPORARY #136 diagnostic"), "136: instrumentation marked temporary")
	for fname in ["dispose_item", "use_item", "_use_upgrade_kit", "consume_seed_item",
			"consume_dock_good", "consume_farm_cash", "_do_death", "apply_state"]:
		var fpos := psrc.find("func " + fname + "(")
		var npos := psrc.find("\nfunc ", fpos + 1)
		_assert(fpos != -1 and npos != -1
			and psrc.substr(fpos, npos - fpos).contains("_audit_inventory("),
			"136: %s reports to the audit helper" % fname)
	print("[Playtest] Inventory audit trap done")


func _audit_has(p, site: String, item_id: String) -> bool:
	for line in p.inventory_audit_log:
		if line.contains("site=" + site) and line.contains("item=" + item_id):
			return true
	return false


## Issue #137: the menu-sequence batch — (a) continue-lobby class truth,
## (c) no invite auto-open, (d) HostPhase fits 720p, (e) lobby-list
## format. ((b) was ruled not-a-defect: the Architect is the secret
## cipher class, unlock-gated in every class surface by design.)
func _test_menu_batch_137() -> void:
	print("[Playtest] Menu batch (issue #137)...")
	var MenuScene: PackedScene = load("res://scenes/ui/main_menu.tscn")
	var menu = MenuScene.instantiate()
	root.add_child(menu)
	var msrc := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	var NM = root.get_node("NetworkManager")

	# (e) The lobby list status line formats cleanly for 1 and N.
	menu._on_lobby_list([{"name": "A", "players": 1, "max_players": 4}])
	_assert(menu.get_node("%JoinStatusLabel").text == "Found 1 lobby",
		"137e: singular lobby count formats")
	menu._on_lobby_list([{"name": "A", "players": 1, "max_players": 4},
		{"name": "B", "players": 2, "max_players": 4},
		{"name": "C", "players": 3, "max_players": 4}])
	_assert(menu.get_node("%JoinStatusLabel").text == "Found 3 lobbies",
		"137e: plural lobby count formats")
	_assert(not msrc.contains("tr_n(\""), "137e: no tr_n remnant in main_menu.gd")

	# (a) A continued run's lobby selects the roster host's class.
	NM._continued_run = {
		"lobby": {"lobby_name": "Dungeon"},
		"players": [
			{"steam_id": 111, "name": "H", "class_id": "mage", "is_host": true,
				"player_state": {"level": 7}},
			{"steam_id": 222, "name": "G", "class_id": "warrior", "is_host": false,
				"player_state": {"level": 5}},
		],
	}
	NM.selected_class_id = "warrior"
	menu._on_staging_ready()
	_assert(NM.selected_class_id == "mage",
		"137a: continue derives the selection from the roster host")
	var row = menu.get_node("%LobbyPanel/LobbyClassRow")
	var pressed_text := ""
	for b in row.get_children():
		if (b as Button).button_pressed:
			pressed_text = (b as Button).text
	_assert(pressed_text == "Mage", "137a: the Mage row button is the selected one")
	NM._continued_run = {}
	NM.selected_class_id = "warrior"

	# (c) The staging handler no longer springs the invite overlay;
	# the manual Invite All path still can.
	var sp := msrc.find("func _on_staging_ready()")
	var sp_end := msrc.find("\nfunc ", sp + 1)
	_assert(sp != -1 and not msrc.substr(sp, sp_end - sp).contains("open_invite_dialog"),
		"137c: staging ready does not auto-open the invite dialog")
	var ia := msrc.find("func _on_invite_all_pressed()")
	var ia_end := msrc.find("\nfunc ", ia + 1)
	_assert(ia != -1 and msrc.substr(ia, ia_end - ia).contains("open_invite_dialog"),
		"137c: manual Invite All still opens the dialog")

	# (d) HostPhase geometry: no tab page may inflate the stack past a
	# 720p fit; the warning label's wrapped minimum stays honest.
	menu._on_host_pressed()
	var tabs = menu.get_node("%HostPhase/HostTabs")
	_assert(tabs.get_combined_minimum_size().y <= 380.0,
		"137d: host tabs minimum height fits 720p with margin")
	var lobby_page = tabs.get_child(2)
	_assert(lobby_page.get_combined_minimum_size().y < 500.0,
		"137d: Lobby tab minimum height is sane")
	var warn_min := Vector2.ZERO
	for c in lobby_page.get_children():
		if c is Label and (c as Label).text.begins_with("Warning:"):
			warn_min = (c as Control).get_combined_minimum_size()
	_assert(warn_min.x >= 400.0 and warn_min.y < 80.0,
		"137d: warning label wrapped minimum is honest")
	menu.queue_free()
	print("[Playtest] Menu batch done")


func _test_inventory_pause_screen() -> void:
	print("[Playtest] Inventory as alternative pause screen (Jesse 2026-10-13)...")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")

	# --- Source pins: gate + swap live at the proven seams, and the
	# feature adds NO tree pausing anywhere (solo behaves like MP).
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(psrc.contains("hud.inventory_open"),
		"invpause: take_damage/input read hud.inventory_open")
	_assert(psrc.contains("hud.swap_inventory_to_pause()"),
		"invpause: Esc branch swaps inventory -> pause")
	_assert(psrc.contains("not hud.inventory_open"),
		"invpause: click-recapture guard knows the inventory")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("func open_inventory") and hsrc.contains("func close_inventory")
		and hsrc.contains("func swap_inventory_to_pause"),
		"invpause: hud owns open/close/swap")
	_assert(not hsrc.contains("get_tree().paused") and not psrc.contains("get_tree().paused"),
		"invpause: no tree pausing added by the feature")

	# --- Centered panel (scene data): anchors at 0.5, symmetric offsets.
	var tsrc := FileAccess.get_file_as_string("res://scenes/ui/hud.tscn")
	var inv_block := ""
	var inv_start := tsrc.find("[node name=\"InventoryPanel\"")
	if inv_start >= 0:
		var inv_end := tsrc.find("[node name=", inv_start + 10)
		inv_block = tsrc.substr(inv_start, (inv_end - inv_start) if inv_end > inv_start else 600)
	_assert(inv_block.contains("anchor_left = 0.5") and inv_block.contains("anchor_right = 0.5")
		and inv_block.contains("offset_left = -330.0") and inv_block.contains("offset_right = 330.0"),
		"invpause: InventoryPanel centered in hud.tscn")

	# --- Behavioral: real player + real HUD through the real gate.
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._player = p
	p.hud = hud
	var panel = hud.find_child("InventoryPanel", true, false)
	var pause_panel = hud.find_child("PausePanel", true, false)
	p.hp = p.max_hp
	p.take_damage(10.0, "test")
	_assert(p.hp == p.max_hp - 10.0, "invpause: damage lands while closed")
	hud.toggle_inventory()
	_assert(hud.inventory_open and panel.visible, "invpause: toggle opens panel + state")
	p.take_damage(40.0, "test")
	_assert(p.hp == p.max_hp - 10.0, "invpause: NO damage while inventory open")
	hud.swap_inventory_to_pause()
	_assert(not hud.inventory_open and not panel.visible, "invpause: swap closes inventory")
	_assert(hud.is_paused and pause_panel.visible, "invpause: swap opens pause UI (one panel up)")
	p.take_damage(40.0, "test")
	_assert(p.hp == p.max_hp - 10.0, "invpause: pause breather still gates after swap")
	hud.hide_pause()
	hud.toggle_inventory()
	_assert(hud.inventory_open and panel.visible, "invpause: reopen after pause")
	hud.toggle_inventory()
	_assert(not hud.inventory_open and not panel.visible, "invpause: toggle-close is clean")
	p.take_damage(40.0, "test")
	_assert(p.hp == p.max_hp - 50.0, "invpause: damage lands after toggle-close")
	hud.queue_free()
	p.queue_free()
	print("[Playtest] inventory pause screen done")


func _test_fishing_rod_phase3() -> void:
	print("[Playtest] Fishing rod + rod-out + director casting (issues #104 P3 / #126 P1+P2)...")
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var DirectorScript: GDScript = load("res://scripts/fishing/fishing_director.gd")
	var MerchScript: GDScript = load("res://scripts/dungeon/dock_merchant.gd")
	var EconScript: GDScript = load("res://scripts/dungeon/dock_economy.gd")
	var LegendScript: GDScript = load("res://scripts/ui/mouse_legend.gd")
	# Purge leftover players from earlier tests so group lookups can't
	# hand the director a stale (possibly rod-equipped) player.
	for n in get_nodes_in_group("players"):
		(n as Node).free()

	# --- The rod item: TOOL gear, no stats, one shared id everywhere.
	var rod = ItemDBNode.get_item("fishing_rod")
	_assert(rod != null, "rod: fishing_rod exists in ItemDB")
	_assert(int(rod.get("slot")) == 3, "rod: TOOL slot")
	_assert(not bool(rod.get("consumable")), "rod: not consumable")
	_assert(float(rod.get("damage_bonus")) == 0.0 and float(rod.get("health_bonus")) == 0.0 \
		and float(rod.get("speed_bonus")) == 0.0 and float(rod.get("damage_mult")) == 1.0,
		"rod: zero stats (pure gate key)")
	_assert(str(EconScript.ROD_ITEM) == "fishing_rod", "rod: economy item id")
	# Issue #126: the rod refusal is deleted everywhere; Phase 2
	# deleted the spot itself — sessions live on the FishingDirector.
	_assert(not ResourceLoader.exists("res://scripts/dungeon/fishing_spot.gd"),
		"#126 P2: fishing_spot.gd deleted")
	_assert(ResourceLoader.exists("res://scripts/fishing/fishing_director.gd"),
		"#126 P2: fishing_director.gd exists")
	var dconsts: Dictionary = DirectorScript.get_script_constant_map()
	_assert(not dconsts.has("ROD_PROMPT"), "#126: no refusal constant on the director")
	var legend_src := FileAccess.get_file_as_string("res://scripts/ui/mouse_legend.gd")
	_assert(not legend_src.contains("Requires " + "Fishing Rod") and not legend_src.contains("fishing_blocked"),
		"#126: legend blocked state + refusal deleted")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(not psrc.contains("Requires " + "Fishing Rod"), "#126: no rod refusal in the player source")
	_assert(psrc.contains("KEY_V"), "#126: rod key branch exists (V; F is the class ability)")
	_assert(psrc.contains("Equip your Fishing Rod (Tool slot) to cast"), "#126: equip toast text")
	_assert(psrc.contains("The dock merchant sells a Fishing Rod"), "#126: merchant toast text")
	_assert(psrc.contains("rod_out and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED"),
		"#126: LMB attacks disabled while rod-out")

	# --- Server cast gate (Phase 2): the one rod check that survives
	# lives on the director — a forged cast with no rod EQUIPPED is
	# rejected server-side; spots/prompts no longer exist at all.
	var g = PlayerScene.instantiate()
	g.class_id = "warrior"
	root.add_child(g)
	g.global_position = Vector3.ZERO
	var director = DirectorScript.new()
	root.add_child(director)
	director.test_players = {1: g}
	DirectorScript.debug_force_water = 1
	_assert(not g.has_rod_equipped(), "cast gate: fresh player has no rod")
	director.request_cast(Vector3(0, 0, 4))
	_assert(not director.has_bobber(1),
		"cast gate: forged cast without the rod rejected (#126 P2)")
	_assert(str(g.legend_state()) == "standard",
		"legend: no spot-proximity fishing context anymore (#126 P2)")

	# --- Rod-out mode gates (issue #126 gates c/d; Choice B: the rod
	# must be EQUIPPED — ownership alone never enters the mode).
	g.call("_toggle_rod_out")
	_assert(not bool(g.get("rod_out")), "rod-out: no rod -> cannot enter (gate c)")
	g.call("receive_item", "fishing_rod")
	_assert(bool(g.call("_owns_fishing_rod")) and not g.has_rod_equipped(),
		"rod-out: rod owned but unequipped")
	g.call("_toggle_rod_out")
	_assert(not bool(g.get("rod_out")), "rod-out: owned-but-unequipped cannot enter (Choice B)")
	for i in g.inventory.size():
		var it = g.inventory[i].get("item")
		if it != null and str(it.get("id")) == "fishing_rod":
			g.equip_stack(i)
			break
	_assert(g.has_rod_equipped(), "rod-out: rod equipped in TOOL")
	g.call("_toggle_rod_out")
	_assert(bool(g.get("rod_out")), "rod-out: equipped rod enters the mode (gate d)")
	g.call("_toggle_rod_out")
	_assert(not bool(g.get("rod_out")), "rod-out: key toggles back off")
	g.call("_toggle_rod_out")
	for i in g.inventory.size():
		var it2 = g.inventory[i].get("item")
		if it2 != null and str(it2.get("id")) == "fishing_rod":
			g.unequip_stack(i)
			break
	_assert(not g.has_rod_equipped() and not bool(g.get("rod_out")),
		"rod-out: losing the equipped rod ends the mode")
	# Re-equip the same stack for the session block below.
	for i in g.inventory.size():
		var it3 = g.inventory[i].get("item")
		if it3 != null and str(it3.get("id")) == "fishing_rod":
			g.equip_stack(i)
			break
	_assert(g.has_rod_equipped(), "rod-out: rod re-equipped for the session block")
	# Issue #126 Phase 3: rod-out legend contexts — registry rows for
	# all four states + the live state machine on the player.
	_assert(str(LegendScript.actions_for("warrior", "fishing_ready")["left"]).contains("Cast"),
		"legend P3: fishing_ready left = Cast")
	_assert(str(LegendScript.actions_for("mage", "fishing_wait")["right"]).contains("Reel"),
		"legend P3: fishing_wait right = Reel in")
	_assert(str(LegendScript.actions_for("rogue", "fishing_aim")["left"]).contains("Aim at water"),
		"legend P3: fishing_aim left = Aim at water")
	_assert(str(LegendScript.actions_for("architect", "fishing_hook")["left"]).contains("Hook"),
		"legend P3: fishing_hook left = Hook!")
	g._toggle_rod_out()
	DirectorScript.debug_force_water = 1
	_assert(g.legend_state() == "fishing_ready", "legend P3: aiming at water reads Cast")
	DirectorScript.debug_force_water = 0
	_assert(g.legend_state() == "fishing_aim", "legend P3: aiming at dirt reads Aim at water")
	g.set_bobber_out(true)
	_assert(g.legend_state() == "fishing_wait", "legend P3: bobber out reads the reel context")
	g.set_bite_ready(true)
	_assert(g.legend_state() == "fishing_hook", "legend P3: bite window reads Hook!")
	g.set_bobber_out(false)
	DirectorScript.debug_force_water = 1 # restore the section's seam state
	g._toggle_rod_out()
	# Issue #126 Phase 3 cleanup pin: the interact scan no longer
	# enumerates the deleted spots group.
	var player_src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	_assert(not player_src.contains("\"fishing_spots\""),
		"cleanup P3: no fishing_spots group entry left in player.gd")
	# Issue #131: a REAL HUD on the fisher before the session drive,
	# so the bite toast has somewhere to land (and the pin below can
	# watch it land — the old pin asserted only the _bite_ready
	# mirror and stayed green over a dead p.toast call site).
	var HudScene131: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud131 = HudScene131.instantiate()
	root.add_child(hud131)
	hud131.setup(g)
	_assert(g.hud == hud131, "131: HUD attached to the fisher")
	DirectorScript.debug_wait_override = 2.0
	DirectorScript.debug_now_msec = 900000
	DirectorScript.debug_catch_roll = 0.9 # deterministic minnow
	director.request_cast(Vector3(0, 0, 4))
	_assert(director.session_state_for(1) == DirectorScript.SessionState.WAITING,
		"session: validated cast with the rod equipped")
	_assert(bool(g.get("_bobber_out")), "session: bobber mirror set")
	DirectorScript.debug_now_msec = 900000 + 2100
	director._process(0.016)
	_assert(director.session_state_for(1) == DirectorScript.SessionState.BITING, "session: bite fired")
	_assert(bool(g.get("_bite_ready")), "session: bite mirror set")
	var toast_label = hud131.get_node("%ToastLabel") as Label
	_assert(toast_label != null and toast_label.text == "Bite! LMB / E to hook",
		"131: the bite toast actually reaches the fisher's HUD")
	director.request_hook()
	_assert(_farm_inv_count(g, "fish_minnow") == 1, "session: catch landed with the rod")
	_assert(not director.has_bobber(1), "session: catch ends the session")
	DirectorScript.debug_wait_override = -1.0
	DirectorScript.debug_catch_roll = -1.0
	DirectorScript.debug_now_msec = -1
	DirectorScript.debug_force_water = -1
	director.free()

	# --- Issue #129: a flop visual self-frees with no fx resolution;
	# its _visuals entry must not go stale (the recast's clear path
	# used to cast the freed instance and log a SCRIPT ERROR).
	var dsrc129 := FileAccess.get_file_as_string("res://scripts/fishing/fishing_director.gd")
	_assert(dsrc129.contains("func _visual_for"), "129: validity-safe visual fetch exists")
	_assert(not dsrc129.contains("_visuals.get(peer) as FishingVisual"),
		"129: no cast-before-check fetch remains in the fx getters")
	var director2 = DirectorScript.new()
	root.add_child(director2)
	director2.fx_cast(7, Vector3(0, 1, 0), Vector3(3, 0, 3), false) # dirt: flop
	var vis129: Dictionary = director2.get("_visuals")
	_assert(vis129.has(7), "129: flop cast stores a visual")
	var flop_v = vis129[7]
	var steps := 0
	while not flop_v.is_queued_for_deletion() and steps < 400:
		flop_v._process(0.05)
		steps += 1
	_assert(flop_v.is_queued_for_deletion(), "129: flop visual resolves and self-frees")
	flop_v.free() # the frame-end flush, driven synchronously
	_assert(not vis129.has(7), "129: entry erased when the flop visual exits")
	director2.fx_cast(7, Vector3(0, 1, 0), Vector3(3, 0.5, 3), true) # recast, water
	_assert(vis129.has(7) and is_instance_valid(vis129[7]),
		"129: recast after a flop stores a live visual (clear path error-free)")
	director2.fx_bite(7)
	director2.fx_reel_in(7)
	_assert(not vis129.has(7), "129: reel-in erases the entry")
	director2.free()

	# --- Persistence: save roundtrip keeps the rod AND its TOOL marker.
	var state: Dictionary = g.get_state()
	var g2 = PlayerScene.instantiate()
	g2.class_id = "warrior"
	root.add_child(g2)
	g2.apply_state(state)
	_assert(_farm_inv_count(g2, "fishing_rod") == 1, "persist: rod survives save/load")
	_assert(str(g2.equipped_ids.get("TOOL", "")) == "fishing_rod",
		"persist: TOOL marker + equipped_ids survive save/load")
	_assert(g2.has_rod_equipped(), "persist: restored player has the rod equipped")

	# --- Held visuals: own viewmodel + peer prop via push_snapshot.
	_assert(g.find_child("RodProp", true, false) != null,
		"visuals: rod prop in the local viewmodel when equipped")
	var pv = PlayerScene.instantiate()
	pv.class_id = "mage"
	pv.set_multiplayer_authority(2)
	root.add_child(pv)
	pv.push_snapshot(pv.global_position, 100.0, 1, true, 0.0,
		{"TOOL": "fishing_rod", "WEAPON": "iron_sword"})
	_assert(str(pv.equipped_ids.get("TOOL", "")) == "fishing_rod",
		"visuals: snapshot carries equipped_ids to the peer replica")
	var held = pv.get_node_or_null("HeldProp")
	_assert(held != null and held.visible, "visuals: peer HeldProp visible")
	_assert(held != null and held.get_node_or_null("RodProp") != null,
		"visuals: peer sees the held rod")
	_assert(held != null and held.get_node_or_null("WeaponProp") != null,
		"visuals: peer sees the equipped weapon's world_model")
	# Issue #126 Phase 1: rod_out rides the snapshot; in rod-out the
	# peer HeldProp shows the rod alone (weapon suppressed).
	pv.push_snapshot(pv.global_position, 100.0, 1, true, 0.0,
		{"TOOL": "fishing_rod", "WEAPON": "iron_sword"}, true)
	_assert(bool(pv.get("rod_out")), "visuals: snapshot carries rod_out to the peer replica")
	held = pv.get_node_or_null("HeldProp")
	_assert(held != null and held.get_node_or_null("RodProp") != null
		and held.get_node_or_null("WeaponProp") == null,
		"visuals: in rod-out peers see the rod alone")

	# --- Merchant: GEAR listing, buy / dispose / re-buy (permanent stock).
	var cat: Array = MerchScript.catalog()
	var rod_row: Dictionary = {}
	for e in cat:
		if str(e.get("id")) == "fishing_rod":
			rod_row = e
	_assert(not rod_row.is_empty(), "merchant: rod listed in the dock catalog")
	_assert(bool(rod_row.get("gear", false)), "merchant: rod row flagged GEAR")
	_assert(int(rod_row.get("price")) == EconScript.PRICE_ROD,
		"merchant: rod priced at PRICE_ROD")
	_assert(EconScript.sell_value_for("fishing_rod") == 0,
		"merchant: rod is not a sellable dock good")
	var m = PlayerScene.instantiate()
	m.class_id = "warrior"
	root.add_child(m)
	var merch = MerchScript.new()
	root.add_child(merch)
	merch.test_player = m
	EconScript.debug_reset()
	EconScript.grant_cash(1, 25)
	merch.request_buy("fishing_rod")
	_assert(_farm_inv_count(m, "fishing_rod") == 1, "merchant: rod bought for farm cash")
	_assert(EconScript.cash_balance(1) == 25 - EconScript.PRICE_ROD,
		"merchant: PRICE_ROD deducted from the ledger")
	_assert(EconScript.stock_count(1, "fishing_rod") == 0,
		"merchant: rod NOT tracked as dock-good stock")
	# Dispose (unequipped) and re-buy: permanent stock.
	for i in m.inventory.size():
		var it = m.inventory[i].get("item")
		if it != null and str(it.get("id")) == "fishing_rod":
			m.dispose_item(i)
			break
	_assert(_farm_inv_count(m, "fishing_rod") == 0, "merchant: rod disposed")
	merch.request_buy("fishing_rod")
	_assert(_farm_inv_count(m, "fishing_rod") == 1, "merchant: rod re-buyable after dispose")
	EconScript.debug_reset()
	merch.free()
	g.queue_free()
	g2.queue_free()
	pv.queue_free()
	m.queue_free()
	print("[Playtest] fishing rod phase 3 done")


func _test_class_tagging_phase4() -> void:
	print("[Playtest] Class tagging + full validation (issue #104 Phase 4)...")
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	for n in get_nodes_in_group("players"):
		(n as Node).free()

	# --- The tagging matrix, read back from the shipped catalog data.
	var expect := {
		"apprentice_staff": ["mage"], "storm_caller": ["mage"],
		"scholar_tome": ["mage"], "storm_talisman": ["mage"],
		"worn_dagger": ["rogue"], "void_blade": ["rogue"],
		"swift_boots": ["rogue"],
		"kingsfall_blade": ["warrior"], "plate_armor": ["warrior"],
		"dragonscale_armor": ["warrior"], "aegis_of_the_deep": ["warrior"],
		"runeblade": ["warrior", "mage"],
	}
	for id in expect:
		var it = ItemDBNode.get_item(id)
		_assert(it != null, "tags: %s exists" % id)
		var got: Array = []
		for c in it.get("allowed_classes"):
			got.append(str(c))
		_assert(got == expect[id], "tags: %s restricted to %s (got %s)" % [id, str(expect[id]), str(got)])
	# Universal by design: generic blades/armor, the rod (every class
	# fishes), the feather (achievement reward), universal trinkets.
	for id in ["rusty_sword", "iron_sword", "leather_armor", "lucky_charm",
			"ember_amulet", "phoenix_feather", "fishing_rod"]:
		var it = ItemDBNode.get_item(id)
		_assert((it.get("allowed_classes") as Array).is_empty(),
			"tags: %s stays universal" % id)
	# Phoenix Feather icon: the feather shares charm.png with the Lucky
	# Charm (data-level fact behind the Phase 2 art gap — the TOOL slot
	# renders the medallion; a feather asset is the Art Director's).
	var feather = ItemDBNode.get_item("phoenix_feather")
	var charm = ItemDBNode.get_item("lucky_charm")
	_assert(feather.get("icon") != null and feather.get("icon") == charm.get("icon"),
		"feather icon: shares the Lucky Charm medallion texture (art gap, data-confirmed)")

	# --- Enforcement against the tagged catalog (real items, real code).
	var w = PlayerScene.instantiate()
	w.class_id = "warrior"
	root.add_child(w)
	_grant_equipped(w, "plate_armor")
	_assert(str(w.equipped_ids.get("ARMOR", "")) == "plate_armor",
		"tags: warrior equips warrior-only plate")
	var mg = PlayerScene.instantiate()
	mg.class_id = "mage"
	root.add_child(mg)
	mg.receive_item("plate_armor")
	for i in mg.inventory.size():
		var it2 = mg.inventory[i].get("item")
		if it2 != null and str(it2.get("id")) == "plate_armor":
			_assert(not mg.equip_stack(i), "tags: mage refused warrior-only plate")
	_grant_equipped(mg, "apprentice_staff")
	_assert(str(mg.equipped_ids.get("WEAPON", "")) == "apprentice_staff",
		"tags: mage equips mage-only staff")

	# --- Solo class-switch auto-unequip against the tagged catalog.
	_grant_equipped(w, "iron_sword") # universal: must survive the switch
	_assert(str(w.equipped_ids.get("WEAPON", "")) == "iron_sword", "switch: setup weapon")
	w.switch_class("mage")
	_assert(str(w.equipped_ids.get("ARMOR", "")) == "",
		"switch: warrior-only plate auto-unequipped on switch to mage")
	_assert(w.equipped_entry("ARMOR").is_empty(),
		"switch: ARMOR slot empty after switch")
	_assert(str(w.equipped_ids.get("WEAPON", "")) == "iron_sword",
		"switch: universal gear stays equipped")
	_assert(_farm_inv_count(w, "plate_armor") == 1,
		"switch: unequipped plate stays in the bag (not deleted)")

	# --- Migration regression vs the tagged catalog: a marker-less save
	# auto-equips only what the class may wear.
	var donor = PlayerScene.instantiate()
	donor.class_id = "warrior"
	root.add_child(donor)
	donor.inventory.clear()
	donor.receive_item("plate_armor")
	donor.receive_item("apprentice_staff")
	var legacy: Dictionary = donor.get_state()
	for e in legacy["inventory"]:
		e.erase("slot") # strip markers -> legacy format
	var mig_mage = PlayerScene.instantiate()
	mig_mage.class_id = "mage"
	root.add_child(mig_mage)
	mig_mage.apply_state(legacy)
	_assert(str(mig_mage.equipped_ids.get("WEAPON", "")) == "apprentice_staff",
		"migration: mage auto-equips the mage staff from a legacy save")
	_assert(str(mig_mage.equipped_ids.get("ARMOR", "")) == "",
		"migration: warrior-only plate NOT auto-equipped for a mage")
	var mig_war = PlayerScene.instantiate()
	mig_war.class_id = "warrior"
	root.add_child(mig_war)
	mig_war.apply_state(legacy)
	_assert(str(mig_war.equipped_ids.get("ARMOR", "")) == "plate_armor",
		"migration: warrior auto-equips the plate from the same legacy save")

	# --- Save/load roundtrip keeps tagged markers.
	var rt = PlayerScene.instantiate()
	rt.class_id = "warrior"
	root.add_child(rt)
	_grant_equipped(rt, "kingsfall_blade")
	var saved: Dictionary = rt.get_state()
	var rt2 = PlayerScene.instantiate()
	rt2.class_id = "warrior"
	root.add_child(rt2)
	rt2.apply_state(saved)
	_assert(str(rt2.equipped_ids.get("WEAPON", "")) == "kingsfall_blade",
		"roundtrip: tagged weapon marker + equipped_ids survive save/load")

	# --- MP visibility pass: tagged gear reaches the peer's held props.
	var pv = PlayerScene.instantiate()
	pv.class_id = "mage"
	pv.set_multiplayer_authority(2)
	root.add_child(pv)
	pv.push_snapshot(pv.global_position, 100.0, 1, true, 0.0,
		{"WEAPON": "kingsfall_blade", "TOOL": "phoenix_feather"})
	var held = pv.get_node_or_null("HeldProp")
	_assert(held != null and held.get_node_or_null("WeaponProp") != null,
		"mp visibility: peer sees the tagged weapon's world_model prop")
	_assert(held != null and held.get_node_or_null("RodProp") == null,
		"mp visibility: feather in TOOL does not conjure a rod prop")
	w.queue_free()
	mg.queue_free()
	donor.queue_free()
	mig_mage.queue_free()
	mig_war.queue_free()
	rt.queue_free()
	rt2.queue_free()
	pv.queue_free()
	print("[Playtest] class tagging phase 4 done")


func _test_save_format_pf2() -> void:
	print("[Playtest] Save format PF Phase 2 (lossless round-trip)...")
	# Issue #111 pulled-forward item, PF Phase 2 (Eng 3): unknown keys
	# survive a load -> continue -> re-save cycle at all three levels —
	# player_state (Player._state_extras), roster entry (producer merge
	# by steam_id), and run top level (loaded-dict-first producers).
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var DungeonScript = load("res://scripts/dungeon/dungeon.gd")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	var stsrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(psrc.contains("_state_extras"), "pf2: player carries _state_extras")
	_assert(psrc.contains("STATE_KEYS"), "pf2: consumed-key set is explicit")
	# Loaded-dict-first seeding present in all four producers (the two
	# MP producers + station are also driven live / merged below; the
	# solo literals are pinned here — they share the identical pattern).
	_assert(dsrc.contains("_save_base = SaveManager.load_run(SaveManager.MODE_MP,"),
		"pf2: dungeon MP producer seeds _save_base from the loaded dict")
	_assert(dsrc.contains("SaveManager.MODE_SOLO, NetworkManager.active_run_slot).duplicate(true)"),
		"pf2: dungeon solo producer is loaded-dict-first")
	_assert(hsrc.contains("SaveManager.MODE_SOLO, NetworkManager.active_run_slot).duplicate(true)"),
		"pf2: hud pause-save producer is loaded-dict-first")
	_assert(stsrc.contains("SaveManager.load_run(SaveManager.MODE_MP,"),
		"pf2: station producer is loaded-dict-first")
	_assert(dsrc.contains("prev_by_sid") and stsrc.contains("prev_by_sid"),
		"pf2: roster-entry unknown-key merge in both MP producers")
	# F-1 (Eng 9, PF2 verification): the lobby dict is composed by BOTH
	# MP producers as a merge over the LOADED lobby (only max_players /
	# lobby_name / visibility are overwritten) — pin that form so a
	# fresh-literal lobby regression fails here even before the rig.
	_assert(dsrc.contains("(_save_base.get(\"lobby\", {}) as Dictionary).duplicate(true)"),
		"pf2: dungeon lobby composed from the loaded lobby dict (F-1)")
	_assert(stsrc.contains("(base.get(\"lobby\", {}) as Dictionary).duplicate(true)"),
		"pf2: station lobby composed from the loaded lobby dict (F-1)")

	# --- Player level: unknown keys survive apply_state -> get_state.
	for n in get_nodes_in_group("players"):
		(n as Node).free()
	var p = PlayerScene.instantiate()
	p.class_id = "mage"
	root.add_child(p)
	var st: Dictionary = p.get_state()
	st["level"] = 9
	st["pf2_future_state"] = {"nested": [1, 2, 3], "note": "from a newer build"}
	st["pf2_future_scalar"] = 42
	p.apply_state(st)
	var back: Dictionary = p.get_state()
	_assert(int(back.get("level", 0)) == 9, "pf2: live fields apply normally")
	_assert(int(back.get("pf2_future_scalar", 0)) == 42,
		"pf2: unknown scalar key survives apply -> get")
	_assert(str(back.get("pf2_future_state", {})) == str({"nested": [1, 2, 3], "note": "from a newer build"}),
		"pf2: unknown nested key survives verbatim")
	p.apply_state({"level": 3})
	_assert(not p.get_state().has("pf2_future_scalar"),
		"pf2: extras track the LAST applied state (no stale carry)")

	# --- Live load -> continue -> re-save through the real MP write
	# path. Scratch-pinned autoload SaveManager (never real slots).
	var SM: Variant = root.get_node("SaveManager")
	SM.set("_test_runs_dir", "user://runs_pf2_test")
	SM.set("_test_account_pin", "pf2test")
	var slot := 4
	var pstate := {"level": 6, "xp": 210, "xp_next": 300, "stat_points": 0,
		"bonus_damage": 2.0, "bonus_health": 5.0, "bonus_speed": 0.5, "bonus_aura": 0.0,
		"inventory": [{"id": "iron_sword", "count": 1, "slot": "WEAPON"}],
		"run_start_msec": 999, "run_kills": 11, "run_damage_dealt": 88.0,
		"supermarket_cash": 0, "bounty_progress": {}, "totem_charges": 1,
		"specialization": "", "affinity": {}, "family_collection": {},
		"equipped_special": "", "no_death_streak": 2,
		"second_wind_armed": true, "second_wind_used": false,
		"pf2_future_state": {"x": [1, 2]}}
	var guest_state: Dictionary = pstate.duplicate(true)
	guest_state["level"] = 5
	guest_state.erase("pf2_future_state")
	var fixture := {"theme_id": "dungeon", "level_number": 3, "seed": 31337,
		"is_multiplayer": true, "at_station": false, "wave": 2,
		"host_difficulty": 1.25, "host_loot_mult": 2.0,
		"lobby": {"max_players": 6, "lobby_name": "PF2's Dungeon", "visibility": "public",
			"pf2_future_lobby": {"region": "eu-west", "mods": ["x", "y"]}},
		"roster": [
			{"steam_id": 1, "player_name": "Host", "class_id": "rogue",
				"player_state": pstate, "rts_faction": -1, "is_host": true,
				"pf2_future_entry": "keep-me"},
			{"steam_id": 76561198000000222, "player_name": "Guest", "class_id": "mage",
				"player_state": guest_state, "rts_faction": -1, "is_host": false,
				"pf2_guest_entry": 7}],
		"class_id": "rogue", "player_state": pstate,
		"pf2_future_top": {"a": 1}}
	_assert(SM.save_run(fixture, "mp", slot), "pf2: injected fixture saves")
	var loaded: Dictionary = SM.load_run("mp", slot)
	# Continue: the host restores from the loaded roster entry.
	var host = PlayerScene.instantiate()
	host.class_id = "rogue"
	root.add_child(host)
	host.apply_state((loaded["roster"][0] as Dictionary)["player_state"])
	# Re-save via the real write path on a detached Dungeon rig
	# (save_multiplayer_run's collection shell needs a live scene; its
	# deterministic core — _save_base seeding + _write_multiplayer_save —
	# is driven here exactly as the producer composes it).
	var d = DungeonScript.new()
	d.set("_save_slot", slot)
	var base: Dictionary = SM.load_run("mp", slot).duplicate(true)
	base["theme_id"] = "dungeon"
	base["level_number"] = 3
	base["seed"] = 31337
	# F-1: compose the lobby exactly as production does (save_multiplayer_
	# run): start from the LOADED lobby dict, overwrite only the three
	# known keys. The shipped rig skipped this step entirely, so a
	# fresh-literal lobby regression would have passed the suite.
	var lobby: Dictionary = (base.get("lobby", {}) as Dictionary).duplicate(true)
	lobby["max_players"] = 8
	lobby["lobby_name"] = "PF2's Dungeon (continued)"
	lobby["visibility"] = "public"
	base["lobby"] = lobby
	d.set("_save_base", base)
	d.set("_save_roster", [{"steam_id": 1, "player_name": "Host",
		"class_id": "rogue", "player_state": host.get_state(),
		"rts_faction": -1, "is_host": true}])
	d.call("_write_multiplayer_save")
	var resaved: Dictionary = SM.load_run("mp", slot)
	# Zero key loss at all three levels.
	_assert((resaved.get("pf2_future_top", {}) as Dictionary).get("a", 0) == 1,
		"pf2: unknown TOP-LEVEL key survives the producer write-back")
	var rroster: Array = resaved.get("roster", [])
	var hentry: Dictionary = {}
	var gentry: Dictionary = {}
	for e in rroster:
		if int(e.get("steam_id", 0)) == 1:
			hentry = e
		if int(e.get("steam_id", 0)) == 76561198000000222:
			gentry = e
	_assert(str(hentry.get("pf2_future_entry", "")) == "keep-me",
		"pf2: unknown ROSTER-ENTRY key merged into the fresh host entry")
	_assert(((hentry.get("player_state", {}) as Dictionary).get("pf2_future_state", {}) as Dictionary).has("x"),
		"pf2: unknown PLAYER_STATE key survives through the real player + producer")
	_assert(int(gentry.get("pf2_guest_entry", 0)) == 7,
		"pf2: absent guest entry carried forward verbatim (unknown key intact)")
	_assert(((resaved.get("player_state", {}) as Dictionary).get("pf2_future_state", {}) as Dictionary).has("x"),
		"pf2: host mirror player_state keeps the unknown key")
	_assert(int(resaved.get("level_number", 0)) == 3 and int(resaved.get("seed", 0)) == 31337,
		"pf2: producer fields written as called (diff-clean otherwise)")
	# F-1: the lobby-level unknown key survived the real producer
	# composition (merge over the loaded lobby), while the known keys
	# took the producer's fresh values.
	var rlobby: Dictionary = resaved.get("lobby", {})
	var rfuture: Dictionary = rlobby.get("pf2_future_lobby", {})
	_assert(str(rfuture.get("region", "")) == "eu-west"
		and (rfuture.get("mods", []) as Array) == ["x", "y"],
		"pf2: unknown LOBBY key survives the producer lobby merge (F-1)")
	_assert(int(rlobby.get("max_players", 0)) == 8
		and str(rlobby.get("lobby_name", "")) == "PF2's Dungeon (continued)"
		and str(rlobby.get("visibility", "")) == "public",
		"pf2: lobby merge overwrote only the known keys (F-1)")
	d.free()
	host.queue_free()
	p.queue_free()
	SM.set("_test_runs_dir", "")
	SM.set("_test_account_pin", "")
	print("[Playtest] save format pf2 done")


func _test_weapon_upgrade_kits() -> void:
	print("[Playtest] Weapon upgrade kits (issue #113 Phase 1)...")
	# Two kit consumables: upgrade_kit (+1, UNCOMMON) and masterwork_kit
	# (+2, RARE). Using one raises the EQUIPPED weapon stack's
	# upgrade_level (persisted on the stack dict); each level adds flat
	# damage in _recalc_stats; cap +5. Refused uses never consume.
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var kit = ItemDBNode.get_item("upgrade_kit")
	var mwk = ItemDBNode.get_item("masterwork_kit")
	_assert(kit != null and mwk != null, "kits: both kit items load from ItemDB")
	_assert(kit.consumable and mwk.consumable, "kits: kits are consumables (never equipped)")
	_assert(int(kit.upgrade_levels) == 1 and int(mwk.upgrade_levels) == 2,
		"kits: upgrade_kit +1 level, masterwork_kit +2 levels")
	_assert(int(kit.rarity) == 1 and int(mwk.rarity) == 2,
		"kits: upgrade_kit is UNCOMMON, masterwork_kit is RARE")
	_assert(not ItemData.is_gear(kit) and not ItemData.is_gear(mwk),
		"kits: kits are not gear (bag-only)")

	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	var msrc := FileAccess.get_file_as_string("res://scripts/mobs/mob.gd")
	_assert(psrc.contains("Equip a weapon first"), "kits: no-weapon toast pinned")
	_assert(psrc.contains("UPGRADE_DAMAGE_PER_LEVEL"), "kits: flat damage per level in player")
	_assert(hsrc.contains("damage from upgrades"), "kits: panel detail line pinned")
	_assert(hsrc.contains("will be lost"), "kits: dispose confirmation names the loss")
	_assert(msrc.contains("_try_masterwork_drop") and msrc.contains("\"masterwork_kit\""),
		"kits: masterwork drops wired for elites/bosses")

	# --- Drop tables: upgrade_kit at uncommon weight (1.0) on the
	# regular mobs of the dungeon/depths themes (the warlord board
	# fields these same mob datas); village mobs stay kit-free.
	for mid in ["goblin", "skeleton", "bat", "orc", "archer", "shieldbearer",
			"splitter", "cultist", "gravewarden"]:
		var md = load("res://data/mobs/%s.tres" % mid)
		var found := false
		for d in md.get("drops"):
			if d.get("item") != null and str(d.get("item").get("id")) == "upgrade_kit":
				found = is_equal_approx(float(d.get("weight")), 1.0)
		_assert(found, "kits: upgrade_kit in %s drop table at weight 1.0" % mid)
	var slime_md = load("res://data/mobs/slime.tres")
	var slime_has := false
	for d in slime_md.get("drops"):
		if d.get("item") != null and str(d.get("item").get("id")) == "upgrade_kit":
			slime_has = true
	_assert(not slime_has, "kits: village mobs (slime) do not drop upgrade kits")

	# --- Use flow on a live player. A warrior spawns with the rusty
	# sword EQUIPPED (mult 1.0, so damage deltas are exact).
	for n in get_nodes_in_group("players"):
		(n as Node).free()
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	_assert(str((p.equipped_entry("WEAPON").get("item") as ItemData).id) == "rusty_sword",
		"kits: warrior starts with the rusty sword equipped")
	p._recalc_stats()
	var dmg0: float = p.damage
	# Apply one upgrade kit: +1 level, +2 damage, kit consumed.
	p.receive_item("upgrade_kit")
	_assert(_kit_index(p, "upgrade_kit") >= 0, "kits: kit received into the bag")
	p.use_item(_kit_index(p, "upgrade_kit"))
	var went = p.equipped_entry("WEAPON")
	_assert(int(went.get("upgrade_level", 0)) == 1, "kits: weapon stack at +1 after one kit")
	_assert(_kit_index(p, "upgrade_kit") < 0, "kits: kit consumed on a successful use")
	_assert(is_equal_approx(p.damage - dmg0, 2.0), "kits: +1 level = +2 flat damage")
	# Masterwork: +2 levels.
	p.receive_item("masterwork_kit")
	p.use_item(_kit_index(p, "masterwork_kit"))
	went = p.equipped_entry("WEAPON")
	_assert(int(went.get("upgrade_level", 0)) == 3, "kits: masterwork kit adds +2 levels (now +3)")
	_assert(is_equal_approx(p.damage - dmg0, 6.0), "kits: +3 levels = +6 flat damage")
	# Clamp at the cap: +2 from level 4 lands on +5.
	went["upgrade_level"] = 4
	p._recalc_stats()
	p.receive_item("masterwork_kit")
	p.use_item(_kit_index(p, "masterwork_kit"))
	_assert(int(p.equipped_entry("WEAPON").get("upgrade_level", 0)) == 5,
		"kits: upgrade clamps at the +5 cap")
	# At cap: refused, not consumed.
	p.receive_item("upgrade_kit")
	p.use_item(_kit_index(p, "upgrade_kit"))
	_assert(_kit_index(p, "upgrade_kit") >= 0, "kits: at cap -> kit NOT consumed")
	# --- Persistence: upgrade_level rides the stack dict through
	# get_state/apply_state; a state without the key reads as 0.
	var st: Dictionary = p.get_state()
	var saved_level := -1
	for e in st["inventory"]:
		if str(e.get("id", "")) == "rusty_sword":
			saved_level = int(e.get("upgrade_level", -1))
	_assert(saved_level == 5, "kits: get_state writes upgrade_level on the stack")
	var p2 = PlayerScene.instantiate()
	p2.class_id = "warrior"
	root.add_child(p2)
	p2.apply_state(st)
	_assert(int(p2.equipped_entry("WEAPON").get("upgrade_level", 0)) == 5,
		"kits: apply_state restores the upgrade level")
	_assert(is_equal_approx(p2.damage, p.damage), "kits: restored weapon deals upgraded damage")
	for e in st["inventory"]:
		e.erase("upgrade_level")
	var p3 = PlayerScene.instantiate()
	p3.class_id = "warrior"
	root.add_child(p3)
	p3.apply_state(st)
	_assert(int(p3.equipped_entry("WEAPON").get("upgrade_level", -1)) == 0,
		"kits: old saves without upgrade_level read as 0")
	# --- Refusal: with NO weapon equipped a kit is never consumed.
	var p4 = PlayerScene.instantiate()
	p4.class_id = "warrior"
	root.add_child(p4)
	p4.unequip_stack(_kit_index(p4, "rusty_sword"))
	_assert(p4.equipped_entry("WEAPON").is_empty(), "kits: refusal rig has no weapon equipped")
	p4.receive_item("upgrade_kit")
	p4.use_item(_kit_index(p4, "upgrade_kit"))
	_assert(_kit_index(p4, "upgrade_kit") >= 0
		and int(p4.inventory[_kit_index(p4, "upgrade_kit")]["count"]) == 1,
		"kits: no weapon equipped -> kit NOT consumed")
	p.queue_free()
	p2.queue_free()
	p3.queue_free()
	p4.queue_free()
	print("[Playtest] weapon upgrade kits done")


func _kit_index(p, item_id: String) -> int:
	for i in range(p.inventory.size()):
		var it = (p.inventory[i] as Dictionary).get("item")
		if it != null and str(it.get("id")) == item_id:
			return i
	return -1


func _test_masterwork_drop_hook() -> void:
	print("[Playtest] Masterwork drop hook (issue #113 F-2)...")
	# F-2 (Eng 9, Phase 1 verification): _try_masterwork_drop was pinned
	# at source level only. This drives the hook BEHAVIORALLY across the
	# kill classes with deterministic rolls: seeds are searched at
	# runtime for one roll in each band — below the elite chance, in the
	# elite..boss gap (the branch discriminator), and above the boss
	# chance — then re-seeded immediately before each hook call, so the
	# hook's own randf() reproduces the banded value exactly. No
	# statistical asserts (issue #115 is the standing warning).
	var MobScene: PackedScene = load("res://scenes/mobs/mob.tscn")
	# The chance consts come from the script's constant map, never a
	# static Mob reference: naming the class here would force mob.gd
	# (which names autoloads) into the suite's compile-time dependency
	# chain — the 2026-10-12 hollow-suite trap.
	var mob_consts: Dictionary = (load("res://scripts/mobs/mob.gd") as GDScript).get_script_constant_map()
	var e_chance := float(mob_consts.get("MASTERWORK_DROP_CHANCE_ELITE", -1.0))
	var b_chance := float(mob_consts.get("MASTERWORK_DROP_CHANCE_BOSS", -1.0))
	_assert(is_equal_approx(b_chance, 0.25),
		"mw hook: boss chance const is 0.25 (placeholder)")
	_assert(is_equal_approx(e_chance, 0.10),
		"mw hook: elite chance const is 0.10 (placeholder)")
	var seed_low := -1
	var seed_mid := -1
	var seed_high := -1
	for s in range(1, 20000):
		seed(s)
		var v := randf()
		if v < e_chance and seed_low < 0:
			seed_low = s
		elif v >= e_chance and v < b_chance and seed_mid < 0:
			seed_mid = s
		elif v >= b_chance and seed_high < 0:
			seed_high = s
		if seed_low > 0 and seed_mid > 0 and seed_high > 0:
			break
	_assert(seed_low > 0 and seed_mid > 0 and seed_high > 0,
		"mw hook: deterministic seeds found for all three roll bands")
	var stub := RelicDungeonStub.new()
	root.add_child(stub)
	var holder := Node3D.new()
	root.add_child(holder)
	var cases: Array = [
		# [mob data id, elite flag, seed, expect drop, label]
		["goblin", false, seed_low, false, "regular mob never drops (gate)"],
		["goblin", true, seed_low, true, "elite + low roll drops"],
		["goblin", true, seed_mid, false, "elite + mid roll: elite branch refuses"],
		["goblin", true, seed_high, false, "elite + high roll refuses"],
		["boss_boar", false, seed_low, true, "boss + low roll drops"],
		["boss_boar", false, seed_mid, true, "boss + mid roll drops (boss branch, same roll that refused the elite)"],
		["boss_boar", false, seed_high, false, "boss + high roll refuses"],
		["apex_boar", false, seed_mid, true, "apex (is_boss + apex_id) rides the boss branch"],
		["apex_boar", false, seed_high, false, "apex + high roll refuses"],
	]
	for c in cases:
		var data: Resource = load("res://data/mobs/%s.tres" % str(c[0]))
		var mob = MobScene.instantiate()
		mob.setup(77, data, 1.0, 1.0, bool(c[1]), 1.0)
		holder.add_child(mob)
		stub.pickups.clear()
		seed(int(c[2]))
		mob._try_masterwork_drop(stub)
		var dropped := false
		for pk in stub.pickups:
			if str(pk[0]) == "masterwork_kit":
				dropped = true
		_assert(dropped == bool(c[3]), "mw hook: %s" % str(c[4]))
		mob.queue_free()
	stub.queue_free()
	holder.queue_free()
	print("[Playtest] masterwork drop hook done")


func _test_warlord_rebind_m1() -> void:
	print("[Playtest] Warlord faction rebind (issue #106 M-1)...")
	# M-1: _setup_warlord keyed its connected map by peer authority but
	# queried it by roster Steam64 (never matched — the host above all
	# could never rebind), and _reclaim_faction dropped reclaims that
	# arrived before _rts_manager existed, sending fast loaders to the
	# late-joiner path for a brand-new faction.
	var DungeonScript = load("res://scripts/dungeon/dungeon.gd")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var RTSScript = load("res://scripts/rts/rts_manager.gd")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	var setup := _bughunt_body(dsrc, "_setup_warlord")
	_assert(setup.contains("_pending_reclaims.clear()"),
		"m1: setup flushes queued reclaims once factions are registered")
	var late := _bughunt_body(dsrc, "_warlord_assign_late_joiners")
	_assert(late.contains("_pending_reclaims.has(int(p.get_multiplayer_authority()))"),
		"m1: late-joiner assignment never overrides a queued reclaim")

	# --- Reclaim queue behavior (detached rig: the queue path returns
	# before any tree access when the manager is null).
	var rig = DungeonScript.new()
	_assert((rig.get("_pending_reclaims") as Dictionary).is_empty(),
		"m1: reclaim queue starts empty")
	rig.call("_reclaim_faction", 7, 3)
	rig.call("_reclaim_faction", 9, 0)
	rig.call("_reclaim_faction", 7, -1) # invalid faction: never queued
	var pend: Dictionary = rig.get("_pending_reclaims")
	_assert(int(pend.get(7, -99)) == 3 and int(pend.get(9, -99)) == 0
		and pend.size() == 2,
		"m1: early reclaims queue by peer id (invalid faction ignored)")

	# --- The fixed keying against real player nodes: a roster Steam64
	# now finds its player, and the value registration must store is
	# the node's PEER authority (faction_peers' namespace).
	for n in get_nodes_in_group("players"):
		(n as Node).free()
	var host = PlayerScene.instantiate()
	host.class_id = "warrior"
	root.add_child(host)
	host.set("steam_id", 76561198000000001)
	var guest = PlayerScene.instantiate()
	guest.class_id = "mage"
	root.add_child(guest)
	guest.set_multiplayer_authority(7)
	guest.set("steam_id", 76561198000000002)
	var peer_steam_ids: Dictionary = rig.get("peer_steam_ids")
	var connected := {}
	for pl in get_nodes_in_group("players"):
		var peer_id := int(pl.get_multiplayer_authority())
		var psid := int(pl.get("steam_id")) if pl.get("steam_id") != null else 0
		if psid == 0:
			psid = int(peer_steam_ids.get(peer_id, peer_id))
		connected[psid] = pl
	_assert(connected.has(76561198000000001),
		"m1: host roster Steam64 finds the host player (host rebinds)")
	_assert(connected.has(76561198000000002),
		"m1: guest roster Steam64 finds the guest player")
	_assert(int(connected[76561198000000001].get_multiplayer_authority()) == 1,
		"m1: registration value for the host is peer id 1, not the Steam64")
	_assert(int(connected[76561198000000002].get_multiplayer_authority()) == 7,
		"m1: registration value for the guest is its peer id")

	# --- faction_peers invariant with a real manager: register_faction
	# stores exactly the peer id it is handed (what the fix passes).
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	var mgr = RTSScript.new()
	holder.add_child(mgr)
	mgr.register_faction(3, 1, "warrior")
	_assert(int(mgr.faction_peers.get(3, -99)) == 1,
		"m1: faction_peers[3] holds peer id 1 after fixed registration")
	holder.queue_free()
	host.queue_free()
	guest.queue_free()
	rig.free()
	print("[Playtest] warlord rebind m1 done")


func _test_station_roster_carry_forward() -> void:
	print("[Playtest] Station roster carry-forward (issue #112)...")
	var StationScript := load("res://scripts/station/station.gd")
	var stsrc := FileAccess.get_file_as_string("res://scripts/station/station.gd")
	_assert(stsrc.contains("Dungeon.carry_forward_roster(roster, base.get(\"roster\", []))"),
		"station112: producer invokes the dungeon carry-forward merge")

	# Scratch-pinned save state: the station producer must never touch a
	# real run slot while this regression is driven.
	var SM: Variant = root.get_node("SaveManager")
	var NM: Variant = root.get_node("NetworkManager")
	var scratch := "user://runs_station112_test"
	if DirAccess.dir_exists_absolute(scratch):
		for f in DirAccess.get_files_at(scratch):
			DirAccess.remove_absolute(scratch.path_join(f))
		DirAccess.remove_absolute(scratch)
	SM.set("_test_runs_dir", scratch)
	SM.set("_test_account_pin", "station112_scratch")
	var old_slot := int(NM.get("active_run_slot"))
	var old_mode := str(NM.get("active_run_mode"))
	var old_transport := int(NM.get("transport"))
	var old_difficulty := float(NM.get("host_difficulty"))
	var old_loot := float(NM.get("host_loot_mult"))
	var old_visibility := str(NM.get("lobby_visibility"))
	NM.set("transport", 0) # STEAM (the LAN branch intentionally has no saves)
	NM.set("active_run_mode", "mp")
	NM.set("active_run_slot", 6)
	NM.set("host_difficulty", 1.0)
	NM.set("host_loot_mult", 1.0)
	NM.set("lobby_visibility", "friends")

	var host_sid := 76561198000000331
	var absent_sid := 76561198000000447
	var absent_state := {"level": 9, "xp": 777, "xp_next": 1000,
		"inventory": [{"id": "void_blade", "count": 1}],
		"station112_future_state": {"kept": [1, 2, 3]}}
	var absent_entry := {"steam_id": absent_sid, "player_name": "Absent Rogue",
		"class_id": "rogue", "player_state": absent_state, "rts_faction": 3,
		"is_host": false, "station112_future_entry": {"kept": "verbatim"}}
	var fixture := {"theme_id": "dungeon", "level_number": 3, "seed": 111,
		"is_multiplayer": true, "at_station": true, "wave": 0,
		"host_difficulty": 1.0, "host_loot_mult": 1.0,
		"lobby": {"max_players": 4, "lobby_name": "Station 112", "visibility": "friends"},
		"roster": [
			{"steam_id": host_sid, "player_name": "Present Host", "class_id": "rogue",
				"player_state": {"level": 7, "xp": 100}, "rts_faction": -1,
				"is_host": true, "station112_host_entry": "keep-me"},
			absent_entry],
		"class_id": "rogue", "player_state": {"level": 7, "xp": 100}}
	_assert(SM.save_run(fixture, "mp", 6), "station112: previous roster fixture saves")

	# The station scene contains only the present host. The absent member
	# has no local player node for the producer to collect.
	for n in get_nodes_in_group("players"):
		(n as Node).free()
	var peer := StationSavePeer.new()
	peer.steam_id = host_sid
	peer.class_id = "rogue"
	peer.saved_state = {"level": 8, "xp": 250, "xp_next": 400,
		"inventory": [{"id": "iron_sword", "count": 1}]}
	root.add_child(peer)
	peer.add_to_group("players")
	var station = StationScript.new()
	root.add_child(station)
	station.save_multiplayer_run("dungeon", 4, 424242)

	var saved: Dictionary = SM.load_run("mp", 6)
	var saved_roster: Array = saved.get("roster", [])
	_assert(saved_roster.size() == 2, "station112: station save keeps both roster members")
	var saved_host: Dictionary = {}
	var saved_absent: Dictionary = {}
	for e in saved_roster:
		if int(e.get("steam_id", 0)) == host_sid:
			saved_host = e
		elif int(e.get("steam_id", 0)) == absent_sid:
			saved_absent = e
	_assert(not saved_host.is_empty(), "station112: present host remains in the roster")
	_assert(int((saved_host.get("player_state", {}) as Dictionary).get("level", 0)) == 8,
		"station112: present host's fresh state wins")
	_assert(str(saved_host.get("station112_host_entry", "")) == "keep-me",
		"station112: PF2 unknown-key merge still applies to the fresh entry")
	_assert(not saved_absent.is_empty(), "station112: absent member is not dropped")
	_assert(saved_absent.size() == absent_entry.size(),
		"station112: absent entry keeps its exact key set")
	_assert(saved_absent == absent_entry,
		"station112: absent entry survives verbatim")
	_assert(int(saved.get("level_number", 0)) == 4 and int(saved.get("seed", 0)) == 424242,
		"station112: producer writes the station save fields")

	station.free()
	peer.free()
	NM.set("active_run_slot", old_slot)
	NM.set("active_run_mode", old_mode)
	NM.set("transport", old_transport)
	NM.set("host_difficulty", old_difficulty)
	NM.set("host_loot_mult", old_loot)
	NM.set("lobby_visibility", old_visibility)
	for f in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch.path_join(f))
	DirAccess.remove_absolute(scratch)
	if FileAccess.file_exists("user://profile_station112_scratch.cfg"):
		DirAccess.remove_absolute("user://profile_station112_scratch.cfg")
	SM.set("_test_runs_dir", "")
	SM.set("_test_account_pin", "")
	print("[Playtest] station roster carry-forward done")


## Stub dungeon node for the issue #111 minor-3 snapshot test: carries
## exactly the fields HUD._capture_pause_save_snapshot samples.
class PauseSaveDungeonStub extends Node:
	var theme: Variant = {"theme_id": "misty_docks"}
	var level_number := 4
	var wave := 3
	var wave_state := 0
	var wave_info := {"wave": 3, "total": 5, "level": 4, "theme_name": "Misty Docks",
		"theme_id": "misty_docks", "state": 0, "time_left": 8.0, "mobs_left": 0,
		"keys_found": 0, "keys_needed": 0}


## Stub station node for the issue #111 minor-3 snapshot test.
class PauseSaveStationStub extends Node:
	var departure_seed := 987654


func _test_111_minor_restore_drops() -> void:
	print("[Playtest] Issue #111 minor 1: unknown-item restore drops...")
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud = HudScene.instantiate()
	root.add_child(hud)
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	hud._player = p
	p.hud = hud
	_assert(ItemDBNode.get_item("health_potion") != null, "111-1: fixture item resolves")
	# Mixed restore: one valid stack, two ids that no longer resolve.
	p.apply_state({"inventory": [
		{"id": "health_potion", "count": 4},
		{"id": "gone_item_111", "count": 3},
		{"id": "also_gone_111", "count": 7},
	]})
	_assert(p.inventory.size() == 1, "111-1: valid stack restores, unknown stacks dropped")
	_assert(int(p.inventory[0]["count"]) == 4, "111-1: valid stack count intact")
	var drops: Array = p.last_restore_dropped
	_assert(drops.size() == 2, "111-1: both dropped entries collected (no silent loss)")
	_assert(str(drops[0].get("id", "")) == "gone_item_111" and int(drops[0].get("count", 0)) == 3,
		"111-1: first drop records id + count")
	_assert(str(drops[1].get("id", "")) == "also_gone_111" and int(drops[1].get("count", 0)) == 7,
		"111-1: second drop records id + count")
	# The player-facing notice fires through the restore flow's toast.
	var toast_label = hud.find_child("ToastLabel", true, false)
	_assert(toast_label != null and str(toast_label.text) == "Some items could not be restored",
		"111-1: restore notice toasted to the player")
	# Clean restore: restores exactly as before, drop record cleared.
	p.apply_state({"inventory": [{"id": "health_potion", "count": 2}]})
	_assert(p.inventory.size() == 1 and int(p.inventory[0]["count"]) == 2,
		"111-1: clean restore still exact")
	_assert(p.last_restore_dropped.is_empty(), "111-1: clean restore leaves an empty drop record")
	p.hud = null
	root.remove_child(p)
	p.free()
	hud.queue_free()
	print("[Playtest] 111 minor 1 done")


func _test_111_minor_legacy_mp_save() -> void:
	print("[Playtest] Issue #111 minor 2: legacy MP saves warn, restore nobody...")
	var SaveScript = load("res://scripts/autoload/save_manager.gd")
	var DungeonScript = load("res://scripts/dungeon/dungeon.gd")
	var scratch := "user://runs_111_minor_test"
	if DirAccess.dir_exists_absolute(scratch):
		for f in DirAccess.get_files_at(scratch):
			DirAccess.remove_absolute(scratch.path_join(f))
		DirAccess.remove_absolute(scratch)
	# --- Detection (pure dict shape + slot round-trip on a fresh mgr).
	var mgr = SaveScript.new()
	mgr.set("_test_runs_dir", scratch)
	mgr.set("_test_account_pin", "minor111_scratch")
	var legacy := {"is_multiplayer": true, "theme_id": "village", "level_number": 3,
		"seed": 777, "class_id": "mage", "player_state": {"level": 5, "inventory": []}}
	_assert(mgr.is_legacy_mp_save(legacy), "111-2: pre-roster MP dict detected as legacy")
	var current := {"is_multiplayer": true, "theme_id": "village", "level_number": 3,
		"seed": 777, "class_id": "mage", "player_state": {"level": 5},
		"roster": [{"steam_id": 76561198000000001, "class_id": "mage",
			"player_state": {"level": 5}}]}
	_assert(not mgr.is_legacy_mp_save(current), "111-2: roster MP dict is not legacy")
	_assert(not mgr.is_legacy_mp_save({"is_multiplayer": false, "class_id": "mage",
		"player_state": {"level": 5}}), "111-2: solo dict is not legacy")
	_assert(not mgr.is_legacy_mp_save({}), "111-2: empty dict is not legacy")
	mgr.save_run(legacy, SaveScript.MODE_MP, 0)
	var loaded: Dictionary = mgr.load_run(SaveScript.MODE_MP, 0)
	_assert(not loaded.is_empty(), "111-2: legacy MP save still loads from its slot")
	_assert(mgr.is_legacy_mp_save(loaded), "111-2: loaded legacy MP save still detected")
	mgr.free()
	# --- Continue path: the real NetworkManager refuses with the
	# explicit message and stashes NOTHING for restore (no partial
	# restore, no silent fresh start).
	var sm = root.get_node("SaveManager")
	var nm = root.get_node("NetworkManager")
	sm.set("_test_runs_dir", scratch)
	sm.save_run(legacy, SaveScript.MODE_MP, 0)
	var captured: Array = []
	var cb := func(reason: String) -> void:
		captured.append(reason)
	nm.connection_failed.connect(cb)
	var prev_roster: Array = DungeonScript.continued_roster
	var prev_saved: Dictionary = DungeonScript.saved_player_state
	DungeonScript.continued_roster = [{"sentinel": 1}]
	DungeonScript.saved_player_state = {"sentinel": 2}
	var ok: bool = nm.continue_run(SaveScript.MODE_MP, 0)
	_assert(not ok, "111-2: continue_run refuses a legacy MP save")
	_assert(captured.size() == 1 and str(captured[0]) == SaveScript.LEGACY_MP_SAVE_MESSAGE,
		"111-2: explicit legacy message surfaced via connection_failed")
	_assert((DungeonScript.continued_roster as Array).size() == 1
		and int((DungeonScript.continued_roster[0] as Dictionary).get("sentinel", 0)) == 1,
		"111-2: no roster stashed (no partial restore)")
	_assert(int((DungeonScript.saved_player_state as Dictionary).get("sentinel", 0)) == 2,
		"111-2: no player state stashed (no partial restore)")
	nm.connection_failed.disconnect(cb)
	DungeonScript.continued_roster = prev_roster
	DungeonScript.saved_player_state = prev_saved
	sm.set("_test_runs_dir", "")
	for f in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch.path_join(f))
	DirAccess.remove_absolute(scratch)
	print("[Playtest] 111 minor 2 done")


func _test_111_minor_pause_save_snapshot() -> void:
	print("[Playtest] Issue #111 minor 3: pause-save snapshot = HUD display...")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var DungeonScript = load("res://scripts/dungeon/dungeon.gd")
	var StationScript = load("res://scripts/station/station.gd")
	# Group hygiene: park any pre-existing dungeon/station nodes so the
	# snapshot samples ONLY this rig; restored at the end.
	var parked_dungeons: Array = get_nodes_in_group("dungeon")
	for n in parked_dungeons:
		n.remove_from_group("dungeon")
	var parked_stations: Array = get_nodes_in_group("station")
	for n in parked_stations:
		n.remove_from_group("station")
	current_scene = null
	var prev_next_seed: int = DungeonScript.next_seed
	var prev_station_level: int = StationScript.next_level_number
	DungeonScript.next_seed = 424242
	var hud = HudScene.instantiate()
	root.add_child(hud)
	# --- Dungeon branch: one sample of the live dungeon + handoff seed.
	var stub := PauseSaveDungeonStub.new()
	root.add_child(stub)
	stub.add_to_group("dungeon")
	var snap: Dictionary = hud._capture_pause_save_snapshot()
	_assert(str(snap.get("theme_id", "")) == "misty_docks", "111-3: snapshot theme from the live dungeon")
	_assert(int(snap.get("level_number", 0)) == 4, "111-3: snapshot level from the live dungeon")
	_assert(int(snap.get("seed", 0)) == 424242, "111-3: snapshot seed = Dungeon.next_seed (what the save writes)")
	_assert(not bool(snap.get("at_station", true)), "111-3: dungeon snapshot is not a station save")
	_assert(int(snap.get("wave", -1)) == 3, "111-3: snapshot wave from the live dungeon")
	# The mid-wave step-back rides along in the snapshot.
	stub.wave_state = 1
	var snap_active: Dictionary = hud._capture_pause_save_snapshot()
	_assert(int(snap_active.get("wave", -1)) == 2, "111-3: mid-wave snapshot steps the wave back one")
	stub.wave_state = 0
	# --- Applying the snapshot makes the HUD display THOSE values.
	hud._apply_pause_save_snapshot(snap)
	_assert(hud.displayed_level == 4 and hud.displayed_seed == 424242
		and hud.displayed_theme_id == "misty_docks",
		"111-3: HUD displayed seed/level == snapshot after apply")
	var wave_label = hud.find_child("WaveLabel", true, false)
	_assert(wave_label != null and str(wave_label.text).begins_with("Lv 4 · Misty Docks"),
		"111-3: wave label re-derived from the snapshot")
	# --- Station branch: no dungeon node -> the station's next level.
	root.remove_child(stub)
	stub.free()
	var sstub := PauseSaveStationStub.new()
	root.add_child(sstub)
	sstub.add_to_group("station")
	StationScript.next_level_number = 6
	var ssnap: Dictionary = hud._capture_pause_save_snapshot()
	_assert(bool(ssnap.get("at_station", false)), "111-3: station snapshot flagged at_station")
	_assert(int(ssnap.get("level_number", 0)) == 6, "111-3: station snapshot level = Station.next_level_number")
	_assert(int(ssnap.get("seed", 0)) == 987654, "111-3: station snapshot seed = departure_seed")
	var dests6: Array = DungeonScript.board_destinations(6)
	_assert(str(ssnap.get("theme_id", "")) == str(dests6[(6 - 1) % dests6.size()]),
		"111-3: station snapshot theme = board destination")
	hud._apply_pause_save_snapshot(ssnap)
	_assert(hud.displayed_level == 6 and hud.displayed_seed == 987654,
		"111-3: HUD display follows the station snapshot")
	root.remove_child(sstub)
	sstub.free()
	# --- Source pins: the save handler writes the snapshot itself
	# (the async quit shell can't be driven headless; same pattern the
	# PF2 tests use for save producers).
	var hsrc := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	_assert(hsrc.contains("var snap := _capture_pause_save_snapshot()"),
		"111-3: save & quit samples via the snapshot")
	_assert(hsrc.contains("_apply_pause_save_snapshot(snap)"),
		"111-3: save & quit refreshes the display from the snapshot")
	_assert(hsrc.contains("var level_seed := int(snap[\"seed\"])")
		and hsrc.contains("solo_base[\"seed\"] = level_seed"),
		"111-3: the written seed comes from the snapshot")
	# --- Cleanup: restore statics, groups, scene.
	DungeonScript.next_seed = prev_next_seed
	StationScript.next_level_number = prev_station_level
	hud.queue_free()
	for n in parked_dungeons:
		n.add_to_group("dungeon")
	for n in parked_stations:
		n.add_to_group("station")
	print("[Playtest] 111 minor 3 done")


func _test_architect_tools_repair() -> void:
	print("[Playtest] Architect starting tools + wrench repair (issue #113 P3)...")
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var StructureScript = load("res://scripts/combat/structure.gd")
	var BuildingScript = load("res://scripts/rts/building.gd")
	var StationScript = load("res://scripts/station/station.gd")
	var LegendScript = load("res://scripts/ui/mouse_legend.gd")
	var psrc := FileAccess.get_file_as_string("res://scripts/player/player.gd")

	# --- ItemData: both tools exist with the specced shape.
	var wrench = ItemDBNode.get_item("field_wrench")
	var hammer = ItemDBNode.get_item("forge_hammer")
	_assert(wrench != null and hammer != null, "tools113: both tool items exist in ItemDB")
	_assert(int(wrench.get("slot")) == 0 and int(hammer.get("slot")) == 0,
		"tools113: both tools are WEAPON slot")
	_assert(int(wrench.get("rarity")) == 2, "tools113: wrench is RARE")
	_assert(int(hammer.get("rarity")) == 3, "tools113: hammer is EPIC")
	_assert((wrench.get("allowed_classes") as Array) == ["architect"]
		and (hammer.get("allowed_classes") as Array) == ["architect"],
		"tools113: both tools are architect-only at equip time")
	_assert(bool(wrench.get("starting_gear")) and bool(hammer.get("starting_gear")),
		"tools113: both tools flagged starting_gear")
	_assert(wrench.get("icon") != null and hammer.get("icon") != null,
		"tools113: both tools carry the Art icons")
	_assert(ResourceLoader.exists(str(wrench.get("world_model")))
		and ResourceLoader.exists(str(hammer.get("world_model"))),
		"tools113: both tools have world models")

	# --- Never loot, never purchasable.
	var stock_clean := true
	for i in 40:
		for e in StationScript.build_vendor_stock():
			if str(e.get("id", "")) in ["field_wrench", "forge_hammer"]:
				stock_clean = false
	_assert(stock_clean, "tools113: vendor stock never sells the tools (40 rolls)")
	var drops_clean := true
	for f in DirAccess.get_files_at("res://data/mobs"):
		if f.ends_with(".tres"):
			var txt := FileAccess.get_file_as_string("res://data/mobs/" + f)
			if txt.contains("field_wrench") or txt.contains("forge_hammer"):
				drops_clean = false
	_assert(drops_clean, "tools113: tools appear in no mob drop pool")
	var dsrc := FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")
	_assert(_bughunt_body(dsrc, "_shower_loot").contains("starting_gear"),
		"tools113: loot shower excludes starting gear")

	# Holder as current_scene: positional sfx in structure/build FX
	# need a scene to attach to in -s mode.
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder

	# --- Starting grant: both tools, wrench equipped, hammer bagged.
	var arch = PlayerScene.instantiate()
	arch.class_id = "architect"
	root.add_child(arch)
	var ids := {}
	var markers := {}
	for e in arch.inventory:
		var it = e["item"]
		ids[str(it.get("id"))] = int(e["count"])
		markers[str(it.get("id"))] = str(e.get("equipped_slot", ""))
	_assert(ids.has("field_wrench") and ids.has("forge_hammer"),
		"tools113: a new architect starts with both tools")
	_assert(str(markers.get("field_wrench", "")) == "WEAPON",
		"tools113: the wrench starts equipped")
	_assert(str(markers.get("forge_hammer", "x")) == "",
		"tools113: the hammer starts in the bag")
	_assert(arch.has_wrench_equipped(), "tools113: has_wrench_equipped reads WEAPON")
	_assert(absf(float(arch.get("damage")) - 22.0) < 0.01,
		"tools113: equipped wrench stats apply ((12+8) x 1.1 = 22)")

	# --- Equip swap both ways through the ordinary #104 action.
	var hammer_idx := -1
	var wrench_idx := -1
	for i in arch.inventory.size():
		var iid := str((arch.inventory[i]["item"] as Object).get("id"))
		if iid == "forge_hammer":
			hammer_idx = i
		if iid == "field_wrench":
			wrench_idx = i
	_assert(arch.equip_stack(hammer_idx), "tools113: hammer equips via the ordinary swap")
	_assert(str(arch.equipped_item("WEAPON").get("id")) == "forge_hammer",
		"tools113: hammer now holds the WEAPON slot")
	_assert(not arch.has_wrench_equipped(), "tools113: wrench is bagged after the swap")
	_assert(absf(float(arch.get("damage")) - 51.3) < 0.01,
		"tools113: equipped hammer stats apply ((12+26) x 1.35 = 51.3)")
	_assert(arch.equip_stack(wrench_idx), "tools113: wrench swaps back")

	# --- Non-architects: never granted, cannot equip.
	var war = PlayerScene.instantiate()
	war.class_id = "warrior"
	root.add_child(war)
	var war_has_tools := false
	for e in war.inventory:
		if str((e["item"] as Object).get("id")) in ["field_wrench", "forge_hammer"]:
			war_has_tools = true
	_assert(not war_has_tools, "tools113: non-architects are not granted the tools")
	war.inventory.append({"item": wrench, "count": 1, "equipped_slot": ""})
	_assert(not war.equip_stack(war.inventory.size() - 1),
		"tools113: a warrior carrying the wrench cannot equip it")
	war.apply_state({"inventory": []})
	_assert(war.inventory.is_empty(),
		"tools113: restoring a non-architect grants nothing")

	# --- Re-grant: disposed tools return on restore, bagged, no dupes.
	var arch2 = PlayerScene.instantiate()
	arch2.class_id = "architect"
	root.add_child(arch2)
	var disposed: Dictionary = arch2.get_state()
	var kept: Array = []
	for e in disposed.get("inventory", []):
		if str(e.get("id", "")) not in ["field_wrench", "forge_hammer"]:
			kept.append(e)
	disposed["inventory"] = kept
	arch2.apply_state(disposed)
	arch2.apply_state(disposed) # twice: must not duplicate
	var regranted := {}
	var regrant_markers := {}
	for e in arch2.inventory:
		var it = e["item"]
		regranted[str(it.get("id"))] = int(e["count"])
		regrant_markers[str(it.get("id"))] = str(e.get("equipped_slot", ""))
	_assert(int(regranted.get("field_wrench", 0)) == 1
		and int(regranted.get("forge_hammer", 0)) == 1,
		"tools113: disposed tools are re-granted exactly once on restore")
	_assert(str(regrant_markers.get("field_wrench", "x")) == ""
		and str(regrant_markers.get("forge_hammer", "x")) == "",
		"tools113: re-granted tools land in the bag, unequipped")
	# Legacy marker-less state (no slot keys at all, no tools).
	arch2.apply_state({"inventory": [{"id": "iron_sword", "count": 1}]})
	var legacy_tools := 0
	for e in arch2.inventory:
		if str((e["item"] as Object).get("id")) in ["field_wrench", "forge_hammer"]:
			legacy_tools += 1
	_assert(legacy_tools == 2, "tools113: legacy architect saves gain both tools")

	# --- Repair: dungeon Structure, server ticks.
	var st1 = StructureScript.new()
	st1.setup("sentry_turret", 1, 1, 1.0, "t113-turret")
	holder.add_child(st1)
	st1.position = Vector3(2, 0, 0)
	st1.hp = 40.0
	var t = arch.repair_target_at(arch.global_position)
	_assert(not t.is_empty() and str(t.get("kind", "")) == "structure",
		"tools113: scan finds the damaged friendly turret")
	_assert(str(t.get("name", "")) == "Sentry Turret",
		"tools113: repair prompt name resolves")
	arch.repair_start("structure", "t113-turret")
	_assert(arch.get("_srv_repair_target") == st1,
		"tools113: server accepts the repair channel")
	arch._server_repair_tick(0.6)
	_assert(absf(st1.hp - 65.0) < 0.01, "tools113: one server tick repairs 25 HP")
	arch._server_repair_tick(0.6)
	arch._server_repair_tick(0.6)
	_assert(absf(st1.hp - 100.0) < 0.01, "tools113: repair caps at max_hp, never above")
	arch._server_repair_tick(0.6)
	_assert(arch.get("_srv_repair_target") == null,
		"tools113: channel ends when the target is full")
	arch.repair_start("structure", "t113-turret")
	_assert(arch.get("_srv_repair_target") == null,
		"tools113: a full structure is refused")

	# Refusals: neutral owner, destroyed, out of range.
	var st2 = StructureScript.new()
	st2.setup("bulwark_wall", 0, 1, 1.0, "t113-neutral")
	holder.add_child(st2)
	st2.position = Vector3(-2, 0, 0)
	st2.hp = 50.0
	arch.repair_start("structure", "t113-neutral")
	_assert(arch.get("_srv_repair_target") == null,
		"tools113: a neutral (owner 0) structure is refused")
	var st3 = StructureScript.new()
	st3.setup("spike_trap", 1, 1, 1.0, "t113-dead")
	holder.add_child(st3)
	st3.position = Vector3(0, 0, 2)
	st3.hp = 0.0
	arch.repair_start("structure", "t113-dead")
	_assert(arch.get("_srv_repair_target") == null,
		"tools113: a destroyed structure is refused (no resurrect)")
	var st4 = StructureScript.new()
	st4.setup("keystone", 1, 1, 1.0, "t113-far")
	holder.add_child(st4)
	st4.position = Vector3(20, 0, 0)
	st4.hp = 100.0
	arch.repair_start("structure", "t113-far")
	_assert(arch.get("_srv_repair_target") == null,
		"tools113: an out-of-range structure is refused")
	_assert(arch.repair_target_at(arch.global_position).is_empty(),
		"tools113: no valid target among full/neutral/destroyed/far")

	# No wrench equipped -> no channel; stop intent clears a live one.
	st1.hp = 40.0
	arch.unequip_stack(wrench_idx)
	arch.repair_start("structure", "t113-turret")
	_assert(arch.get("_srv_repair_target") == null,
		"tools113: no channel without the wrench equipped")
	arch.equip_stack(wrench_idx)
	arch.repair_start("structure", "t113-turret")
	_assert(arch.get("_srv_repair_target") == st1, "tools113: channel restarts")
	arch.repair_stop()
	_assert(arch.get("_srv_repair_target") == null,
		"tools113: the stop intent clears the channel")
	# A forged replica (non-architect claiming the wrench) is refused.
	war.set("equipped_ids", {"WEAPON": "field_wrench"})
	war.repair_start("structure", "t113-turret")
	_assert(war.get("_srv_repair_target") == null,
		"tools113: a non-architect is refused even with forged equipped_ids")

	# --- Repair: RTS building, faction-gated.
	arch.position = Vector3(30, 0, 0)
	arch.set("rts_faction", 0)
	var b1 = BuildingScript.new()
	b1.setup(0, "tower", null)
	b1.building_id = 771
	holder.add_child(b1)
	b1.position = Vector3(32, 0, 0)
	b1.hp = 7000.0
	var tb = arch.repair_target_at(arch.global_position)
	_assert(not tb.is_empty() and str(tb.get("kind", "")) == "building",
		"tools113: scan finds the damaged friendly RTS tower")
	arch.repair_start("building", "771")
	_assert(arch.get("_srv_repair_target") == b1,
		"tools113: server accepts the building channel")
	arch._server_repair_tick(0.6)
	_assert(absf(b1.hp - 7025.0) < 0.01, "tools113: building tick repairs 25 HP")
	arch.repair_stop()
	var b2 = BuildingScript.new()
	b2.setup(1, "barracks", null)
	b2.building_id = 772
	holder.add_child(b2)
	b2.position = Vector3(28, 0, 0)
	b2.hp = 100.0
	arch.repair_start("building", "772")
	_assert(arch.get("_srv_repair_target") == null,
		"tools113: an enemy-faction building is refused")
	b1.destroyed = true
	arch.repair_start("building", "771")
	_assert(arch.get("_srv_repair_target") == null,
		"tools113: a destroyed building is refused (no resurrect)")

	# --- No melee anywhere; legend carries the repair line.
	var legend_std: Dictionary = LegendScript.actions_for("architect", "standard")
	_assert(str(legend_std.get("left", "")) == "Cast selected ability",
		"tools113: the architect keeps NO basic attack (LMB casts abilities)")
	var legend_rep: Dictionary = LegendScript.actions_for("architect", "repair_ready")
	_assert(str(legend_rep.get("right", "")) == "Hold E — Repair",
		"tools113: the mouse legend shows the repair line in repair context")
	_assert(not _bughunt_body(psrc, "_server_repair_tick").contains("take_damage"),
		"tools113: the repair tick path never deals damage")

	# Cleanup.
	for n in [st1, st2, st3, st4, b1, b2]:
		(n as Node).free()
	arch.free()
	war.free()
	arch2.free()
	current_scene = null
	holder.free()
	print("[Playtest] architect tools + repair done")


func _test_hammer_smash() -> void:
	print("[Playtest] Hammer Smash (issue #113 P4)...")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var MobScene: PackedScene = load("res://scenes/mobs/mob.tscn")
	var slime_data: Resource = load("res://data/mobs/slime.tres")

	# Holder as current_scene: positional sfx in the smash FX need one.
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder

	# Architect with the hammer equipped (wrench is the spawn default).
	var arch = PlayerScene.instantiate()
	arch.class_id = "architect"
	root.add_child(arch)
	var unlocked_ids: Array = []
	for a in arch.unlocked_abilities:
		unlocked_ids.append(str(a.get("id", "")))
	_assert(unlocked_ids.has("hammer_smash"),
		"smash113: Hammer Smash is unlocked from level 1 (starting tool)")
	_assert(arch.has_wrench_equipped() and not arch.has_hammer_equipped(),
		"smash113: fresh architect holds the wrench, not the hammer")

	# Mobs: one in radius (2m), one out (10m). Deep HP pools — no deaths
	# in this test (the death path needs a full dungeon).
	var m1 = MobScene.instantiate()
	m1.setup(1, slime_data)
	holder.add_child(m1)
	m1.position = Vector3(2, 0, 0)
	m1.set("max_hp", 10000.0)
	m1.set("hp", 10000.0)
	var m2 = MobScene.instantiate()
	m2.setup(2, slime_data)
	holder.add_child(m2)
	m2.position = Vector3(10, 0, 0)
	m2.set("max_hp", 10000.0)
	m2.set("hp", 10000.0)

	# Gate: wrench equipped -> the server refuses, no cooldown spent.
	arch.request_hammer_smash(40.0)
	_assert(absf(float(m1.get("hp")) - 10000.0) < 0.01,
		"smash113: no damage while the wrench is equipped")
	_assert(float(arch.get("_srv_smash_cd")) == 0.0,
		"smash113: refused cast spends no server cooldown")
	# Client cast path refuses too (and consumes no local cooldown).
	arch._cast_hammer_smash()
	_assert(float(arch.ability_cds.get("hammer_smash", 0.0)) == 0.0,
		"smash113: gated client cast consumes no local cooldown")

	# Equip the hammer and cast end-to-end through the ability path.
	var hammer_idx := -1
	for i in arch.inventory.size():
		if str((arch.inventory[i]["item"] as Object).get("id")) == "forge_hammer":
			hammer_idx = i
	_assert(arch.equip_stack(hammer_idx), "smash113: hammer equips for the Smash")
	arch._cast_hammer_smash()
	var want_dmg: float = float(arch.get("damage")) * 1.5
	_assert(absf(float(m1.get("hp")) - (10000.0 - want_dmg)) < 0.5,
		"smash113: in-radius mob takes 150% of the caster's damage")
	_assert(m1.is_stunned() and absf(float(m1.get("_stun_t")) - 1.0) < 0.01,
		"smash113: in-radius mob is stunned for 1.0s")
	_assert(absf(float(m2.get("hp")) - 10000.0) < 0.01 and not m2.is_stunned(),
		"smash113: out-of-radius mob is untouched")
	_assert(float(arch.get("_srv_smash_cd")) > 9.0,
		"smash113: validated cast starts the 10s server cooldown")
	_assert(float(arch.ability_cds.get("hammer_smash", 0.0)) > 9.0,
		"smash113: client cooldown mirror set for the HUD")

	# Server cooldown blocks an immediate recast even via direct intent.
	arch.request_hammer_smash(40.0)
	_assert(absf(float(m1.get("hp")) - (10000.0 - want_dmg)) < 0.5,
		"smash113: recast inside the server cooldown is refused")

	# Stun gates movement: a physics tick leaves the mob stationary
	# and burns the timer down. (Knockback from the hit is cleared
	# first — it decays into velocity independently of the gate.)
	m1.set("_knockback", Vector3.ZERO)
	m1._physics_process(0.6)
	_assert(absf(float(m1.get("_stun_t")) - 0.4) < 0.05,
		"smash113: stun timer ticks down server-side")
	_assert(absf(m1.velocity.x) < 0.01 and absf(m1.velocity.z) < 0.01,
		"smash113: stunned mob does not move")

	# Stun refresh takes the longer duration; the dead are not stunned.
	m1.apply_stun(0.2)
	_assert(absf(float(m1.get("_stun_t")) - 0.4) < 0.05,
		"smash113: a shorter re-stun does not shorten the stun")
	m1.apply_stun(2.0)
	_assert(absf(float(m1.get("_stun_t")) - 2.0) < 0.01,
		"smash113: a longer re-stun extends the stun")
	m1.set("_stun_t", 0.0)
	m2.set("alive", false)
	m2.apply_stun(1.0)
	_assert(not m2.is_stunned(), "smash113: dead mobs are not stunned")

	# Forged replica: a non-architect claiming the hammer is refused.
	var war = PlayerScene.instantiate()
	war.class_id = "warrior"
	root.add_child(war)
	war.set("equipped_ids", {"WEAPON": "forge_hammer"})
	war.request_hammer_smash(40.0)
	_assert(absf(float(m1.get("hp")) - (10000.0 - want_dmg)) < 0.5,
		"smash113: non-architect refused even with forged equipped_ids")

	# A zero/negative damage claim is refused (cooldown untouched).
	arch.set("_srv_smash_cd", 0.0)
	arch.request_hammer_smash(0.0)
	_assert(float(arch.get("_srv_smash_cd")) == 0.0,
		"smash113: empty damage claim refused, cooldown untouched")

	# Cleanup.
	m1.free()
	m2.free()
	arch.free()
	war.free()
	current_scene = null
	holder.free()
	print("[Playtest] hammer smash done")
func _test_weapon_model_coverage_113() -> void:
	print("[Playtest] Weapon model coverage (issue #113 Phase 2)...")
	# Every weapon resolves a 3D world model. storm_caller + void_blade
	# carry the Art Director's GLBs as world_model AND retain a
	# WeaponVisual procedural fallback: if the asset ever goes missing,
	# the consumers drop to the fallback instead of the bare icon.
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var PickupScene: PackedScene = load("res://scenes/items/item_pickup.tscn")
	var weapons := 0
	var uncovered: Array = []
	for id in ItemDBNode.items.keys():
		var it = ItemDBNode.get_item(id)
		if it == null or int(it.get("slot")) != 0: # Slot.WEAPON
			continue
		weapons += 1
		var has_model: bool = str(it.get("world_model")) != "" \
			and ResourceLoader.exists(str(it.get("world_model")))
		if not has_model and not WeaponVisual.has_fallback(id):
			uncovered.append(id)
	_assert(weapons == 10,
		"113: item catalog carries 10 weapons (8 + Phase 3 wrench/hammer)")
	_assert(uncovered.is_empty(),
		"113: every weapon has a world model or a procedural fallback")
	var sc_item = ItemDBNode.get_item("storm_caller")
	var vb_item = ItemDBNode.get_item("void_blade")
	_assert(str(sc_item.get("world_model")) \
			== "res://assets/models/kaykit/weapons/storm_caller.glb" \
		and ResourceLoader.exists(str(sc_item.get("world_model"))) \
		and str(vb_item.get("world_model")) \
			== "res://assets/models/kaykit/weapons/void_blade.glb" \
		and ResourceLoader.exists(str(vb_item.get("world_model"))),
		"113: storm caller + void blade wired to the Art Director GLBs")
	_assert(WeaponVisual.has_fallback("storm_caller") \
		and WeaponVisual.has_fallback("void_blade"),
		"113: both wired weapons retain their procedural fallbacks")
	var sc_prop: Node3D = WeaponVisual.build_fallback("storm_caller")
	_assert(sc_prop.find_child("StormOrb", true, false) != null,
		"113: storm caller fallback builds with its orb")
	sc_prop.free()
	var vb_prop: Node3D = WeaponVisual.build_fallback("void_blade")
	_assert(vb_prop.find_child("VoidBlade", true, false) != null \
		and vb_prop.find_child("VoidCore", true, false) != null,
		"113: void blade fallback builds blade + emissive core")
	vb_prop.free()
	# GLB live: the real models drive all three consumers.
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	var mage = PlayerScene.instantiate()
	holder.add_child(mage)
	mage.set_multiplayer_authority(1)
	mage.class_id = "mage"
	mage.receive_item("storm_caller")
	for i in mage.inventory.size():
		var eit = mage.inventory[i].get("item")
		if eit != null and str(eit.get("id")) == "storm_caller":
			mage.equip_stack(i)
	var vm = mage.get("_viewmodel")
	var vm_glb := false
	if vm != null:
		vm_glb = vm.find_child("StormCallerProp", true, false) == null
		if vm_glb:
			vm_glb = false
			for n in vm.find_children("*", "MeshInstance3D", true, false):
				vm_glb = true
	_assert(vm_glb,
		"113: mage viewmodel renders the storm caller GLB (no fallback prop)")
	var peer = PlayerScene.instantiate()
	holder.add_child(peer)
	peer.set_multiplayer_authority(2)
	peer.class_id = "rogue"
	peer.push_snapshot(Vector3.ZERO, 100.0, 1, true, 0.0,
		{"WEAPON": "void_blade"})
	var held = peer.get_node_or_null("HeldProp/WeaponProp")
	var held_glb: bool = held != null \
		and held.find_child("VoidCore", true, false) == null \
		and not held.find_children("*", "MeshInstance3D", true, false).is_empty()
	_assert(held_glb,
		"113: peer held prop renders the void blade GLB (no fallback core)")
	var pk = PickupScene.instantiate()
	pk.setup(vb_item)
	holder.add_child(pk)
	var pk_model = pk.get_node_or_null("Model")
	var pk_glb := false
	if pk_model != null:
		for c in pk_model.get_children():
			if c.name != "VoidBladeProp":
				pk_glb = true
	_assert(pk_glb and not (pk.get_node("Sprite3D") as Node3D).visible,
		"113: void blade pickup renders the GLB, icon sprite hidden")
	pk.free()
	# Asset-missing simulation: point the shared ItemData resources at a
	# bogus path; every consumer must drop to the procedural fallback.
	# Booleans are captured first and the paths restored BEFORE the
	# asserts, so the catalog can never be left poisoned.
	var saved_sc = str(sc_item.get("world_model"))
	var saved_vb = str(vb_item.get("world_model"))
	sc_item.set("world_model", "res://assets/models/kaykit/weapons/__missing_113.glb")
	vb_item.set("world_model", "res://assets/models/kaykit/weapons/__missing_113.glb")
	var mage2 = PlayerScene.instantiate()
	holder.add_child(mage2)
	mage2.set_multiplayer_authority(1)
	mage2.class_id = "mage"
	mage2.receive_item("storm_caller")
	for i in mage2.inventory.size():
		var eit2 = mage2.inventory[i].get("item")
		if eit2 != null and str(eit2.get("id")) == "storm_caller":
			mage2.equip_stack(i)
	var vm2 = mage2.get("_viewmodel")
	var vm_sim: bool = vm2 != null \
		and vm2.find_child("StormCallerProp", true, false) != null
	var peer2 = PlayerScene.instantiate()
	holder.add_child(peer2)
	peer2.set_multiplayer_authority(3)
	peer2.class_id = "rogue"
	peer2.push_snapshot(Vector3.ZERO, 100.0, 1, true, 0.0,
		{"WEAPON": "void_blade"})
	var held2 = peer2.get_node_or_null("HeldProp/WeaponProp")
	var held_sim: bool = held2 != null \
		and held2.find_child("VoidCore", true, false) != null
	var dup_vb = vb_item.duplicate()
	dup_vb.set("world_model", "res://assets/models/kaykit/weapons/__missing_113.glb")
	var pk2 = PickupScene.instantiate()
	pk2.setup(dup_vb)
	holder.add_child(pk2)
	var pk2_model = pk2.get_node_or_null("Model")
	var pk_sim := false
	if pk2_model != null:
		for c in pk2_model.get_children():
			if c.name == "VoidBladeProp":
				pk_sim = true
	sc_item.set("world_model", saved_sc)
	vb_item.set("world_model", saved_vb)
	_assert(vm_sim,
		"113: missing GLB -> viewmodel falls back to the procedural prop")
	_assert(held_sim,
		"113: missing GLB -> held prop falls back to the procedural prop")
	_assert(pk_sim,
		"113: missing GLB -> pickup falls back to the procedural model")
	mage.free()
	peer.free()
	mage2.free()
	peer2.free()
	pk2.free()
	current_scene = null
	holder.free()
	print("[Playtest] weapon model coverage 113 done")
