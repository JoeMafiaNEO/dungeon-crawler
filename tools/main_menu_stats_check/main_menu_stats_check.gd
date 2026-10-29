extends Node
## Issue #234 rendered check: the main menu title
## stats line in both states — no revealed save (no
## buildings segment, no deepest cycle) and a
## revealed save present ("Buildings cleared: 7").

const SHOT_DIR := "/home/hatch/workspace/main-menu-shots"

var _frames := 0
var _menu: Node = null
var _phase := 0


func _instance_menu() -> void:
	if _menu != null:
		_menu.free()
	_menu = load("res://scenes/ui/main_menu.tscn"
		).instantiate()
	add_child(_menu)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_instance_menu()


func _process(_delta: float) -> void:
	_frames += 1
	if _phase == 0 and _frames == 40:
		_snap("menu_no_reveal.png")
		var sm = get_node("/root/SaveManager")
		sm.call("save_run", {"level": 6, "revealed": true,
			"buildings_cleared": 7}, "solo", 1)
		sm.call("save_run", {"level": 6, "revealed": false,
			"buildings_cleared": 99}, "solo", 2)
		_instance_menu()
		_phase = 1
	elif _phase == 1 and _frames == 80:
		_snap("menu_revealed.png")
		get_tree().quit(0)


func _snap(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := SHOT_DIR.path_join(fname)
	if img.save_png(path) == OK:
		print("[MENU234] saved ", path)
	else:
		print("[MENU234] FAIL saving ", path)
