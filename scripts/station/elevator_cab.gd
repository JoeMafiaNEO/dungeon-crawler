class_name ElevatorCab
extends Node3D
## The Act 1 ride (issue #201, spec section 3): a plain elevator cab
## that carries the party between the six opening levels. It implements
## the train interior's exact contract surface — boarding statics,
## server ride clock, the issue-#135 ride-state pull for late loaders,
## skip, passenger scrub, disembark hop — with the spec's deltas:
##
## - The cab is IDENTICAL on every ride: one fixed interior, no
##   dressing, no windows, no scenery, no destination signage —
##   nothing that varies by destination or direction.
## - The ride is the ~8s placeholder (Jesse's fork 3), accompanied by
##   a subtle synthesized hum, in-cab only. No music, no recordings.
## - Arrival announces the destination's display name ALONE (fork 4).
## - Disembark flags the dungeon with arrived_by_elevator; the train's
##   own arrival flag stays the train's (Act 2's real train and the
##   legacy interim flow keep the car — train_interior.gd is untouched).

## Handoff statics (set by the dungeon before change_scene_to_file).
## Same names/roles as the train interior's, so the boarding handler
## drives either vehicle identically.
static var passenger_classes: Dictionary = {} # peer_id -> class_id
static var passenger_steam_ids: Dictionary = {} # peer_id -> Steam ID (name bar)
static var ride_theme_id: String = "village" # destination theme
static var doors_locked := false
static var ride_active := false
static var ride_dest_name := ""
static var ride_seconds := 8.0
## Test/driver override: when > 0 the ride lasts this long instead.
static var ride_seconds_override := 0.0

## Full ride length (fork 3 placeholder). The skip button
## fast-forwards to ~2s remaining.
const RIDE_SECONDS := 8.0
const DUNGEON_SCENE := "res://scenes/dungeon/dungeon.tscn"

const CAB_L := 9.0
const CAB_W := 5.0
const WALL_H := 3.2
const DOOR_W := 2.2

const PlayerScene := preload("res://scenes/player/player.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")

var _doors: Array = [] # sliding door panels (MeshInstance3D)
var _doors_open := false
var _door_tween: Tween = null
var _local_hud: CanvasLayer = null

# --- Ride state (mirrors the train interior's) ---
var _riding := false
var _arrived := false
var _skipping := false
var _ride_left := 0.0
var _ride_dest := ""
var _disembarked_local := false
var _door_blocker: StaticBody3D = null
var _disembark_area: Area3D = null
var _skip_button: Node3D = null
var _hum_player: AudioStreamPlayer = null
var _hum_on := false


## E-interact skip button. The player's _nearest_interact_node picks
## it up via the "skip_lever" group (shared with the train's lever);
## it is only visible (hence interactable) while the cab is riding.
class SkipButton extends Node3D:
	var interior: ElevatorCab = null

	func prompt_text() -> String:
		return "Press to skip"

	func interact(_player: Player) -> void:
		if interior != null and interior.is_riding():
			interior.rpc("request_skip_ride")


func _ready() -> void:
	_build_cab()
	_build_skip_button()
	_build_disembark_zone()
	_build_hum()
	_spawn_passengers()
	if _local_hud != null:
		_local_hud.fade_in(1.5)
	if not doors_locked:
		open_doors()
	# Background-load the next dungeon during the ride so disembark is instant.
	ResourceLoader.load_threaded_request(DUNGEON_SCENE)
	# Issue #135 (mirrored): a client that finishes loading after the
	# server's one-shot broadcasts pulls the live state instead of
	# reading statics it can never see.
	if not multiplayer.is_server():
		_pull_ride_state()
	if multiplayer.is_server():
		_run_ride()


func is_riding() -> bool:
	return _riding and not _arrived


## Server drives the ride clock; every peer ticks its own copy in
## _process. Skip shortens the clock; arrival is an RPC.
func _run_ride() -> void:
	ride_active = true
	ride_dest_name = _dest_display_name()
	ride_seconds = ride_seconds_override if ride_seconds_override > 0.0 else RIDE_SECONDS
	_ride_left = ride_seconds
	# Let every peer finish loading the cab before the ride starts.
	await get_tree().create_timer(1.0).timeout
	if not ride_active:
		return
	rpc("ride_started", ride_dest_name, ride_seconds)
	while ride_active and _ride_left > 0.0:
		await get_tree().create_timer(0.5).timeout
	if ride_active:
		rpc("begin_arrival")


## Ride begins (all peers): the hum starts, the skip button appears.
## No HUD status text (fork 4 / spec section 7: the ride shows a
## neutral status or nothing — the cab shows nothing).
@rpc("any_peer", "call_local")
func ride_started(dest_name: String, seconds: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_peer_id:
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
	_skip_button.visible = true
	_start_hum()


func _process(delta: float) -> void:
	if not _riding or _arrived:
		return
	_ride_left -= delta


## Skip button pressed (server): fast-forward to ~2s remaining.
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
	if sender != 0 and sender != NetworkManager.server_peer_id:
		return
	_apply_skip()
	_skipping = true


## Issue #135 ride-state pull (mirrored from the train interior): a
## client whose cab finished loading after the server's one-shot
## broadcasts asks for the live state; the server answers the
## requester only. Applying the answer is idempotent.
@rpc("any_peer", "call_local")
func request_ride_state() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	rpc_id(sender, "ride_state_sync", _arrived, _riding, _ride_dest, _ride_left)


@rpc("any_peer", "call_local")
func ride_state_sync(arrived: bool, riding: bool, dest_name: String, seconds_left: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_peer_id:
		return
	_apply_ride_state(arrived, riding, dest_name, seconds_left)


## The sync application itself (no multiplayer access — tests drive
## this directly on a bare cab).
func _apply_ride_state(arrived: bool, riding: bool, dest_name: String, seconds_left: float) -> void:
	if _arrived or _disembarked_local:
		return
	if arrived:
		_ride_dest = dest_name
		_apply_arrival()
	elif riding:
		ride_dest_name = dest_name
		ride_seconds = seconds_left
		_apply_ride_started()
		_watch_arrival_deadline(seconds_left)


func _pull_ride_state() -> void:
	if multiplayer.is_server() or _arrived or _disembarked_local:
		return
	rpc_id(NetworkManager.server_peer_id, "request_ride_state")
	_watch_pull_reply()


## If the answer never comes (the server's cab wasn't loaded when we
## asked, so the request hit no node) or the ride hadn't started yet,
## ask again shortly. Stops once the ride is under way locally.
func _watch_pull_reply() -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree() or _arrived or _disembarked_local or multiplayer.is_server():
		return
	if not _riding:
		_pull_ride_state()


## A client that joined the ride mid-flight via sync re-pulls when
## the server's clock should have run out, in case the one-shot
## begin_arrival broadcast missed it too.
func _watch_arrival_deadline(seconds_left: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(seconds_left + 2.0).timeout
	if is_inside_tree() and not _arrived and not _disembarked_local and not multiplayer.is_server():
		_pull_ride_state()


## Arrival (all peers): the hum stops, the banner carries the
## destination's display name alone (fork 4), doors open + unlock,
## disembark zone live. A client that missed this one-shot broadcast
## applies the same state via the ride-state pull (issue #135).
@rpc("any_peer", "call_local")
func begin_arrival() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_peer_id:
		return
	_apply_arrival()


## Fork 4: the arrival banner is the destination's display name,
## alone — no verb, no wording around it.
func _arrival_banner() -> String:
	return _ride_dest


## The arrival state itself, shared by the broadcast and the pull.
## Idempotent: the _arrived guard makes a second application a no-op.
func _apply_arrival() -> void:
	if _arrived:
		return
	_arrived = true
	_riding = false
	ride_active = false
	_stop_hum()
	if _local_hud != null:
		_local_hud.announce(_arrival_banner(), Dungeon.arrival_tint(ride_theme_id))
		if _local_hud.has_method("hide_station_timer"):
			_local_hud.hide_station_timer()
	_skip_button.visible = false
	doors_locked = false
	open_doors()
	if _door_blocker != null and is_instance_valid(_door_blocker):
		_door_blocker.queue_free()
	_door_blocker = null
	_disembark_area.monitoring = true
	# Disembark is local and voluntary (issue #92, mirrored): every
	# peer walks through the open door on its own schedule and hops
	# via do_disembark() directly.


func _on_disembark_body_entered(body: Node3D) -> void:
	if not _arrived:
		return
	if not body.is_in_group("players"):
		return
	if int(body.get_multiplayer_authority()) != multiplayer.get_unique_id():
		return
	# Local hop (issue #92): no server RPC.
	do_disembark()


## Disembark (local, voluntary): capture state, flag the dungeon to
## spawn in the annex as an elevator arrival, and hop to the
## background-loaded scene. Every peer calls this directly when its
## player walks through the open door (issue #92).
func do_disembark() -> void:
	if _disembarked_local:
		return
	_disembarked_local = true
	# Scrub our player node from the cab on all peers (Jesse
	# 2026-10-08): without this a ghost body is left at the exit,
	# blocking the door for everyone still aboard.
	rpc("scrub_passenger", multiplayer.get_unique_id())
	# State capture (per peer, local): without this the hop wipes progression.
	var me := _my_player()
	if me != null:
		Dungeon.saved_player_state = me.get_state()
	Dungeon.spawn_in_annex = true
	Dungeon.arrived_by_elevator = true
	var ps: PackedScene = ResourceLoader.load_threaded_get(DUNGEON_SCENE) as PackedScene
	if ps != null and ps.can_instantiate():
		get_tree().call_deferred("change_scene_to_packed", ps)
	else:
		get_tree().call_deferred("change_scene_to_file", DUNGEON_SCENE)


## Remove a disembarked peer's player node from the cab (all peers).
@rpc("any_peer", "call_local")
func scrub_passenger(peer_id: int) -> void:
	var node := get_node_or_null("Player_%d" % peer_id)
	if node != null:
		node.queue_free()


func _dest_display_name() -> String:
	var lt: LevelTheme = load("res://data/levels/theme_%s.tres" % ride_theme_id) as LevelTheme
	if lt != null:
		return lt.display_name
	return ride_theme_id


## Sliding cab doors (rear end). Tween when in the tree, snap
## otherwise (lets tests drive the state machine without a scene
## tree). Locked doors never re-open during the ride. The cues are
## the neutral door sounds (spec section 4), not the train's.
func open_doors() -> void:
	if _doors_open or doors_locked:
		return
	_doors_open = true
	AudioManager.sfx("door_open")
	_animate_doors()


func close_doors() -> void:
	if not _doors_open:
		return
	_doors_open = false
	AudioManager.sfx("door_close")
	_animate_doors()


## Lock the cab for the ride: doors close and stay closed.
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


## Boarding spots down the center of the cab, one per player (scales
## to the 12-player cap, mirroring the train interior).
func spawn_points() -> Array:
	var count := maxi(4, passenger_classes.size())
	var spots := []
	var x0 := -3.0
	var x1 := 3.0
	for i in count:
		var t := float(i) / float(maxi(1, count - 1))
		spots.append(Vector3(lerpf(x0, x1, t), 0.1, 0.0))
	return spots


## Deterministic on every peer: the boarding rpc transitioned everyone
## at once, so each peer spawns the full roster locally (no spawn
## rpcs needed). Mirrors the train interior.
func _spawn_passengers() -> void:
	var spots := spawn_points()
	var pids := passenger_classes.keys()
	pids.sort()
	var i := 0
	for pid in pids:
		var p := PlayerScene.instantiate() as Player
		p.name = "Player_%d" % pid
		p.class_id = str(passenger_classes[pid])
		p.steam_id = int(passenger_steam_ids.get(pid, 0))
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


# --- The hum (fork 3) ---

## A subtle synthesized hum for the ride's duration, in-cab only: a
## low fundamental with a soft harmonic, looped seamlessly (whole
## cycles per loop), played quietly on the SFX bus.
func _build_hum() -> void:
	_hum_player = AudioStreamPlayer.new()
	_hum_player.name = "HumPlayer"
	_hum_player.bus = "SFX"
	_hum_player.stream = _make_hum_stream()
	_hum_player.volume_db = -20.0
	add_child(_hum_player)


static func _make_hum_stream() -> AudioStreamWAV:
	var rate := 22050
	var seconds := 2.0
	var frames := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(frames * 2)
	# 55 Hz fundamental + 110 Hz harmonic: whole cycles in 2s, so the
	# loop point is click-free.
	for i in frames:
		var t := float(i) / float(rate)
		var v := sin(TAU * 55.0 * t) * 0.55 + sin(TAU * 110.0 * t) * 0.25 \
			+ sin(TAU * 165.0 * t) * 0.08
		var s := int(clampf(v, -1.0, 1.0) * 32767.0 * 0.5)
		data.encode_s16(i * 2, s)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream


func _start_hum() -> void:
	_hum_on = true
	if _hum_player != null and is_inside_tree():
		_hum_player.play()


func _stop_hum() -> void:
	_hum_on = false
	if _hum_player != null and is_inside_tree():
		_hum_player.stop()


# --- Cab construction ---

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


## The cab shell: plain walls, a ceiling, a handrail, two lamps, and
## the rear sliding doors. FIXED — this function takes no theme, no
## destination, no direction; every ride builds the identical cab.
func _build_cab() -> void:
	var wall := _mat(Color(0.52, 0.52, 0.55))
	var trim := _mat(Color(0.32, 0.32, 0.35))
	var floor_mat := _mat(Color(0.28, 0.28, 0.30))
	var steel := _mat(Color(0.62, 0.63, 0.66))
	var lamp_glow := _mat(Color(1.0, 0.90, 0.70), Color(1.0, 0.82, 0.55), 2.5)

	# Floor (top at y=0) and ceiling.
	_solid(Vector3(CAB_L, 1.0, CAB_W), Vector3(0, -0.5, 0), floor_mat, "CabFloor")
	_solid(Vector3(CAB_L + 0.8, 0.4, CAB_W + 0.8), Vector3(0, WALL_H + 0.2, 0), trim, "CabCeiling")

	# Side walls: solid, no window openings — the cab has no windows.
	_solid(Vector3(CAB_L, WALL_H, 0.4), Vector3(0, WALL_H * 0.5, 2.7), wall, "WallNorth")
	_solid(Vector3(CAB_L, WALL_H, 0.4), Vector3(0, WALL_H * 0.5, -2.7), wall, "WallSouth")

	# Front end wall (x=+4.7, solid).
	_solid(Vector3(0.4, WALL_H, CAB_W + 0.8), Vector3(4.7, WALL_H * 0.5, 0), wall, "WallFront")

	# Rear end wall (x=-4.7) with a centered doorway gap.
	var seg_w := (CAB_W + 0.8 - DOOR_W) * 0.5
	var seg_z := DOOR_W * 0.5 + seg_w * 0.5
	_solid(Vector3(0.4, WALL_H, seg_w), Vector3(-4.7, WALL_H * 0.5, seg_z), wall, "WallRearA")
	_solid(Vector3(0.4, WALL_H, seg_w), Vector3(-4.7, WALL_H * 0.5, -seg_z), wall, "WallRearB")
	# Lintel above the doorway.
	_solid(Vector3(0.4, WALL_H - 2.6, DOOR_W), Vector3(-4.7, 2.6 + (WALL_H - 2.6) * 0.5, 0), wall, "DoorLintel")
	# Invisible blocker: the party rides inside; freed at arrival so
	# the party can disembark through the open doors.
	_door_blocker = _blocker(Vector3(0.4, 2.6, DOOR_W), Vector3(-4.7, 1.3, 0), "DoorBlocker")

	# Door frame: posts + header.
	_solid(Vector3(0.5, 2.6, 0.25), Vector3(-4.7, 1.3, DOOR_W * 0.5 + 0.125), trim, "DoorFrameA")
	_solid(Vector3(0.5, 2.6, 0.25), Vector3(-4.7, 1.3, -DOOR_W * 0.5 - 0.125), trim, "DoorFrameB")
	_visual(Vector3(0.5, 0.25, DOOR_W + 0.5), Vector3(-4.7, 2.725, 0), trim, "DoorHeader")

	# Sliding door panels (visual): closed = covering the gap, open =
	# slid sideways into the wall pockets.
	var panel_w := DOOR_W * 0.5 + 0.05
	for side in [-1.0, 1.0]:
		var panel := _visual(Vector3(0.15, 2.6, panel_w), Vector3(-4.7, 1.3, side * DOOR_W * 0.25), steel,
				"DoorPanelA" if side < 0.0 else "DoorPanelB")
		panel.set_meta("closed_z", side * DOOR_W * 0.25)
		panel.set_meta("open_z", side * (DOOR_W * 0.5 + panel_w * 0.5 + 0.1))
		_doors.append(panel)

	# A plain handrail along both side walls.
	for side in [-1.0, 1.0]:
		_visual(Vector3(CAB_L - 1.6, 0.08, 0.08), Vector3(0, 1.0, side * 2.42), steel,
				"HandrailNorth" if side > 0.0 else "HandrailSouth")

	# Two plain ceiling lamps (fixed color — no theme tint, ever).
	for lx in [-2.2, 2.2]:
		_visual(Vector3(0.9, 0.12, 0.9), Vector3(lx, WALL_H - 0.04, 0), lamp_glow, "CabLamp")
		var omni := OmniLight3D.new()
		omni.position = Vector3(lx, WALL_H - 0.3, 0)
		omni.light_color = Color(1.0, 0.86, 0.62)
		omni.light_energy = 1.2
		omni.omni_range = 6.0
		add_child(omni)


## Skip button: a small plain panel with a single button, mounted by
## the doors. No label, no signage — the interact prompt names it.
## Hidden (hence uninteractable) until the ride starts.
func _build_skip_button() -> void:
	var button := SkipButton.new()
	button.interior = self
	button.name = "SkipButton"
	button.add_to_group("skip_lever")
	button.position = Vector3(-4.2, 0.0, 1.65)
	var trim := _mat(Color(0.32, 0.32, 0.35))
	var red := _mat(Color(0.65, 0.16, 0.16), Color(0.65, 0.16, 0.16), 0.7)
	var plate := MeshInstance3D.new()
	var pbm := BoxMesh.new()
	pbm.size = Vector3(0.10, 0.7, 0.5)
	pbm.material = trim
	plate.mesh = pbm
	plate.position = Vector3(0, 1.25, 0)
	button.add_child(plate)
	var knob := MeshInstance3D.new()
	var kbm := BoxMesh.new()
	kbm.size = Vector3(0.10, 0.22, 0.22)
	kbm.material = red
	knob.mesh = kbm
	knob.position = Vector3(0.08, 1.25, 0)
	button.add_child(knob)
	button.visible = false
	add_child(button)
	_skip_button = button


## Disembark zone: Area3D in the rear doorway. Monitoring stays off
## until arrival; walking through hops the peer to the next dungeon
## (background-loaded during the ride).
func _build_disembark_zone() -> void:
	_disembark_area = Area3D.new()
	_disembark_area.name = "DisembarkZone"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.6, 2.6)
	cs.shape = box
	_disembark_area.add_child(cs)
	_disembark_area.position = Vector3(-4.7, 1.3, 0.0)
	_disembark_area.monitoring = false
	_disembark_area.monitorable = false
	_disembark_area.body_entered.connect(_on_disembark_body_entered)
	add_child(_disembark_area)
