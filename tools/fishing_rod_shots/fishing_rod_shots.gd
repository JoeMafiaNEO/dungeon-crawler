extends SceneTree
## Issue #104 Phase 3 validation driver: three renders at 1920x1080 —
## (1) a peer replica holding rod + weapon (the MP view), (2) the local
## first-person viewmodel with the rod equipped, (3) the gate prompt at
## a fishing spot without the rod.
##   xvfb-run -a -s "-screen 0 1920x1080x24" Godot --path . \
##     --resolution 1920x1080 -s tools/fishing_rod_shots/fishing_rod_shots.gd

func _init() -> void:
	call_deferred("_run")


func _shot(path: String) -> void:
	await create_timer(0.9).timeout
	root.get_texture().get_image().save_png(path)
	print("[RodShots] saved ", path)


func _run() -> void:
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var SpotScript: GDScript = load("res://scripts/dungeon/fishing_spot.gd")
	var world := Node3D.new()
	root.add_child(world)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.7
	we.environment = env
	world.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	world.add_child(light)
	var ground := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(40, 0.1, 40)
	ground.mesh = gm
	ground.position.y = -0.05
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.16, 0.22, 0.17)
	ground.material_override = gmat
	world.add_child(ground)

	# (1) Peer replica (authority 2) with synced equipped_ids.
	var pv = PlayerScene.instantiate()
	pv.class_id = "warrior"
	pv.set_multiplayer_authority(2)
	world.add_child(pv)
	pv.global_position = Vector3(0, 0, 0)
	pv.push_snapshot(Vector3.ZERO, 100.0, 1, true, 0.6,
		{"TOOL": "fishing_rod", "WEAPON": "iron_sword"})
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = Vector3(1.7, 1.8, -2.6)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	await _shot("/home/hatch/workspace/rod_shots/tp_peer_rod.png")
	cam.queue_free()
	pv.queue_free()

	# (2) Local hero, rod + iron sword equipped: first-person viewmodel.
	var hero = PlayerScene.instantiate()
	hero.class_id = "warrior"
	world.add_child(hero)
	hero.global_position = Vector3(6, 0, 0)
	hero.receive_item("iron_sword")
	hero.receive_item("fishing_rod")
	for i in hero.inventory.size():
		var it = hero.inventory[i].get("item")
		if it != null and str(it.get("id")) in ["iron_sword", "fishing_rod"]:
			hero.equip_stack(i)
	var hcam = hero.get("_camera")
	if hcam != null:
		hcam.current = true
	await _shot("/home/hatch/workspace/rod_shots/fp_rod.png")

	# (3) Rod-less hero at a fishing spot: the gate prompt.
	hero.free() # immediate: a queued hero would linger as the "local player"
	var hero2 = PlayerScene.instantiate()
	hero2.class_id = "warrior"
	world.add_child(hero2)
	hero2.global_position = Vector3(-6, 0, 0)
	var spot = SpotScript.new()
	world.add_child(spot)
	spot.global_position = Vector3(-6, 0, 1.5)
	spot.water_point = Vector3(-6, 0, 5)
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._player = hero2
	hud.set_pickup_prompt(true, str(spot.prompt_text()))
	var hcam2 = hero2.get("_camera")
	if hcam2 != null:
		hcam2.current = true
	await _shot("/home/hatch/workspace/rod_shots/gate_prompt.png")
	print("[RodShots] prompt was: ", spot.prompt_text())
	quit()
