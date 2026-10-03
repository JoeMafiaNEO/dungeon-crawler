class_name FrostShard
extends Node3D
## Mage frost projectile. Fast blue shard; slows enemies it hits.
## Mirrors Fireball: flies on every peer, server owns hits.

var velocity := Vector3.ZERO
var damage := 10.0
var owner_peer := 0
var slow_duration := 2.5
var slow_mult := 0.5

var _life := 2.0
var _exploded := false


func setup(p_velocity: Vector3, p_damage: float, p_owner: int) -> void:
	velocity = p_velocity
	damage = p_damage
	owner_peer = p_owner


## True if the projectile is inside a wall/obstacle cell.
func _is_in_wall() -> bool:
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if dungeons.is_empty():
		return false
	var dungeon = dungeons[0]
	var layout = dungeon.get("_layout")
	if layout == null:
		return false
	return layout.is_solid_world(global_position)


func _ready() -> void:
	# Icy core.
	var core := MeshInstance3D.new()
	var shard := BoxMesh.new()
	shard.size = Vector3(0.12, 0.12, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.75, 1.0)
	mat.emission_energy_multiplier = 3.0
	shard.material = mat
	core.mesh = shard
	add_child(core)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.8, 1.0)
	light.light_energy = 1.2
	light.omni_range = 6.0
	add_child(light)
	if velocity.length() > 0.01:
		rotation.y = atan2(velocity.x, velocity.z)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_life -= delta
	position += velocity * delta
	if _life <= 0.0 or position.y < 0.0:
		_shatter()
		return
	# Walls stop frost shards.
	if _is_in_wall():
		_shatter()
		return
	if multiplayer.is_server():
		for node in get_tree().get_nodes_in_group("mobs"):
			var mob := node as Mob
			if mob == null or not mob.alive:
				continue
			# XZ distance: the shard flies at a fixed height, so use
			# horizontal distance to avoid tunneling past mobs.
			var a := Vector2(mob.global_position.x, mob.global_position.z)
			var b := Vector2(global_position.x, global_position.z)
			if a.distance_to(b) < 1.3:
				mob.rpc_id(NetworkManager.server_id, "take_damage", damage, owner_peer, global_position)
				mob.apply_slow(slow_duration, slow_mult)
				AudioManager.sfx("frost_hit", global_position)
				_shatter()
				return


func _shatter() -> void:
	if _exploded:
		return
	_exploded = true
	Effects.burst(get_parent(), global_position, Color(0.6, 0.85, 1.0), 12, 4.0)
	queue_free()
