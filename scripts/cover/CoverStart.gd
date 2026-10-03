extends Control

# 封面（继承自 echo_go_start 完整设计）：
# - 浮动小岛 + 5 朵飘云 + 标题 + 太阳 + 雨动画
# - 点云 3 次 → 下雨；点太阳 → 放晴
# - 按钮：
#     继续  → emit "continue_pressed"（Main 连到 _on_continue_pressed）
#     重来  → emit "start_pressed"（Main 连到 _on_start_pressed）

signal start_pressed
signal continue_pressed

@onready var island: TextureRect = $Island
@onready var title: TextureRect = $Title
@onready var continue_button: TextureButton = $Continue
@onready var restart_button: TextureButton = $Restart
@onready var note: Label = $Note
@onready var sky: ColorRect = $Sky

var time := 0.0
var island_y := 0.0
var title_y := 0.0
var clouds: Array[Sprite2D] = []
var cloud_base: Dictionary = {}
var click_count := 0
var last_click := -10.0
var raining := false
var sunny: Color
var rain: CPUParticles2D
var sun: Sprite2D

const SUN_HIDDEN := Vector2(1100, -180)
const SUN_SHOWN := Vector2(1100, 150)


func _ready() -> void:
	island.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	island_y = island.position.y
	title_y = title.position.y
	sunny = sky.color

	# === 按钮显隐：有没有存档决定"继续" 显示 ===
	var sm = get_node_or_null("/root/SaveManager")
	if sm and sm.has_save():
		continue_button.visible = true
		var label: String = sm.get_save_time_label()
		# 把存档时间显示到 note 里（原本的 note 是"点云 X/3"，这里暂存一下）
		note.text = "上次：%s" % label
	else:
		continue_button.visible = false

	_hook(continue_button, "继续")
	_hook(restart_button, "重来")

	_collect_clouds(self)
	for cloud in clouds:
		cloud_base[cloud] = cloud.position
	_make_rain()
	_make_sun()

	# === 一次性进入音效 ===
	var once := AudioStreamPlayer.new()
	once.stream = load("res://assets/cover_start/start_once.wav")
	add_child(once)
	once.play()


func _make_rain() -> void:
	rain = CPUParticles2D.new()
	rain.position = Vector2(640, -20)
	rain.emitting = false
	rain.amount = 80
	rain.lifetime = 1.6
	rain.preprocess = 1.6
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(700, 1)
	rain.direction = Vector2(0.15, 1)
	rain.spread = 8.0
	rain.gravity = Vector2(0, 400)
	rain.initial_velocity_min = 280.0
	rain.initial_velocity_max = 420.0
	rain.scale_amount_min = 2.0
	rain.scale_amount_max = 4.0
	rain.color = Color(0.53, 0.81, 0.92, 0.85)
	add_child(rain)
	move_child(rain, 1)


func _make_sun() -> void:
	sun = Sprite2D.new()
	sun.texture = load("res://assets/cover_start/sun.png")
	sun.scale = Vector2(0.28, 0.28)
	sun.position = SUN_HIDDEN
	add_child(sun)


func _collect_clouds(node: Node) -> void:
	for child in node.get_children():
		if child is Sprite2D and str(child.name).begins_with("Cloud"):
			clouds.append(child)
		_collect_clouds(child)


func _process(delta: float) -> void:
	time += delta
	island.position.y = island_y + sin(time * 1.2) * 8.0
	title.position.y = title_y + sin(time * 1.5 + 0.8) * 5.0
	if raining:
		sun.position.y = SUN_SHOWN.y + sin(time * 1.4) * 4.0
		return
	var i := 0
	for cloud in clouds:
		var base: Vector2 = cloud_base[cloud]
		var phase := float(i) * 1.3
		cloud.position = base + Vector2(sin(time * 0.7 + phase) * 6.0, cos(time * 0.55 + phase) * 4.0)
		i += 1


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos: Vector2 = mouse.position
	if raining and sun.get_rect().has_point(sun.to_local(pos)):
		_restore()
		get_viewport().set_input_as_handled()
		return
	if raining:
		return
	if continue_button.get_global_rect().has_point(pos) or restart_button.get_global_rect().has_point(pos):
		return
	for cloud in clouds:
		if cloud.get_rect().has_point(cloud.to_local(pos)):
			var base_scale := cloud.scale
			cloud.scale = base_scale * 1.12
			var tween := create_tween()
			tween.tween_property(cloud, "scale", base_scale, 0.15)
			_click_cloud()
			get_viewport().set_input_as_handled()
			return


func _click_cloud() -> void:
	if time - last_click > 2.0:
		click_count = 0
	last_click = time
	click_count += 1
	note.text = "点云 %d/3" % click_count
	if click_count >= 3:
		_start_rain()


func _start_rain() -> void:
	raining = true
	note.text = "下雨"
	rain.emitting = true
	sun.position = SUN_HIDDEN
	var drop := create_tween()
	drop.tween_property(sun, "position", SUN_SHOWN, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var gloomy := Color(0.55, 0.58, 0.62, sky.color.a)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sky, "color", gloomy, 0.8)
	for cloud in clouds:
		tween.tween_property(cloud, "modulate:a", 0.0, 0.6)


func _hook(button: TextureButton, message: String) -> void:
	button.pivot_offset = button.size * 0.5
	button.mouse_entered.connect(func() -> void:
		button.scale = Vector2(1.06, 1.06)
	)
	button.mouse_exited.connect(func() -> void:
		button.scale = Vector2.ONE
	)
	button.button_down.connect(func() -> void:
		button.scale = Vector2(0.96, 0.96)
	)
	button.button_up.connect(func() -> void:
		button.scale = Vector2(1.06, 1.06)
		note.text = message
		# === 用信号发出去，Main 会接 ===
		if message == "继续":
			continue_pressed.emit()
		elif message == "重来":
			# 先恢复天气（视觉），再清档进新游戏
			_restore()
			start_pressed.emit()
	)


# （信号发出去，Main 连到 _on_continue_pressed / _on_start_pressed）


func _restore() -> void:
	raining = false
	click_count = 0
	note.text = "放晴"
	rain.emitting = false
	sky.color = sunny
	var tween := create_tween()
	tween.tween_property(sun, "position", SUN_HIDDEN, 0.4)
	for cloud in clouds:
		cloud.modulate.a = 1.0
		cloud.position = cloud_base[cloud]