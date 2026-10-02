class_name DebugLayer
extends Node2D
## 调试层 (世界坐标)。只在 F1 打开时绘制；分类开关见 GameConfig.debug_show_*。

var enabled: bool = false
var match_ref: Match = null

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if match_ref == null or not enabled:
		return
	if GameConfig.debug_show_block:
		_draw_block()
	if GameConfig.debug_show_zones:
		_draw_zones()
	if GameConfig.debug_show_shapes:
		_draw_shapes()
	if GameConfig.debug_show_ball:
		_draw_ball()
	if GameConfig.debug_show_aim:
		_draw_aim()

# ------------------------------------------------------------
#  阻挡：扇区 + 判定三因子
# ------------------------------------------------------------
func _draw_block() -> void:
	var bs: BlockSystem = match_ref.block_system
	if bs == null or not bs.active or bs.receiver == null or bs.opponent == null:
		return
	var a: Vector2 = bs.receiver.global_position
	var col := Color(0.3, 0.8, 1.0)
	match bs.state:
		GameTypes.Interference.CONFIRMED:
			col = Color(1.0, 0.1, 0.1)
		GameTypes.Interference.POSSIBLE:
			col = Color(1.0, 0.35, 0.2)
	# 速度扇区
	if bs.sector_axis.length_squared() > 0.001:
		var center_ang: float = bs.sector_axis.angle()
		var half: float = deg_to_rad(GameConfig.block_sector_half_angle)
		var r: float = GameConfig.block_sector_radius
		var pts := PackedVector2Array()
		pts.append(a)
		var steps := 24
		for i in steps + 1:
			var ang: float = center_ang - half + (2.0 * half) * float(i) / float(steps)
			pts.append(a + Vector2.RIGHT.rotated(ang) * r)
		draw_colored_polygon(pts, Color(col, 0.12))
		draw_line(a, a + Vector2.RIGHT.rotated(center_ang - half) * r, Color(col, 0.6), 1.5)
		draw_line(a, a + Vector2.RIGHT.rotated(center_ang + half) * r, Color(col, 0.6), 1.5)
		draw_line(a, a + bs.sector_axis * r, Color(col, 0.8), 2.0)
	# 预计接球点 (参考)
	draw_circle(bs.intercept_point, 12.0, Color(col, 0.15))
	draw_arc(bs.intercept_point, 12.0, 0.0, TAU, 20, Color(col, 0.7), 2.0)
	if bs.state != GameTypes.Interference.NONE:
		draw_arc(bs.opponent.global_position, GameConfig.player_radius + 22.0, 0.0, TAU, 28, Color(col, 0.9), 3.0)
	# 三因子
	var f: Font = GameConfig.ui_font()
	if f != null:
		var txt := "阻挡判定:\n 1 意图 speed=%.0f (>=%.0f) %s\n 2 扇区 dist=%.0f/%.0f  ang=%.0f/%.0f  %s\n 3 接触 %.0fms/%.0fms  %s\n -> %s" % [
			bs.dbg_speed, GameConfig.block_pursuit_speed, _ok(bs.dbg_has_intent),
			bs.dbg_dist, GameConfig.block_sector_radius,
			bs.dbg_angle_deg, GameConfig.block_sector_half_angle, _ok(bs.dbg_in_sector),
			bs.dbg_contact * 1000.0, GameConfig.block_min_contact_time * 1000.0, _ok(bs.dbg_collided),
			_state_name(bs.state)]
		draw_string(f, a + Vector2(14, -92), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(col, 0.95))

func _ok(b: bool) -> String:
	return "OK" if b else "--"

func _state_name(s: int) -> String:
	match s:
		GameTypes.Interference.CONFIRMED:
			return "CONFIRMED(阻挡)"
		GameTypes.Interference.POSSIBLE:
			return "POSSIBLE(风险)"
	return "NONE"

# ------------------------------------------------------------
#  场地 / 碰撞体 / 球 / 瞄准
# ------------------------------------------------------------
func _draw_zones() -> void:
	draw_rect(GameConfig.arena_rect(), Color(1, 1, 0, 0.4), false, 1.0)
	draw_rect(GameConfig.table_rect(), Color(0, 1, 1, 0.6), false, 2.0)
	draw_rect(GameConfig.wall_rect(), Color(0, 1, 1, 0.6), false, 2.0)

func _draw_shapes() -> void:
	var font: Font = GameConfig.ui_font()
	for pl in match_ref.players:
		var c: Vector2 = pl.global_position
		if pl is AiPlayer:
			draw_arc(c, (pl as AiPlayer).ai_radius, 0.0, TAU, 32, Color(0.4, 1, 0.4, 0.8), 1.5)
			draw_circle(c, 3.0, Color(0.4, 1, 0.4, 0.9))
			if font != null and (pl as AiPlayer).debug_last_error != "":
				draw_string(font, c + Vector2(10, 36), "AI失误: " + (pl as AiPlayer).debug_last_error,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.5, 0.5, 0.95))
		else:
			_draw_capsule(c, pl.rotation, GameConfig.player_half_length, GameConfig.player_radius, Color(0.4, 1, 0.4, 0.8))
		draw_line(c, c + pl.linear_velocity * 0.15, Color(1, 1, 0.2, 0.9), 2.0)
		if font != null:
			draw_string(font, c + Vector2(10, -24), "P%d" % pl.player_index,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 1, 0.6, 0.9))

func _draw_ball() -> void:
	var b: Ball = match_ref.ball
	var font: Font = GameConfig.ui_font()
	if b == null or font == null:
		return
	var txt := "state=%d height=%d\nvel=(%.0f,%.0f)\nz=%.1f vz=%.1f scale=%.2f\n桌弹=%d 接弹=%d\n撞墙=%s 可回击=%s" % [
		b.state, b.height_state, b.vel.x, b.vel.y, b.z, b.vz, b.visual_scale(),
		b.table_bounces, b.receiver_bounces,
		str(b.wall_since_hit), str(b.returnable)]
	draw_string(font, b.global_position + Vector2(16, -12), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.92))

func _draw_aim() -> void:
	var font: Font = GameConfig.ui_font()
	if font == null or match_ref.players.size() == 0:
		return
	var p1: PlayerController = match_ref.players[0]
	var sch: InputScheme = p1.input_scheme
	if sch == null or sch.aim_mode != InputScheme.AimMode.MOUSE:
		return
	var o: Vector2 = p1.global_position
	var l: float = GameConfig.player_half_length
	var tc: Vector2 = GameConfig.table_center
	draw_line(o, tc, Color(1.0, 0.85, 0.2, 0.22), 1.0)
	draw_circle(tc, 8.0, Color(1.0, 0.85, 0.2, 0.2))
	draw_arc(tc, 8.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.2, 0.85), 2.0)
	# 辅助瞄准点: 桌中心关于墙的镜像 (墙外)
	var mirror: Vector2 = HitSystem.mirror_of_table_center()
	draw_circle(mirror, 7.0, Color(0.8, 0.6, 1.0, 0.25))
	draw_arc(mirror, 7.0, 0.0, TAU, 20, Color(0.8, 0.6, 1.0, 0.9), 2.0)
	draw_line(tc, mirror, Color(0.8, 0.6, 1.0, 0.25), 1.0)
	# 击球区默认位置 (空心) 与当前位置 (实心)
	for local_pos in [Vector2(0.0, -l), Vector2(0.0, l)]:
		draw_arc(p1.to_global(local_pos), 6.0, 0.0, TAU, 20, Color(0.6, 0.6, 0.65, 0.85), 1.5)
	if p1.hit_points.size() >= 2:
		draw_circle(p1.hit_points[0].global_position, 4.0, Color(0.35, 1.0, 0.4))
		draw_circle(p1.hit_points[1].global_position, 4.0, Color(0.35, 1.0, 0.4))
		draw_line(o, o + Vector2.RIGHT.rotated(p1.rotation) * 110.0, Color(0.4, 1.0, 0.4, 0.7), 2.0)
	if sch.is_dragging():
		var anchor: Vector2 = sch.mouse_anchor_world()
		var cur: Vector2 = sch.current_mouse_world(self)
		draw_circle(anchor, 6.0, Color(0.5, 0.85, 1.0, 0.9))
		draw_line(anchor, cur, Color(0.5, 0.85, 1.0, 0.6), 1.5)
		draw_circle(cur, 4.0, Color(0.6, 0.95, 1.0))
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
		draw_line(bp, bp + raw * 90.0, Color(1.0, 0.5, 0.2, 0.85), 2.0)
		draw_line(bp, bp + ass * 90.0, Color(0.2, 1.0, 0.5, 0.95), 3.0)
		var ht := "Strength=%.2f  zoneSpd=%.0f\nrawSpd=%.0f -> ballSpd=%.0f (assist %+.0f)\nRawDir=(%.2f,%.2f)\nAssistDir=(%.2f,%.2f)\nAssistAngle=%.1f deg  ballV=(%.0f,%.0f)" % [
			info.get("strength", 0.0), info.get("zone_speed", 0.0),
			info.get("raw_speed", 0.0), info.get("ball_speed", 0.0), info.get("assist_speed_delta", 0.0),
			raw.x, raw.y, ass.x, ass.y, rad_to_deg(info.get("assist_angle", 0.0)), b.vel.x, b.vel.y]
		draw_string(font, tc + Vector2(18, 30), ht, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.9, 0.6, 0.95))

func _draw_capsule(c: Vector2, angle: float, hl: float, r: float, color: Color) -> void:
	var seg: float = hl - r
	draw_set_transform(c, angle, Vector2.ONE)
	draw_rect(Rect2(-r, -seg, 2.0 * r, 2.0 * seg), color, false, 1.5)
	draw_arc(Vector2(0.0, -seg), r, 0.0, TAU, 24, color, 1.5)
	draw_arc(Vector2(0.0, seg), r, 0.0, TAU, 24, color, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
