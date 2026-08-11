class_name TownWorldLogStoryPolicy
extends RefCounted

const ROUTINE_ACTION_TYPES: Array[String] = [
	"去", "待着", "搭话", "答话", "做活动",
]
const ROUTINE_ACTION_VERBS: Array[String] = [
	"睡觉", "歇着", "休息", "吃饭", "喝水",
]


static func should_capture(payload: Dictionary) -> bool:
	var story_type := _text(payload.get("storyType", ""))
	if story_type == "action_outcome":
		if _text(payload.get("status", "")) != "completed":
			return false
		if _text(payload.get("actionType", "")) in ROUTINE_ACTION_TYPES:
			return false
		if _text(payload.get("verb", "")) in ROUTINE_ACTION_VERBS:
			return false
		return not story_root_event_ids(payload).is_empty()
	if story_type == "gathering_arrival":
		return not story_root_event_ids(payload).is_empty()
	return false


static func story_root_event_ids(payload: Dictionary) -> Array[String]:
	var raw: Variant = payload.get(
		"storyRootEventIds",
		payload.get("causedByEventIds", []),
	)
	var result: Array[String] = []
	if not raw is Array:
		return result
	for value: Variant in raw as Array:
		var root_id := _text(value)
		if not root_id.is_empty() and not result.has(root_id):
			result.append(root_id)
	return result


static func _text(value: Variant) -> String:
	return (value as String).strip_edges() if value is String else str(value).strip_edges()
