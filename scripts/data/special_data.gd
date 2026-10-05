class_name SpecialData
extends Resource
## Data-driven special (Relic Vault, issue #6): condition-gated bonus
## rewards that sit OUTSIDE the level-100 skill curve and affinity
## families — never skill seven. Earned into the account-level profile
## vault (vault_specials); exactly one may be equipped per run.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var unlock_hint: String = ""
@export var effect_summary: String = ""
@export var effect_params: Dictionary = {}

## All special ids, in vault display order.
const SPECIAL_IDS: Array[String] = [
	"holy_light",
	"iron_resolve",
	"greed_charm",
	"apex_boar_hide",
	"apex_horror_eye",
	"apex_warden_sigil",
]

## Earn thresholds.
const IRON_RESOLVE_STREAK := 3 ## consecutive deathless level clears
const GREED_CHARM_GOAL := 500 ## single-visit checkout earnings ($)
const AURA_EARN_REQ := 20.0 ## aura points that earn Holy Light

## Apex boss mob id -> the special its kill earns.
const APEX_BOSS_SPECIALS := {
	"apex_boar": "apex_boar_hide",
	"apex_horror": "apex_horror_eye",
	"apex_warden": "apex_warden_sigil",
}

static var _cache: Dictionary = {}


## All six specials, loaded once.
static func all() -> Array:
	if _cache.is_empty():
		for sid in SPECIAL_IDS:
			var d: SpecialData = load("res://data/specials/special_%s.tres" % sid)
			if d != null:
				_cache[sid] = d
			else:
				push_warning("[SpecialData] Missing special tres: %s" % sid)
	var out: Array = []
	for sid in SPECIAL_IDS:
		if _cache.has(sid):
			out.append(_cache[sid])
	return out


## The special's data, or null.
static func get_special(special_id: String) -> SpecialData:
	all()
	return _cache.get(special_id)


## The special id an apex boss kill earns, or "" for non-apex mobs.
static func apex_special_for_boss(boss_id: String) -> String:
	return str(APEX_BOSS_SPECIALS.get(boss_id, ""))


## Apex boss mob id -> trophy display name (Collection tab, issue #5).
static func trophy_name_for_apex(apex_mob_id: String) -> String:
	var sp := get_special(apex_special_for_boss(apex_mob_id))
	if sp != null:
		return sp.display_name
	match apex_mob_id:
		"apex_boar":
			return "Apex Bristleback"
		"apex_warden":
			return "Apex Warden"
		"apex_horror":
			return "Apex Maw of the Deep"
	return apex_mob_id


## Apex boss mob id -> relic ItemData id (physical 100% drop, issue #5).
static func relic_item_for_apex(apex_mob_id: String) -> String:
	match apex_mob_id:
		"apex_boar":
			return "relic_apex_boar_hide"
		"apex_warden":
			return "relic_apex_warden_sigil"
		"apex_horror":
			return "relic_apex_horror_eye"
	return ""


## Runtime SaveManager lookup (autoload refs don't resolve at compile time
## in -s script mode; this keeps the API working headless and in-game).
static func _save_manager() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null:
		return loop.root.get_node_or_null("SaveManager")
	return null


## Runtime NetworkManager lookup (same compile-time autoload issue).
static func _network_manager() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null:
		return loop.root.get_node_or_null("NetworkManager")
	return null


## True when the id is in the account-level vault.
static func is_earned(special_id: String) -> bool:
	var sm := _save_manager()
	return sm != null and special_id in sm.get_vault_specials()


## Earn a special into the account vault. Idempotent: returns true only
## when newly earned. Writes through the profile (Steam Cloud included).
static func earn(special_id: String) -> bool:
	var data := get_special(special_id)
	if data == null:
		push_warning("[SpecialData] earn() unknown special: %s" % special_id)
		return false
	var sm := _save_manager()
	if sm == null:
		return false
	var earned: Array = sm.get_vault_specials()
	if special_id in earned:
		return false
	earned.append(special_id)
	sm.set_vault_specials(earned)
	return true


## Server-side earn check -> grant on the earning player's own instance,
## so the write lands in THEIR account profile (not the host's) with the
## "Special earned" toast. Safe to call from the server: the authority
## guard drops it everywhere except the owner's peer.
static func earn_for(player: Node, special_id: String) -> void:
	if player == null:
		return
	player.rpc_id(int(player.get_multiplayer_authority()), "rpc_earn_special", special_id)


## Equip a special for the run. Exactly one equipped max: equipping
## replaces. Only earned specials can be equipped. Syncs to the server
## copy so server-side effects (checkout sale) see it in multiplayer.
static func equip(player: Node, special_id: String) -> bool:
	if player == null or not is_earned(special_id):
		return false
	player.set("equipped_special", special_id)
	player.call("_apply_equipped_special")
	if not player.get_tree().get_multiplayer().is_server():
		var dungeon := player.get_tree().get_first_node_in_group("dungeon")
		var nm := _network_manager()
		if dungeon != null and nm != null:
			dungeon.rpc_id(int(nm.get("server_id")), "sync_equipped_special",
				int(player.get_multiplayer_authority()), special_id)
	return true


## Clear the run's equipped special.
static func unequip(player: Node) -> void:
	if player == null:
		return
	player.set("equipped_special", "")
	player.call("_apply_equipped_special")
