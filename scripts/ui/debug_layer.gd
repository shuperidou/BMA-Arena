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
	if sch == null or sch.aim_mode != InputScheme.AimMode.MOUSE or not p1.debug_has_aim:
		return
	var o: Vector2 = p1.global_position
	var ball_xy: Vector2 = match_ref.ball.global_position
	var length := 110.0
	# 球的 XY 投影 (仅参考)
	draw_circle(ball_xy, 3.0, Color(1.0, 0.45, 0.9))
	# 目标方向线 (品红) —— 纯手动
	draw_line(o, o + Vector2.RIGHT.rotated(p1.debug_target_rotation) * length, Color(1.0, 0.35, 0.85, 0.9), 2.0)
	# 角色当前朝向 (绿)
	draw_line(o, o + Vector2.RIGHT.rotated(p1.rotation) * length, Color(0.4, 1.0, 0.4, 0.85), 2.0)
	# 锚点 / 当前鼠标 (用世界坐标绘制)
	var dx_screen: float = 0.0
	if sch.is_dragging():
		var anchor: Vector2 = sch.mouse_anchor_world()
		var cur: Vector2 = sch.current_mouse_world(self)
		dx_screen = sch.mouse_drag_screen_x(self)
		draw_circle(anchor, 6.0, Color(0.5, 0.85, 1.0, 0.9))
		draw_line(anchor, cur, Color(0.5, 0.85, 1.0, 0.6), 1.5)
		draw_circle(cur, 4.0, Color(0.6, 0.95, 1.0))
	var txt := "offset=%.2f target=%.2f rot=%.2f\ndrag=%s dx=%.0fpx" % [
		p1.debug_angle_offset, p1.debug_target_rotation, p1.rotation,
		str(sch.is_dragging()), dx_screen]
	draw_string(font, o + Vector2(12, 20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.7, 0.95, 0.95))

func _draw_capsule(c: Vector2, angle: float, hl: float, r: float, color: Color) -> void:
	var seg: float = hl - r
	draw_set_transform(c, angle, Vector2.ONE)
	draw_rect(Rect2(-r, -seg, 2.0 * r, 2.0 * seg), color, false, 1.5)
	draw_arc(Vector2(0.0, -seg), r, 0.0, TAU, 24, color, 1.5)
	draw_arc(Vector2(0.0, seg), r, 0.0, TAU, 24, color, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
