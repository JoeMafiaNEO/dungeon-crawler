class_name WeaponVisual
extends RefCounted
## Issue #113 Phase 2: procedural fallback world models for weapons
## whose real asset has not landed yet (the Art Director's 4-model
## list). Consumers prefer an item's world_model whenever one is set;
## these builders are the safety net so weapon coverage is complete
## in code regardless of asset timing — when the real model lands in
## the .tres, the fallback retires automatically.
##
## Props are built grip-at-origin, extending +Y, at pickup scale
## (~1.2-1.8 units tall, like the KayKit models) so the pickup
## measure/normalize pass and the held/viewmodel transforms apply
## unchanged.

const FALLBACK_IDS: Array[String] = ["storm_caller", "void_blade"]


static func has_fallback(item_id: String) -> bool:
	return FALLBACK_IDS.has(item_id)


static func build_fallback(item_id: String) -> Node3D:
	match item_id:
		"storm_caller":
			return build_storm_caller()
		"void_blade":
			return build_void_blade()
	return null


static func _mat(albedo: Color, emission := Color(0, 0, 0),
		energy := 0.0, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = 0.6
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


static func _mesh_inst(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi


static func build_storm_caller() -> Node3D:
	# A storm staff: dark bronze shaft, steel collar, four prongs
	# cupping a glowing cyan orb.
	var root := Node3D.new()
	root.name = "StormCallerProp"
	var bronze := _mat(Color(0.23, 0.16, 0.10))
	var steel := _mat(Color(0.45, 0.47, 0.52), Color(0, 0, 0), 0.0, 0.7)
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.030
	shaft_mesh.bottom_radius = 0.034
	shaft_mesh.height = 1.55
	root.add_child(_mesh_inst(shaft_mesh, bronze, Vector3(0, 0.825, 0)))
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.05
	cap_mesh.height = 0.10
	root.add_child(_mesh_inst(cap_mesh, steel, Vector3(0, 0.02, 0)))
	var collar_mesh := CylinderMesh.new()
	collar_mesh.top_radius = 0.055
	collar_mesh.bottom_radius = 0.055
	collar_mesh.height = 0.08
	root.add_child(_mesh_inst(collar_mesh, steel, Vector3(0, 1.56, 0)))
	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.105
	orb_mesh.height = 0.21
	var orb := _mesh_inst(orb_mesh,
		_mat(Color(0.35, 0.80, 1.0), Color(0.40, 0.85, 1.0), 2.2),
		Vector3(0, 1.70, 0))
	orb.name = "StormOrb"
	root.add_child(orb)
	var prong_mesh := BoxMesh.new()
	prong_mesh.size = Vector3(0.03, 0.24, 0.03)
	for i in 4:
		var a := float(i) * PI * 0.5
		var prong := _mesh_inst(prong_mesh, steel,
			Vector3(cos(a) * 0.075, 1.66, sin(a) * 0.075))
		prong.rotation = Vector3(sin(a) * 0.30, 0, -cos(a) * 0.30)
		root.add_child(prong)
	return root


static func build_void_blade() -> Node3D:
	# A void blade: black grip, dark steel guard, near-black blade
	# with a violet emissive core strip and a flattened pyramid tip.
	var root := Node3D.new()
	root.name = "VoidBladeProp"
	var dark := _mat(Color(0.05, 0.05, 0.07))
	var steel := _mat(Color(0.16, 0.15, 0.20), Color(0, 0, 0), 0.0, 0.6)
	var blade_mat := _mat(Color(0.07, 0.05, 0.11), Color(0, 0, 0), 0.0, 0.6)
	blade_mat.roughness = 0.35
	var grip_mesh := CylinderMesh.new()
	grip_mesh.top_radius = 0.026
	grip_mesh.bottom_radius = 0.026
	grip_mesh.height = 0.24
	root.add_child(_mesh_inst(grip_mesh, dark, Vector3(0, 0.12, 0)))
	var pommel_mesh := SphereMesh.new()
	pommel_mesh.radius = 0.045
	pommel_mesh.height = 0.09
	var pommel := _mesh_inst(pommel_mesh,
		_mat(Color(0.30, 0.12, 0.55), Color(0.45, 0.20, 0.90), 1.2),
		Vector3(0, 0.0, 0))
	pommel.name = "VoidPommel"
	root.add_child(pommel)
	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(0.24, 0.045, 0.06)
	root.add_child(_mesh_inst(guard_mesh, steel, Vector3(0, 0.26, 0)))
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.085, 0.78, 0.018)
	var blade := _mesh_inst(blade_mesh, blade_mat, Vector3(0, 0.67, 0))
	blade.name = "VoidBlade"
	root.add_child(blade)
	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(0.020, 0.70, 0.022)
	var core := _mesh_inst(core_mesh,
		_mat(Color(0.40, 0.16, 0.80), Color(0.55, 0.25, 1.0), 1.8),
		Vector3(0, 0.67, 0))
	core.name = "VoidCore"
	root.add_child(core)
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.045
	tip_mesh.height = 0.18
	tip_mesh.radial_segments = 4
	var tip := _mesh_inst(tip_mesh, blade_mat, Vector3(0, 1.15, 0))
	tip.rotation_degrees = Vector3(0, 45, 0)
	tip.scale = Vector3(1.0, 1.0, 0.25)
	root.add_child(tip)
	return root
