class_name FarmPlot
extends Node3D
## E-interact farm soil plot (issue #102).
## Phase 1: one-player-per-plot server-authoritative locking.
## Phase 2: claim hardening (P2P peer ids via get_remote_sender_id) +
## disconnect auto-release.
## Phase 3: server-authoritative farming loop. States:
## untilled -> tilled -> planted -> growing -> harvestable -> (harvest)
## -> untilled. E drives the machine: E on untilled tills (free); E on
## tilled with seeds plants (consumes 1 seed); E on tilled without seeds
## prompts "out of seeds"; E on growing prompts "still growing (N waves
## left)"; E on harvestable harvests into the inventory (server-side
## rarity roll) and resets to untilled, releasing the claim. Growth ticks
## per wave cleared (server-side hook), never real time — no watering
## minigame: farming is the passive counterpart to fishing's active game.
##
## Trust model: the server owns the lock, the states, the seed ledger,
## growth ticks, and harvest rolls. Claim/interact RPCs take no peer id —
## the server attributes every call via multiplayer.get_remote_sender_id()
## (P2P peer ids; server = 1, never the 64-bit Steam id). Light anti-cheat,
## co-op game.

const GROWTH_TICKS := 3 ## Waves for a crop to mature. Jesse's numbers call (spec: 2-3).
const HARVEST_COMMON_W := 0.70 ## Harvest rarity weights. Jesse's numbers call.
const HARVEST_RARE_W := 0.25
const HARVEST_LEGENDARY_W := 0.05
const STARTER_SEED_COUNT := 3 ## Free seeds per misty-docks level entry. Jesse's call.

const SEED_ITEM := "seed_packet"
## Issue #155 (ii): seed tiers. REGULAR is the default everywhere;
## the QUALITY (fine) tier is a separate ledger bucket and a
## separate bag item, and it is the only tier whose harvest
## consults the rarity roll. The server spends EXACTLY the
## requested bucket — no substitution (Jesse's ruling,
## 2026-10-16; better-first auto-spend was rejected).
const TIER_REGULAR := 0
const TIER_FINE := 1
const SEED_ITEM_FINE := "seed_packet_fine"
## Jesse's planting UX: holding E this long at a tilled plot
## plants the QUALITY tier; a shorter tap plants the tap tier.
const PLANT_HOLD_SECONDS := 0.35
const CROP_COMMON := "crop_sunroot"
const CROP_RARE := "crop_moonmelon"
const CROP_LEGENDARY := "crop_goldengourd"
const DOCK_TROPHY_GOLDEN := "golden_crop"

## TEST SEAMS (never set in production): debug_harvest_roll >= 0 forces the
## harvest rarity roll; test_player overrides _player_for_peer().
static var debug_harvest_roll: float = -1.0
## Server-side seed ledger: peer id -> {tier -> plantable seed
## count} (issue #155 (ii): one bucket per tier). Mirrors the
## seed_packet stacks the server granted. Cleared per peer on
## disconnect; Phase 4 vendor seed purchases must update this
## ledger too. Writers replace the per-peer dict (never mutate
## it in place) so snapshot/restore in tests stays exact.
static var _seed_ledger: Dictionary = {}

var test_player: Player = null

## Issue #142: a harvest awaiting its grant outcome. While set, the
## plot does NOT flip and NO stock is recorded — the crop stays
## standing until the harvester's inventory answers (report_claim);
## an unanswered outcome leaves it standing too.
var _harvest_pending: Dictionary = {}

var plot_index: int = 0
var occupied_by: int = 0 ## peer id holding the plot; 0 = free
var plot_state: String = "untilled" ## Phase 3 state machine state.
var growth_ticks: int = 0 ## wave ticks since planting.
var planted_tier: int = TIER_REGULAR ## Issue #155 (ii): the tier growing on this plot; replicated via sync_plot.


## Seed ledger (server-side only). Grant is additive per level entry so
## unspent seeds from an earlier misty-docks visit are never wiped.
## Starter seeds are REGULAR only (issue #155 (ii)).
static func grant_starter_seeds(peer: int) -> void:
	grant_seeds(peer, STARTER_SEED_COUNT)


## Issue #102 Phase 4: vendor seed purchases add to the ledger (the Phase 3
## flagged seam). Additive like the starter grant. Issue #155 (ii): the
## tier selects the bucket; existing callers default to REGULAR.
static func grant_seeds(peer: int, n: int, tier: int = TIER_REGULAR) -> void:
	var tiers: Dictionary = (_seed_ledger.get(peer, {}) as Dictionary).duplicate()
	tiers[tier] = int(tiers.get(tier, 0)) + n
	_seed_ledger[peer] = tiers


## Issue #102 Phase 4: death wipes the inventory mirror, so the ledger must
## go too (else phantom seeds after respawn). Called by the dungeon's
## notify_player_died (server).
static func clear_ledger(peer: int) -> void:
	_seed_ledger.erase(peer)


static func seed_count(peer: int, tier: int = TIER_REGULAR) -> int:
	var tiers: Dictionary = _seed_ledger.get(peer, {})
	return int(tiers.get(tier, 0))


## Issue #160: derive-at-restore SETS the seed ledger from the bag
## (the durable truth) — assignment, never accumulation. Per tier
## (issue #155 (ii)): setting one bucket never disturbs the other.
static func set_seed_count(peer: int, n: int, tier: int = TIER_REGULAR) -> void:
	var tiers: Dictionary = (_seed_ledger.get(peer, {}) as Dictionary).duplicate()
	tiers[tier] = n
	_seed_ledger[peer] = tiers


## Spend exactly one seed from the REQUESTED tier's bucket —
## never a substitution from the other tier (Jesse's ruling).
static func _spend_seed(peer: int, tier: int = TIER_REGULAR) -> bool:
	var left := seed_count(peer, tier)
	if left <= 0:
		return false
	var tiers: Dictionary = (_seed_ledger.get(peer, {}) as Dictionary).duplicate()
	tiers[tier] = left - 1
	_seed_ledger[peer] = tiers
	return true


func _ready() -> void:
	add_to_group("farm_plots")
	_build()


func prompt_text() -> String:
	var me := int(multiplayer.get_unique_id())
	if occupied_by == 0:
		return "Till soil ({interact})"
	if occupied_by != me:
		return "Plot in use"
	match plot_state:
		"tilled":
			# Issue #155 (ii): Jesse's planting prompts, keyed on
			# what the local player's bag actually holds (the bag
			# mirrors the server ledger). Both tiers held -> the
			# tap/hold pair; only quality held -> the tap plants
			# quality.
			var reg := _local_bag_count(SEED_ITEM)
			var fine := _local_bag_count(SEED_ITEM_FINE)
			if reg > 0 and fine > 0:
				return "E — Plant Seed · Hold E — Plant Quality Seed"
			if fine > 0:
				return "E — Plant Quality Seed"
			return "Plant seeds ({interact})"
		"planted", "growing":
			return "Growing (%d waves left)" % _waves_left()
		"harvestable":
			return "Harvest! ({interact})"
	return "Till soil ({interact})"


## The interact entry. Issue #155 (ii): the tier rides the
## request (default REGULAR — every pre-tier caller is regular);
## the player's tap/hold plant press passes its resolved tier.
func interact(player: Player, tier: int = TIER_REGULAR) -> void:
	var me := int(multiplayer.get_unique_id())
	if occupied_by != 0 and occupied_by != me:
		if player.hud != null:
			player.hud.toast("Someone is already farming this plot.")
		return
	if multiplayer.is_server():
		plot_action(tier)
	else:
		rpc_id(NetworkManager.server_peer_id, "plot_action", tier)


## The E flow, server-side: free plot -> claim + act; claimed plot -> act.
## Claim and the state action are one E (mirrors fishing's one-E claim+cast).
@rpc("any_peer", "call_local")
func plot_action(tier: int = TIER_REGULAR) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender_peer()
	if occupied_by == 0:
		_claim(peer)
		if occupied_by != peer:
			return
	elif occupied_by != peer:
		return
	match plot_state:
		"untilled":
			_till(peer)
		"tilled":
			# Issue #155 (ii): spend EXACTLY the requested tier's
			# bucket. An empty requested bucket refuses — the
			# other tier is never substituted.
			if _spend_seed(peer, tier):
				_plant(peer, tier)
			elif tier == TIER_FINE:
				rpc_id(peer, "on_plot_toast", "Out of quality seeds.")
			else:
				rpc_id(peer, "on_plot_toast", "Out of seeds.")
		"planted", "growing":
			# Issue #102 Phase 4: fertilizer (same E, no separate UI — the
			# flagged interaction choice). Holding fertilizer consumes one
			# and advances exactly one growth tick immediately (may mature
			# the crop); without it, the existing "still growing" prompt.
			if DockEconomy.spend_stock(peer, DockEconomy.FERTILIZER_ITEM):
				var fplayer := _player_for_peer(peer)
				if fplayer != null:
					# Issue #160: the merchant's self-guard — for the
					# server's own player the consume executes locally
					# (rpc_id to own peer id is undeliverable on Steam).
					if peer == int(multiplayer.get_unique_id()):
						fplayer.consume_dock_good(DockEconomy.FERTILIZER_ITEM)
					else:
						fplayer.rpc_id(peer, "consume_dock_good", DockEconomy.FERTILIZER_ITEM)
				growth_ticks += 1
				plot_state = "harvestable" if growth_ticks >= GROWTH_TICKS else "growing"
				_sync_plot()
				if plot_state == "harvestable":
					rpc_id(peer, "on_plot_toast", "Fertilized — ready to harvest!")
				else:
					rpc_id(peer, "on_plot_toast", "Fertilized — %d waves left." % _waves_left())
			else:
				rpc_id(peer, "on_plot_toast", "Still growing (%d waves left)." % _waves_left())
		"harvestable":
			_harvest(peer)


## Server-side wave hook: each cleared wave advances growing plots one
## tick. Called by the dungeon's _wave_cleared (host only). Never called
## by clients; plot nodes exist on every peer, state arrives via sync.
func on_wave_cleared() -> void:
	if not multiplayer.is_server():
		return
	if plot_state != "planted" and plot_state != "growing":
		return
	growth_ticks += 1
	plot_state = "harvestable" if growth_ticks >= GROWTH_TICKS else "growing"
	_sync_plot()


func _waves_left() -> int:
	return maxi(0, GROWTH_TICKS - growth_ticks)


func _till(peer: int) -> void:
	plot_state = "tilled"
	growth_ticks = 0
	_sync_plot()
	rpc_id(peer, "on_plot_toast", "Soil tilled — E to plant seeds.")


func _plant(peer: int, tier: int = TIER_REGULAR) -> void:
	# Tell the planter's client to drop one packet OF THE SPENT
	# TIER from its stack (inventory is per-peer authoritative;
	# the ledger already decremented that tier's bucket).
	var item_id := SEED_ITEM_FINE if tier == TIER_FINE else SEED_ITEM
	var player := _player_for_peer(peer)
	if player != null:
		if peer == int(multiplayer.get_unique_id()):
			player.consume_seed_item(item_id)
		else:
			player.rpc_id(peer, "consume_seed_item", item_id)
	planted_tier = tier
	plot_state = "planted"
	growth_ticks = 0
	_sync_plot()
	rpc_id(peer, "on_plot_toast", "Planted — harvest in %d waves." % GROWTH_TICKS)


func _harvest(peer: int) -> void:
	if not _harvest_pending.is_empty():
		return # an earlier harvest on this plot is still unanswered
	var item_id := _roll_harvest_item()
	var player := _player_for_peer(peer)
	if player == null:
		return
	# Issue #142: the grant reports its outcome back (receive_item's
	# report leg); the plot flips and the stock ledger records ONLY
	# on success (report_claim). A failed grant leaves the crop
	# standing and writes no record — recording a crop that never
	# entered an inventory would corrupt sell validation, and a
	# vanished crop is exactly the silent loss this issue kills.
	_harvest_pending = {"peer": peer, "item_id": item_id,
		"since": Time.get_ticks_msec() / 1000.0}
	if peer == int(multiplayer.get_unique_id()):
		player.receive_item(item_id, -1, str(get_path()), 1, peer)
	else:
		player.rpc_id(peer, "receive_item", item_id, -1, str(get_path()), 1, peer)


## Issue #142: the harvest grant's outcome (called by the
## harvester's own receive_item via the report leg).
@rpc("any_peer", "call_local")
func report_claim(taken: int, tag: int = 0) -> void:
	if not multiplayer.is_server() or _harvest_pending.is_empty():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != int(_harvest_pending.get("peer", -1)):
		return
	var item_id := str(_harvest_pending.get("item_id", ""))
	var peer := int(_harvest_pending["peer"])
	_harvest_pending = {}
	if taken < 1:
		rpc_id(peer, "on_plot_toast", "Inventory full — your crop is still standing.")
		return
	# Phase 5 validation fix: the harvest is a server grant — record it
	# in the DockEconomy stock ledger or the vendor's sell validation
	# (spend_stock) rejects the very crop the server just gave.
	DockEconomy.grant_stock(peer, item_id)
	if item_id == CROP_LEGENDARY:
		# Each peer records the trophy in their own profile (Collection
		# tab), paralleling dungeon.record_apex_kill.
		rpc_id(peer, "record_dock_trophy", DOCK_TROPHY_GOLDEN)
	plot_state = "untilled"
	growth_ticks = 0
	planted_tier = TIER_REGULAR
	occupied_by = 0
	rpc("sync_occupant", 0)
	_sync_plot()


## Issue #142: an unanswered harvest outcome leaves the crop
## standing — nothing flipped, nothing recorded.
func _process(_delta: float) -> void:
	if not multiplayer.is_server() or _harvest_pending.is_empty():
		return
	if Time.get_ticks_msec() / 1000.0 - float(_harvest_pending.get("since", 0.0)) > 3.0:
		_harvest_pending = {}


## Harvest rarity: weighted roll, server-side.
## (Numbers are defaults for Jesse to tune; flagged in the report.)
## Issue #155 (ii): a REGULAR plot never consults the roll — it
## harvests Sunroot UNCONDITIONALLY, and debug_harvest_roll has
## NO effect on it BY DESIGN. The roll is the QUALITY tier's.
func _roll_harvest_item() -> String:
	if planted_tier == TIER_REGULAR:
		return CROP_COMMON
	var roll := debug_harvest_roll if debug_harvest_roll >= 0.0 else randf()
	if roll < HARVEST_LEGENDARY_W:
		return CROP_LEGENDARY
	if roll < HARVEST_LEGENDARY_W + HARVEST_RARE_W:
		return CROP_RARE
	return CROP_COMMON


## Server-authoritative claim: first valid claim wins, everyone syncs.
## Takes no peer id — the caller is attributed via get_remote_sender_id().
@rpc("any_peer", "call_local")
func claim_plot() -> void:
	if not multiplayer.is_server():
		return
	_claim(_sender_peer())


@rpc("any_peer", "call_local")
func release_plot() -> void:
	if not multiplayer.is_server():
		return
	if occupied_by != _sender_peer():
		return
	occupied_by = 0
	rpc("sync_occupant", 0)


## Server-side forced release (peer disconnect). Never called by clients.
## Abandoned crops keep their growth state — a new claimer can finish them.
func force_release_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_seed_ledger.erase(peer_id)
	if occupied_by != peer_id:
		return
	occupied_by = 0
	rpc("sync_occupant", 0)


@rpc("any_peer", "call_local")
func sync_occupant(peer_id: int) -> void:
	occupied_by = peer_id
	_refresh_marker()


## State broadcast, server -> everyone (mirrors sync_occupant; self-heals).
## Issue #155 (ii): the planted tier rides the same broadcast —
## a replica knows which tier is growing.
@rpc("any_peer", "call_local")
func sync_plot(state: String, ticks: int, tier: int = TIER_REGULAR) -> void:
	plot_state = state
	growth_ticks = ticks
	planted_tier = tier
	_refresh_visual()


func _sync_plot() -> void:
	rpc("sync_plot", plot_state, growth_ticks, planted_tier)
	_refresh_visual()


## Each peer records the dock trophy in their own profile + toast
## (server RPC, paralleling dungeon.record_apex_kill).
@rpc("any_peer", "call_local")
func record_dock_trophy(trophy_id: String) -> void:
	if SaveManager.record_dock_trophy(trophy_id):
		_toast_local("TROPHY: Golden Gourd harvested!")
		AudioManager.sfx("unlock")


## Client-side presentation: server-rpc'd toast for the acting peer.
## call_local: when the actor IS the server (host/solo), executes locally.
@rpc("any_peer", "call_local")
func on_plot_toast(msg: String) -> void:
	_toast_local(msg)


## P2P peer id of the RPC sender; local (server) calls fall back to the
## server's own id. Never a 64-bit Steam id (see AGENTS.md).
func _sender_peer() -> int:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender


func _player_for_peer(peer: int) -> Player:
	if test_player != null:
		return test_player
	for n in get_tree().get_nodes_in_group("players"):
		if n.get_multiplayer_authority() == peer:
			return n as Player
	return null


func _local_player() -> Player:
	var me := int(multiplayer.get_unique_id())
	for n in get_tree().get_nodes_in_group("players"):
		if n.get_multiplayer_authority() == me:
			return n as Player
	return null


## The local player's bag count of an item (prompts read the
## bag — the client-visible mirror of the server ledger).
func _local_bag_count(item_id: String) -> int:
	var p := _local_player()
	if p == null:
		return 0
	var total := 0
	for entry in p.inventory:
		var item := (entry as Dictionary).get("item") as ItemData
		if item != null and item.id == item_id:
			total += int((entry as Dictionary).get("count", 0))
	return total


func _toast_local(msg: String) -> void:
	var p := _local_player()
	if p != null and p.hud != null:
		p.hud.toast(msg)


func _claim(peer: int) -> void:
	if occupied_by != 0:
		return
	occupied_by = peer
	rpc("sync_occupant", occupied_by)


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


## Growth visuals: soil tint per state + procedural sprout boxes.
## (Art Director delivers real tilled-soil / crop-stage sprites later.)
func _refresh_visual() -> void:
	var soil := get_node_or_null("Soil") as MeshInstance3D
	if soil != null:
		var tint := Color(0.25, 0.16, 0.10) # untilled: packed dark earth
		if plot_state == "tilled" or plot_state == "planted":
			tint = Color(0.38, 0.26, 0.15) # tilled: loosened lighter soil
		elif plot_state == "growing":
			tint = Color(0.33, 0.24, 0.14)
		elif plot_state == "harvestable":
			tint = Color(0.40, 0.30, 0.16) # harvestable: rich worked soil
		var m := StandardMaterial3D.new()
		m.albedo_color = tint
		soil.material_override = m
	var crops := get_node_or_null("Crops")
	if crops != null:
		for c in crops.get_children():
			c.queue_free()
		_add_sprouts(crops)


func _add_sprouts(parent: Node) -> void:
	if plot_state == "untilled" or plot_state == "tilled":
		return
	var col := Color(0.25, 0.7, 0.25) # planted/growing: green sprouts
	var h := 0.18
	if plot_state == "growing":
		h = 0.38
	elif plot_state == "harvestable":
		col = Color(1.0, 0.8, 0.2) # harvestable: golden heads
		h = 0.55
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.6
	for off in [Vector3(-0.9, 0, -0.6), Vector3(0.2, 0, -0.9), Vector3(1.0, 0, 0.1), Vector3(-0.3, 0, 0.8), Vector3(0.9, 0, 0.9)]:
		var s := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.14, h, 0.14)
		s.mesh = sm
		s.position = off + Vector3(0, 0.12 + h * 0.5, 0)
		s.material_override = mat
		parent.add_child(s)


func _build() -> void:
	# Tilled soil square with furrow ridges, corner posts, and a small claim
	# sign. _refresh_visual re-tints/re-models per growth state (Phase 3).
	var soil_m := StandardMaterial3D.new()
	soil_m.albedo_color = Color(0.25, 0.16, 0.10)
	var ridge_m := StandardMaterial3D.new()
	ridge_m.albedo_color = Color(0.32, 0.21, 0.13)
	var base := MeshInstance3D.new()
	base.name = "Soil"
	var bm := BoxMesh.new()
	bm.size = Vector3(3.4, 0.12, 3.4)
	base.mesh = bm
	base.position = Vector3(0, 0.06, 0)
	base.material_override = soil_m
	add_child(base)
	for k in 3:
		var ridge := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(3.2, 0.10, 0.28)
		ridge.mesh = rm
		ridge.position = Vector3(0, 0.14, -1.1 + float(k) * 1.1)
		ridge.material_override = ridge_m
		add_child(ridge)
	var crops := Node3D.new()
	crops.name = "Crops"
	add_child(crops)
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
