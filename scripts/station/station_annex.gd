class_name StationAnnex
extends Node3D
## Phase 1 (issue #2): deterministic roofed station-hall shell attached to the
## dungeon arena's north wall via a short corridor. Empty shell only — floor,
## walls, roof, lamps, all with collision where it matters. Phase 2 instances
## the station content (train, departures board, vendor, heal pad) inside.
##
## Generation runs on the server as part of dungeon.gd; every peer rebuilds
## identically from the level seed, so the annex is multiplayer-safe.
##
## TODO (Phase 1 warlord): Warlord's Domain wants the annex at the map corner
## rather than the north-wall center. Parameterize the attach wall/corner when
## the warlord pass lands (Phase 2+) instead of hacking it here.

const HALL_W := 24.0
const HALL_D := 20.0
const HALL_H := 4.5
const WALL_T := 1.0
const CORRIDOR_W := 4.0
const CORRIDOR_L := 6.0
const DOOR_W := 4.0

var attach_x := 0.0
var arena_half := 24.0
## OmniLight3D lamps, exposed so Phase 2 can tint them per theme.
var lamps: Array = []


## Deterministic annex placement from the level seed.
## Scans discrete x positions (seeded order) for a doorway spot whose two
## northmost grid rows are clear of obstacles. Last resort: carves the
## least-blocked spot (grid cells -> FLOOR, obstacle props dropped) — still
## deterministic on every peer since it derives from seed + layout only.
static func plan(level_seed: int, layout: LevelLayout) -> Dictionary:
	var half := layout.arena_half_size()
	var max_off := half - HALL_W * 0.5 - 1.0
	var cands: Array = []
	var x: float = -floor(max_off / 4.0) * 4.0
	while x <= max_off + 0.01:
		cands.append(x)
		x += 4.0
	if cands.is_empty():
		cands.append(0.0)
	var start: int = abs(level_seed) % cands.size()
	var best := start
	var best_blocked := 1 << 30
	for i in cands.size():
		var idx := (start + i) % cands.size()
		var cx: float = cands[idx]
		var blocked := _doorway_blocked(layout, cx)
		if blocked == 0:
			return {"attach_x": cx, "cleared": false}
		if blocked < best_blocked:
			best_blocked = blocked
			best = idx
	var bx: float = cands[best]
	_clear_doorway(layout, bx)
	return {"attach_x": bx, "cleared": true}


## Arena north-wall segments with a doorway gap for the annex corridor.
## Returns [center, size] pairs matching _build_walls' format.
static func north_wall_segments(half: float, thick: float, wall_h: float, ax: float, door_w: float) -> Array:
	var gap_l := ax - door_w * 0.5
	var gap_r := ax + door_w * 0.5
	var full_l := -half - thick * 0.5
	var full_r := half + thick * 0.5
	return [
		[Vector3((full_l + gap_l) * 0.5, wall_h * 0.5, -half), Vector3(gap_l - full_l, wall_h, thick)],
		[Vector3((gap_r + full_r) * 0.5, wall_h * 0.5, -half), Vector3(full_r - gap_r, wall_h, thick)],
	]


static func build(parent: Node3D, annex_plan: Dictionary, layout: LevelLayout) -> StationAnnex:
	var a := StationAnnex.new()
	a.name = "StationAnnex"
	a.attach_x = float(annex_plan.get("attach_x", 0.0))
	a.arena_half = layout.arena_half_size()
	parent.add_child(a)
	a._build()
	return a


## Hall center in world space (for tests / Phase 2 content placement).
func hall_center() -> Vector3:
	return Vector3(attach_x, 0.0, -arena_half - CORRIDOR_L - HALL_D * 0.5)


static func _doorway_blocked(layout: LevelLayout, cx: float) -> int:
	var n := 0
	for cz in [0, 1]:
		for gx in layout.grid_size:
			if layout.grid[layout.idx(gx, cz)] != LevelLayout.OBSTACLE:
				continue
			var wp := layout.cell_to_world(gx, cz)
			if absf(wp.x - cx) <= 3.5:
				n += 1
	return n


static func _clear_doorway(layout: LevelLayout, cx: float) -> void:
	for cz in [0, 1]:
		for gx in layout.grid_size:
			var wp := layout.cell_to_world(gx, cz)
			if absf(wp.x - cx) > 3.5:
				continue
			layout.grid[layout.idx(gx, cz)] = LevelLayout.FLOOR
	var north_edge := -layout.arena_half_size() + 5.0
	layout.props = layout.props.filter(func(p: Dictionary) -> bool:
		var pos: Vector3 = p.get("pos", Vector3.ZERO)
		return not (bool(p.get("obstacle_visual", false)) and absf(pos.x - cx) <= 3.5 and pos.z <= north_edge)
	)


func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


## Solid box: collision + visual mesh. Collision layer 1, no mask (static world).
func _solid(size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	body.position = pos
	add_child(body)
	return body


func _visual(size: Vector3, pos: Vector3, mat: Material, node_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if node_name != "":
		mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


func _build() -> void:
	var h := arena_half
	var ax := attach_x
	var stone := _mat(Color(0.42, 0.40, 0.44))
	var wall_mat := _mat(Color(0.34, 0.32, 0.38))
	var dark := _mat(Color(0.12, 0.11, 0.13))
	var brass := _mat(Color(0.72, 0.55, 0.25))
	var lamp_glow := _mat(Color(1.0, 0.85, 0.55), Color(1.0, 0.75, 0.40), 3.0)

	# Floors (tops at y=0, matching the arena floor). Butt-jointed with no
	# overlaps: the arena floor always extends exactly 3m past the walls
	# (size = grid_size * cell_size + 6), so the corridor floor meets it at -h-3.
	_solid(Vector3(HALL_W + 2.0 * WALL_T, 1.0, HALL_D + 0.5),
		Vector3(ax, -0.5, -h - 13.75), stone).name = "HallFloor"
	_solid(Vector3(CORRIDOR_W + 1.0, 1.0, 3.5),
		Vector3(ax, -0.5, -h - 4.75), stone).name = "CorridorFloor"

	# Hall walls (south wall split for the corridor mouth).
	_solid(Vector3(WALL_T, HALL_H, HALL_D + 2.0 * WALL_T),
		Vector3(ax - HALL_W * 0.5 - WALL_T * 0.5, HALL_H * 0.5, -h - CORRIDOR_L - HALL_D * 0.5), wall_mat)
	_solid(Vector3(WALL_T, HALL_H, HALL_D + 2.0 * WALL_T),
		Vector3(ax + HALL_W * 0.5 + WALL_T * 0.5, HALL_H * 0.5, -h - CORRIDOR_L - HALL_D * 0.5), wall_mat)
	_solid(Vector3(HALL_W + 2.0 * WALL_T, HALL_H, WALL_T),
		Vector3(ax, HALL_H * 0.5, -h - CORRIDOR_L - HALL_D - WALL_T * 0.5), wall_mat)
	var sw_w := (HALL_W - CORRIDOR_W) * 0.5
	_solid(Vector3(sw_w, HALL_H, WALL_T),
		Vector3(ax - CORRIDOR_W * 0.5 - sw_w * 0.5, HALL_H * 0.5, -h - CORRIDOR_L - WALL_T * 0.5), wall_mat)
	_solid(Vector3(sw_w, HALL_H, WALL_T),
		Vector3(ax + CORRIDOR_W * 0.5 + sw_w * 0.5, HALL_H * 0.5, -h - CORRIDOR_L - WALL_T * 0.5), wall_mat)

	# Corridor side walls (run into the arena wall to seal the junction).
	_solid(Vector3(0.5, 3.5, CORRIDOR_L + 1.25),
		Vector3(ax - CORRIDOR_W * 0.5 - 0.25, 1.75, -h - CORRIDOR_L * 0.5 + 0.375), wall_mat)
	_solid(Vector3(0.5, 3.5, CORRIDOR_L + 1.25),
		Vector3(ax + CORRIDOR_W * 0.5 + 0.25, 1.75, -h - CORRIDOR_L * 0.5 + 0.375), wall_mat)

	# Roof: solid cover over hall + corridor (visual only; hides theme-sky mismatch).
	_visual(Vector3(HALL_W + 2.6, 0.3, HALL_D + 2.6),
		Vector3(ax, HALL_H + 0.15, -h - CORRIDOR_L - HALL_D * 0.5), dark, "HallRoof")
	_visual(Vector3(CORRIDOR_W + 1.6, 0.3, CORRIDOR_L + 1.5),
		Vector3(ax, 3.65, -h - CORRIDOR_L * 0.5 + 0.375), dark, "CorridorRoof")

	# Brass lintel marking the arena-side doorway.
	_visual(Vector3(DOOR_W + 1.2, 0.5, 0.8), Vector3(ax, 3.9, -h), brass, "DoorLintel")

	# Warm lamp posts (station recipe); Phase 2 tints these per theme.
	for lx in [ax - 8.0, ax + 8.0]:
		for lz in [-h - CORRIDOR_L - HALL_D * 0.5 - 4.0, -h - CORRIDOR_L - HALL_D * 0.5 + 4.0]:
			var pole := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.16, 4.2, 0.16)
			pm.material = dark
			pole.mesh = pm
			pole.position = Vector3(lx, 2.1, lz)
			add_child(pole)
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.22
			sm.height = 0.44
			sm.material = lamp_glow
			bulb.mesh = sm
			bulb.position = Vector3(lx, 4.3, lz)
			add_child(bulb)
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.80, 0.50)
			lamp.light_energy = 1.6
			lamp.omni_range = 12.0
			lamp.position = Vector3(lx, 4.0, lz)
			add_child(lamp)
			lamps.append(lamp)
