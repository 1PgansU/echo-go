# Act1ResultTip：右下角浮窗，显示家庭画像判定结果
extends PanelContainer

var _label: Label


func _ready() -> void:
	add_to_group("act1_result_tip")  # 让 Act1 容易找到
	_label = Label.new()
	_label.text = ""
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.85))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(300, 0)
	_label.add_theme_constant_override("line_spacing", 4)
	add_child(_label)
	# 初始隐藏
	visible = false
	modulate.a = 0.0


# 公开：显示判定结果
func show_result(text: String) -> void:
	_label.text = text
	visible = true
	# 淡入
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.6)


# 公开：清空（下次开始新一轮时）
func clear() -> void:
	visible = false
	modulate.a = 0.0
	_label.text = ""