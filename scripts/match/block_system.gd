class_name BlockSystem
extends Node
## 阻挡 / Interference 判定系统 (独立模块，不硬编码进角色或球)。
##
## 输入: 接球者 A、对手 B、球的位置与速度、最近碰撞事件、时间窗口。
## 输出: NONE / POSSIBLE / CONFIRMED 的内部状态 + 可视化的预计接球点与危险走廊。
##
## 判定依据 (设计文档第 2 节):
##   A 有机会接球 + A 正在向预计接球点移动 + B 位于 A 与球之间 + 发生了有效碰撞
## 这里全部用可调阈值近似。具体数值需要试玩调整 (TEMP)。

var ball: Ball = null
var receiver: PlayerController = null
var opponent: PlayerController = null

var state: int = GameTypes.Interference.NONE
var intercept_point: Vector2 = Vector2.ZERO
var active: bool = false

func update(dt: float, current_ball: Ball, current_receiver: PlayerController,
		current_opponent: PlayerController, collision_time: float,
		collision_pos: Vector2, now: float) -> void:
	ball = current_ball
	receiver = current_receiver
	opponent = current_opponent
	state = GameTypes.Interference.NONE

	if not active or ball == null or receiver == null or opponent == null:
		intercept_point = ball.global_position if ball != null else Vector2.ZERO
		return

	intercept_point = predicted_intercept(ball, receiver)
	var to_r: Vector2 = intercept_point - receiver.global_position
	var dist: float = to_r.length()
	if dist > GameConfig.block_pursuit_max_dist:
		return

	# A 是否正在向预计接球点移动
	var pursuing: bool = false
	if receiver.linear_velocity.length() > GameConfig.block_pursuit_speed and to_r.length() > 1.0:
		pursuing = receiver.linear_velocity.normalized().dot(to_r.normalized()) > GameConfig.block_pursuit_dot

	var recent_collision: bool = (now - collision_time) <= GameConfig.block_collision_window

	if recent_collision and _near_segment(receiver.global_position, intercept_point, collision_pos):
		state = GameTypes.Interference.CONFIRMED
	elif pursuing and _near_segment(receiver.global_position, intercept_point, opponent.global_position):
		state = GameTypes.Interference.POSSIBLE

## 球将来最接近接球者的位置 (简化预测)。
func predicted_intercept(b: Ball, a: PlayerController) -> Vector2:
	var v: Vector2 = b.vel
	if v.length_squared() < 1.0:
		return b.global_position
	var d: Vector2 = a.global_position - b.global_position
	var t: float = clampf(d.dot(v) / v.length_squared(), 0.0, 0.6)
	return b.global_position + v * t

## q 是否落在 a->p 这条走廊内。
func _near_segment(a: Vector2, p: Vector2, q: Vector2) -> bool:
	var ap: Vector2 = p - a
	var l2: float = ap.length_squared()
	if l2 < 1.0:
		return false
	var t: float = (q - a).dot(ap) / l2
	if t <= 0.05 or t >= 0.95:
		return false
	var proj: Vector2 = a + ap * t
	return (q - proj).length() <= GameConfig.block_corridor_width
