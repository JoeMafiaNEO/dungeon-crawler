extends RefCounted
## BuildingGen (issues #199/#200): the PURE procedural building
## planner.
##
## plan_for(seed, world_lot_x, world_lot_z, floors, style,
## span_x, span_z, massing) returns a building as box pieces —
## perimeter walls per floor, floor plates, partitions with door
## gaps, and stair treads — every choice derived from the
## integer-hash discipline (no global RNG state), so a plan is a
## pure function of its inputs and identical on any machine, in
## any order.
##
## Size & shape (#200): the footprint is the merged lot span
## (span_x x span_z lots), and the massing shapes it per floor —
## 0 straight extrusion, 1 setbacks (the footprint only shrinks
## with height), 2 podium + tower. Interiors follow each floor's
## ACTUAL footprint; the stairwell rect derives from the smallest
## (top) footprint, so the stair column stays inside every floor
## while lower floors gain room around it.
##
## Enterable by construction: exactly ONE ground-floor exterior
## door — the door wall is BUILT as segments + a lintel around the
## gap, so nothing ever covers it. Every intermediate floor plate
## is decomposed around the stairwell rect (a real opening you can
## fly through); the roof plate stays whole; stacked straight
## flights climb the well. Floor pitch is 3.0 m (2.75 walls + a
## 0.25 plate inside the wall line), so a plan's silhouette height
## is exactly floors x 3.0 — the #197 exterior read is preserved.
##
## Pieces are Dictionaries: {k: "wall"/"plate"/"stair"/"part",
## c: Vector3 center (building-local, ground at y=0, span center
## at x/z 0), s: Vector3 size, shell: bool}. Shell pieces render
## under the exterior window material; interior pieces are plain.

const PITCH := 3.0 ## floor-to-floor height (== WorldGen.FLOOR_HEIGHT)
const WALL_H := 2.75
const PLATE_T := 0.25
const WALL_T := 0.3
const DOOR_W := 1.2
const DOOR_H := 2.2
const PART_T := 0.15
const PART_DOOR_W := 1.0
const PART_DOOR_H := 2.1
const STAIR_RUN := 3.4
const STAIR_W := 1.1
const STEPS_PER_FLIGHT := 10
const MIN_FOOT := 3.4 ## a floor's footprint never shrinks below this

const S_DOOR_WALL := 301
const S_DOOR_OFF := 302
const S_STAIR := 303
const S_W := 304
const S_D := 305
const S_PART := 310
const S_STEP_A := 320
const S_STEP_B := 321
const S_PODIUM := 322


static func _mix32(h: int) -> int:
	h &= 0xFFFFFFFF
	h ^= h >> 16
	h = (h * 0x7FEB352D) & 0xFFFFFFFF
	h ^= h >> 15
	h = (h * 0x846CA68B) & 0xFFFFFFFF
	h ^= h >> 16
	return h


static func _rand01(seed: int, x: int, z: int, salt: int) -> float:
	var h := seed & 0xFFFFFFFF
	h = _mix32(h ^ (x & 0xFFFFFFFF))
	h = _mix32(h ^ (z & 0xFFFFFFFF))
	h = _mix32(h ^ (salt & 0xFFFFFFFF))
	return float(h & 0xFFFFFF) / float(0x1000000)


static func _piece(k: String, c: Vector3, s: Vector3, shell: bool) -> Dictionary:
	return {"k": k, "c": c, "s": s, "shell": shell}


## Append a wall spanning axis-interval [a0, a1] on one exterior
## side of the (w x d) floor rect, at floor band [y0, y0 + WALL_H].
## side: 0:+Z 1:-Z 2:+X 3:-X.
static func _wall_side(pieces: Array, side: int, a0: float, a1: float,
		y0: float, w: float, d: float) -> void:
	if a1 - a0 < 0.05:
		return
	var mid := (a0 + a1) * 0.5
	var len := a1 - a0
	match side:
		0:
			pieces.append(_piece("wall", Vector3(mid, y0 + WALL_H * 0.5, d * 0.5 - WALL_T * 0.5),
				Vector3(len, WALL_H, WALL_T), true))
		1:
			pieces.append(_piece("wall", Vector3(mid, y0 + WALL_H * 0.5, -(d * 0.5 - WALL_T * 0.5)),
				Vector3(len, WALL_H, WALL_T), true))
		2:
			pieces.append(_piece("wall", Vector3(w * 0.5 - WALL_T * 0.5, y0 + WALL_H * 0.5, mid),
				Vector3(WALL_T, WALL_H, len), true))
		3:
			pieces.append(_piece("wall", Vector3(-(w * 0.5 - WALL_T * 0.5), y0 + WALL_H * 0.5, mid),
				Vector3(WALL_T, WALL_H, len), true))


## Decompose the plate rect (interior of the walls of a w x d
## floor) minus the hole rect (pass an empty-span rect for a whole
## plate) into boxes at plate band [py, py + PLATE_T]. Guillotine
## split, <= 4 pieces.
static func _plate(pieces: Array, w: float, d: float, py: float,
		hole: Rect2, shell: bool) -> void:
	var ix := w * 0.5 - WALL_T
	var iz := d * 0.5 - WALL_T
	var rects: Array = []
	if hole.size.x <= 0.0:
		rects.append(Rect2(-ix, -iz, ix * 2.0, iz * 2.0))
	else:
		if hole.position.x > -ix:
			rects.append(Rect2(-ix, -iz, hole.position.x + ix, iz * 2.0))
		if hole.end.x < ix:
			rects.append(Rect2(hole.end.x, -iz, ix - hole.end.x, iz * 2.0))
		if hole.position.y > -iz:
			rects.append(Rect2(hole.position.x, -iz, hole.size.x, hole.position.y + iz))
		if hole.end.y < iz:
			rects.append(Rect2(hole.position.x, hole.end.y, hole.size.x, iz - hole.end.y))
	for r in rects:
		var rr := r as Rect2
		if rr.size.x < 0.05 or rr.size.y < 0.05:
			continue
		pieces.append(_piece("plate",
			Vector3(rr.get_center().x, py + PLATE_T * 0.5, rr.get_center().y),
			Vector3(rr.size.x, PLATE_T, rr.size.y), shell))


static func plan_for(seed: int, wlx: int, wlz: int, floors: int, style: int,
		span_x: int = 1, span_z: int = 1, massing: int = 0) -> Dictionary:
	var bw := float(span_x) * 8.0 - 0.8 \
		- 0.8 * float(int(_rand01(seed, wlx, wlz, S_W) * 3.0) % 3)
	var bd := float(span_z) * 8.0 - 0.8 \
		- 0.8 * float(int(_rand01(seed, wlx, wlz, S_D) * 3.0) % 3)
	var door_wall := int(_rand01(seed, wlx, wlz, S_DOOR_WALL) * 4.0) % 4
	var door_len := bw if door_wall < 2 else bd
	var door_center := -door_len * 0.5 \
		+ (0.3 + 0.4 * _rand01(seed, wlx, wlz, S_DOOR_OFF)) * door_len
	# Massing shape parameters (hash-derived, floor-independent).
	var step_a := floors + 1
	var step_b := floors + 1
	if massing == 1 and floors >= 3:
		step_a = clampi(1 + int(_rand01(seed, wlx, wlz, S_STEP_A)
			* float(maxi(1, floors / 3))), 1, floors - 1)
		step_b = clampi(step_a + 1 + int(_rand01(seed, wlx, wlz, S_STEP_B)
			* float(maxi(1, floors / 3))), step_a + 1, floors)
	var podium_h := 0
	if massing == 2:
		podium_h = 1 + int(_rand01(seed, wlx, wlz, S_PODIUM) * 2.0) % 2
	var corner := int(_rand01(seed, wlx, wlz, S_STAIR) * 4.0) % 4
	var sx := 1.0 if corner == 0 or corner == 3 else -1.0
	var sz := 1.0 if corner < 2 else -1.0
	# The footprint of each floor, and the stairwell rect derived
	# from the SMALLEST (top) footprint (see the header).
	var top_size := _floor_size(floors - 1, floors, bw, bd, massing,
		step_a, step_b, podium_h)
	var zx1 := sx * (top_size.x * 0.5 - WALL_T)
	var zx0 := zx1 - sx * STAIR_RUN
	var zz1 := sz * (top_size.y * 0.5 - WALL_T)
	var zz0 := zz1 - sz * STAIR_W
	var hole := Rect2(Vector2(minf(zx0, zx1), minf(zz0, zz1)),
		Vector2(STAIR_RUN, STAIR_W))
	var pieces: Array = []
	# Ground plate (top at y = -0.05, sunk just under grade).
	_plate(pieces, bw, bd, -0.3, Rect2(), false)
	for f in floors:
		var y0 := float(f) * PITCH
		var fs := _floor_size(f, floors, bw, bd, massing, step_a, step_b, podium_h)
		var fw := fs.x
		var fd := fs.y
		# --- exterior walls (this floor's footprint) ---
		for side in 4:
			var slen := fw if side < 2 else fd
			if f == 0 and side == door_wall:
				_wall_side(pieces, side, -slen * 0.5, door_center - DOOR_W * 0.5, y0, fw, fd)
				_wall_side(pieces, side, door_center + DOOR_W * 0.5, slen * 0.5, y0, fw, fd)
				# Lintel over the door gap.
				var lc := Vector3.ZERO
				var ls := Vector3.ZERO
				match side:
					0:
						lc = Vector3(door_center, y0 + DOOR_H + (WALL_H - DOOR_H) * 0.5, fd * 0.5 - WALL_T * 0.5)
						ls = Vector3(DOOR_W, WALL_H - DOOR_H, WALL_T)
					1:
						lc = Vector3(door_center, y0 + DOOR_H + (WALL_H - DOOR_H) * 0.5, -(fd * 0.5 - WALL_T * 0.5))
						ls = Vector3(DOOR_W, WALL_H - DOOR_H, WALL_T)
					2:
						lc = Vector3(fw * 0.5 - WALL_T * 0.5, y0 + DOOR_H + (WALL_H - DOOR_H) * 0.5, door_center)
						ls = Vector3(WALL_T, WALL_H - DOOR_H, DOOR_W)
					3:
						lc = Vector3(-(fw * 0.5 - WALL_T * 0.5), y0 + DOOR_H + (WALL_H - DOOR_H) * 0.5, door_center)
						ls = Vector3(WALL_T, WALL_H - DOOR_H, DOOR_W)
				pieces.append(_piece("wall", lc, ls, true))
			else:
				_wall_side(pieces, side, -slen * 0.5, slen * 0.5, y0, fw, fd)
		# --- partitions (door-gapped, stairwell-truncated) ---
		var pcount := int(_rand01(seed, wlx, wlz, S_PART + f * 3) * 3.0) % 3
		for p in pcount:
			# The partition index folds into every salt: without
			# it, two partitions on one floor derived identical
			# orientation/position/gap — coplanar duplicates.
			var pbase := 400 + f * 8 + p * 4
			var along_x := _rand01(seed, wlx, wlz, pbase) < 0.5
			var span := (fw - 2.0 * WALL_T) if along_x else (fd - 2.0 * WALL_T)
			var cross := (fd - 2.0 * WALL_T) if along_x else (fw - 2.0 * WALL_T)
			var fixed := (randf_range_s(seed, wlx, wlz, pbase + 1, -0.3, 0.3)) * cross
			var gap_c := (0.3 + 0.4 * _rand01(seed, wlx, wlz, pbase + 2)) * span - span * 0.5
			# Wall spans along its axis: full span minus the door
			# gap, minus the stairwell when the line crosses it.
			var spans: Array = [[-span * 0.5, span * 0.5]]
			spans = _subtract_span(spans, gap_c - PART_DOOR_W * 0.5, gap_c + PART_DOOR_W * 0.5)
			var zone_cross0 := (zz0 if along_x else zx0)
			var zone_cross1 := (zz1 if along_x else zx1)
			var gap_in_zone := false
			if fixed > minf(zone_cross0, zone_cross1) - PART_T \
					and fixed < maxf(zone_cross0, zone_cross1) + PART_T:
				var zs0 := (zx0 if along_x else zz0)
				var zs1 := (zx1 if along_x else zz1)
				spans = _subtract_span(spans, minf(zs0, zs1), maxf(zs0, zs1))
				# If the door gap overlaps the well, the lintel
				# would float over the opening — skip it.
				gap_in_zone = gap_c + PART_DOOR_W * 0.5 > minf(zs0, zs1) \
					and gap_c - PART_DOOR_W * 0.5 < maxf(zs0, zs1)
			for sp in spans:
				var a0 := float(sp[0])
				var a1 := float(sp[1])
				if a1 - a0 < 0.05:
					continue
				var mid := (a0 + a1) * 0.5
				if along_x:
					pieces.append(_piece("part",
						Vector3(mid, y0 + WALL_H * 0.5, fixed),
						Vector3(a1 - a0, WALL_H, PART_T), false))
				else:
					pieces.append(_piece("part",
						Vector3(fixed, y0 + WALL_H * 0.5, mid),
						Vector3(PART_T, WALL_H, a1 - a0), false))
			# Partition lintel over its door gap — skipped when
			# the gap fell inside the stairwell span (the wall is
			# truncated there; a lintel would float over the well).
			if not gap_in_zone:
				var lintel_c := Vector3.ZERO
				var lintel_s := Vector3.ZERO
				if along_x:
					lintel_c = Vector3(gap_c, y0 + PART_DOOR_H + (WALL_H - PART_DOOR_H) * 0.5, fixed)
					lintel_s = Vector3(PART_DOOR_W, WALL_H - PART_DOOR_H, PART_T)
				else:
					lintel_c = Vector3(fixed, y0 + PART_DOOR_H + (WALL_H - PART_DOOR_H) * 0.5, gap_c)
					lintel_s = Vector3(PART_T, WALL_H - PART_DOOR_H, PART_DOOR_W)
				pieces.append(_piece("part", lintel_c, lintel_s, false))
		# --- plate above this floor (this floor's footprint) ---
		var py := y0 + WALL_H
		if f < floors - 1:
			_plate(pieces, fw, fd, py, hole, false)
			# --- flight f -> f+1, ascending toward the corner ---
			var zlo := minf(zx0, zx1)
			var tread := STAIR_RUN / float(STEPS_PER_FLIGHT)
			for i in STEPS_PER_FLIGHT:
				var tread_top := y0 + float(i + 1) * (PITCH / float(STEPS_PER_FLIGHT))
				var xc := zlo + (float(i) + 0.5) * tread if sx > 0.0 \
					else zlo + STAIR_RUN - (float(i) + 0.5) * tread
				pieces.append(_piece("stair",
					Vector3(xc, tread_top - 0.09, (zz0 + zz1) * 0.5),
					Vector3(tread, 0.18, STAIR_W), false))
		else:
			_plate(pieces, fw, fd, py, Rect2(), true)
	return {"pieces": pieces, "w": bw, "d": bd, "floors": floors,
		"door_wall": door_wall, "door_center": door_center,
		"hole": hole, "style": style, "span_x": span_x,
		"span_z": span_z, "massing": massing}


## The footprint of floor f under the building's massing. Every
## floor's rect is centered on the span center, and the size is
## NON-INCREASING in f (straight: constant; setbacks: two steps
## down; podium: full base, then a narrower tower).
static func _floor_size(f: int, floors: int, bw: float, bd: float,
		massing: int, step_a: int, step_b: int, podium_h: int) -> Vector2:
	if massing == 1 and floors >= 3:
		var shrink := 0.0
		if f >= step_b:
			shrink = 2.4
		elif f >= step_a:
			shrink = 1.2
		return Vector2(maxf(bw - shrink, MIN_FOOT), maxf(bd - shrink, MIN_FOOT))
	if massing == 2 and f >= podium_h:
		return Vector2(minf(maxf(bw * 0.62, MIN_FOOT), bw),
			minf(maxf(bd * 0.62, MIN_FOOT), bd))
	return Vector2(bw, bd)


static func _subtract_span(spans: Array, a: float, b: float) -> Array:
	var out: Array = []
	for sp in spans:
		var s0 := float(sp[0])
		var s1 := float(sp[1])
		if b <= s0 or a >= s1:
			out.append([s0, s1])
			continue
		if a > s0:
			out.append([s0, a])
		if b < s1:
			out.append([b, s1])
	return out


## Small deterministic range helper (same hash family).
static func randf_range_s(seed: int, x: int, z: int, salt: int, lo: float, hi: float) -> float:
	return lo + (hi - lo) * _rand01(seed, x, z, salt)


## The street door of a plan placed at `origin` (the span
## center at ground height): the gap's center on the ground
## floor's door wall, the wall's outward normal, and the
## DOORSTEP — the point just outside the gap where an arriving
## player stands (issue #204: the P5 interface's doorstep
## point; Act 2's respawn anchors resolve to doorsteps). The
## ground floor's footprint is always the plan's full w x d
## (massing steps apply from floor 1 up), so the plan's own
## dims place the gap. Pure: every peer derives the identical
## doorstep from the same plan + origin.
static func door_world(plan: Dictionary, origin: Vector3) -> Dictionary:
	var w := float(plan["w"])
	var d := float(plan["d"])
	var wall := int(plan["door_wall"])
	var dc := float(plan["door_center"])
	var gap := Vector3.ZERO
	var normal := Vector3.ZERO
	match wall:
		0:
			gap = Vector3(dc, 0.0, d * 0.5 - WALL_T * 0.5)
			normal = Vector3(0, 0, 1)
		1:
			gap = Vector3(dc, 0.0, -(d * 0.5 - WALL_T * 0.5))
			normal = Vector3(0, 0, -1)
		2:
			gap = Vector3(w * 0.5 - WALL_T * 0.5, 0.0, dc)
			normal = Vector3(1, 0, 0)
		_:
			gap = Vector3(-(w * 0.5 - WALL_T * 0.5), 0.0, dc)
			normal = Vector3(-1, 0, 0)
	var gap_world := origin + gap
	return {"gap_center": gap_world, "normal": normal,
		"doorstep": gap_world + normal * (WALL_T * 0.5 + 1.1),
		"wall": wall}


## Canonical serialization for the determinism pins.
static func serialize_plan(plan: Dictionary) -> String:
	var parts: Array = []
	parts.append("w=%.2f d=%.2f f=%d door=%d@%.2f hole=%.2f,%.2f span=%dx%d m=%d" % [
		float(plan["w"]), float(plan["d"]), int(plan["floors"]),
		int(plan["door_wall"]), float(plan["door_center"]),
		(plan["hole"] as Rect2).position.x, (plan["hole"] as Rect2).position.y,
		int(plan["span_x"]), int(plan["span_z"]), int(plan["massing"])])
	for p in plan["pieces"]:
		var c: Vector3 = p["c"]
		var s: Vector3 = p["s"]
		parts.append("%s%d:%.2f,%.2f,%.2f:%.2f,%.2f,%.2f" % [
			str(p["k"]), 1 if bool(p["shell"]) else 0,
			c.x, c.y, c.z, s.x, s.y, s.z])
	return "|".join(parts)
