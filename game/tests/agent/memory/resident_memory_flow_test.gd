extends "res://tests/agent/support/AgentTestCase.gd"


const AGENT_SYSTEM_PATH := "res://agent/AgentSystem.gd"
const SCRIPTED_MODEL_PATH := "res://tests/agent/support/ScriptedModelProvider.gd"
const MEMORY_SYSTEM_PATH := "res://agent/memory/ResidentMemorySystem.gd"
const UserTestDataCleanerScript := preload("res://tests/support/UserTestDataCleaner.gd")
const TestData := preload("res://tests/support/AgentMemoryTestData.gd")

var _test_root := "user://tests/agent-memory-flow/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


class ResultCollector:
	var values: Array[Dictionary] = []

	func collect(value: Dictionary) -> void:
		values.append(value.duplicate(true))


func _initialize() -> void:
	_test_action_waits_for_world_result()
	_test_organizer_failure_keeps_old_memory_and_continues_deciding()
	_test_organizer_provider_failure_keeps_old_memory_and_continues_deciding()
	_test_conversation_end_triggers_immediate_organization()
	_test_capacity_overflow_retries_once()
	_test_failed_capacity_retry_keeps_old_memory()
	_test_corrupt_memory_blocks_the_wake()
	_finish_suite("AGENT_MEMORY_FLOW_PASS", [_test_root])


func _test_action_waits_for_world_result() -> void:
	var system := _new_system("world-result")
	var model: RefCounted = (load(SCRIPTED_MODEL_PATH) as Script).new()
	model.call("queue_decision", TestData.stay_decision("intent-1", "action-1"))
	_expect_ok(system.call("initialize_resident", TestData.initialization(), model), "resident initializes")
	var results := ResultCollector.new()
	_expect_ok(
		system.call(
			"request_decision",
			"resident-lin-lan",
			TestData.wake_packet("intent-1"),
			results.collect,
		),
		"resident decision starts",
	)
	_expect_equal(results.values.size(), 1, "valid intention reaches the world")
	var pending_snapshot: Dictionary = system.call(
		"get_memory_debug_snapshot",
		"resident-lin-lan",
	)
	_expect_equal(pending_snapshot.get("pending_action_count"), 1, "intention waits for world confirmation")
	_expect_equal(
		pending_snapshot.get("memory"),
		_pending_memory("我先想一想。"),
		"intention is visible as the current focus, not an accomplished memory",
	)

	var result_wake := TestData.wake_packet("result-1")
	result_wake["action_results"] = [{
		"action_id": "action-1",
		"status": "completed",
		"reason": "林岚等了一会儿。",
		"time": {"day": 1, "clock": "08:15", "period": "上午"},
	}]
	model.call("queue_decision", TestData.stay_decision("result-1", "action-2"))
	var result_collector := ResultCollector.new()
	_expect_ok(
		system.call(
			"request_decision",
			"resident-lin-lan",
			result_wake,
			result_collector.collect,
		),
		"confirmed result wake starts",
	)
	var confirmed_snapshot: Dictionary = system.call(
		"get_memory_debug_snapshot",
		"resident-lin-lan",
	)
	_expect_equal(confirmed_snapshot.get("pending_action_count"), 1, "new decision is pending")
	_expect_equal(confirmed_snapshot.get("evidence_item_count"), 1, "world result creates evidence")
	_expect_equal(
		confirmed_snapshot.get("memory"),
		_pending_memory("我先想一想。"),
		"ordinary result does not force immediate organized memory",
	)


func _test_organizer_failure_keeps_old_memory_and_continues_deciding() -> void:
	var system := _new_system("organizer-failure")
	var model: RefCounted = (load(SCRIPTED_MODEL_PATH) as Script).new()
	_expect_ok(system.call("initialize_resident", TestData.initialization(), model), "failure resident initializes")
	for index in range(3):
		model.call("queue_decision", TestData.stay_decision("failure-%d" % index, "failure-action-%d" % index))
		var warmup := ResultCollector.new()
		_expect_ok(
			system.call(
				"request_decision",
				"resident-lin-lan",
				TestData.event_wake("failure-%d" % index, "failure-event-%d" % index),
				warmup.collect,
			),
			"evidence warmup starts",
		)
	model.call("queue_json_response", {})
	model.call("queue_decision", TestData.stay_decision("failure-3", "failure-action-3"))
	var results := ResultCollector.new()
	_expect_ok(
		system.call(
			"request_decision",
			"resident-lin-lan",
			TestData.event_wake("failure-3", "failure-event-3"),
			results.collect,
		),
		"fourth evidence triggers organizer",
	)
	_expect_equal(results.values.size(), 1, "organizer failure does not suppress the world decision")
	var snapshot: Dictionary = system.call("get_memory_debug_snapshot", "resident-lin-lan")
	_expect_equal(snapshot.get("memory"), _pending_memory("我先想一想。"), "invalid organizer JSON preserves old memory")
	_expect_equal(snapshot.get("evidence_item_count"), 4, "failed organization preserves evidence")
	var requests := model.call("get_requests") as Array
	_expect_equal(requests.size(), 5, "four decisions plus one organizer request are issued")
	if requests.size() == 5:
		_expect_equal(
			(requests[3] as Dictionary).get("request_kind"),
			"memory_organization",
			"organization runs before the fourth decision",
		)


func _test_conversation_end_triggers_immediate_organization() -> void:
	var system := _new_system("conversation-end")
	var model: RefCounted = (load(SCRIPTED_MODEL_PATH) as Script).new()
	model.call("set_auto_complete", false)
	var memory := TestData.organized_memory()
	model.call("queue_json_response", memory)
	model.call("queue_decision", TestData.stay_decision("conversation-end", "conversation-action"))
	_expect_ok(system.call("initialize_resident", TestData.initialization(), model), "conversation resident initializes")
	var results := ResultCollector.new()
	_expect_ok(
		system.call(
			"request_decision",
			"resident-lin-lan",
			TestData.conversation_end_wake(),
			results.collect,
		),
		"conversation end wake starts",
	)
	_expect_equal(
		(model.call("get_requests") as Array).size(),
		1,
		"conversation end first waits for organization",
	)
	_expect_equal(
		model.call("complete_next", 2),
		true,
		"duplicate organization callback is delivered",
	)
	var requests := model.call("get_requests") as Array
	_expect_equal(requests.size(), 2, "conversation end organizes before decision")
	if requests.size() == 2:
		_expect_equal(
			(requests[0] as Dictionary).get("request_kind"),
			"memory_organization",
			"conversation end uses the dedicated organizer route",
		)
	_expect_equal(
		model.call("complete_next"),
		true,
		"the single decision request completes",
	)
	_expect_equal(results.values.size(), 1, "duplicate organizer callback still produces one decision")
	var snapshot: Dictionary = system.call("get_memory_debug_snapshot", "resident-lin-lan")
	_expect_equal(
		snapshot.get("memory"),
		_organized_pending_memory(memory),
		"organizer output fully replaces memory while the submitted action remains the current focus",
	)


func _test_organizer_provider_failure_keeps_old_memory_and_continues_deciding() -> void:
	var system := _new_system("organizer-provider-failure")
	var model: RefCounted = (load(SCRIPTED_MODEL_PATH) as Script).new()
	model.call("queue_failure", ["模拟整理 Provider 失败"])
	model.call(
		"queue_decision",
		TestData.stay_decision("conversation-end", "provider-failure-action"),
	)
	_expect_ok(
		system.call("initialize_resident", TestData.initialization(), model),
		"provider-failure resident initializes",
	)
	var results := ResultCollector.new()
	_expect_ok(
		system.call(
			"request_decision",
			"resident-lin-lan",
			TestData.conversation_end_wake(),
			results.collect,
		),
		"organizer Provider failure flow starts",
	)
	_expect_equal(results.values.size(), 1, "organizer Provider failure still returns one decision")
	var requests := model.call("get_requests") as Array
	_expect_equal(requests.size(), 2, "failed organizer call is followed by a resident decision call")
	if requests.size() == 2:
		_expect_equal(
			(requests[1] as Dictionary).get("request_kind"),
			"resident_decision",
			"resident decision follows the failed organizer call",
		)
	var snapshot: Dictionary = system.call(
		"get_memory_debug_snapshot",
		"resident-lin-lan",
	)
	_expect_equal(snapshot.get("memory"), _pending_memory("我先想一想。"), "Provider failure preserves old memory")
	_expect_equal(snapshot.get("evidence_item_count"), 1, "Provider failure preserves evidence")
	_expect_equal(
		snapshot.get("last_organization", {}).get("status"),
		"organization_error",
		"Provider failure remains visible after the resident decision",
	)
	_expect_equal(
		(snapshot.get("read_errors", []) as Array).has("模拟整理 Provider 失败"),
		true,
		"Provider failure detail remains visible to debug",
	)


func _test_capacity_overflow_retries_once() -> void:
	var system := _new_system("capacity-retry")
	var model: RefCounted = (load(SCRIPTED_MODEL_PATH) as Script).new()
	var overflow := TestData.organized_memory()
	overflow["important_memories"] = "记".repeat(2401)
	model.call("queue_json_response", overflow)
	model.call("queue_json_response", TestData.organized_memory())
	model.call("queue_decision", TestData.stay_decision("conversation-end", "retry-action"))
	_expect_ok(system.call("initialize_resident", TestData.initialization(), model), "retry resident initializes")
	var results := ResultCollector.new()
	_expect_ok(
		system.call(
			"request_decision",
			"resident-lin-lan",
			TestData.conversation_end_wake(),
			results.collect,
		),
		"capacity retry flow starts",
	)
	var requests := model.call("get_requests") as Array
	_expect_equal(requests.size(), 3, "overflow causes one retry before decision")
	if requests.size() == 3:
		_expect_equal(
			(requests[0] as Dictionary).get("request_kind"),
			"memory_organization",
			"first request organizes memory",
		)
		_expect_equal(
			(requests[1] as Dictionary).get("retry_attempt"),
			1,
			"second request is marked as compression retry",
		)
	var snapshot: Dictionary = system.call("get_memory_debug_snapshot", "resident-lin-lan")
	_expect_equal(
		snapshot.get("memory"),
		_organized_pending_memory(TestData.organized_memory()),
		"valid retry output replaces memory while the submitted action remains the current focus",
	)


func _test_failed_capacity_retry_keeps_old_memory() -> void:
	var root := _test_root.path_join("failed-capacity-retry")
	var memory_path := root.path_join("resident-lin-lan/resident_memory.json")
	var memory_store: RefCounted = (
		load("res://agent/memory/ResidentMemoryStore.gd") as Script
	).new(memory_path)
	var old_memory := TestData.organized_memory()
	old_memory["current_thoughts"] = "这份旧记忆必须保持完整。"
	_expect_ok(memory_store.call("replace", old_memory), "old memory fixture writes")
	var evidence_queue: RefCounted = (
		load("res://agent/memory/ResidentEvidenceQueue.gd") as Script
	).new(root.path_join("resident-lin-lan/world_evidence.json"))
	_expect_ok(evidence_queue.call("initialize_empty"), "old evidence fixture writes")
	var system := _new_system("failed-capacity-retry")
	var model: RefCounted = (load(SCRIPTED_MODEL_PATH) as Script).new()
	var overflow := TestData.organized_memory()
	overflow["important_memories"] = "记".repeat(2401)
	model.call("queue_json_response", overflow)
	model.call("queue_json_response", overflow)
	model.call("queue_decision", TestData.stay_decision("conversation-end", "failed-retry-action"))
	_expect_ok(system.call("initialize_resident", TestData.initialization(), model), "failed-retry resident initializes")
	var results := ResultCollector.new()
	_expect_ok(
		system.call(
			"request_decision",
			"resident-lin-lan",
			TestData.conversation_end_wake(),
			results.collect,
		),
		"failed capacity retry flow starts",
	)
	_expect_equal(results.values.size(), 1, "failed retry still continues to the world decision")
	var snapshot: Dictionary = system.call("get_memory_debug_snapshot", "resident-lin-lan")
	_expect_equal(
		snapshot.get("memory"),
		_pending_memory_from(old_memory, "我先想一想。"),
		"second overflow does not damage old memory",
	)


func _test_corrupt_memory_blocks_the_wake() -> void:
	var root := _test_root.path_join("corrupt")
	var path := root.path_join("resident-lin-lan/resident_memory.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken-json")
	file = null
	var memory_system: RefCounted = (load(MEMORY_SYSTEM_PATH) as Script).new(
		TestData.initialization(),
		root,
	)
	var result: Dictionary = memory_system.call("prepare_context", TestData.wake_packet("corrupt"))
	_expect_equal(result.get("ok"), false, "corrupt resident memory fails explicitly")


func _new_system(suffix: String) -> RefCounted:
	var system: RefCounted = (load(AGENT_SYSTEM_PATH) as Script).new()
	var configuration: Dictionary = system.call(
		"configure_test_runtime_storage",
		_test_root.path_join(suffix),
	)
	if configuration.get("ok") != true:
		_failures.append("test runtime storage failed: %s" % [configuration])
	return system


func _finalize() -> void:
	UserTestDataCleanerScript.remove_tree(_test_root)


func _pending_memory(line: String) -> Dictionary:
	var memory := TestData.empty_memory()
	memory["current_thoughts"] = line
	return memory


func _pending_memory_from(base: Dictionary, thought: String) -> Dictionary:
	var memory := base.duplicate(true)
	memory["current_thoughts"] = thought
	return memory


func _organized_pending_memory(memory: Dictionary) -> Dictionary:
	var projected := memory.duplicate(true)
	projected["important_memories"] = _conversation_memory_with_source_lines(memory)
	projected["current_thoughts"] = "我先想一想。"
	return projected


func _conversation_memory_with_source_lines(memory: Dictionary) -> String:
	return "唐小满说：木架明天能好吗？\n林岚说：我明早送过去。\n%s" % String(
		memory.get("important_memories", ""),
	)
