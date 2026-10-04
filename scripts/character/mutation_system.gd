class_name MutationSystem
extends RefCounted
## P4 · 角色构筑 v1 (最小可验证)：变异候选生成。
##
## 涌现式 + 玩家主动选 + 最小可验证。只变异"形状类别 + 整体大小"。
## 每拍候选互有取舍 (大=够球/阻挡覆盖大, 但移动慢、转身难 -> 见 GameConfig.size_*_exponent)。
## 禁止：AI 战斗力评分 / 胜率排行 / "推荐最佳"。这里只"生成候选 + 应用选择", 不做任何评价。

## 生成 n 个候选 (第 0 个永远是"保留当前")。每个候选 = {shape_index, size_scale, name}。
static func generate(n: int = -1) -> Array:
	var count: int = GameConfig.mutation_candidates if n < 0 else n
	count = maxi(count, 2)
	var out: Array = []
	out.append(make(GameConfig.player_shape_index, GameConfig.player_size_scale, "保留当前"))
	for i in range(1, count):
		var si: int = randi() % maxi(GameConfig.player_shape_count(), 1)
		var ss: float = clampf(
			GameConfig.player_size_scale + randf_range(-GameConfig.mutation_size_delta, GameConfig.mutation_size_delta),
			GameConfig.mutation_size_min, GameConfig.mutation_size_max)
		out.append(make(si, ss, "候选 %d" % i))
	return out

static func make(shape_index: int, size_scale: float, label: String) -> Dictionary:
	return {"shape_index": shape_index, "size_scale": size_scale, "name": label}

## 候选的可读描述 (形状名 + 大小 + 代价提示)。
static func describe(c: Dictionary) -> String:
	var si: int = int(c.get("shape_index", 0))
	var ss: float = float(c.get("size_scale", 1.0))
	return "%s  大小 %.2f" % [GameConfig.player_shape_name(si), ss]

## 应用候选到"当前身体"。
static func apply(c: Dictionary) -> void:
	GameConfig.player_shape_index = int(c.get("shape_index", 0))
	GameConfig.player_size_scale = float(c.get("size_scale", 1.0))
