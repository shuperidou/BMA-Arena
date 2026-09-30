class_name HitPoint
extends Node2D
## 角色两端的击球点。
##
## 现在只有"触及半径"这一个概念，以后可以挂装备 (球拍/课本/电子词典...)
## 改变半径、方向或触发特殊击球。

var reach: float = 22.0

func _ready() -> void:
	reach = GameConfig.hit_reach
	queue_redraw()

## 是否触及球。
func touches(ball: Ball) -> bool:
	return global_position.distance_to(ball.global_position) <= reach + ball.radius

func _draw() -> void:
	draw_circle(Vector2.ZERO, reach, Color(0.35, 1.0, 0.4, 0.12))
	draw_arc(Vector2.ZERO, reach, 0.0, TAU, 28, Color(0.35, 1.0, 0.4, 0.55), 2.0)
	draw_circle(Vector2.ZERO, 3.0, Color(0.35, 1.0, 0.4))
