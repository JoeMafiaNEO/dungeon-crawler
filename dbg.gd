extends SceneTree
func _init() -> void:
	var theme: LevelTheme = load("res://data/levels/theme_village.tres")
	var a: LevelLayout = ProcGen.generate(theme, 12345)
	var c: LevelLayout = ProcGen.generate(theme, 99999)
	print("floors A:", a.floors.size(), " C:", c.floors.size())
	print("props A:", a.props.size(), " C:", c.props.size())
	var ra: Rect2 = a.floors[0]["rect"]
	var rc: Rect2 = c.floors[0]["rect"]
	print("A0:", ra, " C0:", rc)
	quit()
