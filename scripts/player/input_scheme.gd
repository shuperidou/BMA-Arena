class_name InputScheme
extends RefCounted
## 一个玩家的输入方案 (P1 鼠标)。
##
## 移动 = 世界坐标 (WASD 永远对应屏幕上/下/左/右，与朝向无关)
## 朝向 = 纯手动。按住鼠标后，鼠标相对锚点的"水平"拖动产生击球区局部位移。

enum AimMode { MOUSE, NONE }

var move_keys: Dictionary
var serve_key: int
var aim_mode: int

# 鼠标拖动状态 (锚点方案)
var _dragging: bool = false
var _anchor_screen: Vector2 = Vector2.ZERO  ## 屏幕/视口坐标 (拖动输入用)
var _anchor_world: Vector2 = Vector2.ZERO   ## 世界坐标 (仅 Debug 画图)

# 测试用覆盖 (无头环境无法真实移动鼠标)
var debug_dragging_override: bool = false
var debug_drag_override: Vector2 = Vector2.ZERO

func _init(p_move: Dictionary, p_serve: int, p_aim: int) -> void:
	move_keys = p_move
	serve_key = p_serve
	aim_mode = p_aim

func _pressed(keycode: int) -> bool:
	return keycode != 0 and Input.is_physical_key_pressed(keycode)

## 世界坐标移动方向 (俯视: up = -y)。与角色 rotation 无关。
func move_vector() -> Vector2:
	var v := Vector2(
		float(_pressed(move_keys["right"])) - float(_pressed(move_keys["left"])),
		float(_pressed(move_keys["down"])) - float(_pressed(move_keys["up"]))
	)
	return v.normalized() if v.length() > 1.0 else v

func serve_pressed() -> bool:
	return _pressed(serve_key)

# ------------------------------------------------------------
#  鼠标锚点拖动
# ------------------------------------------------------------
func update_mouse(owner: Node2D) -> void:
	if aim_mode != AimMode.MOUSE:
		return
	var pressed: bool = Input.is_mouse_button_pressed(GameConfig.aim_mouse_button)
	if pressed and not _dragging:
		_dragging = true
		_anchor_screen = _viewport_mouse(owner)
		_anchor_world = owner.get_global_mouse_position()
	elif not pressed and _dragging:
		_dragging = false

func is_dragging() -> bool:
	return debug_dragging_override or _dragging

func _viewport_mouse(owner: Node2D) -> Vector2:
	return owner.get_viewport().get_mouse_position()

## 屏幕/视口空间的完整 2D 拖动向量 (像素)。
func mouse_drag_screen(owner: Node2D) -> Vector2:
	if debug_dragging_override:
		return debug_drag_override
	if not _dragging:
		return Vector2.ZERO
	return _viewport_mouse(owner) - _anchor_screen

## 水平分量 (击球区拖动 + 身体微转用)。
func mouse_drag_screen_x(owner: Node2D) -> float:
	return mouse_drag_screen(owner).x

func mouse_anchor_world() -> Vector2:
	return _anchor_world

func current_mouse_world(owner: Node2D) -> Vector2:
	return owner.get_global_mouse_position()
