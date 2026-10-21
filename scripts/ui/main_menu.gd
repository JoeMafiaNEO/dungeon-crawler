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
## Issue #152: the solo class-choice popup overlay (pad B closes it).
var _solo_popup: Control = null
## Issue #152: the confirm modal's Cancel button (its focus primary —
## the non-destructive choice on a destructive confirm).
var _confirm_cancel: Button = null
## Issue #191 (section A): THE RULE — a close returns what the
## open took. Opening an overlay captures the focus owner (the
## opener) and its phase; the matching close hands focus back
## to the opener when it can still take focus, else re-seeds
## the surface underneath through its own phase apply. Focus
## never strands inside a hidden surface (Jesse's Settings
## B-lockout was the rule's first instance: _close_settings
## only hid the overlay, leaving focus owned by an invisible
## Close button).
var _overlay_opener: Control = null
var _overlay_phase := ""


func _phase_node(phase_name: String) -> Control:
	match phase_name:
		"TitlePhase":
			return %TitlePhase
		"ModePhase":
			return %ModePhase
		"MultiPhase":
			return %MultiPhase
		"HostPhase":
			return %HostPhase
		"JoinPhase":
			return %JoinPhase
		"SoloPhase":
			return %SoloPhase
		"StagingPhase":
			return %StagingPhase
		"DailyPhase":
			return %DailyPhase
	return null


func _current_phase_name() -> String:
	for n in ["TitlePhase", "ModePhase", "MultiPhase", "HostPhase",
			"JoinPhase", "SoloPhase", "StagingPhase", "DailyPhase"]:
		var p := _phase_node(n)
		if p != null and p.visible:
			return n
	return ""


func _capture_overlay_return() -> void:
	var vp := get_viewport()
	_overlay_opener = vp.gui_get_focus_owner() if vp != null else null
	_overlay_phase = _current_phase_name()


func _restore_overlay_return() -> void:
	var opener := _overlay_opener
	var phase_name := _overlay_phase
	_overlay_opener = null
	_overlay_phase = ""
	if opener != null and is_instance_valid(opener) and phase_name != "":
		var phase := _phase_node(phase_name)
		if phase != null and FocusChain.collect(phase).has(opener):
			FocusChain.apply(phase, opener)
			return
	if phase_name != "":
		_apply_phase_focus(phase_name)


## --- On-screen keyboard (issue #191, section C) -----------
## The TextEntry seam: the LAN fields summon text entry ONLY
## through _request_text_entry. On pad that opens the built-in
## OSK below (the fields live in the LAN flow — the least-Steam
## context in the game, where a Steam-only keyboard would be a
## dead end); a Steam gamepad-text-input front-end can slot in
## behind this one function later without a field or a panel
## changing. On keyboard/mouse the seam is a no-op and typing
## stays native. The OSK writes live into the bound field
## (the way Steam's keyboard does), and its own close obeys
## section A's rule: focus returns to the field.
var _osk_overlay: Control = null
var _osk_field: LineEdit = null
var _osk_echo: Label = null
var _osk_first_key: Button = null
var _osk_return_suppress := false


func _request_text_entry(field: LineEdit) -> void:
	if _osk_return_suppress:
		_osk_return_suppress = false
		return
	# The summon arrives on focus_entered — INSIDE the
	# engine's focus change. Opening there would grab focus
	# for a key mid-notification (a hard engine crash), so
	# the decision defers to the frame's end.
	call_deferred("_summon_text_entry", field)


## The seam's decision (synchronous): pad source summons
## the built-in OSK for the field; anything else is native.
func _summon_text_entry(field: LineEdit) -> void:
	if field == null or not is_instance_valid(field):
		return
	if not InputSource.is_pad():
		return
	_open_osk(field)


func _open_osk(field: LineEdit) -> void:
	if _osk_overlay == null:
		_build_osk()
	_osk_field = field
	_osk_overlay.visible = true
	_osk_refresh_echo()
	FocusChain.apply(_osk_overlay, _osk_first_key)


func _close_osk() -> void:
	if _osk_overlay != null:
		_osk_overlay.visible = false
	var field := _osk_field
	_osk_field = null
	if field != null and is_instance_valid(field):
		# Section A: focus returns to the opener (the field);
		# the return grab must not re-summon the OSK.
		_osk_return_suppress = true
		field.grab_focus()


func _osk_refresh_echo() -> void:
	if _osk_echo == null or _osk_field == null:
		return
	var text := _osk_field.text
	if _osk_field == _host_pw_field:
		# The password field's echo is MASKED — the OSK never
		# renders the lobby password in clear (hard pin).
		_osk_echo.text = "•".repeat(text.length())
	elif text.is_empty():
		_osk_echo.text = _osk_field.placeholder_text
	else:
		_osk_echo.text = text


func _osk_key(ch: String) -> void:
	if _osk_field == null or not is_instance_valid(_osk_field):
		return
	_osk_field.text += ch
	_osk_field.text_changed.emit(_osk_field.text)
	_osk_refresh_echo()


func _osk_back() -> void:
	if _osk_field == null or not is_instance_valid(_osk_field):
		return
	if not _osk_field.text.is_empty():
		_osk_field.text = _osk_field.text.left(_osk_field.text.length() - 1)
		_osk_field.text_changed.emit(_osk_field.text)
	_osk_refresh_echo()


func _build_osk() -> void:
	_osk_overlay = Control.new()
	_osk_overlay.name = "OskOverlay"
	_osk_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_osk_overlay.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_osk_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_osk_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "OskPanel"
	# The settings overlay's framed-panel dressing (the Art
	# Director's style pass): the OSK wears the menu's own
	# clothes — same StyleBox family, the 0.65 dim untouched.
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.08, 0.07, 0.10, 0.98)
	psb.border_color = Color(0.85, 0.70, 0.30)
	psb.set_border_width_all(3)
	psb.set_corner_radius_all(6)
	psb.content_margin_left = 28
	psb.content_margin_right = 28
	psb.content_margin_top = 20
	psb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	_osk_echo = Label.new()
	_osk_echo.name = "OskEcho"
	_osk_echo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_osk_echo.add_theme_font_size_override("font_size", 22)
	vb.add_child(_osk_echo)
	# Deliberate QWERTY rows (the Art Director's style pass):
	# four centered HBox rows — digits, qwerty, asdf, zxcv —
	# short rows centered against the widest, so a D-pad
	# user's spatial map of the keyboard holds. Keys type
	# the character they show: digits literal, letters
	# lowercase (no shift state in this widget).
	var grid := VBoxContainer.new()
	grid.name = "OskGrid"
	grid.add_theme_constant_override("separation", 6)
	vb.add_child(grid)
	for row in ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]:
		var hrow := HBoxContainer.new()
		hrow.alignment = HBoxContainer.ALIGNMENT_CENTER
		hrow.add_theme_constant_override("separation", 6)
		grid.add_child(hrow)
		for ch in row:
			var b := Button.new()
			b.text = ch
			b.custom_minimum_size = Vector2(46, 44)
			b.pressed.connect(_osk_key.bind(ch))
			hrow.add_child(b)
			if _osk_first_key == null:
				_osk_first_key = b
	var specials := HBoxContainer.new()
	specials.name = "OskSpecials"
	specials.add_theme_constant_override("separation", 6)
	specials.alignment = HBoxContainer.ALIGNMENT_CENTER
	vb.add_child(specials)
	for spec in [[".", "."], ["-", "-"], ["_", "_"], ["Space", " "], ["Back", ""], ["Done", ""]]:
		var sb := Button.new()
		sb.text = spec[0]
		if spec[0] == "Done":
			sb.name = "OskDone"
		sb.custom_minimum_size = Vector2(92, 44)
		if spec[0] == "Back":
			sb.pressed.connect(_osk_back)
		elif spec[0] == "Done":
			sb.pressed.connect(_close_osk)
		else:
			sb.pressed.connect(_osk_key.bind(spec[1]))
		specials.add_child(sb)
	add_child(_osk_overlay)
	_style_buttons()
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
var _host_pw_toggle: CheckButton = null
## Issue #132: Lobby tab controls re-derived per save selection.
var _host_vis_buttons: Dictionary = {}
var _host_cap_slider: HSlider = null
var _host_cap_val: Label = null

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
	NetworkManager.session_lost.connect(_on_session_lost)
	NetworkManager.baked_version_mismatch.connect(_on_baked_version_mismatch)
	NetworkManager.continue_staging_ready.connect(_on_staging_ready)
	NetworkManager.saved_class_notice_received.connect(_on_saved_class_notice)
	NetworkManager.lobby_members_changed.connect(_refresh_staging_roster)
	NetworkManager.lobby_members_changed.connect(_refresh_lobby_strip)
	# Issue #9 Phase 1: refresh the leaderboard rows when downloads land.
	Leaderboard.entries_updated.connect(_on_leaderboard_entries)
	_select_class("warrior")
	_select_difficulty(1.0)
	_select_loot(1.0)
	# Jesse 2026-10-11: unlimited saves — wrap the solo slot list in a scroller.
	_wrap_solo_slots()
	_show_phase("TitlePhase")


## Wrap SoloSlotsList in a ScrollContainer (once) for unlimited saves.
## Stores a direct ref — reparenting breaks the % unique-name lookup.
var _solo_slots_list: VBoxContainer = null


func _wrap_solo_slots() -> void:
	var list := %SoloSlotsList as VBoxContainer
	_solo_slots_list = list
	if list.get_parent() is ScrollContainer:
		return
	var scroll := ScrollContainer.new()
	scroll.name = "SoloSlotsScroll"
	# Issue #191 (section B): focus walking below the fold
	# scrolls the list to the focused row.
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(600, 320)
	var parent := list.get_parent()
	var idx := list.get_index()
	parent.remove_child(list)
	parent.add_child(scroll)
	parent.move_child(scroll, idx)
	scroll.add_child(list)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_apply_phase_focus(phase_name)


## Issue #152 (2A-1): chain the phase's controls and seed focus to its
## primary NON-DESTRUCTIVE control, so a pad user can start navigating
## the moment a surface appears (previously nothing seeded focus —
## grab_focus existed exactly once in the whole UI).
func _apply_phase_focus(phase_name: String) -> void:
	match phase_name:
		"TitlePhase":
			FocusChain.apply(%TitlePhase, %TitleStartButton)
		"ModePhase":
			FocusChain.apply(%ModePhase, %MultiButton)
		"MultiPhase":
			FocusChain.apply(%MultiPhase, %HostButton)
		"HostPhase":
			FocusChain.apply(%HostPhase, _host_tab_container)
		"JoinPhase":
			FocusChain.apply(%JoinPhase, _lan_ip_field if _lan_mode_join else %LobbyList)
		"SoloPhase":
			FocusChain.apply(%SoloPhase, _solo_primary())
		"StagingPhase":
			FocusChain.apply(%StagingPhase, %StartRunButton)
		"DailyPhase":
			FocusChain.apply(%DailyPhase, %DailyPlayButton)


## Solo's primary: the first focusable slot-card control, else Back.
func _solo_primary() -> Control:
	if _solo_slots_list != null:
		var cards := FocusChain.collect(_solo_slots_list)
		if not cards.is_empty():
			return cards[0]
	return %SoloBackButton


func _show_lobby(title: String, can_start: bool) -> void:
	_in_lobby = true
	# A fresh lobby showing starts the reselect interaction clean:
	# no pick made yet, nothing awaiting a warning decision.
	_lobby_class_touched = false
	_pending_reselect_class = ""
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
	# Issue #152: lobby chain (tree order is the panel's visual order);
	# primary is Ready, per the spec's per-surface table.
	var ready_btn := %LobbyPanel.get_node_or_null("ReadyButton") as Control
	FocusChain.apply(%LobbyPanel, ready_btn)


## Issue #152 (2A-1): pad Back + host tab switching. B (ui_cancel on
## the pad) invokes the SAME handler as the visible surface's
## on-screen Back/Close — one code path per surface. Keyboard Esc is
## deliberately NOT routed here: no menu surface consumed it before,
## and it keeps exactly that behavior; Tab stays focus navigation.
func _input(event: InputEvent) -> void:
	# Issue #152: Godot's Range controls adjust only on real key
	# events — a pad ui_left/right press on a focused slider falls
	# through to focus navigation and the value never changes
	# (probed live, 2026-10-16). Bridge it here so "ui_left/right
	# adjust" holds on pad too: nudge the focused slider by its
	# step and consume the event. Keyboard arrows land on the same
	# path with the same net effect as the native adjust.
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var foc := get_viewport().gui_get_focus_owner()
		if foc is Range and (foc as Range).editable:
			var r := foc as Range
			var dir := 1.0 if event.is_action_pressed("ui_right") else -1.0
			r.value = clampf(r.value + dir * r.step, r.min_value, r.max_value)
			get_viewport().set_input_as_handled()
			return
	# Host tabs: the TabContainer holds a slot in the host chain;
	# Left/Right while IT owns focus switch pages (the native tab-bar
	# keys never reach it from the pad).
	if _host_tabs_built and _host_tab_container != null and %HostPhase.visible \
			and get_viewport().gui_get_focus_owner() == _host_tab_container \
			and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
		var dir := 1 if event.is_action_pressed("ui_right") else -1
		var count := _host_tab_container.get_tab_count()
		var t := _host_tab_container.current_tab
		for i in count:
			t = (t + dir + count) % count
			if not _host_tab_container.is_tab_disabled(t):
				break
		if t != _host_tab_container.current_tab:
			_host_tab_container.current_tab = t
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):
		_menu_back()


func _menu_back() -> void:
	# Topmost overlays first, then the lobby, then the phase stack.
	if _osk_overlay != null and _osk_overlay.visible:
		_close_osk()
	elif _solo_popup != null and is_instance_valid(_solo_popup):
		_close_solo_class_popup()
	elif _confirm_overlay != null and _confirm_overlay.visible:
		_on_overwrite_cancelled()
	elif _settings_overlay != null and _settings_overlay.visible:
		_close_settings()
	elif _in_lobby:
		_on_leave_pressed()
	elif %ModePhase.visible:
		_on_mode_back_pressed()
	elif %MultiPhase.visible:
		_on_multi_back_pressed()
	elif %HostPhase.visible:
		_on_host_tabs_back()
	elif %JoinPhase.visible:
		_on_join_back_pressed()
	elif %SoloPhase.visible:
		_on_solo_back_pressed()
	elif %DailyPhase.visible:
		_on_daily_back_pressed()
	elif %StagingPhase.visible:
		_on_staging_back_pressed()
	else:
		return # Title: no back.
	get_viewport().set_input_as_handled()


## Issue #152: switching host tabs (mouse, pad, or a refresh forcing
## off a locked tab) re-chains the phase and re-seeds into the new
## page when focus didn't survive the switch.
func _on_host_tab_changed(_tab: int) -> void:
	if not %HostPhase.visible or _host_tab_container == null:
		return
	var page := _host_tab_container.get_current_tab_control()
	var in_page := FocusChain.collect(page) if page != null else []
	FocusChain.apply(%HostPhase, in_page[0] if not in_page.is_empty() else null)


## Continued-run reselect (lobby picker): whether the player has
## deliberately picked a class in this lobby showing, the off-class
## pick awaiting its warning decision, and the warning dialog.
var _lobby_class_touched := false
var _pending_reselect_class := ""
var _reselect_dialog: ConfirmationDialog = null


## Class selection row in the lobby (hidden if the save locks classes).
func _build_lobby_class_row() -> void:
	var existing := %LobbyPanel.get_node_or_null("LobbyClassRow")
	if existing != null:
		existing.queue_free()
	if NetworkManager.lobby_class_locked:
		return
	# Reselect: with a saved-class notice on record and no deliberate
	# pick yet, the saved class is the presented pick — the restore
	# choice the row's pressed state then follows.
	var my_notice := NetworkManager.my_saved_class_notice()
	if not my_notice.is_empty() and not _lobby_class_touched:
		NetworkManager.selected_class_id = str(my_notice.get("class_id", NetworkManager.selected_class_id))
	var row := HBoxContainer.new()
	row.name = "LobbyClassRow"
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	%LobbyPanel.add_child(row)
	%LobbyPanel.move_child(row, 2)
	var group := ButtonGroup.new()
	for cid in ["warrior", "rogue", "mage", "architect"]:
		if cid == "architect" and not SaveManager.is_architect_unlocked():
			continue
		var b := Button.new()
		b.text = cid.capitalize()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (NetworkManager.selected_class_id == cid)
		b.toggled.connect(_on_lobby_class.bind(cid))
		_style_one_button(b)
		row.add_child(b)


func _on_lobby_class(pressed: bool, cid: String) -> void:
	AudioManager.sfx("ui_click")
	if not pressed:
		return
	_lobby_class_touched = true
	# Reselect: an off-class pick behind a saved-class notice warns
	# BEFORE the pick commits — selected_class_id (what the dungeon
	# handshake will send) does not move until the player confirms.
	var notice := NetworkManager.my_saved_class_notice()
	if not notice.is_empty() and cid != str(notice.get("class_id", "")):
		_pending_reselect_class = cid
		_show_reselect_warning(notice, cid)
		return
	NetworkManager.selected_class_id = cid


## The reselect warning: leaving the saved character behind is a
## one-way door at the run's next save — say so before it commits.
func _show_reselect_warning(notice: Dictionary, cid: String) -> void:
	if _reselect_dialog == null:
		_reselect_dialog = ConfirmationDialog.new()
		_reselect_dialog.title = "Change Class?"
		_reselect_dialog.ok_button_text = "Confirm"
		_reselect_dialog.confirmed.connect(_on_reselect_confirmed)
		_reselect_dialog.canceled.connect(_on_reselect_canceled)
		add_child(_reselect_dialog)
	_reselect_dialog.dialog_text = "Leave your saved %s (Level %d) behind and start this run as a Level 1 %s? Your saved character is replaced when the run next saves." % [
		str(notice.get("class_id", "")).capitalize(),
		int(notice.get("level", 1)), cid.capitalize()]
	_reselect_dialog.popup_centered()


func _on_reselect_confirmed() -> void:
	if _pending_reselect_class != "":
		NetworkManager.selected_class_id = _pending_reselect_class
	_pending_reselect_class = ""


func _on_reselect_canceled() -> void:
	_pending_reselect_class = ""
	# Revert the pick to the saved class (the restore choice) and
	# re-present the row so the pressed button tells the truth.
	var notice := NetworkManager.my_saved_class_notice()
	if not notice.is_empty():
		NetworkManager.selected_class_id = str(notice.get("class_id", NetworkManager.selected_class_id))
	_build_lobby_class_row()


## A saved-class notice landed while the lobby is up: re-present
## the saved class as the restore pick — unless the player has
## already made a deliberate pick this showing.
func _on_saved_class_notice() -> void:
	if _in_lobby and not _lobby_class_touched:
		_build_lobby_class_row()


## Ready button for all players including the host; Start Dungeon (host only)
## is gated on everyone being ready.
func _build_lobby_ready_button() -> void:
	var existing := %LobbyPanel.get_node_or_null("ReadyButton")
	if existing != null:
		existing.queue_free()
	var b := Button.new()
	b.name = "ReadyButton"
	b.text = "Ready"
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(160, 48)
	b.toggled.connect(_on_lobby_ready_toggled)
	_style_one_button(b)
	%LobbyPanel.add_child(b)


func _on_lobby_ready_toggled(pressed: bool) -> void:
	AudioManager.sfx("ui_click")
	var my_id := _my_lobby_id()
	NetworkManager.lobby_ready[my_id] = pressed
	if NetworkManager.is_host:
		# Host relays their own ready state to everyone.
		NetworkManager.rpc("broadcast_ready_state", my_id, pressed)
	else:
		# Sync to host via RPC (host relays to everyone).
		NetworkManager.rpc_id(NetworkManager.server_peer_id, "sync_ready_state", my_id, pressed)
	_refresh_lobby_start()


## The local player's ID as it appears in NetworkManager.lobby_members:
## Steam64 on Steam, peer ID on LAN.
func _my_lobby_id() -> int:
	if SteamManager.initialized and NetworkManager.transport != NetworkManager.Transport.LAN:
		return SteamManager.steam_id
	return multiplayer.get_unique_id()


func _refresh_lobby_start() -> void:
	# Start Dungeon only works if all players (including host) are ready.
	var all_ready := true
	for sid in NetworkManager.lobby_members:
		if not bool(NetworkManager.lobby_ready.get(sid, false)):
			all_ready = false
			break
	%StartButton.disabled = not all_ready
	# Issue #152: Start's disabled state is part of the lobby chain —
	# re-chain so an enabled Start becomes reachable (and vice
	# versa). Primary stays Ready, matching _show_lobby's seed.
	if _in_lobby:
		var ready_btn := %LobbyPanel.get_node_or_null("ReadyButton") as Control
		FocusChain.apply(%LobbyPanel, ready_btn)


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
	# Issue #191 (section C): text entry summons through the seam.
	_lan_ip_field.focus_entered.connect(_request_text_entry.bind(_lan_ip_field))
	var name_label := Label.new()
	name_label.text = "Your name:"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form.add_child(name_label)
	_lan_name_field = LineEdit.new()
	_lan_name_field.placeholder_text = "Player"
	_lan_name_field.focus_entered.connect(_request_text_entry.bind(_lan_name_field))
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
	# Issue #152: the form/list swap changes the focusable set —
	# re-chain, seeding the mode's primary field/list.
	if %JoinPhase.visible:
		FocusChain.apply(%JoinPhase, _lan_ip_field if lan_mode else %LobbyList)


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
		_refresh_host_save_list()
		_refresh_host_tabs()
		return
	_host_tabs_built = true
	# Hide the legacy HostPhase children; the tabs take over.
	for child in %HostPhase.get_children():
		child.visible = false
	var tabs := TabContainer.new()
	tabs.name = "HostTabs"
	# Issue #137d: 360 (was 420) — the HostPhase stack must keep the
	# Host/Back row on screen at 720p with margin to spare.
	tabs.custom_minimum_size = Vector2(560, 360)
	%HostPhase.add_child(tabs)
	_host_tab_container = tabs
	# Issue #152: the tab bar takes a slot in the host focus chain;
	# _input switches pages on Left/Right while it owns focus.
	tabs.focus_mode = Control.FOCUS_ALL
	tabs.tab_changed.connect(_on_host_tab_changed)
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
	var conn_group := ButtonGroup.new()
	var steam_btn := Button.new()
	steam_btn.name = "SteamBtn"
	steam_btn.text = "Steam"
	steam_btn.toggle_mode = true
	steam_btn.button_group = conn_group
	steam_btn.button_pressed = not _lan_mode_host
	steam_btn.toggled.connect(_on_host_conn_toggled.bind(false, steam_btn))
	_style_one_button(steam_btn)
	conn_row.add_child(steam_btn)
	var lan_btn := Button.new()
	lan_btn.name = "LanBtn"
	lan_btn.text = "LAN"
	lan_btn.toggle_mode = true
	lan_btn.button_group = conn_group
	lan_btn.button_pressed = _lan_mode_host
	lan_btn.toggled.connect(_on_host_conn_toggled.bind(true, lan_btn))
	_style_one_button(lan_btn)
	conn_row.add_child(lan_btn)
	var save_label := Label.new()
	save_label.text = "Save File (optional — hosting from a save locks Difficulty & Loot)"
	save_label.add_theme_font_size_override("font_size", 18)
	t1.add_child(save_label)
	var save_scroll := ScrollContainer.new()
	# Issue #191 (section B): follow focus below the fold.
	save_scroll.follow_focus = true
	save_scroll.custom_minimum_size = Vector2(540, 130)
	# Issue #145: the scrollbar is ALWAYS present and dressed in
	# the menu's own palette (the framed panels' dark inset +
	# accent gold), so "more saves below the fold" reads at a
	# glance — Jesse missed a save in this list because the bar
	# gave no cue. Affordance only: the scroll behavior itself
	# (his approved exception on this surface) does not change;
	# a full-length thumb honestly says the list fits.
	save_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	var vbar := save_scroll.get_v_scroll_bar()
	vbar.custom_minimum_size.x = 14
	var gold := Color(0.85, 0.70, 0.30)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.07, 0.10, 0.98)
	track.border_color = Color(gold, 0.55)
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	vbar.add_theme_stylebox_override("scroll", track)
	var grab := StyleBoxFlat.new()
	grab.bg_color = gold
	grab.set_corner_radius_all(3)
	vbar.add_theme_stylebox_override("grabber", grab)
	var grab_hi := StyleBoxFlat.new()
	grab_hi.bg_color = gold.lightened(0.25)
	grab_hi.set_corner_radius_all(3)
	vbar.add_theme_stylebox_override("grabber_highlight", grab_hi)
	var grab_press := StyleBoxFlat.new()
	grab_press.bg_color = gold.lightened(0.45)
	grab_press.set_corner_radius_all(3)
	vbar.add_theme_stylebox_override("grabber_pressed", grab_press)
	t1.add_child(save_scroll)
	_host_save_list = VBoxContainer.new()
	_host_save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_scroll.add_child(_host_save_list)
	_refresh_host_save_list()
	# --- Tab 2: Difficulty & Loot ---
	var t2_scroll := ScrollContainer.new()
	# Issue #191 (section B): follow focus below the fold.
	t2_scroll.follow_focus = true
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
	var diff_group := ButtonGroup.new()
	for spec in [["Easy", "easy"], ["Normal", "normal"], ["Hard", "hard"], ["Advanced", "advanced"]]:
		var b := Button.new()
		b.text = spec[0]
		b.toggle_mode = true
		b.button_group = diff_group
		b.button_pressed = (NetworkManager.host_difficulty_preset == spec[1])
		b.toggled.connect(_on_host_diff_preset.bind(spec[1]))
		b.name = "Diff_" + spec[1]
		_style_one_button(b)
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
	var loot_group := ButtonGroup.new()
	for spec in [["0.5x", 0.5], ["1.0x", 1.0], ["2.0x", 2.0], ["Custom", -1.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.toggle_mode = true
		b.button_group = loot_group
		b.button_pressed = (absf(NetworkManager.host_loot_mult - float(spec[1])) < 0.01) or \
			(float(spec[1]) < 0.0 and NetworkManager.host_loot_mult not in [0.5, 1.0, 2.0])
		b.toggled.connect(_on_host_loot_preset.bind(float(spec[1])))
		b.name = "Loot_" + str(spec[1])
		_style_one_button(b)
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
	var rar_group := ButtonGroup.new()
	var rar_def := Button.new()
	rar_def.text = "Default"
	rar_def.toggle_mode = true
	rar_def.button_group = rar_group
	rar_def.button_pressed = NetworkManager.custom_rarity.is_empty()
	rar_def.toggled.connect(_on_host_rarity_default.bind(true))
	rar_def.name = "RarDefault"
	_style_one_button(rar_def)
	rar_row.add_child(rar_def)
	var rar_cus := Button.new()
	rar_cus.text = "Custom"
	rar_cus.toggle_mode = true
	rar_cus.button_group = rar_group
	rar_cus.button_pressed = not NetworkManager.custom_rarity.is_empty()
	rar_cus.toggled.connect(_on_host_rarity_default.bind(false))
	rar_cus.name = "RarCustom"
	_style_one_button(rar_cus)
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
	_host_pw_toggle = pw_toggle
	_host_pw_field = LineEdit.new()
	_host_pw_field.placeholder_text = "Password"
	_host_pw_field.text = NetworkManager.lobby_password
	_host_pw_field.editable = pw_toggle.button_pressed
	_host_pw_field.text_changed.connect(_on_host_pw_changed)
	# Issue #191 (section C): text entry summons through the seam.
	_host_pw_field.focus_entered.connect(_request_text_entry.bind(_host_pw_field))
	pw_row.add_child(_host_pw_field)
	var vis_label := Label.new()
	vis_label.text = "Lobby Visibility (Steam only)"
	vis_label.add_theme_font_size_override("font_size", 18)
	t3.add_child(vis_label)
	var vis_row := HBoxContainer.new()
	vis_row.add_theme_constant_override("separation", 8)
	t3.add_child(vis_row)
	var vis_group := ButtonGroup.new()
	for spec in [["Public", "public"], ["Friends Only", "friends"], ["Private", "private"]]:
		var b := Button.new()
		b.text = spec[0]
		b.toggle_mode = true
		b.button_group = vis_group
		b.button_pressed = (NetworkManager.lobby_visibility == spec[1])
		b.toggled.connect(_on_host_visibility.bind(spec[1]))
		b.name = "Vis_" + spec[1]
		_style_one_button(b)
		vis_row.add_child(b)
		_host_vis_buttons[spec[1]] = b
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
	_host_cap_slider = cap_slider
	var cap_val := Label.new()
	cap_val.name = "CapVal"
	cap_val.text = str(NetworkManager.lobby_player_cap)
	cap_row.add_child(cap_val)
	_host_cap_val = cap_val
	var warn := Label.new()
	warn.text = "Warning: players joining a pre-existing save file will start at level 1."
	warn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Issue #137d: an autowrap label with no minimum width reports a
	# minimum size of (1, 1583) — the whole text stacked at 1px wide —
	# which inflates the Lobby tab's minimum height to ~1830 and can
	# push the Host/Back row off a 720p screen. A realistic minimum
	# width keeps its wrapped minimum height honest (~2 lines).
	warn.custom_minimum_size = Vector2(500, 0)
	t3.add_child(warn)
	var open_row := HBoxContainer.new()
	open_row.add_theme_constant_override("separation", 12)
	t3.add_child(open_row)
	var open_toggle := CheckButton.new()
	open_toggle.text = "Open roster: allow new players to join this save at level 1"
	open_toggle.button_pressed = NetworkManager.lobby_open_roster
	open_toggle.toggled.connect(_on_host_open_roster_toggled)
	open_row.add_child(open_toggle)
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
	_refresh_host_lobby_controls()


## Issue #132: the lobby settings a continued run will actually host
## with, derived from its save dict using the exact defaults the M-5
## continue path applies (network_manager.gd continue_multiplayer):
## visibility falls back to friends-only for legacy saves that predate
## the field (unknown values fall back the same way, never to public),
## cap is the save's max_players (default MAX_PLAYERS = 12) clamped to
## the cap slider's 4-12 range, and no password is ever stored in a
## save — a continued lobby is passwordless.
static func lobby_settings_for_run(run: Dictionary) -> Dictionary:
	var lobby_raw = run.get("lobby", {})
	var lobby: Dictionary = lobby_raw if lobby_raw is Dictionary else {}
	var vis := str(lobby.get("visibility", "friends"))
	if vis not in ["public", "friends", "private"]:
		vis = "friends"
	var cap := clampi(int(lobby.get("max_players", 12)), 4, 12)
	return {"visibility": vis, "cap": cap, "password": str(lobby.get("password", ""))}


## Issue #132: re-derive the Lobby tab controls from the current
## selection so the tab shows what Host will actually create. With a
## save selected that is the save's stored settings (continue_run reads
## the save, never these controls); on Fresh Run it is the menu's own
## NetworkManager values, exactly as before. Controls are set without
## emitting signals, so the derivation never writes the NetworkManager
## values — hosting semantics are unchanged in both modes.
func _refresh_host_lobby_controls() -> void:
	if _host_tab_container == null:
		return
	var vis := NetworkManager.lobby_visibility
	var cap := NetworkManager.lobby_player_cap
	var pw := NetworkManager.lobby_password
	if NetworkManager.host_save_slot >= 0:
		var run := SaveManager.load_run(SaveManager.MODE_MP, NetworkManager.host_save_slot)
		if not run.is_empty():
			var s := lobby_settings_for_run(run)
			vis = str(s["visibility"])
			cap = int(s["cap"])
			pw = str(s["password"])
	for key in _host_vis_buttons:
		(_host_vis_buttons[key] as Button).set_pressed_no_signal(key == vis)
	if _host_cap_slider != null:
		_host_cap_slider.set_value_no_signal(float(cap))
	if _host_cap_val != null:
		_host_cap_val.text = str(cap)
	if _host_pw_toggle != null:
		_host_pw_toggle.set_pressed_no_signal(not pw.is_empty())
	if _host_pw_field != null:
		_host_pw_field.text = pw
		_host_pw_field.editable = not pw.is_empty()


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
	_style_one_button(fresh)
	_host_save_list.add_child(fresh)
	for slot in SaveManager.list_slots(SaveManager.MODE_MP):
		var run: Dictionary = SaveManager.load_run(SaveManager.MODE_MP, slot)
		var summary := SaveManager.run_summary(run)
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", 8)
		var b := Button.new()
		b.text = "Slot %d: %s" % [slot + 1, summary]
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = (NetworkManager.host_save_slot == slot)
		b.toggled.connect(_on_host_save_selected.bind(slot))
		_style_one_button(b)
		hrow.add_child(b)
		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.tooltip_text = "Delete this saved run (asks first)"
		del_btn.custom_minimum_size = Vector2(36, 0)
		del_btn.pressed.connect(_show_delete_confirm.bind(SaveManager.MODE_MP, slot))
		_style_one_button(del_btn)
		hrow.add_child(del_btn)
		_host_save_list.add_child(hrow)
	# Issue #152: the save list is dynamic — re-chain the host phase
	# on every rebuild (a freed focused row re-seeds per apply()).
	if %HostPhase.visible:
		FocusChain.apply(%HostPhase, null)


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


func _on_host_open_roster_toggled(pressed: bool) -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.lobby_open_roster = pressed


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
	# Continued-run reselect: hosting from a save no longer locks the
	# lobby class row — picks are real now, governed by the saved-
	# class notice + warning (Jesse's ruling: guests may reselect).
	NetworkManager.lobby_class_locked = false
	NetworkManager.lobby_ready.clear()
	if _lan_mode_host:
		var lan_slot := NetworkManager.host_save_slot
		if lan_slot >= 0:
			# Jesse 2026-10-11: LAN host from save — load the save data directly.
			# (Steam's continue_run needs a lobby; LAN goes straight in.)
			var run := SaveManager.load_run(SaveManager.MODE_MP, lan_slot)
			if not run.is_empty() and SaveManager.is_legacy_mp_save(run):
				# Issue #111 minor 2: a pre-roster save would restore
				# nobody — say so instead of starting everyone fresh.
				_on_connection_failed(SaveManager.LEGACY_MP_SAVE_MESSAGE)
				return
			if not run.is_empty():
				NetworkManager.active_run_mode = SaveManager.MODE_MP
				NetworkManager.active_run_slot = lan_slot
				NetworkManager.is_host = true
				# Find the host's roster entry for their saved state.
				var host_state := {}
				var host_class := "warrior"
				for entry in run.get("roster", []):
					if bool(entry.get("is_host", false)):
						host_state = entry.get("player_state", {})
						host_class = str(entry.get("class_id", "warrior"))
						break
				NetworkManager.selected_class_id = host_class
				Dungeon.saved_player_state = host_state
				Dungeon.next_theme_id = str(run.get("theme_id", "village"))
				Dungeon.next_seed = int(run.get("seed", randi()))
				Dungeon.next_level_number = int(run.get("level_number", 1))
				Dungeon.next_wave = int(run.get("wave", 0))
				Dungeon.continued_roster = run.get("roster", [])
				NetworkManager.host_lan()
				# Issue #140: the session store the dungeon captures from
				# (set after host_lan, whose fresh-session clear precedes it).
				NetworkManager.continued_session_roster = run.get("roster", []).duplicate()
				if bool(run.get("at_station", false)):
					Station.next_level_number = int(run.get("level_number", 1))
					get_tree().change_scene_to_file("res://scenes/station/train_interior.tscn")
				else:
					get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")
				return
		NetworkManager.host_lan()
		_show_lobby("LAN Lobby", true)
	else:
		var slot := NetworkManager.host_save_slot
		if slot >= 0:
			# Hosting from a save: route through continue_run so _continued_run
			# is set and start_continued_run() can rpc("load_dungeon") later.
			NetworkManager.continue_run(SaveManager.MODE_MP, slot)
		else:
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
	var list := _solo_slots_list if _solo_slots_list != null else %SoloSlotsList
	for child in list.get_children():
		child.queue_free()
	for slot in SaveManager.list_slots(SaveManager.MODE_SOLO):
		list.add_child(_build_slot_card(SaveManager.MODE_SOLO, slot))
	# Always offer one "New Run" slot at the end.
	list.add_child(_build_slot_card(SaveManager.MODE_SOLO, SaveManager.next_free_slot(SaveManager.MODE_SOLO)))
	_refresh_legacy_rows(%SoloLegacyList, SaveManager.MODE_SOLO)
	_style_buttons()
	# Issue #152: the slot cards are dynamic — re-chain on refresh.
	if %SoloPhase.visible:
		FocusChain.apply(%SoloPhase, _solo_primary())


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
		var del_btn := Button.new()
		del_btn.text = "Delete"
		del_btn.tooltip_text = "Delete this saved run (asks first)"
		del_btn.pressed.connect(_show_delete_confirm.bind(mode, slot))
		row.add_child(del_btn)
	else:
		meta.text = "Empty slot"
		meta.modulate = Color(0.55, 0.55, 0.60)
		var new_btn := Button.new()
		new_btn.text = "New Run"
		new_btn.pressed.connect(_on_slot_new_pressed.bind(mode, slot))
		row.add_child(new_btn)
	return margin


## First empty slot for the mode (dynamic — always available).
func _first_empty_slot(mode: String) -> int:
	return SaveManager.next_free_slot(mode)


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
	_capture_overlay_return()
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
	cancel.pressed.connect(_close_solo_class_popup)
	vb.add_child(cancel)
	add_child(overlay)
	_solo_popup = overlay
	_style_buttons()
	# Issue #152: chain the popup; primary is the first class button.
	FocusChain.apply(overlay, null)


func _close_solo_class_popup() -> void:
	if _solo_popup != null and is_instance_valid(_solo_popup):
		_solo_popup.queue_free()
	_solo_popup = null
	# Issue #191 (section A): focus returns to the opener on
	# the Solo phase.
	_restore_overlay_return()


func _on_solo_class_chosen(cid: String, slot: int, overlay: Control) -> void:
	AudioManager.sfx("ui_click")
	NetworkManager.selected_class_id = cid
	overlay.queue_free()
	_solo_popup = null
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
	_confirm_cancel = no
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
	# Issue #144 Phase 1 (Q2): look sensitivity + stick deadzone sliders.
	# Stored as fractions via the shared handler (slider % / 100):
	# sensitivity 10-200% (default 100 = 1.0x), deadzone 0-50% (default 20).
	for spec in [["Look sensitivity", "look_sens", 10, 200, 5, 1.0], ["Stick deadzone", "look_deadzone", 0, 50, 1, 0.2]]:
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 12)
		lrow.alignment = BoxContainer.ALIGNMENT_CENTER
		var llab := Label.new()
		llab.text = spec[0]
		llab.custom_minimum_size = Vector2(120, 0)
		lrow.add_child(llab)
		var lslider := HSlider.new()
		lslider.custom_minimum_size = Vector2(220, 0)
		lslider.min_value = spec[2]
		lslider.max_value = spec[3]
		lslider.step = spec[4]
		lslider.value = float(SaveManager.get_profile_setting("settings", spec[1], spec[5])) * 100.0
		lslider.value_changed.connect(_on_settings_vol_changed.bind(spec[1]))
		lrow.add_child(lslider)
		var lval := Label.new()
		lval.name = "Val_%s" % spec[1]
		lval.text = "%d" % int(lslider.value)
		lval.custom_minimum_size = Vector2(40, 0)
		lrow.add_child(lval)
		vb.add_child(lrow)
	for spec in [["CRT filter", "crt_enabled", true], ["Screen shake", "shake_enabled", true], ["Fullscreen", "fullscreen", false], ["Invert look Y", "look_invert_y", false]]:
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
	close.pressed.connect(_close_settings)
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
		"look_sens":
			SaveManager.set_profile_setting("settings", "look_sens", v)
		"look_deadzone":
			SaveManager.set_profile_setting("settings", "look_deadzone", v)
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
	_capture_overlay_return()
	_settings_overlay.visible = true
	# Issue #152: chain the panel (sliders/toggles ride native focus
	# behavior — ui_left/right adjust, ui_accept flips).
	FocusChain.apply(_settings_overlay, null)


func _close_settings() -> void:
	_settings_overlay.visible = false
	# Issue #191 (section A): hand focus back to the opener —
	# Jesse's expectation: the Settings button is re-selected.
	_restore_overlay_return()


func _show_overwrite_confirm(mode: String, slot: int) -> void:
	_capture_overlay_return()
	_confirm_mode = mode
	_confirm_slot = slot
	var run := SaveManager.load_run(mode, slot)
	_confirm_msg.text = "Slot %d already holds a saved run:\n%s\n\nStart a new run and overwrite it?" % [
		slot + 1, SaveManager.run_summary(run)]
	_confirm_overlay.visible = true
	# Issue #152: chain the modal; primary is Cancel (non-destructive).
	FocusChain.apply(_confirm_overlay, _confirm_cancel)


## Delete confirm: reuses the overwrite modal with a delete action.
var _delete_mode := ""
var _delete_slot := -1


func _show_delete_confirm(mode: String, slot: int) -> void:
	AudioManager.sfx("ui_click")
	_capture_overlay_return()
	_delete_mode = mode
	_delete_slot = slot
	_confirm_mode = "delete"
	var run := SaveManager.load_run(mode, slot)
	_confirm_msg.text = "Delete this saved run?\nSlot %d: %s\n\nThis cannot be undone." % [
		slot + 1, SaveManager.run_summary(run)]
	_confirm_overlay.visible = true
	# Issue #152: chain the modal; primary is Cancel (non-destructive).
	FocusChain.apply(_confirm_overlay, _confirm_cancel)


func _on_overwrite_confirmed() -> void:
	AudioManager.sfx("ui_click")
	_confirm_overlay.visible = false
	if _confirm_mode == "delete":
		SaveManager.clear_run(_delete_mode, _delete_slot)
		# If we deleted the host's selected save, deselect it.
		if _delete_mode == SaveManager.MODE_MP and NetworkManager.host_save_slot == _delete_slot:
			NetworkManager.host_save_slot = -1
		_delete_mode = ""
		_delete_slot = -1
		_confirm_mode = ""
		_refresh_solo_ui()
		_refresh_host_save_list()
		_refresh_host_tabs()
		# Issue #191 (section A): the delete exit stays on this
		# surface — focus returns to the opener.
		_restore_overlay_return()
		return
	if _confirm_mode == SaveManager.MODE_MP:
		_host_slot = _confirm_slot
		_build_host_tabs()
		_show_phase("HostPhase")
	else:
		_show_solo_class_popup(_confirm_slot)


func _on_overwrite_cancelled() -> void:
	AudioManager.sfx("ui_click")
	_confirm_overlay.visible = false
	# Issue #191 (section A): focus returns to the opener.
	_restore_overlay_return()


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
	# Continued run: use the save path; fresh run: normal start.
	if not NetworkManager._continued_run.is_empty():
		NetworkManager.start_continued_run()
	else:
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
	# Jesse 2026-10-11: continued runs now use the lobby UI, not the old staging phase.
	# Issue #137a: on a continue, the lobby class row must tell the
	# truth — select the class the save's roster records for the host
	# (flagged entry, else the saver's own entry, else the first),
	# not the "warrior" default.
	# Issue #140 rider: the roster lives under the run's "roster" key
	# (the save format's only roster key) — the original #137a code read
	# a "players" key real saves never carry, so the derivation silently
	# never fired outside the suite's fabricated dict.
	var roster: Array = NetworkManager._continued_run.get("roster", [])
	var host_entry: Dictionary = {}
	for entry in roster:
		if entry is Dictionary and bool(entry.get("is_host", false)):
			host_entry = entry
			break
	if host_entry.is_empty() and SteamManager.initialized:
		for entry in roster:
			if entry is Dictionary and int(entry.get("steam_id", 0)) == SteamManager.steam_id:
				host_entry = entry
				break
	if host_entry.is_empty() and not roster.is_empty() and roster[0] is Dictionary:
		host_entry = roster[0]
	if not host_entry.is_empty():
		NetworkManager.selected_class_id = str(host_entry.get("class_id", NetworkManager.selected_class_id))
	var run_title := "Continue Run"
	if not NetworkManager._continued_run.is_empty():
		var lobby: Dictionary = NetworkManager._continued_run.get("lobby", {})
		var lname := str(lobby.get("lobby_name", "Dungeon"))
		run_title = "Continue: %s" % lname
	_show_lobby(run_title, true)
	# Issue #137c: no invite overlay here — hosting a save must not
	# spring Steam's invite UI unprompted. The manual Invite buttons
	# (roster rows / Invite All) still open it on demand.


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
	# Issue #152: dynamic roster rows — re-chain while staging shows.
	if %StagingPhase.visible:
		FocusChain.apply(%StagingPhase, null)


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
	# Issue #137e: plain English (the localization revert left a tr_n()
	# call whose raw key has no % placeholder — the format failed on
	# every refresh with "not all arguments converted").
	%JoinStatusLabel.text = "Found %d %s" % [lobbies.size(), "lobby" if lobbies.size() == 1 else "lobbies"]
	for lobby in lobbies:
		%LobbyList.add_item("%s (%d/%d)" % [lobby["name"], lobby["players"], lobby["max_players"]])


func _on_connection_failed(reason: String) -> void:
	%JoinStatusLabel.text = reason
	_show_phase("JoinPhase")


## Issue #133: a guest waiting in the lobby when the host's session
## ends (the in-world case is the HUD's notice). Run the same
## leave_lobby() teardown the lobby Leave button uses and say so.
## Hosts and solo menus never satisfy the guard — session_lost only
## fires for an established client session in the first place.
func _on_session_lost() -> void:
	if NetworkManager.is_host or NetworkManager.peer == null:
		return
	NetworkManager.leave_lobby()
	%JoinStatusLabel.text = "The host ended the session."
	_show_phase("JoinPhase")


## Issue #138 Phase 2: the host's baked level doesn't match this
## build's shipped scene — the load was refused before any scene
## change. A client leaves the incompatible lobby; the message
## explains the rest (the in-world case is the HUD's dialog).
func _on_baked_version_mismatch(message: String) -> void:
	if not NetworkManager.is_host and NetworkManager.peer != null:
		NetworkManager.leave_lobby()
	%JoinStatusLabel.text = message
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
