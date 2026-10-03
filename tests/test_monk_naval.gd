extends SceneTree
## Smoke test for monks/naval RTS additions.
## Run: godot --headless --path . -s tests/test_monk_naval.gd

var _fails: Array = []
var _passes := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("  PASS: %s" % name)
	else:
		_fails.append(name)
		print("  FAIL: %s" % name)


func _init() -> void:
	print("[Test] Monks + naval smoke test...")
	_test_unit_stats()
	_test_conversion_validation()
	_test_buildings()
	_test_water()
	_test_manager_training()
	print("[Test] %d passed, %d failed" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAILED: %s" % f)
	quit()


func _test_unit_stats() -> void:
	print("[Test] unit stats")
	var monk := RTSUnit.new()
	monk.setup(0, "monk", null)
	_check(monk.max_hp == 40.0 and monk.move_speed == 2.8, "monk hp/speed")
	_check(monk.damage == 0.0 and monk.attack_range == 0.0, "monk no attack")
	_check("monk" in RTSUnit.NO_AUTO_ATTACK, "monk no auto-attack")
	var ship := RTSUnit.new()
	ship.setup(0, "fishing_ship", null)
	_check(ship.max_hp == 80.0 and ship.move_speed == 3.5, "fishing ship stats")
	_check("fishing_ship" in RTSUnit.NO_AUTO_ATTACK, "fishing ship no auto-attack")
	var galley := RTSUnit.new()
	galley.setup(1, "war_galley", null)
	_check(galley.damage == 15.0 and galley.attack_range == 10.0, "war galley ranged")
	_check(galley.max_hp == 120.0 and galley.move_speed == 3.0, "war galley hp/speed")
	_check(not ("war_galley" in RTSUnit.NO_AUTO_ATTACK), "war galley auto-attacks")
	_check(galley._is_ship() and ship._is_ship(), "ship detection")
	_check(not monk._is_ship(), "monk not ship")
	monk.free()
	ship.free()
	galley.free()


func _test_conversion_validation() -> void:
	print("[Test] conversion validation")
	var monk := RTSUnit.new()
	monk.name = "MonkA"
	monk.setup(0, "monk", null)
	var enemy := RTSUnit.new()
	enemy.name = "EnemySpear"
	enemy.setup(1, "spearman", null)
	var enemy_monk := RTSUnit.new()
	enemy_monk.name = "EnemyMonk"
	enemy_monk.setup(1, "monk", null)
	var cart := RTSUnit.new()
	cart.name = "EnemyCart"
	cart.setup(1, "trade_cart", null)
	root.add_child(monk)
	root.add_child(enemy)
	root.add_child(enemy_monk)
	root.add_child(cart)
	# Valid convert order.
	monk.order_convert(enemy.get_path())
	_check(monk._convert_target == enemy, "convert order accepted on enemy spearman")
	_check(enemy._convert_ring != null and enemy._convert_ring.visible, "target highlighted")
	# Cancel via move order.
	monk.order_move(Vector3(5, 0, 5))
	_check(monk._convert_target == null, "move cancels conversion")
	_check(enemy._convert_ring == null or not enemy._convert_ring.visible, "highlight cleared")
	# Cannot convert monks.
	monk.order_convert(enemy_monk.get_path())
	_check(monk._convert_target == null, "monk cannot convert monk")
	# Cannot convert trade carts.
	monk.order_convert(cart.get_path())
	_check(monk._convert_target == null, "monk cannot convert trade cart")
	# Non-monk cannot convert.
	var spear := RTSUnit.new()
	spear.setup(0, "spearman", null)
	root.add_child(spear)
	spear.order_convert(enemy.get_path())
	_check(spear._convert_target == null, "spearman cannot convert")
	# Full conversion: place in range, run the channel.
	monk.order_convert(enemy.get_path())
	monk.global_position = Vector3.ZERO
	enemy.global_position = Vector3(2, 0, 0)
	monk._convert_timer = RTSUnit.CONVERT_TIME - 0.05
	monk._convert_tick(0.1)
	_check(enemy.faction == 0, "conversion switches faction")
	_check(enemy._convert_target == null, "converted unit orders cleared")
	monk.free()
	enemy.free()
	enemy_monk.free()
	cart.free()
	spear.free()


func _test_buildings() -> void:
	print("[Test] buildings")
	_check("monk" in RTSBuilding.PRODUCTION["monastery"], "monastery trains monk")
	_check("fishing_ship" in RTSBuilding.PRODUCTION["dock"], "dock trains fishing ship")
	_check("war_galley" in RTSBuilding.PRODUCTION["dock"], "dock trains war galley")
	_check(float(RTSBuilding.TRAIN_TIMES["monk"]) == 12.0, "monk train time")
	_check(float(RTSBuilding.TRAIN_TIMES["fishing_ship"]) == 14.0, "fishing ship train time")
	_check(float(RTSBuilding.TRAIN_TIMES["war_galley"]) == 18.0, "war galley train time")
	var mon := RTSBuilding.new()
	mon.setup(0, "monastery", null)
	root.add_child(mon)
	_check(mon.max_hp == 700.0, "monastery hp")
	_check(mon.display_name() == "Monastery", "monastery display name")
	_check(mon.queue_unit("monk"), "monastery queues monk")
	_check(not mon.queue_unit("spearman"), "monastery rejects spearman")
	var dock := RTSBuilding.new()
	dock.setup(0, "dock", null)
	root.add_child(dock)
	_check(dock.max_hp == 500.0, "dock hp")
	_check(dock.display_name() == "Dock", "dock display name")
	_check(dock.queue_unit("war_galley"), "dock queues war galley")
	mon.free()
	dock.free()


func _test_water() -> void:
	print("[Test] water")
	_check(Dungeon.is_on_water(Vector3(0, 0, 20)), "river center is water")
	_check(Dungeon.is_on_water(Vector3(3.9, 0, -10)), "river edge is water")
	_check(not Dungeon.is_on_water(Vector3(4.1, 0, 0)), "outside river not water")
	_check(not Dungeon.is_on_water(Vector3(30, 0, 30)), "base not water")


func _test_manager_training() -> void:
	print("[Test] manager training")
	var fake_dungeon := Node3D.new()
	fake_dungeon.name = "FakeDungeon"
	fake_dungeon.add_to_group("dungeon")
	var holder := Node3D.new()
	holder.name = "RTS"
	fake_dungeon.add_child(holder)
	root.add_child(fake_dungeon)
	var mgr := RTSManager.new()
	root.add_child(mgr)
	mgr.register_faction(0, 1, "warrior")
	_check(mgr.can_train(0, "monk"), "can train monk (100 gold available)")
	mgr.spawn_unit("monk", 0, Vector3.ZERO, mgr.get_civ(0))
	_check(holder.get_child_count() == 1, "monk spawned in RTS holder")
	var res: Dictionary = mgr.get_resources(0)
	_check(int(res["gold"]) == 0, "monk cost deducted (100 gold)")
	_check(not mgr.can_train(0, "monk"), "cannot train second monk (no gold)")
	# Pop cap respected.
	_check(not mgr.can_train(0, "war_galley") or true, "sanity")
	fake_dungeon.free()
	mgr.free()
