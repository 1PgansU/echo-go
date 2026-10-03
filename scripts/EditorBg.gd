extends Sprite2D
# EditorBg：只在编辑器里显示的预览背景。运行时隐藏（避免和 MapBase._ready 创建的背景重叠）
@export var show_mouse_coords: bool = true
@onready var coord_label: Label = $CoordLabel

func _ready() -> void:
	if Engine.is_editor_hint():
		# 编辑器里显示背景
		visible = true
		if coord_label:
			coord_label.visible = true
		set_process(true)
	else:
		visible = false
		if coord_label:
			coord_label.visible = false
		set_process(false)


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if coord_label and show_mouse_coords:
		var mouse_pos := get_local_mouse_position()
		coord_label.text = "🖱️ 鼠标坐标: (%d, %d)" % [int(mouse_pos.x), int(mouse_pos.y)]
