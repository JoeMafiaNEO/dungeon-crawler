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
	# Issue #126 Phase 3: rod-out contexts (player.legend_state picks
	# the state from the session mirrors + an aim probe). The left
	# slot carries Cast / the aim guidance / the hook call; the right
	# slot carries Reel in while a bobber is out.
	"fishing_ready": {
		"warrior": {"left": "Cast", "right": "", "middle": "Ping"},
		"mage": {"left": "Cast", "right": "", "middle": "Ping"},
		"rogue": {"left": "Cast", "right": "", "middle": "Ping"},
		"architect": {"left": "Cast", "right": "", "middle": "Ping"},
	},
	"fishing_aim": {
		"warrior": {"left": "Aim at water", "right": "", "middle": "Ping"},
		"mage": {"left": "Aim at water", "right": "", "middle": "Ping"},
		"rogue": {"left": "Aim at water", "right": "", "middle": "Ping"},
		"architect": {"left": "Aim at water", "right": "", "middle": "Ping"},
	},
	"fishing_wait": {
		"warrior": {"left": "", "right": "Reel in", "middle": "Ping"},
		"mage": {"left": "", "right": "Reel in", "middle": "Ping"},
		"rogue": {"left": "", "right": "Reel in", "middle": "Ping"},
		"architect": {"left": "", "right": "Reel in", "middle": "Ping"},
	},
	"fishing_hook": {
		"warrior": {"left": "Hook!", "right": "", "middle": "Ping"},
		"mage": {"left": "Hook!", "right": "", "middle": "Ping"},
		"rogue": {"left": "Hook!", "right": "", "middle": "Ping"},
		"architect": {"left": "Hook!", "right": "", "middle": "Ping"},
	},
	# Issue #113 Phase 3: architect with the Field Wrench equipped near a
	# damaged friendly repairable (player.legend_state picks the state).
	# The right slot carries the hold-E context line, same pattern as the
	# fishing rows.
	"repair_ready": {
		"architect": {"left": "Cast selected ability", "right": "Hold {interact} — Repair", "middle": "Ping"},
	},
}

## Issue #152 (2A-2): the slots are ACTION slots — the renderer
## (hud.refresh_mouse_legend) captions each slot with the current
## source's label for its action via PromptText.glyph(). Every state
## uses the default mapping (left = attack, right = alt_attack,
## middle = ping) except repair_ready, whose right slot is the
## interact hold, not alt_attack.
const DEFAULT_SLOT_ACTIONS := {"left": "attack", "right": "alt_attack", "middle": "ping"}
const SLOT_ACTIONS := {
	"repair_ready": {"left": "attack", "right": "interact", "middle": "ping"},
}


## The {left, right, middle} action names for a state's slots.
static func slot_actions_for(state: String = "standard") -> Dictionary:
	var table: Dictionary = SLOT_ACTIONS
	return table.get(state, DEFAULT_SLOT_ACTIONS)

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
