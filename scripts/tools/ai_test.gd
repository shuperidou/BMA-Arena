extends Node
## AI 自动发球冒烟测试。
## 运行: godot --headless --path <project> res://scenes/AiTest.tscn

var main_node: Node
var match_ref: Match
var ball: Ball
var events: Array[String] = []
var t: float = 0.0

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	match_ref = main_node.match_ref
	ball = main_node.ball
	ball.table_bounced.connect(func(i: int) -> void: events.append("T%d" % i))
	ball.wall_bounced.connect(func() -> void: events.append("W"))
	# 强制 AI(玩家2) 发球
	match_ref.server_index = 2
	match_ref._begin_serve()

func _physics_process(delta: float) -> void:
	t += delta
	if match_ref == null:
		return
	if t > 3.0:
		var served: bool = events.size() > 0 or ball.state != GameTypes.BallState.HELD
		print("AI SERVE served=", served, " events=", events, " state=", match_ref.state)
		get_tree().quit()
