extends Node
## Issue #103 validation driver: boots the REAL Misty Docks dungeon
## (heightmap terrain integration) and plays a scripted run through it:
## spawn on terrain -> walk to a farm plot (till + plant) -> dock
## merchant (E opens the vendor) -> fishing pier (claim + cast + reel)
## -> out the station-annex doorway and back (no step at the door).
## Also asserts the terrain's structural guarantees: only layout ponds
## are water, the doorway strip is flat at y=0, generation is
## deterministic, and a wave mob spawns standing on the terrain.
##
## Run checks + (optionally) screenshots under Xvfb (no --headless:
## the E-interact path needs a capturable mouse, which the headless
## display driver cannot provide):
##   xvfb-run godot --path . res://scenes/terrain/docks_integration_check.tscn -- --seed 424242
##   xvfb-run godot --path . res://scenes/terrain/docks_integration_check.tscn -- --mode=shots
##
## This is a test harness only: it drives the real player with synthetic
## key input through the game's own interact path, exactly like the
## tools/sim harness boots real levels. Nothing here ships in gameplay.

var _seed := 424242
var _mode := "run"
var _out_dir := "/home/hatch/workspace/docks_integration_shots"
var _pass := 0
var _fail := 0
var _dungeon: Dungeon = null
var _terrain: HeightmapTerrain = null
var _player: Player = null


func _ready() -> void:
	_parse_args()
	# CRT off for clean screenshots (same pattern as terrain_test.gd).
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	# Boot the real dungeon, sim-harness style (await a frame first:
	# the root is busy setting up this scene during _ready).
	await get_tree().process_frame
	NetworkManager.selected_class_id = "warrior"
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "misty_docks"
	Dungeon.next_seed = _seed
	Dungeon.next_level_number = 1
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	_dungeon = packed.instantiate() as Dungeon
	get_tree().root.add_child(_dungeon)
	get_tree().current_scene = _dungeon
	for i in 12:
		await get_tree().physics_frame
	_terrain = _dungeon.get("_terrain") as HeightmapTerrain
	await _run_checks()
	if _mode == "shots":
		await _take_shots()
	print("[DOCKS] SUMMARY: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


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
		elif i + 1 < args.size():
			val = args[i + 1]
			i += 1
		if key == "--seed":
			_seed = int(val)
		elif key == "--mode":
			_mode = val
		elif key == "--out":
			_out_dir = val
		i += 1


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("[DOCKS] PASS: ", label)
	else:
		_fail += 1
		print("[DOCKS] FAIL: ", label)


func _run_checks() -> void:
	var theme := _dungeon.theme
	_check(theme != null and theme.use_heightmap_terrain, "docks theme flag use_heightmap_terrain on")
	# A non-opted theme stays flat (themes flip on one at a time in
	# the #103 set: village #118, the dungeon #120, the depths #121
	# and apex #122 have flipped; warlord is the flat exemplar
	# until its own issue lands (#123) — this pin moves to the next
	# still-off theme when warlord flips).
	var warlord_theme := load("res://data/levels/theme_warlord.tres") as LevelTheme
	_check(warlord_theme != null and not warlord_theme.use_heightmap_terrain, "warlord theme flag stays off")
	_check(_terrain != null, "heightmap terrain built instead of flat floor")
	_check(_dungeon.get_node_or_null("Floor") == null, "no flat Floor node on terrain docks")
	_check(_dungeon.get_node_or_null("TerrainDoorApron") != null, "doorway apron built")
	if _terrain == null:
		return
	# Cycle-scaling path duplicates the theme; the flag must survive.
	var dup := theme.duplicate() as LevelTheme
	_check(dup.use_heightmap_terrain, "flag survives theme.duplicate() (cycle scaling)")
	# Dungeon helper == terrain sampler.
	var worst := 0.0
	for p in [Vector3(0, 0, 0), Vector3(10, 0, -6), Vector3(-20, 0, 14), Vector3(27, 0, 27)]:
		worst = maxf(worst, absf(_dungeon.ground_height_at(p) - _terrain.get_ground_height(p)))
	_check(worst < 0.001, "dungeon.ground_height_at matches terrain sampler (worst %.4f)" % worst)
	await _check_water_discipline()
	_check_door_flatness()
	await _check_determinism()
	# --- Player spawn ---
	var players := get_tree().get_nodes_in_group("players")
	_check(not players.is_empty(), "local player spawned")
	if players.is_empty():
		return
	_player = players[0] as Player
	# Test scaffolding: keep the walker alive through wave contact.
	_player.set("hp", 100000.0)
	for i in 90:
		await get_tree().physics_frame
	var sp := _dungeon.spawn_points[0]
	_check(absf(sp.y - _terrain.get_ground_height(sp)) < 0.01,
		"spawn point grounded (y=%.3f)" % sp.y)
	_check(_player.is_on_floor(), "player standing on terrain after settle")
	var dev := _player.global_position.y - _terrain.get_ground_height(_player.global_position)
	_check(absf(dev) <= 0.75, "player y tracks terrain at spawn (dev %.3f)" % dev)
	print("[DOCKS] player at ", _player.global_position, " ground ", _terrain.get_ground_height(_player.global_position))
	# --- A wave mob spawns on the terrain (real spawn path) ---
	var mpos := _dungeon._random_mob_pos()
	_dungeon.spawn_mob(9001, "goblin", mpos)
	for i in 30:
		await get_tree().physics_frame
	var mob := _dungeon.get_node_or_null("Mobs/Mob_9001")
	_check(mob != null, "goblin spawned via spawn_mob")
	if mob != null:
		for i in 60:
			await get_tree().physics_frame
		var mdev := (mob as Node3D).global_position.y - _terrain.get_ground_height((mob as Node3D).global_position)
		_check(absf(mdev) <= 0.75, "mob stands on terrain (dev %.3f)" % mdev)
	# Test scaffolding: park the wave director and clear the field so
	# later traversal legs measure terrain, not mob body-blocking. The
	# spawn/grounding behavior is already proven above.
	_dungeon.set("wave_timer", 99999.0)
	_dungeon.set("mobs_to_spawn", 0)
	_clear_mobs()
	# --- Walk: spawn -> farm plot, till + plant ---
	var plot := _dungeon.get_node_or_null("FarmPlot_0") as FarmPlot
	_check(plot != null, "farm plot 0 exists")
	var st := await _walk_to(plot.global_position, 1.4, 60.0)
	_report_walk("spawn->farm plot", st)
	await _press_e()
	if plot.plot_state != "tilled":
		_diagnose_interact(plot)
	_check(plot.plot_state == "tilled", "farm: E tills (state=%s)" % plot.plot_state)
	await _press_e()
	_check(plot.plot_state == "planted", "farm: E plants with starter seed (state=%s)" % plot.plot_state)
	# --- Walk: plot -> merchant, E opens the vendor ---
	var merch := _dungeon.get_node_or_null("DockMerchant")
	_check(merch != null, "dock merchant exists")
	st = await _walk_to((merch as Node3D).global_position, 1.4, 60.0)
	_report_walk("plot->merchant", st)
	await _press_e()
	var hud = _dungeon.get("_local_hud")
	# NOTE (pre-existing #102 quirk, terrain-independent): show_dock_vendor
	# sets dock_vendor_open=true, then _open_cipher_popup's internal
	# close_cipher_popup() resets it to false — so the flag never reads
	# true. The faithful observable is the open cipher popup carrying
	# the "Dock Merchant" panel.
	var vendor_shown := hud != null and bool(hud.get("cipher_popup_open")) \
		and _popup_has_text(hud.get("_cipher_popup") as Control, "Dock Merchant")
	if not vendor_shown:
		_diagnose_interact(merch as Node3D)
	_check(vendor_shown, "merchant: E opens dock vendor popup")
	if hud != null and hud.has_method("close_cipher_popup"):
		hud.close_cipher_popup()
	# --- Walk: merchant -> fishing pier, claim + cast + reel ---
	var spot := _dungeon.get_node_or_null("FishingSpot_0") as FishingSpot
	_check(spot != null, "fishing spot 0 exists")
	# Test scaffolding (issue #104 Phase 3): claiming a spot requires
	# the fishing rod EQUIPPED in the TOOL slot — the claim is refused
	# without it. Grant + equip the rod before the pier leg so the
	# claim runs under the same rules as a real player.
	_player.receive_item("fishing_rod")
	var rod_idx := -1
	var inv: Array = _player.get("inventory")
	for i in inv.size():
		var it = (inv[i] as Dictionary).get("item")
		if it != null and str(it.get("id")) == "fishing_rod":
			rod_idx = i
	if rod_idx >= 0:
		_player.equip_stack(rod_idx)
	_check(_player.has_rod_equipped(),
		"fishing: rod equipped in TOOL slot (spot-claim gate)")
	_check(absf(spot.water_point.y - _terrain.water_level) < 0.001,
		"fishing water_point.y == terrain water level (%.2f)" % spot.water_point.y)
	st = await _walk_to(spot.global_position, 1.4, 60.0)
	_report_walk("merchant->fishing pier", st)
	FishingSpot.debug_wait_override = 0.8
	FishingSpot.debug_catch_roll = 0.9 # plain minnow
	# Freeze the spot's clock (the suite's own seam): with real time,
	# the 0.8s bite wait + 1.2s reel window can fully elapse inside
	# this leg's frame-counted waits on a slow machine — the session
	# then reads as claimed-but-idle (a miss keeps the claim), which
	# is exactly how this leg used to fail downstream of the rod fix.
	FishingSpot.debug_now_msec = 100000
	await _press_e()
	# The claim+cast round-trip settles over the following frames;
	# poll for the session like the bite-cue wait below does, rather
	# than sampling once (a fixed sample races the interact dispatch).
	var session_up := false
	for i in 120: # up to ~2s of process frames
		await get_tree().process_frame
		if spot.occupied_by == 1 and spot.is_session_active_for(1):
			session_up = true
			break
	_check(session_up,
		"fishing: E claims + casts (occupied_by=%d)" % spot.occupied_by)
	var fishing_set := false
	for i in 120:
		await get_tree().process_frame
		if bool(_player.get("is_fishing")):
			fishing_set = true
			break
	_check(fishing_set, "fishing: player is_fishing")
	# Advance the frozen clock past the 0.8s bite wait (inside the
	# 1.2s reel window): the next spot _process tick flips to BITING.
	FishingSpot.debug_now_msec = 100000 + 900
	var bite := false
	for i in 360: # up to ~6s of process frames for the bite cue
		await get_tree().process_frame
		if int(spot.get("_session_state")) == FishingSpot.SessionState.BITING:
			bite = true
			break
	_check(bite, "fishing: bite cue fired")
	await _press_e() # reel
	for i in 10:
		await get_tree().physics_frame
	var fish_held := _inv_count("fish_minnow")
	var fish_stock: int = DockEconomy.stock_count(1, "fish_minnow")
	_check(fish_held >= 1 or fish_stock >= 1,
		"fishing: catch landed (inv=%d stock=%d)" % [fish_held, fish_stock])
	FishingSpot.debug_wait_override = -1.0
	FishingSpot.debug_catch_roll = -1.0
	FishingSpot.debug_now_msec = -1
	# --- Walk: pier -> annex doorway -> hall, and back (no step) ---
	# Route to a staging point on the door axis first (BFS), then run
	# straight through the doorway gap; the no-step measurement only
	# counts the crossing window around the arena edge.
	var layout := _dungeon.get("_layout") as LevelLayout
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var half := layout.arena_half_size()
	var staging := Vector3(ax, 0, -half + 3.0)
	st = await _walk_to(staging, 1.2, 60.0)
	_report_walk("pier->door staging", st)
	var door_out := Vector3(ax, 0, -half - 5.5)
	st = await _walk_to(door_out, 1.6, 30.0, true, Vector2(-half - 3.0, -half + 3.0))
	_report_walk("staging->annex hall (through door)", st)
	_check(st["max_abs_y"] <= 0.5,
		"annex: no step crossing the doorway (max |y| in window %.3f)" % st["max_abs_y"])
	st = await _walk_to(staging, 1.2, 30.0, true, Vector2(-half - 3.0, -half + 3.0))
	_report_walk("annex hall->staging (back out)", st)
	_check(st["max_abs_y"] <= 0.5,
		"annex: no step on re-entry (max |y| in window %.3f)" % st["max_abs_y"])
	var back := Vector3(_dungeon.spawn_points[0].x, 0, _dungeon.spawn_points[0].z)
	st = await _walk_to(back, 2.0, 60.0)
	_report_walk("staging->spawn (return)", st)


func _check_water_discipline() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var violations := 0
	var wet := 0
	var x := -28.0
	while x <= 28.0:
		var z := -28.0
		while z <= 28.0:
			var p := Vector3(x, 0, z)
			if _terrain.is_water(p):
				wet += 1
				var near_pond := false
				for pd in layout.ponds:
					var pond: Dictionary = pd
					var c: Vector3 = pond["center"]
					if Vector2(p.x - c.x, p.z - c.z).length() <= float(pond["radius"]) + 1.25:
						near_pond = true
						break
				if not near_pond:
					violations += 1
			z += 1.0
		x += 1.0
	_check(violations == 0, "only layout ponds are water (%d wet samples, %d violations)" % [wet, violations])
	for pd in layout.ponds:
		var pond: Dictionary = pd
		var c: Vector3 = pond["center"]
		var h := _terrain.get_ground_height(c)
		_check(h <= _terrain.water_level - 0.25,
			"pond basin carved below water plane (center h=%.2f, water=%.2f)" % [h, _terrain.water_level])


func _check_door_flatness() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var half := layout.arena_half_size()
	var h_door := _terrain.get_ground_height(Vector3(ax, 0, -half))
	var h_in := _terrain.get_ground_height(Vector3(ax, 0, -half + 2.5))
	_check(absf(h_door) <= 0.15, "terrain meets annex floor at door (h=%.3f)" % h_door)
	_check(absf(h_in) <= 0.3, "door approach flat (h=%.3f)" % h_in)


func _check_determinism() -> void:
	var t2 := HeightmapTerrain.new()
	t2.map_points = _terrain.map_points
	t2.cell_size = _terrain.cell_size
	t2.terrain_seed = _terrain.terrain_seed
	t2.noise_frequency = _terrain.noise_frequency
	t2.amplitude = _terrain.amplitude
	t2.height_offset = _terrain.height_offset
	t2.water_level = _terrain.water_level
	t2.pond_depth = _terrain.pond_depth
	t2.smooth_passes = _terrain.smooth_passes
	t2.flatten_radius = _terrain.flatten_radius
	t2.poi_points = _terrain.poi_points.duplicate()
	t2.flatten_targets = _terrain.flatten_targets.duplicate()
	t2.pond_specs = _terrain.pond_specs.duplicate()
	add_child(t2)
	t2.generate()
	_check(t2.heights_copy() == _terrain.heights_copy(),
		"terrain generation deterministic (identical heights, seed %d)" % _terrain.terrain_seed)
	t2.queue_free()
	await get_tree().process_frame


func _report_walk(label: String, st: Dictionary) -> void:
	_check(bool(st["arrived"]), "walk %s: arrived" % label)
	_check(float(st["max_dev"]) <= 1.25,
		"walk %s: stayed on ground (max dev %.2f)" % [label, float(st["max_dev"])])
	_check(float(st["min_y"]) > -1.0,
		"walk %s: never fell through (min y %.2f)" % [label, float(st["min_y"])])
	print("[DOCKS] walk %s: floor ratio %.2f, frames %d" % [label, float(st["floor_ratio"]), int(st["frames"])])


## Drives the real player with synthetic W input (the player's own
## physics reads physical keys), steering body yaw at each waypoint.
## Waypoints route over layout FLOOR cells (BFS) unless `direct` is set
## (the annex corridor lives outside the grid; its strip is pre-cleared).
func _walk_to(target: Vector3, stop_dist: float, max_seconds: float, direct := false, step_window := Vector2(1, -1)) -> Dictionary:
	var stats := {"arrived": false, "max_dev": 0.0, "min_y": 999.0,
		"max_abs_y": 0.0, "floor_ratio": 0.0, "frames": 0}
	var waypoints: Array[Vector3] = []
	if direct:
		waypoints.append(target)
	else:
		waypoints = _path_points(_player.global_position, target)
		waypoints.append(target)
	var budget := int(max_seconds * 60.0)
	var floor_frames := 0
	_key(KEY_W, true)
	for wi in waypoints.size():
		var wp: Vector3 = waypoints[wi]
		var is_final := wi == waypoints.size() - 1
		var reach := stop_dist if is_final else 1.1
		var best := 1e9
		var stall_frames := 0
		while int(stats["frames"]) < budget:
			await get_tree().physics_frame
			stats["frames"] = int(stats["frames"]) + 1
			if int(stats["frames"]) % 240 == 0:
				_clear_mobs() # scaffolding: keep traversal legs mob-free
			var pp := _player.global_position
			var to := Vector3(wp.x - pp.x, 0.0, wp.z - pp.z)
			var dist := to.length()
			if dist <= reach:
				if is_final:
					stats["arrived"] = true
				break
			if dist < best - 0.3:
				best = dist
				stall_frames = 0
			else:
				stall_frames += 1
				if stall_frames > 300: # 5s without progress: snagged
					break
			var yaw := atan2(-to.x, -to.z)
			_player.rotation.y = yaw
			_player.set("_yaw", yaw)
			var g := _terrain.get_ground_height(pp)
			stats["max_dev"] = maxf(float(stats["max_dev"]), absf(pp.y - g))
			stats["min_y"] = minf(float(stats["min_y"]), pp.y)
			# No-step metric: whole leg, or only inside the z window
			# when one is given (the doorway crossing).
			if step_window.x > step_window.y or (pp.z >= step_window.x and pp.z <= step_window.y):
				stats["max_abs_y"] = maxf(float(stats["max_abs_y"]), absf(pp.y))
			if _player.is_on_floor():
				floor_frames += 1
		if is_final or int(stats["frames"]) >= budget:
			break
	_key(KEY_W, false)
	stats["floor_ratio"] = float(floor_frames) / maxf(1.0, float(stats["frames"]))
	return stats


func _path_points(from_w: Vector3, to_w: Vector3) -> Array[Vector3]:
	var layout := _dungeon.get("_layout") as LevelLayout
	var start := layout.world_to_cell(from_w)
	var goal := layout.world_to_cell(to_w)
	if not layout.is_floor(goal.x, goal.y):
		return []
	var prev := {}
	var queue: Array[Vector2i] = [start]
	prev[start] = start
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == goal:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if prev.has(n) or not layout.is_floor(n.x, n.y):
				continue
			prev[n] = c
			queue.append(n)
	if not prev.has(goal):
		return []
	var cells: Array[Vector3] = []
	var cur := goal
	while cur != start:
		cells.append(layout.cell_to_world(cur.x, cur.y))
		cur = prev[cur]
	cells.reverse()
	# Greedy line-of-sight prune so the walk is not a grid zigzag.
	var pts: Array[Vector3] = []
	var anchor := from_w
	var i := 0
	while i < cells.size():
		var j := cells.size() - 1
		while j > i and not _segment_clear(anchor, cells[j], layout):
			j -= 1
		pts.append(cells[j])
		anchor = cells[j]
		i = j + 1
	return pts


func _segment_clear(a: Vector3, b: Vector3, layout: LevelLayout) -> bool:
	var dist := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := int(ceil(dist / 0.5))
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / float(steps))
		var c := layout.world_to_cell(p)
		if not layout.is_floor(c.x, c.y):
			return false
	return true


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _press_e() -> void:
	# The interact path requires a captured mouse (player._input gate).
	# NOTE: only works under a real display server (Xvfb) — the headless
	# display driver silently ignores mouse_mode, so this check suite
	# runs under xvfb-run, like the screenshot drivers.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_key(KEY_E, true)
	for i in 5:
		await get_tree().process_frame
	_key(KEY_E, false)
	for i in 5:
		await get_tree().process_frame


func _clear_mobs() -> void:
	var holder := _dungeon.get_node_or_null("Mobs")
	if holder != null:
		for m in holder.get_children():
			m.queue_free()


## True if any Label in the popup subtree carries the given text.
func _popup_has_text(root_node: Control, needle: String) -> bool:
	if root_node == null:
		return false
	if root_node is Label and (root_node as Label).text == needle:
		return true
	for child in root_node.get_children():
		if child is Control and _popup_has_text(child as Control, needle):
			return true
	return false


## Diagnostic dump for a failed E-interact: where the player stands vs
## the target, what the player's own interact scan sees, and the gates.
func _diagnose_interact(target: Node3D) -> void:
	var dist := _player.global_position.distance_to(target.global_position)
	var nearest = _player.call("_nearest_interact_node")
	var hud = _player.get("hud")
	print("[DOCKS] diag: dist=%.2f nearest=%s mouse_mode=%d hud=%s cipher=%s paused=%s reading=%s" % [
		dist, str(nearest), Input.mouse_mode, str(hud),
		str(hud.get("cipher_popup_open")) if hud != null else "?",
		str(hud.get("is_paused")) if hud != null else "?",
		str(_player.get("_reading_board"))])


func _inv_count(item_id: String) -> int:
	var n := 0
	for entry in _player.get("inventory"):
		var item = entry["item"]
		if item != null and str(item.get("id")) == item_id:
			n += int(entry.get("count", 1))
	return n


func _take_shots() -> void:
	var mk := DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[DOCKS] shots dir ", _out_dir, " mkdir err=", mk)
	# Photography only (driver-local): Misty Docks plays at night in
	# heavy fog, which makes terrain inspection impossible. Lift fog +
	# ambient and add a work light for the two captures; hide the HUD.
	# None of this exists in a normal game boot.
	var hud = _dungeon.get("_local_hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	for child in _dungeon.get_children():
		if child is WorldEnvironment:
			var env := (child as WorldEnvironment).environment
			env.fog_enabled = false
			env.ambient_light_energy = 1.1
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-52, -38, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	# Overview: whole arena + annex roofline.
	cam.position = Vector3(36, 40, 38)
	cam.look_at(Vector3(0, 0, -6), Vector3.UP)
	await _snap("docks_terrain_overview.png")
	# Ground level: hover over the first pond looking back at its
	# pier, the fishing spot, and the shore props behind them.
	var spot := _dungeon.get_node_or_null("FishingSpot_0") as Node3D
	var layout := _dungeon.get("_layout") as LevelLayout
	if spot != null and not layout.ponds.is_empty():
		var center: Vector3 = (layout.ponds[0] as Dictionary)["center"]
		var to_spot := spot.global_position - center
		to_spot.y = 0.0
		var dist := to_spot.length()
		to_spot = to_spot.normalized()
		cam.position = center - to_spot * dist * 0.55 + Vector3(0, 2.6, 0)
		var clearance := _terrain.get_ground_height(cam.position) + 1.2
		cam.position.y = maxf(cam.position.y, clearance)
		cam.look_at(Vector3(spot.global_position.x,
				spot.global_position.y + 0.6, spot.global_position.z), Vector3.UP)
		await _snap("docks_terrain_ground.png")
	print("[DOCKS] shots saved to ", _out_dir)


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_dir + "/" + file_name)
	print("[DOCKS] snap ", file_name, " size=", img.get_size(), " err=", err)
