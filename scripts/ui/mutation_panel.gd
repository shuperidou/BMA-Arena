class_name MutationPanel
extends CanvasLayer
## P4 · 变异面板: 展示候选 (形状+大小), 玩家凭手感自己选 (涌现式, 无推荐/评分)。
## 打开时暂停游戏。点按钮或按 1~N 选择; Esc 取消。

var main_ref: Node = null
var _list: VBoxContainer = null
var _cands: Array = []

func _ready() -> void:
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc: int = event.physical_keycode
	if kc == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif kc >= KEY_1 and kc <= KEY_9:
		var idx: int = kc - KEY_1
		if idx >= 0 and idx < _cands.size():
			_pick(_cands[idx])
			get_viewport().set_input_as_handled()

func open() -> void:
	_refresh()
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(340, 80)
	panel.size = Vector2(600, 480)
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.position = Vector2(28, 20)
	vb.size = Vector2(544, 440)
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "变异 · 选一个保留  (Esc 取消)"
	_font(title, 26)
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "大 = 够球/阻挡覆盖大, 但移动慢、转身难; 小 = 灵活。没有最优, 凭手感选。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_font(hint, 15)
	vb.add_child(hint)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	vb.add_child(_list)

func _font(c: Control, sz: int) -> void:
	c.add_theme_font_override("font", GameConfig.ui_font())
	c.add_theme_font_size_override("font_size", sz)

func _refresh() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	_cands = MutationSystem.generate()
	for i in _cands.size():
		var c: Dictionary = _cands[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var prev := ShapePreview.new()
		prev.setup(int(c.shape_index), float(c.size_scale))
		row.add_child(prev)
		var lab := Label.new()
		lab.text = "[%d] %s · %s" % [i + 1, str(c.get("name", "")), MutationSystem.describe(c)]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_font(lab, 19)
		row.add_child(lab)
		var pick := Button.new()
		pick.text = "选"
		_font(pick, 18)
		pick.pressed.connect(_pick.bind(c))
		row.add_child(pick)
		var test := Button.new()
		test.text = "试战"
		_font(test, 18)
		test.pressed.connect(_test.bind(c))
		row.add_child(test)
		_list.add_child(row)

func _test(c: Dictionary) -> void:
	if main_ref != null and main_ref.has_method("start_test"):
		main_ref.start_test(c)

func _pick(c: Dictionary) -> void:
	MutationSystem.apply(c)
	if main_ref != null and main_ref.has_method("rebuild_shapes"):
		main_ref.rebuild_shapes()
	close()
