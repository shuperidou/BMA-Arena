class_name BlockSystem
extends Node
## 阻挡 / Interference 判定系统 (独立模块，不硬编码进角色或球)。
##
## 规则 (方案 A)：
##   1) 预测球的"可接住位置 P"和到达时间 T (撞墙后落桌、可击球高度内)
##   2) 机会判定 (忽略对手 A)：接球方 B 能否在 T 之前赶到 P
##      -> 不能则无阻挡 (B 本来就没机会)；这一步可用 block_require_time_reachable 开关
##   3) 妨碍判定：0.4s 内发生实际碰撞, 且碰撞点落在 B->P 走廊内 -> CONFIRMED
##      仅"A 正在追球 + A 在走廊内" -> POSSIBLE (提示，无判罚)
##
## 阈值全部可调 (TEMP)。

var ball: Ball = null
var receiver: PlayerController = null
var opponent: PlayerController = null

var state: int = GameTypes.Interference.NONE
var intercept_point: Vector2 = Vector2.ZERO
var intercept_time: float = 0.0
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

	# 1) 预测可接住点 (由 Ball 提供)
	var pred: Dictionary = ball.predict_catchable()
	intercept_point = pred.point
	intercept_time = pred.time
	if not pred.found:
		intercept_point = _closest_approach(ball, receiver)

	var to_r: Vector2 = intercept_point - receiver.global_position
	var dist: float = to_r.length()
	if dist > GameConfig.block_pursuit_max_dist:
		return

	# 2) 机会判定 (忽略对手)。time<0 表示预测不确定 -> 跳过该检查。
	if GameConfig.block_require_time_reachable and intercept_time >= 0.0:
		var reach: float = GameConfig.move_speed * (intercept_time + GameConfig.block_reach_slack)
		if dist > reach:
			return

	# 3) 妨碍判定
	var pursuing: bool = false
	if receiver.linear_velocity.length() > GameConfig.block_pursuit_speed and to_r.length() > 1.0:
		pursuing = receiver.linear_velocity.normalized().dot(to_r.normalized()) > GameConfig.block_pursuit_dot

	var recent_collision: bool = (now - collision_time) <= GameConfig.block_collision_window

	if recent_collision and _near_segment(receiver.global_position, intercept_point, collision_pos):
		state = GameTypes.Interference.CONFIRMED
	elif pursuing and _near_segment(receiver.global_position, intercept_point, opponent.global_position):
		state = GameTypes.Interference.POSSIBLE

# ------------------------------------------------------------
#  球将来最接近接球者的位置 (预测不确定时的兜底)。
func _closest_approach(b: Ball, a: PlayerController) -> Vector2:
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
