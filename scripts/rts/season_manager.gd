extends Node
## Issue #10 Phase 1: Warlord Seasons scheduler.
## Server-side 8-minute rotation: Gold Rush → Plague → Mercenary Raid.
## 30s warning + banner per event. Tuning in rts_tuning.cfg [seasons].

class_name SeasonManager

signal season_warning(event_id: String, seconds: float)
signal season_started(event_id: String)
signal season_ended(event_id: String)

const EVENT_IDS := ["gold_rush", "plague", "mercenary_raid"]
const EVENT_NAMES := {
	"gold_rush": "Gold Rush",
	"plague": "Plague",
	"mercenary_raid": "Mercenary Raid",
}

var _rts: RTSManager = null
var _dungeon: Node = null
var _timer := 0.0
var _event_idx := 0
var _warning_sent := false
var _active_event := ""
var _active_timer := 0.0
var _running := false
## Issue #10 Phase 2: track which seasons fired (for sim harness).
var seasons_fired: Array = []

func setup(rts_manager: RTSManager, dungeon: Node) -> void:
	_rts = rts_manager
	_dungeon = dungeon

func start() -> void:
	if not multiplayer.is_server():
		return
	_running = true
	_timer = 0.0
	_event_idx = 0
	_warning_sent = false
	_active_event = ""
	print("[Seasons] Scheduler started (rotation %ds)" % int(_rotation_seconds()))

func stop() -> void:
	_running = false
	_active_event = ""

func _rotation_seconds() -> float:
	return RTSTuning.get_float("seasons", "rotation_seconds", 480.0)

func _warning_seconds() -> float:
	return RTSTuning.get_float("seasons", "warning_seconds", 30.0)

func _process(delta: float) -> void:
	if not _running or not multiplayer.is_server():
		return
	_timer += delta
	var rotation := _rotation_seconds()
	var warning := _warning_seconds()
	
	# Active event tick (e.g., plague damage over time).
	if _active_event != "":
		_active_timer += delta
		_tick_active_event(delta)
	
	# Warning at (rotation - warning) seconds.
	if not _warning_sent and _timer >= rotation - warning:
		_warning_sent = true
		var next_event: String = EVENT_IDS[_event_idx % EVENT_IDS.size()]
		rpc("client_season_warning", next_event, warning)
		season_warning.emit(next_event, warning)
	
	# Event start at rotation seconds.
	if _timer >= rotation:
		_timer = 0.0
		_warning_sent = false
		_start_event(EVENT_IDS[_event_idx % EVENT_IDS.size()])
		_event_idx += 1

func _start_event(event_id: String) -> void:
	_active_event = event_id
	_active_timer = 0.0
	seasons_fired.append(event_id)  # Issue #10 Phase 2: track for sim.
	print("[Seasons] Starting event: ", event_id)
	rpc("client_season_started", event_id)
	season_started.emit(event_id)
	
	match event_id:
		"gold_rush":
			_do_gold_rush()
		"plague":
			_do_plague_start()
		"mercenary_raid":
			_do_mercenary_raid()

func _tick_active_event(delta: float) -> void:
	match _active_event:
		"plague":
			_tick_plague(delta)
		_:
			# Gold Rush and Mercenary Raid are instant; end immediately.
			_end_event()

func _end_event() -> void:
	if _active_event == "":
		return
	var eid := _active_event
	_active_event = ""
	rpc("client_season_ended", eid)
	season_ended.emit(eid)

# --- Gold Rush ---

func _do_gold_rush() -> void:
	if _dungeon == null or not _dungeon.has_method("spawn_rts_node"):
		return
	var count := RTSTuning.get_int("seasons", "gold_rush_nodes", 6)
	var amount := RTSTuning.get_int("seasons", "gold_rush_amount", 500)
	# Spawn extra gold nodes at the contested center ring (4-12m).
	for i in count:
		var pos := _random_center_pos(4.0, 12.0)
		# The dungeon's spawn_rts_node is an RPC; call via dungeon.
		_dungeon.rpc("spawn_rts_node", "gold", pos, amount)
	print("[Seasons] Gold Rush: spawned %d gold nodes" % count)

func _random_center_pos(min_r: float, max_r: float) -> Vector3:
	# Delegate to dungeon's helper if available.
	if _dungeon != null and _dungeon.has_method("_random_land_pos"):
		return _dungeon._random_land_pos(min_r, max_r)
	var angle := randf() * TAU
	var radius := min_r + randf() * (max_r - min_r)
	return Vector3(cos(angle) * radius, 0, sin(angle) * radius)

# --- Plague ---

var _plague_tick_accum := 0.0

func _do_plague_start() -> void:
	_plague_tick_accum = 0.0
	print("[Seasons] Plague started")

func _tick_plague(delta: float) -> void:
	var duration := RTSTuning.get_float("seasons", "plague_duration", 60.0)
	var dps := RTSTuning.get_float("seasons", "plague_dps", 5.0)
	var tick := RTSTuning.get_float("seasons", "plague_tick", 1.0)
	
	if _active_timer >= duration:
		_end_event()
		return
	
	_plague_tick_accum += delta
	if _plague_tick_accum >= tick:
		_plague_tick_accum = 0.0
		_apply_plague_damage(dps * tick)

func _apply_plague_damage(amount: float) -> void:
	# Damage all units, NOT structures. Structures are buildings, not units.
	if _rts == null:
		return
	# Get all units via the RTS unit group.
	for unit in _rts.get_tree().get_nodes_in_group("rts_units"):
		if unit != null and is_instance_valid(unit) and bool(unit.get("alive")):
			# Skip structures: they don't have the unit "alive" in the same way,
			# or check if it's a building. Units are in rts_units; buildings are not.
			if unit.has_method("take_damage"):
				unit.take_damage(amount, -1)

# --- Mercenary Raid ---

func _do_mercenary_raid() -> void:
	if _rts == null or _dungeon == null:
		return
	var count: int = RTSTuning.get_int("seasons", "raid_unit_count", 8)
	var unit_type: String = "spearman"  # Config: seasons.raid_unit_type (string getter TBD)
	# Find the nearest faction to the map center (0,0).
	var target_faction := _nearest_faction_to_center()
	if target_faction < 0:
		return
	print("[Seasons] Mercenary Raid: %d %s targeting faction %d" % [count, unit_type, target_faction])
	# Spawn hostile mercenaries at the map edge, ordered to attack.
	# Spawn directly via the dungeon's RTS node (avoids dungeon.gd changes).
	var rts_node: Node = _dungeon.get_node_or_null("RTS")
	if rts_node == null:
		return
	var unit_script := load("res://scripts/rts/unit.gd")
	var civ_script := load("res://scripts/rts/civ_data.gd")
	var civ = civ_script.for_class("warrior")
	for i in count:
		var angle := (TAU / count) * i
		var pos := Vector3(cos(angle) * 45.0, 0, sin(angle) * 45.0)
		var u: Node3D = unit_script.new()
		u.setup(-99, unit_type, civ)  # Faction -99: hostile mercenaries.
		u.position = pos
		rts_node.add_child(u)
		_order_raid_attack(u, target_faction)


func _order_raid_attack(raider: Node3D, target_faction: int) -> void:
	var best: Node3D = null
	var best_d := INF
	var rpos: Vector3 = raider.global_position
	for node in get_tree().get_nodes_in_group("rts_units"):
		var f = node.get("faction")
		if f != null and int(f) == target_faction:
			var d: float = rpos.distance_to((node as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = node as Node3D
	for node in get_tree().get_nodes_in_group("rts_buildings"):
		var f = node.get("faction")
		if f != null and int(f) == target_faction:
			var d: float = rpos.distance_to((node as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = node as Node3D
	if best != null and raider.has_method("order_attack"):
		raider.order_attack(best)

func _nearest_faction_to_center() -> int:
	if _rts == null or _rts.factions.is_empty():
		return -1
	# Find faction with a unit/building closest to center.
	# Simplified: return the first alive faction (the AI or player).
	for fid in _rts.factions:
		var f: Dictionary = _rts.factions[fid]
		if bool(f.get("alive", false)):
			return int(fid)
	return -1

# --- Client RPCs ---

@rpc("authority", "call_remote", "reliable")
func client_season_warning(event_id: String, seconds: float) -> void:
	season_warning.emit(event_id, seconds)

@rpc("authority", "call_remote", "reliable")
func client_season_started(event_id: String) -> void:
	season_started.emit(event_id)

@rpc("authority", "call_remote", "reliable")
func client_season_ended(event_id: String) -> void:
	season_ended.emit(event_id)

## HUD helper: time until next event (for countdown line).
func time_until_next() -> float:
	if not _running:
		return -1.0
	return _rotation_seconds() - _timer

## HUD helper: current or next event ID.
func current_event_id() -> String:
	if _active_event != "":
		return _active_event
	return EVENT_IDS[_event_idx % EVENT_IDS.size()]

func event_display_name(event_id: String) -> String:
	return EVENT_NAMES.get(event_id, event_id)
