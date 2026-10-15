extends Node
## Issue #132 validation driver: the Host menu's Lobby tab must show
## what Host will actually create for the selected save. Seeds two MP
## saves into the isolated user:// (a legacy save whose lobby dict has
## NO visibility key, cap 12 — the M-5 repro shape — and a modern save
## stored public, cap 6), boots the REAL main menu, enters the Host
## Game tabs, clicks the save rows through the real toggled-signal
## path, and reads the Lobby tab controls after each selection:
##   fresh entry      -> menu defaults (Public / cap 4 / no password)
##   legacy selected  -> Friends Only / cap 12 / no password
##   public selected  -> Public / cap 6
##   back to legacy   -> Friends Only / cap 12 (re-derived both ways)
##   Fresh Run        -> menu defaults restored
## It also proves the derivation is display-only: the NetworkManager
## values fresh hosting consumes are never written by selecting saves.
##
## Run under Xvfb (real display driver, like the other menu checks):
##   xvfb-run godot --path . --resolution 1280x720 res://scenes/ui/host_lobby_prefill_check.tscn
## Env SHOT_PREFIX (before/after) names the screenshots in
## ~/workspace/issue132_shots/.
##
## This is a test harness only. Nothing here ships in gameplay.

var _pass := 0
var _fail := 0
var _menu: Control = null
var _shot_dir := "/home/hatch/workspace/issue132_shots"


func _ready() -> void:
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	_seed_saves()
	# The menu is instanced by the check scene itself (see the .tscn):
	# a Control instanced into an already-running tree never receives a
	# layout size in this harness, so it must be part of the startup
	# scene to render (and be screenshot-able) for real.
	_menu = get_node("MainMenu") as Control
	await get_tree().process_frame
	await get_tree().process_frame
	await _run_checks()
	_finish()


func _seed_saves() -> void:
	var legacy_run := {
		"theme_id": "village", "level_number": 1, "seed": 42,
		"is_multiplayer": true,
		"lobby": {"max_players": 12, "lobby_name": "Legacy"},
		"roster": [{"steam_id": 111, "player_name": "Host", "class_id": "mage",
			"player_state": {"level": 7}, "is_host": true}],
	}
	var public_run := {
		"theme_id": "village", "level_number": 1, "seed": 43,
		"is_multiplayer": true,
		"lobby": {"max_players": 6, "lobby_name": "Pub", "visibility": "public"},
		"roster": [{"steam_id": 111, "player_name": "Host", "class_id": "mage",
			"player_state": {"level": 7}, "is_host": true}],
	}
	_check(SaveManager.save_run(legacy_run, SaveManager.MODE_MP, 0), "legacy fixture saved to slot 0")
	_check(SaveManager.save_run(public_run, SaveManager.MODE_MP, 1), "public fixture saved to slot 1")
	var loaded: Dictionary = SaveManager.load_run(SaveManager.MODE_MP, 0)
	_check(not (loaded.get("lobby", {}) as Dictionary).has("visibility"),
		"legacy fixture really has no visibility key")


func _lobby_page() -> Control:
	var tabs = _menu.get_node("%HostPhase/HostTabs")
	return tabs.get_child(2) as Control


func _vis_button(text: String) -> Button:
	for b in _lobby_page().find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


func _cap_slider() -> HSlider:
	var found = _lobby_page().find_children("*", "HSlider", true, false)
	return found[0] as HSlider if not found.is_empty() else null


func _cap_val() -> Label:
	return _lobby_page().find_child("CapVal", true, false) as Label


func _pw_toggle() -> CheckButton:
	for c in _lobby_page().find_children("*", "CheckButton", true, false):
		if (c as CheckButton).text == "Use password":
			return c as CheckButton
	return null


func _save_row_button(slot: int) -> Button:
	# Save rows live in the menu's host save list: the Fresh Run button
	# is a direct child; each save row is an HBox whose first button is
	# the slot toggle.
	var list = _menu.get("_host_save_list") as VBoxContainer
	for child in list.get_children():
		if child is HBoxContainer:
			for b in child.get_children():
				if b is Button and (b as Button).text.begins_with("Slot %d:" % (slot + 1)):
					return b as Button
	return null


func _fresh_button() -> Button:
	var list = _menu.get("_host_save_list") as VBoxContainer
	for child in list.get_children():
		if child is Button and (child as Button).text.begins_with("Fresh Run"):
			return child as Button
	return null


func _expect_state(label: String, vis_text: String, cap: int) -> void:
	var vis_ok := false
	for t in ["Public", "Friends Only", "Private"]:
		var b := _vis_button(t)
		if b != null and b.button_pressed:
			vis_ok = (t == vis_text)
	var slider := _cap_slider()
	var val := _cap_val()
	_check(vis_ok, "%s: visibility shows %s" % [label, vis_text])
	_check(slider != null and int(slider.value) == cap and val != null and val.text == str(cap),
		"%s: cap shows %d (slider %s, label %s)" % [label, cap,
			str(int(slider.value)) if slider != null else "?", val.text if val != null else "?"])


func _shot(name: String) -> void:
	var prefix := OS.get_environment("SHOT_PREFIX")
	if prefix == "":
		prefix = "run"
	# Let layout + several presented frames settle, then capture after
	# the frame that actually drew (a bare process_frame await can grab
	# the still-empty viewport texture and save a black image).
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [_shot_dir, prefix, name]
	img.save_png(path)
	print("  shot: %s center_px=%s" % [path, img.get_pixel(img.get_width() / 2, img.get_height() / 2)])


func _run_checks() -> void:
	NetworkManager.host_save_slot = -1
	NetworkManager.lobby_visibility = "public"
	NetworkManager.lobby_player_cap = 4
	NetworkManager.lobby_password = ""
	_menu.call("_on_host_pressed")
	await get_tree().process_frame
	var tabs = _menu.get_node("%HostPhase/HostTabs")
	tabs.current_tab = 2
	_expect_state("fresh entry", "Public", 4)
	_check(not _pw_toggle().button_pressed, "fresh entry: password toggle off")

	# Click the legacy save row (real toggled-signal path).
	var legacy_btn := _save_row_button(0)
	_check(legacy_btn != null, "legacy save row exists")
	legacy_btn.button_pressed = true
	await get_tree().process_frame
	_expect_state("legacy selected", "Friends Only", 12)
	_check(not _pw_toggle().button_pressed,
		"legacy selected: password toggle off (no password is stored or applied)")
	await _shot("lobby_legacy")

	# Switch to the public save.
	_save_row_button(1).button_pressed = true
	await get_tree().process_frame
	_expect_state("public selected", "Public", 6)

	# Back to legacy — derivation runs both ways.
	_save_row_button(0).button_pressed = true
	await get_tree().process_frame
	_expect_state("legacy re-selected", "Friends Only", 12)

	# Fresh Run restores the menu's own defaults.
	_fresh_button().button_pressed = true
	await get_tree().process_frame
	_expect_state("fresh re-selected", "Public", 4)

	# Display-only: selecting saves never wrote the fresh-host values.
	_check(NetworkManager.lobby_visibility == "public" and NetworkManager.lobby_player_cap == 4,
		"NetworkManager fresh-host values untouched by selection")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS: %s" % label)
	else:
		_fail += 1
		print("  FAIL: %s" % label)


func _finish() -> void:
	print("[HostLobbyPrefillCheck] %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
