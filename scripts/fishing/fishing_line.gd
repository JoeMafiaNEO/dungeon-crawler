class_name FishingLine
extends Node3D

const POINT_COUNT := 24
const SEGMENTS := 23
const CONSTRAINT_ITERATIONS := 3
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const DAMPING := 0.985
const MIN_ROPE_LENGTH := 0.6

var rope_length := 0.8

var _points: PackedVector3Array = PackedVector3Array()
var _prev: PackedVector3Array = PackedVector3Array()
var _tip: Node3D = null
var _initialized := false
var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	top_level = true
	global_position = Vector3.ZERO
	_points.resize(POINT_COUNT)
	_prev.resize(POINT_COUNT)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.8, 0.65, 1.0)
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func set_tip(target: Node3D) -> void:
	_tip = target


func release_to(point: Vector3, vel: Vector3) -> void:
	if _tip == null:
		return
	var tip_pos: Vector3 = _tip.global_position
	rope_length = maxf(MIN_ROPE_LENGTH, tip_pos.distance_to(point))
	var dt := 1.0 / 60.0
	for i in range(POINT_COUNT):
		var t := float(i) / float(SEGMENTS)
		var p: Vector3 = tip_pos.lerp(point, t)
		_points[i] = p
		_prev[i] = p - vel * dt * (1.0 - t * 0.5)
	_initialized = true


func reel_in(amount: float) -> void:
	rope_length = maxf(MIN_ROPE_LENGTH, rope_length - amount)


func is_fully_reeled() -> bool:
	return rope_length <= MIN_ROPE_LENGTH + 0.05


func get_end() -> Vector3:
	if not _initialized or _tip == null:
		return global_position
	return _points[POINT_COUNT - 1]


func get_tension() -> float:
	if _tip == null or not _initialized:
		return 0.0
	var d: float = _tip.global_position.distance_to(_points[POINT_COUNT - 1])
	var stretch: float = d / maxf(rope_length, 0.001)
	return clampf((stretch - 0.75) / 0.25, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if _tip == null:
		return
	if not _initialized:
		_init_hang()
	var dt2 := delta * delta
	for i in range(1, POINT_COUNT):
		var v: Vector3 = (_points[i] - _prev[i]) * DAMPING
		_prev[i] = _points[i]
		_points[i] = _points[i] + v + GRAVITY * dt2
	_points[0] = _tip.global_position
	var rest := rope_length / float(SEGMENTS)
	for _iter in range(CONSTRAINT_ITERATIONS):
		_points[0] = _tip.global_position
		for i in range(SEGMENTS):
			_solve_segment(i, rest)


func _init_hang() -> void:
	var tip_pos: Vector3 = _tip.global_position
	var rest := rope_length / float(SEGMENTS)
	for i in range(POINT_COUNT):
		var p := tip_pos + Vector3(0.0, -rest * float(i), 0.0)
		_points[i] = p
		_prev[i] = p
	_initialized = true


func _solve_segment(i: int, rest: float) -> void:
	var a := _points[i]
	var b := _points[i + 1]
	var delta_p: Vector3 = b - a
	var dist := delta_p.length()
	if dist < 0.0001:
		return
	var diff := (dist - rest) / dist
	if i == 0:
		_points[i + 1] = b - delta_p * diff
	else:
		var corr := delta_p * (0.5 * diff)
		_points[i] = a + corr
		_points[i + 1] = b - corr


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if not _initialized:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(SEGMENTS):
		_mesh.surface_add_vertex(_points[i])
		_mesh.surface_add_vertex(_points[i + 1])
	_mesh.surface_end()
