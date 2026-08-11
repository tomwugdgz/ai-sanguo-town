class_name TownAgentWakeStateRuntime
extends RefCounted


static func initial_state() -> Dictionary:
	return {
		"needsRefresh": false,
		"builtAbsoluteMinute": -1,
		"builtWeather": "",
	}


static func mark_built(
	resident: Dictionary,
	absolute_minute: int,
	weather: String,
) -> void:
	resident["pendingWakeState"] = {
		"needsRefresh": false,
		"builtAbsoluteMinute": absolute_minute,
		"builtWeather": weather,
	}


static func mark_dirty(resident: Dictionary) -> void:
	var state := resident.get("pendingWakeState", {}) as Dictionary
	state["needsRefresh"] = true
	resident["pendingWakeState"] = state


static func needs_refresh(
	resident: Dictionary,
	absolute_minute: int,
	weather: String,
) -> bool:
	var state := resident.get("pendingWakeState", {}) as Dictionary
	# 时间继续流逝不等于当前决定失效。排队中的居民只在真正影响
	# 决策的世界事实变化时标记 dirty；发给 Provider 前再由 Gateway
	# 触发一次最终刷新。
	return bool(state.get("needsRefresh", true))


static func preserved_social_results(pending_wake: Dictionary) -> Variant:
	if not pending_wake.has("snapshot"):
		return null
	return (
		pending_wake.get("social_response_results", []) as Array
	).duplicate(true)


static func normalized_resident_ids(
	resident_values: Array,
	residents: Dictionary,
	resident_id_by_name: Dictionary,
) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in resident_values:
		var normalized := String(value).strip_edges()
		var resident_id := (
			normalized
			if residents.has(normalized)
			else String(resident_id_by_name.get(normalized, ""))
		)
		if not resident_id.is_empty() and not result.has(resident_id):
			result.append(resident_id)
	return result
