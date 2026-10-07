extends Node
## Wraps GodotSteam initialization and per-frame callbacks.
## Safe to run without Steam: the game falls back to solo/offline mode.

signal steam_ready

## Steam app ID is passed explicitly to steamInit so no steam_appid.txt file
## is needed next to the executable (verified: SDK never touches the file
## when a nonzero app ID is passed).
const STEAM_APP_ID := 3441590

var initialized: bool = false
var steam_id: int = 0
var persona_name: String = "Player"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.has_singleton("Steam"):
		push_warning("[SteamManager] Steam singleton not found; running without Steam.")
		return
	# GodotSteam 4.14+ returns a bool from steamInit; older versions returned a Dictionary.
	# App ID is passed explicitly — no steam_appid.txt file required.
	var result = Steam.steamInit(STEAM_APP_ID)
	if result is Dictionary:
		initialized = int(result.get("status", 0)) == 1
	else:
		initialized = bool(result)
	if initialized:
		steam_id = Steam.getSteamID()
		persona_name = Steam.getPersonaName()
		print("[SteamManager] Initialized as %s (%d)" % [persona_name, steam_id])
		steam_ready.emit()
	else:
		push_warning("[SteamManager] steamInit failed; running without Steam.")


func _process(_delta: float) -> void:
	if initialized:
		Steam.run_callbacks()


## Issue #84 Phase 1: DLC ownership check.
## Uses GodotSteam Apps.isDLCInstalled(app_id). Returns false if Steam is not
## initialized (headless, no Steam, etc.) — base game unaffected.
## DLC App IDs (to be assigned by Jesse on Steamworks):
##   Sunken Crypt (Bundle 1): 3441591 (placeholder)
const DLC_SUNKEN_CRYPT_APP_ID := 3441591

## For tests: mock override. If set, is_dlc_owned returns this instead of
## querying Steam. Reset to -1 for real behavior.
var _dlc_mock := -1

func set_dlc_mock(owned: bool) -> void:
	_dlc_mock = 1 if owned else 0

func clear_dlc_mock() -> void:
	_dlc_mock = -1

func is_dlc_owned(app_id: int) -> bool:
	if _dlc_mock >= 0:
		return _dlc_mock == 1
	if not initialized:
		return false
	if not Engine.has_singleton("Steam"):
		return false
	# GodotSteam 4.22.1 Apps interface: isDLCInstalled(appID) -> bool.
	return bool(Steam.isDLCInstalled(app_id))

func is_sunken_crypt_owned() -> bool:
	return is_dlc_owned(DLC_SUNKEN_CRYPT_APP_ID)
