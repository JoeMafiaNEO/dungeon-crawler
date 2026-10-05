extends Node
## WorkshopEcho: Steam Workshop UGC sharing for daily run echoes (issue #9 Phase 3).
##
## Uploads the day's best echo as a Workshop item tagged "daily-echo-<YYYYMMDD>",
## queries that tag, and downloads the top 3 for ghost racing.
##
## All Steam calls are guarded by SteamManager.initialized — silent no-op
## offline, per the Phase 1 pattern. The echo file format comes from
## EchoRecorder (Phase 2); this module only moves bytes.
##
## Verified against GodotSteam 4.22.1 via live introspection (2026-10-05):
##   createItem(app_id, file_type) / item_created(result, file_id, accept_tos)
##   startItemUpdate(app_id, file_id) -> update_handle
##   setItemTitle/handle, setItemDescription, setItemTags(handle, tags, allow_admin),
##   setItemContent(handle, folder), setItemVisibility(handle, vis), submitItemUpdate(handle, note)
##   item_updated(result, need_tos, file_id)
##   createQueryAllUGCRequestPage(query_type, matching_type, creator, consumer, page)
##   addRequiredTag(handle, tag), sendQueryUGCRequest(handle)
##   ugc_query_completed(handle, result, count, total, cached, cursor)
##   getQueryUGCResult(handle, index) -> Dictionary {published_file_id, ...}
##   downloadItem(file_id, high_priority) / item_downloaded(result, file_id, app_id)
##   getItemInstallInfo(file_id) -> Dictionary {folder, ...}

signal upload_complete(success: bool, file_id: int)
signal query_complete(echoes: Array)  # Array of {file_id:int, title:String}
signal download_complete(file_id: int, echo_path: String)

const TAG_PREFIX := "daily-echo-"
const MAX_DOWNLOADS := 3
const STAGING_DIR := "user://workshop_staging"
const ECHO_FILENAME := "echo.dat"
# Steamworks: k_EUGCMatchingUGCType_Items = 0, k_ERemoteStoragePublishedFileVisibilityPublic = 0
const VISIBILITY_PUBLIC := 0

var _pending_upload_date := ""
var _pending_query_handle := 0


func _ready() -> void:
	# Connect Steam signals only when Steam is actually running; the
	# singleton exists regardless, but signals never fire offline.
	if SteamManager.initialized:
		Steam.item_created.connect(_on_item_created)
		Steam.item_updated.connect(_on_item_updated)
		Steam.ugc_query_completed.connect(_on_ugc_query_completed)
		Steam.item_downloaded.connect(_on_item_downloaded)


## Tag for a given date string (YYYYMMDD).
static func tag_for_date(date_str: String) -> String:
	return TAG_PREFIX + date_str


func steam_available() -> bool:
	return SteamManager.initialized


## Upload today's best echo to the Workshop. Silent no-op offline or when
## no echo file exists. Result arrives via upload_complete.
func upload_today_best() -> void:
	if not steam_available():
		return
	var recorder: Node = get_node_or_null("/root/EchoRecorder")
	var daily: Node = get_node_or_null("/root/DailyRun")
	if recorder == null or daily == null:
		return
	var date_str: String = daily.call("get_today_string")
	var echo_path: String = recorder.call("echo_path_for_date", date_str)
	if not FileAccess.file_exists(echo_path):
		return
	# setItemContent needs a folder: stage the .dat into a content dir.
	var staging := "%s/%s" % [STAGING_DIR, date_str]
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive(staging.trim_prefix("user://"))
	var src := FileAccess.open(echo_path, FileAccess.READ)
	var dst := FileAccess.open("%s/%s" % [staging, ECHO_FILENAME], FileAccess.WRITE)
	if src == null or dst == null:
		return
	dst.store_buffer(src.get_buffer(src.get_length()))
	src.close()
	dst.close()
	_pending_upload_date = date_str
	Steam.createItem(Steam.getAppID(), Steam.WORKSHOP_FILE_TYPE_COMMUNITY)


func _on_item_created(result: int, file_id: int, _accept_tos: bool) -> void:
	if _pending_upload_date.is_empty():
		return
	var date_str := _pending_upload_date
	_pending_upload_date = ""
	if result != 1:  # k_EResultOK
		upload_complete.emit(false, 0)
		return
	var handle: int = Steam.startItemUpdate(Steam.getAppID(), file_id)
	Steam.setItemTitle(handle, "Daily Echo %s" % date_str)
	Steam.setItemDescription(handle,
		"Daily dungeon crawler echo for %s. Race this ghost!" % date_str)
	Steam.setItemTags(handle, [tag_for_date(date_str)], false)
	# Absolute OS path: Steam wants a real folder, not user://.
	var staging_abs := "%s/workshop_staging/%s" % [OS.get_user_data_dir(), date_str]
	Steam.setItemContent(handle, staging_abs)
	Steam.setItemPreview(handle, staging_abs + "/" + ECHO_FILENAME)
	Steam.setItemVisibility(handle, VISIBILITY_PUBLIC)
	Steam.submitItemUpdate(handle, "Daily echo upload")


func _on_item_updated(result: int, _need_tos: bool, file_id: int) -> void:
	upload_complete.emit(result == 1, file_id)


## Query the Workshop for today's echoes. Result via query_complete.
## Silent no-op offline (emits empty array).
func query_today_echoes() -> void:
	if not steam_available():
		query_complete.emit([])
		return
	var daily: Node = get_node_or_null("/root/DailyRun")
	if daily == null:
		query_complete.emit([])
		return
	var date_str: String = daily.call("get_today_string")
	_pending_query_handle = Steam.createQueryAllUGCRequestPage(
		Steam.UGC_QUERY_RANKED_BY_VOTE,
		Steam.UGC_MATCHING_UGC_TYPE_ITEMS,
		0, Steam.getAppID(), 1)
	Steam.addRequiredTag(_pending_query_handle, tag_for_date(date_str))
	Steam.sendQueryUGCRequest(_pending_query_handle)


func _on_ugc_query_completed(handle: int, result: int, results_returned: int,
		_total_matching: int, _cached: bool, _cursor: String) -> void:
	if handle != _pending_query_handle:
		return
	_pending_query_handle = 0
	var echoes: Array = []
	if result == 1:  # k_EResultOK
		for i in mini(results_returned, MAX_DOWNLOADS):
			var info: Dictionary = Steam.getQueryUGCResult(handle, i)
			echoes.append({
				"file_id": int(info.get("published_file_id", 0)),
				"title": str(info.get("title", "Echo")),
			})
	query_complete.emit(echoes)


## Download a Workshop echo by file_id. Result via download_complete.
## Silent no-op offline.
func download_echo(file_id: int) -> void:
	if not steam_available() or file_id == 0:
		return
	Steam.downloadItem(file_id, true)


func _on_item_downloaded(result: int, file_id: int, _app_id: int) -> void:
	if result != 1:
		download_complete.emit(file_id, "")
		return
	var info: Dictionary = Steam.getItemInstallInfo(file_id)
	var folder := str(info.get("folder", ""))
	var echo_path := folder + "/" + ECHO_FILENAME if not folder.is_empty() else ""
	download_complete.emit(file_id, echo_path)
