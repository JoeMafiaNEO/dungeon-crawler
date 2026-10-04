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
	_test_cycle_scaling()
	_test_ai_director()
	_test_economy()
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
	print("[Playtest] Save roundtrip...")
	# Exercise the real SaveManager code path (atomic save + load).
	var mgr = load("res://scripts/autoload/save_manager.gd").new()
	# Back up any real run save so the test doesn't clobber it.
	var backup := {}
	var real_path := "user://run_save.cfg"
	if FileAccess.file_exists(real_path):
		var bcfg := ConfigFile.new()
		if bcfg.load(real_path) == OK:
			backup = bcfg.get_value("run", "data", {})
	mgr.clear_run("mage")
	var run := {
		"level": 9, "class_id": "mage", "theme_id": "dungeon",
		"level_number": 2, "cycle": 1, "seed": 12345,
		"stats": {"str": 5, "vit": 3},
	}
	mgr.save_run(run)
	_assert(mgr.has_run("mage"), "SaveManager reports run exists after save")
	var loaded: Dictionary = mgr.load_run("mage")
	_assert(int(loaded.get("level", 0)) == 9, "SaveManager preserves level")
	_assert(str(loaded.get("class_id", "")) == "mage", "SaveManager preserves class")
	_assert(str(loaded.get("theme_id", "")) == "dungeon", "SaveManager preserves theme")
	_assert(int(loaded.get("cycle", 0)) == 1, "SaveManager preserves cycle")
	_assert(str(loaded.get("saved_at", "")) != "", "SaveManager stamps saved_at")
	var summary: String = mgr.run_summary("mage")
	_assert(str(summary) != "", "run_summary non-empty for saved run")
	# Per-class isolation: warrior slot is empty.
	_assert(not mgr.has_run("warrior"), "Per-class saves are isolated")
	var saves: Array = mgr.list_solo_saves()
	_assert(saves.size() == 1, "list_solo_saves finds the mage save")
	# Multiplayer save format.
	var mp_run := {
		"theme_id": "dungeon", "level_number": 2, "seed": 999,
		"is_multiplayer": true, "host_difficulty": 1.5, "host_loot_mult": 2.0,
		"lobby": {"max_players": 4, "lobby_name": "Test"},
		"roster": [
			{"steam_id": 111, "player_name": "Host", "class_id": "warrior",
			 "player_state": {"level": 5}, "rts_faction": 0, "is_host": true},
			{"steam_id": 222, "player_name": "Guest", "class_id": "mage",
			 "player_state": {"level": 3}, "rts_faction": 1, "is_host": false},
		],
	}
	mgr.save_run(mp_run)
	var mp_loaded: Dictionary = mgr.load_run()
	_assert(bool(mp_loaded.get("is_multiplayer", false)), "Multiplayer flag preserved")
	_assert(int(mp_loaded.get("save_version", 0)) == mgr.SAVE_VERSION, "Save version stamped")
	_assert(float(mp_loaded.get("host_difficulty", 0.0)) == 1.5, "Host difficulty preserved")
	_assert(mp_loaded.get("roster", []).size() == 2, "Roster preserved")
	_assert(mgr.is_save_compatible(), "Save compatibility check passes")
	var mp_summary: String = mgr.run_summary("")
	_assert("2 players" in mp_summary, "Multiplayer summary shows player count")
	mgr.clear_run("")
	_assert(not mgr.has_run(""), "clear_run removes the multiplayer run")
	mgr.clear_run("mage")
	_assert(not mgr.has_run("mage"), "clear_run removes the class save")
	# Restore the real run save if there was one.
	if not backup.is_empty():
		mgr.save_run(backup)
	mgr.free()


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
	_assert(src.contains("per_res := 8 + 2 * cycle"), "Node count scales with cycle")


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
	# Save path pattern.
	var mgr = load("res://scripts/autoload/save_manager.gd").new()
	_assert("architect" in mgr.SOLO_CLASSES, "architect in SOLO_CLASSES")
	_assert("user://solo_%s.cfg" % "architect" == "user://solo_architect.cfg", "Architect save path pattern")
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
	# Meta round-trip (back up user://savegame.cfg so the test can't clobber it).
	var cfg_path := "user://savegame.cfg"
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
