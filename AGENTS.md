# AGENTS.md — 工程约定

Godot 4.7 项目，GDScript，俯视角 2D。设计总纲在 `C:\Users\shupe\Desktop\PROJECT_CONTEXT.txt`。

## 命令

```powershell
# 导入资源 / 检查脚本
& "D:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Godot\Games\ArenaBlock" --import

# 无头跑主场景（抓运行时错误）
& "D:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Godot\Games\ArenaBlock" --quit-after 600

# 自动对拉测试（验证发球/弹跳/计分）
& "D:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/RallyTest.tscn

# 控制模型测试（世界移动/解耦/旋转惯性）
& "D:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/ControlTest.tscn

# 击球系统测试（力度曲线/方向/智能辅助）
& "D:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/HitTest.tscn

# 单人调试模式冒烟测试
& "D:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/SoloTest.tscn

# 编辑器
& "D:\Godot\Godot_v4.7-stable_win64.exe" --path "D:\Godot\Games\ArenaBlock" -e
```

没有独立 lint/typecheck；用 `--import` 和 `--headless` 运行来暴露解析/运行错误。

## 约定

- **所有可调数值只能放在 `scripts/autoload/game_config.gd`**。不要在角色/球/比赛脚本里写魔法数字。
  临时值标 `[TEMP]`，数值模拟得来的标 `[TUNED]`。
- 规则逻辑放 `Match` / `BlockSystem`；物理表现放 `Ball` / `PlayerController`。不要互相渗。
- 场景用**代码组装**（`main.gd`），几何来自 GameConfig。新增可视对象优先代码创建，保持数据驱动。
- 中文 UI 必须用 `GameConfig.ui_font()`（系统字体），Godot 默认字体不含中文。
- 不要为了"看起来完整"提前加入装备/技能/经济/复杂 AI（见设计文档第 35 节）。
- 提交前至少跑一次 `--import` + 无头运行，确认无 ERROR。

## 已知结构

- 碰撞层：`1` = 玩家，`2` = 场地（墙/桌/边界）。球不使用物理层（自定义 z 物理）。
- 球模型：俯视 XY + 独立高度 `height_z`（距地面）。`GROUND_Z=ground_z`，`TABLE_Z=table_z`（独立，不要假定为 0）。桌弹=下降且高度穿过 `table_z` 且 XY 在桌面内；`height_z<=ground_z` 落地。
- 球的**视觉缩放只影响 _draw**，绝不改 `radius`（逻辑碰撞半径固定）。比赛逻辑读 `state`/`height_state`，不读视觉。球只在 `state==LIVE` 时显示（发球前不可见）。
- 发球（全局）：从发球方 `global_position`、沿其朝向 `Vector2.RIGHT.rotated(rotation)`（局部 +x = 面向桌中心方向）以 `ball_hit_speed`/`ball_hit_vz` 发出。
- 单人调试：`Match.solo_mode` + `Main._toggle_solo()`（F1 打开调试后按 `1`）。开启后玩家2 隐藏/冻结/关闭碰撞，`_other()` 返回自己（自己发自己接），不计分、不判阻挡、不重置位置。
- 输入用 physical keycode 轮询，没有用 InputMap。
- **控制模型：平移与旋转严格解耦。** 移动永远是世界坐标（绝不用 `transform.basis * input`）。
- 朝向：**强回正到"面向桌中心"**（`base_face_enabled`/`base_face_response`/`base_face_max_angular_velocity`/`base_face_acceleration`，默认较强较快），撞歪后由物理短暂影响、随即快速拉回；不硬锁死。球不影响朝向。
- 鼠标（锚点方案）：`mouse_delta = 当前鼠标 - 锚点`（屏幕/视口 2D 向量）。**把它数值原样当作击球区的局部坐标系位移，绝不做 world->local 转换**（故意让角色 rotation 影响击球区最终世界方向）。A=(0,-L)+delta，B=(0,+L)-delta（反向），`|delta|<=hit_zone_max_offset`。松开按 `hit_zone_return_speed` 平滑回位。鼠标**不修改 rotation**。改控制时不要引入 `transform.basis*input`、世界→局部转换、绝对鼠标瞄准或自动朝球。
