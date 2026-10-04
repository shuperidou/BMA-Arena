class_name EscMenu
extends CanvasLayer
## ESC 菜单: 形状选择 + 角色大小拖动条 + 继续/退出。打开时暂停游戏。
## 用代码构建 UI (与工程"代码组装"风格一致)。

var main_ref: Node = null
var _ai_opt: OptionButton
var _filter_opt: OptionButton
var _smooth_slider: HSlider
var _size_slider: HSlider
var _size_label: Label

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(430, 120)
	panel.size = Vector2(420, 420)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(28, 22)
	vb.size = Vector2(364, 376)
	vb.add_theme_constant_override("separation", 18)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "菜单   (Esc 关闭)"
	_font(title, 28)
	vb.add_child(title)

	# 身体 (现在只有纺锤; 改身体在「变异」面板)
	var body_label := Label.new()
	body_label.text = "身体: 纺锤   长%.0f 宽%.0f 大小%.2f" % [
		GameConfig.player_half_length, GameConfig.player_radius, GameConfig.player_size_scale]
	_font(body_label, 17)
	vb.add_child(body_label)

	# AI 强度
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 10)
	vb.add_child(arow)
	var alab := Label.new()
	alab.text = "AI 强度:"
	_font(alab, 20)
	arow.add_child(alab)
	_ai_opt = OptionButton.new()
	_font(_ai_opt, 20)
	for i in GameConfig.ai_level_count():
		_ai_opt.add_item(GameConfig.ai_level_name(i), i)
	_ai_opt.selected = GameConfig.ai_level
	_ai_opt.get_popup().add_theme_font_override("font", GameConfig.ui_font())
	_ai_opt.get_popup().add_theme_font_size_override("font_size", 20)
	_ai_opt.item_selected.connect(_on_ai_level)
	arow.add_child(_ai_opt)

	# 挥拍滤波 (A 平滑 / B 蓄力; 玩家/AI 共享)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 10)
	vb.add_child(frow)
	var flab := Label.new()
	flab.text = "挥拍滤波:"
	_font(flab, 19)
	frow.add_child(flab)
	_filter_opt = OptionButton.new()
	_font(_filter_opt, 18)
	var fnames: Array[String] = ["瞬时", "平滑A", "蓄力B", "A+B"]
	for i in fnames.size():
		_filter_opt.add_item(fnames[i], i)
	_filter_opt.selected = GameConfig.swing_filter_mode
	_filter_opt.item_selected.connect(_on_filter_mode)
	frow.add_child(_filter_opt)
	_smooth_slider = HSlider.new()
	_smooth_slider.min_value = 0.02
	_smooth_slider.max_value = 0.5
	_smooth_slider.step = 0.01
	_smooth_slider.value = GameConfig.swing_smooth_tau
	_smooth_slider.custom_minimum_size = Vector2(150, 26)
	_smooth_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_smooth_slider.value_changed.connect(_on_smooth_tau)
	frow.add_child(_smooth_slider)
	var ftau := Label.new()
	ftau.text = "τ=%.2fs" % GameConfig.swing_smooth_tau
	_font(ftau, 15)
	frow.add_child(ftau)

	# 大小拖动条
	var zrow := HBoxContainer.new()
	zrow.add_theme_constant_override("separation", 10)
	vb.add_child(zrow)
	var zlab := Label.new()
	zlab.text = "大小:"
	_font(zlab, 20)
	zrow.add_child(zlab)
	_size_slider = HSlider.new()
	_size_slider.min_value = 0.5
	_size_slider.max_value = 2.0
	_size_slider.step = 0.05
	_size_slider.value = GameConfig.player_size_scale
	_size_slider.custom_minimum_size = Vector2(220, 28)
	_size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_size_slider.value_changed.connect(_on_size)
	zrow.add_child(_size_slider)
	_size_label = Label.new()
	_font(_size_label, 20)
	zrow.add_child(_size_label)
	_update_size_label()

	# 按钮
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 16)
	vb.add_child(brow)
	var mutate := Button.new()
	mutate.text = "变异"
	_font(mutate, 20)
	mutate.pressed.connect(_on_mutate)
	brow.add_child(mutate)
	var bexp := Button.new()
	bexp.text = "导出基因"
	_font(bexp, 17)
	bexp.pressed.connect(_on_export_genome)
	brow.add_child(bexp)
	var bimp := Button.new()
	bimp.text = "导入基因"
	_font(bimp, 17)
	bimp.pressed.connect(_on_import_genome)
	brow.add_child(bimp)
	var resume := Button.new()
	resume.text = "继续"
	_font(resume, 20)
	resume.pressed.connect(close)
	brow.add_child(resume)
	var quit := Button.new()
	quit.text = "退出游戏"
	_font(quit, 20)
	quit.pressed.connect(func() -> void: get_tree().quit())
	brow.add_child(quit)

func _font(c: Control, sz: int) -> void:
	c.add_theme_font_override("font", GameConfig.ui_font())
	c.add_theme_font_size_override("font_size", sz)

func _on_ai_level(i: int) -> void:
	GameConfig.ai_level = i
	GameConfig.ai_apply_level()

func _on_mutate() -> void:
	close()
	if main_ref != null and main_ref.has_method("open_mutation"):
		main_ref.open_mutation()

func _on_export_genome() -> void:
	if main_ref != null and main_ref.has_method("export_genome"):
		main_ref.export_genome()

func _on_import_genome() -> void:
	if main_ref != null and main_ref.has_method("import_genome"):
		main_ref.import_genome()

func _on_filter_mode(i: int) -> void:
	GameConfig.swing_filter_mode = i

func _on_smooth_tau(v: float) -> void:
	GameConfig.swing_smooth_tau = v

func _on_size(v: float) -> void:
	GameConfig.player_size_scale = v
	_update_size_label()
	_apply()

func _update_size_label() -> void:
	_size_label.text = "%.2f" % GameConfig.player_size_scale

func _apply() -> void:
	if main_ref != null and main_ref.has_method("rebuild_shapes"):
		main_ref.rebuild_shapes()
