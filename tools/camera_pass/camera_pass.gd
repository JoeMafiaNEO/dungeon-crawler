extends Node
## Scripted camera pass for the build pipeline.
##
## Boots every level theme in solo mode, flies a cinematic camera through
## scripted waypoints, and saves screenshots next to the build zip.
## A companion ffmpeg x11grab recording (see tools/capture_footage.sh)
## captures the whole pass as a short gameplay clip.
##
## Run under a virtual display:
##   godot --path . res://tools/camera_pass/camera_pass.tscn -- --shot-dir <dir>
##   (add `--themes village,warlord` to shoot a subset)
##
## The driver survives level swaps by manually instancing dungeon.tscn
## instead of change_scene_to_file (which would free this node).

const THEMES: Array[String] = ["village", "dungeon", "depths", "supermarket", "warlord"]
const SEEDS := {
	"village": 424242,
	"dungeon": 777001,
	"depths": 900100,
	"supermarket": 313370,
	"warlord": 555010,
}
const SETTLE_TIME := 7.0
const WAVE_THEMES: Array[String] = ["village", "dungeon", "depths"]

var _shot_dir := "user://camera_pass"
var _counts := {}
var _shot_total := 0
var _cam: Camera3D = null
var _pending_themes: PackedStringArray = []
## Player kept at full HP during the pass so mobs can swarm for action
## shots without the death screen ruining the footage.
var _pass_player: Node = null


func _physics_process(_delta: float) -> void:
	_top_up()


func _process(_delta: float) -> void:
	_top_up()


func _top_up() -> void:
	if _pass_player != null and is_instance_valid(_pass_player):
		if bool(_pass_player.get("alive")):
			_pass_player.set("hp", _pass_player.get("max_hp"))


func _ready() -> void:
	_parse_args()
	# Let the bootstrap scene finish entering the tree before swapping levels.
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	NetworkManager.selected_class_id = "mage"
	var themes: Array[String] = THEMES.duplicate()
	if not _pending_themes.is_empty():
		themes = themes.filter(func(t): return t in _pending_themes)
	for theme in themes:
		await _capture_theme(theme)
	# Park on an empty scene so the last level's audio/processes stop.
	print("[CameraPass] DONE total_shots=%d dir=%s" % [_shot_total, _shot_dir])
	get_tree().quit()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--shot-dir" and i + 1 < args.size():
			_shot_dir = args[i + 1]
			i += 2
		elif args[i] == "--themes" and i + 1 < args.size():
			# Debug/reshot: comma-separated subset, e.g. --themes village,warlord
			_pending_themes = args[i + 1].split(",")
			i += 2
		else:
			i += 1


func _capture_theme(theme: String) -> void:
	print("[CameraPass] === theme: %s ===" % theme)
	NetworkManager.leave_lobby()
	NetworkManager.is_host = true
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = theme
	Dungeon.next_seed = int(SEEDS[theme])
	Dungeon.next_level_number = 1
	_swap_to_dungeon()
	await get_tree().create_timer(SETTLE_TIME).timeout
	var dungeon := get_tree().current_scene
	if dungeon == null or not dungeon.has_method("_start_wave"):
		push_warning("[CameraPass] dungeon scene not ready for theme %s, skipping" % theme)
		return
	var player := _find_player()
	if player == null:
		push_warning("[CameraPass] no player spawned for theme %s, skipping" % theme)
		return
	_take_over_camera()
	_pass_player = player
	var focus: Vector3 = player.global_position
	# 1. Wide establishing shot.
	await _fly_to(focus + Vector3(20, 16, 20), focus + Vector3(0, 2, 0), 1.6)
	await _snap(theme, "wide")
	# 2-4. Orbit around the player.
	for i in range(3):
		var ang := TAU * float(i) / 3.0 + 0.5
		var pos := focus + Vector3(cos(ang) * 10.0, 5.0, sin(ang) * 10.0)
		await _fly_to(pos, focus + Vector3(0, 1.5, 0), 1.2)
		await _snap(theme, "orbit%d" % i)
	# 5. Theme-specific action.
	if theme in WAVE_THEMES:
		dungeon._start_wave()
		await get_tree().create_timer(5.0).timeout
		for i in range(2):
			var ang2 := TAU * (0.15 + 0.35 * float(i))
			var pos2 := focus + Vector3(cos(ang2) * 7.0, 3.5, sin(ang2) * 7.0)
			await _fly_to(pos2, focus + Vector3(0, 1.2, 0), 0.8)
			await _snap(theme, "combat%d" % i)
	elif theme == "warlord":
		# High top-down view of the RTS battlefield.
		await _fly_to(focus + Vector3(0, 48, 20), focus, 1.6)
		await _snap(theme, "topdown")
	elif theme == "supermarket":
		# Low shot down the main aisle toward the checkout glow.
		await _fly_to(focus + Vector3(-8, 3.2, 10), focus + Vector3(6, 1.5, -6), 1.2)
		await _snap(theme, "aisle")


func _swap_to_dungeon() -> void:
	var tree := get_tree()
	var cur := tree.current_scene
	if cur != null and cur != self:
		# Park current_scene on the driver (not null): the new scene's _ready
		# fires during add_child, and game code (e.g. positional SFX) expects
		# a valid current_scene at that point.
		tree.current_scene = self
		cur.queue_free()
		await tree.process_frame
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	var inst := packed.instantiate()
	tree.root.add_child(inst)
	tree.current_scene = inst


func _find_player() -> Node:
	var players := get_tree().get_nodes_in_group("players")
	for p in players:
		if p.get_multiplayer_authority() == multiplayer.get_unique_id():
			return p
	if not players.is_empty():
		return players[0]
	return null


func _take_over_camera() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		var pcam := p.find_child("Camera3D", true, false) as Camera3D
		if pcam != null:
			pcam.current = false
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "PassCamera"
		_cam.far = 220.0
		# Parented to root (not the level) so it survives theme swaps.
		get_tree().root.add_child(_cam)
		_cam.global_position = Vector3(0, 20, 20)
	_cam.current = true


func _fly_to(pos: Vector3, look: Vector3, hold: float) -> void:
	var from: Vector3 = _cam.global_position
	var t := 0.0
	var dur := 1.2
	while t < 1.0:
		t = minf(1.0, t + get_process_delta_time() / dur)
		var s := t * t * (3.0 - 2.0 * t)
		_cam.global_position = from.lerp(pos, s)
		_cam.look_at(from.lerp(look, s))
		await get_tree().process_frame
	_cam.look_at(look)
	await get_tree().create_timer(hold).timeout


func _snap(theme: String, label: String) -> void:
	var c: int = int(_counts.get(theme, 0)) + 1
	_counts[theme] = c
	# Let the frame actually draw before capturing.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%02d_%s.png" % [_shot_dir, theme, c, label]
	var err := img.save_png(path)
	_shot_total += 1
	print("[CameraPass] shot %s err=%s" % [path, err])
