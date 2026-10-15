class_name Bobber
extends Node3D

const WATER_Y := 0.0
const REST_OFFSET := 0.12
const FLOAT_SNAP_DIST := 0.6

var _line: FishingLine = null
var _bob_phase := 0.0
var _bob_vel := 0.0
var _floating := false


func _ready() -> void:
	top_level = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.15, 0.1, 1.0)
	# Issue #139: unshaded — a lit bobber is a black dot in the
	# Docks' night shadow, and its 0.17 m bite plunge (the bite
	# cue's moving part) could not resolve at 15 m.
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var body := MeshInstance3D.new()
	body.mesh = sphere
	body.material_override = red
	add_child(body)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.015
	stick.bottom_radius = 0.015
	stick.height = 0.24
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.9, 1.0)
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var antenna := MeshInstance3D.new()
	antenna.mesh = stick
	antenna.material_override = white
	antenna.position = Vector3(0.0, 0.2, 0.0)
	add_child(antenna)


func attach_to_line(line: FishingLine) -> void:
	_line = line


func _process(delta: float) -> void:
	if _line == null:
		return
	var end: Vector3 = _line.get_end()
	if end.y < WATER_Y + FLOAT_SNAP_DIST:
		if not _floating:
			_floating = true
			_bob_vel = 0.0
		_bob_phase += delta * 2.2
		var target_y := WATER_Y + REST_OFFSET + sin(_bob_phase) * 0.05
		_bob_vel += (target_y - global_position.y) * 25.0 * delta
		_bob_vel *= exp(-3.5 * delta)
		var new_y: float = global_position.y + _bob_vel * delta
		global_position = Vector3(end.x, new_y, end.z)
	else:
		_floating = false
		global_position = end
