class_name StationTerminal
extends Area3D
## The GPS terminal on every train station platform
## (issue #244 T2, spec §3.2/§5): the interactable exists
## from T2 — E prompts at it like any world interactable —
## but the node chart it opens is T4; interact() is an
## inert stub until then.

var station_key := ""


func prompt_text() -> String:
	return "GPS terminal"


func interact(_player: Node) -> void:
	# T4: open the node chart (pan/zoom canvas; a course is
	# drafted by any rider, confirmed from aboard). Nothing
	# chart-side exists to open yet.
	pass
