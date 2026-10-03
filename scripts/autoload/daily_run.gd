extends Node
## DailyRun: seeded daily challenge runs.
## Each day gets a deterministic seed from the date. One attempt per day.
## Leaderboard is local (Steam leaderboards need App ID setup).

const DAILY_SAVE_KEY := "daily"


func get_today_seed() -> int:
	# Deterministic seed from today's date (YYYYMMDD).
	var dt := Time.get_datetime_dict_from_system()
	return dt["year"] * 10000 + dt["month"] * 100 + dt["day"]


func get_today_string() -> String:
	var dt := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [dt["year"], dt["month"], dt["day"]]


func has_attempted_today() -> bool:
	var last: String = str(SaveManager.get_setting(DAILY_SAVE_KEY, "last_attempt", ""))
	return last == get_today_string()


func record_attempt(score: int) -> void:
	# Record today's attempt. Score = cycle * 1000 + level * 10 + kills.
	SaveManager.set_setting(DAILY_SAVE_KEY, "last_attempt", get_today_string())
	SaveManager.set_setting(DAILY_SAVE_KEY, "last_score", score)
	# Update best.
	var best := get_best_score()
	if score > best:
		SaveManager.set_setting(DAILY_SAVE_KEY, "best_score", score)
		SaveManager.set_setting(DAILY_SAVE_KEY, "best_date", get_today_string())


func get_best_score() -> int:
	return int(SaveManager.get_setting(DAILY_SAVE_KEY, "best_score", 0))


func get_best_date() -> String:
	return str(SaveManager.get_setting(DAILY_SAVE_KEY, "best_date", "Never"))


func calculate_score(cycle: int, level: int, kills: int) -> int:
	return cycle * 1000 + level * 10 + kills
