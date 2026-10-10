class_name MouseLegend
extends RefCounted
## Data-driven mouse-button legend registry (issue #95).
##
## Keyed by (state, class_id) -> {left, right, middle} label strings.
## New classes, new states (rogue charging, Holy Light armed/charging), and new
## abilities are added as DATA ROWS below — never UI code changes. The render
## path (hud.refresh_mouse_legend) reads this table and knows nothing about
## classes. Labels verified against scripts/player/player.gd _input.

## Phase 2 states: rogue dagger charge + Holy Light arm/charge (mage).
## Labels verified against scripts/player/player.gd _input (issue #91 v2).
const REGISTRY := {
	"standard": {
		"warrior": {"left": "Attack", "right": "", "middle": "Ping"},
		"mage": {"left": "Cast selected ability", "right": "", "middle": "Ping"},
		"rogue": {"left": "Attack", "right": "Hold: charge dagger throw", "middle": "Ping"},
		"architect": {"left": "Cast selected ability", "right": "", "middle": "Ping"},
	},
	"charging": {
		"rogue": {"left": "Throw dagger", "right": "Release: cancel", "middle": "Ping"},
	},
	"hl_armed": {
		"mage": {"left": "Start charge", "right": "Disarm", "middle": "Ping"},
	},
	"hl_charging": {
		"mage": {"left": "", "right": "Disarm (cancel)", "middle": "Ping"},
	},
}

## Fallback row for unknown classes (and unknown states fall back to standard).
const FALLBACK := {"left": "Attack", "right": "", "middle": "Ping"}


## Returns the {left, right, middle} label row for a class in a state.
## Unknown class -> FALLBACK; unknown state -> standard row for that class.
static func actions_for(class_id: String, state: String = "standard") -> Dictionary:
	var states: Dictionary = REGISTRY
	var table: Dictionary = states.get(state, states["standard"])
	var row: Dictionary = table.get(class_id, {})
	if row.is_empty():
		return FALLBACK.duplicate()
	return row


## All class_ids registered for a state (drives tests + future UI).
static func classes_for(state: String = "standard") -> Array:
	var states: Dictionary = REGISTRY
	var table: Dictionary = states.get(state, states["standard"])
	return table.keys()
