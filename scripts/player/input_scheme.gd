class_name InputScheme
extends RefCounted
## 一个玩家的输入方案。用 physical keycode，避免键盘布局差异。
##
## 基础控制模型 (设计):
##   移动 = 世界坐标向量 (WASD 永远对应屏幕上/下/左/右，绝不按角色朝向旋转)
##   朝向 = 目标角度 (鼠标) 或键盘转向 (仅第二玩家临时用)
## 两者完全解耦。

enum AimMode { MOUSE, KEYBOARD, NONE }

var move_keys: Dictionary
var serve_key: int
var aim_mode: int
var rot_ccw_key: int
var rot_cw_key: int

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

## 键盘转向输入: +1 = 顺时针 (Godot 2D 正角速度为顺时针)。仅 KEYBOARD 模式用。
func turn_axis() -> float:
	return float(_pressed(rot_cw_key)) - float(_pressed(rot_ccw_key))

## 鼠标目标角度。无有效目标时返回 NAN。
func mouse_aim_angle(owner: Node2D) -> float:
	if aim_mode != AimMode.MOUSE:
		return NAN
	var d: Vector2 = owner.get_global_mouse_position() - owner.global_position
	if d.length() < GameConfig.min_mouse_distance:
		return NAN
	return d.angle()
