class_name BountySystem
extends Node
## Bounty Board core (issue #7 Phase 1): data-driven opt-in objectives.
##
## Generation is server-side on dungeon entry, seeded by the level seed, so
## every peer in the run sees the same 3 bounties (deterministic,
## reproducible). Tracking is server-authoritative and per player: progress
## lives in Player.bounty_progress ({bounty_id: count}, -1 = failed) and
## rides along in player snapshots. Completion pays bonus cash + XP
## immediately and feeds SaveManager.check_achievements().
##
## The record_* helpers are static and pure (plain Dictionaries in/out) so
## the headless suite can exercise generation, theme filtering and
## per-player independence without a scene tree.

# --- Template pools (dictionaries in code; no .tres needed per spec) ---

const KILL_TEMPLATES := [
	{"count": 8, "cash": 50, "xp": 30},
	{"count": 15, "cash": 100, "xp": 60},
	{"count": 25, "cash": 160, "xp": 100},
]
const ELITE_TEMPLATES := [
	{"count": 2, "cash": 140, "xp": 110},
	{"count": 4, "cash": 260, "xp": 200},
]
const NO_DEATH_TEMPLATES := [
	{"cash": 220, "xp": 180},
]
const CASH_TEMPLATES := [
	{"amount": 200, "cash": 90, "xp": 50},
	{"amount": 350, "cash": 150, "xp": 90},
]

const MOB_PLURALS := {
	"slime": "Slimes",
	"goblin": "Goblins",
	"skeleton": "Skeletons",
	"orc": "Orc Brutes",
	"bat": "Giant Bats",
	"archer": "Goblin Archers",
	"cultist": "Dark Cultists",
}

## Reward multiplier per cycle (cycle 1 = base).
static func reward_mult(cycle: int) -> float:
	return 1.0 + 0.25 * float(maxi(0, cycle - 1))


## Server-side generation: 3 bounty dicts, seeded by the level seed.
## kill/elite bounties only use mob ids from theme.mob_mix (the AI
## Director's allowed set); cash bounties only on supermarket; no_death
## anywhere. Identical output for the same inputs on every peer.
static func generate(level_seed: int, theme_id: String, mob_mix: Dictionary, cycle: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed
	var roster: Array = mob_mix.keys()
	var out: Array = []
	if roster.is_empty():
		# No kill-based bounties possible (e.g. the warlord RTS map has an
		# empty mob mix): fall back to the always-valid no_death bounty.
		out.append(_make_no_death(cycle, _bounty_id(level_seed, 0)))
		return out
	# Slot 1: kill bounty, mob weighted by the theme's mix.
	var mob_id := _weighted_pick(rng, mob_mix)
	out.append(_make_kill(rng, cycle, mob_id, _bounty_id(level_seed, 0)))
	var used_kinds := ["kill"]
	var used_mobs := [mob_id]
	# Slot 2: elite hunt or a flawless run.
	if rng.randf() < 0.5:
		out.append(_make_elite(rng, cycle, _weighted_pick(rng, mob_mix), _bounty_id(level_seed, 1)))
		used_kinds.append("elite")
	else:
		out.append(_make_no_death(cycle, _bounty_id(level_seed, 1)))
		used_kinds.append("no_death")
	# Slot 3: supermarket gets the cash bounty, everyone else kill/no_death.
	# Issue #44: dedup — never repeat a kind already used this level.
	if theme_id == "supermarket":
		out.append(_make_cash(rng, cycle, _bounty_id(level_seed, 2)))
	elif rng.randf() < 0.5 or "no_death" in used_kinds:
		# Prefer kill; force it if no_death already used.
		var m2 := _weighted_pick(rng, mob_mix)
		# Avoid same-mob duplicate kill bounties when the roster allows it.
		if m2 in used_mobs and roster.size() > 1:
			for _i in range(8):
				var alt := _weighted_pick(rng, mob_mix)
				if not alt in used_mobs:
					m2 = alt
					break
		out.append(_make_kill(rng, cycle, m2, _bounty_id(level_seed, 2)))
	elif not "no_death" in used_kinds:
		out.append(_make_no_death(cycle, _bounty_id(level_seed, 2)))
	else:
		out.append(_make_kill(rng, cycle, _weighted_pick(rng, mob_mix), _bounty_id(level_seed, 2)))
	return out


static func _bounty_id(level_seed: int, slot: int) -> String:
	return "bty_%x_%d" % [level_seed & 0xFFFFFFFF, slot]


static func _weighted_pick(rng: RandomNumberGenerator, mob_mix: Dictionary) -> String:
	var total := 0.0
	for k in mob_mix.keys():
		total += float(mob_mix[k])
	if total <= 0.0:
		return str(mob_mix.keys()[0])
	var roll := rng.randf() * total
	for k in mob_mix.keys():
		roll -= float(mob_mix[k])
		if roll <= 0.0:
			return str(k)
	return str(mob_mix.keys()[0])


static func _mob_name(mob_id: String) -> String:
	return str(MOB_PLURALS.get(mob_id, mob_id.capitalize() + "s"))


static func _make_kill(rng: RandomNumberGenerator, cycle: int, mob_id: String, bid: String) -> Dictionary:
	var t: Dictionary = KILL_TEMPLATES[rng.randi_range(0, KILL_TEMPLATES.size() - 1)]
	var mult := reward_mult(cycle)
	return {
		"id": bid,
		"kind": "kill",
		"mob_id": mob_id,
		"target": int(t["count"]),
		"cash_reward": int(round(float(t["cash"]) * mult)),
		"xp_reward": int(round(float(t["xp"]) * mult)),
		"name": "Slay %d %s" % [int(t["count"]), _mob_name(mob_id)],
		"desc": "Defeat %d %s this level." % [int(t["count"]), _mob_name(mob_id)],
	}


static func _make_elite(rng: RandomNumberGenerator, cycle: int, mob_id: String, bid: String) -> Dictionary:
	var t: Dictionary = ELITE_TEMPLATES[rng.randi_range(0, ELITE_TEMPLATES.size() - 1)]
	var mult := reward_mult(cycle)
	return {
		"id": bid,
		"kind": "elite",
		"mob_id": mob_id,
		"target": int(t["count"]),
		"cash_reward": int(round(float(t["cash"]) * mult)),
		"xp_reward": int(round(float(t["xp"]) * mult)),
		"name": "Elite %s Hunter" % _mob_name(mob_id),
		"desc": "Defeat %d elite %s this level." % [int(t["count"]), _mob_name(mob_id)],
	}


static func _make_no_death(cycle: int, bid: String) -> Dictionary:
	var t: Dictionary = NO_DEATH_TEMPLATES[0]
	var mult := reward_mult(cycle)
	return {
		"id": bid,
		"kind": "no_death",
		"target": 1,
		"cash_reward": int(round(float(t["cash"]) * mult)),
		"xp_reward": int(round(float(t["xp"]) * mult)),
		"name": "Untouchable",
		"desc": "Clear the level without dying.",
	}


static func _make_cash(rng: RandomNumberGenerator, cycle: int, bid: String) -> Dictionary:
	var t: Dictionary = CASH_TEMPLATES[rng.randi_range(0, CASH_TEMPLATES.size() - 1)]
	var mult := reward_mult(cycle)
	return {
		"id": bid,
		"kind": "cash",
		"target": int(t["amount"]),
		"cash_reward": int(round(float(t["cash"]) * mult)),
		"xp_reward": int(round(float(t["xp"]) * mult)),
		"name": "Big Spender",
		"desc": "Sell $%d of loot at checkout." % int(t["amount"]),
	}


# --- Per-player tracking (static, pure; progress is {bounty_id: count},
# -1 means failed). Each returns the bounty dicts completed by the event. ---

static func new_progress(bounties: Array) -> Dictionary:
	var p := {}
	for b in bounties:
		p[str(b["id"])] = 0
	return p


static func is_complete(progress: Dictionary, bounty: Dictionary) -> bool:
	var c := int(progress.get(str(bounty["id"]), -1))
	return c >= 0 and c >= int(bounty["target"])


static func is_failed(progress: Dictionary, bounty: Dictionary) -> bool:
	return int(progress.get(str(bounty["id"]), 0)) < 0


static func _settled(progress: Dictionary, bounty: Dictionary) -> bool:
	return is_complete(progress, bounty) or is_failed(progress, bounty)


## Mob death hook: kill/elite bounties filtered by mob id.
static func record_kill(progress: Dictionary, bounties: Array, mob_id: String, is_elite: bool) -> Array:
	var done: Array = []
	for b in bounties:
		var bid := str(b["id"])
		if _settled(progress, b):
			continue
		var kind := str(b["kind"])
		var matches := false
		if kind == "kill" and not is_elite and str(b["mob_id"]) == mob_id:
			matches = true
		elif kind == "elite" and is_elite and str(b["mob_id"]) == mob_id:
			matches = true
		if matches:
			progress[bid] = int(progress.get(bid, 0)) + 1
			if is_complete(progress, b):
				done.append(b)
	return done


## Player death hook: fails that player's no_death bounties only.
static func record_death(progress: Dictionary, bounties: Array) -> Array:
	var failed: Array = []
	for b in bounties:
		var bid := str(b["id"])
		if _settled(progress, b):
			continue
		if str(b["kind"]) == "no_death":
			progress[bid] = -1
			failed.append(b)
	return failed


## Checkout hook: cash bounties progress on per-sale earnings.
static func record_checkout(progress: Dictionary, bounties: Array, earned: int) -> Array:
	var done: Array = []
	for b in bounties:
		var bid := str(b["id"])
		if _settled(progress, b):
			continue
		if str(b["kind"]) == "cash":
			progress[bid] = int(progress.get(bid, 0)) + earned
			if is_complete(progress, b):
				done.append(b)
	return done


## Level-clear hook: surviving no_death bounties complete and pay out.
static func record_level_cleared(progress: Dictionary, bounties: Array) -> Array:
	var done: Array = []
	for b in bounties:
		var bid := str(b["id"])
		if _settled(progress, b):
			continue
		if str(b["kind"]) == "no_death":
			progress[bid] = int(b["target"])
			done.append(b)
	return done


# --- Instance: the live manager the dungeon owns (like AIDirector) ---

## The run's 3 bounties, identical on every peer.
var bounties: Array = []


func setup_for_level(level_seed: int, theme_id: String, mob_mix: Dictionary, cycle: int) -> void:
	bounties = generate(level_seed, theme_id, mob_mix, cycle)
