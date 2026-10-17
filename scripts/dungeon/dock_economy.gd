class_name DockEconomy
extends RefCounted
## Issue #102 Phase 4: server-authoritative farm-cash economy ledgers.
##
## Farm cash is an INVENTORY ITEM (Jesse's decision) — no currency plumbing.
## These static ledgers mirror what the server granted/spent per peer so
## vendor transactions validate against server truth; each client's
## inventory stack is the display mirror (mutated via rpc to the owning
## peer, mirroring the Phase 3 FarmPlot seed-ledger pattern). Anti-cheat is
## light (co-op game): the sell UI only lists what the client actually
## holds, so ledger over-count from client-side disposal/use can't be
## spent. Ledgers clear on disconnect and on death (death wipes the
## inventory mirror, so phantom balances must go too).
##
## Trust model: only the server mutates these. All entry points assume the
## caller already checked multiplayer.is_server().

## --- Economy numbers: ALL Jesse's calls (flagged in the Phase 4 report) ---
const FISH_SELL := {"fish_minnow": 2, "fish_riverbass": 5, "fish_glimmerfin": 12}
const CROP_SELL := {"crop_sunroot": 3}
const PRICE_SEED := 2
const PRICE_BAIT := 3
const PRICE_FERTILIZER := 4
const PRICE_SALVE := 5
const PRICE_DRAUGHT := 8
const PRICE_CURRENT := 8
const PRICE_BULWARK := 8
## Issue #104 Phase 3: the fishing rod is GEAR (permanent stock, bought
## with farm cash, kept across levels like any equipment). Price ruled
## FREE by Jesse 2026-10-17 (issue #161; supersedes the 9 farm cash
## settlement of 2026-10-15): still a merchant acquisition, at 0.
const PRICE_ROD := 0
const ROD_ITEM := "fishing_rod"
## Bait odds shift: added to both rare thresholds in the Phase 2 catch roll.
const BAIT_RARE_SHIFT := 0.15

const CASH_ITEM := "farm_cash"
const BAIT_ITEM := "bait_lure"
const FERTILIZER_ITEM := "fertilizer"
const SEED_ITEM := "seed_packet"
const SALVE_ITEM := "dock_salve"
const DRAUGHT_ITEM := "harbor_draught"
const CURRENT_ITEM := "swift_current"
const BULWARK_ITEM := "barnacle_bulwark"

static var _cash: Dictionary = {} ## peer id -> farm cash balance
static var _stock: Dictionary = {} ## peer id -> {item_id -> count} (server-granted dock goods)


## Farm-cash value of a sellable dock good; 0 = the merchant won't buy it.
## Mirrors the sell_value fields on the item .tres files (single source of
## truth for the vendor; the tres values are the display mirror).
static func sell_value_for(item_id: String) -> int:
	if FISH_SELL.has(item_id):
		return int(FISH_SELL[item_id])
	if CROP_SELL.has(item_id):
		return int(CROP_SELL[item_id])
	return 0


static func reset_peer(peer: int) -> void:
	_cash.erase(peer)
	_stock.erase(peer)


static func cash_balance(peer: int) -> int:
	return int(_cash.get(peer, 0))


static func grant_cash(peer: int, n: int) -> void:
	_cash[peer] = cash_balance(peer) + n


static func spend_cash(peer: int, n: int) -> bool:
	var bal := cash_balance(peer)
	if bal < n:
		return false
	_cash[peer] = bal - n
	return true


static func grant_stock(peer: int, item_id: String, n: int = 1) -> void:
	var goods: Dictionary = _stock.get(peer, {})
	goods[item_id] = int(goods.get(item_id, 0)) + n
	_stock[peer] = goods


## Issue #160: clamped debits — the drop-side inverse of the grants.
## A mirror never goes below zero: legacy drift (a bag that shrank
## while its mirror was stale) debits to the floor, not into debt.
static func debit_cash(peer: int, n: int) -> void:
	_cash[peer] = maxi(0, cash_balance(peer) - n)


static func debit_stock(peer: int, item_id: String, n: int = 1) -> void:
	var goods: Dictionary = _stock.get(peer, {})
	goods[item_id] = maxi(0, int(goods.get(item_id, 0)) - n)
	_stock[peer] = goods


## Issue #160: derive-at-restore SETS both mirrors from the bag (the
## durable truth) in one call — assignment, never accumulation, so a
## restore can neither double nor carry a stale balance forward.
static func set_mirrors(peer: int, cash: int, stock: Dictionary) -> void:
	_cash[peer] = cash
	_stock[peer] = stock.duplicate()


static func stock_count(peer: int, item_id: String) -> int:
	var goods: Dictionary = _stock.get(peer, {})
	return int(goods.get(item_id, 0))


static func spend_stock(peer: int, item_id: String, n: int = 1) -> bool:
	var have := stock_count(peer, item_id)
	if have < n:
		return false
	var goods: Dictionary = _stock.get(peer, {})
	goods[item_id] = have - n
	_stock[peer] = goods
	return true


## TEST SEAM: wipe all ledger state between sim runs.
static func debug_reset() -> void:
	_cash.clear()
	_stock.clear()
