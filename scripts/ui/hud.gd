extends CanvasLayer
## Player HUD: health, XP, level, equipment, crosshair, toasts, pause menu.

## Preloaded (not class_name) so the bounty UI keeps working even when the
## global class cache is stale on a fresh clone (issue #7 red-fix lesson).
const BountySys := preload("res://scripts/systems/bounty.gd")
const BountyUI := preload("res://scripts/ui/bounty_ui.gd")

var is_paused := false

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

## Pause menu tabs: 0=Stats, 1=Specialization, 2=Collection.
var _pause_tab := 0
var _pause_tab_btns: Array[Button] = []
## Node names (under PauseVBox) belonging to each tab.
var _pause_tab_members: Array = []
## Action buttons moved outside the scroll area (stored refs avoid % lookup issues).
var _class_btn: Button
var _save_quit_btn: Button


func _ready() -> void:
	add_to_group("hud")
	_build_pause_tabs()
	_build_bounty_tracker()


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
	_bounty_tracker.offset_top = 96.0
	_bounty_tracker.offset_right = -16.0
	_bounty_tracker.offset_bottom = 180.0
	_bounty_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bounty_tracker.add_theme_font_size_override("font_size", 14)
	_bounty_tracker.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	_bounty_tracker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_bounty_tracker.add_theme_constant_override("outline_size", 4)
	_bounty_tracker.visible = false
	add_child(_bounty_tracker)


## Rework the pause panel into three tabs (Stats / Specialization / Collection).
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
	var tab_names := ["Stats", "Specialization", "Collection"]
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
	# Define tab membership.
	_pause_tab_members = [
		["HintLabel", "VolLabel", "MasterRow", "MusicRow", "SFXRow",
			"StatPointsLabel", "StatPair1", "StatPair2"],
		["SpecLabel", "SpecList"],
		["FamilyLabel", "FamilyPanel", "CollectionLabel", "CollectionLog"],
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
	var hint := vbox.get_node_or_null("HintLabel") as Label
	if hint != null:
		hint.add_theme_font_size_override("font_size", 12)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "WASD move · Click attack · Shift dash · Q ability · G ping · R start wave"
	# Slimmer stat labels so two columns fit the 480px panel.
	for pn in ["StatPair1", "StatPair2"]:
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
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if selected else Color(0.7, 0.7, 0.75))
	btn.add_theme_font_size_override("font_size", 14)


func _on_pause_tab_pressed(idx: int) -> void:
	_pause_tab = idx
	for i in _pause_tab_btns.size():
		_pause_tab_btns[i].button_pressed = i == idx
		_style_tab_button(_pause_tab_btns[i], i == idx)
	_apply_pause_tab_visibility()
	# Stats and Collection tabs are designed to fit; scrolling hard-disabled
	# (layouts that cannot scroll, not promises). Specialization keeps
	# auto-scroll as a safety valve.
	var scroll := %PausePanel.get_node("PauseMain/PauseScroll") as ScrollContainer
	if scroll != null:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if idx == 1 else ScrollContainer.SCROLL_MODE_DISABLED


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
	if idx >= 0 and idx < 3:
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


func set_level(level: int, p: Node) -> void:
	%LevelLabel.text = "Lv %d %s" % [level, (p.get("class_data") as ClassData).display_name]


## All carried items apply. Shows total items, stack count, stacked multipliers.
func refresh_loadout(p: Player) -> void:
	var lines: Array[String] = []
	var total := 0
	for entry in p.inventory:
		total += int(entry["count"])
	lines.append("Carried items: %d (%d stacks)" % [total, p.inventory.size()])
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
	%ToastLabel.text = message
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
	vendor_open = true
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
	close_hint.text = "E / Esc — close"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vb.add_child(close_hint)
	_open_cipher_popup(vb.get_parent() as Control)


func refresh_vendor_cash() -> void:
	if _vendor_cash_label != null and is_instance_valid(_vendor_cash_label) and _player != null:
		_vendor_cash_label.text = "Your cash: $%d" % int(_player.get("supermarket_cash"))


func _on_vendor_buy(st: Node, item_id: String) -> void:
	st.rpc_id(NetworkManager.server_id, "buy_vendor_item", item_id)
	AudioManager.sfx("ui_click")


# --- Bounty Board (issue #7 Phase 2) ---

var bounty_open := false
var _bounty_tracker: Label = null
var _bounty_tick := 0.0
## Warlord mode hides the objective cluster; the tracker hides with it.
var _bounty_hide := false


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
	bounty_open = true
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
	close_hint.text = "E / Esc — close"
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

	vault_open = true


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
		desc.text = data.description
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


func _input(event: InputEvent) -> void:
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


func close_cipher_popup() -> void:
	var was_vault := vault_open
	if _cipher_popup != null and is_instance_valid(_cipher_popup):
		_cipher_popup.queue_free()
	_cipher_popup = null
	vendor_open = false
	bounty_open = false
	if was_vault:
		AudioManager.sfx("vault_close")
	vault_open = false
	_vendor_cash_label = null
	cipher_popup_open = false
	if was_vault:
		AudioManager.sfx("vault_close")
	if not is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	close_hint.text = "E / Esc — close"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vb.add_child(close_hint)
	AudioManager.sfx("pickup")
	_open_cipher_popup(vb.get_parent() as Control)


## Lockbox popup: text entry for the mason's key.
func show_lockbox_popup() -> void:
	var vb := _cipher_panel()
	var title := Label.new()
	title.text = "Brass Lockbox"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(title)
	var desc := Label.new()
	desc.text = "A brass lockbox etched with mason's marks."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	vb.add_child(desc)
	var entry := LineEdit.new()
	entry.placeholder_text = "Enter the mason's key..."
	entry.custom_minimum_size = Vector2(320, 0)
	entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(entry)
	var feedback := Label.new()
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.add_theme_font_size_override("font_size", 13)
	feedback.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	vb.add_child(feedback)
	var submit := Button.new()
	submit.text = "Unlock"
	submit.pressed.connect(_on_lockbox_submit.bind(entry, feedback))
	vb.add_child(submit)
	var close_hint := Label.new()
	close_hint.text = "E / Esc — close"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	vb.add_child(close_hint)
	entry.text_submitted.connect(_on_lockbox_submit.bind(entry, feedback))
	_open_cipher_popup(vb.get_parent() as Control)
	entry.grab_focus()


func _on_lockbox_submit(_text: String, entry: LineEdit, feedback: Label) -> void:
	var key := CipherPoems.normalize_key(entry.text)
	if key == CipherPoems.passphrase():
		var fresh := SaveManager.unlock_architect()
		SaveManager.unlock_achievement("drafted")
		AudioManager.sfx("unlock")
		close_cipher_popup()
		if fresh:
			toast("SECRET CLASS UNLOCKED: Architect")
			var prog: Dictionary = SaveManager.get_achievement_progress("drafted")
			if not prog.is_empty():
				show_toast("ACHIEVEMENT: %s — %s" % [prog["name"], prog["desc"]])
		else:
			toast("The Architect is already unlocked.")
	else:
		AudioManager.sfx("ui_error")
		var n := SaveManager.get_cipher_fragments().size()
		feedback.text = "The lockbox clicks shut. (%d/8 fragments)" % n
		entry.select_all()


# --- Departure board (Train Station Phase 2) ---

func flash_damage() -> void:
	var tween := create_tween()
	tween.tween_property(%DamageFlash, "modulate:a", 0.35, 0.05)
	tween.tween_property(%DamageFlash, "modulate:a", 0.0, 0.3)


func flash_dash() -> void:
	# Brief cool streak across the screen on dash.
	%DamageFlash.modulate = Color(0.6, 0.8, 1.0, 0.22)
	var tween := create_tween()
	tween.tween_property(%DamageFlash, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void: %DamageFlash.modulate = Color(1, 0.25, 0.25, 0))


func show_pause() -> void:
	is_paused = true
	refresh_stats()
	%PausePanel.visible = true
	# Default to the Stats tab when the menu opens.
	if _pause_tab_btns.size() == 3:
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


func hide_pause() -> void:
	is_paused = false
	%PausePanel.visible = false
	%ClassPanel.visible = false
	%TopRight.visible = true


func _on_resume_pressed() -> void:
	hide_pause()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_quit_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


## Save the current run as a save point, then quit to the menu.
## Host in multiplayer: saves the full roster. Client: just disconnects.
## Station-aware: quitting from the pit-stop saves the NEXT level, exactly
## as if the train had departed.
func _on_save_quit_pressed() -> void:
	if _player == null:
		_on_quit_pressed()
		return
	var theme_id := "village"
	var level_number := 1
	var level_seed := 0
	var station := get_tree().get_first_node_in_group("station")
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if station != null:
		var nl := Station.next_level_number
		# board_destinations() swaps warlord for the APEX ARENA on apex
		# cycles (issue #5) so the saved next theme agrees with the board.
		var dests := Dungeon.board_destinations(nl)
		theme_id = dests[(nl - 1) % dests.size()]
		level_number = nl
		level_seed = int(station.get("departure_seed"))
	elif dungeon != null:
		theme_id = str(dungeon.get("theme").get("theme_id")) if dungeon.get("theme") != null else "village"
		level_number = int(dungeon.get("level_number"))
		level_seed = Dungeon.next_seed
	else:
		_on_quit_pressed()
		return
	if multiplayer.get_peers().size() > 0 and not multiplayer.is_server():
		# Client: warn that only the host's save persists.
		_show_quit_confirm("Disconnect? Only the host's save will persist.", _on_quit_pressed)
		return
	if multiplayer.get_peers().size() > 0:
		# Host: multiplayer save with roster collection (async, then quit).
		var saver = station if station != null else dungeon
		saver.save_multiplayer_run(theme_id, level_number, level_seed)
		# save_multiplayer_run waits 3s for clients; quit after.
		await get_tree().create_timer(3.5).timeout
	else:
		SaveManager.save_run({
			"theme_id": theme_id,
			"level_number": level_number,
			"class_id": _player.class_id,
			"player_state": _player.get_state(),
		}, SaveManager.MODE_SOLO, NetworkManager.active_run_slot)
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
	dialog.popup_centered()


func _on_class_pressed() -> void:
	%ClassPanel.visible = true


func _on_class_cancel() -> void:
	%ClassPanel.visible = false


func _on_class_chosen(new_class: String) -> void:
	%ClassPanel.visible = false
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

func refresh_stats() -> void:
	if _player == null:
		return
	%StatPointsLabel.text = "Stat points: %d" % _player.stat_points
	%DmgVal.text = "+%d dmg" % int(_player.bonus_damage)
	%HpVal.text = "+%d hp" % int(_player.bonus_health)
	%SpdVal.text = "+%.1f spd" % _player.bonus_speed
	%AuraVal.text = "+%d aura" % int(_player.bonus_aura)
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
func _refresh_collection_log() -> void:
	for child in %CollectionLog.get_children():
		child.queue_free()
	if _player == null:
		return
	var fams := Player.families()
	var coll_all: Dictionary = _player.get("family_collection")
	var grid := HBoxContainer.new()
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 16)
	%CollectionLog.add_child(grid)
	var cols: Array = []
	for i in 2:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
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
		row.add_theme_font_size_override("font_size", 11)
		(cols[idx % 2] as VBoxContainer).add_child(row)
		idx += 1
	_refresh_cipher_section()
	_refresh_combo_codex()
	_refresh_trophy_section()


## Apex trophies (issue #5 Phase 3): 3 fixed rows, one per apex boss.
## Earned rows show the relic icon in gold; locked rows show ??? + hint.
## Fixed row count → layout cannot scroll.
func _refresh_trophy_section() -> void:
	var trophies: Array = SaveManager.get_apex_trophies()
	var header := Label.new()
	header.text = "Apex Trophies — %d/3" % trophies.size()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	%CollectionLog.add_child(header)
	for apex_id in ["apex_boar", "apex_warden", "apex_horror"]:
		var earned: bool = apex_id in trophies
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		%CollectionLog.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(24, 24)
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
		label.add_theme_font_size_override("font_size", 11)
		row.add_child(label)



## Architect Cipher section: collected fragments as raw cipher + shift hint
## (never the solution). Compact, at most 8 short rows.
func _refresh_cipher_section() -> void:
	var frags: Array = SaveManager.get_cipher_fragments()
	var header := Label.new()
	header.text = "Architect Cipher — %d/8" % frags.size()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 12)
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
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", Color(0.8, 0.75, 0.55))
		%CollectionLog.add_child(row)


## Combo Finishers codex (issue #8 Phase 2): 5 fixed rows. Undiscovered
## show "???" + hint, discovered show name + trigger. Compact, zero-scroll.
func _refresh_combo_codex() -> void:
	var found: Array = SaveManager.get_combos_discovered()
	var header := Label.new()
	header.text = "Combo Finishers — %d/5" % found.size()
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 12)
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
		row.add_theme_font_size_override("font_size", 11)
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


## Supermarket: update cash display.
func set_market_cash(cash: int, goal: int) -> void:
	%MarketLabel.text = "Cash: $%d / $%d" % [cash, goal]


func _on_stat_pressed(stat: String) -> void:
	if _player != null and _player.spend_point(stat):
		refresh_stats()


# --- Waves ---

func set_wave(info: Dictionary) -> void:
	var state := int(info.get("state", 0))
	var level := int(info.get("level", 1))
	var cycle := (level - 1) / 4
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
	%WaveLabel.text = "Lv %d · %s%s · Wave %d/%d" % [level, str(info.get("theme_name", "")), cycle_str, int(info.get("wave", 0)), int(info.get("total", 5))]
	# Supermarket mode: show cash instead of waves.
	var is_market := str(info.get("theme_id", "")) == "supermarket"
	%MarketLabel.visible = is_market
	if is_market:
		%WaveLabel.text = "Lv %d · %s%s" % [level, str(info.get("theme_name", "")), cycle_str]
		%WaveStatus.text = "Walk through CHECKOUT to sell loot and unlock the gate!"
		%NextWaveButton.visible = false
		return
	# Host-only Next Wave button during intermission.
	var is_host := multiplayer.is_server()
	%NextWaveButton.visible = is_host and state == 0
	match state:
		0: # intermission
			%WaveStatus.text = "Waiting for host..." if not is_host else "Press R to begin wave"
		1: # active
			%WaveStatus.text = "Mobs left: %d" % int(info.get("mobs_left", 0))
		_:
			var kn := int(info.get("keys_needed", 0))
			if kn > 0:
				%WaveStatus.text = "Keys: %d/%d" % [int(info.get("keys_found", 0)), kn]
			else:
				%WaveStatus.text = "Cleared!"


func announce(text: String, tint: Color = Color(1.0, 1.0, 1.0)) -> void:
	%AnnounceLabel.text = text
	%AnnounceLabel.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	%AnnounceLabel.scale = Vector2(1.25, 1.25)
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


## Boarding countdown (issue #3 Phase 2): ALL ABOARD window with the aboard
## roster. Reuses the station timer label — no new UI chrome.
func show_boarding_timer(sec: float, aboard_count: int, living_count: int) -> void:
	var s := int(ceil(maxf(sec, 0.0)))
	%StationTimerLabel.text = "ALL ABOARD — TRAIN LEAVES IN %d:%02d (%d/%d)" % [s / 60, s % 60, aboard_count, living_count]
	%StationTimerLabel.visible = true


## Ride status (issue #3 Phase 3): destination + arrival countdown. Reuses
## the station timer label — no new UI chrome. Hide via hide_station_timer.
func show_ride_status(title: String, sec: float) -> void:
	var s := int(ceil(maxf(sec, 0.0)))
	%StationTimerLabel.text = "%s — %d:%02d" % [title, s / 60, s % 60]
	%StationTimerLabel.visible = true


# --- Downed / revive (co-op) ---

func show_downed(seconds: float) -> void:
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


func hide_death_screen() -> void:
	%DeathPanel.visible = false


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
	%PickupPrompt.visible = text != ""
	%PickupPrompt.text = text


# --- Class ability bar ---

func refresh_abilities(p) -> void:
	for c in %AbilityBar.get_children():
		c.queue_free()
	if p == null:
		return
	for i in p.unlocked_abilities.size():
		var a: Dictionary = p.unlocked_abilities[i]
		var sid := String(a["id"])
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
			sb.bg_color = Color(0.08, 0.08, 0.1, 0.75) if i != p.selected_ability else Color(0.25, 0.2, 0.08, 0.9)
			sb.border_color = Color(0.8, 0.65, 0.25, 1.0) if i == p.selected_ability else Color(0.35, 0.35, 0.4, 0.8)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		slot.add_theme_stylebox_override("panel", sb)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		var key_l := Label.new()
		key_l.text = "[%s]" % String(a["key"])
		key_l.add_theme_font_size_override("font_size", 11)
		key_l.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
		key_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(key_l)
		var name_l := Label.new()
		name_l.text = "%s %s" % [String(a["name"]), p.rank_roman()]
		name_l.add_theme_font_size_override("font_size", 13)
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
			bar.custom_minimum_size = Vector2(90, 6)
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
			pips.add_theme_font_size_override("font_size", 10)
			pips.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(pips)
		# Status line: charges (warrior) or cooldown.
		var status_l := Label.new()
		status_l.add_theme_font_size_override("font_size", 11)
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
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			slot.add_theme_stylebox_override("panel", sb)
			var vb := VBoxContainer.new()
			vb.add_theme_constant_override("separation", 0)
			var key_l := Label.new()
			key_l.text = "[8]"
			key_l.add_theme_font_size_override("font_size", 11)
			key_l.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
			key_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(key_l)
			var name_l := Label.new()
			name_l.text = String(sig["name"])
			name_l.add_theme_font_size_override("font_size", 13)
			name_l.add_theme_color_override("font_color", Color(0.95, 0.8, 1.0))
			name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(name_l)
			var status_l := Label.new()
			status_l.add_theme_font_size_override("font_size", 11)
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
			%AbilityBar.add_child(slot)


func _wave_number() -> int:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null and "wave" in dungeon:
		return int(dungeon.get("wave"))
	return 0

# --- Boss bar ---

func set_boss(boss_name: String, frac: float) -> void:
	%BossBar.visible = true
	%BossName.text = boss_name
	%BossHP.value = frac


func hide_boss() -> void:
	%BossBar.visible = false


# --- Inventory ---

func set_pickup_prompt(visible: bool, item_name: String) -> void:
	%PickupPrompt.visible = visible
	if visible:
		%PickupPrompt.text = "[E]  " + item_name


func toggle_inventory() -> void:
	%InventoryPanel.visible = not %InventoryPanel.visible
	if %InventoryPanel.visible and _player != null:
		refresh_inventory(_player)
	_layout_pause()


## Shift the pause panel left when the inventory is open so the two don't overlap.
func _layout_pause() -> void:
	var panel: PanelContainer = %PausePanel
	if %InventoryPanel.visible:
		panel.offset_left = -420.0
		panel.offset_right = 60.0
	else:
		panel.offset_left = -240.0
		panel.offset_right = 240.0


func refresh_inventory(p: Player) -> void:
	%InventoryList.clear()
	for i in p.inventory.size():
		var entry: Dictionary = p.inventory[i]
		var item := entry["item"] as ItemData
		var label := item.display_name
		if int(entry["count"]) > 1:
			label += " x%d" % int(entry["count"])
		if item.consumable:
			label = "[USE] " + label
		var idx: int = %InventoryList.add_item("%s  %s" % [label, _item_summary(item)])
		%InventoryList.set_item_custom_fg_color(idx, ItemData.rarity_color(item.rarity))


func _on_dispose_pressed() -> void:
	if _player == null:
		return
	var sel: PackedInt32Array = %InventoryList.get_selected_items()
	if sel.is_empty():
		toast("Select a stack first.")
		return
	_player.dispose_item(sel[0])


func _on_use_pressed() -> void:
	if _player == null:
		return
	var sel: PackedInt32Array = %InventoryList.get_selected_items()
	if sel.is_empty():
		toast("Select a stack first.")
		return
	_player.use_item(sel[0])


func _item_summary(item: ItemData) -> String:
	var parts: Array[String] = []
	if item.consumable:
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

