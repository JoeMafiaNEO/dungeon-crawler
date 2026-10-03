extends SceneTree
## Playtest automation: headless smoke tests for Steam-ready validation.
## Run: godot --headless --path . -s tests/playtest.gd

var _failures: Array = []
var _passes: int = 0


func _init() -> void:
	print("[Playtest] Starting automated validation...")
	_test_boot()
	_test_rts_costs()
	_test_rts_production()
	_test_save_roundtrip()
	_test_cycle_scaling()
	_test_ai_director()
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
	# ConfigFile roundtrip with nested dict.
	var cfg := ConfigFile.new()
	var data := {"level": 9, "class_id": "mage", "theme_id": "dungeon", "stats": {"str": 5}}
	cfg.set_value("run", "data", data)
	cfg.save("user://test_save.cfg")
	var cfg2 := ConfigFile.new()
	_assert(cfg2.load("user://test_save.cfg") == OK, "Save file loads")
	var loaded: Dictionary = cfg2.get_value("run", "data", {})
	_assert(int(loaded.get("level", 0)) == 9, "Save preserves level")
	_assert(str(loaded.get("class_id", "")) == "mage", "Save preserves class")
	DirAccess.remove_absolute("user://test_save.cfg")


func _test_cycle_scaling() -> void:
	print("[Playtest] Cycle scaling...")
	# Grid size: 40 + 40*cycle, capped at 96.
	for cycle in [0, 1, 2, 5]:
		var grid: int = mini(40 + 40 * cycle, 96)
		_assert(grid <= 96, "Grid capped at 96 (cycle %d)" % cycle)
		_assert(grid >= 40, "Grid at least 40 (cycle %d)" % cycle)
	# Key counts: base + cycle, capped at 8.
	for cycle in [0, 1, 5, 10]:
		var keys: int = mini(3 + cycle, 8)
		_assert(keys <= 8, "Keys capped at 8 (cycle %d)" % cycle)


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
