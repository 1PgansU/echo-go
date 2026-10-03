# NPCDiary.gd — 每个 NPC 一本私人日记（数据层）
# 数据结构（每本日记是一个数组，按 day 升序）：
# [
#   {
#     "day": 3,                     # 第几天
#     "date": "2026-10-03",         # 真实日期
#     "weather": "☀️ 晴",
#     "mood": "happy",
#     "mood_label": "😊 开心",
#     "with_player": false,         # 是否和玩家相关
#     "content": "今天天气不错……",  # 日记正文
#   },
#   ...
# ]
extends Node

# 单例
static var _inst: Node = null
static func get_instance() -> Node:
	if _inst == null or not is_instance_valid(_inst):
		var EngineScript = load("res://scripts/offline/NPCDiary.gd")
		_inst = EngineScript.new()
		_inst.name = "NPCDiary"
		var root = Engine.get_main_loop().get_root()
		if root:
			root.call_deferred("add_child", _inst)
	return _inst

# 9 个 NPC 一人一本
const NPC_IDS := [
	"father", "mother", "brother", "classmate", "teacher",
	"crush", "partner", "xiaoyang", "xiaoyou"
]

# 玩家 id（用来从 RelationshipMatrix 里查"玩家↔NPC 真实亲密度"）
# 注意：RelationshipMatrix 内部把所有 NPC 视为同质节点，
# "玩家"是 NPC 列表中的 "partner" 这一项（和"前任"id 撞名，纯巧合）
const PLAYER_ID := "partner"

const SAVE_PATH := "user://npc_diary.json"

# === 心情 / 天气 ===
const WEATHERS := ["☀️ 晴", "⛅ 多云", "🌧️ 雨", "❄️ 雪", "🌙 夜晚"]
const MOOD_LABEL := {
	"happy":     "😊 开心",
	"chill":     "🍃 平静",
	"down":      "😔 有点低落",
	"excited":   "🔥 激动",
	"thoughtful":"🤔 若有所思",
}

# NPC 性格语气
const NPC_VOICE := {
	"xiaoyou":  "excited",
	"xiaoyang": "happy",
	"mother":   "thoughtful",
	"father":   "chill",
	"brother":  "chill",
	"classmate":"chill",
	"teacher":  "thoughtful",
	"crush":    "thoughtful",
	"partner":  "excited",
}

# === 内容池 ===
# layer 0 = 独处（和玩家无关）
# layer 1 = 偶然想起玩家
# layer 2 = 亲密玩家
const CONTENT_POOL := {
	"alone": [
		"今天天气不错，出去溜达了一圈。",
		"一个人去楼下买了杯奶茶，喝着还挺好喝的。",
		"下午在家窝着，翻了几页书。",
		"今天有点困，睡了很久。",
		"看见一只野猫，毛茸茸的，蹲在花坛边上一动不动。",
		"街角新开了一家店，门口排了好长的队。",
		"今天什么也没干，就发了一天呆。",
		"整理了下房间，把一些旧东西翻出来看了看。",
	],
	"miss_player": {
		"xiaoyou":  "今天又想起 %X 了。",
		"xiaoyang": "路上好像看到 %X 的背影，想打招呼来着，结果一眨眼人就不见了。",
		"mother":   "%X 出门前我多看了几眼，也不知道这孩子今天过得顺不顺。",
		"father":   "%X 这两天心情好像不错，家里的气氛也跟着松快了一点。",
		"brother":  "%X 给我带了点吃的回来，还挺暖的。",
		"classmate":"今天 %X 主动跟我说了句话，感觉还挺意外的。",
		"teacher":  "%X 最近状态还行，作为老师看在眼里也放心了些。",
		"crush":    "不知道为什么，今天脑海里莫名其妙地出现了 %X 的脸。",
		"partner":  "……没什么。",
	},
	"intimate": [
		"和 %X 聊了好久，发现我们居然有这么多共同点。",
		"今天和 %X 待在一起一整个下午，时间过得好快。",
		"%X 跟我说了一件事，让我对 TA 有点改观。",
		"今天和 %X 一起去买了杯奶茶。",
		"%X 笑了一下，我的心跳漏了半拍。",
	],
	"conflict": [
		"和 %X 有点小矛盾，不过应该没什么大事。",
		"%X 今天好像心情不太好，我也不知道该说什么。",
	],
}

# === 内部数据 ===
var _diaries: Dictionary = {}  # { npc_id: [entry, entry, ...] }


func _ready() -> void:
	_load_diary()


# === 存档 / 读档 ===
func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[NPCDiary] 写存档失败: %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(_diaries, "\t"))
	f.close()


func _load_diary() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		_diaries = parsed


# === 对外 API ===

# 取整本日记（按 day 升序）
func get_diary(npc_id: String) -> Array:
	var arr: Array = _diaries.get(npc_id, [])
	return arr.duplicate()


# 取"今天"的全部 NPC 日记（按时间倒序）
func get_today_entries() -> Array:
	var today: String = Time.get_date_string_from_system()
	var out: Array = []
	for npc_id in NPC_IDS:
		for e in _diaries.get(npc_id, []):
			if str(e.get("date", "")) == today:
				var copy: Dictionary = e.duplicate()
				copy["npc_id"] = npc_id
				out.append(copy)
	# 按 day 倒序
	out.sort_custom(func(a, b): return int(a.get("day", 0)) > int(b.get("day", 0)))
	return out


# 取总数
func get_total_count(npc_id: String) -> int:
	return _diaries.get(npc_id, []).size()


# 取玩家对 NPC 的亲密度（从 RelationshipMatrix 读）
func _get_player_points(npc_id: String) -> int:
	var matrix_script: Variant = load("res://scripts/offline/RelationshipMatrix.gd")
	if matrix_script == null:
		return 0
	var matrix: Node = matrix_script.get_instance() if matrix_script.has_method("get_instance") else null
	if matrix == null:
		return 0
	if not matrix.has_method("pair"):
		return 0
	# pair(a, b) 返回 {"points": int, "type": String, ...}
	var rel: Dictionary = matrix.pair(npc_id, PLAYER_ID)
	if rel == null:
		return 0
	return int(rel.get("points", 0))


# 玩家亲密度等级 → 可见条数
func get_visible_count(npc_id: String) -> int:
	var total: int = get_total_count(npc_id)
	if total <= 0:
		return 0
	var pts: int = _get_player_points(npc_id)
	var lv: int = _points_to_level(pts)
	# 等级 0~5 对应可见条数
	match lv:
		0, 1: return min(1, total)   # 点头之交也能偷看 1 条
		2:     return min(2, total)
		3:     return min(4, total)
		4:     return min(8, total)
		5:     return total
	return 0


func _points_to_level(p: int) -> int:
	# 复刻 RelationshipMatrix 的 LEVEL_TABLE
	if p >= 150: return 5
	if p >= 90:  return 4
	if p >= 50:  return 3
	if p >= 20:  return 2
	if p >= 5:   return 1
	return 0


# === 写日记 ===
# 与玩家互动后调用，自动写一条
func append_entry(npc_id: String, day: int, with_player: bool = false) -> void:
	if not _diaries.has(npc_id):
		_diaries[npc_id] = []

	var base_mood: String = NPC_VOICE.get(npc_id, "chill")
	var weather: String = WEATHERS[randi() % WEATHERS.size()]

	var content: String = ""
	if with_player:
		# 和玩家有关：按亲密度高低选语气
		var pts: int = _get_player_points(npc_id)
		if pts >= 50:
			content = CONTENT_POOL["intimate"][randi() % CONTENT_POOL["intimate"].size()]
		elif pts >= 20:
			var pool: Array = CONTENT_POOL["intimate"] + CONTENT_POOL["miss_player"].values()
			content = pool[randi() % pool.size()]
		else:
			# 低亲密度但仍有接触：偶尔想起来
			var tmpl_dict: Dictionary = CONTENT_POOL["miss_player"]
			var tmpl: String = tmpl_dict.get(npc_id, "今天想起 %X 了。")
			content = tmpl
	else:
		content = CONTENT_POOL["alone"][randi() % CONTENT_POOL["alone"].size()]

	# 替换 %X 为"你"
	content = content.replace("%X", "你")

	var entry: Dictionary = {
		"day": day,
		"date": Time.get_date_string_from_system(),
		"weather": weather,
		"mood": base_mood,
		"mood_label": MOOD_LABEL.get(base_mood, ""),
		"with_player": with_player,
		"content": content,
	}
	_diaries[npc_id].append(entry)

	# 控制每本最多 50 条
	if _diaries[npc_id].size() > 50:
		_diaries[npc_id] = _diaries[npc_id].slice(_diaries[npc_id].size() - 50, 50)
	_save()


# 给所有 NPC 各写一条"独处"日记（用于 sim / 离线推进）
func append_daily_for_all(day: int) -> void:
	for npc_id in NPC_IDS:
		# 20% 概率写"想起玩家"
		var with_player: bool = randf() < 0.20
		append_entry(npc_id, day, with_player)


# === 首次启动：按亲密度预填有趣日记 ===
# Lv ≥ 3 朋友及以上：写 3 条（含 2 条和玩家相关）
# Lv = 2 熟人：写 2 条（1 条和玩家相关）
# Lv = 1 点头之交：写 1 条（独处）
# Lv = 0 陌生：写 1 条（独处，初始可能看不到）
# 每个 NPC 的日记有不同的"开头小故事"，让日记看起来有剧情感
func seed_starter_diaries(matrix: Node) -> void:
	if matrix == null:
		return

	# 各 NPC 亲密度对应的预设故事（按"和玩家关系"分等级）
	# 每条都是 (天数偏移, with_player, 内容)
	var stories: Dictionary = {
		"xiaoyou": [  # Lv.3 闺蜜
			[-2, true, "今天和 %X 一起放学，TA 突然问我「你觉得我们算不算最亲的」。我没说话，但心里偷偷笑了——这不是废话嘛。"],
			[-1, true, "晚上给 %X 发消息，问 TA 最近在干嘛。结果消息发出去后我又盯着屏幕等了好久……是不是有点太黏了。"],
			[-1, false, "今天穿了一件新卫衣出门，希望明天能碰见 %X，不知道 TA 会不会注意到。"],
		],
		"xiaoyang": [  # Lv.3 发小
			[-3, true, "今天踢球的时候，%X 给我带了一瓶水。我们都跑得满头大汗，但感觉特别爽。"],
			[-1, true, "晚饭后看到 %X 在楼下散步，我假装出来买东西，其实就是想去打个招呼。"],
			[-1, false, "今天自己在家拼了一个乐高，手指都按疼了，但拼完超有成就感。"],
		],
		"mother": [  # Lv.2 熟人
			[-2, true, "%X 出门前我多看了几眼，也不知道这孩子今天过得顺不顺。"],
			[-1, false, "今天把家里收拾了一遍，累得腰都直不起来。"],
		],
		"father": [  # Lv.1 点头之交
			[-1, false, "今天下班回来，看见 %X 在房间里写作业，没敢敲门打扰。"],
		],
		"brother": [  # Lv.1
			[-1, true, "%X 给我带了点吃的回来，还挺暖的。"],
		],
		"classmate": [  # Lv.1
			[-2, false, "今天 %X 主动跟我说了句话，感觉还挺意外的。"],
		],
		"teacher": [  # Lv.0 陌生
			[-1, false, "今天备课到很晚，明天还要早读，有点累。"],
		],
		"crush": [  # Lv.0 重头开始
			[-1, false, "不知道为什么，今天脑海里莫名其妙地出现了 TA 的脸。我们明明还没说过几句话。"],
		],
		"partner": [  # Lv.-1 前任
			[-1, false, "……没什么。"],
		],
	}

	var today_date: String = Time.get_date_string_from_system()

	for npc_id in NPC_IDS:
		if not _diaries.has(npc_id):
			_diaries[npc_id] = []
		# 已有内容则跳过（玩家可能从旧存档来）
		if _diaries[npc_id].size() > 0:
			continue

		var npc_stories: Array = stories.get(npc_id, [])
		if npc_stories.is_empty():
			continue

		var pts: int = _get_player_points(npc_id)
		var lv: int = _points_to_level(pts)
		# 决定要写几条
		var max_count: int = 1
		match lv:
			0, 1: max_count = 1
			2:     max_count = 2
			3, 4, 5, _: max_count = 3

		var written: int = 0
		for story in npc_stories:
			if written >= max_count:
				break
			var day_offset: int = int(story[0])
			var with_player: bool = bool(story[1])
			var text: String = str(story[2]).replace("%X", "你")
			# 心情 / 天气（保持 NPC 性格）
			var base_mood: String = NPC_VOICE.get(npc_id, "chill")
			var weather: String = WEATHERS[randi() % WEATHERS.size()]
			var entry: Dictionary = {
				"day": 1 + day_offset,  # 玩家开游戏是 Day 1，故事发生在 -2~0 天
				"date": today_date,
				"weather": weather,
				"mood": base_mood,
				"mood_label": MOOD_LABEL.get(base_mood, ""),
				"with_player": with_player,
				"content": text,
			}
			_diaries[npc_id].append(entry)
			written += 1

	# 按 day 升序
	for npc_id in NPC_IDS:
		if _diaries.get(npc_id, []).size() > 0:
			_diaries[npc_id].sort_custom(func(a, b): return int(a.get("day", 0)) < int(b.get("day", 0)))

	_save()


# === 调试 / 重置 ===
func clear_all() -> void:
	_diaries = {}
	_save()


func to_dict() -> Dictionary:
	return {"diaries": _diaries.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	if data.has("diaries") and typeof(data["diaries"]) == TYPE_DICTIONARY:
		_diaries = data["diaries"].duplicate(true)
		_save()
