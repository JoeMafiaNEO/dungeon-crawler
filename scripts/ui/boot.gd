extends Control
## Issue #256: the boot loading screen — the game's
## first scene. The Act 1 cache warmer (#253) moved
## here: boot derives the home anchor, warms the
## starting railway's chunk set into the purely local
## WorldCache with visible progress, and hands off to
## the main menu. Warming is an optimization, never a
## gate: an empty anchor, or a pump that makes no
## progress for STALL_LIMIT_MSEC, proceeds to the menu
## anyway — the player is never trapped on this screen.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const CacheWarmer := preload(
	"res://scripts/world/cache_warmer.gd")
## The largest party footprint (Jesse's pin): the
## warlord grid caps at 96 (4 players), its cells are
## 2 m, so the reveal footprint is 192 m across. The
## anchor's center — and with it the whole target
## set — is footprint-independent; the rect only
## feeds the scatter suppress, where the largest
## footprint is the safe superset for every party.
const BOOT_FOOTPRINT := 192.0
const STALL_LIMIT_MSEC := 30000

var _warmer: Node = null
var _handed_off := false
var _last_done := -1
var _last_progress_msec := 0
var _bar: ProgressBar
var _status: Label


func _ready() -> void:
	_build_ui()
	_last_progress_msec = Time.get_ticks_msec()
	var anchor: Dictionary = Dungeon.compute_home_anchor(
		BOOT_FOOTPRINT)
	if anchor.is_empty():
		_proceed()
		return
	_warmer = CacheWarmer.new()
	_warmer.name = "CacheWarmer"
	add_child(_warmer)
	_warmer.call("setup",
		Vector2(float(anchor["anchor_x"]),
			float(anchor["anchor_z"])),
		Rect2(float(anchor["rect_x"]),
			float(anchor["rect_z"]),
			float(anchor["rect_w"]),
			float(anchor["rect_d"])),
		Callable())
	_update_progress()


func _process(_delta: float) -> void:
	if _handed_off or _warmer == null:
		return
	_warmer.call("pump_step")
	_update_progress()
	if bool(_warmer.call("is_done")):
		_proceed()
		return
	# The watchdog: progress is the warmer's done
	# count; a full stall stretch hands off anyway.
	var done := warm_progress().x
	var now := Time.get_ticks_msec()
	if done != _last_done:
		_last_done = done
		_last_progress_msec = now
	elif now - _last_progress_msec > STALL_LIMIT_MSEC:
		_proceed()


## The boot screen's own progress read (the warmer's
## read-only accessor): (completed, total).
func warm_progress() -> Vector2i:
	if _warmer == null:
		return Vector2i.ZERO
	return Vector2i(
		int(_warmer.call("progress_done")),
		int(_warmer.call("progress_total")))


func _proceed() -> void:
	if _handed_off:
		return
	_handed_off = true
	get_tree().change_scene_to_file(MENU_SCENE)


func _update_progress() -> void:
	var p := warm_progress()
	_bar.max_value = maxi(1, p.y)
	_bar.value = p.x
	_status.text = "%d / %d chunks" % [p.x, p.y]


func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.texture = preload(
		"res://assets/sprites/menu/menu_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)
	var logo := TextureRect.new()
	logo.texture = preload(
		"res://assets/sprites/ui/logo.png")
	logo.custom_minimum_size = Vector2(360, 120)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(logo)
	var label := Label.new()
	label.text = "Preparing the world…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color",
		Color(0.92, 0.94, 0.98))
	vbox.add_child(label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(420, 22)
	_bar.min_value = 0
	_bar.max_value = 1
	_bar.value = 0
	_bar.show_percentage = false
	vbox.add_child(_bar)
	_status = Label.new()
	_status.text = "0 / 0 chunks"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color",
		Color(0.75, 0.79, 0.88))
	vbox.add_child(_status)
