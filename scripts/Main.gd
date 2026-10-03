# 主控制器：管理场景切换（封面 / 世界 / 对话）
extends Node2D

@onready var cover: Control = $UILayer/Cover
@onready var world_root: Node2D = $WorldRoot
@onready var dialogue_layer: CanvasLayer = $DialogueLayer

var dialogue_ui: Control = null
var chat_dialogue: Control = null
var world_ui: CanvasLayer = null  # WorldUI.tscn 实例
var player: Node = null            # 玩家节点（持久，跨地图移动）
var offline_clock: Node = null     # 离线时钟（统一调度离线模拟）
var memory_panel: CanvasLayer = null  # 奇遇回看面板（按 Q）
var diary_panel: CanvasLayer = null   # NPC 日记面板（按 J）
var festival_panel: CanvasLayer = null # 节日弹窗（按 G）
var album_panel: CanvasLayer = null    # 回忆相册（按 P）
var group_chat_panel: CanvasLayer = null # 微信群聊（按 C）
var quest_ui: CanvasLayer = null       # 好感任务（按 K）


func _ready() -> void:
	add_to_group("main")
	add_to_group("world_root")  # 让 MapManager 能找到 WorldRoot
	cover.visible = true
	# === 封面的两个按钮：信号接进来 ===
	# CoverStart 自身（extends Control）有 start_pressed / continue_pressed 信号
	if cover.has_signal("start_pressed"):
		cover.start_pressed.connect(_on_start_pressed)
	if cover.has_signal("continue_pressed"):
		cover.continue_pressed.connect(_on_continue_pressed)

	# 实例化 DialogueUI（全局可见）
	var dialogue_scene = load("res://scenes/DialogueUI.tscn")
	if dialogue_scene:
		dialogue_ui = dialogue_scene.instantiate()
		dialogue_layer.add_child(dialogue_ui)

	# 实例化 ChatDialogue（全局可见，默认隐藏）
	var chat_scene = load("res://scenes/ChatDialogue.tscn")
	if chat_scene:
		chat_dialogue = chat_scene.instantiate()
		dialogue_layer.add_child(chat_dialogue)

	# 注册到 GameManager
	var gm = get_node("/root/GameManager")
	if gm:
		gm.register_dialogue_ui(dialogue_ui)
		gm.register_chat_dialogue(chat_dialogue)

	# 实例化 WorldUI（跨地图常驻 UI）
	var world_ui_scene = load("res://scenes/WorldUI.tscn")
	print("[Main] load WorldUI.tscn = %s" % (world_ui_scene != null))
	if world_ui_scene:
		world_ui = world_ui_scene.instantiate()
		dialogue_layer.add_child(world_ui)
		var names = []
		for c in world_ui.get_children():
			names.append(c.name)
		print("[Main] WorldUI 实例化完成，子节点 = %s" % str(names))

	# === 实例化 NPC 日记面板（按 E 偷看日记）===
	var diary_script = load("res://scripts/ui/npc_diary_panel.gd")
	if diary_script:
		diary_panel = diary_script.new()
		diary_panel.name = "NPCDiaryPanel"
		dialogue_layer.add_child(diary_panel)
		print("[Main] NPC 日记面板已挂载（按 E 打开）")

	# === 实例化节日弹窗（按 G 打开日历）===
	var festival_script = load("res://scripts/ui/festival_popup.gd")
	if festival_script:
		festival_panel = festival_script.new()
		festival_panel.name = "FestivalPopup"
		dialogue_layer.add_child(festival_panel)
		print("[Main] 节日弹窗已挂载（按 G 打开日历）")

	# === 实例化回忆相册（按 P 打开）===
	var album_script = load("res://scripts/ui/memory_album_panel.gd")
	if album_script:
		album_panel = album_script.new()
		album_panel.name = "MemoryAlbumPanel"
		dialogue_layer.add_child(album_panel)
		print("[Main] 回忆相册已挂载（按 P 打开）")

	# === 实例化微信群聊（按 C 打开）===
	var chat_script = load("res://scripts/ui/group_chat_panel.gd")
	if chat_script:
		group_chat_panel = chat_script.new()
		group_chat_panel.name = "GroupChatPanel"
		dialogue_layer.add_child(group_chat_panel)
		print("[Main] 微信群聊已挂载（按 C 打开）")

	# === 快捷键速查 HUD（按 H 显示/隐藏，默认显示迷你气泡）===
	var hint_script = load("res://scripts/ui/key_hint_hud.gd")
	if hint_script:
		var hint_hud = hint_script.new()
		hint_hud.name = "KeyHintHUD"
		dialogue_layer.add_child(hint_hud)
		print("[Main] 快捷键 HUD 已挂载（按 H 切换）")

	# === 好感任务面板（按 K 打开，靠近 NPC 自动更新）===
	var rq_script = load("res://scripts/ui/relationship_quest_ui.gd")
	if rq_script:
		quest_ui = rq_script.new()
		quest_ui.name = "RelationshipQuestUI"
		dialogue_layer.add_child(quest_ui)
		print("[Main] 好感任务面板已挂载（按 K 打开）")

	# 检查时间档案：没有 → 显示 AgeSetupUI
	var tm = get_node_or_null("/root/TimeManager")
	if tm and not tm.has_profile():
		var age_ui_script = load("res://scripts/AgeSetupUI.gd")
		if age_ui_script:
			var age_ui = age_ui_script.new()
			dialogue_layer.add_child(age_ui)
			if age_ui.has_signal("setup_completed"):
				age_ui.setup_completed.connect(_on_age_setup_completed)

	# 挂载 OfflineClock（检测离线时长 + 自动跑 DramaEngine）
	# 用 call_deferred 是因为 _ready 太早，关系网络需要等 GameManager 起来
	call_deferred("_setup_offline_clock")

	# 启动封面背景音乐（菜单音乐）
	call_deferred("_setup_music")

	# 应用玩家的"初始亲缘好感度"（首次启动时）
	_setup_player_initial_relationships()

	# 挂载 NPCMemoryPanel（按 Q 打开"最近奇遇"）
	var memory_script = load("res://scripts/ui/npc_memory_panel.gd")
	if memory_script:
		memory_panel = memory_script.new()
		memory_panel.name = "NPCMemoryPanel"
		dialogue_layer.add_child(memory_panel)
		print("[Main] NPCMemoryPanel 已挂载（按 Q 打开）")


# === 玩家在 AgeSetupUI 完成输入 ===
func _on_age_setup_completed(_age: int) -> void:
	print("[Main] Age setup done, age=%d" % _age)
	pass


# === 启动时应用玩家的"初始亲缘好感度" ===
# 第二次开游戏就用存档的好感，**不要覆盖**
# 所以用 GameManager 检测是否是 first_run
func _setup_player_initial_relationships() -> void:
	var matrix_script = load("res://scripts/offline/RelationshipMatrix.gd")
	if matrix_script == null:
		return
	var matrix = matrix_script.get_instance()
	# 检查 GameManager 是否标注 first_run
	var gm = get_node_or_null("/root/GameManager")
	var is_first_run: bool = true
	if gm and "first_run" in gm:
		is_first_run = gm.first_run
	if is_first_run:
		matrix.apply_player_initial_points()
		print("[Main] 首次启动 → 已应用玩家初始好感预设")
		# === 按初始亲密度给每个 NPC 预填有趣日记 ===
		var diary_script = load("res://scripts/offline/NPCDiary.gd")
		if diary_script:
			var diary = diary_script.get_instance()
			if diary and diary.has_method("seed_starter_diaries"):
				diary.seed_starter_diaries(matrix)
			print("[Main] 首次启动 → 已写入 NPC 初始日记（带故事线）")
	else:
		print("[Main] 非首次启动 → 跳过（用存档数据）")


# === 挂载离线时钟（在 _ready 末尾 deferred 调用）===
func _setup_offline_clock() -> void:
	var ClockScript = load("res://scripts/offline/OfflineClock.gd")
	if ClockScript == null:
		push_warning("[Main] OfflineClock.gd 加载失败")
		return
	offline_clock = ClockScript.new()
	offline_clock.name = "OfflineClock"
	add_child(offline_clock)
	print("[Main] OfflineClock 已挂载")


# === 音乐（封面 → 世界切换） ===
func _setup_music() -> void:
	# 切到封面时，播放菜单音乐
	var music = get_node_or_null("/root/Music")
	if music and music.has_method("play_menu"):
		music.play_menu()
	print("[Main] 菜单音乐已启动")

func _play_game_music() -> void:
	var music = get_node_or_null("/root/Music")
	if music and music.has_method("play_game"):
		music.play_game()


# === 开发者快捷键：1/2/3 字母键（避开 Godot 编辑器 F8 等快捷键冲突） ===
const DramaEngineScript := preload("res://scripts/offline/DramaEngine.gd")
# 5 分钟 = 1 天（玩家离线模拟）
const SECONDS_PER_DAY: int = 300

var _day_sim_timer: float = 0.0
var _auto_sim_enabled: bool = true

func _process(delta: float) -> void:
	if not _auto_sim_enabled: return
	_day_sim_timer += delta
	if _day_sim_timer >= float(SECONDS_PER_DAY):
		_day_sim_timer = 0.0
		_auto_sim_enabled = false  # 每个"模拟日"只跑一次
		print("[Auto-Sim] 现实时间 5 分钟已到 → 自动跑 1 天模拟")
		_debug_run_drama(1)
		# 下一帧重置，重新计时
		call_deferred("_reset_auto_sim")
func _reset_auto_sim() -> void:
	_auto_sim_enabled = true

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# 1：立刻跑 N 天模拟
	if event.keycode == KEY_1:
		_debug_run_drama(5)
		get_viewport().set_input_as_handled()
	# 2：打印关系总览
	elif event.keycode == KEY_2:
		_debug_print_summary()
		get_viewport().set_input_as_handled()
	# 3：清空离线存档
	elif event.keycode == KEY_3:
		_debug_clear_offline_state()
		get_viewport().set_input_as_handled()

# F8：跑 N 天模拟（默认 5）
func _debug_run_drama(days: int) -> void:
	print("\n[DEBUG F8] ===== 立刻跑 %d 天离线模拟 =====" % days)
	# 找 clock
	var clock = get_node_or_null("OfflineClock")
	if clock == null:
		clock = get_node_or_null("/root/OfflineClock")
	if clock == null:
		# 没有就先挂一个
		_setup_offline_clock()
		clock = get_node_or_null("OfflineClock")
	if clock == null:
		print("[DEBUG F8] ❌ OfflineClock 还是没起来")
		return
	# 加载 DramaEngine
	var DramaScript = load("res://scripts/offline/DramaEngine.gd")
	if DramaScript == null:
		print("[DEBUG F8] ❌ DramaEngine 加载失败")
		return
	var drama = DramaScript.new()
	drama.name = "DramaEngine"
	add_child(drama)
	drama.run_n_days(days)
	# 销毁 drama（matrix 已写回 clock）
	drama.queue_free()
	# 弹个提示
	_show_debug_toast("✅ 已模拟 %d 天 · Day %d · 最近奇遇数 %d" % [days, clock.get_current_day(), clock._state.get("events", []).size()])
	print("[DEBUG F8] ===== 完成 =====\n")

# F9：打印世界关系总览
func _debug_print_summary() -> void:
	print("\n[DEBUG F9] ===== 世界关系总览 =====")
	var clock = get_node_or_null("OfflineClock")
	if clock == null:
		clock = get_node_or_null("/root/OfflineClock")
	if clock == null:
		print("OfflineClock 没起来")
		return
	# 矩阵
	var Matrix = load("res://scripts/offline/RelationshipMatrix.gd")
	var matrix = Matrix.get_instance()
	if clock._state.get("matrix"):
		matrix.from_dict(clock._state["matrix"])
	var pairs: Array = matrix.get_top_pairs(10)
	print("Top 10 关系对：")
	for p in pairs:
		if int(p.points) == 0:
			continue
		var na: String = DramaEngineScript.NPC_DISPLAY.get(p.a, p.a)
		var nb: String = DramaEngineScript.NPC_DISPLAY.get(p.b, p.b)
		var rel_pair: Dictionary = matrix.pair(p.a, p.b)
		var rel_type: String = ""
		if rel_pair.has("type"):
			rel_type = rel_pair["type"]
		print("  %s × %s  →  %d 分 (%s)" % [na, nb, int(p.points), rel_type])
	# 最近 5 条奇遇
	var all: Array = clock._state.get("events", [])
	print("\n最近 5 条奇遇：")
	var start_idx: int = max(0, all.size() - 5)
	for i in range(start_idx, all.size()):
		var e: Dictionary = all[i]
		print("  Day %d  %s" % [int(e.get("day", 0)), str(e.get("summary", ""))])
	print("[DEBUG F9] ===== 完成 =====\n")
	_show_debug_toast("📊 已打印世界关系总览（控制台）")

# F10：清空所有离线状态（重新开始）
func _debug_clear_offline_state() -> void:
	var path = "user://offline_state.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		print("[DEBUG F10] 已删除 %s" % path)
	# 重置内存中的 matrix
	var Matrix = load("res://scripts/offline/RelationshipMatrix.gd")
	var matrix = Matrix.get_instance()
	matrix.from_dict({})
	var clock = get_node_or_null("OfflineClock")
	if clock:
		clock._state = {"last_quit_unix": int(Time.get_unix_time_from_system()), "game_day": 1, "events": []}
		clock._save()
	_show_debug_toast("🧹 已清空离线状态")
	print("[DEBUG F10] 离线状态已清空")

# 屏幕中间弹个 1.5 秒的小提示
func _show_debug_toast(text: String) -> void:
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_color", Color(1, 0.95, 0.85, 1))
	toast.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 1))
	toast.add_theme_constant_override("outline_size", 4)
	# 居中
	var viewport_size := get_viewport().get_visible_rect().size
	toast.position = Vector2(viewport_size.x * 0.5 - 280, viewport_size.y * 0.3)
	toast.size = Vector2(560, 60)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 半透明背景
	var bg := Panel.new()
	bg.size = Vector2(560, 60)
	bg.position = toast.position
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.1, 0.05, 0.85)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_right = 12
	sb.corner_radius_bottom_left = 12
	bg.add_theme_stylebox_override("panel", sb)
	dialogue_layer.add_child(bg)
	dialogue_layer.add_child(toast)
	# 1.5 秒后淡出
	var t := get_tree().create_tween()
	t.tween_interval(1.5)
	t.tween_property(toast, "modulate:a", 0.0, 0.4)
	t.parallel().tween_property(bg, "modulate:a", 0.0, 0.4)
	t.tween_callback(_kill_toast.bind(toast, bg))

func _kill_toast(toast: Label, bg: Panel) -> void:
	if is_instance_valid(toast):
		toast.queue_free()
	if is_instance_valid(bg):
		bg.queue_free()


# === 玩家点"开始新游戏"：清档重开 ===
func _on_start_pressed() -> void:
	print("[Main] _on_start_pressed (new game) → 彻底清档")
	# === 1. 删除磁盘存档 ===
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("delete_save"):
		sm.delete_save()
	var sc_path = "user://session_count.json"
	if FileAccess.file_exists(sc_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sc_path))
	var offline_state_path = "user://offline_state.json"
	if FileAccess.file_exists(offline_state_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(offline_state_path))
	# === 2. 重置 GameManager（关系、性格、历史） ===
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		if gm.has_method("reset"):
			gm.reset()
		# 标记 first_run=true（让 Main._setup_player_initial_relationships 重新走）
		if "first_run" in gm:
			gm.first_run = true
	# === 4. 重置 LLMClient（每个 NPC 的历史/指令） ===
	var llm = get_node_or_null("/root/LLMClient")
	if llm and llm.has_method("reset_all_history"):
		llm.reset_all_history()
	# === 5. 重置关系矩阵（清空所有亲密度，回到 9 个 NPC 全陌生） ===
	var MatrixScript = load("res://scripts/offline/RelationshipMatrix.gd")
	if MatrixScript:
		var matrix = MatrixScript.get_instance()
		matrix.from_dict({})
		print("[Main] 关系矩阵已清空")
	# === 6. 重置日记（清空所有 NPC 的日记） ===
	var DiaryScript = load("res://scripts/offline/NPCDiary.gd")
	if DiaryScript:
		var diary = DiaryScript.get_instance()
		diary.from_dict({})
		print("[Main] NPC 日记已清空")
	# === 7. 重置回忆相册 ===
	var AlbumScript = load("res://scripts/offline/MemoryAlbum.gd")
	if AlbumScript:
		var album = AlbumScript.get_instance()
		album.from_dict({})
		print("[Main] 回忆相册已清空")
	# === 8. 重置 OfflineClock（内存状态） ===
	var clock = get_node_or_null("OfflineClock")
	if clock == null:
		clock = get_node_or_null("/root/OfflineClock")
	if clock == null:
		clock = get_node_or_null("/root/Main/OfflineClock")
	if clock:
		# 把内存状态写回"全新"
		clock._state = {
			"last_quit_unix": int(Time.get_unix_time_from_system()),
			"game_day": 1,
			"events": []
		}
		clock._save()
		print("[Main] OfflineClock 已重置为 Day 1")
	# === 9. 重新应用初始亲密度 + 种子日记（first_run=true） ===
	_setup_player_initial_relationships()
	goto_world()


# === 玩家点"继续上次" ===
func _on_continue_pressed() -> void:
	print("[Main] _on_continue_pressed called")
	var sm = get_node_or_null("/root/SaveManager")
	var gm = get_node_or_null("/root/GameManager")
	if sm and gm:
		var data = sm.load_save()
		gm.apply_save_data(data)
	goto_world()

	# === 开屏来信：离线回来后的 NPC 钩子 ===
	# 延迟 0.5s 等世界加载完再弹
	await get_tree().create_timer(0.5).timeout
	_trigger_opening_letter()


func _hide_cover() -> void:
	cover.visible = false


func goto_world() -> void:
	_hide_cover()

	# 清掉旧地图
	for child in world_root.get_children():
		child.queue_free()

	# 创建 Player（持久）
	if player == null:
		var player_scene = load("res://scenes/Player.tscn") if ResourceLoader.exists("res://scenes/Player.tscn") else null
		if player_scene == null:
			# 没有独立 Player.tscn → 用脚本动态创建
			var PlayerScript = load("res://scripts/Player.gd")
			if PlayerScript:
				var node = Node2D.new()
				node.set_script(PlayerScript)
				player = node
		else:
			player = player_scene.instantiate()

	# 如果 Player 已经存在但被错误 add 到了旧地图，先摘下
	if player.get_parent() != null:
		player.get_parent().remove_child(player)

	# 把 DialogueUI 提到 DialogueLayer
	if dialogue_ui and dialogue_ui.get_parent() != dialogue_layer:
		dialogue_ui.reparent(dialogue_layer)

	# 让 MapManager 加载主入口
	var map_mgr = get_node_or_null("/root/MapManager")
	if map_mgr:
		map_mgr.start(player, "world")
	else:
		push_error("[Main] MapManager autoload missing")

	# 切到世界后播放游戏音乐（覆盖菜单音乐）
	_play_game_music()


# 把当前地图的 Camera2D 跟随玩家
func _bind_camera_to_player() -> void:
	if player == null:
		return
	var map_node := player.get_parent()
	if map_node == null:
		return
	var cam := map_node.get_node_or_null("MapCamera")
	if cam == null:
		return
	cam.reparent(player, false)
	cam.position = Vector2.ZERO
	# Camera2D 作 player 子节点时会随玩家移动
	print("[Main] camera bound to player")

# === 开屏来信：玩家离线回来后，根据关系矩阵随机选一封"急件" ===
func _trigger_opening_letter() -> void:
	# 检查离线时长：> 60 秒才弹（防止秒退重开乱弹）
	var clock = get_node_or_null("OfflineClock")
	if clock and clock._state:
		var last_quit: int = int(clock._state.get("last_quit_unix", 0))
		var elapsed: int = int(Time.get_unix_time_from_system()) - last_quit
		if elapsed < 60:
			print("[OpeningLetter] 离线 < 60s，不弹")
			return

	# 检查 OfflineClock 的"今天模拟"事件，匹配来信用模板
	var template_id := _pick_letter_template()
	if template_id.is_empty():
		print("[OpeningLetter] 没找到合适模板，跳过")
		return

	# 实例化开屏来信
	var LetterScript = load("res://scripts/ui/opening_letter.gd")
	if LetterScript == null:
		return
	var letter = LetterScript.new()
	letter.name = "OpeningLetter"
	add_child(letter)
	letter.show_letter(template_id)

# 根据关系矩阵的好感度，从一群"愿意写信的 NPC"里随机挑一封
# === 核心规则 ===
# - Lv.0~1：完全不熟 → 不会发信
# - Lv.2：偶尔寒暄（低概率）
# - Lv.3：常发"大事"
# - Lv.4：每天轰炸
# - Lv.5：天天告白
# - crush / partner：玩家要努力才能解锁
func _pick_letter_template() -> String:
	var matrix_script = load("res://scripts/offline/RelationshipMatrix.gd")
	if matrix_script == null:
		return ""
	var matrix = matrix_script.get_instance()

	# === 哪些 NPC 是"会主动写信给玩家"的人？===
	# 闺蜜、兄弟、妈妈（Lv.2+ 偶尔发）
	# crush（玩家要追到 90 分才会发）
	const CANDIDATES := ["xiaoyou", "xiaoyang", "mother", "crush"]
	var weighted: Array = []  # [npc_id, weight]
	for npc_id in CANDIDATES:
		var rel = matrix.pair(npc_id, "partner")
		var pts: int = int(rel.get("points", 0))
		var lv: int = matrix.get_level_for_points(pts)
		# 等级 → 写信权重
		# Lv.0~1: 0
		# Lv.2:   1（20%）
		# Lv.3:   3（60%）
		# Lv.4:   5（100%）
		# Lv.5:   6
		var weight: int = 0
		match lv:
			0, 1: weight = 0
			2: weight = 1
			3: weight = 3
			4: weight = 5
			5: weight = 6
		if weight > 0:
			weighted.append({"id": npc_id, "lv": lv, "w": weight})

	if weighted.is_empty():
		print("[OpeningLetter] 没有任何 NPC 够格写信（都太生疏）")
		return ""

	# 加权随机
	var total_w: int = 0
	for e in weighted:
		total_w += int(e["w"])
	var r: int = randi() % total_w
	var acc: int = 0
	var picked: Dictionary = weighted[0]
	for e in weighted:
		acc += int(e["w"])
		if r <= acc:
			picked = e
			break

	var npc_id: String = picked["id"]
	var lv: int = picked["lv"]
	# 简化映射：每个 NPC 一档
	if npc_id == "xiaoyou":
		# 小柚：Lv.3 惊天 / Lv.2 寒暄
		return "xiaoyou_first" if lv >= 3 else "xiaoyou_chill"
	elif npc_id == "xiaoyang":
		return "xiaoyang_chill"
	elif npc_id == "mother":
		return "mother_warm"
	elif npc_id == "crush":
		# crush 要 90 分才会发信（"我好像也注意到你了"）
		if lv < 4:
			return ""
		return "crush_first"
	return ""