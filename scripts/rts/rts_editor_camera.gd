class_name RTSEditorCamera
extends RTSCamera
## Always-on editor variant of the RTS camera (issue #266 P2, spec
## §4.1): no faction, no town hall, no manager — pan (WASD 20 m/s +
## edge scroll, inherited `_process`) and zoom (wheel, 6–40 m) over the
## map being edited, with HEIGHT-AWARE picking: `_screen_to_ground`
## raycasts against the terrain height instead of the y=0 plane, so a
## click on a +6 m tier lands on the tier (the base camera's y=0
## projection misplaces by parallax — the red-before defect).
##
## Tool input is forwarded to the editor controller via signals; the
## camera itself places nothing.

signal tool_click(screen_pos: Vector2, pressed: bool)
signal tool_motion(screen_pos: Vector2)
signal tool_cancel

var _terrain: ZonesTerrain = null


## Editor setup: process + input on, always active, centred over the
## map. No manager, no drag box (no selection in the editor).
func setup_editor(terrain: ZonesTerrain) -> void:
	_terrain = terrain
	active = true
	current = true
	position = Vector3(0, _zoom, 0)
	rotation = Vector3(-PI / 2.0, 0, 0)
	set_process_input(true)
	set_process(true)


func set_terrain(terrain: ZonesTerrain) -> void:
	_terrain = terrain


func _input(event: InputEvent) -> void:
	# Same UI-hover guard as the base camera (issue #180): a click over
	# any UI control belongs to the UI (tool palette, buttons).
	if event is InputEventMouseButton \
			and get_viewport().gui_get_hovered_control() != null:
		return
	# Mouse wheel: zoom (same 6–40 m clamp as the base camera).
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom - 5.0, 6.0, 40.0)
			position.y = _zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom + 5.0, 6.0, 40.0)
			position.y = _zoom
	# Tool clicks: left press/release + motion forward to the editor;
	# right press cancels the current gesture (e.g. a ramp's first
	# click).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		tool_click.emit(event.position, event.pressed)
	if event is InputEventMouseMotion:
		tool_motion.emit(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed:
		tool_cancel.emit()


## Height-aware ground pick: intersect the ray with the terrain
## surface, not the y=0 plane. Marches the ray from the camera in
## 1 m steps until it crosses the terrain height, then bisects the
## crossing. A fixed-point iteration from the y=0 hit is NOT enough:
## when the y=0 projection overshoots a tier entirely, the iteration
## converges at the wrong (flat) point — the march finds the tier.
func _screen_to_ground(screen_pos: Vector2) -> Vector3:
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0)
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return Vector3.ZERO
	if _terrain == null:
		return hit
	var max_t := from.distance_to(hit)
	var step := 1.0
	var prev := from
	var t := step
	while t <= max_t + step:
		var p := from + dir * t
		if p.y <= _terrain.get_ground_height(p):
			var lo := prev
			var hi := p
			for i in 10:
				var mid := (lo + hi) * 0.5
				if mid.y <= _terrain.get_ground_height(mid):
					hi = mid
				else:
					lo = mid
			return hi
		prev = p
		t += step
	return hit
