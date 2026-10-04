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
	# 最多 1 个"换形状类别", 其余都是"同类别·改大小" (不做一堆推倒重来的选项)
	var n_change: int = 1 if count >= 3 else 0
	var n_same: int = count - 1 - n_change
	for i in n_same:
		out.append(make(GameConfig.player_shape_index, _rand_size(), "同形·变异"))
	for i in n_change:
		out.append(make(_rand_other_shape(), _rand_size(), "换形"))
	return out

static func _rand_size() -> float:
	return clampf(
		GameConfig.player_size_scale + randf_range(-GameConfig.mutation_size_delta, GameConfig.mutation_size_delta),
		GameConfig.mutation_size_min, GameConfig.mutation_size_max)

## 换一个"别的"形状类别 (排除当前)。
static func _rand_other_shape() -> int:
	var n: int = GameConfig.player_shape_count()
	if n <= 1:
		return 0
	var si: int = randi() % (n - 1)
	if si >= GameConfig.player_shape_index:
		si += 1
	return si

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
