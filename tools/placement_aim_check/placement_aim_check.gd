extends Node
## Issue #232 rendered check: the placement aim phase
## in the real game — an armed totem (aura ring + the
## 8 m range ring, legend reading Place / Cancel), a
## blizzard armed with the camera pitched up so the
## reticle rests ON the 20 m range ring (the clamp,
## felt), and an armed bulwark wall (the 3.0 x 0.6
## footprint box). Boots the real dungeon as host.
## Run under Xvfb.

const SHOT_DIR := "/home/hatch/workspace/placement-aim-shots"

var _frames := 0
var _player: Node = null
var _phase := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_boot.call_deferred()


func _boot() -> void:
	await get_tree().process_frame
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	NetworkManager.selected_class_id = "warrior"
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
	var inst := (load("res://scenes/dungeon/dungeon.tscn")
		as PackedScene).instantiate()
	tree.root.add_child(inst)
	tree.current_scene = inst
	print("[AIM232] dungeon booted")


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("players")
	if not players.is_empty():
		_player = players[0]


func _snap(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := SHOT_DIR.path_join(fname)
	if img.save_png(path) == OK:
		print("[AIM232] saved ", path)
	else:
		print("[AIM232] FAIL saving ", path)


func _process(_delta: float) -> void:
	_frames += 1
	if _player == null:
		if _frames > 30:
			_find_player()
		return
	match _phase:
		0:
			# Warrior: arm the totem through the real
			# ability trigger; pitch down a touch so
			# both rings read on the ground.
			_player.set("_pitch", -0.18)
			var cam0 = _player.get("_camera")
			if cam0 != null:
				cam0.rotation.x = -0.18
			_player.call("_use_class_ability")
			print("[AIM232] armed: ", _player.get("_aim_ability"))
			_phase = 1
		1:
			if _frames % 50 == 0:
				_snap("aim_totem.png")
				_phase = 2
		2:
			# Mage: switch, give blizzard, pitch the
			# camera up so the aim runs to the clamp.
			_player.call("switch_class", "mage")
			_player.set("unlocked_abilities", [
				{"id": "fireball", "name": "Fireball", "unlock": 1, "key": "1", "desc": "x"},
				{"id": "blizzard", "name": "Blizzard", "unlock": 7, "key": "2", "desc": "y"}])
			_player.set("selected_ability", 1)
			var hud2 = _player.get("hud")
			if hud2 != null:
				hud2.call("refresh_abilities", _player)
			_player.call("_cast_spell")
			print("[AIM232] armed: ", _player.get("_aim_ability"))
			_phase = 3
		3:
			# Nearly level: the 20 m ray outruns the
			# ground, so the reticle lands clamped at
			# exactly 20 m, resting on the range ring.
			_player.set("_pitch", -0.03)
			var cam = _player.get("_camera")
			if cam != null:
				cam.rotation.x = -0.03
			if _frames % 50 == 0:
				_snap("aim_blizzard_clamp.png")
				_phase = 4
		4:
			_player.set("_pitch", -0.35)
			var cam2 = _player.get("_camera")
			if cam2 != null:
				cam2.rotation.x = -0.35
			_player.call("switch_class", "architect")
			_player.set("unlocked_abilities", [
				{"id": "sentry_turret", "name": "Sentry Turret", "unlock": 1, "key": "1", "desc": "x"},
				{"id": "bulwark_wall", "name": "Bulwark Wall", "unlock": 4, "key": "2", "desc": "y"}])
			_player.set("selected_ability", 1)
			var hud3 = _player.get("hud")
			if hud3 != null:
				hud3.call("refresh_abilities", _player)
			_player.call("_cast_architect_ability")
			print("[AIM232] armed: ", _player.get("_aim_ability"))
			_phase = 5
		5:
			if _frames % 50 == 0:
				_snap("aim_wall.png")
				get_tree().quit(0)
