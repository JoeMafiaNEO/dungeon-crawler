class_name CipherPlaque
extends Node3D
## Weathered stone plaque hiding one Mason's Cipher poem.
## One spawns per dungeon level (server-side). Reading grants the reader's
## next uncollected fragment (local meta, no networking). Each machine tracks
## its own read state on its local instance; clients with all 8 hide plaques.

var _read_locally := false
var _granted_idx := -1
var _t := 0.0
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group("cipher_plaques")
	if SaveManager.get_cipher_fragments().size() >= CipherPoems.POEMS.size():
		visible = false
		return
	# Dark stone slab.
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 1.2, 0.2)
	slab.mesh = bm
	slab.position.y = 0.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.24, 0.22)
	slab.set_surface_override_material(0, mat)
	add_child(slab)
	# Faint gold light so it catches the eye in dark corners.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.position.y = 1.2
	add_child(light)
	# Ground ring, slow shimmer (totem ring-pulse idiom).
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.62
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(1.0, 0.85, 0.4, 0.5)
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.85, 0.4)
	rmat.emission_energy_multiplier = 1.2
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = rmat
	_ring.mesh = torus
	_ring.position.y = 0.06
	add_child(_ring)


func _process(delta: float) -> void:
	if not visible or _ring == null:
		return
	_t += delta
	var s := 1.0 + sin(_t * 2.2) * 0.06
	_ring.scale = Vector3(s, 1, s)


func prompt_text() -> String:
	return "Read weathered plaque"


func interact(player: Player) -> void:
	if player.hud == null:
		return
	# Re-reading shows the same poem again; never double-grants.
	if _read_locally and _granted_idx >= 0:
		player.hud.show_poem_popup(_granted_idx)
		return
	var idx := CipherPoems.next_fragment(SaveManager.get_cipher_fragments())
	if idx < 0:
		return  # already complete; plaques are hidden anyway
	_granted_idx = idx
	_read_locally = true
	SaveManager.add_cipher_fragment(idx)
	AudioManager.sfx("key")
	player.hud.show_poem_popup(idx)
