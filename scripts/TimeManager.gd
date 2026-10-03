# TimeManager：北京时间，游戏内时间系统
extends Node

# === 持久化文件 ===
const PROFILE_PATH := "user://time_profile.json"

# === 数据 ===
# player_age: 玩家输入的真实年龄（如 30）
# first_run_real_ts: 首次启动时真实 UTC unix 时间（秒）
# game_birth_year: 游戏内"那年"基准年（= first_run_real_year - player_age + 16）
var _data: Dictionary = {}
var _loaded: bool = false

# 星期几中文
const WEEKDAY_ZH := ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

# 北京时区：UTC+8 = 8*3600 = 28800秒
const BEIJING_OFFSET_SEC := 28800


func _ready() -> void:
	_load_profile()


# === 加载 ===
func _load_profile() -> void:
	_loaded = false
	_data = {}
	if not FileAccess.file_exists(PROFILE_PATH):
		return
	var f = FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return
	var text = f.get_as_text()
	f.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_warning("[TimeManager] parse error: %s" % json.get_error_message())
		return
	_data = json.data
	_loaded = true
	print("[TimeManager] profile loaded: %s" % _data)


# === 是否有档案（玩家已输入年龄）===
func has_profile() -> bool:
	return _loaded and _data.has("player_age") and _data.has("first_run_real_ts")


# === 玩家首次输入年龄 ===
func setup(age: int) -> void:
	age = clamp(age, 10, 100)
	var utc_ts: int = int(Time.get_unix_time_from_system())
	var beijing_ts: int = utc_ts + BEIJING_OFFSET_SEC
	var real_dt: Dictionary = Time.get_datetime_dict_from_unix_time(beijing_ts)
	var real_year: int = real_dt.get("year", 2026)
	var game_birth_year: int = real_year - age + 16
	_data = {
		"player_age": age,
		"first_run_real_ts": utc_ts,
		"game_birth_year": game_birth_year
	}
	_save_profile()
	print("[TimeManager] profile saved: age=%d, game_birth_year=%d (16岁那年=%d)" % [age, game_birth_year, game_birth_year])


# === 内部 ===
func _save_profile() -> void:
	var f = FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[TimeManager] save failed")
		return
	f.store_string(JSON.stringify(_data, "  "))
	f.close()
	_loaded = true


# === 内部：拿当前"北京 datetime"（含 weekday）
# Godot 的 get_unix_time_from_system 返回 UTC
# 加上 8 小时偏移，得到北京时间 ts
# 然后把 beijing_ts 当 UTC 解 → weekday/month/day/hour 都是北京的
# 最后再用 Zeller 算法校正 weekday（不受 OS 时区影响）
func _now_beijing_dt() -> Dictionary:
	var utc_ts: int = int(Time.get_unix_time_from_system())
	var beijing_ts: int = utc_ts + BEIJING_OFFSET_SEC
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(beijing_ts)
	dt["weekday"] = _calc_weekday(
		int(dt.get("year", 2026)),
		int(dt.get("month", 1)),
		int(dt.get("day", 1))
	)
	return dt


# === Zeller-like 计算 weekday (0=周日, 1=周一, ..., 6=周六)
# 适用于公历 1582+ (Python 算法)
func _calc_weekday(year: int, month: int, day: int) -> int:
	if month <= 2:
		month += 12
		year -= 1
	var k: int = year % 100
	var j: int = year / 100
	var h: int = (day + (13 * (month + 1)) / 5 + k + k / 4 + j / 4 + 5 * j) % 7
	# h: 0=周六, 1=周日, 2=周一, ..., 6=周五
	var weekday: int = (h + 5) % 7  # 转 0=周日
	return weekday


# === 当前游戏时间 ===
# 返回 Dictionary: year/month/day/hour/minute/weekday
func now() -> Dictionary:
	if not has_profile():
		return {}
	var first_utc_ts: int = int(_data.get("first_run_real_ts", 0))
	var birth_year: int = int(_data.get("game_birth_year", 2010))
	var utc_now: int = int(Time.get_unix_time_from_system())
	var beijing_ts: int = utc_now + BEIJING_OFFSET_SEC
	# 把 beijing_ts 当 UTC 解 → 拿到的是"北京 datetime"
	var beijing_dt: Dictionary = Time.get_datetime_dict_from_unix_time(beijing_ts)
	var delta_seconds: int = utc_now - first_utc_ts
	var delta_days: int = delta_seconds / 86400
	var years_passed: int = delta_days / 365
	var game_year: int = birth_year + years_passed
	var game_dt: Dictionary = beijing_dt.duplicate()
	game_dt["year"] = game_year
	# 用 Zeller 算法重算 weekday（不受 OS 时区影响）
	game_dt["weekday"] = _calc_weekday(
		int(game_dt.get("year", 2010)),
		int(game_dt.get("month", 1)),
		int(game_dt.get("day", 1))
	)
	return game_dt


# === 友好的游戏日期显示 ===
# 默认 "10月2日"
# with_year=true: "2012年10月2日"
func today_str(with_year: bool = true) -> String:
	var t: Dictionary = now()
	if t.is_empty():
		return ""
	var month: int = int(t.get("month", 1))
	var day: int = int(t.get("day", 1))
	var year: int = int(t.get("year", 2010))
	if with_year:
		return "%d年%d月%d日" % [year, month, day]
	else:
		return "%d月%d日" % [month, day]


# === 现实真实北京日期（带年份）===
func real_today_str() -> String:
	var dt: Dictionary = _now_beijing_dt()
	var year: int = int(dt.get("year", 2026))
	var month: int = int(dt.get("month", 1))
	var day: int = int(dt.get("day", 1))
	return "%d年%d月%d日" % [year, month, day]


# === 现实真实北京时刻 ===
func real_now_str() -> String:
	var dt: Dictionary = _now_beijing_dt()
	var hour: int = int(dt.get("hour", 0))
	var minute: int = int(dt.get("minute", 0))
	return "北京 %02d:%02d" % [hour, minute]


# === 距离首次启动过了几天（真实） ===
func days_since_start() -> int:
	if not has_profile():
		return 0
	var utc_now: int = int(Time.get_unix_time_from_system())
	var first_utc_ts: int = int(_data.get("first_run_real_ts", utc_now))
	return int((utc_now - first_utc_ts) / 86400)


# === 玩家信息（用于 UI） ===
func player_age() -> int:
	return int(_data.get("player_age", 16))


# === 重置（用于 debug / 设置）===
func reset() -> void:
	_data = {}
	_loaded = false
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	print("[TimeManager] profile reset")