class_name Station
extends Node3D
## Station annex content (issue #2): the train station lives inside the
## dungeon's annex hall as a child node. The dungeon owns players + HUD;
## the station contributes the train, departures board, vendor, heal pad,
## and the vote flow, and emits departure_resolved for the dungeon's ride.
##
## Run handoff (set before add_child, i.e. before _ready):
##   Station.next_level_number (this class; drives board rec. levels) /
##   station.dungeon / station.annex (instance vars)

const DepartureBoardScript := preload("res://scripts/station/departure_board.gd")
const VendorStallScript := preload("res://scripts/station/vendor_stall.gd")
const BountyBoardScript := preload("res://scripts/station/bounty_board.gd")
const RelicVaultScript := preload("res://scripts/station/relic_vault.gd")

const DEPART_TIME := 45.0
const HEAL_TICK := 0.5
const HEAL_RADIUS := 2.2
## Boarding window after a unanimous vote (issue #3 Phase 2).
const BOARD_TIME := 45.0

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
	"apex": "★★★★★",
}

## Per-theme station dressing: platform lamp tint (Phase 5).
const DRESSING_LAMPS := {
	"village": Color(0.6, 1.0, 0.6),
	"dungeon": Color(0.5, 0.7, 1.0),
	"depths": Color(0.8, 0.4, 0.9),
	"supermarket": Color(1.0, 1.0, 0.95),
	"warlord": Color(1.0, 0.55, 0.25),
	"apex": Color(1.0, 0.25, 0.2),
}

## Owning dungeon: player roster + departure hop target.
var dungeon: Node = null
## The annex shell built by StationAnnex: provides floor, walls, roof, and
## the 4 lamp posts that apply_dressing tints.
var annex: StationAnnex = null
## Emitted (server) when the vote resolves. The dungeon drives the ride + hop.
signal departure_resolved(theme_id: String)

static var next_level_number: int = 1

## Seed for the upcoming level, rolled once by the server on station load so
## Save & Quit and the departure hop agree on it.
var departure_seed := 0

var _time_left := DEPART_TIME
## Embedded mode: the 45s vote timer starts on the first board interaction,
## not on ready (the hall is open from level start).
var _timer_running := true
var _departing := false
var _last_sync_sec := -1
## Issue #3 Phase 2 boarding: after a unanimous vote the station enters ALL
## ABOARD (45s boarding timer); walking through the train door marks a peer
## aboard; all living aboard (or timer expiry) completes boarding and the
## dungeon's ride begins.
var _boarding_active := false
var _boarding_locked := false
var _boarding_time_left := BOARD_TIME
var _boarding_theme := ""
## peer_id -> true for boarded players (server-authoritative).
var aboard := {}
var _boarding_zone: Area3D = null
var _board_label: Label3D = null
var _ring: MeshInstance3D
var _heal_pad: Area3D
var _heal_tick := 0.0
## Destination votes: peer_id -> theme_id (server-authoritative, Phase 2).
var votes := {}
## Phase 5 dressing: platform lamps, NOW BOARDING sign, per-theme prop sets.
var _lamps: Array = []
var _boarding_sign: Label3D
var _dressing: Node3D


func _ready() -> void:
	add_to_group("station")
	randomize()
	if multiplayer.is_server():
		departure_seed = randi()
		_roll_vendor_stock()
	# Annex hall content only: no own floor/environment, lamps, player
	# spawning, or HUD — the dungeon and the annex shell provide those.
	# (Issue #2 Phase 5: the standalone station scene is gone.)
	_timer_running = false
	_build_station_embedded()
	# Dress for the rotation default; re-dressed when a vote resolves.
	# board_destinations() swaps warlord for the APEX ARENA on apex cycles
	# (issue #5), so the default dressing stays consistent with the board.
	var dests := Dungeon.board_destinations(next_level_number)
	apply_dressing(dests[(next_level_number - 1) % dests.size()])


func _process(delta: float) -> void:
	# Gold boarding-ring pulse (all peers, pure ambience).
	if _ring != null:
		var s := 1.0 + sin(Time.get_ticks_msec() / 300.0) * 0.04
		_ring.scale = Vector3(s, 1, s)
	# Issue #29: poll fallback for the BOARD HERE zone. The Area3D
	# body_entered signal can miss (physics flake); if the local player is
	# standing in the zone during ALL ABOARD, report them boarded.
	_poll_boarding_zone()
	if not multiplayer.is_server():
		return
	if _boarding_active:
		_tick_boarding(delta)
	elif not _departing and _timer_running:
		_time_left -= delta
		var sec := int(ceil(maxf(_time_left, 0.0)))
		if sec != _last_sync_sec:
			_last_sync_sec = sec
			rpc("station_timer_sync", maxf(_time_left, 0.0))
		if _time_left <= 0.0:
			if _unanimous_theme() != "":
				depart()
			else:
				# No unanimity: the train waits. Reset the clock, keep the
				# votes (players may change them), and try again.
				_time_left = DEPART_TIME
				_last_sync_sec = -1
				rpc("station_timer_sync", DEPART_TIME)
				rpc("vote_reset_notice")
	_heal_tick -= delta
	if _heal_tick <= 0.0:
		_heal_tick = HEAL_TICK
		_process_heal_pad()


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


## Unanimous destination, or "" when the living players don't all agree on
## one. living_override lets tests drive the flow without a scene tree of
## players.
func _unanimous_theme(living_override: Array = []) -> String:
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	return resolve_destination(votes, living)


## Destination resolution (static for testability). Departure requires EVERY
## living player to vote for the SAME destination; anything else returns ""
## (no departure — the timer resets and voting continues).
static func resolve_destination(p_votes: Dictionary, living: Array) -> String:
	if living.is_empty():
		return ""
	var theme := ""
	for pid in living:
		if not p_votes.has(pid):
			return ""
		var t := str(p_votes[pid])
		if theme == "":
			theme = t
		elif t != theme:
			return ""
	return theme


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


## Record a vote from a peer. Pure logic (no RPC): the cast_vote RPC wrapper
## handles networking + the all-voted early departure. living_override lets
## tests drive the flow without a scene tree. Returns {"ok": bool, ...}.
func record_vote(peer_id: int, theme_id: String, living_override: Array = []) -> Dictionary:
	# Votes must name a destination the board actually offers: on apex cycles
	# (issue #5) warlord is swapped for the APEX ARENA.
	if not theme_id in Dungeon.board_destinations(next_level_number):
		return {"ok": false, "reason": "bad_theme"}
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	if not peer_id in living:
		return {"ok": false, "reason": "not_living"}
	votes[peer_id] = theme_id
	if not _timer_running:
		# First board interaction starts the 45s departure countdown.
		_timer_running = true
		_time_left = DEPART_TIME
		_last_sync_sec = -1
	return {"ok": true}


## Vote for a destination. Server records; every peer syncs for board UI.
@rpc("any_peer", "call_local")
func cast_vote(theme_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var res: Dictionary = record_vote(sender, theme_id)
	if not bool(res.get("ok", false)):
		return
	rpc("sync_votes", votes)
	if not _departing and _unanimous_theme() != "":
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
	# Issue #29: refresh the 2D popup tallies if it's open.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("refresh_destination_popup"):
		hud.refresh_destination_popup(votes, str(votes.get(multiplayer.get_unique_id(), "")))


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


## Timer expired without unanimity: tell every peer the clock restarted and
## the vote stays open.
@rpc("any_peer", "call_local")
func vote_reset_notice() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast("No agreement — vote again.")


## Server-authoritative departure (issue #3 Phase 2): resolve the
## destination, re-dress, then enter ALL ABOARD — the 45s boarding window.
## The dungeon's ride only begins when boarding completes (all living players
## aboard, or timer expiry), via _finish_boarding -> departure_resolved.
## living_override lets tests drive the flow without a scene tree of players.
func depart(living_override: Array = []) -> void:
	if _departing or not multiplayer.is_server():
		return
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	var theme_id := resolve_destination(votes, living)
	if theme_id == "":
		return # No unanimity — the train doesn't leave.
	_departing = true
	apply_dressing(theme_id)
	_start_boarding(theme_id, living)


## ALL ABOARD: banner + 45s server-authoritative boarding timer + aboard
## roster on every peer's HUD. Walk through the train door to board.
func _start_boarding(theme_id: String, living: Array) -> void:
	_boarding_active = true
	_boarding_locked = false
	_boarding_theme = theme_id
	_boarding_time_left = BOARD_TIME
	_last_sync_sec = -1
	aboard.clear()
	rpc("announce_boarding")
	rpc("boarding_sync", BOARD_TIME, aboard, living)


## Boarding timer tick (server). Expiry pulls the stragglers aboard.
func _tick_boarding(delta: float) -> void:
	_boarding_time_left -= delta
	var sec := int(ceil(maxf(_boarding_time_left, 0.0)))
	if sec != _last_sync_sec:
		_last_sync_sec = sec
		rpc("boarding_sync", maxf(_boarding_time_left, 0.0), aboard, _living_peer_ids())
	if _boarding_time_left <= 0.0:
		_finish_boarding()


## Record a boarding from a peer. Pure logic (no RPC): the request_board RPC
## wrapper handles networking + the all-aboard early departure.
## living_override lets tests drive the flow without a scene tree.
## Returns {"ok": bool, ...}.
func record_boarding(peer_id: int, living_override: Array = []) -> Dictionary:
	if not _boarding_active or _boarding_locked:
		return {"ok": false, "reason": "not_boarding"}
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	if not peer_id in living:
		return {"ok": false, "reason": "not_living"}
	aboard[peer_id] = true
	return {"ok": true}


## True when every living player has boarded. living_override lets tests
## drive the flow without a scene tree of players.
func _all_aboard(living_override: Array = []) -> bool:
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	if living.is_empty():
		return false
	for pid in living:
		if not aboard.has(pid):
			return false
	return true


## Board through the annex train door. Server records; every peer syncs the
## roster for the HUD; all living aboard ends the timer early.
@rpc("any_peer", "call_local")
func request_board() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var res: Dictionary = record_boarding(sender)
	if not bool(res.get("ok", false)):
		return
	AudioManager.sfx("board_chime")
	var living := _living_peer_ids()
	rpc("boarding_sync", maxf(_boarding_time_left, 0.0), aboard, living)
	if _all_aboard(living):
		_finish_boarding(living)


## Boarding complete (all aboard, or timer expiry): stragglers are pulled
## aboard by the dungeon's ride, doors close + lock, and the departure
## resolves. living_override lets tests drive the flow without a scene tree.
func _finish_boarding(living_override: Array = []) -> void:
	if not _boarding_active or not multiplayer.is_server():
		return
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	for pid in living:
		aboard[pid] = true # stragglers ride too — the pull-aboard moves them
	_boarding_active = false
	_boarding_locked = true
	AudioManager.sfx("door_lock")
	rpc("boarding_sync", 0.0, aboard, living)
	rpc("boarding_locked")
	departure_resolved.emit(_boarding_theme)


## ALL ABOARD banner on every peer.
@rpc("any_peer", "call_local")
func announce_boarding() -> void:
	AudioManager.sfx("all_aboard")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("announce"):
		hud.announce("ALL ABOARD!")


## Keep every peer's boarding HUD in sync: countdown + aboard roster.
@rpc("any_peer", "call_local")
func boarding_sync(time_left: float, aboard_now: Dictionary, living: Array) -> void:
	aboard = aboard_now.duplicate()
	# Final-seconds tick on every peer (driven by the server's per-second sync).
	if time_left <= 5.0 and time_left > 0.0:
		AudioManager.sfx("countdown_tick")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_boarding_timer"):
		hud.show_boarding_timer(time_left, aboard.size(), living.size())


## Boarding over: lock the train door (no more walk-through boarding) and
## hide the countdown. The ride starts on the dungeon side.
@rpc("any_peer", "call_local")
func boarding_locked() -> void:
	_boarding_locked = true
	if _board_label != null:
		_board_label.text = "DOORS LOCKED"
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("hide_station_timer"):
		hud.hide_station_timer()


## Train-door walk-through: each peer reports its own player only.
func _on_boarding_zone_body_entered(body: Node3D) -> void:
	if _boarding_locked or not _boarding_active:
		return
	if not body.is_in_group("players"):
		return
	if int(body.get_multiplayer_authority()) != multiplayer.get_unique_id():
		return
	rpc("request_board")


## Issue #29: poll fallback for the BOARD HERE zone. Runs on every peer;
## if the local player is inside the zone box during ALL ABOARD, report
## them boarded (idempotent — record_boarding just sets aboard[peer]=true).
func _poll_boarding_zone() -> void:
	if _boarding_locked or not _boarding_active:
		return
	if _boarding_zone == null:
		return
	var my_id := multiplayer.get_unique_id()
	# Already boarded? Skip the scan.
	if aboard.get(my_id, false):
		return
	var center := _boarding_zone.global_position
	var half := Vector3(2.5, 1.25, 1.5) # matches the 5x2.5x3 BoxShape3D
	for p in get_tree().get_nodes_in_group("players"):
		var body := p as Node3D
		if body == null:
			continue
		if int(body.get_multiplayer_authority()) != my_id:
			continue
		var d: Vector3 = body.global_position - center
		if absf(d.x) <= half.x and absf(d.y) <= half.y and absf(d.z) <= half.z:
			rpc("request_board")
			return


## Departure ride for the annex (issue #2 Phase 3): re-dress for the
## resolved theme, whistle, pull stragglers aboard, chug + rumble, fade to
## black. Called on all peers via the dungeon's begin_annex_departure rpc.
func play_departure_ride(theme_id: String, spots: Dictionary) -> void:
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
		# Fallback is station-relative (hall coordinates).
		var fallback: Vector3 = to_global(Vector3(0, 0.1, 2.0))
		var spot: Vector3 = spots.get(multiplayer.get_unique_id(), fallback)
		me.global_position = spot
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		if hud.has_method("toast"):
			hud.toast("All aboard!")
		if hud.has_method("hide_station_timer"):
			hud.hide_station_timer()


# --- Players (the dungeon owns spawning; the station only looks players up) ---


func get_player_node(peer_id: int) -> Node:
	# The dungeon owns players — delegate to it.
	if dungeon != null and dungeon.has_method("get_player_node"):
		return dungeon.get_player_node(peer_id)
	return null


func _my_player() -> Player:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != null and p.get_multiplayer_authority() == multiplayer.get_unique_id():
			return p
	return null


# --- Station construction (static shell; all procedural meshes) ---

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


## Annex-hall content layout (issue #2 Phase 2): train along the north side,
## departures board facing the corridor entrance (+z), vendor east, heal pad
## west. All coordinates are local to the station node, which the dungeon
## places at the hall center. No floor/environment/lamps/Players of its own
## — the annex shell and the dungeon provide those.
func _build_station_embedded() -> void:
	var dark := _mat(Color(0.16, 0.15, 0.17))
	var steel := _mat(Color(0.35, 0.36, 0.40))
	var wood := _mat(Color(0.45, 0.32, 0.20))
	var wood_dark := _mat(Color(0.32, 0.22, 0.14))
	var train_green := _mat(Color(0.10, 0.28, 0.16))
	var win_glow := _mat(Color(1.0, 0.75, 0.35), Color(1.0, 0.65, 0.25), 2.5)
	var lamp_glow := _mat(Color(1.0, 0.85, 0.55), Color(1.0, 0.75, 0.40), 3.0)
	var heal_glow := _mat(Color(0.25, 0.95, 0.45), Color(0.20, 0.90, 0.40), 2.0)
	var ring_gold := _mat(Color(1.0, 0.80, 0.30), Color(1.0, 0.70, 0.20), 1.8)

	# Tracks: two steel rails along the north strip + wooden sleepers.
	_box(self, Vector3(19, 0.14, 0.14), Vector3(-1.5, 0.10, -5.3), steel)
	_box(self, Vector3(19, 0.14, 0.14), Vector3(-1.5, 0.10, -3.7), steel)
	var sleepers := Node3D.new()
	sleepers.name = "Sleepers"
	add_child(sleepers)
	for x in range(-11, 9, 2):
		_box(sleepers, Vector3(0.5, 0.08, 3.4), Vector3(x, 0.05, -4.5), wood_dark)

	# Train: engine + 2 cars, static.
	var train := Node3D.new()
	train.name = "Train"
	add_child(train)
	_box(train, Vector3(4.0, 2.2, 2.4), Vector3(-1, 1.45, -4.5), train_green)   # engine body
	_box(train, Vector3(1.6, 1.1, 2.0), Vector3(-2.0, 3.05, -4.5), train_green)  # cabin
	_cyl(train, 0.28, 0.34, 1.0, Vector3(0.3, 3.0, -4.5), dark)                   # chimney
	_box(train, Vector3(0.9, 0.7, 0.1), Vector3(-1, 1.9, -5.72), win_glow)        # lit windows
	_box(train, Vector3(0.9, 0.7, 0.1), Vector3(-1, 1.9, -3.28), win_glow)
	_box(train, Vector3(0.5, 0.5, 0.1), Vector3(-2.0, 3.1, -5.68), win_glow)
	for wx in [-2.4, -1.6, -0.4, 0.4]:
		var wheel := _cyl(train, 0.42, 0.42, 0.18, Vector3(wx, 0.42, -4.5), dark)
		wheel.rotation_degrees.x = 90.0
	_box(train, Vector3(3.4, 2.2, 2.4), Vector3(-5.5, 1.45, -4.5), wood)           # car 1
	_box(train, Vector3(3.4, 2.2, 2.4), Vector3(-9.5, 1.45, -4.5), wood)           # car 2
	for cx in [-6.4, -5.5, -4.6, -10.4, -9.5, -8.6]:
		_box(train, Vector3(0.7, 0.6, 0.1), Vector3(cx, 1.8, -5.72), win_glow)
		_box(train, Vector3(0.7, 0.6, 0.1), Vector3(cx, 1.8, -3.28), win_glow)
	_box(train, Vector3(0.6, 0.25, 0.25), Vector3(1.1, 1.1, -4.5), lamp_glow)    # headlamp

	# Boarding zone: Area3D in front of the train doors + gold pulse ring.
	# Walking through the door during ALL ABOARD marks the player boarded
	# (issue #3 Phase 2).
	var zone := Area3D.new()
	zone.name = "BoardingZone"
	zone.position = Vector3(-1, 1.0, -2.0)
	var zcs := CollisionShape3D.new()
	var zshape := BoxShape3D.new()
	zshape.size = Vector3(5, 2.5, 3)
	zcs.shape = zshape
	zone.add_child(zcs)
	zone.body_entered.connect(_on_boarding_zone_body_entered)
	add_child(zone)
	_boarding_zone = zone
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 2.5
	torus.material = ring_gold
	_ring.mesh = torus
	_ring.position = Vector3(-1, 0.06, -2.0)
	add_child(_ring)
	var board_label := Label3D.new()
	board_label.text = "BOARD HERE"
	board_label.font_size = 96
	board_label.modulate = Color(1.0, 0.85, 0.40)
	board_label.outline_size = 12
	board_label.position = Vector3(-1, 2.8, -2.0)
	board_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(board_label)
	_board_label = board_label

	# Heal pad (Phase 4): glowing green disc + REST sign + heal trigger.
	_cyl(self, 2.0, 2.0, 0.10, Vector3(-9.5, 0.06, 3.5), heal_glow)
	var rest_label := Label3D.new()
	rest_label.text = "REST"
	rest_label.font_size = 72
	rest_label.modulate = Color(0.45, 1.0, 0.55)
	rest_label.outline_size = 10
	rest_label.position = Vector3(-9.5, 2.4, 3.5)
	rest_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(rest_label)
	var pad := Area3D.new()
	pad.name = "HealPad"
	pad.collision_layer = 0
	pad.collision_mask = 1 # players (default layer 1)
	pad.position = Vector3(-9.5, 1.0, 3.5)
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
	stall.position = Vector3(10, 0, -0.5)
	add_child(stall)

	# Relic Vault locker (issue #6 Phase 2): E-interact opens the vault panel.
	var vault := RelicVaultScript.new()
	vault.name = "RelicVault"
	vault.position = Vector3(-10, 0, -0.5)
	add_child(vault)

	# Departure board (Phase 2): faces the corridor entrance (+z).
	var board := DepartureBoardScript.new()
	board.name = "DepartureBoard"
	board.position = Vector3(7, 0, 4.2)
	add_child(board)

	# Bounty board (issue #7 Phase 2): E-interact opens the bounty panel.
	var bounty_board := BountyBoardScript.new()
	bounty_board.name = "BountyBoard"
	bounty_board.position = Vector3(3.2, 0, 4.2)
	add_child(bounty_board)

	# NOW BOARDING sign (Phase 5): big gold label above the train.
	_boarding_sign = Label3D.new()
	_boarding_sign.font_size = 84
	_boarding_sign.modulate = Color(1.0, 0.82, 0.35)
	_boarding_sign.outline_size = 12
	_boarding_sign.position = Vector3(-1, 3.9, -3.6)
	_boarding_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Issue #58: text was truncated ("NOW BOARDING: THE DU") — widen the label.
	_boarding_sign.width = 1200.0
	add_child(_boarding_sign)

	# Per-theme dressing props (Phase 5); only the active set is visible.
	_build_dressing()


## Dress the station for a destination theme: tint the lamps, show that
## theme's prop set, set the NOW BOARDING sign. Unknown ids fall back to
## village. Called on load (rotation default) and again when a vote resolves.
func apply_dressing(theme_id: String) -> void:
	# The apex arena (issue #5) is a board destination, not a THEME_ORDER
	# entry — allow it explicitly. Unknown ids fall back to village.
	var tid := theme_id if (theme_id in Dungeon.THEME_ORDER or theme_id == "apex") else "village"
	var tint: Color = DRESSING_LAMPS.get(tid, Color.WHITE)
	# The station lives in the annex hall: tint the annex shell's lamps.
	var lamp_list: Array = annex.lamps if annex != null else _lamps
	for lamp in lamp_list:
		(lamp as OmniLight3D).light_color = tint
	if _dressing != null:
		for child in _dressing.get_children():
			child.visible = (child.name == tid)
	if _boarding_sign != null:
		_boarding_sign.text = "NOW BOARDING: " + Station.theme_display_name(tid).to_upper()


## Prop set builder: one Node3D per theme under Dressing. All procedural,
## a few boxes each — no new textures. Hall coordinates (issue #2).
func _build_dressing() -> void:
	_dressing = Node3D.new()
	_dressing.name = "Dressing"
	add_child(_dressing)
	_dressing_props_embedded()


## Hall prop coordinates (issue #2): all props sit
## on the hall floor (y=0) along the south strip and corners, clear of the
## train (north strip), board, vendor, and heal pad.
func _dressing_props_embedded() -> void:
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

	# village: hay bales + a low-poly tree (SE corner / SW corner).
	var v := Node3D.new()
	v.name = "village"
	_dressing.add_child(v)
	_box(v, Vector3(0.9, 0.9, 0.9), Vector3(10.8, 0.45, 5.8), hay)
	_box(v, Vector3(0.9, 0.9, 0.9), Vector3(9.7, 0.45, 5.9), hay)
	_box(v, Vector3(0.9, 0.9, 0.9), Vector3(10.3, 1.32, 5.8), hay)
	_cyl(v, 0.18, 0.24, 1.6, Vector3(-11.0, 0.8, 5.8), trunk_m)
	_box(v, Vector3(1.6, 1.4, 1.6), Vector3(-11.0, 2.2, 5.8), leaf)

	# dungeon: torch posts flanking the south strip.
	var d := Node3D.new()
	d.name = "dungeon"
	_dressing.add_child(d)
	for tx in [11.0, -11.0]:
		_box(d, Vector3(0.14, 1.8, 0.14), Vector3(tx, 0.9, 5.8), trunk_m)
		_box(d, Vector3(0.30, 0.22, 0.30), Vector3(tx, 1.9, 5.8), torch_tip)

	# depths: crystal clusters on rock bases (both south corners).
	var de := Node3D.new()
	de.name = "depths"
	_dressing.add_child(de)
	for cx in [11.0, -11.0]:
		_box(de, Vector3(1.4, 0.5, 1.4), Vector3(cx, 0.25, 5.8), rock)
		var c1 := _box(de, Vector3(0.35, 1.1, 0.35), Vector3(cx - 0.2, 1.0, 5.8), crystal)
		c1.rotation.z = 0.18
		var c2 := _box(de, Vector3(0.30, 0.8, 0.30), Vector3(cx + 0.3, 0.85, 5.6), crystal)
		c2.rotation.z = -0.22

	# supermarket: product crates + a shopping cart.
	var s := Node3D.new()
	s.name = "supermarket"
	_dressing.add_child(s)
	_box(s, Vector3(1.0, 1.0, 1.0), Vector3(11.0, 0.5, 5.8), crate_r)
	_box(s, Vector3(1.0, 1.0, 1.0), Vector3(9.8, 0.5, 5.9), crate_b)
	_box(s, Vector3(1.0, 1.0, 1.0), Vector3(10.5, 1.5, 5.8), crate_y)
	_box(s, Vector3(1.2, 0.7, 0.8), Vector3(-10.5, 0.55, 5.5), cart_m)
	for wx in [-10.85, -10.15]:
		for wz in [5.25, 5.75]:
			var wheel := _cyl(s, 0.12, 0.12, 0.08, Vector3(wx, 0.12, wz), chain_m)
			wheel.rotation_degrees.x = 90.0
	var handle := _box(s, Vector3(0.08, 0.08, 0.9), Vector3(-9.85, 1.0, 5.5), chain_m)
	handle.rotation_degrees.z = -25.0

	# warlord: war banners + a weapon rack.
	var w := Node3D.new()
	w.name = "warlord"
	_dressing.add_child(w)
	for bx in [11.3, -11.3]:
		_box(w, Vector3(0.14, 2.8, 0.14), Vector3(bx, 1.4, 5.5), trunk_m)
		_box(w, Vector3(0.80, 1.5, 0.06), Vector3(bx, 1.9, 5.5), banner_m)
	_box(w, Vector3(0.14, 1.4, 0.14), Vector3(4.5, 0.7, -6.3), trunk_m)
	_box(w, Vector3(0.14, 1.4, 0.14), Vector3(5.5, 0.7, -6.3), trunk_m)
	_box(w, Vector3(1.3, 0.12, 0.12), Vector3(5.0, 1.3, -6.3), trunk_m)
	var ews1 := _box(w, Vector3(0.10, 1.2, 0.10), Vector3(5.0, 0.75, -6.25), steel_dark)
	ews1.rotation_degrees.z = 28.0
	var ews2 := _box(w, Vector3(0.10, 1.2, 0.10), Vector3(5.0, 0.75, -6.25), steel_dark)
	ews2.rotation_degrees.z = -28.0

	# apex: crimson war banners + braziers flanking the south strip.
	var a := Node3D.new()
	a.name = "apex"
	_dressing.add_child(a)
	var ember := _mat(Color(1.0, 0.35, 0.1), Color(1.0, 0.3, 0.08), 2.5)
	for bx in [11.3, -11.3]:
		_box(a, Vector3(0.14, 2.8, 0.14), Vector3(bx, 1.4, 5.5), steel_dark)
		_box(a, Vector3(0.80, 1.5, 0.06), Vector3(bx, 1.9, 5.5), banner_m)
		# Brazier: iron bowl on a stand with an ember glow.
		_cyl(a, 0.35, 0.25, 0.25, Vector3(bx * 0.85, 0.9, 5.6), steel_dark)
		_box(a, Vector3(0.12, 0.9, 0.12), Vector3(bx * 0.85, 0.45, 5.6), steel_dark)
		_box(a, Vector3(0.30, 0.18, 0.30), Vector3(bx * 0.85, 1.08, 5.6), ember)
