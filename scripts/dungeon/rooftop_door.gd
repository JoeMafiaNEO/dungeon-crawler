class_name RooftopDoor
extends Node3D
## Rooftop exit door (issue #203, P3 spec section 1 beat 5).
## Created in the annex hall AT the reveal beat — never before:
## a door standing in the hub from the start would be a clue the
## no-clues rule forbids (and the RTS top-down camera can see
## every pre-placed object near the arena). P3 creates it and
## makes it present; where it mechanically leads (the descent to
## the street) is the P4/P5 travel design, so using it does
## nothing yet — deliberately, like the Vault door's shape:
## plain, unsigned, a door and nothing more.


func _ready() -> void:
	add_to_group("rooftop_door")
	_build()


func prompt_text() -> String:
	return "Open the door"


func interact(_player: Player) -> void:
	# P4 wires the descent. In P3 the door is present, not a path.
	pass


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
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
	# Closed doors block: a plain body across the doorway.
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 2.6, 0.24)
	col.shape = box
	col.position = Vector3(0, 1.3, 0)
	body.add_child(col)
	add_child(body)
