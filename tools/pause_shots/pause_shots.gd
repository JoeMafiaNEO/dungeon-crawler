extends Node
## Pause-menu zero-scroll verification driver (issue #16). Run under Xvfb:
##   godot --path . res://tools/pause_shots/pause_shots.tscn --resolution 1920x1080 -- --shot-dir /tmp/pause_shots
## Instances the HUD standalone, opens the pause menu on each tab (Stats
## forced to the mage worst-case with AuraRow visible), screenshots, and
## prints a scrollbar audit. Cleans up user:// saves afterwards.

var _shot_dir := "/tmp/pause_shots"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	print("[PauseShots] output -> ", _shot_dir)
	var packed: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: CanvasLayer = packed.instantiate()
	get_tree().root.add_child.call_deferred(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	hud.show_pause()
	# Worst case: mage — AuraRow visible makes the Stats tab tallest.
	var aura := hud.get_node_or_null("%AuraRow")
	if aura != null:
		aura.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	_audit(hud, "stats")
	await _snap("pause_stats.png")
	hud.select_pause_tab(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_audit(hud, "spec")
	await _snap("pause_spec.png")
	hud.select_pause_tab(2)
	await get_tree().process_frame
	await get_tree().process_frame
	_audit(hud, "collection")
	await _snap("pause_collection.png")
	_cleanup_saves()
	print("[PauseShots] done")
	get_tree().quit()


## Programmatic scrollbar audit: report scroll mode + vbar visibility.
func _audit(hud: Node, tab: String) -> void:
	var scroll := hud.get_node_or_null("%PausePanel/PauseMain/PauseScroll") as ScrollContainer
	if scroll == null:
		print("[PauseShots] AUDIT[", tab, "]: no scroll node found")
		return
	var bar := scroll.get_v_scroll_bar()
	var vis := bar.visible if bar != null else false
	print("[PauseShots] AUDIT[", tab, "]: mode=", scroll.vertical_scroll_mode,
		" vbar_visible=", vis)


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir + "/" + name
	if img.save_png(path) == OK:
		print("[PauseShots] saved ", path)
	else:
		push_error("[PauseShots] FAILED to save " + path)


## Never leave save files behind an end-to-end driver run.
func _cleanup_saves() -> void:
	for f in ["user://solo_warrior.cfg", "user://solo_rogue.cfg",
			"user://solo_mage.cfg", "user://solo_architect.cfg",
			"user://savegame.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
			print("[PauseShots] cleaned ", f)
