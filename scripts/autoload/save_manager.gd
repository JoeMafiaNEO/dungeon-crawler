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
# A run save captures everything needed to resume a solo run later:
# {theme_id, level_number, class_id, player_state, saved_at}.
# Auto-saved on every level transition; cleared on death.

const RUN_SAVE_PATH := "user://run_save.cfg"


func save_run(run: Dictionary) -> void:
	var cfg := ConfigFile.new()
	var data := run.duplicate(true)
	data["saved_at"] = Time.get_datetime_string_from_system()
	cfg.set_value("run", "data", data)
	# Atomic write: save to temp, then rename.
	var tmp_path := RUN_SAVE_PATH + ".tmp"
	if cfg.save(tmp_path) == OK:
		DirAccess.rename_absolute(tmp_path, RUN_SAVE_PATH)


func load_run() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_SAVE_PATH) != OK:
		return {}
	var data = cfg.get_value("run", "data", {})
	return data if data is Dictionary else {}


func has_run() -> bool:
	return not load_run().is_empty()


func clear_run() -> void:
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(RUN_SAVE_PATH)


## Human-readable summary for the main menu Continue button.
func run_summary() -> String:
	var run := load_run()
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
	var ps: Dictionary = run.get("player_state", {})
	var lvl := int(ps.get("level", 1))
	var class_id := str(run.get("class_id", "warrior")).capitalize()
	return "Lv %d %s · %s · Level %d" % [lvl, class_id, theme_name, int(run.get("level_number", 1))]
