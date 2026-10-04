class_name Station
extends Node3D
## Train station pit-stop between dungeon levels (Phase 1: shell + departure).
## Server-authoritative departure: 45s timer, or early when every living player
## stands in the boarding zone. The station then saves the run and hops to the
## next themed level.
##
## Run handoff (set before change_scene_to_file):
##   Station.next_level_number (this class) / Dungeon.saved_player_state (per peer, local)

const PlayerScene := preload("res://scenes/player/player.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const DepartureBoardScript := preload("res://scripts/station/departure_board.gd")

const DEPART_TIME := 45.0
const BOARD_CHECK := 0.5
const SAVE_STATE_TIMEOUT := 3.0

static var next_level_number: int = 1

var peer_classes := {} # int peer_id -> String class_id
var spawn_points: Array[Vector3] = [
	Vector3(-2, 1.1, -4), Vector3(0, 1.1, -4),
	Vector3(2, 1.1, -4), Vector3(0, 1.1, -2),
]
## Seed for the upcoming level, rolled once by the server on station load so
## Save & Quit and the departure hop agree on it.
var departure_seed := 0

var _local_hud: CanvasLayer
var _time_left := DEPART_TIME
var _board_tick := 0.0
var _departing := false
var _board_opened := false
var _last_sync_sec := -1
var _ring: MeshInstance3D
## Destination votes: peer_id -> theme_id (server-authoritative, Phase 2).
var votes := {}
# --- Multiplayer run-save state (trimmed mirror of dungeon's; no RTS here) ---
var _save_roster: Array = []
var _save_pending: Dictionary = {}
var _save_base: Dictionary = {}


func _ready() -> void:
	add_to_group("station")
	randomize()
	if multiplayer.is_server():
		departure_seed = randi()
	_build_station()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	AudioManager.play_music("menu")
	if multiplayer.is_server():
		var host_id := multiplayer.get_unique_id()
		peer_classes[host_id] = NetworkManager.selected_class_id
		_do_spawn(host_id, NetworkManager.selected_class_id, spawn_points[0])
	else:
		# Pull-based, like the dungeon: the server spawns us on register.
		rpc_id(NetworkManager.server_id, "register_class", NetworkManager.selected_class_id)


func _process(delta: float) -> void:
	# Gold boarding-ring pulse (all peers, pure ambience).
	if _ring != null:
		var s := 1.0 + sin(Time.get_ticks_msec() / 300.0) * 0.04
		_ring.scale = Vector3(s, 1, s)
	if not multiplayer.is_server() or _departing:
		return
	_time_left -= delta
	var sec := int(ceil(maxf(_time_left, 0.0)))
	if sec != _last_sync_sec:
		_last_sync_sec = sec
		rpc("station_timer_sync", maxf(_time_left, 0.0))
	_board_tick -= delta
	if _board_tick <= 0.0:
		_board_tick = BOARD_CHECK
		# Phase 2: all-aboard opens the departure board (vote), it no longer
		# departs by itself. Solo boards auto-open here too.
		if not _board_opened and _all_aboard():
			_board_opened = true
			rpc("open_board")
	if _time_left <= 0.0:
		depart()


## Early departure: every living player stands in the boarding zone.
func _all_aboard() -> bool:
	var zone := $BoardingZone as Area3D
	if zone == null:
		return false
	var bodies := zone.get_overlapping_bodies()
	var any_alive := false
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p == null or not bool(p.get("alive")):
			continue
		any_alive = true
		if not bodies.has(p):
			return false
	return any_alive


## Peer ids of living players (voters).
func _living_peer_ids() -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p == null or not bool(p.get("alive")):
			continue
		out.append(int(p.get_multiplayer_authority()))
	return out


## Every living player has cast a vote.
func _all_voted() -> bool:
	var living := _living_peer_ids()
	if living.is_empty():
		return false
	for pid in living:
		if not votes.has(pid):
			return false
	return true


## Destination resolution (static for testability). Non-voters don't count;
## no votes -> theme rotation (today's behavior); ties -> host's pick, else
## first tied theme in THEME_ORDER.
static func resolve_destination(p_votes: Dictionary, living: Array, host_id: int, next_level: int) -> String:
	var counts := {}
	for pid in living:
		if p_votes.has(pid):
			var t := str(p_votes[pid])
			counts[t] = int(counts.get(t, 0)) + 1
	if counts.is_empty():
		return Dungeon.THEME_ORDER[(next_level - 1) % Dungeon.THEME_ORDER.size()]
	var best := ""
	var best_n := 0
	var tied: Array = []
	for t in counts:
		var n: int = counts[t]
		if n > best_n:
			best_n = n
			best = str(t)
			tied = [str(t)]
		elif n == best_n:
			tied.append(str(t))
	if tied.size() == 1:
		return best
	if p_votes.has(host_id) and str(p_votes[host_id]) in tied:
		return str(p_votes[host_id])
	for t in Dungeon.THEME_ORDER:
		if t in tied:
			return str(t)
	return best


## Recommended level for a theme at the upcoming level: informational only.
static func recommended_level(theme_id: String, next_level: int) -> int:
	var cycle := int((next_level - 1) / Dungeon.THEME_ORDER.size()) + 1
	var idx := Dungeon.THEME_ORDER.find(theme_id)
	return (cycle - 1) * Dungeon.THEME_ORDER.size() + (idx + 1)


## Theme display name from its .tres (falls back to capitalized id).
static func theme_display_name(theme_id: String) -> String:
	var t = load("res://data/levels/theme_%s.tres" % theme_id)
	if t != null and str(t.get("display_name")) != "":
		return str(t.get("display_name"))
	return theme_id.capitalize()


## Vote for a destination. Server records; every peer syncs for board UI.
@rpc("any_peer", "call_local")
func cast_vote(theme_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not theme_id in Dungeon.THEME_ORDER:
		return
	var node := get_player_node(sender)
	if node == null or not bool(node.get("alive")):
		return
	votes[sender] = theme_id
	rpc("sync_votes", votes)
	if not _departing and _all_voted():
		depart()


## Keep every peer's board UI in sync with the server's vote table.
@rpc("any_peer", "call_local")
func sync_votes(v: Dictionary) -> void:
	votes = v.duplicate()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("refresh_departure_board"):
		hud.refresh_departure_board()


## Server opens the departure board on every peer (all-aboard trigger).
@rpc("any_peer", "call_local")
func open_board() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_departure_board"):
		hud.show_departure_board()


## "NOW ARRIVING" banner before the hop (Phase 5 will dress this further).
@rpc("any_peer", "call_local")
func announce_arrival(theme_id: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("announce"):
		hud.announce("NOW ARRIVING: " + Station.theme_display_name(theme_id))


@rpc("any_peer", "call_local")
func station_timer_sync(time_left: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_station_timer"):
		hud.show_station_timer(time_left)


## Server-authoritative departure: resolve the destination, pull
## stragglers aboard, announce, save, hop levels.
func depart() -> void:
	if _departing or not multiplayer.is_server():
		return
	_departing = true
	var new_level := next_level_number
	var theme_id := resolve_destination(votes, _living_peer_ids(), multiplayer.get_unique_id(), new_level)
	var seed := departure_seed
	# Boarding spots inside the cars (server assigns, every peer moves its own).
	var spots := {}
	var i := 0
	for pid in peer_classes:
		spots[pid] = Vector3(-13.5 + float(i % 2) * 2.0, 1.5, 3.0)
		i += 1
	rpc("pull_aboard", spots)
	rpc("announce_arrival", theme_id)
	await get_tree().create_timer(2.5).timeout
	# Save point (moved here from dungeon's change_level): persist the run so
	# it can be continued from the menu. Server-only.
	var me := _my_player()
	var cycle := (new_level - 1) / Dungeon.THEME_ORDER.size() + 1
	SaveManager.set_deepest_cycle(cycle)
	SaveManager.check_achievements()
	if me != null:
		if multiplayer.get_peers().size() > 0:
			await save_multiplayer_run(theme_id, new_level, seed)
		else:
			SaveManager.save_run({
				"theme_id": theme_id,
				"level_number": new_level,
				"class_id": me.class_id,
				"player_state": me.get_state(),
				"seed": seed,
			})
	rpc("leave_station", theme_id, seed, new_level)


@rpc("any_peer", "call_local")
func pull_aboard(spots: Dictionary) -> void:
	var me := _my_player()
	if me != null:
		var spot: Vector3 = spots.get(multiplayer.get_unique_id(), Vector3(-11, 1.5, 3))
		me.global_position = spot
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		if hud.has_method("toast"):
			hud.toast("All aboard!")
		if hud.has_method("hide_station_timer"):
			hud.hide_station_timer()
		if hud.has_method("close_departure_board"):
			hud.close_departure_board()


@rpc("any_peer", "call_local")
func leave_station(theme_id: String, new_seed: int, new_level: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	Dungeon.next_theme_id = theme_id
	Dungeon.next_seed = new_seed
	Dungeon.next_level_number = new_level
	AudioManager.sfx("portal_enter")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/dungeon/dungeon.tscn")


# --- Players (mirror of dungeon's pull-based flow, minus roster continuation) ---

@rpc("any_peer", "call_local")
func register_class(class_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	peer_classes[sender] = class_id
	_do_spawn(sender, class_id, _next_spawn_point())
	var node := get_player_node(sender)
	if node != null:
		rpc("spawn_player", sender, class_id, node.position)


@rpc("any_peer", "call_local")
func spawn_player(peer_id: int, class_id: String, pos: Vector3) -> void:
	_do_spawn(peer_id, class_id, pos)


func _next_spawn_point() -> Vector3:
	var idx := peer_classes.size() % maxi(1, spawn_points.size())
	return spawn_points[idx]


func _do_spawn(peer_id: int, class_id: String, pos: Vector3) -> void:
	if get_player_node(peer_id) != null:
		return
	var p := PlayerScene.instantiate() as Player
	p.name = "Player_%d" % peer_id
	p.class_id = class_id
	p.set_multiplayer_authority(peer_id)
	p.position = pos
	$Players.add_child(p)
	if peer_id == multiplayer.get_unique_id():
		if not Dungeon.saved_player_state.is_empty():
			p.apply_state(Dungeon.saved_player_state)
			Dungeon.saved_player_state = {}
		_local_hud = HudScene.instantiate()
		add_child(_local_hud)
		_local_hud.setup(p)
		_local_hud.show_station_mode()


@rpc("any_peer", "call_local")
func despawn_player(peer_id: int) -> void:
	var node := get_player_node(peer_id)
	if node != null:
		node.queue_free()


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	peer_classes.erase(peer_id)
	rpc("despawn_player", peer_id)


func get_player_node(peer_id: int) -> Node:
	return $Players.get_node_or_null("Player_%d" % peer_id)


func _my_player() -> Player:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != null and p.get_multiplayer_authority() == multiplayer.get_unique_id():
			return p
	return null


# --- Multiplayer run save (trimmed mirror of dungeon's; stations have no RTS) ---

func save_multiplayer_run(theme_id: String, level_number: int, level_seed: int) -> void:
	if not multiplayer.is_server():
		return
	_save_base = {
		"theme_id": theme_id,
		"level_number": level_number,
		"seed": level_seed,
		"is_multiplayer": true,
		"host_difficulty": NetworkManager.host_difficulty,
		"host_loot_mult": NetworkManager.host_loot_mult,
		"lobby": {
			"max_players": NetworkManager.MAX_PLAYERS,
			"lobby_name": "%s's Dungeon" % SteamManager.persona_name if SteamManager.initialized else "Dungeon",
		},
	}
	_save_roster.clear()
	_save_pending.clear()
	var me := _my_player()
	if me != null:
		_save_roster.append(_roster_entry(multiplayer.get_unique_id(), me))
	for pid in multiplayer.get_peers():
		_save_pending[pid] = true
	if _save_pending.is_empty():
		_write_multiplayer_save()
		return
	rpc("station_request_save_state")
	await get_tree().create_timer(SAVE_STATE_TIMEOUT).timeout
	_mark_missing_disconnected()
	_write_multiplayer_save()


func _roster_entry(steam_id: int, player_node: Node) -> Dictionary:
	return {
		"steam_id": steam_id,
		"player_name": NetworkManager.member_name(steam_id),
		"class_id": str(player_node.get("class_id")),
		"player_state": player_node.get_state(),
		"rts_faction": -1,
		"is_host": steam_id == multiplayer.get_unique_id(),
	}


func _mark_missing_disconnected() -> void:
	for pid in _save_pending:
		var node := get_player_node(pid)
		var entry := _roster_entry(pid, node) if node != null else {
			"steam_id": pid, "player_name": NetworkManager.member_name(pid),
			"class_id": "warrior", "player_state": {}, "rts_faction": -1, "is_host": false,
		}
		entry["disconnected"] = true
		_save_roster.append(entry)


func _write_multiplayer_save() -> void:
	_save_base["roster"] = _save_roster
	if not _save_roster.is_empty():
		_save_base["class_id"] = _save_roster[0].get("class_id", "warrior")
		_save_base["player_state"] = _save_roster[0].get("player_state", {})
	SaveManager.save_run(_save_base)


@rpc("any_peer", "call_local")
func station_request_save_state() -> void:
	if multiplayer.is_server():
		return
	var me := _my_player()
	if me == null:
		return
	rpc_id(NetworkManager.server_id, "station_submit_save_state", {
		"steam_id": multiplayer.get_unique_id(),
		"player_name": SteamManager.persona_name if SteamManager.initialized else "Player",
		"class_id": str(me.get("class_id")),
		"player_state": me.get_state(),
		"rts_faction": -1,
		"is_host": false,
	})


@rpc("any_peer")
func station_submit_save_state(state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _save_pending.has(sender):
		_save_pending.erase(sender)
		_save_roster.append(state)


# --- Station construction (static shell; all procedural meshes) ---

## Dusk-blue ambience: dim cool directional + warm platform lamps (in _build_station).
func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.08, 0.10, 0.22)
	sky_mat.sky_horizon_color = Color(0.28, 0.22, 0.32)
	sky_mat.ground_bottom_color = Color(0.05, 0.05, 0.08)
	sky_mat.ground_horizon_color = Color(0.12, 0.11, 0.16)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.42, 0.62)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.55, 0.60, 0.85)
	sun.light_energy = 0.35
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	add_child(sun)


func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_station() -> void:
	_build_environment()
	var stone := _mat(Color(0.42, 0.40, 0.44))
	var stone_light := _mat(Color(0.62, 0.60, 0.64))
	var dark := _mat(Color(0.16, 0.15, 0.17))
	var steel := _mat(Color(0.35, 0.36, 0.40))
	var wood := _mat(Color(0.45, 0.32, 0.20))
	var wood_dark := _mat(Color(0.32, 0.22, 0.14))
	var train_green := _mat(Color(0.10, 0.28, 0.16))
	var brass := _mat(Color(0.72, 0.55, 0.25))
	var win_glow := _mat(Color(1.0, 0.75, 0.35), Color(1.0, 0.65, 0.25), 2.5)
	var lamp_glow := _mat(Color(1.0, 0.85, 0.55), Color(1.0, 0.75, 0.40), 3.0)
	var heal_glow := _mat(Color(0.25, 0.95, 0.45), Color(0.20, 0.90, 0.40), 2.0)
	var ring_gold := _mat(Color(1.0, 0.80, 0.30), Color(1.0, 0.70, 0.20), 1.8)

	# Ground: dark ballast plane, 48 x 24.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(48, 24)
	pm.material = _mat(Color(0.20, 0.19, 0.22))
	ground.mesh = pm
	add_child(ground)

	# Platform: raised 30 x 1 x 6 slab + lighter edge stripe.
	_box(self, Vector3(30, 1, 6), Vector3(0, 0.5, -4), stone)
	_box(self, Vector3(30, 0.08, 0.35), Vector3(0, 1.02, -1.15), stone_light)

	# Tracks: two steel rails beside the platform + wooden sleepers.
	_box(self, Vector3(38, 0.14, 0.14), Vector3(0, 0.10, 2.2), steel)
	_box(self, Vector3(38, 0.14, 0.14), Vector3(0, 0.10, 3.8), steel)
	var sleepers := Node3D.new()
	sleepers.name = "Sleepers"
	add_child(sleepers)
	for x in range(-18, 19, 2):
		_box(sleepers, Vector3(0.5, 0.08, 3.4), Vector3(x, 0.05, 3.0), wood_dark)

	# Train: engine + 2 cars, static (Phase 5 adds ride feel).
	var train := Node3D.new()
	train.name = "Train"
	add_child(train)
	_box(train, Vector3(4.0, 2.2, 2.4), Vector3(-6, 1.45, 3.0), train_green)   # engine body
	_box(train, Vector3(1.6, 1.1, 2.0), Vector3(-7.0, 3.05, 3.0), train_green)  # cabin
	_cyl(train, 0.28, 0.34, 1.0, Vector3(-4.7, 3.0, 3.0), dark)                  # chimney
	_box(train, Vector3(0.9, 0.7, 0.1), Vector3(-6, 1.9, 1.78), win_glow)       # lit windows
	_box(train, Vector3(0.9, 0.7, 0.1), Vector3(-6, 1.9, 4.22), win_glow)
	_box(train, Vector3(0.5, 0.5, 0.1), Vector3(-7.0, 3.1, 1.98), win_glow)
	for wx in [-7.4, -6.6, -5.4, -4.6]:
		var wheel := _cyl(train, 0.42, 0.42, 0.18, Vector3(wx, 0.42, 3.0), dark)
		wheel.rotation_degrees.x = 90.0
	_box(train, Vector3(3.4, 2.2, 2.4), Vector3(-11, 1.45, 3.0), wood)          # car 1
	_box(train, Vector3(3.4, 2.2, 2.4), Vector3(-15, 1.45, 3.0), wood)           # car 2
	for cx in [-11.9, -11.0, -10.1, -15.9, -15.0, -14.1]:
		_box(train, Vector3(0.7, 0.6, 0.1), Vector3(cx, 1.8, 1.78), win_glow)
		_box(train, Vector3(0.7, 0.6, 0.1), Vector3(cx, 1.8, 4.22), win_glow)
	_box(train, Vector3(0.6, 0.25, 0.25), Vector3(-3.9, 1.1, 3.0), lamp_glow)    # headlamp

	# Boarding zone: Area3D in front of the train doors + gold pulse ring.
	var zone := Area3D.new()
	zone.name = "BoardingZone"
	zone.position = Vector3(-6, 1.5, 0.5)
	var zcs := CollisionShape3D.new()
	var zshape := BoxShape3D.new()
	zshape.size = Vector3(6, 3, 4)
	zcs.shape = zshape
	zone.add_child(zcs)
	add_child(zone)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.6
	torus.outer_radius = 2.9
	torus.material = ring_gold
	_ring.mesh = torus
	_ring.position = Vector3(-6, 0.08, 0.5)
	add_child(_ring)
	var board_label := Label3D.new()
	board_label.text = "BOARD HERE"
	board_label.font_size = 96
	board_label.modulate = Color(1.0, 0.85, 0.40)
	board_label.outline_size = 12
	board_label.position = Vector3(-6, 3.4, 0.5)
	board_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(board_label)

	# Heal pad (visual only in Phase 1): glowing green disc + REST sign.
	_cyl(self, 2.0, 2.0, 0.10, Vector3(10, 1.06, -4), heal_glow)
	var rest_label := Label3D.new()
	rest_label.text = "REST"
	rest_label.font_size = 72
	rest_label.modulate = Color(0.45, 1.0, 0.55)
	rest_label.outline_size = 10
	rest_label.position = Vector3(10, 2.6, -4)
	rest_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(rest_label)

	# Vendor stall (visual only in Phase 1): table + posts + awning.
	var stall := Node3D.new()
	stall.name = "VendorStall"
	stall.position = Vector3(4, 1.0, -5.5)
	add_child(stall)
	_box(stall, Vector3(3.0, 0.15, 1.4), Vector3(0, 0.85, 0), wood)
	for px in [-1.35, 1.35]:
		for pz in [-0.6, 0.6]:
			_box(stall, Vector3(0.12, 2.4, 0.12), Vector3(px, 1.2, pz), wood_dark)
	_box(stall, Vector3(3.4, 0.12, 1.8), Vector3(0, 2.5, 0), _mat(Color(0.65, 0.25, 0.20)))

	# Departure board (Phase 2): dark board, gold frame, DEPARTURES sign.
	# E-interact opens the destination vote UI.
	var board := DepartureBoardScript.new()
	board.name = "DepartureBoard"
	board.position = Vector3(-12, 0, -4)
	add_child(board)

	# Warm platform lamps.
	for lx in [-10.0, 0.0, 10.0]:
		_box(self, Vector3(0.16, 4.2, 0.16), Vector3(lx, 2.1, -6.4), dark)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		sm.material = lamp_glow
		bulb.mesh = sm
		bulb.position = Vector3(lx, 4.3, -6.4)
		add_child(bulb)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.80, 0.50)
		lamp.light_energy = 1.6
		lamp.omni_range = 12.0
		lamp.position = Vector3(lx, 4.0, -6.2)
		add_child(lamp)

	var players := Node3D.new()
	players.name = "Players"
	add_child(players)
