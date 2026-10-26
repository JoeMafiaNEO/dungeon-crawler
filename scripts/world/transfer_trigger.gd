class_name TransferTrigger
extends Area3D
## The transfer trigger on every playable building's door
## (issue #204 shipped the component + record + doorstep;
## issue #205 S1 wires it): using the door is the party
## transfer INTO the building — party-together (F0), the
## whole party gathers to the ground floor. A second
## building's door cannot be used while the party is inside
## one: the party is in the floor scene then, not the street
## (emergent from the transfer shape, no separate lock).
##
## Issue #209: the door is also where the building's
## clear-time board lives — interacting opens a door panel
## (the cab-panel idiom) showing the board's top 5; Enter
## building runs the existing transfer unchanged.

var building_key := ""
var doorstep := Vector3.ZERO
var record: Dictionary = {}

var _panel: CanvasLayer = null
var _rows_box: VBoxContainer = null
var _player: Node = null


func _board() -> String:
	return Leaderboard.board_name_for(building_key)


func prompt_text() -> String:
	# The cached best rides the prompt when the local player
	# has one; prompt rendering never fetches (the cache is
	# warmed by panel opens and by clear posts).
	var best := Leaderboard.player_best(_board())
	if best >= 0:
		return "Enter building · Best " + Leaderboard.format_score(
			_board(), best)
	return "Enter building"


func interact(player: Node) -> void:
	if building_key == "":
		return
	if Dungeon.floor_active():
		return # the party is already inside a building
	_player = player
	_toggle_panel()


func activate(_player: Node) -> void:
	if building_key == "":
		return
	if Dungeon.floor_active():
		return # the party is already inside a building
	NetworkManager.rpc("load_floor", building_key, 0, true)


func _header_text() -> String:
	var floors := int(record.get("floors", 0))
	if FloorGen.is_home_key(building_key, Dungeon.home_anchor):
		return "Home — %d floors" % floors
	return "%s — %d floors" % [
		str(record.get("kind", "city")).capitalize(), floors]


func _toggle_panel() -> void:
	if _panel != null:
		_close_panel()
		return
	Leaderboard.ensure_board(_board())
	Leaderboard.fetch_top(_board())
	if not Leaderboard.entries_updated.is_connected(
			_on_entries_updated):
		Leaderboard.entries_updated.connect(_on_entries_updated)
	_panel = CanvasLayer.new()
	_panel.layer = 20
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var title := Label.new()
	title.text = _header_text()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	box.add_child(_rows_box)
	_fill_rows()
	if not Leaderboard.steam_available():
		var note := Label.new()
		note.text = "Steam leaderboards offline"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color",
			Color(0.6, 0.6, 0.6))
		box.add_child(note)
	var enter := Button.new()
	enter.text = "Enter building"
	enter.pressed.connect(func() -> void:
		var p := _player
		_close_panel()
		activate(p))
	box.add_child(enter)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_panel)
	box.add_child(close)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The board's top 5, through the main menu's row shape
## (rank · name · time; the local player's row in gold).
func _fill_rows() -> void:
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		child.queue_free()
	var entries: Array = Leaderboard.get_cached(_board())
	if entries.is_empty():
		var none := Label.new()
		none.text = "No recorded clear yet — set the first time."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_color_override("font_color",
			Color(0.75, 0.75, 0.75))
		_rows_box.add_child(none)
		return
	for i in mini(5, entries.size()):
		var e: Dictionary = entries[i]
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = "%d. %s — %s" % [
			e.get("rank", i + 1), e.get("name", "?"),
			Leaderboard.format_score(_board(),
				int(e.get("score", 0)))]
		if bool(e.get("is_player", false)):
			lbl.add_theme_color_override("font_color",
				Color(1.0, 0.85, 0.3))
		else:
			lbl.add_theme_color_override("font_color",
				Color(0.9, 0.9, 0.9))
		_rows_box.add_child(lbl)


func _on_entries_updated(board_name: String) -> void:
	if _panel != null and board_name == _board():
		_fill_rows()


func _close_panel() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
		_rows_box = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
