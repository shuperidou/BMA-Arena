extends Node
## AI vs AI 观察模式测试：双方 AI 能自动发球并完成多个回合。
## 运行: godot --headless --path <project> res://scenes/AiVsAiTest.tscn

var main_node: Node
var match_ref: Match
var ball: Ball
var hits: int = 0
var bounces: int = 0
var deaths: int = 0

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	match_ref = main_node.match_ref
	ball = main_node.ball
	# 切到 "AI vs AI" (第 4 个模式: 0 普通 / 1 Solo / 2 万能 / 3 AI vs AI)
	main_node.debug_mode = 3
	main_node._apply_debug_mode()

	ball.table_bounced.connect(func(_i: int) -> void: bounces += 1)
	ball.wall_bounced.connect(func() -> void: bounces += 1)
	for p in main_node.players:
		p.ball_touched.connect(func(_pl: PlayerController, _hp: HitPoint) -> void: hits += 1)
	ball.died.connect(func(_r: int) -> void: deaths += 1)

	# 跑 ~20 秒模拟; 统计"卡住"帧 (想动却几乎不动 且 离目标还远)
	var stuck: int = 0
	for i in 1200:
		await get_tree().physics_frame
		if ball.state == GameTypes.BallState.LIVE:
			for p in main_node.players:
				if p.linear_velocity.length() < 20.0 \
						and p.global_position.distance_to(p._target_point()) > 60.0:
					stuck += 1

	var p0: PlayerController = main_node.players[0]
	var p1: PlayerController = main_node.players[1]
	print("AIVSAI p0.ai=", p0.ai_enabled, " p1.ai=", p1.ai_enabled)
	print("AIVSAI hits=", hits, " bounces=", bounces, " deaths=", deaths, " stuck=", stuck, " score=", match_ref.scores)
	if p0.ai_enabled and p1.ai_enabled and hits >= 3 and bounces >= 3:
		print("AIVSAI PASS")
	else:
		print("AIVSAI FAIL")
	get_tree().quit()
