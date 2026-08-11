extends "res://tests/agent/support/AgentTestCase.gd"

const ProviderDoubles := preload("res://tests/agent/support/ProviderTestDoubles.gd")
const ResultCollector = ProviderDoubles.ResultCollector
const FakeTransport = ProviderDoubles.ImmediateTransport


const PROVIDER_PATH := "res://agent/model/KimiModelProvider.gd"


func _initialize() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "Kimi provider script loads")
	if provider_script != null:
		_test_k3_request(provider_script)
		_test_k2_6_request(provider_script)
		_test_k2_7_highspeed_request(provider_script)
		_test_k2_6_thinking_override(provider_script)
		_test_configuration(provider_script)
		_test_unknown_model_never_reaches_transport(provider_script)
		_test_invalid_k2_6_thinking_never_reaches_transport(provider_script)
		_test_provider_error(provider_script)
		_test_truncated_completion(provider_script)
	_finish_suite("KIMI_PROVIDER_PROTOCOL_PASS")


func _test_k3_request(provider_script: Script) -> void:
	var decision := _decision("kimi-k3-decision")
	var transport := FakeTransport.new()
	transport.response = _http_response(200, {
		"choices": [{
			"finish_reason": "stop",
			"message": {
				"role": "assistant",
				"reasoning_content": "internal reasoning is ignored",
				"content": JSON.stringify(decision),
			},
		}],
		"usage": {"prompt_tokens": 120, "completion_tokens": 40, "total_tokens": 160},
	})
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-kimi-key",
		"model": "kimi-k3",
		"thinking_type": "not-a-k3-setting",
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", _model_input("kimi-k3-decision"), collector.collect)

	_expect_equal(collector.values, [{"ok": true, "decision": decision}], "K3 response becomes a provider-neutral decision")
	_expect_equal(transport.requests.size(), 1, "K3 sends one request")
	if transport.requests.size() == 1:
		var request := transport.requests[0]
		var body := request.get("body", {}) as Dictionary
		_expect_equal(request.get("url"), "https://api.moonshot.cn/v1/chat/completions", "K3 uses the China endpoint")
		_expect_equal(body.get("model"), "kimi-k3", "K3 uses its official model id")
		_expect_equal(body.get("reasoning_effort"), "low", "K3 uses the lowest supported reasoning effort")
		_expect_equal(body.get("max_completion_tokens"), 32768, "K3 uses its model-specific output field")
		_expect(not body.has("max_tokens"), "K3 omits the legacy max_tokens field")
		_expect(not body.has("thinking"), "K3 omits the K2 thinking field")
		_expect_equal(body.get("response_format"), {"type": "json_object"}, "K3 requests JSON output")
		_expect_equal((body.get("messages", []) as Array).size(), 2, "current main model input is compiled into messages")
		_expect(JSON.stringify(body.get("messages", [])).contains("kimi-k3-decision"), "world decision id reaches the compiled user message")
		_expect(not JSON.stringify(body).contains("temporary-kimi-key"), "Kimi key never enters the body")
	_expect(not JSON.stringify(provider.call("get_debug_snapshot")).contains("temporary-kimi-key"), "Kimi key never enters debug records")


func _test_k2_6_request(provider_script: Script) -> void:
	var decision := _decision("kimi-k2-decision")
	var transport := FakeTransport.new()
	transport.response = _http_response(200, {
		"choices": [{"finish_reason": "stop", "message": {"content": JSON.stringify(decision)}}],
	})
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-kimi-key",
		"model": "kimi-k2.6",
	})
	var collector := ResultCollector.new()
	var compiled_request := {
		"messages": [
			{"role": "system", "content": "只返回合法 JSON。"},
			{"role": "user", "content": "决定编号：kimi-k2-decision"},
		],
	}
	provider.call("request_decision", compiled_request, collector.collect)
	_expect_equal(collector.values, [{"ok": true, "decision": decision}], "K2.6 remains independently usable")
	if transport.requests.size() == 1:
		var body := transport.requests[0].get("body", {}) as Dictionary
		_expect_equal(body.get("messages"), compiled_request.get("messages"), "precompiled messages pass through unchanged")
		_expect_equal(body.get("thinking"), {"type": "disabled"}, "K2.6 keeps disabled thinking")
		_expect_equal(body.get("max_tokens"), 32768, "K2.6 keeps the compatible token field")
		_expect(not body.has("reasoning_effort"), "K2.6 omits K3 reasoning options")
		_expect(not body.has("max_completion_tokens"), "K2.6 omits K3 token field")


func _test_k2_6_thinking_override(provider_script: Script) -> void:
	var decision := _decision("kimi-k2-thinking")
	var transport := FakeTransport.new()
	transport.response = _http_response(200, {
		"choices": [{"finish_reason": "stop", "message": {"content": JSON.stringify(decision)}}],
	})
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-kimi-key",
		"model": "kimi-k2.6",
		"thinking_type": "enabled",
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", _model_input("kimi-k2-thinking"), collector.collect)
	_expect_equal(collector.values, [{"ok": true, "decision": decision}], "K2.6 remains usable with thinking enabled")
	_expect_equal(transport.requests.size(), 1, "K2.6 thinking override sends one request")
	if transport.requests.size() == 1:
		_expect_equal(transport.requests[0].get("body", {}).get("thinking"), {"type": "enabled"}, "K2.6 accepts an explicit enabled thinking mode")


func _test_k2_7_highspeed_request(provider_script: Script) -> void:
	var decision := _decision("kimi-k2-7-highspeed")
	var transport := FakeTransport.new()
	transport.response = _http_response(200, {
		"choices": [{"finish_reason": "stop", "message": {"content": JSON.stringify(decision)}}],
	})
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-kimi-key",
		"model": "kimi-k2.7-code-highspeed",
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", _model_input("kimi-k2-7-highspeed"), collector.collect)
	_expect_equal(collector.values, [{"ok": true, "decision": decision}], "K2.7 Highspeed remains usable")
	_expect_equal(transport.requests.size(), 1, "K2.7 Highspeed sends one request")
	if transport.requests.size() == 1:
		var body := transport.requests[0].get("body", {}) as Dictionary
		_expect_equal(body.get("model"), "kimi-k2.7-code-highspeed", "K2.7 keeps only the Highspeed model id")
		_expect_equal(body.get("max_tokens"), 32768, "K2.7 Highspeed keeps the compatible token field")
		_expect(not body.has("thinking"), "K2.7 Highspeed relies on its required thinking default")
		_expect(not body.has("reasoning_effort"), "K2.7 Highspeed omits the K3 reasoning option")


func _test_configuration(provider_script: Script) -> void:
	var unsupported: RefCounted = provider_script.new(null, null, {
		"api_key": "temporary-kimi-key",
		"model": "kimi-unknown",
	})
	_expect_equal(
		unsupported.call("validate_configuration"),
		["Kimi Provider 不支持模型：kimi-unknown"],
		"shared adapter rejects models without a protocol profile",
	)
	var previous_project_key := OS.get_environment("KIMI-API-KEY")
	var previous_official_key := OS.get_environment("MOONSHOT_API_KEY")
	OS.unset_environment("KIMI-API-KEY")
	OS.unset_environment("MOONSHOT_API_KEY")
	OS.set_environment("KIMI-API-KEY", "project-environment-key")
	var project_key_provider: RefCounted = provider_script.new(null, null, {
		"env_file_path": "user://missing-kimi-test.env",
	})
	_expect_equal(project_key_provider.call("validate_configuration"), [], "project Kimi key environment name is accepted")
	OS.unset_environment("KIMI-API-KEY")
	OS.set_environment("MOONSHOT_API_KEY", "official-environment-key")
	var official_key_provider: RefCounted = provider_script.new(null, null, {
		"env_file_path": "user://missing-kimi-test.env",
	})
	_expect_equal(official_key_provider.call("validate_configuration"), [], "official Moonshot key environment name is accepted")
	_restore_environment("KIMI-API-KEY", previous_project_key)
	_restore_environment("MOONSHOT_API_KEY", previous_official_key)


func _test_unknown_model_never_reaches_transport(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _http_response(200, {
		"choices": [{"finish_reason": "stop", "message": {"content": "{}"}}],
	})
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-kimi-key",
		"model": "kimi-unknown",
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", _model_input("kimi-unknown"), collector.collect)
	_expect_equal(transport.requests.size(), 0, "unsupported Kimi model performs zero network requests")
	_expect_equal(collector.values, [{"ok": false, "errors": ["模型调用失败"]}], "unsupported model returns the neutral failure packet")
	var diagnostics := provider.call("get_diagnostics") as Array
	_expect_equal(diagnostics.size(), 1, "unsupported model records one diagnostic")
	if diagnostics.size() == 1:
		_expect_equal(diagnostics[0].get("error_type"), "configuration", "unsupported model is classified as configuration failure")
		_expect(_errors_contain(diagnostics[0].get("errors", []), "不支持模型"), "diagnostics retain the unsupported model reason")


func _test_invalid_k2_6_thinking_never_reaches_transport(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _http_response(200, {
		"choices": [{"finish_reason": "stop", "message": {"content": "{}"}}],
	})
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-kimi-key",
		"model": "kimi-k2.6",
		"thinking_type": "sometimes",
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", _model_input("kimi-invalid-thinking"), collector.collect)
	_expect_equal(transport.requests.size(), 0, "invalid K2.6 thinking mode performs zero network requests")
	_expect_equal(collector.values, [{"ok": false, "errors": ["模型调用失败"]}], "invalid thinking mode returns the neutral failure packet")
	var diagnostics := provider.call("get_diagnostics") as Array
	_expect_equal(diagnostics.size(), 1, "invalid thinking mode records one diagnostic")
	if diagnostics.size() == 1:
		_expect_equal(diagnostics[0].get("error_type"), "configuration", "invalid thinking mode is classified as configuration failure")
		_expect(_errors_contain(diagnostics[0].get("errors", []), "thinking_type"), "diagnostics retain the invalid thinking mode reason")


func _test_provider_error(provider_script: Script) -> void:
	var cases := [
		{"provider_type": "exceeded_current_quota_error", "expected_type": "billing", "retryable": false},
		{"provider_type": "rate_limit_reached_error", "expected_type": "rate_limit", "retryable": true},
	]
	for case: Dictionary in cases:
		var transport := FakeTransport.new()
		transport.response = _http_response(429, {
			"error": {"type": case["provider_type"], "message": "Kimi provider detail"},
		})
		var provider: RefCounted = provider_script.new(null, transport, {"api_key": "temporary-kimi-key"})
		var collector := ResultCollector.new()
		provider.call("request_decision", _model_input("kimi-error"), collector.collect)
		_expect_equal(collector.values, [{"ok": false, "errors": ["模型调用失败"]}], "provider error stays neutral at the Agent seam")
		var diagnostics := provider.call("get_diagnostics") as Array
		if diagnostics.size() == 1:
			_expect_equal(diagnostics[0].get("error_type"), case["expected_type"], "429 is classified by provider error type")
			_expect_equal(diagnostics[0].get("retryable"), case["retryable"], "429 retryability matches its cause")


func _test_truncated_completion(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _http_response(200, {
		"choices": [{
			"finish_reason": "length",
			"message": {"content": JSON.stringify({"decision_id": "incomplete"})},
		}],
	})
	var provider: RefCounted = provider_script.new(null, transport, {"api_key": "temporary-kimi-key"})
	var collector := ResultCollector.new()
	provider.call("request_decision", _model_input("kimi-truncated"), collector.collect)
	_expect_equal(collector.values, [{"ok": false, "errors": ["模型调用失败"]}], "truncated output never reaches the business contract")
	var diagnostics := provider.call("get_diagnostics") as Array
	if diagnostics.size() == 1:
		_expect_equal(diagnostics[0].get("error_type"), "output_truncated", "length finish reason is classified as truncation")


func _restore_environment(name: String, value: String) -> void:
	if value.is_empty():
		OS.unset_environment(name)
	else:
		OS.set_environment(name, value)


func _decision(decision_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {"action_id": "%s-stay" % decision_id, "type": "待着", "line": "先看看。"},
	}


func _model_input(decision_id: String) -> Dictionary:
	return {
		"initialization": {"me": {"resident_id": "resident-lin-lan", "attributes": {"name": "林岚"}}},
		"wake_packet": {"decision_id": decision_id, "snapshot": {}, "events": []},
		"messages": [
			{"role": "system", "content": "只返回合法的居民决定 JSON。"},
			{"role": "user", "content": "决定编号：%s" % decision_id},
		],
	}


func _http_response(status_code: int, payload: Dictionary) -> Dictionary:
	return {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": status_code,
		"headers": PackedStringArray(),
		"body": JSON.stringify(payload).to_utf8_buffer(),
	}
