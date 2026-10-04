class_name MutationSystem
extends RefCounted
## P4 · 角色构筑 v1：变异候选生成。
##
## 候选 = **一整具身体** = { kind 身体种类, size_scale 大小, 以及该身体自己的参数 }。
## 大多数候选沿用当前身体调参; 偶尔**换一种身体种类** (spindle/circle/polar)。
## 每拍候选互有取舍 (大=够球/阻挡覆盖大, 但移动慢、转身难 -> GameConfig.size_*_exponent)。
## 禁止：AI 战斗力评分 / 胜率排行 / "推荐最佳"。只生成+应用, 不做任何评价。

## 生成 n 个候选 (第 0 个永远是"保留当前")。
static func generate(n: int = -1) -> Array:
	var count: int = GameConfig.mutation_candidates if n < 0 else n
	count = maxi(count, 2)
	var out: Array = []
	out.append(_current("保留当前"))
	for i in range(1, count):
		out.append(_mutated_candidate(i))
	return out

## 当前身体的快照 (作为候选基准)。
static func _current(label: String) -> Dictionary:
	return {
		"kind": GameConfig.player_body_kind,
		"size_scale": GameConfig.player_size_scale,
		"half_len": GameConfig.player_half_length,
		"radius": GameConfig.player_radius,
		"circle_radius": GameConfig.circle_body_radius,
		"polar_r0": GameConfig.polar_r0,
		"polar_lobes": GameConfig.polar_lobes,
		"polar_amp": GameConfig.polar_amp,
		"name": label,
	}

## 一个变异候选: 偶尔换身体种类, 再抖大小 + 抖该身体的参数。
static func _mutated_candidate(i: int) -> Dictionary:
	var c: Dictionary = _current("变异 %d" % i)
	if randf() < GameConfig.mutation_kind_chance:
		var kinds: Array = GameConfig.BODY_KINDS
		c["kind"] = kinds[randi() % kinds.size()]
	c["size_scale"] = clampf(
		GameConfig.player_size_scale + randf_range(-GameConfig.mutation_size_delta, GameConfig.mutation_size_delta),
		GameConfig.mutation_size_min, GameConfig.mutation_size_max)
	match String(c["kind"]):
		"circle":
			c["circle_radius"] = clampf(GameConfig.circle_body_radius + randf_range(-4.0, 4.0), 10.0, 40.0)
		"polar":
			c["polar_r0"] = clampf(GameConfig.polar_r0 + randf_range(-7.0, 7.0), 14.0, 44.0)
			c["polar_lobes"] = clampi(GameConfig.polar_lobes + randi_range(-1, 1), 2, 8)
			c["polar_amp"] = clampf(GameConfig.polar_amp + randf_range(-0.15, 0.15), 0.0, 0.85)
		_:
			c["half_len"] = clampf(
				GameConfig.player_half_length + randf_range(-GameConfig.mutation_len_delta, GameConfig.mutation_len_delta),
				GameConfig.mutation_len_min, GameConfig.mutation_len_max)
			c["radius"] = clampf(
				GameConfig.player_radius + randf_range(-GameConfig.mutation_wid_delta, GameConfig.mutation_wid_delta),
				GameConfig.mutation_wid_min, GameConfig.mutation_wid_max)
	return c

## 候选的可读描述。
static func describe(c: Dictionary) -> String:
	var kind: String = String(c.get("kind", "spindle"))
	var s: String = "%s · 大小%.2f" % [GameConfig.body_kind_label(kind), float(c.get("size_scale", 1.0))]
	match kind:
		"circle":
			s += " · 半径%.0f" % float(c.get("circle_radius", 20.0))
		"polar":
			s += " · r%.0f 花%d 深%.2f" % [
				float(c.get("polar_r0", 26.0)), int(c.get("polar_lobes", 4)), float(c.get("polar_amp", 0.45))]
		_:
			s += " · 长%.0f 宽%.0f" % [float(c.get("half_len", 90.0)), float(c.get("radius", 14.0))]
	return s

## 应用候选到"当前身体"。
static func apply(c: Dictionary) -> void:
	GameConfig.player_body_kind = String(c.get("kind", "spindle"))
	GameConfig.player_size_scale = float(c.get("size_scale", 1.0))
	if c.has("half_len"):
		GameConfig.player_half_length = float(c["half_len"])
	if c.has("radius"):
		GameConfig.player_radius = float(c["radius"])
	if c.has("circle_radius"):
		GameConfig.circle_body_radius = float(c["circle_radius"])
	if c.has("polar_r0"):
		GameConfig.polar_r0 = float(c["polar_r0"])
	if c.has("polar_lobes"):
		GameConfig.polar_lobes = int(c["polar_lobes"])
	if c.has("polar_amp"):
		GameConfig.polar_amp = float(c["polar_amp"])
