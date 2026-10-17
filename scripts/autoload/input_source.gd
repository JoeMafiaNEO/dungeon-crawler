extends Node
## InputSource (issue #152, #144 Phase 2A): which device family produced
## the most recent input — keyboard/mouse or gamepad. Menu surfaces read
## it to decide how an interaction presents (2A-1, e.g. the departure
## board), and the 2A-2 PromptText resolver will render prompt strings
## from it. Live switching both ways; `changed` fires only on an actual
## switch.
##
## This service NEVER gates gameplay and is never consulted by the
## Phase 1 gate: player.gd's gameplay_focused() predicate is the only
## input gate and does not read this node. It observes input; it does
## not consume it (nothing here marks events handled).

enum Source { KB_MOUSE, PAD }

signal changed(source: Source)

## Joypad stick motion must exceed this before it counts as pad intent,
## so a drifting stick can't steal the source from the keyboard.
const STICK_DEADZONE := 0.35

var _current: Source = Source.KB_MOUSE


func current_source() -> Source:
	return _current


func is_pad() -> bool:
	return _current == Source.PAD


## Single write path (also the seam tests and tools drive directly).
func set_source(source: Source) -> void:
	if source == _current:
		return
	_current = source
	changed.emit(source)


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventMouseMotion:
		set_source(Source.KB_MOUSE)
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			set_source(Source.PAD)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > STICK_DEADZONE:
			set_source(Source.PAD)
