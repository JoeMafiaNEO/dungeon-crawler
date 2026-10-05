extends Node
## Real-boot legacy migration check (issue #4 Phase 6). Run headless:
##   godot --headless --path . res://tools/migrate_check/migrate_check.tscn
## Seeds a synthetic legacy tree, boots the real game (the SaveManager
## autoload migrates on _ready), verifies the migration, then removes every
## file it created and restores backups. Never leaves test data in user://.

var _failures := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[MigrateCheck] PASS: ", label)
	else:
		_failures += 1
		print("[MigrateCheck] FAIL: ", label)


func _write_legacy(path: String, data: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "data", data)
	cfg.save(path)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if "--seed" in args:
		_seed()
		print("[MigrateCheck] seeded; quitting for a fresh boot")
		get_tree().quit()
		return
	_verify()


var _legacy_paths := ["user://solo_warrior.cfg", "user://solo_mage.cfg",
	"user://run_save.cfg", "user://savegame.cfg"]
var _prof_path := "user://profile_local.cfg"


func _slot_paths() -> Array:
	var out: Array = []
	for mode in ["solo", "mp"]:
		for s in range(3):
			out.append("user://runs/%s_%d.cfg" % [mode, s])
	return out


## Move an existing file to a sidecar so the seed starts clean. Self-heals:
## a leftover sidecar from a crashed run is moved back first.
func _stash(path: String) -> void:
	var bak := path + ".migratebak"
	if FileAccess.file_exists(bak):
		# Leftover from a crashed run: heal it before doing anything.
		var hbytes := FileAccess.get_file_as_bytes(bak)
		var hf := FileAccess.open(path, FileAccess.WRITE)
		hf.store_buffer(hbytes)
		hf.close()
		DirAccess.remove_absolute(bak)
	if FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		var bf := FileAccess.open(bak, FileAccess.WRITE)
		bf.store_buffer(bytes)
		bf.close()
		DirAccess.remove_absolute(path)


func _restore() -> void:
	for p in _legacy_paths + _slot_paths() + [_prof_path]:
		var bak: String = str(p) + ".migratebak"
		if FileAccess.file_exists(bak):
			var bytes := FileAccess.get_file_as_bytes(bak)
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_buffer(bytes)
			f.close()
			DirAccess.remove_absolute(bak)
		elif FileAccess.file_exists(p) and _is_scratch(p):
			DirAccess.remove_absolute(p)


## True for files this driver created (synthetic legacy files and the slots
## migration wrote). Never deletes anything it didn't create.
func _is_scratch(path: String) -> bool:
	if path in _legacy_paths:
		return true
	if path == "user://migrate_check_manifest.cfg":
		return true
	if path.begins_with("user://runs/"):
		return true
	return path == _prof_path


func _seed() -> void:
	for p in _legacy_paths + _slot_paths() + [_prof_path]:
		_stash(p)
	DirAccess.make_dir_recursive_absolute("user://runs")
	# Synthetic legacy tree: warrior (older), mage (newer), one MP run,
	# and an old-format meta file.
	_write_legacy("user://solo_warrior.cfg", {"class_id": "warrior",
		"theme_id": "dungeon", "level_number": 3, "is_multiplayer": false,
		"saved_at": "2026-01-01T00:00:00", "save_version": 1,
		"player_state": {"level": 8}})
	_write_legacy("user://solo_mage.cfg", {"class_id": "mage",
		"theme_id": "village", "level_number": 1, "is_multiplayer": false,
		"saved_at": "2026-06-01T00:00:00", "save_version": 1,
		"player_state": {"level": 12}})
	_write_legacy("user://run_save.cfg", {"class_id": "mage",
		"theme_id": "warlord", "level_number": 4, "is_multiplayer": true,
		"saved_at": "2026-06-02T00:00:00", "save_version": 1,
		"player_state": {"level": 6}, "roster": []})
	var metacfg := ConfigFile.new()
	metacfg.set_value("meta", "total_kills", 57)
	metacfg.save("user://savegame.cfg")
	print("[MigrateCheck] synthetic legacy tree written")


func _verify() -> void:
	# The SaveManager autoload ran _migrate_legacy() in its _ready, before
	# this driver's _ready. Give it a frame, then verify.
	await get_tree().process_frame
	await get_tree().process_frame
	_check(SaveManager.has_run("solo", 0), "newest legacy (mage) migrated to solo slot 0")
	_check(SaveManager.has_run("solo", 1), "older legacy (warrior) migrated to solo slot 1")
	_check(not SaveManager.has_run("solo", 2), "solo slot 2 stays empty")
	var mage_run: Dictionary = SaveManager.load_run("solo", 0)
	_check(str(mage_run.get("class_id", "")) == "mage", "slot 0 holds the mage run")
	_check(str(SaveManager.load_run("solo", 1).get("class_id", "")) == "warrior",
		"slot 1 holds the warrior run")
	_check(SaveManager.has_run("mp", 0), "legacy MP run migrated to mp slot 0")
	var mp_run: Dictionary = SaveManager.load_run("mp", 0)
	_check(bool(mp_run.get("is_multiplayer", false)), "migrated MP run keeps its flag")
	_check(FileAccess.file_exists("user://solo_warrior.cfg")
		and FileAccess.file_exists("user://solo_mage.cfg")
		and FileAccess.file_exists("user://run_save.cfg"),
		"migration is copy-only: legacy files retained")
	_check(SaveManager.list_legacy_saves().is_empty(),
		"no legacy overflow left after migration")
	_check(SaveManager.get_total_kills() == 57,
		"old savegame.cfg meta merged into the profile")
	print("[MigrateCheck] DIAG total_kills=", SaveManager.get_total_kills(),
		" savegame_exists=", FileAccess.file_exists("user://savegame.cfg"))
	if _failures > 0:
		# Diagnostics: dump actual slot/legacy state to distinguish a real
		# migration bug from concurrent user:// writers on this shared VM.
		print("[MigrateCheck] DIAG user://dump:")
		for mode in ["solo", "mp"]:
			for s in range(3):
				var r: Dictionary = SaveManager.load_run(mode, s)
				print("[MigrateCheck] DIAG   %s_%d: class=%s mp=%s" % [mode, s,
					str(r.get("class_id", "-")), str(bool(r.get("is_multiplayer", false)))])
		for e in SaveManager.list_legacy_saves():
			print("[MigrateCheck] DIAG   legacy left: ", str(e.get("path", "?")))
	_restore()
	print("[MigrateCheck] done; failures=%d; user:// restored" % _failures)
	get_tree().quit(_failures)
