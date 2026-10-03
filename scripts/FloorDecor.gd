# FloorDecor：用 _draw() 画一些简单的像素风地面装饰
# 简化版：只画远景墙+地板带，NPC 和玩家不被遮挡
extends Node2D

const WOOD_DARK := Color(0.50, 0.38, 0.25)
const WALL := Color(0.95, 0.90, 0.82)
const WALL_SHADOW := Color(0.78, 0.72, 0.62)

func _draw() -> void:
	# === 远景墙 (上半部 y 80-380) ===
	draw_rect(Rect2(0, 80, 1280, 300), WALL)
	# 墙脚线
	draw_rect(Rect2(0, 378, 1280, 3), WALL_SHADOW)

	# === 地板 (下半部 y 380-720) ===
	# 地板带横向条纹 (浅色和深色交替, 体现纹理)
	for y in range(400, 720, 32):
		draw_rect(Rect2(0, y, 1280, 1), Color(0.78, 0.72, 0.55))
	# 竖向木板分块 (每隔 100px)
	for x in range(0, 1280, 100):
		draw_rect(Rect2(x, 380, 2, 340), WOOD_DARK)

	# === 顶部挂件：横梁 ===
	draw_rect(Rect2(0, 80, 1280, 8), WOOD_DARK)

	# === 远景小物品（贴在墙上，玩家走不到的位置）===
	# 中央墙画
	_draw_picture_frame(640, 200, 120, 80)
	# 左窗
	_draw_window(120, 200, 80, 100)
	# 右窗
	_draw_window(1160, 200, 80, 100)
	# 右侧时钟
	_draw_clock(1100, 130, 30, 30)


func _draw_picture_frame(cx: int, cy: int, w: int, h: int) -> void:
	var frame := Color(0.35, 0.25, 0.18)
	draw_rect(Rect2(cx - w/2, cy - h/2, w, h), frame)
	draw_rect(Rect2(cx - w/2 + 4, cy - h/2 + 4, w - 8, h - 8), Color(0.78, 0.65, 0.50))
	# 画中画（简单的风景）
	draw_rect(Rect2(cx - w/2 + 6, cy - h/2 + 6, w - 12, (h - 12) / 2), Color(0.55, 0.75, 0.85))
	draw_rect(Rect2(cx - w/2 + 6, cy, w - 12, (h - 12) / 2), Color(0.40, 0.62, 0.35))


func _draw_window(cx: int, cy: int, w: int, h: int) -> void:
	var frame := Color(0.40, 0.28, 0.20)
	draw_rect(Rect2(cx - w/2, cy - h/2, w, h), frame)
	# 天空
	draw_rect(Rect2(cx - w/2 + 3, cy - h/2 + 3, w - 6, h - 6), Color(0.62, 0.78, 0.88))
	# 云
	draw_rect(Rect2(cx - 18, cy - 18, 22, 6), Color(1, 1, 1))
	draw_rect(Rect2(cx + 4, cy - 10, 14, 4), Color(1, 1, 1))
	# 十字窗格
	draw_rect(Rect2(cx, cy - h/2 + 3, 2, h - 6), frame)
	draw_rect(Rect2(cx - w/2 + 3, cy, w - 6, 2), frame)


func _draw_clock(cx: int, cy: int, w: int, h: int) -> void:
	# 表盘
	draw_circle(Vector2(cx, cy), w * 0.5, Color(0.98, 0.95, 0.88))
	draw_arc(Vector2(cx, cy), w * 0.5, 0, TAU, 32, Color(0.30, 0.20, 0.15), 2.5)
	# 时针
	draw_line(Vector2(cx, cy), Vector2(cx, cy - w * 0.3), Color(0.10, 0.05, 0.05), 2.0)
	# 分针
	draw_line(Vector2(cx, cy), Vector2(cx + w * 0.35, cy - w * 0.1), Color(0.10, 0.05, 0.05), 1.5)
