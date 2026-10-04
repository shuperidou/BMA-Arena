class_name ShapePreview
extends Control
## 候选形状略图: 画出形状轮廓, 让玩家"看图选" (变异面板用)。
## 用固定参考半径归一化 -> 各候选之间的相对大小可见。

var shape_index: int = 0
var size_scale: float = 1.0

const BASE_MAX_EXTENT: float = 90.0   ## 各形状基准下的最大半径 (纺锤半长 ~90)

func setup(si: int, ss: float) -> void:
	shape_index = si
	size_scale = ss
	custom_minimum_size = Vector2(76, 76)
	queue_redraw()

func _draw() -> void:
	var base: PackedVector2Array = GameConfig.player_shape_points(shape_index)
	if base.size() < 3:
		return
	# player_shape_points 已乘了全局 size; 先还原成基准形状, 再按"候选 size"缩放
	var g: float = maxf(GameConfig.player_size_scale, 0.05)
	var ref: float = GameConfig.mutation_size_max * BASE_MAX_EXTENT
	var c: Vector2 = size * 0.5
	var k: float = (minf(size.x, size.y) * 0.45) / maxf(ref, 1.0)
	var poly := PackedVector2Array()
	for p in base:
		poly.append(c + p * (size_scale / g) * k)
	draw_colored_polygon(poly, Color(0.31, 0.82, 0.77, 0.5))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(1, 1, 1, 0.65), 1.5)
