class_name Structure
extends Node3D
## Architect placeable: walls, turrets, traps, keystones.
## Placed via dungeon RPC on all peers; each peer simulates visuals,
## the server applies damage/effects (totem pattern).

const STRUCTURE_CAP := 6
const KEYSTONE_RADIUS := 6.0
const TURRET_RANGE := 12.0
const TURRET_TICK := 1.2
const TRAP_RADIUS := 2.0
const TRAP_AOE := 2.5
const DEMOLISH_RADIUS := 3.0

const STATS := {
	"sentry_turret": {"hp": 100.0, "life": 60.0},
	"bulwark_wall": {"hp": 150.0, "life": 20.0},
	"spike_trap": {"hp": 60.0, "life": 60.0},
	"keystone": {"hp": 200.0, "life": 45.0},
}

var structure_id := ""
var owner_peer := 0
var rank := 1
var max_hp := 100.0
var hp := 100.0
var uid := ""

var _life := 60.0
var _fire_tick := 0.0
var _triggered := false
var _ring: MeshInstance3D = null


func setup(p_id: String, p_owner: int, p_rank: int = 1, hp_mult: float = 1.0, p_uid: String = "") -> void:
	structure_id = p_id
	owner_peer = p_owner
	rank = p_rank
	uid = p_uid
	var st: Dictionary = STATS.get(structure_id, {"hp": 100.0, "life": 30.0})
	max_hp = float(st["hp"]) * hp_mult
	hp = max_hp
	_life = float(st["life"])


func _ready() -> void:
	add_to_group("structures")
	match structure_id:
		"bulwark_wall":
			_build_wall()
		"sentry_turret":
			_build_turret()
		"spike_trap":
			_build_trap()
		"keystone":
			_build_keystone()
		_:
			_build_wall()
	AudioManager.sfx("totem_place", global_position)


func _add_mat(mi: MeshInstance3D, c: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mi.set_surface_override_material(0, mat)


func _glow(mi: MeshInstance3D, c: Color, energy: float = 2.0) -> void:
	var mat := mi.get_surface_override_material(0) as StandardMaterial3D
	if mat != null:
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = energy


func _billboard(path: String, height_m: float, y_off: float) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = load(path) as Texture2D
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.pixel_size = height_m / 256.0
	sp.position.y = y_off
	sp.shaded = true
	return sp


func _build_wall() -> void:
	# Mossy stone slab sprite, 3m wide x 2.5m tall (billboarded pixel art).
	add_child(_billboard("res://assets/sprites/structures/wall.png", 2.5, 1.25))
	# Blocks enemies only: physics layer 2. Mobs mask layer 2; players don't.
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 2.5, 0.6)
	cs.shape = shape
	cs.position.y = 1.25
	body.add_child(cs)
	add_child(body)


func _build_turret() -> void:
	# Brass/wood turret sprite with glowing amber sight (billboarded pixel art).
	add_child(_billboard("res://assets/sprites/structures/turret.png", 1.9, 0.95))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.light_energy = 1.0
	light.omni_range = 4.0
	light.position.y = 1.8
	add_child(light)


func _build_trap() -> void:
	# Dark iron spike-plate sprite (billboarded pixel art), ~1.6m across.
	add_child(_billboard("res://assets/sprites/structures/trap.png", 1.6, 0.15))
	# Hidden: only the owning player sees the shimmer.
	if int(multiplayer.get_unique_id()) == owner_peer:
		var shim := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.9
		sm.bottom_radius = 0.9
		sm.height = 0.02
		shim.mesh = sm
		shim.position.y = 0.1
		_add_mat(shim, Color(1.0, 0.85, 0.3))
		_glow(shim, Color(1.0, 0.85, 0.3))
		add_child(shim)


func _build_keystone() -> void:
	# Rune-carved obelisk sprite (billboarded pixel art), ~2.6m tall.
	add_child(_billboard("res://assets/sprites/structures/keystone.png", 2.6, 1.3))
	# Ground ring showing the 6m buff radius.
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = KEYSTONE_RADIUS - 0.12
	torus.outer_radius = KEYSTONE_RADIUS
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.5, 0.8, 1.0, 0.5)
	rmat.emission_enabled = true
	rmat.emission = Color(0.5, 0.8, 1.0)
	rmat.emission_energy_multiplier = 1.5
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = rmat
	_ring.mesh = torus
	_ring.position.y = 0.1
	add_child(_ring)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.8, 1.0)
	light.light_energy = 1.5
	light.omni_range = KEYSTONE_RADIUS + 2.0
	light.position.y = 2.0
	add_child(light)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_expire()
		return
	match structure_id:
		"sentry_turret":
			_tick_turret(delta)
		"spike_trap":
			_tick_trap()


func _tick_turret(delta: float) -> void:
	_fire_tick -= delta
	if _fire_tick > 0.0:
		return
	var interval := TURRET_TICK
	if keystone_near(get_tree(), global_position, owner_peer):
		interval /= 1.3
	_fire_tick = interval
	var target := _pick_target()
	if target == null:
		return
	var muzzle := global_position + Vector3(0, 1.6, 0)
	var aim: Vector3 = target.global_position + Vector3(0, 0.9, 0)
	_spawn_tracer(muzzle, aim)
	Effects.burst(get_parent(), aim, Color(1.0, 0.7, 0.3), 6, 3.0)
	AudioManager.sfx("bow_shot", global_position, 1.2, 0.5)
	if not multiplayer.is_server():
		return
	var dmg := _owner_damage() * 0.6 * _rank_mult()
	if multiplayer.is_server():
		target.take_damage(dmg, owner_peer, target.global_position)
	else:
		target.rpc_id(NetworkManager.server_id, "take_damage", dmg, owner_peer, target.global_position)


## Nearest alive mob in range; marked targets (Rogue synergy) win ties.
func _pick_target() -> Mob:
	var best: Mob = null
	var best_d := TURRET_RANGE
	var marked_best: Mob = null
	var marked_d := TURRET_RANGE
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m == null or not m.alive:
			continue
		var d := global_position.distance_to(m.global_position)
		if d > TURRET_RANGE:
			continue
		if m.is_marked():
			if d < marked_d:
				marked_d = d
				marked_best = m
		elif d < best_d:
			best_d = d
			best = m
	return marked_best if marked_best != null else best


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.4)
	bm.material = mat
	beam.mesh = bm
	get_parent().add_child(beam)
	beam.global_position = (from + to) * 0.5
	beam.look_at(to, Vector3.UP)
	get_tree().create_timer(0.12).timeout.connect(beam.queue_free)


func _tick_trap() -> void:
	if _triggered:
		return
	for n in get_tree().get_nodes_in_group("mobs"):
		var m := n as Mob
		if m == null or not m.alive:
			continue
		if m.global_position.distance_to(global_position) > TRAP_RADIUS:
			continue
		_triggered = true
		Effects.burst(get_parent(), global_position + Vector3(0, 0.5, 0), Color(0.7, 0.7, 0.75), 20, 5.0)
		AudioManager.sfx("explosion", global_position, 1.3, 0.6)
		if multiplayer.is_server():
			var dmg := _owner_damage() * 1.5 * _rank_mult()
			for n2 in get_tree().get_nodes_in_group("mobs"):
				var m2 := n2 as Mob
				if m2 == null or not m2.alive:
					continue
				if m2.global_position.distance_to(global_position) < TRAP_AOE:
					if multiplayer.is_server():
						m2.take_damage(dmg, owner_peer, global_position)
					else:
						m2.rpc_id(NetworkManager.server_id, "take_damage", dmg, owner_peer, global_position)
					m2.apply_slow(3.0, 0.6)
		queue_free()
		return


## Server-side HP loss. Mobs call this directly (they only run on the server);
## on death the server tells every peer to play rubble FX and free its copy.
func take_structure_damage(amount: float, from_peer: int) -> void:
	if not multiplayer.is_server():
		return
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		var dungeon := get_tree().get_first_node_in_group("dungeon")
		if dungeon != null:
			dungeon.rpc("break_structure", uid)


## Demolish: big explosion, never the quiet expire path.
func demolish() -> void:
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.2), 30, 7.0)
	AudioManager.sfx("explosion", global_position)
	queue_free()


func _expire() -> void:
	# Quiet expire: dust puff, no explosion (explosions are Demolish's job).
	AudioManager.sfx("totem_expire", global_position)
	Effects.burst(get_parent(), global_position + Vector3(0, 0.8, 0), Color(0.6, 0.6, 0.6), 10, 3.0)
	queue_free()


## The placing player (server-side authoritative copy).
func _caster() -> Player:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null:
		return null
	return dungeon.get_player_node(owner_peer) as Player


func _owner_damage() -> float:
	var c := _caster()
	return c.damage if c != null else 12.0


func _rank_mult() -> float:
	return 1.0 + float(rank - 1) * 0.25


## True if one of owner's keystones is within 6m of pos.
static func keystone_near(tree: SceneTree, pos: Vector3, owner: int) -> bool:
	for n in tree.get_nodes_in_group("structures"):
		var k := n as Structure
		if k == null or k.structure_id != "keystone":
			continue
		if k.owner_peer != owner or k.is_queued_for_deletion():
			continue
		var d: Vector3 = k.global_position - pos
		d.y = 0.0
		if d.length() <= KEYSTONE_RADIUS:
			return true
	return false
