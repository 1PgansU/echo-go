# MapBase：所有地图场景的基类
# 职责：
#   - 1:1 显示像素背景图（不缩放，保证清晰度）
#   - 维护本地图的传送门 / NPC
#   - 提供世界坐标 (0,0) ~ (world_size) 边界
#   - 提供 change_to(other_map_id) 切场景
extends Node2D
class_name MapBase

# 地图世界大小的两种模式
enum MapSizeMode {
	VIEWPORT,  # 玩家边界 = 视口大小（1280x720），图溢出被裁
	IMAGE,     # 玩家边界 = 渲染后图大小，能在地图里走
}

# 由 MapManager 在载入时填入
var map_id: String = ""
var map_title: String = ""

# === 子类需要 export ===
@export var background_path: String = ""        # 像素背景图（res:// 路径）
@export var background_color: Color = Color(0.886, 0.827, 0.659)  # 图片外的填充
@export var viewport_size: Vector2 = Vector2(1280, 720)  # 游戏视口（用于相机）
@export var pixel_scale: float = 1.0              # 像素放大倍率（默认 1=不放大；只在大地图手动开）
@export var pixel_art: bool = false              # 像素风开关（默认关，不影响原图）
@export var fit_to_viewport: bool = false        # 默认不强行铺满；只在大地图手动开
@export var map_size_mode: MapSizeMode = MapSizeMode.IMAGE  # 默认玩家边界=图大小

# === 内部 ===
var _background: Sprite2D
var _bg_size: Vector2 = Vector2.ZERO   # 原图大小（未缩放）
var world_size: Vector2 = Vector2.ZERO  # 等于 _bg_size

func _ready() -> void:
	# === 背景色填充（视口大小）===
	var fill := ColorRect.new()
	fill.color = background_color
	fill.position = Vector2.ZERO
	fill.size = viewport_size
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.z_index = -10
	add_child(fill)

	# === 像素背景图（1:1 不缩放）===
	if background_path != "" and ResourceLoader.exists(background_path):
		var tex: Texture2D = load(background_path)
		if tex != null:
			_bg_size = tex.get_size()
			# === 计算最终 scale ===
			var final_scale: float = pixel_scale
			if fit_to_viewport:
				var sx: float = viewport_size.x / _bg_size.x
				var sy: float = viewport_size.y / _bg_size.y
				var fit: float = max(sx, sy)
				if pixel_art:
					final_scale = max(1.0, ceil(fit))
				else:
					final_scale = fit
			# === 渲染后的图实际像素大小 ===
			var rendered: Vector2 = _bg_size * final_scale
			# === 模式 A：地图 = 视口大小（玩家边界=视口，图溢出被裁）===
			# === 模式 B：地图 = 图大小（玩家边界=图，能在地图里走）===
			if map_size_mode == MapSizeMode.VIEWPORT:
				world_size = viewport_size
			else:
				world_size = rendered
			_background = Sprite2D.new()
			_background.texture = tex
			_background.z_index = -5
			_background.centered = false
			# 居中：让图中心对齐视口中心（溢出部分在视口外被裁掉）
			var offset: Vector2 = (viewport_size - rendered) * 0.5
			_background.position = offset
			# 像素风：关 filter，用 nearest-neighbor；放大后保持硬边
			if pixel_art:
				_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			# 用 scale 放大
			_background.scale = Vector2(final_scale, final_scale)
			add_child(_background)
			print("[MapBase] %s bg: %s 原图=%.0fx%.0f scale=%.2f 渲染=%.0fx%.0f 视口=%.0fx%.0f mode=%s (像素风=%s)" % [map_id, background_path, _bg_size.x, _bg_size.y, final_scale, rendered.x, rendered.y, viewport_size.x, viewport_size.y, map_size_mode, str(pixel_art)])
		else:
			push_warning("[MapBase] %s: failed to load %s" % [map_id, background_path])
	else:
		push_warning("[MapBase] %s: no background at %s" % [map_id, background_path])

	# === Camera2D（跟随玩家，限制在地图内）===
	_setup_camera()
	# 等玩家进来后再绑定相机（延迟到帧尾）
	call_deferred("_bind_camera_to_player")


func _setup_camera() -> void:
	# 删除旧的
	for c in get_children():
		if c.name == "MapCamera" and c is Camera2D:
			c.queue_free()
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.zoom = Vector2.ONE
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	# 限制相机在地图内
	var limit_left: int = 0
	var limit_top: int = 0
	var limit_right: int = 0
	var limit_bottom: int = 0
	if world_size != Vector2.ZERO:
		limit_right = int(world_size.x)
		limit_bottom = int(world_size.y)
		# 如果地图小于视口，让相机停在地图中心
		if world_size.x < viewport_size.x:
			var half_w: int = int(world_size.x) / 2
			limit_left = half_w
			limit_right = half_w
		if world_size.y < viewport_size.y:
			var half_h: int = int(world_size.y) / 2
			limit_top = half_h
			limit_bottom = half_h
	cam.limit_left = limit_left
	cam.limit_top = limit_top
	cam.limit_right = limit_right
	cam.limit_bottom = limit_bottom
	add_child(cam)
	# 必须在 add_child 之后才能 make_current（Godot 4 强约束）
	cam.make_current()


func _bind_camera_to_player() -> void:
	var cam := get_node_or_null("MapCamera")
	if cam == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# 把相机挂在玩家身上 → 自动跟随；limit 仍然由 Camera2D 自己控制
	cam.reparent(player, false)
	cam.position = Vector2.ZERO


# 玩家出生点（子类可重写）
func get_spawn_position() -> Vector2:
	# 默认：地图中心偏下
	if world_size != Vector2.ZERO:
		return Vector2(world_size.x * 0.5, world_size.y * 0.7)
	return Vector2(640, 480)


# 获取地图边界（玩家限位用）
func get_world_bounds() -> Rect2:
	if world_size == Vector2.ZERO:
		return Rect2(Vector2.ZERO, viewport_size)
	return Rect2(Vector2.ZERO, world_size)


# 切到另一张图（用 MapManager 集中调度）
func change_to(other_map_id: String, spawn_pos: Vector2 = Vector2.ZERO) -> void:
	var mm = get_node_or_null("/root/MapManager")
	if mm and mm.has_method("change_map"):
		mm.change_map(other_map_id, spawn_pos)


# 取得本地图所有"门"节点（供 MapManager 处理入口）
func get_portals() -> Array:
	var portals: Array = []
	for child in get_children():
		if child == null:
			continue
		if child.is_in_group("portals"):
			portals.append(child)
	return portals


# 取得本地图所有 NPC（供 World 信号 / 保存用）
func get_npcs() -> Array:
	var npcs: Array = []
	for child in get_children():
		if child == null:
			continue
		if child is Area2D and child.has_method("interact") and child.is_in_group("npcs"):
			npcs.append(child)
	return npcs
