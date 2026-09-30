class_name InputScheme
extends RefCounted
## 一个玩家的键位方案。用 physical keycode，避免键盘布局差异。
##
## 使用代码轮询而不是 InputMap，方便原型阶段零配置运行。

var keys: Dictionary

func _init(key_map: Dictionary) -> void:
	keys = key_map

func _pressed(action: String) -> bool:
	return Input.is_physical_key_pressed(keys[action])

## 移动方向 (俯视: up = -y)。
func move_vector() -> Vector2:
	var v := Vector2(
		float(_pressed("right")) - float(_pressed("left")),
		float(_pressed("down")) - float(_pressed("up"))
	)
	return v.normalized() if v.length() > 1.0 else v

## 旋转输入: +1 = 顺时针 (Godot 2D 正角速度为顺时针)。
func turn_axis() -> float:
	return float(_pressed("rot_cw")) - float(_pressed("rot_ccw"))

func serve_pressed() -> bool:
	return _pressed("serve")
