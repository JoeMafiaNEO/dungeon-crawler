extends CanvasLayer
## Player HUD: health, XP, level, equipment, crosshair, toasts, pause menu.

## Preloaded (not class_name) so the bounty UI keeps working even when the
## global class cache is stale on a fresh clone (issue #7 red-fix lesson).
const BountySys := preload("res://scripts/systems/bounty.gd")
const BountyUI := preload("res://scripts/ui/bounty_ui.gd")
const DeepTreeCanvas := preload(
	"res://scripts/ui/deep_tree_canvas.gd")

## Issue #215: the Deep Tree canvas surface (null until
## first opened) + whether it was opened from the pause
## menu (closing returns there) or directly from
## gameplay (closing resumes).
var _tree_surface: Control = null
var _tree_from_pause := false

var is_paused := false

## Inventory (character panel) open. The inventory is an alternative
## pause screen (Jesse 2026-10-13): while it is up the mouse is free
## and the local player takes no damage — Player.take_damage reads
## this on the player's authority peer, whose HUD is this one.
var inventory_open := false
## Issue #133: the session-lost notice dialog (null until shown).
var _session_lost_dialog: ConfirmationDialog = null
## Issue #152: the quit-confirm dialog while it is up (pad B presses
## its Cancel through _pad_back; null otherwise).
var _quit_dialog: ConfirmationDialog = null

## The local player. Untyped (Variant) so UI harnesses can drive the bounty
## panel/tracker with a lightweight test double (a Dictionary with
## bounty_progress) without needing the full Player script, which does not
## compile in -s test mode (SteamManager autoload).
var _player
var _toast_tween: Tween


func setup(p: Player) -> void:
	_player = p
	p.hud = self
	p.health_changed.connect(_on_health_changed)
	p.xp_changed.connect(_on_xp_changed)
	p.leveled_up.connect(_on_leveled_up)
	# Issue #95 Phase 2: legend follows rogue charge / Holy Light states live.
	if not p.click_state_changed.is_connected(_on_click_state_changed):
		p.click_state_changed.connect(_on_click_state_changed)
	_on_health_changed(p.hp, p.max_hp)
	_on_xp_changed(p.xp, p.xp_next, p.level)
	%LevelLabel.text = "Lv %d %s" % [p.level, p.class_data.display_name]
	refresh_loadout(p)
	refresh_abilities(p)
	# Volume sliders reflect saved settings.
	%MasterSlider.value = AudioManager.master_vol
	%MusicSlider.value = AudioManager.music_vol
	%SFXSlider.value = AudioManager.sfx_vol
	%MasterSlider.value_changed.connect(func(v: float): AudioManager.set_master_vol(v))
	%MusicSlider.value_changed.connect(func(v: float): AudioManager.set_music_vol(v))
	%SFXSlider.value_changed.connect(func(v: float): AudioManager.set_sfx_vol(v))


func _on_health_changed(hp: float, max_hp: float) -> void:
	%HPBar.max_value = max_hp
	%HPBar.value = hp
	%HPLabel.text = "%d / %d" % [int(hp), int(max_hp)]
	_hp_frac = hp / maxf(1.0, max_hp)


var _hp_frac := 1.0
var _vignette_t := 0.0

## Pause menu tabs: 0=Stats, 1=Specialization, 2=Collection,
## 3=Keybinds, 4=Voice (Keybinds + Voice added 2026-10-28 on
## Jesse's order — the Keybinds tab shows every binding, the
## Voice tab carries the voice-chat settings in-game).
var _pause_tab := 0
var _pause_tab_btns: Array[Button] = []
## Voice tab controls (built with the pause tabs; they wire the
## same VoiceManager settings as the main-menu Settings panel).
var _pause_voice_transmit_tog: CheckButton
var _pause_voice_mode_opt: OptionButton
var _pause_voice_thresh_slider: HSlider
var _pause_voice_thresh_val: Label
var _pause_voice_mute_tog: CheckButton
var _pause_voice_vol_slider: HSlider
var _pause_voice_vol_val: Label
var _pause_voice_status_label: Label
## Node names (under PauseVBox) belonging to each tab.
var _pause_tab_members: Array = []
## Action buttons moved outside the scroll area (stored refs avoid % lookup issues).
var _class_btn: Button
var _save_quit_btn: Button


## Issue #152 (2A-2): prompt labels that carry PromptText tokens,
## tracked as [label, template] pairs so a live input-source switch
## re-renders them in place. Entries are pruned when their label is
## freed (popups rebuild their labels on every open).
var _tracked_prompts: Array = []
var _legend_player: Object = null
var _pickup_name := ""
var _pickup_shown := false
var _pause_hint_label: Label = null

const PAUSE_HINT_TEMPLATE := "{move} move · {attack} attack · {dash} dash · {cycle_ability} ability · {ping} ping · {start_wave} start wave"

## Keybinds tab rows: every non-ui InputMap action, in play order,
## with its display name. The BINDINGS are never stored here — they
## are read live from InputMap.action_get_events() when the rows
## are generated (keybind_rows), so the tab always shows the keys
## the game actually ships. The ui_* menu actions are summarized
## by the trailing "Menu Navigation" row instead of listed singly.
const KEYBIND_ACTIONS := [
	["move_forward", "Move Forward"],
	["move_back", "Move Back"],
	["move_left", "Move Left"],
	["move_right", "Move Right"],
	["jump", "Jump"],
	["dash", "Dash"],
	["attack", "Attack"],
	["alt_attack", "Alt Attack"],
	["interact", "Interact"],
	["ability", "Use Ability"],
	["cycle_ability", "Cycle Ability"],
	["ability_1", "Ability 1"],
	["ability_2", "Ability 2"],
	["ability_3", "Ability 3"],
	["ability_4", "Ability 4"],
	["ability_5", "Ability 5"],
	["ability_6", "Ability 6"],
	["ability_7", "Ability 7"],
	["signature_ability", "Signature Ability"],
	["start_wave", "Start Wave"],
	["potion", "Drink Potion"],
	["inventory", "Inventory"],
	["deep_tree_open", "Deep Tree"],
	["ping", "Ping"],
	["toggle_rod", "Fishing Rod"],
	["build_menu", "Build Menu"],
	["look_left", "Look Left"],
	["look_right", "Look Right"],
	["look_up", "Look Up"],
	["look_down", "Look Down"],
	["voice_ptt", "Voice Push-to-Talk"],
	["voice_mute", "Voice Mute Mic"],
	["pause", "Pause"],
]
const CLOSE_HINT_TEMPLATE := "{close_keys} — close"
const DEST_HINT_TEMPLATE := "{choose} a destination to vote. Unanimous vote departs the train.  ({close_keys_tight} closes)"


func _track_prompt_label(l: Label, template: String) -> void:
	_tracked_prompts.append([l, template])


# --- Issue #190 (section 4): composite prompt segments ---
## The designated ART surfaces (the interact/pickup prompt
## line, the legend caption slots) render a template as
## SEGMENTS: text runs as Labels, Steam glyph art as
## TextureRects, inside an HBox. Textures cache per path; a
## path that fails to load falls back to the segment's text
## (under the Steam tier, Steam's origin string), and from
## there the native label — fail-closed in cascade. With no
## art in play the composite is all-text segments and reads
## exactly as the standing prompt did.
var _prompt_line: HBoxContainer = null
var _prompt_template := ""
var _prompt_visible := false
var _glyph_cache: Dictionary = {}


func _glyph_texture(path: String) -> Texture2D:
	if _glyph_cache.has(path):
		return _glyph_cache[path]
	var tex: Texture2D = null
	var img := Image.new()
	if img.load(path) == OK and img.get_width() > 0:
		tex = ImageTexture.create_from_image(img)
	_glyph_cache[path] = tex
	return tex


func _fill_segment_line(host: HBoxContainer, segments: Array, font_size: int, font_color: Color = Color.WHITE) -> void:
	for c in host.get_children():
		host.remove_child(c)
		c.free()
	for seg in segments:
		var d: Dictionary = seg
		var art: Texture2D = null
		if str(d.get("kind", "")) == "action" and str(d.get("glyph_path", "")) != "":
			art = _glyph_texture(str(d["glyph_path"]))
		if art != null:
			var tr := TextureRect.new()
			tr.texture = art
			tr.custom_minimum_size = Vector2(font_size + 4, font_size + 4)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			host.add_child(tr)
		elif str(d.get("text", "")) != "":
			var l := Label.new()
			l.text = str(d["text"])
			l.add_theme_font_size_override("font_size", font_size)
			l.add_theme_color_override("font_color", font_color)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			host.add_child(l)


func _render_prompt_line() -> void:
	if _prompt_line == null:
		return
	_prompt_line.visible = _prompt_visible
	if _prompt_visible:
		_fill_segment_line(_prompt_line, PromptText.resolve_segments(_prompt_template), 22)


func _on_input_source_changed(_source: int = 0) -> void:
	var live: Array = []
	for entry in _tracked_prompts:
		if is_instance_valid(entry[0]):
			(entry[0] as Label).text = PromptText.resolve(str(entry[1]))
			live.append(entry)
	_tracked_prompts = live
	_render_prompt_line()
	# Issue #190 (amendment): the ability bar's conditional
	# caps + flanks re-render with the source/binding change.
	if _ability_player != null and is_instance_valid(_ability_player):
		refresh_abilities(_ability_player)
	else:
		_render_ability_flanks()
	if _pause_hint_label != null and is_instance_valid(_pause_hint_label):
		_pause_hint_label.text = PromptText.resolve(PAUSE_HINT_TEMPLATE)
	if _legend_player != null and is_instance_valid(_legend_player):
		refresh_mouse_legend(_legend_player)


func _ready() -> void:
	add_to_group("hud")
	# Issue #152 (2A-2): live prompt re-render on input-source flips.
	InputSource.changed.connect(_on_input_source_changed)
	# Issue #190 (section 5): the SAME re-render routine serves
	# the adapter's bindings_changed (activation, controller
	# swap, overlay rebind via the fingerprint poll).
	SteamInputAdapter.bindings_changed.connect(_on_input_source_changed)
	# Issue #190 (section 4): the composite prompt line lives
	# where %PickupPrompt stood (same anchors/offsets); the
	# plain label is superseded and stays hidden.
	_prompt_line = HBoxContainer.new()
	_prompt_line.name = "PromptLine"
	_prompt_line.anchor_left = 0.5
	_prompt_line.anchor_top = 1.0
	_prompt_line.anchor_right = 0.5
	_prompt_line.anchor_bottom = 1.0
	_prompt_line.offset_left = -200.0
	_prompt_line.offset_top = -165.0
	_prompt_line.offset_right = 200.0
	_prompt_line.offset_bottom = -130.0
	_prompt_line.alignment = HBoxContainer.ALIGNMENT_CENTER
	_prompt_line.add_theme_constant_override("separation", 3)
	_prompt_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_line.visible = false
	add_child(_prompt_line)
	%PickupPrompt.visible = false
	# Issue #190 (amendment): the cycle_ability flank hosts,
	# flanking %AbilityBar (its band is -220..220, -76..-16).
	for side in [-1, 1]:
		var flank := HBoxContainer.new()
		flank.name = "AbilityFlankL" if side < 0 else "AbilityFlankR"
		flank.anchor_left = 0.5
		flank.anchor_top = 1.0
		flank.anchor_right = 0.5
		flank.anchor_bottom = 1.0
		flank.offset_left = -258.0 if side < 0 else 224.0
		flank.offset_top = -66.0
		flank.offset_right = -224.0 if side < 0 else 258.0
		flank.offset_bottom = -26.0
		flank.alignment = HBoxContainer.ALIGNMENT_CENTER
		flank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flank.visible = false
		add_child(flank)
		if side < 0:
			_ability_flank_left = flank
		else:
			_ability_flank_right = flank
	# Issue #133: a guest whose host vanished gets the session-lost
	# notice (NetworkManager detects; the HUD presents).
	NetworkManager.session_lost.connect(_on_session_lost)
	NetworkManager.baked_version_mismatch.connect(_on_baked_version_mismatch)
	_build_character_panel()
	_build_pause_tabs()
	_build_bounty_tracker()
	_build_potion_slot()
	_build_charge_meter()
	_build_ascension_indicator()
	_apply_healthbar_art()


## Jesse 2026-10-11: SNES health bar frame overlay on the player HP bar.
## Jesse 2026-10-11: code-generated HUD health bar border (replaced PNG frame).
func _apply_healthbar_art() -> void:
	var hp_bar := %HPBar as ProgressBar
	if hp_bar == null:
		return
	# Dark code-drawn border behind the bar.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.07, 0.95)
	bg.border_color = Color(0.75, 0.68, 0.45)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(3)
	bg.content_margin_left = 2.0
	bg.content_margin_right = 2.0
	bg.content_margin_top = 2.0
	bg.content_margin_bottom = 2.0
	hp_bar.add_theme_stylebox_override("background", bg)
	# Red fill texture.
	var fill_tex := load("res://assets/sprites/ui/healthbar_fill.png") as Texture2D
	if fill_tex != null:
		var fill_style := StyleBoxTexture.new()
		fill_style.texture = fill_tex
		hp_bar.add_theme_stylebox_override("fill", fill_style)


## Issue #69 Phase 1: Thrown dagger charge meter. Small bar near the
## crosshair (HUD-only), visible while RMB is held.
var _charge_bar: ProgressBar = null

func _build_charge_meter() -> void:
	_charge_bar = ProgressBar.new()
	_charge_bar.name = "ChargeMeter"
	_charge_bar.set_anchors_preset(Control.PRESET_CENTER)
	_charge_bar.offset_left = -40.0
	_charge_bar.offset_top = 24.0
	_charge_bar.offset_right = 40.0
	_charge_bar.offset_bottom = 32.0
	_charge_bar.min_value = 0.0
	_charge_bar.max_value = 1.0
	_charge_bar.value = 0.0
	_charge_bar.show_percentage = false
	_charge_bar.visible = false
	add_child(_charge_bar)


## Issue #11 Phase 1: Ascension indicator (wings icon + count next to XP bar).
## Placeholder gold chevron until Art Director lands the SNES wings sprite.
var _asc_label: Label = null

func _build_ascension_indicator() -> void:
	_asc_label = Label.new()
	_asc_label.name = "AscensionIndicator"
	# Position: top-left, near the XP bar area.
	_asc_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_asc_label.offset_left = 12.0
	_asc_label.offset_top = 52.0
	_asc_label.add_theme_font_size_override("font_size", 14)
	_asc_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_asc_label.visible = false
	add_child(_asc_label)
	_update_ascension_indicator()


func _update_ascension_indicator() -> void:
	if _asc_label == null:
		return
	var count := SaveManager.get_ascension_count()
	if count <= 0:
		_asc_label.visible = false
		return
	_asc_label.visible = true
	var pct := int((SaveManager.get_ascension_xp_mult() - 1.0) * 100.0)
	# Placeholder: gold chevron "»" as wings. Art to provide sprite.
	_asc_label.text = "» %d" % count
	_asc_label.tooltip_text = "+%d%% XP (%d ascension%s)" % [pct, count, "" if count == 1 else "s"]


## Issue #69 Phase 1: Update the charge meter. Called by player.
func set_charge_meter(charge: float, visible: bool) -> void:
	if _charge_bar == null:
		return
	_charge_bar.visible = visible
	_charge_bar.value = clampf(charge, 0.0, 1.0)


## Compact bounty tracker (issue #7 Phase 2): 2-3 short lines under the
## TopRight objective cluster, auto-hides when no bounties are active.
## Code-built (not in the tscn) so it works with bare-script harnesses too.
func _build_bounty_tracker() -> void:
	if _bounty_tracker != null:
		return
	_bounty_tracker = Label.new()
	_bounty_tracker.name = "BountyTracker"
	_bounty_tracker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_bounty_tracker.offset_left = -516.0
	_bounty_tracker.offset_top = 130.0
	_bounty_tracker.offset_right = -16.0
	_bounty_tracker.offset_bottom = 214.0
	_bounty_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bounty_tracker.add_theme_font_size_override("font_size", 14)
	_bounty_tracker.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	_bounty_tracker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_bounty_tracker.add_theme_constant_override("outline_size", 4)
	_bounty_tracker.visible = false
	add_child(_bounty_tracker)


## Potion quick-slot (Jesse's feature): small slot left of the ability bar.
## Left-click cycles the equipped potion type (only types in inventory).
## H drinks via Player.use_item(). Code-built for bare-script harnesses.
func _build_potion_slot() -> void:
	if _potion_button != null:
		return
	_potion_button = Button.new()
	_potion_button.name = "PotionSlot"
	# Bottom-center, left of the AbilityBar (bar spans -220..+220).
	_potion_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_potion_button.offset_left = -296.0
	_potion_button.offset_top = -76.0
	_potion_button.offset_right = -232.0
	_potion_button.offset_bottom = -12.0
	_potion_button.tooltip_text = PromptText.resolve("Left-click: cycle potion type. {potion}: drink.")
	_potion_button.pressed.connect(_cycle_potion)
	# Count label (bottom-right of the slot).
	_potion_count_label = Label.new()
	_potion_count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_potion_count_label.offset_left = -28.0
	_potion_count_label.offset_top = -20.0
	_potion_count_label.offset_right = -4.0
	_potion_count_label.offset_bottom = -4.0
	_potion_count_label.add_theme_font_size_override("font_size", 14)
	_potion_count_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_potion_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_potion_count_label.add_theme_constant_override("outline_size", 3)
	_potion_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_potion_button.add_child(_potion_count_label)
	# Key hint label (top-left).
	var key_hint := Label.new()
	key_hint.text = "[H]"
	key_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key_hint.offset_left = 4.0
	key_hint.offset_top = 2.0
	key_hint.add_theme_font_size_override("font_size", 11)
	key_hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_potion_button.add_child(key_hint)
	add_child(_potion_button)
	refresh_potion_slot()


## Update the potion slot from the player's inventory. Called from
## refresh_inventory() and after cycling/drinking.
func refresh_potion_slot() -> void:
	if _potion_button == null:
		return
	if _potion_player == null or not is_instance_valid(_potion_player):
		# Issue #77: the player joins group "players" (plural); prefer the
		# setup() player and only fall back to the group lookup.
		if _player != null and is_instance_valid(_player):
			_potion_player = _player
		else:
			_potion_player = get_tree().get_first_node_in_group("players") as Player
	if _potion_player == null:
		_potion_button.visible = false
		return
	_potion_button.visible = true
	# Count each potion type in inventory.
	var counts := {}
	for pid in POTION_IDS:
		counts[pid] = 0
	for entry in _potion_player.inventory:
		var item = entry["item"]
		if item != null and counts.has(item.id):
			counts[item.id] = int(counts[item.id]) + int(entry["count"])
	# If equipped type is empty, auto-advance to a type with stock.
	var equipped: String = POTION_IDS[_potion_idx]
	if int(counts[equipped]) <= 0:
		for i in POTION_IDS.size():
			var pid: String = POTION_IDS[(_potion_idx + i) % POTION_IDS.size()]
			if int(counts[pid]) > 0:
				_potion_idx = POTION_IDS.find(pid)
				equipped = pid
				break
	var total := 0
	for pid in POTION_IDS:
		total += int(counts[pid])
	if total <= 0:
		# Empty/greyed state.
		_potion_button.modulate = Color(0.4, 0.4, 0.4, 0.6)
		_potion_count_label.text = ""
		_potion_button.text = "—"
		_potion_button.tooltip_text = "No potions. Buy from the station vendor."
		return
	# Show equipped type.
	var color: Color = POTION_COLORS[equipped]
	_potion_button.modulate = Color(1, 1, 1, 1)
	# Tint via theme stylebox.
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.55)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_potion_button.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = color.darkened(0.4)
	_potion_button.add_theme_stylebox_override("hover", sbh)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = color.darkened(0.7)
	_potion_button.add_theme_stylebox_override("pressed", sbp)
	_potion_button.text = POTION_NAMES[equipped]
	_potion_count_label.text = "x%d" % int(counts[equipped])
	_potion_button.tooltip_text = PromptText.resolve("%s Potion x%d — Left-click: cycle. {potion}: drink." % [POTION_NAMES[equipped], int(counts[equipped])])


## Left-click: cycle to the next potion type the player actually has.
func _cycle_potion() -> void:
	if _potion_player == null or not is_instance_valid(_potion_player):
		return
	# Build list of types with stock.
	var available: Array = []
	for entry in _potion_player.inventory:
		var item = entry["item"]
		if item != null and POTION_IDS.has(item.id) and int(entry["count"]) > 0:
			if not available.has(item.id):
				available.append(item.id)
	if available.size() <= 1:
		return  # Nothing to cycle to.
	var current: String = POTION_IDS[_potion_idx]
	var pos := available.find(current)
	if pos == -1:
		_potion_idx = POTION_IDS.find(available[0])
	else:
		_potion_idx = POTION_IDS.find(available[(pos + 1) % available.size()])
	AudioManager.sfx("ui_click")
	refresh_potion_slot()


## H key: drink the equipped potion via the server-authoritative use_item().
func drink_potion() -> void:
	if _potion_player == null or not is_instance_valid(_potion_player):
		return
	var pid: String = POTION_IDS[_potion_idx]
	# Find the inventory index for this potion type.
	for i in _potion_player.inventory.size():
		var entry: Dictionary = _potion_player.inventory[i]
		var item = entry["item"]
		if item != null and item.id == pid and int(entry["count"]) > 0:
			_potion_player.use_item(i)
			refresh_potion_slot()
			return
	# Equipped type ran out — refresh to auto-advance or show empty.
	refresh_potion_slot()


## Rework the pause panel into five tabs (Stats / Specialization /
## Collection / Keybinds / Voice).
## Action buttons are moved outside the ScrollContainer, fixed at the bottom.
func _build_pause_tabs() -> void:
	# Bare-script harnesses (no tscn) have no pause panel; skip cleanly.
	var panel := get_node_or_null("%PausePanel") as PanelContainer
	if panel == null:
		return
	# Idempotent: skip if already built (e.g. scene re-entered).
	if panel.get_node_or_null("PauseMain") != null:
		return
	var scroll := panel.get_node("PauseScroll") as ScrollContainer
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vbox := scroll.get_node("PauseVBox") as VBoxContainer
	# Main layout: title, tabs, scroll (expanding), actions (fixed bottom).
	var main := VBoxContainer.new()
	main.name = "PauseMain"
	main.add_theme_constant_override("separation", 6)
	panel.add_child(main)
	# Move title + divider to main.
	for n in ["PausedLabel", "PauseDivider"]:
		var c := vbox.get_node(n) as Control
		c.reparent(main)
	# Tab bar.
	var tab_bar := HBoxContainer.new()
	tab_bar.name = "PauseTabBar"
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 4)
	main.add_child(tab_bar)
	var tab_names := ["Stats", "Specialization", "Collection", "Keybinds", "Voice"]
	for i in tab_names.size():
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.toggle_mode = true
		btn.pressed.connect(_on_pause_tab_pressed.bind(i))
		_style_tab_button(btn, i == 0)
		tab_bar.add_child(btn)
		_pause_tab_btns.append(btn)
	# Compact the Stats tab so its content fits the pause panel with zero
	# scrolling (Jesse's hard rule). Stat rows become two columns; hint
	# text shrinks; spacing tightens.
	_compact_stats_tab(vbox)
	# Keybinds + Voice panels are built in code and join the vbox;
	# each is the sole member of its tab.
	_build_keybinds_panel(vbox)
	_build_voice_panel(vbox)
	# Define tab membership.
	_pause_tab_members = [
		["HintLabel", "VolLabel", "MasterRow", "MusicRow", "SFXRow",
			"StatPointsLabel", "StatPair1", "StatPair2", "StatPair3"],
		["SpecLabel", "SpecList"],
		["FamilyLabel", "FamilyPanel", "CollectionLabel", "CollectionLog"],
		["KeybindsPanel"],
		["VoicePanel"],
	]
	# Move the scroll into main (expanding).
	scroll.reparent(main)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Action buttons: fixed at bottom, outside the scroll.
	var actions := VBoxContainer.new()
	actions.name = "PauseActions"
	actions.add_theme_constant_override("separation", 4)
	main.add_child(actions)
	for nn in ["ResumeButton", "ClassButton", "QuitButton", "SaveQuitButton"]:
		var b := vbox.get_node_or_null(nn) as Button
		if b != null:
			b.reparent(actions)
			if nn == "ClassButton":
				_class_btn = b
			elif nn == "SaveQuitButton":
				_save_quit_btn = b
	# Remove the now-empty old VBox (scroll was moved, vbox is orphaned).
	# Note: vbox is still a child of scroll; scroll was reparented with it.


## Keybind rows for the Keybinds tab: one row per KEYBIND_ACTIONS
## entry — {"action", "display", "bindings"} — with the bindings
## rendered from the LIVE InputMap, plus three summary rows for
## controls that are not InputMap actions (mouse look, the RTS
## command-view toggle, menu navigation). Pure data: the suite
## pins coverage and binding truth against this, the panel below
## only renders it.
func keybind_rows() -> Array:
	var rows: Array = []
	for spec in KEYBIND_ACTIONS:
		var action := str(spec[0])
		rows.append({
			"action": action,
			"display": str(spec[1]),
			"bindings": _keybind_binding_text(action),
		})
	rows.insert(4, {"action": "", "display": "Look", "bindings": "Mouse"})
	rows.append({"action": "", "display": "Command View (RTS)", "bindings": "Tab"})
	rows.append({"action": "", "display": "Menu Navigation",
		"bindings": "Arrow Keys, Enter / Space, Esc"})
	return rows


## All bindings of one action as one line ("W, Up, Left Stick"),
## duplicates collapsed (the four move actions each bind two
## left-stick axes, which read once).
func _keybind_binding_text(action: String) -> String:
	var parts: Array = []
	for ev in InputMap.action_get_events(action):
		var t := _keybind_event_text(ev)
		if t != "" and not parts.has(t):
			parts.append(t)
	var out := ""
	for i in parts.size():
		out += (", " if i > 0 else "") + str(parts[i])
	return out


## One bound event in player words. Keys name by their physical
## position (the layout the prompts use); pad controls carry a
## "Pad" prefix so the two families never blur on one line.
static func _keybind_event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "Left Click"
			MOUSE_BUTTON_RIGHT:
				return "Right Click"
			MOUSE_BUTTON_MIDDLE:
				return "Middle Click"
			MOUSE_BUTTON_XBUTTON1:
				return "Mouse X1"
			MOUSE_BUTTON_XBUTTON2:
				return "Mouse X2"
			MOUSE_BUTTON_WHEEL_UP:
				return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel Down"
		return "Mouse Button"
	if ev is InputEventJoypadButton:
		var pad_names := ["Pad A", "Pad B", "Pad X", "Pad Y", "Pad View",
			"Pad Guide", "Pad Menu", "Pad LS Click", "Pad RS Click",
			"Pad LB", "Pad RB", "Pad D-Pad Up", "Pad D-Pad Down",
			"Pad D-Pad Left", "Pad D-Pad Right"]
		var bi := (ev as InputEventJoypadButton).button_index
		if bi >= 0 and bi < pad_names.size():
			return pad_names[bi]
		return "Pad Button %d" % bi
	if ev is InputEventJoypadMotion:
		match (ev as InputEventJoypadMotion).axis:
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
				return "Left Stick"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
				return "Right Stick"
			JOY_AXIS_TRIGGER_LEFT:
				return "Pad LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "Pad RT"
		return "Pad Stick"
	return ""


## Build the Keybinds tab: two columns of one-line rows, small
## type, so ALL the bindings fit the pause panel with zero
## scrolling (Jesse's fit-to-screen rule — no scroll approval
## was given for this tab).
func _build_keybinds_panel(vbox: VBoxContainer) -> void:
	var panel := HBoxContainer.new()
	panel.name = "KeybindsPanel"
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 24)
	var rows := keybind_rows()
	var half := (rows.size() + 1) / 2
	for side in 2:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		for i in range(side * half, mini((side + 1) * half, rows.size())):
			var lab := Label.new()
			lab.text = "%s: %s" % [str(rows[i]["display"]), str(rows[i]["bindings"])]
			lab.add_theme_font_size_override("font_size", 11)
			col.add_child(lab)
		panel.add_child(col)
	vbox.add_child(panel)


## Build the Voice tab: the voice-chat settings, mirroring the
## main-menu Settings panel's voice block (transmit / mode / mic
## threshold / status / device note) plus a mic-mute toggle and
## the voice playback volume, so they are reachable in-game.
## Everything wires the same VoiceManager / AudioManager
## settings the menu panel does — one source of truth, two
## surfaces.
func _build_voice_panel(vbox: VBoxContainer) -> void:
	var panel := VBoxContainer.new()
	panel.name = "VoicePanel"
	panel.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Voice Chat"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	panel.add_child(title)
	# Transmit toggle.
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 12)
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	var tlab := Label.new()
	tlab.text = "Transmit"
	tlab.custom_minimum_size = Vector2(120, 0)
	trow.add_child(tlab)
	_pause_voice_transmit_tog = CheckButton.new()
	_pause_voice_transmit_tog.toggled.connect(_on_pause_voice_transmit_toggled)
	trow.add_child(_pause_voice_transmit_tog)
	panel.add_child(trow)
	# Mode picker.
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 12)
	mrow.alignment = BoxContainer.ALIGNMENT_CENTER
	var mlab := Label.new()
	mlab.text = "Mode"
	mlab.custom_minimum_size = Vector2(120, 0)
	mrow.add_child(mlab)
	_pause_voice_mode_opt = OptionButton.new()
	_pause_voice_mode_opt.add_item("Auto", 0)
	_pause_voice_mode_opt.add_item("Push-to-talk", 1)
	_pause_voice_mode_opt.add_item("Voice activation", 2)
	_pause_voice_mode_opt.item_selected.connect(_on_pause_voice_mode_selected)
	mrow.add_child(_pause_voice_mode_opt)
	panel.add_child(mrow)
	# Mic threshold slider.
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	hrow.alignment = BoxContainer.ALIGNMENT_CENTER
	var hlab := Label.new()
	hlab.text = "Mic threshold"
	hlab.custom_minimum_size = Vector2(120, 0)
	hrow.add_child(hlab)
	_pause_voice_thresh_slider = HSlider.new()
	_pause_voice_thresh_slider.custom_minimum_size = Vector2(160, 0)
	_pause_voice_thresh_slider.min_value = -60
	_pause_voice_thresh_slider.max_value = -10
	_pause_voice_thresh_slider.step = 1
	_pause_voice_thresh_slider.value_changed.connect(_on_pause_voice_thresh_changed)
	hrow.add_child(_pause_voice_thresh_slider)
	_pause_voice_thresh_val = Label.new()
	_pause_voice_thresh_val.custom_minimum_size = Vector2(40, 0)
	hrow.add_child(_pause_voice_thresh_val)
	panel.add_child(hrow)
	# Mic muted toggle (the M key's state, shown and settable).
	var urow := HBoxContainer.new()
	urow.add_theme_constant_override("separation", 12)
	urow.alignment = BoxContainer.ALIGNMENT_CENTER
	var ulab := Label.new()
	ulab.text = "Mic muted"
	ulab.custom_minimum_size = Vector2(120, 0)
	urow.add_child(ulab)
	_pause_voice_mute_tog = CheckButton.new()
	_pause_voice_mute_tog.toggled.connect(_on_pause_voice_mute_toggled)
	urow.add_child(_pause_voice_mute_tog)
	panel.add_child(urow)
	# Voice playback volume.
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 12)
	vrow.alignment = BoxContainer.ALIGNMENT_CENTER
	var vlab := Label.new()
	vlab.text = "Voice volume"
	vlab.custom_minimum_size = Vector2(120, 0)
	vrow.add_child(vlab)
	_pause_voice_vol_slider = HSlider.new()
	_pause_voice_vol_slider.custom_minimum_size = Vector2(160, 0)
	_pause_voice_vol_slider.min_value = 0
	_pause_voice_vol_slider.max_value = 100
	_pause_voice_vol_slider.step = 1
	_pause_voice_vol_slider.value_changed.connect(_on_pause_voice_vol_changed)
	vrow.add_child(_pause_voice_vol_slider)
	_pause_voice_vol_val = Label.new()
	_pause_voice_vol_val.custom_minimum_size = Vector2(40, 0)
	vrow.add_child(_pause_voice_vol_val)
	panel.add_child(vrow)
	# Mic status + the PTT/mute keys (read from the live InputMap).
	_pause_voice_status_label = Label.new()
	_pause_voice_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_pause_voice_status_label)
	var keys := Label.new()
	keys.text = "Push-to-talk: %s · Mute mic: %s" % [
		_keybind_binding_text("voice_ptt"), _keybind_binding_text("voice_mute")]
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.add_theme_font_size_override("font_size", 12)
	panel.add_child(keys)
	var note := Label.new()
	note.text = "Microphone device: set in Steam / system settings."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	panel.add_child(note)
	vbox.add_child(panel)
	_refresh_pause_voice_rows()


## Voice tab wiring — thin handlers onto the VoiceManager
## autoload, mirroring the main-menu Settings panel's voice rows.
func _voice_manager() -> Node:
	return get_node_or_null("/root/VoiceManager")


func _refresh_pause_voice_rows() -> void:
	var vm := _voice_manager()
	if vm != null:
		if _pause_voice_transmit_tog != null:
			_pause_voice_transmit_tog.set_pressed_no_signal(bool(vm.get("transmit_enabled")))
		if _pause_voice_mode_opt != null:
			var modes := ["auto", "ptt", "va"]
			_pause_voice_mode_opt.select(maxi(modes.find(str(vm.get("mode"))), 0))
		if _pause_voice_thresh_slider != null:
			_pause_voice_thresh_slider.set_value_no_signal(float(vm.get("va_threshold_db")))
			if _pause_voice_thresh_val != null:
				_pause_voice_thresh_val.text = "%d" % int(float(vm.get("va_threshold_db")))
		if _pause_voice_mute_tog != null:
			_pause_voice_mute_tog.set_pressed_no_signal(bool(vm.get("mic_muted")))
		if _pause_voice_status_label != null:
			_pause_voice_status_label.text = str(vm.call("mic_status_text"))
	var am := get_node_or_null("/root/AudioManager")
	if am != null and _pause_voice_vol_slider != null:
		_pause_voice_vol_slider.set_value_no_signal(float(am.get("voice_vol")) * 100.0)
		if _pause_voice_vol_val != null:
			_pause_voice_vol_val.text = "%d" % int(float(am.get("voice_vol")) * 100.0)


func _on_pause_voice_transmit_toggled(on: bool) -> void:
	var vm := _voice_manager()
	if vm != null:
		vm.call("set_transmit_enabled", on)
	_refresh_pause_voice_rows()


func _on_pause_voice_mode_selected(idx: int) -> void:
	var vm := _voice_manager()
	if vm != null:
		vm.call("set_mode", ["auto", "ptt", "va"][idx])
	_refresh_pause_voice_rows()


func _on_pause_voice_thresh_changed(value: float) -> void:
	var vm := _voice_manager()
	if vm != null:
		vm.call("set_va_threshold_db", value)
	if _pause_voice_thresh_val != null:
		_pause_voice_thresh_val.text = "%d" % int(value)


func _on_pause_voice_mute_toggled(on: bool) -> void:
	var vm := _voice_manager()
	if vm != null:
		vm.call("set_mic_muted", on)
	_refresh_pause_voice_rows()


func _on_pause_voice_vol_changed(value: float) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.call("set_voice_vol", value / 100.0)
	if _pause_voice_vol_val != null:
		_pause_voice_vol_val.text = "%d" % int(value)


## Compact the Stats tab so its content fits the pause panel with zero
## scrolling. Called once from _build_pause_tabs() (idempotent via the
## early-return there). The two-column stat pairs (StatPair1/StatPair2)
## live in the scene so unique-name lookups keep working; here we only
## tighten spacing, shrink the title/divider/hint, and slim stat labels.
func _compact_stats_tab(vbox: VBoxContainer) -> void:
	vbox.add_theme_constant_override("separation", 6)
	# Title + divider shrink slightly to give the scroll viewport more room.
	var title := vbox.get_node_or_null("PausedLabel") as Label
	if title != null:
		title.add_theme_font_size_override("font_size", 30)
	var div := vbox.get_node_or_null("PauseDivider") as TextureRect
	if div != null:
		div.custom_minimum_size = Vector2(0, 16)
	# Shorter controls hint, smaller font — one line at panel width.
	# Issue #152 (2A-2): token template rendered through PromptText
	# (KB rendering is the pre-token string byte-for-byte); the
	# label is kept so source flips re-render it live.
	var hint := vbox.get_node_or_null("HintLabel") as Label
	if hint != null:
		hint.add_theme_font_size_override("font_size", 12)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = PromptText.resolve(PAUSE_HINT_TEMPLATE)
		_pause_hint_label = hint
	# Slimmer stat labels so two columns fit the 480px panel.
	for pn in ["StatPair1", "StatPair2", "StatPair3"]:
		var pair := vbox.get_node_or_null(pn) as HBoxContainer
		if pair == null:
			continue
		for row in pair.get_children():
			for c in (row as HBoxContainer).get_children():
				if c is Label:
					(c as Label).add_theme_font_size_override("font_size", 13)


## Gold-on-dark styling for the tab buttons; selected tab is highlighted.
func _style_tab_button(btn: Button, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.2, 0.08, 0.95) if selected else Color(0.08, 0.08, 0.1, 0.75)
	sb.border_color = Color(0.8, 0.65, 0.25, 1.0)
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(4)
	# Five tabs share the 480px panel (2026-10-28): padding and
	# font slimmed from the three-tab era so the bar still fits
	# on one row with no scrolling.
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if selected else Color(0.7, 0.7, 0.75))
	btn.add_theme_font_size_override("font_size", 13)


func _on_pause_tab_pressed(idx: int) -> void:
	_pause_tab = idx
	for i in _pause_tab_btns.size():
		_pause_tab_btns[i].button_pressed = i == idx
		_style_tab_button(_pause_tab_btns[i], i == idx)
	_apply_pause_tab_visibility()
	# Issue #37 reopened: refresh the collection log on tab switch so the
	# redundant headers hide when there's full progress content.
	if idx == 2:
		_refresh_collection_log()
	# Voice tab: reflect the live VoiceManager state on every visit
	# (the M-key mute and the menu panel can change it meanwhile).
	if idx == 4:
		_refresh_pause_voice_rows()
	# Stats, Collection, Keybinds and Voice tabs are designed to fit; scrolling hard-disabled
	# (layouts that cannot scroll, not promises). Specialization keeps
	# auto-scroll as a safety valve.
	var scroll := %PausePanel.get_node("PauseMain/PauseScroll") as ScrollContainer
	if scroll != null:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if idx == 1 else ScrollContainer.SCROLL_MODE_DISABLED
	# Issue #152: tab visibility changed the focusable set — re-chain;
	# a focused control on the now-hidden tab re-seeds to Resume.
	if is_paused:
		FocusChain.apply(_pause_surface(), _pause_primary())


## Show only the current tab's nodes; action buttons are outside the scroll.
func _apply_pause_tab_visibility() -> void:
	var scroll := %PausePanel.get_node("PauseMain/PauseScroll") as ScrollContainer
	var vbox := scroll.get_node("PauseVBox") as VBoxContainer
	for i in _pause_tab_members.size():
		var visible := i == _pause_tab
		for nn in _pause_tab_members[i]:
			var c := vbox.get_node_or_null(nn) as Control
			if c != null:
				c.visible = visible
	# Force the container to recalculate; hidden nodes must not reserve space.
	vbox.queue_sort()
	scroll.scroll_vertical = 0


## Programmatic tab selection (used by tools and external callers).
func select_pause_tab(idx: int) -> void:
	if idx >= 0 and idx < 5:
		_on_pause_tab_pressed(idx)


func _process(delta: float) -> void:
	# Cipher popup input grace (don't let the opening keypress close it).
	if _cipher_grace > 0.0:
		_cipher_grace -= delta
	# Bounty tracker (issue #7 Phase 2): refresh at 2 Hz from live data.
	_bounty_tick += delta
	if _bounty_tick >= 0.5:
		_bounty_tick = 0.0
		_refresh_bounty_tracker()
	# Issue #19: refresh ability bar when Warlord state changes
	# (hide/show Eagle Eye slot).
	var warlord_now := _is_warlord_theme()
	if warlord_now != _last_warlord:
		_last_warlord = warlord_now
		if _player != null:
			refresh_abilities(_player)
	# Potion quick-slot: lazy-show when the player spawns (in case
	# refresh_inventory hasn't run yet).
	if _potion_button != null and not _potion_button.visible:
		# Issue #77: player joins group "players" (plural); the setup() player
	# counts too.
		if _player != null or get_tree().get_first_node_in_group("players") != null:
			refresh_potion_slot()
	# Low-HP vignette: pulses red as health drops below 35%.
	if _hp_frac < 0.35 and _player != null and _player.get("alive"):
		_vignette_t += delta
		var pulse := 0.5 + 0.5 * sin(_vignette_t * 6.0)
		var strength := (0.35 - _hp_frac) / 0.35
		%LowHPVignette.color.a = 0.12 + 0.28 * strength * pulse
	else:
		%LowHPVignette.color.a = 0.0


# --- Combat feedback ---

var _hitmarker_tween: Tween


func show_hitmarker() -> void:
	%Crosshair.text = "x"
	if _hitmarker_tween != null and _hitmarker_tween.is_valid():
		_hitmarker_tween.kill()
	_hitmarker_tween = create_tween()
	_hitmarker_tween.tween_interval(0.12)
	_hitmarker_tween.tween_callback(func() -> void: %Crosshair.text = "+")


func show_boss_card(title: String) -> void:
	%BossCard.text = title
	%BossCard.visible = true
	%BossCard.modulate.a = 0.0
	%BossCard.scale = Vector2(1.3, 1.3)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(%BossCard, "modulate:a", 1.0, 0.4)
	tw.tween_property(%BossCard, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.6)
	tw.tween_property(%BossCard, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void: %BossCard.visible = false)


func _on_xp_changed(xp: int, xp_next: int, _level: int) -> void:
	%XPBar.max_value = xp_next
	%XPBar.value = xp


func _on_leveled_up(level: int) -> void:
	set_level(level, _player)


## Issue #95 Phase 2: player click-action state changed (rogue charge,
## Holy Light arm/charge) — re-render the legend immediately, no polling.
func _on_click_state_changed() -> void:
	refresh_mouse_legend(_player)


func set_level(level: int, p: Node) -> void:
	%LevelLabel.text = "Lv %d %s" % [level, (p.get("class_data") as ClassData).display_name]


## All carried items apply. Shows total items, stack count, stacked multipliers.
func refresh_loadout(p: Player) -> void:
	var lines: Array[String] = []
	var total := 0
	for entry in p.inventory:
		total += int(entry["count"])
	lines.append("Carried items: %d (%d %s)" % [total, p.inventory.size(), "stack" if p.inventory.size() == 1 else "stacks"])
	lines.append("DMG x%.2f · HP x%.2f · SPD x%.2f · XP x%.2f" % [
		_item_mult(p, "damage"), _item_mult(p, "health"), _item_mult(p, "speed"), p.xp_mult])
	%EquipLabel.text = "\n".join(lines)


func _item_mult(p: Player, kind: String) -> float:
	var m := 1.0
	for entry in p.inventory:
		var item := entry["item"] as ItemData
		if item == null:
			continue
		var count := int(entry["count"])
		match kind:
			"damage":
				m *= pow(item.damage_mult, count)
			"health":
				m *= pow(item.health_mult, count)
			"speed":
				m *= pow(item.speed_mult, count)
	return m


func toast(message: String) -> void:
	# Issue #190 (section 2): display-point resolution — a
	# toast authored with tokens (on any peer, by any author)
	# renders with THIS viewer's bindings.
	%ToastLabel.text = PromptText.resolve(message)
	%ToastLabel.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(%ToastLabel, "modulate:a", 0.0, 0.6)


## Alias used by achievement unlock calls.
func show_toast(message: String) -> void:
	toast(message)


# --- Station vendor (Train Station Phase 4) ---

var vendor_open := false
var _vendor_cash_label: Label = null


## Vendor panel: 3 potions + 3 rotating items, compact, no scroll.
## Reuses the cipher popup shell (mouse visible, E/Esc closes).
func show_vendor() -> void:
	var st := get_tree().get_first_node_in_group("station")
	if st == null or _player == null:
		return
	var stock: Array = st.get("vendor_stock")
	var vb := _cipher_panel()
	var title := Label.new()
	title.text = "Vendor"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(title)
	_vendor_cash_label = Label.new()
	_vendor_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vendor_cash_label.add_theme_font_size_override("font_size", 14)
	_vendor_cash_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	vb.add_child(_vendor_cash_label)
	refresh_vendor_cash()
	for entry in stock:
		var item_id := str(entry.get("id"))
		var price := int(entry.get("price"))
		var item := ItemDB.get_item(item_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var nl := Label.new()
		nl.text = item.display_name if item != null else item_id
		nl.custom_minimum_size = Vector2(230, 0)
		nl.add_theme_font_size_override("font_size", 14)
		row.add_child(nl)
		var pl := Label.new()
		pl.text = "$%d" % price
		pl.custom_minimum_size = Vector2(64, 0)
		pl.add_theme_font_size_override("font_size", 14)
		pl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		row.add_child(pl)
		var buy := Button.new()
		buy.text = "BUY"
		buy.pressed.connect(_on_vendor_buy.bind(st, item_id))
		row.add_child(buy)
		vb.add_child(row)
	var close_hint := Label.new()
	close_hint.text = PromptText.resolve(CLOSE_HINT_TEMPLATE)
	_track_prompt_label(close_hint, CLOSE_HINT_TEMPLATE)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vb.add_child(close_hint)
	_open_cipher_popup(vb.get_parent() as Control)
	# Set AFTER the open: _open_cipher_popup's pre-open cleanup
	# (close_cipher_popup) resets every popup flag, including this one.
	vendor_open = true


func refresh_vendor_cash() -> void:
	if _vendor_cash_label != null and is_instance_valid(_vendor_cash_label) and _player != null:
		_vendor_cash_label.text = "Your cash: $%d" % int(_player.get("supermarket_cash"))


func _on_vendor_buy(st: Node, item_id: String) -> void:
	# SteamMultiplayerPeer can't rpc_id its own peer ID: call directly as server.
	if multiplayer.is_server():
		st.buy_vendor_item(item_id)
	else:
		st.rpc_id(NetworkManager.server_peer_id, "buy_vendor_item", item_id)
	AudioManager.sfx("ui_click")


# --- Dock merchant (issue #102 Phase 4) ---

var dock_vendor_open := false
var _dock_cash_label: Label = null


## Dock merchant panel: buy seeds/bait/fertilizer/consumables/buffs for
## farm cash, sell fish/crops for farm cash. Compact, no scroll. Reuses the
## cipher popup shell (mouse visible, E/Esc closes), mirroring show_vendor.
func show_dock_vendor() -> void:
	var merch := get_tree().get_first_node_in_group("dock_merchant")
	if merch == null or _player == null:
		return
	var vb := _cipher_panel()
	var title := Label.new()
	title.text = "Dock Merchant"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.65, 0.95, 1.0))
	vb.add_child(title)
	_dock_cash_label = Label.new()
	_dock_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dock_cash_label.add_theme_font_size_override("font_size", 14)
	_dock_cash_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(_dock_cash_label)
	# Local mirror first; the server answers with the authoritative ledger
	# balance right after (request_dock_balance -> dock_balance).
	_dock_cash_label.text = "Farm cash: %d" % _player.farm_cash_count()
	if multiplayer.is_server():
		merch.request_dock_balance()
	else:
		merch.rpc_id(NetworkManager.server_peer_id, "request_dock_balance")
	var buy_head := Label.new()
	buy_head.text = "— Buy —"
	buy_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buy_head.add_theme_font_size_override("font_size", 13)
	buy_head.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vb.add_child(buy_head)
	for entry in merch.get_catalog():
		var item_id := str(entry.get("id"))
		var price := int(entry.get("price"))
		var item: ItemData = ItemDB.get_item(item_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var nl := Label.new()
		nl.text = item.display_name if item != null else item_id
		if bool(entry.get("gear", false)):
			nl.text += " [GEAR]"
		nl.custom_minimum_size = Vector2(230, 0)
		nl.add_theme_font_size_override("font_size", 14)
		row.add_child(nl)
		var pl := Label.new()
		# Issue #161: a 0-price row (the free fishing rod) reads "Free",
		# not a bare "0 fc".
		pl.text = "Free" if price == 0 else "%d fc" % price
		pl.custom_minimum_size = Vector2(64, 0)
		pl.add_theme_font_size_override("font_size", 14)
		pl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		row.add_child(pl)
		var buy := Button.new()
		buy.text = "BUY"
		buy.pressed.connect(_on_dock_buy.bind(merch, item_id))
		row.add_child(buy)
		vb.add_child(row)
	var sell_head := Label.new()
	sell_head.text = "— Sell (your holdings) —"
	sell_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_head.add_theme_font_size_override("font_size", 13)
	sell_head.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vb.add_child(sell_head)
	var any_sell := false
	for inv_entry in _player.inventory:
		var e_item: ItemData = inv_entry.get("item")
		if e_item == null:
			continue
		var value := DockEconomy.sell_value_for(e_item.id)
		if value <= 0:
			continue
		any_sell = true
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 10)
		var snl := Label.new()
		snl.text = "%s x%d" % [e_item.display_name, int(inv_entry.get("count"))]
		snl.custom_minimum_size = Vector2(230, 0)
		snl.add_theme_font_size_override("font_size", 14)
		srow.add_child(snl)
		var spl := Label.new()
		spl.text = "+%d fc" % value
		spl.custom_minimum_size = Vector2(64, 0)
		spl.add_theme_font_size_override("font_size", 14)
		spl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		srow.add_child(spl)
		var sell := Button.new()
		sell.text = "SELL"
		sell.pressed.connect(_on_dock_sell.bind(merch, e_item.id))
		srow.add_child(sell)
		vb.add_child(srow)
	if not any_sell:
		var none := Label.new()
		none.text = "(nothing to sell — go fish)"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_font_size_override("font_size", 12)
		none.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		vb.add_child(none)
	var close_hint := Label.new()
	close_hint.text = PromptText.resolve(CLOSE_HINT_TEMPLATE)
	_track_prompt_label(close_hint, CLOSE_HINT_TEMPLATE)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vb.add_child(close_hint)
	_open_cipher_popup(vb.get_parent() as Control)
	# Set AFTER the open: _open_cipher_popup's pre-open cleanup
	# (close_cipher_popup) resets every popup flag, including this one.
	dock_vendor_open = true


## Server-authoritative balance lands here (merchant.dock_balance RPC).
func set_dock_balance(balance: int) -> void:
	if _dock_cash_label != null and is_instance_valid(_dock_cash_label):
		_dock_cash_label.text = "Farm cash: %d" % balance


## Rebuild the panel after a buy/sell so holdings + buttons refresh.
func refresh_dock_vendor() -> void:
	if dock_vendor_open:
		show_dock_vendor()


func _on_dock_buy(merch: Node, item_id: String) -> void:
	# SteamMultiplayerPeer can't rpc_id its own peer ID: call directly as server.
	if multiplayer.is_server():
		merch.request_buy(item_id)
	else:
		merch.rpc_id(NetworkManager.server_peer_id, "request_buy", item_id)
	AudioManager.sfx("ui_click")


func _on_dock_sell(merch: Node, item_id: String) -> void:
	if multiplayer.is_server():
		merch.request_sell(item_id)
	else:
		merch.rpc_id(NetworkManager.server_peer_id, "request_sell", item_id)
	AudioManager.sfx("ui_click")


# --- Bounty Board (issue #7 Phase 2) ---

var bounty_open := false
var _bounty_tracker: Label = null
# Potion quick-slot (Jesse's feature): HUD slot next to the ability bar.
# Left-click cycles the equipped potion type; H drinks via Player.use_item().
# Only cycles through types the player actually has in inventory.
const POTION_IDS := ["health_potion", "swift_potion", "power_elixir"]
const POTION_COLORS := {
	"health_potion": Color(0.9, 0.25, 0.25),
	"swift_potion": Color(0.25, 0.7, 1.0),
	"power_elixir": Color(0.85, 0.55, 0.15),
}
const POTION_NAMES := {
	"health_potion": "Health",
	"swift_potion": "Swift",
	"power_elixir": "Power",
}
var _potion_idx := 0
var _potion_button: Button = null
var _potion_count_label: Label = null
var _potion_player: Player = null
var _bounty_tick := 0.0
## Issue #19: tracks Warlord theme state to refresh the ability bar
## (hide/show Eagle Eye) when entering/leaving Warlord.
var _last_warlord := false
## Warlord mode hides the objective cluster; the tracker hides with it.
var _bounty_hide := false
# Issue #62: tracks whether the boarding phase is active, so the wave
# button stays hidden during ALL ABOARD.
var _boarding_active := false


## Bounty panel: 3 fixed cards (name / target / reward / per-player progress
## bar / claimed state). Fixed layout, no ScrollContainer — cannot scroll.
## Reuses the cipher popup shell (mouse visible, E/Esc closes).
func show_bounty() -> void:
	var bnode := get_tree().get_first_node_in_group("bounty_system")
	if bnode == null or _player == null:
		return
	var bounties: Array = bnode.get("bounties")
	if bounties.size() != 3:
		return
	var progress: Dictionary = _player.get("bounty_progress")
	AudioManager.sfx("bounty_accept")
	var vb := _cipher_panel()
	var title := Label.new()
	title.text = "Bounty Board"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(title)
	for b in bounties:
		vb.add_child(BountyUI.make_card(b, progress))
	var expiry := Label.new()
	expiry.text = "Unclaimed bounties expire at departure."
	expiry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	expiry.add_theme_font_size_override("font_size", 12)
	expiry.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	vb.add_child(expiry)
	# Issue #34: the panel was built but never opened — actually render it.
	_open_cipher_popup(vb.get_parent() as Control)
	# Set AFTER the open: _open_cipher_popup's pre-open cleanup
	# (close_cipher_popup) resets every popup flag, including this one.
	bounty_open = true

# --- Relic Vault (issue #6 Phase 2) ---

var vault_open := false


## Vault panel: 6 special cards (equip one per run) + a fixed trophy row.
## Fixed card count → the layout cannot scroll. Reuses the cipher popup
## shell (mouse visible, E/Esc closes).
func show_vault() -> void:
	if _player == null:
		return
	_build_vault_panel()
	AudioManager.sfx("vault_open")


func _build_vault_panel() -> void:
	var vb := _cipher_panel()
	var title := Label.new()
	title.text = "RELIC VAULT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Equip one special per run — effects apply immediately."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80))
	vb.add_child(sub)
	var cur := str(_player.get("equipped_special"))
	var eq := Label.new()
	if cur == "":
		eq.text = "Equipped: none"
	else:
		var cur_data := SpecialData.get_special(cur)
		eq.text = "Equipped: %s" % (cur_data.display_name if cur_data != null else cur)
	eq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eq.add_theme_font_size_override("font_size", 14)
	eq.add_theme_color_override("font_color", Color(0.60, 1.0, 0.65))
	vb.add_child(eq)
	var grid := GridContainer.new()
	grid.name = "VaultGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for sid in SpecialData.SPECIAL_IDS:
		grid.add_child(_vault_card(sid))
	vb.add_child(grid)
	# Trophy row (visual only): apex trophies earned so far.
	var trow := HBoxContainer.new()
	trow.name = "TrophyRow"
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	trow.add_theme_constant_override("separation", 12)
	var tlabel := Label.new()
	tlabel.text = "TROPHIES"
	tlabel.add_theme_font_size_override("font_size", 13)
	tlabel.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	trow.add_child(tlabel)
	for sid in ["apex_boar_hide", "apex_horror_eye", "apex_warden_sigil"]:
		var t := TextureRect.new()
		var tdata := SpecialData.get_special(sid)
		t.texture = tdata.icon if tdata != null else null
		t.custom_minimum_size = Vector2(40, 40)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if not SpecialData.is_earned(sid):
			t.modulate = Color(0.30, 0.30, 0.35)
		trow.add_child(t)
	vb.add_child(trow)
	var close_hint := Label.new()
	close_hint.text = PromptText.resolve(CLOSE_HINT_TEMPLATE)
	_track_prompt_label(close_hint, CLOSE_HINT_TEMPLATE)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vb.add_child(close_hint)
	_open_cipher_popup(vb.get_parent() as Control)
	vault_open = true


## Compact tracker: one short line per unsettled bounty, hidden when none
## are active (or in warlord mode, where the objective cluster is hidden).
func _refresh_bounty_tracker() -> void:
	if _bounty_tracker == null:
		return
	var txt := ""
	if not _bounty_hide and _player != null:
		var bnode := get_tree().get_first_node_in_group("bounty_system")
		if bnode != null:
			var bounties: Array = bnode.get("bounties")
			var progress: Dictionary = _player.get("bounty_progress")
			txt = BountyUI.tracker_text(bounties, progress)
	_bounty_tracker.text = txt
	_bounty_tracker.visible = not txt.is_empty()


func _vault_card(sid: String) -> Control:
	var data := SpecialData.get_special(sid)
	var earned := SpecialData.is_earned(sid)
	var equipped := str(_player.get("equipped_special")) == sid
	var card := PanelContainer.new()
	card.name = "VaultCard_" + sid
	card.custom_minimum_size = Vector2(230, 176)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.texture = data.icon
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(icon)
	var name_l := Label.new()
	name_l.text = data.display_name
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", Color(1.0, 0.90, 0.60))
	top.add_child(name_l)
	vb.add_child(top)
	var desc := Label.new()
	if earned:
		# Issue #190 (section 2): descriptions are authored
		# with tokens — resolve at the display point, and join
		# the tracked registry (with the template retained) so
		# an open description re-renders across a source flip.
		desc.text = PromptText.resolve(data.description)
		_track_prompt_label(desc, data.description)
		desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88))
	else:
		desc.text = "Locked — " + data.unlock_hint
		desc.add_theme_color_override("font_color", Color(0.60, 0.60, 0.65))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(214, 44)
	desc.add_theme_font_size_override("font_size", 12)
	vb.add_child(desc)
	var btn := Button.new()
	if not earned:
		btn.text = "LOCKED"
		btn.disabled = true
	elif equipped:
		btn.text = "UNEQUIP"
		btn.pressed.connect(_on_vault_unequip)
	else:
		btn.text = "EQUIP"
		btn.pressed.connect(_on_vault_equip.bind(sid))
	vb.add_child(btn)
	if not earned:
		card.modulate = Color(0.62, 0.62, 0.68)
	return card


func _on_vault_equip(sid: String) -> void:
	if _player == null:
		return
	if SpecialData.equip(_player, sid):
		AudioManager.sfx("relic_equip")
		_build_vault_panel()


func _on_vault_unequip() -> void:
	if _player == null:
		return
	SpecialData.unequip(_player)
	AudioManager.sfx("ui_click")
	_build_vault_panel()


# --- Mason's Cipher popups ---

var cipher_popup_open := false
var _cipher_popup: Control = null
var _cipher_grace := 0.0


## Issue #152 (2A-1): pad Back. B (ui_cancel on the pad) invokes the
## SAME close/back handler as the topmost surface's on-screen
## Back/Close — one code path per surface. Keyboard input is not
## routed here at all: E/Esc keep the physical-key paths below,
## byte-identical to before. Priority is topmost-first: a dialog
## owns Back while it is up, then the popups, then the class panel,
## then the character panel, then pause (B = Resume).
## Returns true when a surface consumed the press.
func _pad_back() -> bool:
	if _session_lost_dialog != null and is_instance_valid(_session_lost_dialog):
		return false # Terminal dialog: acknowledge-only, no way back.
	if _quit_dialog != null and is_instance_valid(_quit_dialog) and _quit_dialog.visible:
		# Godot dialogs cancel on Esc natively but never see the pad's
		# B; press the dialog's own Cancel button — the same handler
		# the mouse and Esc both reach.
		(_quit_dialog.get_cancel_button() as Button).pressed.emit()
		return true
	if dest_popup_open and _cipher_grace <= 0.0:
		close_destination_popup()
		return true
	if cipher_popup_open and _cipher_grace <= 0.0:
		close_cipher_popup()
		return true
	var class_panel := get_node_or_null("%ClassPanel") as Control
	if class_panel != null and class_panel.visible:
		_on_class_cancel()
		return true
	if inventory_open:
		close_inventory()
		return true
	if is_paused:
		_on_resume_pressed()
		return true
	return false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("deep_tree_open") \
			and _player != null \
			and not cipher_popup_open \
			and (_tree_surface == null
				or not _tree_surface.visible):
		open_deep_tree(is_paused)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):
		if _pad_back():
			get_viewport().set_input_as_handled()
			return
	if dest_popup_open and _cipher_grace <= 0.0:
		if event is InputEventKey:
			var dk := event as InputEventKey
			if dk.pressed and not dk.echo and (dk.physical_keycode == KEY_E or dk.physical_keycode == KEY_ESCAPE):
				close_destination_popup()
				get_viewport().set_input_as_handled()
				return
	if not cipher_popup_open or _cipher_grace > 0.0:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.physical_keycode == KEY_E or k.physical_keycode == KEY_ESCAPE:
			close_cipher_popup()
			get_viewport().set_input_as_handled()


func _cipher_panel() -> VBoxContainer:
	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	return vb


func _open_cipher_popup(content: Control) -> void:
	close_cipher_popup()
	_cipher_grace = 0.3
	cipher_popup_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(content)
	root.add_child(center)
	_cipher_popup = root
	add_child(root)
	# Issue #152: chain the popup's controls and seed its primary
	# (vendor/dock: first BUY; vault: first enabled card button;
	# lockbox: the entry field; label-only popups chain empty).
	FocusChain.apply(root, null)


func close_cipher_popup() -> void:
	var was_vault := vault_open
	if _cipher_popup != null and is_instance_valid(_cipher_popup):
		_cipher_popup.queue_free()
	_cipher_popup = null
	vendor_open = false
	dock_vendor_open = false
	bounty_open = false
	if was_vault:
		AudioManager.sfx("vault_close")
	vault_open = false
	_vendor_cash_label = null
	_dock_cash_label = null
	cipher_popup_open = false
	if was_vault:
		AudioManager.sfx("vault_close")
	if not is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Issue #191 (section A): the popup closes over gameplay —
	# focus is released.
	_release_focus()


## Destination board popup (issue #29): 2D menu replacing the 3D
## walk-up-and-read interaction. Lists destinations, click to vote.
## Voting/unanimous rules unchanged — only the surface changed.
var dest_popup_open := false
var _dest_popup: Control = null
var _dest_list: VBoxContainer = null
var _dest_station: Node = null
var _dest_destinations: Array = []
var _dest_next_level := 1


func open_destination_popup(station: Node, destinations: Array, next_level: int) -> void:
	close_destination_popup()
	_cipher_grace = 0.3
	dest_popup_open = true
	_dest_station = station
	_dest_destinations = destinations.duplicate()
	_dest_next_level = next_level
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "SELECT DESTINATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(title)
	var hint := Label.new()
	hint.text = PromptText.resolve(DEST_HINT_TEMPLATE)
	_track_prompt_label(hint, DEST_HINT_TEMPLATE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vb.add_child(hint)
	_dest_list = VBoxContainer.new()
	_dest_list.add_theme_constant_override("separation", 4)
	vb.add_child(_dest_list)
	center.add_child(panel)
	root.add_child(center)
	_dest_popup = root
	add_child(root)
	_refresh_destination_list()
	AudioManager.sfx("ui_click")
	# Issue #152 (§2.3): the destination rows are chained Buttons and
	# the first row takes focus — this popup IS the pad route.
	FocusChain.apply(root, null)


func close_destination_popup() -> void:
	if _dest_popup != null and is_instance_valid(_dest_popup):
		_dest_popup.queue_free()
	_dest_popup = null
	_dest_list = null
	_dest_station = null
	dest_popup_open = false
	if not is_paused and not cipher_popup_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Issue #191 (section A): the popup closes over gameplay —
	# focus is released.
	_release_focus()


## Rebuild the destination buttons with current vote tallies.
## Called on open and whenever sync_votes arrives.
func refresh_destination_popup(votes: Dictionary, my_vote: String) -> void:
	if not dest_popup_open:
		return
	_refresh_destination_list(votes, my_vote)


func _refresh_destination_list(votes: Dictionary = {}, my_vote: String = "") -> void:
	if _dest_list == null:
		return
	for c in _dest_list.get_children():
		c.queue_free()
	# Pull live votes from the station if not supplied.
	if votes.is_empty() and _dest_station != null:
		var sv = _dest_station.get("votes")
		if sv is Dictionary:
			votes = sv
	# Count votes per destination.
	var tallies := {}
	for tid in _dest_destinations:
		tallies[tid] = 0
	for peer_id in votes:
		var tid := str(votes[peer_id])
		if tallies.has(tid):
			tallies[tid] = int(tallies[tid]) + 1
	for tid in _dest_destinations:
		var btn := Button.new()
		var row_text := DepartureBoard.row_base_text(tid, _dest_next_level)
		var n := int(tallies.get(tid, 0))
		var label := row_text
		if n > 0:
			label += "   [%d vote%s]" % [n, "" if n == 1 else "s"]
		if tid == my_vote:
			label = ">> " + label
		btn.text = label
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 15)
		if tid == my_vote:
			btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		var theme_id: String = str(tid)
		btn.pressed.connect(_on_destination_chosen.bind(theme_id))
		_dest_list.add_child(btn)
	# Issue #11 Phase 1: ASCEND gold row (fixed 6th row, zero-scroll preserved).
	# Uses the same unanimous-vote flow with special id "ASCEND".
	var ascend_btn := Button.new()
	var asc_count := SaveManager.get_ascension_count()
	var asc_label := "ASCEND — Reset to Cycle 1 (+%d%% XP, %d ascensions)" % [
		int((SaveManager.get_ascension_xp_mult() - 1.0) * 100.0), asc_count]
	var asc_votes := 0
	for peer_id in votes:
		if str(votes[peer_id]) == "ASCEND":
			asc_votes += 1
	if asc_votes > 0:
		asc_label += "   [%d vote%s]" % [asc_votes, "" if asc_votes == 1 else "s"]
	if my_vote == "ASCEND":
		asc_label = ">> " + asc_label
	ascend_btn.text = asc_label
	ascend_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	ascend_btn.add_theme_font_size_override("font_size", 15)
	ascend_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	ascend_btn.pressed.connect(_on_destination_chosen.bind("ASCEND"))
	_dest_list.add_child(ascend_btn)
	# Issue #152: rows were just rebuilt (freed + recreated) — re-chain
	# and re-seed if the focused row died in the rebuild.
	if dest_popup_open and _dest_popup != null:
		FocusChain.apply(_dest_popup, null)


func _on_destination_chosen(theme_id: String) -> void:
	if _dest_station == null or not is_instance_valid(_dest_station):
		return
	# Issue #11 Phase 1: Solo ASCEND gets a confirm modal.
	if theme_id == "ASCEND":
		var players := get_tree().get_nodes_in_group("players")
		if players.size() <= 1:
			_show_quit_confirm(
				"Reset this run to Cycle 1? You keep nothing but +5% XP forever.",
				func() -> void: _dest_station.rpc("cast_vote", "ASCEND"))
			return
	_dest_station.rpc("cast_vote", theme_id)
	AudioManager.sfx("ui_click")
	# Refresh to show my vote highlight; the server sync_votes will
	# refresh again with the authoritative tallies.
	_refresh_destination_list()


## Poem popup: verse + cipher + shift hint. Game keeps running.
func show_poem_popup(idx: int) -> void:
	var poems := CipherPoems.POEMS
	if idx < 0 or idx >= poems.size():
		return
	var p: Dictionary = poems[idx]
	var vb := _cipher_panel()
	var title := Label.new()
	title.text = "Old Note — fragment %d/8" % (idx + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(title)
	for line in p["verse"]:
		var l := Label.new()
		l.text = str(line)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
		vb.add_child(l)
	var cipher := Label.new()
	cipher.text = str(p["cipher"])
	cipher.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cipher.add_theme_font_size_override("font_size", 28)
	cipher.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vb.add_child(cipher)
	var hint := Label.new()
	hint.text = "(the mason shifts his letters forward — count back %d)" % int(p["shift"])
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vb.add_child(hint)
	var close_hint := Label.new()
	close_hint.text = PromptText.resolve(CLOSE_HINT_TEMPLATE)
	_track_prompt_label(close_hint, CLOSE_HINT_TEMPLATE)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vb.add_child(close_hint)
	AudioManager.sfx("pickup")
	_open_cipher_popup(vb.get_parent() as Control)


# --- Departure board (Train Station Phase 2) ---

func flash_damage() -> void:
	var tween := create_tween()
	tween.tween_property(%DamageFlash, "modulate:a", 0.35, 0.05)
	tween.tween_property(%DamageFlash, "modulate:a", 0.0, 0.3)


func flash_dash() -> void:
	# Brief cool streak across the screen on dash. Own rect (Jesse 2026-10-10):
	# sharing DamageFlash let hit flashes hijack the dash fade and vice versa.
	%DashFlash.modulate = Color(1, 1, 1, 0.22)
	var tween := create_tween()
	tween.tween_property(%DashFlash, "modulate:a", 0.0, 0.25)


## Issue #152: the pause surface + its focus primary, resolved
## null-safely — bare-script harnesses build pause UI without the
## tscn's unique-name nodes, and FocusChain.apply accepts nulls.
func _pause_surface() -> Control:
	return get_node_or_null("%PausePanel")


func _pause_primary() -> Control:
	# ResumeButton carries no unique-name flag in hud.tscn (the pause
	# builder works from stored refs for the same reason) — resolve
	# by path: the rebuilt PauseMain layout first, the raw tscn
	# layout as fallback.
	var b := get_node_or_null("PausePanel/PauseMain/PauseActions/ResumeButton")
	if b == null:
		b = get_node_or_null("PausePanel/PauseScroll/PauseVBox/ResumeButton")
	return b


func show_pause() -> void:
	is_paused = true
	refresh_stats()
	%PausePanel.visible = true
	# Default to the Stats tab when the menu opens.
	if _pause_tab_btns.size() == 5:
		_on_pause_tab_pressed(0)
	# Hide the top-right wave cluster so it doesn't peek out behind the panel.
	%TopRight.visible = false
	_layout_pause()
	# Class switching is solo-only.
	if _class_btn != null:
		_class_btn.visible = multiplayer.get_peers().size() == 0
	# Save & Quit label depends on host/client role.
	if _save_quit_btn != null:
		if multiplayer.get_peers().size() == 0:
			_save_quit_btn.text = "Save & Quit to Menu"
		elif multiplayer.is_server():
			_save_quit_btn.text = "Save & Quit (saves run)"
		else:
			_save_quit_btn.text = "Disconnect (host holds the save)"
	# Issue #152: chain the pause surface; primary is Resume.
	FocusChain.apply(_pause_surface(), _pause_primary())


## Issue #191 (section A): release focus on a close over
## gameplay. Null-safe: suite fixtures (and teardown paths)
## call the close functions with the HUD out of tree.
func _release_focus() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.gui_release_focus()


func hide_pause() -> void:
	is_paused = false
	%PausePanel.visible = false
	%ClassPanel.visible = false
	%TopRight.visible = true
	# Issue #191 (section A): pause closes over GAMEPLAY —
	# focus is released, never stranded in the hidden panel.
	_release_focus()


func _on_resume_pressed() -> void:
	hide_pause()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_quit_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


## Issue #133: NetworkManager reports the session ended underneath a
## guest (host process died or left mid-run). Supersedes whatever the
## HUD is showing — pause, inventory, downed and death surfaces all
## close, the same way show_downed/show_death_screen take over — then
## an honest notice whose only action runs the pause menu's own Quit
## path (_on_quit_pressed): shared leave_lobby() teardown and scene
## return, so the abrupt exit and the graceful exit are one code path.
## Issue #138 Phase 2: a train boarding named a baked-scene hash
## this build doesn't ship — the hop was refused before the scene
## changed. Same honest-exit shape as session loss: explain, and
## the only way out is the menu.
func _on_baked_version_mismatch(message: String) -> void:
	if _session_lost_dialog != null:
		return
	hide_pause()
	hide_death_screen()
	hide_downed()
	force_close_inventory()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dialog := ConfirmationDialog.new()
	dialog.title = "Version Mismatch"
	dialog.dialog_text = message + "\nThis run cannot continue on your build."
	dialog.ok_button_text = "Return to Menu"
	dialog.get_cancel_button().hide()
	add_child(dialog)
	_session_lost_dialog = dialog
	dialog.confirmed.connect(_on_quit_pressed)
	dialog.popup_centered()


func _on_session_lost() -> void:
	if _session_lost_dialog != null:
		return
	hide_pause()
	hide_death_screen()
	hide_downed()
	force_close_inventory()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var dialog := ConfirmationDialog.new()
	dialog.title = "Connection Lost"
	dialog.dialog_text = "The host has ended the session.\nThe run is over."
	dialog.ok_button_text = "Return to Menu"
	# No cancel: there is no session to return to.
	dialog.get_cancel_button().hide()
	add_child(dialog)
	_session_lost_dialog = dialog
	dialog.confirmed.connect(_on_quit_pressed)
	dialog.popup_centered()


## Issue #111 minor 3: the run state a pause-save writes, sampled ONCE
## from the same sources the save has always used. Returns {} when
## there is nothing to save from here (neither station nor dungeon).
## _on_save_quit_pressed writes exactly this dict's values and pushes
## it into the HUD display via _apply_pause_save_snapshot — one source
## of truth at save time, so the HUD's seed/level and the save card
## can't disagree about what was saved.
func _capture_pause_save_snapshot() -> Dictionary:
	var snap := {"theme_id": "village", "level_number": 1, "seed": 0,
		"at_station": false, "wave": 0}
	var station := get_tree().get_first_node_in_group("station")
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	# Jesse 2026-10-11: use the current scene to decide, not just node
	# existence — a stale station node can linger after scene changes.
	var scene_path := str(get_tree().current_scene.scene_file_path) if get_tree().current_scene != null else ""
	var in_station := scene_path.contains("station") or (station != null and dungeon == null)
	if in_station and station != null:
		snap["at_station"] = true
		var nl := Station.next_level_number
		# board_destinations() swaps warlord for the APEX ARENA on apex
		# cycles (issue #5) so the saved next theme agrees with the board.
		var dests := Dungeon.board_destinations(nl)
		snap["theme_id"] = dests[(nl - 1) % dests.size()]
		snap["level_number"] = nl
		snap["seed"] = int(station.get("departure_seed"))
	elif dungeon != null:
		snap["theme_id"] = str(dungeon.get("theme").get("theme_id")) if dungeon.get("theme") != null else "village"
		snap["level_number"] = int(dungeon.get("level_number"))
		snap["seed"] = Dungeon.next_seed
		# Jesse 2026-10-11: save the wave so continuing resumes where you were.
		var w := int(dungeon.get("wave"))
		# If mid-wave (active), step back one so the wave restarts fresh.
		if str(dungeon.get("wave_state")) == "1":  # WaveState.ACTIVE
			w = maxi(0, w - 1)
		snap["wave"] = w
	else:
		return {}
	return snap


## The seed/level the HUD currently displays for the run. Refreshed
## ONLY from the pause-save snapshot (issue #111 minor 3) so the
## display always describes the state the last pause-save wrote.
var displayed_theme_id := ""
var displayed_level := 0
var displayed_seed := 0


## Issue #111 minor 3: push a pause-save snapshot into the HUD display.
## The wave cluster (the visible level display in the dungeon) is
## re-derived from the snapshot's level/theme, keeping the live wave
## fields, so what the player sees matches what the save wrote.
func _apply_pause_save_snapshot(snap: Dictionary) -> void:
	displayed_theme_id = str(snap.get("theme_id", ""))
	displayed_level = int(snap.get("level_number", 0))
	displayed_seed = int(snap.get("seed", 0))
	if bool(snap.get("at_station", false)):
		return
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return
	var info: Variant = dungeon.get("wave_info")
	if info is Dictionary and not (info as Dictionary).is_empty():
		var merged: Dictionary = (info as Dictionary).duplicate()
		merged["level"] = displayed_level
		merged["theme_id"] = displayed_theme_id
		set_wave(merged)


## Save the current run as a save point, then quit to the menu.
## Host in multiplayer: saves the full roster. Client: just disconnects.
## Station-aware: quitting from the pit-stop saves the NEXT level, exactly
## as if the train had departed. The at_station flag ensures continuing
## puts you back at the station (shops/healing), not straight into the
## next dungeon level.
func _on_save_quit_pressed() -> void:
	if _player == null:
		_on_quit_pressed()
		return
	# Issue #111 minor 3: sample the run state ONCE (see
	# _capture_pause_save_snapshot) — the save below writes exactly
	# the snapshot, and the HUD display is refreshed from that same
	# snapshot, so the two can never describe different levels.
	var snap := _capture_pause_save_snapshot()
	if snap.is_empty():
		_on_quit_pressed()
		return
	_apply_pause_save_snapshot(snap)
	var theme_id := str(snap["theme_id"])
	var level_number := int(snap["level_number"])
	var level_seed := int(snap["seed"])
	var at_station := bool(snap["at_station"])
	var wave_number := int(snap["wave"])
	if multiplayer.get_peers().size() > 0 and not multiplayer.is_server():
		# Client: warn that only the host's save persists.
		_show_quit_confirm("Disconnect? Only the host's save will persist.", _on_quit_pressed)
		return
	if NetworkManager.active_run_mode == SaveManager.MODE_MP and NetworkManager.is_host:
		# Host: multiplayer save with roster collection (async, then quit).
		# Issue #70: LAN has no saves — skip straight to quit.
		if NetworkManager.transport != NetworkManager.Transport.LAN:
			var station := get_tree().get_first_node_in_group("station")
			var dungeon := get_tree().get_first_node_in_group("dungeon")
			var saver = station if at_station and station != null else dungeon
			saver.save_multiplayer_run(theme_id, level_number, level_seed)
			# save_multiplayer_run waits 3s for clients; quit after.
			await get_tree().create_timer(3.5).timeout
		else:
			_on_quit_pressed()
			return
	else:
		# Issue #111 PF Phase 2: loaded-dict-first (the _save_base
		# pattern) — unknown top-level keys survive a pause-save.
		var solo_base: Dictionary = SaveManager.load_run(
			SaveManager.MODE_SOLO, NetworkManager.active_run_slot).duplicate(true)
		solo_base["theme_id"] = theme_id
		solo_base["level_number"] = level_number
		solo_base["seed"] = level_seed
		solo_base["at_station"] = at_station
		solo_base["wave"] = wave_number
		solo_base["class_id"] = _player.class_id
		solo_base["player_state"] = _player.get_state()
		SaveManager.save_run(solo_base, SaveManager.MODE_SOLO,
			NetworkManager.active_run_slot)
	_on_quit_pressed()


## Show a confirmation dialog with a custom message and confirm callback.
func _show_quit_confirm(message: String, on_confirm: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = message
	dialog.ok_button_text = "Confirm"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.confirmed.connect(on_confirm)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	# Issue #152: track the dialog while it is up so pad B can press
	# its Cancel (see _pad_back); forget it as soon as it closes.
	_quit_dialog = dialog
	dialog.canceled.connect(func() -> void: _quit_dialog = null)
	dialog.confirmed.connect(func() -> void: _quit_dialog = null)
	dialog.popup_centered()


func _on_class_pressed() -> void:
	%ClassPanel.visible = true
	# Issue #152: chain the class panel; primary is the first class.
	FocusChain.apply(%ClassPanel, %ClassPanel.get_node("ClassVBox/WarriorBtn"))


func _on_class_cancel() -> void:
	%ClassPanel.visible = false
	# Issue #191 (section A): the class panel is menu over
	# menu — its close re-applies focus into the pause surface.
	FocusChain.apply(_pause_surface(), _pause_primary())


func _on_class_chosen(new_class: String) -> void:
	%ClassPanel.visible = false
	# Issue #191 (section A): menu over menu — re-apply into pause.
	FocusChain.apply(_pause_surface(), _pause_primary())
	var player := _my_player()
	if player == null:
		return
	if player.get("class_id") == new_class:
		toast("Already a %s!" % new_class.capitalize())
		return
	hide_pause()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.call("switch_class", new_class)


func _my_player() -> Node:
	var me := multiplayer.get_unique_id()
	for n in get_tree().get_nodes_in_group("players"):
		if n.get_multiplayer_authority() == me:
			return n
	return null


# --- Specialization ---

## Build the specialization list: one row per unlocked skill.
func _refresh_spec_list() -> void:
	for child in %SpecList.get_children():
		child.queue_free()
	if _player == null:
		return
	var cls := str(_player.get("class_id"))
	var plevel := int(_player.get("level"))
	var spec_locked := plevel < Player.SPECIALIZATION_UNLOCK_LEVEL
	if spec_locked:
		var hint := Label.new()
		hint.text = "Specialization unlocks at level %d (currently %d)." % [Player.SPECIALIZATION_UNLOCK_LEVEL, plevel]
		hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%SpecList.add_child(hint)
	for a in Player.class_abilities(cls):
		var sid := str(a["id"])
		if sid == "holy_light":
			continue  # special track, not in families
		if int(a["unlock"]) > plevel:
			continue  # not unlocked yet
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		var aff := float(_player.get("affinity").get(sid, 0.0))
		var fam := Player.family_of(sid)
		lbl.text = "%s [%s] — %.0f" % [str(a["name"]), fam.capitalize(), aff]
		if str(_player.get("specialization")) == sid:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		row.add_child(lbl)
		var btn := Button.new()
		if str(_player.get("specialization")) == sid:
			btn.text = "Respec"
			btn.pressed.connect(_on_respec_pressed)
		else:
			btn.text = "Specialize"
			btn.pressed.connect(_on_specialize_pressed.bind(sid))
			if spec_locked:
				btn.disabled = true
				btn.tooltip_text = "Unlocks at level %d" % Player.SPECIALIZATION_UNLOCK_LEVEL
		row.add_child(btn)
		%SpecList.add_child(row)
	# Issue #215: the tree lives on its own canvas
	# surface now (the #206 rows are retired, section
	# 7.3 of the node-UI spec); the tab carries the
	# open button.
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	var tbtn := Button.new()
	tbtn.text = "Open the Deep Tree"
	tbtn.pressed.connect(_on_open_tree_pressed)
	trow.add_child(tbtn)
	%SpecList.add_child(trow)
	# Issue #217 (Jesse's order): the direct-key tip,
	# styled like the unlock hint above.
	var tip := Label.new()
	tip.text = "Tip: press N to open the Deep Tree."
	tip.add_theme_color_override("font_color",
		Color(0.7, 0.7, 0.75))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%SpecList.add_child(tip)
	# Issue #152: spec rows are dynamic — re-chain while paused.
	if is_paused:
		FocusChain.apply(_pause_surface(), _pause_primary())


## Issue #215: the Deep Tree canvas surface - hosted
## here, above the pause surface (node-UI spec 7.1).
## Opened from the Specialization tab's button or the
## deep_tree_open action; pausing is the pause menu's
## own (is_paused; multiplayer semantics unchanged).
func _on_open_tree_pressed() -> void:
	open_deep_tree(true)


func open_deep_tree(from_pause: bool) -> void:
	if _player == null:
		return
	if _tree_surface != null and _tree_surface.visible:
		return
	_tree_from_pause = from_pause or is_paused
	if not is_paused:
		show_pause()
	if _tree_surface == null:
		_tree_surface = DeepTreeCanvas.new()
		_tree_surface.surface_closed.connect(
			_on_tree_surface_closed)
		_tree_surface.panel_focus_entered.connect(
			_on_tree_panel_focus)
		add_child(_tree_surface)
	_tree_surface.open_for(_player,
		Player.class_abilities(str(_player.get(
			"class_id"))))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.sfx("ui_click")


func _on_tree_surface_closed() -> void:
	if not _tree_from_pause:
		hide_pause()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		FocusChain.apply(_pause_surface(),
			_pause_primary())
	_tree_from_pause = false


func _on_tree_panel_focus() -> void:
	if _tree_surface != null:
		FocusChain.apply(_tree_surface.panel_root(),
			_tree_surface.panel_primary())


## Issue #215 (spec 5.3): the player's purchase-denial
## forward lands here; the surface shows the reason
## verbatim. Factored as a plain receiver so the suite
## can drive it directly (the #135 discipline).
func tree_denial_received(node_id: int,
		reason: String) -> void:
	AudioManager.sfx("ui_error")
	if _tree_surface != null and _tree_surface.visible:
		_tree_surface.show_denial(node_id, reason)


func _on_specialize_pressed(skill_id: String) -> void:
	if _player == null:
		return
	_player.call("specialize", skill_id)
	_refresh_spec_list()
	_refresh_family_panel()
	_refresh_collection_log()
	AudioManager.sfx("ui_click")


func _on_respec_pressed() -> void:
	if _player == null:
		return
	_player.call("respec")
	_refresh_spec_list()
	_refresh_family_panel()
	_refresh_collection_log()
	AudioManager.sfx("ui_click")


# --- Stat points ---

## Issue #184 (section 6): the ATK SPD display form. The x
## form ships as the FLAGGED PROVISIONAL (tracker 34d stays
## Jesse's call — the HUD already speaks x natively); BOTH
## forms live behind this one switch and the single formatter
## below, so the ruling lands as a one-line change.
const ATK_SPD_DISPLAY_X := true


func atk_spd_text(mult: float) -> String:
	if ATK_SPD_DISPLAY_X:
		return "×%.2f" % mult
	return "+%d%%" % int(roundf((mult - 1.0) * 100.0))


func refresh_stats() -> void:
	if _player == null:
		return
	%StatPointsLabel.text = "Stat points: %d" % _player.stat_points
	%DmgVal.text = "+%d dmg" % int(_player.bonus_damage)
	%HpVal.text = "+%d hp" % int(_player.bonus_health)
	%SpdVal.text = "+%.1f spd" % _player.bonus_speed
	%AuraVal.text = "+%d aura" % int(_player.bonus_aura)
	%AtkSpdVal.text = atk_spd_text(_player.atk_spd_mult())
	var is_mage := str(_player.get("class_id")) == "mage"
	%AuraRow.visible = is_mage
	_refresh_spec_list()
	_refresh_family_panel()
	_refresh_collection_log()
	var can: bool = _player.stat_points > 0
	%DmgPlus.disabled = not can
	%HpPlus.disabled = not can
	%SpdPlus.disabled = not can
	%AuraPlus.disabled = not can
	%AtkSpdPlus.disabled = not can
	# Issue #156: spending the last stat point disables all the
	# +/- buttons at once — including, typically, the one the pad
	# just pressed. Rescue re-seeds focus off the dead button (a
	# no-op while focus lives elsewhere in the pause chain).
	FocusChain.rescue(_pause_surface(), _pause_primary())


# --- Family panel & collection log (Phase 5) ---

## Refresh the pause-menu family panel: current family's progress, traits, signature.
func _refresh_family_panel() -> void:
	for child in %FamilyPanel.get_children():
		child.queue_free()
	if _player == null:
		return
	var spec := String(_player.get("specialization"))
	if spec == "":
		var lbl := Label.new()
		lbl.text = "Specialize in a skill to begin a family collection."
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%FamilyPanel.add_child(lbl)
		return
	var fid := Player.family_of(spec)
	if fid == "":
		return
	var fams := Player.families()
	var fam: Dictionary = fams[fid]
	var aff := float(_player.get("affinity").get(spec, 0.0))
	var coll: Dictionary = _player.get("family_collection").get(fid, {"traits": [], "signature": false})
	# Family name + affinity bar.
	var title := Label.new()
	title.text = "%s Family — %.0f/100" % [String(fam["name"]), aff]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%FamilyPanel.add_child(title)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = aff
	bar.custom_minimum_size = Vector2(220, 10)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.18, 1.0)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.8, 0.65, 0.25, 1.0)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	%FamilyPanel.add_child(bar)
	# Milestone pips with trait names (compact: no descs, they show in tooltips).
	var earned: Array = coll.get("traits", [])
	for m in [25, 50, 75]:
		var tdata: Dictionary = fam["traits"][m]
		var tid := String(tdata["id"])
		var row := Label.new()
		if tid in earned:
			row.text = "◆%d %s" % [m, String(tdata["name"])]
			row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		else:
			row.text = "◇%d %s" % [m, String(tdata["name"])]
			row.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		row.tooltip_text = String(tdata["desc"])
		row.add_theme_font_size_override("font_size", 11)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%FamilyPanel.add_child(row)
	# Signature: name or silhouette.
	var sig: Dictionary = fam["signature"]
	var sig_row := Label.new()
	if bool(coll.get("signature", false)):
		sig_row.text = "◆100 %s" % String(sig["name"])
		sig_row.tooltip_text = String(sig["desc"])
		sig_row.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
	else:
		sig_row.text = "◇100 ???"
		sig_row.tooltip_text = "Reach 100 affinity"
		sig_row.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	sig_row.add_theme_font_size_override("font_size", 11)
	sig_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	%FamilyPanel.add_child(sig_row)


## Refresh the collection log: two-column compact grid of all families.
## Issue #55: full-progress state must fit 1080p with zero scroll — compact
## fonts and tight separation throughout.
func _refresh_collection_log() -> void:
	for child in %CollectionLog.get_children():
		child.queue_free()
	if _player == null:
		return
	var fams := Player.families()
	var coll_all: Dictionary = _player.get("family_collection")
	var grid := HBoxContainer.new()
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 12)
	%CollectionLog.add_child(grid)
	var cols: Array = []
	for i in 2:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		grid.add_child(vb)
		cols.append(vb)
	var idx := 0
	for fid in fams:
		var fam: Dictionary = fams[fid]
		var coll: Dictionary = coll_all.get(fid, {"traits": [], "signature": false})
		var earned: Array = coll.get("traits", [])
		var sig_done := bool(coll.get("signature", false))
		var row := Label.new()
		var txt := "%s: " % String(fam["name"])
		if earned.is_empty() and not sig_done:
			txt += "—"
			row.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
		else:
			txt += "%d/3%s" % [earned.size(), " +★" if sig_done else ""]
			row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if sig_done else Color(0.8, 0.75, 0.55))
		row.text = txt
		row.tooltip_text = _collection_tooltip(fam, earned, sig_done)
		row.add_theme_font_size_override("font_size", 9)
		(cols[idx % 2] as VBoxContainer).add_child(row)
		idx += 1
	_refresh_cipher_section()
	_refresh_combo_codex()
	_refresh_trophy_section()
	_refresh_dock_trophy_section()
	_hide_redundant_collection_headers()


## Issue #37 reopened: hide redundant Collection headers when the log has
## real content. Saves 3 rows (~54px) in the full-progress state.
func _hide_redundant_collection_headers() -> void:
	if _pause_tab != 2:
		return
	# Has content if any section has rows beyond the family grid.
	var has_content := %CollectionLog.get_child_count() > 2
	var scroll := %PausePanel.get_node("PauseMain/PauseScroll") as ScrollContainer
	if scroll == null:
		return
	var vbox := scroll.get_node("PauseVBox") as VBoxContainer
	if vbox == null:
		return
	for nn in ["FamilyLabel", "FamilyPanel", "CollectionLabel"]:
		var ctl := vbox.get_node_or_null(nn) as Control
		if ctl != null:
			ctl.visible = not has_content


## Apex trophies (issue #5 Phase 3): 3 fixed rows, one per apex boss.
## Earned rows show the relic icon in gold; locked rows show ??? + hint.
## Issue #55: compact (20px icons, font 10) so the full Collection fits 1080p.
func _refresh_trophy_section() -> void:
	var trophies: Array = SaveManager.get_apex_trophies()
	var header := Label.new()
	header.text = "Apex Trophies — %d/3" % trophies.size()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	%CollectionLog.add_child(header)
	for apex_id in ["apex_boar", "apex_warden", "apex_horror"]:
		var earned: bool = apex_id in trophies
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		%CollectionLog.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(16, 16)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var sp := SpecialData.get_special(SpecialData.apex_special_for_boss(apex_id))
		if sp != null and sp.icon != null:
			icon.texture = sp.icon
		if not earned:
			icon.modulate = Color(0.25, 0.25, 0.3)
		row.add_child(icon)
		var label := Label.new()
		if earned:
			label.text = "%s — %s" % [sp.display_name, sp.effect_summary]
			label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		else:
			label.text = "??? — %s" % sp.unlock_hint
			label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		label.add_theme_font_size_override("font_size", 9)
		row.add_child(label)



## Dock trophies (issue #102 Phase 3): misty docks trophies — the golden
## crop plus the legendary fish (Phase 5). Issue #55: compact, same
## pattern as the apex trophy rows (earned = gold row, locked = ??? + hint).
func _refresh_dock_trophy_section() -> void:
	var trophies: Array = SaveManager.get_dock_trophies()
	var header := Label.new()
	header.text = "Dock Trophies — %d/2" % mini(trophies.size(), 2)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	%CollectionLog.add_child(header)
	var rows := [
		{"id": "golden_crop", "name": "Golden Gourd", "hint": "Harvest the legendary golden crop"},
		{"id": "legendary_fish", "name": "Legendary Fish", "hint": "Land the legendary fish"},
	]
	for r in rows:
		var earned: bool = str(r["id"]) in trophies
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		%CollectionLog.add_child(row)
		var label := Label.new()
		if earned:
			label.text = "%s — misty docks trophy" % str(r["name"])
			label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		else:
			label.text = "??? — %s" % str(r["hint"])
			label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		label.add_theme_font_size_override("font_size", 9)
		row.add_child(label)



## Architect Cipher section: collected fragments as raw cipher + shift hint
## (never the solution). Issue #55: compact fonts for 1080p zero-scroll fit.
## (never the solution). Compact, at most 8 short rows.
func _refresh_cipher_section() -> void:
	var frags: Array = SaveManager.get_cipher_fragments()
	var header := Label.new()
	header.text = "Architect Cipher — %d/8" % frags.size()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	%CollectionLog.add_child(header)
	var sorted := frags.duplicate()
	sorted.sort()
	for i in sorted:
		var idx := int(i)
		if idx < 0 or idx >= CipherPoems.POEMS.size():
			continue
		var p: Dictionary = CipherPoems.POEMS[idx]
		var row := Label.new()
		row.text = "%s. %s — the verse speaks of %s" % [
			CipherPoems.roman(idx), str(p["cipher"]), CipherPoems.shift_word(int(p["shift"]))]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 9)
		row.add_theme_color_override("font_color", Color(0.8, 0.75, 0.55))
		%CollectionLog.add_child(row)


## Combo Finishers codex (issue #8 Phase 2): 5 fixed rows. Undiscovered
## show "???" + hint, discovered show name + trigger. Issue #55: compact.
func _refresh_combo_codex() -> void:
	var found: Array = SaveManager.get_combos_discovered()
	var header := Label.new()
	header.text = "Combo Finishers — %d/5" % found.size()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	%CollectionLog.add_child(header)
	for f in Combo.COMBO_FINISHERS:
		var fid := str(f["id"])
		var row := Label.new()
		if fid in found:
			row.text = "◆ %s — %s" % [str(f["name"]), str(f["trigger_desc"])]
			row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		else:
			row.text = "◇ ??? — %s" % str(f["hint"])
			row.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 9)
		%CollectionLog.add_child(row)


## Tooltip detail for a collection log row.
func _collection_tooltip(fam: Dictionary, earned: Array, sig_done: bool) -> String:
	var parts: Array = []
	for tid in earned:
		parts.append(tid)
	if sig_done:
		parts.append(String(fam["signature"]["id"]))
	else:
		parts.append("???")
	return "%s: %s" % [String(fam["name"]), ", ".join(parts)]


func _on_next_wave_pressed() -> void:
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if dungeons.is_empty():
		return
	dungeons[0].rpc("request_next_wave")


## Supermarket: update gate-progress display (per-visit earnings vs goal).
func set_market_cash(earned: int, goal: int) -> void:
	%MarketLabel.text = "Earned: $%d / $%d" % [earned, goal]


func _on_stat_pressed(stat: String) -> void:
	if _player != null and _player.spend_point(stat):
		refresh_stats()


# --- Waves ---

func set_wave(info: Dictionary) -> void:
	var state := int(info.get("state", 0))
	var level := int(info.get("level", 1))
	# Issue #201 (census site 12): the shared loop-index read —
	# during the Act 1 stretch the suffix never appears.
	var cycle := Dungeon.loop_index_for(level)
	var cycle_str := " · Cycle %d" % (cycle + 1) if cycle > 0 else ""
	# Warlord mode: hide the wave cluster entirely (RTS uses its own HUD).
	var is_warlord := str(info.get("theme_id", "")) == "warlord"
	_bounty_hide = is_warlord
	%WaveLabel.visible = not is_warlord
	%WaveStatus.visible = not is_warlord
	%NextWaveButton.visible = false
	if is_warlord:
		%MarketLabel.visible = false
		return
	var wave_num := int(info.get("wave", 0))
	var wave_total := int(info.get("total", 5))
	if wave_total > 0:
		%WaveLabel.text = "Lv %d · %s%s · Wave %d/%d" % [level, str(info.get("theme_name", "")), cycle_str, wave_num, wave_total]
	else:
		# Endless theme (Jesse 2026-10-15): no final wave to count toward.
		%WaveLabel.text = "Lv %d · %s%s · Wave %d" % [level, str(info.get("theme_name", "")), cycle_str, wave_num]
	# Supermarket mode: show cash instead of waves.
	var is_market := str(info.get("theme_id", "")) == "supermarket"
	%MarketLabel.visible = is_market
	if is_market:
		%WaveLabel.text = "Lv %d · %s%s" % [level, str(info.get("theme_name", "")), cycle_str]
		%WaveStatus.text = "Walk through CHECKOUT to sell loot and unlock the gate!"
		%NextWaveButton.visible = false
		return
	# Host-only Next Wave button during intermission. State 2 with
	# total 0 is an endless theme's CLEARED state (Jesse 2026-10-15):
	# the host may continue past the final wave there too.
	var is_host := multiplayer.is_server()
	# Issue #62: hide the wave button during boarding — it does nothing there.
	%NextWaveButton.visible = is_host and (state == 0 or (state == 2 and int(info.get("total", 5)) <= 0)) and not _boarding_active
	match state:
		0: # intermission
			# Issue #60: the "Press R to begin wave" hint is redundant with the
			# "START NEXT WAVE (R)" button for the host. Hide the hint text
			# when the button is visible; clients still see "Waiting for host..."
			if is_host:
				%WaveStatus.visible = false
			else:
				%WaveStatus.visible = not is_warlord
				%WaveStatus.text = "Waiting for host..."
		1: # active
			%WaveStatus.text = "Mobs left: %d" % int(info.get("mobs_left", 0))
		_:
			var kn := int(info.get("keys_needed", 0))
			if kn > 0:
				%WaveStatus.text = "Keys: %d/%d" % [int(info.get("keys_found", 0)), kn]
			else:
				%WaveStatus.text = "Cleared!"


func announce(text: String, tint: Color = Color(1.0, 1.0, 1.0)) -> void:
	# Issue #190 (section 2): announces render on the VIEWER's
	# machine — a host-authored string carrying tokens shows
	# each player their own bindings.
	%AnnounceLabel.text = PromptText.resolve(text)
	%AnnounceLabel.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	%AnnounceLabel.scale = Vector2(1.25, 1.25)
	# Issue #23/#46/#52/#59/#57: shrink-to-fit so wide banners don't overflow.
	# Pixel-accurate: measure the text width at 72pt, scale down to fit.
	# Issue #59: budget for the 1280x720 design resolution.
	# Issue #57: conservative 1000px budget (accounts for 1.25x pop scale
	# and font measurement inaccuracies); floor at 12pt.
	var font_size := 72
	var font: Font = %AnnounceLabel.get_theme_font("font")
	if font != null:
		var w72 := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
		if w72 > 1000.0:
			font_size = maxi(12, int(72.0 * 1000.0 / w72))
	elif text.length() > 15:
		# Fallback if font not available: aggressive char-count shrink.
		font_size = maxi(12, int(72.0 * 15.0 / text.length()))
	%AnnounceLabel.add_theme_font_size_override("font_size", font_size)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(%AnnounceLabel, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.tween_property(%AnnounceLabel, "scale", Vector2.ONE, 0.4)


## Full-screen fade (Phase 5: the train ride). Lazy overlay; idempotent.
func _fade_rect() -> ColorRect:
	var r := get_node_or_null("FadeRect") as ColorRect
	if r == null:
		r = ColorRect.new()
		r.name = "FadeRect"
		r.color = Color(0, 0, 0, 0)
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
	return r


func fade_out(dur: float) -> void:
	var r := _fade_rect()
	r.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(r, "color:a", 1.0, dur)


func fade_in(dur: float) -> void:
	var r := _fade_rect()
	r.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(r, "color:a", 0.0, dur)


# --- Train station (Phase 1) ---

## Top-center gold countdown, driven by the server's station_timer_sync.
func show_station_timer(sec: float) -> void:
	var s := int(ceil(maxf(sec, 0.0)))
	%StationTimerLabel.text = "TRAIN DEPARTS IN %d:%02d — BOARD!" % [s / 60, s % 60]
	%StationTimerLabel.visible = true


func hide_station_timer() -> void:
	%StationTimerLabel.visible = false
	_boarding_active = false


## Boarding status (issue #93 Phase 3): the vote resolved, the lobby doors
## are open, and the party is waiting on the depart lever. Reuses the
## station timer label — no new UI chrome. Hide via hide_station_timer.
func show_now_boarding(theme_id: String) -> void:
	%StationTimerLabel.text = "NOW BOARDING: %s — pull the depart lever" % theme_id.to_upper()
	%StationTimerLabel.visible = true
	# Issue #62: boarding started — hide the wave button immediately.
	_boarding_active = true
	%NextWaveButton.visible = false


## Ride status (issue #3 Phase 3): destination + arrival countdown. Reuses
## the station timer label — no new UI chrome. Hide via hide_station_timer.
func show_ride_status(title: String, sec: float) -> void:
	var s := int(ceil(maxf(sec, 0.0)))
	%StationTimerLabel.text = "%s — %d:%02d" % [title, s / 60, s % 60]
	%StationTimerLabel.visible = true


# --- Downed / revive (co-op) ---

func show_downed(seconds: float) -> void:
	force_close_inventory()
	%DownedLabel.visible = true
	update_downed(seconds)


func update_downed(seconds: float) -> void:
	%DownedLabel.text = "DOWNED\nTeammate revive or bleed-out in %ds" % int(ceil(seconds))


func hide_downed() -> void:
	%DownedLabel.visible = false


func show_revive_progress(frac: float) -> void:
	%ReviveBar.visible = true
	%ReviveBar.value = frac


func hide_revive_progress() -> void:
	%ReviveBar.visible = false


# --- Death screen (solo) ---

func show_death_screen(stats: Dictionary) -> void:
	hide_pause()
	force_close_inventory()
	var cause := str(stats.get("cause", ""))
	if cause.is_empty():
		%DeathCauseLabel.text = "The dungeon claimed you."
	else:
		%DeathCauseLabel.text = "Slain by %s" % cause
	var secs := int(stats.get("time_sec", 0))
	%DeathStatsLabel.text = "Time survived: %s\nKills: %d\nLevel reached: %d\nCycle reached: %d\nDamage dealt: %d" % [
		_fmt_run_time(secs),
		int(stats.get("kills", 0)),
		int(stats.get("level", 1)),
		int(stats.get("cycle", 1)),
		int(stats.get("damage", 0.0)),
	]
	%DeathPanel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Issue #152: chain the death panel; primary is Quick Restart.
	FocusChain.apply(get_node_or_null("%DeathPanel"),
		get_node_or_null("%QuickRestartButton"))
	# Issue #18: hide the wave-start banner + prompt behind the death panel.
	# A dead player can't start a wave; the normal wave-info refresh restores
	# them on respawn/continue.
	%NextWaveButton.visible = false
	%WaveStatus.visible = false


func hide_death_screen() -> void:
	%DeathPanel.visible = false
	# Issue #191 (section A): the death screen closes over
	# gameplay — focus is released.
	_release_focus()


func _fmt_run_time(secs: int) -> String:
	return "%d:%02d" % [secs / 60, secs % 60]


func _on_quick_restart_pressed() -> void:
	hide_death_screen()
	# Issue #4 Phase 5: restart in the slot the run died in, not slot 0.
	NetworkManager.play_solo(NetworkManager.active_run_slot)


func _on_death_menu_pressed() -> void:
	hide_death_screen()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func set_hint(text: String) -> void:
	# Issue #190 (sections 2+4): hints are templates now —
	# they render through the composite prompt line, tokens
	# resolved at display time on this machine.
	_prompt_visible = text != ""
	_prompt_template = text
	_render_prompt_line()


# --- Class ability bar ---

## Issue #190 (amendment): the ability-bar key caps are
## input-source conditional. Keyboard renders them as
## today; on PAD the numbers are REMOVED (Q6's pad-is-
## cycle-only stays honest) and cycle_ability flank glyphs
## render on both sides of the bar, resolving through the
## #190 tier machinery like every other prompt surface.
var _ability_player: Node = null
## Issue #194: the last built hotbar row's analytic width
## (the #193 positioner's live measure; 0 = not built yet).
var _hotbar_content_w := 0.0
## Issue #194: the scale step the last build chose.
var _hotbar_scale := 1.0
var _ability_flank_left: HBoxContainer = null
var _ability_flank_right: HBoxContainer = null


func _render_ability_flanks() -> void:
	if _ability_flank_left == null or _ability_flank_right == null:
		return
	var show := InputSource.is_pad() and _ability_player != null and is_instance_valid(_ability_player)
	_ability_flank_left.visible = show
	_ability_flank_right.visible = show
	if show:
		var segs := PromptText.action_segments("cycle_ability")
		_fill_segment_line(_ability_flank_left, segs, 14, Color(0.8, 0.7, 0.4))
		_fill_segment_line(_ability_flank_right, segs, 14, Color(0.8, 0.7, 0.4))
		_position_ability_flanks()


## Issue #193: the flanks track %AbilityBar's LIVE width. The
## bar grows past its nominal 440px band as slots unlock (a
## full mage bar measures ~686px) and the #190 amendment's
## fixed offsets let the outer slots paint over the glyphs.
## Positions derive from the bar's laid-out rect widened to
## its combined minimum (growth runs rightward from the
## anchored left edge), inner edges held at a fixed margin;
## at nominal width the result equals the original offsets.
func _position_ability_flanks() -> void:
	if _ability_flank_left == null or _ability_flank_right == null:
		return
	if get_viewport() == null:
		return  # detached fixture: no viewport, no geometry
	var bar := %AbilityBar
	# The HUD is a CanvasLayer: its children anchor to the
	# viewport, so anchor geometry is computed in viewport
	# space (exact at any layout state).
	var vp := get_viewport().get_visible_rect()
	var cx: float = vp.size.x * 0.5
	var bar_l: float = vp.size.x * bar.anchor_left + bar.offset_left
	var content_w: float = _hotbar_content_w if _hotbar_content_w > 0.0 else bar.get_combined_minimum_size().x
	var w := maxf(bar.offset_right - bar.offset_left, content_w)
	var margin := 4.0
	var l_in: float = bar_l - margin - cx
	var r_in: float = bar_l + w + margin - cx
	_ability_flank_left.offset_right = l_in
	_ability_flank_left.offset_left = l_in - _ability_flank_left.get_combined_minimum_size().x
	_ability_flank_right.offset_left = r_in
	_ability_flank_right.offset_right = r_in + _ability_flank_right.get_combined_minimum_size().x


func refresh_abilities(p) -> void:
	refresh_mouse_legend(p)
	_ability_player = p
	if p == null:
		for c in %AbilityBar.get_children():
			c.queue_free()
		_hotbar_content_w = 0.0
		_render_ability_flanks()
		return
	# Issue #194: hotbar scaling. The bar grows slot by slot
	# with nothing capping its width; at high counts its right
	# end (and the #193 flank riding it) reaches the
	# bottom-right controls legend. Past the collision cap,
	# slot size and gaps step down through clean scale steps
	# until the bar fits; 0.5 is the floor (fonts floor at
	# 8px, the affinity bar at 40px — legibility holds).
	var cap := _hotbar_cap()
	# Steps pair the slot scale with its padding: at the
	# deepest step the padding crushes to 2px, which is
	# what lets the maximum row fit at the reference width.
	for step in [[1.0, 8], [0.85, 7], [0.7, 5], [0.6, 4], [0.5, 2]]:
		_hotbar_scale = step[0]
		_hotbar_content_w = _build_ability_slots(p, step[0], step[1])
		if _hotbar_content_w <= cap:
			break
	_render_ability_flanks()


## Issue #194: the width the hotbar may occupy — from its
## anchored left edge to the controls legend's left edge,
## less the Item 3 flank's margin and width allowance. Read
## live from the legend's own offsets so the two stay tied.
func _hotbar_cap() -> float:
	if get_viewport() == null:
		return 1e9
	var vp_w := get_viewport().get_visible_rect().size.x
	var bar := %AbilityBar
	var legend = get_node_or_null("MouseLegend")
	var legend_inset := 280.0
	if legend != null:
		legend_inset = -legend.offset_left
	var bar_left: float = vp_w * bar.anchor_left + bar.offset_left
	var flank_allow := 40.0
	if _ability_flank_right != null:
		flank_allow = maxf(flank_allow, _ability_flank_right.get_combined_minimum_size().x)
	return vp_w - legend_inset - bar_left - 4.0 - flank_allow


func _sf(base: int, s: float) -> int:
	return maxi(8, int(round(float(base) * s)))


## One scaled build of the slot row; returns the row's
## analytic width (slot minimums + gaps), measured from the
## slots built here — never from a half-freed predecessor.
func _build_ability_slots(p, s: float, pad_px: int) -> float:
	for c in %AbilityBar.get_children():
		c.queue_free()
	var sep := maxi(2, int(round(8.0 * s)))
	%AbilityBar.add_theme_constant_override("separation", sep)
	var built: Array = []
	var pad_source := InputSource.is_pad()
	for i in p.unlocked_abilities.size():
		var a: Dictionary = p.unlocked_abilities[i]
		var sid := String(a["id"])
		# Issue #19 (Jesse's call): Eagle Eye is a dead button in Warlord
		# (no waves, no mobs, unreachable in command view). Hide the slot
		# entirely while in the Warlord theme; it reappears on other levels.
		if sid == "eagle_eye" and _is_warlord_theme():
			continue
		var spec := String(p.get("specialization"))
		var is_spec := sid == spec and spec != ""
		var fam := Player.family_of(sid)
		var slot := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		if is_spec:
			# Specialized: gold highlight.
			sb.bg_color = Color(0.22, 0.18, 0.08, 0.9)
			sb.border_color = Color(1.0, 0.85, 0.3, 1.0)
		elif fam != "":
			# Non-specialized family skill: dimmed lock tint.
			sb.bg_color = Color(0.05, 0.05, 0.07, 0.6)
			sb.border_color = Color(0.25, 0.25, 0.3, 0.5)
		else:
			sb.bg_color = Color(0.08, 0.08, 0.1, 0.75)
			sb.border_color = Color(0.35, 0.35, 0.4, 0.8)
		# Selected slot always gets the gold highlight on top of any family tint.
		if i == p.selected_ability:
			sb.bg_color = Color(0.25, 0.2, 0.08, 0.9)
			sb.border_color = Color(0.8, 0.65, 0.25, 1.0)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = pad_px
		sb.content_margin_right = pad_px
		sb.content_margin_top = maxi(2, pad_px / 2)
		sb.content_margin_bottom = maxi(2, pad_px / 2)
		slot.add_theme_stylebox_override("panel", sb)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		var key_l := Label.new()
		# Issue #190 (amendment): the direct-select number
		# caps render on keyboard only — on pad there is no
		# direct select, so the numbers vanish.
		key_l.text = "" if pad_source else "[%s]" % String(a["key"])
		key_l.add_theme_font_size_override("font_size", _sf(11, s))
		key_l.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
		key_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(key_l)
		var name_l := Label.new()
		name_l.text = "%s %s" % [String(a["name"]), p.rank_roman()]
		name_l.add_theme_font_size_override("font_size", _sf(13, s))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if fam != "" and not is_spec:
			name_l.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		vb.add_child(name_l)
		# Affinity fill + milestone pips under the specialized skill.
		if is_spec:
			var aff := float(p.get("affinity").get(sid, 0.0))
			var bar := ProgressBar.new()
			bar.min_value = 0.0
			bar.max_value = 100.0
			bar.value = aff
			bar.custom_minimum_size = Vector2(maxf(40.0, 90.0 * s), 6)
			bar.show_percentage = false
			var bg2 := StyleBoxFlat.new()
			bg2.bg_color = Color(0.15, 0.15, 0.18, 1.0)
			bg2.set_corner_radius_all(2)
			bar.add_theme_stylebox_override("background", bg2)
			var fill2 := StyleBoxFlat.new()
			fill2.bg_color = Color(0.8, 0.65, 0.25, 1.0)
			fill2.set_corner_radius_all(2)
			bar.add_theme_stylebox_override("fill", fill2)
			vb.add_child(bar)
			var pips := Label.new()
			var pip_txt := ""
			for m in [25, 50, 75, 100]:
				pip_txt += "◆%d " % m if aff >= m else "◇%d " % m
			pips.text = pip_txt.strip_edges()
			pips.add_theme_font_size_override("font_size", _sf(10, s))
			pips.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(pips)
		# Status line: charges (warrior) or cooldown.
		var status_l := Label.new()
		status_l.add_theme_font_size_override("font_size", _sf(11, s))
		status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if p.class_id == "warrior":
			var sig_cd: float = float(p.ability_cds.get(sid, 0.0))
			if sid in ["sanctuary_totem", "doom_totem"] and sig_cd > 0.0:
				status_l.text = "%.0fs" % sig_cd
				status_l.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
			else:
				status_l.text = "x%d" % p.totem_charges if i == p.selected_ability else ""
				status_l.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		else:
			var cd: float = float(p.ability_cds.get(sid, 0.0))
			if cd > 0.0:
				status_l.text = "%.0fs" % cd
				status_l.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
			elif sid == "eagle_eye" and p.eagle_eye_used_wave == _wave_number():
				status_l.text = "used"
				status_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		vb.add_child(status_l)
		slot.add_child(vb)
		slot.tooltip_text = String(a["desc"])
		built.append(slot)
		%AbilityBar.add_child(slot)
	# Mage signature slots (key 8) appended after the regular bar.
	if p.class_id == "mage":
		var fams := Player.families()
		for fid in ["fire", "frost", "storm"]:
			var sig: Dictionary = p.call("family_signature", fid)
			if sig.is_empty():
				continue
			var ssid := String(sig["id"])
			var slot := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.2, 0.12, 0.25, 0.9)
			sb.border_color = Color(0.9, 0.6, 1.0, 1.0)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(4)
			sb.content_margin_left = pad_px
			sb.content_margin_right = pad_px
			sb.content_margin_top = maxi(2, pad_px / 2)
			sb.content_margin_bottom = maxi(2, pad_px / 2)
			slot.add_theme_stylebox_override("panel", sb)
			var vb := VBoxContainer.new()
			vb.add_theme_constant_override("separation", 0)
			var key_l := Label.new()
			key_l.text = "" if pad_source else "[8]"
			key_l.add_theme_font_size_override("font_size", _sf(11, s))
			key_l.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
			key_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(key_l)
			var name_l := Label.new()
			name_l.text = String(sig["name"])
			name_l.add_theme_font_size_override("font_size", _sf(13, s))
			name_l.add_theme_color_override("font_color", Color(0.95, 0.8, 1.0))
			name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(name_l)
			var status_l := Label.new()
			status_l.add_theme_font_size_override("font_size", _sf(11, s))
			status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var cd: float = float(p.ability_cds.get(ssid, 0.0))
			if cd > 0.0:
				status_l.text = "%.0fs" % cd
				status_l.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
			else:
				status_l.text = "READY"
				status_l.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			vb.add_child(status_l)
			slot.add_child(vb)
			slot.tooltip_text = String(sig["desc"])
			built.append(slot)
			%AbilityBar.add_child(slot)
	_render_ability_flanks()


	var total := 0.0
	for slot in built:
		total += (slot as Control).get_combined_minimum_size().x
	if built.size() > 1:
		total += float(sep) * float(built.size() - 1)
	return total

func _wave_number() -> int:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null and "wave" in dungeon:
		return int(dungeon.get("wave"))
	return 0


## Issue #19: true while the current level uses the Warlord theme.
func _is_warlord_theme() -> bool:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	return dungeon != null and bool(dungeon.get("is_warlord"))

# --- Boss bar ---

func set_boss(boss_name: String, frac: float) -> void:
	%BossBar.visible = true
	%BossName.text = boss_name
	%BossHP.value = frac


func hide_boss() -> void:
	%BossBar.visible = false


# --- Inventory ---

func set_pickup_prompt(visible: bool, item_name: String) -> void:
	_pickup_shown = visible
	_pickup_name = item_name
	_prompt_visible = visible
	if visible:
		# Issue #152 (2A-2) + #190 (section 4): the interact-
		# prompt line — every prompt_text() string and loot name
		# lands here, so rendering the assembled template as
		# composite segments resolves tokens embedded by the
		# source (e.g. "({interact})") as well as the
		# "[{interact}]" prefix, with glyph art when Steam
		# serves it.
		_prompt_template = "[{interact}]  " + item_name
	_render_prompt_line()


func toggle_inventory() -> void:
	if inventory_open:
		close_inventory()
	else:
		open_inventory()


## Open the character panel as an alternative pause screen: the
## mouse is freed for the panel and the local player is damage-
## immune while it is up (Player.take_damage gates on
## inventory_open, the same seam as the pause menu's is_paused
## breather). The world is NOT paused — solo and multiplayer behave
## identically here.
func open_inventory() -> void:
	inventory_open = true
	%InventoryPanel.visible = true
	if _player != null:
		refresh_inventory(_player)
	_layout_pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Close the panel and hand the mouse back — but only when no other
## menu or popup owns it (mirrors close_destination_popup's rule, so
## a close never recaptures over the pause menu or a popup).
func close_inventory() -> void:
	if not inventory_open:
		return
	inventory_open = false
	%InventoryPanel.visible = false
	_layout_pause()
	if not is_paused and not cipher_popup_open and not dest_popup_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Esc while the inventory is open swaps to the pause UI (Jesse
## 2026-10-13): the pause menu opens FIRST so close_inventory's
## recapture check sees is_paused and leaves the mouse free for it,
## and close_inventory's layout pass re-centers the pause panel.
## Exactly one of the two panels is visible afterwards.
func swap_inventory_to_pause() -> void:
	show_pause()
	close_inventory()


## Silent close for full-screen takeovers (death / downed): clears
## the panel state without touching the mouse — the takeover
## screen owns the cursor.
func force_close_inventory() -> void:
	inventory_open = false
	%InventoryPanel.visible = false


## Shift the pause panel left when the inventory is open so the two don't overlap.
func _layout_pause() -> void:
	var panel: PanelContainer = %PausePanel
	if %InventoryPanel.visible:
		panel.offset_left = -420.0
		panel.offset_right = 60.0
	else:
		panel.offset_left = -240.0
		panel.offset_right = 240.0


# --- Character panel (issue #104 Phase 2) --------------------------------
## The I-key inventory panel is now a character panel: LEFT = the four
## equipment slot boxes, RIGHT = the bag as exactly INVENTORY_MAX fixed
## rows. Zero-scroll BY CONSTRUCTION: the row count is constant (empty
## rows render disabled), there is no ScrollContainer anywhere in the
## panel, and the panel is sized for the full layout at any inventory
## state. Gear lacking an icon texture renders as rarity-colored name
## text in its slot box (the spec's art-gap fallback).
const SLOT_ORDER: Array[String] = ["WEAPON", "ARMOR", "TRINKET", "TOOL"]
var _slot_boxes: Dictionary = {} # slot name -> {box, icon, item_label}
var _bag_rows: Array = [] # Array[Button], INVENTORY_MAX entries
var _bag_group := ButtonGroup.new()
var _equip_button: Button
## Issue #152 (§2.1): the character panel's pad selection model. A
## bag-row selection (the rows' ButtonGroup state) and a slot
## selection are mutually exclusive; _selected_slot names the slot
## chosen via focus + ui_accept, "" while the bag owns the selection.
var _selected_slot := ""
var _unequip_button: Button = null


func _build_character_panel() -> void:
	var vbox := %InventoryPanel.get_node("InvVBox") as VBoxContainer
	var body := HBoxContainer.new()
	body.name = "CharBody"
	body.add_theme_constant_override("separation", 10)
	vbox.add_child(body)
	# LEFT: equipment slot boxes.
	var slot_col := VBoxContainer.new()
	slot_col.name = "SlotColumn"
	slot_col.add_theme_constant_override("separation", 6)
	body.add_child(slot_col)
	var slot_head := Label.new()
	slot_head.text = "EQUIPPED"
	slot_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_head.add_theme_font_size_override("font_size", 13)
	slot_col.add_child(slot_head)
	for slot_name in SLOT_ORDER:
		# A PanelContainer, NOT a Button with an icon: Button icons render
		# at native texture size and blow the box (and the whole panel)
		# up. The TextureRect is hard-sized to 52x52 instead.
		var box := PanelContainer.new()
		box.name = "Slot_" + slot_name
		box.custom_minimum_size = Vector2(188, 66)
		# Issue #152 (§2.1): the slot box joins the panel's focus
		# chain. ui_accept on a focused box SELECTS the slot (the
		# Unequip button performs it); mouse clicks keep their
		# direct-unequip behavior, unchanged.
		box.focus_mode = Control.FOCUS_ALL
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.09, 0.12, 0.95)
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(1)
		sb.border_color = Color(0.45, 0.38, 0.25, 0.9)
		sb.content_margin_left = 6.0
		sb.content_margin_right = 6.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		box.add_theme_stylebox_override("panel", sb)
		box.gui_input.connect(_on_slot_gui_input.bind(slot_name))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		box.add_child(hb)
		var icon := TextureRect.new()
		icon.name = "SlotIcon_" + slot_name
		icon.custom_minimum_size = Vector2(52, 52)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(icon)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vb)
		var slot_label := Label.new()
		slot_label.text = slot_name
		slot_label.add_theme_font_size_override("font_size", 12)
		slot_label.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
		slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(slot_label)
		var item_label := Label.new()
		item_label.name = "SlotItem_" + slot_name
		item_label.text = "—"
		item_label.add_theme_font_size_override("font_size", 12)
		item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_label.custom_minimum_size = Vector2(104, 0)
		item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(item_label)
		slot_col.add_child(box)
		_slot_boxes[slot_name] = {"box": box, "icon": icon, "item_label": item_label}
	# RIGHT: the bag — exactly INVENTORY_MAX fixed rows, always rendered.
	var bag_col := VBoxContainer.new()
	bag_col.name = "BagColumn"
	bag_col.add_theme_constant_override("separation", 2)
	body.add_child(bag_col)
	var bag_head := Label.new()
	bag_head.text = "BAG"
	bag_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_head.add_theme_font_size_override("font_size", 13)
	bag_col.add_child(bag_head)
	for i in Player.INVENTORY_MAX:
		var row := Button.new()
		row.name = "BagRow_%d" % i
		row.custom_minimum_size = Vector2(436, 24)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.toggle_mode = true
		row.button_group = _bag_group
		row.add_theme_font_size_override("font_size", 13)
		row.text = "—"
		row.disabled = true
		row.pressed.connect(_on_bag_row_pressed.bind(i))
		row.gui_input.connect(_on_bag_row_gui_input.bind(i))
		bag_col.add_child(row)
		_bag_rows.append(row)
	# Hint + action row (Equip joins the retained Use/Dispose).
	var hint := Label.new()
	hint.name = "CharHint"
	hint.text = "Only EQUIPPED gear grants bonuses. Double-click a row to equip; click a filled slot to unequip. Pad: focus a slot, A selects it, then use Unequip."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint)
	var actions := HBoxContainer.new()
	actions.name = "CharActions"
	actions.add_theme_constant_override("separation", 8)
	vbox.add_child(actions)
	_equip_button = Button.new()
	_equip_button.name = "EquipButton"
	_equip_button.text = "Equip selected"
	_equip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_button.pressed.connect(_on_equip_pressed)
	actions.add_child(_equip_button)
	var use_b := Button.new()
	use_b.name = "UseButton"
	use_b.text = "Use selected (consumable)"
	use_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_b.pressed.connect(_on_use_pressed)
	actions.add_child(use_b)
	var dis_b := Button.new()
	dis_b.name = "DisposeButton"
	dis_b.text = "Dispose selected stack"
	dis_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dis_b.pressed.connect(_on_dispose_pressed)
	actions.add_child(dis_b)
	# Issue #152 (§2.1): the pad route to unequip — enabled only
	# while an equipped slot is selected (see _refresh_char_actions).
	_unequip_button = Button.new()
	_unequip_button.name = "UnequipButton"
	_unequip_button.text = "Unequip selected slot"
	_unequip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unequip_button.disabled = true
	_unequip_button.pressed.connect(_on_unequip_pressed)
	actions.add_child(_unequip_button)


func _selected_bag_index() -> int:
	for i in _bag_rows.size():
		if (_bag_rows[i] as Button).button_pressed:
			return i
	return -1


func _class_tag(item: ItemData) -> String:
	var names: Array[String] = []
	for c in item.allowed_classes:
		names.append(c.capitalize())
	return " / ".join(names)


## Shared equip path for the Equip button and row double-clicks. Denials
## toast the specific reason (the player's equip_stack re-checks in code
## regardless — Phase 1 enforcement).
func _equip_row(index: int) -> void:
	if _player == null:
		return
	if index < 0 or index >= _player.inventory.size():
		toast("Select a stack first.")
		return
	var entry: Dictionary = _player.inventory[index]
	var item := entry["item"] as ItemData
	if item == null:
		return
	if not ItemData.is_gear(item):
		toast("%s can't be equipped." % item.display_name)
		return
	if not item.allowed_classes.is_empty() and not item.allowed_classes.has(_player.class_id):
		toast("%s only." % _class_tag(item))
		return
	if str(entry.get("equipped_slot", "")) == ItemData.slot_name(item.slot):
		toast("Already equipped.")
		return
	_player.equip_stack(index)


func _on_equip_pressed() -> void:
	_equip_row(_selected_bag_index())


func _on_bag_row_pressed(_index: int) -> void:
	# Selection state lives in the rows' ButtonGroup. Issue #152:
	# a bag selection clears any slot selection (mutually exclusive).
	if _selected_slot != "":
		_selected_slot = ""
		_refresh_slot_highlight()
	_refresh_char_actions()


func _on_bag_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
			_equip_row(index)


func _on_slot_gui_input(event: InputEvent, slot_name: String) -> void:
	# Issue #152 (§2.1): pad path — ui_accept on a focused slot box
	# SELECTS the slot; the action row's Unequip button performs
	# the unequip (bag select→Equip is the template).
	if event.is_action_pressed("ui_accept"):
		_select_slot(slot_name)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_slot_pressed(slot_name)


## Clicking a filled slot box unequips that stack.
func _on_slot_pressed(slot_name: String) -> void:
	if _player == null:
		return
	var entry: Dictionary = _player.equipped_entry(slot_name)
	if entry.is_empty():
		toast("No %s equipped." % slot_name.capitalize())
		return
	for i in _player.inventory.size():
		if _player.inventory[i] == entry:
			_player.unequip_stack(i)
			return


## Issue #152 (§2.1): select a slot for the action row (pad path).
func _select_slot(slot_name: String) -> void:
	_selected_slot = slot_name
	# Bag and slot selections are mutually exclusive.
	for row in _bag_rows:
		(row as Button).set_pressed_no_signal(false)
	_refresh_slot_highlight()
	_refresh_char_actions()


## The selected slot's box wears a gold border; the rest keep the
## panel's standard border color.
func _refresh_slot_highlight() -> void:
	for slot_name in SLOT_ORDER:
		var parts: Dictionary = _slot_boxes.get(slot_name, {})
		if parts.is_empty():
			continue
		var box := parts["box"] as PanelContainer
		var sb := box.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.border_color = Color(1.0, 0.85, 0.4) if slot_name == _selected_slot \
				else Color(0.45, 0.38, 0.25, 0.9)


## Unequip enable rule (issue #152 §2.1): live only while the
## selection is a slot with something equipped in it.
func _refresh_char_actions() -> void:
	if _unequip_button == null:
		return
	var live := false
	if _selected_slot != "" and _player != null:
		live = not (_player.equipped_entry(_selected_slot) as Dictionary).is_empty()
	_unequip_button.disabled = not live
	# Issue #156: this refresh changes the panel's focusable set
	# WITHOUT re-chaining — if the Unequip button just disabled
	# under the pad's focus, focus would rest on the dead control.
	# The helper's rescue re-seeds it (a no-op while focus lives).
	FocusChain.rescue(get_node_or_null("%InventoryPanel"), null)


func _on_unequip_pressed() -> void:
	if _selected_slot == "":
		return
	# The mouse path's unequip, toasts included — one code path.
	_on_slot_pressed(_selected_slot)
	_refresh_char_actions()


func refresh_inventory(p: Player) -> void:
	for slot_name in SLOT_ORDER:
		var parts: Dictionary = _slot_boxes.get(slot_name, {})
		if parts.is_empty():
			continue
		var icon := parts["icon"] as TextureRect
		var item_label := parts["item_label"] as Label
		var entry: Dictionary = p.equipped_entry(slot_name)
		if entry.is_empty():
			icon.texture = null
			item_label.text = "—"
			item_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		else:
			var item := entry["item"] as ItemData
			var label := item.display_name
			# Issue #113 Phase 1: an upgraded stack reads "Iron Sword +3",
			# and the weapon slot adds the detail line under the name.
			var ulevel := int(entry.get("upgrade_level", 0))
			if ulevel > 0:
				label += " +%d" % ulevel
			if int(entry["count"]) > 1:
				label += " x%d" % int(entry["count"])
			if slot_name == "WEAPON" and ulevel > 0:
				label += "\n+%d damage from upgrades" % int(
					Player.UPGRADE_DAMAGE_PER_LEVEL * float(ulevel))
			icon.texture = item.icon
			item_label.text = label
			item_label.add_theme_color_override("font_color", ItemData.rarity_color(item.rarity))
	for i in _bag_rows.size():
		var row := _bag_rows[i] as Button
		if i >= p.inventory.size():
			row.text = "—"
			row.disabled = true
			row.set_pressed_no_signal(false)
			continue
		var entry: Dictionary = p.inventory[i]
		var item := entry["item"] as ItemData
		var label := item.display_name
		# Issue #113 Phase 1: upgraded stacks read "Iron Sword +3" in
		# the bag too (same read as the slot box).
		if int(entry.get("upgrade_level", 0)) > 0:
			label += " +%d" % int(entry.get("upgrade_level", 0))
		if int(entry["count"]) > 1:
			label += " x%d" % int(entry["count"])
		if item.consumable:
			label = "[USE] " + label
		elif str(entry.get("equipped_slot", "")) != "":
			label = "[EQ] " + label
		var summary := _item_summary(item)
		if summary != "":
			label += "  " + summary
		if not item.allowed_classes.is_empty():
			label += "  [%s only]" % _class_tag(item)
		row.text = label
		row.disabled = false
		var restricted := not item.allowed_classes.is_empty() \
			and not item.allowed_classes.has(p.class_id)
		if restricted:
			row.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		else:
			row.add_theme_color_override("font_color", ItemData.rarity_color(item.rarity))
	# Potion quick-slot: refresh from the player's inventory.
	_potion_player = p
	refresh_potion_slot()
	# Issue #152: row/slot contents changed the panel's focusable
	# set — re-chain while the panel is open (primary-less apply
	# seeds the first control, the WEAPON slot box, only when focus
	# is dead), and keep the Unequip enable state honest.
	if inventory_open:
		FocusChain.apply(get_node_or_null("%InventoryPanel"), null)
	_refresh_char_actions()


func _on_dispose_pressed() -> void:
	if _player == null:
		return
	var sel := _selected_bag_index()
	if sel < 0 or sel >= _player.inventory.size():
		toast("Select a stack first.")
		return
	# Issue #113 Phase 1: disposing an UPGRADED stack asks first, and
	# the confirmation names the loss (plain stacks keep the immediate
	# dispose they have always had).
	var entry: Dictionary = _player.inventory[sel]
	var ulevel := int(entry.get("upgrade_level", 0))
	if ulevel > 0:
		var ditem := entry.get("item") as ItemData
		var dname := ditem.display_name if ditem != null else "Item"
		_show_quit_confirm(
			"Dispose %s +%d? The +%d upgrade will be lost." % [dname, ulevel, ulevel],
			func() -> void:
				if _player != null and sel < _player.inventory.size():
					_player.dispose_item(sel))
		return
	_player.dispose_item(sel)


func _on_use_pressed() -> void:
	if _player == null:
		return
	var sel := _selected_bag_index()
	if sel < 0 or sel >= _player.inventory.size():
		toast("Select a stack first.")
		return
	_player.use_item(sel)


func _item_summary(item: ItemData) -> String:
	var parts: Array[String] = []
	if item.consumable:
		# Issue #113 Phase 1: upgrade kits name their strength.
		if item.upgrade_levels > 0:
			parts.append("weapon +%d level%s" % [item.upgrade_levels,
				"s" if item.upgrade_levels > 1 else ""])
		if item.heal_fraction > 0.0:
			parts.append("heal %d%%" % int(item.heal_fraction * 100.0))
		if item.buff_stat != "":
			parts.append("%s x%.1f %ds" % [item.buff_stat, item.buff_mult, int(item.buff_duration)])
		return " ".join(parts)
	if item.damage_bonus != 0.0:
		parts.append("+%d dmg" % int(item.damage_bonus))
	if item.health_bonus != 0.0:
		parts.append("+%d hp" % int(item.health_bonus))
	if item.speed_bonus != 0.0:
		parts.append("+%.1f spd" % item.speed_bonus)
	if item.damage_mult != 1.0:
		parts.append("dmg x%.2f" % item.damage_mult)
	if item.health_mult != 1.0:
		parts.append("hp x%.2f" % item.health_mult)
	if item.speed_mult != 1.0:
		parts.append("spd x%.2f" % item.speed_mult)
	if item.xp_mult != 1.0:
		parts.append("xp x%.2f" % item.xp_mult)
	if parts.is_empty():
		return ""
	return "(" + ", ".join(parts) + ")"


## Toggle FPS-specific HUD elements for RTS command view.
## Hides crosshair and ability bar; keeps health/XP/status.
func set_command_view(on: bool) -> void:
	%Crosshair.visible = not on
	%AbilityBar.visible = not on



## --- Mouse legend (issue #95): persistent bottom-right click guide ---
## Data-driven via MouseLegend; render path knows nothing about classes.
var _legend_left: Label
var _legend_right: Label
var _legend_mid: Label
## Issue #190 (section 4): the legend rows are composite —
## a caption host (glyph art or caption text) beside the verb
## label above. Row containers own the layout visibility;
## the verb labels' visible flags mirror it (the standing
## suite reads them).
var _legend_row_left: HBoxContainer
var _legend_row_right: HBoxContainer
var _legend_row_mid: HBoxContainer
var _legend_cap_left: HBoxContainer
var _legend_cap_right: HBoxContainer
var _legend_cap_mid: HBoxContainer


## Tiny procedural mouse icon (Art Director ships the real SNES sprite in Phase 3).
## Kept as the fallback if the sprite file is ever missing.
class MouseIcon:
	extends Control

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := Color(0.85, 0.82, 0.75, 0.95)
		var dark := Color(0.45, 0.4, 0.32, 0.95)
		# Body: rounded rect.
		draw_rect(Rect2(2, 6, w - 4, h - 8), body, true)
		draw_rect(Rect2(2, 6, w - 4, h - 8), dark, false, 2.0)
		# Button split line + wheel.
		draw_line(Vector2(w / 2, 6), Vector2(w / 2, h * 0.45), dark, 2.0)
		draw_circle(Vector2(w / 2, h * 0.32), 3.0, dark)


## Art Director's SNES mouse icon (Phase 3). Nearest filtering keeps the
## pixel art crisp; falls back to the procedural MouseIcon if missing.
const LEGEND_ICON_PATH := "res://assets/sprites/ui/mouse_legend_icon.png"


func _build_mouse_legend() -> void:
	var panel := PanelContainer.new()
	panel.name = "MouseLegend"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -280.0
	panel.offset_top = -100.0
	panel.offset_right = -16.0
	panel.offset_bottom = -16.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.08, 0.78)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.55, 0.42, 0.22, 0.9)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hb)
	if ResourceLoader.exists(LEGEND_ICON_PATH, "Texture2D"):
		var icon := TextureRect.new()
		icon.texture = load(LEGEND_ICON_PATH)
		icon.custom_minimum_size = Vector2(38, 38)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(icon)
	else:
		# Sprite missing: fall back to the procedural icon rather than crashing.
		var icon := MouseIcon.new()
		icon.custom_minimum_size = Vector2(26, 38)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var rl := _legend_row(vb, "LMB")
	_legend_row_left = rl["row"]
	_legend_cap_left = rl["cap"]
	_legend_left = rl["verb"]
	var rr := _legend_row(vb, "RMB")
	_legend_row_right = rr["row"]
	_legend_cap_right = rr["cap"]
	_legend_right = rr["verb"]
	var rm := _legend_row(vb, "MMB")
	_legend_row_mid = rm["row"]
	_legend_cap_mid = rm["cap"]
	_legend_mid = rm["verb"]
	add_child(panel)


func _legend_row(parent: Control, btn: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var cap := HBoxContainer.new()
	cap.add_theme_constant_override("separation", 2)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cap)
	var verb := Label.new()
	verb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	verb.add_theme_font_size_override("font_size", 13)
	verb.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
	row.add_child(verb)
	_fill_segment_line(cap, [{"kind": "text", "text": btn}], 13, Color(0.8, 0.7, 0.4))
	return {"row": row, "cap": cap, "verb": verb}


## One legend row's render: the caption slot as composite
## segments (art when Steam serves it), the verb resolved.
func _set_legend_row(row_c: Control, cap: HBoxContainer, verb: Label, action: String, verb_template: String, toggle: bool) -> void:
	var show := verb_template != "" or not toggle
	row_c.visible = show
	verb.visible = show
	if not show:
		return
	_fill_segment_line(cap, PromptText.action_segments(action), 13, Color(0.8, 0.7, 0.4))
	verb.text = PromptText.resolve(verb_template)


## Re-renders the legend from the registry. Called on ability refresh (covers
## setup + class switch); the player emits click_state_changed for live
## transitions (rogue charge, Holy Light arm/charge), wired in setup().
func refresh_mouse_legend(p) -> void:
	if _legend_left == null:
		_build_mouse_legend()
	if p != null:
		_legend_player = p
	var cid := str(p.get("class_id")) if p != null else ""
	var state := "standard"
	if p != null and p is Object and (p as Object).has_method("legend_state"):
		state = str(p.legend_state())
	var row: Dictionary = MouseLegend.actions_for(cid, state)
	# Issue #152 (2A-2): slots are action slots — captions render
	# the slot action's glyph for the current source and the verb
	# labels resolve their tokens, all through PromptText.
	var slots: Dictionary = MouseLegend.slot_actions_for(state)
	# Issue #190 (section 4): the caption slots are a
	# designated art surface — they render as segments now;
	# the verb labels keep the resolved text (and the
	# visibility the standing pins read).
	_set_legend_row(_legend_row_left, _legend_cap_left, _legend_left, str(slots["left"]), str(row["left"]), true)
	_set_legend_row(_legend_row_right, _legend_cap_right, _legend_right, str(slots["right"]), str(row["right"]), true)
	_set_legend_row(_legend_row_mid, _legend_cap_mid, _legend_mid, str(slots["middle"]), str(row["middle"]), false)
