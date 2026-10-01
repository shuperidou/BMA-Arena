class_name DebugLayer
extends Node2D
## 调试 / 空间提示层 (世界坐标)。设计文档第 8、40 节。
##
##  - 空间提示 (接球区域 / 危险走廊 / 接球点)：默认开，帮助理解阻挡机制，不是绝对判罚
##  - 详细调试 (F1)：球状态、速度、高度、弹跳计数、碰撞体等

var enabled: bool = false
var match_ref: Match = null

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if match_ref == null:
		return
	if GameConfig.show_hints:
		_draw_hints()
	if enabled:
		_draw_debug()

func _draw_hints() -> void:
	var bs: BlockSystem = match_ref.block_system
	if bs == null or not bs.active or bs.receiver == null or bs.opponent == null:
		return
	var a: Vector2 = bs.receiver.global_position
	var p: Vector2 = bs.intercept_point
	var col := Color(0.3, 0.8, 1.0)
	match bs.state:
		GameTypes.Interference.CONFIRMED:
			col = Color(1.0, 0.3, 0.3)
		GameTypes.Interference.POSSIBLE:
			col = Color(1.0, 0.85, 0.3)
	# 危险走廊 (接球者 -> 预计接球点)
	draw_line(a, p, Color(col, 0.16), GameConfig.block_corridor_width * 2.0, true)
	draw_line(a, p, Color(col, 0.5), 2.0, true)
	# 预计接球点
	draw_circle(p, 16.0, Color(col, 0.18))
	draw_arc(p, 16.0, 0.0, TAU, 28, col, 2.0)
	# 对手是否在走廊里
	if bs.state != GameTypes.Interference.NONE:
		draw_arc(bs.opponent.global_position, GameConfig.player_radius + 22.0, 0.0, TAU, 28, Color(col, 0.9), 3.0)

func _draw_debug() -> void:
	var font: Font = GameConfig.ui_font()
	if font == null:
		return
	# 场地碰撞体轮廓
	var ar: Rect2 = GameConfig.arena_rect()
	draw_rect(ar, Color(1, 1, 0, 0.4), false, 1.0)
	draw_rect(GameConfig.table_rect(), Color(0, 1, 1, 0.6), false, 2.0)
	draw_rect(GameConfig.wall_rect(), Color(0, 1, 1, 0.6), false, 2.0)
	# 玩家碰撞体轮廓 + 速度
	for pl in match_ref.players:
		var c: Vector2 = pl.global_position
		_draw_capsule(c, pl.rotation, GameConfig.player_half_length, GameConfig.player_radius, Color(0.4, 1, 0.4, 0.8))
		draw_line(c, c + pl.linear_velocity * 0.15, Color(1, 1, 0.2, 0.9), 2.0)
		draw_string(font, c + Vector2(10, -24), "P%d" % pl.player_index,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 1, 0.6, 0.9))
	# 球信息
	var b: Ball = match_ref.ball
	if b != null:
		var txt := "state=%d height=%d\nvel=(%.0f,%.0f)\nz=%.1f vz=%.1f scale=%.2f\n桌弹=%d 接弹=%d\n撞墙=%s 可回击=%s" % [
			b.state, b.height_state, b.vel.x, b.vel.y, b.z, b.vz, b.visual_scale(),
			b.table_bounces, b.receiver_bounces,
			str(b.wall_since_hit), str(b.returnable)]
		draw_string(font, b.global_position + Vector2(16, -12), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.92))
	# 鼠标相对瞄准可视化 (玩家1)
	if match_ref.players.size() > 0:
		_draw_aim(font, match_ref.players[0])

func _draw_aim(font: Font, p1: PlayerController) -> void:
	var sch: InputScheme = p1.input_scheme
	if sch == null or sch.aim_mode != InputScheme.AimMode.MOUSE:
		return
	var o: Vector2 = p1.global_position
	var l: float = GameConfig.player_half_length
	# 桌中心 (参考)
	var tc: Vector2 = GameConfig.table_center
	draw_line(o, tc, Color(1.0, 0.85, 0.2, 0.22), 1.0)
	draw_circle(tc, 8.0, Color(1.0, 0.85, 0.2, 0.2))
	draw_arc(tc, 8.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.2, 0.85), 2.0)
	# 辅助瞄准点: 桌中心关于墙的镜像 (在墙外)
	var mirror: Vector2 = HitSystem.mirror_of_table_center()
	draw_circle(mirror, 7.0, Color(0.8, 0.6, 1.0, 0.25))
	draw_arc(mirror, 7.0, 0.0, TAU, 20, Color(0.8, 0.6, 1.0, 0.9), 2.0)
	draw_line(tc, mirror, Color(0.8, 0.6, 1.0, 0.25), 1.0)
	# 击球区默认位置 (空心) 与当前位置 (实心，HitPoint 也画了触及圈)
	for local_pos in [Vector2(0.0, -l), Vector2(0.0, l)]:
		draw_arc(p1.to_global(local_pos), 6.0, 0.0, TAU, 20, Color(0.6, 0.6, 0.65, 0.85), 1.5)
	if p1.hit_points.size() >= 2:
		draw_circle(p1.hit_points[0].global_position, 4.0, Color(0.35, 1.0, 0.4))
		draw_circle(p1.hit_points[1].global_position, 4.0, Color(0.35, 1.0, 0.4))
		# 角色自身朝向 (绿)
		draw_line(o, o + Vector2.RIGHT.rotated(p1.rotation) * 110.0, Color(0.4, 1.0, 0.4, 0.7), 2.0)
	# 锚点 / 当前鼠标 (世界坐标)
	if sch.is_dragging():
		var anchor: Vector2 = sch.mouse_anchor_world()
		var cur: Vector2 = sch.current_mouse_world(self)
		draw_circle(anchor, 6.0, Color(0.5, 0.85, 1.0, 0.9))
		draw_line(anchor, cur, Color(0.5, 0.85, 1.0, 0.6), 1.5)
		draw_circle(cur, 4.0, Color(0.6, 0.95, 1.0))
	# 击球区世界速度 (箭头)
	for hp in p1.hit_points:
		draw_line(hp.global_position, hp.global_position + hp.velocity * 0.12, Color(1.0, 0.3, 1.0, 0.85), 2.0)
	var a_pos: Vector2 = p1.hit_points[0].position if p1.hit_points.size() >= 2 else Vector2.ZERO
	var b_pos: Vector2 = p1.hit_points[1].position if p1.hit_points.size() >= 2 else Vector2.ZERO
	var txt := "rot=%.2f\nMouseWorldDelta=(%.1f,%.1f)\nHitLocalDelta  =(%.1f,%.1f)\nA_local=(%.1f,%.1f) B_local=(%.1f,%.1f)" % [
		p1.rotation,
		p1.debug_mouse_world_delta.x, p1.debug_mouse_world_delta.y,
		p1.hit_zone_offset_local.x, p1.hit_zone_offset_local.y,
		a_pos.x, a_pos.y, b_pos.x, b_pos.y]
	draw_string(font, o + Vector2(12, 22), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 1.0, 0.9, 0.95))
	# 击球系统信息 (最近一次击球)
	var b: Ball = match_ref.ball
	if b != null and not b.last_hit_info.is_empty():
		var info: Dictionary = b.last_hit_info
		var bp: Vector2 = b.global_position
		var raw: Vector2 = info.get("raw_dir", Vector2.ZERO)
		var ass: Vector2 = info.get("assisted_dir", Vector2.ZERO)
		draw_line(bp, bp + raw * 90.0, Color(1.0, 0.5, 0.2, 0.85), 2.0)   # 原始方向 (橙)
		draw_line(bp, bp + ass * 90.0, Color(0.2, 1.0, 0.5, 0.95), 3.0)   # 辅助后方向 (绿)
		var ht := "Strength=%.2f  ballSpd=%.0f  zoneSpd=%.0f\nRawDir=(%.2f,%.2f)\nAssistDir=(%.2f,%.2f)\nAssistAngle=%.1f deg  ballV=(%.0f,%.0f)" % [
			info.get("strength", 0.0), info.get("ball_speed", 0.0), info.get("zone_speed", 0.0),
			raw.x, raw.y, ass.x, ass.y, rad_to_deg(info.get("assist_angle", 0.0)), b.vel.x, b.vel.y]
		draw_string(font, tc + Vector2(18, 30), ht, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.9, 0.6, 0.95))

func _draw_capsule(c: Vector2, angle: float, hl: float, r: float, color: Color) -> void:
	var seg: float = hl - r
	draw_set_transform(c, angle, Vector2.ONE)
	draw_rect(Rect2(-r, -seg, 2.0 * r, 2.0 * seg), color, false, 1.5)
	draw_arc(Vector2(0.0, -seg), r, 0.0, TAU, 24, color, 1.5)
	draw_arc(Vector2(0.0, seg), r, 0.0, TAU, 24, color, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
