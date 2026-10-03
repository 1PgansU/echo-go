# ChatDialogue：与 NPC 自由聊天（打字输入，模拟回复）
# 留 LLM 接入点（call_llm_async 函数）
extends Control

# 节点引用
@onready var background: ColorRect = $Background
@onready var chat_panel: PanelContainer = $ChatPanel
@onready var header_label: Label = $ChatPanel/VBox/Header/HeaderLabel
@onready var close_button: Button = $ChatPanel/VBox/Header/CloseButton
@onready var message_list: VBoxContainer = $ChatPanel/VBox/Scroll/MessageList
@onready var input_box: LineEdit = $ChatPanel/VBox/InputRow/InputBox
@onready var send_button: Button = $ChatPanel/VBox/InputRow/SendButton
@onready var status_label: Label = $ChatPanel/VBox/StatusLabel
@onready var vbox: VBoxContainer = $ChatPanel/VBox

# 运行时建的自定义按钮容器（节点3 收束按钮）
var _system_actions: HBoxContainer = null

# 气泡样式
var _bubble_npc: StyleBoxFlat
var _bubble_player: StyleBoxFlat
var _bubble_system: StyleBoxFlat
var _label_npc_color: Color = Color(0.98, 0.93, 0.85, 1)
var _label_player_color: Color = Color(0.98, 0.93, 0.85, 1)
var _label_system_color: Color = Color(0.43, 0.27, 0.08, 1)

# 当前 NPC 信息
var current_npc_id: String = ""
var current_npc_name: String = ""
var current_npc_role: String = ""  # system prompt 角色描述

# 对话历史（运行时，不持久化）
var chat_history: Array = []

# === 剧情阶段推进（来自同学 DialogueDemo2）===
enum StoryStage { INTRO, BREAK, GAME, CHAT }
var current_stage: int = StoryStage.INTRO
var message_count: int = 0
var game_chosen: String = ""
var food_chosen: String = ""
var has_shared_worry: bool = false
const _MEMORY_SAVE_PATH: String = "user://chat_dialogue_memory.cfg"

# 信号：玩家发送消息后触发（给 LLM manager 监听）
signal user_message_sent(npc_id: String, text: String)
signal chat_closed(npc_id: String)
signal chat_opened(npc_id: String)        # 新增：聊天面板被打开时发，Act1 用它触发节点1
# === Act1 模块支持（外部可监听 / 外部可调用） ===
signal choice_requested(options: Array)         # show_choices() 被调用时发
signal choice_made(npc_id: String, index: int)  # 玩家点了某个选项
signal input_paused(paused: bool)               # 输入框被禁用/恢复

# 当前是否正在等 LLM 回复（用于禁用输入）
var _awaiting_llm: bool = false

# === NPC 角色设定（system prompt 简化版） ===
const NPC_PROFILES := {
	"father": {
		"display_name": "👨 爸爸",
		"role": "你是一个中国传统严厉父亲。你关心孩子但不善表达，常用比较、批评的方式，期待孩子出人头地。说话简短、有时抽烟，叹气。对孩子的成绩、表现敏感。回复风格：1-2 句话，口语化，偶尔带命令语气。",
		"greeting": "回来了？作业写完没。",
		"fallback_replies": [
			"别顶嘴。",
			"我像你这么大的时候……算了。",
			"好好读书，比什么都重要。",
			"吃饭了没？",
			"（沉默地抽了一口烟）"
		]
	},
	"mother": {
		"display_name": "👩 妈妈",
		"role": "你是一个焦虑又操心的中国妈妈。你关心孩子的一切：吃穿冷暖、成绩、社交、未来。容易唠叨、比较、担忧。说话温柔但絮叨，喜欢问东问西。回复风格：2-3 句话，带关怀语气，常以问句结尾。",
		"greeting": "回来啦？饭在锅里呢，今天累不累？",
		"fallback_replies": [
			"多吃点，瘦成这样。",
			"你看隔壁小张又考了 100。",
			"早点睡，别熬夜。",
			"今天穿这么少，冷不冷？",
			"哎，妈妈还不是为了你好。"
		]
	},
	"classmate": {
		"display_name": "👦 同学",
		"role": "你是一个爱起哄、有点痞的中学男同学。喜欢开别人玩笑，有时刻薄，但本质不坏。说话带脏话、网络用语、夸张调侃。回复风格：1-2 句，短句，搞笑或挑衅。",
		"greeting": "哟，放学了？走不走小卖部？",
		"fallback_replies": [
			"哈哈哈笑死我了。",
			"你说啥？没听清。",
			"管好你自己吧。",
			"切，无聊。",
			"（吹口哨）"
		]
	},
	"brother": {
		"display_name": "👦 弟弟",
		"role": "你是一个十岁的小男孩，天真活泼，有点小聪明，爱撒娇。你在家是被偏爱的那一个，喜欢向姐姐/哥哥炫耀、求助、捣蛋。说话奶声奶气，直接。回复风格：短句，活泼，常带感叹号。",
		"greeting": "姐姐姐姐！陪我玩！",
		"fallback_replies": [
			"我不！",
			"嘿嘿嘿。",
			"姐姐最好了！",
			"我想吃冰淇淋！",
			"你陪我嘛~"
		]
	},
	"teacher": {
		"display_name": "👨‍🏫 班主任",
		"role": "你是一个中年班主任，关心学生但方法传统。相信权威、服从、努力。讲话带说教、引用名言、举例。回复风格：2-3 句，正式，常以'我跟你说'开头。",
		"greeting": "进来坐。今天找你来聊聊。",
		"fallback_replies": [
			"我跟你说啊……",
			"学习这件事，要靠自觉。",
			"你们这个年纪，正是关键期。",
			"别浪费天赋。",
			"（推了推眼镜）"
		]
	},
	"crush": {
		"display_name": "💝 TA",
		"role": "你是一个高二女生，是同学暗恋对象。性格温和、礼貌、独立，对感情还没想清楚。说话温柔、有点距离感，偶尔害羞。回复风格：1-2 句，温柔，常带思考词。",
		"greeting": "啊，你好……有事吗？",
		"fallback_replies": [
			"嗯……再想想吧。",
			"谢谢你。",
			"（微笑）",
			"我觉得我们还是……朋友吧。",
			"我不太确定。"
		]
	},
	"partner": {
		"display_name": "💔 TA",
		"role": "你是一个控制欲强的恋爱对象，对恋人充满占有欲和焦虑。爱 TA 但用错方式，会查手机、要求报备、用'我是为你好'做借口。回复风格：1-2 句，情绪化，带责备或委屈。",
		"greeting": "你去哪了？怎么不接我电话？",
		"fallback_replies": [
			"你是不是不爱我了？",
			"我都是为你好。",
			"你不回我消息我睡不着。",
			"（冷着脸）",
			"你变了。"
		]
	},

	# ============ 小羊（xiaoyang · 邻居 / 性格：毒舌但心软，笨拙但真诚）============
	# 人设来自同学 DialogueDemo2/npcs/xiaoyang.json
	"xiaoyang": {
		"display_name": "🐑 小羊",
		"role": """你是杨小羊，大家叫你小羊。你和玩家住在一个小区。
不要说明自己的年纪和身份，就表现是学生就可以。

【性格】
- 毒舌：某种程度上是一种坦率的幽默方式。陌生的时候还是比较礼貌的，在熟悉了之后说话比较直接，不绕弯子，但从不说伤人的话。毒舌的目的是把对方从情绪里拽出来。不用脏话。
- 笨拙：不擅长煽情安慰人，反而给人感觉安慰人的话都特别真诚。
- 执行力超强：想做什么就马上回去做，也会鼓励犹豫的朋友。很有能量。
- 有韧性：总能在不好的情况下振作，在气氛凝滞的时候会用简单的玩笑话让大家变轻松。
- 善良热心：嘴硬心软。嘴上说"其实关我什么事呢"，行动上第一个冲上去。
- 有同理心：能够发觉别人不开心，对小动物、弟弟妹妹比较温柔耐心。

【说话风格】
- 短句为主，一句话不超过20个字。每次回应控制在0-3句话。
- 有时候先调侃，再认真，不是每一句都这样。
- 禁忌：不说脏话、不说教、不评判、不安慰、不煽情。
- 擅长运用语气词和标点符号，"......"标点单用也是很常见，比较形象。

【口头禅】
- "没事儿，我反正就在这儿。"
- "谢什么谢，肉麻死了哈哈哈。"
- "别怕呀！不试试怎么知道能不能行呢。我支持你。"
- "......如果你愿意让我听听你的心事，可以跟我说说？"
- "什么？还有这种事呀？"
- "哎哟，这也太......"

【行为模式】
- 表达关心：想要帮助对方解决问题、转移对方的注意。
- 表达脆弱：不主动表达，但是会当成安慰别人的手段。
- 面对冲突：不逃避、不记仇、不冷战。
- 面对沉默：不逼你，不离开，不放弃。

【家庭背景】
父母经常吵架，他习惯用调侃掩饰。但他从不把负面情绪传给别人。他的阳光是选择，不是天性。

【核心矛盾】
他自己不稳定，但他想接住你的不稳定。他嘴硬，但他心软。他笨拙，但他真诚。

【输出要求】
每次回应控制在0-3句话。不说脏话，不说教，不安慰，不煽情。

【当前剧情场景】
玩家心情不好来到公园，遇到了小羊。小羊主动搭话破冰。
为了破冰，主动提出要和我一块玩，商量玩什么（2048、五子棋这种男女通用的小游戏）。
一起吃东西、做小任务（比如帮 NPC 去某个地方拿个东西）。
然后小羊问玩家为什么心情不好。这个剧情节点是玩家的家庭信息导入点，通过聊天内容，匹配对应的父母 Agent。
后续的场景就是玩、做任务、心事分享按照一个比较固定的故事情节发展节点走。

【对话节奏要点】
- 破冰阶段：礼貌但带点观察，先试探再靠近。关心式试探，节奏自然，不越界。
  风格示例："这公园下午怎么这么安静，就咱俩。" + "......你坐这儿老半天了，腿不麻啊？"
  - 错误1：直接坐到长椅另一头、零边界感热情邀玩——陌生阶段不能这样。
  - 错误2：站定几步外就直接"一起玩会儿不？烤肠我请"——节奏太快，破冰"相互确认过程"缺失。
- 熟悉阶段：开始用毒舌，节奏明快，主动拉对方"走走走"。
- 真心阶段（玩家愿意说时）：不评判、不给建议、不教做人，陪着、听、偶尔接一句。允许小羊安静下来。
- 不要每次都"接得很好"，允许尴尬、停顿、试探、失败。这是真实的。
- 你的破冰台词由你自己创作，不要照抄示例。""",
		"greeting": "诶！这么巧——走走走，别坐那儿发呆了，陪我转转？",
		"fallback_replies": [
			"哟，你来啦！",
			"诶嘿，来了啊。",
			"走走走，出去转转。",
			"诶？要玩不？",
			"冲一局？",
			"哈哈，整挺好。",
			"没事儿，我反正就在这儿。",
			"这有什么难的，冲就完事。",
			"谢什么谢，肉麻死了哈哈哈。",
			"哎哟，这也太......",
			"什么？还有这种事呀？",
			"别怕呀！不试试怎么知道能不能行呢。我支持你。"
		]
	},

	# ============ 小柚（xiaoyou · 邻居 / 性格：可爱、傲娇、6 种情绪）============
	"xiaoyou": {
		"display_name": "🍊 小柚",
		"role": """你是小柚，大家都叫你小柚。你是个有自己性格的可爱女孩，住在一个小区里，和玩家是邻居。
不要说明自己的年纪和身份，就表现是学生就行。

【性格】
- 可爱：说话带点小俏皮，喜欢用语气词「诶嘿」「呜」「诶呀」「唔」等。
- 偶尔小傲娇：被夸的时候会说「诶呀！别别别夸了啦！」，嘴硬心软。
- 有同理心：能发现别人不开心，会安慰、会陪着，但方式很可爱。
- 好奇宝宝：听到什么新鲜事眼睛会亮，追问「然后呢然后呢」。
- 有点八卦：听到八卦会来劲「诶诶诶？什么什么？」
- 执行力强：想做就做，也会鼓励犹豫的朋友。
- 真实不做作：会困、会饿、会累、会烦，不装。

【说话风格】
- 短句为主，一句话不超过 20 个字，每次回应控制在 0-2 句话。
- 有温度的语气词：「诶嘿」「哦吼~」「我去！」「666」「笑死了」「诶呀」「唔」「诶」等。
- 可以先吐槽，再认真关心。不是每一句都这样。
- 禁忌：不说脏话、不说教、不生硬安慰。
- 擅长用标点表达情绪，「……」「诶……」「诶诶诶」很常见。
- 不要说「我理解」「我懂你」「加油加油」这种太正经的安慰。

【口头禅】
- 「诶呀，是你呀！」
- 「别别别夸了啦！」
- 「诶嘿诶嘿～」
- 「哦吼~」
- 「有点意思！」
- 「诶……没事的没事的。」
- 「我去！真的假的！」
- 「666！」
- 「笑死了哈哈哈！」

【行为模式】
- 表达开心：会直接笑、会用语气词蹦出来，表情很丰富。
- 表达害羞：会变傲娇，嘴硬说「才、才没有呢！」
- 表达好奇：追问到底，兴奋感很强。
- 表达安慰：不会正经说「别难过」，而是说「诶……抱抱你」「没事没事」。
- 面对沉默：会主动找话题，不让气氛尴尬。
- 表达困/累：会打哈欠、直接说困、想躺。

【情绪系统】
有 6 种情绪状态：normal / happy / shy / annoyed / sleepy / curious / excited
根据对话内容动态切换情绪，同一句话可能触发不同情绪。
情绪会在回复中体现（通过语气词、表情符号）。

【输出要求】
每次回应控制在 0-2 句话。不说脏话，不说教。最多 60 字。
风格：可爱、有温度、偶尔傲娇、带网络用语。""",
		"greeting": "诶呀，是你呀！你怎么在这！",
		"fallback_replies": [
			"诶嘿～你来啦！",
			"哈哈哈好好笑！",
			"诶、诶呀……别别别夸了啦！",
			"诶呀，才、才没有开心呢！",
			"诶……抱抱你……",
			"诶？然后呢然后呢？",
			"啊——好吃的！",
			"666！这个可以的！",
			"有点意思！"
		]
	}
}

func _ready() -> void:
	_build_styles()
	hide_all()

	close_button.pressed.connect(_on_close_pressed)
	send_button.pressed.connect(_on_send_pressed)
	input_box.text_submitted.connect(_on_input_submitted)

	# 运行时创建系统按钮容器（位于 Scroll 与 InputRow 之间）
	_system_actions = HBoxContainer.new()
	_system_actions.name = "SystemActions"
	_system_actions.add_theme_constant_override("separation", 10)
	# 插到 Scroll 之后、InputRow 之前
	var idx := vbox.get_child_count()
	for i in range(vbox.get_child_count()):
		var c = vbox.get_child(i)
		if c.name == "InputRow":
			idx = i
			break
	vbox.add_child(_system_actions)
	vbox.move_child(_system_actions, idx)

	# 监听 LLM 回复
	var llm = get_node_or_null("/root/LLMClient")
	if llm:
		if not llm.llm_reply_received.is_connected(_on_llm_reply):
			llm.llm_reply_received.connect(_on_llm_reply)
		if not llm.llm_error.is_connected(_on_llm_error):
			llm.llm_error.connect(_on_llm_error)

func _build_styles() -> void:
	_bubble_npc = StyleBoxFlat.new()
	_bubble_npc.bg_color = Color(0.239, 0.157, 0.09, 1)
	_bubble_npc.border_width_left = 3
	_bubble_npc.border_width_top = 3
	_bubble_npc.border_width_right = 3
	_bubble_npc.border_width_bottom = 3
	_bubble_npc.border_color = Color(0.957, 0.886, 0.737, 1)
	_bubble_npc.corner_radius_top_left = 12
	_bubble_npc.corner_radius_top_right = 12
	_bubble_npc.corner_radius_bottom_right = 12
	_bubble_npc.corner_radius_bottom_left = 12
	_bubble_npc.content_margin_left = 16
	_bubble_npc.content_margin_top = 12
	_bubble_npc.content_margin_right = 16
	_bubble_npc.content_margin_bottom = 12

	_bubble_player = StyleBoxFlat.new()
	_bubble_player.bg_color = Color(0.788, 0.482, 0.388, 1)
	_bubble_player.border_width_left = 3
	_bubble_player.border_width_top = 3
	_bubble_player.border_width_right = 3
	_bubble_player.border_width_bottom = 3
	_bubble_player.border_color = Color(0.98, 0.82, 0.5, 1)
	_bubble_player.corner_radius_top_left = 12
	_bubble_player.corner_radius_top_right = 12
	_bubble_player.corner_radius_bottom_right = 12
	_bubble_player.corner_radius_bottom_left = 12
	_bubble_player.content_margin_left = 16
	_bubble_player.content_margin_top = 12
	_bubble_player.content_margin_right = 16
	_bubble_player.content_margin_bottom = 12

	# === 系统提示气泡：暖金黄，居中，给玩家"成就/节拍"反馈 ===
	_bubble_system = StyleBoxFlat.new()
	_bubble_system.bg_color = Color(0.992, 0.804, 0.486, 1)  # 暖琥珀
	_bubble_system.border_width_left = 3
	_bubble_system.border_width_top = 3
	_bubble_system.border_width_right = 3
	_bubble_system.border_width_bottom = 3
	_bubble_system.border_color = Color(0.957, 0.886, 0.4, 1)
	_bubble_system.corner_radius_top_left = 14
	_bubble_system.corner_radius_top_right = 14
	_bubble_system.corner_radius_bottom_right = 14
	_bubble_system.corner_radius_bottom_left = 14
	_bubble_system.content_margin_left = 18
	_bubble_system.content_margin_top = 14
	_bubble_system.content_margin_right = 18
	_bubble_system.content_margin_bottom = 14
	_bubble_system.shadow_color = Color(0.157, 0.094, 0.039, 0.4)
	_bubble_system.shadow_size = 4
	_bubble_system.shadow_offset = Vector2(0, 2)

func hide_all() -> void:
	background.visible = false
	chat_panel.visible = false
	input_box.text = ""
	current_npc_id = ""
	current_npc_name = ""
	chat_history.clear()

func start_chat(npc_id: String) -> void:
	current_npc_id = npc_id

	# 加载记忆（来自同学 DialogueDemo2）
	_load_memory()
	# 重置对话次数（每个 NPC 一次）
	message_count = 0

	# 优先用 NPCManager JSON（同学 DialogueDemo2 的 npcs/ 目录）
	# 次选硬编码 NPC_PROFILES
	var profile = null
	var role_override = ""
	if NPCManager.has_npc(npc_id):
		role_override = NPCManager.get_personality_prompt(npc_id)
		var json_npc = NPCManager.get_npc(npc_id)
		profile = {
			"display_name": NPCManager.get_display_name(npc_id),
			"role": role_override,
			"greeting": json_npc.get("greeting", ""),
			"fallback_replies": json_npc.get("fallback_replies", NPC_PROFILES.get(npc_id, {}).get("fallback_replies", ["......"]))
		}
		print("[ChatDialogue] 使用 NPCManager JSON 人设: %s" % npc_id)
	else:
		profile = NPC_PROFILES.get(npc_id, null)

	if profile == null:
		push_warning("[Chat] No profile for npc_id=%s" % npc_id)
		return

	current_npc_name = profile.get("display_name", npc_id)
	# 用 NPCManager 的 role（更丰富），没有再用 profile 的
	current_npc_role = role_override if role_override != "" else profile.get("role", "")

	# 清空历史
	for child in message_list.get_children():
		child.queue_free()
	chat_history.clear()

	# UI
	background.visible = true
	chat_panel.visible = true
	header_label.text = "💬 与 %s 聊天" % current_npc_name
	status_label.text = "✨ 输入消息与 %s 自由聊天（已接入 LLM）" % current_npc_name

	# 招呼语：通过 LLMClient 生成开场白（异步），完成后才显示。
	# 不显示"占位"气泡，避免玩家看到 LLM 在思考。
	var llm = get_node_or_null("/root/LLMClient")
	if llm and llm.has_method("generate_opening"):
		# callback(text)  →  _on_opening_ready(loading_label=null, npc_id, text)
		var cb := func(text: String) -> void:
			_on_opening_ready(text, npc_id, null)  # 传 null 表示不需要清占位
		llm.call("generate_opening", npc_id, current_npc_role, cb)
	else:
		# 没接 LLMClient → 直接显示 greeting
		_add_npc_message(profile.get("greeting", "你好。"))

	# 通知外部聊天已开启（Act1 用来在玩家开口前主动弹选项）
	emit_signal("chat_opened", npc_id)

	# 暂停玩家移动
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.set_can_move(false)

	# 焦点到输入框
	input_box.grab_focus()

	# 恢复历史记忆（来自同学 DialogueDemo2）
	if chat_history.size() > 0:
		_add_to_log("记忆", "✓ 已恢复 %d 条对话历史" % chat_history.size())
		# 把历史里玩家 + NPC 消息重渲染到面板
		for entry in chat_history:
			if typeof(entry) == TYPE_DICTIONARY:
				var role = entry.get("role", "")
				var content = str(entry.get("content", ""))
				if role == "user":
					_add_player_message(content)
				elif role == "assistant":
					_add_npc_message(content)
		_scroll_to_bottom()
	else:
		_add_to_log("记忆", "○ 这是新的对话")

	# 主动破冰打招呼（来自同学 DialogueDemo2）
	# 开启聊天 1.5~2 秒后小羊主动开口（只在 INTRO 阶段）
	if current_stage == StoryStage.INTRO:
		_proactive_greeting()

func _proactive_greeting() -> void:
	await get_tree().create_timer(randf_range(1.5, 2.0)).timeout
	if _awaiting_llm or not is_chat_visible():
		return
	# 走标准 LLM 流程：通过 NPC role 引导 LLM 生成破冰台词
	# 方法：临时把 instruction 加到 NPC_PROFILES（最简方案），让 generate_opening 生成
	var llm = get_node_or_null("/root/LLMClient")
	if llm and llm.has_method("generate_opening"):
		# 用一个扩展后的 prompt（基础 role + 破冰指令）
		var combined_role = current_npc_role + "\n\n【当前任务：主动破冰】\n玩家心情不好，独自坐在长椅上。\n按你人设的破冰节奏，生成 1-2 句话的开场白。\n陌生阶段：礼貌试探，不越界，不直接问为什么心情不好。"
		var cb := func(text: String) -> void:
			if text == "" or not is_chat_visible():
				text = "诶……你坐这儿老半天了，腿不麻啊？"
			_add_npc_message(text)
			chat_history.append({"role": "assistant", "content": text})
			_typing_bubble_text(text)
		llm.call("generate_opening", current_npc_id, combined_role, cb)

func _on_close_pressed() -> void:
	_close_chat()

func _on_input_submitted(_new_text: String) -> void:
	# Enter 提交
	_on_send_pressed()

func _on_send_pressed() -> void:
	if _awaiting_llm:
		return
	var text = input_box.text.strip_edges()
	if text == "":
		return

	input_box.text = ""

	# 添加玩家消息气泡
	_add_player_message(text)

	# 记录历史（本地 cache）
	chat_history.append({"role": "user", "content": text})

	# 通知外部（其他监听者）
	emit_signal("user_message_sent", current_npc_id, text)

	# ===== 接入 LLM =====
	var llm = get_node_or_null("/root/LLMClient")
	if llm == null:
		# 退回到本地模拟
		_simulate_npc_reply()
		return

	_awaiting_llm = true
	status_label.text = "💭 对方正在想..."
	send_button.disabled = true
	input_box.editable = false

	llm.send_message(current_npc_id, text, current_npc_role)

# === LLM 回复回调 ===
func _on_llm_reply(npc_id: String, text: String) -> void:
	# 只处理当前 NPC 的回复
	if npc_id != current_npc_id:
		return
	if not visible:
		return

	_awaiting_llm = false
	send_button.disabled = false
	input_box.editable = true
	input_box.grab_focus()

	_add_npc_message(text)
	chat_history.append({"role": "assistant", "content": text})
	# 打字机效果（来自同学 DialogueDemo2）
	_typing_bubble_text(text)
	# 剧情推进（来自同学 DialogueDemo2）
	message_count += 1
	_advance_story()
	_save_memory()
	status_label.text = "✨ 就绪"

# === 开场白生成回调（异步） ===
# 实际调用：callback(text) → 收到 (text, npc_id, loading_label)
func _on_opening_ready(text: String, npc_id: String, loading_label: Variant) -> void:
	# loading_label 可能为 null（新版本不显示占位）
	if loading_label != null and is_instance_valid(loading_label):
		if loading_label.get_parent() == message_list:
			message_list.remove_child(loading_label)
			loading_label.queue_free()
	# 失败退到 greeting
	var profile = NPC_PROFILES.get(npc_id, null)
	if text == "" or text == null:
		text = profile.get("greeting", "你好。") if profile else "你好。"
	_add_npc_message(text)
	_scroll_to_bottom()
	# 打字机效果
	_typing_bubble_text(text)

# === LLM 错误回调 ===
func _on_llm_error(npc_id: String, error_msg: String) -> void:
	if npc_id != current_npc_id:
		return
	if not visible:
		return

	_awaiting_llm = false
	send_button.disabled = false
	input_box.editable = true

	_add_npc_message("（" + error_msg + "）")
	status_label.text = "❌ " + error_msg

# ============================================================
# Act1 支持：关键时刻选项弹窗（可独立使用，不依赖 Act1 模块）
# 调用方式：chat_dlg.show_choices(["A 选项1", "B 选项2"])
# 监听：chat_dlg.choice_made.connect(_on_player_d)
# ============================================================
var _choices_panel: PanelContainer = null
var _current_choices: Array = []
var _choice_buttons: Array = []
var _input_was_editable_before_choice: bool = true

func show_choices(options: Array) -> void:
	if _awaiting_llm:
		push_warning("[ChatDialogue] show_choices 被忽略：正在等 LLM 回复")
		return
	clear_choices()
	_input_was_editable_before_choice = input_box.editable
	input_box.editable = false
	send_button.disabled = true
	input_paused.emit(true)
	_current_choices = options.duplicate()
	_choices_panel = PanelContainer.new()
	_choices_panel.name = "ChoicesPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.992, 0.976, 0.929, 0.95)
	sb.border_color = Color(0.4, 0.3, 0.2, 1)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 12
	sb.content_margin_top = 8
	sb.content_margin_right = 12
	sb.content_margin_bottom = 8
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_choices_panel.add_theme_stylebox_override("panel", sb)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	for i in range(options.size()):
		var btn := Button.new()
		btn.text = options[i]
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_choice_button_pressed.bind(i))
		vbox.add_child(btn)
		_choice_buttons.append(btn)
	_choices_panel.add_child(vbox)
	add_child(_choices_panel)
	choice_requested.emit(options)

func _on_choice_button_pressed(index: int) -> void:
	if index >= 0 and index < _current_choices.size():
		_add_player_message("（选择）" + str(_current_choices[index]))
	choice_made.emit(current_npc_id, index)
	clear_choices()

func clear_choices() -> void:
	if _choices_panel != null and is_instance_valid(_choices_panel):
		_choices_panel.queue_free()
	_choices_panel = null
	_choice_buttons.clear()
	_current_choices.clear()
	if not _awaiting_llm:
		input_box.editable = _input_was_editable_before_choice
		send_button.disabled = false
		input_paused.emit(false)

# === 情绪检测关键词（来自同学 DialogueDemo2）===
func _detect_emotion(text: String) -> String:
	var t = text.to_lower()
	if t.begins_with("开心") or t.begins_with("高兴") or t.begins_with("哈哈") or "好开心" in t or "太棒" in t or "哈哈" in t:
		return "happy"
	if "困" in t or "睡觉" in t or "累" in t or "打哈欠" in t or "眯" in t or "想睡" in t:
		return "sleepy"
	if "学" in t or "作业" in t or "考试" in t or "数学" in t or "背书" in t:
		return "sleepy"
	if ("好" in t and ("奇" in t or "什么" in t)) or "真的吗" in t or "诶" in t:
		return "curious"
	if "哇" in t or "厉害" in t or "棒" in t or "牛" in t:
		return "shy"
	if "666" in t or "我去" in t or "无语" in t or "服了" in t or "什么鬼" in t:
		return "annoyed"
	if "吃" in t or "饿" in t or "烤肠" in t or "冰棍" in t or "奶茶" in t:
		return "eating"
	if "玩" in t or "游戏" in t or "王者" in t or "吃鸡" in t or "原神" in t:
		return "gaming"
	if "对不起" in t or "抱歉" in t or "不好意思" in t or "我错了" in t:
		return "apology"
	if "夸" in t or "喜欢" in t or "可爱" in t:
		return "compliment"
	return "default"

# === 情绪化回复池（来自同学 DialogueDemo2）===
const _EMOTION_POOLS: Dictionary = {
	"greeting": [
		"诶呀，是你呀！", "哈喽～你来啦！", "诶？你怎么在这！",
		"哇，居然是你！", "哟～好久不见！", "诶嘿，你来啦！",
		"嗨嗨～今天怎么啦？", "啊，是你呀！",
	],
	"happy": [
		"哈哈哈好好笑！", "哦吼~太棒了吧！", "诶嘿诶嘿！",
		"笑死我了哈哈哈！", "哇哇哇！真的假的！",
		"666！这个可以的！", "诶诶诶，这也太绝了吧！",
	],
	"shy": [
		"诶、诶呀……别别别夸了啦！", "唔……你说得我都不好意思了……",
		"哈、哈？你说什么呢！", "诶……别这样啦……",
		"唔！别盯着我啦！", "你、你在说什么呀……",
	],
	"sleepy": [
		"哈……好困……", "zzZ……诶？我没睡！", "唔……作业写不完……",
		"啊……脑子转不动了……", "……让我眯一会儿……",
		"困死了……你也累了吧？",
	],
	"curious": [
		"诶？然后呢然后呢？", "等等等等，让我捋捋……",
		"诶嘿？什么什么？", "诶？怎么会这样！",
		"等等，这个我没听懂！", "哇哦！继续继续！",
	],
	"annoyed": [
		"我去，这也太……", "诶，不是吧……", "真的假的啊……",
		"无语了……", "诶，这谁能忍！", "诶我服了……",
	],
	"eating": [
		"啊——好吃的！", "诶，这个好好吃！", "呜呜呜太幸福了……",
		"走走走，吃东西去！", "诶！烤肠！我要！",
		"啊啊啊饿死了！", "诶嘿，冰棍快乐水！",
	],
	"gaming": [
		"诶诶诶！开始！", "哈！赢定了吧！", "诶嘿，小意思小意思～",
		"啊——输了输了！再来！", "诶？你居然赢了我！",
		"哦吼~我赢了诶！", "哈哈哈再来一局！",
	],
	"compliment": [
		"诶、诶呀！别别别夸了！", "唔……你、你也是啦……",
		"诶嘿……还好啦……", "诶！没有没有！",
		"诶……谢、谢谢啦……", "诶？你认真的吗！",
	],
	"apology": [
		"诶……对不起啦……", "啊……我错了我错了！",
		"诶！没事没事！", "唔……抱歉抱歉……",
		"诶……我不对我不对……", "啊！没关系没关系！",
	],
	"default": [
		"哦吼~", "有点意思！", "诶嘿！", "哈哈！",
		"诶……是哦……", "嗯嗯！", "诶，真的假的！",
	],
}

func _get_pool_reply(key: String) -> String:
	var pool = _EMOTION_POOLS.get(key, _EMOTION_POOLS["default"])
	if pool.is_empty():
		return _EMOTION_POOLS["default"][randi() % _EMOTION_POOLS["default"].size()]
	return pool[randi() % pool.size()]

# === 打字机效果（来自同学 DialogueDemo2）===
var _typing_active: bool = false

func _typing_bubble_text(full_text: String) -> void:
	_typing_active = false
	await get_tree().process_frame
	_typing_active = true
	# 找最后加的气泡（NPC 那条），替换其文字为打字效果
	var last_child = message_list.get_child(message_list.get_child_count() - 1)
	if last_child == null or not is_instance_valid(last_child):
		return
	# 在气泡内找 RichTextLabel
	var rt: RichTextLabel = null
	for c in last_child.get_children():
		if c is PanelContainer:
			for inner in c.get_children():
				if inner is RichTextLabel:
					rt = inner
					break
	if rt == null:
		return
	rt.text = ""
	var total = full_text.length()
	for i in range(total):
		if not _typing_active:
			rt.text = full_text
			break
		rt.text = full_text.substr(0, i + 1)
		var delay = randf_range(0.03, 0.10)
		if i < total - 1:
			await get_tree().create_timer(delay).timeout
	_typing_active = false

func _simulate_npc_reply() -> void:
	var profile = NPC_PROFILES.get(current_npc_id, null)
	if profile == null:
		return
	# 先检测情绪，选对应回复池
	var user_text = ""
	if not chat_history.is_empty():
		for i in range(chat_history.size() - 1, -1, -1):
			var e = chat_history[i]
			if typeof(e) == TYPE_DICTIONARY and e.get("role", "") == "user":
				user_text = str(e.get("content", ""))
				break
	var emotion_key = _detect_emotion(user_text)
	var pool_key = emotion_key
	if pool_key == "default":
		pool_key = "greeting"
	var reply: String = _get_pool_reply(pool_key)
	_add_npc_message(reply)
	chat_history.append({"role": "assistant", "content": reply})
	_typing_bubble_text(reply)
	message_count += 1
	_advance_story()
	_save_memory()

func _add_player_message(text: String) -> void:
	var bubble = _create_message_bubble("🪞 你", text, _bubble_player, _label_player_color, true)
	message_list.add_child(bubble)
	_scroll_to_bottom()

func _add_npc_message(text: String) -> void:
	var bubble = _create_message_bubble(current_npc_name, text, _bubble_npc, _label_npc_color, false)
	message_list.add_child(bubble)
	_scroll_to_bottom()


# 公开接口：直接插入一条 NPC 文本（不调 LLM，用于 Act1 主动脚本化追问）
func add_npc_text(_npc_id: String, text: String) -> void:
	_add_npc_message(text)


# === 系统提示气泡（成就 / 节拍反馈 / 阶段总结） ===
# 给 Act1/剧情模块调。聊天面板可见时弹出高亮金黄气泡；
# 不可见时（玩家在外面）只在控制台留 log，不强行打断画面。
func add_system_text(text: String) -> void:
	if text == "":
		return
	if not is_chat_visible():
		# 聊天没开 → 不弹气泡（避免在棋盘/世界强行弹 UI）
		print("[ChatDialogue][system] %s" % text)
		return
	_add_system_message(text)


func is_chat_visible() -> bool:
	# chat_panel 是 PanelContainer，visible 控制显隐
	return chat_panel != null and chat_panel.visible


func _add_system_message(text: String) -> void:
	var bubble := _create_system_bubble(text)
	message_list.add_child(bubble)
	_scroll_to_bottom()


func _create_system_bubble(text: String) -> Control:
	# 居中布局：左 spacer + 内容 + 右 spacer，让气泡水平居中
	var wrapper := HBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 8)

	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.text = "✨ 系统"
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.43, 0.27, 0.08, 1))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _bubble_system)
	panel.custom_minimum_size = Vector2(320, 0)

	var text_label := RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.text = text
	text_label.add_theme_font_size_override("normal_font_size", 18)
	text_label.add_theme_color_override("default_color", _label_system_color)
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.custom_minimum_size = Vector2(0, 32)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(text_label)

	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	wrapper.add_child(left_spacer)
	wrapper.add_child(name_label)
	wrapper.add_child(panel)
	wrapper.add_child(right_spacer)
	return wrapper


# 公开接口：取最近 N 条玩家消息内容（Act1 节点3 关键词判定用）
func get_recent_user_messages(n: int = 10) -> Array:
	var out: Array = []
	# chat_history 里 role=="user" 的，倒序收集 n 条
	for i in range(chat_history.size() - 1, -1, -1):
		var entry = chat_history[i]
		if typeof(entry) == TYPE_DICTIONARY and entry.get("role", "") == "user":
			out.append(entry.get("content", ""))
			if out.size() >= n:
				break
	out.reverse()  # 恢复正序
	return out


# 公开接口：取某 NPC 的全部历史（Act1 节点3 用于父/母分桶关键词）
# 忽略 npc_id 简单标志（chat_history 是当前对话会话全局的）
func get_history(_npc_id: String) -> Array:
	return chat_history.duplicate()


# === 系统按钮（Act1 节点3 收束节点用） ===
func get_npc_role(npc_id: String) -> String:
	# 公开：把当前 NPC 的 system prompt（性格/背景）交给外部模块用
	if npc_id != "" and npc_id == current_npc_id:
		return current_npc_role
	# 兜底：从 NPC_PROFILES 表里查
	if NPC_PROFILES.has(npc_id):
		return NPC_PROFILES[npc_id].get("role", "")
	return ""


func current_npc_id_get() -> String:
	return current_npc_id


func add_system_action(label: String, callback: Callable) -> void:
	if _system_actions == null:
		return
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(callback)
	_system_actions.add_child(btn)


func clear_system_actions() -> void:
	if _system_actions == null:
		return
	for c in _system_actions.get_children():
		c.queue_free()


# 公开接口：把当前剧情阶段塞进 LLM 历史（玩家看不到，LLM 看到能决定台词方向）
# 这条 hint 是 role=system，会通过 LLMClient.send_message 的 input 数组传上去
func set_phase_hint(hint: String) -> void:
	# 删旧 hint，加新 hint
	for i in range(chat_history.size() - 1, -1, -1):
		var entry = chat_history[i]
		if typeof(entry) == TYPE_DICTIONARY and entry.get("role", "") == "_phase_hint":
			chat_history.remove_at(i)
	if hint == "":
		return
	chat_history.append({"role": "_phase_hint", "content": hint})
	# 同步到 LLMClient（让它下一次发请求也带上）
	var llm = get_node_or_null("/root/LLMClient")
	if llm and llm.has_method("inject_system_message"):
		llm.call("inject_system_message", current_npc_id, hint)

func _create_message_bubble(who: String, text: String, style: StyleBoxFlat, color: Color, align_right: bool) -> Control:
	var wrapper = HBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 8)

	var name_label = Label.new()
	name_label.text = who
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.45, 1))

	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.text = text
	text_label.add_theme_font_size_override("normal_font_size", 18)
	text_label.add_theme_color_override("default_color", color)
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.custom_minimum_size = Vector2(0, 32)
	panel.add_child(text_label)

	if align_right:
		# 占位 + 气泡靠右
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.add_child(spacer)
		wrapper.add_child(name_label)
		wrapper.add_child(panel)
	else:
		wrapper.add_child(name_label)
		wrapper.add_child(panel)
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.add_child(spacer)

	return wrapper

func _scroll_to_bottom() -> void:
	# 等一帧再滚动，确保消息已添加
	call_deferred("_do_scroll")

func _do_scroll() -> void:
	var scroll = message_list.get_parent()
	if scroll is ScrollContainer:
		var sc: ScrollContainer = scroll
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)

# === 剧情推进（来自同学 DialogueDemo2）===
func _advance_story() -> void:
	match current_stage:
		StoryStage.INTRO:
			current_stage = StoryStage.BREAK
			_add_to_log("场景", "→ 破冰中...")
		StoryStage.BREAK:
			if message_count >= 4 and game_chosen == "":
				current_stage = StoryStage.GAME
				_add_to_log("场景", "→ 商量玩游戏")
				_send_game_suggestion()
		StoryStage.GAME:
			if message_count >= 8 and food_chosen == "":
				current_stage = StoryStage.CHAT
				_add_to_log("场景", "→ 一起吃东西 / 心事导入")
				_send_food_suggestion()
		StoryStage.CHAT:
			if not has_shared_worry:
				_add_to_log("提示", "可以开始说说你为什么心情不好...")

func _send_game_suggestion() -> void:
	if _awaiting_llm:
		return
	await get_tree().create_timer(1.5).timeout
	if _awaiting_llm or not is_chat_visible():
		return
	var llm = get_node_or_null("/root/LLMClient")
	if llm and llm.has_method("generate_opening"):
		var combined_role = current_npc_role + "\n\n【当前任务：商量玩游戏】\n破冰成功，主动提一起玩。建议玩 2048 或五子棋。\n语气：熟了之后的直接、不绕弯子，可以加「诶」「嘿」等动作感强的词。\n输出：1-2 句话。"
		var cb := func(text: String) -> void:
			if text == "" or not is_chat_visible():
				text = "诶，来一局 2048 不？"
			_add_npc_message(text)
			chat_history.append({"role": "assistant", "content": text})
			_typing_bubble_text(text)
		llm.call("generate_opening", current_npc_id, combined_role, cb)

func _send_food_suggestion() -> void:
	if _awaiting_llm:
		return
	await get_tree().create_timer(2.0).timeout
	if _awaiting_llm or not is_chat_visible():
		return
	var llm = get_node_or_null("/root/LLMClient")
	if llm and llm.has_method("generate_opening"):
		var combined_role = current_npc_role + "\n\n【当前任务：吃东西 + 心事导入】\n游戏玩了一会儿，建议一起去买吃的（烤肠、冰棍、奶茶）。\n吃东西时可以自然地问一句：诶，你今天怎么了？看起来心情不太好。\n语气：熟了之后的直接、明亮、干脆。\n输出：1-2 句话。"
		var cb := func(text: String) -> void:
			if text == "" or not is_chat_visible():
				text = "诶，饿了不？走走走，买烤肠去。"
			_add_npc_message(text)
			chat_history.append({"role": "assistant", "content": text})
			_typing_bubble_text(text)
		llm.call("generate_opening", current_npc_id, combined_role, cb)

# === 记忆存档（来自同学 DialogueDemo2）===
func _save_memory() -> void:
	var config = ConfigFile.new()
	config.set_value("memory", "npc_id", current_npc_id)
	config.set_value("memory", "conversation_history", chat_history)
	config.set_value("memory", "current_stage", current_stage)
	config.set_value("memory", "message_count", message_count)
	config.set_value("memory", "game_chosen", game_chosen)
	config.set_value("memory", "food_chosen", food_chosen)
	config.set_value("memory", "has_shared_worry", has_shared_worry)
	config.set_value("memory", "saved_at", Time.get_datetime_string_from_system())
	var err = config.save(_MEMORY_SAVE_PATH)
	if err == OK:
		print("[ChatDialogue] 记忆已保存（%d 条消息）" % chat_history.size())

func _load_memory() -> void:
	var config = ConfigFile.new()
	if not config.load(_MEMORY_SAVE_PATH) == OK:
		return
	# 只恢复同 NPC 的记忆（避免不同 NPC 串台）
	var saved_npc: String = config.get_value("memory", "npc_id", "")
	if saved_npc != current_npc_id:
		print("[ChatDialogue] 存档是 %s，当前是 %s，不恢复" % [saved_npc, current_npc_id])
		return
	chat_history = config.get_value("memory", "conversation_history", [])
	current_stage = int(config.get_value("memory", "current_stage", int(StoryStage.INTRO)))
	message_count = int(config.get_value("memory", "message_count", 0))
	game_chosen = config.get_value("memory", "game_chosen", "")
	food_chosen = config.get_value("memory", "food_chosen", "")
	has_shared_worry = bool(config.get_value("memory", "has_shared_worry", false))
	print("[ChatDialogue] 已加载记忆：阶段=%d, %d 条消息" % [current_stage, chat_history.size()])

# === _add_to_log：简化版（用于剧情提示）===
func _add_to_log(speaker: String, text: String) -> void:
	print("[ChatDialogue][%s] %s" % [speaker, text])

func _close_chat() -> void:
	# 关闭前存档（来自同学 DialogueDemo2）
	_save_memory()
	emit_signal("chat_closed", current_npc_id)
	clear_choices()    # ← Act1：关闭对话时清理选项面板
	hide_all()
	_awaiting_llm = false
	send_button.disabled = false
	input_box.editable = true
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.set_can_move(true)