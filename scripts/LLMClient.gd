# LLM Client: 调用智源 BigModel API（OpenAI 兼容接口）
# 每 NPC 独立多轮历史（per_npc history）
# 每 NPC 独立 instructions（system prompt）——直接来自 ChatDialogue 的 NPC_PROFILES.role
# 监听 ChatDialogue 发出的 user_message_sent → 异步回调 llm_reply_received
extends Node

# ===== API 配置 =====
const API_URL := "https://open.bigmodel.cn/api/paas/v4/chat/completions"
const MODEL_NAME := "glm-4-flash"  # 默认模型，可被 NPC JSON 的 model 字段覆盖

# ===== 全局开关 =====
const USE_MOCK_API: bool = false        # 调试时改 true 看本地模拟
const MAX_HISTORY_PER_NPC: int = 17     # 与 DialogueDemo2 一致：system + 8 轮

# ===== 状态 =====
var api_key: String = ""
var _histories: Dictionary = {}          # npc_id -> [{role, content}, ...]
var _instructions: Dictionary = {}      # npc_id -> system prompt 字符串
var _last_response_ids: Dictionary = {}  # npc_id -> 上轮 response_id（用于 previous_response_id）
var _http_request_pool: Array = []

# 信号
signal llm_reply_received(npc_id: String, text: String)
signal llm_error(npc_id: String, error_msg: String)

# === 初始化：读取 .env ===
func _ready() -> void:
	api_key = _read_env_from_file("res://.env", "ZHIPU_API_KEY")
	if api_key.is_empty():
		push_warning("[LLMClient] 未找到 ZHIPU_API_KEY，API 调用会失败")
	else:
		print("[LLMClient] 已加载智源 API Key，长度: %d" % api_key.length())

# ===== 公开接口 =====

# 生成某 NPC 的开场白（玩家按 E 刚开聊时调用）
# - 不污染 per_npc history（不写进 _histories）
# - 失败时 callback 收到空字符串，ChatDialogue 会用 profile.greeting 兜底
func generate_opening(npc_id: String, npc_system_role: String, callback: Callable) -> void:
	if USE_MOCK_API:
		_mock_opening(npc_id, callback)
		return

	if api_key.is_empty():
		push_warning("[LLMClient] generate_opening 跳过：无 API Key")
		callback.call("")
		return

	# 临时指令：让 LLM 生成一段独立、不引用上下文的招呼语
	var prompt := npc_system_role + "\n\n" + \
		"【本次特殊任务】生成一句招呼语（≤ 25 字）。\n" + \
		"要求：\n" + \
		"1. 体现你（这个 NPC）的身份和性格\n" + \
		"2. 每次生成都不一样（同一 NPC 多次调用结果也不重复）\n" + \
		"3. 不要寒暄客套，要符合你的人设\n" + \
		"4. 不要引用任何之前的对话上下文（本次是全新招呼）\n" + \
		"5. 直接输出这句话，不要任何前缀/标点/引号"

	# 用一个独立 NPC id 防止污染 _histories / _last_response_ids
	var tmp_id := "__opening__%s__%d" % [npc_id, Time.get_ticks_msec()]

	var http_request = HTTPRequest.new()
	add_child(http_request)
	_http_request_pool.append(http_request)
	http_request.request_completed.connect(_on_opening_request_completed.bind(tmp_id, http_request, callback))

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key
	]

	# OpenAI 兼容格式
	var body: Dictionary = {
		"model": MODEL_NAME,
		"messages": [
			{"role": "system", "content": npc_system_role},
			{"role": "user", "content": prompt}
		],
		"temperature": 1.0,
	}

	print("[LLMClient] generate_opening for %s (tmp_id=%s)" % [npc_id, tmp_id])
	var err = http_request.request(API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_http_request_pool.erase(http_request)
		http_request.queue_free()
		callback.call("")


func _on_opening_request_completed(
		result: int, response_code: int, _headers: Array,
		body: PackedByteArray, tmp_id: String,
		http_request: HTTPRequest, callback: Callable) -> void:
	if http_request in _http_request_pool:
		_http_request_pool.erase(http_request)
	if is_instance_valid(http_request):
		http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[LLMClient] generate_opening 失败 tmp_id=%s code=%d" % [tmp_id, response_code])
		callback.call("")
		return

	var body_text = body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(body_text) != OK:
		callback.call("")
		return

	var reply := _extract_reply(json.data)
	print("[LLMClient] generate_opening 拿到: %s" % reply)
	callback.call(reply)


# === 群聊回复（不污染 history，prompt 直接用调用方传的 context）===
# - 用于 GroupChatEngine：让 NPC 在群里回复玩家消息
# - 与 generate_opening 区别：prompt 不附加"招呼语"任务，让 LLM 真的看上下文
# - 用 tmp_id 防污染 _histories（同 generate_opening 设计）
func generate_reply_async(npc_id: String, system_role: String, user_context: String, callback: Callable) -> void:
	if USE_MOCK_API:
		_mock_opening(npc_id, callback)
		return

	if api_key.is_empty():
		push_warning("[LLMClient] generate_reply_async 跳过：无 API Key")
		callback.call("")
		return

	# 临时 NPC id 防污染 per_npc history
	var tmp_id := "__reply__%s__%d" % [npc_id, Time.get_ticks_msec()]

	var http_request = HTTPRequest.new()
	add_child(http_request)
	_http_request_pool.append(http_request)
	http_request.request_completed.connect(_on_reply_request_completed.bind(tmp_id, http_request, callback))

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key
	]

	var body: Dictionary = {
		"model": MODEL_NAME,
		"messages": [
			{"role": "system", "content": system_role},
			{"role": "user", "content": user_context}
		],
		"temperature": 0.95,
	}

	print("[LLMClient] generate_reply_async for %s (tmp_id=%s, ctx_len=%d)" % [npc_id, tmp_id, user_context.length()])
	var err = http_request.request(API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_http_request_pool.erase(http_request)
		http_request.queue_free()
		callback.call("")


func _on_reply_request_completed(
		result: int, response_code: int, _headers: Array,
		body: PackedByteArray, tmp_id: String,
		http_request: HTTPRequest, callback: Callable) -> void:
	if http_request in _http_request_pool:
		_http_request_pool.erase(http_request)
	if is_instance_valid(http_request):
		http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[LLMClient] generate_reply_async 失败 tmp_id=%s code=%d" % [tmp_id, response_code])
		callback.call("")
		return

	var body_text = body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(body_text) != OK:
		callback.call("")
		return

	var reply := _extract_reply(json.data)
	print("[LLMClient] generate_reply_async 拿到: %s" % reply)
	callback.call(reply)


# 本地模拟开场白
func _mock_opening(npc_id: String, callback: Callable) -> void:
	var pool := {
		"xiaoyang": [
			"哟，又是你呀。",
			"今天怎么这么晚？",
			"诶～好巧啊，在这遇见你。",
			"刚才那个五子棋，没下够吧？",
			"在想什么呢，一副走神的样子。"
		],
		"xiaoyou": [
			"诶呀～是你啊！",
			"今天放学好早嘛～",
			"走走走，去小卖部！",
			"诶嘿，你脸色不太好啊？",
			"我跟你说，今天可有意思了～"
		],
	}
	var default := ["诶，你来啦。", "嗯？怎么了？", "哈？有什么事吗？"]
	var list: Array = pool.get(npc_id, default)
	var delay = randf_range(0.6, 1.2)
	await get_tree().create_timer(delay).timeout
	callback.call(list[randi() % list.size()])


# 给某 NPC 发送一条消息，异步返回通过信号
func send_message(npc_id: String, user_text: String, npc_system_role: String = "") -> void:
	if USE_MOCK_API:
		_mock_reply(npc_id, user_text)
		return

	if api_key.is_empty():
		push_warning("[LLMClient] send_message 跳过：无 API Key")
		emit_signal("llm_error", npc_id, "未配置 API Key")
		return

	# 记录/更新这个 NPC 的 instructions（覆盖式）
	if npc_system_role != "":
		_instructions[npc_id] = npc_system_role

	# 拿 / 创建这个 NPC 的历史
	var hist: Array = _histories.get(npc_id, [])
	# 加 user
	hist.append({"role": "user", "content": user_text})

	# 截断历史，防止 token 爆炸
	if hist.size() > MAX_HISTORY_PER_NPC:
		hist = hist.slice(-MAX_HISTORY_PER_NPC)
	_histories[npc_id] = hist

	var http_request = HTTPRequest.new()
	add_child(http_request)
	_http_request_pool.append(http_request)
	http_request.request_completed.connect(_on_request_completed.bind(npc_id, http_request))

	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key
	]

	# 构建 messages 数组：system + 完整历史
	var messages: Array = []
	var system_prompt: String = ""
	if _instructions.has(npc_id) and _instructions[npc_id] != "":
		system_prompt = _instructions[npc_id]
	if system_prompt.is_empty():
		system_prompt = "你是 NPC，回复要简短。"
	messages.append({"role": "system", "content": system_prompt})

	# 完整历史
	for msg in hist:
		messages.append({"role": msg["role"], "content": msg["content"]})

	# OpenAI 兼容请求体
	var body: Dictionary = {
		"model": MODEL_NAME,
		"messages": messages,
	}

	var hist_len := messages.size()
	var instr_len := system_prompt.length()
	var has_prev: bool = _last_response_ids.has(npc_id) and _last_response_ids[npc_id] != ""
	print("[LLMClient] send_to npc=%s msgs=%d instr=%s prev_id=%s" % [
		npc_id, hist_len,
		("YES (%d chars)" % instr_len) if instr_len > 0 else "NO",
		"YES" if has_prev else "NO"
	])

	var err = http_request.request(API_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_histories[npc_id] = hist.slice(0, -1)  # 回滚 user 消息
		emit_signal("llm_error", npc_id, "请求发送失败 (err=%d)" % err)
		http_request.queue_free()
		_http_request_pool.erase(http_request)


# 清空某个 NPC 的历史
func reset_history(npc_id: String) -> void:
	_histories.erase(npc_id)
	_instructions.erase(npc_id)
	_last_response_ids.erase(npc_id)


# 清空所有 NPC 历史
func reset_all_history() -> void:
	_histories.clear()
	_instructions.clear()
	_last_response_ids.clear()


# 调试：拿某 NPC 历史长度
func get_history_length(npc_id: String) -> int:
	if _histories.has(npc_id):
		return _histories[npc_id].size()
	return 0


# 注入一条剧情提示（role=system）
func inject_system_message(npc_id: String, msg: String) -> void:
	if msg == "":
		return
	var hist: Array = _histories.get(npc_id, [])
	for i in range(hist.size() - 1, -1, -1):
		var entry = hist[i]
		if typeof(entry) == TYPE_DICTIONARY and entry.get("role", "") == "system":
			hist.remove_at(i)
	hist.append({"role": "system", "content": msg})
	_histories[npc_id] = hist


# ===== 私有 =====

func _on_request_completed(result: int, response_code: int, headers: Array, body: PackedByteArray, npc_id: String, http_request: HTTPRequest) -> void:
	if http_request in _http_request_pool:
		_http_request_pool.erase(http_request)
	if is_instance_valid(http_request):
		http_request.queue_free()

	var body_text = body.get_string_from_utf8()
	print("[LLMClient] HTTP %d for %s" % [response_code, npc_id])

	if result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("llm_error", npc_id, "网络错误")
		return
	if response_code == 401:
		emit_signal("llm_error", npc_id, "API Key 无效 (401)")
		return
	if response_code != 200:
		emit_signal("llm_error", npc_id, "HTTP %d" % response_code)
		return

	var json = JSON.new()
	if json.parse(body_text) != OK:
		emit_signal("llm_error", npc_id, "响应解析失败")
		return

	var response = json.data
	var reply := _extract_reply(response)

	if reply.is_empty():
		emit_signal("llm_error", npc_id, "无响应内容")
		return

	# 保存 response_id（智源 API 可能会返回 id）
	var response_id := _extract_response_id(response)
	if response_id != "":
		_last_response_ids[npc_id] = response_id

	# 加入历史
	var hist: Array = _histories.get(npc_id, [])
	hist.append({"role": "assistant", "content": reply})
	_histories[npc_id] = hist

	emit_signal("llm_reply_received", npc_id, reply)


# 提取回复内容：OpenAI 格式 choices[0].message.content
func _extract_reply(response: Variant) -> String:
	if response is Dictionary and response.has("choices"):
		var choices: Array = response["choices"]
		if choices.size() > 0:
			var choice = choices[0]
			if choice is Dictionary and choice.has("message"):
				var msg = choice["message"]
				if msg is Dictionary and msg.has("content"):
					return str(msg["content"])
	return ""


func _extract_response_id(response: Variant) -> String:
	if response is Dictionary and response.has("id"):
		return str(response["id"])
	return ""


# ===== 本地模拟 =====
func _mock_reply(npc_id: String, user_text: String) -> void:
	var mock_replies := [
		"嗯嗯~", "是啊~", "然后呢～", "确实确实",
		"哈哈哈哈", "诶？你说啥", "诶嘿嘿~", "好呀好呀",
		"我也要！", "真的吗～", "啊这样啊"
	]
	var delay = randf_range(0.8, 1.6)
	await get_tree().create_timer(delay).timeout
	var reply = mock_replies[randi() % mock_replies.size()]
	emit_signal("llm_reply_received", npc_id, reply)


# ===== .env 文件读取工具 =====
func _read_env_from_file(env_path: String, key: String) -> String:
	if not FileAccess.file_exists(env_path):
		push_warning("[LLMClient] 找不到 %s" % env_path)
		return ""
	var f: FileAccess = FileAccess.open(env_path, FileAccess.READ)
	if f == null:
		push_warning("[LLMClient] 打不开 %s" % env_path)
		return ""
	while not f.eof_reached():
		var line: String = f.get_line()
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var eq: int = line.find("=")
		if eq < 0:
			continue
		var k: String = line.substr(0, eq).strip_edges()
		if k == key:
			var value: String = line.substr(eq + 1).strip_edges()
			# 去掉引号包裹
			if value.length() >= 2 and (
				(value.begins_with("\"") and value.ends_with("\""))
				or (value.begins_with("'") and value.ends_with("'"))
			):
				value = value.substr(1, value.length() - 2)
			f.close()
			return value
	f.close()
	return ""
