extends "res://tests/agent/support/OpenAICompatibleProviderTestCase.gd"


const PROVIDER_PATH := "res://agent/model/AlibabaBailianModelProvider.gd"


func _initialize() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "阿里百炼 Provider 脚本可加载")
	if provider_script != null:
		_test_bailian_request(provider_script)
		_test_bailian_open_model_request(provider_script)
		_test_bailian_quota_error(provider_script)
	_finish_suite("ALIBABA_BAILIAN_PROVIDER_PROTOCOL_PASS")


func _test_bailian_request(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("bailian-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-bailian-key",
		"model": "qwen3.7-plus",
		"input_modalities": ["text", "image"],
	})
	var collector := ResultCollector.new()
	var messages := [{
		"role": "user",
		"content": [
			{"type": "image_url", "image_url": {"url": "https://example.invalid/image.png"}},
			{"type": "text", "text": "只返回决定 JSON"},
		],
	}]
	provider.call("request_decision", {"messages": messages}, collector.collect)

	_expect_equal(collector.values, [{"ok": true, "decision": _decision("bailian-decision")}], "Bailian returns a neutral decision")
	_expect_equal(transport.requests.size(), 1, "Bailian sends one request")
	if transport.requests.size() == 1:
		var request := transport.requests[0]
		var body := request.get("body", {}) as Dictionary
		_expect_equal(request.get("url"), "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "Bailian uses the Beijing compatible endpoint")
		_expect_equal(body.get("model"), "qwen3.7-plus", "Bailian sends the selected model")
		_expect_equal(body.get("messages"), messages, "Bailian visual content passes through unchanged")
		_expect_equal(body.get("enable_thinking"), false, "Bailian uses conservative non-thinking mode")
		_expect_equal(body.get("response_format"), {"type": "json_object"}, "Bailian requests JSON output where supported")
		_expect(not body.has("max_tokens"), "Bailian omits an unsupported legacy token field")
		_expect(not JSON.stringify(body).contains("temporary-bailian-key"), "Bailian key never enters the body")
	_expect(not JSON.stringify(provider.call("get_debug_snapshot")).contains("temporary-bailian-key"), "Bailian key never enters debug records")

func _test_bailian_open_model_request(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _success_response("bailian-open-decision")
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-bailian-key",
		"model": "qwen3.5-397b-a17b",
	})
	var collector := ResultCollector.new()
	provider.call("request_decision", {"messages": [{"role": "user", "content": "决定 JSON"}]}, collector.collect)
	_expect_equal(transport.requests.size(), 1, "Bailian open model sends one request")
	if transport.requests.size() == 1:
		var body := transport.requests[0].get("body", {}) as Dictionary
		_expect_equal(body.get("enable_thinking"), false, "Bailian open models keep conservative non-thinking mode")
		_expect_equal(body.get("response_format"), {"type": "json_object"}, "Bailian open models use their documented JSON Mode")

func _test_bailian_quota_error(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = _http_response(429, {
		"error": {
			"code": "Throttling.AllocationQuota",
			"type": "insufficient_quota",
			"message": "Allocation quota reached",
		},
	})
	var provider: RefCounted = provider_script.new(null, transport, {"api_key": "temporary-bailian-key"})
	var collector := ResultCollector.new()
	provider.call("request_decision", {"messages": [{"role": "user", "content": "决定 JSON"}]}, collector.collect)
	var diagnostics := provider.call("get_diagnostics") as Array
	_expect_equal(diagnostics.size(), 1, "Bailian provider errors create one diagnostic")
	if diagnostics.size() == 1:
		_expect_equal(diagnostics[0].get("error_type"), "rate_limit", "Bailian allocation quota is retryable rate limiting")
		_expect_equal(diagnostics[0].get("retryable"), true, "Bailian allocation quota can be retried")
		_expect_equal(diagnostics[0].get("provider_error_code"), "Throttling.AllocationQuota", "Bailian error code is retained for diagnostics")
