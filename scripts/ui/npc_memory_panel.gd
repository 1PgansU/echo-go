# NPCMemoryPanel.gd — 玩家按 Q 时打开的"最近奇遇"面板
# 走到 NPC 旁边按 Q → 看到 NPC 最近 5 场戏
extends CanvasLayer

const WIDTH := 540
const HEIGHT := 420
const MARGIN := 24
const NPC_DISPLAY := {
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

var _panel: Panel = null
var _npc_id: String = ""
var _is_open: bool = false

func _ready() -> void:
	# 监听：按 Q 打开
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80  # 介于 DialogueLayer(100) 之下、WorldUI(50) 之上
	visible = false

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# ESC 关闭
	if event.keycode == KEY_ESCAPE and _is_open:
		close()
		return
	# Q 切换（保留快捷键：玩家没图标按钮也能用键盘）
	if event.keycode == KEY_Q:
		if _is_open:
			close()
		else:
			_try_open_nearby()

# 打开"当前玩家附近 NPC"的奇遇
func _try_open_nearby() -> void:
	var player = _get_player()
	if player == null:
		return
	# 找最近的 NPC（用 NPC group 或者叫 npc_id 字段的节点）
	var npcs := get_tree().get_nodes_in_group("npc")
	if npcs.is_empty():
		# 兜底：找所有带 npc_id 字段的 Node2D
		npcs = []
		for n in get_tree().get_nodes_in_group("world_root")[0].get_children() if get_tree().get_nodes_in_group("world_root") else []:
			if n.get("npc_id") != null:
				npcs.append(n)
	if npcs.is_empty():
		print("[NPCMemoryPanel] 没找到任何 NPC")
		return
	# 取距离最近
	var closest: Node = null
	var closest_dist: float = INF
	for n in npcs:
		var d: float = (n.global_position - player.global_position).length()
		if d < closest_dist:
			closest_dist = d
			closest = n
	if closest == null or closest_dist > 200:
		print("[NPCMemoryPanel] 附近没 NPC（最近 %.0f px）" % closest_dist)
		return
	open(closest.npc_id)

func open(npc_id: String) -> void:
	_npc_id = npc_id
	if _panel == null:
		_build_panel()
		add_child(_panel)
	_refresh()
	_panel.visible = true
	_is_open = true
	visible = true

func close() -> void:
	if _panel:
		_panel.visible = false
	_is_open = false
	visible = false

func _build_panel() -> void:
	# 主面板（居中固定尺寸，Panel 而非 PanelContainer — 避免样式覆盖冲突）
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	_panel.size = Vector2(WIDTH, HEIGHT)
	# 把 Panel 居中
	var vp := get_viewport()
	if vp != null:
		var vp_size: Vector2 = vp.get_visible_rect().size
		_panel.position = Vector2((vp_size.x - WIDTH) / 2, (vp_size.y - HEIGHT) / 2)
	# Style（Panel 用 panel stylebox）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.94, 0.85)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_right = 16
	sb.corner_radius_bottom_left = 16
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.45, 0.27, 0.20, 0.6)
	sb.content_margin_left = MARGIN
	sb.content_margin_top = MARGIN
	sb.content_margin_right = MARGIN
	sb.content_margin_bottom = MARGIN
	_panel.add_theme_stylebox_override("panel", sb)
	# 内层 VBox
	var vbox := VBoxContainer.new()
	vbox.name = "RootVBox"
	vbox.add_theme_constant_override("separation", 10)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	_panel.add_child(vbox)
	# 标题
	var title := Label.new()
	title.name = "Title"
	title.text = "🌍 最近的奇遇"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.239, 0.157, 0.09))
	vbox.add_child(title)
	# 副标题
	var sub := Label.new()
	sub.name = "Sub"
	sub.text = ""
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.55, 0.45, 0.30))
	vbox.add_child(sub)
	# 滚动列表
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	vbox.add_child(scroll)
	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭 (ESC)"
	close_btn.custom_minimum_size = Vector2(120, 40)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)

func _refresh() -> void:
	if _panel == null:
		return
	var list: VBoxContainer = _panel.get_node_or_null("RootVBox/Scroll/List")
	if list == null:
		push_warning("[NPCMemoryPanel] List 没找到")
		return
	for c in list.get_children():
		c.queue_free()
	# 标题
	var npc_name: String = NPC_DISPLAY.get(_npc_id, _npc_id)
	var title: Label = _panel.get_node_or_null("RootVBox/Title")
	var sub: Label = _panel.get_node_or_null("RootVBox/Sub")
	if title:
		title.text = "🌍 %s · 最近的奇遇" % npc_name
	# 副标题
	var clock = _get_clock()
	if sub:
		if clock:
			sub.text = "现在 · Day %d · 玩家不在的时候，这里也热热闹闹的~" % clock.get_current_day()
		else:
			sub.text = "现在 · 玩家不在的时候，这里也热热闹闹的~"
	# 列表
	var events: Array = []
	if clock:
		events = clock.get_events_for(_npc_id, 5)
	if events.is_empty():
		var empty := Label.new()
		empty.text = "（暂时没有奇遇，再离线一段时间再来看看吧~）"
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
		return
	for evt in events:
		list.add_child(_build_event_card(evt))

func _build_event_card(evt: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.97, 0.90)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.corner_radius_bottom_left = 10
	sb.border_color = Color(0.70, 0.55, 0.35)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 14
	sb.content_margin_top = 10
	sb.content_margin_right = 14
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	# 内层
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)
	# 标题行：Day N · 标签
	var head := Label.new()
	var tags: Array = evt.get("tags", [])
	var tag_str: String = ""
	if not tags.is_empty():
		var tag_parts: Array = []
		for t in tags:
			tag_parts.append("#" + str(t))
		tag_str = "  ".join(tag_parts)
	head.text = "📅 Day %d   %s" % [int(evt.get("day", 0)), tag_str]
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", Color(0.55, 0.45, 0.30))
	vbox.add_child(head)
	# 摘要
	var summary := Label.new()
	summary.text = str(evt.get("summary", ""))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 15)
	summary.add_theme_color_override("font_color", Color(0.20, 0.15, 0.10))
	vbox.add_child(summary)
	# 对话节选（最多 2 句）
	var transcript: Array = evt.get("transcript", [])
	if not transcript.is_empty():
		var dialog_label := Label.new()
		var shown: Array = transcript.slice(0, min(2, transcript.size()))
		dialog_label.text = "「 " + "  ".join(shown) + " 」"
		dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dialog_label.add_theme_font_size_override("font_size", 13)
		dialog_label.add_theme_color_override("font_color", Color(0.45, 0.38, 0.28))
		vbox.add_child(dialog_label)
	return card

func _get_clock() -> Node:
	var c = get_node_or_null("/root/Main/OfflineClock")
	if c: return c
	c = get_node_or_null("/root/OfflineClock")
	if c: return c
	return null

func _get_player() -> Node:
	for n in get_tree().get_nodes_in_group("player"):
		return n
	return null
