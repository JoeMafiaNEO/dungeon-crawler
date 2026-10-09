extends Node
## Boarding flow screenshot driver (issue #3 Phase 2). Run under Xvfb:
##   godot --path . res://tools/boarding_shots/boarding_shots.tscn -- --shot-dir /tmp/boarding_shots
## Boots a solo dungeon, forces a unanimous vote + depart() (ALL ABOARD),
## screenshots the banner + boarding timer HUD.

var _shot_dir := "/tmp/boarding_shots"
## Scratch isolation: the E2E ride saves runs/profile data. These pins keep
## every write on scratch files that we delete at the end. Real user:// saves
## are NEVER touched.
const SCRATCH_ACCOUNT := "boarding_shots"
const SCRATCH_RUNS_DIR := "user://runs_scratch_boarding"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Pin SaveManager to scratch storage BEFORE anything can save.
	SaveManager.set("_test_account_pin", SCRATCH_ACCOUNT)
	SaveManager.set("_test_runs_dir", SCRATCH_RUNS_DIR)
	SaveManager.load_game()
	print("[BoardingShots] scratch profile: user://profile_%s.cfg" % SCRATCH_ACCOUNT)
	for arg in OS.get_cmdline_user_args():
		if arg == "--shot-dir":
			continue
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot-dir" and i + 1 < args.size():
			_shot_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	print("[BoardingShots] output -> ", _shot_dir)
	NetworkManager.selected_class_id = "warrior"
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "village"
	Dungeon.next_seed = 424242
	Dungeon.next_level_number = 1
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	var inst := packed.instantiate()
	get_tree().root.add_child.call_deferred(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = inst
	await get_tree().create_timer(8.0).timeout
	var station := get_tree().get_first_node_in_group("station")
	if station == null or not station.has_method("depart"):
		push_error("[BoardingShots] no station found")
		get_tree().quit()
		return
	# Annex establishing shot (Phase 5 validation): park the player in the
	# hall facing the train (north, -z) before forcing the vote.
	var _player0 := _find_player()
	if _player0 != null:
		_player0.global_position = (station as Node3D).global_transform * Vector3(3.0, 0.1, 2.5)
		_player0.set("_yaw", 0.0)
		_player0.rotation.y = 0.0
		await get_tree().create_timer(1.0).timeout
		await get_tree().process_frame
		await get_tree().process_frame
		var _img0 := get_viewport().get_texture().get_image()
		if _img0.save_png(_shot_dir + "/annex_train.png") == OK:
			print("[BoardingShots] saved ", _shot_dir + "/annex_train.png")
		else:
			push_error("[BoardingShots] FAILED to save annex_train.png")
	# Solo: one vote is unanimous -> ALL ABOARD.
	station.record_vote(1, "dungeon", [1])
	station.depart([1])
	await get_tree().create_timer(1.5).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir + "/boarding_all_aboard.png"
	if img.save_png(path) == OK:
		print("[BoardingShots] saved ", path)
	else:
		push_error("[BoardingShots] FAILED to save " + path)
	# End-to-end (issue #93 Phase 3): walk the player into the lobby, pull
	# the depart lever -> doors close -> ride -> interior scene.
	var player := _find_player()
	if player != null:
		var lp: Vector3 = station.annex.lobby_spawn_spots()[0]
		player.global_position = station.to_global(lp)
		await get_tree().create_timer(1.0).timeout
		print("[BoardingShots] doors_open=", station.annex.doors_open)
		# Pull the lever through the real interact path.
		var lever := _find_depart_lever()
		if lever != null:
			player.global_position = (lever as Node3D).global_position + Vector3(0, 0, 1.0)
			# Face the lever (south, +z) for the prop shot.
			player.set("_yaw", 3.14159)
			player.rotation.y = 3.14159
			await get_tree().create_timer(0.5).timeout
			await get_tree().process_frame
			await get_tree().process_frame
			var img2 := get_viewport().get_texture().get_image()
			if img2.save_png(_shot_dir + "/depart_lever.png") == OK:
				print("[BoardingShots] saved ", _shot_dir + "/depart_lever.png")
			lever.interact(player)
			print("[BoardingShots] lever pulled, depart_requested=", station.get("_depart_requested"))
		await get_tree().create_timer(1.0).timeout
		await get_tree().process_frame
		await get_tree().process_frame
		var img3 := get_viewport().get_texture().get_image()
		if img3.save_png(_shot_dir + "/depart_doors_closing.png") == OK:
			print("[BoardingShots] saved ", _shot_dir + "/depart_doors_closing.png")
		await get_tree().create_timer(2.0).timeout
		print("[BoardingShots] doors_open after depart=", station.annex.doors_open)
		await get_tree().create_timer(6.0).timeout
		var cur := get_tree().current_scene
		print("[BoardingShots] current_scene=", cur.name if cur != null else "null")
	# The end-to-end ride saved into the scratch profile + scratch runs dir.
	# Remove ONLY those scratch files; real user:// saves were never touched.
	_cleanup_scratch()
	print("[BoardingShots] done")
	get_tree().quit()


## Unpin SaveManager, reload the real profile, and delete scratch files.
func _cleanup_scratch() -> void:
	SaveManager.set("_test_account_pin", "")
	SaveManager.set("_test_runs_dir", "")
	SaveManager.load_game()
	var prof := "user://profile_%s.cfg" % SCRATCH_ACCOUNT
	if FileAccess.file_exists(prof):
		DirAccess.remove_absolute(prof)
		print("[BoardingShots] removed scratch profile")
	if DirAccess.dir_exists_absolute(SCRATCH_RUNS_DIR):
		for f in DirAccess.get_files_at(SCRATCH_RUNS_DIR):
			DirAccess.remove_absolute(SCRATCH_RUNS_DIR.path_join(f))
		DirAccess.remove_absolute(SCRATCH_RUNS_DIR)
		print("[BoardingShots] removed scratch runs dir")


func _find_depart_lever() -> Node:
	var levers := get_tree().get_nodes_in_group("depart_lever")
	return levers[0] if not levers.is_empty() else null


func _find_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == multiplayer.get_unique_id():
			return p
	var ps := get_tree().get_nodes_in_group("players")
	return ps[0] if not ps.is_empty() else null
