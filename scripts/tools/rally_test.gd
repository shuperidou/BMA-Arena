extends Node
## 无头自动对拉测试 (仅开发用)。
## 运行: godot --headless --path <project> res://scenes/RallyTest.tscn
## 让"当前接球方"每帧瞬移到球旁自动回击，验证 发球->桌->墙->桌->回击 的循环与计分。

var main_node: Node
var match_ref: Match
var ball: Ball
var players: Array[PlayerController] = []
var t: float = 0.0
var events: Array[String] = []

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	match_ref = main_node.match_ref
	ball = main_node.ball
	players = main_node.players
	main_node.debug_layer.enabled = true  # 确保调试绘制路径也被执行
	for p in players:
		p.input_scheme = null  # 测试里不让鼠标/键盘控制旋转，手动摆位更稳定

	ball.table_bounced.connect(func(i: int) -> void:
		events.append("TABLE%d y=%.0f z=%.0f" % [i, ball.global_position.y, ball.z]))
	ball.wall_bounced.connect(func() -> void:
		events.append("WALL y=%.0f z=%.0f" % [ball.global_position.y, ball.z]))
	ball.died.connect(func(r: int) -> void:
		events.append("DIE(%d) y=%.0f bounce=%d wall=%s" % [r, ball.global_position.y, ball.table_bounces, str(ball.wall_since_hit)]))
	for p in players:
		p.ball_touched.connect(func(pl: PlayerController, _hp: HitPoint) -> void:
			events.append("HIT by P%d" % pl.player_index))
	match_ref.state_changed.connect(func(s: int) -> void:
		events.append("--- STATE=%d score=%s" % [s, str(match_ref.scores)]))

	# 发球现在从发球方位置、沿其朝向发出；把发球方摆在桌近边、朝向桌中心
	players[0].global_position = Vector2(0.0, -10.0)
	players[0].rotation = -PI / 2.0
	players[0].linear_velocity = Vector2.ZERO
	players[0].angular_velocity = 0.0
	match_ref._do_serve(players[0])
	print("TEST serve fired. ball vel=", ball.vel, " vz=", ball.vz)

func _physics_process(delta: float) -> void:
	t += delta
	if match_ref == null or ball == null:
		return
	# 前 4 秒自动回击；之后故意不接，验证计分
	var recv: PlayerController = match_ref.expected_receiver
	if t < 4.0 and recv != null and ball.state == GameTypes.BallState.LIVE and ball.returnable:
		recv.global_position = ball.global_position + Vector2(0.0, 90.0)
		recv.rotation = 0.0
		recv.linear_velocity = Vector2.ZERO
		recv.angular_velocity = 0.0
	elif t >= 4.0:
		# 故意离开：验证球死 -> 计分 -> 下一分
		for p in players:
			p.global_position = Vector2(430.0, 250.0)
	if t > 7.0:
		print("TEST EVENTS:")
		for e in events:
			print("  ", e)
		print("TEST final score=", match_ref.scores, " state=", match_ref.state)
		get_tree().quit()
