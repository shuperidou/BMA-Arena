extends Node
## 击球系统单元测试 (直接调用 HitSystem，不经物理)。
## 运行: godot --headless --path <project> res://scenes/HitTest.tscn

var main_node: Node
var p1: PlayerController
var ball: Ball
var zone: HitPoint
var failures: int = 0
var _last_death: int = -1

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	p1 = main_node.players[0]
	ball = main_node.ball
	zone = p1.hit_points[0]
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

## 设置判定区速度 (同时写 velocity 和 swing_velocity, HitSystem 用后者)。
func _setv(v: Vector2) -> void:
	zone.velocity = v
	zone.swing_velocity = v

func _run() -> void:
	p1.global_position = Vector2(0.0, -14.0)
	p1.rotation = -PI / 2.0  # 面向桌中心 (局部 +x = 世界上方)
	GameConfig.assist_strength = 0.0  # 先关辅助, 单独测力度/方向映射
	GameConfig.defense_perp_threshold = 1e9  # 先关防守判定, 单独测其它 (T11 再打开)

	# T1: 击球区静止 -> 力度最低, 球速=min, 方向≈面向
	ball.global_position = Vector2(0.0, -60.0)
	_setv(Vector2.ZERO)
	var o0: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T1 min strength", o0.strength < 0.01, "strength=%.3f" % o0.strength)
	_check("T1 ball speed == min", absf(o0.ball_speed - GameConfig.hit_speed_min) < 1.0, "spd=%.0f" % o0.ball_speed)
	_check("T1 raw dir ≈ facing(up)", o0.raw_dir.dot(Vector2(0.0, -1.0)) > 0.9, str(o0.raw_dir))

	# T2: 快速挥动 -> 力度高, 球速=min~max 之间且更大
	_setv(Vector2(0.0, -1500.0))
	var o1: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T2 high strength", o1.strength > 0.9, "strength=%.3f" % o1.strength)
	_check("T2 ball speed <= max", o1.ball_speed <= GameConfig.hit_speed_max + 1.0, "spd=%.0f" % o1.ball_speed)
	_check("T2 speed increases", o1.ball_speed > o0.ball_speed, "%.0f > %.0f" % [o1.ball_speed, o0.ball_speed])

	# T3: assist=1, raw 出界 -> 完全辅助后落桌
	GameConfig.assist_strength = 1.0
	ball.global_position = Vector2(0.0, -30.0)
	_setv(Vector2(1500.0, 0.0))  # 向右挥 -> raw 偏右上, 会飞出远端
	var o2: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T3 raw outside good zone",
		not _in_good_zone(ball.global_position, o2.raw_dir, o2.raw_speed, o2.vz), "raw=%s" % str(o2.raw_dir))
	_check("T3 assist=1 speed within [assist_min, max]",
		o2.ball_speed >= GameConfig.hit_speed_min - 1.0 and o2.ball_speed <= GameConfig.hit_speed_max + 1.0,
		"spd=%.0f assist_min=%.0f" % [o2.ball_speed, GameConfig.hit_speed_min])
	var pw3: float = _post_wall_center_dist(ball.global_position, o2.assisted_dir)
	_check("T3 assist aims so post-wall line hits table center (mirror)", pw3 < 8.0, "dist=%.1f" % pw3)

	# T3b: 偏心球 -> 无辅助会飞出, 辅助后墙后路径仍经过桌中心 (真正的镜面验证)
	ball.global_position = Vector2(-120.0, -30.0)
	_setv(Vector2(1500.0, 0.0))
	var o2b: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T3b off-center raw outside good zone",
		not _in_good_zone(ball.global_position, o2b.raw_dir, o2b.raw_speed, o2b.vz), "raw=%s" % str(o2b.raw_dir))
	_check("T3b off-center assist speed within limits",
		o2b.ball_speed >= GameConfig.hit_speed_min - 1.0 and o2b.ball_speed <= GameConfig.hit_speed_max + 1.0,
		"spd=%.0f" % o2b.ball_speed)
	var pwb: float = _post_wall_center_dist(ball.global_position, o2b.assisted_dir)
	_check("T3b off-center post-wall line hits table center", pwb < 8.0, "dist=%.1f" % pwb)

	# T4: assist=0 -> 完全无辅助
	GameConfig.assist_strength = 0.0
	_setv(Vector2(0.0, -1500.0))  # 沿朝向(非防守), 单独测 assist=0
	var o3: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T4 assist=0 -> no correction",
		absf(o3.assist_angle) < 0.001 and o3.assisted_dir.is_equal_approx(o3.raw_dir),
		"angle=%.3f" % o3.assist_angle)

	# T5: assist=1 但 raw 已合法 -> 不干预
	GameConfig.assist_strength = 1.0
	var checked_valid := false
	for y0 in [0.0, -10.0, -25.0, -40.0, -55.0, -70.0, -90.0]:
		ball.global_position = Vector2(0.0, y0)
		_setv(Vector2.ZERO)
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
	_setv(Vector2.ZERO)
	var o5: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T6 no-input touch speed within limits",
		o5.ball_speed >= GameConfig.hit_speed_min - 1.0 and o5.ball_speed <= GameConfig.hit_speed_max + 1.0,
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

	# T9: AI 击球力度/vz 必须落在"玩家的上下限"内, 且角度有变化
	GameConfig.ai_error_chance = 0.0  # 失误会故意越界, 这里先关掉
	var ai: AiPlayer = main_node.players[1]
	var in_limits := true
	var angle0: float = 999.0
	var varied := false
	for i in 16:
		ball.global_position = Vector2(randf_range(-120.0, 120.0), randf_range(-60.0, -20.0))
		var oa: Dictionary = ai.compute_hit(ai.hit_points[0], ball)
		var spd: float = oa.ball_speed
		var vz: float = oa.vz
		if spd < GameConfig.hit_speed_min - 1.0 or spd > GameConfig.hit_speed_max + 1.0 \
				or vz < GameConfig.hit_vz_min - 1.0 or vz > GameConfig.hit_vz_max + 1.0:
			in_limits = false
		var d: Vector2 = oa.velocity.normalized()
		if i == 0:
			angle0 = d.angle()
		elif absf(wrapf(d.angle() - angle0, -PI, PI)) > 0.001:
			varied = true
	_check("T9 AI strength/vz within player limits", in_limits,
		"speed=[%.0f,%.0f] vz=[%.0f,%.0f]" % [GameConfig.hit_speed_min, GameConfig.hit_speed_max,
			GameConfig.hit_vz_min, GameConfig.hit_vz_max])
	_check("T9 AI varies hit angle", varied, "angle0=%.2f" % angle0)

	# T10: 判定区速度分解 —— 沿朝向分量 -> 球速; 垂直分量 -> vy (两者垂直)
	p1.global_position = Vector2(0.0, -14.0)
	p1.rotation = -PI / 2.0          # 面向桌(上), facing=(0,-1), perp=(1,0)
	ball.global_position = Vector2(0.0, -60.0)
	_setv(Vector2(0.0, -1000.0))   # 沿朝向的挥动
	var oa: Dictionary = HitSystem.compute(p1, zone, ball)
	_setv(Vector2(1000.0, 0.0))    # 垂直朝向的挥动 (鼠标向下)
	var ob: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T10 沿朝向挥动 -> 球速更大", oa.ball_speed > ob.ball_speed,
		"along=%.0f perp=%.0f" % [oa.ball_speed, ob.ball_speed])
	_check("T10 垂直挥动 -> vy 更大", ob.vz > oa.vz,
		"along_vz=%.0f perp_vz=%.0f" % [oa.vz, ob.vz])

	# T11: 防守姿态 (向下猛拉) -> 按概率救球到墙镜像
	p1.global_position = Vector2(0.0, -14.0)
	p1.rotation = -PI / 2.0
	ball.global_position = Vector2(0.0, -60.0)
	GameConfig.defense_perp_threshold = 400.0
	GameConfig.defense_save_chance = 1.0
	_setv(Vector2(800.0, 0.0))   # v_perp=800 > 阈值 -> 防守
	var od: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T11 防守(必成功) -> 瞄准墙镜像",
		od.is_defense and od.defense_saved and _post_wall_center_dist(ball.global_position, od.assisted_dir) < 8.0,
		"defense=%s saved=%s dir=%s" % [str(od.is_defense), str(od.defense_saved), str(od.assisted_dir)])
	GameConfig.defense_save_chance = 0.0
	_setv(Vector2(800.0, 0.0))
	var od2: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T11 防守(必失败) -> 用原始方向",
		od2.is_defense and not od2.defense_saved and od2.assisted_dir.is_equal_approx(od2.raw_dir),
		"defense=%s saved=%s" % [str(od2.is_defense), str(od2.defense_saved)])
	# T11c: 水平分量明显超过阈值 -> 不算防守 (按配置比例自适应)
	GameConfig.defense_save_chance = 1.0
	var vp: float = 800.0
	var va: float = vp * (GameConfig.defense_max_along_ratio + 0.5)  # 明确超过阈值
	_setv(Vector2(vp, -va))  # v_perp=vp, v_along=va
	var od3: Dictionary = HitSystem.compute(p1, zone, ball)
	_check("T11c 水平太大 -> 不算防守", not od3.is_defense,
		"defense=%s v_along=%.0f v_perp=%.0f ratio=%.2f" % [str(od3.is_defense), va, vp, GameConfig.defense_max_along_ratio])
	GameConfig.defense_save_chance = 0.6
