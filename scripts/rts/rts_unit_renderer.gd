class_name RTSUnitRenderer
extends Node3D
## Jesse 2026-10-11: MultiMesh renderer for RTS units. Replaces thousands
## of individual Sprite3D draw calls with one draw call per unit type.
## Units register on spawn; the renderer updates instance transforms each
## frame from the spatial hash. Per-instance color carries the faction tint.

# unit_type -> MultiMeshInstance3D
var _meshes: Dictionary = {}
# unit_type -> Array[RTSUnit] (parallel to multimesh instances)
var _units: Dictionary = {}
var _mgr: RTSManager = null


func _ready() -> void:
	add_to_group("rts_unit_renderer")
	_mgr = get_tree().get_first_node_in_group("rts_manager") as RTSManager


func _process(_delta: float) -> void:
	if _mgr == null:
		return
	_update_instances()


## Register a unit for multimesh rendering. Hides its individual sprite.
func register_unit(unit: Node3D) -> void:
	var utype := str(unit.get("unit_type"))
	if not _meshes.has(utype):
		_create_mesh(utype, unit)
	(_units[utype] as Array).append(unit)
	# Hide the individual sprite — the multimesh draws it now.
	var sprite = unit.get("_sprite")
	if sprite != null and is_instance_valid(sprite):
		(sprite as Node3D).visible = false


func unregister_unit(unit: Node3D) -> void:
	var utype := str(unit.get("unit_type"))
	if not _units.has(utype):
		return
	(_units[utype] as Array).erase(unit)
	# Restore individual sprite (in case multimesh is disabled later).
	var sprite = unit.get("_sprite")
	if sprite != null and is_instance_valid(sprite):
		(sprite as Node3D).visible = true


func _create_mesh(utype: String, sample_unit: Node3D) -> void:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	# Quad with the unit's texture.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	var sprite = sample_unit.get("_sprite")
	if sprite != null:
		var tex: Texture2D = sprite.get("texture")
		mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Billboard via shader would be ideal; for now we bake orientation
	# into the instance transform each frame.
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = 0
	mmi.multimesh = mm
	add_child(mmi)
	_meshes[utype] = mmi
	_units[utype] = []


func _update_instances() -> void:
	# Check if command view is active (flat) or FPS (upright).
	var flat := false
	var cam := get_tree().get_first_node_in_group("rts_camera")
	if cam != null and bool(cam.get("active")):
		flat = true
	# For FPS view, get the active camera for Y-billboarding.
	var fps_cam: Camera3D = null
	if not flat:
		fps_cam = get_viewport().get_camera_3d()
	for utype in _meshes:
		var mmi: MultiMeshInstance3D = _meshes[utype]
		var mm: MultiMesh = mmi.multimesh
		var arr: Array = _units[utype]
		# Compact out dead/freed units.
		var live: Array = []
		for u in arr:
			if is_instance_valid(u) and bool(u.get("alive")):
				live.append(u)
		_units[utype] = live
		mm.instance_count = live.size()
		for i in live.size():
			var u: Node3D = live[i]
			var pos: Vector3 = u.global_position + Vector3(0, 0.45, 0)
			var t := Transform3D()
			if flat:
				# Flat: rotate quad to face up, feet toward screen bottom.
				t = t.rotated(Vector3(1, 0, 0), PI / 2)
				t = t.rotated(Vector3(0, 0, 1), PI)
			elif fps_cam != null:
				# Y-billboard: yaw to face the camera.
				var to_cam: Vector3 = fps_cam.global_position - pos
				to_cam.y = 0
				if to_cam.length_squared() > 0.001:
					var yaw := atan2(to_cam.x, to_cam.z)
					t = t.rotated(Vector3(0, 1, 0), yaw)
			t.origin = pos
			mm.set_instance_transform(i, t)
			# Faction tint.
			var faction := int(u.get("faction"))
			mm.set_instance_color(i, RTSManager.faction_color(faction))
