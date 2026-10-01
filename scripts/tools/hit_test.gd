extends Node
## 击球系统单元测试 (直接调用 HitSystem，不经物理)。
## 运行: godot --headless --path <project> res://scenes/HitTest.tscn

var main_node: Node
var p1: PlayerController
var ball: Ball
var failures: int = 0
var _last_death: int = -1

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	p1 = main_node.players[0]
	ball = main_node.ball
	p1.input_scheme = null
	ball.died.connect(func(r: int) -> void: _last_death = r)
	_run()
	print("HIT TEST failures=", failures)
	get_tree().quit()

func _check(name: String, cond: bool, detail: String) -> void:
	if cond:
		print("PASS  ", name, "  ", detail)
	else:
		failures += 1
		print("FAIL  ", name, "  ", detail)

func _lands_on_table(p: Vector2, dir: Vector2, speed: float, vz: float) -> bool:
	var d: float = 2.0 * speed * vz / GameConfig.ball_gravity
	return GameConfig.table_rect().grow(-4.0).has_point(p + dir * d)

func _run() -> void:
	var zone: HitPoint = p1.hit_points[0]
	p1.global_position = Vector2(0.0, -14.0)
	p1.rotation = -PI / 2.0  # 面向桌中心 (局部 +x = 世界上方)

	# T1: 击球区静止 -> 力度最低, 球速=min, 方向≈面向
	ball.global_position = Vector2(0.0, -60.0)
	zone.velocity = Vector2.ZERO
	var o0: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T1 min strength", o0.strength < 0.01, "strength=%.3f" % o0.strength)
	_check("T1 ball speed == min", absf(o0.ball_speed - GameConfig.hit_speed_min) < 1.0, "spd=%.0f" % o0.ball_speed)
	_check("T1 raw dir ≈ facing(up)", o0.raw_dir.dot(Vector2(0.0, -1.0)) > 0.9, str(o0.raw_dir))

	# T2: 快速挥动 -> 力度高, 球速=min~max 之间且更大
	zone.velocity = Vector2(0.0, -1500.0)
	var o1: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T2 high strength", o1.strength > 0.9, "strength=%.3f" % o1.strength)
	_check("T2 ball speed <= max", o1.ball_speed <= GameConfig.hit_speed_max + 1.0, "spd=%.0f" % o1.ball_speed)
	_check("T2 speed increases", o1.ball_speed > o0.ball_speed, "%.0f > %.0f" % [o1.ball_speed, o0.ball_speed])

	# T3: 原始方向会出界 -> 有界辅助并落桌
	ball.global_position = Vector2(0.0, -30.0)
	zone.velocity = Vector2(1500.0, 0.0)  # 向右挥 -> raw 偏右上, 会飞出远端
	var o2: Dictionary = HitSystem.compute(p1, zone, ball)
	var raw_miss: bool = not _lands_on_table(ball.global_position, o2.raw_dir, o2.ball_speed, o2.vz)
	_check("T3 raw misses table", raw_miss, "raw=%s" % str(o2.raw_dir))
	_check("T3 assist within limit", absf(rad_to_deg(o2.assist_angle)) <= GameConfig.max_assist_angle + 0.01,
		"assist=%.1f deg" % rad_to_deg(o2.assist_angle))
	if absf(o2.assist_angle) > 0.001:
		_check("T3 assisted lands on table",
			_lands_on_table(ball.global_position, o2.assisted_dir, o2.ball_speed, o2.vz),
			"assisted=%s" % str(o2.assisted_dir))

	# T4: 辅助算法本身 (确定性, 不依赖球速参数)
	var tp := Vector2(0.0, -40.0)
	var td := 100.0
	var traw := Vector2(0.9, 0.436).normalized()  # 明显朝下, 会飞过近边
	_check("T4 raw misses (helper)", not HitSystem._lands_on_table(tp, traw, td), str(traw))
	var corr: float = HitSystem._find_correction(tp, traw, td, deg_to_rad(GameConfig.max_assist_angle))
	_check("T4 correction bounded", absf(rad_to_deg(corr)) <= GameConfig.max_assist_angle + 0.01,
		"corr=%.1f" % rad_to_deg(corr))
	_check("T4 corrected lands", HitSystem._lands_on_table(tp, traw.rotated(corr), td),
		str(traw.rotated(corr)))

	# T5: 墙后连续第 2 次落桌 -> DOUBLE_BOUNCE (接球方输)
	ball.state = GameTypes.BallState.LIVE
	ball.reset_shot()
	ball.wall_since_hit = true
	ball._register_table_bounce()
	var after_first: bool = ball.state != GameTypes.BallState.DEAD
	ball._register_table_bounce()
	_check("T5 1st bounce allowed", after_first, "state=%d" % ball.state)
	_check("T5 2nd bounce -> DOUBLE_BOUNCE",
		ball.state == GameTypes.BallState.DEAD and _last_death == GameTypes.DeathReason.DOUBLE_BOUNCE,
		"state=%d reason=%d" % [ball.state, _last_death])
