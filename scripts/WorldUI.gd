# WorldUI：跨地图常驻 UI（顶部栏 + 信箱按钮 + 红点 + 提示）
# 挂在 Main 的 CanvasLayer 下，不随地图切换被 free
extends CanvasLayer

# === 像素图标绘制（inner class；GDScript 允许 forward ref，但放顶部更稳） ===
class PixelIcon extends Control:
	var pixels: Array = []
	var icon_keys: Dictionary = {}
	var color_map: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAW or what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
			queue_redraw()

	func _draw() -> void:
		if pixels.is_empty():
			return
		var pix_w := 16
		var pix_h := 16
		# 自适应：算出最大可容纳的整数 scale，再按实际 size 居中
		var max_scale_w: int = int(size.x) / pix_w
		var max_scale_h: int = int(size.y) / pix_h
		var scale: int = mini(max_scale_w, max_scale_h)
		if scale < 1:
			scale = 1
		var total := Vector2(pix_w * scale, pix_h * scale)
		var offset := (size - total) * 0.5
		offset = offset.floor()
		for y in pix_h:
			if y >= pixels.size(): continue
			var row: String = pixels[y]
			for x in pix_w:
				if x >= row.length(): continue
				var ch := row[x]
				if ch == "." or not icon_keys.has(ch): continue
				var key: String = icon_keys[ch]
				if not color_map.has(key): continue
				var col: Color = color_map[key]
				if col.a <= 0.001: continue
				var rect := Rect2(offset.x + x * float(scale), offset.y + y * float(scale), float(scale), float(scale))
				draw_rect(rect, col, true)


# === 像素图标尺寸 ===
const ICON_PIX_W := 16    # 16×16 像素艺术
const ICON_PIX_H := 16
const ICON_SCALE := 3     # 3 倍放大 → 48×48 屏幕像素
const BTN_SIZE := 48

@onready var date_label: Label = get_node_or_null("DateLabel")
# 用户要求：顶部"日期 · 自由探索"那行不显示（多余视觉噪音）
# 以下按钮节点已删除，保留 null 引用以防 @onready 报错
@onready var memory_button: Button = get_node_or_null("MemoryButton")
@onready var diary_button: Button = get_node_or_null("DiaryButton")
@onready var album_button: Button = get_node_or_null("AlbumButton")
@onready var festival_button: Button = get_node_or_null("FestivalButton")
@onready var chat_button: Button = get_node_or_null("ChatButton")
@onready var phone_button: Button = get_node_or_null("PhoneButton")
@onready var quest_button: Button = get_node_or_null("QuestButton")

# 代码构造的像素按钮字典（key → Control）
var _pixel_btns: Dictionary = {}

# === 像素调色板（16 色 GameBoy 风米黄调）===
const C := {
	"bg":      Color(0.992, 0.976, 0.929),  # 浅米
	"shadow":  Color(0.557, 0.420, 0.227),  # 浅棕阴影
	"dark":    Color(0.239, 0.157, 0.090),  # 深棕主描线
	"red":     Color(0.722, 0.196, 0.196),  # 红（信箱/任务）
	"green":   Color(0.486, 0.620, 0.353),  # 绿（日记/相册）
	"blue":    Color(0.380, 0.518, 0.706),  # 蓝（聊天）
	"yellow":  Color(0.945, 0.769, 0.243),  # 黄（日历/节日）
	"orange":  Color(0.918, 0.471, 0.243),  # 橙（奇遇）
	"pink":    Color(0.910, 0.451, 0.612),  # 粉（群聊）
	"none":    Color(0, 0, 0, 0),
}

# === 16x16 像素艺术数据（每个图标一个 16x16 字符串数组）===
# 字符到调色板的映射：. = 透明 / b = 背景米色 / # = 深棕 / 其它见 const ICON_KEYS
const ICON_KEYS := {
	".": "none",
	"b": "bg",
	"#": "dark",
	"s": "shadow",
	"R": "red",
	"G": "green",
	"B": "blue",
	"Y": "yellow",
	"O": "orange",
	"P": "pink",
}

# 8 个图标（行数 = 16；每行 = 16 字符）
const ICONS := {
	"mail": [
		"................",
		"................",
		"...###########...",
		"..#bbbbbbbbbb#..",
		".#b#b#b#b#b#b#b#",
		"#bbRb#b#b#b#bRbb#",
		"#bbbbbbbbbbbbbb#",
		"#bRbRbRbRbRbRbRb#",
		"#bbbbbbbbbbbbbb#",
		"################",
		"################",
		"................",
		"................",
		"................",
		"................",
		"................",
	],
	"memory": [  # 奇遇：💡灯泡
		"................",
		".......####.....",
		"......#YYYY#....",
		".....#YYYYYY#...",
		"....#YYYYYYYY#..",
		"....#YY#bb#bs#..",
		"....#YYYYYYYY#..",
		"....#YYYYYYYY#..",
		"....#YYYYYYYY#..",
		"....#YYYY#YY#...",
		".....#YYYYYY#...",
		"......#YYYY#....",
		"......#OOOO#....",
		"......#OOOO#....",
		"......#OOOO#....",
		"......####......",
	],
	"diary": [  # 日记：📔 绿色书
		"................",
		"....###########.",
		"...#GGGGGGGGGG#.",
		"..#GGGGGGGGGGG#.",
		".#GGGGGGGGGGGG#.",
		"#GGGGGGGGGGGGG#.",
		"#GGGGGGGGGGGGG#.",
		"#GGGGGGGGGGGGG#.",
		"#GGGGGGGGGGGGG#.",
		"#GGGGGGGGGGGGG#.",
		"#GGGGGGGGGGGGG#.",
		"#GGGGGGGGGGGGG#.",
		"#GGGGGGGGGGGGG#.",
		"#GGGGGGGGGGGGG#.",
		".#GGGGGGGGGGGG#.",
		"..############..",
	],
	"album": [  # 相册：📷 相机
		"................",
		".....####.......",
		"....#bbbb#......",
		"...#bYYYYb#.....",
		"..##b####b##....",
		"#bYbbbbbbbbYb#.",
		"#bYb#b##b#bYb#.",
		"#bYbG#bb#GbYb#.",
		"#bYbG#bb#GbYb#.",
		"#bYbG#bb#GbYb#.",
		"#bYbG#bb#GbYb#.",
		"#bYbG#bb#GbYb#.",
		"#bYbG#bb#GbYb#.",
		"#bYbG####GbYb#.",
		"#bYbbbbbbbbYb#.",
		".##bbbbbbbb##..",
	],
	"calendar": [  # 日历：📅
		"................",
		"..####..####....",
		".#bbbb##bbbb#...",
		"#bbbbbbbbbbbb#..",
		"#bYYYYYYYYYYb#..",
		"#bYbbbbbbbbYb#..",
		"#bYbRRbbRRbbYb#.",
		"#bYbbbbbbbbbYb#.",
		"#bYbBBBBBBBbYb#.",
		"#bYbbbbbbbbbYb#.",
		"#bYbRRRRRRRbYb#.",
		"#bYbbbbbbbbbYb#.",
		"#bYYYYYYYYYYb#..",
		"#bbbbbbbbbbbb#..",
		".#bbbbbbbbbb#...",
		"..############..",
	],
	"chat": [  # 群聊：💬
		"................",
		".....######.....",
		"...##PPPPPP##...",
		"..#PPPPPPPPPP#..",
		".#PPPPPPPPPPPP#.",
		"#PPPPPPPPPPPPPP#",
		"#PPPP####PPPPPP#",
		"#PPP####PPPPPP#.",
		"#PP####PPPPPP#..",
		"#P####PPPPPPP#..",
		".##PPPP######...",
		"..#PPPPP###.....",
		"..#PPPP#.......",
		"...####.........",
		"................",
		"................",
	],
	"quest": [  # 任务：💝 心
		"................",
		"...##.....##....",
		"..#RR#...#RR#...",
		".#RRRR#.#RRRR#..",
		"#RRRRRR#RRRRRR#.",
		"#RRRRRRRRRRRRRR#",
		"#RRRRRRRRRRRRRR#",
		"#RRRRRRRRRRRRRR#",
		".#RRRRRRRRRRR#..",
		"..#RRRRRRRRR#...",
		"...#RRRRRRR#....",
		"....#RRRRR#.....",
		".....#RRR#......",
		"......#R#.......",
		"................",
		"................",
	],
	"map": [  # 地图：🗺️ 折叠地图
		"................",
		"...###########..",
		"..#bbbbbbbbbb#..",
		".#bYYbYYYbYYb#.",
		"#bbbYbbYYbbYbb#",
		"#bGGbYbGGbYbGb#",
		"#bbGGbYbbGGbYb#",
		"#bGbGGGbGbGGGb#",
		"#bGbGbbGbGbbGb#",
		"#bGGbGbGGbGbGGb",
		"#bbGGGbbGGGbbGb",
		"#bYYbYYYbYYYbYb",
		".#bbbYYYYYbbb#.",
		"..#bbbbbbbbbb#.",
		"...###########.",
		"................",
	],
}


func _ready() -> void:
	# === 极简顶栏：左上一个无框日期文字 + 右上 8 个无框像素图标按钮（彻底去框去割裂） ===
	_build_top_right_btns()

	# 旧的 emoji 按钮节点可能不存在（已被像素风按钮替代），仅作清理
	if memory_button: memory_button.visible = false
	if diary_button: diary_button.visible = false
	if album_button: album_button.visible = false
	if festival_button: festival_button.visible = false
	if chat_button: chat_button.visible = false
	if phone_button: phone_button.visible = false
	if quest_button: quest_button.visible = false

	# 监听 GameManager 的 scene_changed（兼容旧 World.gd 的逻辑）
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("scene_changed"):
		if not gm.scene_changed.is_connected(_on_scene_changed):
			gm.scene_changed.connect(_on_scene_changed)

	# 监听 MapManager 的 map_changed
	var mm = get_node_or_null("/root/MapManager")
	if mm and mm.has_signal("map_changed"):
		if not mm.map_changed.is_connected(_on_map_changed):
			mm.map_changed.connect(_on_map_changed)

	# 初始填充一次 date_label（延迟到下一帧，确保 autoload 已就绪）
	_on_map_changed.call_deferred("")


# === 极简顶栏：右上 8 个无框像素图标按钮（无外框，hover 才出底色） ===
func _build_top_right_btns() -> void:
	# 紧贴屏幕右上角：7 × 40px 按钮 + 8px 右间距
	var base_x: float = 1280.0 - 6.0 * BTN_SIZE - 8.0
	var base_y: float = 16.0
	var pixel_btns := {
		"memory":    _make_pixel_btn(ICONS["memory"],    Vector2(base_x + 0.0 * BTN_SIZE, base_y), _on_memory_pressed),
		"diary":     _make_pixel_btn(ICONS["diary"],     Vector2(base_x + 1.0 * BTN_SIZE, base_y), _on_diary_pressed),
		"album":     _make_pixel_btn(ICONS["album"],     Vector2(base_x + 2.0 * BTN_SIZE, base_y), _on_album_pressed),
		"calendar":  _make_pixel_btn(ICONS["calendar"],  Vector2(base_x + 3.0 * BTN_SIZE, base_y), _on_festival_pressed),
		"chat":      _make_pixel_btn(ICONS["chat"],      Vector2(base_x + 4.0 * BTN_SIZE, base_y), _on_chat_pressed),
		"quest":     _make_pixel_btn(ICONS["quest"],     Vector2(base_x + 5.0 * BTN_SIZE, base_y), _on_quest_pressed),
	}
	_pixel_btns = pixel_btns


func _input(event: InputEvent) -> void:
	# 信箱功能已移除：M 键不再打开信箱
	pass


func _process(_delta: float) -> void:
	# 封面（开始游戏前）时隐藏整个 WorldUI
	var main = get_tree().get_first_node_in_group("main")
	if main == null:
		return
	var cover_node = main.get_node_or_null("UILayer/Cover")
	if cover_node:
		visible = not cover_node.visible


func _on_scene_changed(scene_id: String) -> void:
	# 兼容旧 signal：scene_id = "map:xxx" 来自 MapManager；或 "day1_family_xx" 来自 NPC
	if scene_id.begins_with("map:"):
		# 让 _on_map_changed 处理
		return
	# 旧 NPC 触发的：scene_id 是剧本 id，根据 NPC 的 map_title 来推
	var title_map := {
		"day1_family_01": "🏠 客厅里的审判",
		"day1_family_02": "👩 厨房里的叹息",
		"day1_school_01": "🏫 走廊里的笑声",
		"day2_family_02": "🎂 弟弟的生日",
		"day2_school_02": "📋 文理分科表",
		"day3_love_01":   "💌 那张纸条",
		"day3_love_02":   "💔 TA 的关心",
		"chat:father":    "👨 和爸爸聊聊",
		"chat:mother":    "👩 和妈妈聊聊",
		"chat:brother":   "👦 和弟弟聊聊",
		"chat:classmate": "👦 和同学聊聊",
		"chat:teacher":   "👨‍🏫 和班主任聊聊",
		"chat:crush":     "💝 和 TA 聊聊",
		"chat:partner":   "💔 和 TA 聊聊",
		"chat:xiaoyang":  "🐑 阳光下的邻居",
		"chat:xiaoyou":   "🍊 可爱的小柚"
	}
	if title_map.has(scene_id) and date_label:
		var title: String = title_map[scene_id]
		# 去掉 emoji，仅留中文
		var parts: Array = title.split(" ", false, 1)
		var clean_title: String = parts[1] if parts.size() > 1 else title
		var date_str: String = ""
		var tm2 = get_node_or_null("/root/TimeManager")
		if tm2 and tm2.has_profile():
			date_str = tm2.today_str()
		date_label.text = ("%s · %s" % [date_str, clean_title]) if date_str != "" else clean_title


func _on_map_changed(new_map_id: String) -> void:
	if date_label == null:
		return
	var map_title: String = ""
	var mm = get_node_or_null("/root/MapManager")
	if mm and mm.current_map and "map_title" in mm.current_map:
		map_title = mm.current_map.map_title
	# 用户要求：顶部"日期 · 自由探索"那行不显示
	if date_label:
		date_label.text = ""
		date_label.visible = false


# === 像素风按钮工厂 ===
func _make_pixel_btn(icon_pixels: Array, pos: Vector2, on_pressed: Callable) -> Control:
	var btn := Button.new()
	btn.text = ""  # 不要 emoji 文字
	btn.position = pos
	btn.size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# 自定义 StyleBox：透明底 + 无边框（与 TopBar 同框，消除视觉割裂）
	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(1, 1, 1, 0)  # 完全透明
	normal_sb.border_width_left = 0
	normal_sb.border_width_top = 0
	normal_sb.border_width_right = 0
	normal_sb.border_width_bottom = 0
	normal_sb.corner_radius_top_left = 0
	normal_sb.corner_radius_top_right = 0
	normal_sb.corner_radius_bottom_left = 0
	normal_sb.corner_radius_bottom_right = 0
	normal_sb.content_margin_left = 0
	normal_sb.content_margin_right = 0
	normal_sb.content_margin_top = 0
	normal_sb.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("focus", normal_sb)

	var hover_sb := normal_sb.duplicate()
	hover_sb.bg_color = Color(0.992, 0.804, 0.486, 0.35)  # 黄色半透叠加
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)

	var pressed_sb := normal_sb.duplicate()
	pressed_sb.bg_color = C["shadow"]
	btn.add_theme_stylebox_override("pressed", pressed_sb)

	# 像素 icon 子控件（直接 _draw()，闭包取 outer 变量）
	var icon_node := PixelIcon.new()
	icon_node.name = "PixelIcon"
	icon_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_node.pixels = icon_pixels
	icon_node.icon_keys = ICON_KEYS
	icon_node.color_map = C
	icon_node.queue_redraw()
	btn.add_child(icon_node)
	add_child(btn)

	btn.pressed.connect(on_pressed)
	return btn


# === 像素图标绘制（class 定义在顶部，避免 forward ref 问题）===


func _on_memory_pressed() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.memory_panel:
		var p = main.memory_panel
		# 顶栏 NPC 在哪里就用哪个 ID；这里用 player 找
		if p.has_method("open") and main.player:
			var npc_id = _find_nearest_npc_id(main.player)
			if npc_id != "":
				p.open(npc_id)
			else:
				print("[WorldUI] 附近没有 NPC，奇遇面板需要走近 NPC 再打开")
		elif p.has_method("_open"):
			p._open()


func _on_diary_pressed() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.diary_panel:
		main.diary_panel._open()


func _on_album_pressed() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.album_panel:
		main.album_panel._open()


func _on_festival_pressed() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.festival_panel:
		# 强制显示"今天日历"（哪怕没节日也要给反馈）
		if main.festival_panel.has_method("_show_today_panel"):
			main.festival_panel._show_today_panel()
		elif main.festival_panel.has_method("trigger_today_event"):
			main.festival_panel.trigger_today_event()


func _on_chat_pressed() -> void:
	# 提示音/反馈
	print("[WorldUI] chat button pressed")
	var main = get_tree().get_first_node_in_group("main")
	if main == null:
		push_warning("[WorldUI] 找不到 main 节点")
		return
	var panel: Control = main.get_node_or_null("ChatAppPanel")
	if panel == null:
		var scene: PackedScene = load("res://scenes/ChatAppPanel.tscn")
		print("[WorldUI] load scene = ", scene)
		if scene == null:
			push_warning("[WorldUI] ChatAppPanel.tscn 加载失败")
			_show_toast("ChatApp 加载失败")
			return
		panel = scene.instantiate()
		if panel == null:
			push_warning("[WorldUI] ChatAppPanel 实例化失败")
			_show_toast("ChatApp 实例化失败")
			return
		panel.name = "ChatAppPanel"
		var target: Node = main.get_node_or_null("DialogueLayer")
		if target == null:
			target = main.get_node_or_null("UILayer")
		(target if target else main).add_child(panel)
		print("[WorldUI] ChatAppPanel 已挂载到 ", target.name if target else "main")
	if panel and panel.has_method("open"):
		print("[WorldUI] 调用 panel.open()")
		panel.open()
	else:
		push_warning("[WorldUI] 节点不是 Control 或没有 open() 方法")
		_show_toast("ChatApp 初始化失败")


func _show_toast(text: String) -> void:
	# 简易 toast：贴在自己（WorldUI）右上角，3 秒消失
	var tween := create_tween()
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	lbl.modulate = Color(1, 1, 1, 0)
	lbl.position = Vector2(800, 80)
	add_child(lbl)
	tween.tween_property(lbl, "modulate:a", 1.0, 0.2)
	tween.tween_interval(2.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tween.tween_callback(lbl.queue_free)


# 兜底：当 .tscn load 失败，直接用脚本构造一个最简控制台反馈
func _fallback_build_chat_panel(main: Node) -> void:
	var p := Control.new()
	p.name = "ChatAppPanel"
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = "📱 ChatApp 加载失败\n请检查 scenes/ChatAppPanel.tscn"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.add_child(label)
	var target: Node = main.get_node_or_null("DialogueLayer")
	if target == null:
		target = main.get_node_or_null("UILayer")
	(target if target else main).add_child(p)
	if p.has_method("open"):
		p.open()


func _on_quest_pressed() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main and main.quest_ui:
		# 好感任务：靠近 NPC 自动选任务，没有就近 NPC 就提示
		if main.quest_ui.has_method("open_for"):
			var npc_id = ""
			if main.player:
				npc_id = _find_nearest_npc_id(main.player)
			if npc_id != "":
				main.quest_ui.open_for(npc_id)
			else:
				print("[WorldUI] 附近没有 NPC，任务面板需要走近 NPC 再打开")
		elif main.quest_ui.has_method("_open"):
			main.quest_ui._open()


# 找玩家附近最近 NPC 的 npc_id（用于奇遇面板）
func _find_nearest_npc_id(player: Node) -> String:
	var nearest: Node = null
	var best_d2: float = INF
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc == null or not is_instance_valid(npc): continue
		if not "npc_id" in npc: continue
		var d = (npc.global_position - player.global_position).length_squared()
		if d < best_d2:
			best_d2 = d
			nearest = npc
	if nearest == null: return ""
	return str(nearest.npc_id)