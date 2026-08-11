class_name TownSocialMatterRuntime
extends RefCounted


const RESULT_ENVELOPE := preload(
	"res://world/runtime/TownRuntimeResultEnvelope.gd"
)
const REGISTRY_SCRIPT := preload(
	"res://world/runtime/social/TownSocialRegistry.gd"
)

const STATES := [
	"latent",
	"open",
	"collecting",
	"assigned",
	"executing",
	"closed",
]
const RESPONSE_KINDS := [
	"accept",
	"reject",
	"defer",
	"withdraw",
]
const TERMINAL_CANDIDATE_REASONS := [
	"provider_failed",
	"provider_timeout",
	"request_cancelled",
]
const NO_RESPONSE_OUTCOMES := [
	"reopen",
	"close",
]
const SOCIAL_RESPONSE_FIELDS := [
	"response_id",
	"matter_id",
	"matter_revision",
	"response_round_id",
	"option_id",
	"public_text",
]
const PUBLIC_RESPONSE_TEXT_MAX_LENGTH := 80
const MAX_ACTIVE_COMMITMENTS_PER_RESIDENT := 1
const AWARENESS_LEVELS := [
	"partial",
	"known",
]
const AWARENESS_SOURCES := [
	"witnessed",
	"bulletin_read",
	"relayed",
	"direct_request",
	"direct_conversation",
	"announcement_broadcast",
	"town_bell",
	"postal_notice",
]
const CHANNEL_KINDS := [
	"direct_request",
	"bulletin",
	"public_expression",
]
const INVOLVEMENT_ROLES := [
	"creator",
	"affected",
	"participant",
	"observer",
]
const EXPOSURE_CHANNELS := [
	"visible",
	"audible",
	"direct_request",
	"bulletin",
	"relayed",
	"experienced",
]
const EXPOSURE_STATUSES := [
	"pending",
	"deferred",
	"noticed",
	"ignored",
	"expired",
]
const ATTENTION_OPTIONS := [
	"notice",
	"ignore",
	"defer",
]
const MAX_RETAINED_CLOSED_MATTERS := 64

var _registry: RefCounted = REGISTRY_SCRIPT.new()
var _matters_by_id: Dictionary = {}
var _active_matter_id_by_source_key: Dictionary = {}
var _receipts_by_resident: Dictionary = {}
var _receipt_by_response_key: Dictionary = {}
var _matter_sequence := 0
var _round_sequence := 0
var _goal_sequence := 0


func reset() -> void:
	_matters_by_id.clear()
	_active_matter_id_by_source_key.clear()
	_receipts_by_resident.clear()
	_receipt_by_response_key.clear()
	_matter_sequence = 0
	_round_sequence = 0
	_goal_sequence = 0


func create_matter(spec: Dictionary) -> Dictionary:
	var validation := _validate_matter_spec(spec)
	if not bool(validation.get("ok", false)):
		return validation
	var normalized := (
		validation.get("value", {}) as Dictionary
	).duplicate(true)
	var source_key := _source_key(
		normalized.get("source_state_ref", {}) as Dictionary,
		normalized.get("subject_ids", []) as Array,
	)
	if _active_matter_id_by_source_key.has(source_key):
		var existing_id := String(
			_active_matter_id_by_source_key.get(source_key, "")
		)
		var existing := _matters_by_id.get(existing_id, {}) as Dictionary
		if not existing.is_empty() and String(existing.get("state", "")) != "closed":
			return _success({
				"created": false,
				"matter": existing.duplicate(true),
			})
	var requested_id := String(normalized.get("matter_id", "")).strip_edges()
	var matter_id := requested_id
	if matter_id.is_empty():
		_matter_sequence += 1
		matter_id = "matter-%06d" % _matter_sequence
	elif _matters_by_id.has(matter_id):
		return _failure(
			"SOCIAL_MATTER_ID_CONFLICT",
			"matter_id 已经存在",
		)
	var matter := {
		"matter_id": matter_id,
		"kind": normalized.get("kind"),
		"source_event_ids": normalized.get("source_event_ids"),
		"source_state_ref": normalized.get("source_state_ref"),
		"parent_matter_id": normalized.get("parent_matter_id"),
		"creator_id": normalized.get("creator_id"),
		"subject_ids": normalized.get("subject_ids"),
		"resolution_rules": normalized.get("resolution_rules"),
		"reason_summary": normalized.get("reason_summary"),
		"source_action_goal": {},
		"channels": [],
		"channel_revision": 0,
		"participants": {},
		"awareness": {},
		"involvement": {},
		"exposures": {},
		"place_id": normalized.get("place_id"),
		"created_at": normalized.get("created_at"),
		"expires_at": normalized.get("expires_at"),
		"response_round_id": "",
		"response_window_until": -1,
		"fixed_candidates": [],
		"candidate_results": {},
		"response_history": [],
		"capacity": normalized.get("capacity"),
		"state": normalized.get("initial_state"),
		"revision": 1,
		"close_reason": "",
		"closed_at": -1,
		"attention_level": normalized.get("attention_level"),
		"result_refs": [],
	}
	_matters_by_id[matter_id] = matter
	_active_matter_id_by_source_key[source_key] = matter_id
	return _success({
		"created": true,
		"matter": matter.duplicate(true),
	})


func activate_matter(matter_id: String) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	var state := String(matter.get("state", ""))
	if state == "open":
		return _success(matter.duplicate(true))
	if state != "latent":
		return _failure(
			"SOCIAL_STATE_INVALID",
			"只有 latent 事项可以公开",
		)
	matter["state"] = "open"
	_increment_revision(matter)
	return _success(matter.duplicate(true))


func set_source_action_goal(
	matter_id: String,
	action_goal: Dictionary,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) == "closed":
		return _failure(
			"SOCIAL_MATTER_CLOSED",
			"已关闭事项不能更换行动目标",
		)
	var validation := _registry.validate_action_goal(action_goal,) as Dictionary
	if not bool(validation.get("ok", false)):
		return validation
	var normalized := (
		validation.get("value", {}) as Dictionary
	).duplicate(true)
	if normalized == matter.get("source_action_goal", {}):
		return _success(normalized)
	if String(matter.get("state", "")) == "collecting":
		return _failure(
			"SOCIAL_RESPONSE_STATE_INVALID",
			"回应收集中不能更换行动目标",
		)
	matter["source_action_goal"] = normalized
	_increment_revision(matter)
	return _success(normalized)


func add_channel(
	matter_id: String,
	channel: Dictionary,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) == "closed":
		return _failure(
			"SOCIAL_CHANNEL_STATE_INVALID",
			"已关闭事项不能增加传播渠道",
		)
	var normalized_result := _validate_channel(channel)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result
	var normalized := (
		normalized_result.get("value", {}) as Dictionary
	).duplicate(true)
	var channels := matter.get("channels", []) as Array
	for index in channels.size():
		var existing := channels[index] as Dictionary
		if (
			String(existing.get("channel_kind", ""))
			== String(normalized.get("channel_kind", ""))
			and String(existing.get("source_id", ""))
			== String(normalized.get("source_id", ""))
		):
			channels[index] = normalized
			matter["channel_revision"] = int(
				matter.get("channel_revision", 0)
			) + 1
			return _success(matter.duplicate(true))
	channels.append(normalized)
	channels.sort_custom(
		func(left: Variant, right: Variant) -> bool:
			var left_channel := left as Dictionary
			var right_channel := right as Dictionary
			return (
				"%s|%s"
				% [
					String(left_channel.get("channel_kind", "")),
					String(left_channel.get("source_id", "")),
				]
				<
				"%s|%s"
				% [
					String(right_channel.get("channel_kind", "")),
					String(right_channel.get("source_id", "")),
				]
			)
	)
	matter["channel_revision"] = int(
		matter.get("channel_revision", 0)
	) + 1
	return _success(matter.duplicate(true))


func record_awareness(
	matter_id: String,
	resident_id: String,
	awareness: String,
	acquired_via: String,
	source_id: String,
	updated_at: int,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) == "closed":
		return _failure("SOCIAL_MATTER_CLOSED", "已关闭事项不能增加知情")
	var normalized_resident := resident_id.strip_edges()
	var normalized_source := source_id.strip_edges()
	if (
		normalized_resident.is_empty()
		or normalized_source.is_empty()
		or awareness not in AWARENESS_LEVELS
		or acquired_via not in AWARENESS_SOURCES
		or updated_at < 0
	):
		return _failure(
			"SOCIAL_AWARENESS_INVALID",
			"知情记录字段无效",
		)
	var awareness_records := matter.get("awareness", {}) as Dictionary
	var current := awareness_records.get(normalized_resident, {}) as Dictionary
	if not current.is_empty():
		if (
			_awareness_level_rank(
				String(current.get("awareness", ""))
			)
			> _awareness_level_rank(awareness)
		):
			awareness = String(current.get("awareness", ""))
		var current_rank := _awareness_source_rank(
			String(current.get("acquired_via", ""))
		)
		var next_rank := _awareness_source_rank(acquired_via)
		if (
			next_rank < current_rank
			and updated_at <= int(current.get("updated_at", -1))
		):
			return _success(current.duplicate(true))
		if (
			String(current.get("awareness", "")) == awareness
			and String(current.get("acquired_via", "")) == acquired_via
			and String(current.get("source_id", "")) == normalized_source
		):
			return _success(current.duplicate(true))
	var next_record := {
		"awareness": awareness,
		"acquired_via": acquired_via,
		"source_id": normalized_source,
		"updated_at": updated_at,
	}
	if next_record == current:
		return _success(current.duplicate(true))
	awareness_records[normalized_resident] = next_record
	_increment_revision(matter)
	return _success(
		(awareness_records[normalized_resident] as Dictionary).duplicate(true)
	)


func record_involvement(
	matter_id: String,
	resident_id: String,
	role: String,
	updated_at: int,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) == "closed":
		return _failure("SOCIAL_MATTER_CLOSED", "已关闭事项不能增加事项关系")
	var normalized_resident := resident_id.strip_edges()
	if (
		normalized_resident.is_empty()
		or role not in INVOLVEMENT_ROLES
		or updated_at < 0
	):
		return _failure("SOCIAL_INVOLVEMENT_INVALID", "事项关系字段无效")
	var records := matter.get("involvement", {}) as Dictionary
	var next_record := {
		"role": role,
		"updated_at": updated_at,
	}
	if records.get(normalized_resident, {}) == next_record:
		return _success(next_record.duplicate(true))
	records[normalized_resident] = next_record
	_increment_revision(matter)
	return _success(next_record.duplicate(true))


func offer_exposure(
	matter_id: String,
	resident_id: String,
	channel: String,
	clue: String,
	source_id: String,
	created_at: int,
	expires_at: int,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) == "closed":
		return _failure("SOCIAL_MATTER_CLOSED", "已关闭事项不能产生接触机会")
	var normalized_resident := resident_id.strip_edges()
	var normalized_clue := clue.strip_edges()
	var normalized_source := source_id.strip_edges()
	if (
		normalized_resident.is_empty()
		or channel not in EXPOSURE_CHANNELS
		or normalized_clue.is_empty()
		or normalized_clue.length() > 80
		or normalized_clue.contains("\n")
		or normalized_source.is_empty()
		or created_at < 0
		or expires_at <= created_at
	):
		return _failure("SOCIAL_EXPOSURE_INVALID", "接触机会字段无效")
	var source_revision := int(
		(matter.get("source_state_ref", {}) as Dictionary).get(
			"source_revision",
			0,
		)
	)
	var exposure_id := "%s-x-%s-r%d" % [
		matter_id,
		normalized_resident,
		source_revision,
	]
	var exposures := matter.get("exposures", {}) as Dictionary
	var existing := exposures.get(exposure_id, {}) as Dictionary
	if not existing.is_empty():
		return _success(existing.duplicate(true))
	var exposure := {
		"exposure_id": exposure_id,
		"resident_id": normalized_resident,
		"matter_revision": int(matter.get("revision", 0)),
		"channel": channel,
		"clue": normalized_clue,
		"source_id": normalized_source,
		"created_at": created_at,
		"expires_at": mini(
			expires_at,
			int(matter.get("expires_at", expires_at)),
		),
		"status": "pending",
		"reconsider_at": -1,
		"handled_at": -1,
	}
	exposures[exposure_id] = exposure
	_increment_revision(matter)
	exposure["matter_revision"] = int(matter.get("revision", 0))
	return _success(exposure.duplicate(true))


func exposures_for(
	resident_id: String,
	now: int,
) -> Array[Dictionary]:
	var normalized_resident := resident_id.strip_edges()
	var result: Array[Dictionary] = []
	if normalized_resident.is_empty() or now < 0:
		return result
	for matter_value: Variant in _matters_by_id.values():
		var matter := matter_value as Dictionary
		if String(matter.get("state", "")) == "closed":
			continue
		for exposure_value: Variant in (
			matter.get("exposures", {}) as Dictionary
		).values():
			var exposure := exposure_value as Dictionary
			if (
				String(exposure.get("resident_id", ""))
				!= normalized_resident
				or not _exposure_is_actionable(exposure, now)
			):
				continue
			var projected := exposure.duplicate(true)
			projected["matter_id"] = String(
				matter.get("matter_id", "")
			)
			projected["matter_revision"] = int(
				matter.get("revision", 0)
			)
			projected["options"] = ATTENTION_OPTIONS.duplicate()
			result.append(projected)
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if int(left.get("expires_at", -1)) != int(
				right.get("expires_at", -1)
			):
				return int(left.get("expires_at", -1)) < int(
					right.get("expires_at", -1)
				)
			return String(left.get("exposure_id", "")) < String(
				right.get("exposure_id", "")
			)
	)
	return result


func actionable_exposure_resident_ids(
	resident_ids: Array,
	now: int,
) -> Array[String]:
	var result: Array[String] = []
	if resident_ids.is_empty() or now < 0:
		return result
	var requested: Dictionary = {}
	for resident_value: Variant in resident_ids:
		var normalized := String(resident_value).strip_edges()
		if not normalized.is_empty():
			requested[normalized] = true
	var actionable: Dictionary = {}
	for matter_value: Variant in _matters_by_id.values():
		var matter := matter_value as Dictionary
		if String(matter.get("state", "")) == "closed":
			continue
		for exposure_value: Variant in (
			matter.get("exposures", {}) as Dictionary
		).values():
			var exposure := exposure_value as Dictionary
			var resident_id := String(
				exposure.get("resident_id", "")
			)
			if (
				requested.has(resident_id)
				and _exposure_is_actionable(exposure, now)
			):
				actionable[resident_id] = true
	for resident_value: Variant in resident_ids:
		var resident_id := String(resident_value)
		if actionable.has(resident_id) and not result.has(resident_id):
			result.append(resident_id)
	return result


func resolve_exposure(
	matter_id: String,
	resident_id: String,
	attention: Dictionary,
	now: int,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	var exposure_id := String(
		attention.get("exposure_id", "")
	).strip_edges()
	var option_id := String(attention.get("option_id", "")).strip_edges()
	var exposures := matter.get("exposures", {}) as Dictionary
	var exposure := exposures.get(exposure_id, {}) as Dictionary
	if (
		exposure.is_empty()
		or String(exposure.get("resident_id", ""))
		!= resident_id.strip_edges()
		or option_id not in ATTENTION_OPTIONS
		or now < 0
		or int(exposure.get("expires_at", -1)) <= now
		or String(exposure.get("status", "")) not in [
			"pending",
			"deferred",
		]
	):
		return _failure("SOCIAL_EXPOSURE_STALE", "接触机会已经失效")
	if option_id == "defer":
		exposure["status"] = "deferred"
		exposure["reconsider_at"] = mini(
			now + 10,
			int(exposure.get("expires_at", now + 10)) - 1,
		)
		exposure["handled_at"] = now
	else:
		exposure["status"] = (
			"noticed" if option_id == "notice" else "ignored"
		)
		exposure["reconsider_at"] = -1
		exposure["handled_at"] = now
	_increment_revision(matter)
	if option_id == "notice":
		var awareness_result := record_awareness(
			matter_id,
			resident_id,
			"partial",
			"witnessed",
			String(exposure.get("source_id", "")),
			now,
		)
		if awareness_result.get("ok") != true:
			return awareness_result
	return _success(exposure.duplicate(true))


func expire_exposures(now: int) -> Array[Dictionary]:
	var expired: Array[Dictionary] = []
	for matter_value: Variant in _matters_by_id.values():
		var matter := matter_value as Dictionary
		if String(matter.get("state", "")) == "closed":
			continue
		var changed := false
		for exposure_value: Variant in (
			matter.get("exposures", {}) as Dictionary
		).values():
			var exposure := exposure_value as Dictionary
			if (
				String(exposure.get("status", "")) in [
					"pending",
					"deferred",
				]
				and int(exposure.get("expires_at", -1)) <= now
			):
				exposure["status"] = "expired"
				exposure["handled_at"] = now
				expired.append(exposure.duplicate(true))
				changed = true
		if changed:
			_increment_revision(matter)
	return expired


func begin_response_round(
	matter_id: String,
	candidates: Array,
	started_at: int,
	response_window_until: int,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) != "open":
		return _failure(
			"SOCIAL_RESPONSE_STATE_INVALID",
			"只有 open 事项可以开始回应轮次",
		)
	if (
		started_at < 0
		or response_window_until <= started_at
		or candidates.is_empty()
	):
		return _failure(
			"SOCIAL_RESPONSE_ROUND_INVALID",
			"回应轮次的时间或候选无效",
		)
	var frozen_candidates: Array[Dictionary] = []
	var seen_residents := {}
	var awareness_records := matter.get("awareness", {}) as Dictionary
	for candidate_value: Variant in candidates:
		var candidate_result := _validate_candidate(candidate_value)
		if not bool(candidate_result.get("ok", false)):
			return candidate_result
		var candidate := (
			candidate_result.get("value", {}) as Dictionary
		).duplicate(true)
		var resident_id := String(candidate.get("resident_id", ""))
		if seen_residents.has(resident_id):
			return _failure(
				"SOCIAL_RESPONSE_CANDIDATE_DUPLICATE",
				"回应候选不能重复",
			)
		if not awareness_records.has(resident_id):
			return _failure(
				"SOCIAL_RESPONSE_CANDIDATE_UNAWARE",
				"未实际知情的居民不能进入回应候选",
			)
		seen_residents[resident_id] = true
		candidate["terminal"] = false
		candidate["terminal_reason"] = ""
		candidate["response"] = {}
		frozen_candidates.append(candidate)
	frozen_candidates.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("resident_id", "")) < String(
				right.get("resident_id", "")
			)
	)
	_round_sequence += 1
	_increment_revision(matter)
	var round_id := "%s-r%d" % [matter_id, _round_sequence]
	matter["state"] = "collecting"
	matter["response_round_id"] = round_id
	matter["response_window_until"] = response_window_until
	matter["fixed_candidates"] = frozen_candidates
	matter["candidate_results"] = {}
	return _success({
		"matter_id": matter_id,
		"matter_revision": int(matter.get("revision", 0)),
		"response_round_id": round_id,
		"candidate_ids": _candidate_ids(frozen_candidates),
	})


func submit_response(
	resident_id: String,
	response: Dictionary,
	submitted_at: int,
) -> Dictionary:
	var normalized_resident := resident_id.strip_edges()
	for key_value: Variant in response:
		if (
			not key_value is String
			or key_value not in SOCIAL_RESPONSE_FIELDS
		):
			return _rejected_submit(
				normalized_resident,
				(
					String(response.get("response_id", ""))
					if response.get("response_id") is String
					else ""
				),
				(
					String(response.get("matter_id", ""))
					if response.get("matter_id") is String
					else ""
				),
				"社会回应包含未知字段：%s" % str(key_value),
			)
	var response_id_result := _required_text(response, "response_id")
	var matter_id_result := _required_text(response, "matter_id")
	if not bool(response_id_result.get("ok", false)):
		return _rejected_submit(
			normalized_resident,
			"",
			"",
			String(response_id_result.get("reason", "")),
		)
	if not bool(matter_id_result.get("ok", false)):
		return _rejected_submit(
			normalized_resident,
			String(response_id_result.get("value", "")),
			"",
			String(matter_id_result.get("reason", "")),
		)
	var response_id := String(response_id_result.get("value", ""))
	var matter_id := String(matter_id_result.get("value", ""))
	var response_key := _response_key(normalized_resident, response_id)
	if _receipt_by_response_key.has(response_key):
		var existing_receipt := (
			_receipt_by_response_key.get(response_key, {}) as Dictionary
		).duplicate(true)
		return _success({
			"duplicate": true,
			"status": existing_receipt.get("status"),
			"receipt": existing_receipt,
		})
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _rejected_submit(
			normalized_resident,
			response_id,
			matter_id,
			"社会事项不存在",
		)
	if submitted_at < 0:
		return _rejected_submit(
			normalized_resident,
			response_id,
			matter_id,
			"submitted_at 无效",
		)
	if String(matter.get("state", "")) in ["assigned", "executing"]:
		return _submit_assignment_response(
			matter,
			normalized_resident,
			response_id,
			response,
			submitted_at,
		)
	if (
		String(matter.get("state", "")) != "collecting"
		or typeof(response.get("matter_revision")) != TYPE_INT
		or int(response.get("matter_revision", -1))
		!= int(matter.get("revision", -2))
		or typeof(response.get("response_round_id")) != TYPE_STRING
		or String(response.get("response_round_id", ""))
		!= String(matter.get("response_round_id", ""))
	):
		return _stale_submit(
			normalized_resident,
			response_id,
			matter_id,
			"事项修订或回应轮次已经失效",
		)
	var candidate_index := _candidate_index(
		matter.get("fixed_candidates", []) as Array,
		normalized_resident,
	)
	if candidate_index < 0:
		return _rejected_submit(
			normalized_resident,
			response_id,
			matter_id,
			"居民不属于本轮固定候选",
		)
	var candidates := matter.get("fixed_candidates", []) as Array
	var candidate := candidates[candidate_index] as Dictionary
	if bool(candidate.get("terminal", false)):
		return _rejected_submit(
			normalized_resident,
			response_id,
			matter_id,
			"该候选本轮已经终止",
		)
	var option_id_result := _required_text(response, "option_id")
	if not bool(option_id_result.get("ok", false)):
		return _rejected_submit(
			normalized_resident,
			response_id,
			matter_id,
			String(option_id_result.get("reason", "")),
		)
	var option := _find_option(
		candidate.get("options", []) as Array,
		String(option_id_result.get("value", "")),
	)
	if option.is_empty():
		return _rejected_submit(
			normalized_resident,
			response_id,
			matter_id,
			"option_id 不属于本轮候选选项",
		)
	var public_text_value: Variant = response.get("public_text", "")
	if typeof(public_text_value) != TYPE_STRING:
		return _rejected_submit(
			normalized_resident,
			response_id,
			matter_id,
			"public_text 必须是字符串",
		)
	var public_text := String(public_text_value).strip_edges()
	if (
		public_text.length() > PUBLIC_RESPONSE_TEXT_MAX_LENGTH
		or public_text.contains("\n")
		or public_text.contains("\r")
		or public_text.contains("\t")
	):
		return _rejected_submit(
			normalized_resident,
			response_id,
			matter_id,
			"public_text 必须是最多 %d 字的单行文字"
			% PUBLIC_RESPONSE_TEXT_MAX_LENGTH,
		)
	if (
		not bool(option.get("allows_public_text", false))
		and not public_text.is_empty()
	):
		return _rejected_submit(
			normalized_resident,
			response_id,
			matter_id,
			"当前选项不允许公开文字",
		)
	var normalized_response := {
		"response_id": response_id,
		"resident_id": normalized_resident,
		"matter_id": matter_id,
		"matter_revision": int(matter.get("revision", 0)),
		"response_round_id": String(matter.get("response_round_id", "")),
		"option_id": String(option.get("option_id", "")),
		"response_kind": String(option.get("response_kind", "")),
		"public_text": public_text,
		"submitted_at": submitted_at,
		"role": String(option.get("role", "")),
		"action_goal": (
			option.get("action_goal", {}) as Dictionary
		).duplicate(true),
	}
	candidate["terminal"] = true
	candidate["terminal_reason"] = "responded"
	candidate["response"] = normalized_response
	(matter.get("candidate_results", {}) as Dictionary)[
		normalized_resident
	] = normalized_response.duplicate(true)
	if String(normalized_response.get("response_kind", "")) != "accept":
		var receipt := _queue_receipt(
			normalized_resident,
			response_id,
			matter_id,
			"recorded",
			"个人回应已经记录",
		)
		return _success({
			"duplicate": false,
			"status": "recorded",
			"receipt": receipt,
		})
	return _success({
		"duplicate": false,
		"status": "pending",
		"receipt": {},
	})


func _submit_assignment_response(
	matter: Dictionary,
	resident_id: String,
	response_id: String,
	response: Dictionary,
	submitted_at: int,
) -> Dictionary:
	var matter_id := String(matter.get("matter_id", ""))
	var participant := (
		(matter.get("participants", {}) as Dictionary).get(
			resident_id,
			{},
		) as Dictionary
	)
	if (
		participant.is_empty()
		or String(participant.get("status", "")) not in [
			"assigned",
			"executing",
		]
	):
		return _rejected_submit(
			resident_id,
			response_id,
			matter_id,
			"居民不是当前事项的活跃参与者",
		)
	var action_goal := participant.get("action_goal", {}) as Dictionary
	var expected_round_id := "assignment:%s" % String(
		action_goal.get("goal_id", "")
	)
	if (
		typeof(response.get("matter_revision")) != TYPE_INT
		or int(response.get("matter_revision", -1))
		!= int(matter.get("revision", -2))
		or typeof(response.get("response_round_id")) != TYPE_STRING
		or String(response.get("response_round_id", ""))
		!= expected_round_id
	):
		return _stale_submit(
			resident_id,
			response_id,
			matter_id,
			"承诺修订已经失效",
		)
	var option_id_result := _required_text(response, "option_id")
	if not bool(option_id_result.get("ok", false)):
		return _rejected_submit(
			resident_id,
			response_id,
			matter_id,
			String(option_id_result.get("reason", "")),
		)
	var option_id := String(option_id_result.get("value", ""))
	if option_id not in [
		"defer_assignment",
		"withdraw_assignment",
	]:
		return _rejected_submit(
			resident_id,
			response_id,
			matter_id,
			"承诺回应选项无效",
		)
	var public_text_value: Variant = response.get("public_text", "")
	if typeof(public_text_value) != TYPE_STRING:
		return _rejected_submit(
			resident_id,
			response_id,
			matter_id,
			"public_text 必须是字符串",
		)
	var public_text := String(public_text_value).strip_edges()
	if (
		public_text.length() > PUBLIC_RESPONSE_TEXT_MAX_LENGTH
		or public_text.contains("\n")
		or public_text.contains("\r")
		or public_text.contains("\t")
	):
		return _rejected_submit(
			resident_id,
			response_id,
			matter_id,
			"public_text 必须是最多 %d 字的单行文字"
			% PUBLIC_RESPONSE_TEXT_MAX_LENGTH,
		)
	var outcome := "deferred"
	var reason := "本轮暂不履行，承诺仍然有效"
	participant["last_assignment_response"] = {
		"response_id": response_id,
		"option_id": option_id,
		"public_text": public_text,
		"submitted_at": submitted_at,
	}
	if option_id == "defer_assignment":
		participant["deferred_until"] = mini(
			submitted_at + 30,
			int(matter.get("expires_at", submitted_at + 31)) - 1,
		)
		_increment_revision(matter)
	else:
		outcome = "withdrawn"
		reason = "居民已经退出本次承诺"
		var released := release_participant(
			matter_id,
			resident_id,
			(
				public_text
				if not public_text.is_empty()
				else "居民改变主意，退出承诺"
			),
			submitted_at,
		)
		if not bool(released.get("ok", false)):
			return released
	var receipt := _queue_receipt(
		resident_id,
		response_id,
		matter_id,
		"recorded",
		reason,
	)
	return _success({
		"duplicate": false,
		"status": "recorded",
		"assignment_outcome": outcome,
		"action_goal": action_goal.duplicate(true),
		"receipt": receipt,
	})


func mark_candidate_terminal(
	matter_id: String,
	resident_id: String,
	reason: String,
	expected_response_round_id: String = "",
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) != "collecting":
		return _failure(
			"SOCIAL_RESPONSE_STATE_INVALID",
			"当前没有收集中的回应轮次",
		)
	if (
		not expected_response_round_id.is_empty()
		and String(matter.get("response_round_id", ""))
		!= expected_response_round_id
	):
		return _failure(
			"SOCIAL_RESPONSE_ROUND_STALE",
			"社会回应轮次已经变化",
		)
	if reason not in TERMINAL_CANDIDATE_REASONS:
		return _failure(
			"SOCIAL_RESPONSE_TERMINAL_REASON_INVALID",
			"候选终止原因无效",
		)
	var candidates := matter.get("fixed_candidates", []) as Array
	var index := _candidate_index(candidates, resident_id.strip_edges())
	if index < 0:
		return _failure(
			"SOCIAL_RESPONSE_CANDIDATE_INVALID",
			"居民不属于本轮固定候选",
		)
	var candidate := candidates[index] as Dictionary
	if bool(candidate.get("terminal", false)):
		return _success(candidate.duplicate(true))
	candidate["terminal"] = true
	candidate["terminal_reason"] = reason
	candidate["response"] = {}
	(matter.get("candidate_results", {}) as Dictionary)[
		resident_id.strip_edges()
	] = {
		"terminal_reason": reason,
	}
	return _success(candidate.duplicate(true))


func is_response_round_ready(matter_id: String) -> bool:
	var matter := _matter(matter_id)
	if matter.is_empty() or String(matter.get("state", "")) != "collecting":
		return false
	for candidate_value: Variant in matter.get("fixed_candidates", []) as Array:
		if not bool((candidate_value as Dictionary).get("terminal", false)):
			return false
	return true


func timeout_due_response_rounds(now: int) -> Array[String]:
	var ready_matter_ids: Array[String] = []
	if now < 0:
		return ready_matter_ids
	for matter_value: Variant in _matters_by_id.values():
		var matter := matter_value as Dictionary
		if (
			String(matter.get("state", "")) != "collecting"
			or int(matter.get("response_window_until", -1)) > now
		):
			continue
		var matter_id := String(matter.get("matter_id", ""))
		for resident_id: String in pending_candidate_ids(matter_id):
			mark_candidate_terminal(
				matter_id,
				resident_id,
				"provider_timeout",
			)
		if is_response_round_ready(matter_id):
			ready_matter_ids.append(matter_id)
	ready_matter_ids.sort()
	return ready_matter_ids


func _exposure_is_actionable(exposure: Dictionary, now: int) -> bool:
	if int(exposure.get("expires_at", -1)) <= now:
		return false
	var status := String(exposure.get("status", ""))
	return (
		status == "pending"
		or (
			status == "deferred"
			and int(exposure.get("reconsider_at", -1)) <= now
		)
	)


func settle_response_round(
	matter_id: String,
	settled_at: int,
	no_response_outcome: String = "reopen",
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) != "collecting":
		return _failure(
			"SOCIAL_RESPONSE_STATE_INVALID",
			"当前没有收集中的回应轮次",
		)
	if not is_response_round_ready(matter_id):
		return _failure(
			"SOCIAL_RESPONSE_ROUND_PENDING",
			"固定候选尚未全部返回、失败或超时",
		)
	if settled_at < 0 or no_response_outcome not in NO_RESPONSE_OUTCOMES:
		return _failure(
			"SOCIAL_RESPONSE_SETTLEMENT_INVALID",
			"回应结算参数无效",
		)
	var accepted: Array[Dictionary] = []
	for candidate_value: Variant in matter.get("fixed_candidates", []) as Array:
		var candidate := candidate_value as Dictionary
		var response := candidate.get("response", {}) as Dictionary
		if String(response.get("response_kind", "")) == "accept":
			accepted.append(candidate)
	accepted.sort_custom(_candidate_precedes)
	var capacity := int(matter.get("capacity", 1))
	var selected_ids: Array[String] = []
	for candidate: Dictionary in accepted:
		var response := candidate.get("response", {}) as Dictionary
		var resident_id := String(candidate.get("resident_id", ""))
		if (
			selected_ids.size() < capacity
			and _resident_active_commitment_count(
				resident_id,
				matter_id,
			) < MAX_ACTIVE_COMMITMENTS_PER_RESIDENT
		):
			selected_ids.append(resident_id)
			_assign_participant(matter, candidate, settled_at)
			_queue_receipt(
				resident_id,
				String(response.get("response_id", "")),
				matter_id,
				"selected",
				"本轮回应已经选中",
				String(
					(
						(
							matter.get("participants", {}) as Dictionary
						).get(resident_id, {}) as Dictionary
					).get("role", "")
				),
				String(
					(
						(
							(
								matter.get("participants", {}) as Dictionary
							).get(resident_id, {}) as Dictionary
						).get("action_goal", {}) as Dictionary
					).get("goal_id", "")
				),
			)
		else:
			_queue_receipt(
				resident_id,
				String(response.get("response_id", "")),
				matter_id,
				"not_selected",
				"回应合法，但本轮容量或个人承诺名额已满",
			)
	_archive_response_round(matter, settled_at)
	if not selected_ids.is_empty():
		matter["state"] = "assigned"
		_increment_revision(matter)
		return _success({
			"state": "assigned",
			"selected_resident_ids": selected_ids,
		})
	if no_response_outcome == "close":
		return close_matter(
			matter_id,
			"social.resolve.no_response",
			"no_response",
			[],
			settled_at,
		)
	matter["state"] = "open"
	_increment_revision(matter)
	return _success({
		"state": "open",
		"selected_resident_ids": [],
	})


func start_execution(
	matter_id: String,
	resident_id: String,
	goal_id: String,
	started_at: int,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) not in ["assigned", "executing"]:
		return _failure(
			"SOCIAL_EXECUTION_STATE_INVALID",
			"事项当前没有可以执行的正式承诺",
		)
	var participants := matter.get("participants", {}) as Dictionary
	var normalized_resident := resident_id.strip_edges()
	var participant := participants.get(normalized_resident, {}) as Dictionary
	var action_goal := participant.get("action_goal", {}) as Dictionary
	if (
		participant.is_empty()
		or String(action_goal.get("goal_id", "")) != goal_id.strip_edges()
		or started_at < 0
	):
		return _failure(
			"SOCIAL_ACTION_GOAL_MISMATCH",
			"行动目标与被选中的参与者不一致",
		)
	if String(participant.get("status", "")) == "executing":
		return _success(participant.duplicate(true))
	if String(participant.get("status", "")) != "assigned":
		return _failure(
			"SOCIAL_EXECUTION_STATE_INVALID",
			"参与者已经结束当前承诺",
		)
	participant["status"] = "executing"
	participant["started_at"] = started_at
	matter["state"] = "executing"
	_increment_revision(matter)
	return _success(participant.duplicate(true))


func record_action_result(
	matter_id: String,
	resident_id: String,
	goal_id: String,
	result_ref: Dictionary,
	status: String,
	finished_at: int,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if status not in ["completed", "failed", "interrupted"] or finished_at < 0:
		return _failure(
			"SOCIAL_ACTION_RESULT_INVALID",
			"行动结果无效",
		)
	var result_id_result := _required_text(result_ref, "result_id")
	if not bool(result_id_result.get("ok", false)):
		return _failure(
			"SOCIAL_ACTION_RESULT_INVALID",
			String(result_id_result.get("reason", "")),
		)
	var participants := matter.get("participants", {}) as Dictionary
	var normalized_resident := resident_id.strip_edges()
	var participant := participants.get(normalized_resident, {}) as Dictionary
	var action_goal := participant.get("action_goal", {}) as Dictionary
	if (
		participant.is_empty()
		or String(action_goal.get("goal_id", "")) != goal_id.strip_edges()
	):
		return _failure(
			"SOCIAL_ACTION_GOAL_MISMATCH",
			"行动结果不属于当前参与者目标",
		)
	var result_id := String(result_id_result.get("value", ""))
	for existing_value: Variant in participant.get("result_refs", []) as Array:
		if String((existing_value as Dictionary).get("result_id", "")) == result_id:
			return _success(participant.duplicate(true))
	var normalized_result := result_ref.duplicate(true)
	normalized_result["status"] = status
	normalized_result["finished_at"] = finished_at
	(participant.get("result_refs", []) as Array).append(normalized_result)
	_append_unique_result(matter, normalized_result)
	participant["status"] = status
	participant["finished_at"] = finished_at
	if not _matter_has_active_participant(matter):
		var has_completed := false
		for participant_value: Variant in (
			matter.get("participants", {}) as Dictionary
		).values():
			if String(
				(participant_value as Dictionary).get("status", "")
			) == "completed":
				has_completed = true
				break
		if not has_completed:
			matter["state"] = "open"
	_increment_revision(matter)
	return _success(participant.duplicate(true))


func release_participant(
	matter_id: String,
	resident_id: String,
	reason: String,
	released_at: int,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) not in ["assigned", "executing"]:
		return _failure(
			"SOCIAL_PARTICIPANT_STATE_INVALID",
			"当前事项没有可释放的参与者",
		)
	var participants := matter.get("participants", {}) as Dictionary
	var normalized_resident := resident_id.strip_edges()
	var participant := participants.get(normalized_resident, {}) as Dictionary
	if participant.is_empty() or reason.strip_edges().is_empty() or released_at < 0:
		return _failure(
			"SOCIAL_PARTICIPANT_INVALID",
			"参与者释放参数无效",
		)
	participant["status"] = "withdrawn"
	participant["released_at"] = released_at
	participant["release_reason"] = reason.strip_edges()
	record_involvement(
		matter_id,
		normalized_resident,
		"observer",
		released_at,
	)
	var has_active_participant := false
	has_active_participant = _matter_has_active_participant(matter)
	if not has_active_participant:
		matter["state"] = "open"
	_increment_revision(matter)
	return _success(matter.duplicate(true))


func update_source_state(
	matter_id: String,
	source_revision: int,
	active: bool,
	updated_at: int,
	result_refs: Array = [],
	source_patch: Dictionary = {},
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) == "closed":
		return _failure("SOCIAL_MATTER_CLOSED", "已关闭事项不能更新来源")
	var source_ref := matter.get("source_state_ref", {}) as Dictionary
	var current_revision := int(source_ref.get("source_revision", -1))
	if source_revision < current_revision or updated_at < 0:
		return _failure(
			"SOCIAL_SOURCE_STALE",
			"来源修订已经失效",
		)
	var patch_error := _apply_source_patch(
		matter,
		source_patch,
		updated_at,
	)
	if not patch_error.is_empty():
		return _failure(
			"SOCIAL_SOURCE_INVALID",
			patch_error,
		)
	source_ref["source_revision"] = source_revision
	if not active:
		return close_matter(
			matter_id,
			"social.resolve.source_cleared",
			"source_cleared",
			result_refs,
			updated_at,
		)
	if String(matter.get("state", "")) == "collecting":
		_invalidate_pending_responses(matter, "来源修订已经变化")
		_archive_response_round(matter, updated_at)
		matter["state"] = "open"
	_increment_revision(matter)
	return _success(matter.duplicate(true))


func _apply_source_patch(
	matter: Dictionary,
	source_patch: Dictionary,
	updated_at: int,
) -> String:
	for key_value: Variant in source_patch:
		if String(key_value) not in [
			"capacity",
			"expires_at",
			"place_id",
			"reason_summary",
			"source_event_ids",
		]:
			return "来源更新包含未知字段：%s" % str(key_value)
	if source_patch.has("capacity"):
		if (
			typeof(source_patch.get("capacity")) != TYPE_INT
			or int(source_patch.get("capacity", 0)) <= 0
		):
			return "来源更新 capacity 必须是正整数"
		matter["capacity"] = int(source_patch.get("capacity"))
	if source_patch.has("expires_at"):
		if (
			typeof(source_patch.get("expires_at")) != TYPE_INT
			or int(source_patch.get("expires_at", -1)) <= updated_at
		):
			return "来源更新 expires_at 必须晚于更新时间"
		matter["expires_at"] = int(source_patch.get("expires_at"))
	if source_patch.has("place_id"):
		if typeof(source_patch.get("place_id")) != TYPE_STRING:
			return "来源更新 place_id 必须是字符串"
		matter["place_id"] = String(
			source_patch.get("place_id")
		).strip_edges()
	if source_patch.has("reason_summary"):
		if typeof(source_patch.get("reason_summary")) != TYPE_STRING:
			return "来源更新 reason_summary 必须是字符串"
		var reason_summary := String(
			source_patch.get("reason_summary")
		).strip_edges()
		if (
			reason_summary.length() > 80
			or reason_summary.contains("\n")
			or reason_summary.contains("\r")
			or reason_summary.contains("\t")
		):
			return "来源更新 reason_summary 必须是最多80字的单行文字"
		matter["reason_summary"] = reason_summary
	if source_patch.has("source_event_ids"):
		if typeof(source_patch.get("source_event_ids")) != TYPE_ARRAY:
			return "来源更新 source_event_ids 必须是数组"
		var normalized_event_ids: Array[String] = []
		for event_value: Variant in (
			source_patch.get("source_event_ids", []) as Array
		):
			if (
				typeof(event_value) != TYPE_STRING
				or String(event_value).strip_edges().is_empty()
			):
				return "来源更新 source_event_ids 只能包含非空字符串"
			var event_id := String(event_value).strip_edges()
			if not normalized_event_ids.has(event_id):
				normalized_event_ids.append(event_id)
		normalized_event_ids.sort()
		matter["source_event_ids"] = normalized_event_ids
	return ""


func expire_due(now: int) -> Array[Dictionary]:
	var closed: Array[Dictionary] = []
	var matter_ids: Array[String] = []
	for id_value: Variant in _matters_by_id:
		matter_ids.append(String(id_value))
	matter_ids.sort()
	for matter_id: String in matter_ids:
		var matter := _matter(matter_id)
		if (
			String(matter.get("state", "")) != "closed"
			and int(matter.get("expires_at", -1)) <= now
		):
			var result := close_matter(
				matter_id,
				"social.resolve.expired",
				"expired",
				[],
				now,
			)
			if bool(result.get("ok", false)):
				closed.append(
					(result.get("value", {}) as Dictionary).duplicate(true)
				)
	return closed


func close_matter(
	matter_id: String,
	resolver_id: String,
	close_reason: String,
	result_refs: Array,
	closed_at: int,
) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return _failure("SOCIAL_MATTER_NOT_FOUND", "社会事项不存在")
	if String(matter.get("state", "")) == "closed":
		return _success(matter.duplicate(true))
	if (
		not _matter_allows_resolver(matter, resolver_id)
		or close_reason.strip_edges().is_empty()
		or closed_at < 0
	):
		return _failure(
			"SOCIAL_RESOLUTION_INVALID",
			"事项未登记该关闭规则或关闭参数无效",
		)
	for result_value: Variant in result_refs:
		if typeof(result_value) != TYPE_DICTIONARY:
			return _failure(
				"SOCIAL_RESOLUTION_INVALID",
				"result_refs 只能包含对象",
			)
	if String(matter.get("state", "")) == "collecting":
		_invalidate_pending_responses(matter, "事项已经关闭")
		_archive_response_round(matter, closed_at)
	for result_value: Variant in result_refs:
		_append_unique_result(matter, result_value as Dictionary)
	matter["state"] = "closed"
	matter["close_reason"] = close_reason.strip_edges()
	matter["closed_at"] = closed_at
	_increment_revision(matter)
	var source_key := _source_key(
		matter.get("source_state_ref", {}) as Dictionary,
		matter.get("subject_ids", []) as Array,
	)
	if String(_active_matter_id_by_source_key.get(source_key, "")) == matter_id:
		_active_matter_id_by_source_key.erase(source_key)
	var result := _success(matter.duplicate(true))
	_evict_stale_closed_matters()
	return result


func _evict_stale_closed_matters() -> void:
	# closed 事项如果永久驻留，list_matters(true) 和公共活动投影会随
	# 游玩时间线性变慢。只保留最近关闭的一批，完整历史由 world log 承担。
	var closed_ids: Array[String] = []
	for matter_id: String in _matters_by_id:
		var matter := _matters_by_id[matter_id] as Dictionary
		if String(matter.get("state", "")) == "closed":
			closed_ids.append(matter_id)
	if closed_ids.size() <= MAX_RETAINED_CLOSED_MATTERS:
		return
	closed_ids.sort_custom(
		func(left: String, right: String) -> bool:
			var left_matter := _matters_by_id[left] as Dictionary
			var right_matter := _matters_by_id[right] as Dictionary
			var left_closed := int(left_matter.get("closed_at", -1))
			var right_closed := int(right_matter.get("closed_at", -1))
			if left_closed != right_closed:
				return left_closed < right_closed
			return left < right
	)
	var evicted_ids := {}
	while closed_ids.size() > MAX_RETAINED_CLOSED_MATTERS:
		var evict_id: String = closed_ids.pop_front()
		evicted_ids[evict_id] = true
		_matters_by_id.erase(evict_id)
	for response_key: Variant in _receipt_by_response_key.keys():
		var receipt := _receipt_by_response_key[response_key] as Dictionary
		if evicted_ids.has(String(receipt.get("matter_id", ""))):
			_receipt_by_response_key.erase(response_key)


func create_save_snapshot() -> Dictionary:
	return {
		"schema": "town-social-matters",
		"schema_version": 1,
		"matters": list_matters(true),
		"receipts_by_resident": _receipts_by_resident.duplicate(true),
		"sequences": {
			"matter": _matter_sequence,
			"round": _round_sequence,
			"goal": _goal_sequence,
		},
	}


func restore_save_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation := _validate_save_snapshot(snapshot)
	if not bool(validation.get("ok", false)):
		return validation
	var value := validation.get("value", {}) as Dictionary
	var restored_matters := value.get("matters", {}) as Dictionary
	var restored_active_sources := (
		value.get("active_sources", {}) as Dictionary
	)
	var restored_receipts := (
		value.get("receipts_by_resident", {}) as Dictionary
	)
	var sequences := value.get("sequences", {}) as Dictionary
	_matters_by_id = restored_matters.duplicate(true)
	_active_matter_id_by_source_key = restored_active_sources.duplicate(true)
	_receipts_by_resident = restored_receipts.duplicate(true)
	_receipt_by_response_key.clear()
	for resident_value: Variant in _receipts_by_resident:
		var resident_id := String(resident_value)
		for receipt_value: Variant in (
			_receipts_by_resident.get(resident_id, []) as Array
		):
			var receipt := receipt_value as Dictionary
			_receipt_by_response_key[
				_response_key(
					resident_id,
					String(receipt.get("response_id", "")),
				)
			] = receipt.duplicate(true)
	_matter_sequence = int(sequences.get("matter", 0))
	_round_sequence = int(sequences.get("round", 0))
	_goal_sequence = int(sequences.get("goal", 0))
	return _success({
		"matter_count": _matters_by_id.size(),
		"pending_candidates": all_pending_candidate_refs(),
	})


func pending_candidate_ids(matter_id: String) -> Array[String]:
	var matter := _matter(matter_id)
	var result: Array[String] = []
	if matter.is_empty() or String(matter.get("state", "")) != "collecting":
		return result
	for candidate_value: Variant in matter.get("fixed_candidates", []) as Array:
		var candidate := candidate_value as Dictionary
		if not bool(candidate.get("terminal", false)):
			result.append(String(candidate.get("resident_id", "")))
	result.sort()
	return result


func all_pending_candidate_refs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for matter: Dictionary in list_matters(false):
		var matter_id := String(matter.get("matter_id", ""))
		var round_id := String(matter.get("response_round_id", ""))
		for resident_id: String in pending_candidate_ids(matter_id):
			result.append({
				"matter_id": matter_id,
				"matter_revision": int(matter.get("revision", 0)),
				"response_round_id": round_id,
				"resident_id": resident_id,
			})
	return result


func get_matter(matter_id: String) -> Dictionary:
	var matter := _matter(matter_id)
	return matter.duplicate(true)


func find_active_matter(
	source_kind: String,
	source_id: String,
	subject_ids: Array,
) -> Dictionary:
	var source_key := _source_key(
		{
			"source_kind": source_kind.strip_edges(),
			"source_id": source_id.strip_edges(),
		},
		subject_ids,
	)
	var matter_id := String(
		_active_matter_id_by_source_key.get(source_key, "")
	)
	return get_matter(matter_id)


func list_matters(include_closed: bool = false) -> Array[Dictionary]:
	var matter_ids: Array[String] = []
	for id_value: Variant in _matters_by_id:
		matter_ids.append(String(id_value))
	matter_ids.sort()
	var result: Array[Dictionary] = []
	for matter_id: String in matter_ids:
		var matter := _matter(matter_id)
		if include_closed or String(matter.get("state", "")) != "closed":
			result.append(matter.duplicate(true))
	return result


func public_summary(matter_id: String) -> Dictionary:
	var matter := _matter(matter_id)
	if matter.is_empty():
		return {}
	var participants := matter.get("participants", {}) as Dictionary
	var active_participants := 0
	for participant_value: Variant in participants.values():
		if String((participant_value as Dictionary).get("status", "")) in [
			"assigned",
			"executing",
			"completed",
		]:
			active_participants += 1
	return {
		"matter_id": String(matter.get("matter_id", "")),
		"kind": String(matter.get("kind", "")),
		"place_id": String(matter.get("place_id", "")),
		"state": String(matter.get("state", "")),
		"revision": int(matter.get("revision", 0)),
		"expires_at": int(matter.get("expires_at", -1)),
		"capacity": int(matter.get("capacity", 0)),
		"participant_count": active_participants,
		"attention_level": String(matter.get("attention_level", "")),
		"close_reason": String(matter.get("close_reason", "")),
	}


func drain_receipts(resident_id: String) -> Array[Dictionary]:
	var normalized := resident_id.strip_edges()
	var stored := _receipts_by_resident.get(normalized, []) as Array
	var result: Array[Dictionary] = []
	for value: Variant in stored:
		result.append((value as Dictionary).duplicate(true))
	_receipts_by_resident[normalized] = []
	return result


func peek_receipts(resident_id: String) -> Array[Dictionary]:
	var stored := _receipts_by_resident.get(
		resident_id.strip_edges(),
		[],
	) as Array
	var result: Array[Dictionary] = []
	for value: Variant in stored:
		result.append((value as Dictionary).duplicate(true))
	return result


func _validate_matter_spec(spec: Dictionary) -> Dictionary:
	var source_result := _registry.validate_source_ref(spec.get("source_state_ref"),) as Dictionary
	if not bool(source_result.get("ok", false)):
		return source_result
	var rules_result := _registry.validate_resolution_rules(spec.get("resolution_rules", []),) as Dictionary
	if not bool(rules_result.get("ok", false)):
		return rules_result
	var kind_result := _required_text(spec, "kind")
	if not bool(kind_result.get("ok", false)):
		return kind_result
	var subject_result := _string_array(spec.get("subject_ids", []), false)
	if not bool(subject_result.get("ok", false)):
		return subject_result
	var event_result := _string_array(spec.get("source_event_ids", []), true)
	if not bool(event_result.get("ok", false)):
		return event_result
	for text_field in [
		"matter_id",
		"parent_matter_id",
		"creator_id",
		"place_id",
		"reason_summary",
	]:
		if spec.has(text_field) and typeof(spec.get(text_field)) != TYPE_STRING:
			return _failure(
				"SOCIAL_MATTER_SPEC_INVALID",
				"%s 必须是字符串" % text_field,
			)
	for int_field in ["created_at", "expires_at", "capacity"]:
		if typeof(spec.get(int_field)) != TYPE_INT:
			return _failure(
				"SOCIAL_MATTER_SPEC_INVALID",
				"%s 必须是整数" % int_field,
			)
	var created_at := int(spec.get("created_at", -1))
	var expires_at := int(spec.get("expires_at", -1))
	var capacity := int(spec.get("capacity", 0))
	var reason_summary := String(
		spec.get("reason_summary", "")
	).strip_edges()
	if (
		reason_summary.length() > 80
		or reason_summary.contains("\n")
		or reason_summary.contains("\r")
		or reason_summary.contains("\t")
	):
		return _failure(
			"SOCIAL_MATTER_SPEC_INVALID",
			"reason_summary 必须是最多80字的单行文字",
		)
	if created_at < 0 or expires_at <= created_at or capacity <= 0:
		return _failure(
			"SOCIAL_MATTER_SPEC_INVALID",
			"事项时间或容量无效",
		)
	var initial_state_value: Variant = spec.get("initial_state", "latent")
	var attention_value: Variant = spec.get("attention_level", "daily")
	if (
		typeof(initial_state_value) != TYPE_STRING
		or String(initial_state_value) not in ["latent", "open"]
		or typeof(attention_value) != TYPE_STRING
		or String(attention_value) not in ["daily", "social", "major"]
	):
		return _failure(
			"SOCIAL_MATTER_SPEC_INVALID",
			"事项初始状态或注意力等级无效",
		)
	return _success({
		"matter_id": String(spec.get("matter_id", "")).strip_edges(),
		"kind": String(kind_result.get("value", "")),
		"source_event_ids": event_result.get("value", []),
		"source_state_ref": source_result.get("value", {}),
		"parent_matter_id": String(
			spec.get("parent_matter_id", "")
		).strip_edges(),
		"creator_id": String(spec.get("creator_id", "")).strip_edges(),
		"subject_ids": subject_result.get("value", []),
		"resolution_rules": rules_result.get("value", []),
		"place_id": String(spec.get("place_id", "")).strip_edges(),
		"reason_summary": reason_summary,
		"created_at": created_at,
		"expires_at": expires_at,
		"capacity": capacity,
		"initial_state": String(initial_state_value),
		"attention_level": String(attention_value),
	})


func _validate_save_snapshot(snapshot: Dictionary) -> Dictionary:
	if (
		snapshot.get("schema") != "town-social-matters"
		or snapshot.get("schema_version") != 1
		or typeof(snapshot.get("matters")) != TYPE_ARRAY
		or typeof(snapshot.get("receipts_by_resident")) != TYPE_DICTIONARY
		or typeof(snapshot.get("sequences")) != TYPE_DICTIONARY
	):
		return _failure(
			"SOCIAL_SAVE_INVALID",
			"社会事项存档外壳无效",
		)
	var sequences := snapshot.get("sequences", {}) as Dictionary
	for field in ["matter", "round", "goal"]:
		if (
			typeof(sequences.get(field)) != TYPE_INT
			or int(sequences.get(field, -1)) < 0
		):
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"社会事项存档序列无效",
			)
	var restored_matters := {}
	var active_sources := {}
	for matter_value: Variant in snapshot.get("matters", []) as Array:
		var matter_result := _validate_saved_matter(matter_value)
		if not bool(matter_result.get("ok", false)):
			return matter_result
		var matter := (
			matter_result.get("value", {}) as Dictionary
		).duplicate(true)
		var matter_id := String(matter.get("matter_id", ""))
		if restored_matters.has(matter_id):
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"社会事项存档包含重复 matter_id",
			)
		restored_matters[matter_id] = matter
		if String(matter.get("state", "")) != "closed":
			var source_key := _source_key(
				matter.get("source_state_ref", {}) as Dictionary,
				matter.get("subject_ids", []) as Array,
			)
			if active_sources.has(source_key):
				return _failure(
					"SOCIAL_SAVE_INVALID",
					"同一持续来源存在多个活跃事项",
				)
			active_sources[source_key] = matter_id
	var receipts_result := _validate_saved_receipts(
		snapshot.get("receipts_by_resident", {}) as Dictionary
	)
	if not bool(receipts_result.get("ok", false)):
		return receipts_result
	return _success({
		"matters": restored_matters,
		"active_sources": active_sources,
		"receipts_by_resident": receipts_result.get("value", {}),
		"sequences": sequences.duplicate(true),
	})


func _validate_saved_matter(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _failure(
			"SOCIAL_SAVE_INVALID",
			"保存的社会事项必须是对象",
		)
	var matter := raw_value as Dictionary
	for text_field in [
		"matter_id",
		"kind",
		"state",
		"close_reason",
		"attention_level",
	]:
		if typeof(matter.get(text_field)) != TYPE_STRING:
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"保存事项 %s 字段无效" % text_field,
			)
	if (
		matter.has("reason_summary")
		and typeof(matter.get("reason_summary")) != TYPE_STRING
	):
		return _failure(
			"SOCIAL_SAVE_INVALID",
			"保存事项 reason_summary 字段无效",
		)
	if not matter.has("reason_summary"):
		matter["reason_summary"] = ""
	if not matter.has("involvement"):
		matter["involvement"] = {}
	if not matter.has("exposures"):
		matter["exposures"] = {}
	var reason_summary := String(
		matter.get("reason_summary", "")
	).strip_edges()
	if (
		reason_summary.length() > 80
		or reason_summary.contains("\n")
		or reason_summary.contains("\r")
		or reason_summary.contains("\t")
	):
		return _failure(
			"SOCIAL_SAVE_INVALID",
			"保存事项 reason_summary 必须是最多80字的单行文字",
		)
	matter["reason_summary"] = reason_summary
	if (
		String(matter.get("matter_id", "")).strip_edges().is_empty()
		or String(matter.get("state", "")) not in STATES
		or typeof(matter.get("revision")) != TYPE_INT
		or int(matter.get("revision", 0)) <= 0
		or typeof(matter.get("capacity")) != TYPE_INT
		or int(matter.get("capacity", 0)) <= 0
	):
		return _failure(
			"SOCIAL_SAVE_INVALID",
			"保存事项身份、状态、修订或容量无效",
		)
	var source_result := _registry.validate_source_ref(matter.get("source_state_ref"),) as Dictionary
	if not bool(source_result.get("ok", false)):
		return _failure(
			"SOCIAL_SAVE_INVALID",
			String(source_result.get("reason", "")),
		)
	var rules_result := _registry.validate_resolution_rules(matter.get("resolution_rules"),) as Dictionary
	if not bool(rules_result.get("ok", false)):
		return _failure(
			"SOCIAL_SAVE_INVALID",
			String(rules_result.get("reason", "")),
		)
	for array_field in [
		"source_event_ids",
		"subject_ids",
		"channels",
		"fixed_candidates",
		"response_history",
		"result_refs",
	]:
		if typeof(matter.get(array_field)) != TYPE_ARRAY:
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"保存事项 %s 必须是数组" % array_field,
			)
	for dictionary_field in [
		"participants",
		"awareness",
		"involvement",
		"exposures",
		"candidate_results",
		"source_action_goal",
	]:
		if typeof(matter.get(dictionary_field)) != TYPE_DICTIONARY:
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"保存事项 %s 必须是对象" % dictionary_field,
			)
	for exposure_value: Variant in (
		matter.get("exposures", {}) as Dictionary
	).values():
		if not exposure_value is Dictionary:
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"保存事项 exposure 必须是对象",
			)
		var exposure := exposure_value as Dictionary
		if (
			typeof(exposure.get("exposure_id")) != TYPE_STRING
			or String(exposure.get("exposure_id", "")).is_empty()
			or typeof(exposure.get("resident_id")) != TYPE_STRING
			or String(exposure.get("resident_id", "")).is_empty()
			or typeof(exposure.get("channel")) != TYPE_STRING
			or String(exposure.get("channel", ""))
			not in EXPOSURE_CHANNELS
			or typeof(exposure.get("clue")) != TYPE_STRING
			or String(exposure.get("clue", "")).is_empty()
			or typeof(exposure.get("source_id")) != TYPE_STRING
			or String(exposure.get("source_id", "")).is_empty()
			or typeof(exposure.get("status")) != TYPE_STRING
			or String(exposure.get("status", ""))
			not in EXPOSURE_STATUSES
		):
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"保存事项 exposure 文本字段无效",
			)
		for exposure_int_field in [
			"matter_revision",
			"created_at",
			"expires_at",
			"reconsider_at",
			"handled_at",
		]:
			if typeof(exposure.get(exposure_int_field)) != TYPE_INT:
				return _failure(
					"SOCIAL_SAVE_INVALID",
					"保存事项 exposure.%s 必须是整数"
					% exposure_int_field,
				)
	for int_field in [
		"created_at",
		"expires_at",
		"closed_at",
		"response_window_until",
		"channel_revision",
	]:
		if typeof(matter.get(int_field)) != TYPE_INT:
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"保存事项 %s 必须是整数" % int_field,
			)
	if String(matter.get("state", "")) == "collecting":
		if (
			typeof(matter.get("response_round_id")) != TYPE_STRING
			or String(matter.get("response_round_id", "")).is_empty()
			or (matter.get("fixed_candidates", []) as Array).is_empty()
		):
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"收集中的事项缺少回应轮次或固定候选",
			)
		for candidate_value: Variant in (
			matter.get("fixed_candidates", []) as Array
		):
			if typeof(candidate_value) != TYPE_DICTIONARY:
				return _failure(
					"SOCIAL_SAVE_INVALID",
					"固定候选必须是对象",
				)
			var candidate := candidate_value as Dictionary
			if (
				typeof(candidate.get("terminal")) != TYPE_BOOL
				or typeof(candidate.get("response")) != TYPE_DICTIONARY
				or typeof(candidate.get("options")) != TYPE_ARRAY
			):
				return _failure(
					"SOCIAL_SAVE_INVALID",
					"固定候选保存字段无效",
				)
	else:
		if typeof(matter.get("response_round_id")) != TYPE_STRING:
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"response_round_id 必须是字符串",
			)
	return _success(matter.duplicate(true))


func _validate_saved_receipts(receipts: Dictionary) -> Dictionary:
	var normalized := {}
	for resident_value: Variant in receipts:
		if typeof(resident_value) != TYPE_STRING:
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"社会回执居民编号无效",
			)
		var resident_id := String(resident_value).strip_edges()
		var values: Variant = receipts.get(resident_value)
		if resident_id.is_empty() or typeof(values) != TYPE_ARRAY:
			return _failure(
				"SOCIAL_SAVE_INVALID",
				"社会回执列表无效",
			)
		var stored: Array[Dictionary] = []
		for receipt_value: Variant in values as Array:
			if typeof(receipt_value) != TYPE_DICTIONARY:
				return _failure(
					"SOCIAL_SAVE_INVALID",
					"社会回执必须是对象",
				)
			var receipt := receipt_value as Dictionary
			if (
				typeof(receipt.get("response_id")) != TYPE_STRING
				or String(receipt.get("response_id", "")).is_empty()
				or typeof(receipt.get("matter_id")) != TYPE_STRING
				or typeof(receipt.get("status")) != TYPE_STRING
				or String(receipt.get("status", "")) not in [
					"recorded",
					"selected",
					"not_selected",
					"stale",
					"rejected",
				]
			):
				return _failure(
					"SOCIAL_SAVE_INVALID",
					"社会回执字段无效",
				)
			stored.append(receipt.duplicate(true))
		normalized[resident_id] = stored
	return _success(normalized)


func _validate_channel(channel: Dictionary) -> Dictionary:
	var channel_result := _required_text(channel, "channel_kind")
	var source_result := _required_text(channel, "source_id")
	if not bool(channel_result.get("ok", false)):
		return channel_result
	if not bool(source_result.get("ok", false)):
		return source_result
	var channel_kind := String(channel_result.get("value", ""))
	if channel_kind not in CHANNEL_KINDS:
		return _failure(
			"SOCIAL_CHANNEL_INVALID",
			"未登记的事项渠道",
		)
	if typeof(channel.get("active", true)) != TYPE_BOOL:
		return _failure("SOCIAL_CHANNEL_INVALID", "channel active 必须是布尔值")
	if typeof(channel.get("updated_at")) != TYPE_INT:
		return _failure("SOCIAL_CHANNEL_INVALID", "channel updated_at 必须是整数")
	return _success({
		"channel_kind": channel_kind,
		"source_id": String(source_result.get("value", "")),
		"active": bool(channel.get("active", true)),
		"updated_at": int(channel.get("updated_at", 0)),
	})


func _validate_candidate(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _failure(
			"SOCIAL_RESPONSE_CANDIDATE_INVALID",
			"回应候选必须是对象",
		)
	var candidate := raw_value as Dictionary
	var resident_result := _required_text(candidate, "resident_id")
	if not bool(resident_result.get("ok", false)):
		return resident_result
	for int_field in ["ability_score", "load", "available_at"]:
		if typeof(candidate.get(int_field)) != TYPE_INT:
			return _failure(
				"SOCIAL_RESPONSE_CANDIDATE_INVALID",
				"候选 %s 必须是整数" % int_field,
			)
	if int(candidate.get("load", -1)) < 0 or int(candidate.get("available_at", -1)) < 0:
		return _failure(
			"SOCIAL_RESPONSE_CANDIDATE_INVALID",
			"候选负荷或可用时间无效",
		)
	if typeof(candidate.get("options")) != TYPE_ARRAY:
		return _failure(
			"SOCIAL_RESPONSE_CANDIDATE_INVALID",
			"候选 options 必须是数组",
		)
	var options: Array[Dictionary] = []
	var seen_options := {}
	for option_value: Variant in candidate.get("options", []) as Array:
		var option_result := _validate_option(option_value)
		if not bool(option_result.get("ok", false)):
			return option_result
		var option := (
			option_result.get("value", {}) as Dictionary
		).duplicate(true)
		var option_id := String(option.get("option_id", ""))
		if seen_options.has(option_id):
			return _failure(
				"SOCIAL_RESPONSE_OPTION_DUPLICATE",
				"候选 option_id 不能重复",
			)
		seen_options[option_id] = true
		options.append(option)
	if options.is_empty():
		return _failure(
			"SOCIAL_RESPONSE_CANDIDATE_INVALID",
			"候选至少需要一个回应选项",
		)
	options.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("option_id", "")) < String(
				right.get("option_id", "")
			)
	)
	return _success({
		"resident_id": String(resident_result.get("value", "")),
		"ability_score": int(candidate.get("ability_score", 0)),
		"load": int(candidate.get("load", 0)),
		"available_at": int(candidate.get("available_at", 0)),
		"options": options,
	})


func _validate_option(raw_value: Variant) -> Dictionary:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _failure(
			"SOCIAL_RESPONSE_OPTION_INVALID",
			"回应选项必须是对象",
		)
	var option := raw_value as Dictionary
	var option_result := _required_text(option, "option_id")
	var kind_result := _required_text(option, "response_kind")
	if not bool(option_result.get("ok", false)):
		return option_result
	if not bool(kind_result.get("ok", false)):
		return kind_result
	var response_kind := String(kind_result.get("value", ""))
	if response_kind not in RESPONSE_KINDS:
		return _failure(
			"SOCIAL_RESPONSE_OPTION_INVALID",
			"response_kind 未登记",
		)
	if typeof(option.get("allows_public_text", false)) != TYPE_BOOL:
		return _failure(
			"SOCIAL_RESPONSE_OPTION_INVALID",
			"allows_public_text 必须是布尔值",
		)
	var normalized := {
		"option_id": String(option_result.get("value", "")),
		"response_kind": response_kind,
		"allows_public_text": bool(option.get("allows_public_text", false)),
		"meaning": String(option.get("meaning", "")).strip_edges(),
		"role": "",
		"action_goal": {},
	}
	if (
		normalized["meaning"].length() > 80
		or normalized["meaning"].contains("\n")
		or normalized["meaning"].contains("\r")
	):
		return _failure(
			"SOCIAL_RESPONSE_OPTION_INVALID",
			"回应选项 meaning 必须是最多80字的单行文字",
		)
	if response_kind == "accept":
		var goal_result := _registry.validate_action_goal(option.get("action_goal"),) as Dictionary
		if not bool(goal_result.get("ok", false)):
			return goal_result
		var action_goal := (
			goal_result.get("value", {}) as Dictionary
		).duplicate(true)
		normalized["role"] = String(action_goal.get("role", ""))
		normalized["action_goal"] = action_goal
	return _success(normalized)


func _assign_participant(
	matter: Dictionary,
	candidate: Dictionary,
	selected_at: int,
) -> void:
	var response := candidate.get("response", {}) as Dictionary
	var resident_id := String(candidate.get("resident_id", ""))
	var action_goal := (
		response.get("action_goal", {}) as Dictionary
	).duplicate(true)
	if String(action_goal.get("goal_id", "")).is_empty():
		_goal_sequence += 1
		action_goal["goal_id"] = "goal-%06d" % _goal_sequence
	(matter.get("participants", {}) as Dictionary)[resident_id] = {
		"resident_id": resident_id,
		"role": String(response.get("role", "")),
		"response_status": "selected",
		"response_id": String(response.get("response_id", "")),
		"action_goal": action_goal,
		"status": "assigned",
		"selected_at": selected_at,
		"started_at": -1,
		"finished_at": -1,
		"result_refs": [],
	}
	record_involvement(
		String(matter.get("matter_id", "")),
		resident_id,
		"participant",
		selected_at,
	)


func _matter_has_active_participant(matter: Dictionary) -> bool:
	for value: Variant in (
		matter.get("participants", {}) as Dictionary
	).values():
		if String((value as Dictionary).get("status", "")) in [
			"assigned",
			"executing",
		]:
			return true
	return false


func _archive_response_round(matter: Dictionary, settled_at: int) -> void:
	var round_id := String(matter.get("response_round_id", ""))
	if round_id.is_empty():
		return
	(matter.get("response_history", []) as Array).append({
		"response_round_id": round_id,
		"matter_revision": int(matter.get("revision", 0)),
		"response_window_until": int(
			matter.get("response_window_until", -1)
		),
		"fixed_candidates": (
			matter.get("fixed_candidates", []) as Array
		).duplicate(true),
		"candidate_results": (
			matter.get("candidate_results", {}) as Dictionary
		).duplicate(true),
		"settled_at": settled_at,
	})
	matter["response_round_id"] = ""
	matter["response_window_until"] = -1
	matter["fixed_candidates"] = []
	matter["candidate_results"] = {}


func _invalidate_pending_responses(
	matter: Dictionary,
	reason: String,
) -> void:
	for candidate_value: Variant in matter.get("fixed_candidates", []) as Array:
		var candidate := candidate_value as Dictionary
		var response := candidate.get("response", {}) as Dictionary
		if String(response.get("response_kind", "")) != "accept":
			continue
		var response_id := String(response.get("response_id", ""))
		var resident_id := String(candidate.get("resident_id", ""))
		if (
			not response_id.is_empty()
			and not _receipt_by_response_key.has(
				_response_key(resident_id, response_id)
			)
		):
			_queue_receipt(
				resident_id,
				response_id,
				String(matter.get("matter_id", "")),
				"stale",
				reason,
			)


func _queue_receipt(
	resident_id: String,
	response_id: String,
	matter_id: String,
	status: String,
	reason: String,
	role: String = "",
	action_goal_id: String = "",
) -> Dictionary:
	var receipt := {
		"response_id": response_id,
		"matter_id": matter_id,
		"status": status,
		"role": role,
		"action_goal_id": action_goal_id,
		"reason": reason,
	}
	var response_key := _response_key(resident_id, response_id)
	if _receipt_by_response_key.has(response_key):
		return (
			_receipt_by_response_key.get(response_key, {}) as Dictionary
		).duplicate(true)
	_receipt_by_response_key[response_key] = receipt.duplicate(true)
	var resident_receipts := (
		_receipts_by_resident.get(resident_id, []) as Array
	)
	resident_receipts.append(receipt.duplicate(true))
	_receipts_by_resident[resident_id] = resident_receipts
	return receipt


func _rejected_submit(
	resident_id: String,
	response_id: String,
	matter_id: String,
	reason: String,
) -> Dictionary:
	if resident_id.is_empty() or response_id.is_empty():
		return _failure("SOCIAL_RESPONSE_REJECTED", reason)
	var receipt := _queue_receipt(
		resident_id,
		response_id,
		matter_id,
		"rejected",
		reason,
	)
	return _success({
		"duplicate": false,
		"status": "rejected",
		"receipt": receipt,
	})


func _stale_submit(
	resident_id: String,
	response_id: String,
	matter_id: String,
	reason: String,
) -> Dictionary:
	if resident_id.is_empty() or response_id.is_empty():
		return _failure("SOCIAL_RESPONSE_STALE", reason)
	var receipt := _queue_receipt(
		resident_id,
		response_id,
		matter_id,
		"stale",
		reason,
	)
	return _success({
		"duplicate": false,
		"status": "stale",
		"receipt": receipt,
	})


func _resident_active_commitment_count(
	resident_id: String,
	excluded_matter_id: String,
) -> int:
	var count := 0
	for matter_value: Variant in _matters_by_id.values():
		var matter := matter_value as Dictionary
		if String(matter.get("matter_id", "")) == excluded_matter_id:
			continue
		var participant := (
			(matter.get("participants", {}) as Dictionary).get(
				resident_id,
				{},
			) as Dictionary
		)
		if String(participant.get("status", "")) in [
			"assigned",
			"executing",
		]:
			count += 1
	return count


func _candidate_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_ability := int(left.get("ability_score", 0))
	var right_ability := int(right.get("ability_score", 0))
	if left_ability != right_ability:
		return left_ability > right_ability
	var left_load := int(left.get("load", 0))
	var right_load := int(right.get("load", 0))
	if left_load != right_load:
		return left_load < right_load
	var left_available := int(left.get("available_at", 0))
	var right_available := int(right.get("available_at", 0))
	if left_available != right_available:
		return left_available < right_available
	return String(left.get("resident_id", "")) < String(
		right.get("resident_id", "")
	)


func _matter_allows_resolver(
	matter: Dictionary,
	resolver_id: String,
) -> bool:
	if not bool(_registry.is_resolver_registered(resolver_id)):
		return false
	for rule_value: Variant in matter.get("resolution_rules", []) as Array:
		if String((rule_value as Dictionary).get("resolver_id", "")) == resolver_id:
			return true
	return false


func _append_unique_result(
	matter: Dictionary,
	result_ref: Dictionary,
) -> void:
	var result_id := String(result_ref.get("result_id", "")).strip_edges()
	var stored_results := matter.get("result_refs", []) as Array
	if not result_id.is_empty():
		for existing_value: Variant in stored_results:
			if String((existing_value as Dictionary).get("result_id", "")) == result_id:
				return
	stored_results.append(result_ref.duplicate(true))


func _find_option(options: Array, option_id: String) -> Dictionary:
	for option_value: Variant in options:
		var option := option_value as Dictionary
		if String(option.get("option_id", "")) == option_id:
			return option
	return {}


func _candidate_index(candidates: Array, resident_id: String) -> int:
	for index in candidates.size():
		if String((candidates[index] as Dictionary).get("resident_id", "")) == resident_id:
			return index
	return -1


func _candidate_ids(candidates: Array) -> Array[String]:
	var result: Array[String] = []
	for candidate_value: Variant in candidates:
		result.append(
			String((candidate_value as Dictionary).get("resident_id", ""))
		)
	return result


func _awareness_source_rank(source: String) -> int:
	match source:
		"witnessed", "announcement_broadcast", "town_bell", "postal_notice":
			return 3
		"bulletin_read":
			return 2
		"relayed":
			return 1
		_:
			return 0


func _awareness_level_rank(level: String) -> int:
	return (
		2
		if level in ["known", "participating"]
		else 1 if level == "partial" else 0
	)


func _required_text(value: Dictionary, field: String) -> Dictionary:
	if not value.has(field) or typeof(value.get(field)) != TYPE_STRING:
		return _failure(
			"SOCIAL_FIELD_INVALID",
			"%s 必须是字符串" % field,
		)
	var normalized := String(value.get(field)).strip_edges()
	if normalized.is_empty():
		return _failure(
			"SOCIAL_FIELD_INVALID",
			"%s 不能为空" % field,
		)
	return _success(normalized)


func _string_array(raw_value: Variant, allow_empty: bool) -> Dictionary:
	if typeof(raw_value) != TYPE_ARRAY:
		return _failure(
			"SOCIAL_FIELD_INVALID",
			"字段必须是字符串数组",
		)
	var result: Array[String] = []
	var seen := {}
	for value: Variant in raw_value as Array:
		if typeof(value) != TYPE_STRING:
			return _failure(
				"SOCIAL_FIELD_INVALID",
				"数组只能包含字符串",
			)
		var normalized := String(value).strip_edges()
		if normalized.is_empty():
			return _failure(
				"SOCIAL_FIELD_INVALID",
				"数组不能包含空字符串",
			)
		if not seen.has(normalized):
			seen[normalized] = true
			result.append(normalized)
	if not allow_empty and result.is_empty():
		return _failure(
			"SOCIAL_FIELD_INVALID",
			"数组不能为空",
		)
	result.sort()
	return _success(result)


func _source_key(source_ref: Dictionary, subject_ids: Array) -> String:
	var normalized_subjects: Array[String] = []
	for value: Variant in subject_ids:
		normalized_subjects.append(String(value))
	normalized_subjects.sort()
	return "%s|%s|%s" % [
		String(source_ref.get("source_kind", "")),
		String(source_ref.get("source_id", "")),
		",".join(normalized_subjects),
	]


func _response_key(resident_id: String, response_id: String) -> String:
	return "%s|%s" % [resident_id, response_id]


func _matter(matter_id: String) -> Dictionary:
	return _matters_by_id.get(matter_id.strip_edges(), {}) as Dictionary


func _increment_revision(matter: Dictionary) -> void:
	matter["revision"] = int(matter.get("revision", 0)) + 1


func _success(value: Variant) -> Dictionary:
	return RESULT_ENVELOPE.success(value)


func _failure(error_code: String, reason: String) -> Dictionary:
	return RESULT_ENVELOPE.failure(error_code, reason)
