class_name TownClinicInterviewPolicy
extends RefCounted


const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const SCHEMA_VERSION := 1
const STATUSES := [
	"required",
	"active",
	"completed",
	"refused",
	"interrupted",
]
const PATIENT_RESPONSE_KINDS := ["describe", "decline"]
const COMPLETED_RESPONSE_KINDS := ["describe", "decline"]
const CONTEXT_FIELDS := [
	"schemaVersion",
	"requestId",
	"patientResidentId",
	"conditionIds",
	"reportedSummary",
	"status",
	"conversationId",
	"clinicianResidentId",
	"patientResponseKind",
	"patientResponseTurnId",
	"startedAtMinute",
	"endedAtMinute",
	"attemptCount",
	"endReason",
]


func create_context(
	request_id: String,
	patient_resident_id: String,
	condition_ids: Array,
	reported_summary: String,
) -> Dictionary:
	var normalized_request := request_id.strip_edges()
	var normalized_patient := patient_resident_id.strip_edges()
	var normalized_conditions := _normalized_string_array(condition_ids)
	var normalized_summary := reported_summary.strip_edges()
	if (
		normalized_request.is_empty()
		or normalized_patient.is_empty()
		or normalized_conditions.is_empty()
		or normalized_summary.is_empty()
	):
		return {}
	return {
		"schemaVersion": SCHEMA_VERSION,
		"requestId": normalized_request,
		"patientResidentId": normalized_patient,
		"conditionIds": normalized_conditions,
		"reportedSummary": normalized_summary,
		"status": "required",
		"conversationId": "",
		"clinicianResidentId": "",
		"patientResponseKind": "",
		"patientResponseTurnId": -1,
		"startedAtMinute": -1,
		"endedAtMinute": -1,
		"attemptCount": 0,
		"endReason": "",
	}


func bind_conversation(
	context: Dictionary,
	conversation_id: String,
	clinician_resident_id: String,
	started_at_minute: int,
) -> Dictionary:
	if not validate_context(context):
		return _failure("CLINIC_INTERVIEW_CONTEXT_INVALID")
	var status := String(context.get("status", ""))
	if status not in ["required", "interrupted"]:
		return _failure("CLINIC_INTERVIEW_NOT_BINDABLE")
	var normalized_conversation := conversation_id.strip_edges()
	var normalized_clinician := clinician_resident_id.strip_edges()
	if (
		normalized_conversation.is_empty()
		or normalized_clinician.is_empty()
		or normalized_clinician
		== String(context.get("patientResidentId", ""))
		or started_at_minute < 0
	):
		return _failure("CLINIC_INTERVIEW_BINDING_INVALID")
	var updated := context.duplicate(true)
	updated["status"] = "active"
	updated["conversationId"] = normalized_conversation
	updated["clinicianResidentId"] = normalized_clinician
	updated["patientResponseKind"] = ""
	updated["patientResponseTurnId"] = -1
	updated["startedAtMinute"] = started_at_minute
	updated["endedAtMinute"] = -1
	updated["attemptCount"] = int(updated.get("attemptCount", 0)) + 1
	updated["endReason"] = ""
	return _success(updated)


func record_patient_response(
	context: Dictionary,
	conversation_id: String,
	response_kind: String,
	turn_id: int,
) -> Dictionary:
	if not validate_context(context):
		return _failure("CLINIC_INTERVIEW_CONTEXT_INVALID")
	var normalized_kind := response_kind.strip_edges()
	if (
		String(context.get("status", "")) != "active"
		or String(context.get("conversationId", ""))
		!= conversation_id.strip_edges()
		or normalized_kind not in PATIENT_RESPONSE_KINDS
		or turn_id < 1
	):
		return _failure("CLINIC_INTERVIEW_RESPONSE_INVALID")
	if not String(context.get("patientResponseKind", "")).is_empty():
		return _failure("CLINIC_INTERVIEW_RESPONSE_ALREADY_RECORDED")
	var updated := context.duplicate(true)
	updated["patientResponseKind"] = normalized_kind
	updated["patientResponseTurnId"] = turn_id
	return _success(updated)


func finish_conversation(
	context: Dictionary,
	conversation_id: String,
	end_reason: String,
	ended_at_minute: int,
) -> Dictionary:
	if not validate_context(context):
		return _failure("CLINIC_INTERVIEW_CONTEXT_INVALID")
	if (
		String(context.get("status", "")) != "active"
		or String(context.get("conversationId", ""))
		!= conversation_id.strip_edges()
		or end_reason.strip_edges().is_empty()
		or ended_at_minute < int(context.get("startedAtMinute", 0))
	):
		return _failure("CLINIC_INTERVIEW_FINISH_INVALID")
	var updated := context.duplicate(true)
	var response_kind := String(
		updated.get("patientResponseKind", ""),
	)
	if response_kind == "describe":
		updated["status"] = "completed"
	elif response_kind == "decline" or end_reason == "拒绝接话":
		updated["status"] = "refused"
	else:
		updated["status"] = "interrupted"
	updated["endedAtMinute"] = ended_at_minute
	updated["endReason"] = end_reason.strip_edges()
	return _success(updated)


func activity_is_allowed(context: Dictionary) -> bool:
	return (
		validate_context(context)
		and String(context.get("status", "")) in ["completed", "refused"]
	)


func projection_for_role(context: Dictionary, role: String) -> Dictionary:
	if not validate_context(context):
		return {}
	var normalized_role := role.strip_edges()
	if normalized_role not in ["patient", "clinician"]:
		return {}
	var result := {
		"request_id": String(context.get("requestId", "")),
		"role": normalized_role,
		"status": String(context.get("status", "")),
		"conversation_id": String(context.get("conversationId", "")),
		"reported_summary": String(context.get("reportedSummary", "")),
		"attempt_count": int(context.get("attemptCount", 0)),
		"patient_response_kind": String(
			context.get("patientResponseKind", ""),
		),
		"response_options": [],
	}
	if (
		normalized_role == "patient"
		and String(context.get("status", "")) == "active"
		and String(context.get("patientResponseKind", "")).is_empty()
	):
		result["response_options"] = PATIENT_RESPONSE_KINDS.duplicate()
	return result


func validate_context(context: Dictionary) -> bool:
	if (
		not _exact_keys(context, CONTEXT_FIELDS)
		or int(context.get("schemaVersion", 0)) != SCHEMA_VERSION
		or String(context.get("requestId", "")).strip_edges().is_empty()
		or String(
			context.get("patientResidentId", ""),
		).strip_edges().is_empty()
		or not context.get("conditionIds", []) is Array
		or (context.get("conditionIds", []) as Array).is_empty()
		or typeof(context.get("reportedSummary")) != TYPE_STRING
		or String(context.get("reportedSummary", "")).strip_edges().is_empty()
		or String(context.get("status", "")) not in STATUSES
		or typeof(context.get("conversationId")) != TYPE_STRING
		or typeof(context.get("clinicianResidentId")) != TYPE_STRING
		or typeof(context.get("patientResponseKind")) != TYPE_STRING
		or typeof(context.get("patientResponseTurnId")) != TYPE_INT
		or typeof(context.get("startedAtMinute")) != TYPE_INT
		or typeof(context.get("endedAtMinute")) != TYPE_INT
		or typeof(context.get("attemptCount")) != TYPE_INT
		or int(context.get("attemptCount", -1)) < 0
		or typeof(context.get("endReason")) != TYPE_STRING
	):
		return false
	if _normalized_string_array(
		context.get("conditionIds", []) as Array,
	) != context.get("conditionIds", []):
		return false
	var status := String(context.get("status", ""))
	var response_kind := String(context.get("patientResponseKind", ""))
	var response_turn_id := int(context.get("patientResponseTurnId", -1))
	var conversation_id := String(context.get("conversationId", ""))
	var clinician_id := String(context.get("clinicianResidentId", ""))
	var patient_id := String(context.get("patientResidentId", ""))
	var started_at := int(context.get("startedAtMinute", -1))
	var ended_at := int(context.get("endedAtMinute", -1))
	var attempt_count := int(context.get("attemptCount", -1))
	var end_reason := String(context.get("endReason", ""))
	if not response_kind.is_empty() and response_kind not in COMPLETED_RESPONSE_KINDS:
		return false
	if status == "required":
		return (
			conversation_id.is_empty()
			and clinician_id.is_empty()
			and response_kind.is_empty()
			and response_turn_id == -1
			and started_at == -1
			and ended_at == -1
			and attempt_count == 0
			and end_reason.is_empty()
		)
	if status == "active":
		if (
			conversation_id.is_empty()
			or clinician_id.is_empty()
			or clinician_id == patient_id
			or started_at < 0
			or ended_at != -1
			or attempt_count < 1
			or not end_reason.is_empty()
		):
			return false
		return (
			(response_kind.is_empty() and response_turn_id == -1)
			or (
				response_kind in COMPLETED_RESPONSE_KINDS
				and response_turn_id >= 1
			)
		)
	if (
		conversation_id.is_empty()
		or clinician_id.is_empty()
		or clinician_id == patient_id
		or started_at < 0
		or ended_at < started_at
		or attempt_count < 1
		or end_reason.strip_edges().is_empty()
	):
		return false
	if status == "completed":
		return response_kind == "describe" and response_turn_id >= 1
	if status == "refused":
		return (
			(response_kind == "decline" and response_turn_id >= 1)
			or (
				response_kind.is_empty()
				and response_turn_id == -1
				and end_reason == "拒绝接话"
			)
		)
	return (
		status == "interrupted"
		and response_kind.is_empty()
		and response_turn_id == -1
	)


func _normalized_string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		if typeof(value) != TYPE_STRING:
			continue
		var normalized := String(value).strip_edges()
		if normalized.is_empty() or result.has(normalized):
			continue
		result.append(normalized)
	result.sort()
	return result


func _exact_keys(value: Dictionary, expected: Array) -> bool:
	return WORLD_SCALARS.exact_keys(value, expected)


func _success(context: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"context": context.duplicate(true),
	}


func _failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"context": {},
	}
