# OfflineClock.gd — 离线时间换算 + 存档
# 1 现实小时 = 1 游戏日（可在 settings.json 改）
extends Node

const SAVE_PATH := "user://offline_state.json"
const SETTINGS_PATH := "user://offline_settings.json"
# 1 现实小时 = 1 游戏日
# 离线 1 小时 = 1 游戏日，触发 4 场戏
const REAL_SECONDS_PER_GAME_DAY := 3600.0  # 1 hour = 1 game day

# 存档
var _state: Dictionary = {
	"last_quit_unix": 0,    # 上次退游戏时 unix 时间戳（秒）
	"game_day": 1,          # 当前游戏日数（Day N）
	"events": []            # 所有奇遇（按天数分组）
}

func _ready() -> void:
	_load()
	# 启动时立刻检测离线时长
	call_deferred("_check_offline_elapsed")

# 启动时调用一次：算出离线了几天，补算"奇遇"
func _check_offline_elapsed() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var last: int = int(_state.get("last_quit_unix", 0))
	if last <= 0:
		# 第一次玩
		_state["last_quit_unix"] = now
		_state["game_day"] = 1
		_save()
		return
	var elapsed_real: float = float(now - last)
	var elapsed_days: int = int(floor(elapsed_real / REAL_SECONDS_PER_GAME_DAY))
	if elapsed_days <= 0:
		# 不到 1 个游戏日，啥也不做
		return
	print("[OfflineClock] 离线 %d 秒 ≈ %d 游戏日 (1 小时 = 1 天)" % [int(elapsed_real), elapsed_days])
	# 调用 DramaEngine 跑 N 天
	var drama = load("res://scripts/offline/DramaEngine.gd").new()
	drama.name = "DramaEngine"
	add_child(drama)
	drama.run_n_days(elapsed_days)
	# 推进游戏日数
	_state["game_day"] = int(_state.get("game_day", 1)) + elapsed_days
	_state["last_quit_unix"] = now
	_save()

# 玩家主动退出游戏时调用
func on_quit() -> void:
	_state["last_quit_unix"] = int(Time.get_unix_time_from_system())
	_save()
	print("[OfflineClock] 退出存档完成。当前 Day %d" % int(_state.get("game_day", 1)))

# 玩家手动跳到指定游戏日（调试用）
func force_day(day: int) -> void:
	_state["game_day"] = day
	_state["last_quit_unix"] = int(Time.get_unix_time_from_system())
	_save()

# 写一条奇遇
func add_event(evt: Dictionary) -> void:
	# evt: { "day": int, "a": str, "b": str, "template": str, "summary": str, "delta": int, "type": str, "transcript": [str,str,...] }
	_state.get("events", []).append(evt)
	# 控制总条数（防止无限增长）：最多保留 200 条
	var evs: Array = _state.get("events", [])
	while evs.size() > 200:
		evs.pop_front()
	_state["events"] = evs

# 查某个 NPC 最近的奇遇
func get_events_for(npc_id: String, max_n: int = 5) -> Array:
	var out: Array = []
	var evs: Array = _state.get("events", [])
	for i in range(evs.size() - 1, -1, -1):
		var e: Dictionary = evs[i]
		if e.get("a", "") == npc_id or e.get("b", "") == npc_id:
			out.append(e)
		if out.size() >= max_n:
			break
	return out

# 查所有奇遇（按天数分组）
func get_all_events_grouped() -> Dictionary:
	var grouped: Dictionary = {}
	var evs: Array = _state.get("events", [])
	for e in evs:
		var d: int = int(e.get("day", 1))
		if not grouped.has(d): grouped[d] = []
		grouped[d].append(e)
	return grouped

func get_current_day() -> int:
	return int(_state.get("game_day", 1))

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[OfflineClock] 写存档失败")
		return
	f.store_string(JSON.stringify(_state, "\t"))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_DICTIONARY:
		_state = parsed