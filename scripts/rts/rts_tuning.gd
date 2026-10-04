class_name RTSTuning
extends RefCounted
## Single source of truth for Warlord's Domain balance numbers.
## Reads res://scripts/rts/rts_tuning.cfg once (lazy, on first access) and
## overlays it on the defaults baked into the scripts. Any key missing from
## the file falls back to the default passed by the caller, so a hand-edited
## file can never break the game — worst case, the default applies.

const PATH := "res://scripts/rts/rts_tuning.cfg"

static var _cfg: ConfigFile = null
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cfg = ConfigFile.new()
	var err := _cfg.load(PATH)
	if err != OK:
		push_warning("[RTSTuning] Could not load %s (err %d); using defaults." % [PATH, err])
		_cfg = null


## Force a reload (used by the sim harness after the file changes on disk).
static func reload() -> void:
	_loaded = false
	_cfg = null


static func get_float(section: String, key: String, default: float) -> float:
	_ensure_loaded()
	if _cfg != null and _cfg.has_section_key(section, key):
		return float(_cfg.get_value(section, key, default))
	return default


static func get_int(section: String, key: String, default: int) -> int:
	_ensure_loaded()
	if _cfg != null and _cfg.has_section_key(section, key):
		return int(_cfg.get_value(section, key, default))
	return default


static func get_array(section: String, key: String, default: Array) -> Array:
	_ensure_loaded()
	if _cfg != null and _cfg.has_section_key(section, key):
		var v = _cfg.get_value(section, key, default)
		if v is Array:
			return v
	return default


static func get_dict(section: String, key: String, default: Dictionary) -> Dictionary:
	_ensure_loaded()
	if _cfg != null and _cfg.has_section_key(section, key):
		var v = _cfg.get_value(section, key, default)
		if v is Dictionary:
			return v
	return default


## Cost dictionaries, e.g. get_cost("unit_costs", "catapult", RTSManager.UNIT_COSTS["catapult"]).
static func get_cost(section: String, key: String, default: Dictionary) -> Dictionary:
	return get_dict(section, key, default)


## Per-civ multiplier, e.g. get_civ_mult("iron_vanguard", "spearman_hp_mult", 1.3).
static func get_civ_mult(civ_id: String, key: String, default: float) -> float:
	var d := get_dict("civs", civ_id, {})
	if d.has(key):
		return float(d[key])
	return default


static func get_civ_int(civ_id: String, key: String, default: int) -> int:
	var d := get_dict("civs", civ_id, {})
	if d.has(key):
		return int(d[key])
	return default
