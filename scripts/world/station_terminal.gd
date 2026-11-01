class_name StationTerminal
extends Area3D
## A station's GPS terminal (issue #244 T2 build, T3
## wiring). The node chart is T4; T3 wires the SUMMON
## (spec §4.4/F4): when the train stands idle at another
## station, interacting here calls it in — it runs the
## route empty. When the train is here (board at the
## consist itself) or moving, the terminal is quiet.

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
		return "Summon train"
	return "GPS terminal"


func interact(_player: Player) -> void:
	if _summonable():
		NetworkManager.train_summon(station_key)
