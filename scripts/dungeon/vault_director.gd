extends Node
## Issue #185 (Mason's Vault P2): the vault's mechanism brain,
## on the FishingDirector precedent — one director child of the
## dungeon, server-authoritative state, replicated via its own
## sync RPCs on DISCRETE changes only (an interact, a wake, a
## door opening); nothing syncs per frame.
##
## Content is keyed from the CipherPoems rows: every mechanism's
## def (authored in VaultLayout) carries only a poem INDEX; the
## words, ciphers and shifts are read from CipherPoems.POEMS at
## the point of use. No second copy of them exists in the vault.
##
## Trust model (the house pattern): requests carry no peer id —
## the server attributes via get_remote_sender_id(); the local
## server path (solo / the host's own press) uses the unique id.
## Mechanism visuals live in VaultMechanism nodes registered
## here identically on every peer; this node owns only state.

## PLACEHOLDER damage for a wrong pressure plate (Jesse tunes
## at P4). Dealt through the player's (float, String) funnel.
const TRAP_DAMAGE := 10.0
const TRAP_SOURCE := "Stone Trap"

var defs: Dictionary = {}   # key -> authored def (identical on all peers)
var nodes: Dictionary = {}  # key -> VaultMechanism node (local visuals)

# --- State: written on the server, mirrored everywhere by sync.
var door_open: Dictionary = {}     # door key -> bool
var wheel_state: Dictionary = {}   # wheel key -> {"pos": int, "spins": int}
var item_state: Dictionary = {}    # item key -> {"mode": String, "by": int}
var carried_by: Dictionary = {}    # peer -> item key
var wstone_on_pan: Dictionary = {} # weigh stone key -> bool
var plate_next: Dictionary = {}    # plates family key -> next step (1-based)
var statue_woken: Dictionary = {}  # statue key -> bool
var wake_latched: Dictionary = {}  # chamber key -> bool
var treasure_open := false         # P3 rite drives this (seam below)


func _ready() -> void:
	add_to_group("vault_director")


# --- Registration (VaultLayout, identical on every peer) ---

func register_mechanism(key: String, p_def: Dictionary, node: Node) -> void:
	defs[key] = p_def
	nodes[key] = node
	match str(p_def.get("kind", "")):
		"wheel":
			wheel_state[key] = {"pos": 0, "spins": 0}
		"door", "door_try":
			door_open[key] = false
		"tablet", "stone":
			item_state[key] = {"mode": "pedestal", "by": 0}
		"wstone":
			wstone_on_pan[key] = false
		"plate":
			var fam := str(p_def.get("plates", ""))
			if not plate_next.has(fam):
				plate_next[fam] = 1
		"statue":
			statue_woken[key] = false


## Server only, called once by VaultLayout after registration:
## chambers whose sentries are LIVE from the start (the patrolled
## carry room) spawn through the dungeon's standard mob path.
func spawn_live_sentries(dungeon: Node) -> void:
	if not multiplayer.is_server():
		return
	for key in defs:
		var d: Dictionary = defs[key]
		if str(d.get("kind", "")) == "statue" and bool(d.get("live", false)):
			statue_woken[key] = true
			_sync(key)
			dungeon.call("server_spawn_mob", str(d.get("mob", "stone_sentry")),
				(nodes[key] as Node3D).global_position)


# --- State composition (identical on server and clients) ---

func _poem(idx: int) -> Dictionary:
	return CipherPoems.POEMS[clampi(idx, 0, CipherPoems.POEMS.size() - 1)]


static func _decode(cipher: String, by: int) -> String:
	return CipherPoems.cipher_word(cipher, (26 - by % 26) % 26)


func _wheel_display(door_def: Dictionary) -> String:
	var poem := _poem(int(door_def.get("poem", 0)))
	var cipher := str(poem["cipher"])
	if door_def.has("wheels"):
		# Two wheels partition the letters: wheel A counter-shifts
		# the even-index letters, wheel B the odd-index ones.
		var ws: Array = door_def["wheels"]
		var pa := int((wheel_state.get(ws[0], {}) as Dictionary).get("pos", 0))
		var pb := int((wheel_state.get(ws[1], {}) as Dictionary).get("pos", 0))
		var out := ""
		for i in cipher.length():
			out += _decode(cipher[i], pa if i % 2 == 0 else pb)
		return out
	var pos := int((wheel_state.get(str(door_def.get("wheel", "")), {}) as Dictionary).get("pos", 0))
	return _decode(cipher, pos)


func _door_display(key: String) -> String:
	var d: Dictionary = defs.get(key, {})
	if d.has("wheel") or d.has("wheels"):
		return _wheel_display(d)
	return ""


func mech_state(key: String) -> Dictionary:
	var d: Dictionary = defs.get(key, {})
	match str(d.get("kind", "")):
		"wheel":
			return {"pos": int((wheel_state.get(key, {}) as Dictionary).get("pos", 0))}
		"door":
			return {"open": bool(door_open.get(key, false)), "display": _door_display(key)}
		"door_try":
			return {"open": bool(door_open.get(key, false))}
		"tablet", "stone":
			return {"state": str((item_state.get(key, {}) as Dictionary).get("mode", "pedestal"))}
		"socket", "lsocket":
			var it: Dictionary = item_state.get(str(d.get("item", "")), {})
			return {"filled": str(it.get("mode", "")) == "socketed"}
		"wstone":
			return {"on_pan": bool(wstone_on_pan.get(key, false))}
		"plate":
			return {"rung": int(plate_next.get(str(d.get("plates", "")), 1)) > int(d.get("step", 0))}
		"statue":
			return {"woken": bool(statue_woken.get(key, false))}
	return {}


# --- Sync (server -> all, on discrete change) ---

func _sync(key: String) -> void:
	rpc("sync_mech", key, mech_state(key))


@rpc("authority", "call_local", "reliable")
func sync_mech(key: String, state: Dictionary) -> void:
	# Fold the incoming state into the mirror, then render.
	var d: Dictionary = defs.get(key, {})
	match str(d.get("kind", "")):
		"wheel":
			wheel_state[key] = {"pos": int(state.get("pos", 0)),
				"spins": int((wheel_state.get(key, {}) as Dictionary).get("spins", 0))}
		"door", "door_try":
			door_open[key] = bool(state.get("open", false))
		"tablet", "stone":
			var mode := str(state.get("state", "pedestal"))
			var by := int(state.get("by", 0))
			item_state[key] = {"mode": mode, "by": by}
			_update_carry_visual(key, mode, by)
		"wstone":
			wstone_on_pan[key] = bool(state.get("on_pan", false))
		"plate":
			if state.has("next"):
				plate_next[str(d.get("plates", ""))] = int(state["next"])
		"statue":
			statue_woken[key] = bool(state.get("woken", false))
	var n = nodes.get(key)
	if n != null and is_instance_valid(n):
		n.call("apply_state", mech_state(key))


@rpc("authority", "call_local", "reliable")
func sync_fx(sfx_name: String, pos: Vector3) -> void:
	AudioManager.sfx(sfx_name, pos)


## Item syncs carry the carrier so every peer can dress the
## carrying player (the tablet/stone world node hides meanwhile).
func _sync_item(key: String) -> void:
	var it: Dictionary = item_state.get(key, {"mode": "pedestal", "by": 0})
	rpc("sync_mech", key, {"state": str(it["mode"]), "by": int(it["by"])})


func _update_carry_visual(item_key: String, mode: String, by: int) -> void:
	# Remove any stale visual for this item, then re-dress.
	for p in get_tree().get_nodes_in_group("players"):
		var old = p.get_node_or_null("VaultCarried_%s" % item_key)
		if old != null:
			old.queue_free()
	if mode != "carried" or by == 0:
		return
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null or not dungeon.has_method("get_player_node"):
		return
	var player = dungeon.call("get_player_node", by)
	if player == null:
		return
	var d: Dictionary = defs.get(item_key, {})
	var slab := MeshInstance3D.new()
	slab.name = "VaultCarried_%s" % item_key
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.62, 0.12)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.40, 0.37)
	bm.material = m
	slab.mesh = bm
	slab.position = Vector3(0.42, 1.30, 0.28)
	player.add_child(slab)
	var l := Label3D.new()
	l.text = str(d.get("word", d.get("letter", "")))
	l.font_size = 40
	l.pixel_size = 0.004
	l.modulate = Color(0.92, 0.90, 0.84)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 0.45, 0)
	slab.add_child(l)


# --- Interact routing ---

func request_interact(key: String, player: Node) -> void:
	if multiplayer.is_server():
		_handle(key, multiplayer.get_unique_id())
	else:
		rpc_id(NetworkManager.server_peer_id, "rpc_vault_interact", key)


@rpc("any_peer", "call_remote", "reliable")
func rpc_vault_interact(key: String) -> void:
	if not multiplayer.is_server():
		return
	_handle(key, multiplayer.get_remote_sender_id())


func _chamber_door_open(d: Dictionary) -> bool:
	return bool(door_open.get(str(d.get("door", "")), false))


func _handle(key: String, sender: int) -> void:
	var d: Dictionary = defs.get(key, {})
	if d.is_empty():
		return
	match str(d.get("kind", "")):
		"wheel":
			_handle_wheel(key, d)
		"door":
			_handle_door(key, d)
		"door_try":
			_handle_door_try(key, d)
		"tablet", "stone":
			_handle_take(key, sender)
		"socket", "lsocket":
			_handle_place(key, d, sender)
		"wstone":
			_handle_weigh_stone(key, d)
		"plate":
			_handle_plate(key, d, sender)


func _open_door(door_key: String) -> void:
	if door_key == "" or bool(door_open.get(door_key, false)):
		return
	door_open[door_key] = true
	_sync(door_key)
	var n = nodes.get(door_key)
	if n != null and is_instance_valid(n):
		rpc("sync_fx", "train_door_open", (n as Node3D).global_position)


func _wake_chamber(chamber: String) -> void:
	if bool(wake_latched.get(chamber, false)):
		return
	wake_latched[chamber] = true
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	for key in defs:
		var d: Dictionary = defs[key]
		if str(d.get("kind", "")) != "statue" or str(d.get("chamber", "")) != chamber:
			continue
		if bool(statue_woken.get(key, false)):
			continue
		statue_woken[key] = true
		_sync(key)
		if dungeon != null:
			dungeon.call("server_spawn_mob", str(d.get("mob", "stone_sentry")),
				(nodes[key] as Node3D).global_position)


# --- WHEEL (poems 1, 4, 5) ---

func _handle_wheel(key: String, d: Dictionary) -> void:
	if _chamber_door_open(d):
		return
	var st: Dictionary = wheel_state.get(key, {"pos": 0, "spins": 0})
	st["spins"] = int(st["spins"]) + 1
	st["pos"] = (int(st["pos"]) + 1) % 26
	wheel_state[key] = st
	_sync(key)
	var door_key := str(d.get("door", ""))
	_sync(door_key)  # the door's letters move with the wheel
	var poem := _poem(int(d.get("poem", 0)))
	var door_def: Dictionary = defs.get(door_key, {})
	# The wake rule (citation-settled): cumulative rotations
	# REACHING shift + 26 with the door never opened wakes the
	# chamber. Checked independently of the display — at the
	# reaching spin the letters read the word again (a full
	# revolution later), and the wake still answers.
	if int(st["spins"]) >= int(poem["shift"]) + 26:
		_wake_chamber(str(d.get("chamber", "")))
	if _wheel_display(door_def) == str(poem["word"]):
		# The correct value: a soft chime — a cue, not a
		# confirmation. The door opens only when it is TRIED
		# (see _handle_door).
		var n = nodes.get(door_key)
		if n != null and is_instance_valid(n):
			rpc("sync_fx", "board_chime", (n as Node3D).global_position)


## Wheel doors are tried like any door: interacting the door
## opens it iff its letters currently read the decoded word.
## Any other reading refuses plainly — a locked clunk, no
## penalty, no wheel reset (testing is not forcing).
func _handle_door(key: String, d: Dictionary) -> void:
	if bool(door_open.get(key, false)):
		return
	var poem := _poem(int(d.get("poem", 0)))
	if _door_display(key) == str(poem["word"]):
		_open_door(key)
	else:
		rpc("sync_fx", "door_lock", (nodes[key] as Node3D).global_position)


# --- DOORS (poem 7): three lintels, one decodes to the word ---

func _handle_door_try(key: String, d: Dictionary) -> void:
	if bool(door_open.get(key, false)):
		return
	var poem := _poem(int(d.get("poem", 0)))
	if _decode(str(d.get("lintel", "")), int(poem["shift"])) == str(poem["word"]):
		_open_door(key)
	else:
		rpc("sync_fx", "door_lock", (nodes[key] as Node3D).global_position)
		_wake_chamber(str(d.get("chamber", "")))


# --- CARRY (poems 2, 8) ---

func _handle_take(key: String, sender: int) -> void:
	var it: Dictionary = item_state.get(key, {})
	if str(it.get("mode", "")) != "pedestal":
		return
	if carried_by.has(sender):
		return  # one at a time
	it["mode"] = "carried"
	it["by"] = sender
	item_state[key] = it
	carried_by[sender] = key
	_sync_item(key)


func _handle_place(key: String, d: Dictionary, sender: int) -> void:
	var item_key := str(d.get("item", ""))
	if str(carried_by.get(sender, "")) != item_key:
		# Wrong socket for what they carry (or empty hands):
		# a clunk, no penalty, nothing changes.
		if carried_by.has(sender):
			rpc("sync_fx", "door_lock", (nodes[key] as Node3D).global_position)
		return
	var it: Dictionary = item_state.get(item_key, {})
	it["mode"] = "socketed"
	it["by"] = 0
	item_state[item_key] = it
	carried_by.erase(sender)
	_sync_item(item_key)
	_sync(key)  # the socket shows its fill
	var door_key := str(d.get("door", ""))
	if door_key != "":
		var fam: Array = d.get("family", [item_key])
		var done := true
		for fk in fam:
			if str((item_state.get(str(fk), {}) as Dictionary).get("mode", "")) != "socketed":
				done = false
		if done:
			_open_door(door_key)


# --- WEIGH (poem 3): stones on the pan must sum to the shift ---

func _handle_weigh_stone(key: String, d: Dictionary) -> void:
	if _chamber_door_open(d):
		return
	wstone_on_pan[key] = not bool(wstone_on_pan.get(key, false))
	_sync(key)
	var poem := _poem(int(d.get("poem", 0)))
	var sum := 0
	for k in defs:
		var kd: Dictionary = defs[k]
		if str(kd.get("kind", "")) == "wstone" and str(kd.get("weigh", "")) == str(d.get("weigh", "")):
			if bool(wstone_on_pan.get(k, false)):
				sum += int(kd.get("weight", 0))
	if sum == int(poem["shift"]):
		_open_door(str(d.get("door", "")))


# --- PLATES (poem 6): the shown order, or the traps answer ---

func _handle_plate(key: String, d: Dictionary, sender: int) -> void:
	if _chamber_door_open(d):
		return
	var fam := str(d.get("plates", ""))
	var expected := int(plate_next.get(fam, 1))
	if int(d.get("step", 0)) == expected:
		plate_next[fam] = expected + 1
		# Sync the whole family (rung states + the counter).
		for k in defs:
			var kd: Dictionary = defs[k]
			if str(kd.get("kind", "")) == "plate" and str(kd.get("plates", "")) == fam:
				rpc("sync_mech", k, {"rung": int(plate_next[fam]) > int(kd.get("step", 0)), "next": int(plate_next[fam])})
		rpc("sync_fx", "board_chime", (nodes[key] as Node3D).global_position)
		if int(plate_next[fam]) > 8:
			_open_door(str(d.get("door", "")))
	else:
		# Wrong plate: the stone traps bite the stepper and the
		# sequence resets.
		plate_next[fam] = 1
		for k in defs:
			var kd: Dictionary = defs[k]
			if str(kd.get("kind", "")) == "plate" and str(kd.get("plates", "")) == fam:
				rpc("sync_mech", k, {"rung": false, "next": 1})
		var dungeon := get_tree().get_first_node_in_group("dungeon")
		if dungeon != null and dungeon.has_method("get_player_node"):
			var p = dungeon.call("get_player_node", sender)
			if p != null and p.has_method("take_damage"):
				p.call("take_damage", TRAP_DAMAGE, TRAP_SOURCE)
		rpc("sync_fx", "door_lock", (nodes[key] as Node3D).global_position)


# --- P3 seams (rite / treasure), present but unwired in P2 ---

## The rite (P3) opens the treasure chamber through here.
func set_treasure_open(open: bool) -> void:
	treasure_open = open
	if open:
		_open_door("treasure_door")
