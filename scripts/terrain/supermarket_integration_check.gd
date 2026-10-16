extends Node
## Issue #119 validation driver: boots the REAL MegaMart Supermarket
## dungeon (heightmap terrain, parameterized LevelTheme profile) and
## plays a scripted run through it: spawn on terrain -> a goblin
## spawns grounded and hunts on the terrain -> obstacle collision
## boxes seated by the footprint rule -> long traversals (floor-
## contact aggregate) -> out the station-annex doorway and back (no
## step at the door). Also asserts the theme's structural guarantees:
## DRY (water parked at -1.00, zero wet samples), sampled max grade
## <= 55% outside flattened POIs/footprints (design expectation ~5%:
## amp 0.15 near-zero relief), tint ramp compressed (no banding),
## deterministic generation, generation-time comparison against the
## Docks profile, and the door apron/flatten contract.
##
## Harness discipline (the F-4 template): every effect that resolves
## over frames is POLLED with a budget, never single-sampled; timed
## mechanics would run on frozen debug clocks. This theme's loop has
## no E-interact legs (no fishing/farm/vendor here). Two supermarket
## refinements: routing keeps one cell of clearance from obstacle
## cells (dense shelf aisles), and routed legs get one re-plan retry
## against physics-contact wedge variance (logged when used).
##
## Run checks + (optionally) screenshots under Xvfb:
##   xvfb-run godot --path . res://scenes/terrain/supermarket_integration_check.tscn -- --seed 424242
##   xvfb-run godot --path . res://scenes/terrain/supermarket_integration_check.tscn -- --mode=shots
##
## This is a test harness only. Nothing here ships in gameplay.

var _seed := 424242
var _mode := "run"
var _out_dir := "/home/hatch/workspace/mart119_shots"
var _pass := 0
var _fail := 0
var _dungeon: Dungeon = null
var _terrain: HeightmapTerrain = null
var _player: Player = null
var _floor_frames_total := 0
var _frames_total := 0


func _ready() -> void:
	_parse_args()
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	await get_tree().process_frame
	NetworkManager.selected_class_id = "warrior"
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "supermarket"
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
	print("[MART] SUMMARY: %d passed, %d failed" % [_pass, _fail])
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
		print("[MART] PASS: ", label)
	else:
		_fail += 1
		print("[MART] FAIL: ", label)


func _run_checks() -> void:
	var theme := _dungeon.theme
	_check(theme != null and theme.use_heightmap_terrain, "supermarket theme flag use_heightmap_terrain on")
	_check(_terrain != null, "heightmap terrain built instead of flat floor")
	_check(_dungeon.get_node_or_null("Arena/Floor") == null, "no flat Floor node on terrain supermarket")
	_check(_dungeon.get_node_or_null("Arena/TerrainDoorApron") != null, "doorway apron built")
	# Issue #138 Phase 3: seed 1 IS the supermarket pin — the
	# dungeon must have loaded the baked scene there, and must NOT
	# off it. (The supermarket bake ships heights-mode: the surface
	# is regenerated from LevelData heights at adoption.)
	if _seed == LevelData.pinned_seed("supermarket"):
		_check(str(_dungeon.get("_baked_hash")) == LevelData.shipped_hash("supermarket"),
			"baked path engaged at the pinned seed (hash %s)" % str(_dungeon.get("_baked_hash")).substr(0, 8))
		_check(_dungeon.get_node_or_null("LevelData") != null,
			"adopted LevelData rides under the baked dungeon")
	else:
		_check(str(_dungeon.get("_baked_hash")) == "",
			"procgen path at unpinned seed %d (no baked hash)" % _seed)
	if _terrain == null:
		return
	# Profile actually carried from the theme (issue #119 params).
	_check(absf(_terrain.amplitude - 0.15) < 0.001 and absf(_terrain.noise_frequency - 0.050) < 0.0001
		and absf(_terrain.height_offset - 0.08) < 0.001 and absf(_terrain.water_level - (-1.00)) < 0.001,
		"terrain profile from theme (amp %.2f freq %.3f off %.2f water %.2f)" % [
			_terrain.amplitude, _terrain.noise_frequency, _terrain.height_offset, _terrain.water_level])
	# Tint ramp anchor carried from the theme: the design floor
	# offset - amp/2 = 0.08 - 0.075 = 0.005, NOT the parked water
	# level (which would pin the ramp at t=1).
	_check(not is_nan(_terrain.tint_anchor) and absf(_terrain.tint_anchor - 0.005) < 0.001,
		"tint anchor from theme (design floor %.3f)" % _terrain.tint_anchor)
	var dup := theme.duplicate() as LevelTheme
	_check(dup.use_heightmap_terrain and absf(dup.terrain_amplitude - 0.15) < 0.001,
		"flag + profile survive theme.duplicate() (cycle scaling)")
	# Dungeon helper == terrain sampler.
	var worst := 0.0
	for p in [Vector3(0, 0, 0), Vector3(10, 0, -6), Vector3(-20, 0, 14), Vector3(27, 0, 27)]:
		worst = maxf(worst, absf(_dungeon.ground_height_at(p) - _terrain.get_ground_height(p)))
	_check(worst < 0.001, "dungeon.ground_height_at matches terrain sampler (worst %.4f)" % worst)
	_check_dry()
	_check_grade()
	_check_door_flatness()
	_check_obstacle_seating()
	await _check_determinism_and_perf()
	# --- Player spawn ---
	var players := get_tree().get_nodes_in_group("players")
	_check(not players.is_empty(), "local player spawned")
	if players.is_empty():
		return
	_player = players[0] as Player
	# Test scaffolding: keep the walker alive through mob contact.
	_player.set("hp", 100000.0)
	for i in 90:
		await get_tree().physics_frame
	var sp := _dungeon.spawn_points[0]
	var sdev := absf(sp.y - _terrain.get_ground_height(sp))
	_check(sdev < 0.001, "spawn deviation %.3f (grounded spawn point)" % sdev)
	_check(_player.is_on_floor(), "player standing on terrain after settle")
	var dev := _player.global_position.y - _terrain.get_ground_height(_player.global_position)
	_check(absf(dev) <= 0.75, "player y tracks terrain at spawn (dev %.3f)" % dev)
	print("[MART] player at ", _player.global_position, " ground ", _terrain.get_ground_height(_player.global_position))
	# Park the wave director and clear the field: traversal + mob legs
	# measure terrain, not mob body-blocking. Supermarket ALSO has an
	# ambient spawner (_process_supermarket: a market mob every 2s up
	# to a cap, plus loot ticks) that the wave parking does not touch
	# — freeze its ticks too, or the cleared field refills within
	# seconds and the ambient mobs swarm the walker (observed: a
	# six-mob pile pinning the player mid-arena, velocity zero, a Mob
	# in the player's slide colliders). The docks/village themes have
	# no ambient spawner, which is why their checks never needed this.
	_dungeon.set("wave_timer", 99999.0)
	_dungeon.set("mobs_to_spawn", 0)
	_dungeon.set("_market_spawn_tick", 1e9)
	_dungeon.set("_market_loot_tick", 1e9)
	_clear_mobs()
	# --- Goblin: grounded spawn + hunt on terrain ---
	await _check_goblin()
	_clear_mobs()
	# --- Traversals (floor-contact aggregate is the P2 gate) ---
	var layout := _dungeon.get("_layout") as LevelLayout
	var far := _farthest_mob_spawn()
	var st := await _walk_leg("spawn->far mob spawn", far, 1.6, 90.0)
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var half := layout.arena_half_size()
	var staging := Vector3(ax, 0, -half + 3.0)
	st = await _walk_leg("far point->door staging", staging, 1.2, 90.0)
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
	st = await _walk_leg("staging->spawn (return)", back, 2.0, 90.0)
	var agg := float(_floor_frames_total) / maxf(1.0, float(_frames_total))
	_check(agg >= 0.98, "floor contact aggregate %.3f >= 0.98 (%d/%d frames)" % [
		agg, _floor_frames_total, _frames_total])


func _check_dry() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	_check(layout.ponds.is_empty(), "supermarket layout carves no ponds (%d)" % layout.ponds.size())
	var half := layout.arena_half_size()
	var wet := 0
	var samples := 0
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			samples += 1
			if _terrain.is_water(Vector3(x, 0, z)):
				wet += 1
			z += 0.5
		x += 0.5
	_check(wet == 0, "DRY: zero wet samples in arena (%d wet of %d)" % [wet, samples])
	var heights := _terrain.heights_copy()
	var mn := heights[0]
	var mx := heights[0]
	for h in heights:
		mn = minf(mn, h)
		mx = maxf(mx, h)
	_check(mn > _terrain.water_level,
		"terrain minimum %.3f sits above parked water %.2f" % [mn, _terrain.water_level])
	# Near-zero relief by design: the whole heightfield spans ~amp.
	_check(mx - mn <= 0.30, "relief span %.3f <= 2x amp (near-flat by design)" % (mx - mn))
	print("[MART] dry: heights %.3f..%.3f, water %.2f, wet %d/%d" % [mn, mx, _terrain.water_level, wet, samples])


## Sampled max grade over the heightfield, excluding flattened POIs,
## the door flatten disc, the apron strip, and obstacle footprints.
func _check_grade() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var mp := _terrain.map_points
	var cs := _terrain.cell_size
	var sampled := 0
	var skipped := 0
	var max_g := 0.0
	var sum_g := 0.0
	for gz in range(1, mp - 1):
		for gx in range(1, mp - 1):
			var wx := (float(gx) - float(mp - 1) * 0.5) * cs
			var wz := (float(gz) - float(mp - 1) * 0.5) * cs
			var wp := Vector3(wx, 0, wz)
			if _near_flattened(wp) or _on_obstacle(layout, wp):
				skipped += 1
				continue
			var g := _terrain._slope_at(gx, gz)
			sampled += 1
			sum_g += g
			max_g = maxf(max_g, g)
	print("[MART] grade: max %.1f%%, mean %.1f%% over %d samples (%d excluded: flattened/footprints)" % [
		max_g * 100.0, (sum_g / maxf(1.0, float(sampled))) * 100.0, sampled, skipped])
	_check(max_g <= 0.55, "grade measured %.1f%% <= 55%% budget" % (max_g * 100.0))
	# Design pin: amp 0.15 polished concrete measures ~5%; 20% leaves
	# generous margin while still proving near-zero relief (a profile
	# regression toward village/docks amplitudes fails here).
	_check(max_g <= 0.20, "grade design pin %.1f%% <= 20%% (near-flat supermarket)" % (max_g * 100.0))
	_tint_spread()


func _near_flattened(wp: Vector3) -> bool:
	for poi in _terrain.poi_points:
		if Vector2(wp.x - poi.x, wp.z - poi.z).length() <= _terrain.flatten_radius + 1.0:
			return true
	for spec in _terrain.flatten_targets:
		var pos: Vector3 = spec["pos"]
		if Vector2(wp.x - pos.x, wp.z - pos.z).length() <= float(spec.get("radius", 6.5)) + 1.0:
			return true
	return false


func _on_obstacle(layout: LevelLayout, wp: Vector3) -> bool:
	var c := layout.world_to_cell(wp)
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + d
		if layout.cell_at(n.x, n.y) == LevelLayout.OBSTACLE:
			return true
	return false


## No-banding proof (the inverse of the village census): the theme's
## tint ramp is compressed, so EVERY vertex color must sit close to
## every other — measure the actual spread of rendered vertex colors
## over the heightfield and pin it small. A banding regression (a
## wide ramp, or the anchor lost so the ramp pins at an extreme)
## shows up here as spread or as a collapsed mean.
func _tint_spread() -> void:
	var mp := _terrain.map_points
	var lo := Color(1e9, 1e9, 1e9)
	var hi := Color(-1e9, -1e9, -1e9)
	var total := 0
	for gz in range(1, mp - 1):
		for gx in range(1, mp - 1):
			var h := _terrain._sample_grid(gx, gz)
			var c := _terrain._vertex_color(h, _terrain._slope_at(gx, gz))
			lo.r = minf(lo.r, c.r)
			lo.g = minf(lo.g, c.g)
			lo.b = minf(lo.b, c.b)
			hi.r = maxf(hi.r, c.r)
			hi.g = maxf(hi.g, c.g)
			hi.b = maxf(hi.b, c.b)
			total += 1
	var spread := Vector3(hi.r - lo.r, hi.g - lo.g, hi.b - lo.b).length()
	print("[MART] tint spread over %d verts: %.3f (channel ranges r %.3f g %.3f b %.3f)" % [
		total, spread, hi.r - lo.r, hi.g - lo.g, hi.b - lo.b])
	_check(spread <= 0.20, "vertex tint spread %.3f <= 0.20 (no banding)" % spread)
	_check(spread >= 0.02, "vertex tint spread %.3f >= 0.02 (ramp expresses, not pinned flat)" % spread)


func _check_door_flatness() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var half := layout.arena_half_size()
	var h_door := _terrain.get_ground_height(Vector3(ax, 0, -half))
	_check(absf(h_door) <= 0.15, "terrain meets annex floor at door (h=%.3f)" % h_door)
	# Approach strip: the shared door flatten (r=6.5 smoothstep) leaves
	# a soft rim whose residual scales with the theme's amplitude —
	# the docks bound was 0.3 at amp 1.0 and village's 0.45 at amp
	# 1.6; at amp 0.15 the same geometry allows ~0.05. Bound 0.10.
	var strip_max := 0.0
	var zz := -half + 0.5
	while zz <= -half + 3.0:
		strip_max = maxf(strip_max, absf(_terrain.get_ground_height(Vector3(ax, 0, zz))))
		zz += 0.5
	_check(strip_max <= 0.10, "door approach strip flat (max |h| %.3f over the rim)" % strip_max)


## Every obstacle collision box must sit at the footprint rule:
## center y == min ground height under the cell - 0.3 sunk + 1.5
## (half the 3m box). Checked against the dungeon's own sampler.
func _check_obstacle_seating() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var body := _dungeon.get_node_or_null("Arena/Obstacles")
	_check(body != null, "obstacle collision body built")
	if body == null:
		return
	var shapes := 0
	var worst := 0.0
	for col in body.get_children():
		var cs := col as CollisionShape3D
		if cs == null:
			continue
		shapes += 1
		var wp := Vector3(cs.position.x, 0, cs.position.z)
		var expected := _dungeon._min_ground_height(wp, layout.cell_size * 0.5) + 1.5 - 0.3
		worst = maxf(worst, absf(cs.position.y - expected))
	_check(shapes > 0, "obstacle cells present (%d shapes)" % shapes)
	_check(worst <= 0.01, "obstacle boxes seated by footprint rule (worst dev %.4f over %d)" % [worst, shapes])
	print("[MART] obstacle seating: %d boxes, worst dev %.4f" % [shapes, worst])


func _check_determinism_and_perf() -> void:
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
	t2.tint_anchor = _terrain.tint_anchor
	t2.poi_points = _terrain.poi_points.duplicate()
	t2.flatten_targets = _terrain.flatten_targets.duplicate()
	t2.pond_specs = _terrain.pond_specs.duplicate()
	add_child(t2)
	var t0 := Time.get_ticks_msec()
	t2.generate()
	var mart_ms := Time.get_ticks_msec() - t0
	# Issue #138 Phase 3, baked mode (same oracle as the village
	# check's Phase 2 leg): the adopted terrain's live config
	# arrays are empty by design, so a regeneration cannot
	# reproduce its heights — compare against the shipped
	# LevelData heights instead. (The t2 generate above still
	# runs: mart_ms feeds the perf sanity assert below.)
	if str(_dungeon.get("_baked_hash")) != "":
		var data = _dungeon.get_node_or_null("LevelData")
		var dh: PackedFloat32Array = data.get("heights") if data != null else PackedFloat32Array()
		_check(dh == _terrain.heights_copy(),
			"baked terrain heights == shipped LevelData heights (seed %d)" % _seed)
	else:
		_check(t2.heights_copy() == _terrain.heights_copy(),
			"terrain generation deterministic (identical heights, seed %d)" % _terrain.terrain_seed)
	t2.queue_free()
	# Perf A/B: the Docks profile at the Docks extent, same POI inputs,
	# so the comparison isolates profile+extent cost. Reported, with
	# only an absolute sanity ceiling asserted (timing ratios flake).
	var docks := load("res://data/levels/theme_misty_docks.tres") as LevelTheme
	var t3 := HeightmapTerrain.new()
	t3.map_points = int(round(float(docks.grid_size) * docks.cell_size)) + 1
	t3.cell_size = 1.0
	t3.terrain_seed = _terrain.terrain_seed
	t3.noise_frequency = docks.terrain_noise_frequency
	t3.amplitude = docks.terrain_amplitude
	t3.height_offset = docks.terrain_height_offset
	t3.water_level = docks.terrain_water_level
	t3.pond_depth = docks.terrain_pond_depth
	t3.smooth_passes = docks.terrain_smooth_passes
	t3.flatten_radius = docks.terrain_flatten_radius
	t3.tint_anchor = docks.terrain_tint_anchor
	t3.poi_points = _terrain.poi_points.duplicate()
	t3.flatten_targets = _terrain.flatten_targets.duplicate()
	t3.pond_specs = _terrain.pond_specs.duplicate()
	add_child(t3)
	var t1 := Time.get_ticks_msec()
	t3.generate()
	var docks_ms := Time.get_ticks_msec() - t1
	t3.queue_free()
	print("[MART] generation time: supermarket 72m extent %d ms; docks-profile A/B %d ms" % [mart_ms, docks_ms])
	_check(mart_ms < 5000, "generation time %d ms within sanity ceiling (docks A/B %d ms)" % [mart_ms, docks_ms])
	await get_tree().process_frame


## A regular mob (goblin, from this theme's mix), spawned the
## production way, must stand on the terrain and hunt the player
## across it without leaving the ground.
func _check_goblin() -> void:
	var pos := _farthest_mob_spawn()
	pos.y = _terrain.get_ground_height(pos) + 0.5
	_dungeon.spawn_mob(9002, "goblin", pos)
	for i in 30:
		await get_tree().physics_frame
	var mob := _dungeon.get_node_or_null("Mobs/Mob_9002") as Node3D
	_check(mob != null, "goblin spawned via spawn_mob")
	if mob == null:
		return
	for i in 60:
		await get_tree().physics_frame
	var mdev := mob.global_position.y - _terrain.get_ground_height(mob.global_position)
	_check(absf(mdev) <= 0.75, "goblin stands on terrain (dev %.3f)" % mdev)
	var start_dist := mob.global_position.distance_to(_player.global_position)
	var max_dev := 0.0
	var min_y := 999.0
	var floor_frames := 0
	var frames := 0
	for i in 900: # 15s of hunting at 60fps physics
		await get_tree().physics_frame
		frames += 1
		if not is_instance_valid(mob):
			break
		var mp2 := mob.global_position
		max_dev = maxf(max_dev, absf(mp2.y - _terrain.get_ground_height(mp2)))
		min_y = minf(min_y, mp2.y)
		if (mob as CharacterBody3D).is_on_floor():
			floor_frames += 1
	var end_dist := 0.0
	if is_instance_valid(mob):
		end_dist = mob.global_position.distance_to(_player.global_position)
	_check(end_dist < start_dist - 2.0, "goblin closed on the player over terrain (%.1f -> %.1f m)" % [start_dist, end_dist])
	_check(max_dev <= 1.25, "goblin stayed grounded while hunting (max dev %.2f)" % max_dev)
	_check(min_y > -1.0, "goblin never fell through (min y %.2f)" % min_y)
	print("[MART] goblin hunt: floor fraction %.2f over %d frames" % [
		float(floor_frames) / maxf(1.0, float(frames)), frames])


func _farthest_mob_spawn() -> Vector3:
	var layout := _dungeon.get("_layout") as LevelLayout
	var best := Vector3(0, 0, -10)
	var best_d := -1.0
	for s in layout.mob_spawns:
		var d := Vector2(s.x, s.z).length()
		if d > best_d:
			best_d = d
			best = s
	return best


## One routed traversal with a single re-plan retry. The walker can
## wedge on a shelf/prop corner under physics-contact variance
## (identical seed: one run stalls, the next slides past — observed
## on multiple legs across runs). A human player un-wedges and
## re-routes; the harness does the same, once, and says so in the
## log. A leg that stalls twice is a real failure. Terrain stats
## merge across attempts (the aggregate measures the terrain, not
## the walker's luck). The direct door legs stay single-attempt:
## their step measurement must not span a retry.
func _walk_leg(label: String, target: Vector3, stop_dist: float, max_seconds: float) -> Dictionary:
	var st := await _walk_to(target, stop_dist, max_seconds)
	if not bool(st["arrived"]):
		print("[MART] walk %s: stalled once (walker wedge), re-planning" % label)
		var st2 := await _walk_to(target, stop_dist, max_seconds)
		st2["max_dev"] = maxf(float(st["max_dev"]), float(st2["max_dev"]))
		st2["min_y"] = minf(float(st["min_y"]), float(st2["min_y"]))
		st2["frames"] = int(st["frames"]) + int(st2["frames"])
		st2["floor_frames"] = int(st["floor_frames"]) + int(st2["floor_frames"])
		st2["floor_ratio"] = float(st2["floor_frames"]) / maxf(1.0, float(st2["frames"]))
		st = st2
	_report_walk(label, st)
	return st


func _report_walk(label: String, st: Dictionary) -> void:
	_check(bool(st["arrived"]), "walk %s: arrived" % label)
	_check(float(st["max_dev"]) <= 1.25,
		"walk %s: stayed on ground (max dev %.2f)" % [label, float(st["max_dev"])])
	_check(float(st["min_y"]) > -1.0,
		"walk %s: never fell through (min y %.2f)" % [label, float(st["min_y"])])
	_floor_frames_total += int(st["floor_frames"])
	_frames_total += int(st["frames"])
	print("[MART] walk %s: floor ratio %.2f, frames %d" % [label, float(st["floor_ratio"]), int(st["frames"])])


## Drives the real player with synthetic W input, steering body yaw at
## each waypoint (same harness as the docks/village checks). Waypoints
## route over layout FLOOR cells (BFS) unless `direct` is set.
func _walk_to(target: Vector3, stop_dist: float, max_seconds: float, direct := false, step_window := Vector2(1, -1)) -> Dictionary:
	var stats := {"arrived": false, "max_dev": 0.0, "min_y": 999.0,
		"max_abs_y": 0.0, "floor_ratio": 0.0, "frames": 0, "floor_frames": 0}
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
					# Harness telemetry: a stall here is the walker
					# wedged on something; the cell census around the
					# player says on what (kept in the log so a flaky
					# run describes itself).
					var lay := _dungeon.get("_layout") as LevelLayout
					var pc := lay.world_to_cell(pp)
					var census := ""
					for dy in [-1, 0, 1]:
						for dx in [-1, 0, 1]:
							census += str(lay.cell_at(pc.x + dx, pc.y + dy))
					var near := ""
					var holder := _dungeon.get_node_or_null("Mobs")
					if holder != null:
						for m in holder.get_children():
							var mp3 := (m as Node3D).global_position
							if Vector2(mp3.x - pp.x, mp3.z - pp.z).length() < 6.0:
								near += " [" + m.name + " at " + str(mp3) + "]"
					var cols := ""
					for ci in _player.get_slide_collision_count():
						cols += " <" + str(_player.get_slide_collision(ci).get_collider().get_path()) + ">"
					print("[MART] stall at ", pp, " vel ", _player.velocity, " cell ", pc, " census(3x3) ", census, " heading to ", wp, " mobs-near:", near, " colliders:", cols)
					break
			var yaw := atan2(-to.x, -to.z)
			_player.rotation.y = yaw
			_player.set("_yaw", yaw)
			var g := _terrain.get_ground_height(pp)
			stats["max_dev"] = maxf(float(stats["max_dev"]), absf(pp.y - g))
			stats["min_y"] = minf(float(stats["min_y"]), pp.y)
			if step_window.x > step_window.y or (pp.z >= step_window.x and pp.z <= step_window.y):
				stats["max_abs_y"] = maxf(float(stats["max_abs_y"]), absf(pp.y))
			if _player.is_on_floor():
				floor_frames += 1
		if is_final or int(stats["frames"]) >= budget:
			break
	_key(KEY_W, false)
	stats["floor_frames"] = floor_frames
	stats["floor_ratio"] = float(floor_frames) / maxf(1.0, float(stats["frames"]))
	return stats


## Pathable for ROUTING: a floor cell with no obstacle in its
## 8-neighborhood. The docks/village layouts are sparse enough that
## center-line paths suffice there; this theme's shelf aisles are
## dense, and a string-pulled segment that grazes a shelf corner
## wedges the walker intermittently (observed: identical seed, one
## run stalls at a corner, the next slides past). Routing with a
## one-cell clearance keeps the walker's collision radius off the
## corners entirely. Goals that are themselves obstacle-adjacent
## route to their nearest pathable cell, then hop directly.
func _pathable(layout: LevelLayout, c: Vector2i) -> bool:
	if not layout.is_floor(c.x, c.y):
		return false
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if layout.cell_at(c.x + dx, c.y + dy) == LevelLayout.OBSTACLE:
				return false
	return true


func _path_points(from_w: Vector3, to_w: Vector3) -> Array[Vector3]:
	var layout := _dungeon.get("_layout") as LevelLayout
	var start := layout.world_to_cell(from_w)
	var goal := layout.world_to_cell(to_w)
	if not layout.is_floor(goal.x, goal.y):
		return []
	# If the goal is obstacle-adjacent, route to the nearest pathable
	# cell instead; _walk_to appends the exact target for the last hop.
	var route_goal := goal
	if not _pathable(layout, goal):
		var best_d := 1e9
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var cand := goal + Vector2i(dx, dy)
				if _pathable(layout, cand):
					var d := Vector2(dx, dy).length()
					if d < best_d:
						best_d = d
						route_goal = cand
	var prev := {}
	var queue: Array[Vector2i] = [start]
	prev[start] = start
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == route_goal:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if prev.has(n) or not _pathable(layout, n):
				continue
			prev[n] = c
			queue.append(n)
	if not prev.has(route_goal):
		return []
	var cells: Array[Vector3] = []
	var cur := route_goal
	while cur != start:
		cells.append(layout.cell_to_world(cur.x, cur.y))
		cur = prev[cur]
	cells.reverse()
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
		if not _pathable(layout, c):
			return false
	return true


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _clear_mobs() -> void:
	var holder := _dungeon.get_node_or_null("Mobs")
	if holder != null:
		for m in holder.get_children():
			m.queue_free()


func _take_shots() -> void:
	var mk := DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[MART] shots dir ", _out_dir, " mkdir err=", mk)
	var hud = _dungeon.get("_local_hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	# Photography only (driver-local, same pattern as the docks and
	# village checks): kill the distance haze and add a low work light
	# so any relief or tint banding would show. None of this exists in
	# a normal game boot.
	for child in _dungeon.get_children():
		if child is WorldEnvironment:
			var env := (child as WorldEnvironment).environment
			env.fog_enabled = false
			env.ambient_light_energy = 1.1
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.35
	sun.rotation_degrees = Vector3(-34, -38, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	var layout := _dungeon.get("_layout") as LevelLayout
	var half := layout.arena_half_size()
	# Overview: whole arena + annex roofline.
	cam.position = Vector3(38, 34, 41)
	cam.look_at(Vector3(0, 0, -5), Vector3.UP)
	await _snap("mart_overview.png")
	# Ground level at spawn, looking across the arena: flat must read
	# flat and the concrete tint must show no banding.
	var sp := _dungeon.spawn_points[0]
	cam.position = Vector3(sp.x - 4.0, _terrain.get_ground_height(sp) + 2.1, sp.z + 5.0)
	cam.look_at(Vector3(sp.x + 6.0, _terrain.get_ground_height(sp) + 0.8, sp.z - 14.0), Vector3.UP)
	await _snap("mart_spawn_ground.png")
	# Annex approach: on the door axis, looking north through the door.
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var door_in := Vector3(ax + 2.5, 0, -half + 7.0)
	cam.position = Vector3(door_in.x, _terrain.get_ground_height(door_in) + 1.8, door_in.z)
	cam.look_at(Vector3(ax, 1.2, -half - 2.0), Vector3.UP)
	await _snap("mart_annex_approach.png")
	# Low grazing shot across the floor: banding, if any, shows at
	# grazing angles as stripes; relief shows as silhouette.
	cam.position = Vector3(-half + 4.0, 0.7, 6.0)
	cam.look_at(Vector3(half - 4.0, 0.4, -8.0), Vector3.UP)
	await _snap("mart_grazing.png")
	print("[MART] shots saved to ", _out_dir)


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_dir + "/" + file_name)
	print("[MART] snap ", file_name, " size=", img.get_size(), " err=", err)
