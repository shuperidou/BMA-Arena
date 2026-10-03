class_name AiPlayer
extends PlayerController
## 圆形 AI 角色 (替代原来的纺锤玩家2)。
##
## - 只有一个圆形碰撞体 + 中心一个击球判定区 (不用两端判定点)
## - 自主跑向"球的可接住点"
## - 击球完全智能：只要没被阻挡，就一定把球打回桌面 (角度随机变化)

var ai_radius: float = 20.0
var ai_hit_radius: float = 72.0
var _home: Vector2 = Vector2(0.0, 40.0)
var debug_last_error: String = ""   ## 最近一次失误表现 (Debug 用)
var omniscient: bool = false        ## 万能模式: 接到球必落桌 (不夹玩家速度上限, 不失误)

func _ready() -> void:
	gravity_scale = 0.0
	mass = GameConfig.player_mass
	collision_layer = 1
	collision_mask = 3
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp = 0.0
	angular_damp = GameConfig.player_angular_damp

	var cs := CollisionShape2D.new()
	cs.name = "CollisionShape2D"
	var circ := CircleShape2D.new()
	circ.radius = ai_radius
	cs.shape = circ
	add_child(cs)

	var hp := HitPoint.new()
	hp.name = "HitPoint"
	hp.reach = ai_hit_radius
	hp.position = Vector2.ZERO
	add_child(hp)
	hit_points = [hp]

	queue_redraw()

# ------------------------------------------------------------
#  自主移动
# ------------------------------------------------------------
func _desired_move_dir(state: PhysicsDirectBodyState2D) -> Vector2:
	var target: Vector2 = _target_point()
	var d: Vector2 = target - state.transform.origin
	return d.normalized() if d.length() > 6.0 else Vector2.ZERO

func _target_point() -> Vector2:
	if ball == null or ball.state != GameTypes.BallState.LIVE:
		return global_position  # 球不在场(发球/死球): 原地待命
	# 自己刚打完这球 -> 切"防阻挡模式": 绕开对手的接球走廊, 避免被判阻挡
	if ball.last_hitter == self:
		return _anti_block_target()
	# 否则我是接球方 -> 追可接住点
	var pred: Dictionary = ball.predict_catchable()
	if pred.found:
		return pred.point
	return ball.global_position

## 防阻挡：绕到"对手 -> 预计接球点"这条走廊的侧面去。
func _anti_block_target() -> Vector2:
	if rival == null:
		return global_position
	var pred: Dictionary = ball.predict_catchable()
	var p: Vector2 = pred.point if pred.found else ball.global_position
	var h: Vector2 = rival.global_position
	var mid: Vector2 = (h + p) * 0.5
	var seg: Vector2 = p - h
	var perp: Vector2 = Vector2(-seg.y, seg.x).normalized() if seg.length() > 1.0 else Vector2(0.0, 1.0)
	if (global_position - mid).dot(perp) < 0.0:
		perp = -perp
	var target: Vector2 = mid + perp * GameConfig.ai_avoid_distance
	var ar: Rect2 = GameConfig.arena_rect().grow(-40.0)
	return Vector2(clampf(target.x, ar.position.x, ar.end.x), clampf(target.y, ar.position.y, ar.end.y))

# ------------------------------------------------------------
#  智能击球 / 发球 (保证落桌, 角度随机变化)
# ------------------------------------------------------------
func _smart_shot(from: Vector2) -> Dictionary:
	# 目标: 桌面内随机 x (角度变化); 瞄准它关于墙的镜像点 ->
	#   球直接撞墙(回击不先弹桌), 撞墙后水平线经过桌面上该 x, 再由"墙弹回桌"辅助落桌。
	var tr := GameConfig.table_rect()
	var m: float = maxf(GameConfig.assist_good_margin, 20.0)
	var tx: float = randf_range(tr.position.x + m, tr.end.x - m)
	var aim := Vector2(tx, 2.0 * GameConfig.wall_inner_y() - GameConfig.table_center.y)
	var d: Vector2 = aim - from
	var dist: float = maxf(d.length(), 1.0)
	var dir: Vector2 = d / dist
	# vz 限制在"玩家的上下限"内 (AI 不作弊)
	var vz: float = randf_range(GameConfig.hit_vz_min, GameConfig.hit_vz_max)
	# 由 vz 反推水平初速, 使球正好够到镜像点 (z0=桌高时 = dist*g/(2*vz))
	var z0: float = maxf(ball.z, GameConfig.table_z) if ball != null else GameConfig.table_z
	var disc: float = vz * vz + 2.0 * GameConfig.ball_gravity * (z0 - GameConfig.table_z)
	var t_flight: float = (vz + sqrt(maxf(disc, 0.0))) / maxf(GameConfig.ball_gravity, 1.0)
	var speed: float = dist / maxf(t_flight, 0.0001)
	if omniscient:
		# 万能模式: 直接给够速度, 不夹到玩家上限 -> 保证一定能打到桌
		speed = clampf(speed, 1.0, GameConfig.hit_speed_max * 4.0)
	else:
		speed = clampf(speed, GameConfig.hit_speed_min, GameConfig.hit_speed_max)
	# 扣杀 (仅当 F1 开关打开): 球够高 + 概率成功 -> vz 向下、速度由它反推(很快)
	debug_last_error = ""
	var ai_smash: bool = GameConfig.debug_ai_smash and ball != null \
		and ball.z >= GameConfig.ai_smash_height_min \
		and randf() < GameConfig.smash_success_chance
	if ai_smash:
		vz = GameConfig.smash_vz
		var dsc: float = vz * vz + 2.0 * GameConfig.ball_gravity * (z0 - GameConfig.table_z)
		var tfl: float = (vz + sqrt(maxf(dsc, 0.0))) / maxf(GameConfig.ball_gravity, 1.0)
		speed = clampf(dist / maxf(tfl, 0.0001) * GameConfig.smash_speed_mult,
			1.0, GameConfig.hit_speed_max * 4.0)
		debug_last_error = "扣杀"
	elif not omniscient and randf() < GameConfig.ai_error_chance:
		match randi() % 4:
			0:  # 瞄偏
				dir = dir.rotated(deg_to_rad(randf_range(-GameConfig.ai_error_aim_deg, GameConfig.ai_error_aim_deg)))
				debug_last_error = "瞄偏"
			1:  # 太轻
				speed *= GameConfig.ai_error_power_min
				debug_last_error = "太轻"
			2:  # 太重
				speed *= GameConfig.ai_error_power_max
				debug_last_error = "太重"
			3:  # 打反
				dir = -dir
				debug_last_error = "打反"
	return {
		"velocity": dir * speed, "vz": vz, "strength": 1.0,
		"ball_speed": speed, "raw_speed": speed, "zone_speed": 0.0,
		"zone_world": from, "zone_vel": Vector2.ZERO,
		"raw_dir": dir, "assisted_dir": dir, "assist_angle": 0.0, "assist_speed_delta": 0.0,
		"is_smash": ai_smash,
	}

func compute_hit(_hit_point: HitPoint, b: Ball) -> Dictionary:
	return _smart_shot(b.global_position)

func compute_serve(b: Ball) -> Dictionary:
	return _smart_shot(b.global_position)

func _draw() -> void:
	draw_circle(Vector2.ZERO, ai_radius, _body_color)
	draw_arc(Vector2.ZERO, ai_radius, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(1, 1, 1, 0.85))
