# GroupChat.gd — NPC 之间在群里说话，玩家潜水观察
"""
"群"是一种特殊的对话形式：
- 多个 NPC 依次发言（不是 1 对 1）
- 玩家可以潜水（默认）或主动加入（按 P 发消息）
- 话题由"今天的奇遇 / 节日 / 某 NPC 触发"驱动
"""
extends Node

static var _inst: Node = null
static func get_instance() -> Node:
	if _inst == null:
		var EngineScript = load("res://scripts/offline/GroupChat.gd")
		_inst = EngineScript.new()
		_inst.name = "GroupChat"
		var root = Engine.get_main_loop().get_root()
		if root:
			root.add_child(_inst)
	return _inst

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
# NPC 头像（emoji 占位）
const NPC_AVATAR := {
	"xiaoyou":  "🍊",
	"xiaoyang": "🐑",
	"mother":   "👩",
	"father":   "👨",
	"brother":  "👦",
	"classmate":"🧑",
	"teacher":  "👨‍🏫",
	"crush":    "💝",
	"partner":  "💔",
}

# === 群组定义 ===
# 每个群有名字 + 成员 + 触发话题（按 sim 进度）
const GROUPS := {
	"best_friend": {
		"name": "🍊 闺蜜/兄弟群",
		"members": ["xiaoyou", "xiaoyang"],   # 小柚 + 小羊
		"unlock_level": 2,  # 玩家 Lv.2 就能加入
		"topics": ["日常", "游戏", "学习", "恋爱", "八卦"],
	},
	"family": {
		"name": "👨‍👩‍👧 一家亲",
		"members": ["mother", "father", "brother"],
		"unlock_level": 2,
		"topics": ["吃饭", "作业", "周末", "节日"],
	},
	"class": {
		"name": "📚 班级群",
		"members": ["classmate", "teacher"],
		"unlock_level": 1,
		"topics": ["作业", "考试", "通知"],
	},
	"crush_alone": {
		"name": "💝 1对1",
		"members": ["crush"],
		"unlock_level": 4,
		"topics": ["私密", "告白"],
	},
}

# === 群聊模板库（按话题分类）===
# 注意：GDScript const Array 元素只能是基础类型（String / int / Dictionary）
# 不能直接写 ("speaker", "msg1", "msg2") 这样的元组
# 所以改成"模板字典"，speaker 顺序由群成员顺序决定
const TOPIC_TEMPLATES := {
	"日常": [
		{"lines": ["今天好累啊", "出来逛街吧！", "TA 应该有空", "我问问", "奶茶还是咖啡？", "我请！"]},
		{"lines": ["我饿了", "走，吃啥？", "今天想吃辣的", "我也"]},
	],
	"游戏": [
		{"lines": ["今晚开黑不？", "三缺一", "我菜鸡别带我", "你才菜！", "今天被大佬带躺了", "截图截图！"]},
	],
	"学习": [
		{"lines": ["作业写完没？", "明天要交", "我刚抄完", "……", "哼", "不带你抄"]},
	],
	"恋爱": [
		{"lines": ["姐妹们！！！", "我有事要说！！！", "？？？", "快说", "我好像", "喜欢上了一个人", "！", "！", "！"]},
	],
	"八卦": [
		{"lines": ["听说 X 和 Y 在一起了", "真的假的", "我昨天看到了", "在奶茶店", "啊？？", "我居然不知道"]},
	],
	"吃饭": [
		{"lines": ["今天回家吃饭吗", "给你做了糖醋排骨", "我在外面吃了", "给我留点", "妈做的饭最好吃", "+1"]},
	],
	"作业": [
		{"lines": ["今天作业交了吗？", "不交扣分", "作业是啥来着", "我忘了"]},
	],
	"考试": [
		{"lines": ["下周考试范围已发", "请复习", "我没复习", "帮帮我"]},
	],
	"通知": [
		{"lines": ["明天开家长会", "请通知", "完了", "我妈要打死我"]},
	],
	"周末": [
		{"lines": ["周末去哪儿玩？", "爬山？", "去公园吧", "孩子们都爱去", "我想去电玩城", "我要抓娃娃"]},
	],
	"节日": [
		{"lines": ["节日快乐鸭！🎉", "今天要一起过！", "同乐同乐", "今天谁请客？"]},
	],
	"私密": [
		{"lines": ["那个……", "我有个事想跟你说", "其实……", "（打字中）"]},
	],
	"告白": [
		{"lines": ["我", "我好像", "喜欢你"]},
	],
}

# === 生成一段群聊 ===
# group_key: best_friend / family / class / crush_alone
# topic: 上面 TOPIC_TEMPLATES 的 key
# 模板里只有"消息文本列表"，说话人按群成员顺序轮换
func generate_conversation(group_key: String, topic: String) -> Array:
	var group: Dictionary = GROUPS.get(group_key, {})
	var templates: Array = TOPIC_TEMPLATES.get(topic, [])
	var members: Array = group.get("members", [])
	if members.is_empty() or templates.is_empty():
		return []

	# 随机选一个对话片段
	var idx: int = randi() % templates.size()
	var tpl: Dictionary = templates[idx]
	var raw_lines: Array = tpl.get("lines", [])

	var out: Array = []
	for i in range(raw_lines.size()):
		var msg: String = str(raw_lines[i])
		var speaker: String = members[i % members.size()] if not members.is_empty() else "xiaoyou"
		out.append({
			"speaker": speaker,
			"speaker_name": NPC_DISPLAY.get(speaker, speaker),
			"avatar": NPC_AVATAR.get(speaker, "🙂"),
			"msg": msg,
		})
	return out

# === 根据玩家进度和最近事件，决定"今天哪个群聊"
# 返回: { "group_key": ..., "topic": ..., "lines": [...] }
func roll_today_chat() -> Dictionary:
	# 检查玩家等级
	var matrix_script = load("res://scripts/offline/RelationshipMatrix.gd")
	var matrix = matrix_script.get_instance() if matrix_script else null
	var player_pts: int = 0
	if matrix:
		var rel = matrix.pair("xiaoyou", "partner")
		player_pts = int(rel.get("points", 0))
	var player_lv: int = matrix.get_level_for_points(player_pts) if matrix else 0

	# 候选群（玩家等级必须达到 unlock_level）
	var candidates: Array = []
	for k in GROUPS:
		if GROUPS[k].get("unlock_level", 0) <= player_lv:
			candidates.append(k)
	if candidates.is_empty():
		return {}

	# 选群（按"好友等级"加权）
	var group_key: String = candidates[randi() % candidates.size()]
	var group: Dictionary = GROUPS[group_key]
	# 选话题
	var topics: Array = group.get("topics", [])
	var topic: String = topics[randi() % topics.size()] if not topics.is_empty() else "日常"
	var lines: Array = generate_conversation(group_key, topic)
	return {
		"group_key": group_key,
		"group_name": group["name"],
		"topic": topic,
		"lines": lines,
	}