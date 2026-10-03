# DramaTemplates.gd — 事件模板库
# 几十种"两个 NPC 怎么互动"的可能性
# 每个模板是 (a 对 b 说话, b 回答, 然后可能再来一句)
# 实际产出还会让 LLM 润色
extends RefCounted

# 模板结构：
#   "id": 唯一名
#   "needs_type": 触发最低关系（"陌生"表示任何关系都可能）
#   "weight": 1.0 基准权重
#   "scenes": [ [a_acting, b_react], ... ]    ← 多轮剧本
#   "delta": 关系值变化范围
#   "tags": ["日常", "温情", "冲突", "浪漫", "搞笑", "成长", "运动", "吃货", "工作", "学习"]

const TEMPLATES: Array = [
	# === Lv.0 日常闲聊（任何关系都可能） ===
	{"id": "casual_chat", "needs_type": "陌生", "needs_level": 0, "weight": 1.0,
	 "scenes": [
		["%A 朝 %B 招手：「诶～」", "%B 抬头笑了笑：「哟，怎么了？」"],
		["%A 凑过去：「最近怎么样？」", "%B 耸耸肩：「还行吧，就那样。」"],
		["%A 递了瓶水过去：「渴不？」", "%B 接过来：「谢啦！」"]
	 ],
	 "delta": [1, 3], "tags": ["日常"]},

	# === Lv.0 一起运动 ===
	{"id": "play_ball", "needs_type": "陌生", "needs_level": 0, "weight": 0.7,
	 "scenes": [
		["%A 拍了拍篮球：「来一局？」", "%B 挑眉：「怕你啊？上！」"],
		["%A 在跑道边热身：「一起跑两圈？」", "%B 跟上：「冲啊。」"],
		["%A 拎着羽毛球拍晃了晃：「整不？」", "%B 笑：「必须整啊。」"]
	 ],
	 "delta": [2, 5], "tags": ["运动", "日常"]},

	# === 一起吃东西 ===
	{"id": "eat_together", "needs_type": "陌生", "needs_level": 0, "weight": 0.8,
	 "scenes": [
		["%A 拎着一袋小笼包：「哎，这个超好吃！」", "%B 眼睛亮了：「我尝尝我尝尝。」"],
		["%A 掏出两个冰棍：「来一根？」", "%B 接过来：「这么热的天，神仙啊！」"],
		["%A 在奶茶店门口招手：「快来，我请。」", "%B 笑：「真的假的，那我可不客气啦。」"]
	 ],
	 "delta": [2, 4], "tags": ["吃货"]},

	# === 求教/学东西 ===
	{"id": "teach_something", "needs_type": "熟人", "needs_level": 2, "weight": 0.6,
	 "scenes": [
		["%A 拿着课本：「这个题我不会，能教教我吗？」", "%B 凑过来：「来，我给你讲。」"],
		["%A 比划着动作：「这个舞步怎么跳啊？」", "%B 笑着演示：「你跟着我做——一二三。」"],
		["%A 举着手机：「哎，相机参数我不会调。」", "%B 接过手机：「看我的。」"]
	 ],
	 "delta": [3, 6], "tags": ["学习", "成长"]},

	# === 帮个小忙 ===
	{"id": "do_a_favor", "needs_type": "熟人", "needs_level": 2, "weight": 0.7,
	 "scenes": [
		["%A 抱着纸箱快走：「哎——能帮个忙不？」", "%B 赶紧跑过去：「来来来，给我一半。」"],
		["%A 在修东西：「扳手借我用下？」", "%B 递过去：「给。」"],
		["%A 拎着重物喘气：「等下——能搭把手吗？」", "%B 赶紧上去：「你怎么不早叫我！」"]
	 ],
	 "delta": [3, 7], "tags": ["温情"]},

	# === 一起打游戏 ===
	{"id": "play_game", "needs_type": "熟人", "weight": 0.7,
	 "scenes": [
		["%A 举起手机：「联机不？」", "%B 掏出另一只手机：「等我登录！」"],
		["%A 打开游戏：「上次那关我又没过。」", "%B 凑过去：「来，我带你飞。」"],
		["%A 在沙发上盘腿坐：「开黑开黑。」", "%B 笑：「等着被你坑呢。」"]
	 ],
	 "delta": [2, 5], "tags": ["日常", "搞笑"]},

	# === 听心事 / 安慰 ===
	{"id": "comfort", "needs_type": "朋友", "weight": 0.5,
	 "scenes": [
		["%A 沉默了一会儿：「……最近有点事。」", "%B 安静地坐过去：「想说说吗？我听着呢。」"],
		["%A 叹了口长气：「算了不说了。」", "%B 轻轻拍了拍 %A 的背：「没事，不急。」"],
		["%A 眼眶有点红：「没事没事……就是……」", "%B 轻轻递了张纸巾：「不急，慢慢说。」"]
	 ],
	 "delta": [5, 10], "tags": ["温情", "成长"]},

	# === 小吵 / 冲突 ===
	{"id": "small_fight", "needs_type": "熟人", "weight": 0.3,
	 "scenes": [
		["%A 叉着腰：「你到底咋想的啊！」", "%B 偏过头：「我就是这个意思，不服来辩！」"],
		["%A 哼了一声：「行吧行吧。」", "%B 也不服气：「行行行，都是我的错。」"],
		["%A 把手里的东西一放：「气死我了！」", "%B 别过脸去：「你才气人呢！」"]
	 ],
	 "delta": [-3, -1], "tags": ["冲突"]},

	# === 和好 ===
	{"id": "make_up", "needs_type": "熟人", "weight": 0.4,
	 "scenes": [
		["%A 犹豫了下：「……那个，昨天的我说的有点过了。」", "%B 摸了摸后脑勺：「我也是，别放心上。」"],
		["%A 递过去一罐可乐：「和好不？」", "%B 笑着接过来：「本来就没什么大事。」"],
		["%A 主动伸出手：「握个手？」", "%B 用力回握：「走，请你吃冰棍。」"]
	 ],
	 "delta": [2, 4], "tags": ["温情"]},

	# === 表白 / 暧昧 ===
	{"id": "confession", "needs_type": "暧昧", "weight": 0.2,
	 "scenes": [
		["%A 红了耳朵：「那个……我、我有句话想跟你说……」", "%B 抬头看 %A：「嗯？怎么了？」"],
		["%A 小声：「我好像……有点喜欢你。」", "%B 愣住：「……你认真的？」"]
	 ],
	 "delta": [5, 12], "tags": ["浪漫"]},

	# === 忘年交（家长 × 学生） ===
	{"id": "elder_younger", "needs_type": "熟人", "weight": 0.6,
	 "scenes": [
		["%A 在路边走，看到 %B 拎着很重的东西：「来来来，我帮你。」", "%B 笑着道谢：「哎，谢谢你啊。」"],
		["%A 在公园下棋，%B 路过凑过来：「这步怎么走？」", "%A 笑着教 %B：「看，这里。」"],
		["%A 在晾衣服，%B 跑过来帮忙：「搭把手？」", "%A 笑：「好孩子。」"]
	 ],
	 "delta": [3, 6], "tags": ["温情", "成长"]},

	# === 偷告状（搞笑） ===
	{"id": "snitch", "needs_type": "熟人", "weight": 0.2,
	 "scenes": [
		["%A 偷偷凑过去：「我跟你说啊，%X 刚才在……」", "%B 眼睛瞪大：「真的假的！」"],
		["%A 压低声音：「别告诉别人哦……但 %X 居然……」", "%B 噗嗤笑出声：「哈哈哈哈哈。」"]
	 ],
	 "delta": [1, 2], "tags": ["搞笑"]},

	# === 一起发呆/看天 ===
	{"id": "stare_sky", "needs_type": "陌生", "weight": 0.4,
	 "scenes": [
		["%A 坐在天台上，%B 走过来挨着坐下。", "两个人看着天，没说话，但也不觉得尴尬。"],
		["%A 和 %B 一起靠着栏杆看晚霞。", "%A 突然说：「你觉不觉得今天颜色特别好看？」", "%B 点点头：「嗯。」"]
	 ],
	 "delta": [2, 4], "tags": ["温情"]},

	# === 互相吐槽（不伤人的吐槽，年轻人之间） ===
	{"id": "tease", "needs_type": "朋友", "weight": 0.4,
	 "scenes": [
		["%A 笑：「你今天发型咋回事啊？」", "%B 翻白眼：「你呢？鸡窝？」"],
		["%A 模仿 %B 刚才的动作。", "%B 一把扑过去：「别学我！」"]
	 ],
	 "delta": [1, 3], "tags": ["搞笑"]},

	# === 突然送东西 ===
	{"id": "gift", "needs_type": "熟人", "weight": 0.3,
	 "scenes": [
		["%A 递过去一个小盒子：「给你，路上看到的，想起你。」", "%B 愣了下：「啊？……谢谢！」"],
		["%A 把自己做的点心塞给 %B：「尝尝，我自己做的。」", "%B 尝了一口：「好吃诶！」"]
	 ],
	 "delta": [3, 6], "tags": ["温情", "浪漫"]},

	# === 联机对战（游戏里打了一架） ===
	{"id": "game_versus", "needs_type": "熟人", "weight": 0.5,
	 "scenes": [
		["%A 放下手机：「三局两胜，来不来？」", "%B 笑：「输的人请奶茶啊。」"],
		["%A 战绩一刷新：「耶！」", "%B 不服：「再来一局！」"]
	 ],
	 "delta": [1, 4], "tags": ["搞笑", "运动"]},

	# === 帮家人办事 ===
	{"id": "family_errand", "needs_type": "熟人", "weight": 0.4,
	 "scenes": [
		["%A 拎着菜篮：「帮我拎一段路呗？」", "%B 接过菜篮：「行，顺路嘛。」"],
		["%A 跑过来：「哎，能帮我跟 %B 说一声不？」", "%C 点头：「行，我一会儿告诉他。」"]
	 ],
	 "delta": [2, 4], "tags": ["温情"]},

	# === 体育/比赛（看比赛/打比赛） ===
	{"id": "watch_sports", "needs_type": "熟人", "weight": 0.4,
	 "scenes": [
		["%A 举着望远镜：「诶诶诶，进了！！」", "%B 跟着跳起来：「漂亮！！」"],
		["%A 看着屏幕：「这球踢的……」，%B 拍了下大腿：「啊——！」"]
	 ],
	 "delta": [2, 4], "tags": ["运动", "日常"]},

	# === 找东西/问路（小事互动） ===
	{"id": "ask_way", "needs_type": "陌生", "weight": 0.5,
	 "scenes": [
		["%A 走过来：「请问 XX 怎么走啊？」", "%B 详细指路：「往前，再右转。」"],
		["%A 在地上找东西，%B 蹲下来：「你找啥？」", "%A：「我钥匙掉了……」"]
	 ],
	 "delta": [1, 2], "tags": ["日常"]},

	# === 雨天共伞 ===
	{"id": "share_umbrella", "needs_type": "熟人", "weight": 0.4,
	 "scenes": [
		["%A 没带伞，站在屋檐下发呆。", "%B 撑伞过来：「走吧，一起。」"],
		["%A 把自己伞往 %B 那边偏了偏：「你别淋到。」", "%B 笑：「你肩膀湿了诶。」"]
	 ],
	 "delta": [3, 5], "tags": ["温情", "浪漫"]},

	# === 深夜（失眠/聊天） ===
	{"id": "late_night", "needs_type": "朋友", "weight": 0.3,
	 "scenes": [
		["%A 发了条消息：「睡了吗？」", "%B 几乎是秒回：「没呢，怎么了？」"],
		["%A 和 %B 聊到凌晨三点，最后 %B 说：「睡吧，晚安。」"]
	 ],
	 "delta": [3, 5], "tags": ["温情"]},

	# === 撞见尴尬事 ===
	{"id": "awkward", "needs_type": "熟人", "weight": 0.3,
	 "scenes": [
		["%A 撞见 %B 在偷偷吃零食，两人对眼。", "%A 笑：「我什么都没看到。」", "%B 脸红：「……别告诉别人啊！」"],
		["%A 撞见 %B 在自言自语练习表白，场面一度非常尴尬。", "%A 假装没看到走过去。", "%B 抓狂：「啊——你怎么在这！！」"]
	 ],
	 "delta": [1, 3], "tags": ["搞笑"]},

	# === Lv.3 闺蜜级（needs_level=3）—— 只有朋友才解锁 ===
	{"id": "share_secret", "needs_type": "朋友", "needs_level": 3, "weight": 1.0,
	 "scenes": [
		["%A 拉 %B 到角落：「我跟你说个秘密……」", "%B 睁大眼睛：「真的假的！」"],
		["%A 抱着膝盖：「其实我最近有点迷茫……」", "%B 靠过去：「说说，我听着呢。」"]
	 ],
	 "delta": [5, 10], "tags": ["成长", "温情"]},

	{"id": "comfort_sad", "needs_type": "朋友", "needs_level": 3, "weight": 0.9,
	 "scenes": [
		["%A 看到 %B 眼眶红红的：「你……还好吗？」", "%B 抽了抽鼻子：「我没事……真的……」"],
		["%A 把纸巾递过去：「哭出来会好受点。」", "%B 接过纸巾，低头擦了擦眼角。"]
	 ],
	 "delta": [4, 8], "tags": ["温情"]},

	{"id": "bestie_makeup", "needs_type": "朋友", "needs_level": 3, "weight": 0.8,
	 "scenes": [
		["%A 拎着化妆包冲到 %B 家：「来，今天教你画个约会妆！」", "%B 眼睛亮了：「真的吗！快开始！」"],
		["%A 举起两支口红：「正红还是豆沙？」", "%B 纠结到抓头：「啊啊啊选不出来！」"]
	 ],
	 "delta": [3, 7], "tags": ["日常", "浪漫"]},

	# === Lv.4 灵魂级（needs_level=4）—— 闺蜜/兄弟才解锁 ===
	{"id": "love_confession_xiaoyou", "needs_type": "好朋友", "needs_level": 4, "weight": 1.2,
	 "scenes": [
		["%A 攥着手机冲到 %B 面前：「你懂吗我谈恋爱了！！！！」", "%B 一把抓住 %A 的肩膀：「谁！！是谁！！给我从实招来！！」"],
		["%A 把手机怼到 %B 脸上：「看聊天记录！！他跟我表白了！！」", "%B 看完深吸一口气：「我——靠——」"]
	 ],
	 "delta": [6, 12], "tags": ["浪漫", "成长"]},

	{"id": "midnight_talk", "needs_type": "好朋友", "needs_level": 4, "weight": 0.9,
	 "scenes": [
		["凌晨两点 %A 发来消息：「你睡了吗？」", "%B 秒回：「没，怎么了？」"],
		["%A 语音电话拨过来：「我睡不着……能陪我聊聊吗？」", "%B 接起电话：「说吧，我在。」"]
	 ],
	 "delta": [5, 10], "tags": ["温情", "成长"]},

	{"id": "major_decision", "needs_type": "好朋友", "needs_level": 4, "weight": 0.8,
	 "scenes": [
		["%A 把志愿表摊开：「你帮我看看……我该怎么选？」", "%B 认真看完：「我觉得你适合 XXX。」"],
		["%A 看着远方：「如果我跟家里说想……你说他们会不会同意？」", "%B 拍了拍 %A 的肩：「你想做就做，我支持你。」"]
	 ],
	 "delta": [6, 11], "tags": ["成长"]},

	# === Lv.5 灵魂伴侣（needs_level=5）—— 恋人级 ===
	{"id": "first_kiss", "needs_type": "恋人", "needs_level": 5, "weight": 0.5,
	 "scenes": [
		["%A 心跳加速：「那个……我可以……」", "%B 轻轻闭上眼睛，没说话。"],
		["%A 在月色下轻轻靠近 %B。", "%B 红着脸：「……笨蛋。」"]
	 ],
	 "delta": [8, 15], "tags": ["浪漫"]},

	{"id": "future_together", "needs_type": "恋人", "needs_level": 5, "weight": 0.6,
	 "scenes": [
		["%A 握着 %B 的手：「以后……我们一直这样好不好？」", "%B 点点头：「嗯，一直。」"],
		["%A 和 %B 并肩看夕阳：「等我们都七十岁了……还一起来这儿好不好？」", "%B 笑：「好，说定了。」"]
	 ],
	 "delta": [8, 15], "tags": ["浪漫", "成长"]},
]

# 根据 a/b 当前关系和性格，返回候选模板
# 按当前等级挑选模板
# current_level: 0~5（来自 RelationshipMatrix.get_level_for_points）
# 规则：只能选 needs_level <= current_level < needs_level + 2 的模板
#       （即每个等级只能看到"自己的 + 上一级"的事件，避免低级抽到顶级）
func pick_template_by_level(current_level: int) -> Dictionary:
	var candidates: Array = []
	for t in TEMPLATES:
		var needs_lv: int = int(t.get("needs_level", 0))
		# 等级门控：当前等级 >= 模板所需等级（解锁）
		if current_level < needs_lv:
			continue
		# 反避免：当前等级不能超过模板所需等级 + 1（防止 Lv.0 抽到 Lv.5）
		if current_level > needs_lv + 1:
			continue
		candidates.append(t)
	if candidates.is_empty():
		# 兜底：所有模板都不可用 → 用 needs_level=0 的
		for t in TEMPLATES:
			if int(t.get("needs_level", 0)) == 0:
				return t
		return TEMPLATES[0]
	# 加权随机
	var total_w: float = 0.0
	for t in candidates:
		total_w += float(t.get("weight", 1.0))
	var r: float = randf() * total_w
	var acc: float = 0.0
	for t in candidates:
		acc += float(t.get("weight", 1.0))
		if r <= acc:
			return t
	return candidates[0]

# 把模板里的 %A/%B/%X 替换成具体名字
func render(scene: String, name_a: String, name_b: String, name_c: String = "") -> String:
	var out: String = scene
	out = out.replace("%A", name_a)
	out = out.replace("%B", name_b)
	out = out.replace("%C", name_c if name_c != "" else name_b)
	out = out.replace("%X", name_a)  # 默认 %X = 别人
	return out

func _type_rank(t: String) -> int:
	match t:
		"恋人": return 6
		"暧昧": return 5
		"好朋友": return 4
		"朋友": return 3
		"熟人": return 2
		"点头之交": return 1
		_: return 0  # 陌生
