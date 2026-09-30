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

## 球死亡原因 (TEMP 计分规则依据)
enum DeathReason {
	NONE,
	FLOOR,          ## 落地
	DOUBLE_BOUNCE,  ## 接球方侧桌弹次数超限
	OUT_OF_BOUNDS,  ## 出界
}

## 阻挡判定内部状态
enum Interference {
	NONE,
	POSSIBLE,
	CONFIRMED,
}
