# FestivalPopup.gd — 节日 + NPC 生日 + 玩家生日 弹窗
"""
玩家打开游戏或当天 sim 结束时：
- 今天有节日 → 全屏弹窗「🎄 圣诞节快乐！」
- NPC 今天生日 → 弹「小柚今天生日！🎂」+ 自动送祝福 + 加好感
- 玩家今天生日 → 全员群发祝福
按 G 键手动打开"节日日历"
"""
extends CanvasLayer

const NPC_DISPLAY := {
	"xiaoyou":  "🍊 小柚",
	"xiaoyang": "🐑 小羊",
	"mother":   "👩 妈妈",
	"father":   "👨 爸爸",
	"brother":  "👦 弟弟",
	"classmate":"👦 同学",
	"teacher":  "👨‍🏫 老师",
	"crush":    "💝 TA",
	"partner":  "💔 TA",
}

var _panel: Control = null
var _is_open: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 95
	visible = false

func _input(event: InputEvent) -> void:
	# G 快捷键已移除：改用 WorldUI 顶部图标按钮
	pass

# === 触发（外部调用，比如每天 sim 完成 / 开屏过场）===
func trigger_today_event() -> void:
	var festival_script = load("res://scripts/offline/FestivalCalendar.gd")
	if festival_script == null:
		return
	var cal = festival_script.get_instance()
	var today_str: String = Time.get_date_string_from_system()  # "2026-10-03"
	var info: Dictionary = cal.check_today(today_str)
	# 玩家生日
	var gm = get_node_or_null("/root/GameManager")
	var player_birthday: String = ""
	if gm and "player_birthday" in gm:
		player_birthday = gm.player_birthday
	# 优先级：有玩家生日 > 有 NPC 生日 > 有节日 > 没有
	if not player_birthday.is_empty() and today_str.ends_with(player_birthday):
		_show_player_birthday()
	elif not info["birthdays"].is_empty():
		_show_npc_birthday(info["birthdays"][0])
	elif info["festival"] != null:
		_show_festival(info["festival"])
	elif info["lunar"] != null:
		_show_festival(info["lunar"])
	# 没有节日 → 不弹

func _close() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
	_is_open = false
	visible = false

# === 节日弹窗 ===
func _show_festival(festival: Dictionary) -> void:
	_show_built(festival["name"], "🎉 今天是%s！大家一起庆祝吧～" % festival["name"])

# === NPC 生日弹窗 ===
func _show_npc_birthday(npc_id: String) -> void:
	var npc_name: String = NPC_DISPLAY.get(npc_id, npc_id)
	_show_built("🎂 %s 的生日" % npc_name, "今天是 TA 的生日！\n记得送上祝福～")
	# 自动加好感
	var matrix_script = load("res://scripts/offline/RelationshipMatrix.gd")
	var matrix = matrix_script.get_instance() if matrix_script else null
	if matrix:
		matrix.mutate(npc_id, "partner", 5)  # 生日祝福 +5 分

# === 玩家生日弹窗 ===
func _show_player_birthday() -> void:
	_show_built("🎉 你的生日！", "今天是你的生日！\n所有人都给你发了祝福～\n\n爱你的 NPC：9/9")

func _show_today_panel() -> void:
	# 显示"今天"的所有节日
	var festival_script = load("res://scripts/offline/FestivalCalendar.gd")
	if festival_script == null:
		return
	var cal = festival_script.get_instance()
	var today_str: String = Time.get_date_string_from_system()
	var info: Dictionary = cal.check_today(today_str)
	var content: String = ""
	if info["festival"]:
		content += "今天：%s\n" % info["festival"]["name"]
	if info["lunar"]:
		content += "今天：%s\n" % info["lunar"]["name"]
	for b in info["birthdays"]:
		content += "🎂 %s 今天生日！\n" % NPC_DISPLAY.get(b, b)
	if content.is_empty():
		content = "（今天普普通通，没有特殊日子～）"
	_show_built("📅 节日日历", content)

# === 通用弹窗构造函数 ===
func _show_built(title: String, body: String) -> void:
	_is_open = true
	visible = true
	if _panel:
		_panel.queue_free()

	# 黑底
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_click)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(520, 320)
	center.add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.97, 0.90)
	style.border_color = Color(0.85, 0.70, 0.40)
	style.border_width_left = 4
	style.border_width_top = 4
	style.border_width_right = 4
	style.border_width_bottom = 4
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(pad)
	pad.add_child(vbox)

	# 大标题
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 32)
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.40, 0.20))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lbl)

	# 内容
	var body_lbl := Label.new()
	body_lbl.text = body
	body_lbl.add_theme_font_size_override("font_size", 18)
	body_lbl.add_theme_color_override("font_color", Color(0.30, 0.20, 0.10))
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body_lbl)

	# 占位
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	# 关闭按钮
	var close := Button.new()
	close.text = "好的 [G 关]"
	close.custom_minimum_size = Vector2(160, 36)
	close.pressed.connect(_close)
	vbox.add_child(close)

func _on_dim_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()