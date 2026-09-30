class_name Ball
extends Node2D
## 球系统。
##
## 俯视 2D 投影 + 独立高度 z 的简化 2.5D 模型：
##  - xy 平面按速度直线运动 (俯视看到的位置)
##  - z 按重力运动；z 落到桌面高度时，若在桌面矩形内 => 桌弹；否则继续落到地面 => 球死
##  - 撞到墙 (场地顶边的竖直墙) 时水平反射
##
## 这套模型是为了让现实规则(先打桌→弹墙→弹回桌)在俯视视角下成立，
## 参数集中在 GameConfig，标了 [TUNED]，可试玩再调。

signal table_bounced(bounce_index: int)
signal wall_bounced()
signal died(reason: int)

var state: int = GameTypes.BallState.INACTIVE
var vel: Vector2 = Vector2.ZERO
var z: float = 0.0          ## 高度 (桌面高度为 0 基准)
var vz: float = 0.0
var radius: float = 8.0

## 自最近一次击球以来的统计 (计分/回击判定用)
var table_bounces: int = 0          ## 桌弹总次数
var receiver_bounces: int = 0       ## 墙之后落在桌上的次数 (接球方侧)
var wall_since_hit: bool = false    ## 上次击球后是否已撞墙
var returnable: bool = false        ## 是否已满足"墙后落桌"，接球方可回击
var last_hitter: Node = null

var _floor_h: float = 60.0
var _bounce_threshold: float = 25.0

func _ready() -> void:
	radius = GameConfig.ball_radius
	_floor_h = GameConfig.table_height
	_bounce_threshold = GameConfig.bounce_vz_threshold
	queue_redraw()

## 重置一次击球后的追踪状态。
func reset_shot() -> void:
	table_bounces = 0
	receiver_bounces = 0
	wall_since_hit = false
	returnable = false

## 从当前位置以给定 xy 速度发射 (z 保持不变)。
func launch_velocity(v: Vector2, vz0: float) -> void:
	vel = v
	vz = vz0
	state = GameTypes.BallState.LIVE
	reset_shot()

## 弹道发射：让球第一次落桌点尽量落在 target (xy)。
## 用于发球这类"把球打进桌"的动作。
func launch_toward(target: Vector2, vz0: float) -> void:
	var d: Vector2 = target - position
	var dist: float = maxf(d.length(), 1.0)
	var speed: float = dist * GameConfig.ball_gravity / (2.0 * vz0)
	var dir: Vector2 = d / dist
	z = 0.0
	launch_velocity(dir * speed, vz0)

func _physics_process(dt: float) -> void:
	if state != GameTypes.BallState.LIVE:
		return
	_step(dt)

func _step(dt: float) -> void:
	# --- xy ---
	position += vel * dt
	vel = vel.lerp(Vector2.ZERO, clampf(GameConfig.ball_air_drag * dt, 0.0, 1.0))

	# --- z (独立高度) ---
	z += vz * dt
	vz -= GameConfig.ball_gravity * dt

	# --- 墙 (仅顶边) ---
	var wall_y: float = GameConfig.wall_inner_y()
	if position.y - radius <= wall_y and vel.y < 0.0:
		position.y = wall_y + radius
		vel.y = -vel.y * GameConfig.ball_wall_rest
		wall_since_hit = true
		_apply_wall_return_assist()
		wall_bounced.emit()

	# --- 表面判定 ---
	if vz <= 0.0 and z <= 0.0:
		if _over_table():
			z = 0.0
			var incoming: float = -vz
			vz = incoming * GameConfig.ball_table_rest
			if incoming >= _bounce_threshold:
				_register_table_bounce()
		# 否则处于缝隙/地面之上：继续下落直到地面

	if z <= -_floor_h:
		_die(GameTypes.DeathReason.FLOOR)
		return

	# 安全兜底：飞出场地太远
	var margin_rect := GameConfig.arena_rect().grow(260.0)
	if not margin_rect.has_point(position):
		_die(GameTypes.DeathReason.OUT_OF_BOUNDS)
		return

	queue_redraw()

func _register_table_bounce() -> void:
	table_bounces += 1
	if wall_since_hit:
		receiver_bounces += 1
		returnable = true
	table_bounced.emit(table_bounces)
	if wall_since_hit and receiver_bounces > GameConfig.receiver_bounce_limit:
		_die(GameTypes.DeathReason.DOUBLE_BOUNCE)

## 墙弹后给一个竖直速度，让球落回桌面而不是掉进桌墙缝隙。
## 纯物理下几乎必然掉缝，所以这里做游戏化辅助 (可配置关闭)。
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
	var zw: float = maxf(z, 5.0)
	vz = (0.5 * GameConfig.ball_gravity * tt * tt - zw) / tt

func _over_table() -> bool:
	return GameConfig.table_rect().has_point(position)

func _die(reason: int) -> void:
	if state == GameTypes.BallState.DEAD:
		return
	state = GameTypes.BallState.DEAD
	queue_redraw()
	died.emit(reason)

func _draw() -> void:
	var h: float = z * GameConfig.ball_visual_height_scale
	# 影子 (高度越高影子越淡越大)
	var sh_a: float = clampf(0.35 - z * 0.002, 0.08, 0.35)
	draw_circle(Vector2.ZERO, radius * (1.0 + z * 0.003), Color(0, 0, 0, sh_a))
	# 球体 (视觉上按高度向上偏移)
	var p := Vector2(0.0, -h)
	draw_circle(p, radius, Color(1, 1, 1))
	var inner := Color(1.0, 0.83, 0.3)
	match state:
		GameTypes.BallState.DEAD:
			inner = Color(0.5, 0.5, 0.5)
		GameTypes.BallState.HELD:
			inner = Color(0.6, 0.9, 1.0)
	draw_circle(p, radius * 0.6, inner)
