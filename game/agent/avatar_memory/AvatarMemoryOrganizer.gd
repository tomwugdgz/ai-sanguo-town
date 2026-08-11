class_name AgentAvatarMemoryOrganizer
extends RefCounted


const AgentJsonScript := preload("res://agent/AgentJson.gd")
const PromptTextScript := preload("res://agent/prompt/PromptText.gd")
const RULE_PROMPTS := [
	"res://prompts/rules/10_identity_and_knowledge.md",
	"res://prompts/rules/20_behavior_and_expression.md",
	"res://prompts/rules/30_data_authority.md",
	"res://prompts/rules/35_events_and_results.md",
]
const BACKGROUND_PROMPTS := [
	"res://prompts/background/10_town_common_knowledge.md",
]
const ORGANIZER_PROMPT := (
	"res://prompts/avatar_memory/10_avatar_memory_organizer.md"
)

# 提示词文件是静态内容，进程级缓存；组装结果按实例缓存（身份字段不变）。
static var _prompt_text_cache: Dictionary = {}

var _initialization: Dictionary
var _resident_id: String
var _resident_name: String
var _avatar_person_id: String
var _avatar_name: String
var _store: RefCounted
var _system_prompt_cache := ""


func _init(
	initialization: Dictionary,
	avatar_person_id: String,
	avatar_name: String,
	store: RefCounted,
) -> void:
	# initialization 为共享只读数据（约定不可变），各组件持引用不再各存深拷贝。
	_initialization = initialization
	var me := _initialization.get("me", {}) as Dictionary
	_resident_id = String(me.get("resident_id", ""))
	_resident_name = String(
		(me.get("attributes", {}) as Dictionary).get("name", ""),
	)
	_avatar_person_id = avatar_person_id
	_avatar_name = avatar_name
	_store = store


func build_request(
	old_memory: Dictionary,
	evidence_items: Array,
	retry_feedback: String = "",
) -> Dictionary:
	var old_validation := _store.call("validate", old_memory) as Dictionary
	if not bool(old_validation.get("ok", false)):
		return old_validation
	var system_result := _build_system_prompt()
	if not bool(system_result.get("ok", false)):
		return system_result
	var old_for_model := (old_validation["memory"] as Dictionary).duplicate(true)
	old_for_model.erase("state_version")
	old_for_model.erase("resident_id")
	old_for_model.erase("avatar_person_id")
	old_for_model.erase("revision")
	var sections: Array[String] = [
		"[旧化身记忆]\n%s"
		% PromptTextScript.escape_dynamic(
			JSON.stringify(old_for_model, "  ", true),
		),
		"[近期候选证据]\n%s"
		% PromptTextScript.escape_dynamic(
			JSON.stringify(evidence_items, "  ", true),
		),
	]
	if not retry_feedback.strip_edges().is_empty():
		sections.append(
			"[重试要求]\n%s"
			% PromptTextScript.escape_dynamic(retry_feedback),
		)
	return {
		"ok": true,
		"request_kind": "avatar_memory_organization",
		"max_tokens": 4096,
		"old_memory": old_validation["memory"],
		"evidence_items": evidence_items.duplicate(true),
		"messages": [
			{"role": "system", "content": system_result["content"]},
			{"role": "user", "content": "\n\n".join(sections)},
		],
	}


func build_retry_request(
	old_memory: Dictionary,
	evidence_items: Array,
	validation: Dictionary,
) -> Dictionary:
	var feedback := (
		"上次输出没有通过检查。请只根据旧记忆和候选证据修正，"
		+ "返回完整 JSON，不要解释。\n问题：%s"
	) % "；".join(validation.get("errors", []))
	var result := build_request(old_memory, evidence_items, feedback)
	if bool(result.get("ok", false)):
		result["retry_attempt"] = 1
	return result


func validate_candidate(
	candidate: Variant,
	old_memory: Dictionary,
	evidence_items: Array,
) -> Dictionary:
	if typeof(candidate) != TYPE_DICTIONARY:
		return _candidate_failure("化身记忆整理结果必须是对象")
	var output := candidate as Dictionary
	if not _has_exact_fields(
		output,
		["summary", "memories", "open_loops", "message_updates"],
	):
		return _candidate_failure("化身记忆整理结果字段不完整或包含未知字段")
	if (
		typeof(output.get("summary")) != TYPE_STRING
		or typeof(output.get("memories")) != TYPE_ARRAY
		or typeof(output.get("open_loops")) != TYPE_ARRAY
		or typeof(output.get("message_updates")) != TYPE_ARRAY
	):
		return _candidate_failure("化身记忆整理结果字段类型损坏")
	var old_validation := _store.call("validate", old_memory) as Dictionary
	if not bool(old_validation.get("ok", false)):
		return old_validation
	var canonical_old := old_validation["memory"] as Dictionary
	var source_refs := _valid_source_refs(canonical_old, evidence_items)
	var old_memories := _items_by_id(
		canonical_old.get("memories", []) as Array,
		"memory_id",
	)
	var old_loops := _items_by_id(
		canonical_old.get("open_loops", []) as Array,
		"loop_id",
	)
	var used_ids := {}
	var next_memories: Array[Dictionary] = []
	for index in (output["memories"] as Array).size():
		var normalized := _normalize_sourced_item(
			(output["memories"] as Array)[index],
			"memory",
			index,
			old_memories,
			source_refs,
			used_ids,
			int(canonical_old.get("revision", 0)) + 1,
		)
		if not bool(normalized.get("ok", false)):
			return normalized
		next_memories.append(normalized["item"])
	var next_loops: Array[Dictionary] = []
	for index in (output["open_loops"] as Array).size():
		var normalized := _normalize_sourced_item(
			(output["open_loops"] as Array)[index],
			"loop",
			index,
			old_loops,
			source_refs,
			used_ids,
			int(canonical_old.get("revision", 0)) + 1,
		)
		if not bool(normalized.get("ok", false)):
			return normalized
		next_loops.append(normalized["item"])
	var loop_ids := _items_by_id(next_loops, "loop_id")
	for loop_id: Variant in old_loops:
		var old_loop := old_loops[loop_id] as Dictionary
		if (
			["active", "disputed"].has(
				String(old_loop.get("status", "")),
			)
			and not loop_ids.has(loop_id)
		):
			return _candidate_failure(
				"未解决事项不能在没有明确结果时消失：%s" % loop_id,
			)
	var messages_result := _apply_message_updates(
		canonical_old.get("sent_messages", []) as Array,
		output["message_updates"] as Array,
	)
	if not bool(messages_result.get("ok", false)):
		return messages_result
	var next_state := {
		"state_version": int(canonical_old["state_version"]),
		"resident_id": _resident_id,
		"avatar_person_id": _avatar_person_id,
		"summary": String(output["summary"]).strip_edges(),
		"memories": next_memories,
			"open_loops": next_loops,
			"sent_messages": messages_result["messages"],
			"revision": int(canonical_old.get("revision", 0)) + 1,
			"departure_screening": (
				canonical_old.get("departure_screening", {}) as Dictionary
			).duplicate(true),
		}
	var validation := _store.call("validate", next_state) as Dictionary
	if not bool(validation.get("ok", false)):
		var result := validation.duplicate(true)
		result["retryable"] = true
		return result
	return {
		"ok": true,
		"memory": (validation["memory"] as Dictionary).duplicate(true),
	}


func _normalize_sourced_item(
	value: Variant,
	kind: String,
	index: int,
	old_items: Dictionary,
	valid_refs: Dictionary,
	used_ids: Dictionary,
	next_revision: int,
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _candidate_failure("化身%s第 %d 项必须是对象" % [kind, index])
	var raw := value as Dictionary
	var common_fields := [
		"content",
		"world_time",
		"source_type",
		"source_person_id",
		"source_refs",
		"status",
		"salience",
	]
	var id_field := "memory_id" if kind == "memory" else "loop_id"
	var expected := common_fields.duplicate()
	expected.append(id_field)
	if kind == "loop":
		expected.append_array(["people", "progress"])
	for key: Variant in raw:
		if not expected.has(key):
			return _candidate_failure(
				"化身%s第 %d 项包含未知字段：%s" % [kind, index, key],
			)
	for field_name: String in common_fields:
		if not raw.has(field_name):
			return _candidate_failure(
				"化身%s第 %d 项缺少 %s" % [kind, index, field_name],
			)
	if (
		typeof(raw.get("content")) != TYPE_STRING
		or String(raw.get("content")).strip_edges().is_empty()
		or typeof(raw.get("world_time")) != TYPE_DICTIONARY
		or typeof(raw.get("source_type")) != TYPE_STRING
		or typeof(raw.get("source_person_id")) != TYPE_STRING
		or typeof(raw.get("status")) != TYPE_STRING
		or typeof(raw.get("salience")) != TYPE_INT
		or (
			raw.has(id_field)
			and typeof(raw.get(id_field)) != TYPE_STRING
		)
	):
		return _candidate_failure(
			"化身%s第 %d 项字段类型损坏" % [kind, index],
		)
	var refs_value: Variant = raw.get("source_refs")
	if typeof(refs_value) != TYPE_ARRAY or (refs_value as Array).is_empty():
		return _candidate_failure("化身%s第 %d 项缺少来源" % [kind, index])
	var refs: Array[String] = []
	for ref_value: Variant in refs_value as Array:
		var ref := String(ref_value).strip_edges()
		if (
			typeof(ref_value) != TYPE_STRING
			or ref.is_empty()
			or refs.has(ref)
			or not valid_refs.has(ref)
		):
			return _candidate_failure(
				"化身%s第 %d 项引用了未知或重复来源" % [kind, index],
			)
		refs.append(ref)
	refs.sort()
	var item_id := String(raw.get(id_field, "")).strip_edges()
	if not item_id.is_empty() and not old_items.has(item_id):
		return _candidate_failure(
			"化身%s第 %d 项不能自行创建编号" % [kind, index],
		)
	if item_id.is_empty():
		item_id = _new_item_id(kind, raw, refs, next_revision, used_ids)
	if used_ids.has(item_id):
		return _candidate_failure("化身记忆条目编号重复：%s" % item_id)
	used_ids[item_id] = true
	var normalized := {
		id_field: item_id,
		"content": String(raw.get("content", "")).strip_edges(),
		"world_time": (raw.get("world_time", {}) as Dictionary).duplicate(true),
		"source_type": String(raw.get("source_type", "")),
		"source_person_id": String(
			raw.get("source_person_id", ""),
		).strip_edges(),
		"source_refs": refs,
		"status": String(raw.get("status", "")),
		"salience": int(raw.get("salience", 0)),
	}
	if kind == "loop":
		if (
			typeof(raw.get("people")) != TYPE_ARRAY
			or typeof(raw.get("progress")) != TYPE_STRING
		):
			return _candidate_failure("化身未解决事项第 %d 项类型损坏" % index)
		normalized["people"] = (raw["people"] as Array).duplicate()
		normalized["progress"] = String(raw["progress"]).strip_edges()
	return {"ok": true, "item": normalized}


func _apply_message_updates(
	old_messages: Array,
	updates: Array,
) -> Dictionary:
	var by_id := _items_by_id(old_messages, "message_id")
	var updated := {}
	for index in updates.size():
		if typeof(updates[index]) != TYPE_DICTIONARY:
			return _candidate_failure("留言状态更新第 %d 项必须是对象" % index)
		var update := updates[index] as Dictionary
		if not _has_exact_fields(update, ["message_id", "status"]):
			return _candidate_failure("留言状态更新第 %d 项字段损坏" % index)
		var message_id := String(update.get("message_id", ""))
		var status := String(update.get("status", ""))
		if (
			not by_id.has(message_id)
			or updated.has(message_id)
			or not ["acknowledged", "resolved"].has(status)
		):
			return _candidate_failure("留言状态更新第 %d 项内容损坏" % index)
		updated[message_id] = status
	var messages: Array[Dictionary] = []
	for value: Variant in old_messages:
		var message := (value as Dictionary).duplicate(true)
		var message_id := String(message.get("message_id", ""))
		if updated.has(message_id):
			message["status"] = updated[message_id]
		messages.append(message)
	return {"ok": true, "messages": messages}


func _valid_source_refs(
	old_memory: Dictionary,
	evidence_items: Array,
) -> Dictionary:
	var refs := {}
	for value: Variant in evidence_items:
		if typeof(value) == TYPE_DICTIONARY:
			var ref := String((value as Dictionary).get("source_ref", ""))
			if not ref.is_empty():
				refs[ref] = true
	for field_name: String in ["memories", "open_loops"]:
		for value: Variant in old_memory.get(field_name, []) as Array:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			for ref_value: Variant in (
				(value as Dictionary).get("source_refs", []) as Array
			):
				refs[String(ref_value)] = true
	return refs


func _items_by_id(items: Array, id_field: String) -> Dictionary:
	var result := {}
	for value: Variant in items:
		if typeof(value) == TYPE_DICTIONARY:
			var item := value as Dictionary
			result[String(item.get(id_field, ""))] = item.duplicate(true)
	return result


func _new_item_id(
	kind: String,
	raw: Dictionary,
	refs: Array[String],
	revision: int,
	used_ids: Dictionary,
) -> String:
	var digest := AgentJsonScript.content_sha256({
		"resident_id": _resident_id,
		"kind": kind,
		"content": raw.get("content"),
		"source_refs": refs,
		"revision": revision,
	})
	var prefix := "avatar-memory" if kind == "memory" else "avatar-loop"
	var candidate := "%s-%s" % [prefix, digest.left(20)]
	var suffix := 1
	while used_ids.has(candidate):
		candidate = "%s-%s-%d" % [prefix, digest.left(16), suffix]
		suffix += 1
	return candidate


func _build_system_prompt() -> Dictionary:
	if not _system_prompt_cache.is_empty():
		return {"ok": true, "content": _system_prompt_cache}
	var sections: Array[String] = []
	for path: String in RULE_PROMPTS + BACKGROUND_PROMPTS + [ORGANIZER_PROMPT]:
		var read_result := _read_text(path)
		if not bool(read_result.get("ok", false)):
			return read_result
		sections.append(String(read_result["content"]).strip_edges())
	sections.append("""## 本次固定身份

居民本人：%s（%s）
化身：%s（%s）""" % [
		PromptTextScript.escape_dynamic(_resident_name),
		PromptTextScript.escape_dynamic(_resident_id),
		PromptTextScript.escape_dynamic(_avatar_name),
		PromptTextScript.escape_dynamic(_avatar_person_id),
	])
	_system_prompt_cache = "\n\n".join(sections)
	return {"ok": true, "content": _system_prompt_cache}


func _read_text(path: String) -> Dictionary:
	if _prompt_text_cache.has(path):
		return {"ok": true, "content": _prompt_text_cache[path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["无法读取化身记忆提示词：%s" % path]}
	var content := file.get_as_text().strip_edges()
	file = null
	if content.is_empty():
		return {"ok": false, "errors": ["化身记忆提示词为空：%s" % path]}
	_prompt_text_cache[path] = content
	return {"ok": true, "content": content}


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_name: Variant in fields:
		if not value.has(field_name):
			return false
	return true


func _candidate_failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "retryable": true}
