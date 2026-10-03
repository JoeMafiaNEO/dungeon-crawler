extends Node
## Temporary functional test driver for monks/naval. Runs inside a real boot.
## Only runs if /tmp/test_monk_naval.flag exists. Removed after validation.

var _fails: Array = []
var _passes := 0
var _frame := 0


func _ready() -> void:
	if not FileAccess.file_exists("/tmp/test_monk_naval.flag"):
		queue_free()
		return


func _check(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("  PASS: %s" % name)
	else:
		_fails.append(name)
		print("  FAIL: %s" % name)


func _process(_delta: float) -> void:
	if not FileAccess.file_exists("/tmp/test_monk_naval.flag"):
		return
	_frame += 1
	if _frame < 30:
		return
	print("[Test] Monks + naval functional test...")
	_test_unit_stats()
	_test_conversion()
	_test_buildings()
	_test_water()
	_test_manager_training()
	print("[Test] %d passed, %d failed" % [_passes, _fails.size()])
	DirAccess.remove_absolute("/tmp/test_monk_naval.flag")
	get_tree().quit()


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
	_check(ship._is_ship(), "ship detection")
	var galley := RTSUnit.new()
	galley.setup(1, "war_galley", null)
	_check(galley.damage == 15.0 and galley.attack_range == 10.0, "war galley ranged")
	_check(not ("war_galley" in RTSUnit.NO_AUTO_ATTACK), "war galley auto-attacks")
	monk.free()
	ship.free()
	galley.free()


func _test_conversion() -> void:
	print("[Test] conversion")
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
	get_tree().root.add_child(monk)
	get_tree().root.add_child(enemy)
	get_tree().root.add_child(enemy_monk)
	get_tree().root.add_child(cart)
	monk.order_convert(enemy.get_path())
	_check(monk._convert_target == enemy, "convert accepted on enemy")
	_check(enemy._convert_ring != null and enemy._convert_ring.visible, "target highlighted")
	monk.order_move(Vector3(5, 0, 5))
	_check(monk._convert_target == null, "move cancels conversion")
	monk.order_convert(enemy_monk.get_path())
	_check(monk._convert_target == null, "cannot convert monk")
	monk.order_convert(cart.get_path())
	_check(monk._convert_target == null, "cannot convert trade cart")
	# Full channel.
	monk.order_convert(enemy.get_path())
	monk.global_position = Vector3.ZERO
	enemy.global_position = Vector3(2, 0, 0)
	monk._convert_timer = RTSUnit.CONVERT_TIME - 0.05
	monk._convert_tick(0.1)
	_check(enemy.faction == 0, "conversion switches faction")
	monk.free()
	enemy.free()
	enemy_monk.free()
	cart.free()


func _test_buildings() -> void:
	print("[Test] buildings")
	_check("monk" in RTSBuilding.PRODUCTION["monastery"], "monastery trains monk")
	_check("fishing_ship" in RTSBuilding.PRODUCTION["dock"], "dock trains fishing ship")
	_check("war_galley" in RTSBuilding.PRODUCTION["dock"], "dock trains war galley")
	var mon := RTSBuilding.new()
	mon.setup(0, "monastery", null)
	get_tree().root.add_child(mon)
	_check(mon.max_hp == 700.0, "monastery hp")
	_check(mon.display_name() == "Monastery", "monastery name")
	_check(mon.queue_unit("monk"), "monastery queues monk")
	_check(not mon.queue_unit("spearman"), "monastery rejects spearman")
	var dock := RTSBuilding.new()
	dock.setup(0, "dock", null)
	get_tree().root.add_child(dock)
	_check(dock.max_hp == 500.0, "dock hp")
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
	fake_dungeon.add_to_group("dungeon")
	var holder := Node3D.new()
	holder.name = "RTS"
	fake_dungeon.add_child(holder)
	get_tree().root.add_child(fake_dungeon)
	var mgr := RTSManager.new()
	get_tree().root.add_child(mgr)
	mgr.register_faction(0, 1, "warrior")
	_check(mgr.can_train(0, "monk"), "can train monk")
	mgr.spawn_unit("monk", 0, Vector3.ZERO, mgr.get_civ(0))
	_check(holder.get_child_count() == 1, "monk spawned")
	var res: Dictionary = mgr.get_resources(0)
	_check(int(res["gold"]) == 0, "monk cost deducted")
	_check(not mgr.can_train(0, "monk"), "no gold for second monk")
	fake_dungeon.free()
	mgr.free()
