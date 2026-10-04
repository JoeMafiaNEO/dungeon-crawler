extends Node
## SaveManager: persists player progress, meta unlocks, and settings.
## Uses user://savegame.cfg (ConfigFile). Steam Auto-Cloud can sync this.

const SAVE_PATH := "user://savegame.cfg"
const SETTINGS_PATH := "user://settings.cfg"

# Meta progression: unlocks that broaden (not flatten).
# - unlocked_items: Array[String] of item IDs added to drop pool
# - unlocked_classes: Array[String] (future class variants)
# - total_runs: int
# - total_kills: int
# - deepest_cycle: int
# - total_cash_earned: int (supermarket)

var _save := ConfigFile.new()
var _settings := ConfigFile.new()


func _ready() -> void:
	load_game()
	load_settings()


func load_game() -> void:
	var err := _save.load(SAVE_PATH)
	if err != OK:
		# Fresh save with defaults.
		_save.set_value("meta", "unlocked_items", [])
		_save.set_value("meta", "total_runs", 0)
		_save.set_value("meta", "total_kills", 0)
		_save.set_value("meta", "deepest_cycle", 0)
		_save.set_value("meta", "total_cash_earned", 0)
		_save.set_value("meta", "unlocked_achievements", [])


func save_game() -> void:
	_save.save(SAVE_PATH)


func load_settings() -> void:
	_settings.load(SETTINGS_PATH)


func save_settings() -> void:
	_settings.save(SETTINGS_PATH)


# --- Meta progression ---

func get_unlocked_items() -> Array:
	return _save.get_value("meta", "unlocked_items", [])


## All unlocked achievement IDs.
func get_unlocked_achievements() -> Array:
	return _save.get_value("meta", "unlocked_achievements", [])


func unlock_item(item_id: String) -> bool:
	var unlocked: Array = get_unlocked_items()
	if item_id in unlocked:
		return false
	unlocked.append(item_id)
	_save.set_value("meta", "unlocked_items", unlocked)
	save_game()
	return true


func is_item_unlocked(item_id: String) -> bool:
	return item_id in get_unlocked_items()


func add_run() -> void:
	_save.set_value("meta", "total_runs", get_total_runs() + 1)
	save_game()


func get_total_runs() -> int:
	return int(_save.get_value("meta", "total_runs", 0))


func add_kills(count: int) -> void:
	_save.set_value("meta", "total_kills", get_total_kills() + count)
	save_game()


func get_total_kills() -> int:
	return int(_save.get_value("meta", "total_kills", 0))


func set_deepest_cycle(cycle: int) -> void:
	if cycle > get_deepest_cycle():
		_save.set_value("meta", "deepest_cycle", cycle)
		save_game()


func get_deepest_cycle() -> int:
	return int(_save.get_value("meta", "deepest_cycle", 0))


func add_cash_earned(amount: int) -> void:
	_save.set_value("meta", "total_cash_earned", get_total_cash_earned() + amount)
	save_game()


func get_total_cash_earned() -> int:
	return int(_save.get_value("meta", "total_cash_earned", 0))


# --- Achievements & Meta Unlocks ---
# Broaden (new items/builds), not flatten (no raw stats).

const ACHIEVEMENTS := [
	{"id": "kill_100", "name": "Slayer", "desc": "Kill 100 mobs", "item": "void_blade", "check": "kills", "threshold": 100},
	{"id": "cycle_2", "name": "Explorer", "desc": "Reach Cycle 2", "item": "phoenix_feather", "check": "cycle", "threshold": 2},
	{"id": "cash_1000", "name": "Entrepreneur", "desc": "Earn $1000 at MegaMart", "item": "storm_caller", "check": "cash", "threshold": 1000},
]


func check_achievements() -> Array:
	# Returns list of newly unlocked achievement IDs.
	var unlocked := []
	var done: Array = _save.get_value("meta", "unlocked_achievements", [])
	for a in ACHIEVEMENTS:
		if a["id"] in done:
			continue
		var progress := 0
		match a["check"]:
			"kills":
				progress = get_total_kills()
			"cycle":
				progress = get_deepest_cycle()
			"cash":
				progress = get_total_cash_earned()
		if progress >= a["threshold"]:
			done.append(a["id"])
			unlocked.append(a["id"])
			unlock_item(a["item"])
	if not unlocked.is_empty():
		_save.set_value("meta", "unlocked_achievements", done)
		save_game()
	return unlocked


func get_achievement_progress(ach_id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a["id"] == ach_id:
			var progress := 0
			match a["check"]:
				"kills":
					progress = get_total_kills()
				"cycle":
					progress = get_deepest_cycle()
				"cash":
					progress = get_total_cash_earned()
			return {"name": a["name"], "desc": a["desc"], "progress": progress, "threshold": a["threshold"], "done": progress >= a["threshold"]}
	return {}


# --- Settings ---

func get_setting(section: String, key: String, default = null):
	return _settings.get_value(section, key, default)


func set_setting(section: String, key: String, value) -> void:
	_settings.set_value(section, key, value)
	save_settings()


# --- Run saves (save points) ---
# Multiplayer saves live in RUN_SAVE_PATH (host-only, single slot).
# Solo saves are per-class: user://solo_<class_id>.cfg — so each class
# keeps its own run and you can swap freely from the menu.
# A run save captures everything needed to resume later:
# {theme_id, level_number, class_id, player_state, saved_at}.
# Auto-saved on every level transition; cleared on death.

const RUN_SAVE_PATH := "user://run_save.cfg"
const SOLO_SAVE_PATTERN := "user://solo_%s.cfg"
const SOLO_CLASSES: Array[String] = ["warrior", "rogue", "mage", "architect"]
## Save format version. Continue refuses saves with a mismatched version.
const SAVE_VERSION := 1


## Path for a run: multiplayer -> shared slot, solo -> per-class slot.
func _save_path_for(run: Dictionary) -> String:
	if bool(run.get("is_multiplayer", false)):
		return RUN_SAVE_PATH
	return SOLO_SAVE_PATTERN % str(run.get("class_id", "warrior"))


func save_run(run: Dictionary) -> void:
	var cfg := ConfigFile.new()
	var data := run.duplicate(true)
	data["saved_at"] = Time.get_datetime_string_from_system()
	data["save_version"] = SAVE_VERSION
	cfg.set_value("run", "data", data)
	var path := _save_path_for(run)
	# Atomic write: save to temp, then rename.
	var tmp_path := path + ".tmp"
	if cfg.save(tmp_path) == OK:
		DirAccess.rename_absolute(tmp_path, path)


## Load a run. class_id "" = multiplayer slot; otherwise that class's solo save.
func load_run(class_id: String = "") -> Dictionary:
	_migrate_legacy_save()
	var path := RUN_SAVE_PATH if class_id == "" else SOLO_SAVE_PATTERN % class_id
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var data = cfg.get_value("run", "data", {})
	return data if data is Dictionary else {}


func has_run(class_id: String = "") -> bool:
	return not load_run(class_id).is_empty()


func clear_run(class_id: String = "") -> void:
	var path := RUN_SAVE_PATH if class_id == "" else SOLO_SAVE_PATTERN % class_id
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## All per-class solo saves: [{class_id, run}].
func list_solo_saves() -> Array:
	_migrate_legacy_save()
	var out: Array = []
	for cid in SOLO_CLASSES:
		var run := load_run(cid)
		if not run.is_empty():
			out.append({"class_id": cid, "run": run})
	return out


## One-time migration: an old single-slot solo save moves to its class file.
func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(RUN_SAVE_PATH):
		return
	var cfg := ConfigFile.new()
	if cfg.load(RUN_SAVE_PATH) != OK:
		return
	var data = cfg.get_value("run", "data", {})
	if not (data is Dictionary):
		return
	if bool(data.get("is_multiplayer", false)):
		return  # already the multiplayer slot
	var cid := str(data.get("class_id", "warrior"))
	var dest := SOLO_SAVE_PATTERN % cid
	if FileAccess.file_exists(dest):
		return  # don't clobber an existing per-class save
	DirAccess.rename_absolute(RUN_SAVE_PATH, dest)


## Human-readable summary for the main menu Continue button.
## Pass a run dict, or a class_id ("" = multiplayer slot).
func run_summary(run_or_class: Variant = "") -> String:
	var run: Dictionary = {}
	if run_or_class is Dictionary:
		run = run_or_class
	else:
		run = load_run(str(run_or_class))
	if run.is_empty():
		return ""
	var theme_id := str(run.get("theme_id", "village"))
	var theme_name := theme_id.capitalize()
	# Friendly theme names.
	match theme_id:
		"village":
			theme_name = "Village Outskirts"
		"dungeon":
			theme_name = "The Dungeon"
		"depths":
			theme_name = "The Depths"
		"supermarket":
			theme_name = "MegaMart Supermarket"
		"warlord":
			theme_name = "Warlord's Domain"
	if bool(run.get("is_multiplayer", false)):
		var roster: Array = run.get("roster", [])
		var names: Array = []
		for entry in roster:
			var ps2: Dictionary = entry.get("player_state", {})
			names.append("%s %d" % [str(entry.get("class_id", "?")).capitalize(), int(ps2.get("level", 1))])
		return "%d players (%s) · %s · Level %d" % [roster.size(), ", ".join(names), theme_name, int(run.get("level_number", 1))]
	var ps: Dictionary = run.get("player_state", {})
	var lvl := int(ps.get("level", 1))
	var class_id := str(run.get("class_id", "warrior")).capitalize()
	return "Lv %d %s · %s · Level %d" % [lvl, class_id, theme_name, int(run.get("level_number", 1))]


## True if the saved run's version matches the current format.
func is_save_compatible(class_id: String = "") -> bool:
	var run := load_run(class_id)
	if run.is_empty():
		return false
	return int(run.get("save_version", 0)) == SAVE_VERSION
