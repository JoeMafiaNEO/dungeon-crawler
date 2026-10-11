extends Control
## Main menu: phased navigation (Title -> Mode -> Multi/Solo -> setup).

var _lobbies: Array = []
var _in_lobby := false
var _phases: Array = []
## Issue #4 Phase 5: which MP slot a fresh host targets (set by the slot
## cards / Host Game button before HostPhase is shown).
var _host_slot := 0
## Overwrite-confirm modal state.
var _confirm_overlay: Control
var _confirm_msg: Label
var _confirm_mode := ""
var _confirm_slot := 0
## Issue #17 settings panel state.
var _settings_overlay: Control
## Issue #70: LAN multiplayer UI state.
var _lan_mode_host := false  # True if HostPhase is in LAN mode.
var _lan_mode_join := false  # True if JoinPhase is in LAN mode.
var _lan_ip_label: Label = null
var _lan_ip_field: LineEdit = null
var _lan_name_field: LineEdit = null
var _lan_host_toggle: Button = null
var _lan_join_toggle: Button = null
## Host tab menu state (Jesse 2026-10-11 rework).
var _host_tabs_built := false
var _host_tab_container: TabContainer = null
var _host_tab2: Control = null
var _host_create_button: Button = null
var _host_save_list: VBoxContainer = null
var _host_adv_box: VBoxContainer = null
var _host_loot_custom_row: HBoxContainer = null
var _host_rarity_custom_box: VBoxContainer = null
var _host_pw_field: LineEdit = null

const CLASS_DESCS := {
	"warrior": "Warrior — Tanky melee, totems and auras.",
	"rogue": "Rogue — Fast ranged, stealth and burst.",
	"mage": "Mage — Spells, arcane power and aura.",
	"architect": "Architect — Secret builder: walls, turrets, traps.",
}


func _ready() -> void:
	_style_buttons()
	_phases = [%TitlePhase, %ModePhase, %MultiPhase, %HostPhase, %JoinPhase, %SoloPhase, %StagingPhase, %DailyPhase]
	if SteamManager.initialized:
		%PersonaLabel.text = "Logged in as %s" % SteamManager.persona_name
	else:
		%PersonaLabel.text = "Steam not running — solo play available."
		%MultiButton.disabled = true
	NetworkManager.lobby_list_updated.connect(_on_lobby_list)
	NetworkManager.lobby_created_success.connect(_on_host_ready)
	NetworkManager.lobby_join_succeeded.connect(_on_join_ready)
	NetworkManager.lobby_members_changed.connect(_refresh_members)
	NetworkManager.lobby_members_changed.connect(_refresh_lobby_start)
	NetworkManager.lobby_ready_changed.connect(_refresh_lobby_start)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.continue_staging_ready.connect(_on_staging_ready)
	NetworkManager.lobby_members_changed.connect(_refresh_staging_roster)
	NetworkManager.lobby_members_changed.connect(_refresh_lobby_strip)
	# Issue #9 Phase 1: refresh the leaderboard rows when downloads land.
	Leaderboard.entries_updated.connect(_on_leaderboard_entries)
	_select_class("warrior")
	_select_difficulty(1.0)
	_select_loot(1.0)
	_show_phase("TitlePhase")
	_refresh_title_stats()
	_refresh_solo_ui()
	_build_confirm_modal()
	_build_settings_panel()
	_apply_saved_fullscreen()
	# Jesse 2026-10-11: class selection moved to Lobby (MP) / popup (Solo).
	%TitlePhase.get_node("TitleClassRow").visible = false
	%TitlePhase.get_node("TitleClassDesc").visible = false
	# Jesse 2026-10-11: Daily Challenge hidden for a future update.
	%ModePhase.get_node("DailyButton").visible = false
	# Mason's Cipher: the Architect stays hidden until unlocked.
	%TitleArchitectButton.visible = SaveManager.is_architect_unlocked()
	AudioManager.play_music("menu")


func _show_phase(phase_name: String) -> void:
	_in_lobby = false
	%LobbyPanel.visible = false
	for p in _phases:
		p.visible = (p.name == phase_name)
	# Issue #70: ensure LAN UI exists when Host/Join phases show.
	if phase_name == "HostPhase":
		_build_host_lan_ui()
	elif phase_name == "JoinPhase":
		_build_join_lan_ui()


func _show_lobby(title: String, can_start: bool) -> void:
	_in_lobby = true
	for p in _phases:
		p.visible = false
	%LobbyPanel.visible = true
	%LobbyTitle.text = title
	%StartButton.visible = can_start
	# Jesse 2026-10-11: class selection in lobby (unless save-locked), ready button.
	_build_lobby_class_row()
	_build_lobby_ready_button()
	# Issue #70: kick button for LAN host (kicks selected member).
	_ensure_kick_button()
	_refresh_members()
	_refresh_lobby_start()


## Class selection row in the lobby (hidden if the save locks classes).
func _build_lobby_class_row() -> void:
	var existing := %LobbyPanel.get_node_or_null("LobbyClassRow")
	if existing != null:
		existing.queue_free()
	if NetworkManager.lobby_class_locked:
		return
	var row := HBoxContainer.new()
	row.name = "LobbyClassRow"
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	%LobbyPanel.add_child(row)
	%LobbyPanel.move_child(row, 2)
	for cid in ["warrior", "rogue", "mage", "architect"]:
		if cid == "architect" and not SaveManager.is_architect_unlocked():
			continue
		var b := Button.new()
		b.text = cid.capitalize()
		b.toggle_mode = true
		b.button_pressed = (NetworkManager.selected_class_id == cid)
		b.toggled.connect(_on_lobby_class.bind(cid))
		row.add_child(b)


func _on_lobby_class(pressed: bool, cid: String) -> void:
	AudioManager.sfx("ui_click")
	if pressed:
		NetworkManager.selected_class_id = cid


## Ready button for non-hosts; host sees Start Dungeon (gated on all ready).
func _build_lobby_ready_button() -> void:
	var existing := %LobbyPanel.get_node_or_null("ReadyButton")
	if existing != null:
		existing.queue_free()
	if NetworkManager.is_host:
		return
	var b := Button.new()
	b.name = "ReadyButton"
	b.text = "Ready"
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(160, 48)
	b.toggled.connect(_on_lobby_ready_toggled)
	%LobbyPanel.add_child(b)


func _on_lobby_ready_toggled(pressed: bool) -> void:
	AudioManager.sfx("ui_click")
	var my_id := multiplayer.get_unique_id()
	NetworkManager.lobby_ready[my_id] = pressed
	# Sync to host via RPC (host relays to everyone).
	if not NetworkManager.is_host:
		NetworkManager.rpc_id(NetworkManager.server_peer_id, "sync_ready_state", my_id, pressed)
	_refresh_lobby_start()


func _refresh_lobby_start() -> void:
	# Start Dungeon only works if all players are ready.
	var all_ready := true
	for sid in NetworkManager.lobby_members:
		if sid == NetworkManager.server_peer_id:
			continue
		if not bool(NetworkManager.lobby_ready.get(sid, false)):
			all_ready = false
			break
	%StartButton.disabled = not all_ready


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
	_refresh_multi_ui()
	_show_phase("MultiPhase")


## Simplified multiplayer page (Jesse 2026-10-11): just Host Game / Join Game.
## Save slot selection moved into the Host Game tab menu.
func _refresh_multi_ui() -> void:
	%MpSlotsList.visible = false
	%MpLegacyList.visible = false
	_style_buttons()


func _on_solo_pressed() -> void:
	AudioManager.sfx("ui_click")
	_refresh_solo_ui()
	_show_phase("SoloPhase")


func _on_mode_back_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("TitlePhase")


# --- Daily phase (issue #9 Phase 1 + Phase 2 echo toggle) ---

func _on_daily_pressed() -> void:
	AudioManager.sfx("ui_click")
	_refresh_daily_ui()
	_show_phase("DailyPhase")


## Populate the Daily phase: attempt info, play button state, leaderboard.
func _refresh_daily_ui() -> void:
	var attempted := DailyRun.has_attempted_today()
	var best := DailyRun.get_best_score()
	%DailyInfo.text = "Seed %d · %s\nLocal best: %d%s" % [
		DailyRun.get_today_seed(),
		"Attempt used — come back tomorrow" if attempted else "One attempt per day",
		best,
		"" if Leaderboard.steam_available() else " · Steam leaderboards offline",
	]
	%DailyPlayButton.disabled = attempted
	%DailyPlayButton.tooltip_text = "Already attempted today" if attempted else "Start today's seeded run"
	# Echo toggle (Phase 2): only meaningful when a best echo exists.
	var has_echo := EchoRecorder.has_echo_for_date(DailyRun.get_today_string())
	%RaceEchoCheck.disabled = not has_echo or attempted
	%RaceEchoCheck.button_pressed = false
	EchoRecorder.race_echo = false
	_refresh_leaderboard_panel()
	_style_buttons()


## Fill both boards with exactly MAX_ENTRIES fixed rows (no scrolling by
## construction). Empty rows stay as dimmed placeholders; the player's own
## row is highlighted gold.
func _refresh_leaderboard_panel() -> void:
	_fill_board_rows(%DepthRows, Leaderboard.BOARD_DEPTH)
	_fill_board_rows(%SpeedRows, Leaderboard.BOARD_SPEED)


func _fill_board_rows(rows_node: VBoxContainer, board_name: String) -> void:
	for child in rows_node.get_children():
		child.queue_free()
	var entries: Array = Leaderboard.get_cached(board_name)
	for i in range(Leaderboard.MAX_ENTRIES):
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i < entries.size():
			var e: Dictionary = entries[i]
			lbl.text = "%d. %s — %s" % [
				e.get("rank", i + 1), e.get("name", "?"),
				Leaderboard.format_score(board_name, int(e.get("score", 0)))]
			if bool(e.get("is_player", false)):
				lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			else:
				lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		else:
			lbl.text = "%d. —" % (i + 1)
			lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		rows_node.add_child(lbl)


func _on_leaderboard_entries(_board_name: String) -> void:
	# Only repaint when the Daily phase is visible.
	if %DailyPhase.visible:
		_refresh_leaderboard_panel()


func _on_daily_play_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.play_daily()


func _on_race_echo_toggled(pressed: bool) -> void:
	EchoRecorder.race_echo = pressed
	# Racing a downloaded Workshop echo overrides the local best; clearing
	# the toggle resets to local-only.
	if not pressed:
		EchoRecorder.race_echo_path = ""
	AudioManager.sfx("ui_click")


# --- Workshop echo sharing (issue #9 Phase 3) ---

func _on_top_echoes_pressed() -> void:
	AudioManager.sfx("ui_click")
	if not WorkshopEcho.steam_available():
		%DailyInfo.text = "Steam Workshop offline — cannot fetch top echoes."
		return
	%TopEchoesButton.disabled = true
	%TopEchoesButton.text = "Fetching..."
	WorkshopEcho.query_complete.connect(_on_workshop_query, CONNECT_ONE_SHOT)
	WorkshopEcho.query_today_echoes()


func _on_workshop_query(echoes: Array) -> void:
	%TopEchoesButton.disabled = false
	%TopEchoesButton.text = "Race top echoes"
	for child in %TopEchoesList.get_children():
		child.queue_free()
	if echoes.is_empty():
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = "No shared echoes today — be the first!"
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		%TopEchoesList.add_child(lbl)
		return
	for e in echoes:
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.text = "Race: %s" % str(e.get("title", "Echo"))
		b.pressed.connect(_on_workshop_echo_chosen.bind(int(e.get("file_id", 0))))
		%TopEchoesList.add_child(b)
	_style_buttons()


func _on_workshop_echo_chosen(file_id: int) -> void:
	AudioManager.sfx("ui_click")
	WorkshopEcho.download_complete.connect(_on_workshop_download, CONNECT_ONE_SHOT)
	WorkshopEcho.download_echo(file_id)


func _on_workshop_download(file_id: int, echo_path: String) -> void:
	if echo_path.is_empty() or not FileAccess.file_exists(echo_path):
		return
	# Copy into our echoes dir so the ghost loader finds it.
	var local := "user://echoes/workshop_%d.dat" % file_id
	var src := FileAccess.open(echo_path, FileAccess.READ)
	var dst := FileAccess.open(local, FileAccess.WRITE)
	if src != null and dst != null:
		dst.store_buffer(src.get_buffer(src.get_length()))
		src.close()
		dst.close()
		EchoRecorder.race_echo_path = local
		EchoRecorder.race_echo = true
		%RaceEchoCheck.button_pressed = true
		%DailyInfo.text = "Workshop echo ready — toggle 'Race my best echo' and start!"


func _on_daily_back_pressed() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("ModePhase")


# --- Multiplayer phase ---

# --- Issue #70: LAN multiplayer UI ---

## Build the Steam/LAN toggle + IP display for HostPhase (idempotent).
func _build_host_lan_ui() -> void:
	if _lan_host_toggle != null:
		return
	var phase := %HostPhase as VBoxContainer
	# Toggle row.
	var toggle_row := HBoxContainer.new()
	toggle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var steam_btn := Button.new()
	steam_btn.text = "Steam"
	steam_btn.toggle_mode = true
	steam_btn.button_pressed = true
	var lan_btn := Button.new()
	lan_btn.text = "LAN"
	lan_btn.toggle_mode = true
	steam_btn.toggled.connect(_on_host_transport_toggled.bind(false, lan_btn, steam_btn))
	lan_btn.toggled.connect(_on_host_transport_toggled.bind(true, steam_btn, lan_btn))
	toggle_row.add_child(steam_btn)
	toggle_row.add_child(lan_btn)
	phase.add_child(toggle_row)
	phase.move_child(toggle_row, 1)  # After the title.
	_lan_host_toggle = lan_btn
	# IP display (hidden unless LAN mode).
	_lan_ip_label = Label.new()
	_lan_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lan_ip_label.add_theme_font_size_override("font_size", 28)
	_lan_ip_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	_lan_ip_label.visible = false
	phase.add_child(_lan_ip_label)
	phase.move_child(_lan_ip_label, 2)


func _on_host_transport_toggled(pressed: bool, lan_mode: bool, other: Button, self_btn: Button) -> void:
	if not pressed:
		# Keep one selected. set_pressed_no_signal: changing pressed state
		# programmatically must NOT re-emit toggled, or the two buttons
		# ping-pong each other into infinite recursion (stack overflow).
		self_btn.set_pressed_no_signal(true)
		return
	other.set_pressed_no_signal(false)
	_lan_mode_host = lan_mode
	if _lan_ip_label != null:
		_lan_ip_label.visible = lan_mode
		if lan_mode:
			_lan_ip_label.text = "Join IP: %s:%d" % [NetworkManager.get_lan_ip(), NetworkManager.LAN_PORT]
	AudioManager.sfx("ui_click")


## Build the Steam/LAN toggle + IP/name fields for JoinPhase (idempotent).
func _build_join_lan_ui() -> void:
	if _lan_join_toggle != null:
		return
	var phase := %JoinPhase as VBoxContainer
	var toggle_row := HBoxContainer.new()
	toggle_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var steam_btn := Button.new()
	steam_btn.text = "Steam"
	steam_btn.toggle_mode = true
	steam_btn.button_pressed = true
	var lan_btn := Button.new()
	lan_btn.text = "LAN"
	lan_btn.toggle_mode = true
	steam_btn.toggled.connect(_on_join_transport_toggled.bind(false, lan_btn, steam_btn))
	lan_btn.toggled.connect(_on_join_transport_toggled.bind(true, steam_btn, lan_btn))
	toggle_row.add_child(steam_btn)
	toggle_row.add_child(lan_btn)
	phase.add_child(toggle_row)
	phase.move_child(toggle_row, 1)
	_lan_join_toggle = lan_btn
	# LAN join form (hidden unless LAN mode).
	var form := VBoxContainer.new()
	form.name = "LanJoinForm"
	form.visible = false
	var ip_label := Label.new()
	ip_label.text = "Host IP:"
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form.add_child(ip_label)
	_lan_ip_field = LineEdit.new()
	_lan_ip_field.placeholder_text = "192.168.1.x"
	_lan_ip_field.custom_minimum_size = Vector2(280, 0)
	_lan_ip_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Issues #73/#76: keep the LAN form compact and centered — a
	# full-width LineEdit reads as an unstyled dark band.
	_lan_ip_field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	form.add_child(_lan_ip_field)
	var name_label := Label.new()
	name_label.text = "Your name:"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form.add_child(name_label)
	_lan_name_field = LineEdit.new()
	_lan_name_field.placeholder_text = "Player"
	_lan_name_field.custom_minimum_size = Vector2(280, 0)
	_lan_name_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lan_name_field.max_length = 16
	_lan_name_field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	form.add_child(_lan_name_field)
	var join_btn := Button.new()
	join_btn.text = "Join LAN Game"
	join_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join_btn.pressed.connect(_on_lan_join_pressed)
	form.add_child(join_btn)
	phase.add_child(form)
	phase.move_child(form, 2)


func _on_join_transport_toggled(pressed: bool, lan_mode: bool, other: Button, self_btn: Button) -> void:
	if not pressed:
		# set_pressed_no_signal: never re-emit toggled from inside the
		# handler, or the two buttons recurse into a stack overflow.
		self_btn.set_pressed_no_signal(true)
		return
	other.set_pressed_no_signal(false)
	_lan_mode_join = lan_mode
	var form := %JoinPhase.get_node_or_null("LanJoinForm")
	if form != null:
		form.visible = lan_mode
	# Hide the Steam lobby list in LAN mode.
	var list := %JoinPhase.get_node_or_null("LobbyList")
	if list != null:
		list.visible = not lan_mode
	# Hide the Steam lobby buttons (Refresh/Join Selected) in LAN mode.
	var join_row := %JoinPhase.get_node_or_null("JoinRow")
	if join_row != null:
		join_row.visible = not lan_mode
	AudioManager.sfx("ui_click")


func _on_lan_join_pressed() -> void:
	AudioManager.sfx("ui_click")
	var ip := _lan_ip_field.text.strip_edges()
	var pname := _lan_name_field.text.strip_edges()
	if ip == "":
		# TODO: show error in UI.
		return
	NetworkManager.join_lan(ip, NetworkManager.LAN_PORT, pname)


func _on_host_pressed() -> void:
	AudioManager.sfx("ui_click")
	_build_host_tabs()
	_show_phase("HostPhase")


## Host Game tabbed menu (Jesse 2026-10-11 rework). Scrollbars allowed here.
func _build_host_tabs() -> void:
	if _host_tabs_built:
		_refresh_host_tabs()
		return
	_host_tabs_built = true
	# Hide the legacy HostPhase children; the tabs take over.
	for child in %HostPhase.get_children():
		child.visible = false
	var tabs := TabContainer.new()
	tabs.name = "HostTabs"
	tabs.custom_minimum_size = Vector2(560, 420)
	%HostPhase.add_child(tabs)
	_host_tab_container = tabs
	# --- Tab 1: Connection & Save ---
	var t1 := VBoxContainer.new()
	t1.name = "Connection"
	tabs.add_child(t1)
	var conn_label := Label.new()
	conn_label.text = "Connection"
	conn_label.add_theme_font_size_override("font_size", 18)
	t1.add_child(conn_label)
	var conn_row := HBoxContainer.new()
	conn_row.add_theme_constant_override("separation", 12)
	t1.add_child(conn_row)
	var steam_btn := Button.new()
	steam_btn.name = "SteamBtn"
	steam_btn.text = "Steam"
	steam_btn.toggle_mode = true
	steam_btn.button_pressed = not _lan_mode_host
	steam_btn.toggled.connect(_on_host_conn_toggled.bind(false, steam_btn))
	conn_row.add_child(steam_btn)
	var lan_btn := Button.new()
	lan_btn.name = "LanBtn"
	lan_btn.text = "LAN"
	lan_btn.toggle_mode = true
	lan_btn.button_pressed = _lan_mode_host
	lan_btn.toggled.connect(_on_host_conn_toggled.bind(true, lan_btn))
	conn_row.add_child(lan_btn)
	var save_label := Label.new()
	save_label.text = "Save File (optional — hosting from a save locks Difficulty & Loot)"
	save_label.add_theme_font_size_override("font_size", 18)
	t1.add_child(save_label)
	var save_scroll := ScrollContainer.new()
	save_scroll.custom_minimum_size = Vector2(540, 180)
	t1.add_child(save_scroll)
	_host_save_list = VBoxContainer.new()
	_host_save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_scroll.add_child(_host_save_list)
	_refresh_host_save_list()
	# --- Tab 2: Difficulty & Loot ---
	var t2_scroll := ScrollContainer.new()
	t2_scroll.name = "Difficulty & Loot"
	tabs.add_child(t2_scroll)
	var t2 := VBoxContainer.new()
	t2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t2_scroll.add_child(t2)
	_host_tab2 = t2_scroll
	var diff_label := Label.new()
	diff_label.text = "Difficulty"
	diff_label.add_theme_font_size_override("font_size", 18)
	t2.add_child(diff_label)
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	t2.add_child(diff_row)
	for spec in [["Easy", "easy"], ["Normal", "normal"], ["Hard", "hard"], ["Advanced", "advanced"]]:
		var b := Button.new()
		b.text = spec[0]
		b.toggle_mode = true
		b.button_pressed = (NetworkManager.host_difficulty_preset == spec[1])
		b.toggled.connect(_on_host_diff_preset.bind(spec[1]))
		b.name = "Diff_" + spec[1]
		diff_row.add_child(b)
	_host_adv_box = VBoxContainer.new()
	t2.add_child(_host_adv_box)
	_refresh_adv_box()
	var loot_label := Label.new()
	loot_label.text = "Loot Multiplier"
	loot_label.add_theme_font_size_override("font_size", 18)
	t2.add_child(loot_label)
	var loot_row := HBoxContainer.new()
	loot_row.add_theme_constant_override("separation", 8)
	t2.add_child(loot_row)
	for spec in [["0.5x", 0.5], ["1.0x", 1.0], ["2.0x", 2.0], ["Custom", -1.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.toggle_mode = true
		b.button_pressed = (absf(NetworkManager.host_loot_mult - float(spec[1])) < 0.01) or \
			(float(spec[1]) < 0.0 and NetworkManager.host_loot_mult not in [0.5, 1.0, 2.0])
		b.toggled.connect(_on_host_loot_preset.bind(float(spec[1])))
		b.name = "Loot_" + str(spec[1])
		loot_row.add_child(b)
	_host_loot_custom_row = HBoxContainer.new()
	t2.add_child(_host_loot_custom_row)
	_refresh_loot_custom_row()
	var rar_label := Label.new()
	rar_label.text = "Rarity Distribution"
	rar_label.add_theme_font_size_override("font_size", 18)
	t2.add_child(rar_label)
	var rar_row := HBoxContainer.new()
	rar_row.add_theme_constant_override("separation", 8)
	t2.add_child(rar_row)
	var rar_def := Button.new()
	rar_def.text = "Default"
	rar_def.toggle_mode = true
	rar_def.button_pressed = NetworkManager.custom_rarity.is_empty()
	rar_def.toggled.connect(_on_host_rarity_default.bind(true))
	rar_def.name = "RarDefault"
	rar_row.add_child(rar_def)
	var rar_cus := Button.new()
	rar_cus.text = "Custom"
	rar_cus.toggle_mode = true
	rar_cus.button_pressed = not NetworkManager.custom_rarity.is_empty()
	rar_cus.toggled.connect(_on_host_rarity_default.bind(false))
	rar_cus.name = "RarCustom"
	rar_row.add_child(rar_cus)
	_host_rarity_custom_box = VBoxContainer.new()
	t2.add_child(_host_rarity_custom_box)
	_refresh_rarity_box()
	# --- Tab 3: Lobby Settings ---
	var t3 := VBoxContainer.new()
	t3.name = "Lobby"
	tabs.add_child(t3)
	var pw_label := Label.new()
	pw_label.text = "Lobby Password (default: none)"
	pw_label.add_theme_font_size_override("font_size", 18)
	t3.add_child(pw_label)
	var pw_row := HBoxContainer.new()
	pw_row.add_theme_constant_override("separation", 12)
	t3.add_child(pw_row)
	var pw_toggle := CheckButton.new()
	pw_toggle.text = "Use password"
	pw_toggle.button_pressed = not NetworkManager.lobby_password.is_empty()
	pw_toggle.toggled.connect(_on_host_pw_toggled)
	pw_row.add_child(pw_toggle)
	_host_pw_field = LineEdit.new()
	_host_pw_field.placeholder_text = "Password"
	_host_pw_field.text = NetworkManager.lobby_password
	_host_pw_field.editable = pw_toggle.button_pressed
	_host_pw_field.text_changed.connect(_on_host_pw_changed)
	pw_row.add_child(_host_pw_field)
	var vis_label := Label.new()
	vis_label.text = "Lobby Visibility (Steam only)"
	vis_label.add_theme_font_size_override("font_size", 18)
	t3.add_child(vis_label)
	var vis_row := HBoxContainer.new()
	vis_row.add_theme_constant_override("separation", 8)
	t3.add_child(vis_row)
	for spec in [["Public", "public"], ["Friends Only", "friends"], ["Private", "private"]]:
		var b := Button.new()
		b.text = spec[0]
		b.toggle_mode = true
		b.button_pressed = (NetworkManager.lobby_visibility == spec[1])
		b.toggled.connect(_on_host_visibility.bind(spec[1]))
		vis_row.add_child(b)
	var cap_label := Label.new()
	cap_label.text = "Player Cap (4-12, default 4)"
	cap_label.add_theme_font_size_override("font_size", 18)
	t3.add_child(cap_label)
	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 12)
	t3.add_child(cap_row)
	var cap_slider := HSlider.new()
	cap_slider.min_value = 4
	cap_slider.max_value = 12
	cap_slider.step = 1
	cap_slider.value = NetworkManager.lobby_player_cap
	cap_slider.custom_minimum_size = Vector2(200, 0)
	cap_slider.value_changed.connect(_on_host_cap_changed)
	cap_row.add_child(cap_slider)
	var cap_val := Label.new()
	cap_val.name = "CapVal"
	cap_val.text = str(NetworkManager.lobby_player_cap)
	cap_row.add_child(cap_val)
	var warn := Label.new()
	warn.text = "Warning: players joining a pre-existing save file will start at level 1."
	warn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t3.add_child(warn)
	# --- Bottom buttons ---
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 16)
	bot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	%HostPhase.add_child(bot_row)
	_host_create_button = Button.new()
	_host_create_button.text = "Host"
	_host_create_button.custom_minimum_size = Vector2(160, 48)
	_host_create_button.pressed.connect(_on_host_create_pressed)
	bot_row.add_child(_host_create_button)
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(160, 48)
	back_btn.pressed.connect(_on_host_tabs_back)
	bot_row.add_child(back_btn)
	_style_buttons()
	_refresh_host_tabs()


## Host tab refresh: lock states, button enable.
func _refresh_host_tabs() -> void:
	if _host_tab_container == null:
		return
	var from_save := NetworkManager.host_save_slot >= 0
	# Tab 2 locked when hosting from a save.
	_host_tab_container.set_tab_disabled(1, from_save)
	if from_save and _host_tab_container.current_tab == 1:
		_host_tab_container.current_tab = 0
	_refresh_host_button()


func _refresh_host_button() -> void:
	if _host_create_button == null:
		return
	# Minimum specs: connection chosen (always true — Steam default).
	_host_create_button.disabled = false


func _on_host_conn_toggled(pressed: bool, lan_mode: bool, btn: Button) -> void:
	AudioManager.sfx("ui_click")
	_lan_mode_host = lan_mode
	_refresh_host_button()


func _refresh_host_save_list() -> void:
	if _host_save_list == null:
		return
	for c in _host_save_list.get_children():
		c.queue_free()
	# "Fresh run" option.
	var fresh := Button.new()
	fresh.text = "Fresh Run (no save)"
	fresh.toggle_mode = true
	fresh.button_pressed = (NetworkManager.host_save_slot < 0)
	fresh.toggled.connect(_on_host_save_selected.bind(-1))
	_host_save_list.add_child(fresh)
	for slot in range(SaveManager.MAX_SLOTS):
		if not SaveManager.has_run(SaveManager.MODE_MP, slot):
			continue
		var run: Dictionary = SaveManager.load_run(SaveManager.MODE_MP, slot)
		var summary := SaveManager.run_summary(run)
		var b := Button.new()
		b.text = "Slot %d: %s" % [slot + 1, summary]
		b.toggle_mode = true
		b.button_pressed = (NetworkManager.host_save_slot == slot)
		b.toggled.connect(_on_host_save_selected.bind(slot))
		_host_save_list.add_child(b)


func _on_host_save_selected(pressed: bool, slot: int) -> void:
	AudioManager.sfx("ui_click")
	if pressed:
		NetworkManager.host_save_slot = slot
	else:
		NetworkManager.host_save_slot = -1
	_refresh_host_save_list()
	_refresh_host_tabs()


func _on_host_diff_preset(pressed: bool, preset: String) -> void:
	AudioManager.sfx("ui_click")
	if not pressed:
		return
	NetworkManager.host_difficulty_preset = preset
	match preset:
		"easy":
			NetworkManager.host_difficulty = 0.75
		"normal":
			NetworkManager.host_difficulty = 1.0
		"hard":
			NetworkManager.host_difficulty = 1.5
		"advanced":
			NetworkManager.host_difficulty = 1.0
	_refresh_adv_box()
	_refresh_host_button()


func _refresh_adv_box() -> void:
	if _host_adv_box == null:
		return
	for c in _host_adv_box.get_children():
		c.queue_free()
	if NetworkManager.host_difficulty_preset != "advanced":
		return
	var title := Label.new()
	title.text = "Advanced Multipliers"
	_host_adv_box.add_child(title)
	for spec in [
		["Mob HP / round", "adv_mob_hp_mult", 0.5, 3.0],
		["Mob Dmg / round", "adv_mob_dmg_mult", 0.5, 3.0],
		["Mob max spawn", "adv_mob_max_spawn", 4, 32],
		["Boss HP / round", "adv_boss_hp_mult", 0.5, 3.0],
		["Boss Dmg / round", "adv_boss_dmg_mult", 0.5, 3.0],
		["Wave credits mult", "adv_wave_credits_mult", 0.5, 3.0],
	]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var lab := Label.new()
		lab.text = spec[0]
		lab.custom_minimum_size = Vector2(160, 0)
		row.add_child(lab)
		var slider := HSlider.new()
		slider.min_value = float(spec[2])
		slider.max_value = float(spec[3])
		slider.step = 0.1 if spec[1] != "adv_mob_max_spawn" else 1.0
		slider.custom_minimum_size = Vector2(180, 0)
		var key := str(spec[1])
		if key == "adv_mob_max_spawn":
			slider.value = NetworkManager.adv_mob_max_spawn
		else:
			slider.value = float(NetworkManager.get(key))
		slider.value_changed.connect(_on_host_adv_changed.bind(key))
		row.add_child(slider)
		var val := Label.new()
		val.name = "AdvVal_" + key
		val.text = str(slider.value)
		row.add_child(val)
		_host_adv_box.add_child(row)


func _on_host_adv_changed(value: float, key: String) -> void:
	if key == "adv_mob_max_spawn":
		NetworkManager.adv_mob_max_spawn = int(value)
	else:
		NetworkManager.set(key, value)
	if _host_adv_box != null:
		var lab := _host_adv_box.find_child("AdvVal_" + key, true, false) as Label
		if lab != null:
			lab.text = str(value)


func _on_host_loot_preset(pressed: bool, mult: float) -> void:
	AudioManager.sfx("ui_click")
	if not pressed:
		return
	if mult < 0.0:
		# Custom: keep current or default to 1.0.
		if NetworkManager.host_loot_mult in [0.5, 1.0, 2.0]:
			NetworkManager.host_loot_mult = 1.0
	else:
		NetworkManager.host_loot_mult = mult
	_refresh_loot_custom_row()
	_refresh_host_button()


func _refresh_loot_custom_row() -> void:
	if _host_loot_custom_row == null:
		return
	for c in _host_loot_custom_row.get_children():
		c.queue_free()
	var is_custom := NetworkManager.host_loot_mult not in [0.5, 1.0, 2.0]
	if not is_custom:
		return
	var lab := Label.new()
	lab.text = "Custom multiplier:"
	_host_loot_custom_row.add_child(lab)
	var slider := HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 5.0
	slider.step = 0.1
	slider.value = NetworkManager.host_loot_mult
	slider.custom_minimum_size = Vector2(180, 0)
	slider.value_changed.connect(_on_host_loot_custom_changed)
	_host_loot_custom_row.add_child(slider)
	var val := Label.new()
	val.name = "LootCustomVal"
	val.text = "%.1fx" % slider.value
	_host_loot_custom_row.add_child(val)


func _on_host_loot_custom_changed(value: float) -> void:
	NetworkManager.host_loot_mult = value
	if _host_loot_custom_row != null:
		var lab := _host_loot_custom_row.find_child("LootCustomVal", true, false) as Label
		if lab != null:
			lab.text = "%.1fx" % value


func _on_host_rarity_default(pressed: bool, is_default: bool) -> void:
	AudioManager.sfx("ui_click")
	if not pressed:
		return
	if is_default:
		NetworkManager.custom_rarity.clear()
	else:
		# Start from an even split; user adjusts.
		NetworkManager.custom_rarity = {"common": 50.0, "uncommon": 25.0, "rare": 15.0, "epic": 7.0, "legendary": 3.0}
	_refresh_rarity_box()


func _refresh_rarity_box() -> void:
	if _host_rarity_custom_box == null:
		return
	for c in _host_rarity_custom_box.get_children():
		c.queue_free()
	if NetworkManager.custom_rarity.is_empty():
		return
	var total := 0.0
	for rar in ["common", "uncommon", "rare", "epic", "legendary"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var lab := Label.new()
		lab.text = rar.capitalize()
		lab.custom_minimum_size = Vector2(120, 0)
		row.add_child(lab)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = float(NetworkManager.custom_rarity.get(rar, 0.0))
		slider.custom_minimum_size = Vector2(180, 0)
		slider.value_changed.connect(_on_host_rarity_changed.bind(rar))
		row.add_child(slider)
		var val := Label.new()
		val.name = "RarVal_" + rar
		val.text = "%d%%" % int(slider.value)
		row.add_child(val)
		_host_rarity_custom_box.add_child(row)
		total += slider.value
	var total_lab := Label.new()
	total_lab.name = "RarTotal"
	total_lab.text = "Total: %d%% (must equal 100%%)" % int(total)
	total_lab.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4) if int(total) == 100 else Color(1.0, 0.4, 0.4))
	_host_rarity_custom_box.add_child(total_lab)
	_refresh_host_button()


func _on_host_rarity_changed(value: float, rar: String) -> void:
	NetworkManager.custom_rarity[rar] = value
	if _host_rarity_custom_box != null:
		var lab := _host_rarity_custom_box.find_child("RarVal_" + rar, true, false) as Label
		if lab != null:
			lab.text = "%d%%" % int(value)
		var total := 0.0
		for r in NetworkManager.custom_rarity.values():
			total += float(r)
		var tlab := _host_rarity_custom_box.find_child("RarTotal", true, false) as Label
		if tlab != null:
			tlab.text = "Total: %d%% (must equal 100%%)" % int(total)
			tlab.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4) if int(total) == 100 else Color(1.0, 0.4, 0.4))
	_refresh_host_button()


func _on_host_pw_toggled(pressed: bool) -> void:
	AudioManager.sfx("ui_click")
	if _host_pw_field != null:
		_host_pw_field.editable = pressed
	if not pressed:
		NetworkManager.lobby_password = ""
		if _host_pw_field != null:
			_host_pw_field.text = ""


func _on_host_pw_changed(text: String) -> void:
	NetworkManager.lobby_password = text


func _on_host_visibility(pressed: bool, vis: String) -> void:
	AudioManager.sfx("ui_click")
	if pressed:
		NetworkManager.lobby_visibility = vis


func _on_host_cap_changed(value: float) -> void:
	NetworkManager.lobby_player_cap = int(value)
	if _host_tab_container != null:
		var lab := _host_tab_container.find_child("CapVal", true, false) as Label
		if lab != null:
			lab.text = str(int(value))


func _on_host_create_pressed() -> void:
	AudioManager.sfx("ui_click")
	# Validate rarity total if custom.
	if not NetworkManager.custom_rarity.is_empty():
		var total := 0.0
		for r in NetworkManager.custom_rarity.values():
			total += float(r)
		if int(total) != 100:
			AudioManager.sfx("ui_error")
			return
	# Lock class selection if hosting from a save.
	NetworkManager.lobby_class_locked = (NetworkManager.host_save_slot >= 0)
	NetworkManager.lobby_ready.clear()
	if _lan_mode_host:
		NetworkManager.host_lan()
		_show_lobby("LAN Lobby", true)
	else:
		var slot := NetworkManager.host_save_slot
		if slot < 0:
			slot = _first_empty_slot(SaveManager.MODE_MP)
			if slot == -1:
				slot = 0
		_host_slot = slot
		NetworkManager.host_lobby(slot)


func _on_host_tabs_back() -> void:
	AudioManager.sfx("ui_click")
	_show_phase("MultiPhase")


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
	_update_class_row("TitlePhase/TitleClassRow", class_id, "TitleClassDesc")


func _update_class_row(row_path: String, class_id: String, desc_label: String) -> void:
	var row := get_node_or_null(row_path) as HBoxContainer
	if row == null:
		return
	for child in row.get_children():
		if child is Button:
			var b := child as Button
			var is_sel := (class_id == "warrior" and "Warrior" in b.name) or \
				(class_id == "rogue" and "Rogue" in b.name) or \
				(class_id == "mage" and "Mage" in b.name) or \
				(class_id == "architect" and "Architect" in b.name)
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


func _on_host_architect_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("architect")


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
	# Issue #70: LAN host bypasses Steam lobby.
	if _lan_mode_host:
		NetworkManager.lan_player_name = "Host"
		NetworkManager.host_lan()
		return
	# Issue #4 Phase 5: the lobby hosts into the slot chosen on the MP saves UI.
	NetworkManager.host_lobby(_host_slot)


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
	if _lan_mode_join:
		# Jesse 2026-10-08: the Steam list must be hidden in LAN mode, but if
		# it ever isn't, don't silently fire a Steam join — redirect to the
		# LAN form instead of hanging on "Joining...".
		%JoinStatusLabel.text = "LAN mode: enter the host IP below and press Join LAN Game."
		return
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

## Show the solo slot cards (issue #4 Phase 5): one card per solo slot with
## its run summary, per-slot Continue / New Run, and legacy overflow rows.
func _refresh_solo_ui() -> void:
	for child in %SoloSlotsList.get_children():
		child.queue_free()
	for slot in range(SaveManager.MAX_SLOTS):
		%SoloSlotsList.add_child(_build_slot_card(SaveManager.MODE_SOLO, slot))
	_refresh_legacy_rows(%SoloLegacyList, SaveManager.MODE_SOLO)
	_style_buttons()


## Build one slot card row: slot label + summary (or a clean empty state) +
## actions. Occupied slots get Continue + New (New asks before overwriting);
## empty slots get a single New Run button.
func _build_slot_card(mode: String, slot: int) -> MarginContainer:
	# Issue #35: wrap in MarginContainer so labels don't touch x=0,
	# buttons aren't flush at edge, and the gold border isn't clipped.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	# Issue #74: keep each slot card a compact centered row. A full-width
	# row pinned the action buttons to the far screen edge, detached from
	# the slot label; a 560px centered card reads as one row.
	margin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	margin.custom_minimum_size = Vector2(560, 0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var slot_lbl := Label.new()
	slot_lbl.text = "Slot %d" % (slot + 1)
	slot_lbl.custom_minimum_size = Vector2(64, 0)
	row.add_child(slot_lbl)
	var meta := Label.new()
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.clip_text = true
	row.add_child(meta)
	if SaveManager.has_run(mode, slot):
		meta.text = SaveManager.run_summary(SaveManager.load_run(mode, slot))
		var cont := Button.new()
		cont.text = "Continue"
		cont.pressed.connect(_on_slot_continue_pressed.bind(mode, slot))
		if not SaveManager.is_save_compatible(mode, slot):
			cont.disabled = true
			cont.tooltip_text = "Save from an older version"
		row.add_child(cont)
		var new_btn := Button.new()
		new_btn.text = "New"
		new_btn.tooltip_text = "Start a new run in this slot (asks before overwriting)"
		new_btn.pressed.connect(_on_slot_new_pressed.bind(mode, slot))
		row.add_child(new_btn)
	else:
		meta.text = "Empty slot"
		meta.modulate = Color(0.55, 0.55, 0.60)
		var new_btn := Button.new()
		new_btn.text = "New Run"
		new_btn.pressed.connect(_on_slot_new_pressed.bind(mode, slot))
		row.add_child(new_btn)
	return margin


## First empty slot for the mode, or -1 when all are occupied.
func _first_empty_slot(mode: String) -> int:
	for slot in range(SaveManager.MAX_SLOTS):
		if not SaveManager.has_run(mode, slot):
			return slot
	return -1


## Legacy overflow rows: at most 2, only when unmigrated legacy saves exist
## for this mode (issue #4 Phase 5).
func _refresh_legacy_rows(list_node: VBoxContainer, mode: String) -> void:
	for child in list_node.get_children():
		child.queue_free()
	var total := 0
	var shown := 0
	for entry in SaveManager.list_legacy_saves():
		if str(entry.get("mode", "")) != mode:
			continue
		total += 1
		if shown >= 2:
			continue
		shown += 1
		var lbl := Label.new()
		lbl.text = "Legacy: %s · %s" % [
			str(entry.get("path", "")).get_file(),
			SaveManager.run_summary(entry.get("run", {})),
		]
		lbl.modulate = Color(0.65, 0.60, 0.50)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_node.add_child(lbl)
	if total > 2:
		var more := Label.new()
		more.text = "+%d more legacy saves on disk" % (total - 2)
		more.modulate = Color(0.55, 0.52, 0.45)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_node.add_child(more)


func _on_slot_continue_pressed(mode: String, slot: int) -> void:
	AudioManager.sfx("ui_click")
	if not NetworkManager.continue_run(mode, slot):
		if mode == SaveManager.MODE_SOLO:
			_refresh_solo_ui()
		else:
			_refresh_multi_ui()


func _on_slot_new_pressed(mode: String, slot: int) -> void:
	AudioManager.sfx("ui_click")
	if SaveManager.has_run(mode, slot):
		_show_overwrite_confirm(mode, slot)
		return
	if mode == SaveManager.MODE_MP:
		_host_slot = slot
		_build_host_tabs()
		_show_phase("HostPhase")
	else:
		# Jesse 2026-10-11: class selection popup before starting a solo run.
		_show_solo_class_popup(slot)


## Class popup for solo new/overwrite: pick a class, then start the run.
func _show_solo_class_popup(slot: int) -> void:
	var overlay := Control.new()
	overlay.name = "SoloClassPopup"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Choose Your Class"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)
	for cid in ["warrior", "rogue", "mage", "architect"]:
		if cid == "architect" and not SaveManager.is_architect_unlocked():
			continue
		var b := Button.new()
		b.text = cid.capitalize()
		b.custom_minimum_size = Vector2(220, 44)
		b.pressed.connect(_on_solo_class_chosen.bind(cid, slot, overlay))
		vb.add_child(b)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(220, 44)
	cancel.pressed.connect(func() -> void: overlay.queue_free())
	vb.add_child(cancel)
	add_child(overlay)
	_style_buttons()


func _on_solo_class_chosen(cid: String, slot: int, overlay: Control) -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.selected_class_id = cid
	overlay.queue_free()
	NetworkManager.play_solo(slot)


## Build the overwrite-confirm modal (issue #4 Phase 5): a dimmed overlay
## with a compact dialog. Shown when a New Run targets an occupied slot.
func _build_confirm_modal() -> void:
	_confirm_overlay = Control.new()
	_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.10, 0.98)
	sb.border_color = Color(0.85, 0.70, 0.30)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	_confirm_msg = Label.new()
	_confirm_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_msg.custom_minimum_size = Vector2(420, 0)
	vb.add_child(_confirm_msg)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	var yes := Button.new()
	yes.text = "Overwrite"
	yes.pressed.connect(_on_overwrite_confirmed)
	hb.add_child(yes)
	var no := Button.new()
	no.text = "Cancel"
	no.pressed.connect(_on_overwrite_cancelled)
	hb.add_child(no)
	add_child(_confirm_overlay)
	_style_buttons()


## Issue #17 Phase 1: compact settings panel (modal). Fixed layout,
## zero-scroll by construction. Sliders wire live to AudioManager;
## toggles persist to the profile (CRT/shake/fullscreen applied in Phase 2).
func _build_settings_panel() -> void:
	_settings_overlay = Control.new()
	_settings_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.10, 0.98)
	sb.border_color = Color(0.85, 0.70, 0.30)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(title)
	for spec in [["Master", "master_vol"], ["Music", "music_vol"], ["SFX", "sfx_vol"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var lab := Label.new()
		lab.text = spec[0]
		lab.custom_minimum_size = Vector2(70, 0)
		row.add_child(lab)
		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(220, 0)
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = _settings_vol_default(spec[1])
		slider.value_changed.connect(_on_settings_vol_changed.bind(spec[1]))
		row.add_child(slider)
		var val := Label.new()
		val.name = "Val_%s" % spec[1]
		val.text = "%d" % int(slider.value)
		val.custom_minimum_size = Vector2(40, 0)
		row.add_child(val)
		vb.add_child(row)
	# FOV slider (60-100, default 75).
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 12)
	frow.alignment = BoxContainer.ALIGNMENT_CENTER
	var flab := Label.new()
	flab.text = "FOV"
	flab.custom_minimum_size = Vector2(70, 0)
	frow.add_child(flab)
	var fslider := HSlider.new()
	fslider.custom_minimum_size = Vector2(220, 0)
	fslider.min_value = 60
	fslider.max_value = 100
	fslider.step = 1
	fslider.value = float(SaveManager.get_profile_setting("settings", "fov", 75.0))
	fslider.value_changed.connect(_on_settings_vol_changed.bind("fov"))
	frow.add_child(fslider)
	var fval := Label.new()
	fval.name = "Val_fov"
	fval.text = "%d" % int(fslider.value)
	fval.custom_minimum_size = Vector2(40, 0)
	frow.add_child(fval)
	vb.add_child(frow)
	for spec in [["CRT filter", "crt_enabled", true], ["Screen shake", "shake_enabled", true], ["Fullscreen", "fullscreen", false]]:
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 12)
		trow.alignment = BoxContainer.ALIGNMENT_CENTER
		var tlab := Label.new()
		tlab.text = spec[0]
		tlab.custom_minimum_size = Vector2(150, 0)
		trow.add_child(tlab)
		var tog := CheckButton.new()
		tog.button_pressed = _settings_toggle_default(spec[1], spec[2])
		tog.toggled.connect(_on_settings_toggle_changed.bind(spec[1]))
		trow.add_child(tog)
		vb.add_child(trow)
	# Issue #33 Phase 1: language picker. OptionButton with supported locales.
	# Phase 1 ships English only; es/fr/de are listed for Phase 3 (selecting
	# them falls back to English until translations land).
	# Language picker removed 2026-10-06: localization disabled, English only.
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: _settings_overlay.visible = false)
	vb.add_child(close)
	add_child(_settings_overlay)
	_style_buttons()


## Language switching disabled 2026-10-06 (localization reverted to English-only).
## Handler kept as a no-op stub in case any old signal connection references it.
func _on_settings_language_changed(_index: int) -> void:
	return


func _settings_vol_default(key: String) -> float:
	match key:
		"master_vol":
			return float(SaveManager.get_profile_setting("settings", "master_vol", 1.0)) * 100.0
		"music_vol":
			return float(SaveManager.get_profile_setting("settings", "music_vol", 0.8)) * 100.0
		"sfx_vol":
			return float(SaveManager.get_profile_setting("settings", "sfx_vol", 1.0)) * 100.0
	return 100.0


func _settings_toggle_default(key: String, fallback: bool) -> bool:
	return bool(SaveManager.get_profile_setting("settings", key, fallback))


func _on_settings_vol_changed(value: float, key: String) -> void:
	var v := value / 100.0
	match key:
		"master_vol":
			AudioManager.set_master_vol(v)
		"music_vol":
			AudioManager.set_music_vol(v)
		"sfx_vol":
			AudioManager.set_sfx_vol(v)
		"fov":
			SaveManager.set_profile_setting("settings", "fov", float(value))
	if _settings_overlay != null:
		var lab := _settings_overlay.find_child("Val_%s" % key, true, false) as Label
		if lab != null:
			lab.text = "%d" % int(value)


func _on_settings_toggle_changed(pressed: bool, key: String) -> void:
	# Issue #17 Phase 2: CRT and fullscreen apply immediately.
	match key:
		"crt_enabled":
			if has_node("/root/CRTManager"):
				get_node("/root/CRTManager").set_crt_enabled(pressed)
			else:
				SaveManager.set_profile_setting("settings", key, pressed)
		"fullscreen":
			_apply_fullscreen(pressed)
		_:
			SaveManager.set_profile_setting("settings", key, pressed)


func _apply_fullscreen(enabled: bool) -> void:
	SaveManager.set_profile_setting("settings", "fullscreen", enabled)
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_saved_fullscreen() -> void:
	var fs := bool(SaveManager.get_profile_setting("settings", "fullscreen", false))
	if fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_settings_pressed() -> void:
	AudioManager.sfx("ui_click")
	_settings_overlay.visible = true


func _show_overwrite_confirm(mode: String, slot: int) -> void:
	_confirm_mode = mode
	_confirm_slot = slot
	var run := SaveManager.load_run(mode, slot)
	_confirm_msg.text = "Slot %d already holds a saved run:\n%s\n\nStart a new run and overwrite it?" % [
		slot + 1, SaveManager.run_summary(run)]
	_confirm_overlay.visible = true


func _on_overwrite_confirmed() -> void:
	AudioManager.sfx("ui_click")
	_confirm_overlay.visible = false
	if _confirm_mode == SaveManager.MODE_MP:
		_host_slot = _confirm_slot
		_build_host_tabs()
		_show_phase("HostPhase")
	else:
		_show_solo_class_popup(_confirm_slot)


func _on_overwrite_cancelled() -> void:
	AudioManager.sfx("ui_click")
	_confirm_overlay.visible = false


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


func _on_architect_pressed() -> void:
	AudioManager.sfx("ui_click")
	_select_class("architect")


# --- Lobby panel ---

func _refresh_members() -> void:
	if not _in_lobby:
		return
	%MemberList.clear()
	for sid in NetworkManager.lobby_members:
		var marker := " (host)" if sid == NetworkManager.server_id else ""
		%MemberList.add_item(NetworkManager.member_name(sid) + marker)
	# Issue #70: show kick button only for LAN host.
	_update_kick_button()


## Issue #70: ensure the kick button exists in the lobby panel.
func _ensure_kick_button() -> void:
	if %LobbyPanel.get_node_or_null("KickButton") != null:
		return
	var btn := Button.new()
	btn.name = "KickButton"
	btn.text = "Kick Selected"
	btn.visible = false
	btn.pressed.connect(_on_kick_pressed)
	%LobbyPanel.add_child(btn)
	# Place after MemberList, before StartButton.
	%LobbyPanel.move_child(btn, %LobbyPanel.get_children().find(%MemberList) + 1)


func _update_kick_button() -> void:
	var btn := %LobbyPanel.get_node_or_null("KickButton") as Button
	if btn == null:
		return
	btn.visible = (NetworkManager.transport == NetworkManager.Transport.LAN
		and NetworkManager.is_host)


func _on_kick_pressed() -> void:
	AudioManager.sfx("ui_click")
	var sel: PackedInt32Array = %MemberList.get_selected_items()
	if sel.is_empty():
		return
	var idx := sel[0]
	if idx < 0 or idx >= NetworkManager.lobby_members.size():
		return
	var pid: int = NetworkManager.lobby_members[idx]
	if pid == NetworkManager.server_id:
		return  # Can't kick yourself.
	NetworkManager.kick_peer(pid)


func _on_start_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.start_game()


func _on_leave_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.leave_lobby()
	_show_phase("TitlePhase")


# --- Staging (continued run) ---

const STAGING_AUTO_START := 60.0
var _staging_timer := 0.0
var _staging_active := false


func _on_staging_ready() -> void:
	_show_phase("StagingPhase")
	_staging_active = true
	_staging_timer = STAGING_AUTO_START
	%OpenLobbyCheck.button_pressed = false
	Dungeon.continued_open_lobby = false
	_refresh_staging_roster()
	_refresh_lobby_strip()
	# Open the Steam invite dialog so the host can re-invite the crew.
	NetworkManager.open_invite_dialog()


func _process(delta: float) -> void:
	if not _staging_active:
		return
	_staging_timer -= delta
	if _staging_timer <= 0.0:
		_staging_active = false
		_on_start_run_pressed()
		return
	%AutoStartLabel.text = "Auto-start in %ds" % int(ceili(_staging_timer))


func _refresh_staging_roster() -> void:
	if not _staging_active:
		return
	# Clear existing rows.
	for child in %RosterList.get_children():
		child.queue_free()
	var roster: Array = Dungeon.continued_roster
	var run := SaveManager.load_run(SaveManager.MODE_MP, NetworkManager.active_run_slot)
	# Issue #4 Phase 4: the staging screen names the slot being continued.
	%StagingInfo.text = "MP Slot %d · %s" % [NetworkManager.active_run_slot + 1, SaveManager.run_summary(run)]
	var joined := {}
	for sid in NetworkManager.lobby_members:
		joined[int(sid)] = true
	for entry in roster:
		var sid := int(entry.get("steam_id", 0))
		var ps: Dictionary = entry.get("player_state", {})
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		var lbl := Label.new()
		var status := "Joined" if joined.has(sid) else "Waiting"
		var status_color := Color(0.5, 1.0, 0.5) if joined.has(sid) else Color(1.0, 0.8, 0.4)
		lbl.text = "%s — Lv %d %s [%s]" % [
			entry.get("player_name", "?"),
			int(ps.get("level", 1)),
			str(entry.get("class_id", "?")).capitalize(),
			status,
		]
		lbl.add_theme_color_override("font_color", status_color)
		row.add_child(lbl)
		if not joined.has(sid) and not bool(entry.get("is_host", false)):
			var inv := Button.new()
			inv.text = "Invite"
			_style_one_button(inv) # Issue #36: match the menu button style.
			inv.pressed.connect(_on_invite_player_pressed.bind(sid))
			row.add_child(inv)
		%RosterList.add_child(row)


## Jesse 2026-10-10: small live lobby-member strip for the host on the
## continue-run staging screen. Shows who's actually in the Steam lobby
## right now (count + names), updating as members join/leave.
func _refresh_lobby_strip() -> void:
	if not _staging_active:
		return
	var members: Array = NetworkManager.lobby_members
	var names: Array[String] = []
	for sid in members:
		names.append(NetworkManager.member_name(int(sid)))
	%LobbyStripLabel.text = "Lobby (%d):" % members.size()
	%LobbyStripNames.text = ", ".join(names) if not names.is_empty() else "—"


func _on_invite_player_pressed(steam_id: int) -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.invite_friend(steam_id)


func _on_invite_all_pressed() -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.open_invite_dialog()


func _on_open_lobby_toggled(pressed: bool) -> void:
	AudioManager.sfx("ui_click")
	Dungeon.continued_open_lobby = pressed


func _on_start_run_pressed() -> void:
	AudioManager.sfx("ui_click")
	_staging_active = false
	NetworkManager.start_continued_run()


func _on_staging_back_pressed() -> void:
	AudioManager.sfx("ui_click")
	_staging_active = false
	NetworkManager.leave_lobby()
	Dungeon.continued_roster = []
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
	%JoinStatusLabel.text = tr_n("FOUND_LOBBY_ONE", "FOUND_LOBBY_MANY", lobbies.size()) % [lobbies.size()]
	for lobby in lobbies:
		%LobbyList.add_item("%s (%d/%d)" % [lobby["name"], lobby["players"], lobby["max_players"]])


func _on_connection_failed(reason: String) -> void:
	%JoinStatusLabel.text = reason
	_show_phase("JoinPhase")


## Apply pixel-art button textures to all menu buttons.
func _style_buttons() -> void:
	var boxes := _make_button_styleboxes()
	if boxes.is_empty():
		return
	_apply_to_buttons(self, boxes[0], boxes[1], boxes[2])


## Issue #36: style a single dynamically-created button (roster Invite
## buttons are built after _style_buttons runs).
func _style_one_button(b: Button) -> void:
	var boxes := _make_button_styleboxes()
	if boxes.is_empty():
		return
	b.add_theme_stylebox_override("normal", boxes[0])
	b.add_theme_stylebox_override("hover", boxes[1])
	b.add_theme_stylebox_override("pressed", boxes[2])
	b.add_theme_stylebox_override("focus", boxes[1])
	b.add_theme_stylebox_override("disabled", boxes[0])
	b.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))


func _make_button_styleboxes() -> Array:
	var normal_tex := load("res://assets/sprites/menu/btn_normal.png") as Texture2D
	var hover_tex := load("res://assets/sprites/menu/btn_hover.png") as Texture2D
	var pressed_tex := load("res://assets/sprites/menu/btn_pressed.png") as Texture2D
	if normal_tex == null:
		return []
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
	return [normal, hover, pressed]


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
