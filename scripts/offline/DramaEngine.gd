# DramaEngine.gd — 离线模拟器（核心）
# 玩家离线 N 天时，按"每天 K 场戏"模拟
# 1. 选两个 NPC（按 RelationshipMatrix.weight 加权）
# 2. 选一个模板（按关系 + 性格）
# 3. 渲染对话（先用模板文本）
# 4. 写入 OfflineClock 事件 + 调整关系矩阵
extends Node

const RelationshipMatrix = preload("res://scripts/offline/RelationshipMatrix.gd")
const DramaTemplates = preload("res://scripts/offline/DramaTemplates.gd")

const NPC_DISPLAY = {
	"father":   "👨 爸爸",
	"mother":   "👩 妈妈",
	"brother":  "👦 弟弟",
	"classmate":"👦 同学",
	"teacher":  "👨‍🏫 班主任",
	"crush":    "💝 TA",
	"partner":  "💔 TA",
	"xiaoyang": "🐑 小羊",
	"xiaoyou":  "🍊 小柚",
}

const EVENTS_PER_DAY := 4  # 每天模拟 4 场戏

# 关系网络（全局唯一）
var _matrix: Node = null
var _templates: RefCounted = null
var _clock: Node = null

func run_n_days(days: int) -> void:
	print("[DramaEngine] 开始模拟 %d 天，每天 %d 场戏" % [days, EVENTS_PER_DAY])
	# 拿全局实例
	_matrix = RelationshipMatrix.get_instance()
	_templates = DramaTemplates.new()
	_clock = _get_clock()
	# 恢复历史 matrix
	if _clock and _clock._state.get("matrix"):
		_matrix.from_dict(_clock._state["matrix"])
	# 模拟
	# 模拟天数从 (当前游戏日 - elapsed_days + 1) 到 当前游戏日
	var base_day: int = (_clock.get_current_day() if _clock else 1) - days + 1
	for d in range(days):
		var current_day: int = base_day + d
		for i in EVENTS_PER_DAY:
			var evt := _simulate_one_event(current_day)
			if _clock:
				_clock.add_event(evt)
	# 写回
	if _clock:
		_clock._state["matrix"] = _matrix.to_dict()
		_clock._save()
	print("[DramaEngine] 模拟完成，共 %d 天 / %d 场戏" % [days, days * EVENTS_PER_DAY])

func _get_clock() -> Node:
	var c = get_node_or_null("/root/Main/OfflineClock")
	if c: return c
	c = get_node_or_null("/root/OfflineClock")
	if c: return c
	# 没有就直接 new 一个
	var ClockScript = load("res://scripts/offline/OfflineClock.gd")
	if ClockScript:
		var inst = ClockScript.new()
		inst.name = "OfflineClock"
		get_tree().get_root().add_child(inst)
		return inst
	return null

func _simulate_one_event(day: int) -> Dictionary:
	var npc_ids: Array = _matrix.NPC_IDS
	var pair: Array = _pick_pair()
	var a: String = pair[0]
	var b: String = pair[1]
	var rel: Dictionary = _matrix.pair(a, b)
	var current_type: String = "陌生"
	if rel.has("type"):
		current_type = rel["type"]
	# === 等级门控：根据当前 points 计算 level，再按 level 挑模板 ===
	var points: int = int(rel.get("points", 0))
	var current_level: int = _matrix.get_level_for_points(points)
	var t: Dictionary = _templates.pick_template_by_level(current_level)
	# 渲染对话
	var name_a: String = NPC_DISPLAY.get(a, a)
	var name_b: String = NPC_DISPLAY.get(b, b)
	var transcript: Array = []
	var scenes_raw: Variant = t.get("scenes")
	var scenes: Array = (scenes_raw as Array) if scenes_raw is Array else []
	for line in scenes:
		var s: String = line[0] if line is Array and line.size() > 0 else str(line)
		transcript.append(_templates.render(s, name_a, name_b))
		if line is Array and line.size() > 1:
			var s2: String = line[1]
			transcript.append(_templates.render(s2, name_a, name_b))
	# delta
	var raw_delta: Variant = null
	if t.has("delta"):
		raw_delta = t["delta"]
	var delta_range: Array = (raw_delta as Array) if raw_delta is Array else [1, 3]
	var lo: int = int(delta_range[0])
	var hi: int = int(delta_range[1]) if delta_range.size() > 1 else lo
	var delta: int = randi_range(lo, hi)
	# 关系值变化（记录 before / after 用来触发相册）
	var before_type: String = "陌生"
	if rel.has("type"):
		before_type = rel["type"]
	_matrix.mutate(a, b, delta)
	var new_rel: Dictionary = _matrix.pair(a, b)
	var new_type: String = "陌生"
	if new_rel.has("type"):
		new_type = new_rel["type"]
	# 摘要
	var summary: String = _summarize(t, name_a, name_b, delta, new_type)
	var evt_tags: Array = []
	var _raw_tags: Variant = t.get("tags")
	if _raw_tags is Array:
		evt_tags = _raw_tags
	var evt := {
		"day": day,
		"a": a, "b": b,
		"name_a": name_a, "name_b": name_b,
		"template": str(t.get("id", "?")),
		"tags": evt_tags,
		"transcript": transcript,
		"delta": delta,
		"new_type": new_type,
		"summary": summary,
		"timestamp": int(Time.get_unix_time_from_system()),
	}
	print("[DramaEngine] Day %d · %s × %s · %s · %+d 分 → %s" % [day, name_a, name_b, str(t.get("id", "?")), delta, new_type])

	# === 触发相册入库：等级跃迁或超大批量加分 ===
	var album_script = load("res://scripts/offline/MemoryAlbum.gd")
	if album_script:
		var album = album_script.get_instance()
		# add_memory 签名：(before_type, after_type, day, a, b, delta, transcript, tags)
		album.add_memory(before_type, new_type, day, a, b, delta, transcript, evt_tags)

	# === 触发日记：让 NPC 写一条独处日记 ===
	# （A 不直接和玩家互动，简化处理：写"独处"日记，body 用平淡内容）
	var diary_script = load("res://scripts/offline/NPCDiary.gd")
	if diary_script:
		var diary = diary_script.get_instance()
		if diary and diary.has_method("append_entry"):
			diary.append_entry(a, day, false)
			# 重大事件（delta 很大）→ B 也写一条
			if delta >= 8:
				diary.append_entry(b, day, false)

	return evt

# 加权选两个 NPC
func _pick_pair() -> Array:
	var npc_ids: Array = _matrix.NPC_IDS
	var total_w: float = 0.0
	var weights: Array = []
	for a in npc_ids:
		var row: Array = []
		for b in npc_ids:
			if a == b:
				row.append(0.0)
			else:
				var w: float = _matrix.weight(a, b)
				row.append(w)
				total_w += w
		weights.append(row)
	if total_w <= 0:
		return [npc_ids[0], npc_ids[1]]
	var r: float = randf() * total_w
	var acc: float = 0.0
	for ai in npc_ids.size():
		for bi in npc_ids.size():
			if ai == bi: continue
			acc += float(weights[ai][bi])
			if r <= acc:
				return [npc_ids[ai], npc_ids[bi]]
	return [npc_ids[0], npc_ids[1]]

func _summarize(t: Dictionary, name_a: String, name_b: String, delta: int, new_type: String) -> String:
	var tags: Array = []
	var _raw: Variant = t.get("tags")
	if _raw is Array:
		tags = _raw
	var tag_str: String = "/".join(tags) if not tags.is_empty() else "日常"
	if delta > 0:
		return "「%s」和「%s」一起【%s】，关系变成【%s】(+%d)" % [name_a, name_b, tag_str, new_type, delta]
	elif delta < 0:
		return "「%s」和「%s」闹了点【%s】，关系变成【%s】(%d)" % [name_a, name_b, tag_str, new_type, delta]
	else:
		return "「%s」和「%s」打了个照面，关系保持【%s】" % [name_a, name_b, new_type]
