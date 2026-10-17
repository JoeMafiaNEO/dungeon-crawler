class_name LevelData
extends Node3D
## Issue #138: the serialized runtime data baked into a pregenerated
## level scene (scenes/levels/pregen/theme_<id>.tscn) next to its Arena
## subtree. Carries everything runtime systems query from the live
## build today: the complete LevelLayout (rebuilt by to_layout()) and
## the post-flatten / post-carve terrain height array (the baked mesh
## alone cannot answer ground_height_at() queries).
##
## content_hash is computed at bake time over the canonical layout
## fingerprint plus the raw height bytes: procgen drift changes one of
## those inputs, so a re-bake that no longer reproduces the shipped
## hash fails loudly instead of silently changing a shipped level
## (spec #138 section 6b). This script names no autoloads — it is safe
## to load from the headless test suite.

@export var theme_id: String = ""
@export var level_seed: int = 0
## Issue #153 D1: the cycle this bake was generated at (1 = the
## shipped pinned library; higher cycles are library-only today).
@export var cycle: int = 1
## Issue #153 D1 (B): the player count a warlord bake was generated
## for. Only warlord's grid depends on it; every other theme records
## 1. Part of the v2 content hash — a p2 warlord bake can never
## collide with the p1 scene's hash.
@export var player_count: int = 1
@export var content_hash: String = ""
## How the terrain surface ships: "mesh" = the generated mesh +
## collision are frozen into the scene; "heights" = the scene carries
## heights only and the surface is regenerated from them at load by
## HeightmapTerrain.build_from_heights() (the specced size fallback).
@export var terrain_mode: String = "mesh"
@export var grid_size: int = 0
@export var cell_size: float = 2.0
@export var grid: PackedByteArray = PackedByteArray()
@export var props_data: Array[Dictionary] = []
@export var ponds_data: Array[Dictionary] = []
@export var torches: PackedVector3Array = PackedVector3Array()
@export var player_spawns: PackedVector3Array = PackedVector3Array()
@export var mob_spawns: PackedVector3Array = PackedVector3Array()
@export var maze_dead_ends: PackedVector3Array = PackedVector3Array()
@export var fishing_spots: PackedVector3Array = PackedVector3Array()
@export var farm_plots: PackedVector3Array = PackedVector3Array()
@export var heights: PackedFloat32Array = PackedFloat32Array()
@export var terrain_map_points: int = 0
@export var terrain_cell_size: float = 1.0


## --- Bake manifest access (issue #138 Phase 2) ---
## The manifest the bake tool writes next to the scenes is the single
## runtime source for which themes are baked and their pins. Read
## once, cached in a static. Missing/corrupt manifest = no baked
## themes (pure procgen game, exactly the pre-#138 behavior).

const MANIFEST_PATH := "res://scenes/levels/pregen/bake_manifest.json"
const PREGEN_DIR := "res://scenes/levels/pregen"

static var _manifest_cache: Dictionary = {}
static var _manifest_read := false
static var _shipped_hash_cache: Dictionary = {}


static func manifest_entry(theme_id: String) -> Dictionary:
	if not _manifest_read:
		_manifest_read = true
		if FileAccess.file_exists(MANIFEST_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
			if parsed is Dictionary:
				_manifest_cache = parsed
	var scenes: Dictionary = _manifest_cache.get("scenes", {})
	var entry = scenes.get(theme_id, {})
	return entry if entry is Dictionary else {}


static func baked_scene_path(theme_id: String) -> String:
	var entry := manifest_entry(theme_id)
	return str(entry.get("scene_path", ""))


static func pinned_seed(theme_id: String) -> int:
	var entry := manifest_entry(theme_id)
	if entry.is_empty():
		return -1
	return int(entry.get("seed", -1))


## The content hash of the baked scene THIS build ships for a theme
## ("" = no baked scene). Read from the shipped scene's LevelData —
## not the manifest — because the MP handshake must verify the actual
## artifact a peer would load, and cached after the first read.
static func shipped_hash(theme_id: String) -> String:
	if _shipped_hash_cache.has(theme_id):
		return str(_shipped_hash_cache[theme_id])
	var result := ""
	var path := baked_scene_path(theme_id)
	if path != "" and ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			var inst = ps.instantiate()
			var data = inst.get_node_or_null("LevelData")
			if data != null:
				result = str(data.get("content_hash"))
			inst.free()
	_shipped_hash_cache[theme_id] = result
	return result


static func _pack_vec3s(list: Array[Vector3]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in list:
		out.append(v)
	return out


static func _unpack_vec3s(packed: PackedVector3Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for v in packed:
		out.append(v)
	return out


## Fill from a live generation (the bake tool path): copies the layout
## fields and the terrain's final height array, then stamps the
## content hash. Flat themes pass an empty height array / 0 points.
func fill(p_theme_id: String, p_seed: int, layout: LevelLayout,
		p_heights: PackedFloat32Array, p_map_points: int, p_terrain_cell: float,
		p_cycle: int = 1, p_player_count: int = 1) -> void:
	theme_id = p_theme_id
	level_seed = p_seed
	cycle = p_cycle
	player_count = p_player_count
	grid_size = layout.grid_size
	cell_size = layout.cell_size
	grid = layout.grid.duplicate()
	props_data = layout.props.duplicate(true)
	ponds_data = layout.ponds.duplicate(true)
	torches = _pack_vec3s(layout.torches)
	player_spawns = _pack_vec3s(layout.player_spawns)
	mob_spawns = _pack_vec3s(layout.mob_spawns)
	maze_dead_ends = _pack_vec3s(layout.maze_dead_ends)
	fishing_spots = _pack_vec3s(layout.fishing_spots)
	farm_plots = _pack_vec3s(layout.farm_plots)
	heights = p_heights.duplicate()
	terrain_map_points = p_map_points
	terrain_cell_size = p_terrain_cell
	content_hash = compute_content_hash()


## Rebuild the LevelLayout the runtime systems consume. The result's
## fingerprint() equals the baked generation's exactly.
func to_layout() -> LevelLayout:
	var layout := LevelLayout.new()
	layout.grid_size = grid_size
	layout.cell_size = cell_size
	layout.grid = grid.duplicate()
	layout.props = props_data.duplicate(true)
	layout.ponds = ponds_data.duplicate(true)
	layout.torches = _unpack_vec3s(torches)
	layout.player_spawns = _unpack_vec3s(player_spawns)
	layout.mob_spawns = _unpack_vec3s(mob_spawns)
	layout.maze_dead_ends = _unpack_vec3s(maze_dead_ends)
	layout.fishing_spots = _unpack_vec3s(fishing_spots)
	layout.farm_plots = _unpack_vec3s(farm_plots)
	return layout


## Content hash v2 (issue #153 D1 — one format, forever): SHA-256
## over theme + seed + cycle + player_count + the canonical layout
## fingerprint + the raw height bytes. Deterministic across machines
## and runs: every input derives from (theme, seed, cycle, players)
## through the existing generation path, and floats serialize
## exactly. (v1 hashed theme + seed + fingerprint + heights only;
## pre-D1 variant files keep their v1 hashes until re-baked.)
func compute_content_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var header := "%s\n%d\n%d\n%d\n%s\n" % [theme_id, level_seed, cycle, player_count, to_layout().fingerprint()]
	ctx.update(header.to_utf8_buffer())
	ctx.update(heights.to_byte_array())
	return ctx.finish().hex_encode()
