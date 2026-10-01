extends Node
## 无头自动对拉测试。
## 运行: godot --headless --path <project> res://scenes/RallyTest.tscn
## 由测试直接调用 _apply_hit (用可控的击球区速度), 验证 发球->桌->墙->桌->回击 循环与计分。

var main_node: Node
var match_ref: Match
var ball: Ball
var players: Array[PlayerController] = []
var events: Array[String] = []
var t: float = 0.0
var _next_hit: float = 0.0

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	match_ref = main_node.match_ref
	ball = main_node.ball
	players = main_node.players
	main_node.debug_layer.enabled = true
	for p in players:
		p.input_scheme = null
		p.ball = null  # 禁用自动触及，避免与手动 _apply_hit 重复
	# 玩家2 (AI) 关掉，避免跑动/碰撞干扰对拉验证
	players[1].freeze = true
	players[1].set_physics_process(false)
	players[1].collision_layer = 0
	players[1].collision_mask = 0
	players[1].global_position = Vector2(430.0, 250.0)

	ball.table_bounced.connect(func(i: int) -> void:
		events.append("TABLE%d y=%.0f z=%.0f" % [i, ball.global_position.y, ball.z]))
	ball.wall_bounced.connect(func() -> void:
		events.append("WALL y=%.0f z=%.0f" % [ball.global_position.y, ball.z]))
	ball.died.connect(func(r: int) -> void:
		events.append("DIE(%d) y=%.0f bounce=%d wall=%s" % [r, ball.global_position.y, ball.table_bounces, str(ball.wall_since_hit)]))
	match_ref.state_changed.connect(func(s: int) -> void:
		events.append("--- STATE=%d score=%s" % [s, str(match_ref.scores)]))
	for p in players:
		p.ball_touched.connect(func(pl: PlayerController, _hp: HitPoint) -> void:
			events.append("TOUCH P%d" % pl.player_index))

	players[0].global_position = Vector2(0.0, -10.0)
	players[0].rotation = -PI / 2.0
	players[0].linear_velocity = Vector2.ZERO
	players[0].angular_velocity = 0.0
	match_ref._do_serve(players[0])
	print("TEST serve fired. ball vel=", ball.vel, " vz=", ball.vz)

func _do_test_hit() -> void:
	var recv: PlayerController = match_ref.expected_receiver
	if recv == null:
		return
	var facing: float = (GameConfig.table_center - ball.global_position).angle()
	recv.rotation = facing
	recv.global_position = ball.global_position - recv.hit_points[0].position.rotated(facing)
	recv.linear_velocity = Vector2.ZERO
	recv.angular_velocity = 0.0
	if recv.hit_points.size() >= 2:
		recv.hit_points[0].velocity = Vector2(0.0, -400.0)
		recv.hit_points[1].velocity = Vector2(0.0, 400.0)
	match_ref._apply_hit(recv, recv.hit_points[0])

func _physics_process(delta: float) -> void:
	t += delta
	if match_ref == null or ball == null:
		return
	if t < 4.0 and ball.state == GameTypes.BallState.LIVE and ball.returnable and t >= _next_hit:
		_do_test_hit()
		_next_hit = t + 0.05
	if t >= 4.0:
		for p in players:
			p.global_position = Vector2(430.0, 250.0)  # 故意离开
	if t > 7.0:
		print("TEST EVENTS:")
		for e in events:
			print("  ", e)
		print("TEST final score=", match_ref.scores, " state=", match_ref.state)
		get_tree().quit()
