extends Node
## Issue #122 validation driver: boots the REAL Apex Arena dungeon
## (heightmap terrain, parameterized LevelTheme profile + the r=8.0
## center boss-fight disc) and plays a scripted run through it: spawn
## on terrain -> a scripted apex fight on the disc (boss grounded,
## charge + seismic slam + mud wall unimpeded on the flattened floor,
## relief intact outside the disc) -> long traversals (floor-contact
## aggregate) -> out the station-annex doorway and back (no step at
## the door). Also asserts the theme's structural guarantees: DRY
## (water parked at -1.00, zero wet samples), sampled max grade
## <= 55% outside flattened POIs/footprints (the center disc is a
## flattened footprint), deterministic generation, and the door
## apron/flatten contract.
##
## Run checks + (optionally) screenshots under Xvfb (the walk legs
## use synthetic key input through the game's own physics, like the
## docks/village checks):
##   xvfb-run godot --path . res://scenes/terrain/apex_integration_check.tscn -- --seed 424242
##   xvfb-run godot --path . res://scenes/terrain/apex_integration_check.tscn -- --mode=shots
##
## This is a test harness only. Nothing here ships in gameplay.

var _seed := 424242
var _mode := "run"
var _out_dir := "/home/hatch/workspace/apex122_shots"
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
	Dungeon.next_theme_id = "apex"
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
	print("[APEX] SUMMARY: %d passed, %d failed" % [_pass, _fail])
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
		print("[APEX] PASS: ", label)
	else:
		_fail += 1
		print("[APEX] FAIL: ", label)


func _run_checks() -> void:
	var theme := _dungeon.theme
	_check(theme != null and theme.use_heightmap_terrain, "apex theme flag use_heightmap_terrain on")
	_check(_terrain != null, "heightmap terrain built instead of flat floor")
	_check(_dungeon.get_node_or_null("Floor") == null, "no flat Floor node on terrain apex")
	_check(_dungeon.get_node_or_null("TerrainDoorApron") != null, "doorway apron built")
	if _terrain == null:
		return
	# Profile actually carried from the theme (issue #122 params).
	_check(absf(_terrain.amplitude - 0.6) < 0.001 and absf(_terrain.noise_frequency - 0.040) < 0.0001
		and absf(_terrain.height_offset - 0.30) < 0.001 and absf(_terrain.water_level - (-1.00)) < 0.001,
		"terrain profile from theme (amp %.2f freq %.3f off %.2f water %.2f)" % [
			_terrain.amplitude, _terrain.noise_frequency, _terrain.height_offset, _terrain.water_level])
	# Tint ramp anchor carried from the theme: apex anchors at its
	# design floor 0.0 (= offset - amp * 0.5), NOT at the parked water
	# level, so the palette bands express.
	_check(not is_nan(_terrain.tint_anchor) and absf(_terrain.tint_anchor) < 0.001,
		"tint anchor from theme (design floor %.2f)" % _terrain.tint_anchor)
	var dup := theme.duplicate() as LevelTheme
	_check(dup.use_heightmap_terrain and absf(dup.terrain_amplitude - 0.6) < 0.001
		and absf(dup.terrain_center_flatten_radius - 8.0) < 0.001,
		"flag + profile + center disc survive theme.duplicate() (cycle scaling)")
	# The center disc target is on the terrain, at the arena center,
	# with the NAN (local-height) marker and the spec'd radius.
	var disc_found := false
	for spec in _terrain.flatten_targets:
		var pos: Vector3 = spec["pos"]
		if Vector2(pos.x, pos.z).length() < 0.01 and absf(float(spec.get("radius", 0.0)) - 8.0) < 0.001:
			disc_found = true
			_check(is_nan(float(spec["height"])), "center disc height is NAN (local terrain height)")
	_check(disc_found, "center disc flatten target present (r 8.0 at arena center)")
	# Dungeon helper == terrain sampler.
	var worst := 0.0
	for p in [Vector3(0, 0, 0), Vector3(10, 0, -6), Vector3(-20, 0, 14), Vector3(23, 0, 23)]:
		worst = maxf(worst, absf(_dungeon.ground_height_at(p) - _terrain.get_ground_height(p)))
	_check(worst < 0.001, "dungeon.ground_height_at matches terrain sampler (worst %.4f)" % worst)
	_check_dry()
	_check_grade()
	_check_center_disc()
	_check_door_flatness()
	await _check_determinism()
	# --- Player spawn ---
	var players := get_tree().get_nodes_in_group("players")
	_check(not players.is_empty(), "local player spawned")
	if players.is_empty():
		return
	_player = players[0] as Player
	# Test scaffolding: keep the walker alive through boss contact.
	_player.set("hp", 100000.0)
	for i in 90:
		await get_tree().physics_frame
	var sp := _dungeon.spawn_points[0]
	var sdev := absf(sp.y - _terrain.get_ground_height(sp))
	_check(sdev < 0.001, "spawn deviation %.3f (grounded spawn point)" % sdev)
	_check(_player.is_on_floor(), "player standing on terrain after settle")
	var dev := _player.global_position.y - _terrain.get_ground_height(_player.global_position)
	_check(absf(dev) <= 0.75, "player y tracks terrain at spawn (dev %.3f)" % dev)
	print("[APEX] player at ", _player.global_position, " ground ", _terrain.get_ground_height(_player.global_position))
	# Park the wave director and clear the field: traversal + boss legs
	# measure terrain, not mob body-blocking.
	_dungeon.set("wave_timer", 99999.0)
	_dungeon.set("mobs_to_spawn", 0)
	_clear_mobs()
	# --- Scripted apex fight on the disc ---
	await _check_apex_fight()
	_clear_mobs()
	# The fight's mud mounds are physical structures; the traversal
	# legs measure terrain, not structures — clear them too.
	for n in get_tree().get_nodes_in_group("structures"):
		n.queue_free()
	# --- Traversals (floor-contact aggregate is the P2 gate) ---
	var layout := _dungeon.get("_layout") as LevelLayout
	var far := _farthest_mob_spawn()
	var st := await _walk_to(far, 1.6, 60.0)
	_report_walk("center->far mob spawn", st)
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var half := layout.arena_half_size()
	var staging := Vector3(ax, 0, -half + 3.0)
	st = await _walk_to(staging, 1.2, 60.0)
	_report_walk("far point->door staging", st)
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
	var agg := float(_floor_frames_total) / maxf(1.0, float(_frames_total))
	_check(agg >= 0.98, "floor contact aggregate %.3f >= 0.98 (%d/%d frames)" % [
		agg, _floor_frames_total, _frames_total])


func _check_dry() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	_check(layout.ponds.is_empty(), "apex layout carves no ponds (%d)" % layout.ponds.size())
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
	for h in heights:
		mn = minf(mn, h)
	_check(mn > _terrain.water_level,
		"terrain minimum %.3f sits above parked water %.2f" % [mn, _terrain.water_level])
	print("[APEX] dry: min height %.3f, water %.2f, wet %d/%d" % [mn, _terrain.water_level, wet, samples])


## Sampled max grade over the heightfield, excluding flattened POIs,
## the door + center-disc flatten discs, the apron strip, and obstacle
## footprints.
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
	print("[APEX] grade: max %.1f%%, mean %.1f%% over %d samples (%d excluded: flattened/footprints)" % [
		max_g * 100.0, (sum_g / maxf(1.0, float(sampled))) * 100.0, sampled, skipped])
	_check(max_g <= 0.55, "grade measured %.1f%% <= 55%% budget" % (max_g * 100.0))
	_tint_census()


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


## Palette census, the village pattern: with the ramp anchored at the
## design floor, all three dry bands (low/mid/high) must populate. No
## vertex is under water on this dry theme.
func _tint_census() -> void:
	var mp := _terrain.map_points
	var counts := {"bed": 0, "low": 0, "mid": 0, "high": 0}
	var total := 0
	for gz in range(1, mp - 1):
		for gx in range(1, mp - 1):
			var h := _terrain._sample_grid(gx, gz)
			var c := _terrain._vertex_color(h, _terrain._slope_at(gx, gz))
			var best := "bed"
			var best_d := 1e9
			for key in counts.keys():
				var tint: Color = _terrain.get("tint_" + key)
				var d := (Vector3(c.r - tint.r, c.g - tint.g, c.b - tint.b)).length()
				if d < best_d:
					best_d = d
					best = key
			counts[best] = int(counts[best]) + 1
			total += 1
	print("[APEX] tint census of %d verts: bed %.1f%%, low %.1f%%, mid %.1f%%, high %.1f%%" % [
		total,
		100.0 * float(counts["bed"]) / maxf(1.0, float(total)),
		100.0 * float(counts["low"]) / maxf(1.0, float(total)),
		100.0 * float(counts["mid"]) / maxf(1.0, float(total)),
		100.0 * float(counts["high"]) / maxf(1.0, float(total))])
	_check(int(counts["low"]) > 0 and int(counts["mid"]) > 0 and int(counts["high"]) > 0,
		"tint ramp expresses low/mid/high bands (low %d, mid %d, high %d of %d)" % [
			int(counts["low"]), int(counts["mid"]), int(counts["high"]), total])


## The center disc: heights relax toward the center's local height —
## a flat core with a soft rim (the shared smoothstep profile) — and
## the relief OUTSIDE the disc is untouched.
func _check_center_disc() -> void:
	var center_h := _terrain.get_ground_height(Vector3.ZERO)
	var dev_core := 0.0
	var dev_disc := 0.0
	var x := -8.0
	while x <= 8.0:
		var z := -8.0
		while z <= 8.0:
			var d := Vector2(x, z).length()
			if d <= 8.0:
				var dev := absf(_terrain.get_ground_height(Vector3(x, 0, z)) - center_h)
				dev_disc = maxf(dev_disc, dev)
				if d <= 2.0:
					dev_core = maxf(dev_core, dev)
			z += 0.5
		x += 0.5
	print("[APEX] center disc: center h %.3f, core dev %.4f (r<=2), disc dev %.4f (r<=8)" % [
		center_h, dev_core, dev_disc])
	# Bounds are looser than the suite's #122 pins on purpose: the
	# suite measures the fixed seed 424242 bare heightfield (core
	# 0.009 / disc 0.163), while this check boots the dungeon's own
	# seed chain — rim deviation is seed-dependent (0.200 observed at
	# the default seed). The binding facts are the flat core and the
	# boss grounding deviation (0.001 in the fight leg).
	_check(dev_core <= 0.03, "disc core flat (max dev %.4f within r<=2)" % dev_core)
	_check(dev_disc <= 0.25, "disc rim soft (max dev %.4f within r<=8)" % dev_disc)
	# Rim relief: the annulus just outside the disc still has terrain.
	var lo := 1e9
	var hi := -1e9
	x = -14.0
	while x <= 14.0:
		var z := -14.0
		while z <= 14.0:
			var d := Vector2(x, z).length()
			if d >= 10.0 and d <= 14.0:
				var h := _terrain.get_ground_height(Vector3(x, 0, z))
				lo = minf(lo, h)
				hi = maxf(hi, h)
			z += 0.5
		x += 0.5
	print("[APEX] rim relief: annulus r 10-14 spans %.3f..%.3f (relief %.3f)" % [lo, hi, hi - lo])
	_check(hi - lo > 0.03, "rim relief intact outside the disc (span %.3f)" % (hi - lo))


func _check_door_flatness() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var half := layout.arena_half_size()
	var h_door := _terrain.get_ground_height(Vector3(ax, 0, -half))
	_check(absf(h_door) <= 0.15, "terrain meets annex floor at door (h=%.3f)" % h_door)
	# Approach strip: the shared door flatten's soft-rim residual
	# scales with the theme's amplitude (village calibrated 0.45 at
	# amp 1.6; apex amp 0.6 -> ~0.17). Bound 0.20; the binding proof
	# is the annex loop's no-step measurement below.
	var strip_max := 0.0
	var zz := -half + 0.5
	while zz <= -half + 3.0:
		strip_max = maxf(strip_max, absf(_terrain.get_ground_height(Vector3(ax, 0, zz))))
		zz += 0.5
	_check(strip_max <= 0.20, "door approach strip flat (max |h| %.3f over the rim)" % strip_max)


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
	t2.tint_anchor = _terrain.tint_anchor
	t2.poi_points = _terrain.poi_points.duplicate()
	t2.flatten_targets = _terrain.flatten_targets.duplicate()
	t2.pond_specs = _terrain.pond_specs.duplicate()
	add_child(t2)
	t2.generate()
	_check(t2.heights_copy() == _terrain.heights_copy(),
		"terrain generation deterministic (identical heights, seed %d)" % _terrain.terrain_seed)
	t2.queue_free()
	await get_tree().process_frame


## Scripted apex fight. The boss spawns the production way (farthest
## mob spawn, grounded +0.5) and must stand on the terrain; then,
## scaffolding in the village pattern, it is re-placed on the center
## disc with the player at charge-band distance. Charge and the
## HP/cooldown-shaped specials are POLLED (never sampled at a fixed
## frame); the two cooldown legs use frozen-clock seams (the cooldown
## fields set directly) so the poll is deterministic.
func _check_apex_fight() -> void:
	var pos := _farthest_mob_spawn()
	pos.y = _terrain.get_ground_height(pos) + 0.5
	_dungeon.spawn_mob(9002, "apex_boar", pos)
	for i in 30:
		await get_tree().physics_frame
	var boss := _dungeon.get_node_or_null("Mobs/Mob_9002") as Node3D
	_check(boss != null, "apex boss spawned via spawn_mob")
	if boss == null:
		return
	for i in 60:
		await get_tree().physics_frame
	var bdev := boss.global_position.y - _terrain.get_ground_height(boss.global_position)
	_check(absf(bdev) <= 0.75, "apex boss stands on terrain at production spawn (dev %.3f)" % bdev)
	# Scaffolding: boss onto the disc center, player at charge band.
	var center := Vector3.ZERO
	boss.global_position = Vector3(center.x, _terrain.get_ground_height(center) + 0.5, center.z)
	_player.global_position = Vector3(center.x + 12.0, _terrain.get_ground_height(Vector3(12, 0, 0)) + 0.2, center.z)
	for i in 30:
		await get_tree().physics_frame
	var disc_dev := absf(boss.global_position.y - _terrain.get_ground_height(boss.global_position))
	_check(disc_dev <= 0.75, "apex boss grounded on the center disc (dev %.3f)" % disc_dev)
	# --- Charge leg: poll for the charge state; sample grounding
	# every frame while watching.
	var charge_seen := false
	var max_dev := 0.0
	var min_y := 999.0
	var relocated := false
	for w in 2:
		var window := 1800 # 30s per window at 60fps physics
		for i in window:
			await get_tree().physics_frame
			if not is_instance_valid(boss):
				break
			var bp := boss.global_position
			max_dev = maxf(max_dev, absf(bp.y - _terrain.get_ground_height(bp)))
			min_y = minf(min_y, bp.y)
			if float(boss.get("_charge_t")) > 0.0:
				charge_seen = true
				break
		if charge_seen or not is_instance_valid(boss):
			break
		if not relocated:
			relocated = true
			var dest := Vector3(center.x - 12.0, 0, center.z)
			_player.global_position = Vector3(dest.x, _terrain.get_ground_height(dest) + 0.2, dest.z)
			print("[APEX] charge watch: player re-placed at charge-band distance (scaffolding)")
	_check(charge_seen, "apex boss executed its charge on the disc")
	_check(max_dev <= 1.25, "apex boss stayed grounded through the charge watch (max dev %.2f)" % max_dev)
	_check(min_y > -1.0, "apex boss never fell through (min y %.2f)" % min_y)
	# Let any charge finish, re-center the boss on the disc.
	for i in 120:
		await get_tree().physics_frame
	boss.global_position = Vector3(center.x, _terrain.get_ground_height(center) + 0.5, center.z)
	_player.global_position = Vector3(center.x + 6.0, _terrain.get_ground_height(Vector3(6, 0, 0)) + 0.2, center.z)
	for i in 30:
		await get_tree().physics_frame
	# --- Seismic slam leg: frozen-clock seam (special-2 cooldown set
	# to zero), then poll for the shockwave to exist and expand past
	# the disc rim (r 8) unimpeded.
	boss.set("_special2_cd", 0.0)
	var slam_seen := false
	for i in 900: # 15s: telegraph (1.0s) + AI tick
		await get_tree().physics_frame
		var waves: Array = boss.get("_shockwaves")
		if not waves.is_empty():
			slam_seen = true
			break
	_check(slam_seen, "apex boss fired seismic slam on the disc (shockwave spawned)")
	var ring_max := 0.0
	if slam_seen:
		for i in 600: # ring expands 6 m/s: past r=8 in ~1.2s
			await get_tree().physics_frame
			var waves2: Array = boss.get("_shockwaves")
			for wv in waves2:
				ring_max = maxf(ring_max, float(wv.get("radius", 0.0)))
			if ring_max >= 8.0:
				break
	_check(ring_max >= 8.0, "seismic shockwave crossed the disc rim unimpeded (max radius %.1f)" % ring_max)
	var post_dev := absf(boss.global_position.y - _terrain.get_ground_height(boss.global_position))
	_check(post_dev <= 1.25, "apex boss grounded after the slam (dev %.3f)" % post_dev)
	# --- Mud wall leg: HP gate (66%) crossed by direct damage, the
	# special-3 cooldown zeroed (frozen-clock seam), poll for the
	# three mud mounds in the structures group.
	var max_hp := float(boss.get("max_hp"))
	boss.call("take_damage", max_hp * 0.40, 1, Vector3.ZERO) # -> 60%: under the 66% gate
	boss.set("_special3_cd", 0.0)
	var mounds := 0
	for i in 900: # 15s: telegraph (1.0s) + placement
		await get_tree().physics_frame
		mounds = 0
		for n in get_tree().get_nodes_in_group("structures"):
			if str(n.get("structure_id")) == "mud_mound":
				mounds += 1
		if mounds >= 3:
			break
	_check(mounds == 3, "apex boss raised its mud wall on terrain (mounds %d)" % mounds)
	print("[APEX] fight done: boss at ", boss.global_position, " ground ",
		_terrain.get_ground_height(boss.global_position))


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


func _report_walk(label: String, st: Dictionary) -> void:
	_check(bool(st["arrived"]), "walk %s: arrived" % label)
	_check(float(st["max_dev"]) <= 1.25,
		"walk %s: stayed on ground (max dev %.2f)" % [label, float(st["max_dev"])])
	_check(float(st["min_y"]) > -1.0,
		"walk %s: never fell through (min y %.2f)" % [label, float(st["min_y"])])
	_floor_frames_total += int(st["floor_frames"])
	_frames_total += int(st["frames"])
	print("[APEX] walk %s: floor ratio %.2f, frames %d" % [label, float(st["floor_ratio"]), int(st["frames"])])


## Drives the real player with synthetic W input, steering body yaw
## at each waypoint (same harness as the docks/village checks).
## Waypoints route over layout FLOOR cells (BFS) unless `direct`.
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


func _clear_mobs() -> void:
	var holder := _dungeon.get_node_or_null("Mobs")
	if holder != null:
		for m in holder.get_children():
			m.queue_free()


func _take_shots() -> void:
	var mk := DirAccess.make_dir_recursive_absolute(_out_dir)
	print("[APEX] shots dir ", _out_dir, " mkdir err=", mk)
	var hud = _dungeon.get("_local_hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	# Photography only (driver-local, same pattern as the docks and
	# village checks): kill the distance haze and add a low work
	# light so the terrain relief shades visibly.
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
	# Overview: whole arena + annex roofline, oblique for relief.
	cam.position = Vector3(30, 28, 33)
	cam.look_at(Vector3(0, 0, -4), Vector3.UP)
	await _snap("apex_overview.png")
	# Disc close-up: ground level at the disc rim, looking across the
	# flattened boss floor toward the relief beyond.
	var rim := Vector3(9.0, 0, 0)
	cam.position = Vector3(rim.x, _terrain.get_ground_height(rim) + 1.6, rim.z + 3.0)
	cam.look_at(Vector3(-14.0, _terrain.get_ground_height(Vector3(-14, 0, 0)) + 0.6, 0), Vector3.UP)
	await _snap("apex_disc_rim.png")
	# Annex approach: on the door axis, looking north through the door.
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var door_in := Vector3(ax + 2.5, 0, -half + 7.0)
	cam.position = Vector3(door_in.x, _terrain.get_ground_height(door_in) + 1.8, door_in.z)
	cam.look_at(Vector3(ax, 1.2, -half - 2.0), Vector3.UP)
	await _snap("apex_annex_approach.png")
	# Slope vista: from the arena's low point toward its high point.
	var heights := _terrain.heights_copy()
	var mp := _terrain.map_points
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	var lo_h := 1e9
	var hi_h := -1e9
	for gz in mp:
		for gx in mp:
			var h := heights[gz * mp + gx]
			var wp := Vector3((float(gx) - float(mp - 1) * 0.5) * _terrain.cell_size, 0,
				(float(gz) - float(mp - 1) * 0.5) * _terrain.cell_size)
			if h < lo_h:
				lo_h = h
				lo = wp
			if h > hi_h:
				hi_h = h
				hi = wp
	cam.position = Vector3(lo.x, lo_h + 1.7, lo.z)
	cam.look_at(Vector3(hi.x, hi_h + 0.5, hi.z), Vector3.UP)
	await _snap("apex_slope_vista.png")
	print("[APEX] shots saved to ", _out_dir)


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_dir + "/" + file_name)
	print("[APEX] snap ", file_name, " size=", img.get_size(), " err=", err)
