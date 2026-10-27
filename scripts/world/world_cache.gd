extends RefCounted
## WorldCache (Jesse's anti-hitch package, 2026-10-26): a
## purely local, disposable disk cache for the world
## generators' pure outputs — chunk data (WorldGen) and
## nature scatter (ScatterGen) — under user://world_cache/.
##
## Both generators are pure functions of (WORLD_SEED, cx,
## cz), so a cached payload is never authoritative: it is
## the function's own output, saved. A miss, a corrupt file,
## or a version/seed mismatch simply regenerates. Deleting
## the whole directory is always safe. Nothing here is
## synced, saved to a slot, or shared between machines.
##
## Measured case (VM, 2026-10-26): generate_chunk costs
## 42-62 ms; a cache roundtrip costs ~0.05 ms and 1.5-5 KB
## per chunk. Revisits stop paying generation entirely.
##
## All file I/O happens on the caller's thread (the
## streamer calls these from its main-thread paths only).

const CACHE_VERSION := 1
const DIR_PATH := "user://world_cache"

const WorldGen := preload("res://scripts/world/world_gen.gd")
const ChunkData := preload("res://scripts/world/chunk_data.gd")


static func _path_for(cx: int, cz: int) -> String:
	return "%s/chunk_%d_%d.bin" % [DIR_PATH, cx, cz]


static func _ensure_dir() -> void:
	var d := DirAccess.open("user://")
	if d != null and not d.dir_exists("world_cache"):
		d.make_dir("world_cache")


## The validated payload for a chunk, or {} when absent or
## untrustworthy. Validation is strict: version, seed,
## coords, and field shapes must all match what the pure
## generators would produce, or the payload is ignored.
static func read_payload(cx: int, cz: int) -> Dictionary:
	var path := _path_for(cx, cz)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var raw = bytes_to_var(f.get_buffer(f.get_length()))
	if not (raw is Dictionary):
		return {}
	var p: Dictionary = raw
	if int(p.get("v", -1)) != CACHE_VERSION:
		return {}
	if int(p.get("seed", -1)) != WorldGen.WORLD_SEED:
		return {}
	if int(p.get("cx", 0)) != cx or int(p.get("cz", 0)) != cz:
		return {}
	return p


static func _payload_valid_data(p: Dictionary) -> bool:
	if not p.has("lots") or not p.has("buildings") \
			or not p.has("heights"):
		return false
	if not (p["lots"] is PackedByteArray) \
			or (p["lots"] as PackedByteArray).size() \
				!= WorldGen.LOTS_PER_CHUNK * WorldGen.LOTS_PER_CHUNK:
		return false
	if not (p["heights"] is PackedFloat32Array) \
			or (p["heights"] as PackedFloat32Array).size() \
				!= (WorldGen.LOTS_PER_CHUNK + 1) \
					* (WorldGen.LOTS_PER_CHUNK + 1):
		return false
	if not (p["buildings"] is Array):
		return false
	return true


## The chunk's data from cache, or null on a miss.
static func read_data(cx: int, cz: int) -> RefCounted:
	var p := read_payload(cx, cz)
	if p.is_empty() or not _payload_valid_data(p):
		return null
	var d := ChunkData.new()
	d.cx = cx
	d.cz = cz
	d.lots = p["lots"]
	d.buildings = p["buildings"]
	d.heights = p["heights"]
	return d


## The chunk's scatter output from cache, or null when the
## payload carries none (or is untrustworthy).
static func read_scatter(cx: int, cz: int) -> Variant:
	var p := read_payload(cx, cz)
	if p.is_empty() or not _payload_valid_data(p):
		return null
	var s = p.get("scatter", null)
	if s is Dictionary:
		return s
	return null


static func _write_payload(cx: int, cz: int, p: Dictionary) -> void:
	_ensure_dir()
	var f := FileAccess.open(_path_for(cx, cz), FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(var_to_bytes(p))


static func _base_payload(cx: int, cz: int) -> Dictionary:
	return {"v": CACHE_VERSION, "seed": WorldGen.WORLD_SEED,
		"cx": cx, "cz": cz, "scatter": null}


## Merge-write a generated chunk's data, preserving any
## scatter already cached for it.
static func write_data(data: RefCounted) -> void:
	var cx: int = data.cx
	var cz: int = data.cz
	var p := read_payload(cx, cz)
	if p.is_empty() or not _payload_valid_data(p):
		p = _base_payload(cx, cz)
	p["lots"] = data.lots
	p["buildings"] = data.buildings
	p["heights"] = data.heights
	_write_payload(cx, cz, p)


## Merge-write a computed scatter output, preserving the
## chunk data already cached for it. (If no data is cached
## yet the scatter is dropped — scatter without its chunk
## data would fail validation on read anyway.)
static func write_scatter(cx: int, cz: int, scatter: Dictionary) -> void:
	var p := read_payload(cx, cz)
	if p.is_empty() or not _payload_valid_data(p):
		return
	p["scatter"] = scatter
	_write_payload(cx, cz, p)
