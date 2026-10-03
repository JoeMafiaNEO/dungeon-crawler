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
	"orc": 20,
	"skeleton": 22,
	"elite": 40,  # Multiplier on base cost.
}

var credits: float = 0.0
var credit_rate: float = 10.0  # Credits per second.
var wave_number: int = 0
## Mob IDs the current theme allows. Empty = all.
var allowed_mobs: Array = []


func set_allowed_mobs(ids: Array) -> void:
	allowed_mobs = ids.duplicate()


func start_wave(wave: int) -> void:
	wave_number = wave
	credits = 50.0 + wave * 25.0  # Starting budget scales with wave.


func _process(delta: float) -> void:
	credits += credit_rate * delta


func get_wave_composition() -> Array:
	# Returns array of mob type IDs to spawn this wave.
	var composition: Array = []
	var budget := credits
	
	# Don't buy too cheap (RoR2 rule): prefer expensive enemies as budget grows.
	# Only spawn mobs the current theme allows.
	var available := ENEMY_COSTS.keys()
	if not allowed_mobs.is_empty():
		available = available.filter(func(id): return id in allowed_mobs)
	available.sort_custom(func(a, b): return ENEMY_COSTS[a] < ENEMY_COSTS[b])
	
	while budget >= 5.0 and composition.size() < 20:
		# Pick the most expensive enemy we can afford (with some randomness).
		var candidates := []
		for mob_id in available:
			if ENEMY_COSTS[mob_id] <= budget:
				candidates.append(mob_id)
		if candidates.is_empty():
			break
		
		# Bias toward expensive (last 3 candidates) but allow cheap.
		var pick: String
		if randf() < 0.7 and candidates.size() >= 3:
			pick = candidates[randi_range(candidates.size() - 3, candidates.size() - 1)]
		else:
			pick = candidates[randi() % candidates.size()]
		
		# Elite chance: 10% to upgrade to elite.
		if randf() < 0.1 and pick != "elite":
			composition.append({"type": pick, "elite": true})
			budget -= ENEMY_COSTS[pick] + ENEMY_COSTS["elite"]
		else:
			composition.append({"type": pick, "elite": false})
			budget -= ENEMY_COSTS[pick]
	
	credits = budget  # Leftover carries over.
	return composition


func get_threat_level() -> float:
	# 0.0-1.0 threat for HUD/AI scaling.
	return clampf(credits / 200.0, 0.0, 1.0)
