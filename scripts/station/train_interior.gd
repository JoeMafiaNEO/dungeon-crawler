class_name TrainInterior
extends Node3D
## Physical train-car interior — the party rides here between levels.
##
## Phase 1: deterministic car shell (floor/walls/ceiling, window frames,
## bench seats, sliding end doors + SFX, lamps), 4 aisle spawn points.
## Phase 2: boarding is over when the scene loads (doors_locked) — the
## dungeon's ALL ABOARD flow drove per-player boarding first.
## Phase 3: the real ride — 25s server-authoritative timer, scrolling window
## scenery (procedural, seeded), chug/rumble loop, E-interact skip lever,
## background load of the next dungeon, arrival (brake screech, platform
## visible through the windows, doors open + unlock), then disembark through
## the car door into the next dungeon's annex (with a straggler fallback).

## Handoff statics (set by the dungeon before change_scene_to_file).
static var passenger_classes: Dictionary = {} # peer_id -> class_id
static var ride_theme_id: String = "village" # destination theme
## Issue #3 Phase 2: the dungeon locks the car doors when boarding completes
## (all aboard or timer expiry) — nobody re-opens them during the ride.
static var doors_locked := false
## Ride state (issue #3 Phase 3): the server sets these when the ride starts;
## a peer whose _ready runs after the server's ride_started rpc applies them
## locally instead of missing the ride. Reset by board_train_interior.
static var ride_active := false
static var ride_dest_name := ""
static var ride_seconds := 25.0
## Test/driver override: when > 0 the ride lasts this long instead.
static var ride_seconds_override := 0.0

## Full ride length. The skip lever fast-forwards to ~2s remaining.
const RIDE_SECONDS := 25.0
## After arrival, stragglers still in the car are pulled through the door.
const DISEMBARK_WINDOW := 20.0
const DUNGEON_SCENE := "res://scenes/dungeon/dungeon.tscn"

const CAR_L := 16.0
const CAR_W := 5.0
const WALL_H := 3.2
const DOOR_W := 2.2

const PlayerScene := preload("res://scenes/player/player.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")

var _doors: Array = [] # sliding door panels (MeshInstance3D)
var _doors_open := false
var _door_tween: Tween = null
var _local_hud: CanvasLayer = null

# --- Ride state (issue #3 Phase 3) ---
var _riding := false
var _arrived := false
var _skipping := false
var _ride_left := 0.0
var _ride_dest := ""
var _last_ride_sec := -1
var _chug_timer := 0.0
var _disembarked := {} # peer_id -> true (server-side)
var _disembarked_local := false
var _scenery_root: Node3D = null
var _scenery_mats: Array = []
var _platform_root: Node3D = null
var _door_blocker: StaticBody3D = null
var _disembark_area: Area3D = null
var _skip_lever: Node3D = null


## E-interact skip lever (issue #3 Phase 3). The player's
## _nearest_interact_node picks it up via the "skip_lever" group; it is only
## visible (hence interactable) while the train is riding.
class SkipLever extends Node3D:
	var interior: TrainInterior = null

	func prompt_text() -> String:
		return "Pull the skip lever"

	func interact(_player: Player) -> void:
		if interior != null and interior.is_riding():
			interior.rpc("request_skip_ride")


func _ready() -> void:
	_build_car()
	_build_scenery()
	_build_platform()
	_build_skip_lever()
	_build_disembark_zone()
	_spawn_passengers()
	if _local_hud != null:
		_local_hud.fade_in(1.5)
	if not doors_locked:
		open_doors()
	# Background-load the next dungeon during the ride so disembark is instant.
	ResourceLoader.load_threaded_request(DUNGEON_SCENE)
	# Late-apply: the server may have rpc'd ride_started before this peer's
	# _ready ran (all peers change scene at once).
	if ride_active:
		_apply_ride_started()
	if multiplayer.is_server():
		_run_ride()


func is_riding() -> bool:
	return _riding and not _arrived


## Server drives the ride clock; every peer ticks its own copy in _process
## (scenery easing + HUD). Skip shortens the clock; arrival is an RPC.
func _run_ride() -> void:
	ride_active = true
	ride_dest_name = _dest_display_name()
	ride_seconds = ride_seconds_override if ride_seconds_override > 0.0 else RIDE_SECONDS
	_ride_left = ride_seconds
	# Let every peer finish loading the car before the ride starts.
	await get_tree().create_timer(1.0).timeout
	if not ride_active:
		return
	rpc("ride_started", ride_dest_name, ride_seconds)
	while ride_active and _ride_left > 0.0:
		await get_tree().create_timer(0.5).timeout
	if ride_active:
		rpc("begin_arrival")


## Ride begins (all peers): HUD status, scenery rolls, chug/rumble loop.
@rpc("any_peer", "call_local")
func ride_started(dest_name: String, seconds: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	ride_active = true
	ride_dest_name = dest_name
	ride_seconds = seconds
	_apply_ride_started()


func _apply_ride_started() -> void:
	if _riding:
		return
	_riding = true
	_ride_dest = ride_dest_name
	_ride_left = ride_seconds
	_last_ride_sec = -1
	_chug_timer = 0.0
	_scenery_root.visible = true
	_skip_lever.visible = true
	AudioManager.sfx("train_chug")
	_show_ride_hud()


func _process(delta: float) -> void:
	if not _riding or _arrived:
		return
	_ride_left -= delta
	# Scenery: full speed until 8s out, eases to a stop by 3s out.
	var f := _scenery_speed_factor(_ride_left)
	for m in _scenery_mats:
		(m as StandardMaterial3D).uv1_offset.x -= 0.9 * f * delta
	# Chug + rumble loop (one-shots re-triggered, like the departure ride).
	_chug_timer -= delta
	if _chug_timer <= 0.0:
		_chug_timer = 2.0
		AudioManager.sfx("train_chug", null, randf_range(0.92, 1.08), 0.7)
		AudioManager.sfx("rumble", null, randf_range(0.85, 1.0), 0.5)
	var sec := int(ceil(maxf(_ride_left, 0.0)))
	if sec != _last_ride_sec:
		_last_ride_sec = sec
		_show_ride_hud()


## Pure easing curve (testable): 1.0 while cruising, 0.0 once stopped.
static func _scenery_speed_factor(time_left: float) -> float:
	return clampf((time_left - 3.0) / 5.0, 0.0, 1.0)


func _show_ride_hud() -> void:
	var hud := _local_hud
	if hud == null or not hud.has_method("show_ride_status"):
		return
	var title := "RIDING TO " + _ride_dest.to_upper()
	if _skipping:
		title = "SKIPPING AHEAD"
	hud.show_ride_status(title, _ride_left)


## Skip lever pulled (server): fast-forward to ~2s remaining, tell peers.
@rpc("any_peer", "call_local")
func request_skip_ride() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not is_riding():
		return
	_apply_skip()
	rpc("ride_skip_notice")


## Pure skip (testable): the clock jumps to ~2s, never backwards past arrival.
func _apply_skip() -> void:
	_ride_left = minf(_ride_left, 2.0)


@rpc("any_peer", "call_local")
func ride_skip_notice() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	_apply_skip()
	_skipping = true
	_show_ride_hud()


## Arrival (all peers): brake screech, banner, scenery -> platform, doors
## open + unlock, disembark zone live. The server then runs the straggler
## fallback window.
@rpc("any_peer", "call_local")
func begin_arrival() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	if _arrived:
		return
	_arrived = true
	_riding = false
	ride_active = false
	AudioManager.sfx("train_brake")
	if _local_hud != null:
		_local_hud.announce("NOW ARRIVING: " + _ride_dest, Dungeon.arrival_tint(ride_theme_id))
		if _local_hud.has_method("hide_station_timer"):
			_local_hud.hide_station_timer()
	_scenery_root.visible = false
	_platform_root.visible = true
	_skip_lever.visible = false
	doors_locked = false
	open_doors()
	if _door_blocker != null and is_instance_valid(_door_blocker):
		_door_blocker.queue_free()
	_door_blocker = null
	_disembark_area.monitoring = true
	if multiplayer.is_server():
		_run_disembark_window()


## Server: after the disembark window, pull any stragglers through the door
## so the run can never soft-lock in the car.
func _run_disembark_window() -> void:
	await get_tree().create_timer(DISEMBARK_WINDOW).timeout
	for pid in passenger_classes.keys():
		if not _disembarked.has(int(pid)):
			rpc_id(int(pid), "do_disembark")


func _on_disembark_body_entered(body: Node3D) -> void:
	if not _arrived:
		return
	if not body.is_in_group("players"):
		return
	if int(body.get_multiplayer_authority()) != multiplayer.get_unique_id():
		return
	rpc("request_disembark")


## A peer walked its player through the open car door: the server records it
## and tells that peer to hop.
@rpc("any_peer", "call_local")
func request_disembark() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not _arrived or _disembarked.has(sender):
		return
	_disembarked[sender] = true
	rpc_id(sender, "do_disembark")


## Disembark (targeted RPC from the server): capture state, flag the dungeon
## to spawn in the annex, and hop to the background-loaded scene.
@rpc("any_peer", "call_local")
func do_disembark() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	if _disembarked_local:
		return
	_disembarked_local = true
	# State capture (per peer, local): without this the hop wipes progression.
	var me := _my_player()
	if me != null:
		Dungeon.saved_player_state = me.get_state()
	Dungeon.spawn_in_annex = true
	Dungeon.arrived_by_train = true
	var ps: PackedScene = ResourceLoader.load_threaded_get(DUNGEON_SCENE) as PackedScene
	if ps != null and ps.can_instantiate():
		get_tree().call_deferred("change_scene_to_packed", ps)
	else:
		get_tree().call_deferred("change_scene_to_file", DUNGEON_SCENE)


func _dest_display_name() -> String:
	var lt: LevelTheme = load("res://data/levels/theme_%s.tres" % ride_theme_id) as LevelTheme
	if lt != null:
		return lt.display_name
	return ride_theme_id


## Sliding car doors (rear end). Tween when in the tree, snap otherwise
## (lets tests drive the state machine without a scene tree). Locked doors
## (issue #3 Phase 2) never re-open during the ride.
func open_doors() -> void:
	if _doors_open or doors_locked:
		return
	_doors_open = true
	AudioManager.sfx("train_door_open")
	_animate_doors()


func close_doors() -> void:
	if not _doors_open:
		return
	_doors_open = false
	AudioManager.sfx("train_door_close")
	_animate_doors()


## Lock the car for the ride: doors close and stay closed.
func lock_doors() -> void:
	doors_locked = true
	close_doors()


func _animate_doors() -> void:
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()
	_door_tween = null
	for d in _doors:
		var tz: float = float(d.get_meta("open_z")) if _doors_open else float(d.get_meta("closed_z"))
		if is_inside_tree():
			if _door_tween == null:
				_door_tween = create_tween().set_parallel()
			_door_tween.tween_property(d, "position:z", tz, 0.6).set_trans(Tween.TRANS_SINE)
		else:
			d.position.z = tz


## Boarding spots down the center aisle, one per max party member.
func spawn_points() -> Array:
	return [
		Vector3(-5.0, 0.1, 0.0),
		Vector3(-2.0, 0.1, 0.0),
		Vector3(1.0, 0.1, 0.0),
		Vector3(4.0, 0.1, 0.0),
	]


## Deterministic on every peer: the boarding rpc transitioned everyone at
## once, so each peer spawns the full roster locally (no spawn rpcs needed).
func _spawn_passengers() -> void:
	var spots := spawn_points()
	var pids := passenger_classes.keys()
	pids.sort()
	var i := 0
	for pid in pids:
		var p := PlayerScene.instantiate() as Player
		p.name = "Player_%d" % pid
		p.class_id = str(passenger_classes[pid])
		p.set_multiplayer_authority(int(pid))
		p.position = spots[i % spots.size()]
		add_child(p)
		if int(pid) == multiplayer.get_unique_id():
			if not Dungeon.saved_player_state.is_empty():
				p.apply_state(Dungeon.saved_player_state)
				Dungeon.saved_player_state = {}
			_local_hud = HudScene.instantiate()
			add_child(_local_hud)
			_local_hud.setup(p)
		i += 1


func _my_player() -> Player:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != null and p.get_multiplayer_authority() == multiplayer.get_unique_id():
			return p
	return null


# --- Car construction ---

func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


## Solid box: collision + visual mesh. Collision layer 1, no mask (static world).
func _solid(size: Vector3, pos: Vector3, mat: Material, node_name: String = "",
		parent: Node3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	if node_name != "":
		body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	body.position = pos
	(parent if parent != null else self).add_child(body)
	return body


## Visual-only box (no collision).
func _visual(size: Vector3, pos: Vector3, mat: Material, node_name: String = "",
		parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if node_name != "":
		mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


## Collision-only box (invisible).
func _blocker(size: Vector3, pos: Vector3, node_name: String = "") -> StaticBody3D:
	var body := StaticBody3D.new()
	if node_name != "":
		body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	add_child(body)
	return body


func _build_car() -> void:
	var wood := _mat(Color(0.36, 0.24, 0.14))
	var wall_red := _mat(Color(0.45, 0.16, 0.14))
	var cream := _mat(Color(0.82, 0.76, 0.62))
	var brass := _mat(Color(0.72, 0.55, 0.25))
	var cushion := _mat(Color(0.55, 0.12, 0.12))
	var dark := _mat(Color(0.10, 0.09, 0.11))
	var glass := _mat(Color(0.55, 0.70, 0.85, 0.35))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var lamp_glow := _mat(Color(1.0, 0.88, 0.60), Color(1.0, 0.78, 0.45), 3.0)

	# Floor (top at y=0) and ceiling.
	_solid(Vector3(CAR_L, 1.0, CAR_W), Vector3(0, -0.5, 0), wood, "CarFloor")
	_solid(Vector3(CAR_L + 0.8, 0.4, CAR_W + 0.8), Vector3(0, WALL_H + 0.2, 0), cream, "CarCeiling")

	# Side walls with real window openings (issue #3 Phase 3): full-length
	# sill (y 0..1.45) and header (y 2.55..3.2), plus segments between the
	# window gaps (gaps at wx±0.85, y 1.45..2.55).
	var win_x := [-5.25, -1.75, 1.75, 5.25]
	for side in [1.0, -1.0]:
		var sname := "North" if side > 0.0 else "South"
		var zc: float = side * 2.7
		_solid(Vector3(CAR_L, 1.45, 0.4), Vector3(0, 0.725, zc), wall_red, "WallSill" + sname)
		_solid(Vector3(CAR_L, 0.65, 0.4), Vector3(0, 2.875, zc), wall_red, "WallHeader" + sname)
		var edges := [-8.0]
		for wx in win_x:
			edges.append(wx - 0.85)
			edges.append(wx + 0.85)
		edges.append(8.0)
		var seg := 0
		for i in range(0, edges.size(), 2):
			var x0: float = edges[i]
			var x1: float = edges[i + 1]
			_solid(Vector3(x1 - x0, 1.1, 0.4), Vector3((x0 + x1) * 0.5, 2.0, zc),
					wall_red, "WallSeg%s_%d" % [sname, seg])
			seg += 1

	# Front end wall (x=+8, solid).
	_solid(Vector3(0.4, WALL_H, CAR_W + 0.8), Vector3(8.2, WALL_H * 0.5, 0), wall_red, "WallFront")

	# Rear end wall (x=-8) with a centered doorway gap.
	var seg_w := (CAR_W + 0.8 - DOOR_W) * 0.5
	var seg_z := DOOR_W * 0.5 + seg_w * 0.5
	_solid(Vector3(0.4, WALL_H, seg_w), Vector3(-8.2, WALL_H * 0.5, seg_z), wall_red, "WallRearA")
	_solid(Vector3(0.4, WALL_H, seg_w), Vector3(-8.2, WALL_H * 0.5, -seg_z), wall_red, "WallRearB")
	# Lintel above the doorway.
	_solid(Vector3(0.4, WALL_H - 2.6, DOOR_W), Vector3(-8.2, 2.6 + (WALL_H - 2.6) * 0.5, 0), wall_red, "DoorLintel")
	# Invisible blocker: the party rides inside; freed at arrival so the
	# party can disembark through the open doors.
	_door_blocker = _blocker(Vector3(0.4, 2.6, DOOR_W), Vector3(-8.2, 1.3, 0), "DoorBlocker")

	# Door frame: posts + header.
	_solid(Vector3(0.5, 2.6, 0.25), Vector3(-8.2, 1.3, DOOR_W * 0.5 + 0.125), brass, "DoorFrameA")
	_solid(Vector3(0.5, 2.6, 0.25), Vector3(-8.2, 1.3, -DOOR_W * 0.5 - 0.125), brass, "DoorFrameB")
	_visual(Vector3(0.5, 0.25, DOOR_W + 0.5), Vector3(-8.2, 2.725, 0), brass, "DoorHeader")

	# Sliding door panels (visual): closed = covering the gap, open = slid
	# sideways into the wall pockets.
	var panel_w := DOOR_W * 0.5 + 0.05
	for side in [-1.0, 1.0]:
		var panel := _visual(Vector3(0.15, 2.6, panel_w), Vector3(-8.2, 1.3, side * DOOR_W * 0.25), dark,
				"DoorPanelA" if side < 0.0 else "DoorPanelB")
		panel.set_meta("closed_z", side * DOOR_W * 0.25)
		panel.set_meta("open_z", side * (DOOR_W * 0.5 + panel_w * 0.5 + 0.1))
		# Brass leading edge (child of the panel, so it slides with it).
		var edge := MeshInstance3D.new()
		var ebm := BoxMesh.new()
		ebm.size = Vector3(0.17, 2.6, 0.08)
		ebm.material = brass
		edge.mesh = ebm
		edge.position = Vector3(0, 0, -side * (panel_w * 0.5 - 0.04))
		panel.add_child(edge)
		_doors.append(panel)

	# Window frames (border strips, so the opening stays clear) + transparent
	# glass over the wall openings.
	for side in [-1.0, 1.0]:
		for k in 4:
			var wx: float = win_x[k]
			var fz: float = side * 2.48
			_visual(Vector3(1.7, 0.15, 0.08), Vector3(wx, 2.475, fz), dark,
					"WindowFrame_%d_%d" % [1 if side > 0.0 else 0, k])
			_visual(Vector3(1.7, 0.15, 0.08), Vector3(wx, 1.525, fz), dark)
			_visual(Vector3(0.15, 0.8, 0.08), Vector3(wx - 0.775, 2.0, fz), dark)
			_visual(Vector3(0.15, 0.8, 0.08), Vector3(wx + 0.775, 2.0, fz), dark)
			_visual(Vector3(1.4, 0.8, 0.06), Vector3(wx, 2.0, side * 2.46), glass,
					"WindowGlass_%d_%d" % [1 if side > 0.0 else 0, k])

	# Bench seats along both walls (solid: players walk the aisle, not
	# through the seats).
	for side in [-1.0, 1.0]:
		_solid(Vector3(12.0, 0.5, 0.7), Vector3(0, 0.25, side * 2.0), wood, "BenchBase")
		_solid(Vector3(12.0, 0.15, 0.95), Vector3(0, 0.575, side * 1.95), cushion, "BenchSeat")
		_solid(Vector3(12.0, 0.9, 0.15), Vector3(0, 1.1, side * 2.35), cushion, "BenchBack")

	# Warm ceiling lamps.
	for lx in [-5.0, 0.0, 5.0]:
		_visual(Vector3(0.8, 0.15, 0.8), Vector3(lx, WALL_H - 0.05, 0), lamp_glow, "CarLamp")
		var omni := OmniLight3D.new()
		omni.position = Vector3(lx, WALL_H - 0.3, 0)
		omni.light_color = Color(1.0, 0.82, 0.55)
		omni.light_energy = 1.2
		omni.omni_range = 7.0
		add_child(omni)


## Scrolling countryside outside the windows (issue #3 Phase 3): two long
## unshaded planes with a seeded procedural texture, scrolled in _process.
## Hidden until the ride starts.
func _build_scenery() -> void:
	_scenery_root = Node3D.new()
	_scenery_root.name = "Scenery"
	add_child(_scenery_root)
	var tex := _make_scenery_texture()
	for side in [1.0, -1.0]:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3(24.0, 1.0, 1.0)
		mat.uv1_offset = Vector3(0.0 if side > 0.0 else 0.5, 0.0, 0.0)
		_scenery_mats.append(mat)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(240.0, 3.4)
		pm.material = mat
		mi.mesh = pm
		mi.position = Vector3(0, 1.6, side * 5.2)
		mi.rotation_degrees = Vector3(90.0 if side < 0.0 else -90.0, 0, 0)
		_scenery_root.add_child(mi)
	_scenery_root.visible = false


## Seeded passing-world texture: sky gradient, hill band, patchy fields with
## tree blobs. 512x64, one texture shared by both sides.
func _make_scenery_texture() -> ImageTexture:
	var img := Image.create(512, 64, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(int(Dungeon.next_seed))
	var sky_top := Color(0.35, 0.55, 0.85)
	var sky_bot := Color(0.70, 0.85, 0.95)
	var hill := Color(0.30, 0.45, 0.30)
	var grass := Color(0.32, 0.55, 0.28)
	var grass_dark := Color(0.22, 0.42, 0.22)
	var tree := Color(0.15, 0.32, 0.16)
	var field := Color(0.55, 0.48, 0.28)
	for x in 512:
		var tree_h := 0
		var field_h := 0
		var r := rng.randf()
		if r < 0.18:
			tree_h = rng.randi_range(6, 14)
		elif r < 0.30:
			field_h = rng.randi_range(4, 10)
		for y in 64:
			var c: Color
			if y < 20:
				c = sky_top.lerp(sky_bot, float(y) / 20.0)
			elif y < 26:
				c = hill
			else:
				c = grass if (x / 8 + y / 8) % 2 == 0 else grass_dark
				if y >= 64 - tree_h:
					c = tree
				elif y >= 64 - tree_h - field_h:
					c = field
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Arrival platform (issue #3 Phase 3): slab, lamps, crates, and a
## theme-tinted destination sign. Hidden until begin_arrival swaps the
## scrolling scenery for it.
func _build_platform() -> void:
	_platform_root = Node3D.new()
	_platform_root.name = "ArrivalPlatform"
	add_child(_platform_root)
	var concrete := _mat(Color(0.45, 0.44, 0.42))
	var stripe := _mat(Color(0.85, 0.70, 0.20))
	var post := _mat(Color(0.20, 0.18, 0.16))
	var lamp := _mat(Color(1.0, 0.90, 0.65), Color(1.0, 0.80, 0.50), 2.5)
	var crate := _mat(Color(0.50, 0.36, 0.20))
	# Slab: top at y=0, on the car's south side (the window side).
	_solid(Vector3(24.0, 1.0, 3.2), Vector3(0, -0.5, 5.8), concrete, "PlatformSlab", _platform_root)
	_visual(Vector3(24.0, 0.06, 0.35), Vector3(0, 0.03, 4.35), stripe, "PlatformStripe", _platform_root)
	for lx in [-9.0, -4.5, 0.0, 4.5, 9.0]:
		_visual(Vector3(0.18, 2.6, 0.18), Vector3(lx, 1.3, 6.9), post, "", _platform_root)
		_visual(Vector3(0.55, 0.28, 0.55), Vector3(lx, 2.75, 6.9), lamp, "", _platform_root)
	# Destination sign, theme-tinted.
	var tint: Color = Dungeon.arrival_tint(ride_theme_id)
	_visual(Vector3(0.16, 2.3, 0.16), Vector3(-1.7, 1.15, 6.4), post, "", _platform_root)
	_visual(Vector3(0.16, 2.3, 0.16), Vector3(1.7, 1.15, 6.4), post, "", _platform_root)
	_visual(Vector3(4.2, 1.0, 0.14), Vector3(0, 2.5, 6.4), post, "SignBoard", _platform_root)
	var label := Label3D.new()
	label.name = "SignLabel"
	label.text = _dest_display_name().to_upper()
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = tint.lightened(0.3)
	label.outline_size = 8
	label.position = Vector3(0, 2.5, 6.31)
	label.rotation.y = PI
	_platform_root.add_child(label)
	# Crates for flavor.
	_solid(Vector3(0.8, 0.8, 0.8), Vector3(6.0, 0.4, 6.2), crate, "", _platform_root)
	_solid(Vector3(0.8, 0.8, 0.8), Vector3(6.9, 0.4, 6.0), crate, "", _platform_root)
	_solid(Vector3(0.7, 0.7, 0.7), Vector3(6.4, 1.15, 6.1), crate, "", _platform_root)
	# End platform outside the rear doorway: disembark steps onto it.
	_solid(Vector3(5.0, 1.0, 3.4), Vector3(-10.7, -0.5, 0), concrete, "PlatformEnd", _platform_root)
	_visual(Vector3(0.18, 2.6, 0.18), Vector3(-12.0, 1.3, 1.2), post, "", _platform_root)
	_visual(Vector3(0.55, 0.28, 0.55), Vector3(-12.0, 2.75, 1.2), lamp, "", _platform_root)
	var plight := OmniLight3D.new()
	plight.position = Vector3(-12.0, 2.6, 1.2)
	plight.light_color = Color(1.0, 0.85, 0.6)
	plight.light_energy = 1.0
	plight.omni_range = 6.0
	_platform_root.add_child(plight)
	_platform_root.visible = false


## Skip lever (issue #3 Phase 3): E-interact prop near the rear door.
## Hidden (hence uninteractable) until the ride starts.
func _build_skip_lever() -> void:
	var lever := SkipLever.new()
	lever.interior = self
	lever.name = "SkipLever"
	lever.add_to_group("skip_lever")
	lever.position = Vector3(-6.5, 0.0, 1.5)
	var brass := _mat(Color(0.72, 0.55, 0.25))
	var dark := _mat(Color(0.10, 0.09, 0.11))
	var red := _mat(Color(0.70, 0.12, 0.12), Color(0.70, 0.12, 0.12), 0.8)
	var base := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = Vector3(0.4, 0.9, 0.4)
	bbm.material = dark
	base.mesh = bbm
	base.position = Vector3(0, 0.45, 0)
	lever.add_child(base)
	var handle := MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.12, 1.1, 0.12)
	hbm.material = brass
	handle.mesh = hbm
	handle.position = Vector3(0, 1.2, 0.25)
	handle.rotation.x = -0.5
	lever.add_child(handle)
	var knob := MeshInstance3D.new()
	var kbm := BoxMesh.new()
	kbm.size = Vector3(0.22, 0.22, 0.22)
	kbm.material = red
	knob.mesh = kbm
	knob.position = Vector3(0, 1.68, 0.5)
	lever.add_child(knob)
	var tag := Label3D.new()
	tag.text = "PULL TO SKIP"
	tag.font_size = 48
	tag.pixel_size = 0.008
	tag.position = Vector3(0, 2.1, 0)
	lever.add_child(tag)
	lever.visible = false
	add_child(lever)
	_skip_lever = lever


## Disembark zone (issue #3 Phase 3): Area3D in the rear doorway. Monitoring
## stays off until arrival; walking through hops the peer to the next
## dungeon (background-loaded during the ride).
func _build_disembark_zone() -> void:
	_disembark_area = Area3D.new()
	_disembark_area.name = "DisembarkZone"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.6, 2.6)
	cs.shape = box
	_disembark_area.add_child(cs)
	_disembark_area.position = Vector3(-8.2, 1.3, 0.0)
	_disembark_area.monitoring = false
	_disembark_area.monitorable = false
	_disembark_area.body_entered.connect(_on_disembark_body_entered)
	add_child(_disembark_area)
