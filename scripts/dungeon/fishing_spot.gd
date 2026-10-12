class_name FishingSpot
extends Node3D
## E-interact fishing spot at a pier end (issue #102).
## Phase 1: one-player-per-spot server-authoritative locking.
## Phase 2: spot-based fishing minigame. One E claims AND casts
## (DM's call); server rolls the 3-8s wait, broadcasts the bite cue,
## and validates the 1.2s reel window. Catch rarity is weighted by
## wait time (longer wait -> better odds). Miss = bobber lost, recast
## free, spot stays claimed. Walking away from the spot cancels the
## attempt and releases the claim; the player is stationary and
## vulnerable while fishing (movement suppressed client-side, mobs
## aggro normally).
## Phase 5: legendary fish (fish_starleaper) on the catch roll's top
## slice; landing it records the "legendary_fish" dock trophy,
## paralleling the golden crop.
##
## Trust model: the server owns the lock AND the session. Claim RPCs
## take no peer id — the server attributes every call via
## multiplayer.get_remote_sender_id() (P2P peer ids; server = 1, never
## the 64-bit Steam id). Light anti-cheat, co-op game.

enum SessionState { NONE, WAITING, BITING }

const WAIT_MIN := 3.0 ## seconds, server-rolled wait before a bite
const WAIT_MAX := 8.0
const REEL_WINDOW_MSEC := 1200 ## 1.2s reel window after the bite cue
const LEAVE_RADIUS := 3.0 ## horizontal meters from the spot: leaving cancels

## Issue #102 Phase 5: legendary fish + dock trophy, mirroring the
## Phase 3 golden crop (crop_goldengourd / "golden_crop"). Top slice of
## the catch roll; inert trophy item (no sell value — the merchant's
## FISH_SELL table has no entry for it).
const FISH_LEGENDARY := "fish_starleaper"
const DOCK_TROPHY_LEGENDARY_FISH := "legendary_fish"
const CATCH_LEGENDARY_BASE := 0.01 ## Legendary chance at minimum wait. Jesse's numbers call.
const CATCH_LEGENDARY_T := 0.04 ## Scales to 5% at maximum wait (the crop legendary weight).

## TEST SEAMS (never set in production): debug_wait_override >= 0 forces
## the wait roll; debug_now_msec >= 0 replaces Time.get_ticks_msec();
## debug_catch_roll >= 0 forces the catch rarity roll;
## test_player overrides _player_for_peer().
static var debug_wait_override: float = -1.0
static var debug_now_msec: int = -1
static var debug_catch_roll: float = -1.0
var test_player: Player = null

var spot_index: int = 0
var water_point: Vector3 = Vector3.ZERO ## pond center; the bobber lands here
var occupied_by: int = 0 ## peer id holding the spot; 0 = free

var _session_state: int = SessionState.NONE
var _session_peer: int = 0
## Issue #102 Phase 4: bait auto-consumes on cast (server ledger + client
## stack drop in _start_session). While true, the next _roll_catch_item
## shifts rarity toward rare/uncommon, then clears. Cancelled sessions
## clear it in _end_session so it never leaks into a later cast.
var _bait_this_cast := false
var _wait_duration: float = 0.0
var _bite_at_msec: int = 0
var _reel_deadline_msec: int = 0
var _visual: FishingVisual = null


func _ready() -> void:
	add_to_group("fishing_spots")
	_build()


func prompt_text() -> String:
	var me := int(multiplayer.get_unique_id())
	if occupied_by == 0:
		return "Fish here"
	if occupied_by != me:
		return "Spot in use"
	if _session_state != SessionState.NONE:
		return "Reel in! (E)"
	return "Cast again"


func interact(player: Player) -> void:
	var me := int(multiplayer.get_unique_id())
	if occupied_by != 0 and occupied_by != me:
		if player.hud != null:
			player.hud.toast("Someone is already using this spot.")
		return
	if multiplayer.is_server():
		fish_action()
	else:
		rpc_id(NetworkManager.server_peer_id, "fish_action")


## The E flow, server-side: free spot -> claim + cast; active session ->
## reel attempt (early presses ignored); claimed idle spot -> recast.
@rpc("any_peer", "call_local")
func fish_action() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender_peer()
	if occupied_by == 0:
		_claim(peer)
		if occupied_by == peer:
			_start_session(peer)
	elif occupied_by == peer:
		if _session_state == SessionState.NONE:
			_start_session(peer)
		else:
			_reel_attempt(peer)


## Server-authoritative claim: first valid claim wins, everyone syncs.
## Takes no peer id — the caller is attributed via get_remote_sender_id().
@rpc("any_peer", "call_local")
func claim_spot() -> void:
	if not multiplayer.is_server():
		return
	_claim(_sender_peer())


@rpc("any_peer", "call_local")
func release_spot() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender_peer()
	if occupied_by != peer:
		return
	_cancel_session(false)
	occupied_by = 0
	rpc("sync_occupant", 0)


## Server-side forced release (peer disconnect). Never called by clients.
func force_release_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if occupied_by != peer_id:
		return
	_cancel_session(false)
	occupied_by = 0
	rpc("sync_occupant", 0)


@rpc("any_peer", "call_local")
func sync_occupant(peer_id: int) -> void:
	occupied_by = peer_id
	_refresh_marker()


## Client -> server: reel input. Validated against the rolled window.
@rpc("any_peer", "call_local")
func reel_attempt() -> void:
	if not multiplayer.is_server():
		return
	_reel_attempt(_sender_peer())


func is_session_active_for(peer: int) -> bool:
	return _session_state != SessionState.NONE and _session_peer == peer


func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	if occupied_by == 0:
		return
	# Cancel-on-leave: any displacement from the spot cancels the attempt
	# and releases the claim (knockback included — horizontal plane only,
	# so jumping at the spot doesn't false-trigger).
	var holder := _player_for_peer(occupied_by)
	if holder != null:
		var flat := Vector2(holder.global_position.x, holder.global_position.z)
		var sflat := Vector2(global_position.x, global_position.z)
		if flat.distance_to(sflat) > LEAVE_RADIUS:
			_cancel_session(true)
			occupied_by = 0
			rpc("sync_occupant", 0)
			return
	elif _session_state != SessionState.NONE:
		_cancel_session(false)
		return
	if _session_state == SessionState.WAITING and _now_msec() >= _bite_at_msec:
		_session_state = SessionState.BITING
		_reel_deadline_msec = _now_msec() + REEL_WINDOW_MSEC
		rpc_id(_session_peer, "on_bite")
	elif _session_state == SessionState.BITING and _now_msec() > _reel_deadline_msec:
		_miss()


func _claim(peer: int) -> void:
	if occupied_by != 0:
		return
	occupied_by = peer
	rpc("sync_occupant", occupied_by)


func _start_session(peer: int) -> void:
	if _session_state != SessionState.NONE:
		return
	var player := _player_for_peer(peer)
	if player == null:
		return
	_session_peer = peer
	# Issue #102 Phase 4: bait is consumed per cast and applies to this
	# cast's roll (the flagged design choice — no separate "use" step, so
	# the one-E claim+cast flow stays frictionless and the server owns the
	# odds shift).
	if DockEconomy.spend_stock(peer, DockEconomy.BAIT_ITEM):
		_bait_this_cast = true
		var bplayer := _player_for_peer(peer)
		if bplayer != null:
			bplayer.rpc_id(peer, "consume_dock_good", DockEconomy.BAIT_ITEM)
	_wait_duration = _roll_wait()
	_bite_at_msec = _now_msec() + int(_wait_duration * 1000.0)
	_reel_deadline_msec = 0
	_session_state = SessionState.WAITING
	player.rpc_id(peer, "set_fishing", true)
	rpc_id(peer, "on_cast", water_point)


## Reel validation, server-side. Early presses (before the bite) are
## ignored; late presses fall through to the miss path.
func _reel_attempt(peer: int) -> void:
	if peer != _session_peer:
		return
	if _session_state == SessionState.WAITING:
		return
	if _session_state != SessionState.BITING:
		return
	if _now_msec() > _reel_deadline_msec:
		return
	_resolve_catch(peer)


func _resolve_catch(peer: int) -> void:
	var item_id := _roll_catch_item()
	var player := _player_for_peer(peer)
	if player != null:
		player.rpc_id(peer, "receive_item", item_id)
	# Phase 5 validation fix: the catch is a server grant — record it in
	# the DockEconomy stock ledger or the vendor's sell validation
	# (spend_stock) rejects the very fish the server just gave.
	DockEconomy.grant_stock(peer, item_id)
	if item_id == FISH_LEGENDARY:
		# Each peer records the trophy in their own profile (Collection
		# tab), paralleling farm_plot's golden-crop harvest.
		rpc_id(peer, "record_dock_trophy", DOCK_TROPHY_LEGENDARY_FISH)
	_end_session()
	rpc_id(peer, "on_catch", item_id)


func _miss() -> void:
	var peer := _session_peer
	_end_session()
	# Spot stays claimed — recast is free.
	rpc_id(peer, "on_miss")


func _cancel_session(notify: bool) -> void:
	if _session_state == SessionState.NONE:
		return
	var peer := _session_peer
	_end_session()
	if notify:
		rpc_id(peer, "on_cancel")


func _end_session() -> void:
	var peer := _session_peer
	_session_state = SessionState.NONE
	_session_peer = 0
	_bait_this_cast = false
	var player := _player_for_peer(peer)
	if player != null:
		player.rpc_id(peer, "set_fishing", false)


## Catch rarity weighted by wait time: longer wait -> better odds.
## (Numbers are defaults for Jesse to tune; flagged in the report.)
## Bait (issue #102 Phase 4): while _bait_this_cast, both rare thresholds
## shift up by DockEconomy.BAIT_RARE_SHIFT (Jesse's call).
## Phase 5: the legendary slice sits on top of the table, mirroring the
## farm_plot harvest weights (legendary checked first, then rare bands).
func _roll_catch_item() -> String:
	var t := clampf((_wait_duration - WAIT_MIN) / (WAIT_MAX - WAIT_MIN), 0.0, 1.0)
	var shift := DockEconomy.BAIT_RARE_SHIFT if _bait_this_cast else 0.0
	_bait_this_cast = false
	var roll := debug_catch_roll if debug_catch_roll >= 0.0 else randf()
	if roll < CATCH_LEGENDARY_BASE + CATCH_LEGENDARY_T * t + shift:
		return FISH_LEGENDARY
	if roll < 0.05 + 0.15 * t + shift:
		return "fish_glimmerfin"
	if roll < 0.25 + 0.35 * t + shift:
		return "fish_riverbass"
	return "fish_minnow"


func _roll_wait() -> float:
	if debug_wait_override >= 0.0:
		return debug_wait_override
	return randf_range(WAIT_MIN, WAIT_MAX)


func _now_msec() -> int:
	if debug_now_msec >= 0:
		return debug_now_msec
	return int(Time.get_ticks_msec())


## P2P peer id of the RPC sender; local (server) calls fall back to the
## server's own id. Never a 64-bit Steam id (see AGENTS.md).
func _sender_peer() -> int:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender


func _player_for_peer(peer: int) -> Player:
	if test_player != null:
		return test_player
	for n in get_tree().get_nodes_in_group("players"):
		if n.get_multiplayer_authority() == peer:
			return n as Player
	return null


func _local_player() -> Player:
	var me := int(multiplayer.get_unique_id())
	for n in get_tree().get_nodes_in_group("players"):
		if n.get_multiplayer_authority() == me:
			return n as Player
	return null


func _toast_local(msg: String) -> void:
	var p := _local_player()
	if p != null and p.hud != null:
		p.hud.toast(msg)


# --- Client-side presentation (driven by server RPCs) ---
# call_local: the server rpc_ids the fishing peer; when the fisher IS the
# server (host/solo), the call executes locally instead of erroring.

@rpc("any_peer", "call_local")
func on_cast(target: Vector3) -> void:
	_clear_visual()
	_visual = FishingVisual.new()
	add_child(_visual)
	_visual.begin_cast(global_position + Vector3(0, 1.4, 0), target)


@rpc("any_peer", "call_local")
func on_bite() -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	_visual.bite()
	AudioManager.sfx("ping", _visual.bobber_position(), 1.0, 1.0)


@rpc("any_peer", "call_local")
func on_catch(_item_id: String) -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.caught()


@rpc("any_peer", "call_local")
func on_miss() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.missed()
	_toast_local("Missed! E to cast again.")


@rpc("any_peer", "call_local")
func on_cancel() -> void:
	_clear_visual()
	_toast_local("Fishing interrupted.")


## Each peer records the dock trophy in their own profile + toast
## (server RPC, paralleling farm_plot.record_dock_trophy).
@rpc("any_peer", "call_local")
func record_dock_trophy(trophy_id: String) -> void:
	if SaveManager.record_dock_trophy(trophy_id):
		_toast_local("TROPHY: Starleaper landed!")
		AudioManager.sfx("unlock")


func _clear_visual() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null


func _refresh_marker() -> void:
	var marker := get_node_or_null("Marker") as MeshInstance3D
	if marker != null:
		marker.material_override = _marker_mat(occupied_by != 0)


func _marker_mat(occupied: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if occupied:
		m.albedo_color = Color(0.85, 0.25, 0.2)
		m.emission_enabled = true
		m.emission = Color(0.85, 0.2, 0.15)
		m.emission_energy_multiplier = 1.5
	else:
		m.albedo_color = Color(0.3, 0.8, 0.4)
		m.emission_enabled = true
		m.emission = Color(0.25, 0.75, 0.35)
		m.emission_energy_multiplier = 1.2
	return m


func _build() -> void:
	# Wooden sign post marking the spot + a floating availability marker
	# (green = free, red = occupied).
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.30, 0.18)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.14, 1.4, 0.14)
	post.mesh = pm
	post.position = Vector3(0, 0.7, 0)
	post.material_override = wood
	add_child(post)
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	marker.mesh = sm
	marker.position = Vector3(0, 1.6, 0)
	marker.material_override = _marker_mat(false)
	add_child(marker)
