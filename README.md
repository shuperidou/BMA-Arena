# 竞技场：阻挡个屁 (Arena: Block My Ass)

俯视角 2D、物理驱动、休闲竞技的桌墙球原型。
当前处于 **阶段 0 + 阶段 1**：工程基础 + 最小可玩比赛（含第一版阻挡）。

> 设计总纲见 `C:\Users\shupe\Desktop\PROJECT_CONTEXT.txt`。
> 一切"为了试玩而临时定"的数值都在 `scripts/autoload/game_config.gd` 里，标了 `[TEMP]` / `[TUNED]`。

---

## 运行

需要 Godot 4.7。本机路径：`D:\Godot\Godot_v4.7-stable_win64.exe`

```powershell
# 用编辑器打开
& "D:\Godot\Godot_v4.7-stable_win64.exe" --path "D:\Godot\Games\ArenaBlock" -e

# 直接运行
& "D:\Godot\Godot_v4.7-stable_win64.exe" --path "D:\Godot\Games\ArenaBlock"
```

### 操作

| | 移动 | 朝向 | 发球 |
|--|--|--|--|
| 玩家1 | W A S D (世界坐标) | 鼠标 | 空格 |
| 玩家2 | 方向键 (世界坐标) | , / . (仅测试用) | 回车 |

其他：`F1` 调试显示开关，`F2` 空间提示开关，`R` 重开比赛，`Esc` 退出。

### 控制模型（重要）

拳击式控制：WASD 移动身体，鼠标横向拖动调整两个击球区与身体姿态。

```
WASD   -> 世界坐标移动 (与朝向无关)
基础朝向 -> 面向桌中心 (angle(char -> table_center))，带惯性维持
按住鼠标 -> 建立锚点; 水平拖动 drag.x:
   ├─ 两个击球区沿身体长轴反向位移 (一伸一缩)  [hit_zone_sensitivity, max_hit_zone_offset]
   └─ 身体相对"面向桌中心"小幅偏转             [rotation_sensitivity, max_rotation_offset]
松开鼠标 -> 击球区回位 + 身体回到面向桌中心 (平滑，不瞬跳)
```

- WASD 永远对应屏幕上/下/左/右，角色朝哪都一样。
- **朝向不再追随球**；球只影响球自己。基础姿态 = 面向桌中心。
- 朝向**不累积**：`target = base + sign(drag.x) * clamp(|drag.x|*rot_sens, 0, max_rotation_offset)`；鼠标回锚点即回桌中心方向。
- 固定左右映射（不随球/角色位置重解释）。鼠标 Y 轴不参与。
- 参数：`hit_zone_sensitivity` / `max_hit_zone_offset` / `hit_zone_return_speed` / `rotation_sensitivity` / `max_rotation_offset` / `mouse_drag_deadzone` / `rotation_response` / `max_angular_velocity` / `rotation_acceleration` / `rotation_damping` / `aim_mouse_button`。
- 已删除 Q/E，无绝对瞄准/投影/自动朝球/角度累计。玩家2 的键盘朝向只是本地双人测试的临时方案 [TEMP]。
- `F1` 调试画出：桌中心、基础朝向(灰) / 目标朝向(品红) / 当前朝向(绿)、两个击球区的默认位置(空心)与当前偏移位置(实心)、锚点、当前鼠标，并显示 `base/target/rot/limit/zone/drag/dx`。

### 无头自动对拉测试（开发用）

```powershell
& "D:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/RallyTest.tscn
```

会让"当前接球方"自动瞬移接球 4 秒，然后故意离开，验证 `发球 -> 桌 -> 墙 -> 桌 -> 回击` 循环与计分。

### 无头控制测试（开发用）

```powershell
& "D:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/ControlTest.tscn
```

自动验证：朝下按 W 仍向世界上移动、朝上按 D 仍向世界右移动、移动与旋转互不干扰、旋转是渐进而非瞬移。

---

## 目录结构

```
ArenaBlock/
  project.godot
  icon.svg
  scenes/
    Main.tscn            # 入口场景（根节点只挂 main.gd，其余代码组装）
    RallyTest.tscn       # 无头自动对拉测试
  scripts/
    autoload/
      game_config.gd     # 所有可调参数（几何/物理/阻挡/比赛/输入）
      event_bus.gd       # 全局信号（UI 通知等）
    core/
      game_types.gd      # 共享枚举
      main.gd            # 代码组装整个场景 + 全局按键
    arena/
      arena.gd           # 场地：墙/桌/边界，画灰盒 + 静态碰撞体
    ball/
      ball.gd            # 球：俯视投影 + 高度 z 的 2.5D 物理、弹跳、球死
    player/
      player_controller.gd  # 整体刚体纺锤 + 移动/旋转控制
      hit_point.gd          # 两端击球点
      input_scheme.gd       # 键位轮询
    match/
      match.gd           # 比赛状态机、发球、计分、重发
      block_system.gd    # 独立阻挡判定系统
    ui/
      hud.gd             # 比分/状态/消息
      debug_layer.gd     # 调试 + 空间提示（预计接球点/危险走廊）
    tools/
      rally_test.gd      # 自动对拉测试脚本
```

---

## 系统结构（职责分离）

- **Match**：当前比赛阶段、发球、球死、胜负、阻挡重发。只做规则，不碰物理细节。
- **Ball**：位置、速度、桌面/墙面弹跳、当前球路状态。通过信号上报 `table_bounced / wall_bounced / died`。
- **PlayerController**：身体物理、移动、旋转、击球点接触。规则不写在这里。
- **BlockSystem**：预计接球点、路线走廊、阻挡状态（NONE/POSSIBLE/CONFIRMED）。
- **Arena**：几何与静态碰撞体，全部来自 GameConfig。
- **GameConfig**：唯一数值来源。

---

## 已实现功能

- 墙 + 课桌 + 活动区域（灰盒，含桌墙缝隙）
- 两个纺锤形刚体，可移动、可旋转，两端各一击球点，彼此可碰撞
- 球：桌面弹跳、墙面弹跳、落地/出界判死
- 发球 → 对拉 → 球死 → 得分 → 重开 的完整循环
- 第一版阻挡：预计接球点 + 危险走廊可视化 + 碰撞窗口判定 + 阻挡后由被阻挡方重发
- Debug：球状态/速度/高度/弹跳计数、碰撞体轮廓、速度向量、接球点

---

## 球的伪 Z 轴（高度）系统

2D 俯视 + 一个独立高度变量，不改成 3D。

```
position (x,y) = 场地水平位置       vel = 水平速度
height_z       = 距地面高度         vz  = 垂直速度
radius         = 逻辑碰撞半径(固定)  state/height_state = 逻辑状态
```

- `GROUND_Z = GameConfig.ground_z`（落地 → 球死）；`TABLE_Z = GameConfig.table_z`（独立，可改）。
- 桌弹同时看 XY 与 Z：**下降中 + 高度穿过 TABLE_Z + XY 在桌面内** 才弹。
- 墙：XY 反弹，且 `height_z <= wall_max_height`（预留，超了就飞过墙）。
- 可击球高度范围：`hit_height_min` / `hit_height_max`（第一阶段宽松）。
- 击球是否有效由 `Match` 读 **逻辑状态** 判断，绝不靠视觉。

视觉只做可读性，且**不改变逻辑半径**：

- 高度越高 → 球显示越大：`visual_scale = clamp(base_ball_scale * (1 + height_scale_factor * z/TABLE_Z), min_visual_scale, max_visual_scale)`。
- 影子固定在 XY、大小固定；球相对影子向上偏移 `z * shadow_offset_factor`，高度越高两者越远。
- 参数：`base_ball_scale` / `height_scale_factor` / `min_visual_scale` / `max_visual_scale` / `shadow_offset_factor` / `shadow_scale`。

## 临时设计（TEMP，等试玩后再改）

| 项 | 当前临时方案 | 位置 |
|--|--|--|
| 比分规则 | 落地/球死后按"撞墙且落桌→击球方得分，否则击球方失误" | `match.gd: _decide_winner` |
| 发球轮换 | 每分简单交替 | `match.gd: _award_point` |
| 胜负分 | 5 分 | `GameConfig.score_to_win` |
| 球墙回弹 | **辅助回弹**：墙弹后主动算一个落点，避免球总掉进桌墙缝隙（游戏化处理） | `GameConfig.wall_return_assist` + `ball.gd: _apply_wall_return_assist` |
| 回击许可 | 只有"预计接球方"且球已满足"墙后落桌"时可回击 | `match.gd: _on_ball_touched` |
| 接球方桌弹上限 | 2 | `GameConfig.receiver_bounce_limit` |
| 阻挡阈值/窗口 | 全部拍脑袋值 | `GameConfig` 阻挡区 |
| 分辨率/镜头 | 1280×720 固定，看全场 | `project.godot` / `main.gd` |

---

## 当前问题 / 待验证

1. **阻挡系统没有自动化验证**，阈值（走廊宽度、追球判断、碰撞窗口）纯靠试玩调。
2. 球在发球瞬间会落进发球方击球点的触及范围内（被规则忽略，但观感一般）。
3. 接球方必须等球回落到近边附近回击才不失误（深度判断），"回击过早"目前只是被忽略而不是判失误，规则语义可以再明确。
4. 球的墙弹用了辅助回弹，**手感偏"程序化"**，可能需要更物理的版本或加随机性。
5. 手感（移动/旋转/球速）未经过真人试玩，数值都在 `[TUNED]`，大概率要调。
6. 角色是 180px 长的纺锤，和桌子比例偏大——是为了让两端能覆盖桌面，之后可重新权衡。

---

## 下一阶段建议

先真人试玩，重点回答："**一个纺锤刚体在桌墙之间追球、旋转、撞人，是否已经好玩？**"

- 若**手感生硬**：优先调 `GameConfig` 的角色移动/旋转与球速、恢复系数。
- 若**球路无聊**：调 `wall_return_assist`（关掉看看纯物理）和桌面尺寸/缝隙。
- 若**阻挡判定不准**：只调 BlockSystem 的阈值，不动其他系统。
- 核心好玩后再进入阶段 2 的"反复试玩调规则"，再往阶段 3（简单 AI）。
