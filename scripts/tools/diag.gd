extends Node
## 临时诊断: 跑 AI vs AI, 打印球与 AI(P2) 的状态, 用于定位"来回跑/够不到/弹跳变短"。
## 运行: godot --headless --path <project> res://scenes/Diag.tscn

var main_node: Node
var ball: Ball

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	main_node.debug_mode = 3
	main_node._apply_debug_mode()
	ball = main_node.ball
	var ai: PlayerController = main_node.players[1]
	var prev_bounces: int = 0
	for i in 480:
		await get_tree().physics_frame
		if i % 10 == 0:
			var tg: Vector2 = ai._target_point()
			var d: float = ai.global_position.distance_to(ball.global_position)
			print("D f=%d state=%d ret=%s ball=(%.0f,%.0f,z%.0f,vz%.0f) bounce=%d | ai=(%.0f,%.0f) tgt=(%.0f,%.0f) vel=(%.0f,%.0f) dBall=%.0f arm=%.1f lastH=%s" % [
				i, ball.state, str(ball.returnable),
				ball.global_position.x, ball.global_position.y, ball.z, ball.vz, ball.table_bounces,
				ai.global_position.x, ai.global_position.y,
				tg.x, tg.y, ai.linear_velocity.x, ai.linear_velocity.y, d, ai._ai_arm_cur.length(),
				("P2" if ball.last_hitter == ai else ("P1" if ball.last_hitter != null else "-"))])
	get_tree().quit()
