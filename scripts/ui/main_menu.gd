extends Control
## Main menu: phased navigation (Title -> Mode -> Multi/Solo -> setup).

var _lobbies: Array = []
var _in_lobby := false
var _phases: Array = []

const CLASS_DESCS := {
	"warrior": "Warrior — Tanky melee, totems and auras.",
	"rogue": "Rogue — Fast ranged, stealth and burst.",
	"mage": "Mage — Spells, arcane power and aura.",
}


func _ready() -> void:
	_style_buttons()
	_phases = [%TitlePhase, %ModePhase, %MultiPhase, %HostPhase, %JoinPhase, %SoloPhase, %ClassPhase]
	if SteamManager.initialized:
		%PersonaLabel.text = "Logged in as %s" % SteamManager.persona_name
	else:
		%PersonaLabel.text = "Steam not running — solo play available."
		%MultiButton.disabled = true
	NetworkManager.lobby_list_updated.connect(_on_lobby_list)
	NetworkManager.lobby_created_success.connect(_on_host_ready)
	NetworkManager.lobby_join_succeeded.connect(_on_join_ready)
	NetworkManager.lobby_members_changed.connect(_refresh_members)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	_select_class("warrior")
	_select_difficulty(1.0)
	_select_loot(1.0)
	_show_phase("TitlePhase")
	_refresh_title_stats()
	_refresh_solo_ui()
	AudioManager.play_music("menu")


func _show_phase(phase_name: String) -> void:
	_in_lobby = false
	%LobbyPanel.visible = false
	for p in _phases:
		p.visible = (p.name == phase_name)


func _show_lobby(title: String, can_start: bool) -> void:
	_in_lobby = true
	for p in _phases:
		p.visible = false
	%LobbyPanel.visible = true
	%LobbyTitle.text = title
	%StartButton.visible = can_start
	_refresh_members()


# --- Title phase ---

func _refresh_title_stats() -> void:
	var ach := SaveManager.get_unlocked_achievements()
	%StatsLabel.text = "Runs: %d · Kills: %d · Deepest cycle: %d · Achievements: %d" % [
		SaveManager.get_total_runs(),
		SaveManager.get_total_kills(),
		SaveManager.get_deepest_cycle(),
		ach.size(),
	]


func _on_start_game_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("ModePhase")


# --- Mode phase ---

func _on_multi_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("MultiPhase")


func _on_solo_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("SoloPhase")


func _on_mode_back_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("TitlePhase")


# --- Multiplayer phase ---

func _on_host_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("HostPhase")


func _on_join_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("JoinPhase")
	_on_refresh_pressed()


func _on_multi_back_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("ModePhase")


# --- Host setup phase ---

func _select_class(class_id: String) -> void:
	NetworkManager.selected_class_id = class_id
	_update_class_row("HostPhase/HostClassRow", class_id, "HostClassDesc")
	_update_class_row("ClassPhase/ClassRow", class_id, "ClassDescLabel")


func _update_class_row(row_path: String, class_id: String, desc_label: String) -> void:
	var row := get_node_or_null(row_path) as HBoxContainer
	if row == null:
		return
	for child in row.get_children():
		if child is Button:
			var b := child as Button
			var is_sel := (class_id == "warrior" and "Warrior" in b.name) or \
				(class_id == "rogue" and "Rogue" in b.name) or \
				(class_id == "mage" and "Mage" in b.name)
			b.modulate = Color(1.3, 1.25, 1.0) if is_sel else Color(1, 1, 1)
	var desc := get_node_or_null("%" + desc_label) as Label
	if desc != null:
		desc.text = CLASS_DESCS.get(class_id, "")


func _on_host_warrior_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("warrior")


func _on_host_rogue_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("rogue")


func _on_host_mage_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("mage")


func _select_difficulty(value: float) -> void:
	NetworkManager.host_difficulty = value
	var mapping := {"DiffEasy": 0.75, "DiffNormal": 1.0, "DiffHard": 1.5}
	for child in %HostPhase.get_node("DiffRow").get_children():
		if child is Button:
			child.modulate = Color(1.3, 1.25, 1.0) if mapping.get(child.name, 1.0) == value else Color(1, 1, 1)


func _on_diff_easy_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_difficulty(0.75)


func _on_diff_normal_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_difficulty(1.0)


func _on_diff_hard_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_difficulty(1.5)


func _select_loot(value: float) -> void:
	NetworkManager.host_loot_mult = value
	var mapping := {"LootHalf": 0.5, "LootNormal": 1.0, "LootDouble": 2.0}
	for child in %HostPhase.get_node("LootRow").get_children():
		if child is Button:
			child.modulate = Color(1.3, 1.25, 1.0) if mapping.get(child.name, 1.0) == value else Color(1, 1, 1)


func _on_loot_half_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_loot(0.5)


func _on_loot_normal_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_loot(1.0)


func _on_loot_double_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_loot(2.0)


func _on_create_lobby_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.host_lobby()


func _on_host_back_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("MultiPhase")


# --- Join phase ---

func _on_refresh_pressed() -> void:
	AudioManager.sfx("ui_click")
	%JoinStatusLabel.text = "Searching for lobbies..."
	%LobbyList.clear()
	NetworkManager.refresh_lobby_list()


func _on_join_selected_pressed() -> void:
	AudioManager.sfx("ui_click")
	var selected: PackedInt32Array = %LobbyList.get_selected_items()
	if selected.is_empty():
		%JoinStatusLabel.text = "Select a lobby first."
		return
	var lobby: Dictionary = _lobbies[selected[0]]
	%JoinStatusLabel.text = "Joining %s..." % lobby["name"]
	NetworkManager.join_lobby(int(lobby["id"]))


func _on_join_back_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("MultiPhase")


# --- Solo phase ---

func _refresh_solo_ui() -> void:
	if SaveManager.has_run():
		%ContinueButton.visible = true
		%ContinueInfoLabel.visible = true
		%ContinueInfoLabel.text = SaveManager.run_summary()
	else:
		%ContinueButton.visible = false
		%ContinueInfoLabel.visible = false


func _on_new_game_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("ClassPhase")


func _on_continue_pressed() -> void:
	AudioManager.sfx("ui_click")
	if not NetworkManager.continue_run():
		%ContinueInfoLabel.text = "No saved run found."
		_refresh_solo_ui()


func _on_solo_back_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("ModePhase")


# --- Class select phase (solo) ---

func _on_warrior_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("warrior")


func _on_rogue_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("rogue")


func _on_mage_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("mage")


func _on_start_solo_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.play_solo()


func _on_class_back_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("SoloPhase")


# --- Lobby panel ---

func _refresh_members() -> void:
	if not _in_lobby:
		return
	%MemberList.clear()
	for sid in NetworkManager.lobby_members:
		var marker := " (host)" if sid == NetworkManager.server_id else ""
		%MemberList.add_item(NetworkManager.member_name(sid) + marker)


func _on_start_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.start_game()


func _on_leave_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.leave_lobby()
	_show_phase("TitlePhase")


# --- Network callbacks ---

func _on_host_ready() -> void:
	_show_lobby("Your Lobby", true)


func _on_join_ready() -> void:
	var title := "Lobby"
	if NetworkManager.lobby_id != 0 and SteamManager.initialized:
		title = Steam.getLobbyData(NetworkManager.lobby_id, "name")
	_show_lobby(title, false)


func _on_lobby_list(lobbies: Array) -> void:
	_lobbies = lobbies
	%LobbyList.clear()
	if lobbies.is_empty():
		%JoinStatusLabel.text = "No lobbies found. Host one!"
		return
	%JoinStatusLabel.text = "Found %d lobb%s." % [lobbies.size(), "y" if lobbies.size() == 1 else "ies"]
	for lobby in lobbies:
		%LobbyList.add_item("%s (%d/%d)" % [lobby["name"], lobby["players"], lobby["max_players"]])


func _on_connection_failed(reason: String) -> void:
	%JoinStatusLabel.text = reason
	_show_phase("JoinPhase")


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
