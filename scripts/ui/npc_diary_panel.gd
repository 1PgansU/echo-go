# npc_diary_panel.gd — 偷看 NPC 私人日记面板
# 入口：WorldUI 顶部 📔 图标
# 流程：NPC 列表 → 选中后展示该 NPC 日记（按亲密度门控可见条数）
extends CanvasLayer

# 玩家 id（用于查 RelationshipMatrix）
const PLAYER_ID := "partner"

const NPC_DISPLAY := {
	"father":   {"name": "爸爸",    "icon": "👨", "color": Color(0.55, 0.45, 0.35)},
	"mother":   {"name": "妈妈",    "icon": "👩", "color": Color(0.85, 0.55, 0.55)},
	"brother":  {"name": "弟弟",    "icon": "👦", "color": Color(0.45, 0.70, 0.50)},
	"classmate":{"name": "同学",    "icon": "👦", "color": Color(0.50, 0.60, 0.80)},
	"teacher":  {"name": "班主任",  "icon": "👨‍🏫", "color": Color(0.40, 0.40, 0.55)},
	"crush":    {"name": "TA",      "icon": "💝", "color": Color(0.95, 0.60, 0.75)},
	"partner":  {"name": "TA",      "icon": "💔", "color": Color(0.65, 0.45, 0.55)},
	"xiaoyang": {"name": "小羊",    "icon": "🐑", "color": Color(0.95, 0.85, 0.55)},
	"xiaoyou":  {"name": "小柚",    "icon": "🍊", "color": Color(0.95, 0.65, 0.30)},
}

# UI 尺寸
const PICKER_W := 760.0
const PICKER_H := 540.0
const DETAIL_W := 820.0
const DETAIL_H := 620.0

var _root: Control = null  # 整个面板的根节点
var _is_open: bool = false
var _current_npc: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	visible = false


# === 入口 ===
func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_build_picker()


# 兼容旧代码（WorldUI 还在调 _open）
func _open() -> void:
	open()


func close() -> void:
	_is_open = false
	visible = false
	_clear_root()


# 兼容旧代码
func _close() -> void:
	close()


# === NPC 列表 ===
func _build_picker() -> void:
	_clear_root()

	# 黑底（点击关闭）
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_click)
	add_child(dim)

	# 居中
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	_root = center

	# 主面板
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PICKER_W, PICKER_H)
	center.add_child(panel)

	# 信纸样式
	panel.add_theme_stylebox_override("panel", _make_paper_stylebox())

	# 内容
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)
	pad.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "📔 偷看 TA 的日记"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.40, 0.20, 0.15))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "你和 TA 越熟，能看到的日记越多"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.55, 0.40, 0.30))
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# NPC 网格
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	var diary: Node = _get_diary()
	for npc_id in NPC_DISPLAY.keys():
		var info: Dictionary = NPC_DISPLAY[npc_id]
		var pts: int = _get_player_points(npc_id)
		var lv: int = _points_to_level(pts)
		var total: int = diary.get_total_count(npc_id) if diary else 0
		var vis: int = diary.get_visible_count(npc_id) if diary else 0
		grid.add_child(_make_npc_card(npc_id, info, lv, total, vis))


# 卡片按钮
func _make_npc_card(npc_id: String, info: Dictionary, lv: int, total: int, vis: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(220, 90)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# 按等级染色
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.97, 0.88) if lv >= 2 else Color(0.88, 0.85, 0.80)
	style.border_color = Color(0.60, 0.45, 0.30)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)

	var hov := style.duplicate()
	hov.bg_color = Color(1.0, 0.94, 0.78) if lv >= 2 else Color(0.92, 0.88, 0.82)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)

	# 文字
	var label: String
	if lv <= 1 and total == 0:
		# 啥也没有：完全锁
		label = "%s  %s\n🔒 TA 还没开始写日记" % [info["icon"], info["name"]]
		btn.disabled = true
	elif total == 0:
		# 等级够但还没内容
		label = "%s  %s\n📓 这本日记还是空的" % [info["icon"], info["name"]]
		btn.disabled = true
	else:
		label = "%s  %s\n✏️ 看到 %d 条 / 共 %d 条" % [info["icon"], info["name"], vis, total]
		btn.pressed.connect(_open_detail.bind(npc_id))

	btn.text = label
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.20, 0.15, 0.10) if lv >= 2 else Color(0.45, 0.40, 0.35))
	return btn


# === 日记详情 ===
func _open_detail(npc_id: String) -> void:
	_current_npc = npc_id
	_clear_root()

	# 黑底
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_click)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	_root = center

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(DETAIL_W, DETAIL_H)
	center.add_child(panel)
	panel.add_theme_stylebox_override("panel", _make_paper_stylebox())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(pad)
	pad.add_child(vbox)

	# 顶部按钮行
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 8)
	vbox.add_child(top_h)

	var back := Button.new()
	back.text = "← 返回"
	back.custom_minimum_size = Vector2(80, 32)
	back.pressed.connect(_build_picker)
	top_h.add_child(back)

	var info: Dictionary = NPC_DISPLAY.get(npc_id, {"name": npc_id, "icon": "📔"})
	var title := Label.new()
	title.text = "📔 %s 的日记本" % info["name"]
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.40, 0.20, 0.15))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_h.add_child(title)

	# 装饰占位
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(80, 32)
	top_h.add_child(spacer)

	vbox.add_child(HSeparator.new())

	# 滚动
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var entries_box := VBoxContainer.new()
	entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_box.add_theme_constant_override("separation", 12)
	scroll.add_child(entries_box)

	# 取数据
	var diary: Node = _get_diary()
	if diary == null:
		entries_box.add_child(_make_empty_label("（日记系统未就绪）"))
		return
	var all_entries: Array = diary.get_diary(npc_id)
	var vis: int = diary.get_visible_count(npc_id)
	if vis == 0:
		entries_box.add_child(_make_empty_label("（你还不够了解 TA，再多聊聊天吧）"))
		return
	# 取最后 vis 条
	var show_entries: Array
	if all_entries.size() <= vis:
		show_entries = all_entries
	else:
		show_entries = all_entries.slice(all_entries.size() - vis, vis)

	if show_entries.is_empty():
		entries_box.add_child(_make_empty_label("（这本日记还是空白的……）"))
		return

	# 倒序（最新在最上面）
	for i in range(show_entries.size() - 1, -1, -1):
		_add_diary_entry(entries_box, show_entries[i])


# 一条日记卡片
func _add_diary_entry(parent: VBoxContainer, entry: Dictionary) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.97, 0.90)
	style.border_color = Color(0.70, 0.55, 0.35)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	card.add_child(pad)
	pad.add_child(inner)

	# 元信息
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 14)
	inner.add_child(meta)

	var day: int = int(entry.get("day", 0))
	var date: String = str(entry.get("date", ""))
	var weather: String = str(entry.get("weather", ""))
	var mood: String = str(entry.get("mood_label", ""))
	var with_player: bool = bool(entry.get("with_player", false))

	var head_lbl := Label.new()
	head_lbl.text = "📅 第 %d 天 · %s" % [day, date]
	head_lbl.add_theme_font_size_override("font_size", 13)
	head_lbl.add_theme_color_override("font_color", Color(0.55, 0.42, 0.28))
	meta.add_child(head_lbl)

	if weather != "":
		var w_lbl := Label.new()
		w_lbl.text = weather
		w_lbl.add_theme_font_size_override("font_size", 13)
		w_lbl.add_theme_color_override("font_color", Color(0.55, 0.42, 0.28))
		meta.add_child(w_lbl)

	if mood != "":
		var m_lbl := Label.new()
		m_lbl.text = mood
		m_lbl.add_theme_font_size_override("font_size", 13)
		m_lbl.add_theme_color_override("font_color", Color(0.55, 0.42, 0.28))
		meta.add_child(m_lbl)

	if with_player:
		var tag := Label.new()
		tag.text = "💭 想到你"
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", Color(0.85, 0.45, 0.55))
		meta.add_child(tag)

	# 正文
	var content := Label.new()
	content.text = str(entry.get("content", ""))
	content.add_theme_font_size_override("font_size", 16)
	content.add_theme_color_override("font_color", Color(0.20, 0.15, 0.10))
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(content)


# === 工具函数 ===
func _clear_root() -> void:
	# 释放所有子节点（除了 self 自己的 dim）
	for c in get_children():
		c.queue_free()
	_root = null


func _make_paper_stylebox() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.97, 0.94, 0.85)
	s.border_color = Color(0.50, 0.35, 0.20, 0.7)
	s.border_width_left = 4
	s.border_width_top = 4
	s.border_width_right = 4
	s.border_width_bottom = 4
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	return s


func _make_empty_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.55, 0.42, 0.28))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _on_dim_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


# === 数据查询 ===
func _get_diary() -> Node:
	var script: Variant = load("res://scripts/offline/NPCDiary.gd")
	if script == null:
		return null
	if not script.has_method("get_instance"):
		return null
	return script.get_instance()


func _get_player_points(npc_id: String) -> int:
	var matrix_script: Variant = load("res://scripts/offline/RelationshipMatrix.gd")
	if matrix_script == null:
		return 0
	var matrix: Node = matrix_script.get_instance() if matrix_script.has_method("get_instance") else null
	if matrix == null:
		return 0
	if not matrix.has_method("pair"):
		return 0
	var rel: Dictionary = matrix.pair(npc_id, PLAYER_ID)
	if rel == null:
		return 0
	return int(rel.get("points", 0))


func _points_to_level(p: int) -> int:
	if p >= 150: return 5
	if p >= 90:  return 4
	if p >= 50:  return 3
	if p >= 20:  return 2
	if p >= 5:   return 1
	return 0
