class_name HitPoint
extends Node2D
## 角色两端的击球点。
##
## 现在只有"触及半径"这一个概念，以后可以挂装备 (球拍/课本/电子词典...)
## 改变半径、方向或触发特殊击球。

var reach: float = 22.0
var velocity: Vector2 = Vector2.ZERO        ## 世界空间实际速度 (有限差分)
var swing_velocity: Vector2 = Vector2.ZERO  ## 判定区"挥动"速度 (未夹制, 经身体 rotation; 击球力度依据)
var power01: float = 0.0:                    ## 当前挥拍力量 (0..1) -> 判定区填充色
	set(v):
		power01 = v
		queue_redraw()
var _prev_world: Vector2 = Vector2.ZERO
var _has_prev: bool = false

func _ready() -> void:
	reach = GameConfig.hit_reach
	queue_redraw()

func _physics_process(dt: float) -> void:
	var gp: Vector2 = global_position
	if _has_prev and dt > 0.0:
		velocity = (gp - _prev_world) / dt
	_prev_world = gp
	_has_prev = true

## 是否触及球。
func touches(ball: Ball) -> bool:
	return global_position.distance_to(ball.global_position) <= reach + ball.radius

func _draw() -> void:
	# 填充色随"挥拍力量"变化: 弱=蓝, 强=橙红 (与球的力度配色一致)
	var pw: float = clampf(power01, 0.0, 1.0)
	var fill: Color = Color(0.45, 0.7, 1.0).lerp(Color(1.0, 0.35, 0.15), pw)
	draw_circle(Vector2.ZERO, reach, Color(fill.r, fill.g, fill.b, 0.12 + 0.22 * pw))
	draw_arc(Vector2.ZERO, reach, 0.0, TAU, 28, Color(fill.r, fill.g, fill.b, 0.6), 2.0)
	draw_circle(Vector2.ZERO, 3.0, Color(fill.r, fill.g, fill.b))
