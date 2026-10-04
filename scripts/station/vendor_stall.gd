class_name VendorStall
extends Node3D
## Station vendor stall (Train Station Phase 4). E-interact opens the vendor
## panel: 3 potions + 3 rotating items, bought with persistent run cash.
## Stock itself lives on the server in station.gd; this is the prop + prompt.


func _ready() -> void:
	add_to_group("vendor_stall")
	_build()


func prompt_text() -> String:
	return "Browse vendor"


func interact(player: Player) -> void:
	if player.hud != null and player.hud.has_method("show_vendor"):
		player.hud.show_vendor()


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
	var wood := _mat(Color(0.45, 0.32, 0.20))
	var wood_dark := _mat(Color(0.32, 0.22, 0.14))
	var awning := _mat(Color(0.65, 0.25, 0.20))
	# Table + posts + awning.
	_box(Vector3(3.0, 0.15, 1.4), Vector3(0, 0.85, 0), wood)
	for px in [-1.35, 1.35]:
		for pz in [-0.6, 0.6]:
			_box(Vector3(0.12, 2.4, 0.12), Vector3(px, 1.2, pz), wood_dark)
	_box(Vector3(3.4, 0.12, 1.8), Vector3(0, 2.5, 0), awning)
	# Cosmetic wares on the table: 3 little crates/bottles.
	var ware_colors := [Color(0.75, 0.30, 0.25), Color(0.30, 0.55, 0.85), Color(0.85, 0.70, 0.30)]
	for i in 3:
		_box(Vector3(0.35, 0.35, 0.35), Vector3(-0.9 + float(i) * 0.9, 1.10, 0),
			_mat(ware_colors[i], ware_colors[i], 0.6))
	# VENDOR sign (billboarded so it reads from anywhere on the platform).
	var label := Label3D.new()
	label.text = "VENDOR"
	label.font_size = 72
	label.modulate = Color(1.0, 0.85, 0.40)
	label.outline_size = 10
	label.position = Vector3(0, 3.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
