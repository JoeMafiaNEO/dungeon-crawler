extends Node
## Ember Foundry validation screenshots (issue #85 Phase 4). Run under Xvfb:
##   xvfb-run -a godot --path . --resolution 1920x1080 res://tools/foundry_shots/foundry_shots.tscn -- --shot-dir /tmp/foundry_shots
## Captures: forge floors + molten channels + ember fall, all 4 mobs,
## imp explosion fuse telegraph, golem armor phase tell.

var _shot_dir := "/tmp/foundry_shots"
const SCRATCH_ACCOUNT := "foundry_shots"
const SCRATCH_RUNS_DIR := "user://runs_scratch_foundry"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.set("_test_account_pin", SCRATCH_ACCOUNT)
	SaveManager.set("_test_runs_dir", SCRATCH_RUNS_DIR)
	SaveManager.load_game()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot-dir" and i + 1 < args.size():
			_shot_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	print("[FoundryShots] output -> ", _shot_dir)
	NetworkManager.selected_class_id = "warrior"
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "ember_foundry"
	Dungeon.next_seed = 987654
	Dungeon.next_level_number = 3
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	var inst := packed.instantiate()
	get_tree().root.add_child.call_deferred(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = inst
	# Let the level build (motes, props, mobs).
	await get_tree().create_timer(6.0).timeout
	_shot("01_foundry_theme")
	# Spawn each mob in front of the camera for close-ups.
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	var player: Node3D = _find_player()
	if player == null or dungeon == null:
		push_error("[FoundryShots] no player/dungeon")
		_cleanup()
		return
	var base: Vector3 = player.global_position + Vector3(0, 0, -6.0)
	# Phase 4: buff player HP so mobs don't kill during screenshots.
	player.set("max_hp", 99999.0)
	player.set("hp", 99999.0)
	# Cinder imp.
	var imp = await _spawn_mob(dungeon, "cinder_imp", base)
	await get_tree().create_timer(1.0).timeout
	_shot("02_cinder_imp")
	# Imp fuse telegraph: force-damage to trigger fuse, screenshot mid-flash.
	if imp != null:
		imp.take_damage(9999.0, 1, player.global_position)
		await get_tree().create_timer(0.25).timeout
		_shot("03_imp_fuse_telegraph")
		await get_tree().create_timer(1.0).timeout  # Let it detonate.
	# Bellows hound.
	var hound = await _spawn_mob(dungeon, "bellows_hound", base + Vector3(3, 0, 0))
	await get_tree().create_timer(1.0).timeout
	_shot("04_bellows_hound")
	# Slag spitter.
	var spitter = await _spawn_mob(dungeon, "slag_spitter", base + Vector3(-3, 0, 0))
	await get_tree().create_timer(1.0).timeout
	_shot("05_slag_spitter")
	# Force the spitter to fire a lava glob.
	if spitter != null:
		spitter.set("_attack_cd", 0.0)
		await get_tree().create_timer(1.5).timeout
		_shot("06_lava_glob")
	# Forge golem + armor phase tell: damage to 50% (phase 1).
	var golem = await _spawn_mob(dungeon, "forge_golem", base + Vector3(0, 0, 3))
	await get_tree().create_timer(1.0).timeout
	_shot("07_forge_golem")
	if golem != null:
		var max_hp: float = golem.get("max_hp") if golem.get("max_hp") != null else 180.0
		golem.take_damage(max_hp * 0.45, 1, player.global_position)
		await get_tree().create_timer(0.5).timeout
		_shot("08_golem_armor_phase1")
		golem.take_damage(max_hp * 0.35, 1, player.global_position)
		await get_tree().create_timer(0.5).timeout
		_shot("09_golem_armor_phase2")
	print("[FoundryShots] all shots captured")
	_cleanup()


func _spawn_mob(dungeon: Node, mob_id: String, pos: Vector3):
	if not dungeon.has_method("server_spawn_mob"):
		return null
	var mob = dungeon.call("server_spawn_mob", mob_id, pos)
	await get_tree().process_frame
	# server_spawn_mob may return the mob or null; find it.
	if mob == null:
		for n in get_tree().get_nodes_in_group("mobs"):
			if n.get("data") != null and str(n.get("data").get("id")) == mob_id:
				var np: Vector3 = n.global_position
				if np.distance_to(pos) < 3.0:
					return n
	return mob


func _find_player():
	for n in get_tree().get_nodes_in_group("players"):
		return n
	return null


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_shot_dir, name]
	img.save_png(path)
	print("[FoundryShots] saved ", path)


func _cleanup() -> void:
	# Scratch isolation: never touch real saves.
	SaveManager.set("_test_account_pin", "")
	SaveManager.set("_test_runs_dir", "")
	if DirAccess.dir_exists_absolute(SCRATCH_RUNS_DIR):
		OS.move_to_trash(SCRATCH_RUNS_DIR)
	get_tree().quit()
