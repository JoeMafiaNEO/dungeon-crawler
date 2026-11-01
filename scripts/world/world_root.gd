extends Node3D
## Issue #204 (P4): the real-world scene — Act 2's ground.
## Built from the standard kit the train hop proved: real
## Player nodes, the HUD, the session's multiplayer, late-join
## by state pull. Per-peer by design: each peer's world scene
## is its own (its own WorldStreamer focused on its own
## player — the world is derived data, no shared streaming
## state, no server arbitration), and party members arrive
## independently through the rooftop door.
##
## The root owns: the clock-driven environment (all
## presentation derived locally from Dungeon.world_time via
## WorldClock — the P2 parameter mechanism), the home
## building's standalone assembly on the reveal's reserved
## plot, the entry ready-gate (the inner chunk ring fully
## built behind a black fade before the first look — the P3
## toast-cover pattern), the local player's spawn, a light
## presence protocol for peers in the world together, and
## the death pipeline: a street death respawns at the Act 2
## record's anchor doorstep.
##
## State pull (#135-style): a client whose statics were never
## restored (a fresh joiner) asks the server's world root for
## the reveal + act2 snapshot and waits — bounded — before
## building. In the door-entry and continued-run flows the
## statics are already in place and no pull happens.

const PlayerScene := preload("res://scenes/player/player.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const WorldGen := preload("res://scripts/world/world_gen.gd")
const WorldClock := preload("res://scripts/world/world_clock.gd")
const StreamerScript := preload("res://scripts/world/world_streamer.gd")

const GATE_BOUND_S := 3.0
const PULL_BOUND_S := 2.0
const CLOCK_SAVE_EVERY_S := 30.0
const CLOCK_SYNC_EVERY_S := 5.0

var _streamer: Node3D = null
var _env: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _sun: DirectionalLight3D = null
var _local_player: Player = null
var _local_hud: CanvasLayer = null
var _fade: ColorRect = null
var _gate_open := false
var _gate_deadline := 0.0
var _spawn_point := Vector3.ZERO
var _presence := {} # peer_id -> Player (remote world peers)
var _clock_t := 0.0
var _sync_t := 0.0
var _save_t := 0.0
# Issue #238: the world scene's MP save collection state — the
# mirror of the dungeon saver's (the protocol is mirrored, the
# loss-prevention discipline is CALLED from Dungeon statics).
var _save_roster: Array = []
var _save_pending: Dictionary = {}
var _save_base: Dictionary = {}
var _save_slot := -1
var _respawn_in := -1.0
var _started := false
## Issue #241: the entry arm's outcome for this begin
## (already / armed / refused / skipped) — the pins read
## it; the arm itself is _arm_act2_entry below.
var _entry_arm_outcome := ""


func _ready() -> void:
	# Issue #237: the record funnel samples street
	# positions only while a world scene is live on the
	# peer building the record — this group is its gate.
	add_to_group("world_root")
	_build_environment()
	_streamer = get_node_or_null("WorldStreamer")
	_build_fade()
	# Issue #241: the entry arm runs HERE — after the
	# group registration above (the act2_record funnel's
	# sampling gate; before it, the funnel samples
	# nothing) and before the pull branch, so the host's
	# _begin and every snapshot it later serves see the
	# armed state. The order is specified, not cosmetic.
	_entry_arm_outcome = _arm_act2_entry()
	if _needs_pull():
		_gate_deadline = Time.get_ticks_msec() / 1000.0 \
			+ PULL_BOUND_S + GATE_BOUND_S
		# Issue #242: the request carries the client's claimed
		# Steam ID and lobby-picked class, so the server can
		# answer with the client's own continued state (the
		# world scene has no register flow to arm it).
		rpc_id(NetworkManager.server_peer_id,
			"world_state_request", SteamManager.steam_id,
			NetworkManager.selected_class_id)
	else:
		_begin()


func _needs_pull() -> bool:
	if multiplayer.multiplayer_peer == null \
			or multiplayer.is_server():
		return false
	return Dungeon.home_anchor.is_empty()


## Issue #241: the entry arm — entry arming must not be
## fire-and-forget. The door's transition rpc can fail to
## land silently (its has_method guard, its server leg's
## empty-slot return), and a host/solo begin that accepts
## a context-"" arrival silently poisons every later save
## that session: the clock refuses at "", the writers skip
## the stamp, and the run's Act 2 record is unrecoverable.
## The world scene is where every fresh-entry route
## converges and where the record funnel samples positions
## legitimately, so the guarantee lives here: the arm
## inspects the arrival state itself and either finds it
## armed, repairs it loudly, or refuses it loudly.
## Returns the outcome token: already / armed / refused /
## skipped.
func _arm_act2_entry() -> String:
	# Clients never execute the arm: their context
	# arrives by the state pull, and a client that
	# self-armed would fabricate against the host's
	# record.
	if multiplayer.multiplayer_peer != null \
			and not multiplayer.is_server():
		return "skipped"
	# Case A: the overwhelming common case — the door's
	# rpc landed, a continue restored, an in-session hop
	# set it. Nothing touched, no stamp; the file
	# self-maintains through the clock exactly as today.
	if Dungeon.act2_context == "world":
		# Issue #244 (train T1): the initial discovery
		# beat rides this arm — a pre-train save (or a
		# fresh reveal's first entry) gains the home
		# ring here; a no-op once the set is discovered.
		Dungeon.train_init_discovery()
		return "already"
	var mode: String = NetworkManager.active_run_mode
	var slot: int = NetworkManager.active_run_slot
	var home := Dungeon.home_building()
	if Dungeon.revealed and not home.is_empty():
		# Case B (the Jesse shape): reconstruct the
		# transition record the rpc would have set, from
		# the same source the door used — fill-if-missing
		# only, never overwrite: a partially landed
		# transition keeps what it set.
		var key := str(home["key"])
		var doorstep: Vector3 = home["doorstep"]
		var filled: Array = []
		Dungeon.act2_context = "world"
		if Dungeon.act2_anchor_building == "":
			Dungeon.act2_anchor_building = key
			Dungeon.act2_anchor_doorstep = doorstep
			filled.append("anchor")
		if not Dungeon.act2_cleared.has(key):
			Dungeon.act2_cleared.append(key)
			filled.append("cleared")
		if Dungeon.act2_last_transition.is_empty():
			# Issue #244 rider: the point in the record's
			# canonical [x, y, z] array form — the same
			# shape rpc_act2_transition writes and the
			# arrival reader requires. (This line once
			# stamped the raw Vector3; a fall-through
			# arrival on the reconstructed record then
			# hit a type error in _arrival_point.)
			Dungeon.act2_last_transition = {
				"building": key,
				"point": [doorstep.x, doorstep.y, doorstep.z]}
			filled.append("last_transition")
		if Dungeon.world_time <= 0.0:
			Dungeon.world_time = WorldClock.ENTRY_TIME
			filled.append("world_time")
		# Issue #244 (train T1): the initial discovery
		# beat rides the reconstruction too — initialized
		# BEFORE the stamp below, so a written stamp
		# carries the home ring in its record.
		if Dungeon.train_init_discovery():
			filled.append("train_ring")
		# The file stamp, CONDITIONED (Case B'): if the
		# file already carries a world act2, do NOT stamp
		# — its stored positions survive until the
		# session's own clock re-stamps from live play.
		# An unconditional stamp here would wipe #237
		# positions with a pre-spawn sample. (At _ready
		# no player has spawned, so a stamp taken now
		# samples no positions — the format's "no stored
		# position"; positions arrive with the first
		# clock tick, sampled live in this scene.)
		var run: Dictionary = SaveManager.load_run(mode, slot)
		var file_act2: Dictionary = run.get("act2", {})
		var stamp := "written"
		if run.is_empty():
			stamp = "no_file"
		elif str(file_act2.get("context", "")) == "world":
			stamp = "held_file_already_world"
		else:
			Dungeon.save_act2_clock()
		push_warning("[WorldRoot] #241 entry arm: repaired "
			+ "unarmed arrival (mode=%s slot=%d filled=%s stamp=%s)"
			% [mode, slot,
				",".join(PackedStringArray(filled))
					if not filled.is_empty() else "context",
				stamp])
		return "armed"
	# Case C: nothing faithful to arm — a pre-reveal run
	# has no Act 2 record, and fabricating one would be
	# worse than the disease. An active run that loads
	# non-empty is a real session whose statics deny its
	# own reveal: refuse LOUDLY (no statics changed, no
	# write; the session proceeds, but the shape is named
	# in the log). No active run at all (dev/staging
	# boots, which are legitimate and frequent): skipped,
	# silent by design.
	var run_c: Dictionary = SaveManager.load_run(mode, slot)
	if run_c.is_empty():
		return "skipped"
	push_warning("[WorldRoot] #241 entry arm: REFUSED "
		+ "unarmed arrival (context='%s' revealed=%s home_anchor=%s mode=%s slot=%d)"
		% [Dungeon.act2_context, str(Dungeon.revealed),
			str(not Dungeon.home_anchor.is_empty()), mode, slot])
	return "refused"


## The server root answers a joiner's pull with the run's
## reveal + Act 2 snapshot (the run record's shape, so the
## client restores through the same restore functions a
## continue uses).
## The pull's payload: the run record's own shape, so the
## client restores through the same functions a continue uses.
func state_snapshot() -> Dictionary:
	return {"revealed": Dungeon.revealed,
		"buildings_cleared": Dungeon.buildings_cleared,
		"home_anchor": Dungeon.home_anchor,
		"act2": Dungeon.act2_record(),
		"world_time": Dungeon.world_time}


## Issue #242: the requester's own continued state, computed
## pure (host_continue_plan's idiom, the register rule): the
## claimed Steam ID is matched against the continued roster —
## entry found: the saved class + saved player_state; EXCEPT
## an off-class lobby pick backed by a delivered saved-class
## notice, which returns the picked class with an EMPTY state
## (a deliberate reselect — a fresh character). No entry (or
## an empty roster — every non-continued session): {} — the
## reply carries no your_state at all and the requester spawns
## fresh, as mid-session joiners do today. Delivery is the
## register path's trust posture: the roster match gates what
## is delivered, and the reply goes only to the requester.
static func continued_your_state(roster: Array,
		chosen_class: String, notices: Dictionary,
		claimed_id: int) -> Dictionary:
	var saved_state := {}
	var saved_class := "warrior"
	for entry in roster:
		if entry is Dictionary and claimed_id != 0 \
				and int(entry.get("steam_id", 0)) == claimed_id:
			saved_state = entry.get("player_state", {})
			saved_class = str(entry.get("class_id", "warrior"))
			var notice: Dictionary = notices.get(claimed_id, {})
			if chosen_class != saved_class \
					and not notice.is_empty() \
					and str(notice.get("class_id", "")) \
						== saved_class:
				return {"class_id": chosen_class,
					"player_state": {}}
			return {"class_id": saved_class,
				"player_state": saved_state}
	return {}


@rpc("any_peer")
func world_state_request(claimed_steam_id: int = 0,
		chosen_class: String = "") -> void:
	if not multiplayer.is_server():
		return
	var snap := state_snapshot()
	# Issue #242: a continuing client's own class/state rides
	# the reply (the snapshot itself is context-only, as
	# before) — present only when the claim matches the
	# continued roster.
	var yours := continued_your_state(Dungeon.continued_roster,
		chosen_class, NetworkManager.saved_class_notices,
		claimed_steam_id)
	if not yours.is_empty():
		snap["your_state"] = yours
	rpc_id(multiplayer.get_remote_sender_id(),
		"world_state_apply", snap)


@rpc("any_peer")
func world_state_apply(snap: Dictionary) -> void:
	if _started:
		return
	Dungeon.restore_reveal_state(snap)
	Dungeon.restore_act2_state(snap)
	# Issue #242: arm the client's own continued class/state
	# BEFORE _begin — _spawn_local reads exactly these two
	# statics, in this precedence. Absent (a fresh join), both
	# keep whatever the restores left and the spawn is fresh.
	var yours: Dictionary = snap.get("your_state", {})
	if not yours.is_empty():
		Dungeon.act2_local_class = str(yours.get("class_id", ""))
		Dungeon.saved_player_state = yours.get("player_state", {})
	_begin()


func _begin() -> void:
	if _started:
		return
	_started = true
	_gate_deadline = Time.get_ticks_msec() / 1000.0 + GATE_BOUND_S
	if Dungeon.world_time <= 0.0:
		Dungeon.world_time = WorldClock.ENTRY_TIME
	_spawn_point = _arrival_point()
	_setup_streamer()
	_build_home()
	_spawn_local()
	_announce_presence()


## Arrival: the anchor's doorstep after a door transition;
## on a continue, the player's own stored street position
## (issue #237 — Jesse's amendment of the #204 rule);
## else the record's last transition point; else the
## doorstep. Y is re-sampled from the terrain function at
## the point itself (the record's y is the ground at the
## building's center). Death respawns never come here —
## they use the anchor doorstep directly.
func _arrival_point() -> Vector3:
	var p := Vector3.ZERO
	var from_stored := false
	if Dungeon.act2_spawn_at == "doorstep":
		Dungeon.act2_spawn_at = ""
		p = Dungeon.act2_anchor_doorstep
	elif not Dungeon.act2_my_position().is_empty():
		# Issue #237: my stored position — exact XZ; a
		# stored (0, 0) is a real spot, so this branch
		# tracks itself instead of the ZERO sentinel.
		var mine := Dungeon.act2_my_position()
		p = Vector3(float(mine[0]), 0.0, float(mine[1]))
		from_stored = true
	elif not Dungeon.act2_last_transition.is_empty():
		var pt: Array = Dungeon.act2_last_transition.get(
			"point", [])
		if pt.size() == 3:
			p = Vector3(float(pt[0]), float(pt[1]), float(pt[2]))
	if p == Vector3.ZERO and not from_stored:
		p = Dungeon.act2_anchor_doorstep
	p.y = WorldGen.height_at(WorldGen.WORLD_SEED, p.x, p.z) + 0.4
	return p


func _setup_streamer() -> void:
	if _streamer == null:
		return
	if not Dungeon.home_anchor.is_empty():
		var ha := Dungeon.home_anchor
		_streamer.set("suppress_rect", Rect2(
			float(ha["rect_x"]), float(ha["rect_z"]),
			float(ha["rect_w"]), float(ha["rect_d"])))
		_streamer.set("suppress_enabled", true)
	# Issue #244 T2: hand the streamer the run's train
	# network — the discovered set from the statics + the
	# home node's center and station point (the home
	# building's doorstep), the suppress_rect pattern.
	var home := Dungeon.home_building()
	if not home.is_empty():
		var ho: Vector3 = home["origin"]
		var hd: Vector3 = home["doorstep"]
		_streamer.call("set_track_network",
			Dungeon.act2_train_cities,
			Vector2(ho.x, ho.z), Vector2(hd.x, hd.z))
	_streamer.call("set_target_position", _spawn_point)


func _build_home() -> void:
	var home := Dungeon.home_building()
	if home.is_empty():
		return
	var node: Node3D = _streamer.call(
		"build_standalone_building", home["plan"],
		home["origin"], true, str(home["key"]))
	add_child(node)


func _spawn_local() -> void:
	var class_id := Dungeon.act2_local_class
	if class_id == "":
		class_id = str(Dungeon.saved_player_state.get(
			"class_id", ""))
	if class_id == "":
		class_id = "warrior"
	_local_player = _make_player(multiplayer.get_unique_id(),
		class_id, _spawn_point)
	if not Dungeon.saved_player_state.is_empty():
		_local_player.apply_state(Dungeon.saved_player_state)
		Dungeon.saved_player_state = {}
	_local_hud = HudScene.instantiate()
	add_child(_local_hud)
	_local_hud.setup(_local_player)
	_local_player.died.connect(_on_local_died)
	if _streamer != null:
		_streamer.call("set_target_node", _local_player)


func _make_player(pid: int, class_id: String, pos: Vector3) -> Player:
	var p := PlayerScene.instantiate() as Player
	p.name = "Player_%d" % pid
	p.class_id = class_id
	p.set_multiplayer_authority(pid)
	p.position = pos
	add_child(p)
	return p


## Presence: peers in the world together see each other's
## class bodies. Deliberately light (P4): hellos carry the
## peer's class; full cross-scene state replication is later
## work. Presence is presentation — the world itself never
## depends on it.
## Issue #237: my own street position for the presence
## payload ([x, y, z], or [] when there is no local player
## to read) — a fact about the sender, announced by the
## sender; no peer derives or validates anyone's world.
func _my_presence_pos() -> Array:
	if _local_player == null:
		return []
	var gp := _local_player.global_position
	return [gp.x, gp.y, gp.z]


func _announce_presence() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	rpc("world_hello", multiplayer.get_unique_id(),
		_local_player.class_id if _local_player != null else "",
		_my_presence_pos())


@rpc("any_peer")
func world_hello(pid: int, class_id: String, pos: Array = []) -> void:
	_spawn_remote(pid, class_id, pos)
	rpc_id(pid, "world_present", multiplayer.get_unique_id(),
		_local_player.class_id if _local_player != null else "",
		_my_presence_pos())


@rpc("any_peer")
func world_present(pid: int, class_id: String, pos: Array = []) -> void:
	_spawn_remote(pid, class_id, pos)


func _spawn_remote(pid: int, class_id: String, pos: Array = []) -> void:
	if pid == multiplayer.get_unique_id() or _presence.has(pid) \
			or not _started:
		return
	# Issue #237: a hello carrying the sender's position
	# places the replica where that player actually
	# stands; without a usable one, the arrival offset
	# stands, exactly as before.
	var at := _spawn_point + Vector3(1.5, 0, 1.5)
	if pos.size() == 3 and (pos[0] is int or pos[0] is float) \
			and (pos[1] is int or pos[1] is float) \
			and (pos[2] is int or pos[2] is float) \
			and is_finite(float(pos[0])) \
			and is_finite(float(pos[1])) \
			and is_finite(float(pos[2])):
		at = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	_presence[pid] = _make_player(pid,
		class_id if class_id != "" else "warrior", at)


@rpc("any_peer")
func sync_world_time(t: float) -> void:
	if multiplayer.is_server():
		return
	# The clock is monotone: a late packet never rewinds it.
	if t > Dungeon.world_time:
		Dungeon.world_time = t


# --- MP run saving (issue #238) ---
#
# The world scene's resident saver: the exact call the HUD's
# save-and-quit already makes on the station/dungeon savers. The
# collection protocol mirrors Dungeon.save_multiplayer_run; every
# piece of the loss-prevention discipline is a CALL to the shared
# Dungeon statics (bind_submitted_state / find_roster_entry /
# carry_forward_roster), never a copy that can diverge (#112).
#
# C-1 fence: a presence replica's get_state() is NEVER read for a
# save — replica state is a near-fresh character and writing it
# would permanently destroy that player's earned progression.
# Client states arrive only through the collection protocol
# below (each client's WorldRoot answers from its own local
# player); a peer that misses the window is carried forward from
# the previous save or written with an empty state.

func save_multiplayer_run(theme_id: String, level_number: int,
		level_seed: int) -> void:
	if not multiplayer.is_server():
		return
	if NetworkManager.transport == NetworkManager.Transport.LAN:
		return  # Issue #70: LAN sessions have no saves.
	_save_slot = NetworkManager.active_run_slot
	# Loaded-dict-first (issue #111 PF2), then stamp — the dungeon
	# saver's composition with the world's values (design §3.2).
	# theme/level/seed are the snapshot's CARRIED values (the HUD
	# passes them in); wave is carried by the loaded dict itself
	# and written back unchanged — the street has no wave to step
	# back.
	_save_base = SaveManager.load_run(SaveManager.MODE_MP, _save_slot)
	if _save_base == null:
		_save_base = {}
	_save_base["theme_id"] = theme_id
	_save_base["level_number"] = level_number
	_save_base["seed"] = level_seed
	_save_base["is_multiplayer"] = true
	_save_base["at_station"] = false
	# Issue #242 (§4): the identity block stamps from statics
	# only when the session is ENGAGED — a real world session
	# always is (context "world"; revealed for any post-reveal
	# run). In a never-engaged session (the pre-#242 broken
	# continue's spawn: context "" and unrevealed) the statics
	# are script defaults holding no truth, and stamping them
	# wiped the file's reveal/axis identity while its act2
	# survived. Unengaged: the loaded dict's values stand.
	if Dungeon.act2_context != "" or Dungeon.revealed:
		_save_base["act1_step"] = Dungeon.act1_step
		_save_base["vault_return_theme"] \
			= Dungeon.vault_return_theme
		_save_base["revealed"] = Dungeon.revealed
		_save_base["buildings_cleared"] \
			= Dungeon.buildings_cleared
		_save_base["home_anchor"] = Dungeon.home_anchor
	# The act2 stamp rides the SAME write as the roster (design
	# §4): act2_record() samples every player's street position
	# live, here in the world scene (issue #237).
	if Dungeon.act2_context != "":
		_save_base["act2"] = Dungeon.act2_record()
		_save_base["world_time"] = Dungeon.world_time
	_save_base["host_difficulty"] = NetworkManager.host_difficulty
	_save_base["host_loot_mult"] = NetworkManager.host_loot_mult
	var lobby_name := ("%s's Dungeon" % SteamManager.persona_name) \
		if SteamManager.initialized else "Dungeon"
	_save_base["lobby"] = {
		"max_players": NetworkManager.MAX_PLAYERS,
		"lobby_name": lobby_name,
		"visibility": NetworkManager.lobby_visibility,
	}
	_save_roster.clear()
	if _local_player != null:
		# The host's OWN player node — real state (never a replica).
		var my_sid := SteamManager.steam_id \
			if SteamManager.initialized \
			else multiplayer.get_unique_id()
		_save_roster.append({
			"steam_id": my_sid,
			"player_name": NetworkManager.member_name(my_sid),
			"class_id": str(_local_player.get("class_id")),
			"player_state": _local_player.get_state(),
			"rts_faction": -1,
			"is_host": true,
		})
	_save_pending.clear()
	for pid in multiplayer.get_peers():
		_save_pending[pid] = true
	if not _save_pending.is_empty():
		rpc("rpc_request_save_state", _save_slot)
		await get_tree().create_timer(
			Dungeon.SAVE_STATE_TIMEOUT).timeout
		_carry_missing_world_saves()
	_write_world_save()


## Peers that never answered the collection window: carry each
## one's previous roster entry forward verbatim (#105 C-1 — the
## entry is NEVER filled from the server-side presence replica;
## that state is a near-fresh character). A peer with no previous
## entry is written with an empty player_state and its real class
## (the class rides the presence hello — an identity fact, not
## state).
func _carry_missing_world_saves() -> void:
	if _save_pending.is_empty():
		return
	var previous := SaveManager.load_run(
		SaveManager.MODE_MP, _save_slot)
	var prev_roster: Array = previous.get("roster", [])
	for pid in _save_pending.keys():
		var sid := int(NetworkManager.peer_steam_ids.get(pid, pid))
		var prev := Dungeon.find_roster_entry(prev_roster, sid)
		if not prev.is_empty():
			_save_roster.append(prev)
		else:
			var cls := "warrior"
			var rep = _presence.get(pid)
			if rep != null:
				cls = str(rep.get("class_id"))
			_save_roster.append({
				"steam_id": sid,
				"player_name": NetworkManager.member_name(sid),
				"class_id": cls,
				"player_state": {},
				"rts_faction": -1,
				"is_host": false,
			})
	_save_pending.clear()


func _write_world_save() -> void:
	# Issue #109 (M-4): merge the previous roster in before
	# writing — a member absent from this session entirely must
	# survive the save untouched.
	var previous := SaveManager.load_run(
		SaveManager.MODE_MP, _save_slot)
	var prev_roster: Array = previous.get("roster", [])
	_save_roster = Dungeon.carry_forward_roster(
		_save_roster, prev_roster)
	# Issue #111 (PF2): an entry this build doesn't know about
	# keeps its unknown keys — merge previous-under-current per
	# Steam ID, as the dungeon saver's write does.
	var prev_by_sid := {}
	for e in prev_roster:
		if e is Dictionary:
			prev_by_sid[int(e.get("steam_id", 0))] = e
	for i in _save_roster.size():
		var entry: Dictionary = _save_roster[i]
		var prev: Dictionary = prev_by_sid.get(
			int(entry.get("steam_id", 0)), {})
		if not prev.is_empty():
			var merged := prev.duplicate()
			for k in entry.keys():
				merged[k] = entry[k]
			_save_roster[i] = merged
	_save_base["roster"] = _save_roster
	if not _save_roster.is_empty():
		_save_base["class_id"] = str(
			_save_roster[0].get("class_id", ""))
		_save_base["player_state"] = (
			_save_roster[0].get("player_state", {}) as Dictionary
			).duplicate(true)
	SaveManager.save_run(_save_base, SaveManager.MODE_MP, _save_slot)


@rpc("any_peer", "call_local")
func rpc_request_save_state(slot_index: int) -> void:
	if multiplayer.is_server():
		return
	if _local_player == null:
		return
	var state := {
		# The real Steam64 ID, not the peer ID (peer IDs are
		# session-scoped; Steam IDs persist across sessions).
		"steam_id": SteamManager.steam_id \
			if SteamManager.initialized \
			else multiplayer.get_unique_id(),
		"player_name": SteamManager.persona_name \
			if SteamManager.initialized else "Player",
		"class_id": str(_local_player.get("class_id")),
		"player_state": _local_player.get_state(),
		"rts_faction": -1,
		"is_host": false,
	}
	rpc_id(NetworkManager.server_peer_id,
		"rpc_submit_save_state", state, slot_index)


@rpc("any_peer")
func rpc_submit_save_state(state: Dictionary, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	if slot_index != _save_slot:
		return  # stale response from an earlier save; ignore
	var sender := multiplayer.get_remote_sender_id()
	if not _save_pending.has(sender):
		return
	# Issue #108 (M-3): the claimed steam_id is never trusted —
	# bind the submission to the sender's Steam64 from the
	# server's own register-time mapping, and reject senders with
	# no server-assigned identity.
	var bound := Dungeon.bind_submitted_state(
		state, sender, NetworkManager.peer_steam_ids)
	if bound.is_empty():
		return
	_save_pending.erase(sender)
	var sid := int(bound["steam_id"])
	# One sender = one roster entry: a resubmission replaces only
	# the sender's own entry, never another player's.
	for i in range(_save_roster.size() - 1, -1, -1):
		if int(_save_roster[i].get("steam_id", 0)) == sid:
			_save_roster.remove_at(i)
	_save_roster.append(bound)


func _on_local_died() -> void:
	_respawn_in = 2.5
	if _local_hud != null and _local_hud.has_method("announce"):
		_local_hud.announce(
			"You died. You wake at the doorstep.")


func _respawn_local() -> void:
	var p := _local_player
	if p == null:
		return
	var anchor := Dungeon.act2_anchor_doorstep
	anchor.y = WorldGen.height_at(WorldGen.WORLD_SEED,
		anchor.x, anchor.z) + 0.4
	p.position = anchor
	p.velocity = Vector3.ZERO
	p.downed = false
	p.alive = true
	p.hp = p.max_hp
	p.health_changed.emit(p.hp, p.max_hp)


func _process(delta: float) -> void:
	# The clock: server-advanced, locally presented.
	if multiplayer.is_server():
		Dungeon.world_time += delta
		_sync_t += delta
		if _sync_t >= CLOCK_SYNC_EVERY_S \
				and multiplayer.multiplayer_peer != null:
			_sync_t = 0.0
			rpc("sync_world_time", Dungeon.world_time)
		_save_t += delta
		if _save_t >= CLOCK_SAVE_EVERY_S:
			_save_t = 0.0
			Dungeon.save_act2_clock()
	_clock_t += delta
	if _clock_t >= 0.25:
		_clock_t = 0.0
		_apply_clock()
	# The ready-gate.
	if _started and not _gate_open:
		if _entry_ring_ready() or Time.get_ticks_msec() \
				/ 1000.0 >= _gate_deadline:
			_gate_open = true
			var tw := create_tween()
			tw.tween_property(_fade, "color",
				Color(0, 0, 0, 0), 0.8)
	if _respawn_in > 0.0:
		_respawn_in -= delta
		if _respawn_in <= 0.0:
			_respawn_local()


## The gate's predicate: the inner chunk ring (terrain +
## buildings + scatter) around the spawn is fully built.
func _entry_ring_ready() -> bool:
	if _streamer == null:
		return true
	var scx := int(floor(_spawn_point.x / WorldGen.CHUNK_SIZE))
	var scz := int(floor(_spawn_point.z / WorldGen.CHUNK_SIZE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if not bool(_streamer.call("chunk_fully_built",
					scx + dx, scz + dz)):
				return false
	return true


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_curve = 0.09
	_sky_mat.ground_curve = 0.02
	_sky_mat.sun_angle_max = 30.0
	sky.sky_material = _sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	_env = env
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	add_child(_sun)
	_apply_clock()


## All presentation derives from world_time through the P2
## parameter mechanism (WorldClock's keyframes over the same
## sky / sun / fog fields the level themes carry).
func _apply_clock() -> void:
	if _env == null:
		return
	var p := WorldClock.params_at(Dungeon.world_time)
	_sky_mat.sky_top_color = p["sky_top_color"]
	_sky_mat.sky_horizon_color = p["sky_horizon_color"]
	_sky_mat.ground_bottom_color = (p["ground_color"]
		as Color).darkened(0.4)
	_sky_mat.ground_horizon_color = p["ground_color"]
	_sky_mat.sky_energy_multiplier = float(
		p["sky_energy_multiplier"])
	_env.ambient_light_color = p["ambient_color"]
	_env.ambient_light_energy = float(p["ambient_energy"])
	_env.fog_light_color = p["fog_color"]
	_env.fog_density = float(p["fog_density"])
	_env.fog_sky_affect = float(p["fog_sky_affect"])
	_sun.light_color = p["sun_color"]
	_sun.light_energy = float(p["sun_energy"])
	var dir := (p["sun_direction"] as Vector3).normalized()
	_sun.rotation = Vector3(asin(clampf(-dir.y, -1.0, 1.0)),
		atan2(-dir.x, -dir.z), 0.0)
