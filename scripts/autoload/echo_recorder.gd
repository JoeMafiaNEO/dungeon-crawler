extends Node
## EchoRecorder: 10Hz recorder for daily run echoes (issue #9 Phase 2).
##
## Records (tick, position, facing, ability-cast events) during daily runs into
## a compact binary buffer. Pure observation — zero RNG calls, zero gameplay
## interference. On run end, if the player's best daily score, the echo is
## saved to user://echoes/<YYYYMMDD>.dat (~72KB for 10 minutes).
##
## Binary format:
##   Header: "ECHO"(4) + version u8(1) + date YYYYMMDD(8) + seed s32(4)
##           + sample_count u32(4) + event_count u32(4) = 25 bytes
##   Sample (12 bytes): tick u32(4) + pos xyz s16 x100 (6) + yaw u16 (2)
##   Event: tick u32(4) + id_len u8(1) + id bytes

const SAMPLE_HZ := 10.0
const SAMPLE_INTERVAL := 0.1
const ECHO_DIR := "user://echoes"
const MAGIC := "ECHO"
const VERSION := 1
# Position quantized to centimeters; s16 range = ±327.67m (max grid is 96m).
const POS_SCALE := 100.0

var is_recording := false

## "Race my best echo" toggle (issue #9 Phase 2). Set by the Daily menu;
## when true and a best echo exists, the dungeon spawns a visual-only ghost.
var race_echo := false

## Path to a downloaded Workshop echo to race (issue #9 Phase 3). When set,
## the dungeon races this file instead of the local best echo.
var race_echo_path := ""

var _samples := PackedByteArray()
var _sample_count := 0
var _ability_events: Array = []  # Array of {tick:int, ability_id:String}
var _accum := 0.0
var _player: Node3D = null
var _date_str := ""
var _seed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_recording(player: Node3D, date_str: String, seed: int) -> void:
	"""Begin a 10Hz recording session. Pure observation — no RNG touched."""
	stop_recording()
	is_recording = true
	_player = player
	_date_str = date_str
	_seed = seed
	_samples = PackedByteArray()
	_sample_count = 0
	_ability_events = []
	_accum = 0.0


func stop_recording() -> Dictionary:
	"""End recording and return the echo data dictionary."""
	var data := {
		"date": _date_str,
		"seed": _seed,
		"samples": _samples,
		"sample_count": _sample_count,
		"ability_events": _ability_events.duplicate(),
	}
	is_recording = false
	_player = null
	_samples = PackedByteArray()
	_sample_count = 0
	_ability_events = []
	_accum = 0.0
	return data


func record_ability(ability_id: String) -> void:
	"""Log an ability-cast event at the current tick. No-op when idle."""
	if not is_recording or ability_id.is_empty():
		return
	_ability_events.append({"tick": _sample_count, "ability_id": ability_id})


func echo_path_for_date(date_str: String) -> String:
	return "%s/%s.dat" % [ECHO_DIR, date_str]


func has_echo_for_date(date_str: String) -> bool:
	return FileAccess.file_exists(echo_path_for_date(date_str))


func save_echo(data: Dictionary, path: String) -> bool:
	"""Write echo data to the binary file format. Returns success."""
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("echoes"):
		dir.make_dir("echoes")
	var samples: PackedByteArray = data.get("samples", PackedByteArray())
	var events: Array = data.get("ability_events", [])
	var buf := PackedByteArray()
	buf.resize(25)
	buf.encode_s32(0, 0)  # placeholder; overwritten below
	# Header: MAGIC(4) + version u8(1) + date(8) + seed s32(4) + counts u32x2(8)
	var magic_bytes := MAGIC.to_utf8_buffer()
	for i in 4:
		buf[i] = magic_bytes[i]
	buf[4] = VERSION
	var date_bytes := str(data.get("date", "")).left(8).to_utf8_buffer()
	for i in mini(date_bytes.size(), 8):
		buf[5 + i] = date_bytes[i]
	buf.encode_s32(13, int(data.get("seed", 0)))
	buf.encode_u32(17, int(data.get("sample_count", 0)))
	buf.encode_u32(21, events.size())
	buf.append_array(samples)
	for ev in events:
		var ev_buf := PackedByteArray()
		ev_buf.resize(5)
		ev_buf.encode_u32(0, int(ev.get("tick", 0)))
		var id_bytes := str(ev.get("ability_id", "")).to_utf8_buffer().slice(0, 255)
		ev_buf[4] = id_bytes.size()
		ev_buf.append_array(id_bytes)
		buf.append_array(ev_buf)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(buf)
	f.close()
	return true


func load_echo(path: String) -> Dictionary:
	"""Read an echo file. Returns {} on any format error."""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var buf := f.get_buffer(f.get_length())
	f.close()
	if buf.size() < 25:
		return {}
	if buf.slice(0, 4).get_string_from_utf8() != MAGIC:
		return {}
	if buf[4] != VERSION:
		return {}
	var date_str := buf.slice(5, 13).get_string_from_utf8()
	var seed := buf.decode_s32(13)
	var sample_count := buf.decode_u32(17)
	var event_count := buf.decode_u32(21)
	var expected := 25 + sample_count * 12
	if buf.size() < expected:
		return {}
	var samples := buf.slice(25, 25 + sample_count * 12)
	var events: Array = []
	var off := 25 + sample_count * 12
	for i in event_count:
		if off + 5 > buf.size():
			return {}
		var tick := buf.decode_u32(off)
		var id_len := buf[off + 4]
		off += 5
		if off + id_len > buf.size():
			return {}
		var ability_id := buf.slice(off, off + id_len).get_string_from_utf8()
		off += id_len
		events.append({"tick": tick, "ability_id": ability_id})
	return {
		"date": date_str,
		"seed": seed,
		"samples": samples,
		"sample_count": sample_count,
		"ability_events": events,
	}


## Decode a single sample (index) into {tick, pos: Vector3, yaw: float}.
## Static so the ghost and tests share the exact decoding path.
static func decode_sample(samples: PackedByteArray, index: int) -> Dictionary:
	var off := index * 12
	if off + 12 > samples.size():
		return {}
	return {
		"tick": samples.decode_u32(off),
		"pos": Vector3(
			samples.decode_s16(off + 4) / POS_SCALE,
			samples.decode_s16(off + 6) / POS_SCALE,
			samples.decode_s16(off + 8) / POS_SCALE),
		"yaw": float(samples.decode_u16(off + 10)) / 65535.0 * TAU,
	}


static func encode_sample(buf: PackedByteArray, tick: int, pos: Vector3, yaw: float) -> void:
	var off := buf.size()
	buf.resize(off + 12)
	buf.encode_u32(off, tick)
	buf.encode_s16(off + 4, int(clampf(pos.x * POS_SCALE, -32767.0, 32767.0)))
	buf.encode_s16(off + 6, int(clampf(pos.y * POS_SCALE, -32767.0, 32767.0)))
	buf.encode_s16(off + 8, int(clampf(pos.z * POS_SCALE, -32767.0, 32767.0)))
	var yaw_n := int(wrapf(yaw, 0.0, TAU) / TAU * 65535.0)
	buf.encode_u16(off + 10, yaw_n)


func _process(delta: float) -> void:
	if not is_recording:
		return
	if _player == null or not is_instance_valid(_player):
		return
	_accum += delta
	while _accum >= SAMPLE_INTERVAL:
		_accum -= SAMPLE_INTERVAL
		_record_sample()


func _record_sample() -> void:
	# Pure observation: read transform only. No RNG, no gameplay calls.
	var yaw := _player.rotation.y
	encode_sample(_samples, _sample_count, _player.global_position, yaw)
	_sample_count += 1
