extends Node
## 击球系统单元测试 (直接调用 HitSystem，不经物理)。
## 运行: godot --headless --path <project> res://scenes/HitTest.tscn

var main_node: Node
var p1: PlayerController
var ball: Ball
var failures: int = 0

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	p1 = main_node.players[0]
	ball = main_node.ball
	p1.input_scheme = null
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
	_check("T3 raw misses table", not _lands_on_table(ball.global_position, o2.raw_dir, o2.ball_speed, o2.vz),
		"raw=%s" % str(o2.raw_dir))
	_check("T3 assist within limit", absf(rad_to_deg(o2.assist_angle)) <= GameConfig.max_assist_angle + 0.01,
		"assist=%.1f deg" % rad_to_deg(o2.assist_angle))
	_check("T3 assisted lands on table", _lands_on_table(ball.global_position, o2.assisted_dir, o2.ball_speed, o2.vz),
		"assisted=%s" % str(o2.assisted_dir))

	# T4: 原始方向已合法 -> 不辅助
	ball.global_position = Vector2(0.0, -30.0)
	zone.velocity = Vector2.ZERO
	var o3: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T4 no assist when already valid", absf(o3.assist_angle) < 0.001, "assist=%.3f" % o3.assist_angle)
