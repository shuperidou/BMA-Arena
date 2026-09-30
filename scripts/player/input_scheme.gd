class_name InputScheme
extends RefCounted
## 一个玩家的输入方案。
##
## 基础控制模型 (玩家1)：
##   移动 = 世界坐标 (WASD 永远对应屏幕上/下/左/右，与朝向无关)
##   朝向 = 默认朝球；按住鼠标后，鼠标相对锚点的"水平"拖动直接产生角度偏移。
##
## 朝向公式：
##   ball_angle   = angle(球XY - 角色位置)
##   angle_offset = clamp(水平拖动像素 * sensitivity, -max, +max)   (死区内为 0)
##   target_rot   = ball_angle + angle_offset
## 右拖 = 顺时针，左拖 = 逆时针 (固定映射，不随球/角色位置变化)。松开 -> offset=0。

enum AimMode { MOUSE, KEYBOARD, NONE }

var move_keys: Dictionary
var serve_key: int
var aim_mode: int
var rot_ccw_key: int
var rot_cw_key: int

# 鼠标拖动状态 (锚点方案)
var _dragging: bool = false
var _anchor_screen: Vector2 = Vector2.ZERO  ## 屏幕/视口坐标 (角度输入用)
var _anchor_world: Vector2 = Vector2.ZERO   ## 世界坐标 (仅 Debug 画图)

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

## 键盘转向输入: +1 = 顺时针。仅 KEYBOARD 模式用 (第二玩家临时方案)。
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
		_anchor_screen = _viewport_mouse(owner)
		_anchor_world = owner.get_global_mouse_position()
	elif not pressed and _dragging:
		# 松开：偏移归零
		_dragging = false

func is_dragging() -> bool:
	return _dragging

func _viewport_mouse(owner: Node2D) -> Vector2:
	return owner.get_viewport().get_mouse_position()

## 屏幕空间水平拖动距离 (像素)。旋转只用这个，不用世界坐标。
func mouse_drag_screen_x(owner: Node2D) -> float:
	if not _dragging:
		return 0.0
	return _viewport_mouse(owner).x - _anchor_screen.x

func mouse_anchor_world() -> Vector2:
	return _anchor_world

func current_mouse_world(owner: Node2D) -> Vector2:
	return owner.get_global_mouse_position()
