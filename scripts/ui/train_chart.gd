extends Control
## Issue #244 T4 (spec §5): the GPS node chart. A 2D
## canvas over the derived train network — discovered
## nodes only, at their relative world positions — with
## course plotting (tap to append, tap again to remove,
## clear), the routed path drawn over the edges it will
## traverse, pass-throughs marked, and a ride-time
## estimate at TRAIN_SPEED. Confirm departs through
## NetworkManager's server validation (T3); while the
## train moves, the chart is view-only.
##
## Navigation is the F1 ruling: pan + zoom on the Deep
## Tree canvas precedent (cam_offset + zoom-at-cursor +
## drag pan), NOT a scroll surface. The chart opens
## centered on the train's node at the tightest zoom that
## keeps the plotted course (or home) in frame.
##
## Faces: "car" (the in-train terminal — the primary
## surface) and "station" (a station terminal, which also
## carries the summon). The draft is shared (Dungeon
## statics via NetworkManager.publish, last editor wins);
## this control is a consumer of T1's derivation + T3's
## state, never an authority.

const WorldGen := preload("res://scripts/world/world_gen.gd")
const TrainNetwork := preload("res://scripts/world/train_network.gd")

const ZOOM_MIN := 0.04
const ZOOM_MAX := 4.0
const NODE_HIT_PX := 16.0

var _face := "car"
var _station_key := ""
var _cam := Vector2.ZERO
var _zoom := 0.3
var _dragging := false
var _press_travel := 0.0
var _press_moved := false
var _poll := 0.0
var _sig := ""
var _fitted := false

var _status_lbl: Label
var _estimate_lbl: Label
var _confirm_btn: Button
var _summon_btn: Button
var _clear_btn: Button


## Opens the chart over the current scene (or focuses the
## one already open). Called by the terminals.
static func open_chart(face: String, station_key: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	for n in tree.get_nodes_in_group("train_chart"):
		if is_instance_valid(n):
			(n as Control).grab_focus()
			return
	var layer := CanvasLayer.new()
	layer.layer = 60
	var chart: Control = (load(
		"res://scripts/ui/train_chart.gd") as GDScript).new()
	chart.add_to_group("train_chart")
	chart.set("chart_face", face)
	chart.set("chart_station", station_key)
	layer.add_child(chart)
	tree.current_scene.add_child(layer)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The face/station handed in by the opener (set before
## the node enters the tree).
var chart_face: String:
	set(v):
		_face = v
	get:
		return _face
var chart_station: String:
	set(v):
		_station_key = v
	get:
		return _station_key


## --- Pure chart logic (suite-driven) ---

## Tap semantics on the draft: appended when absent,
## removed when present (§5).
static func draft_toggle(draft: Array, key: String) -> Array:
	var out := draft.duplicate()
	if out.has(key):
		out.erase(key)
	else:
		out.append(key)
	return out


## The confirm payload: the train's node is the course
## head; the draft's destinations follow, with the origin
## and consecutive duplicates folded out (T3 validates
## the rest server-side).
static func confirm_course(at_key: String,
		draft: Array) -> Array:
	var out: Array = [at_key]
	for k in draft:
		if String(k) != String(out[out.size() - 1]):
			out.append(String(k))
	return out


## Default view (§5): centered on the train's position,
## at the tightest zoom that also keeps every must-see
## point in frame.
static func fit_view(center: Vector2, must_see: Array,
		viewport: Vector2) -> Dictionary:
	var hx := 60.0
	var hy := 60.0
	for p in must_see:
		var d := (p as Vector2) - center
		hx = maxf(hx, absf(d.x) + 60.0)
		hy = maxf(hy, absf(d.y) + 60.0)
	var zx := viewport.x * 0.46 / hx
	var zy := viewport.y * 0.42 / hy
	return {"center": center,
		"zoom": clampf(minf(zx, zy), ZOOM_MIN, ZOOM_MAX)}


## Ride-time text at TRAIN_SPEED: "2:13".
static func ride_time_text(length_m: float) -> String:
	var secs := int(round(length_m
		/ TrainNetwork.TRAIN_SPEED))
	return "%d:%02d" % [secs / 60, secs % 60]


func _ready() -> void:
	# Anchors AND offsets (the Deep Tree canvas's lesson):
	# anchors alone leave a code-built root control at
	# (0, 0) size.
	set_anchors_preset(PRESET_FULL_RECT)
	set_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	_build_chrome()
	# Deferred so the full-rect layout has run before the
	# default view fits itself to the real size.
	call_deferred("_refresh", true)


func _build_chrome() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(PRESET_TOP_WIDE)
	top.set_offsets_preset(PRESET_TOP_WIDE)
	top.add_theme_stylebox_override("panel",
		_bar_style())
	add_child(top)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 12)
	top.add_child(trow)
	var title := Label.new()
	title.text = "GPS — TRAIN NETWORK"
	title.add_theme_color_override("font_color",
		Color(0.95, 0.85, 0.55))
	trow.add_child(title)
	_status_lbl = Label.new()
	_status_lbl.add_theme_color_override("font_color",
		Color(0.85, 0.88, 0.95))
	trow.add_child(_status_lbl)
	var bottom := PanelContainer.new()
	# Bottom-wide with EXPLICIT offsets: the offsets
	# preset parks the bar below the viewport's edge
	# (its minimum size grows off-screen).
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 0.0
	bottom.offset_right = 0.0
	bottom.offset_top = -46.0
	bottom.offset_bottom = 0.0
	bottom.add_theme_stylebox_override("panel",
		_bar_style())
	add_child(bottom)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	bottom.add_child(brow)
	_estimate_lbl = Label.new()
	_estimate_lbl.add_theme_color_override("font_color",
		Color(0.85, 0.88, 0.95))
	brow.add_child(_estimate_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	brow.add_child(spacer)
	_summon_btn = Button.new()
	_summon_btn.text = "Summon train here"
	_summon_btn.pressed.connect(_on_summon)
	brow.add_child(_summon_btn)
	_clear_btn = Button.new()
	_clear_btn.text = "Clear course"
	_clear_btn.pressed.connect(_on_clear)
	brow.add_child(_clear_btn)
	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm — depart"
	_confirm_btn.pressed.connect(_on_confirm)
	brow.add_child(_confirm_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_close)
	brow.add_child(close_btn)


func _bar_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.92)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _close() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var layer := get_parent() as CanvasLayer
	if layer != null:
		layer.queue_free()
	else:
		queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


## --- State ---

func _model() -> Dictionary:
	var hb: Dictionary = Dungeon.home_building()
	var hc := Vector2((hb["origin"] as Vector3).x,
		(hb["origin"] as Vector3).z)
	var hs := Vector2((hb["doorstep"] as Vector3).x,
		(hb["doorstep"] as Vector3).z)
	return TrainNetwork.chart_model(WorldGen.WORLD_SEED,
		Dungeon.act2_train_cities, hc, hs,
		Dungeon.train_state,
		NetworkManager.train_local_elapsed_msec())


func _signature() -> String:
	var st: Dictionary = Dungeon.train_state
	return "%s|%s|%d|%d|%s" % [
		String(st.get("status", "idle")),
		String(st.get("at", "")),
		Dungeon.act2_train_cities.size(),
		Dungeon.train_draft.size(),
		",".join(Dungeon.train_draft)]


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= 0.4:
		_poll = 0.0
		if _signature() != _sig:
			_refresh(false)


func _refresh(refit: bool) -> void:
	_sig = _signature()
	if refit or not _fitted:
		_fit_default()
		_fitted = size.x > 10.0
	_update_chrome()
	queue_redraw()


func _fit_default() -> void:
	var m := _model()
	var nodes: Dictionary = m["nodes"]
	var train: Dictionary = m["train"]
	var center: Vector2 = nodes.get(
		String(train.get("at", "home")), Vector2.ZERO)
	var must: Array = []
	var draft: Array = Dungeon.train_draft
	if draft.is_empty():
		if nodes.has(TrainNetwork.HOME_KEY):
			must.append(nodes[TrainNetwork.HOME_KEY])
	else:
		for k in draft:
			if nodes.has(String(k)):
				must.append(nodes[String(k)])
	# Degenerate case (train at home, nothing plotted):
	# the §5 fit collapses to a single point — fall back
	# to framing the whole discovered network so the
	# chart never opens as a microscope on one node.
	var span := 0.0
	for p in must:
		span = maxf(span, (p as Vector2).distance_to(center))
	if span < 1.0 and nodes.size() > 1:
		must.clear()
		for k in nodes:
			must.append(nodes[k])
	var fit := fit_view(center, must, size)
	_cam = fit["center"]
	_zoom = float(fit["zoom"])


func _moving() -> bool:
	return String(Dungeon.train_state.get("status",
		"idle")) == "moving"


## Issue #244 T6: a course is underway while the train
## moves AND while it stands at an intermediate stop —
## confirms and summons refuse in both (the server's
## idle checks say the same); the draft may still be
## edited at the stop for the NEXT course.
func _underway() -> bool:
	var s := String(Dungeon.train_state.get("status",
		"idle"))
	return s == "moving" or s == "stopped"


func _update_chrome() -> void:
	var st: Dictionary = Dungeon.train_state
	var moving := _moving()
	if moving:
		var path: Array = st.get("path", [])
		_status_lbl.text = "En route %s → %s — view only" % [
			String(path[0]) if not path.is_empty() else "?",
			String(path[path.size() - 1])
			if not path.is_empty() else "?"]
	elif String(st.get("status", "idle")) == "stopped":
		var course: Array = st.get("course", [])
		_status_lbl.text = "Stopped at %s — course to %s underway" % [
			String(st.get("at", "home")),
			String(course[course.size() - 1])
			if not course.is_empty() else "?"]
	else:
		_status_lbl.text = "At %s — %s" % [
			String(st.get("at", "home")),
			"plot a course" if _face == "car"
			else "plot a course, or summon"]
	var draft: Array = Dungeon.train_draft
	var stopped := String(st.get("status", "idle")) \
		== "stopped"
	_confirm_btn.disabled = moving or (not stopped \
		and draft.is_empty())
	_confirm_btn.text = "Depart — next leg" if stopped \
		else "Confirm — depart"
	_clear_btn.disabled = moving or draft.is_empty()
	var can_summon := _face == "station" and not _underway() \
		and String(st.get("at", "")) != _station_key \
		and (_station_key == TrainNetwork.HOME_KEY
			or Dungeon.act2_train_cities.has(_station_key))
	_summon_btn.visible = can_summon
	# Estimate over the plotted draft.
	if draft.is_empty():
		_estimate_lbl.text = "Tap a node to plot a course" \
			if not moving else "Riding the plotted course"
	else:
		var hb: Dictionary = Dungeon.home_building()
		var hc := Vector2((hb["origin"] as Vector3).x,
			(hb["origin"] as Vector3).z)
		var hs := Vector2((hb["doorstep"] as Vector3).x,
			(hb["doorstep"] as Vector3).z)
		var course := confirm_course(
			String(st.get("at", "home")), draft)
		var rp := TrainNetwork.route_path(
			WorldGen.WORLD_SEED, Dungeon.act2_train_cities,
			hc, hs, course)
		if float(rp["length"]) > 0.0:
			_estimate_lbl.text = \
				"Course: %s · %d m · ≈ %s at %d m/s" % [
				" → ".join(course),
				int(round(float(rp["length"]))),
				ride_time_text(float(rp["length"])),
				int(TrainNetwork.TRAIN_SPEED)]
		else:
			_estimate_lbl.text = "Course not routable"


## --- Actions ---

func _on_clear() -> void:
	if _moving():
		return
	NetworkManager.train_publish_draft([])
	_refresh(false)


func _on_confirm() -> void:
	if _moving():
		return
	# Issue #244 T6: while stopped mid-course, Confirm
	# is the dwell ruling's departure — a rider confirms
	# and the next leg departs (no re-plot; the server
	# gates on the sender being aboard).
	if String(Dungeon.train_state.get("status", "idle")) \
			== "stopped":
		NetworkManager.train_continue()
		_refresh(false)
		return
	var course := confirm_course(
		String(Dungeon.train_state.get("at", "home")),
		Dungeon.train_draft)
	if course.size() >= 2:
		NetworkManager.train_confirm(course)
	_refresh(false)


func _on_summon() -> void:
	if _moving() or _face != "station":
		return
	NetworkManager.train_summon(_station_key)
	_refresh(false)


## --- Canvas ---

func _to_screen(p: Vector2) -> Vector2:
	return (p - _cam) * _zoom + size * 0.5


func _to_chart(p: Vector2) -> Vector2:
	return (p - size * 0.5) / _zoom + _cam


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := _to_chart(screen)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_cam += before - _to_chart(screen)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP \
				and mb.pressed:
			_zoom_at(mb.position, 1.12)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN \
				and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.12)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_press_moved = false
				_press_travel = 0.0
			elif _dragging:
				_dragging = false
				if not _press_moved:
					_tap(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.relative.length() > 0.0:
			_press_travel += mm.relative.length()
			if _press_travel > 6.0:
				_press_moved = true
			_cam -= mm.relative / _zoom
			queue_redraw()


func _tap(screen: Vector2) -> void:
	if _moving():
		return
	var m := _model()
	var nodes: Dictionary = m["nodes"]
	var cp := _to_chart(screen)
	var best := ""
	var best_d := NODE_HIT_PX / _zoom
	for k in nodes:
		var d := cp.distance_to(nodes[k])
		if d < best_d:
			best_d = d
			best = String(k)
	if best == "" or best == String(
			Dungeon.train_state.get("at", "")):
		return  # The origin is implicit, never plotted.
	NetworkManager.train_publish_draft(
		draft_toggle(Dungeon.train_draft, best))
	_refresh(false)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size),
		Color(0.03, 0.04, 0.07))
	var m := _model()
	var nodes: Dictionary = m["nodes"]
	var font := get_theme_default_font()
	# Routed path first (under the edges' emphasis):
	# the expanded route over the draft, pass-throughs
	# hollow, stops numbered.
	var draft: Array = Dungeon.train_draft
	var pass_through: Dictionary = {}
	var path_pts: Array = []
	if not draft.is_empty() or _underway():
		var st: Dictionary = Dungeon.train_state
		var stops: Array = st.get("course", []) \
			if _underway() else draft
		var course: Array = st.get("path", []) if _moving() \
			else (st.get("course", []) if _underway()
				else confirm_course(
					String(st.get("at", "home")), draft))
		var hb: Dictionary = Dungeon.home_building()
		var hc := Vector2((hb["origin"] as Vector3).x,
			(hb["origin"] as Vector3).z)
		var hs := Vector2((hb["doorstep"] as Vector3).x,
			(hb["doorstep"] as Vector3).z)
		var rp := TrainNetwork.route_path(
			WorldGen.WORLD_SEED, Dungeon.act2_train_cities,
			hc, hs, course)
		for k in rp["nodes"]:
			path_pts.append(nodes.get(String(k),
				Vector2.ZERO))
			if not stops.has(String(k)) and String(k) \
					!= String(st.get("at", "")):
				pass_through[String(k)] = true
	# Edges.
	for e in m["edges"]:
		var ea: Array = e
		draw_line(_to_screen(nodes[ea[0]]),
			_to_screen(nodes[ea[1]]),
			Color(0.35, 0.42, 0.55), 1.5)
	# Path polyline.
	for i in path_pts.size() - 1:
		draw_line(_to_screen(path_pts[i]),
			_to_screen(path_pts[i + 1]),
			Color(0.95, 0.78, 0.30), 3.0)
	# Nodes.
	var at_key := String(Dungeon.train_state.get("at",
		"home"))
	for k in nodes:
		var sp := _to_screen(nodes[k])
		if sp.x < -60 or sp.y < -60 or sp.x > size.x + 60 \
				or sp.y > size.y + 60:
			continue
		var key := String(k)
		var is_home := key == TrainNetwork.HOME_KEY
		var plotted := draft.has(key)
		var r := 9.0 if not pass_through.has(key) else 5.0
		var fill := Color(0.55, 0.65, 0.85)
		if is_home:
			fill = Color(0.95, 0.78, 0.30)
		if plotted:
			fill = Color(0.98, 0.85, 0.35)
		if pass_through.has(key):
			draw_arc(sp, r, 0, TAU, 24,
				Color(0.75, 0.80, 0.90), 1.5)
		else:
			draw_circle(sp, r, fill)
			draw_arc(sp, r, 0, TAU, 32,
				Color(0.08, 0.09, 0.12), 2.0)
		if key == at_key and not _moving():
			draw_arc(sp, r + 5.0, 0, TAU, 32,
				Color(0.4, 0.95, 0.55), 2.0)
		var label := "HOME" if is_home else key
		if plotted:
			label += " (%d)" % (draft.find(key) + 1)
		draw_string(font, sp + Vector2(-34, r + 16),
			label, HORIZONTAL_ALIGNMENT_LEFT, 140, 13,
			Color(0.88, 0.90, 0.96))
	# Train marker.
	var train: Dictionary = m["train"]
	var tp := Vector2.ZERO
	var have_train := false
	if String(train["mode"]) == "at":
		if nodes.has(String(train["at"])):
			tp = _to_screen(nodes[String(train["at"])])
			have_train = true
	elif nodes.has(String(train["a"])) \
			and nodes.has(String(train["b"])):
		tp = _to_screen((nodes[String(train["a"])] as Vector2).lerp(
			nodes[String(train["b"])], float(train["t"])))
		have_train = true
	if have_train:
		var pts := PackedVector2Array([
			tp + Vector2(0, -13), tp + Vector2(9, 4),
			tp + Vector2(-9, 4)])
		draw_colored_polygon(pts, Color(0.95, 0.35, 0.30))
		# At a node the label drops below the node's own
		# label; on a leg it rides just under the marker.
		var ly := 42.0 if String(train["mode"]) == "at" \
			else 24.0
		draw_string(font, tp + Vector2(-16, ly), "TRAIN",
			HORIZONTAL_ALIGNMENT_LEFT, 60, 12,
			Color(0.98, 0.75, 0.70))
