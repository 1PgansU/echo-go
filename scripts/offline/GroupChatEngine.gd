# GroupChatEngine.gd — 群聊系统的大脑
"""
职责：
1. 群定义（成员、解锁条件）
2. 智能选话题（节日 / 玩家最近互动 / 剧情阶段 / 随机）
3. 生成群聊消息（模板驱动 + 玩家上下文）
4. 玩家发言后，群里 NPC 自动接话（可走 LLM）
5. 持久化（按群存档）

设计：模板 = "安全的、可控的底料"；LLM = "有灵魂的加料"
- 默认 80% 用模板
- 玩家主动说话后，那一轮 100% 走 LLM（让 NPC 真的"听到"玩家）
"""
extends Node

const NPCManager = preload("res://scripts/NPCManager.gd")
const FestivalCalendar = preload("res://scripts/offline/FestivalCalendar.gd")

static var _inst: Node = null
static func get_instance() -> Node:
	if _inst == null:
		var EngineScript = load("res://scripts/offline/GroupChatEngine.gd")
		_inst = EngineScript.new()
		_inst.name = "GroupChatEngine"
		var root = Engine.get_main_loop().get_root()
		if root:
			root.add_child(_inst)
	return _inst

const SAVE_PATH := "user://group_chat.json"

# === NPC 显示名 + 头像 ===
const NPC_DISPLAY := {
	"xiaoyou":  "🍊 小柚",
	"xiaoyang": "🐑 小羊",
	"mother":   "👩 妈妈",
	"father":   "👨 爸爸",
	"brother":  "👦 弟弟",
	"classmate":"🧑 同学",
	"teacher":  "👨‍🏫 老师",
	"crush":    "💝 TA",
	"partner":  "💔 TA",
}
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

# === 群定义 ===
# 4 个群，覆盖主要关系场景
const GROUPS := {
	"group_close": {
		"name": "🌸 闺蜜秘密基地",
		"members": ["xiaoyou", "crush", "xiaoyang"],  # 闺蜜+暗恋对象+发小
		"unlock_level": 3,
		"vibe": "girls_only_with_one_friend",  # 亲密+小八卦
	},
	"group_family": {
		"name": "👨‍👩‍👧‍👦 我们一家",
		"members": ["mother", "father", "brother"],
		"unlock_level": 2,
		"vibe": "family_daily",  # 家人日常
	},
	"group_class": {
		"name": "📚 高二三班",
		"members": ["classmate", "xiaoyang", "teacher"],
		"unlock_level": 1,
		"vibe": "school_life",  # 校园生活
	},
}

# === 话题库（按 vibe 分类）===
# 每个话题 = { 模板组: [msg1, msg2, ...], trigger_keywords: [...] }
# 消息模板用 %X 占位"玩家"
const TOPICS := {
	"family_daily": {
		"吃饭": {
			"lines": [
				"今天回家吃饭吗？",
				"给你做了糖醋排骨~",
				"我在外面吃了。",
				"给我留点！",
				"妈妈做的饭最好吃！",
			],
		},
		"作业": {
			"lines": [
				"今天作业多吗？",
				"不交扣分。",
				"作业是啥来着？",
				"我忘了……",
				"哥哥/姐姐帮我写！",
			],
		},
		"周末": {
			"lines": [
				"周末去哪儿玩？",
				"爬山？",
				"去公园吧。",
				"我想去电玩城！",
				"我要抓娃娃！",
			],
		},
		"节日": {
			"lines": [
				"节日快乐鸭！🎉",
				"今天要一起过！",
				"同乐同乐~",
				"今天谁请客？",
			],
		},
		"担心": {
			"lines": [
				"%X 怎么没说话？",
				"今天心情不好吗？",
				"是不是又熬夜了？",
				"给你留了饭。",
				"有事跟爸妈说啊。",
			],
		},
	},
	"girls_only_with_one_friend": {
		"日常": {
			"lines": [
				"诶嘿～今天好累啊。",
				"出来逛街吧！",
				"%X 应该有空。",
				"我问问。",
				"奶茶还是咖啡？",
				"我请！",
			],
		},
		"八卦": {
			"lines": [
				"诶诶诶？",
				"听说 X 和 Y 在一起了",
				"真的假的！",
				"我昨天看到了！",
				"在奶茶店！",
				"我居然不知道……",
			],
		},
		"游戏": {
			"lines": [
				"今晚开黑不？",
				"三缺一~",
				"我菜鸡别带我",
				"你才菜！",
				"今天被大佬带躺了",
				"截图截图！",
			],
		},
		"恋爱": {
			"lines": [
				"姐妹们！！！",
				"我有事要说！！！",
				"？？？",
				"快说！",
				"我好像",
				"喜欢上了一个人",
				"！",
			],
		},
		"学习": {
			"lines": [
				"作业写完没？",
				"明天要交。",
				"我刚抄完。",
				"……",
				"哼。",
				"不带你抄。",
			],
		},
		"节日": {
			"lines": [
				"节日快乐鸭！🎉",
				"今天要一起过！",
				"今天谁请客？",
				"诶嘿，我买了小蛋糕！",
			],
		},
		"心情": {
			"lines": [
				"%X 怎么没说话？",
				"是不是不开心？",
				"我陪你聊天！",
				"诶……抱抱你。",
				"没事没事！",
			],
		},
	},
	"school_life": {
		"作业": {
			"lines": [
				"作业借我抄一下！",
				"别闹。",
				"今天作业是啥？",
				"我也没写。",
			],
		},
		"考试": {
			"lines": [
				"下周考试范围已发。",
				"请认真复习。",
				"我没复习……",
				"帮帮我！",
			],
		},
		"通知": {
			"lines": [
				"明天开家长会。",
				"请通知家长。",
				"完了……",
				"我妈要打死我。",
			],
		},
		"校园": {
			"lines": [
				"食堂今天吃啥？",
				"听说新出了一个菜。",
				"我想吃辣！",
				"走走走吃饭。",
			],
		},
		"日常": {
			"lines": [
				"小卖部见！",
				"今天好累。",
				"放学走不走？",
				"一起走！",
			],
		},
		"节日": {
			"lines": [
				"节日快乐！",
				"今天放假吗？",
				"求放假！",
			],
		},
	},
}

# === 存档：每个群一本聊天记录 ===
# group_key → [{"speaker", "speaker_name", "msg", "ts", "by_player"}, ...]
var _chats: Dictionary = {}
# 已读进度：每个群最后已读消息数
var _unread: Dictionary = {}


func _ready() -> void:
	_load()


# === 群元信息 ===
func get_chat_groups() -> Dictionary:
	return GROUPS


func get_members(group_key: String) -> Array:
	return GROUPS.get(group_key, {}).get("members", [])


# 返回玩家加入等级（按关系矩阵的等级）
# - 闺蜜群 = Lv 3（小柚/小羊 Lv 3，但 crush 0，所以用综合最高）
# - 家庭群 = Lv 2
# - 班级群 = Lv 1
func get_unlock_level(group_key: String) -> int:
	return GROUPS.get(group_key, {}).get("unlock_level", 1)


# === 检查群是否解锁 ===
# 规则：群成员中至少 1 个 NPC 与玩家亲密度等级 ≥ unlock_level
func is_unlocked(group_key: String) -> bool:
	var matrix_script = load("res://scripts/offline/RelationshipMatrix.gd")
	var matrix = matrix_script.get_instance() if matrix_script else null
	if matrix == null:
		return true  # 兜底
	var unlock_lv: int = get_unlock_level(group_key)
	var members: Array = get_members(group_key)
	for m in members:
		var rel = matrix.pair(m, "partner")
		var pts: int = int(rel.get("points", 0))
		var lv: int = matrix.get_level_for_points(pts)
		if lv >= unlock_lv:
			return true
	return false


# === 智能选话题 ===
# 1. 看今天是不是节日 → 节日话题
# 2. 看剧情阶段（DramaEngine）
# 3. 看玩家最近跟谁互动 → 关系提示话题
# 4. 默认随机
func pick_topic_for_group(group_key: String) -> String:
	var group: Dictionary = GROUPS.get(group_key, {})
	var vibe: String = group.get("vibe", "family_daily")
	var pool: Dictionary = TOPICS.get(vibe, {})
	if pool.is_empty():
		return ""

	# === 节日优先 ===
	var fest = FestivalCalendar.get_instance()
	if fest:
		var today_str: String = Time.get_date_string_from_system()  # 2026-10-03
		var info: Dictionary = fest.check_today(today_str)
		if info.get("festival") != null or info.get("lunar") != null or info.get("birthdays", []).size() > 0:
			if pool.has("节日"):
				return "节日"

	# === 剧情阶段触发 ===
	# DramaEngine 不暴露单例/上下文 API；剧情阶段上下文后续通过外部传入或事件注入
	# 未来扩展时，把 act_id / stage 放到 _clock._state 里再读
	pass  # placeholder for future剧情集成

	# === 默认随机 ===
	var keys: Array = pool.keys()
	return keys[randi() % keys.size()]


# === 生成一段对话（不依赖 LLM，纯模板） ===
# 返回消息列表，每条 {speaker, speaker_name, msg}
func generate_conversation(group_key: String, topic: String, msg_count: int = -1) -> Array:
	var group: Dictionary = GROUPS.get(group_key, {})
	var members: Array = group.get("members", [])
	var vibe: String = group.get("vibe", "family_daily")
	var pool: Dictionary = TOPICS.get(vibe, {})
	var tpl: Dictionary = pool.get(topic, {})
	if tpl.is_empty() or members.is_empty():
		return []

	var lines: Array = tpl.get("lines", [])
	if msg_count < 0:
		msg_count = randi_range(4, 8)
	msg_count = min(msg_count, lines.size())

	# === 30% 概率走 LLM（让群聊像活的；否则模板拼接） ===
	var llm = Engine.get_main_loop().get_root().get_node_or_null("LLMClient")
	var use_llm_rate: float = 0.3  # 每条 30% 走 LLM
	var recent: Array = get_recent(group_key, 6)

	var out: Array = []
	for i in range(msg_count):
		var speaker: String = members[i % members.size()]
		var template_msg: String = str(lines[i]).replace("%X", "你")

		# 决定这条消息走 LLM 还是模板
		var msg: String = template_msg
		if llm and llm.has_method("send_message") and randf() < use_llm_rate:
			# 拼上下文给 LLM
			var role: String = ""
			if NPCManager.has_npc(speaker):
				role = NPCManager.get_personality_prompt(speaker)
			if role == "":
				role = "你是 %s。在微信群里聊天，请用你的性格特点简短回复。" % speaker
			var ctx: String = "你现在在「%s」群里。群里其他人: %s。\n" % [group.get("name", "群"), str(members)]
			ctx += "最近对话：\n"
			for m in recent:
				ctx += "- %s: %s\n" % [m.get("speaker_name", "?"), m.get("msg", "")]
			ctx += "本次话题：%s\n请按你人设用群里聊天的口吻发 1 句话（不超过 30 字）。" % topic
			# 异步调，但这里是同步流程——用简单 await 方案（仅 1 个 NPC 走 LLM，避免卡顿）
			var got_text: Array = [""]
			var cb: Callable = func(t: String) -> void:
				got_text[0] = t
			llm.call("generate_reply_async", speaker, role, ctx, cb)
			# 等几帧（最多 ~0.5 秒）
			var waited: int = 0
			while got_text[0] == null and waited < 10:
				await Engine.get_main_loop().process_frame
				waited += 1
			var llm_reply: String = str(got_text[0])
			if llm_reply != "" and llm_reply != "null" and llm_reply != "None" and llm_reply.length() > 0:
				msg = llm_reply

		out.append({
			"speaker": speaker,
			"speaker_name": NPC_DISPLAY.get(speaker, speaker),
			"avatar": NPC_AVATAR.get(speaker, "🙂"),
			"msg": msg,
			"by_player": false,
			"ts": Time.get_ticks_msec(),
		})
		# 把这条加入 recent，让下一条 NPC 看到上下文
		recent.append({"speaker_name": NPC_DISPLAY.get(speaker, speaker), "msg": msg})
	return out


# === 拿群聊的历史 ===
func get_history(group_key: String) -> Array:
	return _chats.get(group_key, [])


# === 加入消息（来自玩家 + NPC） ===
func append_message(group_key: String, msg: Dictionary) -> void:
	if not _chats.has(group_key):
		_chats[group_key] = []
	if not msg.has("ts"):
		msg["ts"] = Time.get_ticks_msec()
	_chats[group_key].append(msg)
	# 限制每群最多 200 条
	if _chats[group_key].size() > 200:
		_chats[group_key] = _chats[group_key].slice(_chats[group_key].size() - 200, 200)
	_save()


# === 取最近 N 条（倒序）===
func get_recent(group_key: String, n: int = 20) -> Array:
	var hist: Array = get_history(group_key)
	if hist.size() <= n:
		return hist
	return hist.slice(hist.size() - n, hist.size())


# === 未读 ===
func get_unread_count(group_key: String) -> int:
	var total: int = get_history(group_key).size()
	var last_read: int = int(_unread.get(group_key, 0))
	return max(0, total - last_read)


func mark_read(group_key: String) -> void:
	_unread[group_key] = get_history(group_key).size()
	_save()


# === 玩家发言后，让群里 NPC 自动回 1~2 句 ===
# 走 LLM：如果 LLM 客户端在线 → 每个 NPC 用其角色生成回复
# 否则退到模板拼接
func generate_replies_after_player(group_key: String, player_text: String) -> Array:
	var members: Array = get_members(group_key)
	if members.is_empty():
		return []
	var llm = Engine.get_main_loop().get_root().get_node_or_null("LLMClient")
	var recent: Array = get_recent(group_key, 10)

	# 选 1~2 个 NPC 回话
	var reply_count: int = randi_range(1, 2)
	var replies: Array = []
	var used: Array = []
	for i in range(reply_count):
		var available: Array = []
		for m in members:
			if not used.has(m):
				available.append(m)
		if available.is_empty():
			break
		var npc: String = available[randi() % available.size()]
		used.append(npc)

		var reply_text: String = ""
		# 优先 LLM
		if llm and llm.has_method("send_message"):
			# 拿 NPC 人设
			var role: String = ""
			if NPCManager.has_npc(npc):
				role = NPCManager.get_personality_prompt(npc)
			if role == "":
				role = "你是 %s。在微信群里聊天，请用你的性格特点简短回复。" % npc

			# 拼接上下文
			var ctx: String = "你现在在「%s」群里。群里其他人: %s。\n" % [GROUPS.get(group_key, {}).get("name", "群"), str(members)]
			ctx += "最近对话：\n"
			var tail: Array = recent.slice(max(0, recent.size() - 6))
			for m in tail:
				ctx += "- %s: %s\n" % [m.get("speaker_name", "?"), m.get("msg", "")]
			ctx += "\n玩家刚才说：\"%s\"\n请按你人设，用群里聊天的口吻回复 1-2 句话。不超过 60 字。语气：自然、有角色特色。" % player_text

			# 用 generate_reply_async（专用群聊回复，不附加"招呼语"任务覆盖）
			var capture_npc: String = npc
			var got_text: Array = [""]  # 等待 callback 填充
			var cb: Callable = func(t: String) -> void:
				got_text[0] = t
			llm.call("generate_reply_async", capture_npc, role, ctx, cb)
			# 等几帧让 callback 触发（最多 0.5 秒）
			var waited: int = 0
			while got_text[0] == null and waited < 10:
				await Engine.get_main_loop().process_frame
				waited += 1
			reply_text = str(got_text[0])
			if reply_text == "" or reply_text == "null" or reply_text == "None":
				reply_text = _fallback_reply(npc, player_text)

		# LLM 不可用 → 模板
		if reply_text == "":
			reply_text = _fallback_reply(npc, player_text)

		replies.append({
			"speaker": npc,
			"speaker_name": NPC_DISPLAY.get(npc, npc),
			"avatar": NPC_AVATAR.get(npc, "🙂"),
			"msg": reply_text,
			"by_player": false,
			"ts": Time.get_ticks_msec(),
		})
		# 加进 recent，下一个 NPC 才能"接住"
		recent.append({"speaker_name": NPC_DISPLAY.get(npc, npc), "msg": reply_text})

	return replies


# === 模板回话（无 LLM 时） ===
# 根据玩家文本的情绪/关键词 + NPC 性格匹配一句
func _fallback_reply(npc_id: String, player_text: String) -> String:
	var t: String = player_text.to_lower()

	# 关键词情绪
	var emotion: String = "default"
	if "难过" in t or "伤心" in t or "不开心" in t or "哭" in t or "郁闷" in t:
		emotion = "comfort"
	elif "开心" in t or "哈哈" in t or "高兴" in t or "爽" in t:
		emotion = "happy"
	elif "?" in player_text or "?" in player_text or "怎么" in t or "为什么" in t:
		emotion = "curious"
	elif "作业" in t or "学习" in t or "考试" in t:
		emotion = "study"
	elif "吃" in t or "饿" in t:
		emotion = "food"

	var replies: Dictionary = {
		"xiaoyou": {
			"comfort":  ["诶……抱抱你", "没事的没事的！", "诶……我陪你"],
			"happy":    ["诶嘿诶嘿～", "哈哈哈好好笑！", "哦吼~太棒了！"],
			"curious":  ["诶？然后呢然后呢？", "诶嘿？什么什么？"],
			"study":    ["我也写不完……", "诶……作业好难"],
			"food":     ["啊——好吃的！", "我也饿了！"],
			"default":  ["诶嘿～", "666！", "有点意思！"],
		},
		"xiaoyang": {
			"comfort":  ["没事儿，我反正就在这儿。", "......我在呢。", "谢什么谢，肉麻死了。"],
			"happy":    ["整挺好！", "哈哈哈笑死我了。", "哟~"],
			"curious":  ["什么？还有这种事呀？", "诶？怎么会这样！"],
			"study":    ["我也忘写了。", "哎哟……"],
			"food":     ["走走走，吃东西去！", "诶！烤肠！我要！"],
			"default":  ["诶嘿！", "哎哟~", "冲冲冲！"],
		},
		"mother": {
			"comfort":  ["别难过，妈在呢。", "有什么事跟妈说。", "给你做了好吃的。"],
			"happy":    ["看见你开心妈也开心。", "好~"],
			"curious":  ["什么事呀？", "怎么了？"],
			"study":    ["作业写完没？", "认真点。"],
			"food":     ["饭在锅里呢。", "今天做了你爱吃的。"],
			"default":  ["早点睡。", "多穿点。"],
		},
		"father": {
			"comfort":  ["（沉默地拍了下你肩膀）", "没事。"],
			"happy":    ["嗯。"],
			"curious":  ["嗯？"],
			"study":    ["好好读书。", "作业写完没。"],
			"food":     ["吃饭了没？"],
			"default":  ["嗯。", "早点睡。"],
		},
		"brother": {
			"comfort":  ["姐姐别哭！", "我陪你玩！"],
			"happy":    ["耶！", "嘿嘿嘿！"],
			"curious":  ["然后呢！", "什么什么？"],
			"study":    ["姐姐帮我写！", "我不要写作业！"],
			"food":     ["我要吃好吃的！", "姐姐给我做！"],
			"default":  ["姐姐姐姐！", "陪我玩！"],
		},
		"classmate": {
			"comfort":  ["诶，咋啦？", "别丧。"],
			"happy":    ["哈哈哈笑死我了。", "666！"],
			"curious":  ["啥？", "你没搞错？"],
			"study":    ["作业借我抄下！", "我也忘写。"],
			"food":     ["走，小卖部！", "食堂见。"],
			"default":  ["切~", "管好你自己。"],
		},
		"teacher": {
			"comfort":  ["我跟你说啊……", "有事找我。"],
			"happy":    ["嗯，不错。"],
			"curious":  ["什么事？"],
			"study":    ["要自觉。", "认真复习。"],
			"food":     ["别浪费粮食。"],
			"default":  ["嗯。", "知道了。"],
		},
		"crush": {
			"comfort":  ["……我不太确定。", "（微笑）"],
			"happy":    ["嗯嗯，开心就好。"],
			"curious":  ["嗯？"],
			"study":    ["加油。"],
			"food":     ["嗯。"],
			"default":  ["嗯……", "（微笑）"],
		},
		"partner": {
			"comfort":  ["……你变了。"],
			"happy":    ["你才开心？"],
			"curious":  ["你又想啥？"],
			"study":    ["……"],
			"food":     ["……"],
			"default":  ["你怎么又不回我消息了。", "你是不是不爱我了。"],
		},
	}

	var npc_pool: Dictionary = replies.get(npc_id, {})
	var pool: Array = npc_pool.get(emotion, npc_pool.get("default", ["嗯。"]))
	return pool[randi() % pool.size()]


# === 持久化 ===
func _save() -> void:
	var config = ConfigFile.new()
	config.set_value("data", "chats", _chats)
	config.set_value("data", "unread", _unread)
	var err = config.save(SAVE_PATH)
	if err != OK:
		push_warning("[GroupChatEngine] 存档失败: %s" % SAVE_PATH)


func _load() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	_chats = config.get_value("data", "chats", {})
	_unread = config.get_value("data", "unread", {})


func reset_all() -> void:
	_chats.clear()
	_unread.clear()
	_save()