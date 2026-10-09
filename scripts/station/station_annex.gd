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

## Boarding lobby (issue #93 Phase 1): waiting room dressed as a train car
## interior, built as part of the annex build. All LOBBY_* coords are
## hall-local (the Station node sits at hall_center(), so they match
## station.gd's content coords).
##
## Placement note: the spec anchors the lobby at the old BoardingZone
## (-1, -2.0) "extending north behind the train's footprint", but the train
## prop occupies z in [-5.7, -3.3] directly north of that point, so a room
## extending north would swallow the engine. The room instead sits just
## SOUTH of the train with its doorway on the north wall at exactly the old
## BoardingZone spot (-1, -2.0) — the Phase 3 flow ("boarding zone location
## becomes the lobby doorway") is preserved.
const LOBBY_CX := -1.0
const LOBBY_CZ := 0.5
const LOBBY_W := 8.0
const LOBBY_D := 5.0
const LOBBY_H := 3.2
const LOBBY_WALL_T := 0.5
const LOBBY_DOOR_W := 2.4
const LOBBY_DOOR_X := -1.0
const LOBBY_DOOR_H := 2.6
## Sliding door panels (issue #93 Phase 2): tween duration per peer.
const LOBBY_DOOR_TWEEN_S := 1.5
const LOBBY_PANEL_W := 1.2
const LOBBY_PANEL_T := 0.12

## Lobby door state (issue #93 Phase 2): server-authoritative, RPC-synced.
## Closed doors block the doorway via LobbyDoorBlocker; open doors free it.
var doors_open := false
var _door_panels: Array = []
var _door_blocker: StaticBody3D = null
var _door_tween: Tween = null
## Arrival settle countdown; -1 = inactive. Doors start closed on build and
## the server opens them 1s after the annex appears.
var _settle_left := -1.0


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


## Hall-local (station frame) -> annex-node-local (dungeon frame).
func _hl(lx: float, y: float, lz: float) -> Vector3:
	var hc := hall_center()
	return Vector3(hc.x + lx, y, hc.z + lz)


## Lobby footprint in hall-local coords, walls included (for tests).
func lobby_bounds() -> AABB:
	var hw := LOBBY_W * 0.5 + LOBBY_WALL_T
	var hd := LOBBY_D * 0.5 + LOBBY_WALL_T
	return AABB(Vector3(LOBBY_CX - hw, 0.0, LOBBY_CZ - hd), Vector3(hw * 2.0, LOBBY_H, hd * 2.0))


## Interior arrival spawn spots, hall-local (issue #93 Phase 3 wires these
## into the arrival hop). Kept clear of benches/straps by construction.
func lobby_spawn_spots() -> Array:
	return [
		Vector3(LOBBY_CX - 2.0, 0.0, LOBBY_CZ),
		Vector3(LOBBY_CX, 0.0, LOBBY_CZ),
		Vector3(LOBBY_CX + 2.0, 0.0, LOBBY_CZ),
		Vector3(LOBBY_CX, 0.0, LOBBY_CZ + 1.5),
	]


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

	_build_lobby()


## Boarding lobby (issue #93 Phase 1): waiting room dressed as a train car
## interior. All coords hall-local, converted with _hl(). No behavior —
## door panels, depart lever, and flow arrive in Phases 2-3.
func _build_lobby() -> void:
	var cx := LOBBY_CX
	var cz := LOBBY_CZ
	var hw := LOBBY_W * 0.5
	var hd := LOBBY_D * 0.5
	var wt := LOBBY_WALL_T
	var car_wall := _mat(Color(0.48, 0.36, 0.24))   # warm wood paneling
	var car_dark := _mat(Color(0.30, 0.21, 0.13))    # dark wood trim
	var brass := _mat(Color(0.72, 0.55, 0.25))
	var lamp_glow := _mat(Color(1.0, 0.85, 0.55), Color(1.0, 0.75, 0.40), 3.0)
	var win_glow := _mat(Color(1.0, 0.80, 0.45), Color(1.0, 0.68, 0.30), 2.0)

	# Floor: top at y=0.01 to avoid z-fighting with the hall floor.
	_solid(Vector3(LOBBY_W + 2.0 * wt, 1.0, LOBBY_D + 2.0 * wt),
		_hl(cx, -0.49, cz), car_dark).name = "LobbyFloor"

	# Walls (0.5 thick, outer faces flush with the interior boundary).
	# North wall split for the doorway (LOBBY_DOOR_W wide at LOBBY_DOOR_X).
	var door_l := LOBBY_DOOR_X - LOBBY_DOOR_W * 0.5
	var door_r := LOBBY_DOOR_X + LOBBY_DOOR_W * 0.5
	var nz := cz - hd - wt * 0.5
	_solid(Vector3(door_l - (cx - hw - wt), LOBBY_H, wt),
		_hl((cx - hw - wt + door_l) * 0.5, LOBBY_H * 0.5, nz), car_wall).name = "LobbyWallN_A"
	_solid(Vector3((cx + hw + wt) - door_r, LOBBY_H, wt),
		_hl((door_r + cx + hw + wt) * 0.5, LOBBY_H * 0.5, nz), car_wall).name = "LobbyWallN_B"
	# Lintel above the doorway (opening is LOBBY_DOOR_H tall; panels in Phase 2).
	_solid(Vector3(LOBBY_DOOR_W, LOBBY_H - LOBBY_DOOR_H, wt),
		_hl(LOBBY_DOOR_X, LOBBY_DOOR_H + (LOBBY_H - LOBBY_DOOR_H) * 0.5, nz), car_wall).name = "LobbyLintel"
	# South / west / east walls.
	_solid(Vector3(LOBBY_W + 2.0 * wt, LOBBY_H, wt),
		_hl(cx, LOBBY_H * 0.5, cz + hd + wt * 0.5), car_wall).name = "LobbyWallS"
	_solid(Vector3(wt, LOBBY_H, LOBBY_D),
		_hl(cx - hw - wt * 0.5, LOBBY_H * 0.5, cz), car_wall).name = "LobbyWallW"
	_solid(Vector3(wt, LOBBY_H, LOBBY_D),
		_hl(cx + hw + wt * 0.5, LOBBY_H * 0.5, cz), car_wall).name = "LobbyWallE"

	# Roof (visual only).
	_visual(Vector3(LOBBY_W + 2.0 * wt + 0.6, 0.3, LOBBY_D + 2.0 * wt + 0.6),
		_hl(cx, LOBBY_H + 0.15, cz), _mat(Color(0.12, 0.11, 0.13)), "LobbyRoof")

	# Bench seats along the west/east walls (solid) + backrests.
	for bx in [cx - hw + 0.5, cx + hw - 0.5]:
		for bz in [cz - 1.25, cz + 1.25]:
			_solid(Vector3(0.6, 0.45, 2.2), _hl(bx, 0.225, bz), car_wall).name = "LobbyBench"
			var back_x: float = bx - 0.375 if bx < cx else bx + 0.375
			_solid(Vector3(0.15, 1.0, 2.2), _hl(back_x, 0.95, bz), car_dark).name = "LobbyBenchBack"

	# Luggage racks above the benches (visual) + a couple of bags.
	# NOTE: names are assigned AFTER add_child (not via _visual's node_name
	# param): pre-add_child duplicate names get replaced with @Class@n and
	# lose the Lobby* prefix, while post-add_child assignment auto-numbers
	# them (LobbyRack2, ...) as the benches above already rely on.
	for bx in [cx - hw + 0.5, cx + hw - 0.5]:
		for bz in [cz - 1.25, cz + 1.25]:
			_visual(Vector3(0.5, 0.08, 2.2), _hl(bx, 2.3, bz), car_dark).name = "LobbyRack"
	for lx2 in [cx - hw + 0.5, cx + hw - 0.5]:
		_visual(Vector3(0.4, 0.3, 0.6), _hl(lx2, 2.49, cz - 1.6), brass).name = "LobbyBag"
		_visual(Vector3(0.4, 0.28, 0.55), _hl(lx2, 2.48, cz + 1.0), car_dark).name = "LobbyBag"

	# Hanging straps from the ceiling (visual).
	var strap_mat := _mat(Color(0.25, 0.16, 0.10))
	for sx in [cx - 2.0, cx, cx + 2.0]:
		for sz in [cz - 1.0, cz + 1.0]:
			_visual(Vector3(0.05, 0.5, 0.05), _hl(sx, 2.95, sz), strap_mat).name = "LobbyStrap"
			_visual(Vector3(0.08, 0.25, 0.18), _hl(sx, 2.58, sz), strap_mat).name = "LobbyStrapHandle"

	# Warm ceiling lamps (appended to lamps so station dressing can tint them).
	for lz2 in [cz - 1.25, cz + 1.25]:
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.30
		sm.material = lamp_glow
		bulb.mesh = sm
		bulb.position = _hl(cx, 3.0, lz2)
		add_child(bulb)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.82, 0.55)
		lamp.light_energy = 1.4
		lamp.omni_range = 8.0
		lamp.position = _hl(cx, 2.85, lz2)
		add_child(lamp)
		lamps.append(lamp)

	# Windows: warm glowing panes on the north segments + south wall.
	for wx in [(cx - hw - wt + door_l) * 0.5, (door_r + cx + hw + wt) * 0.5]:
		_visual(Vector3(1.8, 1.1, 0.12), _hl(wx, 1.8, nz), car_dark).name = "LobbyWinFrame"
		_visual(Vector3(1.5, 0.8, 0.14), _hl(wx, 1.8, nz), win_glow).name = "LobbyWindow"
	for wx in [cx - 2.0, cx + 2.0]:
		_visual(Vector3(1.8, 1.1, 0.12), _hl(wx, 1.8, cz + hd + wt * 0.5), car_dark).name = "LobbyWinFrame"
		_visual(Vector3(1.5, 0.8, 0.14), _hl(wx, 1.8, cz + hd + wt * 0.5), win_glow).name = "LobbyWindow"

	_build_lobby_doors(car_dark, brass)
	# Doors start closed; the server opens them after the 1s arrival settle.
	_settle_left = 1.0


## Sliding door panels on the lobby doorway (issue #93 Phase 2): two wood
## panels with brass leading edges that slide apart into the wall. Built
## closed; state changes go through set_lobby_doors (server) ->
## _rpc_lobby_doors (all peers, tween locally).
func _build_lobby_doors(panel_mat: Material, brass: Material) -> void:
	var cx := LOBBY_CX
	var cz := LOBBY_CZ
	var hd := LOBBY_D * 0.5
	var wt := LOBBY_WALL_T
	var nz := cz - hd - wt * 0.5
	# Panels ride just inside the lobby, sliding in front of the interior
	# face of the north wall segments.
	var pz := nz + wt * 0.5 + LOBBY_PANEL_T * 0.5 + 0.1
	for side in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(LOBBY_PANEL_W, LOBBY_DOOR_H, LOBBY_PANEL_T)
		pm.material = panel_mat
		panel.mesh = pm
		var closed_x: float = LOBBY_DOOR_X + side * LOBBY_PANEL_W * 0.5
		panel.position = _hl(closed_x, LOBBY_DOOR_H * 0.5, pz)
		panel.set_meta("closed_x", closed_x)
		panel.set_meta("open_x", LOBBY_DOOR_X + side * (LOBBY_PANEL_W * 0.5 + 1.35))
		# Brass leading-edge strip rides with the panel.
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.08, LOBBY_DOOR_H - 0.2, LOBBY_PANEL_T + 0.04)
		sm.material = brass
		strip.mesh = sm
		strip.position = Vector3(-side * (LOBBY_PANEL_W * 0.5 - 0.04), 0, 0)
		panel.add_child(strip)
		add_child(panel)
		# NOTE (Phase 1 naming gotcha): .name AFTER add_child.
		panel.name = "LobbyDoorPanel"
		_door_panels.append(panel)
	_door_blocker_build()


## Invisible collision filling the doorway while the doors are closed.
func _door_blocker_build() -> void:
	if _door_blocker != null:
		if is_instance_valid(_door_blocker) and not _door_blocker.is_queued_for_deletion():
			return
		_door_blocker = null
	var cz := LOBBY_CZ
	var hd := LOBBY_D * 0.5
	var wt := LOBBY_WALL_T
	var nz := cz - hd - wt * 0.5
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(LOBBY_DOOR_W, LOBBY_DOOR_H, wt)
	cs.shape = shape
	body.add_child(cs)
	body.position = _hl(LOBBY_DOOR_X, LOBBY_DOOR_H * 0.5, nz)
	add_child(body)
	body.name = "LobbyDoorBlocker"
	_door_blocker = body


## Server entry: decide the lobby door state, broadcast to all peers.
func set_lobby_doors(open: bool) -> void:
	if not multiplayer.is_server():
		return
	rpc("_rpc_lobby_doors", open)


@rpc("any_peer", "call_local")
func _rpc_lobby_doors(open: bool) -> void:
	_apply_lobby_doors(open)


## Local apply: state + SFX + tween (snap when not in the tree, so tests can
## drive the state machine) + collision toggle. Idempotent.
func _apply_lobby_doors(open: bool) -> void:
	if doors_open == open:
		return
	doors_open = open
	AudioManager.sfx("train_door_open" if open else "train_door_close")
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()
	_door_tween = null
	for d in _door_panels:
		var tx: float = float(d.get_meta("open_x")) if open else float(d.get_meta("closed_x"))
		if is_inside_tree():
			if _door_tween == null:
				_door_tween = create_tween().set_parallel()
			_door_tween.tween_property(d, "position:x", tx, LOBBY_DOOR_TWEEN_S).set_trans(Tween.TRANS_SINE)
		else:
			d.position.x = tx
	if open:
		if _door_blocker != null and is_instance_valid(_door_blocker):
			# Out of the tree immediately (no one-frame collision window,
			# no name clash on a same-frame rebuild); actual free is deferred.
			_door_blocker.get_parent().remove_child(_door_blocker)
			_door_blocker.queue_free()
		_door_blocker = null
	else:
		_door_blocker_build()


func _process(delta: float) -> void:
	# Arrival settle: doors start closed on build; the server opens them 1s
	# after the annex appears.
	if _settle_left < 0.0:
		return
	if not multiplayer.is_server():
		return
	_settle_left -= delta
	if _settle_left <= 0.0:
		_settle_left = -1.0
		set_lobby_doors(true)
