class_name Arena
extends Node2D
## 场地：墙 + 课桌 + 活动区域。
##
## 几何全部来自 GameConfig，Arena 只负责：
##  - 画出灰盒
##  - 为"玩家"生成静态碰撞体 (球不使用这些，球用独立的 z 物理)
##
## 玩家被课桌、墙、场地边界挡住；球可以飞过课桌上方，只在落桌/落地上有规则。

var _table_rect: Rect2
var _wall_rect: Rect2
var _arena_rect: Rect2

func _ready() -> void:
	_arena_rect = GameConfig.arena_rect()
	_wall_rect = GameConfig.wall_rect()
	_table_rect = GameConfig.table_rect()
	_build_static_bodies()
	queue_redraw()

func table_rect() -> Rect2:
	return _table_rect

func wall_rect() -> Rect2:
	return _wall_rect

func _build_static_bodies() -> void:
	var t := 40.0
	_add_box("Wall", _wall_rect)
	_add_box("Table", GameConfig.table_block_rect())
	# 三条边界 (左/右/下)，把玩家关在活动区域内
	_add_box("BoundLeft", Rect2(_arena_rect.position.x - t, _arena_rect.position.y - t,
		t, _arena_rect.size.y + 2.0 * t))
	_add_box("BoundRight", Rect2(_arena_rect.end.x, _arena_rect.position.y - t,
		t, _arena_rect.size.y + 2.0 * t))
	_add_box("BoundBottom", Rect2(_arena_rect.position.x - t, _arena_rect.end.y,
		_arena_rect.size.x + 2.0 * t, t))

func _add_box(node_name: String, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.name = node_name
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	cs.position = rect.position + rect.size * 0.5
	body.add_child(cs)
	add_child(body)

func _draw() -> void:
	# 活动区域地面
	draw_rect(_arena_rect, Color(0.13, 0.15, 0.19))
	# 缝隙区域 (桌与墙之间) 稍微提亮，帮助读图
	var gap := Rect2(_arena_rect.position.x, _wall_rect.end.y,
		_arena_rect.size.x, _table_rect.position.y - _wall_rect.end.y)
	draw_rect(gap, Color(0.16, 0.18, 0.22))
	# 课桌
	draw_rect(_table_rect, Color(0.48, 0.36, 0.23))
	draw_rect(_table_rect, Color(0.62, 0.48, 0.32), false, 3.0)
	# 墙
	draw_rect(_wall_rect, Color(0.36, 0.42, 0.54))
	draw_rect(_wall_rect, Color(0.55, 0.63, 0.79), false, 2.0)
	# 边界
	draw_rect(_arena_rect, Color(0.3, 0.33, 0.4), false, 2.0)
