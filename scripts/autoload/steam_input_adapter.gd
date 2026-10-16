extends Node
## Issue #150 (#144 Phase 5A): the Steam Input adapter. The ONLY
## place game code touches Steam Input APIs (via the backend below).
## When — and only when — a valid Steam session offers the full
## gameplay action set, this adapter becomes THE pad source: Steam
## action state is translated into the existing Phase 0/1 InputMap
## verb layer as joypad events on a reserved device, so every
## downstream read site (event dispatch, held-state polls, analog
## vectors, the gameplay_focused gate) consumes Steam input exactly
## like native pad input, with no second read sites and no Steam
## branches in gameplay code. While inactive, native pad input is
## byte-for-byte untouched.
##
## Fail-closed: activation requires Steam initialized, input init
## success, a connected controller, the gameplay action-set handle,
## and EVERY required action handle nonzero. Any failure leaves
## native in sole control (today, with no HinterGald configuration
## published in Steamworks, handles do not resolve — a Steam player
## still gets the working native path, never a dead pad).
##
## Arbitration: on activation, every joypad binding in the verb
## vocabulary is swapped for a copy on SENTINEL_DEVICE (the
## adapter's own injected events); native joypad events then match
## nothing and cannot double-fire a verb. On deactivation the
## original binding objects are restored exactly.
##
## runFrame ownership: the adapter initializes Steam Input with
## explicitly_call_runframe = true and calls run_frame() itself at
## the top of every active physics tick (this autoload runs at
## physics priority -100, ahead of gameplay nodes), so Steam state
## is refreshed before the player's dispatch and polls consume it
## in the same tick. SteamManager's run_callbacks keeps serving
## everything else.

const SET_NAME := "gameplay"
const ANALOG_ACTIONS: Array[String] = ["move", "look"]
const DIGITAL_ACTIONS: Array[String] = [
	"jump", "attack", "alt_attack", "interact", "dash", "cycle_ability",
	"ability", "start_wave", "potion", "inventory", "pause", "ping",
	"toggle_rod", "build_menu",
]
## Every action whose joypad bindings the arbitration swap covers
## (the full Phase 0/1 vocabulary; ability_1..7 and signature_ability
## carry no joypad bindings — Q6 — and are no-ops here).
const VOCABULARY: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"look_left", "look_right", "look_up", "look_down",
	"jump", "attack", "alt_attack", "interact", "dash", "cycle_ability",
	"ability", "start_wave", "potion", "inventory", "pause", "ping",
	"toggle_rod", "build_menu",
	"ability_1", "ability_2", "ability_3", "ability_4", "ability_5",
	"ability_6", "ability_7", "signature_ability",
]
## Reserved joypad device id for adapter-injected events. Physical
## pads report small indices; bindings copied onto this device can
## only ever be matched by the adapter.
const SENTINEL_DEVICE := 7
## Injection shapes for the digital actions, mirroring the Phase 1
## pad map (and the manifest's default-bindings table): "btn" =
## joypad button, "trig" = trigger axis treated as a button.
const INJECT := {
	"jump": ["btn", JOY_BUTTON_A],
	"attack": ["trig", JOY_AXIS_TRIGGER_RIGHT],
	"alt_attack": ["trig", JOY_AXIS_TRIGGER_LEFT],
	"interact": ["btn", JOY_BUTTON_X],
	"dash": ["btn", JOY_BUTTON_LEFT_STICK],
	"cycle_ability": ["btn", JOY_BUTTON_LEFT_SHOULDER],
	"ability": ["btn", JOY_BUTTON_Y],
	"start_wave": ["btn", JOY_BUTTON_DPAD_UP],
	"potion": ["btn", JOY_BUTTON_DPAD_DOWN],
	"inventory": ["btn", JOY_BUTTON_BACK],
	"pause": ["btn", JOY_BUTTON_START],
	"ping": ["btn", JOY_BUTTON_RIGHT_STICK],
	"toggle_rod": ["btn", JOY_BUTTON_DPAD_LEFT],
	"build_menu": ["btn", JOY_BUTTON_DPAD_RIGHT],
}

var backend: RefCounted
var active := false
## Diagnostic record of injected digital edges ([action, pressed]),
## newest last, capped. The suite asserts exactly-once edges here;
## the Input action states prove the edges land.
var emitted: Array = []

var _controller := 0
var _set_handle := 0
var _input_inited := false
var _handles: Dictionary = {}
var _digital_state: Dictionary = {}
var _saved_bindings: Dictionary = {}
var _sentinel_bindings: Dictionary = {}
var _retry_t := 0.0
var _retry_interval := 0.5


## The real Steam backend: every Steam Input call in the game goes
## through this class (and only here). Each call guards on the Steam
## singleton existing; session_ready additionally requires
## SteamManager's initialized flag, the codebase pattern. Absent
## Steam = safe defaults, zero errors.
class SteamBackend:
	extends RefCounted

	func _steam() -> Object:
		return Engine.get_singleton("Steam")

	func session_ready() -> bool:
		if _steam() == null:
			return false
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return false
		var sm := tree.root.get_node_or_null("SteamManager")
		return sm != null and bool(sm.get("initialized"))

	func set_manifest_path(path: String) -> bool:
		var s := _steam()
		return s != null and bool(s.setInputActionManifestFilePath(path))

	func input_init() -> bool:
		var s := _steam()
		return s != null and bool(s.inputInit(true))

	func input_shutdown() -> void:
		var s := _steam()
		if s != null:
			s.inputShutdown()

	func run_frame() -> void:
		var s := _steam()
		if s != null:
			s.runFrame()

	func connected_controllers() -> Array:
		var s := _steam()
		return s.getConnectedControllers() if s != null else []

	func action_set_handle(set_name: String) -> int:
		var s := _steam()
		return int(s.getActionSetHandle(set_name)) if s != null else 0

	func digital_handle(action_name: String) -> int:
		var s := _steam()
		return int(s.getDigitalActionHandle(action_name)) if s != null else 0

	func analog_handle(action_name: String) -> int:
		var s := _steam()
		return int(s.getAnalogActionHandle(action_name)) if s != null else 0

	func activate_action_set(controller: int, set_handle: int) -> void:
		var s := _steam()
		if s != null:
			s.activateActionSet(controller, set_handle)

	func digital_data(controller: int, handle: int) -> Dictionary:
		var s := _steam()
		if s == null:
			return {}
		var d = s.getDigitalActionData(controller, handle)
		return d if d is Dictionary else {}

	func analog_data(controller: int, handle: int) -> Dictionary:
		var s := _steam()
		if s == null:
			return {}
		var d = s.getAnalogActionData(controller, handle)
		return d if d is Dictionary else {}

	func digital_origins(controller: int, set_handle: int, handle: int) -> Array:
		var s := _steam()
		return s.getDigitalActionOrigins(controller, set_handle, handle) if s != null else []

	func analog_origins(controller: int, set_handle: int, handle: int) -> Array:
		var s := _steam()
		return s.getAnalogActionOrigins(controller, set_handle, handle) if s != null else []

	func glyph_for_origin(origin: int) -> String:
		var s := _steam()
		return str(s.getGlyphForActionOrigin(origin)) if s != null else ""

	func string_for_origin(origin: int) -> String:
		var s := _steam()
		return str(s.getStringForActionOrigin(origin)) if s != null else ""

	func show_binding_panel(controller: int) -> bool:
		var s := _steam()
		return s != null and bool(s.showBindingPanel(controller))


func _ready() -> void:
	process_physics_priority = -100
	if backend == null:
		backend = SteamBackend.new()


## Test seam: swap the backend (the suite drives a fake). An active
## session is wound down first so no state leaks across the swap.
func set_backend(b: RefCounted) -> void:
	if active:
		deactivate("backend swap")
	backend = b


func _process(delta: float) -> void:
	if active:
		return
	_retry_t += delta
	if _retry_t >= _retry_interval:
		_retry_t = 0.0
		try_activate()


func _physics_process(_delta: float) -> void:
	if active:
		tick()


## Attempt activation. Fails closed at every step; returns whether
## the adapter is active afterwards.
func try_activate() -> bool:
	if active:
		return true
	if backend == null or not backend.session_ready():
		return false
	if not _input_inited:
		# Dev override: point Steam at the loose manifest before init
		# (editor/dev runs, or the depot file beside the build).
		var mp := _dev_manifest_path()
		if mp != "":
			backend.set_manifest_path(mp)
		if not backend.input_init():
			return false
		_input_inited = true
	var ctrls: Array = backend.connected_controllers()
	if ctrls.is_empty():
		return false # input stays initialized; waiting on a pad
	var set_h: int = backend.action_set_handle(SET_NAME)
	if set_h == 0:
		return _fail_handles()
	var handles: Dictionary = {}
	for name in DIGITAL_ACTIONS:
		var h: int = backend.digital_handle(name)
		if h == 0:
			return _fail_handles()
		handles[name] = h
	for name in ANALOG_ACTIONS:
		var h: int = backend.analog_handle(name)
		if h == 0:
			return _fail_handles()
		handles[name] = h
	_controller = int(ctrls[0]) # FIRST connected controller only
	_set_handle = set_h
	backend.activate_action_set(_controller, set_h)
	_handles = handles
	_swap_bindings()
	active = true
	_retry_interval = 0.5
	print("[SteamInputAdapter] Steam Input active (controller %d) — pad source: Steam" % _controller)
	return true


func _fail_handles() -> bool:
	# No (or partial) configuration published: shut input back down
	# and retry slowly. Native stays in sole control throughout.
	backend.input_shutdown()
	_input_inited = false
	_retry_interval = 10.0
	return false


## Wind the Steam session down: release every held action, zero the
## axes, restore the native bindings exactly. Input stays
## initialized so a reconnecting pad re-activates without churn.
func deactivate(reason: String) -> void:
	if not active:
		return
	for name in DIGITAL_ACTIONS:
		if bool(_digital_state.get(name, false)):
			_inject_digital(name, false)
	_digital_state.clear()
	_inject_axis(JOY_AXIS_LEFT_X, 0.0)
	_inject_axis(JOY_AXIS_LEFT_Y, 0.0)
	_inject_axis(JOY_AXIS_RIGHT_X, 0.0)
	_inject_axis(JOY_AXIS_RIGHT_Y, 0.0)
	Input.flush_buffered_events()
	_restore_bindings()
	active = false
	_controller = 0
	_set_handle = 0
	_handles.clear()
	print("[SteamInputAdapter] Steam Input inactive (%s) — pad source: native" % reason)


## One refresh-and-translate step (the ordering contract: run_frame
## first, then reads, then injected events flushed — all before any
## gameplay physics in the same tick via priority -100).
func tick() -> void:
	if not active:
		return
	backend.run_frame()
	if not backend.connected_controllers().has(_controller):
		deactivate("controller disconnected")
		return
	for name in DIGITAL_ACTIONS:
		var d: Dictionary = backend.digital_data(_controller, int(_handles[name]))
		var st := bool(d.get("state", false))
		if st != bool(_digital_state.get(name, false)):
			_digital_state[name] = st
			_inject_digital(name, st)
	var mv: Dictionary = backend.analog_data(_controller, int(_handles["move"]))
	_inject_axis(JOY_AXIS_LEFT_X, float(mv.get("x", 0.0)))
	_inject_axis(JOY_AXIS_LEFT_Y, float(mv.get("y", 0.0)))
	var lk: Dictionary = backend.analog_data(_controller, int(_handles["look"]))
	_inject_axis(JOY_AXIS_RIGHT_X, float(lk.get("x", 0.0)))
	_inject_axis(JOY_AXIS_RIGHT_Y, float(lk.get("y", 0.0)))
	Input.flush_buffered_events()


func _inject_digital(action_name: String, pressed: bool) -> void:
	var spec: Array = INJECT[action_name]
	if spec[0] == "btn":
		var ev := InputEventJoypadButton.new()
		ev.button_index = int(spec[1])
		ev.pressed = pressed
		ev.device = SENTINEL_DEVICE
		Input.parse_input_event(ev)
	else:
		var ev := InputEventJoypadMotion.new()
		ev.axis = int(spec[1])
		ev.axis_value = 1.0 if pressed else 0.0
		ev.device = SENTINEL_DEVICE
		Input.parse_input_event(ev)
	emitted.append([action_name, pressed])
	if emitted.size() > 128:
		emitted.pop_front()


func _inject_axis(axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	ev.device = SENTINEL_DEVICE
	Input.parse_input_event(ev)


func _swap_bindings() -> void:
	_saved_bindings.clear()
	_sentinel_bindings.clear()
	for action_name in VOCABULARY:
		var joy: Array = []
		for e in InputMap.action_get_events(action_name):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				joy.append(e)
		if joy.is_empty():
			continue
		_saved_bindings[action_name] = joy
		var sent: Array = []
		for e in joy:
			InputMap.action_erase_event(action_name, e)
			var d: InputEvent = e.duplicate()
			d.device = SENTINEL_DEVICE
			InputMap.action_add_event(action_name, d)
			sent.append(d)
		_sentinel_bindings[action_name] = sent


func _restore_bindings() -> void:
	for action_name in _sentinel_bindings.keys():
		for d in _sentinel_bindings[action_name]:
			InputMap.action_erase_event(action_name, d)
		for e in _saved_bindings[action_name]:
			InputMap.action_add_event(action_name, e)
	_sentinel_bindings.clear()
	_saved_bindings.clear()


func _dev_manifest_path() -> String:
	var candidates := [
		ProjectSettings.globalize_path("res://steam_input/hintergald_actions.vdf"),
		OS.get_executable_path().get_base_dir().path_join("steam_input/hintergald_actions.vdf"),
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""


# --- Glyph / binding interface (API only — Phase 3 owns prompts) ---

## The controller origin currently bound to an action (0 = none).
func binding_origin_for(action_name: String) -> int:
	if not active or not _handles.has(action_name):
		return 0
	var origins: Array
	if DIGITAL_ACTIONS.has(action_name):
		origins = backend.digital_origins(_controller, _set_handle, int(_handles[action_name]))
	else:
		origins = backend.analog_origins(_controller, _set_handle, int(_handles[action_name]))
	return int(origins[0]) if not origins.is_empty() else 0


## Steam's glyph asset path for the action's current binding.
func glyph_path_for(action_name: String) -> String:
	var origin := binding_origin_for(action_name)
	return backend.glyph_for_origin(origin) if origin != 0 else ""


## Steam's short label for the action's current binding origin.
func origin_label_for(action_name: String) -> String:
	var origin := binding_origin_for(action_name)
	return backend.string_for_origin(origin) if origin != 0 else ""


## Open Steam's binding panel for the active controller.
func show_binding_panel() -> bool:
	return backend.show_binding_panel(_controller) if active else false
