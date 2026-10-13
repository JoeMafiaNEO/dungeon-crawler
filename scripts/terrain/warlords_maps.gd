extends Node3D
## Issue #103: WARLORDS (RTS) map variants on the elevated-zones
## terrain system. TEST SCENE ONLY — no production code is modified.
##
## Four symmetric-ish RTS layouts built from the same ZonesTerrain
## zone/ramp vocabulary as zones_test.gd (flat tiers, steep terrace
## edges physics bodies cannot climb, carved ramps as the only way
## up, roughness texture on the flats — ellipse zones via "radius_z"
## for bands/terraces):
##
##   twin_crowns     two lowland bases (W/E), each with a +3m
##                   expansion plateau, one contested +6m peak in the
##                   centre with a ramp from each side.
##   fortress_mesa   one big central mesa (+3m ring step, +6m top)
##                   with a SINGLE south ramp; bases SW + NE.
##   terraced_valley N-S valley with a pond chain down the middle,
##                   +3m terraced banks both sides, +6m high ground
##                   across the north end; bases at the valley mouth.
##   the_staircase   W->E progression bands: lowland (both bases),
##                   +3m band, +6m band, +9m peak strip; one ramp
##                   per faction half at every step.
##   ring12          GENERATED layout (see _gen_ring12): 12 starts
##                   on a ring (rotational symmetry = fairness by
##                   construction), each with a +3m expansion
##                   plateau + ramp behind it, a contested +6m peak
##                   between each pair of neighbours (ramp from each
##                   side), and a fortress-style +6m mesa at the
##                   centre (ramps facing starts 0/3/6/9). 220x220m
##                   terrain; playable ring inside the ±100 unit
##                   movement clamp (see _gen_ring12).
##
## Per-map proofs (probe mode, [WMAPS] lines):
##   * both factions' bases (town hall + house + barracks each) via
##     the production-mirror spawn + min-basing; footprint ranges
##     must stay far under the 1.2m cliff-test cap, and dry.
##   * top-tier flatness (stddev / max dev vs tier height).
##   * every ramp's centreline grade (design cap ~50%).
##   * walker spot-check: driven at a NON-ramp edge of the top tier,
##     it stalls (never reaches the tier).
##   * connectivity: a 20-unit squad per faction ordered from its
##     base to the top tier via ramp waypoints on the real
##     order_move_squad path — all arrive, 0 stuck / wet.
##
## Run modes:
##   probe: headless measurements for one map
##     godot --headless --path . res://scenes/terrain/warlords_maps.tscn \
##       -- --mode=probe --map=twin_crowns
##   shots: Xvfb screenshots (INSPECT the PNGs)
##     xvfb-run godot --path . res://scenes/terrain/warlords_maps.tscn \
##       --resolution 1920x1080 -- --mode=shots --map=fortress_mesa \
##       --shot-dir=/tmp/shots
##   perf: 12-faction perf probe on ring12 (escalating unit totals,
##     idle + all-march-to-centre windows per step)
##     godot --headless --path . res://scenes/terrain/warlords_maps.tscn \
##       -- --mode=perf --map=ring12
##   (default): interactive view of the --map layout, squads march.

const CIVS := {0: "iron_vanguard", 1: "shadow_covenant"}
const SPACING := 1.4
const FOOTPRINTS := {
	"town_hall": Vector2(3.4, 3.4),
	"house": Vector2(2.2, 2.0),
	"barracks": Vector2(4.6, 2.4),
	"tower": Vector2(2.4, 2.4),
}
const PAD := 0.2

# Layout schema (all positions Vector3 with y = 0, terrain supplies y):
#   seed, pond_radius
#   zones / ramps: ZonesTerrain dicts (see zones_terrain.gd)
#   ponds: Array[Vector3] pond centres
#   bases: {faction: {"town_hall": V3, "house": V3, "barracks": V3}}
#   prize: V3 — prop cluster spot on the top tier
#   squads: {faction: {"spawn": V3, "legs": Array[V3]}} — last leg
#     target is the faction's gather point on the top tier. Gathers
#     are kept >20m apart: RTS units auto-aggro enemies within 8m,
#     and the proof measures connectivity, not combat.
#   edge_probe: {"spawn": V3, "target": V3, "min_h": float,
#     "max_h": float} — walker must end with height inside the band
#   top_stats: {"center": Vector2, "radius": float, "tier": float}
#   cams: overview pos/tgt absolute; low pos/tgt are (x, height
#     above ground at that xz, z)
#   trees / rocks: Array[Vector2] dressing spots
const LAYOUTS := {
	"twin_crowns": {
		"seed": 1101, "pond_radius": 6.0,
		"zones": [
			{"center": Vector2(0, -2), "radius": 16.0, "height": 6.0,
				"phase1": 0.0, "phase2": 0.0},
			{"center": Vector2(-40, -22), "radius": 13.0, "height": 3.0,
				"phase1": -5.108, "phase2": -8.513},
			{"center": Vector2(40, -22), "radius": 13.0, "height": 3.0,
				"phase1": -4.315, "phase2": -7.192},
		],
		"ramps": [
			{"base": Vector2(-25, -2), "dir": Vector2(1, 0),
				"length": 18.0, "width": 6.0, "h0": 0.0, "h1": 6.0},
			{"base": Vector2(25, -2), "dir": Vector2(-1, 0),
				"length": 18.0, "width": 6.0, "h0": 0.0, "h1": 6.0},
			{"base": Vector2(-42.4, -3.7), "dir": Vector2(0.1322, -0.9912),
				"length": 11.0, "width": 5.0, "h0": 0.0, "h1": 3.0},
			{"base": Vector2(42.4, -3.7), "dir": Vector2(-0.1322, -0.9912),
				"length": 11.0, "width": 5.0, "h0": 0.0, "h1": 3.0},
		],
		"ponds": [Vector3(-6, 0, 36), Vector3(6, 0, -40)],
		"bases": {
			0: {"town_hall": Vector3(-44, 0, 8), "house": Vector3(-37, 0, 3),
				"barracks": Vector3(-46, 0, 16)},
			1: {"town_hall": Vector3(44, 0, 8), "house": Vector3(37, 0, 3),
				"barracks": Vector3(46, 0, 16)},
		},
		"prize": Vector3(7, 0, -10),
		"squads": {
			0: {"spawn": Vector3(-40, 0, 10),
				"legs": [Vector3(-28, 0, -2), Vector3(-8, 0, -2)]},
			1: {"spawn": Vector3(40, 0, 10),
				"legs": [Vector3(28, 0, -2), Vector3(8, 0, -2)]},
		},
		"edge_probe": {"spawn": Vector3(0, 0, -32),
			"target": Vector3(0, 0, -4), "min_h": -0.5, "max_h": 1.5},
		"top_stats": {"center": Vector2(0, -2), "radius": 9.0, "tier": 6.0},
		"cams": {
			"overview_pos": Vector3(54, 50, 60), "overview_tgt": Vector3(0, 0, -2),
			"low_pos": Vector3(-50, 2.4, 22), "low_tgt": Vector3(0, 4.5, -4),
		},
		"trees": [Vector2(-52, -8), Vector2(-30, 26), Vector2(30, 26),
			Vector2(52, -8), Vector2(-14, -34), Vector2(14, -34),
			Vector2(-20, 40), Vector2(20, 40), Vector2(-34, -34),
			Vector2(34, -34)],
		"rocks": [Vector2(-18, 14), Vector2(18, 14), Vector2(-8, -22),
			Vector2(52, 24), Vector2(-52, 24)],
	},
	"fortress_mesa": {
		"seed": 2202, "pond_radius": 5.0,
		"zones": [
			{"center": Vector2(0, 0), "radius": 30.0, "height": 3.0,
				"phase1": -4.712, "phase2": -7.854},
			{"center": Vector2(0, 0), "radius": 19.0, "height": 6.0,
				"phase1": -4.712, "phase2": -7.854},
		],
		"ramps": [
			{"base": Vector2(0, 41), "dir": Vector2(0, -1),
				"length": 24.0, "width": 6.5, "h0": 0.0, "h1": 6.0},
		],
		"ponds": [Vector3(-38, 0, -30), Vector3(24, 0, 28),
			Vector3(52, 0, -2), Vector3(-20, 0, 52)],
		"bases": {
			0: {"town_hall": Vector3(-44, 0, 40), "house": Vector3(-37, 0, 45),
				"barracks": Vector3(-48, 0, 32)},
			1: {"town_hall": Vector3(44, 0, -40), "house": Vector3(37, 0, -45),
				"barracks": Vector3(48, 0, -32)},
		},
		"prize": Vector3(6, 0, -7),
		"squads": {
			0: {"spawn": Vector3(-40, 0, 36),
				"legs": [Vector3(-20, 0, 44), Vector3(2, 0, 47),
					Vector3(0, 0, 20), Vector3(-7, 0, -8)]},
			1: {"spawn": Vector3(40, 0, -36),
				"legs": [Vector3(48, 0, 26), Vector3(20, 0, 48),
					Vector3(2, 0, 47), Vector3(0, 0, 20),
					Vector3(7, 0, 8)]},
		},
		"edge_probe": {"spawn": Vector3(0, 0, -25),
			"target": Vector3(0, 0, -4), "min_h": 1.8, "max_h": 4.6},
		"top_stats": {"center": Vector2(0, 0), "radius": 10.0, "tier": 6.0},
		"cams": {
			"overview_pos": Vector3(54, 52, 60), "overview_tgt": Vector3(0, 1, 0),
			"low_pos": Vector3(7, 2.2, 55), "low_tgt": Vector3(0, 5.5, 6),
		},
		"trees": [Vector2(-48, -16), Vector2(-24, -44), Vector2(16, -48),
			Vector2(48, 18), Vector2(-52, 12), Vector2(12, 44),
			Vector2(-8, -8), Vector2(8, 12), Vector2(-12, 6)],
		"rocks": [Vector2(-34, 20), Vector2(36, -20), Vector2(-6, -14),
			Vector2(10, -4), Vector2(40, 40)],
	},
	"terraced_valley": {
		"seed": 3303, "pond_radius": 5.0,
		"zones": [
			{"center": Vector2(-34, 4), "radius": 14.0, "radius_z": 58.0,
				"height": 3.0, "phase1": 0.0, "phase2": 0.0},
			{"center": Vector2(34, 4), "radius": 14.0, "radius_z": 58.0,
				"height": 3.0, "phase1": 0.0, "phase2": 0.0},
			{"center": Vector2(0, -47), "radius": 72.0, "radius_z": 13.0,
				"height": 6.0, "phase1": 0.0, "phase2": 0.0},
		],
		"ramps": [
			{"base": Vector2(-14, 2), "dir": Vector2(-1, 0),
				"length": 13.0, "width": 5.5, "h0": 0.0, "h1": 3.0},
			{"base": Vector2(14, 2), "dir": Vector2(1, 0),
				"length": 13.0, "width": 5.5, "h0": 0.0, "h1": 3.0},
			{"base": Vector2(-34, -29), "dir": Vector2(0, -1),
				"length": 12.0, "width": 5.5, "h0": 3.0, "h1": 6.0},
			{"base": Vector2(34, -29), "dir": Vector2(0, -1),
				"length": 12.0, "width": 5.5, "h0": 3.0, "h1": 6.0},
			{"base": Vector2(0, -27), "dir": Vector2(0, -1),
				"length": 18.0, "width": 6.0, "h0": 0.0, "h1": 6.0},
		],
		"ponds": [Vector3(0, 0, 26), Vector3(0, 0, 6), Vector3(0, 0, -14)],
		"bases": {
			0: {"town_hall": Vector3(-16, 0, 46), "house": Vector3(-9, 0, 51),
				"barracks": Vector3(-20, 0, 52)},
			1: {"town_hall": Vector3(16, 0, 46), "house": Vector3(9, 0, 51),
				"barracks": Vector3(20, 0, 52)},
		},
		"prize": Vector3(16, 0, -47),
		"squads": {
			0: {"spawn": Vector3(-14, 0, 40),
				"legs": [Vector3(-14, 0, 8), Vector3(-27, 0, 2),
					Vector3(-34, 0, -22), Vector3(-34, 0, -38),
					Vector3(-26, 0, -44)]},
			1: {"spawn": Vector3(14, 0, 40),
				"legs": [Vector3(8, 0, 14), Vector3(0, 0, -21),
					Vector3(0, 0, -44)]},
		},
		"edge_probe": {"spawn": Vector3(-10, 0, -24),
			"target": Vector3(-10, 0, -46), "min_h": -0.5, "max_h": 1.5},
		"top_stats": {"center": Vector2(0, -46), "radius": 9.0, "tier": 6.0},
		"cams": {
			"overview_pos": Vector3(54, 52, 60), "overview_tgt": Vector3(0, 0, -6),
			"low_pos": Vector3(-3, 2.4, 36), "low_tgt": Vector3(0, 5.0, -34),
		},
		"trees": [Vector2(-30, 30), Vector2(30, 30), Vector2(-38, -8),
			Vector2(38, -8), Vector2(-28, -40), Vector2(28, -40),
			Vector2(-11, 33), Vector2(11, 33), Vector2(-44, 20),
			Vector2(44, 20)],
		"rocks": [Vector2(-24, 12), Vector2(24, 12), Vector2(-12, -30),
			Vector2(12, -30), Vector2(-40, -30)],
	},
	"the_staircase": {
		"seed": 4404, "pond_radius": 4.5,
		"zones": [
			{"center": Vector2(-13, 0), "radius": 12.0, "radius_z": 72.0,
				"height": 3.0, "phase1": 0.0, "phase2": 0.0},
			{"center": Vector2(12, 0), "radius": 12.0, "radius_z": 72.0,
				"height": 6.0, "phase1": 0.0, "phase2": 0.0},
			{"center": Vector2(38, 0), "radius": 15.0, "radius_z": 72.0,
				"height": 9.0, "phase1": 0.0, "phase2": 0.0},
		],
		"ramps": [
			{"base": Vector2(-31, -30), "dir": Vector2(1, 0),
				"length": 13.0, "width": 6.0, "h0": 0.0, "h1": 3.0},
			{"base": Vector2(-31, 30), "dir": Vector2(1, 0),
				"length": 13.0, "width": 6.0, "h0": 0.0, "h1": 3.0},
			{"base": Vector2(-6, -30), "dir": Vector2(1, 0),
				"length": 13.0, "width": 6.0, "h0": 3.0, "h1": 6.0},
			{"base": Vector2(-6, 30), "dir": Vector2(1, 0),
				"length": 13.0, "width": 6.0, "h0": 3.0, "h1": 6.0},
			{"base": Vector2(18, -30), "dir": Vector2(1, 0),
				"length": 13.0, "width": 6.0, "h0": 6.0, "h1": 9.0},
			{"base": Vector2(18, 30), "dir": Vector2(1, 0),
				"length": 13.0, "width": 6.0, "h0": 6.0, "h1": 9.0},
		],
		"ponds": [Vector3(-52, 0, -46)],
		"bases": {
			0: {"town_hall": Vector3(-44, 0, -34), "house": Vector3(-37, 0, -39),
				"barracks": Vector3(-47, 0, -25)},
			1: {"town_hall": Vector3(-44, 0, 34), "house": Vector3(-37, 0, 39),
				"barracks": Vector3(-47, 0, 25)},
		},
		"prize": Vector3(46, 0, 8),
		"squads": {
			0: {"spawn": Vector3(-40, 0, -30),
				"legs": [Vector3(-35, 0, -30), Vector3(-14, 0, -30),
					Vector3(10, 0, -30), Vector3(40, 0, -28)]},
			1: {"spawn": Vector3(-40, 0, 30),
				"legs": [Vector3(-35, 0, 30), Vector3(-14, 0, 30),
					Vector3(10, 0, 30), Vector3(40, 0, 28)]},
		},
		"edge_probe": {"spawn": Vector3(16, 0, 8),
			"target": Vector3(46, 0, 8), "min_h": 4.8, "max_h": 7.6},
		"top_stats": {"center": Vector2(38, -2), "radius": 8.0, "tier": 9.0},
		"cams": {
			"overview_pos": Vector3(56, 54, 58), "overview_tgt": Vector3(2, 1, 0),
			"low_pos": Vector3(-46, 7.0, 28), "low_tgt": Vector3(26, 3.0, -12),
		},
		"trees": [Vector2(-52, -14), Vector2(-52, 14), Vector2(-34, 44),
			Vector2(-18, 8), Vector2(4, -12), Vector2(28, 12),
			Vector2(48, -20), Vector2(-4, 40), Vector2(20, -42)],
		"rocks": [Vector2(-38, -8), Vector2(-2, 22), Vector2(16, 20),
			Vector2(44, 22), Vector2(-20, -44)],
	},
}

# --- ring12 layout (generated: rotational symmetry) --------------------------

func _v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0, p.y)


## 12-player ring layout, built by rotating one start kit 12 times
## (identical-by-rotation starts = fairness by construction; the
## only asymmetry is the world-space micro-noise, which the probe's
## fairness pass measures). For start i at azimuth u (unit vector
## in xz): base flat at radius 76, its +3m expansion plateau at
## radius 90 with its ramp on the azimuth line (foot at 74, below
## the plateau edge's earliest wobble reach — a foot inside the
## edge band makes the ramp's end-fade carve a moat — the
## ramp is the start's chokepoint, plateau cliff sides face the
## neighbours), a contested +6m peak at radius 44 halfway to the
## next start with a ramp from each neighbour's side, and the
## fortress-style centre: +3m ring (r24) under a +6m top (r15),
## ramps facing starts 0/3/6/9. Ponds sit at radius 64 on the peak
## azimuths — clear of routes, ramp bases and spawn blocks.
## Buildings flank the azimuth corridor (|lateral| >= 8).
##
## Sizing constraint (production, found by the first ring12 probe):
## RTSUnit._apply_movement clamps unit positions to ±100 on x/z
## ("map bounds 200x200"), so nothing a unit must stand on may sit
## outside that box. The first cut put expansions at radius 125
## and every march stalled exactly at the clamp (centroid best =
## target - 100). The ring therefore lives inside ±100 with
## margin; the terrain (220x220) extends past it as scenery.
func _gen_ring12() -> Dictionary:
	var zones: Array = []
	var ramps: Array = []
	var ponds: Array = []
	var bases := {}
	var squads := {}
	var center_runs := {}
	var fair_starts: Array = []
	var fair_exps: Array = []
	var trees: Array = []
	var rocks: Array = []
	zones.append({"center": Vector2.ZERO, "radius": 24.0, "height": 3.0,
		"phase1": 0.7, "phase2": 1.3})
	zones.append({"center": Vector2.ZERO, "radius": 15.0, "height": 6.0,
		"phase1": 2.1, "phase2": 0.4})
	for i in 12:
		var th := TAU * float(i) / 12.0
		var u := Vector2(cos(th), sin(th))
		var v := Vector2(-sin(th), cos(th))
		var s := u * 76.0
		var e := u * 90.0
		# Expansion plateau + its ramp (foot just behind the base).
		zones.append({"center": e, "radius": 10.0, "height": 3.0,
			"phase1": fmod(1.13 * float(i), TAU),
			"phase2": fmod(2.71 * float(i), TAU)})
		ramps.append({"base": u * 74.0, "dir": u, "length": 16.0,
			"width": 9.0, "h0": 0.0, "h1": 3.0})
		# Contested peak between this start and the next.
		var pk_ang := th + TAU / 24.0
		var pk := Vector2(cos(pk_ang), sin(pk_ang)) * 44.0
		zones.append({"center": pk, "radius": 9.0, "height": 6.0,
			"phase1": fmod(0.71 * float(i) + 0.5, TAU),
			"phase2": fmod(1.97 * float(i), TAU)})
		for nb in [i, (i + 1) % 12]:
			var nth := TAU * float(nb) / 12.0
			var ns := Vector2(cos(nth), sin(nth)) * 76.0
			var d := (ns - pk).normalized()
			ramps.append({"base": pk + d * 20.0, "dir": -d,
				"length": 19.0, "width": 6.0, "h0": 0.0, "h1": 6.0})
		var pa := th + TAU / 24.0
		ponds.append(_v3(Vector2(cos(pa), sin(pa)) * 64.0))
		var thv := s + v * 8.0 - u * 1.0
		var hv := s - v * 8.0 - u * 1.0
		var bv := s - v * 8.0 - u * 9.0
		bases[i] = {"town_hall": _v3(thv), "house": _v3(hv),
			"barracks": _v3(bv)}
		fair_starts.append(Vector2(thv.x, thv.y))
		fair_exps.append(e)
		squads[i] = {"spawn": _v3(s - u * 6.0),
			"legs": [_v3(u * 80.0), _v3(e)]}
		if i == 0 or i == 6:
			center_runs[i] = [_v3(u * 80.0), _v3(u * 44.0),
				_v3(u * 30.0), _v3(u * 4.0)]
		trees.append(s + v * 13.0 - u * 6.0)
		trees.append(s - v * 13.0 - u * 6.0)
		rocks.append(s + v * 11.0 + u * 11.0)
	# Centre ramps face every 3rd start.
	for k in 4:
		var th := TAU * float(k) / 4.0
		var u := Vector2(cos(th), sin(th))
		ramps.append({"base": u * 38.0, "dir": -u, "length": 28.0,
			"width": 8.0, "h0": 0.0, "h1": 6.0})
	for k in 4:
		var a := TAU * (float(k) + 0.5) / 4.0
		trees.append(Vector2(cos(a), sin(a)) * 44.0)
	return {
		"seed": 5505, "pond_radius": 5.5,
		"map_points": 221, "cell_size": 1.0,
		"factions": 12, "squad_count": 15,
		"zones": zones, "ramps": ramps, "ponds": ponds,
		"bases": bases, "prize": Vector3(3.0, 0, 3.0),
		"squads": squads, "center_runs": center_runs,
		"fairness": {"starts": fair_starts, "expansions": fair_exps},
		"edge_probe": {"spawn": Vector3(90, 0, 15),
			"target": Vector3(90, 0, 0), "min_h": -0.5, "max_h": 1.5},
		"top_stats": {"center": Vector2.ZERO, "radius": 8.0, "tier": 6.0},
		"shot_views": [
			{"name": "overview", "command": true, "relief": false,
				"pos": Vector3(70, 105, 118), "tgt": Vector3(0, 0, 0)},
			{"name": "start", "command": false, "relief": true,
				"pos": Vector3(62, 2.4, 14), "tgt": Vector3(92, 3.5, -2)},
			{"name": "center", "command": false, "relief": true,
				"march_center": true,
				"pos": Vector3(17, 4.5, 8), "tgt": Vector3(0, 0.8, 0)},
		],
		"trees": trees, "rocks": rocks,
	}


var _layout: Dictionary
var _map_name := "twin_crowns"
var _terrain: ZonesTerrain
var _mgr: RTSManager
var _renderer: RTSUnitRenderer
var _cam: RTSCamera
var _armies: Node3D
var _bases_node: Node3D
var _units: Array = []
var _units_by_faction := {0: [], 1: []}
var _buildings: Array = []
var _walker: TerrainWalker
var _mode := "run"
var _shot_dir := "/tmp/warlords_maps_shots"
var _fails := 0
# Perf-probe state (mode=perf): ground-snap timing accumulators and
# per-unit home slots for the teleport reset between steps.
var _snap_timing := false
var _snap_usec := 0
var _snap_calls := 0
var _perf_homes := {}
var _perf_counts := {}
var _perf_rr := 0


func _ready() -> void:
	process_priority = -100 # unit snap before the renderer (companions)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			_mode = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-dir="):
			_shot_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--map="):
			_map_name = arg.get_slice("=", 1)
	if _map_name == "ring12":
		_layout = _gen_ring12()
	elif LAYOUTS.has(_map_name):
		_layout = LAYOUTS[_map_name]
	else:
		printerr("[WMAPS] unknown map ", _map_name, " — using twin_crowns")
		_map_name = "twin_crowns"
		_layout = LAYOUTS[_map_name]
	print("[WMAPS] map=", _map_name, " mode=", _mode)
	_setup_env()
	_build_terrain()
	_build_rts_stack()
	if _mode == "perf":
		await _run_perf()
		print("[WMAPS] ", _map_name, " done fails=", _fails)
		get_tree().quit(_fails)
		return
	_place_buildings()
	_dress()
	_spawn_armies()
	_spawn_walker((_layout["edge_probe"] as Dictionary)["spawn"])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	match _mode:
		"probe":
			await _run_probe()
			print("[WMAPS] ", _map_name, " done fails=", _fails)
			get_tree().quit(_fails)
		"shots":
			_cam.set_process(false)
			_cam.set_process_input(false)
			await _run_shots()
			print("[WMAPS] ", _map_name, " done fails=", _fails)
			get_tree().quit(_fails)
		_:
			_set_view(true)
			_cam.position = Vector3(0, 95, 0.001)
			_cam.rotation = Vector3(-PI / 2, 0, 0)
			_march_all()


func _process(_delta: float) -> void:
	if _terrain == null:
		return
	var snap_t0 := Time.get_ticks_usec() if _snap_timing else 0
	for u in _units:
		if not is_instance_valid(u):
			continue
		var n := u as Node3D
		var p := n.global_position
		var gy := _terrain.get_ground_height(p)
		if absf(p.y - gy) > 0.0005:
			n.global_position = Vector3(p.x, gy, p.z)
	if _snap_timing:
		_snap_usec += Time.get_ticks_usec() - snap_t0
		_snap_calls += 1


# --- world -------------------------------------------------------------------

func _setup_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = false
	add_child(sun)
	var env := WorldEnvironment.new()
	env.name = "Environment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.55, 0.75)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)


func _build_terrain() -> void:
	_terrain = ZonesTerrain.new()
	_terrain.name = "Terrain"
	_terrain.map_points = int(_layout.get("map_points", 121))
	_terrain.cell_size = float(_layout.get("cell_size", 1.0))
	_terrain.terrain_seed = int(_layout["seed"])
	_terrain.noise_frequency = 0.045
	_terrain.amplitude = 0.6 # ±0.3m low-freq base; +±0.45m rough texture (ZonesTerrain)
	_terrain.water_level = -0.55 # below the noise floor: pond-only water
	_terrain.smooth_passes = 1
	_terrain.pond_radius = float(_layout["pond_radius"])
	_terrain.pond_depth = 1.7
	_terrain.zones.assign((_layout["zones"] as Array).duplicate())
	_terrain.ramps.assign((_layout["ramps"] as Array).duplicate())
	for p in _layout["ponds"]:
		_terrain.pond_centers.append(p)
	add_child(_terrain)
	_terrain.generate()


func _build_rts_stack() -> void:
	_mgr = RTSManager.new()
	_mgr.name = "RTSManager"
	add_child(_mgr)
	_bases_node = Node3D.new()
	_bases_node.name = "Bases"
	add_child(_bases_node)
	_armies = Node3D.new()
	_armies.name = "Armies"
	add_child(_armies)
	var nf := int(_layout.get("factions", 2))
	_units_by_faction.clear()
	if nf <= 2:
		_mgr.register_faction(0, multiplayer.get_unique_id(), "warrior")
		_mgr.register_faction(1, -1, "rogue")
		_units_by_faction[0] = []
		_units_by_faction[1] = []
	else:
		# 12 player slots: the stack ships 3 civs, so slots cycle
		# warrior/rogue/mage (civ bonuses + sprite sets), while
		# player identity comes from RTSManager.FACTION_COLORS —
		# 12 distinct colors driving unit rings, MultiMesh tints
		# and building banners.
		var classes := ["warrior", "rogue", "mage"]
		for f in nf:
			_mgr.register_faction(f,
				multiplayer.get_unique_id() if f == 0 else -1,
				classes[f % classes.size()])
			_units_by_faction[f] = []
	_renderer = RTSUnitRenderer.new()
	_renderer.name = "RTSUnitRenderer"
	add_child(_renderer)
	_cam = RTSCamera.new()
	_cam.name = "RTSCamera"
	_cam.add_to_group("rts_camera")
	add_child(_cam)
	_cam.setup(_mgr, 0)


func _ground(p: Vector3) -> float:
	return _terrain.get_ground_height(p)


func _grade(p: Vector3) -> float:
	var e := 0.9
	var dx := _ground(p + Vector3(e, 0, 0)) - _ground(p + Vector3(-e, 0, 0))
	var dz := _ground(p + Vector3(0, 0, e)) - _ground(p + Vector3(0, 0, -e))
	return sqrt(dx * dx + dz * dz) / (2.0 * e)


# --- measurements --------------------------------------------------------------

## Interior flatness of the top tier (ramp channels excluded).
func _tier_stats(center: Vector2, radius: float, tier: float) -> Dictionary:
	var n := 0
	var mean := 0.0
	var vals: Array[float] = []
	var step := 1.5
	var gx := center.x - radius
	while gx <= center.x + radius:
		var gz := center.y - radius
		while gz <= center.y + radius:
			var d := Vector2(gx - center.x, gz - center.y).length()
			if d <= radius:
				var near_ramp := false
				for rp in _terrain.ramps:
					var b: Vector2 = rp["base"]
					var dir: Vector2 = rp["dir"]
					var rel := Vector2(gx - b.x, gz - b.y)
					var s := rel.dot(dir)
					var lat := rel.dot(Vector2(-dir.y, dir.x))
					if s > -2.0 and s < float(rp["length"]) + 2.0 \
							and absf(lat) < 4.5:
						near_ramp = true
				if not near_ramp:
					var h := _ground(Vector3(gx, 0, gz))
					vals.append(h)
					mean += h
					n += 1
			gz += step
		gx += step
	mean /= float(maxi(n, 1))
	var var_sum := 0.0
	var max_dev := 0.0
	for h in vals:
		var_sum += (h - mean) * (h - mean)
		max_dev = maxf(max_dev, absf(h - tier))
	return {"n": n, "mean": mean, "stddev": sqrt(var_sum / float(maxi(n, 1))),
		"max_dev": max_dev}


func _report_top_tier() -> void:
	var spec: Dictionary = _layout["top_stats"]
	var st := _tier_stats(spec["center"], float(spec["radius"]),
		float(spec["tier"]))
	print("[WMAPS] ", _map_name, " top tier (", spec["tier"], "m) flatness: n=",
		st["n"], " mean=", snappedf(float(st["mean"]), 0.01),
		" stddev=", snappedf(float(st["stddev"]), 0.01),
		" max_dev=", snappedf(float(st["max_dev"]), 0.01))
	if float(st["max_dev"]) > 0.9:
		_fails += 1
		printerr("[WMAPS] FAIL ", _map_name, " top tier max_dev ",
			st["max_dev"], " > 0.9 (roughness bound)")


func _report_ramp_grades() -> void:
	for ri in _terrain.ramps.size():
		var rp: Dictionary = _terrain.ramps[ri]
		var b: Vector2 = rp["base"]
		var dir: Vector2 = rp["dir"]
		var gmax := 0.0
		var s := -1.0
		while s <= float(rp["length"]) + 1.0:
			var ahead := b + dir * (s + 0.5)
			var behind := b + dir * (s - 0.5)
			var g := absf(_ground(Vector3(ahead.x, 0, ahead.y))
				- _ground(Vector3(behind.x, 0, behind.y)))
			gmax = maxf(gmax, g)
			s += 0.5
		print("[WMAPS] ", _map_name, " ramp ", ri + 1, " (",
			rp["h0"], "->", rp["h1"], "m) centreline max grade=",
			snappedf(gmax * 100.0, 0), "% (design cap ~50%)")
		if gmax > 0.7:
			_fails += 1
			printerr("[WMAPS] FAIL ", _map_name, " ramp ", ri + 1,
				" grade ", gmax, " over cap")


# --- buildings -------------------------------------------------------------------

func _footprint_stats(center: Vector3, size: Vector2) -> Dictionary:
	var hx := size.x * 0.5 + PAD
	var hz := size.y * 0.5 + PAD
	var step := 0.4
	var nx := maxi(2, int(ceil(hx * 2.0 / step)))
	var nz := maxi(2, int(ceil(hz * 2.0 / step)))
	var mn := INF
	var mx := -INF
	for iz in nz + 1:
		for ix in nx + 1:
			var p := Vector3(
				center.x - hx + hx * 2.0 * float(ix) / float(nx), 0,
				center.z - hz + hz * 2.0 * float(iz) / float(nz))
			var hh := _terrain.get_ground_height(p)
			mn = minf(mn, hh)
			mx = maxf(mx, hh)
	return {"min": mn, "max": mx, "range": mx - mn,
		"dry": mn >= _terrain.water_level + 0.02}


## Civ for a faction: the two classic slots use the CIVS map;
## extra slots (ring12) take the civ they registered with.
func _civ_for(faction: int) -> CivData:
	if CIVS.has(faction):
		return CivData.for_civ_id(str(CIVS[faction]))
	var c := _mgr.get_civ(faction)
	return c if c != null else CivData.for_class("warrior")


## Production-mirror spawn (dungeon.gd via rts_buildings_terrain.gd),
## pos.y = footprint minimum.
func _spawn_building(faction: int, btype: String, center: Vector3,
		label: String) -> void:
	var st := _footprint_stats(center, FOOTPRINTS[btype])
	var civ := _civ_for(faction)
	var b := RTSBuilding.new()
	b.setup(faction, btype, civ)
	b.building_id = _mgr.alloc_building_id()
	b.name = "RTSBuilding_%d" % b.building_id
	b.rts_manager = _mgr
	b.position = Vector3(center.x, float(st["min"]), center.z)
	_bases_node.add_child(b)
	b.start_construction()
	_buildings.append({"node": b, "type": btype, "label": label,
		"center": center, "range": float(st["range"])})
	print("[WMAPS] ", _map_name, " building ", label, " (", btype,
		", faction ", faction, ") at (", center.x, ", ", center.z,
		") footprint range=", snappedf(float(st["range"]), 0.01),
		"m placed_y=", snappedf(float(st["min"]), 0.01),
		" dry=", bool(st["dry"]))
	if float(st["range"]) > 1.2:
		_fails += 1
		printerr("[WMAPS] FAIL ", _map_name, " building ", label,
			" footprint range over the 1.2m cap")
	if not bool(st["dry"]):
		_fails += 1
		printerr("[WMAPS] FAIL ", _map_name, " building ", label, " in water")


func _place_buildings() -> void:
	var keys: Array = (_layout["bases"] as Dictionary).keys()
	keys.sort()
	for faction in keys:
		var base: Dictionary = (_layout["bases"] as Dictionary)[faction]
		for btype in ["town_hall", "house", "barracks"]:
			_spawn_building(faction, btype, base[btype],
				"f%d_%s" % [faction, btype])


# --- dressing (light) ------------------------------------------------------------

func _place_prop(type: String, p: Vector3, rot_y: float, sink: float = 0.0) -> void:
	var prop := PropBuilder.build(type, 1.0, {"pos": p})
	prop.position = Vector3(p.x, _ground(p) - sink, p.z)
	prop.rotation.y = rot_y
	add_child(prop)


func _dress() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for t in _layout["trees"]:
		_place_prop("tree", Vector3(t.x, 0, t.y), rng.randf() * TAU)
	for r in _layout["rocks"]:
		_place_prop("rock", Vector3(r.x, 0, r.y), rng.randf() * TAU, 0.15)
	# The prize: a rock ring + pines on the top tier.
	var prize: Vector3 = _layout["prize"]
	for k in 5:
		var a := TAU * float(k) / 5.0
		_place_prop("rock", prize + Vector3(cos(a) * 2.6, 0, sin(a) * 2.6),
			rng.randf() * TAU, 0.1)
	_place_prop("pine", prize + Vector3(-3.4, 0, -2.2), rng.randf() * TAU)
	_place_prop("pine", prize + Vector3(3.4, 0, 2.2), rng.randf() * TAU)


# --- units -------------------------------------------------------------------

func _spawn_one(faction: int, unit_type: String, pos: Vector3) -> void:
	var civ := _civ_for(faction)
	var u := RTSUnit.new()
	u.setup(faction, unit_type, civ)
	u.unit_id = _mgr.alloc_unit_id()
	u.name = "RTSUnit_%d" % u.unit_id
	u.position = Vector3(pos.x, _ground(pos), pos.z)
	_armies.add_child(u)
	_units.append(u)
	(_units_by_faction[faction] as Array).append(u)


## squad_count units per faction in a 4-wide block (60% spearmen,
## 40% archers; default 20 = 12 + 8, the classic maps' mix).
func _spawn_armies() -> void:
	var count := int(_layout.get("squad_count", 20))
	var keys: Array = (_layout["squads"] as Dictionary).keys()
	keys.sort()
	for faction in keys:
		var anchor: Vector3 = ((_layout["squads"] as Dictionary)[faction]
			as Dictionary)["spawn"]
		for idx in count:
			var col := idx % 4
			var row := idx / 4
			var utype := "spearman" if idx < count * 3 / 5 else "archer"
			_spawn_one(faction, utype, anchor + Vector3(
				(float(col) - 1.5) * SPACING, 0, float(row) * SPACING))
	print("[WMAPS] ", _map_name, " armies spawned: ", _units.size(), " units")


func _centroid(units: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in units:
		if is_instance_valid(u):
			c += (u as Node3D).global_position
			n += 1
	return c / float(maxi(n, 1)) if n > 0 else Vector3.ZERO


## March one faction's squad through its layout legs; score the
## end state.
func _march_faction(faction: int) -> Dictionary:
	var spec: Dictionary = ((_layout["squads"] as Dictionary)[faction]
		as Dictionary)
	return await _march_units(faction, _units_by_faction[faction],
		spec["legs"])


## March a set of units through waypoint legs (ramps) to the final
## leg's target (the gather point); score the end state.
func _march_units(faction: int, units: Array, legs: Array) -> Dictionary:
	var gather: Vector3 = legs[legs.size() - 1]
	var total_frames := 0
	for li in legs.size():
		var tgt: Vector3 = legs[li]
		var ids: Array = []
		for u in units:
			ids.append(int(u.get("unit_id")))
		_mgr.order_move_squad(ids, tgt)
		var frames := 0
		var best := INF
		var since_improve := 0
		while frames < 1500:
			await get_tree().physics_frame
			frames += 1
			total_frames += 1
			var c := _centroid(units)
			var d := Vector2(c.x - tgt.x, c.z - tgt.z).length()
			if d < best - 0.2:
				best = d
				since_improve = 0
			else:
				since_improve += 1
			if d < 2.5 or since_improve > 300:
				break
		print("[WMAPS] ", _map_name, " f", faction, " march leg ",
			li + 1, " -> (", tgt.x, ", ", tgt.z, ") frames=", frames,
			" centroid_dist=", snappedf(best if best != INF else -1.0, 0.1))
	# Regroup: legs end when the CENTROID arrives, which can leave a
	# tail still strung out along the route (e.g. funneling out of a
	# ramp exit). The last leg's order is still active — units keep
	# walking to the gather on their own — so just wait for the tail
	# to actually close up before scoring. (No re-issue: re-ordering
	# a squad whose members already sit on the target point crashed
	# the engine natively once, fortress f1 regroup, 2026-10-12.)
	var arrived_now := 0
	var best_arrived := -1
	var since_arrive := 0
	var regroup_frames := 0
	while regroup_frames < 1200:
		await get_tree().physics_frame
		regroup_frames += 1
		if regroup_frames % 30 != 0:
			continue
		arrived_now = 0
		for u in units:
			if not is_instance_valid(u):
				continue
			var p := (u as Node3D).global_position
			if Vector2(p.x - gather.x, p.z - gather.z).length() < 6.5:
				arrived_now += 1
		if arrived_now > best_arrived:
			best_arrived = arrived_now
			since_arrive = 0
		else:
			since_arrive += 30
		if arrived_now >= units.size() or since_arrive > 300:
			break
	total_frames += regroup_frames
	print("[WMAPS] ", _map_name, " f", faction, " regroup frames=",
		regroup_frames, " arrived=", best_arrived, "/", units.size())
	for i in 2:
		await get_tree().process_frame
	var arrived := 0
	var on_steep := 0
	var wet := 0
	var max_dev := 0.0
	for u in units:
		if not is_instance_valid(u):
			continue
		var p := (u as Node3D).global_position
		max_dev = maxf(max_dev, absf(p.y - _ground(p)))
		if _terrain.is_water(p):
			wet += 1
		if Vector2(p.x - gather.x, p.z - gather.z).length() < 6.5:
			arrived += 1
		elif _grade(p) > 1.0:
			on_steep += 1
	var stats := {"frames": total_frames, "arrived": arrived,
		"on_steep": on_steep, "wet": wet, "max_dev": max_dev}
	print("[WMAPS] ", _map_name, " f", faction, " march done: frames=",
		total_frames, " arrived_at_top=", arrived, "/", units.size(),
		" left_on_steep=", on_steep, " in_water=", wet,
		" max |y-ground|=", snappedf(max_dev, 0.001))
	if arrived < int(ceil(0.85 * float(units.size()))):
		_fails += 1
		printerr("[WMAPS] FAIL ", _map_name, " f", faction, " only ",
			arrived, " units reached the top tier")
	if on_steep > 1:
		_fails += 1
		printerr("[WMAPS] FAIL ", _map_name, " f", faction, " ",
			on_steep, " units left hanging on steep ground")
	if wet > 0:
		_fails += 1
		printerr("[WMAPS] FAIL ", _map_name, " f", faction, " ",
			wet, " units ended in water")
	return stats


func _march_all() -> void:
	var keys: Array = (_layout["squads"] as Dictionary).keys()
	keys.sort()
	for faction in keys:
		await _march_faction(faction)


# --- walker -------------------------------------------------------------------

func _spawn_walker(spawn: Vector3) -> void:
	_walker = TerrainWalker.new()
	_walker.terrain = _terrain
	_walker.position = Vector3(spawn.x, _ground(spawn) + 1.5, spawn.z)
	add_child(_walker)


func _reset_walker(spawn: Vector3, target: Vector3) -> void:
	_walker.position = Vector3(spawn.x, _ground(spawn) + 1.5, spawn.z)
	_walker.velocity = Vector3.ZERO
	_walker.waypoints = [target]
	_walker.distance_walked = 0.0
	_walker.max_deviation = 0.0


func _walk_until(progress: Callable, goal: float, max_frames: int) -> Dictionary:
	var best := -INF
	var since := 0
	var frames := 0
	while frames < max_frames:
		await get_tree().physics_frame
		frames += 1
		var v := float(progress.call(_walker.global_position))
		if v > best + 0.05:
			best = v
			since = 0
		else:
			since += 1
		if best >= goal:
			break
		if since > 300 and frames > 400:
			break
	var p := _walker.global_position
	return {"frames": frames, "best": best, "final": p,
		"height": p.y, "grade": _grade(p),
		"distance": _walker.distance_walked}


## Drive the walker at a non-ramp edge of the top tier: it must stall
## with its height inside the expected band (never reaches the tier).
func _run_edge_probe() -> void:
	var spec: Dictionary = _layout["edge_probe"]
	var spawn: Vector3 = spec["spawn"]
	var target: Vector3 = spec["target"]
	var dirv := Vector2(target.x - spawn.x, target.z - spawn.z)
	var total := dirv.length()
	dirv = dirv.normalized()
	_reset_walker(spawn, target)
	var res := await _walk_until(
		func(p: Vector3) -> float:
			return Vector2(p.x - spawn.x, p.z - spawn.z).dot(dirv),
		total - 5.0, 1500)
	print("[WMAPS] ", _map_name, " walker vs top-tier edge: frames=",
		res["frames"], " progress=", snappedf(float(res["best"]), 0.1),
		"/", snappedf(total, 0.1), " stopped_at=(",
		snappedf((res["final"] as Vector3).x, 0.1), ", ",
		snappedf((res["final"] as Vector3).z, 0.1), ") height=",
		snappedf(float(res["height"]), 0.01), " (band ",
		spec["min_h"], "..", spec["max_h"], ") grade_at_stop=",
		snappedf(float(res["grade"]) * 100.0, 0), "% distance=",
		snappedf(float(res["distance"]), 0.1), "m")
	if float(res["height"]) < float(spec["min_h"]) \
			or float(res["height"]) > float(spec["max_h"]):
		_fails += 1
		printerr("[WMAPS] FAIL ", _map_name,
			" walker height outside the stall band — edge did not block")
	if float(res["best"]) > total - 5.0:
		_fails += 1
		printerr("[WMAPS] FAIL ", _map_name,
			" walker reached the top tier over a non-ramp edge")


# --- ring12 extra proofs -------------------------------------------------------

## Mean ground height over a disc. When axis is given, samples on
## the uphill ramp channel cut (within skip_lat of the axis, on the
## approach side) are excluded, mirroring _tier_stats.
func _sample_disc_mean(c: Vector2, radius: float,
		axis := Vector2.ZERO, skip_lat := -1.0) -> float:
	var sum := 0.0
	var n := 0
	var step := 1.5
	var gx := c.x - radius
	while gx <= c.x + radius:
		var gz := c.y - radius
		while gz <= c.y + radius:
			var rel := Vector2(gx - c.x, gz - c.y)
			if rel.length() <= radius:
				var keep := true
				if skip_lat >= 0.0:
					var lat := absf(rel.dot(Vector2(-axis.y, axis.x)))
					if lat < skip_lat and rel.dot(axis) < 1.0:
						keep = false
				if keep:
					sum += _ground(Vector3(gx, 0, gz))
					n += 1
			gz += step
		gx += step
	return sum / float(maxi(n, 1))


## Cross-start fairness: every start is the same kit rotated, so
## base-flat and expansion-top means should match across all 12
## starts up to world-space micro-noise. Spread over 0.6m would
## mean the zone structure itself differs per start (a real bug).
func _report_fairness() -> void:
	var fair: Dictionary = _layout["fairness"]
	var starts: Array = fair["starts"]
	var exps: Array = fair["expansions"]
	var base_means: Array[float] = []
	var exp_means: Array[float] = []
	for idx in starts.size():
		var c2: Vector2 = starts[idx]
		var e2: Vector2 = exps[idx]
		base_means.append(_sample_disc_mean(c2, 5.0))
		exp_means.append(_sample_disc_mean(e2, 5.0, e2.normalized(), 5.0))
	var b_spread := float(base_means.max()) - float(base_means.min())
	var e_spread := float(exp_means.max()) - float(exp_means.min())
	print("[WMAPS] ", _map_name, " fairness across ", starts.size(),
		" starts: base-flat mean min=", snappedf(float(base_means.min()), 0.01),
		" max=", snappedf(float(base_means.max()), 0.01),
		" spread=", snappedf(b_spread, 0.01),
		"m | expansion-top mean min=", snappedf(float(exp_means.min()), 0.01),
		" max=", snappedf(float(exp_means.max()), 0.01),
		" spread=", snappedf(e_spread, 0.01), "m")
	if b_spread > 0.6 or e_spread > 0.6:
		_fails += 1
		printerr("[WMAPS] FAIL ", _map_name,
			" start fairness spread over the 0.6m sanity bound")


## Two sample squads (opposite starts) march base -> centre mesa
## top via their azimuth's centre ramp. Each squad is despawned
## after scoring so the opposing run never meets it (aggro range
## would turn the proof into a battle).
func _run_center_runs() -> void:
	var runs: Dictionary = _layout["center_runs"]
	var keys: Array = runs.keys()
	keys.sort()
	for f in keys:
		var stats := await _march_units(f, _units_by_faction[f], runs[f])
		print("[WMAPS] ", _map_name, " f", f, " CENTRE RUN scored: arrived=",
			stats["arrived"], " on_steep=", stats["on_steep"],
			" wet=", stats["wet"])
		for u in _units_by_faction[f]:
			if is_instance_valid(u):
				_renderer.unregister_unit(u)
				(u as Node).queue_free()
		_units_by_faction[f] = []
		for i in 5:
			await get_tree().physics_frame


# --- modes -------------------------------------------------------------------

func _run_probe() -> void:
	for i in 30:
		await get_tree().physics_frame
	_report_top_tier()
	_report_ramp_grades()
	if _layout.has("fairness"):
		_report_fairness()
	await _run_edge_probe()
	await _march_all()
	if _layout.has("center_runs"):
		await _run_center_runs()
	for rec in _buildings:
		var b: RTSBuilding = rec["node"]
		print("[WMAPS] ", _map_name, " building final ", str(rec["label"]),
			" range=", snappedf(float(rec["range"]), 0.01), "m",
			" node_y==footprint_min: ",
			absf(b.position.y - _footprint_stats(rec["center"],
				FOOTPRINTS[str(rec["type"])])["min"]) < 0.01)


# --- perf probe (ring12) -------------------------------------------------------

## Per-faction gather point on the centre mesa top (ring of 12 at
## radius 5 — the convergence target for the march window).
func _perf_gather(f: int) -> Vector3:
	var th := TAU * float(f) / float(maxi(_units_by_faction.size(), 1))
	return Vector3(cos(th) * 5.0, 0, sin(th) * 5.0)


## Spawn `count` more perf units, round-robin across factions so
## every escalation step grows all factions evenly. Blocks are
## 15-wide grids on each faction's start anchor; home slots are
## remembered for the teleport reset.
func _perf_spawn(count: int, fids: Array) -> void:
	for k in count:
		var f: int = fids[_perf_rr % fids.size()]
		_perf_rr += 1
		var idx := int(_perf_counts.get(f, 0))
		_perf_counts[f] = idx + 1
		var anchor: Vector3 = ((_layout["squads"] as Dictionary)[f]
			as Dictionary)["spawn"]
		# Perf blocks (15 wide, 20 deep at the top step) are far
		# bigger than a start kit: centre them at 90% of the spawn
		# radius so they clear base buildings and ramp feet.
		anchor = Vector3(anchor.x * 0.9, 0, anchor.z * 0.9)
		var col := idx % 15
		var row := idx / 15
		var home := anchor + Vector3((float(col) - 7.0) * SPACING, 0,
			(float(row) - 10.0) * SPACING)
		var utype := "spearman" if idx % 5 < 3 else "archer"
		_spawn_one(f, utype, home)
		_perf_homes[_units[_units.size() - 1]] = home


## Stop everything and put every unit back on its home slot, so
## the next step's idle window measures units standing on their
## starts again (no despawn: the renderer holds unit refs).
## The dead are pruned FIRST: server-side death queue_free()s the
## unit, and touching a freed instance from the driver segfaults
## the engine natively (first perf run died in the step-2400
## order loop on exactly that).
func _perf_reset() -> void:
	var living: Array = []
	for u in _units:
		if is_instance_valid(u) and bool(u.get("alive")):
			living.append(u)
	_units = living
	for f in _units_by_faction:
		var fa: Array = []
		for u in _units_by_faction[f]:
			if is_instance_valid(u) and bool(u.get("alive")):
				fa.append(u)
		_units_by_faction[f] = fa
	_mgr.dissolve_squads_for(_units.duplicate())
	for u in _units:
		if not is_instance_valid(u):
			continue
		u.set("_move_target", Vector3.INF)
		u.set("_attack_target", null)
		var home: Vector3 = _perf_homes.get(u, Vector3.ZERO)
		(u as Node3D).global_position = Vector3(home.x, _ground(home), home.z)
		if u is CharacterBody3D:
			(u as CharacterBody3D).velocity = Vector3.ZERO


## Measure one window of `frames` physics frames: physics CPU ms
## and process CPU ms per frame (Performance monitors; process is
## sampled at physics ticks, so it is the process frame adjacent
## to each tick), wall ms per physics frame (real-time keeping —
## over 16.7ms the sim cannot hold 60Hz), and the driver's
## ground-snap cost (the terrain sampling share).
func _perf_window(frames: int) -> Dictionary:
	var phys_acc := 0.0
	var proc_acc := 0.0
	var snap0 := _snap_usec
	var snapc0 := _snap_calls
	var t0 := Time.get_ticks_usec()
	var n := 0
	while n < frames:
		await get_tree().physics_frame
		n += 1
		phys_acc += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		proc_acc += Performance.get_monitor(Performance.TIME_PROCESS)
	var snap_frames := maxi(_snap_calls - snapc0, 1)
	return {
		"phys_ms": phys_acc / float(n) * 1000.0,
		"proc_ms": proc_acc / float(n) * 1000.0,
		"wall_ms": float(Time.get_ticks_usec() - t0) / 1000.0 / float(n),
		"snap_ms": float(_snap_usec - snap0) / 1000.0 / float(snap_frames),
		"snap_us_per_unit": float(_snap_usec - snap0) / float(snap_frames)
			/ float(maxi(_units.size(), 1)),
	}


## 12-faction perf probe: escalating totals on the real RTS stack.
## Per step: timed spawn of the delta batch, settle, an IDLE window
## (units standing on their starts — the stack's dormancy applies,
## as in production), then a MARCH window (every unit ordered once
## to its gather on the centre mesa: the convergence worst case),
## then a teleport reset home. Converging columns make fringe
## contact, so marches include some real combat and deaths;
## survivors are counted per step and the reset prunes the dead
## before the next step tops back up to its target total.
func _run_perf() -> void:
	_snap_timing = true
	var steps := [1200, 2400, 3000, 3600]
	var fids: Array = _units_by_faction.keys()
	fids.sort()
	var nf := fids.size()
	print("[WMAPS] PERF factions=", nf, " steps=", steps,
		" (cumulative spawn; idle window then march window per step)")
	var past60 := 0
	var past30 := 0
	for si in steps.size():
		var target: int = steps[si]
		var t0 := Time.get_ticks_usec()
		_perf_spawn(target - _units.size(), fids)
		var spawn_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		for i in 45:
			await get_tree().physics_frame
		var idle := await _perf_window(180)
		for f in fids:
			var ids: Array = []
			for u in _units_by_faction[f]:
				if is_instance_valid(u) and bool(u.get("alive")):
					ids.append(int(u.get("unit_id")))
			_mgr.order_move_squad(ids, _perf_gather(f))
		var march := await _perf_window(600)
		var alive := 0
		var radial := 0.0
		for u in _units:
			if is_instance_valid(u) and bool(u.get("alive")):
				alive += 1
				var p := (u as Node3D).global_position
				radial += Vector2(p.x, p.z).length()
		print("[WMAPS] PERF step total=", target, " (", target / nf,
			"/faction) spawn_delta_ms=", snappedf(spawn_ms, 0),
			" alive_after_march=", alive,
			" mean_radius_after_march=", snappedf(
				radial / float(maxi(alive, 1)), 0.1), "m")
		print("[WMAPS] PERF   idle : phys=", snappedf(float(idle["phys_ms"]), 1),
			"ms proc=", snappedf(float(idle["proc_ms"]), 1),
			"ms wall/frame=", snappedf(float(idle["wall_ms"]), 1),
			"ms snap=", snappedf(float(idle["snap_ms"]), 2), "ms (",
			snappedf(float(idle["snap_us_per_unit"]), 1), "us/unit)")
		print("[WMAPS] PERF   march: phys=", snappedf(float(march["phys_ms"]), 1),
			"ms proc=", snappedf(float(march["proc_ms"]), 1),
			"ms wall/frame=", snappedf(float(march["wall_ms"]), 1),
			"ms snap=", snappedf(float(march["snap_ms"]), 2), "ms (",
			snappedf(float(march["snap_us_per_unit"]), 1), "us/unit)")
		if past60 == 0 and float(march["phys_ms"]) > 16.7:
			past60 = target
		if past30 == 0 and (float(march["phys_ms"]) > 33.3
				or float(march["wall_ms"]) > 33.4):
			past30 = target
		if float(march["wall_ms"]) > 250.0 and si < steps.size() - 1:
			print("[WMAPS] PERF aborting escalation: march wall/frame ",
				snappedf(float(march["wall_ms"]), 0),
				"ms — higher steps would not finish in reasonable time")
			break
		if si < steps.size() - 1:
			_perf_reset()
			for i in 15:
				await get_tree().physics_frame
	if past60 > 0:
		print("[WMAPS] PERF verdict: march physics passes the 60fps ",
			"budget (16.7ms) at ", past60, " units")
	else:
		print("[WMAPS] PERF verdict: march physics stays inside the ",
			"60fps budget through 3600 units")
	if past30 > 0:
		print("[WMAPS] PERF verdict: PRACTICAL CEILING at ", past30,
			" units (march busts the 30fps budget)")
	else:
		print("[WMAPS] PERF verdict: no 30fps ceiling hit through ",
			"3600 units — ceiling is beyond probe scope")


func _set_view(command: bool) -> void:
	_cam.active = command
	_cam.current = true
	get_tree().call_group("rts_units", "_on_command_view_toggled", command)


func _pose(pos: Vector3, target: Vector3) -> void:
	_cam.position = pos
	_cam.look_at(target)


func _run_shots() -> void:
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method("set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	print("[WMAPS] ", _map_name, " shots start units=", _units.size(),
		" buildings=", _buildings.size())
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	for i in 30:
		await get_tree().physics_frame
	for rec in _buildings:
		(rec["node"] as RTSBuilding).add_build_work(1000.0)
	for i in 10:
		await get_tree().process_frame
	# Walker presses against the top-tier edge during the shots.
	var spec: Dictionary = _layout["edge_probe"]
	_walker.waypoints = [spec["target"]]
	if _layout.has("shot_views"):
		await _run_shot_views()
		print("[WMAPS] ", _map_name, " shots done")
		return
	var cams: Dictionary = _layout["cams"]
	# View 1: overview — the whole layout must read.
	_set_view(true)
	_pose(cams["overview_pos"], cams["overview_tgt"])
	await _settle(15)
	await _snap(_map_name + "_overview.png")
	# View 2: ground level — tier structure / chokepoint / bases.
	_set_view(false)
	var lp: Vector3 = cams["low_pos"]
	var lt: Vector3 = cams["low_tgt"]
	_pose(Vector3(lp.x, _ground(lp) + lp.y, lp.z),
		Vector3(lt.x, _ground(lt) + lt.y, lt.z))
	await _settle(12)
	await _snap(_map_name + "_low.png")
	print("[WMAPS] ", _map_name, " shots done")


## Data-driven shot list (ring12): each view may march faction 0's
## squad to the centre first ("march_center"), use command view,
## and interpret pos/tgt y as height above the ground at that xz
## ("relief").
func _run_shot_views() -> void:
	_cam.far = 3000.0
	var views: Array = _layout["shot_views"]
	for vi in views.size():
		var v: Dictionary = views[vi]
		if bool(v.get("march_center", false)):
			var legs: Array = (_layout["center_runs"] as Dictionary)[0]
			await _march_units(0, _units_by_faction[0], legs)
		_set_view(bool(v.get("command", false)))
		var p: Vector3 = v["pos"]
		var t: Vector3 = v["tgt"]
		if bool(v.get("relief", false)):
			p = Vector3(p.x, _ground(p) + p.y, p.z)
			t = Vector3(t.x, _ground(t) + t.y, t.z)
		_pose(p, t)
		await _settle(15)
		await _snap(_map_name + "_" + str(v["name"]) + ".png")


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _snap(file_name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fails += 1
		printerr("[WMAPS] FAIL empty image for ", file_name)
		return
	img.save_png(_shot_dir + "/" + file_name)
	print("[WMAPS] saved ", _shot_dir + "/" + file_name)
