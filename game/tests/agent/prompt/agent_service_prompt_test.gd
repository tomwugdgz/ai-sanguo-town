extends "res://tests/agent/support/AgentPromptTestCase.gd"


const AGENT_CONTRACT := preload("res://agent/AgentContract.gd")


func _initialize() -> void:
	var compiler_script := _load_prompt_compiler()
	if compiler_script != null:
		_test_medical_response_contract(compiler_script)
		_test_service_request_and_world_destination_constraints(compiler_script)
	_finish_prompt_test("AGENT_SERVICE_PROMPT_PASS")


func _test_medical_response_contract(compiler_script: Script) -> void:
	var wake := _wake_packet("medical-reply-1", "晴天")
	wake["snapshot"]["conversation"] = {
		"conversation_id": "conversation-medical-1",
		"with_resident_id": "resident-tang-xiao-man",
		"with": "唐小满",
		"turns": [{
			"turn_id": 1,
			"speaker_resident_id": "resident-tang-xiao-man",
			"speaker": "唐小满",
			"say": "哪里不舒服？",
			"narration": "",
			"photos": [],
		}],
		"medical_context": {
			"request_id": "clinic-request-1",
			"role": "patient",
			"status": "active",
			"conversation_id": "conversation-medical-1",
			"reported_summary": "头痛，需要问诊",
			"attempt_count": 1,
			"patient_response_kind": "",
			"response_options": ["describe", "decline"],
		},
	}
	wake["events"] = [{
		"event_id": "medical-reply-event-1",
		"time": {"day": 1, "clock": "08:10", "period": "上午"},
		"type": "对方答话",
		"conversation_id": "conversation-medical-1",
		"turn": (
			wake["snapshot"]["conversation"]["turns"][0] as Dictionary
		).duplicate(true),
	}]
	_expect_equal(
		AGENT_CONTRACT.validate_wake_packet(wake),
		[],
		"patient medical conversation is accepted by the wake contract",
	)
	var fabricated_projection := wake.duplicate(true)
	fabricated_projection["snapshot"]["conversation"]["medical_context"][
		"conversation_id"
	] = ""
	_expect(
		not AGENT_CONTRACT.validate_wake_packet(
			fabricated_projection,
		).is_empty(),
		"active medical projection cannot exist without a real conversation",
	)
	var scripted_projection := wake.duplicate(true)
	scripted_projection["snapshot"]["conversation"]["medical_context"][
		"patient_response_kind"
	] = "scripted_answer"
	_expect(
		not AGENT_CONTRACT.validate_wake_packet(
			scripted_projection,
		).is_empty(),
		"medical projection rejects a scripted patient response kind",
	)
	var compiler: RefCounted = compiler_script.new(_initialization())
	var request := compiler.call("compile", wake, "") as Dictionary
	var constraints := request.get("derived_constraints", {}) as Dictionary
	_expect_equal(
		constraints.get("medical_response"),
		{
			"fields": ["request_id", "response_kind"],
			"request_id": "clinic-request-1",
			"response_kinds": ["describe", "decline"],
			"required": true,
		},
		"patient receives exact medical response choices",
	)
	var actions := constraints.get("actions", {}) as Dictionary
	_expect(
		((actions.get("答话", {}) as Dictionary).get("fields", []) as Array).has(
			"medical_response",
		),
		"patient reply action exposes the required structured field",
	)
	var messages := request.get("messages", []) as Array
	_expect(
		messages.size() == 2
		and String((messages[1] as Dictionary).get("content", "")).contains(
			"medical_response 必须是对象",
		),
		"prompt states the exact medical response shape",
	)
	var decision := {
		"decision_id": "medical-reply-1",
		"handling": "replace_current",
		"action": {
			"action_id": "medical-reply-1-answer",
			"type": "答话",
			"conversation_id": "conversation-medical-1",
			"say": "从早上开始一直头痛，我愿意说清楚。",
			"narration": "",
			"photos": [],
			"end": false,
			"medical_response": {
				"request_id": "clinic-request-1",
				"response_kind": "describe",
			},
		},
	}
	_expect_equal(
		AGENT_CONTRACT.validate_decision(
			decision,
			_initialization(),
			wake,
			{},
		),
		[],
		"exact patient medical response is accepted",
	)
	var missing_response := decision.duplicate(true)
	missing_response["action"].erase("medical_response")
	_expect(
		not AGENT_CONTRACT.validate_decision(
			missing_response,
			_initialization(),
			wake,
			{},
		).is_empty(),
		"patient cannot omit the required structured response",
	)
	var wrong_request := decision.duplicate(true)
	wrong_request["action"]["medical_response"]["request_id"] = "other-request"
	_expect(
		not AGENT_CONTRACT.validate_decision(
			wrong_request,
			_initialization(),
			wake,
			{},
		).is_empty(),
		"patient cannot answer a different medical request",
	)
	var ordinary_wake := wake.duplicate(true)
	ordinary_wake["decision_id"] = "ordinary-reply-null-medical"
	ordinary_wake["snapshot"]["conversation"]["medical_context"] = null
	var ordinary_request := compiler.call("compile", ordinary_wake, "") as Dictionary
	var ordinary_actions := (
		ordinary_request.get("derived_constraints", {}) as Dictionary
	).get("actions", {}) as Dictionary
	_expect(
		not ((ordinary_actions.get("答话", {}) as Dictionary).get(
			"fields",
			[],
		) as Array).has("medical_response"),
		"ordinary conversation does not expose the medical field",
	)
	var ordinary_decision := decision.duplicate(true)
	ordinary_decision["decision_id"] = "ordinary-reply-null-medical"
	ordinary_decision["action"]["action_id"] = (
		"ordinary-reply-null-medical-answer"
	)
	ordinary_decision["action"].erase("medical_response")
	_expect_equal(
		AGENT_CONTRACT.validate_decision(
			ordinary_decision,
			_initialization(),
			ordinary_wake,
			{},
		),
		[],
		"ordinary reply remains valid without a medical response",
	)
	var canonical_ordinary := AGENT_CONTRACT.canonicalize_decision(
		ordinary_decision,
	)
	_expect(
		not (
			canonical_ordinary.get("action", {}) as Dictionary
		).has("medical_response"),
		"ordinary reply canonicalization does not read a missing optional field",
	)
	_expect_equal(
		(
			AGENT_CONTRACT.canonicalize_decision(decision).get(
				"action",
				{},
			) as Dictionary
		).get("medical_response"),
		decision["action"]["medical_response"],
		"medical reply canonicalization retains the structured response",
	)


func _test_service_request_and_world_destination_constraints(
	compiler_script: Script,
) -> void:
	var wake := _wake_packet("service-task-prompt-1", "晴天")
	wake["snapshot"]["place"]["destinations"] = [
		"中心广场",
		"图书馆",
	]
	wake["snapshot"]["work_tasks"] = [{
		"task_id": "service-task:clinic:request-1",
		"capability": "care.consultation",
		"source_kind": "clinic_request",
		"source_ref": "request-1",
		"targets": [{
			"kind": "service_request",
			"ref": "request-1",
		}],
		"expected_result": "consultation_record",
		"state": "pending",
		"priority": 85,
		"process_stage": "awaiting_interview",
		"service_request": {
			"request_id": "request-1",
			"kind": "clinic",
			"requester_resident_id": "resident-tang-xiao-man",
			"requester_name": "唐小满",
			"requester_current_place": "诊所",
			"subject_ref": "头疼",
			"item_id": "",
			"place_id": "诊所",
			"state": "pending",
			"wait_reason": "",
			"medical_dialogue": {
				"request_id": "request-1",
				"role": "clinician",
				"status": "required",
				"conversation_id": "",
				"reported_summary": "头疼",
				"attempt_count": 0,
				"patient_response_kind": "",
				"response_options": [],
			},
		},
	}]
	_expect_equal(
		AGENT_CONTRACT.validate_wake_packet(wake),
		[],
		"service request task is accepted by the Agent wake contract",
	)
	var mismatched_wake := wake.duplicate(true)
	mismatched_wake["snapshot"]["work_tasks"][0]["source_ref"] = (
		"another-request"
	)
	_expect(
		not AGENT_CONTRACT.validate_wake_packet(
			mismatched_wake,
		).is_empty(),
		"service request cannot detach from its World task source",
	)
	var compiler: RefCounted = compiler_script.new(_initialization())
	var request := compiler.call("compile", wake, "") as Dictionary
	var messages := request.get("messages", []) as Array
	_expect_equal(messages.size(), 2, "service request prompt compiles")
	if messages.size() != 2:
		return
	var user_text := String(
		(messages[1] as Dictionary).get("content", ""),
	)
	_expect(
		user_text.contains("当前可前往地点：中心广场、图书馆"),
		"dynamic prompt renders the World travel allowlist",
	)
	_expect(
		user_text.contains("唐小满")
		and user_text.contains("头疼")
		and user_text.contains("医患对话：状态required"),
		"service request details are rendered instead of rejected or hidden",
	)
	var actions := (
		request.get("derived_constraints", {}) as Dictionary
	).get("actions", {}) as Dictionary
	_expect_equal(
		(
			(actions.get("去", {}) as Dictionary).get(
				"places",
				[],
			)
		),
		["中心广场", "图书馆"],
		"travel constraints use the World allowlist exactly",
	)
