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
var debug_aim_override: float = NAN  ## 测试用：非 NAN 时覆盖鼠标目标角度
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
	angular_damp = 0.0

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
	var dir: Vector2 = input_scheme.move_vector() if input_scheme != null else Vector2.ZERO
	var target_v: Vector2 = dir * GameConfig.move_speed
	var dv: Vector2 = target_v - state.linear_velocity
	state.linear_velocity += dv.limit_length(GameConfig.move_accel * step)

	# --- 旋转：与平移完全独立 ---
	_update_rotation(state, step)

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

## 旋转追踪：鼠标给目标角度，带角加速度限制地逐渐转向 (有旋转惯性)。
func _update_rotation(state: PhysicsDirectBodyState2D, step: float) -> void:
	if input_scheme == null:
		return
	var accel: float = GameConfig.rotation_acceleration * step
	if input_scheme.aim_mode == InputScheme.AimMode.MOUSE:
		var target: float = debug_aim_override if not is_nan(debug_aim_override) \
			else input_scheme.mouse_aim_angle(self)
		if is_nan(target):
			# 鼠标太近或不在鼠标模式：角速度逐渐衰减
			state.angular_velocity = move_toward(state.angular_velocity, 0.0, GameConfig.rotation_damping * step)
			return
		var err: float = wrapf(target - state.transform.get_rotation(), -PI, PI)
		var desired_w: float = clampf(err * GameConfig.rotation_gain,
			-GameConfig.max_angular_velocity, GameConfig.max_angular_velocity)
		state.angular_velocity += clampf(desired_w - state.angular_velocity, -accel, accel)
	elif input_scheme.aim_mode == InputScheme.AimMode.KEYBOARD:
		var target_w: float = input_scheme.turn_axis() * GameConfig.max_angular_velocity
		state.angular_velocity += clampf(target_w - state.angular_velocity, -accel, accel)

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
	# 朝向标记 (局部 -y 为"前方")
	draw_line(Vector2.ZERO, Vector2(0.0, -seg), Color(1, 1, 1, 0.45), 3.0)
	draw_circle(Vector2.ZERO, 5.0, Color(1, 1, 1, 0.85))
