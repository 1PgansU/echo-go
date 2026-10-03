# RelationshipMatrix.gd — 9 个 NPC 之间的"关系网"
# 数据结构：
#   _matrix: { "xiaoyang": { "mother": {"points": 18, "type": "忘年交", "events": [...]}, ... }, ... }
# 不写盘：被 OfflineClock 在关游戏 / 开游戏时统一调度
extends Node

# 全局唯一的关系网实例（singleton）
static var _inst: Node = null
static func get_instance() -> Node:
	if _inst == null:
		var MatrixScript = load("res://scripts/offline/RelationshipMatrix.gd")
		_inst = MatrixScript.new()
		_inst.name = "RelationshipMatrix"
		var root = Engine.get_main_loop().get_root()
		if root:
			root.call_deferred("add_child", _inst)  # 延后一帧，避开根未就绪
		# 兜底：万一 _ready 因为某种原因没填充，强制初始化
		_inst._ensure_full_grid()
	return _inst

# 9 个 NPC（必须和 ChatDialogue 里的 npc_id 对齐）
const NPC_IDS := [
	"father", "mother", "brother", "classmate", "teacher",
	"crush", "partner", "xiaoyang", "xiaoyou"
]

# 性格契合度（决定两个 NPC 互动可能性）
# 这里按"性格向性"打分：开朗-开朗 / 阴郁-开朗 / 安静-安静 ...
# 不考虑年龄/性别/身份，纯性格契合
const PERSONALITY_AFFINITY := {
	"xiaoyang":  {"xiaoyou": 0.95, "brother": 0.85, "crush": 0.80, "classmate": 0.75, "father": 0.45, "mother": 0.55, "teacher": 0.30, "partner": 0.40},
	"xiaoyou":   {"xiaoyang": 0.95, "brother": 0.85, "crush": 0.80, "classmate": 0.75, "mother": 0.55, "father": 0.45, "teacher": 0.30, "partner": 0.40},
	"father":    {"mother": 0.50, "teacher": 0.65, "xiaoyang": 0.45, "brother": 0.70, "xiaoyou": 0.45, "classmate": 0.40, "crush": 0.30, "partner": 0.30},
	"mother":    {"father": 0.50, "teacher": 0.55, "xiaoyang": 0.55, "brother": 0.75, "xiaoyou": 0.65, "classmate": 0.45, "crush": 0.50, "partner": 0.50},
	"brother":   {"xiaoyang": 0.85, "xiaoyou": 0.85, "classmate": 0.80, "father": 0.70, "mother": 0.75, "crush": 0.40, "partner": 0.35, "teacher": 0.30},
	"classmate": {"xiaoyang": 0.75, "xiaoyou": 0.75, "brother": 0.80, "crush": 0.60, "partner": 0.60, "father": 0.40, "mother": 0.45, "teacher": 0.50},
	"teacher":   {"father": 0.65, "mother": 0.55, "classmate": 0.50, "crush": 0.35, "partner": 0.35, "xiaoyang": 0.30, "xiaoyou": 0.30, "brother": 0.30},
	"crush":     {"xiaoyang": 0.80, "xiaoyou": 0.80, "classmate": 0.60, "partner": 0.20, "brother": 0.40, "father": 0.30, "mother": 0.50, "teacher": 0.35},
	"partner":   {"crush": 0.20, "classmate": 0.60, "xiaoyang": 0.40, "xiaoyou": 0.40, "brother": 0.35, "father": 0.30, "mother": 0.50, "teacher": 0.35},
}

# 关系类型（按 points 升序解锁）
# 等级数字：0~5
const LEVEL_TABLE := [
	{"min":   0, "name": "陌生",       "level": 0, "color": "gray"},
	{"min":   5, "name": "点头之交",   "level": 1, "color": "white"},
	{"min":  20, "name": "熟人",       "level": 2, "color": "blue"},
	{"min":  50, "name": "朋友",       "level": 3, "color": "green"},
	{"min":  90, "name": "闺蜜/兄弟",  "level": 4, "color": "purple"},
	{"min": 150, "name": "灵魂伴侣",   "level": 5, "color": "gold"},
]

func get_type_for_points(p: int) -> String:
	# 从大到小遍历，先匹配到最大的阈值（避免 min:0 第一项就吞掉所有）
	for i in range(LEVEL_TABLE.size() - 1, -1, -1):
		if p >= LEVEL_TABLE[i]["min"]:
			return LEVEL_TABLE[i]["name"]
	return "陌生"

# 新增：根据分数返回等级（0~5）
func get_level_for_points(p: int) -> int:
	for i in range(LEVEL_TABLE.size() - 1, -1, -1):
		if p >= LEVEL_TABLE[i]["min"]:
			return int(LEVEL_TABLE[i]["level"])
	return 0

# 新增：返回下一级所需分数（当前等级的最大值+1）
func get_next_level_threshold(p: int) -> int:
	for entry in LEVEL_TABLE:
		if p < entry["min"]:
			return entry["min"]
	return -1  # 已满级

# 关系值变化：双向影响
# delta 可能为正可能为负
func mutate(a: String, b: String, delta: int) -> void:
	_ensure(a, b)
	_ensure(b, a)
	_matrix[a][b]["points"] = int(_matrix[a][b].get("points", 0)) + delta
	_matrix[b][a]["points"] = int(_matrix[b][a].get("points", 0)) + delta
	# 关系类型同步
	_matrix[a][b]["type"] = get_type_for_points(int(_matrix[a][b]["points"]))
	_matrix[b][a]["type"] = get_type_for_points(int(_matrix[b][a]["points"]))
	# 关系变更信号
	relationship_mutated.emit(a, b, int(_matrix[a][b]["points"]), _matrix[a][b]["type"])

signal relationship_mutated(a: String, b: String, points: int, type_name: String)

var _matrix: Dictionary = {}

func _ready() -> void:
	_ensure_full_grid()

# === 玩家对各 NPC 的"初始亲缘好感度" ===
# 这是游戏的"叙事预设"——不是每个 NPC 都从 0 开始
# 9 个 NPC 差异化开局：闺蜜/发小高、暗恋/前任低/负、家人中等
const PLAYER_INITIAL_POINTS := {
	"xiaoyou":   60,   # 闺蜜，从小认识（Lv.3 朋友开局 · 高）
	"xiaoyang":  45,   # 邻居/发小（Lv.3 朋友）
	"mother":    28,   # 妈妈（Lv.2 熟人偏上）
	"father":    18,   # 爸爸（Lv.1 点头之交 → 熟人间）
	"brother":   10,   # 弟弟（Lv.1 点头之交）
	"classmate":  6,   # 同学（Lv.1 点头之交）
	"teacher":    2,   # 老师（Lv.0 陌生 → 略认识）
	"crush":      0,   # 暗恋对象：还没说过话（**重头开始追**）
	"partner":  -15,   # 前任：刚分手（负分，关系微妙）
}

# 给玩家"加载一次性"的好感预设
# 注意：只在第一次玩 / 重开档时调用，已有进度不要覆盖
func apply_player_initial_points() -> void:
	for npc_id in PLAYER_INITIAL_POINTS:
		var pts: int = PLAYER_INITIAL_POINTS[npc_id]
		if not _matrix.has("partner"):
			_matrix["partner"] = {}
		_matrix["partner"][npc_id] = {
			"points": pts,
			"type": get_type_for_points(pts),
			"events": 0,
		}
		# NPC 那边也要有对玩家的记录（虽然是 NPC → partner）
		if not _matrix.has(npc_id):
			_matrix[npc_id] = {}
		_matrix[npc_id]["partner"] = {
			"points": pts,
			"type": get_type_for_points(pts),
			"events": 0,
		}
		# 重要：crush 跟玩家之间**没有"早就认识"的桥**，
		# 所以 NPC 那边对玩家也是 0（不是 50）
		if npc_id == "crush":
			_matrix["crush"]["partner"]["points"] = 0
			_matrix["crush"]["partner"]["type"] = "陌生"
		# partner（前任）也是：TA 已经跟玩家 0 分（分手了）
		if npc_id == "partner":
			_matrix["partner"]["partner"]["points"] = 0
			_matrix["partner"]["partner"]["type"] = "陌生"
	print("[RelationshipMatrix] 已应用玩家初始好感预设")

func _ensure_full_grid() -> void:
	# 默认所有 NPC 互相 0 分（陌生）
	for a in NPC_IDS:
		_matrix[a] = {}
		for b in NPC_IDS:
			if a != b:
				_matrix[a][b] = {"points": 0, "type": "陌生", "events": 0}

func _ensure(a: String, b: String) -> void:
	if not _matrix.has(a): _matrix[a] = {}
	if not _matrix[a].has(b): _matrix[a][b] = {"points": 0, "type": "陌生", "events": 0}

# 查 A 对 B 的关系
func pair(a: String, b: String) -> Dictionary:
	if a == b: return {"points": 999, "type": "自己", "events": 0}
	_ensure(a, b)
	return _matrix[a][b]

# 两个 NPC 互动的可能性权重（性格契合 + 当前关系 + 同地）
func weight(a: String, b: String) -> float:
	if a == b: return 0.0
	var aff: float = PERSONALITY_AFFINITY.get(a, {}).get(b, 0.5)
	var rel: int = int(pair(a, b).get("points", 0))
	# 关系越好 → 越可能继续互动（已经熟了）
	var rel_w: float = 0.3 + clamp(float(rel) / 100.0, 0.0, 1.0) * 0.7
	return aff * rel_w

# 关系最强的 K 对（用来"跨 NPC 关系传染"）
func get_top_pairs(k: int = 5) -> Array:
	var pairs: Array = []
	for a in NPC_IDS:
		for b in NPC_IDS:
			if a < b:  # 去重
				pairs.append({"a": a, "b": b, "points": int(pair(a, b).get("points", 0))})
	pairs.sort_custom(func(x, y): return int(x.points) > int(y.points))
	return pairs.slice(0, min(k, pairs.size()))

# 序列化（写盘）
func to_dict() -> Dictionary:
	return _matrix.duplicate(true)

# 反序列化（读盘）
func from_dict(d: Dictionary) -> void:
	_matrix = d.duplicate(true)
	for a in NPC_IDS:
		if not _matrix.has(a): _matrix[a] = {}
		for b in NPC_IDS:
			if a != b and not _matrix[a].has(b):
				_matrix[a][b] = {"points": 0, "type": "陌生", "events": 0}
