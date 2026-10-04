extends Node
## Architect screenshot driver. Run under Xvfb:
##   godot --path . res://tools/architect_shots/architect_shots.tscn --resolution 1280x720 -- --shot-dir /tmp/architect_shots
## 1. Screenshots the title menu (4-class picker).
## 2. Boots solo architect, places a wall + turret, screenshots in-game.

var _shot_dir := "/tmp/architect_shots"
var _t0 := 0
var _phase := 0
var _player: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_t0 = Time.get_ticks_msec()
	print("[ArchitectShots] output -> ", _shot_dir)
	_show_title()


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func _show_title() -> void:
	await get_tree().process_frame
	var tree := get_tree()
	var cur := tree.current_scene
	if cur != null and cur != self:
		tree.current_scene = self
		cur.queue_free()
		await tree.process_frame
	var packed := load("res://scenes/ui/main_menu.tscn") as PackedScene
	var inst := packed.instantiate()
	tree.root.add_child(inst)
	tree.current_scene = inst
	print("[ArchitectShots] title booted")


func _boot_dungeon() -> void:
	await get_tree().process_frame
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	NetworkManager.selected_class_id = "architect"
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "village"
	Dungeon.next_seed = 424242
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
	print("[ArchitectShots] dungeon booted")


func _snap(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join("architect_%s.png" % label)
	if img.save_png(path) == OK:
		print("[ArchitectShots] saved ", path)
	else:
		push_error("[ArchitectShots] FAILED " + path)


func _process(_delta: float) -> void:
	var t := _elapsed()
	match _phase:
		0:
			# Let the title settle, then snap the 4-class picker.
			if t > 6.0:
				_snap("title_picker")
				_phase = 1
		1:
			if t > 7.0:
				_boot_dungeon()
				_phase = 2
		2:
			var ps := get_tree().get_nodes_in_group("players")
			if not ps.is_empty():
				_player = ps[0]
				_phase = 3
			elif t > 70.0:
				push_error("[ArchitectShots] player never spawned")
				get_tree().quit()
		3:
			# Player is architect already (title choice). Place wall + turret ahead.
			if t > 14.0:
				var dgn := get_tree().get_first_node_in_group("dungeon")
				var pp: Vector3 = _player.global_position
				var fwd: Vector3 = -_player.global_transform.basis.z
				fwd.y = 0.0
				fwd = fwd.normalized()
				var me := int(_player.get_multiplayer_authority())
				dgn.place_structure("bulwark_wall", pp + fwd * 8.0, me, 1, "shot_wall")
				var right := fwd.cross(Vector3.UP).normalized()
				dgn.place_structure("sentry_turret", pp + fwd * 6.5 + right * 5.5, me, 1, "shot_turret")
				print("[ArchitectShots] structures placed")
				_phase = 4
		4:
			if t > 17.0:
				_snap("in_game")
				print("[ArchitectShots] done")
				get_tree().quit()
