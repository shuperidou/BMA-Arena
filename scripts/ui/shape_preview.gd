class_name ShapePreview
extends Control
## 候选身体略图: 画纺锤轮廓 (长/宽/大小), 让玩家"看图选" (变异面板用)。
## 固定参考归一化 -> 各候选之间的相对大小可见。

var half_len: float = 90.0
var radius: float = 14.0
var size_scale: float = 1.0

func setup_candidate(c: Dictionary) -> void:
	half_len = float(c.get("half_len", 90.0))
	radius = float(c.get("radius", 14.0))
	size_scale = float(c.get("size_scale", 1.0))
	custom_minimum_size = Vector2(76, 76)
	queue_redraw()

func _draw() -> void:
	var base: PackedVector2Array = GameConfig.spindle_points(half_len, radius)
	if base.size() < 3:
		return
	var ref: float = GameConfig.mutation_len_max * GameConfig.mutation_size_max
	var c: Vector2 = size * 0.5
	var k: float = (minf(size.x, size.y) * 0.45) / maxf(ref, 1.0)
	var poly := PackedVector2Array()
	for p in base:
		poly.append(c + p * size_scale * k)
	draw_colored_polygon(poly, Color(0.31, 0.82, 0.77, 0.5))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(1, 1, 1, 0.65), 1.5)
