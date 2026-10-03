# OpeningLetter.gd — 开场"闺蜜来信"过场
"""
当玩家离线 > 5 分钟重新打开游戏时，弹出 NPC 小优/小羊的来信
制造"刚回来就被消息炸到"的钩子
"""
extends CanvasLayer

# 信纸设计
const LETTER_WIDTH := 560
const LETTER_HEIGHT := 380
const LETTER_BG := Color(0.98, 0.94, 0.85)   # 米黄信纸
const LETTER_BORDER := Color(0.85, 0.65, 0.40) # 牛皮纸边框
const TEXT_COLOR := Color(0.25, 0.15, 0.10)
const ACCENT_COLOR := Color(0.90, 0.30, 0.25)  # 重点红

var _letter: PanelContainer = null
var _is_showing: bool = false

# === 来信模板（按 NPC + 关系阶段分发） ===
const LETTERS := {
	"xiaoyou_first": {
		"npc": "xiaoyou",
		"npc_name": "🍊 小柚",
		"title": "一封十万火急的信！！！",
		"body": [
			"姐妹！！！！！！！",
			"你在吗你在吗你在吗！！！",
			"我靠我靠我靠——",
			"我谈恋爱了！！！！！！",
			"就、就上周那个我跟你说过的学长……",
			"他、他居然跟我表白了！！！",
			"我整个人都傻了现在！！",
			"你快上线！跟我说说该怎么办！",
			"（尖叫）（原地升天）（灵魂出窍）",
		],
	},
	"xiaoyou_chill": {
		"npc": "xiaoyou",
		"npc_name": "🍊 小柚",
		"title": "姐妹你今天有空吗",
		"body": [
			"在吗～",
			"想约你出来逛逛",
			"上次那个学长……（脸红）",
			"我们已经在一起三周啦～",
			"想带他给你看看",
			"你什么时候有空呀？",
			"我请你喝奶茶！",
		],
	},
	"xiaoyang_first": {
		"npc": "xiaoyang",
		"npc_name": "🐑 小羊",
		"title": "哥们儿！！！！急！！！！",
		"body": [
			"在不在！！！！",
			"我靠我靠我跟你说个事",
			"我打游戏认识了个哥们儿",
			"他、他居然是我同班同学！！！",
			"线下面基的时候我直接愣住了",
			"现在天天一起开黑",
			"你要不要一起来？三缺一！",
		],
	},
	"mother_care": {
		"npc": "mother",
		"npc_name": "👩 妈妈",
		"title": "宝贝，妈妈想你了",
		"body": [
			"孩子，你最近还好吗？",
			"你爸说你老是不回家吃饭",
			"妈妈给你做了你最爱吃的糖醋排骨",
			"周末记得回来啊",
			"妈妈给你留了",
		],
	},
	# === Lv.3+ 小羊来信（发小/兄弟）===
	"xiaoyang_chill": {
		"npc": "xiaoyang",
		"npc_name": "🐑 小羊",
		"title": "哥/姐，出来玩！",
		"body": [
			"在吗在吗！",
			"周末有空不？",
			"我攒了点钱，想请你去电玩城",
			"打几局拳皇 + 抓娃娃",
			"输了的人请奶茶",
			"（我超有信心的！）",
			"不见不散啊！",
		],
	},
	# === Lv.2 妈妈来信（家人常关怀）===
	"mother_warm": {
		"npc": "mother",
		"npc_name": "👩 妈妈",
		"title": "宝贝，记得吃饭",
		"body": [
			"孩子，",
			"妈妈看你最近老是不在家",
			"是不是太忙了？",
			"冰箱里给你炖了排骨汤",
			"热一热就能喝",
			"别饿着自己啊",
			"妈妈爱你",
		],
	},
	# === Lv.4+ crush 破天荒发信 ===
	"crush_first": {
		"npc": "crush",
		"npc_name": "💝 TA",
		"title": "……那个",
		"body": [
			"嗯……你今天有空吗",
			"我、我有个事想跟你说",
			"别笑我啊",
			"其实就是……",
			"上次图书馆碰到你那次",
			"我、我其实注意你很久了",
			"（发送时间：凌晨 2:03）",
			"（已读 24 小时后还在"输入中"……）",
		],
	},
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200  # 比 DialogueLayer(100) 还高，开屏过场要最顶层
	visible = false

# === 对外 API ===
func show_letter(template_id: String) -> void:
	if _is_showing: return
	if not LETTERS.has(template_id):
		push_warning("OpeningLetter: 未知模板 %s" % template_id)
		return
	_is_showing = true
	visible = true
	_build(LETTERS[template_id])

func close() -> void:
	if _letter:
		_letter.queue_free()
		_letter = null
	_is_showing = false
	visible = false

func is_showing() -> bool:
	return _is_showing

# === 内部：构建信件 ===
func _build(data: Dictionary) -> void:
	# 半透明黑底（全屏）
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_click)
	add_child(dim)

	# 用 CenterContainer 包裹信纸，自动屏幕居中
	var center_box := CenterContainer.new()
	center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_box)

	# 信纸（size 写死，scale 动画）
	_letter = PanelContainer.new()
	_letter.custom_minimum_size = Vector2(LETTER_WIDTH, LETTER_HEIGHT)
	_letter.size = Vector2(LETTER_WIDTH, LETTER_HEIGHT)
	_letter.scale = Vector2(0.01, 0.01)
	_letter.pivot_offset = Vector2(LETTER_WIDTH / 2, LETTER_HEIGHT / 2)
	_letter.z_index = 1000
	center_box.add_child(_letter)
	# 信纸样式
	var style := StyleBoxFlat.new()
	style.bg_color = LETTER_BG
	style.border_color = LETTER_BORDER
	style.border_width_left = 6
	style.border_width_top = 6
	style.border_width_right = 6
	style.border_width_bottom = 6
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 16
	_letter.add_theme_stylebox_override("panel", style)
	add_child(_letter)

	# 信纸内容
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_letter.add_child(box)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 28)
	pad.add_theme_constant_override("margin_right", 28)
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_bottom", 24)
	box.add_child(pad)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	pad.add_child(inner)

	# 寄件人
	var from_label := Label.new()
	from_label.text = data["npc_name"] + " 寄来了一封信"
	from_label.add_theme_font_size_override("font_size", 16)
	from_label.add_theme_color_override("font_color", Color(0.40, 0.30, 0.20))
	inner.add_child(from_label)

	# 标题（手写感）
	var title := Label.new()
	title.text = "✉️  " + data["title"]
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT_COLOR)
	inner.add_child(title)

	# 分隔线
	var sep := HSeparator.new()
	inner.add_child(sep)

	# 正文（逐行打字机效果）
	var body_box := VBoxContainer.new()
	body_box.add_theme_constant_override("separation", 4)
	inner.add_child(body_box)

	for line in data["body"]:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", TEXT_COLOR)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.visible_ratio = 0.0  # 配合 tween 做逐字出现
		body_box.add_child(lbl)

	# 底部关闭按钮
	var close_btn := Button.new()
	close_btn.text = "  收下信 · 关 闭  "
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(close)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(close_btn)

	# === 入场动画 ===
	# 信纸从小放大
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_letter, "scale", Vector2(1, 1), 0.6)
	# 文字逐行浮现（每行 0.15s）
	var labels: Array = []
	for child in body_box.get_children():
		labels.append(child)
	for i in range(labels.size()):
		var lbl: Label = labels[i]
		var delay: float = 0.6 + 0.18 * i
		tween.tween_property(lbl, "visible_ratio", 1.0, 0.4).set_delay(delay)

func _on_dim_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()