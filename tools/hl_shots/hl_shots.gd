extends Node
## Issue #91 Phase 3: Holy Light v2 screenshot driver. Run under Xvfb:
##   godot --path . res://tools/hl_shots/hl_shots.tscn --resolution 1920x1080 -- --shot-dir /tmp/hl_shots
## Captures: armed reticle, charge, mid-sweep x2, wind-down.

var _shot_dir := "/tmp/hl_shots"
var _t0 := 0
var _phase := 0
var _player: Node = null
var _t_phase := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	_t0 = Time.get_ticks_msec()
	print("[HLShots] output -> ", _shot_dir)
	_boot_dungeon()


func _elapsed() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


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
	print("[HLShots] dungeon booted")


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		_player = players[0]


func _setup_player() -> void:
	# Mage with Holy Light equipped, aura 20.
	_player.set("class_id", "mage")
	_player.set("bonus_aura", 20.0)
	_player.call("_push_aura")
	var SD: GDScript = load("res://scripts/data/special_data.gd")
	SD.earn("holy_light")
	SD.equip(_player, "holy_light")
	# Position for a clear view.
	_player.global_position = Vector3(0, 0, 0)


func _shot(name: String) -> void:
	var path := _shot_dir + "/" + name + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("[HLShots] saved ", path)


func _process(delta: float) -> void:
	var t := _elapsed()
	match _phase:
		0:
			_find_player()
			if _player != null:
				_setup_player()
				_phase = 1
				_t_phase = t
			elif t > 60.0:
				push_error("[HLShots] player never spawned")
				get_tree().quit()
		1:
			# Wait 2s for scene to settle, then arm Holy Light.
			if t - _t_phase > 2.0:
				_player.call("_hl_arm")
				_phase = 2
				_t_phase = t
		2:
			# Armed: screenshot the gold reticle.
			if t - _t_phase > 1.0:
				_shot("hl_armed_reticle")
				# Start charge.
				_player.call("_hl_start_charge")
				_phase = 3
				_t_phase = t
		3:
			# Charge: screenshot mid-charge (reticle pulsing).
			if t - _t_phase > 0.5:
				_shot("hl_charge")
				# Force the strike (don't rely on _process timing under Xvfb).
				_player.set("_hl_charge_t", 1.0)
				_player.call("_hl_strike")
				_phase = 4
				_t_phase = t
		4:
			# Beam is active: position at first aim point, screenshot mid-sweep.
			if t - _t_phase > 1.0:
				var aim1: Vector3 = _player.global_position + Vector3(5, 0, 5)
				_player.set("_hl_aim", aim1)
				# Move the beam container directly.
				for b in _player.get("_hl_beams").values():
					var n: Node3D = b.get("node")
					if n != null and is_instance_valid(n):
						n.global_position = aim1
				_phase = 5
				_t_phase = t
		5:
			if t - _t_phase > 2.0:
				_shot("hl_mid_sweep_1")
				# Move to second aim point.
				var aim2: Vector3 = _player.global_position + Vector3(-5, 0, 8)
				_player.set("_hl_aim", aim2)
				for b in _player.get("_hl_beams").values():
					var n2: Node3D = b.get("node")
					if n2 != null and is_instance_valid(n2):
						n2.global_position = aim2
				_phase = 6
				_t_phase = t
		6:
			if t - _t_phase > 2.0:
				_shot("hl_mid_sweep_2")
				_phase = 7
				_t_phase = t
		7:
			# Wait for wind-down (10s hold), then screenshot.
			# For the shot, we fast-forward by setting _hl_active_t.
			if t - _t_phase > 1.0:
				_player.set("_hl_active_t", 10.5)  # Mid wind-down
				_phase = 8
				_t_phase = t
		8:
			if t - _t_phase > 0.5:
				_shot("hl_winddown")
				print("[HLShots] done")
				get_tree().quit()
