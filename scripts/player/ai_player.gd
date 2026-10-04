class_name AiPlayer
extends PlayerController
## 圆形 AI 角色 (玩家2; 也可用于 "AI vs AI")。
##
## AI 逻辑 (追球/防阻挡/智能击球/发球/扣杀/失误) 已上移到 PlayerController,
## 由 ai_enabled 开关驱动。这里只提供"圆形身体 + 中心一个击球判定点"。

var ai_radius: float = 20.0
var ai_hit_radius: float = 44.0
var _home: Vector2 = Vector2(0.0, 40.0)

func _ready() -> void:
	ai_enabled = true
	gravity_scale = 0.0
	mass = GameConfig.player_mass
	collision_layer = 1
	collision_mask = 3
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp = 0.0
	angular_damp = GameConfig.player_angular_damp

	var cs := CollisionShape2D.new()
	cs.name = "CollisionShape2D"
	var circ := CircleShape2D.new()
	circ.radius = ai_radius
	cs.shape = circ
	add_child(cs)

	var hp := HitPoint.new()
	hp.name = "HitPoint"
	hp.reach = ai_hit_radius
	hp.position = Vector2.ZERO
	add_child(hp)
	hit_points = [hp]

	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, ai_radius, _body_color)
	draw_arc(Vector2.ZERO, ai_radius, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
	draw_circle(Vector2.ZERO, 4.0, Color(1, 1, 1, 0.85))
