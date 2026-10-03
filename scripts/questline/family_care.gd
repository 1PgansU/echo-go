# ============================================================
# Family Care Questline · 亲情故事线（任务1：给爸妈倒水）
# ============================================================
# 设计：
#  - 玩家进入家（HomeMap）→ 顶部显示大字号任务横幅："任务1：给爸妈倒水"
#  - 玩家走到爸妈（father / mother）身边 → 浮现一个"倒水"按钮（仅在任务未完成时）
#  - 玩家点倒水 → 屏幕下方弹出"亲情值 +10"飘字 → 紧接着自动打开对应爸妈的对话框
#    （先强制插入一句固定的夸赞台词，再交给 LLM 接管后续对话）
#  - 任务一次性：给爸爸或妈妈任意一方倒水都算完成，永久隐藏倒水按钮
#  - 不修改原有 NPC/Portal/Chat 等功能
# ============================================================
extends Node

# ---------- 任务配置 ----------
const TASK_TITLE := "任务1：给爸妈倒水"
const AFFINITY_DELTA := 10
const TARGET_MAPS := ["home"]   # 哪些地图里显示任务横幅

# 强制夸赞台词（按 npc_id 分）—— 单行短句，单独一条消息，不混
const PRAISE_TEXT := {
	"father": "（爸爸笑着接过水）\n哟，今天太阳打西边出来了。",
	"mother": "（妈妈笑着接过水）\n哎哟，乖孩子。",
}

# 过渡台词（夸完之后、聊成绩之前的"委婉引入"）
# 单独一条消息，间隔 1 秒后注入
const TRANSITION_TEXT := {
	"father": "（爸爸放下杯子，笑容收了收）\n……嗳，爸问你个事儿。",
	"mother": "（妈妈放下杯子，擦了擦手）\n……对了，妈跟你聊个事儿。",
}

# 倒水按钮距离（像素）：玩家中心与 NPC 中心距离 < 这个值就显示按钮
const NEAR_DIST := 96.0

# ---------- 状态 ----------
var _task_done: bool = false
var _served_npc: String = ""    # 任务完成时，记录是给谁倒的水（"father" / "mother"）

# ---------- 压力警报触发追踪 ----------
var _alert_pending: bool = false    # 正在等"施压台词"出现
var _alert_history_baseline: int = 0  # 触发 pending 时的 chat_history 长度
var _alert_timer_remaining: float = -1.0  # 检测到施压后倒计时（1.5s 后弹 alert）
var _alert_wait_elapsed: float = 0.0  # 等待施压台词已耗时，用于超时
var _scan_logged: bool = false  # 是否已打印过一次扫描（用于调试）
const _PRESSURE_KEYWORDS: Array = ["考试", "小柚", "成绩", "分数", "考得", "考分", "名次"]
const _PRESSURE_WAIT_TIMEOUT: float = 25.0  # 最多等 25 秒，超时就放弃弹 alert

# ---------- UI 引用（运行时查找） ----------
var _world_ui: CanvasLayer = null
var _banner_label = null        # 顶部任务横幅
var _floating_label = null       # 屏幕下方"+10 亲情值"飘字
var _father_water_btn = null
var _mother_water_btn = null
var _hammer_btn = null          # 任务完成后挂在 NPC 头顶的"锤他"按钮
var _hammer_popup_label = null  # 锤一下后飘出的数字
var _hammer_count: int = 0              # 累计锤的次数（可拿来做表情用）
var _hammer_sfx_player: AudioStreamPlayer = null   # 锤击音效播放器（运行时懒加载）
var _hammer_sfx_buf: PackedByteArray                # 预生成好的 wav bytes


func _ready() -> void:
	add_to_group("family_care_quest")
	# 等一帧再连信号（GameManager / MapManager 一定已经在了）
	call_deferred("_initialize")


func _initialize() -> void:
	# 监听 MapManager 切图 → 进入 home 时显示横幅
	var mm = get_node_or_null("/root/MapManager")
	if mm and mm.has_signal("map_changed"):
		if not mm.map_changed.is_connected(_on_map_changed):
			mm.map_changed.connect(_on_map_changed)
	# 轮询：每帧检查玩家是否在爸妈身边
	set_process(true)
	print("[FamilyCare] questline initialized")


func _process(_delta: float) -> void:
	# 失效引用清理（NPC / 按钮 切图后被释放，引用还在）
	if _father_water_btn != null and not is_instance_valid(_father_water_btn):
		_father_water_btn = null
	if _mother_water_btn != null and not is_instance_valid(_mother_water_btn):
		_mother_water_btn = null
	if _hammer_btn != null and not is_instance_valid(_hammer_btn):
		_hammer_btn = null
	if _hammer_popup_label != null and not is_instance_valid(_hammer_popup_label):
		_hammer_popup_label = null
	if _floating_label != null and not is_instance_valid(_floating_label):
		_floating_label = null
	if _banner_label != null and not is_instance_valid(_banner_label):
		_banner_label = null
	# 等待施压台词出现后倒计时（1.5s 后弹 alert）
	if _alert_pending:
		_alert_wait_elapsed += _delta
		if _alert_wait_elapsed > _PRESSURE_WAIT_TIMEOUT:
			# 超时：放弃弹 alert（LLM 一直没输出施压）
			print("[FamilyCare] 等待施压台词超时（%.1fs），放弃弹警报" % _PRESSURE_WAIT_TIMEOUT)
			_alert_pending = false
		else:
			# === 关键修改：不再依赖 _check_pressure_dialogue 轮询 chat_history ===
			# 因为 ChatDialogue._on_opening_ready 只显示气泡不 append 到 chat_history，
			# 而 start_chat 会清空 history，导致 baseline 计算不可靠。
			# 改为监听 LLMClient.llm_reply_received 信号（_on_llm_reply_for_alert）
			# 这里只负责 1.5s 倒计时
			if _alert_timer_remaining > 0.0:
				_alert_timer_remaining -= _delta
				if _alert_timer_remaining <= 0.0:
					_alert_pending = false
					_trigger_pressure_alert()
	# 任务完成后：所有倒水按钮永久隐藏
	if _task_done:
		_set_water_btn_visible(_father_water_btn, false)
		_set_water_btn_visible(_mother_water_btn, false)
		return
	var current_map_id := _get_current_map_id()
	if current_map_id != "home":
		_set_water_btn_visible(_father_water_btn, false)
		_set_water_btn_visible(_mother_water_btn, false)
		return
	# 检查附近 NPC
	var father := _find_npc_by_id("father")
	var mother := _find_npc_by_id("mother")
	_set_water_btn_visible(_father_water_btn, _is_player_near(father))
	_set_water_btn_visible(_mother_water_btn, _is_player_near(mother))


# 扫描 chat_history，看 baseline 之后是否有新 assistant 消息
# 一旦出现任意一条新 NPC 消息（施压对话开始），就启动 1.5s 倒计时
func _check_pressure_dialogue() -> void:
	if _alert_timer_remaining > 0.0:
		return  # 已经在倒计时
	var gm = get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("get_chat_dialogue"):
		return
	var chat = gm.call("get_chat_dialogue")
	if chat == null or not is_instance_valid(chat):
		return
	if not "chat_history" in chat:
		return
	var history: Array = chat.chat_history
	# 调试：每次扫描都打一条（追踪是否还在扫描）
	if not _scan_logged:
		print("[FamilyCare] _scan_pressure_dialogue 首次执行：baseline=%d, history.size=%d" % [_alert_history_baseline, history.size()])
		_scan_logged = true
	# 只看 baseline 之后新增的 assistant 消息（任意新 NPC 消息都算"施压开始"）
	for i in range(_alert_history_baseline, history.size()):
		var entry = history[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if entry.get("role", "") != "assistant":
			continue
		var content: String = entry.get("content", "")
		if content == null or content == "":
			continue
		print("[FamilyCare] 检测到新 NPC 消息，1.5s 后弹警报：%s" % content.substr(0, 30))
		_alert_timer_remaining = 1.5
		return


# 由 _serve_water() 调用，开启"等施压台词 + 然后弹 alert"的监听
func _arm_pressure_alert() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("get_chat_dialogue"):
		return
	var chat = gm.call("get_chat_dialogue")
	if chat == null or not is_instance_valid(chat):
		return
	if not "chat_history" in chat:
		return
	_alert_pending = true
	_alert_timer_remaining = -1.0
	_alert_history_baseline = (chat.chat_history as Array).size()
	_scan_logged = false
	print("[FamilyCare] 已开启施压台词监听（baseline=%d）" % _alert_history_baseline)

	# === 关键修复：直接订阅 LLMClient 的 llm_reply_received 信号 ===
	# 这样不需要轮询 chat_history，LLM 一回话立刻触发倒计时
	var llm = get_node_or_null("/root/LLMClient")
	if llm and not llm.llm_reply_received.is_connected(_on_llm_reply_for_alert):
		llm.llm_reply_received.connect(_on_llm_reply_for_alert)
		print("[FamilyCare] 已订阅 LLMClient.llm_reply_received")

func _on_llm_reply_for_alert(npc_id: String, text: String) -> void:
	# 只在监听期间触发
	if not _alert_pending:
		return
	print("[FamilyCare] LLM 回复（np=%s），1.5s 后弹警报：%s" % [npc_id, text.substr(0, 30)])
	_alert_timer_remaining = 1.5


# ============================================================
# 地图切换：进入 home —— 横幅不再自动显示（默认隐藏）
# ============================================================
func _on_map_changed(_new_map_id: String) -> void:
	# 横幅默认隐藏，玩家通过其他方式了解任务
	_hide_banner()


# ============================================================
# 顶部任务横幅（页面顶部 · 大字号 · 非常明显）
# ============================================================
func _show_banner() -> void:
	# 已禁用：任务横幅默认隐藏（不再自动显示）
	_hide_banner()


func _hide_banner() -> void:
	_ensure_banner()
	if _banner_label:
		var panel: Node = _banner_label.get_parent()
		if panel:
			panel.visible = false


func _ensure_banner() -> void:
	if _banner_label and is_instance_valid(_banner_label):
		return
	# 找 WorldUI（多策略）
	var world_ui: Node = _find_world_ui()
	if world_ui == null:
		push_warning("[FamilyCare] 找不到 WorldUI，顶栏横幅无法挂载")
		return

	var panel := PanelContainer.new()
	panel.name = "FamilyCareBanner"
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 0
	panel.offset_top = 80
	panel.offset_right = 0
	panel.offset_bottom = 152
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.78, 0.18, 0.18, 0.94)         # 醒目暖红
	sb.border_color = Color(0.99, 0.82, 0.45, 1)
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.content_margin_left = 28
	sb.content_margin_top = 14
	sb.content_margin_right = 28
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.z_index = 100

	var label := Label.new()
	label.name = "TaskTitle"
	label.text = TASK_TITLE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 非常大、非常明显
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color(1, 0.97, 0.86, 1))
	label.add_theme_color_override("font_outline_color", Color(0.18, 0.05, 0.05, 1))
	label.add_theme_constant_override("outline_size", 8)
	panel.add_child(label)

	panel.visible = false   # 默认隐藏 —— 横幅不再自动显示
	world_ui.add_child(panel)
	_banner_label = label


# ============================================================
# 屏幕下方"亲情值 +10"飘字
# ============================================================
func _show_affinity_popup() -> void:
	var main = _get_main_node()
	if main == null:
		return
	var layer = main.get_node_or_null("DialogueLayer")
	if layer == null:
		return

	# 如果已经在播，先清掉
	if _floating_label and is_instance_valid(_floating_label):
		_floating_label.queue_free()

	var label := Label.new()
	label.name = "AffinityPopup"
	label.text = "💖 亲情值 +%d" % AFFINITY_DELTA
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_left = -280
	label.offset_top = -200
	label.offset_right = 280
	label.offset_bottom = -140
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
	label.add_theme_color_override("font_outline_color", Color(0.25, 0.10, 0.05, 1))
	label.add_theme_constant_override("outline_size", 8)
	label.modulate.a = 0.0
	label.z_index = 200
	layer.add_child(label)
	_floating_label = label

	# 动画：淡入 + 向上漂 + 淡出
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.25)
	tween.tween_property(label, "offset_top", -260, 1.6).set_delay(0.15)
	tween.set_parallel(false)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func() -> void:
		if is_instance_valid(label):
			label.queue_free()
		if _floating_label == label:
			_floating_label = null
	)


# ============================================================
# 倒水按钮（HomeMap 上 · 走到爸妈身边才显示）
# ============================================================
func _ensure_water_buttons() -> void:
	# 把按钮挂到 NPC 节点上 → 跟随 NPC 移动/呼吸
	var father := _find_npc_by_id("father")
	if _father_water_btn == null and father:
		var btn := _make_water_button("father")
		father.add_child(btn)
		btn.position = Vector2(-48, -110)   # NPC 上方一点（按钮 96 宽）
		btn.visible = false
		_father_water_btn = btn
	var mother := _find_npc_by_id("mother")
	if _mother_water_btn == null and mother:
		var btn := _make_water_button("mother")
		mother.add_child(btn)
		btn.position = Vector2(-48, -110)
		btn.visible = false
		_mother_water_btn = btn


func _make_water_button(npc_id: String) -> Button:
	var btn := Button.new()
	btn.name = "WaterButton_%s" % npc_id
	btn.text = "💧 倒水"
	btn.custom_minimum_size = Vector2(96, 44)
	# 视觉样式（显眼蓝色）
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.30, 0.55, 0.85, 1)
	sb_normal.corner_radius_top_left = 10
	sb_normal.corner_radius_top_right = 10
	sb_normal.corner_radius_bottom_left = 10
	sb_normal.corner_radius_bottom_right = 10
	sb_normal.border_width_left = 2
	sb_normal.border_width_top = 2
	sb_normal.border_width_right = 2
	sb_normal.border_width_bottom = 2
	sb_normal.border_color = Color(1, 1, 1, 0.85)
	sb_normal.content_margin_left = 12
	sb_normal.content_margin_top = 8
	sb_normal.content_margin_right = 12
	sb_normal.content_margin_bottom = 8
	var sb_hover := sb_normal.duplicate()
	sb_hover.bg_color = Color(0.40, 0.70, 1.0, 1)
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	# 绑定点击
	btn.pressed.connect(_on_water_btn_pressed.bind(npc_id))
	return btn


func _on_water_btn_pressed(npc_id: String) -> void:
	if _task_done:
		return
	# 1) 立即把两个倒水按钮都关掉（防止连点）
	_set_water_btn_visible(_father_water_btn, false)
	_set_water_btn_visible(_mother_water_btn, false)
	# 2) 标记任务完成
	_task_done = true
	_served_npc = npc_id
	# 3) 加亲情值（GameManager 有接口 add_relationship）
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("add_relationship"):
		gm.add_relationship(npc_id, AFFINITY_DELTA)
	# 4) 屏幕下方飘字
	_show_affinity_popup()
	# 5) 立刻打开对应爸妈的对话框，先注入固定的夸赞台词
	_open_chat_with_praise(npc_id)
	# 6) 任务完成 → QuestList 第 4 节点标 done（横幅保留，由玩家主动结束任务时再关）
	_mark_quest_list_done()
	print("[FamilyCare] 已给 %s 倒水，亲情值+%d，任务完成" % [npc_id, AFFINITY_DELTA])


# 把 QuestList 的第 4 个节点（亲情：倒水）标成 done
func _mark_quest_list_done() -> void:
	var ql := _find_quest_list()
	if ql == null:
		# QuestList 还没加载（比如玩家在 home 还没见过 WorldUI）→ 延迟再试
		var t := get_tree().create_timer(0.6)
		t.timeout.connect(_mark_quest_list_done)
		return
	if ql.has_method("set_node_state"):
		ql.call("set_node_state", 3, "done")
		print("[FamilyCare] QuestList 节点4 标记为 done")


func _find_quest_list() -> Node:
	# 复用 Act1 的查找方式（同一份 UI）
	var paths := [
		"/root/Root/Main/DialogueLayer/WorldUI/QuestList",
		"/root/Root/Main/WorldUI/QuestList",
		"/root/Main/DialogueLayer/WorldUI/QuestList",
		"/root/Main/WorldUI/QuestList",
	]
	for p in paths:
		var q = get_node_or_null(p)
		if q:
			return q
	var group_nodes = get_tree().get_nodes_in_group("quest_list")
	if group_nodes.size() > 0:
		return group_nodes[0]
	return null


func _open_chat_with_praise(npc_id: String) -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		push_warning("[FamilyCare] GameManager 找不到，无法打开聊天")
		return
	var chat = null
	if gm.has_method("get_chat_dialogue"):
		chat = gm.call("get_chat_dialogue")
	if chat == null:
		push_warning("[FamilyCare] ChatDialogue 找不到")
		return
	# 先开聊天
	chat.start_chat(npc_id)
	# 立刻开启施压台词监听（baseline 在 start_chat 清空 history 之后取）
	_arm_pressure_alert()
	# 节拍序列：
	#   t=0.05s   注入夸赞台词（独立一条消息）
	#   t=1.10s   注入过渡台词（独立一条消息）
	#   t=2.10s   给 LLM 聊考试的指令
	#   [等待 LLM 在 chat_history 中输出施压台词] → 检测到后 1.5 秒弹压力警报
	var t := get_tree().create_timer(0.05)
	t.timeout.connect(func() -> void:
		if chat and is_instance_valid(chat) and chat.has_method("add_npc_text"):
			chat.call("add_npc_text", npc_id, PRAISE_TEXT.get(npc_id, "（接过水）\n谢谢你，乖孩子。"))
		# 1 秒后注入过渡台词（让父母缓一缓再开口）
		var t2 := get_tree().create_timer(1.0)
		t2.timeout.connect(func() -> void:
			if chat and is_instance_valid(chat) and chat.has_method("add_npc_text"):
				chat.call("add_npc_text", npc_id, TRANSITION_TEXT.get(npc_id, "……对了，妈跟你聊个事儿。"))
		)
		# 再过 1 秒（夸赞+1s 过渡，过渡+1s 开始聊考试）给 LLM 节拍指令：聊成绩 + 小柚 + 施压
		var t3 := get_tree().create_timer(1.0)
		t3.timeout.connect(func() -> void:
			if chat and is_instance_valid(chat) and chat.has_method("set_phase_hint"):
				var target_name: String = "小柚"
				chat.call("set_phase_hint",
					"【节拍指令】玩家刚给" + npc_id + "倒了一杯水。\n"
					+ "你（" + npc_id + "）已经按顺序说了：\n"
					+ "第1条：夸赞玩家（已说过）。\n"
					+ "第2条：过渡台词『爸/妈问你个事儿』（已说过）。\n"
					+ "现在（第 3 步），请你接着说 2 句话，话题转到『期末考试成绩』：\n"
					+ "第1句：提起期末考试，语气和缓地表达『感觉你考得没有你的朋友" + target_name + "好』。\n"
					+ "第2句：叹气 + 比较 + 暗示失望——典型中国家长的『关心式施压』语气。\n"
					+ "说完 2 句就安静等玩家回复，不要追问、不要继续施压、不要讲道理。")
		)
	)


# ============================================================
# 弹出"压力检测"卡片
# PressureAlert 是 autoload 节点（/root/PressureAlert），可以直接拿到
# ============================================================
func _trigger_pressure_alert() -> void:
	print("[FamilyCare] _trigger_pressure_alert() 被调用")
	var alert := get_node_or_null("/root/PressureAlert")
	if alert == null:
		alert = get_tree().get_first_node_in_group("pressure_alert")
	if alert == null:
		push_warning("[FamilyCare] PressureAlert 找不到（autoload 没注册？）")
		return

	# 找 DialogueLayer（多策略）
	var layer: CanvasLayer = _find_dialogue_layer()
	if layer == null:
		push_warning("[FamilyCare] DialogueLayer 找不到，压力卡无法挂载")
		return
	if alert.has_method("show_alert"):
		alert.call("show_alert", layer)
		print("[FamilyCare] 触发 PressureAlert → layer=", layer.get_path())
	else:
		push_warning("[FamilyCare] PressureAlert 没有 show_alert() 方法")

	# 警报显示 2.5s + 缓冲 0.5s = 3s 后：强制关闭对话框 + 生成"锤他"按钮
	var t := get_tree().create_timer(3.0)
	t.timeout.connect(_on_alert_finished)


# ============================================================
# 工具方法
# ============================================================
func _find_dialogue_layer() -> CanvasLayer:
	# 策略 1：硬编码路径
	for p in ["/root/Root/Main/DialogueLayer", "/root/Main/DialogueLayer", "/root/DialogueLayer"]:
		var n: Node = get_node_or_null(p)
		if n is CanvasLayer:
			return n
	# 策略 2：group
	for c in get_tree().get_nodes_in_group("dialogue_layer"):
		if c is CanvasLayer:
			return c
	# 策略 3：扫整个 /root 树，挑 layer 最大（>= 50）的 CanvasLayer
	var candidates: Array = []
	_collect_canvas_layers(get_tree().root, candidates)
	candidates.sort_custom(func(a, b): return a["layer"] > b["layer"])
	for entry in candidates:
		var n: Node = entry["node"]
		if n.layer >= 50:
			return n
	# 兜底：随便挑一个 CanvasLayer
	if candidates.size() > 0:
		return candidates[0]["node"]
	return null


# ============================================================
# 工具方法
# ============================================================
func _get_current_map_id() -> String:
	var mm = get_node_or_null("/root/MapManager")
	if mm and "current_map" in mm and mm.current_map and "map_id" in mm.current_map:
		return mm.current_map.map_id
	return ""


func _get_current_map() -> Node:
	var mm = get_node_or_null("/root/MapManager")
	if mm and mm.current_map:
		return mm.current_map
	return null


# 兼容两种 Main 路径：/root/Root/Main（Main.tscn 当前结构）或 /root/Main
func _get_main_node() -> Node:
	var m = get_node_or_null("/root/Root/Main")
	if m != null:
		return m
	return get_node_or_null("/root/Main")


func _find_npc_by_id(npc_id: String) -> Node:
	var map = _get_current_map()
	if map == null:
		return null
	for child in map.get_children():
		if child == null:
			continue
		if child is Area2D and child.is_in_group("npcs") and "npc_id" in child and child.npc_id == npc_id:
			return child
	return null


# 递归收集所有 CanvasLayer
func _collect_canvas_layers(node: Node, out: Array) -> void:
	if node is CanvasLayer:
		out.append({"node": node, "layer": node.layer})
	for child in node.get_children():
		_collect_canvas_layers(child, out)


func _is_player_near(npc: Node) -> bool:
	if npc == null:
		return false
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	# 首次调用时确保按钮已建好
	if _father_water_btn == null or _mother_water_btn == null:
		_ensure_water_buttons()
	var d: float = player.global_position.distance_to(npc.global_position)
	return d <= NEAR_DIST


func _set_water_btn_visible(btn, visible: bool) -> void:
	if btn == null:
		return
	# 用 weakref 包一层再验证，避免 typed 参数在 freed 节点上报错
	var w: WeakRef = weakref(btn)
	var alive = w.get_ref()
	if alive == null:
		# 节点已被释放（切图时），清掉我们的引用
		if btn == _father_water_btn:
			_father_water_btn = null
		elif btn == _mother_water_btn:
			_mother_water_btn = null
		return
	if alive.visible == visible:
		return
	alive.visible = visible


# 找 WorldUI（不依赖硬编码路径）
func _find_world_ui() -> Node:
	# 策略 1：硬编码路径
	for p in ["/root/Root/Main/DialogueLayer/WorldUI", "/root/Main/DialogueLayer/WorldUI",
			"/root/Root/Main/WorldUI", "/root/Main/WorldUI"]:
		var n: Node = get_node_or_null(p)
		if n != null:
			return n
	# 策略 2：group
	var gs := get_tree().get_nodes_in_group("world_ui")
	if gs.size() > 0:
		return gs[0]
	# 策略 3：name == WorldUI
	for c in get_tree().get_nodes_in_group("ui_root"):
		var wu := c.get_node_or_null("WorldUI")
		if wu:
			return wu
	# 策略 4：扫整个树，找 WorldUI.tscn 的根（用 script 关联）
	for c in get_tree().root.find_children("*", "Control", true, false):
		if c.name == "WorldUI":
			return c
	return null


# ============================================================
# 警报结束后：自动关闭对话框 + 在被递水 NPC 头顶生成"锤他"按钮
# ============================================================
func _on_alert_finished() -> void:
	print("[FamilyCare] 警报播放完毕，关闭对话框 + 生成'锤他'按钮")
	# 1) 强制关闭 ChatDialogue
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_chat_dialogue"):
		var chat = gm.call("get_chat_dialogue")
		if chat and is_instance_valid(chat) and chat.has_method("_close_chat"):
			chat.call("_close_chat")
	# 2) 关闭 _alert_pending —— 不再监听施压
	_alert_pending = false
	# 3) 在被递水的 NPC 头顶生成"锤他"按钮
	_spawn_hammer_btn(_served_npc)


func _spawn_hammer_btn(npc_id: String) -> void:
	if _hammer_btn != null and is_instance_valid(_hammer_btn):
		return  # 已生成过，避免重复
	var npc := _find_npc_by_id(npc_id)
	if npc == null:
		push_warning("[FamilyCare] 找不到 NPC %s，锤他按钮无法生成" % npc_id)
		return
	_hammer_count = 0

	# === 按钮：锤子造型 · 暖红底 · 金黄描边 · 不大不小（240×280）===
	var btn := Button.new()
	btn.name = "HammerBtn"
	btn.text = "🔨\n锤他"
	btn.custom_minimum_size = Vector2(240, 280)
	# 普通态
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.90, 0.30, 0.25, 1)      # 暖红
	sb_normal.border_color = Color(1, 0.85, 0.40, 1)     # 金黄边框
	sb_normal.border_width_left = 5
	sb_normal.border_width_top = 5
	sb_normal.border_width_right = 5
	sb_normal.border_width_bottom = 5
	sb_normal.corner_radius_top_left = 16
	sb_normal.corner_radius_top_right = 16
	sb_normal.corner_radius_bottom_left = 16
	sb_normal.corner_radius_bottom_right = 16
	sb_normal.content_margin_left = 12
	sb_normal.content_margin_top = 10
	sb_normal.content_margin_right = 12
	sb_normal.content_margin_bottom = 10
	# 按下态
	var sb_pressed := sb_normal.duplicate()
	sb_pressed.bg_color = Color(0.78, 0.18, 0.18, 1)
	# 悬停态
	var sb_hover := sb_normal.duplicate()
	sb_hover.bg_color = Color(0.98, 0.42, 0.32, 1)
	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_font_size_override("font_size", 56)
	btn.add_theme_color_override("font_color", Color(1, 1, 0.85))
	btn.add_theme_color_override("font_outline_color", Color(0.20, 0.05, 0.05))
	btn.add_theme_constant_override("outline_size", 4)

	# 挂在 NPC 节点之上（跟随 NPC 移动）
	npc.add_child(btn)
	# 按钮中心对准 NPC 上方一点（按钮宽 240，所以 offset_x = -120）
	btn.position = Vector2(-120, -360)

	# 点击 → 锤子动画 + 飘字
	btn.pressed.connect(_on_hammer_pressed.bind(npc))
	_hammer_btn = btn


func _on_hammer_pressed(npc: Node) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	_hammer_count += 1
	print("[FamilyCare] 锤第 %d 下" % _hammer_count)
	var npc2d := npc as Node2D
	if npc2d == null:
		push_warning("[FamilyCare] 锤他目标不是 Node2D，终止")
		return

	# 0) 播放"啪"打击音效
	_play_hammer_sfx()
	# 1) 按钮轻微"砸下去"回弹（按下时 tween 缩放）
	if _hammer_btn and is_instance_valid(_hammer_btn):
		var tw: Tween = _hammer_btn.create_tween()
		tw.tween_property(_hammer_btn, "scale", Vector2(0.82, 0.82), 0.06)
		tw.tween_property(_hammer_btn, "scale", Vector2(1.15, 1.15), 0.08)
		tw.tween_property(_hammer_btn, "scale", Vector2(1.0, 1.0), 0.10)
	# 2) NPC 抖动（被锤）
	var shake := npc2d.create_tween()
	var origin: Vector2 = npc2d.position
	shake.tween_property(npc2d, "position", origin + Vector2(8, 0), 0.04)
	shake.tween_property(npc2d, "position", origin + Vector2(-8, 0), 0.04)
	shake.tween_property(npc2d, "position", origin + Vector2(6, -4), 0.04)
	shake.tween_property(npc2d, "position", origin, 0.06)
	# 3) 飘字：累计次数（蓝色"N连击"）
	if _hammer_popup_label and is_instance_valid(_hammer_popup_label):
		_hammer_popup_label.queue_free()
	var popup := Label.new()
	popup.text = "👊×%d" % _hammer_count
	popup.add_theme_font_size_override("font_size", 56)
	popup.add_theme_color_override("font_color", Color(1, 0.95, 0.55))
	popup.add_theme_color_override("font_outline_color", Color(0.20, 0.05, 0.05))
	popup.add_theme_constant_override("outline_size", 6)
	popup.z_index = 200
	popup.modulate.a = 0.0
	npc.add_child(popup)
	popup.position = Vector2(-80, -480)
	_hammer_popup_label = popup
	var tw2 := npc.create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(popup, "modulate:a", 1.0, 0.10)
	tw2.tween_property(popup, "position", popup.position + Vector2(0, -60), 0.6).set_ease(Tween.EASE_OUT)
	tw2.set_parallel(false)
	tw2.tween_property(popup, "modulate:a", 0.0, 0.4)
	tw2.tween_callback(func() -> void:
		if is_instance_valid(popup):
			popup.queue_free()
	)
	# 4) 累加 N 触发 NPC 委屈表情阶段
	_update_npc_hurt_mood(npc2d, _hammer_count)


# ============================================================
# 锤击音效（运行时生成 AudioStreamWAV · 零外部依赖）
# "啪"声设计：
#   - 总时长 0.18s
#   - 短促低频"砰"（80Hz 半衰减）+ 高频"啪"（1200Hz 短脉冲）相加
#   - 振幅随时间指数衰减
# ============================================================
func _ensure_hammer_sfx() -> void:
	if _hammer_sfx_player != null and is_instance_valid(_hammer_sfx_player):
		return
	_hammer_sfx_player = AudioStreamPlayer.new()
	_hammer_sfx_player.bus = "Master"
	add_child(_hammer_sfx_player)
	_hammer_sfx_player.stream = _make_hammer_wav()
	print("[FamilyCare] 锤击 SFX 已就绪（runtime AudioStreamWAV）")


func _make_hammer_wav() -> AudioStreamWAV:
	# 参数
	var sample_rate: int = 22050
	var duration: float = 0.18
	var frames: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)  # 16-bit 单声道
	# 合成（拆分成多步，避免 GDScript 解析器在长表达式上卡住）
	var two_pi: float = 6.2831853
	for i in range(frames):
		var t: float = float(i) / float(sample_rate)
		var env: float = exp(-t * 22.0)
		var low: float = sin(t * two_pi * 80.0) * 0.55
		var hi: float = 0.0
		if t < 0.04:
			var noise: float = randf() * 2.0 - 1.0
			var fade: float = 1.0 - t / 0.04
			hi = noise * 0.45 * fade
		var sample_f: float = (low + hi) * env
		# 手动量化 16-bit PCM（手动 if 限制范围）
		var v: int = int(sample_f * 32767.0)
		if v > 32767:
			v = 32767
		if v < -32768:
			v = -32768
		var lo: int = v & 0xFF
		var hi2: int = (v >> 8) & 0xFF
		data[i * 2] = lo
		data[i * 2 + 1] = hi2
	var stream := AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _play_hammer_sfx() -> void:
	_ensure_hammer_sfx()
	if _hammer_sfx_player == null:
		return
	# 每次都"重新设 stream" → 让 play() 立刻从头播放（避免同 stream 重复 play 不重置位置）
	_hammer_sfx_player.stream = _make_hammer_wav()
	_hammer_sfx_player.play()


# ============================================================
# 锤击累积 → NPC 委屈表情阶段
#   1-4:    轻微皱眉（橙 😐）
#   5-9:    委屈（黄 🥺）
#   10-19:  泪奔（红 😭） + 头顶冒黑线
#   20+:    倒下（离开地图，飘字"我被你锤没了"）
# ============================================================
func _update_npc_hurt_mood(npc: Node2D, count: int) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	# NPC 的 label = NameLabel（带 emoji），直接覆盖文本 + 颜色
	var name_label: Label = npc.get_node_or_null("NameLabel")
	if name_label == null:
		return
	var npc_name: String = npc.npc_name if "npc_name" in npc else "NPC"
	var emoji := "😐"
	var color := Color(1, 1, 1, 1)
	if count >= 20:
		emoji = "💀"
		color = Color(0.6, 0.6, 0.6, 1)
	elif count >= 10:
		emoji = "😭"
		color = Color(1, 0.35, 0.35, 1)
	elif count >= 5:
		emoji = "🥺"
		color = Color(1, 0.55, 0.30, 1)
	elif count >= 1:
		emoji = "😣"
		color = Color(1, 0.85, 0.50, 1)
	name_label.text = "%s  %s" % [npc_name, emoji]
	name_label.add_theme_color_override("font_color", color)
	print("[FamilyCare] NPC 委屈阶段 #%d → emoji=%s" % [count, emoji])

	# 阶段 20：NPC "倒下"动画 + 移出可见区（仍在节点树里，玩家不能再交互）
	if count == 20:
		_play_hammer_sfx()
		var fall := npc.create_tween()
		fall.set_parallel(true)
		fall.tween_property(npc, "rotation_degrees", 90.0, 0.6)
		fall.tween_property(npc, "modulate:a", 0.3, 0.6)
		fall.set_parallel(false)
		# 飘字："我被你锤没了"
		var bye := Label.new()
		bye.text = "💢 我被你锤没了…"
		bye.add_theme_font_size_override("font_size", 32)
		bye.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
		bye.add_theme_color_override("font_outline_color", Color(0.2, 0.05, 0.05))
		bye.add_theme_constant_override("outline_size", 5)
		bye.z_index = 200
		npc.add_child(bye)
		bye.position = Vector2(-160, -180)
		var tw := npc.create_tween()
		tw.tween_property(bye, "position", bye.position + Vector2(0, -80), 2.0).set_ease(Tween.EASE_OUT)
		tw.tween_property(bye, "modulate:a", 0.0, 1.0).set_delay(1.0)
