class_name ThrownDagger
extends Node3D
## Rogue thrown dagger (issue #69). Out leg: straight flight with
## charge-scaled range (6m tap → 16m full) and damage (0.6x → 1.4x).
## Return leg (Phase 2): homes to the rogue's CURRENT position — tracks
## movement, dodges, Shadow Step blinks. Hits on both legs.
## Flies on every peer; server owns hit detection. Collides with walls.

var velocity := Vector3.ZERO
var damage := 6.0
var owner_peer := 0

var _distance_traveled := 0.0
var _max_range := 6.0
var _hit := false
## Phase 2: return leg state.
var _returning := false
var _return_speed := 32.0
const CATCH_DIST := 1.2
## Issue #81: per-leg hit set — each mob takes damage once per leg.
## Cleared when the return leg starts.
var _hit_mobs := {}


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


## Find the owning rogue's player node.
func _owner_node() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if int(p.get_multiplayer_authority()) == owner_peer:
			return p
	return null


func _ready() -> void:
	# Spinning dagger: simple box, rotates in _physics_process.
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
	rotation.y += delta * 20.0

	# Phase 2: edge case — owner died or disconnected → despawn.
	var owner := _owner_node()
	if owner == null or not bool(owner.get("alive")):
		_despawn()
		return

	if _returning:
		_update_return(delta, owner)
	else:
		_update_outbound(delta)


## Out leg: straight flight.
func _update_outbound(delta: float) -> void:
	var step := velocity * delta
	position += step
	_distance_traveled += step.length()
	# Walls stop the out leg → start return.
	if _is_in_wall():
		_start_return()
		return
	# Max range → start return.
	if _distance_traveled >= _max_range:
		_start_return()
		return
	# Server owns hit detection (out leg).
	if multiplayer.is_server():
		_check_mob_hits()


## Phase 2: Return leg — home to the rogue's CURRENT position.
func _update_return(delta: float, owner: Node) -> void:
	if owner == null:
		_despawn()
		return
	var target: Vector3 = owner.global_position + Vector3(0, 1.4, 0)
	var to_target := target - global_position
	var dist := to_target.length()
	# Auto-catch on arrival.
	if dist < CATCH_DIST:
		_catch()
		return
	# Home toward the rogue (tracks blinks/dodges).
	var dir := to_target / dist
	position += dir * _return_speed * delta
	# Server owns hit detection (return leg hits too).
	if multiplayer.is_server():
		_check_mob_hits()


## Start the return leg.
func _start_return() -> void:
	_returning = true
	# Issue #81: clear the hit set — return leg gets its own once-per-mob.
	_hit_mobs.clear()
	# Tell the owner the dagger is returning (for HUD/Fan lockout).
	var owner := _owner_node()
	if owner != null and owner.has_method("_on_dagger_returning"):
		owner._on_dagger_returning()


## Check for mob hits (both legs). Server only.
## Issue #81: each mob takes damage once per leg (tracked in _hit_mobs).
func _check_mob_hits() -> void:
	for node in get_tree().get_nodes_in_group("mobs"):
		var mob := node as Mob
		if mob == null or not mob.alive:
			continue
		var mob_id := mob.get_instance_id()
		if _hit_mobs.has(mob_id):
			continue
		var a := Vector2(mob.global_position.x, mob.global_position.z)
		var b := Vector2(global_position.x, global_position.z)
		if a.distance_to(b) < 0.9:
			_hit_mobs[mob_id] = true
			# Mark Target +50% applies on both legs (Phase 2 kit interaction).
			var hit_dmg := damage
			if mob.is_marked():
				hit_dmg *= 1.5
			mob.rpc_id(NetworkManager.server_id, "take_damage", hit_dmg, owner_peer, global_position)
			# Precision affinity: thrown hits feed it (Phase 2).
			var owner := _owner_node()
			if owner != null and owner.has_method("gain_affinity_capped"):
				var cast_id := "thrown_%d" % get_instance_id()
				owner.gain_affinity_capped("precision", 1.0, mob.get_instance_id(), cast_id, 8.0)
			# Don't despawn on hit — the dagger passes through (both legs hit).


## Auto-catch: dagger returns to hand.
func _catch() -> void:
	if _hit:
		return
	_hit = true
	var owner := _owner_node()
	if owner != null and owner.has_method("_on_dagger_caught"):
		owner.rpc_id(owner_peer, "_on_dagger_caught")
	rpc("catch_fx")


func _despawn() -> void:
	if _hit:
		return
	_hit = true
	rpc("hit_fx")


@rpc("any_peer", "call_local")
func hit_fx() -> void:
	Effects.burst(get_parent(), global_position, Color(0.9, 0.85, 0.7), 8, 3.0)
	queue_free()


@rpc("any_peer", "call_local")
func catch_fx() -> void:
	# Catch click + small sparkle.
	Effects.burst(get_parent(), global_position, Color(1.0, 0.95, 0.6), 6, 2.0)
	queue_free()
