extends Node
## Train dressing screenshot driver (issue #3 Phase 4). Run under Xvfb:
##   godot --path . res://tools/dress_shots/dress_shots.tscn --resolution 1280x720 -- --shot-dir /tmp/dress_shots
## Boots the interior once per theme (depths, supermarket, warlord), applies
## the ride dressing, and screenshots the dressed car. Cleans up user:// saves
## afterwards (end-to-end runs must not pollute saves).

var _shot_dir := "/tmp/dress_shots"
var _car: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	print("[DressShots] output -> ", _shot_dir)
	var InteriorScript: GDScript = load("res://scripts/station/train_interior.gd")
	var packed: PackedScene = load("res://scenes/station/train_interior.tscn")
	# Per-theme camera: position + yaw framing the signature props.
	var poses := {
		"depths": [Vector3(5.0, 0.1, -0.8), -2.47], # crystal cluster, north-east
		"supermarket": [Vector3(1.5, 0.1, -1.0), PI], # poster boards, north wall
		"warlord": [Vector3(0.0, 0.1, -1.0), PI], # war banners, north wall
	}
	for theme in ["depths", "supermarket", "warlord"]:
		InteriorScript.passenger_classes = {1: "warrior"}
		InteriorScript.ride_theme_id = theme
		InteriorScript.doors_locked = true
		InteriorScript.ride_seconds_override = 25.0
		InteriorScript.ride_active = false
		_car = packed.instantiate()
		get_tree().root.add_child.call_deferred(_car)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		# Dressing applies at ride start; call it directly (offline the
		# server check passes) so the shot shows the dressed car.
		_car.apply_dressing(theme)
		_face_props(poses[theme][0], poses[theme][1])
		await get_tree().process_frame
		await get_tree().process_frame
		await _snap("dress_" + theme + ".png")
		_car.queue_free()
		_car = null
		await get_tree().process_frame
	_cleanup_saves()
	print("[DressShots] done")
	get_tree().quit()


## Frame the signature props: position + yaw.
func _face_props(pos: Vector3, yaw: float) -> void:
	var rider := _car.get_node_or_null("Player_1")
	if rider != null:
		rider.global_position = pos
		rider.set("_yaw", yaw)
		rider.rotation.y = yaw


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir + "/" + name
	if img.save_png(path) == OK:
		print("[DressShots] saved ", path)
	else:
		push_error("[DressShots] FAILED to save " + path)


## Never leave save files behind an end-to-end driver run.
func _cleanup_saves() -> void:
	for f in ["user://solo_warrior.cfg", "user://solo_rogue.cfg",
			"user://solo_mage.cfg", "user://solo_architect.cfg",
			"user://savegame.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
			print("[DressShots] cleaned ", f)
