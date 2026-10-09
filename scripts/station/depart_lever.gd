class_name DepartLever
extends Node3D
## Brass depart lever inside the boarding lobby (issue #93 Phase 3).
## E-interact (vendor pattern): any living player pulls it; the station's
## request_depart RPC validates server-side (vote resolved, not departing).


func _ready() -> void:
	add_to_group("depart_lever")
	_build()


func prompt_text() -> String:
	return "Pull the depart lever"


func interact(_player: Player) -> void:
	var station := get_tree().get_first_node_in_group("station")
	if station != null and station.has_method("request_depart"):
		station.rpc("request_depart")


func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


func _build() -> void:
	var iron := _mat(Color(0.18, 0.17, 0.20))
	var brass := _mat(Color(0.72, 0.55, 0.25), Color(0.72, 0.55, 0.25), 0.4)
	# Pedestal.
	_box(Vector3(0.35, 0.9, 0.35), Vector3(0, 0.45, 0), iron)
	_box(Vector3(0.45, 0.08, 0.45), Vector3(0, 0.94, 0), brass)
	# Angled handle + knob.
	var handle := _box(Vector3(0.09, 0.85, 0.09), Vector3(0, 1.3, 0), brass)
	handle.rotation_degrees.x = -28.0
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	sm.material = brass
	knob.mesh = sm
	knob.position = Vector3(0, 1.68, 0.20)
	add_child(knob)
	# DEPART sign above (billboarded so it reads from anywhere in the lobby).
	var label := Label3D.new()
	label.text = "DEPART"
	label.font_size = 64
	label.modulate = Color(1.0, 0.85, 0.40)
	label.outline_size = 10
	label.position = Vector3(0, 2.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
