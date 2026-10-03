# QuestList：右上角任务清单（2 个节点 + 状态）
# 状态: "locked"（灰） / "active"（亮蓝） / "done"（✓）
extends PanelContainer

var _quest: Node = null  # Act1 引用（可选）
var _nodes := []        # 2 个 Button
var _labels := []       # 2 个 Label 描述


func _ready() -> void:
	add_to_group("quest_list")  # 让 Act1 容易找到
	# 构造内部 UI：VBoxContainer + 3 个 row
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var titles := [
		"① 破冰：跟小羊说第一句话",
		"② 下棋：跟小羊下一盘五子棋",
		"③ 亲情：给爸妈倒水",
		"④ 发泄：锤他",
	]

	for i in range(titles.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)

		var lbl := Label.new()
		lbl.text = titles[i]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(lbl)
		_labels.append(lbl)

		var btn := Button.new()
		btn.text = "●"
		btn.custom_minimum_size = Vector2(40, 28)
		btn.disabled = true  # 纯展示，不点
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		btn.tooltip_text = titles[i]
		row.add_child(btn)
		_nodes.append(btn)

	set_node_state(0, "active")  # 节点1 永远最先亮


# 外部调用：index 0/1 ; state "locked"/"active"/"done"
func set_node_state(index: int, state: String) -> void:
	if index < 0 or index >= _nodes.size():
		return
	var btn: Button = _nodes[index]
	var lbl: Label = _labels[index]
	match state:
		"locked":
			lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
			btn.text = "○"
			btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		"active":
			lbl.add_theme_color_override("font_color", Color(0.957, 0.886, 0.4))
			btn.text = "▶"
			btn.add_theme_color_override("font_color", Color(0.957, 0.886, 0.4))
		"done":
			lbl.add_theme_color_override("font_color", Color(0.5, 0.78, 0.5))
			btn.text = "✓"
			btn.add_theme_color_override("font_color", Color(0.5, 0.78, 0.5))


# 反向连接 Act1（这里只是接口预留，不调用也行）
func bind_questline(q: Node) -> void:
	_quest = q