class_name Dungeon
extends Node3D
## Procedural arena scene. The server picks a theme + seed; every peer runs
## ProcGen.generate() locally to build a byte-identical map, so only the
## seed (one int) crosses the network. Gameplay (waves, mobs, loot) stays
## server-authoritative exactly as before.
##
## Run handoff (set before change_scene_to_file):
##   next_theme_id / next_seed / next_level_number / saved_player_state

const PlayerScene := preload("res://scenes/player/player.tscn")
const MobScene := preload("res://scenes/mobs/mob.tscn")
const PickupScene := preload("res://scenes/items/item_pickup.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")

const MAX_CONCURRENT := 8
const TOTAL_WAVES := 5
const INTERMISSION_TIME := 10.0
const THEME_ORDER: Array[String] = ["village", "dungeon", "depths", "supermarket", "warlord"]

static var next_theme_id: String = "village"
static var next_seed: int = 12345
static var next_level_number: int = 1
static var saved_player_state: Dictionary = {}

## Warlord's Domain: the river runs north-south at x=0, 8m wide.
## Ships move freely but get +50% speed on water.
static func is_on_water(pos: Vector3) -> bool:
	return absf(pos.x) < 4.0

## 1-based cycle number (1 = first run through the four themes).
## Used by the HUD and the death screen's run stats.
func get_cycle_number() -> int:
	return int((level_number - 1) / THEME_ORDER.size()) + 1


enum WaveState { INTERMISSION, ACTIVE, CLEARED }

var theme: LevelTheme
var level_number := 1
var mob_types: Array[MobData] = []
var spawn_points: Array[Vector3] = []
var peer_classes := {} # int peer_id -> String class_id
var wave := 0
var wave_state: WaveState = WaveState.INTERMISSION
# Supermarket mode: collect & sell loot to unlock the gate.
var is_supermarket := false
# Warlord mode: AoE4-style RTS hybrid. No waves, no keys.
var is_warlord := false
var _rts_manager: RTSManager = null
var _warlord_setup_pending := false
var market_cash_goal := 500
var _market_spawn_tick := 0.0
var _market_loot_tick := 0.0
var wave_timer := 8.0 # countdown to the first wave
var mobs_to_spawn := 0
# AI Director composition for the current wave: Array of {"type": String, "elite": bool}.
var _wave_composition: Array = []
var _director: Node = null
var wave_info := {"wave": 0, "total": TOTAL_WAVES, "level": 1, "theme_name": "", "state": 0, "time_left": 8.0, "mobs_left": 0, "keys_found": 0, "keys_needed": 0}

var _layout: LevelLayout
var _mob_mix_sorted: Array[Dictionary] = []
var _server_rng := RandomNumberGenerator.new()
var _torch_lights: Array[OmniLight3D] = []
var _ambient_timer := 6.0
var _mob_id := 0
var _pickup_id := 0
var _spawn_tick := 0.0
var _wave_broadcast := 0.0
var _local_hud: CanvasLayer
var _portal: Area3D
var _advancing := false
var _boss: Mob = null
# --- Portal puzzle ---
var _portal_sealed := false
var _keys_needed := 0
var _keys_found := 0


func _ready() -> void:
	add_to_group("dungeon")
	randomize()
	_server_rng.seed = randi()
	# AI Director for wave composition (server-side only, but harmless on clients).
	_director = load("res://scripts/systems/ai_director.gd").new()
	_director.name = "AIDirector"
	add_child(_director)
	theme = load("res://data/levels/theme_%s.tres" % next_theme_id) as LevelTheme
	if theme == null:
		push_warning("[Dungeon] Unknown theme '%s', falling back to village." % next_theme_id)
		theme = load("res://data/levels/theme_village.tres") as LevelTheme
	level_number = next_level_number
	# Cycle scaling: each full loop (village->dungeon->depths) enlarges the
	# map and adds keys. Duplicate the theme so the .tres stays pristine.
	var cycle := (level_number - 1) / THEME_ORDER.size()
	if cycle > 0:
		theme = theme.duplicate() as LevelTheme
		theme.grid_size = mini(96, theme.grid_size + cycle * 40)
		theme.puzzle_key_count = mini(8, theme.puzzle_key_count + cycle)
	_layout = ProcGen.generate(theme, next_seed)
	_mob_mix_sorted = ProcGen.sorted_mob_mix(theme)
	# AI Director only spawns mobs this theme allows.
	_director.set_allowed_mobs(theme.mob_mix.keys())
	_load_mob_types()
	_build_arena_from_layout()
	AudioManager.play_music(next_theme_id)
	wave_info["theme_name"] = theme.display_name
	wave_info["theme_id"] = theme.theme_id
	wave_info["level"] = level_number
	# Supermarket mode: no waves, collect & sell to unlock the gate.
	is_supermarket = theme.theme_id == "supermarket"
	if is_supermarket:
		var mkt_cycle := (level_number - 1) / THEME_ORDER.size()
		market_cash_goal = 500 + mkt_cycle * 250
		wave_state = WaveState.CLEARED  # skip wave logic
		# Spawn the gate (sealed) and checkout immediately.
		if multiplayer.is_server():
			rpc("spawn_portal", _portal_pos(), true)
			_spawn_checkout()
			_spawn_potion_shop()
	# Warlord mode: RTS hybrid. No waves, no keys. Portal sealed until victory.
	is_warlord = theme.theme_id == "warlord"
	if is_warlord:
		wave_state = WaveState.CLEARED  # skip wave logic
		if multiplayer.is_server():
			rpc("spawn_portal", _portal_pos(), true)
			# Defer RTS setup until players have spawned.
			_warlord_setup_pending = true
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if multiplayer.is_server():
		var host_id := multiplayer.get_unique_id()
		peer_classes[host_id] = NetworkManager.selected_class_id
		_do_spawn(host_id, NetworkManager.selected_class_id, spawn_points[0])
	else:
		# Pull-based: the server pushes new arrivals to everyone already in
		# the game, and each newcomer pulls the full world state once loaded.
		rpc_id(NetworkManager.server_id, "register_class", NetworkManager.selected_class_id)
		rpc_id(NetworkManager.server_id, "request_state")


func get_spawn_point() -> Vector3:
	if spawn_points.size() > 0:
		return spawn_points[0]
	return Vector3(0, 1, 8)


func get_player_node(peer_id: int) -> Node:
	return $Players.get_node_or_null("Player_%d" % peer_id)


func _my_player() -> Player:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != null and p.get_multiplayer_authority() == multiplayer.get_unique_id():
			return p
	return null


func _load_mob_types() -> void:
	for entry in _mob_mix_sorted:
		var type_id := str(entry.get("id", ""))
		var data := load("res://data/mobs/%s.tres" % type_id) as MobData
		if data != null:
			mob_types.append(data)
		else:
			push_warning("[Dungeon] Missing mob data: %s" % type_id)
	# The theme boss isn't in the wave mix; load it too.
	if theme.boss_id != "":
		var boss_data := load("res://data/mobs/%s.tres" % theme.boss_id) as MobData
		if boss_data != null and not mob_types.has(boss_data):
			mob_types.append(boss_data)
		elif boss_data == null:
			push_warning("[Dungeon] Missing boss data: %s" % theme.boss_id)


# --- Players ---

@rpc("any_peer", "call_local")
func register_class(class_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	peer_classes[sender] = class_id
	_do_spawn(sender, class_id, _next_spawn_point())
	var node := get_player_node(sender)
	if node != null:
		rpc("spawn_player", sender, class_id, node.position)


@rpc("any_peer", "call_local")
func request_state() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	for pid in peer_classes:
		var existing := get_player_node(pid)
		if existing != null:
			rpc_id(sender, "spawn_player", pid, peer_classes[pid], existing.position)
	for m in $Mobs.get_children():
		var mob := m as Mob
		if mob != null and mob.alive:
			rpc_id(sender, "spawn_mob", mob.mob_id, mob.data.id, mob.position, mob.hp_scale, mob.dmg_scale, mob.is_elite)
	for p in $Pickups.get_children():
		var pickup := p as ItemPickup
		if pickup != null and not pickup.claimed:
			if pickup.is_key:
				rpc_id(sender, "spawn_key", pickup.position)
			elif pickup.item != null:
				rpc_id(sender, "spawn_pickup", pickup.item.id, pickup.position)


@rpc("any_peer", "call_local")
func spawn_player(peer_id: int, class_id: String, pos: Vector3) -> void:
	_do_spawn(peer_id, class_id, pos)


func _next_spawn_point() -> Vector3:
	var idx := peer_classes.size() % maxi(1, spawn_points.size())
	return spawn_points[idx]


func _do_spawn(peer_id: int, class_id: String, pos: Vector3) -> void:
	if get_player_node(peer_id) != null:
		return
	var p := PlayerScene.instantiate() as Player
	p.name = "Player_%d" % peer_id
	p.class_id = class_id
	p.set_multiplayer_authority(peer_id)
	p.position = pos
	$Players.add_child(p)
	if peer_id == multiplayer.get_unique_id():
		if not saved_player_state.is_empty():
			p.apply_state(saved_player_state)
			saved_player_state = {}
		_local_hud = HudScene.instantiate()
		add_child(_local_hud)
		_local_hud.setup(p)


@rpc("any_peer", "call_local")
func despawn_player(peer_id: int) -> void:
	var node := get_player_node(peer_id)
	if node != null:
		node.queue_free()


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	peer_classes.erase(peer_id)
	rpc("despawn_player", peer_id)


# --- Level transitions ---

func _difficulty_scale() -> float:
	return pow(1.15, float(level_number - 1))


## Average damage output across all players. Used to scale mob HP so
## the challenge stays consistent as the team gears up.
func _team_avg_damage() -> float:
	var total := 0.0
	var count := 0
	for n in get_tree().get_nodes_in_group("players"):
		var dmg := float(n.get("damage"))
		if dmg > 0.0:
			total += dmg
			count += 1
	if count == 0:
		return 10.0
	return total / float(count)


## Mob HP multiplier: base difficulty × team damage adaptation.
## At 15 avg damage this is 1.0x; scales linearly beyond that.
func _hp_scale() -> float:
	var adapt := _team_avg_damage() / 15.0
	# Bounded: 0.85x-1.75x (roadmap). Difficulty comes from composition,
	# positioning, elites, and attack cadence — not HP mirroring.
	adapt = clampf(adapt, 0.85, 1.75)
	return _difficulty_scale() * theme.hp_scale * adapt


func advance_level() -> void:
	if not multiplayer.is_server() or _advancing:
		return
	_advancing = true
	var new_level := level_number + 1
	# Cycle through themes: village -> dungeon -> depths -> village (new seed, harder).
	var theme_id: String = THEME_ORDER[(new_level - 1) % THEME_ORDER.size()]
	rpc("change_level", theme_id, randi(), new_level)


@rpc("any_peer", "call_local")
func change_level(theme_id: String, new_seed: int, new_level: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	var me := _my_player()
	if me != null:
		# Leaving the supermarket: confiscate supermarket loot (potions stay).
		if theme != null and theme.theme_id == "supermarket":
			var kept: Array = []
			for entry in me.get("inventory"):
				var item = entry["item"]
				if not bool(item.get("supermarket_loot")):
					kept.append(entry)
			me.set("inventory", kept)
			me.set("supermarket_cash", 0)
		saved_player_state = me.get_state()
		# Save point: persist the run so it can be continued from the menu.
		SaveManager.save_run({
			"theme_id": theme_id,
			"level_number": new_level,
			"class_id": me.class_id,
			"player_state": me.get_state(),
		})
		AudioManager.sfx("portal_enter")
	next_theme_id = theme_id
	next_seed = new_seed
	next_level_number = new_level
	# Deferred: change_level runs inside the portal's physics callback, and
	# freeing CollisionObjects during physics is illegal.
	get_tree().call_deferred("change_scene_to_file", "res://scenes/dungeon/dungeon.tscn")


# --- Mobs (host only) ---

func _process(delta: float) -> void:
	# Torch flicker and portal spin run on every peer; pure ambience.
	var t := Time.get_ticks_msec() / 1000.0
	for i in _torch_lights.size():
		_torch_lights[i].light_energy = 1.4 + sin(t * 7.0 + float(i) * 2.1) * 0.18
	if _portal != null and is_instance_valid(_portal):
		_portal.rotate_y(delta * 1.5)
	if multiplayer.is_server():
		# Deferred warlord setup: wait for at least one player.
		if _warlord_setup_pending and not get_tree().get_nodes_in_group("players").is_empty():
			_warlord_setup_pending = false
			_setup_warlord()
		if is_supermarket:
			_process_supermarket(delta)
		else:
			_process_waves(delta)
	if _local_hud != null:
		_local_hud.set_wave(wave_info)
		if is_supermarket:
			var me := _my_player()
			if me != null:
				_local_hud.set_market_cash(int(me.get("supermarket_cash")), market_cash_goal)
		_update_boss_bar()
	_process_ambient(delta)


## Supermarket: continuous mob spawner + loot spawner. Runs on server.
func _process_supermarket(delta: float) -> void:
	var cycle := (level_number - 1) / THEME_ORDER.size()
	# Mob capacity grows with cycle and map size.
	var mob_cap := 8 + cycle * 4
	var mob_count := $Mobs.get_child_count()
	if mob_count < mob_cap:
		_market_spawn_tick -= delta
		if _market_spawn_tick <= 0.0:
			_market_spawn_tick = 2.0
			_spawn_market_mob()
	# Loot spawns randomly, up to 20 at a time.
	var loot_count := 0
	for p in $Pickups.get_children():
		var item = p.get("item")
		if item != null and bool(item.get("supermarket_loot")):
			loot_count += 1
	if loot_count < 20:
		_market_loot_tick -= delta
		if _market_loot_tick <= 0.0:
			_market_loot_tick = 3.0
			_spawn_market_loot()


func _spawn_market_mob() -> void:
	# AI Director picks from its accumulated credits for continuous spawning.
	var comp: Array = _director.get_wave_composition()
	var data: MobData = null
	var elite := false
	if not comp.is_empty():
		var pick: Dictionary = comp[0]
		data = _mob_data(str(pick["type"]))
		elite = bool(pick["elite"])
	if data == null:
		data = _pick_mob_type()
	if data == null:
		return
	var pos := _random_floor_pos()
	if pos == Vector3.INF:
		return
	_mob_id += 1
	var hp_scale := _hp_scale()
	var dmg_scale := _difficulty_scale() * theme.dmg_scale
	rpc("spawn_mob", _mob_id, data.id, pos, hp_scale, dmg_scale, elite and not data.is_boss)


func _spawn_market_loot() -> void:
	var loot_ids := ["cereal_box", "soda_can", "milk_carton", "frozen_pizza", "snack_cake"]
	var pos := _random_floor_pos()
	if pos == Vector3.INF:
		return
	pos.y += 0.8
	rpc("spawn_pickup", loot_ids[_server_rng.randi() % loot_ids.size()], pos)


## Warlord's Domain setup: RTS factions, town halls, villagers, resources.
func _setup_warlord() -> void:
	print("[Warlord] Setting up RTS mode...")
	_rts_manager = RTSManager.new()
	_rts_manager.name = "RTSManager"
	add_child(_rts_manager)
	_rts_manager.winner_declared.connect(_on_warlord_winner)

	# Register player factions.
	var faction_id := 0
	var players := get_tree().get_nodes_in_group("players")
	print("[Warlord] Found %d players" % players.size())
	for p in players:
		var class_id := str(p.get("class_id"))
		var peer_id := p.get_multiplayer_authority()
		_rts_manager.register_faction(faction_id, peer_id, class_id)
		p.set("rts_faction", faction_id)
		_spawn_faction_base(faction_id, _faction_spawn_pos(faction_id))
		faction_id += 1

	# Solo: add AI warlord opponent(s).
	if faction_id == 1:
		var ai_count := 1
		var cycle := (level_number - 1) / THEME_ORDER.size()
		if cycle >= 2:
			ai_count = 2
		for i in ai_count:
			_rts_manager.register_faction(faction_id, -1, ["warrior", "rogue", "mage"][randi() % 3])
			_spawn_faction_base(faction_id, _faction_spawn_pos(faction_id))
			var ai := AIWarlord.new()
			ai.faction_id = faction_id
			add_child(ai)
			faction_id += 1

	# Scatter resource nodes.
	_spawn_resource_nodes()

	# River across the map + one dock per faction near the river bank.
	rpc("spawn_rts_river")
	for fid in _rts_manager.factions:
		var fi := int(fid)
		var bp := _faction_spawn_pos(fi)
		var side := 1.0 if bp.x >= 0.0 else -1.0
		var dciv := _rts_manager.get_civ(fi)
		rpc("spawn_rts_dock", fi, Vector3(side * 6.0, 0.0, bp.z), dciv.civ_id)

	# RTS camera for the local player (Tab to toggle).
	var rts_cam := RTSCamera.new()
	rts_cam.name = "RTSCamera"
	rts_cam.add_to_group("rts_camera")
	add_child(rts_cam)
	# Find local player's faction.
	var local_faction := 0
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == multiplayer.get_unique_id():
			local_faction = int(p.get("rts_faction"))
			break
	rts_cam.setup(_rts_manager, local_faction)

	# RTS HUD: resource bar, age, population (one per local player).
	var rts_hud := RTSHUD.new()
	rts_hud.name = "RTSHUD"
	add_child(rts_hud)
	rts_hud.setup(_rts_manager, local_faction)

	rpc("announce", "WARLORD'S DOMAIN — Last faction standing wins!")
	rpc("announce", "Press TAB for command view. B to build. Right-click to order units.")


func _faction_spawn_pos(faction_id: int) -> Vector3:
	# Spread factions around the map.
	var angle := TAU * float(faction_id) / float(maxi(2, _rts_manager.factions.size()))
	var radius := 30.0
	return Vector3(cos(angle) * radius, 0, sin(angle) * radius)


func _spawn_faction_base(faction_id: int, pos: Vector3) -> void:
	var civ := _rts_manager.get_civ(faction_id)
	rpc("spawn_rts_base", faction_id, pos, civ.civ_id)


@rpc("any_peer", "call_local")
func spawn_rts_base(faction_id: int, pos: Vector3, civ_id: String) -> void:
	var civ := CivData.for_class(_class_from_civ(civ_id))
	# Town Hall.
	var th := RTSBuilding.new()
	th.setup(faction_id, "town_hall", civ)
	th.position = pos
	$RTS.add_child(th)
	_wire_building(th, faction_id)
	# 3 villagers around it.
	var villagers: Array = []
	for i in 3:
		var v := RTSUnit.new()
		v.setup(faction_id, "villager", civ)
		var angle := TAU * float(i) / 3.0
		v.position = pos + Vector3(cos(angle) * 3.0, 0, sin(angle) * 3.0)
		$RTS.add_child(v)
		villagers.append(v)
	# Server: AI factions auto-gather immediately.
	if multiplayer.is_server() and _rts_manager != null:
		var f: Dictionary = _rts_manager.factions.get(faction_id, {})
		if int(f.get("peer_id", -2)) == -1:  # AI faction
			for v in villagers:
				var node := _nearest_resource(v.position)
				if node != null:
					v.order_gather(node)


func _nearest_resource(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 9999.0
	for n in get_tree().get_nodes_in_group("rts_resources"):
		var d: float = pos.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## Server-side wiring so building production (training) actually works.
func _wire_building(b: RTSBuilding, faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	var mgr := get_tree().get_first_node_in_group("rts_manager")
	b.rts_manager = mgr
	if _rts_manager != null:
		b.knights_unlocked = _rts_manager.get_age(faction_id) >= 1


@rpc("any_peer", "call_local")
func spawn_rts_dock(faction_id: int, pos: Vector3, civ_id: String) -> void:
	var civ := CivData.for_class(_class_from_civ(civ_id))
	var dock := RTSBuilding.new()
	dock.setup(faction_id, "dock", civ)
	dock.position = pos
	$RTS.add_child(dock)
	_wire_building(dock, faction_id)


@rpc("any_peer", "call_local")
func spawn_rts_river() -> void:
	# Visual-only water plane (no collision: units have no pathfinding,
	# so a solid river would trap land units). Group "rts_water" for queries.
	var water := StaticBody3D.new()
	water.name = "River"
	water.add_to_group("rts_water")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8.0, 0.2, 96.0)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.45, 0.75, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = Vector3(0, -0.1, 0)
	water.add_child(mi)
	$RTS.add_child(water)
	# Decorative reeds along the banks.
	for i in 24:
		var z := randf_range(-44.0, 44.0)
		var side := 1.0 if i % 2 == 0 else -1.0
		var x := side * randf_range(4.5, 6.0)
		_spawn_reed(Vector3(x, 0, z))


func _spawn_reed(pos: Vector3) -> void:
	var reed := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.05
	cm.height = randf_range(0.6, 1.2)
	reed.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.55, 0.25)
	reed.material_override = mat
	reed.position = pos + Vector3(0, cm.height / 2.0, 0)
	$RTS.add_child(reed)


func _class_from_civ(civ_id: String) -> String:
	match civ_id:
		"iron_vanguard":
			return "warrior"
		"shadow_covenant":
			return "rogue"
		"arcane_dominion":
			return "mage"
	return "warrior"


func _spawn_resource_nodes() -> void:
	for i in 24:
		var t: String = ["wood", "food", "gold", "stone"][i % 4]
		var angle := TAU * float(i) / 18.0
		var radius := 18.0 + randf() * 8.0
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		rpc("spawn_rts_node", t, pos)


@rpc("any_peer", "call_local")
func spawn_rts_node(res_type: String, pos: Vector3) -> void:
	var amounts := {"wood": 600, "food": 500, "gold": 400, "stone": 500}
	var node := RTSResourceNode.new()
	node.setup(res_type, int(amounts[res_type]))
	node.position = pos
	node.add_to_group("rts_resources")
	$RTS.add_child(node)


func _on_warlord_winner(winner_faction: int) -> void:
	rpc("announce", "VICTORY! The portal is open.")
	# Unseal the portal.
	rpc("unseal_portal")


## Server-side: start construction of a building at a position.
## Charges the cost, spawns the building under construction, and orders
## an idle villager of the faction to build it.
@rpc("any_peer", "call_local")
func rpc_start_construction(faction_id: int, btype: String, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if _rts_manager == null:
		return
	var cost: Dictionary = RTSManager.BUILDING_COSTS.get(btype, {})
	if cost.is_empty():
		return
	var age_req := 1 if btype in ["siege_workshop", "monastery"] else 0
	if _rts_manager.get_age(faction_id) < age_req:
		return
	if not _rts_manager.spend(faction_id, cost):
		return
	# Find a villager of this faction (prefer idle).
	var builder: Node3D = null
	for u in get_tree().get_nodes_in_group("rts_units"):
		if int(u.get("faction")) != faction_id or str(u.get("unit_type")) != "villager":
			continue
		if u.get("_move_target") == Vector3.INF and u.get("_attack_target") == null and u.get("_gather_node") == null:
			builder = u
			break
	if builder == null:
		for u in get_tree().get_nodes_in_group("rts_units"):
			if int(u.get("faction")) == faction_id and str(u.get("unit_type")) == "villager":
				builder = u
				break
	if builder == null:
		for k in cost:  # refund
			_rts_manager.add_resource(faction_id, k, int(cost[k]))
		return
	var civ: CivData = _rts_manager.factions[faction_id]["civ"]
	var b := RTSBuilding.new()
	b.setup(faction_id, btype, civ)
	b.rts_manager = _rts_manager
	b.position = pos
	$RTS.add_child(b)
	b.start_construction()
	builder.rpc("rpc_order_build", b.get_path())


## Checkout counter: walk through to auto-sell supermarket loot for cash.
func _spawn_checkout() -> void:
	var pos := _portal_pos() + Vector3(12, 0, 0)
	rpc("spawn_checkout", pos)


@rpc("any_peer", "call_local")
func spawn_checkout(pos: Vector3) -> void:
	var root := Area3D.new()
	root.name = "Checkout"
	root.position = pos
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 4.0
	cyl.height = 4.0
	col.shape = cyl
	col.position.y = 2.0
	root.add_child(col)
	# Visual: green glowing register.
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.0, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 0.3)
	mat.emission_energy_multiplier = 1.5
	box.material = mat
	mesh.mesh = box
	mesh.position.y = 0.5
	root.add_child(mesh)
	# Glowing sell-zone ring on the floor.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.6
	torus.outer_radius = 4.0
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.2, 1.0, 0.4)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.2, 1.0, 0.4)
	ring_mat.emission_energy_multiplier = 2.0
	torus.material = ring_mat
	ring.mesh = torus
	ring.position.y = 0.1
	root.add_child(ring)
	var label := Label3D.new()
	label.text = "CHECKOUT\n(walk through to sell)"
	label.position = Vector3(0, 2.6, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	$Pickups.add_child(root)
	root.body_entered.connect(_on_checkout_body.bind(root))


func _on_checkout_body(body: Node3D, checkout: Area3D) -> void:
	# Server-side: auto-sell the entering player's supermarket loot.
	if not multiplayer.is_server():
		return
	if not body.is_in_group("players"):
		return
	_sell_player_loot(body)


## Potion shop: 3D counter with 3 buyable potions. E at a pedestal to buy.
func _spawn_potion_shop() -> void:
	var base := _portal_pos() + Vector3(-14, 0, 0)
	var potions := [
		{"id": "health_potion", "price": 50, "color": Color(0.9, 0.2, 0.2), "label": "Health Potion\n$50"},
		{"id": "swift_potion", "price": 75, "color": Color(0.2, 0.7, 1.0), "label": "Swift Potion\n$75"},
		{"id": "power_elixir", "price": 100, "color": Color(1.0, 0.6, 0.1), "label": "Power Elixir\n$100"},
	]
	for i in potions.size():
		var p: Dictionary = potions[i]
		var pos := base + Vector3(i * 5.0 - 5.0, 0, 0)
		rpc("spawn_shop_pedestal", pos, p["id"], p["price"], p["color"], p["label"])
	# Shop sign.
	rpc("spawn_shop_sign", base + Vector3(0, 0, -2.5))


@rpc("any_peer", "call_local")
func spawn_shop_sign(pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = "POTION SHOP"
	label.font_size = 64
	label.position = pos + Vector3(0, 3.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.85, 0.3)
	$Pickups.add_child(label)


@rpc("any_peer", "call_local")
func spawn_shop_pedestal(pos: Vector3, item_id: String, price: int, color: Color, label_text: String) -> void:
	var root := Area3D.new()
	root.name = "Shop_%s" % item_id
	root.position = pos
	root.set_meta("item_id", item_id)
	root.set_meta("price", price)
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.5
	cyl.height = 3.0
	col.shape = cyl
	col.position.y = 1.5
	root.add_child(col)
	# Pedestal.
	var ped := MeshInstance3D.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = 0.5
	cyl_mesh.bottom_radius = 0.6
	cyl_mesh.height = 1.0
	var ped_mat := StandardMaterial3D.new()
	ped_mat.albedo_color = Color(0.4, 0.42, 0.48)
	cyl_mesh.material = ped_mat
	ped.mesh = cyl_mesh
	ped.position.y = 0.5
	root.add_child(ped)
	# Floating potion bottle (spinning).
	var bottle := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.3
	sph.height = 0.6
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = color
	bmat.emission_enabled = true
	bmat.emission = color
	bmat.emission_energy_multiplier = 2.0
	sph.material = bmat
	bottle.mesh = sph
	bottle.position.y = 1.6
	root.add_child(bottle)
	# Spin animation.
	var tw := bottle.create_tween().set_loops()
	tw.tween_property(bottle, "rotation:y", TAU, 3.0)
	var bob := bottle.create_tween().set_loops()
	bob.tween_property(bottle, "position:y", 1.8, 1.0)
	bob.tween_property(bottle, "position:y", 1.6, 1.0)
	# Price label.
	var label := Label3D.new()
	label.text = "%s\n(E to buy)" % label_text
	label.font_size = 32
	label.position = Vector3(0, 2.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	$Pickups.add_child(root)


## Buy a potion from the shop. Called via E interaction.
@rpc("any_peer", "call_local")
func buy_potion(item_id: String, price: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player := get_player_node(sender)
	if player == null:
		return
	var cash := int(player.get("supermarket_cash"))
	if cash < price:
		player.rpc_id(sender, "on_buy_failed", price)
		return
	player.set("supermarket_cash", cash - price)
	player.rpc_id(sender, "receive_item", item_id)
	player.rpc_id(sender, "on_bought", item_id, price)


## Sell all supermarket loot in the player's inventory for cash.
@rpc("any_peer", "call_local")
func sell_loot() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player := get_player_node(sender)
	if player == null:
		return
	_sell_player_loot(player)


## Server-side: convert a player's supermarket loot into cash.
func _sell_player_loot(player: Node) -> void:
	var sender := int(player.get_multiplayer_authority())
	var total := 0
	var kept: Array = []
	for entry in player.get("inventory"):
		var item = entry["item"]
		if bool(item.get("supermarket_loot")):
			total += int(item.get("sell_value")) * int(entry["count"])
		else:
			kept.append(entry)
	if total > 0:
		player.set("inventory", kept)
		player.set("supermarket_cash", int(player.get("supermarket_cash")) + total)
		player.rpc_id(sender, "on_sold", total)
		_check_gate_unlock()


func _check_gate_unlock() -> void:
	if not is_supermarket or not _portal_sealed:
		return
	var team_cash := 0
	for n in get_tree().get_nodes_in_group("players"):
		team_cash += int(n.get("supermarket_cash"))
	if team_cash >= market_cash_goal:
		_portal_sealed = false
		rpc("unlock_portal")
		rpc("announce", "GATE UNLOCKED!")


@rpc("any_peer", "call_local")
func unlock_portal() -> void:
	_portal_sealed = false
	# Update portal visual to unlocked (cyan).
	if _portal != null and is_instance_valid(_portal):
		var ring = _portal.get_node_or_null("Ring")
		if ring != null:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 0.9, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.3, 0.9, 1.0)
			mat.emission_energy_multiplier = 2.0
			(ring as MeshInstance3D).material_override = mat


func _random_floor_pos() -> Vector3:
	for attempt in 20:
		var cx := _server_rng.randi() % _layout.grid_size
		var cz := _server_rng.randi() % _layout.grid_size
		if _layout.is_floor(cx, cz):
			var pos := _layout.cell_to_world(cx, cz)
			pos.y = 0.5
			return pos
	return Vector3.INF


## Boss HP bar: every peer reads its local boss copy (hp syncs via snapshots).
func _update_boss_bar() -> void:
	if _boss != null and is_instance_valid(_boss) and bool(_boss.get("alive")):
		var bd := _boss.get("data") as MobData
		var max_hp: float = bd.health * float(_boss.get("hp_scale"))
		_local_hud.set_boss(bd.boss_title, clampf(float(_boss.get("hp")) / max_hp, 0.0, 1.0))
	else:
		_local_hud.hide_boss()


## Random ambient one-shots per theme. Runs on every peer; positions are
## cosmetic so they don't need to agree across the network.
func _process_ambient(delta: float) -> void:
	_ambient_timer -= delta
	if _ambient_timer > 0.0:
		return
	_ambient_timer = randf_range(5.0, 11.0)
	var spot := Vector3(randf_range(-16.0, 16.0), 1.5, randf_range(-16.0, 16.0))
	match theme.theme_id:
		"village":
			if randf() < 0.65:
				AudioManager.sfx("bird", spot, randf_range(0.85, 1.15), 0.7)
			else:
				AudioManager.sfx("wind_gust")
		"dungeon":
			var r := randf()
			if r < 0.45:
				AudioManager.sfx("drip", spot, randf_range(0.8, 1.25), 0.8)
			elif r < 0.75:
				AudioManager.sfx("wind_gust", null, 1.0, 0.7)
			else:
				AudioManager.sfx("torch_crackle", spot, randf_range(0.9, 1.1), 0.6)
		_:
			# depths and beyond
			if randf() < 0.5:
				AudioManager.sfx("rumble", null, randf_range(0.85, 1.1), 0.8)
			else:
				AudioManager.sfx("drip", spot, randf_range(0.6, 0.9), 0.7)


# --- Waves (host only) ---

func _process_waves(delta: float) -> void:
	match wave_state:
		WaveState.INTERMISSION:
			# No auto-countdown: the host starts the next wave manually.
			pass
		WaveState.ACTIVE:
			_spawn_tick -= delta
			if _spawn_tick <= 0.0 and mobs_to_spawn > 0 and $Mobs.get_child_count() < MAX_CONCURRENT:
				_spawn_tick = 1.1
				mobs_to_spawn -= 1
				_mob_id += 1
				# Pop the next mob from the AI Director's composition.
				var pick: Dictionary = {"type": "slime", "elite": false}
				if not _wave_composition.is_empty():
					pick = _wave_composition.pop_front()
				var data := _mob_data(str(pick["type"]))
				if data == null:
					data = _pick_mob_type()
				var hp_scale := _hp_scale()
				var dmg_scale := _difficulty_scale() * theme.dmg_scale
				var elite := bool(pick["elite"]) and not data.is_boss
				rpc("spawn_mob", _mob_id, data.id, _random_mob_pos(), hp_scale, dmg_scale, elite)
			if mobs_to_spawn <= 0 and $Mobs.get_child_count() == 0:
				_wave_cleared()
	_wave_broadcast -= delta
	if _wave_broadcast <= 0.0:
		_wave_broadcast = 0.25
		_push_wave_info()
		rpc_unreliable_wave()


func _start_wave() -> void:
	wave += 1
	wave_state = WaveState.ACTIVE
	_spawn_tick = 0.5
	if wave >= TOTAL_WAVES and theme.boss_id != "":
		# Boss wave: the theme boss plus a small honor guard.
		mobs_to_spawn = 4
		_wave_composition = []
		_spawn_boss()
	else:
		# AI Director decides the wave composition.
		_director.start_wave(wave)
		_wave_composition = _director.get_wave_composition()
		mobs_to_spawn = _wave_composition.size()
		rpc("announce", "WAVE %d" % wave)


## Host-only: manually trigger the next wave during intermission.
@rpc("any_peer", "call_local")
func request_next_wave() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	if wave_state == WaveState.INTERMISSION:
		_start_wave()
	_push_wave_info()
	rpc_unreliable_wave()


func _spawn_boss() -> void:
	_mob_id += 1
	# Farthest spawn from the center so the boss makes an entrance.
	var pos := _random_mob_pos()
	var best_d := 0.0
	for s in _layout.mob_spawns:
		var d: float = (Vector3(s.x, 0, s.z) - Vector3.ZERO).length()
		if d > best_d:
			best_d = d
			pos = Vector3(s.x, 0.5, s.z)
	rpc("spawn_mob", _mob_id, theme.boss_id, pos, _difficulty_scale() * theme.hp_scale, _difficulty_scale() * theme.dmg_scale)


func _wave_cleared() -> void:
	if wave >= TOTAL_WAVES:
		wave_state = WaveState.CLEARED
		_shower_loot()
		# The exit portal spawns SEALED: the party must find every key first.
		_keys_needed = theme.puzzle_key_count
		_keys_found = 0
		rpc("spawn_portal", _portal_pos(), true)
		for spot in _key_spots():
			rpc("spawn_key", spot)
		rpc("announce", "%s CLEARED! The portal is SEALED -- find %d keys!" % [theme.display_name.to_upper(), _keys_needed])
		rpc("update_key_count", 0, _keys_needed)
	else:
		wave_state = WaveState.INTERMISSION
		wave_timer = INTERMISSION_TIME
		rpc("announce", "Wave cleared!")
	_push_wave_info()
	rpc_unreliable_wave()


## Key hiding spots: maze dead-ends for labyrinth themes, far-flung floor
## cells otherwise. Server-side only.
func _key_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	if not _layout.maze_dead_ends.is_empty():
		var pool := _layout.maze_dead_ends.duplicate()
		pool.shuffle()
		for i in mini(_keys_needed, pool.size()):
			var p: Vector3 = pool[i]
			spots.append(Vector3(p.x, 1.0, p.z))
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for p in ProcGen.key_spots(_layout, _keys_needed, rng):
			spots.append(Vector3(p.x, 1.0, p.z))
	return spots


func _shower_loot() -> void:
	var ids: Array = []
	for id in ItemDB.items.keys():
		var item = ItemDB.items[id]
		if not bool(item.get("supermarket_loot")):
			ids.append(id)
	if ids.is_empty():
		return
	for i in mini(4, ids.size()):
		var item_id: String = ids[randi() % ids.size()]
		var pos := Vector3(randf_range(-6.0, 6.0), 0.8, randf_range(-6.0, 6.0))
		rpc("spawn_pickup", item_id, pos)


func _portal_pos() -> Vector3:
	# Away from the center so nobody trips it while grabbing loot.
	if _layout.mob_spawns.is_empty():
		return Vector3(0, 0, -8.0)
	var pos: Vector3 = _layout.mob_spawns[randi() % _layout.mob_spawns.size()]
	pos.y = 0.0
	return pos


func _mobs_alive() -> int:
	var count := 0
	for m in $Mobs.get_children():
		var mob := m as Mob
		if mob != null and mob.alive:
			count += 1
	return count


func _push_wave_info() -> void:
	wave_info["wave"] = wave
	wave_info["total"] = TOTAL_WAVES
	wave_info["level"] = level_number
	wave_info["theme_name"] = theme.display_name
	wave_info["theme_id"] = theme.theme_id
	wave_info["state"] = int(wave_state)
	wave_info["time_left"] = maxf(wave_timer, 0.0)
	wave_info["mobs_left"] = _mobs_alive() + mobs_to_spawn
	wave_info["keys_found"] = _keys_found
	wave_info["keys_needed"] = _keys_needed


func rpc_unreliable_wave() -> void:
	rpc("wave_snapshot", wave_info["wave"], wave_info["total"], wave_info["level"],
		wave_info["state"], wave_info["time_left"], wave_info["mobs_left"],
		wave_info["keys_found"], wave_info["keys_needed"])


@rpc("any_peer", "call_local", "unreliable")
func wave_snapshot(w: int, total: int, level: int, state: int, time_left: float, mobs_left: int, keys_found: int, keys_needed: int) -> void:
	wave_info["wave"] = w
	wave_info["total"] = total
	wave_info["level"] = level
	wave_info["state"] = state
	wave_info["time_left"] = time_left
	wave_info["mobs_left"] = mobs_left
	wave_info["keys_found"] = keys_found
	wave_info["keys_needed"] = keys_needed


@rpc("any_peer", "call_local")
func announce(text: String) -> void:
	if _local_hud != null:
		_local_hud.announce(text)
	# Every peer hears wave stingers locally.
	if text.begins_with("WAVE"):
		AudioManager.sfx("wave_horn")
	elif text.contains("CLEARED") or text == "Wave cleared!":
		AudioManager.sfx("wave_clear")


func _pick_mob_type() -> MobData:
	if mob_types.is_empty():
		return null
	var type_id := ProcGen.pick_mob_id(_server_rng, _mob_mix_sorted)
	return _mob_data(type_id)


@rpc("any_peer", "call_local")
func spawn_mob(mob_id: int, type_id: String, pos: Vector3, hp_scale: float = 1.0, dmg_scale: float = 1.0, elite: bool = false) -> void:
	var data := _mob_data(type_id)
	if data == null:
		return
	var m := MobScene.instantiate() as Mob
	m.name = "Mob_%d" % mob_id
	m.setup(mob_id, data, hp_scale, dmg_scale, elite)
	m.position = pos
	$Mobs.add_child(m)
	if data.is_boss:
		_boss = m
		rpc("announce", "WARNING: %s" % data.boss_title)
		if _local_hud != null:
			_local_hud.show_boss_card(data.boss_title)
		AudioManager.sfx("boss_roar", pos)
	elif elite and _local_hud != null:
		_local_hud.toast("Elite %s appeared!" % data.display_name)


## Fires an enemy arrow on all peers. Each peer simulates its own copy;
## only the server applies damage (see EnemyArrow).
@rpc("any_peer", "call_local")
func spawn_arrow(origin: Vector3, dir: Vector3, damage: float, speed: float, shooter_name: String = "Goblin Archer") -> void:
	var arrow := EnemyArrow.new()
	arrow.setup(dir.normalized() * speed, damage)
	arrow.attacker_name = shooter_name
	add_child(arrow)
	arrow.global_position = origin


## Places a warrior totem on all peers.
@rpc("any_peer", "call_local")
func place_totem(totem_id: String, pos: Vector3, owner: int, rank: int = 1) -> void:
	var totem := Totem.new()
	totem.setup(totem_id, owner, rank)
	add_child(totem)
	totem.global_position = Vector3(pos.x, 0.05, pos.z)


## Server-side helper for boss summons.
func server_spawn_mob(type_id: String, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_mob_id += 1
	var data := _mob_data(type_id)
	var elite := data != null and not data.is_boss and randf() < 0.10
	rpc("spawn_mob", _mob_id, type_id, pos, _difficulty_scale() * theme.hp_scale, _difficulty_scale() * theme.dmg_scale, elite)


func _mob_data(type_id: String) -> MobData:
	for d in mob_types:
		if d.id == type_id:
			return d
	# Fallback: load directly (e.g. a boss summoning a type outside the mix).
	if ResourceLoader.exists("res://data/mobs/%s.tres" % type_id):
		return load("res://data/mobs/%s.tres" % type_id) as MobData
	return null


func _random_mob_pos() -> Vector3:
	if _layout.mob_spawns.is_empty():
		return Vector3(0, 1.0, -10.0)
	for attempt in 12:
		var pos: Vector3 = _layout.mob_spawns[randi() % _layout.mob_spawns.size()]
		pos.y = 1.0
		var clear := true
		for n in get_tree().get_nodes_in_group("players"):
			var p := n as Node3D
			if p != null and p.global_position.distance_to(pos) < 8.0:
				clear = false
				break
		if clear:
			return pos
	var fallback: Vector3 = _layout.mob_spawns[0]
	fallback.y = 1.0
	return fallback


# --- Pickups ---

@rpc("any_peer", "call_local")
func spawn_pickup(item_id: String, pos: Vector3) -> void:
	var item := ItemDB.get_item(item_id)
	if item == null:
		return
	_pickup_id += 1
	var pickup := PickupScene.instantiate() as ItemPickup
	pickup.name = "Pickup_%d" % _pickup_id
	pickup.setup(item)
	pickup.position = pos
	$Pickups.add_child(pickup)


## Spawns a puzzle key. Keys never expire and count toward unsealing the portal.
@rpc("any_peer", "call_local")
func spawn_key(pos: Vector3) -> void:
	_pickup_id += 1
	var key := PickupScene.instantiate() as ItemPickup
	key.name = "Key_%d" % _pickup_id
	key.is_key = true
	key.position = pos
	$Pickups.add_child(key)


# --- Portal ---

@rpc("any_peer", "call_local")
func spawn_portal(pos: Vector3, sealed: bool) -> void:
	if _portal != null and is_instance_valid(_portal):
		return
	AudioManager.sfx("portal_open", pos)
	_portal_sealed = sealed
	var root := Area3D.new()
	root.name = "Portal"
	root.position = pos
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.6
	cyl.height = 3.0
	col.shape = cyl
	col.position.y = 1.5
	root.add_child(col)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var tm := TorusMesh.new()
	tm.outer_radius = 1.4
	tm.inner_radius = 1.1
	tm.rings = 24
	tm.ring_segments = 48
	var pmat := StandardMaterial3D.new()
	tm.material = pmat
	ring.mesh = tm
	ring.position.y = 1.5
	ring.rotation_degrees.x = 90.0
	root.add_child(ring)
	var swirl := _make_portal_particles()
	swirl.name = "Swirl"
	swirl.position.y = 1.5
	root.add_child(swirl)
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.omni_range = 9.0
	light.position.y = 1.5
	root.add_child(light)
	root.body_entered.connect(_on_portal_body)
	add_child(root)
	_portal = root
	_apply_portal_visual()


## Colors the portal by seal state: chained red while sealed, cyan when open.
func _apply_portal_visual() -> void:
	if _portal == null or not is_instance_valid(_portal):
		return
	var ring := _portal.get_node_or_null("Ring") as MeshInstance3D
	var swirl := _portal.get_node_or_null("Swirl") as GPUParticles3D
	var light := _portal.get_node_or_null("Glow") as OmniLight3D
	if _portal_sealed:
		if ring != null:
			var m := ring.mesh as TorusMesh
			var pmat := m.material as StandardMaterial3D
			pmat.albedo_color = Color(0.55, 0.12, 0.12)
			pmat.emission_enabled = true
			pmat.emission = Color(0.8, 0.15, 0.1)
			pmat.emission_energy_multiplier = 1.2
		if swirl != null:
			swirl.emitting = false
		if light != null:
			light.light_color = Color(0.8, 0.2, 0.15)
			light.light_energy = 1.0
	else:
		if ring != null:
			var m := ring.mesh as TorusMesh
			var pmat := m.material as StandardMaterial3D
			pmat.albedo_color = Color(0.3, 0.9, 1.0)
			pmat.emission_enabled = true
			pmat.emission = Color(0.25, 0.8, 1.0)
			pmat.emission_energy_multiplier = 2.5
		if swirl != null:
			swirl.emitting = true
		if light != null:
			light.light_color = Color(0.35, 0.85, 1.0)
			light.light_energy = 2.0


## Server-side: a key was claimed by a player.
@rpc("any_peer", "call_local")
func collect_key(claimer: int) -> void:
	if not multiplayer.is_server():
		return
	_keys_found += 1
	AudioManager.sfx("key")
	rpc("update_key_count", _keys_found, _keys_needed)
	if _keys_found >= _keys_needed:
		rpc("unseal_portal")


@rpc("any_peer", "call_local")
func update_key_count(found: int, needed: int) -> void:
	_keys_found = found
	_keys_needed = needed
	_push_wave_info()


@rpc("any_peer", "call_local")
func unseal_portal() -> void:
	_portal_sealed = false
	_apply_portal_visual()
	AudioManager.sfx("unlock")
	rpc("announce", "PORTAL UNSEALED! Get to the portal!")


func _make_portal_particles() -> GPUParticles3D:
	var parts := GPUParticles3D.new()
	parts.amount = 40
	parts.lifetime = 1.2
	parts.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_height = 0.0
	pm.emission_ring_radius = 1.25
	pm.emission_ring_inner_radius = 1.1
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.06
	pm.scale_max = 0.14
	pm.color = Color(0.4, 0.9, 1.0)
	parts.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var qmat := StandardMaterial3D.new()
	qmat.albedo_color = Color(0.5, 0.95, 1.0)
	qmat.emission_enabled = true
	qmat.emission = Color(0.4, 0.9, 1.0)
	qmat.emission_energy_multiplier = 2.0
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = qmat
	parts.draw_pass_1 = quad
	return parts


func _on_portal_body(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if not body.is_in_group("players"):
		return
	if _portal_sealed:
		# Nudge only the player who bumped into it.
		var peer_id := int(body.name.get_slice("_", 1))
		rpc_id(peer_id, "portal_denied")
		return
	advance_level()


@rpc("any_peer", "call_local")
func portal_denied() -> void:
	AudioManager.sfx("ui_error")
	if _local_hud != null:
		_local_hud.announce("Sealed! Find the remaining keys.")


# --- Arena construction from the procedural layout ---

func _build_arena_from_layout() -> void:
	for holder_name in ["Players", "Mobs", "Pickups", "Projectiles", "RTS"]:
		var holder := Node3D.new()
		holder.name = holder_name
		add_child(holder)
	_build_environment()
	_build_floor()
	_build_walls()
	_build_obstacles()
	_build_props()
	_build_torches()
	spawn_points = _layout.player_spawns


func _build_environment() -> void:
	var env := Environment.new()
	if theme.sun_energy > 0.0:
		var sky := Sky.new()
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = theme.sky_color
		sky_mat.sky_horizon_color = theme.sky_color.lightened(0.25)
		sky_mat.ground_bottom_color = theme.ground_color.darkened(0.4)
		sky_mat.ground_horizon_color = theme.ground_color
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = theme.sky_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = theme.ambient_color
	env.ambient_light_energy = theme.ambient_energy
	env.fog_enabled = true
	env.fog_light_color = theme.fog_color
	env.fog_density = theme.fog_density
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = theme.sun_color
	sun.light_energy = theme.sun_energy
	var dir := theme.sun_direction.normalized()
	sun.rotation = Vector3(asin(clampf(-dir.y, -1.0, 1.0)), atan2(-dir.x, -dir.z), 0.0)
	add_child(sun)


func _flat_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat


func _build_floor() -> void:
	var size := float(_layout.grid_size) * _layout.cell_size + 6.0
	var body := StaticBody3D.new()
	body.name = "Floor"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	col.shape = box
	col.position.y = -0.5
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.material = TextureGen.textured_mat(TextureGen.floor_tex(theme.ground_color), size / 8.0)
	mesh.mesh = plane
	body.add_child(mesh)
	add_child(body)


func _build_walls() -> void:
	var half := _layout.arena_half_size()
	var wall_h := 4.0
	var thick := 1.5
	var mat := TextureGen.textured_mat(TextureGen.wall_tex(theme.wall_color), 3.0)
	for data in [
		[Vector3(0, wall_h * 0.5, -half), Vector3(half * 2.0 + thick, wall_h, thick)],
		[Vector3(0, wall_h * 0.5, half), Vector3(half * 2.0 + thick, wall_h, thick)],
		[Vector3(-half, wall_h * 0.5, 0), Vector3(thick, wall_h, half * 2.0 + thick)],
		[Vector3(half, wall_h * 0.5, 0), Vector3(thick, wall_h, half * 2.0 + thick)],
	]:
		var body := StaticBody3D.new()
		body.name = "Wall"
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = data[1]
		col.shape = box
		body.add_child(col)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = data[1]
		bm.material = mat
		mesh.mesh = bm
		body.add_child(mesh)
		body.position = data[0]
		add_child(body)


func _build_obstacles() -> void:
	var n := _layout.grid_size
	var body := StaticBody3D.new()
	body.name = "Obstacles"
	var shape_count := 0
	for cz in n:
		for cx in n:
			if _layout.grid[_layout.idx(cx, cz)] != LevelLayout.OBSTACLE:
				continue
			var col := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(_layout.cell_size, 3.0, _layout.cell_size)
			col.shape = box
			var wp := _layout.cell_to_world(cx, cz)
			col.position = Vector3(wp.x, 1.5, wp.z)
			body.add_child(col)
			shape_count += 1
	if shape_count > 0:
		add_child(body)
	else:
		body.queue_free()


func _build_props() -> void:
	for p in _layout.props:
		var prop_type := str(p.get("type", "rock"))
		var pos: Vector3 = p.get("pos", Vector3.ZERO)
		var visual: Node3D
		if bool(p.get("obstacle_visual", false)):
			# Obstacle block visual, tinted by the theme, scaled to the block.
			visual = PropBuilder.build(prop_type, float(p.get("scl", 1.0)), {"pos": pos})
			if not visual.has_meta("is_model"):
				_tint_prop(visual, theme.obstacle_color)
		else:
			visual = PropBuilder.build(prop_type, float(p.get("scl", 1.0)), {"pos": pos})
		visual.position = pos
		visual.rotation.y = float(p.get("rot", 0.0))
		add_child(visual)


func _tint_prop(node: Node, color: Color) -> void:
	# Recolor placeholder obstacle visuals toward the theme palette.
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var m := (mi.material_override as StandardMaterial3D)
			if m != null:
				var tinted := m.duplicate() as StandardMaterial3D
				tinted.albedo_color = tinted.albedo_color.lerp(color, 0.55)
				mi.material_override = tinted
		_tint_prop(child, color)


func _build_torches() -> void:
	for pos in _layout.torches:
		var torch := PropBuilder.build("torch", 1.0, {
			"light_color": theme.torch_light_color,
			"light_energy": theme.torch_light_energy,
		})
		torch.position = pos - Vector3(0, 1.6, 0) # layout stores flame height; prop is ground-based
		add_child(torch)
		for child in torch.get_children():
			if child is OmniLight3D:
				_torch_lights.append(child)
		var sparks := Effects.make_flame()
		sparks.position = pos + Vector3(0, 0.35, 0)
		add_child(sparks)
