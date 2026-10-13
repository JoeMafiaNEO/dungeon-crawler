class_name ItemData
extends Resource
## Data-driven loot item. Bonuses are flat additions to player stats.

enum Slot { WEAPON, ARMOR, TRINKET, TOOL }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }


## Issue #104 Phase 1: canonical name of a slot ("" for none). Inventory
## stacks store this string as their equipped marker, and run saves store
## it under the "slot" key.
static func slot_name(s: int) -> String:
	match s:
		Slot.WEAPON:
			return "WEAPON"
		Slot.ARMOR:
			return "ARMOR"
		Slot.TRINKET:
			return "TRINKET"
		Slot.TOOL:
			return "TOOL"
	return ""


## Issue #104 Phase 1: an item is GEAR iff it is not a consumable and its
## slot is one of the four equipment slots. Only gear can be equipped, and
## only equipped gear grants passive stats (Player._recalc_stats).
static func is_gear(item: ItemData) -> bool:
	if item == null or item.consumable:
		return false
	return item.slot == Slot.WEAPON or item.slot == Slot.ARMOR \
		or item.slot == Slot.TRINKET or item.slot == Slot.TOOL


## Issue #104 Phase 1: per-copy power score: sum of flat bonuses +
## multiplier deviation from 1.0.
static func power_score(item: ItemData) -> float:
	if item == null:
		return 0.0
	return item.damage_bonus + item.health_bonus + item.speed_bonus \
		+ (item.damage_mult - 1.0) + (item.health_mult - 1.0) \
		+ (item.speed_mult - 1.0) + (item.xp_mult - 1.0)


## Issue #104 Phase 1: STACK-level power score — what a whole stack
## actually grants (flat bonuses scale with count, multipliers
## compound). The old-save migration picks the highest-power STACK per
## slot by this score.
static func stack_power_score(item: ItemData, count: int) -> float:
	if item == null:
		return 0.0
	var c := maxi(1, count)
	return (item.damage_bonus + item.health_bonus + item.speed_bonus) * float(c) \
		+ (pow(item.damage_mult, c) - 1.0) + (pow(item.health_mult, c) - 1.0) \
		+ (pow(item.speed_mult, c) - 1.0) + (pow(item.xp_mult, c) - 1.0)


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
## Issue #104 Phase 1: classes allowed to EQUIP this item (empty = all
## classes). Enforced at equip time only — anyone may carry the item.
@export var allowed_classes: Array[String] = []
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
## Issue #113 Phase 1: weapon upgrade kit strength. When > 0, this
## consumable is an upgrade kit: using it adds this many upgrade levels
## to the EQUIPPED weapon stack (see Player._use_upgrade_kit). 0 = not
## a kit.
@export var upgrade_levels: int = 0
## Fraction of max HP restored on use (0 = none).
@export var heal_fraction: float = 0.0
## Temporary buff on use: stat "speed"/"damage", mult, duration seconds.
@export var buff_stat: String = ""
@export var buff_mult: float = 1.0
@export var buff_duration: float = 0.0
## Issue #102 Phase 4: wave-counted buff duration. When > 0, using the item
## grants a wave buff lasting this many cleared waves (decremented by
## Player.on_wave_cleared, broadcast by the dungeon per wave). Mult < 1.0
## reduces the stat (defense = damage taken).
@export var buff_waves: int = 0
## Supermarket loot: sellable for cash, cleared from inventory on leaving
## the supermarket level. Potions are NOT supermarket loot.
@export var supermarket_loot: bool = false
## Cash value when sold at the supermarket checkout.
@export var sell_value: int = 0
## Issue #102 Phase 4: dock-economy good (fish, crops, seeds, farm cash,
## bait, fertilizer, dock vendor wares). Excluded from the station vendor
## pool and every other run-cash commerce path: the dock economy is
## balance-isolated by design — farm cash never converts to run cash
## ("gold") and run cash never buys dock goods.
@export var dock_good: bool = false
## Meta-locked: must be unlocked via achievements before it enters the drop pool.
@export var meta_locked: bool = false
## Issue #113 Phase 3: class starting gear (the Architect's tools).
## Granted at run start and re-granted when missing — never loot, never
## purchasable: catalog-wide pool builders (vendor stock, loot shower)
## must exclude these, and they are never added to MobData drop pools.
@export var starting_gear: bool = false
## Relic Vault special (issue #5): if set, picking this up earns/activates the
## named special (SpecialData id) instead of entering the inventory.
@export var grants_special: String = ""
