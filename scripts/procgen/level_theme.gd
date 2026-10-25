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

# --- Sky dome (issue #202) ---
## Procedural-sky shaping for sunlit themes, consumed by
## dungeon.gd::_build_environment. EVERY default below equals the
## value in effect before these fields existed — the engine defaults
## of ProceduralSkyMaterial / Environment (probed first-hand on the
## shipping engine build) plus the horizon lightening factor that
## used to be hardcoded at 0.25 in _build_environment. A theme whose
## .tres sets none of them renders exactly as the pre-#202 build did;
## the four outdoor Act 1 themes carry their treatments as .tres data.
@export var sky_curve: float = 0.15
@export var sky_energy_multiplier: float = 1.0
@export var ground_curve: float = 0.02
@export var ground_energy_multiplier: float = 1.0
## sky_horizon_color = sky_color.lightened(this factor).
@export var horizon_lighten: float = 0.25
@export var sun_angle_max: float = 30.0
@export var sun_curve: float = 0.15
## Environment.fog_sky_affect: how strongly the sky itself is fogged.
## 1.0 (the engine default) = the sky fully takes the fog at distance.
@export var fog_sky_affect: float = 1.0

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
## Jesse 2026-10-15 (Misty Docks only): the wave flow does not end at
## the final wave. The clear sequence (loot shower + key scatter) still
## fires exactly once when the final wave is cleared, but the host may
## then keep starting waves — they cycle intermission -> active like
## waves 1-4, composed by the AI Director on its normal scaling curve,
## while the scattered keys remain collectable. Every other theme
## leaves this false and ends its wave flow at the final wave.
@export var endless_waves: bool = false

# --- Puzzle ---
## After the final wave this many keys scatter in the level; finding them
## all clears the level (secures the run's gains).
@export var puzzle_key_count: int = 3
## When true, ProcGen carves a backrooms-style maze of rock walls (depths).
@export var maze_walls: bool = false

# --- Fishing + farming (issue #102) ---
## When true, ProcGen places ponds with piers and records fishing spots.
## Base themes leave this false and pay nothing (no new RNG draws).
@export var has_fishing_water: bool = false
## When true, ProcGen places farm soil plots and records farm plot spots.
@export var has_farm_plots: bool = false

# --- Heightmap terrain (issue #103) ---
## When true, the dungeon builds true heightmap terrain instead of the
## flat floor. The terrain conforms to the generated layout — ProcGen
## placement and RNG draw order are untouched, and heights derive
## deterministically from the level seed on every peer.
@export var use_heightmap_terrain: bool = false
## Terrain profile (issue #118: parameterized out of dungeon.gd's
## _build_terrain, where the Misty Docks constants used to be hardcoded).
## The defaults ARE the docks profile, so a theme that only flips
## use_heightmap_terrain gets the proven marsh behavior; each opted-in
## theme's .tres carries its own profile explicitly.
@export var terrain_amplitude: float = 1.0
@export var terrain_noise_frequency: float = 0.045
@export var terrain_height_offset: float = 0.55
## Parked below the terrain minimum on dry themes: no water anywhere
## (ponds exist only where the layout carves them — see pond_depth).
@export var terrain_water_level: float = -0.10
@export var terrain_pond_depth: float = 0.5
@export var terrain_smooth_passes: int = 2
@export var terrain_flatten_radius: float = 5.0
## Extra flatten disc at the arena center (0 = off): terrain relaxes
## toward its LOCAL height at the center over this radius (issue #122,
## Apex Arena: the boss-fight disc — charges/slams read clearly while
## the rim relief outside the disc is untouched). Carried as a
## flatten_target with a NAN height, which HeightmapTerrain resolves
## by sampling the local grid height, exactly like a POI.
@export var terrain_center_flatten_radius: float = 0.0
## Vertex-color palette: bed (under water), then low/mid/high bands.
@export var terrain_tint_bed: Color = Color(0.23, 0.22, 0.16)
@export var terrain_tint_low: Color = Color(0.16, 0.23, 0.17)
@export var terrain_tint_mid: Color = Color(0.26, 0.25, 0.19)
@export var terrain_tint_high: Color = Color(0.32, 0.32, 0.33)
## Height the vertex-tint ramp's t=0 sits at (issue #118 follow-up).
## NAN (the default) = anchor at terrain_water_level, the original
## shared behavior — wet themes (the docks) keep their proven palette
## arithmetically untouched. Dry themes park their water far below
## the terrain, which would pin every vertex at t=1 (single-band
## render); they set this to their design floor (terrain_height_offset
## - terrain_amplitude * 0.5) so the low/mid/high bands express.
@export var terrain_tint_anchor: float = NAN
