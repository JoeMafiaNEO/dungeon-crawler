class_name ItemData
extends Resource
## Data-driven loot item. Bonuses are flat additions to player stats.

enum Slot { WEAPON, ARMOR, TRINKET }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }


static func rarity_name(r: int) -> String:
	match r:
		Rarity.COMMON:
			return "Common"
		Rarity.UNCOMMON:
			return "Uncommon"
		Rarity.RARE:
			return "Rare"
		Rarity.EPIC:
			return "Epic"
		Rarity.LEGENDARY:
			return "Legendary"
	return "Common"


static func rarity_color(r: int) -> Color:
	match r:
		Rarity.COMMON:
			return Color(0.82, 0.82, 0.82)
		Rarity.UNCOMMON:
			return Color(0.35, 0.9, 0.35)
		Rarity.RARE:
			return Color(0.35, 0.6, 1.0)
		Rarity.EPIC:
			return Color(0.7, 0.35, 1.0)
		Rarity.LEGENDARY:
			return Color(1.0, 0.62, 0.15)
	return Color.WHITE

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var slot: Slot = Slot.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var damage_bonus: float = 0.0
@export var health_bonus: float = 0.0
@export var speed_bonus: float = 0.0
## Multipliers granted while equipped. They stack multiplicatively.
@export var damage_mult: float = 1.0
@export var health_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var xp_mult: float = 1.0
## 3D model shown for the world pickup (res:// path to .glb/.gltf).
@export var world_model: String = ""
## Consumables are used from the inventory (not passive). One use = one count.
@export var consumable: bool = false
## Fraction of max HP restored on use (0 = none).
@export var heal_fraction: float = 0.0
## Temporary buff on use: stat "speed"/"damage", mult, duration seconds.
@export var buff_stat: String = ""
@export var buff_mult: float = 1.0
@export var buff_duration: float = 0.0
## Supermarket loot: sellable for cash, cleared from inventory on leaving
## the supermarket level. Potions are NOT supermarket loot.
@export var supermarket_loot: bool = false
## Cash value when sold at the supermarket checkout.
@export var sell_value: int = 0
## Meta-locked: must be unlocked via achievements before it enters the drop pool.
@export var meta_locked: bool = false
