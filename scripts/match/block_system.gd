class_name BlockSystem
extends Node
## 阻挡 / Interference 判定系统 (独立模块)。
##
## 规则 (扇区模型)：
##   1) 接球方 A 必须有移动意图：速度低于 block_pursuit_speed 视为静止 -> 不构成阻挡
##   2) 球必须在 A 的"速度扇区"内：以 A 的速度方向为轴，半角 block_sector_half_angle 内,
##      且在半径 block_sector_radius 内
##   3) 发生了实际碰撞, 且接触持续时间 >= block_min_contact_time
##   4) (可选, 默认关) 忽略对手的时间可达判定
##   5) (可选, 默认关) 对手 B 必须在 A 的"球侧"(不在正后方)
##
## 命中 2) 但未满足 3) -> POSSIBLE(提示); 满足 2)+3) -> CONFIRMED(判罚)。
## 是否真的判罚由 Match 决定 (点一: 只有球死了才结算)。
##
## 阈值全部可调 (TEMP)。

var ball: Ball = null
var receiver: PlayerController = null
var opponent: PlayerController = null

var state: int = GameTypes.Interference.NONE
var intercept_point: Vector2 = Vector2.ZERO  ## 仅供 Debug 画"预计接球点"
var intercept_time: float = 0.0
var sector_axis: Vector2 = Vector2.ZERO      ## 扇区轴 (= 接球方速度方向)
var active: bool = false

# Debug 因子
var dbg_speed: float = 0.0
var dbg_has_intent: bool = false
var dbg_dist: float = 0.0
var dbg_angle_deg: float = 0.0
var dbg_in_sector: bool = false
var dbg_contact: float = 0.0
var dbg_collided: bool = false

func update(dt: float, current_ball: Ball, current_receiver: PlayerController,
		current_opponent: PlayerController, collision_time: float,
		collision_pos: Vector2, now: float, contact_duration: float) -> void:
	ball = current_ball
	receiver = current_receiver
	opponent = current_opponent
	state = GameTypes.Interference.NONE
	sector_axis = Vector2.ZERO

	if not active or ball == null or receiver == null or opponent == null:
		return

	# Debug 用: 预测可接住点
	var pred: Dictionary = ball.predict_catchable()
	intercept_point = pred.point
	intercept_time = pred.time
	if not pred.found:
		intercept_point = ball.global_position

	# 1) 移动意图: 静止的接球方不构成阻挡
	var vel: Vector2 = receiver.linear_velocity
	var speed: float = vel.length()
	if speed < GameConfig.block_pursuit_speed:
		return
	var axis: Vector2 = vel / speed
	sector_axis = axis

	dbg_speed = speed
	dbg_has_intent = speed >= GameConfig.block_pursuit_speed

	var to_ball: Vector2 = ball.global_position - receiver.global_position
	var bdist: float = to_ball.length()
	dbg_dist = bdist
	var ang: float = absf(wrapf(axis.angle() - to_ball.angle(), -PI, PI))
	dbg_angle_deg = rad_to_deg(ang)
	dbg_in_sector = bdist <= GameConfig.block_sector_radius \
		and ang <= deg_to_rad(GameConfig.block_sector_half_angle)

	# 4) (可选) 时间可达：忽略对手, 接球方要赶得上
	if GameConfig.block_require_time_reachable and intercept_time >= 0.0:
		var reach: float = GameConfig.move_speed * (intercept_time + GameConfig.block_reach_slack)
		if bdist > reach:
			return

	# 2) 扇区: 球在半角 + 半径内 = "A 正冲过去要接的球"
	if not dbg_in_sector:
		return

	# 5) (可选) 对手必须在 A 的球侧
	if GameConfig.block_require_opponent_in_front:
		var to_b: Vector2 = opponent.global_position - receiver.global_position
		if to_b.dot(axis) <= 0.0:
			return

	# 扇区满足 -> 至少是 POSSIBLE(危险提示)
	state = GameTypes.Interference.POSSIBLE

	# 3) 实际碰撞 + 持续时间
	var recent_collision: bool = (now - collision_time) <= GameConfig.block_collision_window
	dbg_contact = contact_duration
	dbg_collided = recent_collision and contact_duration >= GameConfig.block_min_contact_time
	if dbg_collided:
		state = GameTypes.Interference.CONFIRMED
