extends Node
## Wraps GodotSteam initialization and per-frame callbacks.
## Safe to run without Steam: the game falls back to solo/offline mode.

signal steam_ready

## Steam app ID fallback. When a steam_appid.txt file is present (next to
## the executable in exports, or in the project root), its value wins —
## test builds rely on the file so the app ID can be swapped without a
## rebuild. Otherwise this const is used.
const STEAM_APP_ID := 3441590

var initialized: bool = false
var steam_id: int = 0
var persona_name: String = "Player"


## Read the app ID from steam_appid.txt if present. Checks next to the
## executable first (exported builds), then the project root (editor).
## Returns 0 when no usable file is found.
func _read_steam_app_id_file() -> int:
	var paths: Array[String] = [
		OS.get_executable_path().get_base_dir().path_join("steam_appid.txt"),
		ProjectSettings.globalize_path("res://steam_appid.txt"),
	]
	for p in paths:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				var id := int(f.get_as_text().strip_edges())
				if id > 0:
					return id
	return 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.has_singleton("Steam"):
		push_warning("[SteamManager] Steam singleton not found; running without Steam.")
		return
	# GodotSteam 4.14+ returns a bool from steamInit; older versions returned a Dictionary.
	# Test builds rely on steam_appid.txt: the file's value wins when present.
	var app_id := STEAM_APP_ID
	var file_id := _read_steam_app_id_file()
	if file_id > 0:
		app_id = file_id
		print("[SteamManager] Using app ID %d from steam_appid.txt" % app_id)
	var result = Steam.steamInit(app_id)
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
