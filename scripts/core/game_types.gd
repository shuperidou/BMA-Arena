class_name GameTypes
extends RefCounted
## Shared enums. Kept in one place so the match / ball / block systems agree.

enum MatchState {
	PREPARE,      ## 角色就位，等待发球
	SERVE,        ## 球被发球方持球，等待发球输入
	RALLY,        ## 球在飞行中
	POINT_PAUSE,  ## 得分后短暂停顿
	INTERFERENCE, ## 阻挡成立，重发停顿
	MATCH_OVER,   ## 比赛结束
}

enum BallState {
	INACTIVE, ## 未激活
	HELD,     ## 被发球方持球
	LIVE,     ## 飞行中
	DEAD,     ## 已死
}

## 球的高度状态 (逻辑状态，比赛系统读取，不靠视觉判断)
enum BallHeightState {
	NONE,       ## 非飞行
	ON_GROUND,  ## 触地
	ASCENDING,  ## 上升
	DESCENDING, ## 下降
	HOVERING,   ## 接近顶点/贴桌
}

## 球死亡原因 (TEMP 计分规则依据)
enum DeathReason {
	NONE,
	FLOOR,          ## 落地
	DOUBLE_BOUNCE,  ## 接球方侧(墙后)桌弹超过一次 -> 接球方输
	BAD_BOUNCE,     ## 同一面连续弹超过一次(未到墙就跳弹/墙连弹) -> 击球方失误
	OUT_OF_BOUNDS,  ## 出界
}

## 阻挡判定内部状态
enum Interference {
	NONE,
	POSSIBLE,
	CONFIRMED,
}
