class_name Totem
extends Node3D
## Warrior placeable. Pulsing aura that buffs allies or hinders enemies.
## Placed via RPC; each peer simulates visuals, server applies effects.

const RADIUS := 6.0
const DURATION := 20.0
const TICK := 1.0

var totem_id := ""
var owner_peer := 0
var _affinity_awarded := false
var rank := 1

var _life := DURATION
## Issue #210 (Doom Herald): aura applications counted
## for the 5 s pulse cadence.
var _pulse := 0
var _tick := 0.0
var _ring: MeshInstance3D


func setup(p_id: String, p_owner: int, p_rank: int = 1) -> void:
	totem_id = p_id
	owner_peer = p_owner
	rank = p_rank
	# Signature totems have fixed lifetimes (fixed power, no ranks).
	if totem_id == "sanctuary_totem":
		_life = 5.0
	elif totem_id == "doom_totem":
		_life = 10.0


func _ready() -> void:
	add_to_group("totems")
	# Issue #210 (slice B3): the tree's duration_add joins
	# the totem's lifetime (the base DURATION, or the
	# signature's fixed lifetime set in setup()).
	var dcaster := _caster()
	if dcaster != null:
		_life += dcaster.tree_totem_mod(totem_id,
			"duration_add", 0.0)
	# Wide Ward: +25% radius on Warden totems — scale the visual ring now.
	var vis_r := _aura_radius()
	# Totem pole: stacked stone/wood.
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.4
	bc.bottom_radius = 0.5
	bc.height = 0.3
	base.mesh = bc
	base.position.y = 0.15
	_add_mat(base, Color(0.45, 0.42, 0.4))
	add_child(base)
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.18
	pc.bottom_radius = 0.22
	pc.height = 1.6
	pole.mesh = pc
	pole.position.y = 1.1
	_add_mat(pole, Color(0.5, 0.38, 0.22))
	add_child(pole)
	var top := MeshInstance3D.new()
	var ts := SphereMesh.new()
	ts.radius = 0.28
	ts.height = 0.56
	top.mesh = ts
	top.position.y = 2.1
	_add_mat(top, _color())
	var glow_mat := top.get_surface_override_material(0) as StandardMaterial3D
	if glow_mat != null:
		glow_mat.emission_enabled = true
		glow_mat.emission = _color()
		glow_mat.emission_energy_multiplier = 3.0
	add_child(top)
	# Colored light.
	var light := OmniLight3D.new()
	light.light_color = _color()
	light.light_energy = 1.5
	light.omni_range = vis_r + 2.0
	light.position.y = 2.0
	add_child(light)
	# Ground ring showing the aura radius.
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = vis_r - 0.12
	torus.outer_radius = vis_r
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = _color()
	rmat.emission_enabled = true
	rmat.emission = _color()
	rmat.emission_energy_multiplier = 1.5
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color.a = 0.6
	torus.material = rmat
	_ring.mesh = torus
	_ring.position.y = 0.1
	add_child(_ring)
	AudioManager.sfx("totem_place", global_position)


func _add_mat(mi: MeshInstance3D, c: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mi.set_surface_override_material(0, mat)


func _color() -> Color:
	match totem_id:
		"bulwark":
			return Color(0.4, 0.7, 1.0)
		"warhorn":
			return Color(1.0, 0.6, 0.2)
		"stoneskin":
			return Color(0.7, 0.65, 0.6)
		"rally":
			return Color(1.0, 0.9, 0.3)
		"sanctuary_totem":
			return Color(1.0, 0.9, 0.4)
		"doom_totem":
			return Color(0.7, 0.15, 0.2)
		_:
			return Color(0.4, 1.0, 0.5)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_fade()
		return
	# Pulse the ring.
	if _ring != null:
		var s := 1.0 + sin(Time.get_ticks_msec() / 300.0) * 0.03
		_ring.scale = Vector3(s, 1, s)
	# Server applies the aura effect.
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		# Issue #210 (Oathkeeper): the totem ticks faster
		# while its owner is downed (the next interval is
		# set here, through the same caster resolution).
		var ocaster := _caster()
		if ocaster != null and bool(ocaster.get("downed")):
			var oath_pct: float = ocaster.tree_totem_behavior("oathkeeper")
			if oath_pct > 0.0:
				_tick = TICK / (1.0 + oath_pct / 100.0)
		_apply_aura()


func _apply_aura() -> void:
	# Affinity: award once per placement (first tick).
	if not _affinity_awarded:
		_affinity_awarded = true
		_award_placement_affinity()
	var r := _aura_radius()
	var strength := _aura_strength()
	var caster := _caster()
	# Issue #210 (Strength in Numbers): conqueror auras
	# run stronger while 3+ enemies stand inside — the
	# count is taken here, where the radius is known;
	# the boost folds into the same strength the
	# branches (and doom's stored magnitude) read.
	if caster != null and totem_id in ["bulwark",
			"warhorn", "rally", "doom_totem"]:
		var sin_pct: float = caster.tree_totem_behavior(
			"strength_in_numbers")
		if sin_pct > 0.0:
			var foes := 0
			for n in get_tree().get_nodes_in_group("mobs"):
				var fm := n as Mob
				if fm != null and fm.alive and fm.global_position.distance_to(global_position) < r:
					foes += 1
			if foes >= 3:
				strength *= 1.0 + sin_pct / 100.0
	match totem_id:
		"reciprocity":
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < r:
					p.rpc_id(p.get_multiplayer_authority(), "heal", 4.0 * _rank_mult() * strength)
			# Issue #210 (Thorn Mirror, the SE's adopted
			# form): the tick also slows enemies in
			# radius 20% for 2 s, on its own cadence.
			if caster != null and caster.tree_totem_variant("reciprocity") == "thorn_mirror":
				for n in get_tree().get_nodes_in_group("mobs"):
					var tm := n as Mob
					if tm == null or not tm.alive:
						continue
					if tm.global_position.distance_to(global_position) < r:
						tm.apply_slow(2.0, 0.8)
		"bulwark":
			var relentless := caster != null and caster.has_trait("relentless")
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m == null or not m.alive:
					continue
				if m.global_position.distance_to(global_position) < r:
					m.apply_slow(TICK * 1.5, 0.6 / strength)
					# Relentless: mark so bulwark-slowed enemies deal -10% damage.
					if relentless:
						m.bulwark_slow_t = TICK * 1.5
		"warhorn":
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < r:
					p.rpc_id(p.get_multiplayer_authority(), "apply_warhorn", TICK * 1.5, strength)
					# Issue #210 (Thunderhead Horn): the
					# aura also grants attack speed (the
					# war drums verb, at its own magnitude).
					if caster != null and caster.tree_totem_variant("warhorn") == "thunderhead_horn":
						p.rpc_id(p.get_multiplayer_authority(), "apply_war_drums", TICK * 1.5)
		"stoneskin":
			var shared := caster != null and caster.has_trait("shared_vitality")
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < r:
					p.rpc_id(p.get_multiplayer_authority(), "apply_stoneskin", TICK * 1.5, strength)
					# Issue #210 (Living Stone): the totem
					# also heals allies in radius per tick
					# (authored 2.0, the heal-tick form).
					if caster != null and caster.tree_totem_variant("stoneskin") == "living_stone":
						p.rpc_id(p.get_multiplayer_authority(), "heal", 2.0 * _rank_mult() * strength)
					# Shared Vitality: Stoneskin also grants +10% move speed.
					if shared:
						p.rpc_id(p.get_multiplayer_authority(), "apply_shared_vitality", TICK * 1.5)
		"rally":
			var drums := caster != null and caster.has_trait("war_drums")
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < r:
					p.rpc_id(p.get_multiplayer_authority(), "apply_rally", TICK * 1.5, strength)
					# Issue #210 (Forced March): Rally also
					# grants damage (the warhorn verb, at
					# Rally's own strength).
					if caster != null and caster.tree_totem_variant("rally") == "forced_march":
						p.rpc_id(p.get_multiplayer_authority(), "apply_warhorn", TICK * 1.5, strength)
					# War Drums: Rally also grants +10% attack speed.
					if drums:
						p.rpc_id(p.get_multiplayer_authority(), "apply_war_drums", TICK * 1.5)
		"sanctuary_totem":
			# Warden signature: allies in radius are immune to damage.
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < r:
					p.rpc_id(p.get_multiplayer_authority(), "apply_sanctuary", TICK * 1.5)
					# Issue #210 (Aegis Dome): allies inside
					# also gain armor (the stoneskin verb
					# at its base strength).
					if caster != null and caster.tree_totem_variant("sanctuary_totem") == "aegis_dome":
						p.rpc_id(p.get_multiplayer_authority(), "apply_stoneskin", TICK * 1.5, 1.0)
		"doom_totem":
			# Conqueror signature: enemies in radius take +30% damage.
			# Issue #210: the magnitude is the caster's
			# stored vuln fold (0.30 base, x vuln_pct,
			# x the folded strength incl. Strength in
			# Numbers); Doom Herald pulses every 5 s.
			_pulse += 1
			var dvuln := 0.30 * strength
			if caster != null:
				dvuln *= 1.0 + caster.tree_totem_mod(
					"doom_totem", "vuln_pct", 0.0)
			var herald: bool = caster != null and caster.tree_totem_variant("doom_totem") == "doom_herald" and _pulse % 5 == 0
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m == null or not m.alive:
					continue
				if m.global_position.distance_to(global_position) < r:
					m.doom_t = TICK * 1.5
					m.doom_vuln = dvuln
					if herald:
						m.take_damage(12.0 * strength, owner_peer, global_position)


## The placing player (server-side authoritative copy).
func _caster() -> Player:
	var dungeon := get_tree().get_first_node_in_group("dungeon")
	if dungeon == null or not dungeon.has_method("get_player_node"):
		return null
	return dungeon.get_player_node(owner_peer) as Player


## Warden's Oath / Commanding Presence: +15% aura strength on matching totems.
func _aura_strength() -> float:
	var caster := _caster()
	if caster == null:
		return 1.0
	var strength := 1.0
	if totem_id in ["reciprocity", "stoneskin"] and caster.has_trait("wardens_oath"):
		strength = 1.15
	if totem_id in ["bulwark", "warhorn", "rally"] and caster.has_trait("commanding_presence"):
		strength = 1.15
	# Issue #210 (slice B3): the tree's magnitude channel
	# scales the branch's tick strength. Reciprocity's
	# channel is mend_pct — it scales the tick's heal
	# (the SE's ruling on the reciprocity premise flag:
	# no reflect mechanic exists; the channel is named
	# for what it scales).
	var mag_key: String = {"reciprocity": "mend_pct",
		"stoneskin": "armor_pct",
		"bulwark": "guard_pct", "warhorn": "aura_pct",
		"rally": "haste_pct"}.get(totem_id, "")
	if mag_key != "":
		strength *= 1.0 + caster.tree_totem_mod(
			totem_id, mag_key, 0.0)
	return strength


## Wide Ward: +25% aura radius on Warden totems.
func _aura_radius() -> float:
	var r := RADIUS
	var caster := _caster()
	if caster != null and totem_id in ["reciprocity", "stoneskin"] and caster.has_trait("wide_ward"):
		r *= 1.25
	# Issue #210 (slice B3): the tree's radius joins at
	# this same caster read, for every totem type.
	if caster != null:
		r += caster.tree_totem_mod(totem_id,
			"radius_add", 0.0)
	return r


## Public aura radius for combo-finisher world-state checks (issue #8).
func aura_radius() -> float:
	return _aura_radius()


func _rank_mult() -> float:
	return 1.0 + float(rank - 1) * 0.25


## Award affinity once per totem placement, per Appendix A.
func _award_placement_affinity() -> void:
	var caster := _caster()
	if caster == null:
		return
	var r := _aura_radius()
	var cast_id := "totem_%d" % get_instance_id()
	match totem_id:
		"reciprocity":
			# +2 per distinct ally healed, max +6.
			var count := 0
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < r:
					count += 1
			for i in mini(count, 3):
				caster.gain_affinity_capped("reciprocity", 2.0, -1, cast_id, 6.0)
		"bulwark":
			# +2 per distinct enemy slowed, max +6.
			var count := 0
			for n in get_tree().get_nodes_in_group("mobs"):
				var m := n as Mob
				if m == null or not m.alive:
					continue
				if m.global_position.distance_to(global_position) < r:
					count += 1
			for i in mini(count, 3):
				caster.gain_affinity_capped("bulwark", 2.0, -1, cast_id, 6.0)
		"warhorn", "stoneskin", "rally":
			# +3 base, +1 per extra ally, max +6.
			var count := 0
			for n in get_tree().get_nodes_in_group("players"):
				var p := n as Player
				if p == null or not p.alive:
					continue
				if p.global_position.distance_to(global_position) < r:
					count += 1
			if count > 0:
				var pts := minf(6.0, 3.0 + float(count - 1))
				caster.gain_affinity_capped(totem_id, pts, -1, cast_id, 6.0)


func _fade() -> void:
	AudioManager.sfx("totem_expire", global_position)
	Effects.burst(get_parent(), global_position + Vector3(0, 1.0, 0), _color(), 15, 4.0)
	queue_free()
