class_name AgentContractWorkTasks
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


static func _validate_work_tasks(
	tasks: Array,
	errors: Array[String],
) -> void:
	var task_ids: Dictionary = {}
	for index in tasks.size():
		var path := "snapshot.work_tasks[%d]" % index
		var value: Variant = tasks[index]
		if not value is Dictionary:
			errors.append("%s 必须是对象" % path)
			continue
		var task := value as Dictionary
		AgentContractIdentity._validate_allowed_fields(
			task,
			[
				"task_id",
				"capability",
				"source_kind",
				"source_ref",
				"targets",
				"expected_result",
				"state",
				"priority",
				"process_stage",
				"next_step",
				"message",
				"service_request",
			],
			path,
			errors,
		)
		var task_id := AgentContract._require_non_empty_string(
			task,
			"task_id",
			"%s.task_id" % path,
			errors,
		)
		if not task_id.is_empty() and task_ids.has(task_id):
			errors.append("%s.task_id 重复" % path)
		task_ids[task_id] = true
		for field_name: String in [
			"capability",
			"source_kind",
			"source_ref",
			"expected_result",
			"state",
		]:
			AgentContract._require_non_empty_string(
				task,
				field_name,
				"%s.%s" % [path, field_name],
				errors,
			)
		if (
			typeof(task.get("priority")) != TYPE_INT
			or int(task.get("priority", -1)) < 0
			or int(task.get("priority", 101)) > 100
		):
			errors.append("%s.priority 必须是 0 到 100 的整数" % path)
		var targets := AgentContract._require_array(
			task,
			"targets",
			"%s.targets" % path,
			errors,
		)
		if targets.is_empty():
			errors.append("%s.targets 不能为空" % path)
		for target_index in targets.size():
			var target_value: Variant = targets[target_index]
			var target_path := "%s.targets[%d]" % [
				path,
				target_index,
			]
			if not target_value is Dictionary:
				errors.append("%s 必须是对象" % target_path)
				continue
			var target := target_value as Dictionary
			AgentContractIdentity._validate_allowed_fields(
				target,
				["kind", "ref"],
				target_path,
				errors,
			)
			AgentContract._require_non_empty_string(
				target,
				"kind",
				"%s.kind" % target_path,
				errors,
			)
			AgentContract._require_non_empty_string(
				target,
				"ref",
				"%s.ref" % target_path,
				errors,
			)
		if task.has("next_step"):
			var next_step := AgentContract._require_dictionary(
				task,
				"next_step",
				"%s.next_step" % path,
				errors,
			)
			AgentContractIdentity._validate_allowed_fields(
				next_step,
				["place_id", "instruction"],
				"%s.next_step" % path,
				errors,
			)
			AgentContract._require_non_empty_string(
				next_step,
				"place_id",
				"%s.next_step.place_id" % path,
				errors,
			)
			AgentContract._require_non_empty_string(
				next_step,
				"instruction",
				"%s.next_step.instruction" % path,
				errors,
			)
		if task.has("message"):
			var message := AgentContract._require_dictionary(
				task,
				"message",
				"%s.message" % path,
				errors,
			)
			AgentContractIdentity._validate_allowed_fields(
				message,
				[
					"kind",
					"announcement_id",
					"sender_resident_id",
					"sender_name",
					"recipient_resident_id",
					"recipient_name",
					"recipient_current_place",
					"content",
				],
				"%s.message" % path,
				errors,
			)
			var message_kind := String(message.get("kind", ""))
			for field_name: String in [
				"kind",
				"sender_resident_id",
				"sender_name",
				"recipient_resident_id",
				"recipient_name",
				"recipient_current_place",
				"content",
			]:
				AgentContract._require_non_empty_string(
					message,
					field_name,
					"%s.message.%s" % [path, field_name],
					errors,
				)
			if message_kind not in ["private", "announcement_notice"]:
				errors.append("%s.message.kind 无效" % path)
			if typeof(message.get("announcement_id")) != TYPE_STRING:
				errors.append("%s.message.announcement_id 必须是文本" % path)
			elif (
				message_kind == "announcement_notice"
				and String(message.get("announcement_id", "")).is_empty()
			):
				errors.append("%s.message 正式通知缺少公告编号" % path)
			if (
				String(task.get("capability", "")) != "message.deliver"
				or String(task.get("source_kind", "")) != (
					"formal_notice"
					if message_kind == "announcement_notice"
					else "resident_message"
				)
			):
				errors.append(
					"%s.message 与送达任务来源不一致" % path,
				)
			var sender_id := String(
				message.get("sender_resident_id", ""),
			)
			var recipient_id := String(
				message.get("recipient_resident_id", ""),
			)
			if (
				not sender_id.is_empty()
				and not AgentContractIdentity._resident_id_is_safe(sender_id)
			):
				errors.append(
					"%s.message.sender_resident_id 无效" % path,
				)
			if (
				not recipient_id.is_empty()
				and not AgentContractIdentity._resident_id_is_safe(recipient_id)
			):
				errors.append(
					"%s.message.recipient_resident_id 无效" % path,
				)
			var has_recipient_target := false
			for target_value: Variant in targets:
				if (
					target_value is Dictionary
					and String(
						(target_value as Dictionary).get("kind", ""),
					) == "resident"
					and String(
						(target_value as Dictionary).get("ref", ""),
					) == recipient_id
				):
					has_recipient_target = true
					break
			if not recipient_id.is_empty() and not has_recipient_target:
				errors.append(
					"%s.message 收件人与任务目标不一致" % path,
				)
			if String(message.get("content", "")).length() > 240:
				errors.append(
					"%s.message.content 不能超过 240 个字符" % path,
				)
		if task.has("service_request"):
			var service_request := AgentContract._require_dictionary(
				task,
				"service_request",
				"%s.service_request" % path,
				errors,
			)
			AgentContractIdentity._validate_allowed_fields(
				service_request,
				[
					"request_id",
					"kind",
					"requester_resident_id",
					"requester_name",
					"requester_current_place",
					"subject_ref",
					"item_id",
					"place_id",
					"state",
					"wait_reason",
					"medical_dialogue",
				],
				"%s.service_request" % path,
				errors,
			)
			for field_name: String in [
				"request_id",
				"kind",
				"requester_resident_id",
				"requester_name",
				"requester_current_place",
				"state",
			]:
				AgentContract._require_non_empty_string(
					service_request,
					field_name,
					"%s.service_request.%s" % [path, field_name],
					errors,
				)
			for field_name: String in [
				"subject_ref",
				"item_id",
				"place_id",
				"wait_reason",
			]:
				if typeof(service_request.get(field_name)) != TYPE_STRING:
					errors.append(
						"%s.service_request.%s 必须是文本"
						% [path, field_name],
					)
			var request_id := String(
				service_request.get("request_id", ""),
			)
			var requester_id := String(
				service_request.get("requester_resident_id", ""),
			)
			if (
				not requester_id.is_empty()
				and not AgentContractIdentity._resident_id_is_safe(requester_id)
			):
				errors.append(
					"%s.service_request.requester_resident_id 无效"
					% path,
				)
			var has_request_target := false
			for target_value: Variant in targets:
				if (
					target_value is Dictionary
					and String(
						(target_value as Dictionary).get("kind", ""),
					) == "service_request"
					and String(
						(target_value as Dictionary).get("ref", ""),
					) == request_id
				):
					has_request_target = true
					break
			if not request_id.is_empty() and not has_request_target:
				errors.append(
					"%s.service_request 与任务目标不一致" % path,
				)
			if (
				not request_id.is_empty()
				and String(task.get("source_ref", "")) != request_id
			):
				errors.append(
					"%s.service_request 与任务来源不一致" % path,
				)
			if service_request.has("medical_dialogue"):
				AgentContractMedical._validate_medical_dialogue_projection(
					service_request.get("medical_dialogue"),
					"%s.service_request.medical_dialogue" % path,
					request_id,
					errors,
				)
