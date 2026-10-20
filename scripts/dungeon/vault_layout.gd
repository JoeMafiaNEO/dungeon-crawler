extends RefCounted
## Issue #185 (Mason's Vault P2): the vault's authored layout.
## The dungeon's flat-floor path builds the arena slab, the
## perimeter, and the station annex from a hand-made LevelLayout
## (below); EVERYTHING inside — the chamber chain, partitions,
## doors, mechanisms, statues — is constructed here in code
## (the docks/station precedent: authored, not procgen, not a
## baked scene).
##
## The chain runs north (the annex entry) to south: eight
## chambers in passphrase order, one per CipherPoems row, then
## the rite hall, then the treasure chamber. All mechanism
## content (words, ciphers, shifts) is read from the
## CipherPoems rows by the VaultDirector at the point of use;
## this file authors only geometry, keys, and placement.

const MechScript := preload("res://scripts/dungeon/vault_mechanism.gd")

const HALF_SPAN := 17.0   # chamber half-width (side walls at ±17)
const ENTRY_Z := -38.0    # south edge of the entry apron
const SOUTH_Z := 44.0     # the treasure chamber's far wall
# Partition z lines between the bands, in order.
const PARTITIONS := [-30.0, -22.0, -14.0, -6.0, 2.0, 10.0, 18.0, 26.0, 38.0]


## The hand-made layout the standard builders consume: an
## all-floor grid, party spawns in the first chamber, torches
## along the chain. No mob spawns (the director places every
## vault encounter), no props, no obstacles.
static func make_layout(theme: LevelTheme) -> LevelLayout:
	var layout := LevelLayout.new()
	layout.grid_size = theme.grid_size
	layout.cell_size = theme.cell_size
	layout.grid = PackedByteArray()
	layout.grid.resize(theme.grid_size * theme.grid_size)  # all FLOOR
	for x in [-3.0, -1.0, 1.0, 3.0]:
		layout.player_spawns.append(Vector3(x, 0, -35.0))
	for z in [-36.0, -28.0, -20.0, -12.0, -4.0, 4.0, 12.0, 20.0, 28.0, 36.0]:
		layout.torches.append(Vector3(-16.2, 2.4, z))
		layout.torches.append(Vector3(16.2, 2.4, z))
	return layout


static func build(dungeon: Node3D, director: Node) -> void:
	var root := Node3D.new()
	root.name = "Vault"
	dungeon.add_child(root)
	var stone := _mat(Color(0.40, 0.38, 0.35))
	# Side walls + the south end wall.
	_box(root, Vector3(1.2, 4.0, SOUTH_Z - ENTRY_Z), Vector3(-HALF_SPAN, 2.0, (ENTRY_Z + SOUTH_Z) * 0.5), stone, true)
	_box(root, Vector3(1.2, 4.0, SOUTH_Z - ENTRY_Z), Vector3(HALF_SPAN, 2.0, (ENTRY_Z + SOUTH_Z) * 0.5), stone, true)
	_box(root, Vector3(HALF_SPAN * 2.0, 4.0, 1.2), Vector3(0, 2.0, SOUTH_Z), stone, true)
	# Partitions (a 3 m doorway gap at center; the poem-7
	# partition carries three door panels in a 9 m gap).
	for i in PARTITIONS.size():
		var z: float = PARTITIONS[i]
		var gap := 4.5 if i == 6 else 1.5
		_box(root, Vector3(HALF_SPAN - gap, 4.0, 0.8), Vector3(-(gap + (HALF_SPAN - gap) * 0.5), 2.0, z), stone, true)
		_box(root, Vector3(HALF_SPAN - gap, 4.0, 0.8), Vector3(gap + (HALF_SPAN - gap) * 0.5, 2.0, z), stone, true)
		_box(root, Vector3(gap * 2.0, 1.0, 0.8), Vector3(0, 3.5, z), stone, true)
	_build_chambers(root, director)
	# Server: the patrolled chamber's sentries are live at build.
	director.call("on_vault_built", dungeon)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


static func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material, collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.position = pos
		parent.add_child(body)
	return mi


static func _label(parent: Node, text: String, pos: Vector3, size: int = 56) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = Color(0.92, 0.90, 0.84)
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	parent.add_child(l)
	return l


static func _mech(parent: Node, director: Node, key: String, def: Dictionary, pos: Vector3) -> Node3D:
	var n: Node3D = MechScript.new()
	n.position = pos
	parent.add_child(n)
	n.call("setup", key, def)
	director.call("register_mechanism", key, def, n)
	return n


static func _statue(parent: Node, director: Node, key: String, chamber: String, mob: String, pos: Vector3, live := false) -> void:
	var data := load("res://data/mobs/%s.tres" % mob) as MobData
	var def := {"kind": "statue", "chamber": chamber, "mob": mob, "live": live,
		"texture": data.frames[0] if data != null and not data.frames.is_empty() else null}
	_mech(parent, director, key, def, pos)


static func _build_chambers(root: Node3D, director: Node) -> void:
	var stone := _mat(Color(0.40, 0.38, 0.35))
	# --- Chamber 1 · WHEEL (poem I): one wheel, door tests it.
	_mech(root, director, "wheel1", {"kind": "wheel", "poem": 0, "door": "door1", "chamber": "c1"}, Vector3(-6, 0, -34))
	_mech(root, director, "door1", {"kind": "door", "poem": 0, "wheel": "wheel1"}, Vector3(0, 0, -30))
	# --- Chamber 2 · CARRY (poem II): the QUIET tablet, patrolled.
	_mech(root, director, "tablet_quiet", {"kind": "tablet", "poem": 1, "word": str(CipherPoems.POEMS[1]["word"])}, Vector3(-8, 0, -28))
	_mech(root, director, "socket_quiet", {"kind": "socket", "item": "tablet_quiet", "door": "door2"}, Vector3(8, 0, -23.5))
	_mech(root, director, "door2", {"kind": "door"}, Vector3(0, 0, -22))
	_statue(root, director, "statue_c2a", "c2", "stone_sentry", Vector3(-4, 0, -26), true)
	_statue(root, director, "statue_c2b", "c2", "stone_sentry", Vector3(4, 0, -26), true)
	# --- Chamber 3 · WEIGH (poem III): the pan must sum to the shift.
	var beam_pos := Vector3(0, 0, -17)
	_box(root, Vector3(0.5, 2.2, 0.5), beam_pos + Vector3(-2.2, 1.1, 0), stone, true)
	_box(root, Vector3(0.5, 2.2, 0.5), beam_pos + Vector3(2.2, 1.1, 0), stone, true)
	_box(root, Vector3(5.4, 0.3, 0.5), beam_pos + Vector3(0, 2.3, 0), stone)
	var pan := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.7
	cm.height = 0.18
	cm.material = _mat(Color(0.55, 0.48, 0.30))
	pan.mesh = cm
	pan.position = beam_pos + Vector3(0, 0.55, 0)
	root.add_child(pan)
	# The counterweight pan is engraved with the shift (the row's
	# own number, read from CipherPoems — never a copy).
	_label(root, str(CipherPoems.POEMS[2]["shift"]), beam_pos + Vector3(0, 3.1, 0), 72)
	for i in 5:
		var w := i + 1
		var home := Vector3(-6.0 + 3.0 * i, 0, -20.5)
		_mech(root, director, "wstone%d" % w,
			{"kind": "wstone", "poem": 2, "weigh": "weigh3", "door": "door3", "weight": w,
				"home_pos": home, "pan_pos": beam_pos + Vector3((float(i) - 2.0) * 0.35, 0.68, 0)},
			home)
	_mech(root, director, "door3", {"kind": "door"}, Vector3(0, 0, -14))
	# --- Chamber 4 · WHEEL (poem IV): one wheel, a waking chamber.
	_mech(root, director, "wheel4", {"kind": "wheel", "poem": 3, "door": "door4", "chamber": "c4"}, Vector3(-6, 0, -10))
	_mech(root, director, "door4", {"kind": "door", "poem": 3, "wheel": "wheel4"}, Vector3(0, 0, -6))
	_statue(root, director, "statue_c4a", "c4", "stone_sentry", Vector3(5, 0, -12))
	_statue(root, director, "statue_c4b", "c4", "stone_sentry", Vector3(5, 0, -8))
	# --- Chamber 5 · WHEEL (poem V): two wheels share the door.
	_mech(root, director, "wheel5a", {"kind": "wheel", "poem": 4, "door": "door5", "chamber": "c5"}, Vector3(-6, 0, -2))
	_mech(root, director, "wheel5b", {"kind": "wheel", "poem": 4, "door": "door5", "chamber": "c5"}, Vector3(6, 0, -2))
	_mech(root, director, "door5", {"kind": "door", "poem": 4, "wheels": ["wheel5a", "wheel5b"]}, Vector3(0, 0, 2))
	_statue(root, director, "statue_c5a", "c5", "stone_sentry", Vector3(-4.5, 0, -4.5))
	_statue(root, director, "statue_c5b", "c5", "stone_sentry", Vector3(4.5, 0, 0.5))
	# --- Chamber 6 · PLATES (poem VI): the inlay shows the order.
	var steps := [1, 4, 6, 2, 7, 3, 8, 5]
	var pi := 0
	for row in 2:
		for col in 4:
			var step: int = steps[pi]
			_mech(root, director, "plate%d" % step,
				{"kind": "plate", "poem": 5, "plates": "plates6", "door": "door6",
					"step": step, "step_roman": CipherPoems.roman(step - 1)},
				Vector3(-6.0 + 4.0 * col, 0, 4.0 + 4.0 * row))
			pi += 1
	_mech(root, director, "door6", {"kind": "door"}, Vector3(0, 0, 10))
	# --- Chamber 7 · DOORS (poem VII): one lintel decodes true.
	# The strings are the row's own cipher and two one-letter
	# mutations of it (authored here as lintel text; which one is
	# real is COMPUTED from the row by the director, never
	# flagged in the data).
	var cipher7 := str(CipherPoems.POEMS[6]["cipher"])
	_mech(root, director, "door7a", {"kind": "door_try", "poem": 6, "chamber": "c7", "lintel": "V" + cipher7.substr(1)}, Vector3(-3, 0, 18))
	_mech(root, director, "door7b", {"kind": "door_try", "poem": 6, "chamber": "c7", "lintel": cipher7}, Vector3(3, 0, 18))
	_mech(root, director, "door7c", {"kind": "door_try", "poem": 6, "chamber": "c7", "lintel": cipher7.substr(0, 3) + "V"}, Vector3(0, 0, 18))
	_statue(root, director, "statue_c7a", "c7", "stone_sentry", Vector3(-6.5, 0, 14))
	_statue(root, director, "statue_c7b", "c7", "stone_sentry", Vector3(6.5, 0, 14))
	# --- Chamber 8 · CARRY (poem VIII): five stones, five
	# sockets, one lintel. The stones are the decoded word's
	# first five letters, the sockets in word order.
	var word8 := str(CipherPoems.POEMS[7]["word"])
	var fam: Array = []
	for i in 5:
		fam.append("stone_%s" % word8[i].to_lower())
	for i in 5:
		var letter := word8[i]
		_mech(root, director, "stone_%s" % letter.to_lower(),
			{"kind": "stone", "poem": 7, "letter": letter}, Vector3(-14, 0, 19.5 + 1.5 * i))
	for i in 5:
		var letter := word8[i]
		_mech(root, director, "lsock_%s" % letter.to_lower(),
			{"kind": "lsocket", "item": "stone_%s" % letter.to_lower(), "letter": letter,
				"door": "door8", "family": fam}, Vector3(14, 0, 19.5 + 1.5 * i))
	_mech(root, director, "door8", {"kind": "door"}, Vector3(0, 0, 26))
	# --- The rite hall: eight word-stones on plinths, flanked by
	# the two warden statues. The stones' WORDS are the
	# director's business — a per-run permutation (#186); the
	# layout only stands the stones (positions 0-7, in two rows).
	for i in 8:
		_mech(root, director, "rite_%d" % i,
			{"kind": "rite_stone", "pos": i, "chamber": "rite"},
			Vector3(-6.0 + 4.0 * (i % 4), 0, 29.0 + 4.0 * (i / 4)))
	_statue(root, director, "warden_a", "rite", "vault_warden", Vector3(-8, 0, 32))
	_statue(root, director, "warden_b", "rite", "vault_warden", Vector3(8, 0, 32))
	_mech(root, director, "treasure_door", {"kind": "door"}, Vector3(0, 0, 38))
	# --- Treasure chamber: the departure lever (#186) — a real
	# mechanism, inert until the rite activates it.
	var lever_node := _mech(root, director, "lever", {"kind": "lever"}, Vector3(0, 0, 41))
	lever_node.name = "VaultLever"
