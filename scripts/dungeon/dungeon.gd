class_name Dungeon
extends Node3D
## Procedural arena scene. The server picks a theme + seed; every peer runs
## ProcGen.generate() locally to build a byte-identical map, so only the
## seed (one int) crosses the network. Gameplay (waves, mobs, loot) stays
## server-authoritative exactly as before.
##
## Run handoff (set before change_scene_to_file):
##   next_theme_id / next_seed / next_level_number / saved_player_state

## Multiplayer save: roster collection state.
const SAVE_STATE_TIMEOUT := 3.0
var _save_roster: Array = []
var _save_pending: Dictionary = {}
var _save_base: Dictionary = {}

const PlayerScene := preload("res://scenes/player/player.tscn")
const MobScene := preload("res://scenes/mobs/mob.tscn")
const PickupScene := preload("res://scenes/items/item_pickup.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const DecoyScript := preload("res://scripts/combat/decoy.gd")

const MAX_CONCURRENT := 8
const TOTAL_WAVES := 5
const INTERMISSION_TIME := 10.0
const THEME_ORDER: Array[String] = ["village", "dungeon", "depths", "supermarket", "warlord"]

## Danger model (Phase 3): base tier per theme × depth scaling.
## Single source of truth for mob HP/damage, XP, and loot sell values.
## Risk/reward: picking a harder destination pays more if you survive.
const DANGER_TIERS := {"village": 1, "dungeon": 2, "depths": 3, "supermarket": 1, "warlord": 4}
const TIER_MULT := {1: 1.0, 2: 1.3, 3: 1.7, 4: 2.2}


static func danger_mult(theme_id: String, level_number: int) -> float:
	return float(TIER_MULT[int(DANGER_TIERS.get(theme_id, 1))]) * pow(1.15, float(level_number - 1))


## Theme tint for the NOW ARRIVING banner (Phase 5; mirrors station lamps).
static func arrival_tint(theme_id: String) -> Color:
	match theme_id:
		"village":
			return Color(0.6, 1.0, 0.6)
		"dungeon":
			return Color(0.5, 0.7, 1.0)
		"depths":
			return Color(0.8, 0.4, 0.9)
		"supermarket":
			return Color(1.0, 1.0, 0.95)
		"warlord":
			return Color(1.0, 0.55, 0.25)
	return Color.WHITE

static var next_theme_id: String = "village"
static var next_seed: int = 12345
static var next_level_number: int = 1
static var saved_player_state: Dictionary = {}
## Roster from a continued multiplayer save (empty for fresh runs).
static var continued_roster: Array = []
## Host toggle: allow strangers to join a continued run as fresh characters.
static var continued_open_lobby: bool = false

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
var _construction_check_tick := 0.0
var market_cash_goal := 500
## Per-visit supermarket earnings (server). The gate unlocks on earnings, not
## held cash, so spending at vendors can never re-lock it (Phase 4: cash is
## persistent across the whole run).
var market_earned_visit := 0
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
		market_earned_visit = 0
		wave_state = WaveState.CLEARED  # skip wave logic
		# Spawn the gate (sealed) and checkout immediately.
		if multiplayer.is_server():
			rpc("spawn_portal", _portal_pos(), true)
			_spawn_checkout()
			_spawn_potion_shop()
			# Mason's Cipher: the lockbox sits near the checkout (any cycle).
			rpc("spawn_cipher_lockbox", _portal_pos() + Vector3(9, 0, 0))
	# Mason's Cipher: one parchment note per dungeon level.
	if multiplayer.is_server() and not is_supermarket and not is_warlord:
		rpc("spawn_cipher_plaque", _cipher_plaque_pos())
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
	# Continued run: match the joiner against the saved roster.
	var roster_entry := _find_roster_entry(sender)
	if not continued_roster.is_empty():
		if roster_entry.is_empty() and not continued_open_lobby:
			# Stranger on a roster-locked lobby: reject.
			rpc_id(sender, "reject_join", "This lobby is continuing a saved run (roster-locked).")
			return
		if not roster_entry.is_empty():
			# Returning player: restore their saved class and state.
			class_id = str(roster_entry.get("class_id", class_id))
	peer_classes[sender] = class_id
	_do_spawn(sender, class_id, _next_spawn_point())
	var node := get_player_node(sender)
	if node != null:
		rpc("spawn_player", sender, class_id, node.position)
	# Send the saved state to the rejoiner (server also applies locally).
	if not roster_entry.is_empty():
		var ps: Dictionary = roster_entry.get("player_state", {})
		if not ps.is_empty():
			node.apply_state(ps)
			rpc_id(sender, "apply_continued_state", ps)
		# Warlord: reclaim their faction from AI control.
		if is_warlord:
			_reclaim_faction(sender, int(roster_entry.get("rts_faction", -1)))


## Find a roster entry by Steam ID. Returns {} if not found.
func _find_roster_entry(steam_id: int) -> Dictionary:
	for entry in continued_roster:
		if int(entry.get("steam_id", 0)) == steam_id:
			return entry
	return {}


@rpc("any_peer", "call_local")
func reject_join(reason: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("toast"):
		hud.toast(reason)
	await get_tree().create_timer(2.0).timeout
	NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


@rpc("any_peer", "call_local")
func apply_continued_state(ps: Dictionary) -> void:
	var me := _my_player()
	if me != null:
		me.apply_state(ps)


## A returning player takes their saved Warlord faction back from AI control.
func _reclaim_faction(peer_id: int, faction_id: int) -> void:
	if _rts_manager == null or faction_id < 0:
		return
	if not _rts_manager.factions.has(faction_id):
		return
	_rts_manager.faction_peers[faction_id] = peer_id
	# Remove the AI driver for this faction.
	for child in get_children():
		if child is AIWarlord and child.faction_id == faction_id:
			child.queue_free()
	var node := get_player_node(peer_id)
	if node != null:
		node.set("rts_faction", faction_id)
	rpc("announce", "%s has rejoined the battle!" % NetworkManager.member_name(peer_id))


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
			rpc_id(sender, "spawn_mob", mob.mob_id, mob.data.id, mob.position, mob.hp_scale, mob.dmg_scale, mob.is_elite, mob.reward_scale)
	for p in $Pickups.get_children():
		var pickup := p as ItemPickup
		if pickup != null and not pickup.claimed:
			if pickup.is_key:
				rpc_id(sender, "spawn_key", pickup.position)
			elif pickup.item != null:
				rpc_id(sender, "spawn_pickup", pickup.item.id, pickup.position, pickup.value_mult)
	# Warlord: sync RTS state for late joiners.
	if is_warlord and _rts_manager != null:
		sync_rts_state(sender)


## Send full RTS state to a late-joining client.
func sync_rts_state(target_peer: int) -> void:
	if _rts_manager == null:
		return
	for fid in _rts_manager.factions:
		var fi := int(fid)
		var f: Dictionary = _rts_manager.factions[fi]
		var res: Dictionary = f.get("resources", {})
		var civ: CivData = f.get("civ")
		rpc_id(target_peer, "client_sync_faction", fi,
			_rts_manager.faction_peers.get(fi, -1),
			civ.civ_id if civ else "iron_vanguard",
			int(res.get("wood", 0)), int(res.get("food", 0)),
			int(res.get("gold", 0)), int(res.get("stone", 0)),
			int(f.get("age", 0)))
	for u in get_tree().get_nodes_in_group("rts_units"):
		var uciv: CivData = u.get("civ")
		rpc_id(target_peer, "client_spawn_unit",
			str(u.get("unit_type")), int(u.get("faction")),
			u.global_position, uciv.civ_id if uciv else "iron_vanguard")
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		var bciv: CivData = b.get("civ")
		rpc_id(target_peer, "client_spawn_building",
			int(b.get("faction")), str(b.get("building_type")),
			b.global_position, bciv.civ_id if bciv else "iron_vanguard")


@rpc("any_peer", "call_local")
func client_sync_faction(faction_id: int, peer_id: int, civ_id: String, wood: int, food: int, gold: int, stone: int, age: int) -> void:
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
		# Arrival (Phase 5): fade in from the train ride, dressed banner, brake.
		_local_hud.fade_in(1.5)
		_local_hud.announce("NOW ARRIVING: " + theme.display_name,
			Dungeon.arrival_tint(theme.theme_id))
		AudioManager.sfx("train_brake")


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
	# Warlord: hand the leaver's faction to an AI so the FFA doesn't soft-lock.
	if is_warlord and _rts_manager != null:
		for fid in _rts_manager.faction_peers:
			if int(_rts_manager.faction_peers[fid]) == peer_id:
				var fi := int(fid)
				_rts_manager.faction_peers[fi] = -1  # mark as AI-controlled
				var ai := AIWarlord.new()
				ai.faction_id = fi
				add_child(ai)
				rpc("announce", "%s's faction is now AI-controlled." % _rts_manager.get_civ(fi).display_name)
				break


# --- Level transitions ---

func _difficulty_scale() -> float:
	return pow(1.15, float(level_number - 1)) * NetworkManager.host_difficulty


## Danger multiplier for this level: theme tier × depth. Drives mob HP and
## damage, XP rewards, and loot sell values (risk/reward).
func _danger_mult() -> float:
	return danger_mult(theme.theme_id, level_number)


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


## Mob HP multiplier: danger model (tier × depth) × host difficulty × team
## damage adaptation. At 15 avg damage the adaptation is 1.0x; scales
## linearly beyond that.
func _hp_scale() -> float:
	var adapt := _team_avg_damage() / 15.0
	# Bounded: 0.85x-1.75x (roadmap). Difficulty comes from composition,
	# positioning, elites, and attack cadence — not HP mirroring.
	adapt = clampf(adapt, 0.85, 1.75)
	return _danger_mult() * NetworkManager.host_difficulty * adapt


## Portal exits now lead to the train station pit-stop (Phase 1).
## The station owns the departure timer, the run save, and the hop to the
## next themed level; this just hands off per-peer player state.
func go_to_station() -> void:
	if not multiplayer.is_server() or _advancing:
		return
	_advancing = true
	rpc("go_to_station_net")


@rpc("any_peer", "call_local")
func go_to_station_net() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != NetworkManager.server_id:
		return
	var me := _my_player()
	if me != null:
		# Leaving the supermarket: confiscate supermarket loot (potions stay).
		# Cash persists across the run now (Phase 4) — only loot is taken.
		if theme != null and theme.theme_id == "supermarket":
			var kept: Array = []
			for entry in me.get("inventory"):
				var item = entry["item"]
				if not bool(item.get("supermarket_loot")):
					kept.append(entry)
			me.set("inventory", kept)
		saved_player_state = me.get_state()
		# NOTE: run save + deepest-cycle meta moved to the station departure.
	Station.next_level_number = level_number + 1
	AudioManager.sfx("portal_enter")
	# Deferred: go_to_station_net can run inside the portal's physics
	# callback, and freeing CollisionObjects during physics is illegal.
	get_tree().call_deferred("change_scene_to_file", "res://scenes/station/station.tscn")


# --- Mobs (host only) ---

func _process(delta: float) -> void:
	# Sim clock for the RTS economy (respawns etc.) — tracks time_scale.
	sim_time += delta
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
		if is_warlord and _rts_manager != null:
			_construction_check_tick += delta
			if _construction_check_tick >= 5.0:
				_construction_check_tick = 0.0
				_check_stalled_construction()
			_process_node_respawns()
			_process_river(delta)
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
	var dmg_scale := _danger_mult() * NetworkManager.host_difficulty
	rpc("spawn_mob", _mob_id, data.id, pos, hp_scale, dmg_scale, elite and not data.is_boss, _danger_mult())


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
	if not continued_roster.is_empty():
		# Continued run: pre-register ALL roster factions by saved ID.
		# No-shows become AI immediately; rejoiners reclaim via _reclaim_faction.
		var connected := {}
		for pl in get_tree().get_nodes_in_group("players"):
			connected[int(pl.get_multiplayer_authority())] = pl
		for entry in continued_roster:
			var fid := int(entry.get("rts_faction", -1))
			if fid < 0:
				continue
			var sid := int(entry.get("steam_id", 0))
			var cls := str(entry.get("class_id", "warrior"))
			if connected.has(sid):
				_rts_manager.register_faction(fid, sid, cls)
				connected[sid].set("rts_faction", fid)
			else:
				# No-show: AI controls this faction from the start.
				_rts_manager.register_faction(fid, -1, cls)
				var ai := AIWarlord.new()
				ai.faction_id = fid
				add_child(ai)
			_spawn_faction_base(fid, _faction_spawn_pos(fid))
			faction_id = maxi(faction_id, fid + 1)
	else:
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
	rts_hud.show_guide()

	rpc("announce", "WARLORD'S DOMAIN — Last faction standing wins!")
	rpc("announce", "Press TAB for command view. B to build. Right-click to order units.")

	# Tell clients to build their local RTS stack (manager + camera + HUD).
	for p in get_tree().get_nodes_in_group("players"):
		var pid := p.get_multiplayer_authority()
		if pid != multiplayer.get_unique_id() and multiplayer.get_peers().has(pid):
			var pfaction := int(p.get("rts_faction"))
			var pciv := _rts_manager.get_civ(pfaction).civ_id
			rpc_id(pid, "client_setup_warlord", pfaction, pciv)


## Client-side RTS bootstrap: create local manager, camera, and HUD.
## The server runs the sim; this just gives the client something to render.
@rpc("any_peer", "call_local")
func client_setup_warlord(my_faction: int, my_civ_id: String) -> void:
	if multiplayer.is_server():
		return
	# Only the server should invoke this.
	if multiplayer.get_remote_sender_id() != NetworkManager.server_id:
		return
	print("[Warlord] Client setting up RTS (faction %d)..." % my_faction)
	_rts_manager = RTSManager.new()
	_rts_manager.name = "RTSManager"
	add_child(_rts_manager)
	# Register our faction locally (server will sync resources/state).
	var class_id := _class_from_civ(my_civ_id)
	_rts_manager.register_faction(my_faction, multiplayer.get_unique_id(), class_id)
	var rts_cam := RTSCamera.new()
	rts_cam.name = "RTSCamera"
	rts_cam.add_to_group("rts_camera")
	add_child(rts_cam)
	rts_cam.setup(_rts_manager, my_faction)
	var rts_hud := RTSHUD.new()
	rts_hud.name = "RTSHUD"
	add_child(rts_hud)
	rts_hud.setup(_rts_manager, my_faction)
	# Sync rts_faction onto the local player so _damage_rts_targets runs.
	var me := get_player_node(multiplayer.get_unique_id())
	if me != null:
		me.set("rts_faction", my_faction)


## Server tick: reassign builders to stalled construction, or refund if none available.
func _check_stalled_construction() -> void:
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if not bool(b.get("under_construction")) or bool(b.get("destroyed")):
			continue
		var faction_id := int(b.get("faction"))
		# Is anyone building this?
		var has_builder := false
		for u in get_tree().get_nodes_in_group("rts_units"):
			if int(u.get("faction")) != faction_id:
				continue
			var target = u.get("_build_target")
			if target == b and is_instance_valid(target):
				has_builder = true
				break
		if has_builder:
			continue
		# Find an idle villager to reassign.
		var builder: Node3D = null
		for u in get_tree().get_nodes_in_group("rts_units"):
			if int(u.get("faction")) != faction_id or str(u.get("unit_type")) != "villager":
				continue
			if not bool(u.get("alive")):
				continue
			builder = u
			break
		if builder != null:
			builder.rpc("rpc_order_build", b.get_path())
		else:
			# No builders left: refund and remove the stalled site.
			var btype := str(b.get("building_type"))
			var cost: Dictionary = RTSTuning.get_cost("building_costs", btype, RTSManager.BUILDING_COSTS.get(btype, {}))
			for k in cost:
				_rts_manager.add_resource(faction_id, k, int(cost[k]))
			b.queue_free()


## Server-side build spot validation: spacing from other buildings, not on river.
func _is_valid_build_spot(pos: Vector3) -> bool:
	for b in get_tree().get_nodes_in_group("rts_buildings"):
		if pos.distance_to(b.global_position) < 5.0:
			return false
	if is_on_water(pos):
		return false
	return true


func _faction_spawn_pos(faction_id: int) -> Vector3:
	# Spread factions around the map.
	var angle := TAU * float(faction_id) / float(maxi(2, _rts_manager.factions.size()))
	var radius := RTSTuning.get_float("map", "faction_radius", 30.0)
	return Vector3(cos(angle) * radius, 0, sin(angle) * radius)


func _spawn_faction_base(faction_id: int, pos: Vector3) -> void:
	var civ := _rts_manager.get_civ(faction_id)
	rpc("spawn_rts_base", faction_id, pos, civ.civ_id)
	# Guaranteed starting cluster near the town center (tunable via [map]).
	var cluster := RTSTuning.get_dict("map", "starting_cluster",
		{"wood": 6, "food": 4, "gold": 3, "stone": 2})
	for t in cluster:
		for n in int(cluster[t]):
			var angle := randf() * TAU
			var dist := 8.0 + randf() * 6.0
			var npos := pos + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
			if is_on_water(npos):
				npos = pos + Vector3(cos(angle + PI) * dist, 0, sin(angle + PI) * dist)
			rpc("spawn_rts_node", t, npos)


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
		if int(_rts_manager.faction_peers.get(faction_id, -2)) == -1:  # AI faction
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


## Water material for the river UV scroll effect.
var _river_mat: StandardMaterial3D = null


@rpc("any_peer", "call_local")
func spawn_rts_river() -> void:
	# Visual-only water plane (no collision: units have no pathfinding,
	# so a solid river would trap land units). Group "rts_water" for queries.
	# PlaneMesh at y=0.08 — avoids z-fighting with the ground at y=0.
	var water := StaticBody3D.new()
	water.name = "River"
	water.add_to_group("rts_water")
	# Dark riverbed for depth, just above the ground.
	var bed := MeshInstance3D.new()
	var bedm := PlaneMesh.new()
	bedm.size = Vector2(8.0, 96.0)
	bed.mesh = bedm
	var bedmat := StandardMaterial3D.new()
	bedmat.albedo_color = Color(0.08, 0.16, 0.22, 1.0)
	bed.material_override = bedmat
	bed.position = Vector3(0, 0.02, 0)
	water.add_child(bed)
	# Water surface.
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8.0, 96.0)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.38, 0.65, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = Vector3(0, 0.08, 0)
	water.add_child(mi)
	_river_mat = mat
	$RTS.add_child(water)
	# Decorative reeds along the banks.
	for i in 24:
		var z := randf_range(-44.0, 44.0)
		var side := 1.0 if i % 2 == 0 else -1.0
		var x := side * randf_range(4.5, 6.0)
		_spawn_reed(Vector3(x, 0, z))


## Scroll the river UVs for a subtle flow effect.
func _process_river(delta: float) -> void:
	if _river_mat != null:
		var off := _river_mat.uv1_offset
		off.y += delta * 0.05
		_river_mat.uv1_offset = off


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


## Pending node respawns: {type, due} — server-side only.
var _node_respawns: Array = []
## Simulation clock (seconds). Advanced by _process delta so it tracks
## Engine.time_scale — wall-clock Time.get_ticks_msec() does not.
var sim_time := 0.0


## Server: schedule a node respawn after depletion (faster in later cycles).
func schedule_node_respawn(res_type: String) -> void:
	if not multiplayer.is_server():
		return
	var cycle := (level_number - 1) / THEME_ORDER.size()
	var base := RTSTuning.get_float("map", "respawn_base", 75.0)
	var per_cycle := RTSTuning.get_float("map", "respawn_cycle_reduction", 10.0)
	var min_d := RTSTuning.get_float("map", "respawn_min", 30.0)
	var delay := maxf(min_d, base - per_cycle * float(cycle))
	_node_respawns.append({"type": res_type, "due": sim_time + delay})


func _spawn_resource_nodes() -> void:
	var faction_count := maxi(2, _rts_manager.factions.size())
	var cycle := (level_number - 1) / THEME_ORDER.size()
	# Nodes per resource per faction, +bonus per cycle so late cycles don't thin out.
	var per_res: int = RTSTuning.get_int("map", "nodes_per_resource_per_faction", 8) + RTSTuning.get_int("map", "nodes_cycle_bonus", 2) * cycle
	var types := ["wood", "food", "gold", "stone"]
	for fi in _rts_manager.factions:
		for t in types:
			for n in per_res:
				rpc("spawn_rts_node", t, _random_land_pos(14.0, 42.0))
	# Contested center ring: bonus gold/stone to reward map control.
	for i in RTSTuning.get_int("map", "center_ring_nodes", 12):
		var t: String = "gold" if i % 2 == 0 else "stone"
		rpc("spawn_rts_node", t, _random_land_pos(4.0, 12.0))


## Random position on land (not river), within a radius band.
func _random_land_pos(min_r: float, max_r: float) -> Vector3:
	for attempt in 20:
		var angle := randf() * TAU
		var radius := min_r + randf() * (max_r - min_r)
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if not is_on_water(pos):
			return pos
	var angle2 := randf() * TAU
	return Vector3(cos(angle2) * 20.0, 0, sin(angle2) * 20.0)


func _process_node_respawns() -> void:
	if _node_respawns.is_empty():
		return
	var ready: Array = []
	for entry in _node_respawns:
		if float(entry["due"]) <= sim_time:
			ready.append(entry)
	for entry in ready:
		_node_respawns.erase(entry)
		rpc("spawn_rts_node", str(entry["type"]), _random_land_pos(10.0, 42.0))


@rpc("any_peer", "call_local")
func spawn_rts_node(res_type: String, pos: Vector3) -> void:
	var amounts := RTSTuning.get_dict("map", "node_amounts",
		{"wood": 1000, "food": 800, "gold": 800, "stone": 800})
	var node := RTSResourceNode.new()
	node.setup(res_type, int(amounts.get(res_type, 500)))
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
	# Server-side position validation (client ghost is advisory only).
	if not _is_valid_build_spot(pos):
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
	var b := _spawn_building_local(faction_id, btype, pos, civ.civ_id)
	rpc("client_spawn_building", faction_id, btype, pos, civ.civ_id)
	builder.rpc("rpc_order_build", b.get_path())


@rpc("any_peer", "call_local")
func client_spawn_building(faction_id: int, btype: String, pos: Vector3, civ_id: String) -> void:
	if multiplayer.is_server():
		return
	_spawn_building_local(faction_id, btype, pos, civ_id)


func _spawn_building_local(faction_id: int, btype: String, pos: Vector3, civ_id: String) -> RTSBuilding:
	var civ := CivData.for_civ_id(civ_id)
	var b := RTSBuilding.new()
	b.setup(faction_id, btype, civ)
	b.rts_manager = _rts_manager
	b.position = pos
	$RTS.add_child(b)
	b.start_construction()
	return b


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
		market_earned_visit += total
		SaveManager.add_cash_earned(total)
		SaveManager.check_achievements()
		player.rpc_id(sender, "on_sold", total)
		_check_gate_unlock()


func _check_gate_unlock() -> void:
	if not is_supermarket or not _portal_sealed:
		return
	# Gate integrity: unlock on per-visit EARNINGS, not held cash. Cash is
	# persistent (Phase 4), so a team-cash check would trivialize future gates
	# and spending could re-lock this one. Earnings only grow.
	if gate_unlocked(market_earned_visit, market_cash_goal):
		_portal_sealed = false
		rpc("unlock_portal")
		rpc("announce", "GATE UNLOCKED!")


## Static for testability: the gate opens on per-visit earnings.
static func gate_unlocked(earned: int, goal: int) -> bool:
	return earned >= goal


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
				var dmg_scale := _danger_mult() * NetworkManager.host_difficulty
				var elite := bool(pick["elite"]) and not data.is_boss
				rpc("spawn_mob", _mob_id, data.id, _random_mob_pos(), hp_scale, dmg_scale, elite, _danger_mult())
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
	rpc("spawn_mob", _mob_id, theme.boss_id, pos, _danger_mult() * NetworkManager.host_difficulty, _danger_mult() * NetworkManager.host_difficulty, false, _danger_mult())


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
func spawn_mob(mob_id: int, type_id: String, pos: Vector3, hp_scale: float = 1.0, dmg_scale: float = 1.0, elite: bool = false, reward_scale: float = 1.0) -> void:
	var data := _mob_data(type_id)
	if data == null:
		return
	var m := MobScene.instantiate() as Mob
	m.name = "Mob_%d" % mob_id
	m.setup(mob_id, data, hp_scale, dmg_scale, elite, reward_scale)
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


## Places an architect structure on all peers. Caps are enforced
## deterministically on every peer (same reliable RPC order => same outcome).
@rpc("any_peer", "call_local")
func place_structure(structure_id: String, pos: Vector3, owner: int, rank: int, uid: String) -> void:
	var mine: Array = []
	for n in get_tree().get_nodes_in_group("structures"):
		var s := n as Structure
		if s != null and s.owner_peer == owner and not s.is_queued_for_deletion():
			mine.append(s)
	# Per-type caps: 3 traps; keystones replace (a 2nd keystone despawns the first).
	var same := 0
	for s in mine:
		if (s as Structure).structure_id == structure_id:
			same += 1
	if structure_id == "spike_trap" and same >= 3:
		return
	if structure_id == "keystone":
		for s in mine.duplicate():
			if (s as Structure).structure_id == "keystone":
				(s as Structure).queue_free()
				mine.erase(s)
	# Global cap: evict the oldest non-keystone structure.
	if mine.size() >= Structure.STRUCTURE_CAP:
		var evicted := false
		for s in mine:
			var st := s as Structure
			if st.structure_id != "keystone":
				st.queue_free()
				evicted = true
				break
		if not evicted:
			return
	# Keystone buff: +50% max HP when placed within 6m of a keystone.
	var hp_mult := 1.0
	if Structure.keystone_near(get_tree(), Vector3(pos.x, 0.0, pos.z), owner):
		hp_mult = 1.5
	var st := Structure.new()
	st.setup(structure_id, owner, rank, hp_mult, uid)
	add_child(st)
	st.global_position = Vector3(pos.x, 0.05, pos.z)


## Server: a structure was destroyed. Every peer plays rubble FX and frees
## its local copy (structures are created per-peer via call_local).
@rpc("any_peer", "call_local")
func break_structure(uid: String) -> void:
	for n in get_tree().get_nodes_in_group("structures"):
		var s := n as Structure
		if s != null and s.uid == uid and not s.is_queued_for_deletion():
			Effects.burst(s.get_parent(), s.global_position + Vector3(0, 0.8, 0), Color(0.5, 0.48, 0.45), 12, 4.0)
			AudioManager.sfx("totem_expire", s.global_position)
			s.queue_free()
			return


## Architect Demolish: detonate all of one player's structures. Damage is
## server-side; every peer plays the explosion and frees its copies.
@rpc("any_peer", "call_local")
func demolish_structures(owner: int) -> void:
	var mine: Array = []
	for n in get_tree().get_nodes_in_group("structures"):
		var s := n as Structure
		if s != null and s.owner_peer == owner and not s.is_queued_for_deletion():
			mine.append(s)
	for s in mine:
		var st := s as Structure
		if multiplayer.is_server():
			var dmg := st.max_hp * 0.5
			for m in get_tree().get_nodes_in_group("mobs"):
				var mob := m as Mob
				if mob == null or not mob.alive:
					continue
				if mob.global_position.distance_to(st.global_position) < Structure.DEMOLISH_RADIUS:
					mob.rpc_id(NetworkManager.server_id, "take_damage", dmg, owner, st.global_position)
		st.demolish()


## Spawns a rogue shadow decoy (Double Take trait) on all peers.
@rpc("any_peer", "call_local")
func spawn_decoy(pos: Vector3, owner: int) -> void:
	var decoy: Node3D = DecoyScript.new()
	decoy.setup(owner)
	add_child(decoy)
	decoy.global_position = Vector3(pos.x, 0.05, pos.z)


## Server-side helper for boss summons.
func server_spawn_mob(type_id: String, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_mob_id += 1
	var data := _mob_data(type_id)
	var elite := data != null and not data.is_boss and randf() < 0.10
	rpc("spawn_mob", _mob_id, type_id, pos, _danger_mult() * NetworkManager.host_difficulty, _danger_mult() * NetworkManager.host_difficulty, elite, _danger_mult())


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
func spawn_pickup(item_id: String, pos: Vector3, value_mult: float = 1.0) -> void:
	var item := ItemDB.get_item(item_id)
	if item == null:
		return
	# Danger model: mob drops carry scaled sell values (risk/reward).
	# Shelf loot, keys, and shop stock use the default 1.0.
	if value_mult != 1.0 and item.sell_value > 0:
		item = item.duplicate() as ItemData
		item.sell_value = roundi(float(item.sell_value) * value_mult)
	_pickup_id += 1
	var pickup := PickupScene.instantiate() as ItemPickup
	pickup.name = "Pickup_%d" % _pickup_id
	pickup.value_mult = value_mult
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


## Mason's Cipher: parchment note hiding one poem (one per dungeon level).
@rpc("any_peer", "call_local")
func spawn_cipher_plaque(pos: Vector3) -> void:
	var plaque := CipherPlaque.new()
	plaque.name = "CipherPlaque"
	plaque.position = pos
	$Pickups.add_child(plaque)


## Mason's Cipher: brass lockbox on the supermarket level.
@rpc("any_peer", "call_local")
func spawn_cipher_lockbox(pos: Vector3) -> void:
	var box := CipherLockbox.new()
	box.name = "CipherLockbox"
	box.position = pos
	$Pickups.add_child(box)


## Random floor spot for the cipher note, away from the spawn area.
## Server-side only.
func _cipher_plaque_pos() -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = _server_rng.randi()
	var spots := ProcGen.key_spots(_layout, 1, rng)
	if spots.is_empty():
		return Vector3(6, 0.6, 6)
	var p: Vector3 = spots[0]
	return Vector3(p.x, 0.6, p.z)


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
	go_to_station()


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


# --- Multiplayer save ---

## Save a multiplayer run: collect each peer's state, then write the roster.
## Called by the server on level transition and from the host's pause menu.
func save_multiplayer_run(theme_id: String, level_number: int, level_seed: int) -> void:
	if not multiplayer.is_server():
		return
	_save_base = {
		"theme_id": theme_id,
		"level_number": level_number,
		"seed": level_seed,
		"is_multiplayer": true,
		"host_difficulty": NetworkManager.host_difficulty,
		"host_loot_mult": NetworkManager.host_loot_mult,
		"lobby": {
			"max_players": NetworkManager.MAX_PLAYERS,
			"lobby_name": "%s's Dungeon" % SteamManager.persona_name if SteamManager.initialized else "Dungeon",
		},
	}
	_save_roster.clear()
	_save_pending.clear()
	# Host's own state first.
	var me := _my_player()
	if me != null:
		_save_roster.append(_roster_entry(multiplayer.get_unique_id(), me))
	# Ask each connected peer for their state.
	for pid in multiplayer.get_peers():
		_save_pending[pid] = true
	if _save_pending.is_empty():
		_write_multiplayer_save()
		return
	rpc("rpc_request_save_state")
	# 3s window, then write with whoever responded.
	await get_tree().create_timer(SAVE_STATE_TIMEOUT).timeout
	_mark_missing_disconnected()
	_write_multiplayer_save()


func _roster_entry(steam_id: int, player_node: Node) -> Dictionary:
	var rts_faction := -1
	if is_warlord and _rts_manager != null:
		for fid in _rts_manager.faction_peers:
			if _rts_manager.faction_peers[fid] == steam_id:
				rts_faction = int(fid)
	return {
		"steam_id": steam_id,
		"player_name": NetworkManager.member_name(steam_id),
		"class_id": str(player_node.get("class_id")),
		"player_state": player_node.get_state(),
		"rts_faction": rts_faction,
		"is_host": steam_id == multiplayer.get_unique_id(),
	}


func _mark_missing_disconnected() -> void:
	for pid in _save_pending:
		var node := get_player_node(pid)
		var entry := _roster_entry(pid, node) if node != null else {
			"steam_id": pid, "player_name": NetworkManager.member_name(pid),
			"class_id": "warrior", "player_state": {}, "rts_faction": -1, "is_host": false,
		}
		entry["disconnected"] = true
		_save_roster.append(entry)


func _write_multiplayer_save() -> void:
	_save_base["roster"] = _save_roster
	# class_id at top level for backwards compat (host's class).
	if not _save_roster.is_empty():
		_save_base["class_id"] = _save_roster[0].get("class_id", "warrior")
		_save_base["player_state"] = _save_roster[0].get("player_state", {})
	SaveManager.save_run(_save_base)


@rpc("any_peer", "call_local")
func rpc_request_save_state() -> void:
	if multiplayer.is_server():
		return
	var me := _my_player()
	if me == null:
		return
	var state := {
		"steam_id": multiplayer.get_unique_id(),
		"player_name": SteamManager.persona_name if SteamManager.initialized else "Player",
		"class_id": str(me.get("class_id")),
		"player_state": me.get_state(),
		"rts_faction": -1,
		"is_host": false,
	}
	rpc_id(1, "rpc_submit_save_state", state)


@rpc("any_peer")
func rpc_submit_save_state(state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _save_pending.has(sender):
		_save_pending.erase(sender)
		_save_roster.append(state)


## A player died; the server checks if the whole party wiped.
@rpc("any_peer", "call_local")
func notify_player_died() -> void:
	if not multiplayer.is_server():
		return
	# Defer one frame so the death flag settles.
	await get_tree().process_frame
	check_party_wipe()


## If all connected players are dead, the run is over: clear the save.
func check_party_wipe() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return  # solo handled in player.die()
	var connected := {}
	for pid in multiplayer.get_peers():
		connected[int(pid)] = true
	connected[multiplayer.get_unique_id()] = true
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		# Only count connected players; disconnected don't block the wipe.
		if p != null and connected.has(p.get_multiplayer_authority()):
			if bool(p.get("alive")):
				return  # someone's still standing
	SaveManager.clear_run()
	rpc("announce", "Party wiped! The run has been erased.")
