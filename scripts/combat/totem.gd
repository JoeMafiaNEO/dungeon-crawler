class_name Totem
extends Node3D
## Warrior placeable. Pulsing aura that buffs allies or hinders enemies.
## Placed via RPC; each peer simulates visuals, server applies effects.

const RADIUS := 6.0
const DURATION := 20.0
const TICK := 1.0

var totem_id := ""
var owner_peer := 0
var rank := 1

var _life := DURATION
var _tick := 0.0
var _ring: MeshInstance3D


func setup(p_id: String, p_owner: int, p_rank: int = 1) -> void:
	totem_id = p_id
	owner_peer = p_owner
	rank = p_rank


func _ready() -> void:
	# Totem pole: stacked stone/wood.
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.4
	bc.bottom_radius = 0.5
	bc.height = 0.3
	base.mesh = bc
	base.position.y = 0.15
	_add_mat(base, Color(0.45, 0.42, 0.4))
	add_child(base)
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.18
	pc.bottom_radius = 0.22
	pc.height = 1.6
	pole.mesh = pc
	pole.position.y = 1.1
	_add_mat(pole, Color(0.5, 0.38, 0.22))
	add_child(pole)
	var top := MeshInstance3D.new()
	var ts := SphereMesh.new()
	ts.radius = 0.28
	ts.height = 0.56
	top.mesh = ts
	top.position.y = 2.1
	_add_mat(top, _color())
	var glow_mat := top.get_surface_override_material(0) as StandardMaterial3D
	if glow_mat != null:
		glow_mat.emission_enabled = true
		glow_mat.emission = _color()
		glow_mat.emission_energy_multiplier = 3.0
	add_child(top)
	# Colored light.
	var light := OmniLight3D.new()
	light.light_color = _color()
	light.light_energy = 1.5
	light.omni_range = RADIUS + 2.0
	light.position.y = 2.0
	add_child(light)
	# Ground ring showing the aura radius.
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.12
	torus.outer_radius = RADIUS
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = _color()
	rmat.emission_enabled = true
	rmat.emission = _color()
	rmat.emission_energy_multiplier = 1.5
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color.a = 0.6
	torus.material = rmat
	_ring.mesh = torus
	_ring.position.y = 0.1
	add_child(_ring)
	AudioManager.sfx("totem_place", global_position)


func _add_mat(mi: MeshInstance3D, c: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mi.set_surface_override_material(0, mat)


func _color() -> Color:
	match totem_id:
		"bulwark":
			return Color(0.4, 0.7, 1.0)
		"warhorn":
			return Color(1.0, 0.6, 0.2)
		"stoneskin":
			return Color(0.7, 0.65, 0.6)
		"rally":
			return Color(1.0, 0.9, 0.3)
		_:
			return Color(0.4, 1.0, 0.5)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_fade()
		return
	# Pulse the ring.
	if _ring != null:
		var s := 1.0 + sin(Time.get_ticks_msec() / 300.0) * 0.03
		_ring.scale = Vector3(s, 1, s)
	# Server applies the aura effect.
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_apply_aura()


func _apply_aura() -> void:
	match totem_id:
		"reciprocity":
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < RADIUS:
					p.rpc_id(p.get_multiplayer_authority(), "heal", 4.0 * _rank_mult())
		"bulwark":
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m == null or not m.alive:
					continue
				if m.global_position.distance_to(global_position) < RADIUS:
					m.apply_slow(TICK * 1.5, 0.6)
		"warhorn":
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < RADIUS:
					p.rpc_id(p.get_multiplayer_authority(), "apply_warhorn", TICK * 1.5)
		"stoneskin":
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < RADIUS:
					p.rpc_id(p.get_multiplayer_authority(), "apply_stoneskin", TICK * 1.5)
		"rally":
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < RADIUS:
					p.rpc_id(p.get_multiplayer_authority(), "apply_rally", TICK * 1.5)


func _rank_mult() -> float:
	return 1.0 + float(rank - 1) * 0.25


func _fade() -> void:
	AudioManager.sfx("totem_expire", global_position)
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), _color(), 15, 4.0)
	queue_free()
