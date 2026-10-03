class_name PropBuilder
extends RefCounted
## Builds low-poly placeholder props from primitives.
##
## Each prop type is a static function; themes reference types by string name.
## When the real asset packs land, a type can return an imported model scene
## instead -- the theme .tres files don't change.

static var _mats: Dictionary = {}
static var _model_cache: Dictionary = {}

## Imported-model registry: prop type -> list of {p: path, s: scale, y: y-offset}.
## Variety picks are deterministic on the prop's world position so every peer
## builds the same visual from the same layout. Types not listed here fall
## through to the primitive builders below (house, tent, well, crystal, bones,
## stalagmite, bush keep their programmer-art look for now).
static var _model_registry: Dictionary = {
	"tree": [
		{"p": "res://assets/models/kenney/nature/tree_oak.glb", "s": 2.2},
		{"p": "res://assets/models/kenney/nature/tree_detailed.glb", "s": 2.2},
	],
	"pine": [
		{"p": "res://assets/models/kenney/nature/tree_cone.glb", "s": 2.0},
		{"p": "res://assets/models/kenney/nature/tree_cone_dark.glb", "s": 2.0},
	],
	"rock": [
		{"p": "res://assets/models/kenney/nature/rock_largeA.glb", "s": 1.6},
		{"p": "res://assets/models/kenney/nature/rock_largeB.glb", "s": 1.6},
		{"p": "res://assets/models/kenney/nature/rock_largeC.glb", "s": 1.6},
		{"p": "res://assets/models/kenney/nature/rock_smallA.glb", "s": 2.0},
		{"p": "res://assets/models/kenney/nature/rock_smallB.glb", "s": 2.0},
	],
	"pillar": [
		{"p": "res://assets/models/kaykit/dungeon/pillar.glb", "s": 0.62},
	],
	"crate": [
		{"p": "res://assets/models/kaykit/dungeon/box_small.glb", "s": 0.8},
	],
	"barrel": [
		{"p": "res://assets/models/kaykit/dungeon/barrel_small.glb", "s": 0.8},
	],
	"torch": [
		{"p": "res://assets/models/kaykit/dungeon/torch_lit.glb", "s": 1.4, "y": 0.55},
	],
	"rubble": [
		{"p": "res://assets/models/kaykit/dungeon/rubble_large.glb", "s": 0.3},
	],
	"fence": [
		{"p": "res://assets/models/kenney/nature/fence_simple.glb", "s": 2.0},
	],
	"mushroom": [
		{"p": "res://assets/models/kenney/nature/mushroom_red.glb", "s": 1.0},
		{"p": "res://assets/models/kenney/nature/mushroom_tan.glb", "s": 1.0},
		{"p": "res://assets/models/kenney/nature/mushroom_redGroup.glb", "s": 1.0},
	],
	"grass": [
		{"p": "res://assets/models/kenney/nature/grass.glb", "s": 1.5},
	],
}


static func _model_for(prop_type: String, pos: Vector3) -> Node3D:
	if not _model_registry.has(prop_type):
		return null
	var variants: Array = _model_registry[prop_type]
	# Deterministic variety: hash the world position so all peers agree.
	var idx := absi(hash("%s|%.3f|%.3f" % [prop_type, pos.x, pos.z])) % variants.size()
	var cfg: Dictionary = variants[idx]
	var path := str(cfg["p"])
	if not _model_cache.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			return null
		_model_cache[path] = packed
	var inst := (_model_cache[path] as PackedScene).instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = "Prop_" + prop_type
	holder.set_meta("is_model", true)
	holder.add_child(inst)
	inst.scale = Vector3.ONE * float(cfg.get("s", 1.0))
	inst.position.y = float(cfg.get("y", 0.0))
	return holder


static func mat(color: Color, emission: Color = Color(0, 0, 0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%.1f" % [color.to_html(), emission.to_html(), emission_energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_mats[key] = m
	return m


static func build(prop_type: String, size_cells: float = 1.0, opts: Dictionary = {}) -> Node3D:
	var from_model := _model_for(prop_type, opts.get("pos", Vector3.ZERO))
	if from_model != null:
		if prop_type == "torch":
			# Imported torch has its own flame mesh; add the real light + keep flicker support.
			var light := OmniLight3D.new()
			light.light_color = opts.get("light_color", Color(1.0, 0.55, 0.25))
			light.light_energy = float(opts.get("light_energy", 2.0))
			light.omni_range = 9.0
			light.position = Vector3(0, 1.8, 0)
			from_model.add_child(light)
		if size_cells != 1.0:
			from_model.scale = Vector3.ONE * size_cells
		return from_model
	var root := Node3D.new()
	root.name = "Prop_" + prop_type
	match prop_type:
		"tree":
			_add_trunk(root, 0.18, 1.2, Color(0.36, 0.25, 0.15))
			_add_cone(root, 1.4, 1.6, 1.6, Color(0.22, 0.45, 0.22))
			_add_cone(root, 1.0, 1.2, 2.6, Color(0.26, 0.52, 0.26))
		"shelf":
			# Supermarket aisle shelf: tall unit with colorful product boxes.
			_add_box(root, Vector3(2.4, 1.8, 0.6), 0.9, Color(0.75, 0.78, 0.82))
			_add_box(root, Vector3(2.4, 0.08, 0.65), 0.45, Color(0.55, 0.58, 0.62))
			_add_box(root, Vector3(2.4, 0.08, 0.65), 0.95, Color(0.55, 0.58, 0.62))
			_add_box(root, Vector3(2.4, 0.08, 0.65), 1.45, Color(0.55, 0.58, 0.62))
			var prod_colors := [Color(0.9, 0.25, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.75, 0.35), Color(0.85, 0.45, 0.85)]
			for i in 6:
				var pc: Color = prod_colors[i % prod_colors.size()]
				_add_box(root, Vector3(0.3, 0.28, 0.4), 0.62, pc, 0.0, Vector3(-0.9 + float(i % 3) * 0.9, 0, 0))
				_add_box(root, Vector3(0.3, 0.28, 0.4), 1.12, pc, 0.0, Vector3(-0.9 + float((i + 1) % 3) * 0.9, 0, 0))
		"checkout":
			# Checkout counter with conveyor belt.
			_add_box(root, Vector3(2.0, 0.9, 0.8), 0.45, Color(0.35, 0.38, 0.42))
			_add_box(root, Vector3(2.0, 0.08, 0.8), 0.94, Color(0.2, 0.22, 0.25))
			_add_box(root, Vector3(0.5, 1.4, 0.5), 0.7, Color(0.85, 0.87, 0.9))
		"cart":
			# Shopping cart: basket + handle + wheels.
			_add_box(root, Vector3(0.7, 0.5, 1.0), 0.75, Color(0.7, 0.75, 0.82))
			_add_trunk(root, 0.03, 0.9, Color(0.4, 0.42, 0.45))
			_add_box(root, Vector3(0.7, 0.06, 0.08), 1.0, Color(0.4, 0.42, 0.45))
		"display":
			# Product display stand with pyramid of goods.
			_add_cylinder(root, 0.8, 0.15, 0.35, Color(0.8, 0.2, 0.25))
			_add_ball_at(root, 0.35, Vector3(0, 0.6, 0), Color(0.95, 0.7, 0.2))
			_add_ball_at(root, 0.28, Vector3(0.3, 0.55, 0.2), Color(0.2, 0.6, 0.9))
			_add_ball_at(root, 0.28, Vector3(-0.3, 0.55, -0.15), Color(0.35, 0.8, 0.35))
		"pine":
			_add_trunk(root, 0.15, 1.0, Color(0.32, 0.22, 0.13))
			_add_cone(root, 1.1, 1.8, 1.5, Color(0.13, 0.30, 0.18))
			_add_cone(root, 0.8, 1.4, 2.5, Color(0.15, 0.35, 0.20))
			_add_cone(root, 0.5, 1.0, 3.3, Color(0.17, 0.38, 0.22))
		"bush":
			_add_ball(root, 0.55, 0.35, Color(0.25, 0.50, 0.25))
		"flowers":
			# Cheerful wildflower patch: 5-7 little blooms in varied colors.
			var petal_colors := [Color(0.95, 0.35, 0.45), Color(0.95, 0.85, 0.3), Color(0.9, 0.9, 0.95), Color(0.75, 0.4, 0.9), Color(0.95, 0.55, 0.25)]
			for f in 6:
				var a := randf() * TAU
				var r := randf_range(0.1, 0.55)
				var fp := Vector3(cos(a) * r, 0, sin(a) * r)
				_add_trunk_at(root, 0.02, 0.28, Color(0.25, 0.5, 0.25), fp)
				_add_ball_at(root, 0.09, fp + Vector3(0, 0.3, 0), petal_colors[f % petal_colors.size()])
		"haybale":
			_add_cylinder(root, 0.55, 0.9, 0.45, Color(0.85, 0.68, 0.35))
			_add_cylinder(root, 0.57, 0.92, 0.1, Color(0.78, 0.60, 0.30))
		"rock":
			_add_ball(root, 0.7, 0.45, Color(0.45, 0.45, 0.47), 7)
		"pillar":
			_add_box(root, Vector3(0.9, 2.6, 0.9), 1.3, Color(0.55, 0.53, 0.50))
			_add_box(root, Vector3(1.2, 0.25, 1.2), 0.12, Color(0.60, 0.58, 0.55))
			_add_box(root, Vector3(1.2, 0.25, 1.2), 2.7, Color(0.60, 0.58, 0.55))
		"rubble":
			_add_box(root, Vector3(0.5, 0.3, 0.4), 0.15, Color(0.42, 0.42, 0.44), 0.4)
			_add_box(root, Vector3(0.35, 0.25, 0.3), 0.12, Color(0.48, 0.48, 0.50), -0.7)
			_add_box(root, Vector3(0.28, 0.2, 0.25), 0.1, Color(0.38, 0.38, 0.40), 1.2)
		"tent":
			_add_prism(root, Vector3(1.6, 1.3, 2.0), 0.65, Color(0.72, 0.62, 0.48))
			_add_trunk(root, 0.06, 1.8, Color(0.35, 0.25, 0.15))
		"house":
			_add_box(root, Vector3(2.6, 1.8, 2.2), 0.9, Color(0.78, 0.72, 0.60))
			_add_prism(root, Vector3(3.0, 1.2, 2.6), 2.4, Color(0.45, 0.30, 0.18))
			_add_box(root, Vector3(0.7, 1.2, 0.1), 0.6, Color(0.30, 0.20, 0.12), 0.0, Vector3(0, 0, 1.15))
		"fence":
			for k in 3:
				_add_trunk_at(root, 0.07, 0.9, Color(0.40, 0.30, 0.18), Vector3((k - 1) * 0.9, 0.45, 0))
			_add_box(root, Vector3(2.0, 0.08, 0.08), 0.65, Color(0.42, 0.32, 0.20))
			_add_box(root, Vector3(2.0, 0.08, 0.08), 0.35, Color(0.42, 0.32, 0.20))
		"well":
			_add_cylinder(root, 0.7, 0.8, 0.4, Color(0.50, 0.48, 0.45))
			_add_trunk_at(root, 0.07, 1.6, Color(0.35, 0.25, 0.15), Vector3(0.6, 0.8, 0))
			_add_trunk_at(root, 0.07, 1.6, Color(0.35, 0.25, 0.15), Vector3(-0.6, 0.8, 0))
			_add_prism(root, Vector3(1.7, 0.5, 1.0), 1.85, Color(0.45, 0.30, 0.18))
		"crate":
			_add_box(root, Vector3(0.8, 0.8, 0.8), 0.4, Color(0.55, 0.42, 0.26), 0.3)
		"torch":
			_add_trunk(root, 0.06, 1.5, Color(0.30, 0.20, 0.12))
			var flame := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.14
			sm.height = 0.3
			flame.mesh = sm
			flame.position = Vector3(0, 1.65, 0)
			flame.material_override = mat(Color(1, 0.6, 0.2), Color(1.0, 0.45, 0.1), 3.0)
			root.add_child(flame)
			var light := OmniLight3D.new()
			light.light_color = opts.get("light_color", Color(1.0, 0.55, 0.25))
			light.light_energy = float(opts.get("light_energy", 2.0))
			light.omni_range = 9.0
			light.position = Vector3(0, 1.8, 0)
			root.add_child(light)
		"crystal":
			var c := MeshInstance3D.new()
			var sm2 := SphereMesh.new()
			sm2.radial_segments = 4
			sm2.rings = 3
			sm2.radius = 0.45
			sm2.height = 1.4
			c.mesh = sm2
			c.position = Vector3(0, 0.7, 0)
			c.material_override = mat(Color(0.45, 0.3, 0.9), Color(0.5, 0.25, 1.0), 1.6)
			root.add_child(c)
		"bones":
			_add_box(root, Vector3(0.5, 0.08, 0.12), 0.04, Color(0.85, 0.83, 0.78), 0.5)
			_add_box(root, Vector3(0.4, 0.08, 0.1), 0.04, Color(0.82, 0.80, 0.75), -0.9)
			_add_ball(root, 0.16, 0.08, Color(0.85, 0.83, 0.78), 7)
		"mushroom":
			_add_trunk(root, 0.09, 0.35, Color(0.80, 0.75, 0.65))
			_add_ball(root, 0.28, 0.18, Color(0.75, 0.20, 0.20), 9)
		"stalagmite":
			_add_cone(root, 0.55, 1.6, 0.8, Color(0.35, 0.34, 0.38))
		"mazewall":
			# Backrooms-style solid rock wall, one cell (2m) wide, 3.2m tall.
			_add_box(root, Vector3(2.0, 3.2, 2.0), 1.6, Color(0.15, 0.14, 0.17))
		_:
			_add_ball(root, 0.5, 0.35, Color(0.5, 0.5, 0.5), 7)
	if size_cells != 1.0:
		root.scale = Vector3.ONE * size_cells
	return root


static func _mi(mesh: Mesh, pos: Vector3, color: Color, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = rot_y
	mi.material_override = mat(color)
	return mi


static func _add_box(root: Node3D, size: Vector3, y: float, color: Color, rot_y: float = 0.0, offset: Vector3 = Vector3.ZERO) -> void:
	var b := BoxMesh.new()
	b.size = size
	root.add_child(_mi(b, Vector3(offset.x, y, offset.z), color, rot_y))


static func _add_trunk(root: Node3D, r: float, h: float, color: Color) -> void:
	_add_trunk_at(root, r, h, color, Vector3(0, h * 0.5, 0))


static func _add_trunk_at(root: Node3D, r: float, h: float, color: Color, pos: Vector3) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r * 0.8
	c.bottom_radius = r
	c.height = h
	root.add_child(_mi(c, pos, color))


static func _add_cylinder(root: Node3D, r: float, h: float, y: float, color: Color) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	root.add_child(_mi(c, Vector3(0, y, 0), color))


static func _add_cone(root: Node3D, r: float, h: float, y: float, color: Color) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.02
	c.bottom_radius = r
	c.height = h
	root.add_child(_mi(c, Vector3(0, y, 0), color))


static func _add_ball(root: Node3D, r: float, y: float, color: Color, segs: int = 9) -> void:
	_add_ball_at(root, r, Vector3(0, y, 0), color, segs)


static func _add_ball_at(root: Node3D, r: float, pos: Vector3, color: Color, segs: int = 9) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(3, segs / 2)
	var mi := _mi(s, pos, color)
	mi.scale.y = 0.75
	root.add_child(mi)


static func _add_prism(root: Node3D, size: Vector3, y: float, color: Color) -> void:
	var p := PrismMesh.new()
	p.size = size
	root.add_child(_mi(p, Vector3(0, y, 0), color))
