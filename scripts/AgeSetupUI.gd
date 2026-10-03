# AgeSetupUI：首次启动让玩家输入真实年龄，建立"游戏内16岁"的基准
extends Control

signal setup_completed(age: int)

const CARD_BG := Color(0.976, 0.957, 0.91, 1)
const CARD_BORDER := Color(0.788, 0.482, 0.388, 1)
const TEXT_DARK := Color(0.239, 0.157, 0.09, 1)
const TEXT_BODY := Color(0.34, 0.30, 0.25, 1)
const BUTTON_BG := Color(0.788, 0.482, 0.388, 1)
const BUTTON_HOVER := Color(0.98, 0.65, 0.5, 1)

var _input: LineEdit
var _btn: Button
var _hint: Label
var _real_time_label: Label
var _input_age: int = 16
var _ticker: Timer


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 背景
	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.35)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# 卡片
	var card = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = CARD_BORDER
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(24)
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 16
	sb.content_margin_left = 56
	sb.content_margin_right = 56
	sb.content_margin_top = 48
	sb.content_margin_bottom = 48
	card.add_theme_stylebox_override("panel", sb)
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -320
	card.offset_top = -240
	card.offset_right = 320
	card.offset_bottom = 240
	add_child(card)
	# 内部 VBox
	var vb = VBoxContainer.new()
	vb.anchor_right = 1.0
	vb.anchor_bottom = 1.0
	vb.add_theme_constant_override("separation", 18)
	card.add_child(vb)
	# 标题
	var title = Label.new()
	title.text = "👋 你好，新同学"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", TEXT_DARK)
	vb.add_child(title)
	# 副标题
	var sub = Label.new()
	sub.text = "在开始之前，告诉我你今年多大？\n我会把你带回 16 岁那年——和今天同样的月份和日期。"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", TEXT_BODY)
	vb.add_child(sub)
	# 实时北京时钟
	_real_time_label = Label.new()
	_real_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_real_time_label.add_theme_font_size_override("font_size", 14)
	_real_time_label.add_theme_color_override("font_color", Color(0.478, 0.518, 0.443, 1))
	vb.add_child(_real_time_label)
	# 输入框
	_input = LineEdit.new()
	_input.text = "16"
	_input.placeholder_text = "例如：30"
	_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input.add_theme_font_size_override("font_size", 28)
	_input.max_length = 3
	_input.custom_minimum_size = Vector2(220, 60)
	_input.text_changed.connect(_on_text_changed)
	_input.text_submitted.connect(_on_submit)
	vb.add_child(_input)
	# 提示
	_hint = Label.new()
	_hint.text = "提示：10-100 之间的整数"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5, 1))
	vb.add_child(_hint)
	# 按钮
	_btn = Button.new()
	_btn.text = "开始回响 →"
	_btn.custom_minimum_size = Vector2(0, 56)
	_btn.pressed.connect(_on_confirm)
	var sb_btn = StyleBoxFlat.new()
	sb_btn.bg_color = BUTTON_BG
	sb_btn.set_corner_radius_all(28)
	sb_btn.content_margin_left = 40
	sb_btn.content_margin_right = 40
	sb_btn.content_margin_top = 14
	sb_btn.content_margin_bottom = 14
	_btn.add_theme_stylebox_override("normal", sb_btn)
	var sb_btn_h = sb_btn.duplicate()
	sb_btn_h.bg_color = BUTTON_HOVER
	_btn.add_theme_stylebox_override("hover", sb_btn_h)
	_btn.add_theme_stylebox_override("pressed", sb_btn_h)
	_btn.add_theme_color_override("font_color", Color(0.98, 0.93, 0.85, 1))
	_btn.add_theme_font_size_override("font_size", 20)
	vb.add_child(_btn)
	# 占位
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	# 每秒刷新北京时钟
	_ticker = Timer.new()
	_ticker.wait_time = 1.0
	_ticker.timeout.connect(_refresh_real_time)
	_ticker.autostart = true
	add_child(_ticker)
	_refresh_real_time()
	# 默认聚焦
	_input.grab_focus()
	_input.select_all()


func _on_text_changed(new_text: String) -> void:
	# 限制数字
	var s: String = ""
	for c in new_text:
		if c >= "0" and c <= "9":
			s += c
	if s != new_text:
		_input.text = s
		_input.caret_column = s.length()
		return
	if s.is_empty():
		_input_age = 0
		return
	_input_age = int(s)
	_validate_hint()


func _on_submit(_t: String) -> void:
	_on_confirm()


func _validate_hint() -> void:
	if _input_age < 10 or _input_age > 100:
		_hint.text = "请输入 10-100 之间的整数"
		_hint.add_theme_color_override("font_color", Color(0.7, 0.3, 0.2, 1))
		_btn.disabled = true
	else:
		_hint.text = "你 %d 岁 → 游戏回到你 16 岁那年（%d 年）" % [_input_age, _compute_year()]
		_hint.add_theme_color_override("font_color", Color(0.4, 0.55, 0.4, 1))
		_btn.disabled = false


func _compute_year() -> int:
	var utc_ts: int = int(Time.get_unix_time_from_system())
	var beijing_ts: int = utc_ts + 28800
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(beijing_ts)
	var real_year: int = int(dt.get("year", 2026))
	return real_year - _input_age + 16


func _refresh_real_time() -> void:
	var tm = get_node_or_null("/root/TimeManager")
	if tm and tm.has_method("real_now_str") and tm.has_method("real_today_str"):
		var s: String = tm.real_today_str() + " · " + tm.real_now_str()
		_real_time_label.text = "📅 现在是 " + s
	else:
		_real_time_label.text = "📅 现在是 北京时间"


func _on_confirm() -> void:
	if _input_age < 10 or _input_age > 100:
		return
	var tm = get_node_or_null("/root/TimeManager")
	if tm:
		tm.setup(_input_age)
	# 关闭
	emit_signal("setup_completed", _input_age)
	queue_free()