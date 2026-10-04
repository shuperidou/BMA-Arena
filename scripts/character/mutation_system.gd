class_name MutationSystem
extends RefCounted
## P4 · 角色构筑 v1 (最小可验证)：变异候选生成。
##
## 只变异"纺锤"这一种身体: 大小 + 形状方程参数(长半/宽半)。**不做"换形状类别"**
## (其它身体以后各自设计判定方式, 见 GameConfig.player_body_kind)。
## 每拍候选互有取舍 (大=够球/阻挡覆盖大, 但移动慢、转身难 -> GameConfig.size_*_exponent)。
## 禁止：AI 战斗力评分 / 胜率排行 / "推荐最佳"。只生成+应用, 不做任何评价。

## 生成 n 个候选 (第 0 个永远是"保留当前")。
## 每个候选 = {half_len, radius, size_scale, name}。
static func generate(n: int = -1) -> Array:
	var count: int = GameConfig.mutation_candidates if n < 0 else n
	count = maxi(count, 2)
	var out: Array = []
	out.append(make(GameConfig.player_half_length, GameConfig.player_radius,
		GameConfig.player_size_scale, "保留当前"))
	for i in range(1, count):
		var L: float = clampf(
			GameConfig.player_half_length + randf_range(-GameConfig.mutation_len_delta, GameConfig.mutation_len_delta),
			GameConfig.mutation_len_min, GameConfig.mutation_len_max)
		var r: float = clampf(
			GameConfig.player_radius + randf_range(-GameConfig.mutation_wid_delta, GameConfig.mutation_wid_delta),
			GameConfig.mutation_wid_min, GameConfig.mutation_wid_max)
		var ss: float = clampf(
			GameConfig.player_size_scale + randf_range(-GameConfig.mutation_size_delta, GameConfig.mutation_size_delta),
			GameConfig.mutation_size_min, GameConfig.mutation_size_max)
		out.append(make(L, r, ss, "变异 %d" % i))
	return out

static func make(half_len: float, radius: float, size_scale: float, label: String) -> Dictionary:
	return {"half_len": half_len, "radius": radius, "size_scale": size_scale, "name": label}

## 候选的可读描述 (长半 / 宽半 / 大小)。
static func describe(c: Dictionary) -> String:
	return "长 %.0f · 宽 %.0f · 大小 %.2f" % [
		float(c.get("half_len", 90.0)), float(c.get("radius", 14.0)), float(c.get("size_scale", 1.0))]

## 应用候选到"当前身体" (纺锤)。
static func apply(c: Dictionary) -> void:
	GameConfig.player_half_length = float(c.get("half_len", 90.0))
	GameConfig.player_radius = float(c.get("radius", 14.0))
	GameConfig.player_size_scale = float(c.get("size_scale", 1.0))
	GameConfig.player_body_kind = "spindle"
