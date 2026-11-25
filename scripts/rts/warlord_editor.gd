class_name WarlordEditor
extends Node3D
## Standalone Warlord level editor (issue #266 P2, spec §4).
##
## A mode in the game client (not the Godot editor): paint terrain
## tiers, ramps, ponds, resource nodes, and faction starts onto the
## §5 map format; validate live with the SAME baseplate validator the
## host uses (`WarlordMap.validate`); save named maps to
## `user://maps/`; playtest the map as a solo skirmish (1 human + AI
## fill) and return with the map unchanged. The editor owns its scene,
## its working map, and its teardown; it never writes a run save and
## never touches the dungeon loop.
##
## The working map is a plain §5 Dictionary. Every tool mutates it,
## then the terrain rebuilds (`WarlordMap.build_terrain` + generate),
## markers reposition, and the validator re-runs — on committed edits
## (clicks), never per mouse-motion (a validate call builds a terrain).

const EDITOR_SEED := 5505
const ERASE_RADIUS := 6.0
const POND_RADIUS_MIN := 4.5
const POND_RADIUS_MAX := 6.0
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MATCH_SCENE := "res://scenes/rts/warlord_match.tscn"

const TOOL_SELECT := "select"
const TOOL_ERASE := "erase"
const TOOL_TIER := "tier"
const TOOL_RAMP := "ramp"
const TOOL_POND := "pond"
const TOOL_NODE := "node"
const TOOL_START := "start"

var _map: Dictionary = {}
var _terrain: ZonesTerrain = null
var _camera: RTSEditorCamera = null
var _markers: Node3D = null
var _ghost: MeshInstance3D = null
var _tool := TOOL_TIER
var _tier_height := 3
var _zone_radius := 12.0
var _ramp_width := 8.0
var _pond_radius := 5.0
var _node_type := "wood"
var _ramp_first := Vector2.INF
var _validation := ""
var _name_edit: LineEdit = null
var _readout: Label = null
var _tool_label: Label = null


func _ready() -> void:
	_camera = RTSEditorCamera.new()
	_camera.name = "EditorCamera"
	add_child(_camera)
	_markers = Node3D.new()
	_markers.name = "Markers"
	add_child(_markers)
	_ghost = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(2.0, 0.4, 2.0)
	_ghost.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.3, 1.0, 0.3, 0.5)
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = gmat
	add_child(_ghost)
	_build_ui()
	_camera.tool_click.connect(_on_tool_click)
	_camera.tool_motion.connect(_on_tool_motion)
	_camera.tool_cancel.connect(_on_tool_cancel)
	# Return from a playtest: the stash holds the map as it was.
	var nm: Node = get_tree().root.get_node_or_null("NetworkManager")
	var stash: Dictionary = {}
	if nm != null:
		stash = nm.get("warlord_editor_map") as Dictionary
	if not stash.is_empty():
		_map = stash.duplicate(true)
		nm.set("warlord_editor_map", {})
		if _name_edit != null:
			_name_edit.text = str(_map.get("display_name", ""))
		_after_edit()
	else:
		new_map(220)


## A blank map at the chosen size (160 or 220). Invalid until starts
## and nodes are placed — the readout names the failing proof.
func new_map(size_m: int) -> void:
	_map = {
		"format_version": WarlordMap.FORMAT_VERSION,
		"name": "",
		"display_name": "",
		"size_m": size_m,
		"seed": EDITOR_SEED,
		"zones": [],
		"ramps": [],
		"ponds": [],
		"starts": [],
		"nodes": [],
	}
	_after_edit()


func map_dict() -> Dictionary:
	return _map


func validation_error() -> String:
	return _validation


## Height-aware pick through the editor camera (pin iii).
func pick_ground(screen_pos: Vector2) -> Vector3:
	return _camera._screen_to_ground(screen_pos)


## Paint a tier zone. +9 m is a staircase tier: it only places where
## the current ground already reads +6 (within the validator's tier
## tolerance) — the tool rule; the validator stays the P1 one.
func place_zone(pos: Vector2, height: int, radius: float) -> bool:
	if height not in WarlordMap.TIER_HEIGHTS:
		return false
	if radius <= 0.0:
		return false
	if height == 9:
		var h := _ground_height(pos)
		if absf(h - 6.0) > WarlordMap.TIER_TOL:
			return false
	(_map["zones"] as Array).append({
		"center": [pos.x, pos.y], "height": height, "radius": radius})
	_after_edit()
	return true


## Place a ramp from `base` along unit `dir`. h0/h1 are sampled from
## the current terrain at the two ends and must read as tier heights
## with h1 > h0; the grade is the validator's call at save (design
## cap ~0.5, hard fail > 0.7) — the readout shows it live.
func place_ramp(base: Vector2, dir: Vector2, length: float,
		width: float) -> bool:
	if length <= 0.0 or width <= 0.0 or dir.length() < 0.5:
		return false
	dir = dir.normalized()
	var h0 := _tier_at(base)
	var h1 := _tier_at(base + dir * length)
	if h0 < 0 or h1 < 0 or h1 <= h0:
		return false
	(_map["ramps"] as Array).append({
		"base": [base.x, base.y], "dir": [dir.x, dir.y],
		"h0": h0, "h1": h1, "length": length, "width": width})
	_after_edit()
	return true


func place_pond(pos: Vector2, radius: float) -> void:
	(_map["ponds"] as Array).append({
		"center": [pos.x, pos.y],
		"radius": clampf(radius, POND_RADIUS_MIN, POND_RADIUS_MAX)})
	_after_edit()


## Place a resource node with the shipped amount for its type
## (amounts are not editable in v1 — placement is the tool).
func place_node(res_type: String, pos: Vector2) -> void:
	var amounts := RTSTuning.get_dict("map", "node_amounts",
		{"wood": 1000, "food": 800, "gold": 800, "stone": 800})
	(_map["nodes"] as Array).append({
		"type": res_type, "pos": [pos.x, pos.y],
		"amount": int(amounts.get(res_type, 500))})
	_after_edit()


## Place the next faction start (ids are 0..n-1 by index — the match
## reads starts[faction]). Refuses past 12.
func place_start(pos: Vector2) -> bool:
	var starts: Array = _map["starts"]
	if starts.size() >= WarlordMap.STARTS_MAX:
		return false
	starts.append({"faction": starts.size(), "pos": [pos.x, pos.y]})
	_after_edit()
	return true


func move_start(faction: int, pos: Vector2) -> bool:
	var starts: Array = _map["starts"]
	if faction < 0 or faction >= starts.size():
		return false
	(starts[faction] as Dictionary)["pos"] = [pos.x, pos.y]
	_after_edit()
	return true


## Erase the nearest entry within ERASE_RADIUS (zone centre / ramp
## base / pond centre / node / start). Starts re-number so ids stay
## 0..n-1 by index.
func erase_at(pos: Vector2) -> bool:
	var best_kind := ""
	var best_idx := -1
	var best_d := ERASE_RADIUS
	for i in (_map["zones"] as Array).size():
		var d := pos.distance_to(_vec2((_map["zones"][i] as Dictionary).get("center", [])))
		if d < best_d:
			best_d = d
			best_kind = "zones"
			best_idx = i
	for i in (_map["ramps"] as Array).size():
		var d := pos.distance_to(_vec2((_map["ramps"][i] as Dictionary).get("base", [])))
		if d < best_d:
			best_d = d
			best_kind = "ramps"
			best_idx = i
	for i in (_map["ponds"] as Array).size():
		var d := pos.distance_to(_vec2((_map["ponds"][i] as Dictionary).get("center", [])))
		if d < best_d:
			best_d = d
			best_kind = "ponds"
			best_idx = i
	for i in (_map["nodes"] as Array).size():
		var d := pos.distance_to(_vec2((_map["nodes"][i] as Dictionary).get("pos", [])))
		if d < best_d:
			best_d = d
			best_kind = "nodes"
			best_idx = i
	for i in (_map["starts"] as Array).size():
		var d := pos.distance_to(_vec2((_map["starts"][i] as Dictionary).get("pos", [])))
		if d < best_d:
			best_d = d
			best_kind = "starts"
			best_idx = i
	if best_idx < 0:
		return false
	(_map[best_kind] as Array).remove_at(best_idx)
	if best_kind == "starts":
		for i in (_map["starts"] as Array).size():
			(_map["starts"][i] as Dictionary)["faction"] = i
	_after_edit()
	return true


## Filename-safe form of a player-chosen map name: keep
## [A-Za-z0-9_-], spaces become underscores, everything else drops.
static func sanitize_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var ch := raw[i]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") \
				or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
		elif ch == " ":
			out += "_"
	return out


## Save the working map under `display_name` (sanitized to the file
## name). "" = saved. Refuses with the validator's named proof when
## the map is unplayable, and with "exists" when the file is there and
## `overwrite` is false (the UI confirms — no silent overwrite).
func save_map(display_name: String, overwrite: bool) -> String:
	var err := WarlordMap.validate(_map)
	if err != "":
		return err
	var fname := sanitize_name(display_name)
	if fname == "":
		return "name must contain a letter or digit"
	var path := WarlordMap.USER_MAPS_DIR + "/" + fname + ".json"
	if FileAccess.file_exists(path) and not overwrite:
		return "exists"
	_map["name"] = fname
	_map["display_name"] = display_name
	if not DirAccess.dir_exists_absolute(WarlordMap.USER_MAPS_DIR):
		DirAccess.make_dir_recursive_absolute(WarlordMap.USER_MAPS_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "could not write " + path
	f.store_string(WarlordMap.canonical_json(_map))
	f.close()
	return ""


## Load a map file into the editor. Parseable maps load even when
## invalid (the readout names the failing proof so the author can fix
## it); unparseable files are refused. "" = loaded.
func load_map(path: String) -> String:
	var parsed := WarlordMap.parse_map(FileAccess.get_file_as_string(path))
	if not bool(parsed.get("ok", false)):
		return str(parsed.get("error", "unparseable"))
	_map = (parsed["map"] as Dictionary).duplicate(true)
	if _name_edit != null:
		_name_edit.text = str(_map.get("display_name", ""))
	_after_edit()
	return ""


## Delete a saved map file (explicit, UI-confirmed — the editor never
## deletes on its own). "" = deleted.
func delete_map(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "no such file"
	return "" if DirAccess.remove_absolute(path) == OK else "delete failed"


## Prepare a solo skirmish on the working map: validate (an
## unplayable map cannot be hosted — the skirmish is a local host),
## then stamp the match vars. No scene change — `launch_playtest`
## does that, so the suite can drive the preparation.
func prepare_playtest() -> String:
	var err := WarlordMap.validate(_map)
	if err != "":
		return err
	var nm: Node = get_tree().root.get_node_or_null("NetworkManager")
	if nm == null:
		return "no session"
	nm.set("warlord_map", _map.duplicate(true))
	nm.set("warlord_editor_map", _map.duplicate(true))
	nm.set("warlord_faction_count", WarlordMap.start_count(_map))
	nm.set("warlord_ai_fill", true)
	nm.set("is_host", true)
	nm.set("active_run_mode", "warlord")
	nm.set("warlord_editor_playtest", true)
	return ""


func launch_playtest() -> String:
	var err := prepare_playtest()
	if err != "":
		return err
	get_tree().change_scene_to_file(MATCH_SCENE)
	return ""


## After every committed edit: rebuild the terrain, reposition the
## markers, re-validate, refresh the readout.
func _after_edit() -> void:
	if _terrain != null and is_instance_valid(_terrain):
		remove_child(_terrain)
		_terrain.free()
	_terrain = WarlordMap.build_terrain(_map)
	if _terrain != null:
		add_child(_terrain)
		_terrain.generate()
	if _camera != null:
		_camera.set_terrain(_terrain)
		if not _camera.active:
			_camera.setup_editor(_terrain)
	_rebuild_markers()
	_validation = WarlordMap.validate(_map)
	_update_readout()


func _rebuild_markers() -> void:
	for c in _markers.get_children():
		_markers.remove_child(c)
		c.free()
	for s in _map.get("starts", []):
		var sd: Dictionary = s
		var p := _vec2(sd.get("pos", []))
		var m := _marker_mesh(RTSManager.faction_color(int(sd.get("faction", 0))),
			Vector3(3.4, 1.2, 3.4))
		m.position = Vector3(p.x, _ground_height(p) + 0.6, p.y)
		_markers.add_child(m)
	var node_colors := {"wood": Color(0.35, 0.7, 0.3),
		"food": Color(0.9, 0.5, 0.3), "gold": Color(0.95, 0.8, 0.2),
		"stone": Color(0.6, 0.6, 0.65)}
	for n in _map.get("nodes", []):
		var nd: Dictionary = n
		var p := _vec2(nd.get("pos", []))
		var m := _marker_mesh(node_colors.get(str(nd.get("type", "")), Color.WHITE),
			Vector3(1.4, 0.8, 1.4))
		m.position = Vector3(p.x, _ground_height(p) + 0.4, p.y)
		_markers.add_child(m)


func _marker_mesh(color: Color, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	return mi


func _ground_height(pos: Vector2) -> float:
	if _terrain == null:
		return 0.0
	return _terrain.get_ground_height(Vector3(pos.x, 0, pos.y))


## The tier height at a point, or -1 when the ground there is not a
## tier top (within the validator's tolerance).
func _tier_at(pos: Vector2) -> int:
	var h := _ground_height(pos)
	for t in [0, 3, 6, 9]:
		if absf(h - float(t)) <= WarlordMap.TIER_TOL:
			return t
	return -1


## Ghost validity for node/start placement: dry, and flat across the
## start footprint (the validator's base-placement rule — the pattern
## of the match's `_is_valid_build_spot`, sampled on the editor's
## terrain). A hint only; the validator gates at save.
func _spot_valid(pos: Vector2, need_flat: bool) -> bool:
	if _terrain == null:
		return false
	if _terrain.is_water(Vector3(pos.x, 0, pos.y)):
		return false
	if not need_flat:
		return true
	var lo := INF
	var hi := -INF
	var half := WarlordMap.FOOTPRINT_SIZE * 0.5
	for dx in [-half, 0.0, half]:
		for dz in [-half, 0.0, half]:
			var h := _ground_height(pos + Vector2(dx, dz))
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo < WarlordMap.FOOTPRINT_RANGE_MAX


func _vec2(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.INF


func _on_tool_click(screen_pos: Vector2, pressed: bool) -> void:
	if not pressed:
		return
	var g := pick_ground(screen_pos)
	var pos := Vector2(g.x, g.z)
	match _tool:
		TOOL_TIER:
			place_zone(pos, _tier_height, _zone_radius)
		TOOL_POND:
			place_pond(pos, _pond_radius)
		TOOL_NODE:
			place_node(_node_type, pos)
		TOOL_START:
			var near := -1
			for i in (_map["starts"] as Array).size():
				if pos.distance_to(_vec2((_map["starts"][i] as Dictionary).get("pos", []))) < 4.0:
					near = i
			if near >= 0:
				move_start(near, pos)
			else:
				place_start(pos)
		TOOL_ERASE:
			erase_at(pos)
		TOOL_RAMP:
			if _ramp_first == Vector2.INF:
				_ramp_first = pos
				_update_readout()
			else:
				var d := pos - _ramp_first
				if d.length() > 1.0:
					place_ramp(_ramp_first, d.normalized(), d.length(),
						_ramp_width)
				_ramp_first = Vector2.INF


func _on_tool_motion(screen_pos: Vector2) -> void:
	var g := pick_ground(screen_pos)
	_ghost.position = Vector3(g.x, g.y + 0.2, g.z)
	var ok := true
	if _tool == TOOL_START:
		ok = _spot_valid(Vector2(g.x, g.z), true)
	elif _tool == TOOL_NODE:
		ok = _spot_valid(Vector2(g.x, g.z), false)
	var mat := _ghost.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.3, 1.0, 0.3, 0.5) if ok else Color(1.0, 0.3, 0.3, 0.5)


func _on_tool_cancel() -> void:
	_ramp_first = Vector2.INF


func _update_readout() -> void:
	if _readout == null:
		return
	if _ramp_first != Vector2.INF:
		_readout.text = "Ramp: click the uphill end (right-click cancels)"
		_readout.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	elif _validation == "":
		_readout.text = "Valid — ready to save / host / playtest"
		_readout.add_theme_color_override("font_color", Color(0.45, 0.95, 0.5))
	else:
		_readout.text = "Invalid: " + _validation
		_readout.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	# Top bar: name, new, save, load, delete, playtest, back.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.add_theme_constant_override("separation", 6)
	layer.add_child(bar)
	var name_label := Label.new()
	name_label.text = "Map:"
	bar.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(180, 0)
	_name_edit.placeholder_text = "map name"
	bar.add_child(_name_edit)
	for spec in [["New 160", 160], ["New 220", 220]]:
		var b := Button.new()
		b.text = str(spec[0])
		b.pressed.connect(func() -> void: new_map(int(spec[1])))
		bar.add_child(b)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save_pressed)
	bar.add_child(save_btn)
	var load_btn := OptionButton.new()
	load_btn.name = "LoadList"
	load_btn.pressed.connect(func() -> void: _refresh_load_list(load_btn))
	load_btn.item_selected.connect(_on_load_selected.bind(load_btn))
	bar.add_child(load_btn)
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.pressed.connect(_on_delete_pressed.bind(load_btn))
	bar.add_child(del_btn)
	var play_btn := Button.new()
	play_btn.text = "Playtest"
	play_btn.pressed.connect(_on_playtest_pressed)
	bar.add_child(play_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(MENU_SCENE))
	bar.add_child(back_btn)
	# Tool palette (left column, under the top bar — anchored top so
	# the full tool list fits on screen at 720p).
	var palette := VBoxContainer.new()
	palette.set_anchors_preset(Control.PRESET_TOP_LEFT)
	palette.position = Vector2(8, 48)
	palette.add_theme_constant_override("separation", 4)
	layer.add_child(palette)
	_tool_label = Label.new()
	_tool_label.text = "Tool: Tier +3"
	palette.add_child(_tool_label)
	var tools := [
		["Tier +3", TOOL_TIER, 3], ["Tier +6", TOOL_TIER, 6],
		["Tier +9", TOOL_TIER, 9], ["Ramp", TOOL_RAMP, 0],
		["Pond", TOOL_POND, 0], ["Node: Wood", TOOL_NODE, 0],
		["Node: Food", TOOL_NODE, 1], ["Node: Gold", TOOL_NODE, 2],
		["Node: Stone", TOOL_NODE, 3], ["Start", TOOL_START, 0],
		["Erase", TOOL_ERASE, 0],
	]
	for t in tools:
		var tb := Button.new()
		tb.text = str(t[0])
		tb.pressed.connect(_pick_tool.bind(str(t[1]), int(t[2]), str(t[0])))
		palette.add_child(tb)
	var size_label := Label.new()
	size_label.text = "Size"
	palette.add_child(size_label)
	var size_slider := HSlider.new()
	size_slider.min_value = 4.0
	size_slider.max_value = 40.0
	size_slider.value = _zone_radius
	size_slider.custom_minimum_size = Vector2(140, 0)
	size_slider.value_changed.connect(func(v: float) -> void:
		_zone_radius = v
		_pond_radius = clampf(v, POND_RADIUS_MIN, POND_RADIUS_MAX)
		_ramp_width = clampf(v, 4.0, 16.0))
	palette.add_child(size_slider)
	# Validation readout (bottom, on a dark panel so it reads over
	# the terrain; offset up so the text sits ON screen).
	var readout_panel := PanelContainer.new()
	readout_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	readout_panel.offset_top = -32
	var rstyle := StyleBoxFlat.new()
	rstyle.bg_color = Color(0, 0, 0, 0.55)
	readout_panel.add_theme_stylebox_override("panel", rstyle)
	layer.add_child(readout_panel)
	_readout = Label.new()
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout_panel.add_child(_readout)


func _pick_tool(tool: String, arg: int, label: String) -> void:
	_tool = tool
	if tool == TOOL_TIER:
		_tier_height = arg
	elif tool == TOOL_NODE:
		_node_type = WarlordMap.RESOURCE_TYPES[arg]
	_ramp_first = Vector2.INF
	if _tool_label != null:
		_tool_label.text = "Tool: " + label
	_update_readout()


func _refresh_load_list(list: OptionButton) -> void:
	list.clear()
	list.add_item("Standard (built-in)")
	list.set_item_metadata(0, WarlordMap.STANDARD_PATH)
	for e in WarlordMap.list_user_maps():
		var d: Dictionary = e
		list.add_item(str(d.get("name", "?")))
		list.set_item_metadata(list.item_count - 1, str(d.get("path", "")))


func _on_load_selected(index: int, list: OptionButton) -> void:
	var path := str(list.get_item_metadata(index))
	if path != "":
		load_map(path)


func _on_save_pressed() -> void:
	var err := save_map(_name_edit.text, false)
	if err == "exists":
		var dlg := ConfirmationDialog.new()
		dlg.dialog_text = "A map with that name exists. Overwrite it?"
		dlg.confirmed.connect(func() -> void:
			save_map(_name_edit.text, true))
		add_child(dlg)
		dlg.popup_centered()
	elif err != "":
		_readout.text = "Cannot save: " + err
		_readout.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))


func _on_delete_pressed(list: OptionButton) -> void:
	if list.selected < 0:
		return
	var path := str(list.get_item_metadata(list.selected))
	if path == "" or path == WarlordMap.STANDARD_PATH:
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete this saved map?"
	dlg.confirmed.connect(func() -> void: delete_map(path))
	add_child(dlg)
	dlg.popup_centered()


func _on_playtest_pressed() -> void:
	var err := launch_playtest()
	if err != "":
		_readout.text = "Cannot playtest: " + err
		_readout.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
