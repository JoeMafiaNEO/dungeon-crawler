extends Node3D
## Issue #204 (P4): the real-world scene — Act 2's ground.
## Built from the standard kit the train hop proved: real
## Player nodes, the HUD, the session's multiplayer, late-join
## by state pull. Per-peer by design: each peer's world scene
## is its own (its own WorldStreamer focused on its own
## player — the world is derived data, no shared streaming
## state, no server arbitration), and party members arrive
## independently through the rooftop door.
##
## The root owns: the clock-driven environment (all
## presentation derived locally from Dungeon.world_time via
## WorldClock — the P2 parameter mechanism), the home
## building's standalone assembly on the reveal's reserved
## plot, the entry ready-gate (the inner chunk ring fully
## built behind a black fade before the first look — the P3
## toast-cover pattern), the local player's spawn, a light
## presence protocol for peers in the world together, and
## the death pipeline: a street death respawns at the Act 2
## record's anchor doorstep.
##
## State pull (#135-style): a client whose statics were never
## restored (a fresh joiner) asks the server's world root for
## the reveal + act2 snapshot and waits — bounded — before
## building. In the door-entry and continued-run flows the
## statics are already in place and no pull happens.

const PlayerScene := preload("res://scenes/player/player.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const WorldGen := preload("res://scripts/world/world_gen.gd")
const WorldClock := preload("res://scripts/world/world_clock.gd")
const StreamerScript := preload("res://scripts/world/world_streamer.gd")

const GATE_BOUND_S := 3.0
const PULL_BOUND_S := 2.0
const CLOCK_SAVE_EVERY_S := 30.0
const CLOCK_SYNC_EVERY_S := 5.0

var _streamer: Node3D = null
var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _sun: DirectionalLight3D = null
var _local_player: Player = null
var _local_hud: CanvasLayer = null
var _fade: ColorRect = null
var _gate_open := false
var _gate_deadline := 0.0
var _spawn_point := Vector3.ZERO
var _presence := {} # peer_id -> Player (remote world peers)
var _clock_t := 0.0
var _sync_t := 0.0
var _save_t := 0.0
var _respawn_in := -1.0
var _started := false


func _ready() -> void:
	# Issue #237: the record funnel samples street
	# positions only while a world scene is live on the
	# peer building the record — this group is its gate.
	add_to_group("world_root")
	_build_environment()
	_streamer = get_node_or_null("WorldStreamer")
	_build_fade()
	if _needs_pull():
		_gate_deadline = Time.get_ticks_msec() / 1000.0 \
			+ PULL_BOUND_S + GATE_BOUND_S
		rpc_id(NetworkManager.server_peer_id,
			"world_state_request")
	else:
		_begin()


func _needs_pull() -> bool:
	if multiplayer.multiplayer_peer == null \
			or multiplayer.is_server():
		return false
	return Dungeon.home_anchor.is_empty()


## The server root answers a joiner's pull with the run's
## reveal + Act 2 snapshot (the run record's shape, so the
## client restores through the same restore functions a
## continue uses).
## The pull's payload: the run record's own shape, so the
## client restores through the same functions a continue uses.
func state_snapshot() -> Dictionary:
	return {"revealed": Dungeon.revealed,
		"buildings_cleared": Dungeon.buildings_cleared,
		"home_anchor": Dungeon.home_anchor,
		"act2": Dungeon.act2_record(),
		"world_time": Dungeon.world_time}


@rpc("any_peer")
func world_state_request() -> void:
	if not multiplayer.is_server():
		return
	rpc_id(multiplayer.get_remote_sender_id(),
		"world_state_apply", state_snapshot())


@rpc("any_peer")
func world_state_apply(snap: Dictionary) -> void:
	if _started:
		return
	Dungeon.restore_reveal_state(snap)
	Dungeon.restore_act2_state(snap)
	_begin()


func _begin() -> void:
	if _started:
		return
	_started = true
	_gate_deadline = Time.get_ticks_msec() / 1000.0 + GATE_BOUND_S
	if Dungeon.world_time <= 0.0:
		Dungeon.world_time = WorldClock.ENTRY_TIME
	_spawn_point = _arrival_point()
	_setup_streamer()
	_build_home()
	_spawn_local()
	_announce_presence()


## Arrival: the anchor's doorstep after a door transition;
## on a continue, the player's own stored street position
## (issue #237 — Jesse's amendment of the #204 rule);
## else the record's last transition point; else the
## doorstep. Y is re-sampled from the terrain function at
## the point itself (the record's y is the ground at the
## building's center). Death respawns never come here —
## they use the anchor doorstep directly.
func _arrival_point() -> Vector3:
	var p := Vector3.ZERO
	var from_stored := false
	if Dungeon.act2_spawn_at == "doorstep":
		Dungeon.act2_spawn_at = ""
		p = Dungeon.act2_anchor_doorstep
	elif not Dungeon.act2_my_position().is_empty():
		# Issue #237: my stored position — exact XZ; a
		# stored (0, 0) is a real spot, so this branch
		# tracks itself instead of the ZERO sentinel.
		var mine := Dungeon.act2_my_position()
		p = Vector3(float(mine[0]), 0.0, float(mine[1]))
		from_stored = true
	elif not Dungeon.act2_last_transition.is_empty():
		var pt: Array = Dungeon.act2_last_transition.get(
			"point", [])
		if pt.size() == 3:
			p = Vector3(float(pt[0]), float(pt[1]), float(pt[2]))
	if p == Vector3.ZERO and not from_stored:
		p = Dungeon.act2_anchor_doorstep
	p.y = WorldGen.height_at(WorldGen.WORLD_SEED, p.x, p.z) + 0.4
	return p


func _setup_streamer() -> void:
	if _streamer == null:
		return
	if not Dungeon.home_anchor.is_empty():
		var ha := Dungeon.home_anchor
		_streamer.set("suppress_rect", Rect2(
			float(ha["rect_x"]), float(ha["rect_z"]),
			float(ha["rect_w"]), float(ha["rect_d"])))
		_streamer.set("suppress_enabled", true)
	_streamer.call("set_target_position", _spawn_point)


func _build_home() -> void:
	var home := Dungeon.home_building()
	if home.is_empty():
		return
	var node: Node3D = _streamer.call(
		"build_standalone_building", home["plan"],
		home["origin"], true, str(home["key"]))
	add_child(node)


func _spawn_local() -> void:
	var class_id := Dungeon.act2_local_class
	if class_id == "":
		class_id = str(Dungeon.saved_player_state.get(
			"class_id", ""))
	if class_id == "":
		class_id = "warrior"
	_local_player = _make_player(multiplayer.get_unique_id(),
		class_id, _spawn_point)
	if not Dungeon.saved_player_state.is_empty():
		_local_player.apply_state(Dungeon.saved_player_state)
		Dungeon.saved_player_state = {}
	_local_hud = HudScene.instantiate()
	add_child(_local_hud)
	_local_hud.setup(_local_player)
	_local_player.died.connect(_on_local_died)
	if _streamer != null:
		_streamer.call("set_target_node", _local_player)


func _make_player(pid: int, class_id: String, pos: Vector3) -> Player:
	var p := PlayerScene.instantiate() as Player
	p.name = "Player_%d" % pid
	p.class_id = class_id
	p.set_multiplayer_authority(pid)
	p.position = pos
	add_child(p)
	return p


## Presence: peers in the world together see each other's
## class bodies. Deliberately light (P4): hellos carry the
## peer's class; full cross-scene state replication is later
## work. Presence is presentation — the world itself never
## depends on it.
## Issue #237: my own street position for the presence
## payload ([x, y, z], or [] when there is no local player
## to read) — a fact about the sender, announced by the
## sender; no peer derives or validates anyone's world.
func _my_presence_pos() -> Array:
	if _local_player == null:
		return []
	var gp := _local_player.global_position
	return [gp.x, gp.y, gp.z]


func _announce_presence() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	rpc("world_hello", multiplayer.get_unique_id(),
		_local_player.class_id if _local_player != null else "",
		_my_presence_pos())


@rpc("any_peer")
func world_hello(pid: int, class_id: String, pos: Array = []) -> void:
	_spawn_remote(pid, class_id, pos)
	rpc_id(pid, "world_present", multiplayer.get_unique_id(),
		_local_player.class_id if _local_player != null else "",
		_my_presence_pos())


@rpc("any_peer")
func world_present(pid: int, class_id: String, pos: Array = []) -> void:
	_spawn_remote(pid, class_id, pos)


func _spawn_remote(pid: int, class_id: String, pos: Array = []) -> void:
	if pid == multiplayer.get_unique_id() or _presence.has(pid) \
			or not _started:
		return
	# Issue #237: a hello carrying the sender's position
	# places the replica where that player actually
	# stands; without a usable one, the arrival offset
	# stands, exactly as before.
	var at := _spawn_point + Vector3(1.5, 0, 1.5)
	if pos.size() == 3 and (pos[0] is int or pos[0] is float) \
			and (pos[1] is int or pos[1] is float) \
			and (pos[2] is int or pos[2] is float) \
			and is_finite(float(pos[0])) \
			and is_finite(float(pos[1])) \
			and is_finite(float(pos[2])):
		at = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	_presence[pid] = _make_player(pid,
		class_id if class_id != "" else "warrior", at)


@rpc("any_peer")
func sync_world_time(t: float) -> void:
	if multiplayer.is_server():
		return
	# The clock is monotone: a late packet never rewinds it.
	if t > Dungeon.world_time:
		Dungeon.world_time = t


func _on_local_died() -> void:
	_respawn_in = 2.5
	if _local_hud != null and _local_hud.has_method("announce"):
		_local_hud.announce(
			"You died. You wake at the doorstep.")


func _respawn_local() -> void:
	var p := _local_player
	if p == null:
		return
	var anchor := Dungeon.act2_anchor_doorstep
	anchor.y = WorldGen.height_at(WorldGen.WORLD_SEED,
		anchor.x, anchor.z) + 0.4
	p.position = anchor
	p.velocity = Vector3.ZERO
	p.downed = false
	p.alive = true
	p.hp = p.max_hp
	p.health_changed.emit(p.hp, p.max_hp)


func _process(delta: float) -> void:
	# The clock: server-advanced, locally presented.
	if multiplayer.is_server():
		Dungeon.world_time += delta
		_sync_t += delta
		if _sync_t >= CLOCK_SYNC_EVERY_S \
				and multiplayer.multiplayer_peer != null:
			_sync_t = 0.0
			rpc("sync_world_time", Dungeon.world_time)
		_save_t += delta
		if _save_t >= CLOCK_SAVE_EVERY_S:
			_save_t = 0.0
			Dungeon.save_act2_clock()
	_clock_t += delta
	if _clock_t >= 0.25:
		_clock_t = 0.0
		_apply_clock()
	# The ready-gate.
	if _started and not _gate_open:
		if _entry_ring_ready() or Time.get_ticks_msec() \
				/ 1000.0 >= _gate_deadline:
			_gate_open = true
			var tw := create_tween()
			tw.tween_property(_fade, "color",
				Color(0, 0, 0, 0), 0.8)
	if _respawn_in > 0.0:
		_respawn_in -= delta
		if _respawn_in <= 0.0:
			_respawn_local()


## The gate's predicate: the inner chunk ring (terrain +
## buildings + scatter) around the spawn is fully built.
func _entry_ring_ready() -> bool:
	if _streamer == null:
		return true
	var scx := int(floor(_spawn_point.x / WorldGen.CHUNK_SIZE))
	var scz := int(floor(_spawn_point.z / WorldGen.CHUNK_SIZE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if not bool(_streamer.call("chunk_fully_built",
					scx + dx, scz + dz)):
				return false
	return true


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_curve = 0.09
	_sky_mat.ground_curve = 0.02
	_sky_mat.sun_angle_max = 30.0
	sky.sky_material = _sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	_env = env
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	add_child(_sun)
	_apply_clock()


## All presentation derives from world_time through the P2
## parameter mechanism (WorldClock's keyframes over the same
## sky / sun / fog fields the level themes carry).
func _apply_clock() -> void:
	if _env == null:
		return
	var p := WorldClock.params_at(Dungeon.world_time)
	_sky_mat.sky_top_color = p["sky_top_color"]
	_sky_mat.sky_horizon_color = p["sky_horizon_color"]
	_sky_mat.ground_bottom_color = (p["ground_color"]
		as Color).darkened(0.4)
	_sky_mat.ground_horizon_color = p["ground_color"]
	_sky_mat.sky_energy_multiplier = float(
		p["sky_energy_multiplier"])
	_env.ambient_light_color = p["ambient_color"]
	_env.ambient_light_energy = float(p["ambient_energy"])
	_env.fog_light_color = p["fog_color"]
	_env.fog_density = float(p["fog_density"])
	_env.fog_sky_affect = float(p["fog_sky_affect"])
	_sun.light_color = p["sun_color"]
	_sun.light_energy = float(p["sun_energy"])
	var dir := (p["sun_direction"] as Vector3).normalized()
	_sun.rotation = Vector3(asin(clampf(-dir.y, -1.0, 1.0)),
		atan2(-dir.x, -dir.z), 0.0)
