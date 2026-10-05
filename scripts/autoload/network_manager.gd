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

var peer: SteamMultiplayerPeer
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
	active_run_mode = SaveManager.MODE_MP
	active_run_slot = 0
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
	# Pull the host's game settings from lobby data.
	var diff_str := Steam.getLobbyData(lobby_id, "difficulty")
	var loot_str := Steam.getLobbyData(lobby_id, "loot_mult")
	host_difficulty = float(diff_str) if diff_str != "" else 1.0
	host_loot_mult = float(loot_str) if loot_str != "" else 1.0


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
	# Issue #4 Phase 4: a stale continued roster must never leak into the next
	# session's rejoin matching (wrong slot's seats, phantom roster-lock).
	Dungeon.continued_roster = []
	_reset_peer()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	server_id = 1


func play_solo() -> void:
	leave_lobby()
	is_host = true
	host_difficulty = 1.0
	host_loot_mult = 1.0
	active_run_mode = SaveManager.MODE_SOLO
	active_run_slot = 0
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
