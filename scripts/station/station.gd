class_name Station
extends Node3D
## Station annex content (issue #2): the train station lives inside the
## dungeon's annex hall as a child node. The dungeon owns players + HUD;
## the station contributes the train, departures board, vendor, heal pad,
## and the vote flow, and emits departure_resolved for the dungeon's ride.
##
## Run handoff (set before add_child, i.e. before _ready):
##   Station.next_level_number (this class; drives board rec. levels) /
##   station.dungeon / station.annex (instance vars)

const DepartureBoardScript := preload("res://scripts/station/departure_board.gd")
const VaultDoorScript := preload("res://scripts/station/vault_door.gd")
const VendorStallScript := preload("res://scripts/station/vendor_stall.gd")
const BountyBoardScript := preload("res://scripts/station/bounty_board.gd")
const RelicVaultScript := preload("res://scripts/station/relic_vault.gd")

const DEPART_TIME := 45.0
const HEAL_TICK := 0.5
const HEAL_RADIUS := 2.2
## Door-close animation window after the depart lever is pulled (issue #93
## Phase 3): doors shut, then departure_resolved fires and the ride begins.
const DEPART_CLOSE_TIME := 2.0

## Vendor stock (server-authoritative, picked fresh every station visit).
const VENDOR_POTIONS := [
	{"id": "health_potion", "price": 50},
	{"id": "swift_potion", "price": 75},
	{"id": "power_elixir", "price": 100},
]
const VENDOR_POTION_IDS := ["health_potion", "swift_potion", "power_elixir"]
var vendor_stock: Array = [] # [{id, price}]
## Issue #142: vendor purchases awaiting their grant outcome, keyed
## by purchase tag (see buy_vendor_item / report_claim). A purchase
## whose outcome never reports refunds by default after a timeout.
var _pending_vendor: Dictionary = {}
var _vendor_seq := 0

## Danger stars per theme (informational only — no locks). Moved here from
## the old floating HUD board panel; the physical 3D board reads it.
const BOARD_STARS := {
	"village": "★☆☆☆", "dungeon": "★★☆☆", "depths": "★★★☆",
	"supermarket": "★☆☆☆", "warlord": "★★★★",
	"apex": "★★★★★", "misty_docks": "★☆☆☆",
	# Issue #182: PLACEHOLDER stars — Jesse tunes them at P4.
	"mason_vault": "★★★",
}

## Per-theme station dressing: platform lamp tint (Phase 5).
const DRESSING_LAMPS := {
	"village": Color(0.6, 1.0, 0.6),
	"dungeon": Color(0.5, 0.7, 1.0),
	"depths": Color(0.8, 0.4, 0.9),
	"supermarket": Color(1.0, 1.0, 0.95),
	"warlord": Color(1.0, 0.55, 0.25),
	"apex": Color(1.0, 0.25, 0.2),
	"misty_docks": Color(0.45, 0.7, 0.9),
	"mason_vault": Color(0.85, 0.78, 0.58),
}

## Owning dungeon: player roster + departure hop target.
var dungeon: Node = null
## Issue #201: the theme of the level this station lives in,
## handed off by the dungeon before _ready (the linear successor
## rule is theme-keyed). "" = unknown (tooling) — linear mode
## stays off, exactly the legacy behavior.
var current_theme_id := ""
## The annex shell built by StationAnnex: provides floor, walls, roof, and
## the 4 lamp posts that apply_dressing tints.
var annex: StationAnnex = null
## Emitted (server) when the vote resolves. The dungeon drives the ride + hop.
signal departure_resolved(theme_id: String)

static var next_level_number: int = 1

## Seed for the upcoming level, rolled once by the server on station load so
## Save & Quit and the departure hop agree on it.
var departure_seed := 0

var _time_left := DEPART_TIME
## Embedded mode: the 45s vote timer starts on the first board interaction,
## not on ready (the hall is open from level start).
var _timer_running := true
var _departing := false
var _last_sync_sec := -1
## Issue #93 Phase 3: after a unanimous vote the station opens the lobby
## doors and waits for the depart lever — player-paced, no timer. The vote
## resolves into _depart_theme; the lever pull completes the departure via
## departure_resolved.
var _depart_theme := ""
var _depart_requested := false
var _board_label: Label3D = null
var _ring: MeshInstance3D
var _heal_pad: Area3D
var _heal_tick := 0.0
## Destination votes: peer_id -> theme_id (server-authoritative, Phase 2).
var votes := {}
## Phase 5 dressing: platform lamps, NOW BOARDING sign, per-theme prop sets.
var _lamps: Array = []
var _boarding_sign: Label3D
var _dressing: Node3D
## Issue #201 (spec section 5): the Mason's Vault hub door.
## Built only in linear mode; visible only while the vault gate
## is open — closed, there is no door, no sign, no trace.
var _vault_door: Node3D = null


## Issue #201 (P1 Slice 1): the Act 1 linear flow. The axis is
## open (Dungeon.act1_step >= 0) and this level is not Warlord's —
## departures FROM Warlord belong to the legacy board flow (the
## spec section 10 interim), so the Warlord hub keeps its board.
func _linear_mode() -> bool:
	return Dungeon.act1_step >= 0 and _current_theme() != "" \
		and _current_theme() != "warlord"


## The hall strip's dressing test (issue #201 section 4, widened
## by Jesse 2026-10-27): every Act 1 hub — Warlord's Domain
## included — stands an elevator bank where the tracks were.
## Wider than _linear_mode on purpose: the linear rule also
## drives departure flow, and Warlord's keeps its legacy path.
func _elevator_dressed() -> bool:
	return Dungeon.act1_step >= 0 and _current_theme() != ""


func _current_theme() -> String:
	if current_theme_id != "":
		return current_theme_id
	return Dungeon.next_theme_id


## Where the depart lever goes in linear mode: the current
## theme's successor in the six — or, inside the Vault, the
## successor the detour deferred (vault_return_theme).
func linear_destination() -> String:
	if not _linear_mode():
		return ""
	if _current_theme() == "mason_vault":
		return Dungeon.vault_return_theme
	return Dungeon.act1_successor(_current_theme())


## Issue #201 (fork 2, LEVER ONLY): the next level is named only
## here — in the depart lever's prompt, at the moment of use.
## No plaque, no board label, no standing signage.
func depart_prompt_text() -> String:
	var dest := linear_destination()
	if dest != "":
		return "Depart for " + theme_display_name(dest)
	return "Pull the depart lever"


func _ready() -> void:
	add_to_group("station")
	randomize()
	if multiplayer.is_server():
		departure_seed = randi()
		_roll_vendor_stock()
	# Annex hall content only: no own floor/environment, lamps, player
	# spawning, or HUD — the dungeon and the annex shell provide those.
	# (Issue #2 Phase 5: the standalone station scene is gone.)
	_timer_running = false
	_build_station_embedded()
	# Dress for the rotation default; re-dressed when a vote resolves.
	# board_destinations() swaps warlord for the APEX ARENA on apex cycles
	# (issue #5) and appends misty_docks as an opt-in 6th row (issue #102),
	# so the rotation default is computed from THEME_ORDER directly — the
	# docks row is opt-in, never the default.
	var rot_idx := (next_level_number - 1) % Dungeon.THEME_ORDER.size()
	var rot_id: String = Dungeon.THEME_ORDER[rot_idx]
	var rot_cycle := int((next_level_number - 1) / Dungeon.THEME_ORDER.size()) + 1
	if Dungeon.is_apex_cycle(rot_cycle):
		rot_id = "apex"
	if _linear_mode():
		# Issue #201 (spec section 2): the hub keeps the CURRENT
		# level's own dressing in linear mode — re-dressing to the
		# departure theme is legacy-only.
		rot_id = _current_theme()
	apply_dressing(rot_id)
	if _linear_mode() and linear_destination() != "":
		# Issue #201 (spec section 2): no vote, no timer — the
		# lobby doors stand open and the depart lever is armed
		# with the successor from the start. The lever pull and
		# the door-close chain are the shipped ones, unchanged.
		_depart_theme = linear_destination()
		_departing = true
		if annex != null:
			annex.set_lobby_doors(true)


func _process(delta: float) -> void:
	# Gold doorway-ring pulse (all peers, pure ambience).
	if _ring != null:
		var s := 1.0 + sin(Time.get_ticks_msec() / 300.0) * 0.04
		_ring.scale = Vector3(s, 1, s)
	# Heal pad (all peers, Jesse 2026-10-10 fix): each peer checks its OWN
	# player locally. The old server-only version couldn't see client bodies
	# in the server's physics space, so clients never got healed.
	_heal_tick -= delta
	if _heal_tick <= 0.0:
		_heal_tick = HEAL_TICK
		_process_heal_pad()
	# Issue #201 (spec section 5): the hub door exists exactly
	# while the gate is open (the static is the lan_sync mirror).
	if _vault_door != null:
		_vault_door.visible = Dungeon.vault_gate_open
	if not multiplayer.is_server():
		return
	_process_pending_vendor()
	if not _departing and _timer_running:
		_time_left -= delta
		var sec := int(ceil(maxf(_time_left, 0.0)))
		if sec != _last_sync_sec:
			_last_sync_sec = sec
			rpc("station_timer_sync", maxf(_time_left, 0.0))
		if _time_left <= 0.0:
			if _unanimous_theme() != "":
				depart()
			else:
				# No unanimity: the train waits. Reset the clock, keep the
				# votes (players may change them), and try again.
				_time_left = DEPART_TIME
				_last_sync_sec = -1
				rpc("station_timer_sync", DEPART_TIME)
				rpc("vote_reset_notice")


## Heal pad: every tick, living players on the pad get 15% max HP.
## Heal pad (Jesse 2026-10-10 fix): each peer checks its OWN player against
## the pad's local physics overlap. The old server-only loop used the
## server's get_overlapping_bodies(), which can't see client bodies, so
## clients never got healed. heal() is any_peer + call_local, so a direct
## local call is safe on all peers (co-op trust model).
func _process_heal_pad() -> void:
	if _heal_pad == null:
		return
	var me := _my_player()
	if me == null:
		return
	if not bool(me.get("alive")):
		return
	if float(me.get("hp")) >= float(me.get("max_hp")):
		return
	var on_pad := false
	for b in _heal_pad.get_overlapping_bodies():
		if b == me:
			on_pad = true
			break
	if not on_pad:
		return
	me.heal(heal_tick_amount(float(me.get("max_hp"))))


## Heal tick amount: 15% of max HP per 0.5s tick (~3.3s to full from empty).
static func heal_tick_amount(max_hp: float) -> float:
	return max_hp * 0.15


## Vendor buy price: 3x sell value, $50 floor (potions have fixed prices).
static func vendor_price(sell_value: int) -> int:
	return maxi(50, sell_value * 3)


## Pure purchase resolution (static for testability).
## Returns {ok, price, new_cash} or {ok:false, reason}.
static func resolve_purchase(cash: int, stock: Array, item_id: String) -> Dictionary:
	var price := -1
	for entry in stock:
		if str(entry.get("id")) == item_id:
			price = int(entry.get("price"))
			break
	if price < 0:
		return {"ok": false, "reason": "not_in_stock"}
	if cash < price:
		return {"ok": false, "reason": "broke", "price": price}
	return {"ok": true, "price": price, "new_cash": cash - price}


## Peer ids of living players (voters).
func _living_peer_ids() -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p == null or not bool(p.get("alive")):
			continue
		out.append(int(p.get_multiplayer_authority()))
	return out


## Unanimous destination, or "" when the living players don't all agree on
## one. living_override lets tests drive the flow without a scene tree of
## players.
func _unanimous_theme(living_override: Array = []) -> String:
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	return resolve_destination(votes, living)


## Destination resolution (static for testability). Departure requires EVERY
## living player to vote for the SAME destination; anything else returns ""
## (no departure — the timer resets and voting continues).
static func resolve_destination(p_votes: Dictionary, living: Array) -> String:
	if living.is_empty():
		return ""
	var theme := ""
	for pid in living:
		if not p_votes.has(pid):
			return ""
		var t := str(p_votes[pid])
		if theme == "":
			theme = t
		elif t != theme:
			return ""
	return theme


## Recommended level for a theme at the upcoming level: informational only.
static func recommended_level(theme_id: String, next_level: int) -> int:
	var cycle := int((next_level - 1) / Dungeon.THEME_ORDER.size()) + 1
	var idx := Dungeon.THEME_ORDER.find(theme_id)
	if idx < 0:
		# Opt-in destinations (misty_docks) target the upcoming level itself.
		return next_level
	return (cycle - 1) * Dungeon.THEME_ORDER.size() + (idx + 1)


## Theme display name from its .tres (falls back to capitalized id).
static func theme_display_name(theme_id: String) -> String:
	var t = load("res://data/levels/theme_%s.tres" % theme_id)
	if t != null and str(t.get("display_name")) != "":
		return str(t.get("display_name"))
	# Issue #182: until P2 lands the vault's theme resource, the
	# board shows its proper name (the capitalize fallback would
	# read "Mason Vault"). The .tres wins the day it exists.
	if theme_id == "mason_vault":
		return "The Mason's Vault"
	return theme_id.capitalize()


## Record a vote from a peer. Pure logic (no RPC): the cast_vote RPC wrapper
## handles networking + the all-voted early departure. living_override lets
## tests drive the flow without a scene tree. Returns {"ok": bool, ...}.
func record_vote(peer_id: int, theme_id: String, living_override: Array = []) -> Dictionary:
	# Issue #201 (spec section 2): in linear mode the vote is
	# bypassed, not deleted — refused here, so no vote is ever
	# recorded, the 45s timer never starts, and the destination
	# popup (board-driven) never opens. Legacy flow untouched.
	if _linear_mode():
		return {"ok": false, "reason": "linear"}
	# Issue #203 (P3): a revealed run's board is retired — votes
	# are refused, so no departure can ever resolve from it.
	if Dungeon.revealed:
		return {"ok": false, "reason": "revealed"}
	# Votes must name a destination the board actually offers: on apex cycles
	# (issue #5) warlord is swapped for the APEX ARENA.
	if not theme_id in Dungeon.board_destinations(next_level_number):
		return {"ok": false, "reason": "bad_theme"}
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	if not peer_id in living:
		return {"ok": false, "reason": "not_living"}
	votes[peer_id] = theme_id
	if not _timer_running:
		# First board interaction starts the 45s departure countdown.
		_timer_running = true
		_time_left = DEPART_TIME
		_last_sync_sec = -1
	return {"ok": true}


## Vote for a destination. Server records; every peer syncs for board UI.
@rpc("any_peer", "call_local")
func cast_vote(theme_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var res: Dictionary = record_vote(sender, theme_id)
	if not bool(res.get("ok", false)):
		return
	rpc("sync_votes", votes)
	if not _departing and _unanimous_theme() != "":
		depart()


## Keep every peer's physical board in sync with the server's vote table.
@rpc("any_peer", "call_local")
func sync_votes(v: Dictionary) -> void:
	votes = v.duplicate()
	var board := get_tree().get_first_node_in_group("departure_board")
	if board != null:
		board.set_tallies(votes)
		if board.has_method("set_my_vote"):
			board.set_my_vote(str(votes.get(multiplayer.get_unique_id(), "")))
	# Issue #29: refresh the 2D popup tallies if it's open.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("refresh_destination_popup"):
		hud.refresh_destination_popup(votes, str(votes.get(multiplayer.get_unique_id(), "")))


## Vendor stock (Phase 4): 3 fixed potions + 3 rotating items.
## Rotating picks exclude potions, supermarket_loot, and meta-locked items
## unless the local save has them unlocked. New stock every station visit.
func _roll_vendor_stock() -> void:
	vendor_stock = build_vendor_stock()
	rpc("sync_vendor_stock", vendor_stock)


## Pure stock builder (static for testability).
static func build_vendor_stock() -> Array:
	var stock: Array = VENDOR_POTIONS.duplicate(true)
	var pool: Array = []
	for id in ItemDB.items.keys():
		if id in VENDOR_POTION_IDS:
			continue
		var item: ItemData = ItemDB.items[id]
		if item == null:
			continue
		if bool(item.get("supermarket_loot")):
			continue
		# Issue #102 Phase 4: dock-economy goods are balance-isolated —
		# run cash ("gold") never buys them and they never convert to it.
		if bool(item.get("dock_good")):
			continue
		# Issue #113 Phase 3: starting gear is never purchasable.
		if bool(item.get("starting_gear")):
			continue
		if bool(item.get("meta_locked")) and not SaveManager.is_item_unlocked(id):
			continue
		pool.append(id)
	pool.shuffle()
	for i in mini(3, pool.size()):
		var item: ItemData = ItemDB.items[pool[i]]
		stock.append({"id": pool[i], "price": vendor_price(int(item.get("sell_value")))})
	return stock


## Sync vendor stock to every peer (also called for late joiners).
@rpc("any_peer", "call_local")
func sync_vendor_stock(stock: Array) -> void:
	vendor_stock = stock.duplicate(true)


## Buy a vendor item. Server validates stock + cash; mirrors buy_potion.
@rpc("any_peer", "call_local")
func buy_vendor_item(item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var player := get_player_node(sender)
	if player == null or not bool(player.get("alive")):
		return
	var res := resolve_purchase(int(player.get("supermarket_cash")), vendor_stock, item_id)
	if not bool(res.get("ok")):
		if str(res.get("reason")) == "broke":
			player.rpc_id(sender, "on_buy_failed", int(res.get("price")))
		return
	player.set("supermarket_cash", int(res.get("new_cash")))
	# Issue #142: the purchase stays pending until the grant reports
	# its outcome (receive_item's report leg). The success tell fires
	# in report_claim; a grant that lands nothing refunds in full —
	# money never vanishes silently.
	_vendor_seq += 1
	_pending_vendor[_vendor_seq] = {"peer": sender, "item_id": item_id,
		"price": int(res.get("price")), "since": Time.get_ticks_msec() / 1000.0}
	player.rpc_id(sender, "receive_item", item_id, -1, str(get_path()), 1, _vendor_seq)


## Issue #142: the grant outcome for a vendor purchase (called by
## the buyer's own receive_item via the report leg). Success moves
## the on_bought tell here; failure refunds in full.
@rpc("any_peer", "call_local")
func report_claim(taken: int, tag: int = 0) -> void:
	if not multiplayer.is_server():
		return
	var rec: Dictionary = _pending_vendor.get(tag, {})
	if rec.is_empty():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if int(rec.get("peer", -1)) != sender:
		return
	_pending_vendor.erase(tag)
	if taken >= 1:
		var player := get_player_node(sender)
		if player != null:
			player.rpc_id(sender, "on_bought", str(rec.get("item_id", "")), int(rec.get("price", 0)))
	else:
		_refund_vendor(sender, rec)


## Issue #142: refund a vendor purchase whose grant landed nothing
## (or whose outcome never arrived — _process_pending_vendor).
func _refund_vendor(peer: int, rec: Dictionary) -> void:
	var player := get_player_node(peer)
	if player == null:
		return
	player.set("supermarket_cash", int(player.get("supermarket_cash")) + int(rec.get("price", 0)))
	if peer == multiplayer.get_unique_id() or multiplayer.get_peers().has(peer):
		player.rpc_id(peer, "on_buy_refunded", int(rec.get("price", 0)))


## Issue #142: vendor purchases with no outcome after the timeout
## refund by default.
func _process_pending_vendor() -> void:
	if not multiplayer.is_server() or _pending_vendor.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for tag in _pending_vendor.keys():
		var rec: Dictionary = _pending_vendor[tag]
		if now - float(rec.get("since", now)) > 3.0:
			_pending_vendor.erase(tag)
			_refund_vendor(int(rec.get("peer", 0)), rec)


@rpc("any_peer", "call_local")
func station_timer_sync(time_left: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_station_timer"):
		hud.show_station_timer(time_left)


## Timer expired without unanimity: tell every peer the clock restarted and
## the vote stays open.
@rpc("any_peer", "call_local")
func vote_reset_notice() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast("No agreement — vote again.")


## Server-authoritative departure (issue #93 Phase 3): resolve the
## destination, re-dress, then open the lobby doors and wait for the depart
## lever — player-paced, no timer. The lever pull completes the departure
## via _complete_departure -> departure_resolved, and the dungeon's ride
## begins. living_override lets tests drive the flow without a scene tree
## of players.
func depart(living_override: Array = []) -> void:
	if _departing or not multiplayer.is_server():
		return
	# Issue #203 (P3): a revealed run has no departure — the
	# board flow is retired for it, wherever this station sits.
	if Dungeon.revealed:
		return
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	var theme_id := resolve_destination(votes, living)
	if theme_id == "":
		return # No unanimity — the train doesn't leave.
	# Issue #11 Phase 1: ASCEND — party-wide prestige reset, not a destination.
	if theme_id == "ASCEND":
		_departing = true
		rpc("_do_ascend")
		return
	_departing = true
	apply_dressing(theme_id)
	_open_lobby_for_boarding(theme_id)


## Issue #11 Phase 1: ASCEND execution. Each player increments their OWN
## profile ascension_count (not host-inherited), wipes their run, and starts
## a fresh Cycle 1. Server triggers, clients execute locally.
@rpc("any_peer", "call_local", "reliable")
func _do_ascend() -> void:
	# Increment own ascension count.
	var new_count := SaveManager.add_ascension()
	print("[Ascension] Ascended! Count: %d (+%d%% XP)" % [new_count, int((SaveManager.get_ascension_xp_mult() - 1.0) * 100.0)])
	# Issue #11 Phase 2: full run wipe. Clear the current run slot
	# (same wipe path as death — inventory, level, gold, bounties gone;
	# profile achievements/unlocks/collections/trophies untouched).
	var mode := NetworkManager.active_run_mode
	var slot := NetworkManager.active_run_slot
	if mode != "" and slot >= 0:
		SaveManager.clear_run(mode, slot)
	# Reset local player to fresh Cycle 1 state (level 1).
	var player := get_tree().get_first_node_in_group("players")
	if player != null and player.is_multiplayer_authority():
		player.set("level", 1)
		player.set("xp", 0)
		# Clear inventory via the player's reset (if available).
		if player.has_method("clear_inventory"):
			player.clear_inventory()
	# Update the HUD ascension indicator.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("_update_ascension_indicator"):
		hud._update_ascension_indicator()
	# Reset the vote state so the board can be used again for the fresh run.
	if multiplayer.is_server():
		votes.clear()
		_departing = false
		rpc("sync_votes", votes)


## Vote resolved: open the lobby doors, announce ALL ABOARD, and wait for
## the depart lever (issue #93 Phase 3). Player-paced — no timer, no roster.
func _open_lobby_for_boarding(theme_id: String) -> void:
	_depart_theme = theme_id
	_depart_requested = false
	rpc("announce_boarding", theme_id)
	# Issue #93 Phase 2: vote resolve opens the lobby doors.
	if annex != null:
		annex.set_lobby_doors(true)


## Record a depart-lever pull from a peer. Pure logic (no RPC): the
## request_depart RPC wrapper handles networking. The vote must have
## resolved and no depart may already be in flight.
## living_override lets tests drive the flow without a scene tree.
## Returns {"ok": bool, ...}.
func record_depart(peer_id: int, living_override: Array = []) -> Dictionary:
	if not _departing or _depart_requested:
		return {"ok": false, "reason": "not_ready"}
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	if not peer_id in living:
		return {"ok": false, "reason": "not_living"}
	_depart_requested = true
	return {"ok": true}


## Record a Vault-door use from a peer. Pure logic (no RPC): the
## request_vault_entry RPC wrapper handles networking. Linear
## mode only, gate open only, one departure in flight at most.
## On success the deferred successor is recorded and the door
## resolves a mason_vault departure through the identical chain
## (door close -> departure_resolved) the lever uses.
func record_vault_entry(peer_id: int, living_override: Array = []) -> Dictionary:
	if not _linear_mode():
		return {"ok": false, "reason": "not_linear"}
	if not Dungeon.vault_gate_open:
		return {"ok": false, "reason": "gate_closed"}
	if _depart_requested or _current_theme() == "mason_vault":
		return {"ok": false, "reason": "not_ready"}
	var living := living_override if not living_override.is_empty() else _living_peer_ids()
	if not peer_id in living:
		return {"ok": false, "reason": "not_living"}
	# Issue #201 (spec section 5): boarding to the Vault records
	# the successor the party is deferring; the Vault's own
	# departure goes there (see linear_destination).
	Dungeon.vault_return_theme = Dungeon.act1_successor(_current_theme())
	_depart_theme = "mason_vault"
	_depart_requested = true
	return {"ok": true}


## Vault door used in the hub. Server validates; any living
## player may use it (the lever pattern).
@rpc("any_peer", "call_local")
func request_vault_entry() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var res: Dictionary = record_vault_entry(sender)
	if not bool(res.get("ok", false)):
		return
	_begin_departure_close()


## Depart lever pulled in the lobby. Server validates; any living player may
## pull it. Stragglers outside are pulled into the lobby by the ride.
@rpc("any_peer", "call_local")
func request_depart() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var res: Dictionary = record_depart(sender)
	if not bool(res.get("ok", false)):
		return
	AudioManager.sfx("board_chime")
	# Issue #201 (spec section 2): station texts retire in Act 1 —
	# the board label position carries nothing in linear mode.
	if _board_label != null and not _linear_mode():
		_board_label.text = "DEPARTING"
	_begin_departure_close()


## Lever accepted: close the lobby doors, wait out the 2s door-close
## animation, then complete the departure and hand off to the dungeon's
## ride chain.
func _begin_departure_close() -> void:
	_apply_depart_close()
	await get_tree().create_timer(DEPART_CLOSE_TIME).timeout
	_complete_departure()


## Door-close half of the departure (split out so tests can drive the door
## state without the 2s timer).
func _apply_depart_close() -> void:
	if annex != null:
		annex.set_lobby_doors(false)


## Doors are shut: lock up, resolve the departure. The dungeon drives the
## whistle / pull-aboard / fade ride and hops to the train interior.
## Split out so tests can drive completion without the 2s timer.
func _complete_departure() -> void:
	AudioManager.sfx("door_lock")
	departure_resolved.emit(_depart_theme)


## ALL ABOARD banner on every peer, retargeted to the lobby doors opening
## (issue #93 Phase 3): the vote resolved, walk in at your own pace.
@rpc("any_peer", "call_local")
func announce_boarding(theme_id: String) -> void:
	AudioManager.sfx("all_aboard")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("announce"):
		hud.announce("ALL ABOARD!")
	# Issue #71: the SELECT DESTINATION popup must not linger past the vote
	# — it covered the doorway instruction.
	if hud != null and hud.has_method("close_destination_popup"):
		hud.close_destination_popup()
	if hud != null and hud.has_method("show_now_boarding"):
		hud.show_now_boarding(theme_id)
	if _board_label != null:
		_board_label.text = "NOW BOARDING: " + theme_id.to_upper()


## Departure ride for the annex (issue #2 Phase 3): re-dress for the
## resolved theme, whistle, pull stragglers aboard, chug + rumble, fade to
## black. Called on all peers via the dungeon's begin_annex_departure rpc.
func play_departure_ride(theme_id: String, spots: Dictionary) -> void:
	# Issue #201 (spec section 2): the annex re-dress to the
	# DEPARTURE theme is legacy-only; in linear mode the hub
	# keeps the current level's dressing through the ride.
	if not _linear_mode():
		apply_dressing(theme_id)
	# Jesse's whistle recording (train_whistle.mp3, file-override) — legacy
	# only under #201: the Act 1 beat has no whistle, chug or rumble.
	if not _linear_mode():
		AudioManager.sfx("train_whistle")
	pull_aboard(spots) # moves players, toasts "All aboard!", hides the timer
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("fade_out"):
		hud.fade_out(1.2)
	await get_tree().create_timer(1.0).timeout
	if TrainInterior.USE_SYNTH_TRAIN_CUES and not _linear_mode():
		AudioManager.sfx("train_chug")
		AudioManager.sfx("rumble")


@rpc("any_peer", "call_local")
func pull_aboard(spots: Dictionary) -> void:
	# Anyone mid-vote steps away from the board first.
	for n in get_tree().get_nodes_in_group("players"):
		if n.has_method("exit_reading"):
			n.exit_reading()
	var me := _my_player()
	if me != null:
		# Fallback is station-relative (hall coordinates).
		var fallback: Vector3 = to_global(Vector3(0, 0.1, 2.0))
		var spot: Vector3 = spots.get(multiplayer.get_unique_id(), fallback)
		me.global_position = spot
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		# Issue #201 (spec section 7): the "All aboard!" toast is
		# retired in Act 1 — the pull itself is unchanged.
		if hud.has_method("toast") and not _linear_mode():
			hud.toast("All aboard!")
		if hud.has_method("hide_station_timer"):
			hud.hide_station_timer()


# --- Players (the dungeon owns spawning; the station only looks players up) ---


func get_player_node(peer_id: int) -> Node:
	# The dungeon owns players — delegate to it.
	if dungeon != null and dungeon.has_method("get_player_node"):
		return dungeon.get_player_node(peer_id)
	return null


func _my_player() -> Player:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Player
		if p != null and p.get_multiplayer_authority() == multiplayer.get_unique_id():
			return p
	return null


# --- Station construction (static shell; all procedural meshes) ---

func _mat(c: Color, emission: Color = Color(0, 0, 0, 1), energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


## Invisible physics slab so players can actually stand in the station.
func _static_box(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.position = pos
	body.add_child(cs)
	add_child(body)


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	parent.add_child(mi)
	return mi


## Annex-hall content layout (issue #2 Phase 2): train along the north side,
## departures board facing the corridor entrance (+z), vendor east, heal pad
## west. All coordinates are local to the station node, which the dungeon
## places at the hall center. No floor/environment/lamps/Players of its own
## — the annex shell and the dungeon provide those.
func _build_station_embedded() -> void:
	var dark := _mat(Color(0.16, 0.15, 0.17))
	var steel := _mat(Color(0.35, 0.36, 0.40))
	var wood := _mat(Color(0.45, 0.32, 0.20))
	var wood_dark := _mat(Color(0.32, 0.22, 0.14))
	var train_green := _mat(Color(0.10, 0.28, 0.16))
	var win_glow := _mat(Color(1.0, 0.75, 0.35), Color(1.0, 0.65, 0.25), 2.5)
	var lamp_glow := _mat(Color(1.0, 0.85, 0.55), Color(1.0, 0.75, 0.40), 3.0)
	var heal_glow := _mat(Color(0.25, 0.95, 0.45), Color(0.20, 0.90, 0.40), 2.0)
	var ring_gold := _mat(Color(1.0, 0.80, 0.30), Color(1.0, 0.70, 0.20), 1.8)

	# North strip. Legacy: two steel rails + wooden sleepers.
	# Issue #201 (spec section 4): in an Act 1 hub a plain elevator
	# bank stands in an unadorned wall where the tracks were.
	if _elevator_dressed():
		_build_elevator_bank()
	else:
		_box(self, Vector3(19, 0.14, 0.14), Vector3(-1.5, 0.10, -5.3), steel)
		_box(self, Vector3(19, 0.14, 0.14), Vector3(-1.5, 0.10, -3.7), steel)
		var sleepers := Node3D.new()
		sleepers.name = "Sleepers"
		add_child(sleepers)
		for x in range(-11, 9, 2):
			_box(sleepers, Vector3(0.5, 0.08, 3.4), Vector3(x, 0.05, -4.5), wood_dark)

	# Issue #97: old green-box train prop removed (Jesse). The #93 rework
	# retired the old boarding flow; the prop was never deleted.

	# Doorway marker: gold pulse ring + destination signage at the lobby
	# doorway (issue #93). Issue #99: doorway moved to the SOUTH wall —
	# ring/label follow it. Probed LobbyDoorBlocker AABB: doorway center at
	# hall-local z=3.25 (wall plane). The marker sits 0.25 inside the lobby
	# at z=3.0 — the same interior-face offset the original had (old marker
	# z=-2.0 vs old wall plane -2.25); at the raw wall plane the label
	# embeds in the lintel and is invisible (verified via Xvfb shots). The
	# label rides a further 0.05 inside to clear the lintel face cleanly
	# (coplanar placement z-fights as a dark bar in captures).
	# The ring is pure ambience; the label shows NOW BOARDING once the vote
	# resolves.
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 2.5
	torus.material = ring_gold
	_ring.mesh = torus
	_ring.position = Vector3(-1, 0.06, 3.0)
	add_child(_ring)
	# Issue #201 slice 2, gate amendment: the BOARD HERE label is NOT
	# built in an Act 1 hub — under Jesse's no-clues rule there is no
	# boarding in Act 1, and "board" is the root of the forbidden
	# token family. The ring (pure ambience) stays; the legacy marker
	# is untouched (its writers null-guard _board_label).
	if not _linear_mode():
		var board_label := Label3D.new()
		board_label.text = "BOARD HERE"
		board_label.font_size = 96
		board_label.modulate = Color(1.0, 0.85, 0.40)
		board_label.outline_size = 12
		# resolves the lintel-face z-fighting the coplanar 3.0 placement showed
		# in Xvfb captures; visually identical in-game.
		board_label.position = Vector3(-1, 2.8, 2.95)
		board_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(board_label)
		_board_label = board_label

	# Heal pad (Phase 4): glowing green disc + REST sign + heal trigger.
	_cyl(self, 2.0, 2.0, 0.10, Vector3(-9.5, 0.06, 3.5), heal_glow)
	var rest_label := Label3D.new()
	rest_label.text = "REST"
	rest_label.font_size = 72
	rest_label.modulate = Color(0.45, 1.0, 0.55)
	rest_label.outline_size = 10
	rest_label.position = Vector3(-9.5, 2.4, 3.5)
	rest_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(rest_label)
	var pad := Area3D.new()
	pad.name = "HealPad"
	pad.collision_layer = 0
	pad.collision_mask = 1 # players (default layer 1)
	pad.position = Vector3(-9.5, 1.0, 3.5)
	var pcs := CollisionShape3D.new()
	var pcyl := CylinderShape3D.new()
	pcyl.radius = HEAL_RADIUS
	pcyl.height = 3.0
	pcs.shape = pcyl
	pad.add_child(pcs)
	add_child(pad)
	_heal_pad = pad

	# Vendor stall (Phase 4): E-interact opens the vendor panel.
	var stall := VendorStallScript.new()
	stall.name = "VendorStall"
	stall.position = Vector3(10, 0, -0.5)
	add_child(stall)

	# Relic Vault locker (issue #6 Phase 2): E-interact opens the vault panel.
	var vault := RelicVaultScript.new()
	vault.name = "RelicVault"
	vault.position = Vector3(-10, 0, -0.5)
	add_child(vault)

	# Departure board (Phase 2): faces the corridor entrance (+z).
	# Issue #201 (spec sections 2/5): in linear mode the board is
	# not built at all — no votes, no popup, no Vault row; the
	# hub door below replaces the row.
	if not _linear_mode():
		var board := DepartureBoardScript.new()
		board.name = "DepartureBoard"
		board.position = Vector3(7, 0, 4.2)
		add_child(board)

	# Issue #201 (spec section 5): Mason's Vault hub door — a
	# plain, unsigned door in the hub's north wall, present only
	# while the gate is open (visibility follows the verdict in
	# _process; the player's interact scan skips invisible nodes,
	# so a closed gate leaves no trace at all).
	if _linear_mode():
		var vdoor := VaultDoorScript.new()
		vdoor.name = "VaultDoor"
		vdoor.position = Vector3(-6, 0, -6.5)
		vdoor.visible = Dungeon.vault_gate_open
		add_child(vdoor)
		_vault_door = vdoor

	# Bounty board (issue #7 Phase 2): E-interact opens the bounty panel.
	var bounty_board := BountyBoardScript.new()
	bounty_board.name = "BountyBoard"
	bounty_board.position = Vector3(3.2, 0, 4.2)
	add_child(bounty_board)

	# NOW BOARDING sign (Phase 5): big gold label above the train.
	# Issue #63: wide enough for full destination names (no truncation).
	# Issue #201 (spec sections 4/7): not built in an Act 1 hub at all —
	# apply_dressing's write is null-guarded.
	if not _linear_mode():
		_boarding_sign = Label3D.new()
		_boarding_sign.font_size = 84
		_boarding_sign.width = 1200.0
		_boarding_sign.modulate = Color(1.0, 0.82, 0.35)
		_boarding_sign.outline_size = 12
		_boarding_sign.position = Vector3(-1, 3.9, -3.6)
		_boarding_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(_boarding_sign)

	# Per-theme dressing props (Phase 5); only the active set is visible.
	_build_dressing()


## Issue #201 (spec section 4): the Act 1 north strip — a plain bank
## of closed doors in an unadorned wall panel, where the tracks were.
## No signage, no text, no theme tint: three identical door pairs with
## a small indicator lamp each. Visual only, like the tracks were.
func _build_elevator_bank() -> void:
	var bank := Node3D.new()
	bank.name = "ElevatorBank"
	add_child(bank)
	var panel_mat := _mat(Color(0.44, 0.42, 0.46))
	var steel := _mat(Color(0.58, 0.59, 0.62))
	var dark := _mat(Color(0.22, 0.21, 0.24))
	var lamp_glow := _mat(Color(1.0, 0.75, 0.35), Color(1.0, 0.62, 0.22), 2.0)
	# The unadorned wall panel spanning the strip.
	_box(bank, Vector3(15.0, 3.4, 0.4), Vector3(-1.5, 1.7, -5.55), panel_mat)
	for dx in [-6.5, -1.5, 3.5]:
		# Frame + two closed slabs with a center seam.
		_box(bank, Vector3(2.7, 2.95, 0.14), Vector3(dx, 1.475, -5.32), dark)
		_box(bank, Vector3(1.16, 2.75, 0.10), Vector3(dx - 0.60, 1.375, -5.26), steel)
		_box(bank, Vector3(1.16, 2.75, 0.10), Vector3(dx + 0.60, 1.375, -5.26), steel)
		# Indicator lamp above the pair (a plain glowing block, no text).
		_box(bank, Vector3(0.18, 0.18, 0.06), Vector3(dx, 3.12, -5.28), lamp_glow)


## Dress the station for a destination theme: tint the lamps, show that
## theme's prop set, set the NOW BOARDING sign. Unknown ids fall back to
## village. Called on load (rotation default) and again when a vote resolves.
func apply_dressing(theme_id: String) -> void:
	# The apex arena (issue #5) and misty docks (issue #102) are board
	# destinations, not THEME_ORDER entries — allow them explicitly.
	# Unknown ids fall back to village.
	var tid := theme_id if (theme_id in Dungeon.THEME_ORDER or theme_id == "apex" or theme_id == "misty_docks") else "village"
	var tint: Color = DRESSING_LAMPS.get(tid, Color.WHITE)
	# The station lives in the annex hall: tint the annex shell's lamps.
	var lamp_list: Array = annex.lamps if annex != null else _lamps
	for lamp in lamp_list:
		(lamp as OmniLight3D).light_color = tint
	if _dressing != null:
		for child in _dressing.get_children():
			child.visible = (child.name == tid)
	if _boarding_sign != null:
		_boarding_sign.text = "NOW BOARDING: %s" % [Station.theme_display_name(tid).to_upper()]


## Prop set builder: one Node3D per theme under Dressing. All procedural,
## a few boxes each — no new textures. Hall coordinates (issue #2).
func _build_dressing() -> void:
	_dressing = Node3D.new()
	_dressing.name = "Dressing"
	add_child(_dressing)
	_dressing_props_embedded()


## Hall prop coordinates (issue #2): all props sit
## on the hall floor (y=0) along the south strip and corners, clear of the
## train (north strip), board, vendor, and heal pad.
func _dressing_props_embedded() -> void:
	var hay := _mat(Color(0.85, 0.70, 0.40))
	var leaf := _mat(Color(0.30, 0.55, 0.28))
	var trunk_m := _mat(Color(0.40, 0.28, 0.16))
	var torch_tip := _mat(Color(1.0, 0.55, 0.15), Color(1.0, 0.45, 0.10), 3.0)
	var chain_m := _mat(Color(0.18, 0.18, 0.20))
	var rock := _mat(Color(0.30, 0.28, 0.34))
	var crystal := _mat(Color(0.55, 0.30, 0.85), Color(0.45, 0.20, 0.80), 2.5)
	var crate_r := _mat(Color(0.75, 0.25, 0.20))
	var crate_b := _mat(Color(0.20, 0.40, 0.75))
	var crate_y := _mat(Color(0.85, 0.75, 0.25))
	var cart_m := _mat(Color(0.55, 0.58, 0.62))
	var banner_m := _mat(Color(0.70, 0.12, 0.12))
	var steel_dark := _mat(Color(0.25, 0.25, 0.28))

	# village: hay bales + a low-poly tree (SE corner / SW corner).
	var v := Node3D.new()
	v.name = "village"
	_dressing.add_child(v)
	_box(v, Vector3(0.9, 0.9, 0.9), Vector3(10.8, 0.45, 5.8), hay)
	_box(v, Vector3(0.9, 0.9, 0.9), Vector3(9.7, 0.45, 5.9), hay)
	_box(v, Vector3(0.9, 0.9, 0.9), Vector3(10.3, 1.32, 5.8), hay)
	_cyl(v, 0.18, 0.24, 1.6, Vector3(-11.0, 0.8, 5.8), trunk_m)
	_box(v, Vector3(1.6, 1.4, 1.6), Vector3(-11.0, 2.2, 5.8), leaf)

	# dungeon: torch posts flanking the south strip.
	var d := Node3D.new()
	d.name = "dungeon"
	_dressing.add_child(d)
	for tx in [11.0, -11.0]:
		_box(d, Vector3(0.14, 1.8, 0.14), Vector3(tx, 0.9, 5.8), trunk_m)
		_box(d, Vector3(0.30, 0.22, 0.30), Vector3(tx, 1.9, 5.8), torch_tip)

	# depths: crystal clusters on rock bases (both south corners).
	var de := Node3D.new()
	de.name = "depths"
	_dressing.add_child(de)
	for cx in [11.0, -11.0]:
		_box(de, Vector3(1.4, 0.5, 1.4), Vector3(cx, 0.25, 5.8), rock)
		var c1 := _box(de, Vector3(0.35, 1.1, 0.35), Vector3(cx - 0.2, 1.0, 5.8), crystal)
		c1.rotation.z = 0.18
		var c2 := _box(de, Vector3(0.30, 0.8, 0.30), Vector3(cx + 0.3, 0.85, 5.6), crystal)
		c2.rotation.z = -0.22

	# supermarket: product crates + a shopping cart.
	var s := Node3D.new()
	s.name = "supermarket"
	_dressing.add_child(s)
	_box(s, Vector3(1.0, 1.0, 1.0), Vector3(11.0, 0.5, 5.8), crate_r)
	_box(s, Vector3(1.0, 1.0, 1.0), Vector3(9.8, 0.5, 5.9), crate_b)
	_box(s, Vector3(1.0, 1.0, 1.0), Vector3(10.5, 1.5, 5.8), crate_y)
	_box(s, Vector3(1.2, 0.7, 0.8), Vector3(-10.5, 0.55, 5.5), cart_m)
	for wx in [-10.85, -10.15]:
		for wz in [5.25, 5.75]:
			var wheel := _cyl(s, 0.12, 0.12, 0.08, Vector3(wx, 0.12, wz), chain_m)
			wheel.rotation_degrees.x = 90.0
	var handle := _box(s, Vector3(0.08, 0.08, 0.9), Vector3(-9.85, 1.0, 5.5), chain_m)
	handle.rotation_degrees.z = -25.0

	# warlord: war banners + a weapon rack.
	var w := Node3D.new()
	w.name = "warlord"
	_dressing.add_child(w)
	for bx in [11.3, -11.3]:
		_box(w, Vector3(0.14, 2.8, 0.14), Vector3(bx, 1.4, 5.5), trunk_m)
		_box(w, Vector3(0.80, 1.5, 0.06), Vector3(bx, 1.9, 5.5), banner_m)
	_box(w, Vector3(0.14, 1.4, 0.14), Vector3(4.5, 0.7, -6.3), trunk_m)
	_box(w, Vector3(0.14, 1.4, 0.14), Vector3(5.5, 0.7, -6.3), trunk_m)
	_box(w, Vector3(1.3, 0.12, 0.12), Vector3(5.0, 1.3, -6.3), trunk_m)
	var ews1 := _box(w, Vector3(0.10, 1.2, 0.10), Vector3(5.0, 0.75, -6.25), steel_dark)
	ews1.rotation_degrees.z = 28.0
	var ews2 := _box(w, Vector3(0.10, 1.2, 0.10), Vector3(5.0, 0.75, -6.25), steel_dark)
	ews2.rotation_degrees.z = -28.0

	# apex: crimson war banners + braziers flanking the south strip.
	var a := Node3D.new()
	a.name = "apex"
	_dressing.add_child(a)
	var ember := _mat(Color(1.0, 0.35, 0.1), Color(1.0, 0.3, 0.08), 2.5)
	for bx in [11.3, -11.3]:
		_box(a, Vector3(0.14, 2.8, 0.14), Vector3(bx, 1.4, 5.5), steel_dark)
		_box(a, Vector3(0.80, 1.5, 0.06), Vector3(bx, 1.9, 5.5), banner_m)
		# Brazier: iron bowl on a stand with an ember glow.
		_cyl(a, 0.35, 0.25, 0.25, Vector3(bx * 0.85, 0.9, 5.6), steel_dark)
		_box(a, Vector3(0.12, 0.9, 0.12), Vector3(bx * 0.85, 0.45, 5.6), steel_dark)
		_box(a, Vector3(0.30, 0.18, 0.30), Vector3(bx * 0.85, 1.08, 5.6), ember)

	# misty_docks (issue #102): dock lantern posts + crates + a rope coil.
	var md := Node3D.new()
	md.name = "misty_docks"
	_dressing.add_child(md)
	var lamp_glow := _mat(Color(1.0, 0.75, 0.35), Color(1.0, 0.6, 0.25), 2.5)
	for lx in [11.0, -11.0]:
		_box(md, Vector3(0.14, 2.2, 0.14), Vector3(lx, 1.1, 5.8), trunk_m)
		_box(md, Vector3(0.5, 0.08, 0.08), Vector3(lx, 2.2, 5.8), trunk_m)
		_box(md, Vector3(0.28, 0.34, 0.28), Vector3(lx + 0.22, 1.95, 5.8), lamp_glow)
	_box(md, Vector3(1.0, 1.0, 1.0), Vector3(9.8, 0.5, 5.9), crate_b)
	_box(md, Vector3(1.0, 1.0, 1.0), Vector3(-9.8, 0.5, 5.9), crate_r)
	_cyl(md, 0.45, 0.35, 0.18, Vector3(10.6, 0.18, 5.2), chain_m)


## Save the multiplayer run from the station (host only).
## Mirrors Dungeon.save_multiplayer_run but synchronous — the station has
## all player nodes locally, so no RPC round-trip is needed.
func save_multiplayer_run(theme_id: String, level_number: int, level_seed: int) -> void:
	if not multiplayer.is_server():
		return
	# Issue #70: LAN has no saves.
	if NetworkManager.transport == NetworkManager.Transport.LAN:
		return
	var roster: Array = []
	var my_sid := SteamManager.steam_id if SteamManager.initialized else multiplayer.get_unique_id()
	for n in get_tree().get_nodes_in_group("players"):
		var sid := int(n.get("steam_id")) if n.get("steam_id") != null else my_sid
		roster.append({
			"steam_id": sid,
			"player_name": NetworkManager.member_name(sid),
			"class_id": str(n.get("class_id")),
			"player_state": n.get_state(),
			"rts_faction": -1,
			"is_host": sid == my_sid,
		})
	# Issue #111 PF Phase 2: loaded-dict-first (the _save_base pattern,
	# mirroring Dungeon.save_multiplayer_run) — unknown top-level keys
	# survive this write-back; roster entries gain the previous entry's
	# unknown keys by steam_id (fresh fields win).
	# Issue #112: carry absent roster members forward by Steam64 before
	# the key merge, matching the dungeon path's post-M-4 behavior.
	# Carried entries are already complete, so the merge is a no-op for
	# them and their saved entries survive verbatim.
	var base: Dictionary = SaveManager.load_run(SaveManager.MODE_MP,
		NetworkManager.active_run_slot).duplicate(true)
	roster = Dungeon.carry_forward_roster(roster, base.get("roster", []))
	var prev_by_sid := {}
	for e in base.get("roster", []):
		prev_by_sid[int((e as Dictionary).get("steam_id", 0))] = e
	for entry in roster:
		var prev_e: Dictionary = prev_by_sid.get(int(entry.get("steam_id", 0)), {})
		for k in prev_e.keys():
			if not entry.has(k):
				entry[k] = prev_e[k]
	base["theme_id"] = theme_id
	base["level_number"] = level_number
	base["seed"] = level_seed
	base["is_multiplayer"] = true
	base["at_station"] = true
	base["host_difficulty"] = NetworkManager.host_difficulty
	base["host_loot_mult"] = NetworkManager.host_loot_mult
	var lobby: Dictionary = (base.get("lobby", {}) as Dictionary).duplicate(true)
	lobby["max_players"] = NetworkManager.MAX_PLAYERS
	lobby["lobby_name"] = ("%s's Dungeon" % SteamManager.persona_name) \
		if SteamManager.initialized else "Dungeon"
	# Issue #110 (M-5) parity with the dungeon producer: persist the
	# lobby visibility so station saves don't drop it.
	lobby["visibility"] = NetworkManager.lobby_visibility
	base["lobby"] = lobby
	base["roster"] = roster
	SaveManager.save_run(base, SaveManager.MODE_MP, NetworkManager.active_run_slot)
