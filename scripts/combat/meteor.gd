class_name Meteor
extends Node3D
## Visual meteor: a flaming rock that streaks down from the sky and
## impacts after FALL_TIME. Server applies damage on impact.

const FALL_TIME := 1.0
const BLAST_RADIUS := 4.5

var target := Vector3.ZERO
var damage := 0.0
var owner_peer := 0

var _t := 0.0
var _start := Vector3.ZERO
var _impacted := false


func setup(p_target: Vector3, p_damage: float, p_owner: int) -> void:
	target = p_target
	damage = p_damage
	owner_peer = p_owner
	# Streak in at an angle from high above.
	_start = target + Vector3(6.0, 18.0, 3.0)


func _ready() -> void:
	global_position = _start
	# Rocky core: dark basalt sphere.
	var rock := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	sphere.radial_segments = 9
	sphere.rings = 6
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.25, 0.2, 0.18)
	rock_mat.roughness = 0.95
	sphere.material = rock_mat
	rock.mesh = sphere
	add_child(rock)
	# Glowing lava cracks: smaller emissive inner sphere peeking through.
	var lava := MeshInstance3D.new()
	var lava_sphere := SphereMesh.new()
	lava_sphere.radius = 0.42
	lava_sphere.height = 0.84
	var lava_mat := StandardMaterial3D.new()
	lava_mat.albedo_color = Color(1.0, 0.35, 0.05)
	lava_mat.emission_enabled = true
	lava_mat.emission = Color(1.0, 0.3, 0.05)
	lava_mat.emission_energy_multiplier = 4.0
	lava_sphere.material = lava_mat
	lava.mesh = lava_sphere
	lava.scale = Vector3(1.02, 0.9, 1.02)
	add_child(lava)
	# Fire light.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.1)
	light.light_energy = 3.0
	light.omni_range = 10.0
	add_child(light)
	# Flame trail.
	var trail := Effects.make_flame()
	trail.amount = 40
	trail.local_coords = false
	add_child(trail)
	# Orient along the fall direction.
	var dir: Vector3 = (target - _start).normalized()
	rotation.x = atan2(dir.y, Vector2(dir.x, dir.z).length()) + PI / 2.0


func _physics_process(delta: float) -> void:
	if _impacted:
		return
	_t += delta
	var f := clampf(_t / FALL_TIME, 0.0, 1.0)
	# Ease-in: accelerates as it falls.
	var eased := f * f
	global_position = _start.lerp(target + Vector3(0, 0.3, 0), eased)
	# Spin for drama.
	rotation.y += delta * 9.0
	if f >= 1.0:
		_impact()


func _impact() -> void:
	if _impacted:
		return
	_impacted = true
	var at := target + Vector3(0, 0.5, 0)
	Effects.burst(get_parent(), at, Color(1.0, 0.5, 0.15), 50, 9.0)
	Effects.burst(get_parent(), at, Color(1.0, 0.85, 0.4), 30, 7.0)
	Effects.burst(get_parent(), at, Color(0.3, 0.25, 0.22), 25, 6.0)
	AudioManager.sfx("explosion", target)
	# Scorch decal: darkened ground disc that fades.
	Effects.scorch(get_parent(), target, BLAST_RADIUS)
	if multiplayer.is_server():
		var dungeon := get_tree().get_first_node_in_group("dungeon")
		var caster: Player = null
		if dungeon != null:
			caster = dungeon.get_player_node(owner_peer) as Player
		# Conflagration: +25% blast radius.
		var radius := BLAST_RADIUS
		if caster != null and caster.has_trait("conflagration"):
			radius *= 1.25
		var hit_any := false
		for n in get_tree().get_nodes_in_group("mobs"):
			var m := n as Mob
			if m == null or not m.alive:
				continue
			if m.global_position.distance_to(target) < radius:
				m.rpc_id(NetworkManager.server_id, "take_damage", damage, owner_peer, target)
				# Wildfire: fire hits apply burn (3s DoT).
				if caster != null and caster.has_trait("wildfire"):
					m.apply_burn(3.0, damage * 0.3, owner_peer)
				hit_any = true
		# Affinity: +8 if the impact hit at least one enemy (single grant).
		if hit_any and caster != null:
			caster.gain_affinity("meteor", 8.0)
	queue_free()
