class_name Fireball
extends Node3D
## Mage projectile. Flies straight on every peer; the server owns hit
## detection and damage, then tells everyone to explode.

var velocity := Vector3.ZERO
var damage := 10.0
var owner_peer := 0

var _life := 2.5
var _exploded := false
var skill_tag := "fireball"  # or "barrage" for Arcane Barrage bolts


func setup(p_velocity: Vector3, p_damage: float, p_owner: int, p_skill := "fireball") -> void:
	velocity = p_velocity
	damage = p_damage
	owner_peer = p_owner
	skill_tag = p_skill


## True if the projectile is inside a wall/obstacle cell.
func _is_in_wall() -> bool:
	var dungeons := get_tree().get_nodes_in_group("dungeon")
	if dungeons.is_empty():
		return false
	var dungeon = dungeons[0]
	var layout = dungeon.get("_layout")
	if layout == null:
		return false
	return layout.is_solid_world(global_position)


## Issue #206 (spec section 6): the caster's Deep Tree
## look for this projectile, or {} when the caster's set
## doesn't govern it (stock construction, byte-for-byte).
func _caster_look() -> Dictionary:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null or not dungeon.has_method("get_player_node"):
		return {}
	var caster = dungeon.get_player_node(owner_peer)
	if caster == null:
		return {}
	var owned: Array = caster.get("tree_owned")
	if owned.is_empty():
		return {}
	return DeepTree.look_for(int(caster.get("tree_seed")),
		str(caster.get("class_id")),
		"barrage" if skill_tag == "barrage" else "fireball",
		owned)


func _ready() -> void:
	var look := _caster_look()
	var governed := not look.is_empty() \
		and not bool(look.get("stock", true))
	var shift := float(look.get("hue_shift", 0.0)) \
		if governed else 0.0
	if governed and bool(look.get("variant", false)):
		# Variant-governed: the seeded grammar body
		# replaces the stock sphere (cached template).
		var tmpl := DeepTreeLooks.bundle_template(owner_peer,
			"barrage" if skill_tag == "barrage" else "fireball",
			look, Color(1.0, 0.45, 0.1), Color(1.0, 0.4, 0.08))
		add_child(tmpl.duplicate())
	else:
		# Glowing core (stock values when ungoverned).
		var core := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.22
		sphere.height = 0.44
		var mat := StandardMaterial3D.new()
		mat.albedo_color = DeepTreeLooks.shifted(
			Color(1.0, 0.45, 0.1), shift)
		mat.emission_enabled = true
		mat.emission = DeepTreeLooks.shifted(
			Color(1.0, 0.4, 0.08), shift)
		mat.emission_energy_multiplier = float(look.get(
			"emission_energy", 4.0)) if governed else 4.0
		sphere.material = mat
		core.mesh = sphere
		add_child(core)
	# Light it casts (the look never adds lights; energy
	# and color stay in the stock envelope).
	var light := OmniLight3D.new()
	light.light_color = DeepTreeLooks.shifted(
		Color(1.0, 0.5, 0.15), shift)
	light.light_energy = float(look.get("light_energy",
		1.6)) if governed else 1.6
	light.omni_range = 7.0
	add_child(light)
	# Trail.
	if governed:
		add_child(DeepTreeLooks.make_trail(look,
			DeepTreeLooks.shifted(Color(1.0, 0.45, 0.1),
				shift)))
	else:
		var trail := Effects.make_flame()
		trail.amount = 24
		trail.local_coords = false
		add_child(trail)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_life -= delta
	position += velocity * delta
	if _life <= 0.0 or position.y < 0.0:
		_explode()
		return
	# Walls stop fireballs (Meteor is the exception — it falls from the sky).
	if _is_in_wall():
		_explode()
		return
	if multiplayer.is_server():
		for node in get_tree().get_nodes_in_group("mobs"):
			var mob := node as Mob
			if mob == null or not mob.alive:
				continue
			# Issue #20: fuse on horizontal (XZ) distance. The fireball flies
			# at ~1.45m height but mob origins are at feet (y≈0); 3D distance
			# can never drop below 1.45m on a level shot, so level shots would
			# never detonate. (Frost Shard already uses this pattern.)
			var a := Vector2(mob.global_position.x, mob.global_position.z)
			var b := Vector2(global_position.x, global_position.z)
			if a.distance_to(b) < 1.3:
				_explode()
				return


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	if multiplayer.is_server():
		# Small AoE around the impact point.
		var dungeon := get_tree().get_first_node_in_group("dungeon")
		var caster: Player = null
		if dungeon != null:
			caster = dungeon.get_player_node(owner_peer) as Player
		var cast_id := "fireball_%d" % get_instance_id()
		# Conflagration: +25% blast radius on fire skills.
		var radius := 2.6
		if caster != null and caster.has_trait("conflagration") and skill_tag == "fireball":
			radius *= 1.25
		# Issue #206 (spec section 5): the caster's tree
		# radius_add for the skill, beside Conflagration.
		if caster != null:
			radius += caster.tree_radius_add("barrage" if skill_tag == "barrage" else "fireball")
		for node in get_tree().get_nodes_in_group("mobs"):
			var mob := node as Mob
			if mob == null or not mob.alive:
				continue
			# Issue #20: XZ distance for the AoE as well — matches the fuse.
			var ma := Vector2(mob.global_position.x, mob.global_position.z)
			var mb := Vector2(global_position.x, global_position.z)
			if ma.distance_to(mb) < radius:
				mob.take_damage(damage, owner_peer, global_position)
				# Wildfire: fire hits apply burn (3s DoT).
				if caster != null and caster.has_trait("wildfire"):
					mob.apply_burn(3.0, damage * 0.3, owner_peer)
				# Affinity: fireball +2/hit max 10/cast; barrage +1/hit max 6/cast.
				if caster != null:
					if skill_tag == "barrage":
						caster.gain_affinity_capped("barrage", 1.0, mob.get_instance_id(), cast_id, 6.0)
					else:
						caster.gain_affinity_capped("fireball", 2.0, mob.get_instance_id(), cast_id, 10.0)
		rpc("explode_fx")
	else:
		# Clients wait for the server's fx; time out just in case.
		await get_tree().create_timer(0.5).timeout
		if is_inside_tree():
			queue_free()


@rpc("any_peer", "call_local")
func explode_fx() -> void:
	AudioManager.sfx("explosion", global_position)
	Effects.burst(get_parent(), global_position, Color(1.0, 0.5, 0.1), 26, 7.0)
	Effects.burst(get_parent(), global_position, Color(1.0, 0.85, 0.4), 12, 3.5)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.55, 0.2)
	flash.light_energy = 3.0
	flash.omni_range = 10.0
	get_parent().add_child(flash)
	flash.global_position = global_position
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
	queue_free()

