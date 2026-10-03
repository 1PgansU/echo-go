# KeyHintHUD.gd — 占位（图标已替代快捷键面板）
# 保留此脚本以兼容已挂在场景上的引用，但不再显示任何 UI
extends CanvasLayer

func _ready() -> void:
	# 全部子节点清空，并禁用自身
	for c in get_children():
		c.queue_free()
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED