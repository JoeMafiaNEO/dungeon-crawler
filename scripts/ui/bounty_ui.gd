class_name BountyUI
extends RefCounted
## Pure bounty UI builders (issue #7 Phase 2). No Player/tree/autoload
## dependencies, so unit tests can load this in -s mode (player.gd does not
## compile headless due to the SteamManager autoload).

const BountySys := preload("res://scripts/systems/bounty.gd")


## One fixed bounty card: name, desc, progress bar + state, reward line.
static func make_card(b: Dictionary, progress: Dictionary) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.name = "BountyCard_%s" % str(b.get("id", "?"))
	card.add_theme_constant_override("separation", 2)
	var nm := Label.new()
	nm.text = str(b.get("name", "Bounty"))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	card.add_child(nm)
	var desc := Label.new()
	desc.text = str(b.get("desc", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
	card.add_child(desc)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var target := int(b.get("target", 1))
	var cur := int(progress.get(str(b.get("id", "")), 0))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 14)
	bar.max_value = target
	bar.value = clampi(cur, 0, target)
	bar.show_percentage = false
	row.add_child(bar)
	var state := Label.new()
	state.add_theme_font_size_override("font_size", 13)
	if BountySys.is_failed(progress, b):
		state.text = "FAILED"
		state.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	elif BountySys.is_complete(progress, b):
		state.text = "DONE"
		state.add_theme_color_override("font_color", Color(0.45, 1.0, 0.5))
	else:
		state.text = "%d/%d" % [cur, target]
		state.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	row.add_child(state)
	card.add_child(row)
	var reward := Label.new()
	reward.text = "+$%d cash  ·  +%d XP" % [int(b.get("cash_reward", 0)), int(b.get("xp_reward", 0))]
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward.add_theme_font_size_override("font_size", 13)
	reward.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	card.add_child(reward)
	return card


## Compact tracker text: one short line per unsettled bounty, "" when none
## are active. Pure function of the bounty list + per-player progress.
static func tracker_text(bounties: Array, progress: Dictionary) -> String:
	var lines: Array[String] = []
	for b in bounties:
		if BountySys.is_complete(progress, b) or BountySys.is_failed(progress, b):
			continue
		var bid := str(b.get("id", ""))
		var cur := int(progress.get(bid, 0))
		lines.append("%s  %d/%d" % [str(b.get("name", "Bounty")), cur, int(b.get("target", 1))])
	return "\n".join(lines)
