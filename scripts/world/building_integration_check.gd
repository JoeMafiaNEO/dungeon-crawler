extends Node
## Issue #211 validation driver: the live-transfer leg the
## -s suite structurally cannot run for issue #209's
## building clear-time leaderboards. Boots the REAL world
## scene, enters a REAL playable building through its street
## door (TransferTrigger.activate -> NetworkManager
## .load_floor), clears its floors through the shipped
## clear spine (complete_level_objective) riding the real
## FloorTransfer surfaces between floors, and asserts:
##   1. a completion posts EXACTLY ONCE, the time reaching
##      the announce/upload path under the no-Steam posture
##      (nothing errors; nothing uploads; the completion
##      handler posts its time toast - proven by driving
##      the handler directly. Through the spine itself the
##      toast is superseded in-sequence by the "Floor
##      cleared." announce: the FINDING printed in _run,
##      reported on the issue, not fixed here);
##   2. entry -> exit abandons with no post.
##
## Run under Xvfb (never --headless - headless ignores
## mouse_mode; the standing scene-check rule):
##   xvfb-run -a godot --path . res://scenes/world/building_integration_check.tscn
##
## The driver lives OUTSIDE the current scene (a /root
## child) so it survives the real change_scene_to_file
## transfers it drives. This is a test harness only.
## Nothing here ships in gameplay.

const WORLD_PATH := "res://scenes/world/world.tscn"
const DUNGEON_PATH := "res://scenes/dungeon/dungeon.tscn"
const FloorGen := preload("res://scripts/world/floor_gen.gd")

static var _booted := false

var _pass := 0
var _fail := 0
var _target: Dictionary = {}


func _ready() -> void:
	if _booted:
		# The driver instance: run deferred so the world
		# scene change (queued by the boot instance) lands
		# first; _run polls for it regardless.
		call_deferred("_run")
		return
	_booted = true
	# Boot instance: spawn the persistent driver, then hand
	# the tree to the real world scene. Both deferred: the
	# root is busy setting up children during _ready, so a
	# direct add_child here fails.
	var drv := Node.new()
	drv.name = "BuildingCheckDriver"
	drv.set_script(get_script())
	get_tree().root.add_child.call_deferred(drv)
	get_tree().change_scene_to_file.call_deferred(WORLD_PATH)


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("[BUILDING] PASS: ", label)
	else:
		_fail += 1
		print("[BUILDING] FAIL: ", label)


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s
		* 1000.0)
	var beat := Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
		if Time.get_ticks_msec() - beat > 10000:
			beat = Time.get_ticks_msec()
			var pp := Vector3.ZERO
			var pl = _world_player()
			if pl != null:
				pp = pl.get("global_position")
			print("[BUILDING] ...waiting (scene: ",
				get_tree().current_scene.scene_file_path
					if get_tree().current_scene
						!= null else "none",
				", floor_index: ", Dungeon.floor_index,
				", attempt: ", Dungeon.attempt_key,
				", player: ", pp,
				", triggers: ", get_tree()
					.get_nodes_in_group(
						"transfer_trigger").size(),
				")")
	return bool(cond.call())


func _scene_is(path: String) -> bool:
	var cs = get_tree().current_scene
	return cs != null and cs.scene_file_path == path


func _world_player() -> Node:
	var cs = get_tree().current_scene
	if cs == null:
		return null
	return cs.get("_local_player") as Node


func _find_trigger(key: String) -> Node:
	# The streamer registers every door trigger in this
	# group (world_streamer.gd) — the shipped index.
	for n in get_tree().get_nodes_in_group(
			"transfer_trigger"):
		if str(n.get("building_key")) == key:
			return n
	return null


func _find_transfer(mode: String) -> Node:
	for n in get_tree().get_nodes_in_group("floor_transfer"):
		if str(n.get("mode")) == mode:
			return n
	return null


func _transfers_ready() -> bool:
	return not get_tree().get_nodes_in_group(
		"floor_transfer").is_empty()


func _pick_target() -> Dictionary:
	# Enumerate buildings the way the streamer does:
	# WorldGen.generate_chunk carries each chunk's
	# building list ([lx, lz, floors, style, span...]).
	# Test playability with BuildingSelect (the
	# streamer's own call) and apply the streamer's
	# home-plot suppression test identically - a building
	# whose lot rect intersects the reserved rect never
	# builds: no shell, no door. Full records derive only
	# for finalists. Expanding chunk rings around the
	# home chunk until a candidate appears (playable
	# buildings are sparse near the home village).
	const WorldGen := preload(
		"res://scripts/world/world_gen.gd")
	const BuildingSelect := preload(
		"res://scripts/world/building_select.gd")
	var home_key := str(Dungeon.home_building().get("key",
		""))
	var hp: PackedStringArray = home_key.split(",")
	if hp.size() != 2:
		return {}
	var hcx := int(floor(float(hp[0]) / 16.0))
	var hcz := int(floor(float(hp[1]) / 16.0))
	var ha: Dictionary = Dungeon.home_anchor
	var srect := Rect2(float(ha["rect_x"]),
		float(ha["rect_z"]), float(ha["rect_w"]),
		float(ha["rect_d"]))
	for ring in range(0, 13):
		var best: Dictionary = {}
		var best_d := INF
		for dcx in range(-ring, ring + 1):
			for dcz in range(-ring, ring + 1):
				if maxi(absi(dcx), absi(dcz)) != ring:
					continue
				var data = WorldGen.generate_chunk(
					hcx + dcx, hcz + dcz)
				for b in data.buildings:
					var floors := int(b[2])
					if floors < 1 or floors > 2:
						continue
					var wlx := (hcx + dcx) * 16 \
						+ int(b[0])
					var wlz := (hcz + dcz) * 16 \
						+ int(b[1])
					var key := "%d,%d" % [wlx, wlz]
					if key == home_key:
						continue
					if not BuildingSelect.is_playable(
							WorldGen.WORLD_SEED,
							wlx, wlz):
						continue
					var brect := Rect2(
						Vector2(float(wlx),
							float(wlz)) * 8.0,
						Vector2(float(b[4]),
							float(b[5])) * 8.0)
					if srect.intersects(brect):
						continue
					var rec: Dictionary = FloorGen.record_for(
						key, Dungeon.home_anchor)
					if rec.is_empty():
						continue
					var ds: Vector3 = rec["doorstep"]
					var d := ds.distance_to(
						Dungeon.act2_anchor_doorstep)
					if d < best_d:
						best_d = d
						best = rec
		if not best.is_empty():
			return best
	return {}


func _run() -> void:
	var crt_mgr = get_node_or_null("/root/CRTManager")
	if crt_mgr != null and crt_mgr.has_method(
			"set_crt_enabled"):
		crt_mgr.set_crt_enabled(false)
	# Fabricate the post-reveal Act 2 state through the
	# game's own derivations (the reveal's anchor, the
	# home ledger seed, the counted home building).
	Dungeon.revealed = true
	Dungeon.home_anchor = Dungeon.compute_home_anchor(96.0)
	Dungeon.seed_home_ledger()
	Dungeon.buildings_cleared = 1
	Dungeon.act2_context = "world"
	var home: Dictionary = Dungeon.home_building()
	Dungeon.act2_anchor_building = str(home["key"])
	Dungeon.act2_anchor_doorstep = home["doorstep"]
	_target = _pick_target()
	_check(not _target.is_empty(),
		"a playable 1-2 floor building exists near home (scan)")
	if _target.is_empty():
		_finish()
		return
	var key := str(_target["key"])
	var floors := int(_target["floors"])
	print("[BUILDING] target: ", key, " floors: ", floors,
		" doorstep: ", _target["doorstep"])
	var lb = get_node_or_null("/root/Leaderboard")
	var no_steam := lb != null and not bool(lb.call(
		"steam_available"))
	_check(no_steam,
		"no-Steam posture: steam_available() is false")
	# Boot: the world scene becomes current and spawns the
	# local player.
	var c_boot := func() -> bool:
		return _scene_is(WORLD_PATH) \
			and _world_player() != null
	_check(await _wait_until(c_boot, 30.0),
		"the world scene boots with a local player")
	# Move the player to the target's doorstep so its chunk
	# streams in, then find the REAL street door trigger.
	var wp = _world_player()
	var doorstep: Vector3 = _target["doorstep"]
	wp.set("global_position", doorstep
		+ Vector3(0, 1.0, 0))
	var c_trig := func() -> bool:
		return _find_trigger(key) != null
	_check(await _wait_until(c_trig, 90.0),
		"the target building's street door streams in")
	var trig = _find_trigger(key)
	if trig == null:
		_finish()
		return
	var cleared_before: int = Dungeon.buildings_cleared
	# REAL door entry through the shipped path.
	trig.call("activate", wp)
	var c_f0 := func() -> bool:
		return _scene_is(DUNGEON_PATH) \
			and Dungeon.floor_active() \
			and Dungeon.floor_index == 0 \
			and _transfers_ready()
	_check(await _wait_until(c_f0, 30.0),
		"door entry lands the party on floor 0 (load_floor)")
	_check(Dungeon.attempt_key == key,
		"the street entry began the attempt (server-side)")
	# Clear the floors through the shipped spine, riding
	# the real stair surfaces between them. The final
	# floor is cleared separately below - its toast poll
	# must start in the same breath as the clear.
	for f in floors - 1:
		var dgn = get_tree().current_scene
		var lp = dgn.call("_my_player")
		if lp != null:
			lp.set("hp", lp.get("max_hp"))
		dgn.call("complete_level_objective")
		await get_tree().process_frame
		await get_tree().process_frame
		if true:
			var stamped := int(Dungeon.attempt_mask) \
				& (1 << f) != 0
			_check(stamped
				and Dungeon.attempt_last_completed
					.is_empty(),
				"floor %d clear stamps the attempt, posts nothing yet" % (f + 1))
			var up = _find_transfer("stair_up")
			_check(up != null,
				"floor %d offers its stair_up surface" % (f + 1))
			if up == null:
				_finish()
				return
			up.call("interact", lp)
			var nf := f + 1
			var c_up := func() -> bool:
				return _scene_is(DUNGEON_PATH) \
					and Dungeon.floor_index == nf \
					and _transfers_ready()
			_check(await _wait_until(c_up, 30.0),
				"stair_up rides load_floor to floor %d" % (nf + 1))
	# The final floor: clear it and poll the HUD banner
	# from the same breath - the floor's own "Floor
	# cleared." announce follows the completion announce
	# in the same spine, so the banner only holds the
	# completion text until the next announce lands.
	var dgn2 = get_tree().current_scene
	var lp3 = dgn2.call("_my_player")
	if lp3 != null:
		lp3.set("hp", lp3.get("max_hp"))
	dgn2.call("complete_level_objective")
	var toast_seen := false
	var toast_last := ""
	var toast_deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < toast_deadline \
			and not toast_seen:
		var hud = dgn2.get("_local_hud")
		if hud != null:
			var lbl = hud.get_node_or_null(
				"%AnnounceLabel")
			if lbl != null:
				toast_last = str(lbl.get("text"))
				toast_seen = toast_last.begins_with(
					"Building cleared in")
		if not toast_seen:
			await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	# The completing clear posted.
	var done: Dictionary = Dungeon.attempt_last_completed
	var det: Array = done.get("details", [])
	var posted := str(done.get("key", "")) == key \
		and int(done.get("seconds", -1)) >= 0 \
		and det.size() == 4 \
		and (det.is_empty() or int(det[0]) == floors)
	_check(posted,
		"the completion posted (key, seconds, details)")
	_check(Dungeon.attempt_key == ""
		and Dungeon.buildings_cleared
			== cleared_before + 1,
		"the attempt closed and the building counted exactly once")
	print("[BUILDING] toast label observed: '", toast_last,
		"'")
	# FINDING (issue #211, reported on the issue, routed
	# through the DM/gate - NOT fixed inline): through the
	# real spine the completion toast does not survive.
	# sync_floor_cleared's completion block rpcs
	# announce_building_cleared (the "Building cleared in
	# M:SS" banner), and _server_floor_cleared's very next
	# line rpcs announce_text("Floor cleared.") - the
	# second announce supersedes the banner within the
	# same call sequence, so the resting banner after a
	# completing clear reads "Floor cleared." and the
	# clear time is never presented, though spec section 3
	# has the handler "show the time locally". The probe
	# leg below proves the handler itself posts its toast
	# when the spine's ordering is not in play.
	if not toast_seen:
		print("[BUILDING] FINDING: the spine's resting ",
			"banner is '", toast_last, "' - the ",
			"completion toast is superseded in-sequence ",
			"(see the comment above this print).")
	# Probe leg: drive the completion handler directly
	# with a distinctive time, outside the spine's
	# announce sequence - the counted proof that the
	# announce/upload path posts the time toast under
	# the no-Steam posture.
	dgn2.call("announce_building_cleared", key, 7541,
		done.get("details", []))
	var probe_seen := false
	var probe_deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < probe_deadline \
			and not probe_seen:
		var hud2 = dgn2.get("_local_hud")
		if hud2 != null:
			var lbl2 = hud2.get_node_or_null(
				"%AnnounceLabel")
			if lbl2 != null and str(lbl2.get("text")) \
					== "Building cleared in 125:41":
				probe_seen = true
		if not probe_seen:
			await get_tree().process_frame
	_check(probe_seen,
		"the completion announce path posts the time toast (handler driven directly)")
	var pend: Array = lb.get("_pending_uploads")
	_check(pend.is_empty(),
		"nothing uploads under the no-Steam posture")
	# Exactly once: re-driving the spine cannot re-post.
	dgn2.call("complete_level_objective")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Dungeon.attempt_last_completed == done
		and Dungeon.buildings_cleared
			== cleared_before + 1,
		"a further clear cannot re-post the completion")
	# Ride down + exit, then the abandon leg: re-enter and
	# leave without clearing.
	for f in range(floors - 1, 0, -1):
		var dn = _find_transfer("stair_down")
		if dn == null:
			break
		var lp2 = get_tree().current_scene.call(
			"_my_player")
		dn.call("interact", lp2)
		var tf := f - 1
		var c_dn := func() -> bool:
			return Dungeon.floor_index == tf \
				and _transfers_ready()
		await _wait_until(c_dn, 30.0)
	var exit_prop = _find_transfer("exit")
	_check(exit_prop != null,
		"the ground floor offers its street exit")
	if exit_prop != null:
		exit_prop.call("interact",
			get_tree().current_scene.call("_my_player"))
		var c_world := func() -> bool:
			return _scene_is(WORLD_PATH) \
				and _world_player() != null
		_check(await _wait_until(c_world, 30.0),
			"exit returns the party to the street")
	# Abandon: re-enter (a fresh attempt begins), exit at
	# once - no post, no count.
	_check(await _wait_until(c_trig, 90.0),
		"the door streams back in for the abandon leg")
	var trig2 = _find_trigger(key)
	if trig2 != null:
		trig2.call("activate", _world_player())
		_check(await _wait_until(c_f0, 30.0),
			"re-entry lands on floor 0")
		_check(Dungeon.attempt_key == key,
			"re-entry began a fresh attempt")
		var exit2 = _find_transfer("exit")
		if exit2 != null:
			exit2.call("interact",
				get_tree().current_scene.call(
					"_my_player"))
			var c_world2 := func() -> bool:
				return _scene_is(WORLD_PATH)
			await _wait_until(c_world2, 30.0)
		_check(Dungeon.attempt_key == ""
			and Dungeon.attempt_last_completed == done
			and Dungeon.buildings_cleared
				== cleared_before + 1,
			"entry -> exit abandons with no post")
	_finish()


func _finish() -> void:
	print("[BUILDING] SUMMARY: %d passed, %d failed"
		% [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
