class_name RTSResourceNode
extends StaticBody3D
## Depletable resource node: wood (trees), food (bushes), gold (vein).

var resource_type: String = "wood"
var amount: int = 500


func setup(p_type: String, p_amount: int) -> void:
	resource_type = p_type
	amount = p_amount
	_build_visual()


func _build_visual() -> void:
	var mesh_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	match resource_type:
		"wood":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.3
			cyl.bottom_radius = 0.4
			cyl.height = 1.2
			mesh_inst.mesh = cyl
			mesh_inst.position.y = 0.6
			mat.albedo_color = Color(0.4, 0.25, 0.15)
		"food":
			var sph := SphereMesh.new()
			sph.radius = 0.5
			sph.height = 1.0
			mesh_inst.mesh = sph
			mesh_inst.position.y = 0.5
			mat.albedo_color = Color(0.3, 0.7, 0.3)
		"gold":
			var box := BoxMesh.new()
			box.size = Vector3(0.8, 0.6, 0.8)
			mesh_inst.mesh = box
			mesh_inst.position.y = 0.3
			mat.albedo_color = Color(0.9, 0.75, 0.2)
		"stone":
			var rock := BoxMesh.new()
			rock.size = Vector3(1.0, 0.8, 0.9)
			mesh_inst.mesh = rock
			mesh_inst.position.y = 0.4
			mesh_inst.rotation.y = 0.5
			mat.albedo_color = Color(0.55, 0.55, 0.58)
	mesh_inst.set_surface_override_material(0, mat)
	add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.5, 1.0)
	col.shape = shape
	col.position.y = 0.75
	add_child(col)


func gather(requested: int) -> int:
	if not multiplayer.is_server():
		return 0
	var actual := mini(requested, amount)
	amount -= actual
	if amount <= 0:
		# Schedule a respawn before freeing (server-side, broadcast via RPC).
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("schedule_node_respawn"):
			scene.schedule_node_respawn(resource_type)
		queue_free()
	return actual
