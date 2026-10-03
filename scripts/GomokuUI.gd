# 五子棋 UI（带 AI）
# - 15x15 棋盘（grid_size=15）
# - 玩家黑子、NPC 白子（Alpha-Beta 剪枝 AI）
# - 标题/提示：当前轮到谁、ESC 关闭
extends Control
class_name GomokuUI

const GRID_SIZE := 15
const CELL_SIZE := 36.0
const PADDING := 28.0
const BOARD_SIZE := CELL_SIZE * (GRID_SIZE - 1) + PADDING * 2.0
const STONE_RADIUS := 14.0

# 棋盘数据：0=空, 1=黑(玩家), 2=白(NPC/AI)
var _board: Array = []
var _player_turn: bool = true
var _npc_id: String = "xiaoyang"
var _npc_name: String = "🐑 小羊"
var _game_over: bool = false  # 游戏是否已结束
var _ai_search_depth: int = 2  # AI 搜索深度（值越大越强但越慢）

# UI
var _board_rect: ColorRect
var _title_label: Label
var _turn_label: Label
var _close_label: Label
var _status_label: Label
var _canvas: Control

# 调试：玩家每步计数器
var _move_count: int = 0


func _ready() -> void:
	# 初始空棋盘
	for r in GRID_SIZE:
		var row: Array = []
		for c in GRID_SIZE:
			row.append(0)
		_board.append(row)

	# 半透明黑色背景
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	# 关闭面板：点背景
	bg.gui_input.connect(_on_bg_input)

	# 主面板（居中）
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-BOARD_SIZE * 0.5 - 40, -BOARD_SIZE * 0.5 - 100)
	panel.size = Vector2(BOARD_SIZE + 80, BOARD_SIZE + 200)
	# 木纹色
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.96, 0.87, 0.66)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(0.4, 0.25, 0.15)
	sb.content_margin_left = 16
	sb.content_margin_top = 16
	sb.content_margin_right = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# 标题
	_title_label = Label.new()
	_title_label.text = "🎮 五子棋 · %s vs 你" % _npc_name
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(0.2, 0.1, 0.05))
	vbox.add_child(_title_label)

	# 回合提示
	_turn_label = Label.new()
	_turn_label.text = "轮到：你（黑子）"
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", 16)
	_turn_label.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1))
	vbox.add_child(_turn_label)

	# 棋盘画板
	_canvas = Control.new()
	_canvas.size = Vector2(BOARD_SIZE, BOARD_SIZE)
	_canvas.custom_minimum_size = Vector2(BOARD_SIZE, BOARD_SIZE)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_on_canvas_draw)
	_canvas.gui_input.connect(_on_canvas_input)
	vbox.add_child(_canvas)

	# 状态
	_status_label = Label.new()
	_status_label.text = "💡 点击棋盘交叉点落子"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.4, 0.3, 0.2))
	vbox.add_child(_status_label)

	# 关闭提示
	_close_label = Label.new()
	_close_label.text = "[ESC] 关闭  ·  落子数：0"
	_close_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_close_label.add_theme_font_size_override("font_size", 12)
	_close_label.add_theme_color_override("font_color", Color(0.5, 0.3, 0.2))
	vbox.add_child(_close_label)

	# 设焦点以接收键盘
	grab_focus()


func setup(npc_id: String, npc_name: String) -> void:
	_npc_id = npc_id
	_npc_name = npc_name


# -------- 输入 --------
func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _on_canvas_input(event: InputEvent) -> void:
	if _game_over:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _player_turn:
		return
	# 计算点击最近的格点
	var pos: Vector2 = mb.position
	var gx := int(round((pos.x - PADDING) / CELL_SIZE))
	var gy := int(round((pos.y - PADDING) / CELL_SIZE))
	if gx < 0 or gx >= GRID_SIZE or gy < 0 or gy >= GRID_SIZE:
		return
	if _board[gy][gx] != 0:
		return
	# 玩家落子
	_board[gy][gx] = 1
	_move_count += 1
	_canvas.queue_redraw()

	# 检查玩家是否获胜
	if _check_win(1, gy, gx):
		_game_over = true
		_turn_label.text = "🏆 你赢了！"
		_status_label.text = "太厉害啦！%s 投来佩服的目光 ✨" % _npc_name
		_close_label.text = "[ESC] 关闭  ·  落子数：%d" % _move_count
		_give_relationship(3)  # 胜利给更多关系分
		return

	# 切换到 AI 回合
	_player_turn = false
	_turn_label.text = "轮到：%s（白子·思考中…）" % _npc_name
	_close_label.text = "[ESC] 关闭  ·  落子数：%d" % _move_count

	# 棋盘已满
	if _get_empty_cells().is_empty():
		_game_over = true
		_turn_label.text = "🤝 棋盘已满 · 平局！"
		_status_label.text = "势均力敌的精彩对决～"
		return

	# 0.5秒延迟后让 AI 出招（模拟思考）
	_ai_think_and_move()


func _ai_think_and_move() -> void:
	# 短暂延迟让节奏更自然
	await get_tree().create_timer(0.5).timeout
	if _game_over or not is_inside_tree():
		return
	var best := _find_best_move(2)  # AI 是白子 = 2
	if best == null or best.is_empty():
		_game_over = true
		_turn_label.text = "🤝 平局！"
		_status_label.text = "棋盘已满～"
		return
	var by: int = best["y"]
	var bx: int = best["x"]
	_board[by][bx] = 2
	_move_count += 1
	_canvas.queue_redraw()

	# 检查 AI 是否获胜
	if _check_win(2, by, bx):
		_game_over = true
		_turn_label.text = "💀 你输了！"
		_status_label.text = "%s 略胜一筹，再来一局？" % _npc_name
		_close_label.text = "[ESC] 关闭  ·  落子数：%d" % _move_count
		_give_relationship(1)
		return

	# 回到玩家回合
	_player_turn = true
	_turn_label.text = "轮到：你（黑子）"
	_close_label.text = "[ESC] 关闭  ·  落子数：%d" % _move_count


func _give_relationship(delta: int) -> void:
	var gm = get_tree().get_first_node_in_group("gamemanager")
	if gm == null:
		gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("add_relationship"):
		gm.call("add_relationship", _npc_id, delta)


# -------- AI 算法（基于你提供的五子棋算法移植到 GDScript） --------

# 1. 胜负判断：只检查刚下的棋子
func _check_win(player: int, y: int, x: int) -> bool:
	var dirs = [[0, 1], [1, 0], [1, 1], [1, -1]]
	for d in dirs:
		var dy: int = d[0]
		var dx: int = d[1]
		var cnt: int = 1
		for step in range(1, 5):
			var ny: int = y + dy * step
			var nx: int = x + dx * step
			if ny >= 0 and ny < GRID_SIZE and nx >= 0 and nx < GRID_SIZE and _board[ny][nx] == player:
				cnt += 1
			else:
				break
		for step in range(1, 5):
			var ny: int = y - dy * step
			var nx: int = x - dx * step
			if ny >= 0 and ny < GRID_SIZE and nx >= 0 and nx < GRID_SIZE and _board[ny][nx] == player:
				cnt += 1
			else:
				break
		if cnt >= 5:
			return true
	return false


# 2. 棋型评分：根据连续棋子数和开口数返回分值
func _get_shape_score(count: int, open_ends: int) -> int:
	if count >= 5:
		return 1000000  # 五连
	if count == 4:
		if open_ends == 2:
			return 100000  # 活四
		if open_ends == 1:
			return 50000  # 冲四
	elif count == 3:
		if open_ends == 2:
			return 5000  # 活三
		if open_ends == 1:
			return 800  # 眠三
	elif count == 2:
		if open_ends == 2:
			return 500  # 活二
		if open_ends == 1:
			return 100  # 眠二
	return 10


# 3. 评估单个点：对指定玩家在(x,y)落子的价值
func _evaluate_point(y: int, x: int, player: int) -> int:
	var score: int = 0
	var dirs = [[0, 1], [1, 0], [1, 1], [1, -1]]
	for d in dirs:
		var dy: int = d[0]
		var dx: int = d[1]
		var count: int = 1
		var open_ends: int = 0
		# 正方向
		for step in range(1, 5):
			var ny: int = y + dy * step
			var nx: int = x + dx * step
			if ny >= 0 and ny < GRID_SIZE and nx >= 0 and nx < GRID_SIZE:
				if _board[ny][nx] == player:
					count += 1
				elif _board[ny][nx] == 0:
					open_ends += 1
					break
				else:
					break
			else:
				break
		# 反方向
		for step in range(1, 5):
			var ny: int = y - dy * step
			var nx: int = x - dx * step
			if ny >= 0 and ny < GRID_SIZE and nx >= 0 and nx < GRID_SIZE:
				if _board[ny][nx] == player:
					count += 1
				elif _board[ny][nx] == 0:
					open_ends += 1
					break
				else:
					break
			else:
				break
		score += _get_shape_score(count, open_ends)
	return score


# 评估整个棋盘对 player 玩家的价值（同时考虑进攻和防守）
func _evaluate_board(player: int) -> int:
	var total: int = 0
	var opponent: int = 1 if player == 2 else 2
	for r in GRID_SIZE:
		for c in GRID_SIZE:
			if _board[r][c] == player:
				total += _evaluate_point(r, c, player)
			elif _board[r][c] == opponent:
				total -= _evaluate_point(r, c, opponent)
	return total


# 收集所有空位（带临近棋子筛选，减少搜索空间）
func _get_empty_cells() -> Array:
	var empties: Array = []
	for r in GRID_SIZE:
		for c in GRID_SIZE:
			if _board[r][c] == 0:
				# 只考虑 2 格内有棋子的位置（开局除外）
				if _has_neighbor(r, c, 2) or _move_count < 2:
					empties.append({"y": r, "x": c})
	# 如果没找到（比如全空棋盘），返回全部空位
	if empties.is_empty():
		for r in GRID_SIZE:
			for c in GRID_SIZE:
				if _board[r][c] == 0:
					empties.append({"y": r, "x": c})
	return empties


func _has_neighbor(y: int, x: int, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dy == 0 and dx == 0:
				continue
			var ny: int = y + dy
			var nx: int = x + dx
			if ny >= 0 and ny < GRID_SIZE and nx >= 0 and nx < GRID_SIZE:
				if _board[ny][nx] != 0:
					return true
	return false


# 4. Alpha-Beta 剪枝搜索
# 注意：minimax 中 "maximizing=true" 表示当前在落子方走（player 进攻），
# "maximizing=false" 表示对手走（player 防守），评估函数始终从 player 视角打分
func _alpha_beta(depth: int, alpha: int, beta: int, maximizing: bool, player: int) -> int:
	# 终止条件：达到深度限制
	if depth == 0:
		return _evaluate_board(player)

	var empties: Array = _get_empty_cells()
	if empties.is_empty():
		return 0

	if maximizing:
		var max_eval: int = -2147483648  # -INF
		for cell in empties:
			var cy: int = cell["y"]
			var cx: int = cell["x"]
			_board[cy][cx] = player
			# 落子后立即判断是否五连
			if _check_win(player, cy, cx):
				_board[cy][cx] = 0
				return 10000000
			var ev: int = _alpha_beta(depth - 1, alpha, beta, false, player)
			_board[cy][cx] = 0
			if ev > max_eval:
				max_eval = ev
			if ev > alpha:
				alpha = ev
			if beta <= alpha:
				break  # 剪枝
		return max_eval
	else:
		var min_eval: int = 2147483647  # INF
		var opponent: int = 1 if player == 2 else 2
		for cell in empties:
			var cy: int = cell["y"]
			var cx: int = cell["x"]
			_board[cy][cx] = opponent
			# 对手落子后立即判断是否五连（如果对手胜利则对 player 极差）
			if _check_win(opponent, cy, cx):
				_board[cy][cx] = 0
				return -10000000
			var ev: int = _alpha_beta(depth - 1, alpha, beta, true, player)
			_board[cy][cx] = 0
			if ev < min_eval:
				min_eval = ev
			if ev < beta:
				beta = ev
			if beta <= alpha:
				break  # 剪枝
		return min_eval


# 5. AI 决策：返回最佳落子位置
func _find_best_move(player: int) -> Dictionary:
	var empty_cells: Array = _get_empty_cells()
	if empty_cells.is_empty():
		return {}

	# 快速检查：能否直接赢？
	for cell in empty_cells:
		var cy: int = cell["y"]
		var cx: int = cell["x"]
		_board[cy][cx] = player
		if _check_win(player, cy, cx):
			_board[cy][cx] = 0
			return cell
		_board[cy][cx] = 0

	# 快速检查：对手能否直接赢？必须堵
	var opponent: int = 1 if player == 2 else 2
	for cell in empty_cells:
		var cy: int = cell["y"]
		var cx: int = cell["x"]
		_board[cy][cx] = opponent
		if _check_win(opponent, cy, cx):
			_board[cy][cx] = 0
			return cell
		_board[cy][cx] = 0

	# Alpha-Beta 搜索
	var best_score: int = -2147483648  # -INF
	var best_move: Dictionary = empty_cells[0]

	# 对候选点先做一次快速评估排序，剪枝效果更好
	var scored: Array = []
	for cell in empty_cells:
		var cy: int = cell["y"]
		var cx: int = cell["x"]
		var s: int = _evaluate_point(cy, cx, player) + _evaluate_point(cy, cx, opponent)
		scored.append({"y": cy, "x": cx, "score": s})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])
	# 只考虑前若干高分点，控制搜索分支
	var candidates: Array = scored.slice(0, min(8, scored.size()))

	for cell in candidates:
		var cy: int = cell["y"]
		var cx: int = cell["x"]
		_board[cy][cx] = player
		var ev: int = _alpha_beta(_ai_search_depth - 1, -2147483648, 2147483647, false, player)
		_board[cy][cx] = 0
		if ev > best_score:
			best_score = ev
			best_move = {"y": cy, "x": cx}

	return best_move


# -------- 绘制 --------
func _on_canvas_draw() -> void:
	# 棋盘底色（米黄）
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(BOARD_SIZE, BOARD_SIZE)),
		Color(0.96, 0.87, 0.66), true)

	# 网格线
	var line_color := Color(0.2, 0.1, 0.05)
	for i in GRID_SIZE:
		var p := float(i) * CELL_SIZE + PADDING
		_canvas.draw_line(Vector2(p, PADDING), Vector2(p, BOARD_SIZE - PADDING), line_color, 1.2)
		_canvas.draw_line(Vector2(PADDING, p), Vector2(BOARD_SIZE - PADDING, p), line_color, 1.2)

	# 5 个星位
	var star_points = [Vector2i(3, 3), Vector2i(3, 11), Vector2i(11, 3), Vector2i(11, 11), Vector2i(7, 7)]
	for sp in star_points:
		var c := Vector2(sp) * CELL_SIZE + Vector2(PADDING, PADDING)
		_canvas.draw_circle(c, 3.0, line_color)

	# 棋子
	for r in GRID_SIZE:
		for c in GRID_SIZE:
			var v = _board[r][c]
			if v == 0:
				continue
			var center := Vector2(c, r) * CELL_SIZE + Vector2(PADDING, PADDING)
			var color := Color(0.05, 0.05, 0.05) if v == 1 else Color(0.98, 0.98, 0.95)
			var outline := Color.WHITE if v == 2 else Color(0.3, 0.3, 0.3)
			_canvas.draw_circle(center, STONE_RADIUS, color)
			# 描边
			var pts: Array = []
			for k in 24:
				var a := float(k) / 24.0 * TAU
				pts.append(center + Vector2(cos(a), sin(a)) * STONE_RADIUS)
			_canvas.draw_polyline(PackedVector2Array(pts), outline, 1.5)


# -------- 外部接口 --------
func open(npc_id: String, npc_name: String) -> void:
	_npc_id = npc_id
	_npc_name = npc_name
	if _title_label:
		_title_label.text = "🎮 五子棋 · %s vs 你" % _npc_name
	show()


func close() -> void:
	# 给 NPC +1 关系分（无论输赢，"陪玩了一局"就算互动）
	_give_relationship(1)
	queue_free()
