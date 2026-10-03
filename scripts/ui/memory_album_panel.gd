# MemoryAlbumPanel.gd — 玩家按 R 打开回忆相册
extends CanvasLayer

const WIDTH := 760
const HEIGHT := 600
const MARGIN := 24

var _panel: Control = null
var _is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 96
	visible = false

func _input(event: InputEvent) -> void:
	# P 快捷键已移除：改用 WorldUI 顶部图标按钮
	pass

func _open() -> void:
	_is_open = true
	visible = true
	if _panel:
		_panel.queue_free()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_click)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	center.add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.94, 0.85)  # 暖米色
	style.border_color = Color(0.55, 0.42, 0.28)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", MARGIN)
	pad.add_theme_constant_override("margin_right", MARGIN)
	pad.add_theme_constant_override("margin_top", MARGIN)
	pad.add_theme_constant_override("margin_bottom", MARGIN)
	_panel.add_child(pad)
	pad.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "📸 我们的回忆"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.40, 0.20, 0.15))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "（按 [P] 关闭）"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.50, 0.40, 0.30))
	vbox.add_child(hint)

	# 滚动条
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	scroll.add_child(list)

	# 加载相册
	var album_script = load("res://scripts/offline/MemoryAlbum.gd")
	if album_script == null:
		return
	var album = album_script.get_instance()
	var memories: Array = album.get_album()

	if memories.is_empty():
		var empty := Label.new()
		empty.text = "（还没有回忆……）\n继续在游戏里生活，\n特别的瞬间会自动被记录下来 ✨"
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.50, 0.40, 0.30))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	else:
		# 倒序：最新在最上面
		for i in range(memories.size() - 1, -1, -1):
			_add_card(list, memories[i])

func _add_card(parent: VBoxContainer, mem: Dictionary) -> void:
	# 一张回忆卡片（仿 Instagram 风）
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.98, 0.92)
	style.border_color = Color(0.85, 0.75, 0.55)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0, 0, 0, 0.15)
	style.shadow_offset = Vector2(0, 2)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	card.add_child(pad)
	pad.add_child(inner)

	# 顶部信息：日期 + 标签
	var meta_h := HBoxContainer.new()
	meta_h.add_theme_constant_override("separation", 12)
	inner.add_child(meta_h)

	var day_lbl := Label.new()
	day_lbl.text = "📅 第 %d 天" % int(mem.get("day", 0))
	day_lbl.add_theme_font_size_override("font_size", 13)
	day_lbl.add_theme_color_override("font_color", Color(0.50, 0.40, 0.30))
	meta_h.add_child(day_lbl)

	var date_lbl := Label.new()
	date_lbl.text = str(mem.get("date", ""))
	date_lbl.add_theme_font_size_override("font_size", 13)
	date_lbl.add_theme_color_override("font_color", Color(0.50, 0.40, 0.30))
	meta_h.add_child(date_lbl)

	# 关系跃迁标签
	var level_jump_lbl := Label.new()
	var before_type: String = str(mem.get("level_before", ""))
	var after_type: String = str(mem.get("level_after", ""))
	if before_type != "" and after_type != "":
		level_jump_lbl.text = "✨ %s → %s" % [before_type, after_type]
		level_jump_lbl.add_theme_color_override("font_color", Color(0.85, 0.40, 0.20))
	else:
		level_jump_lbl.text = ""
	level_jump_lbl.add_theme_font_size_override("font_size", 13)
	meta_h.add_child(level_jump_lbl)

	# 大标题
	var title_lbl := Label.new()
	title_lbl.text = str(mem.get("title", "一段回忆"))
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.30, 0.20, 0.10))
	inner.add_child(title_lbl)

	# 副标题
	var sub_lbl := Label.new()
	sub_lbl.text = str(mem.get("subtitle", ""))
	sub_lbl.add_theme_font_size_override("font_size", 14)
	sub_lbl.add_theme_color_override("font_color", Color(0.40, 0.30, 0.20))
	inner.add_child(sub_lbl)

	# 简短的对话片段
	var transcript: Array = mem.get("transcript", [])
	if not transcript.is_empty():
		var sep := HSeparator.new()
		inner.add_child(sep)
		# 最多取前 3 条
		var max_lines: int = min(3, transcript.size())
		for i in range(max_lines):
			var line_lbl := Label.new()
			line_lbl.text = "  · %s" % str(transcript[i])
			line_lbl.add_theme_font_size_override("font_size", 14)
			line_lbl.add_theme_color_override("font_color", Color(0.30, 0.25, 0.20))
			inner.add_child(line_lbl)
		if transcript.size() > max_lines:
			var more := Label.new()
			more.text = "  · ……"
			more.add_theme_font_size_override("font_size", 14)
			more.add_theme_color_override("font_color", Color(0.50, 0.40, 0.30))
			inner.add_child(more)

func _close() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
	_is_open = false
	visible = false

func _on_dim_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()