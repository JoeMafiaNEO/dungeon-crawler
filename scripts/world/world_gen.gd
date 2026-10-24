extends RefCounted
## WorldGen (issue #197): the PURE procedural world generator.
##
## generate_chunk(cx, cz) is a pure function of (seed, cx, cz): same
## inputs -> identical ChunkData, on any machine, in any generation
## order. Every random choice derives from an integer hash of
## (seed, coords, layer_salt) — there is NO global RNG state anywhere
## in this file. Neighborhood lookups are bounded by construction:
## the settlement lattice cells overlapping the chunk plus a fixed
## one-cell margin for density/roads, two cells for a settlement's
## own neighbor search. No unbounded scans, ever.
##
## Layers (brief order): settlement lattice -> roads -> terrain ->
## lots & buildings. WORLD_SEED is the single seed source; the seed
## parameter exists so the suite can prove seed sensitivity — game
## code always uses the default.

const WORLD_SEED := 20261023
const CHUNK_SIZE := 128.0
const LOT_SIZE := 8.0
const LOTS_PER_CHUNK := 16
const CELL_CHUNKS := 8 ## settlement lattice cell = 8x8 chunks
const ROAD_HALF_WIDTH := 6.0 ## meters from a segment = road lot
const FLOOR_HEIGHT := 3.0

# Layer salts (hash domain separation).
const SALT_CELL_KIND := 11
const SALT_CELL_JX := 12
const SALT_CELL_JZ := 13
const SALT_CELL_RADIUS := 14
const SALT_NOISE := 100
const SALT_LOT_ROLL := 200
const SALT_LOT_CLASS := 201
const SALT_FLOORS := 202
const SALT_STYLE := 203

const ChunkData := preload("res://scripts/world/chunk_data.gd")


# ------------------------------------------------------------------
# Hashing: deterministic integer mixes (portable, wrap-safe).
# ------------------------------------------------------------------

static func _mix32(h: int) -> int:
	h &= 0xFFFFFFFF
	h ^= h >> 16
	h = (h * 0x7FEB352D) & 0xFFFFFFFF
	h ^= h >> 15
	h = (h * 0x846CA68B) & 0xFFFFFFFF
	h ^= h >> 16
	return h


static func _hash_int(seed: int, x: int, z: int, salt: int) -> int:
	var h := seed & 0xFFFFFFFF
	h = _mix32(h ^ (x & 0xFFFFFFFF))
	h = _mix32(h ^ (z & 0xFFFFFFFF))
	h = _mix32(h ^ (salt & 0xFFFFFFFF))
	return h


## Uniform [0, 1) from a hash of (seed, x, z, salt).
static func rand01(seed: int, x: int, z: int, salt: int) -> float:
	return float(_hash_int(seed, x, z, salt) & 0xFFFFFF) / float(0x1000000)


static func _cell_of(chunk_coord: int) -> int:
	var q := chunk_coord / CELL_CHUNKS
	if chunk_coord % CELL_CHUNKS != 0 and chunk_coord < 0:
		q -= 1
	return q


# ------------------------------------------------------------------
# Layer 1: the settlement lattice.
# ------------------------------------------------------------------

## The settlement candidate for one lattice cell, or {} when the
## cell is empty. Dictionary: {kind, gx, gz, center (Vector2 world),
## radius_chunks, strength}.
static func settlement_in_cell(seed: int, gx: int, gz: int) -> Dictionary:
	var roll := rand01(seed, gx, gz, SALT_CELL_KIND)
	var kind := ""
	if roll < 0.10:
		kind = "city"
	elif roll < 0.45:
		kind = "village"
	if kind == "":
		return {}
	var jx := rand01(seed, gx, gz, SALT_CELL_JX)
	var jz := rand01(seed, gx, gz, SALT_CELL_JZ)
	var center := Vector2(
		(float(gx * CELL_CHUNKS) + jx * CELL_CHUNKS) * CHUNK_SIZE,
		(float(gz * CELL_CHUNKS) + jz * CELL_CHUNKS) * CHUNK_SIZE)
	var rr := rand01(seed, gx, gz, SALT_CELL_RADIUS)
	if kind == "city":
		return {"kind": kind, "gx": gx, "gz": gz, "center": center,
			"radius_chunks": 4.0 + rr * 2.0, "strength": 1.0}
	return {"kind": kind, "gx": gx, "gz": gz, "center": center,
		"radius_chunks": 1.0 + rr * 1.0, "strength": 0.42}


## All settlements in the lattice cells within `cell_margin` of the
## cell containing chunk (cx, cz).
static func settlements_near(seed: int, cx: int, cz: int, cell_margin: int) -> Array:
	var out: Array = []
	var gx0 := _cell_of(cx)
	var gz0 := _cell_of(cz)
	for gx in range(gx0 - cell_margin, gx0 + cell_margin + 1):
		for gz in range(gz0 - cell_margin, gz0 + cell_margin + 1):
			var s := settlement_in_cell(seed, gx, gz)
			if not s.is_empty():
				out.append(s)
	return out


## Settlement density at a world position: {density 0..1, kind of
## the dominant settlement, center of it}. Bounded: cells +-1 (a
## settlement two cells away is >= 8 chunks off, beyond the maximum
## 6-chunk influence radius).
static func density_at_world(seed: int, wx: float, wz: float) -> Dictionary:
	var cx := int(floor(wx / CHUNK_SIZE))
	var cz := int(floor(wz / CHUNK_SIZE))
	var total := 0.0
	var best := 0.0
	var best_kind := ""
	var best_center := Vector2.ZERO
	for s in settlements_near(seed, cx, cz, 1):
		var c: Vector2 = s["center"]
		var d_chunks := Vector2(wx - c.x, wz - c.y).length() / CHUNK_SIZE
		var r := float(s["radius_chunks"])
		if d_chunks >= r:
			continue
		var t := 1.0 - d_chunks / r
		var contrib := float(s["strength"]) * t * t
		total += contrib
		if contrib > best:
			best = contrib
			best_kind = str(s["kind"])
			best_center = c
	return {"density": clampf(total, 0.0, 1.0), "kind": best_kind,
		"center": best_center}


# ------------------------------------------------------------------
# Layer 2: roads.
# ------------------------------------------------------------------

## A settlement's road targets: its 2 nearest neighbor settlements
## (deterministic: distance, then cell coords break ties). The
## neighbor search is bounded to cells +-2.
static func road_targets(seed: int, s: Dictionary) -> Array:
	var cands: Array = []
	var gx := int(s["gx"])
	var gz := int(s["gz"])
	for ogx in range(gx - 2, gx + 3):
		for ogz in range(gz - 2, gz + 3):
			if ogx == gx and ogz == gz:
				continue
			var o := settlement_in_cell(seed, ogx, ogz)
			if o.is_empty():
				continue
			var d: float = (o["center"] as Vector2).distance_to(s["center"])
			cands.append({"d": d, "gx": ogx, "gz": ogz, "s": o})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["d"]) != float(b["d"]):
			return float(a["d"]) < float(b["d"])
		if int(a["gx"]) != int(b["gx"]):
			return int(a["gx"]) < int(b["gx"])
		return int(a["gz"]) < int(b["gz"]))
	var out: Array = []
	for i in mini(2, cands.size()):
		out.append(cands[i]["s"])
	return out


## Every road segment that can cross chunk (cx, cz), as [Vector2,
## Vector2] world-space endpoint pairs. Collection rule (what makes
## border continuity hold by construction): an edge is included
## when EITHER endpoint settlement sits within one cell of the
## chunk's cell — candidates are gathered from cells +-2 so edges
## pointing INTO the neighborhood are never missed.
static func road_segments_near_chunk(seed: int, cx: int, cz: int) -> Array:
	var near_keys := {}
	for s in settlements_near(seed, cx, cz, 1):
		near_keys["%d,%d" % [int(s["gx"]), int(s["gz"])]] = true
	var seen := {}
	var out: Array = []
	for s in settlements_near(seed, cx, cz, 2):
		var skey := "%d,%d" % [int(s["gx"]), int(s["gz"])]
		for t in road_targets(seed, s):
			var tkey := "%d,%d" % [int(t["gx"]), int(t["gz"])]
			if not near_keys.has(skey) and not near_keys.has(tkey):
				continue
			var ekey := skey + ">" + tkey if skey < tkey else tkey + ">" + skey
			if seen.has(ekey):
				continue
			seen[ekey] = true
			out.append([s["center"], t["center"]])
	return out


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ------------------------------------------------------------------
# Layer 3: terrain.
# ------------------------------------------------------------------

static func _smooth_noise(seed: int, wx: float, wz: float, cell: float, salt: int) -> float:
	var fx := wx / cell
	var fz := wz / cell
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var sx := tx * tx * (3.0 - 2.0 * tx)
	var sz := tz * tz * (3.0 - 2.0 * tz)
	var v00 := rand01(seed, ix, iz, salt)
	var v10 := rand01(seed, ix + 1, iz, salt)
	var v01 := rand01(seed, ix, iz + 1, salt)
	var v11 := rand01(seed, ix + 1, iz + 1, salt)
	return lerpf(lerpf(v00, v10, sx), lerpf(v01, v11, sx), sz)


static func _raw_height(seed: int, wx: float, wz: float) -> float:
	var h := 0.0
	var amp := 16.0
	var cell := 192.0
	for o in 4:
		h += amp * (_smooth_noise(seed, wx, wz, cell, SALT_NOISE + o) - 0.5) * 2.0
		amp *= 0.5
		cell *= 0.5
	return h


## World-space terrain height (pure). Inside settlement influence
## the ground flattens toward the dominant settlement's own raw
## elevation, so settlements sit on plausible grade.
##
## Far-field note (prototype limit, per the #197 gate addendum):
## every GENERATOR decision is integer-hash math — exact at any
## coordinate, positive or negative. World-space floats appear only
## when sampling heights/densities and when the streamer places
## vertices; chunk node positions themselves are engine float32, so
## far-field VISUAL jitter beyond roughly +-50k chunks is a known
## prototype limit — the generated DATA stays exact. Noted, not
## solved, by design.
static func height_at(seed: int, wx: float, wz: float) -> float:
	var raw := _raw_height(seed, wx, wz)
	var d := density_at_world(seed, wx, wz)
	var dens := float(d["density"])
	if dens <= 0.01:
		return raw
	var c: Vector2 = d["center"]
	var grade := _raw_height(seed, c.x, c.y)
	var f := clampf(dens * 1.7, 0.0, 0.88)
	return lerpf(raw, grade, f)


# ------------------------------------------------------------------
# Layer 4 + assembly: lots & buildings.
# ------------------------------------------------------------------

static func generate_chunk(cx: int, cz: int, seed: int = WORLD_SEED) -> RefCounted:
	var data := ChunkData.new()
	data.cx = cx
	data.cz = cz
	data.lots.resize(LOTS_PER_CHUNK * LOTS_PER_CHUNK)
	data.heights.resize((LOTS_PER_CHUNK + 1) * (LOTS_PER_CHUNK + 1))
	var ox := float(cx) * CHUNK_SIZE
	var oz := float(cz) * CHUNK_SIZE
	# Terrain corners (17x17 at lot corners).
	for iz in LOTS_PER_CHUNK + 1:
		for ix in LOTS_PER_CHUNK + 1:
			data.heights[iz * (LOTS_PER_CHUNK + 1) + ix] = height_at(
				seed, ox + float(ix) * LOT_SIZE, oz + float(iz) * LOT_SIZE)
	var segments := road_segments_near_chunk(seed, cx, cz)
	# Lot world coords feed every hash below: lot identity is its
	# WORLD lot coordinate, so a lot's fate never depends on which
	# chunk generation encountered it (chunks never share lots, but
	# the discipline keeps the rule uniform across layers).
	for lz in LOTS_PER_CHUNK:
		for lx in LOTS_PER_CHUNK:
			var wlx := cx * LOTS_PER_CHUNK + lx
			var wlz := cz * LOTS_PER_CHUNK + lz
			var center := Vector2(ox + (float(lx) + 0.5) * LOT_SIZE,
				oz + (float(lz) + 0.5) * LOT_SIZE)
			var dist_road := 1.0e9
			for seg in segments:
				dist_road = minf(dist_road, _dist_to_segment(center, seg[0], seg[1]))
			var idx := lz * LOTS_PER_CHUNK + lx
			if dist_road <= ROAD_HALF_WIDTH:
				data.lots[idx] = ChunkData.ROAD
				continue
			var dinfo := density_at_world(seed, center.x, center.y)
			var dens := float(dinfo["density"])
			if dens <= 0.02:
				data.lots[idx] = ChunkData.EMPTY
				continue
			# Buildings hug roads: the build threshold scales with
			# density squared and falls with road distance.
			var road_factor := 1.0
			if dist_road > 32.0:
				road_factor = 0.15
			elif dist_road > 16.0:
				road_factor = 0.45
			var roll := rand01(seed, wlx, wlz, SALT_LOT_ROLL)
			if roll < dens * dens * road_factor * 1.4:
				data.lots[idx] = ChunkData.BUILDING
				var cap := 12
				if str(dinfo["kind"]) == "village":
					cap = 2 ## villages stay low (brief: 1-2 floors)
				var span := lerpf(1.0, float(cap), pow(dens, 1.5))
				var froll := rand01(seed, wlx, wlz, SALT_FLOORS)
				var floors := clampi(1 + int(pow(froll, 0.6) * span), 1, cap)
				var style := int(rand01(seed, wlx, wlz, SALT_STYLE) * 6.0)
				data.buildings.append([lx, lz, floors, mini(style, 5)])
			else:
				var croll := rand01(seed, wlx, wlz, SALT_LOT_CLASS)
				if croll < 0.25:
					data.lots[idx] = ChunkData.GREEN
				elif croll < 0.35:
					data.lots[idx] = ChunkData.PLAZA
				else:
					data.lots[idx] = ChunkData.EMPTY
	return data
