class_name TownActionOptionDirectory
extends RefCounted


const RESULT_ENVELOPE := preload(
	"res://world/runtime/TownRuntimeResultEnvelope.gd"
)
const SOCIAL_REGISTRY_SCRIPT := preload(
	"res://world/runtime/social/TownSocialRegistry.gd"
)

const CONTEXT_FIELDS := [
	"context_type",
	"context_id",
	"context_revision",
]
const OPTIONAL_TEXT_FIELDS := [
	"label",
	"reason_summary",
	"execution_summary",
]
const MAX_OPTION_ID_LENGTH := 160

var _capability_registry: RefCounted


func _init(capability_registry: RefCounted = null) -> void:
	_capability_registry = capability_registry
	if _capability_registry == null:
		_capability_registry = SOCIAL_REGISTRY_SCRIPT.new()


func query_options(
	actor_id: String,
	context_ref: Dictionary,
	raw_candidates: Array,
	now_world_minute: int,
	max_options: int,
) -> Dictionary:
	if (
		_capability_registry == null
		or not _capability_registry.has_method("validate_action_goal")
	):
		return _failure(
			"ACTION_OPTION_REGISTRY_INVALID",
			"行动能力登记器不可用",
		)
	var normalized_actor_id := actor_id.strip_edges()
	if normalized_actor_id.is_empty():
		return _failure(
			"ACTION_OPTION_ACTOR_INVALID",
			"actor_id 不能为空",
		)
	if now_world_minute < 0:
		return _failure(
			"ACTION_OPTION_TIME_INVALID",
			"now_world_minute 不能小于零",
		)
	if max_options <= 0:
		return _failure(
			"ACTION_OPTION_LIMIT_INVALID",
			"max_options 必须是正整数",
		)
	var context_result := _normalize_context_ref(context_ref)
	if not bool(context_result.get("ok", false)):
		return context_result
	var normalized_context := (
		context_result.get("value", {}) as Dictionary
	).duplicate(true)
	var accepted: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	for index in raw_candidates.size():
		var candidate_result := _normalize_candidate(
			raw_candidates[index],
			normalized_actor_id,
			normalized_context,
			now_world_minute,
		)
		if not bool(candidate_result.get("ok", false)):
			rejected.append({
				"candidate_index": index,
				"error_code": String(
					candidate_result.get(
						"error_code",
						"ACTION_OPTION_INVALID",
					)
				),
				"reason": String(candidate_result.get("reason", "")),
			})
			continue
		accepted.append(
			(candidate_result.get("value", {}) as Dictionary).duplicate(true)
		)
	accepted.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("option_id", "")) < String(
				right.get("option_id", "")
			)
	)
	var unique: Array[Dictionary] = []
	var option_by_id := {}
	var integrity_seen := {}
	for option in accepted:
		var option_id := String(option.get("option_id", ""))
		var integrity_key := String(option.get("integrity_key", ""))
		if integrity_seen.has(integrity_key):
			continue
		if option_by_id.has(option_id):
			var existing := option_by_id.get(option_id, {}) as Dictionary
			if String(existing.get("integrity_key", "")) != integrity_key:
				rejected.append({
					"candidate_index": -1,
					"error_code": "ACTION_OPTION_ID_COLLISION",
					"reason": "同一 option_id 指向了不同的行动选项：%s" % option_id,
				})
			continue
		option_by_id[option_id] = option
		integrity_seen[integrity_key] = true
		unique.append(option)
	var truncated := unique.size() > max_options
	if truncated:
		unique.resize(max_options)
	return _success({
		"actor_id": normalized_actor_id,
		"context_ref": normalized_context,
		"items": unique,
		"rejected": rejected,
		"truncated": truncated,
		"candidate_count": raw_candidates.size(),
	})


func validate_selection(
	actor_id: String,
	context_ref: Dictionary,
	option_id: String,
	expected_integrity_key: String,
	raw_candidates: Array,
	now_world_minute: int,
	max_options: int,
) -> Dictionary:
	var normalized_option_id := option_id.strip_edges()
	var normalized_integrity_key := expected_integrity_key.strip_edges()
	if normalized_option_id.is_empty() or normalized_integrity_key.is_empty():
		return _failure(
			"ACTION_OPTION_SELECTION_INVALID",
			"option_id 和 integrity_key 不能为空",
		)
	var query_result := query_options(
		actor_id,
		context_ref,
		raw_candidates,
		now_world_minute,
		max_options,
	)
	if not bool(query_result.get("ok", false)):
		return query_result
	var items := (
		query_result.get("value", {}) as Dictionary
	).get("items", []) as Array
	for option_value: Variant in items:
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		if String(option.get("option_id", "")) != normalized_option_id:
			continue
		if (
			String(option.get("integrity_key", ""))
			!= normalized_integrity_key
		):
			return _failure(
				"ACTION_OPTION_CHANGED",
				"行动选项已经变化，需要按最新事实重新选择",
			)
		return _success(option.duplicate(true))
	return _failure(
		"ACTION_OPTION_STALE",
		"行动选项已经过期、失效或不再位于本轮候选中",
	)


func action_goal_from_option(raw_option: Variant) -> Dictionary:
	if (
		_capability_registry == null
		or not _capability_registry.has_method("validate_action_goal")
	):
		return _failure(
			"ACTION_OPTION_REGISTRY_INVALID",
			"行动能力登记器不可用",
		)
	if typeof(raw_option) != TYPE_DICTIONARY:
		return _failure(
			"ACTION_OPTION_INVALID",
			"行动选项必须是对象",
		)
	var option := raw_option as Dictionary
	for field in [
		"option_id",
		"integrity_key",
		"actor_id",
		"context_ref",
		"capability_id",
		"role",
		"target_refs",
		"constraints",
		"result_contract",
		"expires_at_world_minute",
	]:
		if not option.has(field):
			return _failure(
				"ACTION_OPTION_INVALID",
				"行动选项缺少 %s" % field,
			)
	var result_contract_value: Variant = option.get("result_contract")
	if typeof(result_contract_value) != TYPE_DICTIONARY:
		return _failure(
			"ACTION_OPTION_RESULT_INVALID",
			"result_contract 必须是对象",
		)
	var result_contract := result_contract_value as Dictionary
	var success_result_id := String(
		result_contract.get("success_result_id", "")
	).strip_edges()
	var normalized_result := _normalize_candidate(
		option,
		String(option.get("actor_id", "")),
		option.get("context_ref", {}) as Dictionary,
		0,
	)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result
	var normalized_option := (
		normalized_result.get("value", {}) as Dictionary
	)
	if (
		String(normalized_option.get("integrity_key", ""))
		!= String(option.get("integrity_key", ""))
	):
		return _failure(
			"ACTION_OPTION_CHANGED",
			"行动选项内容与完整性编号不一致",
		)
	var goal_result := _capability_registry.validate_action_goal({
			"goal_id": "option-goal:%s:%s" % [
				String(option.get("option_id", "")),
				String(option.get("integrity_key", "")).substr(0, 12),
			],
			"capability_id": String(option.get("capability_id", "")),
			"role": String(option.get("role", "")),
			"target_refs": (
				option.get("target_refs", {}) as Dictionary
			).duplicate(true),
			"success_result_id": success_result_id,
		},) as Dictionary
	if not bool(goal_result.get("ok", false)):
		return goal_result
	return _success(
		(goal_result.get("value", {}) as Dictionary).duplicate(true)
	)


func _normalize_candidate(
	raw_value: Variant,
	actor_id: String,
	context_ref: Dictionary,
	now_world_minute: int,
) -> Dictionary:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _failure(
			"ACTION_OPTION_INVALID",
			"行动候选必须是对象",
		)
	var raw := raw_value as Dictionary
	if raw.has("available") and raw.get("available") != true:
		return _failure(
			"ACTION_OPTION_UNAVAILABLE",
			"行动候选当前不可用",
		)
	if raw.has("known_to_actor") and raw.get("known_to_actor") != true:
		return _failure(
			"ACTION_OPTION_NOT_KNOWN",
			"行动候选不在人物当前知识范围内",
		)
	if raw.has("actor_id"):
		if (
			not raw.get("actor_id") is String
			or String(raw.get("actor_id", "")).strip_edges() != actor_id
		):
			return _failure(
				"ACTION_OPTION_ACTOR_MISMATCH",
				"行动候选不属于当前人物",
			)
	if raw.has("context_ref"):
		if typeof(raw.get("context_ref")) != TYPE_DICTIONARY:
			return _failure(
				"ACTION_OPTION_CONTEXT_INVALID",
				"候选 context_ref 必须是对象",
			)
		var candidate_context_result := _normalize_context_ref(
			raw.get("context_ref") as Dictionary
		)
		if not bool(candidate_context_result.get("ok", false)):
			return candidate_context_result
		if (
			_canonical_json(candidate_context_result.get("value", {}))
			!= _canonical_json(context_ref)
		):
			return _failure(
				"ACTION_OPTION_CONTEXT_MISMATCH",
				"行动候选不属于当前情境",
			)
	var expires_at_world_minute := 0
	if raw.has("expires_at_world_minute"):
		var expiry_value: Variant = raw.get("expires_at_world_minute")
		if not _is_whole_number(expiry_value):
			return _failure(
				"ACTION_OPTION_EXPIRY_INVALID",
				"expires_at_world_minute 必须是整值数字",
			)
		expires_at_world_minute = int(expiry_value)
		if expires_at_world_minute < 0:
			return _failure(
				"ACTION_OPTION_EXPIRY_INVALID",
				"expires_at_world_minute 不能小于零",
			)
	if (
		expires_at_world_minute > 0
		and expires_at_world_minute <= now_world_minute
	):
		return _failure(
			"ACTION_OPTION_EXPIRED",
			"行动候选已经过期",
		)
	var success_result_id := String(
		raw.get("success_result_id", "")
	).strip_edges()
	var result_contract := {}
	if raw.has("result_contract"):
		var contract_result := _normalize_serializable(
			raw.get("result_contract")
		)
		if not bool(contract_result.get("ok", false)):
			return _failure(
				"ACTION_OPTION_RESULT_INVALID",
				String(contract_result.get("reason", "")),
			)
		if typeof(contract_result.get("value")) != TYPE_DICTIONARY:
			return _failure(
				"ACTION_OPTION_RESULT_INVALID",
				"result_contract 必须是对象",
			)
		result_contract = (
			contract_result.get("value", {}) as Dictionary
		).duplicate(true)
		var contract_success := String(
			result_contract.get("success_result_id", "")
		).strip_edges()
		if success_result_id.is_empty():
			success_result_id = contract_success
		elif not contract_success.is_empty() and contract_success != success_result_id:
			return _failure(
				"ACTION_OPTION_RESULT_INVALID",
				"success_result_id 与 result_contract 不一致",
			)
	if success_result_id.is_empty():
		return _failure(
			"ACTION_OPTION_RESULT_INVALID",
			"行动候选缺少 success_result_id",
		)
	result_contract["success_result_id"] = success_result_id
	var target_refs_result := _normalize_serializable(
		raw.get("target_refs")
	)
	if (
		not bool(target_refs_result.get("ok", false))
		or typeof(target_refs_result.get("value")) != TYPE_DICTIONARY
	):
		return _failure(
			"ACTION_OPTION_TARGETS_INVALID",
			"target_refs 必须是可序列化对象",
		)
	var goal_result := _capability_registry.validate_action_goal({
			"capability_id": raw.get("capability_id"),
			"role": raw.get("role"),
			"target_refs": target_refs_result.get("value"),
			"success_result_id": success_result_id,
		},) as Dictionary
	if not bool(goal_result.get("ok", false)):
		return goal_result
	var goal := goal_result.get("value", {}) as Dictionary
	var constraints_result := _normalize_serializable(
		raw.get("constraints", {})
	)
	if not bool(constraints_result.get("ok", false)):
		return _failure(
			"ACTION_OPTION_CONSTRAINTS_INVALID",
			String(constraints_result.get("reason", "")),
		)
	if typeof(constraints_result.get("value")) != TYPE_DICTIONARY:
		return _failure(
			"ACTION_OPTION_CONSTRAINTS_INVALID",
			"constraints 必须是对象",
		)
	var constraints := (
		constraints_result.get("value", {}) as Dictionary
	).duplicate(true)
	var signature_payload := {
		"actor_id": actor_id,
		"context_ref": context_ref,
		"capability_id": String(goal.get("capability_id", "")),
		"role": String(goal.get("role", "")),
		"target_refs": (
			goal.get("target_refs", {}) as Dictionary
		).duplicate(true),
		"constraints": constraints,
		"result_contract": result_contract,
		"expires_at_world_minute": expires_at_world_minute,
	}
	var integrity_key := _canonical_json(signature_payload).sha256_text()
	var option_id := "action:%s" % integrity_key.substr(0, 24)
	if raw.has("option_id"):
		if not raw.get("option_id") is String:
			return _failure(
				"ACTION_OPTION_ID_INVALID",
				"option_id 必须是字符串",
			)
		option_id = String(raw.get("option_id", "")).strip_edges()
		if (
			option_id.is_empty()
			or option_id.length() > MAX_OPTION_ID_LENGTH
			or option_id.contains("\n")
			or option_id.contains("\r")
		):
			return _failure(
				"ACTION_OPTION_ID_INVALID",
				"option_id 为空、过长或包含换行",
			)
	var normalized := {
		"option_id": option_id,
		"integrity_key": integrity_key,
		"actor_id": actor_id,
		"context_ref": context_ref.duplicate(true),
		"capability_id": String(goal.get("capability_id", "")),
		"role": String(goal.get("role", "")),
		"target_refs": (
			goal.get("target_refs", {}) as Dictionary
		).duplicate(true),
		"constraints": constraints,
		"result_contract": result_contract,
		"expires_at_world_minute": expires_at_world_minute,
	}
	for field in OPTIONAL_TEXT_FIELDS:
		if not raw.has(field):
			continue
		if not raw.get(field) is String:
			return _failure(
				"ACTION_OPTION_TEXT_INVALID",
				"%s 必须是字符串" % field,
			)
		normalized[field] = String(raw.get(field, "")).strip_edges()
	return _success(normalized)


func _normalize_context_ref(raw: Dictionary) -> Dictionary:
	for field in CONTEXT_FIELDS:
		if not raw.has(field):
			return _failure(
				"ACTION_OPTION_CONTEXT_INVALID",
				"context_ref 缺少 %s" % field,
			)
	if (
		not raw.get("context_type") is String
		or not raw.get("context_id") is String
		or not _is_whole_number(raw.get("context_revision"))
	):
		return _failure(
			"ACTION_OPTION_CONTEXT_INVALID",
			"context_ref 字段类型无效",
		)
	var context_type := String(raw.get("context_type", "")).strip_edges()
	var context_id := String(raw.get("context_id", "")).strip_edges()
	var context_revision := int(raw.get("context_revision", -1))
	if context_type.is_empty() or context_id.is_empty() or context_revision < 0:
		return _failure(
			"ACTION_OPTION_CONTEXT_INVALID",
			"context_ref 字段不能为空且修订不能小于零",
		)
	return _success({
		"context_type": context_type,
		"context_id": context_id,
		"context_revision": context_revision,
	})


func _normalize_serializable(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return _success(value)
		TYPE_FLOAT:
			var number := float(value)
			if is_nan(number) or is_inf(number):
				return _failure(
					"ACTION_OPTION_NOT_SERIALIZABLE",
					"浮点数必须是有限值",
				)
			if number == floor(number):
				return _success(int(number))
			return _success(number)
		TYPE_ARRAY:
			var normalized_array: Array = []
			for item: Variant in value as Array:
				var item_result := _normalize_serializable(item)
				if not bool(item_result.get("ok", false)):
					return item_result
				normalized_array.append(item_result.get("value"))
			return _success(normalized_array)
		TYPE_DICTIONARY:
			var source := value as Dictionary
			var keys: Array[String] = []
			for key_value: Variant in source:
				if not key_value is String:
					return _failure(
						"ACTION_OPTION_NOT_SERIALIZABLE",
						"对象键必须是字符串",
					)
				keys.append(String(key_value))
			keys.sort()
			var normalized_dictionary := {}
			for key in keys:
				var entry_result := _normalize_serializable(source.get(key))
				if not bool(entry_result.get("ok", false)):
					return entry_result
				normalized_dictionary[key] = entry_result.get("value")
			return _success(normalized_dictionary)
	return _failure(
		"ACTION_OPTION_NOT_SERIALIZABLE",
		"行动选项只能保存 JSON 可序列化数据",
	)


func _canonical_json(value: Variant) -> String:
	var normalized_result := _normalize_serializable(value)
	if not bool(normalized_result.get("ok", false)):
		return ""
	return JSON.stringify(normalized_result.get("value"))


func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number) and number == floor(number)


func _success(value: Variant) -> Dictionary:
	return RESULT_ENVELOPE.success(value)


func _failure(error_code: String, reason: String) -> Dictionary:
	return RESULT_ENVELOPE.failure(error_code, reason)
