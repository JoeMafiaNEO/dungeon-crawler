class_name ItemPickup
extends Area3D
## Loot drop in the world. The server owns claims; every peer renders it.
## Players press E nearby to pick it up into their inventory.
## Unclaimed loot expires after LIFETIME seconds (server-authoritative).

const LIFETIME := 30.0
const WARN_AT := 5.0

var item: ItemData
var claimed := false
## Issue #142: how many units this drop holds. Mob loot is always 1;
## a disposed stack drops as one pickup carrying its full count.
var count := 1
## Danger-model loot multiplier at spawn (1.0 = base sell value). Preserved
## across late-joiner re-syncs so scaled drops keep their scaled price.
var value_mult := 1.0
## Key mode: this pickup is a puzzle key, not inventory loot. The dungeon
## counts it toward the key objective (finding them all clears the level).
## Set before _ready runs.
var is_key := false

var _t := 0.0
var _base_y := 0.0
var _request_sent := false
var _life := LIFETIME
var _warned := false
var _visual: Node3D
## Issue #142: a claim is a lock with an outcome still owed. The server
## records who claimed and when (its own _t clock); the claimer's grant
## reports a taken count back (report_claim). No report within
## CLAIM_TIMEOUT releases the lock — a disconnect mid-claim can never
## wedge the drop or eat it.
const CLAIM_TIMEOUT := 3.0
var _claimer_peer := 0
var _claim_since := -1.0


func setup(p_item: ItemData) -> void:
	item = p_item


func _ready() -> void:
	if is_key:
		$Label3D.text = "[E] Take Key"
	else:
		_refresh_label()
		$Label3D.modulate = ItemData.rarity_color(item.rarity)
	_build_visual()
	_base_y = position.y


## Issue #142: a multi-unit drop (a disposed stack) says how many it holds.
func _refresh_label() -> void:
	if item == null:
		return
	$Label3D.text = "[E] " + item.display_name + (" x%d" % count if count > 1 else "")


const KEY_MODEL := "res://assets/models/kaykit/dungeon/key.glb"


func _build_key_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Model"
	add_child(_visual)
	var packed := load(KEY_MODEL) as PackedScene
	if packed != null:
		var inst := packed.instantiate() as Node3D
		_visual.add_child(inst)
		var box := _measure(inst)
		var max_d := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if max_d > 0.01:
			inst.scale = Vector3.ONE * (0.9 / max_d)
		inst.position.y -= box.position.y * inst.scale.x
		$Sprite3D.visible = false
	else:
		$Sprite3D.texture = null
	# Gold beacon light so keys can be spotted in the dark.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.3)
	light.light_energy = 1.6
	light.omni_range = 7.0
	light.position.y = 1.0
	add_child(light)


## 3D model pickup visual, normalized to a readable size. Falls back to the
## 2D icon sprite, then to an emissive cube, so a pickup is never invisible.
## Rarer items get a colored glow light so they stand out at a distance.
func _build_visual() -> void:
	if is_key:
		_build_key_visual()
		return
	_visual = Node3D.new()
	_visual.name = "Model"
	add_child(_visual)
	var glow := OmniLight3D.new()
	glow.light_color = ItemData.rarity_color(item.rarity)
	glow.light_energy = 0.6 + float(item.rarity) * 0.5
	glow.omni_range = 4.0 + float(item.rarity) * 1.5
	glow.position.y = 1.0
	add_child(glow)
	# Rare+ loot gets a sky beam so it can be spotted across the map.
	if item.rarity >= ItemData.Rarity.RARE:
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.22
		cyl.height = 8.0
		var bmat := StandardMaterial3D.new()
		var rc := ItemData.rarity_color(item.rarity)
		bmat.albedo_color = Color(rc.r, rc.g, rc.b, 0.35)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.emission_enabled = true
		bmat.emission = rc
		bmat.emission_energy_multiplier = 1.5
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cyl.material = bmat
		beam.mesh = cyl
		beam.position.y = 4.0
		add_child(beam)
	var inst: Node3D = null
	if item.world_model != "" and ResourceLoader.exists(item.world_model):
		var packed := load(item.world_model) as PackedScene
		if packed != null:
			inst = packed.instantiate() as Node3D
	if inst == null and WeaponVisual.has_fallback(item.id):
		# Issue #113 Phase 2: procedural fallback model — flows through
		# the same measure/normalize/seat path as a real world model.
		inst = WeaponVisual.build_fallback(item.id)
	if inst != null:
		_visual.add_child(inst)
		var box := _measure(inst)
		var max_d := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if max_d > 0.01:
			inst.scale = Vector3.ONE * (0.8 / max_d)
		# Sit the model upright on its base.
		inst.position.y -= box.position.y * inst.scale.x
		$Sprite3D.visible = false
	elif item.icon != null:
		$Sprite3D.texture = item.icon
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.5, 0.5)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.85, 0.3)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.7, 0.2)
		m.emission_energy_multiplier = 1.5
		mi.material_override = m
		mi.position.y = 0.4
		_visual.add_child(mi)
		$Sprite3D.visible = false


static func _measure(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	# Issue: was using global_transform, which is unreliable during setup
	# (scene tree not updated yet). Use local transform chain instead.
	for c in _all_meshes(n):
		var mi := c as MeshInstance3D
		var local_box: AABB = mi.get_aabb()
		# Walk up the local transform chain to n.
		var xform := Transform3D.IDENTITY
		var cur := mi as Node3D
		while cur != null and cur != n:
			xform = cur.transform * xform
			cur = cur.get_parent() as Node3D
		var wa: AABB = xform * local_box
		if first:
			box = wa
			first = false
		else:
			box = box.merge(wa)
	return box


static func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


func _process(delta: float) -> void:
	_t += delta
	position.y = _base_y + sin(_t * 2.5) * 0.15
	if _visual != null:
		_visual.rotate_y(delta * 1.2)
	if _warned and _visual != null:
		_visual.visible = fmod(_t * 5.0, 1.0) < 0.6
	if multiplayer.is_server() and not claimed and not is_key:
		_life -= delta
		if _life <= WARN_AT and not _warned:
			_warned = true
			rpc("warn_expiry")
		if _life <= 0.0:
			rpc("despawn")
	# Issue #142: a claim whose outcome never reports (the claimer
	# disconnected mid-claim) releases at the full count — a peer who
	# left takes their inventory with them, so nothing can duplicate.
	if multiplayer.is_server() and claimed and _claim_since >= 0.0 \
			and _t - _claim_since > CLAIM_TIMEOUT:
		claimed = false
		_claimer_peer = 0
		_claim_since = -1.0


func is_available() -> bool:
	return not claimed and not _request_sent


func request_claim(claimer_peer: int) -> void:
	if not is_available():
		return
	# NOTE: only flag the request as sent. The authoritative `claimed` flag is
	# set by claim() on the server. Setting claimed here would break solo play,
	# where this instance IS the server instance and claim() would early-out.
	_request_sent = true
	# SteamMultiplayerPeer can't rpc_id its own peer ID: when this instance is
	# the server, call directly (same outcome — claim() is call_local).
	if multiplayer.is_server():
		claim(claimer_peer)
	else:
		rpc_id(NetworkManager.server_peer_id, "claim", claimer_peer)


@rpc("any_peer", "call_local")
func claim(claimer: int) -> void:
	if not multiplayer.is_server():
		return
	if claimed:
		return
	claimed = true
	var dungeon := get_tree().get_first_node_in_group("dungeon") as Dungeon
	if is_key:
		# Keys never enter an inventory — no outcome to await.
		rpc("despawn")
		if dungeon != null:
			dungeon.collect_key(claimer)
		return
	# Issue #142: the drop is NOT freed here. The grant's outcome is
	# decided on the claimer (only they can see their inventory), and
	# they report the taken count back — report_claim despawns on a
	# full take and releases the lock otherwise, so a full inventory
	# leaves the drop in the world instead of destroying it.
	_claimer_peer = claimer
	_claim_since = _t
	var player_node: Node = null
	if dungeon != null:
		player_node = dungeon.get_player_node(claimer)
	if player_node != null:
		player_node.rpc_id(claimer, "receive_item", item.id, item.sell_value,
			str(get_path()), count)
	else:
		# Nobody to grant to (the claimer vanished mid-claim): release.
		claimed = false
		_claimer_peer = 0
		_claim_since = -1.0


## Issue #142: the claimer's grant reports how many units actually
## landed. Full take -> the drop is consumed (despawn everywhere).
## Anything less (inventory full) -> the lock releases and the drop
## stays in the world at the remaining count, claimable by anyone.
@rpc("any_peer", "call_local")
func report_claim(taken: int, tag: int = 0) -> void:
	if not multiplayer.is_server():
		return
	if not claimed or _claim_since < 0.0:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != _claimer_peer:
		return
	var claimer := _claimer_peer
	var got := clampi(taken, 0, count)
	_claimer_peer = 0
	_claim_since = -1.0
	if got > 0:
		_credit_dock_mirrors(claimer, got)
	if got >= count:
		rpc("despawn")
	else:
		claimed = false
		rpc("sync_count", count - got)


## Issue #155 (i): dock goods run on server ledger mirrors (FarmPlot's
## seed ledger, DockEconomy's stock/cash) that the plant/cast/buy verbs
## read — the bag item alone is inert. A claimed world drop of one of
## these credits the SAME mirrors through the SAME grant functions the
## dock merchant uses, per unit actually taken (this report is the
## server's grant-outcome point — the farm harvest credits its stock
## ledger here too). A partial or failed take credits proportionally,
## never the drop's full count, and the guard above (one report per
## claim) keeps a re-claim of the remainder from double-crediting.
func _credit_dock_mirrors(peer: int, taken_units: int) -> void:
	if item == null:
		return
	match item.id:
		"seed_packet":
			FarmPlot.grant_seeds(peer, taken_units)
		"bait_lure":
			DockEconomy.grant_stock(peer, DockEconomy.BAIT_ITEM, taken_units)
		"farm_cash":
			DockEconomy.grant_cash(peer, taken_units)


## Issue #142: keep every peer's remaining-count (and label) in step.
@rpc("any_peer", "call_local")
func sync_count(new_count: int) -> void:
	count = maxi(new_count, 0)
	_refresh_label()


## Issue #142: called on the CLAIMER's own instance of this pickup when
## its grant resolves — their request is no longer in flight, so the
## pickup prompt may offer it again.
func resolve_my_claim() -> void:
	_request_sent = false


@rpc("any_peer", "call_local")
func despawn() -> void:
	queue_free()


@rpc("any_peer", "call_local")
func warn_expiry() -> void:
	# Expiry blinking is handled in _process via _warned.
	_warned = true
