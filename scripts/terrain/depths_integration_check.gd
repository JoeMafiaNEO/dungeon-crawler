extends Node
## Issue #121 validation driver: boots the REAL Depths dungeon
## (heightmap terrain, parameterized LevelTheme profile) and plays a
## scripted run through it: spawn on terrain -> a regular mob crosses
## the maze on terrain to reach the player (no slope-stuck) -> the
## horror boss spawns grounded at the farthest mob spawn (the
## production _spawn_boss shape) and fights on the terrain -> long
## maze traversals (floor-contact aggregate) -> out the station-annex
## doorway and back (no step at the door). Also asserts the theme's
## structural guarantees: DRY (water parked at -1.00, zero wet
## samples), sampled max grade <= 55% outside flattened POIs and
## wall/obstacle footprints, deterministic generation, and the door
## apron/flatten contract.
##
## Discipline (F-4 pattern): legs POLL game state (arrival, boss
## actions, distance closed) instead of sampling after fixed frame
## counts; the wave director is parked (frozen clock) during the
## traversal legs so they measure terrain, not combat.
##
## Run checks + (optionally) screenshots under Xvfb:
##   xvfb-run godot --path . res://scenes/terrain/depths_integration_check.tscn -- --seed 424242
##   xvfb-run godot --path . res://scenes/terrain/depths_integration_check.tscn -- --mode=shots
##
## This is a test harness only. Nothing here ships in gameplay.

var _seed := 424242
var _mode := "run"
var _out_dir := "/home/hatch/workspace/depths121_shots"
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
	Dungeon.next_theme_id = "depths"
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
	print("[DEPTHS] SUMMARY: %d passed, %d failed" % [_pass, _fail])
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
		print("[DEPTHS] PASS: ", label)
	else:
		_fail += 1
		print("[DEPTHS] FAIL: ", label)


func _run_checks() -> void:
	var theme := _dungeon.theme
	_check(theme != null and theme.use_heightmap_terrain, "depths theme flag use_heightmap_terrain on")
	_check(_terrain != null, "heightmap terrain built instead of flat floor")
	_check(_dungeon.get_node_or_null("Floor") == null, "no flat Floor node on terrain depths")
	_check(_dungeon.get_node_or_null("TerrainDoorApron") != null, "doorway apron built")
	if _terrain == null:
		return
	# Profile actually carried from the theme (issue #121 params).
	_check(absf(_terrain.amplitude - 1.8) < 0.001 and absf(_terrain.noise_frequency - 0.040) < 0.0001
		and absf(_terrain.height_offset - 0.90) < 0.001 and absf(_terrain.water_level - (-1.00)) < 0.001,
		"terrain profile from theme (amp %.2f freq %.3f off %.2f water %.2f)" % [
			_terrain.amplitude, _terrain.noise_frequency, _terrain.height_offset, _terrain.water_level])
	# Tint ramp anchor carried from the theme: depths anchors at its
	# design floor 0.0 (= offset - amp * 0.5), NOT at the parked water
	# level, so the palette bands express on a dry theme.
	_check(not is_nan(_terrain.tint_anchor) and absf(_terrain.tint_anchor) < 0.001,
		"tint anchor from theme (design floor %.2f)" % _terrain.tint_anchor)
	var dup := theme.duplicate() as LevelTheme
	_check(dup.use_heightmap_terrain and absf(dup.terrain_amplitude - 1.8) < 0.001,
		"flag + profile survive theme.duplicate() (cycle scaling)")
	# Dungeon helper == terrain sampler.
	var worst := 0.0
	for p in [Vector3(0, 0, 0), Vector3(10, 0, -6), Vector3(-20, 0, 14), Vector3(20, 0, 20)]:
		worst = maxf(worst, absf(_dungeon.ground_height_at(p) - _terrain.get_ground_height(p)))
	_check(worst < 0.001, "dungeon.ground_height_at matches terrain sampler (worst %.4f)" % worst)
	_check_dry()
	_check_grade()
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
	print("[DEPTHS] player at ", _player.global_position, " ground ", _terrain.get_ground_height(_player.global_position))
	# Park the wave director and clear the field: traversal + boss legs
	# measure terrain, not mob body-blocking (frozen-clock seam).
	_dungeon.set("wave_timer", 99999.0)
	_dungeon.set("mobs_to_spawn", 0)
	_clear_mobs()
	# --- Regular mob: crosses the maze on terrain, no slope-stuck ---
	await _check_mob_traversal()
	_clear_mobs()
	# --- Horror boss: grounded spawn + fight on terrain ---
	await _check_horror()
	_clear_mobs()
	# --- Traversals (floor-contact aggregate is the P2 gate) ---
	var layout := _dungeon.get("_layout") as LevelLayout
	var far := _farthest_mob_spawn()
	var st := await _walk_to(far, 1.6, 90.0)
	_report_walk("spawn->far mob spawn", st)
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var half := layout.arena_half_size()
	var staging := Vector3(ax, 0, -half + 3.0)
	st = await _walk_to(staging, 1.2, 90.0)
	_report_walk("far point->door staging", st)
	var door_out := Vector3(ax, 0, -half - 5.5)
	# The step window covers the SEAM (door joint + apron + hall
	# entry), not the arena-side approach gradient — that gradient is
	# the strip check's subject, measured above with its own
	# amp-scaled bound. (Village's wider window worked because its
	# approach is open field at a lower amplitude.)
	st = await _walk_to(door_out, 1.6, 30.0, true, Vector2(-half - 3.0, -half + 1.0))
	_report_walk("staging->annex hall (through door)", st)
	_check(st["max_abs_y"] <= 0.5,
		"annex: no step crossing the doorway (max |y| in seam window %.3f)" % st["max_abs_y"])
	st = await _walk_to(staging, 1.2, 30.0, true, Vector2(-half - 3.0, -half + 1.0))
	_report_walk("annex hall->staging (back out)", st)
	_check(st["max_abs_y"] <= 0.5,
		"annex: no step on re-entry (max |y| in seam window %.3f)" % st["max_abs_y"])
	var back := Vector3(_dungeon.spawn_points[0].x, 0, _dungeon.spawn_points[0].z)
	st = await _walk_to(back, 2.0, 90.0)
	_report_walk("staging->spawn (return)", st)
	var agg := float(_floor_frames_total) / maxf(1.0, float(_frames_total))
	# What is enforced, and what is only measured (calibration note,
	# corrected): the aggregate is asserted at 0.90 because at amp
	# 1.8 with a single smoothing pass the micro-relief flickers
	# is_on_floor on bump crests (per-leg ratios 0.93-0.99); it
	# measures 0.950-0.953 across the gate seeds. Grounding itself
	# is enforced per leg in _report_walk: max y-deviation from the
	# terrain <= 0.5 and min y > -1.0 on every leg. The deviation
	# measures 0.00-0.02 on open-field legs and up to 0.09 on the
	# door-seam legs across the gate seeds — the 0.5 bound keeps
	# >5x headroom over the worst measured leg while actually
	# binding (the previous 1.25 could not fail a hovering walker).
	_check(agg >= 0.90, "floor contact aggregate %.3f >= 0.90 (%d/%d frames)" % [
		agg, _floor_frames_total, _frames_total])


func _check_dry() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	_check(layout.ponds.is_empty(), "depths layout carves no ponds (%d)" % layout.ponds.size())
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
	print("[DEPTHS] dry: min height %.3f, water %.2f, wet %d/%d" % [mn, _terrain.water_level, wet, samples])


## Sampled max grade over the heightfield, excluding flattened POIs,
## the door flatten disc, the apron strip, and footprint cells. In
## the maze the footprints are the WALL cells themselves (walls are
## based into the terrain; their surface is not walkable floor), so
## samples count only on layout FLOOR cells.
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
			if _near_flattened(wp) or not _on_floor(layout, wp):
				skipped += 1
				continue
			var g := _terrain._slope_at(gx, gz)
			sampled += 1
			sum_g += g
			max_g = maxf(max_g, g)
	print("[DEPTHS] grade: max %.1f%%, mean %.1f%% over %d samples (%d excluded: flattened/footprints)" % [
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


func _on_floor(layout: LevelLayout, wp: Vector3) -> bool:
	var c := layout.world_to_cell(wp)
	return layout.is_floor(c.x, c.y)


## Which palette bands the depths heightfield actually lands in
## (vertex colors via the terrain's own _vertex_color, classified by
## nearest tint). With the ramp anchored at the design floor, all
## three dry bands (low/mid/high) must be populated.
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
	print("[DEPTHS] tint census of %d verts: bed %.1f%%, low %.1f%%, mid %.1f%%, high %.1f%%" % [
		total,
		100.0 * float(counts["bed"]) / maxf(1.0, float(total)),
		100.0 * float(counts["low"]) / maxf(1.0, float(total)),
		100.0 * float(counts["mid"]) / maxf(1.0, float(total)),
		100.0 * float(counts["high"]) / maxf(1.0, float(total))])
	_check(int(counts["low"]) > 0 and int(counts["mid"]) > 0 and int(counts["high"]) > 0,
		"tint ramp expresses low/mid/high bands (low %d, mid %d, high %d of %d)" % [
			int(counts["low"]), int(counts["mid"]), int(counts["high"]), total])


func _check_door_flatness() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var half := layout.arena_half_size()
	var h_door := _terrain.get_ground_height(Vector3(ax, 0, -half))
	_check(absf(h_door) <= 0.15, "terrain meets annex floor at door (h=%.3f)" % h_door)
	# Approach strip: the shared door flatten (r=6.5 smoothstep) leaves
	# a soft rim whose residual scales with the theme's amplitude —
	# the docks check's 0.3 bound was calibrated at amp 1.0, village's
	# 0.45 at amp 1.6; at depths' amp 1.8 the same geometry measures
	# 0.547 at the strip's far edge (seed 424242), so the bound sits
	# at the amp-scaled 0.6. The binding proof is the annex loop's
	# no-step measurement below.
	var strip_max := 0.0
	var zz := -half + 0.5
	while zz <= -half + 3.0:
		strip_max = maxf(strip_max, absf(_terrain.get_ground_height(Vector3(ax, 0, zz))))
		zz += 0.5
	_check(strip_max <= 0.6, "door approach strip flat (max |h| %.3f over the rim)" % strip_max)


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


## A regular depths mob (skeleton, the theme's heaviest mix entry)
## in a real encounter shape: a mob spawn with a CLEAR STRAIGHT LINE
## to the player (mob steering is straight-line at the nearest
## player — production behavior on any floor; over a whole maze it
## wedges on walls, which is steering, not terrain). The leg
## isolates the terrain question: spawned 5-14m away across sloped
## cavern floor, the mob must close to melee — slope never arrests
## it (the grade budget is far below the walker's hard-stop, and
## terrain adds no slope-speed). Poll the distance until arrival
## or the window ends, sampling grounding every frame.
func _check_mob_traversal() -> void:
	# Encounter search: scan FROM each mob spawn for a floor point
	# 5-8m away with a clear straight segment — the shape of a real
	# encounter (the player rounds a corner into the mob's room).
	# Anchoring on the player's spawn clearing instead proved
	# seed-fragile: at seed 1 no mob spawn has a >=4m clear line to
	# ANY player vantage, while every mob room has clear lines of
	# its own. The player is re-placed at the far end (scaffolding,
	# printed) — the mob's crossing is what is measured.
	var enc := _find_encounter()
	_check(bool(enc[0]), "mob traversal: an encounter line exists (mob room with a clear 5-8m line)")
	if not bool(enc[0]):
		return
	var pos: Vector3 = enc[1]
	var vantage: Vector3 = enc[2]
	_player.global_position = Vector3(vantage.x, _terrain.get_ground_height(vantage) + 0.2, vantage.z)
	_player.velocity = Vector3.ZERO
	for i in 30:
		await get_tree().physics_frame
	print("[DEPTHS] mob traversal: encounter line %.1fm, player re-placed (scaffolding)" % [
		Vector2(pos.x - vantage.x, pos.z - vantage.z).length()])
	pos.y = _terrain.get_ground_height(pos) + 0.5
	_dungeon.spawn_mob(9003, "skeleton", pos)
	for i in 30:
		await get_tree().physics_frame
	var mob := _dungeon.get_node_or_null("Mobs/Mob_9003") as Node3D
	_check(mob != null, "skeleton spawned via spawn_mob for the traversal leg")
	if mob == null:
		return
	var start_dist := Vector2(mob.global_position.x - _player.global_position.x,
		mob.global_position.z - _player.global_position.z).length()
	var final_dist := start_dist
	var max_dev := 0.0
	var min_y := 999.0
	var frames := 0
	while frames < 2400: # 40s poll window
		await get_tree().physics_frame
		frames += 1
		if not is_instance_valid(mob):
			break
		var mp2 := mob.global_position
		max_dev = maxf(max_dev, absf(mp2.y - _terrain.get_ground_height(mp2)))
		min_y = minf(min_y, mp2.y)
		final_dist = Vector2(mp2.x - _player.global_position.x,
			mp2.z - _player.global_position.z).length()
		if final_dist <= 3.0:
			break
	print("[DEPTHS] mob traversal: closed %.1fm -> %.1fm over %d frames" % [start_dist, final_dist, frames])
	_check(final_dist <= maxf(3.5, start_dist * 0.35),
		"mob closed on the player across sloped floor (%.1fm -> %.1fm, no slope-stuck)" % [start_dist, final_dist])
	_check(max_dev <= 1.25, "mob stayed grounded crossing the floor (max dev %.2f)" % max_dev)
	_check(min_y > -1.0, "mob never fell through (min y %.2f)" % min_y)


## The horror boss, spawned the production way (farthest mob spawn,
## grounded +0.5 — dungeon._spawn_boss's shape), must stand on the
## terrain in its arena and FIGHT there: the engagement watch polls
## for a boss action (void-rift cast, summons, phaseshift, or a
## reposition) instead of sampling after a fixed count, sampling
## grounding every frame. The arena's local grade is measured and
## reported (the issue's "summon arena local-flat" POI).
func _check_horror() -> void:
	var pos := _farthest_mob_spawn()
	# Arena local grade (floor cells within 4m of the boss spawn).
	var layout := _dungeon.get("_layout") as LevelLayout
	var mp := _terrain.map_points
	var arena_max := 0.0
	for gz in range(1, mp - 1):
		for gx in range(1, mp - 1):
			var wx := (float(gx) - float(mp - 1) * 0.5) * _terrain.cell_size
			var wz := (float(gz) - float(mp - 1) * 0.5) * _terrain.cell_size
			var wp := Vector3(wx, 0, wz)
			if Vector2(wx - pos.x, wz - pos.z).length() <= 4.0 and _on_floor(layout, wp):
				arena_max = maxf(arena_max, _terrain._slope_at(gx, gz))
	print("[DEPTHS] horror arena local grade max %.1f%% (around farthest spawn)" % (arena_max * 100.0))
	_check(arena_max <= 0.55, "horror arena locally within grade budget (%.1f%%)" % (arena_max * 100.0))
	pos.y = _terrain.get_ground_height(pos) + 0.5
	_dungeon.spawn_mob(9002, "boss_horror", pos)
	for i in 30:
		await get_tree().physics_frame
	var horror := _dungeon.get_node_or_null("Mobs/Mob_9002") as Node3D
	_check(horror != null, "horror boss spawned via spawn_mob")
	if horror == null:
		return
	for i in 60:
		await get_tree().physics_frame
	var hdev := horror.global_position.y - _terrain.get_ground_height(horror.global_position)
	_check(absf(hdev) <= 0.75, "horror stands on terrain (dev %.3f)" % hdev)
	# Best-effort walk into the arena so the boss engages; if the
	# maze approach stalls out (seed-dependent), re-place the player
	# at the mob spawn nearest the horror — scaffolding: the fight
	# evidence below is the gate, not the commute (the village boar
	# leg's relocate seam, promoted to a guarantee).
	var st := await _walk_to(pos, 9.0, 45.0)
	var hd := Vector2(_player.global_position.x - pos.x,
		_player.global_position.z - pos.z).length()
	if not bool(st["arrived"]) or hd > 12.0:
		var near := Vector3.ZERO
		var nd := 1e9
		for s in layout.mob_spawns:
			var d := Vector2(s.x - pos.x, s.z - pos.z).length()
			if d > 4.0 and d < nd:
				nd = d
				near = s
		if nd < 1e9:
			_player.global_position = Vector3(near.x, _terrain.get_ground_height(near) + 0.2, near.z)
			print("[DEPTHS] horror approach: player re-placed at engagement distance (scaffolding)")
	# Engagement watch: poll for a boss action; if none fires in the
	# first window, re-place the player at engagement distance once
	# (nearest mob spawn to the horror) and keep watching.
	var spawn_pos := horror.global_position
	var action_seen := false
	var max_dev := 0.0
	var min_y := 999.0
	var frames := 0
	var relocated := false
	for w in 2:
		var window := 1500 # 25s per window at 60fps physics
		for i in window:
			await get_tree().physics_frame
			frames += 1
			if not is_instance_valid(horror):
				action_seen = true # died mid-watch: it fought
				break
			var hp2 := horror.global_position
			max_dev = maxf(max_dev, absf(hp2.y - _terrain.get_ground_height(hp2)))
			min_y = minf(min_y, hp2.y)
			var rifts: Array = horror.get("_rifts")
			if not rifts.is_empty() or float(horror.get("_phaseshift_t")) > 0.0 \
					or hp2.distance_to(spawn_pos) > 2.0 \
					or _dungeon.get_node("Mobs").get_child_count() > 1:
				action_seen = true
				break
		if action_seen or not is_instance_valid(horror):
			break
		if not relocated:
			relocated = true
			var best := Vector3.ZERO
			var best_d := 1e9
			for s in (_dungeon.get("_layout") as LevelLayout).mob_spawns:
				var d := Vector2(s.x - horror.global_position.x, s.z - horror.global_position.z).length()
				if d > 4.0 and d < best_d:
					best_d = d
					best = s
			if best_d < 1e9:
				_player.global_position = Vector3(best.x, _terrain.get_ground_height(best) + 0.2, best.z)
				print("[DEPTHS] horror watch: player re-placed at engagement distance (scaffolding)")
	_check(action_seen, "horror acted on terrain (rift / summon / phaseshift / reposition)")
	_check(max_dev <= 1.25, "horror stayed grounded through engagement (max dev %.2f)" % max_dev)
	_check(min_y > -1.0, "horror never fell through (min y %.2f)" % min_y)
	# Summoned adds stand on the terrain too.
	var holder := _dungeon.get_node_or_null("Mobs")
	if holder != null:
		var adds := 0
		var adds_dev := 0.0
		for m in holder.get_children():
			if m != horror and m is Node3D:
				adds += 1
				adds_dev = maxf(adds_dev, absf((m as Node3D).global_position.y
					- _terrain.get_ground_height((m as Node3D).global_position)))
		if adds > 0:
			_check(adds_dev <= 1.25, "summoned adds grounded on terrain (%d adds, max dev %.2f)" % [adds, adds_dev])
		print("[DEPTHS] horror engagement: %d frames watched, %d adds present" % [frames, adds])
	# --- Issue #127: void-rift grounding on the real heightmap.
	# Drive a cast directly (the fight above proves the AI casts on
	# its own; this leg measures placement): server anchors and
	# client discs must sit on the sampled ground, at spawn and
	# after the rifts have drifted + pulsed for a few seconds.
	if is_instance_valid(horror):
		horror.call("_do_void_rift")
		for i in 10:
			await get_tree().physics_frame
		# Measure the DRIVEN cast specifically: its anchors are the
		# tail of _rifts (appends are last; only older rifts expire),
		# its discs are the new batch in _rift_nodes. (The AI may
		# have rifts of its own live from the fight above.)
		var batch_after := int(horror.get("_rift_batch"))
		var anchors: Array = horror.get("_rifts")
		var mine: Array = anchors.slice(maxi(0, anchors.size() - 3))
		_check(mine.size() == 3, "127: rift cast spawns 3 zones on the Depths")
		var worst_anchor := 0.0
		for r in mine:
			var ap: Vector3 = r["pos"]
			worst_anchor = maxf(worst_anchor, absf(ap.y - _terrain.get_ground_height(ap)))
		_check(worst_anchor <= 0.02, "127: rift anchors grounded at spawn (worst dev %.3f)" % worst_anchor)
		var disc_nodes: Dictionary = horror.get("_rift_nodes")
		var my_discs: Array = disc_nodes.get(batch_after, [])
		var worst_disc := 0.0
		for n in my_discs:
			var np := (n as Node3D).global_position
			worst_disc = maxf(worst_disc, absf(np.y - (_terrain.get_ground_height(np) + 0.12)))
		_check(my_discs.size() == 3 and worst_disc <= 0.02,
			"127: rift discs seated at ground + 0.12 (%d discs, worst dev %.3f)" % [my_discs.size(), worst_disc])
		# Let them drift + pulse (~3.5s), then re-measure: the
		# grounding must hold at the NEW positions.
		for i in 210:
			await get_tree().physics_frame
		var worst_anchor2 := 0.0
		for r in horror.get("_rifts"):
			var ap2: Vector3 = r["pos"]
			worst_anchor2 = maxf(worst_anchor2, absf(ap2.y - _terrain.get_ground_height(ap2)))
		_check(worst_anchor2 <= 0.02, "127: anchors stay grounded through the drift (worst dev %.3f)" % worst_anchor2)
		var worst_disc2 := 0.0
		var worst_track := 0.0
		var anchors2: Array = horror.get("_rifts")
		for b in disc_nodes:
			for n in disc_nodes[b]:
				if is_instance_valid(n):
					var np2 := (n as Node3D).global_position
					worst_disc2 = maxf(worst_disc2, absf(np2.y - (_terrain.get_ground_height(np2) + 0.12)))
					var near := 1e9
					for r in anchors2:
						var ap3: Vector3 = r["pos"]
						near = minf(near, Vector2(np2.x - ap3.x, np2.z - ap3.z).length())
					worst_track = maxf(worst_track, near)
		_check(worst_disc2 <= 0.02, "127: discs stay seated on the ground (worst dev %.3f)" % worst_disc2)
		_check(worst_track <= 2.0, "127: discs track their rifts (worst gap %.2f; batch-disciplined pulse nudges, 1 Hz x 1.2 m/s drift bound plus load slack)" % worst_track)


## [found, spawn_pos, player_pos]: scan each mob spawn (nearest to
## the player's spawn first) over 16 compass directions for a floor
## point 5-8m out whose segment back to the spawn crosses only
## layout FLOOR cells. Returns [false, Vector3.ZERO, Vector3.ZERO].
func _find_encounter() -> Array:
	var layout := _dungeon.get("_layout") as LevelLayout
	var origin := _dungeon.spawn_points[0]
	var spawns: Array = layout.mob_spawns.duplicate()
	spawns.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return Vector2(a.x - origin.x, a.z - origin.z).length() < Vector2(b.x - origin.x, b.z - origin.z).length())
	for s in spawns:
		for k in range(16):
			var ang := TAU * float(k) / 16.0
			var dir := Vector3(cos(ang), 0, sin(ang))
			for d in [8.0, 7.0, 6.0, 5.0]:
				var cand: Vector3 = s + dir * d
				var cell := layout.world_to_cell(cand)
				if layout.is_floor(cell.x, cell.y) and _segment_clear(s, cand, layout):
					return [true, s, cand]
	return [false, Vector3.ZERO, Vector3.ZERO]


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
	_check(float(st["max_dev"]) <= 0.5,
		"walk %s: stayed on ground (max dev %.2f)" % [label, float(st["max_dev"])])
	_check(float(st["min_y"]) > -1.0,
		"walk %s: never fell through (min y %.2f)" % [label, float(st["min_y"])])
	_floor_frames_total += int(st["floor_frames"])
	_frames_total += int(st["frames"])
	print("[DEPTHS] walk %s: floor ratio %.2f, frames %d" % [label, float(st["floor_ratio"]), int(st["frames"])])


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
				if stall_frames > 180: # 3s without progress: snagged
					# (a corridor wedge never resolves by pushing —
					# velocity reads 0 — so the open-field 5s grace
					# only burns time; skip to the next waypoint)
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
	# NO segment shortcutting (unlike the open-field village check):
	# in the maze a diagonal shortcut runs the walker dead-center
	# into corridor props and wedges it (vel 0, no slide progress).
	# Pure cell-center waypoints keep the walker on the corridor
	# center lines, maximally clear of the obstacle cells the BFS
	# already routes around.
	return cells


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
	print("[DEPTHS] shots dir ", _out_dir, " mkdir err=", mk)
	var hud = _dungeon.get("_local_hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	# Photography only (driver-local, same pattern as the docks and
	# village checks): the Depths is near-dark by design (sun 0.0,
	# violet ambient) — kill the fog and add work lights so the
	# terrain relief and palette read in frame for Art's review.
	for child in _dungeon.get_children():
		if child is WorldEnvironment:
			var env := (child as WorldEnvironment).environment
			env.fog_enabled = false
			env.ambient_light_energy = 1.0
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-34, -38, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	var layout := _dungeon.get("_layout") as LevelLayout
	var half := layout.arena_half_size()
	# Overview: whole cavern + annex roofline, oblique for relief.
	cam.position = Vector3(29, 26, 31)
	cam.look_at(Vector3(0, 0, -4), Vector3.UP)
	await _snap("depths_overview.png")
	# Ground level at spawn, looking across the maze.
	var sp := _dungeon.spawn_points[0]
	cam.position = Vector3(sp.x - 3.0, _terrain.get_ground_height(sp) + 2.0, sp.z + 4.0)
	cam.look_at(Vector3(sp.x + 5.0, _terrain.get_ground_height(sp) + 0.8, sp.z - 12.0), Vector3.UP)
	await _snap("depths_spawn_ground.png")
	# Horror arena: above the farthest mob spawn, looking down its room.
	var arena := _farthest_mob_spawn()
	cam.position = Vector3(arena.x + 5.0, _terrain.get_ground_height(arena) + 6.5, arena.z + 6.0)
	cam.look_at(Vector3(arena.x, _terrain.get_ground_height(arena) + 0.6, arena.z), Vector3.UP)
	await _snap("depths_horror_arena.png")
	# Annex approach: on the door axis, looking north through the door.
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var door_in := Vector3(ax + 2.5, 0, -half + 7.0)
	cam.position = Vector3(door_in.x, _terrain.get_ground_height(door_in) + 1.8, door_in.z)
	cam.look_at(Vector3(ax, 1.2, -half - 2.0), Vector3.UP)
	await _snap("depths_annex_approach.png")
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
	await _snap("depths_slope_vista.png")
	print("[DEPTHS] shots saved to ", _out_dir)


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_dir + "/" + file_name)
	print("[DEPTHS] snap ", file_name, " size=", img.get_size(), " err=", err)
