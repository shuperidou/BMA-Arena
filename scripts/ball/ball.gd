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

# 击球反馈
var hit_flash: float = 0.0        ## 1->0 的击球闪一下
var last_strength: float = 0.0    ## 上次击球力度 (0..1)
var last_save_state: int = 0      ## 上次击球: 救球 0=无/1=成功/2=失败
var last_smash_state: int = 0     ## 上次击球: 扣杀 0=无/1=成功/2=失败
var last_hit_info: Dictionary = {} ## 上次击球调试信息
var _trail: Array[Vector2] = []   ## 拖尾 (存视觉位置，含高度偏移)
var _last_surface: int = 0        ## 最近一次弹跳的面 (0=无 1=桌 2=墙) —— 同面连弹即结算
var serve_shot: bool = false      ## 本次是否为发球 (发球必须先弹桌再撞墙; 回击只需墙->桌)

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
	_last_surface = 0

## 从当前位置以给定 xy 速度发射 (高度/垂直速度由调用方设置)。
func launch_velocity(v: Vector2, vz0: float) -> void:
	vel = v
	vz = vz0
	state = GameTypes.BallState.LIVE
	reset_shot()
	_trail.clear()

## 记录一次击球的反馈信息 (由 Match 调用)。
func register_hit(info: Dictionary) -> void:
	last_hit_info = info
	last_strength = clampf(info.get("strength", 0.0), 0.0, 1.0)
	last_save_state = 0
	if bool(info.get("is_defense", false)):
		last_save_state = 1 if bool(info.get("defense_saved", false)) else 2
	last_smash_state = 0
	if bool(info.get("smash_attempt", false)):
		last_smash_state = 1 if bool(info.get("is_smash", false)) else 2
	hit_flash = 1.0

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
		# 墙连弹 -> 直接结算。
		# 发球: 撞墙前碰不碰桌无所谓。
		# 回击: 撞墙前**一定不能先碰桌**, 否则回击方输 (设计文档新规)。
		if _last_surface == 2 or (not serve_shot and table_bounces >= 1):
			_die(GameTypes.DeathReason.BAD_BOUNCE)
			return
		position.y = wall_y + radius
		vel.y = -vel.y * GameConfig.wall_bounce_factor
		wall_since_hit = true
		_last_surface = 2
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
	# 拖尾 + 闪一下衰减
	_trail.append(position - Vector2(0.0, z * GameConfig.shadow_offset_factor))
	if _trail.size() > 12:
		_trail.pop_front()
	hit_flash = maxf(0.0, hit_flash - dt * 2.5)
	queue_redraw()

func _register_table_bounce() -> void:
	# 同一面(桌)连续弹两次 -> 直接结算：墙前跳弹=击球方失误, 墙后=接球方没接到
	if _last_surface == 1:
		if wall_since_hit:
			_die(GameTypes.DeathReason.DOUBLE_BOUNCE)
		else:
			_die(GameTypes.DeathReason.BAD_BOUNCE)
		return
	_last_surface = 1
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

## 预测"可接住点"：球撞墙后落桌、且高度在可击范围内的第一个位置与时间。
## 返回 {point: Vector2, time: float, found: bool}；found=false 时 time=-1。
func predict_catchable(horizon: float = 2.0) -> Dictionary:
	if state != GameTypes.BallState.LIVE:
		return {"point": global_position, "time": -1.0, "found": false}
	if returnable and _over_table() and z >= GameConfig.hit_height_min and z <= GameConfig.hit_height_max:
		return {"point": global_position, "time": 0.0, "found": true}
	var p: Vector2 = position
	var v: Vector2 = vel
	var zz: float = z
	var vzz: float = vz
	var wall: bool = wall_since_hit
	var bounced_after_wall: bool = false
	var t: float = 0.0
	var dt: float = 0.016
	var wall_y: float = GameConfig.wall_inner_y()
	var tr := GameConfig.table_rect()
	var g: float = GameConfig.ball_gravity
	while t < horizon:
		p += v * dt
		v = v.lerp(Vector2.ZERO, clampf(GameConfig.ball_air_drag * dt, 0.0, 1.0))
		var prev_zz: float = zz
		zz += vzz * dt
		vzz -= g * dt
		if p.y - radius <= wall_y and v.y < 0.0 and zz <= GameConfig.wall_max_height:
			p.y = wall_y + radius
			v.y = -v.y * GameConfig.wall_bounce_factor
			wall = true
			bounced_after_wall = false
			var vy_ret: float = v.y
			if vy_ret > 1.0:
				var target_y: float = tr.position.y + tr.size.y * GameConfig.wall_return_depth_frac
				var dy: float = target_y - p.y
				if dy > 1.0:
					var tt: float = dy / vy_ret
					var zw: float = maxf(zz, GameConfig.table_z + 5.0)
					vzz = (GameConfig.table_z - zw + 0.5 * g * tt * tt) / tt
		if vzz <= 0.0 and prev_zz > GameConfig.table_z and zz <= GameConfig.table_z and tr.has_point(p):
			zz = GameConfig.table_z
			vzz = -vzz * GameConfig.table_bounce_factor
			if wall:
				bounced_after_wall = true
		if wall and bounced_after_wall and tr.has_point(p) \
				and zz >= GameConfig.hit_height_min and zz <= GameConfig.hit_height_max:
			return {"point": p, "time": t, "found": true}
		if zz <= GameConfig.ground_z:
			break
		t += dt
	return {"point": global_position, "time": -1.0, "found": false}

func _die(reason: int) -> void:
	if state == GameTypes.BallState.DEAD:
		return
	state = GameTypes.BallState.DEAD
	height_state = GameTypes.BallHeightState.NONE
	_trail.clear()
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
	# 发球前 (HELD/INACTIVE) 不显示；球死(DEAD)也不显示
	if state != GameTypes.BallState.LIVE:
		return
	var r: float = radius * visual_scale()
	var p := Vector2(0.0, -z * GameConfig.shadow_offset_factor)
	# 球心颜色: 救球=绿; 否则按力度 弱蓝<->强橙红
	var core := Color(1.0, 0.83, 0.3)
	if hit_flash > 0.05:
		if last_smash_state == 1:
			core = Color(1.0, 0.35, 1.0)      # 扣杀成功: 品红
		elif last_smash_state == 2:
			core = Color(0.5, 0.4, 0.55)      # 扣杀失败: 灰品红 (哑火)
		elif last_save_state == 1:
			core = Color(0.35, 1.0, 0.45)     # 救球成功: 绿
		elif last_save_state == 2:
			core = Color(0.55, 0.35, 0.32)    # 救球失败: 暗红
		else:
			core = Color(0.45, 0.7, 1.0).lerp(Color(1.0, 0.35, 0.15), last_strength)
	# 拖尾 (越新越明显, 颜色跟随球心)
	var n: int = _trail.size()
	for i in n:
		var f: float = float(i) / float(maxi(n, 1))
		var tp: Vector2 = _trail[i] - position
		draw_circle(tp, radius * (0.25 + 0.5 * f) * visual_scale(),
			Color(core.r, core.g, core.b, 0.05 + 0.18 * f))
	# 影子：固定在 XY 位置，大小固定 (不随高度缩放)
	draw_circle(Vector2.ZERO, radius * GameConfig.shadow_scale, Color(0, 0, 0, 0.32))
	# 球：随高度放大 + 向上偏移 (影子与球的距离体现高度)
	draw_circle(p, r, Color(1, 1, 1))
	draw_circle(p, r * 0.6, core)
	# 击球闪环 (颜色跟随球心); 救球失败 -> 断成几段的暗环, 一眼可辨
	if hit_flash > 0.01:
		var rr: float = radius * (1.5 + (1.0 - hit_flash) * 10.0)
		if last_save_state == 2:
			for seg in 6:
				var a0: float = float(seg) / 6.0 * TAU
				draw_arc(p, rr, a0, a0 + TAU / 6.0 * 0.5, 6, Color(core.r, core.g, core.b, hit_flash * 0.7), 3.0)
		else:
			draw_arc(p, rr, 0.0, TAU, 28, Color(core.r, core.g, core.b, hit_flash * 0.8), 3.0)
	# 扣杀: 一圈尖刺 (成功=又长又亮; 失败=又短又暗的"哑火"刺)
	if hit_flash > 0.05 and last_smash_state != 0:
		var ok: bool = last_smash_state == 1
		var spikes: int = 12
		var base_r: float = r * 1.15
		var tip_r: float = r * ((1.7 if ok else 1.3) + (1.0 - hit_flash) * (3.5 if ok else 1.0))
		var col := Color(1.0, 0.35, 1.0, hit_flash * 0.9) if ok else Color(0.5, 0.42, 0.55, hit_flash * 0.65)
		for i in spikes:
			var ang: float = float(i) / float(spikes) * TAU
			var dir_v: Vector2 = Vector2(cos(ang), sin(ang))
			var tang: Vector2 = Vector2(-dir_v.y, dir_v.x)
			var a: Vector2 = p + dir_v * base_r + tang * (r * 0.28)
			var b: Vector2 = p + dir_v * base_r - tang * (r * 0.28)
			var c: Vector2 = p + dir_v * tip_r
			draw_colored_polygon(PackedVector2Array([a, b, c]), col)
	# 扣杀提示: 球够高且可接 -> 脉动环 + 向下箭头, 提示"现在可以扣杀"
	if GameConfig.smash_hint_enabled and state == GameTypes.BallState.LIVE \
			and returnable and z >= GameConfig.smash_height_min and z <= GameConfig.hit_height_max:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.008)
		var hr: float = r * (1.9 + 0.6 * pulse)
		draw_arc(p, hr, 0.0, TAU, 32, Color(1.0, 0.85, 0.25, 0.30 + 0.40 * pulse), 3.0)
		var chev := Color(1.0, 0.85, 0.25, 0.45 + 0.50 * pulse)
		for k in 2:
			var top_y: float = p.y - r * (2.4 + float(k) * 0.9)
			var cw: float = r * 0.65
			var pts2 := PackedVector2Array([
				Vector2(p.x - cw, top_y),
				Vector2(p.x, top_y + r * 0.6),
				Vector2(p.x + cw, top_y)])
			draw_polyline(pts2, chev, 2.5)
