extends Node
## 无头控制测试。
## 验证: WASD 世界移动 / 鼠标拖动向量=击球区局部位移(与 rotation 无关) / 反向移动 /
##       鼠标不改变 rotation / 松开回位。
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
	# 关掉玩家2(AI)，避免它跑动干扰玩家1的测试
	p2.freeze = true
	p2.set_physics_process(false)
	p2.global_position = Vector2(430.0, 250.0)
	p2.collision_layer = 0
	p2.collision_mask = 0
	GameConfig.base_face_enabled = false  # 先关回正，便于隔离测试坐标/移动
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
		print("PASS  ", name, "  ", detail)
	else:
		failures += 1
		print("FAIL  ", name, "  ", detail)

func _place(pos: Vector2, rot: float) -> void:
	p1.global_position = pos
	p1.rotation = rot
	p1.linear_velocity = Vector2.ZERO
	p1.angular_velocity = 0.0

func _set_drag(dragging: bool, v: Vector2) -> void:
	var sch: InputScheme = p1.input_scheme
	sch.debug_dragging_override = dragging
	sch.debug_drag_override = v

func _run() -> void:
	p1.input_scheme = InputScheme.new(GameConfig.p1_move, GameConfig.p1_serve, InputScheme.AimMode.MOUSE)

	# T1: 朝下(rotation=90°)按 W -> 向世界坐标上方移动
	_place(Vector2(0, 120), PI / 2.0)
	_key(KEY_W, true)
	await _frames(45)
	_key(KEY_W, false)
	await _frames(2)
	_check("T1 world-up", p1.global_position.y < 60.0 and absf(p1.global_position.x) < 45.0,
		str(p1.global_position.round()))

	# T2: 朝上(rotation=-90°)按 D -> 向世界坐标右方移动
	_place(Vector2(0, 120), -PI / 2.0)
	_key(KEY_D, true)
	await _frames(45)
	_key(KEY_D, false)
	await _frames(2)
	_check("T2 world-right", p1.global_position.x > 60.0 and absf(p1.global_position.y - 120.0) < 45.0,
		str(p1.global_position.round()))

	# T3: 鼠标拖动向量 = 击球区局部位移，与 rotation 无关 (不做 world->local 转换)
	var drag := Vector2(100.0, 0.0)
	var locals: Array = []
	for rot in [0.0, PI / 2.0, PI / 4.0]:
		_place(Vector2(0, 120), rot)
		p1.hit_zone_offset_local = Vector2.ZERO
		_set_drag(true, drag)
		await _frames(40)
		locals.append(p1.hit_zone_offset_local)
	var same: bool = locals[0].is_equal_approx(locals[1]) and locals[0].is_equal_approx(locals[2])
	_check("T3a local-delta same for all rotations", same, str(locals))
	_check("T3b local-delta == clamp(drag)",
		locals[0].is_equal_approx(Vector2(GameConfig.hit_zone_max_offset, 0.0)), str(locals[0]))

	# T3c: 同样的局部向量，世界位置随 rotation 不同 (证明 Transform 生效)
	_place(Vector2(0, 120), 0.0)
	p1.hit_zone_offset_local = Vector2.ZERO
	_set_drag(true, drag)
	await _frames(40)
	var w0: Vector2 = p1.hit_points[0].global_position - p1.global_position
	_place(Vector2(0, 120), PI / 2.0)
	p1.hit_zone_offset_local = Vector2.ZERO
	_set_drag(true, drag)
	await _frames(40)
	var w1: Vector2 = p1.hit_points[0].global_position - p1.global_position
	_check("T3c world position differs by rotation", not w0.is_equal_approx(w1),
		"rot0=%s rot90=%s" % [str(w0.round()), str(w1.round())])

	# T3d: 两个击球区反向 (A=+delta, B=-delta)
	var a_local: Vector2 = p1.hit_points[0].position
	var b_local: Vector2 = p1.hit_points[1].position
	var off: Vector2 = p1.hit_zone_offset_local
	var a_delta: Vector2 = a_local - Vector2(0.0, -GameConfig.player_half_length)
	var b_delta: Vector2 = b_local - Vector2(0.0, GameConfig.player_half_length)
	_check("T3d zones opposite", a_delta.is_equal_approx(off) and b_delta.is_equal_approx(-off),
		"A=%s B=%s off=%s" % [str(a_delta.round()), str(b_delta.round()), str(off.round())])

	# T4: 强回正到"面向桌中心"
	GameConfig.base_face_enabled = true
	var base_angle: float = (GameConfig.table_center - Vector2(0, 120)).angle()
	# T4a: 不拖动 -> 回到 base
	_place(Vector2(0, 120), 0.7)
	_set_drag(false, Vector2.ZERO)
	await _frames(60)
	_check("T4a recenters to base (no drag)",
		absf(wrapf(p1.rotation - base_angle, -PI, PI)) < 0.12, "rot=%.3f base=%.3f" % [p1.rotation, base_angle])
	# T4b: 拖动 -> 有限的小幅旋转 (不超过 drag_rot_max)
	_place(Vector2(0, 120), 0.7)
	_set_drag(true, Vector2(200.0, 0.0))
	await _frames(60)
	var off4: float = absf(wrapf(p1.rotation - base_angle, -PI, PI))
	_check("T4b drag gives small bounded rotation",
		off4 <= GameConfig.drag_rot_max + 0.12 and off4 > 0.02,
		"off=%.2f max=%.2f" % [off4, GameConfig.drag_rot_max])

	# T4c: 回正很快 (撞歪 2.27rad，1 秒内回到基准)
	_place(Vector2(0, 120), 0.7)
	_set_drag(false, Vector2.ZERO)
	var frames_to_settle: int = 0
	for i in 120:
		await get_tree().physics_frame
		frames_to_settle += 1
		if absf(wrapf(p1.rotation - base_angle, -PI, PI)) < 0.05:
			break
	_check("T4c recenter is fast (<0.5s)", frames_to_settle < 60, "frames=%d" % frames_to_settle)

	# T5: 松开后击球区回到默认位置
	_set_drag(false, Vector2.ZERO)
	await _frames(40)
	_check("T5 zones return to default", p1.hit_zone_offset_local.length() < 0.5,
		str(p1.hit_zone_offset_local))
