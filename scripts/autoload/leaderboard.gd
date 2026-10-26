extends Node
## Leaderboard: Steam leaderboards (issue #9 Phase 1; the
## registry generalization is issue #209).
## Boards are created via findOrCreateLeaderboard:
##   daily_depth — sort descending, score = deepest cycle * 100000 + level
##   daily_speed — sort ascending,  score = Cycle-1 clear time in seconds
##   bld_<wlx>_<wlz> — per-building clear-time boards (issue
##   #209): sort ascending, score = clear seconds, created on
##   a building's first posted clear and named by its
##   anchor-lot key ("bld_" + key.replace(",", "_")).
## Every Steam call is guarded by SteamManager.initialized: offline or
## no-Steam skips silently and the local best (DailyRun.record_attempt)
## keeps working. Uploads use keep_best so a player's top score stands.
##
## GodotSteam 4.22.1 API (verified against the vendored GDExtension):
##   findOrCreateLeaderboard(name, sort, display) -> leaderboard_find_result(handle, found)
##   uploadLeaderboardScore(score, keep_best, details, handle)
##   downloadLeaderboardEntries(handle, request, start, end)
##     -> leaderboard_scores_downloaded(message, handle, entries_array)
##   entries are dicts: {score, steam_id, global_rank, ugc_handle, details}

signal boards_ready
signal entries_updated(board_name: String)

const BOARD_DEPTH := "daily_depth"
const BOARD_SPEED := "daily_speed"
const MAX_ENTRIES := 10
## Issue #209 section 5: details slot 3. Bump when any
## WorldGen / BuildingGen / FloorGen output changes for the
## same building key (a breaking change escalates to a board
## name suffix — that call belongs to the change forcing it).
const LAYOUT_VERSION := 1

## board_name -> {sort, display}. The two daily boards
## register at _ready; building boards register on demand
## through ensure_board (ascending / numeric, like speed).
var _board_configs: Dictionary = {}
## board_name -> Steam leaderboard handle (int). Empty until found.
var _handles: Dictionary = {}
## board_name -> Array of entry dicts {rank, name, score, is_player, details}.
var _cache: Dictionary = {BOARD_DEPTH: [], BOARD_SPEED: []}
## Uploads requested before their board resolved:
## [board_name, score, details] triples.
var _pending_uploads: Array = []


static func depth_score(cycle: int, level: int) -> int:
	# Cycle dominates: cycle 2 level 1 (200001) beats cycle 1 level 99 (100099).
	return cycle * 100000 + level


static func speed_score(clear_seconds: int) -> int:
	return maxi(clear_seconds, 0)


## Issue #209 section 4: the per-building board name — a pure
## function of the anchor-lot key, identical on every peer
## and every install, forever (an API contract, not a
## display string). Key "-14,203" -> "bld_-14_203".
static func board_name_for(building_key: String) -> String:
	return "bld_" + building_key.replace(",", "_")


func _steam_manager() -> Node:
	return get_node_or_null("/root/SteamManager")


func steam_available() -> bool:
	var sm := _steam_manager()
	return sm != null and bool(sm.get("initialized"))


func _steam_id() -> int:
	var sm := _steam_manager()
	return int(sm.get("steam_id")) if sm != null else 0


func _register_defaults() -> void:
	if _board_configs.has(BOARD_DEPTH):
		return
	_board_configs[BOARD_DEPTH] = {
		"sort": Steam.LEADERBOARD_SORT_METHOD_DESCENDING,
		"display": Steam.LEADERBOARD_DISPLAY_TYPE_NUMERIC}
	_board_configs[BOARD_SPEED] = {
		"sort": Steam.LEADERBOARD_SORT_METHOD_ASCENDING,
		"display": Steam.LEADERBOARD_DISPLAY_TYPE_NUMERIC}


func _ready() -> void:
	_register_defaults()
	if not steam_available():
		return
	Steam.leaderboard_find_result.connect(_on_leaderboard_found)
	Steam.leaderboard_scores_downloaded.connect(_on_scores_downloaded)
	ensure_boards()


## Resolve (creating if needed) both daily boards. No-op without Steam.
func ensure_boards() -> void:
	if not steam_available():
		return
	for board in [BOARD_DEPTH, BOARD_SPEED]:
		if _handles.has(board):
			continue
		var sort := Steam.LEADERBOARD_SORT_METHOD_DESCENDING
		if board == BOARD_SPEED:
			sort = Steam.LEADERBOARD_SORT_METHOD_ASCENDING
		Steam.findOrCreateLeaderboard(board, sort, Steam.LEADERBOARD_DISPLAY_TYPE_NUMERIC)


## Issue #209: register (if new) and resolve a board by name.
## Building boards are ascending / numeric. No-op without
## Steam (the config still registers, so the found handler's
## registered-name check stays meaningful offline).
func ensure_board(board_name: String) -> void:
	_register_defaults()
	if not _board_configs.has(board_name):
		_board_configs[board_name] = {
			"sort": Steam.LEADERBOARD_SORT_METHOD_ASCENDING,
			"display": Steam.LEADERBOARD_DISPLAY_TYPE_NUMERIC}
	if not steam_available() or _handles.has(board_name):
		return
	var cfg: Dictionary = _board_configs[board_name]
	Steam.findOrCreateLeaderboard(board_name,
		int(cfg["sort"]), int(cfg["display"]))


func _on_leaderboard_found(handle: int, _found: int) -> void:
	if handle == 0:
		return
	var board_name := Steam.getLeaderboardName(handle)
	_register_defaults()
	if not _board_configs.has(board_name):
		return # unregistered names are still rejected (issue #209)
	_handles[board_name] = handle
	fetch_top(board_name)
	# A dynamic board's queued uploads flush on its own
	# resolution; the daily pair keeps its both-boards gate.
	_flush_pending_uploads(board_name)
	if _handles.has(BOARD_DEPTH) and _handles.has(BOARD_SPEED):
		boards_ready.emit()
		_flush_pending_uploads()


## Upload a finished daily run. Depth always uploads; speed uploads only on
## a full Cycle-1 clear (clear_seconds >= 0). Silently skipped offline.
func upload_daily(cycle: int, level: int, clear_seconds: int = -1) -> void:
	if not steam_available():
		return
	ensure_boards()
	var jobs: Array = [[BOARD_DEPTH, depth_score(cycle, level), []]]
	if clear_seconds >= 0:
		jobs.append([BOARD_SPEED, speed_score(clear_seconds), []])
	if _handles.has(BOARD_DEPTH) and _handles.has(BOARD_SPEED):
		for job in jobs:
			Steam.uploadLeaderboardScore(job[1], true, job[2], _handles[job[0]])
	else:
		_pending_uploads.append_array(jobs)


## Issue #209: the general upload path — any registered
## board, with its details payload. Uploads immediately when
## the board's handle has resolved; otherwise the upload
## queues and flushes on resolution. Silently skipped
## offline (nothing queues without Steam).
func upload_score(board_name: String, score: int, details: Array) -> void:
	if not steam_available():
		return
	ensure_board(board_name)
	if _handles.has(board_name):
		Steam.uploadLeaderboardScore(score, true, details,
			_handles[board_name])
	else:
		_pending_uploads.append([board_name, score, details])


## Issue #209 section 3: a building clear, posted under the
## local player's own Steam account with KeepBest.
func upload_building(board_name: String, seconds: int,
		details: Array) -> void:
	upload_score(board_name, seconds, details)


func _flush_pending_uploads(only_board: String = "") -> void:
	var remaining: Array = []
	for job in _pending_uploads:
		if (only_board == "" or job[0] == only_board) \
				and _handles.has(job[0]):
			Steam.uploadLeaderboardScore(job[1], true, job[2],
				_handles[job[0]])
		else:
			remaining.append(job)
	_pending_uploads = remaining


## Download the global top 10 for a board. Results land in _cache and
## emit entries_updated. No-op without Steam.
func fetch_top(board_name: String) -> void:
	_cache[board_name] = []
	if not steam_available() or not _handles.has(board_name):
		entries_updated.emit(board_name)
		return
	Steam.downloadLeaderboardEntries(
		_handles[board_name],
		Steam.LEADERBOARD_DATA_REQUEST_GLOBAL, 1, MAX_ENTRIES)


func _on_scores_downloaded(_message: String, handle: int, entries: Array) -> void:
	var board_name := ""
	for b in _handles:
		if int(_handles[b]) == handle:
			board_name = b
	if board_name == "":
		return
	var rows: Array = []
	var my_id := _steam_id()
	for e in entries:
		if not (e is Dictionary):
			continue
		var sid := int(e.get("steam_id", 0))
		rows.append({
			"rank": int(e.get("global_rank", rows.size() + 1)),
			"name": str(Steam.getFriendPersonaName(sid)),
			"score": int(e.get("score", 0)),
			"is_player": sid == my_id and my_id != 0,
			"details": e.get("details", []),
		})
	_cache[board_name] = rows
	entries_updated.emit(board_name)


## Cached top-10 rows for the UI. Empty array offline / before download.
func get_cached(board_name: String) -> Array:
	return _cache.get(board_name, [])


## The local player's cached best on a board (their own row),
## or -1 when they have none cached. Issue #209: the door
## prompt reads this — prompt rendering never fetches.
func player_best(board_name: String) -> int:
	for e in get_cached(board_name):
		if bool(e.get("is_player", false)):
			return int(e.get("score", 0))
	return -1


## Human-readable score for the panel rows.
static func format_score(board_name: String, score: int) -> String:
	if board_name == BOARD_DEPTH:
		return "Cycle %d · Lv %d" % [score / 100000, score % 100000]
	var m := score / 60
	var s := score % 60
	return "%d:%02d" % [m, s]
