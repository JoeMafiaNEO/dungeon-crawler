extends Node
## Steam P2P lobby hosting / joining built on SteamMultiplayerPeer.
## No dedicated servers: the lobby host is the game server.

signal lobby_list_updated(lobbies: Array) # Array of Dictionaries {id, name, players, max_players}
signal lobby_created_success
signal continue_staging_ready
signal lobby_join_succeeded
signal lobby_members_changed
signal connection_failed(reason: String)

const GAME_TAG := "dungeon-crawler"
const MAX_PLAYERS := 4
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
var server_id: int = 1
var selected_class_id: String = "warrior"
var lobby_members: Array[int] = []
## Active run slot (issue #4): every in-run save/clear targets this
## (mode, slot). Set by play_solo / host_lobby / continue_run.
## Phase 5's slot picker will choose the slot; until then slot 0.
var active_run_mode: String = "solo"
var active_run_slot: int = 0


func _ready() -> void:
	if transport == Transport.LAN or not SteamManager.initialized:
		# LAN mode: skip Steam lobby signals, but still track peers.
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


# --- Hosting ---

## Host a fresh lobby in the given MP slot (issue #4 Phase 5).
func host_lobby(slot: int = 0) -> void:
	if not SteamManager.initialized:
		connection_failed.emit("Steam isn't running. Open Steam, then try again.")
		return
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
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)


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
	Steam.setLobbyJoinable(lobby_id, true)
	_refresh_members()
	lobby_created_success.emit()


# --- LAN hosting (issue #70) ---

## Host a LAN game via ENet. No Steam lobby, no saves.
func host_lan(port: int = LAN_PORT) -> void:
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


## Host -> all LAN clients: broadcast the full cosmetic-name roster.
## Keeps every client's lobby menu current on join/leave/kick.
@rpc("authority", "call_remote", "reliable")
func lan_sync_roster(names: Dictionary) -> void:
	lan_names = names.duplicate()
	_refresh_members()
	lobby_members_changed.emit()


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
	if transport == Transport.LAN:
		# LAN has no Steam lobby: broadcast the dungeon load directly.
		Dungeon.saved_player_state = {}
		rpc("load_dungeon", "village", randi(), 1)
		return
	if lobby_id == 0:
		return
	Steam.setLobbyJoinable(lobby_id, false)
	Dungeon.saved_player_state = {}
	rpc("load_dungeon", "village", randi(), 1)


@rpc("any_peer", "call_local")
func load_dungeon(theme_id: String, level_seed: int, level_number: int) -> void:
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = theme_id
	Dungeon.next_seed = level_seed
	Dungeon.next_level_number = level_number
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")


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
		return
	Steam.joinLobby(id)


func _on_lobby_joined(joined_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		connection_failed.emit("Couldn't join that lobby.")
		return
	lobby_id = joined_id
	var owner: int = Steam.getLobbyOwner(lobby_id)
	_reset_peer()
	peer = SteamMultiplayerPeer.new()
	if peer.create_client(owner) != OK:
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
	if transport == Transport.LAN:
		# ENet: server is always peer 1. Announce our cosmetic name.
		server_id = 1
		rpc_id(server_id, "lan_announce_name", lan_player_name)
	_refresh_members()
	lobby_join_succeeded.emit()


func _on_connection_failed() -> void:
	connection_failed.emit("Connection to host failed.")


# --- Members ---

func _on_peer_connected(id: int) -> void:
	if transport == Transport.LAN:
		_on_lan_peer_connected(id)
	_refresh_members()
	lobby_members_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if transport == Transport.LAN:
		# Drop the name so ghosts don't linger in the lobby list.
		lan_names.erase(id)
		_broadcast_lan_roster()
	_refresh_members()
	lobby_members_changed.emit()


func _on_lobby_chat_update(_lobby: int, _changed: int, _maker: int, _state: int) -> void:
	_refresh_members()
	lobby_members_changed.emit()


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


func member_name(peer_id: int) -> String:
	if transport == Transport.LAN:
		return str(lan_names.get(peer_id, "Player %d" % peer_id))
	if SteamManager.initialized:
		return Steam.getFriendPersonaName(peer_id)
	return "Player %d" % peer_id


# --- Leaving / solo ---

func leave_lobby() -> void:
	if transport == Transport.LAN:
		lobby_id = 0
		is_host = false
		lobby_members.clear()
		lan_names.clear()
		transport = Transport.STEAM  # Reset to default.
		Dungeon.continued_roster = []
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
	Dungeon.next_theme_id = "village"
	Dungeon.next_seed = randi()
	Dungeon.next_level_number = 1
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")


## Start today's daily challenge run (deterministic seed).
func play_daily() -> void:
	leave_lobby()
	is_host = true
	# Daily is a fresh run; class saves are untouched.
	Dungeon.saved_player_state = {}
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
	# Re-host a new lobby with the same settings.
	_reset_peer()
	peer = SteamMultiplayerPeer.new()
	if peer.create_host() != OK:
		connection_failed.emit("Couldn't start a host peer.")
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	server_id = SteamManager.steam_id
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, int(lobby.get("max_players", MAX_PLAYERS)))
	return true


func _on_continue_lobby_created() -> void:
	# Called after the continued-run lobby is created.
	var run_id := "%s_%d" % [str(_continued_run.get("saved_at", "")), int(_continued_run.get("seed", 0))]
	Steam.setLobbyData(lobby_id, "game", GAME_TAG)
	Steam.setLobbyData(lobby_id, "name", str(_continued_run.get("lobby", {}).get("lobby_name", "Dungeon")))
	Steam.setLobbyData(lobby_id, "continued_run", "1")
	Steam.setLobbyData(lobby_id, "run_id", run_id)
	Steam.setLobbyData(lobby_id, "difficulty", str(host_difficulty))
	Steam.setLobbyData(lobby_id, "loot_mult", str(host_loot_mult))
	Steam.setLobbyJoinable(lobby_id, true)
	_refresh_members()
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
	# Broadcast the dungeon load to all clients (they pull state via
	# register_class, and the server matches them against the saved roster).
	# Without this the host loads alone and clients sit in staging forever.
	rpc("load_dungeon", str(run.get("theme_id", "village")), int(run.get("seed", randi())), int(run.get("level_number", 1)))
	_continue_load_level()


## Load the saved level for a continued multiplayer run.
func _continue_load_level() -> void:
	var run := _continued_run
	_continued_run = {}
	# Find the host's roster entry for their saved state.
	var host_state := {}
	var host_class := "warrior"
	var my_id := SteamManager.steam_id
	for entry in run.get("roster", []):
		if int(entry.get("steam_id", 0)) == my_id:
			host_state = entry.get("player_state", {})
			host_class = str(entry.get("class_id", "warrior"))
			break
	selected_class_id = host_class
	Dungeon.saved_player_state = host_state
	Dungeon.next_theme_id = str(run.get("theme_id", "village"))
	Dungeon.next_seed = int(run.get("seed", randi()))
	Dungeon.next_level_number = int(run.get("level_number", 1))
	# Stash the roster for the staging UI.
	Dungeon.continued_roster = run.get("roster", [])
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")


func _reset_peer() -> void:
	if peer != null and is_instance_valid(peer):
		peer.close()
	peer = null
