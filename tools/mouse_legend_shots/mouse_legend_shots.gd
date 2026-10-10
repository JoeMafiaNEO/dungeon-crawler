extends Node
## Issue #95 Phase 1 verification driver. Run under Xvfb:
##   godot --path . res://tools/mouse_legend_shots/mouse_legend_shots.tscn --resolution 1920x1080 -- --shot-dir /tmp/mls
## Renders the HUD for warrior and rogue, screenshots the bottom-right legend.
var _shot_dir := "/tmp/mls"

func _ready() -> void:
	var crt := "on"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--crt="):
			crt = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	# Issue #95 Phase 3: CRT legibility check. CRTManager is an autoload and
	# defaults enabled; the flag forces it off for the comparison shot.
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null:
		crt_mgr.set_crt_enabled(crt != "off")
		print("[MLS] crt_enabled=", crt_mgr.is_crt_enabled())
	var PlayerScript = load("res://scripts/player/player.gd")
	var p = PlayerScript.new()
	p.class_id = "warrior"
	p.level = 1
	var packed: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: CanvasLayer = packed.instantiate()
	get_tree().root.add_child.call_deferred(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	hud.refresh_mouse_legend(p)
	await get_tree().process_frame
	await _snap("legend_warrior.png")
	var panel = hud.get_node("MouseLegend")
	print("[MLS] warrior anchors: ", panel.anchor_left, ",", panel.anchor_top, " mouse_filter: ", panel.mouse_filter)
	print("[MLS] warrior left='", hud._legend_left.text, "' right_visible=", hud._legend_right.visible, " mid='", hud._legend_mid.text, "'")
	p.class_id = "rogue"
	hud.refresh_mouse_legend(p)
	await get_tree().process_frame
	await _snap("legend_rogue.png")
	print("[MLS] rogue left='", hud._legend_left.text, "' right_visible=", hud._legend_right.visible, " right='", hud._legend_right.text, "'")
	# Issue #95 Phase 2: dynamic states.
	p._charging = true
	hud.refresh_mouse_legend(p)
	await get_tree().process_frame
	await _snap("legend_rogue_charging.png")
	print("[MLS] charging left='", hud._legend_left.text, "' right='", hud._legend_right.text, "'")
	p._charging = false
	p.class_id = "mage"
	p._hl_state = PlayerScript.HLState.ARMED
	hud.refresh_mouse_legend(p)
	await get_tree().process_frame
	await _snap("legend_mage_hlarmed.png")
	print("[MLS] hl_armed left='", hud._legend_left.text, "' right='", hud._legend_right.text, "'")
	p._hl_state = PlayerScript.HLState.CHARGING
	hud.refresh_mouse_legend(p)
	await get_tree().process_frame
	await _snap("legend_mage_hlcharging.png")
	print("[MLS] hl_charging left_visible=", hud._legend_left.visible, " right='", hud._legend_right.text, "'")
	print("[MLS] done")
	get_tree().quit()

func _snap(name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir + "/" + name)
