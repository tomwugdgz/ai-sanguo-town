class_name AgentMemoryOrganizer
extends RefCounted


const RULE_PROMPTS := [
	"res://prompts/rules/10_identity_and_knowledge.md",
	"res://prompts/rules/20_behavior_and_expression.md",
	"res://prompts/rules/30_data_authority.md",
	"res://prompts/rules/35_events_and_results.md",
]
const BACKGROUND_PROMPTS := [
	"res://prompts/background/10_town_common_knowledge.md",
]
const ORGANIZER_PROMPT := "res://prompts/memory/10_memory_organizer.md"
const ContinuityGuardScript := preload(
	"res://agent/memory/MemoryContinuityGuard.gd",
)
const ModelImageContentScript := preload("res://agent/prompt/ModelImageContent.gd")
const PromptTextScript := preload("res://agent/prompt/PromptText.gd")

# 提示词文件是静态内容，进程级缓存一份；组装结果按实例缓存（initialization 不变）。
static var _prompt_text_cache: Dictionary = {}

var _initialization: Dictionary
var _store: RefCounted
var _photo_content_resolver: Object
var _resident_names: Dictionary = {}
var _continuity_guard: RefCounted
var _system_prompt_cache := ""


func _init(
	initialization: Dictionary,
	store: RefCounted,
	photo_content_resolver: Object = null,
) -> void:
	# initialization 为共享只读数据（约定不可变），各组件持引用不再各存深拷贝。
	_initialization = initialization
	_store = store
	_photo_content_resolver = photo_content_resolver
	_continuity_guard = ContinuityGuardScript.new(_initialization)
	_index_resident_names()


func build_request(
	old_memory: Dictionary,
	evidence_items: Array,
	retry_feedback: String = "",
) -> Dictionary:
	var old_validation := _store.call("validate", old_memory) as Dictionary
	if not bool(old_validation.get("ok", false)):
		return old_validation
	var prompt_result := _build_system_prompt()
	if not bool(prompt_result.get("ok", false)):
		return prompt_result
	var sections := [
		_render_memory(old_validation["memory"] as Dictionary),
		_render_evidence(evidence_items),
	]
	if not retry_feedback.strip_edges().is_empty():
		sections.append("[压缩重试]\n%s" % _safe(retry_feedback))
	var user_text := "\n\n".join(sections)
	var content_result: Dictionary = ModelImageContentScript.build(
		user_text,
		evidence_items,
		_photo_content_resolver,
	)
	if not bool(content_result.get("ok", false)):
		return content_result
	return {
		"ok": true,
		"request_kind": "memory_organization",
		"max_tokens": 8192,
		"old_memory": (old_validation["memory"] as Dictionary).duplicate(true),
		"messages": [
			{"role": "system", "content": prompt_result["content"]},
			{"role": "user", "content": content_result["content"]},
		],
	}


func build_retry_request(
	old_memory: Dictionary,
	evidence_items: Array,
	validation: Dictionary,
) -> Dictionary:
	var fields: Array = validation.get("overflow_fields", [])
	var limits := _store.call("capacity") as Dictionary
	var feedback := ""
	if bool(validation.get("continuity_failure", false)):
		feedback = (
			"上次输出破坏了既有记忆连续性。请根据旧记忆和世界证据修正，"
			+ "没有世界确认时必须保留原关系和未完成事项。"
			+ "\n问题：%s"
		) % "；".join(validation.get("errors", []))
	else:
		feedback = (
			"上次输出超过代码硬上限。请继续概括并返回完整 JSON。"
			+ "\n超限字段：%s"
			+ "\n提示词目标总字符：%d；代码硬上限总字符：%d。"
		) % [
			", ".join(fields),
			int(limits.get("target_total", 5000)),
			int(limits.get("hard_total", 6000)),
		]
	var request := build_request(old_memory, evidence_items, feedback)
	if bool(request.get("ok", false)):
		request["retry_attempt"] = 1
	return request


func validate_candidate(
	candidate: Variant,
	old_memory: Dictionary = {},
	evidence_items: Array = [],
) -> Dictionary:
	var validation := _store.call("validate", candidate) as Dictionary
	if not bool(validation.get("ok", false)):
		return validation
	if old_memory.is_empty():
		return validation
	var continuity := _continuity_guard.call(
		"validate",
		old_memory,
		validation["memory"],
		evidence_items,
	) as Dictionary
	if not bool(continuity.get("ok", false)):
		return continuity
	return validation


func _build_system_prompt() -> Dictionary:
	if not _system_prompt_cache.is_empty():
		return {"ok": true, "content": _system_prompt_cache}
	var sections: Array[String] = []
	for path: String in RULE_PROMPTS + BACKGROUND_PROMPTS + [ORGANIZER_PROMPT]:
		var read_result := _read_text(path)
		if not bool(read_result.get("ok", false)):
			return read_result
		sections.append(String(read_result["content"]).strip_edges())
	sections.append(_render_initialization())
	_system_prompt_cache = "\n\n".join(sections)
	return {"ok": true, "content": _system_prompt_cache}


func _render_initialization() -> String:
	var me := _initialization.get("me", {}) as Dictionary
	var attributes := me.get("attributes", {}) as Dictionary
	var social_state := me.get("social_state", {}) as Dictionary
	var lines: Array[String] = [
		"### 本人稳定资料",
		"姓名：%s（%s）；性别：%s；年龄：%s" % [
			_safe(attributes.get("name", "")),
			_safe(me.get("resident_id", "")),
			_safe(attributes.get("gender", "")),
			_safe(attributes.get("age", "")),
		],
		"欲望：%s" % _safe(attributes.get("desire", "")),
		"性格：%s" % _safe(attributes.get("personality", "")),
		"说话方式：%s" % _safe(attributes.get("speech", "")),
		"前世记忆（三国）：%s" % _safe(attributes.get("backstory", "")),
		"前世人生大事（三国）：%s" % _format_life_events(attributes.get("life_events", [])),
		"前世人生大事只在该话题被聊到时，顺着每条大事的“情境”渐进透露，不要一次倒尽；聊得越深讲得越多。",
		"住处：%s；职业：%s；工作地：%s" % [
			_safe(social_state.get("home", "")),
			_safe(social_state.get("job", "")),
			_safe(social_state.get("workplace", "")),
		],
		"",
		"### 居民公开资料",
	]
	var residents := _initialization.get("residents", []) as Array
	if residents.is_empty():
		lines.append("- 无")
	for resident_value: Variant in residents:
		var resident := resident_value as Dictionary
		lines.append("- %s；性别：%s；年龄：%s；职业：%s；住处：%s；工作地：%s" % [
			_person_label(resident.get("name", ""), resident.get("resident_id", "")),
			_safe(resident.get("gender", "")),
			_safe(resident.get("age", "")),
			_safe(resident.get("job", "")),
			_safe(resident.get("home", "")),
			_safe(resident.get("workplace", "")),
		])
	lines.append("")
	lines.append("### 地点资料")
	var places := _initialization.get("places", []) as Array
	if places.is_empty():
		lines.append("- 无")
	for place_value: Variant in places:
		var place := place_value as Dictionary
		lines.append("- %s；类型：%s；说明：%s" % [
			_safe(place.get("name", "")),
			_safe(place.get("type", "")),
			_safe(place.get("summary", "")),
		])
	return "\n".join(lines)


func _render_memory(memory: Dictionary) -> String:
	return """[旧整理记忆]

[重要记忆]
%s

[人物关系]
%s

[当前想法]
%s

[长期目标]
%s

[短期目标]
%s""" % [
		_or_none(memory.get("important_memories")),
		_or_none(memory.get("relationships")),
		_or_none(memory.get("current_thoughts")),
		_or_none(memory.get("long_term_goals")),
		_or_none(memory.get("short_term_goals")),
	]


func _render_evidence(items: Array) -> String:
	var lines: Array[String] = ["[近期世界证据]"]
	if items.is_empty():
		lines.append("- 无")
	for index in items.size():
		var item := items[index] as Dictionary
		var wake := item.get("wake_packet", {}) as Dictionary
		var snapshot := wake.get("snapshot", {}) as Dictionary
		var place := snapshot.get("place", {}) as Dictionary
		var me := snapshot.get("me", {}) as Dictionary
		lines.append("")
		lines.append("证据 %d；%s；天气%s；地点%s；本人正在%s。" % [
			index + 1,
			_render_time(snapshot.get("time", {})),
			_safe(snapshot.get("weather", "")),
			_safe(place.get("name", "")),
			_safe(me.get("doing", "")),
		])
		var nearby_names: Array[String] = []
		for nearby_value: Variant in snapshot.get("nearby", []) as Array:
			var nearby := nearby_value as Dictionary
			nearby_names.append(_person_label(
				nearby.get("name", ""),
				nearby.get("resident_id", ""),
			))
		lines.append("附近：%s" % (
			"无" if nearby_names.is_empty() else "、".join(nearby_names)
		))
		for event_value: Variant in wake.get("events", []) as Array:
			lines.append("- 世界事件：%s" % _render_event(event_value as Dictionary))
		var intent_by_id := {}
		for intent_value: Variant in item.get("matched_intents", []) as Array:
			var intent := intent_value as Dictionary
			intent_by_id[String(intent.get("action_id", ""))] = intent
		for result_value: Variant in wake.get("action_results", []) as Array:
			var result := result_value as Dictionary
			var intent := intent_by_id.get(String(result.get("action_id", "")), {}) as Dictionary
			lines.append("- 原动作意图：%s" % _render_action(intent))
			lines.append("  世界最终结果（动作ID：%s）：%s；%s；%s" % [
				_safe(result.get("action_id", "")),
				_safe(result.get("status", "")),
				_safe(result.get("reason", "")),
				_render_time(result.get("time", {})),
			])
	return "\n".join(lines)


func _render_event(event: Dictionary) -> String:
	var prefix := "%s；世界事件ID：%s；%s" % [
		_render_time(event.get("time", {})),
		_safe(event.get("event_id", "")),
		_safe(event.get("type", "")),
	]
	match String(event.get("type", "")):
		"有人来了", "有人走了":
			return "%s；%s" % [
				prefix,
				_person_label(
					event.get("who", ""),
					event.get("who_resident_id", ""),
				),
			]
		"天气变了":
			return "%s；天气变为%s" % [prefix, _safe(event.get("weather", ""))]
		"公告发布":
			return "%s；%s" % [prefix, _safe(event.get("text", ""))]
		"搭话", "对方答话":
			return "%s；%s" % [prefix, _render_turn(event.get("turn", {}))]
		"旁听":
			return "%s；%s" % [prefix, _render_turn(event.get("turn", {}))]
		"对话结束":
			var turns: Array[String] = []
			for turn_value: Variant in event.get("turns", []) as Array:
				turns.append(_render_turn(turn_value))
			return "%s；原因%s；完整对话：%s" % [
				prefix,
				_safe(event.get("reason", "")),
				" / ".join(turns),
			]
	return prefix


func _render_turn(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	var turn := value as Dictionary
	var rendered := "%s说“%s”；%s" % [
		_person_label(
			turn.get("speaker", ""),
			turn.get("speaker_resident_id", ""),
		),
		_safe(turn.get("say", "")),
		_safe(turn.get("narration", "")),
	]
	var photo_refs := _render_photo_refs(turn.get("photos", []))
	return rendered if photo_refs.is_empty() else "%s；%s" % [rendered, photo_refs]


func _render_action(action: Dictionary) -> String:
	if action.is_empty():
		return "无"
	var action_type := String(action.get("type", ""))
	var detail := ""
	match action_type:
		"去":
			detail = "前往%s；%s" % [
				_safe(action.get("place", "")),
				_safe(action.get("line", "")),
			]
		"用道具":
			detail = "对%s进行%s；%s" % [
				_safe(action.get("prop", "")),
				_safe(action.get("verb", "")),
				_safe(action.get("line", "")),
			]
		"待着":
			detail = _safe(action.get("line", ""))
		"托人传话":
			detail = "托人给%s带口信“%s”；%s" % [
				_person_label(
					_name_for_id(
						action.get("recipient_resident_id", ""),
					),
					action.get("recipient_resident_id", ""),
				),
				_safe(action.get("content", "")),
				_safe(action.get("line", "")),
			]
		"搭话":
			detail = "向%s搭话；说“%s”；%s" % [
				_person_label(
					_name_for_id(action.get("target_resident_id", "")),
					action.get("target_resident_id", ""),
				),
				_safe(action.get("say", "")),
				_safe(action.get("narration", "")),
			]
		"答话":
			detail = "说“%s”；%s；%s" % [
				_safe(action.get("say", "")),
				_safe(action.get("narration", "")),
				"结束对话" if bool(action.get("end", false)) else "继续对话",
			]
	var rendered := "动作ID：%s；%s；%s" % [
		_safe(action.get("action_id", "")),
		_safe(action_type),
		detail,
	]
	var photo_refs := _render_photo_refs(action.get("photos", []))
	return rendered if photo_refs.is_empty() else "%s；%s" % [rendered, photo_refs]


func _index_resident_names() -> void:
	var me := _initialization.get("me", {}) as Dictionary
	var attributes := me.get("attributes", {}) as Dictionary
	_resident_names[String(me.get("resident_id", ""))] = String(attributes.get("name", ""))
	for resident_value: Variant in _initialization.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		_resident_names[String(resident.get("resident_id", ""))] = String(resident.get("name", ""))


func _name_for_id(value: Variant) -> String:
	var resident_id := String(value)
	return _safe(_resident_names.get(resident_id, "未知人物"))


func _person_label(name: Variant, resident_id: Variant) -> String:
	var safe_name := _safe(name)
	var safe_id := _safe(resident_id)
	if safe_id.strip_edges().is_empty():
		return safe_name
	return "%s（%s）" % [safe_name, safe_id]


func _render_photo_refs(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return ""
	var refs: Array[String] = []
	for photo_value: Variant in value as Array:
		if typeof(photo_value) != TYPE_DICTIONARY:
			continue
		var ref := _safe((photo_value as Dictionary).get("ref", ""))
		if not ref.strip_edges().is_empty():
			refs.append(ref)
	return "" if refs.is_empty() else "照片引用：%s" % "、".join(refs)


func _render_time(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "时间未知"
	var time := value as Dictionary
	return "第%s天 %s %s" % [
		_safe(time.get("day", "")),
		_safe(time.get("clock", "")),
		_safe(time.get("period", "")),
	]


func _or_none(value: Variant) -> String:
	var text := _safe(value)
	return "无" if text.strip_edges().is_empty() else text


func _safe(value: Variant) -> String:
	return PromptTextScript.escape_dynamic(value)


func _format_life_events(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "暂无"
	var lines: Array[String] = []
	for item_value: Variant in value as Array:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item := item_value as Dictionary
		var era := _safe(item.get("era", ""))
		var title := _safe(item.get("title", ""))
		var summary := _safe(item.get("summary", ""))
		var trigger := _safe(item.get("trigger", ""))
		lines.append(
			"· %s %s：%s（情境：%s）" % [era, title, summary, trigger]
		)
	return "\n".join(lines) if not lines.is_empty() else "暂无"


func _read_text(path: String) -> Dictionary:
	if _prompt_text_cache.has(path):
		return {"ok": true, "content": _prompt_text_cache[path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["无法读取记忆提示词：%s" % path]}
	var content := file.get_as_text()
	file = null
	_prompt_text_cache[path] = content
	return {"ok": true, "content": content}
