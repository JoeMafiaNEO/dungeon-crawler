extends Node
## Issue #102 Phase 5: misty docks screenshot driver. Boots a real solo
## misty-docks run and captures 1920x1080 inspection shots:
##   01_docks_overview.png   FPS view from spawn across the arena
##   02_water_ponds.png      pond + pier + reeds + lantern from the pier
##   03_farm_plots.png       farm plot close-up (tilled/planted/growing)
##   04_fishing_waiting.png  bobber floating mid-pond, line out
##   05_fishing_bite.png     bite moment (splash + "!" cue)
##   06_fishing_caught.png   reel-in lift just after the catch
##   07_vendor_ui.png        dock merchant UI open, farm cash balance
## Run under Xvfb:
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --resolution 1920x1080 \
##     res://tools/docks_shots/docks_shots.tscn -- --shot-dir=/path/to/shots
## Scratch account only; never touches the real user:// saves.

var _shot_dir := "/home/hatch/workspace/misty_docks_phase5_shots"
var _player: Node = null
var _dungeon: Node = null
var _hidden_layers: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	get_viewport().size = Vector2i(1920, 1080)
	print("[DocksShots] output -> ", _shot_dir)
	_boot()


func _boot() -> void:
	var crt = get_node_or_null("/root/CRTManager")
	if crt != null and crt.has_method("set_crt_enabled"):
		crt.set_crt_enabled(false)
	SaveManager.set("_test_account_pin", "docks_shots")
	SaveManager.set("_test_runs_dir", "user://runs_scratch_dockshots")
	SaveManager.load_game()
	NetworkManager.selected_class_id = "warrior"
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "misty_docks"
	Dungeon.next_seed = 424242
	Dungeon.next_level_number = 1
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	var inst := packed.instantiate()
	get_tree().root.add_child.call_deferred(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = inst
	await get_tree().create_timer(8.0).timeout
	_dungeon = get_tree().get_first_node_in_group("dungeon")
	for n in get_tree().get_nodes_in_group("players"):
		_player = n as Node
		break
	if _dungeon == null or _player == null:
		push_error("[DocksShots] no dungeon/player — aborting")
		_cleanup()
		return
	print("[DocksShots] dungeon ready: spots=%d plots=%d" % [
		get_tree().get_nodes_in_group("fishing_spots").size(),
		get_tree().get_nodes_in_group("farm_plots").size()])
	_shoot_all()


func _shoot_all() -> void:
	# Scenic shots: hide every CanvasLayer (HUD) for a clean frame.
	_hide_hud()
	await get_tree().create_timer(0.4).timeout
	_overview_shot()
	await _settle(0.8)
	await _snap("01_docks_overview.png")
	_pond_shot()
	await _settle(0.8)
	await _snap("02_water_ponds.png")
	await _farm_shot()
	await _settle(0.8)
	await _snap("03_farm_plots.png")
	await _fishing_waiting_shot()
	await _snap("04_fishing_waiting.png")
	await _bite_and_catch_shots()
	_vendor_shot()
	await _settle(1.2)
	await _snap("07_vendor_ui.png")
	print("[DocksShots] all shots captured")
	_cleanup()


func _spots() -> Array:
	var s := get_tree().get_nodes_in_group("fishing_spots")
	s.sort_custom(func(a, b): return a.spot_index < b.spot_index)
	return s


func _plots() -> Array:
	var s := get_tree().get_nodes_in_group("farm_plots")
	s.sort_custom(func(a, b): return a.plot_index < b.plot_index)
	return s


func _clear_mobs() -> void:
	for m in get_tree().get_nodes_in_group("mobs"):
		m.queue_free()


func _overview_shot() -> void:
	var spawns: Array = _dungeon.get("spawn_points")
	_player.global_position = spawns[0] + Vector3(0, 0.3, 0)
	# Face the arena's mesh centroid (level_shots' proven pattern; elevated
	# shots fog out under the exponential theme fog).
	var box := AABB()
	var got := false
	for mi in _dungeon.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if not got else box.merge(b)
		got = true
	var target: Vector3 = box.get_center() if got else (spawns[0] as Vector3)
	_player.look_at(Vector3(target.x, _player.global_position.y, target.z), Vector3.UP)
	print("[DocksShots] overview: facing ", target)


func _pond_shot() -> void:
	var spot = _spots()[0]
	var pond_center: Vector3 = spot.water_point
	_player.global_position = spot.global_position + Vector3(0, 0.3, 0)
	_player.look_at(Vector3(pond_center.x, _player.global_position.y, pond_center.z), Vector3.UP)
	print("[DocksShots] pond: at pier, facing ", pond_center)


func _farm_shot() -> void:
	# Prep plot 0 through till + plant + 3 waves so the shot shows the
	# tilled soil, crop visuals and a harvestable state (real paths, no
	# test seams — this is a live server instance).
	_clear_mobs()
	var plot = _plots()[0]
	FarmPlot.grant_starter_seeds(1)
	for s in FarmPlot.STARTER_SEED_COUNT:
		_player.call("receive_item", FarmPlot.SEED_ITEM)
	_player.global_position = plot.global_position + Vector3(0, 0.3, 0)
	plot.plot_action() # till
	plot.plot_action() # plant
	plot.on_wave_cleared()
	plot.on_wave_cleared()
	plot.on_wave_cleared()
	print("[DocksShots] farm: plot0 state=", plot.plot_state)
	var look: Vector3 = plot.global_position + Vector3(2.0, 0, 1.5)
	_player.global_position = plot.global_position + Vector3(-3.5, 0.3, -4.5)
	_player.look_at(Vector3(look.x, _player.global_position.y, look.z), Vector3.UP)


func _fishing_waiting_shot() -> void:
	_clear_mobs()
	var spot = _spots()[0]
	_player.global_position = spot.global_position + Vector3(0, 0.3, 0)
	var pond_center: Vector3 = spot.water_point
	_player.look_at(Vector3(pond_center.x, _player.global_position.y, pond_center.z), Vector3.UP)
	FishingSpot.debug_wait_override = 30.0 # long wait: stays in WAITING for the shot
	spot.fish_action()
	await get_tree().create_timer(2.0).timeout
	var vis0 = spot.get("_visual")
	print("[DocksShots] waiting: session=", spot._session_state, " (1=WAITING)",
		" visual=", vis0 != null,
		" bobber=", (vis0.bobber_position() if vis0 != null else Vector3.ZERO),
		" player=", _player.global_position)
	# Cancel by walking away so the next cast re-arms cleanly.
	_player.global_position = spot.global_position + Vector3(6.0, 0, 0)
	await get_tree().create_timer(0.6).timeout
	_player.global_position = spot.global_position + Vector3(0, 0.3, 0)
	FishingSpot.debug_wait_override = -1.0
	print("[DocksShots] waiting: after walk-away occupied=", spot.occupied_by)


func _bite_and_catch_shots() -> void:
	_clear_mobs()
	var spot = _spots()[0]
	var pond_center: Vector3 = spot.water_point
	_player.global_position = spot.global_position + Vector3(0, 0.3, 0)
	_player.look_at(Vector3(pond_center.x, _player.global_position.y, pond_center.z), Vector3.UP)
	FishingSpot.debug_wait_override = 1.2
	FishingSpot.debug_catch_roll = -1.0
	# Frozen-clock protocol (the suite's debug_now seam): at this VM's
	# software-GL frame rate, real-time polling overruns the 1.2s reel
	# window before the capture lands. Freeze the session clock, step it
	# past the bite roll by hand, and the bite holds indefinitely.
	FishingSpot.debug_now_msec = 900000
	spot.fish_action()
	# Let the cast arc finish in real time first (0.75s): the "!" cue is
	# positioned over the bobber only in the visual's bobbing phase, so a
	# bite forced mid-arc would photograph the cue at the pier instead.
	await get_tree().create_timer(1.1).timeout
	FishingSpot.debug_now_msec = 900000 + 1300 # past the 1.2s wait roll
	spot._process(0.016) # server tick: bite fires, deadline = frozen now + 1200
	if spot._session_state != FishingSpot.SessionState.BITING:
		push_error("[DocksShots] bite never fired — skipping bite/catch shots")
		FishingSpot.debug_now_msec = -1
		FishingSpot.debug_wait_override = -1.0
		return
	var vis = spot.get("_visual")
	print("[DocksShots] BITE fired (frozen clock); visual=", vis != null,
		" bang visible=", (vis.get("_bang").visible if vis != null and vis.get("_bang") != null else "n/a"),
		" bobber=", (vis.bobber_position() if vis != null else Vector3.ZERO))
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("05_fishing_bite.png")
	spot.reel_attempt() # frozen now <= deadline: catch resolves
	print("[DocksShots] after reel: session=", spot._session_state, " (0=NONE)")
	await get_tree().create_timer(0.18).timeout # mid lift, before the visual frees (0.45s)
	await _snap("06_fishing_caught.png")
	FishingSpot.debug_now_msec = -1
	FishingSpot.debug_wait_override = -1.0
	print("[DocksShots] catch resolved")


func _vendor_shot() -> void:
	# Restore HUD (the vendor panel is UI), grant a balance + one sellable.
	for cl in _hidden_layers:
		if is_instance_valid(cl):
			(cl as CanvasLayer).visible = true
	_hidden_layers.clear()
	_clear_mobs()
	var merch = get_tree().get_first_node_in_group("dock_merchant")
	_player.global_position = merch.global_position + Vector3(0, 0.3, 3.2)
	_player.look_at(Vector3(merch.global_position.x, _player.global_position.y,
		merch.global_position.z), Vector3.UP)
	DockEconomy.grant_cash(1, 14)
	for i in 14:
		_player.call("receive_item", "farm_cash")
	DockEconomy.grant_stock(1, "fish_riverbass", 1)
	_player.call("receive_item", "fish_riverbass")
	merch.interact(_player)
	print("[DocksShots] vendor open: balance=", DockEconomy.cash_balance(1))


func _hide_hud() -> void:
	_hidden_layers.clear()
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		_hidden_layers.append(cl)
		(cl as CanvasLayer).visible = false
	await get_tree().process_frame
	await get_tree().process_frame


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	_clear_mobs()


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_dir + "/" + name)
	print("[DocksShots] saved ", name, " (err=", err, ")")


func _cleanup() -> void:
	SaveManager.set("_test_account_pin", "")
	SaveManager.set("_test_runs_dir", "")
	FishingSpot.debug_wait_override = -1.0
	if DirAccess.dir_exists_absolute("user://runs_scratch_dockshots"):
		OS.move_to_trash("user://runs_scratch_dockshots")
	print("[DocksShots] done")
	get_tree().quit()
