extends Node
## Boarding lobby verification driver (issue #93 Phase 1). Run under Xvfb:
##   godot --path . res://tools/lobby_shots/lobby_shots.tscn --resolution 1920x1080 -- --shot-dir /tmp/lobby_shots
## Builds the annex (shell + lobby) for a fixed seed and screenshots the
## lobby interior, the doorway, and the lobby/train context.
var _shot_dir := "/tmp/lobby_shots"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	# A touch of ambient so the unlit corners read on the screenshot.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.03)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.32, 0.30)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var AnnexScript: GDScript = load("res://scripts/station/station_annex.gd")
	var ProcGenScript: GDScript = load("res://scripts/procgen/procgen.gd")
	var theme: Resource = load("res://data/levels/theme_village.tres")
	var layout = ProcGenScript.generate(theme, 12345)
	var plan: Dictionary = AnnexScript.plan(12345, layout)
	var holder := Node3D.new()
	add_child(holder)
	var annex = AnnexScript.build(holder, plan, layout)
	var hc: Vector3 = annex.hall_center()
	print("[LobbyShots] hall_center=", hc, " attach_x=", annex.attach_x)
	# Freeze the 1s arrival settle so the closed shot is deterministic;
	# the open shot drives the real tween path explicitly.
	annex._settle_left = -1.0
	await get_tree().process_frame
	await get_tree().process_frame
	# 1. Interior wide shot from the southwest corner.
	await _snap(Vector3(hc.x - 3.5, 2.2, hc.z + 2.5), Vector3(hc.x, 1.0, hc.z - 1.5), "lobby_interior.png")
	# 2. Doorway close-up from inside, looking north.
	await _snap(Vector3(hc.x - 1.0, 1.6, hc.z + 1.5), Vector3(hc.x - 1.0, 1.3, hc.z - 2.25), "lobby_doorway.png")
	# 3. Context: lobby + train from above-southeast.
	await _snap(Vector3(hc.x + 8.0, 2.5, hc.z + 5.0), Vector3(hc.x - 1.0, 1.0, hc.z - 3.0), "lobby_context.png")
	# 4. Phase 2: doors closed on build (arrival state).
	await _snap(Vector3(hc.x - 1.0, 1.6, hc.z + 1.5), Vector3(hc.x - 1.0, 1.3, hc.z - 2.25), "lobby_doors_closed.png")
	# 5. Phase 2: doors open (real tween path, 1.5s + margin).
	annex.set_lobby_doors(true)
	await get_tree().create_timer(2.0).timeout
	await _snap(Vector3(hc.x - 1.0, 1.6, hc.z + 1.5), Vector3(hc.x - 1.0, 1.3, hc.z - 2.25), "lobby_doors_open.png")
	print("[LobbyShots] done")
	get_tree().quit()

func _snap(pos: Vector3, target: Vector3, name: String) -> void:
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	cam.position = pos
	cam.look_at(target)
	cam.fov = 65.0
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir + "/" + name)
	print("[LobbyShots] saved ", name)
	cam.queue_free()
