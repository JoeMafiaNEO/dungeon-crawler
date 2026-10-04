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
const VendorStallScript := preload("res://scripts/station/vendor_stall.gd")

const DEPART_TIME := 45.0
const SAVE_STATE_TIMEOUT := 3.0
const HEAL_TICK := 0.5
const HEAL_RADIUS := 2.2

## Vendor stock (server-authoritative, picked fresh every station visit).
const VENDOR_POTIONS := [
	{"id": "health_potion", "price": 50},
	{"id": "swift_potion", "price": 75},
	{"id": "power_elixir", "price": 100},
]
const VENDOR_POTION_IDS := ["health_potion", "swift_potion", "power_elixir"]
var vendor_stock: Array = [] # [{id, price}]

## Danger stars per theme (informational only — no locks). Moved here from
## the old floating HUD board panel; the physical 3D board reads it.
const BOARD_STARS := {
	"village": "★☆☆☆", "dungeon": "★★☆☆", "depths": "★★★☆",
	"supermarket": "★☆☆☆", "warlord": "★★★★",
}

## Per-theme station dressing: platform lamp tint (Phase 5).
const DRESSING_LAMPS := {
	"village": Color(0.6, 1.0, 0.6),
	"dungeon": Color(0.5, 0.7, 1.0),
	"depths": Color(0.8, 0.4, 0.9),
	"supermarket": Color(1.0, 1.0, 0.95),
	"warlord": Color(1.0, 0.55, 0.25),
}

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
var _departing := false
var _last_sync_sec := -1
var _ring: MeshInstance3D
var _heal_pad: Area3D
var _heal_tick := 0.0
## Destination votes: peer_id -> theme_id (server-authoritative, Phase 2).
var votes := {}
## Phase 5 dressing: platform lamps, NOW BOARDING sign, per-theme prop sets.
var _lamps: Array = []
var _boarding_sign: Label3D
var _dressing: Node3D
# --- Multiplayer run-save state (trimmed mirror of dungeon's; no RTS here) ---
var _save_roster: Array = []
var _save_pending: Dictionary = {}
var _save_base: Dictionary = {}


func _ready() -> void:
	add_to_group("station")
	randomize()
	if multiplayer.is_server():
		departure_seed = randi()
		_roll_vendor_stock()
	_build_station()
	# Dress for the rotation default; re-dressed when a vote resolves.
	apply_dressing(Dungeon.THEME_ORDER[(next_level_number - 1) % Dungeon.THEME_ORDER.size()])
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
	_heal_tick -= delta
	if _heal_tick <= 0.0:
		_heal_tick = HEAL_TICK
		_process_heal_pad()
	var sec := int(ceil(maxf(_time_left, 0.0)))
	if sec != _last_sync_sec:
		_last_sync_sec = sec
		rpc("station_timer_sync", maxf(_time_left, 0.0))
	if _time_left <= 0.0:
		depart()


## Heal pad: every tick, living players on the pad get 15% max HP.
## Server-authoritative; heal() itself does FX + clamps to max.
func _process_heal_pad() -> void:
	if _heal_pad == null:
		return
	for b in _heal_pad.get_overlapping_bodies():
		if not b.is_in_group("players"):
			continue
		if not bool(b.get("alive")):
			continue
		if float(b.get("hp")) >= float(b.get("max_hp")):
			continue
		b.rpc_id(b.get_multiplayer_authority(), "heal", heal_tick_amount(float(b.get("max_hp"))))


## Heal tick amount: 15% of max HP per 0.5s tick (~3.3s to full from empty).
static func heal_tick_amount(max_hp: float) -> float:
	return max_hp * 0.15


## Vendor buy price: 3x sell value, $50 floor (potions have fixed prices).
static func vendor_price(sell_value: int) -> int:
	return maxi(50, sell_value * 3)


## Pure purchase resolution (static for testability).
## Returns {ok, price, new_cash} or {ok:false, reason}.
static func resolve_purchase(cash: int, stock: Array, item_id: String) -> Dictionary:
	var price := -1
	for entry in stock:
		if str(entry.get("id")) == item_id:
			price = int(entry.get("price"))
			break
	if price < 0:
		return {"ok": false, "reason": "not_in_stock"}
	if cash < price:
		return {"ok": false, "reason": "broke", "price": price}
	return {"ok": true, "price": price, "new_cash": cash - price}


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


## Keep every peer's physical board in sync with the server's vote table.
@rpc("any_peer", "call_local")
func sync_votes(v: Dictionary) -> void:
	votes = v.duplicate()
	var board := get_tree().get_first_node_in_group("departure_board")
	if board != null:
		board.set_tallies(votes)
		if board.has_method("set_my_vote"):
			board.set_my_vote(str(votes.get(multiplayer.get_unique_id(), "")))


## Vendor stock (Phase 4): 3 fixed potions + 3 rotating items.
## Rotating picks exclude potions, supermarket_loot, and meta-locked items
## unless the local save has them unlocked. New stock every station visit.
func _roll_vendor_stock() -> void:
	vendor_stock = build_vendor_stock()
	rpc("sync_vendor_stock", vendor_stock)


## Pure stock builder (static for testability).
static func build_vendor_stock() -> Array:
	var stock: Array = VENDOR_POTIONS.duplicate(true)
	var pool: Array = []
	for id in ItemDB.items.keys():
		if id in VENDOR_POTION_IDS:
			continue
		var item: ItemData = ItemDB.items[id]
		if item == null:
			continue
		if bool(item.get("supermarket_loot")):
			continue
		if bool(item.get("meta_locked")) and not SaveManager.is_item_unlocked(id):
			continue
		pool.append(id)
	pool.shuffle()
	for i in mini(3, pool.size()):
		var item: ItemData = ItemDB.items[pool[i]]
		stock.append({"id": pool[i], "price": vendor_price(int(item.get("sell_value")))})
	return stock


## Sync vendor stock to every peer (also called for late joiners).
@rpc("any_peer", "call_local")
func sync_vendor_stock(stock: Array) -> void:
	vendor_stock = stock.duplicate(true)


## Buy a vendor item. Server validates stock + cash; mirrors buy_potion.
@rpc("any_peer", "call_local")
func buy_vendor_item(item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player := get_player_node(sender)
	if player == null or not bool(player.get("alive")):
		return
	var res := resolve_purchase(int(player.get("supermarket_cash")), vendor_stock, item_id)
	if not bool(res.get("ok")):
		if str(res.get("reason")) == "broke":
			player.rpc_id(sender, "on_buy_failed", int(res.get("price")))
		return
	player.set("supermarket_cash", int(res.get("new_cash")))
	player.rpc_id(sender, "receive_item", item_id)
	player.rpc_id(sender, "on_bought", item_id, int(res.get("price")))


@rpc("any_peer", "call_local")
func station_timer_sync(time_left: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_station_timer"):
		hud.show_station_timer(time_left)


## Server-authoritative departure: resolve the destination, ride out with
## whistle/chug/fade (Phase 5), then save and hop levels.
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
	rpc("begin_departure", theme_id, spots)
	# 3.5s ride: 1.2s fade + ~1s black, whistle into chug. No moving-train
	# gameplay (scope control).
	await get_tree().create_timer(3.5).timeout
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


## Departure ride (all peers): re-dress for the resolved theme, whistle,
## pull stragglers aboard, chug + rumble, fade to black.
@rpc("any_peer", "call_local")
func begin_departure(theme_id: String, spots: Dictionary) -> void:
	apply_dressing(theme_id)
	AudioManager.sfx("train_whistle")
	pull_aboard(spots) # moves players, toasts "All aboard!", hides the timer
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("fade_out"):
		hud.fade_out(1.2)
	await get_tree().create_timer(1.0).timeout
	AudioManager.sfx("train_chug")
	AudioManager.sfx("rumble")


@rpc("any_peer", "call_local")
func pull_aboard(spots: Dictionary) -> void:
	# Anyone mid-vote steps away from the board first.
	for n in get_tree().get_nodes_in_group("players"):
		if n.has_method("exit_reading"):
			n.exit_reading()
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
		rpc_id(sender, "sync_vendor_stock", vendor_stock)


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
		_local_hud.toast("Check the DEPARTURES board (E) to vote!")


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


## Invisible physics slab so players can actually stand in the station.
func _static_box(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.position = pos
	body.add_child(cs)
	add_child(body)


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
	# Physics: platform top (y=1.0) and ground level (y=0) slabs.
	_static_box(Vector3(30, 1, 6), Vector3(0, 0.5, -4))
	_static_box(Vector3(48, 1, 24), Vector3(0, -0.5, 0))

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

	# Heal pad (Phase 4): glowing green disc + REST sign + heal trigger.
	# The server ticks heal(max_hp * 0.15) for living players inside.
	_cyl(self, 2.0, 2.0, 0.10, Vector3(10, 1.06, -4), heal_glow)
	var rest_label := Label3D.new()
	rest_label.text = "REST"
	rest_label.font_size = 72
	rest_label.modulate = Color(0.45, 1.0, 0.55)
	rest_label.outline_size = 10
	rest_label.position = Vector3(10, 2.6, -4)
	rest_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(rest_label)
	var pad := Area3D.new()
	pad.name = "HealPad"
	pad.collision_layer = 0
	pad.collision_mask = 1 # players (default layer 1)
	pad.position = Vector3(10, 1.5, -4)
	var pcs := CollisionShape3D.new()
	var pcyl := CylinderShape3D.new()
	pcyl.radius = HEAL_RADIUS
	pcyl.height = 3.0
	pcs.shape = pcyl
	pad.add_child(pcs)
	add_child(pad)
	_heal_pad = pad

	# Vendor stall (Phase 4): E-interact opens the vendor panel.
	var stall := VendorStallScript.new()
	stall.name = "VendorStall"
	stall.position = Vector3(4, 1.0, -5.5)
	add_child(stall)

	# Departure board (Phase 2): dark board, gold frame, DEPARTURES sign.
	# E-interact opens the destination vote UI.
	var board := DepartureBoardScript.new()
	board.name = "DepartureBoard"
	board.position = Vector3(-12, 1.0, -4) # on the platform (top y=1.0)
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
		_lamps.append(lamp)

	# NOW BOARDING sign (Phase 5): big gold label near the train doors.
	_boarding_sign = Label3D.new()
	_boarding_sign.font_size = 84
	_boarding_sign.modulate = Color(1.0, 0.82, 0.35)
	_boarding_sign.outline_size = 12
	_boarding_sign.position = Vector3(-9, 4.6, -0.6)
	_boarding_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_boarding_sign)

	# Per-theme dressing props (Phase 5); only the active set is visible.
	_build_dressing()

	var players := Node3D.new()
	players.name = "Players"
	add_child(players)


## Dress the station for a destination theme: tint the lamps, show that
## theme's prop set, set the NOW BOARDING sign. Unknown ids fall back to
## village. Called on load (rotation default) and again when a vote resolves.
func apply_dressing(theme_id: String) -> void:
	var tid := theme_id if theme_id in Dungeon.THEME_ORDER else "village"
	var tint: Color = DRESSING_LAMPS.get(tid, Color.WHITE)
	for lamp in _lamps:
		(lamp as OmniLight3D).light_color = tint
	if _dressing != null:
		for child in _dressing.get_children():
			child.visible = (child.name == tid)
	if _boarding_sign != null:
		_boarding_sign.text = "NOW BOARDING: " + Station.theme_display_name(tid).to_upper()


## Prop set builder: one Node3D per theme under Dressing. All procedural,
## a few boxes each — no new textures.
func _build_dressing() -> void:
	_dressing = Node3D.new()
	_dressing.name = "Dressing"
	add_child(_dressing)
	var hay := _mat(Color(0.85, 0.70, 0.40))
	var leaf := _mat(Color(0.30, 0.55, 0.28))
	var trunk_m := _mat(Color(0.40, 0.28, 0.16))
	var torch_tip := _mat(Color(1.0, 0.55, 0.15), Color(1.0, 0.45, 0.10), 3.0)
	var chain_m := _mat(Color(0.18, 0.18, 0.20))
	var rock := _mat(Color(0.30, 0.28, 0.34))
	var crystal := _mat(Color(0.55, 0.30, 0.85), Color(0.45, 0.20, 0.80), 2.5)
	var crate_r := _mat(Color(0.75, 0.25, 0.20))
	var crate_b := _mat(Color(0.20, 0.40, 0.75))
	var crate_y := _mat(Color(0.85, 0.75, 0.25))
	var cart_m := _mat(Color(0.55, 0.58, 0.62))
	var banner_m := _mat(Color(0.70, 0.12, 0.12))
	var steel_dark := _mat(Color(0.25, 0.25, 0.28))

	# village: hay bales + a low-poly tree.
	var v := Node3D.new()
	v.name = "village"
	_dressing.add_child(v)
	_box(v, Vector3(0.9, 0.9, 0.9), Vector3(-13.5, 1.45, -6.0), hay)
	_box(v, Vector3(0.9, 0.9, 0.9), Vector3(-12.4, 1.45, -6.1), hay)
	_box(v, Vector3(0.9, 0.9, 0.9), Vector3(-13.0, 2.32, -6.0), hay)
	_cyl(v, 0.18, 0.24, 1.6, Vector3(13.0, 1.8, -6.0), trunk_m)
	_box(v, Vector3(1.6, 1.4, 1.6), Vector3(13.0, 3.2, -6.0), leaf)

	# dungeon: torch posts + a beam with hanging chains.
	var d := Node3D.new()
	d.name = "dungeon"
	_dressing.add_child(d)
	for tx in [-13.5, 7.5]:
		_box(d, Vector3(0.14, 1.8, 0.14), Vector3(tx, 1.9, -6.2), trunk_m)
		_box(d, Vector3(0.30, 0.22, 0.30), Vector3(tx, 2.9, -6.2), torch_tip)
	_box(d, Vector3(3.0, 0.18, 0.18), Vector3(-4.5, 3.4, -6.3), trunk_m)
	for i in range(3):
		_box(d, Vector3(0.06, 1.1, 0.06), Vector3(-5.5 + float(i), 2.75, -6.3), chain_m)

	# depths: crystal clusters on rock bases.
	var de := Node3D.new()
	de.name = "depths"
	_dressing.add_child(de)
	_box(de, Vector3(1.4, 0.5, 1.4), Vector3(-13.5, 1.25, -6.0), rock)
	var cry1 := _box(de, Vector3(0.35, 1.1, 0.35), Vector3(-13.7, 2.0, -6.0), crystal)
	cry1.rotation.z = 0.18
	var cry2 := _box(de, Vector3(0.30, 0.8, 0.30), Vector3(-13.2, 1.85, -6.2), crystal)
	cry2.rotation.z = -0.22
	var cry3 := _box(de, Vector3(0.28, 0.9, 0.28), Vector3(-13.5, 1.9, -5.7), crystal)
	cry3.rotation.x = 0.15
	_box(de, Vector3(1.0, 0.4, 1.0), Vector3(13.0, 1.2, -6.0), rock)
	var cry4 := _box(de, Vector3(0.30, 0.9, 0.30), Vector3(13.0, 1.8, -6.0), crystal)
	cry4.rotation.z = 0.12

	# supermarket: product crates + a shopping cart.
	var s := Node3D.new()
	s.name = "supermarket"
	_dressing.add_child(s)
	_box(s, Vector3(1.0, 1.0, 1.0), Vector3(-13.5, 1.5, -6.0), crate_r)
	_box(s, Vector3(1.0, 1.0, 1.0), Vector3(-12.3, 1.5, -6.1), crate_b)
	_box(s, Vector3(1.0, 1.0, 1.0), Vector3(-13.0, 2.5, -6.0), crate_y)
	_box(s, Vector3(1.2, 0.7, 0.8), Vector3(7.5, 1.55, -6.2), cart_m)
	for wx in [7.15, 7.85]:
		for wz in [-6.45, -5.95]:
			var wheel := _cyl(s, 0.12, 0.12, 0.08, Vector3(wx, 1.12, wz), chain_m)
			wheel.rotation_degrees.x = 90.0
	var handle := _box(s, Vector3(0.08, 0.08, 0.9), Vector3(8.15, 2.0, -6.2), chain_m)
	handle.rotation_degrees.z = -25.0

	# warlord: war banners + a weapon rack.
	var w := Node3D.new()
	w.name = "warlord"
	_dressing.add_child(w)
	for bx in [-13.5, 13.0]:
		_box(w, Vector3(0.14, 2.8, 0.14), Vector3(bx, 2.4, -6.2), trunk_m)
		_box(w, Vector3(0.80, 1.5, 0.06), Vector3(bx, 2.9, -6.2), banner_m)
	_box(w, Vector3(0.14, 1.4, 0.14), Vector3(-5.0, 1.7, -6.3), trunk_m)
	_box(w, Vector3(0.14, 1.4, 0.14), Vector3(-4.0, 1.7, -6.3), trunk_m)
	_box(w, Vector3(1.3, 0.12, 0.12), Vector3(-4.5, 2.3, -6.3), trunk_m)
	var sw1 := _box(w, Vector3(0.10, 1.2, 0.10), Vector3(-4.5, 1.75, -6.25), steel_dark)
	sw1.rotation_degrees.z = 28.0
	var sw2 := _box(w, Vector3(0.10, 1.2, 0.10), Vector3(-4.5, 1.75, -6.25), steel_dark)
	sw2.rotation_degrees.z = -28.0
