# ============================================================
# PressureAlert：屏幕中央"父母施压"检测提示卡
# ============================================================
# 触发时机：父母说完"你不如小柚考得好" → 等 1s → 弹出
# 视觉：屏幕中央 · 红色底（带金黄边框） · 白色长方形大字 · 大感叹号
# 动画：淡入 → 闪烁 3 下（每下 0.25s） → 淡出 → 销毁
# 不阻塞对话 / 输入：mouse_filter = IGNORE；z_index 最高
# ============================================================
extends Node

const FLASH_TIMES := 2           # 闪 2 下
const FLASH_HALF := 0.2          # 每下"亮"或"暗"半周期（秒）→ 一亮一暗 0.4s
const FADE_IN_S := 0.3
const FADE_OUT_S := 0.4
const ALERT_TOTAL_S := 2.5       # 警报总时长：0.3 + 0.4*2*2 + 0.4 ≈ 2.3s

const ALERT_HEAD := "\u26a0"                              # ⚠ 大感叹号
const ALERT_BODY := "系统检测到你受到父母的压力\n采取对其处罚机制"   # 注：原文如此保留


func _ready() -> void:
	add_to_group("pressure_alert")
	print("[PressureAlert] autoload 已就绪，path = ", get_path())


# ============================================================
# 外部入口：弹出"压力检测"卡片
# parent: 挂到哪一层 CanvasLayer（一般 DialogueLayer），卡片会在它之下创建
# ============================================================
func show_alert(parent: CanvasLayer) -> void:
	print("[PressureAlert] show_alert() 被调用，parent = ", parent)
	if parent == null:
		push_warning("[PressureAlert] parent 为空，无法显示")
		return
	# 清掉旧的卡（如果之前还在显示）
	var old = parent.get_node_or_null("PressureAlertCard")
	if old:
		old.queue_free()
	_build_card(parent)


func _build_card(parent: CanvasLayer) -> void:
	# === 计算屏幕中心位置（CanvasLayer 下的 Control 需要手动算 position）===
	var viewport_size := get_viewport().get_visible_rect().size
	var card_size := Vector2(900, 280)
	var center_pos := (viewport_size - card_size) * 0.5
	print("[FamilyCare] viewport_size=%s, card_size=%s, center=%s" % [viewport_size, card_size, center_pos])

	# 构造 UI：PanelContainer（红底）+ VBoxContainer（感叹号 + 正文）
	var panel := PanelContainer.new()
	panel.name = "PressureAlertCard"
	# 不用 anchor preset（CanvasLayer 下不可靠），直接 position + size
	panel.position = center_pos
	panel.size = card_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 4096   # Godot 合法上限，确保在所有 UI 之上

	# 红底 + 金黄边框
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.15, 0.15, 0.96)
	sb.border_color = Color(1, 0.85, 0.4, 1)
	sb.border_width_left = 5
	sb.border_width_top = 5
	sb.border_width_right = 5
	sb.border_width_bottom = 5
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 40
	sb.content_margin_top = 32
	sb.content_margin_right = 40
	sb.content_margin_bottom = 32
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	# PanelContainer 在 size 设定后立刻强制重布局，否则首帧尺寸还是 0
	panel.reset_size()

	# 内部 VBox：⚠ 标题 + 正文
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	# ⚠ 大感叹号（金黄色）
	var head := Label.new()
	head.text = ALERT_HEAD
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 96)
	head.add_theme_color_override("font_color", Color(1, 0.95, 0.55))
	head.add_theme_color_override("font_outline_color", Color(0.2, 0, 0, 1))
	head.add_theme_constant_override("outline_size", 6)
	vbox.add_child(head)

	# 正文（白色长方形大字）
	var body := Label.new()
	body.text = ALERT_BODY
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 44)
	body.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	body.add_theme_color_override("font_outline_color", Color(0.25, 0, 0, 1))
	body.add_theme_constant_override("outline_size", 4)
	vbox.add_child(body)

	# 透明度初值 0（淡入）
	panel.modulate.a = 0.0

	# === 动画序列：淡入 → 闪 3 下 → 淡出 → 销毁 ===
	var tw := create_tween()
	# 1) 淡入
	tw.tween_property(panel, "modulate:a", 1.0, FADE_IN_S)
	# 2) 闪 FLASH_TIMES 下
	for i in range(FLASH_TIMES):
		tw.tween_property(panel, "modulate:a", 0.25, FLASH_HALF)
		tw.tween_property(panel, "modulate:a", 1.0, FLASH_HALF)
	# 3) 淡出
	tw.tween_property(panel, "modulate:a", 0.0, FADE_OUT_S)
	# 4) 销毁
	tw.tween_callback(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free()
	)
	print("[PressureAlert] 压力检测卡已弹出，position=%s" % center_pos)


# ============================================================
# 自动加载：PressureAlert 单例永远挂在 /root/Main/DialogueLayer 下
# 不需要手动 instantiate / set_position
# 通过 group "pressure_alert" 让任何脚本拿到：
#     var a = get_tree().get_first_node_in_group("pressure_alert")
#     a.show_alert(parent_canvas_layer)
# ============================================================