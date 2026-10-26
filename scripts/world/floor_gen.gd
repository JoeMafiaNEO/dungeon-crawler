class_name FloorGen
extends RefCounted
## Pure floor synthesis for Act 2 buildings (issue #205, P5).
##
## Everything here is a deterministic function of the building
## record + floor index + danger index, computed identically
## on every peer — a floor is never replicated; each peer
## synthesizes the same LevelTheme and the same seed and the
## game's ordinary level machinery (the dungeon scene) builds
## the same floor from them. Floor-count parity is the hard
## contract: a building's interior floors == its shell's
## floors field. The footprint is cheated (arena-scale floor
## scenes); the count is not.
##
## The home building (S3) is the one authored exception: its
## floors ARE the six Act 1 themes, in order.

const WorldGen := preload("res://scripts/world/world_gen.gd")
const BuildingGen := preload("res://scripts/world/building_gen.gd")
const BuildingSelect := preload("res://scripts/world/building_select.gd")

const SALT_SEED := 5001
## The home building's floors, in order (issue #205 S3).
const HOME_THEMES: Array = ["village", "dungeon", "depths",
	"supermarket", "misty_docks", "warlord"]
## The boss pool by danger band (band = danger index tiers).
const BOSS_POOL: Array = ["boss_boar", "boss_warden", "boss_horror"]


## The full building record for a "wlx,wlz" anchor-lot key —
## the same derivation the world streamer assembles from, so
## the shell in the street and the floors behind its door
## always agree. {} when the lot holds no building.
static func record_for(key: String) -> Dictionary:
	var parts := key.split(",")
	if parts.size() != 2:
		return {}
	var wlx := int(parts[0])
	var wlz := int(parts[1])
	var seed: int = WorldGen.WORLD_SEED
	var b: Dictionary = WorldGen.building_at(seed, wlx, wlz)
	if b.is_empty():
		return {}
	var floors := int(b["floors"])
	var style := int(b["style"])
	var span_x := int(b["span_x"])
	var span_z := int(b["span_z"])
	var massing := int(b["massing"])
	var plan: Dictionary = BuildingGen.plan_for(seed, wlx, wlz,
		floors, style, span_x, span_z, massing)
	var origin := Vector3((float(wlx) + float(span_x) * 0.5)
		* WorldGen.LOT_SIZE, 0.0,
		(float(wlz) + float(span_z) * 0.5) * WorldGen.LOT_SIZE)
	origin.y = WorldGen.height_at(seed, origin.x, origin.z)
	var dw: Dictionary = BuildingGen.door_world(plan, origin)
	var dens: Dictionary = WorldGen.density_at_world(seed,
		origin.x, origin.z)
	return {"key": key, "wlx": wlx, "wlz": wlz,
		"floors": floors, "style": style,
		"span_x": span_x, "span_z": span_z, "massing": massing,
		"origin": origin, "doorstep": dw["doorstep"],
		"gap_center": dw["gap_center"],
		"density": float(dens["density"]),
		"kind": str(dens["kind"]),
		"playable": BuildingSelect.is_playable(seed, wlx, wlz)}


static func is_home_key(key: String, home_anchor: Dictionary) -> bool:
	if home_anchor.is_empty():
		return false
	return key == "%d,%d" % [
		int(floor(float(home_anchor["rect_x"]) / WorldGen.LOT_SIZE)),
		int(floor(float(home_anchor["rect_z"]) / WorldGen.LOT_SIZE))]


## The per-floor generation seed: an int hash of (key, floor)
## — stable across peers and sessions, different per floor.
static func seed_for(key: String, floor_idx: int) -> int:
	var parts := key.split(",")
	var wlx := int(parts[0]) if parts.size() == 2 else 0
	var wlz := int(parts[1]) if parts.size() == 2 else 0
	var h := (wlx * 73856093) ^ (wlz * 19349663) \
		^ ((floor_idx + 1) * 83492791) ^ (WorldGen.WORLD_SEED * 31)
	return absi(h) % 2000000000


## THE ACCESS RULE (mechanical): vertical travel stops at the
## lowest uncleared floor. Returns that floor's index, or
## `floors` when the building is fully cleared.
static func lowest_uncleared(mask: int, floors: int) -> int:
	for f in floors:
		if (mask >> f) & 1 == 0:
			return f
	return floors


## A floor may be entered iff it is at or below the frontier
## (every cleared floor, plus the lowest uncleared one).
static func floor_allowed(mask: int, floors: int, f: int) -> bool:
	if f < 0 or f >= floors:
		return false
	return f <= lowest_uncleared(mask, floors)


static func allowed_floors(mask: int, floors: int) -> Array:
	var out: Array = []
	for f in floors:
		if floor_allowed(mask, floors, f):
			out.append(f)
	return out


## Grid size (cells) for a floor: the span/style base,
## modulated per floor by the shell's massing profile —
## tapered/stepped shells narrow with height, podium shells
## narrow off the podium. Always inside the specced 24–96.
static func grid_for(record: Dictionary, floor_idx: int) -> int:
	var span_x := int(record.get("span_x", 1))
	var span_z := int(record.get("span_z", 1))
	var style := int(record.get("style", 0))
	var floors := maxi(1, int(record.get("floors", 1)))
	var massing := int(record.get("massing", 0))
	var base := 24 + (span_x + span_z - 2) * 10 + style * 2
	var frac := float(floor_idx) / float(maxi(1, floors - 1))
	var shrink := 0.0
	match massing:
		1:
			shrink = 0.15 * frac
		2:
			shrink = 0.30 * frac
		3:
			shrink = 0.20 * (1.0 - frac)
	return clampi(int(round(float(base) * (1.0 - shrink))), 24, 96)


static func boss_for(danger: int) -> String:
	var band := clampi(danger / 2, 0, BOSS_POOL.size() - 1)
	return str(BOSS_POOL[band])


static func mob_mix_for(danger: int) -> Dictionary:
	if danger <= 0:
		return {"goblin": 3.0, "slime": 2.0, "bat": 1.5}
	if danger == 1:
		return {"goblin": 2.5, "skeleton": 2.0, "orc": 1.5,
			"archer": 1.5, "bat": 1.0}
	if danger <= 3:
		return {"skeleton": 2.0, "orc": 2.0, "archer": 2.0,
			"shieldbearer": 1.5, "splitter": 1.0, "cultist": 1.0}
	return {"skeleton": 2.0, "orc": 2.0, "archer": 1.5,
		"shieldbearer": 1.5, "cultist": 1.5,
		"stone_sentry": 1.0, "gravewarden": 1.0}


## The synthesized runtime LevelTheme for one floor. The home
## building's floors are the Act 1 themes themselves (loaded
## and duplicated — the machinery's own cycle paths treat
## them exactly as Act 1 does).
static func theme_for(record: Dictionary, floor_idx: int,
		danger: int, is_home: bool) -> LevelTheme:
	if is_home and floor_idx >= 0 and floor_idx < HOME_THEMES.size():
		var authored := load("res://data/levels/theme_%s.tres"
			% str(HOME_THEMES[floor_idx])) as LevelTheme
		if authored != null:
			return authored.duplicate() as LevelTheme
	var t := LevelTheme.new()
	t.theme_id = "floor"
	var kind := str(record.get("kind", "city"))
	t.display_name = "%s — Floor %d" % [
		kind.capitalize(), floor_idx + 1]
	t.grid_size = grid_for(record, floor_idx)
	t.cell_size = 2.0
	# District character drives the palette.
	match kind:
		"village":
			t.ground_color = Color(0.36, 0.33, 0.26)
			t.wall_color = Color(0.45, 0.38, 0.28)
			t.obstacle_color = Color(0.40, 0.35, 0.26)
		"wilderness":
			t.ground_color = Color(0.30, 0.34, 0.24)
			t.wall_color = Color(0.38, 0.40, 0.30)
			t.obstacle_color = Color(0.34, 0.36, 0.27)
		_:
			t.ground_color = Color(0.32, 0.33, 0.30)
			t.wall_color = Color(0.42, 0.38, 0.34)
			t.obstacle_color = Color(0.38, 0.36, 0.33)
	t.obstacle_entries = [
		{"type": "pillar", "weight": 3.0, "size": 1},
		{"type": "rubble", "weight": 2.0, "size": 1},
		{"type": "crate", "weight": 2.0, "size": 1}] as Array[Dictionary]
	t.mob_mix = mob_mix_for(danger)
	t.hp_scale = 1.0 + 0.25 * float(danger)
	t.dmg_scale = 1.0 + 0.15 * float(danger)
	var floors := int(record.get("floors", 1))
	if floor_idx == floors - 1:
		t.boss_id = boss_for(danger)
	t.puzzle_key_count = 2
	return t
