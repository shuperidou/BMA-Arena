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

	# 1) 预测可接住点
	var pred: Dictionary = predict_catchable(ball)
	intercept_point = pred.point
	intercept_time = pred.time

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
#  球的可接住点预测
# ------------------------------------------------------------
## 前向模拟球 (与 Ball 相同的 xy/z 物理)，返回球"撞墙后落桌、且高度可击"的第一个位置与时间。
## 找不到则返回最接近接球者的点 (time=-1, 表示不确定)。
func predict_catchable(b: Ball) -> Dictionary:
	if b.state != GameTypes.BallState.LIVE:
		return {"point": b.global_position, "time": -1.0}
	if _is_catchable(b.returnable, b.global_position, b.z):
		return {"point": b.global_position, "time": 0.0}

	var radius: float = GameConfig.ball_radius
	var wall_y: float = GameConfig.wall_inner_y()
	var tr := GameConfig.table_rect()
	var g: float = GameConfig.ball_gravity
	var pos: Vector2 = b.global_position
	var vel: Vector2 = b.vel
	var z: float = b.z
	var vz: float = b.vz
	var wall: bool = b.wall_since_hit
	var bounced_after_wall: bool = false
	var t: float = 0.0
	var dt: float = 0.016
	while t < 2.0:
		pos += vel * dt
		vel = vel.lerp(Vector2.ZERO, clampf(GameConfig.ball_air_drag * dt, 0.0, 1.0))
		var prev_z: float = z
		z += vz * dt
		vz -= g * dt

		if pos.y - radius <= wall_y and vel.y < 0.0 and z <= GameConfig.wall_max_height:
			pos.y = wall_y + radius
			vel.y = -vel.y * GameConfig.ball_wall_rest
			wall = true
			bounced_after_wall = false
			# 与 Ball 相同的"墙弹后回桌"竖直速度修正
			var vy_ret: float = vel.y
			if vy_ret > 1.0:
				var target_y: float = tr.position.y + tr.size.y * GameConfig.wall_return_depth_frac
				var dy: float = target_y - pos.y
				if dy > 1.0:
					var tt: float = dy / vy_ret
					var zw: float = maxf(z, GameConfig.table_z + 5.0)
					vz = (GameConfig.table_z - zw + 0.5 * g * tt * tt) / tt

		if vz <= 0.0 and prev_z > GameConfig.table_z and z <= GameConfig.table_z and tr.has_point(pos):
			z = GameConfig.table_z
			vz = -vz * GameConfig.table_bounce_factor
			if wall:
				bounced_after_wall = true

		if _is_catchable(wall and bounced_after_wall, pos, z):
			return {"point": pos, "time": t}
		if z <= GameConfig.ground_z:
			break
		t += dt

	return {"point": _closest_approach(b, receiver), "time": -1.0}

func _is_catchable(returnable: bool, pos: Vector2, z: float) -> bool:
	if not returnable:
		return false
	if not GameConfig.table_rect().has_point(pos):
		return false
	return z >= GameConfig.hit_height_min and z <= GameConfig.hit_height_max

## 球将来最接近接球者的位置 (预测不确定时的兜底)。
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
