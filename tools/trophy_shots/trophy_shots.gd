extends Node
## Apex trophy screenshot driver. Run under Xvfb with a SCRATCH account:
##   DUNGEON_TEST_ACCOUNT=trophy_shots godot --path . res://tools/trophy_shots/trophy_shots.tscn -- --shot-dir /tmp/trophy_shots
## Boots solo warrior, records 2/3 apex trophies (boar+warden earned, horror
## locked), opens pause -> Collection tab, screenshots the trophy rows.
## Uses only the scratch profile (never touches the real user:// saves).

var _shot_dir := "/tmp/trophy_shots"
var _t0 := 0
var _phase := 0
var _player: Node = null
var _hud: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_t0 = Time.get_ticks_msec()
	var acct := OS.get_environment("DUNGEON_TEST_ACCOUNT")
	if acct.is_empty():
		push_error("[TrophyShots] DUNGEON_TEST_ACCOUNT must be set (scratch-only rule)")
		get_tree().quit()
		return
	print("[TrophyShots] output -> ", _shot_dir, " (account: ", acct, ")")
	_boot_dungeon()


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func _process(_delta: float) -> void:
	var t := _elapsed()
	match _phase:
		0:
			_find_player()
			if _player != null:
				_setup()
				_phase = 1
			elif t > 60.0:
				push_error("[TrophyShots] player never spawned")
				_cleanup()
		1:
			if t > 14.0:
				_open_collection()
				_phase = 2
		2:
			if t > 17.0:
				_snap("trophy_rows")
				print("[TrophyShots] done")
				_cleanup()


func _boot_dungeon() -> void:
	await get_tree().process_frame
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	NetworkManager.selected_class_id = "warrior"
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "village"
	Dungeon.next_seed = 777001
	Dungeon.next_level_number = 1
	var tree := get_tree()
	var cur := tree.current_scene
	if cur != null and cur != self:
		tree.current_scene = self
		cur.queue_free()
		await tree.process_frame
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	var inst := packed.instantiate()
	tree.root.add_child(inst)
	tree.current_scene = inst
	print("[TrophyShots] dungeon booted")


func _find_player() -> void:
	var ps := get_tree().get_nodes_in_group("players")
	if not ps.is_empty():
		_player = ps[0]


func _setup() -> void:
	# 2/3 trophies: boar + warden earned, horror locked (shows ??? row).
	# Pin the autoload to the scratch profile (never touches real saves).
	var acct := OS.get_environment("DUNGEON_TEST_ACCOUNT")
	SaveManager.set("_test_account_pin", acct)
	SaveManager.load_game()
	SaveManager.record_apex_trophy("apex_boar")
	SaveManager.record_apex_trophy("apex_warden")
	_hud = _player.get("hud")
	print("[TrophyShots] trophies recorded")


func _open_collection() -> void:
	if _hud == null:
		return
	_hud.call("show_pause")
	_hud.call("select_pause_tab", 2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _snap(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_shot_dir, name])
	print("[TrophyShots] saved ", name)


func _cleanup() -> void:
	# Unpin + delete the scratch profile (never touches real saves).
	var acct := OS.get_environment("DUNGEON_TEST_ACCOUNT")
	if not acct.is_empty():
		SaveManager.set("_test_account_pin", "")
		SaveManager.load_game()
		var scratch := "user://profile_%s.cfg" % acct
		if FileAccess.file_exists(scratch):
			DirAccess.remove_absolute(scratch)
			print("[TrophyShots] scratch profile removed")
	get_tree().quit()
