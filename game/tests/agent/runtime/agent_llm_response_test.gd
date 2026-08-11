extends "res://tests/agent/support/AgentTestCase.gd"


const AgentSystemScript := preload("res://agent/AgentSystem.gd")
const ScriptedModelProviderScript := preload("res://tests/agent/support/ScriptedModelProvider.gd")
const TestData := preload("res://tests/support/AgentMemoryTestData.gd")

var _system_counter := 0
var _test_root := "user://tests/agent/llm-response/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


class ResultCollector:
	var values: Array[Dictionary] = []

	func collect(value: Dictionary) -> void:
		values.append(value.duplicate(true))


class FailingModelProvider:
	extends RefCounted

	func request_decision(_model_input: Dictionary, on_complete: Callable) -> void:
		on_complete.call({"ok": false, "errors": ["supplier-secret-error"]})


class DuplicateCallbackProvider:
	extends RefCounted

	func request_decision(model_request: Dictionary, on_complete: Callable) -> void:
		var wake_packet := model_request.get("wake_packet", {}) as Dictionary
		var result := {
			"ok": true,
			"decision": TestData.stay_decision(
				String(wake_packet.get("decision_id", "")),
				"duplicate-callback-action",
			),
		}
		on_complete.call(result)
		on_complete.call(result)


func _initialize() -> void:
	_test_valid_response_reaches_world_once()
	_test_invalid_response_is_rejected()
	_test_provider_error_is_sanitized()
	_test_duplicate_callback_is_one_shot()
	_test_extra_fields_are_rejected()
	_test_stale_response_is_discarded()
	_finish_suite("AGENT_LLM_RESPONSE_PASS", [_test_root])


func _test_valid_response_reaches_world_once() -> void:
	var system := _new_system()
	var model: RefCounted = ScriptedModelProviderScript.new()
	var initialization := TestData.initialization()
	var wake := TestData.wake_packet("valid-response")
	var decision := TestData.stay_decision("valid-response", "valid-action")
	model.call("queue_decision", decision)
	_expect_ok(system.call("initialize_resident", initialization, model), "居民初始化后才能请求模型")
	var results := ResultCollector.new()
	_expect_ok(
		system.call("request_decision", "resident-lin-lan", wake, results.collect),
		"合法世界唤醒启动一次模型决定",
	)
	_expect_equal(results.values, [_accepted_decision_result(decision)], "合法模型决定只到达世界一次")
	var requests: Array = model.call("get_requests")
	_expect_equal(requests.size(), 1, "模型收到一次编译请求")
	if requests.size() == 1:
		var request := requests[0] as Dictionary
		_expect_equal(request.get("initialization"), initialization, "模型请求保留居民初始化资料")
		_expect_equal(request.get("wake_packet"), wake, "模型请求与当前世界唤醒一致")
		_expect_equal((request.get("messages", []) as Array).size(), 2, "模型请求包含基线和动态消息")
	_expect_equal(model.call("get_responses"), [decision], "测试模型记录未经修改的原始响应")


func _test_invalid_response_is_rejected() -> void:
	var system := _new_system()
	var model: RefCounted = ScriptedModelProviderScript.new()
	model.call("queue_decision", TestData.stay_decision("wrong-id", "wrong-action"))
	_expect_ok(system.call("initialize_resident", TestData.initialization(), model), "错误响应测试初始化居民")
	var results := ResultCollector.new()
	system.call(
		"request_decision",
		"resident-lin-lan",
		TestData.wake_packet("expected-id"),
		results.collect,
	)
	_expect_equal(results.values.size(), 1, "错误模型决定仍产生一次失败回调")
	if results.values.size() == 1:
		_expect_equal(results.values[0].get("ok"), false, "不匹配的 decision_id 被拒绝")
		_expect(_errors_contain(results.values[0].get("errors", []), "decision_id"), "失败结果指出不匹配字段")

	model.call("queue_decision", {
		"decision_id": "empty-action",
		"handling": "replace_current",
		"action": {},
	})
	var empty_results := ResultCollector.new()
	system.call(
		"request_decision",
		"resident-lin-lan",
		TestData.wake_packet("empty-action"),
		empty_results.collect,
	)
	_expect_equal(empty_results.values.size(), 1, "空动作结构不会导致运行时崩溃")
	if empty_results.values.size() == 1:
		_expect_equal(empty_results.values[0].get("ok"), false, "空动作被契约拒绝")
		_expect(_errors_contain(empty_results.values[0].get("errors", []), "action.action_id"), "空动作指出缺失字段")


func _test_provider_error_is_sanitized() -> void:
	var system := _new_system()
	_expect_ok(
		system.call("initialize_resident", TestData.initialization(), FailingModelProvider.new()),
		"Provider 失败测试初始化居民",
	)
	var results := ResultCollector.new()
	system.call(
		"request_decision",
		"resident-lin-lan",
		TestData.wake_packet("provider-failure"),
		results.collect,
	)
	_expect_equal(results.values, [{"ok": false, "errors": ["模型调用失败"]}], "世界只收到统一模型错误")
	_expect(not JSON.stringify(results.values).contains("supplier-secret-error"), "供应商错误详情不会进入世界回调")


func _test_duplicate_callback_is_one_shot() -> void:
	var system := _new_system()
	_expect_ok(
		system.call("initialize_resident", TestData.initialization(), DuplicateCallbackProvider.new()),
		"重复回调测试初始化居民",
	)
	var results := ResultCollector.new()
	system.call(
		"request_decision",
		"resident-lin-lan",
		TestData.wake_packet("duplicate-callback"),
		results.collect,
	)
	_expect_equal(results.values.size(), 1, "Provider 重复回调只到达世界一次")
	system.call("close_game")
	_expect_equal((system.get("_retired_residents") as Array).size(), 0, "重复回调不会遗留退休居民实例")


func _test_extra_fields_are_rejected() -> void:
	var system := _new_system()
	var model: RefCounted = ScriptedModelProviderScript.new()
	var raw_decision := TestData.stay_decision("extra-fields", "extra-action")
	raw_decision["reasoning"] = "供应商附加内容"
	raw_decision["action"]["debug"] = {"trace": true}
	model.call("queue_decision", raw_decision)
	_expect_ok(system.call("initialize_resident", TestData.initialization(), model), "额外字段测试初始化居民")
	var results := ResultCollector.new()
	system.call(
		"request_decision",
		"resident-lin-lan",
		TestData.wake_packet("extra-fields"),
		results.collect,
	)
	_expect_equal(results.values.size(), 1, "包含额外字段的决定完成一次")
	if results.values.size() == 1:
		_expect_equal(results.values[0].get("ok"), false, "决定和动作额外字段被拒绝")
		_expect(_errors_contain(results.values[0].get("errors", []), "decision.reasoning"), "报告决定额外字段")
		_expect(_errors_contain(results.values[0].get("errors", []), "action.debug"), "报告动作额外字段")
	_expect_equal(model.call("get_responses"), [raw_decision], "调试记录保留原始模型响应")


func _test_stale_response_is_discarded() -> void:
	var system := _new_system()
	var model: RefCounted = ScriptedModelProviderScript.new()
	model.call("set_auto_complete", false)
	model.call("queue_decision", TestData.stay_decision("old", "old-action"))
	model.call("queue_decision", TestData.stay_decision("current", "current-action"))
	_expect_ok(system.call("initialize_resident", TestData.initialization(), model), "过期响应测试初始化居民")
	var old_results := ResultCollector.new()
	var current_results := ResultCollector.new()
	system.call("request_decision", "resident-lin-lan", TestData.wake_packet("old"), old_results.collect)
	system.call("request_decision", "resident-lin-lan", TestData.wake_packet("current"), current_results.collect)
	model.call("complete_next")
	_expect_equal(old_results.values.size(), 1, "已被新唤醒替代的旧响应得到明确过期回执")
	if old_results.values.size() == 1:
		_expect_equal(old_results.values[0].get("stale"), true, "旧响应不能再被误当成当前决定")
	model.call("complete_next")
	_expect_equal(current_results.values.size(), 1, "当前响应只到达世界一次")
	if current_results.values.size() == 1:
		_expect_equal(
			current_results.values[0].get("decision"),
			TestData.stay_decision("current", "current-action"),
			"当前模型决定保持不变",
		)


func _new_system() -> RefCounted:
	_system_counter += 1
	var system: RefCounted = AgentSystemScript.new()
	_expect_ok(
		system.call("configure_test_runtime_storage", _test_root.path_join(str(_system_counter))),
		"LLM 响应测试配置独立运行目录",
	)
	return system


func _finalize() -> void:
	_BaseUserTestDataCleaner.remove_tree(_test_root)
