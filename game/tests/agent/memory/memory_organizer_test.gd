extends "res://tests/agent/support/AgentTestCase.gd"


const MEMORY_SYSTEM_PATH := "res://agent/memory/ResidentMemorySystem.gd"
const MEMORY_ORGANIZER_PATH := "res://agent/memory/MemoryOrganizer.gd"
const MEMORY_STORE_PATH := "res://agent/memory/ResidentMemoryStore.gd"
const TestData := preload("res://tests/support/AgentMemoryTestData.gd")

var _test_root := "user://tests/agent/memory-organizer/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	_test_four_new_wakes_trigger_full_memory_overwrite()
	_test_open_conversation_delays_batch_organization()
	_test_day_change_organizes_pending_evidence()
	_test_stale_organization_cannot_overwrite_newer_evidence()
	_test_organizer_renders_names_and_can_request_capacity_retry()
	_test_organizer_request_failure_does_not_block_context()
	_finish_suite("MEMORY-ORGANIZER_PASS", [_test_root])


func _test_four_new_wakes_trigger_full_memory_overwrite() -> void:
	var system := _new_memory_system("organization")
	var preparation: Dictionary = {}
	for index in range(4):
		preparation = system.call("prepare_context", _event_wake(index)) as Dictionary
		_expect_ok(preparation, "evidence wake prepares resident context")
		if index < 3:
			_expect_equal(
				preparation.has("organization_request"),
				false,
				"fewer than four new queue items do not trigger organization",
			)
	_expect(preparation.has("organization_request"), "fourth new queue item triggers organization")
	var organized := TestData.organized_memory()
	organized["important_memories"] = (
		"唐小满（resident-tang-xiao-man）今天来到我附近。"
	)
	organized["relationships"] = ""
	_expect_ok(
		system.call(
			"accept_organization",
			preparation.get("organization_token"),
			organized,
		),
		"valid organizer output replaces the full memory",
	)
	var snapshot := system.call("get_debug_snapshot") as Dictionary
	_expect_equal(snapshot.get("memory"), organized, "organized memory is the complete replacement")
	_expect_equal(snapshot.get("evidence_item_count"), 4, "successful organization keeps rolling evidence")
	var snapshot_only := TestData.wake_packet("snapshot-only")
	var next := system.call("prepare_context", snapshot_only) as Dictionary
	_expect_equal(
		next.has("organization_request"),
		false,
		"same queue is not organized again without a trigger",
	)

func _test_open_conversation_delays_batch_organization() -> void:
	var system := _new_memory_system("open-conversation")
	var preparation: Dictionary = {}
	for index in range(4):
		var wake := _event_wake(20 + index)
		wake["snapshot"]["conversation"] = {
			"conversation_id": "conversation-open",
			"with_resident_id": "resident-tang-xiao-man",
			"with": "唐小满",
			"turns": [],
		}
		preparation = system.call("prepare_context", wake) as Dictionary
		_expect_ok(preparation, "open conversation evidence is retained")
	_expect_equal(
		preparation.has("organization_request"),
		false,
		"batch threshold does not organize while a conversation is open",
	)
	var end_wake := TestData.wake_packet("conversation-ended")
	end_wake["events"] = [{
		"event_id": "conversation-ended",
		"time": {"day": 1, "clock": "08:30", "period": "上午"},
		"type": "对话结束",
		"conversation_id": "conversation-open",
		"turns": [],
		"reason": "主动结束",
	}]
	var ended := system.call("prepare_context", end_wake) as Dictionary
	_expect_ok(ended, "conversation end evidence prepares")
	_expect(
		ended.has("organization_request"),
		"confirmed conversation end releases the delayed organization",
	)

func _test_day_change_organizes_pending_evidence() -> void:
	var system := _new_memory_system("day-change")
	var first := system.call("prepare_context", _event_wake(30, 1)) as Dictionary
	_expect_ok(first, "first-day evidence prepares")
	_expect_equal(
		first.has("organization_request"),
		false,
		"one evidence item does not meet the batch threshold",
	)
	var next_day := system.call(
		"prepare_context",
		TestData.wake_packet("next-day", 2),
	) as Dictionary
	_expect_ok(next_day, "next-day snapshot prepares")
	_expect(
		next_day.has("organization_request"),
		"crossing a game day organizes pending evidence without storing the snapshot-only wake",
	)
	var snapshot := system.call("get_debug_snapshot") as Dictionary
	_expect_equal(snapshot.get("evidence_item_count"), 1, "snapshot-only wake does not enter evidence")

func _test_stale_organization_cannot_overwrite_newer_evidence() -> void:
	var system := _new_memory_system("stale-organization")
	var preparation: Dictionary = {}
	for index in range(4):
		preparation = system.call("prepare_context", _event_wake(40 + index)) as Dictionary
	_expect(preparation.has("organization_token"), "batch produces an organization token")
	_expect_ok(
		system.call("prepare_context", _event_wake(44)),
		"new evidence arrives while an older organization is pending",
	)
	var acceptance := system.call(
		"accept_organization",
		preparation.get("organization_token"),
		TestData.organized_memory(),
	) as Dictionary
	_expect_equal(acceptance.get("ok"), false, "stale organization result is rejected")
	_expect_equal(acceptance.get("safe_to_continue"), true, "stale result is safe to ignore")
	_expect_equal(
		(system.call("get_debug_snapshot") as Dictionary).get("memory"),
		TestData.empty_memory(),
		"stale organization cannot overwrite resident memory",
	)

func _test_organizer_renders_names_and_can_request_capacity_retry() -> void:
	var root := _test_root.path_join("organizer")
	var store: RefCounted = (load(MEMORY_STORE_PATH) as Script).new(
		root.path_join("resident_memory.json"),
	)
	var organizer: RefCounted = (load(MEMORY_ORGANIZER_PATH) as Script).new(
		TestData.initialization(),
		store,
	)
	var items := [{
		"wake_packet": _event_wake(4),
		"matched_intents": [],
	}]
	var request := organizer.call("build_request", TestData.empty_memory(), items) as Dictionary
	_expect_ok(request, "organizer builds a request from the rolling queue")
	var messages := request.get("messages", []) as Array
	if messages.size() == 2:
		var text := "%s\n%s" % [
			String((messages[0] as Dictionary).get("content", "")),
			_message_text((messages[1] as Dictionary).get("content")),
		]
		_expect(text.contains("林岚") and text.contains("唐小满"), "organizer prompt uses names")
		_expect(
			text.contains("resident-lin-lan")
			and text.contains("resident-tang-xiao-man")
			and text.contains("event-4"),
			"organizer prompt preserves world identity and source ids",
		)
	var too_long := TestData.empty_memory()
	too_long["important_memories"] = "记".repeat(2401)
	var validation := organizer.call("validate_candidate", too_long) as Dictionary
	_expect_equal(validation.get("retryable"), true, "organizer exposes capacity retry")
	var retry := organizer.call(
		"build_retry_request",
		TestData.empty_memory(),
		items,
		validation,
	) as Dictionary
	_expect_ok(retry, "organizer builds one compression retry")
	if (retry.get("messages", []) as Array).size() == 2:
		_expect(
			_message_text(((retry["messages"] as Array)[1] as Dictionary).get("content"))
				.contains("important_memories"),
			"retry identifies the overflowing field",
		)

func _test_organizer_request_failure_does_not_block_context() -> void:
	var system := _new_memory_system("organizer-request-failure")
	var wake := TestData.wake_packet("photo-conversation-end")
	wake["events"] = [{
		"event_id": "photo-conversation-end",
		"time": {"day": 1, "clock": "08:20", "period": "上午"},
		"type": "对话结束",
		"conversation_id": "conversation-photo",
		"turns": [{
			"turn_id": 1,
			"speaker_resident_id": "resident-tang-xiao-man",
			"speaker": "唐小满",
			"say": "看看这张照片。",
			"narration": "",
			"photos": [{"ref": "photo-without-resolver", "mime_type": "image/png"}],
		}],
		"reason": "主动结束",
	}]
	var preparation := system.call("prepare_context", wake) as Dictionary
	_expect_ok(preparation, "organizer request failure keeps the decision context usable")
	_expect(
		not preparation.has("organization_request"),
		"failed organizer request is not sent to the model",
	)
	var snapshot := system.call("get_debug_snapshot") as Dictionary
	_expect_equal(
		snapshot.get("last_update", {}).get("status"),
		"organization_error",
		"organizer request failure remains visible to debug",
	)
	_expect_equal(snapshot.get("evidence_item_count"), 1, "failed organizer request keeps evidence")

func _new_memory_system(suffix: String) -> RefCounted:
	return (load(MEMORY_SYSTEM_PATH) as Script).new(
		TestData.initialization(),
		_test_root.path_join(suffix),
	)

func _event_wake(index: int, day: int = 1) -> Dictionary:
	return TestData.event_wake(
		"wake-%d" % index,
		"event-%d" % index,
		day,
		"有人走了",
		"08:%02d" % (index % 60),
	)

func _message_text(content: Variant) -> String:
	if typeof(content) == TYPE_STRING:
		return String(content)
	if typeof(content) != TYPE_ARRAY:
		return ""
	for part_value: Variant in content as Array:
		if typeof(part_value) != TYPE_DICTIONARY:
			continue
		var part := part_value as Dictionary
		if part.get("type") == "text":
			return String(part.get("text", ""))
	return ""


func _finalize() -> void:
	_BaseUserTestDataCleaner.remove_tree(_test_root)
