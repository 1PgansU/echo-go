# Letter：单封信弹窗场景
extends Control

@onready var title_label: Label = $Panel/VBox/Header/HeaderText/Title
@onready var sender_label: Label = $Panel/VBox/Header/HeaderText/Sender
@onready var icon_label: Label = $Panel/VBox/Header/Icon
@onready var content_label: RichTextLabel = $Panel/VBox/ContentScroll/Content
@onready var skip_button: Button = $Panel/VBox/Footer/SkipButton
@onready var panel: Panel = $Panel

var _letter_data: Dictionary = {}
var _on_finished: Callable = Callable()


func _ready() -> void:
	skip_button.pressed.connect(_on_skip_pressed)
	# 3 秒后淡入跳过按钮（避免一开就显示）
	skip_button.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(skip_button, "modulate:a", 1.0, 0.6)


func setup(letter_data: Dictionary, on_finished: Callable) -> void:
	_letter_data = letter_data
	_on_finished = on_finished
	_render()


func _render() -> void:
	icon_label.text = _letter_data.get("icon", "💌")
	sender_label.text = _letter_data.get("sender_title", "")
	title_label.text = _letter_data.get("title", "")

	# 让边框颜色随 NPC 颜色变化（保持米白底，不染整面板）
	var accent: Color = _letter_data.get("accent", Color(0.788, 0.482, 0.388))
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.984, 0.965, 0.918, 0.96)
	stylebox.border_width_left = 3
	stylebox.border_width_top = 3
	stylebox.border_width_right = 3
	stylebox.border_width_bottom = 3
	stylebox.border_color = accent
	stylebox.corner_radius_top_left = 8
	stylebox.corner_radius_top_right = 8
	stylebox.corner_radius_bottom_right = 8
	stylebox.corner_radius_bottom_left = 8
	stylebox.shadow_color = Color(0, 0, 0, 0.3)
	stylebox.shadow_size = 16
	stylebox.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", stylebox)

	# 标题颜色也用 NPC 色（强标识）
	title_label.add_theme_color_override("font_color", accent)

	# 内容渲染（保留换行）
	var lines: Array = _letter_data.get("content", [])
	content_label.text = "\n".join(lines)


func _on_skip_pressed() -> void:
	_finish()


func _finish() -> void:
	# 淡出整个面板
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func():
		if _on_finished.is_valid():
			_on_finished.call()
		queue_free()
	)


func _unhandled_input(event: InputEvent) -> void:
	# ESC 或回车 → 跳过
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ENTER):
		_finish()
		get_viewport().set_input_as_handled()