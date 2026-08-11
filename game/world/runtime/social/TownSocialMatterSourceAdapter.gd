class_name TownSocialMatterSourceAdapter
extends RefCounted


const RESULT_ENVELOPE := preload(
	"res://world/runtime/TownRuntimeResultEnvelope.gd"
)
var _social_runtime: RefCounted


func bind_social_runtime(runtime: RefCounted) -> void:
	_social_runtime = runtime


func sync_place_service_pressure(
	place_state: Dictionary,
	now: int,
) -> Dictionary:
	var required := _require_fields(
		place_state,
		[
			"pressure_id",
			"source_revision",
			"place_id",
			"owner_id",
			"open",
			"service_capacity",
			"active_workers",
			"waiting_requests",
			"helper_activity_id",
			"expires_at",
		],
	)
	if not bool(required.get("ok", false)):
		return required
	for field in [
		"pressure_id",
		"place_id",
		"helper_activity_id",
	]:
		if not _nonempty_text(place_state.get(field)):
			return _failure(
				"SOCIAL_SOURCE_FACT_INVALID",
				"%s 必须是非空字符串" % field,
			)
	if typeof(place_state.get("owner_id")) != TYPE_STRING:
		return _failure(
			"SOCIAL_SOURCE_FACT_INVALID",
			"owner_id 必须是字符串",
		)
	for field in [
		"source_revision",
		"service_capacity",
		"active_workers",
		"waiting_requests",
		"expires_at",
	]:
		if typeof(place_state.get(field)) != TYPE_INT:
			return _failure(
				"SOCIAL_SOURCE_FACT_INVALID",
				"%s 必须是整数" % field,
			)
	if typeof(place_state.get("open")) != TYPE_BOOL:
		return _failure(
			"SOCIAL_SOURCE_FACT_INVALID",
			"open 必须是布尔值",
		)
	var service_capacity := maxi(int(place_state.get("service_capacity")), 0)
	var active_workers := maxi(int(place_state.get("active_workers")), 0)
	var waiting_requests := maxi(int(place_state.get("waiting_requests")), 0)
	var owner_id := String(place_state.get("owner_id")).strip_edges()
	if bool(place_state.get("open")) and owner_id.is_empty():
		return _failure(
			"SOCIAL_SOURCE_FACT_INVALID",
			"营业中的地点必须有已确认负责人",
		)
	var staffed_capacity := mini(service_capacity, active_workers)
	var active := (
		bool(place_state.get("open"))
		and waiting_requests > staffed_capacity
	)
	var place_id := String(place_state.get("place_id")).strip_edges()
	return _sync_fact(
		{
			"source_kind": "place_service_pressure",
			"source_id": String(
				place_state.get("pressure_id")
			).strip_edges(),
			"source_revision": int(place_state.get("source_revision")),
			"active": active,
			"kind": "place_service_pressure",
			"source_event_ids": _event_ids(place_state),
			"creator_id": owner_id,
			"subject_ids": [place_id],
			"place_id": place_id,
			"expires_at": int(place_state.get("expires_at")),
			"capacity": maxi(
				1,
				waiting_requests - staffed_capacity,
			),
			"attention_level": "daily",
			"resolution_rules": [
				_resolution_rule("social.resolve.goal_completed"),
				_resolution_rule("social.resolve.service_reduced"),
				_resolution_rule("social.resolve.no_response"),
			],
			"close_resolver_id": "social.resolve.service_reduced",
			"close_reason": "service_pressure_cleared",
			"action_goal": {
				"capability_id": "world.perform_activity",
				"role": "temporary_helper",
				"target_refs": {
					"place_id": place_id,
					"activity_id": String(
						place_state.get("helper_activity_id")
					).strip_edges(),
				},
				"success_result_id": "service-help-completed",
			},
		},
		now,
	)


func sync_resident_request(
	request_state: Dictionary,
	now: int,
) -> Dictionary:
	var required := _require_fields(
		request_state,
		[
			"request_id",
			"source_revision",
			"requester_id",
			"submitted",
			"active",
			"subject_ids",
			"place_id",
			"capability_id",
			"target_refs",
			"success_result_id",
			"expires_at",
			"capacity",
		],
	)
	if not bool(required.get("ok", false)):
		return required
	for field in [
		"request_id",
		"requester_id",
		"capability_id",
		"success_result_id",
	]:
		if not _nonempty_text(request_state.get(field)):
			return _failure(
				"SOCIAL_SOURCE_FACT_INVALID",
				"%s 必须是非空字符串" % field,
			)
	if (
		typeof(request_state.get("submitted")) != TYPE_BOOL
		or typeof(request_state.get("active")) != TYPE_BOOL
		or typeof(request_state.get("source_revision")) != TYPE_INT
		or typeof(request_state.get("expires_at")) != TYPE_INT
		or typeof(request_state.get("capacity")) != TYPE_INT
		or typeof(request_state.get("subject_ids")) != TYPE_ARRAY
		or typeof(request_state.get("target_refs")) != TYPE_DICTIONARY
	):
		return _failure(
			"SOCIAL_SOURCE_FACT_INVALID",
			"居民请求字段类型无效",
		)
	var reason_summary := String(
		request_state.get("reason_summary", "")
	).strip_edges()
	if (
		typeof(request_state.get("reason_summary", "")) != TYPE_STRING
		or reason_summary.length() > 80
		or reason_summary.contains("\n")
		or reason_summary.contains("\r")
		or reason_summary.contains("\t")
	):
		return _failure(
			"SOCIAL_SOURCE_FACT_INVALID",
			"reason_summary 必须是最多80字的单行文字",
		)
	var requester_id := String(
		request_state.get("requester_id")
	).strip_edges()
	var subject_ids := _normalized_subjects(
		request_state.get("subject_ids", []) as Array,
	)
	if not subject_ids.has(requester_id):
		subject_ids.append(requester_id)
		subject_ids.sort()
	var active := (
		bool(request_state.get("submitted"))
		and bool(request_state.get("active"))
	)
	return _sync_fact(
		{
			"source_kind": "resident_request",
			"source_id": String(
				request_state.get("request_id")
			).strip_edges(),
			"source_revision": int(request_state.get("source_revision")),
			"active": active,
			"kind": "resident_request",
			"reason_summary": reason_summary,
			"source_event_ids": _event_ids(request_state),
			"creator_id": requester_id,
			"subject_ids": subject_ids,
			"place_id": String(
				request_state.get("place_id")
			).strip_edges(),
			"expires_at": int(request_state.get("expires_at")),
			"capacity": int(request_state.get("capacity")),
			"attention_level": "daily",
			"resolution_rules": [
				_resolution_rule("social.resolve.goal_completed"),
				_resolution_rule("social.resolve.no_response"),
			],
			"close_resolver_id": "social.resolve.source_cleared",
			"close_reason": "request_withdrawn",
			"action_goal": {
				"capability_id": String(
					request_state.get("capability_id")
				).strip_edges(),
				"role": "helper",
				"target_refs": (
					request_state.get("target_refs", {}) as Dictionary
				).duplicate(true),
				"success_result_id": String(
					request_state.get("success_result_id")
				).strip_edges(),
			},
		},
		now,
	)


func sync_conversation_commitment(
	commitment_state: Dictionary,
	now: int,
) -> Dictionary:
	var required := _require_fields(commitment_state, [
		"commitment_id", "source_revision", "conversation_id",
		"promisor_id", "beneficiary_id", "active", "reason_summary",
		"place_id", "capability_id", "target_refs", "success_result_id",
		"expires_at",
	])
	if not bool(required.get("ok", false)):
		return required
	for field: String in [
		"commitment_id", "conversation_id", "promisor_id",
		"beneficiary_id", "reason_summary", "capability_id",
		"success_result_id",
	]:
		if not _nonempty_text(commitment_state.get(field)):
			return _failure("SOCIAL_SOURCE_FACT_INVALID", "%s 必须是非空字符串" % field)
	if (
		typeof(commitment_state.get("source_revision")) != TYPE_INT
		or typeof(commitment_state.get("active")) != TYPE_BOOL
		or typeof(commitment_state.get("expires_at")) != TYPE_INT
		or typeof(commitment_state.get("target_refs")) != TYPE_DICTIONARY
	):
		return _failure("SOCIAL_SOURCE_FACT_INVALID", "对话承诺字段类型无效")
	var reason_summary := String(commitment_state.get("reason_summary", "")).strip_edges()
	if reason_summary.length() > 80 or "\n" in reason_summary or "\r" in reason_summary or "\t" in reason_summary:
		return _failure("SOCIAL_SOURCE_FACT_INVALID", "reason_summary 必须是最多80字的单行文字")
	var promisor_id := String(commitment_state.get("promisor_id", "")).strip_edges()
	var beneficiary_id := String(commitment_state.get("beneficiary_id", "")).strip_edges()
	var subjects: Array[String] = [promisor_id]
	if beneficiary_id != promisor_id:
		subjects.append(beneficiary_id)
	return _sync_fact({
		"source_kind": "conversation_commitment",
		"source_id": String(commitment_state.get("commitment_id", "")).strip_edges(),
		"source_revision": int(commitment_state.get("source_revision", 0)),
		"active": bool(commitment_state.get("active", false)),
		"kind": "resident_request",
		"reason_summary": reason_summary,
		"source_event_ids": _event_ids(commitment_state),
		"creator_id": beneficiary_id,
		"subject_ids": subjects,
		"place_id": String(commitment_state.get("place_id", "")).strip_edges(),
		"expires_at": int(commitment_state.get("expires_at", -1)),
		"capacity": 1,
		"attention_level": "daily",
		"resolution_rules": [
			_resolution_rule("social.resolve.goal_completed"),
			_resolution_rule("social.resolve.cancelled"),
		],
		"close_resolver_id": "social.resolve.source_cleared",
		"close_reason": "commitment_cancelled",
		"action_goal": {
			"capability_id": String(commitment_state.get("capability_id", "")).strip_edges(),
			"role": "promisor",
			"target_refs": (commitment_state.get("target_refs", {}) as Dictionary).duplicate(true),
			"success_result_id": String(commitment_state.get("success_result_id", "")).strip_edges(),
		},
	}, now)


func sync_animal_attention(
	animal_state: Dictionary,
	now: int,
) -> Dictionary:
	var required := _require_fields(
		animal_state,
		[
			"animal_id",
			"source_revision",
			"exists",
			"public_attention",
			"place_id",
			"expires_at",
		],
	)
	if not bool(required.get("ok", false)):
		return required
	if (
		not _nonempty_text(animal_state.get("animal_id"))
		or not _nonempty_text(animal_state.get("place_id"))
		or typeof(animal_state.get("source_revision")) != TYPE_INT
		or typeof(animal_state.get("exists")) != TYPE_BOOL
		or typeof(animal_state.get("public_attention")) != TYPE_BOOL
		or typeof(animal_state.get("expires_at")) != TYPE_INT
	):
		return _failure(
			"SOCIAL_SOURCE_FACT_INVALID",
			"动物关注字段无效",
		)
	var animal_id := String(animal_state.get("animal_id")).strip_edges()
	var place_id := String(animal_state.get("place_id")).strip_edges()
	var active := (
		bool(animal_state.get("exists"))
		and bool(animal_state.get("public_attention"))
	)
	return _sync_fact(
		{
			"source_kind": "animal_attention",
			"source_id": animal_id,
			"source_revision": int(animal_state.get("source_revision")),
			"active": active,
			"kind": "animal_attention",
			"source_event_ids": _event_ids(animal_state),
			"creator_id": "",
			"subject_ids": [animal_id],
			"place_id": place_id,
			"expires_at": int(animal_state.get("expires_at")),
			"capacity": 1,
			"attention_level": "daily",
			"resolution_rules": [
				_resolution_rule("social.resolve.goal_completed"),
				_resolution_rule("social.resolve.no_response"),
			],
			"close_resolver_id": "social.resolve.source_cleared",
			"close_reason": "animal_attention_ended",
			"action_goal": {
				"capability_id": "world.wait",
				"role": "observer",
				"target_refs": {
					"minutes": 5,
					"animal_id": animal_id,
					"place_id": place_id,
				},
				"success_result_id": "animal-observed",
			},
		},
		now,
	)


func sync_job_vacancy(
	vacancy_state: Dictionary,
	now: int,
) -> Dictionary:
	var required := _require_fields(
		vacancy_state,
		[
			"vacancy_id",
			"source_revision",
			"occupation_id",
			"occupation_label",
			"primary_place_id",
			"vacant",
			"vacancy_effect",
			"staffing_entry_rule",
			"candidate_resident_ids",
			"expires_at",
		],
	)
	if not bool(required.get("ok", false)):
		return required
	for field in [
		"vacancy_id",
		"occupation_id",
		"occupation_label",
		"primary_place_id",
		"vacancy_effect",
		"staffing_entry_rule",
	]:
		if not _nonempty_text(vacancy_state.get(field)):
			return _failure(
				"SOCIAL_SOURCE_FACT_INVALID",
				"%s 必须是非空字符串" % field,
			)
	if (
		typeof(vacancy_state.get("source_revision")) != TYPE_INT
		or typeof(vacancy_state.get("expires_at")) != TYPE_INT
		or typeof(vacancy_state.get("vacant")) != TYPE_BOOL
		or typeof(vacancy_state.get("candidate_resident_ids"))
		!= TYPE_ARRAY
	):
		return _failure(
			"SOCIAL_SOURCE_FACT_INVALID",
			"岗位空缺字段类型无效",
		)
	var occupation_id := String(
		vacancy_state.get("occupation_id"),
	).strip_edges()
	var occupation_label := String(
		vacancy_state.get("occupation_label"),
	).strip_edges()
	var candidate_resident_ids := _normalized_subjects(
		vacancy_state.get("candidate_resident_ids", []) as Array,
	)
	var reason_summary := "%s岗位目前空缺，相关服务已暂停或降级，居民可以协商是否自愿接手。" % (
		occupation_label
	)
	return _sync_fact(
		{
			"source_kind": "job_vacancy",
			"source_id": String(
				vacancy_state.get("vacancy_id"),
			).strip_edges(),
			"source_revision": int(
				vacancy_state.get("source_revision"),
			),
			"active": bool(vacancy_state.get("vacant")),
			"kind": "job_vacancy",
			"reason_summary": reason_summary,
			"source_event_ids": _event_ids(vacancy_state),
			"creator_id": "",
			"subject_ids": [occupation_id],
			"place_id": String(
				vacancy_state.get("primary_place_id"),
			).strip_edges(),
			"expires_at": int(vacancy_state.get("expires_at")),
			"capacity": 2,
			"attention_level": "daily",
			"resolution_rules": [
				_resolution_rule("social.resolve.goal_completed"),
				_resolution_rule("social.resolve.no_response"),
			],
			"close_resolver_id": "social.resolve.source_cleared",
			"close_reason": "job_vacancy_filled",
			"action_goal": {
				"capability_id": "staffing.apply_assignment",
				"role": "job_candidate",
				"target_refs": {
					"occupation_id": occupation_id,
					"assignment_kind": "transfer",
				},
				"success_result_id": "staffing-assignment-applied",
			},
			"candidate_resident_ids": candidate_resident_ids,
		},
		now,
	)


func job_vacancy_response_candidate(
	resident_id: String,
	ability_score: int,
	load: int,
	available_at: int,
	matter_id: String,
	allowed_assignment_modes: Array,
	from_occupation_id: String,
) -> Dictionary:
	if _social_runtime == null:
		return {}
	var matter := _social_runtime.get_matter(matter_id,) as Dictionary
	if (
		matter.is_empty()
		or String(matter.get("state", "")) == "closed"
		or String(matter.get("kind", "")) != "job_vacancy"
	):
		return {}
	var source_goal := (
		matter.get("source_action_goal", {}) as Dictionary
	).duplicate(true)
	var options: Array[Dictionary] = []
	if (
		allowed_assignment_modes.has("transfer")
		and not source_goal.is_empty()
	):
		var target_refs := (
			source_goal.get("target_refs", {}) as Dictionary
		).duplicate(true)
		target_refs["assignment_kind"] = "transfer"
		var normalized_from := from_occupation_id.strip_edges()
		if not normalized_from.is_empty():
			target_refs["from_occupation_id"] = normalized_from
		source_goal["target_refs"] = target_refs
		options.append({
			"option_id": "volunteer_transfer",
			"response_kind": "accept",
			"meaning": "自愿申请转到这个空缺岗位，由 World 核对后再生效",
			"allows_public_text": true,
			"action_goal": source_goal,
		})
	for mode_spec: Dictionary in [
		{
			"mode": "part_time",
			"option_id": "volunteer_part_time",
			"meaning": "先兼职协助这个岗位，保留当前正式职业",
		},
		{
			"mode": "shift",
			"option_id": "volunteer_shift_morning",
			"meaning": "承担上午轮班，保留当前正式职业",
			"shift_start_minute": 480,
			"shift_end_minute": 960,
		},
		{
			"mode": "shift",
			"option_id": "volunteer_shift_evening",
			"meaning": "承担下午和傍晚轮班，保留当前正式职业",
			"shift_start_minute": 960,
			"shift_end_minute": 1320,
		},
		{
			"mode": "trial",
			"option_id": "volunteer_trial",
			"meaning": "先试做实际任务，由结果决定是否形成资格",
		},
	]:
		var mode := String(mode_spec.get("mode", ""))
		if (
			not allowed_assignment_modes.has(mode)
			or source_goal.is_empty()
		):
			continue
		var arrangement_goal := source_goal.duplicate(true)
		var target_refs := (
			arrangement_goal.get(
				"target_refs",
				{},
			) as Dictionary
		).duplicate(true)
		target_refs["assignment_kind"] = mode
		var normalized_from := from_occupation_id.strip_edges()
		if not normalized_from.is_empty():
			target_refs["from_occupation_id"] = normalized_from
		if mode == "shift":
			target_refs["shift_start_minute"] = String.num_int64(
				int(mode_spec.get("shift_start_minute", 0)),
			)
			target_refs["shift_end_minute"] = String.num_int64(
				int(mode_spec.get("shift_end_minute", 1440)),
			)
		arrangement_goal["target_refs"] = target_refs
		options.append({
			"option_id": String(mode_spec.get("option_id", "")),
			"response_kind": "accept",
			"meaning": String(mode_spec.get("meaning", "")),
			"allows_public_text": true,
			"action_goal": arrangement_goal,
		})
	options.append({
		"option_id": "keep_current_job",
		"response_kind": "reject",
		"meaning": "保留现在的职业，不申请本次转岗",
		"allows_public_text": true,
	})
	options.append({
		"option_id": "consider_later",
		"response_kind": "defer",
		"meaning": "这次先不决定，岗位继续保持空缺",
		"allows_public_text": true,
	})
	return {
		"resident_id": resident_id.strip_edges(),
		"ability_score": ability_score,
		"load": load,
		"available_at": available_at,
		"options": options,
	}


func response_candidate(
	resident_id: String,
	ability_score: int,
	load: int,
	available_at: int,
	matter_id: String,
) -> Dictionary:
	if _social_runtime == null:
		return {}
	var matter := _social_runtime.get_matter(matter_id,) as Dictionary
	if matter.is_empty() or String(matter.get("state", "")) == "closed":
		return {}
	var action_goal := matter.get("source_action_goal", {}) as Dictionary
	if action_goal.is_empty():
		return {}
	return {
		"resident_id": resident_id.strip_edges(),
		"ability_score": ability_score,
		"load": load,
		"available_at": available_at,
		"options": [
			{
				"option_id": "accept",
				"response_kind": "accept",
				"allows_public_text": true,
				"action_goal": action_goal.duplicate(true),
			},
			{
				"option_id": "decline",
				"response_kind": "reject",
				"allows_public_text": true,
			},
			{
				"option_id": "defer",
				"response_kind": "defer",
				"allows_public_text": true,
			},
		],
	}


func _sync_fact(fact: Dictionary, now: int) -> Dictionary:
	if _social_runtime == null:
		return _failure(
			"SOCIAL_SOURCE_RUNTIME_MISSING",
			"社会事项来源尚未绑定运行时",
		)
	var active := bool(fact.get("active", false))
	if (
		now < 0
		or int(fact.get("source_revision", -1)) < 0
		or (
			active
			and (
				int(fact.get("expires_at", -1)) <= now
				or int(fact.get("capacity", 0)) <= 0
			)
		)
	):
		return _failure(
			"SOCIAL_SOURCE_FACT_INVALID",
			"来源时间、修订或容量无效",
		)
	var source_kind := String(fact.get("source_kind", ""))
	var source_id := String(fact.get("source_id", ""))
	var subject_ids := fact.get("subject_ids", []) as Array
	var existing := _social_runtime.find_active_matter(source_kind,
		source_id,
		subject_ids,) as Dictionary
	if not active:
		if existing.is_empty():
			return _success({
				"action": "none",
				"matter": {},
			})
		var closed := _social_runtime.close_matter(String(existing.get("matter_id", "")),
			String(fact.get("close_resolver_id", "")),
			String(fact.get("close_reason", "")),
			[],
			now,) as Dictionary
		if not bool(closed.get("ok", false)):
			return closed
		return _success({
			"action": "closed",
			"matter": (
				closed.get("value", {}) as Dictionary
			).duplicate(true),
		})
	if not existing.is_empty():
		var updated := _social_runtime.update_source_state(String(existing.get("matter_id", "")),
			int(fact.get("source_revision", 0)),
			true,
			now,
			[],
			{
				"capacity": int(fact.get("capacity", 1)),
				"expires_at": int(fact.get("expires_at", -1)),
				"place_id": String(fact.get("place_id", "")),
				"reason_summary": String(
					fact.get("reason_summary", "")
				),
				"source_event_ids": (
					fact.get("source_event_ids", []) as Array
				).duplicate(),
			},) as Dictionary
		if not bool(updated.get("ok", false)):
			return updated
		var updated_matter := updated.get("value", {}) as Dictionary
		var goal_result := _social_runtime.set_source_action_goal(String(updated_matter.get("matter_id", "")),
			fact.get("action_goal", {}) as Dictionary,) as Dictionary
		if not bool(goal_result.get("ok", false)):
			return goal_result
		updated_matter = _social_runtime.get_matter(String(updated_matter.get("matter_id", "")),) as Dictionary
		return _success({
			"action": "updated",
			"matter": updated_matter.duplicate(true),
		})
	var created := _social_runtime.create_matter({
			"kind": String(fact.get("kind", "")),
			"source_event_ids": fact.get("source_event_ids", []),
			"source_state_ref": {
				"source_kind": source_kind,
				"source_id": source_id,
				"source_revision": int(fact.get("source_revision", 0)),
			},
			"creator_id": String(fact.get("creator_id", "")),
			"subject_ids": subject_ids,
			"resolution_rules": fact.get("resolution_rules", []),
			"place_id": String(fact.get("place_id", "")),
			"reason_summary": String(
				fact.get("reason_summary", "")
			),
			"created_at": now,
			"expires_at": int(fact.get("expires_at", -1)),
			"capacity": int(fact.get("capacity", 1)),
			"initial_state": "open",
			"attention_level": String(
				fact.get("attention_level", "daily")
			),
		},) as Dictionary
	if not bool(created.get("ok", false)):
		return created
	var matter := (
		(
			created.get("value", {}) as Dictionary
		).get("matter", {}) as Dictionary
	)
	var goal_result := _social_runtime.set_source_action_goal(String(matter.get("matter_id", "")),
		fact.get("action_goal", {}) as Dictionary,) as Dictionary
	if not bool(goal_result.get("ok", false)):
		return goal_result
	matter = _social_runtime.get_matter(String(matter.get("matter_id", "")),) as Dictionary
	return _success({
		"action": (
			"created"
			if bool(
				(created.get("value", {}) as Dictionary).get("created", false)
			)
			else "existing"
		),
		"matter": matter.duplicate(true),
	})


func _event_ids(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var raw_value: Variant = value.get("source_event_ids", [])
	if typeof(raw_value) != TYPE_ARRAY:
		return result
	for event_value: Variant in raw_value as Array:
		if typeof(event_value) != TYPE_STRING:
			continue
		var event_id := String(event_value).strip_edges()
		if not event_id.is_empty() and not result.has(event_id):
			result.append(event_id)
	result.sort()
	return result


func _normalized_subjects(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		if typeof(value) != TYPE_STRING:
			continue
		var subject_id := String(value).strip_edges()
		if not subject_id.is_empty() and not result.has(subject_id):
			result.append(subject_id)
	result.sort()
	return result


func _resolution_rule(resolver_id: String) -> Dictionary:
	return {
		"resolver_id": resolver_id,
		"params": {},
	}


func _require_fields(value: Dictionary, fields: Array) -> Dictionary:
	for field_value: Variant in fields:
		var field := String(field_value)
		if not value.has(field):
			return _failure(
				"SOCIAL_SOURCE_FACT_INVALID",
				"来源事实缺少 %s" % field,
			)
	return _success({})


func _nonempty_text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty()


func _success(value: Variant) -> Dictionary:
	return RESULT_ENVELOPE.success(value)


func _failure(error_code: String, reason: String) -> Dictionary:
	return RESULT_ENVELOPE.failure(error_code, reason)
