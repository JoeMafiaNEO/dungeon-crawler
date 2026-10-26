class_name DeepTreeCanvas
extends Control
## Issue #215: the Deep Tree node-style canvas UI (spec:
## files/deep-tree-node-ui-spec-2026-10-26.md, sections
## 2-6; design paper sections 14-15). One custom-drawn
## Control renders the local player's tree as a radial
## graph - class core at the center, one sector per
## branch, rings as radial distance - on a free pan/zoom
## canvas (Jesse's fork-5 ruling; his explicit scrolling
## approval covers this surface). No per-node Controls;
## hit-testing is geometric.
##
## The canvas holds no state of its own: every node,
## edge, state, wallet and number derives at rebuild
## time from DeepTree's API over the local player's
## data, and the layout is a deterministic pure function
## of (branch, ring, index). Entries rebuild at exactly
## three moments (spec 2.2): surface open, a purchase
## resolution (accept or denial surfacing), and - via
## the open/rebuild path - any hud-driven refresh.
## deep_tree.gd is read-only to this build; the pure
## functions below are statics so the suite pins them
## directly (acceptance section 8).

const DeepTree := preload(
	"res://scripts/progression/deep_tree.gd")

# --- Layout constants (spec 2.1; starting values) ---
const CORE_R := 90.0
const RING_GAP := 120.0
const STEP_DEG := 22.0
# --- Camera constants (spec 3) ---
const ZOOM_MIN := 0.25
const ZOOM_MAX := 2.5
# --- Glyph radii (world units at 1x; spec 4.1) ---
const GLYPH_STAT := 11.0
const GLYPH_MOD := 13.0
const GLYPH_BEHAVIOR := 15.0
const GLYPH_CAPSTONE := 21.0
const GLYPH_CORE := 34.0
const GLYPH_GATE := 26.0
# --- Label tiers (spec 9.4) ---
const ZOOM_LABELS_ALL := 1.1
const ZOOM_LABELS_FRONTIER := 0.55

## Sector center angles per class (spec 2.1, RULED:
## the adjacency-true ordering - the table's circular
## order is the graph's circular order, so bridge edges
## only ever join circular neighbors).
const SECTORS := {
	"mage": {2: -90.0, 1: 180.0, 3: 0.0, 0: 90.0},
	"warrior": {4: -135.0, 5: -45.0, 0: 90.0},
	"rogue": {6: -135.0, 7: -45.0, 0: 90.0},
	"architect": {8: -135.0, 9: -45.0, 0: 90.0},
}

## Branch identity colors, one UI-side table keyed by
## branch key (spec 3; exact hexes are the Art
## Director's pass within the SNES palette discipline).
const BRANCH_COLORS := {
	"fire": Color(0.98, 0.45, 0.13),
	"frost": Color(0.45, 0.80, 0.95),
	"storm": Color(0.95, 0.85, 0.25),
	"warden": Color(0.35, 0.75, 0.40),
	"conqueror": Color(0.85, 0.25, 0.30),
	"shadow": Color(0.60, 0.45, 0.90),
	"precision": Color(0.25, 0.80, 0.75),
	"engineering": Color(0.80, 0.65, 0.30),
	"forge": Color(0.95, 0.55, 0.20),
	"wayfaring": Color(0.60, 0.75, 0.55),
}

const BG_COLOR := Color(0.03, 0.04, 0.08)
const DOT_COLOR := Color(0.14, 0.17, 0.28)
const FOG_COLOR := Color(0.45, 0.52, 0.70, 0.16)
const LOCKED_FILL := Color(0.16, 0.16, 0.19)
const LOCKED_RING := Color(0.45, 0.45, 0.50)
const DARK_FILL := Color(0.07, 0.08, 0.13)

## The classless universal targets (spec 5.1 item 1):
## a small authored UI-side table. holy_light's entry
## agrees with its authored ability def (the class
## ability list is consulted first; this is the
## fallback).
const CLASSLESS := {
	"basic_attack": {"name": "Basic Attack",
		"desc": "Your class's standard attack."},
	"holy_light": {"name": "Holy Light",
		"desc": "Radiant light 10s, heals nearby allies 15% (20s cd)"},
	"xp": {"name": "Experience",
		"desc": "Experience earned from all sources."},
}

signal surface_closed


# ------------------------------------------------------------------
# Pure layout + drawn set (spec 2). All statics.
# ------------------------------------------------------------------

static func sector_angle(class_id: String,
		branch: int) -> float:
	var table: Dictionary = SECTORS.get(class_id, {})
	return float(table.get(branch, 90.0))


static func layout_pos(class_id: String, seed: int,
		branch: int, ring: int, index: int) -> Vector2:
	var w := DeepTree.width(seed, branch, ring)
	var off := (float(index) - float(w - 1) / 2.0) \
		* STEP_DEG
	var ang := deg_to_rad(sector_angle(class_id, branch)
		+ off)
	var r := CORE_R + float(ring) * RING_GAP
	return Vector2(cos(ang), sin(ang)) * r


static func branch_color(branch_key: String) -> Color:
	return BRANCH_COLORS.get(branch_key,
		Color(0.8, 0.8, 0.85))


static func _branch_map(class_id: String) -> Dictionary:
	var out := {}
	for b in DeepTree.branches_for(class_id):
		out[int(b["id"])] = b
	return out


static func _player_bits(player: Variant) -> Dictionary:
	return {
		"class_id": str(player.get("class_id")),
		"seed": int(player.get("tree_seed")),
		"owned": player.get("tree_owned") as Array,
		"lifetime": player.get("tree_lifetime")
			as Dictionary,
		"fcol": player.get("family_collection")
			as Dictionary,
		"level": int(player.get("level")),
	}


## The drawn set (spec 2.2): node entries with
## positions, edges with both endpoints drawn, gates
## for locked branches, headers for every sector.
static func build_entries(player: Variant) -> Dictionary:
	var bits := _player_bits(player)
	var class_id := str(bits["class_id"])
	var seed := int(bits["seed"])
	var owned: Array = bits["owned"]
	var bmap := _branch_map(class_id)
	var nodes: Array = []
	var by_id := {}
	for e in DeepTree.visible_nodes(player):
		var entry: Dictionary = e.duplicate()
		entry["pos"] = layout_pos(class_id, seed,
			int(entry["branch"]), int(entry["ring"]),
			int(entry["index"]))
		nodes.append(entry)
		by_id[int(entry["id"])] = entry
	var edges: Array = []
	for entry in nodes:
		var nid := int(entry["id"])
		for p in DeepTree.parent_of(seed, class_id, nid):
			var pid := int(p)
			if pid == DeepTree.CORE_ID:
				edges.append([DeepTree.CORE_ID, nid,
					owned.has(nid)])
			elif by_id.has(pid):
				edges.append([pid, nid,
					owned.has(nid) and owned.has(pid)])
	var gates: Array = []
	var headers: Array = []
	for bid in bmap:
		var info: Dictionary = bmap[bid]
		var unlocked := DeepTree.branch_unlocked(
			bits["fcol"], class_id, bid, bits["lifetime"],
			int(bits["level"]))
		var deepest := DeepTree.deepest_owned(owned, bid)
		var drawn_deepest := deepest + 2 if unlocked \
			else 0
		if not unlocked:
			gates.append({"branch": bid,
				"key": str(info["key"]),
				"name": str(info["name"]),
				"pos": layout_pos(class_id, seed, bid,
					1, 0)})
			drawn_deepest = 1
		var hang := deg_to_rad(sector_angle(class_id,
			bid))
		var hr := CORE_R + float(drawn_deepest + 1) \
			* RING_GAP
		headers.append({"branch": bid,
			"key": str(info["key"]),
			"name": str(info["name"]),
			"wallet": DeepTree.wallet(player, bid),
			"unlocked": unlocked,
			"pos": Vector2(cos(hang), sin(hang)) * hr})
	return {"nodes": nodes, "edges": edges,
		"gates": gates, "headers": headers,
		"by_id": by_id}


## Fog silhouettes (spec 2.2 / 9.1): rings deepest+3
## and deepest+4 per unlocked branch, positions from
## width() alone. A fog entry carries a position and a
## branch - no id, name, cost, state, or archetype.
static func fog_entries(player: Variant) -> Array:
	var bits := _player_bits(player)
	var class_id := str(bits["class_id"])
	var seed := int(bits["seed"])
	var owned: Array = bits["owned"]
	var out: Array = []
	for b in DeepTree.branches_for(class_id):
		var bid := int(b["id"])
		if not DeepTree.branch_populated(bid):
			continue
		if not DeepTree.branch_unlocked(bits["fcol"],
				class_id, bid, bits["lifetime"],
				int(bits["level"])):
			continue
		var deepest := DeepTree.deepest_owned(owned, bid)
		for ring in [deepest + 3, deepest + 4]:
			for idx in DeepTree.width(seed, bid, ring):
				out.append({
					"pos": layout_pos(class_id, seed,
						bid, ring, idx),
					"branch": bid, "ring": ring})
	return out


# ------------------------------------------------------------------
# Detail builders (spec 5). Pure; every string is
# composed from the node's dict, the ability defs, or
# the aggregate function (design paper 15.2).
# ------------------------------------------------------------------

static func ability_def(abilities: Array,
		target: String) -> Dictionary:
	for a in abilities:
		if str(a.get("id", "")) == target:
			return a
	if CLASSLESS.has(target):
		return CLASSLESS[target]
	return {"name": target.capitalize(), "desc": ""}


static func _fmt_mult(v: float) -> String:
	return "x%.2f" % v


static func _fmt_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.2f" % v


## The before -> after lines (spec 5.1 item 7) for one
## node against an owned set: the aggregate diff over
## the node's affected channels, clamps already inside
## compute_aggregates. For an owned node the pair is
## (owned-without, owned-with) - its contribution; for
## an unowned node (current, with-node).
static func aggregate_diff(seed: int, class_id: String,
		owned: Array, node: Dictionary) -> Array:
	var nid := int(node["id"])
	var is_owned := owned.has(nid)
	var before_set: Array = []
	var after_set: Array = []
	for id in owned:
		if int(id) != nid:
			before_set.append(id)
	after_set = before_set.duplicate()
	after_set.append(nid)
	if not is_owned:
		before_set = owned.duplicate()
		after_set = owned.duplicate()
		after_set.append(nid)
	var before := DeepTree.compute_aggregates(seed,
		class_id, before_set)
	var after := DeepTree.compute_aggregates(seed,
		class_id, after_set)
	var lines: Array = []
	var target := str(node.get("target", ""))
	if str(node.get("archetype", "")) == "stat":
		var channel := str((node.get("params", {}) as
			Dictionary).get("channel", ""))
		var b := float((before["stat_adds"] as
			Dictionary).get(channel, 0.0))
		var a := float((after["stat_adds"] as
			Dictionary).get(channel, 0.0))
		if not is_equal_approx(b, a):
			if channel in ["speed", "atk_spd"]:
				lines.append("%s +%d%% -> +%d%%" % [
					channel.capitalize(),
					int(round(b * 100.0)),
					int(round(a * 100.0))])
			else:
				lines.append("%s +%s -> +%s" % [
					channel.capitalize(), _fmt_num(b),
					_fmt_num(a)])
	elif target != "":
		var bm: Dictionary = (before["skill_mods"] as
			Dictionary).get(target, {})
		var am: Dictionary = (after["skill_mods"] as
			Dictionary).get(target, {})
		var keys := {}
		for k in bm:
			keys[k] = true
		for k in am:
			keys[k] = true
		var sorted_keys := keys.keys()
		sorted_keys.sort()
		var aname := target.capitalize()
		for k in sorted_keys:
			var b := float(bm.get(k, 0.0))
			var a := float(am.get(k, 0.0))
			if is_equal_approx(b, a):
				continue
			if k in ["dmg_mult", "cd_mult"]:
				lines.append("%s %s %s -> %s" % [
					aname, k.trim_suffix("_mult"),
					_fmt_mult(b if b != 0.0 else 1.0),
					_fmt_mult(a if a != 0.0 else 1.0)])
			elif k.ends_with("_pct") or k in [
					"pulse_dmg", "burn_pct",
					"shatter_pct", "brand_amp",
					"step_dmg", "vuln_add",
					"threshold_add"]:
				lines.append("%s %s %d%% -> %d%%" % [
					aname, k, int(round(b * 100.0)),
					int(round(a * 100.0))])
			else:
				lines.append("%s %s +%s -> +%s" % [
					aname, k.trim_suffix("_add"),
					_fmt_num(b), _fmt_num(a)])
	return lines


static func detail_for(player: Variant, node_id: int,
		abilities: Array) -> Dictionary:
	var bits := _player_bits(player)
	var class_id := str(bits["class_id"])
	var seed := int(bits["seed"])
	var owned: Array = bits["owned"]
	var node := DeepTree.node_for(seed, class_id,
		DeepTree.id_branch(node_id),
		DeepTree.id_ring(node_id),
		DeepTree.id_index(node_id))
	if node.is_empty():
		return {}
	var bmap := _branch_map(class_id)
	var bid := int(node["branch"])
	var info: Dictionary = bmap.get(bid, {})
	var state := "locked"
	if owned.has(node_id):
		state = "owned"
	elif DeepTree.prereq_met(seed, class_id, node_id,
			owned):
		state = "purchasable"
	var target := str(node.get("target", ""))
	var adef := ability_def(abilities, target)
	var effect_lines: Array = [str(node["desc"])]
	var params: Dictionary = node.get("params", {})
	if params.has("components"):
		for comp in params["components"]:
			var c: Dictionary = comp
			effect_lines.append("  - %s: %d step(s)" % [
				str(c.get("param", "")),
				int(c.get("steps", 0))])
	var parents: Array = []
	for p in DeepTree.parent_of(seed, class_id, node_id):
		var pid := int(p)
		if pid == DeepTree.CORE_ID:
			parents.append({"name": "Class Core",
				"ring": 0, "owned": true})
		else:
			var pn := DeepTree.node_for(seed, class_id,
				DeepTree.id_branch(pid),
				DeepTree.id_ring(pid),
				DeepTree.id_index(pid))
			parents.append({
				"name": str(pn.get("name", "?")),
				"ring": int(pn.get("ring", 0)),
				"owned": owned.has(pid)})
	var wallet := DeepTree.wallet(player, bid)
	var cost := int(node["cost"])
	var afford := wallet >= cost
	var identity := "%s branch - Ring %d - %s" % [
		str(info.get("name", "")), int(node["ring"]),
		str(node["archetype"]).capitalize()]
	if bool(node.get("capstone", false)):
		identity += " - Capstone (%s)" % str(
			node.get("kind", ""))
	var reason := ""
	if state == "locked":
		reason = "Requires any one of the above - " \
			+ "none owned yet."
	var diff := aggregate_diff(seed, class_id, owned,
		node)
	if diff.is_empty():
		diff = ["No numeric channel changes - its " \
			+ "effect is the authored rule above."]
	return {
		"node_id": node_id, "name": str(node["name"]),
		"state": state, "identity": identity,
		"ability_name": str(adef.get("name", "")),
		"ability_desc": str(adef.get("desc", "")),
		"effect_lines": effect_lines,
		"cost": cost, "wallet": wallet,
		"wallet_after": wallet - cost,
		"branch_name": str(info.get("name", "")),
		"branch_key": str(info.get("key", "")),
		"can_afford": afford,
		"afford_line": "Affordable" if afford else
			"Need %d more insight in %s" % [
				cost - wallet, str(info.get("name", ""))],
		"parents": parents,
		"parents_heading": "Requires any one of:",
		"reason_line": reason,
		"diff_lines": diff,
		"diff_caption": "(clamps applied)",
		"diff_owned": owned.has(node_id),
	}


## Branch detail (spec 5.4): gate clicks and sector
## inspection. The unlock requirement is composed from
## the predicate's own inputs.
static func branch_detail_for(player: Variant,
		branch: int) -> Dictionary:
	var bits := _player_bits(player)
	var class_id := str(bits["class_id"])
	var bmap := _branch_map(class_id)
	var info: Dictionary = bmap.get(branch, {})
	if info.is_empty():
		return {}
	var unlocked := DeepTree.branch_unlocked(
		bits["fcol"], class_id, branch,
		bits["lifetime"], int(bits["level"]))
	var skill_names: Array = []
	for s in info.get("skills", []):
		skill_names.append(str(s).capitalize())
	var req := ""
	if branch == 0:
		req = "Reach level 20 (currently %d)" % int(
			bits["level"])
	elif branch in [8, 9]:
		var best := 0.0
		for bid in [8, 9]:
			var bi: Dictionary = bmap.get(bid, {})
			for sk in bi.get("skills", []):
				best = maxf(best,
					float((bits["lifetime"] as
						Dictionary).get(str(sk), 0.0)))
		req = "Reach 100 lifetime affinity in any " \
			+ "Engineering or Forge skill (best: %d / 100)" \
			% int(best)
	else:
		var fam := str(info.get("family", ""))
		req = "Earn the %s signature - specialize a " \
			% fam.capitalize() \
			+ "%s skill to mastery" % fam
		var fc: Dictionary = (bits["fcol"] as
			Dictionary).get(fam, {})
		if bool(fc.get("signature", false)):
			req += " (signature earned)"
		else:
			req += " (not yet earned)"
	return {"branch": branch,
		"name": str(info.get("name", "")),
		"key": str(info.get("key", "")),
		"skills": skill_names,
		"wallet": DeepTree.wallet(player, branch),
		"unlocked": unlocked,
		"requirement": req,
		"deepest": DeepTree.deepest_owned(
			bits["owned"], branch)}


## Core detail (spec 5.4): the overview.
static func core_detail_for(player: Variant) -> Dictionary:
	var bits := _player_bits(player)
	var class_id := str(bits["class_id"])
	var lines: Array = []
	for b in DeepTree.branches_for(class_id):
		var bid := int(b["id"])
		var d := branch_detail_for(player, bid)
		lines.append({
			"name": str(b["name"]),
			"wallet": int(d["wallet"]),
			"unlocked": bool(d["unlocked"]),
			"requirement": str(d["requirement"]),
			"deepest": int(d["deepest"])})
	return {"class_id": class_id,
		"class_name": class_id.capitalize(),
		"total_owned": (bits["owned"] as Array).size(),
		"branches": lines}


# ------------------------------------------------------------------
# Search + path (spec 6.3) and the pad chooser (6.2).
# ------------------------------------------------------------------

## Search over the DRAWN set only (spec 15.4): node
## name, target ability name, and desc text. Locked
## branches match by branch name to their gate (the
## gate's pseudo-id is -branch).
static func search_matches(built: Dictionary,
		abilities: Array, query: String) -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	if q == "":
		return out
	var nodes: Array = built.get("nodes", [])
	var sorted := nodes.duplicate()
	sorted.sort_custom(func(a: Dictionary,
			b: Dictionary) -> bool:
		if int(a["ring"]) != int(b["ring"]):
			return int(a["ring"]) < int(b["ring"])
		return int(a["id"]) < int(b["id"]))
	for e in sorted:
		var aname := str(ability_def(abilities,
			str(e.get("target", ""))).get("name", ""))
		if str(e["name"]).to_lower().contains(q) \
				or aname.to_lower().contains(q) \
				or str(e["desc"]).to_lower().contains(q):
			out.append(int(e["id"]))
	for g in built.get("gates", []):
		if str(g["name"]).to_lower().contains(q):
			out.append(-int(g["branch"]))
	return out


## The minimum-cost prerequisite chain (spec 6.3):
## over parent_of, OR parents take the cheapest route;
## owned nodes cost 0 and end the recursion. The walk
## stays inside the drawn set (plus the core). Returns
## {} when no route exists inside the band.
static func path_to(player: Variant, target_id: int,
		drawn_ids: Array) -> Dictionary:
	var bits := _player_bits(player)
	var class_id := str(bits["class_id"])
	var seed := int(bits["seed"])
	var owned: Array = bits["owned"]
	if owned.has(target_id):
		return {"cost": 0, "count": 0,
			"chain": [target_id]}
	var allowed := {}
	for id in drawn_ids:
		allowed[int(id)] = true
	allowed[DeepTree.CORE_ID] = true
	if not allowed.has(target_id):
		return {}
	var node_cost := {}
	for id in allowed:
		if id == DeepTree.CORE_ID or owned.has(id):
			node_cost[id] = 0
		else:
			var n := DeepTree.node_for(seed, class_id,
				DeepTree.id_branch(id),
				DeepTree.id_ring(id),
				DeepTree.id_index(id))
			node_cost[id] = int(n.get("cost", 0))
	var dist := {target_id: int(node_cost[target_id])}
	var prev := {}
	var settled := {}
	var frontier := -1
	while true:
		var cur := -1
		var cur_d := -1
		for id in dist:
			if settled.has(id):
				continue
			if cur_d < 0 or int(dist[id]) < cur_d:
				cur = int(id)
				cur_d = int(dist[id])
		if cur < 0:
			break
		settled[cur] = true
		if cur == DeepTree.CORE_ID or owned.has(cur):
			frontier = cur
			break
		for p in DeepTree.parent_of(seed, class_id, cur):
			var pid := int(p)
			if not allowed.has(pid) or settled.has(pid):
				continue
			var nd := cur_d + int(node_cost[pid])
			if not dist.has(pid) or nd < int(dist[pid]):
				dist[pid] = nd
				prev[pid] = cur
	if frontier < 0:
		return {}
	var chain: Array = [frontier]
	var walk := frontier
	while walk != target_id:
		walk = int(prev[walk])
		chain.append(walk)
	var total := 0
	var count := 0
	for id in chain:
		if int(id) != frontier and not owned.has(id):
			total += int(node_cost[id])
			count += 1
	return {"cost": total, "count": count,
		"chain": chain}


## The pad focus-snap chooser (spec 6.2): candidates
## are the focus's parents, children, same-ring
## siblings, and bridge-linked nodes (bridges are
## parents/children in the graph, so they arrive
## through those sets); the winner is the candidate
## whose direction best matches the input direction.
## focusables: [{id, pos, branch, ring}] including the
## core (id 0). parents_map: id -> [parent ids] for
## real nodes. Returns the chosen id or the focus id
## when nothing lies in the input's cone.
static func choose_neighbor(focusables: Array,
		parents_map: Dictionary, focus_id: int,
		dir: Vector2) -> int:
	var by_id := {}
	for f in focusables:
		by_id[int(f["id"])] = f
	if not by_id.has(focus_id) or dir.length() < 0.01:
		return focus_id
	var focus: Dictionary = by_id[focus_id]
	var cand := {}
	for p in parents_map.get(focus_id, []):
		cand[int(p)] = true
	for id in parents_map:
		var ps: Array = parents_map[id]
		if ps.has(focus_id) and by_id.has(int(id)):
			cand[int(id)] = true
	if focus.has("branch"):
		for f in focusables:
			if int(f["id"]) == focus_id:
				continue
			if f.has("branch") \
					and int(f["branch"]) == int(
						focus["branch"]) \
					and int(f["ring"]) == int(
						focus["ring"]):
				cand[int(f["id"])] = true
	if focus_id == DeepTree.CORE_ID:
		for f in focusables:
			cand[int(f["id"])] = true
	var fpos: Vector2 = focus["pos"]
	var best := focus_id
	var best_score := 0.35
	for id in cand:
		if int(id) == focus_id or not by_id.has(int(id)):
			continue
		var delta: Vector2 = by_id[int(id)]["pos"] \
			- fpos
		if delta.length() < 1.0:
			continue
		var score := dir.normalized().dot(
			delta.normalized())
		if score > best_score + 0.0001 \
				or (is_equal_approx(score, best_score)
					and best != focus_id
					and delta.length() < (by_id[best][
						"pos"] as Vector2).distance_to(
							fpos)):
			best = int(id)
			best_score = score
	return best


# ------------------------------------------------------------------
# Instance side: camera, rendering, panel, input.
# ------------------------------------------------------------------

var _player: Variant = null
var _abilities: Array = []
var _bmap: Dictionary = {}
var _built: Dictionary = {}
var _fog: Array = []
var _cam_offset := Vector2.ZERO
var _zoom := 1.0
var _selected := 0 # node id; 0 = core; negative = gate (-branch)
var _focus_id := 0
var _hover_id := -999999
var _in_panel := false
var _cursor_mode := false
var _cursor_pos := Vector2.ZERO
var _dragging := false
var _matches: Array = []
var _match_idx := 0
var _path: Dictionary = {}
var _denial := ""
var _ease_to := {}
var _flick_ready_msec := 0
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _buy_btn: Button
var _search_edit: LineEdit
var _search_lbl: Label

signal panel_focus_entered


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	# Anchors AND offsets: anchors alone, set once the
	# node is parented under the HUD's CanvasLayer,
	# leave the rect at (0, 0) - the offsets preset is
	# what makes the full-rect sizing take.
	set_anchors_preset(PRESET_FULL_RECT)
	set_offsets_preset(PRESET_FULL_RECT)
	_build_chrome()
	visible = false


func _build_chrome() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(PRESET_CENTER_RIGHT)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -356.0
	_panel.offset_right = -8.0
	_panel.offset_top = 8.0
	_panel.offset_bottom = -8.0
	# The game's menu idiom (dark panel, gold edge) as
	# an explicit stylebox - the default theme's panel
	# is transparent over the graph.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.97)
	sb.border_color = Color(0.85, 0.70, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = \
		ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_panel_box = VBoxContainer.new()
	_panel_box.size_flags_horizontal = \
		Control.SIZE_EXPAND_FILL
	_panel_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_panel_box)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(PRESET_TOP_LEFT)
	bar.offset_left = 8.0
	bar.offset_top = 8.0
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search the tree..."
	_search_edit.custom_minimum_size = Vector2(220, 0)
	_search_edit.text_changed.connect(_on_search_changed)
	bar.add_child(_search_edit)
	var prev := Button.new()
	prev.text = "<"
	prev.pressed.connect(_on_match_step.bind(-1))
	bar.add_child(prev)
	var next := Button.new()
	next.text = ">"
	next.pressed.connect(_on_match_step.bind(1))
	bar.add_child(next)
	_search_lbl = Label.new()
	_search_lbl.text = ""
	bar.add_child(_search_lbl)


func open_for(player: Variant, abilities: Array) -> void:
	_player = player
	_abilities = abilities
	_selected = 0
	_focus_id = 0
	_hover_id = -999999
	_in_panel = false
	_cursor_mode = false
	_denial = ""
	_matches = []
	_match_idx = 0
	_search_edit.text = ""
	_search_lbl.text = ""
	visible = true
	rebuild()
	_fit_camera()
	_refresh_panel()
	queue_redraw()


func close_surface() -> void:
	visible = false
	surface_closed.emit()


## Rebuild moment (spec 2.2): recompute the drawn set
## from the player's data. Camera motion never calls
## this.
func rebuild() -> void:
	if _player == null:
		return
	_built = build_entries(_player)
	_bmap = _branch_map(str(_player.get("class_id")))
	_fog = fog_entries(_player)
	_update_path()
	queue_redraw()


func _update_path() -> void:
	_path = {}
	if _selected > 0 and _player != null:
		var ids: Array = []
		for e in _built.get("nodes", []):
			ids.append(int(e["id"]))
		_path = path_to(_player, _selected, ids)


func _w2s(world: Vector2) -> Vector2:
	return (world - _cam_offset) * _zoom + size * 0.5


func _s2w(screen: Vector2) -> Vector2:
	return (screen - size * 0.5) / _zoom + _cam_offset


func _fit_camera() -> void:
	var pts: Array = [Vector2.ZERO]
	for e in _built.get("nodes", []):
		pts.append(e["pos"])
	for g in _built.get("gates", []):
		pts.append(g["pos"])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	_cam_offset = (lo + hi) * 0.5
	var span := (hi - lo) + Vector2(320, 320)
	# The detail panel docks over the right 364 px; fit
	# against the remaining width and shift the center
	# so the band frames left of the panel.
	var usable_x := maxf(size.x - 400.0, 200.0)
	var zx := usable_x / maxf(span.x, 1.0)
	var zy := size.y / maxf(span.y, 1.0)
	_zoom = clampf(minf(zx, zy), ZOOM_MIN, ZOOM_MAX)
	_cam_offset.x += 200.0 / _zoom


func _glyph_radius(entry: Dictionary) -> float:
	match str(entry.get("archetype", "")):
		"stat":
			return GLYPH_STAT
		"behavior":
			return GLYPH_BEHAVIOR
		"capstone":
			return GLYPH_CAPSTONE
		_:
			return GLYPH_MOD


func _entry_pos(id: int) -> Vector2:
	if id == 0:
		return Vector2.ZERO
	if id < 0:
		for g in _built.get("gates", []):
			if int(g["branch"]) == -id:
				return g["pos"]
		return Vector2.ZERO
	var by_id: Dictionary = _built.get("by_id", {})
	if by_id.has(id):
		return by_id[id]["pos"]
	return Vector2.ZERO


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	var font := get_theme_default_font()
	# Sparse pixel dot grid (world-anchored).
	var tl := _s2w(Vector2.ZERO)
	var br := _s2w(size)
	var step := 48.0
	var gx: float = floor(tl.x / step) * step
	while gx <= br.x:
		var gy: float = floor(tl.y / step) * step
		while gy <= br.y:
			var sp := _w2s(Vector2(gx, gy))
			draw_rect(Rect2(sp - Vector2.ONE,
				Vector2(2, 2)), DOT_COLOR)
			gy += step
		gx += step
	# Fog silhouettes (rendering layer only, spec 2.2).
	for f in _fog:
		var sp := _w2s(f["pos"])
		draw_arc(sp, GLYPH_MOD * _zoom, 0, TAU, 24,
			FOG_COLOR, 2.0)
	# Edges under nodes (spec 2.3).
	for e in _built.get("edges", []):
		var child: Dictionary = (_built["by_id"] as
			Dictionary).get(int(e[1]), {})
		var binfo: Dictionary = _bmap.get(
			int(child.get("branch", 0)), {})
		var col := branch_color(str(binfo.get("key", "")))
		var c := col
		c.a = 0.9 if bool(e[2]) else 0.30
		draw_line(_w2s(_entry_pos(int(e[0]))),
			_w2s(_entry_pos(int(e[1]))), c, 2.0)
	# Path highlight (spec 6.3).
	var chain: Array = _path.get("chain", [])
	if chain.size() > 1:
		for i in chain.size() - 1:
			draw_line(_w2s(_entry_pos(int(chain[i]))),
				_w2s(_entry_pos(int(chain[i + 1]))),
				Color(1.0, 0.9, 0.4, 0.85), 3.0)
	# Branch headers (spec 4.3).
	for h in _built.get("headers", []):
		var sp := _w2s(h["pos"])
		var col := branch_color(str(h["key"]))
		draw_string(font, sp + Vector2(0, -6),
			str(h["name"]), HORIZONTAL_ALIGNMENT_CENTER,
			-1, 16, col)
		draw_string(font, sp + Vector2(0, 14),
			"wallet %d" % int(h["wallet"]),
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12,
			Color(0.85, 0.85, 0.9))
	# Gates (spec 4.3).
	for g in _built.get("gates", []):
		_draw_gate(g)
	# Nodes.
	for e in _built.get("nodes", []):
		_draw_node(e, font)
	# Core (spec 4.3).
	_draw_core(font)
	# Search markers.
	for m in _matches:
		var mid := int(m)
		if mid > 0:
			var sp2 := _w2s(_entry_pos(mid))
			draw_arc(sp2, (GLYPH_CAPSTONE + 7.0) * _zoom,
				0, TAU, 32, Color(1.0, 0.85, 0.3), 2.0)
	# Pad cursor (free-cursor mode).
	if _cursor_mode:
		draw_circle(_cursor_pos, 5.0,
			Color(1, 1, 1, 0.9))
		draw_arc(_cursor_pos, 10.0, 0, TAU, 24,
			Color(1, 1, 1, 0.6), 1.5)


func _draw_core(font: Font) -> void:
	var sp := _w2s(Vector2.ZERO)
	var r := GLYPH_CORE * _zoom
	draw_circle(sp, r, Color(0.10, 0.11, 0.18))
	draw_arc(sp, r, 0, TAU, 40, Color(0.95, 0.85, 0.45),
		3.0)
	draw_arc(sp, r * 0.68, 0, TAU, 32,
		Color(0.95, 0.85, 0.45), 2.0)
	if _selected == 0:
		draw_arc(sp, r + 5.0, 0, TAU, 40, Color.WHITE,
			2.0)
	if _focus_id == 0 and _pad_active():
		draw_arc(sp, r + 10.0, 0, TAU, 40,
			Color(1, 1, 1, 0.5), 2.0)
	var cname := str(_player.get("class_id")
		).capitalize() if _player != null else ""
	draw_string(font, sp + Vector2(0, r + 16), cname,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 13,
		Color(0.95, 0.9, 0.7))


func _draw_gate(g: Dictionary) -> void:
	var sp := _w2s(g["pos"])
	var r := GLYPH_GATE * _zoom
	draw_circle(sp, r, LOCKED_FILL)
	draw_arc(sp, r, 0, TAU, 32, LOCKED_RING, 3.0)
	# Lock mark: body + shackle.
	draw_rect(Rect2(sp + Vector2(-7, -1) * _zoom,
		Vector2(14, 11) * _zoom), LOCKED_RING)
	draw_arc(sp + Vector2(0, -2) * _zoom, 5.0 * _zoom,
		PI, TAU, 12, LOCKED_RING, 2.0)
	if _selected == -int(g["branch"]):
		draw_arc(sp, r + 5.0, 0, TAU, 32, Color.WHITE,
			2.0)


func _draw_node(e: Dictionary, font: Font) -> void:
	var sp := _w2s(e["pos"])
	var binfo: Dictionary = _bmap.get(
			int(e["branch"]), {})
	var col := branch_color(str(binfo.get("key", "")))
	var state := str(e["state"])
	var r := _glyph_radius(e) * _zoom
	var fill := DARK_FILL
	var ring := col
	if state == "owned":
		fill = col
		ring = col.darkened(0.35)
	elif state == "locked":
		fill = LOCKED_FILL
		ring = LOCKED_RING
	var arch := str(e["archetype"])
	if arch == "behavior":
		var pts := PackedVector2Array([
			sp + Vector2(0, -r), sp + Vector2(r, 0),
			sp + Vector2(0, r), sp + Vector2(-r, 0)])
		draw_polygon(pts, PackedColorArray([fill]))
		draw_polyline(PackedVector2Array([pts[0], pts[1],
			pts[2], pts[3], pts[0]]), ring, 2.0)
	else:
		draw_circle(sp, r, fill)
		draw_arc(sp, r, 0, TAU, 28, ring, 2.0)
		if arch == "capstone":
			draw_arc(sp, r * 0.66, 0, TAU, 24, ring, 2.0)
			if str(e.get("kind", "")) == "variant":
				_draw_star(sp + Vector2(0, -r),
					4.5 * _zoom, ring)
		elif arch == "stat":
			var s := r * 0.5
			draw_line(sp + Vector2(-s, 0),
				sp + Vector2(s, 0), ring, 2.0)
			draw_line(sp + Vector2(0, -s),
				sp + Vector2(0, s), ring, 2.0)
	if int(e["id"]) == _selected:
		draw_arc(sp, r + 5.0, 0, TAU, 28, Color.WHITE,
			2.0)
	if int(e["id"]) == _hover_id:
		draw_arc(sp, r + 9.0, 0, TAU, 28,
			Color(1, 1, 1, 0.45), 1.5)
	if int(e["id"]) == _focus_id and _pad_active():
		draw_arc(sp, r + 9.0, 0, TAU, 28,
			Color(1, 1, 1, 0.5), 2.0)
	# Labels (tiered, spec 9.4).
	var show_name := false
	var show_cost := false
	if _zoom >= ZOOM_LABELS_ALL:
		show_name = true
		show_cost = true
	elif _zoom >= ZOOM_LABELS_FRONTIER:
		show_name = state != "locked" \
			or int(e["id"]) == _selected
	if show_name:
		draw_string(font, sp + Vector2(0, r + 13),
			str(e["name"]), HORIZONTAL_ALIGNMENT_CENTER,
			-1, 11, Color(0.88, 0.88, 0.92))
	if show_cost:
		draw_string(font, sp + Vector2(0, r + 25),
			"%d" % int(e["cost"]),
			HORIZONTAL_ALIGNMENT_CENTER, -1, 10,
			Color(0.65, 0.68, 0.78))


func _draw_star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var ang := -PI * 0.5 + float(i) * PI * 0.25
		var rad := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	draw_polygon(pts, PackedColorArray([col]))


func _pad_active() -> bool:
	return _focus_id != _hover_id or _in_panel


# ------------------------------------------------------------------
# Detail panel (spec 5): renders the pure builders'
# output verbatim.
# ------------------------------------------------------------------

func _lbl(text: String, col := Color(0.88, 0.88, 0.92),
		size := 13, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _hdr(text: String) -> Label:
	return _lbl(text, Color(1.0, 0.85, 0.40), 14, false)


func _refresh_panel() -> void:
	for c in _panel_box.get_children():
		c.queue_free()
	_buy_btn = null
	if _selected > 0:
		_panel_node()
	elif _selected < 0:
		_panel_branch(-_selected)
	else:
		_panel_core()
	var hint := _lbl("Drag to pan - wheel zooms - " \
		+ "click a node. Esc closes.",
		Color(0.55, 0.58, 0.68), 11)
	_panel_box.add_child(hint)


func _panel_node() -> void:
	var d := detail_for(_player, _selected, _abilities)
	if d.is_empty():
		return
	_panel_box.add_child(_hdr(str(d["name"])))
	_panel_box.add_child(_lbl(str(d["identity"]),
		Color(0.65, 0.68, 0.78), 12))
	_panel_box.add_child(_lbl("State: %s" % str(
		d["state"]).capitalize()))
	if str(d["reason_line"]) != "":
		_panel_box.add_child(_lbl(str(d["reason_line"]),
			Color(0.95, 0.70, 0.45)))
	_panel_box.add_child(_hdr("Ability - %s" % str(
		d["ability_name"])))
	_panel_box.add_child(_lbl(str(d["ability_desc"])))
	_panel_box.add_child(_hdr("This node"))
	for line in d["effect_lines"]:
		_panel_box.add_child(_lbl(str(line)))
	_panel_box.add_child(_hdr("Cost"))
	_panel_box.add_child(_lbl(
		"%d insight (%s) - wallet %d -> %d" % [
			int(d["cost"]), str(d["branch_name"]),
			int(d["wallet"]), int(d["wallet_after"])]))
	_panel_box.add_child(_lbl(str(d["afford_line"]),
		Color(0.55, 0.9, 0.55) if bool(d["can_afford"])
			else Color(0.95, 0.60, 0.45)))
	_panel_box.add_child(_hdr(str(d["parents_heading"])))
	for p in d["parents"]:
		_panel_box.add_child(_lbl("%s - Ring %d %s" % [
			str(p["name"]), int(p["ring"]),
			"[owned]" if bool(p["owned"])
				else "[unmet]"]))
	_panel_box.add_child(_hdr("Before -> after %s" % str(
		d["diff_caption"])))
	if bool(d["diff_owned"]):
		_panel_box.add_child(_lbl(
			"(this node's contribution)",
			Color(0.65, 0.68, 0.78), 11))
	for line in d["diff_lines"]:
		_panel_box.add_child(_lbl(str(line)))
	if not _path.is_empty() and int(_path["count"]) > 0:
		_panel_box.add_child(_lbl(
			"Path cost: %d insight across %d nodes" % [
				int(_path["cost"]), int(_path["count"])],
			Color(1.0, 0.9, 0.45)))
	if str(d["state"]) == "purchasable":
		_buy_btn = Button.new()
		_buy_btn.text = "Buy (%d insight)" % int(d["cost"])
		_buy_btn.disabled = not bool(d["can_afford"])
		_buy_btn.pressed.connect(_on_buy_pressed)
		_panel_box.add_child(_buy_btn)
	if _denial != "":
		_panel_box.add_child(_lbl(_denial,
			Color(0.95, 0.45, 0.40)))


func _panel_branch(branch: int) -> void:
	var d := branch_detail_for(_player, branch)
	if d.is_empty():
		return
	_panel_box.add_child(_hdr(str(d["name"])))
	_panel_box.add_child(_lbl(
		"Branch - %s" % ("unlocked" if bool(
			d["unlocked"]) else "locked")))
	var skills: Array = d["skills"]
	_panel_box.add_child(_lbl("Skills: %s" % ", ".join(
		skills) if not skills.is_empty() else
		"Skills: (classless)"))
	_panel_box.add_child(_lbl("Wallet: %d insight" % int(
		d["wallet"])))
	_panel_box.add_child(_lbl(
		"Deepest owned ring: %d" % int(d["deepest"])))
	_panel_box.add_child(_hdr("Unlock requirement"))
	_panel_box.add_child(_lbl(str(d["requirement"])))


func _panel_core() -> void:
	var d := core_detail_for(_player)
	if d.is_empty():
		return
	_panel_box.add_child(_hdr("%s - Deep Tree" % str(
		d["class_name"])))
	_panel_box.add_child(_lbl("Nodes owned: %d" % int(
		d["total_owned"])))
	for b in d["branches"]:
		_panel_box.add_child(_lbl(
			"%s - wallet %d - %s - deepest ring %d" % [
				str(b["name"]), int(b["wallet"]),
				"unlocked" if bool(b["unlocked"])
					else "locked",
				int(b["deepest"])]))
		_panel_box.add_child(_lbl("  %s" % str(
			b["requirement"]), Color(0.65, 0.68, 0.78),
			12))


func _select(id: int) -> void:
	_selected = id
	_focus_id = id
	_denial = ""
	_update_path()
	_refresh_panel()
	queue_redraw()


func _on_buy_pressed() -> void:
	if _player == null or _selected <= 0:
		return
	_player.call("try_purchase", _selected)
	# Purchase resolution (spec 2.2): the sync lands
	# through the claim path; rebuild + refresh in
	# place. Buying never closes the panel.
	rebuild()
	_refresh_panel()


## The denial receiver (spec 5.3): hud forwards the
## player's tree_purchase_denied here. The reason shows
## verbatim.
func show_denial(node_id: int, reason: String) -> void:
	_denial = reason
	if node_id == _selected or _selected > 0:
		_refresh_panel()
	rebuild()


func panel_root() -> Control:
	return _panel


func panel_primary() -> Control:
	return _buy_btn


# ------------------------------------------------------------------
# Search (spec 6.3).
# ------------------------------------------------------------------

func _on_search_changed(text: String) -> void:
	_matches = search_matches(_built, _abilities, text)
	_match_idx = 0
	if _matches.is_empty():
		_search_lbl.text = "0" if text.strip_edges() \
			!= "" else ""
	else:
		_search_lbl.text = "%d" % _matches.size()
		_fly_to(int(_matches[0]))
	queue_redraw()


func _on_match_step(dir: int) -> void:
	if _matches.is_empty():
		return
	_match_idx = (_match_idx + dir) % _matches.size()
	_fly_to(int(_matches[_match_idx]))


func _fly_to(id: int) -> void:
	_select(id)
	_ease_to = {"cam": _entry_pos(id), "zoom": _zoom}
	set_process(true)


# ------------------------------------------------------------------
# Input (spec 6): mouse, keyboard, pad.
# ------------------------------------------------------------------

func _hit_at(screen: Vector2) -> int:
	var world := _s2w(screen)
	var best := -999999
	var best_d := INF
	var by_id: Dictionary = _built.get("by_id", {})
	for id in by_id:
		var e: Dictionary = by_id[id]
		var d := world.distance_to(e["pos"])
		if d <= _glyph_radius(e) + 6.0 and d < best_d:
			best_d = d
			best = int(id)
	if world.distance_to(Vector2.ZERO) <= GLYPH_CORE \
			+ 6.0:
		if world.distance_to(Vector2.ZERO) < best_d:
			best = 0
	for g in _built.get("gates", []):
		var d := world.distance_to(g["pos"])
		if d <= GLYPH_GATE + 6.0 and d < best_d:
			best_d = d
			best = -int(g["branch"])
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP \
				and mb.pressed:
			_zoom_at(mb.position, 1.12)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN \
				and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.12)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var hit := _hit_at(mb.position)
				if hit != -999999:
					_select(hit)
				else:
					_dragging = true
				accept_event()
			else:
				if _dragging:
					_dragging = false
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_cam_offset -= mm.relative / _zoom
			queue_redraw()
		else:
			var hit := _hit_at(mm.position)
			if hit != _hover_id:
				_hover_id = hit
				queue_redraw()


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := _s2w(screen)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var after := _s2w(screen)
	_cam_offset += before - after
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if _search_edit.has_focus():
			return
		match k.keycode:
			KEY_ESCAPE:
				close_surface()
			KEY_LEFT, KEY_A:
				_cam_offset.x -= 60.0 / _zoom
				queue_redraw()
			KEY_RIGHT, KEY_D:
				_cam_offset.x += 60.0 / _zoom
				queue_redraw()
			KEY_UP, KEY_W:
				_cam_offset.y -= 60.0 / _zoom
				queue_redraw()
			KEY_DOWN, KEY_S:
				_cam_offset.y += 60.0 / _zoom
				queue_redraw()
			KEY_EQUAL, KEY_KP_ADD:
				_zoom = clampf(_zoom * 1.15, ZOOM_MIN,
					ZOOM_MAX)
				queue_redraw()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom = clampf(_zoom / 1.15, ZOOM_MIN,
					ZOOM_MAX)
				queue_redraw()
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		match jb.button_index:
			JOY_BUTTON_DPAD_UP:
				_pad_move(Vector2.UP)
			JOY_BUTTON_DPAD_DOWN:
				_pad_move(Vector2.DOWN)
			JOY_BUTTON_DPAD_LEFT:
				_pad_move(Vector2.LEFT)
			JOY_BUTTON_DPAD_RIGHT:
				_pad_move(Vector2.RIGHT)
			JOY_BUTTON_A:
				if not _in_panel:
					_select(_focus_id)
			JOY_BUTTON_B:
				if _in_panel:
					_in_panel = false
				else:
					close_surface()
			JOY_BUTTON_LEFT_SHOULDER, \
					JOY_BUTTON_RIGHT_SHOULDER:
				_in_panel = not _in_panel
				if _in_panel:
					panel_focus_entered.emit()
			JOY_BUTTON_RIGHT_STICK:
				_cursor_mode = not _cursor_mode
				if _cursor_mode:
					_cursor_pos = size * 0.5
				set_process(true)
				queue_redraw()
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		# LT / RT are axes in Godot 4: zoom in both pad
		# modes (spec 6.2), on a shared flick cooldown.
		if jm.axis in [JOY_AXIS_TRIGGER_LEFT,
				JOY_AXIS_TRIGGER_RIGHT] \
				and jm.axis_value > 0.5 \
				and Time.get_ticks_msec() \
					>= _flick_ready_msec:
			_flick_ready_msec = Time.get_ticks_msec() \
				+ 220
			if jm.axis == JOY_AXIS_TRIGGER_LEFT:
				_zoom = clampf(_zoom / 1.2, ZOOM_MIN,
					ZOOM_MAX)
			else:
				_zoom = clampf(_zoom * 1.2, ZOOM_MIN,
					ZOOM_MAX)
			queue_redraw()
			return
		if _cursor_mode:
			return
		if jm.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] \
				and absf(jm.axis_value) > 0.75 \
				and Time.get_ticks_msec() \
					>= _flick_ready_msec:
			_flick_ready_msec = Time.get_ticks_msec() \
				+ 280
			var dir := Vector2(
				Input.get_axis("ui_left", "ui_right"),
				Input.get_axis("ui_up", "ui_down"))
			if dir.length() > 0.3:
				_pad_move(dir)


func _pad_move(dir: Vector2) -> void:
	if _in_panel:
		return
	var focusables: Array = []
	var parents_map := {}
	var by_id: Dictionary = _built.get("by_id", {})
	for id in by_id:
		var e: Dictionary = by_id[id]
		focusables.append({"id": int(id), "pos": e["pos"],
			"branch": int(e["branch"]),
			"ring": int(e["ring"])})
		var ps: Array = []
		for p in DeepTree.parent_of(int(_player.get(
				"tree_seed")), str(_player.get(
				"class_id")), int(id)):
			ps.append(int(p))
		parents_map[int(id)] = ps
	focusables.append({"id": 0, "pos": Vector2.ZERO})
	for g in _built.get("gates", []):
		focusables.append({"id": -int(g["branch"]),
			"pos": g["pos"]})
	var next := choose_neighbor(focusables, parents_map,
		_focus_id, dir)
	if next != _focus_id:
		_focus_id = next
		_selected = next
		_update_path()
		_refresh_panel()
		_ease_focus_into_box()
		queue_redraw()


func _ease_focus_into_box() -> void:
	var sp := _w2s(_entry_pos(_focus_id))
	var box := Rect2(size * 0.2, size * 0.6)
	if not box.has_point(sp):
		_ease_to = {"cam": _entry_pos(_focus_id),
			"zoom": _zoom}
		set_process(true)


func _process(delta: float) -> void:
	var busy := false
	if not _ease_to.is_empty():
		busy = true
		var target: Vector2 = _ease_to["cam"]
		_cam_offset = _cam_offset.lerp(target,
			1.0 - pow(0.0005, delta))
		_zoom = lerpf(_zoom, float(_ease_to["zoom"]),
			1.0 - pow(0.0005, delta))
		if _cam_offset.distance_to(target) < 1.0:
			_ease_to = {}
		queue_redraw()
	if _cursor_mode and visible:
		busy = true
		var stick := Vector2(Input.get_axis(
			"look_left", "look_right"), Input.get_axis(
			"look_up", "look_down"))
		if stick.length() > 0.15:
			_cursor_pos += stick * 620.0 * delta
			_cursor_pos = _cursor_pos.clamp(
				Vector2.ZERO, size)
			var hit := _hit_at(_cursor_pos)
			if hit != _hover_id:
				_hover_id = hit
			queue_redraw()
	if not busy:
		set_process(false)
