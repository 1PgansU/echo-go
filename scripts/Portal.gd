# Portal：地图传送门（一个 Area2D + 提示 + 可视像素门）
# 玩家靠近后按 E，调用 MapBase.change_to
extends Area2D
class_name Portal

@export var portal_id: String = ""                # 唯一 id（用于反查：进门 → 出门）
@export var target_map_id: String = ""            # 目标地图 id
@export var return_portal_id: String = ""         # 目标地图里对应的"返回门" id（决定出生点）
@export var label_text: String = "🚪 出门"         # 头顶提示（emoji）
@export var one_way: bool = false                  # 单向（不能返回）
@export var draw_door: bool = true                 # 是否在 _draw() 里画门身（背景图已有门就关掉）

var _player_nearby: bool = false

@onready var label: Label = $Label
@onready var hint: Label = $Hint

# 门身尺寸（像素）
const DOOR_W := 16   # 像素宽
const DOOR_H := 32   # 像素高
const PIXEL := 4.0   # 单像素 4x4 屏幕像素 → 64×128 屏幕大小

# 门的像素颜色网格（在 _ready 里生成一次）
var _door_pixels: Array = []


func _ready() -> void:
	add_to_group("portals")
	if label:
		label.text = label_text
	if hint:
		hint.visible = false
	add_to_group("npcs")
	_build_door_pixels()
	queue_redraw()


func _process(_delta: float) -> void:
	if _player_nearby and hint:
		hint.visible = true
	elif hint:
		hint.visible = false


func _draw() -> void:
	if not draw_door:
		return
	if _door_pixels.is_empty():
		return
	var ox := -DOOR_W * PIXEL * 0.5
	var oy := -DOOR_H * PIXEL
	for y in DOOR_H:
		for x in DOOR_W:
			var c = _door_pixels[y][x]
			if c.a <= 0.001:
				continue
			var rect = Rect2(
				x * PIXEL + ox,
				y * PIXEL + oy,
				PIXEL, PIXEL
			)
			draw_rect(rect, c, true)


# 生成 16×32 像素网格
func _build_door_pixels() -> void:
	_door_pixels.clear()
	for y in DOOR_H:
		var row: Array = []
		for x in DOOR_W:
			row.append(Color(0, 0, 0, 0))
		_door_pixels.append(row)

	var frame := Color(0.40, 0.25, 0.15)        # 深棕门框
	var wood := Color(0.72, 0.50, 0.30)         # 木门
	var wood_dark := Color(0.55, 0.36, 0.20)    # 木门深
	var handle := Color(0.85, 0.65, 0.20)       # 金色把手
	var top := Color(0.30, 0.18, 0.10)          # 顶

	# 顶封（y=0-2）
	for y in range(0, 3):
		for x in range(0, DOOR_W):
			_door_pixels[y][x] = top

	# 门框 (左右 x=0/15, 上下 y=2/29)
	for x in range(0, DOOR_W):
		_door_pixels[2][x] = frame
		_door_pixels[29][x] = frame
	for y in range(2, 30):
		_door_pixels[y][0] = frame
		_door_pixels[y][15] = frame

	# 门身 (x=2-13, y=4-27)
	for y in range(4, 28):
		for x in range(2, 14):
			_door_pixels[y][x] = wood

	# 木纹（纵纹）
	for y in range(4, 28):
		_door_pixels[y][4] = wood_dark
		_door_pixels[y][9] = wood_dark

	# 上下板分割
	for x in range(2, 14):
		_door_pixels[16][x] = wood_dark

	# 把手 (y=16, x=11)
	_door_pixels[16][11] = handle

	# 底部台阶 (y=30-31)
	for x in range(0, DOOR_W):
		_door_pixels[30][x] = frame
		_door_pixels[31][x] = Color(0.2, 0.13, 0.07)


func set_player_nearby(value: bool) -> void:
	_player_nearby = value


func interact(_player: Node) -> void:
	if target_map_id == "":
		push_warning("[Portal] %s: target_map_id empty" % portal_id)
		return
	var spawn := Vector2.ZERO
	var mm = get_node_or_null("/root/MapManager")
	if mm:
		mm.change_map(target_map_id, spawn)