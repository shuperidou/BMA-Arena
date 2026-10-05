class_name ShapePreview
extends Control
## 候选身体略图: 按候选的"身体种类 + 参数"画轮廓, 让玩家"看图选" (变异面板用)。
## 固定参考归一化 -> 各候选之间的相对大小可见。

var cand: Dictionary = {}

func setup_candidate(c: Dictionary) -> void:
	cand = c
	custom_minimum_size = Vector2(76, 76)
	queue_redraw()

func _circle_points(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 32:
		var th: float = TAU * float(k) / 32.0
		pts.append(Vector2(r * cos(th), r * sin(th)))
	return pts

func _draw() -> void:
	var kind: String = String(cand.get("kind", "spindle"))
	var ref: float = GameConfig.mutation_len_max * GameConfig.mutation_size_max
	var base: PackedVector2Array
	if kind == "circle":
		base = _circle_points(float(cand.get("circle_radius", 20.0)))
		ref = 40.0 * GameConfig.mutation_size_max
	elif kind == "polar":
		base = GameConfig.polar_points(float(cand.get("polar_r0", 26.0)),
			int(cand.get("polar_lobes", 4)), float(cand.get("polar_amp", 0.45)))
		ref = 44.0 * 1.85 * GameConfig.mutation_size_max
	elif kind == "superformula":
		base = GameConfig.superformula_points(float(cand.get("sf_m", 6.0)), float(cand.get("sf_n1", 0.6)),
			float(cand.get("sf_n2", 0.6)), float(cand.get("sf_n3", 0.6)), float(cand.get("sf_a", 1.0)),
			float(cand.get("sf_b", 1.0)), float(cand.get("sf_radius", 30.0)))
		ref = 48.0 * 1.85 * GameConfig.mutation_size_max
	else:
		base = GameConfig.spindle_points(float(cand.get("half_len", 90.0)), float(cand.get("radius", 14.0)))
	if base.size() < 3:
		return
	var size_scale: float = float(cand.get("size_scale", 1.0))
	var c: Vector2 = size * 0.5
	var k: float = (minf(size.x, size.y) * 0.45) / maxf(ref, 1.0)
	var poly := PackedVector2Array()
	for p in base:
		poly.append(c + p * size_scale * k)
	draw_colored_polygon(poly, Color(0.31, 0.82, 0.77, 0.5))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(1, 1, 1, 0.65), 1.5)
