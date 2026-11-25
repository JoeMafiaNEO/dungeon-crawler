extends Node
## Issue #266 P1: the Standard map bake (dev only, never runs at runtime).
##
## Builds data/maps/standard.json — the standalone mode's default map and
## the editor's "duplicate and edit" starting point. The terrain is
## AUTHORED, not transcribed: the production warlord level is FLAT
## (theme_warlord leaves use_heightmap_terrain off), so there is no
## dungeon terrain to bake. The authored terrain is ring12's layout
## (scripts/terrain/warlords_maps.gd _gen_ring12, values reproduced
## here with the same constants — the test scene itself is never
## imported): 220x220, centre +3/+6, 12 expansion +3 plateaus, 12
## contested +6 peaks, ponds on the peak azimuths, 12 ring starts.
## The resource nodes ARE baked from the dungeon scatter rules
## (WarlordSetup.scatter_positions, cycle 0, fixed seed 5505) — the
## dungeon scatter is unseeded randf() at runtime, so the bake freezes
## one seeded replay.
##
## Run: godot --headless --path . res://tools/bake_standard_map.tscn
## Output is atomic (.tmp then rename) and deterministic: run twice
## and the file is byte-identical (the suite pins this).

const OUT_PATH := "res://data/maps/standard.json"
const STANDARD_SEED := 5505
const STANDARD_SIZE := 220
const STANDARD_NAME := "standard"


func _ready() -> void:
	await get_tree().process_frame
	var map_data := _build_standard_map()
	var text := WarlordMap.canonical_json(map_data)
	DirAccess.make_dir_recursive_absolute("res://data/maps")
	var tmp := OUT_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[BAKE] cannot write %s" % tmp)
		get_tree().quit()
		return
	f.store_string(text)
	f.close()
	if DirAccess.rename_absolute(tmp, OUT_PATH) != OK:
		push_error("[BAKE] rename %s -> %s failed" % [tmp, OUT_PATH])
		get_tree().quit()
		return
	var reread := WarlordMap.parse_map(FileAccess.get_file_as_string(OUT_PATH))
	if not bool(reread.get("ok", false)):
		push_error("[BAKE] baked map unparsable: %s" % str(reread.get("error", "?")))
		get_tree().quit()
		return
	var err := WarlordMap.validate(reread["map"])
	if err != "":
		push_error("[BAKE] baked map invalid: %s" % err)
		get_tree().quit()
		return
	var m: Dictionary = reread["map"]
	print("[BAKE] standard map written: %s (%d bytes, hash %s, %d zones, %d ramps, %d ponds, %d starts, %d nodes)"
		% [OUT_PATH, text.length(), WarlordMap.map_hash(m),
			(m.get("zones", []) as Array).size(),
			(m.get("ramps", []) as Array).size(),
			(m.get("ponds", []) as Array).size(),
			(m.get("starts", []) as Array).size(),
			(m.get("nodes", []) as Array).size()])
	get_tree().quit()


## The Standard map dict. Zones/ramps/ponds reproduce _gen_ring12's
## VALUES (warlords_maps.gd:313-396) — including the phases, which the
## §5 format does not carry but the loader passes through when present
## (defaulting to 0.0 for maps that omit them).
func _build_standard_map() -> Dictionary:
	var zones: Array = []
	var ramps: Array = []
	var ponds: Array = []
	var starts: Array = []
	zones.append({"center": [0.0, 0.0], "radius": 24.0, "height": 3,
		"phase1": 0.7, "phase2": 1.3})
	zones.append({"center": [0.0, 0.0], "radius": 15.0, "height": 6,
		"phase1": 2.1, "phase2": 0.4})
	for i in 12:
		var th := TAU * float(i) / 12.0
		var u := Vector2(cos(th), sin(th))
		var s := u * 76.0
		var e := u * 90.0
		zones.append({"center": [e.x, e.y], "radius": 10.0, "height": 3,
			"phase1": fmod(1.13 * float(i), TAU),
			"phase2": fmod(2.71 * float(i), TAU)})
		ramps.append({"base": [u.x * 74.0, u.y * 74.0], "dir": [u.x, u.y],
			"length": 16.0, "width": 9.0, "h0": 0, "h1": 3})
		var pk_ang := th + TAU / 24.0
		var pk := Vector2(cos(pk_ang), sin(pk_ang)) * 44.0
		zones.append({"center": [pk.x, pk.y], "radius": 9.0, "height": 6,
			"phase1": fmod(0.71 * float(i) + 0.5, TAU),
			"phase2": fmod(1.97 * float(i), TAU)})
		for nb in [i, (i + 1) % 12]:
			var nth := TAU * float(nb) / 12.0
			var ns := Vector2(cos(nth), sin(nth)) * 76.0
			var d := (ns - pk).normalized()
			var rbase := pk + d * 20.0
			ramps.append({"base": [rbase.x, rbase.y], "dir": [-d.x, -d.y],
				"length": 19.0, "width": 6.0, "h0": 0, "h1": 6})
		var pa := th + TAU / 24.0
		ponds.append({"center": [cos(pa) * 64.0, sin(pa) * 64.0], "radius": 5.5})
		starts.append({"faction": i, "pos": [s.x, s.y]})
	for k in 4:
		var th2 := TAU * float(k) / 4.0
		var u2 := Vector2(cos(th2), sin(th2))
		ramps.append({"base": [u2.x * 38.0, u2.y * 38.0],
			"dir": [-u2.x, -u2.y], "length": 28.0, "width": 8.0,
			"h0": 0, "h1": 6})
	var partial := {
		"format_version": WarlordMap.FORMAT_VERSION,
		"name": STANDARD_NAME,
		"display_name": "Standard",
		"size_m": STANDARD_SIZE,
		"seed": STANDARD_SEED,
		"zones": zones, "ramps": ramps, "ponds": ponds, "starts": starts,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = STANDARD_SEED
	var water := func(pos: Vector3) -> bool:
		return WarlordMap.is_pond_water(partial, pos)
	var amounts := RTSTuning.get_dict("map", "node_amounts",
		{"wood": 1000, "food": 800, "gold": 800, "stone": 800})
	var nodes: Array = []
	for entry in WarlordSetup.scatter_positions(
			WarlordSetup.map_scale_for(12), 12, 0, rng, water):
		var p: Vector3 = entry["pos"]
		nodes.append({"type": str(entry["type"]), "pos": [p.x, p.z],
			"amount": int(amounts.get(str(entry["type"]), 800))})
	partial["nodes"] = nodes
	return partial
