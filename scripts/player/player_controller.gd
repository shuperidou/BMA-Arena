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
var _ai_stuck_frames: int = 0       ## AI 连续"想动却动不了"的帧数 (脱困用)
var _ai_aim_x: float = 0.0          ## AI 本次进攻落点 x (换对手击球时重选) -> 决定方向
var _ai_aim_y: float = 0.0          ## AI 本次进攻落点 y (深度; 高手会据 hit_speed 区间自动换算)
var _ai_face_dir: Vector2 = Vector2.ZERO  ## 高手/大师: 解析求得的出球方向 (供朝向跟随)
var _ai_bait_x: float = 0.0         ## 假动作诱饵 x (与真实落点相反侧)
var _ai_last_hitter_seen: Node = null
var _ai_smooth_target: Vector2 = Vector2.ZERO   ## 平滑后的走位目标 (抗抖)
var _ai_smooth_ready: bool = false
var _ai_post_target: Vector2 = Vector2.ZERO     ## 打完球后的"防阻挡"目标 (每拍只算一次)
var _ai_post_ready: bool = false
var _ai_arm_cur: Vector2 = Vector2.ZERO          ## 手臂当前伸出量 (局部), 受速度/加速度上限约束
var _ai_arm_vel: Vector2 = Vector2.ZERO          ## 手臂伸出速度

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

## 挥拍力量 (0..1): 由"沿朝向的挥速"经力度曲线算出 (仅供判定区填色)。
func _swing_power01(sw: Vector2) -> float:
	var facing: Vector2 = Vector2.RIGHT.rotated(rotation)
	var ref: float = maxf(GameConfig.hit_zone_speed_ref, 1.0)
	var t: float = clampf(maxf(sw.dot(facing), 0.0) / ref, 0.0, 1.0)
	return pow(t, maxf(GameConfig.hit_speed_curve, 0.05))

## P4 体型代价: 移动速度倍率 (越大越慢)。只作用玩家(索引1), AI 不继承玩家变异。
func _size_speed_mult() -> float:
	if player_index != 1:
		return 1.0
	return pow(maxf(GameConfig.player_size_scale, 0.05), -GameConfig.size_move_exponent)

## P4 体型代价: 转身速度倍率 (越大越难转)。只作用玩家(索引1)。
func _size_turn_mult() -> float:
	if player_index != 1:
		return 1.0
	return pow(maxf(GameConfig.player_size_scale, 0.05), -GameConfig.size_turn_exponent)

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
	# P4 体型代价: 越大 -> 移动越慢 (speed ∝ size^(-exponent))
	var target_v: Vector2 = dir * GameConfig.move_speed * _size_speed_mult()
	var dv: Vector2 = target_v - state.linear_velocity
	state.linear_velocity += dv.limit_length(GameConfig.move_accel * step)

	# --- 击球区控制 (玩家=鼠标; AI=判定点收到中心, 像圆形 AI 那样用中心触球) ---
	if ai_enabled:
		# 对手换了击球 -> 重新选本次落点 (方向由朝向决定, 见 _ai_face_point)
		if ball != null and ball.last_hitter != _ai_last_hitter_seen:
			_ai_last_hitter_seen = ball.last_hitter
			if ball.last_hitter != self:
				_ai_pick_aim()
		# AI: 判定点收到中心, 每帧像甩鼠标一样设好"挥动速度"; 命中走同一 HitSystem。
		var sw2: Vector2 = _ai_desired_swing()
		# "手臂": 判定点朝球方向伸出 (最多 ai_arm_len), 让 AI 能越桌够球
		# 1) 计算"想要的"伸手: 朝球方向, 最多 ai_arm_len。
		#    时机门: 必须"本方可击(returnable)且球已过顶点(vz<=0)"才伸 -> 球要先升到顶点再落下, 才有合理滞空。
		var want: Vector2 = Vector2.ZERO
		if ball != null and ball.returnable and ball.z >= GameConfig.ai_min_hit_height:
			want = (ball.global_position - global_position).rotated(-rotation).limit_length(GameConfig.ai_arm_len)
		# 2) 施加速度/加速度上限 (和身体移动同一套), 让手臂连续伸出/缩回, 而不是瞬移
		var tv: Vector2 = (want - _ai_arm_cur).limit_length(GameConfig.ai_arm_speed)
		var arm_dv: Vector2 = tv - _ai_arm_vel
		_ai_arm_vel += arm_dv.limit_length(GameConfig.ai_arm_accel * step)
		_ai_arm_cur = (_ai_arm_cur + _ai_arm_vel * step).limit_length(GameConfig.ai_arm_len)
		for hp in hit_points:
			hp.position = _ai_arm_cur
			hp.reach = GameConfig.ai_hit_reach
			hp.swing_velocity = sw2
			hp.power01 = _swing_power01(sw2)
		_recenter_body(state, step, _ai_face_point(), 0.0)
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
		var p01: float = _swing_power01(sw)
		hit_points[0].swing_velocity = sw
		hit_points[1].swing_velocity = sw
		hit_points[0].power01 = p01
		hit_points[1].power01 = p01
	debug_hit_zone_local_delta = target_local
	# 鼠标左右拖动时，身体跟随做"有限的小幅旋转"
	var drag_rad: float = 0.0
	if GameConfig.base_face_enabled and input_scheme.is_dragging():
		var dx: float = input_scheme.mouse_drag_screen_x(self)
		drag_rad = clampf(dx * GameConfig.drag_rot_sensitivity,
			-GameConfig.drag_rot_max, GameConfig.drag_rot_max)
	_recenter_body(state, step, GameConfig.table_center, drag_rad)

## 强回正: 快速转向"面向桌中心" (drag_rad = 鼠标拖动带来的小偏角; AI 传 0)。
func _recenter_body(state: PhysicsDirectBodyState2D, step: float, aim_point: Vector2, drag_rad: float) -> void:
	if not GameConfig.base_face_enabled:
		return
	var base: float = (aim_point - state.transform.origin).angle() + drag_rad
	var err: float = wrapf(base - state.transform.get_rotation(), -PI, PI)
	# P4 体型代价: 越大 -> 转身越难 (turn ∝ size^(-exponent))
	var tmult: float = _size_turn_mult()
	var desired_w: float = clampf(err * GameConfig.base_face_response,
		-GameConfig.base_face_max_angular_velocity, GameConfig.base_face_max_angular_velocity) * tmult
	var face_accel: float = GameConfig.base_face_acceleration * step * tmult
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
		return _ai_move_dir(state)
	return input_scheme.move_vector() if input_scheme != null else Vector2.ZERO

## AI 走位: 趋目标 + 躲对手碰撞箱 + 卡住脱困。
func _ai_move_dir(state: PhysicsDirectBodyState2D) -> Vector2:
	var from: Vector2 = state.transform.origin
	var raw_target: Vector2 = _target_point()
	# 目标平滑 (抗抖): 每帧向真实目标插值, 避免目标逐帧跳动导致"来回跑"
	if not _ai_smooth_ready:
		_ai_smooth_target = raw_target
		_ai_smooth_ready = true
	else:
		_ai_smooth_target = _ai_smooth_target.lerp(raw_target, GameConfig.ai_target_smooth)
	var target: Vector2 = _ai_smooth_target
	var to: Vector2 = target - from
	if to.length() < GameConfig.ai_arrive_dist:
		_ai_stuck_frames = 0
		return Vector2.ZERO
	var dir: Vector2 = to.normalized()
	# 躲对手: 靠太近且方向朝它 -> 加侧向分量绕开
	if rival != null:
		var to_r: Vector2 = rival.global_position - from
		var rd: float = to_r.length()
		if rd < GameConfig.ai_personal_space and rd > 0.1 \
				and to_r.normalized().dot(dir) > 0.3:
			var side: Vector2 = Vector2(-to_r.y, to_r.x).normalized()
			if side.dot(to) < 0.0:
				side = -side
			dir = (dir + side * GameConfig.ai_avoid_gain).normalized()
	# 绕桌角: 直线路径真的被桌子挡住时才绕 (不要用"沿边滑", 那会阻止 AI 靠近桌子)
	dir = _route_around_table(dir, from, target)
	# 卡住脱困: 想动却几乎动不了 -> 沿垂直方向蹭出去
	if state.linear_velocity.length() < GameConfig.ai_stuck_velocity:
		_ai_stuck_frames += 1
	else:
		_ai_stuck_frames = 0
	if _ai_stuck_frames >= GameConfig.ai_unstick_frames:
		var perp: Vector2 = Vector2(-to.y, to.x).normalized()
		dir = (dir + perp * GameConfig.ai_unstick_gain).normalized()
	return dir

## 击球计算: 玩家与 AI 走**同一套 HitSystem**。AI 通过自己每帧设置的 swing_velocity
## 参与判定 (像玩家甩鼠标), 不再有特权输出。
func compute_hit(hit_point: HitPoint, b: Ball) -> Dictionary:
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
	_ai_arm_cur = Vector2.ZERO
	_ai_arm_vel = Vector2.ZERO
	_ai_smooth_ready = false
	_ai_post_ready = false

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
	# 自己刚打完这球 -> 切"防阻挡模式": 绕开对手的接球走廊 (每拍只算一次, 免得目标和球一起乱动)
	if ball.last_hitter == self:
		if not _ai_post_ready:
			_ai_post_target = _anti_block_target()
			_ai_post_ready = true
		return _ai_post_target
	_ai_post_ready = false
	# 否则我是接球方 -> 追可接住点 (投影到可达区域, 见 _clamp_reachable)
	var pred: Dictionary = ball.predict_catchable()
	if pred.found:
		return _clamp_reachable(pred.point)
	return _clamp_reachable(ball.global_position)

## 把目标点投影到"可达区域" (桌/边界之外)。球可接点在桌正上方而玩家进不去桌子,
## 所以 AI 贴桌沿站, 用判定半径伸过去够球 —— 避免直线怼桌卡死。
func _clamp_reachable(p: Vector2) -> Vector2:
	var clr: float = GameConfig.ai_body_clearance
	var ar: Rect2 = GameConfig.arena_rect().grow(-clr)
	var q := Vector2(clampf(p.x, ar.position.x, ar.end.x), clampf(p.y, ar.position.y, ar.end.y))
	var tr: Rect2 = GameConfig.table_block_rect().grow(clr)
	if tr.has_point(q):
		# 推出到"AI 所在的纵向一侧"(玩家通常在桌下方): 只调 y, 保留 x -> 站到桌前、与球对齐, 手臂上够。
		q.y = tr.end.y if global_position.y > GameConfig.table_center.y else tr.position.y
	return q

## (已移除 _slide_along_table: 它把"朝桌分量"删掉, 会让 AI 永远靠近不了桌子 -> 来回跑够不到。)

## 线段 a-b 是否与矩形 r 相交 (路径是否被桌子挡)。
func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var p0 := r.position
	var p1 := Vector2(r.end.x, r.position.y)
	var p2 := r.end
	var p3 := Vector2(r.position.x, r.end.y)
	return Geometry2D.segment_intersects_segment(a, b, p0, p1) != null \
		or Geometry2D.segment_intersects_segment(a, b, p1, p2) != null \
		or Geometry2D.segment_intersects_segment(a, b, p2, p3) != null \
		or Geometry2D.segment_intersects_segment(a, b, p3, p0) != null

## 若直线路径被桌子挡住, 绕到"最省路"的桌角 (只处理这一格桌子, 足够)。
func _route_around_table(dir: Vector2, from: Vector2, target: Vector2) -> Vector2:
	var tr: Rect2 = GameConfig.table_block_rect().grow(GameConfig.ai_body_clearance)
	# 仅当"路径中点落在桌内"才认为真的被挡 (避免目标恰在桌边时的误触发)
	if not tr.has_point((from + target) * 0.5):
		return dir
	var g2: float = 6.0
	var cors: Array[Vector2] = [
		tr.position - Vector2(g2, g2),
		Vector2(tr.end.x + g2, tr.position.y - g2),
		tr.end + Vector2(g2, g2),
		Vector2(tr.position.x - g2, tr.end.y + g2)]
	var best: Vector2 = from
	var best_cost: float = 1e18
	for c in cors:
		if _seg_hits_rect(from, c, tr):
			continue
		var cost: float = from.distance_to(c) + c.distance_to(target)
		if cost < best_cost:
			best_cost = cost
			best = c
	if best == from:
		return dir
	return (best - from).normalized()

## 换一次进攻落点 (好区内)。达到"普通"以上会挑对手对侧 (逼他跑); 并备一个反侧诱饵做假动作。
func _ai_pick_aim() -> void:
	var tr := GameConfig.table_rect()
	var m: float = maxf(GameConfig.assist_good_margin, 20.0)
	var lo: float = tr.position.x + m
	var hi: float = tr.end.x - m
	# 深度"稳定带" (不贴边)
	var d_lo: float = tr.position.y + tr.size.y * GameConfig.ai_shot_band_frac
	var d_hi: float = tr.end.y - tr.size.y * GameConfig.ai_shot_band_frac
	var cx: float = GameConfig.table_center.x
	var opp_x: float = rival.global_position.x if rival != null else cx
	var far_x: float = hi if opp_x < 0.0 else lo          # 对手反侧
	var near_x: float = lo if opp_x < 0.0 else hi         # 对手同侧
	if GameConfig.ai_diverse:
		# 多样化打法: 每拍随机选横向套路 + 深浅套路
		match randi() % 4:
			0: _ai_aim_x = far_x + randf_range(-m, m)     # 对角 (逼跑)
			1: _ai_aim_x = near_x + randf_range(-m, m)    # 直线 (出其不意)
			2: _ai_aim_x = cx + randf_range(-m, m)        # 中路
			_: _ai_aim_x = randf_range(lo, hi)            # 纯随机
		var mid_y: float = (d_lo + d_hi) * 0.5
		match randi() % 3:
			0: _ai_aim_y = randf_range(d_lo, mid_y)       # 短 (靠墙侧)
			1: _ai_aim_y = randf_range(mid_y, d_hi)       # 深 (靠玩家侧)
			_: _ai_aim_y = randf_range(d_lo, d_hi)        # 随机
	elif GameConfig.ai_smart_aim() and rival != null:
		_ai_aim_x = clampf(far_x + randf_range(-m, m), lo, hi)
		_ai_aim_y = randf_range(d_lo, d_hi)
	else:
		_ai_aim_x = randf_range(lo, hi)
		_ai_aim_y = GameConfig.table_center.y
	_ai_aim_x = clampf(_ai_aim_x, lo, hi)
	_ai_aim_y = clampf(_ai_aim_y, d_lo, d_hi)
	_ai_bait_x = (lo + hi) - _ai_aim_x                    # 诱饵 = 真实落点的反侧

## AI 朝向点 = 落点关于墙的镜像。朝向它 -> raw_dir 指向镜像 -> 撞墙后落点 = 目标 x。
## 假动作: 球还远时先朝向"诱饵"(反侧), 球近到阈值内再切真实落点 (骗对手先动)。
func _ai_face_point() -> Vector2:
	# 高手/大师: 朝向 = 解析求得的出球方向 (让 raw_dir ≈ facing 指向目标)
	if GameConfig.ai_level >= 3 and _ai_face_dir.length() > 0.1:
		return global_position + _ai_face_dir * 240.0
	var x: float = _ai_aim_x
	if GameConfig.ai_feint() and ball != null \
			and global_position.distance_to(ball.global_position) > GameConfig.ai_feint_switch_dist:
		x = _ai_bait_x
	return Vector2(x, 2.0 * GameConfig.wall_inner_y() - _ai_aim_y)

## AI 的"挥动": 反推出能打到桌上目标的判定区速度 (world) —— 走与玩家相同的 HitSystem 判定。
## 目标 = 本次落点 _ai_aim_x 的墙镜像; 由 vz 反推所需球速 -> 反推 strength -> v_along。
func _ai_desired_swing() -> Vector2:
	if ball == null or ball.state != GameTypes.BallState.LIVE:
		return Vector2.ZERO
	var facing: Vector2 = Vector2.RIGHT.rotated(rotation)
	var perp: Vector2 = facing.rotated(PI * 0.5)
	var ref: float = maxf(GameConfig.hit_zone_speed_ref, 1.0)
	var curve: float = maxf(GameConfig.hit_speed_curve, 0.05)
	var from: Vector2 = ball.global_position
	var tr := GameConfig.table_rect()
	var mm: float = maxf(GameConfig.assist_good_margin, 20.0)
	var tx: float = clampf(_ai_aim_x, tr.position.x + mm, tr.end.x - mm)
	var z0: float = maxf(ball.z, GameConfig.table_z)
	# 把 hit_speed_min/max 当参数用 (改 hit_speed 时 AI 依然有效)
	var s_min: float = maxf(GameConfig.hit_speed_min, 1.0)
	var s_max: float = maxf(GameConfig.hit_speed_max, s_min + 1.0)
	var g: float = GameConfig.ball_gravity
	var w_y: float = GameConfig.wall_inner_y()
	var gain: float = maxf(GameConfig.hit_vz_perp_gain, 1.0)
	var v_perp: float = 0.0
	var strength: float = 0.0
	if GameConfig.ai_level >= 3:
		# 高手/大师: 解析反解落点。选桌内"稳定带"目标 T=(tx, aim_y), 反解(方向,球速,vz)使球恰落在 T。
		# 弹道(含墙反射损耗 wbf): t=(vz+sqrt(vz²+2g(z0-tz)))/g; 撞墙前 vx 不变, vy 反号×wbf。
		#   T_x = from.x + vx*t ;  T_y = wall_y + |vy|*wbf*(t - t_wall), t_wall=(wall_y-from.y)/vy
		#   => vx=A, |vy|=B, speed=sqrt(A²+B²); 遍历 vz 取使 speed∈[hit_speed_min,max] 者。
		var band_lo: float = tr.position.y + tr.size.y * GameConfig.ai_shot_band_frac
		var band_hi: float = tr.end.y - tr.size.y * GameConfig.ai_shot_band_frac
		var aim_y: float = clampf(_ai_aim_y, band_lo, band_hi)
		_ai_aim_y = aim_y
		var wbf: float = clampf(GameConfig.wall_bounce_factor, 0.05, 1.0)
		var nz: int = 24
		var best_err: float = 1e18
		var vz_pick: float = GameConfig.hit_vz_min
		var face_dir: Vector2 = facing
		for kz in nz:
			var cz: float = lerpf(GameConfig.hit_vz_min, GameConfig.hit_vz_max, float(kz) / float(nz - 1))
			var dsc: float = cz * cz + 2.0 * g * (z0 - GameConfig.table_z)
			var tl: float = (cz + sqrt(maxf(dsc, 0.0))) / maxf(g, 1.0)
			if tl <= 0.001:
				continue
			var aa: float = (tx - from.x) / tl
			var bb: float = ((aim_y - w_y) + wbf * (w_y - from.y)) / (wbf * tl)
			var sp: float = sqrt(aa * aa + bb * bb)
			var err: float = 0.0
			if sp < s_min:
				err = s_min - sp
			elif sp > s_max:
				err = sp - s_max
			if err < best_err - 0.0001:
				best_err = err
				vz_pick = cz
				strength = clampf((sp - s_min) / maxf(s_max - s_min, 1.0), 0.0, 1.0)
				face_dir = Vector2(aa, -bb).normalized()
				if err <= 0.0001:
					break
		_ai_face_dir = face_dir
		v_perp = (vz_pick - GameConfig.hit_vz_v0) / gain * ref
	else:
		# 普通以下: 老实的一拍 (瞄准镜像, 按 vz 反推球速)
		var vzb: float = randf_range(GameConfig.hit_vz_min, GameConfig.hit_vz_max)
		var dsc0: float = vzb * vzb + 2.0 * g * (z0 - GameConfig.table_z)
		var tl0: float = (vzb + sqrt(maxf(dsc0, 0.0))) / maxf(g, 1.0)
		var aim0 := Vector2(tx, 2.0 * w_y - GameConfig.table_center.y)
		var want0: float = maxf((aim0 - from).length(), 1.0) / maxf(tl0, 0.001)
		strength = clampf((want0 - s_min) / maxf(s_max - s_min, 1.0), 0.0, 1.0)
		v_perp = (vzb - GameConfig.hit_vz_v0) / gain * ref
	# v_perp 不越救球阈值 (避免误触防守姿态)
	v_perp = clampf(v_perp, -GameConfig.defense_perp_threshold * 0.8, GameConfig.defense_perp_threshold * 0.8)
	# AI 扣杀开关(关): 高球时压低力度, 避免无意触发扣杀
	if not (GameConfig.debug_ai_smash or GameConfig.ai_level_smash()) and ball.z >= GameConfig.smash_height_min:
		strength = minf(strength, maxf(GameConfig.smash_power_min - 0.05, 0.0))
	var v_along: float = ref * pow(strength, 1.0 / curve)
	var sw: Vector2 = facing * v_along + perp * v_perp
	# 失误表现: omniscient 不失误; 其余按 ai_error_chance
	debug_last_error = ""
	if not omniscient and randf() < GameConfig.ai_error_chance:
		match randi() % 4:
			0:
				sw = sw.rotated(deg_to_rad(randf_range(-GameConfig.ai_error_aim_deg, GameConfig.ai_error_aim_deg)))
				debug_last_error = "瞄偏"
			1:
				sw *= GameConfig.ai_error_power_min
				debug_last_error = "太轻"
			2:
				sw *= GameConfig.ai_error_power_max
				debug_last_error = "太重"
			3:
				sw = -sw
				debug_last_error = "打反"
	return sw

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
	# 必须也投影到桌外, 否则这个"避让点"落进/穿过桌子会让 AI 顶桌卡死
	return _clamp_reachable(Vector2(clampf(target.x, ar.position.x, ar.end.x),
		clampf(target.y, ar.position.y, ar.end.y)))

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
	var ai_smash: bool = (GameConfig.debug_ai_smash or GameConfig.ai_level_smash()) and ball != null \
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
