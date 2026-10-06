class_name ThrownDagger
extends Node3D
## Rogue thrown dagger (issue #69 Phase 1). Out leg only — straight flight
## with charge-scaled range (6m tap → 16m full) and damage (0.6x → 1.4x).
## Flies on every peer; server owns hit detection. Collides with walls.
## Phase 2 adds the boomerang return.

var velocity := Vector3.ZERO
var damage := 6.0
var owner_peer := 0

var _distance_traveled := 0.0
var _max_range := 6.0
var _hit := false


func setup(p_velocity: Vector3, p_damage: float, p_owner: int, p_range := 6.0) -> void:
	velocity = p_velocity
	damage = p_damage
	owner_peer = p_owner
	_max_range = p_range


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
	# Spinning dagger: simple box, rotates in _physics_process.
	# SNES sprite comes in Phase 2.
	var blade := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.5, 0.08, 0.12)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.85, 0.9)
	bmat.metallic = 0.8
	bmesh.material = bmat
	blade.mesh = bmesh
	add_child(blade)


func _physics_process(delta: float) -> void:
	if _hit:
		return
	# Spin for style.
	rotation.y += delta * 20.0
	var step := velocity * delta
	position += step
	_distance_traveled += step.length()
	# Range limit (charge-scaled).
	if _distance_traveled >= _max_range:
		_despawn()
		return
	# Walls stop the dagger.
	if _is_in_wall():
		_despawn()
		return
	# Server owns hit detection.
	if multiplayer.is_server():
		for node in get_tree().get_nodes_in_group("mobs"):
			var mob := node as Mob
			if mob == null or not mob.alive:
				continue
			var a := Vector2(mob.global_position.x, mob.global_position.z)
			var b := Vector2(global_position.x, global_position.z)
			if a.distance_to(b) < 0.9:
				_hit = true
				mob.rpc_id(NetworkManager.server_id, "take_damage", damage, owner_peer, global_position)
				rpc("hit_fx")
				return


func _despawn() -> void:
	if _hit:
		return
	_hit = true
	# Phase 1: just despawn at max range. Phase 2 adds boomerang return.
	rpc("hit_fx")


@rpc("any_peer", "call_local")
func hit_fx() -> void:
	Effects.burst(get_parent(), global_position, Color(0.9, 0.85, 0.7), 8, 3.0)
	queue_free()
