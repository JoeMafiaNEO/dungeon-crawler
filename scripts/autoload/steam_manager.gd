extends Node
## Wraps GodotSteam initialization and per-frame callbacks.
## Safe to run without Steam: the game falls back to solo/offline mode.

signal steam_ready

var initialized: bool = false
var steam_id: int = 0
var persona_name: String = "Player"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.has_singleton("Steam"):
		push_warning("[SteamManager] Steam singleton not found; running without Steam.")
		return
	# GodotSteam 4.14+ returns a bool from steamInit; older versions returned a Dictionary.
	var result = Steam.steamInit()
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
