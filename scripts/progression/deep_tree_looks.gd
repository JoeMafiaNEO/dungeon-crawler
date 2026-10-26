class_name DeepTreeLooks
extends RefCounted

## Issue #206 (spec section 6 / paper section 13.3): the
## seeded primitive-grammar projectile bodies. Built once
## per (owner, skill) into a template cache (<= 32 bundles,
## LRU-evicted); every cast duplicates the template, so the
## per-cast cost over stock is zero and generation never
## happens per-frame or per-cast. Materials are flat
## palette + emission, the register the stock projectiles
## already use. Budgets: <= 8 primitives, <= 800 vertices
## per generated mesh.

const MAX_BUNDLES := 32

static var _cache := {} # "owner|skill" -> template Node3D
static var _cache_order: Array = []


## The shifted family color: hue rotated by the look's
## shift (degrees), saturation/value preserved.
static func shifted(base: Color, hue_shift_deg: float) -> Color:
	var h := fposmod(base.h + hue_shift_deg / 360.0, 1.0)
	return Color.from_hsv(h, base.s, base.v, base.a)


static func bundle_template(owner_peer: int, skill_id: String,
		look: Dictionary, base_albedo: Color,
		base_emission: Color) -> Node3D:
	# The key fingerprints the look itself: the look is a
	# pure function of the governing set, so a changed set
	# (new purchase) yields a new key and a fresh bundle,
	# while an identical set hits. LRU-capped at 32.
	var key := "%d|%s|%d" % [owner_peer, skill_id,
		str(look).hash()]
	if _cache.has(key):
		_cache_order.erase(key)
		_cache_order.append(key)
		return _cache[key]
	# Cache miss: materials are built exactly once, here,
	# and shared by every duplicate of the template.
	var shift := float(look.get("hue_shift", 0.0))
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = shifted(base_albedo, shift)
	core_mat.emission_enabled = true
	core_mat.emission = shifted(base_emission, shift)
	core_mat.emission_energy_multiplier = float(look.get(
		"emission_energy", 4.0))
	var shell_mat := StandardMaterial3D.new()
	shell_mat.albedo_color = shifted(base_albedo,
		shift).darkened(0.45)
	var root := grammar_root(look.get("grammar", {}),
		core_mat, shell_mat)
	_cache[key] = root
	_cache_order.append(key)
	while _cache.size() > MAX_BUNDLES:
		var old: String = _cache_order.pop_front()
		(_cache[old] as Node3D).free()
		_cache.erase(old)
	return root


## The look's trail, from the Effects factories (spec
## section 6 vocabulary: burst vs trail vs halo shapes the
## existing machinery already speaks).
static func make_trail(look: Dictionary,
		shifted_color: Color) -> GPUParticles3D:
	var trail: GPUParticles3D
	match str(look.get("trail_kind", "flame")):
		"embers", "halo":
			trail = Effects.make_status_motes(shifted_color)
		_:
			trail = Effects.make_flame()
	trail.amount = int(look.get("trail_amount", 24))
	trail.local_coords = false
	return trail


## Build the grammar assembly: a core primitive plus 0-2
## shell elements (spec section 6). The returned node is a
## TEMPLATE (never added to a tree by the cache holder);
## callers add a duplicate.
static func grammar_root(grammar: Dictionary,
		core_mat: Material, shell_mat: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "TreeGrammar"
	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = _core_mesh(str(grammar.get("core",
		"octahedron")))
	core.material_override = core_mat
	root.add_child(core)
	var shells: Array = grammar.get("shells", [])
	for kind_v in shells:
		match str(kind_v):
			"spike_crown":
				for k in 4:
					var spike := MeshInstance3D.new()
					spike.name = "Spike%d" % k
					var cone := CylinderMesh.new()
					cone.top_radius = 0.0
					cone.bottom_radius = 0.07
					cone.height = 0.3
					cone.radial_segments = 6
					spike.mesh = cone
					spike.material_override = shell_mat
					var ang := TAU * float(k) / 4.0
					spike.position = Vector3(cos(ang) * 0.16,
						0.18, sin(ang) * 0.16)
					spike.rotation = Vector3(sin(ang) * 0.5,
						0, -cos(ang) * 0.5)
					root.add_child(spike)
			"orbit_ring":
				var ring := MeshInstance3D.new()
				ring.name = "OrbitRing"
				var torus := TorusMesh.new()
				torus.inner_radius = 0.30
				torus.outer_radius = 0.36
				torus.rings = 6
				torus.ring_segments = 12
				ring.mesh = torus
				ring.material_override = shell_mat
				ring.rotation = Vector3(deg_to_rad(24.0), 0,
					deg_to_rad(12.0))
				root.add_child(ring)
			"fin_set":
				for k in 3:
					var fin := MeshInstance3D.new()
					fin.name = "Fin%d" % k
					var box := BoxMesh.new()
					box.size = Vector3(0.04, 0.30, 0.18)
					fin.mesh = box
					fin.material_override = shell_mat
					var ang := TAU * float(k) / 3.0
					fin.position = Vector3(cos(ang) * 0.2,
						-0.05, sin(ang) * 0.2)
					fin.rotation = Vector3(0, -ang, 0.35)
					root.add_child(fin)
	root.scale = Vector3.ONE * float(grammar.get("scale",
		1.0))
	return root


static func _core_mesh(core_kind: String) -> Mesh:
	match core_kind:
		"sphere8":
			var s := SphereMesh.new()
			s.radius = 0.24
			s.height = 0.48
			s.radial_segments = 8
			s.rings = 4
			return s
		"box":
			var b := BoxMesh.new()
			b.size = Vector3(0.4, 0.4, 0.4)
			return b
		"crystal":
			return _pyramid_pair_mesh(0.20, 0.42)
		_: # octahedron
			return _pyramid_pair_mesh(0.26, 0.26)


## Two pyramids base-to-base (octahedron when apex == base
## radius): 6 vertices, 8 triangles, flat normals via
## per-face vertices.
static func _pyramid_pair_mesh(base_r: float,
		apex_h: float) -> ArrayMesh:
	var top := Vector3(0, apex_h, 0)
	var bot := Vector3(0, -apex_h, 0)
	var ring := [Vector3(base_r, 0, 0), Vector3(0, 0, base_r),
		Vector3(-base_r, 0, 0), Vector3(0, 0, -base_r)]
	var verts := PackedVector3Array()
	for k in 4:
		var a: Vector3 = ring[k]
		var b: Vector3 = ring[(k + 1) % 4]
		verts.append_array([a, b, top])
		verts.append_array([b, a, bot])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		arrays)
	return m


## Budget accounting for the pins: total vertices across
## every mesh instance under a root.
static func vertex_count(root: Node) -> int:
	var total := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mesh := (n as MeshInstance3D).mesh
			if mesh != null:
				for s in mesh.get_surface_count():
					var arrs := mesh.surface_get_arrays(s)
					total += (arrs[Mesh.ARRAY_VERTEX]
						as PackedVector3Array).size()
		for c in n.get_children():
			stack.append(c)
	return total


static func primitive_count(root: Node) -> int:
	var total := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			total += 1
		for c in n.get_children():
			stack.append(c)
	return total
