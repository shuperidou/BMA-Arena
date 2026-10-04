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
	var perp: Vector2 = facing.rotated(PI * 0.5)                  # 垂直于朝向 (角色局部 +y)
	var zone_world: Vector2 = zone.global_position
	# 用"挥动速度"(未夹制的鼠标拖动, 经身体 rotation)，而不是被 max_offset 夹住的判定区实际速度
	var zone_vel: Vector2 = zone.swing_velocity
	var speed: float = zone_vel.length()
	var ref: float = maxf(GameConfig.hit_zone_speed_ref, 1.0)
	# 把判定区世界速度分解成"沿朝向"和"垂直朝向"两个正交分量:
	#   v_along (沿朝向)   -> 球速 (主要影响因素)
	#   v_perp  (垂直朝向) -> vy/弧线 (鼠标向下=增大, 向上=减小)
	var v_along: float = zone_vel.dot(facing)
	var v_perp: float = zone_vel.dot(perp)

	# --- 力度：沿朝向的分速度 -> 曲线 -> 球速 (用绝对值: 左右任一向甩都能发力, 不再只有单向) ---
	var t: float = clampf(absf(v_along) / ref, 0.0, 1.0)
	var strength: float = pow(t, maxf(GameConfig.hit_speed_curve, 0.05))
	var ball_speed: float = lerpf(GameConfig.hit_speed_min, GameConfig.hit_speed_max, strength)

	# --- 原始方向：面向桌中心 + 偏置(位置 + 挥动) ---
	var outward: Vector2 = zone_world - player.global_position
	outward = outward.normalized() if outward.length() > 1.0 else facing
	var swing: Vector2 = zone_vel / speed if speed > 1.0 else Vector2.ZERO
	# 偏置是"位置 + 挥动"的加权和 (不归一化，权重才有意义)
	var bias: Vector2 = outward * GameConfig.position_bias_weight + swing
	var raw_dir: Vector2 = (facing + bias * GameConfig.hit_direction_strength).normalized()

	# --- vy/弧线 + 智能辅助 + 防守姿态 ---
	var p: Vector2 = ball.global_position
	# vy/弧线：由"垂直于朝向的分速度"决定 (鼠标向下 -> v_perp>0 -> vy增大)
	var perp_t: float = clampf(v_perp / ref, -1.0, 1.0)
	var vz: float = clampf(GameConfig.hit_vz_v0 + perp_t * GameConfig.hit_vz_perp_gain,
		GameConfig.hit_vz_min, GameConfig.hit_vz_max)
	var g: float = GameConfig.ball_gravity
	var assist: float = clampf(GameConfig.assist_strength, 0.0, 1.0)
	var assisted_dir: Vector2 = raw_dir
	var final_speed: float = ball_speed
	var assist_angle: float = 0.0
	var assist_speed_delta: float = 0.0

	# 触发判定。优先级: 扣杀 > 救球 > 其它 (互斥, 先到先得)。
	var is_defense: bool = v_perp > GameConfig.defense_perp_threshold \
		and absf(v_along) < v_perp * GameConfig.defense_max_along_ratio
	# 扣杀三级: 尝试(条件) / 成功(能走完墙桌循环, 过概率) / 无敌(成功后不被接住, 再过概率)
	var smash_attempt: bool = ball.z >= GameConfig.smash_height_min \
		and strength >= GameConfig.smash_power_min
	var is_smash: bool = smash_attempt and randf() < GameConfig.smash_success_chance
	var smash_invincible: bool = false
	var defense_saved: bool = false
	if is_smash:
		is_defense = false
		smash_invincible = randf() < GameConfig.smash_invincible_chance
	elif is_defense:
		vz = clampf(vz * GameConfig.defense_vz_mult, GameConfig.hit_vz_min, GameConfig.hit_vz_max)
		defense_saved = randf() < GameConfig.defense_save_chance   # 救球成功概率 0~1

	# 墙镜像恢复方向 (桌中心关于墙的镜像)
	var tc: Vector2 = GameConfig.table_center
	var wall_y: float = GameConfig.wall_inner_y()
	var mirror := Vector2(tc.x, 2.0 * wall_y - tc.y)
	var to_m: Vector2 = mirror - p
	var recov_dir: Vector2 = to_m.normalized() if to_m.length() > 1.0 else raw_dir
	var da: float = wrapf(recov_dir.angle() - raw_dir.angle(), -PI, PI)
	var cap: float = deg_to_rad(GameConfig.max_assist_angle)
	da = clampf(da, -cap, cap)

	if is_smash:
		# 扣杀成功: 舍弃固定参数, 按实际几何自由反解 —— 取目标落点 T(桌上), 反推(vz向下 + 水平速度),
		# 让球"先撞墙、再正好砸到 T" (用镜像 + 墙反射损耗补偿)。保证一定上桌。
		var tr_s: Rect2 = GameConfig.table_rect()
		var T: Vector2 = Vector2(
			clampf(p.x + randf_range(-70.0, 70.0), tr_s.position.x + 30.0, tr_s.end.x - 30.0),
			tc.y + randf_range(-25.0, 25.0))
		var M: Vector2 = Vector2(T.x, 2.0 * wall_y - T.y)
		var to_M: Vector2 = M - p
		var dist_m: float = maxf(to_M.length(), 1.0)
		assisted_dir = to_M / dist_m
		vz = -absf(GameConfig.smash_vz)                       # 向下
		var z0s: float = maxf(ball.z, GameConfig.table_z)
		var discs: float = vz * vz + 2.0 * g * (z0s - GameConfig.table_z)
		var tfs: float = (vz + sqrt(maxf(discs, 0.0))) / maxf(g, 1.0)
		var wbf: float = clampf(GameConfig.wall_bounce_factor, 0.05, 1.0)
		var fw: float = 0.0
		if absf(p.y - M.y) > 1.0:
			fw = clampf((p.y - wall_y) / (p.y - M.y), 0.0, 1.0)
		var tfs_eff: float = maxf(tfs * (1.0 - (1.0 - wbf) * fw), 0.0001)
		final_speed = clampf(dist_m / tfs_eff, GameConfig.hit_speed_min, GameConfig.hit_speed_max * 4.0)
		assist_angle = 0.0
	elif smash_attempt:
		# 扣杀失败(失误): 方向打歪 + vz 向下 -> 球多半撞到桌(墙前跳弹)再弹飞/出界, 由击球方失误
		vz = -absf(GameConfig.smash_vz)
		var skew: float = deg_to_rad(randf_range(-GameConfig.smash_fail_skew_deg, GameConfig.smash_fail_skew_deg))
		assisted_dir = raw_dir.rotated(skew)
		final_speed = ball_speed
		assist_angle = skew
	elif is_defense and defense_saved:
		# 救球成功: vz 固定, 由它反推水平初速, 让球正好"够到"墙后镜像(桌中心)附近。
		# 于是球上抛撞墙、再落回桌面时, 落点≈桌中心 -> 保证真的救起来。
		var target: Vector2 = mirror + _save_target_offset()
		var to_t: Vector2 = target - p
		var dist: float = maxf(to_t.length(), 1.0)
		assisted_dir = to_t / dist
		# 从当前高度 z0 抛起、落回桌面高 table_z 所需的时间 (z0=table_z 时 = 2*vz/g)
		var z0: float = maxf(ball.z, GameConfig.table_z)
		var disc: float = vz * vz + 2.0 * g * (z0 - GameConfig.table_z)
		var t_flight: float = (vz + sqrt(maxf(disc, 0.0))) / maxf(g, 1.0)
		final_speed = clampf(dist / maxf(t_flight, 0.0001) * GameConfig.defense_save_speed_mult,
			0.0, GameConfig.hit_speed_max * 3.0)
		assist_angle = 0.0
	elif is_defense:
		# 防守失败: 不给任何辅助(用原始方向, 大概率丢分)
		assist_angle = 0.0
		assisted_dir = raw_dir
		final_speed = ball_speed
	elif assist > 0.0 and not _lands_in_good_zone(p, raw_dir, 2.0 * ball_speed * vz / g):
		# 常规辅助：按 assist_strength 混合到镜像方向
		assist_angle = da * assist
		assisted_dir = raw_dir.rotated(assist_angle)
		final_speed = ball_speed
		# 力度容错: 只修方向不够; 把球速朝"正好够到墙后镜像"的方向拉一点 (让力度差一点的球也能进好区)
		var t_fl: float = 2.0 * vz / maxf(g, 1.0)
		if t_fl > 0.0001:
			var need_speed: float = (mirror - p).length() / t_fl
			var ss: float = clampf(GameConfig.assist_speed_strength, 0.0, 1.0) * assist
			final_speed = clampf(lerpf(ball_speed, need_speed, ss),
				GameConfig.hit_speed_min, GameConfig.hit_speed_max)

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
		"is_defense": is_defense,
		"defense_saved": defense_saved,
		"smash_attempt": smash_attempt,
		"is_smash": is_smash,
		"smash_invincible": smash_invincible,
	}

## 救球目标点: 墙后镜像 + 在 defense_save_offset 半径内的随机偏移 (0=正中)。
static func _save_target_offset() -> Vector2:
	var r: float = GameConfig.defense_save_offset
	if r <= 0.0:
		return Vector2.ZERO
	var a: float = randf() * TAU
	var d: float = sqrt(randf()) * r
	return Vector2(cos(a), sin(a)) * d

## 沿 dir 飞出 dist 后是否落在桌面内。
static func _lands_on_table(p: Vector2, dir: Vector2, dist: float) -> bool:
	return GameConfig.table_rect().grow(-4.0).has_point(p + dir * dist)

## 落点是否落在"好区"(桌面内缩 assist_good_margin)。不在则触发辅助。
## 注意: 要按**真实弹道**判断 —— 若中途撞到墙, 用反射后的落点 (否则瞄准墙的球永远"出界", 被拉回中心)。
static func _lands_in_good_zone(p: Vector2, dir: Vector2, dist: float) -> bool:
	var endp: Vector2 = p + dir * dist
	if dir.y < 0.0 and endp.y < GameConfig.wall_inner_y():
		endp = Vector2(endp.x, 2.0 * GameConfig.wall_inner_y() - endp.y)
	return GameConfig.table_rect().grow(-GameConfig.assist_good_margin).has_point(endp)

## 桌中心关于墙的镜像点 (墙在俯视上是水平镜面 -> 翻转 y)。
static func mirror_of_table_center() -> Vector2:
	var tc := GameConfig.table_center
	return Vector2(tc.x, 2.0 * GameConfig.wall_inner_y() - tc.y)
