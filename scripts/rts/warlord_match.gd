class_name WarlordMatch
extends Node3D
## Standalone Warlord match controller (issue #266 P1).
##
## Owns the match scene: terrain from the picked map, the RTSManager
## (with match_host = this node), the presentation stack (camera, HUD,
## season manager, unit renderer), faction registration, base/node
## spawning, the match clock, the winner/draw end, and the results
## screen. It never calls into dungeon.gd, the reveal, act context, or
## the dungeon save/continue flow (spec §2.3) — the dungeon loop's
## Warlord's Domain is a separate consumer of the same RTS baseplate.
##
## Host surface (mirror of the dungeon's, scoped to the match):
## spawn_rts_base, spawn_rts_node, rpc_start_construction,
## client_spawn_building, client_sync_building_state,
## _spawn_building_local, _is_valid_build_spot, is_on_water,
## ground_height_at, _random_land_pos, _nearest_resource,
## _wire_building, _class_from_civ, register_match_class,
## client_setup_warlord_match, sync_warlord_state,
## client_sync_warlord_faction, client_show_results.
## The RTS stack resolves its host through RTSManager.match_host —
## this node — so _spawn_unit_local, AI _order_build, camera
## placement, the unit clamp, and water queries all work here
## without any group-"dungeon" node on the scene.

const WARLORD_SETUP_TIMEOUT_MSEC := 15000
const MATCH_SCENE_MENU := "res://scenes/ui/main_menu.tscn"
const MATCH_SCENE_EDITOR := "res://scenes/rts/warlord_editor.tscn"
const AI_CLASSES: Array[String] = ["warrior", "rogue", "mage"]

var _map: Dictionary = {}
var _terrain: ZonesTerrain = null
var _rts_holder: Node3D = null
var _rts_manager: RTSManager = null
var _camera: RTSCamera = null
var _hud: RTSHUD = null
var _season_manager: Node = null
var _results_screen: WarlordResults = null

var _faction_count: int = 4
var _ai_fill: bool = true
## Issue #266 P2: true when this match is the editor's solo-skirmish
## playtest — teardown returns to the editor scene (the map is
## stashed in NM), and an Exit Playtest button rides the match.
var _playtest := false
var _rng := RandomNumberGenerator.new()
var _local_faction: int = -1

var _setup_pending := false
var _setup_wait_started_msec := 0
var _setup_complete := false
var _peer_classes: Dictionary = {}
var _human_factions: Array[int] = []
var _match_started := false
var _results_shown := false


func _ready() -> void:
	var nm: Node = get_tree().root.get_node_or_null("NetworkManager")
	if nm != null:
		_map = nm.get("warlord_map") as Dictionary
		_faction_count = int(nm.get("warlord_faction_count"))
		_ai_fill = bool(nm.get("warlord_ai_fill"))
		_playtest = bool(nm.get("warlord_editor_playtest"))
	if _playtest:
		# A playtest match may never end (the AI cannot reach the
		# human on a disconnected map) — the exit must not wait for
		# the results screen.
		var layer := CanvasLayer.new()
		layer.layer = 45
		add_child(layer)
		var exit_btn := Button.new()
		exit_btn.text = "Exit Playtest"
		exit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		exit_btn.position = Vector2(-150, 40)
		exit_btn.pressed.connect(quit_to_menu)
		layer.add_child(exit_btn)
	if _map.is_empty():
		_map = WarlordMap.standard_map()
	if _map.is_empty():
		push_error("[Warlord] no map data — cannot build the match scene")
		return
	_rng.seed = int(_map.get("seed", 5505))
	# Terrain from the picked map.
	_terrain = WarlordMap.build_terrain(_map)
	add_child(_terrain)
	_terrain.generate()
	# RTS holder + manager. match_host = this node: the whole RTS
	# stack resolves its host through it (gate-confirmed seam).
	_rts_holder = Node3D.new()
	_rts_holder.name = "RTS"
	add_child(_rts_holder)
	_rts_manager = RTSManager.new()
	_rts_manager.name = "RTSManager"
	_rts_manager.match_host = self
	add_child(_rts_manager)
	_rts_manager.winner_declared.connect(_on_match_winner)
	var renderer := RTSUnitRenderer.new()
	renderer.name = "RTSUnitRenderer"
	add_child(renderer)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.is_server():
		_setup_pending = true
		_setup_wait_started_msec = Time.get_ticks_msec()
	else:
		# Tell the host our class; the host answers with
		# client_setup_warlord_match once factions are registered.
		var cls := "warrior"
		if nm != null:
			cls = str(nm.get("selected_class_id"))
		rpc_id(NetworkManager.server_peer_id, "register_match_class", cls)


func _process(delta: float) -> void:
	if _setup_pending and multiplayer.is_server():
		var peers := multiplayer.get_peers()
		var all_in := true
		for p in peers:
			if not _peer_classes.has(p):
				all_in = false
				break
		var waited := Time.get_ticks_msec() - _setup_wait_started_msec
		if all_in or waited >= WARLORD_SETUP_TIMEOUT_MSEC:
			_do_faction_setup()
	if _match_started and multiplayer.is_server() and not _results_shown:
		_rts_manager.match_clock_sec += delta
		if _all_factions_dead():
			_show_results(-1)


func _all_factions_dead() -> bool:
	if _rts_manager == null or _rts_manager.factions.is_empty():
		return false
	for fid in _rts_manager.factions:
		if bool(_rts_manager.factions[fid].get("alive", false)):
			return false
	return true


## Server: register factions in join order (host first, then sorted
## peers), fill with AI per the host's choice, spawn bases + clusters
## + map nodes, then start the match clock.
func _do_faction_setup() -> void:
	_setup_pending = false
	_setup_complete = true
	var peers := multiplayer.get_peers()
	peers.sort()
	var humans: Array[int] = [1]
	humans.append_array(peers)
	var human_count := humans.size()
	var ai_count := 0
	if _ai_fill:
		ai_count = maxi(0, _faction_count - human_count)
	var total := human_count + ai_count
	var nm: Node = get_tree().root.get_node_or_null("NetworkManager")
	var faction_ids: Array[int] = []
	for i in total:
		var fid := i
		var peer := -1
		var cls := "warrior"
		if i < human_count:
			peer = humans[i]
			if i == 0:
				if nm != null:
					cls = str(nm.get("selected_class_id"))
			else:
				cls = str(_peer_classes.get(peer, "warrior"))
			_human_factions.append(fid)
		else:
			cls = AI_CLASSES[_rng.randi() % AI_CLASSES.size()]
		# Registration follows the dungeon's register-then-place order
		# (WarlordSetup.spawn_pos is order-dependent). The returned
		# ring position is DISCARDED here: match bases sit at the
		# map's starts (spec §3.4), not on the dungeon's flat ring.
		WarlordSetup.register_and_place(_rts_manager, fid, peer, cls,
			WarlordSetup.map_scale_for(total))
		if peer == -1:
			var ai := AIWarlord.new()
			ai.faction_id = fid
			add_child(ai)
		faction_ids.append(fid)
	# Spawn bases + starting clusters + map nodes.
	var starts: Array = _map.get("starts", [])
	for fid in faction_ids:
		if fid >= starts.size():
			continue
		var s: Dictionary = starts[fid]
		var spos := Vector2((s["pos"] as Array)[0], (s["pos"] as Array)[1])
		var pos := Vector3(spos.x, ground_height_at(Vector3(spos.x, 0, spos.y)), spos.y)
		_spawn_faction_base(fid, pos)
	for node in _map.get("nodes", []):
		var n: Dictionary = node
		var npos2 := Vector2((n["pos"] as Array)[0], (n["pos"] as Array)[1])
		var npos := Vector3(npos2.x, ground_height_at(Vector3(npos2.x, 0, npos2.y)), npos2.y)
		rpc("spawn_rts_node", str(n.get("type", "wood")), npos,
			_rts_manager.alloc_node_id(), int(n.get("amount", -1)))
	# Tell each client its faction, then replay the match state.
	for i in human_count:
		var peer := humans[i]
		if peer == 1:
			continue
		var fid := i
		var civ: CivData = _rts_manager.get_civ(fid)
		rpc_id(peer, "client_setup_warlord_match", fid, civ.civ_id)
	_setup_local_presentation(0)
	_rts_manager.match_begin(faction_ids)
	_match_started = true
	for i in human_count:
		var peer := humans[i]
		if peer == 1:
			continue
		sync_warlord_state(peer)


## Server: spawn one faction's base (town hall + 3 villagers) and its
## guaranteed starting cluster, mirroring dungeon._spawn_faction_base.
func _spawn_faction_base(faction_id: int, pos: Vector3) -> void:
	var civ := _rts_manager.get_civ(faction_id)
	var town_hall_id := _rts_manager.alloc_building_id()
	var villager_ids := [_rts_manager.alloc_unit_id(), _rts_manager.alloc_unit_id(), _rts_manager.alloc_unit_id()]
	rpc("spawn_rts_base", faction_id, pos, civ.civ_id, town_hall_id, villager_ids)
	for entry in WarlordSetup.starting_cluster_positions(pos, _rng, Callable(self, "is_on_water")):
		var e: Dictionary = entry
		var npos: Vector3 = e["pos"]
		npos.y = ground_height_at(npos)
		rpc("spawn_rts_node", str(e["type"]), npos, _rts_manager.alloc_node_id())


## Local presentation stack (camera + HUD + season manager), built
## once the local faction is known. The camera starts ACTIVE at the
## map centre (there is no FPS player to toggle from); units read the
## camera's active flag at spawn and orient their sprites flat.
func _setup_local_presentation(local_faction: int) -> void:
	_local_faction = local_faction
	_season_manager = load("res://scripts/rts/season_manager.gd").new()
	_season_manager.name = "SeasonManager"
	add_child(_season_manager)
	_season_manager.setup(_rts_manager, self)
	if multiplayer.is_server():
		_season_manager.start()
	_camera = RTSCamera.new()
	_camera.name = "RTSCamera"
	_camera.add_to_group("rts_camera")
	add_child(_camera)
	_camera.setup(_rts_manager, local_faction)
	_camera.active = true
	_camera.current = true
	_camera.position = Vector3(0, 40.0, 0)
	_camera.rotation = Vector3(-PI / 2, 0, 0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud = RTSHUD.new()
	_hud.name = "RTSHUD"
	# rts_army_sandbox precedent: the RTS HUD joins group "hud" so the
	# camera's drag box has a parent (there is no player HUD here).
	_hud.add_to_group("hud")
	add_child(_hud)
	_hud.setup(_rts_manager, local_faction)
	_hud.show_guide()
	if _season_manager != null:
		_hud.set_season_manager(_season_manager)


# --- Host surface (mirror of the dungeon's, scoped to the match) ---

@rpc("any_peer", "call_local")
func spawn_rts_base(faction_id: int, pos: Vector3, civ_id: String, building_id: int, villager_ids: Array) -> void:
	var civ := CivData.for_class(_class_from_civ(civ_id))
	var th := RTSBuilding.new()
	th.setup(faction_id, "town_hall", civ)
	th.building_id = building_id
	th.name = "RTSBuilding_%d" % building_id
	th.position = pos
	_rts_holder.add_child(th)
	_wire_building(th, faction_id)
	var villagers: Array = []
	for i in 3:
		var v := RTSUnit.new()
		v.setup(faction_id, "villager", civ)
		var vid := int(villager_ids[i]) if i < villager_ids.size() else 0
		v.unit_id = vid
		v.name = "RTSUnit_%d" % vid
		var angle := TAU * float(i) / 3.0
		var vpos := pos + Vector3(cos(angle) * 3.0, 0, sin(angle) * 3.0)
		vpos.y = ground_height_at(vpos)
		v.position = vpos
		_rts_holder.add_child(v)
		villagers.append(v)
	if multiplayer.is_server() and _rts_manager != null:
		if int(_rts_manager.faction_peers.get(faction_id, -2)) == -1:  # AI faction
			for v in villagers:
				var node := _nearest_resource(v.position)
				if node != null:
					v.order_gather(node)


@rpc("any_peer", "call_local")
func spawn_rts_node(res_type: String, pos: Vector3, node_id: int, amount: int = -1) -> void:
	var amounts := RTSTuning.get_dict("map", "node_amounts",
		{"wood": 1000, "food": 800, "gold": 800, "stone": 800})
	var node := RTSResourceNode.new()
	node.setup(res_type, amount if amount > 0 else int(amounts.get(res_type, 500)))
	node.node_id = node_id
	node.name = "RTSNode_%d" % node_id
	node.position = pos
	node.add_to_group("rts_resources")
	_rts_holder.add_child(node)


## Server-side: start construction of a building at a position.
## Mirrors dungeon.rpc_start_construction exactly (cost, age gate,
## spot validation, spend, builders from the selection, refund on an
## empty builder list).
@rpc("any_peer", "call_local")
func rpc_start_construction(faction_id: int, btype: String, pos: Vector3, builder_paths: Array = []) -> void:
	if not multiplayer.is_server():
		return
	if _rts_manager == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		var owner := int(_rts_manager.faction_peers.get(faction_id, -2))
		if owner != sender and owner != -1:
			return
	var cost: Dictionary = RTSTuning.get_cost("building_costs", btype, RTSManager.BUILDING_COSTS.get(btype, {}))
	if cost.is_empty():
		return
	var age_req := 1 if btype in ["siege_workshop", "monastery"] else 0
	if _rts_manager.get_age(faction_id) < age_req:
		return
	if not _is_valid_build_spot(pos):
		return
	if not _rts_manager.spend(faction_id, cost):
		return
	var builders: Array[Node3D] = []
	for p in builder_paths:
		var u := get_node_or_null(p) as Node3D
		if u != null and is_instance_valid(u) \
				and int(u.get("faction")) == faction_id \
				and str(u.get("unit_type")) == "villager":
			builders.append(u)
	if builders.is_empty():
		for k in cost:  # refund
			_rts_manager.add_resource(faction_id, k, int(cost[k]))
		return
	var civ: CivData = _rts_manager.factions[faction_id]["civ"]
	var bid := _rts_manager.alloc_building_id()
	var b := _spawn_building_local(faction_id, btype, pos, civ.civ_id, bid)
	rpc("client_spawn_building", faction_id, btype, pos, civ.civ_id, bid)
	for builder in builders:
		builder.rpc("rpc_order_build", b.get_path())


@rpc("any_peer", "call_local")
func client_spawn_building(faction_id: int, btype: String, pos: Vector3, civ_id: String, building_id: int) -> void:
	if multiplayer.is_server():
		return
	_spawn_building_local(faction_id, btype, pos, civ_id, building_id)


@rpc("any_peer")
func client_sync_building_state(building_id: int, new_hp: float, new_progress: float, new_under: bool) -> void:
	# Same D7 server-origin rule as the dungeon's: only the server
	# (or the local path, sender 0) may set a building's state.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_peer_id:
		push_warning("[D7] refused forged building state for %d from peer %d" % [building_id, sender])
		return
	var b := get_node_or_null("RTS/RTSBuilding_%d" % building_id) as RTSBuilding
	if b == null:
		return
	b.apply_build_state(new_hp, new_progress, new_under)


func _spawn_building_local(faction_id: int, btype: String, pos: Vector3, civ_id: String, building_id: int) -> RTSBuilding:
	var civ := CivData.for_civ_id(civ_id)
	var b := RTSBuilding.new()
	b.setup(faction_id, btype, civ)
	b.building_id = building_id
	b.name = "RTSBuilding_%d" % building_id
	b.rts_manager = _rts_manager
	var bpos := pos
	bpos.y = ground_height_at(bpos)
	b.position = bpos
	_rts_holder.add_child(b)
	b.start_construction()
	return b


## Server-side build spot validation: spacing from other buildings, not on water.
func _is_valid_build_spot(pos: Vector3) -> bool:
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if pos.distance_to(b.global_position) < 5.0:
			return false
	if is_on_water(pos):
		return false
	return true


## Water test for the match: the built terrain's is_water (ponds are
## the only water on a v1 map — base noise never dips below the water
## level). Falls back to the map's pond circles before the terrain
## exists.
func is_on_water(pos: Vector3) -> bool:
	if _terrain != null:
		return _terrain.is_water(pos)
	return WarlordMap.is_pond_water(_map, pos)


func ground_height_at(pos: Vector3) -> float:
	if _terrain != null:
		return _terrain.get_ground_height(pos)
	return 0.0


## Random land position (mirror of dungeon._random_land_pos): 20
## attempts rejecting water, fallback radius 20. Used by the season
## manager (Gold Rush centre ring) via has_method.
func _random_land_pos(min_r: float, max_r: float) -> Vector3:
	for i in 20:
		var angle := randf() * TAU
		var dist := min_r + randf() * (max_r - min_r)
		var pos := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		if not is_on_water(pos):
			return pos
	var a2 := randf() * TAU
	return Vector3(cos(a2) * 20.0, 0, sin(a2) * 20.0)


func _nearest_resource(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 9999.0
	for n in get_tree().get_nodes_in_group("rts_resources"):
		var d: float = pos.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _wire_building(b: RTSBuilding, faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	var mgr := get_tree().get_first_node_in_group("rts_manager")
	b.rts_manager = mgr
	if _rts_manager != null:
		b.knights_unlocked = _rts_manager.get_age(faction_id) >= 1


func _class_from_civ(civ_id: String) -> String:
	match civ_id:
		"iron_vanguard":
			return "warrior"
		"shadow_covenant":
			return "rogue"
		"arcane_dominion":
			return "mage"
	return "warrior"


# --- Class handshake + late join ---

@rpc("any_peer")
func register_match_class(class_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_peer_classes[sender] = class_id
	if _setup_complete and _match_started:
		_assign_late_joiner(sender, class_id)


func _assign_late_joiner(peer: int, class_id: String) -> void:
	# A departed human's faction stands driverless: a late joiner
	# reclaims it. Otherwise a fresh faction while starts remain.
	for fid in _human_factions:
		if int(_rts_manager.faction_peers.get(fid, -2)) == -1:
			_rts_manager.faction_peers[fid] = peer
			var civ: CivData = _rts_manager.get_civ(fid)
			rpc_id(peer, "client_setup_warlord_match", fid, civ.civ_id)
			sync_warlord_state(peer)
			return
	if _rts_manager.factions.size() < _faction_count:
		var fid := _rts_manager.factions.size()
		WarlordSetup.register_and_place(_rts_manager, fid, peer, class_id,
			WarlordSetup.map_scale_for(_faction_count))
		_human_factions.append(fid)
		var starts: Array = _map.get("starts", [])
		if fid < starts.size():
			var s: Dictionary = starts[fid]
			var spos := Vector2((s["pos"] as Array)[0], (s["pos"] as Array)[1])
			var pos := Vector3(spos.x, ground_height_at(Vector3(spos.x, 0, spos.y)), spos.y)
			_spawn_faction_base(fid, pos)
		var civ2: CivData = _rts_manager.get_civ(fid)
		rpc_id(peer, "client_setup_warlord_match", fid, civ2.civ_id)
		sync_warlord_state(peer)
	# No faction available: the client stays without one (no
	# client_setup_warlord_match sent). No new rule is invented in v1.


@rpc("any_peer", "call_local")
func client_setup_warlord_match(my_faction: int, my_civ_id: String) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != NetworkManager.server_peer_id:
		return
	var class_id := _class_from_civ(my_civ_id)
	_rts_manager.register_faction(my_faction, multiplayer.get_unique_id(), class_id)
	_setup_complete = true
	_setup_local_presentation(my_faction)


# --- State sync (D2-correct: unit replays go through the MANAGER node) ---

func sync_warlord_state(target_peer: int) -> void:
	if _rts_manager == null:
		return
	for fid in _rts_manager.factions:
		var fi := int(fid)
		var f: Dictionary = _rts_manager.factions[fi]
		var res: Dictionary = f.get("resources", {})
		var civ: CivData = f.get("civ")
		rpc_id(target_peer, "client_sync_warlord_faction", fi,
			_rts_manager.faction_peers.get(fi, -1),
			civ.civ_id if civ else "iron_vanguard",
			int(res.get("wood", 0)), int(res.get("food", 0)),
			int(res.get("gold", 0)), int(res.get("stone", 0)),
			int(f.get("age", 0)))
	for u in get_tree().get_nodes_in_group("rts_units"):
		var uciv: CivData = u.get("civ")
		_rts_manager.rpc_id(target_peer, "client_spawn_unit",
			str(u.get("unit_type")), int(u.get("faction")),
			u.global_position, uciv.civ_id if uciv else "iron_vanguard",
			int(u.get("unit_id")))
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		var bciv: CivData = b.get("civ")
		rpc_id(target_peer, "client_spawn_building",
			int(b.get("faction")), str(b.get("building_type")),
			b.global_position, bciv.civ_id if bciv else "iron_vanguard",
			int(b.get("building_id")))
		rpc_id(target_peer, "client_sync_building_state",
			int(b.get("building_id")), float(b.get("hp")),
			float(b.get("build_progress")),
			bool(b.get("under_construction")))
	# The match DOES re-send resource nodes (the dungeon's D2 gap):
	# nodes are explicit map placements, and a late joiner needs them
	# at their current amounts.
	for n in get_tree().get_nodes_in_group("rts_resources"):
		var raw_amt = n.get("amount")
		var amt := int(raw_amt) if raw_amt != null else 500
		rpc_id(target_peer, "spawn_rts_node",
			str(n.get("resource_type")), n.global_position,
			int(n.get("node_id")), amt)


@rpc("any_peer", "call_local")
func client_sync_warlord_faction(faction_id: int, peer_id: int, civ_id: String, wood: int, food: int, gold: int, stone: int, age: int) -> void:
	if multiplayer.is_server():
		return
	if _rts_manager == null:
		return
	if not _rts_manager.factions.has(faction_id):
		_rts_manager.register_faction(faction_id, peer_id, _class_from_civ(civ_id))
	var f: Dictionary = _rts_manager.factions[faction_id]
	f["resources"] = {"wood": wood, "food": food, "gold": gold, "stone": stone}
	f["age"] = age
	_rts_manager.resources_changed.emit(faction_id)


# --- End of match + teardown ---

func _on_match_winner(winner_faction: int) -> void:
	if not multiplayer.is_server():
		return
	if _results_shown:
		return
	_show_results(winner_faction)


## Host computes the results and broadcasts them; every peer
## (including the host, via call_local) opens the results screen.
## winner -1 is the mutual-wipe draw line — never an invented winner.
func _show_results(winner_faction: int) -> void:
	if _rts_manager == null:
		return
	var results: Dictionary = _rts_manager.match_results(winner_faction)
	rpc("client_show_results", results)


@rpc("any_peer", "call_local")
func client_show_results(results: Dictionary) -> void:
	if _results_shown:
		return
	_results_shown = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _results_screen != null and is_instance_valid(_results_screen):
		return
	_results_screen = load("res://scripts/rts/warlord_results.gd").new()
	_results_screen.playtest_mode = _playtest
	add_child(_results_screen)
	_results_screen.setup(results, self)


func return_to_lobby() -> void:
	if _playtest:
		_return_to_editor()
		return
	var nm: Node = get_tree().root.get_node_or_null("NetworkManager")
	if nm != null:
		nm.set("return_to_lobby", true)
	get_tree().change_scene_to_file(MATCH_SCENE_MENU)


func quit_to_menu() -> void:
	if _playtest:
		_return_to_editor()
		return
	var nm: Node = get_tree().root.get_node_or_null("NetworkManager")
	if nm != null:
		nm.call("leave_lobby")
	get_tree().change_scene_to_file(MATCH_SCENE_MENU)


## Issue #266 P2: a playtest has no lobby — both exits return to the
## editor, which restores the stashed map as it was. The flag clears
## so a later real match never inherits the editor return.
func _return_to_editor() -> void:
	var nm: Node = get_tree().root.get_node_or_null("NetworkManager")
	if nm != null:
		nm.set("warlord_editor_playtest", false)
	get_tree().change_scene_to_file(MATCH_SCENE_EDITOR)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_peer_classes.erase(peer_id)
	if _rts_manager == null:
		return
	# A departed human's faction stands driverless (ownerless, peer
	# -1, no AIWarlord spawned) — the mode does NOT auto-AI it (v1).
	for fid in _rts_manager.factions:
		if int(_rts_manager.faction_peers.get(fid, -2)) == peer_id:
			_rts_manager.faction_peers[fid] = -1
