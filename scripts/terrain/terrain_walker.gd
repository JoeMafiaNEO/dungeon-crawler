class_name TerrainWalker
extends CharacterBody3D
## Issue #103 test-scene probe: a physics body that walks waypoints across
## the heightmap terrain. Proves bodies ride HeightMapShape3D via gravity
## (the player/mob path from the spec). Records max deviation from the
## array ground height for the verify pass.

var terrain: HeightmapTerrain
var speed: float = 4.0
var waypoints: Array[Vector3] = []
var _wp: int = 0
var max_deviation: float = 0.0
var distance_walked: float = 0.0

const GRAVITY := 22.0


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	var mesh := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.7
	mesh.mesh = cm
	mesh.position.y = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.75, 0.25)
	mesh.material_override = mat
	add_child(mesh)
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(50.0)


func _physics_process(delta: float) -> void:
	if terrain == null or waypoints.is_empty():
		return
	velocity.y -= GRAVITY * delta
	var target := waypoints[_wp]
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if to.length() < 1.0:
		_wp = (_wp + 1) % waypoints.size()
		return
	var dir := to.normalized()
	# Water blocks movement like a wall (spec minimum-viable behavior):
	# 3m lookahead; steer to the dry side, reverse if boxed in.
	var ahead := global_position + dir * 3.0
	if terrain.is_water(ahead):
		var side := Vector3(-dir.z, 0.0, dir.x)
		var left_ok := not terrain.is_water(global_position + side * 3.0)
		var right_ok := not terrain.is_water(global_position - side * 3.0)
		if left_ok and right_ok:
			# Pick the side closer to the waypoint.
			var dl := (global_position + side * 3.0).distance_to(target)
			var dr := (global_position - side * 3.0).distance_to(target)
			dir = side if dl < dr else -side
		elif left_ok:
			dir = side
		elif right_ok:
			dir = -side
		else:
			dir = -dir
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	var before := global_position
	move_and_slide()
	distance_walked += before.distance_to(global_position)
	if is_on_floor():
		var dev := absf(global_position.y - terrain.get_ground_height(global_position))
		max_deviation = maxf(max_deviation, dev)
