# PixelSprite：用 _draw() 直接绘制一个 16x16 像素艺术小人
# 不需要外部贴图，纯代码画
extends Node2D
class_name PixelSprite

# 角色外观配置（每种 NPC 唯一）
@export var skin: Color = Color(0.96, 0.80, 0.65)         # 皮肤
@export var hair: Color = Color(0.20, 0.13, 0.07)          # 头发
@export var shirt: Color = Color(0.45, 0.65, 0.85)         # 上衣
@export var pants: Color = Color(0.25, 0.30, 0.45)         # 裤子
@export var hair_style: int = 0                           # 0=短 1=中长 2=光头 3=双马尾 4=卷 5=刘海
@export var accessory: int = 0                            # 0=无 1=眼镜 2=胡茬 3=领带 4=刘海盖 5=背包

# 每个像素 3x3 缩放，最终 48x48 显示（与背景图里的像素小人相称）
const PIXEL := 3.0

func _ready() -> void:
	# 用 set_meta 让 _process 能访问
	set_meta("is_pixel", true)

func _draw() -> void:
	# 16x16 像素布局 (居中绘制，所以 x 减 32, y 减 32)
	# y=0 是头顶，y=15 是脚
	var pix := _build_pixel_data()
	for y in range(16):
		for x in range(16):
			var c = pix[y][x]
			if c.a <= 0.001:
				continue
			var rect = Rect2(
				(x * PIXEL) - 32.0,
				(y * PIXEL) - 32.0,
				PIXEL, PIXEL
			)
			draw_rect(rect, c, true)

# 生成 16x16 像素颜色网格
func _build_pixel_data() -> Array:
	var pix: Array = []
	for y in range(16):
		pix.append([])
		for x in range(16):
			pix[y].append(Color(0, 0, 0, 0))  # 默认透明

	# === 身体轮廓 (居中, 5-10 宽, 6-15 高) ===
	# 躯干 (衣服): y 7-11, x 5-10
	for y in range(7, 12):
		for x in range(5, 11):
			pix[y][x] = shirt

	# 裤子: y 12-15, x 5-10
	for y in range(12, 16):
		for x in range(5, 11):
			pix[y][x] = pants

	# 鞋子 (深色脚): y 15, x 5-10 单独压暗
	var shoe := pants.darkened(0.5)
	for x in range(5, 11):
		pix[15][x] = shoe

	# === 头 (皮肤): y 2-6, x 5-10 ===
	for y in range(2, 7):
		for x in range(5, 11):
			pix[y][x] = skin

	# 脖子: y 6-7, x 6-9 略深
	var neck := skin.darkened(0.15)
	for x in range(6, 10):
		pix[7][x] = neck

	# === 头发 ===
	match hair_style:
		0:  # 短发 (覆盖头顶 y 0-3)
			for y in range(0, 4):
				for x in range(4, 11):
					pix[y][x] = hair
			# 鬓角
			pix[4][4] = hair
			pix[4][10] = hair
		1:  # 中长发 (到肩膀)
			for y in range(0, 4):
				for x in range(4, 11):
					pix[y][x] = hair
			pix[4][4] = hair
			pix[4][10] = hair
			pix[5][4] = hair
			pix[5][10] = hair
		2:  # 光头 (只有鬓角一缕)
			pix[1][5] = hair
			pix[1][10] = hair
		3:  # 双马尾 (小女孩/可爱)
			for y in range(0, 4):
				for x in range(5, 11):
					pix[y][x] = hair
			pix[4][4] = hair
			pix[4][11] = hair
			pix[5][4] = hair
			pix[5][11] = hair
			pix[6][4] = hair
			pix[6][11] = hair
		4:  # 卷发 (蓬松, 大一点)
			for y in range(0, 5):
				for x in range(3, 12):
					pix[y][x] = hair
			pix[5][3] = hair
			pix[5][12] = hair
		5:  # 刘海盖 (额前)
			for y in range(0, 4):
				for x in range(4, 11):
					pix[y][x] = hair
			# 长刘海到眼睛下
			pix[4][5] = hair
			pix[4][6] = hair
			pix[4][9] = hair
			pix[4][10] = hair

	# === 眼睛 (y=4, x=6/9) ===
	var eye := Color(0.05, 0.05, 0.05)
	# 默认皮肤眼睛区域可见 (hair_style != 5刘海盖)
	if hair_style != 5:
		pix[4][6] = eye
		pix[4][9] = eye
	else:
		# 刘海盖：眼睛再下一行
		pix[5][6] = eye
		pix[5][9] = eye

	# === 嘴 (y=5, x=7-8) ===
	var mouth := Color(0.65, 0.30, 0.25)
	if hair_style != 5:
		pix[5][7] = mouth
		pix[5][8] = mouth
	else:
		pix[6][7] = mouth
		pix[6][8] = mouth

	# === 腮红 (y=5, x=5/10) ===
	var blush := Color(1.0, 0.6, 0.55, 0.5)
	if hair_style != 5:
		pix[5][5] = blush
		pix[5][10] = blush

	# === 配件 ===
	match accessory:
		1:  # 眼镜
			pix[4][6] = Color(0, 0, 0, 1)
			pix[4][9] = Color(0, 0, 0, 1)
			pix[4][7] = Color(0, 0, 0, 1)
			pix[4][8] = Color(0, 0, 0, 1)
			# 镜框
			var glass := Color(0.15, 0.15, 0.15)
			pix[3][6] = glass
			pix[3][7] = glass
			pix[3][8] = glass
			pix[3][9] = glass
		2:  # 胡茬 (爸爸用)
			var stub := Color(0.20, 0.13, 0.07)
			pix[5][6] = stub
			pix[5][10] = stub
			pix[6][6] = stub
			pix[6][10] = stub
			pix[6][7] = stub
			pix[6][8] = stub
		3:  # 领带
			pix[8][7] = Color(0.65, 0.15, 0.15)
			pix[8][8] = Color(0.65, 0.15, 0.15)
			pix[9][7] = Color(0.65, 0.15, 0.15)
			pix[9][8] = Color(0.65, 0.15, 0.15)
			pix[10][7] = Color(0.65, 0.15, 0.15)
			pix[10][8] = Color(0.65, 0.15, 0.15)
		4:  # 刘海盖 (小女孩)
			pass  # 头发里已经处理
		5:  # 背包
			pix[8][4] = Color(0.45, 0.30, 0.20)
			pix[9][4] = Color(0.45, 0.30, 0.20)
			pix[10][4] = Color(0.45, 0.30, 0.20)
			pix[11][4] = Color(0.45, 0.30, 0.20)

	# === 手臂 (上臂颜色稍深) ===
	var arm := shirt.darkened(0.18)
	# 左臂
	pix[7][4] = arm
	pix[8][4] = arm
	pix[9][4] = arm
	pix[10][4] = arm
	# 右臂
	pix[7][11] = arm
	pix[8][11] = arm
	pix[9][11] = arm
	pix[10][11] = arm

	# 手 (皮肤)
	pix[11][4] = skin
	pix[11][11] = skin

	# === 阴影 (脚下) ===
	pix[15][4] = Color(0, 0, 0, 0.15)
	pix[15][11] = Color(0, 0, 0, 0.15)

	return pix


# 跑步动画（在 NPC.gd 里调用 toggle）
var _walk_t: float = 0.0
func set_walk_phase(phase: float) -> void:
	_walk_t = phase
	queue_redraw()

func get_walk_phase() -> float:
	return _walk_t
