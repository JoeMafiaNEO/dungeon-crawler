class_name TerrainPerfUnit
extends Node3D
## Issue #103 test-scene probe: lightweight stand-in for an RTS unit.
## Mirrors the _apply_movement sampling path from the spec: manual 2D
## movement + per-frame get_ground_height() array sample (never a physics
## query). The perf pass measures this loop at 500/1000/1500 units.

var terrain: HeightmapTerrain
var velocity := Vector3.ZERO
var speed := 3.0
var _dir := Vector3.FORWARD
var _retarget := 0.0


func _ready() -> void:
	# Cheap visual: small billboard-free box so the perf scene reads.
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.5, 0.5)
	mesh.mesh = bm
	mesh.position.y = 0.25
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.2, 0.2)
	mesh.material_override = mat
	add_child(mesh)


func tick(delta: float) -> void:
	# Wander: pick a new heading every few seconds or at map edge.
	_retarget -= delta
	var half := terrain.half_extent() - 2.0
	if _retarget <= 0.0 or absf(position.x) > half or absf(position.z) > half:
		var a := randf() * TAU
		_dir = Vector3(cos(a), 0.0, sin(a))
		_retarget = 2.0 + randf() * 3.0
	var next := position + _dir * speed * delta
	# Spec minimum-viable water: blocks like a wall — don't enter.
	if not terrain.is_water(next):
		position.x = next.x
		position.z = next.z
	else:
		_retarget = 0.0 # pick a new heading next tick
	# THE sampling path under test: array sample only, no physics query.
	position.y = terrain.get_ground_height(position)
