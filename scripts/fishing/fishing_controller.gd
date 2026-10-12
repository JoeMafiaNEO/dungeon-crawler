class_name FishingController
extends Node3D

enum State { IDLE, CASTING, WAITING, REELING }

const CHARGE_TIME := 1.5
const MIN_CAST_DIST := 4.0
const MAX_CAST_DIST := 15.0
const REEL_SPEED := 3.0

var _state: int = State.IDLE
var _charge := 0.0
var _was_lmb := false
var _was_rmb := false

var _rod: FishingRod
var _line: FishingLine
var _bobber: Bobber


func _ready() -> void:
	_rod = FishingRod.new()
	add_child(_rod)
	_line = FishingLine.new()
	add_child(_line)
	_line.set_tip(_rod.get_tip())
	_bobber = Bobber.new()
	add_child(_bobber)
	_bobber.attach_to_line(_line)


func get_state() -> int:
	return _state


func get_charge() -> float:
	return _charge


func _process(delta: float) -> void:
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var lmb_pressed := lmb and not _was_lmb
	var lmb_released := _was_lmb and not lmb
	var rmb_pressed := rmb and not _was_rmb
	var rmb_released := _was_rmb and not rmb
	match _state:
		State.IDLE:
			_rod.set_bend(0.0)
			if lmb_pressed:
				_state = State.CASTING
				_charge = 0.0
		State.CASTING:
			if lmb:
				_charge = minf(1.0, _charge + delta / CHARGE_TIME)
				_rod.set_bend(_charge * 0.35)
			if lmb_released:
				_do_cast()
				_state = State.WAITING
		State.WAITING:
			_rod.set_bend(_line.get_tension() * 0.6)
			if rmb_pressed:
				_state = State.REELING
		State.REELING:
			if rmb:
				_line.reel_in(REEL_SPEED * delta)
				_rod.set_bend(_line.get_tension())
				if _line.is_fully_reeled():
					_state = State.IDLE
					_rod.set_bend(0.0)
			if rmb_released:
				_state = State.WAITING
	_was_lmb = lmb
	_was_rmb = rmb


func _do_cast() -> void:
	var tip_pos: Vector3 = _rod.get_tip().global_position
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3(0.0, 0.0, -1.0)
	fwd = fwd.normalized()
	var dist := lerpf(MIN_CAST_DIST, MAX_CAST_DIST, _charge)
	var target := tip_pos + fwd * dist
	target.y = 0.0
	var dir: Vector3 = (target - tip_pos).normalized()
	var speed := lerpf(7.0, 17.0, _charge)
	var vel := dir * speed + Vector3(0.0, lerpf(2.5, 5.5, _charge), 0.0)
	_line.release_to(target, vel)
	_rod.set_bend(0.15)
