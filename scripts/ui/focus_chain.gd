class_name FocusChain
extends RefCounted
## Shared focus chaining for pad menu navigation (issue #152, #144
## Phase 2A-1). ONE helper for every menu surface — main menu phases,
## HUD pause / inventory / popups — so pad navigation behaves the same
## everywhere:
##
## - chain_focus() links a control list in the given (visual) order
##   with wrap at both ends: focus_next / focus_previous plus all four
##   focus neighbors follow the chain, so Tab, Shift+Tab, RB/LB,
##   d-pad and the left stick all walk the same loop.
## - collect() gathers a surface's currently focusable controls in
##   tree order (= visual order for these layouts): visible in tree,
##   focus_mode not NONE, and not disabled (buttons) / locked
##   (LineEdit, Range).
## - apply() is the surface entry point: (re)collect + (re)chain, and
##   seed focus to the surface's primary control ONLY when the current
##   focus is dead — no owner, a freed control, or a control outside
##   this surface's chain. A live in-surface focus is never stolen,
##   which is what lets dynamic lists re-chain on every refresh while
##   the player keeps their place; a refresh that frees the focused
##   control re-seeds to the primary, per the spec.

static func is_focusable(c: Control) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	if c.focus_mode == Control.FOCUS_NONE:
		return false
	if not c.is_visible_in_tree():
		return false
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	if c is LineEdit and not (c as LineEdit).editable:
		return false
	if c is Range and not (c as Range).editable:
		return false
	return true


static func collect(surface: Node) -> Array:
	var out: Array = []
	_collect_into(surface, out)
	return out


static func _collect_into(node: Node, out: Array) -> void:
	if node is Control and is_focusable(node as Control):
		out.append(node)
	for child in node.get_children():
		_collect_into(child, out)


static func chain_focus(controls: Array) -> void:
	var n := controls.size()
	if n == 0:
		return
	for i in n:
		var c := controls[i] as Control
		var nx := controls[(i + 1) % n] as Control
		var pv := controls[(i - 1 + n) % n] as Control
		c.focus_next = c.get_path_to(nx)
		c.focus_previous = c.get_path_to(pv)
		c.focus_neighbor_right = c.get_path_to(nx)
		c.focus_neighbor_bottom = c.get_path_to(nx)
		c.focus_neighbor_left = c.get_path_to(pv)
		c.focus_neighbor_top = c.get_path_to(pv)


## Chain the surface and seed focus to `primary` (or the first
## focusable control) if focus is not already alive inside the chain.
static func apply(surface: Control, primary: Control = null) -> void:
	if surface == null or not is_instance_valid(surface):
		return
	var controls := collect(surface)
	chain_focus(controls)
	if controls.is_empty():
		return
	var vp := surface.get_viewport()
	if vp == null:
		return
	var owner := vp.gui_get_focus_owner()
	if owner != null and is_instance_valid(owner) and controls.has(owner):
		return
	var target: Control = primary if (primary != null and controls.has(primary)) else controls[0]
	target.grab_focus()
