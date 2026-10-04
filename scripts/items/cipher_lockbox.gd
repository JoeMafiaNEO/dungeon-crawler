class_name CipherLockbox
extends Node3D
## Brass lockbox on the supermarket level. Enter the mason's passphrase
## (decoded from all 8 cipher fragments) to unlock the Architect class.

var _t := 0.0
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("cipher_lockbox")
	# Brass box.
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.6, 0.6)
	box.mesh = bm
	box.position.y = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.55, 0.25)
	mat.metallic = 0.6
	mat.roughness = 0.4
	box.set_surface_override_material(0, mat)
	add_child(box)
	# Lock detail.
	var lock := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.18, 0.24, 0.1)
	lock.mesh = lm
	lock.position = Vector3(0, 0.35, 0.32)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.3, 0.25, 0.15)
	lock.set_surface_override_material(0, lmat)
	add_child(lock)
	# Subtle sparkle light.
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.9, 0.5)
	_light.light_energy = 1.0
	_light.omni_range = 5.0
	_light.position.y = 1.0
	add_child(_light)


func _process(delta: float) -> void:
	if _light == null:
		return
	_t += delta
	_light.light_energy = 1.0 + sin(_t * 3.0) * 0.25


func prompt_text() -> String:
	return "Open brass lockbox"


func interact(player: Player) -> void:
	if player.hud == null:
		return
	player.hud.show_lockbox_popup()
