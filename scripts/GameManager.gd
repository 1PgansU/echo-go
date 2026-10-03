# 全局游戏管理器（Autoload 模式：作为单例手动加载到 Main）
extends Node

# 全性格
var personality: PersonalityEngine

# 当前正在进行的 scene（仅作 UI 显示用）
var current_scene_id: String = ""

# 进度（玩家完成的对话历史）
var history: Array = []

# === 关系分（每个 NPC 一个：用于心情值/互动）
# 例如 "xiaoyang": {"points": 3, "mood": "happy"}
var relationship_points: Dictionary = {}

# 数据
var scenes_data: Dictionary = {}

# 对话 UI 引用
var dialogue_ui: Control = null
var chat_dialogue: Control = null  # ChatDialogue.tscn 实例（聊天模式用）

# 信号
signal personality_updated
signal scene_changed(new_scene_id)
signal relationship_changed(npc_id: String, points: int, mood: String)

# === 玩家开游戏次数（用于派信） ===
const SESSION_COUNT_PATH := "user://session_count.json"

# === 是否第一次启动（新游戏/读档判定）===
# - true: 首次启动 / 玩家刚点了"新游戏"，需要应用初始亲密度 + 初始日记
# - false: 玩家点了"继续上次"，不要动这些写入，应该用存档数据
var first_run: bool = true

func _ready() -> void:
	personality = PersonalityEngine.new()
	add_child(personality)
	load_scenes_data()
	# 启动时根据有没有存档决定 first_run
	var save_path = "user://save_slot_1.json"
	if FileAccess.file_exists(save_path):
		first_run = false
		print("[GameManager] 检测到存档 → first_run = false")
	else:
		first_run = true
		print("[GameManager] 无存档 → first_run = true")

func register_dialogue_ui(ui: Control) -> void:
	dialogue_ui = ui
	print("[GameManager] DialogueUI registered")

func register_chat_dialogue(ui: Control) -> void:
	chat_dialogue = ui
	print("[GameManager] ChatDialogue registered")

func get_chat_dialogue() -> Control:
	if chat_dialogue == null:
		# 兜底：动态加载
		var scene = load("res://scenes/ChatDialogue.tscn")
		if scene:
			chat_dialogue = scene.instantiate()
			# 挂在 Main 的 DialogueLayer 上
			var main = get_tree().get_first_node_in_group("main")
			if main:
				var layer = main.get_node_or_null("DialogueLayer")
				if layer:
					layer.add_child(chat_dialogue)
	return chat_dialogue

func load_scenes_data() -> void:
	var path = "res://data/scenes.json"
	if not FileAccess.file_exists(path):
		push_error("scenes.json not found at %s" % path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open scenes.json")
		return
	var text = file.get_as_text()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("JSON parse error: %s" % json.get_error_message())
		return
	scenes_data = json.data
	print("[GameManager] Loaded %d scenes" % scenes_data.size())

# === 玩家开游戏次数 ===
func get_session_count() -> int:
	var f = FileAccess.open(SESSION_COUNT_PATH, FileAccess.READ)
	if f == null:
		return 1
	var text = f.get_as_text().strip_edges()
	f.close()
	if text.is_valid_int():
		return int(text)
	return 1


func record_session() -> void:
	var current = get_session_count()
	# 注意：本次会话已经预先被读过，所以这里只 +1
	# 但 Main 在读之前 get_session_count 就已经返回了本次的 number
	# 所以我们这里存的是"完成本次后的次数"，下次读会读到
	var f = FileAccess.open(SESSION_COUNT_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Cannot write session count")
		return
	f.store_string(str(current + 1))
	f.close()
	print("[GameManager] Session recorded, next session will be #%d" % (current + 1))
	# 同步自动存档（让 continue 能反映最新进度）
	auto_save()

func get_scene(scene_id: String) -> Dictionary:
	return scenes_data.get(scene_id, {})

func apply_choice(scene_id: String, choice_id: String) -> Dictionary:
	var scene = get_scene(scene_id)
	if scene.is_empty():
		push_error("Scene not found: %s" % scene_id)
		return {}

	var choice = null
	for c in scene.get("choices", []):
		if c.get("id", "") == choice_id:
			choice = c
			break

	if choice == null:
		push_error("Choice not found: %s" % choice_id)
		return {}

	if choice.has("personality_delta"):
		personality.apply_delta(choice.get("personality_delta"))

	# 不重复记录同一 scene 的多次选择（如允许重玩）
	if not history.any(func(h): return h.get("scene_id", "") == scene_id):
		history.append({
			"scene_id": scene_id,
			"choice_id": choice_id,
			"label": choice.get("label", ""),
			"text": choice.get("text", "")
		})

	current_scene_id = scene_id
	emit_signal("personality_updated")
	emit_signal("scene_changed", scene_id)

	# 自动存档
	auto_save()

	return choice

func reset() -> void:
	personality.reset()
	current_scene_id = ""
	history = []
	relationship_points = {}
	emit_signal("personality_updated")


# === 关系分 + 心情映射 ===
func add_relationship(npc_id: String, delta: int = 1) -> void:
	if npc_id == "":
		return
	if not relationship_points.has(npc_id):
		relationship_points[npc_id] = {"points": 0, "mood": "neutral"}
	var entry: Dictionary = relationship_points[npc_id]
	entry["points"] = int(entry.get("points", 0)) + delta
	entry["mood"] = _mood_for_points(int(entry["points"]))
	relationship_points[npc_id] = entry
	print("[GameManager] 关系 %s: %d 分 (%s)" % [npc_id, entry["points"], entry["mood"]])
	emit_signal("relationship_changed", npc_id, int(entry["points"]), entry["mood"])


func get_relationship(npc_id: String) -> Dictionary:
	return relationship_points.get(npc_id, {"points": 0, "mood": "neutral"})


# 心情映射
func _mood_for_points(p: int) -> String:
	if p <= 0:
		return "neutral"   # 😐
	elif p <= 2:
		return "smile"     # 🙂
	elif p <= 4:
		return "happy"     # 😄
	else:
		return "excited"   # 🤩

# === 存档相关 ===
func get_save_data() -> Dictionary:
	return {
		"personality_traits": personality.traits.duplicate() if personality else {},
		"history": history.duplicate(),
		"current_scene_id": current_scene_id,
		"session_count": get_session_count(),
		"relationship_points": relationship_points.duplicate()
	}


func apply_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	if personality and data.has("personality_traits"):
		var traits = data.get("personality_traits", {})
		for k in traits.keys():
			if k in personality.traits:
				personality.traits[k] = traits[k]
	if data.has("history"):
		history = data.get("history", []).duplicate()
	if data.has("current_scene_id"):
		current_scene_id = data.get("current_scene_id", "")
	if data.has("relationship_points"):
		relationship_points = data.get("relationship_points", {}).duplicate()
	emit_signal("personality_updated")


func apply_trait_delta(delta: Dictionary) -> void:
	if personality == null:
		return
	for k in delta.keys():
		if k in personality.traits:
			personality.traits[k] = personality.traits[k] + delta[k]
	emit_signal("personality_updated")


func auto_save() -> void:
	var sm = get_node_or_null("/root/SaveManager")
	if sm:
		sm.save(get_save_data())


# === 退出游戏：通知 OfflineClock 记录退出时间 ===
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var clock = get_node_or_null("/root/Main/OfflineClock")
		if clock == null:
			clock = get_node_or_null("/root/OfflineClock")
		if clock and clock.has_method("on_quit"):
			clock.call("on_quit")