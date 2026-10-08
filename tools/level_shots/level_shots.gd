extends Node
## DLC level showcase capture. Boots a real solo run for a theme with a live
## player (same pattern as tools/foundry_shots), hides HUD, saves 1920x1080.
## Run under Xvfb:
##   xvfb-run -a godot --path . --resolution 1920x1080 res://tools/level_shots/level_shots.tscn -- <theme_id> <out.png>

var _theme_id := "sunken_crypt"
var _out := "/tmp/shot.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_theme_id = args[0]
	if args.size() > 1:
		_out = args[1]
	get_viewport().size = Vector2i(1920, 1080)
	# Scratch save isolation (same pattern as foundry_shots).
	SaveManager.set("_test_account_pin", "level_shots")
	SaveManager.set("_test_runs_dir", "user://runs_scratch_levelshots")
	SaveManager.load_game()
	NetworkManager.selected_class_id = "warrior"
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = _theme_id
	Dungeon.next_seed = 424242
	Dungeon.next_level_number = 1
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	var inst := packed.instantiate()
	get_tree().root.add_child.call_deferred(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = inst
	# Let the level build and the player spawn.
	await get_tree().create_timer(6.0).timeout
	_aim_showcase_camera()
	await get_tree().create_timer(1.0).timeout
	_capture()


func _aim_showcase_camera() -> void:
	# Authentic first-person gameplay view: put the player on the clearest
	# spawn point facing the open arena. (Elevated shots don't work — the
	# theme fog is exponential and fogs out anything past ~20m.)
	var dungeon: Node = get_tree().get_first_node_in_group("dungeon")
	var player: Node3D = null
	for n in get_tree().get_nodes_in_group("players"):
		player = n as Node3D
		break
	if dungeon == null or player == null:
		push_error("[LevelShots] no dungeon/player")
		return
	var spawns: Array = dungeon.get("spawn_points")
	if spawns.is_empty():
		push_error("[LevelShots] no spawn points")
		return
	var c := Vector3.ZERO
	var box := AABB()
	var got_box := false
	for mi in dungeon.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b: AABB = m.global_transform * m.get_aabb()
		if not got_box:
			box = b
			got_box = true
		else:
			box = box.merge(b)
	if got_box:
		c = box.get_center()
	else:
		for s in spawns:
			c += (s as Vector3)
		c /= float(spawns.size())
	var best: Vector3 = spawns[0]
	var best_d := 1e20
	for s in spawns:
		var d: float = (s as Vector3).distance_to(c)
		if d < best_d:
			best_d = d
			best = s
	player.global_position = best + Vector3(0, 0.3, 0)
	player.look_at(Vector3(c.x, player.global_position.y, c.z), Vector3.UP)
	print("[LevelShots] player at ", player.global_position, " facing arena center ", c)


func _capture() -> void:
	# Hide HUD overlays so the level reads clean.
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out)
	print("[LevelShots] saved %s (err=%d)" % [_out, err])
	_cleanup()


func _cleanup() -> void:
	SaveManager.set("_test_account_pin", "")
	SaveManager.set("_test_runs_dir", "")
	if DirAccess.dir_exists_absolute("user://runs_scratch_levelshots"):
		OS.move_to_trash("user://runs_scratch_levelshots")
	get_tree().quit()
