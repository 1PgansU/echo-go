# MapManager：单例 Autoload，统一调度多张地图的切换
# 持有当前 map 实例 + 玩家节点引用，切换时旧 map queue_free，新 map instantiate 并把玩家 reparent 进去
extends Node

# 所有已注册的 map 资源（map_id -> PackedScene 路径）
var map_registry: Dictionary = {}

# 当前地图实例
var current_map: Node = null

# 玩家（从 World 注入）
var player: Node = null

# 出生点（切换时使用）
var _pending_spawn: Vector2 = Vector2.ZERO
var _pending_spawn_set: bool = false

# 信号
signal map_changed(new_map_id: String)
signal player_spawn_requested(spawn_pos: Vector2)


func _ready() -> void:
	# 注册所有地图（路径写死，简洁可控）
	map_registry = {
		"world":  "res://scenes/World.tscn",       # 主入口（两个门）
		"home":   "res://scenes/HomeMap.tscn",     # 家
		"class":  "res://scenes/ClassroomMap.tscn" # 教室
	}


# 启动：加载主入口地图
func start(player_node: Node, start_map_id: String = "world") -> void:
	player = player_node
	# 派信（按设计：每次开游戏派一封）—— 在 change_map 之前
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("record_session"):
		gm.record_session()
	change_map(start_map_id, Vector2.ZERO)


# 切换地图
func change_map(map_id: String, spawn_pos: Vector2 = Vector2.ZERO) -> void:
	if not map_registry.has(map_id):
		push_error("[MapManager] Unknown map: %s" % map_id)
		return

	# 旧 map 退出
	if current_map:
		# 玩家先从旧 map 摘下（避免被一起 free）
		if player and player.get_parent() == current_map:
			current_map.remove_child(player)
		current_map.queue_free()
		current_map = null

	# 新 map
	var scene: PackedScene = load(map_registry[map_id])
	if scene == null:
		push_error("[MapManager] Failed to load %s" % map_registry[map_id])
		return
	var new_map = scene.instantiate()
	# 挂到 World 根（WorldRoot）下
	var world_root = get_tree().get_first_node_in_group("world_root")
	if world_root == null:
		# 兜底：挂 Main 节点下
		var main = get_tree().get_first_node_in_group("main")
		if main:
			world_root = main
		else:
			push_error("[MapManager] No world_root / main to attach map")
			return
	world_root.add_child(new_map)
	current_map = new_map

	# 把玩家 reparent 进去
	if player:
		new_map.add_child(player)
		# 出生点
		if spawn_pos != Vector2.ZERO:
			player.global_position = spawn_pos
		elif new_map.has_method("get_spawn_position"):
			player.global_position = new_map.get_spawn_position()
		else:
			player.global_position = Vector2(640, 500)

	# 通知 World 顶部栏更新
	emit_signal("map_changed", map_id)
	# 通知 GameManager（兼容旧 signal）
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("scene_changed"):
		gm.emit_signal("scene_changed", "map:%s" % map_id)
	print("[MapManager] switched to %s" % map_id)


func get_current_map_id() -> String:
	if current_map and "map_id" in current_map:
		return current_map.map_id
	return ""
