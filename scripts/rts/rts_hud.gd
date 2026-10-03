extends CanvasLayer
## RTS HUD: resource bar, age display, build menu, selection info.
## Only visible in the Warlord's Domain level.

class_name RTSHUD

var _manager: RTSManager = null
var _faction_id := 0
var _res_label: Label = null
var _age_label: Label = null
var _pop_label: Label
var _age_up_btn: Button = null
var _hint_label: Label = null
# Build menu (B key): pick a building to place.
var _build_panel: PanelContainer = null
var _build_buttons: Dictionary = {}
# Training panel: queue units from a selected production building.
var _train_panel: PanelContainer = null
var _train_title: Label = null
var _train_buttons: Dictionary = {}
var _train_building: Node3D = null


func _ready() -> void:
	layer = 10
	visible = false
	_build_ui()


func _build_ui() -> void:
	# Top bar: resources.
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("separation", 20)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top)

	_res_label = Label.new()
	_res_label.add_theme_font_size_override("font_size", 18)
	top.add_child(_res_label)

	_age_label = Label.new()
	_age_label.add_theme_font_size_override("font_size", 18)
	top.add_child(_age_label)

	_pop_label = Label.new()
	_pop_label.add_theme_font_size_override("font_size", 18)
	top.add_child(_pop_label)

	_age_up_btn = Button.new()
	_age_up_btn.text = "Age Up"
	_age_up_btn.add_theme_font_size_override("font_size", 16)
	_age_up_btn.pressed.connect(_on_age_up_pressed)
	top.add_child(_age_up_btn)

	# Bottom hint.
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.text = "Tab: Command View | Click: Select | Right-click: Order | B: Build menu"
	add_child(_hint_label)
	_build_panels()


func _build_panels() -> void:
	# Build menu: hidden until B is pressed in command view.
	_build_panel = PanelContainer.new()
	_build_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_panel.position = Vector2(-260, -220)
	_build_panel.custom_minimum_size = Vector2(520, 0)
	_build_panel.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_build_panel.add_child(vb)
	var title := Label.new()
	title.text = "Build (click to place, right-click to cancel)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	for btype in ["barracks", "archery_range", "market", "siege_workshop", "monastery", "dock", "tower"]:
		var btn := Button.new()
		btn.text = _building_button_text(btype)
		btn.pressed.connect(_on_build_button.bind(btype))
		grid.add_child(btn)
		_build_buttons[btype] = btn
	add_child(_build_panel)

	# Training panel: shown when a production building is selected.
	_train_panel = PanelContainer.new()
	_train_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_train_panel.position = Vector2(-260, -220)
	_train_panel.custom_minimum_size = Vector2(520, 0)
	_train_panel.visible = false
	var tvb := VBoxContainer.new()
	tvb.name = "VBoxContainer"
	tvb.add_theme_constant_override("separation", 4)
	_train_panel.add_child(tvb)
	_train_title = Label.new()
	_train_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tvb.add_child(_train_title)
	var tgrid := GridContainer.new()
	tgrid.columns = 2
	tgrid.add_theme_constant_override("h_separation", 8)
	tgrid.add_theme_constant_override("v_separation", 4)
	tvb.add_child(tgrid)
	tgrid.name = "TrainGrid"
	add_child(_train_panel)


func _building_button_text(btype: String) -> String:
	var cost: Dictionary = RTSManager.BUILDING_COSTS.get(btype, {})
	var parts: Array = []
	for k in ["wood", "food", "gold", "stone"]:
		if int(cost.get(k, 0)) > 0:
			parts.append("%d %s" % [int(cost[k]), k.capitalize()])
	var disp := btype.replace("_", " ").capitalize()
	var age_req := _building_age_req(btype)
	if age_req > 0:
		disp += " (%s+)" % RTSManager.AGES[age_req]
	return "%s\n%s" % [disp, ", ".join(parts)]


func _building_age_req(btype: String) -> int:
	# Fortress (1): siege workshop, monastery. Empire (2): nothing extra yet.
	if btype in ["siege_workshop", "monastery"]:
		return 1
	return 0


func toggle_build_menu() -> void:
	_build_panel.visible = not _build_panel.visible
	if _build_panel.visible:
		_train_panel.visible = false
		_refresh_build_buttons()
		call_deferred("_pin_build_panel")


## Pin the build panel so its bottom sits 16px above the screen bottom,
## regardless of content height (fixes clipping on small screens).
func _pin_build_panel() -> void:
	_pin_panel_bottom(_build_panel)


func _pin_train_panel() -> void:
	_pin_panel_bottom(_train_panel)


func _pin_panel_bottom(panel: Control) -> void:
	# Explicitly set anchors + all four offsets. Setting only `position`
	# leaves stale offset_right/bottom values that break centering.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.reset_size()
	var sz := panel.size
	panel.offset_left = -sz.x / 2.0
	panel.offset_right = sz.x / 2.0
	panel.offset_top = -sz.y - 16.0
	panel.offset_bottom = -16.0


func hide_build_menu() -> void:
	_build_panel.visible = false


func is_build_menu_open() -> bool:
	return _build_panel.visible


func _refresh_build_buttons() -> void:
	if _manager == null:
		return
	var age := _manager.get_age(_faction_id)
	for btype in _build_buttons:
		var btn: Button = _build_buttons[btype]
		var req := _building_age_req(btype)
		var cost: Dictionary = RTSManager.BUILDING_COSTS.get(btype, {})
		btn.disabled = age < req or not _manager.can_afford(_faction_id, cost)
		btn.text = _building_button_text(btype)


func _on_build_button(btype: String) -> void:
	# Tell the camera to enter placement mode.
	var cam := get_tree().get_first_node_in_group("rts_camera")
	if cam != null and cam.has_method("start_placement"):
		cam.call("start_placement", btype)
	hide_build_menu()


## Show trainable units for a selected production building.
func show_train_menu(building: Node3D) -> void:
	var btype := str(building.get("building_type"))
	var allowed: Array = RTSBuilding.PRODUCTION.get(btype, [])
	if allowed.is_empty():
		hide_train_menu()
		return
	_train_building = building
	_build_panel.visible = false
	_train_panel.visible = true
	call_deferred("_pin_train_panel")
	_train_title.text = "%s — train units" % btype.replace("_", " ").capitalize()
	var grid := _train_panel.get_node("VBoxContainer/TrainGrid")
	for c in grid.get_children():
		c.queue_free()
	_train_buttons.clear()
	for utype in allowed:
		# Knights need Fortress+.
		if utype == "knight" and _manager.get_age(_faction_id) < 1:
			continue
		var btn := Button.new()
		btn.text = _unit_button_text(utype)
		btn.pressed.connect(_on_train_button.bind(utype))
		grid.add_child(btn)
		_train_buttons[utype] = btn
	_refresh_train_buttons()


func hide_train_menu() -> void:
	_train_panel.visible = false
	_train_building = null


func _unit_button_text(utype: String) -> String:
	var cost: Dictionary = RTSManager.UNIT_COSTS.get(utype, {})
	var parts: Array = []
	for k in ["wood", "food", "gold", "stone"]:
		if int(cost.get(k, 0)) > 0:
			parts.append("%d %s" % [int(cost[k]), k.capitalize()])
	return "%s\n%s" % [utype.replace("_", " ").capitalize(), ", ".join(parts)]


func _refresh_train_buttons() -> void:
	if _manager == null or _train_building == null or not is_instance_valid(_train_building):
		hide_train_menu()
		return
	for utype in _train_buttons:
		var btn: Button = _train_buttons[utype]
		btn.disabled = not _manager.can_train(_faction_id, utype)
		btn.text = _unit_button_text(utype)


func _on_train_button(utype: String) -> void:
	if _train_building == null or not is_instance_valid(_train_building):
		hide_train_menu()
		return
	# Server validates cost/pop via building.queue_unit.
	_train_building.rpc_id(NetworkManager.server_id, "rpc_queue_unit", utype)
	_refresh_train_buttons()


func setup(manager: RTSManager, faction_id: int) -> void:
	_manager = manager
	_faction_id = faction_id
	_manager.resources_changed.connect(_on_resources_changed)
	_manager.age_changed.connect(_on_age_changed)
	visible = true
	_refresh()


func _on_resources_changed(faction: int) -> void:
	if faction == _faction_id:
		_refresh()


func _on_age_changed(faction: int, _new_age: int) -> void:
	if faction == _faction_id:
		_refresh()


func _refresh() -> void:
	if _manager == null:
		return
	var res := _manager.get_resources(_faction_id)
	_res_label.text = "Wood: %d  Food: %d  Gold: %d  Stone: %d" % [res["wood"], res["food"], res["gold"], res["stone"]]
	_age_label.text = "Age: %s" % RTSManager.AGES[_manager.get_age(_faction_id)]
	_pop_label.text = "Pop: %d/%d" % [_manager.get_population(_faction_id), _manager.get_pop_cap(_faction_id)]
	if _build_panel.visible:
		_refresh_build_buttons()
	if _train_panel.visible:
		_refresh_train_buttons()
	_refresh_age_button()


func _on_age_up_pressed() -> void:
	if _manager == null:
		return
	if multiplayer.is_server():
		_manager.rpc_age_up(_faction_id)
	else:
		_manager.rpc_id(NetworkManager.server_id, "rpc_age_up", _faction_id)


func _refresh_age_button() -> void:
	if _age_up_btn == null or _manager == null:
		return
	var age := _manager.get_age(_faction_id)
	if age >= 2:
		_age_up_btn.visible = false
		return
	_age_up_btn.visible = true
	var next_cost: Dictionary = RTSManager.AGE_COSTS[age + 1]
	var parts: Array = []
	for k in ["wood", "food", "gold", "stone"]:
		if int(next_cost.get(k, 0)) > 0:
			parts.append("%d %s" % [int(next_cost[k]), k.capitalize()])
	_age_up_btn.text = "Age Up: %s" % ", ".join(parts)
	_age_up_btn.disabled = not _manager.can_afford(_faction_id, next_cost)
