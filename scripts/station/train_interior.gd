class_name TrainInterior
extends Node3D
## Phase 1 (issue #3): physical train-car interior — the party rides here
## between levels. Boarding: the dungeon's departure rpc loads this scene
## (TrainInterior.passenger_classes carries the roster); when the placeholder
## ride ends, leave_interior() hops to the next dungeon via the hop path.
##
## The car is a fixed deterministic shell: floor, walls, ceiling, window
## frames, bench seats, sliding end doors (open/close + SFX), lamps — all
## with collision where it matters. Dressing, the real ride sequence, and
## passing-world windows are later phases.

## Handoff statics (set by the dungeon before change_scene_to_file).
static var passenger_classes: Dictionary = {} # peer_id -> class_id
static var ride_theme_id: String = "village" # destination theme (Phase 4 dressing)

## Placeholder ride length. The real ride sequence is a later phase.
const RIDE_SECONDS := 6.0

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


func _ready() -> void:
	_build_car()
	_spawn_passengers()
	if _local_hud != null:
		_local_hud.fade_in(1.5)
	open_doors()
	if multiplayer.is_server():
		_run_ride()


func _run_ride() -> void:
	await get_tree().create_timer(RIDE_SECONDS).timeout
	rpc("leave_interior")


## Ride over (all peers): doors close, fade out, capture state, load the
## next dungeon via the hop path (Dungeon.next_* were set at boarding).
@rpc("any_peer", "call_local")
func leave_interior() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	close_doors()
	if _local_hud != null:
		_local_hud.fade_out(1.2)
	await get_tree().create_timer(1.5).timeout
	# State capture (per peer, local): without this the hop wipes progression.
	# Mirrors the old go_to_station_net/change_level handoff.
	var me := _my_player()
	if me != null:
		Dungeon.saved_player_state = me.get_state()
	get_tree().call_deferred("change_scene_to_file", "res://scenes/dungeon/dungeon.tscn")


## Sliding car doors (rear end). Tween when in the tree, snap otherwise
## (lets tests drive the state machine without a scene tree).
func open_doors() -> void:
	if _doors_open:
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
func _solid(size: Vector3, pos: Vector3, mat: Material, node_name: String = "") -> StaticBody3D:
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
	add_child(body)
	return body


## Visual-only box (no collision).
func _visual(size: Vector3, pos: Vector3, mat: Material, node_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if node_name != "":
		mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
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
	var glass := _mat(Color(0.55, 0.70, 0.85), Color(0.45, 0.60, 0.80), 0.7)
	var lamp_glow := _mat(Color(1.0, 0.88, 0.60), Color(1.0, 0.78, 0.45), 3.0)

	# Floor (top at y=0) and ceiling.
	_solid(Vector3(CAR_L, 1.0, CAR_W), Vector3(0, -0.5, 0), wood, "CarFloor")
	_solid(Vector3(CAR_L + 0.8, 0.4, CAR_W + 0.8), Vector3(0, WALL_H + 0.2, 0), cream, "CarCeiling")

	# Side walls (inner faces at z=±2.5).
	_solid(Vector3(CAR_L, WALL_H, 0.4), Vector3(0, WALL_H * 0.5, 2.7), wall_red, "WallNorth")
	_solid(Vector3(CAR_L, WALL_H, 0.4), Vector3(0, WALL_H * 0.5, -2.7), wall_red, "WallSouth")

	# Front end wall (x=+8, solid).
	_solid(Vector3(0.4, WALL_H, CAR_W + 0.8), Vector3(8.2, WALL_H * 0.5, 0), wall_red, "WallFront")

	# Rear end wall (x=-8) with a centered doorway gap.
	var seg_w := (CAR_W + 0.8 - DOOR_W) * 0.5
	var seg_z := DOOR_W * 0.5 + seg_w * 0.5
	_solid(Vector3(0.4, WALL_H, seg_w), Vector3(-8.2, WALL_H * 0.5, seg_z), wall_red, "WallRearA")
	_solid(Vector3(0.4, WALL_H, seg_w), Vector3(-8.2, WALL_H * 0.5, -seg_z), wall_red, "WallRearB")
	# Lintel above the doorway.
	_solid(Vector3(0.4, WALL_H - 2.6, DOOR_W), Vector3(-8.2, 2.6 + (WALL_H - 2.6) * 0.5, 0), wall_red, "DoorLintel")
	# Invisible blocker: the party rides inside; nobody walks out the door.
	_blocker(Vector3(0.4, 2.6, DOOR_W), Vector3(-8.2, 1.3, 0), "DoorBlocker")

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

	# Window frames + glass on both side walls (visual dressing; the
	# passing-world effect is a later phase).
	for side in [-1.0, 1.0]:
		for k in 4:
			var wx := -5.25 + float(k) * 3.5
			_visual(Vector3(1.7, 1.1, 0.08), Vector3(wx, 2.0, side * 2.48), dark,
					"WindowFrame_%d_%d" % [1 if side > 0.0 else 0, k])
			_visual(Vector3(1.4, 0.8, 0.06), Vector3(wx, 2.0, side * 2.46), glass)

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
