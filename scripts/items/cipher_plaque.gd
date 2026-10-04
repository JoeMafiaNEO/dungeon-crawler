class_name CipherPlaque
extends Node3D
## Parchment note hiding one Mason's Cipher poem.
## One spawns per dungeon level (server-side). Reading grants the reader's
## next uncollected fragment (local meta, no networking). Each machine tracks
## its own read state on its local instance; clients with all 8 hide notes.

var _read_locally := false
var _granted_idx := -1
var _t := 0.0
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group("cipher_plaques")
	if SaveManager.get_cipher_fragments().size() >= CipherPoems.POEMS.size():
		visible = false
		return
	# Parchment scroll: paper sheet on wooden rods, faint ink lines.
	var paper := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.7, 1.0, 0.03)
	paper.mesh = pm
	paper.position.y = 0.65
	paper.rotation.x = -0.06
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.93, 0.87, 0.72)
	pmat.roughness = 0.9
	paper.set_surface_override_material(0, pmat)
	add_child(paper)
	# Ink lines suggesting verse (4 thin + 1 bold cipher line).
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.25, 0.2, 0.15)
	for i in range(5):
		var line := MeshInstance3D.new()
		var lm := BoxMesh.new()
		var w := 0.5 - float(i % 3) * 0.08
		var h := 0.035 if i == 4 else 0.02
		lm.size = Vector3(w, h, 0.005)
		line.mesh = lm
		line.position = Vector3(0.0, 0.92 - float(i) * 0.16, 0.02)
		line.rotation.x = -0.06
		line.set_surface_override_material(0, ink)
		add_child(line)
	# Wooden scroll rods, top and bottom.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.2)
	wood.roughness = 0.8
	for ry in [1.18, 0.12]:
		var rod := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.05
		rm.bottom_radius = 0.05
		rm.height = 0.9
		rod.mesh = rm
		rod.rotation.z = PI / 2.0
		rod.position.y = ry
		rod.set_surface_override_material(0, wood)
		add_child(rod)
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
	return "Read old note"


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
