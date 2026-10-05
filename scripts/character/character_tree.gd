class_name CharacterTree
extends RefCounted
## P5 · 角色家谱 / 进化树。
##
## 永久记录: 父代 / 子代 / 每次变异候选 / 玩家选择 / **被淘汰分支也保存** / 当前节点。
## = 角色家谱 + 玩家历史 + 收藏(为未来"后悔机制: 重新启用旧形态"留数据)。
## 每个节点 = 一具身体的快照 (即 MutationSystem 的候选字典) + 元信息 (id/parent/gen/status/label/children)。

const SAVE_PATH := "user://character_tree.json"

var nodes: Array = []      ## 节点列表 (每项是 Dictionary)
var current_id: int = -1   ## 当前所在节点
var next_id: int = 0

func get_node_by_id(id: int) -> Dictionary:
	for n in nodes:
		if int(n.get("id", -1)) == id:
			return n
	return {}

func current() -> Dictionary:
	return get_node_by_id(current_id)

func children_of(id: int) -> Array:
	var out: Array = []
	for n in nodes:
		if int(n.get("parent", -1)) == id:
			out.append(n)
	return out

func count() -> int:
	return nodes.size()

func _new_node(parent_id: int, gen: int, cand: Dictionary, status: String, label: String) -> Dictionary:
	var node: Dictionary = cand.duplicate()
	node["id"] = next_id
	node["parent"] = parent_id
	node["gen"] = gen
	node["status"] = status
	node["label"] = label
	node["children"] = []
	next_id += 1
	nodes.append(node)
	return node

## 以"当前身体"建立根节点 (清空旧树)。返回根 id。
func reset_root(cand: Dictionary) -> int:
	nodes.clear()
	next_id = 0
	current_id = -1
	var n: Dictionary = _new_node(-1, 0, cand, "current", "初始")
	current_id = int(n["id"])
	return current_id

## 玩家选定一个候选: 作为当前节点的子代; **其余候选作为"被淘汰分支"一并保存**。
## 返回新当前节点的 id。
func choose(cand: Dictionary, eliminated: Array = []) -> int:
	var cur: Dictionary = current()
	var gen: int = int(cur.get("gen", 0)) + 1 if not cur.is_empty() else 0
	var chosen: Dictionary = _new_node(current_id, gen, cand, "current", String(cand.get("name", "选择")))
	for e in eliminated:
		_new_node(current_id, gen, e, "eliminated", String(e.get("name", "淘汰")))
	if not cur.is_empty():
		cur["children"].append(chosen["id"])
		if String(cur.get("status", "")) == "current":
			cur["status"] = "past"
	current_id = int(chosen["id"])
	return current_id

func to_dict() -> Dictionary:
	return {"current": current_id, "next": next_id, "nodes": nodes}

func from_dict(d: Dictionary) -> void:
	current_id = int(d.get("current", -1))
	next_id = int(d.get("next", 0))
	nodes = d.get("nodes", [])

func save() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true

func load_tree() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	from_dict(parsed)
	return true

## 从根到当前的路径 (节点列表) —— 用于展示"我这一路是怎么变过来的"。
func path_to_current() -> Array:
	var out: Array = []
	var id: int = current_id
	while id >= 0:
		var n: Dictionary = get_node_by_id(id)
		if n.is_empty():
			break
		out.push_front(n)
		id = int(n.get("parent", -1))
	return out
