extends Node
## Loads every ItemData resource under res://data/items so drops and
## equipment can be looked up by id at runtime.

var items: Dictionary = {} # String id -> ItemData


func _ready() -> void:
	_load_dir("res://data/items")


func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[ItemDB] Could not open %s" % path)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var item := load(path + "/" + file_name) as ItemData
		if item != null and not item.id.is_empty():
			items[item.id] = item
		else:
			push_warning("[ItemDB] Skipped invalid item file: %s" % file_name)
	print("[ItemDB] Loaded %d items." % items.size())


func get_item(item_id: String) -> ItemData:
	return items.get(item_id) as ItemData
