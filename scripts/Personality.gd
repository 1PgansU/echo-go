# Godot 4 · 8 维性格引擎
extends Node
class_name PersonalityEngine

# 8 个性格维度，初始为 0
var traits: Dictionary = {
	"confidence":   0,  # 自信
	"sensitivity":  0,  # 敏感
	"resilience":   0,  # 抗压
	"social":       0,  # 社交
	"expression":   0,  # 表达
	"independence": 0,  # 独立
	"family_bond":  0,  # 家庭亲近
	"study_drive":  0   # 学业重视
}

const DIM_NAMES = {
	"confidence":   "自信",
	"sensitivity":  "敏感",
	"resilience":   "抗压",
	"social":       "社交",
	"expression":   "表达",
	"independence": "独立",
	"family_bond":  "家庭亲近",
	"study_drive":  "学业重视"
}

const DIM_ICONS = {
	"confidence":   "💪",
	"sensitivity":  "🌸",
	"resilience":   "🛡️",
	"social":       "🤝",
	"expression":   "💬",
	"independence": "🦅",
	"family_bond":  "🏠",
	"study_drive":  "📚"
}

# 安全访问 traits 中的 key，做累加
func _add(key: String, v: int) -> void:
	if not traits.has(key):
		traits[key] = 0
	traits[key] = int(traits[key]) + v

# 安全访问 traits 中的 key，做减法
func _sub(key: String, v: int) -> void:
	_add(key, -v)

# 从问卷答案初始化（answers: Array[int]，每题 0-3）
func init_from_answers(answers: Array) -> void:
	reset()
	if answers.size() < 5:
		push_warning("Questionnaire answers incomplete")
		return

	# 题目 1：被父母批评时的反应
	var r1 = answers[0]
	match r1:
		0: _add("confidence", 2); _add("expression", 2); _sub("family_bond", 1)
		1: _add("resilience", 1); _add("sensitivity", 2); _sub("confidence", 1)
		2: _add("expression", 1); _sub("confidence", 1)
		3: _add("social", 2); _add("sensitivity", 1)

	# 题目 2：被同学误解时
	var r2 = answers[1]
	match r2:
		0: _add("expression", 2); _add("social", 1)
		1: _add("social", 2); _add("sensitivity", 1)
		2: _add("resilience", 2); _add("independence", 1); _sub("confidence", 1)
		3: _add("confidence", 1); _add("resilience", 1); _sub("social", 1)

	# 题目 3：对学业看法
	var r3 = answers[2]
	match r3:
		0: _add("study_drive", 3); _add("resilience", 1)
		1: _add("study_drive", 1)
		2: _sub("study_drive", 1); _add("independence", 1)
		3: _sub("study_drive", 2); _add("independence", 2)

	# 题目 4：暗恋拒绝
	var r4 = answers[3]
	match r4:
		0: _add("confidence", 2); _add("expression", 1); _add("sensitivity", 1)
		1: _add("resilience", 2); _add("independence", 2)
		2: _sub("confidence", 2); _add("sensitivity", 2)
		3: _sub("confidence", 1); _add("sensitivity", 2); _add("independence", 1)

	# 题目 5：父母爱我吗
	var r5 = answers[4]
	match r5:
		0: _add("family_bond", 3); _sub("sensitivity", 1)
		1: _add("family_bond", 1)
		2: _sub("family_bond", 1); _add("sensitivity", 1)
		3: _sub("family_bond", 3); _add("resilience", 2); _add("independence", 2)

func reset() -> void:
	for key in traits:
		traits[key] = 0

# 应用 delta（限制在 -10~+10）
func apply_delta(delta: Dictionary) -> void:
	for key in delta:
		if traits.has(key):
			traits[key] = clampi(int(traits[key]) + int(delta[key]), -10, 10)

# 获取所有维度
func get_traits() -> Dictionary:
	return traits.duplicate()

# 获取主导人格类型
func get_archetype() -> String:
	var max_dim = ""
	var max_val = 0
	for key in traits:
		var v = absi(int(traits[key]))
		if v > max_val:
			max_val = v
			max_dim = key

	if max_dim == "":
		return "平衡型人格"
	return "%s型人格" % DIM_NAMES[max_dim]

# 获取标签
func get_tags() -> Array:
	var tags: Array = []
	if int(traits["confidence"]) >= 3: tags.append("坚定自我")
	if int(traits["confidence"]) <= -3: tags.append("自我怀疑")
	if int(traits["sensitivity"]) >= 3: tags.append("高度敏感")
	if int(traits["resilience"]) >= 3: tags.append("百折不挠")
	if int(traits["resilience"]) <= -3: tags.append("容易崩溃")
	if int(traits["social"]) >= 3: tags.append("人群中的鱼")
	if int(traits["social"]) <= -3: tags.append("习惯独处")
	if int(traits["expression"]) >= 3: tags.append("敢于发声")
	if int(traits["independence"]) >= 3: tags.append("独立自主")
	if int(traits["family_bond"]) >= 3: tags.append("恋家")
	if int(traits["family_bond"]) <= -3: tags.append("渴望逃离")
	if int(traits["study_drive"]) >= 3: tags.append("卷王")
	if int(traits["study_drive"]) <= -3: tags.append("躺平派")
	return tags

# 序列化为字典（用于保存）
func to_dict() -> Dictionary:
	return traits.duplicate()

# 从字典恢复
func from_dict(data: Dictionary) -> void:
	for key in traits:
		if data.has(key):
			traits[key] = int(data[key])