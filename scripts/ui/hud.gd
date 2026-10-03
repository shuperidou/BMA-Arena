class_name Hud
extends CanvasLayer
## 临时 UI [TEMP]：比分 / 状态 / 操作提示 / 中央消息气泡。
## 灰盒阶段只求可读。

var match_ref: Match = null

var _score_label: Label
var _state_label: Label
var _controls_label: Label
var _message_label: Label
var _block_label: Label
var _save_label: Label
var _debug_menu_label: Label
var _debug_menu_visible: bool = false
var _msg_timer: float = 0.0

func _ready() -> void:
	_score_label = _make_label(Vector2(0, 16), 36, Color(1, 1, 1))
	_score_label.size = Vector2(1280, 60)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_state_label = _make_label(Vector2(24, 16), 22, Color(0.8, 0.85, 0.95))

	_block_label = _make_label(Vector2(0, 78), 26, Color(1, 0.9, 0.4))
	_block_label.size = Vector2(1280, 40)
	_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_block_label.visible = false

	_save_label = _make_label(Vector2(0, 118), 26, Color(0.4, 1.0, 0.5))
	_save_label.size = Vector2(1280, 40)
	_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_label.visible = false

	_message_label = _make_label(Vector2(0, 300), 46, Color(1, 1, 1))
	_message_label.size = Vector2(1280, 80)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.visible = false

	_controls_label = _make_label(Vector2(24, 596), 18, Color(0.7, 0.74, 0.82))
	_controls_label.size = Vector2(900, 110)
	_controls_label.text = "玩家1  WASD 世界移动 / 鼠标 朝向 / 空格 发球\n" \
		+ "玩家2  (圆形 AI, 自动跑动/发球/击球)\n" \
		+ "F1 调试菜单   R 重开   Esc 退出"

	_debug_menu_label = _make_label(Vector2(24, 96), 18, Color(0.6, 0.95, 1.0))
	_debug_menu_label.size = Vector2(560, 220)
	_debug_menu_label.visible = false

	EventBus.message.connect(_on_message)
	EventBus.score_changed.connect(_on_score)
	EventBus.match_state_changed.connect(_on_state)
	update_debug_menu()

func set_debug_menu(is_visible: bool) -> void:
	_debug_menu_visible = is_visible
	_debug_menu_label.visible = is_visible
	update_debug_menu()

func update_debug_menu() -> void:
	if _debug_menu_label == null:
		return
	var mode_name: String = match_ref.debug_mode_name if match_ref != null else "普通"
	_debug_menu_label.text = "[F1 调试菜单]  (再按一次关闭)\n" \
		+ " 1  模式轮换: %s\n" % mode_name \
		+ " 2  阻挡扇区+因子: %s\n" % _mark(GameConfig.debug_show_block) \
		+ " 3  鼠标/击球: %s\n" % _mark(GameConfig.debug_show_aim) \
		+ " 4  球状态: %s\n" % _mark(GameConfig.debug_show_ball) \
		+ " 5  碰撞体/速度: %s\n" % _mark(GameConfig.debug_show_shapes) \
		+ " 6  场地/桌/墙: %s\n" % _mark(GameConfig.debug_show_zones) \
		+ " 7  阻挡/救球提示: %s\n" % _mark(GameConfig.debug_show_block_hud) \
		+ " 8  AI扣杀: %s" % _mark(GameConfig.debug_ai_smash)

func _mark(b: bool) -> String:
	return "开" if b else "关"

func _make_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", GameConfig.ui_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	return l

func _process(dt: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= dt
		if _msg_timer <= 0.0:
			_message_label.visible = false
	_update_block_label()
	_update_hud_prompts()

func _update_hud_prompts() -> void:
	# 阻挡 / 救球 文字提示：只在 F1 打开且该分类开启时显示
	var show: bool = _debug_menu_visible and GameConfig.debug_show_block_hud
	_block_label.visible = show and _block_label.text != ""
	var saving: bool = false
	if match_ref != null and match_ref.ball != null:
		var b: Ball = match_ref.ball
		saving = b.hit_flash > 0.2 and bool(b.last_hit_info.get("defense_saved", false))
	_save_label.text = "救球！" if saving else ""
	_save_label.visible = show and saving

func _update_block_label() -> void:
	if match_ref == null or match_ref.block_system == null:
		return
	if not match_ref.block_system.active:
		_block_label.text = ""
		return
	match match_ref.block_system.state:
		GameTypes.Interference.CONFIRMED:
			_block_label.text = "阻挡成立!"
			_block_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		GameTypes.Interference.POSSIBLE:
			_block_label.text = "阻挡风险..."
			_block_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		_:
			_block_label.text = ""

func _on_message(text: String, duration: float) -> void:
	_message_label.text = text
	_message_label.visible = true
	_msg_timer = duration

func _on_score(scores: Dictionary) -> void:
	_score_label.text = "玩家1   %d : %d   玩家2" % [scores[1], scores[2]]

func _on_state(_s: int) -> void:
	if match_ref != null:
		_state_label.text = "状态: " + match_ref.state_name()
