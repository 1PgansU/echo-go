# RelationshipQuestUI.gd — 好感任务面板（点击 WorldUI 顶部 💝 图标 或按 K 打开）
# 当玩家站在 NPC 附近，打开"好感任务"列表
# 完成任: 好感度 +delta 点（不同任务分数不同）
extends CanvasLayer

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# K：打开/关闭任务面板（保留快捷键：玩家没图标按钮也能用键盘）
	if event.keycode == KEY_K:
		var panel: PanelContainer = find_child("Panel", true, false) as PanelContainer
		if panel == null:
			return  # 还没初始化完成，忽略
		if panel.visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()

var _current_npc: String = ""
var _is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_build_panel()
	_close()

func open_for(npc_id: String) -> void:
	_current_npc = npc_id
	_refresh()
	_open()

func _open() -> void:
	_refresh()
	$Panel.visible = true
	_is_open = true

func _close() -> void:
	$Panel.visible = false
	_is_open = false

# ============================================================
# 任务库（npc_id → [任务列表]）
# ============================================================
const QUESTS := {
	"xiaoyang": [
		{"id": "ym_ball", "title": "🏀 约小羊打球", "desc": "主动约他单挑一场", "delta": 4, "icon": "🏀"},
		{"id": "ym_game", "title": "🎮 一起开黑", "desc": "组队打几把游戏", "delta": 3, "icon": "🎮"},
		{"id": "ym_snack", "title": "🍦 买冰淇淋", "desc": "路过便利店给他带一根", "delta": 2, "icon": "🍦"},
		{"id": "ym_late", "title": "🌙 深夜聊天", "desc": "睡不着，发消息骚扰他", "delta": 5, "icon": "🌙"},
	],
	"xiaoyou": [
		{"id": "yy_shop", "title": "🛍️ 一起去逛街", "desc": "约她逛两个小时的街", "delta": 4, "icon": "🛍️"},
		{"id": "yy_tea", "title": "🍹 请喝奶茶", "desc": "买两杯她最爱的口味", "delta": 3, "icon": "🍹"},
		{"id": "yy_photo", "title": "📸 帮她拍照", "desc": "认真给她拍一组照片", "delta": 3, "icon": "📸"},
		{"id": "yy_secret", "title": "🤫 听她说秘密", "desc": "认真听她倾诉，不打断", "delta": 5, "icon": "🤫"},
	],
	"father": [
		{"id": "fa_tea", "title": "🍵 买好茶叶", "desc": "记得他喜欢龙井", "delta": 4, "icon": "🍵"},
		{"id": "fa_help", "title": "🔧 帮忙干活", "desc": "主动帮他做点家务", "delta": 3, "icon": "🔧"},
		{"id": "fa_walk", "title": "🚶 陪他散步", "desc": "饭后一起去楼下走走", "delta": 3, "icon": "🚶"},
		{"id": "fa_talk", "title": "💬 认真聊天", "desc": "不玩手机，好好聊一次", "delta": 5, "icon": "💬"},
	],
	"mother": [
		{"id": "mo_cook", "title": "🍳 帮她做饭", "desc": "主动进厨房帮忙", "delta": 4, "icon": "🍳"},
		{"id": "mo_tea", "title": "🫖 泡杯热茶", "desc": "给她泡杯她爱喝的茶", "delta": 3, "icon": "🫖"},
		{"id": "mo_clean", "title": "🧹 打扫房间", "desc": "主动把房间收拾干净", "delta": 3, "icon": "🧹"},
		{"id": "mo_talk", "title": "🤗 认真倾听", "desc": "不顶嘴，好好听她说话", "delta": 5, "icon": "🤗"},
	],
	"brother": [
		{"id": "br_game", "title": "🎮 带他上分", "desc": "用实力带他赢一局", "delta": 4, "icon": "🎮"},
		{"id": "br_snack", "title": "🍕 买零食", "desc": "偷偷给他买包薯片", "delta": 2, "icon": "🍕"},
		{"id": "br_cover", "title": "🛡️ 帮他瞒着", "desc": "他闯祸了，帮他说话", "delta": 3, "icon": "🛡️"},
	],
	"classmate": [
		{"id": "cm_study", "title": "📚 一起自习", "desc": "约他去图书馆学习", "delta": 4, "icon": "📚"},
		{"id": "cm_lunch", "title": "🍱 一起吃饭", "desc": "叫上他一起买饭", "delta": 2, "icon": "🍱"},
		{"id": "cm_notes", "title": "📝 借笔记", "desc": "主动把笔记借给他抄", "delta": 3, "icon": "📝"},
	],
	"teacher": [
		{"id": "tc_question", "title": "❓ 主动提问", "desc": "上课积极举手回答问题", "delta": 4, "icon": "❓"},
		{"id": "tc_help", "title": "📦 帮忙搬东西", "desc": "看到老师搬东西，主动帮忙", "delta": 3, "icon": "📦"},
		{"id": "tc_respect", "title": "🙏 礼貌问好", "desc": "见到老师主动问好", "delta": 2, "icon": "🙏"},
	],
	"crush": [
		{"id": "cr_drink", "title": "🥤 送杯奶茶", "desc": "鼓起勇气递给她一杯奶茶", "delta": 6, "icon": "🥤"},
		{"id": "cr_help", "title": "📚 帮忙借书", "desc": "帮她去图书馆借她想要的书", "delta": 5, "icon": "📚"},
		{"id": "cr_walk", "title": "🚶 一起走", "desc": "找借口一起走一段路", "delta": 4, "icon": "🚶"},
		{"id": "cr_notice", "title": "👀 默默关注", "desc": "远远看着她，不打扰", "delta": 2, "icon": "👀"},
		{"id": "cr_confess", "title": "💌 表白", "desc": "鼓起勇气……说出那句话", "delta": 20, "icon": "💌"},
	],
	"partner": [
		{"id": "pt_reach", "title": "🤝 主动联系", "desc": "发一条消息，哪怕只是问好", "delta": 5, "icon": "🤝"},
		{"id": "pt_apology", "title": "💬 道歉", "desc": "认真为之前的事道歉", "delta": 6, "icon": "💬"},
		{"id": "pt_memory", "title": "📸 回忆相册", "desc": "发一张以前的合照", "delta": 4, "icon": "📸"},
	],
}

const NPC_DISPLAY := {
	"xiaoyang": "小羊 🐑", "xiaoyou": "小柚 🍊",
	"father": "👨 爸爸", "mother": "👩 妈妈",
	"brother": "👦 弟弟", "classmate": "🧑 同学",
	"teacher": "👨‍🏫 班主任", "crush": "💝 TA", "partner": "💔 TA",
}

# ============================================================
# 构建面板
# ============================================================
func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -240
	panel.offset_right = 260
	panel.offset_bottom = 240
	add_child(panel)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.97, 0.94, 0.85)
	bg.corner_radius_top_left = 16
	bg.corner_radius_top_right = 16
	bg.corner_radius_bottom_left = 16
	bg.corner_radius_bottom_right = 16
	bg.border_width_left = 2
	bg.border_width_right = 2
	bg.border_width_top = 2
	bg.border_width_bottom = 2
	bg.border_color = Color(0.45, 0.27, 0.20, 0.6)
	panel.add_theme_stylebox_override("panel", bg)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)
	pad.add_child(v)

	# 标题栏
	var title_h := HBoxContainer.new()
	title_h.add_theme_constant_override("separation", 10)
	v.add_child(title_h)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "💝 好感任务"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.35, 0.22, 0.12))
	title_h.add_child(title)

	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_h.add_child(title_spacer)

	var hint := Label.new()
	hint.text = "按 [K] 关闭"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.45, 0.30))
	title_h.add_child(hint)

	v.add_child(HSeparator.new())

	# 任务列表区域
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	var quest_v := VBoxContainer.new()
	quest_v.name = "QuestList"
	quest_v.add_theme_constant_override("separation", 8)
	scroll.add_child(quest_v)

	# 底部说明
	var footer := Label.new()
	footer.text = "靠近 NPC 按 [K] 查看专属任务，完成即可提升好感 🎯"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(0.55, 0.45, 0.30))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(footer)

# ============================================================
# 刷新任务列表
# ============================================================
func _refresh() -> void:
	var panel: PanelContainer = find_child("Panel", true, false) as PanelContainer
	if panel == null:
		return
	var list: VBoxContainer = find_child("QuestList", true, false) as VBoxContainer
	var title: Label = find_child("TitleLabel", true, false) as Label
	if list == null or title == null:
		return

	# 清空列表
	for c in list.get_children():
		c.queue_free()

	if _current_npc == "":
		title.text = "💝 好感任务"
		var tip := Label.new()
		tip.text = "靠近某个 NPC，再按 [K] 查看专属任务"
		tip.add_theme_font_size_override("font_size", 14)
		tip.add_theme_color_override("font_color", Color(0.60, 0.60, 0.70))
		list.add_child(tip)
		return

	var npc_name: String = NPC_DISPLAY.get(_current_npc, _current_npc)
	title.text = "💝 %s 的任务" % npc_name

	var quests: Array = QUESTS.get(_current_npc, [])
	if quests.is_empty():
		var tip := Label.new()
		tip.text = "这个关系暂时没有专属任务……"
		tip.add_theme_font_size_override("font_size", 13)
		tip.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
		list.add_child(tip)
		return

	for q in quests:
		var row := _build_quest_row(q)
		list.add_child(row)

func _build_quest_row(q: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(540, 64)

	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(1.0, 0.97, 0.90)
	rs.corner_radius_top_left = 10
	rs.corner_radius_top_right = 10
	rs.corner_radius_bottom_left = 10
	rs.corner_radius_bottom_right = 10
	rs.border_color = Color(0.70, 0.55, 0.35)
	rs.border_width_left = 1
	rs.border_width_top = 1
	rs.border_width_right = 1
	rs.border_width_bottom = 1
	row.add_theme_stylebox_override("panel", rs)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	row.add_child(pad)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	pad.add_child(h)

	# 图标
	var icon := Label.new()
	icon.text = str(q.get("icon", "📌"))
	icon.add_theme_font_size_override("font_size", 26)
	icon.custom_minimum_size = Vector2(36, 36)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(icon)

	# 任务名 + 描述
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 3)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)

	var title_lbl := Label.new()
	title_lbl.text = str(q.get("title", "任务"))
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.25, 0.18, 0.10))
	mid.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = str(q.get("desc", ""))
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.45, 0.35, 0.25))
	mid.add_child(desc_lbl)

	# 加分标签 + 完成按钮
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(right)

	var delta_lbl := Label.new()
	var d: int = int(q.get("delta", 0))
	delta_lbl.text = "+%d ❤️" % d
	delta_lbl.add_theme_font_size_override("font_size", 15)
	delta_lbl.add_theme_color_override("font_color", Color(1.00, 0.40, 0.50))
	right.add_child(delta_lbl)

	var btn := Button.new()
	btn.text = "完成"
	btn.custom_minimum_size = Vector2(60, 30)
	btn.pressed.connect(_on_quest_done.bind(q))
	right.add_child(btn)

	return row

func _on_quest_done(q: Dictionary) -> void:
	var npc_id: String = _current_npc
	var delta: int = int(q.get("delta", 0))

	# 好感度变化
	var matrix_script = load("res://scripts/offline/RelationshipMatrix.gd")
	var matrix = matrix_script.get_instance() if matrix_script else null
	if matrix:
		matrix.mutate(npc_id, "partner", delta)
		var new_rel = matrix.pair(npc_id, "partner")
		var new_type: String = str(new_rel.get("type", ""))
		var pts: int = int(new_rel.get("points", 0))
		_show_done_popup(q, delta, npc_id, pts, new_type)
		_close()
	else:
		_show_simple_popup("完成！", "+%d 好感" % delta)

func _show_done_popup(q: Dictionary, delta: int, npc_id: String, pts: int, new_type: String) -> void:
	var popup := PanelContainer.new()
	popup.anchor_left = 0.5
	popup.anchor_top = 0.5
	popup.anchor_right = 0.5
	popup.anchor_bottom = 0.5
	popup.offset_left = -180
	popup.offset_top = -100
	popup.offset_right = 180
	popup.offset_bottom = 100
	popup.z_index = 9999
	add_child(popup)

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	ps.corner_radius_top_left = 16
	ps.corner_radius_top_right = 16
	ps.corner_radius_bottom_left = 16
	ps.corner_radius_bottom_right = 16
	ps.border_width_left = 2
	ps.border_width_right = 2
	ps.border_width_top = 2
	ps.border_width_bottom = 2
	ps.border_color = Color(1.0, 0.4, 0.5, 0.7)
	popup.add_theme_stylebox_override("panel", ps)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 20)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	popup.add_child(pad)
	pad.add_child(v)

	var icon_lbl := Label.new()
	icon_lbl.text = str(q.get("icon", "✅"))
	icon_lbl.add_theme_font_size_override("font_size", 36)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(icon_lbl)

	var done_lbl := Label.new()
	done_lbl.text = "任务完成！"
	done_lbl.add_theme_font_size_override("font_size", 18)
	done_lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	done_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(done_lbl)

	var delta_lbl := Label.new()
	delta_lbl.text = "+%d 好感 ❤️" % delta
	delta_lbl.add_theme_font_size_override("font_size", 20)
	delta_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.5))
	delta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(delta_lbl)

	var type_lbl := Label.new()
	type_lbl.text = "关系：%s（%d 分）" % [new_type, pts]
	type_lbl.add_theme_font_size_override("font_size", 14)
	type_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.90))
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(type_lbl)

	# 自动消失（2秒后销毁）
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(func():
		if popup and popup.is_inside_tree():
			popup.queue_free())

func _show_simple_popup(title_txt: String, sub_txt: String) -> void:
	pass  # _show_done_popup already covers this
