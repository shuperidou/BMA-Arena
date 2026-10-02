# 竞技场：阻挡个屁 (Arena: Block My Ass)

俯视角 2D、物理驱动、休闲竞技的桌墙球原型。当前处于 **阶段 0 + 阶段 1**：
工程基础 + 最小可玩比赛（含阻挡判定、圆形 AI、智能回球、伪 Z 高度、调试菜单）。

> 设计总纲在 `历史对话文件\PROJECT_CONTEXT.txt`（桌面）。
> 所有可调数值集中在 `scripts/autoload/game_config.gd`，按 A–M 分区。

---

## 运行

需要 Godot 4.7。本机：`D:\Godot\Godot_v4.7-stable_win64.exe`

```powershell
& "D:\Godot\Godot_v4.7-stable_win64.exe" --path "D:\Godot\Games\ArenaBlock" -e   # 编辑器
& "D:\Godot\Godot_v4.7-stable_win64.exe" --path "D:\Godot\Games\ArenaBlock"      # 直接玩
```

### 操作

| | 移动 | 朝向 | 发球 |
|--|--|--|--|
| 玩家1(你) | W A S D (世界坐标) | 鼠标按住拖动 | 空格 |
| 玩家2 | 圆形 AI，自动跑动 / 发球 / 击球 | | |

- 其他：`F1` 调试菜单、`R` 重开、`Esc` 退出。
- `F1` 打开后，菜单里按键分类开关：`1` 单人(玩家2消失,自己发接) / `2` 阻挡扇区+因子 /
  `3` 鼠标击球 / `4` 球状态 / `5` 碰撞体 / `6` 场地桌墙。

### 玩家1 控制模型（重要）

平移与朝向**解耦**，朝向由鼠标拖动决定：

```
WASD -> 世界坐标移动 (与 rotation 无关)
按住鼠标 -> 记录锚点; 水平拖动:
   击球区A局部位移 = +鼠标拖动向量, B = -鼠标拖动向量   (不做 world->local 转换)
   身体同时做"有限小幅旋转" (drag_rot_max)
松开 -> 击球区回位; 身体回正到"面向桌中心"
```

- 移动永远世界坐标（绝不 `transform.basis * input`）。
- 鼠标拖动向量**原样**作为击球区**局部**位移；由身体 rotation 决定最终世界方向。
- 已删除 Q/E；`base_face_*` 强回正到面向桌中心。

### 击球系统（`scripts/match/hit_system.gd`）

```
力度 = 曲线(击球区世界速度 / hit_zone_speed_ref) -> 映射到 [hit_speed_min, hit_speed_max]
方向 = 面向桌中心 + (击球区位置 + 挥动) * hit_direction_strength
辅助 = 原始落点不在"好区"时, 把方向拉向"桌中心关于墙的镜像点" (assist_strength 0..1)
```

- **辅助和 AI 一致**：瞄准墙的镜像，让球直接撞墙(回击不先弹桌)、撞墙后水平路径过桌心。
- `hit_speed_v0 / hit_vz_v0 / hit_vz_min / hit_vz_max` = 击出瞬间(初速度)相关参数。
- 反馈：击球闪光 + 力度颜色(弱蓝↔强红) + 扩散环 + 拖尾。

### 球：伪 Z 高度

俯视 XY + 独立 `height_z`。`GROUND_Z=ground_z`，`TABLE_Z=table_z`。
桌弹=下降且高度穿过 `table_z` 且 XY 在桌面内；`height_z<=ground_z` 落地。
视觉：高度越高球越大 + 影子越远；**视觉缩放不改逻辑半径**。

### AI（`scripts/player/ai_player.gd`）

- 圆形刚体 + 中心一个击球判定区（不用纺锤/两端）。
- 追"球的可接住点"；球不在场时原地待命。
- 击球/发球瞄准"桌面上随机 x 关于墙的镜像点"，力度/vz 与玩家同区间。
- **防阻挡模式**：自己打完球后绕开"对手→接球点"走廊。
- **失误系数** `ai_error_chance`(0~1)：按概率触发不同失误表现（瞄偏 / 太轻 / 太重 / 打反）。

### 规则（文档 77–99 行）

- **发球**：从发球位发出；撞墙前碰不碰桌无所谓。
- **回击**：撞墙前**不能先碰桌**，否则回击方输（必须先到墙，再落桌）。
- **球在桌上连续弹第 2 次** → 接球方输（击球方得分）。
- 墙后落过桌但接球方没接到、球落地 → 击球方得分；只撞墙没落桌 → 接球方得分。
- 同一面连弹 2 次 → 直接结算。
- 阻挡成立(扇区+碰撞+接触时长) → 若接球方因此没接到 → 重发(被阻挡方发球)；击球方自己失误不算阻挡。
- 计分/发球轮换是临时方案 [TEMP]，一局 5 分。

### 阻挡判定（扇区模型，`scripts/match/block_system.gd`）

```
1) 接球方必须有移动意图 (速度 >= block_pursuit_speed), 静止不算
2) 球在"速度扇区"内: 轴=接球方速度方向, 半角 block_sector_half_angle, 半径 block_sector_radius
3) 实际碰撞 + 接触时长 >= block_min_contact_time  -> CONFIRMED
   仅满足 2) -> POSSIBLE(提示)
可选门槛(默认关): block_require_time_reachable / block_require_opponent_in_front
```

### 调试（`F1`）

分类显示：阻挡扇区+判定三因子（意图/扇区/接触）、鼠标击球、球状态、碰撞体、场地。
菜单会显示各项开/关。

> 设计说明：空间提示（接球点 / 阻挡扇区 / 危险区）**按当前设计只在 `F1` 里显示**，不再常驻。
> （文档第一阶段曾设想"接球阶段始终可见"，后由设计者改为"调试菜单内查看"。）

---

## 目录结构

```
ArenaBlock/
  project.godot  icon.svg
  scenes/   Main.tscn  RallyTest.tscn  ControlTest.tscn  HitTest.tscn  SoloTest.tscn  AiTest.tscn  BlockTest.tscn
  scripts/
    autoload/  game_config.gd  event_bus.gd
    core/      game_types.gd  main.gd
    arena/     arena.gd
    ball/      ball.gd
    player/    player_controller.gd  ai_player.gd  hit_point.gd  input_scheme.gd
    match/     match.gd  hit_system.gd  block_system.gd
    ui/        hud.gd  debug_layer.gd
    tools/     rally_test.gd  control_test.gd  hit_test.gd  solo_test.gd  ai_test.gd  block_test.gd
```

## 系统结构

- **Match**：状态机 SERVE→RALLY→(POINT|INTERFERENCE)、发球、球死判分、延迟阻挡重发。
- **Ball**：xy 运动 + 独立高度 z、桌弹/墙弹(墙弹回桌辅助)、球死、击球反馈。
- **PlayerController**：整体刚体纺锤/键盘无关；移动世界坐标、鼠标拖动击球区、强回正。
- **AiPlayer**（继承 PlayerController）：圆形、自主跑动/智能击球/失误表现/防阻挡。
- **HitSystem**：力度曲线 + 方向偏置 + 墙镜像辅助（玩家与 AI 用同一套思路）。
- **BlockSystem**：扇区 + 碰撞 + 接触时长 → NONE/POSSIBLE/CONFIRMED。
- **GameConfig**：唯一数值来源（A–M 分区）。

## 无头测试（开发用）

```powershell
$g = "D:\Godot\Godot_v4.7-stable_win64_console.exe"
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/HitTest.tscn      # 击球系统
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/ControlTest.tscn  # 控制解耦
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/BlockTest.tscn    # 阻挡扇区
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/RallyTest.tscn    # 对拉/计分
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/AiTest.tscn       # AI 发球
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/SoloTest.tscn     # 单人调试
```

## 当前问题 / 下一页

1. **手感/数值未真人验证**：力度区间（`hit_speed_min/max`）与 `hit_vz_*`、`move_speed` 需要试玩收敛，否则常常落不了桌。
2. 人类发球(沿朝向) 与 AI 发球(智能) 不对称，待统一。
3. 阻挡 POSSIBLE 可能偏频繁地亮红。
4. 计分/发球轮换仍是 TEMP。
5. "阻挡个屁"争论玩法未做（文档说后期）。

## 下一阶段

先真人试玩，回答核心问题：**纺锤刚体在桌墙之间追球、旋转、撞人，是否已经好玩？**
好玩再往：武器/装备、变异、AI 试战、进化树推进。不好玩先改核心手感。
