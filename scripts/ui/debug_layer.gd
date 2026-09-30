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

func _draw_capsule(c: Vector2, angle: float, hl: float, r: float, color: Color) -> void:
	var seg: float = hl - r
	draw_set_transform(c, angle, Vector2.ONE)
	draw_rect(Rect2(-r, -seg, 2.0 * r, 2.0 * seg), color, false, 1.5)
	draw_arc(Vector2(0.0, -seg), r, 0.0, TAU, 24, color, 1.5)
	draw_arc(Vector2(0.0, seg), r, 0.0, TAU, 24, color, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
