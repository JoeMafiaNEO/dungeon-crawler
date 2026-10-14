extends Node
## Jesse 2026-10-13 validation driver: inventory as an alternative
## pause screen. Boots the REAL dungeon and drives the local player
## through the game's own input path (synthetic key events, like the
## terrain checks):
##   damage lands -> I opens the panel (mouse freed, panel centered,
##   world NOT paused) -> mob-path damage is gated while open, and a
##   real goblin closes to melee and swings without scratching the
##   player -> Esc swaps to the pause UI (exactly one panel up) ->
##   pause breather still gates -> Resume closes everything (mouse
##   recaptured, damage lands again) -> I/I toggle-close also clean.
##
## Run under Xvfb (mouse_mode needs a real display driver):
##   xvfb-run godot --path . --resolution 1920x1080 res://scenes/ui/inventory_pause_check.tscn
##
## This is a test harness only. Nothing here ships in gameplay.

var _pass := 0
var _fail := 0
var _dungeon: Dungeon = null
var _player: Player = null
var _hud: CanvasLayer = null
var _inv_panel: Control = null
var _pause_panel: Control = null
var _shot_dir := "/home/hatch/workspace/inventory_pause_shots"


func _ready() -> void:
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	await get_tree().process_frame
	NetworkManager.selected_class_id = "warrior"
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "dungeon"
	Dungeon.next_seed = 424242
	Dungeon.next_level_number = 1
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	_dungeon = packed.instantiate() as Dungeon
	get_tree().root.add_child(_dungeon)
	get_tree().current_scene = _dungeon
	for i in 12:
		await get_tree().physics_frame
	var players := get_tree().get_nodes_in_group("players")
	_check(players.size() > 0, "player spawned")
	if players.is_empty():
		_finish()
		return
	_player = players[0] as Player
	_hud = _player.get("hud") as CanvasLayer
	_check(_hud != null, "player hud bound")
	_inv_panel = _hud.find_child("InventoryPanel", true, false) as Control
	_pause_panel = _hud.find_child("PausePanel", true, false) as Control
	_check(_inv_panel != null and _pause_panel != null, "both panels exist")
	await _run_checks()
	_finish()


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("[INVP] PASS: ", label)
	else:
		_fail += 1
		print("[INVP] FAIL: ", label)


func _finish() -> void:
	print("[INVP] SUMMARY: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = code
	ev2.pressed = false
	Input.parse_input_event(ev2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Synthetic input flushes and Control layout settle per PROCESS
## frame; under load several physics ticks can share one iteration,
## so key-driven steps wait on process frames, not physics frames.
func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Damage delivered exactly the way mob.gd delivers it.
func _mob_hit(amount: float) -> void:
	_player.rpc_id(_player.get_multiplayer_authority(), "take_damage", amount, "check goblin")


func _run_checks() -> void:
	_check(not get_tree().paused, "tree not paused at boot")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse captured in gameplay")
	_check(not bool(_hud.get("inventory_open")) and not _inv_panel.visible, "inventory closed at boot")

	# The damage seam is live before the panel opens (mob-shaped rpc).
	_player.hp = _player.max_hp
	_mob_hit(10.0)
	await _frames(3)
	_check(absf(_player.hp - (_player.max_hp - 10.0)) < 0.01,
		"damage lands while inventory closed (hp %.1f)" % _player.hp)

	# A real goblin in front of the player: world-life witness.
	var fwd := -_player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var mpos := _player.global_position + fwd * 2.8
	mpos.y = _player.global_position.y
	_dungeon.spawn_mob(9001, "goblin", mpos)
	await _frames(6)
	var mobs := get_tree().get_nodes_in_group("mobs")
	_check(mobs.size() > 0, "goblin spawned via spawn_mob")
	var goblin: Node3D = mobs[0] as Node3D if mobs.size() > 0 else null

	# --- Open the inventory through the real I-key path. ---
	_key(KEY_I)
	await _settle(4)
	await _frames(2)
	_check(bool(_hud.get("inventory_open")), "I opens inventory (state)")
	_check(_inv_panel.visible, "I opens inventory (panel visible)")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse uncaptured while open")
	_check(not get_tree().paused, "tree NOT paused while open (solo == MP rule)")
	# Centered: panel rect center == viewport center.
	var vp_center := get_viewport().get_visible_rect().size * 0.5
	var panel_center := _inv_panel.get_global_rect().get_center()
	_check(absf(panel_center.x - vp_center.x) <= 2.0 and absf(panel_center.y - vp_center.y) <= 2.0,
		"panel centered (center %s vs viewport %s)" % [str(panel_center), str(vp_center)])
	await _take_shot()

	# --- Damage is gated while open (mob-shaped rpc). ---
	var hp_open := _player.hp
	_mob_hit(25.0)
	await _frames(3)
	_check(absf(_player.hp - hp_open) < 0.01, "damage gated while inventory open")

	# --- The world keeps running while the panel is open. ---
	if goblin != null:
		var start_pos := goblin.global_position
		var closed_in := false
		for i in 480: # up to ~8s of physics
			await get_tree().physics_frame
			if not is_instance_valid(goblin):
				break
			if goblin.global_position.distance_to(_player.global_position) < 2.3:
				closed_in = true
				break
		_check(goblin.global_position.distance_to(start_pos) > 0.2 or closed_in,
			"goblin moved while panel open (world running)")
		_check(closed_in, "goblin closed to melee range while panel open")
		# Let it actually swing: _attack_cd resets to the full
		# cooldown when a melee swing fires.
		var swung := false
		for i in 300: # up to ~5s
			await get_tree().physics_frame
			if not is_instance_valid(goblin):
				break
			if float(goblin.get("_attack_cd")) > 0.05:
				swung = true
				break
		_check(swung, "goblin swung at the player while panel open")
		_check(absf(_player.hp - hp_open) < 0.01,
			"real goblin melee dealt no damage while open (hp %.1f)" % _player.hp)
		_check(not get_tree().paused, "tree still not paused after combat while open")

	# --- Esc swaps inventory -> pause UI, exactly one panel up. ---
	_key(KEY_ESCAPE)
	await _settle(4)
	await _frames(2)
	_check(not bool(_hud.get("inventory_open")) and not _inv_panel.visible,
		"Esc swap: inventory closed")
	_check(bool(_hud.get("is_paused")) and _pause_panel.visible, "Esc swap: pause UI visible")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Esc swap: mouse stays free for pause")
	_mob_hit(25.0)
	await _frames(3)
	_check(absf(_player.hp - hp_open) < 0.01, "pause breather still gates after swap")

	# --- Resume closes everything: capture + damage restored. ---
	var resume_btn := _hud.find_child("ResumeButton", true, false) as Button
	_check(resume_btn != null, "resume button found")
	if resume_btn != null:
		resume_btn.pressed.emit()
	await _settle(3)
	await _frames(2)
	_check(not _pause_panel.visible and not _inv_panel.visible, "resume: both panels closed")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "resume: mouse recaptured")
	_mob_hit(15.0)
	await _frames(3)
	_check(absf(_player.hp - (hp_open - 15.0)) < 0.01,
		"damage lands again after resume (hp %.1f)" % _player.hp)

	# --- Toggle-close via I is equally clean. ---
	_key(KEY_I)
	await _settle(4)
	await _frames(2)
	_check(bool(_hud.get("inventory_open")) and _inv_panel.visible, "I reopens inventory")
	_key(KEY_I)
	await _settle(4)
	await _frames(2)
	_check(not bool(_hud.get("inventory_open")) and not _inv_panel.visible, "I closes inventory")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "toggle-close: mouse recaptured")
	var hp_now := _player.hp
	_mob_hit(5.0)
	await _frames(3)
	_check(absf(_player.hp - (hp_now - 5.0)) < 0.01, "damage lands after toggle-close")
	_check(not get_tree().paused, "tree never paused (final)")


func _take_shot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir + "/inventory_centered.png")
	print("[INVP] shot saved: inventory_centered.png (%dx%d)" % [img.get_width(), img.get_height()])
