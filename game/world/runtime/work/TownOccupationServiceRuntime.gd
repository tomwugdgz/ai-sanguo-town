class_name TownOccupationServiceRuntime
extends RefCounted


const RESULT_SHAPES := preload("res://world/contract/TownWorldResultShapes.gd")
const REQUEST_KINDS := [
	"clinic",
	"library_loan",
	"library_return",
	"library_assist",
	"civic_request",
	"repair",
	"dining_order",
	"cafe_order",
	"grocer_sale",
	"flower_sale",
	"performance",
]
const REQUEST_STATES := [
	"pending",
	"waiting",
	"completed",
	"cancelled",
]
const BOOK_CATALOG := [
	"book_plant_reference",
	"book_town_history",
	"book_practical_crafts",
]
const MAX_TERMINAL_REQUESTS := 128
const MAX_RETURNED_LOANS := 128
const MAX_RESOLVED_FOLLOW_UPS := 128
const MAX_ACCESSION_RECORDS := 256


var _configured := false
var _request_sequence := 0
var _request_terminal_sequence := 0
var _loan_sequence := 0
var _requests: Dictionary = {}
var _loans: Dictionary = {}
var _book_available_copies: Dictionary = {}
var _dirty_dish_count := 0
var _used_cafe_table_count := 0
var _accession_records: Array[Dictionary] = []
var _accession_sequence := 0
var _equipment_conditions: Dictionary = {}
var _follow_up_sequence := 0
var _scheduled_follow_ups: Dictionary = {}
var _dining_order_completion_by_resident: Dictionary = {}
var _archive_summary := {
	"requests": {
		"terminalCount": 0,
		"completedCount": 0,
		"cancelledCount": 0,
		"countByKind": {},
	},
	"returnedLoans": {"count": 0, "countByBook": {}},
	"resolvedFollowUps": {"count": 0},
	"accessions": {"count": 0},
}


func configure() -> Dictionary:
	if _configured:
		return _failure("OCCUPATION_SERVICE_ALREADY_CONFIGURED")
	_configured = true
	return {"ok": true, "errorCode": ""}


func initialize() -> Dictionary:
	if not _configured:
		return _failure("OCCUPATION_SERVICE_NOT_CONFIGURED")
	_request_sequence = 0
	_request_terminal_sequence = 0
	_loan_sequence = 0
	_requests.clear()
	_loans.clear()
	_book_available_copies.clear()
	_dirty_dish_count = 0
	_used_cafe_table_count = 0
	_accession_records.clear()
	_accession_sequence = 0
	_equipment_conditions.clear()
	_follow_up_sequence = 0
	_scheduled_follow_ups.clear()
	_archive_summary = _empty_archive_summary()
	_dining_order_completion_by_resident.clear()
	for book_id: String in BOOK_CATALOG:
		_book_available_copies[book_id] = 1
	return {
		"ok": true,
		"errorCode": "",
		"snapshot": snapshot(),
	}


func create_request(spec: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("OCCUPATION_SERVICE_NOT_CONFIGURED")
	var kind := String(spec.get("kind", "")).strip_edges()
	var requester_id := String(
		spec.get("requesterResidentId", ""),
	).strip_edges()
	var subject_ref := String(spec.get("subjectRef", "")).strip_edges()
	var item_id := String(spec.get("itemId", "")).strip_edges()
	var place_id := String(spec.get("placeId", "")).strip_edges()
	var context := (
		(spec.get("context", {}) as Dictionary).duplicate(true)
		if spec.get("context", {}) is Dictionary
		else {}
	)
	var created_at_value: Variant = spec.get("createdAtMinute")
	if (
		kind not in REQUEST_KINDS
		or requester_id.is_empty()
		or place_id.is_empty()
		or typeof(created_at_value) != TYPE_INT
		or int(created_at_value) < 0
		or (
			kind in ["library_loan", "dining_order", "cafe_order",
				"grocer_sale", "flower_sale"]
			and item_id.is_empty()
		)
		or (
			kind in ["library_return", "repair", "performance"]
			and subject_ref.is_empty()
		)
	):
		return _failure("OCCUPATION_SERVICE_REQUEST_INVALID")
	if kind == "library_loan" and item_id not in BOOK_CATALOG:
		return _failure("OCCUPATION_SERVICE_BOOK_UNKNOWN")
	_request_sequence += 1
	var request_id := "occupation-service-%06d" % _request_sequence
	var request := {
		"requestId": request_id,
		"kind": kind,
		"requesterResidentId": requester_id,
		"subjectRef": subject_ref,
		"itemId": item_id,
		"placeId": place_id,
		"state": "pending",
		"taskId": "",
		"waitReason": "",
		"createdAtMinute": int(created_at_value),
		"completedAtMinute": -1,
		"workerResidentId": "",
		"outcome": {},
		"context": context,
		"terminalSequence": 0,
	}
	_requests[request_id] = request
	return _request_success(request)


func attach_task(request_id: String, task_id: String) -> Dictionary:
	var request := _request_for_update(request_id)
	if (
		request.is_empty()
		or String(request.get("state", "")) != "pending"
		or task_id.strip_edges().is_empty()
		or not String(request.get("taskId", "")).is_empty()
	):
		return _failure("OCCUPATION_SERVICE_TASK_ATTACH_INVALID")
	request["taskId"] = task_id.strip_edges()
	_requests[request_id] = request
	return _request_success(request)


func attach_follow_up_task(
	request_id: String,
	task_id: String,
) -> Dictionary:
	var request := _request_for_update(request_id)
	if (
		request.is_empty()
		or String(request.get("state", "")) not in ["pending", "waiting"]
		or task_id.strip_edges().is_empty()
	):
		return _failure("OCCUPATION_SERVICE_TASK_ATTACH_INVALID")
	request["taskId"] = task_id.strip_edges()
	request["state"] = "pending"
	request["waitReason"] = ""
	_requests[request_id] = request
	return _request_success(request)


func mark_waiting(request_id: String, reason: String) -> Dictionary:
	var request := _request_for_update(request_id)
	if (
		request.is_empty()
		or String(request.get("state", "")) not in ["pending", "waiting"]
		or reason.strip_edges().is_empty()
	):
		return _failure("OCCUPATION_SERVICE_WAIT_INVALID")
	request["state"] = "waiting"
	request["waitReason"] = reason.strip_edges()
	_requests[request_id] = request
	return _request_success(request)


func resume_request(request_id: String) -> Dictionary:
	var request := _request_for_update(request_id)
	if (
		request.is_empty()
		or String(request.get("state", "")) != "waiting"
	):
		return _failure("OCCUPATION_SERVICE_RESUME_INVALID")
	request["state"] = "pending"
	request["waitReason"] = ""
	_requests[request_id] = request
	return _request_success(request)


func record_progress(
	request_id: String,
	outcome: Dictionary,
) -> Dictionary:
	var request := _request_for_update(request_id)
	if (
		request.is_empty()
		or String(request.get("state", "")) not in ["pending", "waiting"]
		or outcome.is_empty()
	):
		return _failure("OCCUPATION_SERVICE_PROGRESS_INVALID")
	request["state"] = "pending"
	request["waitReason"] = ""
	request["outcome"] = outcome.duplicate(true)
	_requests[request_id] = request
	return _request_success(request)


func merge_request_context(
	request_id: String,
	context_patch: Dictionary,
) -> Dictionary:
	var request := _request_for_update(request_id)
	if request.is_empty() or context_patch.is_empty():
		return _failure("OCCUPATION_SERVICE_CONTEXT_INVALID")
	var context := (request.get("context", {}) as Dictionary).duplicate(true)
	for key_value: Variant in context_patch:
		context[String(key_value)] = context_patch.get(key_value)
	request["context"] = context
	_requests[request_id] = request
	return _request_success(request)


func complete_request(
	request_id: String,
	worker_resident_id: String,
	absolute_minute: int,
	outcome: Dictionary,
) -> Dictionary:
	var request := _request_for_update(request_id)
	if (
		request.is_empty()
		or String(request.get("state", "")) not in ["pending", "waiting"]
		or worker_resident_id.strip_edges().is_empty()
		or absolute_minute < int(request.get("createdAtMinute", 0))
		or outcome.is_empty()
	):
		return _failure("OCCUPATION_SERVICE_COMPLETE_INVALID")
	request["state"] = "completed"
	request["waitReason"] = ""
	request["completedAtMinute"] = absolute_minute
	request["workerResidentId"] = worker_resident_id.strip_edges()
	request["outcome"] = outcome.duplicate(true)
	_request_terminal_sequence += 1
	request["terminalSequence"] = _request_terminal_sequence
	_requests[request_id] = request
	_compact_terminal_requests()
	return _request_success(request)


func schedule_follow_up(
	original_request_id: String,
	patient_resident_id: String,
	complaint: String,
	due_at_minute: int,
	created_at_minute: int,
) -> Dictionary:
	if (
		not _configured
		or original_request_id.strip_edges().is_empty()
		or patient_resident_id.strip_edges().is_empty()
		or complaint.strip_edges().is_empty()
		or created_at_minute < 0
		or due_at_minute <= created_at_minute
	):
		return _failure("OCCUPATION_SERVICE_FOLLOW_UP_INVALID")
	for value: Variant in _scheduled_follow_ups.values():
		var existing := value as Dictionary
		if (
			String(existing.get("originalRequestId", ""))
			== original_request_id.strip_edges()
			and String(existing.get("state", "")) in ["scheduled", "requested"]
		):
			return {
				"ok": true,
				"errorCode": "",
				"followUp": existing.duplicate(true),
			}
	_follow_up_sequence += 1
	var follow_up_id := "clinic-follow-up-%06d" % _follow_up_sequence
	var follow_up := {
		"followUpId": follow_up_id,
		"originalRequestId": original_request_id.strip_edges(),
		"patientResidentId": patient_resident_id.strip_edges(),
		"complaint": complaint.strip_edges(),
		"state": "scheduled",
		"createdAtMinute": created_at_minute,
		"dueAtMinute": due_at_minute,
		"requestId": "",
		"resolvedAtMinute": -1,
	}
	_scheduled_follow_ups[follow_up_id] = follow_up
	return {
		"ok": true,
		"errorCode": "",
		"followUp": follow_up.duplicate(true),
	}


func due_follow_ups(absolute_minute: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in _scheduled_follow_ups.values():
		var follow_up := value as Dictionary
		if (
			String(follow_up.get("state", "")) == "scheduled"
			and int(follow_up.get("dueAtMinute", -1)) <= absolute_minute
		):
			result.append(follow_up.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("dueAtMinute", 0)) != int(b.get("dueAtMinute", 0)):
			return int(a.get("dueAtMinute", 0)) < int(b.get("dueAtMinute", 0))
		return String(a.get("followUpId", "")) < String(b.get("followUpId", ""))
	)
	return result


func attach_follow_up_request(
	follow_up_id: String,
	request_id: String,
) -> Dictionary:
	var follow_up := (
		(_scheduled_follow_ups.get(follow_up_id, {}) as Dictionary)
		.duplicate(true)
	)
	if (
		follow_up.is_empty()
		or String(follow_up.get("state", "")) != "scheduled"
		or request_id.strip_edges().is_empty()
	):
		return _failure("OCCUPATION_SERVICE_FOLLOW_UP_ATTACH_INVALID")
	follow_up["state"] = "requested"
	follow_up["requestId"] = request_id.strip_edges()
	_scheduled_follow_ups[follow_up_id] = follow_up
	return {
		"ok": true,
		"errorCode": "",
		"followUp": follow_up.duplicate(true),
	}


func resolve_follow_up(
	follow_up_id: String,
	absolute_minute: int,
) -> Dictionary:
	var follow_up := (
		(_scheduled_follow_ups.get(follow_up_id, {}) as Dictionary)
		.duplicate(true)
	)
	if (
		follow_up.is_empty()
		or String(follow_up.get("state", "")) != "requested"
		or absolute_minute < int(follow_up.get("dueAtMinute", 0))
	):
		return _failure("OCCUPATION_SERVICE_FOLLOW_UP_RESOLVE_INVALID")
	follow_up["state"] = "resolved"
	follow_up["resolvedAtMinute"] = absolute_minute
	_scheduled_follow_ups[follow_up_id] = follow_up
	_compact_resolved_follow_ups()
	return {
		"ok": true,
		"errorCode": "",
		"followUp": follow_up.duplicate(true),
	}


func cancel_request(request_id: String, reason: String) -> Dictionary:
	var request := _request_for_update(request_id)
	if (
		request.is_empty()
		or String(request.get("state", "")) not in ["pending", "waiting"]
		or reason.strip_edges().is_empty()
	):
		return _failure("OCCUPATION_SERVICE_CANCEL_INVALID")
	request["state"] = "cancelled"
	request["waitReason"] = reason.strip_edges()
	_request_terminal_sequence += 1
	request["terminalSequence"] = _request_terminal_sequence
	_requests[request_id] = request
	_compact_terminal_requests()
	return _request_success(request)


func checkout_book(
	request_id: String,
	worker_resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	var request := _request_for_update(request_id)
	var book_id := String(request.get("itemId", ""))
	if (
		String(request.get("kind", "")) != "library_loan"
		or String(request.get("state", "")) not in ["pending", "waiting"]
		or int(_book_available_copies.get(book_id, 0)) <= 0
	):
		return _failure("OCCUPATION_SERVICE_BOOK_UNAVAILABLE")
	_loan_sequence += 1
	var loan_id := "library-loan-%06d" % _loan_sequence
	var loan := {
		"loanId": loan_id,
		"bookId": book_id,
		"borrowerResidentId": String(
			request.get("requesterResidentId", ""),
		),
		"state": "borrowed",
		"borrowedAtMinute": absolute_minute,
		"dueAtMinute": absolute_minute + 4320,
		"returnedAtMinute": -1,
		"handledByResidentId": worker_resident_id,
	}
	_book_available_copies[book_id] = (
		int(_book_available_copies.get(book_id, 0)) - 1
	)
	_loans[loan_id] = loan
	var completed := complete_request(
		request_id,
		worker_resident_id,
		absolute_minute,
		{
			"kind": "loan_record",
			"loanId": loan_id,
			"bookId": book_id,
			"borrowerResidentId": String(
				request.get("requesterResidentId", ""),
			),
			"dueAtMinute": int(loan.get("dueAtMinute", 0)),
		},
	)
	if completed.get("ok") != true:
		return completed
	return {
		"ok": true,
		"errorCode": "",
		"request": (
			completed.get("request", {}) as Dictionary
		).duplicate(true),
		"loan": loan.duplicate(true),
	}


func return_book(
	request_id: String,
	worker_resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	var request := _request_for_update(request_id)
	var loan_id := String(request.get("subjectRef", ""))
	var loan := (_loans.get(loan_id, {}) as Dictionary).duplicate(true)
	if (
		String(request.get("kind", "")) != "library_return"
		or String(request.get("state", "")) not in ["pending", "waiting"]
		or loan.is_empty()
		or String(loan.get("state", "")) != "borrowed"
		or String(loan.get("borrowerResidentId", ""))
		!= String(request.get("requesterResidentId", ""))
	):
		return _failure("OCCUPATION_SERVICE_RETURN_INVALID")
	var book_id := String(loan.get("bookId", ""))
	loan["state"] = "returned"
	loan["returnedAtMinute"] = absolute_minute
	loan["handledByResidentId"] = worker_resident_id
	_loans[loan_id] = loan
	_book_available_copies[book_id] = (
		int(_book_available_copies.get(book_id, 0)) + 1
	)
	var completed := complete_request(
		request_id,
		worker_resident_id,
		absolute_minute,
		{
			"kind": "catalog_state_change",
			"loanId": loan_id,
			"bookId": book_id,
			"returned": true,
		},
	)
	if completed.get("ok") != true:
		return completed
	_compact_returned_loans()
	return {
		"ok": true,
		"errorCode": "",
		"request": (
			completed.get("request", {}) as Dictionary
		).duplicate(true),
		"loan": loan.duplicate(true),
	}


func request(request_id: String) -> Dictionary:
	return (
		(_requests.get(request_id, {}) as Dictionary).duplicate(true)
		if _requests.has(request_id)
		else {}
	)


func loan(loan_id: String) -> Dictionary:
	return (
		(_loans.get(loan_id, {}) as Dictionary).duplicate(true)
		if _loans.has(loan_id)
		else {}
	)


func borrowed_loan_for_resident(resident_id: String) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty():
		return {}
	var loan_ids: Array[String] = []
	for loan_id_value: Variant in _loans:
		loan_ids.append(String(loan_id_value))
	loan_ids.sort()
	for loan_id: String in loan_ids:
		var value := _loans.get(loan_id, {}) as Dictionary
		if (
			String(value.get("state", "")) == "borrowed"
			and String(value.get("borrowerResidentId", ""))
			== normalized_id
		):
			return value.duplicate(true)
	return {}


func borrowed_loans_due_by(absolute_minute: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if absolute_minute < 0:
		return result
	for loan_value: Variant in _loans.values():
		var value := loan_value as Dictionary
		if (
			String(value.get("state", "")) == "borrowed"
			and int(value.get("dueAtMinute", -1)) <= absolute_minute
		):
			result.append(value.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("dueAtMinute", 0)) != int(b.get("dueAtMinute", 0)):
			return int(a.get("dueAtMinute", 0)) < int(b.get("dueAtMinute", 0))
		return String(a.get("loanId", "")) < String(b.get("loanId", ""))
	)
	return result


func has_active_request(kind: String, subject_ref := "") -> bool:
	var normalized_kind := kind.strip_edges()
	var normalized_subject := String(subject_ref).strip_edges()
	for request_value: Variant in _requests.values():
		var value := request_value as Dictionary
		if (
			String(value.get("kind", "")) == normalized_kind
			and String(value.get("state", "")) in ["pending", "waiting"]
			and (
				normalized_subject.is_empty()
				or String(value.get("subjectRef", "")) == normalized_subject
			)
		):
			return true
	return false


func record_equipment_use(
	prop_name: String,
	place_id: String,
	activity_id: String,
	absolute_minute: int,
	wear_limit := 6,
) -> Dictionary:
	var normalized_prop := prop_name.strip_edges()
	var normalized_place := place_id.strip_edges()
	if (
		normalized_prop.is_empty()
		or normalized_place.is_empty()
		or activity_id.strip_edges().is_empty()
		or absolute_minute < 0
		or wear_limit < 2
	):
		return _failure("OCCUPATION_SERVICE_EQUIPMENT_USE_INVALID")
	var condition := (
		(_equipment_conditions.get(normalized_prop, {}) as Dictionary)
		.duplicate(true)
	)
	if condition.is_empty():
		condition = {
			"propName": normalized_prop,
			"placeId": normalized_place,
			"state": "usable",
			"useCount": 0,
			"wearLimit": wear_limit,
			"faultId": "",
			"faultReason": "",
			"lastActivityId": "",
			"updatedAtMinute": absolute_minute,
		}
	if String(condition.get("state", "")) != "maintenance_due":
		condition["useCount"] = int(condition.get("useCount", 0)) + 1
		condition["lastActivityId"] = activity_id.strip_edges()
		condition["updatedAtMinute"] = absolute_minute
		if int(condition.get("useCount", 0)) >= int(
			condition.get("wearLimit", wear_limit),
		):
			condition["state"] = "maintenance_due"
			condition["faultId"] = "equipment-wear:%s:%d" % [
				normalized_prop,
				absolute_minute,
			]
			condition["faultReason"] = "持续使用后需要检修"
	_equipment_conditions[normalized_prop] = condition
	return {
		"ok": true,
		"errorCode": "",
		"condition": condition.duplicate(true),
	}


func active_equipment_faults() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in _equipment_conditions.values():
		var condition := value as Dictionary
		if String(condition.get("state", "")) == "maintenance_due":
			result.append(condition.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("faultId", "")) < String(b.get("faultId", ""))
	)
	return result


func resolve_equipment_fault(
	fault_id: String,
	worker_resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	for prop_value: Variant in _equipment_conditions:
		var prop_name := String(prop_value)
		var condition := (
			(_equipment_conditions.get(prop_name, {}) as Dictionary)
			.duplicate(true)
		)
		if String(condition.get("faultId", "")) != fault_id:
			continue
		if (
			String(condition.get("state", "")) != "maintenance_due"
			or worker_resident_id.strip_edges().is_empty()
			or absolute_minute < int(condition.get("updatedAtMinute", 0))
		):
			return _failure("OCCUPATION_SERVICE_EQUIPMENT_REPAIR_INVALID")
		condition["state"] = "usable"
		condition["useCount"] = 0
		condition["faultId"] = ""
		condition["faultReason"] = ""
		condition["repairedByResidentId"] = worker_resident_id.strip_edges()
		condition["updatedAtMinute"] = absolute_minute
		_equipment_conditions[prop_name] = condition
		return {
			"ok": true,
			"errorCode": "",
			"condition": condition.duplicate(true),
		}
	return _failure("OCCUPATION_SERVICE_EQUIPMENT_FAULT_UNKNOWN")


func record_dirty_dish(
	resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	if (
		resident_id.strip_edges().is_empty()
		or absolute_minute < 0
	):
		return _failure("OCCUPATION_SERVICE_DISH_INVALID")
	_dirty_dish_count += 1
	return {
		"ok": true,
		"errorCode": "",
		"dirtyDishCount": _dirty_dish_count,
	}


func clean_dirty_dish(
	worker_resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	if (
		worker_resident_id.strip_edges().is_empty()
		or absolute_minute < 0
		or _dirty_dish_count <= 0
	):
		return _failure("OCCUPATION_SERVICE_DISH_INVALID")
	_dirty_dish_count -= 1
	return {
		"ok": true,
		"errorCode": "",
		"dirtyDishCount": _dirty_dish_count,
	}


func record_used_cafe_table(
	resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	if (
		resident_id.strip_edges().is_empty()
		or absolute_minute < 0
	):
		return _failure("OCCUPATION_SERVICE_TABLE_INVALID")
	_used_cafe_table_count += 1
	return {
		"ok": true,
		"errorCode": "",
		"usedCafeTableCount": _used_cafe_table_count,
	}


func clean_used_cafe_table(
	worker_resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	if (
		worker_resident_id.strip_edges().is_empty()
		or absolute_minute < 0
		or _used_cafe_table_count <= 0
	):
		return _failure("OCCUPATION_SERVICE_TABLE_INVALID")
	_used_cafe_table_count -= 1
	return {
		"ok": true,
		"errorCode": "",
		"usedCafeTableCount": _used_cafe_table_count,
	}


func record_accession(
	record_id: String,
	worker_resident_id: String,
	absolute_minute: int,
) -> Dictionary:
	if (
		record_id.strip_edges().is_empty()
		or worker_resident_id.strip_edges().is_empty()
		or absolute_minute < 0
		or _has_accession_record(record_id)
	):
		return _failure("OCCUPATION_SERVICE_ACCESSION_INVALID")
	var accession := {
		"accessionId": "",
		"recordId": record_id.strip_edges(),
		"workerResidentId": worker_resident_id.strip_edges(),
		"accessionedAtMinute": absolute_minute,
	}
	_accession_sequence += 1
	accession["accessionId"] = "library-accession-%06d" % _accession_sequence
	_accession_records.append(accession)
	_compact_accession_records()
	return {
		"ok": true,
		"errorCode": "",
		"accession": accession.duplicate(true),
	}


func accession_for_record(record_id: String) -> Dictionary:
	var normalized_record_id := record_id.strip_edges()
	if normalized_record_id.is_empty():
		return {}
	for value: Variant in _accession_records:
		var accession := value as Dictionary
		if String(accession.get("recordId", "")) == normalized_record_id:
			return accession.duplicate(true)
	return {}


func _has_accession_record(record_id: String) -> bool:
	return not accession_for_record(record_id).is_empty()


func snapshot() -> Dictionary:
	var requests: Array[Dictionary] = []
	var request_ids: Array[String] = []
	for request_id_value: Variant in _requests:
		request_ids.append(String(request_id_value))
	request_ids.sort()
	for request_id: String in request_ids:
		requests.append(
			(_requests.get(request_id, {}) as Dictionary).duplicate(true),
		)
	var loans: Array[Dictionary] = []
	var loan_ids: Array[String] = []
	for loan_id_value: Variant in _loans:
		loan_ids.append(String(loan_id_value))
	loan_ids.sort()
	for loan_id: String in loan_ids:
		loans.append(
			(_loans.get(loan_id, {}) as Dictionary).duplicate(true),
		)
	var scheduled_follow_ups: Array[Dictionary] = []
	var follow_up_ids: Array[String] = []
	for follow_up_id_value: Variant in _scheduled_follow_ups:
		follow_up_ids.append(String(follow_up_id_value))
	follow_up_ids.sort()
	for follow_up_id: String in follow_up_ids:
		scheduled_follow_ups.append(
			(_scheduled_follow_ups.get(follow_up_id, {}) as Dictionary)
			.duplicate(true),
		)
	return {
		"schemaVersion": 1,
		"requestSequence": _request_sequence,
		"requestTerminalSequence": _request_terminal_sequence,
		"loanSequence": _loan_sequence,
		"followUpSequence": _follow_up_sequence,
		"accessionSequence": _accession_sequence,
		"requests": requests,
		"loans": loans,
		"bookAvailableCopies": _book_available_copies.duplicate(true),
		"dirtyDishCount": _dirty_dish_count,
		"usedCafeTableCount": _used_cafe_table_count,
		"accessionRecords": _accession_records.duplicate(true),
		"equipmentConditions": _equipment_conditions.duplicate(true),
		"scheduledFollowUps": scheduled_follow_ups,
		"diningOrderCompletionByResident": _dining_order_completion_by_resident.duplicate(
			true,
		),
		"archiveSummary": _archive_summary.duplicate(true),
	}


func restore(value: Dictionary) -> Dictionary:
	if (
		not _configured
		or int(value.get("schemaVersion", 0)) != 1
		or typeof(value.get("requestSequence")) != TYPE_INT
		or typeof(value.get("requestTerminalSequence", 0)) != TYPE_INT
		or typeof(value.get("loanSequence")) != TYPE_INT
		or typeof(value.get("accessionSequence", 0)) != TYPE_INT
		or not value.get("requests") is Array
		or not value.get("loans") is Array
		or not value.get("bookAvailableCopies") is Dictionary
		or typeof(value.get("dirtyDishCount", 0)) != TYPE_INT
		or typeof(value.get("usedCafeTableCount", 0)) != TYPE_INT
		or not value.get("accessionRecords", []) is Array
		or not value.get("equipmentConditions", {}) is Dictionary
		or not value.get("archiveSummary", {}) is Dictionary
		or (
			value.has("diningOrderCompletionByResident")
			and not value.get("diningOrderCompletionByResident", {}) is Dictionary
		)
	):
		return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
	var requests: Dictionary = {}
	for request_value: Variant in value.get("requests", []) as Array:
		if not request_value is Dictionary:
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		var request := (request_value as Dictionary).duplicate(true)
		var request_id := String(request.get("requestId", ""))
		if not request.has("terminalSequence"):
			request["terminalSequence"] = 0
		if (
			request_id.is_empty()
			or requests.has(request_id)
			or String(request.get("kind", "")) not in REQUEST_KINDS
			or String(request.get("state", "")) not in REQUEST_STATES
			or typeof(request.get("terminalSequence", 0)) != TYPE_INT
			or int(request.get("terminalSequence", 0)) < 0
		):
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		requests[request_id] = request
	var loans: Dictionary = {}
	for loan_value: Variant in value.get("loans", []) as Array:
		if not loan_value is Dictionary:
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		var loan := (loan_value as Dictionary).duplicate(true)
		var loan_id := String(loan.get("loanId", ""))
		if (
			loan_id.is_empty()
			or loans.has(loan_id)
			or String(loan.get("bookId", "")) not in BOOK_CATALOG
			or String(loan.get("state", "")) not in ["borrowed", "returned"]
		):
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		loans[loan_id] = loan
	var book_copies: Dictionary = {}
	for book_id: String in BOOK_CATALOG:
		var copies_value: Variant = (
			value.get("bookAvailableCopies", {}) as Dictionary
		).get(book_id)
		if typeof(copies_value) != TYPE_INT or int(copies_value) < 0:
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		book_copies[book_id] = int(copies_value)
	var accession_records: Array[Dictionary] = []
	for accession_value: Variant in (
		value.get("accessionRecords", []) as Array
	):
		if not accession_value is Dictionary:
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		accession_records.append(
			(accession_value as Dictionary).duplicate(true),
		)
	var equipment_conditions: Dictionary = {}
	for condition_value: Variant in (
		value.get("equipmentConditions", {}) as Dictionary
	).values():
		if not condition_value is Dictionary:
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		var condition := (condition_value as Dictionary).duplicate(true)
		var prop_name := String(condition.get("propName", ""))
		if (
			prop_name.is_empty()
			or equipment_conditions.has(prop_name)
			or String(condition.get("placeId", "")).is_empty()
			or String(condition.get("state", ""))
			not in ["usable", "maintenance_due"]
			or typeof(condition.get("useCount")) != TYPE_INT
			or int(condition.get("useCount", -1)) < 0
		):
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		equipment_conditions[prop_name] = condition
	var scheduled_follow_ups: Dictionary = {}
	for follow_up_value: Variant in value.get("scheduledFollowUps", []) as Array:
		if not follow_up_value is Dictionary:
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		var follow_up := (follow_up_value as Dictionary).duplicate(true)
		var follow_up_id := String(follow_up.get("followUpId", ""))
		if (
			follow_up_id.is_empty()
			or scheduled_follow_ups.has(follow_up_id)
			or String(follow_up.get("patientResidentId", "")).is_empty()
			or String(follow_up.get("state", ""))
			not in ["scheduled", "requested", "resolved"]
		):
			return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
		scheduled_follow_ups[follow_up_id] = follow_up
	_request_sequence = int(value.get("requestSequence", 0))
	_request_terminal_sequence = int(
		value.get("requestTerminalSequence", 0),
	)
	_loan_sequence = int(value.get("loanSequence", 0))
	_follow_up_sequence = int(value.get("followUpSequence", 0))
	_accession_sequence = int(
		value.get("accessionSequence", accession_records.size()),
	)
	_requests = requests
	_loans = loans
	_book_available_copies = book_copies
	_dirty_dish_count = int(value.get("dirtyDishCount", 0))
	_used_cafe_table_count = int(
		value.get("usedCafeTableCount", 0),
	)
	if _dirty_dish_count < 0 or _used_cafe_table_count < 0:
		return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
	_accession_records = accession_records
	_equipment_conditions = equipment_conditions
	_scheduled_follow_ups = scheduled_follow_ups
	_dining_order_completion_by_resident = _normalize_dining_order_completion_map(
		value.get("diningOrderCompletionByResident", {}) as Dictionary,
	)
	_archive_summary = _normalized_archive_summary(
		value.get("archiveSummary", {}) as Dictionary,
	)
	_rebuild_dining_order_completion_history()
	if (
		_request_terminal_sequence < 0
		or _accession_sequence < 0
		or _archive_summary.is_empty()
	):
		return _failure("OCCUPATION_SERVICE_SAVE_INVALID")
	_restore_terminal_sequences()
	_compact_terminal_requests()
	_compact_returned_loans()
	_compact_resolved_follow_ups()
	_compact_accession_records()
	return {
		"ok": true,
		"errorCode": "",
		"snapshot": snapshot(),
	}


func _empty_archive_summary() -> Dictionary:
	return {
		"requests": {
			"terminalCount": 0,
			"completedCount": 0,
			"cancelledCount": 0,
			"countByKind": {},
		},
		"returnedLoans": {"count": 0, "countByBook": {}},
		"resolvedFollowUps": {"count": 0},
		"accessions": {"count": 0},
	}


func _compact_terminal_requests() -> void:
	var terminal: Array[Dictionary] = []
	for value: Variant in _requests.values():
		var request_value := value as Dictionary
		if String(request_value.get("state", "")) in ["completed", "cancelled"]:
			terminal.append(request_value)
	terminal.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("terminalSequence", 0)) != int(b.get("terminalSequence", 0)):
			return int(a.get("terminalSequence", 0)) > int(b.get("terminalSequence", 0))
		return String(a.get("requestId", "")) > String(b.get("requestId", ""))
	)
	for index in range(MAX_TERMINAL_REQUESTS, terminal.size()):
		var request_value := terminal[index] as Dictionary
		_archive_terminal_request(request_value)
		_requests.erase(String(request_value.get("requestId", "")))


func _archive_terminal_request(request_value: Dictionary) -> void:
	var summary := (
		_archive_summary.get("requests", {}) as Dictionary
	).duplicate(true)
	summary["terminalCount"] = int(summary.get("terminalCount", 0)) + 1
	var state := String(request_value.get("state", ""))
	var state_key := "completedCount" if state == "completed" else "cancelledCount"
	summary[state_key] = int(summary.get(state_key, 0)) + 1
	var count_by_kind := (
		summary.get("countByKind", {}) as Dictionary
	).duplicate(true)
	var kind := String(request_value.get("kind", ""))
	count_by_kind[kind] = int(count_by_kind.get(kind, 0)) + 1
	summary["countByKind"] = count_by_kind
	_archive_summary["requests"] = summary


func _compact_returned_loans() -> void:
	var returned: Array[Dictionary] = []
	for value: Variant in _loans.values():
		var loan_value := value as Dictionary
		if String(loan_value.get("state", "")) == "returned":
			returned.append(loan_value)
	returned.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("returnedAtMinute", -1)) != int(b.get("returnedAtMinute", -1)):
			return int(a.get("returnedAtMinute", -1)) > int(b.get("returnedAtMinute", -1))
		return String(a.get("loanId", "")) > String(b.get("loanId", ""))
	)
	for index in range(MAX_RETURNED_LOANS, returned.size()):
		var loan_value := returned[index] as Dictionary
		var summary := (
			_archive_summary.get("returnedLoans", {}) as Dictionary
		).duplicate(true)
		summary["count"] = int(summary.get("count", 0)) + 1
		var count_by_book := (
			summary.get("countByBook", {}) as Dictionary
		).duplicate(true)
		var book_id := String(loan_value.get("bookId", ""))
		count_by_book[book_id] = int(count_by_book.get(book_id, 0)) + 1
		summary["countByBook"] = count_by_book
		_archive_summary["returnedLoans"] = summary
		_loans.erase(String(loan_value.get("loanId", "")))


func _compact_resolved_follow_ups() -> void:
	var resolved: Array[Dictionary] = []
	for value: Variant in _scheduled_follow_ups.values():
		var follow_up := value as Dictionary
		if String(follow_up.get("state", "")) == "resolved":
			resolved.append(follow_up)
	resolved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("resolvedAtMinute", -1)) != int(b.get("resolvedAtMinute", -1)):
			return int(a.get("resolvedAtMinute", -1)) > int(b.get("resolvedAtMinute", -1))
		return String(a.get("followUpId", "")) > String(b.get("followUpId", ""))
	)
	for index in range(MAX_RESOLVED_FOLLOW_UPS, resolved.size()):
		var follow_up := resolved[index] as Dictionary
		var summary := (
			_archive_summary.get("resolvedFollowUps", {}) as Dictionary
		).duplicate(true)
		summary["count"] = int(summary.get("count", 0)) + 1
		_archive_summary["resolvedFollowUps"] = summary
		_scheduled_follow_ups.erase(String(follow_up.get("followUpId", "")))


func _compact_accession_records() -> void:
	_accession_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("accessionedAtMinute", -1)) != int(b.get("accessionedAtMinute", -1)):
			return int(a.get("accessionedAtMinute", -1)) > int(b.get("accessionedAtMinute", -1))
		return String(a.get("accessionId", "")) > String(b.get("accessionId", ""))
	)
	while _accession_records.size() > MAX_ACCESSION_RECORDS:
		_accession_records.pop_back()
		var summary := (
			_archive_summary.get("accessions", {}) as Dictionary
		).duplicate(true)
		summary["count"] = int(summary.get("count", 0)) + 1
		_archive_summary["accessions"] = summary


func _restore_terminal_sequences() -> void:
	var terminal: Array[Dictionary] = []
	for value: Variant in _requests.values():
		var request_value := value as Dictionary
		if String(request_value.get("state", "")) in ["completed", "cancelled"]:
			terminal.append(request_value)
	terminal.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("completedAtMinute", -1)) != int(b.get("completedAtMinute", -1)):
			return int(a.get("completedAtMinute", -1)) < int(b.get("completedAtMinute", -1))
		return String(a.get("requestId", "")) < String(b.get("requestId", ""))
	)
	for request_value: Dictionary in terminal:
		_request_terminal_sequence = maxi(
			_request_terminal_sequence,
			int(request_value.get("terminalSequence", 0)),
		)
	for request_value: Dictionary in terminal:
		var sequence := int(request_value.get("terminalSequence", 0))
		if sequence <= 0:
			_request_terminal_sequence += 1
			request_value["terminalSequence"] = _request_terminal_sequence
			_requests[String(request_value.get("requestId", ""))] = request_value
	for accession: Dictionary in _accession_records:
		var parts := String(accession.get("accessionId", "")).split("-")
		if not parts.is_empty() and String(parts[-1]).is_valid_int():
			_accession_sequence = maxi(_accession_sequence, int(parts[-1]))


func _normalized_archive_summary(value: Dictionary) -> Dictionary:
	var result := _empty_archive_summary()
	var specs := {
		"requests": ["terminalCount", "completedCount", "cancelledCount"],
		"returnedLoans": ["count"],
		"resolvedFollowUps": ["count"],
		"accessions": ["count"],
	}
	for section_value: Variant in specs:
		var section := String(section_value)
		var source_value: Variant = value.get(section, {})
		if not source_value is Dictionary:
			return {}
		var source := source_value as Dictionary
		var target := (result.get(section, {}) as Dictionary).duplicate(true)
		for key_value: Variant in specs.get(section, []) as Array:
			var key := String(key_value)
			var count_value: Variant = source.get(key, 0)
			if typeof(count_value) != TYPE_INT or int(count_value) < 0:
				return {}
			target[key] = int(count_value)
		for map_key: String in ["countByKind", "countByBook"]:
			if not target.has(map_key):
				continue
			var map_value: Variant = source.get(map_key, {})
			if not map_value is Dictionary:
				return {}
			var normalized_map: Dictionary = {}
			for item_value: Variant in map_value as Dictionary:
				var count_value: Variant = (map_value as Dictionary).get(item_value)
				if typeof(count_value) != TYPE_INT or int(count_value) < 0:
					return {}
				normalized_map[String(item_value)] = int(count_value)
			target[map_key] = normalized_map
		result[section] = target
	return result


func mark_dining_order_completed_for_resident_meal_period(
	resident_id: String,
	meal_period_ref: String,
) -> void:
	var normalized_resident := resident_id.strip_edges()
	var normalized_period := meal_period_ref.strip_edges()
	if normalized_resident.is_empty() or normalized_period.is_empty():
		return
	var periods := (
		_dining_order_completion_by_resident.get(
			normalized_resident,
			{},
		) as Dictionary
	).duplicate(true)
	periods[normalized_period] = true
	_dining_order_completion_by_resident[normalized_resident] = periods


func has_dining_order_completed_for_resident_meal_period(
	resident_id: String,
	meal_period_ref: String,
) -> bool:
	var normalized_resident := resident_id.strip_edges()
	var normalized_period := meal_period_ref.strip_edges()
	if normalized_resident.is_empty() or normalized_period.is_empty():
		return false
	var periods := (
		_dining_order_completion_by_resident.get(normalized_resident, {})
		as Dictionary
	)
	return bool(periods.get(normalized_period, false))


func _normalize_dining_order_completion_map(
	value: Dictionary,
) -> Dictionary:
	var normalized: Dictionary = {}
	for resident_value: Variant in value:
		var resident_id := String(resident_value)
		var period_map_value: Variant = value.get(resident_id)
		if resident_id.is_empty() or not period_map_value is Dictionary:
			continue
		var period_map := period_map_value as Dictionary
		var normalized_period_map: Dictionary = {}
		for period_value: Variant in period_map:
			var period_ref := String(period_value)
			if period_ref.is_empty():
				continue
			if bool(period_map.get(period_ref, false)):
				normalized_period_map[period_ref] = true
		if not normalized_period_map.is_empty():
			normalized[resident_id] = normalized_period_map
	return normalized


func _rebuild_dining_order_completion_history() -> void:
	for request_value: Variant in _requests.values():
		var request := request_value as Dictionary
		if (
			String(request.get("kind", "")) != "dining_order"
			or String(request.get("state", "")) != "completed"
		):
			continue
		var resident_id := String(request.get("requesterResidentId", ""))
		var meal_period_ref := String(
			(request.get("context", {}) as Dictionary).get(
				"mealPeriodRef",
				"",
			),
		)
		if resident_id.is_empty() or meal_period_ref.is_empty():
			continue
		mark_dining_order_completed_for_resident_meal_period(
			resident_id,
			meal_period_ref,
		)


func _request_for_update(request_id: String) -> Dictionary:
	return (
		(_requests.get(request_id, {}) as Dictionary).duplicate(true)
		if _requests.has(request_id)
		else {}
	)


func _request_success(request: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"request": request.duplicate(true),
	}


func _failure(error_code: String) -> Dictionary:
	return RESULT_SHAPES.failure_minimal(error_code)
