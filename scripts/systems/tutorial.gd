extends Node
## Tutorial: contextual first-run hints.
## Shows one-time hints based on player actions. Dismisses permanently.

const HINTS := [
	{"id": "move", "text": "WASD to move, mouse to look. Left click to attack.", "trigger": "spawn"},
	{"id": "pickup", "text": "Press E near glowing loot to pick it up.", "trigger": "near_loot"},
	{"id": "inventory", "text": "Press I to open inventory. Click items to use them.", "trigger": "first_loot"},
	{"id": "wave", "text": "Survive all waves. Host presses START NEXT WAVE.", "trigger": "wave1"},
	{"id": "portal", "text": "Find keys to unlock the portal. Check the HUD for key count.", "trigger": "sealed_portal"},
	{"id": "dash", "text": "Press Shift to dash (brief invincibility).", "trigger": "first_damage"},
	{"id": "ping", "text": "Press G to ping a location for your team.", "trigger": "multiplayer"},
]

var _shown: Dictionary = {}


func _ready() -> void:
	var saved: Array = SaveManager.get_setting("tutorial", "seen_hints", [])
	for h in saved:
		_shown[h] = true


func should_show(hint_id: String) -> bool:
	return not _shown.get(hint_id, false)


func mark_shown(hint_id: String) -> void:
	_shown[hint_id] = true
	var saved: Array = SaveManager.get_setting("tutorial", "seen_hints", [])
	if hint_id not in saved:
		saved.append(hint_id)
		SaveManager.set_setting("tutorial", "seen_hints", saved)


func get_hint(hint_id: String) -> Dictionary:
	for h in HINTS:
		if h["id"] == hint_id:
			return h
	return {}
