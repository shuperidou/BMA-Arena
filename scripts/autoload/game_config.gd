extends Node
## 全局可调参数 (autoload: GameConfig)
##
## 设计文档要求"规则不要散落在大量脚本里"，所以所有数值集中在这里。
## 标了 [TEMP] 的值是"为了试玩而临时定的"，不属于正式设计，随时可改。
## 标了 [TUNED] 的值是通过数值模拟/预调得来的，实际手感仍需试玩调整。
##
## 分区顺序：
##   A 场地几何 | B 球(物理+视觉) | C 击球初速度与可击高度 | D 角色通用
##   E 玩家1 鼠标控制 | F 击球系统 | G 比赛 | H AI | I 阻挡判定
##   J 调试显示 | K 输入 | L UI 字体 | M 便捷几何访问

# ============================================================
#  A. 场地几何 (世界坐标，单位=像素；-y 朝向墙)
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
#  B. 球 (俯视 XY + 独立高度 Z)
# ============================================================
## 约定 (全部是世界单位)：
##   position.x / position.y = 场地水平位置 (XY)
##   height_z                = 球距地面的高度 (独立变量，不参与 XY)
##   GROUND_Z = 地面高度；TABLE_Z = 桌面高度 (独立，可改)
var ground_z: float = 0.0              ## 落地高度 (height_z <= ground_z => 球死)
var table_z: float = 60.0              ## 桌面高度 (不假定为 0)
var wall_max_height: float = 300.0     ## 墙有效反弹高度上限 (预留；超过则飞过墙)

var ball_radius: float = 8.0           ## 逻辑碰撞半径 (固定，不随视觉缩放)
var ball_gravity: float = 1800.0       ## [TUNED] z 方向重力
var table_bounce_factor: float = 0.8   ## 桌弹垂直恢复系数 [TUNED]
var wall_bounce_factor: float = 0.85   ## 墙弹水平恢复系数 [TUNED]
var ball_air_drag: float = 0.10        ## 每秒水平阻尼比例
var bounce_vz_threshold: float = 25.0  ## 小于此下落速度不算"弹"，视为贴桌滚动

## 墙弹后"辅助回桌"：纯物理下球会掉进桌墙缝隙，这里主动给一个落点。
## 这是游戏化处理 (设计文档允许)，可用 wall_return_assist 关闭。
var wall_return_assist: bool = true
var wall_return_depth_frac: float = 0.8  ## 0=远边, 1=近边。落点=远边+深度*frac [TUNED]

## 视觉：高度 -> 大小 + 阴影 (游戏化提示，非真实透视)
var base_ball_scale: float = 1.0
var height_scale_factor: float = 0.9   ## 高度对显示大小的贡献
var min_visual_scale: float = 0.8
var max_visual_scale: float = 2.6
var shadow_offset_factor: float = 0.35 ## 每单位高度，球相对影子向上偏移的像素数
var shadow_scale: float = 1.0          ## 影子不随高度缩放

# ============================================================
#  C. 击球初速度 (v0 = 击出瞬间的速度) 与可击高度
# ============================================================
var hit_speed_v0: float = 520.0        ## 水平初速度 (发球用) [TUNED]
var hit_vz_v0: float = 450.0           ## 垂直初速度 (击球/发球弧线) [TUNED]
var hit_vz_min: float = 450.0          ## 允许的垂直初速度下限 (AI/变化用)
var hit_vz_max: float = 550.0          ## 允许的垂直初速度上限
## 可击球的高度范围 (第一阶段宽松)
var hit_height_min: float = 0.0
var hit_height_max: float = 150.0

# ============================================================
#  D. 角色通用 (尺寸 / 移动 / 朝向回正)
# ============================================================
var player_half_length: float = 90.0   ## 纺锤半长 (两端到中心)
var player_radius: float = 14.0        ## 纺锤半径
var player_mass: float = 1.0
var hit_reach: float = 44.0            ## 击球点判定额外半径 (翻倍) [TUNED]

var move_speed: float = 720.0
var move_accel: float = 3200.0         ## 速度变化最大加速度 (惯性/手感)

## 玩家1: 强回正到"面向桌中心"——撞歪后快速转回，但仍是物理刚体 (不硬锁死)。
var base_face_enabled: bool = true
var base_face_response: float = 30.0             ## 角度误差 -> 目标角速度
var base_face_max_angular_velocity: float = 25.0 ## rad/s (强)
var base_face_acceleration: float = 600.0        ## rad/s^2 (快速起转)
var player_angular_damp: float = 3.0             ## 物理角阻尼
## 鼠标左右拖动时，身体跟随做"有限的小幅旋转"(让判定区移动看起来自然)
var drag_rot_sensitivity: float = 0.0016         ## 每像素 -> 弧度
var drag_rot_max: float = 0.25                   ## 最大角度 (弧度, ~14°)

# ============================================================
#  E. 玩家1 鼠标控制 (按住建立锚点, 拖动决定击球区局部位移)
# ============================================================
## 鼠标在世界/屏幕中的 2D 拖动向量，**原样**作为击球判定区在角色**局部坐标系**中的位移
## (故意不做 world->local 转换)。击球区A局部偏移 = +delta, B = -delta (反向)。
## 不做缩放(数值相同)；只在局部空间限制大小；鼠标不改变 rotation。
var aim_mouse_button: int = MOUSE_BUTTON_LEFT
var mouse_drag_deadzone: float = 0.0         ## 拖动死区 (屏幕像素, 0=不启用)
var hit_zone_drag_scale: float = 1.0         ## 鼠标位移 -> 局部偏移 (1.0 = 数值相同)
var hit_zone_max_offset: float = 40.0        ## 局部位移上限 (世界单位)
var hit_zone_return_speed: float = 300.0     ## 松开后的回位速度 (单位/秒)

# ============================================================
#  F. 击球系统 (见 scripts/match/hit_system.gd)
# ============================================================
## 力度：由"击球区在世界空间中的实际速度"决定，经过曲线映射到球速区间。
var hit_speed_min: float = 600.0        ## 轻击球速
var hit_speed_max: float = 2000.0       ## 强击球速
var hit_speed_curve: float = 1.4        ## 力度响应曲线指数 (>1 需要更快才到强)
var hit_zone_speed_ref: float = 1500.0  ## 击球区速度归一化基准 (世界单位/秒)

## 方向：基础方向=面向桌中心；叠加"击球区位置 + 挥动方向"的偏置。
var hit_direction_strength: float = 0.6 ## 偏置对方向的影响程度 (0=永远朝桌, 1=完全由挥动决定)
var position_bias_weight: float = 0.5   ## 偏置里"击球区位置"的权重 (其余给挥动速度)

## 智能回球辅助 (0..1 单一旋钮)：1=只要触球就保证回桌；0=完全按玩家击球；中间=部分。
## 原始落点若不在"好区"(桌面内缩 assist_good_margin 像素) 就介入, 把方向拉向"墙的镜像点"。
var assist_strength: float = 1.0        ## 辅助程度 0..1
var max_assist_angle: float = 180.0     ## 修正角硬上限(度)。180=不限制
var assist_good_margin: float = 50.0    ## 好区=桌面内缩这么多像素。越大越容易触发

# ============================================================
#  G. 比赛 (计分/轮换均为临时方案) [TEMP]
# ============================================================
var score_to_win: int = 5
## 墙后接球方侧允许的桌弹次数。设计文档: "球在桌上第二次弹起 -> 接球方输"，
## 所以设为 1：允许第一次落桌，第 2 次连续落桌即判接球方输 (击球方得分)。
var receiver_bounce_limit: int = 1
var point_pause: float = 1.6
var interference_pause: float = 1.8
var hit_cooldown: float = 0.15

# ============================================================
#  H. AI (圆形智能体)
# ============================================================
## AI 自动发球前的等待时间 (给玩家反应时间)
var ai_serve_delay: float = 1.5
## AI 打出球后, 为了避开"阻挡嫌疑"而绕开对手接球走廊的偏移距离
var ai_avoid_distance: float = 160.0
## AI 失误概率 (0~1)。每次击球/发球按此概率触发一次"失误表现" (0=永不失误)。
var ai_error_chance: float = 0.08
var ai_error_aim_deg: float = 40.0     ## 失误表现-瞄偏: 最大偏角(度)
var ai_error_power_min: float = 0.4    ## 失误表现-太轻: 力度缩放
var ai_error_power_max: float = 1.5    ## 失误表现-太重: 力度缩放

# ============================================================
#  I. 阻挡判定 (全部临时阈值) [TEMP]
# ============================================================
var block_collision_window: float = 0.4     ## 碰撞后多久内仍算阻挡窗口
var block_pursuit_speed: float = 40.0       ## 接球方低于此速度视为"静止"(无意图, 不构成阻挡)
## 扇区判定：以接球方速度方向为轴，半角内 + 半径内的球才算"他正冲过去要接的球"
var block_sector_half_angle: float = 55.0   ## 扇区半角 (度)
var block_sector_radius: float = 260.0      ## 扇区半径 (世界单位)
## 可选门槛1: 时间可达 (球到达可接住点前, 接球方能否赶到)。默认关。
var block_require_time_reachable: bool = false
var block_reach_slack: float = 0.12
## 可选门槛2: 对手 B 必须在接球方的"球侧"(不在正后方), 防止背后推人也算阻挡。默认关。
var block_require_opponent_in_front: bool = false
## 碰撞持续时间门槛: 至少要接触这么久才算阻挡
var block_min_contact_time: float = 0.03

# ============================================================
#  J. 调试显示开关 (F1 总开关; 打开后按 1~6 分类)
# ============================================================
var debug_show_block: bool = true    ## 2: 阻挡扇区 + 判定因子
var debug_show_aim: bool = true      ## 3: 鼠标瞄准 / 击球调试
var debug_show_ball: bool = true     ## 4: 球状态
var debug_show_shapes: bool = true   ## 5: 碰撞体 / 速度
var debug_show_zones: bool = true    ## 6: 场地 / 桌 / 墙

# ============================================================
#  K. 输入 (physical keycodes)
# ============================================================
## 基础控制模型 (玩家1):
##   WASD -> 世界坐标平移 (与朝向完全无关); 鼠标 -> 目标朝向; Q/E 已删除。
var p1_move: Dictionary = {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D}
var p1_serve: int = KEY_SPACE
var p1_aim_mode: int = InputScheme.AimMode.MOUSE

# (玩家2 现在是 AI, 不再需要键盘输入变量。)

# ============================================================
#  L. UI 字体 (Godot 默认字体不含中文，用系统字体)
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
#  M. 便捷几何访问
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
