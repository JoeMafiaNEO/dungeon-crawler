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
var _out_path := ""
var _manifest_path := PREGEN_DIR + "/bake_manifest.json"
var _verify := false
var _failures: Array[String] = []


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
		elif key == "--out":
			_out_path = val
		elif key == "--manifest":
			_manifest_path = val
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
	Dungeon.next_level_number = 1
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
	data.fill(_theme_id, _seed, layout, heights, map_points, terrain_cell)
	data.terrain_mode = "mesh"
	_own_recursive(bake_root, bake_root)
	var target := "user://rebake_check.tscn" if _verify else _out_path
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var size := _save_scene(bake_root, target)
	if size < 0:
		return ERR_CANT_CREATE
	var mode := "mesh"
	if size > SIZE_BUDGET_BYTES:
		# Specced fallback: heights-as-data, surface regenerated at load.
		_strip_terrain_surface(arena)
		data.terrain_mode = "heights"
		mode = "heights"
		size = _save_scene(bake_root, target)
		if size < 0:
			return ERR_CANT_CREATE
		print("[BAKE] full capture busted the %d-byte budget; stripped to heights-as-data" % SIZE_BUDGET_BYTES)
	print("[BAKE] theme=%s seed=%d hash=%s mode=%s bytes=%d -> %s" % [
		_theme_id, _seed, data.content_hash, mode, size, target])
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
	scenes[_theme_id] = {
		"theme_id": _theme_id,
		"seed": _seed,
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
