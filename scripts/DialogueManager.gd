# 对话管理器：场景切换 + 选项 UI + 内心独白 + 教育回响
extends Control

@onready var background: ColorRect = $Background
@onready var dialogue_box: PanelContainer = $DialogueBox
@onready var name_label: Label = $DialogueBox/Margin/VBox/NameLabel
@onready var content_label: RichTextLabel = $DialogueBox/Margin/VBox/ContentLabel
@onready var choices_box: VBoxContainer = $DialogueBox/Margin/VBox/ChoicesBox
@onready var inner_voice_box: PanelContainer = $InnerVoiceBox
@onready var inner_voice_label: RichTextLabel = $InnerVoiceBox/Margin/VBox/ContentLabel

# 打字机效果
@export var chars_per_second: float = 30.0

var current_scene_id: String = ""
var current_scene: Dictionary = {}
var current_dialogue_index: int = 0
var current_dialogue_text: String = ""
var is_typing: bool = false
var typing_timer: float = 0.0
var displayed_text: String = ""
var is_showing_echo: bool = false  # 是否正在显示回响

signal dialogue_finished(choice: Dictionary)
signal scene_completed(scene_id: String)

func _ready() -> void:
	hide_all()

func hide_all() -> void:
	background.visible = false
	dialogue_box.visible = false
	inner_voice_box.visible = false

func start_dialogue(scene_id: String, _npc: Node = null) -> void:
	current_scene_id = scene_id
	var gm = get_node("/root/GameManager")
	if gm == null:
		push_warning("[Dialogue] GameManager not found")
		return
	current_scene = gm.get_scene(scene_id)
	if current_scene.is_empty():
		push_warning("[Dialogue] Scene data empty: %s" % scene_id)
		return

	# 禁用玩家移动
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.set_can_move(false)

	# 显示场景背景描述
	_show_background()
	# 启动对话
	await get_tree().create_timer(2.5).timeout

	is_showing_echo = false
	inner_voice_box.visible = false

	show_dialogue()
	current_dialogue_index = 0
	_play_current_dialogue()

func _show_background() -> void:
	inner_voice_box.visible = true
	inner_voice_label.text = "[i] %s" % current_scene.get("background", "")
	var tween = create_tween()
	tween.tween_property(inner_voice_box, "modulate:a", 1.0, 0.5)

func _play_current_dialogue() -> void:
	if current_scene_id == "" or current_scene.is_empty():
		return
	var dialogues = current_scene.get("dialogues", [])
	if current_dialogue_index >= dialogues.size():
		_show_choices()
		return

	var d = dialogues[current_dialogue_index]
	if d.get("is_self", false):
		name_label.text = "🪞 你"
	else:
		name_label.text = d.get("who", "???")
	current_dialogue_text = d.get("text", "")
	displayed_text = ""
	is_typing = true
	typing_timer = 0.0
	content_label.text = ""

func _process(delta: float) -> void:
	if not is_typing:
		return
	typing_timer += delta
	var target_len = mini(int(typing_timer * chars_per_second), current_dialogue_text.length())
	if target_len != displayed_text.length():
		displayed_text = current_dialogue_text.substr(0, target_len)
		content_label.text = displayed_text
	if target_len >= current_dialogue_text.length():
		is_typing = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if is_showing_echo:
		return  # 回响卡期间禁止跳过
	# 只在对话框可见时响应
	if not dialogue_box.visible:
		return
	# 如果选项已显示，让按钮自己处理点击，不在这里拦截
	if choices_box.visible:
		return
	# 只响应键盘推进
	if event.is_action_pressed("interact"):
		if is_typing:
			is_typing = false
			content_label.text = current_dialogue_text
		else:
			current_dialogue_index += 1
			_play_current_dialogue()

func _show_choices() -> void:
	name_label.text = "🪞 你的选择"
	content_label.text = "你会怎么做？"
	choices_box.visible = true

	for child in choices_box.get_children():
		child.queue_free()

	# 选项按钮样式：米色文字 + 深棕色按钮（与DialogueBox 一致）
	var sb_normal = StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.25, 0.16, 0.1, 1)
	sb_normal.border_width_left = 3
	sb_normal.border_width_top = 3
	sb_normal.border_width_right = 3
	sb_normal.border_width_bottom = 3
	sb_normal.border_color = Color(0.957, 0.886, 0.737, 1)
	sb_normal.corner_radius_top_left = 6
	sb_normal.corner_radius_top_right = 6
	sb_normal.corner_radius_bottom_right = 6
	sb_normal.corner_radius_bottom_left = 6
	sb_normal.content_margin_left = 18
	sb_normal.content_margin_top = 12
	sb_normal.content_margin_right = 18
	sb_normal.content_margin_bottom = 12

	var sb_hover = sb_normal.duplicate()
	sb_hover.bg_color = Color(0.78, 0.48, 0.39, 1)
	sb_hover.border_color = Color(0.98, 0.82, 0.5, 1)

	var sb_pressed = sb_hover.duplicate()
	sb_pressed.bg_color = Color(0.6, 0.35, 0.25, 1)

	var choices = current_scene.get("choices", [])
	for choice in choices:
		var btn = Button.new()
		btn.text = "[%s] %s\n  %s" % [choice.get("id", "?"), choice.get("label", ""), choice.get("text", "")]
		btn.custom_minimum_size = Vector2(0, 80)
		btn.add_theme_stylebox_override("normal", sb_normal)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_stylebox_override("pressed", sb_pressed)
		btn.add_theme_stylebox_override("focus", sb_hover)
		# 字体颜色：米色（清晰），hover时变金色
		btn.add_theme_color_override("font_color", Color(0.98, 0.93, 0.85, 1))
		btn.add_theme_color_override("font_hover_color", Color(0.98, 0.82, 0.5, 1))
		btn.add_theme_color_override("font_pressed_color", Color(0.5, 0.25, 0.15, 1))
		btn.add_theme_color_override("font_focus_color", Color(0.98, 0.82, 0.5, 1))
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_choice_pressed.bind(choice))
		choices_box.add_child(btn)

func _on_choice_pressed(choice: Dictionary) -> void:
	choices_box.visible = false

	# 安全获取 GameManager
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		push_warning("[Dialogue] GameManager not found, choice applied locally only")
	else:
		# 应用选择
		gm.apply_choice(current_scene_id, choice.get("id", ""))

	# 显示内心独白
	_show_inner_voice(choice.get("inner_voice", "……"))
	is_showing_echo = false

	await get_tree().create_timer(3.0).timeout

	# 显示教育回响
	if choice.has("echo_card") and choice.get("echo_card") != "":
		_show_echo_card(choice.get("echo_card"))
		is_showing_echo = true
		await get_tree().create_timer(5.0).timeout
		is_showing_echo = false  # 重置，避免影响打字机效果

	# 通知场景完成
	emit_signal("scene_completed", current_scene_id)
	emit_signal("dialogue_finished", choice)

	# 不再自动推进场景：玩家可以自由选择和谁对话

	# 关闭对话
	hide_all()
	is_showing_echo = false
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.set_can_move(true)

func _show_inner_voice(text: String) -> void:
	inner_voice_box.visible = true
	inner_voice_label.text = "「 %s 」" % text
	is_showing_echo = false

func _show_echo_card(text: String) -> void:
	inner_voice_box.visible = true
	inner_voice_label.text = "📜 教育回响\n\n%s" % text

func show_dialogue() -> void:
	background.visible = true
	dialogue_box.visible = true
	inner_voice_box.visible = false
	var tween = create_tween()
	tween.tween_property(dialogue_box, "modulate:a", 1.0, 0.3)