class_name RelicVault
extends Node3D
## Relic Vault locker (issue #6 Phase 2). E-interact opens the vault panel:
## equip one special per run. Procedural gold-trimmed cabinet + the
## SNES locker sprite as its face, styled like the vendor stall.


func _ready() -> void:
	add_to_group("vault_locker")
	_build()


func prompt_text() -> String:
	return "Open relic vault"


func interact(player: Player) -> void:
	if player.hud != null and player.hud.has_method("show_vault"):
		AudioManager.sfx("vault_open")
		player.hud.show_vault()


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
	var wood_dark := _mat(Color(0.30, 0.21, 0.13))
	var gold := _mat(Color(0.85, 0.62, 0.20), Color(0.85, 0.62, 0.20), 0.35)
	# Plinth + gold trim frame the cabinet.
	_box(Vector3(2.0, 0.25, 1.0), Vector3(0, 0.125, 0), wood_dark)
	_box(Vector3(2.0, 0.08, 1.0), Vector3(0, 0.29, 0), gold)
	_box(Vector3(1.9, 2.0, 0.7), Vector3(0, 1.3, -0.08), wood_dark)
	# SNES locker sprite as the cabinet face (faces the hall, +z).
	var face := Sprite3D.new()
	face.texture = load("res://assets/sprites/props/vault_locker.png") as Texture2D
	face.pixel_size = 0.0011
	face.position = Vector3(0, 1.32, 0.28)
	add_child(face)
	# Warm glow so the gold reads in the hall light.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.80, 0.45)
	glow.light_energy = 0.55
	glow.omni_range = 4.0
	glow.position = Vector3(0, 2.0, 1.2)
	add_child(glow)
	# RELIC VAULT sign (billboarded so it reads from anywhere in the hall).
	var label := Label3D.new()
	label.text = "RELIC VAULT"
	label.font_size = 72
	label.modulate = Color(1.0, 0.85, 0.40)
	label.outline_size = 10
	label.position = Vector3(0, 2.85, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
