extends Node
## Issue #138 Phase 2 validation (dev only): the section-5 continue
## fixture. Writes a pre-existing-style solo run save through the
## REAL SaveManager.save_run path — the fixture dict carries exactly
## the top-level keys a real pause-save writes (theme_id,
## level_number, seed, at_station, wave, class_id, player_state) —
## under scratch pins (the real user:// saves are never touched),
## then continues it through the REAL NetworkManager.continue_run
## and verifies which level path the dungeon took:
##
##   --seed 424242 (arbitrary): procgen fallback — no baked hash,
##     and the layout is byte-identical to fresh ProcGen(seed).
##   --seed 1 (the village pin): the baked scene loads (a save from
##     a fresh post-#138 run carries the pin).
##
##   godot --headless --path . res://tools/baked_continue_check.tscn -- --seed 424242 --out ~/result.txt
##
## The tscn root only spawns the real driver as a root sibling, so
## the driver survives continue_run's scene change.

var _is_driver := false
var _seed := 424242
var _level := 3
var _out := ""
var _t := 0.0
var _settle := 0.0
var _continued := false


func _ready() -> void:
	if not _is_driver:
		var driver = load("res://tools/baked_continue_check.gd").new()
		driver.set("_is_driver", true)
		driver.name = "Continue138Driver"
		get_tree().root.call_deferred("add_child", driver)
		return
	_parse_args()
	var scratch := "user://baked138_scratch"
	SaveManager.set("_test_runs_dir", scratch)
	SaveManager.set("_test_account_pin", "baked138_scratch")
	if DirAccess.dir_exists_absolute(scratch):
		for f in DirAccess.get_files_at(scratch):
			DirAccess.remove_absolute(scratch.path_join(f))
	var fixture := {
		"theme_id": "village",
		"level_number": _level,
		"seed": _seed,
		"at_station": false,
		"wave": 2,
		"class_id": "warrior",
		"player_state": {},
	}
	if not SaveManager.save_run(fixture, SaveManager.MODE_SOLO, 5):
		_finish("FAIL fixture save_run refused", 1)
		return
	print("[CONT138] fixture saved: village level %d seed %d" % [_level, _seed])
	_continued = NetworkManager.continue_run(SaveManager.MODE_SOLO, 5)
	if not _continued:
		_finish("FAIL continue_run refused the fixture", 1)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		var key := a
		var val := ""
		var eq := a.find("=")
		if eq > 0:
			key = a.substr(0, eq)
			val = a.substr(eq + 1)
		elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
			val = args[i + 1]
			i += 1
		if key == "--seed":
			_seed = int(val)
		elif key == "--level":
			_level = int(val)
		elif key == "--out":
			_out = val
		i += 1


func _process(delta: float) -> void:
	if not _is_driver or not _continued:
		return
	_t += delta
	if _t > 60.0:
		_finish("FAIL TIMEOUT waiting for the dungeon", 1)
		return
	var scene = get_tree().current_scene
	if scene == null or not scene.scene_file_path.ends_with("dungeon.tscn"):
		return
	_settle += delta
	if _settle < 4.0:
		return
	var dgn = get_tree().get_first_node_in_group("dungeon")
	if dgn == null:
		_finish("FAIL no dungeon node", 1)
		return
	var baked := str(dgn.get("_baked_hash"))
	var layout = dgn.get("_layout")
	var fp: String = str(layout.fingerprint()) if layout != null else "<none>"
	var pin := LevelData.pinned_seed("village")
	var result := ""
	var code := 0
	if Dungeon.next_seed != _seed:
		result = "FAIL continue carried seed %d, fixture said %d" % [Dungeon.next_seed, _seed]
		code = 1
	elif _seed == pin:
		var want := LevelData.shipped_hash("village")
		if baked == want and want != "":
			result = "PASS pinned-seed continue loaded the baked scene (hash %s)" % baked
		else:
			result = "FAIL pinned-seed continue: baked hash '%s', want '%s'" % [baked, want]
			code = 1
	else:
		var theme_v: Resource = load("res://data/levels/theme_village.tres")
		var regen = ProcGen.generate(theme_v, _seed)
		if baked == "" and fp == str(regen.fingerprint()):
			result = "PASS arbitrary-seed continue took procgen, layout == fresh ProcGen(%d)" % _seed
		else:
			result = "FAIL arbitrary-seed continue: baked='%s' fp_match=%s" % [baked, str(fp == str(regen.fingerprint()))]
			code = 1
	# Cleanup: unpin and remove the scratch dir (abort-safe order —
	# unpin first so a later real run can never see the scratch).
	SaveManager.set("_test_runs_dir", "")
	SaveManager.set("_test_account_pin", "")
	var scratch := "user://baked138_scratch"
	if DirAccess.dir_exists_absolute(scratch):
		for f in DirAccess.get_files_at(scratch):
			DirAccess.remove_absolute(scratch.path_join(f))
		DirAccess.remove_absolute(scratch)
	_finish(result, code)


func _finish(result: String, code: int) -> void:
	print("[CONT138] RESULT ", result)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string(result + "\n")
	set_process(false)
	get_tree().quit(code)
