class_name TownActionOptionSourceAdapter
extends RefCounted


const RESULT_ENVELOPE := preload(
	"res://world/runtime/TownRuntimeResultEnvelope.gd"
)
func adapt_legacy_options(
	actor_id: String,
	context_ref: Dictionary,
	raw_options: Array,
	default_role: String,
	expires_at_world_minute: int = 0,
) -> Dictionary:
	var common_error := _validate_common(
		actor_id,
		context_ref,
		default_role,
		expires_at_world_minute,
	)
	if not common_error.is_empty():
		return common_error
	var candidates: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	for index in raw_options.size():
		var result := _legacy_candidate(
			raw_options[index],
			actor_id.strip_edges(),
			context_ref,
			default_role.strip_edges(),
			expires_at_world_minute,
		)
		_collect_result(index, result, candidates, rejected)
	return _success({
		"candidates": candidates,
		"rejected": rejected,
	})


func adapt_action_goals(
	actor_id: String,
	context_ref: Dictionary,
	raw_entries: Array,
	expires_at_world_minute: int = 0,
) -> Dictionary:
	var common_error := _validate_common(
		actor_id,
		context_ref,
		"action-goal",
		expires_at_world_minute,
	)
	if not common_error.is_empty():
		return common_error
	var candidates: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	for index in raw_entries.size():
		var result := _action_goal_candidate(
			raw_entries[index],
			actor_id.strip_edges(),
			context_ref,
			expires_at_world_minute,
		)
		_collect_result(index, result, candidates, rejected)
	return _success({
		"candidates": candidates,
		"rejected": rejected,
	})


func _legacy_candidate(
	raw_value: Variant,
	actor_id: String,
	context_ref: Dictionary,
	default_role: String,
	default_expiry: int,
) -> Dictionary:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _failure(
			"ACTION_OPTION_SOURCE_INVALID",
			"旧行动选项必须是对象",
		)
	var raw := raw_value as Dictionary
	var role := default_role
	if raw.has("role"):
		if not raw.get("role") is String:
			return _failure(
				"ACTION_OPTION_SOURCE_INVALID",
				"旧行动选项 role 必须是字符串",
			)
		role = String(raw.get("role", "")).strip_edges()
	return _candidate_from_parts(
		raw,
		actor_id,
		context_ref,
		String(raw.get("capability_id", "")),
		role,
		raw.get("target_refs"),
		String(raw.get("success_result_id", "")),
		default_expiry,
	)


func _action_goal_candidate(
	raw_value: Variant,
	actor_id: String,
	context_ref: Dictionary,
	default_expiry: int,
) -> Dictionary:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _failure(
			"ACTION_OPTION_SOURCE_INVALID",
			"行动目标来源必须是对象",
		)
	var entry := raw_value as Dictionary
	if typeof(entry.get("action_goal")) != TYPE_DICTIONARY:
		return _failure(
			"ACTION_OPTION_SOURCE_GOAL_INVALID",
			"行动目标来源缺少 action_goal",
		)
	var goal := entry.get("action_goal") as Dictionary
	return _candidate_from_parts(
		entry,
		actor_id,
		context_ref,
		String(goal.get("capability_id", "")),
		String(goal.get("role", "")),
		goal.get("target_refs"),
		String(goal.get("success_result_id", "")),
		default_expiry,
	)


func _candidate_from_parts(
	source: Dictionary,
	actor_id: String,
	context_ref: Dictionary,
	capability_id: String,
	role: String,
	target_refs_value: Variant,
	success_result_id: String,
	default_expiry: int,
) -> Dictionary:
	var option_id_value: Variant = source.get("option_id")
	if not option_id_value is String or String(option_id_value).strip_edges().is_empty():
		return _failure(
			"ACTION_OPTION_SOURCE_ID_INVALID",
			"行动来源缺少稳定 option_id",
		)
	if (
		capability_id.strip_edges().is_empty()
		or role.strip_edges().is_empty()
		or success_result_id.strip_edges().is_empty()
		or typeof(target_refs_value) != TYPE_DICTIONARY
	):
		return _failure(
			"ACTION_OPTION_SOURCE_GOAL_INVALID",
			"行动来源缺少能力、角色、目标或结果",
		)
	var constraints_value: Variant = source.get("constraints", {})
	if typeof(constraints_value) != TYPE_DICTIONARY:
		return _failure(
			"ACTION_OPTION_SOURCE_CONSTRAINTS_INVALID",
			"行动来源 constraints 必须是对象",
		)
	var expiry := default_expiry
	if source.has("expires_at_world_minute"):
		if typeof(source.get("expires_at_world_minute")) != TYPE_INT:
			return _failure(
				"ACTION_OPTION_SOURCE_EXPIRY_INVALID",
				"行动来源期限必须是整数",
			)
		expiry = int(source.get("expires_at_world_minute", 0))
	if expiry < 0:
		return _failure(
			"ACTION_OPTION_SOURCE_EXPIRY_INVALID",
			"行动来源期限不能小于零",
		)
	var candidate := {
		"option_id": String(option_id_value).strip_edges(),
		"actor_id": actor_id,
		"context_ref": context_ref.duplicate(true),
		"capability_id": capability_id.strip_edges(),
		"role": role.strip_edges(),
		"target_refs": (target_refs_value as Dictionary).duplicate(true),
		"constraints": (constraints_value as Dictionary).duplicate(true),
		"success_result_id": success_result_id.strip_edges(),
		"expires_at_world_minute": expiry,
	}
	var label_value: Variant = source.get(
		"label",
		source.get("meaning", ""),
	)
	if not label_value is String:
		return _failure(
			"ACTION_OPTION_SOURCE_TEXT_INVALID",
			"行动来源说明必须是字符串",
		)
	var label := String(label_value).strip_edges()
	if not label.is_empty():
		candidate["label"] = label
	for flag in ["available", "known_to_actor"]:
		if not source.has(flag):
			continue
		if typeof(source.get(flag)) != TYPE_BOOL:
			return _failure(
				"ACTION_OPTION_SOURCE_FLAG_INVALID",
				"行动来源 %s 必须是布尔值" % flag,
			)
		candidate[flag] = bool(source.get(flag))
	return _success(candidate)


func _validate_common(
	actor_id: String,
	context_ref: Dictionary,
	role: String,
	expires_at_world_minute: int,
) -> Dictionary:
	if actor_id.strip_edges().is_empty():
		return _failure(
			"ACTION_OPTION_SOURCE_ACTOR_INVALID",
			"actor_id 不能为空",
		)
	if context_ref.is_empty():
		return _failure(
			"ACTION_OPTION_SOURCE_CONTEXT_INVALID",
			"context_ref 不能为空",
		)
	if role.strip_edges().is_empty():
		return _failure(
			"ACTION_OPTION_SOURCE_ROLE_INVALID",
			"默认行动角色不能为空",
		)
	if expires_at_world_minute < 0:
		return _failure(
			"ACTION_OPTION_SOURCE_EXPIRY_INVALID",
			"默认行动期限不能小于零",
		)
	return {}


func _collect_result(
	index: int,
	result: Dictionary,
	candidates: Array[Dictionary],
	rejected: Array[Dictionary],
) -> void:
	if bool(result.get("ok", false)):
		candidates.append(
			(result.get("value", {}) as Dictionary).duplicate(true)
		)
		return
	rejected.append({
		"source_index": index,
		"error_code": String(
			result.get("error_code", "ACTION_OPTION_SOURCE_INVALID")
		),
		"reason": String(result.get("reason", "")),
	})


func _success(value: Variant) -> Dictionary:
	return RESULT_ENVELOPE.success(value)


func _failure(error_code: String, reason: String) -> Dictionary:
	return RESULT_ENVELOPE.failure(error_code, reason)
