class_name FishingSpot
extends Node3D
## E-interact fishing spot at a pier end (issue #102 Phase 1).
## One player per spot: the server owns the lock; clients claim/release via
## RPC. Phase 2 hooks the rod minigame into the claim path.

var spot_index: int = 0
var occupied_by: int = 0 ## peer id holding the spot; 0 = free


func _ready() -> void:
	add_to_group("fishing_spots")
	_build()


func prompt_text() -> String:
	var me := int(multiplayer.get_unique_id())
	if occupied_by == 0:
		return "Fish here"
	if occupied_by == me:
		return "Stop fishing"
	return "Spot in use"


func interact(player: Player) -> void:
	var me := int(multiplayer.get_unique_id())
	if occupied_by == 0:
		if multiplayer.is_server():
			claim_spot(me)
		else:
			rpc_id(NetworkManager.server_peer_id, "claim_spot", me)
	elif occupied_by == me:
		if multiplayer.is_server():
			release_spot(me)
		else:
			rpc_id(NetworkManager.server_peer_id, "release_spot", me)
	elif player.hud != null:
		player.hud.toast("Someone is already using this spot.")


## Server-authoritative claim: first valid claim wins, everyone syncs.
@rpc("any_peer", "call_local")
func claim_spot(claimer: int) -> void:
	if not multiplayer.is_server():
		return
	if occupied_by != 0:
		return
	occupied_by = claimer
	rpc("sync_occupant", occupied_by)


@rpc("any_peer", "call_local")
func release_spot(claimer: int) -> void:
	if not multiplayer.is_server():
		return
	if occupied_by != claimer:
		return
	occupied_by = 0
	rpc("sync_occupant", 0)


@rpc("any_peer", "call_local")
func sync_occupant(peer_id: int) -> void:
	occupied_by = peer_id
	_refresh_marker()


func _refresh_marker() -> void:
	var marker := get_node_or_null("Marker") as MeshInstance3D
	if marker != null:
		marker.material_override = _marker_mat(occupied_by != 0)


func _marker_mat(occupied: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if occupied:
		m.albedo_color = Color(0.85, 0.25, 0.2)
		m.emission_enabled = true
		m.emission = Color(0.85, 0.2, 0.15)
		m.emission_energy_multiplier = 1.5
	else:
		m.albedo_color = Color(0.3, 0.8, 0.4)
		m.emission_enabled = true
		m.emission = Color(0.25, 0.75, 0.35)
		m.emission_energy_multiplier = 1.2
	return m


func _build() -> void:
	# Wooden sign post marking the spot + a floating availability marker
	# (green = free, red = occupied).
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.30, 0.18)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.14, 1.4, 0.14)
	post.mesh = pm
	post.position = Vector3(0, 0.7, 0)
	post.material_override = wood
	add_child(post)
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	marker.mesh = sm
	marker.position = Vector3(0, 1.6, 0)
	marker.material_override = _marker_mat(false)
	add_child(marker)
