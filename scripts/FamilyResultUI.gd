# 节点3 结束时的「家长类型判定结果」UI
extends Control
class_name ResultUI

const TYPE_LABEL := {
	"control":  {"name": "控制型",   "emoji": "🔒", "color": Color(0.85, 0.30, 0.25)},
	"caring":   {"name": "温柔开明型", "emoji": "🌿", "color": Color(0.30, 0.65, 0.40)},
	"absent":   {"name": "放手型",     "emoji": "💼", "color": Color(0.55, 0.55, 0.65)},
	"neutral":  {"name": "中性",       "emoji": "😐", "color": Color(0.60, 0.60, 0.60)},
	"unknown":  {"name": "未提及",     "emoji": "❔", "color": Color(0.65, 0.65, 0.65)},
}


func _ready() -> void:
	# 半透明黑底
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		queue_free()
		get_viewport().set_input_as_handled()


func open(father_type: String, mother_type: String) -> void:
	# 主面板
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.position = Vector2(-260, -200)
	p.size = Vector2(520, 400)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.94, 0.86)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(0.35, 0.20, 0.10)
	sb.content_margin_left = 22
	sb.content_margin_top = 22
	sb.content_margin_right = 22
	sb.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	p.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "📋 家长类型判定"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.20, 0.10, 0.05))
	vbox.add_child(title)

	# 副标题
	var sub := Label.new()
	sub.text = "（基于你刚才回答的关键词推测）"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.4, 0.3, 0.25))
	vbox.add_child(sub)

	# 父
	vbox.add_child(_make_type_row("👨 爸爸", father_type))
	# 母
	vbox.add_child(_make_type_row("👩 妈妈", mother_type))

	# 提示
	var hint := Label.new()
	hint.text = "（这只是推测，不是诊断哦）"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.4, 0.3))
	vbox.add_child(hint)

	# 按钮
	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_box)
	var btn := Button.new()
	btn.text = "明白了 [Enter]"
	btn.size = Vector2(140, 36)
	btn.pressed.connect(func(): queue_free())
	btn_box.add_child(btn)


func _make_type_row(label_text: String, type_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_l := Label.new()
	name_l.text = label_text
	name_l.add_theme_font_size_override("font_size", 18)
	name_l.add_theme_color_override("font_color", Color(0.20, 0.10, 0.05))
	name_l.size = Vector2(110, 28)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_l)

	var info: Dictionary = TYPE_LABEL.get(type_key, TYPE_LABEL["unknown"])
	var type_l := Label.new()
	type_l.text = "%s %s" % [info["emoji"], info["name"]]
	type_l.add_theme_font_size_override("font_size", 18)
	type_l.add_theme_color_override("font_color", info["color"])
	type_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(type_l)
	return row