class_name FrostShard
extends Node3D
## Mage frost projectile. Fast blue shard; slows enemies it hits.
## Mirrors Fireball: flies on every peer, server owns hits.

var velocity := Vector3.ZERO
var damage := 10.0
var owner_peer := 0
var slow_duration := 2.5
var slow_mult := 0.5

var _life := 2.0
var _exploded := false


func setup(p_velocity: Vector3, p_damage: float, p_owner: int) -> void:
	velocity = p_velocity
	damage = p_damage
	owner_peer = p_owner


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


## Issue #210 (full build section 4): the caster's Deep
## Tree look for this shard, or {} when the caster's set
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
		str(caster.get("class_id")), "frost", owned)


func _ready() -> void:
	var look := _caster_look()
	var governed := not look.is_empty() \
		and not bool(look.get("stock", true))
	var shift := float(look.get("hue_shift", 0.0)) \
		if governed else 0.0
	if governed and bool(look.get("variant", false)):
		# Variant-governed: the seeded grammar body
		# replaces the stock shard (cached template), and
		# the bundle carries its trail.
		var tmpl := DeepTreeLooks.bundle_template(owner_peer,
			"frost", look, Color(0.6, 0.85, 1.0),
			Color(0.4, 0.75, 1.0))
		add_child(tmpl.duplicate())
		add_child(DeepTreeLooks.make_trail(look,
			DeepTreeLooks.shifted(Color(0.6, 0.85, 1.0),
				shift)))
	else:
		# Icy core (stock values when ungoverned; a
		# governed non-variant shard keeps the stock
		# silhouette with shifted palette/energies and no
		# trail — the stock shard has none).
		var core := MeshInstance3D.new()
		var shard := BoxMesh.new()
		shard.size = Vector3(0.12, 0.12, 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = DeepTreeLooks.shifted(
			Color(0.6, 0.85, 1.0), shift)
		mat.emission_enabled = true
		mat.emission = DeepTreeLooks.shifted(
			Color(0.4, 0.75, 1.0), shift)
		mat.emission_energy_multiplier = float(look.get(
			"emission_energy", 3.0)) if governed else 3.0
		shard.material = mat
		core.mesh = shard
		add_child(core)
	var light := OmniLight3D.new()
	light.light_color = DeepTreeLooks.shifted(
		Color(0.5, 0.8, 1.0), shift)
	light.light_energy = float(look.get("light_energy",
		1.2)) if governed else 1.2
	light.omni_range = 6.0
	add_child(light)
	if velocity.length() > 0.01:
		rotation.y = atan2(velocity.x, velocity.z)


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_life -= delta
	position += velocity * delta
	if _life <= 0.0 or position.y < 0.0:
		_shatter()
		return
	# Walls stop frost shards.
	if _is_in_wall():
		_shatter()
		return
	if multiplayer.is_server():
		var dungeon := get_tree().get_first_node_in_group("dungeon")
		var caster: Player = null
		if dungeon != null:
			caster = dungeon.get_player_node(owner_peer) as Player
		for node in get_tree().get_nodes_in_group("mobs"):
			var mob := node as Mob
			if mob == null or not mob.alive:
				continue
			# XZ distance: the shard flies at a fixed height, so use
			# horizontal distance to avoid tunneling past mobs.
			var a := Vector2(mob.global_position.x, mob.global_position.z)
			var b := Vector2(global_position.x, global_position.z)
			if a.distance_to(b) < 1.3:
				# Shatterglass (issue #210): the caster's
				# behavior reads the target's slow state
				# at the hit.
				var dealt := damage
				if caster != null:
					dealt *= caster.tree_shatterglass_mult(mob)
				if multiplayer.is_server():
					mob.take_damage(dealt, owner_peer, global_position)
				else:
					mob.rpc_id(NetworkManager.server_peer_id, "take_damage", dealt, owner_peer, global_position)
				# Permafrost: slows last +2s.
				var sdur := slow_duration
				if caster != null and caster.has_trait("permafrost"):
					sdur += 2.0
				mob.apply_slow(sdur, slow_mult)
				# Affinity: +2 per enemy hit (slow applied); per-enemy 5s cd inside.
				if caster != null:
					caster.gain_affinity("frost", 2.0, mob.get_instance_id())
				AudioManager.sfx("frost_hit", global_position)
				_shatter()
				return


func _shatter() -> void:
	if _exploded:
		return
	_exploded = true
	Effects.burst(get_parent(), global_position, Color(0.6, 0.85, 1.0), 12, 4.0)
	queue_free()
