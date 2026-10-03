class_name CivData
extends Resource
## Civilization bonuses tied to player class.
## Warriors -> Iron Vanguard (infantry swarm), Rogues -> Shadow Covenant (speed/raids),
## Mages -> Arcane Dominion (fast ages, elite late-game).

@export var civ_id: String = ""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var description: String = ""

# Multipliers (1.0 = no bonus).
@export var spearman_hp_mult: float = 1.0
@export var spearman_dmg_mult: float = 1.0
@export var archer_dmg_mult: float = 1.0
@export var archer_range_mult: float = 1.0
@export var knight_dmg_mult: float = 1.0
@export var knight_hp_mult: float = 1.0
@export var train_time_mult: float = 1.0
@export var move_speed_mult: float = 1.0
@export var gather_rate_mult: float = 1.0
@export var age_cost_mult: float = 1.0
@export var townhall_hp_mult: float = 1.0

# Unique unit names (flavor; same AI as base types).
@export var spearman_name: String = "Spearman"
@export var archer_name: String = "Archer"
@export var knight_name: String = "Knight"

# Starting resources bonus.
@export var start_wood: int = 0
@export var start_food: int = 0
@export var start_gold: int = 0


static func for_class(class_id: String) -> CivData:
	var civ := CivData.new()
	match class_id:
		"warrior":
			civ.civ_id = "iron_vanguard"
			civ.display_name = "Iron Vanguard"
			civ.color = Color(0.8, 0.2, 0.2)
			civ.description = "Heavy infantry swarm. Outlast them."
			civ.spearman_hp_mult = 1.3
			civ.spearman_dmg_mult = 1.15
			civ.train_time_mult = 0.8
			civ.townhall_hp_mult = 1.5
			civ.spearman_name = "Legionary"
		"rogue":
			civ.civ_id = "shadow_covenant"
			civ.display_name = "Shadow Covenant"
			civ.color = Color(0.5, 0.2, 0.8)
			civ.description = "Fast raiders. Strike where they aren't."
			civ.archer_dmg_mult = 1.25
			civ.archer_range_mult = 1.1
			civ.move_speed_mult = 1.15
			civ.gather_rate_mult = 1.1
			civ.archer_name = "Ranger"
		"mage":
			civ.civ_id = "arcane_dominion"
			civ.display_name = "Arcane Dominion"
			civ.color = Color(0.2, 0.4, 0.9)
			civ.description = "Race through the ages. Hit Empire first."
			civ.age_cost_mult = 0.7
			civ.knight_dmg_mult = 1.3
			civ.knight_hp_mult = 1.15
			civ.knight_name = "Spellblade"
			civ.start_wood = 100
			civ.start_food = 100
			civ.start_gold = 100
		_:
			civ.civ_id = "iron_vanguard"
			civ.display_name = "Iron Vanguard"
			civ.color = Color(0.8, 0.2, 0.2)
	return civ
