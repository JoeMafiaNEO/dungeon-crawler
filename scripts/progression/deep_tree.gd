class_name DeepTree
extends RefCounted

## The Deep Tree (issue #206, prototype slice: mage + Fire) —
## an infinite procedural skill tree as a pure function of
## (seed, class). Generation is function-not-data: every node
## is regenerated from integer-hash streams on demand, which
## is what lets the server validate purchases BY
## REGENERATION (spec section 4) and every peer derive the
## same looks with zero cosmetic payload (section 6).
##
## Discipline (spec section 2): NO autoloads named here, no
## RNG state, no float hashing. All generation arithmetic is
## integer; floats appear only when aggregates are applied.
## Every magnitude/cost number is a PLACEHOLDER — Jesse's
## tuning calls; the structures and formulas are the spec.
##
## GDScript int64 notes (verified bit-exact against a
## reference splitmix64): hex literals above INT64_MAX are
## CLAMPED by the parser, so the 64-bit constants below are
## written as signed decimals; and >> on negative ints is
## arithmetic, so the finalizer masks after each shift to
## emulate the logical shifts splitmix specifies.

## PLACEHOLDER universal seed (fork 1: one tree for
## everyone). Jesse picks the real value before this branch
## ships; each save stores its seed, stored-seed wins.
const TREE_SEED := 20261025

# Hash stream ids (spec section 2.2).
const S_WIDTH := 1
const S_ARCHETYPE := 2
const S_TARGET := 3
const S_PARAM := 4
const S_MAGNITUDE := 5
const S_NAME_A := 6
const S_NAME_N := 7
const S_LOOK := 8
const S_GRAMMAR := 9
const S_CAPSTONE_KIND := 10
const S_COMPOSE := 11

# splitmix64 constants, signed-decimal form (see header).
const MIX_A := -7046029254386353131 # 0x9E3779B97F4A7C15
const MIX_B := -4658895280553007687 # 0xBF58476D1CE4E5B9
const MIX_C := -7723592293110705685 # 0x94D049BB133111EB

## The one populated branch in the prototype (registry id).
const BRANCH_FIRE := 1

## Packed node id: (branch << 40) | (ring << 4) | index.
## Id 0 is the CORE sentinel (no real node has ring 0).
const CORE_ID := 0


static func _h(seed: int, stream: int, a: int, b: int,
		c: int) -> int:
	var x := seed ^ (stream * MIX_A) ^ (a * MIX_B) \
		^ (b * MIX_C) ^ c
	x ^= (x >> 30) & 0x3FFFFFFFF
	x *= MIX_B
	x ^= (x >> 27) & 0x1FFFFFFFFF
	x *= MIX_C
	x ^= (x >> 31) & 0x1FFFFFFFF
	return x


static func roll(seed: int, stream: int, a: int, b: int,
		c: int, n: int) -> int:
	if n <= 1:
		return 0
	return posmod(_h(seed, stream, a, b, c), n)


static func pack_id(branch: int, ring: int, index: int) -> int:
	return (branch << 40) | (ring << 4) | index


static func id_branch(id: int) -> int:
	return id >> 40


static func id_ring(id: int) -> int:
	return (id >> 4) & 0xFFFFFFFFF


static func id_index(id: int) -> int:
	return id & 15


# ----------------------------------------------------------------
# Branch registry (spec section 2.3 — append-only; ids are
# save data, never renumber). skills = wallet skills;
# targets = wallet skills + the signature (target-only).
# ----------------------------------------------------------------

static func branches_for(class_id: String) -> Array:
	var all := {
		0: {"id": 0, "key": "wayfaring", "name": "Wayfaring",
			"skills": [], "targets": [], "family": ""},
		1: {"id": 1, "key": "fire", "name": "Fire",
			"skills": ["fireball", "meteor"],
			"targets": ["fireball", "meteor", "inferno"],
			"family": "fire"},
		2: {"id": 2, "key": "frost", "name": "Frost",
			"skills": ["frost", "blizzard"],
			"targets": ["frost", "blizzard", "glacial_prison"],
			"family": "frost"},
		3: {"id": 3, "key": "storm", "name": "Storm",
			"skills": ["lightning", "barrage"],
			"targets": ["lightning", "barrage", "tempest"],
			"family": "storm"},
		4: {"id": 4, "key": "warden", "name": "Warden",
			"skills": ["reciprocity", "stoneskin"],
			"targets": ["reciprocity", "stoneskin",
				"sanctuary_totem"], "family": "warden"},
		5: {"id": 5, "key": "conqueror", "name": "Conqueror",
			"skills": ["bulwark", "warhorn", "rally"],
			"targets": ["bulwark", "warhorn", "rally",
				"doom_totem"], "family": "conqueror"},
		6: {"id": 6, "key": "shadow", "name": "Shadow",
			"skills": ["smoke_veil", "shadow_step"],
			"targets": ["smoke_veil", "shadow_step",
				"assassinate"], "family": "shadow"},
		7: {"id": 7, "key": "precision", "name": "Precision",
			"skills": ["eagle_eye", "mark", "fan"],
			"targets": ["eagle_eye", "mark", "fan",
				"execution"], "family": "precision"},
		8: {"id": 8, "key": "engineering", "name": "Engineering",
			"skills": ["sentry_turret", "bulwark_wall",
				"spike_trap", "keystone"],
			"targets": ["sentry_turret", "bulwark_wall",
				"spike_trap", "keystone"], "family": ""},
		9: {"id": 9, "key": "forge", "name": "Forge",
			"skills": ["hammer_smash", "reinforce", "demolish"],
			"targets": ["hammer_smash", "reinforce",
				"demolish"], "family": ""},
	}
	var ids: Array = [0]
	match class_id:
		"mage":
			ids = [0, 1, 2, 3]
		"warrior":
			ids = [0, 4, 5]
		"rogue":
			ids = [0, 6, 7]
		"architect":
			ids = [0, 8, 9]
	var out: Array = []
	for i in ids:
		out.append(all[i])
	return out


static func branch_info(class_id: String, branch: int) -> Dictionary:
	for b in branches_for(class_id):
		if int(b["id"]) == branch:
			return b
	return {}


## Only Fire generates purchasable content in the prototype.
static func branch_populated(branch: int) -> bool:
	return branch == BRANCH_FIRE


# ----------------------------------------------------------------
# Graph shape (spec section 2.4)
# ----------------------------------------------------------------

static func width(seed: int, branch: int, ring: int) -> int:
	return 1 + roll(seed, S_WIDTH, branch, ring, 0, 3)


static func parent_of(seed: int, class_id: String, id: int) -> Array:
	var b := id_branch(id)
	var r := id_ring(id)
	var i := id_index(id)
	if r < 1:
		return []
	var out: Array = []
	if i == 0:
		if r == 1:
			out.append(CORE_ID)
		else:
			out.append(pack_id(b, r - 1, 0))
		if r % 8 == 0:
			# Bridges: cyclically adjacent branches' spines
			# are mutual parents at this ring.
			var order := branches_for(class_id)
			var pos := -1
			for k in order.size():
				if int(order[k]["id"]) == b:
					pos = k
			if pos >= 0 and order.size() > 1:
				var prev_b := int(order[(pos - 1
					+ order.size()) % order.size()]["id"])
				var next_b := int(order[(pos + 1)
					% order.size()]["id"])
				out.append(pack_id(prev_b, r, 0))
				out.append(pack_id(next_b, r, 0))
	elif i % 2 == 1:
		out.append(pack_id(b, r, 0))
	else:
		out.append(pack_id(b, r - 1, 0))
	return out


static func children_of(seed: int, class_id: String, id: int) -> Array:
	var out: Array = []
	var r := id_ring(id)
	var order := branches_for(class_id)
	for cand_b in order:
		var cb := int(cand_b["id"])
		for cr in [r, r + 1]:
			if cr < 1:
				continue
			for ci in width(seed, cb, cr):
				var cand := pack_id(cb, cr, ci)
				if parent_of(seed, class_id, cand).has(id):
					out.append(cand)
	return out


## Deepest owned ring in a branch (0 = none / core only).
static func deepest_owned(owned: Array, branch: int) -> int:
	var d := 0
	for id in owned:
		if id_branch(int(id)) == branch:
			d = maxi(d, id_ring(int(id)))
	return d


## A node is purchasable when any parent is owned; the core
## parent is satisfied by the branch being unlocked.
static func prereq_met(seed: int, class_id: String, id: int,
		owned: Array) -> bool:
	for p in parent_of(seed, class_id, id):
		if int(p) == CORE_ID or owned.has(int(p)):
			return true
	return false


# ----------------------------------------------------------------
# Fire tables (spec section 2.5). Authored vocabulary — the
# generator chooses and scales, never invents.
# ----------------------------------------------------------------

const STAT_CHANNELS := ["damage", "health", "speed",
	"atk_spd", "aura"]
## Quantized unit per stat step (placeholder magnitudes).
const STAT_UNIT := {"damage": 1.0, "health": 8.0,
	"speed": 0.10, "atk_spd": 0.5, "aura": 1.0}
const STAT_BASE := {"damage": 2, "health": 2, "speed": 1,
	"atk_spd": 2, "aura": 1}

## Modifier parameters per target — ONLY parameters with
## real hooks. Basic mage spells ride the shared swing
## timer and have no per-ability cooldown, so no cd_pct
## exists for fireball/meteor (the table says so rather
## than inventing one — spec section 2.5).
const PARAM_TABLE := {
	"fireball": ["dmg_pct", "radius_add"],
	"meteor": ["dmg_pct", "radius_add"],
	"inferno": ["dmg_pct", "cd_pct", "radius_add"],
}
const PARAM_UNIT := {"dmg_pct": 0.5, "cd_pct": 0.5,
	"radius_add": 0.1}
const PARAM_BASE := {"dmg_pct": 4, "cd_pct": 4,
	"radius_add": 2}
const PARAM_SPAN := {"dmg_pct": 5, "cd_pct": 5,
	"radius_add": 3}

const BEHAVIORS := ["emberheart", "fuel_for_the_flame"]
const BEHAVIOR_UNIT := 5.0 # percent per step

const VARIANTS := {
	"twin_suns": {"skill": "fireball",
		"desc": "Twin Suns: Fireball casts two bolts at 65% damage each."},
	"meteor_shower": {"skill": "meteor",
		"desc": "Meteor Shower: Meteor falls as three meteors at 45% in a triangle."},
	"phoenix_pyre": {"skill": "inferno",
		"desc": "Phoenix Pyre: Inferno's tick also heals allies in its radius."},
}
const VARIANT_IDS := ["twin_suns", "meteor_shower",
	"phoenix_pyre"]

const ECHO_FAMILIES := ["frost", "storm"]
const FAMILY_SKILLS := {"frost": ["frost", "blizzard"],
	"storm": ["lightning", "barrage"]}

const NAME_ADJ := ["Kindled", "Ashen", "Ember", "Scorched",
	"Wildfire", "Blazing", "Smoldering", "Cinder",
	"Pyre", "Furnace", "Ignited", "Charred"]
const NAME_NOUN := ["Heart", "Crown", "Conflagration",
	"Brand", "Tongue", "Mantle", "Gaze", "Pact", "Wick",
	"Throne", "Veil", "Oath"]

const COST_BASE := {"stat": 10, "modifier": 16,
	"behavior": 24, "capstone": 60}


static func _floor_log2(n: int) -> int:
	var v := 0
	var p := 1
	while p * 2 <= n:
		p *= 2
		v += 1
	return v


## Ring magnitude bonus percent: 5 x floor(log2(1 + r)),
## integer loop only (spec section 2.6).
static func ring_bonus_pct(ring: int) -> int:
	return 5 * _floor_log2(1 + ring)


static func cost_for(archetype: String, ring: int) -> int:
	var c := int(COST_BASE[archetype])
	for k in range(2, ring + 1):
		c = (c * 61 + 25) / 50
	return c


## Steps for one modifier component (or a stat channel),
## with the ring scale and the caller's archetype scale
## applied in integer math (spec section 2.6).
static func _steps(seed: int, branch: int, ring: int,
		index: int, sub: int, base: int, span: int,
		scale_num: int, scale_den: int) -> int:
	var steps := base + roll(seed, S_MAGNITUDE, branch, ring,
		index * 64 + sub, span)
	steps = steps * (100 + ring_bonus_pct(ring)) / 100
	steps = steps * scale_num / scale_den
	return maxi(1, steps)


static func _band(ring: int) -> Array:
	# [stat_cut, modifier_cut] over a 0..99 roll.
	if ring <= 4:
		return [35, 90]
	if ring <= 11:
		return [25, 80]
	return [20, 70]


static func _archetype(seed: int, branch: int, ring: int,
		index: int) -> String:
	var band := _band(ring)
	var v := roll(seed, S_ARCHETYPE, branch, ring, index, 100)
	if v < band[0]:
		return "stat"
	if v < band[1]:
		return "modifier"
	return "behavior"


static func _components(seed: int, branch: int, ring: int,
		index: int, target: String, scale_num: int,
		scale_den: int, force_single: bool) -> Array:
	var table: Array = PARAM_TABLE[target]
	var count := 1
	if not force_single and ring >= 3 \
			and roll(seed, S_COMPOSE, branch, ring, index,
				100) < 35:
		count = 2
		if ring >= 9 and roll(seed, S_COMPOSE, branch, ring,
				index + 512, 100) < 15:
			count = 3
	var out: Array = []
	for k in count:
		var param := str(table[roll(seed, S_PARAM, branch,
			ring, index * 64 + k, table.size())])
		# Composed components take the x0.65 tax (spec 2.5).
		var cn := scale_num
		var cd := scale_den
		if count > 1:
			cn = cn * 65
			cd = cd * 100
		out.append({"param": param,
			"steps": _steps(seed, branch, ring, index, k,
				int(PARAM_BASE[param]),
				int(PARAM_SPAN[param]), cn, cd)})
	return out



## Quantized values print without float noise (GDScript's
## % operator has no %g; an unsupported specifier makes the
## whole format return unsubstituted).
static func _fmt_num(v: float) -> String:
	if v == floorf(v):
		return str(int(v))
	return "%.1f" % v


static func _fmt_pct(steps: int, param: String) -> String:
	var v := float(steps) * float(PARAM_UNIT[param])
	return _fmt_num(v) + "%"


static func _mod_desc(target: String, comps: Array) -> String:
	var parts: Array = []
	for c in comps:
		var param := str(c["param"])
		var steps := int(c["steps"])
		if param == "dmg_pct":
			parts.append("+%s %s damage" % [_fmt_pct(steps,
				param), target])
		elif param == "cd_pct":
			parts.append("-%s %s cooldown" % [_fmt_pct(steps,
				param), target])
		else:
			parts.append("+%s m %s blast radius" % [
				_fmt_num(float(steps)
					* float(PARAM_UNIT[param])), target])
	return "; ".join(parts)


static func _name_for(seed: int, branch: int, ring: int,
		index: int, composed: bool) -> String:
	var adj := str(NAME_ADJ[roll(seed, S_NAME_A, branch, ring,
		index * 2, NAME_ADJ.size())])
	if composed:
		adj += " " + str(NAME_ADJ[roll(seed, S_NAME_A, branch,
			ring, index * 2 + 1, NAME_ADJ.size())])
	return adj + " " + str(NAME_NOUN[roll(seed, S_NAME_N,
		branch, ring, index * 2, NAME_NOUN.size())])


# ----------------------------------------------------------------
# The generation function (spec section 2.5). Returns the
# inert marker for unpopulated branches / foreign branches,
# {} for coordinates outside the graph.
# ----------------------------------------------------------------

static func node_for(seed: int, class_id: String,
		branch: int, ring: int, index: int) -> Dictionary:
	var id := pack_id(branch, ring, index)
	var info := branch_info(class_id, branch)
	if info.is_empty() or not branch_populated(branch):
		return {"id": id, "branch": branch, "ring": ring,
			"index": index, "inert": true}
	if ring < 1 or index < 0 or index >= width(seed, branch,
			ring):
		return {}
	var info_targets: Array = info["targets"]
	var side := index > 0
	var s_num := 70 if side else 100
	var s_den := 100
	var capstone := index == 0 and ring % 6 == 0
	var archetype := ""
	var kind := ""
	var target := ""
	var params: Dictionary = {}
	var desc := ""
	if capstone:
		archetype = "capstone"
		var kv := roll(seed, S_CAPSTONE_KIND, branch, ring, 0,
			100)
		if kv < 50:
			kind = "major"
			target = str(info_targets[roll(seed, S_TARGET,
				branch, ring, 0, info_targets.size())])
			params = {"components": _components(seed, branch,
				ring, index, target, 300, 100, true)}
			desc = _mod_desc(target, params["components"])
		elif kv < 80:
			kind = "variant"
			var vid := str(VARIANT_IDS[roll(seed, S_TARGET,
				branch, ring, 0, VARIANT_IDS.size())])
			target = str(VARIANTS[vid]["skill"])
			params = {"variant": vid}
			desc = str(VARIANTS[vid]["desc"])
		else:
			kind = "echo"
			var fam := str(ECHO_FAMILIES[roll(seed, S_TARGET,
				branch, ring, 0, ECHO_FAMILIES.size())])
			target = fam
			var steps := _steps(seed, branch, ring, index, 0,
				int(PARAM_BASE["dmg_pct"]),
				int(PARAM_SPAN["dmg_pct"]), 50, 100)
			params = {"echo_family": fam, "steps": steps}
			desc = "+%s %s damage (echo of another family's art)" % [
				_fmt_pct(steps, "dmg_pct"), fam]
	else:
		archetype = _archetype(seed, branch, ring, index)
		if archetype == "stat":
			var ch := str(STAT_CHANNELS[roll(seed, S_TARGET,
				branch, ring, index, STAT_CHANNELS.size())])
			var steps := _steps(seed, branch, ring, index, 0,
				int(STAT_BASE[ch]), 3, s_num, s_den)
			target = ""
			params = {"channel": ch, "steps": steps}
			var v := float(steps) * float(STAT_UNIT[ch])
			if ch == "atk_spd":
				desc = "+%s%% attack speed" % _fmt_num(v)
			elif ch == "speed":
				desc = "+%s move speed" % _fmt_num(v)
			elif ch == "aura":
				desc = "+%d aura" % int(v)
			else:
				desc = "+%s %s" % [_fmt_num(v), ch]
		elif archetype == "modifier":
			target = str(info_targets[roll(seed, S_TARGET,
				branch, ring, index, info_targets.size())])
			var comps := _components(seed, branch, ring,
				index, target, s_num, s_den, false)
			params = {"components": comps}
			desc = _mod_desc(target, comps)
		else: # behavior
			var bid := str(BEHAVIORS[roll(seed, S_TARGET,
				branch, ring, index, BEHAVIORS.size())])
			var steps := _steps(seed, branch, ring, index, 0,
				3, 3, s_num, s_den)
			target = "fireball"
			params = {"behavior": bid, "steps": steps}
			var pct := int(steps * BEHAVIOR_UNIT)
			if bid == "emberheart":
				desc = "Emberheart: your fire skills deal +%d%% damage while you are below 35%% health." % pct
			else:
				desc = "Fuel for the Flame: casting Inferno grants +%d%% fire damage for 5 s." % pct
	var composed: bool = params.has("components") \
		and (params["components"] as Array).size() > 1
	return {"id": id, "branch": branch, "ring": ring,
		"index": index, "archetype": archetype, "kind": kind,
		"target": target, "params": params,
		"cost": cost_for(archetype, ring),
		"name": _name_for(seed, branch, ring, index, composed),
		"desc": desc, "capstone": capstone}


# ----------------------------------------------------------------
# Economy (spec section 3) — wallets are DERIVED, never
# stored; unlock reads the existing signature flag.
# ----------------------------------------------------------------

static func branch_unlocked(family_collection: Dictionary,
		class_id: String, branch: int) -> bool:
	var info := branch_info(class_id, branch)
	if info.is_empty():
		return false
	var fam := str(info["family"])
	if fam == "":
		return false
	var fc: Dictionary = family_collection.get(fam, {})
	return bool(fc.get("signature", false))


static func lifetime_total(lifetime: Dictionary,
		class_id: String, branch: int) -> float:
	var info := branch_info(class_id, branch)
	if info.is_empty():
		return 0.0
	var total := 0.0
	for s in info["skills"]:
		total += float(lifetime.get(str(s), 0.0))
	return total


static func spent_total(seed: int, class_id: String,
		owned: Array, branch: int) -> int:
	var total := 0
	for id in owned:
		var iid := int(id)
		if id_branch(iid) != branch:
			continue
		var node := node_for(seed, class_id, branch,
			id_ring(iid), id_index(iid))
		if not node.is_empty() and not bool(node.get("inert",
				false)):
			total += int(node["cost"])
	return total


static func wallet_of(seed: int, class_id: String,
		lifetime: Dictionary, owned: Array,
		branch: int) -> int:
	return int(lifetime_total(lifetime, class_id, branch)) \
		- spent_total(seed, class_id, owned, branch)


# ----------------------------------------------------------------
# Aggregates (spec section 5) — ONE pure function; the
# clamps bind INSIDE it, so they hold identically on owner,
# server, and replica.
# ----------------------------------------------------------------

static func compute_aggregates(seed: int, class_id: String,
		owned: Array) -> Dictionary:
	var stat_steps := {"damage": 0, "health": 0, "speed": 0,
		"atk_spd": 0, "aura": 0}
	var dmg_steps := {} # skill -> dmg_pct steps
	var cd_steps := {}
	var rad_steps := {}
	var behaviors := {}
	var variants := {}
	var sorted_owned := owned.duplicate()
	sorted_owned.sort()
	for id in sorted_owned:
		var iid := int(id)
		var node := node_for(seed, class_id, id_branch(iid),
			id_ring(iid), id_index(iid))
		if node.is_empty() or bool(node.get("inert", false)):
			continue
		var arch := str(node["archetype"])
		var params: Dictionary = node["params"]
		if arch == "stat":
			var ch := str(params["channel"])
			stat_steps[ch] = int(stat_steps[ch]) \
				+ int(params["steps"])
		elif arch == "behavior":
			var bid := str(params["behavior"])
			var pct := int(params["steps"]
				* BEHAVIOR_UNIT)
			behaviors[bid] = maxi(int(behaviors.get(bid, 0)),
				pct)
		elif arch == "capstone" and str(node["kind"]) \
				== "variant":
			# Deepest owned wins: sorted order folds shallow
			# first, later (deeper) overwrites.
			variants[str(node["target"])] = str(params["variant"])
		elif arch == "capstone" and str(node["kind"]) == "echo":
			var fam := str(params["echo_family"])
			for s in FAMILY_SKILLS[fam]:
				dmg_steps[s] = int(dmg_steps.get(s, 0)) \
					+ int(params["steps"])
		else: # modifier / capstone major: components
			var tgt := str(node["target"])
			for c in params.get("components", []):
				var param := str(c["param"])
				var steps := int(c["steps"])
				if param == "dmg_pct":
					dmg_steps[tgt] = int(dmg_steps.get(tgt,
						0)) + steps
				elif param == "cd_pct":
					cd_steps[tgt] = int(cd_steps.get(tgt, 0)) \
						+ steps
				else:
					rad_steps[tgt] = int(rad_steps.get(tgt,
						0)) + steps
	var stat_adds := {
		"damage": minf(40.0, float(stat_steps["damage"])
			* float(STAT_UNIT["damage"])),
		"health": minf(480.0, float(stat_steps["health"])
			* float(STAT_UNIT["health"])),
		"speed": minf(1.50, float(stat_steps["speed"])
			* float(STAT_UNIT["speed"])),
		"atk_spd": minf(0.60, float(stat_steps["atk_spd"])
			* float(STAT_UNIT["atk_spd"]) / 100.0),
		"aura": int(stat_steps["aura"]),
	}
	var skill_mods := {}
	var touched := {}
	for s in dmg_steps:
		touched[s] = true
	for s in cd_steps:
		touched[s] = true
	for s in rad_steps:
		touched[s] = true
	for s in touched:
		skill_mods[s] = {
			"dmg_mult": minf(1.60, 1.0
				+ float(dmg_steps.get(s, 0))
				* float(PARAM_UNIT["dmg_pct"]) / 100.0),
			"cd_mult": maxf(0.65, 1.0
				- float(cd_steps.get(s, 0))
				* float(PARAM_UNIT["cd_pct"]) / 100.0),
			"radius_add": minf(1.5, float(rad_steps.get(s,
				0)) * float(PARAM_UNIT["radius_add"])),
		}
	return {"stat_adds": stat_adds, "skill_mods": skill_mods,
		"behaviors": behaviors, "variants": variants}


# ----------------------------------------------------------------
# Looks (spec section 6) — parameters only here; the
# construction sites consume them. Derivation hashes the
# governing owned set in canonical (sorted-id) order on the
# LOOK stream; an empty governing set returns "stock".
# ----------------------------------------------------------------

static func governing_nodes(seed: int, class_id: String,
		owned: Array, skill_id: String) -> Array:
	var out: Array = []
	for id in owned:
		var iid := int(id)
		var node := node_for(seed, class_id, id_branch(iid),
			id_ring(iid), id_index(iid))
		if node.is_empty() or bool(node.get("inert", false)):
			continue
		if str(node["target"]) == skill_id:
			out.append(iid)
	out.sort()
	return out


static func look_for(seed: int, class_id: String,
		skill_id: String, governing_owned: Array) -> Dictionary:
	var gov := governing_nodes(seed, class_id,
		governing_owned, skill_id)
	if gov.is_empty():
		return {"stock": true}
	var acc := _h(seed, S_LOOK, skill_id.hash() & 0xFFFFFF,
		gov.size(), 0)
	for id in gov:
		acc = _h(seed, S_LOOK, int(acc & 0xFFFFFF),
			int(id & 0xFFFFFFF), int((id >> 28) & 0xFFFFFFF))
	var has_variant := false
	for id in gov:
		var node := node_for(seed, class_id, id_branch(id),
			id_ring(id), id_index(id))
		if str(node.get("kind", "")) == "variant":
			has_variant = true
	# Envelopes are the stock projectiles' own: material
	# emission never exceeds today's 4.0; the light energy
	# stays within the skill's stock light range (fireball
	# 1.6, meteor 3.0); no look ever adds a light.
	var light_e := 0.8 + float(posmod(acc >> 24, 9)) / 10.0
	if skill_id == "meteor":
		light_e = 1.5 + float(posmod(acc >> 24, 16)) / 10.0
	var out := {
		"stock": false,
		"hue_shift": float(posmod(acc, 41) - 20),
		"emission_energy": 2.4 + float(posmod(acc >> 8, 17))
			/ 10.0,
		"trail_kind": ["flame", "embers", "halo"][posmod(
			acc >> 16, 3)],
		"trail_amount": (36 + posmod(acc >> 20, 13))
			if has_variant else (12 + posmod(acc >> 20, 13)),
		"light_energy": light_e,
		"variant": has_variant,
		"grammar": {},
	}
	if has_variant:
		var g := _h(seed, S_GRAMMAR, int(acc & 0xFFFFFF),
			gov.size(), 7)
		var shells: Array = []
		var shell_kinds := ["spike_crown", "orbit_ring",
			"fin_set"]
		var n_shells := posmod(g >> 12, 3)
		for k in n_shells:
			shells.append(str(shell_kinds[posmod(
				g >> (16 + k * 4), 3)]))
		out["grammar"] = {
			"core": ["octahedron", "sphere8", "box",
				"crystal"][posmod(g, 4)],
			"shells": shells,
			"scale": 0.85 + float(posmod(g >> 8, 31)) / 100.0,
		}
	return out


# ----------------------------------------------------------------
# Data surface (spec section 8) — player is read duck-typed
# (Dictionary or Object) so the module names no game class.
# ----------------------------------------------------------------

static func _pread(player: Variant, key: String,
		default_value: Variant) -> Variant:
	if player is Dictionary:
		return (player as Dictionary).get(key, default_value)
	if player is Object:
		return (player as Object).get(key)
	return default_value


static func visible_nodes(player: Variant) -> Array:
	var class_id := str(_pread(player, "class_id", ""))
	var seed := int(_pread(player, "tree_seed", TREE_SEED))
	var owned: Array = _pread(player, "tree_owned", [])
	var fcol: Dictionary = _pread(player, "family_collection",
		{})
	var out: Array = []
	for b in branches_for(class_id):
		var bid := int(b["id"])
		# Spec section 3: a signature-locked branch exposes
		# NO nodes on the data surface (and inert branches
		# have none to expose).
		if not branch_populated(bid) or not branch_unlocked(
				fcol, class_id, bid):
			continue
		var deepest := deepest_owned(owned, bid)
		for ring in range(1, deepest + 3):
			for index in width(seed, bid, ring):
				var node := node_for(seed, class_id, bid, ring,
					index)
				if node.is_empty():
					continue
				var entry := node.duplicate()
				if owned.has(int(node["id"])):
					entry["state"] = "owned"
				elif prereq_met(seed, class_id, int(node["id"]),
						owned):
					entry["state"] = "purchasable"
				else:
					entry["state"] = "locked"
				out.append(entry)
	return out


static func wallet(player: Variant, branch: int) -> int:
	var class_id := str(_pread(player, "class_id", ""))
	var seed := int(_pread(player, "tree_seed", TREE_SEED))
	var owned: Array = _pread(player, "tree_owned", [])
	var lifetime: Dictionary = _pread(player, "tree_lifetime",
		{})
	return wallet_of(seed, class_id, lifetime, owned, branch)
