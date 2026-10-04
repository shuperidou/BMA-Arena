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
var solo_mode: bool = false  ## 调试：玩家2 消失，玩家1 自己发球自己接
var debug_mode_name: String = "普通"  ## 当前调试模式名 (仅用于 HUD 显示)
var ai_evolve_enabled: bool = false   ## ② 训练模式: 每分后败者继承胜者基因(变异+成长)
var generation: int = 0               ## ② 已进化的代数
var ai_pool: Array[AiGenome] = []     ## ② 锦标赛基因池 (非空 = 轮换锦标赛模式)
var ai_p1_idx: int = 0                ## 当前 P1 用的池下标 (每分轮换)
var ai_p2_idx: int = 0                ## 当前 P2 用的池下标 (P1 轮完一圈才换)

var _timer: float = 0.0
var _serve_timer: float = 0.0
var _serve_latch: bool = false
var _block_pending: bool = false                    ## 本次对拉中出现过阻挡(未立即判罚)
var _blocked_receiver: PlayerController = null      ## 被阻挡的接球方 (重发时由其发球)
var _match_over_pending: bool = false
var _collision_time: float = -10.0
var _collision_pos: Vector2 = Vector2.ZERO
var _collided_flag: bool = false
var _contact_start: float = -1.0
var _last_block_state: int = GameTypes.Interference.NONE

func setup(p_players: Array[PlayerController], p_ball: Ball, p_block: BlockSystem, p_arena: Arena) -> void:
	players = p_players
	ball = p_ball
	block_system = p_block
	arena = p_arena
	for p in players:
		p.ball = ball
		p.rival = _other(p)
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

func set_solo(v: bool) -> void:
	solo_mode = v
	server_index = 1

func _physics_process(dt: float) -> void:
	_update_block()
	match state:
		GameTypes.MatchState.SERVE:
			_tick_serve(dt)
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
	_block_pending = false
	_blocked_receiver = null
	_serve_latch = _server_serve_pressed(players[server_index - 1])
	_serve_timer = GameConfig.ai_serve_delay
	last_hitter = null
	expected_receiver = _other(players[server_index - 1])
	_reset_positions()
	ball.state = GameTypes.BallState.HELD
	ball.height_state = GameTypes.BallHeightState.NONE
	ball.reset_shot()
	ball.last_hitter = null
	ball.z = GameConfig.table_z
	ball.vz = 0.0
	ball.vel = Vector2.ZERO
	# 球贴在发球方身上 (发球前不可见，见 Ball._draw)
	ball.global_position = players[server_index - 1].global_position
	block_system.active = false
	block_system.state = GameTypes.Interference.NONE
	EventBus.match_state_changed.emit(state)
	state_changed.emit(state)
	EventBus.notify("玩家%d 发球  (按发球键)" % server_index, 1.2)

func _server_serve_pressed(p: PlayerController) -> bool:
	return p.input_scheme != null and p.input_scheme.serve_pressed()

func _tick_serve(dt: float) -> void:
	var server: PlayerController = players[server_index - 1]
	if server.ai_enabled:
		# AI 自动发球：等一小段(给玩家反应时间)后发出
		_serve_timer -= dt
		if _serve_timer <= 0.0:
			_do_serve(server)
		return
	var pressed: bool = _server_serve_pressed(server)
	if pressed and not _serve_latch:
		_serve_latch = true
		_do_serve(server)
	else:
		_serve_latch = pressed

func _do_serve(server: PlayerController) -> void:
	# 从发球方所在位置发出；默认沿朝向，AI 走智能发球
	ball.global_position = server.global_position
	ball.z = GameConfig.table_z
	var info: Dictionary = server.compute_serve(ball)
	ball.launch_velocity(info.velocity, info.vz)
	ball.serve_shot = true
	ball.last_hitter = server
	last_hitter = server
	expected_receiver = _other(server)
	state = GameTypes.MatchState.RALLY
	block_system.active = true
	EventBus.match_state_changed.emit(state)
	state_changed.emit(state)

func _reset_positions() -> void:
	if solo_mode:
		return  # 单人调试：不重置位置，玩家自由走动
	# 玩家1 站左边, 玩家2(AI) 站右边, 都面向桌中心
	var left := Vector2(-180.0, 10.0)
	var right := Vector2(180.0, 10.0)
	players[0].reset_to(left, (GameConfig.table_center - left).angle())
	players[1].reset_to(right, (GameConfig.table_center - right).angle())

# ------------------------------------------------------------
#  击球
# ------------------------------------------------------------
func _on_ball_touched(player: PlayerController, hit_point: HitPoint) -> void:
	if state != GameTypes.MatchState.RALLY:
		return
	if not ball.returnable:
		return
	if ball.smash_invincible:
		return   # 无敌扣杀: 对方接不住
	if ball.z < GameConfig.hit_height_min or ball.z > GameConfig.hit_height_max:
		return
	if player != expected_receiver:
		return
	_apply_hit(player, hit_point)

func _apply_hit(player: PlayerController, hit_point: HitPoint) -> void:
	# 接球方成功救起了球 -> 之前的阻挡没有影响进程, 清除待判罚 (点一)
	_block_pending = false
	var info: Dictionary = player.compute_hit(hit_point, ball)
	ball.launch_velocity(info.velocity, info.vz)
	ball.serve_shot = false
	ball.z = maxf(ball.z, GameConfig.table_z)
	ball.register_hit(info)
	ball.last_hitter = player
	last_hitter = player
	expected_receiver = _other(player)

# ------------------------------------------------------------
#  球死 -> 计分
# ------------------------------------------------------------
func _on_ball_died(reason: int) -> void:
	if state != GameTypes.MatchState.RALLY:
		return
	var winner: int = _decide_winner(reason)
	# 阻挡只在"接球方没接到"(正常判给击球方) 时才生效, 改为重发。
	# 若正常判给的是接球方(即击球方自己失误), 不因阻挡改判 —— 防止击球方靠阻挡规避输球。
	if _block_pending and last_hitter != null and winner == last_hitter.player_index:
		_begin_interference()
		return
	_award_point(winner, reason)

func _decide_winner(reason: int) -> int:
	var hitter_index: int = last_hitter.player_index if last_hitter != null else expected_receiver.player_index
	var receiver_index: int = expected_receiver.player_index
	match reason:
		GameTypes.DeathReason.DOUBLE_BOUNCE:
			return hitter_index
		GameTypes.DeathReason.BAD_BOUNCE:
			return receiver_index  # 同一面连弹/跳弹 -> 击球方失误
		GameTypes.DeathReason.FLOOR, GameTypes.DeathReason.OUT_OF_BOUNDS:
			# 墙后已经落过桌(receiver_bounces>=1) => 接球方没接到, 击球方得分;
			# 否则(只撞墙没落桌/只弹桌没到墙) => 击球方失误, 接球方得分 (文档 93-99 行)
			if ball.wall_since_hit and ball.receiver_bounces >= 1:
				return hitter_index
			return receiver_index
	return receiver_index

func _award_point(winner_index: int, reason: int) -> void:
	if solo_mode:
		# 单人调试：不计分，球死后重发
		EventBus.notify("球死  (%s)" % _reason_text(reason), GameConfig.point_pause)
		state = GameTypes.MatchState.POINT_PAUSE
		_timer = GameConfig.point_pause
		block_system.active = false
		ball.state = GameTypes.BallState.INACTIVE
		EventBus.match_state_changed.emit(state)
		state_changed.emit(state)
		return
	scores[winner_index] += 1
	_evolve_if_enabled(winner_index)
	# 先算好发球轮换 + 胜负判定, 再广播比分 (否则发球标记会过期)
	var total: int = scores[1] + scores[2]
	_match_over_pending = scores[winner_index] >= GameConfig.score_to_win \
		and scores[winner_index] - scores[3 - winner_index] >= GameConfig.match_win_by
	if GameConfig.serve_change_every > 0 and total % GameConfig.serve_change_every == 0:
		server_index = 3 - server_index
	EventBus.score_changed.emit(scores)
	EventBus.notify("玩家%d 得分  (%s)" % [winner_index, _reason_text(reason)], GameConfig.point_pause)
	state = GameTypes.MatchState.POINT_PAUSE
	_timer = GameConfig.point_pause
	block_system.active = false
	ball.state = GameTypes.BallState.INACTIVE
	EventBus.match_state_changed.emit(state)
	state_changed.emit(state)

## ② 进化一步。
##   AI vs AI: 败者继承胜者基因 (变异 + 成长)。
##   人机: 只有 AI 一方有基因; 它输了这一分就自我成长 (陪你打越打越强)。
func _evolve_if_enabled(winner_index: int) -> void:
	if not ai_evolve_enabled or winner_index < 1 or winner_index > players.size():
		return
	if ai_pool.size() > 0:
		_tournament_step(winner_index)
		return
	var w: PlayerController = players[winner_index - 1]
	var l: PlayerController = _other(w)
	if w == null or l == null:
		return
	if w.genome != null and l.genome != null:
		l.genome = w.genome.grown(GameConfig.ai_mutation_rate * 2.0, 0.02)
		generation += 1
		EventBus.notify("AI 进化 第%d代: 败者继承+变异  风格[%s]" % [generation, l.genome.style_name()], 2.0)
	elif w.genome != null or l.genome != null:
		var ai_p: PlayerController = w if w.genome != null else l
		if ai_p == l:
			ai_p.genome = ai_p.genome.grown(GameConfig.ai_mutation_rate, 0.01)
			generation += 1
			EventBus.notify("AI 进化 第%d代: 输了这分, 自我成长  风格[%s]" % [generation, ai_p.genome.style_name()], 2.0)

## ② 锦标赛一步: 赢家在池内的那份基因 "变强(grown) + 吸收对手(crossover)"。
## 轮换: P1 每分换下一份; P1 轮完一整圈后 P2 才换下一份 (全配对循环)。
func _tournament_step(winner_index: int) -> void:
	var n: int = ai_pool.size()
	if n == 0:
		return
	var w_idx: int = ai_p1_idx if winner_index == 1 else ai_p2_idx
	var l_idx: int = ai_p2_idx if winner_index == 1 else ai_p1_idx
	ai_pool[w_idx] = ai_pool[w_idx].grown(GameConfig.ai_mutation_rate, 0.01) \
		.crossover(ai_pool[l_idx], GameConfig.ai_crossover_amount)
	ai_p1_idx = (ai_p1_idx + 1) % n
	if ai_p1_idx == 0:
		ai_p2_idx = (ai_p2_idx + 1) % n
	if players.size() >= 2:
		players[0].genome = ai_pool[ai_p1_idx]
		players[1].genome = ai_pool[ai_p2_idx]
	generation += 1
	if players.size() >= 2 and players[0].genome != null and players[1].genome != null:
		EventBus.notify("锦标赛 第%d分: P1[%s] vs P2[%s]" % [generation,
			players[0].genome.style_name(), players[1].genome.style_name()], 1.6)

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
	# 阻挡重发停顿期间保留上一步的 CONFIRMED 状态，让 Debug 能持续显示红色
	if state == GameTypes.MatchState.INTERFERENCE:
		return
	if solo_mode or state != GameTypes.MatchState.RALLY or expected_receiver == null:
		block_system.active = false
		_set_block_state(GameTypes.Interference.NONE)
		return
	# 接触持续时间 (至少几毫秒的碰撞才算阻挡)
	var now: float = _now()
	var contact_duration: float = 0.0
	if _collided_flag:
		if _contact_start < 0.0:
			_contact_start = now
		_collided_flag = false
	else:
		_contact_start = -1.0
	if _contact_start >= 0.0:
		contact_duration = now - _contact_start
	block_system.active = true
	block_system.update(0.0, ball, expected_receiver, _other(expected_receiver),
		_collision_time, _collision_pos, now, contact_duration)
	_set_block_state(block_system.state)
	# 阻挡不立即判罚：先记下，等球真的死了(接球方没救起来)才生效 (点一)
	if block_system.state == GameTypes.Interference.CONFIRMED and not _block_pending:
		_block_pending = true
		_blocked_receiver = expected_receiver

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
	# 故意不关 active：让 CONFIRMED(红) 在重发停顿期间一直可见
	ball.state = GameTypes.BallState.INACTIVE
	var victim: PlayerController = _blocked_receiver if _blocked_receiver != null else expected_receiver
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
	_collided_flag = true

# ------------------------------------------------------------
#  工具
# ------------------------------------------------------------
func _other(p: PlayerController) -> PlayerController:
	if solo_mode:
		return p  # 自己发球自己接
	return players[1] if p == players[0] else players[0]

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _reason_text(reason: int) -> String:
	match reason:
		GameTypes.DeathReason.DOUBLE_BOUNCE:
			return "接球方没接到"
		GameTypes.DeathReason.BAD_BOUNCE:
			return "弹跳犯规"
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
