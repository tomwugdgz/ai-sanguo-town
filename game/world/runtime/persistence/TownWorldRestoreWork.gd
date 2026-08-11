class_name TownWorldRestoreWork
extends RefCounted


const SAVE_CODEC := preload("res://world/runtime/persistence/TownWorldSaveCodec.gd")
# 与 TownWorldRuntime.ACTIVITY_SOURCE_DIRECT 保持一致；活动例程存档只承认直连活动动作。
const ACTIVITY_SOURCE_DIRECT := "activity.perform"


static func prepare_private_messages(
	snapshot_value: Variant,
	residents: Dictionary,
	work_tasks: RefCounted,
) -> Dictionary:
	var unpacked := SAVE_CODEC.unpack_optional_domain_snapshot(
		snapshot_value,
		"privateMessages 必须为对象",
	)
	if unpacked.get("ok") != true:
		return {"ok": false, "errors": unpacked.get("errors", [])}
	if unpacked.get("empty") == true:
		return {
			"ok": true,
			"sequence": 0,
			"messagesById": {},
			"archiveSummary": empty_private_message_archive_summary(),
		}
	var snapshot := unpacked.get("snapshot", {}) as Dictionary
	var schema_version := int(snapshot.get("schemaVersion", 0))
	var expected_fields := ["schemaVersion", "sequence", "messages"]
	if schema_version in [3, 4]:
		expected_fields.append("archiveSummary")
	if (
		not private_message_has_exact_keys(snapshot, expected_fields)
		or schema_version not in [1, 2, 3, 4]
		or (schema_version in [3, 4] and not snapshot.get("archiveSummary") is Dictionary)
		or typeof(snapshot.get("sequence")) != TYPE_INT
		or int(snapshot.get("sequence", -1)) < 0
		or not snapshot.get("messages") is Array
	):
		return {
			"ok": false,
			"errors": ["privateMessages 字段或版本无效"],
		}
	var restored := {}
	var seen_message_ids := {}
	var archive_summary := _normalized_private_message_archive_summary(
		snapshot.get("archiveSummary", {}) as Dictionary,
	)
	if archive_summary.is_empty():
		return {
			"ok": false,
			"errors": ["privateMessages.archiveSummary 无效"],
		}
	var allowed_fields := [
		"messageId",
		"senderResidentId",
		"recipientResidentId",
		"content",
		"state",
		"createdAtMinute",
		"deliveredAtMinute",
		"deliveredByResidentId",
		"taskId",
		"batchId",
		"messageKind",
		"announcementId",
		"expiresAtMinute",
		"sourceRef",
	]
	for value: Variant in snapshot.get("messages", []) as Array:
		if not value is Dictionary:
			return {
				"ok": false,
				"errors": ["privateMessages.messages 只能包含对象"],
			}
		var message := (value as Dictionary).duplicate(true)
		if not message.has("batchId"):
			message["batchId"] = ""
		# Version 1 only stored ordinary resident messages. Normalize it before
		# validating so old saves remain loadable while formal notices retain an
		# exact announcement reference in new saves.
		if not message.has("messageKind"):
			message["messageKind"] = "private"
		if not message.has("announcementId"):
			message["announcementId"] = ""
		if not message.has("expiresAtMinute"):
			message["expiresAtMinute"] = -1
		if not message.has("sourceRef"):
			message["sourceRef"] = ""
		var message_id := String(message.get("messageId", ""))
		var duplicate_message_id := (
			not message_id.is_empty()
			and seen_message_ids.has(message_id)
		)
		if not message_id.is_empty():
			seen_message_ids[message_id] = true
		var sender_id := String(
			message.get("senderResidentId", ""),
		)
		var recipient_id := String(
			message.get("recipientResidentId", ""),
		)
		var state := String(message.get("state", ""))
		var task_id := String(message.get("taskId", ""))
		var task := work_tasks.task(task_id) as Dictionary
		var message_kind := String(message.get("messageKind", "private"))
		var announcement_id := String(
			message.get("announcementId", ""),
		).strip_edges()
		var expected_source_kind := (
			"formal_notice"
			if message_kind == "announcement_notice"
			else "resident_message"
		)
		if (
			state == "pending"
			and String(task.get("processStage", "ready")) == "ready"
		):
			var migrated_task := work_tasks.set_process_stage_from_world(task_id,
				int(task.get("revision", 0)),
				"out_for_delivery",
				{
					"batchId": "",
					"messageId": message_id,
					"nextActivityId": "__resident_delivery__",
				},) as Dictionary
			if migrated_task.get("ok") == true:
				task = migrated_task.get("task", {}) as Dictionary
		if (
			state == "delivered"
			and not duplicate_message_id
			and task.is_empty()
			and _private_message_can_archive(
				message,
				residents,
				allowed_fields,
			)
		):
			archive_summary = archive_private_message_in_summary(
				archive_summary,
				message,
			)
			continue
		if (
			not private_message_has_exact_keys(message, allowed_fields)
			or message_id.is_empty()
			or duplicate_message_id
			or not residents.has(sender_id)
			or not residents.has(recipient_id)
			or sender_id == recipient_id
			or String(message.get("content", "")).strip_edges().is_empty()
			or String(message.get("content", "")).length() > 240
			or message_kind not in ["private", "announcement_notice"]
			or (
				message_kind == "announcement_notice"
				and announcement_id.is_empty()
			)
			or (
				message_kind == "private"
				and not announcement_id.is_empty()
			)
			or state not in ["pending", "delivered"]
			or typeof(message.get("createdAtMinute")) != TYPE_INT
			or int(message.get("createdAtMinute", -1)) < 0
			or typeof(message.get("deliveredAtMinute")) != TYPE_INT
			or typeof(message.get("expiresAtMinute")) != TYPE_INT
			or (
				int(message.get("expiresAtMinute", -1)) >= 0
				and int(message.get("expiresAtMinute", -1))
				<= int(message.get("createdAtMinute", -1))
			)
			or task.is_empty()
			or String(task.get("sourceKind", "")) != expected_source_kind
			or String(task.get("sourceRef", "")) != message_id
			or (
				state == "pending"
				and String(task.get("state", "")) in [
					"completed",
					"failed",
					"cancelled",
				]
			)
			or (
				state == "delivered"
				and (
					int(message.get("deliveredAtMinute", -1)) < 0
					or String(
						message.get("deliveredByResidentId", ""),
					).is_empty()
					or String(task.get("state", "")) != "completed"
				)
			)
		):
			return {
				"ok": false,
				"errors": ["privateMessages 包含无效消息或任务引用"],
			}
		restored[message_id] = message.duplicate(true)
	return {
		"ok": true,
		"sequence": int(snapshot.get("sequence", 0)),
		"messagesById": restored,
		"archiveSummary": archive_summary,
	}


static func prepare_activity_routines(
	snapshot_value: Variant,
	residents: Dictionary,
) -> Dictionary:
	var unpacked := SAVE_CODEC.unpack_optional_domain_snapshot(
		snapshot_value,
		"activityRoutines 必须为对象",
		["schemaVersion", "routines"],
		[1],
		"activityRoutines 字段或版本无效",
	)
	if unpacked.get("ok") != true:
		return {"ok": false, "errors": unpacked.get("errors", [])}
	if unpacked.get("empty") == true:
		return {
			"ok": true,
			"routinesByResident": {},
		}
	var snapshot := unpacked.get("snapshot", {}) as Dictionary
	if not snapshot.get("routines") is Array:
		return {
			"ok": false,
			"errors": ["activityRoutines 字段或版本无效"],
		}
	var result := {}
	var required_fields := [
		"residentId",
		"routineId",
		"sourceActionId",
		"placeId",
		"group",
		"endAbsoluteMinute",
		"sequence",
		"lastActivityId",
		"lastPhase",
	]
	var allowed_fields := required_fields.duplicate()
	allowed_fields.append("visitedActivityIds")
	allowed_fields.append("choiceSeed")
	for value: Variant in snapshot.get("routines", []) as Array:
		if not value is Dictionary:
			return {
				"ok": false,
				"errors": ["activityRoutines.routines 只能包含对象"],
			}
		var routine := value as Dictionary
		var fields_valid := true
		for field: String in required_fields:
			if not routine.has(field):
				fields_valid = false
				break
		if fields_valid:
			for field_value: Variant in routine.keys():
				if not allowed_fields.has(String(field_value)):
					fields_valid = false
					break
		var resident_id := String(routine.get("residentId", ""))
		if (
			not fields_valid
			or resident_id.is_empty()
			or result.has(resident_id)
			or not residents.has(resident_id)
			or String(routine.get("routineId", "")).is_empty()
			or String(routine.get("sourceActionId", "")).is_empty()
			or String(routine.get("placeId", "")).is_empty()
			or String(routine.get("group", "")) not in ["work", "meal"]
			or typeof(routine.get("endAbsoluteMinute")) != TYPE_INT
			or int(routine.get("endAbsoluteMinute", -1)) < 0
			or typeof(routine.get("sequence")) != TYPE_INT
			or int(routine.get("sequence", -1)) < 0
			or String(routine.get("lastActivityId", "")).is_empty()
			or not routine.get("lastPhase") is String
		):
			return {
				"ok": false,
				"errors": ["activityRoutines 包含无效活动过程"],
			}
		var visited_activity_ids: Array = []
		if routine.has("visitedActivityIds"):
			if not routine.get("visitedActivityIds") is Array:
				return {
					"ok": false,
					"errors": ["activityRoutines 包含无效活动过程"],
				}
			for activity_value: Variant in (
				routine.get("visitedActivityIds", []) as Array
			):
				if (
					not activity_value is String
					or String(activity_value).is_empty()
					or visited_activity_ids.has(String(activity_value))
				):
					return {
						"ok": false,
						"errors": ["activityRoutines 包含无效活动过程"],
					}
				visited_activity_ids.append(String(activity_value))
		else:
			visited_activity_ids.append(
				String(routine.get("lastActivityId", "")),
			)
		if (
			visited_activity_ids.is_empty()
			or not visited_activity_ids.has(
				String(routine.get("lastActivityId", "")),
			)
			or (
				routine.has("choiceSeed")
				and typeof(routine.get("choiceSeed")) != TYPE_INT
			)
		):
			return {
				"ok": false,
				"errors": ["activityRoutines 包含无效活动过程"],
			}
		var current_action := (
			residents[resident_id] as Dictionary
		).get("currentAction", {}) as Dictionary
		var direct_activity_is_active := (
			String(current_action.get("type", "")) == "用道具"
			and String(
				current_action.get("action_id", "")
			).begins_with("activity-")
			and String(
				current_action.get("sourceContract", "")
			) == ACTIVITY_SOURCE_DIRECT
		)
		# A resident can finish one routine step and synchronously enter an
		# on-site service wait. The routine deliberately remains suspended so it
		# can continue after service. This is a valid save boundary, not an orphan.
		var onsite_service_wait_is_active := (
			String(current_action.get("type", "")) == "待着"
			and not String(
				current_action.get("serviceRequestId", ""),
			).strip_edges().is_empty()
			and String(
				current_action.get("action_id", ""),
			).begins_with("service-wait:")
		)
		if not direct_activity_is_active and not onsite_service_wait_is_active:
			return {
				"ok": false,
				"errors": [
					"activityRoutines 与居民当前活动不一致：%s"
					% resident_id
				],
			}
		var restored := routine.duplicate(true)
		restored.erase("residentId")
		restored["visitedActivityIds"] = visited_activity_ids
		if not restored.has("choiceSeed"):
			restored["choiceSeed"] = hash("%s:%s:%d" % [
				resident_id,
				String(restored.get("routineId", "")),
				int(restored.get("endAbsoluteMinute", 0)),
			])
		result[resident_id] = restored
	return {
		"ok": true,
		"routinesByResident": result,
	}


static func prepare_work_task_bindings(
	snapshot_value: Variant,
	residents: Dictionary,
	work_tasks: RefCounted,
) -> Dictionary:
	var unpacked := SAVE_CODEC.unpack_optional_domain_snapshot(
		snapshot_value,
		"activityWorkTaskBindings 必须是对象",
	)
	if unpacked.get("ok") != true:
		return {"ok": false, "errors": unpacked.get("errors", [])}
	if unpacked.get("empty") == true:
		return {"ok": true, "bindings": {}}
	var snapshot := unpacked.get("snapshot", {}) as Dictionary
	var result: Dictionary = {}
	for binding_key_value: Variant in snapshot:
		var binding_key := String(binding_key_value)
		var task_id := String(
			snapshot.get(
				binding_key_value,
				"",
			),
		)
		var separator_index := binding_key.find(":")
		if (
			separator_index <= 0
			or task_id.is_empty()
		):
			return {
				"ok": false,
				"errors": ["activityWorkTaskBindings 包含无效绑定"],
			}
		var resident_id := binding_key.substr(0, separator_index)
		var action_id := binding_key.substr(separator_index + 1)
		if (
			not residents.has(resident_id)
			or action_id.is_empty()
		):
			return {
				"ok": false,
				"errors": ["activityWorkTaskBindings 引用未知居民或动作"],
			}
		var current_action := (
			(residents.get(resident_id, {}) as Dictionary).get(
				"currentAction",
				{},
			) as Dictionary
		)
		var task := work_tasks.task(task_id) as Dictionary
		if task.is_empty():
			# Finite-base-inventory tasks are removed while loading older saves.
			# Their current presentation action may finish, but it no longer owns
			# a work result and therefore cannot recreate the retired loop.
			continue
		if (
			String(current_action.get("action_id", "")) != action_id
			or String(task.get("assignedResidentId", "")) != resident_id
			or String(task.get("state", "")) != "in_progress"
		):
			return {
				"ok": false,
				"errors": ["activityWorkTaskBindings 与任务状态不一致"],
			}
		result[binding_key] = task_id
	return {"ok": true, "bindings": result}


static func private_message_has_exact_keys(
	value: Dictionary,
	expected_keys: Array,
) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key_value: Variant in expected_keys:
		if not value.has(String(key_value)):
			return false
	return true


static func empty_private_message_archive_summary() -> Dictionary:
	return {
		"deliveredCount": 0,
		"countByKind": {},
	}


static func _normalized_private_message_archive_summary(
	value: Dictionary,
) -> Dictionary:
	var delivered_count_value: Variant = value.get("deliveredCount", 0)
	var count_by_kind_value: Variant = value.get("countByKind", {})
	if (
		typeof(delivered_count_value) != TYPE_INT
		or int(delivered_count_value) < 0
		or not count_by_kind_value is Dictionary
	):
		return {}
	var count_by_kind: Dictionary = {}
	for kind_value: Variant in count_by_kind_value as Dictionary:
		var count_value: Variant = (
			count_by_kind_value as Dictionary
		).get(kind_value)
		if typeof(count_value) != TYPE_INT or int(count_value) < 0:
			return {}
		count_by_kind[String(kind_value)] = int(count_value)
	return {
		"deliveredCount": int(delivered_count_value),
		"countByKind": count_by_kind,
	}


static func _private_message_can_archive(
	message: Dictionary,
	residents: Dictionary,
	allowed_fields: Array,
) -> bool:
	var sender_id := String(message.get("senderResidentId", ""))
	var recipient_id := String(message.get("recipientResidentId", ""))
	var message_kind := String(message.get("messageKind", "private"))
	var announcement_id := String(
		message.get("announcementId", ""),
	).strip_edges()
	return (
		private_message_has_exact_keys(message, allowed_fields)
		and not String(message.get("messageId", "")).is_empty()
		and residents.has(sender_id)
		and residents.has(recipient_id)
		and sender_id != recipient_id
		and not String(message.get("content", "")).strip_edges().is_empty()
		and String(message.get("content", "")).length() <= 240
		and message_kind in ["private", "announcement_notice"]
		and (
			(message_kind == "private" and announcement_id.is_empty())
			or (
				message_kind == "announcement_notice"
				and not announcement_id.is_empty()
			)
		)
		and typeof(message.get("createdAtMinute")) == TYPE_INT
		and int(message.get("createdAtMinute", -1)) >= 0
		and typeof(message.get("deliveredAtMinute")) == TYPE_INT
		and typeof(message.get("expiresAtMinute", -1)) == TYPE_INT
		and int(message.get("deliveredAtMinute", -1)) >= 0
		and not String(message.get("deliveredByResidentId", "")).is_empty()
	)


static func archive_private_message_in_summary(
	summary_value: Dictionary,
	message: Dictionary,
) -> Dictionary:
	var summary := summary_value.duplicate(true)
	summary["deliveredCount"] = int(summary.get("deliveredCount", 0)) + 1
	var count_by_kind := (
		summary.get("countByKind", {}) as Dictionary
	).duplicate(true)
	var kind := String(message.get("messageKind", "private"))
	count_by_kind[kind] = int(count_by_kind.get(kind, 0)) + 1
	summary["countByKind"] = count_by_kind
	return summary
