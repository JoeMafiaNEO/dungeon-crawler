extends Node
## Steam P2P lobby hosting / joining built on SteamMultiplayerPeer.
## No dedicated servers: the lobby host is the game server.

signal lobby_list_updated(lobbies: Array) # Array of Dictionaries {id, name, players, max_players}
signal lobby_created_success
signal continue_staging_ready
signal lobby_join_succeeded
signal lobby_members_changed
signal lobby_ready_changed
signal connection_failed(reason: String)
## Issue #133: the session ended underneath a connected CLIENT (the
## host process died or left mid-run). Emitted exactly once per session
## by _note_session_lost; the in-world HUD and the lobby-phase main
## menu each present it and run the shared leave_lobby() teardown.
signal session_lost
## Issue #138 Phase 2: a transition payload named a baked-scene
## content hash this build does not ship (version skew). Presented
## by the main menu (lobby phase) and the HUD (in-world), mirroring
## session_lost; the loading peer does NOT change scene.
signal baked_version_mismatch(message: String)

const GAME_TAG := "dungeon-crawler"
const MAX_PLAYERS := 12
const LAN_PORT := 7777

## Issue #70: transport enum — STEAM (default) or LAN (ENet).
enum Transport { STEAM, LAN }
var transport: Transport = Transport.STEAM
## LAN: cosmetic player name (entered on join, never verified).
var lan_player_name: String = ""
## LAN: peer IDs mapped to cosmetic names (host tracks these).
var lan_names: Dictionary = {}

var peer: MultiplayerPeer
var lobby_id: int = 0
var is_host: bool = false
## Host-configurable game settings (synced to clients via lobby data).
var host_difficulty: float = 1.0
var host_loot_mult: float = 1.0
## Advanced mode multipliers (Jesse 2026-10-11 host rework).
var adv_mob_hp_mult: float = 1.0
var adv_mob_dmg_mult: float = 1.0
var adv_mob_max_spawn: int = 12
var adv_boss_hp_mult: float = 1.0
var adv_boss_dmg_mult: float = 1.0
var adv_wave_credits_mult: float = 1.0
var host_difficulty_preset: String = "normal"  # easy, normal, hard, advanced
## Custom loot rarity distribution (percentages, must sum to 100).
## Empty = default distribution.
var custom_rarity: Dictionary = {}
## Lobby settings.
var lobby_password: String = ""
var lobby_visibility: String = "public"  # public, friends, private
var lobby_player_cap: int = 4
## Allow strangers to join a continued save (fresh level-1 characters).
var lobby_open_roster: bool = false
## Issue #140: the continued run's roster, held by the session owner for
## the whole session. The dungeon captures its own copy from here at
## _ready; this store is set when a continued run launches and cleared
## when a session ends or a fresh one begins — never mid-session.
var continued_session_roster: Array = []
## Continued-run reselect: saved-class notices, keyed by Steam ID.
## The host records an entry when it delivers a roster member's
## notice (and its own at arm time); a guest records only its own on
## receipt. An entry's presence is the session's proof the member
## was told their saved class — the dungeon's register rule and the
## host's own continued load consult it: no notice, no reset (the
## race default — a session can never reset by a timing accident).
## Cleared wherever continued_session_roster is cleared.
var saved_class_notices: Dictionary = {}
signal saved_class_notice_received
## Issue #182 (Mason's Vault P1): per-peer cipher-complete records
## — peer id -> the ONE boolean that peer reported, computed from
## its OWN profile. Fragments, counts and identity are never
## stored here (or anywhere in session state). Cleared wherever
## saved_class_notices is cleared.
var peer_cipher_complete: Dictionary = {}
## Remote peers currently connected (the local peer is folded in
## by the gate computation itself). Maintained by the vault
## lifecycle hooks in the peer connect/disconnect handlers.
var vault_remote_peers: Array = []
## The vault gate verdict. Host-computed; clients only mirror it
## (lan_sync_vault_gate). True iff at least one peer is connected
## (the local peer counts) AND every connected peer's record is
## true. Unknown = not complete, always.
var vault_gate_open := false
## Save file hosting: -1 = fresh run, else the slot index.
var host_save_slot: int = -1
## Ready states for the lobby (Jesse 2026-10-11): peer_id -> bool.
var lobby_ready: Dictionary = {}
## Whether the lobby's class selection is locked (hosting from a save).
var lobby_class_locked: bool = false
var server_id: int = 1
## Multiplayer peer ID of the server. ALWAYS 1 (Godot convention; the
## SteamMultiplayerPeer docs confirm create_host() sets unique_id to 1).
## Use this — NOT server_id — for rpc_id() targets and
## get_remote_sender_id() comparisons. server_id is the 64-bit Steam ID on
## Steam (used for Steam API calls and lobby UI); peer IDs are a separate
## 32-bit namespace, so comparing or rpc'ing with server_id silently breaks
## on Steam (Jesse 2026-10-10: R never started waves because the sender check
## compared peer id 1 against the 64-bit Steam ID).
var server_peer_id: int = 1
## Join timeout (Jesse 2026-10-08): if the P2P connection doesn't establish
## within JOIN_TIMEOUT_S, fail with an error instead of hanging on "Joining..."
## forever. Reset on every join attempt; cancelled on successful connect.
const JOIN_TIMEOUT_S := 15.0
var _join_timeout: float = 0.0
## Issue #133: client session-loss detection. _session_established is
## set when a CLIENT finishes connecting (_on_connected_to_server) and
## cleared on teardown; the host and solo play never set it, so this
## path cannot fire outside a joined session. The engine's
## server_disconnected signal is the primary trigger; because the
## 2026-10-14 host-kill evidence cannot distinguish "signal never
## fired under Steam abrupt-kill" from "fired unhandled", a ~1 Hz
## connection-status poll in _process backstops it.
const SESSION_POLL_S := 1.0
var _session_established: bool = false
var _session_lost_handled: bool = false
var _session_poll_t: float = 0.0
var selected_class_id: String = "warrior"
var lobby_members: Array[int] = []
## Active run slot (issue #4): every in-run save/clear targets this
## (mode, slot). Set by play_solo / host_lobby / continue_run.
## Phase 5's slot picker will choose the slot; until then slot 0.
var active_run_mode: String = "solo"
var active_run_slot: int = 0


func _ready() -> void:
	# Issue #86 Bug 1: the old code took the LAN branch if Steam wasn't
	# initialized yet at _ready() time, never connecting the Steam lobby
	# signals. Joining a Steam lobby then hung on "Joining..." forever
	# because _on_lobby_joined never fired. Fix: always connect the
	# multiplayer signals; connect Steam signals now if initialized, or
	# when SteamManager emits steam_ready.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	# Issue #133: until now NOTHING connected server_disconnected, so a
	# guest whose host vanished got no signal at all (the Oct 14 log
	# contained zero disconnect-handling lines).
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if transport == Transport.LAN:
		# LAN mode: skip Steam lobby signals.
		return
	if SteamManager.initialized:
		_connect_steam_signals()


func _process(delta: float) -> void:
	# Join timeout: fail loudly instead of hanging on "Joining..." forever.
	if _join_timeout > 0.0:
		_join_timeout -= delta
		if _join_timeout <= 0.0:
			_join_timeout = 0.0
			_reset_peer()
			connection_failed.emit("Couldn't reach the host (timed out).")
	else:
		if not SteamManager.steam_ready.is_connected(_connect_steam_signals):
			SteamManager.steam_ready.connect(_connect_steam_signals)
	# Issue #133: session-loss backstop poll (~1 Hz). Only an
	# established client session is polled — the join handshake has its
	# own timeout above, and hosts/solo have no server to lose.
	if _client_session_active():
		_session_poll_t += delta
		if _session_poll_t >= SESSION_POLL_S:
			_session_poll_t = 0.0
			if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
				_note_session_lost()
	else:
		_session_poll_t = 0.0


## Connect the Steam lobby signals (idempotent).
func _connect_steam_signals() -> void:
	if transport == Transport.LAN:
		return
	if Steam.lobby_created.is_connected(_on_lobby_created):
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)


# --- Hosting ---

## Host a fresh lobby in the given MP slot (issue #4 Phase 5).
func host_lobby(slot: int = 0) -> void:
	if not SteamManager.initialized:
		connection_failed.emit("Steam isn't running. Open Steam, then try again.")
		return
	continued_session_roster = []  # Issue #140: a fresh lobby owns no roster.
	saved_class_notices = {}
	_reset_vault_gate_state()  # Issue #182: a fresh session owns no cipher records.
	active_run_mode = SaveManager.MODE_MP
	active_run_slot = slot
	_reset_peer()
	peer = SteamMultiplayerPeer.new()
	if peer.create_host() != OK:
		connection_failed.emit("Couldn't start a host peer.")
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	server_id = SteamManager.steam_id
	var lobby_type := Steam.LOBBY_TYPE_PUBLIC
	match lobby_visibility:
		"friends":
			lobby_type = Steam.LOBBY_TYPE_FRIENDS_ONLY
		"private":
			lobby_type = Steam.LOBBY_TYPE_PRIVATE
	Steam.createLobby(lobby_type, lobby_player_cap)


func _on_lobby_created(connect_result: int, new_lobby_id: int) -> void:
	if connect_result != 1:
		connection_failed.emit("Steam lobby creation failed.")
		return
	lobby_id = new_lobby_id
	if not _continued_run.is_empty():
		_on_continue_lobby_created()
		return
	Steam.setLobbyData(lobby_id, "game", GAME_TAG)
	Steam.setLobbyData(lobby_id, "name", "%s's Dungeon" % SteamManager.persona_name)
	Steam.setLobbyData(lobby_id, "difficulty", str(host_difficulty))
	Steam.setLobbyData(lobby_id, "loot_mult", str(host_loot_mult))
	Steam.setLobbyData(lobby_id, "difficulty_preset", host_difficulty_preset)
	Steam.setLobbyData(lobby_id, "player_cap", str(lobby_player_cap))
	Steam.setLobbyData(lobby_id, "visibility", lobby_visibility)
	if not lobby_password.is_empty():
		Steam.setLobbyData(lobby_id, "has_password", "1")
	if host_difficulty_preset == "advanced":
		Steam.setLobbyData(lobby_id, "adv_mob_hp", str(adv_mob_hp_mult))
		Steam.setLobbyData(lobby_id, "adv_mob_dmg", str(adv_mob_dmg_mult))
		Steam.setLobbyData(lobby_id, "adv_mob_spawn", str(adv_mob_max_spawn))
		Steam.setLobbyData(lobby_id, "adv_boss_hp", str(adv_boss_hp_mult))
		Steam.setLobbyData(lobby_id, "adv_boss_dmg", str(adv_boss_dmg_mult))
		Steam.setLobbyData(lobby_id, "adv_credits", str(adv_wave_credits_mult))
	if not custom_rarity.is_empty():
		Steam.setLobbyData(lobby_id, "custom_rarity", JSON.stringify(custom_rarity))
	Steam.setLobbyJoinable(lobby_id, true)
	_refresh_members()
	lobby_created_success.emit()


# --- LAN hosting (issue #70) ---

## Host a LAN game via ENet. No Steam lobby, no saves.
func host_lan(port: int = LAN_PORT) -> void:
	continued_session_roster = []  # Issue #140: fresh session owns no roster.
	saved_class_notices = {}
	_reset_vault_gate_state()  # Issue #182: a fresh session owns no cipher records.
	transport = Transport.LAN
	active_run_mode = "lan"
	active_run_slot = 0
	_reset_peer()
	var enet := ENetMultiplayerPeer.new()
	if enet.create_server(port, MAX_PLAYERS) != OK:
		connection_failed.emit("Couldn't start a LAN host on port %d." % port)
		return
	peer = enet
	multiplayer.multiplayer_peer = peer
	is_host = true
	# server_id from the actual host peer (never hardcoded).
	server_id = multiplayer.get_unique_id()
	lan_names.clear()
	lan_names[server_id] = lan_player_name if lan_player_name != "" else "Host"
	_refresh_members()
	lobby_created_success.emit()


## Get the site-local IP for the LAN join display.
func get_lan_ip() -> String:
	for addr in IP.get_local_addresses():
		# Site-local: 192.168.x.x, 10.x.x.x, 172.16-31.x.x
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
		if addr.begins_with("172."):
			var parts := addr.split(".")
			if parts.size() >= 2:
				var second := int(parts[1])
				if second >= 16 and second <= 31:
					return addr
	# Fallback: first non-loopback IPv4.
	for addr in IP.get_local_addresses():
		if not addr.begins_with("127.") and addr.contains(".") and not addr.contains(":"):
			return addr
	return "127.0.0.1"


## Join a LAN game via ENet.
func join_lan(address: String, port: int = LAN_PORT, player_name: String = "") -> void:
	transport = Transport.LAN
	lan_player_name = player_name if player_name != "" else "Player"
	active_run_mode = "lan"
	active_run_slot = 0
	_reset_peer()
	var enet := ENetMultiplayerPeer.new()
	if enet.create_client(address, port) != OK:
		connection_failed.emit("Couldn't connect to %s:%d." % [address, port])
		return
	peer = enet
	multiplayer.multiplayer_peer = peer
	is_host = false
	# server_id is set by the handshake (host's actual peer ID).
	server_id = 1
	_join_timeout = JOIN_TIMEOUT_S


## Host -> client: sync difficulty/loot config on LAN join (single RPC).
@rpc("authority", "call_remote", "reliable")
func lan_sync_config(difficulty: float, loot_mult: float, host_name: String) -> void:
	host_difficulty = difficulty
	host_loot_mult = loot_mult
	lan_names[server_id] = host_name
	_refresh_members()


## Client -> host: announce cosmetic name on join.
@rpc("any_peer", "call_remote", "reliable")
func lan_announce_name(player_name: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	lan_names[sender] = player_name
	_refresh_members()
	lobby_members_changed.emit()
	_broadcast_lan_roster()


## Client -> host: sync ready state (Jesse 2026-10-11 lobby rework).
@rpc("any_peer", "call_remote", "reliable")
func sync_ready_state(lobby_id: int, is_ready: bool) -> void:
	if not is_host:
		return
	lobby_ready[lobby_id] = is_ready
	lobby_ready_changed.emit()
	# Broadcast to all so every client sees the update.
	rpc("broadcast_ready_state", lobby_id, is_ready)


## Host -> all: relay a player's ready state.
@rpc("any_peer", "call_remote", "reliable")
func broadcast_ready_state(lobby_id: int, is_ready: bool) -> void:
	lobby_ready[lobby_id] = is_ready
	lobby_ready_changed.emit()


## Host -> all LAN clients: broadcast the full cosmetic-name roster.
## Keeps every client's lobby menu current on join/leave/kick.
@rpc("authority", "call_remote", "reliable")
func lan_sync_roster(names: Dictionary) -> void:
	lan_names = names.duplicate()
	_refresh_members()
	lobby_members_changed.emit()


## Host -> all (addressed): a continued roster member's saved class.
## Broadcast-shaped like the other lobby relays — every client hears
## every notice but records only its own. Carries the saved class_id
## and level the lobby warning presents.
@rpc("authority", "call_remote", "reliable")
func receive_saved_class_notice(for_steam_id: int, class_id: String, level: int) -> void:
	if for_steam_id != 0 and for_steam_id == SteamManager.steam_id:
		saved_class_notices[for_steam_id] = {"class_id": class_id, "level": level}
		saved_class_notice_received.emit()


## This peer's own saved-class notice ({} when none arrived).
func my_saved_class_notice() -> Dictionary:
	return saved_class_notices.get(SteamManager.steam_id, {})


## Host-side: deliver saved-class notices for the armed continued
## run — the host's own is computed locally from the save it armed;
## each roster-matched member now in the lobby gets theirs pushed
## (and the delivery recorded here, which is what the register rule
## and the host's continued load consult). Idempotent per member;
## called when the continued lobby is created and on every
## membership change while the run is armed.
func _push_saved_class_notices() -> void:
	if not is_host or _continued_run.is_empty():
		return
	var my_id := SteamManager.steam_id if SteamManager.initialized else 0
	for entry in _continued_run.get("roster", []):
		if not (entry is Dictionary):
			continue
		var sid := int(entry.get("steam_id", 0))
		if sid == 0 or saved_class_notices.has(sid):
			continue
		if sid != my_id and not lobby_members.has(sid):
			continue
		var ps: Dictionary = entry.get("player_state", {})
		var payload := {"class_id": str(entry.get("class_id", "")),
			"level": int(ps.get("level", 1))}
		saved_class_notices[sid] = payload
		if sid != my_id:
			rpc("receive_saved_class_notice", sid,
				str(payload["class_id"]), int(payload["level"]))


## Issue #182 (Mason's Vault P1): recompute the vault gate from
## the records + the connected set, syncing host -> all on any
## change (or when forced, so a fresh connect hears the current
## verdict). Host-only: clients mirror via lan_sync_vault_gate.
## Solo folds to the local record alone (no remote peers, the
## unique id is the whole connected set).
func recompute_vault_gate(force_sync := false) -> void:
	if not multiplayer.is_server():
		return
	var connected: Array = vault_remote_peers.duplicate()
	var me := multiplayer.get_unique_id()
	if not connected.has(me):
		connected.append(me)
	var open := not connected.is_empty()
	for pid in connected:
		if not bool(peer_cipher_complete.get(pid, false)):
			open = false
			break
	if open != vault_gate_open or force_sync:
		vault_gate_open = open
		rpc("lan_sync_vault_gate", open)


## Host -> all: the vault gate verdict (lan_sync family). Mirrors
## into the Dungeon static the departure board reads, and
## re-renders any board in the station so an in-station flip
## shows without a re-entry.
@rpc("authority", "call_local", "reliable")
func lan_sync_vault_gate(open: bool) -> void:
	vault_gate_open = open
	Dungeon.vault_gate_open = open
	for b in get_tree().get_nodes_in_group("departure_board"):
		if b.has_method("refresh_rows"):
			b.call("refresh_rows")


## Vault lifecycle, called from the peer handlers below: a fresh
## peer has no record, so the gate recomputes closed until they
## report (unknown = not complete).
func vault_peer_connected(id: int) -> void:
	if not vault_remote_peers.has(id):
		vault_remote_peers.append(id)
	recompute_vault_gate(true)


## A departed peer's record AND seat leave the computation — a
## party blocked only by the departed peer's missing/false
## record can open (the settled rule's plain meaning).
func vault_peer_disconnected(id: int) -> void:
	peer_cipher_complete.erase(id)
	vault_remote_peers.erase(id)
	recompute_vault_gate()


## Session start/end: the record starts empty and the gate
## closed, on every peer. Called wherever saved_class_notices
## is cleared.
func _reset_vault_gate_state() -> void:
	peer_cipher_complete = {}
	vault_remote_peers = []
	vault_gate_open = false
	Dungeon.vault_gate_open = false


## Host-side: push the current LAN roster to every connected client.
func _broadcast_lan_roster() -> void:
	if not is_host or transport != Transport.LAN:
		return
	rpc("lan_sync_roster", lan_names)


func _on_lan_peer_connected(id: int) -> void:
	# Host sends config to the new client.
	if is_host and transport == Transport.LAN:
		rpc_id(id, "lan_sync_config", host_difficulty, host_loot_mult,
			lan_names.get(server_id, "Host"))


## Host kick: server-side disconnect (issue #70).
func kick_peer(peer_id: int) -> void:
	if not is_host:
		return
	if transport == Transport.LAN and peer != null:
		peer.disconnect_peer(peer_id)
		lan_names.erase(peer_id)
		_refresh_members()
		lobby_members_changed.emit()
		_broadcast_lan_roster()
	# Steam: no kick API in Phase 1 (lobby owner can use Steam UI).


func start_game() -> void:
	if not is_host:
		return
	# Issue #138 Phase 2: a fresh game always enters village level 1;
	# when a baked village ships, the entry carries its pinned seed
	# and content hash so every peer loads the same baked scene and
	# can verify it before changing scene.
	var seed := Dungeon.fresh_seed_for("village", 1, randi())
	var baked_hash := Dungeon.expected_baked_hash("village", 1, seed)
	if transport == Transport.LAN:
		# LAN has no Steam lobby: broadcast the dungeon load directly.
		Dungeon.saved_player_state = {}
		rpc("load_dungeon", "village", seed, 1, baked_hash)
		return
	if lobby_id == 0:
		return
	Steam.setLobbyJoinable(lobby_id, false)
	Dungeon.saved_player_state = {}
	rpc("load_dungeon", "village", seed, 1, baked_hash)


@rpc("any_peer", "call_local")
func load_dungeon(theme_id: String, level_seed: int, level_number: int, baked_hash: String = "", act1_step_next: int = -2) -> void:
	# Issue #138 Phase 2: MP content-hash handshake (spec section 8).
	# A peer whose shipped baked scene differs from the host's (or
	# who ships none) refuses the load LOUDLY instead of desyncing
	# silently (the #135 lesson). "" = procgen level, no check.
	if baked_hash != "":
		var mine := LevelData.shipped_hash(theme_id)
		if mine != baked_hash:
			var msg := "Level version mismatch (%s): the host's game build differs from yours. Update the game to play this run." % theme_id
			push_error("[Net] %s host=%s local=%s" % [msg, baked_hash, mine])
			baked_version_mismatch.emit(msg)
			return
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = theme_id
	Dungeon.next_seed = level_seed
	Dungeon.next_level_number = level_number
	# Issue #201: the Act 1 axis state rides the level load like
	# the other handoff statics — level generation runs per-peer,
	# so every peer's axis must agree. -2 = not carried (a fresh
	# start): derive from the destination's identity.
	if act1_step_next != -2:
		Dungeon.act1_step = act1_step_next
	else:
		Dungeon.act1_step = Dungeon.derive_act1_step(theme_id, level_number)
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")


## Jesse 2026-10-11: clients load the station for continued station saves.
## Issue #201: an Act 1 station save resumes in the elevator cab, not
## the train car — the host says which via the cab flag.
## Issue #204 (P4): clients load the world scene for a
## continued Act 2 run.
@rpc("any_peer", "call_local")
func load_world() -> void:
	get_tree().change_scene_to_file(Dungeon.WORLD_SCENE)


## This peer's own progression state, captured from whichever
## scene it currently stands in (issue #205): the floor hops
## are direct scene transfers (no vehicle interior), so each
## peer captures its own state before the hop — the train's
## per-peer capture pattern without the car.
func _capture_own_state() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var me := scene.find_child(
		"Player_%d" % multiplayer.get_unique_id(), true, false)
	if me != null and me.has_method("get_state"):
		Dungeon.saved_player_state = me.get_state()
		Dungeon.act2_local_class = str(me.get("class_id"))


## Issue #205 (P5): the party transfer into (or between)
## building floors. Party-together (F0): the broadcast lands
## on every peer; each captures its own state, stamps the
## floor statics identically (the floor itself is synthesized
## locally from the pure FloorGen functions), and loads the
## dungeon scene as that floor. `entry` marks a street entry:
## the respawn anchor moves to this building (P4 semantics —
## the anchor updates on every building ENTRY).
@rpc("any_peer", "call_local")
func load_floor(building_key: String, floor_idx: int,
		entry: bool = false) -> void:
	_capture_own_state()
	Dungeon.floor_key = building_key
	Dungeon.floor_index = floor_idx
	Dungeon.act2_context = "building"
	var rec := FloorGen.record_for(building_key, Dungeon.home_anchor)
	if not rec.is_empty():
		Dungeon.act2_last_transition = {
			"building": building_key, "floor": floor_idx,
			"point": rec["doorstep"]}
		if entry:
			Dungeon.act2_anchor_building = building_key
			Dungeon.act2_anchor_doorstep = rec["doorstep"]
	if multiplayer.is_server():
		Dungeon.save_act2_clock()
		# Issue #209: a street entry starts the attempt
		# clock (server wall-clock). Floor transfers, wipe
		# respawns and continues pass entry=false and never
		# restart it.
		if entry:
			Dungeon.attempt_begin(building_key,
				Time.get_ticks_msec())
	get_tree().change_scene_to_file(
		"res://scenes/dungeon/dungeon.tscn")


## Issue #205: the party transfer OUT of a building, back to
## the street at the anchor building's doorstep.
@rpc("any_peer", "call_local")
func load_world_from_floor() -> void:
	_capture_own_state()
	Dungeon.floor_key = ""
	Dungeon.floor_index = 0
	Dungeon.act2_context = "world"
	Dungeon.act2_spawn_at = "doorstep"
	if multiplayer.is_server():
		Dungeon.save_act2_clock()
		# Issue #209: leaving the building abandons the
		# attempt — no post; re-entry starts a fresh one.
		Dungeon.attempt_clear()
	get_tree().change_scene_to_file(Dungeon.WORLD_SCENE)


@rpc("any_peer", "call_local")
func load_station(level_number: int, cab: bool = false) -> void:
	Station.next_level_number = level_number
	get_tree().change_scene_to_file(
		"res://scenes/station/elevator_cab.tscn" if cab
		else "res://scenes/station/train_interior.tscn")


# --- Joining ---

func refresh_lobby_list() -> void:
	if not SteamManager.initialized:
		return
	Steam.addRequestLobbyListStringFilter("game", GAME_TAG, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()


func _on_lobby_match_list(lobbies: Array) -> void:
	var out: Array = []
	for id in lobbies:
		out.append({
			"id": id,
			"name": Steam.getLobbyData(id, "name"),
			"players": Steam.getNumLobbyMembers(id),
			"max_players": MAX_PLAYERS,
		})
	lobby_list_updated.emit(out)


func join_lobby(id: int) -> void:
	if not SteamManager.initialized:
		connection_failed.emit("Steam isn't running. Open Steam, then try again.")
		return
	continued_session_roster = []  # Issue #140: a joiner owns no roster.
	saved_class_notices = {}
	_reset_vault_gate_state()  # Issue #182: a fresh session owns no cipher records.
	_join_timeout = JOIN_TIMEOUT_S
	Steam.joinLobby(id)


func _on_lobby_joined(joined_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		_join_timeout = 0.0
		connection_failed.emit("Couldn't join that lobby.")
		return
	lobby_id = joined_id
	var owner: int = Steam.getLobbyOwner(lobby_id)
	if owner == SteamManager.steam_id:
		# Host echo (Jesse 2026-10-10): Steam fires lobby_joined for the lobby
		# owner too after createLobby. The server peer from host_lobby() /
		# continue_multiplayer() is already running — keep it and keep is_host
		# (otherwise start_game/kick silently no-op on `if not is_host`).
		# Just refresh the roster.
		_refresh_members()
		lobby_members_changed.emit()
		return
	_reset_peer()
	peer = SteamMultiplayerPeer.new()
	# Jesse 2026-10-08: use connect_to_lobby(lobby_id), not create_client(owner).
	# create_client hangs forever on "Joining..." — the lobby-based connect
	# is the correct Steam P2P flow (LAN/ENet path is unaffected).
	# (Renamed 2026-10-10: this GodotSteam build only exports connect_to_lobby.)
	if peer.connect_to_lobby(lobby_id) != OK:
		_join_timeout = 0.0
		connection_failed.emit("Couldn't connect to the host.")
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	server_id = owner
	# Pull the host's game settings from lobby data.
	var diff_str := Steam.getLobbyData(lobby_id, "difficulty")
	var loot_str := Steam.getLobbyData(lobby_id, "loot_mult")
	host_difficulty = float(diff_str) if diff_str != "" else 1.0
	host_loot_mult = float(loot_str) if loot_str != "" else 1.0


func _on_connected_to_server() -> void:
	_join_timeout = 0.0
	# Issue #133: a client session now exists — arm session-loss
	# detection for it (fresh latch for this session).
	_session_established = true
	_session_lost_handled = false
	_session_poll_t = 0.0
	if transport == Transport.LAN:
		# ENet: server is always peer 1. Announce our cosmetic name.
		server_id = 1
		rpc_id(server_id, "lan_announce_name", lan_player_name)
	_refresh_members()
	lobby_join_succeeded.emit()


func _on_connection_failed() -> void:
	_join_timeout = 0.0
	connection_failed.emit("Connection to host failed.")


## Issue #133: true only while this peer is a CLIENT in an established
## session — the one state that can lose a host. Solo play (peer null,
## is_host set by play_solo) and hosting can never satisfy this.
func _client_session_active() -> bool:
	return _session_established and not is_host and peer != null


func _on_server_disconnected() -> void:
	_note_session_lost()


## Issue #133: single funnel for session loss (engine signal + poll
## backstop). Latched per session so the two triggers can't double-fire,
## and guarded so it can only ever fire for a client holding a peer —
## never for the host, never in solo, never after our own leave_lobby()
## (which sets the latch as it tears down).
func _note_session_lost() -> void:
	if _session_lost_handled or is_host or peer == null:
		return
	_session_lost_handled = true
	_session_established = false
	session_lost.emit()


# --- Members ---

func _on_peer_connected(id: int) -> void:
	if transport == Transport.LAN:
		_on_lan_peer_connected(id)
	vault_peer_connected(id)  # Issue #182: the gate's connected set.
	# Issue #205: a joiner mid-building pulls to the party's
	# current floor (the #135 pattern) — the server directs
	# the new peer straight into the floor scene; the
	# dungeon's register/pull machinery does the rest.
	if multiplayer.is_server() and Dungeon.floor_active():
		rpc_id(id, "load_floor", Dungeon.floor_key,
			Dungeon.floor_index, false)
	_refresh_members()
	lobby_members_changed.emit()
	_push_saved_class_notices()


func _on_peer_disconnected(id: int) -> void:
	if transport == Transport.LAN:
		# Drop the name so ghosts don't linger in the lobby list.
		lan_names.erase(id)
		_broadcast_lan_roster()
	vault_peer_disconnected(id)  # Issue #182: record + seat leave the gate.
	# Issue #126 Phase 2: a dropped peer's fishing session ends — the
	# dungeon's FishingDirector force-ends it (visuals clear on every
	# peer via the fx broadcast).
	if multiplayer.is_server():
		for n in get_tree().get_nodes_in_group("fishing_director"):
			if n.has_method("force_end_peer"):
				n.call("force_end_peer", id)
		for n in get_tree().get_nodes_in_group("farm_plots"):
			if n.has_method("force_release_peer"):
				n.call("force_release_peer", id)
	_refresh_members()
	lobby_members_changed.emit()


func _on_lobby_chat_update(_lobby: int, _changed: int, _maker: int, _state: int) -> void:
	_refresh_members()
	lobby_members_changed.emit()
	_push_saved_class_notices()


func _refresh_members() -> void:
	lobby_members.clear()
	if transport == Transport.LAN:
		# ENet: track connected peers (host=1 + clients).
		if multiplayer.multiplayer_peer != null:
			# Host is always in the list.
			if is_host:
				lobby_members.append(server_id)
			# Add known peers from lan_names (excluding host if already added).
			for pid in lan_names:
				if int(pid) != server_id or not is_host:
					if not lobby_members.has(int(pid)):
						lobby_members.append(int(pid))
		return
	if lobby_id != 0 and SteamManager.initialized:
		var count: int = Steam.getNumLobbyMembers(lobby_id)
		for i in count:
			var m = Steam.getLobbyMemberByIndex(lobby_id, i)
			var sid := 0
			if m is Dictionary:
				sid = int(m.get("steam_id", 0))
			else:
				sid = int(m)
			if sid != 0:
				lobby_members.append(sid)


## Issue #164: peer -> Steam64 mapping, recorded by the dungeon's
## register handshake (the only place both ids meet). Some
## member_name callers pass a peer id, others a Steam64.
var peer_steam_ids: Dictionary = {}


func member_name(peer_id: int) -> String:
	if transport == Transport.LAN:
		return str(lan_names.get(peer_id, "Player %d" % peer_id))
	if SteamManager.initialized:
		# Issue #164: Steam.getFriendPersonaName takes a Steam64 —
		# translate a peer id through the recorded mapping first;
		# an unmapped value is treated as a Steam64 (the roster /
		# bounty callers pass one directly).
		var sid := int(peer_steam_ids.get(peer_id, 0))
		if sid == 0:
			sid = peer_id
		var n := Steam.getFriendPersonaName(sid)
		if n != "":
			return n
	return "Player %d" % peer_id


# --- Leaving / solo ---

func leave_lobby() -> void:
	# Issue #133: our own teardown is not a session loss — disarm the
	# detector (and latch it, so a server_disconnected raised by
	# closing our own peer below can't present as one). A future
	# client session re-arms in _on_connected_to_server.
	_session_established = false
	_session_lost_handled = true
	_session_poll_t = 0.0
	if transport == Transport.LAN:
		lobby_id = 0
		is_host = false
		lobby_members.clear()
		lan_names.clear()
		transport = Transport.STEAM  # Reset to default.
		Dungeon.continued_roster = []
		continued_session_roster = []  # Issue #140: session store ends too.
		saved_class_notices = {}
		_reset_vault_gate_state()  # Issue #182: the cipher record ends with the session.
		_reset_peer()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		server_id = 1
		return
	if lobby_id != 0 and SteamManager.initialized:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false
	lobby_members.clear()
	# Issue #4 Phase 4: a stale continued roster must never leak into the next
	# session's rejoin matching (wrong slot's seats, phantom roster-lock).
	Dungeon.continued_roster = []
	continued_session_roster = []  # Issue #140: session store ends too.
	saved_class_notices = {}
	_reset_peer()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	server_id = 1


## Start a fresh solo run in the given solo slot (issue #4 Phase 5).
func play_solo(slot: int = 0) -> void:
	leave_lobby()
	is_host = true
	host_difficulty = 1.0
	host_loot_mult = 1.0
	active_run_mode = SaveManager.MODE_SOLO
	active_run_slot = slot
	SaveManager.clear_run(active_run_mode, active_run_slot)
	Dungeon.saved_player_state = {}
	# Issue #201: a fresh run opens the Act 1 axis at step 0.
	Dungeon.act1_step = 0
	Dungeon.reset_reveal_state()
	Dungeon.reset_act2_state()
	Dungeon.vault_return_theme = ""
	Dungeon.next_theme_id = "village"
	# Issue #138 Phase 2: fresh solo entry takes the pinned seed
	# when a baked village ships (the baked path engages in _ready).
	Dungeon.next_seed = Dungeon.fresh_seed_for("village", 1, randi())
	Dungeon.next_level_number = 1
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")


## Start today's daily challenge run (deterministic seed).
func play_daily() -> void:
	leave_lobby()
	is_host = true
	# Daily is a fresh run; class saves are untouched.
	Dungeon.saved_player_state = {}
	# Issue #201: a fresh run opens the Act 1 axis at step 0.
	Dungeon.act1_step = 0
	Dungeon.reset_reveal_state()
	Dungeon.reset_act2_state()
	Dungeon.vault_return_theme = ""
	Dungeon.next_theme_id = "village"
	Dungeon.next_seed = DailyRun.get_today_seed()
	Dungeon.next_level_number = 1
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")


## Resume a saved run from the main menu. Branches on multiplayer saves.
## mode/slot address the run in SaveManager's slot API.
func continue_run(mode: String, slot: int) -> bool:
	var run := SaveManager.load_run(mode, slot)
	if run.is_empty():
		return false
	if int(run.get("save_version", 0)) != SaveManager.SAVE_VERSION:
		return false
	# Issue #111 minor 2: a pre-roster MP save would load but restore
	# nobody — refuse it with an explicit message instead of silently
	# starting everyone fresh. The save itself is left untouched;
	# there is no converter by design (Jesse's ruling).
	if SaveManager.is_legacy_mp_save(run):
		push_warning("[Save] Refused legacy MP save in slot %d: predates roster saves" % slot)
		connection_failed.emit(SaveManager.LEGACY_MP_SAVE_MESSAGE)
		return false
	active_run_mode = mode
	active_run_slot = slot
	if bool(run.get("is_multiplayer", false)):
		return continue_multiplayer(run)
	leave_lobby()
	is_host = true
	selected_class_id = str(run.get("class_id", "warrior"))
	Dungeon.saved_player_state = run.get("player_state", {})
	Dungeon.next_theme_id = str(run.get("theme_id", "village"))
	Dungeon.next_seed = int(run.get("seed", randi()))
	Dungeon.next_level_number = int(run.get("level_number", 1))
	Dungeon.next_wave = int(run.get("wave", 0))
	# Issue #201: restore the run's Act 1 axis state (the stored
	# key, else the legacy derivation).
	Dungeon.act1_step = Dungeon.act1_step_for_run(run)
	Dungeon.vault_return_theme = str(run.get("vault_return_theme", ""))
	# Issue #203: restore the reveal state beside the axis.
	Dungeon.restore_reveal_state(run)
	Dungeon.restore_act2_state(run)
	# Issue #205 S3: a run continued inside a building
	# keeps its door stash (the home rooftop door reads it).
	if Dungeon.act2_context == "building":
		Dungeon.act2_local_class = selected_class_id
	# Jesse 2026-10-11: station saves resume AT the station, not in the dungeon.
	# Issue #201: in the run's vehicle — cab for Act 1, train otherwise
	# (the axis was restored just above).
	# Issue #204: an Act 2 run resumes in the world scene, at
	# its last transition point — never mid-street.
	if Dungeon.act2_context == "world":
		get_tree().change_scene_to_file(Dungeon.WORLD_SCENE)
	elif bool(run.get("at_station", false)):
		Station.next_level_number = int(run.get("level_number", 1))
		get_tree().change_scene_to_file(
			"res://scenes/station/elevator_cab.tscn" if Dungeon.act1_step >= 0
			else "res://scenes/station/train_interior.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")
	return true


## Continue a multiplayer run: re-host a Steam lobby, then load the saved level.
## The host's saved state is applied; clients rejoin via the staging UI.
var _continued_run: Dictionary = {}

func continue_multiplayer(run: Dictionary) -> bool:
	if not SteamManager.initialized:
		connection_failed.emit("Steam isn't running. Can't re-host the run.")
		return false
	_continued_run = run
	# Restore host settings from the save.
	var lobby: Dictionary = run.get("lobby", {})
	host_difficulty = float(run.get("host_difficulty", 1.0))
	host_loot_mult = float(run.get("host_loot_mult", 1.0))
	# Jesse 2026-10-11: open-roster flag from the host menu.
	Dungeon.continued_open_lobby = lobby_open_roster
	# Re-host a new lobby with the same settings.
	_reset_peer()
	peer = SteamMultiplayerPeer.new()
	if peer.create_host() != OK:
		connection_failed.emit("Couldn't start a host peer.")
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	server_id = SteamManager.steam_id
	# Issue #110 (M-5): re-host with the visibility stored in the save —
	# a run started public continues public. Legacy saves without the
	# field default to friends-only (the old hardcoded behavior).
	lobby_visibility = str(lobby.get("visibility", "friends"))
	var lobby_type := Steam.LOBBY_TYPE_PUBLIC
	match lobby_visibility:
		"friends":
			lobby_type = Steam.LOBBY_TYPE_FRIENDS_ONLY
		"private":
			lobby_type = Steam.LOBBY_TYPE_PRIVATE
	Steam.createLobby(lobby_type, int(lobby.get("max_players", MAX_PLAYERS)))
	return true


func _on_continue_lobby_created() -> void:
	# Called after the continued-run lobby is created.
	var run_id := "%s_%d" % [str(_continued_run.get("saved_at", "")), int(_continued_run.get("seed", 0))]
	Steam.setLobbyData(lobby_id, "game", GAME_TAG)
	Steam.setLobbyData(lobby_id, "name", str(_continued_run.get("lobby", {}).get("lobby_name", "Dungeon")))
	Steam.setLobbyData(lobby_id, "visibility", lobby_visibility)
	Steam.setLobbyData(lobby_id, "continued_run", "1")
	Steam.setLobbyData(lobby_id, "run_id", run_id)
	Steam.setLobbyData(lobby_id, "difficulty", str(host_difficulty))
	Steam.setLobbyData(lobby_id, "loot_mult", str(host_loot_mult))
	Steam.setLobbyJoinable(lobby_id, true)
	_refresh_members()
	# Continued-run reselect: the run is armed — record the host's
	# own saved-class notice (and any already-present member's).
	_push_saved_class_notices()
	# Show the staging UI; the host starts the run from there.
	continue_staging_ready.emit()


## Host starts the continued run from the staging UI.
## Open the Steam invite dialog for the current lobby.
func open_invite_dialog() -> void:
	if lobby_id != 0 and SteamManager.initialized:
		Steam.activateGameOverlayInviteDialog(lobby_id)


## Invite a specific friend to the lobby.
func invite_friend(steam_id: int) -> void:
	if lobby_id != 0 and SteamManager.initialized:
		Steam.inviteUserToGame(lobby_id, str(steam_id))


func start_continued_run() -> void:
	if not is_host or lobby_id == 0:
		return
	Steam.setLobbyJoinable(lobby_id, false)
	var run := _continued_run
	# Issue #209: a continue ends any attempt — attempt state
	# is never saved, and a restored party has no active
	# attempt until it exits and re-enters via the street.
	Dungeon.attempt_clear()
	# Broadcast the level load to all clients (they pull state via
	# register_class, and the server matches them against the saved roster).
	# Without this the host loads alone and clients sit in staging forever.
	# Issue #204: an Act 2 run loads the WORLD for everyone;
	# clients restore their act2 state from the world root's
	# state pull, the #135 pattern.
	var a2: Dictionary = run.get("act2", {})
	if str(a2.get("context", "")) == "world":
		rpc("load_world")
		return
	# Issue #205: a run saved inside a building resumes the
	# whole party at that (building, floor) — the floor's
	# uncleared waves reset (a fresh floor scene).
	if str(a2.get("context", "")) == "building":
		rpc("load_floor", str(a2.get("floor_key", "")),
			int(a2.get("floor_index", 0)), false)
		return
	# Jesse 2026-10-11: station saves resume AT the station.
	if bool(run.get("at_station", false)):
		# Issue #201: clients resume in the run's vehicle too.
		rpc("load_station", int(run.get("level_number", 1)),
			Dungeon.act1_step_for_run(run) >= 0)
	else:
		var c_theme := str(run.get("theme_id", "village"))
		var c_seed := int(run.get("seed", randi()))
		var c_level := int(run.get("level_number", 1))
		rpc("load_dungeon", c_theme, c_seed, c_level,
			Dungeon.expected_baked_hash(c_theme, c_level, c_seed),
			Dungeon.act1_step_for_run(run))
	_continue_load_level()


## Continued-run reselect: the host's own load plan — the class to
## spawn as and the saved state to apply ({} = a fresh reselect
## spawn). The host's committed lobby pick stands when it differs
## from the saved class AND the host's saved-class notice stands
## recorded for THIS save's class (their warning fired in the lobby
## picker, the identical rule every guest is under). Otherwise the
## restore: saved class, saved state. Pure so tests can drive it.
static func host_continue_plan(run: Dictionary, chosen_class: String,
		notices: Dictionary, my_id: int) -> Dictionary:
	var host_state := {}
	var host_class := "warrior"
	for entry in run.get("roster", []):
		if entry is Dictionary and int(entry.get("steam_id", 0)) == my_id:
			host_state = entry.get("player_state", {})
			host_class = str(entry.get("class_id", "warrior"))
			break
	var notice: Dictionary = notices.get(my_id, {})
	if chosen_class != host_class and not notice.is_empty() \
			and str(notice.get("class_id", "")) == host_class:
		return {"class_id": chosen_class, "player_state": {}}
	return {"class_id": host_class, "player_state": host_state}


## Load the saved level for a continued multiplayer run.
func _continue_load_level() -> void:
	var run := _continued_run
	_continued_run = {}
	# Find the host's roster entry for their saved state — behind a
	# recorded notice, an off-class lobby pick reseeds them fresh
	# (host_continue_plan carries the rule).
	var plan := host_continue_plan(run, selected_class_id,
		saved_class_notices, SteamManager.steam_id)
	selected_class_id = str(plan.get("class_id", "warrior"))
	Dungeon.saved_player_state = plan.get("player_state", {})
	Dungeon.next_theme_id = str(run.get("theme_id", "village"))
	Dungeon.next_seed = int(run.get("seed", randi()))
	Dungeon.next_level_number = int(run.get("level_number", 1))
	Dungeon.next_wave = int(run.get("wave", 0))
	# Issue #201: restore the run's Act 1 axis state (the stored
	# key, else the legacy derivation).
	Dungeon.act1_step = Dungeon.act1_step_for_run(run)
	Dungeon.vault_return_theme = str(run.get("vault_return_theme", ""))
	# Issue #203: restore the reveal state beside the axis.
	Dungeon.restore_reveal_state(run)
	Dungeon.restore_act2_state(run)
	# Issue #205 S3: a run continued inside a building
	# keeps its door stash (the home rooftop door reads it).
	if Dungeon.act2_context == "building":
		Dungeon.act2_local_class = selected_class_id
	# Stash the roster for the staging UI.
	Dungeon.continued_roster = run.get("roster", [])
	# Issue #140: the session store the dungeon captures its roster from.
	continued_session_roster = run.get("roster", []).duplicate()
	# Jesse 2026-10-11: station saves resume AT the station.
	# Issue #201: in the run's vehicle (axis restored just above).
	# Issue #204: an Act 2 run resumes in the world scene, at
	# its last transition point — never mid-street.
	if Dungeon.act2_context == "world":
		get_tree().change_scene_to_file(Dungeon.WORLD_SCENE)
	elif bool(run.get("at_station", false)):
		Station.next_level_number = int(run.get("level_number", 1))
		get_tree().change_scene_to_file(
			"res://scenes/station/elevator_cab.tscn" if Dungeon.act1_step >= 0
			else "res://scenes/station/train_interior.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")


func _reset_peer() -> void:
	if peer != null and is_instance_valid(peer):
		peer.close()
	peer = null
