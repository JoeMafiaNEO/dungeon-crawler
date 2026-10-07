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

# --- Shieldbearer config (issue #67): frontal block mechanics ---
## If true, frontal attacks within block_arc_deg are reduced by block_mult.
@export var frontal_block: bool = false
## Frontal arc in degrees (centered on facing direction) where block applies.
@export var block_arc_deg: float = 120.0
## Damage multiplier for blocked frontal hits (0.1 = 90% reduction).
@export var block_mult: float = 0.1

# --- Splitter config (issue #67 Phase 2): split on death ---
## If true, spawn split_count children of split_id on death (server-side).
@export var split_on_death: bool = false
## Mob ID to spawn on death (e.g., "slime_small").
@export var split_id: String = "slime_small"
## Number of children to spawn on death.
@export var split_count: int = 3

# --- Gravewarden config (issue #67 Phase 3): support aura ---
## Radius of the support aura (heals/buffs allies, not self).
## Default 0.0 (no aura); Gravewarden sets 8.0 in its .tres.
@export var support_aura_radius: float = 0.0
## Healing per second applied to allies in the aura.
@export var support_heal_ps: float = 6.0
## Damage multiplier applied to allies in the aura.
@export var support_dmg_mult: float = 1.25

# --- Siren song (issue #84 Phase 3): slowing song ---
## Radius of the song effect (players within are slowed).
@export var song_radius: float = 0.0
## Movement multiplier applied to slowed players (0.6 = 40% slow).
@export var song_slow_mult: float = 0.6
## How long the song channels (seconds).
@export var song_duration: float = 3.0
## Cooldown between songs (seconds).
@export var song_cooldown: float = 12.0

# --- Angler stealth-lunge (issue #84 Phase 3) ---
## If true, mob is invisible + untargetable until player within lunge_range.
@export var stealth_lunge: bool = false
## Range at which stealth breaks and telegraph begins.
@export var lunge_range: float = 8.0
## Telegraph duration before the lunge (seconds).
@export var lunge_telegraph: float = 0.8

# --- Bellows Hound fire trail (issue #85 Phase 2) ---
## DPS dealt to players standing in fresh trail decals (0 = no damaging trail).
@export var trail_damage: float = 0.0
## Seconds a trail decal stays "hot" (damaging). Visual lasts longer.
@export var trail_duration: float = 2.0

# --- Slag Spitter lava glob (issue #85 Phase 2) ---
## Projectile visual variant: "" = default arrow, "lava_glob" = emissive orange sphere.
@export var projectile_kind: String = ""
