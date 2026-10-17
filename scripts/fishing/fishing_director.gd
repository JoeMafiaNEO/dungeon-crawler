extends Node
## Issue #126 Phase 2: per-peer fishing sessions, owned by the dungeon.
##
## Replaces FishingSpot (deleted): there are no spots, claims, or locks
## anymore. A player in rod-out mode casts anywhere; the server (this
## node's server instance) validates the landing — water only: inside
## a layout pond disc or on heightmap terrain below its water level —
## and opens a session keyed by the caster's peer id. Unlimited
## concurrent fishers per pond.
##
## The session core is the spot's proven one, carried with ALL numbers
## unchanged: 3–8s server wait roll, bite broadcast, 1.2s hook window
## (LMB or E), wait-weighted catch roll, bait auto-consumed on the
## validated cast, legendary slice (1%→5% by wait) granting
## fish_starleaper + the "legendary_fish" dock trophy. Movement no
## longer locks: WASD input while the bobber is out cancels (the
## client reports it; a 3.0m drift from the cast stance cancels
## server-side as a backstop, the spot's LEAVE_RADIUS carried).
##
## Trust model (as the spot's): RPCs take no peer id — the server
## attributes every call via multiplayer.get_remote_sender_id()
## (P2P peer ids; server = 1, never the 64-bit Steam id). Catch state
## never leaves the server session; peers get visual broadcasts only.
##
## Presentation: every peer's instance keeps one FishingVisual per
## fishing peer, driven by the fx_* broadcasts. The fisher's own cast
## is predicted locally with the same validation (see predict_cast);
## the server broadcast reconciles it.

enum SessionState { NONE, WAITING, BITING, IDLE }

const WAIT_MIN := 3.0 ## seconds, server-rolled wait before a bite
const WAIT_MAX := 8.0
const REEL_WINDOW_MSEC := 1200 ## 1.2s hook window after the bite cue
const LEAVE_RADIUS := 3.0 ## meters from the cast stance: drifting cancels

const FISH_LEGENDARY := "fish_starleaper"
const DOCK_TROPHY_LEGENDARY_FISH := "legendary_fish"
const CATCH_LEGENDARY_BASE := 0.01 ## Legendary chance at minimum wait.
const CATCH_LEGENDARY_T := 0.04 ## Scales to 5% at maximum wait.

## Cast geometry (carried from the FishingController prototype):
## charge 0→1 maps to 4–15m; the server caps accepted landings at
## MAX_CAST_DIST + CAST_MARGIN from the caster.
const MIN_CAST_DIST := 4.0
const MAX_CAST_DIST := 15.0
const CAST_MARGIN := 2.0
const CHARGE_TIME := 1.5

## TEST SEAMS (never set in production; carried from FishingSpot):
## debug_wait_override >= 0 forces the wait roll; debug_now_msec >= 0
## replaces Time.get_ticks_msec(); debug_catch_roll >= 0 forces the
## catch rarity roll; debug_force_water: -1 real validation, 0 always
## dry, 1 always water. test_players overrides _player_for_peer().
static var debug_wait_override: float = -1.0
static var debug_now_msec: int = -1
static var debug_catch_roll: float = -1.0
static var debug_force_water: int = -1
var test_players: Dictionary = {}

## peer -> {state, bite_at, deadline, wait, baited, bobber, cast_from}
var _sessions: Dictionary = {}

## Issue #142: catches awaiting their grant outcome, by peer. The
## session itself ends at the catch either way; what the outcome
## decides is only where the fish lands (report_claim).
var _catch_pending: Dictionary = {}
## peer -> FishingVisual (presentation only, every peer's instance)
var _visuals: Dictionary = {}
## Peers whose local cast prediction is awaiting the server broadcast.
var _predicted: Dictionary = {}


func _ready() -> void:
	add_to_group("fishing_director")


# --- Shared water validation (client prediction + server authority) ---

## True when p lands in water: inside a layout pond disc, or on
## heightmap terrain below its water level. Identical on every peer —
## the layout and terrain are deterministic across the session.
func is_water_at(p: Vector3) -> bool:
	if debug_force_water >= 0:
		return debug_force_water == 1
	var d := _dungeon()
	if d == null:
		return false
	var layout = d.get("_layout")
	if layout != null:
		for pd in layout.ponds:
			var c: Vector3 = pd["center"]
			var flat := Vector2(p.x - c.x, p.z - c.z)
			if flat.length() <= float(pd["radius"]):
				return true
	var terrain = d.get("_terrain")
	if terrain != null and d.ground_height_at(p) < float(terrain.get("water_level")):
		return true
	return false


## The water surface height at p (for bobber placement).
func water_y_at(p: Vector3) -> float:
	var d := _dungeon()
	if d != null:
		var terrain = d.get("_terrain")
		if terrain != null:
			return float(terrain.get("water_level"))
		var layout = d.get("_layout")
		if layout != null and not layout.ponds.is_empty():
			return float((layout.ponds[0] as Dictionary)["center"].y)
	return p.y


# --- Client -> server requests ---

@rpc("any_peer", "call_local")
func request_cast(landing: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_handle_cast(_sender_peer(), landing)


@rpc("any_peer", "call_local")
func request_hook() -> void:
	if not multiplayer.is_server():
		return
	_handle_hook(_sender_peer())


## Reel the bobber in (RMB): ends the session free, no catch.
@rpc("any_peer", "call_local")
func request_reel_in() -> void:
	if not multiplayer.is_server():
		return
	_end_peer_session(_sender_peer(), "")
	rpc("fx_reel_in", _sender_peer())


## Cancel (WASD input in rod-out / leaving rod-out): same free end,
## with the interruption toast for the fisher.
@rpc("any_peer", "call_local")
func request_cancel() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender_peer()
	if _sessions.has(peer):
		_end_peer_session(peer, "")
		rpc("fx_clear", peer, "Fishing interrupted.")


## Server-side forced end (peer disconnect). Never called by clients.
func force_end_peer(peer: int) -> void:
	if not multiplayer.is_server():
		return
	if _sessions.has(peer):
		_end_peer_session(peer, "")
		rpc("fx_clear", peer, "")


# --- Server session core ---

func _handle_cast(peer: int, landing: Vector3) -> void:
	var player := _player_for_peer(peer)
	if player == null:
		return
	# The one surviving rod gate: the server validates the claim
	# against the caster replica's synced equipped_ids (Phase 1's
	# design — rod-out requires the rod EQUIPPED in TOOL).
	if str(player.equipped_ids.get("TOOL", "")) != "fishing_rod":
		return
	if _sessions.has(peer):
		return # one bobber at a time; reel in first
	var from := player.global_position + Vector3(0, 1.4, 0) \
		+ (-player.global_transform.basis.z) * 0.4
	if landing.distance_to(player.global_position) > MAX_CAST_DIST + CAST_MARGIN:
		rpc("fx_cast", peer, from, landing, false)
		return
	if not is_water_at(landing):
		# Dirt: the bobber flops, no session, free instant recast.
		var dirt := Vector3(landing.x, _ground_y(landing) + 0.05, landing.z)
		rpc("fx_cast", peer, from, dirt, false)
		return
	var bobber := Vector3(landing.x, water_y_at(landing), landing.z)
	# Bait auto-consumes on the validated cast (the spot's rule).
	var baited := false
	if DockEconomy.spend_stock(peer, DockEconomy.BAIT_ITEM):
		baited = true
		# Issue #160: the merchant's self-guard (see farm_plot).
		if peer == int(multiplayer.get_unique_id()):
			player.consume_dock_good(DockEconomy.BAIT_ITEM)
		else:
			player.rpc_id(peer, "consume_dock_good", DockEconomy.BAIT_ITEM)
	var wait := _roll_wait()
	_sessions[peer] = {
		"state": SessionState.WAITING,
		"bite_at": _now_msec() + int(wait * 1000.0),
		"deadline": 0,
		"wait": wait,
		"baited": baited,
		"bobber": bobber,
		"cast_from": player.global_position,
	}
	rpc("fx_cast", peer, from, bobber, true)


func _handle_hook(peer: int) -> void:
	var s: Dictionary = _sessions.get(peer, {})
	if s.is_empty():
		return
	if int(s["state"]) != SessionState.BITING:
		return # early presses are ignored, as at the spots
	if _now_msec() > int(s["deadline"]):
		return
	_resolve_catch(peer, s)


func _resolve_catch(peer: int, s: Dictionary) -> void:
	var item_id := roll_catch_item(float(s["wait"]), bool(s["baited"]))
	_sessions.erase(peer)
	# Issue #142: the grant reports its outcome back (receive_item's
	# report leg) and report_claim decides where the fish lands —
	# the fisher's inventory on success, a world drop at their feet
	# when it can't take the fish. The fish never just vanishes.
	_catch_pending[peer] = {"item_id": item_id,
		"since": Time.get_ticks_msec() / 1000.0}
	var player := _player_for_peer(peer)
	if player != null:
		if peer == int(multiplayer.get_unique_id()):
			player.receive_item(item_id, -1, str(get_path()), 1, peer)
		else:
			player.rpc_id(peer, "receive_item", item_id, -1, str(get_path()), 1, peer)
	rpc("fx_catch", peer, item_id)


## Issue #142: the catch grant's outcome (called by the fisher's
## own receive_item via the report leg).
@rpc("any_peer", "call_local")
func report_claim(taken: int, tag: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var rec: Dictionary = _catch_pending.get(sender, {})
	if rec.is_empty():
		return
	_catch_pending.erase(sender)
	_land_catch(sender, str(rec.get("item_id", "")), taken >= 1)


## Issue #142: record the catch in the stock ledger and land it.
## A grant that failed (or never answered — the _process timeout)
## becomes a world pickup at the fisher's feet instead of vanishing.
func _land_catch(peer: int, item_id: String, in_inventory: bool) -> void:
	# The catch is a server grant — record it in the DockEconomy stock
	# ledger or the vendor's sell validation rejects the fish.
	# Issue #160 (verification leg): only when the fish lands in the
	# bag. A world fish takes its credit at its CLAIM instead (the
	# pickup hook) — crediting here too paid the catcher a sellable
	# balance for a fish anyone could pick up, and the claim would
	# have doubled it.
	if in_inventory:
		DockEconomy.grant_stock(peer, item_id)
	if item_id == FISH_LEGENDARY:
		rpc_id(peer, "record_dock_trophy", DOCK_TROPHY_LEGENDARY_FISH)
	if in_inventory:
		return
	var player := _player_for_peer(peer)
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if player != null and dungeon != null:
		var drop_pos: Vector3 = player.global_position
		drop_pos += -player.global_transform.basis.z * 0.9
		dungeon.spawn_pickup_allocated(item_id, drop_pos)


func _miss(peer: int) -> void:
	var s: Dictionary = _sessions.get(peer, {})
	if s.is_empty():
		return
	# The fish escapes; the bobber STAYS out (reel in to recast).
	s["state"] = SessionState.IDLE
	rpc("fx_escape", peer)


func _end_peer_session(peer: int, _reason: String) -> void:
	_sessions.erase(peer)


func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	# Issue #142: a catch whose grant outcome never arrives lands
	# as a world drop by default (see _land_catch).
	if not _catch_pending.is_empty():
		var now := Time.get_ticks_msec() / 1000.0
		for peer in _catch_pending.keys():
			var rec: Dictionary = _catch_pending[peer]
			if now - float(rec.get("since", now)) > 3.0:
				_catch_pending.erase(peer)
				_land_catch(peer, str(rec.get("item_id", "")), false)
	for peer in _sessions.keys():
		var s: Dictionary = _sessions[peer]
		var player := _player_for_peer(peer)
		if player == null:
			# Fisher gone (disconnect race): end silently.
			_sessions.erase(peer)
			rpc("fx_clear", peer, "")
			continue
		# Drift backstop (the spot's cancel-on-leave, anchored at the
		# cast stance; knockback included, horizontal plane only).
		var flat := Vector2(player.global_position.x, player.global_position.z)
		var anchor: Vector3 = s["cast_from"]
		if flat.distance_to(Vector2(anchor.x, anchor.z)) > LEAVE_RADIUS:
			_sessions.erase(peer)
			rpc("fx_clear", peer, "Fishing interrupted.")
			continue
		if int(s["state"]) == SessionState.WAITING and _now_msec() >= int(s["bite_at"]):
			s["state"] = SessionState.BITING
			s["deadline"] = _now_msec() + REEL_WINDOW_MSEC
			rpc("fx_bite", peer)
		elif int(s["state"]) == SessionState.BITING and _now_msec() > int(s["deadline"]):
			_miss(peer)


## Catch rarity weighted by wait time: longer wait -> better odds.
## (The spot's table, verbatim. Bait shifts both rare thresholds up by
## DockEconomy.BAIT_RARE_SHIFT; the legendary slice sits on top.)
func roll_catch_item(wait_duration: float, baited: bool) -> String:
	var t := clampf((wait_duration - WAIT_MIN) / (WAIT_MAX - WAIT_MIN), 0.0, 1.0)
	var shift := DockEconomy.BAIT_RARE_SHIFT if baited else 0.0
	var roll := debug_catch_roll if debug_catch_roll >= 0.0 else randf()
	if roll < CATCH_LEGENDARY_BASE + CATCH_LEGENDARY_T * t + shift:
		return FISH_LEGENDARY
	if roll < 0.05 + 0.15 * t + shift:
		return "fish_glimmerfin"
	if roll < 0.25 + 0.35 * t + shift:
		return "fish_riverbass"
	return "fish_minnow"


func session_state_for(peer: int) -> int:
	var s: Dictionary = _sessions.get(peer, {})
	if s.is_empty():
		return SessionState.NONE
	return int(s["state"])


func has_bobber(peer: int) -> bool:
	return _sessions.has(peer)


func _roll_wait() -> float:
	if debug_wait_override >= 0.0:
		return debug_wait_override
	return randf_range(WAIT_MIN, WAIT_MAX)


func _now_msec() -> int:
	if debug_now_msec >= 0:
		return debug_now_msec
	return int(Time.get_ticks_msec())


func _ground_y(p: Vector3) -> float:
	var d := _dungeon()
	if d != null:
		return d.ground_height_at(p)
	return p.y


func _dungeon() -> Node:
	var ds := get_tree().get_nodes_in_group("dungeon")
	if ds.is_empty():
		return null
	return ds[0]


## P2P peer id of the RPC sender; local (server) calls fall back to
## the server's own id. Never a 64-bit Steam id (see AGENTS.md).
func _sender_peer() -> int:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender


func _player_for_peer(peer: int) -> Player:
	if test_players.has(peer):
		return test_players[peer] as Player
	for n in get_tree().get_nodes_in_group("players"):
		if n.get_multiplayer_authority() == peer:
			return n as Player
	return null


func _local_player() -> Player:
	return _player_for_peer(int(multiplayer.get_unique_id()))


# --- Presentation (every peer's instance; server broadcasts drive) ---

## Client prediction for the fisher's own cast: play the arc at once
## when the shared validation says water. The fx_cast broadcast
## reconciles (confirm, or convert to a flop).
func predict_cast(peer: int, from: Vector3, landing: Vector3) -> void:
	if not is_water_at(landing):
		return
	_predicted[peer] = true
	_spawn_visual(peer, from, Vector3(landing.x, water_y_at(landing), landing.z), false)


@rpc("authority", "call_local")
func fx_cast(peer: int, from: Vector3, to: Vector3, in_water: bool) -> void:
	var was_predicted := _predicted.has(peer)
	_predicted.erase(peer)
	# Issue #126 sounds: the bobber leaves the rod (landing cues play in
	# FishingVisual at arc arrival, synced to the splash/flop).
	AudioManager.sfx("cast_whoosh", from)
	if was_predicted and in_water and _visuals.has(peer):
		pass # prediction confirmed; keep the running visual
	elif in_water:
		_spawn_visual(peer, from, to, false)
	else:
		_spawn_visual(peer, from, to, true)
	if peer == int(multiplayer.get_unique_id()):
		var p := _local_player()
		if p != null:
			p.set_bobber_out(in_water)


@rpc("authority", "call_local")
func fx_bite(peer: int) -> void:
	var v := _visual_for(peer)
	if v != null:
		v.bite()
		AudioManager.sfx("ping", v.bobber_position(), 1.0, 1.0)
	if peer == int(multiplayer.get_unique_id()):
		var p := _local_player()
		if p != null:
			p.set_bite_ready(true)
			# Issue #126 Phase 3 (bite-cue readability): the fisher
			# gets a HUD toast too — at 15 m the bobber is a long way
			# from the crosshair. Issue #131: Player has no toast()
			# method — the HUD does; the old has_method guard hid
			# the dead call, so the toast never fired.
			if p.hud != null:
				p.hud.toast("Bite! LMB / E to hook")


@rpc("authority", "call_local")
func fx_catch(peer: int, _item_id: String) -> void:
	var v := _visual_for(peer)
	if v != null:
		v.caught()
	_visuals.erase(peer)
	if peer == int(multiplayer.get_unique_id()):
		var p := _local_player()
		if p != null:
			p.set_bobber_out(false)
			p.set_bite_ready(false)


@rpc("authority", "call_local")
func fx_escape(peer: int) -> void:
	var v := _visual_for(peer)
	if v != null:
		v.escape()
	if peer == int(multiplayer.get_unique_id()):
		var p := _local_player()
		if p != null:
			p.set_bite_ready(false)
			if p.hud != null:
				p.hud.toast("It got away... RMB reels in.")


@rpc("authority", "call_local")
func fx_reel_in(peer: int) -> void:
	var v := _visual_for(peer)
	if v != null:
		v.reel_in()
	_visuals.erase(peer)
	if peer == int(multiplayer.get_unique_id()):
		var p := _local_player()
		if p != null:
			p.set_bobber_out(false)
			p.set_bite_ready(false)


@rpc("authority", "call_local")
func fx_clear(peer: int, reason: String) -> void:
	_clear_visual(peer)
	_predicted.erase(peer)
	if peer == int(multiplayer.get_unique_id()):
		var p := _local_player()
		if p != null:
			p.set_bobber_out(false)
			p.set_bite_ready(false)
			if reason != "" and p.hud != null:
				p.hud.toast(reason)


## Each peer records the dock trophy in their own profile + toast
## (server RPC, paralleling the spot's record_dock_trophy).
@rpc("any_peer", "call_local")
func record_dock_trophy(trophy_id: String) -> void:
	var p := _local_player()
	if SaveManager.record_dock_trophy(trophy_id):
		if p != null and p.hud != null:
			p.hud.toast("TROPHY: Starleaper landed!")
		AudioManager.sfx("unlock")


func _spawn_visual(peer: int, from: Vector3, to: Vector3, flop: bool) -> void:
	_clear_visual(peer)
	var v := FishingVisual.new()
	add_child(v)
	v.begin_cast(from, to, flop)
	_visuals[peer] = v
	# Issue #129: the visual self-frees when its resolve animation
	# ends; erase its entry as it exits so the map never holds a
	# stale reference (a flop has no fx resolution call to erase it).
	v.tree_exiting.connect(_on_visual_exiting.bind(peer, v))


func _on_visual_exiting(peer: int, v: FishingVisual) -> void:
	if _visuals.get(peer) == v:
		_visuals.erase(peer)


## Issue #129: validity-safe visual fetch. The typed cast must come
## AFTER the validity check — casting a freed instance logs "Trying
## to cast a freed object" before any guard can run. Stale entries
## (a visual that freed without an fx resolution) prune here.
func _visual_for(peer: int) -> FishingVisual:
	var raw = _visuals.get(peer)
	if raw == null:
		return null
	if not is_instance_valid(raw):
		_visuals.erase(peer)
		return null
	return raw as FishingVisual


func _clear_visual(peer: int) -> void:
	var v := _visual_for(peer)
	if v != null:
		v.queue_free()
	_visuals.erase(peer)
