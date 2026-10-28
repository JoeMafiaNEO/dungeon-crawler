class_name CabButton
extends Node3D
## Elevator cab button inside the annex hall's walk-in cab
## (Jesse 2026-10-27: button departs). E-interact (vendor
## pattern): any living player presses it; the station's
## request_cab_depart RPC validates server-side — the press
## only fires once every living player is inside the cab.


## Set by the station before add_child: false at Warlord's,
## where the button does nothing (Jesse 2026-10-28) — it
## stays out of the interact scan and shows no prompt.
var depart_armed := true


func _ready() -> void:
	if depart_armed:
		add_to_group("cab_button")
	_build()


func _station() -> Node:
	# The button is built inside its own hub's station (bank ->
	# cab -> button): walk up to that station first, so the
	# prompt names this hub's destination even while another
	# hub's station exists (tests, layered scenes).
	var n: Node = get_parent()
	while n != null:
		if n.is_in_group("station"):
			return n
		n = n.get_parent()
	return get_tree().get_first_node_in_group("station")


func prompt_text() -> String:
	if not depart_armed:
		return ""
	# Issue #201 (fork 2) carries over from the lever this
	# button replaces in Act 1 hubs: the destination is named
	# only here, at the moment of use.
	var station := _station()
	if station != null and station.has_method("depart_prompt_text"):
		return str(station.call("depart_prompt_text"))
	return "Press the button"


func interact(_player: Player) -> void:
	var station := _station()
	if station != null and station.has_method("request_cab_depart"):
		station.rpc("request_cab_depart")


func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.55
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _build() -> void:
	var plate := _mat(Color(0.30, 0.29, 0.33))
	var brass := _mat(Color(0.72, 0.55, 0.25), Color(0.72, 0.55, 0.25), 0.4)
	var amber := _mat(Color(1.0, 0.62, 0.20), Color(1.0, 0.55, 0.15), 1.6)
	# Wall plate on the cab's right wall, face toward -X (into
	# the cab): a brass-rimmed plate with one amber button.
	_box(Vector3(0.05, 0.42, 0.30), Vector3(-0.03, 0, 0), brass)
	_box(Vector3(0.05, 0.34, 0.22), Vector3(-0.06, 0, 0), plate)
	_box(Vector3(0.06, 0.16, 0.16), Vector3(-0.10, 0, 0), amber)
