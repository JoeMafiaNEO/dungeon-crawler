class_name FloorTransfer
extends Node3D
## A building floor's transfer surface (issue #205, P5):
## the elevator cab (floor panel), the stairwell doors, and
## the ground floor's street exit. Transfer-per-floor is the
## travel model under the cheat — there are no walkable
## in-world stairs. Every transfer is party-together (F0):
## the surface broadcasts and the whole party moves.
##
## The ACCESS RULE is enforced here, at the surface: the
## panel offers exactly the floors FloorGen.floor_allowed
## admits; the stair up admits the frontier and cleared
## floors only; the stair down always admits.

var mode := "cab" # cab | stair_up | stair_down | exit

var _panel: CanvasLayer = null


func _ready() -> void:
	add_to_group("floor_transfer")
	_build()


func prompt_text() -> String:
	match mode:
		"cab":
			return "Use elevator"
		"stair_up":
			return "Stairs up"
		"stair_down":
			return "Stairs down"
		"exit":
			return "Exit to street"
	return "Use"


func interact(player: Node) -> void:
	match mode:
		"cab":
			_toggle_panel(player)
		"stair_up":
			var mask := Dungeon.floor_mask()
			var floors := _floors()
			if FloorGen.floor_allowed(mask, floors,
					Dungeon.floor_index + 1):
				NetworkManager.rpc("load_floor",
					Dungeon.floor_key,
					Dungeon.floor_index + 1, false)
			elif player != null and player.get("hud") != null:
				player.hud.toast(
					"Sealed — clear the floors below first.")
		"stair_down":
			NetworkManager.rpc("load_floor", Dungeon.floor_key,
				Dungeon.floor_index - 1, false)
		"exit":
			NetworkManager.rpc("load_world_from_floor")


func _floors() -> int:
	var rec := FloorGen.record_for(Dungeon.floor_key)
	return int(rec.get("floors", 1))


## The cab's floor panel: one button per allowed floor
## (the access rule, as data) plus the street. Pure UI over
## the same broadcasts the doors use.
func panel_entries() -> Array:
	var out: Array = []
	var mask := Dungeon.floor_mask()
	var floors := _floors()
	for f in FloorGen.allowed_floors(mask, floors):
		out.append({"floor": f,
			"label": "Floor %d%s%s" % [f + 1,
				" — cleared" if (mask >> f) & 1 == 1 else "",
				" (here)" if f == Dungeon.floor_index else ""],
			"current": f == Dungeon.floor_index})
	out.append({"floor": -1, "label": "Street — exit building",
		"current": false})
	return out


func _toggle_panel(player: Node) -> void:
	if _panel != null:
		_close_panel()
		return
	_panel = CanvasLayer.new()
	_panel.layer = 20
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Elevator — choose a floor"
	box.add_child(title)
	for e in panel_entries():
		var b := Button.new()
		b.text = str(e["label"])
		b.disabled = bool(e["current"])
		var target := int(e["floor"])
		b.pressed.connect(func() -> void:
			_close_panel()
			if target >= 0:
				NetworkManager.rpc("load_floor",
					Dungeon.floor_key, target, false)
			else:
				NetworkManager.rpc("load_world_from_floor"))
		box.add_child(b)
	var close := Button.new()
	close.text = "Stay here"
	close.pressed.connect(_close_panel)
	box.add_child(close)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_panel() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


func _build() -> void:
	var frame := _mat(Color(0.30, 0.26, 0.20))
	var slab_col := Color(0.38, 0.30, 0.20)
	if mode == "cab":
		slab_col = Color(0.45, 0.42, 0.40) # brushed metal cab doors
	var slab := _mat(slab_col)
	_box(Vector3(0.18, 2.6, 0.24), Vector3(-0.85, 1.3, 0), frame)
	_box(Vector3(0.18, 2.6, 0.24), Vector3(0.85, 1.3, 0), frame)
	_box(Vector3(1.9, 0.22, 0.24), Vector3(0, 2.62, 0), frame)
	_box(Vector3(1.5, 2.5, 0.12), Vector3(0, 1.25, 0), slab)
	if mode == "cab":
		# The panel box beside the doors.
		_box(Vector3(0.3, 0.5, 0.1), Vector3(1.25, 1.4, 0),
			_mat(Color(0.16, 0.16, 0.18)))
	var label := Label3D.new()
	label.text = {"cab": "ELEVATOR", "stair_up": "STAIRS UP",
		"stair_down": "STAIRS DOWN",
		"exit": "STREET"}[mode]
	label.font_size = 48
	label.pixel_size = 0.01
	label.position = Vector3(0, 3.1, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
