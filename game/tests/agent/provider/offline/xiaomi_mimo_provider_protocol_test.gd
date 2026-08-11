extends "res://tests/agent/support/OpenAICompatibleProviderTestCase.gd"


const PROVIDER_PATH := "res://agent/model/XiaomiMiMoModelProvider.gd"


func _initialize() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "Xiaomi MiMo Provider script loads")
	if provider_script != null:
		_test_text_request(provider_script)
		_test_visual_request(provider_script)
		_test_unknown_model_rejected(provider_script)
	_finish_suite("XIAOMI_MIMO_PROVIDER_PROTOCOL_PASS")


func _test_text_request(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("mimo-pro-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-xiaomi-key",
		"model": "mimo-v2.5-pro",
		"input_modalities": ["text"],
	})
	var collector := ResultCollector.new()
	provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "只返回决定 JSON"}]},
		collector.collect,
	)

	_expect_equal(collector.values, [{"ok": true, "decision": _decision("mimo-pro-decision")}], "MiMo Pro returns a decision")
	_expect_equal(transport.requests.size(), 1, "MiMo Pro sends one request")
	if transport.requests.size() == 1:
		var request := transport.requests[0]
		var body := request.get("body", {}) as Dictionary
		_expect_equal(request.get("url"), "https://api.xiaomimimo.com/v1/chat/completions", "MiMo uses the official endpoint")
		_expect_equal(body.get("model"), "mimo-v2.5-pro", "MiMo sends the selected model")
		_expect_equal(body.get("thinking"), {"type": "disabled"}, "MiMo disables thinking for stable Agent JSON")
		_expect_equal(body.get("response_format"), {"type": "json_object"}, "MiMo requests structured JSON")
		_expect_equal(body.get("max_completion_tokens"), 1024, "MiMo uses its documented output token field")
		_expect(not body.has("max_tokens"), "MiMo omits the legacy max_tokens field")
		_expect(not JSON.stringify(body).contains("temporary-xiaomi-key"), "Xiaomi key never enters the body")


func _test_visual_request(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("mimo-visual-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-xiaomi-key",
		"model": "mimo-v2.5",
		"input_modalities": ["text", "image"],
	})
	var collector := ResultCollector.new()
	var messages := [{
		"role": "user",
		"content": [
			{"type": "text", "text": "只返回决定 JSON"},
			{"type": "image_url", "image_url": {"url": "data:image/png;base64,AA=="}},
		],
	}]
	provider.call("request_decision", {"messages": messages}, collector.collect)

	_expect_equal(transport.requests.size(), 1, "MiMo V2.5 accepts declared image input")
	if transport.requests.size() == 1:
		_expect_equal(
			transport.requests[0].get("body", {}).get("messages"),
			messages,
			"MiMo visual messages pass through unchanged",
		)


func _test_unknown_model_rejected(provider_script: Script) -> void:
	var provider: RefCounted = provider_script.new(null, null, {
		"api_key": "temporary-xiaomi-key",
		"model": "mimo-unknown",
	})
	_expect(
		_errors_contain(provider.call("validate_configuration"), "不支持模型"),
		"Xiaomi rejects unknown models",
	)
