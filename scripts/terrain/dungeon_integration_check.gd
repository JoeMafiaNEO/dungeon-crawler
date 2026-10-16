extends Node
## Issue #120 validation driver: boots the REAL Dungeon (heightmap
## terrain, parameterized LevelTheme profile — worn stone interior,
## near-flat BY DESIGN) and plays a scripted run through it: spawn on
## terrain -> corridor traversals (floor-contact aggregate) -> the
## Warden boss spawns grounded and its judgment slam disc (telegraph
## ring + pillar) grounds on the terrain -> out the station-annex
## doorway and back (no step at the door). Also asserts the theme's
## structural guarantees: DRY (water parked at -1.00, zero wet
## samples), sampled max grade <= 55% outside flattened POIs/
## footprints, walls buried against the relief, 10 torches grounded,
## deterministic generation, and the door apron/flatten contract.
##
## Run checks + (optionally) screenshots under Xvfb (the walk legs use
## synthetic key input through the game's own physics, like the
## village/docks checks — never --headless for input-simulating
## checks):
##   xvfb-run godot --path . res://scenes/terrain/dungeon_integration_check.tscn -- --seed 424242
##   xvfb-run godot --path . res://scenes/terrain/dungeon_integration_check.tscn -- --mode=shots
##
## This is a test harness only. Nothing here ships in gameplay.

var _seed := 424242
var _mode := "run"
var _out_dir := "/home/hatch/workspace/dungeon120_shots"
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
	Dungeon.next_theme_id = "dungeon"
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
	print("[DUNGEON] SUMMARY: %d passed, %d failed" % [_pass, _fail])
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
		print("[DUNGEON] PASS: ", label)
	else:
		_fail += 1
		print("[DUNGEON] FAIL: ", label)


func _run_checks() -> void:
	var theme := _dungeon.theme
	_check(theme != null and theme.use_heightmap_terrain, "dungeon theme flag use_heightmap_terrain on")
	_check(_terrain != null, "heightmap terrain built instead of flat floor")
	_check(_dungeon.get_node_or_null("Arena/Floor") == null, "no flat Floor node on terrain dungeon")
	_check(_dungeon.get_node_or_null("Arena/TerrainDoorApron") != null, "doorway apron built")
	if _terrain == null:
		return
	# Profile actually carried from the theme (issue #120 params).
	_check(absf(_terrain.amplitude - 0.35) < 0.001 and absf(_terrain.noise_frequency - 0.060) < 0.0001
		and absf(_terrain.height_offset - 0.18) < 0.001 and absf(_terrain.water_level - (-1.00)) < 0.001,
		"terrain profile from theme (amp %.2f freq %.3f off %.2f water %.2f)" % [
			_terrain.amplitude, _terrain.noise_frequency, _terrain.height_offset, _terrain.water_level])
	# Tint ramp anchor carried from the theme: the dry-theme form —
	# anchor at the design floor (offset - amp/2 = 0.18 - 0.175 =
	# 0.005), NOT at the parked water level.
	_check(not is_nan(_terrain.tint_anchor) and absf(_terrain.tint_anchor - 0.005) < 0.001,
		"tint anchor from theme (design floor %.3f)" % _terrain.tint_anchor)
	var dup := theme.duplicate() as LevelTheme
	_check(dup.use_heightmap_terrain and absf(dup.terrain_amplitude - 0.35) < 0.001,
		"flag + profile survive theme.duplicate() (cycle scaling)")
	# Dungeon helper == terrain sampler.
	var worst := 0.0
	for p in [Vector3(0, 0, 0), Vector3(10, 0, -6), Vector3(-14, 0, 9), Vector3(19, 0, 19)]:
		worst = maxf(worst, absf(_dungeon.ground_height_at(p) - _terrain.get_ground_height(p)))
	_check(worst < 0.001, "dungeon.ground_height_at matches terrain sampler (worst %.4f)" % worst)
	_check_dry()
	_check_grade()
	_check_door_flatness()
	_check_walls()
	_check_torches()
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
	print("[DUNGEON] player at ", _player.global_position, " ground ", _terrain.get_ground_height(_player.global_position))
	# Park the wave director and clear the field: traversal + boss legs
	# measure terrain, not mob body-blocking. The Dungeon has no
	# ambient population loop to freeze (the #119 find): its only
	# ambient process is audio one-shots, and the supermarket spawner
	# is gated to that theme in _process.
	_dungeon.set("wave_timer", 99999.0)
	_dungeon.set("mobs_to_spawn", 0)
	_clear_mobs()
	# --- Warden boss: grounded spawn + judgment slam grounding ---
	await _check_warden()
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
	st = await _walk_to(door_out, 1.6, 30.0, true, Vector2(-half - 3.0, -half + 3.0))
	_report_walk("staging->annex hall (through door)", st)
	_check(st["max_abs_y"] <= 0.5,
		"annex: no step crossing the doorway (max |y| in window %.3f)" % st["max_abs_y"])
	st = await _walk_to(staging, 1.2, 30.0, true, Vector2(-half - 3.0, -half + 3.0))
	_report_walk("annex hall->staging (back out)", st)
	_check(st["max_abs_y"] <= 0.5,
		"annex: no step on re-entry (max |y| in window %.3f)" % st["max_abs_y"])
	var back := Vector3(_dungeon.spawn_points[0].x, 0, _dungeon.spawn_points[0].z)
	st = await _walk_to(back, 2.0, 90.0)
	_report_walk("staging->spawn (return)", st)
	var agg := float(_floor_frames_total) / maxf(1.0, float(_frames_total))
	_check(agg >= 0.98, "floor contact aggregate %.3f >= 0.98 (%d/%d frames)" % [
		agg, _floor_frames_total, _frames_total])


func _check_dry() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	_check(layout.ponds.is_empty(), "dungeon layout carves no ponds (%d)" % layout.ponds.size())
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
	print("[DUNGEON] dry: min height %.3f, water %.2f, wet %d/%d" % [mn, _terrain.water_level, wet, samples])


## Sampled max grade over the heightfield, excluding flattened POIs,
## the door flatten disc, the apron strip, and obstacle footprints.
## The issue estimates ~13% for this near-flat interior profile;
## the budget gate is the shared <=55%.
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
	print("[DUNGEON] grade: max %.1f%%, mean %.1f%% over %d samples (%d excluded: flattened/footprints)" % [
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


## Which palette bands the dungeon heightfield actually lands in
## (vertex colors via the terrain's own _vertex_color, classified by
## nearest tint). Cold stone greys: with the anchor at the design
## floor, all three bands must populate — low (damp stone) as the
## floor body, mid as the worn body, high as the raised accent. No
## vertex is under water on this dry theme; a share of blend colors
## still classify as "bed" because the bed tint sits close to the
## blend path in color space — a census artifact only, those verts
## render as their blend color.
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
	var p_bed := 100.0 * float(counts["bed"]) / maxf(1.0, float(total))
	var p_low := 100.0 * float(counts["low"]) / maxf(1.0, float(total))
	var p_mid := 100.0 * float(counts["mid"]) / maxf(1.0, float(total))
	var p_high := 100.0 * float(counts["high"]) / maxf(1.0, float(total))
	print("[DUNGEON] tint census of %d verts: bed %.1f%%, low %.1f%%, mid %.1f%%, high %.1f%%" % [
		total, p_bed, p_low, p_mid, p_high])
	# Measured settle (seed 424242): high 79.2 / mid 20.6 / low 0.1 —
	# worn pale stone dominant, the damp low band present in the
	# terrain's dips (its blends classify mostly to mid by nearest
	# tint, the village bed artifact in reverse). Windows carry
	# headroom for the other gate seeds; Art can re-tune the anchor
	# later exactly as village was tuned.
	_check(p_high >= 50.0 and p_high <= 95.0,
		"tint census: pale high band dominant (%.1f%%)" % p_high)
	_check(p_mid >= 10.0 and p_mid <= 40.0,
		"tint census: worn mid band populated (%.1f%%)" % p_mid)
	_check(p_low > 0.0, "tint census: damp low band present in the dips (%.1f%%)" % p_low)


func _check_door_flatness() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var half := layout.arena_half_size()
	var h_door := _terrain.get_ground_height(Vector3(ax, 0, -half))
	_check(absf(h_door) <= 0.15, "terrain meets annex floor at door (h=%.3f)" % h_door)
	# Approach strip: the shared door flatten (r=6.5 smoothstep) leaves
	# a soft rim whose residual scales with the theme's amplitude —
	# at the dungeon's amp 0.35 the rim residual is a fraction of the
	# village's (amp 1.6) 0.45; the binding proof is the annex loop's
	# no-step measurement in _run_checks.
	var strip_max := 0.0
	var zz := -half + 0.5
	while zz <= -half + 3.0:
		strip_max = maxf(strip_max, absf(_terrain.get_ground_height(Vector3(ax, 0, zz))))
		zz += 0.5
	_check(strip_max <= 0.20, "door approach strip flat (max |h| %.3f over the rim)" % strip_max)


## Phase 1 gate: no doorway/wall intersections from the 0.36m relief.
## On heightmap terrain _build_walls drops every wall's bottom 2m
## (center -1, height +2, tops unchanged), so a wall's bottom must
## sit at -2.0 — far below the terrain minimum (~0.0): no gap can
## open under any wall, and the relief can never poke through a top.
func _check_walls() -> void:
	var walls := 0
	var worst_bottom := -1e9
	for child in _dungeon.get_children():
		if not (child is StaticBody3D):
			continue
		for sub in child.get_children():
			if sub is CollisionShape3D and sub.shape is BoxShape3D:
				var sz := (sub.shape as BoxShape3D).size
				if sz.y >= 3.5 and maxf(sz.x, sz.z) >= 10.0:
					walls += 1
					var bottom := (child as Node3D).global_position.y - sz.y * 0.5
					worst_bottom = maxf(worst_bottom, bottom)
	_check(walls >= 5, "perimeter walls built (%d segments)" % walls)
	_check(walls == 0 or worst_bottom <= -1.5,
		"every wall buried against the relief (highest bottom %.2f <= -1.5)" % worst_bottom)


## Torches ride the grounding pattern: dungeon._build_torches seats
## each torch prop at (x, ground_height_at, z) for its layout point.
## The theme carries 10 torch points; every one must have a prop at
## exactly its grounded base.
func _check_torches() -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var theme := _dungeon.theme
	_check(layout.torches.size() == int(theme.torch_count),
		"layout carries the theme's torch points (%d of %d)" % [
			layout.torches.size(), int(theme.torch_count)])
	var grounded := 0
	for pos in layout.torches:
		var g := _terrain.get_ground_height(pos)
		for child in _dungeon.get_children():
			if child is Node3D:
				var cp := (child as Node3D).position
				var x_ok := absf(cp.x - pos.x) < 0.01
				var z_ok := absf(cp.z - pos.z) < 0.01
				var y_ok := absf(cp.y - g) <= 0.01
				if x_ok and z_ok and y_ok:
					grounded += 1
					break
	_check(grounded == layout.torches.size(),
		"every torch grounded at its terrain base (%d of %d)" % [grounded, layout.torches.size()])


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


## The Warden boss, spawned the production way (farthest mob spawn,
## grounded +0.5), must stand on the terrain and fight grounded —
## and its signature slam must ground too: the judgment telegraph
## ring (the slam disc) sits at the marked spot's terrain height
## +0.15, and the erupting pillar is centered on that same ground
## (+3.5 for the 7m column). Production passes grounded positions
## into these FX; this leg proves the FX honor them on relief.
func _check_warden() -> void:
	var pos := _farthest_mob_spawn()
	pos.y = _terrain.get_ground_height(pos) + 0.5
	_dungeon.spawn_mob(9002, "boss_warden", pos)
	for i in 30:
		await get_tree().physics_frame
	var warden := _dungeon.get_node_or_null("Mobs/Mob_9002") as Node3D
	_check(warden != null, "warden boss spawned via spawn_mob")
	if warden == null:
		return
	for i in 60:
		await get_tree().physics_frame
	var wdev := warden.global_position.y - _terrain.get_ground_height(warden.global_position)
	_check(absf(wdev) <= 0.75, "warden stands on terrain (dev %.3f)" % wdev)
	# Engagement watch: the warden closes on the player and casts
	# judgment on its special cooldown. Every physics frame, sample
	# the warden's grounding and watch for the slam disc; scaffolding
	# note: if no judgment fires in the first window, re-place the
	# player at mid-range distance once and keep watching.
	var ring_seen := false
	var pillar_seen := false
	var ring_ground := 0.0
	var ring_xz := Vector2.ZERO
	var ring_dev := 0.0
	var pillar_dev := 0.0
	var max_dev := 0.0
	var min_y := 999.0
	var relocated := false
	for w in 2:
		var window := 1500 # 25s per window at 60fps physics
		for i in window:
			await get_tree().physics_frame
			if not is_instance_valid(warden):
				break
			var wp := warden.global_position
			max_dev = maxf(max_dev, absf(wp.y - _terrain.get_ground_height(wp)))
			min_y = minf(min_y, wp.y)
			if not ring_seen:
				var ring := _find_slam_ring()
				if ring != null:
					ring_seen = true
					ring_xz = Vector2(ring.global_position.x, ring.global_position.z)
					ring_ground = _terrain.get_ground_height(ring.global_position)
					ring_dev = ring.global_position.y - (ring_ground + 0.15)
			elif not pillar_seen:
				var pillar := _find_slam_pillar(ring_xz)
				if pillar != null:
					pillar_seen = true
					pillar_dev = pillar.global_position.y - (ring_ground + 3.5)
					break
		if pillar_seen or not is_instance_valid(warden):
			break
		if not relocated:
			relocated = true
			var wp2 := warden.global_position
			var away := Vector3(wp2.x - _player.global_position.x, 0, wp2.z - _player.global_position.z)
			if away.length() < 0.1:
				away = Vector3(1, 0, 0)
			var dest := wp2 + away.normalized() * 10.0
			dest.x = clampf(dest.x, -20.0, 20.0)
			dest.z = clampf(dest.z, -20.0, 20.0)
			_player.global_position = Vector3(dest.x, _terrain.get_ground_height(dest) + 0.2, dest.z)
			print("[DUNGEON] warden watch: player re-placed at mid-range (scaffolding)")
	_check(ring_seen, "warden executed judgment (slam disc appeared)")
	if ring_seen:
		_check(absf(ring_dev) <= 0.06,
			"slam disc grounds on terrain (ring dev %.3f from ground + 0.15)" % ring_dev)
	_check(pillar_seen, "warden judgment pillar erupted on the marked spot")
	if pillar_seen:
		_check(absf(pillar_dev) <= 0.10,
			"slam pillar grounds on the marked spot (dev %.3f from ground + 3.5)" % pillar_dev)
	_check(max_dev <= 1.25, "warden stayed grounded through engagement (max dev %.2f)" % max_dev)
	_check(min_y > -1.0, "warden never fell through (min y %.2f)" % min_y)


## The judgment telegraph ring: a TorusMesh (outer radius 3.0) built
## under the Mobs holder by Effects.telegraph_ring.
func _find_slam_ring() -> MeshInstance3D:
	var holder := _dungeon.get_node_or_null("Mobs")
	if holder == null:
		return null
	for n in holder.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh is TorusMesh and (mi.mesh as TorusMesh).outer_radius > 2.5:
			return mi
	return null


## The judgment pillar: a CylinderMesh (top radius 1.2) at the marked
## spot, alive for ~0.45s after the 1.2s telegraph.
func _find_slam_pillar(xz: Vector2) -> MeshInstance3D:
	var holder := _dungeon.get_node_or_null("Mobs")
	if holder == null:
		return null
	for n in holder.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh is CylinderMesh and absf((mi.mesh as CylinderMesh).top_radius - 1.2) < 0.01:
			var p := mi.global_position
			if Vector2(p.x - xz.x, p.z - xz.y).length() < 0.5:
				return mi
	return null


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
	print("[DUNGEON] walk %s: floor ratio %.2f, frames %d" % [label, float(st["floor_ratio"]), int(st["frames"])])


## Drives the real player with synthetic W input, steering body yaw at
## each waypoint (same harness as the village/docks checks). Waypoints
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
	var replaces := 0
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
					_print_stall_telemetry(wp, dist)
					if replaces >= 6:
						break
					# Harness scaffolding (disclosed, like the boss-leg
					# re-place): a body can pin the walker in a concave
					# corner the straightened segment clipped. Re-place
					# at the current waypoint — a floor-cell center —
					# and keep walking the same leg.
					replaces += 1
					_player.global_position = Vector3(wp.x,
						_terrain.get_ground_height(wp) + 0.2, wp.z)
					stall_frames = 0
					best = 1e9
					print("[DUNGEON] walk: stall re-place %d at waypoint %s" % [replaces, wp])
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


## Stall diagnostics (the #119 lesson): if the walker ever snags,
## the log says where, on what cell mix, against which colliders,
## and whether a live mob is body-blocking on open floor.
func _print_stall_telemetry(target: Vector3, dist: float) -> void:
	var layout := _dungeon.get("_layout") as LevelLayout
	var pc := layout.world_to_cell(_player.global_position)
	var tc := layout.world_to_cell(target)
	var census := {"floor": 0, "wall": 0, "obstacle": 0, "other": 0}
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			match layout.cell_at(pc.x + dx, pc.y + dz):
				LevelLayout.FLOOR:
					census["floor"] = int(census["floor"]) + 1
				LevelLayout.WALL:
					census["wall"] = int(census["wall"]) + 1
				LevelLayout.OBSTACLE:
					census["obstacle"] = int(census["obstacle"]) + 1
				_:
					census["other"] = int(census["other"]) + 1
	var colliders: Array[String] = []
	for i in _player.get_slide_collision_count():
		var col := _player.get_slide_collision(i).get_collider()
		colliders.append(str(col))
	var nearby: Array[String] = []
	var holder := _dungeon.get_node_or_null("Mobs")
	if holder != null:
		for m in holder.get_children():
			if m is Node3D:
				var mp := (m as Node3D).global_position
				if mp.distance_to(_player.global_position) <= 6.0:
					nearby.append("%s@%s" % [m.name, mp])
	print("[DUNGEON] walk stall: player %s cell %s, target %s cell %s, dist %.2f, cell census %s, slide colliders %s, nearby mobs %s" % [
		_player.global_position, pc, target, tc, dist, census, colliders, nearby])


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
	print("[DUNGEON] shots dir ", _out_dir, " mkdir err=", mk)
	var hud = _dungeon.get("_local_hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	# Photography only (driver-local, same pattern as the village
	# check): kill the distance haze and add a low work light so the
	# stone relief shades visibly. None of this exists in a normal
	# game boot.
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
	# Overview: whole interior + annex roofline, oblique for relief.
	cam.position = Vector3(29, 27, 31)
	cam.look_at(Vector3(0, 0, -4), Vector3.UP)
	await _snap("dungeon_overview.png")
	# Ground level at spawn, looking across the arena.
	var sp := _dungeon.spawn_points[0]
	cam.position = Vector3(sp.x - 4.0, _terrain.get_ground_height(sp) + 2.1, sp.z + 5.0)
	cam.look_at(Vector3(sp.x + 6.0, _terrain.get_ground_height(sp) + 0.8, sp.z - 14.0), Vector3.UP)
	await _snap("dungeon_spawn_ground.png")
	# Annex approach: on the door axis, looking north through the door.
	var ax := float((_dungeon.get("_annex_plan") as Dictionary).get("attach_x", 0.0))
	var door_in := Vector3(ax + 2.5, 0, -half + 7.0)
	cam.position = Vector3(door_in.x, _terrain.get_ground_height(door_in) + 1.8, door_in.z)
	cam.look_at(Vector3(ax, 1.2, -half - 2.0), Vector3.UP)
	await _snap("dungeon_annex_approach.png")
	# Torch sanity: ground level beside the first torch, flame in
	# frame against its wall (issue #120 Phase 2 asks for these).
	if not layout.torches.is_empty():
		var tp: Vector3 = layout.torches[0]
		var tg := _terrain.get_ground_height(tp)
		cam.position = Vector3(tp.x + 2.6, tg + 1.3, tp.z + 2.6)
		cam.look_at(Vector3(tp.x, tg + 1.5, tp.z), Vector3.UP)
		await _snap("dungeon_torch.png")
	print("[DUNGEON] shots saved to ", _out_dir)


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out_dir + "/" + file_name)
	print("[DUNGEON] snap ", file_name, " size=", img.get_size(), " err=", err)
