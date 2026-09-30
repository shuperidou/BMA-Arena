class_name Ball
extends Node2D
## 球系统 (伪 Z 轴 / 高度)。
##
## 数据模型 (设计文档要求集中)：
##   position        = 场地水平位置 (XY)
##   height_z        = 距地面的高度 (独立变量，不参与 XY)
##   vel             = 水平速度 (XY)
##   vz              = 垂直速度 (Z)
##   radius          = 逻辑碰撞半径 (固定；视觉缩放不改它)
##   state / height_state = 逻辑状态
##
## Z 规则：
##   height_z <= ground_z                -> 落地 (球死)
##   下降且穿过 table_z 且 XY 在桌面内   -> 桌面弹跳
##   撞墙 (XY) 且 height_z <= wall_max_height -> 墙面反弹
##
## 视觉只为可读性：高度越高 -> 球越大 + 球与影子距离越大。逻辑半径不受影响。

signal table_bounced(bounce_index: int)
signal wall_bounced()
signal died(reason: int)

var state: int = GameTypes.BallState.INACTIVE
var height_state: int = GameTypes.BallHeightState.NONE

var vel: Vector2 = Vector2.ZERO   ## 水平速度 (XY)
var z: float = 0.0                ## 高度 (距地面)
var vz: float = 0.0               ## 垂直速度
var radius: float = 8.0           ## 逻辑碰撞半径 (固定)

## 自最近一次击球以来的统计 (计分/回击判定用)
var table_bounces: int = 0
var receiver_bounces: int = 0
var wall_since_hit: bool = false
var returnable: bool = false
var last_hitter: Node = null

var _bounce_threshold: float = 25.0

func _ready() -> void:
	radius = GameConfig.ball_radius
	_bounce_threshold = GameConfig.bounce_vz_threshold
	queue_redraw()

## 重置一次击球后的追踪状态。
func reset_shot() -> void:
	table_bounces = 0
	receiver_bounces = 0
	wall_since_hit = false
	returnable = false

## 从当前位置以给定 xy 速度发射 (高度/垂直速度由调用方设置)。
func launch_velocity(v: Vector2, vz0: float) -> void:
	vel = v
	vz = vz0
	state = GameTypes.BallState.LIVE
	reset_shot()

## 弹道发射：让球第一次落桌点尽量落在 target (xy)。高度从桌面起。
func launch_toward(target: Vector2, vz0: float) -> void:
	var d: Vector2 = target - position
	var dist: float = maxf(d.length(), 1.0)
	var speed: float = dist * GameConfig.ball_gravity / (2.0 * vz0)
	z = GameConfig.table_z
	launch_velocity((d / dist) * speed, vz0)

func _physics_process(dt: float) -> void:
	if state != GameTypes.BallState.LIVE:
		return
	_step(dt)

func _step(dt: float) -> void:
	# --- XY 水平运动 ---
	position += vel * dt
	vel = vel.lerp(Vector2.ZERO, clampf(GameConfig.ball_air_drag * dt, 0.0, 1.0))

	# --- Z 高度运动 ---
	var prev_z: float = z
	z += vz * dt
	vz -= GameConfig.ball_gravity * dt

	# --- 墙 (顶边)：XY 反弹，仅在有效高度内 ---
	var wall_y: float = GameConfig.wall_inner_y()
	if position.y - radius <= wall_y and vel.y < 0.0 and z <= GameConfig.wall_max_height:
		position.y = wall_y + radius
		vel.y = -vel.y * GameConfig.ball_wall_rest
		wall_since_hit = true
		_apply_wall_return_assist()
		wall_bounced.emit()
	# z 高于墙顶时不做 XY 反弹：球会飞过墙 (由越界判定处理)

	# --- 桌面弹跳：下降 + 高度穿过桌面 + XY 在桌面范围 ---
	if vz <= 0.0 and prev_z > GameConfig.table_z and z <= GameConfig.table_z and _over_table():
		z = GameConfig.table_z
		var incoming: float = -vz
		vz = incoming * GameConfig.table_bounce_factor
		if incoming >= _bounce_threshold:
			_register_table_bounce()
	# --- 地面落地 ---
	elif z <= GameConfig.ground_z:
		_die(GameTypes.DeathReason.FLOOR)
		return

	# 安全兜底：飞出场地太远
	if not GameConfig.arena_rect().grow(260.0).has_point(position):
		_die(GameTypes.DeathReason.OUT_OF_BOUNDS)
		return

	_update_height_state()
	queue_redraw()

func _register_table_bounce() -> void:
	table_bounces += 1
	if wall_since_hit:
		receiver_bounces += 1
		returnable = true
	table_bounced.emit(table_bounces)
	if wall_since_hit and receiver_bounces > GameConfig.receiver_bounce_limit:
		_die(GameTypes.DeathReason.DOUBLE_BOUNCE)

func _update_height_state() -> void:
	if z <= GameConfig.ground_z + 0.5:
		height_state = GameTypes.BallHeightState.ON_GROUND
	elif vz > 1.0:
		height_state = GameTypes.BallHeightState.ASCENDING
	elif vz < -1.0:
		height_state = GameTypes.BallHeightState.DESCENDING
	else:
		height_state = GameTypes.BallHeightState.HOVERING

## 墙弹后给一个竖直速度，让球落回桌面而不是掉进桌墙缝隙。
func _apply_wall_return_assist() -> void:
	if not GameConfig.wall_return_assist:
		return
	var vy_ret: float = vel.y
	if vy_ret <= 1.0:
		return
	var tr := GameConfig.table_rect()
	var target_y: float = tr.position.y + tr.size.y * GameConfig.wall_return_depth_frac
	var dy: float = target_y - position.y
	if dy <= 1.0:
		return
	var tt: float = dy / vy_ret
	var zw: float = maxf(z, GameConfig.table_z + 5.0)
	# 让球在 tt 秒后高度正好落到桌面高度
	vz = (GameConfig.table_z - zw + 0.5 * GameConfig.ball_gravity * tt * tt) / tt

func _over_table() -> bool:
	return GameConfig.table_rect().has_point(position)

func _die(reason: int) -> void:
	if state == GameTypes.BallState.DEAD:
		return
	state = GameTypes.BallState.DEAD
	height_state = GameTypes.BallHeightState.NONE
	queue_redraw()
	died.emit(reason)

# ------------------------------------------------------------
#  视觉：高度 -> 大小 + 影子
# ------------------------------------------------------------
func visual_scale() -> float:
	var t: float = clampf(z / maxf(GameConfig.table_z, 1.0), 0.0, 2.0)
	return clampf(GameConfig.base_ball_scale * (1.0 + GameConfig.height_scale_factor * t),
		GameConfig.min_visual_scale, GameConfig.max_visual_scale)

func _draw() -> void:
	# 影子：固定在 XY 位置，大小固定 (不随高度缩放)
	var sh: float = radius * GameConfig.shadow_scale
	draw_circle(Vector2.ZERO, sh, Color(0, 0, 0, 0.32))
	# 球：随高度放大 + 向上偏移 (影子与球的距离体现高度)
	var r: float = radius * visual_scale()
	var p := Vector2(0.0, -z * GameConfig.shadow_offset_factor)
	draw_circle(p, r, Color(1, 1, 1))
	var inner := Color(1.0, 0.83, 0.3)
	if state == GameTypes.BallState.DEAD:
		inner = Color(0.5, 0.5, 0.5)
	elif state == GameTypes.BallState.HELD:
		inner = Color(0.6, 0.9, 1.0)
	draw_circle(p, r * 0.6, inner)
