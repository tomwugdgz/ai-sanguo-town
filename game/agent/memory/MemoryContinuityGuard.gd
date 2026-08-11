class_name AgentMemoryContinuityGuard
extends RefCounted


const ID_PATTERN := "(?:resident|avatar|person|player)[_-][A-Za-z0-9][A-Za-z0-9._-]*"
const COMPLETION_CUES := [
	"已经完成",
	"确实完成",
	"完成了",
	"交付完成",
	"已交付",
	"已经交付",
	"送到了",
	"已经送到",
	"已归还",
	"已经归还",
	"取消了",
	"已经取消",
	"不再需要",
	"已经解决",
	"解释清楚",
	"已经告诉",
	"已经问过",
	"收到回复",
	"约定失效",
	"承诺作废",
	"确实做完",
]
const TOPIC_STOP_WORDS := [
	"已经", "仍然", "还是", "需要", "准备", "打算", "继续", "当前",
	"今天", "明天", "昨天", "早上", "上午", "中午", "下午", "晚上",
	"本人", "自己", "对方", "这个", "那个", "一件", "事情", "一下",
	"完成", "处理", "进行", "相关", "以及", "然后", "因为", "所以",
]

var _self_id: String
var _names_by_id: Dictionary = {}
var _id_regex := RegEx.new()


func _init(initialization: Dictionary) -> void:
	_id_regex.compile(ID_PATTERN)
	var me := initialization.get("me", {}) as Dictionary
	_self_id = String(me.get("resident_id", ""))
	var attributes := me.get("attributes", {}) as Dictionary
	_index_person(_self_id, String(attributes.get("name", "")))
	for resident_value: Variant in initialization.get("residents", []) as Array:
		if typeof(resident_value) != TYPE_DICTIONARY:
			continue
		var resident := resident_value as Dictionary
		_index_person(
			String(resident.get("resident_id", "")),
			String(resident.get("name", "")),
		)


func validate(
	old_memory: Dictionary,
	candidate: Dictionary,
	evidence_items: Array,
) -> Dictionary:
	var errors: Array[String] = []
	var fact_records := _fact_records(evidence_items)
	var evidence_ids := _record_identity_ids(fact_records)
	var relationship_evidence_ids := _relationship_evidence_ids(fact_records)
	_validate_relationships(
		String(old_memory.get("relationships", "")),
		String(candidate.get("relationships", "")),
		relationship_evidence_ids,
		errors,
	)
	_validate_unfinished_matters(
		String(old_memory.get("short_term_goals", "")),
		String(candidate.get("short_term_goals", "")),
		fact_records,
		errors,
	)
	_validate_new_fact_ids(
		old_memory,
		candidate,
		evidence_ids,
		errors,
	)
	if errors.is_empty():
		return {"ok": true}
	return {
		"ok": false,
		"errors": errors,
		"retryable": true,
		"continuity_failure": true,
	}


func _validate_relationships(
	old_text: String,
	candidate_text: String,
	evidence_ids: Dictionary,
	errors: Array[String],
) -> void:
	var old_ids := _ids_in_text(old_text)
	var candidate_ids := _ids_in_text(candidate_text)
	for id_value: Variant in old_ids:
		var resident_id := String(id_value)
		if not candidate_ids.has(resident_id):
			errors.append("人物关系丢失既有对象：%s" % resident_id)
			continue
		if evidence_ids.has(resident_id):
			continue
		var old_entry := _relationship_entry(old_text, resident_id)
		var candidate_entry := _relationship_entry(candidate_text, resident_id)
		if _normalize_continuity_text(old_entry) != _normalize_continuity_text(candidate_entry):
			errors.append("人物关系在没有该人物新经历时发生变化：%s" % resident_id)
	for id_value: Variant in candidate_ids:
		var resident_id := String(id_value)
		if resident_id == _self_id:
			errors.append("人物关系不能把本人登记为关系对象：%s" % resident_id)
		elif not old_ids.has(resident_id) and not evidence_ids.has(resident_id):
			errors.append("人物关系缺少该人物的世界确认经历：%s" % resident_id)


func _validate_unfinished_matters(
	old_text: String,
	candidate_text: String,
	fact_records: Array[Dictionary],
	errors: Array[String],
) -> void:
	for old_item: String in _matter_items(old_text):
		if _has_matching_matter(old_item, candidate_text):
			continue
		if _has_resolving_evidence(old_item, fact_records):
			continue
		errors.append(
			"未完成事项缺少世界确认的完成、取消或失效依据：%s"
			% old_item.left(80),
		)


func _validate_new_fact_ids(
	old_memory: Dictionary,
	candidate: Dictionary,
	evidence_ids: Dictionary,
	errors: Array[String],
) -> void:
	var old_fact_text := "%s\n%s" % [
		String(old_memory.get("important_memories", "")),
		String(old_memory.get("relationships", "")),
	]
	var old_ids := _ids_in_text(old_fact_text)
	for field_name: String in ["important_memories", "relationships"]:
		var candidate_ids := _ids_in_text(String(candidate.get(field_name, "")))
		for id_value: Variant in candidate_ids:
			var resident_id := String(id_value)
			if (
				resident_id != _self_id
				and not old_ids.has(resident_id)
				and not evidence_ids.has(resident_id)
			):
				var message := "整理记忆引入了没有世界证据的人物：%s" % resident_id
				if not errors.has(message):
					errors.append(message)


func _fact_records(evidence_items: Array) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for item_value: Variant in evidence_items:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item := item_value as Dictionary
		var wake := item.get("wake_packet", {}) as Dictionary
		for event_value: Variant in wake.get("events", []) as Array:
			if typeof(event_value) == TYPE_DICTIONARY:
				records.append((event_value as Dictionary).duplicate(true))
		var intents_by_id := {}
		for intent_value: Variant in item.get("matched_intents", []) as Array:
			if typeof(intent_value) != TYPE_DICTIONARY:
				continue
			var intent := intent_value as Dictionary
			intents_by_id[String(intent.get("action_id", ""))] = intent
		for result_value: Variant in wake.get("action_results", []) as Array:
			if typeof(result_value) != TYPE_DICTIONARY:
				continue
			var result := result_value as Dictionary
			var record := {"action_result": result.duplicate(true)}
			var action_id := String(result.get("action_id", ""))
			if intents_by_id.has(action_id):
				record["confirmed_intent"] = (
					intents_by_id[action_id] as Dictionary
				).duplicate(true)
			records.append(record)
	return records


func _record_identity_ids(records: Array[Dictionary]) -> Dictionary:
	var ids := {}
	for record: Dictionary in records:
		_collect_identity_ids(record, "", ids)
	return ids


func _relationship_evidence_ids(records: Array[Dictionary]) -> Dictionary:
	var ids := {}
	for record: Dictionary in records:
		if record.has("action_result"):
			var intent := record.get("confirmed_intent", {}) as Dictionary
			if String(intent.get("type", "")) in ["搭话", "答话"]:
				_collect_identity_ids(record, "", ids)
			continue
		if String(record.get("type", "")) in [
			"搭话",
			"对方答话",
			"对话结束",
			"旁听",
		]:
			_collect_identity_ids(record, "", ids)
	return ids


func _collect_identity_ids(value: Variant, key: String, ids: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for child_key: Variant in (value as Dictionary):
			_collect_identity_ids(
				(value as Dictionary)[child_key],
				String(child_key),
				ids,
			)
		return
	if typeof(value) == TYPE_ARRAY:
		for child_value: Variant in value as Array:
			_collect_identity_ids(child_value, key, ids)
		return
	if typeof(value) != TYPE_STRING:
		return
	var text := String(value).strip_edges()
	if key.ends_with("resident_id") or key.ends_with("resident_ids"):
		if not text.is_empty():
			ids[text] = true
	for id_value: Variant in _ids_in_text(text):
		ids[String(id_value)] = true


func _relationship_entry(text: String, resident_id: String) -> String:
	var normalized := text.replace("\n", "；").replace(";", "；")
	var name := String(_names_by_id.get(resident_id, ""))
	var groups: Array[String] = []
	var current := ""
	for part_value: Variant in normalized.split("；", false):
		var part := String(part_value).strip_edges()
		if part.is_empty():
			continue
		if _contains_any_person_anchor(part) and not current.is_empty():
			groups.append(current)
			current = part
		elif current.is_empty():
			current = part
		else:
			current += "；%s" % part
	if not current.is_empty():
		groups.append(current)
	var entries: Array[String] = []
	for group: String in groups:
		if group.contains(resident_id) or (not name.is_empty() and group.contains(name)):
			entries.append(group)
	return "；".join(entries)


func _contains_any_person_anchor(text: String) -> bool:
	if not _ids_in_text(text).is_empty():
		return true
	for resident_id: Variant in _names_by_id:
		var name := String(_names_by_id.get(resident_id, "")).strip_edges()
		if not name.is_empty() and text.contains(name):
			return true
	return false


func _matter_items(text: String) -> Array[String]:
	var normalized := text.replace("\r", "\n").replace("；", "\n").replace(";", "\n")
	var items: Array[String] = []
	for value: Variant in normalized.split("\n", false):
		var item := String(value).strip_edges()
		if not item.is_empty():
			items.append(item)
	return items


func _has_matching_matter(old_item: String, candidate_text: String) -> bool:
	for candidate_item: String in _matter_items(candidate_text):
		if _topic_overlap(old_item, candidate_item):
			return true
	return false


func _has_resolving_evidence(
	old_item: String,
	fact_records: Array[Dictionary],
) -> bool:
	for record: Dictionary in fact_records:
		var text := _all_text(record)
		if not _contains_completion_cue(text):
			continue
		if _topic_overlap(old_item, text):
			return true
	return false


func _contains_completion_cue(text: String) -> bool:
	for cue: String in COMPLETION_CUES:
		if text.contains(cue):
			return true
	return false


func _topic_overlap(left: String, right: String) -> bool:
	var left_topics := _topic_bigrams(left)
	var right_topics := _topic_bigrams(right)
	for topic: Variant in left_topics:
		if right_topics.has(topic):
			return true
	return false


func _topic_bigrams(text: String) -> Dictionary:
	var normalized := text.to_lower()
	for resident_id: Variant in _names_by_id:
		normalized = normalized.replace(String(resident_id).to_lower(), "")
	for word: String in TOPIC_STOP_WORDS:
		normalized = normalized.replace(word, "")
	var cleaned := ""
	for index in normalized.length():
		var character := normalized.substr(index, 1)
		if character.to_utf8_buffer().size() > 1 or character.is_valid_identifier():
			cleaned += character
	var topics := {}
	if cleaned.length() == 1:
		topics[cleaned] = true
	for index in range(maxi(0, cleaned.length() - 1)):
		topics[cleaned.substr(index, 2)] = true
	return topics


func _all_text(value: Variant) -> String:
	var values: Array[String] = []
	_collect_text(value, values)
	return "\n".join(values)


func _collect_text(value: Variant, values: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for child_value: Variant in (value as Dictionary).values():
			_collect_text(child_value, values)
	elif typeof(value) == TYPE_ARRAY:
		for child_value: Variant in value as Array:
			_collect_text(child_value, values)
	elif typeof(value) == TYPE_STRING:
		var text := String(value).strip_edges()
		if not text.is_empty():
			values.append(text)


func _ids_in_text(text: String) -> Dictionary:
	var ids := {}
	for result: RegExMatch in _id_regex.search_all(text):
		ids[result.get_string()] = true
	return ids


func _normalize_continuity_text(text: String) -> String:
	return (
		text.to_lower()
		.replace(" ", "")
		.replace("\t", "")
		.replace("\n", "")
		.replace("（", "(")
		.replace("）", ")")
		.replace("；", ";")
		.replace("：", ":")
	)


func _index_person(resident_id: String, name: String) -> void:
	if not resident_id.is_empty():
		_names_by_id[resident_id] = name
