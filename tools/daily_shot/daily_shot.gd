extends SceneTree
## Xvfb driver: renders the Daily leaderboard phase at 1920x1080.
## Uses a scratch user:// profile; restores nothing because it never
## touches the real shared files (runs with --user-dir override).

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await create_timer(0.5).timeout
	# Seed representative top-10 rows so the panel renders populated.
	var lb: Node = root.get_node("Leaderboard")
	var cache: Dictionary = lb.get("_cache")
	var depth: Array = []
	var speed: Array = []
	var names := ["RogueRin", "MageMarco", "WarlordWes", "Slimer", "ArchitectAl",
		"DailyDana", "SpeedSam", "Crawler", "Torchbearer", "Me"]
	for i in range(10):
		depth.append({"rank": i + 1, "name": names[i],
			"score": (10 - i) * 100000 + (10 - i), "is_player": i == 9})
		speed.append({"rank": i + 1, "name": names[9 - i],
			"score": 300 + i * 47, "is_player": i == 2})
	cache["daily_depth"] = depth
	cache["daily_speed"] = speed
	menu._refresh_daily_ui()
	menu._show_phase("DailyPhase")
	await create_timer(1.0).timeout
	var vp := root.get_viewport()
	var img := vp.get_texture().get_image()
	img.save_png("/tmp/daily_leaderboard.png")
	print("saved /tmp/daily_leaderboard.png")
	quit()
