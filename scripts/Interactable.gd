# Interactable：通用交互触发器（不画门、不巡逻、不切场景）
# 玩家按 E 调用 interact()，你可以挂自己的脚本覆盖行为，或者用 scene_event_name 触发预定义事件
extends Area2D
class_name Interactable

# === 显示（编辑器里调位置时看得见）===
@export var label_text: String = "📦"           # 头顶 emoji/文字
@export var radius: float = 28.0                 # 编辑器里画的圆形范围
@export var debug_color: Color = Color(0.4, 0.8, 0.5, 0.5)   # 编辑器圆圈颜色
@export var show_in_editor: bool = true          # 编辑器是否显示辅助圈

# === 行为 ===
# 留空 = 什么都不做；填上则触发对应预设事件
@export var scene_event_name: String = ""        # 比如 "mailbox"、"desk"、"bookshelf"
# 或者挂子节点来扩展：override interact() 自己处理

@onready var label: Label = $Label
@onready var hint: Label = $Hint

var _player_nearby: bool = false


func _ready() -> void:
	add_to_group("interactables")
	if label:
		label.text = label_text
	if hint:
		hint.visible = false


func _process(_delta: float) -> void:
	if _player_nearby and hint:
		hint.visible = true
	elif hint:
		hint.visible = false
	if Engine.is_editor_hint() and show_in_editor:
		queue_redraw()


func _draw() -> void:
	# 编辑器预览：画一个绿色半透明圆，方便调位置
	if not Engine.is_editor_hint():
		return
	if not show_in_editor:
		return
	draw_circle(Vector2.ZERO, radius, debug_color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(0.2, 0.5, 0.3, 0.9), 1.5)


func set_player_nearby(value: bool) -> void:
	_player_nearby = value
	if hint:
		hint.visible = value


func interact(_player: Node) -> void:
	# 默认行为：打印事件名 + 触发 GameManager 自定义钩子
	print("[Interactable] %s interacted, event=%s" % [name, scene_event_name])

	var gm = get_node_or_null("/root/GameManager")
	if gm and scene_event_name != "" and gm.has_method("trigger_custom_event"):
		gm.trigger_custom_event(scene_event_name, self)


# 玩家进出范围时自动调用（由信号绑定）
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		set_player_nearby(true)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		set_player_nearby(false)