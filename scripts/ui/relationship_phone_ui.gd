# RelationshipPhoneUI.gd — 模拟微信小手机的「好感关系面板」
# 按 C 打开群聊旁边，按 I（relationship）打开这个
# 显示每个 NPC 的：头像 + 名字 + 关系等级 + 进度条 + 最近一条奇遇摘要
extends CanvasLayer

# 玩家按 I 键呼出/关闭
func _unhandled_input(event: InputEvent) -> void:
	# I 快捷键已移除：图标按钮是入口
	pass

var _is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_phone()
	_close()

func _open() -> void:
	_refresh()
	$PhonePanel.visible = true
	_is_open = true

func _close() -> void:
	$PhonePanel.visible = false
	_is_open = false

# ============================================================
# 外观参数（模拟 iPhone 风格）
# ============================================================
const PHONE_W := 370.0
const PHONE_H := 580.0
const PHONE_COLOR := Color(0.12, 0.11, 0.14)       # 深色机身
const SCREEN_COLOR := Color(0.08, 0.09, 0.12)     # 屏幕背景
const HEADER_COLOR := Color(0.15, 0.60, 0.95)      # 蓝色标题栏
const CARD_COLOR := Color(0.17, 0.17, 0.22)       # 卡片背景
const TEXT_MAIN := Color(0.95, 0.95, 0.95)
const TEXT_SUB := Color(0.60, 0.60, 0.70)
const LEVEL_COLORS := {
	"陌生":      Color(0.50, 0.50, 0.55),
	"点头之交":  Color(0.75, 0.75, 0.75),
	"熟人":      Color(0.30, 0.55, 0.95),
	"朋友":      Color(0.25, 0.80, 0.45),
	"闺蜜/兄弟": Color(0.80, 0.35, 0.95),
	"灵魂伴侣":  Color(1.00, 0.78, 0.10),
	"暧昧":      Color(1.00, 0.40, 0.60),
	"恋人":      Color(1.00, 0.20, 0.30),
}

# 每个 NPC 的基础数据
const NPC_META := {
	"xiaoyang":  {"name": "小羊 🐑", "emoji": "🐑", "color": Color(0.60, 0.90, 1.00), "intro": "永远站在你这边的人"},
	"xiaoyou":   {"name": "小柚 🍊", "emoji": "🍊", "color": Color(1.00, 0.75, 0.45), "intro": "从小的闺蜜，懂你所有欲言又止"},
	"father":    {"name": "👨 爸爸", "emoji": "👨", "color": Color(0.55, 0.70, 0.90), "intro": "嘴上不说，心里全是你"},
	"mother":    {"name": "👩 妈妈", "emoji": "👩", "color": Color(1.00, 0.60, 0.65), "intro": "唠叨里藏着牵挂"},
	"brother":   {"name": "👦 弟弟", "emoji": "👦", "color": Color(0.70, 0.80, 0.55), "intro": "嫌弃你又离不开你"},
	"classmate": {"name": "👦 同学", "emoji": "🧑", "color": Color(0.50, 0.75, 0.90), "intro": "一起熬夜的战友"},
	"teacher":   {"name": "👨‍🏫 班主任", "emoji": "👨‍🏫", "color": Color(0.90, 0.70, 0.40), "intro": "严厉外表下的柔软"},
	"crush":     {"name": "💝 TA", "emoji": "💝", "color": Color(1.00, 0.50, 0.75), "intro": "还没说出口的名字"},
	"partner":   {"name": "💔 TA", "emoji": "💔", "color": Color(0.80, 0.80, 0.90), "intro": "分手后的沉默与未知"},
}

# ============================================================
# 构建手机 UI
# ============================================================
func _build_phone() -> void:
	var panel := PanelContainer.new()
	panel.name = "PhonePanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PHONE_W / 2
	panel.offset_top = -PHONE_H / 2
	panel.offset_right = PHONE_W / 2
	panel.offset_bottom = PHONE_H / 2
	add_child(panel)

	# 机身外壳
	var shell := StyleBoxFlat.new()
	shell.bg_color = PHONE_COLOR
	shell.corner_radius_top_left = 28
	shell.corner_radius_top_right = 28
	shell.corner_radius_bottom_left = 28
	shell.corner_radius_bottom_right = 28
	shell.border_width_left = 2
	shell.border_width_right = 2
	shell.border_width_top = 2
	shell.border_width_bottom = 2
	shell.border_color = Color(0.30, 0.30, 0.38)
	panel.add_theme_stylebox_override("panel", shell)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 0)
	pad.add_theme_constant_override("margin_right", 0)
	pad.add_theme_constant_override("margin_top", 0)
	pad.add_theme_constant_override("margin_bottom", 0)
	panel.add_child(pad)
	pad.add_child(v)

	# === 状态栏 ===
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 8)
	status.custom_minimum_size = Vector2(PHONE_W, 36)
	status.add_theme_constant_override("margin_left", 20)
	status.add_theme_constant_override("margin_right", 20)
	v.add_child(status)

	var time_lbl := Label.new()
	time_lbl.name = "TimeLabel"
	time_lbl.text = "现在"
	time_lbl.add_theme_font_size_override("font_size", 12)
	time_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	time_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_child(time_lbl)

	var batt := Label.new()
	batt.text = "🔋 100%"
	batt.add_theme_font_size_override("font_size", 11)
	batt.add_theme_color_override("font_color", TEXT_SUB)
	batt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	batt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	batt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(batt)

	# === 标题栏 ===
	var header := PanelContainer.new()
	header.custom_minimum_size = Vector2(PHONE_W, 52)
	v.add_child(header)

	var hs := StyleBoxFlat.new()
	hs.bg_color = HEADER_COLOR
	hs.corner_radius_top_left = 0
	hs.corner_radius_top_right = 0
	hs.corner_radius_bottom_left = 0
	hs.corner_radius_bottom_right = 0
	header.add_theme_stylebox_override("panel", hs)

	var header_pad := MarginContainer.new()
	header_pad.add_theme_constant_override("margin_left", 18)
	header_pad.add_theme_constant_override("margin_right", 18)
	header.add_child(header_pad)

	var header_h := HBoxContainer.new()
	header_h.add_theme_constant_override("separation", 8)
	header_pad.add_child(header_h)

	var title := Label.new()
	title.text = "💬 好感通讯录"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	header_h.add_child(title)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_h.add_child(header_spacer)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1))
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_close)
	header_h.add_child(close_btn)

	# === 滚动列表（NPC 卡片） ===
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PHONE_W, PHONE_H - 36 - 52 - 10)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	var scroll_v := VBoxContainer.new()
	scroll_v.add_theme_constant_override("separation", 6)
	scroll_v.custom_minimum_size = Vector2(PHONE_W - 4, 10)
	scroll.add_child(scroll_v)

	var scroll_pad := MarginContainer.new()
	scroll_pad.add_theme_constant_override("margin_left", 10)
	scroll_pad.add_theme_constant_override("margin_right", 10)
	scroll_pad.add_theme_constant_override("margin_top", 8)
	scroll_pad.add_theme_constant_override("margin_bottom", 8)
	scroll_v.add_child(scroll_pad)

	var list := VBoxContainer.new()
	list.name = "NPCList"
	list.add_theme_constant_override("separation", 6)
	scroll_pad.add_child(list)

	# === 底部操作栏 ===
	var bottom_bar := PanelContainer.new()
	bottom_bar.custom_minimum_size = Vector2(PHONE_W, 44)
	v.add_child(bottom_bar)

	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.10, 0.10, 0.13)
	bs.corner_radius_top_left = 0
	bs.corner_radius_top_right = 0
	bs.corner_radius_bottom_left = 28
	bs.corner_radius_bottom_right = 28
	bottom_bar.add_theme_stylebox_override("panel", bs)

	var bottom_pad := MarginContainer.new()
	bottom_pad.add_theme_constant_override("margin_left", 16)
	bottom_pad.add_theme_constant_override("margin_right", 16)
	bottom_bar.add_child(bottom_pad)

	var bottom_h := HBoxContainer.new()
	bottom_h.add_theme_constant_override("separation", 4)
	bottom_pad.add_child(bottom_h)

	var hint := Label.new()
	hint.text = "按 [I] 关闭"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", TEXT_SUB)
	bottom_h.add_child(hint)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_h.add_child(spacer2)

	# 预建 9 张 NPC 卡片
	for npc_id in NPC_META:
		var card := _build_npc_card(npc_id)
		list.add_child(card)

# ============================================================
# 构建一张 NPC 关系卡片
# ============================================================
func _build_npc_card(npc_id: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Card_" + npc_id
	card.custom_minimum_size = Vector2(PHONE_W - 28, 68)

	var cs := StyleBoxFlat.new()
	cs.bg_color = CARD_COLOR
	cs.corner_radius_top_left = 12
	cs.corner_radius_top_right = 12
	cs.corner_radius_bottom_left = 12
	cs.corner_radius_bottom_right = 12
	cs.border_width_left = 1
	cs.border_width_right = 1
	cs.border_width_top = 1
	cs.border_width_bottom = 1
	var meta: Dictionary = NPC_META.get(npc_id, {})
	var accent: Color = meta.get("color", Color(0.5, 0.5, 0.5))
	cs.border_color = accent.darkened(0.5)
	card.add_theme_stylebox_override("panel", cs)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	card.add_child(pad)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pad.add_child(h)

	# 左侧：头像
	var avatar := Label.new()
	avatar.name = "Avatar"
	avatar.text = "🙂"
	avatar.add_theme_font_size_override("font_size", 28)
	avatar.custom_minimum_size = Vector2(40, 40)
	avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(avatar)

	# 中间：名字 + 等级 + 简介 + 进度条
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	mid.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	name_row.add_child(name_lbl)

	var level_lbl := Label.new()
	level_lbl.name = "LevelLabel"
	level_lbl.add_theme_font_size_override("font_size", 11)
	name_row.add_child(level_lbl)

	var intro_lbl := Label.new()
	intro_lbl.name = "IntroLabel"
	intro_lbl.add_theme_font_size_override("font_size", 10)
	intro_lbl.add_theme_color_override("font_color", TEXT_SUB)
	mid.add_child(intro_lbl)

	# 进度条
	var bar_bg := PanelContainer.new()
	bar_bg.custom_minimum_size = Vector2(0, 5)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(bar_bg)

	var bar_s := StyleBoxFlat.new()
	bar_s.bg_color = Color(0.25, 0.25, 0.30)
	bar_s.corner_radius_top_left = 3
	bar_s.corner_radius_top_right = 3
	bar_s.corner_radius_bottom_left = 3
	bar_s.corner_radius_bottom_right = 3
	bar_bg.add_theme_stylebox_override("panel", bar_s)

	var bar_fill := PanelContainer.new()
	bar_fill.name = "BarFill"
	bar_fill.custom_minimum_size = Vector2(0, 5)
	bar_fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar_bg.add_child(bar_fill)

	var fill_s := StyleBoxFlat.new()
	fill_s.corner_radius_top_left = 3
	fill_s.corner_radius_top_right = 3
	fill_s.corner_radius_bottom_left = 3
	fill_s.corner_radius_bottom_right = 3
	bar_fill.add_theme_stylebox_override("panel", fill_s)

	# 右侧：点数
	var pts := Label.new()
	pts.name = "PointsLabel"
	pts.add_theme_font_size_override("font_size", 13)
	pts.add_theme_color_override("font_color", TEXT_SUB)
	pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(pts)

	return card

# ============================================================
# 刷新：读取 RelationshipMatrix，更新每张卡片
# ============================================================
func _refresh() -> void:
	var matrix := _get_matrix()

	# 找到 NPC 列表（用 find_child 防路径写错）
	var list: VBoxContainer = $PhonePanel.find_child("NPCList", true, false) as VBoxContainer

	# 遍历 9 张卡片
	for npc_id in NPC_META:
		var card: PanelContainer = null
		for c in list.get_children():
			if c.name == "Card_" + npc_id:
				card = c
				break
		if card == null:
			continue

		# 取数据（type 用 points 实时算，不依赖 dict 旧值，防止不一致）
		var meta: Dictionary = NPC_META[npc_id]
		var rel: Dictionary = matrix.pair(npc_id, "partner") if matrix else {"points": 0, "type": "陌生"}
		var pts: int = int(rel.get("points", 0))
		var rel_type: String = matrix.get_type_for_points(pts) if matrix else "陌生"
		var level: int = matrix.get_level_for_points(pts) if matrix else 0

		# 找子节点
		var avatar: Label = card.find_child("Avatar", true, false)
		var name_lbl: Label = card.find_child("NameLabel", true, false)
		var level_lbl: Label = card.find_child("LevelLabel", true, false)
		var intro_lbl: Label = card.find_child("IntroLabel", true, false)
		var pts_lbl: Label = card.find_child("PointsLabel", true, false)
		var bar_fill: PanelContainer = card.find_child("BarFill", true, false)

		if avatar: avatar.text = meta.get("emoji", "🙂")
		if name_lbl: name_lbl.text = meta.get("name", npc_id)
		if intro_lbl: intro_lbl.text = meta.get("intro", "")

		if level_lbl:
			var lc: Color = LEVEL_COLORS.get(rel_type, Color(0.5, 0.5, 0.5))
			level_lbl.text = "「" + rel_type + "」"
			level_lbl.add_theme_color_override("font_color", lc)
		if pts_lbl:
			pts_lbl.text = str(pts)
			var lc: Color = LEVEL_COLORS.get(rel_type, Color(0.5, 0.5, 0.5))
			pts_lbl.add_theme_color_override("font_color", lc)

		# 进度条：当前等级最低分 ~ 下一等级最低分
		if bar_fill and matrix:
			var cur_min: int = 0
			for entry in matrix.LEVEL_TABLE:
				if entry["level"] == level:
					cur_min = int(entry["min"])
					break
			var next_min: int = matrix.get_next_level_threshold(pts)
			var pct: float = 0.0
			if next_min > cur_min:
				pct = clamp(float(pts - cur_min) / float(next_min - cur_min), 0.0, 1.0)
			elif next_min == -1:
				pct = 1.0  # 满级

			var bar_w: float = (PHONE_W - 80) * pct
			bar_fill.custom_minimum_size = Vector2(max(bar_w, 4), 5)

			var fill_s: StyleBoxFlat = bar_fill.get_theme_stylebox("panel") as StyleBoxFlat
			if fill_s == null:
				fill_s = StyleBoxFlat.new()
				fill_s.corner_radius_top_left = 3
				fill_s.corner_radius_top_right = 3
				fill_s.corner_radius_bottom_left = 3
				fill_s.corner_radius_bottom_right = 3
				bar_fill.add_theme_stylebox_override("panel", fill_s)
			fill_s.bg_color = LEVEL_COLORS.get(rel_type, Color(0.5, 0.5, 0.5))

	# 更新状态栏时间（用 find_child 防止路径写错）
	var time_lbl: Label = $PhonePanel.find_child("TimeLabel", true, false)
	if time_lbl:
		var tm = get_node_or_null("/root/TimeManager")
		if tm and tm.has_method("get_game_day"):
			var day: int = tm.get_game_day()
			time_lbl.text = "Day %d" % day

# 获取关系矩阵（get_instance 直接挂在 /root 下）
func _get_matrix() -> Node:
	# 1. 直接找根节点下的单例
	var m = get_node_or_null("/root/RelationshipMatrix")
	if m: return m
	# 2. 兜底：get_instance
	var MatrixScript = load("res://scripts/offline/RelationshipMatrix.gd")
	if MatrixScript and MatrixScript.has("get_instance"):
		return MatrixScript.get_instance()
	return null

# ============================================================
# 每帧更新状态栏时间（手机模拟）
# ============================================================
func _process(delta: float) -> void:
	if not _is_open:
		return
	var time_lbl: Label = $PhonePanel.find_child("TimeLabel", true, false)
	if time_lbl:
		var now: Dictionary = Time.get_time_dict_from_system()
		time_lbl.text = "%02d:%02d" % [now.get("hour", 0), now.get("minute", 0)]
