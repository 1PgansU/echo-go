# World：单地图游戏世界，所有 NPC 都常驻，玩家自由互动
extends Node2D

# NPC 模板（World.tscn 中的预放 NPC 节点）
var _npc_templates: Array[Node] = []

func _ready() -> void:
	# 收集所有 NPC 子节点
	for child in get_children():
		if child is Area2D and child.has_method("interact"):
			_npc_templates.append(child)

	# 监听 GameManager 的 scene_changed 信号 —— 用于更新顶部标题
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		if not gm.scene_changed.is_connected(_on_scene_changed):
			gm.scene_changed.connect(_on_scene_changed)

	_update_top_title("")


# 信箱已移除：记录会话的钩子保留以兼容其他调用
func _deliver_session_letter_and_refresh() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	# 进入世界 = 新会话开始（按设计："每次开游戏"派一封信）
	if gm.has_method("record_session"):
		gm.record_session()


func _input(event: InputEvent) -> void:
	pass

func _on_scene_changed(new_scene_id: String) -> void:
	_update_top_title(new_scene_id)

func _update_top_title(scene_id: String) -> void:
	var day_label = get_node_or_null("TopBar/HBox/DayLabel")
	var scene_title = get_node_or_null("TopBar/HBox/SceneTitle")

	# 日期：显示"游戏时间"（玩家16岁那年，月份日期跟真实走）
	var tm = get_node_or_null("/root/TimeManager")
	if day_label and tm and tm.has_profile():
		day_label.text = "📅 %s" % tm.today_str()
	elif day_label:
		day_label.text = "📅 自由探索"

	# 标题：当前场景对应的 NPC 标题
	var titles := {
		"day1_family_01": "🏠 客厅里的审判",
		"day1_family_02": "👩 厨房里的叹息",
		"day1_school_01": "🏫 走廊里的笑声",
		"day2_family_02": "🎂 弟弟的生日",
		"day2_school_02": "📋 文理分科表",
		"day3_love_01":   "💌 那张纸条",
		"day3_love_02":   "💔 TA 的关心",
		"chat:xiaoyang":  "🐑 阳光下的邻居",
		"chat:xiaoyou":   "🍊 可爱的小柚"
	}
	if scene_title:
		scene_title.text = titles.get(scene_id, "🗺️ 自由探索 · 走近 NPC 按 E")

func goto_scene(_scene_id: String) -> void:
	# 保留方法签名，但已无需切换 NPC 位置
	pass