class_name MobData
extends Resource
## Data-driven monster: stats, XP reward, drop table, sprite frames.

@export var id: String = ""
@export var display_name: String = ""
@export var health: float = 30.0
@export var damage: float = 5.0
@export var move_speed: float = 3.0
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.2
@export var xp_reward: int = 10
@export var drop_chance: float = 0.3
@export var drops: Array[DropEntry] = []
@export var frames: Array[Texture2D] = []
## Loot luck: shifts drop weights toward rarer items (0 = normal).
## Tougher mobs and bosses have higher luck.
@export var loot_luck: float = 0.0
## Extra drop rolls on kill (bosses shower loot).
@export var bonus_drops: int = 0
## Ranged attackers keep their distance and fire projectiles instead of
## meleeing. preferred_range is the ideal distance; they back off when
## closer than preferred_range * 0.7 and close in when farther.
@export var ranged: bool = false
@export var preferred_range: float = 10.0
@export var projectile_speed: float = 14.0

# --- Boss config (ignored unless is_boss) ---
@export var is_boss: bool = false
@export var boss_title: String = ""
@export var scale_mult: float = 1.0
## Special attack: "slam" (AoE around self), "summon" (spawn minions),
## "charge" (telegraphed dash at nearest player). "" = none.
@export var special_id: String = ""
@export var special_cooldown: float = 8.0
@export var special_damage_mult: float = 2.0
@export var summon_id: String = ""
@export var summon_count: int = 2
## Apex mechanic id for apex-cycle bosses (issue #5): "", "enrage" (Bristleback),
## "adds" (Warden), "phaseshift" (Horror). Empty for every non-apex mob/boss.
@export var apex_id: String = ""
