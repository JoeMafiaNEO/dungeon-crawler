extends Node
## Affinity/specialization UI screenshot driver. Run under Xvfb:
##   godot --path . res://tools/affinity_shots/affinity_shots.tscn --resolution 1280x720 -- --shot-dir /tmp/affinity_shots
## Boots solo mage at level 24, specializes in Fireball with 60 affinity
## (2 family traits collected), opens the pause menu, and screenshots the
## specialization list + family panel. Wall-clock timed (llvmpipe is slow).

var _shot_dir := "/tmp/affinity_shots"
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
	print("[AffinityShots] output -> ", _shot_dir)
	_boot_dungeon()


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func _process(_delta: float) -> void:
	var t := _elapsed()
	match _phase:
		0:
			# Wait for the player to exist (up to 60s).
			_find_player()
			if _player != null:
				_setup_player()
				_phase = 1
			elif t > 60.0:
				push_error("[AffinityShots] player never spawned")
				get_tree().quit()
		1:
			if t > 14.0:
				_open_pause()
				_phase = 2
		2:
			if t > 17.0:
				_snap("pause_top")
				_phase = 3
		3:
			if t > 18.5:
				_scroll_to_spec()
				_phase = 4
		4:
			if t > 20.0:
				_snap("spec_list")
				_phase = 5
		5:
			if t > 21.5:
				_scroll_to_bottom()
				_phase = 6
		6:
			if t > 23.0:
				_snap("family_panel")
				print("[AffinityShots] done")
				get_tree().quit()


func _boot_dungeon() -> void:
	# Let the bootstrap scene finish entering the tree before swapping.
	await get_tree().process_frame
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	NetworkManager.selected_class_id = "mage"
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
	print("[AffinityShots] dungeon booted")


func _find_player() -> void:
	var ps := get_tree().get_nodes_in_group("players")
	if not ps.is_empty():
		_player = ps[0]


func _setup_player() -> void:
	var class_id := "mage"
	var skill_id := "fireball"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--class="):
			class_id = arg.get_slice("=", 1)
		elif arg.begins_with("--skill="):
			skill_id = arg.get_slice("=", 1)
	# Switch class if needed (tool boots as mage by default).
	if String(_player.get("class_id")) != class_id:
		_player.call("switch_class", class_id)
		# switch_class resets level to 1; restore.
	_player.set("level", 24)
	_player.call("_recalc_stats")
	_player.call("refresh_abilities")
	_player.call("specialize", skill_id)
	(_player.get("affinity") as Dictionary)[skill_id] = 60.0
	_player.call("_check_family_milestones", skill_id)
	_hud = _player.get("hud")
	print("[AffinityShots] player ready: lv24 %s, specialized %s @60" % [class_id, skill_id])


func _open_pause() -> void:
	if _hud == null:
		return
	_hud.call("show_pause")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _scroll() -> ScrollContainer:
	# Pause menu now uses tabs; PauseScroll is under PauseMain.
	if _hud == null:
		return null
	return _hud.get_node("PausePanel/PauseMain/PauseScroll") as ScrollContainer


func _select_tab(idx: int) -> void:
	# 0=Stats, 1=Specialization, 2=Collection.
	if _hud != null and _hud.has_method("select_pause_tab"):
		_hud.call("select_pause_tab", idx)


func _scroll_to_spec() -> void:
	_select_tab(1)


func _scroll_to_bottom() -> void:
	_select_tab(2)


func _snap(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join("affinity_%s.png" % label)
	if img.save_png(path) == OK:
		print("[AffinityShots] saved ", path)
	else:
		push_error("[AffinityShots] FAILED " + path)
