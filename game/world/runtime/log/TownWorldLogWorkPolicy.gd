class_name TownWorldLogWorkPolicy
extends RefCounted

const PLAYER_MEANINGFUL_WORK_CAPABILITIES: Array[String] = [
	"library.accession", "craft.production", "music.perform",
	"cafe.production", "food.production", "fishing.harvest",
	"garden.harvest", "research.handoff",
]
const POSTAL_WORK_CAPABILITIES: Array[String] = [
	"message.accept", "message.sort", "message.prepare", "message.deliver",
]
const INTERNAL_ROLLOVER_SOURCE_KINDS: Array[String] = [
	"daily_operation_plan", "daily_postal_collection_plan", "daily_catalog_plan",
	"catalog_mismatch", "daily_inventory_plan", "inventory_request",
	"production_request", "meal_demand", "fish_demand", "fishing_conditions",
	"plant_state", "flowering_state", "daily_baking_plan", "display_change",
	"follow_up_due", "personal_research_plan", "route", "weather_exposure",
	"place_event", "place_service_change",
]
const TERMINAL_STATUSES: Array[String] = [
	"failed", "cancelled", "canceled", "rejected", "expired",
]


static func request_failure_is_meaningful(payload: Dictionary) -> bool:
	# 只有带服务请求来源的失败才走"服务取消"旧文案；口信类任务由
	# LogStore 的 message.* 分支单独生成"口信投递已取消：原因"。
	return (
		not _request_id(payload).is_empty()
		and _status(payload) in TERMINAL_STATUSES
		and not _is_internal_rollover_cancellation(payload, _status(payload))
	)


static func should_capture(source: Dictionary, payload: Dictionary) -> bool:
	var status := _status(payload)
	if _text(payload.get("sourceKind")) == "staffing_matter":
		return false
	if _is_internal_rollover_cancellation(payload, status):
		return false
	if request_failure_is_meaningful(payload):
		return true
	if not _request_id(payload).is_empty():
		return false
	var capability := _text(payload.get("capability"))
	if capability in POSTAL_WORK_CAPABILITIES:
		return (
			not _text(payload.get("sourceRef")).is_empty()
			and not _participant_ids(source, payload).is_empty()
		)
	if status in ["open", "accepted", "in_progress", "waiting", "pending", "blocked"]:
		return false
	if status in TERMINAL_STATUSES:
		return (
			not _text(payload.get("taskId")).is_empty()
			and not _participant_ids(source, payload).is_empty()
		)
	if status != "completed":
		return false
	for field: String in [
		"cargoLotId", "cargo_lot_id", "messageId", "message_id",
		"matterId", "matter_id", "announcementId", "announcement_id",
		"conflictId", "conflict_id", "conditionId", "condition_id",
	]:
		if not _text(payload.get(field)).is_empty():
			return true
	return capability in PLAYER_MEANINGFUL_WORK_CAPABILITIES


static func _is_internal_rollover_cancellation(
	payload: Dictionary,
	status: String,
) -> bool:
	if status not in TERMINAL_STATUSES:
		return false
	var source_kind := _text(payload.get("sourceKind"))
	var reason := _text(payload.get("waitReason"))
	if source_kind in INTERNAL_ROLLOVER_SOURCE_KINDS:
		return true
	return (
		source_kind == "personal_performance_plan"
		and (
			reason.contains("排练计划已经结束")
			or reason.contains("演出日期已经过去")
		)
	)


static func _participant_ids(source: Dictionary, payload: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in [
		source.get("residentId", ""),
		payload.get("participantIds", []),
		payload.get("participant_resident_ids", []),
		payload.get("resident_ids", []),
	]:
		if value is Array:
			for nested: Variant in value as Array:
				_append_id(result, nested)
		else:
			_append_id(result, value)
	return result


static func _append_id(target: Array[String], value: Variant) -> void:
	var normalized := _text(value)
	if not normalized.is_empty() and not target.has(normalized):
		target.append(normalized)


static func _request_id(payload: Dictionary) -> String:
	return _text(payload.get("requestId", payload.get("request_id", "")))


static func _status(payload: Dictionary) -> String:
	return _text(payload.get("status", "")).to_lower()


static func _text(value: Variant) -> String:
	return (value as String).strip_edges() if value is String else str(value).strip_edges()
