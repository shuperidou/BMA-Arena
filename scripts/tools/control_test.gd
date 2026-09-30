extends Node
## 无头控制测试：验证 WASD 是世界坐标移动、与朝向解耦、鼠标朝向带惯性。
## 运行: godot --headless --path <project> res://scenes/ControlTest.tscn

var main_node: Node
var p1: PlayerController
var p2: PlayerController
var failures: int = 0

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	p1 = main_node.players[0]
	p2 = main_node.players[1]
	p2.input_scheme = null
	p1.debug_aim_override = NAN
	await _run()
	print("CONTROL TEST failures=", failures)
	get_tree().quit()

func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _check(name: String, cond: bool, detail: String) -> void:
	if cond:
		print("PASS ", name, "  ", detail)
	else:
		failures += 1
		print("FAIL ", name, "  ", detail)

func _run() -> void:
	# 测试1: 角色朝下(+y)，按 W -> 必须向世界坐标上方(-y)移动
	p1.global_position = Vector2(0, 120)
	p1.rotation = PI / 2.0     # 朝下
	p1.linear_velocity = Vector2.ZERO
	_key(KEY_W, true)
	await _frames(45)
	_key(KEY_W, false)
	await _frames(2)
	var test1_ok: bool = p1.global_position.y < 60.0 and absf(p1.global_position.x) < 40.0
	_check("T1 朝下按W->世界上", test1_ok, "pos=%s" % str(p1.global_position.round()))

	# 测试2: 角色朝上(-y 方向, rotation=-PI/2)，按 D -> 向世界坐标右方(+x)
	p1.global_position = Vector2(0, 120)
	p1.rotation = -PI / 2.0
	p1.linear_velocity = Vector2.ZERO
	_key(KEY_D, true)
	await _frames(45)
	_key(KEY_D, false)
	await _frames(2)
	var test2_ok: bool = p1.global_position.x > 60.0 and absf(p1.global_position.y - 120.0) < 40.0
	_check("T2 朝上按D->世界右", test2_ok, "pos=%s" % str(p1.global_position.round()))

	# 测试3: 移动与旋转互不干扰。按住 W 同时给 90 度目标朝向
	p1.global_position = Vector2(0, 120)
	p1.rotation = 0.0
	p1.linear_velocity = Vector2.ZERO
	p1.angular_velocity = 0.0
	p1.debug_aim_override = PI / 2.0   # 目标: 朝下
	_key(KEY_W, true)
	await _frames(30)
	var mid_rot: float = p1.rotation
	_key(KEY_W, false)
	await _frames(40)   # 继续追踪目标直到稳定
	var test3_ok: bool = p1.global_position.y < 120.0 - 60.0 and absf(wrapf(p1.rotation - PI / 2.0, -PI, PI)) < 0.15
	_check("T3 上移+转下", test3_ok, "pos=%s rot=%.2f mid=%.2f" % [str(p1.global_position.round()), p1.rotation, mid_rot])

	# 测试4: 旋转是渐进的，不是瞬间。从 0 追到 PI，第一帧不应到位，且角速度受限
	p1.global_position = Vector2(0, 120)
	p1.rotation = 0.0
	p1.linear_velocity = Vector2.ZERO
	p1.angular_velocity = 0.0
	var t4target: float = 2.5
	p1.debug_aim_override = t4target
	await _frames(1)
	_check("T4a 非瞬间转向", absf(p1.rotation) < 0.2, "after1frame rot=%.3f" % p1.rotation)
	await _frames(120)
	var settled: bool = absf(wrapf(p1.rotation - t4target, -PI, PI)) < 0.2
	_check("T4b 最终转到目标", settled, "rot=%.2f (target %.2f)" % [p1.rotation, t4target])
