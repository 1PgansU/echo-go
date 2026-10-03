# 玩家：8 方向移动 + 交互检测（实时 proximity 检测）
extends CharacterBody2D
class_name Player

const SPEED := 160.0

enum Facing { DOWN, UP, LEFT, RIGHT }

@onready var body_sprite: PixelSprite = $PixelSprite
@onready var direction_indicator: Node2D = $DirectionIndicator
@onready var interaction_area: Area2D = $InteractionArea

var facing: Facing = Facing.DOWN
var is_moving: bool = false
var can_move: bool = true
var nearby_npc: Node = null

func _ready() -> void:
	add_to_group("player")
	# 玩家固定外观（少年白衬衫蓝裤）
	if body_sprite:
		body_sprite.skin = Color(0.96, 0.80, 0.65)
		body_sprite.hair = Color(0.10, 0.08, 0.06)
		body_sprite.shirt = Color(0.95, 0.95, 0.98)
		body_sprite.pants = Color(0.30, 0.40, 0.65)
		body_sprite.hair_style = 4
		body_sprite.accessory = 5
		body_sprite.queue_redraw()

func _physics_process(_delta: float) -> void:
	if not can_move:
		velocity = Vector2.ZERO
		is_moving = false
		_update_anim()
		return

	var input_vec = Vector2.ZERO
	if Input.is_action_pressed("move_up"):    input_vec.y -= 1
	if Input.is_action_pressed("move_down"):  input_vec.y += 1
	if Input.is_action_pressed("move_left"):  input_vec.x -= 1
	if Input.is_action_pressed("move_right"): input_vec.x += 1

	input_vec = input_vec.normalized()
	velocity = input_vec * SPEED

	if input_vec != Vector2.ZERO:
		is_moving = true
		if abs(input_vec.x) > abs(input_vec.y):
			facing = Facing.RIGHT if input_vec.x > 0 else Facing.LEFT
		else:
			facing = Facing.DOWN if input_vec.y > 0 else Facing.UP
	else:
		is_moving = false

	_update_anim()
	move_and_slide()
	_clamp_to_world_bounds()

	# 实时检测附近 NPC
	_detect_npc()

	# 交互键
	if Input.is_action_just_pressed("interact"):
		_try_interact()

	# R 键：在 NPC 附近时直接弹五子棋占位面板（可视化演示用，不走 LLM）
	if Input.is_action_just_pressed("play_gomoku"):
		_try_play_gomoku()

func _detect_npc() -> void:
	var closest: Node = null
	var min_dist := INF

	for area in interaction_area.get_overlapping_areas():
		# 同时接受 NPC 和 Portal
		var is_npc := area.has_method("interact") and area.is_in_group("npcs")
		var is_portal := area.is_in_group("portals") and area.has_method("interact")
		if not (is_npc or is_portal):
			continue
		var dist = global_position.distance_to(area.global_position)
		if dist < min_dist:
			min_dist = dist
			closest = area

	if closest != nearby_npc:
		# 离开旧对象
		if nearby_npc and nearby_npc.has_method("set_player_nearby"):
			nearby_npc.set_player_nearby(false)
		# 进入新对象
		nearby_npc = closest
		if nearby_npc and nearby_npc.has_method("set_player_nearby"):
			nearby_npc.set_player_nearby(true)

func _update_anim() -> void:
	# 走路浮动
	if is_moving:
		var t = Time.get_ticks_msec() / 1000.0
		body_sprite.position.y = sin(t * 8.0) * 2.0
		# 朝向倾斜（左右走时身体轻微歪头）
		match facing:
			Facing.LEFT:
				body_sprite.rotation = -0.06
			Facing.RIGHT:
				body_sprite.rotation = 0.06
			_:
				body_sprite.rotation = 0.0
	else:
		body_sprite.position.y = 0
		body_sprite.rotation = 0.0

	# 朝向指示器（保留小三角，朝向玩家看的方向）
	match facing:
		Facing.DOWN:
			direction_indicator.rotation = PI
			direction_indicator.visible = false  # 朝下不显示指示器
		Facing.UP:
			direction_indicator.rotation = 0
			direction_indicator.visible = true
		Facing.RIGHT:
			direction_indicator.rotation = PI / 2
			direction_indicator.visible = true
		Facing.LEFT:
			direction_indicator.rotation = -PI / 2
			direction_indicator.visible = true

func _try_interact() -> void:
	if nearby_npc != null:
		nearby_npc.interact(self)


func _try_play_gomoku() -> void:
	if nearby_npc != null and nearby_npc.has_method("play_gomoku"):
		nearby_npc.play_gomoku(self)

func set_can_move(value: bool) -> void:
	can_move = value
	if not value:
		velocity = Vector2.ZERO


# 把玩家位置限制在当前地图的边界内
func _clamp_to_world_bounds() -> void:
	var parent := get_parent()
	if parent == null:
		return
	# 兼容旧地图（视口固定 1280x720）和新地图（用 get_world_bounds）
	if parent.has_method("get_world_bounds"):
		var b: Rect2 = parent.get_world_bounds()
		# 玩家半径 16 px
		var r := 16.0
		var px: float = clamp(global_position.x, b.position.x + r, b.position.x + b.size.x - r)
		var py: float = clamp(global_position.y, b.position.y + r, b.position.y + b.size.y - r)
		global_position = Vector2(px, py)
	else:
		# 老 MapBase：固定 1280x720
		global_position.x = clamp(global_position.x, 16.0, 1280.0 - 16.0)
		global_position.y = clamp(global_position.y, 16.0, 720.0 - 16.0)