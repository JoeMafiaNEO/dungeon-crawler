extends Node
## Issue #70 Phase 2: LAN loopback harness.
## Run as host: Godot --headless --path . res://tests/lan_loopback.tscn -- --role=host --port=7779
## (Wrapped in a scene so we have Node.multiplayer and rpc.)

var role := "host"
var port := 7779
var result_file := ""
var peer: ENetMultiplayerPeer
var test_passed := false
var handshake_ok := false
var rpc_roundtrip_ok := false

func _ready() -> void:
	# Parse args.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
	result_file = "/tmp/lan_%s.txt" % role
	if FileAccess.file_exists(result_file):
		DirAccess.remove_absolute(result_file)
	print("[LAN] Starting as ", role, " on port ", port)
	
	if role == "host":
		_start_host()
	else:
		_start_client()
	
	await get_tree().create_timer(30.0).timeout
	_report()

func _start_host() -> void:
	peer = ENetMultiplayerPeer.new()
	if peer.create_server(port, 4) != OK:
		_write_result("FAIL: host couldn't create server")
		get_tree().quit()
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_host_peer_connected)
	print("[LAN] Host listening on ", port)
	_write_result("HOST_LISTENING")
	# Keep running; the _ready await handles timeout.
	# (Timer is set up in _ready.)

func _start_client() -> void:
	# Wait a bit for host to be ready.
	await get_tree().create_timer(2.0).timeout
	peer = ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", port) != OK:
		_write_result("FAIL: client couldn't create client")
		get_tree().quit()
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_client_connected)
	multiplayer.connection_failed.connect(_on_client_failed)
	print("[LAN] Client connecting to 127.0.0.1:", port)

func _on_host_peer_connected(id: int) -> void:
	print("[LAN] Host: peer ", id, " connected")
	# Send handshake RPC.
	rpc_id(id, "_lan_test_handshake", 1.5, 2.0)

@rpc("authority", "call_remote", "reliable")
func _lan_test_handshake(difficulty: float, loot: float) -> void:
	print("[LAN] Client: handshake received (diff=", difficulty, ", loot=", loot, ")")
	handshake_ok = true
	# Respond with pong.
	rpc_id(1, "_lan_test_pong")

@rpc("any_peer", "call_remote", "reliable")
func _lan_test_pong() -> void:
	var sender := multiplayer.get_remote_sender_id()
	print("[LAN] Host: pong received from ", sender)
	rpc_roundtrip_ok = true
	_write_result("PASS: handshake + roundtrip OK")
	# Test kick after a delay.
	await get_tree().create_timer(2.0).timeout
	print("[LAN] Host: kicking peer ", sender)
	peer.disconnect_peer(sender)

func _on_client_connected() -> void:
	print("[LAN] Client: connected to server")
	_write_result("CLIENT_CONNECTED")

func _on_client_failed() -> void:
	_write_result("FAIL: client connection failed")

func _report() -> void:
	if role == "host":
		if not test_passed:
			_write_result("FAIL: host timeout (handshake=%s, roundtrip=%s)" % [handshake_ok, rpc_roundtrip_ok])
	get_tree().quit()

func _write_result(text: String) -> void:
	var f := FileAccess.open(result_file, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()
	print("[LAN] Result: ", text)
	if text.begins_with("PASS"):
		test_passed = true
