extends Node
## 阻挡判定单元测试 (直接喂场景给 BlockSystem.update, 不经物理)。
## 运行: godot --headless --path <project> res://scenes/BlockTest.tscn

var main_node: Node
var bs: BlockSystem
var ball: Ball
var a: PlayerController
var b: PlayerController
var failures: int = 0

func _ready() -> void:
	main_node = preload("res://scenes/Main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	bs = main_node.match_ref.block_system
	ball = main_node.ball
	a = main_node.players[0]
	b = main_node.players[1]
	_run()
	print("BLOCK TEST failures=", failures)
	get_tree().quit()

func _check(name: String, cond: bool, detail: String) -> void:
	if cond:
		print("PASS  ", name, "  ", detail)
	else:
		failures += 1
		print("FAIL  ", name, "  ", detail)

## 构造一个场景并跑一次判定。collision_age = 距碰撞过了多久, contact = 接触时长。
func _scn(a_pos: Vector2, a_vel: Vector2, ball_pos: Vector2, b_pos: Vector2,
		collision_age: float, contact: float, now: float) -> int:
	a.global_position = a_pos
	a.linear_velocity = a_vel
	ball.global_position = ball_pos
	b.global_position = b_pos
	bs.active = true
	bs.update(0.0, ball, a, b, now - collision_age, b_pos, now, contact)
	return bs.state

func _run() -> void:
	var now := 10.0
	var up := Vector2(0, -600)
	# 用配置派生的时间值, 避免和 GameConfig 调参脱节
	var win: float = GameConfig.block_collision_window
	var mc: float = GameConfig.block_min_contact_time
	var good_age: float = win * 0.5          # 在窗口内
	var old_age: float = win * 2.0           # 超出窗口
	var good_contact: float = mc + 0.05      # 接触足够
	var short_contact: float = mc * 0.5      # 接触不足

	# S1: 接球方朝球冲 + 球在扇区 + 刚碰撞且接触足够 -> CONFIRMED
	var s1 := _scn(Vector2(0, 0), up, Vector2(0, -60), Vector2(0, -20), good_age, good_contact, now)
	_check("S1 冲球+侧撞 -> CONFIRMED", s1 == GameTypes.Interference.CONFIRMED, "state=%d" % s1)

	# S2: 接球方静止 (无意图) -> NONE
	var s2 := _scn(Vector2(0, 0), Vector2.ZERO, Vector2(0, -60), Vector2(0, -20), good_age, good_contact, now)
	_check("S2 静止 -> NONE", s2 == GameTypes.Interference.NONE, "state=%d" % s2)

	# S3: 球不在速度扇区内 -> NONE
	var s3 := _scn(Vector2(0, 0), up, Vector2(120, -5), Vector2(60, -5), good_age, good_contact, now)
	_check("S3 球在扇区外 -> NONE", s3 == GameTypes.Interference.NONE, "state=%d" % s3)

	# S4: 扇区满足, 但接触时间不足 -> POSSIBLE (不判罚)
	var s4 := _scn(Vector2(0, 0), up, Vector2(0, -60), Vector2(0, -20), good_age, short_contact, now)
	_check("S4 接触太短 -> POSSIBLE", s4 == GameTypes.Interference.POSSIBLE, "state=%d" % s4)

	# S5: 扇区满足, 但碰撞太旧(超出窗口) -> POSSIBLE
	var s5 := _scn(Vector2(0, 0), up, Vector2(0, -60), Vector2(0, -20), old_age, good_contact, now)
	_check("S5 碰撞太旧 -> POSSIBLE", s5 == GameTypes.Interference.POSSIBLE, "state=%d" % s5)

	# S6: 可选门槛-对手在正后方 -> NONE (开关打开时)
	GameConfig.block_require_opponent_in_front = true
	var s6 := _scn(Vector2(0, 0), up, Vector2(0, -60), Vector2(0, 40), good_age, good_contact, now)
	_check("S6 B在正后方(开关开) -> NONE", s6 == GameTypes.Interference.NONE, "state=%d" % s6)
	GameConfig.block_require_opponent_in_front = false

	# S7: 开关关时, 同样场景(B在正后方) -> CONFIRMED
	var s7 := _scn(Vector2(0, 0), up, Vector2(0, -60), Vector2(0, 40), good_age, good_contact, now)
	_check("S7 B在后方(开关关) -> CONFIRMED", s7 == GameTypes.Interference.CONFIRMED, "state=%d" % s7)
