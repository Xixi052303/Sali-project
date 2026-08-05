extends SceneTree

var _failures: int = 0


func _init() -> void:
	_check(is_equal_approx(MultiplayerRules.scale_enemy_appetite(100.0, 1), 100.0), "单人敌人胃口保持基准")
	_check(is_equal_approx(MultiplayerRules.scale_enemy_appetite(100.0, 4), 400.0), "四人敌人胃口按人数缩放")
	_check(is_equal_approx(MultiplayerRules.per_player_damage(100.0, 2), 50.0), "共享剩余胃口按人数换算单次基准伤害")
	_check(is_equal_approx(MultiplayerRules.per_player_damage(200.0, 2), 100.0), "两人敌人200共享胃口仍各承受100单人基准伤害")
	_check(is_equal_approx(MultiplayerRules.respawn_delay(15.0, 15.0, 180.0, 0), 15.0), "首次倒下复活15秒")
	_check(is_equal_approx(MultiplayerRules.respawn_delay(15.0, 15.0, 180.0, 1), 30.0), "每次倒下增加15秒")
	_check(is_equal_approx(MultiplayerRules.respawn_delay(15.0, 15.0, 180.0, 2), 45.0), "同批倒下后下一次复活档位按实际人数增加")
	_check(is_equal_approx(MultiplayerRules.respawn_delay(15.0, 15.0, 180.0, 20), 180.0), "复活倒计时封顶180秒")
	_check(is_equal_approx(MultiplayerRules.ghost_output(100.0, 0.01), 1.0), "幽灵输出统一为百分之一")
	_check(MultiplayerRules.ghost_can_claim_normal_gate(0.0), "普通门基础血量清零后幽灵可以领取")
	_check(not MultiplayerRules.ghost_can_claim_normal_gate(1.0), "普通门仍有基础血量时幽灵不能免碰撞领取")
	_check(MultiplayerRules.all_players_ghost([true, true, true, true]), "全员幽灵才满足全灭")
	_check(not MultiplayerRules.all_players_ghost([true, true, false, true]), "仍有存活玩家时不能判定全灭")
	_test_context_respawn_and_repair_cache()
	_test_context_respawn_overflow_shield()
	_test_respawn_protection_window()
	_test_same_batch_death_tier()
	if _failures == 0:
		print("MULTIPLAYER_RULES_TEST_OK")
		quit(0)
	else:
		push_error("MULTIPLAYER_RULES_TEST_FAILED count=%d" % _failures)
		quit(1)


func _test_context_respawn_and_repair_cache() -> void:
	var state: RunState = RunState.new()
	var context: PlayerRunContext = PlayerRunContext.new()
	context.configure(1, 1, state, null, null)
	context.enter_ghost(15.0)
	var sturdy: UpgradeData = UpgradeData.new()
	sturdy.kind = UpgradeData.Kind.STURDY_CART
	sturdy.value = 0.1
	state.apply_upgrade(sturdy, true, false)
	var repair: UpgradeData = UpgradeData.new()
	repair.kind = UpgradeData.Kind.REPAIR
	repair.value = 0.5
	state.apply_upgrade(repair, true, false)
	context.cache_repair(55.0)
	context.respawn(0.5)
	_check(not context.is_ghost() and is_equal_approx(state.current_durability, 110.0), "复活先取上限50%再应用缓存维修")
	_check(context.tick_respawn(1.0) == false, "复活后不再继续倒计时")


func _test_context_respawn_overflow_shield() -> void:
	var state: RunState = RunState.new()
	var context: PlayerRunContext = PlayerRunContext.new()
	context.configure(2, 2, state, null, null)
	context.enter_ghost(15.0)
	context.cache_repair(100.0)
	context.respawn(0.5)
	_check(is_equal_approx(state.current_durability, 100.0), "复活维修先补满最大耐久")
	_check(is_equal_approx(state.temporary_shield, 50.0), "溢出维修转为临时护盾")


# 直接验证复活保护窗口，不依赖完整战斗时间轴。
func _test_respawn_protection_window() -> void:
	var field: Playfield = Playfield.new()
	var state: RunState = RunState.new()
	var cart_scene: PackedScene = load("res://scenes/cart_3d.tscn") as PackedScene
	var cart: Cart3D = cart_scene.instantiate() as Cart3D
	cart.configure(state, field)
	var context: PlayerRunContext = PlayerRunContext.new()
	context.configure(3, 3, state, cart, null)
	context.enter_ghost(15.0)
	context.respawn(0.5, 2.0)
	_check(not cart.take_damage(1.0), "复活后的2秒保护期间不能受伤")
	cart._physics_process(2.0)
	_check(cart.take_damage(1.0), "复活保护结束后恢复受击")
	cart.free()
	field.free()


func _test_same_batch_death_tier() -> void:
	var first_batch_delay: float = MultiplayerRules.respawn_delay(15.0, 15.0, 180.0, 0)
	var next_batch_delay: float = MultiplayerRules.respawn_delay(15.0, 15.0, 180.0, 2)
	_check(is_equal_approx(first_batch_delay, 15.0), "同一伤害批次的两名玩家共用首档15秒")
	_check(is_equal_approx(next_batch_delay, 45.0), "两人同批倒下后下一批从45秒开始")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("TEST FAILED: %s" % message)
