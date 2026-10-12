class_name FishingRod
extends Node3D

const ROD_LENGTH := 2.2
const ROD_SEGMENTS := 12
const MAX_BEND := 0.55
const HANDLE_HEIGHT := 0.45

var _bend := 0.0
var _dirty := true
var _mesh: ImmediateMesh
var _tip: Node3D


func _ready() -> void:
	var handle := CylinderMesh.new()
	handle.top_radius = 0.035
	handle.bottom_radius = 0.045
	handle.height = HANDLE_HEIGHT
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.35, 0.22, 0.12, 1.0)
	var hmi := MeshInstance3D.new()
	hmi.mesh = handle
	hmi.material_override = hmat
	hmi.position = Vector3(0.0, HANDLE_HEIGHT * 0.5, 0.0)
	add_child(hmi)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.55, 0.6, 1.0)
	_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = mat
	add_child(mi)
	_tip = Node3D.new()
	_tip.name = "RodTip"
	add_child(_tip)
	_rebuild()
	_dirty = false


func set_bend(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	if not is_equal_approx(v, _bend):
		_bend = v
		_dirty = true


func get_bend() -> float:
	return _bend


func get_tip() -> Node3D:
	return _tip


func _process(_delta: float) -> void:
	if _dirty:
		_rebuild()
		_dirty = false


func _rebuild() -> void:
	var base_y := HANDLE_HEIGHT
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var tip_pos := Vector3(0.0, base_y, 0.0)
	for i in range(ROD_SEGMENTS + 1):
		var t := float(i) / float(ROD_SEGMENTS)
		var p := Vector3(
			_bend * MAX_BEND * t * t,
			base_y + t * ROD_LENGTH,
			0.0
		)
		_mesh.surface_add_vertex(p)
		tip_pos = p
	_mesh.surface_end()
	if _tip != null:
		_tip.position = tip_pos
