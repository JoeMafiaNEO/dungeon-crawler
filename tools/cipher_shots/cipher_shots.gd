extends Node
## Cipher screenshot driver. Run under Xvfb:
##   godot --path . res://tools/cipher_shots/cipher_shots.tscn --resolution 1280x720 -- --shot-dir /tmp/cipher_shots
## 1. Boots solo village, opens a poem popup, screenshots it.
## 2. Spawns a lockbox nearby, opens its popup, screenshots it.
## 3. Grants 3 fragments (meta backup/restore), opens pause Collection tab, screenshots.

var _shot_dir := "/tmp/cipher_shots"
var _t0 := 0
var _phase := 0
var _player: Node = null
var _meta_backup := PackedByteArray()
var _meta_path := "user://savegame.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	if FileAccess.file_exists(_meta_path):
		_meta_backup = FileAccess.get_file_as_bytes(_meta_path)
	_t0 = Time.get_ticks_msec()
	print("[CipherShots] output -> ", _shot_dir)
	_boot_dungeon()


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


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
	print("[CipherShots] dungeon booted")


func _snap(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join("cipher_%s.png" % label)
	if img.save_png(path) == OK:
		print("[CipherShots] saved ", path)
	else:
		push_error("[CipherShots] FAILED " + path)


func _process(_delta: float) -> void:
	var t := _elapsed()
	match _phase:
		0:
			var ps := get_tree().get_nodes_in_group("players")
			if not ps.is_empty():
				_player = ps[0]
				_phase = 1
			elif t > 70.0:
				push_error("[CipherShots] player never spawned")
				get_tree().quit()
		1:
			# Open a poem popup directly (no meta write) and snap it.
			if t > 10.0:
				_player.hud.show_poem_popup(2)
				_phase = 2
		2:
			if t > 12.0:
				_snap("poem_popup")
				_player.hud.close_cipher_popup()
				_phase = 3
		3:
			# Lockbox popup next.
			if t > 13.5:
				var dgn := get_tree().get_first_node_in_group("dungeon")
				var pp: Vector3 = _player.global_position
				dgn.spawn_cipher_lockbox(pp + Vector3(2, 0, 2))
				_player.hud.show_lockbox_popup()
				_phase = 4
		4:
			if t > 15.5:
				_snap("lockbox_popup")
				_player.hud.close_cipher_popup()
				_phase = 5
		5:
			# Collection tab with 3 fragments.
			if t > 17.0:
				for i in [0, 2, 5]:
					SaveManager.add_cipher_fragment(i)
				_player.hud.show_pause()
				_player.hud.select_pause_tab(2)
				_phase = 6
		6:
			if t > 19.0:
				_snap("collection_cipher")
				# Park the player in front of the parchment note and snap it.
				_player.hud.hide_pause()
				var notes := get_tree().get_nodes_in_group("cipher_plaques")
				if not notes.is_empty():
					var note := notes[0] as Node3D
					var np: Vector3 = note.global_position
					_player.global_position = np + Vector3(0, 0, 2.2)
					_player.rotation.y = atan2(np.x - _player.global_position.x, np.z - _player.global_position.z) + PI
				_phase = 7
		7:
			if t > 21.0:
				_snap("cipher_note")
				print("[CipherShots] done")
				# Restore meta.
				if _meta_backup.is_empty():
					DirAccess.remove_absolute(_meta_path)
				else:
					var f := FileAccess.open(_meta_path, FileAccess.WRITE)
					f.store_buffer(_meta_backup)
				get_tree().quit()
