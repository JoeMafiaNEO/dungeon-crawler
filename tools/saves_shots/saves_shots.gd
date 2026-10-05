extends Node
## Saves UI screenshot driver (issue #4 Phase 5). Run under Xvfb:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --headless --path . \
##     --resolution 1920x1080 res://tools/saves_shots/saves_shots.tscn \
##     -- --shot-dir /tmp/saves_shots
## Creates scratch saves (solo slots 0/2 occupied, mp slot 1 occupied),
## screenshots SoloPhase / MultiPhase / the overwrite modal, runs the
## ScrollContainer audit, then removes every file it created and restores
## backups. Never leaves test data in user://.

var _shot_dir := "/tmp/saves_shots"
var _backups := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shot-dir" and i + 1 < args.size():
			_shot_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	print("[SavesShots] output -> ", _shot_dir)
	_backup_and_seed()
	var packed := load("res://scenes/ui/main_menu.tscn") as PackedScene
	var menu := packed.instantiate()
	# Root is still setting up children inside _ready: defer the add.
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(menu) or menu.get_parent() == null:
		push_error("[SavesShots] menu failed to enter the tree")
		_restore()
		get_tree().quit()
		return
	# Solo saves screen: slots 1 + 3 occupied, slot 2 empty.
	menu._on_solo_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("saves_solo.png")
	_audit(menu, "SoloPhase")
	# Multiplayer saves screen: slot 2 occupied, slots 1 + 3 empty.
	menu._on_multi_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("saves_multi.png")
	_audit(menu, "MultiPhase")
	# Overwrite-confirm modal over an occupied solo slot.
	menu._show_overwrite_confirm(SaveManager.MODE_SOLO, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("saves_overwrite_modal.png")
	_audit(menu, "OverwriteModal")
	menu._on_overwrite_cancelled()
	_restore()
	print("[SavesShots] done; user:// restored")
	get_tree().quit()


func _backup_and_seed() -> void:
	var paths := ["user://profile_local.cfg"]
	for mode in ["solo", "mp"]:
		for slot in range(3):
			paths.append("user://runs/%s_%d.cfg" % [mode, slot])
	for p in paths:
		if FileAccess.file_exists(p):
			_backups[p] = FileAccess.get_file_as_bytes(p)
			DirAccess.remove_absolute(p)
	DirAccess.make_dir_recursive_absolute("user://runs")
	var ok := true
	ok = ok and SaveManager.save_run({"theme_id": "dungeon", "level_number": 3,
		"seed": 111, "is_multiplayer": false, "class_id": "mage",
		"player_state": {"level": 12}}, SaveManager.MODE_SOLO, 0)
	ok = ok and SaveManager.save_run({"theme_id": "village", "level_number": 1,
		"seed": 222, "is_multiplayer": false, "class_id": "rogue",
		"player_state": {"level": 5}}, SaveManager.MODE_SOLO, 2)
	ok = ok and SaveManager.save_run({"theme_id": "warlord", "level_number": 4,
		"seed": 333, "is_multiplayer": true, "class_id": "mage", "roster": [
			{"steam_id": 111, "class_id": "mage", "player_state": {"level": 6}},
			{"steam_id": 222, "class_id": "rogue", "player_state": {"level": 5}},
		]}, SaveManager.MODE_MP, 1)
	print("[SavesShots] seeded scratch saves: ", ok)


func _restore() -> void:
	for p in _backups.keys():
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(_backups[p])
		f.close()
	# Remove any scratch files that have no backup.
	for mode in ["solo", "mp"]:
		for slot in range(3):
			var p := "user://runs/%s_%d.cfg" % [mode, slot]
			if not _backups.has(p) and FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
	if not _backups.has("user://profile_local.cfg") \
			and FileAccess.file_exists("user://profile_local.cfg"):
		DirAccess.remove_absolute("user://profile_local.cfg")


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir + "/" + file_name
	if img.save_png(path) == OK:
		print("[SavesShots] saved ", path)
	else:
		push_error("[SavesShots] FAILED to save " + path)


## Programmatic ScrollContainer audit: walk the live menu tree, flag any
## scroll container with a visible scrollbar (same method as the 2026-10-04
## scroll-verification pass).
func _audit(menu: Node, label: String) -> void:
	var total := 0
	var bad := 0
	var stack: Array = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is ScrollContainer:
			total += 1
			var sc := n as ScrollContainer
			if sc.get_h_scroll_bar().visible or sc.get_v_scroll_bar().visible:
				bad += 1
				print("[SavesShots] SCROLLBAR VISIBLE: ", sc.get_path())
		for c in n.get_children():
			stack.append(c)
	print("[SavesShots] audit %s: %d scroll containers, %d with visible scrollbars"
		% [label, total, bad])
