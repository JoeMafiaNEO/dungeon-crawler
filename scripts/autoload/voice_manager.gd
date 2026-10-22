extends Node
## VoiceManager (issue #196, Phase A prototype): spatial voice chat.
##
## The ONLY place game code touches voice, mirroring the Steam Input
## adapter's isolation doctrine: capture lives behind a replaceable
## backend (set_backend — the suite drives a fake), and the transport +
## playback core never changes regardless of backend. Voice rides the
## existing RPC mesh as peer data: nothing voice-shaped enters a
## validated endpoint, a snapshot, or a save, and the server has no
## authority over it. Solo / session-less: fully inert — no backend
## start, no rigs, no RPCs.
##
## Design: files/spatial-voice-chat-design-2026-10-22.md (gate-passed).
## Steam Voice API signatures re-verified first-hand against the
## shipped GodotSteam 4.22.1 in-tree (live singleton method list,
## 2026-10-22): startVoiceRecording() / stopVoiceRecording() -> void;
## getAvailableVoice() / getVoice(buffer_size) / decompressVoice(
## voice_data, sample_rate, buffer_size) -> Dictionary;
## getVoiceOptimalSampleRate() -> int; setInGameVoiceSpeaking(
## steam_id, speaking) -> void. Dictionary payload keys are read
## DEFENSIVELY (the binary confirms the "voice_data" / "sample_rate"
## literals; extraction takes the first PackedByteArray value, so a
## key variance degrades to silence, never errors), and the extractors
## are pinned as pure functions in the suite.
##
## §4 PvP AUDIBILITY IS PROVISIONAL: AUDIBILITY_MODE below ships at
## the design paper's recommended (iii) — party full band, enemies
## only inside ENEMY_RADIUS and ducked — PENDING JESSE'S RULING on the
## §4 fork. The whole rule is audibility_for(); his ruling is a
## one-line flip of the constant. All tuning numbers in the const
## block are the paper's placeholders, likewise Jesse's to settle.

# --- Tuning placeholders (paper §2/§3/§7 — Jesse's numbers) ---
const FULL_VOLUME_DISTANCE := 6.0 ## unit_size: ~full volume inside this
const MAX_AUDIBLE_DISTANCE := 28.0 ## max_distance: silence beyond this
const JITTER_MS := 100.0 ## jitter buffer prime depth (paper band 80-120)
const VA_HANGOVER_MS := 250.0 ## VA gate hold after the level drops
const VA_DEFAULT_THRESHOLD_DB := -40.0
const SEND_MIN_BYTES := 512 ## flush the send queue at this many bytes
const SEND_MAX_WAIT_S := 0.05 ## ... or after this wait, whichever first
const RECEIVE_RATE_CAP := 40 ## packets/sec/sender (legit ~20) — flood bound
const CAPTURE_BUFFER := 16384 ## getVoice drain buffer
const PCM_FALLBACK_RATE := 48000

# --- §4 audibility (PROVISIONAL — see header) ---
const AUDIBILITY_MODE := 3 ## (i) open / (ii) faction-private / (iii) ducking
const ENEMY_RADIUS := 8.0 ## (iii): enemies audible only inside this
const ENEMY_DUCK := 0.5 ## (iii): enemy gain inside the radius

enum Relation { PARTY, ENEMY }

## Emitted for every packet the manager broadcasts (the suite's
## observation seam for routing/sequence; game code ignores it).
signal packet_broadcast(data: PackedByteArray)

# --- Settings (profile "voice" section; playback volume lives in
# AudioManager's volume family beside Music/SFX) ---
var transmit_enabled := false ## default OFF (paper §6, privacy)
var mode := "auto" ## "auto" | "ptt" | "va"
var va_threshold_db := VA_DEFAULT_THRESHOLD_DB
var mic_muted := false

var _backend: RefCounted = null

# --- Capture / send state ---
var _capturing := false
var _transmitting := false
var _va_gate_open := false
var _va_hold_t := 0.0
var _send_queue: Array = [] ## Array of PackedByteArray (compressed blobs)
var _send_bytes := 0
var _send_wait := 0.0
var _seq := 0
var _mic_ever_heard := false

# --- Receive state ---
var _rigs: Dictionary = {} ## peer_id -> rig Dictionary
var _recv_windows: Dictionary = {} ## peer_id -> {t: float, count: int}
var _peer_muted: Dictionary = {} ## peer_id -> bool (local, never networked)
var _peer_vol: Dictionary = {} ## peer_id -> float 0..1

# --- Housekeeping ---
var _house_t := 0.0
var _context := "" ## "lobby" | "world"

# --- Test seams (never set by game code) ---
var _debug_peers_on := false
var _debug_peers: Array = []
var _debug_context := ""
var _debug_own_id := -1


## The real Steam Voice backend: every Steam Voice call in the game
## goes through this class (and only here). Each call guards on the
## Steam singleton existing; absent Steam = safe defaults, zero
## errors. Mirrors the input adapter's SteamBackend shape.
class SteamVoiceBackend:
	extends RefCounted

	var _rate := 0

	func _steam() -> Object:
		return Engine.get_singleton("Steam")

	func available() -> bool:
		return _steam() != null

	func session_ready() -> bool:
		if _steam() == null:
			return false
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return false
		var sm := tree.root.get_node_or_null("SteamManager")
		return sm != null and bool(sm.get("initialized"))

	func start_capture() -> bool:
		var s := _steam()
		if s == null or not session_ready():
			return false
		_rate = int(s.call("getVoiceOptimalSampleRate"))
		if _rate <= 0:
			_rate = PCM_FALLBACK_RATE
		s.call("startVoiceRecording")
		return true

	func stop_capture() -> void:
		var s := _steam()
		if s != null:
			s.call("stopVoiceRecording")
			set_speaking(false)

	func poll_capture() -> Array:
		var out: Array = []
		var s := _steam()
		if s == null:
			return out
		# getAvailableVoice gates the drain; its Dictionary is only a
		# hint — the payload comes from getVoice, read defensively.
		var avail: Dictionary = s.call("getAvailableVoice")
		if avail.is_empty():
			return out
		var d: Dictionary = s.call("getVoice", CAPTURE_BUFFER)
		var payload := VoiceManager.extract_payload(d)
		if not payload.is_empty():
			out.append(payload)
		return out

	func decompress(blob: PackedByteArray) -> Dictionary:
		var s := _steam()
		if s == null or blob.is_empty():
			return {}
		if _rate <= 0:
			_rate = PCM_FALLBACK_RATE
		var d: Dictionary = s.call("decompressVoice", blob, _rate,
			maxi(65536, blob.size() * 32))
		var pcm := VoiceManager.extract_payload(d)
		if pcm.is_empty():
			return {}
		return {"pcm": pcm, "rate": VoiceManager.extract_rate(d, _rate)}

	func set_speaking(speaking: bool) -> void:
		var s := _steam()
		if s != null and s.has_method("setInGameVoiceSpeaking") \
				and s.has_method("getSteamID"):
			s.call("setInGameVoiceSpeaking", int(s.call("getSteamID")), speaking)

	func output_rate() -> int:
		return _rate if _rate > 0 else PCM_FALLBACK_RATE


## Key-defensive payload extraction (pinned pure function): the
## documented "voice_data" key first, else the first PackedByteArray
## value in the Dictionary, else empty.
static func extract_payload(d: Dictionary) -> PackedByteArray:
	if d.has("voice_data") and d["voice_data"] is PackedByteArray:
		return d["voice_data"]
	for v in d.values():
		if v is PackedByteArray:
			return v
	return PackedByteArray()


## Key-defensive sample-rate extraction (pinned pure function).
static func extract_rate(d: Dictionary, fallback: int) -> int:
	var r := int(d.get("sample_rate", 0))
	return r if r > 0 else fallback


func _ready() -> void:
	if _backend == null:
		_backend = SteamVoiceBackend.new()
	_load_settings()
	_load_peer_settings()


## Test seam: swap the capture backend (the suite drives a fake).
func set_backend(b: RefCounted) -> void:
	_stop_capture()
	_backend = b


func backend() -> RefCounted:
	return _backend


# ------------------------------------------------------------------
# Settings
# ------------------------------------------------------------------

func _load_settings() -> void:
	transmit_enabled = bool(SaveManager.get_profile_setting("voice", "transmit_enabled", false))
	mode = str(SaveManager.get_profile_setting("voice", "mode", "auto"))
	if mode not in ["auto", "ptt", "va"]:
		mode = "auto"
	va_threshold_db = clampf(float(SaveManager.get_profile_setting(
		"voice", "va_threshold_db", VA_DEFAULT_THRESHOLD_DB)), -60.0, -10.0)
	mic_muted = bool(SaveManager.get_profile_setting("voice", "mic_muted", false))


func _save_settings() -> void:
	SaveManager.set_profile_setting("voice", "transmit_enabled", transmit_enabled)
	SaveManager.set_profile_setting("voice", "mode", mode)
	SaveManager.set_profile_setting("voice", "va_threshold_db", va_threshold_db)
	SaveManager.set_profile_setting("voice", "mic_muted", mic_muted)


func set_transmit_enabled(on: bool) -> void:
	transmit_enabled = on
	_save_settings()
	if not on:
		_stop_capture()


func set_mode(m: String) -> void:
	if m in ["auto", "ptt", "va"]:
		mode = m
		_save_settings()


func set_va_threshold_db(db: float) -> void:
	va_threshold_db = clampf(db, -60.0, -10.0)
	_save_settings()


func set_mic_muted(muted: bool) -> void:
	mic_muted = muted
	_save_settings()
	if muted:
		_stop_capture()


## The settings surface's mic line (paper §6): failure shows in
## place of a live toggle; reception is unaffected either way.
func mic_status_text() -> String:
	if _backend == null or not bool(_backend.call("available")):
		return "Microphone unavailable — check system permissions"
	if not bool(_backend.call("session_ready")):
		return "Microphone unavailable — check system permissions"
	if not transmit_enabled:
		return "Microphone off (transmit disabled in Voice settings)"
	if mic_muted:
		return "Microphone muted (M)"
	return "Microphone ready"


# ------------------------------------------------------------------
# Per-player receive controls (API now; roster UI is Phase B)
# ------------------------------------------------------------------

func set_peer_muted(peer: int, muted: bool) -> void:
	_peer_muted[peer] = muted
	_save_peer_settings()


func is_peer_muted(peer: int) -> bool:
	return bool(_peer_muted.get(peer, false))


func set_peer_volume(peer: int, v: float) -> void:
	_peer_vol[peer] = clampf(v, 0.0, 1.0)
	_save_peer_settings()
	_apply_rig_volume(peer)


func peer_volume(peer: int) -> float:
	return float(_peer_vol.get(peer, 1.0))


## Per-player receive settings persist as ONE profile dictionary
## (local only — my mute of you is my setting, never networked).
func _save_peer_settings() -> void:
	var store := {}
	for peer in _peer_muted.keys():
		var e: Dictionary = store.get(str(peer), {})
		e["muted"] = bool(_peer_muted[peer])
		store[str(peer)] = e
	for peer in _peer_vol.keys():
		var e: Dictionary = store.get(str(peer), {})
		e["vol"] = float(_peer_vol[peer])
		store[str(peer)] = e
	SaveManager.set_profile_setting("voice_peers", "all", store)


func _load_peer_settings() -> void:
	var store: Dictionary = SaveManager.get_profile_setting("voice_peers", "all", {})
	for k in store.keys():
		var peer := int(k)
		var e: Dictionary = store[k]
		if e.has("muted"):
			_peer_muted[peer] = bool(e["muted"])
		if e.has("vol"):
			_peer_vol[peer] = clampf(float(e["vol"]), 0.0, 1.0)


# ------------------------------------------------------------------
# Session / context housekeeping
# ------------------------------------------------------------------

## Remote peer ids in the current session (transport-true on Steam
## and ENet alike). Empty = solo / session-less = inert.
func remote_peers() -> Array:
	if _debug_peers_on:
		return _debug_peers.duplicate()
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return []
	return multiplayer.get_peers()


func current_context() -> String:
	if _debug_context != "":
		return _debug_context
	var cs := get_tree().current_scene
	if cs != null and cs.scene_file_path.ends_with("main_menu.tscn"):
		return "lobby"
	return "world"


func _housekeeping() -> void:
	var ctx := current_context()
	var peers := remote_peers()
	if ctx != _context:
		_context = ctx
		_rebuild_rigs(peers)
	else:
		_sync_rigs(peers)
	if peers.is_empty():
		_stop_capture()


func _sync_rigs(peers: Array) -> void:
	for peer in _rigs.keys():
		if peer not in peers:
			_free_rig(peer)
	for peer in peers:
		if peer not in _rigs:
			_make_rig(peer)
		elif _context == "world":
			_maybe_reparent_rig(peer)


func _rebuild_rigs(peers: Array) -> void:
	for peer in _rigs.keys():
		_free_rig(peer)
	_rigs.clear()
	_recv_windows.clear()
	for peer in peers:
		_make_rig(peer)


# ------------------------------------------------------------------
# Capture gating + send path
# ------------------------------------------------------------------

## "auto" resolves per current input source (paper §3): PTT on
## keyboard/mouse, VA on pad (the shipped pad map has no free button).
func effective_mode() -> String:
	if mode == "ptt" or mode == "va":
		return mode
	var src := get_node_or_null("/root/InputSource")
	if src != null and bool(src.call("is_pad")):
		return "va"
	return "ptt"


func _want_capture() -> bool:
	if not transmit_enabled or mic_muted or _backend == null:
		return false
	if remote_peers().is_empty():
		return false
	if effective_mode() == "va":
		return true ## VA meters continuously; the gate decides sends
	return Input.is_action_pressed("voice_ptt")


func _start_capture() -> void:
	if _capturing or _backend == null:
		return
	if not bool(_backend.call("available")) \
			or not bool(_backend.call("session_ready")):
		return ## mic failure: no start, no retry loop — reception unaffected
	if bool(_backend.call("start_capture")):
		_capturing = true
		_mic_ever_heard = false


func _stop_capture() -> void:
	if _transmitting and _backend != null:
		_backend.call("set_speaking", false)
	_transmitting = false
	_va_gate_open = false
	_send_queue.clear()
	_send_bytes = 0
	_send_wait = 0.0
	if _capturing and _backend != null:
		_backend.call("stop_capture")
	_capturing = false


func _set_transmitting(on: bool) -> void:
	if on == _transmitting:
		return
	_transmitting = on
	if _backend != null:
		_backend.call("set_speaking", on)


func _capture_tick(delta: float) -> void:
	# Mute toggle is a polled edge (InputMap action voice_mute, key M).
	if Input.is_action_just_pressed("voice_mute"):
		set_mic_muted(not mic_muted)
	if not _want_capture():
		if _capturing:
			_stop_capture()
		return
	if not _capturing:
		_start_capture()
		if not _capturing:
			return
	var blobs: Array = _backend.call("poll_capture")
	var eff := effective_mode()
	for blob in blobs:
		if not (blob is PackedByteArray) or blob.is_empty():
			continue
		_mic_ever_heard = true
		if eff == "va":
			# VA metering (paper §3): Steam exposes no level meter, so
			# the player's own packets are decompressed locally and
			# RMS-metered; only above-threshold audio is sent.
			var dec: Dictionary = _backend.call("decompress", blob)
			var pcm: PackedByteArray = dec.get("pcm", PackedByteArray())
			if _pcm_level_db(pcm) >= va_threshold_db:
				_va_gate_open = true
				_va_hold_t = VA_HANGOVER_MS / 1000.0
			if _va_gate_open:
				_enqueue_send(blob)
		else:
			_enqueue_send(blob)
	if eff == "va":
		if _va_hold_t > 0.0:
			_va_hold_t -= delta
			if _va_hold_t <= 0.0:
				_va_gate_open = false
		_set_transmitting(_va_gate_open)
	else:
		_set_transmitting(true)
	# Poll-and-drain cadence (paper §1): flush at ~512 B or ~50 ms.
	if not _send_queue.is_empty():
		_send_wait += delta
		if _send_bytes >= SEND_MIN_BYTES or _send_wait >= SEND_MAX_WAIT_S:
			_flush_send_queue()


func _enqueue_send(blob: PackedByteArray) -> void:
	_send_queue.append(blob)
	_send_bytes += blob.size()


func _flush_send_queue() -> void:
	for blob in _send_queue:
		var packet := PackedByteArray()
		packet.resize(2 + blob.size())
		packet[0] = _seq & 0xFF
		packet[1] = (_seq >> 8) & 0xFF
		for i in blob.size():
			packet[2 + i] = blob[i]
		_seq = (_seq + 1) & 0xFFFF
		_send_packet(packet)
	_send_queue.clear()
	_send_bytes = 0
	_send_wait = 0.0


## The broadcast itself: one unreliable any_peer RPC on this autoload
## (identical path on every peer; sender = get_remote_sender_id()).
func _send_packet(packet: PackedByteArray) -> void:
	packet_broadcast.emit(packet)
	rpc("_receive_voice_packet", packet)


@rpc("any_peer", "unreliable")
func _receive_voice_packet(data: PackedByteArray) -> void:
	_handle_voice_packet(multiplayer.get_remote_sender_id(), data)


## RMS level of PCM16 mono, in dB (pure; pinned).
static func _pcm_level_db(pcm: PackedByteArray) -> float:
	var n := pcm.size() / 2
	if n == 0:
		return -120.0
	var acc := 0.0
	for i in n:
		var v := int(pcm[2 * i]) | (int(pcm[2 * i + 1]) << 8)
		if v >= 32768:
			v -= 65536
		var f := float(v) / 32768.0
		acc += f * f
	return linear_to_db(maxf(sqrt(acc / float(n)), 0.000001))


# ------------------------------------------------------------------
# Receive path
# ------------------------------------------------------------------

func _own_id() -> int:
	if _debug_peers_on and _debug_own_id >= 0:
		return _debug_own_id
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 0


## Receive core (the RPC wrapper above supplies the sender). Every
## drop is silent by design — voice is ephemeral peer data.
func _handle_voice_packet(sender: int, data: PackedByteArray) -> void:
	if sender == _own_id() or sender <= 0:
		return ## own voice is never played back locally
	if is_peer_muted(sender):
		return ## per-player mute drops pre-decode
	if not _rate_ok(sender):
		return
	var rig: Dictionary = _rigs.get(sender, {})
	if rig.is_empty():
		return ## no rig (mid-load / not in session): discard
	if data.size() < 3:
		return
	var gain := _audibility_gain(sender)
	if gain <= 0.0:
		return ## §4: this speaker is not audible to me right now
	rig["duck"] = gain
	_apply_rig_volume(sender)
	var seq := int(data[0]) | (int(data[1]) << 8)
	var payload := data.slice(2)
	var last := int(rig["last_seq"])
	if last >= 0:
		var diff := (seq - last) & 0xFFFF
		if diff == 0 or diff > 32768:
			return ## duplicate / stale / out-of-window: never played late
		if diff > 1:
			# Sequence gap: insert silence of the missing packets'
			# duration rather than compress the timeline (paper §1).
			var per := int(rig["last_packet_frames"])
			if per <= 0:
				per = int(float(rig["rate"]) * 0.02)
			var silence := mini(diff - 1, 10) * per
			_enqueue_silence(rig, silence)
	rig["last_seq"] = seq
	if _backend == null:
		return
	var dec: Dictionary = _backend.call("decompress", payload)
	var pcm: PackedByteArray = dec.get("pcm", PackedByteArray())
	if pcm.is_empty():
		return
	var rate := int(dec.get("rate", int(rig["rate"])))
	if rate > 0 and rate != int(rig["rate"]):
		_rig_set_rate(rig, rate)
	var frames := _pcm_to_frames(pcm)
	rig["last_packet_frames"] = frames.size()
	_enqueue_frames(rig, frames)


func _rate_ok(sender: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var w: Dictionary = _recv_windows.get(sender, {"t": now, "count": 0})
	if now - float(w["t"]) >= 1.0:
		w = {"t": now, "count": 0}
	w["count"] = int(w["count"]) + 1
	_recv_windows[sender] = w
	return int(w["count"]) <= RECEIVE_RATE_CAP


func _enqueue_frames(rig: Dictionary, frames: PackedVector2Array) -> void:
	var q: PackedVector2Array = rig["queue"]
	q.append_array(frames)
	rig["queue"] = q


func _enqueue_silence(rig: Dictionary, count: int) -> void:
	if count <= 0:
		return
	var frames := PackedVector2Array()
	frames.resize(count) ## zero-filled = silence
	_enqueue_frames(rig, frames)
	rig["silence_frames"] = int(rig["silence_frames"]) + count


## PCM16 mono -> stereo frames (pure; pinned).
static func _pcm_to_frames(pcm: PackedByteArray) -> PackedVector2Array:
	var frames := PackedVector2Array()
	var n := pcm.size() / 2
	frames.resize(n)
	for i in n:
		var v := int(pcm[2 * i]) | (int(pcm[2 * i + 1]) << 8)
		if v >= 32768:
			v -= 65536
		var f := float(v) / 32768.0
		frames[i] = Vector2(f, f)
	return frames


# ------------------------------------------------------------------
# Speaker rigs
# ------------------------------------------------------------------

func _make_rig(peer: int) -> void:
	var rate := PCM_FALLBACK_RATE
	if _backend != null and _backend.has_method("output_rate"):
		rate = int(_backend.call("output_rate"))
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = rate
	gen.buffer_length = 0.5
	var node: Node
	if _context == "world":
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "Voice"
		p3.unit_size = FULL_VOLUME_DISTANCE
		p3.max_distance = MAX_AUDIBLE_DISTANCE
		p3.stream = gen
		node = p3
	else:
		var pf := AudioStreamPlayer.new()
		pf.bus = "Voice"
		pf.stream = gen
		node = pf
	node.name = "VoiceRig_%d" % peer
	var parent: Node = self
	if _context == "world":
		var pn := _player_node_for(peer)
		if pn != null:
			parent = pn
	parent.add_child(node)
	node.call("play")
	_rigs[peer] = {
		"node": node, "playback": node.call("get_stream_playback"),
		"queue": PackedVector2Array(), "primed": false,
		"last_seq": -1, "rate": rate, "frames_fed": 0,
		"last_packet_frames": 0, "duck": 1.0, "silence_frames": 0,
	}


func _free_rig(peer: int) -> void:
	var rig: Dictionary = _rigs.get(peer, {})
	if rig.is_empty():
		return
	var node: Node = rig["node"]
	if is_instance_valid(node):
		node.queue_free()
	_rigs.erase(peer)


func _maybe_reparent_rig(peer: int) -> void:
	var rig: Dictionary = _rigs.get(peer, {})
	if rig.is_empty():
		return
	var node: Node = rig["node"]
	if not is_instance_valid(node):
		return
	var pn := _player_node_for(peer)
	if pn != null and node.get_parent() != pn:
		node.reparent(pn)
		if node is Node3D:
			(node as Node3D).position = Vector3.ZERO


func _rig_set_rate(rig: Dictionary, rate: int) -> void:
	rig["rate"] = rate
	var node: Node = rig["node"]
	if not is_instance_valid(node):
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = rate
	gen.buffer_length = 0.5
	node.set("stream", gen)
	node.call("play")
	rig["playback"] = node.call("get_stream_playback")
	rig["primed"] = false


func _apply_rig_volume(peer: int) -> void:
	var rig: Dictionary = _rigs.get(peer, {})
	if rig.is_empty():
		return
	var node: Node = rig["node"]
	if is_instance_valid(node):
		var lin := maxf(peer_volume(peer) * float(rig["duck"]), 0.001)
		node.set("volume_db", linear_to_db(lin))


## Jitter-buffered feed: nothing is pushed until JITTER_MS of PCM is
## queued (primed); an underrun re-primes. Returns frames pushed.
func _feed_rigs() -> void:
	for peer in _rigs.keys():
		var rig: Dictionary = _rigs[peer]
		var pb: Object = rig["playback"]
		if pb == null:
			continue
		var q: PackedVector2Array = rig["queue"]
		var jitter_frames := int(float(rig["rate"]) * JITTER_MS / 1000.0)
		if not bool(rig["primed"]):
			if q.size() < jitter_frames:
				continue
			rig["primed"] = true
		var avail := int(pb.call("get_frames_available"))
		var n := mini(q.size(), avail)
		if n <= 0:
			if q.is_empty():
				rig["primed"] = false
			continue
		var chunk := PackedVector2Array()
		chunk.resize(n)
		for i in n:
			chunk[i] = q[i]
		pb.call("push_buffer", chunk)
		rig["queue"] = q.slice(n)
		rig["frames_fed"] = int(rig["frames_fed"]) + n


func _player_node_for(peer: int) -> Node3D:
	for n in get_tree().get_nodes_in_group("players"):
		if n is Node3D and n.get_multiplayer_authority() == peer:
			return n
	return null


# ------------------------------------------------------------------
# §4 audibility — PROVISIONAL (see header). One isolated rule.
# ------------------------------------------------------------------

## The whole §4 rule as a pure function (pinned on fixtures):
## relation + distance -> gain for the RECEIVER. Mode (iii) ships.
static func audibility_for(p_mode: int, relation: int, distance: float) -> float:
	match p_mode:
		1: ## (i) open proximity: enemies are just speakers
			return 1.0
		2: ## (ii) faction-private: enemies never audible
			return 0.0 if relation == Relation.ENEMY else 1.0
		_: ## (iii) ducking: enemies inside ENEMY_RADIUS, ducked
			if relation == Relation.ENEMY:
				return ENEMY_DUCK if distance <= ENEMY_RADIUS else 0.0
			return 1.0


func _relation_to(sender: int) -> int:
	var rts := get_tree().get_first_node_in_group("rts_manager")
	if rts == null:
		return Relation.PARTY ## co-op scenes: one party, no factions
	var fp: Dictionary = rts.get("faction_peers")
	var mine := -1
	var theirs := -1
	for f in fp.keys():
		if int(fp[f]) == _own_id():
			mine = int(f)
		if int(fp[f]) == sender:
			theirs = int(f)
	if mine < 0 or theirs < 0:
		return Relation.PARTY
	return Relation.PARTY if mine == theirs else Relation.ENEMY


func _audibility_gain(sender: int) -> float:
	var rel := _relation_to(sender)
	if rel == Relation.PARTY:
		return audibility_for(AUDIBILITY_MODE, rel, 0.0)
	var dist := 0.0
	var a := _player_node_for(_own_id())
	var b := _player_node_for(sender)
	if a != null and b != null:
		dist = a.global_position.distance_to(b.global_position)
	return audibility_for(AUDIBILITY_MODE, rel, dist)


# ------------------------------------------------------------------
# Main loop + introspection
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	_house_t += delta
	if _house_t >= 0.5:
		_house_t = 0.0
		_housekeeping()
	_capture_tick(delta)
	_feed_rigs()


## Introspection seam (suite + debugging): a copy of a peer's rig
## state, or an empty Dictionary when no rig exists.
func get_rig_state(peer: int) -> Dictionary:
	var rig: Dictionary = _rigs.get(peer, {})
	if rig.is_empty():
		return {}
	return {
		"queued_frames": (rig["queue"] as PackedVector2Array).size(),
		"frames_fed": int(rig["frames_fed"]),
		"silence_frames": int(rig["silence_frames"]),
		"last_seq": int(rig["last_seq"]),
		"primed": bool(rig["primed"]),
		"duck": float(rig["duck"]),
		"rate": int(rig["rate"]),
		"spatial": rig["node"] is AudioStreamPlayer3D,
	}


## Test seam: drive session membership/context without a transport.
func debug_set_session(peers: Array, context: String, own_id: int = -1) -> void:
	_debug_peers_on = true
	_debug_peers = peers.duplicate()
	_debug_context = context
	_debug_own_id = own_id
	_context = ""
	_housekeeping()


func debug_end_session() -> void:
	_debug_peers_on = false
	_debug_peers = []
	_debug_context = ""
	_debug_own_id = -1
	_context = ""
	_housekeeping()
