extends Node
## Issue #212 validation driver: the live timer-loop legs
## the -s suite structurally cannot run for issue #210
## slice B1 (the loops' coroutines outlive fixture
## teardown there, so B1 aggregate/source-pinned them;
## the Senior Engineer ruled these legs owed, not
## optional). Boots the REAL dungeon with a mage
## Player_1 as the caster and drives the shipped casts
## against live fixture mobs:
##   1. Stasis Burst fires at freeze end for its authored
##      value (caster damage x 1.0) on captured targets -
##      with a no-variant control showing no burst.
##   2. Blizzard tick count = 8 + duration_add steps.
##   3. Tempest strike count = 12 + 2 x duration_add
##      steps (tempest's duration_add unit is 1.0 s).
## Fixture ownership is injected as raw tree_owned ids
## (found by scanning DeepTree generation at TREE_SEED)
## plus _recompute_tree_aggregates - the suite's own
## fixture pattern; aggregates are never faked.
##
## Run under Xvfb (never --headless - the standing
## scene-check rule):
##   xvfb-run -a godot --path . res://scenes/dungeon/deep_tree_timer_check.tscn
##
## This is a test harness only. Nothing here ships in
## gameplay.

const DeepTree := preload(
	"res://scripts/progression/deep_tree.gd")
const MobScene := preload("res://scenes/mobs/mob.tscn")
const GoblinData := preload("res://data/mobs/goblin.tres")

var _pass := 0
var _fail := 0
var _dungeon: Node = null
var _player: Node = null
var _mob_seq := 9000


func _ready() -> void:
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method(
			"set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	await get_tree().process_frame
	NetworkManager.selected_class_id = "mage"
	Dungeon.saved_player_state = {}
	Dungeon.next_theme_id = "dungeon"
	Dungeon.next_seed = 424242
	Dungeon.next_level_number = 1
	var packed := load(
		"res://scenes/dungeon/dungeon.tscn") as PackedScene
	_dungeon = packed.instantiate()
	get_tree().root.add_child(_dungeon)
	get_tree().current_scene = _dungeon
	for i in 16:
		await get_tree().physics_frame
	_player = _dungeon.call("_my_player")
	_check(_player != null,
		"the dungeon boots with a mage Player_1 caster")
	if _player == null:
		_finish()
		return
	await _leg_stasis()
	await _leg_blizzard()
	await _leg_tempest()
	_finish()


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("[TIMER] PASS: ", label)
	else:
		_fail += 1
		print("[TIMER] FAIL: ", label)


func _finish() -> void:
	print("[TIMER] SUMMARY: %d passed, %d failed"
		% [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _purge_strays(keep: Node) -> void:
	for n in get_tree().get_nodes_in_group("mobs"):
		if n != keep:
			n.queue_free()


func _spawn_mob(at: Vector3) -> Node:
	_mob_seq += 1
	var m = MobScene.instantiate()
	# setup BEFORE add_child: Mob._ready reads the data
	# setup installs, and an error there aborts _ready
	# mid-initialization (the suite fixture order).
	m.call("setup", _mob_seq, GoblinData, 500.0, 1.0,
		false)
	m.position = at
	_dungeon.add_child(m)
	return m


func _own(ids: Array) -> void:
	_player.set("tree_owned", ids)
	_player.call("_recompute_tree_aggregates")


## Count distinct hp drops on a mob over a time window
## (polling every physics frame). Returns the drop sizes
## in order. purge=true also frees stray mobs throughout
## (the tempest legs: the random target pool must stay a
## pool of one).
func _count_drops(m: Node, seconds: float,
		purge: bool = false) -> Array:
	var drops: Array = []
	var last := float(m.get("hp"))
	var deadline := Time.get_ticks_msec() + int(seconds
		* 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if purge:
			_purge_strays(m)
		if not is_instance_valid(m):
			break
		var hp := float(m.get("hp"))
		if hp < last - 0.001:
			drops.append(last - hp)
			last = hp
	return drops


func _find_variant(branch: int, variant_id: String) -> int:
	# Variants are capstone-archetype nodes with
	# kind == "variant" and params.variant set (the
	# generation's own shape, read first-hand).
	for ring in range(6, 601, 6):
		var node: Dictionary = DeepTree.node_for(
			DeepTree.TREE_SEED, "mage", branch, ring, 0)
		if str(node.get("archetype", "")) == "capstone" \
				and str(node.get("kind", "")) \
					== "variant" \
				and str((node.get("params", {}) as
					Dictionary).get("variant", "")) \
					== variant_id:
			return int(node.get("id", -1))
	return -1


func _find_duration_node(branch: int, skill: String) -> Array:
	# [node_id, steps] for the first modifier node with a
	# duration_add component for the skill (modifier
	# params carry a components array, read first-hand).
	for ring in range(1, 61):
		var width := DeepTree.width(DeepTree.TREE_SEED,
			branch, ring)
		for idx in width:
			var node: Dictionary = DeepTree.node_for(
				DeepTree.TREE_SEED, "mage", branch,
				ring, idx)
			if str(node.get("archetype", "")) \
					!= "modifier":
				continue
			if str(node.get("target", "")) != skill:
				continue
			var params: Dictionary = node.get("params",
				{})
			for comp in params.get("components", []):
				var c: Dictionary = comp
				if str(c.get("param", "")) \
						== "duration_add":
					return [int(node.get("id", -1)),
						int(c.get("steps", 0))]
	return [-1, 0]


# ------------------------------------------------------------------
# Leg 1: Stasis Burst.
# ------------------------------------------------------------------
func _leg_stasis() -> void:
	var base: Vector3 = _player.global_position
	# Control: no variant owned - the freeze lands, the
	# freeze ends, and NO burst damage event fires.
	var mob_a = _spawn_mob(base + Vector3(3, 0.5, 0))
	var hp_a0 := float(mob_a.get("hp"))
	_player.call("_activate_glacial_prison")
	await get_tree().physics_frame
	_check(float(mob_a.get("_slow_mult")) == 0.0,
		"stasis control: the prison froze the target solid")
	var drops_a := await _count_drops(mob_a, 4.2)
	_check(drops_a.is_empty()
		and float(mob_a.get("hp")) == hp_a0,
		"stasis control: no burst at freeze end without the variant")
	mob_a.queue_free()
	# Variant leg: burst = the caster's damage at
	# activation (authored x 1.0), fired at freeze end.
	var nid := _find_variant(2, "stasis_burst")
	_check(nid >= 0,
		"stasis fixture: a stasis_burst variant node exists in frost generation")
	if nid < 0:
		return
	_own([nid])
	_player.set("ability_cds",
		{"glacial_prison": 0.0})
	var mob_b = _spawn_mob(base + Vector3(3, 0.5, 0))
	var burst := float(_player.get("damage"))
	_player.call("_activate_glacial_prison")
	var drops_b := await _count_drops(mob_b, 4.2)
	print("[TIMER] stasis burst drops: ", drops_b,
		" (authored burst: ", burst, ")")
	_check(drops_b.size() == 1,
		"stasis: exactly one burst event fires at freeze end")
	if drops_b.size() == 1:
		var got := float(drops_b[0])
		_check(is_equal_approx(got, burst)
			or is_equal_approx(got, burst * 1.25),
			"stasis: the burst lands for its authored value (x1.25 = the shipped shatter composition if the slow flag outlives the timer)")
	mob_b.queue_free()
	_own([])


# ------------------------------------------------------------------
# Leg 2: Blizzard tick count.
# ------------------------------------------------------------------
func _leg_blizzard() -> void:
	var base: Vector3 = _player.global_position
	var owner := int(_player.get_multiplayer_authority())
	# Stock: 8 ticks of 10 = the count leg (per-tick size
	# is not the claim; slowed ticks compose +25% shatter
	# from tick 2 by the shipped rules).
	var mob_a = _spawn_mob(base + Vector3(6, 0.5, 0))
	mob_a.call("apply_slow", 60.0, 0.0) # frozen: stays in radius
	_player.call("cast_blizzard", mob_a.global_position,
		10.0, owner, 9101)
	var drops_a := await _count_drops(mob_a, 5.2)
	print("[TIMER] blizzard stock drops: ", drops_a)
	_check(drops_a.size() == 8,
		"blizzard stock: exactly 8 ticks land")
	mob_a.queue_free()
	# Extended: +1 tick per duration_add step.
	var found := _find_duration_node(2, "blizzard")
	_check(int(found[0]) >= 0,
		"blizzard fixture: a duration_add node exists in frost generation")
	if int(found[0]) < 0:
		return
	var steps := int(found[1])
	_own([int(found[0])])
	var agg := float(_player.call("_tree_skill_mod",
		"blizzard", "duration_add", 0.0))
	_check(is_equal_approx(agg, steps * 0.5),
		"blizzard fixture: the aggregate reads steps x 0.5 s")
	var mob_b = _spawn_mob(base + Vector3(6, 0.5, 0))
	mob_b.call("apply_slow", 60.0, 0.0)
	_player.call("cast_blizzard", mob_b.global_position,
		10.0, owner, 9102)
	var drops_b := await _count_drops(mob_b,
		5.2 + steps * 0.6)
	print("[TIMER] blizzard extended drops (steps ",
		steps, "): ", drops_b)
	_check(drops_b.size() == 8 + steps,
		"blizzard: tick count extends by duration_add steps (8 + %d)" % steps)
	mob_b.queue_free()
	_own([])


# ------------------------------------------------------------------
# Leg 3: Tempest strike count.
# ------------------------------------------------------------------
func _leg_tempest() -> void:
	var base: Vector3 = _player.global_position
	var owner := int(_player.get_multiplayer_authority())
	# Stock: one candidate in the 15 m radius - every
	# strike lands on it. 12 strikes x 10.
	var mob_a = _spawn_mob(base + Vector3(5, 0.5, 0))
	_purge_strays(mob_a)
	_player.call("cast_tempest", 10.0, owner, 9201)
	var drops_a := await _count_drops(mob_a, 7.4, true)
	print("[TIMER] tempest stock drops: ", drops_a)
	_check(drops_a.size() == 12,
		"tempest stock: exactly 12 strikes land")
	mob_a.queue_free()
	# Extended: tempest's duration_add unit is 1.0 s =
	# 2 strikes per step.
	var found := _find_duration_node(3, "tempest")
	_check(int(found[0]) >= 0,
		"tempest fixture: a duration_add node exists in storm generation")
	if int(found[0]) < 0:
		return
	var steps := int(found[1])
	_own([int(found[0])])
	var agg := float(_player.call("_tree_skill_mod",
		"tempest", "duration_add", 0.0))
	_check(is_equal_approx(agg, steps * 1.0),
		"tempest fixture: the aggregate reads steps x 1.0 s")
	var mob_b = _spawn_mob(base + Vector3(5, 0.5, 0))
	_purge_strays(mob_b)
	_player.call("cast_tempest", 10.0, owner, 9202)
	var drops_b := await _count_drops(mob_b,
		7.4 + steps * 1.1, true)
	print("[TIMER] tempest extended drops (steps ",
		steps, "): ", drops_b)
	_check(drops_b.size() == 12 + 2 * steps,
		"tempest: strike count extends by duration_add steps x 2 (12 + %d)" % (2 * steps))
	mob_b.queue_free()
	_own([])
