class_name DepartureBoard
extends Node3D
## Station departure board: a big physical 3D board with 5 clickable rows.
## Voting happens by cursor raycast while in "reading mode" (mouse visible,
## E to step away) — no floating HUD panel. Rows are Area3Ds on physics
## layer 4 so the player's cursor raycast can hit them.

const BOARD_W := 4.6
const BOARD_H := 3.2
const ROW_W := 4.2
const ROW_H := 0.42

var _rows := {} # theme_id -> {plate, label, base_text, area, vote_frame, mat}
var _hover_id := ""


func _ready() -> void:
	add_to_group("departure_board")
	_build()


func prompt_text() -> String:
	return "Check departure board"


func interact(player: Player) -> void:
	if player.has_method("enter_reading"):
		player.enter_reading(self)


## One-line row text (no tally). Stars mirror the old HUD panel exactly.
static func row_base_text(theme_id: String, next_level: int) -> String:
	var name := str(Station.theme_display_name(theme_id)).to_upper()
	var stars := str(Station.BOARD_STARS.get(theme_id, ""))
	if theme_id == "supermarket":
		stars += " $"
	var rec := Station.recommended_level(theme_id, next_level)
	return "%s   %s   Rec. Lv %d" % [name, stars, rec]


func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
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
	var wood_dark := _mat(Color(0.32, 0.22, 0.14))
	var board_dark := _mat(Color(0.10, 0.10, 0.13))
	var gold := _mat(Color(0.85, 0.65, 0.25), Color(0.85, 0.60, 0.20), 0.8)
	var slate := Color(0.16, 0.17, 0.22)
	# Two posts.
	_box(Vector3(0.22, 3.8, 0.22), Vector3(-2.0, 1.9, 0), wood_dark)
	_box(Vector3(0.22, 3.8, 0.22), Vector3(2.0, 1.9, 0), wood_dark)
	# Big dark board, center y=2.0 (spans 0.4..3.6).
	_box(Vector3(BOARD_W, BOARD_H, 0.12), Vector3(0, 2.0, 0), board_dark)
	# Gold frame trims.
	_box(Vector3(BOARD_W + 0.16, 0.12, 0.14), Vector3(0, 3.66, 0), gold)
	_box(Vector3(BOARD_W + 0.16, 0.12, 0.14), Vector3(0, 0.34, 0), gold)
	_box(Vector3(0.12, BOARD_H + 0.16, 0.14), Vector3(-2.36, 2.0, 0), gold)
	_box(Vector3(0.12, BOARD_H + 0.16, 0.14), Vector3(2.36, 2.0, 0), gold)
	# Header (fixed to the board, not billboarded — it should feel physical).
	var header := Label3D.new()
	header.text = "DEPARTURES"
	header.font_size = 96
	header.pixel_size = 0.006
	header.modulate = Color(1.0, 0.82, 0.35)
	header.outline_size = 12
	header.position = Vector3(0, 3.32, 0.10)
	add_child(header)
	# 5 clickable rows.
	var next_level := Station.next_level_number
	var y := 2.88
	for theme_id in Dungeon.THEME_ORDER:
		var tid := str(theme_id)
		_build_row(tid, y, slate, next_level)
		y -= 0.54
	# Faint gold light so it reads at dusk.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 0.9
	light.omni_range = 7.0
	light.position = Vector3(0, 2.4, 1.6)
	add_child(light)
	# Unanimous-boarding rule, posted on a plaque between the posts.
	var hint := Label3D.new()
	hint.text = "ALL LIVING PLAYERS MUST AGREE ON A DESTINATION"
	hint.font_size = 36
	hint.pixel_size = 0.0032
	hint.modulate = Color(1.0, 0.82, 0.35)
	hint.outline_size = 6
	hint.outline_modulate = Color(0, 0, 0, 0.9)
	hint.position = Vector3(0, 0.12, 0.10)
	add_child(hint)


func _build_row(tid: String, y: float, slate: Color, next_level: int) -> void:
	# Per-row material so hover/vote highlights are independent.
	var mat := _mat(slate)
	var plate := _box(Vector3(ROW_W, ROW_H, 0.08), Vector3(0, y, 0.10), mat)
	var label := Label3D.new()
	label.font_size = 44
	label.pixel_size = 0.0042
	label.modulate = Color(0.92, 0.92, 0.95)
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.position = Vector3(0, y, 0.16)
	add_child(label)
	var base := row_base_text(tid, next_level)
	label.text = base + "  [0]"
	# Gold "my vote" frame behind the plate, hidden until voted.
	var frame := _box(Vector3(ROW_W + 0.14, ROW_H + 0.12, 0.05),
		Vector3(0, y, 0.06), _mat(Color(0.85, 0.65, 0.25), Color(0.9, 0.7, 0.3), 1.2))
	frame.visible = false
	# Raycast target on dedicated layer 4 (nothing else uses it).
	var area := Area3D.new()
	area.collision_layer = 4
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.input_ray_pickable = true
	area.set_meta("theme_id", tid)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ROW_W, ROW_H, 0.3)
	shape.shape = box
	shape.position = Vector3(0, y, 0.10)
	area.add_child(shape)
	add_child(area)
	_rows[tid] = {"plate": plate, "label": label, "base_text": base,
		"area": area, "frame": frame, "mat": mat, "slate": slate}


## Gold emission on the hovered row's plate.
func set_hover(theme_id: String) -> void:
	if theme_id == _hover_id:
		return
	_hover_id = theme_id
	for tid in _rows:
		var r: Dictionary = _rows[tid]
		var m := r["mat"] as StandardMaterial3D
		if tid == theme_id:
			m.emission_enabled = true
			m.emission = Color(0.9, 0.7, 0.3)
			m.emission_energy_multiplier = 0.9
		else:
			m.emission_enabled = false


## Persistent gold frame on the row the local player voted.
func set_my_vote(theme_id: String) -> void:
	for tid in _rows:
		(_rows[tid]["frame"] as MeshInstance3D).visible = (tid == theme_id)


## Refresh the [n] tallies from the server's vote table.
func set_tallies(votes: Dictionary) -> void:
	var counts := {}
	for pid in votes:
		var t := str(votes[pid])
		counts[t] = int(counts.get(t, 0)) + 1
	for tid in _rows:
		var r: Dictionary = _rows[tid]
		(r["label"] as Label3D).text = "%s  [%d]" % [r["base_text"], int(counts.get(tid, 0))]
