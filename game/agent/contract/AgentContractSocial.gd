class_name AgentContractSocial
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


static func _validate_social_response_results(
	results: Array,
	errors: Array[String],
) -> void:
	var response_ids := {}
	for index in results.size():
		var path := "social_response_results[%d]" % index
		var value: Variant = results[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s 必须是对象" % path)
			continue
		var result := value as Dictionary
		AgentContractIdentity._validate_allowed_fields(
			result,
			[
				"response_id",
				"matter_id",
				"status",
				"role",
				"action_goal_id",
				"reason",
			],
			path,
			errors,
		)
		var response_id := AgentContract._require_non_empty_string(
			result,
			"response_id",
			"%s.response_id" % path,
			errors,
		)
		if not response_id.is_empty() and response_ids.has(response_id):
			errors.append("%s.response_id 在本次回执中重复" % path)
		response_ids[response_id] = true
		AgentContract._require_string(
			result,
			"matter_id",
			"%s.matter_id" % path,
			errors,
		)
		var status := AgentContract._require_non_empty_string(
			result,
			"status",
			"%s.status" % path,
			errors,
		)
		if (
			not status.is_empty()
			and status not in AgentContract.SOCIAL_RESPONSE_RESULT_STATUSES
		):
			errors.append("%s.status 不是合法社会回应结果" % path)
		AgentContract._require_string(result, "role", "%s.role" % path, errors)
		AgentContract._require_string(
			result,
			"action_goal_id",
			"%s.action_goal_id" % path,
			errors,
		)
		AgentContract._require_non_empty_string(
			result,
			"reason",
			"%s.reason" % path,
			errors,
		)


static func _validate_social_exposures(
	exposures: Array,
	errors: Array[String],
) -> void:
	if exposures.size() > 1:
		errors.append("snapshot.social_exposures 每轮最多一项")
	for index in exposures.size():
		var path := "snapshot.social_exposures[%d]" % index
		var value: Variant = exposures[index]
		if not value is Dictionary:
			errors.append("%s 必须是对象" % path)
			continue
		var exposure := value as Dictionary
		AgentContractIdentity._validate_allowed_fields(
			exposure,
			[
				"exposure_id",
				"matter_id",
				"matter_revision",
				"channel",
				"clue",
				"source_id",
				"created_at",
				"expires_at",
				"status",
				"reconsider_at",
				"handled_at",
				"resident_id",
				"options",
			],
			path,
			errors,
		)
		for field in [
			"exposure_id",
			"matter_id",
			"channel",
			"clue",
		]:
			AgentContract._require_non_empty_string(
				exposure,
				field,
				"%s.%s" % [path, field],
				errors,
			)
		if (
			typeof(exposure.get("matter_revision")) != TYPE_INT
			or int(exposure.get("matter_revision", -1)) < 0
		):
			errors.append("%s.matter_revision 必须是非负整数" % path)
		if (
			typeof(exposure.get("expires_at")) != TYPE_INT
			or int(exposure.get("expires_at", -1)) < 0
		):
			errors.append("%s.expires_at 必须是非负整数" % path)
		var options := AgentContract._require_array(
			exposure,
			"options",
			"%s.options" % path,
			errors,
		)
		for option_value: Variant in options:
			if (
				not option_value is String
				or String(option_value) not in [
					"notice",
					"ignore",
					"defer",
				]
			):
				errors.append("%s.options 包含未登记选项" % path)


static func _validate_social_matters(
	matters: Array,
	errors: Array[String],
) -> void:
	var matter_ids := {}
	for index in matters.size():
		var path := "snapshot.social_matters[%d]" % index
		var value: Variant = matters[index]
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("%s 必须是对象" % path)
			continue
		var matter := value as Dictionary
		AgentContractIdentity._validate_allowed_fields(
			matter,
			[
				"matter_id",
				"revision",
				"kind",
				"summary",
				"expires_at",
				"response_round_id",
				"response_window_until",
				"options",
				"assignment",
				],
			path,
			errors,
		)
		var matter_id := AgentContract._require_non_empty_string(
			matter,
			"matter_id",
			"%s.matter_id" % path,
			errors,
		)
		if not matter_id.is_empty() and matter_ids.has(matter_id):
			errors.append("%s.matter_id 在本次快照中重复" % path)
		matter_ids[matter_id] = true
		if (
			typeof(matter.get("revision")) != TYPE_INT
			or int(matter.get("revision", -1)) < 0
		):
			errors.append("%s.revision 必须是非负整数" % path)
		AgentContract._require_non_empty_string(
			matter,
			"kind",
			"%s.kind" % path,
			errors,
		)
		AgentContract._require_non_empty_string(
			matter,
			"summary",
			"%s.summary" % path,
			errors,
		)
		if (
			typeof(matter.get("expires_at")) != TYPE_INT
			or int(matter.get("expires_at", -1)) < 0
		):
			errors.append("%s.expires_at 必须是非负整数" % path)
		if (
			matter.get("response_round_id") != null
			and typeof(matter.get("response_round_id")) != TYPE_STRING
		):
			errors.append("%s.response_round_id 必须是文本或 null" % path)
		if (
			matter.get("response_window_until") != null
			and typeof(matter.get("response_window_until")) != TYPE_INT
		):
			errors.append(
				"%s.response_window_until 必须是整数或 null" % path
			)
		var options := AgentContract._require_array(
			matter,
			"options",
			"%s.options" % path,
			errors,
		)
		var option_ids := {}
		for option_index in options.size():
			var option_path := "%s.options[%d]" % [path, option_index]
			var option_value: Variant = options[option_index]
			if typeof(option_value) != TYPE_DICTIONARY:
				errors.append("%s 必须是对象" % option_path)
				continue
			var option := option_value as Dictionary
			AgentContractIdentity._validate_allowed_fields(
				option,
				[
					"option_id",
					"response_kind",
					"meaning",
					"allows_public_text",
				],
				option_path,
				errors,
			)
			var option_id := AgentContract._require_non_empty_string(
				option,
				"option_id",
				"%s.option_id" % option_path,
				errors,
			)
			if not option_id.is_empty() and option_ids.has(option_id):
				errors.append("%s.option_id 重复" % option_path)
			option_ids[option_id] = true
			AgentContract._require_non_empty_string(
				option,
				"meaning",
				"%s.meaning" % option_path,
				errors,
			)
			if option.has("response_kind"):
				var response_kind := AgentContract._require_non_empty_string(
					option,
					"response_kind",
					"%s.response_kind" % option_path,
					errors,
				)
				if response_kind not in [
					"accept",
					"reject",
					"defer",
					"withdraw",
				]:
					errors.append(
						"%s.response_kind 未登记" % option_path
					)
			if typeof(option.get("allows_public_text")) != TYPE_BOOL:
				errors.append(
					"%s.allows_public_text 必须是布尔值" % option_path
				)
		if (
			not options.is_empty()
			and (
				matter.get("response_round_id") == null
				or matter.get("response_window_until") == null
			)
		):
			errors.append("%s 有回应选项但缺少当前回应轮次" % path)
		_validate_social_assignment(
			matter.get("assignment"),
			"%s.assignment" % path,
			errors,
		)


static func _validate_social_assignment(
	value: Variant,
	path: String,
	errors: Array[String],
) -> void:
	if value == null:
		return
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s 必须是对象或 null" % path)
		return
	var assignment := value as Dictionary
	AgentContractIdentity._validate_allowed_fields(
		assignment,
		[
			"goal_id",
			"role",
			"status",
			"capability_id",
			"target_refs",
			"success_result_id",
		],
		path,
		errors,
	)
	for field in [
		"goal_id",
		"role",
		"capability_id",
		"success_result_id",
	]:
		AgentContract._require_non_empty_string(
			assignment,
			field,
			"%s.%s" % [path, field],
			errors,
		)
	var status := AgentContract._require_non_empty_string(
		assignment,
		"status",
		"%s.status" % path,
		errors,
	)
	if not status.is_empty() and status not in ["assigned", "executing"]:
		errors.append("%s.status 不是合法履约状态" % path)
	var target_refs := AgentContract._require_dictionary(
		assignment,
		"target_refs",
		"%s.target_refs" % path,
		errors,
	)
	for key_value: Variant in target_refs:
		var target_path := "%s.target_refs.%s" % [path, str(key_value)]
		if not key_value is String or String(key_value).strip_edges().is_empty():
			errors.append("%s 的字段名必须是非空文本" % target_path)
			continue
		var target_value: Variant = target_refs.get(key_value)
		if (
			typeof(target_value) == TYPE_STRING
			and String(target_value).strip_edges().is_empty()
		):
			errors.append("%s 必须是非空文本" % target_path)
		elif typeof(target_value) not in [TYPE_STRING, TYPE_INT]:
			errors.append("%s 只能是文本或整数" % target_path)


static func _validate_social_attention(
	attention: Dictionary,
	wake_packet: Dictionary,
	errors: Array[String],
) -> void:
	if attention.is_empty():
		return
	AgentContractIdentity._validate_allowed_fields(
		attention,
		AgentContract.SOCIAL_ATTENTION_FIELDS,
		"social_attention",
		errors,
	)
	var exposure_id := AgentContract._require_non_empty_string(
		attention,
		"exposure_id",
		"social_attention.exposure_id",
		errors,
	)
	var matter_id := AgentContract._require_non_empty_string(
		attention,
		"matter_id",
		"social_attention.matter_id",
		errors,
	)
	if (
		typeof(attention.get("matter_revision")) != TYPE_INT
		or int(attention.get("matter_revision", -1)) < 0
	):
		errors.append(
			"social_attention.matter_revision 必须是非负整数"
		)
	var option_id := AgentContract._require_non_empty_string(
		attention,
		"option_id",
		"social_attention.option_id",
		errors,
	)
	var matched := {}
	for exposure_value: Variant in (
		(wake_packet.get("snapshot", {}) as Dictionary).get(
			"social_exposures",
			[],
		) as Array
	):
		var exposure := exposure_value as Dictionary
		if String(exposure.get("exposure_id", "")) == exposure_id:
			matched = exposure
			break
	if matched.is_empty():
		errors.append(
			"social_attention.exposure_id 必须来自当前接触机会"
		)
		return
	if String(matched.get("matter_id", "")) != matter_id:
		errors.append("social_attention.matter_id 与接触机会不一致")
	if int(matched.get("matter_revision", -1)) != int(
		attention.get("matter_revision", -2)
	):
		errors.append("social_attention.matter_revision 已经过期")
	if not (matched.get("options", []) as Array).has(option_id):
		errors.append("social_attention.option_id 必须来自当前接触选项")


static func _validate_social_response(
	response: Dictionary,
	wake_packet: Dictionary,
	errors: Array[String],
) -> void:
	if response.is_empty():
		return
	AgentContractIdentity._validate_allowed_fields(
		response,
		AgentContract.SOCIAL_RESPONSE_FIELDS,
		"social_response",
		errors,
	)
	AgentContract._require_non_empty_string(
		response,
		"response_id",
		"social_response.response_id",
		errors,
	)
	var matter_id := AgentContract._require_non_empty_string(
		response,
		"matter_id",
		"social_response.matter_id",
		errors,
	)
	var revision_value: Variant = response.get("matter_revision")
	var revision_is_integer := typeof(revision_value) == TYPE_INT
	if typeof(revision_value) == TYPE_FLOAT:
		revision_is_integer = is_equal_approx(
			float(revision_value),
			float(int(revision_value)),
		)
	if not revision_is_integer or int(revision_value) < 0:
		errors.append("social_response.matter_revision 必须是非负整数")
	var response_round_id := AgentContract._require_non_empty_string(
		response,
		"response_round_id",
		"social_response.response_round_id",
		errors,
	)
	var option_id := AgentContract._require_non_empty_string(
		response,
		"option_id",
		"social_response.option_id",
		errors,
	)
	var public_text := ""
	if response.has("public_text"):
		public_text = AgentContract._require_string(
			response,
			"public_text",
			"social_response.public_text",
			errors,
		).strip_edges()
	if (
		public_text.contains("\n")
		or public_text.contains("\r")
		or public_text.contains("\t")
		or public_text.length() > AgentContract.SOCIAL_RESPONSE_TEXT_MAX_LENGTH
	):
		errors.append(
			"social_response.public_text 必须是最多 %d 字的单行文字"
			% AgentContract.SOCIAL_RESPONSE_TEXT_MAX_LENGTH
		)
	var matter := _wake_social_matter(wake_packet, matter_id)
	if matter.is_empty():
		errors.append("social_response.matter_id 必须来自当前事项快照")
		return
	if (
		int(response.get("matter_revision", -1))
		!= int(matter.get("revision", -2))
	):
		errors.append("social_response.matter_revision 已经过期")
	var matter_round_value: Variant = matter.get(
		"response_round_id",
		"",
	)
	var matter_round_id := (
		matter_round_value as String
		if matter_round_value is String
		else ""
	)
	if response_round_id != matter_round_id:
		errors.append("social_response.response_round_id 已经过期")
	var selected_option := {}
	for option_value: Variant in matter.get("options", []) as Array:
		var option := option_value as Dictionary
		if String(option.get("option_id", "")) == option_id:
			selected_option = option
			break
	if selected_option.is_empty():
		errors.append("social_response.option_id 必须来自当前事项选项")
	elif (
		not bool(selected_option.get("allows_public_text", false))
		and not public_text.is_empty()
	):
		errors.append("当前 social_response.option_id 不允许公开文字")
	elif _social_response_text_conflicts(
		String(selected_option.get("response_kind", "")),
		public_text,
	):
		errors.append("social_response.public_text 与 option_id 含义矛盾")


static func _social_response_text_conflicts(
	response_kind: String,
	public_text: String,
) -> bool:
	if public_text.is_empty():
		return false
	var immediate_accept_markers := [
		"我来",
		"我去",
		"我帮",
		"马上来",
		"马上去",
		"这就来",
		"这就去",
		"现在过去",
		"立即过去",
	]
	var rejection_markers := [
		"不能去",
		"不能来",
		"去不了",
		"来不了",
		"帮不了",
		"走不开",
		"没空",
		"没法去",
		"没法来",
		"不帮",
		"不参加",
		"不参与",
		"不方便",
		"先不去",
		"先不来",
	]
	if response_kind == "accept":
		for marker in rejection_markers:
			if public_text.contains(marker):
				return true
	if response_kind == "reject":
		for marker in rejection_markers:
			if public_text.contains(marker):
				return false
		for marker in immediate_accept_markers:
			if public_text.contains(marker):
				return true
	if response_kind == "defer":
		for marker in [
			"马上来",
			"马上去",
			"这就来",
			"这就去",
			"立即过去",
		]:
			if public_text.contains(marker):
				return true
	return false


static func _wake_social_matter(
	wake_packet: Dictionary,
	matter_id: String,
) -> Dictionary:
	for value: Variant in (
		(wake_packet.get("snapshot", {}) as Dictionary).get(
			"social_matters",
			[],
		) as Array
	):
		var matter := value as Dictionary
		if String(matter.get("matter_id", "")) == matter_id:
			return matter
	return {}


static func _validate_optional_world_revision(
	value: Dictionary,
	path: String,
	errors: Array[String],
) -> void:
	if value.has("world_revision") and typeof(value["world_revision"]) != TYPE_INT:
		errors.append("%s.world_revision 必须是整数" % path)
