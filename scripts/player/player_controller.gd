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

var hit_points: Array[HitPoint] = []
## 击球区在角色局部坐标系中的位移 (2D)。
## 直接复用鼠标拖动向量的数值，**不做 world->local 转换**。
var hit_zone_offset_local: Vector2 = Vector2.ZERO
var debug_mouse_world_delta: Vector2 = Vector2.ZERO    ## 鼠标原始拖动向量
var debug_hit_zone_local_delta: Vector2 = Vector2.ZERO ## 限幅后的目标局部偏移
var _last_touch_time: float = -10.0
var _body_color: Color = Color(0.31, 0.82, 0.77)

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

	var cap := CapsuleShape2D.new()
	cap.radius = GameConfig.player_radius
	cap.height = GameConfig.player_half_length * 2.0
	var cs := CollisionShape2D.new()
	cs.name = "CollisionShape2D"
	cs.shape = cap
	add_child(cs)

	for i in 2:
		var hp := HitPoint.new()
		hp.name = "HitPoint%s" % ("Front" if i == 0 else "Back")
		var s := -1.0 if i == 0 else 1.0
		hp.position = Vector2(0.0, s * GameConfig.player_half_length)
		add_child(hp)
		hit_points.append(hp)

	queue_redraw()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var step: float = state.step
	# --- 平移：世界坐标。WASD 永远对应世界方向，与 rotation 无关 ---
	var dir: Vector2 = _desired_move_dir(state)
	var target_v: Vector2 = dir * GameConfig.move_speed
	var dv: Vector2 = target_v - state.linear_velocity
	state.linear_velocity += dv.limit_length(GameConfig.move_accel * step)

	# --- 击球区 / (仅键盘方) 旋转 ---
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
	if input_scheme.aim_mode == InputScheme.AimMode.KEYBOARD:
		# 仅玩家2 临时方案：键盘主动旋转
		var accel: float = GameConfig.rotation_acceleration * step
		var target_w: float = input_scheme.turn_axis() * GameConfig.max_angular_velocity
		state.angular_velocity += clampf(target_w - state.angular_velocity, -accel, accel)
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
	var target_local: Vector2 = (drag * GameConfig.hit_zone_drag_scale) \
		.limit_length(GameConfig.hit_zone_max_offset)
	if input_scheme.is_dragging():
		hit_zone_offset_local = target_local  # 拖动中 1:1 跟随 (速度=挥动速度)
	else:
		hit_zone_offset_local = hit_zone_offset_local.move_toward(Vector2.ZERO,
			GameConfig.hit_zone_return_speed * step)
	_update_hit_points()
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
	var l: float = GameConfig.player_half_length
	hit_points[0].position = Vector2(0.0, -l) + hit_zone_offset_local  # 前端 A
	hit_points[1].position = Vector2(0.0, l) - hit_zone_offset_local   # 后端 B

## 期望的世界移动方向 (默认来自输入；AI 覆写)。
func _desired_move_dir(_state: PhysicsDirectBodyState2D) -> Vector2:
	return input_scheme.move_vector() if input_scheme != null else Vector2.ZERO

## 击球计算 (默认走 HitSystem；AI 覆写)。
func compute_hit(hit_point: HitPoint, b: Ball) -> Dictionary:
	return HitSystem.compute(self, hit_point, b)

## 发球计算 (默认沿朝向；AI 覆写)。
func compute_serve(b: Ball) -> Dictionary:
	var facing: Vector2 = Vector2.RIGHT.rotated(rotation)
	var speed: float = GameConfig.ball_hit_speed
	return {
		"velocity": facing * speed, "vz": GameConfig.ball_hit_vz, "strength": 1.0,
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
	var r: float = GameConfig.player_radius
	var hl: float = GameConfig.player_half_length
	var seg: float = hl - r
	draw_rect(Rect2(-r, -seg, 2.0 * r, 2.0 * seg), _body_color)
	draw_circle(Vector2(0.0, -seg), r, _body_color)
	draw_circle(Vector2(0.0, seg), r, _body_color)
	# 朝向标记: 局部 +x 为"前方" (面向桌中心 / 发球方向)
	draw_line(Vector2.ZERO, Vector2(seg, 0.0), Color(1, 1, 1, 0.6), 4.0)
	draw_circle(Vector2.ZERO, 5.0, Color(1, 1, 1, 0.85))
