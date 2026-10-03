class_name PlayerController
extends RigidBody2D
## 角色系统。
##
## 一个整体刚体纺锤 (无关节、无骨骼)，两端各有一个击球点。
## 移动和旋转用"游戏化控制"：直接限制速度/角速度的变化率，
## 保留惯性和碰撞推挤，但保证可操控 (设计文档第 6 节)。

signal ball_touched(player: PlayerController, hit_point: HitPoint)
signal collided_with_player(other: PlayerController, world_pos: Vector2)

const TOUCH_COOLDOWN := 0.06  ## 防止一帧内反复触发"触及"

var player_index: int = 1
var input_scheme: InputScheme = null
var ball: Ball = null
var rival: PlayerController = null  ## 对手 (由 Match 设置)
var ai_enabled: bool = false        ## 由 AI 驱动 (移动/击球/发球); 用于 "AI vs AI" 观察
var omniscient: bool = false        ## 万能模式: 接到球必落桌
var debug_last_error: String = ""   ## 最近一次 AI 失误表现 (Debug 用)

var hit_points: Array[HitPoint] = []
## 击球区在角色局部坐标系中的位移 (2D)。
## 直接复用鼠标拖动向量的数值，**不做 world->local 转换**。
var hit_zone_offset_local: Vector2 = Vector2.ZERO
var debug_mouse_world_delta: Vector2 = Vector2.ZERO    ## 鼠标原始拖动向量
var debug_hit_zone_local_delta: Vector2 = Vector2.ZERO ## 限幅后的目标局部偏移
var _last_touch_time: float = -10.0
var _prev_drag: Vector2 = Vector2.ZERO
var _prev_drag_valid: bool = false
var _body_color: Color = Color(0.31, 0.82, 0.77)
var _shape_poly: CollisionPolygon2D = null  ## 形状碰撞体 (与显示完全同步)

func setup(index: int, scheme: InputScheme) -> void:
	player_index = index
	input_scheme = scheme
	_body_color = Color(0.31, 0.82, 0.77) if index == 1 else Color(0.95, 0.43, 0.43)

func _ready() -> void:
	gravity_scale = 0.0
	mass = GameConfig.player_mass
	collision_layer = 1
	collision_mask = 3  # 撞其他玩家 (layer1) 和场地 (layer2)
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp = 0.0
	angular_damp = GameConfig.player_angular_damp  # 撞击旋转后逐渐停下

	# 形状碰撞体 (由形状方程采样成多边形, 与显示完全同步)
	_shape_poly = CollisionPolygon2D.new()
	_shape_poly.name = "ShapePoly"
	add_child(_shape_poly)

	for i in 2:
		var hp := HitPoint.new()
		hp.name = "HitPoint%s" % ("Front" if i == 0 else "Back")
		var s := -1.0 if i == 0 else 1.0
		hp.position = Vector2(0.0, s * _shape_half())
		add_child(hp)
		hit_points.append(hp)

	rebuild_shape()
	queue_redraw()

## 形状长轴半长 (判定区间距)。
func _shape_half() -> float:
	return GameConfig.player_shape_half()

## 重建碰撞多边形 + 判定区间距 (换形状时调用)。
func rebuild_shape() -> void:
	if _shape_poly != null:
		_shape_poly.polygon = GameConfig.player_shape_points()
	if hit_points.size() >= 2:
		var h: float = _shape_half()
		hit_points[0].position = Vector2(0.0, -h) + hit_zone_offset_local
		hit_points[1].position = Vector2(0.0, h) - hit_zone_offset_local
	queue_redraw()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var step: float = state.step
	# --- 平移：世界坐标。WASD 永远对应世界方向，与 rotation 无关 ---
	var dir: Vector2 = _desired_move_dir(state)
	var target_v: Vector2 = dir * GameConfig.move_speed
	var dv: Vector2 = target_v - state.linear_velocity
	state.linear_velocity += dv.limit_length(GameConfig.move_accel * step)

	# --- 击球区控制 (玩家=鼠标; AI=判定点收到中心, 像圆形 AI 那样用中心触球) ---
	if ai_enabled:
		for hp in hit_points:
			hp.position = Vector2.ZERO
	else:
		_update_controls(state, step)

	for i in state.get_contact_count():
		var obj: Object = state.get_contact_collider_object(i)
		if obj is PlayerController and obj != self:
			var local_pos: Vector2 = state.get_contact_local_position(i)
			collided_with_player.emit(obj, to_global(local_pos))

func _physics_process(_dt: float) -> void:
	if ball == null or ball.state != GameTypes.BallState.LIVE:
		return
	var now: float = _now()
	if now - _last_touch_time < TOUCH_COOLDOWN:
		return
	for hp in hit_points:
		if hp.touches(ball):
			_last_touch_time = now
			ball_touched.emit(self, hp)
			return

## 控制击球区位置 (玩家1) / (玩家2 临时) 键盘旋转。玩家1 的 rotation 完全交给物理。
func _update_controls(state: PhysicsDirectBodyState2D, step: float) -> void:
	if input_scheme == null:
		return
	if input_scheme.aim_mode != InputScheme.AimMode.MOUSE:
		return
	input_scheme.update_mouse(self)
	# 鼠标世界/屏幕拖动向量 -> 原样作为击球区"局部"位移向量 (故意不做转换/缩放)
	var raw: Vector2 = input_scheme.mouse_drag_screen(self)
	debug_mouse_world_delta = raw
	var drag: Vector2 = raw
	var dead: float = GameConfig.mouse_drag_deadzone
	if dead > 0.0:
		if drag.length() <= dead:
			drag = Vector2.ZERO
		else:
			drag = drag - drag.normalized() * dead
	var dragging: bool = input_scheme.is_dragging()
	# 挥动速度 = 未夹制的鼠标拖动速度 (经 hit_zone_drag_scale)，用于击球力度。
	# 这样判定区即使被 hit_zone_max_offset 夹住，继续甩鼠标仍有力度。
	var drag_vel: Vector2 = Vector2.ZERO
	if dragging:
		if _prev_drag_valid:
			drag_vel = (drag - _prev_drag) / maxf(step, 0.0001)
		_prev_drag = drag
		_prev_drag_valid = true
	else:
		_prev_drag_valid = false
	var swing_local: Vector2 = drag_vel * GameConfig.hit_zone_drag_scale

	var target_local: Vector2 = (drag * GameConfig.hit_zone_drag_scale) \
		.limit_length(GameConfig.hit_zone_max_offset)
	if dragging:
		hit_zone_offset_local = target_local  # 拖动中 1:1 跟随 (位置被 max_offset 夹)
	else:
		hit_zone_offset_local = hit_zone_offset_local.move_toward(Vector2.ZERO,
			GameConfig.hit_zone_return_speed * step)
	_update_hit_points()
	# 击球手势 = 鼠标挥动 (两端共用同一个世界挥动速度):
	#   两端"位置"仍反向移动, 但"挥动速度"一致, 这样鼠标向下猛拉=防守 与用哪端无关。
	if hit_points.size() >= 2:
		var sw: Vector2 = swing_local.rotated(rotation)
		hit_points[0].swing_velocity = sw
		hit_points[1].swing_velocity = sw
	debug_hit_zone_local_delta = target_local
	# 强回正：快速转向"面向桌中心" (仍是物理刚体，撞歪会被物理短暂影响后拉回)
	if GameConfig.base_face_enabled:
		var base: float = (GameConfig.table_center - state.transform.origin).angle()
		# 鼠标左右拖动时，身体跟随做"有限的小幅旋转"，让判定区移动更自然
		if input_scheme.is_dragging():
			var dx: float = input_scheme.mouse_drag_screen_x(self)
			base += clampf(dx * GameConfig.drag_rot_sensitivity,
				-GameConfig.drag_rot_max, GameConfig.drag_rot_max)
		var err: float = wrapf(base - state.transform.get_rotation(), -PI, PI)
		var desired_w: float = clampf(err * GameConfig.base_face_response,
			-GameConfig.base_face_max_angular_velocity, GameConfig.base_face_max_angular_velocity)
		var face_accel: float = GameConfig.base_face_acceleration * step
		state.angular_velocity += clampf(desired_w - state.angular_velocity, -face_accel, face_accel)

## 两个击球区在角色局部坐标系中反向位移 (A=+delta, B=-delta)，再经 Transform 转世界。
func _update_hit_points() -> void:
	if hit_points.size() < 2:
		return
	var l: float = _shape_half()
	hit_points[0].position = Vector2(0.0, -l) + hit_zone_offset_local  # 前端 A
	hit_points[1].position = Vector2(0.0, l) - hit_zone_offset_local   # 后端 B

## 期望的世界移动方向 (默认来自输入; ai_enabled 时由 AI 决定)。
func _desired_move_dir(state: PhysicsDirectBodyState2D) -> Vector2:
	if ai_enabled:
		var target: Vector2 = _target_point()
		var d: Vector2 = target - state.transform.origin
		return d.normalized() if d.length() > 6.0 else Vector2.ZERO
	return input_scheme.move_vector() if input_scheme != null else Vector2.ZERO

## 击球计算 (默认走 HitSystem; ai_enabled 时走智能击球)。
func compute_hit(hit_point: HitPoint, b: Ball) -> Dictionary:
	if ai_enabled:
		return _smart_shot(b.global_position)
	return HitSystem.compute(self, hit_point, b)

## 发球计算 (默认沿朝向; ai_enabled 时走智能发球)。
func compute_serve(b: Ball) -> Dictionary:
	if ai_enabled:
		return _smart_shot(b.global_position)
	var facing: Vector2 = Vector2.RIGHT.rotated(rotation)
	var speed: float = GameConfig.hit_speed_v0
	return {
		"velocity": facing * speed, "vz": GameConfig.hit_vz_v0, "strength": 1.0,
		"ball_speed": speed, "raw_speed": speed, "zone_speed": 0.0,
		"zone_world": b.global_position, "zone_vel": Vector2.ZERO,
		"raw_dir": facing, "assisted_dir": facing, "assist_angle": 0.0, "assist_speed_delta": 0.0,
	}

func reset_to(pos: Vector2, rot: float) -> void:
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	global_position = pos
	rotation = rot

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _draw() -> void:
	var pts: PackedVector2Array = GameConfig.player_shape_points()
	if pts.size() >= 3:
		draw_colored_polygon(pts, _body_color)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(1, 1, 1, 0.35), 2.0)
	# 朝向标记: 局部 +x 为"前方" (面向桌中心 / 发球方向)
	draw_line(Vector2.ZERO, Vector2(_shape_half() * 0.4, 0.0), Color(1, 1, 1, 0.6), 4.0)
	draw_circle(Vector2.ZERO, 5.0, Color(1, 1, 1, 0.85))

# ------------------------------------------------------------
#  AI 逻辑 (ai_enabled 时使用)。原在 AiPlayer, 上移以便任意角色都能挂 AI
#  (P3 "AI vs AI" / P4 "AI 试战" 的基础)。
# ------------------------------------------------------------
func _target_point() -> Vector2:
	if ball == null or ball.state != GameTypes.BallState.LIVE:
		return global_position  # 球不在场(发球/死球): 原地待命
	# 自己刚打完这球 -> 切"防阻挡模式": 绕开对手的接球走廊, 避免被判阻挡
	if ball.last_hitter == self:
		return _anti_block_target()
	# 否则我是接球方 -> 追可接住点
	var pred: Dictionary = ball.predict_catchable()
	if pred.found:
		return pred.point
	return ball.global_position

## 防阻挡：绕到"对手 -> 预计接球点"这条走廊的侧面去。
func _anti_block_target() -> Vector2:
	if rival == null:
		return global_position
	var pred: Dictionary = ball.predict_catchable()
	var p: Vector2 = pred.point if pred.found else ball.global_position
	var h: Vector2 = rival.global_position
	var mid: Vector2 = (h + p) * 0.5
	var seg: Vector2 = p - h
	var perp: Vector2 = Vector2(-seg.y, seg.x).normalized() if seg.length() > 1.0 else Vector2(0.0, 1.0)
	if (global_position - mid).dot(perp) < 0.0:
		perp = -perp
	var target: Vector2 = mid + perp * GameConfig.ai_avoid_distance
	var ar: Rect2 = GameConfig.arena_rect().grow(-40.0)
	return Vector2(clampf(target.x, ar.position.x, ar.end.x), clampf(target.y, ar.position.y, ar.end.y))

## 智能击球/发球: 瞄准"桌面随机 x 关于墙的镜像点", 保证撞墙后落桌; 力度/vz 在玩家上下限内。
func _smart_shot(from: Vector2) -> Dictionary:
	var tr := GameConfig.table_rect()
	var m: float = maxf(GameConfig.assist_good_margin, 20.0)
	var tx: float = randf_range(tr.position.x + m, tr.end.x - m)
	var aim := Vector2(tx, 2.0 * GameConfig.wall_inner_y() - GameConfig.table_center.y)
	var d: Vector2 = aim - from
	var dist: float = maxf(d.length(), 1.0)
	var dir: Vector2 = d / dist
	# vz 限制在"玩家的上下限"内 (AI 不作弊)
	var vz: float = randf_range(GameConfig.hit_vz_min, GameConfig.hit_vz_max)
	# 由 vz 反推水平初速, 使球正好够到镜像点 (z0=桌高时 = dist*g/(2*vz))
	var z0: float = maxf(ball.z, GameConfig.table_z) if ball != null else GameConfig.table_z
	var disc: float = vz * vz + 2.0 * GameConfig.ball_gravity * (z0 - GameConfig.table_z)
	var t_flight: float = (vz + sqrt(maxf(disc, 0.0))) / maxf(GameConfig.ball_gravity, 1.0)
	var speed: float = dist / maxf(t_flight, 0.0001)
	if omniscient:
		# 万能模式: 直接给够速度, 不夹到玩家上限 -> 保证一定能打到桌
		speed = clampf(speed, 1.0, GameConfig.hit_speed_max * 4.0)
	else:
		speed = clampf(speed, GameConfig.hit_speed_min, GameConfig.hit_speed_max)
	# 扣杀 (仅当 F1 开关打开): 球够高 + 概率成功 -> vz 向下、速度由它反推(很快)
	debug_last_error = ""
	var ai_smash: bool = GameConfig.debug_ai_smash and ball != null \
		and ball.z >= GameConfig.ai_smash_height_min \
		and randf() < GameConfig.smash_success_chance
	if ai_smash:
		vz = GameConfig.smash_vz
		var dsc: float = vz * vz + 2.0 * GameConfig.ball_gravity * (z0 - GameConfig.table_z)
		var tfl: float = (vz + sqrt(maxf(dsc, 0.0))) / maxf(GameConfig.ball_gravity, 1.0)
		speed = clampf(dist / maxf(tfl, 0.0001) * GameConfig.smash_speed_mult,
			1.0, GameConfig.hit_speed_max * 4.0)
		debug_last_error = "扣杀"
	# 失误表现：按 ai_error_chance 概率触发 (0=永不失误; 万能模式不失误)
	elif not omniscient and randf() < GameConfig.ai_error_chance:
		match randi() % 4:
			0:  # 瞄偏
				dir = dir.rotated(deg_to_rad(randf_range(-GameConfig.ai_error_aim_deg, GameConfig.ai_error_aim_deg)))
				debug_last_error = "瞄偏"
			1:  # 太轻
				speed *= GameConfig.ai_error_power_min
				debug_last_error = "太轻"
			2:  # 太重
				speed *= GameConfig.ai_error_power_max
				debug_last_error = "太重"
			3:  # 打反
				dir = -dir
				debug_last_error = "打反"
	return {
		"velocity": dir * speed, "vz": vz, "strength": 1.0,
		"ball_speed": speed, "raw_speed": speed, "zone_speed": 0.0,
		"zone_world": from, "zone_vel": Vector2.ZERO,
		"raw_dir": dir, "assisted_dir": dir, "assist_angle": 0.0, "assist_speed_delta": 0.0,
		"is_smash": ai_smash,
	}
