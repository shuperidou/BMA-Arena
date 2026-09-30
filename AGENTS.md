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
- 球的**视觉缩放只影响 _draw**，绝不改 `radius`（逻辑碰撞半径固定）。比赛逻辑读 `state`/`height_state`，不读视觉。
- 输入用 physical keycode 轮询，没有用 InputMap。
- **控制模型：平移与旋转严格解耦。** 移动永远是世界坐标（绝不用 `transform.basis * input`）。
- 朝向 = 基础"面向桌中心"(`GameConfig.table_center`)，带惯性维持；**不再追随球**。
- 鼠标横向拖动（锚点方案，只用 `mouse_drag.x`，屏幕像素）先归一化 `normalized = clamp(|dx|*mouse_drag_sensitivity,0..1)`，再用两条**独立、非线性**曲线分配：① 击球区反向位移（ease-out，到 `hit_zone_drag_threshold` 满偏，`hit_zone_max_offset`；松开按 `hit_zone_return_speed` 平滑回位）；② 身体相对桌中心方向偏转（`rotation_drag_start` 前只有 `rotation_early_max`，之后 ramp 到 1，`rotation_max_offset`）。**不累积角度**，不按球/角色位置重解释左右。改控制时不要引入"角色前后左右"、"绝对鼠标瞄准"或"自动朝球"的耦合。
