# ChatAppPanel: 微信风格聊天 App（根容器）
# 三个 tab：消息 / 通讯录（聊 + 好感度条）
# - 消息 tab：列固定群（闺蜜/家人/班级） + 最近聊过的 NPC 个人对话
# - 通讯录 tab：列所有 NPC，点开 = 启动 ChatDialogue 1v1 聊天
extends Control

# === 节点引用（.tscn 里建好） ===
@onready var tab_messages: Button = $MainPanel/VBox/TopBar/TabMessages
@onready var tab_contacts: Button = $MainPanel/VBox/TopBar/TabContacts
@onready var close_button: Button = $MainPanel/VBox/TopBar/CloseButton
@onready var messages_list: VBoxContainer = $MainPanel/VBox/MessagesPage
@onready var contacts_list: VBoxContainer = $MainPanel/VBox/ContactsPage
@onready var page_messages: Control = $MainPanel/VBox/MessagesPage
@onready var page_contacts: Control = $MainPanel/VBox/ContactsPage

# === 群配置（运行时从 GroupChatEngine 取，避免双写）===
# 注意：保留一个本地 cache，启动时从引擎同步一次
# 新增/修改群定义请改 scripts/offline/GroupChatEngine.gd
var GROUPS: Dictionary = {}

func _refresh_groups_from_engine() -> void:
	var EngineScript = load("res://scripts/offline/GroupChatEngine.gd")
	if EngineScript == null:
		return
	var eng = EngineScript.get_instance()
	if eng == null:
		return
	var src: Dictionary = eng.call("get_chat_groups")
	GROUPS.clear()
	for gid in src.keys():
		var g: Dictionary = src[gid]
		var members: Array = g.get("members", [])
		var recent: String = "（还没有消息）"
		var unread: int = 0
		if eng.has_method("get_history"):
			var hist: Array = eng.get_history(gid)
			if hist.size() > 0:
				var last: Dictionary = hist[hist.size() - 1]
				var preview: String = str(last.get("msg", ""))
				if preview.length() > 18:
					preview = preview.substr(0, 18) + "..."
				recent = "%s: %s" % [str(last.get("speaker_name", "?")), preview]
		if eng.has_method("get_unread_count"):
			unread = int(eng.get_unread_count(gid))
		GROUPS[gid] = {
			"title": g.get("name", "群聊"),
			"members": members,
			"recent": recent,
			"unread": unread,
		}

# === NPC 通讯录 ===
# 头像颜色：skin=肤色 body=衣服 hair=头发 accent=装饰
const NPC_CONTACTS := [
	{"id": "father",    "name": "爸爸",   "tag": "家人",   "signature": "好好读书。",     "skin": "#f0c89a", "body": "#3a5a8c", "hair": "#2a1a14", "accent": "#5a4a3a"},
	{"id": "mother",    "name": "妈妈",   "tag": "家人",   "signature": "吃饭了没？",     "skin": "#f5d0a8", "body": "#a85a6a", "hair": "#1a1a1a", "accent": "#d4a574"},
	{"id": "brother",   "name": "弟弟",   "tag": "家人",   "signature": "姐姐！陪我玩！", "skin": "#fdd0a0", "body": "#5fa84a", "hair": "#2a2018", "accent": "#f0c050"},
	{"id": "classmate", "name": "死党",   "tag": "同学",   "signature": "小卖部见",       "skin": "#e8b888", "body": "#2a2a2a", "hair": "#1a1a1a", "accent": "#c83a3a"},
	{"id": "teacher",   "name": "班主任", "tag": "老师",   "signature": "最近表现如何？", "skin": "#e8c098", "body": "#5a4a3a", "hair": "#3a3a3a", "accent": "#8a8a8a"},
	{"id": "crush",     "name": "TA",     "tag": "暗恋",   "signature": "（微笑）",       "skin": "#fae0c0", "body": "#d8a0c8", "hair": "#3a2a3a", "accent": "#f0a0c0"},
	{"id": "xiaoyang",  "name": "小羊",   "tag": "邻居",   "signature": "没事儿，我反正就在这儿。", "skin": "#f5d0a0", "body": "#d8c8a8", "hair": "#8a7a5a", "accent": "#ffffff"},
	{"id": "xiaoyou",   "name": "小柚",   "tag": "邻居",   "signature": "诶嘿～你来啦！", "skin": "#f5d0a0", "body": "#f0c050", "hair": "#4a3a2a", "accent": "#5fa84a"},
]

var _current_tab: String = "messages"
# NPC id → 缓存的 ImageTexture（避免每行重建）
var _portrait_cache: Dictionary = {}
# 共享的小人立绘（你画的像素小人，可选）
var _avatar_pixel: Texture2D = null

# === 像素小人生成 ===
# 优先用 assets/sprites/avatar_pixel.png（你画的小人），失败则程序生成
# 返回 ImageTexture
func _make_portrait(npc: Dictionary) -> ImageTexture:
	var id: String = npc.get("id", "")
	if _portrait_cache.has(id):
		return _portrait_cache[id]
	# 优先用你画的小人立绘（如果有）
	if _avatar_pixel == null:
		var path := "res://assets/sprites/avatar_pixel.png"
		if ResourceLoader.exists(path):
			_avatar_pixel = load(path)
	var tex: ImageTexture = null
	if _avatar_pixel != null:
		var src := _avatar_pixel.get_image()
		if src != null:
			var small := src.duplicate()
			small.resize(16, 16, Image.INTERPOLATE_NEAREST)
			tex = ImageTexture.create_from_image(small)
	if tex == null:
		# fallback: 程序生成
		tex = _make_portrait_fallback(npc)
	_portrait_cache[id] = tex
	return tex

# 程序生成 16x16 像素小人（备用）
func _make_portrait_fallback(npc: Dictionary) -> ImageTexture:
	var skin := Color(npc.get("skin", "#f0c89a"))
	var body := Color(npc.get("body", "#3a5a8c"))
	var hair := Color(npc.get("hair", "#2a1a14"))
	var accent := Color(npc.get("accent", "#5a4a3a"))
	var bg := Color(0.95, 0.88, 0.72, 1)  # 头像背景浅米色

	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	# 16x16 像素布局（1=skin 2=body 3=hair 4=accent 0=bg）
	# 0=空 1=皮肤 2=衣 3=发 4=装饰
	var P := [
		"0000000000000000",
		"0000033333000000",  # 头顶发
		"0000322223300000",  # 额头 + 头发边
		"0000341111430000",  # 脸
		"0000311111140000",  # 眼1+脸+眼2（4=眼白/瞳）
		"0000311141140000",  # 笑嘴/腮
		"0000311111140000",  # 脸
		"0000022222200000",  # 脖子
		"0000224224220000",  # 衣领/肩
		"0000222222220000",  # 衣
		"0000224422220000",  # 衣饰
		"0000222222220000",  # 衣
		"0000222222220000",  # 衣
		"0000022222200000",  # 衣摆
		"0000000000000000",
		"0000000000000000",
	]
	for y in size:
		for x in size:
			var ch: String = str(P[y][x])
			match ch:
				"1": img.set_pixel(x, y, skin)
				"2": img.set_pixel(x, y, body)
				"3": img.set_pixel(x, y, hair)
				"4": img.set_pixel(x, y, accent)
	var tex := ImageTexture.create_from_image(img)
	return tex

func _ready() -> void:
	tab_messages.pressed.connect(_on_tab_messages_pressed)
	tab_contacts.pressed.connect(_on_tab_contacts_pressed)
	close_button.pressed.connect(_on_close_pressed)

	# 强制覆盖 MainPanel 的背景为完全不透明的浅米色（不依赖 .tscn 里的 PanelSB 孤儿节点）
	var main_panel := get_node_or_null("MainPanel") as PanelContainer
	if main_panel:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.97, 0.95, 0.88, 1)
		sb.border_color = Color(0.80, 0.65, 0.35, 1)
		sb.border_width_left = 3
		sb.border_width_top = 3
		sb.border_width_right = 3
		sb.border_width_bottom = 3
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 6
		main_panel.add_theme_stylebox_override("panel", sb)

	# 隐藏 .tscn 里多余的孤儿 PanelSB StyleBoxFlat 节点（它在 PanelContainer 下但不被使用）
	var orphan := get_node_or_null("MainPanel/PanelSB")
	if orphan:
		orphan.queue_free()

	_build_messages_page()
	_build_contacts_page()
	_switch_tab("messages")
	_stylize_topbar()
	hide()

func open() -> void:
	show()
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)
	_build_messages_page()
	_build_contacts_page()
	_apply_page_background()

func _on_close_pressed() -> void:
	hide()
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_can_move"):
		player.set_can_move(true)

func _on_tab_messages_pressed() -> void:
	_switch_tab("messages")

func _find_npc_id_by_title(title: String) -> String:
	for n in NPC_CONTACTS:
		if n.get("name", "") == title:
			return n.get("id", "")
	return ""

# 给消息/通讯录页面加内边距（避免贴边）
func _apply_page_background() -> void:
	var page_sb := StyleBoxFlat.new()
	page_sb.bg_color = Color(0, 0, 0, 0)  # 透明 - 让 MainPanel 的深棕透出来
	page_sb.content_margin_left = 6
	page_sb.content_margin_top = 6
	page_sb.content_margin_right = 6
	page_sb.content_margin_bottom = 6
	# 让 VBoxContainer 加 padding - 把第一个 child 推下来
	for p in [messages_list, contacts_list]:
		# 通过 add_theme_constant_override 加 padding
		p.add_theme_constant_override("separation", 4)

func _on_tab_contacts_pressed() -> void:
	_switch_tab("contacts")

func _switch_tab(tab: String) -> void:
	_current_tab = tab
	page_messages.visible = (tab == "messages")
	page_contacts.visible = (tab == "contacts")
	tab_messages.modulate = Color(0.25, 0.20, 0.12, 1) if tab == "messages" else Color(0.55, 0.50, 0.42, 1)
	tab_contacts.modulate = Color(0.25, 0.20, 0.12, 1) if tab == "contacts" else Color(0.55, 0.50, 0.42, 1)

func _build_messages_page() -> void:
	_refresh_groups_from_engine()
	for c in messages_list.get_children():
		c.queue_free()
	for gid in GROUPS:
		var g: Dictionary = GROUPS[gid]
		messages_list.add_child(_make_row(
			"", g["title"], g["recent"], g["unread"],
			Callable(self, "_on_group_clicked").bind(gid), true
		))
	var sep := HSeparator.new()
	sep.modulate = Color(0.5, 0.45, 0.35, 0.6)
	messages_list.add_child(sep)
	var lbl := Label.new()
	lbl.text = "  最近对话"
	lbl.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40, 0.95))
	lbl.add_theme_font_size_override("font_size", 13)
	messages_list.add_child(lbl)
	for n in NPC_CONTACTS:
		messages_list.add_child(_make_row(
			n["id"], n["name"], n["signature"], 0,
			Callable(self, "_on_npc_clicked").bind(n["id"]), false
		))

func _build_contacts_page() -> void:
	for c in contacts_list.get_children():
		c.queue_free()
	var by_tag: Dictionary = {}
	for n in NPC_CONTACTS:
		if not by_tag.has(n["tag"]):
			by_tag[n["tag"]] = []
		by_tag[n["tag"]].append(n)
	for tag in by_tag:
		var lbl := Label.new()
		lbl.text = "  %s" % tag
		lbl.add_theme_color_override("font_color", Color(0.45, 0.40, 0.30, 0.95))
		lbl.add_theme_font_size_override("font_size", 12)
		contacts_list.add_child(lbl)
		for n in by_tag[tag]:
			contacts_list.add_child(_make_contact_row(n))

func _make_row(icon_id: String, title: String, subtitle: String, unread: int, callback: Callable, is_group: bool) -> Control:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 44)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.95, 0.90, 1)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 8
	sb.content_margin_top = 6
	sb.content_margin_right = 8
	sb.content_margin_bottom = 6
	row.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.92, 0.82, 0.65, 1)
	row.add_theme_stylebox_override("hover", sb_h)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = Color(0.85, 0.72, 0.50, 1)
	row.add_theme_stylebox_override("pressed", sb_p)
	var sb_f := sb.duplicate() as StyleBoxFlat
	sb_f.bg_color = Color(0.97, 0.95, 0.90, 1)
	row.add_theme_stylebox_override("focus", sb_f)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(36, 36)
	avatar.size = Vector2(36, 36)
	var av_sb := StyleBoxFlat.new()
	av_sb.bg_color = Color(0.95, 0.88, 0.72, 1)
	av_sb.corner_radius_top_left = 8
	av_sb.corner_radius_top_right = 8
	av_sb.corner_radius_bottom_left = 8
	av_sb.corner_radius_bottom_right = 8
	av_sb.border_color = Color(0.85, 0.65, 0.35, 0.8)
	av_sb.border_width_left = 2
	av_sb.border_width_top = 2
	av_sb.border_width_right = 2
	av_sb.border_width_bottom = 2
	avatar.add_theme_stylebox_override("panel", av_sb)
	var av_tex := TextureRect.new()
	av_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	av_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	av_tex.offset_left = 1
	av_tex.offset_top = 1
	av_tex.offset_right = -1
	av_tex.offset_bottom = -1
	if is_group:
		# 群组头像 = 该组第一个 NPC 像素小人（自定义检查色）
		var first_member_id := ""
		var group_data: Dictionary = GROUPS.get(_find_group_id_from_title(title), {})
		var members = group_data.get("members", [])
		if members.size() > 0:
			first_member_id = str(members[0])
		var npc_match: Dictionary = {}
		for n in NPC_CONTACTS:
			if n.get("id", "") == first_member_id:
				npc_match = n
				break
		av_tex.texture = _make_portrait(npc_match)
	else:
		var npc_match2: Dictionary = {}
		for n in NPC_CONTACTS:
			if n.get("name", "") == title or n.get("id", "") == _find_npc_id_by_title(title):
				npc_match2 = n
				break
		if npc_match2.is_empty():
			# fallback: 用 title 当 id 找
			for n in NPC_CONTACTS:
				if title.find(n.get("name", "")) >= 0:
					npc_match2 = n
					break
		av_tex.texture = _make_portrait(npc_match2)
	avatar.add_child(av_tex)
	h.add_child(avatar)

	var text_v := VBoxContainer.new()
	text_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_v.add_theme_constant_override("separation", 2)
	var t := Label.new()
	t.text = title
	t.custom_minimum_size = Vector2(0, 22)
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color(0.20, 0.16, 0.10))
	var s := Label.new()
	s.text = subtitle
	s.custom_minimum_size = Vector2(180, 0)
	s.add_theme_font_size_override("font_size", 12)
	s.add_theme_color_override("font_color", Color(0.40, 0.32, 0.20, 0.95))
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.clip_text = true
	text_v.add_child(t)
	text_v.add_child(s)
	h.add_child(text_v)

	if unread > 0:
		var dot := PanelContainer.new()
		dot.custom_minimum_size = Vector2(22, 22)
		var dot_sb := StyleBoxFlat.new()
		dot_sb.bg_color = Color(0.92, 0.30, 0.30)
		dot_sb.corner_radius_top_left = 11
		dot_sb.corner_radius_top_right = 11
		dot_sb.corner_radius_bottom_left = 11
		dot_sb.corner_radius_bottom_right = 11
		dot.add_theme_stylebox_override("panel", dot_sb)
		var dot_lbl := Label.new()
		dot_lbl.text = str(unread)
		dot_lbl.add_theme_font_size_override("font_size", 12)
		dot_lbl.add_theme_color_override("font_color", Color.WHITE)
		dot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		dot.add_child(dot_lbl)
		h.add_child(dot)

	row.pressed.connect(callback)
	return row


func _make_contact_row(n: Dictionary) -> Control:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 40)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.95, 0.90, 1)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 6
	sb.content_margin_top = 4
	sb.content_margin_right = 6
	sb.content_margin_bottom = 4
	row.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.92, 0.82, 0.65, 1)
	row.add_theme_stylebox_override("hover", sb_h)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = Color(0.85, 0.72, 0.50, 1)
	row.add_theme_stylebox_override("pressed", sb_p)
	var sb_f := sb.duplicate() as StyleBoxFlat
	sb_f.bg_color = Color(0.97, 0.95, 0.90, 1)
	row.add_theme_stylebox_override("focus", sb_f)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(36, 36)
	avatar.size = Vector2(36, 36)
	var av_sb := StyleBoxFlat.new()
	av_sb.bg_color = Color(0.95, 0.88, 0.72, 1)
	av_sb.corner_radius_top_left = 8
	av_sb.corner_radius_top_right = 8
	av_sb.corner_radius_bottom_left = 8
	av_sb.corner_radius_bottom_right = 8
	av_sb.border_color = Color(0.85, 0.65, 0.35, 0.8)
	av_sb.border_width_left = 2
	av_sb.border_width_top = 2
	av_sb.border_width_right = 2
	av_sb.border_width_bottom = 2
	avatar.add_theme_stylebox_override("panel", av_sb)
	var av_tex := TextureRect.new()
	av_tex.texture = _make_portrait(n)
	av_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	av_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	av_tex.offset_left = 1
	av_tex.offset_top = 1
	av_tex.offset_right = -1
	av_tex.offset_bottom = -1
	avatar.add_child(av_tex)
	h.add_child(avatar)

	var t := Label.new()
	t.text = "%s  (%s)" % [n["name"], n["tag"]]
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color(0.20, 0.16, 0.10))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(60, 8)
	bar.max_value = 100
	bar.value = _get_relationship(n["id"])
	bar.show_percentage = false
	var v := bar.value
	if v < 30:
		bar.modulate = Color(0.7, 0.6, 0.5)
	elif v < 70:
		bar.modulate = Color(0.95, 0.78, 0.45)
	else:
		bar.modulate = Color(0.45, 0.85, 0.55)
	h.add_child(bar)

	row.pressed.connect(_on_npc_clicked.bind(n["id"]))
	return row

func _on_group_clicked(group_id: String) -> void:
	# 检查解锁
	var eng_script = load("res://scripts/offline/GroupChatEngine.gd")
	if eng_script:
		var eng = eng_script.get_instance()
		if eng and eng.has_method("is_unlocked") and not eng.is_unlocked(group_id):
			var lv: int = eng.get_unlock_level(group_id)
			_show_toast("🔒 该群需亲密度 Lv.%d 才能加入" % lv)
			return

	# 打开群聊窗口（手机样式浮窗）
	var gc_panel_script = load("res://scripts/ui/group_chat_panel.gd")
	if gc_panel_script == null:
		_show_toast("❌ 群聊面板加载失败")
		return
	var gc_panel = gc_panel_script.new()
	gc_panel.name = "GroupChatPanel_" + group_id
	gc_panel.current_group_key = group_id
	var target: Node = get_tree().get_root()
	target.add_child(gc_panel)
	if gc_panel.has_method("open"):
		gc_panel.open()
	# 关闭自己
	_on_close_pressed()

func _on_npc_clicked(npc_id: String) -> void:
	# 纯展示模式（去 LLM）：找 NPC 信息，弹一个 toast
	var info: Dictionary = _find_npc(npc_id)
	var npc_name: String = info.get("name", npc_id)
	var tag: String = info.get("tag", "")
	var rel: float = _get_relationship(npc_id)
	_show_toast("%s (%s)\n好感度：%d%%" % [npc_name, tag, int(rel)])

func _find_npc(npc_id: String) -> Dictionary:
	for n in NPC_CONTACTS:
		if n["id"] == npc_id:
			return n
	return {}

# Toast：右下角淡入淡出提示，不依赖 LLM
var _toast: Control = null
func _show_toast(text: String) -> void:
	if _toast and is_instance_valid(_toast):
		_toast.queue_free()
	var p := PanelContainer.new()
	p.name = "Toast"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.94, 0.86, 0.95)
	sb.border_color = Color(0.65, 0.50, 0.30)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_top = 12
	sb.content_margin_right = 16
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.30, 0.22, 0.12))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.position = Vector2(-260, 60)
	p.size = Vector2(240, 0)
	add_child(p)
	_toast = p
	# 2 秒后自动消失
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(_toast_fade_out.bind(p))


func _toast_fade_out(p: PanelContainer) -> void:
	if not is_instance_valid(p):
		return
	var tween := create_tween()
	tween.tween_property(p, "modulate:a", 0.0, 0.4)
	tween.tween_callback(p.queue_free)

func _find_group_id_from_title(title: String) -> String:
	for gid in GROUPS:
		if GROUPS[gid]["title"] == title:
			return gid
	return ""

func _get_relationship(npc_id: String) -> float:
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_relationship"):
		var info: Dictionary = gm.get_relationship(npc_id)
		var pts: int = info.get("points", 0)
		return clamp(pts + 50, 0, 100)
	return 50.0


func _stylize_topbar() -> void:
	# 全局字体: 像素风感（用 system 字体 + 最紧凑字形 + 不抗锯齿）
	var pixel := SystemFont.new()
	pixel.font_names = PackedStringArray(["Microsoft YaHei UI", "SimHei", "sans-serif"])
	pixel.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	pixel.hinting = TextServer.HINTING_NONE
	var theme := Theme.new()
	theme.default_font = pixel
	theme.default_font_size = 14
	self.theme = theme

	# TopBar 像素风底色（金棕调）
	var topbar := get_node_or_null("MainPanel/VBox/TopBar") as HBoxContainer
	if topbar == null:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.92, 0.86, 0.72, 1)
	bg.border_width_bottom = 2
	bg.border_color = Color(0.70, 0.55, 0.30, 0.7)
	topbar.add_theme_stylebox_override("panel", bg)
	# 给 tab 加像素风字体色
	for b in [tab_messages, tab_contacts]:
		b.add_theme_color_override("font_color", Color(0.30, 0.22, 0.12))
		b.add_theme_color_override("font_hover_color", Color(0.55, 0.35, 0.15))
		b.add_theme_color_override("font_pressed_color", Color(0.20, 0.12, 0.05))
		b.add_theme_font_size_override("font_size", 16)
	close_button.add_theme_color_override("font_color", Color(0.40, 0.25, 0.10))
	close_button.add_theme_font_size_override("font_size", 18)