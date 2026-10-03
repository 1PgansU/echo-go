# ============================================================
# Act1 · 交朋友（极简版）
# ============================================================
# 节点1：玩家第一次按 E 跟小羊开聊 → 记为"破冰完成"
# 节点2：玩家按 R 开五子棋 → 记为"游戏约定达成"，友情值 +10
#
# 注：QuestList UI 已删除（玩家要求"世界自由探索"）。
#     状态机仍然保留，因为后续可能接叙事推进。
# ============================================================
extends Node

# ---------- 信号 ----------
signal act1_started            # 节点1 开始
signal ice_breaking_done       # 节点1 完成
signal negotiating_done        # 节点2 完成
signal act1_finished           # 全部完成（已加友情值）

# ---------- 状态机 ----------
enum State { IDLE, ICE_DONE, GAME_DONE }
var state: int = State.IDLE

# ---------- 引用 ----------
var _chat_dlg = null
var _connected: bool = false
const NPC_ID := "xiaoyang"

# === 友情值加成（节点2 完成时给） ===
const FRIENDSHIP_BONUS := 10


func _ready() -> void:
	call_deferred("_init_connections")


# ============================================================
# 连接 ChatDialogue 信号
# ============================================================
func _init_connections() -> void:
	_chat_dlg = _find_chat_dialogue()
	if _chat_dlg == null:
		push_warning("[Act1] ChatDialogue 没找到，模块未连接")
		return
	_connect_signals()
	_connected = true
	print("[Act1] 已连接 ChatDialogue，等待玩家事件")


func _find_chat_dialogue():
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_chat_dialogue"):
		var d = gm.call("get_chat_dialogue")
		if d != null:
			return d
	return get_node_or_null("/root/Main/DialogueLayer/ChatDialogue")


func _connect_signals() -> void:
	if _chat_dlg.has_signal("chat_opened"):
		if not _chat_dlg.chat_opened.is_connected(_on_chat_opened):
			_chat_dlg.chat_opened.connect(_on_chat_opened)
	if _chat_dlg.has_signal("chat_closed"):
		if not _chat_dlg.chat_closed.is_connected(_on_chat_closed):
			_chat_dlg.chat_closed.connect(_on_chat_closed)
	if _chat_dlg.has_signal("user_message_sent"):
		if not _chat_dlg.user_message_sent.is_connected(_on_user_message_sent):
			_chat_dlg.user_message_sent.connect(_on_user_message_sent)


func _ensure_chat_connected() -> bool:
	if _connected and _chat_dlg != null and is_instance_valid(_chat_dlg):
		return true
	_chat_dlg = _find_chat_dialogue()
	if _chat_dlg == null:
		return false
	_connect_signals()
	_connected = true
	return true


# ============================================================
# 事件1：玩家按 E 跟小羊开聊
# ============================================================
func _on_chat_opened(npc_id: String) -> void:
	if not _ensure_chat_connected():
		return
	if npc_id != NPC_ID:
		return
	print("[Act1] 聊天打开：%s" % npc_id)
	# 节点1：第一次开聊 → 破冰完成
	if state == State.IDLE:
		_finish_ice_break()


# ============================================================
# 事件2：玩家按 R 开五子棋
# ============================================================
func on_gomoku_started() -> void:
	# GomokuScene 在开局时调用 questline_act1.on_gomoku_started()
	if state == State.ICE_DONE:
		_finish_negotiate()
	else:
		print("[Act1] on_gomoku_started 但状态不对：%s" % State.keys()[state])


# ============================================================
# 事件3：玩家发消息（目前 Act1 无节点3，仅占位）
# ============================================================
func _on_user_message_sent(_npc_id: String, _text: String) -> void:
	pass


# ============================================================
# 节点推进
# ============================================================
func _finish_ice_break() -> void:
	state = State.ICE_DONE
	act1_started.emit()
	ice_breaking_done.emit()
	print("[Act1] 破冰完成")


func _finish_negotiate() -> void:
	state = State.GAME_DONE
	negotiating_done.emit()
	# ===== 友情值 +10（Act1 完成奖励） =====
	_grant_friendship_bonus()
	act1_finished.emit()
	print("[Act1] 全部完成！小羊友情值 +%d" % FRIENDSHIP_BONUS)


func _grant_friendship_bonus() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		push_warning("[Act1] GameManager 找不到，友情值未发放")
		return
	if gm.has_method("add_relationship"):
		gm.call("add_relationship", NPC_ID, FRIENDSHIP_BONUS)
	else:
		push_warning("[Act1] GameManager 没有 add_relationship 方法")


# ============================================================
# 关闭聊天
# ============================================================
func _on_chat_closed(_npc_id: String) -> void:
	pass


# ============================================================
# 调试 / 外部查询
# ============================================================
func get_debug_state() -> Dictionary:
	return {
		"state": State.keys()[state],
		"connected": _connected,
		"friendship_bonus": FRIENDSHIP_BONUS,
	}