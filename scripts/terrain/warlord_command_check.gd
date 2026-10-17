extends Node
## Issue #165 Part A validation driver: boots the REAL Warlord's
## Domain dungeon and drives the first-person command surface the
## way a player does — real input events through the player's own
## _input, real physics frames — and asserts Jesse's mouse rule
## end to end:
##
##   * entering FPS command mode leaves the mouse CAPTURED
##     (aim-driven targeting; the old surface un-captured it);
##   * a unit's PickArea answers a from-above ray on the pick
##     layer, and an aim + left-click selects the pointed
##     own-faction unit (ring visible);
##   * aim + right-click orders the selection: enemy -> attack,
##     empty ground -> move;
##   * an RTS menu opened from command mode un-captures for its
##     lifetime and closing re-captures; exiting command mode
##     leaves the mouse captured;
##   * the top-down camera keeps its free cursor (rule's other
##     half, regression guard).
##
## Run under Xvfb (mouse_mode needs a real display server):
##   xvfb-run godot --path . res://scenes/terrain/warlord_command_check.tscn
##
## This is a test harness only. Nothing here ships in gameplay.

var _pass := 0
var _fail := 0
var _dungeon: Node = null
var _player: Node = null


func _ready() -> void:
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	await get_tree().process_frame
	NetworkManager.selected_class_id = "warrior"
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "warlord"
	Dungeon.next_seed = 1
	Dungeon.next_level_number = 1
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	_dungeon = packed.instantiate()
	get_tree().root.add_child(_dungeon)
	get_tree().current_scene = _dungeon
	await _run_checks()
	print("[WARCMD] SUMMARY: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("[WARCMD] PASS: ", label)
	else:
		_fail += 1
		print("[WARCMD] FAIL: ", label)


func _run_checks() -> void:
	# Wait for the warlord setup: local player + RTS units on the field.
	var ready_ok := false
	for i in 3600:
		await get_tree().physics_frame
		var players := get_tree().get_nodes_in_group("players")
		if not players.is_empty() and not get_tree().get_nodes_in_group("rts_units").is_empty():
			_player = players[0]
			ready_ok = true
			break
	_check(ready_ok, "warlord boot: player + RTS units on the field")
	if not ready_ok:
		return
	_player.set("hp", 100000.0)
	var faction := int(_player.get("rts_faction"))
	var own := _first_unit(faction, true)
	var foe := _first_unit(faction, false)
	_check(own != null and foe != null, "own + enemy units present (faction %d)" % faction)
	if own == null or foe == null:
		return
	# PickArea: a fresh replica carries it, and the from-above ray
	# over the pick layer returns the pointed unit.
	var pick = own.get_node_or_null("PickArea")
	_check(pick != null and int(pick.get("collision_layer")) == 4,
		"PickArea on the unit, pick layer 3")
	var from: Vector3 = own.global_position + Vector3(0, 30, 0)
	var query := PhysicsRayQueryParameters3D.create(from, own.global_position + Vector3(0, -2, 0))
	query.collide_with_bodies = false
	query.collide_with_areas = true
	query.collision_mask = 4
	var hit: Dictionary = get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and (hit.get("collider") as Node).get_parent() == own,
		"from-above pick ray returns the pointed unit")
	# Enter command mode: the mouse must stay CAPTURED.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.call("_toggle_command_mode")
	_check(bool(_player.get("_command_mode")), "command mode entered")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"mouse stays CAPTURED entering FPS command mode")
	var marker_built := false
	for i in 120:
		await get_tree().physics_frame
		if _player.get("_aim_marker") != null:
			marker_built = true
			break
	_check(marker_built, "aim marker built in command mode")
	# Aim at the own unit and click: selection through real input.
	await _aim_at(own.global_position)
	_click(MOUSE_BUTTON_LEFT)
	var selected := false
	for i in 120:
		await get_tree().physics_frame
		if (_player.get("_command_selected") as Array).has(own):
			selected = true
			break
	_check(selected, "aim + click selects the pointed own unit")
	_check(own.get("_select_ring") != null and (own.get("_select_ring") as Node3D).visible,
		"selection ring visible on the selected unit")
	# Aim at the enemy and right-click: attack order.
	foe = _first_unit(faction, false)
	if foe != null and is_instance_valid(own):
		await _aim_at(foe.global_position)
		_click(MOUSE_BUTTON_RIGHT)
		var ordered := false
		for i in 120:
			await get_tree().physics_frame
			if is_instance_valid(own) and own.get("_attack_target") == foe:
				ordered = true
				break
		_check(ordered, "aim + right-click orders an attack on the enemy")
	# Aim at empty ground and right-click: move order.
	if is_instance_valid(own):
		own.set("_attack_target", null)
		var empty := own.global_position + Vector3(14, 0, 14)
		await _aim_at(empty)
		_click(MOUSE_BUTTON_RIGHT)
		var moved := false
		for i in 120:
			await get_tree().physics_frame
			if is_instance_valid(own) and own.get("_move_target") != Vector3.INF:
				moved = true
				break
		_check(moved, "aim + right-click on empty ground orders a move")
	# Menus own the cursor for their lifetime: open the build
	# menu, watch the mouse free, close it, watch it re-capture.
	var key := _action_key("build_menu")
	if key != 0:
		_key_press(key)
		var freed := false
		for i in 120:
			await get_tree().physics_frame
			if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
				freed = true
				break
		_check(freed, "build menu open un-captures the mouse")
		_key_press(key)
		var recap := false
		for i in 120:
			await get_tree().physics_frame
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				recap = true
				break
		_check(recap, "build menu closed re-captures the mouse")
	else:
		_check(false, "build_menu action has a key binding to drive")
	# The leak shape (auditor I7): exiting command mode WHILE a
	# menu is open must still land captured — the exit assignment
	# is unconditional, menu or not.
	if key != 0:
		_key_press(key)
		var freed2 := false
		for i in 120:
			await get_tree().physics_frame
			if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
				freed2 = true
				break
		_check(freed2, "build menu re-opened (exit-leak setup)")
	# Exit command mode: captured, marker gone.
	_player.call("_toggle_command_mode")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"mouse CAPTURED after exiting command mode")
	_check(_player.get("_aim_marker") == null, "aim marker freed on exit")
	# The rule's other half: top-down keeps its free cursor.
	var rts_cam = get_tree().get_first_node_in_group("rts_camera")
	if rts_cam != null:
		rts_cam.call("toggle")
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"top-down command view frees the cursor")
		await _check_camera_orders(rts_cam, faction)
		rts_cam.call("toggle")
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
			"leaving top-down re-captures")


## Camera-half F1 pins, behavioral in-scene (gate M2): the real
## top-down camera selects and orders real units through its own
## input path — click select, right-click move/attack, and a
## build-menu placement confirmed by a real click.
func _check_camera_orders(rts_cam: Node, faction: int) -> void:
	var mgr = get_tree().get_first_node_in_group("rts_manager")
	if rts_cam.get("_manager") == null and mgr != null:
		rts_cam.call("setup", mgr, faction)
	var fighter = _first_unit(faction, true)
	_check(fighter != null, "camera legs: an own unit is available")
	if fighter == null:
		return
	_cam_click(rts_cam, fighter.global_position, MOUSE_BUTTON_LEFT)
	var sel := false
	for i in 120:
		await get_tree().physics_frame
		if (rts_cam.get("_selected") as Array).has(fighter):
			sel = true
			break
	_check(sel, "camera click selects the unit")
	var dest: Vector3 = fighter.global_position + Vector3(12, 0, 0)
	_cam_click(rts_cam, dest, MOUSE_BUTTON_RIGHT)
	var mv := false
	for i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(fighter):
			break
		var mt: Vector3 = fighter.get("_move_target")
		if mt != Vector3.INF and mt.distance_to(dest) < 2.0:
			mv = true
			break
	_check(mv, "camera right-click orders a move (host direct path)")
	var foe2 = _first_unit(faction, false)
	if foe2 != null and is_instance_valid(fighter):
		_cam_click(rts_cam, foe2.global_position, MOUSE_BUTTON_RIGHT)
		var atk := false
		for i in 120:
			await get_tree().physics_frame
			if is_instance_valid(fighter) and fighter.get("_attack_target") == foe2:
				atk = true
				break
		_check(atk, "camera right-click orders an attack (host direct path)")
	# Placement: select a villager, take the build menu's real
	# callback into placement, confirm with a real click.
	var vil: Node3D = null
	for n in get_tree().get_nodes_in_group("rts_units"):
		if int(n.get("faction")) == faction and str(n.get("unit_type")) == "villager" and bool(n.get("alive")):
			vil = n
			break
	_check(vil != null, "camera legs: a villager is available for placement")
	if vil == null or mgr == null:
		return
	mgr.add_resource(faction, "wood", 500)
	_cam_click(rts_cam, vil.global_position, MOUSE_BUTTON_LEFT)
	for i in 120:
		await get_tree().physics_frame
		if (rts_cam.get("_selected") as Array).has(vil):
			break
	var rhud = _dungeon.get_node_or_null("RTSHUD")
	if rhud != null and rhud.has_method("_on_build_button"):
		rhud.call("_on_build_button", "barracks")
	_check(str(rts_cam.get("_placing_type")) == "barracks",
		"camera enters placement from the build menu")
	var spot := Vector3.INF
	for off in [Vector3(10, 0, 10), Vector3(14, 0, 0), Vector3(0, 0, 14), Vector3(-12, 0, 8), Vector3(18, 0, -6)]:
		var cand: Vector3 = vil.global_position + off
		cand.y = 0.0
		if bool(rts_cam.call("_is_valid_build_spot", cand)):
			spot = cand
			break
	_check(spot != Vector3.INF, "camera legs: a valid build spot found")
	if spot == Vector3.INF:
		return
	var bcount := get_tree().get_nodes_in_group("rts_buildings").size()
	_cam_click(rts_cam, spot, MOUSE_BUTTON_LEFT)
	var placed := false
	var fresh_b: Node3D = null
	for i in 180:
		await get_tree().physics_frame
		if get_tree().get_nodes_in_group("rts_buildings").size() == bcount + 1:
			placed = true
			for b in get_tree().get_nodes_in_group("rts_buildings"):
				if (b as Node3D).global_position.distance_to(spot) < 1.5:
					fresh_b = b
			break
	_check(placed, "camera placement click lands a building (host direct path)")
	if fresh_b != null:
		_cam_click(rts_cam, fresh_b.global_position, MOUSE_BUTTON_RIGHT)
		var bt := false
		for i in 120:
			await get_tree().physics_frame
			if is_instance_valid(vil) and vil.get("_build_target") == fresh_b:
				bt = true
				break
		_check(bt, "camera right-click orders the villager to build")


## Click through the real camera input at a world position:
## park the camera above the point and dispatch press+release
## at its projected screen position.
func _cam_click(cam: Node, world: Vector3, button: int) -> void:
	cam.set("position", Vector3(world.x, 40.0, world.z))
	var sp: Vector2 = (cam as Camera3D).unproject_position(world)
	# A real hand moves before it clicks — the placement ghost's
	# validity is motion-driven, so dispatch the motion first.
	var motion := InputEventMouseMotion.new()
	motion.position = sp
	Input.parse_input_event(motion)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = sp
	Input.parse_input_event(ev)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = sp
	Input.parse_input_event(up)


func _first_unit(faction: int, own_side: bool) -> Node3D:
	for n in get_tree().get_nodes_in_group("rts_units"):
		if not bool(n.get("alive")):
			continue
		if (int(n.get("faction")) == faction) == own_side:
			return n
	return null


## Park the player 6 m south of the target, face it, pitch the
## aim down, and wait until the per-frame aim lands on it.
func _aim_at(target: Vector3) -> void:
	var pp := target + Vector3(0, 0, 6)
	pp.y = target.y + 0.2
	_player.set("global_position", pp)
	_player.set("rotation", Vector3.ZERO)
	_player.set("_yaw", 0.0)
	_player.set("_pitch", -0.26)
	# _pitch reaches the camera only through the look handlers;
	# apply it exactly as the mouse-motion handler does.
	var cam = _player.get("_camera")
	if cam != null:
		(cam as Node3D).rotation.x = -0.26
	for i in 240:
		await get_tree().physics_frame
		var aim: Vector3 = _player.get("_command_aim")
		if aim != Vector3.INF and Vector2(aim.x - target.x, aim.z - target.z).length() < 1.2:
			return


func _click(button: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)


func _key_press(code: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _action_key(action: String) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return (ev as InputEventKey).physical_keycode
	return 0
