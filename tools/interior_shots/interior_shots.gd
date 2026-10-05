extends Node
## Train interior screenshot driver (issue #3 Phase 1). Run under Xvfb:
##   godot --path . res://tools/interior_shots/interior_shots.tscn --resolution 1280x720 -- --shot-dir /tmp/interior_shots
## Boots the interior scene with one warrior passenger, screenshots the car
## with doors open, then again after close_doors().

var _shot_dir := "/tmp/interior_shots"
var _car: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	print("[InteriorShots] output -> ", _shot_dir)
	# Board one passenger (peer 1 = local in offline mode) so the player
	# camera exists and gives a sense of scale.
	var InteriorScript: GDScript = load("res://scripts/station/train_interior.gd")
	InteriorScript.passenger_classes = {1: "warrior"}
	InteriorScript.ride_theme_id = "dungeon"
	var packed: PackedScene = load("res://scenes/station/train_interior.tscn")
	_car = packed.instantiate()
	get_tree().root.add_child.call_deferred(_car)
	await get_tree().create_timer(3.0).timeout
	# Face the rear doors for the shot (player at x=-5, doors at x=-8.2).
	var rider := _car.get_node_or_null("Player_1")
	if rider != null:
		rider.set("_yaw", PI * 0.5)
		rider.rotation.y = PI * 0.5
	await get_tree().process_frame
	await _snap("interior_doors_open.png")
	_car.close_doors()
	await get_tree().create_timer(1.0).timeout
	await _snap("interior_doors_closed.png")
	print("[InteriorShots] done")
	get_tree().quit()


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir + "/" + name
	if img.save_png(path) == OK:
		print("[InteriorShots] saved ", path)
	else:
		push_error("[InteriorShots] FAILED to save " + path)
