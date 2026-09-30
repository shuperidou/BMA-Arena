extends Node
## 全局信号 (autoload: EventBus)
##
## 只用来做跨系统的轻量通知，尤其是 UI。
## 球的物理事件仍然走 Ball 自己的信号，方便以后支持多球。

## HUD 中央提示文字 (例如"玩家1 得分"、"阻挡！")
signal message(text: String, duration: float)

## 阻挡状态变化，用于显示提示 / debug
signal interference_changed(state: int, info: Dictionary)

## 比分变化
signal score_changed(scores: Dictionary)

## 比赛状态变化
signal match_state_changed(state: int)

## 一局结束
signal match_finished(winner_index: int, scores: Dictionary)

func notify(text: String, duration: float = 1.6) -> void:
	message.emit(text, duration)
