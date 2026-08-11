class_name TownSocialRegistry
extends RefCounted


const RESULT_ENVELOPE := preload(
	"res://world/runtime/TownRuntimeResultEnvelope.gd"
)
const SOURCE_KINDS := {
	"place_service_pressure": true,
	"resident_request": true,
	"conversation_commitment": true,
	"animal_attention": true,
	"job_vacancy": true,
	"player_intervention": true,
}

const RESOLVERS := {
	"social.resolve.goal_completed": true,
	"social.resolve.service_reduced": true,
	"social.resolve.source_cleared": true,
	"social.resolve.cancelled": true,
	"social.resolve.expired": true,
	"social.resolve.no_response": true,
}

const CAPABILITIES := {
	"world.go_to_place": {
		"operation": "go",
	},
	"world.escort_person_to_place": {
		"operation": "escort",
	},
	"world.fetch_service_for_person": {
		"operation": "service.fetch",
	},
	"world.perform_activity": {
		"operation": "activity.perform",
	},
	"world.start_conversation": {
		"operation": "conversation.start",
	},
	"world.reply_conversation": {
		"operation": "conversation.reply",
	},
	"world.wait": {
		"operation": "wait",
	},
	"bulletin.publish": {
		"operation": "bulletin.publish",
	},
	"bulletin.read": {
		"operation": "bulletin.read",
	},
	"staffing.apply_assignment": {
		"operation": "staffing.apply_assignment",
	},
}
const CAPABILITY_TARGET_FIELDS := {
	"world.go_to_place": {
		"required": ["place_id"],
		"optional": ["animal_id", "resident_id"],
	},
	"world.escort_person_to_place": {
		"required": ["place_id", "person_id"],
		"optional": [],
	},
	"world.fetch_service_for_person": {
		"required": [
			"person_id", "service_place_id", "service_activity_id", "service_label",
		],
		"optional": [],
	},
	"world.perform_activity": {
		"required": ["place_id", "activity_id"],
		"optional": [],
	},
	"world.start_conversation": {
		"required": ["resident_id"],
		"optional": [],
	},
	"world.reply_conversation": {
		"required": ["conversation_id"],
		"optional": [],
	},
	"world.wait": {
		"required": [],
		"optional": ["minutes", "animal_id", "place_id"],
	},
	"bulletin.publish": {
		"required": ["text"],
		"optional": ["matter_id"],
	},
	"bulletin.read": {
		"required": ["announcement_id"],
		"optional": [],
	},
	"staffing.apply_assignment": {
		"required": ["occupation_id", "assignment_kind"],
		"optional": [
			"from_occupation_id",
			"shift_start_minute",
			"shift_end_minute",
		],
	},
}

const REQUIRED_OPERATIONAL_RESOLVERS := [
	"social.resolve.source_cleared",
	"social.resolve.cancelled",
	"social.resolve.expired",
]


func capability_catalog() -> Dictionary:
	return CAPABILITIES.duplicate(true)


func is_source_kind_registered(source_kind: String) -> bool:
	return SOURCE_KINDS.has(source_kind.strip_edges())


func is_resolver_registered(resolver_id: String) -> bool:
	return RESOLVERS.has(resolver_id.strip_edges())


func is_capability_registered(capability_id: String) -> bool:
	return CAPABILITIES.has(capability_id.strip_edges())


func validate_source_ref(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _failure("SOCIAL_SOURCE_INVALID", "source_state_ref 必须是对象")
	var source_ref := raw_value as Dictionary
	for field in ["source_kind", "source_id", "source_revision"]:
		if not source_ref.has(field):
			return _failure(
				"SOCIAL_SOURCE_INVALID",
				"source_state_ref 缺少 %s" % field,
			)
	var source_kind_value: Variant = source_ref.get("source_kind")
	var source_id_value: Variant = source_ref.get("source_id")
	var source_revision_value: Variant = source_ref.get("source_revision")
	if typeof(source_kind_value) != TYPE_STRING:
		return _failure("SOCIAL_SOURCE_INVALID", "source_kind 必须是字符串")
	if typeof(source_id_value) != TYPE_STRING:
		return _failure("SOCIAL_SOURCE_INVALID", "source_id 必须是字符串")
	if typeof(source_revision_value) != TYPE_INT:
		return _failure("SOCIAL_SOURCE_INVALID", "source_revision 必须是整数")
	var source_kind := String(source_kind_value).strip_edges()
	var source_id := String(source_id_value).strip_edges()
	if not is_source_kind_registered(source_kind):
		return _failure(
			"SOCIAL_SOURCE_UNREGISTERED",
			"未登记的社会事项来源：%s" % source_kind,
		)
	if source_id.is_empty() or int(source_revision_value) < 0:
		return _failure(
			"SOCIAL_SOURCE_INVALID",
			"source_id 和 source_revision 无效",
		)
	return _success({
		"source_kind": source_kind,
		"source_id": source_id,
		"source_revision": int(source_revision_value),
	})


func validate_resolution_rules(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) != TYPE_ARRAY:
		return _failure(
			"SOCIAL_RESOLUTION_RULES_INVALID",
			"resolution_rules 必须是数组",
		)
	var normalized: Array[Dictionary] = []
	var seen := {}
	for rule_value: Variant in raw_value as Array:
		if typeof(rule_value) != TYPE_DICTIONARY:
			return _failure(
				"SOCIAL_RESOLUTION_RULES_INVALID",
				"resolution_rules 只能包含对象",
			)
		var rule := rule_value as Dictionary
		var resolver_value: Variant = rule.get("resolver_id")
		var params_value: Variant = rule.get("params", {})
		if typeof(resolver_value) != TYPE_STRING:
			return _failure(
				"SOCIAL_RESOLUTION_RULES_INVALID",
				"resolver_id 必须是字符串",
			)
		if typeof(params_value) != TYPE_DICTIONARY:
			return _failure(
				"SOCIAL_RESOLUTION_RULES_INVALID",
				"resolver params 必须是对象",
			)
		var resolver_id := String(resolver_value).strip_edges()
		if not is_resolver_registered(resolver_id):
			return _failure(
				"SOCIAL_RESOLVER_UNREGISTERED",
				"未登记的关闭规则：%s" % resolver_id,
			)
		if seen.has(resolver_id):
			continue
		seen[resolver_id] = true
		normalized.append({
			"resolver_id": resolver_id,
			"params": (params_value as Dictionary).duplicate(true),
		})
	for required_resolver: String in REQUIRED_OPERATIONAL_RESOLVERS:
		if seen.has(required_resolver):
			continue
		normalized.append({
			"resolver_id": required_resolver,
			"params": {},
		})
	normalized.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("resolver_id", "")) < String(
				right.get("resolver_id", "")
			)
	)
	return _success(normalized)


func validate_action_goal(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _failure(
			"SOCIAL_ACTION_GOAL_INVALID",
			"action_goal 必须是对象",
		)
	var goal := raw_value as Dictionary
	for field in ["capability_id", "role", "target_refs", "success_result_id"]:
		if not goal.has(field):
			return _failure(
				"SOCIAL_ACTION_GOAL_INVALID",
				"action_goal 缺少 %s" % field,
			)
	var capability_value: Variant = goal.get("capability_id")
	var role_value: Variant = goal.get("role")
	var target_refs_value: Variant = goal.get("target_refs")
	var success_result_value: Variant = goal.get("success_result_id")
	if (
		typeof(capability_value) != TYPE_STRING
		or typeof(role_value) != TYPE_STRING
		or typeof(success_result_value) != TYPE_STRING
		or typeof(target_refs_value) != TYPE_DICTIONARY
	):
		return _failure(
			"SOCIAL_ACTION_GOAL_INVALID",
			"action_goal 字段类型无效",
		)
	var capability_id := String(capability_value).strip_edges()
	var role := String(role_value).strip_edges()
	var success_result_id := String(success_result_value).strip_edges()
	if not is_capability_registered(capability_id):
		return _failure(
			"SOCIAL_CAPABILITY_UNREGISTERED",
			"未登记的行动能力：%s" % capability_id,
		)
	if role.is_empty() or success_result_id.is_empty():
		return _failure(
			"SOCIAL_ACTION_GOAL_INVALID",
			"行动角色和成功结果编号不能为空",
		)
	var target_result := _validate_capability_targets(
		capability_id,
		target_refs_value as Dictionary,
	)
	if not bool(target_result.get("ok", false)):
		return target_result
	var normalized := {
		"goal_id": "",
		"capability_id": capability_id,
		"role": role,
		"target_refs": (
			target_result.get("value", {}) as Dictionary
		).duplicate(true),
		"success_result_id": success_result_id,
	}
	if goal.has("goal_id"):
		if typeof(goal.get("goal_id")) != TYPE_STRING:
			return _failure(
				"SOCIAL_ACTION_GOAL_INVALID",
				"goal_id 必须是字符串",
			)
		normalized["goal_id"] = String(goal.get("goal_id")).strip_edges()
	return _success(normalized)


func _validate_capability_targets(
	capability_id: String,
	target_refs: Dictionary,
) -> Dictionary:
	var contract := CAPABILITY_TARGET_FIELDS.get(
		capability_id,
		{},
	) as Dictionary
	if contract.is_empty():
		return _failure(
			"SOCIAL_CAPABILITY_UNREGISTERED",
			"行动能力没有目标合同：%s" % capability_id,
		)
	var required := contract.get("required", []) as Array
	var optional := contract.get("optional", []) as Array
	for key_value: Variant in target_refs:
		if (
			not key_value is String
			or (
				not required.has(String(key_value))
				and not optional.has(String(key_value))
			)
		):
			return _failure(
				"SOCIAL_ACTION_GOAL_INVALID",
				"%s 包含未登记的目标引用：%s"
				% [capability_id, str(key_value)],
			)
	for field_value: Variant in required:
		var field := String(field_value)
		if (
			not target_refs.has(field)
			or not target_refs.get(field) is String
			or String(target_refs.get(field)).strip_edges().is_empty()
		):
			return _failure(
				"SOCIAL_ACTION_GOAL_INVALID",
				"%s 缺少目标引用 %s" % [capability_id, field],
			)
	var normalized := {}
	for key_value: Variant in target_refs:
		var key := String(key_value)
		var value: Variant = target_refs.get(key)
		if key == "minutes":
			if typeof(value) != TYPE_INT or int(value) <= 0:
				return _failure(
					"SOCIAL_ACTION_GOAL_INVALID",
					"world.wait 的 minutes 必须是正整数",
				)
			normalized[key] = int(value)
			continue
		if (
			not value is String
			or String(value).strip_edges().is_empty()
		):
			return _failure(
				"SOCIAL_ACTION_GOAL_INVALID",
				"%s 的目标引用 %s 必须是非空字符串"
				% [capability_id, key],
			)
		normalized[key] = String(value).strip_edges()
	return _success(normalized)


func _success(value: Variant) -> Dictionary:
	return RESULT_ENVELOPE.success(value)


func _failure(error_code: String, reason: String) -> Dictionary:
	return RESULT_ENVELOPE.failure(error_code, reason)
