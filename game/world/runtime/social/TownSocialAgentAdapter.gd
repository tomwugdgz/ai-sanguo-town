class_name TownSocialAgentAdapter
extends RefCounted


var _social_runtime: RefCounted


func bind_social_runtime(runtime: RefCounted) -> void:
	_social_runtime = runtime


func build_social_matters(
	resident_id: String,
	now: int = -1,
) -> Array[Dictionary]:
	if _social_runtime == null:
		return []
	var normalized_resident := resident_id.strip_edges()
	if normalized_resident.is_empty():
		return []
	var result: Array[Dictionary] = []
	for matter_value: Variant in _social_runtime.list_matters(false,) as Array:
		var matter := matter_value as Dictionary
		var awareness := matter.get("awareness", {}) as Dictionary
		if not awareness.has(normalized_resident):
			continue
		result.append(
			_project_matter_for_resident(
				matter,
				normalized_resident,
				now,
			)
		)
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_expiry := int(left.get("expires_at", -1))
			var right_expiry := int(right.get("expires_at", -1))
			if left_expiry != right_expiry:
				return left_expiry < right_expiry
			return String(left.get("matter_id", "")) < String(
				right.get("matter_id", "")
			)
	)
	return result


func submit_social_response(
	resident_id: String,
	response: Dictionary,
	submitted_at: int,
) -> Dictionary:
	if _social_runtime == null:
		return {
			"ok": false,
			"error_code": "SOCIAL_RUNTIME_MISSING",
			"reason": "社会事项运行时尚未绑定",
		}
	return _social_runtime.submit_response(resident_id,
		response,
		submitted_at,) as Dictionary


func take_social_response_results(
	resident_id: String,
) -> Array[Dictionary]:
	if _social_runtime == null:
		return []
	return _social_runtime.drain_receipts(resident_id,) as Array[Dictionary]


func _project_matter_for_resident(
	matter: Dictionary,
	resident_id: String,
	now: int,
) -> Dictionary:
	var options: Array[Dictionary] = []
	var assignment: Variant = null
	var projected_response_round_id := String(
		matter.get("response_round_id", "")
	)
	var projected_response_window_until := int(
		matter.get("response_window_until", -1)
	)
	if String(matter.get("state", "")) == "collecting":
		var candidate := _candidate(
			matter.get("fixed_candidates", []) as Array,
			resident_id,
		)
		if not candidate.is_empty() and not bool(
			candidate.get("terminal", false)
		):
			for option_value: Variant in candidate.get("options", []) as Array:
				var option := option_value as Dictionary
				options.append({
					"option_id": String(option.get("option_id", "")),
					"response_kind": String(
						option.get("response_kind", "")
					),
					"meaning": _option_meaning(
						String(option.get("response_kind", "")),
						String(option.get("meaning", "")),
					),
					"allows_public_text": bool(
						option.get("allows_public_text", false)
					),
				})
	var participant := (
		(matter.get("participants", {}) as Dictionary).get(
			resident_id,
			{},
		) as Dictionary
	)
	if (
		not participant.is_empty()
		and String(participant.get("status", "")) in [
			"assigned",
			"executing",
		]
	):
		var action_goal := participant.get("action_goal", {}) as Dictionary
		var goal_id := String(action_goal.get("goal_id", ""))
		projected_response_round_id = "assignment:%s" % goal_id
		var deferred_until := int(
			participant.get("deferred_until", -1)
		)
		if now < 0 or deferred_until < 0 or now >= deferred_until:
			projected_response_window_until = int(
				matter.get("expires_at", -1)
			)
			options.append({
				"option_id": "defer_assignment",
				"response_kind": "defer",
				"meaning": "本轮暂不履行，稍后再决定",
				"allows_public_text": true,
			})
			options.append({
				"option_id": "withdraw_assignment",
				"response_kind": "withdraw",
				"meaning": "明确退出已经确认的承诺",
				"allows_public_text": true,
			})
		assignment = {
			"goal_id": goal_id,
			"role": String(participant.get("role", "")),
			"status": String(participant.get("status", "")),
			"capability_id": String(
				action_goal.get("capability_id", "")
			),
			"target_refs": (
				action_goal.get("target_refs", {}) as Dictionary
			).duplicate(true),
			"success_result_id": String(
				action_goal.get("success_result_id", "")
			),
		}
	return {
		"matter_id": String(matter.get("matter_id", "")),
		"revision": int(matter.get("revision", 0)),
		"kind": String(matter.get("kind", "")),
		"summary": _matter_summary(matter),
		"expires_at": int(matter.get("expires_at", -1)),
		"response_round_id": (
			projected_response_round_id
			if not projected_response_round_id.is_empty()
			else null
		),
			"response_window_until": (
				projected_response_window_until
				if projected_response_window_until >= 0
				else null
			),
			"options": options,
			"assignment": assignment,
	}


func _candidate(candidates: Array, resident_id: String) -> Dictionary:
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		if String(candidate.get("resident_id", "")) == resident_id:
			return candidate
	return {}


func _matter_summary(matter: Dictionary) -> String:
	var place_id := String(matter.get("place_id", "")).strip_edges()
	match String(matter.get("kind", "")):
		"place_service_pressure":
			var waiting_count := maxi(
				int(matter.get("capacity", 1)),
				1,
			)
			return "%s店里忙不过来，有%d位客人等待，需要临时帮忙接待。" % [
				_readable_subject(place_id, "公共地点"),
				waiting_count,
			]
		"resident_request":
			var reason_summary := String(
				matter.get("reason_summary", "")
			).strip_edges()
			if not reason_summary.is_empty():
				return reason_summary
			var action_goal := (
				matter.get("source_action_goal", {}) as Dictionary
			)
			var target_refs := (
				action_goal.get("target_refs", {}) as Dictionary
			)
			var target_place := String(
				target_refs.get("place_id", place_id)
			).strip_edges()
			if not target_place.is_empty():
				return "有居民请人前往%s帮忙。" % target_place
			return "一名居民请人帮忙处理一件事。"
		"animal_attention":
			return (
				"%s附近有小动物引起了公共关注。"
				% _readable_subject(place_id, "小镇")
			)
		_:
			return "小镇里出现了一件需要回应的公共事项。"


func _readable_subject(value: String, fallback: String) -> String:
	return fallback if value.is_empty() else value


func _option_meaning(
	response_kind: String,
	authored_meaning: String = "",
) -> String:
	var normalized := authored_meaning.strip_edges()
	if not normalized.is_empty():
		return normalized
	match response_kind:
		"accept":
			return "愿意参与，等待 World 统一选择"
		"reject":
			return "明确拒绝本次事项"
		"defer":
			return "暂时不决定，稍后再考虑"
		"withdraw":
			return "退出已经表达过的参与意向"
		_:
			return "不提交新的社会回应"
