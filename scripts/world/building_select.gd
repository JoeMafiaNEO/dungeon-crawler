class_name BuildingSelect
extends RefCounted
## Issue #204 (P4): the deterministic playable-building
## selection roll (P5's F1 cheat, gate-ruled 2026-10-25). A
## building is PLAYABLE — it ships a street door, a doorstep,
## and (in P5) a transfer into floor levels — or it is EMPTY:
## a solid shell with no door gap and no door, honest dressing.
##
## The roll is a pure function of (seed, world lot): a dedicated
## hash stream (salt 4001 on WorldGen's rand01 family — no
## existing stream is disturbed), with the probability scaled
## by settlement density per Jesse's F1: about 0.2 at a dense
## core (many buildings, a fifth of them playable is plenty) to
## about 0.5 at the fringe (few buildings, half of them live).
##
## VILLAGE GUARANTEE (hard rule): a village never rolls zero
## playable. It is structural, not statistical: each village's
## ANCHOR building — the building anchor lot nearest the
## village center, a pure function of the seed — is always
## playable. The scan that finds it is bounded (the village's
## own disc, at most 64x64 lots) and cached per settlement for
## the process; the answer is identical from any caller.

const WorldGen := preload("res://scripts/world/world_gen.gd")

const SALT_SELECT := 4001
const P_CORE := 0.2
const P_FRINGE := 0.5

static var _anchor_cache := {}


## The F1 probability curve: fringe 0.5 -> core 0.2 by density.
static func probability(density: float) -> float:
	return lerpf(P_FRINGE, P_CORE, clampf(density, 0.0, 1.0))


## Is the building ANCHORED at world lot (wlx, wlz) playable?
## Lots without a building anchor are never playable.
static func is_playable(seed: int, wlx: int, wlz: int) -> bool:
	var b := WorldGen.building_at(seed, wlx, wlz)
	if b.is_empty():
		return false
	var center := Vector2((float(wlx) + 0.5) * WorldGen.LOT_SIZE,
		(float(wlz) + 0.5) * WorldGen.LOT_SIZE)
	var dinfo := WorldGen.density_at_world(seed, center.x, center.y)
	if str(dinfo["kind"]) == "village":
		var s := _village_for(seed, wlx, wlz, dinfo)
		if not s.is_empty():
			var anchor := village_anchor_lot(seed, s)
			if anchor.x == wlx and anchor.y == wlz:
				return true
	return WorldGen.rand01(seed, wlx, wlz, SALT_SELECT) \
		< probability(float(dinfo["density"]))


## The village settlement governing a lot: the density field's
## dominant settlement when it is a village, else the nearest
## village in the surrounding cells.
static func _village_for(seed: int, wlx: int, wlz: int,
		dinfo: Dictionary) -> Dictionary:
	var lot_c := Vector2((float(wlx) + 0.5) * WorldGen.LOT_SIZE,
		(float(wlz) + 0.5) * WorldGen.LOT_SIZE)
	var best: Dictionary = {}
	var best_d := 1.0e18
	for s in WorldGen.settlements_near(seed, wlx >> 4, wlz >> 4, 1):
		if str(s["kind"]) != "village":
			continue
		if (s["center"] as Vector2) == (dinfo["center"] as Vector2):
			return s
		var dd := (s["center"] as Vector2).distance_squared_to(lot_c)
		if dd < best_d:
			best_d = dd
			best = s
	return best


## A village's guaranteed-playable anchor lot: the building
## anchor nearest the village center inside the village's disc
## (ties break to the lowest lot coords, so the answer is a
## pure function). The empty sentinel means the village has no
## buildings at all and the guarantee is vacuous.
static func village_anchor_lot(seed: int, s: Dictionary) -> Vector2i:
	var key := "%d,%d" % [int(s["gx"]), int(s["gz"])]
	if _anchor_cache.has(key):
		return _anchor_cache[key]
	var c: Vector2 = s["center"]
	var r := float(s["radius_chunks"]) * WorldGen.CHUNK_SIZE
	var lx0 := int(floor((c.x - r) / WorldGen.LOT_SIZE))
	var lx1 := int(floor((c.x + r) / WorldGen.LOT_SIZE))
	var lz0 := int(floor((c.y - r) / WorldGen.LOT_SIZE))
	var lz1 := int(floor((c.y + r) / WorldGen.LOT_SIZE))
	var seg_cache := {}
	var best := Vector2i(2147483647, 2147483647)
	var best_d := 1.0e18
	for wlz in range(lz0, lz1 + 1):
		for wlx in range(lx0, lx1 + 1):
			var lc := Vector2((float(wlx) + 0.5) * WorldGen.LOT_SIZE,
				(float(wlz) + 0.5) * WorldGen.LOT_SIZE)
			if lc.distance_to(c) > r:
				continue
			if WorldGen.building_at(seed, wlx, wlz, {},
					seg_cache).is_empty():
				continue
			var dd := lc.distance_squared_to(c)
			if dd < best_d - 0.001 or (absf(dd - best_d) <= 0.001
					and (wlx < best.x
						or (wlx == best.x and wlz < best.y))):
				best_d = dd
				best = Vector2i(wlx, wlz)
	_anchor_cache[key] = best
	return best
