extends Node
## Issue #138 Phase 1: the pregenerated-level bake tool (dev only,
## never runs at runtime). Drives the EXISTING build path for one
## (theme, seed) pair — real ProcGen, real Dungeon._build_arena_from_
## layout() — then captures the result as a shipped scene file:
## scenes/levels/pregen/theme_<id>.tscn = the Arena subtree (static
## geometry only) + a LevelData node (layout + terrain heights +
## content hash). No second generator: what ships is what today's
## code builds, frozen.
##
## Run (headless is fine — the bake simulates no input):
##   godot --headless --path . res://tools/bake_levels.tscn -- --theme village --seed 1
##   godot --headless --path . res://tools/bake_levels.tscn -- --theme village --seed 1 --verify
##
## --verify re-bakes to a scratch file and compares the result's
## LevelData content_hash against the shipped scene's — a mismatch
## means procgen drifted from the shipped level.
##
## --manifest-key <key> (issue #151) writes the manifest scenes entry
## under <key> instead of the theme_id — the batch wrapper uses
## <theme>_<seed> keys so variants don't clobber each other. Without
## it, behavior is exactly as before.
##
## --cycle N (issue #153 D1, default 1): bake the level as cycle N.
## Scaling is NOT reimplemented here — at N >= 2 the dungeon boots
## at level number (N-1)*5 + slot + 1 (slot = the theme's index in
## Dungeon.THEME_ORDER; Misty Docks uses slot 0, arbitrary but fixed)
## and its own _ready duplicates/scales/generates exactly as in
## production. At N = 1 the boot is byte-identical to before
## (next_level_number = 1). The cycle is stamped on LevelData and
## into the v2 content hash.
##
## --players N (issue #153 D1 (B), default 1): the party size a
## WARLORD bake is generated for, carried on Dungeon.next_player_
## count exactly like a real departure handoff (#154). Only warlord
## consumes it; other themes record player_count 1 (a [BAKE] note
## says so when N != 1 is requested for them).
##
## HONEST SCOPE: cycle >= 2 bakes and warlord player-count >= 2
## bakes are LIBRARY-ONLY — the runtime consumes exactly the cycle-1
## 1-player pinned scene per theme. Wiring the library into rotation
## is a separate, Jesse-gated step.
##
## Output is atomic: the scene is saved to <out>.tmp.tscn first and
## renamed onto the target only after a successful save, so a killed
## bake never leaves a partial file at the target path.
##
## Note: the engine may abort during process teardown after a
## successful bake (the same flaky exit crash the headless suite
## shows after "All tests passed!"). The [BAKE] lines and the files
## on disk are the authoritative result, not the exit code.
##
## Size budget (spec #138 section 7): <= 2 MB per scene. If the full
## capture busts it, the terrain's runtime-built children (mesh,
## collision, water) are stripped and the scene ships heights-as-data
## only (LevelData.terrain_mode = "heights"); the surface is then
## regenerated from the heights at load by the same terrain code.

const SIZE_BUDGET_BYTES := 2_000_000
const PREGEN_DIR := "res://scenes/levels/pregen"

var _theme_id := "village"
var _seed := 1
var _cycle := 1
var _players := 1
var _out_path := ""
var _manifest_path := PREGEN_DIR + "/bake_manifest.json"
var _manifest_key := ""
var _verify := false
var _eff_players := 1
var _failures: Array[String] = []

## Issue #153 D1: THEME_ORDER slots for the cycle level-number
## formula (mirrors Dungeon.THEME_ORDER; Misty Docks is not in the
## runtime rotation and uses slot 0 — arbitrary but fixed, since its
## scaling depends only on the cycle index).
const THEME_SLOTS := {
	"village": 0, "dungeon": 1, "depths": 2,
	"supermarket": 3, "warlord": 4, "misty_docks": 0,
}


func _ready() -> void:
	_parse_args()
	await get_tree().process_frame
	var err := await _bake()
	if err != OK:
		for f in _failures:
			push_error("[BAKE] " + f)
		print("[BAKE] FAILED (%d problems)" % maxi(_failures.size(), 1))
		get_tree().quit(1)
		return
	get_tree().quit(0)


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
		elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
			val = args[i + 1]
			i += 1
		if key == "--theme":
			_theme_id = val
		elif key == "--seed":
			_seed = int(val)
		elif key == "--cycle":
			_cycle = maxi(1, int(val))
		elif key == "--players":
			_players = maxi(1, int(val))
		elif key == "--out":
			_out_path = val
		elif key == "--manifest":
			_manifest_path = val
		elif key == "--manifest-key":
			_manifest_key = val
		elif key == "--verify":
			_verify = true
		i += 1
	if _out_path == "":
		_out_path = PREGEN_DIR + "/theme_%s.tscn" % _theme_id


func _bake() -> int:
	NetworkManager.selected_class_id = "warrior"
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = _theme_id
	Dungeon.next_seed = _seed
	# Issue #153 D1: cycle >= 2 boots at the cycle's own level number
	# so the dungeon's _ready applies production cycle scaling;
	# cycle 1 keeps next_level_number = 1, exactly as before. (B):
	# the party size rides the #154 handoff static — only warlord
	# consumes it; every other theme records player_count 1.
	_eff_players = _players if _theme_id == "warlord" else 1
	if _theme_id != "warlord" and _players != 1:
		print("[BAKE] NOTE: --players %d ignored for theme %s — player_count recorded as 1 (only warlord consumes it)" % [_players, _theme_id])
	Dungeon.next_level_number = 1 if _cycle <= 1 else (_cycle - 1) * 5 + int(THEME_SLOTS.get(_theme_id, 0)) + 1
	Dungeon.next_player_count = _eff_players
	var packed := load("res://scenes/dungeon/dungeon.tscn") as PackedScene
	if packed == null:
		_failures.append("dungeon.tscn failed to load")
		return ERR_CANT_OPEN
	var dungeon := packed.instantiate()
	get_tree().root.add_child(dungeon)
	get_tree().current_scene = dungeon
	for i in 12:
		await get_tree().physics_frame
	# Freeze the level exactly as built: no wave spawns during capture.
	dungeon.set("wave_timer", 99999.0)
	dungeon.set("mobs_to_spawn", 0)
	var arena: Node3D = dungeon.get("_arena")
	var layout: LevelLayout = dungeon.get("_layout")
	if arena == null or layout == null:
		_failures.append("dungeon built no Arena/layout (theme %s seed %d)" % [_theme_id, _seed])
		return ERR_UNAVAILABLE
	var terrain = dungeon.get("_terrain")
	var heights := PackedFloat32Array()
	var map_points := 0
	var terrain_cell := 1.0
	if terrain != null:
		heights = terrain.heights_copy()
		map_points = int(terrain.get("map_points"))
		terrain_cell = float(terrain.get("cell_size"))
	# --- Capture: new scene root + stolen Arena + LevelData. ---
	var bake_root := Node3D.new()
	bake_root.name = "theme_" + _theme_id
	dungeon.remove_child(arena)
	bake_root.add_child(arena)
	var data := LevelData.new()
	data.name = "LevelData"
	bake_root.add_child(data)
	data.fill(_theme_id, _seed, layout, heights, map_points, terrain_cell, _cycle, _eff_players)
	data.terrain_mode = "mesh"
	_own_recursive(bake_root, bake_root)
	var target := "user://rebake_check.tscn" if _verify else _out_path
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	# Issue #153 D1: atomic output — save to a .tmp.tscn sibling and
	# rename onto the target only after a successful save, so a
	# killed bake leaves no partial file at the target. The --verify
	# scratch target is exempt (it is not a deliverable).
	var save_path := target
	if not _verify:
		save_path = target.get_basename() + ".tmp.tscn"
	var size := _save_scene(bake_root, save_path)
	if size < 0:
		return ERR_CANT_CREATE
	var mode := "mesh"
	if size > SIZE_BUDGET_BYTES:
		# Specced fallback: heights-as-data, surface regenerated at load.
		_strip_terrain_surface(arena)
		data.terrain_mode = "heights"
		mode = "heights"
		size = _save_scene(bake_root, save_path)
		if size < 0:
			return ERR_CANT_CREATE
		print("[BAKE] full capture busted the %d-byte budget; stripped to heights-as-data" % SIZE_BUDGET_BYTES)
	if not _verify:
		var ren := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(target))
		if ren != OK:
			_failures.append("atomic rename failed (%d): %s -> %s" % [ren, save_path, target])
			return ERR_CANT_CREATE
	print("[BAKE] theme=%s seed=%d cycle=%d players=%d hash=%s mode=%s bytes=%d -> %s" % [
		_theme_id, _seed, _cycle, _eff_players, data.content_hash, mode, size, target])
	var result := OK
	if _verify:
		result = _verify_against_shipped(data)
	else:
		_update_manifest(data, size, mode)
	if not _failures.is_empty():
		result = ERR_INVALID_DATA
	return result


func _save_scene(bake_root: Node3D, path: String) -> int:
	var ps := PackedScene.new()
	var err := ps.pack(bake_root)
	if err != OK:
		_failures.append("PackedScene.pack failed (%d)" % err)
		return -1
	err = ResourceSaver.save(ps, path)
	if err != OK:
		_failures.append("ResourceSaver.save failed (%d) for %s" % [err, path])
		return -1
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_failures.append("saved scene unreadable: %s" % path)
		return -1
	return int(f.get_length())


## Set owner = bake root on every descendant so pack() includes the
## whole subtree — except scene-instance roots (instanced .glb prop
## models): those are stored as instances of their source scene and
## their children keep belonging to that source.
func _own_recursive(node: Node, bake_root: Node) -> void:
	for child in node.get_children():
		child.owner = bake_root
		if child.scene_file_path == "":
			_own_recursive(child, bake_root)


func _strip_terrain_surface(arena: Node) -> void:
	var terrain := arena.get_node_or_null("HeightmapTerrain")
	if terrain == null:
		return
	for child_name in ["TerrainMesh", "TerrainBody", "WaterPlane"]:
		var child := terrain.get_node_or_null(child_name)
		if child != null:
			terrain.remove_child(child)
			child.free()


func _verify_against_shipped(fresh: LevelData) -> int:
	var shipped_ps := load(_out_path) as PackedScene
	if shipped_ps == null:
		_failures.append("verify: shipped scene missing: %s" % _out_path)
		return ERR_FILE_NOT_FOUND
	var shipped := shipped_ps.instantiate()
	var shipped_data: LevelData = shipped.get_node_or_null("LevelData")
	if shipped_data == null:
		_failures.append("verify: shipped scene has no LevelData node")
		return ERR_UNAVAILABLE
	var ok := shipped_data.content_hash == fresh.content_hash
	print("[BAKE] VERIFY %s: shipped=%s rebaked=%s" % [
		"PASS" if ok else "FAIL", shipped_data.content_hash, fresh.content_hash])
	if not ok:
		_failures.append("verify: content hash mismatch (procgen drifted from the shipped scene)")
		return ERR_INVALID_DATA
	return OK


func _update_manifest(data: LevelData, size: int, mode: String) -> void:
	var manifest := {"version": 1, "scenes": {}}
	if FileAccess.file_exists(_manifest_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_manifest_path))
		if parsed is Dictionary and parsed.has("scenes"):
			manifest = parsed
	var scenes: Dictionary = manifest["scenes"]
	# Issue #151: the batch wrapper keys variant entries <theme>_<seed>
	# via --manifest-key; without it the key is the theme_id, exactly
	# as the shipped cycle-1 flow has always written it.
	var entry_key := _manifest_key if _manifest_key != "" else _theme_id
	scenes[entry_key] = {
		"theme_id": _theme_id,
		"seed": _seed,
		"cycle": _cycle,
		"player_count": _eff_players,
		"content_hash": data.content_hash,
		"scene_path": _out_path,
		"scene_bytes": size,
		"terrain_mode": mode,
		"bake_date": Time.get_date_string_from_system(),
	}
	manifest["scenes"] = scenes
	var f := FileAccess.open(_manifest_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(manifest, "\t") + "\n")
		print("[BAKE] manifest updated: %s" % _manifest_path)
	else:
		_failures.append("manifest not writable: %s" % _manifest_path)
