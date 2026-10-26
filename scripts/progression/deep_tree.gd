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


## Populated branches (the prototype populated Fire; issue
## #210 slice B1 adds Frost and Storm).
static func branch_populated(branch: int) -> bool:
	return branch in [1, 2, 3, 4, 5, 6, 7, 8, 9]


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
	# Issue #210 (full build section 2.1): glacial prison
	# has NO dmg_pct; the exclusions are the table's own
	# statement. (Amendment 1 adds shatter_pct — the
	# authored Brittle Ice channel, not a dmg_pct.)
	"frost": ["dmg_pct", "slow_add"],
	"blizzard": ["dmg_pct", "radius_add", "duration_add"],
	# Amendment 1 (section B.1): shatter_pct is the
	# integrated Brittle Ice mechanic — the prison's only
	# damage channel, and NOT a dmg_pct.
	"glacial_prison": ["cd_pct", "radius_add", "freeze_add",
		"shatter_pct"],
	# Issue #210 (section 2.2): lightning has NO cd_pct —
	# its 0.6 s server gate is a designed floor.
	# Amendment 1 (section B.2): brand_amp is Arcing Brand.
	"lightning": ["dmg_pct", "chains_add", "brand_amp"],
	"barrage": ["dmg_pct", "brand_amp"],
	"tempest": ["dmg_pct", "cd_pct", "radius_add",
		"duration_add"],
	# Issue #210 slice B2 (Shadow, section 2.5): smoke
	# veil's cd fold has no atk_spd division in the base
	# game and the tree does not add one; shadow_step's
	# step_dmg row is Amendment 1 section C.2 (Umbral
	# Strike, clamp 1.00).
	"smoke_veil": ["cd_pct", "duration_add"],
	"shadow_step": ["cd_pct", "step_dmg"],
	"assassinate": ["cd_pct", "dmg_pct"],
	# Issue #210 slice B2 (Precision, section 2.6):
	# eagle_eye has NO cd_pct — it is wave-gated, a
	# designed protection (Amendment 1 section A).
	"eagle_eye": ["duration_add"],
	"mark": ["cd_pct", "vuln_add"],
	"fan": ["cd_pct", "dmg_pct"],
	"execution": ["cd_pct", "dmg_pct", "threshold_add"],
	# Issue #210 slice B3 (Warden, section 2.3): the
	# totem magnitude channels scale the branch's tick
	# strength (or, for doom, its stored magnitude).
	"reciprocity": ["radius_add", "duration_add",
		"mend_pct"],
	"stoneskin": ["radius_add", "duration_add",
		"armor_pct"],
	"sanctuary_totem": ["cd_pct", "radius_add",
		"duration_add"],
	# Issue #210 slice B3 (Conqueror, section 2.4).
	"bulwark": ["radius_add", "duration_add", "guard_pct"],
	"warhorn": ["radius_add", "duration_add", "aura_pct"],
	"rally": ["radius_add", "duration_add", "haste_pct"],
	"doom_totem": ["cd_pct", "vuln_pct", "radius_add"],
	"sentry_turret": ["cd_pct", "hp_pct", "life_add",
		"dmg_pct", "range_add"],
	"bulwark_wall": ["cd_pct", "hp_pct", "life_add",
		"pulse_dmg"],
	"spike_trap": ["cd_pct", "hp_pct", "life_add",
		"dmg_pct", "radius_add"],
	"keystone": ["cd_pct", "hp_pct", "life_add",
		"radius_add", "aura_pct"],
	"hammer_smash": ["cd_pct", "dmg_pct"],
	"reinforce": ["cd_pct", "shell_pct"],
	"demolish": ["cd_pct", "dmg_pct", "radius_add"],
}
const PARAM_UNIT := {"dmg_pct": 0.5, "cd_pct": 0.5,
	"radius_add": 0.1, "range_add": 0.1, "slow_add": 0.25,
	"duration_add": 0.5, "freeze_add": 0.25,
	"chains_add": 1.0, "shatter_pct": 2.5,
	"brand_amp": 2.0, "step_dmg": 5.0, "vuln_add": 2.0,
	"hp_pct": 1.0, "life_add": 1.0, "shell_pct": 1.0,
	"pulse_dmg": 5.0,
	"threshold_add": 1.0, "mend_pct": 1.0,
	"armor_pct": 1.0, "guard_pct": 1.0, "aura_pct": 1.0,
	"haste_pct": 1.0, "vuln_pct": 1.0}
## Per-target unit overrides: tempest's duration step is
## 1 s (2 strikes), blizzard's is one 0.5 s tick.
const PARAM_UNIT_TARGET := {"tempest": {"duration_add": 1.0},
	# Issue #210 slice B2: the veil window grows in 1 s
	# steps (the dispatch's step size; spec section 2.5
	# names the channel without a size).
	"smoke_veil": {"duration_add": 1.0}}
const PARAM_BASE := {"dmg_pct": 4, "cd_pct": 4,
	"radius_add": 2, "range_add": 2, "slow_add": 2, "duration_add": 2,
	"freeze_add": 2, "chains_add": 1, "shatter_pct": 2,
	"brand_amp": 3, "step_dmg": 2, "vuln_add": 2,
	"hp_pct": 3, "life_add": 2, "shell_pct": 3,
	"pulse_dmg": 2,
	"threshold_add": 2, "mend_pct": 3, "armor_pct": 3,
	"guard_pct": 3, "aura_pct": 3, "haste_pct": 3,
	"vuln_pct": 3}
const PARAM_SPAN := {"dmg_pct": 5, "cd_pct": 5,
	"radius_add": 3, "range_add": 3, "slow_add": 3, "duration_add": 3,
	"freeze_add": 3, "chains_add": 2, "shatter_pct": 3,
	"brand_amp": 4, "step_dmg": 3, "vuln_add": 3,
	"hp_pct": 4, "life_add": 3, "shell_pct": 4,
	"pulse_dmg": 3,
	"threshold_add": 3, "mend_pct": 4, "armor_pct": 4,
	"guard_pct": 4, "aura_pct": 4, "haste_pct": 4,
	"vuln_pct": 4}


static func _param_unit(param: String, target: String) -> float:
	var by_target: Dictionary = PARAM_UNIT_TARGET.get(
		target, {})
	if by_target.has(param):
		return float(by_target[param])
	return float(PARAM_UNIT[param])


const BEHAVIOR_UNIT := 5.0 # percent per step
## Authored behaviors per branch (the Fire pattern: two).
const BEHAVIORS := {
	1: ["emberheart", "fuel_for_the_flame"],
	2: ["shatterglass", "permafrost_heart"],
	3: ["stormcharged", "static_bloom"],
	6: ["veilwalker", "from_the_dark"],
	7: ["deadeye", "surveyor"],
	4: ["rooted_ward", "oathkeeper"],
	5: ["warlords_tempo", "strength_in_numbers"],
	8: ["overbuilt", "siege_mind"],
	9: ["tempered", "salvage"],
}
## The skill a branch's behavior nodes govern for looks.
const BEHAVIOR_TARGET := {1: "fireball", 2: "frost",
	3: "lightning", 6: "smoke_veil", 7: "mark",
	4: "reciprocity", 5: "warhorn",
	8: "sentry_turret", 9: "hammer_smash"}

const VARIANTS := {
	"twin_suns": {"skill": "fireball",
		"desc": "Twin Suns: Fireball casts two bolts at 65% damage each."},
	"meteor_shower": {"skill": "meteor",
		"desc": "Meteor Shower: Meteor falls as three meteors at 45% in a triangle."},
	"phoenix_pyre": {"skill": "inferno",
		"desc": "Phoenix Pyre: Inferno's tick also heals allies in its radius."},
	"splinter_volley": {"skill": "frost",
		"desc": "Splinter Volley: Frost fires two shards at 65% damage each."},
	"whiteout": {"skill": "blizzard",
		"desc": "Whiteout: Blizzard's radius grows by half, its ticks hit 40% harder and land every 0.75 s."},
	"stasis_burst": {"skill": "glacial_prison",
		"desc": "Stasis Burst: when Glacial Prison's freeze ends, its targets take a burst of damage."},
	"forked_sky": {"skill": "lightning",
		"desc": "Forked Sky: chain lightning's first target is struck twice, the second strike at 70%."},
	"tempest_fan": {"skill": "barrage",
		"desc": "Tempest Fan: Barrage fires five bolts at 50% damage each."},
	"eye_of_the_storm": {"skill": "tempest",
		"desc": "Eye of the Storm: when Tempest ends, a final strike at 200% hits the nearest enemy."},
	"choking_veil": {"skill": "smoke_veil",
		"desc": "Choking Veil: enemies caught in Smoke Veil's activation scan are slowed for 3 s."},
	"twin_step": {"skill": "shadow_step",
		"desc": "Twin Step: Shadow Step can be re-cast free within 2 s."},
	"coup_de_grace": {"skill": "assassinate",
		"desc": "Coup de Grâce: a killing Assassinate resets its cooldown."},
	"shuriken_storm": {"skill": "fan",
		"desc": "Shuriken Storm: Fan of Knives strikes each target two extra times at 80%."},
	"death_sentence": {"skill": "mark",
		"desc": "Death Sentence: your marked targets take +25% more damage from everyone."},
	"headsman": {"skill": "execution",
		"desc": "Headsman: bosses face Execution's threshold at half effect instead of immunity."},
	"aegis_dome": {"skill": "sanctuary_totem",
		"desc": "Aegis Dome: allies inside Sanctuary also gain stoneskin armor."},
	"thorn_mirror": {"skill": "reciprocity",
		"desc": "Thorn Mirror: Reciprocity's thorns slow enemies in its radius by 20% for 2 s."},
	"twin_bolts": {"skill": "sentry_turret",
		"name": "Twin Bolts",
		"desc": "Twin Bolts: each turret shot fires a second bolt at 60% damage."},
	"cluster_trap": {"skill": "spike_trap",
		"name": "Cluster Trap",
		"desc": "Cluster Trap: the trap detonates a second time at 70% damage after 0.5 s."},
	"heartstone": {"skill": "keystone",
		"name": "Heartstone",
		"desc": "Heartstone: the keystone also heals nearby structures for 5 health per second."},
	"seismic_smash": {"skill": "hammer_smash",
		"name": "Seismic Smash",
		"desc": "Seismic Smash: the smash sends a ring at 50% damage beyond its own area."},
	"aegis_shell": {"skill": "reinforce",
		"name": "Aegis Shell",
		"desc": "Aegis Shell: while the shell holds, its bearer deals +25% damage."},
	"wrecking_ball": {"skill": "demolish",
		"name": "Wrecking Ball",
		"desc": "Wrecking Ball: Demolish deals +10% damage per structure you have standing."},
	"living_stone": {"skill": "stoneskin",
		"desc": "Living Stone: Stoneskin's totem also heals allies in its radius each tick."},
	"doom_herald": {"skill": "doom_totem",
		"desc": "Doom Herald: every 5 s, Doom's pulse damages enemies in its radius."},
	"thunderhead_horn": {"skill": "warhorn",
		"desc": "Thunderhead Horn: Warhorn also grants allies attack speed."},
	"forced_march": {"skill": "rally",
		"desc": "Forced March: Rally also grants allies damage."},
}
const VARIANT_IDS := {
	1: ["twin_suns", "meteor_shower", "phoenix_pyre"],
	2: ["splinter_volley", "whiteout", "stasis_burst"],
	3: ["forked_sky", "tempest_fan", "eye_of_the_storm"],
	6: ["choking_veil", "twin_step", "coup_de_grace"],
	7: ["shuriken_storm", "death_sentence", "headsman"],
	4: ["aegis_dome", "thorn_mirror", "living_stone"],
	5: ["doom_herald", "thunderhead_horn", "forced_march"],
	8: ["twin_bolts", "cluster_trap", "heartstone"],
	9: ["seismic_smash", "aegis_shell", "wrecking_ball"],
}

const ECHO_FAMILIES := {
	1: ["frost", "storm"],
	2: ["fire", "storm"],
	3: ["frost", "fire"],
	6: ["precision"],
	7: ["shadow"],
	4: ["conqueror"],
	5: ["warden"],
	8: ["forge"], 9: ["engineering"],
}
const FAMILY_SKILLS := {"fire": ["fireball", "meteor"],
	"frost": ["frost", "blizzard"],
	"storm": ["lightning", "barrage"],
	"shadow": ["smoke_veil", "shadow_step"],
	"precision": ["eagle_eye", "mark", "fan"],
	"warden": ["reciprocity", "stoneskin"],
	"conqueror": ["bulwark", "warhorn", "rally"],
	"engineering": ["sentry_turret", "bulwark_wall",
		"spike_trap", "keystone"],
	"forge": ["hammer_smash", "reinforce", "demolish"]}

const NAME_ADJ := ["Kindled", "Ashen", "Ember", "Scorched",
	"Wildfire", "Blazing", "Smoldering", "Cinder",
	"Pyre", "Furnace", "Ignited", "Charred"]
const NAME_NOUN := ["Heart", "Crown", "Conflagration",
	"Brand", "Tongue", "Mantle", "Gaze", "Pact", "Wick",
	"Throne", "Veil", "Oath"]
## Per-branch name vocabulary (#210); branch 1 keeps the
## prototype tables above, so Fire's names never move.
const NAME_ADJ_BY_BRANCH := {
	2: ["Frozen", "Glacial", "Rime", "Hoarfrost", "Silent",
		"Pale", "Winter", "Shivering", "Crystal", "Bitter",
		"Northern", "Glass"],
	3: ["Crackling", "Tempest", "Voltaic", "Howling",
		"Charged", "Forked", "Rumbling", "Bright", "Wild",
		"Stormborn", "Arc", "Thunder"],
	6: ["Silent", "Umbral", "Veiled", "Hollow", "Patient",
		"Dusken", "Hidden", "Fading", "Soundless", "Pale",
		"Grim", "Ashen"],
	7: ["Keen", "Patient", "True", "Cold", "Steady",
		"Piercing", "Watchful", "Measured", "Certain",
		"Bright", "Still", "Hawken"],
	4: ["Rooted", "Patient", "Stalwart", "Oathen",
		"Quiet", "Iron", "Mossy", "Steadfast", "Gravel",
		"Amber", "Hewn", "Deep"],
	5: ["Iron", "Howling", "Crimson", "Relentless",
		"Thunder", "Savage", "Burning", "Grim",
		"Marching", "Broken", "Feral", "Proud"],
	8: ["Iron", "Patient", "Stalwart", "Cogged",
		"Braced", "Riveted", "Quiet", "Heavy",
		"Measured", "Stone", "Copper", "Deep"],
	9: ["Burning", "Iron", "Thunder", "Heavy",
		"Molten", "Grim", "Patient", "Savage",
		"Bright", "Stone", "Howling", "Deep"],
}
const NAME_NOUN_BY_BRANCH := {
	2: ["Shard", "Prison", "Veil", "Heart", "Crown",
		"Mirror", "Gaze", "Pact", "Tomb", "Throne",
		"Garden", "Oath"],
	3: ["Arc", "Verdict", "Tongue", "Mantle", "Gaze",
		"Pact", "Crown", "Throne", "Veil", "Oath",
		"Choir", "Brand"],
	6: ["Veil", "Step", "Blade", "Promise", "Shadow",
		"Whisper", "Gaze", "Covenant", "Edge", "Shroud",
		"Mark", "Throat"],
	7: ["Eye", "Mark", "Fan", "Verdict", "Sight",
		"Ledger", "Point", "Reckoning", "Glance", "Oath",
		"Edge", "Crown"],
	4: ["Ward", "Oath", "Stone", "Root", "Watch",
		"Bastion", "Promise", "Shelter", "Post", "Ring",
		"Hearth", "Gate"],
	5: ["Horn", "Doom", "Standard", "March", "Roar",
		"Banner", "Crown", "Charge", "Dirge", "Toll",
		"Wrath", "Drum"],
	8: ["Turret", "Wall", "Trap", "Key", "Bastion",
		"Gear", "Post", "Engine", "Ward", "Span",
		"Bolt", "Foundation"],
	9: ["Hammer", "Shell", "Wreck", "Forge", "Anvil",
		"Bellows", "Stroke", "Ember", "Brand", "Seal",
		"Fall", "Crown"],
}

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
	var table: Array = (PARAM_TABLE[target] as Array).duplicate()
	# Issue #210 section 2.2: chains_add generates only from
	# the boughs band up (ring >= 5).
	if target == "lightning" and ring < 5:
		table.erase("chains_add")
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
		elif param == "radius_add":
			parts.append("+%s m %s blast radius" % [
				_fmt_num(float(steps)
					* float(PARAM_UNIT[param])), target])
		elif param == "slow_add":
			parts.append("+%s s %s slow duration" % [
				_fmt_num(float(steps)
					* float(PARAM_UNIT[param])), target])
		elif param == "duration_add":
			parts.append("+%s s %s duration" % [
				_fmt_num(float(steps)
					* _param_unit(param, target)), target])
		elif param == "freeze_add":
			parts.append("+%s s %s freeze" % [
				_fmt_num(float(steps)
					* float(PARAM_UNIT[param])), target])
		elif param == "chains_add":
			parts.append("+%d %s chain(s)" % [steps, target])
		elif param == "shatter_pct":
			parts.append("+%s %s shatter (of caster damage)" % [
				_fmt_pct(steps, param), target])
		elif param == "brand_amp":
			parts.append("+%s %s brand amplification" % [
				_fmt_pct(steps, param), target])
		elif param == "hp_pct":
			parts.append("+%s%% max health" % _fmt_num(
				float(steps) * float(PARAM_UNIT[param])))
		elif param == "shell_pct":
			parts.append("shell strength +%s%%"
				% _fmt_num(float(steps)
				* float(PARAM_UNIT[param])))
		elif param == "pulse_dmg":
			parts.append("thorn pulse %s%% of your damage"
				% _fmt_num(float(steps)
				* float(PARAM_UNIT[param])))
		elif param == "life_add":
			parts.append("lasts +%s s longer"
				% _fmt_num(float(steps)
				* float(PARAM_UNIT[param])))
		elif param == "range_add":
			parts.append("range +%s m" % _fmt_num(
				float(steps) * float(PARAM_UNIT[param])))
		elif param == "step_dmg":
			parts.append("+%s %s arrival damage (of weapon damage)" % [
				_fmt_pct(steps, param), target])
		elif param == "vuln_add":
			parts.append("+%s %s vulnerability" % [
				_fmt_pct(steps, param), target])
		elif param == "threshold_add":
			parts.append("+%s %s execute threshold" % [
				_fmt_pct(steps, param), target])
		else: # the slice B3 totem magnitude kinds
			parts.append("+%s %s magnitude" % [
				_fmt_pct(steps, param), target])
	return "; ".join(parts)


static func _name_for(seed: int, branch: int, ring: int,
		index: int, composed: bool) -> String:
	var adjs: Array = NAME_ADJ_BY_BRANCH.get(branch, NAME_ADJ)
	var nouns: Array = NAME_NOUN_BY_BRANCH.get(branch,
		NAME_NOUN)
	var adj := str(adjs[roll(seed, S_NAME_A, branch, ring,
		index * 2, adjs.size())])
	if composed:
		adj += " " + str(adjs[roll(seed, S_NAME_A, branch,
			ring, index * 2 + 1, adjs.size())])
	return adj + " " + str(nouns[roll(seed, S_NAME_N,
		branch, ring, index * 2, nouns.size())])


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
			var vids: Array = VARIANT_IDS[branch]
			var vid := str(vids[roll(seed, S_TARGET,
				branch, ring, 0, vids.size())])
			target = str(VARIANTS[vid]["skill"])
			params = {"variant": vid}
			desc = str(VARIANTS[vid]["desc"])
		else:
			kind = "echo"
			var fams: Array = ECHO_FAMILIES[branch]
			var fam := str(fams[roll(seed, S_TARGET,
				branch, ring, 0, fams.size())])
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
			var bids: Array = BEHAVIORS[branch]
			var bid := str(bids[roll(seed, S_TARGET,
				branch, ring, index, bids.size())])
			var steps := _steps(seed, branch, ring, index, 0,
				3, 3, s_num, s_den)
			target = str(BEHAVIOR_TARGET[branch])
			params = {"behavior": bid, "steps": steps}
			var pct := int(steps * BEHAVIOR_UNIT)
			match bid:
				"emberheart":
					desc = "Emberheart: your fire skills deal +%d%% damage while you are below 35%% health." % pct
				"fuel_for_the_flame":
					desc = "Fuel for the Flame: casting Inferno grants +%d%% fire damage for 5 s." % pct
				"shatterglass":
					desc = "Shatterglass: your frost skills deal +%d%% damage to slowed or frozen targets." % pct
				"permafrost_heart":
					desc = "Permafrost Heart: your frost skills deal +%d%% damage while you are above 75%% health." % pct
				"stormcharged":
					desc = "Stormcharged: for 10 s after casting Tempest, your chain lightning gains +1 chain."
				"overbuilt":
					desc = "Overbuilt: placing a structure repairs your other structures by %d%% of their max health." % pct
				"siege_mind":
					desc = "Siege Mind: your turret deals +%d%% damage to elites and bosses." % pct
				"tempered":
					desc = "Tempered: for 5 s after Reinforce, your Hammer Smash deals +%d%% damage." % pct
				"salvage":
					desc = "Salvage: when your structure is destroyed, refund %d%% of its placement cooldown." % pct
				"static_bloom":
					desc = "Static Bloom: your chain lightning deals +%d%% damage to every target beyond the first." % pct
				_:
					desc = bid
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
		class_id: String, branch: int,
		lifetime: Dictionary = {}) -> bool:
	# Spec section 1.1: the architect branches carry no
	# family; they unlock at lifetime >= 100 in ANY
	# architect branch skill.
	if branch in [8, 9]:
		for bid in [8, 9]:
			for sk in branch_info(class_id,
					bid).get("skills", []):
				if float(lifetime.get(str(sk), 0.0)) \
						>= 100.0:
					return true
		return false
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
	var slow_steps := {}
	var dur_steps := {}
	var freeze_steps := {}
	var chain_steps := {}
	var shatter_steps := {}
	var brand_steps := {}
	var step_steps := {}
	var vuln_steps := {}
	var thresh_steps := {}
	# Issue #210 slice B3: the totem magnitude kinds,
	# keyed "target|param" (one bucket for six channels).
	var mag_steps := {}
	var range_steps := {}
	var life_steps := {}
	var pulse_steps := {}
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
				elif param == "radius_add":
					rad_steps[tgt] = int(rad_steps.get(tgt,
						0)) + steps
				elif param == "range_add":
					range_steps[tgt] = int(
						range_steps.get(tgt, 0)) + steps
				elif param == "life_add":
					life_steps[tgt] = int(
						life_steps.get(tgt, 0)) + steps
				elif param == "pulse_dmg":
					pulse_steps[tgt] = int(
						pulse_steps.get(tgt, 0)) + steps
				elif param == "slow_add":
					slow_steps[tgt] = int(slow_steps.get(tgt,
						0)) + steps
				elif param == "duration_add":
					dur_steps[tgt] = int(dur_steps.get(tgt,
						0)) + steps
				elif param == "freeze_add":
					freeze_steps[tgt] = int(freeze_steps.get(
						tgt, 0)) + steps
				elif param == "chains_add":
					chain_steps[tgt] = int(chain_steps.get(
						tgt, 0)) + steps
				elif param == "shatter_pct":
					shatter_steps[tgt] = int(shatter_steps.get(
						tgt, 0)) + steps
				elif param == "brand_amp":
					brand_steps[tgt] = int(brand_steps.get(
						tgt, 0)) + steps
				elif param == "step_dmg":
					step_steps[tgt] = int(step_steps.get(
						tgt, 0)) + steps
				elif param == "vuln_add":
					vuln_steps[tgt] = int(vuln_steps.get(
						tgt, 0)) + steps
				elif param == "threshold_add":
					thresh_steps[tgt] = int(thresh_steps.get(
						tgt, 0)) + steps
				elif param in ["mend_pct", "armor_pct",
						"guard_pct", "aura_pct",
						"haste_pct", "vuln_pct",
						"hp_pct", "shell_pct"]:
					var mk: String = tgt + "|" + param
					mag_steps[mk] = int(mag_steps.get(
						mk, 0)) + steps
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
	for s in slow_steps:
		touched[s] = true
	for s in dur_steps:
		touched[s] = true
	for s in freeze_steps:
		touched[s] = true
	for s in chain_steps:
		touched[s] = true
	for s in shatter_steps:
		touched[s] = true
	for s in brand_steps:
		touched[s] = true
	for s in step_steps:
		touched[s] = true
	for s in vuln_steps:
		touched[s] = true
	for s in thresh_steps:
		touched[s] = true
	for s in range_steps:
		touched[s] = true
	for s in life_steps:
		touched[s] = true
	for s in pulse_steps:
		touched[s] = true
	for mk in mag_steps:
		touched[mk.split("|")[0]] = true
	for s in touched:
		var entry := {
			"dmg_mult": minf(1.60, 1.0
				+ float(dmg_steps.get(s, 0))
				* float(PARAM_UNIT["dmg_pct"]) / 100.0),
			"cd_mult": maxf(0.65, 1.0
				- float(cd_steps.get(s, 0))
				* float(PARAM_UNIT["cd_pct"]) / 100.0),
			"radius_add": minf(1.5, float(rad_steps.get(s,
				0)) * float(PARAM_UNIT["radius_add"])),
		}
		# Issue #210 channels join the entry only when a
		# producer wrote them (Fire's entries keep their
		# prototype shape exactly). chains_add carries the
		# table's aggregate clamp (+2).
		if int(slow_steps.get(s, 0)) > 0:
			entry["slow_add"] = float(slow_steps[s]) \
				* float(PARAM_UNIT["slow_add"])
		if int(dur_steps.get(s, 0)) > 0:
			entry["duration_add"] = float(dur_steps[s]) \
				* _param_unit("duration_add", s)
		if int(freeze_steps.get(s, 0)) > 0:
			entry["freeze_add"] = float(freeze_steps[s]) \
				* float(PARAM_UNIT["freeze_add"])
		if int(chain_steps.get(s, 0)) > 0:
			entry["chains_add"] = mini(2, int(chain_steps[s]))
		# Issue #210 slice B4 channels: range/life join
		# unclamped (none named); pulse_dmg carries
		# Amendment 1 section D's clamp (<= 0.50).
		if int(range_steps.get(s, 0)) > 0:
			entry["range_add"] = float(range_steps[s]) \
				* float(PARAM_UNIT["range_add"])
		if int(life_steps.get(s, 0)) > 0:
			entry["life_add"] = float(life_steps[s]) \
				* float(PARAM_UNIT["life_add"])
		if int(pulse_steps.get(s, 0)) > 0:
			entry["pulse_dmg"] = minf(0.50,
				float(pulse_steps[s])
				* float(PARAM_UNIT["pulse_dmg"]) / 100.0)
		# Amendment 1 section D clamps: shatter_pct is a
		# fraction of caster damage (<= 1.00); brand_amp is
		# a damage fraction (<= 0.40 per skill).
		if int(shatter_steps.get(s, 0)) > 0:
			entry["shatter_pct"] = minf(1.0,
				float(shatter_steps[s])
				* float(PARAM_UNIT["shatter_pct"]) / 100.0)
		if int(brand_steps.get(s, 0)) > 0:
			entry["brand_amp"] = minf(0.40,
				float(brand_steps[s])
				* float(PARAM_UNIT["brand_amp"]) / 100.0)
		# Issue #210 slice B2 channels: step_dmg carries
		# Amendment 1 section D's clamp (<= 1.00);
		# vuln_add and threshold_add carry no clamp —
		# none is named for them (the no-new-clamps rule).
		if int(step_steps.get(s, 0)) > 0:
			entry["step_dmg"] = minf(1.00,
				float(step_steps[s])
				* float(PARAM_UNIT["step_dmg"]) / 100.0)
		if int(vuln_steps.get(s, 0)) > 0:
			entry["vuln_add"] = float(vuln_steps[s]) \
				* float(PARAM_UNIT["vuln_add"]) / 100.0
		if int(thresh_steps.get(s, 0)) > 0:
			entry["threshold_add"] = float(thresh_steps[s]) \
				* float(PARAM_UNIT["threshold_add"]) / 100.0
		# Issue #210 slice B3: totem magnitudes are
		# fractions of the branch's base magnitude; no
		# clamp is named for any of them (section 1.5).
		for mp in ["mend_pct", "armor_pct", "guard_pct",
				"aura_pct", "haste_pct", "vuln_pct",
				"hp_pct", "shell_pct"]:
			var mkey: String = s + "|" + mp
			if int(mag_steps.get(mkey, 0)) > 0:
				entry[mp] = float(mag_steps[mkey]) \
					* float(PARAM_UNIT[mp]) / 100.0
		skill_mods[s] = entry
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
	if skill_id == "frost":
		# FrostShard's stock light burns at 1.2.
		light_e = 0.9 + float(posmod(acc >> 24, 7)) / 10.0
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
				fcol, class_id, bid,
				_pread(player, "tree_lifetime", {})):
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
