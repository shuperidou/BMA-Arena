class_name HitSystem
extends RefCounted
## 击球系统 (独立模块)。
##
## 输入: 击球者、被触发的击球判定区、球。
## 输出: 球的发射速度/方向 + 调试信息。
##
## 三个因素共同决定击球结果:
##   1) 击球区位置  -> 方向偏置 (相对身体的方向)
##   2) 击球区世界速度 -> 力度 (并参与方向偏置)
##   3) 智能回球辅助 -> 当原始方向会直接飞出桌面时，做有上限的方向修正
##
## 参数全部来自 GameConfig (hit_speed_* / hit_direction_strength / max_assist_angle ...)。

static func compute(player: PlayerController, zone: HitPoint, ball: Ball) -> Dictionary:
	var facing: Vector2 = Vector2.RIGHT.rotated(player.rotation)  # 面向桌中心 (基准方向)
	var zone_world: Vector2 = zone.global_position
	var zone_vel: Vector2 = zone.velocity
	var speed: float = zone_vel.length()

	# --- 力度：世界速度 -> 曲线 -> 球速 ---
	var t: float = clampf(speed / maxf(GameConfig.hit_zone_speed_ref, 1.0), 0.0, 1.0)
	var strength: float = pow(t, maxf(GameConfig.hit_speed_curve, 0.05))
	var ball_speed: float = lerpf(GameConfig.hit_speed_min, GameConfig.hit_speed_max, strength)

	# --- 原始方向：面向桌中心 + 偏置(位置 + 挥动) ---
	var outward: Vector2 = zone_world - player.global_position
	outward = outward.normalized() if outward.length() > 1.0 else facing
	var swing: Vector2 = zone_vel / speed if speed > 1.0 else Vector2.ZERO
	# 偏置是"位置 + 挥动"的加权和 (不归一化，权重才有意义)
	var bias: Vector2 = outward * GameConfig.position_bias_weight + swing
	var raw_dir: Vector2 = (facing + bias * GameConfig.hit_direction_strength).normalized()

	# --- 智能回球辅助 (0..1 单一旋钮) ---
	#   assist=0 -> 完全用原始击球
	#   assist=1 -> 只要触球就保证回桌 (方向+力度都拉到"瞄准桌中心并落桌"的解)
	#   0..1    -> 按比例混合
	var p: Vector2 = ball.global_position
	var vz: float = GameConfig.ball_hit_vz
	var g: float = GameConfig.ball_gravity
	var assist: float = clampf(GameConfig.assist_strength, 0.0, 1.0)
	var assisted_dir: Vector2 = raw_dir
	var final_speed: float = ball_speed
	var assist_angle: float = 0.0
	var assist_speed_delta: float = 0.0
	if assist > 0.0 and not _lands_in_good_zone(p, raw_dir, 2.0 * ball_speed * vz / g):
		# 恢复解 (镜面法)：
		#   方向 = 指向"桌中心关于墙的镜像点" -> 球撞墙反弹后水平路径经过桌中心
		#   力度 = 单独选，让第一次落桌仍在桌面内 (镜像点在墙外，不能当落点)
		var tc: Vector2 = GameConfig.table_center
		var wall_y: float = GameConfig.wall_inner_y()
		var mirror := Vector2(tc.x, 2.0 * wall_y - tc.y)
		var to_m: Vector2 = mirror - p
		var recov_dir: Vector2 = to_m.normalized() if to_m.length() > 1.0 else raw_dir
		var recov_speed: float = _recovery_speed(p, recov_dir, vz, g, ball_speed)
		var da: float = wrapf(recov_dir.angle() - raw_dir.angle(), -PI, PI)
		var cap: float = deg_to_rad(GameConfig.max_assist_angle)
		da = clampf(da, -cap, cap)
		assist_angle = da * assist
		assisted_dir = raw_dir.rotated(assist_angle)
		var new_speed: float = lerpf(ball_speed, recov_speed, assist)
		assist_speed_delta = new_speed - ball_speed
		final_speed = new_speed

	return {
		"velocity": assisted_dir * final_speed,
		"vz": vz,
		"strength": strength,
		"ball_speed": final_speed,
		"raw_speed": ball_speed,
		"zone_speed": speed,
		"zone_world": zone_world,
		"zone_vel": zone_vel,
		"raw_dir": raw_dir,
		"assisted_dir": assisted_dir,
		"assist_angle": assist_angle,
		"assist_speed_delta": assist_speed_delta,
	}

## 沿 dir 飞出 dist 后是否落在桌面内。
static func _lands_on_table(p: Vector2, dir: Vector2, dist: float) -> bool:
	return GameConfig.table_rect().grow(-4.0).has_point(p + dir * dist)

## 落点是否落在"好区"(桌面内缩 assist_good_margin)。不在则触发辅助。
static func _lands_in_good_zone(p: Vector2, dir: Vector2, dist: float) -> bool:
	return GameConfig.table_rect().grow(-GameConfig.assist_good_margin).has_point(p + dir * dist)

## 桌中心关于墙的镜像点 (墙在俯视上是水平镜面 -> 翻转 y)。
static func mirror_of_table_center() -> Vector2:
	var tc := GameConfig.table_center
	return Vector2(tc.x, 2.0 * GameConfig.wall_inner_y() - tc.y)

## 恢复力度 (选项2：优先保留玩家力量 / 救球)。
## 沿恢复方向，只要"玩家原本的球速"就能让第一次落桌落在好区内 -> 原速保留；
## 只有当该速度打不到好区 (太快或太慢) 时，才把它夹到"最快能落进好区"的距离。
static func _recovery_speed(p: Vector2, dir: Vector2, vz: float, g: float, raw_speed: float) -> float:
	var good := GameConfig.table_rect().grow(-GameConfig.assist_good_margin)
	var seg: Array = _ray_rect_segment(p, dir, good)
	if seg.is_empty():
		seg = _ray_rect_segment(p, dir, GameConfig.table_rect())
	if seg.size() != 2:
		return raw_speed  # 判断不了就保留原力量
	var t0: float = seg[0]
	var t1: float = seg[1]
	var d_raw: float = 2.0 * raw_speed * vz / g      # 玩家原力量对应的落点距离
	var d: float = clampf(d_raw, t0, t1)             # 在好区内就保留, 否则夹到最近一端
	# 速度下限: hit_speed_min * assist_min_speed_ratio (1.0 = 与 AI 下限一致)
	var floor_speed: float = GameConfig.hit_speed_min * GameConfig.assist_min_speed_ratio
	return clampf(d * g / (2.0 * vz), floor_speed, GameConfig.hit_speed_max)

## 射线 p+dir*t 与矩形相交的参数区间 [t0,t1] (t>=0)；不相交返回 []。
static func _ray_rect_segment(p: Vector2, dir: Vector2, rect: Rect2) -> Array:
	var tmin: float = -INF
	var tmax: float = INF
	if absf(dir.x) < 1e-6:
		if p.x < rect.position.x or p.x > rect.end.x:
			return []
	else:
		var ta: float = (rect.position.x - p.x) / dir.x
		var tb: float = (rect.end.x - p.x) / dir.x
		tmin = maxf(tmin, minf(ta, tb))
		tmax = minf(tmax, maxf(ta, tb))
	if absf(dir.y) < 1e-6:
		if p.y < rect.position.y or p.y > rect.end.y:
			return []
	else:
		var tc2: float = (rect.position.y - p.y) / dir.y
		var td: float = (rect.end.y - p.y) / dir.y
		tmin = maxf(tmin, minf(tc2, td))
		tmax = minf(tmax, maxf(tc2, td))
	var lo: float = maxf(tmin, 0.0)
	if tmax < lo:
		return []
	return [lo, tmax]
