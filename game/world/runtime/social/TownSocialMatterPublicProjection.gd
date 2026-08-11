class_name TownSocialMatterPublicProjection
extends RefCounted


const ITEM_FIELDS := [
	"matterId",
	"residentId",
	"residentName",
	"phase",
	"iconType",
	"reasonSummary",
	"promiseSummary",
	"executionSummary",
	"confirmedRevision",
	"expiresAtAbsoluteMinute",
]
const HISTORY_FIELDS := [
	"eventId",
	"matterId",
	"matterKind",
	"matterSummary",
	"occurredAt",
	"worldTime",
	"outcome",
	"responderResidentIds",
	"responderNames",
	"responseCount",
	"nonResponderResidentIds",
	"nonResponderNames",
	"nonResponseCount",
	"resultSummary",
	"confirmedRevision",
]
const PUBLIC_PHASES := [
	"observing",
	"reading",
	"responding",
	"executing",
]
const PUBLIC_ICON_TYPES := [
	"",
	"observing",
	"reading",
]
const PUBLIC_OUTCOMES := [
	"responded",
	"unanswered",
	"completed",
	"failed",
]
const SUMMARY_MAX_LENGTH := 18


static func build(
	matters: Array,
	resident_names: Dictionary,
	active_activities: Dictionary,
	bulletin_matter_ids: Dictionary,
	world_revision: int,
	now_absolute_minute: int,
) -> Dictionary:
	var items := _build_items(
		matters,
		resident_names,
		active_activities,
		bulletin_matter_ids,
		now_absolute_minute,
	)
	var history := _build_history(matters, resident_names)
	return {
		"revision": maxi(world_revision, 0),
		"items": items,
		"history": history,
	}


static func _build_items(
	matters: Array,
	resident_names: Dictionary,
	active_activities: Dictionary,
	bulletin_matter_ids: Dictionary,
	now_absolute_minute: int,
) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var seen := {}
	var sorted_matters := _sorted_matters(matters)
	for matter: Dictionary in sorted_matters:
		if String(matter.get("state", "")) == "closed":
			continue
		var expires_at := int(matter.get("expires_at", -1))
		if expires_at >= 0 and expires_at <= now_absolute_minute:
			continue
		var participants := matter.get("participants", {}) as Dictionary
		var resident_ids := _sorted_string_keys(participants)
		for resident_id: String in resident_ids:
			var participant := (
				participants.get(resident_id, {}) as Dictionary
			)
			var participant_status := String(
				participant.get("status", "")
			)
			if participant_status not in ["assigned", "executing"]:
				continue
			var phase := _participant_phase(
				matter,
				participant_status,
				active_activities.get(resident_id, {}) as Dictionary,
			)
			var item := _item(
				matter,
				resident_id,
				String(resident_names.get(resident_id, "")),
				phase,
			)
			var key := _item_key(item)
			if not seen.has(key):
				seen[key] = true
				items.append(item)
	for resident_id: String in _sorted_string_keys(active_activities):
		var activity := (
			active_activities.get(resident_id, {}) as Dictionary
		)
		if (
			String(activity.get("activityId", ""))
			!= "activity_bulletin_read"
			or String(activity.get("phase", "")) != "performing"
		):
			continue
		var matter_id := String(
			bulletin_matter_ids.get(resident_id, "")
		).strip_edges()
		if matter_id.is_empty():
			continue
		var linked_matter := _matter_by_id(sorted_matters, matter_id)
		if linked_matter.is_empty():
			continue
		var item := _item(
			linked_matter,
			resident_id,
			String(resident_names.get(resident_id, "")),
			"reading",
		)
		var key := _item_key(item)
		if not seen.has(key):
			seen[key] = true
			items.append(item)
	items.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return _item_key(left) < _item_key(right)
	)
	return items


static func _build_history(
	matters: Array,
	resident_names: Dictionary,
) -> Array[Dictionary]:
	var history: Array[Dictionary] = []
	for matter: Dictionary in _sorted_matters(matters):
		var matter_id := String(matter.get("matter_id", ""))
		var matter_revision := int(matter.get("revision", 0))
		var has_terminal_result := false
		for round_value: Variant in (
			matter.get("response_history", []) as Array
		):
			var round_record := round_value as Dictionary
			var responder_ids: Array[String] = []
			var non_responder_ids: Array[String] = []
			var candidate_results := (
				round_record.get("candidate_results", {}) as Dictionary
			)
			for resident_id: String in _sorted_string_keys(
				candidate_results
			):
				var response := (
					candidate_results.get(resident_id, {}) as Dictionary
				)
				if not String(
					response.get("response_kind", "")
				).is_empty():
					responder_ids.append(resident_id)
				else:
					non_responder_ids.append(resident_id)
			var responder_names := _resident_names(
				responder_ids,
				resident_names,
			)
			var non_responder_names := _resident_names(
				non_responder_ids,
				resident_names,
			)
			var occurred_at := int(
				round_record.get("settled_at", -1)
			)
			var outcome := (
				"responded"
				if not responder_ids.is_empty()
				else "unanswered"
			)
			history.append(_history_item(
				"social:%s:response:%s"
				% [
					matter_id,
					String(
						round_record.get(
							"response_round_id",
							"round",
						)
					),
				],
				matter_id,
				String(matter.get("kind", "")),
				_reason_summary(matter),
				occurred_at,
				outcome,
				responder_ids,
				responder_names,
				_response_summary(responder_names),
				matter_revision,
				non_responder_ids,
				non_responder_names,
			))
		var participants := matter.get("participants", {}) as Dictionary
		for resident_id: String in _sorted_string_keys(participants):
			var participant := (
				participants.get(resident_id, {}) as Dictionary
			)
			var participant_status := String(
				participant.get("status", "")
			)
			if participant_status not in [
				"completed",
				"failed",
				"interrupted",
			]:
				continue
			has_terminal_result = true
			var outcome := (
				"completed"
				if participant_status == "completed"
				else "failed"
			)
			var resident_name := String(
				resident_names.get(resident_id, "")
			)
			var goal_id := String(
				(
					participant.get("action_goal", {}) as Dictionary
				).get("goal_id", "goal")
			)
			history.append(_history_item(
				"social:%s:result:%s:%s"
				% [matter_id, resident_id, goal_id],
				matter_id,
				String(matter.get("kind", "")),
				_reason_summary(matter),
				int(participant.get("finished_at", -1)),
				outcome,
				[resident_id],
				[resident_name],
				_result_summary(resident_name, outcome),
				matter_revision,
			))
		if (
			String(matter.get("state", "")) == "closed"
			and not has_terminal_result
			and (matter.get("response_history", []) as Array).is_empty()
		):
			history.append(_history_item(
				"social:%s:closed" % matter_id,
				matter_id,
				String(matter.get("kind", "")),
				_reason_summary(matter),
				int(matter.get("closed_at", -1)),
				"unanswered",
				[],
				[],
				_close_summary(
					String(matter.get("close_reason", ""))
				),
				matter_revision,
			))
	history.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_time := int(left.get("occurredAt", -1))
			var right_time := int(right.get("occurredAt", -1))
			if left_time == right_time:
				return String(left.get("eventId", "")) < String(
					right.get("eventId", "")
				)
			return left_time < right_time
	)
	return history


static func _item(
	matter: Dictionary,
	resident_id: String,
	resident_name: String,
	phase: String,
) -> Dictionary:
	var normalized_phase := (
		phase if phase in PUBLIC_PHASES else "executing"
	)
	var icon_type := ""
	if normalized_phase in ["observing", "reading"]:
		icon_type = normalized_phase
	return {
		"matterId": String(matter.get("matter_id", "")),
		"residentId": resident_id,
		"residentName": resident_name,
		"phase": normalized_phase,
		"iconType": icon_type,
		"reasonSummary": _shorten(_reason_summary(matter)),
		"promiseSummary": _shorten(
			_promise_summary(matter, normalized_phase)
		),
		"executionSummary": _shorten(
			_execution_summary(matter, normalized_phase)
		),
		"confirmedRevision": int(matter.get("revision", 0)),
		"expiresAtAbsoluteMinute": int(
			matter.get("expires_at", -1)
		),
	}


static func _history_item(
	event_id: String,
	matter_id: String,
	matter_kind: String,
	matter_summary: String,
	occurred_at: int,
	outcome: String,
	responder_ids: Array,
	responder_names: Array,
	result_summary: String,
	confirmed_revision: int,
	non_responder_ids: Array = [],
	non_responder_names: Array = [],
) -> Dictionary:
	var normalized_outcome := (
		outcome if outcome in PUBLIC_OUTCOMES else "failed"
	)
	return {
		"eventId": event_id,
		"matterId": matter_id,
		"matterKind": matter_kind,
		"matterSummary": _shorten(matter_summary),
		"occurredAt": occurred_at,
		"worldTime": _world_time(occurred_at),
		"outcome": normalized_outcome,
		"responderResidentIds": responder_ids.duplicate(),
		"responderNames": responder_names.duplicate(),
		"responseCount": responder_ids.size(),
		"nonResponderResidentIds": non_responder_ids.duplicate(),
		"nonResponderNames": non_responder_names.duplicate(),
		"nonResponseCount": non_responder_ids.size(),
		"resultSummary": _shorten(result_summary),
		"confirmedRevision": maxi(confirmed_revision, 0),
	}


static func _participant_phase(
	matter: Dictionary,
	participant_status: String,
	active_activity: Dictionary,
) -> String:
	if participant_status == "assigned":
		return "responding"
	if String(active_activity.get("activityId", "")) == (
		"activity_bulletin_read"
	) and String(active_activity.get("phase", "")) == "performing":
		return "reading"
	if (
		String(matter.get("kind", "")) == "animal_attention"
		and String(active_activity.get("actionType", "")) == "待着"
	):
		return "observing"
	return "executing"


static func _reason_summary(matter: Dictionary) -> String:
	match String(matter.get("kind", "")):
		"place_service_pressure":
			var waiting_count := maxi(
				int(matter.get("capacity", 1)),
				1,
			)
			return _shorten("%d位客人正在等待" % waiting_count)
		"resident_request":
			var reason_summary := String(
				matter.get("reason_summary", "")
			).strip_edges()
			if not reason_summary.is_empty():
				return _shorten(reason_summary)
			var action_goal := (
				matter.get("source_action_goal", {}) as Dictionary
			)
			var target_refs := (
				action_goal.get("target_refs", {}) as Dictionary
			)
			var target_place := String(
				target_refs.get("place_id", "")
			).strip_edges()
			if not target_place.is_empty():
				return _shorten("有人请帮忙去%s" % target_place)
			return "有居民请人帮忙"
		"animal_attention":
			return "附近的小动物引起了关注"
		_:
			return "小镇里发生了一件公共事项"


static func _promise_summary(matter: Dictionary, phase: String) -> String:
	if phase == "reading":
		return ""
	match String(matter.get("kind", "")):
		"place_service_pressure":
			return "答应过来帮忙"
		"resident_request":
			return "答应回应这项请求"
		"animal_attention":
			return "决定留下来观察"
		_:
			return "答应参与这件事"


static func _execution_summary(matter: Dictionary, phase: String) -> String:
	if phase == "responding":
		return "准备履行刚才的约定"
	if phase == "reading":
		return "正在阅读社区公告"
	match String(matter.get("kind", "")):
		"place_service_pressure":
			return "正在帮忙接待客人"
		"resident_request":
			return "正在处理居民求助"
		"animal_attention":
			return "正在观察附近的小动物"
		_:
			return "正在处理这件公共事项"


static func _response_summary(responder_names: Array[String]) -> String:
	if responder_names.is_empty():
		return "没有居民回应这件事"
	if responder_names.size() == 1:
		return "%s回应了这件事" % responder_names[0]
	return "%s等%d人作出回应" % [
		responder_names[0],
		responder_names.size(),
	]


static func _result_summary(
	resident_name: String,
	outcome: String,
) -> String:
	var subject := (
		resident_name if not resident_name.is_empty() else "一名居民"
	)
	if outcome == "completed":
		return "%s完成了约定" % subject
	return "%s没能完成约定" % subject


static func _close_summary(close_reason: String) -> String:
	if close_reason.contains("expired"):
		return "这件事没有得到回应"
	if close_reason.contains("inactive"):
		return "事情已经自然结束"
	return "这件事已经结束"


static func _resident_names(
	resident_ids: Array[String],
	resident_names: Dictionary,
) -> Array[String]:
	var result: Array[String] = []
	for resident_id: String in resident_ids:
		var resident_name := String(
			resident_names.get(resident_id, "")
		)
		result.append(
			resident_name if not resident_name.is_empty() else resident_id
		)
	return result


static func _sorted_matters(matters: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in matters:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("matter_id", "")) < String(
				right.get("matter_id", "")
			)
	)
	return result


static func _sorted_string_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key_value: Variant in values:
		result.append(String(key_value))
	result.sort()
	return result


static func _matter_by_id(
	matters: Array[Dictionary],
	matter_id: String,
) -> Dictionary:
	for matter: Dictionary in matters:
		if String(matter.get("matter_id", "")) == matter_id:
			return matter
	return {}


static func _item_key(item: Dictionary) -> String:
	return "%s|%s|%s" % [
		String(item.get("matterId", "")),
		String(item.get("residentId", "")),
		String(item.get("phase", "")),
	]


static func _world_time(absolute_minute: int) -> Dictionary:
	if absolute_minute < 0:
		return {}
	return {
		"day": int(absolute_minute / 1440) + 1,
		"hour": int(absolute_minute / 60) % 24,
		"minute": absolute_minute % 60,
	}


static func _shorten(value: String) -> String:
	var normalized := (
		value.replace("\n", " ")
		.replace("\r", " ")
		.replace("\t", " ")
		.strip_edges()
	)
	if normalized.length() <= SUMMARY_MAX_LENGTH:
		return normalized
	return normalized.left(SUMMARY_MAX_LENGTH - 1) + "…"
