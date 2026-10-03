extends Control
## Main menu: class select, Steam P2P host/join, and solo mode.

var _lobbies: Array = []
var _selected_lobby := 0
var _in_lobby := false


func _ready() -> void:
	_style_buttons()
	if SteamManager.initialized:
		%PersonaLabel.text = "Logged in as %s" % SteamManager.persona_name
	else:
		%PersonaLabel.text = "Steam not running — solo play available."
		%HostButton.disabled = true
		%RefreshButton.disabled = true
		%JoinButton.disabled = true
	NetworkManager.lobby_list_updated.connect(_on_lobby_list)
	NetworkManager.lobby_created_success.connect(_on_host_ready)
	NetworkManager.lobby_join_succeeded.connect(_on_join_ready)
	NetworkManager.lobby_members_changed.connect(_refresh_members)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	_select_class("warrior")
	_show_menu()
	_refresh_save_ui()
	AudioManager.play_music("menu")


## Show/hide the Continue button and fill in the lifetime stats.
func _refresh_save_ui() -> void:
	if SaveManager.has_run():
		%ContinueButton.visible = true
		%ContinueInfoLabel.visible = true
		%ContinueInfoLabel.text = SaveManager.run_summary()
	else:
		%ContinueButton.visible = false
		%ContinueInfoLabel.visible = false
	var ach := SaveManager.get_unlocked_achievements()
	%StatsLabel.text = "Runs: %d · Kills: %d · Deepest cycle: %d · Achievements: %d" % [
		SaveManager.get_total_runs(),
		SaveManager.get_total_kills(),
		SaveManager.get_deepest_cycle(),
		ach.size(),
	]


func _on_continue_pressed() -> void:
	AudioManager.sfx("ui_click")
	if not NetworkManager.continue_run():
		_set_status("No saved run found.")
		_refresh_save_ui()


func _select_class(class_id: String) -> void:
	NetworkManager.selected_class_id = class_id
	%WarriorButton.button_pressed = class_id == "warrior"
	%RogueButton.button_pressed = class_id == "rogue"
	%MageButton.button_pressed = class_id == "mage"
	var data := load("res://data/classes/%s.tres" % class_id) as ClassData
	if data != null:
		%ClassDescLabel.text = "%s — %s" % [data.display_name, data.description]


func _show_menu() -> void:
	_in_lobby = false
	%LobbyPanel.visible = false
	%MenuPanel.visible = true


func _show_lobby(title: String, can_start: bool) -> void:
	_in_lobby = true
	%MenuPanel.visible = false
	%LobbyPanel.visible = true
	%LobbyTitle.text = title
	%StartButton.visible = can_start
	_refresh_members()


func _refresh_members() -> void:
	if not _in_lobby:
		return
	%MemberList.clear()
	for sid in NetworkManager.lobby_members:
		var marker := " (host)" if sid == NetworkManager.server_id else ""
		%MemberList.add_item(NetworkManager.member_name(sid) + marker)


func _set_status(text: String) -> void:
	%StatusLabel.text = text


# --- Menu buttons ---

func _on_warrior_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("warrior")


func _on_rogue_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("rogue")


func _on_mage_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("mage")


func _on_host_pressed() -> void:
	AudioManager.sfx("ui_click")
	_set_status("Creating lobby...")
	NetworkManager.host_lobby()


func _on_refresh_pressed() -> void:
	AudioManager.sfx("ui_click")
	_set_status("Searching for lobbies...")
	%LobbyList.clear()
	NetworkManager.refresh_lobby_list()


func _on_join_pressed() -> void:
	AudioManager.sfx("ui_click")
	var selected: PackedInt32Array = %LobbyList.get_selected_items()
	if selected.is_empty():
		_set_status("Select a lobby first.")
		return
	var lobby: Dictionary = _lobbies[selected[0]]
	_set_status("Joining %s..." % lobby["name"])
	NetworkManager.join_lobby(int(lobby["id"]))


func _on_solo_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.play_solo()


# --- Lobby panel ---

func _on_start_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.start_game()


func _on_leave_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.leave_lobby()
	_set_status("Left lobby.")
	_show_menu()


# --- Network callbacks ---

func _on_host_ready() -> void:
	_set_status("Lobby created! Waiting for players...")
	_show_lobby("Your Lobby", true)


func _on_join_ready() -> void:
	_set_status("Joined! Waiting for host to start...")
	var title := "Lobby"
	if NetworkManager.lobby_id != 0 and SteamManager.initialized:
		title = Steam.getLobbyData(NetworkManager.lobby_id, "name")
	_show_lobby(title, false)


func _on_lobby_list(lobbies: Array) -> void:
	_lobbies = lobbies
	%LobbyList.clear()
	if lobbies.is_empty():
		_set_status("No lobbies found. Host one!")
		return
	_set_status("Found %d lobb%s." % [lobbies.size(), "y" if lobbies.size() == 1 else "ies"])
	for lobby in lobbies:
		%LobbyList.add_item("%s (%d/%d)" % [lobby["name"], lobby["players"], lobby["max_players"]])


func _on_connection_failed(reason: String) -> void:
	_set_status(reason)
	_show_menu()


## Apply pixel-art button textures to all menu buttons.
func _style_buttons() -> void:
	var normal_tex := load("res://assets/sprites/menu/btn_normal.png") as Texture2D
	var hover_tex := load("res://assets/sprites/menu/btn_hover.png") as Texture2D
	var pressed_tex := load("res://assets/sprites/menu/btn_pressed.png") as Texture2D
	if normal_tex == null:
		return
	var normal := StyleBoxTexture.new()
	normal.texture = normal_tex
	normal.expand_margin_left = 8
	normal.expand_margin_right = 8
	normal.expand_margin_top = 8
	normal.expand_margin_bottom = 8
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxTexture
	hover.texture = hover_tex
	var pressed := normal.duplicate() as StyleBoxTexture
	pressed.texture = pressed_tex
	_apply_to_buttons(self, normal, hover, pressed)


func _apply_to_buttons(node: Node, normal: StyleBoxTexture, hover: StyleBoxTexture, pressed: StyleBoxTexture) -> void:
	for child in node.get_children():
		if child is Button:
			var b := child as Button
			b.add_theme_stylebox_override("normal", normal)
			b.add_theme_stylebox_override("hover", hover)
			b.add_theme_stylebox_override("pressed", pressed)
			b.add_theme_stylebox_override("focus", hover)
			b.add_theme_stylebox_override("disabled", normal)
			b.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
			b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))
		_apply_to_buttons(child, normal, hover, pressed)
