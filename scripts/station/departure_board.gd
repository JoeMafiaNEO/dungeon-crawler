class_name DepartureBoard
extends Node3D
## Station departure board prop. E-interact opens the destination vote UI.
## Built procedurally: pole + dark board + gold frame + DEPARTURES sign.


func _ready() -> void:
	add_to_group("departure_board")
	_build()


func prompt_text() -> String:
	return "Check departure board"


func interact(player: Player) -> void:
	if player.hud != null and player.hud.has_method("show_departure_board"):
		player.hud.show_departure_board()


func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
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
	var wood_dark := _mat(Color(0.32, 0.22, 0.14))
	var board_dark := _mat(Color(0.10, 0.10, 0.13))
	var gold := _mat(Color(0.85, 0.65, 0.25), Color(0.85, 0.60, 0.20), 0.8)
	# Pole.
	_box(Vector3(0.18, 3.2, 0.18), Vector3(0, 1.6, 0), wood_dark)
	# Dark board.
	_box(Vector3(2.6, 1.5, 0.10), Vector3(0, 2.9, 0), board_dark)
	# Gold frame: top/bottom/left/right trims.
	_box(Vector3(2.76, 0.10, 0.12), Vector3(0, 3.70, 0), gold)
	_box(Vector3(2.76, 0.10, 0.12), Vector3(0, 2.10, 0), gold)
	_box(Vector3(0.10, 1.70, 0.12), Vector3(-1.33, 2.90, 0), gold)
	_box(Vector3(0.10, 1.70, 0.12), Vector3(1.33, 2.90, 0), gold)
	# DEPARTURES sign (billboarded so it reads from anywhere on the platform).
	var label := Label3D.new()
	label.text = "DEPARTURES"
	label.font_size = 72
	label.modulate = Color(1.0, 0.82, 0.35)
	label.outline_size = 10
	label.position = Vector3(0, 2.9, 0.12)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
