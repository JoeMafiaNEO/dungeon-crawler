extends Node
## Issue #215 validation driver: the rendered-frame
## legs for the Deep Tree canvas UI (spec section 8 -
## suite-green alone does not carry a visual build).
## Boots a real dungeon with a fabricated mage, opens
## the canvas surface through the HUD's real open path,
## and captures five frames for the gate's eye:
##   (i)   the opening overview
##   (ii)  a branch zoom with labels (Fire, zoomed)
##   (iii) the detail panel on a purchasable node
##   (iv)  a locked-branch view on a fresh character
##   (v)   a search highlight ("Fireball")
##
## Run under Xvfb (never --headless - the standing
## scene-check rule):
##   xvfb-run -a godot --path . res://tools/tree_canvas_check/tree_canvas_check.tscn -- --shot-dir=/home/hatch/workspace/deep-tree-ui-shots
##
## This is a test harness only. Nothing here ships in
## gameplay.

const DeepTree := preload(
	"res://scripts/progression/deep_tree.gd")

var _shot_dir := "/home/hatch/workspace/deep-tree-ui-shots"
var _hud: Node = null
var _canvas: Node = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	get_window().size = Vector2i(1280, 720)
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method(
			"set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	await get_tree().process_frame
	NetworkManager.selected_class_id = "mage"
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "dungeon"
	Dungeon.next_seed = 424242
	Dungeon.next_level_number = 1
	var packed := load(
		"res://scenes/dungeon/dungeon.tscn") as PackedScene
	var dgn = packed.instantiate()
	get_tree().root.add_child(dgn)
	get_tree().current_scene = dgn
	for i in 16:
		await get_tree().physics_frame
	var player = dgn.call("_my_player")
	if player == null:
		print("[TREE] FAIL: no player")
		get_tree().quit(1)
		return
	# Fabricated mid-progress mage.
	player.set("family_collection",
		{"fire": {"signature": true},
			"frost": {"signature": true}})
	player.set("tree_lifetime",
		{"fireball": 500.0, "frost": 300.0})
	player.set("level", 30)
	var owned: Array = []
	for r in range(1, 7):
		owned.append(DeepTree.pack_id(1, r, 0))
	player.set("tree_owned", owned)
	player.call("_recompute_tree_aggregates")
	_hud = player.get("hud")
	if _hud == null:
		print("[TREE] FAIL: no hud")
		get_tree().quit(1)
		return
	_hud.call("open_deep_tree", false)
	for i in 30:
		await get_tree().process_frame
	_canvas = _hud.get("_tree_surface")
	if _canvas == null or not _canvas.visible:
		print("[TREE] FAIL: surface did not open")
		get_tree().quit(1)
		return
	print("[TREE] canvas size=", _canvas.size,
		" pos=", _canvas.position, " idx=",
		_canvas.get_index(), " hud children=",
		_hud.get_child_count(), " zoom=",
		_canvas.get("_zoom"), " cam=",
		_canvas.get("_cam_offset"), " nodes=",
		(_canvas.get("_built")["nodes"] as
			Array).size())
	await _snap("01_overview")
	# (ii) Fire branch zoom with labels.
	var cv = load("res://scripts/ui/deep_tree_canvas.gd")
	_canvas.set("_cam_offset", cv.layout_pos("mage",
		DeepTree.TREE_SEED, 1, 3, 0))
	_canvas.set("_zoom", 1.6)
	_canvas.queue_redraw()
	for i in 20:
		await get_tree().process_frame
	await _snap("02_fire_zoom")
	# (iii) Detail panel on a purchasable node: the
	# fire frontier (ring 7 spine - parent ring 6 owned).
	_canvas.call("_select", DeepTree.pack_id(1, 7, 0))
	_canvas.set("_cam_offset", cv.layout_pos("mage",
		DeepTree.TREE_SEED, 1, 7, 0))
	_canvas.set("_zoom", 1.3)
	_canvas.queue_redraw()
	for i in 20:
		await get_tree().process_frame
	await _snap("03_detail_purchasable")
	# (iv) Fresh character: every branch locked.
	player.set("family_collection", {})
	player.set("tree_owned", [])
	player.set("tree_lifetime", {})
	player.set("level", 1)
	player.call("_recompute_tree_aggregates")
	_canvas.call("rebuild")
	_canvas.call("_fit_camera")
	_canvas.call("_select", -2)
	for i in 20:
		await get_tree().process_frame
	await _snap("04_locked_fresh")
	# (v) Search highlight on the mid fixture again.
	player.set("family_collection",
		{"fire": {"signature": true},
			"frost": {"signature": true}})
	player.set("tree_lifetime",
		{"fireball": 500.0, "frost": 300.0})
	player.set("level", 30)
	player.set("tree_owned", owned)
	player.call("_recompute_tree_aggregates")
	_canvas.call("rebuild")
	_canvas.call("_on_search_changed", "Fireball")
	_canvas.set("_ease_to", {})
	_canvas.set("_cam_offset", _canvas.call(
		"_entry_pos", DeepTree.pack_id(1, 1, 0)))
	_canvas.queue_redraw()
	for i in 20:
		await get_tree().process_frame
	await _snap("05_search")
	print("[TREE] SUMMARY: frames captured to ",
		_shot_dir)
	get_tree().quit(0)


func _snap(label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join("tree_%s.png" % label)
	if img.save_png(path) == OK:
		print("[TREE] saved ", path)
	else:
		print("[TREE] FAIL saving ", path)
