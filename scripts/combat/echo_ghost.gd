class_name EchoGhost
extends Node3D
## EchoGhost: visual-only ghost playback for daily run echoes (issue #9 Phase 2).
##
## Replays a recorded echo timeline as a billboarded translucent sprite.
## STRICTLY visual: no CollisionShape (no collision), no damage dealt/taken,
## no AI targeting hooks, and it NEVER touches _server_rng or any gameplay
## RNG stream — it only interpolates recorded positions.

const GHOST_TEXTURE := "res://assets/sprites/ghosts/ghost_sample.png"
# Issue #56: bare EchoRecorder autoload identifier doesn't resolve in -s
# script mode (or --check-only). Load the script for static access; resolve
# the autoload node at runtime for instance methods.
const ERScript := preload("res://scripts/autoload/echo_recorder.gd")
const GHOST_ALPHA := 0.45

var _echo: Dictionary = {}
var _playing := false
var _clock := 0.0  # seconds since playback start
var _sprite: Sprite3D = null


func _ready() -> void:
	_sprite = Sprite3D.new()
	_sprite.texture = load(GHOST_TEXTURE) as Texture2D
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.no_depth_test = false
	_sprite.modulate = Color(1.0, 1.0, 1.0, GHOST_ALPHA)
	_sprite.pixel_size = 0.01
	add_child(_sprite)
	# Deliberately: no CollisionShape3D, no Area3D. Nothing can hit this,
	# and it can hit nothing.


func load_echo(path: String) -> bool:
	var er := get_tree().root.get_node_or_null("EchoRecorder")
	if er == null:
		# No autoload (e.g. -s test mode): use a throwaway instance.
		er = ERScript.new()
	_echo = er.call("load_echo", path)
	if er.get_parent() == null:
		er.free()
	return not _echo.is_empty()


func load_echo_data(data: Dictionary) -> bool:
	_echo = data
	return not _echo.is_empty()


func start() -> void:
	if _echo.is_empty():
		return
	_playing = true
	_clock = 0.0
	visible = true


func stop() -> void:
	_playing = false
	visible = false


func is_playing() -> bool:
	return _playing


func sample_count() -> int:
	return int(_echo.get("sample_count", 0))


func _process(delta: float) -> void:
	if not _playing or _echo.is_empty():
		return
	_clock += delta
	var samples: PackedByteArray = _echo.get("samples", PackedByteArray())
	var count := sample_count()
	if count == 0:
		return
	# Samples are 10Hz: tick t lives at t * 0.1 seconds.
	var f := _clock / ERScript.SAMPLE_INTERVAL
	if f >= float(count - 1):
		# Reached the end of the recording: hold the final pose.
		var last := ERScript.decode_sample(samples, count - 1)
		if not last.is_empty():
			global_position = last["pos"]
			rotation.y = last["yaw"]
		stop()
		return
	var i0 := int(f)
	var frac := f - float(i0)
	var s0 := ERScript.decode_sample(samples, i0)
	var s1 := ERScript.decode_sample(samples, i0 + 1)
	if s0.is_empty() or s1.is_empty():
		return
	# Pure interpolation of recorded data. No RNG anywhere in this path.
	global_position = (s0["pos"] as Vector3).lerp(s1["pos"] as Vector3, frac)
	var y0 := float(s0["yaw"])
	var y1 := float(s1["yaw"])
	rotation.y = y0 + wrapf(y1 - y0, -PI, PI) * frac
