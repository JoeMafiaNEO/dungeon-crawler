extends Node3D
## Issue #185 (Mason's Vault P2): one vault mechanism — a wheel,
## a door, a carry tablet/stone, a socket, a weigh stone, or a
## pressure plate. The node is presentation + the ordinary
## E-interact only: ALL state lives in the VaultDirector
## (server-authoritative); this node asks the director for its
## mirrored state to render and to phrase its prompt, and routes
## interacts to the director, which validates on the server and
## syncs the outcome to every peer.
##
## Built by VaultLayout with an authored key + def; registered
## in the "vault_mechanisms" group (the player's interact scan).

var mech_key := ""
var kind := ""
var def: Dictionary = {}

var _panel: MeshInstance3D = null
var _body: StaticBody3D = null
var _label: Label3D = null
var _ring: MeshInstance3D = null
var _arm: MeshInstance3D = null
var _fill_visual: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _home_pos := Vector3.ZERO
var _pan_pos := Vector3.ZERO


func setup(p_key: String, p_def: Dictionary) -> void:
	mech_key = p_key
	def = p_def
	kind = str(p_def.get("kind", ""))
	# Statues and plain doors are not interactables: they stay
	# out of the scan group so they never shadow a real
	# mechanism. (Wheel doors ARE tryable — the door interact
	# tests whether its letters read the decoded word.)
	var tryable := def.has("wheel") or def.has("wheels")
	if kind != "statue" and (kind != "door" or tryable):
		add_to_group("vault_mechanisms")
	_build_visuals()


func _director() -> Node:
	return get_tree().get_first_node_in_group("vault_director")


func _state() -> Dictionary:
	var d := _director()
	if d != null and d.has_method("mech_state"):
		return d.call("mech_state", mech_key)
	return {}


func prompt_text() -> String:
	match kind:
		"wheel":
			return "Turn the wheel"
		"door":
			return "Open the door"
		"door_try":
			return "Try the door"
		"tablet":
			return "Take the tablet"
		"socket":
			return "Place the tablet"
		"stone":
			return "Take the %s stone" % str(def.get("letter", "?"))
		"lsocket":
			return "Place the stone"
		"wstone":
			if bool(_state().get("on_pan", false)):
				return "Take the %d-weight off the pan" % int(def.get("weight", 0))
			return "Put the %d-weight on the pan" % int(def.get("weight", 0))
		"plate":
			return "Press the plate"
		"rite_stone":
			return "Sound the word-stone"
		"lever":
			return "Pull the departure lever"
	return ""


func interact(player: Node) -> void:
	var d := _director()
	if d != null and d.has_method("request_interact"):
		d.call("request_interact", mech_key, player)


# --- Visual state (driven by the director's sync) ---

func apply_state(state: Dictionary) -> void:
	match kind:
		"wheel":
			if _ring != null:
				_ring.rotation.z = -float(int(state.get("pos", 0))) * TAU / 26.0
		"door", "door_try":
			var open := bool(state.get("open", false))
			if _panel != null:
				_panel.visible = not open
			if _body != null:
				_body.collision_layer = 0 if open else 1
			if _label != null and state.has("display"):
				_label.text = str(state["display"])
		"tablet", "stone":
			visible = str(state.get("state", "pedestal")) == "pedestal"
		"socket", "lsocket":
			if _fill_visual != null:
				_fill_visual.visible = bool(state.get("filled", false))
		"wstone":
			position = _pan_pos if bool(state.get("on_pan", false)) else _home_pos
		"plate":
			if _mat != null:
				# A rung plate keeps a soft gold emission; an unrung
				# one is plain stone.
				_mat.emission_enabled = bool(state.get("rung", false))
		"statue":
			visible = not bool(state.get("woken", false))
		"rite_stone":
			# The word comes from the director's state (the
			# per-run permutation); a sung stone glows.
			if _label != null:
				_label.text = str(state.get("word", ""))
			if _mat != null:
				_mat.emission_enabled = bool(state.get("lit", false))
		"lever":
			if _mat != null:
				_mat.emission_enabled = bool(state.get("active", false))
			if _arm != null:
				_arm.rotation_degrees.x = -38.0 if bool(state.get("pulled", false)) else 0.0


# --- Construction (authored by VaultLayout's defs) ---

func _stone_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _mk_label(text: String, y: float, size: int = 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = Color(0.92, 0.90, 0.84)
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, y, 0)
	add_child(l)
	return l


func _mk_box(size: Vector3, pos: Vector3, mat: Material, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	if collide:
		_body = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		_body.add_child(cs)
		_body.position = pos
		add_child(_body)
	return mi


func _build_visuals() -> void:
	var stone := _stone_mat(Color(0.42, 0.40, 0.37))
	var dark := _stone_mat(Color(0.30, 0.28, 0.26))
	match kind:
		"wheel":
			_mk_box(Vector3(0.8, 1.1, 0.8), Vector3(0, 0.55, 0), dark)
			_ring = MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.42
			tor.outer_radius = 0.62
			tor.material = _stone_mat(Color(0.55, 0.48, 0.30))
			_ring.mesh = tor
			_ring.position = Vector3(0, 1.55, 0)
			add_child(_ring)
			# A notch marks the ring's reading point.
			_mk_box(Vector3(0.12, 0.22, 0.12), Vector3(0, 2.25, 0), dark)
		"door", "door_try":
			_panel = _mk_box(Vector3(3.0, 3.0, 0.3), Vector3(0, 1.5, 0),
				_stone_mat(Color(0.36, 0.33, 0.30)), true)
			if kind == "door_try":
				_label = _mk_label(str(def.get("lintel", "")), 3.6)
			else:
				_label = _mk_label("", 3.6)
		"tablet":
			_mk_box(Vector3(0.9, 0.9, 0.9), Vector3(0, 0.45, 0), dark)
			_mk_box(Vector3(0.62, 0.5, 0.14), Vector3(0, 1.12, 0), stone)
			_mk_label(str(def.get("word", "")), 1.8, 48)
		"socket":
			_mk_box(Vector3(0.9, 0.9, 0.9), Vector3(0, 0.45, 0), dark)
			_fill_visual = _mk_box(Vector3(0.62, 0.5, 0.14), Vector3(0, 1.12, 0), stone)
			_fill_visual.visible = false
		"stone":
			_mk_box(Vector3(0.44, 0.44, 0.44), Vector3(0, 0.22, 0), stone)
			_mk_label(str(def.get("letter", "")), 0.85, 48)
		"lsocket":
			_mk_box(Vector3(0.7, 0.5, 0.7), Vector3(0, 0.25, 0), dark)
			_fill_visual = _mk_box(Vector3(0.44, 0.44, 0.44), Vector3(0, 0.72, 0), stone)
			_fill_visual.visible = false
			_mk_label(str(def.get("letter", "")), 1.25, 48)
		"wstone":
			var w := int(def.get("weight", 1))
			var r := 0.16 + 0.045 * float(w)
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = r
			sm.height = r * 2.0
			sm.material = stone
			mi.mesh = sm
			mi.position = Vector3(0, r, 0)
			add_child(mi)
			_mk_label(str(w), 0.85, 48)
			_home_pos = Vector3(def.get("home_pos", Vector3.ZERO))
			_pan_pos = Vector3(def.get("pan_pos", Vector3.ZERO))
		"plate":
			_mat = _stone_mat(Color(0.38, 0.35, 0.32))
			_mat.emission = Color(0.85, 0.65, 0.25)
			_mat.emission_energy_multiplier = 1.2
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.55
			cm.bottom_radius = 0.6
			cm.height = 0.08
			cm.material = _mat
			mi.mesh = cm
			mi.position = Vector3(0, 0.04, 0)
			add_child(mi)
			# The floor inlay shows the order: this plate's step.
			_mk_label(str(def.get("step_roman", "")), 0.35, 40)
		"rite_stone":
			# A word-stone on a plinth; its label is set from the
			# director's state (the per-run permutation, #186).
			_mk_box(Vector3(0.9, 0.9, 0.9), Vector3(0, 0.45, 0), dark)
			_mat = _stone_mat(Color(0.48, 0.45, 0.40))
			_mat.emission = Color(0.95, 0.78, 0.35)
			_mat.emission_energy_multiplier = 1.4
			_panel = _mk_box(Vector3(0.66, 0.85, 0.14), Vector3(0, 1.35, 0), _mat)
			_label = _mk_label("", 2.05, 48)
		"lever":
			# The departure lever (#186): brass arm on a stone
			# base; it glows once the rite activates it.
			_mk_box(Vector3(0.8, 0.5, 0.8), Vector3(0, 0.25, 0), dark)
			_mat = _stone_mat(Color(0.55, 0.48, 0.30))
			_mat.emission = Color(0.95, 0.78, 0.35)
			_mat.emission_energy_multiplier = 1.2
			_arm = _mk_box(Vector3(0.14, 1.1, 0.14), Vector3(0, 1.0, 0), _mat)
		"statue":
			# A stone figure on a plinth (the mob's own sprite,
			# stone-tinted); the director hides it on wake.
			_mk_box(Vector3(0.9, 0.7, 0.9), Vector3(0, 0.35, 0), dark)
			var sp := Sprite3D.new()
			var tex: Texture2D = def.get("texture", null)
			if tex != null:
				sp.texture = tex
			sp.pixel_size = 0.0035
			sp.modulate = Color(0.55, 0.55, 0.60)
			sp.position = Vector3(0, 1.55, 0)
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(sp)
