class_name AiGenome
extends RefCounted
## ② AI 自进化 · 行为基因 (决定"风格")。
##
## **数据驱动**: 所有基因位定义在 GENE_DEFS 里, 所有操作 (随机/变异/成长/交叉/序列化/风格名)
## 都遍历它 —— 所以**加一条基因 = 往 GENE_DEFS 加一行** (+ 在 AI 逻辑里用一次)。
##
## 进化: 多场比赛里"赢的留下、输的变异", 并随时间"变强"(invert 位往低处走)。
## 不走 RL(③)。禁止做成"全局最优排行"——只塑造"风格", 允许各风格并存。

## 基因表: key -> { def 默认, lo 下限, hi 上限, invert 越低越强(成长方向), label 显示名 }
const GENE_DEFS := {
	"error_chance":     {"def": 0.08, "lo": 0.0, "hi": 0.5, "invert": true,  "label": "失误"},
	"aggression":       {"def": 0.50, "lo": 0.0, "hi": 1.0, "invert": false, "label": "冒进"},
	"save_willingness": {"def": 0.35, "lo": 0.0, "hi": 1.0, "invert": false, "label": "救球"},
	"smash_tendency":   {"def": 0.50, "lo": 0.0, "hi": 1.0, "invert": false, "label": "扣杀"},
	"aim_jitter":       {"def": 0.12, "lo": 0.0, "hi": 0.5, "invert": true,  "label": "抖动"},
	"depth_pref":       {"def": 0.50, "lo": 0.0, "hi": 1.0, "invert": false, "label": "深浅"},
	"feint":            {"def": 0.50, "lo": 0.0, "hi": 1.0, "invert": false, "label": "假动作"},
}

var genes: Dictionary = {}

func _init() -> void:
	for k in GENE_DEFS:
		genes[k] = GENE_DEFS[k]["def"]

func get_gene(k: String) -> float:
	if genes.has(k):
		return float(genes[k])
	return float(GENE_DEFS[k]["def"]) if GENE_DEFS.has(k) else 0.0

func set_gene(k: String, v: float) -> void:
	if GENE_DEFS.has(k):
		genes[k] = clampf(v, GENE_DEFS[k]["lo"], GENE_DEFS[k]["hi"])

## 默认基因 = 当前 AI 的基准行为。
static func make_default() -> AiGenome:
	return AiGenome.new()

## 随机起始基因 (用于"从零养风格")。
static func make_random() -> AiGenome:
	var g := AiGenome.new()
	for k in GENE_DEFS:
		g.genes[k] = randf_range(GENE_DEFS[k]["lo"], GENE_DEFS[k]["hi"])
	return g

func clone() -> AiGenome:
	var g := AiGenome.new()
	for k in GENE_DEFS:
		g.genes[k] = get_gene(k)
	return g

## 变异: 每个基因位加一点随机扰动 (rate = 扰动幅度)。
func mutated(rate: float = 0.1) -> AiGenome:
	var g := clone()
	for k in GENE_DEFS:
		g.genes[k] = clampf(g.get_gene(k) + randf_range(-rate, rate),
			GENE_DEFS[k]["lo"], GENE_DEFS[k]["hi"])
	return g

## 成长: 把"越低越强"(invert) 的位往低处拉一点 (越练越强), 外加轻微变异。
func grown(rate: float = 0.1, growth: float = 0.03) -> AiGenome:
	var g := mutated(rate)
	for k in GENE_DEFS:
		if GENE_DEFS[k]["invert"]:
			g.genes[k] = clampf(g.get_gene(k) - growth, GENE_DEFS[k]["lo"], GENE_DEFS[k]["hi"])
	return g

## 交叉: 朝另一份基因混合一点 (产出"综合"风格, 用于锦标赛里赢家吸收对手特点)。
func crossover(other: AiGenome, amount: float = 0.15) -> AiGenome:
	var g := clone()
	var a: float = clampf(amount, 0.0, 1.0)
	for k in GENE_DEFS:
		g.genes[k] = lerpf(g.get_gene(k), other.get_gene(k), a)
	return g

## 可读风格名 (由基因推导, 仅供参考名字, 非评分)。
func style_name() -> String:
	var s := "均衡"
	var ag: float = get_gene("aggression")
	if ag > 0.6:
		s = "激进"
	elif ag < 0.4:
		s = "稳守"
	if get_gene("smash_tendency") > 0.65:
		s += "·扣杀党"
	if get_gene("save_willingness") > 0.6:
		s += "·爱救球"
	if get_gene("feint") > 0.65:
		s += "·假动作"
	return s

func to_dict() -> Dictionary:
	return genes.duplicate()

static func from_dict(d: Dictionary) -> AiGenome:
	var g := AiGenome.new()
	for k in GENE_DEFS:
		if d.has(k):
			g.set_gene(k, float(d[k]))
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
