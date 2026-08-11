extends "res://tests/agent/support/AgentTestCase.gd"


const AgentSystemScript := preload("res://agent/AgentSystem.gd")
const FakeModelProviderScript := preload("res://agent/model/FakeModelProvider.gd")
const TestData := preload("res://tests/support/AgentMemoryTestData.gd")

var _test_root := "user://tests/agent/code-connectivity/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


class ResultCollector:
	var values: Array[Dictionary] = []

	func collect(value: Dictionary) -> void:
		values.append(value.duplicate(true))


func _initialize() -> void:
	var system: RefCounted = AgentSystemScript.new()
	_expect_ok(
		system.call("configure_test_runtime_storage", _test_root),
		"Fake 连通性测试使用独立运行目录",
	)
	var model: RefCounted = FakeModelProviderScript.new()
	_expect_ok(
		system.call("initialize_resident", TestData.initialization(), model),
		"居民通过正式 Agent 入口初始化",
	)
	var collector := ResultCollector.new()
	var acceptance: Dictionary = system.call(
		"request_decision",
		"resident-lin-lan",
		TestData.wake_packet("fake-connectivity"),
		collector.collect,
	)
	_expect_equal(
		acceptance,
		{"ok": true, "decision_id": "fake-connectivity"},
		"世界唤醒经过记忆、提示词和 Fake 模型后被接受",
	)
	_expect_equal(collector.values.size(), 1, "世界只收到一次 Fake 模型结果")
	if collector.values.size() == 1:
		var result: Dictionary = collector.values[0]
		_expect_equal(result.get("ok"), true, "Fake 模型结果通过决定契约")
		_expect_equal(
			result.get("decision"),
			{
				"decision_id": "fake-connectivity",
				"handling": "replace_current",
				"action": {
					"action_id": "fake-fake-connectivity",
					"type": "待着",
					"line": "先看看周围的情况",
				},
			},
			"Fake 模型返回确定性的合法模拟决定",
		)
	_expect_equal((model.call("get_requests") as Array).size(), 1, "Fake 模型记录一次编译后请求")
	_expect_equal((model.call("get_responses") as Array).size(), 1, "Fake 模型记录一次模拟输出")

	var collision_wake := TestData.wake_packet("collision")
	collision_wake["snapshot"]["me"]["current_action"] = {
		"action_id": "fake-collision",
		"type": "待着",
	}
	var collision_results := ResultCollector.new()
	_expect_ok(
		system.call(
			"request_decision",
			"resident-lin-lan",
			collision_wake,
			collision_results.collect,
		),
		"Fake 模型处理与默认动作编号冲突的世界唤醒",
	)
	_expect_equal(collision_results.values.size(), 1, "动作编号避碰只返回一次结果")
	if collision_results.values.size() == 1:
		_expect_equal(
			collision_results.values[0].get("decision", {}).get("action", {}).get("action_id"),
			"fake-collision-2",
			"Fake 模型不会复用世界正在执行的动作编号",
		)
	_finish_suite("AGENT_CODE_CONNECTIVITY_PASS", [_test_root])


func _finalize() -> void:
	_BaseUserTestDataCleaner.remove_tree(_test_root)
