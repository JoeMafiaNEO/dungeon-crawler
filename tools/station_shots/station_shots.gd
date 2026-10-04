extends Node
## Station screenshot driver. Run under Xvfb:
##   godot --path . res://tools/station_shots/station_shots.tscn --resolution 1280x720 -- --shot-dir /tmp/station_shots
## Boots the station solo, frames a wide shot of train + platform, shows the
## departure timer, and screenshots it.

var _shot_dir := "/tmp/station_shots"
var _t0 := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_t0 = Time.get_ticks_msec()
	print("[StationShots] output -> ", _shot_dir)
	_boot_station()


func _boot_station() -> void:
	await get_tree().process_frame
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	NetworkManager.selected_class_id = "warrior"
	Dungeon.saved_player_state = {}
	Station.next_level_number = 2
	var tree := get_tree()
	var cur := tree.current_scene
	if cur != null and cur != self:
		tree.current_scene = self
		cur.queue_free()
		await tree.process_frame
	var packed := load("res://scenes/station/station.tscn") as PackedScene
	var inst := packed.instantiate()
	tree.root.add_child(inst)
	tree.current_scene = inst
	print("[StationShots] station booted")
	# Let the player spawn, then frame a wide overview shot.
	await get_tree().create_timer(2.0).timeout
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	cam.position = Vector3(10, 9, 14)
	cam.look_at(Vector3(-4, 1.0, -1))
	cam.current = true
	# Force the departure timer label on for the shot.
	var hud := tree.get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_station_timer"):
		hud.show_station_timer(32.0)
	await get_tree().create_timer(0.5).timeout
	_snap("station_wide")
	# Departure board UI shot (Phase 2).
	if hud != null and hud.has_method("show_departure_board"):
		hud.show_departure_board()
		await get_tree().create_timer(0.8).timeout
		_snap("board")
	print("[StationShots] done")
	get_tree().quit()


func _snap(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join("station_%s.png" % label)
	if img.save_png(path) == OK:
		print("[StationShots] saved ", path)
	else:
		print("[StationShots] FAILED to save ", path)
