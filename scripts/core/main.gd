class_name Main
extends Node2D
## 入口：用代码组装整个原型场景 (场地 / 球 / 两个角色 / 比赛 / UI / 调试)。
##
## 采用"代码组装"而不是大量手写 .tscn，是为了让所有几何与参数都来自 GameConfig，
## 方便快速迭代。之后要拆成场景/预制体很容易。

var arena: Arena
var ball: Ball
var block_system: BlockSystem
var match_ref: Match
var hud: Hud
var debug_layer: DebugLayer
var esc_menu: EscMenu
var mutation_panel: MutationPanel
var players: Array[PlayerController] = []
var cam: Camera2D = null

# --- 视听反馈 [TEMP]: 命中停顿(hitstop) + 震屏 + 程序化音效 ---
var _shake: float = 0.0
var _hitstop_until_ms: int = 0
var _audio: AudioStreamPlayer = null
var _sfx_hit: AudioStreamWAV = null
var _sfx_smash: AudioStreamWAV = null
var _sfx_save: AudioStreamWAV = null
var _sfx_score: AudioStreamWAV = null
var _juice_enabled: bool = true

func _ready() -> void:
	GameConfig.ai_apply_level()
	_migrate_legacy_genome()
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)

	cam = Camera2D.new()
	cam.name = "Camera2D"
	cam.position = GameConfig.arena_center
	add_child(cam)
	cam.make_current()
	_setup_audio()

	ball = Ball.new()
	ball.name = "Ball"
	add_child(ball)

	# 玩家1: 鼠标控制的纺锤; 玩家2: 圆形 AI
	var human := PlayerController.new()
	human.name = "Player1"
	human.setup(1, InputScheme.new(GameConfig.p1_move, GameConfig.p1_serve, GameConfig.p1_aim_mode))
	human.global_position = Vector2(-300.0, 140.0)
	add_child(human)
	players.append(human)

	var ai := AiPlayer.new()
	ai.name = "Player2"
	ai.setup(2, null)
	ai.global_position = Vector2(300.0, 140.0)
	add_child(ai)
	players.append(ai)
	EventBus.score_changed.connect(func(_s: Dictionary) -> void: _play(_sfx_score, 1.0))

	block_system = BlockSystem.new()
	block_system.name = "BlockSystem"
	add_child(block_system)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)

	debug_layer = DebugLayer.new()
	debug_layer.name = "DebugLayer"
	add_child(debug_layer)

	esc_menu = EscMenu.new()
	esc_menu.name = "EscMenu"
	esc_menu.main_ref = self
	add_child(esc_menu)

	mutation_panel = MutationPanel.new()
	mutation_panel.name = "MutationPanel"
	mutation_panel.main_ref = self
	add_child(mutation_panel)

	match_ref = Match.new()
	match_ref.name = "Match"
	add_child(match_ref)
	match_ref.setup(players, ball, block_system, arena)

	hud.match_ref = match_ref
	debug_layer.match_ref = match_ref
	# 反馈信号放在 Match 之后连接 -> 触球时先由 Match 结算, 再读 last_smash_state
	for p in players:
		p.ball_touched.connect(_on_ball_touched)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F1:
			debug_layer.enabled = not debug_layer.enabled
			hud.set_debug_menu(debug_layer.enabled)
		KEY_2:
			if debug_layer.enabled:
				_toggle_flag("debug_show_block")
		KEY_3:
			if debug_layer.enabled:
				_toggle_flag("debug_show_aim")
		KEY_4:
			if debug_layer.enabled:
				_toggle_flag("debug_show_ball")
		KEY_5:
			if debug_layer.enabled:
				_toggle_flag("debug_show_shapes")
		KEY_6:
			if debug_layer.enabled:
				_toggle_flag("debug_show_zones")
		KEY_7:
			if debug_layer.enabled:
				_toggle_flag("debug_show_block_hud")
		KEY_8:
			if debug_layer.enabled:
				_toggle_flag("debug_ai_smash")
		KEY_9:
			if debug_layer.enabled:
				_toggle_flag("ai_diverse")
		KEY_0:
			if debug_layer.enabled:
				_toggle_flag("ai_save_enabled")
		KEY_R:
			match_ref.restart()
		KEY_1:
			# 调试：F1 打开调试后，按 1 轮换调试模式 (普通 / Solo / 万能AI)
			if debug_layer.enabled:
				_cycle_debug_mode()

func _toggle_flag(prop: String) -> void:
	GameConfig.set(prop, not GameConfig.get(prop))
	hud.update_debug_menu()

## F1+1 轮换的调试模式 (互斥)。加模式 = 往 DEBUG_MODES 加名字 + 在 _apply_debug_mode 加一行效果。
const DEBUG_MODES: Array[String] = ["普通", "Solo (玩家2消失, 自己发接)", "万能AI (接到必落桌)", "AI vs AI (双方AI对打)"]
var debug_mode: int = 0

func _cycle_debug_mode() -> void:
	debug_mode = (debug_mode + 1) % DEBUG_MODES.size()
	_apply_debug_mode()

## 重新构建所有角色的形状 (ESC 菜单换形状/改大小后调用; 显示+碰撞+判定间距同步)。
func rebuild_shapes() -> void:
	for p in players:
		p.rebuild_shape()

## 打开 P4 变异面板 (ESC 菜单「变异」按钮调用)。
func open_mutation() -> void:
	mutation_panel.open()

## ② 导出/导入 P1 的 AI 基因。多槽位: 每槽一个文件, 互不覆盖 (存成熟体 / 续训)。
const GENOME_SLOTS: int = 6
const GENOME_PATH_LEGACY := "user://ai_genome.json"   ## 旧单文件 (迁移用)
var genome_slot: int = 1

func genome_path(slot: int) -> String:
	return "user://ai_genome_%d.json" % slot

func genome_slot_has(slot: int) -> bool:
	return FileAccess.file_exists(genome_path(slot))

## 把旧的单文件基因迁到 槽1 (若存在且 槽1 还是空的)。启动时调一次。
func _migrate_legacy_genome() -> void:
	if FileAccess.file_exists(GENOME_PATH_LEGACY) and not genome_slot_has(1):
		var g: AiGenome = AiGenome.load_from(GENOME_PATH_LEGACY)
		g.save_to(genome_path(1))

func export_genome() -> void:
	if players[0].genome == null:
		players[0].genome = AiGenome.make_default()
	var ok: bool = players[0].genome.save_to(genome_path(genome_slot))
	EventBus.notify("AI 基因已导出到 槽%d: %s  [%s]" % [genome_slot, "OK" if ok else "失败", players[0].genome.style_name()], 2.0)

func import_genome() -> void:
	players[0].genome = AiGenome.load_from(genome_path(genome_slot))
	EventBus.notify("AI 基因已从 槽%d 导入: 风格[%s]" % [genome_slot, players[0].genome.style_name()], 2.0)

## ② 锦标赛基因池: 从 6 个槽读基因 (空槽 -> 随机种子, 保证起步就有花样)。
func _build_ai_pool() -> void:
	match_ref.ai_pool = []
	for i in GENOME_SLOTS:
		var slot: int = i + 1
		match_ref.ai_pool.append(AiGenome.load_from(genome_path(slot)) if genome_slot_has(slot) \
			else AiGenome.make_random())

## ② 把当前池基因写回 6 个槽 (自动存档: 训练成果不丢)。
func _save_ai_pool() -> void:
	var n: int = mini(match_ref.ai_pool.size(), GENOME_SLOTS)
	if n == 0:
		return
	for i in n:
		match_ref.ai_pool[i].save_to(genome_path(i + 1))
	EventBus.notify("锦标赛: 已自动保存 %d 份池基因到槽" % n, 2.0)

# --- P4 试战: 应用候选, 双方 AI 打一小段给玩家"看球风" (不评分), 之后回面板 ---
var _testing: bool = false
var _test_timer: float = 0.0

func start_test(c: Dictionary) -> void:
	MutationSystem.apply(c)
	rebuild_shapes()
	mutation_panel.close()
	players[0].ai_enabled = true
	match_ref.set_solo(false)
	match_ref.restart()
	_testing = true
	_test_timer = GameConfig.ai_test_seconds
	get_tree().paused = false

func _process(dt: float) -> void:
	_update_juice(dt)
	if not _testing:
		return
	_test_timer -= dt
	if _test_timer <= 0.0:
		_testing = false
		players[0].ai_enabled = debug_mode == 3
		mutation_panel.open()

# ------------------------------------------------------------
#  视听反馈 [TEMP]: hitstop / 震屏 / 程序化音效
# ------------------------------------------------------------
func _update_juice(dt: float) -> void:
	if Engine.time_scale < 0.999 and Time.get_ticks_msec() >= _hitstop_until_ms:
		Engine.time_scale = 1.0
	if cam != null:
		if _shake > 0.0:
			cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
			_shake = maxf(0.0, _shake - 60.0 * dt)
		else:
			cam.offset = Vector2.ZERO

func _on_ball_touched(pl: PlayerController, _hp: HitPoint) -> void:
	if not _juice_enabled or ball == null:
		return
	# 只有"真正该这一方接、且合法"的触球才给反馈 (球飞过非接球方判定区不算)
	if not ball.returnable or ball.smash_invincible:
		return
	if match_ref != null and match_ref.expected_receiver != pl:
		return
	if ball.z < GameConfig.hit_height_min or ball.z > GameConfig.hit_height_max:
		return
	var smash: int = ball.last_smash_state
	var save: int = ball.last_save_state
	var strength: float = ball.last_strength
	if smash == 1:
		_shake = 9.0
		_hitstop_until_ms = Time.get_ticks_msec() + 70
		Engine.time_scale = 0.05
		_play(_sfx_smash, 1.05)
	elif save == 1:
		_shake = 5.0
		_play(_sfx_save, 1.0)
	elif smash == 2:
		_shake = 3.0
		_play(_sfx_hit, 0.8)
	else:
		_shake = 2.0 + 5.0 * clampf(strength, 0.0, 1.0)
		_play(_sfx_hit, 0.9 + 0.4 * clampf(strength, 0.0, 1.0))

func _play(stream: AudioStreamWAV, pitch: float) -> void:
	if _audio == null or stream == null:
		return
	_audio.stream = stream
	_audio.pitch_scale = pitch
	_audio.play()

## 程序化短音: 一段快速衰减的正弦 = "啪" 的一下 (不需要任何音频素材)。
func _make_click(ms: int, freq: float, decay: float) -> AudioStreamWAV:
	var sr: int = 22050
	var n: int = int(sr * ms / 1000.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t: float = float(i) / float(sr)
		var env: float = exp(-t * decay)
		var s: float = sin(TAU * freq * t) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.data = data
	return w

func _setup_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "Sfx"
	add_child(_audio)
	_sfx_hit = _make_click(60, 520.0, 70.0)
	_sfx_smash = _make_click(90, 220.0, 45.0)
	_sfx_save = _make_click(70, 700.0, 60.0)
	_sfx_score = _make_click(140, 880.0, 22.0)

func _apply_debug_mode() -> void:
	var solo: bool = debug_mode == 1
	var omni: bool = debug_mode == 2
	var ai_vs_ai: bool = debug_mode == 3
	# Solo: 玩家2 消失
	match_ref.set_solo(solo)
	var p2: PlayerController = players[1]
	p2.visible = not solo
	p2.set_physics_process(not solo)
	p2.freeze = solo
	p2.collision_layer = 0 if solo else 1
	p2.collision_mask = 0 if solo else 3
	# 万能 AI: 接到必落桌
	if p2 is AiPlayer:
		(p2 as AiPlayer).omniscient = omni
	# AI vs AI: 玩家1 也交给 AI 驱动 (ai_enabled), 并切成圆身 (和 P2 一样, 公平对拼)
	players[0].ai_enabled = ai_vs_ai
	players[0].set_circle_body(ai_vs_ai)
	# ② 进化: AI vs AI = 锦标赛 (6 份基因池轮换 + 自动存档); 普通模式 = P2 用存档基因, 陪你对局也进化
	if match_ref.ai_pool.size() > 0 and not ai_vs_ai:
		_save_ai_pool()                     # 离开训练: 自动把所有池基因写回槽
	match_ref.ai_evolve_enabled = ai_vs_ai or debug_mode == 0
	match_ref.generation = 0
	match_ref.ai_p1_idx = 0
	match_ref.ai_p2_idx = 0
	if ai_vs_ai:
		_build_ai_pool()                    # 从 6 个槽读基因 (空槽 -> 随机种子) 组成池
		players[0].genome = match_ref.ai_pool[0]
		players[1].genome = match_ref.ai_pool[0]
	elif debug_mode == 0:
		match_ref.ai_pool = []
		players[0].genome = null
		players[1].genome = AiGenome.load_from(genome_path(genome_slot))
	else:
		match_ref.ai_pool = []
		players[0].genome = null
		players[1].genome = null
	match_ref.debug_mode_name = DEBUG_MODES[debug_mode]
	EventBus.notify("调试模式 %d/%d: %s" % [debug_mode + 1, DEBUG_MODES.size(), DEBUG_MODES[debug_mode]], 2.5)
	hud.update_debug_menu()
	match_ref.restart()
