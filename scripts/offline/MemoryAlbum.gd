# MemoryAlbum.gd — 重大奇遇自动入库的"回忆相册"
"""
每当关系**跨级跃迁**（陌生→点头之交→熟人→朋友→好朋友→暧昧→恋人）
或者 delta 特别大（≥ 15）的奇遇 → 入相册条目
相册条目：
{
  "day": N,
  "date": "2026-10-03",
  "title": "终于成为朋友",
  "subtitle": "我和小柚一起吃了顿火锅",
  "level_before": "熟人",
  "level_after":  "朋友",
  "npcs": ["xiaoyou"],
  "transcript": ["小柚：...", "我：..."],
  "tags": ["温情", "成长"],
  "image_path": "user://albums/day23.png",   # 截图路径（可选）
}
"""
extends Node

static var _inst: Node = null
static func get_instance() -> Node:
	if _inst == null:
		var EngineScript = load("res://scripts/offline/MemoryAlbum.gd")
		_inst = EngineScript.new()
		_inst.name = "MemoryAlbum"
		var root = Engine.get_main_loop().get_root()
		if root:
			root.add_child(_inst)
	return _inst

const NPC_DISPLAY := {
	"xiaoyou":  "🍊 小柚",
	"xiaoyang": "🐑 小羊",
	"mother":   "👩 妈妈",
	"father":   "👨 爸爸",
	"brother":  "👦 弟弟",
	"classmate":"👦 同学",
	"teacher":  "👨‍🏫 老师",
	"crush":    "💝 TA",
	"partner":  "💔 TA",
}

# 等级中文名
const LEVEL_NAMES := [
	"陌生", "点头之交", "熟人", "朋友", "好朋友", "暧昧", "恋人",
	"灵魂伴侣"  # Lv.5
]

var _album: Array = []  # [{...}, {...}]

# 重大奇遇的判定阈值
const BIG_DELTA := 15    # 单次 +15 分以上
const LEVEL_JUMP_THRESHOLD := 1  # 等级跃迁 ≥ 1 级

# === 入库一条回忆 ===
# 参数顺序：(before_type, after_type, day, a, b, delta, transcript, tags)
func add_memory(before_type: String, after_type: String, day: int, a: String, b: String, delta: int, transcript: Array, tags: Array) -> Dictionary:
	# 找等级前后
	var before_lv: int = _type_to_lv(before_type)
	var after_lv: int = _type_to_lv(after_type)
	var is_level_jump: bool = (after_lv - before_lv) >= LEVEL_JUMP_THRESHOLD
	if not is_level_jump:
		# 不是跃迁就不入库
		return {}

	var title: String = "成为 %s" % LEVEL_NAMES[after_lv] if after_lv < len(LEVEL_NAMES) else "更进一步"
	var npcs: Array = [a, b]
	var subtitle: String = "和 %s、%s 一起度过了重要的一天" % [NPC_DISPLAY.get(a, a), NPC_DISPLAY.get(b, b)]

	var mem := {
		"day": day,
		"date": Time.get_date_string_from_system(),
		"title": title,
		"subtitle": subtitle,
		"level_before": before_type,
		"level_after": after_type,
		"npcs": npcs,
		"transcript": transcript,
		"tags": tags,
		"timestamp": int(Time.get_unix_time_from_system()),
	}
	_album.append(mem)
	if _album.size() > 200:
		_album = _album.slice(_album.size() - 200, 200)
	print("[MemoryAlbum] 📸 新回忆入库：%s · 第 %d 天" % [title, day])
	return mem

func get_album() -> Array:
	return _album

func _type_to_lv(t: String) -> int:
	match t:
		"恋人":       return 6
		"灵魂伴侣":   return 6
		"暧昧":       return 5
		"好朋友":     return 4
		"闺蜜/兄弟":  return 4
		"朋友":       return 3
		"熟人":       return 2
		"点头之交":   return 1
		_:            return 0

# === 序列化（存档）===
func to_dict() -> Dictionary:
	return {"album": _album}

func from_dict(data: Dictionary) -> void:
	if data.has("album"):
		_album = data["album"]