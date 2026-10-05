extends Node
## Relic Vault screenshot driver (issue #6 Phase 2). Run under Xvfb:
##   XDG_DATA_HOME=/tmp/vault_scratch godot --headless --path . \
##     res://tools/vault_shots/vault_shots.tscn --resolution 1920x1080 -- \
##     --shot-dir /tmp/vault_shots
## XDG_DATA_HOME redirects user:// to a scratch dir (never touches real saves).
## Captures: the locker prop, the vault panel locked, the vault panel equipped.

var _shot_dir := "/tmp/vault_shots"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	print("[VaultShots] output -> ", _shot_dir, " user:// -> ", OS.get_user_data_dir())
	_stage_prop()
	await get_tree().process_frame
	await get_tree().process_frame
	# 1. Locker prop (no player/HUD yet for a clean shot).
	await _snap("vault_prop.png")
	# 2. Panel, locked state (fresh scratch profile: nothing earned).
	_stage_player()
	_open_panel()
	await _snap("vault_panel_locked.png")
	# 3. Panel, equipped state.
	_earn_and_equip()
	_open_panel()
	await _snap("vault_panel_equipped.png")
	print("[VaultShots] done")
	get_tree().quit()


var _hud: CanvasLayer = null
var _player: Node = null


func _stage_prop() -> void:
	# Floor + locker + camera.
	var floor_mi := MeshInstance3D.new()
	var floor_bm := BoxMesh.new()
	floor_bm.size = Vector3(12, 0.2, 12)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.25, 0.24, 0.28)
	floor_bm.material = floor_mat
	floor_mi.mesh = floor_bm
	floor_mi.position = Vector3(0, -0.1, 0)
	add_child(floor_mi)
	var VaultScript := load("res://scripts/station/relic_vault.gd")
	var vault = VaultScript.new()
	vault.position = Vector3(0, 0, 0)
	add_child(vault)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.9
	sun.rotation = Vector3(-0.7, 0.4, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0.6, 1.7, 5.2)
	add_child(cam)
	cam.look_at(Vector3(0, 1.35, 0))
	cam.current = true


func _stage_player() -> void:
	# Player + HUD for the panel shots.
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	_player = PlayerScene.instantiate()
	_player.set("class_id", "warrior")
	_player.position = Vector3(0, 0.1, 2.5)
	add_child(_player)
	var HUDScene: PackedScene = load("res://scenes/ui/hud.tscn")
	_hud = HUDScene.instantiate()
	add_child(_hud)
	_hud.call("setup", _player)


func _open_panel() -> void:
	_hud.call("show_vault")
	await get_tree().process_frame
	await get_tree().process_frame


func _earn_and_equip() -> void:
	SpecialData.earn("greed_charm")
	SpecialData.earn("second_wind")
	SpecialData.earn("apex_boar_hide")
	SpecialData.equip(_player, "greed_charm")


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _shot_dir + "/" + file_name
	if img.save_png(path) == OK:
		print("[VaultShots] saved ", path)
	else:
		push_error("[VaultShots] FAILED to save " + path)
