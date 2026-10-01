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

## 落点是否在"好区"内 (与 HitSystem 的触发条件一致)。
func _in_good_zone(p: Vector2, dir: Vector2, speed: float, vz: float) -> bool:
	var d: float = 2.0 * speed * vz / GameConfig.ball_gravity
	return GameConfig.table_rect().grow(-GameConfig.assist_good_margin).has_point(p + dir * d)

## 沿 dir 打到墙并反射后，水平路径离桌中心的最近距离 (验证镜面法)。
func _post_wall_center_dist(p: Vector2, dir: Vector2) -> float:
	var wall_y: float = GameConfig.wall_inner_y()
	if absf(dir.y) < 1e-6:
		return 999.0
	var t: float = (wall_y - p.y) / dir.y
	if t <= 0.0:
		return 999.0
	var hit: Vector2 = p + dir * t
	var rd := Vector2(dir.x, -dir.y)  # 水平反射方向
	var to_c: Vector2 = GameConfig.table_center - hit
	var proj: float = to_c.dot(rd)
	if proj < 0.0:
		return 999.0
	return (to_c - rd * proj).length()

func _run() -> void:
	var zone: HitPoint = p1.hit_points[0]
	p1.global_position = Vector2(0.0, -14.0)
	p1.rotation = -PI / 2.0  # 面向桌中心 (局部 +x = 世界上方)
	GameConfig.assist_strength = 0.0  # 先关辅助, 单独测力度/方向映射

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

	# T3: assist=1, raw 出界 -> 完全辅助后落桌
	GameConfig.assist_strength = 1.0
	ball.global_position = Vector2(0.0, -30.0)
	zone.velocity = Vector2(1500.0, 0.0)  # 向右挥 -> raw 偏右上, 会飞出远端
	var o2: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T3 raw outside good zone",
		not _in_good_zone(ball.global_position, o2.raw_dir, o2.raw_speed, o2.vz), "raw=%s" % str(o2.raw_dir))
	_check("T3 assist=1 first bounce on table",
		_lands_on_table(ball.global_position, o2.assisted_dir, o2.ball_speed, o2.vz),
		"assisted=%s spd=%.0f" % [str(o2.assisted_dir), o2.ball_speed])
	var pw3: float = _post_wall_center_dist(ball.global_position, o2.assisted_dir)
	_check("T3 assist aims so post-wall line hits table center (mirror)", pw3 < 8.0, "dist=%.1f" % pw3)

	# T3b: 偏心球 -> 无辅助会飞出, 辅助后墙后路径仍经过桌中心 (真正的镜面验证)
	ball.global_position = Vector2(-120.0, -30.0)
	zone.velocity = Vector2(1500.0, 0.0)
	var o2b: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T3b off-center raw outside good zone",
		not _in_good_zone(ball.global_position, o2b.raw_dir, o2b.raw_speed, o2b.vz), "raw=%s" % str(o2b.raw_dir))
	_check("T3b off-center assist first bounce on table",
		_lands_on_table(ball.global_position, o2b.assisted_dir, o2b.ball_speed, o2b.vz), str(o2b.assisted_dir))
	var pwb: float = _post_wall_center_dist(ball.global_position, o2b.assisted_dir)
	_check("T3b off-center post-wall line hits table center", pwb < 8.0, "dist=%.1f" % pwb)

	# T4: assist=0 -> 完全无辅助
	GameConfig.assist_strength = 0.0
	var o3: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T4 assist=0 -> no correction",
		absf(o3.assist_angle) < 0.001 and o3.assisted_dir.is_equal_approx(o3.raw_dir),
		"angle=%.3f" % o3.assist_angle)

	# T5: assist=1 但 raw 已合法 -> 不干预
	GameConfig.assist_strength = 1.0
	var checked_valid := false
	for y0 in [0.0, -10.0, -25.0, -40.0, -55.0, -70.0, -90.0]:
		ball.global_position = Vector2(0.0, y0)
		zone.velocity = Vector2.ZERO
		var oc: Dictionary = HitSystem.compute(p1, zone, ball)
		if _in_good_zone(ball.global_position, oc.raw_dir, oc.raw_speed, oc.vz):
			_check("T5 no assist when raw already in good zone", absf(oc.assist_angle) < 0.001,
				"y0=%.0f angle=%.3f" % [y0, oc.assist_angle])
			checked_valid = true
			break
	if not checked_valid:
		print("  NOTE T5 skipped: 当前球速/vz 下, 没有任何起点能让 raw 落进好区 (D 太大)")

	# T6: assist=1, 静止触球(不做任何操作)也回桌
	ball.global_position = Vector2(0.0, -20.0)
	zone.velocity = Vector2.ZERO
	var o5: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T6 no-input touch lands in good zone",
		_in_good_zone(ball.global_position, o5.assisted_dir, o5.ball_speed, o5.vz),
		"assisted=%s spd=%.0f" % [str(o5.assisted_dir), o5.ball_speed])
	var pw6: float = _post_wall_center_dist(ball.global_position, o5.assisted_dir)
	_check("T6 assist aims at wall-mirror of center", pw6 < 8.0, "dist=%.1f" % pw6)

	# T7: 触发范围 = 内缩的"好区" (比整桌小得多)
	var edge_pt := Vector2(GameConfig.table_rect().position.x + 3.0, GameConfig.table_center.y)
	_check("T7 edge landing NOT in good zone",
		not HitSystem._lands_in_good_zone(Vector2.ZERO, edge_pt.normalized(), edge_pt.length()),
		"margin=%.0f" % GameConfig.assist_good_margin)
	var cp := GameConfig.table_center
	_check("T7 center landing in good zone",
		HitSystem._lands_in_good_zone(Vector2.ZERO, cp.normalized(), cp.length()), "center")

	# T8: 墙后连续第 2 次落桌 -> DOUBLE_BOUNCE (接球方输)
	ball.state = GameTypes.BallState.LIVE
	ball.reset_shot()
	ball.wall_since_hit = true
	ball._register_table_bounce()
	var after_first: bool = ball.state != GameTypes.BallState.DEAD
	ball._register_table_bounce()
	_check("T8 1st bounce allowed", after_first, "state=%d" % ball.state)
	_check("T8 2nd bounce -> DOUBLE_BOUNCE",
		ball.state == GameTypes.BallState.DEAD and _last_death == GameTypes.DeathReason.DOUBLE_BOUNCE,
		"state=%d reason=%d" % [ball.state, _last_death])
