class_name WarlordResults
extends CanvasLayer
## Standalone Warlord results screen (issue #266 P1, spec §3.7).
##
## Built by the match controller from the host's match_results
## payload: per-faction stats table (winner first, then elimination
## order) + chronological match timeline. Fit-to-screen by design —
## no scrolling unless Jesse approves it. Buttons hand teardown to
## the controller (Return to Lobby / Quit to Menu).

var _controller: Node = null
## Issue #266 P2: set by the match controller for an editor playtest —
## the exit reads "Return to Editor" and the menu button hides (both
## controller exits return to the editor in that mode).
var playtest_mode := false


func setup(payload: Dictionary, controller: Node) -> void:
	_controller = controller
	layer = 50
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	# CenterContainer, not PRESET_CENTER on the panel: the preset
	# anchors at the viewport centre with the panel's (then empty)
	# size, so the panel grows down-right off the screen instead of
	# staying centred. The container centres the finished panel.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.13, 0.97)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.62, 0.75)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	var winner := int(payload.get("winner", -1))
	var title := Label.new()
	if winner >= 0:
		title.text = "VICTORY — Faction %d" % winner
		title.add_theme_color_override("font_color", RTSManager.faction_color(winner))
	else:
		title.text = "DRAW — no faction remains"
		title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var dur := Label.new()
	dur.text = "Match duration %s" % _fmt_time(float(payload.get("duration_sec", 0.0)))
	dur.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dur)
	vbox.add_child(_build_stats_table(payload))
	vbox.add_child(_build_timeline(payload))
	var secondary := _build_secondary_line(payload)
	if not secondary.is_empty():
		var sl := Label.new()
		sl.text = secondary
		sl.add_theme_font_size_override("font_size", 13)
		sl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
		vbox.add_child(sl)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	vbox.add_child(buttons)
	var to_lobby := Button.new()
	to_lobby.text = "Return to Editor" if playtest_mode else "Return to Lobby"
	to_lobby.pressed.connect(_on_return_to_lobby)
	buttons.add_child(to_lobby)
	var to_menu := Button.new()
	to_menu.text = "Quit to Menu"
	to_menu.pressed.connect(_on_quit_to_menu)
	to_menu.visible = not playtest_mode
	buttons.add_child(to_menu)


func _build_stats_table(payload: Dictionary) -> GridContainer:
	var grid := GridContainer.new()
	# 12 columns: the first holds the faction color chip (blank header),
	# the rest match the row cells (Faction, Pl, Trained, Killed, Lost,
	# Built, Dest., Lost, Res, Age, Peak).
	grid.columns = 12
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	for h in ["", "Faction", "Pl", "Trained", "Killed", "Lost", "Built", "Dest.", "Lost", "Res", "Age", "Peak"]:
		var hl := Label.new()
		hl.text = h
		hl.add_theme_font_size_override("font_size", 13)
		hl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.78))
		grid.add_child(hl)
	var placements: Array = payload.get("placements", [])
	var stats: Dictionary = payload.get("stats", {})
	for entry in placements:
		var e: Dictionary = entry
		var fid := int(e.get("faction", -1))
		var st: Dictionary = stats.get(fid, {})
		var chip := ColorRect.new()
		chip.color = RTSManager.faction_color(fid)
		chip.custom_minimum_size = Vector2(14, 14)
		grid.add_child(chip)
		var fl := Label.new()
		fl.text = "Faction %d" % fid
		grid.add_child(fl)
		var pl := Label.new()
		pl.text = str(int(e.get("placement", 0)))
		grid.add_child(pl)
		var trained: Dictionary = st.get("units_trained", {})
		var total_trained := 0
		var type_bits: Array[String] = []
		for ut in trained:
			var c := int(trained[ut])
			total_trained += c
			type_bits.append("%s %d" % [str(ut), c])
		# Single line: the breakdown rides in parens after the total.
		# A two-line cell doubles every row's height and breaks
		# fit-to-screen on a full match.
		var tr := Label.new()
		tr.text = str(total_trained)
		if not type_bits.is_empty():
			tr.text += " (" + ", ".join(type_bits) + ")"
			tr.add_theme_font_size_override("font_size", 11)
		grid.add_child(tr)
		grid.add_child(_num_label(int(st.get("units_killed", 0))))
		grid.add_child(_num_label(int(st.get("units_lost", 0))))
		grid.add_child(_num_label(int(st.get("buildings_built", 0))))
		grid.add_child(_num_label(int(st.get("buildings_destroyed", 0))))
		grid.add_child(_num_label(int(st.get("buildings_lost", 0))))
		var res: Dictionary = st.get("resources_gathered", {})
		var total_res := 0
		var res_bits: Array[String] = []
		for rt in res:
			var c2 := int(res[rt])
			total_res += c2
			if c2 > 0:
				res_bits.append("%s %d" % [str(rt), c2])
		var rl := Label.new()
		rl.text = str(total_res)
		if not res_bits.is_empty():
			rl.text += " (" + ", ".join(res_bits) + ")"
			rl.add_theme_font_size_override("font_size", 11)
		grid.add_child(rl)
		var ages: Array = st.get("ages", [])
		var age_l := Label.new()
		if ages.is_empty():
			age_l.text = "0"
		else:
			var last: Dictionary = ages[ages.size() - 1]
			var times: Array[String] = []
			for a in ages:
				times.append(_fmt_time(float((a as Dictionary).get("t", 0.0))))
			age_l.text = "%d (%s)" % [int(last.get("age", 0)), ", ".join(times)]
		grid.add_child(age_l)
		var pk := Label.new()
		pk.text = "%d/%d" % [int(st.get("peak_population", 0)), int(st.get("peak_military", 0))]
		grid.add_child(pk)
	return grid


func _build_timeline(payload: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := Label.new()
	head.text = "Match timeline"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.65, 0.70, 0.78))
	box.add_child(head)
	var timeline: Array = payload.get("timeline", [])
	for ev in timeline:
		var e: Dictionary = ev
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var tl := Label.new()
		tl.text = _fmt_time(float(e.get("t", 0.0)))
		tl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.78))
		row.add_child(tl)
		if e.has("faction"):
			var chip := ColorRect.new()
			chip.color = RTSManager.faction_color(int(e.get("faction", 0)))
			chip.custom_minimum_size = Vector2(12, 12)
			row.add_child(chip)
		var txt := Label.new()
		txt.text = _event_text(e)
		row.add_child(txt)
		box.add_child(row)
	return box


func _build_secondary_line(payload: Dictionary) -> String:
	var stats: Dictionary = payload.get("stats", {})
	var bits: Array[String] = []
	for fid in stats:
		var st: Dictionary = stats[fid]
		var parts: Array[String] = []
		var tg := int(st.get("trade_gold", 0))
		var cv := int(st.get("conversions", 0))
		var ff := int(st.get("fish_food", 0))
		if tg > 0:
			parts.append("trade %dg" % tg)
		if cv > 0:
			parts.append("conversions %d" % cv)
		if ff > 0:
			parts.append("fish %d" % ff)
		if not parts.is_empty():
			bits.append("Faction %d: %s" % [int(fid), ", ".join(parts)])
	return " · ".join(bits)


func _event_text(e: Dictionary) -> String:
	var kind := str(e.get("event", ""))
	match kind:
		"match_start":
			var facs: Array = e.get("factions", [])
			return "Match started — %d factions" % facs.size()
		"age_up":
			return "Faction %d reached Age %d" % [int(e.get("faction", -1)), int(e.get("age", 0))]
		"first_blood":
			return "First blood: Faction %d destroyed Faction %d's unit" % [int(e.get("killer", -1)), int(e.get("victim", -1))]
		"town_hall_destroyed":
			if e.has("by"):
				return "Faction %d's Town Hall destroyed by Faction %d" % [int(e.get("faction", -1)), int(e.get("by", -1))]
			return "Faction %d's Town Hall destroyed" % int(e.get("faction", -1))
		"faction_eliminated":
			if e.has("by"):
				return "Faction %d eliminated by Faction %d" % [int(e.get("faction", -1)), int(e.get("by", -1))]
			return "Faction %d eliminated" % int(e.get("faction", -1))
		"match_end":
			var w := int(e.get("winner", -1))
			if w >= 0:
				return "Match ended — Faction %d wins" % w
			return "Match ended — draw"
	return kind


func _num_label(v: int) -> Label:
	var l := Label.new()
	l.text = str(v)
	return l


func _fmt_time(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [s / 60, s % 60]


func _on_return_to_lobby() -> void:
	if _controller != null and _controller.has_method("return_to_lobby"):
		_controller.call("return_to_lobby")


func _on_quit_to_menu() -> void:
	if _controller != null and _controller.has_method("quit_to_menu"):
		_controller.call("quit_to_menu")
