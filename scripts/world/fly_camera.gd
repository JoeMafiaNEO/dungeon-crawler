extends Camera3D
## FlyCamera (issue #197): the world_test scene's fly rig — WASD +
## Q/E (or Space/Ctrl) for height, Shift boosts, click to capture
## the mouse for look, Esc releases. Deliberately NOT the game's
## player: no gameplay, no collision — Jesse flies it to watch
## chunks generate and cull around him.

const BASE_SPEED := 26.0
const BOOST_MULT := 6.0

var _yaw := 0.0
var _pitch := -0.3


func _ready() -> void:
	add_to_group("fly_rig")
	_pitch = rotation.x
	_yaw = rotation.y


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.0025
		_pitch = clampf(_pitch - mm.relative.y * 0.0025, -1.45, 1.45)
		rotation = Vector3(_pitch, _yaw, 0)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	var f := -global_transform.basis.z
	var r := global_transform.basis.x
	f.y = 0
	r.y = 0
	f = f.normalized()
	r = r.normalized()
	if Input.is_key_pressed(KEY_W):
		dir += f
	if Input.is_key_pressed(KEY_S):
		dir -= f
	if Input.is_key_pressed(KEY_D):
		dir += r
	if Input.is_key_pressed(KEY_A):
		dir -= r
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		dir -= Vector3.UP
	var speed := BASE_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= BOOST_MULT
	if dir != Vector3.ZERO:
		global_position += dir.normalized() * speed * delta
