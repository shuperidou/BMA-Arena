class_name InputScheme
extends RefCounted
## 一个玩家的输入方案。
##
## 基础控制模型 (玩家1)：
##   移动 = 世界坐标 (WASD 永远对应屏幕上/下/左/右，与朝向无关)
##   朝向 = 默认朝球；按住鼠标拖动，以"按下瞬间的位置"为锚点做相对偏移
##
## 关键点：鼠标不是绝对瞄准。它是把"球周围的目标点"拖开：
##   mouse_offset_screen = current_mouse - mouse_anchor
##   aim_point           = ball_xy + mouse_offset_screen * mouse_to_world_scale
##   target_rotation     = angle(aim_point - character_position)

enum AimMode { MOUSE, KEYBOARD, NONE }

var move_keys: Dictionary
var serve_key: int
var aim_mode: int
var rot_ccw_key: int
var rot_cw_key: int

# 鼠标拖动状态 (锚点方案)
var _dragging: bool = false
var _anchor: Vector2 = Vector2.ZERO

func _init(p_move: Dictionary, p_serve: int, p_aim: int, p_ccw: int = 0, p_cw: int = 0) -> void:
	move_keys = p_move
	serve_key = p_serve
	aim_mode = p_aim
	rot_ccw_key = p_ccw
	rot_cw_key = p_cw

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

## 键盘转向输入: +1 = 顺时针。仅 KEYBOARD 模式用。
func turn_axis() -> float:
	return float(_pressed(rot_cw_key)) - float(_pressed(rot_ccw_key))

# ------------------------------------------------------------
#  鼠标锚点拖动 (每物理帧调用一次)
# ------------------------------------------------------------
func update_mouse(owner: Node2D) -> void:
	if aim_mode != AimMode.MOUSE:
		return
	var pressed: bool = Input.is_mouse_button_pressed(GameConfig.aim_mouse_button)
	if pressed and not _dragging:
		# 按下瞬间：记录锚点，偏移强制为 0 (不跳变)
		_dragging = true
		_anchor = owner.get_global_mouse_position()
	elif not pressed and _dragging:
		# 松开：偏移归零
		_dragging = false

func is_dragging() -> bool:
	return _dragging

func mouse_anchor() -> Vector2:
	return _anchor

func current_mouse(owner: Node2D) -> Vector2:
	return owner.get_global_mouse_position()

## 未限制的鼠标世界偏移 (基于锚点)。
func mouse_world_offset(owner: Node2D) -> Vector2:
	if not _dragging:
		return Vector2.ZERO
	return (owner.get_global_mouse_position() - _anchor) * GameConfig.mouse_to_world_scale
