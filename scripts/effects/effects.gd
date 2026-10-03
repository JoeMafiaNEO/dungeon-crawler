class_name Effects
extends RefCounted
## Tiny particle-effect factory. All effects are one-shot bursts or ambient
## emitters built in code so scenes stay light.


static func _make_particles(color: Color, amount: int, speed: float, lifetime: float, one_shot: bool, gravity: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.15
	p.fixed_fps = 30
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 55.0
	proc.initial_velocity_min = speed * 0.4
	proc.initial_velocity_max = speed
	proc.gravity = gravity
	proc.scale_min = 0.6
	proc.scale_max = 1.4
	proc.color = color
	p.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var qmat := StandardMaterial3D.new()
	qmat.albedo_color = color
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = qmat
	p.draw_pass_1 = quad
	return p


## One-shot burst (hit sparks, death poof, level-up). Auto-frees itself.
static func burst(parent: Node, pos: Vector3, color: Color, amount: int = 14, speed: float = 5.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := _make_particles(color, amount, speed, 0.5, true, Vector3(0, -9, 0))
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## Jagged lightning bolt between points. Fades quickly.
static func lightning(parent: Node, points: PackedVector3Array, color: Color) -> void:
	if parent == null or not parent.is_inside_tree() or points.size() < 2:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for pt in points:
		im.surface_set_color(color)
		im.surface_add_vertex(pt - points[0])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	parent.add_child(mi)
	mi.global_position = points[0]
	var tw := mi.create_tween()
	tw.tween_property(mi, "transparency", 1.0, 0.25)
	tw.tween_callback(mi.queue_free)


## Expanding telegraph ring on the ground (for delayed AoEs).
static func telegraph_ring(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.15
	torus.outer_radius = radius
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = mat
	mi.mesh = torus
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.15, pos.z)
	# Pulse while the meteor is incoming.
	var tw := mi.create_tween()
	tw.set_loops(2)
	tw.tween_property(mat, "emission_energy_multiplier", 4.0, 0.25)
	tw.tween_property(mat, "emission_energy_multiplier", 2.0, 0.25)
	tw.tween_callback(mi.queue_free)


## Floating combat text. Color scales with damage: white < 15, gold < 40, orange above.
static func damage_number(parent: Node, pos: Vector3, amount: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 72
	label.pixel_size = 0.008
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.9)
	if amount >= 40.0:
		label.modulate = Color(1.0, 0.55, 0.2)
	elif amount >= 15.0:
		label.modulate = Color(1.0, 0.85, 0.3)
	else:
		label.modulate = Color(0.95, 0.95, 0.95)
	label.text = str(int(round(amount)))
	parent.add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.3, 0.3), 1.6, randf_range(-0.3, 0.3))
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y + 1.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.15)
	tw.chain().tween_callback(label.queue_free)


## Continuous flame emitter (torches). Returns the node so callers can move it.
static func make_flame() -> GPUParticles3D:
	var p := _make_particles(Color(1.0, 0.55, 0.15), 12, 1.1, 0.9, false, Vector3(0, 1.5, 0))
	p.explosiveness = 0.1
	var proc := p.process_material as ParticleProcessMaterial
	proc.spread = 14.0
	proc.direction = Vector3(0, 1, 0)
	proc.damping_min = 1.0
	proc.damping_max = 2.0
	return p


static func make_snow() -> GPUParticles3D:
	var p := _make_particles(Color(0.85, 0.93, 1.0), 40, 2.5, 1.6, false, Vector3(0, -4, 0))
	var proc := p.process_material as ParticleProcessMaterial
	proc.spread = 30.0
	proc.direction = Vector3(0, -1, 0)
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 4.0
	return p


## Scorched ground decal: dark disc that fades over a few seconds.
static func scorch(parent: Node, pos: Vector3, radius: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 0.9
	disc.bottom_radius = radius * 0.9
	disc.height = 0.02
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.06, 0.05, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = mat
	mi.mesh = disc
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.06, pos.z)
	var tw := mi.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 2.0)
	tw.tween_callback(mi.queue_free)
