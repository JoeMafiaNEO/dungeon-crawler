class_name VaultDoor
extends Node3D
## Mason's Vault hub door (issue #201, P1 spec section 5).
## A plain, unsigned door in the hub wall: it exists only while
## the vault gate is open (the station owns its visibility), and
## using it — any living player, deliberate E-interact, the lever
## pattern — resolves a mason_vault departure through the
## station's identical chain. No label, no sign: secrecy is
## structural, exactly as the board row's absence kept it.


func _ready() -> void:
	add_to_group("vault_door")
	_build()


func prompt_text() -> String:
	return "Open the door"


func interact(_player: Player) -> void:
	var station := get_tree().get_first_node_in_group("station")
	if station != null and station.has_method("request_vault_entry"):
		station.rpc("request_vault_entry")


func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
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
	var frame := _mat(Color(0.30, 0.26, 0.20))
	var slab := _mat(Color(0.38, 0.30, 0.20))
	var iron := _mat(Color(0.18, 0.17, 0.20))
	# Frame: two jambs + a lintel, proud of the wall face.
	_box(Vector3(0.18, 2.6, 0.24), Vector3(-0.85, 1.3, 0), frame)
	_box(Vector3(0.18, 2.6, 0.24), Vector3(0.85, 1.3, 0), frame)
	_box(Vector3(1.9, 0.22, 0.24), Vector3(0, 2.62, 0), frame)
	# The slab itself: plain wood, one iron handle. Nothing else.
	_box(Vector3(1.5, 2.5, 0.10), Vector3(0, 1.25, -0.04), slab)
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.material = iron
	knob.mesh = sm
	knob.position = Vector3(0.58, 1.25, 0.06)
	add_child(knob)
