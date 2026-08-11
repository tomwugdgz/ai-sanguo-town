class_name TownWorkTaskRuntime
extends RefCounted


signal task_committed(task: Dictionary)


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const CHAIN_CATALOG := preload(
	"res://world/data/town/TownWorkChainCatalog.gd"
)
const TERMINAL_STATES := ["completed", "failed", "cancelled"]
const MAX_TERMINAL_TASKS := 128
const TASK_FIELDS := [
	"taskId",
	"capability",
	"sourceKind",
	"sourceRef",
	"targets",
	"requestedResultKind",
	"createdAtMinute",
	"priority",
]
const TARGET_FIELDS := ["kind", "ref"]
const RESULT_FIELDS := ["resultRef", "facts"]
const REQUIRED_TARGET_KINDS_BY_CAPABILITY := {
	"message.deliver": ["resident"],
	"cargo.pickup": ["cargo_lot"],
	"cargo.transport": ["cargo_lot", "route"],
	"cargo.deliver": ["cargo_lot"],
	"fishing.harvest": ["region"],
	"garden.care": ["region"],
	"garden.harvest": ["region"],
	"research.observe": ["region"],
	"music.perform": ["audience_area"],
}


var _catalog: Dictionary = {}
var _chains_by_occupation: Dictionary = {}
var _occupation_ids_by_capability: Dictionary = {}
var _tasks: Dictionary = {}
var _terminal_sequence := 0
var _configured := false


func configure(catalog: Dictionary = {}) -> Dictionary:
	if _configured:
		return _failure("WORK_TASK_RUNTIME_ALREADY_CONFIGURED")
	_catalog = (
		CHAIN_CATALOG.load_catalog()
		if catalog.is_empty()
		else catalog.duplicate(true)
	)
	var errors := CHAIN_CATALOG.validate(_catalog)
	if not errors.is_empty():
		_catalog.clear()
		return _failure("WORK_CHAIN_CATALOG_INVALID", {
			"errors": Array(errors),
		})
	for value: Variant in _catalog.get("chains", []) as Array:
		var chain := value as Dictionary
		var occupation_id := String(chain.get("occupationId", ""))
		_chains_by_occupation[occupation_id] = chain.duplicate(true)
		for capability_value: Variant in (
			chain.get("taskCapabilities", []) as Array
		):
			var capability := String(capability_value)
			var occupation_ids := (
				_occupation_ids_by_capability.get(
					capability,
					[],
				) as Array
			).duplicate()
			occupation_ids.append(occupation_id)
			_occupation_ids_by_capability[capability] = occupation_ids
	_configured = true
	return {
		"ok": true,
		"errorCode": "",
		"taskCount": 0,
		"occupationCount": _chains_by_occupation.size(),
	}


func create_task(spec: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("WORK_TASK_RUNTIME_NOT_CONFIGURED")
	if not _exact_keys(spec, TASK_FIELDS):
		return _failure("WORK_TASK_SHAPE_INVALID")
	var task_id := String(spec.get("taskId", "")).strip_edges()
	var capability := String(spec.get("capability", "")).strip_edges()
	var source_kind := String(spec.get("sourceKind", "")).strip_edges()
	var source_ref := String(spec.get("sourceRef", "")).strip_edges()
	var result_kind := String(
		spec.get("requestedResultKind", ""),
	).strip_edges()
	if (
		task_id.is_empty()
		or _tasks.has(task_id)
		or capability.is_empty()
		or source_kind.is_empty()
		or source_ref.is_empty()
		or result_kind.is_empty()
	):
		return _failure("WORK_TASK_IDENTITY_INVALID")
	var eligible_occupation_ids := (
		_occupation_ids_by_capability.get(capability, []) as Array
	).duplicate()
	if eligible_occupation_ids.is_empty():
		return _failure("WORK_TASK_CAPABILITY_UNKNOWN")
	var allowed_result := false
	var allowed_source := false
	var allowed_target_kinds: Dictionary = {}
	for occupation_id_value: Variant in eligible_occupation_ids:
		var chain := _chains_by_occupation.get(
			String(occupation_id_value),
			{},
		) as Dictionary
		if (chain.get("resultKinds", []) as Array).has(result_kind):
			allowed_result = true
		if (chain.get("taskSources", []) as Array).has(source_kind):
			allowed_source = true
		for target_kind_value: Variant in (
			chain.get("targetKinds", []) as Array
		):
			allowed_target_kinds[String(target_kind_value)] = true
	if not allowed_source:
		return _failure("WORK_TASK_SOURCE_KIND_INVALID")
	if not allowed_result:
		return _failure("WORK_TASK_RESULT_KIND_INVALID")
	var targets_value: Variant = spec.get("targets")
	if not targets_value is Array or targets_value.is_empty():
		return _failure("WORK_TASK_TARGET_REQUIRED")
	var targets: Array[Dictionary] = []
	var target_keys: Dictionary = {}
	var present_target_kinds: Dictionary = {}
	for value: Variant in targets_value as Array:
		if not value is Dictionary:
			return _failure("WORK_TASK_TARGET_INVALID")
		var target := value as Dictionary
		if not _exact_keys(target, TARGET_FIELDS):
			return _failure("WORK_TASK_TARGET_INVALID")
		var kind := String(target.get("kind", "")).strip_edges()
		var ref := String(target.get("ref", "")).strip_edges()
		var target_key := "%s:%s" % [kind, ref]
		if (
			kind.is_empty()
			or ref.is_empty()
			or not allowed_target_kinds.has(kind)
			or target_keys.has(target_key)
		):
			return _failure("WORK_TASK_TARGET_INVALID")
		target_keys[target_key] = true
		present_target_kinds[kind] = true
		targets.append({"kind": kind, "ref": ref})
	for required_kind_value: Variant in (
		REQUIRED_TARGET_KINDS_BY_CAPABILITY.get(
			capability,
			[],
		) as Array
	):
		if not present_target_kinds.has(String(required_kind_value)):
			return _failure("WORK_TASK_REQUIRED_TARGET_MISSING")
	var created_at: Variant = spec.get("createdAtMinute")
	var priority: Variant = spec.get("priority")
	if (
		typeof(created_at) != TYPE_INT
		or int(created_at) < 0
		or typeof(priority) != TYPE_INT
		or int(priority) < 0
		or int(priority) > 100
	):
		return _failure("WORK_TASK_SCHEDULING_INVALID")
	var task := {
		"taskId": task_id,
		"capability": capability,
		"sourceKind": source_kind,
		"sourceRef": source_ref,
		"targets": targets,
		"requestedResultKind": result_kind,
		"createdAtMinute": int(created_at),
		"priority": int(priority),
		"eligibleOccupationIds": eligible_occupation_ids,
		"eligibleResidentIds": [],
		"state": "open",
		"revision": 1,
		"assignedResidentId": "",
		"assignedOccupationId": "",
		"waitReason": "",
		"processStage": "ready",
		"processFacts": {},
		"result": {},
		"terminalSequence": 0,
	}
	_tasks[task_id] = task
	task_committed.emit(task.duplicate(true))
	return _success(task)


func create_task_for_occupations(
	spec: Dictionary,
	occupation_ids: Array,
) -> Dictionary:
	var created := create_task(spec)
	if created.get("ok") != true:
		return created
	var task := created.get("task", {}) as Dictionary
	var allowed := task.get("eligibleOccupationIds", []) as Array
	var scoped: Array[String] = []
	for occupation_value: Variant in occupation_ids:
		var occupation_id := String(occupation_value).strip_edges()
		if (
			occupation_id.is_empty()
			or not allowed.has(occupation_id)
			or scoped.has(occupation_id)
		):
			continue
		scoped.append(occupation_id)
	if scoped.is_empty():
		_tasks.erase(String(task.get("taskId", "")))
		return _failure("WORK_TASK_ASSIGNEE_SCOPE_INVALID")
	scoped.sort()
	task["eligibleOccupationIds"] = scoped
	_tasks[String(task.get("taskId", ""))] = task
	return _success(task)


func accept_task(
	task_id: String,
	resident_id: String,
	occupation_id: String,
	expected_revision: int,
) -> Dictionary:
	var task := _task_for_update(task_id, expected_revision)
	if task.is_empty():
		return _task_update_failure(task_id, expected_revision)
	if String(task.get("state", "")) not in ["open", "waiting"]:
		return _failure("WORK_TASK_STATE_INVALID")
	if (
		resident_id.strip_edges().is_empty()
		or (
			not (task.get("eligibleOccupationIds", []) as Array).has(
				occupation_id,
			)
			and not (task.get("eligibleResidentIds", []) as Array).has(
				resident_id.strip_edges(),
			)
		)
	):
		return _failure("WORK_TASK_ASSIGNEE_INELIGIBLE")
	task["state"] = "accepted"
	task["assignedResidentId"] = resident_id
	task["assignedOccupationId"] = occupation_id
	task["waitReason"] = ""
	_commit_task(task)
	return _success(task)


func add_eligible_residents(
	task_id: String,
	resident_ids: Array,
) -> Dictionary:
	if not _tasks.has(task_id) or resident_ids.is_empty():
		return _failure("WORK_TASK_RESIDENT_SCOPE_INVALID")
	var task := (_tasks.get(task_id, {}) as Dictionary).duplicate(true)
	if String(task.get("state", "")) in TERMINAL_STATES:
		return _failure("WORK_TASK_ALREADY_TERMINAL")
	var eligible: Array[String] = []
	for resident_value: Variant in task.get("eligibleResidentIds", []) as Array:
		var existing_id := String(resident_value).strip_edges()
		if not existing_id.is_empty() and not eligible.has(existing_id):
			eligible.append(existing_id)
	for resident_value: Variant in resident_ids:
		var resident_id := String(resident_value).strip_edges()
		if not resident_id.is_empty() and not eligible.has(resident_id):
			eligible.append(resident_id)
	if eligible.is_empty():
		return _failure("WORK_TASK_RESIDENT_SCOPE_INVALID")
	eligible.sort()
	if eligible == (task.get("eligibleResidentIds", []) as Array):
		return _success(task)
	task["eligibleResidentIds"] = eligible
	_commit_task(task)
	return _success(task)


func start_task(
	task_id: String,
	resident_id: String,
	expected_revision: int,
) -> Dictionary:
	var task := _task_for_update(task_id, expected_revision)
	if task.is_empty():
		return _task_update_failure(task_id, expected_revision)
	if (
		String(task.get("state", "")) != "accepted"
		or String(task.get("assignedResidentId", "")) != resident_id
	):
		return _failure("WORK_TASK_STATE_INVALID")
	task["state"] = "in_progress"
	_commit_task(task)
	return _success(task)


func wait_task(
	task_id: String,
	resident_id: String,
	expected_revision: int,
	reason: String,
) -> Dictionary:
	var task := _task_for_update(task_id, expected_revision)
	if task.is_empty():
		return _task_update_failure(task_id, expected_revision)
	if (
		String(task.get("state", "")) not in [
			"accepted",
			"in_progress",
		]
		or String(task.get("assignedResidentId", "")) != resident_id
		or reason.strip_edges().is_empty()
	):
		return _failure("WORK_TASK_STATE_INVALID")
	task["state"] = "waiting"
	task["waitReason"] = reason.strip_edges()
	_commit_task(task)
	return _success(task)


func configure_initial_process(
	task_id: String,
	expected_revision: int,
	stage: String,
	facts: Dictionary,
) -> Dictionary:
	var task := _task_for_update(task_id, expected_revision)
	if task.is_empty():
		return _task_update_failure(task_id, expected_revision)
	if (
		String(task.get("state", "")) != "open"
		or String(task.get("processStage", "ready")) != "ready"
		or stage.strip_edges().is_empty()
	):
		return _failure("WORK_TASK_PROCESS_INVALID")
	task["processStage"] = stage.strip_edges()
	task["processFacts"] = facts.duplicate(true)
	_commit_task(task)
	return _success(task)


func advance_process_stage(
	task_id: String,
	resident_id: String,
	expected_revision: int,
	next_stage: String,
	facts: Dictionary,
) -> Dictionary:
	var task := _task_for_update(task_id, expected_revision)
	if task.is_empty():
		return _task_update_failure(task_id, expected_revision)
	if (
		String(task.get("state", "")) not in ["in_progress", "waiting"]
		or String(task.get("assignedResidentId", "")) != resident_id
		or next_stage.strip_edges().is_empty()
	):
		return _failure("WORK_TASK_PROCESS_INVALID")
	var history := (
		(task.get("processFacts", {}) as Dictionary).get(
			"stageHistory",
			[],
		) as Array
	).duplicate(true)
	history.append({
		"stage": String(task.get("processStage", "ready")),
		"facts": (task.get("processFacts", {}) as Dictionary).duplicate(true),
	})
	var next_facts := facts.duplicate(true)
	next_facts["stageHistory"] = history
	task["state"] = "in_progress"
	task["waitReason"] = ""
	task["processStage"] = next_stage.strip_edges()
	task["processFacts"] = next_facts
	_commit_task(task)
	return _success(task)


func set_process_stage_from_world(
	task_id: String,
	expected_revision: int,
	next_stage: String,
	facts: Dictionary,
) -> Dictionary:
	var task := _task_for_update(task_id, expected_revision)
	if task.is_empty():
		return _task_update_failure(task_id, expected_revision)
	if next_stage.strip_edges().is_empty():
		return _failure("WORK_TASK_PROCESS_INVALID")
	task["processStage"] = next_stage.strip_edges()
	task["processFacts"] = facts.duplicate(true)
	_commit_task(task)
	return _success(task)


func complete_task(
	task_id: String,
	resident_id: String,
	expected_revision: int,
	result_kind: String,
	evidence: Dictionary,
) -> Dictionary:
	var task := _task_for_update(task_id, expected_revision)
	if task.is_empty():
		return _task_update_failure(task_id, expected_revision)
	if (
		String(task.get("state", "")) not in [
			"in_progress",
			"waiting",
		]
		or String(task.get("assignedResidentId", "")) != resident_id
		or result_kind != String(task.get("requestedResultKind", ""))
		or not _exact_keys(evidence, RESULT_FIELDS)
		or String(evidence.get("resultRef", "")).strip_edges().is_empty()
		or not evidence.get("facts") is Dictionary
		or (evidence.get("facts", {}) as Dictionary).is_empty()
	):
		return _failure("WORK_TASK_RESULT_EVIDENCE_INVALID")
	task["state"] = "completed"
	task["result"] = {
		"kind": result_kind,
		"resultRef": String(evidence.get("resultRef", "")),
		"facts": (
			evidence.get("facts", {}) as Dictionary
		).duplicate(true),
	}
	_commit_terminal_task(task)
	return _success(task)


func task(task_id: String) -> Dictionary:
	return (
		(_tasks.get(task_id, {}) as Dictionary).duplicate(true)
		if _tasks.has(task_id)
		else {}
	)


func active_task_for_source(
	source_kind: String,
	source_ref: String,
) -> Dictionary:
	for task_id_value: Variant in _tasks:
		var value := _tasks.get(task_id_value, {}) as Dictionary
		if (
			String(value.get("sourceKind", "")) == source_kind
			and String(value.get("sourceRef", "")) == source_ref
			and String(value.get("state", "")) not in TERMINAL_STATES
		):
			return value.duplicate(true)
	return {}


func cancel_task(task_id: String, reason: String) -> Dictionary:
	if not _tasks.has(task_id) or reason.strip_edges().is_empty():
		return _failure("WORK_TASK_CANCEL_INVALID")
	var task := (_tasks.get(task_id, {}) as Dictionary).duplicate(true)
	if String(task.get("state", "")) in TERMINAL_STATES:
		return _failure("WORK_TASK_STATE_INVALID")
	task["state"] = "cancelled"
	task["waitReason"] = reason.strip_edges()
	_commit_terminal_task(task)
	return _success(task)


func release_tasks_for_resident(
	resident_id: String,
	reason: String,
) -> Dictionary:
	var normalized_resident := resident_id.strip_edges()
	var normalized_reason := reason.strip_edges()
	if normalized_resident.is_empty() or normalized_reason.is_empty():
		return _failure("WORK_TASK_RELEASE_INVALID")
	var released_task_ids: Array[String] = []
	for task_id_value: Variant in _tasks:
		var task_id := String(task_id_value)
		var task := _tasks.get(task_id, {}) as Dictionary
		if (
			String(task.get("assignedResidentId", ""))
			!= normalized_resident
			or String(task.get("state", "")) in TERMINAL_STATES
		):
			continue
		var updated := task.duplicate(true)
		updated["state"] = "waiting"
		updated["assignedResidentId"] = ""
		updated["assignedOccupationId"] = ""
		updated["waitReason"] = normalized_reason
		_commit_task(updated)
		released_task_ids.append(task_id)
	released_task_ids.sort()
	return {
		"ok": true,
		"errorCode": "",
		"releasedTaskIds": released_task_ids,
	}


func release_task(
	task_id: String,
	resident_id: String,
	expected_revision: int,
	reason: String,
) -> Dictionary:
	var task := _task_for_update(task_id, expected_revision)
	if task.is_empty():
		return _task_update_failure(task_id, expected_revision)
	if (
		String(task.get("state", "")) not in ["accepted", "in_progress"]
		or String(task.get("assignedResidentId", ""))
		!= resident_id.strip_edges()
		or reason.strip_edges().is_empty()
	):
		return _failure("WORK_TASK_RELEASE_INVALID")
	task["state"] = "waiting"
	task["assignedResidentId"] = ""
	task["assignedOccupationId"] = ""
	task["waitReason"] = reason.strip_edges()
	_commit_task(task)
	return _success(task)


func create_save_snapshot() -> Dictionary:
	var task_ids: Array[String] = []
	for task_id_value: Variant in _tasks:
		task_ids.append(String(task_id_value))
	task_ids.sort()
	var tasks: Array[Dictionary] = []
	for task_id: String in task_ids:
		tasks.append(
			(_tasks.get(task_id, {}) as Dictionary).duplicate(true),
		)
	return {
		"schemaVersion": 1,
		"tasks": tasks,
	}


func restore_save_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("WORK_TASK_RUNTIME_NOT_CONFIGURED")
	if (
		not _exact_keys(snapshot, ["schemaVersion", "tasks"])
		or snapshot.get("schemaVersion") != 1
		or not snapshot.get("tasks") is Array
	):
		return _failure("WORK_TASK_SNAPSHOT_INVALID")
	var restored: Dictionary = {}
	_tasks.clear()
	_terminal_sequence = 0
	for value: Variant in snapshot.get("tasks", []) as Array:
		if not value is Dictionary:
			_tasks.clear()
			return _failure("WORK_TASK_SNAPSHOT_INVALID")
		var task_value := value as Dictionary
		if (
			String(task_value.get("sourceKind", "")) in [
				"stock_below_threshold",
				"finished_food_below_threshold",
			]
			or String(task_value.get("sourceRef", ""))
			== "market-general-goods-restock"
		):
			# These tasks came from the retired finite-base-inventory model.
			# Dropping them prevents an old save from recreating a restock loop.
			continue
		var base_spec: Dictionary = {}
		for field: String in TASK_FIELDS:
			if not task_value.has(field):
				_tasks.clear()
				return _failure("WORK_TASK_SNAPSHOT_INVALID")
			base_spec[field] = task_value.get(field)
		var task_validation := create_task(base_spec)
		if not bool(task_validation.get("ok", false)):
			_tasks.clear()
			return _failure("WORK_TASK_SNAPSHOT_INVALID")
		var normalized := (
			task_validation.get("task", {}) as Dictionary
		)
		for state_field: String in [
			"eligibleOccupationIds",
			"state",
			"revision",
			"assignedResidentId",
			"assignedOccupationId",
			"waitReason",
			"result",
		]:
			if not task_value.has(state_field):
				_tasks.clear()
				return _failure("WORK_TASK_SNAPSHOT_INVALID")
			normalized[state_field] = (
				(task_value.get(state_field) as Dictionary).duplicate(true)
				if task_value.get(state_field) is Dictionary
				else (
					(task_value.get(state_field) as Array).duplicate(true)
					if task_value.get(state_field) is Array
					else task_value.get(state_field)
				)
			)
		normalized["eligibleResidentIds"] = (
			(task_value.get("eligibleResidentIds", []) as Array).duplicate()
			if task_value.get("eligibleResidentIds", []) is Array
			else []
		)
		normalized["processStage"] = String(
			task_value.get("processStage", "ready"),
		)
		normalized["processFacts"] = (
			(task_value.get("processFacts", {}) as Dictionary).duplicate(true)
			if task_value.get("processFacts", {}) is Dictionary
			else {}
		)
		normalized["terminalSequence"] = int(
			task_value.get("terminalSequence", 0),
		)
		if (
			not task_value.has("processStage")
			and String(normalized.get("sourceKind", ""))
			== "resident_message"
		):
			normalized["processStage"] = "out_for_delivery"
			normalized["processFacts"] = {
				"messageId": String(normalized.get("sourceRef", "")),
				"nextActivityId": "__resident_delivery__",
			}
		var task_id := String(normalized.get("taskId", ""))
		if (
			restored.has(task_id)
			or String(normalized.get("state", ""))
			not in [
				"open",
				"offered",
				"accepted",
				"in_progress",
				"waiting",
				"completed",
				"failed",
				"cancelled",
			]
			or typeof(normalized.get("revision")) != TYPE_INT
			or int(normalized.get("revision", 0)) < 1
		):
			_tasks.clear()
			return _failure("WORK_TASK_SNAPSHOT_INVALID")
		restored[task_id] = normalized
		_tasks.erase(task_id)
	_tasks = restored
	_restore_terminal_sequences()
	_compact_terminal_tasks()
	return {
		"ok": true,
		"errorCode": "",
		"taskCount": _tasks.size(),
	}


func open_tasks_for_occupation(
	occupation_id: String,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task_id_value: Variant in _tasks:
		var value := _tasks.get(task_id_value, {}) as Dictionary
		if (
			String(value.get("state", "")) in ["open", "waiting"]
			and (value.get("eligibleOccupationIds", []) as Array).has(
				occupation_id,
			)
		):
			result.append(value.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("priority", 0)) != int(b.get("priority", 0)):
			return int(a.get("priority", 0)) > int(b.get("priority", 0))
		return String(a.get("taskId", "")) < String(b.get("taskId", ""))
	)
	return result


func tasks_for_occupation(
	occupation_id: String,
	resident_id := "",
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for task_id_value: Variant in _tasks:
		var value := _tasks.get(task_id_value, {}) as Dictionary
		if (
			String(value.get("state", "")) in TERMINAL_STATES
			or not (
				value.get("eligibleOccupationIds", []) as Array
			).has(occupation_id)
		):
			continue
		var assigned_id := String(
			value.get("assignedResidentId", ""),
		)
		if not assigned_id.is_empty() and assigned_id != resident_id:
			continue
		result.append(value.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("priority", 0)) != int(b.get("priority", 0)):
			return int(a.get("priority", 0)) > int(b.get("priority", 0))
		return String(a.get("taskId", "")) < String(b.get("taskId", ""))
	)
	return result


func tasks_for_resident(resident_id: String) -> Array[Dictionary]:
	var normalized_resident := resident_id.strip_edges()
	var result: Array[Dictionary] = []
	if normalized_resident.is_empty():
		return result
	for task_id_value: Variant in _tasks:
		var value := _tasks.get(task_id_value, {}) as Dictionary
		if (
			String(value.get("state", "")) in TERMINAL_STATES
			or not (value.get("eligibleResidentIds", []) as Array).has(
				normalized_resident,
			)
		):
			continue
		var assigned_id := String(value.get("assignedResidentId", ""))
		if not assigned_id.is_empty() and assigned_id != normalized_resident:
			continue
		result.append(value.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("priority", 0)) != int(b.get("priority", 0)):
			return int(a.get("priority", 0)) > int(b.get("priority", 0))
		return String(a.get("taskId", "")) < String(b.get("taskId", ""))
	)
	return result


func tasks_for_activity(
	occupation_id: String,
	activity_id: String,
	resident_id := "",
) -> Array[Dictionary]:
	var capabilities := capabilities_for_activity(activity_id)
	if capabilities.is_empty():
		return []
	var result: Array[Dictionary] = []
	for task_id_value: Variant in _tasks:
		var value := _tasks.get(task_id_value, {}) as Dictionary
		if (
			not capabilities.has(String(value.get("capability", "")))
			or not (
				value.get("eligibleOccupationIds", []) as Array
			).has(occupation_id)
			or String(value.get("state", ""))
			not in ["open", "accepted", "in_progress", "waiting"]
		):
			continue
		if not _task_allows_activity(value, activity_id):
			continue
		var assigned_id := String(
			value.get("assignedResidentId", ""),
		)
		if not assigned_id.is_empty() and assigned_id != resident_id:
			continue
		result.append(value.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("priority", 0)) != int(b.get("priority", 0)):
			return int(a.get("priority", 0)) > int(b.get("priority", 0))
		return String(a.get("taskId", "")) < String(b.get("taskId", ""))
	)
	return result


func capabilities_for_activity(activity_id: String) -> Array[String]:
	return CHAIN_CATALOG.capabilities_for_activity(
		_catalog,
		activity_id,
	)


func _task_allows_activity(task_value: Dictionary, activity_id: String) -> bool:
	var next_activity_id := String(
		(task_value.get("processFacts", {}) as Dictionary).get(
			"nextActivityId",
			"",
		),
	)
	return next_activity_id.is_empty() or next_activity_id == activity_id


func service_binding_for(place_id: String) -> Dictionary:
	return CHAIN_CATALOG.service_binding_for(
		_catalog,
		place_id,
	)


func claim_task_for_activity(
	occupation_id: String,
	activity_id: String,
	resident_id: String,
) -> Dictionary:
	var candidates := tasks_for_activity(
		occupation_id,
		activity_id,
		resident_id,
	)
	if candidates.is_empty():
		return _failure("WORK_TASK_NOT_AVAILABLE")
	var selected := candidates[0] as Dictionary
	var task_id := String(selected.get("taskId", ""))
	var state := String(selected.get("state", ""))
	var revision := int(selected.get("revision", 0))
	if state in ["open", "waiting"]:
		var accepted := accept_task(
			task_id,
			resident_id,
			occupation_id,
			revision,
		)
		if not bool(accepted.get("ok", false)):
			return accepted
		selected = accepted.get("task", {}) as Dictionary
		state = "accepted"
		revision = int(selected.get("revision", 0))
	if state == "accepted":
		return start_task(task_id, resident_id, revision)
	if state == "in_progress":
		return _success(selected)
	return _failure("WORK_TASK_STATE_INVALID")


func _task_for_update(
	task_id: String,
	expected_revision: int,
) -> Dictionary:
	if not _tasks.has(task_id):
		return {}
	var task := (_tasks.get(task_id, {}) as Dictionary).duplicate(true)
	if (
		int(task.get("revision", 0)) != expected_revision
		or String(task.get("state", "")) in TERMINAL_STATES
	):
		return {}
	return task


func _task_update_failure(
	task_id: String,
	expected_revision: int,
) -> Dictionary:
	if not _tasks.has(task_id):
		return _failure("WORK_TASK_NOT_FOUND")
	var task := _tasks.get(task_id, {}) as Dictionary
	if String(task.get("state", "")) in TERMINAL_STATES:
		return _failure("WORK_TASK_ALREADY_TERMINAL")
	if int(task.get("revision", 0)) != expected_revision:
		return _failure("WORK_TASK_REVISION_STALE")
	return _failure("WORK_TASK_STATE_INVALID")


func _commit_task(task: Dictionary) -> void:
	task["revision"] = int(task.get("revision", 0)) + 1
	_tasks[String(task.get("taskId", ""))] = task
	task_committed.emit(task.duplicate(true))


func _commit_terminal_task(task: Dictionary) -> void:
	_terminal_sequence += 1
	task["terminalSequence"] = _terminal_sequence
	_commit_task(task)
	_compact_terminal_tasks()


func _restore_terminal_sequences() -> void:
	var terminal_tasks: Array[Dictionary] = []
	for task_value: Variant in _tasks.values():
		var task := task_value as Dictionary
		if String(task.get("state", "")) not in TERMINAL_STATES:
			continue
		terminal_tasks.append(task)
		_terminal_sequence = maxi(
			_terminal_sequence,
			int(task.get("terminalSequence", 0)),
		)
	terminal_tasks.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if int(left.get("createdAtMinute", 0)) != int(
				right.get("createdAtMinute", 0),
			):
				return int(left.get("createdAtMinute", 0)) < int(
					right.get("createdAtMinute", 0),
				)
			return String(left.get("taskId", "")) < String(
				right.get("taskId", ""),
			)
	)
	for task: Dictionary in terminal_tasks:
		if int(task.get("terminalSequence", 0)) > 0:
			continue
		_terminal_sequence += 1
		task["terminalSequence"] = _terminal_sequence
		_tasks[String(task.get("taskId", ""))] = task


func _compact_terminal_tasks() -> void:
	var terminal_tasks: Array[Dictionary] = []
	for task_value: Variant in _tasks.values():
		var task := task_value as Dictionary
		if String(task.get("state", "")) in TERMINAL_STATES:
			terminal_tasks.append(task)
	if terminal_tasks.size() <= MAX_TERMINAL_TASKS:
		return
	terminal_tasks.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if int(left.get("terminalSequence", 0)) != int(
				right.get("terminalSequence", 0),
			):
				return int(left.get("terminalSequence", 0)) > int(
					right.get("terminalSequence", 0),
				)
			return String(left.get("taskId", "")) > String(
				right.get("taskId", ""),
			)
	)
	for index in range(MAX_TERMINAL_TASKS, terminal_tasks.size()):
		_tasks.erase(String(terminal_tasks[index].get("taskId", "")))


func _success(task_value: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"task": task_value.duplicate(true),
	}


func _failure(
	error_code: String,
	extra: Dictionary = {},
) -> Dictionary:
	var result := {
		"ok": false,
		"errorCode": error_code,
	}
	result.merge(extra, true)
	return result


func _exact_keys(
	value: Dictionary,
	expected: Array,
) -> bool:
	return WORLD_SCALARS.exact_keys_sorted(value, expected)
