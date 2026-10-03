extends Node
# NPCManager：加载 npcs/ 下所有 NPC JSON 配置
# 用法：
#   var npc = NPCManager.get_npc("xiaoyang")
#   var prompt = NPCManager.get_personality_prompt("xiaoyang")
#   var model = NPCManager.get_model("xiaoyang")
#   var display_name = NPCManager.get_display_name("xiaoyang")
#   NPCManager.list_ids() → 所有 NPC id 数组
#
# 与 ChatDialogue.NPC_PROFILES 并存：
#   - NPC_PROFILES：硬编码 NPC（项目已有角色）
#   - NPCManager：动态加载 npcs/ 目录（同学的 xiaoyang.json 等）
#   - 优先级：NPCManager > NPC_PROFILES（同名 id 以 JSON 为准）

const NPCS_DIR: String = "res://npcs/"
const DEFAULT_NPC_ID: String = "xiaoyang"

static var _cache: Dictionary = {}

static func _ensure_loaded() -> void:
	if not _cache.is_empty():
		return
	_load_all()

static func _load_all() -> void:
	_cache.clear()
	var dir = DirAccess.open(NPCS_DIR)
	if dir == null:
		push_warning("[NPCManager] 找不到目录: %s，跳过动态加载" % NPCS_DIR)
		return
	dir.list_dir_end()  # 先重置
	var files = DirAccess.get_files_at(NPCS_DIR)
	for filename in files:
		if not filename.ends_with(".json"):
			continue
		var path = NPCS_DIR + filename
		var f = FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_warning("[NPCManager] 打不开: %s" % path)
			continue
		var text = f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(text)
		if parsed == null or not parsed is Dictionary:
			push_error("[NPCManager] JSON 解析失败: %s" % path)
			continue
		var npc: Dictionary = parsed
		if not npc.has("id"):
			push_error("[NPCManager] 缺少 id 字段: %s" % path)
			continue
		var id: String = npc["id"]
		_cache[id] = npc
		print("[NPCManager] 加载 NPC: %s (%s)" % [id, npc.get("display_name", "?")])

static func list_ids() -> Array:
	_ensure_loaded()
	return _cache.keys()

static func has_npc(id: String) -> bool:
	_ensure_loaded()
	return _cache.has(id)

static func get_npc(id: String) -> Dictionary:
	_ensure_loaded()
	if not _cache.has(id):
		push_warning("[NPCManager] 找不到 NPC: %s" % id)
		return {}
	return _cache[id]

static func get_personality_prompt(id: String) -> String:
	var npc = get_npc(id)
	return npc.get("personality_prompt", "")

static func get_model(id: String) -> String:
	var npc = get_npc(id)
	return npc.get("model", "glm-5.3-flash")

static func get_display_name(id: String) -> String:
	var npc = get_npc(id)
	return npc.get("display_name", id)

static func get_avatar_color(id: String) -> String:
	var npc = get_npc(id)
	return npc.get("avatar_color", "#FFFFFF")

static func get_speech_style(id: String) -> Dictionary:
	var npc = get_npc(id)
	return npc.get("speech_style", {"max_words": 60, "use_emotion": true})
