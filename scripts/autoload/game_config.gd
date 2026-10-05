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
## 角色本体允许"越过桌面"这么多像素 (桌子对玩家的碰撞体向内缩这么多; 球弹跳仍按 table_rect)。
var table_player_margin: float = 14.0

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
var wall_return_assist: bool = false
var wall_return_depth_frac: float = 0.8  ## 0=远边, 1=近边。落点=远边+深度*frac [TUNED]

## 视觉：高度 -> 大小 + 阴影 (游戏化提示，非真实透视)
var base_ball_scale: float = 0.8
var height_scale_factor: float = 1.2   ## 高度对显示大小的贡献
var min_visual_scale: float = 0.8
var max_visual_scale: float = 50.6
var shadow_offset_factor: float = 0.35 ## 每单位高度，球相对影子向上偏移的像素数
var shadow_scale: float = 1.0          ## 影子不随高度缩放

# ============================================================
#  C. 击球初速度 (v0 = 击出瞬间的速度) 与可击高度
# ============================================================
var hit_speed_v0: float = 520.0        ## 水平初速度 (发球用) [TUNED]
var hit_vz_v0: float = 450.0           ## 垂直初速度 (击球/发球弧线) [TUNED]
var hit_vz_min: float = 450.0          ## 允许的垂直初速度下限 (AI/变化用)
var hit_vz_max: float = 850.0          ## 允许的垂直初速度上限
## 可击球的高度范围 (第一阶段宽松)
var hit_height_min: float = 10.0
var hit_height_max: float = 250.0

# ============================================================
#  D. 角色通用 (尺寸 / 移动 / 朝向回正)
# ============================================================
var player_half_length: float = 90.0   ## 纺锤半长 (两端到中心) [旧, 形状系统接管后仅备用]
var player_radius: float = 14.0        ## 纺锤半径 [旧]
var player_mass: float = 1.0
var hit_reach: float = 44.0            ## 击球点判定额外半径 (翻倍) [TUNED]

## ---- 形状系统 (P4 身体构筑基础) ----
## 角色的"显示形状 + 碰撞箱 + 判定区间距"由同一条形状方程统一决定, 三者永远同步。
## 每个形状在 _shape_points() 里采样边界点 -> 同时给 CollisionPolygon2D 和绘制用。
## 加形状 = player_shape_count/name/half/points 各加一处分支 + 对应参数即可。
## ---- 身体系统 (P4 身体构筑基础) ----
## 只有"纺锤"实现了击球判定; 其它身体(圆/菱/椭/未来)以后各自设计"判定方式", 不共用判定区。
## "判定方式"做成每身体可插拔 (player_body_kind); 现在只有 "spindle"。
var player_body_kind: String = "spindle"  ## 身体种类 (决定用哪套击球判定): "spindle" 纺锤 / "circle" 圆
## 已实现的身体族 (每种 = 一套 碰撞 + 判定布点 规则)。顺序 = ESC 菜单顺序。
## 加新身体: 往这里加 key + 在 body_kind_label 加名字 + 在 PlayerController 写 _build_xxx()。
const BODY_KINDS: Array[String] = ["spindle", "circle", "polar", "superformula", "sf2"]
func body_kind_label(k: String) -> String:
	match k:
		"circle":
			return "圆 (中心全向)"
		"polar":
			return "极坐标花瓣 (花瓣数=判定点)"
		"superformula":
			return "超公式 (m 偶数)"
		"sf2":
			return "轴对称形 (m=2)"
		_:
			return "纺锤 (两端两点)"
var circle_body_radius: float = 20.0      ## "圆"身体的碰撞半径
var circle_hit_reach: float = 40.0        ## "圆"身体的中心判定半径 (全向覆盖; 圆靠挥拍定方向, 不靠判定点位)
## "极坐标花瓣"身体: 形状 = r(θ) = r0·(1 + amp·cos(lobes·θ)); 判定点放在各花瓣尖(=花瓣数个)。
var polar_r0: float = 26.0                ## 基础半径
var polar_lobes: int = 4                  ## 花瓣数 (同时 = 判定点数量)
var polar_amp: float = 0.45               ## 花瓣深浅 0~0.9 (0=圆, 越大越尖)
## 旋转体(花瓣/超公式)专属控制: 拖动上下=判定点径向缩放(向内缩进), 左右=绕形状中心旋转。
var polar_radial_per_px: float = 0.6      ## 拖动 y 每像素 -> 径向位移 (正=向内缩)
var polar_rot_per_px: float = 0.012       ## 拖动 x 每像素 -> 绕心旋转弧度
var polar_reach_scale: float = 0.5        ## 花瓣判定点半径的整体缩放 (判定区偏大 -> 调小)
## "超公式"身体: r(θ) = (|cos(mθ/4)/a|^n2 + |sin(mθ/4)/b|^n3)^(-1/n1)。一大类封闭花/星/圆角多边形。
## r = k·(|cos(0.25·m·θ)|^n1 + |sin(0.25·m·θ)|^n2)^n3
var sf_m: float = 6.0                     ## 仅偶数, ≤10
var sf_n1: float = 1.0                    ## ∈(0,5]
var sf_n2: float = 1.0                    ## ∈(0,5]
var sf_n3: float = 3.0                    ## ∈[-10,-3] ∪ [3,10]
var sf_k: float = 1.0                     ## 大小系数 ∈[0.5,2]
var sf_px: float = 30.0                   ## k=1 时的像素半径 (与 k 相乘得实际大小)
var sf_n_max: float = 10.0                ## m 的上限 (偶数)
## 判定点数量 = m/2 (m 偶数; 位置+控制+半径沿用花瓣那套)
func sf_pip_count(m: float) -> int:
	return maxi(int(round(m)) / 2, 1)
var player_shape_index: int = 0           ## 当前身体显示形状 (只有 0 纺锤是已设计的)
var shape_segments: int = 28              ## 曲边采样段数
## 纺锤(唯一已设计): 形状=胶囊; 方程参数 = player_half_length(长半) + player_radius(宽半);
##   判定区位置 = ±(player_half_length×大小); 判定区大小 = hit_reach。三者同步。
## 角色大小倍率: 同时缩放 形状多边形 + 碰撞箱 + 判定区间距。
var player_size_scale: float = 1.0

## ---- P4 变异 v1 (最小可验证)：只变异"纺锤"的大小 + 形状方程参数(长/宽); 代价=大→移动慢/转身难 ----
var mutation_candidates: int = 4          ## 每次生成的候选数 (含"保留当前")
var mutation_kind_chance: float = 0.35    ## 变异时"换身体种类"的概率 (0=只调参, 1=总换)
var mutation_size_delta: float = 0.15     ## 大小抖动量
var mutation_size_min: float = 0.85
var mutation_size_max: float = 1.25
var mutation_len_delta: float = 16.0      ## 长半抖动量 (加减)
var mutation_len_min: float = 58.0
var mutation_len_max: float = 132.0
var mutation_wid_delta: float = 5.0       ## 宽半抖动量 (加减)
var mutation_wid_min: float = 8.0
var mutation_wid_max: float = 30.0
var size_move_exponent: float = 0.55      ## 体型→移动速度代价: speed ∝ size^(-此指数)
var size_turn_exponent: float = 0.45      ## 体型→转身速度代价: turn  ∝ size^(-此指数)
var ai_test_seconds: float = 5.0          ## P4"试战"时长(秒): 应用候选后双方AI对打一小段给玩家看

## ---- ② AI 进化 [TEMP]: 变异率 / 探险度 (ESC 可调) ----
## 锦标赛每分, 赢家在池内的基因每个位 ±此值的随机扰动。0=只靠选择(不探索), 越大越爱乱试。
var ai_mutation_rate: float = 0.04
var ai_crossover_amount: float = 0.12     ## 赢家吸收对手基因的比例 (0=不学对手)

## ---- AI 救球 (F1 菜单 0 开关): 搏命(A) + 冷却(B) ----
## AI 只在"够呛"(球很高)且冷却好时, 用一次防守姿态救球 -> 救出的球很高, 正好可被扣杀惩罚。
var ai_save_enabled: bool = true          ## 默认开: AI 会救球 (F1 菜单 0 可关)
var ai_save_cooldown: float = 4.0         ## 冷却(秒): 一次救球后这么久内不再救
var ai_save_low_band: float = 110.0        ## "够呛"=球够低: z ≤ hit_height_min + 此带宽, 才考虑救球 (不再是"球很高")

## ---- 挥拍滤波 (玩家/AI 共享): 力量不看"瞬时", 看"前一段" ----
##   0=瞬时(原) 1=A平滑(短窗低通) 2=B蓄力(累积位移, 衰减) 3=A+B
var swing_filter_mode: int = 1
var swing_smooth_tau: float = 0.10        ## A: 平滑时间常数(秒)
var swing_charge_tau: float = 0.35        ## B: 蓄力衰减时间常数(秒)
var swing_charge_ref: float = 260.0       ## B: 蓄力满值所需的"沿朝向的甩动位移" (速度×秒的累积)

## 已设计的身体种类数 (只有纺锤)。
func player_shape_count() -> int:
	return 1

func player_shape_name(_idx: int = -1) -> String:
	return "纺锤"

## 纺锤长轴(局部y = 判定区连线方向)半长 -> 判定区间距 (随身体同步)。
func player_shape_half(_idx: int = -1) -> float:
	return player_half_length * player_size_scale

## 纺锤(胶囊)边界点: 给定 长半 L / 宽半 r (未乘大小)。
func spindle_points(L: float, r: float) -> PackedVector2Array:
	var seg2: int = maxi(shape_segments / 2, 6)
	var sc: float = maxf(L - r, 0.0)
	var pts := PackedVector2Array()
	pts.append(Vector2(r, -sc))
	pts.append(Vector2(r, sc))
	for k in range(1, seg2):
		var t: float = PI * float(k) / float(seg2)
		pts.append(Vector2(r * cos(t), sc + r * sin(t)))
	pts.append(Vector2(-r, sc))
	pts.append(Vector2(-r, -sc))
	for k in range(1, seg2):
		var t: float = PI + PI * float(k) / float(seg2)
		pts.append(Vector2(r * cos(t), -sc + r * sin(t)))
	return pts

## 极坐标花瓣边界: r(θ) = r0·(1 + amp·cos(lobes·θ))。(lobes 个花瓣尖)
func polar_points(r0: float, lobes: int, amp: float, seg: int = 64) -> PackedVector2Array:
	var n: int = maxi(seg, 12)
	var lo: float = maxf(float(lobes), 1.0)
	var a: float = clampf(amp, -0.9, 0.9)
	var pts := PackedVector2Array()
	for k in n:
		var th: float = TAU * float(k) / float(n)
		var r: float = r0 * (1.0 + a * cos(lo * th))
		pts.append(Vector2(r * cos(th), r * sin(th)))
	return pts

## 超公式半径 (不含大小系数): r(θ) = (|cos(0.25·m·θ)|^n1 + |sin(0.25·m·θ)|^n2)^n3
func superformula_r(th: float, m: float, n1: float, n2: float, n3: float) -> float:
	var a: float = pow(absf(cos(0.25 * m * th)), maxf(n1, 0.01))
	var b: float = pow(absf(sin(0.25 * m * th)), maxf(n2, 0.01))
	return pow(maxf(a + b, 1e-6), maxf(n3, 0.01))

## 合法性: 生成图形需 r_max<5k 且 r_max-r_min>0.5k (核心 g 的最大<5 且 变化>0.5)。
func superformula_valid(m: float, n1: float, n2: float, n3: float, seg: int = 48) -> bool:
	var mx: float = -1e9
	var mn: float = 1e9
	for i in seg:
		var th: float = TAU * float(i) / float(seg)
		var g: float = superformula_r(th, m, n1, n2, n3)
		mx = maxf(mx, g)
		mn = minf(mn, g)
	return mx < 5.0 and (mx - mn) > 0.5

## 采样一组合法参数 (n3∈[-10,-3]∪[3,10], n1/n2∈(0,5]) 直到满足约束。
func superformula_sample_valid(m: float) -> Dictionary:
	for attempt in 300:
		var n1: float = randf_range(0.2, 5.0)
		var n2: float = randf_range(0.2, 5.0)
		var n3: float = randf_range(3.0, 10.0)
		if randf() < 0.5:
			n3 = -n3
		if superformula_valid(m, n1, n2, n3):
			return {"sf_n1": n1, "sf_n2": n2, "sf_n3": n3}
	return {"sf_n1": 1.0, "sf_n2": 1.0, "sf_n3": 3.0}   # 兜底 (已知合法)

## 超公式边界点 (k = 大小系数 [0.5,2]; 实际大小 = k·sf_px)。
func superformula_points(m: float, n1: float, n2: float, n3: float, k: float, seg: int = 72) -> PackedVector2Array:
	var n: int = maxi(seg, 16)
	var scale: float = clampf(k, 0.5, 2.0) * sf_px
	var pts := PackedVector2Array()
	for i in n:
		var th: float = TAU * float(i) / float(n)
		var r: float = superformula_r(th, m, n1, n2, n3)
		pts.append(Vector2(r * cos(th), r * sin(th)) * scale)
	return pts

## 采样身体边界点 (角色局部坐标, 未旋转)。按 player_body_kind 分派。
## (圆身体用原生 CircleShape2D, 不走这里; 这里给"多边形"身体用)
func player_shape_points(_idx: int = -1) -> PackedVector2Array:
	var pts: PackedVector2Array
	match player_body_kind:
		"polar":
			pts = polar_points(polar_r0, polar_lobes, polar_amp)
		"superformula":
			pts = superformula_points(sf_m, sf_n1, sf_n2, sf_n3, sf_k)
		"sf2":
			pts = superformula_points(2.0, sf_n1, sf_n2, sf_n3, sf_k)
		_:
			pts = spindle_points(player_half_length, player_radius)
	if player_size_scale != 1.0:
		for k in pts.size():
			pts[k] = pts[k] * player_size_scale
	return pts

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
var hit_speed_min: float = 500.0       ## 判定区基本没动时的球速 (要"不大")
var hit_speed_max: float = 700.0       ## 挥到参考速度时的球速
var hit_speed_curve: float = 0.95       ## 力度响应曲线指数 (<1 会更快接近满力)
var hit_zone_speed_ref: float = 200.0   ## 挥动速度(px/s)达到此值 = 满力 (越小越容易到顶)
## vy/弧线 = hit_vz_v0 + (垂直于朝向的分速度 / hit_zone_speed_ref) * 此增益。
## 鼠标向下 -> 垂直分速度为正 -> vy 增大; 鼠标向上 -> vy 减小。结果夹在 [hit_vz_min, hit_vz_max]。
var hit_vz_perp_gain: float = 1000.0

## 方向：基础方向=面向桌中心；叠加"击球区位置 + 挥动方向"的偏置。
var hit_direction_strength: float = 0.5 ## 偏置对方向的影响程度 (0=永远朝桌, 1=完全由挥动决定)
var position_bias_weight: float = 0.1   ## 偏置里"击球区位置"的权重 (其余给挥动速度)

## 智能回球辅助 (0..1 单一旋钮)：1=只要触球就保证回桌；0=完全按玩家击球；中间=部分。
## 原始落点若不在"好区"(桌面内缩 assist_good_margin 像素) 就介入, 把方向拉向"墙的镜像点"。
var assist_strength: float = 0.9        ## 辅助程度 0..1 (方向修正)
var assist_speed_strength: float = 0.6  ## 力度容错 0..1: 只修方向不够时, 把球速也朝"正好落好区"拉一点
var max_assist_angle: float = 180.0     ## 修正角硬上限(度)。180=不限制
var assist_good_margin: float = 50.0    ## 好区=桌面内缩这么多像素。越大越容易触发

## 防守姿态：鼠标向下猛拉(垂直分量 > 阈值) -> vy 很大但水平初速常常不够。
## 此时按 probability "救球"：成功则完全瞄准墙镜像落桌, 失败则用原始方向(大概率丢分)。
var defense_perp_threshold: float = 1000.0   ## 触发防守的垂直分量阈值 (px/s)
## 还必须"垂直分量明显大于水平分量"才算防守: |v_along| < v_perp * 此比例。
## 否则横向力度太大 -> 当作普通横向挥动, 不算防守。
var defense_max_along_ratio: float = 1.2
var defense_save_chance: float = 0.8        ## 防守救球成功概率 0~1
var defense_vz_mult: float = 1.8            ## 防守时 vy 的额外倍数
## 救球成功时: 由 vz 反推水平初速, 让球够到"墙后桌中心的镜像"附近并落桌。
var defense_save_offset: float = 0.1        ## 目标(镜像点)周围的随机偏移半径 (0=正中)
var defense_save_speed_mult: float = 1.0    ## 反推水平初速的微调倍数 (1=刚好够到)

## 扣杀 (smash): 球够高 + 力量够 -> vz 向下(大)、水平速度很大; 仍走"先撞墙再落桌"的正常弹射顺序。
## 因为 z0 高、vz 向下单调下降, 撞墙点早于落桌点 -> 自然先撞墙。
var smash_height_min: float = 130.0      ## 触发扣杀的最低球高
var smash_power_min: float = 0.6         ## 触发扣杀的最低力量 (strength 0..1)
var smash_success_chance: float = 1.0    ## 扣杀成功概率 0~1 (满足条件后能"完整走完墙桌循环"的概率)
var smash_invincible_chance: float = 0.05 ## 扣杀无敌概率 0~1 (成功前提下"对方接不住"的概率)
var smash_fail_skew_deg: float = 65.0    ## 扣杀失败时方向打歪的最大角度(度) -> 更像"失误"
var smash_vz: float = -600.0             ## 扣杀的向下竖直速度 (负值, 越大越快)
var smash_speed_mult: float = 0.8        ## 扣杀水平速度微调 (>1 更凶, 可能过桌)
var ai_smash_height_min: float = 160.0   ## AI 触发扣杀的最低球高 (必须 ≤ hit_height_max=250, 否则永远扣不到)
var smash_hint_enabled: bool = true      ## 球够高且可接时, 在球周围显示"可扣杀"提示

# ============================================================
#  G. 比赛 (计分 / 发球轮换 / 胜负)
# ============================================================
var score_to_win: int = 5               ## 先到这么多分 (且满足 match_win_by 的领先) 获胜
var match_win_by: int = 2               ## 需领先的分数 (净胜2=deuce); 设 1 = 无 deuce (先到即胜)
var serve_change_every: int = 2         ## 每打出这么多分, 发球权轮换一次 (1=每分换)
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
var ai_serve_delay: float = 2.0
## AI 打出球后, 为了避开"阻挡嫌疑"而绕开对手接球走廊的偏移距离
var ai_avoid_distance: float = 90.0
## AI 失误概率 (0~1)。每次击球/发球按此概率触发一次"失误表现" (0=永不失误)。
var ai_error_chance: float = 0.02
var ai_error_aim_deg: float = 40.0     ## 失误表现-瞄偏: 最大偏角(度)
var ai_error_power_min: float = 0.4    ## 失误表现-太轻: 力度缩放
var ai_error_power_max: float = 1.5    ## 失误表现-太重: 力度缩放

## ---- AI 走位 / 防卡死 ----
## 桌/墙是实体碰撞, 但球的可接点在桌正上方 -> 追击目标要投影到桌外(贴桌沿伸判定区够球),
## 否则 AI 会直线怼进桌子卡死。
var ai_hit_reach: float = 44.0          ## 判定区触球半径 (AI 用; = 玩家 hit_reach, 保持平等)
var ai_body_clearance: float = 40.0     ## 目标点必须离(缩过的)桌/边界这么多 (机身半径 + 余量)
var ai_arm_len: float = 36.0            ## AI"手臂": 判定点朝球方向可伸出的最大长度 (能越桌够球)
var ai_min_hit_height: float = 90.0     ## 最低击球高度: 球升到这么高(且已过顶点)才出手 -> 保证有滞空
var ai_arm_speed: float = 500.0         ## 手臂伸/缩的速度上限 (px/s) -> 有连续性, 不瞬伸
var ai_arm_accel: float = 2500.0        ## 手臂伸/缩的加速度上限 (px/s^2)
var ai_personal_space: float = 78.0     ## 与对手保持的"个人空间"; 太近就侧向绕开
var ai_arrive_dist: float = 20.0        ## 到达目标的判定距离 (越大越稳, 减少来回抖)
var ai_target_smooth: float = 0.30      ## 目标平滑系数 (每帧向新目标插值; 1=不平滑)
var ai_avoid_gain: float = 1.2          ## 绕对手的侧向权重
var ai_stuck_velocity: float = 30.0     ## 想动却低于此速度视为"卡住"
var ai_unstick_frames: int = 14         ## 连续卡住这么多帧 -> 触发脱困侧移
var ai_unstick_gain: float = 1.6        ## 脱困侧移权重
var ai_shot_depth_jitter: float = 0.12  ## 击球落点深度抖动 (±比例); 0=完全精确
var ai_shot_band_frac: float = 0.30     ## 高手/大师落点"稳定带": 桌面深度内缩此比例 (避免贴边)
var ai_diverse: bool = true             ## 多样化打法 (F1 菜单 9 开关): 每拍随机选"对角/直线/中路 + 深/浅" (默认开)
var ai_feint_switch_dist: float = 200.0  ## 假动作: 球近至此距离内才切换成真实朝向

## ---- AI 强度 / 等级 (ESC 菜单选择) ----
## 等级 = 一组"能力与技巧": 失误率 / 挑对手对侧落点 / 假动作 / 扣杀。
var ai_level: int = 3

func ai_level_count() -> int:
	return 5

func ai_level_name(i: int = -1) -> String:
	var k: int = ai_level if i < 0 else i
	var names: Array[String] = ["新手", "入门", "普通", "高手", "大师"]
	return names[clampi(k, 0, names.size() - 1)]

## 应用等级 (写入 ai_error_chance)。换档后调用。
func ai_apply_level() -> void:
	var errs: Array[float] = [0.30, 0.15, 0.05, 0.02, 0.0]
	ai_error_chance = errs[clampi(ai_level, 0, errs.size() - 1)]

func ai_smart_aim() -> bool:
	return ai_level >= 2   ## 会挑"对手对侧"落点
func ai_feint() -> bool:
	return ai_level >= 3   ## 会做假动作
func ai_level_smash() -> bool:
	return ai_level >= 3   ## 会用扣杀 (与 F1 8 手动开关取或)

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
var block_require_opponent_in_front: bool = true
## 碰撞持续时间门槛: 至少要接触这么久才算阻挡
var block_min_contact_time: float = 0.2

# ============================================================
#  J. 调试显示开关 (F1 总开关; 打开后按 1~6 分类)
# ============================================================
var debug_show_block: bool = true    ## 2: 阻挡扇区 + 判定因子
var debug_show_aim: bool = true      ## 3: 鼠标瞄准 / 击球调试
var debug_show_ball: bool = true     ## 4: 球状态
var debug_show_shapes: bool = true   ## 5: 碰撞体 / 速度
var debug_show_zones: bool = true    ## 6: 场地 / 桌 / 墙
var debug_show_block_hud: bool = true ## 7: 屏幕上方 阻挡/救球 文字提示
var debug_ai_smash: bool = true       ## 8: AI 也使用扣杀 (默认开, F1 可关)

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

## 桌子对"角色本体"的碰撞矩形 (向内缩 table_player_margin, 让角色可越桌一点)。球弹跳仍用 table_rect。
func table_block_rect() -> Rect2:
	return table_rect().grow(-table_player_margin)
