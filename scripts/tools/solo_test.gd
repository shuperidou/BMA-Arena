extends Node
## 单人调试模式冒烟测试：玩家2 消失，玩家1 自己发球自己接。
## 运行: godot --headless --path <project> res://scenes/SoloTest.tscn

var main_node: Node
var match_ref: Match
var ball: Ball
var p1: PlayerController
var events: Array[String] = []
var t: float = 0.0

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	match_ref = main_node.match_ref
	ball = main_node.ball
	p1 = main_node.players[0]
	p1.input_scheme = null  # 测试里手动摆位

	# 开启单人模式 (等价于 F1 后按 1)
	main_node._toggle_solo()
	p1.global_position = Vector2(0.0, -10.0)
	p1.rotation = -PI / 2.0
	p1.linear_velocity = Vector2.ZERO
	p1.angular_velocity = 0.0

	ball.table_bounced.connect(func(i: int) -> void: events.append("T%d" % i))
	ball.wall_bounced.connect(func() -> void: events.append("W"))
	p1.ball_touched.connect(func(pl: PlayerController, _hp: HitPoint) -> void: events.append("HIT"))
	ball.died.connect(func(r: int) -> void:
		events.append("DIE%d@%.0f" % [r, ball.global_position.y]))

	match_ref._do_serve(p1)

func _physics_process(delta: float) -> void:
	t += delta
	if match_ref == null or ball == null:
		return
	if t < 4.0 and ball.state == GameTypes.BallState.LIVE and ball.returnable:
		p1.global_position = ball.global_position + Vector2(0.0, GameConfig.player_half_length)
		p1.rotation = 0.0
		p1.linear_velocity = Vector2.ZERO
		p1.angular_velocity = 0.0
	if t > 5.0:
		var p2: PlayerController = match_ref.players[1]
		print("SOLO events=", events)
		print("SOLO p2.visible=", p2.visible, " frozen=", p2.freeze, " layer=", p2.collision_layer)
		print("SOLO score=", match_ref.scores, " solo=", match_ref.solo_mode)
		get_tree().quit()
