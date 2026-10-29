extends Node
## Issue #236 street-level frame: boots the real world
## scene with the post-reveal state fabricated, walks the
## camera to the home building's doorstep, and captures
## the entrance at street level. The door must read as a
## door ON the ground - gap base at the street, trigger
## at the step - not floating over it.

const WorldGen := preload("res://scripts/world/world_gen.gd")
const BuildingGen := preload("res://scripts/world/building_gen.gd")
const WORLD_PATH := "res://scenes/world/world.tscn"
const SHOT_DIR := "/home/hatch/workspace/home-door-shots"

var _frames := 0
var _world: Node = null
var _cam: Camera3D = null
var _step := Vector3.ZERO
var _gap := Vector3.ZERO
var _normal := Vector3.ZERO


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	Dungeon.revealed = true
	Dungeon.home_anchor = Dungeon.compute_home_anchor(96.0)
	Dungeon.seed_home_ledger()
	Dungeon.buildings_cleared = 1
	Dungeon.act2_context = "world"
	var home: Dictionary = Dungeon.home_building()
	Dungeon.act2_anchor_building = str(home["key"])
	Dungeon.act2_anchor_doorstep = home["doorstep"]
	_step = home["doorstep"]
	_gap = home["gap_center"]
	var door := BuildingGen.door_world(home["plan"],
		home["origin"])
	_normal = door["normal"]
	print("[HOMEDOOR] doorstep: ", _step, " gap: ", _gap,
		" normal: ", _normal)
	print("[HOMEDOOR] terrain at doorstep: ",
		WorldGen.height_at(WorldGen.WORLD_SEED,
			_step.x, _step.z))
	var packed := load(WORLD_PATH) as PackedScene
	_world = packed.instantiate()
	add_child(_world)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 150:
		# The home building + its street chunk should be
		# in by now; put the camera on the street.
		var wr := _world
		var bname := "Building_" + str(
			Dungeon.home_building()["key"]).replace(
			",", "_")
		var b := wr.find_child(bname, true, false)
		print("[HOMEDOOR] home node present: ", b != null)
		if b != null:
			var trig := b.get_node_or_null(
				"TransferTrigger") as Node3D
			if trig != null:
				print("[HOMEDOOR] trigger world y: ",
					trig.global_position.y,
					" terrain there: ",
					WorldGen.height_at(
						WorldGen.WORLD_SEED,
						trig.global_position.x,
						trig.global_position.z))
		_cam = Camera3D.new()
		add_child(_cam)
		var cp := _step + _normal * 7.0
		cp.y = WorldGen.height_at(WorldGen.WORLD_SEED,
			cp.x, cp.z) + 1.7
		_cam.global_position = cp
		_cam.look_at(_gap + Vector3(0, 1.3, 0),
			Vector3.UP)
		_cam.current = true
		print("[HOMEDOOR] camera at: ", cp)
	if _frames == 175:
		var img := get_viewport().get_texture().get_image()
		var path := SHOT_DIR.path_join("home_door.png")
		if img.save_png(path) == OK:
			print("[HOMEDOOR] saved ", path)
		else:
			print("[HOMEDOOR] FAIL saving ", path)
		get_tree().quit(0)
