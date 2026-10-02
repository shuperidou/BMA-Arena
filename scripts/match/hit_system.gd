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
	var vz: float = GameConfig.hit_vz_v0
	var g: float = GameConfig.ball_gravity
	var assist: float = clampf(GameConfig.assist_strength, 0.0, 1.0)
	var assisted_dir: Vector2 = raw_dir
	var final_speed: float = ball_speed
	var assist_angle: float = 0.0
	var assist_speed_delta: float = 0.0
	if assist > 0.0 and not _lands_in_good_zone(p, raw_dir, 2.0 * ball_speed * vz / g):
		# 恢复解 (和 AI 一致)：瞄准"桌中心关于墙的镜像点"。
		#   球直接撞墙(回击不先弹桌), 撞墙后水平路径经过桌中心, 再由"墙弹回桌"辅助落桌。
		#   力度不变(只修方向)。
		var tc: Vector2 = GameConfig.table_center
		var wall_y: float = GameConfig.wall_inner_y()
		var mirror := Vector2(tc.x, 2.0 * wall_y - tc.y)
		var to_m: Vector2 = mirror - p
		var recov_dir: Vector2 = to_m.normalized() if to_m.length() > 1.0 else raw_dir
		var da: float = wrapf(recov_dir.angle() - raw_dir.angle(), -PI, PI)
		var cap: float = deg_to_rad(GameConfig.max_assist_angle)
		da = clampf(da, -cap, cap)
		assist_angle = da * assist
		assisted_dir = raw_dir.rotated(assist_angle)
		assist_speed_delta = 0.0
		final_speed = ball_speed

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
