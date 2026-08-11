extends "res://tests/agent/support/AgentTestCase.gd"


const AgentContractScript := preload("res://agent/AgentContract.gd")
const ScenariosScript := preload("res://agent/debug/AgentDebugScenarios.gd")



func _initialize() -> void:
	var scenarios: RefCounted = ScenariosScript.new()
	var initialization: Dictionary = scenarios.call("initialization")
	_expect_equal(
		AgentContractScript.validate_initialization(initialization),
		[],
		"样例 ResidentInitialization 符合正式契约",
	)
	var action_result_sequence: Array = scenarios.call("sequence", "action_result")
	_expect_equal(action_result_sequence.size(), 2, "动作结果样例包含连续两轮")
	for packet: Dictionary in action_result_sequence:
		_expect_equal(
			AgentContractScript.validate_wake_packet(packet),
			[],
			"样例 WakePacket 符合正式契约",
		)
	if action_result_sequence.size() == 2:
		_expect_equal(
			action_result_sequence[1]["action_results"][0]["action_id"],
			"fake-debug-1",
			"第二轮显式回传上一轮 action_id",
		)
	var memory_sequence: Array = scenarios.call("sequence", "memory")
	_expect_equal(memory_sequence.size(), 4, "记忆样例提供整理触发所需的连续证据")
	_finish_suite("AGENT_DEBUG_SCENARIOS_TEST_PASS")
