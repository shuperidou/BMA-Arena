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
	var a_delta: Vector2 = a_local - Vector2(0.0, -GameConfig.player_shape_half())
	var b_delta: Vector2 = b_local - Vector2(0.0, GameConfig.player_shape_half())
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

	# T6: 形状系统 —— 显示多边形 == 碰撞多边形; 判定区间距随形状同步
	p1.hit_zone_offset_local = Vector2.ZERO
	var ok_sync := true
	var ok_spacing := true
	var detail6 := ""
	for si in GameConfig.player_shape_count():
		GameConfig.player_shape_index = si
		p1.rebuild_shape()
		var pts: PackedVector2Array = GameConfig.player_shape_points()
		var poly: PackedVector2Array = p1._shape_poly.polygon
		if pts.size() < 3 or not _same_pts(pts, poly):
			ok_sync = false
			detail6 += " shape%d(pts=%d/poly=%d)" % [si, pts.size(), poly.size()]
		var half: float = GameConfig.player_shape_half()
		if absf(p1.hit_points[0].position.y + half) > 0.01 \
				or absf(p1.hit_points[1].position.y - half) > 0.01 \
				or absf(p1.hit_points[0].position.x) > 0.01:
			ok_spacing = false
			detail6 += " shape%d spacing(half=%.0f)" % [si, half]
	_check("T6a 显示多边形==碰撞多边形 (所有形状)", ok_sync, detail6)
	_check("T6b 判定区间距随形状同步", ok_spacing, detail6)
	GameConfig.player_shape_index = 0
	p1.rebuild_shape()

	# T7: AI 追击目标点会投影到"可达区域" (桌/边界外), 避免怼桌卡死
	var inside: Vector2 = GameConfig.table_center
	var out: Vector2 = p1._clamp_reachable(inside)
	_check("T7 目标点被推出(缩过的)桌外",
		not GameConfig.table_block_rect().grow(GameConfig.ai_body_clearance).has_point(out),
		"in=%s out=%s margin=%.0f" % [str(inside.round()), str(out.round()), GameConfig.table_player_margin])

	# T8: P4 变异 (只变纺锤: 长/宽/大小) 生成/应用 + 体型代价 (涌现式, 无评分)
	var cands: Array = MutationSystem.generate()
	var c0: Dictionary = cands[0]
	var ok_cnt: bool = cands.size() == GameConfig.mutation_candidates
	var ok_keep: bool = absf(float(c0.half_len) - GameConfig.player_half_length) < 0.001 \
		and absf(float(c0.radius) - GameConfig.player_radius) < 0.001 \
		and absf(float(c0.size_scale) - GameConfig.player_size_scale) < 0.001
	var ok_range: bool = true
	for i in range(1, cands.size()):
		var c: Dictionary = cands[i]
		if float(c.half_len) < GameConfig.mutation_len_min - 0.001 or float(c.half_len) > GameConfig.mutation_len_max + 0.001 \
				or float(c.radius) < GameConfig.mutation_wid_min - 0.001 or float(c.radius) > GameConfig.mutation_wid_max + 0.001 \
				or float(c.size_scale) < GameConfig.mutation_size_min - 0.001 or float(c.size_scale) > GameConfig.mutation_size_max + 0.001:
			ok_range = false
	_check("T8a 候选数 + 含'保留当前'", ok_cnt and ok_keep, "n=%d" % cands.size())
	_check("T8b 候选参数在范围内", ok_range,
		"长[%.0f,%.0f] 宽[%.0f,%.0f]" % [GameConfig.mutation_len_min, GameConfig.mutation_len_max,
			GameConfig.mutation_wid_min, GameConfig.mutation_wid_max])
	MutationSystem.apply(MutationSystem.make(110.0, 20.0, 1.2, "t"))
	_check("T8c 应用候选后当前身体更新",
		absf(GameConfig.player_half_length - 110.0) < 0.001 and absf(GameConfig.player_radius - 20.0) < 0.001 \
		and absf(GameConfig.player_size_scale - 1.2) < 0.001,
		"长%.0f 宽%.0f 大小%.2f" % [GameConfig.player_half_length, GameConfig.player_radius, GameConfig.player_size_scale])
	_check("T8d 体型代价 (大=移动慢/转身难)",
		p1._size_speed_mult() < 1.0 and p1._size_turn_mult() < 1.0,
		"spd=%.3f turn=%.3f" % [p1._size_speed_mult(), p1._size_turn_mult()])
	MutationSystem.apply(MutationSystem.make(90.0, 14.0, 1.0, "t"))   # 还原
	p1.rebuild_shape()

func _same_pts(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true
