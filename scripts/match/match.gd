class_name Match
extends Node
## 比赛系统：发球 / 球运动 / 接球 / 球死 / 基础胜负 / 重发。
##
## 状态机 (设计文档第 30 节)：
##   SERVE  -> RALLY -> (POINT_PAUSE | INTERFERENCE) -> SERVE ...
##   达到分数 -> MATCH_OVER
##
## 计分与轮换都是临时方案 [TEMP]，可随时替换。
## 球的具体弹跳规则细节没有写死，只用"桌弹次数 / 是否撞墙"这类可读状态近似。

signal state_changed(new_state: int)

var players: Array[PlayerController] = []
var ball: Ball = null
var block_system: BlockSystem = null
var arena: Arena = null

var state: int = GameTypes.MatchState.PREPARE
var scores: Dictionary = {1: 0, 2: 0}
var server_index: int = 1
var last_hitter: PlayerController = null
var expected_receiver: PlayerController = null

var _timer: float = 0.0
var _serve_latch: bool = false
var _interference_fired: bool = false
var _match_over_pending: bool = false
var _collision_time: float = -10.0
var _collision_pos: Vector2 = Vector2.ZERO
var _last_block_state: int = GameTypes.Interference.NONE

func setup(p_players: Array[PlayerController], p_ball: Ball, p_block: BlockSystem, p_arena: Arena) -> void:
	players = p_players
	ball = p_ball
	block_system = p_block
	arena = p_arena
	for p in players:
		p.ball = ball
		p.ball_touched.connect(_on_ball_touched)
		p.collided_with_player.connect(_on_players_collided)
	ball.died.connect(_on_ball_died)
	start_match()

# ------------------------------------------------------------
#  生命周期
# ------------------------------------------------------------
func start_match() -> void:
	scores = {1: 0, 2: 0}
	server_index = 1
	_match_over_pending = false
	EventBus.score_changed.emit(scores)
	_begin_serve()

func restart() -> void:
	start_match()

func _physics_process(dt: float) -> void:
	_update_block()
	match state:
		GameTypes.MatchState.SERVE:
			_tick_serve()
		GameTypes.MatchState.RALLY:
			pass
		GameTypes.MatchState.POINT_PAUSE, GameTypes.MatchState.INTERFERENCE:
			_timer -= dt
			if _timer <= 0.0:
				if _match_over_pending:
					_finish_match()
				else:
					_begin_serve()

# ------------------------------------------------------------
#  发球
# ------------------------------------------------------------
func _begin_serve() -> void:
	state = GameTypes.MatchState.SERVE
	_interference_fired = false
	_serve_latch = _server_serve_pressed(players[server_index - 1])
	last_hitter = null
	expected_receiver = _other(players[server_index - 1])
	_reset_positions()
	ball.state = GameTypes.BallState.HELD
	ball.reset_shot()
	ball.last_hitter = null
	ball.z = 0.0
	ball.vz = 0.0
	ball.vel = Vector2.ZERO
	ball.global_position = _serve_spot()
	block_system.active = false
	block_system.state = GameTypes.Interference.NONE
	EventBus.match_state_changed.emit(state)
	state_changed.emit(state)
	EventBus.notify("玩家%d 发球  (按发球键)" % server_index, 1.2)

func _server_serve_pressed(p: PlayerController) -> bool:
	return p.input_scheme != null and p.input_scheme.serve_pressed()

func _tick_serve() -> void:
	var server: PlayerController = players[server_index - 1]
	var pressed: bool = _server_serve_pressed(server)
	if pressed and not _serve_latch:
		_serve_latch = true
		_do_serve(server)
	else:
		_serve_latch = pressed

func _do_serve(server: PlayerController) -> void:
	ball.global_position = _serve_spot()
	ball.z = 0.0
	ball.launch_velocity(Vector2(0.0, -GameConfig.ball_hit_speed), GameConfig.ball_hit_vz)
	ball.last_hitter = server
	last_hitter = server
	expected_receiver = _other(server)
	state = GameTypes.MatchState.RALLY
	block_system.active = true
	EventBus.match_state_changed.emit(state)
	state_changed.emit(state)

func _serve_spot() -> Vector2:
	var server: PlayerController = players[server_index - 1]
	var tr := GameConfig.table_rect()
	var x: float = clampf(server.global_position.x, tr.position.x + 40.0, tr.end.x - 40.0)
	return Vector2(x, tr.end.y + GameConfig.ball_radius + 2.0)

func _reset_positions() -> void:
	var sign: float = -1.0 if server_index == 1 else 1.0
	var server: PlayerController = players[server_index - 1]
	var receiver: PlayerController = _other(server)
	server.reset_to(Vector2(sign * 140.0, 60.0), 0.0)
	receiver.reset_to(Vector2(-sign * 140.0, 140.0), 0.0)

# ------------------------------------------------------------
#  击球
# ------------------------------------------------------------
func _on_ball_touched(player: PlayerController, hit_point: HitPoint) -> void:
	if state != GameTypes.MatchState.RALLY:
		return
	if not ball.returnable:
		return
	if ball.z > GameConfig.max_hit_height:
		return
	if player != expected_receiver:
		return
	_apply_hit(player, hit_point)

func _apply_hit(player: PlayerController, hit_point: HitPoint) -> void:
	var outward: Vector2 = hit_point.global_position - player.global_position
	outward = outward.normalized() if outward.length() > 1.0 else Vector2(0.0, -1.0)
	var v: Vector2 = outward * GameConfig.ball_hit_speed \
		+ player.linear_velocity * GameConfig.hit_player_vel_influence
	ball.launch_velocity(v, GameConfig.ball_hit_vz)
	ball.z = maxf(ball.z, 0.0)
	ball.last_hitter = player
	last_hitter = player
	expected_receiver = _other(player)

# ------------------------------------------------------------
#  球死 -> 计分
# ------------------------------------------------------------
func _on_ball_died(reason: int) -> void:
	if state != GameTypes.MatchState.RALLY:
		return
	_award_point(_decide_winner(reason), reason)

func _decide_winner(reason: int) -> int:
	var hitter_index: int = last_hitter.player_index if last_hitter != null else expected_receiver.player_index
	var receiver_index: int = expected_receiver.player_index
	match reason:
		GameTypes.DeathReason.DOUBLE_BOUNCE:
			return hitter_index
		GameTypes.DeathReason.FLOOR, GameTypes.DeathReason.OUT_OF_BOUNDS:
			# 撞墙过且有桌弹 => 接球方没接到，击球方得分；否则击球方失误，接球方得分
			if ball.wall_since_hit and ball.table_bounces >= 1:
				return hitter_index
			return receiver_index
	return receiver_index

func _award_point(winner_index: int, reason: int) -> void:
	scores[winner_index] += 1
	EventBus.score_changed.emit(scores)
	EventBus.notify("玩家%d 得分  (%s)" % [winner_index, _reason_text(reason)], GameConfig.point_pause)
	state = GameTypes.MatchState.POINT_PAUSE
	_timer = GameConfig.point_pause
	block_system.active = false
	ball.state = GameTypes.BallState.INACTIVE
	_match_over_pending = scores[winner_index] >= GameConfig.score_to_win
	server_index = 3 - server_index  # TEMP: 暂时一直交替发球
	EventBus.match_state_changed.emit(state)
	state_changed.emit(state)

func _finish_match() -> void:
	state = GameTypes.MatchState.MATCH_OVER
	var winner: int = 1 if scores[1] >= scores[2] else 2
	EventBus.match_finished.emit(winner, scores)
	EventBus.notify("比赛结束！玩家%d 获胜 (R 重开)" % winner, 6.0)
	EventBus.match_state_changed.emit(state)
	state_changed.emit(state)

# ------------------------------------------------------------
#  阻挡
# ------------------------------------------------------------
func _update_block() -> void:
	if state != GameTypes.MatchState.RALLY or expected_receiver == null:
		block_system.active = false
		_set_block_state(GameTypes.Interference.NONE)
		return
	block_system.active = true
	block_system.update(0.0, ball, expected_receiver, _other(expected_receiver),
		_collision_time, _collision_pos, _now())
	_set_block_state(block_system.state)
	if block_system.state == GameTypes.Interference.CONFIRMED and not _interference_fired:
		_interference_fired = true
		_begin_interference()

func _set_block_state(s: int) -> void:
	if s == _last_block_state:
		return
	_last_block_state = s
	EventBus.interference_changed.emit(s, {
		"intercept": block_system.intercept_point,
		"receiver": expected_receiver,
	})

func _begin_interference() -> void:
	state = GameTypes.MatchState.INTERFERENCE
	_timer = GameConfig.interference_pause
	block_system.active = false
	ball.state = GameTypes.BallState.INACTIVE
	var victim: PlayerController = expected_receiver
	server_index = victim.player_index  # 被阻挡方重发
	EventBus.notify("阻挡！ 玩家%d 重发" % victim.player_index, GameConfig.interference_pause)
	EventBus.match_state_changed.emit(state)
	state_changed.emit(state)

# ------------------------------------------------------------
#  碰撞记录
# ------------------------------------------------------------
func _on_players_collided(_other_player: PlayerController, world_pos: Vector2) -> void:
	_collision_time = _now()
	_collision_pos = world_pos

# ------------------------------------------------------------
#  工具
# ------------------------------------------------------------
func _other(p: PlayerController) -> PlayerController:
	return players[1] if p == players[0] else players[0]

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _reason_text(reason: int) -> String:
	match reason:
		GameTypes.DeathReason.DOUBLE_BOUNCE:
			return "接球方没接到"
		GameTypes.DeathReason.FLOOR:
			return "球落地"
		GameTypes.DeathReason.OUT_OF_BOUNDS:
			return "球出界"
	return "球死"

func state_name() -> String:
	match state:
		GameTypes.MatchState.PREPARE:
			return "准备"
		GameTypes.MatchState.SERVE:
			return "发球"
		GameTypes.MatchState.RALLY:
			return "对拉"
		GameTypes.MatchState.POINT_PAUSE:
			return "得分"
		GameTypes.MatchState.INTERFERENCE:
			return "阻挡重发"
		GameTypes.MatchState.MATCH_OVER:
			return "结束"
	return "?"
