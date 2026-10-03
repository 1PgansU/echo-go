# FestivalCalendar.gd — 全年节日 + 纪念日 + 每个 NPC 的生日
"""
系统每天 02:00（游戏内时间）检查：
- 今天是不是节日？→ 触发 NPC 写日记 / 群发消息 / 玩家生日？→ 群发祝福
"""
extends Node

static var _inst: Node = null
static func get_instance() -> Node:
	if _inst == null:
		var EngineScript = load("res://scripts/offline/FestivalCalendar.gd")
		_inst = EngineScript.new()
		_inst.name = "FestivalCalendar"
		var root = Engine.get_main_loop().get_root()
		if root:
			root.add_child(_inst)
	return _inst

# === 节日表（公历月份，0=1月）===
# 类型：festival = 全国节日 / birthday_xxx = NPC 生日 / anniversary_xxx = 玩家纪念日
const FESTIVALS := {
	# 公历节日
	"01-01": {"name": "🎆 元旦",      "type": "festival", "color": "gold"},
	"02-14": {"name": "💝 情人节",    "type": "festival", "color": "pink"},
	"03-08": {"name": "🌷 妇女节",   "type": "festival", "color": "pink"},
	"03-14": {"name": "💗 白色情人节","type": "festival", "color": "white"},
	"05-01": {"name": "🛠️ 劳动节",  "type": "festival", "color": "red"},
	"06-01": {"name": "🎈 六一",     "type": "festival", "color": "rainbow"},
	"09-10": {"name": "📚 教师节",    "type": "festival", "color": "gold"},
	"10-01": {"name": "🇨🇳 国庆",    "type": "festival", "color": "red"},
	"10-31": {"name": "🎃 万圣节",   "type": "festival", "color": "orange"},
	"12-24": {"name": "🎄 平安夜",   "type": "festival", "color": "green"},
	"12-25": {"name": "🎄 圣诞节",   "type": "festival", "color": "red"},
	"12-31": {"name": "🎆 跨年夜",   "type": "festival", "color": "gold"},
}

# === 农历节日（用近似公历日期）===
# 真实农历需要复杂计算，这里用通用近似值
const LUNAR_FESTIVALS := {
	# "MM-DD": {"name": "...", "type": "lunar"}
	"01-15": {"name": "🏮 元宵节",   "type": "lunar"},
	"02-02": {"name": "🐉 龙抬头",   "type": "lunar"},
	"05-05": {"name": "🐲 端午节",   "type": "lunar"},
	"07-07": {"name": "🌌 七夕节",   "type": "lunar"},
	"08-15": {"name": "🥮 中秋节",   "type": "lunar"},
	"09-09": {"name": "🌼 重阳节",   "type": "lunar"},
}

# === NPC 生日（公历，玩家预设）===
const NPC_BIRTHDAYS := {
	"xiaoyou":  "03-21",   # 小柚：春分
	"xiaoyang": "08-15",   # 小羊：和中秋同日（戏剧性）
	"mother":   "05-12",   # 妈妈
	"father":   "10-01",   # 爸爸：和国庆同日
	"brother":  "06-01",   # 弟弟：和六一同日
	"classmate":"11-11",   # 同学
	"teacher":  "09-10",   # 老师：和教师节同日
	"crush":    "02-14",   # 暗恋对象：情人节生日
}

# === "今天有什么？"
# 返回: { is_festival: bool, festival_name, is_birthday: {npc_id: name}, is_anniversary: bool }
func check_today(date_str: String) -> Dictionary:
	var result := {
		"festival": null,
		"lunar": null,
		"birthdays": [],
		"is_anniversary": false,
	}
	if not "-" in date_str or date_str.length() < 10:
		return result
	# 切出 MM-DD
	var mm_dd: String = date_str.substr(5, 5)  # "MM-DD"
	if FESTIVALS.has(mm_dd):
		result["festival"] = FESTIVALS[mm_dd]
	if LUNAR_FESTIVALS.has(mm_dd):
		result["lunar"] = LUNAR_FESTIVALS[mm_dd]
	# NPC 生日
	for npc_id in NPC_BIRTHDAYS:
		if NPC_BIRTHDAYS[npc_id] == mm_dd:
			result["birthdays"].append(npc_id)
	return result

# === 给某 NPC 出一句节日祝福（按节日 / 生日不同） ===
const NPC_DISPLAY := {
	"xiaoyou":  "🍊 小柚",
	"xiaoyang": "🐑 小羊",
	"mother":   "👩 妈妈",
	"father":   "👨 爸爸",
	"brother":  "👦 弟弟",
	"classmate":"👦 同学",
	"teacher":  "👨‍🏫 老师",
	"crush":    "💝 TA",
	"partner":  "💔 TA",
}
const NPC_VOICE := {
	"xiaoyou":  "excited",
	"xiaoyang": "happy",
	"mother":   "warm",
	"father":   "calm",
	"brother":  "casual",
	"classmate":"casual",
	"teacher":  "formal",
	"crush":    "shy",
}

const FESTIVAL_GREETINGS := {
	# 公历节日
	"01-01": ["新年快乐鸭！🎆", "今年也要一起玩！", "happy new year～"],
	"02-14": ["情人节快乐 💕", "今天是恋爱的日子～", "……你、你有没有喜欢的人啊"],
	"06-01": ["六一快乐！🎈", "今天可以装一天小孩！", "陪我去抓娃娃不"],
	"10-01": ["国庆快乐！🇨🇳", "放假七天耶！", "走，去哪儿玩？"],
	"12-24": ["平安夜快乐 🍎", "想要什么礼物～", "记得早点回家哦"],
	"12-25": ["圣诞快乐 🎄", "Merry Christmas！", "今年我想要的礼物是……"],
	# 农历节日
	"05-05": ["端午节快乐 🐲", "你吃粽子了吗～", "今天要吃咸的还是甜的！"],
	"07-07": ["七夕快乐 🌌", "……你今天有安排吗", "（小声）那个……"],
	"08-15": ["中秋快乐 🥮", "今天月亮好圆", "陪我一起看月亮吧"],
}

const BIRTHDAY_GREETINGS := [
	"生日快乐！！🎂",
	"祝你天天开心！",
	"今天要吃蛋糕哦！",
	"想要什么礼物？我买给你",
	"🎉🎉🎉",
	"今天你最大！",
]

# 给出（某 NPC + 某节日）的一句祝福
# 用法：get_greeting("xiaoyou", "02-14", "festival")
func get_greeting(npc_id: String, mm_dd: String, kind: String) -> String:
	var lines: Array = []
	if kind == "festival" and FESTIVAL_GREETINGS.has(mm_dd):
		lines = FESTIVAL_GREETINGS[mm_dd]
	elif kind == "birthday":
		lines = BIRTHDAY_GREETINGS
	if lines.is_empty():
		return "%s 节日快乐！" % NPC_DISPLAY.get(npc_id, npc_id)
	return lines[randi() % lines.size()]