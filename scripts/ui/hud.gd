extends CanvasLayer
## Player HUD: health, XP, level, equipment, crosshair, toasts, pause menu.

var is_paused := false

var _player: Player
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


func _process(delta: float) -> void:
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
	# Hide the top-right wave cluster so it doesn't peek out behind the panel.
	%TopRight.visible = false
	_layout_pause()
	# Class switching is solo-only.
	%ClassButton.visible = multiplayer.get_peers().size() == 0


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
func _on_save_quit_pressed() -> void:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon != null and _player != null:
		var theme_id := str(dungeon.get("theme").get("theme_id")) if dungeon.get("theme") != null else "village"
		SaveManager.save_run({
			"theme_id": theme_id,
			"level_number": int(dungeon.get("level_number")),
			"class_id": _player.class_id,
			"player_state": _player.get_state(),
		})
	_on_quit_pressed()


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
	var can := _player.stat_points > 0
	%DmgPlus.disabled = not can
	%HpPlus.disabled = not can
	%SpdPlus.disabled = not can
	%AuraPlus.disabled = not can


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


func announce(text: String) -> void:
	%AnnounceLabel.text = text
	%AnnounceLabel.modulate.a = 1.0
	%AnnounceLabel.scale = Vector2(1.25, 1.25)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(%AnnounceLabel, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.tween_property(%AnnounceLabel, "scale", Vector2.ONE, 0.4)


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
	NetworkManager.play_solo()


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
		var slot := PanelContainer.new()
		var sb := StyleBoxFlat.new()
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
		vb.add_child(name_l)
		# Status line: charges (warrior) or cooldown.
		var status_l := Label.new()
		status_l.add_theme_font_size_override("font_size", 11)
		status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if p.class_id == "warrior":
			status_l.text = "x%d" % p.totem_charges if i == p.selected_ability else ""
			status_l.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		else:
			var cd: float = float(p.ability_cds.get(String(a["id"]), 0.0))
			if cd > 0.0:
				status_l.text = "%.0fs" % cd
				status_l.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
			elif String(a["id"]) == "eagle_eye" and p.eagle_eye_used_wave == _wave_number():
				status_l.text = "used"
				status_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		vb.add_child(status_l)
		slot.add_child(vb)
		slot.tooltip_text = String(a["desc"])
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
