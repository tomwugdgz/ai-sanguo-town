extends "res://tests/agent/support/AgentTestCase.gd"


const AgentContractScript := preload("res://agent/AgentContract.gd")
const AgentPromptCompilerScript := preload("res://agent/prompt/AgentPromptCompiler.gd")
const DATA_PATH := "res://tests/support/ProviderLiveValidationData.gd"



func _initialize() -> void:
	var data_script := load(DATA_PATH) as Script
	_expect(data_script != null, "Provider live validation data loads")
	if data_script == null:
		_finish_suite("PROVIDER_LIVE_VALIDATION_DATA_PASS")
		return
	var data: RefCounted = data_script.new()
	var initialization: Dictionary = data.call("initialization")
	_expect_equal(
		AgentContractScript.validate_initialization(initialization),
		[],
		"behavior initialization follows the Agent contract",
	)

	var connectivity_request: Dictionary = data.call(
		"connectivity_request",
		"example-provider",
		"example-model",
	)
	_expect_equal(
		(connectivity_request.get("messages", []) as Array).size(),
		2,
		"connectivity request has a minimal system/user exchange",
	)
	_expect(
		JSON.stringify(connectivity_request).contains("example-model"),
		"connectivity request identifies the selected model",
	)

	var cases: Array = data.call("behavior_cases")
	var compiler: RefCounted = AgentPromptCompilerScript.new(initialization)
	_expect_equal(compiler.call("get_load_errors"), [], "behavior validation prompt files load")
	_expect_equal(cases.size(), 5, "behavior validation uses five focused wake packets")
	_expect_equal(
		_case_ids(cases),
		[
			"reply_required",
			"eat_when_hungry",
			"seek_storm_shelter",
			"continue_current_work",
			"answer_workshop_notice",
		],
		"behavior cases cover the agreed triggers",
	)
	for case_value: Variant in cases:
		var case_data := case_value as Dictionary
		var compiled := compiler.call("compile", case_data.get("wake_packet"), "") as Dictionary
		_expect_equal(
			AgentContractScript.validate_wake_packet(case_data.get("wake_packet")),
			[],
			"%s wake packet follows the Agent contract" % case_data.get("id", "unknown"),
		)
		_expect(
			typeof(case_data.get("expected")) == TYPE_DICTIONARY
			and not (case_data.get("expected") as Dictionary).is_empty(),
			"%s declares an observable expectation" % case_data.get("id", "unknown"),
		)
		_expect_equal(
			compiled.get("request_kind"),
			"resident_decision",
			"%s compiles into a resident decision request" % case_data.get("id", "unknown"),
		)
	_finish_suite("PROVIDER_LIVE_VALIDATION_DATA_PASS")


func _case_ids(cases: Array) -> Array[String]:
	var ids: Array[String] = []
	for case_value: Variant in cases:
		ids.append(String((case_value as Dictionary).get("id", "")))
	return ids
