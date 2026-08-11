class_name TkTimelinePublisher
extends RefCounted


# 三国编年史自动布告发布器。
# 读取 tk_timeline.json，在对应游戏日把 bulletinText 推送到社区公告栏。
# 发布时间固定为当日 08:00（绝对分钟 = (day-1)*1440 + 480），确定性、可复现。
const TIMELINE_PATH := "res://world/data/town/tk_timeline.json"
const PUBLISHER_ID := "tk_chronicle"
const PUBLISH_MINUTE_OF_DAY := 480

var _events: Array = []
var _posted_event_ids: Dictionary = {}


func _init() -> void:
	_load_timeline()


func _load_timeline() -> void:
	_events = []
	if not FileAccess.file_exists(TIMELINE_PATH):
		return
	var text := FileAccess.get_file_as_string(TIMELINE_PATH)
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_events = parsed.get("events", []) as Array


func publish_due_for_day(world_runtime, bulletin_runtime, day: int) -> int:
	var posted := 0
	for event_value: Variant in _events:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event := event_value as Dictionary
		if int(event.get("gameDay", 0)) != day:
			continue
		var event_id := String(event.get("eventId", ""))
		var bulletin_text := String(event.get("bulletinText", "")).strip_edges()
		if bulletin_text.is_empty():
			continue
		# 幂等：已发布的事件编号直接跳过（二次安全网，即使公告栏去重失效）。
		if _posted_event_ids.has(event_id):
			continue
		# 幂等：公告栏里已存在相同正文则跳过（存档/重载后依然有效）。
		if _bulletin_already_has(bulletin_runtime, bulletin_text):
			_posted_event_ids[event_id] = true
			continue
		var published_at := (day - 1) * 1440 + PUBLISH_MINUTE_OF_DAY
		var result := bulletin_runtime.publish(
			PUBLISHER_ID,
			bulletin_text,
			"",
			published_at,
			{},
			"board",
			"",
			{},
		) as Dictionary
		if bool(result.get("ok", false)):
			posted += 1
			_posted_event_ids[event_id] = true
	return posted


func ensure_posted_upto(world_runtime, bulletin_runtime, day: int) -> int:
	var total := 0
	for d in range(1, day + 1):
		total += publish_due_for_day(world_runtime, bulletin_runtime, d)
	return total


func create_save_snapshot() -> Dictionary:
	return {
		"schema": "tk-timeline-publisher",
		"schema_version": 1,
		"posted_event_ids": _posted_event_ids.duplicate(true),
	}


func restore_save_snapshot(snapshot: Dictionary) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "存档不是对象"}
	var posted := snapshot.get("posted_event_ids", {}) as Dictionary
	if typeof(posted) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "posted_event_ids 字段无效"}
	for key: Variant in posted:
		_posted_event_ids[String(key)] = true
	return {"ok": true, "posted_count": _posted_event_ids.size()}


func _bulletin_already_has(bulletin_runtime, bulletin_text: String) -> bool:
	for announcement: Dictionary in bulletin_runtime.get_announcements(true):
		if String(announcement.get("text", "")).strip_edges() == bulletin_text:
			return true
	return false
