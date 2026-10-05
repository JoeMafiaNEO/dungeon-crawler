extends Node
## SaveManager: persists player progress, meta unlocks, and settings.
## Two clean layers (issue #4):
##  (1) Account profile = meta that follows the player:
##      user://profile_<account>.cfg (Steam account id, or "local" when
##      headless/offline). Holds achievements, unlocked_items,
##      cipher_fragments, architect_unlocked, lifetime stats.
##  (2) Run slots: user://runs/solo_0..2.cfg and user://runs/mp_0..2.cfg.
##      Each slot file stores one run dict + save_version + saved_at.
##      Slot paths derive from (mode, slot) ONLY — never from class_id, so
##      switching class can never clobber another slot.
## Steam Cloud (GodotSteam RemoteStorage): write-through on every save,
## read-through at boot. Every cloud call is guarded by _cloud_available()
## (SteamManager.initialized); headless/offline is local-only, zero errors.
## Last-write-wins, no conflict resolution.

const SETTINGS_PATH := "user://settings.cfg"

# Run-slot modes for the slot API.
const MODE_SOLO := "solo"
const MODE_MP := "mp"
const MAX_SLOTS := 3
const RUNS_DIR := "user://runs"
## Save format version. Continue refuses saves with a mismatched version.
const SAVE_VERSION := 1

# Meta progression: unlocks that broaden (not flatten).
# - unlocked_items: Array[String] of item IDs added to drop pool
# - unlocked_classes: Array[String] (future class variants)
# - total_runs: int
# - total_kills: int
# - deepest_cycle: int
# - total_cash_earned: int (supermarket)

var _profile := ConfigFile.new()
var _profile_account := ""
var _settings := ConfigFile.new()
## Observability hook: cloud writes attempted (guard passed). Tests use this
## to prove no cloud call fires without Steam.
var _cloud_write_count := 0


func _ready() -> void:
	load_game()
	load_settings()


# --- Account profile ---

## Account resolution: Steam id when Steam is up, "local" headless/offline.
## SteamManager is first in autoload order and inits synchronously, so this
## is final by the time _ready runs. Everything works offline: local
## profile, local-only writes, zero errors.
func _resolve_account() -> String:
	if SteamManager.initialized:
		return str(SteamManager.steam_id)
	return "local"


func _profile_path_for(account: String) -> String:
	return "user://profile_%s.cfg" % account


## Current profile path (test hook).
func _profile_path() -> String:
	return _profile_path_for(_resolve_account())


func _seed_profile_defaults() -> void:
	_profile.set_value("meta", "unlocked_items", [])
	_profile.set_value("meta", "total_runs", 0)
	_profile.set_value("meta", "total_kills", 0)
	_profile.set_value("meta", "deepest_cycle", 0)
	_profile.set_value("meta", "total_cash_earned", 0)
	_profile.set_value("meta", "unlocked_achievements", [])
	_profile.set_value("meta", "cipher_fragments", [])
	_profile.set_value("meta", "architect_unlocked", false)


func load_game() -> void:
	_profile_account = _resolve_account()
	_cloud_sync_down()
	var path := _profile_path_for(_profile_account)
	if FileAccess.file_exists(path):
		_profile.load(path)
	else:
		# Fresh profile with defaults (kept in memory until first mutation).
		_seed_profile_defaults()


func save_game() -> void:
	var account := _resolve_account()
	if _profile_account == "":
		# First touch on a standalone instance (tests): the in-memory
		# mutations are the source of truth; don't load over them.
		_profile_account = account
	elif account != _profile_account:
		# Account changed mid-session (Steam came up late): switch profiles
		# instead of writing one account's meta into another's file.
		_profile_account = account
		_profile.load(_profile_path_for(account))
	_profile.set_value("meta", "saved_at", Time.get_datetime_string_from_system())
	var path := _profile_path_for(_profile_account)
	_profile.save(path)
	_cloud_write(_relative(path), FileAccess.get_file_as_bytes(path))


func load_settings() -> void:
	_settings.load(SETTINGS_PATH)


func save_settings() -> void:
	_settings.save(SETTINGS_PATH)


# --- Steam Cloud sync ---

## Every cloud call funnels through here. Headless/offline: no-op.
func _cloud_available() -> bool:
	return SteamManager.initialized and Engine.has_singleton("Steam")


## user://-relative name for the cloud (RemoteStorage keys are relative).
func _relative(path: String) -> String:
	if path.begins_with("user://"):
		return path.substr("user://".length())
	return path


## Write-through: every profile/slot save also lands in the cloud.
func _cloud_write(rel_name: String, data: PackedByteArray) -> void:
	if not _cloud_available():
		return
	_cloud_write_count += 1
	Steam.fileWrite(rel_name, data)


## Boot read-through: if the cloud copy exists and its saved_at is newer
## than local (or local is missing), copy it down. Last-write-wins.
## A zero-length cloud copy is a clear tombstone: never restored.
func _cloud_sync_down() -> void:
	if not _cloud_available():
		return
	_cloud_fetch(_profile_path_for(_profile_account))
	for mode in [MODE_SOLO, MODE_MP]:
		for slot in range(MAX_SLOTS):
			_cloud_fetch(_slot_path(mode, slot))


func _cloud_fetch(local_path: String) -> void:
	if local_path == "":
		return
	var rel := _relative(local_path)
	if not Steam.fileExists(rel):
		return
	var size := int(Steam.getFileSize(rel))
	if size <= 0:
		return  # clear tombstone (or empty file): don't resurrect
	# fileRead returns {"ret": bool, "buf": PackedByteArray}.
	var result: Dictionary = Steam.fileRead(rel, size)
	if not bool(result.get("ret", false)):
		return
	var bytes: PackedByteArray = result.get("buf", PackedByteArray())
	if bytes.is_empty():
		return
	var tmp := "user://.cloud_fetch.tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	var cloud_cfg := ConfigFile.new()
	if cloud_cfg.load(tmp) != OK:
		DirAccess.remove_absolute(tmp)
		return
	DirAccess.remove_absolute(tmp)
	var cloud_at := _saved_at_of(cloud_cfg, local_path)
	var local_at := ""
	if FileAccess.file_exists(local_path):
		var local_cfg := ConfigFile.new()
		if local_cfg.load(local_path) == OK:
			local_at = _saved_at_of(local_cfg, local_path)
	if local_at == "" or cloud_at > local_at:
		var out := FileAccess.open(local_path, FileAccess.WRITE)
		if out != null:
			out.store_buffer(bytes)
			out.close()


func _saved_at_of(cfg: ConfigFile, local_path: String) -> String:
	if local_path.begins_with(RUNS_DIR):
		var data = cfg.get_value("run", "data", {})
		return str(data.get("saved_at", "")) if data is Dictionary else ""
	return str(cfg.get_value("meta", "saved_at", ""))


# --- Meta progression (lives on the account profile) ---

func get_unlocked_items() -> Array:
	return _profile.get_value("meta", "unlocked_items", [])


## All unlocked achievement IDs.
func get_unlocked_achievements() -> Array:
	return _profile.get_value("meta", "unlocked_achievements", [])


func unlock_item(item_id: String) -> bool:
	var unlocked: Array = get_unlocked_items()
	if item_id in unlocked:
		return false
	unlocked.append(item_id)
	_profile.set_value("meta", "unlocked_items", unlocked)
	save_game()
	return true


func is_item_unlocked(item_id: String) -> bool:
	return item_id in get_unlocked_items()


func add_run() -> void:
	_profile.set_value("meta", "total_runs", get_total_runs() + 1)
	save_game()


func get_total_runs() -> int:
	return int(_profile.get_value("meta", "total_runs", 0))


func add_kills(count: int) -> void:
	_profile.set_value("meta", "total_kills", get_total_kills() + count)
	save_game()


func get_total_kills() -> int:
	return int(_profile.get_value("meta", "total_kills", 0))


func set_deepest_cycle(cycle: int) -> void:
	if cycle > get_deepest_cycle():
		_profile.set_value("meta", "deepest_cycle", cycle)
		save_game()


func get_deepest_cycle() -> int:
	return int(_profile.get_value("meta", "deepest_cycle", 0))


func add_cash_earned(amount: int) -> void:
	_profile.set_value("meta", "total_cash_earned", get_total_cash_earned() + amount)
	save_game()


func get_total_cash_earned() -> int:
	return int(_profile.get_value("meta", "total_cash_earned", 0))


# --- Achievements & Meta Unlocks ---
# Broaden (new items/builds), not flatten (no raw stats).

const ACHIEVEMENTS := [
	{"id": "kill_100", "name": "Slayer", "desc": "Kill 100 mobs", "item": "void_blade", "check": "kills", "threshold": 100},
	{"id": "cycle_2", "name": "Explorer", "desc": "Reach Cycle 2", "item": "phoenix_feather", "check": "cycle", "threshold": 2},
	{"id": "cash_1000", "name": "Entrepreneur", "desc": "Earn $1000 at MegaMart", "item": "storm_caller", "check": "cash", "threshold": 1000},
	{"id": "drafted", "name": "Drafted", "desc": "Unlock the secret Architect class", "item": "", "check": "manual", "threshold": 1},
]


func check_achievements() -> Array:
	# Returns list of newly unlocked achievement IDs.
	var unlocked := []
	var done: Array = _profile.get_value("meta", "unlocked_achievements", [])
	for a in ACHIEVEMENTS:
		if a["id"] in done:
			continue
		var progress := 0
		match a["check"]:
			"kills":
				progress = get_total_kills()
			"cycle":
				progress = get_deepest_cycle()
			"cash":
				progress = get_total_cash_earned()
			"manual":
				# Never auto-fires; granted via unlock_achievement().
				progress = 0
		if progress >= a["threshold"]:
			done.append(a["id"])
			unlocked.append(a["id"])
			if str(a["item"]) != "":
				unlock_item(a["item"])
	if not unlocked.is_empty():
		_profile.set_value("meta", "unlocked_achievements", done)
		save_game()
	return unlocked


## Manually grant an achievement (for "manual"-check achievements).
## Returns true if newly unlocked.
func unlock_achievement(ach_id: String) -> bool:
	var done: Array = _profile.get_value("meta", "unlocked_achievements", [])
	if ach_id in done:
		return false
	done.append(ach_id)
	for a in ACHIEVEMENTS:
		if a["id"] == ach_id and str(a.get("item", "")) != "":
			unlock_item(a["item"])
	_profile.set_value("meta", "unlocked_achievements", done)
	save_game()
	return true


func get_achievement_progress(ach_id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a["id"] == ach_id:
			var progress := 0
			match a["check"]:
				"kills":
					progress = get_total_kills()
				"cycle":
					progress = get_deepest_cycle()
				"cash":
					progress = get_total_cash_earned()
				"manual":
					progress = 1 if a["id"] in _profile.get_value("meta", "unlocked_achievements", []) else 0
			return {"name": a["name"], "desc": a["desc"], "progress": progress, "threshold": a["threshold"], "done": progress >= a["threshold"]}
	return {}


# --- Architect Cipher (meta) ---
# Fragments: Array[int] of collected poem indices 0..7, permanent like achievements.

func get_cipher_fragments() -> Array:
	return _profile.get_value("meta", "cipher_fragments", [])


## Grant a fragment. Returns true if newly added.
func add_cipher_fragment(idx: int) -> bool:
	var frags: Array = get_cipher_fragments()
	if idx in frags:
		return false
	frags.append(idx)
	_profile.set_value("meta", "cipher_fragments", frags)
	save_game()
	return true


func is_architect_unlocked() -> bool:
	return bool(_profile.get_value("meta", "architect_unlocked", false))


## Permanently unlock the Architect class. Returns true if newly unlocked.
func unlock_architect() -> bool:
	if is_architect_unlocked():
		return false
	_profile.set_value("meta", "architect_unlocked", true)
	save_game()
	return true


# --- Settings ---
func get_setting(section: String, key: String, default = null):
	return _settings.get_value(section, key, default)


func set_setting(section: String, key: String, value) -> void:
	_settings.set_value(section, key, value)
	save_settings()


## Affinity family collections (issue #4 Phase 2): permanent per-class
## account meta — {family_id: {"traits": [ids], "signature": bool}}.
## Persisted on every run save and level transition, loaded on player spawn.
## In MP each client writes only their OWN local profile (never the host's,
## never a peer's): collections never cross peers.
func save_collections(class_id: String, collection: Dictionary) -> void:
	_profile.set_value("collections", class_id, (collection as Dictionary).duplicate(true))
	save_game()


func load_collections(class_id: String) -> Dictionary:
	var c: Variant = _profile.get_value("collections", class_id, {})
	if c is Dictionary:
		return (c as Dictionary).duplicate(true)
	return {}


## Union of two collections: every earned trait kept, signature is OR.
## Used on spawn so a profile copy and a run-state copy can never downgrade
## each other regardless of which was written last.
static func merge_collections(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := (a as Dictionary).duplicate(true)
	for fid in b:
		if not (b[fid] is Dictionary):
			continue
		if not out.has(fid):
			out[fid] = (b[fid] as Dictionary).duplicate(true)
			continue
		var oa: Dictionary = out[fid]
		var ob: Dictionary = b[fid]
		var traits: Array = oa.get("traits", [])
		for t in ob.get("traits", []):
			if not traits.has(t):
				traits.append(t)
		oa["traits"] = traits
		oa["signature"] = bool(oa.get("signature", false)) or bool(ob.get("signature", false))
	return out


## Persist collections found in a run dict into the LOCAL profile.
## Solo: the run's own player_state. MP: ONLY the host's roster entry —
## clients persist their own collections on their own machines (see
## board_train_interior), so the host never writes a peer's unlocks.
## Empty collections never clobber earned ones.
func _persist_run_collections(run: Dictionary, mode: String) -> void:
	if mode == MODE_SOLO:
		var ps: Dictionary = run.get("player_state", {})
		_persist_one_collection(str(run.get("class_id", "")), ps)
		return
	for entry in run.get("roster", []):
		if entry is Dictionary and bool(entry.get("is_host", false)):
			_persist_one_collection(str(entry.get("class_id", "")),
				entry.get("player_state", {}))
			break


func _persist_one_collection(class_id: String, player_state: Variant) -> void:
	if class_id.is_empty() or not (player_state is Dictionary):
		return
	var coll: Variant = (player_state as Dictionary).get("family_collection", {})
	if coll is Dictionary and not (coll as Dictionary).is_empty():
		save_collections(class_id, coll)


# --- Run slots ---
# user://runs/solo_0..2.cfg and user://runs/mp_0..2.cfg. Each slot file
# stores one run dict + save_version + saved_at. Auto-saved on every level
# transition (annex departure); cleared on death.

## Slot file path. Slot is an int 0..2; anything else is rejected ("").
func _slot_path(mode: String, slot: int) -> String:
	if mode != MODE_SOLO and mode != MODE_MP:
		push_error("[SaveManager] Bad slot mode: %s" % mode)
		return ""
	if slot < 0 or slot >= MAX_SLOTS:
		push_error("[SaveManager] Slot out of range: %d" % slot)
		return ""
	return "%s/%s_%d.cfg" % [RUNS_DIR, mode, slot]


## Save a run into a slot. Stamps saved_at + save_version and the mode's
## is_multiplayer flag. Atomic write (.tmp rename) + cloud write-through.
## Returns false when the slot is invalid.
func save_run(run: Dictionary, mode: String, slot: int) -> bool:
	var path := _slot_path(mode, slot)
	if path == "":
		return false
	DirAccess.make_dir_recursive_absolute(RUNS_DIR)
	var cfg := ConfigFile.new()
	var data := run.duplicate(true)
	data["saved_at"] = Time.get_datetime_string_from_system()
	data["save_version"] = SAVE_VERSION
	data["is_multiplayer"] = (mode == MODE_MP)
	cfg.set_value("run", "data", data)
	# Atomic write: save to temp, then rename.
	var tmp_path := path + ".tmp"
	if cfg.save(tmp_path) != OK:
		return false
	DirAccess.rename_absolute(tmp_path, path)
	# Phase 2: collections ride along on every run save (host-only in MP).
	_persist_run_collections(run, mode)
	_cloud_write(_relative(path), FileAccess.get_file_as_bytes(path))
	return true


## Load a run from a slot. {} when empty or the slot is invalid.
func load_run(mode: String, slot: int) -> Dictionary:
	var path := _slot_path(mode, slot)
	if path == "":
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var data = cfg.get_value("run", "data", {})
	return data if data is Dictionary else {}


func has_run(mode: String, slot: int) -> bool:
	return not load_run(mode, slot).is_empty()


## Death clears only that slot. The cloud copy gets an empty tombstone so
## boot read-through can't resurrect a cleared run.
func clear_run(mode: String, slot: int) -> void:
	var path := _slot_path(mode, slot)
	if path == "":
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_cloud_write(_relative(path), PackedByteArray())


## All occupied slots for a mode: [{slot, run}], ordered by slot.
func list_runs(mode: String) -> Array:
	var out: Array = []
	if mode != MODE_SOLO and mode != MODE_MP:
		return out
	for slot in range(MAX_SLOTS):
		var run := load_run(mode, slot)
		if not run.is_empty():
			out.append({"slot": slot, "run": run})
	return out


## True if the slot's saved run matches the current format.
func is_save_compatible(mode: String, slot: int) -> bool:
	var run := load_run(mode, slot)
	if run.is_empty():
		return false
	return int(run.get("save_version", 0)) == SAVE_VERSION


## Human-readable one-line summary for a run dict. Slot context ("Slot 2")
## is added by the UI.
func run_summary(run: Dictionary) -> String:
	if run.is_empty():
		return ""
	var theme_id := str(run.get("theme_id", "village"))
	var theme_name := theme_id.capitalize()
	# Friendly theme names.
	match theme_id:
		"village":
			theme_name = "Village Outskirts"
		"dungeon":
			theme_name = "The Dungeon"
		"depths":
			theme_name = "The Depths"
		"supermarket":
			theme_name = "MegaMart Supermarket"
		"warlord":
			theme_name = "Warlord's Domain"
	if bool(run.get("is_multiplayer", false)):
		var roster: Array = run.get("roster", [])
		var names: Array = []
		for entry in roster:
			var ps2: Dictionary = entry.get("player_state", {})
			names.append("%s %d" % [str(entry.get("class_id", "?")).capitalize(), int(ps2.get("level", 1))])
		return "%d players (%s) · %s · Level %d" % [roster.size(), ", ".join(names), theme_name, int(run.get("level_number", 1))]
	var ps: Dictionary = run.get("player_state", {})
	var lvl := int(ps.get("level", 1))
	var class_id := str(run.get("class_id", "warrior")).capitalize()
	return "Lv %d %s · %s · Level %d" % [lvl, class_id, theme_name, int(run.get("level_number", 1))]
