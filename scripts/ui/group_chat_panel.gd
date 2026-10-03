# GroupChatPanel.gd — 群聊窗口（手机样式）
"""
在 WorldUI 里点群图标 → 弹出本面板。
- 智能选话题（GroupChatEngine.pick_topic_for_group）
- 玩家可发言 → 群里 NPC 自动接话（LLM 优先 / 模板兜底）
- 未读 / 已读追踪
- 持久化
"""
extends CanvasLayer

const WIDTH := 480
const HEIGHT := 680

# 当前群（外部可设置）
var current_group_key: String = "group_close"

var _is_open: bool = false
var _panel: Control = null
var _chat_list: VBoxContainer = null
var _group_label: Label = null  # 顶部群名（供 _set_group_key 改）
var _status_label: Label = null  # 底部状态
var _input_box: LineEdit = null
var _awaiting_reply: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 94
	visible = false


# 公开：从外部打开 + 指定群
func open_group(group_key: String) -> void:
	current_group_key = group_key
	open()


func open() -> void:
	_is_open = true
	visible = true
	if _panel:
		_panel.queue_free()
	_build_ui()
	_load_history()
	# 进入群聊即视为已读
	var eng = _engine()
	if eng and eng.has_method("mark_read"):
		eng.mark_read(current_group_key)


func _engine() -> Node:
	var EngineScript = load("res://scripts/offline/GroupChatEngine.gd")
	return EngineScript.get_instance() if EngineScript else null


# === 构建微信风整 UI ===
func _build_ui() -> void:
	# 半透明黑底
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# 右下角"手机"
	var phone_holder := Control.new()
	phone_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	phone_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(phone_holder)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	_panel.anchor_left = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -WIDTH - 30
	_panel.offset_top = -HEIGHT - 30
	_panel.offset_right = -30
	_panel.offset_bottom = -30
	phone_holder.add_child(_panel)

	# 微信浅米色背景
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.96, 0.93)
	style.border_color = Color(0.30, 0.30, 0.30)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	_panel.add_theme_stylebox_override("panel", style)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 0)
	_panel.add_child(root_v)

	# === 顶部群信息栏（微信绿）===
	var top := PanelContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.18, 0.50, 0.36)
	top.add_theme_stylebox_override("panel", top_style)
	root_v.add_child(top)

	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 12)
	top.add_child(top_h)

	# ⬅ 返回按钮：回到群列表
	var back := Button.new()
	back.text = "⬅"
	back.custom_minimum_size = Vector2(40, 30)
	back.pressed.connect(_on_back_pressed)
	top_h.add_child(back)

	_group_label = Label.new()
	var eng2 = _engine()
	var grp_name: String = ""
	if eng2:
		var groups: Dictionary = eng2.call("get_chat_groups")
		grp_name = groups.get(current_group_key, {}).get("name", "群聊")
	_group_label.text = grp_name
	_group_label.add_theme_font_size_override("font_size", 18)
	_group_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_group_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(_group_label)

	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(40, 30)
	close.pressed.connect(_close)
	top_h.add_child(close)

	# === 消息滚动区 ===
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_v.add_child(scroll)

	_chat_list = VBoxContainer.new()
	_chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_list.add_theme_constant_override("separation", 10)
	var chat_pad := MarginContainer.new()
	chat_pad.add_theme_constant_override("margin_left", 12)
	chat_pad.add_theme_constant_override("margin_right", 12)
	chat_pad.add_theme_constant_override("margin_top", 12)
	chat_pad.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(chat_pad)
	chat_pad.add_child(_chat_list)

	# === 底部输入框 ===
	var bottom := PanelContainer.new()
	bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bot_style := StyleBoxFlat.new()
	bot_style.bg_color = Color(0.93, 0.94, 0.92)
	bottom.add_theme_stylebox_override("panel", bot_style)
	root_v.add_child(bottom)

	var bot_v := VBoxContainer.new()
	bot_v.add_theme_constant_override("separation", 4)
	var bot_pad := MarginContainer.new()
	bot_pad.add_theme_constant_override("margin_left", 12)
	bot_pad.add_theme_constant_override("margin_right", 12)
	bot_pad.add_theme_constant_override("margin_top", 10)
	bot_pad.add_theme_constant_override("margin_bottom", 10)
	bottom.add_child(bot_pad)
	bot_pad.add_child(bot_v)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
	bot_v.add_child(_status_label)

	var bot_h := HBoxContainer.new()
	bot_h.add_theme_constant_override("separation", 10)
	bot_v.add_child(bot_h)

	_input_box = LineEdit.new()
	_input_box.placeholder_text = "说点什么…"
	_input_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_box.custom_minimum_size = Vector2(0, 36)
	_input_box.text_submitted.connect(_on_input_submitted)
	bot_h.add_child(_input_box)

	var send_btn := Button.new()
	send_btn.text = "发送"
	send_btn.custom_minimum_size = Vector2(60, 36)
	send_btn.pressed.connect(_on_send)
	bot_h.add_child(send_btn)


# === 加载历史（或首次进入生成一波）===
func _load_history() -> void:
	for c in _chat_list.get_children():
		c.queue_free()

	var eng = _engine()
	if eng == null:
		_add_system_bubble("❌ 群聊引擎加载失败")
		return

	var hist: Array = eng.get_history(current_group_key)
	if hist.is_empty():
		# 第一次进入 → 智能选话题 + 生成
		var topic: String = eng.pick_topic_for_group(current_group_key)
		var lines: Array = eng.generate_conversation(current_group_key, topic, randi_range(4, 7))
		# 顶部加一个"话题"系统提示
		if topic != "":
			_add_system_bubble("话题：%s" % topic)
		for msg in lines:
			eng.append_message(current_group_key, msg)
		hist = eng.get_history(current_group_key)

	for msg in hist:
		_add_message_bubble(msg)


# === 玩家发送 ===
func _on_input_submitted(_t: String) -> void:
	_on_send()


func _on_send() -> void:
	if _awaiting_reply:
		return
	var text: String = _input_box.text.strip_edges()
	if text.is_empty():
		return
	_input_box.clear()
	_send_player_message(text)


func _send_player_message(text: String) -> void:
	var eng = _engine()
	if eng == null:
		return

	var msg := {
		"speaker": "partner",
		"speaker_name": "你",
		"avatar": "🙂",
		"msg": text,
		"by_player": true,
		"ts": Time.get_ticks_msec(),
	}
	eng.append_message(current_group_key, msg)
	_add_message_bubble(msg)

	# 加群组成员好感度（参与感的反馈）
	var matrix_script = load("res://scripts/offline/RelationshipMatrix.gd")
	if matrix_script:
		var matrix = matrix_script.get_instance()
		var members: Array = eng.get_members(current_group_key)
		for m in members:
			if matrix.has_method("mutate"):
				matrix.mutate(m, "partner", 1)

	# 触发 NPC 接话
	_status_label.text = "💭 群里正在讨论..."
	_awaiting_reply = true
	var replies: Array = await eng.generate_replies_after_player(current_group_key, text)
	_awaiting_reply = false
	_status_label.text = ""
	for r in replies:
		eng.append_message(current_group_key, r)
		_add_message_bubble(r)
		await get_tree().create_timer(0.4).timeout


# === 渲染一条消息 ===
func _add_message_bubble(msg: Dictionary) -> void:
	var speaker: String = msg.get("speaker", "")
	var is_me: bool = (speaker == "partner")

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	if is_me:
		row.alignment = BoxContainer.ALIGNMENT_END
	_chat_list.add_child(row)

	# 头像（左侧 / 右侧）
	var avatar := Label.new()
	avatar.text = msg.get("avatar", "🙂")
	avatar.add_theme_font_size_override("font_size", 28)
	if not is_me:
		row.add_child(avatar)
	else:
		row.add_child(avatar)  # 简化：左右都用 emoji

	# 气泡
	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.custom_minimum_size = Vector2(120, 50)
	var bstyle := StyleBoxFlat.new()
	if is_me:
		bstyle.bg_color = Color(0.55, 0.83, 0.45)
	else:
		bstyle.bg_color = Color(0.95, 0.97, 0.85)
	bstyle.corner_radius_top_left = 8
	bstyle.corner_radius_top_right = 8
	bstyle.corner_radius_bottom_left = 8
	bstyle.corner_radius_bottom_right = 8
	bstyle.border_color = Color(0.80, 0.80, 0.75)
	bstyle.border_width_left = 1
	bstyle.border_width_top = 1
	bstyle.border_width_right = 1
	bstyle.border_width_bottom = 1
	bubble.add_theme_stylebox_override("panel", bstyle)
	row.add_child(bubble)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	var inner_pad := MarginContainer.new()
	inner_pad.add_theme_constant_override("margin_left", 12)
	inner_pad.add_theme_constant_override("margin_right", 12)
	inner_pad.add_theme_constant_override("margin_top", 8)
	inner_pad.add_theme_constant_override("margin_bottom", 8)
	bubble.add_child(inner_pad)
	inner_pad.add_child(inner)

	# 名字（玩家自己的不显示名字，只显示"我"）
	if not is_me:
		var name := Label.new()
		name.text = msg.get("speaker_name", "")
		name.add_theme_font_size_override("font_size", 11)
		name.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50))
		inner.add_child(name)

	# 正文
	var body := Label.new()
	body.text = msg.get("msg", "")
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(0.10, 0.10, 0.10))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(body)

	# 滚到底部
	_scroll_to_bottom()


func _add_system_bubble(text: String) -> void:
	var lbl := Label.new()
	lbl.text = "— " + text + " —"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.45, 0.42, 0.38))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_list.add_child(lbl)


func _scroll_to_bottom() -> void:
	call_deferred("_do_scroll")


func _do_scroll() -> void:
	if _chat_list == null:
		return
	var scroll = _chat_list.get_parent()
	if scroll == null:
		return
	while scroll and not (scroll is ScrollContainer):
		scroll = scroll.get_parent()
	if scroll:
		var sc: ScrollContainer = scroll
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _close() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
	_is_open = false
	visible = false


func _on_back_pressed() -> void:
	# 返回 = 关闭当前群聊窗口（露出下面的 ChatAppPanel 群列表）
	_close()