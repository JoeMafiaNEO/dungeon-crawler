class_name ScatterGen
extends RefCounted
## Issue #204 (P4): nature scatter — Jesse's six rulings as a
## PURE function of (WORLD_SEED, chunk). Every decision is a
## raw hash of WORLD coordinates (candidate cells, 32 m grove
## cells, lot identities) — never an RNG stream — so a point
## near a chunk border is decided identically from either side
## and borders are continuous by construction.
##
##   N1 FALLOFF — density comes from WorldGen.density_at_world:
##     groves and rocks thin out toward settlement cores (town
##     clearings) and thicken into wilderness forest.
##   N2 GROVES — a 32 m area roll decides groves; trees live
##     inside groves; rocks are looser (anywhere legal); grass
##     and mushrooms are fine-grained inside groves.
##   N3 MIX BY PLACE — near a settlement (density >= 0.35) the
##     grove trees are oak / detailed; far out they are cone
##     pines. Mushrooms are grove-only.
##   N4 CAPPED BUDGET — the CAP_* constants below are the
##     per-chunk budget, grass capped hardest. Overpopulation
##     trims deterministically (lowest deciding hashes win),
##     so the cap holds on the densest possible chunk, not
##     just on average. Budget statement (with the shells-only
##     building numbers): a chunk carries at most CAP_TOTAL
##     scatter instances beside its buildings.
##   N5 SLOPE AVOIDANCE — trees and rocks sample the height
##     field's slope and refuse steep ground; grass follows
##     the sampler anywhere.
##   N6 COLLISION FROM THE START — large trees and rocks are
##     collidable (the streamer gives them shapes on the
##     building-piece collision path); grass, mushrooms and
##     fences are visual-only.
##
## Nothing lands on a ROAD, BUILDING or PLAZA lot, and nothing
## lands inside a building footprint (own chunk's buildings
## plus the spill rects the caller passes for west/north
## neighbors, whose +x/+z spans can cross the border).

const WorldGen := preload("res://scripts/world/world_gen.gd")
const ChunkData := preload("res://scripts/world/chunk_data.gd")

const CELL := 2.0 ## candidate grid pitch (m), world-aligned
const GROVE_CELL := 32.0
const SALT_GROVE := 4099
const SALT_TREE := 4101
const SALT_TREE_TYPE := 4102
const SALT_ROCK := 4103
const SALT_ROCK_BIG := 4104
const SALT_GRASS := 4105
const SALT_MUSH := 4106
const SALT_FENCE := 4107
const SALT_SCALE := 4108
const SALT_ROT := 4109

const TREE_P := 0.11
const ROCK_P := 0.014
const GRASS_P := 0.30
const MUSH_P := 0.022
const FENCE_P := 0.010
const NEAR_DENSITY := 0.35 ## N3's near/far settlement split
const MAX_SLOPE := 0.55 ## rise over run, for trees + rocks

const CAP_TREE := 200
const CAP_ROCK := 60
const CAP_GRASS := 600
const CAP_MUSH := 80
const CAP_FENCE := 40
const CAP_TOTAL := 900

const TYPES: Array = ["oak", "detailed", "pine", "rock_big",
	"rock_small", "grass", "mushroom", "fence"]


## Terrain slope (rise over run) at a world point, from the
## height sampler's central differences.
static func slope_at(seed: int, wx: float, wz: float) -> float:
	var e := 1.0
	var sx := (WorldGen.height_at(seed, wx + e, wz)
		- WorldGen.height_at(seed, wx - e, wz)) / (2.0 * e)
	var sz := (WorldGen.height_at(seed, wx, wz + e)
		- WorldGen.height_at(seed, wx, wz - e)) / (2.0 * e)
	return Vector2(sx, sz).length()


## Is the 32 m grove cell containing (wx, wz) a grove? The
## roll leans on the density at the cell's center (N1): town
## cells rarely grove, wilderness cells usually do.
static func grove_at(seed: int, wx: float, wz: float) -> bool:
	var gx := int(floor(wx / GROVE_CELL))
	var gz := int(floor(wz / GROVE_CELL))
	var cc := Vector2((float(gx) + 0.5) * GROVE_CELL,
		(float(gz) + 0.5) * GROVE_CELL)
	var dens := float(WorldGen.density_at_world(seed, cc.x,
		cc.y)["density"])
	var p := lerpf(0.18, 0.60, clampf(1.0 - dens, 0.0, 1.0))
	return WorldGen.rand01(seed, gx, gz, SALT_GROVE) < p


static func _item(seed: int, hx: int, hz: int, wx: float,
		wz: float, h: float, sbase: float) -> Dictionary:
	return {"p": Vector3(wx, WorldGen.height_at(seed, wx, wz),
			wz),
		"s": sbase * (0.85 + 0.45 * WorldGen.rand01(seed, hx,
			hz, SALT_SCALE)),
		"r": WorldGen.rand01(seed, hx, hz, SALT_ROT) * TAU,
		"h": h}


## The chunk's scatter. `data` is the chunk's own ChunkData;
## `spill_rects` are world-space building footprints (already
## expanded) from neighboring chunks that can overlap this one.
static func scatter_for_chunk(seed: int, cx: int, cz: int,
		data: RefCounted, spill_rects: Array = []) -> Dictionary:
	var out := {}
	for t in TYPES:
		out[t] = []
	var rects: Array = []
	for b in data.buildings:
		var bx := float(cx * 16 + int(b[0])) * WorldGen.LOT_SIZE
		var bz := float(cz * 16 + int(b[1])) * WorldGen.LOT_SIZE
		rects.append(Rect2(bx - 0.6, bz - 0.6,
			float(int(b[4])) * WorldGen.LOT_SIZE + 1.2,
			float(int(b[5])) * WorldGen.LOT_SIZE + 1.2))
	for r in spill_rects:
		rects.append(r)
	var x0 := float(cx) * WorldGen.CHUNK_SIZE
	var z0 := float(cz) * WorldGen.CHUNK_SIZE
	var steps := int(WorldGen.CHUNK_SIZE / CELL)
	var dens_by_lot := {}
	var grove_by_cell := {}
	for iz in steps:
		for ix in steps:
			var wx := x0 + (float(ix) + 0.5) * CELL
			var wz := z0 + (float(iz) + 0.5) * CELL
			var llx := int(floor((wx - x0) / WorldGen.LOT_SIZE))
			var llz := int(floor((wz - z0) / WorldGen.LOT_SIZE))
			var cls: int = data.lot_class(llx, llz)
			if cls == ChunkData.ROAD or cls == ChunkData.BUILDING \
					or cls == ChunkData.PLAZA:
				continue
			var in_rect := false
			for r in rects:
				if (r as Rect2).has_point(Vector2(wx, wz)):
					in_rect = true
					break
			if in_rect:
				continue
			var lkey := "%d,%d" % [llx, llz]
			if not dens_by_lot.has(lkey):
				var lc := Vector2(x0 + (float(llx) + 0.5)
					* WorldGen.LOT_SIZE, z0 + (float(llz) + 0.5)
					* WorldGen.LOT_SIZE)
				dens_by_lot[lkey] = float(WorldGen.density_at_world(
					seed, lc.x, lc.y)["density"])
			var dens: float = dens_by_lot[lkey]
			var hx := int(floor(wx / CELL))
			var hz := int(floor(wz / CELL))
			var gkey := "%d,%d" % [int(floor(wx / GROVE_CELL)),
				int(floor(wz / GROVE_CELL))]
			if not grove_by_cell.has(gkey):
				grove_by_cell[gkey] = grove_at(seed, wx, wz)
			var grove: bool = grove_by_cell[gkey]
			# Grass: fine-grained in groves (sparser on open
			# GREEN lots); follows the ground anywhere (N5).
			var gh := WorldGen.rand01(seed, hx, hz, SALT_GRASS)
			if (grove and gh < GRASS_P) or (not grove
					and cls == ChunkData.GREEN
					and gh < GRASS_P * 0.6):
				out["grass"].append(_item(seed, hx, hz, wx, wz,
					gh, 1.0))
			if grove:
				var th := WorldGen.rand01(seed, hx, hz, SALT_TREE)
				if th < TREE_P and slope_at(seed, wx, wz) \
						<= MAX_SLOPE:
					var kind := "pine"
					if dens >= NEAR_DENSITY:
						kind = "oak" if WorldGen.rand01(seed,
							hx, hz, SALT_TREE_TYPE) < 0.6 \
							else "detailed"
					out[kind].append(_item(seed, hx, hz, wx,
						wz, th, 1.0))
				var mh := WorldGen.rand01(seed, hx, hz, SALT_MUSH)
				if mh < MUSH_P:
					out["mushroom"].append(_item(seed, hx, hz,
						wx, wz, mh, 1.0))
			var rh := WorldGen.rand01(seed, hx, hz, SALT_ROCK)
			if rh < ROCK_P * (1.0 - 0.6 * dens) \
					and slope_at(seed, wx, wz) <= MAX_SLOPE:
				var big := WorldGen.rand01(seed, hx, hz,
					SALT_ROCK_BIG) < 0.3
				out["rock_big" if big else "rock_small"].append(
					_item(seed, hx, hz, wx, wz, rh, 1.0))
			# Fences: settlement-edge dressing, visual only.
			if dens >= 0.45:
				var fh := WorldGen.rand01(seed, hx, hz,
					SALT_FENCE)
				if fh < FENCE_P:
					out["fence"].append(_item(seed, hx, hz,
						wx, wz, fh, 1.0))
	_apply_caps(out)
	return out


## N4: deterministic trim — the lowest deciding hashes win, so
## a capped chunk is still a pure function. Priority under the
## total cap: trees, rocks, mushrooms, fences, then grass
## (grass is capped hardest, so it yields first).
static func _apply_caps(out: Dictionary) -> void:
	_cap_list(out["oak"], CAP_TREE)
	_cap_list(out["detailed"], CAP_TREE)
	_cap_list(out["pine"], CAP_TREE)
	var trees: int = out["oak"].size() + out["detailed"].size() \
		+ out["pine"].size()
	if trees > CAP_TREE:
		# Trim the merged tree set proportionally by hash: keep
		# the CAP_TREE lowest hashes across the three kinds.
		var all: Array = []
		for k in ["oak", "detailed", "pine"]:
			for it in out[k]:
				all.append([float(it["h"]), k, it])
		all.sort_custom(func(a: Array, b: Array) -> bool:
			return float(a[0]) < float(b[0]))
		for k in ["oak", "detailed", "pine"]:
			out[k] = []
		for i in mini(CAP_TREE, all.size()):
			out[str(all[i][1])].append(all[i][2])
	_cap_list(out["rock_big"], CAP_ROCK)
	_cap_list(out["rock_small"], CAP_ROCK)
	_cap_list(out["mushroom"], CAP_MUSH)
	_cap_list(out["fence"], CAP_FENCE)
	_cap_list(out["grass"], CAP_GRASS)
	var total := 0
	for t in TYPES:
		total += (out[t] as Array).size()
	if total > CAP_TOTAL:
		var excess := total - CAP_TOTAL
		for k in ["grass", "mushroom", "fence", "rock_small",
				"rock_big"]:
			if excess <= 0:
				break
			var arr: Array = out[k]
			var cut := mini(excess, arr.size())
			# Lists are hash-trimmed already; cutting the tail
			# removes the highest hashes first.
			arr.resize(arr.size() - cut)
			excess -= cut


static func _cap_list(arr: Array, cap: int) -> void:
	if arr.size() <= cap:
		return
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["h"]) < float(b["h"]))
	arr.resize(cap)


static func total_count(scatter: Dictionary) -> int:
	var n := 0
	for t in TYPES:
		n += (scatter[t] as Array).size()
	return n


## Canonical serialization for the determinism pins.
static func serialize(scatter: Dictionary) -> String:
	var parts: Array = []
	for t in TYPES:
		parts.append("%s:%d" % [t, (scatter[t] as Array).size()])
		for it in scatter[t]:
			var p: Vector3 = it["p"]
			parts.append("%.1f,%.1f,%.2f" % [p.x, p.z,
				float(it["s"])])
	return "|".join(parts)
