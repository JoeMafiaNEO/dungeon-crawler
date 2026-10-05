class_name LevelTheme
extends Resource
## Defines the look, layout parameters, and gameplay tuning for one level theme.
## New themes are added by creating a new .tres with these exported fields --
## no engine code changes needed.

@export var theme_id: String = ""
@export var display_name: String = ""

# --- Layout ---
@export var grid_size: int = 24 ## cells per side (arena is grid_size x grid_size)
@export var cell_size: float = 2.0 ## meters per cell
@export var clear_radius: int = 3 ## cells around center kept free of obstacles
@export var obstacle_blobs_min: int = 4
@export var obstacle_blobs_max: int = 7

# --- Palette ---
@export var ground_color: Color = Color(0.32, 0.33, 0.30)
@export var wall_color: Color = Color(0.42, 0.38, 0.34)
@export var obstacle_color: Color = Color(0.38, 0.36, 0.33)
@export var sky_color: Color = Color(0.55, 0.75, 1.0)
@export var fog_color: Color = Color(0.55, 0.75, 1.0)
@export var fog_density: float = 0.008
@export var ambient_color: Color = Color(0.55, 0.55, 0.60)
@export var ambient_energy: float = 0.7
@export var sun_color: Color = Color(1.0, 0.98, 0.92)
@export var sun_energy: float = 1.1
@export var sun_direction: Vector3 = Vector3(-0.45, -1.0, -0.35)

# --- Obstacles & props ---
## Each entry: { "type": "<prop builder type>", "weight": float, "size": int cells }.
## Obstacles block movement and are always convex (no mob traps).
@export var obstacle_entries: Array[Dictionary] = []
## Each entry: { "type": "<prop builder type>", "weight": float }.
## Props are decorative and never block movement.
@export var prop_entries: Array[Dictionary] = []
@export var props_min: int = 10
@export var props_max: int = 18
## Wall torches with flickering point lights (0 = none, e.g. outdoor themes).
@export var torch_count: int = 0
@export var torch_light_color: Color = Color(1.0, 0.55, 0.25)
@export var torch_light_energy: float = 2.0

# --- Gameplay ---
## Mob mix: { "mob_id": weight }.
@export var mob_mix: Dictionary = {}
@export var hp_scale: float = 1.0
@export var dmg_scale: float = 1.0
## Boss spawned on the final wave of this theme ("" = none).
@export var boss_id: String = ""

# --- Puzzle ---
## After the final wave this many keys scatter in the level; finding them
## all clears the level (secures the run's gains).
@export var puzzle_key_count: int = 3
## When true, ProcGen carves a backrooms-style maze of rock walls (depths).
@export var maze_walls: bool = false
