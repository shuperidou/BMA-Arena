extends Node
## 全局可调参数 (autoload: GameConfig)
##
## 设计文档要求"规则不要散落在大量脚本里"，所以所有数值集中在这里。
## 标了 [TEMP] 的值是"为了试玩而临时定的"，不属于正式设计，随时可改。
## 标了 [TUNED] 的值是通过数值模拟/预调得来的，实际手感仍需试玩调整。

# ============================================================
#  场地几何 (世界坐标，单位=像素；-y 朝向墙)
# ============================================================
## 整个活动区域。玩家被限制在其中。
var arena_size: Vector2 = Vector2(940.0, 500.0)
## 场地中心 (放在屏幕中心附近)。
var arena_center: Vector2 = Vector2(0.0, 22.0)

## 墙厚度。墙贴着场地顶边。
var wall_thickness: float = 16.0

## 课桌尺寸与中心。课桌长边平行墙。
## [TUNED] 桌面远边 y=-178, 近边 y=-28, 与墙之间的缝隙 34px。
var table_size: Vector2 = Vector2(380.0, 150.0)
var table_center: Vector2 = Vector2(0.0, -103.0)

# ============================================================
#  角色
# ============================================================
var player_half_length: float = 90.0   ## 纺锤半长 (两端到中心)
var player_radius: float = 14.0        ## 纺锤半径
var player_mass: float = 1.0
var hit_reach: float = 22.0            ## 击球点判定额外半径 [TUNED]

var move_speed: float = 360.0
var move_accel: float = 3200.0         ## 速度变化最大加速度 (惯性/手感)

# 旋转：鼠标给"目标角度"，角色带惯性逐渐追踪 (设计: 独立于移动)
var max_angular_velocity: float = 5.0   ## rad/s 最大角速度
var rotation_acceleration: float = 30.0 ## rad/s^2 角速度变化上限 (旋转惯性)
var rotation_gain: float = 6.0          ## 角度误差 -> 目标角速度的增益
var rotation_damping: float = 6.0       ## 无鼠标目标时的角速度衰减 (rad/s^2)
var min_mouse_distance: float = 6.0     ## 鼠标离角色太近则不改变目标朝向

# ============================================================
#  球 (俯视投影 + 独立高度 z)
# ============================================================
var ball_radius: float = 8.0
var ball_gravity: float = 1800.0       ## [TUNED]
var ball_table_rest: float = 0.8       ## 桌弹恢复系数 [TUNED]
var ball_wall_rest: float = 0.85       ## 墙弹恢复系数 [TUNED]
var ball_air_drag: float = 0.10        ## 每秒水平阻尼比例
var bounce_vz_threshold: float = 25.0  ## 小于此下落速度不算"弹"，视为贴桌滚动
var table_height: float = 60.0         ## 桌面高于地面 (用于判定落地)
var ball_visual_height_scale: float = 0.35

## 墙弹后"辅助回桌"：纯物理下球会掉进桌墙缝隙，这里主动给一个落点。
## 这是游戏化处理 (设计文档允许)，可用 wall_return_assist 关闭。
var wall_return_assist: bool = true
var wall_return_depth_frac: float = 0.8  ## 0=远边, 1=近边。落点=远边+深度*frac [TUNED]

## 击球赋予的初速度
var ball_hit_speed: float = 360.0      ## [TUNED]
var ball_hit_vz: float = 260.0         ## [TUNED]
var ball_hit_vz_min: float = 150.0
var ball_hit_vz_max: float = 360.0
var hit_player_vel_influence: float = 0.5
var max_hit_height: float = 60.0       ## 球高于此不可被击打 (约等于桌面高度)

# ============================================================
#  比赛 (计分/轮换均为临时方案) [TEMP]
# ============================================================
var score_to_win: int = 5
## 接球方侧允许的桌弹次数；超过即判接球方输。
var receiver_bounce_limit: int = 2
var point_pause: float = 1.6
var interference_pause: float = 1.8
var hit_cooldown: float = 0.15

# ============================================================
#  阻挡判定 (全部临时阈值) [TEMP]
# ============================================================
var block_collision_window: float = 0.4     ## 碰撞后多久内仍算阻挡窗口
var block_pursuit_max_dist: float = 360.0   ## 接球方离预计接球点多远仍算"有机会"
var block_corridor_width: float = 46.0      ## 危险走廊宽度
var block_pursuit_speed: float = 40.0       ## 判定"正在移动"的最小速度
var block_pursuit_dot: float = 0.3          ## 速度方向与接球方向的最小点积
var show_hints: bool = true                 ## 是否显示接球/阻挡空间提示

# ============================================================
#  输入 (physical keycodes)
# ============================================================
## 基础控制模型 (玩家1):
##   WASD -> 世界坐标平移 (与朝向完全无关)
##   鼠标 -> 目标朝向 (旋转带惯性追踪)
##   Q/E 等旋转键已删除。
var p1_move: Dictionary = {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D}
var p1_serve: int = KEY_SPACE
var p1_aim_mode: int = InputScheme.AimMode.MOUSE

## 玩家2 为本地双人测试用 [TEMP]: 方向键世界移动 + 键盘朝向。
## 基础控制模型以玩家1 为准；这里保留键盘朝向只是为了能单人/双人测试。
var p2_move: Dictionary = {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT}
var p2_serve: int = KEY_ENTER
var p2_aim_mode: int = InputScheme.AimMode.KEYBOARD
var p2_rot_ccw: int = KEY_COMMA
var p2_rot_cw: int = KEY_PERIOD

# ============================================================
#  UI 字体 (Godot 默认字体不含中文，用系统字体)
# ============================================================
var _ui_font: Font = null

func ui_font() -> Font:
	if _ui_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([
			"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "SimSun",
			"Noto Sans CJK SC", "sans-serif",
		])
		_ui_font = sf
	return _ui_font

# ============================================================
#  便捷几何访问
# ============================================================
func arena_rect() -> Rect2:
	return Rect2(arena_center - arena_size * 0.5, arena_size)

func wall_rect() -> Rect2:
	var a := arena_rect()
	return Rect2(a.position.x, a.position.y, a.size.x, wall_thickness)

## 墙朝向桌子的那一面的 y 坐标。
func wall_inner_y() -> float:
	return arena_rect().position.y + wall_thickness

func table_rect() -> Rect2:
	return Rect2(table_center - table_size * 0.5, table_size)
