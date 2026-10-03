# SaveManager：自动存档管理
extends Node

const SAVE_PATH := "user://save_slot_1.json"


func _ready() -> void:
	pass


# === 是否有存档 ===
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# === 保存 ===
func save(data: Dictionary) -> void:
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[SaveManager] Failed to open save for write")
		return
	# 加个时间戳
	var enriched = data.duplicate()
	enriched["saved_at"] = Time.get_unix_time_from_system()
	var json_text = JSON.stringify(enriched, "  ")
	f.store_string(json_text)
	f.close()
	print("[SaveManager] ✓ Saved to %s" % SAVE_PATH)


# === 加载 ===
func load_save() -> Dictionary:
	if not has_save():
		return {}
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text = f.get_as_text()
	f.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_warning("[SaveManager] JSON parse error: %s" % json.get_error_message())
		return {}
	return json.data


# === 删除存档（重新开始） ===
func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("[SaveManager] Save deleted")


# === 友好时间显示（"2 天前" / "5 小时前"） ===
func get_save_time_label() -> String:
	var data = load_save()
	if data.is_empty() or not data.has("saved_at"):
		return ""
	var saved_at: float = data.get("saved_at", 0)
	var now = Time.get_unix_time_from_system()
	var delta = now - saved_at
	if delta < 60:
		return "刚刚"
	elif delta < 3600:
		return "%d 分钟前" % int(delta / 60)
	elif delta < 86400:
		return "%d 小时前" % int(delta / 3600)
	elif delta < 86400 * 7:
		return "%d 天前" % int(delta / 86400)
	else:
		return "%d 周前" % int(delta / 86400 / 7)