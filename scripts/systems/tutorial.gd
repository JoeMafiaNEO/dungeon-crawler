extends Node
## Tutorial: contextual first-run hints.
## Shows one-time hints based on player actions. Dismisses permanently.

## Issue #152 (2A-2): hint texts carry PromptText action tokens —
## render through PromptText.resolve() at display time so pad
## players see pad labels. The KB rendering is byte-identical to
## the pre-token strings.
const HINTS := [
	{"id": "move", "text": "{move} to move, {look} to look. {attack_phrase} to attack.", "trigger": "spawn"},
	{"id": "pickup", "text": "Press {interact} near glowing loot to pick it up.", "trigger": "near_loot"},
	{"id": "inventory", "text": "Press {inventory} to open inventory. {choose} items to use them.", "trigger": "first_loot"},
	{"id": "wave", "text": "Survive all waves. Host presses START NEXT WAVE.", "trigger": "wave1"},
	{"id": "keys", "text": "Find keys to clear the level. Check the HUD for key count.", "trigger": "keys_remaining"},
	{"id": "dash", "text": "Press {dash} to dash (brief invincibility).", "trigger": "first_damage"},
	{"id": "ping", "text": "Press {ping} to ping a location for your team.", "trigger": "multiplayer"},
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
