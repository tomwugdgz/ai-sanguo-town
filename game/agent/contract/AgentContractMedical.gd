class_name AgentContractMedical
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


static func _validate_medical_dialogue_projection(
	value: Variant,
	path: String,
	expected_request_id: String,
	errors: Array[String],
) -> void:
	if not value is Dictionary:
		errors.append("%s 必须是对象" % path)
		return
	var medical := value as Dictionary
	AgentContractIdentity._validate_allowed_fields(
		medical,
		[
			"request_id",
			"role",
			"status",
			"conversation_id",
			"reported_summary",
			"attempt_count",
			"patient_response_kind",
			"response_options",
		],
		path,
		errors,
	)
	var request_id := AgentContract._require_non_empty_string(
		medical,
		"request_id",
		"%s.request_id" % path,
		errors,
	)
	if not expected_request_id.is_empty() and request_id != expected_request_id:
		errors.append("%s.request_id 与服务请求不一致" % path)
	var role := AgentContract._require_non_empty_string(
		medical,
		"role",
		"%s.role" % path,
		errors,
	)
	if role not in ["patient", "clinician"]:
		errors.append("%s.role 必须是 patient 或 clinician" % path)
	var status := AgentContract._require_non_empty_string(
		medical,
		"status",
		"%s.status" % path,
		errors,
	)
	if status not in ["required", "active", "completed", "refused", "interrupted"]:
		errors.append("%s.status 无效" % path)
	for field_name: String in [
		"conversation_id",
		"reported_summary",
		"patient_response_kind",
	]:
		if typeof(medical.get(field_name)) != TYPE_STRING:
			errors.append("%s.%s 必须是文本" % [path, field_name])
	if String(medical.get("reported_summary", "")).strip_edges().is_empty():
		errors.append("%s.reported_summary 不能为空" % path)
	if (
		typeof(medical.get("attempt_count")) != TYPE_INT
		or int(medical.get("attempt_count", -1)) < 0
	):
		errors.append("%s.attempt_count 必须是非负整数" % path)
	var options := AgentContract._require_array(
		medical,
		"response_options",
		"%s.response_options" % path,
		errors,
	)
	var seen_options: Dictionary = {}
	for option_value: Variant in options:
		if not option_value is String or String(option_value) not in ["describe", "decline"]:
			errors.append("%s.response_options 只能包含 describe 或 decline" % path)
			continue
		var option := String(option_value)
		if seen_options.has(option):
			errors.append("%s.response_options 不能重复" % path)
		seen_options[option] = true
	var conversation_id := String(
		medical.get("conversation_id", ""),
	).strip_edges()
	var attempt_count := int(medical.get("attempt_count", -1))
	var response_kind := String(
		medical.get("patient_response_kind", ""),
	)
	if response_kind not in ["", "describe", "decline"]:
		errors.append("%s.patient_response_kind 无效" % path)
	if role == "clinician" and not options.is_empty():
		errors.append("%s 医者视角不能替患者选择结构化回应" % path)
	if status == "required":
		if (
			not conversation_id.is_empty()
			or attempt_count != 0
			or not response_kind.is_empty()
			or not options.is_empty()
		):
			errors.append("%s required 状态尚不能包含对话结果" % path)
	elif status == "active":
		if conversation_id.is_empty() or attempt_count < 1:
			errors.append("%s active 状态缺少真实对话" % path)
		if role == "patient":
			var expected_options := (
				["describe", "decline"]
				if response_kind.is_empty()
				else []
			)
			if options != expected_options:
				errors.append("%s 患者回应选项与当前状态不一致" % path)
	else:
		if conversation_id.is_empty() or attempt_count < 1:
			errors.append("%s 终态缺少真实对话" % path)
		if not options.is_empty():
			errors.append("%s 终态不能继续提供回应选项" % path)
		if status == "completed" and response_kind != "describe":
			errors.append("%s completed 状态缺少患者描述" % path)
		elif status == "refused" and response_kind not in ["", "decline"]:
			errors.append("%s refused 状态回应无效" % path)
		elif status == "interrupted" and not response_kind.is_empty():
			errors.append("%s interrupted 状态不能伪造患者回应" % path)


static func _validate_medical_response(
	action: Dictionary,
	wake_packet: Dictionary,
	errors: Array[String],
) -> void:
	var conversation_value: Variant = (
		wake_packet.get("snapshot", {}) as Dictionary
	).get("conversation")
	var medical: Dictionary = {}
	if conversation_value is Dictionary:
		var medical_value: Variant = (
			conversation_value as Dictionary
		).get("medical_context")
		if medical_value is Dictionary:
			medical = medical_value as Dictionary
	var response_options: Array = []
	var response_options_value: Variant = medical.get("response_options", [])
	if response_options_value is Array:
		response_options = response_options_value as Array
	var response_required := (
		String(medical.get("role", "")) == "patient"
		and String(medical.get("status", "")) == "active"
		and not response_options.is_empty()
	)
	if not action.has("medical_response"):
		if response_required:
			errors.append("患者本轮必须提交 action.medical_response")
		return
	var response_value: Variant = action.get("medical_response")
	if not response_value is Dictionary:
		errors.append("action.medical_response 必须是对象")
		return
	if medical.is_empty():
		errors.append("action.medical_response 只能在当前医患对话中提交")
		return
	var response := response_value as Dictionary
	AgentContractIdentity._validate_allowed_fields(
		response,
		["request_id", "response_kind"],
		"action.medical_response",
		errors,
	)
	var request_id := AgentContract._require_non_empty_string(
		response,
		"request_id",
		"action.medical_response.request_id",
		errors,
	)
	var response_kind := AgentContract._require_non_empty_string(
		response,
		"response_kind",
		"action.medical_response.response_kind",
		errors,
	)
	if String(medical.get("role", "")) != "patient":
		errors.append("只有患者本人能提交 action.medical_response")
	if not request_id.is_empty() and request_id != String(medical.get("request_id", "")):
		errors.append("action.medical_response.request_id 与当前医患对话不一致")
	if not response_kind.is_empty() and not response_options.has(response_kind):
		errors.append("action.medical_response.response_kind 不在当前可选回应中")
