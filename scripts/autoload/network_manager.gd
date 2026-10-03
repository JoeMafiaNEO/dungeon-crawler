extends Node
## Steam P2P lobby hosting / joining built on SteamMultiplayerPeer.
## No dedicated servers: the lobby host is the game server.

signal lobby_list_updated(lobbies: Array) # Array of Dictionaries {id, name, players, max_players}
signal lobby_created_success
signal lobby_join_succeeded
signal lobby_members_changed
signal connection_failed(reason: String)

const GAME_TAG := "dungeon-crawler"
const MAX_PLAYERS := 4

var peer: SteamMultiplayerPeer
var lobby_id: int = 0
var is_host: bool = false
var server_id: int = 1
var selected_class_id: String = "warrior"
var lobby_members: Array[int] = []


func _ready() -> void:
	if not SteamManager.initialized:
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

func host_lobby() -> void:
	if not SteamManager.initialized:
		connection_failed.emit("Steam isn't running. Open Steam, then try again.")
		return
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
	Steam.setLobbyData(lobby_id, "game", GAME_TAG)
	Steam.setLobbyData(lobby_id, "name", "%s's Dungeon" % SteamManager.persona_name)
	Steam.setLobbyJoinable(lobby_id, true)
	_refresh_members()
	lobby_created_success.emit()


func start_game() -> void:
	if not is_host or lobby_id == 0:
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


func _on_connected_to_server() -> void:
	_refresh_members()
	lobby_join_succeeded.emit()


func _on_connection_failed() -> void:
	connection_failed.emit("Connection to host failed.")


# --- Members ---

func _on_peer_connected(_id: int) -> void:
	_refresh_members()
	lobby_members_changed.emit()


func _on_peer_disconnected(_id: int) -> void:
	_refresh_members()
	lobby_members_changed.emit()


func _on_lobby_chat_update(_lobby: int, _changed: int, _maker: int, _state: int) -> void:
	_refresh_members()
	lobby_members_changed.emit()


func _refresh_members() -> void:
	lobby_members.clear()
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


func member_name(steam_id: int) -> String:
	if SteamManager.initialized:
		return Steam.getFriendPersonaName(steam_id)
	return "Player %d" % steam_id


# --- Leaving / solo ---

func leave_lobby() -> void:
	if lobby_id != 0 and SteamManager.initialized:
		Steam.leaveLobby(lobby_id)
	lobby_id = 0
	is_host = false
	lobby_members.clear()
	_reset_peer()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	server_id = 1


func play_solo() -> void:
	leave_lobby()
	is_host = true
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "village"
	Dungeon.next_seed = randi()
	Dungeon.next_level_number = 1
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")


## Resume a saved solo run from the main menu.
func continue_run() -> bool:
	var run := SaveManager.load_run()
	if run.is_empty():
		return false
	leave_lobby()
	is_host = true
	selected_class_id = str(run.get("class_id", "warrior"))
	Dungeon.saved_player_state = run.get("player_state", {})
	Dungeon.next_theme_id = str(run.get("theme_id", "village"))
	Dungeon.next_seed = randi()
	Dungeon.next_level_number = int(run.get("level_number", 1))
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")
	return true


func _reset_peer() -> void:
	if peer != null and is_instance_valid(peer):
		peer.close()
	peer = null
