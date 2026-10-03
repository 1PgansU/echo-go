# NPC：场景交互触发器，可自由移动
# 两种模式：
#   - chat_mode = false：触发预设剧本对话（scenes.json）
#   - chat_mode = true：  触发自由聊天（ChatDialogue → 接 LLM）
extends Area2D
class_name NPC

@export var npc_id: String = ""
@export var npc_name: String = "NPC"
@export var scene_to_trigger: String = ""
@export var color: Color = Color(0.78, 0.48, 0.39)
@export var chat_mode: bool = false       # true = 走 ChatDialogue，false = 走预设剧本

# 巡逻参数
@export var wander_radius: float = 80.0       # 巡逻半径（围绕出生点）
@export var wander_speed: float = 50.0        # 移动速度
@export var wander_min_pause: float = 1.5     # 最短停留时间
@export var wander_max_pause: float = 4.0     # 最长停留时间
@export var can_wander: bool = true           # 是否启用巡逻

@onready var sprite: PixelSprite
@onready var label: Label = $NameLabel
@onready var hint: Label = $Hint

var _player_nearby: bool = false

# 巡逻状态
var _spawn_position: Vector2
var _target_position: Vector2
var _pause_timer: float = 0.0
var _is_pausing: bool = true

# 主动破冰相关
var _proximity_timer: float = 0.0
var _proximity_threshold: float = 2.0
var _proactive_done: bool = false
var _proactive_timer: float = 0.0
const PROXIMITY_MIN: float = 1.5
const PROXIMITY_MAX: float = 3.0

func _ready() -> void:
	add_to_group("npc")  # 离线系统/奇遇面板要找 NPC
	if has_node("PixelSprite"):
		sprite = $PixelSprite
	_spawn_position = global_position
	_pick_new_target()

	if sprite:
		_apply_pixel_appearance()
	if label:
		label.text = npc_name
	if hint:
		hint.visible = false
	add_to_group("npcs")
	# 注册关系信号 → 头顶 emoji 变化
	_connect_relationship_signal()
	# 初始 emoji（已有存档分数时）
	_refresh_mood_emoji()


func _connect_relationship_signal() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	if gm.has_signal("relationship_changed") \
			and not gm.relationship_changed.is_connected(_on_relationship_changed):
		gm.relationship_changed.connect(_on_relationship_changed)


func _on_relationship_changed(changed_npc_id: String, _points: int, _mood: String) -> void:
	if changed_npc_id == npc_id:
		_refresh_mood_emoji()


# 心情 → emoji 字符
const MOOD_EMOJI := {
	"neutral": "😐",
	"smile":   "🙂",
	"happy":   "😄",
	"excited": "🤩",
}


func _refresh_mood_emoji() -> void:
	if label == null:
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		label.text = npc_name
		return
	var info: Dictionary = gm.get_relationship(npc_id) if gm.has_method("get_relationship") else {"mood": "neutral", "points": 0}
	var mood: String = info.get("mood", "neutral")
	var emoji: String = MOOD_EMOJI.get(mood, "😐")
	# emoji 跟在名字后面（小一点、浅色）
	label.text = "%s  %s" % [npc_name, emoji]

# 根据 npc_id 自动配肤色/发色/服装
func _apply_pixel_appearance() -> void:
	var def := _get_char_def(npc_id)
	sprite.skin = def.skin
	sprite.hair = def.hair
	sprite.shirt = def.shirt
	sprite.pants = def.pants
	sprite.hair_style = def.hair_style
	sprite.accessory = def.accessory
	sprite.queue_redraw()

# 角色配置 (skin, hair, shirt, pants, hair_style, accessory)
func _get_char_def(id: String) -> Dictionary:
	match id:
		"father":    return {"skin": Color(0.93, 0.74, 0.58), "hair": Color(0.15, 0.10, 0.06), "shirt": Color(0.30, 0.40, 0.55), "pants": Color(0.18, 0.20, 0.30), "hair_style": 0, "accessory": 2}  # 短发+胡茬+眼镜可选
		"mother":    return {"skin": Color(0.96, 0.80, 0.65), "hair": Color(0.30, 0.15, 0.10), "shirt": Color(0.85, 0.45, 0.45), "pants": Color(0.40, 0.25, 0.35), "hair_style": 1, "accessory": 0}  # 中长发
		"classmate": return {"skin": Color(0.94, 0.78, 0.62), "hair": Color(0.10, 0.08, 0.06), "shirt": Color(0.45, 0.65, 0.45), "pants": Color(0.25, 0.30, 0.40), "hair_style": 0, "accessory": 5}  # 背包
		"brother":   return {"skin": Color(0.95, 0.79, 0.63), "hair": Color(0.18, 0.12, 0.08), "shirt": Color(0.95, 0.70, 0.30), "pants": Color(0.35, 0.40, 0.50), "hair_style": 4, "accessory": 0}  # 卷发
		"teacher":   return {"skin": Color(0.92, 0.76, 0.60), "hair": Color(0.30, 0.25, 0.18), "shirt": Color(0.45, 0.45, 0.65), "pants": Color(0.25, 0.25, 0.35), "hair_style": 0, "accessory": 3}  # 短发+领带+眼镜
		"crush":     return {"skin": Color(0.97, 0.82, 0.68), "hair": Color(0.40, 0.22, 0.18), "shirt": Color(0.95, 0.75, 0.80), "pants": Color(0.55, 0.45, 0.60), "hair_style": 3, "accessory": 0}  # 双马尾
		"partner":   return {"skin": Color(0.94, 0.78, 0.62), "hair": Color(0.10, 0.08, 0.07), "shirt": Color(0.55, 0.40, 0.50), "pants": Color(0.25, 0.25, 0.35), "hair_style": 5, "accessory": 1}  # 刘海+眼镜
		"xiaoyang":  return {"skin": Color(0.96, 0.80, 0.65), "hair": Color(0.85, 0.65, 0.30), "shirt": Color(0.95, 0.78, 0.25), "pants": Color(0.55, 0.45, 0.25), "hair_style": 0, "accessory": 0}  # 短发 + 暖色系阳光男孩
		"xiaoyou":   return {"skin": Color(0.97, 0.82, 0.68), "hair": Color(0.92, 0.70, 0.55), "shirt": Color(1.00, 0.70, 0.75), "pants": Color(0.85, 0.60, 0.70), "hair_style": 3, "accessory": 0}  # 双马尾 + 暖粉可爱女孩
		_:           return {"skin": Color(0.96, 0.80, 0.65), "hair": Color(0.20, 0.15, 0.10), "shirt": Color(0.55, 0.55, 0.65), "pants": Color(0.30, 0.30, 0.40), "hair_style": 0, "accessory": 0}

func _process(delta: float) -> void:
	# 玩家走近：累计"主动破冰"计时（达到 1.5-3 秒后 NPC 会主动搭话）
	if _player_nearby:
		_proximity_timer += delta
		if not _proactive_done:
			_try_proactive_greet()
		# NPC 轻微浮动（呼吸感）
		if sprite:
			sprite.position.y = sin(Time.get_ticks_msec() / 1000.0 * 2.0) * 1.0
		# 同步头顶小气泡位置（跟随相机）
		_process_bubble_position()
		return

	# 玩家不在附近：idle 状态
	if sprite:
		sprite.position.y = sin(Time.get_ticks_msec() / 1000.0 * 2.0) * 1.5

	# 巡逻逻辑
	if not can_wander:
		return

	if _is_pausing:
		_pause_timer -= delta
		if _pause_timer <= 0:
			_is_pausing = false
			_pick_new_target()
	else:
		# 移动到目标
		var to_target = _target_position - global_position
		var dist = to_target.length()
		if dist < 4.0:
			_is_pausing = true
			_pause_timer = randf_range(wander_min_pause, wander_max_pause)
		else:
			var dir = to_target.normalized()
			global_position += dir * wander_speed * delta


# ===== 主动破冰 =====

func _try_proactive_greet() -> void:
	# 关掉：玩家走近不再自动搭话——必须按 E 才聊天（玩家要求）
	return


func _pick_new_target() -> void:
	# 在出生点 wander_radius 范围内随机选一个目标
	var angle = randf() * TAU
	var r = randf() * wander_radius
	var offset = Vector2(cos(angle), sin(angle)) * r
	_target_position = _spawn_position + offset
	# 限制在地图边界内（用父 MapBase；兜底走视口范围）
	var bounds := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var parent := get_parent()
	if parent and parent.has_method("get_world_bounds"):
		bounds = parent.get_world_bounds()
	_target_position.x = clamp(_target_position.x, bounds.position.x + 30, bounds.position.x + bounds.size.x - 30)
	_target_position.y = clamp(_target_position.y, bounds.position.y + 30, bounds.position.y + bounds.size.y - 30)


func set_player_nearby(value: bool) -> void:
	_player_nearby = value
	if hint:
		hint.visible = value
		if value and chat_mode and npc_id in ["xiaoyang", "xiaoyou"]:
			# 可玩五子棋的 NPC：明确告诉玩家 E/R/Q/K 都行
			hint.text = "[E] 对话  [R] 玩五子棋\n[Q] 奇遇  [K] 好感任务"
		elif value:
			# 其他 NPC：E 互动 + Q 听八卦 + K 好感任务
			hint.text = "[E] 互动\n[Q] 奇遇  [K] 好感任务"
	if value:
		# 玩家靠近：NPC 头顶冒一个小气泡（一个表情符号）
		_show_approach_bubble()
		# 通知任务面板：这个 NPC 靠近了（K 键会用到）
		_notify_nearby_npc(npc_id)
		# 玩家靠近时立即停下来面对玩家
		_is_pausing = true
		_pause_timer = 999.0  # 暂停到玩家离开
		# 启动「主动破冰」计时器
		_proximity_threshold = randf_range(PROXIMITY_MIN, PROXIMITY_MAX)
		_proximity_timer = 0.0
		_proactive_done = false
	else:
		# 玩家离开：隐藏小气泡
		_hide_approach_bubble()
		# 重置主动破冰
		_proximity_timer = 0.0
		_proactive_done = false

func _notify_nearby_npc(npc_id: String) -> void:
	var quest_ui = get_node_or_null("/root/Main/RelationshipQuestUI")
	if quest_ui and quest_ui.has_method("open_for"):
		quest_ui.open_for(npc_id)

# 每个 NPC 互动时的小气泡 emoji（按 npc_id 取第一个；缺省用 💬）
const APPROACH_EMOJI := {
	"xiaoyang": "🐑",      # 小羊 → 羊
	"xiaoyou":  "🍊",      # 小柚 → 橘子
	"father":   "👨",      # 爸爸
	"mother":   "👩",      # 妈妈
	"brother":  "🧒",      # 弟弟
	"classmate":"🎒",      # 同学
	"teacher":  "📚",      # 老师
	"crush":    "💗",      # 心仪对象
	"partner":  "💞",      # 伴侣
}

# 头顶小气泡：在 NPC 头顶上方画一个圆形气泡，里面放一个 emoji
# 用 CanvasLayer + Control 实现（不依赖外部贴图/场景）
var _approach_bubble: CanvasLayer = null
var _approach_label: Label = null

func _show_approach_bubble() -> void:
	if _approach_bubble != null:
		# 已经显示着 → 顺手把文字刷新一下
		if _approach_label:
			_approach_label.text = APPROACH_EMOJI.get(npc_id, "💬")
		return
	var emoji: String = APPROACH_EMOJI.get(npc_id, "💬")
	# CanvasLayer 跟随 NPC
	var layer := CanvasLayer.new()
	layer.name = "ApproachBubble_%s" % npc_id
	layer.follow_viewport_enabled = true
	# Container：白色圆形气泡背景
	var bubble := Control.new()
	bubble.name = "Bubble"
	bubble.custom_minimum_size = Vector2(34, 34)
	bubble.size = Vector2(34, 34)
	# 画一个圆形 Panel 当背景
	var bg := Panel.new()
	bg.name = "BG"
	bg.position = Vector2.ZERO
	bg.size = Vector2(34, 34)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.95)
	sb.corner_radius_top_left = 17
	sb.corner_radius_top_right = 17
	sb.corner_radius_bottom_left = 17
	sb.corner_radius_bottom_right = 17
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.16, 0.10, 0.05, 0.6)
	bg.add_theme_stylebox_override("panel", sb)
	bubble.add_child(bg)
	# 文字（emoji）
	var lbl := Label.new()
	lbl.name = "Emoji"
	lbl.text = emoji
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0, 4)  # emoji 视觉居中略下
	lbl.size = Vector2(34, 30)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(lbl)
	_approach_label = lbl
	layer.add_child(bubble)
	add_child(layer)
	# 把气泡放在 NPC 头顶偏上
	# 玩家走到屏幕边缘时，layer 会跟着 NPC 走
	_approach_bubble = layer
	# 启动一个轻"上下浮"动画（每秒 1.2 次）
	var t := get_tree().create_tween()
	t.set_loops()
	t.tween_property(bubble, "position:y", -3.0, 0.4).as_relative().set_trans(Tween.TRANS_SINE)
	t.tween_property(bubble, "position:y", 3.0, 0.4).as_relative().set_trans(Tween.TRANS_SINE)
	# 把气泡位置同步到 NPC 头顶（用 process）
	set_process(true)

func _hide_approach_bubble() -> void:
	if _approach_bubble != null:
		_approach_bubble.queue_free()
		_approach_bubble = null
		_approach_label = null

# 让气泡跟随 NPC 头顶
func _process_bubble_position() -> void:
	if _approach_bubble == null:
		return
	var bubble: Control = _approach_bubble.get_node_or_null("Bubble")
	if bubble == null:
		return
	# 把 NPC 的全局坐标换算到当前 viewport 的像素位置
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp else null
	var screen_pos: Vector2
	if cam:
		screen_pos = (global_position - cam.get_screen_center_position()) + Vector2(vp.get_visible_rect().size) * 0.5
	else:
		screen_pos = global_position
	# NPC 头顶上方 60 像素
	bubble.position = screen_pos + Vector2(-17, -90)

func interact(_player: Node) -> void:
	print("[NPC] %s interacted (mode=%s)" % [npc_name, "chat" if chat_mode else "script"])

	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		print("[NPC] GameManager not ready, skip")
		return

	if chat_mode:
		# ===== 聊天模式：打开 ChatDialogue =====
		var chat = gm.get_chat_dialogue()
		if chat == null:
			push_warning("[NPC] ChatDialogue not ready")
			return
		chat.start_chat(npc_id)
		if gm.has_signal("scene_changed"):
			gm.emit_signal("scene_changed", "chat:%s" % npc_id)
	else:
		# ===== 剧本模式：旧逻辑 =====
		if scene_to_trigger == "":
			push_warning("[NPC] No scene_to_trigger set for %s" % npc_name)
			return
		if gm.dialogue_ui == null:
			print("[NPC] DialogueUI not ready, skip dialogue")
			return
		gm.dialogue_ui.start_dialogue(scene_to_trigger, self)


# ===== R 键：弹五子棋占位面板（独立于聊天的可视化演示）=====
func play_gomoku(_player: Node) -> void:
	# 同一时间只允许一个
	if get_tree().get_first_node_in_group("gomoku_ui") != null:
		print("[NPC] 五子棋面板已存在，不重复创建")
		return
	var scene: PackedScene = load("res://scenes/GomokuUI.tscn")
	if scene == null:
		push_warning("[NPC] GomokuUI.tscn 加载失败")
		return
	var ui: Control = scene.instantiate()
	ui.add_to_group("gomoku_ui")
	# 挂到 main 的 DialogueLayer（如果有），否则挂到当前场景
	var main_node := get_tree().get_first_node_in_group("main")
	if main_node:
		var layer: Node = main_node.get_node_or_null("DialogueLayer")
		if layer == null:
			layer = main_node
		layer.add_child(ui)
	else:
		get_tree().current_scene.add_child(ui)
	if ui.has_method("open"):
		ui.open(npc_id, npc_name)
	# 通知 Act1 状态机：节点2 完成
	var a1 = get_node_or_null("/root/QuestlineAct1")
	if a1 and a1.has_method("on_gomoku_started"):
		a1.call("on_gomoku_started")
	print("[NPC] %s 打开五子棋面板（R 触发）" % npc_name)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		set_player_nearby(true)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		set_player_nearby(false)

# 节点销毁时清理小气泡（防止游离 CanvasLayer）
func _exit_tree() -> void:
	_hide_approach_bubble()