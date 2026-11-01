class_name StationTerminal
extends Area3D
## A station's GPS terminal (issue #244 T2 build, T3
## summon wiring, T4 chart face). Interacting opens the
## node chart with this station's face (spec §5): the
## chart carries plotting plus the SUMMON (spec §4.4/F4)
## when the train stands idle at another station — the
## summon's server wiring is T3's, unchanged; T4 gives
## the terminal its chart face (the DM's T4 dispatch).

var station_key := ""


## Summonable = the train is idle somewhere else.
func _summonable() -> bool:
	var st := Dungeon.train_state
	if st.is_empty():
		return false
	return str(st.get("status", "")) == "idle" \
		and str(st.get("at", "")) != station_key


func prompt_text() -> String:
	if _summonable():
		return "Open GPS terminal (summon available)"
	return "Open GPS terminal"


func interact(_player: Player) -> void:
	(load("res://scripts/ui/train_chart.gd") as GDScript).call(
		"open_chart", "station", station_key)
