class_name TreePanel
extends CanvasLayer
## P5 家谱 / 进化树查看面板: 按代展示所有节点 (当前/过去/被淘汰), 点节点看详情,
## 并可"回到这一代" = 后悔机制 (重新启用被淘汰的旧形态)。
## 打开时暂停游戏。

var main_ref: Node = null
var _rows: VBoxContainer = null
var _detail: Label = null
var _restore_btn: Button = null
var _sel_id: int = -1

func _ready() -> void:
	layer = 27
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func open() -> void:
	_refresh()
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

func _font(c: Control, sz: int) -> void:
	c.add_theme_font_override("font", GameConfig.ui_font())
	c.add_theme_font_size_override("font_size", sz)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(120, 56)
	panel.size = Vector2(1040, 610)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(24, 16)
	vb.size = Vector2(992, 578)
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "家谱 · 进化树    (Esc 关闭 · 点节点看详情 · 可回到某代 = 后悔机制)"
	_font(title, 24)
	vb.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(992, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_rows)

	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(992, 60)
	_font(_detail, 17)
	vb.add_child(_detail)

	_restore_btn = Button.new()
	_restore_btn.text = "回到这一代 (启用此形态)"
	_font(_restore_btn, 18)
	_restore_btn.disabled = true
	_restore_btn.pressed.connect(_on_restore)
	vb.add_child(_restore_btn)

func _tree() -> CharacterTree:
	if main_ref != null and "character_tree" in main_ref:
		return main_ref.character_tree
	return null

func _refresh() -> void:
	for ch in _rows.get_children():
		ch.queue_free()
	_sel_id = -1
	_detail.text = ""
	_restore_btn.disabled = true
	var t: CharacterTree = _tree()
	if t == null or t.nodes.is_empty():
		_detail.text = "还没有家谱记录。打完一局 / 用 ESC「变异」选一次形态就会记录。"
		return
	var by_gen: Dictionary = {}
	for n in t.nodes:
		var g: int = int(n.get("gen", 0))
		if not by_gen.has(g):
			by_gen[g] = []
		by_gen[g].append(n)
	var gens: Array = by_gen.keys()
	gens.sort()
	for g in gens:
		var grow := HBoxContainer.new()
		grow.add_theme_constant_override("separation", 8)
		var glab := Label.new()
		glab.text = "第%d代" % g
		glab.custom_minimum_size = Vector2(72, 0)
		_font(glab, 16)
		grow.add_child(glab)
		for n in by_gen[g]:
			grow.add_child(_make_card(t, n))
		_rows.add_child(grow)

func _make_card(t: CharacterTree, n: Dictionary) -> Control:
	var id: int = int(n.get("id", -1))
	var status: String = String(n.get("status", ""))
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(100, 0)
	var prev := ShapePreview.new()
	prev.setup_candidate(n)
	card.add_child(prev)
	var lab := Label.new()
	var mark: String = "◀当前" if id == t.current_id else ("淘汰" if status == "eliminated" else "过去")
	lab.text = "%s\n%s" % [mark, String(n.get("label", "?"))]
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(lab, 13)
	if status == "eliminated":
		lab.add_theme_color_override("font_color", Color(0.55, 0.5, 0.5))
	elif id == t.current_id:
		lab.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	card.add_child(lab)
	var btn := Button.new()
	btn.text = "看/选"
	_font(btn, 13)
	btn.pressed.connect(_on_select.bind(id))
	card.add_child(btn)
	return card

func _on_select(id: int) -> void:
	_sel_id = id
	var t: CharacterTree = _tree()
	var n: Dictionary = t.get_node_by_id(id) if t != null else {}
	if n.is_empty():
		return
	_detail.text = "【%s】%s    状态:%s\n%s" % [
		String(n.get("label", "")), MutationSystem.describe(n),
		String(n.get("status", "")), _lineage_text(t, n)]
	_restore_btn.disabled = (t != null and id == t.current_id)

func _lineage_text(t: CharacterTree, n: Dictionary) -> String:
	var names: Array = []
	var id: int = int(n.get("id", -1))
	while id >= 0:
		var m: Dictionary = t.get_node_by_id(id)
		if m.is_empty():
			break
		names.push_front(String(m.get("label", "?")))
		id = int(m.get("parent", -1))
	return "血缘: " + " → ".join(names)

func _on_restore() -> void:
	if _sel_id < 0:
		return
	if main_ref != null and main_ref.has_method("restore_node"):
		main_ref.restore_node(_sel_id)
	_refresh()
