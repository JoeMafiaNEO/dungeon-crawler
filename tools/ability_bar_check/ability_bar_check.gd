extends Node
## Issue #233 rendered check: the AbilityBar for each
## of the three Q-cycle classes — slot numbers at the
## top of every slot, the class's activate hint in the
## strip under the bar. One frame per class.

const SHOT_DIR := "/home/hatch/workspace/ability-bar-shots"

var _frames := 0
var _hud: CanvasLayer = null
var _classes: Array = []
var _idx := -1
var _player: Node = null


func _roster(cid: String) -> Array:
	var out: Array = []
	for a in Player.class_abilities(cid):
		if int(a["unlock"]) <= 30:
			out.append(a)
	return out


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_classes = ["rogue", "warrior", "architect"]
	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)


func _show_class(cid: String) -> void:
	if _player != null:
		_player.free()
		_player = null
	_player = load("res://scenes/player/player.tscn"
		).instantiate()
	_player.set("class_id", cid)
	add_child(_player)
	_player.set("unlocked_abilities", _roster(cid))
	_player.set("selected_ability", 2)
	_hud.call("refresh_abilities", _player)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % 40 == 1 and _idx + 1 < _classes.size():
		_idx += 1
		_show_class(_classes[_idx])
	elif _frames % 40 == 30 and _idx >= 0:
		var cid: String = _classes[_idx]
		var img := get_viewport().get_texture().get_image()
		# Crop to the bottom band where the bar lives.
		var band := img.get_region(Rect2i(
			0, img.get_height() - 190, img.get_width(), 190))
		var path := SHOT_DIR.path_join("bar_%s.png" % cid)
		if band.save_png(path) == OK:
			print("[BAR233] saved ", path)
		else:
			print("[BAR233] FAIL saving ", path)
		if _idx == _classes.size() - 1:
			get_tree().quit(0)
