extends "res://tests/agent/support/AgentTestCase.gd"


const EVIDENCE_QUEUE_PATH := "res://agent/memory/ResidentEvidenceQueue.gd"
const MEMORY_SYSTEM_PATH := "res://agent/memory/ResidentMemorySystem.gd"
const TestData := preload("res://tests/support/AgentMemoryTestData.gd")

var _test_root := "user://tests/agent/resident-evidence-queue/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	_test_evidence_queue_is_resident_private_fifo()
	_test_evidence_queue_deduplicates_world_sources()
	_test_world_revision_stays_integer_across_evidence_json_round_trip()
	_test_world_result_pairs_with_pending_intention()
	_test_equal_length_external_rewrite_is_detected()
	_finish_suite("RESIDENT-EVIDENCE-QUEUE_PASS", [_test_root])


func _test_equal_length_external_rewrite_is_detected() -> void:
	# 快路径比整文件 SHA-256：同一秒内、等长、且只改文件中段一个字节的
	# 外部改写也必须被发现（复核给出的最强对抗场景）。
	var path := _test_root.path_join(
		"equal-length/resident-lin-lan/world_evidence.json",
	)
	var queue: RefCounted = (load(EVIDENCE_QUEUE_PATH) as Script).new(path)
	_expect_ok(
		queue.call("append_wake", _event_wake(0), []),
		"equal-length rewrite fixture appends evidence",
	)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("equal-length rewrite fixture reads the queue file")
		return
	var original := file.get_as_text()
	file = null
	var tampered_bytes := original.to_utf8_buffer()
	var middle := tampered_bytes.size() / 2
	tampered_bytes[middle] = 88 if tampered_bytes[middle] != 88 else 89
	var writer := FileAccess.open(path, FileAccess.WRITE)
	if writer == null:
		_failures.append("equal-length rewrite fixture rewrites the queue file")
		return
	writer.store_buffer(tampered_bytes)
	writer.flush()
	writer = null
	var read_back := queue.call("read") as Dictionary
	_expect_equal(
		read_back.get("ok"),
		false,
		"same-mtime equal-length middle rewrite does not pass the fast path",
	)


func _test_evidence_queue_is_resident_private_fifo() -> void:
	var lin_path := _test_root.path_join(
		"fifo/resident-lin-lan/world_evidence.json",
	)
	var tang_path := _test_root.path_join(
		"fifo/resident-tang-xiao-man/world_evidence.json",
	)
	var lin_queue: RefCounted = (load(EVIDENCE_QUEUE_PATH) as Script).new(lin_path)
	var tang_queue: RefCounted = (load(EVIDENCE_QUEUE_PATH) as Script).new(tang_path)
	for index in range(17):
		_expect_ok(
			lin_queue.call("append_wake", _event_wake(index), []),
			"resident evidence wake appends",
		)
	var lin_items := (
		(lin_queue.call("read") as Dictionary).get("items", []) as Array
	)
	_expect_equal(
		lin_items.size(),
		17,
		"unorganized evidence stays intact until organization succeeds",
	)
	if lin_items.size() == 17:
		_expect_equal(
			((lin_items[0] as Dictionary)["wake_packet"] as Dictionary).get("decision_id"),
			"wake-0",
			"oldest unorganized evidence is retained",
		)
		_expect_equal(
			((lin_items[-1] as Dictionary)["wake_packet"] as Dictionary).get("decision_id"),
			"wake-16",
			"newest item stays at the queue tail",
		)
	_expect_ok(
		lin_queue.call("mark_organized"),
		"successful organization trims the rolling evidence queue",
	)
	lin_items = (
		(lin_queue.call("read") as Dictionary).get("items", []) as Array
	)
	_expect_equal(lin_items.size(), 16, "organized resident queue keeps sixteen items")
	if lin_items.size() == 16:
		_expect_equal(
			((lin_items[0] as Dictionary)["wake_packet"] as Dictionary).get("decision_id"),
			"wake-1",
			"organization evicts only the oldest item",
		)
	var evicted_duplicate := lin_queue.call(
		"append_wake",
		_event_wake(0),
		[],
	) as Dictionary
	_expect_equal(
		evicted_duplicate.get("added"),
		false,
		"source remains deduplicated after its queue item is evicted",
	)
	var queue_capture := lin_queue.call("capture_state") as Dictionary
	var restored_queue: RefCounted = (load(EVIDENCE_QUEUE_PATH) as Script).new(
		_test_root.path_join("fifo/restored/world_evidence.json"),
	)
	_expect_ok(
		restored_queue.call("apply_state", queue_capture.get("queue_state")),
		"dedupe index restores with resident state",
	)
	_expect_equal(
		(restored_queue.call("append_wake", _event_wake(0), []) as Dictionary)
			.get("added"),
		false,
		"restored state still deduplicates an evicted source",
	)
	_expect_ok(
		tang_queue.call("append_wake", _event_wake(100), []),
		"second resident has an independent queue",
	)
	_expect_equal(
		((tang_queue.call("read") as Dictionary).get("items", []) as Array).size(),
		1,
		"second resident queue is not affected by first resident eviction",
	)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(lin_path),
	)
	_expect(typeof(parsed) == TYPE_ARRAY, "evidence file is one JSON array")

func _test_evidence_queue_deduplicates_world_sources() -> void:
	var queue: RefCounted = (load(EVIDENCE_QUEUE_PATH) as Script).new(
		_test_root.path_join("dedupe/world_evidence.json"),
	)
	var wake := _event_wake(1)
	var first := queue.call("append_wake", wake, []) as Dictionary
	var duplicate := queue.call("append_wake", wake, []) as Dictionary
	_expect_equal(first.get("added"), true, "first source adds one queue item")
	_expect_equal(duplicate.get("added"), false, "identical source redelivery is ignored")
	_expect_equal(
		((queue.call("read") as Dictionary).get("items", []) as Array).size(),
		1,
		"duplicate source does not grow the queue",
	)
	var conflict := wake.duplicate(true)
	conflict["events"][0]["who"] = "另一个人"
	_expect_equal(
		(queue.call("append_wake", conflict, []) as Dictionary).get("ok"),
		false,
		"same source id with different content fails explicitly",
	)
	var capture := queue.call("capture_state") as Dictionary
	var duplicate_state := (capture.get("queue_state", {}) as Dictionary).duplicate(true)
	duplicate_state["items"].append(
		(duplicate_state["items"][0] as Dictionary).duplicate(true),
	)
	_expect_equal(
		(queue.call("validate_state", duplicate_state) as Dictionary).get("ok"),
		false,
		"restored queue rejects duplicate sources across items",
	)
	var conflicting_state := (capture.get("queue_state", {}) as Dictionary).duplicate(true)
	var conflicting_item := (
		(conflicting_state["items"][0] as Dictionary).duplicate(true)
	)
	conflicting_item["wake_packet"]["events"][0]["who"] = "另一个人"
	conflicting_state["items"].append(conflicting_item)
	_expect_equal(
		(queue.call("validate_state", conflicting_state) as Dictionary).get("ok"),
		false,
		"restored queue rejects conflicting sources across items",
	)

func _test_world_revision_stays_integer_across_evidence_json_round_trip() -> void:
	var queue: RefCounted = (load(EVIDENCE_QUEUE_PATH) as Script).new(
		_test_root.path_join("world-revision/world_evidence.json"),
	)
	var first_wake := _event_wake(10)
	first_wake["events"][0]["world_revision"] = 42
	_expect_ok(
		queue.call("append_wake", first_wake, []),
		"integer world revision evidence writes",
	)
	_expect_ok(
		queue.call("read"),
		"integer world revision does not look externally modified after JSON write",
	)
	var reopened_queue: RefCounted = (load(EVIDENCE_QUEUE_PATH) as Script).new(
		_test_root.path_join("world-revision/world_evidence.json"),
	)
	var after_round_trip := reopened_queue.call("read") as Dictionary
	_expect_ok(
		after_round_trip,
		"integer world revision survives evidence JSON round trip",
	)
	var items := after_round_trip.get("items", []) as Array
	if items.size() == 1:
		var event := (
			((items[0] as Dictionary).get("wake_packet", {}) as Dictionary)
				.get("events", [])[0]
		) as Dictionary
		_expect_equal(
			typeof(event.get("world_revision")),
			TYPE_INT,
			"world_revision remains an int after persistence",
		)
		_expect_equal(event.get("world_revision"), 42, "world_revision value remains exact")
	var second_wake := _event_wake(11)
	second_wake["events"][0]["world_revision"] = 43
	_expect_ok(
		queue.call("append_wake", second_wake, []),
		"a real dialogue can append after integer world revision persistence",
	)
	var invalid_queue: RefCounted = (load(EVIDENCE_QUEUE_PATH) as Script).new(
		_test_root.path_join("world-revision-invalid/world_evidence.json"),
	)
	var invalid_wake := _event_wake(12)
	invalid_wake["events"][0]["world_revision"] = 44.0
	var invalid_result := invalid_queue.call("append_wake", invalid_wake, []) as Dictionary
	_expect_equal(invalid_result.get("ok"), false, "float world_revision is rejected")
	_expect(
		_errors_contain(invalid_result.get("errors", []), "world_revision 必须是整数"),
		"world_revision type error is explicit",
	)

func _test_world_result_pairs_with_pending_intention() -> void:
	var system := _new_memory_system("paired-result")
	var decision := {
		"decision_id": "intent-decision",
		"handling": "replace_current",
		"action": {
			"action_id": "talk-action",
			"type": "搭话",
			"target_resident_id": "resident-tang-xiao-man",
			"say": "木架的事，我想解释一下。",
			"narration": "",
			"photos": [],
		},
	}
	_expect_ok(
		system.call("accept_decision", decision, TestData.wake_packet("intent-decision")),
		"valid decision becomes pending",
	)
	var result_wake := TestData.wake_packet("result-decision")
	result_wake["action_results"] = [{
		"action_id": "talk-action",
		"status": "rejected",
		"reason": "唐小满已经离开，搭话没有发生。",
		"time": {"day": 1, "clock": "08:12", "period": "上午"},
	}]
	_expect_ok(system.call("prepare_context", result_wake), "world result enters evidence queue")
	var snapshot := system.call("get_debug_snapshot") as Dictionary
	_expect_equal(snapshot.get("pending_action_count"), 0, "paired result removes pending action")
	_expect_equal(snapshot.get("evidence_item_count"), 1, "result wake creates one queue item")
	var evidence := snapshot.get("evidence", []) as Array
	if evidence.size() == 1:
		var intents := (evidence[0] as Dictionary).get("matched_intents", []) as Array
		_expect_equal(intents.size(), 1, "queue item keeps the matched original intention")
		if intents.size() == 1:
			_expect_equal(
				(intents[0] as Dictionary).get("action_id"),
				"talk-action",
				"matched intention uses the world result action id",
			)
	_expect_equal(snapshot.get("memory"), TestData.empty_memory(), "world result does not write memory directly")

func _event_wake(index: int, day: int = 1) -> Dictionary:
	return TestData.event_wake(
		"wake-%d" % index,
		"event-%d" % index,
		day,
		"有人走了",
		"08:%02d" % (index % 60),
	)


func _new_memory_system(suffix: String) -> RefCounted:
	return (load(MEMORY_SYSTEM_PATH) as Script).new(
		TestData.initialization(),
		_test_root.path_join(suffix),
	)


func _finalize() -> void:
	_BaseUserTestDataCleaner.remove_tree(_test_root)
