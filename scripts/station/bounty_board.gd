class_name BountyBoard
extends Node3D
## Bounty board prop (issue #7 Phase 2): a physical board in the annex hall
## next to the departure board, skinned with the art director's 16-bit SNES
## board art. E-interact opens the bounty panel
## (player.hud.show_bounty()): 3 fixed cards with name / target / reward /
## per-player progress bar / claimed state. The board face itself is flavor
## (baked poster text); the live bounty data lives in the panel.

const BOARD_W := 3.6
const BOARD_H := 2.4
const BOARD_ART := "res://assets/sprites/props/bounty_board.png"


func _ready() -> void:
	add_to_group("bounty_board")
	_build()


func prompt_text() -> String:
	return "Check bounties"


## E-interact: open the bounty panel. Parameter is untyped so UI harnesses
## can drive it with a lightweight test double (player.gd does not compile
## in -s test mode); only player.hud is touched.
func interact(player) -> void:
	if player != null and player.hud != null and player.hud.has_method("show_bounty"):
		player.hud.show_bounty()


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
	# Two posts.
	_box(Vector3(0.22, 3.0, 0.22), Vector3(-1.55, 1.5, 0), wood_dark)
	_box(Vector3(0.22, 3.0, 0.22), Vector3(1.55, 1.5, 0), wood_dark)
	# Board face: the SNES art on a quad (3:2 aspect like the texture).
	var face := MeshInstance3D.new()
	face.name = "BoardFace"
	var quad := QuadMesh.new()
	quad.size = Vector2(BOARD_W, BOARD_H)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_texture = load(BOARD_ART)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Slight emission so the pixel art reads at dusk.
	fmat.emission_enabled = true
	fmat.emission_texture = load(BOARD_ART)
	fmat.emission = Color(1, 1, 1)
	fmat.emission_energy_multiplier = 0.35
	quad.material = fmat
	face.mesh = quad
	face.position = Vector3(0, 1.9, 0)
	add_child(face)
	# Warm light so it reads at dusk.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 0.9
	light.omni_range = 6.0
	light.position = Vector3(0, 2.2, 1.4)
	add_child(light)
