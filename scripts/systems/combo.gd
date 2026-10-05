class_name Combo
extends RefCounted
## Combo Finishers (issue #8): named cross-class ability pairs.
## Server-side detection only. The detection hooks live in the existing
## server code paths (meteor impact, chain-lightning cast, fan/meteor kill
## sites) and check WORLD STATE -- totems, marks, slows, veils -- never who
## cast what. That is what makes finishers work in solo play: place a
## warhorn as warrior, switch class to mage, cast lightning inside the aura.
##
## Anti-cheese: finishers trigger on hits only, each finisher has a
## per-target 5s cooldown (same pattern as affinity's _affinity_enemy_cd),
## and finisher bonus damage can never retrigger another finisher --
## detection happens only at the hook sites, never inside take_damage.

## Per-target cooldown window, same 5s as affinity.
const FINISHER_COOLDOWN_MSEC := 5000
## Smoke Bombard: the meteor must land this close to a veiled player.
const SMOKE_VEIL_RADIUS := 6.0
## Shatter Cascade: frost nova radius / slow.
const FROST_NOVA_RADIUS := 3.0
const FROST_NOVA_SLOW_DURATION := 3.0
const FROST_NOVA_SLOW_MULT := 0.5
## Reciprocity Surge: team heal as a fraction of max HP.
const TEAM_HEAL_FRACTION := 0.2
## Smoke Bombard: blind duration on hit enemies.
const SMOKE_BLIND_DURATION := 4.0
## Stormcall: chain targets and damage multiplier.
const STORMCALL_CHAINS := 6
const STORMCALL_DAMAGE_MULT := 1.25
## Orbital Strike: meteor damage / radius multipliers.
const ORBITAL_DAMAGE_MULT := 2.0
const ORBITAL_RADIUS_MULT := 2.0
## Smoke Bombard: blast radius multiplier.
const SMOKE_RADIUS_MULT := 1.5

const COMBO_FINISHERS := [
	{
		"id": "orbital_strike",
		"name": "Orbital Strike",
		"trigger_desc": "Meteor impacts a marked target",
		"effect": "+100% meteor damage, 2x blast radius",
		"hint": "A marked foe, struck from the sky...",
	},
	{
		"id": "stormcall",
		"name": "Stormcall",
		"trigger_desc": "Chain lightning cast while standing inside a War Horn aura",
		"effect": "Chains 6 targets, +25% damage",
		"hint": "Lightning, empowered by the war horn's call...",
	},
	{
		"id": "shatter_cascade",
		"name": "Shatter Cascade",
		"trigger_desc": "Fan of Knives killing blow on a frost-slowed enemy",
		"effect": "Frost nova burst (3m, slow + damage)",
		"hint": "A frozen foe, shattered by a flurry of blades...",
	},
	{
		"id": "reciprocity_surge",
		"name": "Reciprocity Surge",
		"trigger_desc": "Meteor killing blow inside a Reciprocity aura",
		"effect": "Team heal burst (20% max HP, all living allies)",
		"hint": "Death within the circle of reciprocity mends the party...",
	},
	{
		"id": "smoke_bombard",
		"name": "Smoke Bombard",
		"trigger_desc": "Meteor impact inside smoke veil",
		"effect": "+50% blast radius, hit enemies blinded (miss chance, 4s)",
		"hint": "Fire falling through shadow blinds the enemy...",
	},
]

## "finisher_id:target_instance_id" -> msec of last trigger.
static var _finisher_cd := {}


static func reset_cooldowns() -> void:
	_finisher_cd.clear()


static func finisher_by_id(finisher_id: String) -> Dictionary:
	for f in COMBO_FINISHERS:
		if str(f["id"]) == finisher_id:
			return f
	return {}


static func _now_msec(now_msec: int) -> int:
	return now_msec if now_msec >= 0 else int(Time.get_ticks_msec())


static func _cd_ok(finisher_id: String, target_id: int, now: int) -> bool:
	var key := "%s:%d" % [finisher_id, target_id]
	if _finisher_cd.has(key) and now - int(_finisher_cd[key]) < FINISHER_COOLDOWN_MSEC:
		return false
	return true


static func _cd_mark(finisher_id: String, target_id: int, now: int) -> void:
	_finisher_cd["%s:%d" % [finisher_id, target_id]] = now


## True if pos is inside any live aura of the given totem id.
static func aura_covering(totems: Array, pos: Vector3, totem_id: String) -> bool:
	for t in totems:
		var n := t as Node3D
		if n == null or not is_instance_valid(n):
			continue
		if str(n.get("totem_id")) != totem_id:
			continue
		var r := 6.0
		if n.has_method("aura_radius"):
			r = float(n.call("aura_radius"))
		if n.global_position.distance_to(pos) <= r:
			return true
	return false


## The veiled (smoke veil active) player within radius of pos, or null.
static func veiled_near(players: Array, pos: Vector3, radius: float) -> Node3D:
	for p in players:
		var n := p as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var stealthed = n.get("stealthed")
		if stealthed == null or not bool(stealthed):
			continue
		if n.global_position.distance_to(pos) <= radius:
			return n
	return null


## True if this hit killed the mob (was alive before, dead now). Hook sites
## use this so finisher bonus damage applied later in the same event (e.g. a
## frost nova that kills a mob before the fan loop reaches it) can never
## retrigger -- a mob that is already dead when its turn comes is skipped.
static func note_kill(mob: Node, was_alive: bool) -> bool:
	return was_alive and not bool(mob.get("alive"))


## Meteor impact detection. Returns {"damage_mult", "radius_mult",
## "smoke_veil", "triggered": Array of finisher ids}. World state only; call
## before damage. Orbital Strike keys its per-enemy cooldown to the marked
## target. Smoke Bombard reports veil presence here; the blind itself is
## per-enemy gated via smoke_blind_ok() at the damage loop.
static func check_meteor_impact(mobs: Array, impact_pos: Vector3, base_radius: float,
		totems: Array, players: Array, now_msec: int = -1) -> Dictionary:
	var now := _now_msec(now_msec)
	var out := {"damage_mult": 1.0, "radius_mult": 1.0, "smoke_veil": false, "triggered": []}
	# Orbital Strike: a marked target inside the blast.
	var marked: Node3D = null
	for n in mobs:
		var m := n as Node3D
		if m == null or not is_instance_valid(m):
			continue
		if not bool(m.get("alive")):
			continue
		if m.global_position.distance_to(impact_pos) > base_radius:
			continue
		if m.has_method("is_marked") and bool(m.call("is_marked")):
			marked = m
			break
	if marked != null and _cd_ok("orbital_strike", marked.get_instance_id(), now):
		_cd_mark("orbital_strike", marked.get_instance_id(), now)
		out["damage_mult"] = ORBITAL_DAMAGE_MULT
		out["radius_mult"] = ORBITAL_RADIUS_MULT
		(out["triggered"] as Array).append("orbital_strike")
	# Smoke Bombard: impact inside a smoke veil. The veil gates the bigger
	# blast; the blind on hit enemies is per-enemy cooldown gated (see
	# smoke_blind_ok), same as affinity's per-enemy pattern.
	var veiled := veiled_near(players, impact_pos, SMOKE_VEIL_RADIUS)
	if veiled != null:
		out["radius_mult"] = float(out["radius_mult"]) * SMOKE_RADIUS_MULT
		out["smoke_veil"] = true
	return out


## Smoke Bombard blind gate: each enemy can only be smoke-blinded once per
## 5s (per-enemy cooldown, affinity pattern). Returns true when the blind
## should be applied to this enemy.
static func smoke_blind_ok(mob: Node, now_msec: int = -1) -> bool:
	var now := _now_msec(now_msec)
	var mid := mob.get_instance_id()
	if not _cd_ok("smoke_bombard", mid, now):
		return false
	_cd_mark("smoke_bombard", mid, now)
	return true


## Chain-lightning cast detection. Stormcall: the caster stands inside a
## War Horn damage aura. Returns {"triggered", "id", "chain_targets",
## "damage_mult"}. The per-enemy cooldown is keyed to the first chain target
## (the enemy the empowered chain starts on); falls back to the caster when
## the cast hits nothing.
static func check_lightning_cast(caster_pos: Vector3, caster: Node,
		totems: Array, first_target: Node = null, now_msec: int = -1) -> Dictionary:
	var out := {"triggered": false, "id": "", "chain_targets": 0, "damage_mult": 1.0}
	if not aura_covering(totems, caster_pos, "warhorn"):
		return out
	var now := _now_msec(now_msec)
	var key_id := first_target.get_instance_id() if first_target != null else (caster.get_instance_id() if caster != null else 0)
	if not _cd_ok("stormcall", key_id, now):
		return out
	_cd_mark("stormcall", key_id, now)
	out["triggered"] = true
	out["id"] = "stormcall"
	out["chain_targets"] = STORMCALL_CHAINS
	out["damage_mult"] = STORMCALL_DAMAGE_MULT
	return out


## Fan of Knives killing blow on a frost-slowed enemy -> Shatter Cascade.
## The caller confirms the kill and the slowed state; this enforces only the
## per-enemy cooldown.
static func check_fan_kill(mob: Node, now_msec: int = -1) -> bool:
	var now := _now_msec(now_msec)
	var mid := mob.get_instance_id()
	if not _cd_ok("shatter_cascade", mid, now):
		return false
	_cd_mark("shatter_cascade", mid, now)
	return true


## Meteor killing blow inside a Reciprocity aura -> Reciprocity Surge.
static func check_meteor_kill(impact_pos: Vector3, mob: Node,
		totems: Array, now_msec: int = -1) -> bool:
	if not aura_covering(totems, impact_pos, "reciprocity"):
		return false
	var now := _now_msec(now_msec)
	var mid := mob.get_instance_id()
	if not _cd_ok("reciprocity_surge", mid, now):
		return false
	_cd_mark("reciprocity_surge", mid, now)
	return true


## Shatter Cascade effect: frost nova -- slows and damages mobs in radius.
## Server-side. Nova kills cannot retrigger finishers: detection lives only
## at the hook sites, never inside take_damage, and the fan hook skips mobs
## that are already dead when their turn comes (see note_kill).
static func apply_frost_nova(tree: SceneTree, center: Vector3, damage: float, attacker: int) -> void:
	for n in tree.get_nodes_in_group("mobs"):
		var m := n as Node3D
		if m == null or not is_instance_valid(m):
			continue
		if not bool(m.get("alive")):
			continue
		if m.global_position.distance_to(center) > FROST_NOVA_RADIUS:
			continue
		if m.has_method("apply_slow"):
			m.call("apply_slow", FROST_NOVA_SLOW_DURATION, FROST_NOVA_SLOW_MULT)
		m.rpc_id(NetworkManager.server_id, "take_damage", damage, attacker, center)


## Reciprocity Surge effect: 20% max-HP heal burst to all living allies.
## Server-side; mirrors the totem heal RPC pattern.
static func apply_team_heal(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group("players"):
		var p := n as Node
		if p == null or not is_instance_valid(p):
			continue
		if not bool(p.get("alive")):
			continue
		var amt := 0.0
		var max_hp = p.get("max_hp")
		if max_hp != null:
			amt = float(max_hp) * TEAM_HEAL_FRACTION
		if amt > 0.0 and p.has_method("heal"):
			p.rpc_id(p.get_multiplayer_authority(), "heal", amt)


## Banner + SFX for a triggered finisher. The dungeon RPC fans out to every
## peer (gold banner + shared thunderclap), so clients see it too.
## Server-side: records the codex discovery (first trigger shows a toast).
static func announce_finisher(tree: SceneTree, finisher_id: String) -> void:
	var is_new := SaveManager.add_combo_discovered(finisher_id)
	var dungeon := tree.get_first_node_in_group("dungeon")
	if dungeon == null or not dungeon.has_method("announce_combo"):
		return
	dungeon.rpc("announce_combo", finisher_id, is_new)

