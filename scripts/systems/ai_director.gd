extends Node
## AIDirector: Risk of Rain 2-style wave composition.
## Accumulates "credits" over time, spends them on a priced enemy menu.
## Cheap trash → expensive elites. Never rubber-bands to player performance.

# Enemy costs (credits).
const ENEMY_COSTS := {
	"slime": 5,
	"bat": 8,
	"goblin": 10,
	"archer": 12,
	"cultist": 15,
	"splitter": 18,
	"orc": 20,
	"skeleton": 22,
	"shieldbearer": 25,
	"gravewarden": 30,
}

# Role buckets for mixed waves (Jesse 2026-10-10): every wave drafts from
# each role so waves aren't all-trash or all-elite by accident.
const ROLE_MOBS := {
	"ranged": ["archer"],
	"counter": ["shieldbearer"],
	"heavy": ["gravewarden"],
	"fast": ["splitter", "bat"],
	"melee": ["slime", "goblin", "orc", "skeleton", "cultist"],
}
# Repeating draft order; shuffled per wave so the mix isn't mechanical.
const DRAFT_PATTERN := ["melee", "fast", "ranged", "melee", "counter", "fast", "melee", "heavy"]

# Upgrade tiers: each step costs 40 (normal -> elite -> champion).
const TIER_NAMES := ["normal", "elite", "champion"]
const UPGRADE_STEP_COST := 40

var credits: float = 0.0
var credit_rate: float = 10.0  # Credits per second.
var wave_number: int = 0
## Player count multiplier (Jesse 2026-10-10, issue #101): wave credit budget
## scales with the server's player count. Set by the dungeon before each wave.
var player_count: int = 1
## Mob IDs the current theme allows. Empty = all.
var allowed_mobs: Array = []


func set_allowed_mobs(ids: Array) -> void:
	allowed_mobs = ids.duplicate()


func start_wave(wave: int) -> void:
	wave_number = wave
	# Starting budget scales with wave AND player count (Jesse 2026-10-10).
	credits = (50.0 + wave * 25.0) * float(player_count)


func _process(delta: float) -> void:
	credits += credit_rate * delta * float(player_count)


func get_wave_composition() -> Array:
	# Returns array of {"type": mob_id, "tier": 0/1/2} to spawn this wave.
	# Phase 1 (draft): round-robin through shuffled roles so every wave has
	# a mix — ranged, counters, heavies, fast, melee. Phase 2 (upgrades):
	# leftover credits buy elite/champion tiers (Jesse 2026-10-10).
	var composition: Array = []
	var budget := credits

	var available := ENEMY_COSTS.keys()
	if not allowed_mobs.is_empty():
		available = available.filter(func(id): return id in allowed_mobs)
	if available.is_empty():
		credits = budget
		return composition
	var cheapest := 999999.0
	for mob_id in available:
		cheapest = minf(cheapest, float(ENEMY_COSTS[mob_id]))

	# Phase 1: draft.
	var pattern := DRAFT_PATTERN.duplicate()
	pattern.shuffle()
	var pi := 0
	while budget >= cheapest and composition.size() < 20:
		var role: String = pattern[pi % pattern.size()]
		pi += 1
		var mob_id := _pick_in_role(role, available, budget)
		if mob_id == "":
			continue
		composition.append({"type": mob_id, "tier": 0})
		budget -= ENEMY_COSTS[mob_id]

	# Phase 2: upgrades — priciest base mobs first. Pass 1 spreads elites,
	# pass 2 promotes elites to champions.
	composition.sort_custom(
		func(a, b): return ENEMY_COSTS[a["type"]] > ENEMY_COSTS[b["type"]])
	for entry in composition:
		if entry["tier"] == 0 and budget >= UPGRADE_STEP_COST:
			entry["tier"] = 1
			budget -= UPGRADE_STEP_COST
	for entry in composition:
		if entry["tier"] == 1 and budget >= UPGRADE_STEP_COST:
			entry["tier"] = 2
			budget -= UPGRADE_STEP_COST

	credits = budget  # Leftover carries over.
	return composition


func _pick_in_role(role: String, available: Array, budget: float) -> String:
	# Most-expensive-affordable in the role, with some randomness.
	var candidates := []
	for mob_id in ROLE_MOBS[role]:
		if mob_id in available and ENEMY_COSTS[mob_id] <= budget:
			candidates.append(mob_id)
	if candidates.is_empty():
		return ""
	candidates.sort_custom(func(a, b): return ENEMY_COSTS[a] < ENEMY_COSTS[b])
	if randf() < 0.7 and candidates.size() >= 2:
		return candidates[randi_range(candidates.size() - 2, candidates.size() - 1)]
	return candidates[randi() % candidates.size()]


func get_threat_level() -> float:
	# 0.0-1.0 threat for HUD/AI scaling.
	return clampf(credits / 200.0, 0.0, 1.0)
