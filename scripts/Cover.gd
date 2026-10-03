# Cover：动态封面（程序化动画 + 可选图片背景）
extends Control

# === 主题色 ===
const COLOR_CREAM := Color(0.976, 0.957, 0.91, 1)
const COLOR_WARM := Color(0.96, 0.92, 0.82, 1)
const COLOR_PEACH := Color(0.96, 0.83, 0.72, 1)
const COLOR_INK := Color(0.239, 0.157, 0.09, 1)
const COLOR_GOLD := Color(0.788, 0.482, 0.388, 1)

# === 背景色循环 ===
var _bg_colors: Array[Color] = [COLOR_CREAM, COLOR_WARM, COLOR_PEACH]
var _bg_color_index_a: int = 0
var _bg_color_index_b: int = 1
var _bg_color_blend: float = 0.0
var _bg_speed: float = 0.18

@onready var background_rect: ColorRect = $Background
@onready var background_image: TextureRect = $BackgroundImage
@onready var floating_layer: CanvasLayer = $FloatingLayer

# 图片蒙版（动态创建）
var _overlay: ColorRect = null


func _ready() -> void:
	_init_background_image_optional()


func _process(delta: float) -> void:
	_update_background(delta)


# === 背景渐变呼吸 ===
func _update_background(delta: float) -> void:
	_bg_color_blend += delta * _bg_speed
	if _bg_color_blend >= 1.0:
		_bg_color_blend = 0.0
		_bg_color_index_a = _bg_color_index_b
		_bg_color_index_b = (_bg_color_index_b + 1) % _bg_colors.size()

	var color_a = _bg_colors[_bg_color_index_a]
	var color_b = _bg_colors[_bg_color_index_b]
	# 用一个 sin 曲线让呼吸更柔和
	var t = sin(_bg_color_blend * PI)  # 0→1→0
	background_rect.color = color_a.lerp(color_b, t)


# === 可选图片背景 ===
# 如果 assets/cover.png 或 cover.jpg 存在，自动作为背景
func _init_background_image_optional() -> void:
	if background_image == null:
		return

	var source_path := ""
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var p := "res://assets/cover.%s" % ext
		if FileAccess.file_exists(p):
			source_path = p
			break

	if source_path == "":
		print("[Cover] No background image found, using pure procedural background")
		return

	# 通过 ResourceLoader 加载（要求图片已导入）
	if not ResourceLoader.exists(source_path):
		print("[Cover] Image exists but not imported: %s" % source_path)
		print("[Cover]    Tip: In Godot, click FileSystem -> assets/cover.png -> Reimport")
		return

	var tex := load(source_path) as Texture2D
	if tex == null:
		print("[Cover] Failed to load texture: %s" % source_path)
		return

	background_image.texture = tex
	background_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background_image.visible = true

	# === 智能适配：让图片和文字都好看 ===
	# 根据图片平均亮度决定蒙版策略（这里用全局调制简化）
	# 如果图片深色 → 加暗色蒙版 + 浅色文字
	# 如果图片浅色 → 加亮色蒙版 + 深色文字
	# 简化：固定用半透暖色蒙版，文字保持当前深色

	# 让图片柔和叠在程序化背景上
	background_image.modulate.a = 0.85

	# 把程序化背景调淡（但不消失 —— 呼吸色还在跑）
	background_rect.color.a = 0.4

	# 加一层半透明暖色蒙版，让文字在任何图片上都能看清
	# （通过设置 ColorRect 的 alpha 实现）
	# 蒙版加在 Background 上方 —— 利用前景浮动 emoji 之下、文字之上
	# 这里用代码动态加一个 ColorRect 做蒙版
	_overlay = ColorRect.new()
	_overlay.name = "ImageOverlay"
	_overlay.color = Color(0.976, 0.957, 0.91, 0.4)  # 暖白蒙版 40% 透明
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	# 把蒙版移到 BackgroundImage 之上、VBox 之下
	move_child(_overlay, get_node("VBox").get_index() - 1)

	print("[Cover] ✓ Background image loaded: %s (%dx%d)" % [source_path, tex.get_width(), tex.get_height()])