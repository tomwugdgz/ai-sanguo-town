extends "res://tests/support/TownWorldTestCase.gd"


const STORE := preload("res://world/runtime/log/TownWorldLogStore.gd")
const TOWN_LOG_PANEL := preload("res://ui/town_log/TownLogPanel.gd")


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_death_log_title()
	_test_announcement_summary()
	_finish_suite("TOWN_DEATH_LOG_PRESENTATION_PASS")


func _test_death_log_title() -> void:
	var store: RefCounted = STORE.new()
	_expect_ok(store.call("reset", "death-log-presentation"), "death log reset")
	var source := {
		"eventId": "evt-death-log",
		"kind": "world_event",
		"time": {"day": 3, "hour": 10, "minute": 0},
		"worldRevision": 20,
		"residentId": "resident-a",
		"residentName": "",
		"placeName": "独立市集",
		"payload": {
			"type": "居民死亡",
			"deceased_resident_id": "resident-a",
			"deceased_resident_name": "林岚",
			"reason": "突发疾病",
		},
	}
	_expect_ok(
		store.call("append_public_event", source),
		"death event enters the world log",
	)
	var rows := (store.call("query_threads", {}) as Dictionary).get(
		"rows",
		[],
	) as Array
	_expect_equal(rows.size(), 1, "death event creates one log thread")
	if rows.size() == 1:
		_expect_equal(
			String((rows[0] as Dictionary).get("title", "")),
			"林岚去世：突发疾病",
			"death log title keeps the deceased name and reason",
		)


func _test_announcement_summary() -> void:
	var panel: Control = TOWN_LOG_PANEL.new()
	var summary := String(panel.call(
		"_record_process_summary",
		{
			"title": "公告发布",
			"payload": {
				"type": "公告发布",
				"text": "林岚于第3天10:00死亡。",
				"reason": "突发疾病",
			},
		},
		false,
	))
	_expect_equal(
		summary,
		"公告发布 · 林岚于第3天10:00死亡。 · 原因：突发疾病",
		"announcement log summary keeps its text and reason",
	)
	panel.free()


func _expect_ok(value: Variant, label: String) -> void:
	_expect(
		value is Dictionary and (value as Dictionary).get("ok") == true,
		"%s ok expected, got %s" % [label, value],
	)
