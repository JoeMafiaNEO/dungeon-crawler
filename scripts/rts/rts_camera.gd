class_name RTSCamera
extends Camera3D
## Top-down RTS camera. Press Tab to toggle between FPS and command view.
## Left-click/drag to select, right-click to order.

var active := false
var faction_id := 0
var _manager: RTSManager = null
var _selected: Array = []
var _drag_start := Vector2.INF
var _drag_box: Panel = null
var _pan_speed := 20.0
var _zoom := 40.0
# Building placement mode.
var _placing_type := ""
var _ghost: MeshInstance3D = null
var _ghost_valid := false


func _ready() -> void:
	# Start disabled; enabled when entering warlord level.
	current = false
	set_process_input(false)
	set_process(false)


func setup(manager: RTSManager, p_faction: int) -> void:
	_manager = manager
	faction_id = p_faction
	set_process_input(true)
	set_process(true)
	# Create drag box UI: translucent fill with a bright border so the
	# selection area reads clearly while dragging.
	_drag_box = Panel.new()
	var dstyle := StyleBoxFlat.new()
	dstyle.bg_color = Color(0.3, 0.7, 1.0, 0.15)
	dstyle.border_color = Color(0.45, 0.85, 1.0, 0.95)
	dstyle.set_border_width_all(2)
	dstyle.set_corner_radius_all(2)
	_drag_box.add_theme_stylebox_override("panel", dstyle)
	_drag_box.visible = false
	_drag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_child(_drag_box)


func _process(delta: float) -> void:
	if not active:
		return
	# WASD pan.
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		dir.y += 1
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	# Edge scroll (mouse at screen border pans).
	var vp := get_viewport().get_visible_rect().size
	var mp := get_viewport().get_mouse_position()
	var margin := 12.0
	if mp.x < margin:
		dir.x -= 1
	elif mp.x > vp.x - margin:
		dir.x += 1
	if mp.y < margin:
		dir.y -= 1
	elif mp.y > vp.y - margin:
		dir.y += 1
	if dir != Vector2.ZERO:
		position += Vector3(dir.x, 0, dir.y).normalized() * _pan_speed * delta


func _input(event: InputEvent) -> void:
	if _manager == null:
		return
	# Tab toggles.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle()
			get_viewport().set_input_as_handled()
			return
		# B toggles the build menu in command view.
		if event.keycode == KEY_B and active:
			var rhud := _find_rts_hud()
			if rhud != null and rhud.has_method("toggle_build_menu"):
				rhud.call("toggle_build_menu")
			get_viewport().set_input_as_handled()
			return
		# Esc cancels placement.
		if event.keycode == KEY_ESCAPE and _placing_type != "":
			cancel_placement()
			get_viewport().set_input_as_handled()
			return
	if not active:
		return
	# Placement mode: ghost follows mouse, left-click places, right-click cancels.
	if _placing_type != "":
		if event is InputEventMouseMotion:
			_update_ghost(event.position)
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_confirm_placement(event.position)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				cancel_placement()
		return
	# Left click/drag: selection.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = event.position
		else:
			if _drag_start != Vector2.INF:
				var drag_dist: float = event.position.distance_to(_drag_start)
				if drag_dist < 10.0:
					_select_single(event.position)
				else:
					_select_box(_drag_start, event.position)
				_drag_start = Vector2.INF
				_drag_box.visible = false
	# Right click: order.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_order(event.position)
	# Mouse wheel: zoom.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom - 5.0, 20.0, 60.0)
			position.y = _zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom + 5.0, 20.0, 60.0)
			position.y = _zoom
	# Drag box visual.
	if event is InputEventMouseMotion and _drag_start != Vector2.INF:
		_update_drag_box(_drag_start, event.position)


func toggle() -> void:
	active = not active
	current = active
	# Free the mouse for click/drag orders in command view; recapture for FPS.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if active else Input.MOUSE_MODE_CAPTURED
	# Hide the FPS viewmodel (sword/dagger/staff) in top-down view.
	var player := _find_local_player()
	if player:
		var vm = player.get("_viewmodel")
		if vm and vm is Node3D:
			(vm as Node3D).visible = not active
		# Also disable the FPS camera so it doesn't fight for control.
		var fps_cam = player.get("_camera")
		if fps_cam and fps_cam is Camera3D:
			(fps_cam as Camera3D).current = not active
		# Hide FPS-specific HUD in command view (keep health/XP).
		var hud = player.get("hud")
		if hud != null and hud.has_method("set_command_view"):
			hud.call("set_command_view", active)
		# Update the RTS HUD hints for the new view mode.
		var rhud2 := _find_rts_hud()
		if rhud2 != null and rhud2.has_method("set_command_view"):
			rhud2.call("set_command_view", active)
		# Hide RTS panels when leaving command view.
		if not active:
			var rhud := _find_rts_hud()
			if rhud != null:
				if rhud.has_method("hide_build_menu"):
					rhud.call("hide_build_menu")
				if rhud.has_method("hide_train_menu"):
					rhud.call("hide_train_menu")
			cancel_placement()
	if active:
		# Position above player's town hall.
		var th := _find_my_townhall()
		if th:
			position = th.global_position + Vector3(0, _zoom, 0)
		rotation = Vector3(-PI / 2, 0, 0)


func _find_local_player() -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == multiplayer.get_unique_id():
			return p
	return null


func _find_my_townhall() -> Node3D:
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if int(b.get("faction")) == faction_id and str(b.get("building_type")) == "town_hall":
			return b
	return null


func _screen_to_ground(screen_pos: Vector2) -> Vector3:
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0)
	var hit = plane.intersects_ray(from, dir)
	return hit if hit else Vector3.ZERO


func _select_single(screen_pos: Vector2) -> void:
	_clear_selection()
	var ground := _screen_to_ground(screen_pos)
	# Try friendly buildings first (for the training panel).
	var bbest: Node3D = null
	var bbest_d := 3.5
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if int(b.get("faction")) != faction_id:
			continue
		if bool(b.get("under_construction")):
			continue
		var d := ground.distance_to(b.global_position)
		if d < bbest_d:
			bbest_d = d
			bbest = b
	if bbest != null:
		_selected.append(bbest)
		_show_selection_ring(bbest)
		var rhud := _find_rts_hud()
		if rhud != null and rhud.has_method("show_train_menu"):
			rhud.call("show_train_menu", bbest)
		return
	# Otherwise try friendly units.
	var rhud2 := _find_rts_hud()
	if rhud2 != null and rhud2.has_method("hide_train_menu"):
		rhud2.call("hide_train_menu")
	var best: Node3D = null
	var best_d := 2.0
	for n in get_tree().get_nodes_in_group("rts_units"):
		if int(n.get("faction")) != faction_id:
			continue
		var d := ground.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	if best:
		_selected.append(best)
		_show_selection_ring(best)


func _select_box(p1: Vector2, p2: Vector2) -> void:
	_clear_selection()
	var rect := Rect2(p1, p2 - p1).abs()
	for n in get_tree().get_nodes_in_group("rts_units"):
		if int(n.get("faction")) != faction_id:
			continue
		var sp := unproject_position(n.global_position)
		if rect.has_point(sp):
			_selected.append(n)
			_show_selection_ring(n)


func _issue_order(screen_pos: Vector2) -> void:
	if _selected.is_empty():
		return
	var ground := _screen_to_ground(screen_pos)
	# Check if clicked on enemy, resource, or market.
	var target_unit := _pick_enemy_at(ground)
	var target_node := _pick_resource_at(ground)
	var target_market := _pick_market_at(ground)
	for n in _selected:
		if not is_instance_valid(n):
			continue
		# Issue #54: buildings don't have unit order RPCs — skip them.
		# Right-click with a building selected should not fire unit RPCs.
		if n.is_in_group("rts_buildings"):
			continue
		if target_unit:
			if str(n.get("unit_type")) == "monk" and target_unit.is_in_group("rts_units"):
				n.rpc_id(_server_id(), "order_convert", target_unit.get_path())
			else:
				n.rpc_id(_server_id(), "rpc_order_attack", target_unit.get_path())
		elif target_market and str(n.get("unit_type")) == "trade_cart":
			n.rpc_id(_server_id(), "rpc_order_trade", target_market.get_path())
		elif target_node and str(n.get("unit_type")) == "villager":
			n.rpc_id(_server_id(), "rpc_order_gather", target_node.get_path())
		else:
			# Spread move targets slightly.
			var offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			n.rpc_id(_server_id(), "rpc_order_move", ground + offset)


func _pick_enemy_at(ground: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 2.0
	for n in get_tree().get_nodes_in_group("rts_units"):
		if int(n.get("faction")) == faction_id:
			continue
		var d := ground.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	for n in get_tree().get_nodes_in_group("rts_buildings"):
		if int(n.get("faction")) == faction_id:
			continue
		var d := ground.distance_to(n.global_position)
		if d < best_d + 1.0:
			best_d = d
			best = n
	return best


func _pick_resource_at(ground: Vector3) -> RTSResourceNode:
	var best: RTSResourceNode = null
	var best_d := 2.0
	for n in get_tree().get_nodes_in_group("rts_resources"):
		var d := ground.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _pick_market_at(ground: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 3.0
	for n in get_tree().get_nodes_in_group("rts_buildings"):
		if str(n.get("building_type")) != "market":
			continue
		var d := ground.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _clear_selection() -> void:
	for n in _selected:
		if is_instance_valid(n) and n.has_method("set_selected"):
			n.rpc("set_selected", false)
	_selected.clear()
	var rhud := _find_rts_hud()
	if rhud != null and rhud.has_method("hide_train_menu"):
		rhud.call("hide_train_menu")


func _show_selection_ring(unit: Node3D) -> void:
	if unit.has_method("set_selected"):
		unit.rpc("set_selected", true)


func _update_drag_box(p1: Vector2, p2: Vector2) -> void:
	if _drag_box == null:
		return
	# Lazy-parent: the HUD may not have existed when setup() ran.
	if _drag_box.get_parent() == null:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud == null:
			var dungeon := get_tree().get_first_node_in_group("dungeon")
			hud = dungeon.get_node_or_null("RTSHUD") if dungeon else null
		if hud != null:
			hud.add_child(_drag_box)
		else:
			return
	_drag_box.visible = true
	var rect := Rect2(p1, p2 - p1).abs()
	_drag_box.position = rect.position
	_drag_box.size = rect.size


func _update_ghost(screen_pos: Vector2) -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	var ground := _screen_to_ground(screen_pos)
	_ghost.position = Vector3(ground.x, 1.0, ground.z)
	# Green if buildable here, red if not.
	_ghost_valid = _is_valid_build_spot(ground)
	var mat := _ghost.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.2, 0.9, 0.3, 0.4) if _ghost_valid else Color(0.9, 0.2, 0.2, 0.4)


func _is_valid_build_spot(ground: Vector3) -> bool:
	# Not too close to other buildings.
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if ground.distance_to(b.global_position) < 5.0:
			return false
	# Not on the river.
	if Dungeon.is_on_water(ground):
		return false
	return true


func _confirm_placement(screen_pos: Vector2) -> void:
	if _placing_type == "" or not _ghost_valid:
		return
	var ground := _screen_to_ground(screen_pos)
	ground.y = 0.0
	var btype := _placing_type
	cancel_placement()
	# Ask the server to start construction (validates cost, finds a villager).
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null and dungeon.has_method("rpc_start_construction"):
		dungeon.rpc_id(_server_id(), "rpc_start_construction", faction_id, btype, ground)


func _server_id() -> int:
	return NetworkManager.server_id


func _find_rts_hud() -> Node:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null:
		return dungeon.get_node_or_null("RTSHUD")
	return null


## Enter building placement mode (from the build menu).
func start_placement(btype: String) -> void:
	cancel_placement()
	_placing_type = btype
	_clear_selection()
	_ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 2.0, 3.0)
	_ghost.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.3, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = mat
	_ghost.position = Vector3(0, 1.0, 0)
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null:
		dungeon.get_node("RTS").add_child(_ghost)


func cancel_placement() -> void:
	_placing_type = ""
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
