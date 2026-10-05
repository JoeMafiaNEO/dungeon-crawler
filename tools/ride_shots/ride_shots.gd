extends Node
## Train ride screenshot driver (issue #3 Phase 3). Run under Xvfb:
##   godot --path . res://tools/ride_shots/ride_shots.tscn --resolution 1280x720 -- --shot-dir /tmp/ride_shots
## Boots the interior with one warrior passenger on the full ride, screenshots
## mid-ride (scrolling scenery through the windows), then forces arrival and
## screenshots the platform + open doors. Cleans up user:// saves afterwards
## (lesson from the Phase 2 driver: end-to-end runs must not pollute saves).

var _shot_dir := "/tmp/ride_shots"
var _car: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	print("[RideShots] output -> ", _shot_dir)
	var InteriorScript: GDScript = load("res://scripts/station/train_interior.gd")
	InteriorScript.passenger_classes = {1: "warrior"}
	InteriorScript.ride_theme_id = "depths"
	InteriorScript.doors_locked = true
	InteriorScript.ride_seconds_override = 0.0 # full 25s ride
	InteriorScript.ride_active = false
	var packed: PackedScene = load("res://scenes/station/train_interior.tscn")
	_car = packed.instantiate()
	get_tree().root.add_child.call_deferred(_car)
	# Server waits 1s before rpc'ing ride_started; give the ride time to roll.
	await get_tree().create_timer(7.0).timeout
	_face_window()
	await get_tree().process_frame
	await _snap("ride_midway.png")
	# Force arrival (offline: local call passes the server check), let the
	# doors finish their open tween, then shoot the platform.
	_car.begin_arrival()
	await get_tree().create_timer(2.5).timeout
	_face_platform()
	await get_tree().process_frame
	await _snap("ride_arrival.png")
	_cleanup_saves()
	print("[RideShots] done")
	get_tree().quit()


## Face the north windows (scenery side) from a clear aisle spot.
func _face_window() -> void:
	var rider := _car.get_node_or_null("Player_1")
	if rider != null:
		rider.global_position = Vector3(2.0, 0.1, 0.0)
		rider.set("_yaw", 0.0)
		rider.rotation.y = 0.0


## Face the rear doors / platform for the arrival shot.
func _face_platform() -> void:
	var rider := _car.get_node_or_null("Player_1")
	if rider != null:
		rider.set("_yaw", PI * 0.5)
		rider.rotation.y = PI * 0.5
		# Step toward the door for a better view of the platform.
		rider.global_position = Vector3(-5.5, 0.1, 0.0)


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir + "/" + name
	if img.save_png(path) == OK:
		print("[RideShots] saved ", path)
	else:
		push_error("[RideShots] FAILED to save " + path)


## Never leave save files behind an end-to-end driver run.
func _cleanup_saves() -> void:
	for f in ["user://solo_warrior.cfg", "user://solo_rogue.cfg",
			"user://solo_mage.cfg", "user://solo_architect.cfg",
			"user://savegame.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
			print("[RideShots] cleaned ", f)
