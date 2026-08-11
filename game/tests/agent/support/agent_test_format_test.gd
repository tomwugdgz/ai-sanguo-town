extends "res://tests/agent/support/AgentTestCase.gd"


const Format := preload("res://tests/agent/support/AgentTestFormat.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_failure_report_contains_actionable_context()
	_test_sensitive_values_are_redacted()
	_test_subset_differences_report_behavior_mismatches()
	_finish_suite("AGENT_TEST_FORMAT_PASS")


func _test_failure_report_contains_actionable_context() -> void:
	var report := Format.failure(
		"res://tests/agent/contract/example_test.gd",
		"决定字段不一致",
		"expect_equal",
		{"action": {"type": "待着", "photos": []}},
		{"action": {"type": "答话", "photos": ["photo-1"]}},
		[{
			"source": "res://tests/agent/contract/example_test.gd",
			"function": "_test_decision",
			"line": 42,
		}],
		{"provider_id": "deepseek", "case_id": "reply"},
	)
	_expect(report.contains("[FAIL] contract/example_test.gd"), "失败报告包含职责路径")
	_expect(report.contains("case: _test_decision"), "失败报告包含测试用例名")
	_expect(report.contains("source: tests/agent/contract/example_test.gd:42"), "失败报告包含源码位置")
	_expect(report.contains("$.action.type"), "失败报告包含嵌套字段差异路径")
	_expect(report.contains("context:"), "失败报告包含断言上下文")


func _test_sensitive_values_are_redacted() -> void:
	var rendered := Format.render({
		"api_key": "sk-secret-value",
		"headers": {"Authorization": "Bearer another-secret"},
		"message": "safe",
	})
	_expect(rendered.contains(Format.REDACTED), "敏感字段显示脱敏标记")
	_expect(not rendered.contains("sk-secret-value"), "报告不泄露 API Key")
	_expect(not rendered.contains("another-secret"), "报告不泄露 Authorization")
	_expect(rendered.contains("safe"), "普通诊断字段仍然保留")


func _test_subset_differences_report_behavior_mismatches() -> void:
	var mismatches: Array[String] = Format.subset_differences(
		{
			"handling": "replace_current",
			"action": {"type": "去", "place": "工作坊"},
		},
		{
			"handling": "replace_current",
			"action": {"type": "待着", "line": "先看看。"},
		},
	)
	_expect_equal(
		mismatches,
		[
			"$.action.type expected \"去\", actual \"待着\"",
			"$.action.place missing; expected \"工作坊\"",
		],
		"行为期望报告只比较声明的字段并给出 JSON 路径",
	)
	_expect_equal(
		Format.subset_differences(
			{"action": {"type": "待着"}},
			{"action": {"type": "待着", "line": "额外字段允许存在"}},
		),
		[],
		"行为期望使用子集匹配，不把模型的合法额外字段判为偏差",
	)
