class_name TownResidentSleepRuntime
extends RefCounted


const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const MIN_EFFECTIVE_SLEEP_MINUTES := 90
const FULL_SLEEP_MINUTES := 360
const MAX_COMPLETED_RESULTS_PER_RESIDENT := 32
const ACTIVE_SLEEP_FIELDS: Array[String] = [
	"actionId",
	"startedAtMinute",
	"plannedDurationMinutes",
]
const SLEEP_RESULT_FIELDS: Array[String] = [
	"actionId",
	"startedAtMinute",
	"completedAtMinute",
	"plannedDurationMinutes",
	"actualSleepMinutes",
	"interrupted",
	"endReason",
	"classification",
	"wakeEligible",
]
const RESIDENT_FIELDS: Array[String] = [
	"residentId",
	"activeSleep",
	"completedSleepResults",
	"completedOrder",
	"revision",
]


var _residents: Dictionary = {}


func initialize_resident(resident_id: String) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty() or _residents.has(normalized_id):
		return _failure("SLEEP_RESIDENT_ID_INVALID")
	_residents[normalized_id] = {
		"residentId": normalized_id,
		"activeSleep": {},
		"completedSleepResults": {},
		"completedOrder": [],
		"revision": 1,
	}
	return _success(normalized_id, {"created": true})


func reset_resident(resident_id: String) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if not _residents.has(normalized_id):
		return _failure("SLEEP_RESIDENT_UNKNOWN")
	_residents.erase(normalized_id)
	return initialize_resident(normalized_id)


func has_resident(resident_id: String) -> bool:
	return _residents.has(resident_id)


func resident_ids() -> Array[String]:
	var result: Array[String] = []
	for resident_id_value: Variant in _residents:
		result.append(String(resident_id_value))
	result.sort()
	return result


func start_sleep(
	resident_id: String,
	action_id: String,
	started_at_minute: int,
	planned_duration_minutes: int,
) -> Dictionary:
	var resident := _residents.get(resident_id, {}) as Dictionary
	if resident.is_empty():
		return _failure("SLEEP_RESIDENT_UNKNOWN")
	var normalized_action_id := action_id.strip_edges()
	if (
		normalized_action_id.is_empty()
		or started_at_minute < 0
		or planned_duration_minutes <= 0
	):
		return _failure("SLEEP_START_INVALID")
	var completed := resident.get("completedSleepResults", {}) as Dictionary
	if completed.has(normalized_action_id):
		return _failure("SLEEP_ACTION_ALREADY_COMPLETED")
	var active := resident.get("activeSleep", {}) as Dictionary
	if not active.is_empty():
		if String(active.get("actionId", "")) == normalized_action_id:
			return _success(
				resident_id,
				{
					"started": false,
					"duplicate": true,
					"activeSleep": active.duplicate(true),
				},
			)
		return _failure("SLEEP_ALREADY_ACTIVE")
	active = {
		"actionId": normalized_action_id,
		"startedAtMinute": started_at_minute,
		"plannedDurationMinutes": planned_duration_minutes,
	}
	resident["activeSleep"] = active
	resident["revision"] = int(resident.get("revision", 0)) + 1
	_residents[resident_id] = resident
	return _success(
		resident_id,
		{
			"started": true,
			"duplicate": false,
			"activeSleep": active.duplicate(true),
		},
	)


func finish_sleep(
	resident_id: String,
	action_id: String,
	completed_at_minute: int,
	interrupted: bool,
	end_reason: String,
) -> Dictionary:
	var resident := _residents.get(resident_id, {}) as Dictionary
	if resident.is_empty():
		return _failure("SLEEP_RESIDENT_UNKNOWN")
	var normalized_action_id := action_id.strip_edges()
	var normalized_reason := end_reason.strip_edges()
	if (
		normalized_action_id.is_empty()
		or completed_at_minute < 0
		or normalized_reason.is_empty()
	):
		return _failure("SLEEP_FINISH_INVALID")
	var completed := resident.get("completedSleepResults", {}) as Dictionary
	if completed.has(normalized_action_id):
		return _success(
			resident_id,
			{
				"finished": false,
				"duplicate": true,
				"sleepResult": (
					completed.get(normalized_action_id, {}) as Dictionary
				).duplicate(true),
			},
		)
	var active := resident.get("activeSleep", {}) as Dictionary
	if (
		active.is_empty()
		or String(active.get("actionId", "")) != normalized_action_id
	):
		return _failure("SLEEP_ACTION_NOT_ACTIVE")
	var started_at := int(active.get("startedAtMinute", -1))
	if completed_at_minute < started_at:
		return _failure("SLEEP_FINISH_BEFORE_START")
	var actual_minutes := completed_at_minute - started_at
	var classification := _classify_sleep(actual_minutes, interrupted)
	var result := {
		"actionId": normalized_action_id,
		"startedAtMinute": started_at,
		"completedAtMinute": completed_at_minute,
		"plannedDurationMinutes": int(
			active.get("plannedDurationMinutes", 0),
		),
		"actualSleepMinutes": actual_minutes,
		"interrupted": interrupted,
		"endReason": normalized_reason,
		"classification": classification,
		"wakeEligible": actual_minutes >= MIN_EFFECTIVE_SLEEP_MINUTES,
	}
	completed[normalized_action_id] = result.duplicate(true)
	var completed_order := resident.get("completedOrder", []) as Array
	completed_order.append(normalized_action_id)
	while completed_order.size() > MAX_COMPLETED_RESULTS_PER_RESIDENT:
		var expired_id := String(completed_order.pop_front())
		completed.erase(expired_id)
	resident["activeSleep"] = {}
	resident["completedSleepResults"] = completed
	resident["completedOrder"] = completed_order
	resident["revision"] = int(resident.get("revision", 0)) + 1
	_residents[resident_id] = resident
	return _success(
		resident_id,
		{
			"finished": true,
			"duplicate": false,
			"sleepResult": result.duplicate(true),
		},
	)


func get_active_sleep(resident_id: String) -> Dictionary:
	var resident := _residents.get(resident_id, {}) as Dictionary
	return (resident.get("activeSleep", {}) as Dictionary).duplicate(true)


func get_completed_sleep_result(
	resident_id: String,
	action_id: String,
) -> Dictionary:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var completed := resident.get("completedSleepResults", {}) as Dictionary
	return (completed.get(action_id, {}) as Dictionary).duplicate(true)


func get_resident_revision(resident_id: String) -> int:
	return int(
		(_residents.get(resident_id, {}) as Dictionary).get("revision", 0),
	)


func create_save_snapshot() -> Dictionary:
	return {
		"schemaVersion": 1,
		"residents": _residents.duplicate(true),
	}


func restore_from_snapshot(snapshot: Dictionary) -> Dictionary:
	var errors := _validate_snapshot(snapshot)
	if not errors.is_empty():
		return _failure("SLEEP_SNAPSHOT_INVALID", {"errors": errors})
	_residents = (snapshot.get("residents", {}) as Dictionary).duplicate(true)
	return {
		"ok": true,
		"errorCode": "",
		"residentCount": _residents.size(),
	}


func _classify_sleep(actual_minutes: int, interrupted: bool) -> String:
	if actual_minutes < MIN_EFFECTIVE_SLEEP_MINUTES:
		return "brief_rest"
	if actual_minutes >= FULL_SLEEP_MINUTES and not interrupted:
		return "full_sleep"
	return "effective_sleep"


func _validate_snapshot(snapshot: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _exact_keys(snapshot, ["schemaVersion", "residents"]):
		errors.append("睡眠存档字段不完整或包含未知字段")
	if snapshot.get("schemaVersion") != 1:
		errors.append("睡眠存档版本无效")
	if not snapshot.get("residents") is Dictionary:
		errors.append("睡眠居民存档必须是对象")
		return errors
	for resident_id_value: Variant in snapshot.get("residents", {}) as Dictionary:
		var resident_id := String(resident_id_value)
		var resident_value: Variant = (
			snapshot.get("residents", {}) as Dictionary
		).get(resident_id_value)
		if not resident_value is Dictionary:
			errors.append("睡眠居民存档无效：%s" % resident_id)
			continue
		_validate_resident_snapshot(
			resident_id,
			resident_value as Dictionary,
			errors,
		)
	return errors


func _validate_resident_snapshot(
	resident_id: String,
	resident: Dictionary,
	errors: Array[String],
) -> void:
	if not _exact_keys(resident, RESIDENT_FIELDS):
		errors.append("睡眠居民字段无效：%s" % resident_id)
	if resident_id.is_empty() or String(resident.get("residentId", "")) != resident_id:
		errors.append("睡眠居民编号不一致：%s" % resident_id)
	if typeof(resident.get("revision")) != TYPE_INT or int(
		resident.get("revision", 0),
	) < 1:
		errors.append("睡眠居民修订号无效：%s" % resident_id)
	var active_value: Variant = resident.get("activeSleep")
	if not active_value is Dictionary:
		errors.append("当前睡眠必须是对象：%s" % resident_id)
	else:
		var active := active_value as Dictionary
		if not active.is_empty() and not _valid_active_sleep(active):
			errors.append("当前睡眠记录无效：%s" % resident_id)
	var completed_value: Variant = resident.get("completedSleepResults")
	var order_value: Variant = resident.get("completedOrder")
	if not completed_value is Dictionary or not order_value is Array:
		errors.append("已完成睡眠索引无效：%s" % resident_id)
		return
	var completed := completed_value as Dictionary
	var order := order_value as Array
	if order.size() > MAX_COMPLETED_RESULTS_PER_RESIDENT:
		errors.append("已完成睡眠记录超过上限：%s" % resident_id)
	var seen: Dictionary = {}
	for action_id_value: Variant in order:
		if not action_id_value is String:
			errors.append("已完成睡眠顺序编号无效：%s" % resident_id)
			continue
		var action_id := String(action_id_value)
		if action_id.is_empty() or seen.has(action_id) or not completed.has(action_id):
			errors.append("已完成睡眠顺序不一致：%s" % resident_id)
			continue
		seen[action_id] = true
		var result_value: Variant = completed.get(action_id)
		if not result_value is Dictionary or not _valid_sleep_result(
			result_value as Dictionary,
			action_id,
		):
			errors.append("已完成睡眠结果无效：%s" % resident_id)
	for action_id_value: Variant in completed:
		if not seen.has(String(action_id_value)):
			errors.append("已完成睡眠存在未索引结果：%s" % resident_id)


func _valid_active_sleep(active: Dictionary) -> bool:
	return (
		_exact_keys(active, ACTIVE_SLEEP_FIELDS)
		and not String(active.get("actionId", "")).strip_edges().is_empty()
		and typeof(active.get("startedAtMinute")) == TYPE_INT
		and int(active.get("startedAtMinute", -1)) >= 0
		and typeof(active.get("plannedDurationMinutes")) == TYPE_INT
		and int(active.get("plannedDurationMinutes", 0)) > 0
	)


func _valid_sleep_result(result: Dictionary, action_id: String) -> bool:
	if not _exact_keys(result, SLEEP_RESULT_FIELDS):
		return false
	var started_at_value: Variant = result.get("startedAtMinute")
	var completed_at_value: Variant = result.get("completedAtMinute")
	var planned_value: Variant = result.get("plannedDurationMinutes")
	var actual_value: Variant = result.get("actualSleepMinutes")
	if (
		String(result.get("actionId", "")) != action_id
		or typeof(started_at_value) != TYPE_INT
		or typeof(completed_at_value) != TYPE_INT
		or typeof(planned_value) != TYPE_INT
		or typeof(actual_value) != TYPE_INT
		or int(started_at_value) < 0
		or int(completed_at_value) < int(started_at_value)
		or int(planned_value) <= 0
		or int(actual_value) != int(completed_at_value) - int(started_at_value)
		or typeof(result.get("interrupted")) != TYPE_BOOL
		or String(result.get("endReason", "")).strip_edges().is_empty()
		or typeof(result.get("wakeEligible")) != TYPE_BOOL
	):
		return false
	var expected_classification := _classify_sleep(
		int(actual_value),
		bool(result.get("interrupted", false)),
	)
	return (
		String(result.get("classification", "")) == expected_classification
		and bool(result.get("wakeEligible", false))
		== (int(actual_value) >= MIN_EFFECTIVE_SLEEP_MINUTES)
	)


func _exact_keys(value: Dictionary, expected: Array) -> bool:
	return WORLD_SCALARS.exact_keys(value, expected)


func _success(resident_id: String, payload: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"errorCode": "",
		"residentId": resident_id,
	}
	result.merge(payload, true)
	return result


func _failure(error_code: String, payload: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"errorCode": error_code,
	}
	result.merge(payload, true)
	return result
