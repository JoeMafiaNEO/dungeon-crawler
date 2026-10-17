class_name DockMerchant
extends Node3D
## Issue #102 Phase 4: dock merchant (misty docks level). E-interact opens
## the vendor UI (hud.show_dock_vendor): buys seeds, bait, fertilizer,
## healing consumables and wave-buffs for farm cash; sells fish and crops
## for farm cash.
##
## Trust model: all transactions are server-side. The client UI sends
## request_buy/request_sell; the server validates the item id, the price,
## and the peer's DockEconomy ledger (funds + server-granted stock), then
## mutates the ledger and rpc_ids the owning peer to mirror the change in
## their inventory stack (inventory is per-peer authoritative, mirroring
## the Phase 3 seed pattern). RPCs take no peer id — the server attributes
## every call via multiplayer.get_remote_sender_id() (P2P peer ids;
## server = 1, never the 64-bit Steam id). Light anti-cheat, co-op game.

## TEST SEAM: test_player overrides _player_for_peer().
var test_player: Player = null

## Issue #142: dock purchases awaiting their grant outcome, keyed by
## purchase tag (see request_buy / report_claim). A purchase whose
## outcome never reports rolls back by default after a timeout.
var _pending_dock: Dictionary = {}
var _dock_seq := 0


## Vendor buy catalog. Prices are the DockEconomy.PRICE_* consts (Jesse's
## numbers calls); the catalog is built here so the HUD reads one list.
static func catalog() -> Array:
	return [
		{"id": DockEconomy.SEED_ITEM, "price": DockEconomy.PRICE_SEED},
		{"id": DockEconomy.BAIT_ITEM, "price": DockEconomy.PRICE_BAIT},
		{"id": DockEconomy.FERTILIZER_ITEM, "price": DockEconomy.PRICE_FERTILIZER},
		{"id": DockEconomy.SALVE_ITEM, "price": DockEconomy.PRICE_SALVE},
		{"id": DockEconomy.DRAUGHT_ITEM, "price": DockEconomy.PRICE_DRAUGHT},
		{"id": DockEconomy.CURRENT_ITEM, "price": DockEconomy.PRICE_CURRENT},
		{"id": DockEconomy.BULWARK_ITEM, "price": DockEconomy.PRICE_BULWARK},
		# Issue #104 Phase 3: GEAR listing — permanent stock, re-buyable
		# if disposed, granted as a plain inventory item (NOT a tracked
		# dock good: no stock ledger, never sellable back here).
		{"id": DockEconomy.ROD_ITEM, "price": DockEconomy.PRICE_ROD, "gear": true},
	]


static func catalog_price(item_id: String) -> int:
	for entry in catalog():
		if str(entry.get("id")) == item_id:
			return int(entry.get("price"))
	return -1


func _ready() -> void:
	add_to_group("dock_merchant")
	_build()


func prompt_text() -> String:
	return "Browse dock merchant ({interact})"


func interact(player: Player) -> void:
	if player.hud != null and player.hud.has_method("show_dock_vendor"):
		player.hud.show_dock_vendor()


## HUD accessor (avoids static-class refs from hud.gd).
func get_catalog() -> Array:
	return catalog()


## --- Server RPCs: balance query ---

@rpc("any_peer", "call_local")
func request_dock_balance() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender_peer()
	_tell(peer, "dock_balance", [DockEconomy.cash_balance(peer)])


## Client-side: authoritative balance lands here; the HUD updates its label.
@rpc("any_peer", "call_local")
func dock_balance(balance: int) -> void:
	var p := _local_player()
	if p != null and p.hud != null and p.hud.has_method("set_dock_balance"):
		p.hud.set_dock_balance(balance)


## --- Server RPCs: buying (farm cash -> goods) ---

@rpc("any_peer", "call_local")
func request_buy(item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender_peer()
	var player := _player_for_peer(peer)
	if player == null:
		return
	var price := catalog_price(item_id)
	if price < 0:
		_tell(peer, "on_dock_toast", ["The merchant doesn't sell that."])
		return
	if not DockEconomy.spend_cash(peer, price):
		_tell(peer, "on_dock_toast", ["Not enough farm cash. Need %d." % price])
		return
	# Issue #142: the purchase stays pending until the grant reports
	# its outcome (receive_item's report leg). The per-class ledger
	# credits below land at purchase time and roll back on a failed
	# grant, together with the cash; the on_dock_bought tell fires in
	# report_claim — money and goods never vanish silently.
	_dock_seq += 1
	_pending_dock[_dock_seq] = {"peer": peer, "item_id": item_id, "price": price,
		"seed": item_id == DockEconomy.SEED_ITEM,
		"stock": item_id == DockEconomy.BAIT_ITEM or item_id == DockEconomy.FERTILIZER_ITEM,
		"since": Time.get_ticks_msec() / 1000.0}
	match item_id:
		DockEconomy.SEED_ITEM:
			# Phase 3 flagged seam: vendor seed purchases MUST update the
			# server seed ledger (closed here).
			FarmPlot.grant_seeds(peer, 1)
		DockEconomy.BAIT_ITEM, DockEconomy.FERTILIZER_ITEM:
			DockEconomy.grant_stock(peer, item_id, 1)
		_:
			# Healing consumables / wave buffs: plain inventory items, no
			# server tracking needed. They persist via the existing
			# run inventory, so they stay usable in later levels.
			pass
	player.rpc_id(peer, "receive_item", item_id, -1, str(get_path()), 1, _dock_seq)


## Issue #142: the grant outcome for a dock purchase (called by the
## buyer's own receive_item via the report leg). Success moves the
## on_dock_bought tell here; failure refunds the cash and rolls the
## per-class ledger credits back.
@rpc("any_peer", "call_local")
func report_claim(taken: int, tag: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var rec: Dictionary = _pending_dock.get(tag, {})
	if rec.is_empty() or int(rec.get("peer", -1)) != _sender_peer():
		return
	_pending_dock.erase(tag)
	if taken >= 1:
		_tell(int(rec["peer"]), "on_dock_bought", [str(rec["item_id"])])
	else:
		_rollback_dock(rec)


## Issue #142: make a failed (or never-reported) dock purchase
## whole: cash refund plus the ledger credits it carried.
func _rollback_dock(rec: Dictionary) -> void:
	var peer := int(rec.get("peer", 0))
	DockEconomy.grant_cash(peer, int(rec.get("price", 0)))
	if bool(rec.get("seed")):
		FarmPlot.grant_seeds(peer, -1)
	if bool(rec.get("stock")):
		DockEconomy.spend_stock(peer, str(rec.get("item_id", "")), 1)
	_tell(peer, "on_dock_toast", ["Inventory full — purchase refunded."])


## Issue #142: dock purchases with no outcome after the timeout
## roll back by default.
func _process(_delta: float) -> void:
	if not multiplayer.is_server() or _pending_dock.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for tag in _pending_dock.keys():
		var rec: Dictionary = _pending_dock[tag]
		if now - float(rec.get("since", now)) > 3.0:
			_pending_dock.erase(tag)
			_rollback_dock(rec)


## --- Server RPCs: selling (fish/crops -> farm cash) ---

@rpc("any_peer", "call_local")
func request_sell(item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender_peer()
	var player := _player_for_peer(peer)
	if player == null:
		return
	var value := DockEconomy.sell_value_for(item_id)
	if value <= 0:
		_tell(peer, "on_dock_toast", ["The merchant doesn't want that."])
		return
	if not DockEconomy.spend_stock(peer, item_id, 1):
		_tell(peer, "on_dock_toast", ["You don't have that to sell."])
		return
	DockEconomy.grant_cash(peer, value)
	_take_from_peer(player, peer, item_id)
	_grant_to_peer(player, peer, DockEconomy.CASH_ITEM, value)
	_tell(peer, "on_dock_sold", [item_id, value])


## --- Client-side presentation (driven by server RPCs) ---

@rpc("any_peer", "call_local")
func on_dock_toast(msg: String) -> void:
	var p := _local_player()
	if p != null and p.hud != null:
		p.hud.toast(msg)


@rpc("any_peer", "call_local")
func on_dock_bought(item_id: String) -> void:
	_refresh_vendor_ui("Bought: %s" % _display_name(item_id))


@rpc("any_peer", "call_local")
func on_dock_sold(item_id: String, value: int) -> void:
	_refresh_vendor_ui("Sold %s: +%d farm cash" % [_display_name(item_id), value])


func _refresh_vendor_ui(msg: String) -> void:
	var p := _local_player()
	if p == null or p.hud == null:
		return
	p.hud.toast(msg)
	if p.hud.has_method("refresh_dock_vendor"):
		p.hud.refresh_dock_vendor()


func _display_name(item_id: String) -> String:
	var item: ItemData = ItemDB.get_item(item_id)
	return item.display_name if item != null else item_id


## --- Peer plumbing ---

## Grant n of an item to a peer's inventory (inventory is per-peer
## authoritative). SteamMultiplayerPeer can't rpc_id its own peer id, so
## the server calls its own player node directly (hud._on_vendor_buy
## pattern); remote peers get rpc_id.
func _grant_to_peer(player: Player, peer: int, item_id: String, count: int) -> void:
	for i in count:
		if peer == multiplayer.get_unique_id():
			player.receive_item(item_id)
		else:
			player.rpc_id(peer, "receive_item", item_id)


## Remove 1 of an item from a peer's own stack (client-side drop, mirroring
## the Phase 3 consume_seed_item pattern).
func _take_from_peer(player: Player, peer: int, item_id: String) -> void:
	if peer == multiplayer.get_unique_id():
		player.consume_dock_good(item_id)
	else:
		player.rpc_id(peer, "consume_dock_good", item_id)


## Server -> one peer notification. Same Steam-safe direct/rpc split.
func _tell(peer: int, method: StringName, args: Array) -> void:
	if peer == multiplayer.get_unique_id():
		callv(method, args)
	else:
		match args.size():
			0:
				rpc_id(peer, method)
			1:
				rpc_id(peer, method, args[0])
			_:
				rpc_id(peer, method, args[0], args[1])


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


## --- Prop: dock stall (code-built, VendorStall aesthetic, dock flavor) ---

func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


func _build() -> void:
	var wood := _mat(Color(0.42, 0.33, 0.22))
	var wood_dark := _mat(Color(0.30, 0.22, 0.15))
	var canvas := _mat(Color(0.25, 0.45, 0.55))
	# Counter + posts + canvas awning.
	_box(Vector3(3.0, 0.15, 1.4), Vector3(0, 0.85, 0), wood)
	for px in [-1.35, 1.35]:
		for pz in [-0.6, 0.6]:
			_box(Vector3(0.12, 2.4, 0.12), Vector3(px, 1.2, pz), wood_dark)
	_box(Vector3(3.4, 0.12, 1.8), Vector3(0, 2.5, 0), canvas)
	# Wares: fish crate, coin pouch, bottle.
	_box(Vector3(0.5, 0.35, 0.5), Vector3(-0.9, 1.10, 0), _mat(Color(0.55, 0.42, 0.28)))
	_box(Vector3(0.3, 0.45, 0.3), Vector3(0.0, 1.15, 0.1), _mat(Color(0.85, 0.70, 0.30), Color(0.85, 0.70, 0.30), 0.5))
	_box(Vector3(0.25, 0.5, 0.25), Vector3(0.9, 1.18, -0.1), _mat(Color(0.30, 0.55, 0.85)))
	# DOCK MERCHANT sign (billboarded so it reads from anywhere).
	var label := Label3D.new()
	label.text = "DOCK MERCHANT"
	label.font_size = 64
	label.modulate = Color(0.65, 0.95, 1.0)
	label.outline_size = 10
	label.position = Vector3(0, 3.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
