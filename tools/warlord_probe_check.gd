extends Node
## Issue #138 Phase 3 validation (dev only): the warlord
## bit-identity probe. Boots the production warlord dungeon at a
## seed through the REAL scene flow and writes a digest of
## everything the level build deterministically hands the RTS
## layer:
##
##   * the layout fingerprint (grid, props, spawns, zones data)
##   * the full Arena census (every static node: path, class,
##     local position — the baked scene must present the same set;
##     auto-name counters are normalized away, since @Class@N
##     numbering legitimately differs between a live build and a
##     shipped-scene load while the name SHAPE must not)
##   * the RTS spawn state, captured on the first tick the RTS
##     setup is complete: unit roster (name, faction, type),
##     buildings (name, faction, type, exact position — town
##     halls and docks are static), the resource-node COUNT, and
##     the registered faction ids.
##
## Deliberately NOT captured: live unit positions and resource
## node positions. Both are unseeded by design in production —
## resource scatter uses randf(), the AI faction's class is a
## randi() pick, and AI villagers receive gather orders the
## moment they spawn — so two identical procgen boots at the
## same seed already differ there. A gate that included them
## could never pass on any pair of boots, baked or not.
##
## Run it BEFORE the warlord bake exists (procgen is the only
## path) and AFTER (the baked path engages at the pin): the two
## digest files must be BYTE-IDENTICAL apart from the
## baked_hash line.
##
##   godot --headless --path . res://tools/warlord_probe_check.tscn -- --seed 1 --out ~/probe.txt
##
## The tscn root only spawns the real driver as a root sibling, so
## the driver survives the scene change into the dungeon.

var _is_driver := false
var _seed := 1
var _level := 1
var _out := ""
var _t := 0.0


func _ready() -> void:
	if not _is_driver:
		var driver = load("res://tools/warlord_probe_check.gd").new()
		driver.set("_is_driver", true)
		driver.name = "WarlordProbeDriver"
		get_tree().root.call_deferred("add_child", driver)
		return
	_parse_args()
	NetworkManager.selected_class_id = "warrior"
	Dungeon.next_theme_id = "warlord"
	Dungeon.next_seed = _seed
	Dungeon.next_level_number = _level
	Dungeon.saved_player_state = {}
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon.tscn")


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		var key := a
		var val := ""
		var eq := a.find("=")
		if eq > 0:
			key = a.substr(0, eq)
			val = a.substr(eq + 1)
		elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
			val = args[i + 1]
			i += 1
		if key == "--seed":
			_seed = int(val)
		elif key == "--level":
			_level = int(val)
		elif key == "--out":
			_out = val
		i += 1


func _process(delta: float) -> void:
	if not _is_driver:
		return
	_t += delta
	if _t > 90.0:
		_finish("PROBE TIMEOUT", 1)
		return
	var scene = get_tree().current_scene
	if scene == null or not scene.scene_file_path.ends_with("dungeon.tscn"):
		return
	var dgn = get_tree().get_first_node_in_group("dungeon")
	if dgn == null:
		return
	# Capture on the first tick the deferred RTS setup is complete:
	# manager exists, both factions registered, town halls + docks
	# spawned. The driver sits before the dungeon in tree order, so
	# this tick still precedes any AI-driven building or training.
	var mgr = dgn.get("_rts_manager")
	if mgr == null:
		return
	var factions: Dictionary = mgr.get("factions")
	if factions.size() < 2:
		return
	if get_tree().get_nodes_in_group("rts_buildings").size() < 4:
		return
	var lines: Array[String] = []
	lines.append("baked_hash=" + str(dgn.get("_baked_hash")))
	var layout = dgn.get("_layout")
	lines.append("fingerprint=" + (str(layout.fingerprint()) if layout != null else "<none>"))
	var census: Array[String] = []
	var arena = dgn.get_node_or_null("Arena")
	if arena != null:
		_census(arena, census)
	census.sort()
	lines.append("arena_count=%d" % census.size())
	lines.append_array(census)
	var units: Array[String] = []
	for n in get_tree().get_nodes_in_group("rts_units"):
		units.append("rts_unit|%s|%d|%s" % [n.name,
			int(n.get("faction")), str(n.get("unit_type"))])
	units.sort()
	lines.append_array(units)
	var buildings: Array[String] = []
	for n in get_tree().get_nodes_in_group("rts_buildings"):
		var n3 := n as Node3D
		if n3 != null:
			buildings.append("rts_building|%s|%d|%s|%.3f,%.3f,%.3f" % [n.name,
				int(n.get("faction")), str(n.get("building_type")),
				n3.position.x, n3.position.y, n3.position.z])
	buildings.sort()
	lines.append_array(buildings)
	lines.append("rts_resources_count=%d" % get_tree().get_nodes_in_group("rts_resources").size())
	var fids: Array = factions.keys()
	fids.sort()
	lines.append("factions=" + ",".join(fids.map(func(x): return str(x))))
	_finish("\n".join(lines) + "\n", 0)


func _census(n: Node, out: Array[String]) -> void:
	for c in n.get_children():
		var path_str: String = str(c.get_path())
		var rel_raw: String = path_str.split("Arena/", false)[-1] if path_str.contains("Arena/") else str(c.name)
		var segs: PackedStringArray = rel_raw.split("/")
		for si in segs.size():
			if segs[si].begins_with("@"):
				var at2 := segs[si].find("@", 1)
				if at2 > 0:
					segs[si] = segs[si].substr(0, at2) + "@#"
		var rel: String = "/".join(segs)
		var pos := ""
		if c is Node3D:
			var c3 := c as Node3D
			pos = "|%.3f,%.3f,%.3f" % [c3.position.x, c3.position.y, c3.position.z]
		out.append("arena|%s|%s%s" % [rel, c.get_class(), pos])
		_census(c, out)


func _finish(text: String, code: int) -> void:
	print("[WPROBE] done code=%d bytes=%d" % [code, text.length()])
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
	set_process(false)
	get_tree().quit(code)
