class_name FarmPlot
extends Node3D
## E-interact farm soil plot (issue #102 Phase 1).
## One player per plot: the server owns the lock; clients claim/release via
## RPC. The plot state machine (untilled -> tilled -> planted -> growing ->
## harvestable) arrives in Phase 3; until then the node is the soil visual
## plus the lock.
##
## Trust model (Phase 2 hardening): claim/release take no peer id — the
## server attributes every call via multiplayer.get_remote_sender_id()
## (P2P peer ids; server = 1, never the 64-bit Steam id).

var plot_index: int = 0
var occupied_by: int = 0 ## peer id holding the plot; 0 = free
var plot_state: String = "untilled" ## Phase 3 drives this.


func _ready() -> void:
	add_to_group("farm_plots")
	_build()


func prompt_text() -> String:
	var me := int(multiplayer.get_unique_id())
	if occupied_by == 0:
		return "Claim farm plot"
	if occupied_by == me:
		return "Release farm plot"
	return "Plot in use"


func interact(player: Player) -> void:
	var me := int(multiplayer.get_unique_id())
	if occupied_by == 0:
		if multiplayer.is_server():
			claim_plot()
		else:
			rpc_id(NetworkManager.server_peer_id, "claim_plot")
		if player.hud != null:
			player.hud.toast("Farm plot claimed")
	elif occupied_by == me:
		if multiplayer.is_server():
			release_plot()
		else:
			rpc_id(NetworkManager.server_peer_id, "release_plot")
	elif player.hud != null:
		player.hud.toast("Someone is already farming this plot.")


## Server-authoritative claim: first valid claim wins, everyone syncs.
## Takes no peer id — the caller is attributed via get_remote_sender_id().
@rpc("any_peer", "call_local")
func claim_plot() -> void:
	if not multiplayer.is_server():
		return
	if occupied_by != 0:
		return
	occupied_by = _sender_peer()
	rpc("sync_occupant", occupied_by)


@rpc("any_peer", "call_local")
func release_plot() -> void:
	if not multiplayer.is_server():
		return
	if occupied_by != _sender_peer():
		return
	occupied_by = 0
	rpc("sync_occupant", 0)


## Server-side forced release (peer disconnect). Never called by clients.
func force_release_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if occupied_by != peer_id:
		return
	occupied_by = 0
	rpc("sync_occupant", 0)


## P2P peer id of the RPC sender; local (server) calls fall back to the
## server's own id. Never a 64-bit Steam id (see AGENTS.md).
func _sender_peer() -> int:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender


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
	# Tilled soil square with furrow ridges, corner posts, and a small claim
	# sign. Phase 3 re-tints/re-models this per growth state.
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.25, 0.16, 0.10)
	var ridge_m := StandardMaterial3D.new()
	ridge_m.albedo_color = Color(0.32, 0.21, 0.13)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.4, 0.12, 3.4)
	base.mesh = bm
	base.position = Vector3(0, 0.06, 0)
	base.material_override = soil
	add_child(base)
	for k in 3:
		var ridge := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(3.2, 0.10, 0.28)
		ridge.mesh = rm
		ridge.position = Vector3(0, 0.14, -1.1 + float(k) * 1.1)
		ridge.material_override = ridge_m
		add_child(ridge)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.30, 0.18)
	for sx in [-1.6, 1.6]:
		for sz in [-1.6, 1.6]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.12, 0.7, 0.12)
			post.mesh = pm
			post.position = Vector3(sx, 0.35, sz)
			post.material_override = wood
			add_child(post)
	# Claim sign + floating availability marker (green = free, red = claimed).
	var sign := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.7, 0.5, 0.08)
	sign.mesh = sm
	sign.position = Vector3(0, 1.1, -1.6)
	sign.material_override = wood
	add_child(sign)
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	var mm := SphereMesh.new()
	mm.radius = 0.18
	mm.height = 0.36
	marker.mesh = mm
	marker.position = Vector3(0, 1.75, -1.6)
	marker.material_override = _marker_mat(false)
	add_child(marker)
