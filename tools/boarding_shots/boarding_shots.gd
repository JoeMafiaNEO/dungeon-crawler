extends Node
## Boarding flow screenshot driver (issue #3 Phase 2). Run under Xvfb:
##   godot --path . res://tools/boarding_shots/boarding_shots.tscn -- --shot-dir /tmp/boarding_shots
## Boots a solo dungeon, forces a unanimous vote + depart() (ALL ABOARD),
## screenshots the banner + boarding timer HUD.

var _shot_dir := "/tmp/boarding_shots"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	# End-to-end: walk the player through the train door -> request_board ->
	# all aboard (solo) -> ride -> interior scene.
	var player := _find_player()
	var zone := station.get_node_or_null("BoardingZone")
	if player != null and zone != null:
		player.global_position = (zone as Node3D).global_position
		await get_tree().create_timer(2.0).timeout
		print("[BoardingShots] aboard=", station.aboard, " locked=", station.get("_boarding_locked"))
		await get_tree().create_timer(6.0).timeout
		var cur := get_tree().current_scene
		print("[BoardingShots] current_scene=", cur.name if cur != null else "null")
	# The end-to-end ride runs the real solo save; remove it so later test
	# runs (save roundtrips) see a clean user://.
	for f in ["savegame.cfg", "solo_warrior.cfg", "solo_mage.cfg", "solo_rogue.cfg"]:
		var p := "user://".path_join(f)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	print("[BoardingShots] done")
	get_tree().quit()


func _find_player() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == multiplayer.get_unique_id():
			return p
	var ps := get_tree().get_nodes_in_group("players")
	return ps[0] if not ps.is_empty() else null
