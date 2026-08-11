extends "res://tests/agent/support/AgentTestCase.gd"


const MEMORY_STORE_PATH := "res://agent/memory/ResidentMemoryStore.gd"
const TestData := preload("res://tests/support/AgentMemoryTestData.gd")

var _test_root := "user://tests/agent/resident-memory-store/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	_test_memory_store_accepts_only_five_strings()
	_test_memory_store_reports_retryable_capacity_overflow()
	_finish_suite("RESIDENT-MEMORY-STORE_PASS", [_test_root])


func _test_memory_store_accepts_only_five_strings() -> void:
	var path := _test_root.path_join("store/resident_memory.json")
	var store: RefCounted = (load(MEMORY_STORE_PATH) as Script).new(path)
	var empty := TestData.empty_memory()
	_expect_ok(store.call("replace", empty), "five-field memory replaces atomically")
	_expect_equal(
		(store.call("read") as Dictionary).get("memory"),
		empty,
		"five-field memory reads back unchanged",
	)
	var nested := empty.duplicate(true)
	nested["important_memories"] = []
	_expect_equal(
		(store.call("validate", nested) as Dictionary).get("ok"),
		false,
		"memory fields reject nested arrays",
	)
	var extra := empty.duplicate(true)
	extra["schema_version"] = 1
	_expect_equal(
		(store.call("validate", extra) as Dictionary).get("ok"),
		false,
		"memory rejects unknown top-level fields",
	)

func _test_memory_store_reports_retryable_capacity_overflow() -> void:
	var store: RefCounted = (load(MEMORY_STORE_PATH) as Script).new(
		_test_root.path_join("limits/resident_memory.json"),
	)
	var within_slack := TestData.empty_memory()
	within_slack["important_memories"] = "记".repeat(2200)
	_expect_ok(store.call("validate", within_slack), "120 percent slack accepts target overflow")
	var too_long := TestData.empty_memory()
	too_long["important_memories"] = "记".repeat(2401)
	var validation := store.call("validate", too_long) as Dictionary
	_expect_equal(validation.get("ok"), false, "hard field limit rejects output")
	_expect_equal(validation.get("retryable"), true, "capacity overflow requests model retry")
	_expect(
		(validation.get("overflow_fields", []) as Array).has("important_memories"),
		"capacity error identifies the overflowing field",
	)


func _finalize() -> void:
	_BaseUserTestDataCleaner.remove_tree(_test_root)
