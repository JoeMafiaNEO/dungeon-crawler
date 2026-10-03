class_name EnemyArrow
extends Node3D
## Enemy projectile (goblin archer). Flies straight on every peer;
## the server owns hit detection against players, then tells
## everyone to stick/break.

var velocity := Vector3.ZERO
var damage := 8.0
## Mob display name, passed to the victim's death-cause tracking.
var attacker_name := "Goblin Archer"

var _life := 3.0
var _dead := false


func setup(p_velocity: Vector3, p_damage: float) -> void:
	velocity = p_velocity
	damage = p_damage


func _ready() -> void:
	# Simple wooden arrow: shaft + head.
	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.05, 0.05, 0.7)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.38, 0.22)
	shaft_mesh.material = wood
	shaft.mesh = shaft_mesh
	add_child(shaft)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.09, 0.09, 0.16)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.75, 0.78)
	head_mesh.material = steel
	head.mesh = head_mesh
	head.position = Vector3(0, 0, 0.4)
	add_child(head)
	# Orient along flight direction.
	if velocity.length() > 0.01:
		rotation.y = atan2(velocity.x, velocity.z)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_life -= delta
	position += velocity * delta
	if _life <= 0.0 or position.y < 0.05:
		_break()
		return
	if multiplayer.is_server():
		for node in get_tree().get_nodes_in_group("players"):
			var p := node as Player
			if p == null or not p.alive:
				continue
			var to: Vector3 = p.global_position + Vector3(0, 1.0, 0) - global_position
			if to.length() < 1.1:
				p.rpc_id(p.get_multiplayer_authority(), "take_damage", damage, attacker_name)
				AudioManager.sfx("arrow_hit", global_position)
				_break()
				return


func _break() -> void:
	if _dead:
		return
	_dead = true
	if is_inside_tree():
		Effects.burst(get_parent(), global_position, Color(0.6, 0.5, 0.35), 6)
	queue_free()
