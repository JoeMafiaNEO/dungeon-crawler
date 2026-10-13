extends SceneTree
## Issue #104 Phase 2 validation driver: renders the character panel at
## 1920x1080 with a FULL 12-stack inventory (4 slots equipped, a
## class-restricted row, consumables) and saves a screenshot.
## Run windowed under Xvfb:
##   xvfb-run -a -s "-screen 0 1920x1080x24" \
##     Godot_v4.7.2 --path . --resolution 1920x1080 \
##     -s tools/character_panel_shots/character_panel_shots.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ItemDBNode: Variant = root.get_node("ItemDB")
	var PlayerScene: PackedScene = load("res://scenes/player/player.tscn")
	var HudScene: PackedScene = load("res://scenes/ui/hud.tscn")
	var p = PlayerScene.instantiate()
	p.class_id = "warrior"
	root.add_child(p)
	# 12 stacks total (INVENTORY_MAX): starter + 11 more.
	for id in ["iron_sword", "runeblade", "leather_armor", "plate_armor",
			"lucky_charm", "phoenix_feather", "swift_boots",
			"health_potion", "health_potion", "health_potion",
			"power_elixir", "cereal_box", "ember_amulet"]:
		p.receive_item(id)
	var tome = ItemDBNode.get_item("scholar_tome").duplicate()
	var only_mage: Array[String] = ["mage"]
	tome.set("allowed_classes", only_mage)
	# Swap the cereal stack out for the restricted tome (stay at 12).
	for i in p.inventory.size():
		var it = p.inventory[i].get("item")
		if it != null and str(it.get("id")) == "cereal_box":
			p.inventory[i] = {"item": tome, "count": 1, "equipped_slot": ""}
	# Equip one stack per slot.
	var want := {"iron_sword": true, "plate_armor": true,
		"lucky_charm": true, "phoenix_feather": true}
	for i in p.inventory.size():
		var it = p.inventory[i].get("item")
		if it != null and want.has(str(it.get("id"))):
			p.equip_stack(i)
	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._player = p
	hud.refresh_inventory(p)
	hud.toggle_inventory()
	# Select the runeblade row for a visible selection state.
	var rows: Array = hud.get("_bag_rows")
	for i in p.inventory.size():
		var it = p.inventory[i].get("item")
		if it != null and str(it.get("id")) == "runeblade":
			(rows[i] as Button).set_pressed(true)
	await create_timer(1.2).timeout
	var img := root.get_texture().get_image()
	img.save_png("/home/hatch/workspace/char_panel_shots/panel_full_1080p.png")
	print("[CharPanelShots] saved panel_full_1080p.png, inventory stacks: ", p.inventory.size())
	quit()
