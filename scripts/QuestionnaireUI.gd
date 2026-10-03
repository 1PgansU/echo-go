# 问卷页：5 道题 → 生成性格
extends Control
class_name QuestionnaireUI

@onready var title_label: Label = $VBox/Title
@onready var questions_container: VBoxContainer = $VBox/ScrollContainer/Questions
@onready var submit_button: Button = $VBox/SubmitButton

const QUESTIONS = [
	{
		"q": "1. 你被父母批评时的第一反应？",
		"options": ["A. 直接顶嘴", "B. 沉默走开", "C. 找借口解释", "D. 转移话题"]
	},
	{
		"q": "2. 在班里被同学误解时你会？",
		"options": ["A. 当场澄清", "B. 找朋友倾诉", "C. 自己消化", "D. 以牙还牙"]
	},
	{
		"q": "3. 你对学业的看法？",
		"options": ["A. 非常努力", "B. 尽力而为", "C. 够用就行", "D. 无所谓"]
	},
	{
		"q": "4. 暗恋的人拒绝了你，你会？",
		"options": ["A. 继续追求", "B. 潇洒放下", "C. 自我怀疑", "D. 不再相信"]
	},
	{
		"q": "5. 你觉得父母爱你吗？",
		"options": ["A. 很爱", "B. 还行", "C. 不太确定", "D. 不爱"]
	}
]

var selected_answers: Array = [-1, -1, -1, -1, -1]

func _ready() -> void:
	title_label.text = "📜 遇见 · 那个曾经的自己"
	_build_questions()

func _build_questions() -> void:
	for child in questions_container.get_children():
		child.queue_free()

	for i in QUESTIONS.size():
		var q = QUESTIONS[i]
		var q_box = VBoxContainer.new()
		q_box.add_theme_constant_override("separation", 8)

		var q_label = Label.new()
		q_label.text = q.q
		q_label.add_theme_font_size_override("font_size", 18)
		# 显式设置深色字体，避免默认白色
		q_label.add_theme_color_override("font_color", Color(0.239, 0.157, 0.09, 1))
		q_box.add_child(q_label)

		var grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 8)

		for oi in q.options.size():
			var btn = Button.new()
			btn.text = q.options[oi]
			btn.custom_minimum_size = Vector2(0, 50)
			btn.toggle_mode = true
			# 按钮文字颜色
			btn.add_theme_color_override("font_color", Color(0.239, 0.157, 0.09, 1))
			btn.add_theme_color_override("font_hover_color", Color(0.788, 0.482, 0.388, 1))
			btn.add_theme_color_override("font_pressed_color", Color(0.788, 0.482, 0.388, 1))
			btn.add_theme_color_override("font_focus_color", Color(0.788, 0.482, 0.388, 1))
			btn.pressed.connect(_on_option_pressed.bind(i, oi))
			grid.add_child(btn)

		q_box.add_child(grid)
		questions_container.add_child(q_box)

	# 提交按钮也加字体颜色
	submit_button.add_theme_color_override("font_color", Color(0.239, 0.157, 0.09, 1))
	submit_button.add_theme_color_override("font_hover_color", Color(0.788, 0.482, 0.388, 1))
	submit_button.pressed.connect(_on_submit)

func _on_option_pressed(q_index: int, o_index: int) -> void:
	selected_answers[q_index] = o_index

func _on_submit() -> void:
	# 检查完整性
	for answer in selected_answers:
		if answer == -1:
			show_warning("请回答所有问题～")
			return

	# 初始化性格
	var gm = get_node("/root/GameManager")
	gm.personality.init_from_answers(selected_answers)

	# 进入游戏
	var main = get_tree().get_first_node_in_group("main")
	if main:
		main.goto_intro()

func show_warning(text: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.dialog_text = text
	add_child(dialog)
	dialog.popup_centered()