class_name AiGenome
extends RefCounted
## ② AI 自进化 · 行为基因 (决定"风格")。
##
## 一组可变异/可选择/可导出导入的参数。AI 用它们驱动行为 → 不同基因 = 不同风格。
## 进化: 多场比赛里"赢的留下、输的变异", 并随时间"变强"(失误/抖动下降)。
## 不走 RL(③)。禁止把它做成"全局最优排行"——只塑造"风格", 允许各风格并存。

# --- 基因位 (0..1, 除注明外) ---
var error_chance: float = 0.08      ## 失误率 (越低越强)
var aggression: float = 0.5         ## 冒进度 (球速/力度倾向)
var save_willingness: float = 0.35  ## 救球意愿 (0=从不, 1=总想救)
var smash_tendency: float = 0.5     ## 扣杀倾向
var aim_jitter: float = 0.12        ## 瞄准抖动 (越大越不准)
var depth_pref: float = 0.5         ## 落点深浅偏好 (0=短/靠墙, 1=深/靠玩家)
var feint: float = 0.5              ## 假动作倾向

## 默认基因 = 当前 AI 的基准行为。
static func make_default() -> AiGenome:
	return AiGenome.new()

## 随机起始基因 (用于"从零养风格")。
static func make_random() -> AiGenome:
	var g := AiGenome.new()
	g.error_chance = randf_range(0.02, 0.30)
	g.aggression = randf()
	g.save_willingness = randf()
	g.smash_tendency = randf()
	g.aim_jitter = randf_range(0.05, 0.35)
	g.depth_pref = randf()
	g.feint = randf()
	return g

func clone() -> AiGenome:
	var g := AiGenome.new()
	g.error_chance = error_chance
	g.aggression = aggression
	g.save_willingness = save_willingness
	g.smash_tendency = smash_tendency
	g.aim_jitter = aim_jitter
	g.depth_pref = depth_pref
	g.feint = feint
	return g

## 变异: 每个基因位加一点随机扰动 (rate = 扰动幅度)。
func mutated(rate: float = 0.1) -> AiGenome:
	var g := clone()
	g.error_chance = clampf(g.error_chance + randf_range(-rate, rate), 0.0, 0.5)
	g.aggression = clampf(g.aggression + randf_range(-rate, rate), 0.0, 1.0)
	g.save_willingness = clampf(g.save_willingness + randf_range(-rate, rate), 0.0, 1.0)
	g.smash_tendency = clampf(g.smash_tendency + randf_range(-rate, rate), 0.0, 1.0)
	g.aim_jitter = clampf(g.aim_jitter + randf_range(-rate, rate), 0.0, 0.5)
	g.depth_pref = clampf(g.depth_pref + randf_range(-rate, rate), 0.0, 1.0)
	g.feint = clampf(g.feint + randf_range(-rate, rate), 0.0, 1.0)
	return g

## 成长: 把"失误/抖动"往 0 拉一点 (越练越强), 外加轻微变异。
func grown(rate: float = 0.1, growth: float = 0.03) -> AiGenome:
	var g := mutated(rate)
	g.error_chance = clampf(g.error_chance - growth, 0.0, 0.5)
	g.aim_jitter = clampf(g.aim_jitter - growth, 0.0, 0.5)
	return g

## 交叉: 朝另一份基因混合一点 (产出"综合"风格, 用于锦标赛里赢家吸收对手特点)。
func crossover(other: AiGenome, amount: float = 0.15) -> AiGenome:
	var g := clone()
	var a: float = clampf(amount, 0.0, 1.0)
	g.error_chance = lerpf(g.error_chance, other.error_chance, a)
	g.aggression = lerpf(g.aggression, other.aggression, a)
	g.save_willingness = lerpf(g.save_willingness, other.save_willingness, a)
	g.smash_tendency = lerpf(g.smash_tendency, other.smash_tendency, a)
	g.aim_jitter = lerpf(g.aim_jitter, other.aim_jitter, a)
	g.depth_pref = lerpf(g.depth_pref, other.depth_pref, a)
	g.feint = lerpf(g.feint, other.feint, a)
	return g

## 可读风格名 (由基因推导, 仅供参考名字, 非评分)。
func style_name() -> String:
	var s := ""
	if aggression > 0.6:
		s += "激进"
	elif aggression < 0.4:
		s += "稳守"
	else:
		s += "均衡"
	if smash_tendency > 0.65:
		s += "·扣杀党"
	if save_willingness > 0.6:
		s += "·爱救球"
	if feint > 0.65:
		s += "·假动作"
	return s

func to_dict() -> Dictionary:
	return {
		"error_chance": error_chance, "aggression": aggression,
		"save_willingness": save_willingness, "smash_tendency": smash_tendency,
		"aim_jitter": aim_jitter, "depth_pref": depth_pref, "feint": feint,
	}

static func from_dict(d: Dictionary) -> AiGenome:
	var g := AiGenome.new()
	g.error_chance = float(d.get("error_chance", g.error_chance))
	g.aggression = float(d.get("aggression", g.aggression))
	g.save_willingness = float(d.get("save_willingness", g.save_willingness))
	g.smash_tendency = float(d.get("smash_tendency", g.smash_tendency))
	g.aim_jitter = float(d.get("aim_jitter", g.aim_jitter))
	g.depth_pref = float(d.get("depth_pref", g.depth_pref))
	g.feint = float(d.get("feint", g.feint))
	return g

## 导出到 JSON 文件 (存"成熟体")。
func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true

## 从 JSON 文件导入。
static func load_from(path: String) -> AiGenome:
	if not FileAccess.file_exists(path):
		return AiGenome.make_default()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return AiGenome.make_default()
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return AiGenome.make_default()
	return from_dict(parsed)
