extends Node
## Issue #17 Phase 2: CRT filter manager.
## Full-screen CRT shader on a CanvasLayer below UI (layer -10).
## Toggle persisted in profile ("settings", "crt_enabled", default true).

var _layer: CanvasLayer
var _rect: ColorRect
var _enabled := true


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = -10
	_layer.name = "CRTLayer"
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/crt.gdshader")
	_rect.material = mat
	_layer.add_child(_rect)
	# Apply persisted setting (SaveManager may not be ready yet; defer).
	call_deferred("_apply_saved")


func _apply_saved() -> void:
	if has_node("/root/SaveManager"):
		var sm := get_node("/root/SaveManager")
		_enabled = bool(sm.get_profile_setting("settings", "crt_enabled", true))
		_rect.visible = _enabled


func set_crt_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _rect != null:
		_rect.visible = enabled
	if has_node("/root/SaveManager"):
		get_node("/root/SaveManager").set_profile_setting("settings", "crt_enabled", enabled)


func is_crt_enabled() -> bool:
	return _enabled
