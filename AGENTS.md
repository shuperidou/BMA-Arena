# AGENTS.md — 工程约定

Godot 4.7 项目，GDScript，俯视角 2D。设计总纲在 `桌面\历史对话文件\PROJECT_CONTEXT.txt`。

## 命令

```powershell
$g = "D:\Godot\Godot_v4.7-stable_win64_console.exe"
& $g --headless --path "D:\Godot\Games\ArenaBlock" --import          # 导入/查解析错误
& $g --headless --path "D:\Godot\Games\ArenaBlock" --quit-after 600  # 跑主场景抓运行错误

# 无头测试
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/HitTest.tscn      # 击球系统
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/ControlTest.tscn  # 控制解耦
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/BlockTest.tscn    # 阻挡扇区
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/RallyTest.tscn    # 对拉/计分
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/AiTest.tscn       # AI 发球
& $g --headless --path "D:\Godot\Games\ArenaBlock" res://scenes/SoloTest.tscn     # 单人调试
```

没有独立 lint/typecheck；用 `--import` + `--headless` 运行暴露解析/运行错误。

## 约定

- **所有可调数值只能放在 `scripts/autoload/game_config.gd`**（按 A–M 分区）。不要写魔法数字。
- 规则逻辑放 `Match`/`BlockSystem`/`HitSystem`；物理表现放 `Ball`/`PlayerController`/`AiPlayer`。
- 场景用**代码组装**（`main.gd`），几何来自 GameConfig。
- 中文 UI 用 `GameConfig.ui_font()`。
- 不要为了"看起来完整"提前加装备/技能/经济（设计文档第 35 节）。
- 提交前至少跑 `--import` + 无头运行 + 相关测试，确认无 ERROR。
- **改 `game_config.gd` 前先确认用户没在 Godot 编辑器里开着它**（编辑器保存会覆盖）。

## 已知结构

- 碰撞层：`1`=玩家，`2`=场地；球不用物理层（自定义 z 物理）。
- 球：俯视 XY + 独立高度 `height_z`。`GROUND_Z=ground_z`，`TABLE_Z=table_z`（不要假定 0）。
  桌弹=下降且穿过 `table_z` 且 XY 在桌面内；`height_z<=ground_z` 落地。视觉缩放只改 `_draw`，不改 `radius`。
  球只在 `state==LIVE` 时显示。
- **击球初速度**：`hit_speed_v0`（水平）/`hit_vz_v0`（垂直）/`hit_vz_min|max`（允许区间）。
- **发球 vs 回击**：发球撞墙前碰不碰桌无所谓；**回击撞墙前不能先碰桌**（先弹桌=回击方输）。
- 同面（桌或墙）连续弹两次 → 直接结算。
- 玩家1：WASD 世界移动 + 鼠标按住拖动控制两个击球区（局部位移=鼠标拖动向量原值，**不做 world->local 转换**）；
  `base_face_*` 强回正到面朝桌中心；拖动时 `drag_rot_*` 做有限小幅旋转。鼠标不改 rotation。
- 玩家2：`AiPlayer`（圆形，单判定区）。追 `Ball.predict_catchable()`；瞄准"桌面随机 x 的墙镜像点"；
  击完球切"防阻挡模式"绕开对手走廊；`ai_error_chance`(0~1) 触发失误表现。
- 阻挡（扇区）：接球方须移动(> `block_pursuit_speed`) + 球在"速度方向扇区"内 + 实际碰撞 + 接触 ≥ `block_min_contact_time`。
  仅当"接球方因此没接到"(正常判给击球方) 才重发；击球方自己失误不因阻挡改判。
- 战斗/比赛逻辑读球的 `state`/`height_state`/`table_bounces`/`receiver_bounces`/`returnable`，不读视觉。
- 单人调试：`Match.solo_mode` + `Main._toggle_solo()`（F1 后按 `1`）。隐藏/冻结玩家2、自己发接、不计分。
- 调试分类开关：`GameConfig.debug_show_*`，F1 总开关 + 数字键 1~6。
- 输入用 physical keycode 轮询，没有用 InputMap。
