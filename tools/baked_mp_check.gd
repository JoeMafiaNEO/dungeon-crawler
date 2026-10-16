extends Node
## Issue #138 Phase 2 validation harness (dev only): a two-process
## LAN session proving the MP content-hash handshake on the baked
## village. Run TWO processes against each other:
##
##   godot --headless --path . res://tools/baked_mp_check.tscn -- --role host --out ~/host.txt [--tamper]
##   godot --headless --path . res://tools/baked_mp_check.tscn -- --role client --out ~/client.txt
##
## Green leg: the host's start_game carries the pinned seed + the
## baked hash in load_dungeon; the client verifies its shipped
## scene, loads the baked village, and reports its hash + layout
## fingerprint (must equal the host's). Tamper leg (--tamper on the
## host): the host sends a WRONG hash; the client must refuse the
## load loudly (baked_version_mismatch) and never enter the dungeon.
##
## The tscn root only spawns the real driver as a root sibling, so
## the driver survives the load_dungeon scene change.

var _is_driver := false
var _role := "host"
var _tamper := false
var _port := 17878
var _out := ""
var _t := 0.0
var _phase := "setup"
var _mismatch_msg := ""
var _settle := 0.0


func _ready() -> void:
	if not _is_driver:
		var driver = load("res://tools/baked_mp_check.gd").new()
		driver.set("_is_driver", true)
		driver.name = "Mp138Driver"
		get_tree().root.call_deferred("add_child", driver)
		return
	_parse_args()
	NetworkManager.selected_class_id = "warrior"
	NetworkManager.baked_version_mismatch.connect(_on_mismatch)
	# Transport note: this VM's sandbox blocks UDP outright, so the
	# game's ENet LAN transport cannot run here at all. The harness
	# therefore wires NetworkManager exactly as host_lan()/join_lan()
	# do, but over a WebSocket peer (TCP loopback) — every game-side
	# code path under test (start_game's payload, the load_dungeon
	# RPC, the hash check, the baked dungeon load) is the real one;
	# only the wire differs.
	if _role == "host":
		NetworkManager.lan_player_name = "Host138"
		var ws := WebSocketMultiplayerPeer.new()
		if ws.create_server(_port) != OK:
			_finish("HOST_WS_FAILED", 1)
			return
		multiplayer.multiplayer_peer = ws
		NetworkManager.transport = NetworkManager.Transport.LAN
		NetworkManager.active_run_mode = "lan"
		NetworkManager.active_run_slot = 0
		NetworkManager.peer = ws
		NetworkManager.is_host = true
		NetworkManager.server_id = 1
		multiplayer.peer_connected.connect(_on_peer_connected)
		_phase = "wait_peer"
		print("[MP138] host listening on ws %d (tamper=%s)" % [_port, str(_tamper)])
	else:
		NetworkManager.lan_player_name = "Client138"
		var ws := WebSocketMultiplayerPeer.new()
		if ws.create_client("ws://127.0.0.1:%d" % _port) != OK:
			_finish("CLIENT_WS_FAILED", 1)
			return
		multiplayer.multiplayer_peer = ws
		NetworkManager.transport = NetworkManager.Transport.LAN
		NetworkManager.active_run_mode = "lan"
		NetworkManager.active_run_slot = 0
		NetworkManager.peer = ws
		NetworkManager.is_host = false
		NetworkManager.server_id = 1
		_phase = "wait_load"
		print("[MP138] client joining ws://127.0.0.1:%d" % _port)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		var key := a
		var val := ""
		var eq := a.find("=")
		if eq > 0:
			key = a.substr(0, eq)
			val = a.substr(eq + 1)
		elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
			val = args[i + 1]
			i += 1
		if key == "--role":
			_role = val
		elif key == "--port":
			_port = int(val)
		elif key == "--out":
			_out = val
		elif key == "--tamper":
			_tamper = true
		i += 1


func _on_mismatch(message: String) -> void:
	_mismatch_msg = message
	print("[MP138] MISMATCH SIGNAL: ", message)


func _on_peer_connected(_id: int) -> void:
	if _phase != "wait_peer":
		return
	_phase = "starting"
	print("[MP138] host: peer connected, starting game (tamper=%s)" % str(_tamper))
	await get_tree().create_timer(1.0).timeout
	if _tamper:
		Dungeon.saved_player_state = {}
		NetworkManager.rpc("load_dungeon", "village", 1, 1,
			"00000000000000000000000000000000000000000000000000000000deadbeef")
	else:
		NetworkManager.start_game()
	_phase = "in_game"


func _process(delta: float) -> void:
	if not _is_driver:
		return
	_t += delta
	if _t > 90.0:
		_finish("TIMEOUT phase=%s" % _phase, 1)
		return
	if _role == "client" and _mismatch_msg != "":
		_finish("REJECTED mismatch: %s" % _mismatch_msg, 0)
		return
	var scene = get_tree().current_scene
	if scene != null and scene.scene_file_path.ends_with("dungeon.tscn"):
		_settle += delta
		if _settle >= 6.0:
			var dgn = get_tree().get_first_node_in_group("dungeon")
			if dgn == null:
				_finish("NO_DUNGEON_NODE", 1)
				return
			var layout = dgn.get("_layout")
			var fp: String = str(layout.fingerprint()) if layout != null else "<none>"
			var players := get_tree().get_nodes_in_group("players").size()
			_finish("IN_DUNGEON role=%s hash=%s players=%d fp=%s" % [
				_role, str(dgn.get("_baked_hash")), players, fp], 0)


func _finish(result: String, code: int) -> void:
	print("[MP138] RESULT ", result)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string(result + "\n")
	set_process(false)
	get_tree().quit(code)
