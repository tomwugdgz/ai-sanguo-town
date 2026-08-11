extends "res://tests/agent/support/AgentTestCase.gd"

const ProviderDoubles := preload("res://tests/agent/support/ProviderTestDoubles.gd")
const ResultCollector = ProviderDoubles.ResultCollector
const FakeTransport = ProviderDoubles.ImmediateTransport


const PROVIDER_PATH := "res://agent/model/ZhipuGLMModelProvider.gd"


func _initialize() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "GLM provider script loads")
	if provider_script != null:
		_test_request(provider_script)
		_test_visual_request(provider_script)
	_finish_suite("ZHIPU_GLM_PROVIDER_PROTOCOL_PASS")


func _test_request(provider_script: Script) -> void:
	var decision := {
		"decision_id": "glm-decision",
		"handling": "replace_current",
		"action": {"action_id": "glm-stay", "type": "待着", "line": "先看看。"},
	}
	var transport := FakeTransport.new()
	transport.response = {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"headers": PackedStringArray(),
		"body": JSON.stringify({
			"choices": [{"finish_reason": "stop", "message": {"content": JSON.stringify(decision)}}],
		}).to_utf8_buffer(),
	}
	var provider: RefCounted = provider_script.new(null, transport, {"api_key": "temporary-glm-key"})
	var collector := ResultCollector.new()
	provider.call("request_decision", {
		"initialization": {"me": {"resident_id": "resident-lin-lan", "attributes": {"name": "林岚"}}},
		"wake_packet": {"decision_id": "glm-decision", "snapshot": {}, "events": []},
		"messages": [
			{"role": "system", "content": "只返回合法的居民决定 JSON。"},
			{"role": "user", "content": "决定编号：glm-decision"},
		],
	}, collector.collect)
	_expect_equal(collector.values, [{"ok": true, "decision": decision}], "GLM response uses the shared result seam")
	_expect_equal(transport.requests.size(), 1, "GLM sends one request")
	if transport.requests.size() == 1:
		var request := transport.requests[0]
		var body := request.get("body", {}) as Dictionary
		_expect_equal(request.get("url"), "https://open.bigmodel.cn/api/paas/v4/chat/completions", "GLM uses the official endpoint")
		_expect_equal(body.get("model"), "glm-5.2", "GLM uses the configured model")
		_expect_equal(body.get("thinking"), {"type": "disabled"}, "GLM thinking is disabled by default")
		_expect_equal(body.get("response_format"), {"type": "json_object"}, "GLM requests JSON output")
		_expect(not JSON.stringify(body).contains("temporary-glm-key"), "GLM key never enters the body")


func _test_visual_request(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.response = {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": 200,
		"body": JSON.stringify({
			"choices": [{"finish_reason": "stop", "message": {"content": "{}"}}],
		}).to_utf8_buffer(),
	}
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-glm-key",
		"model": "glm-5v-turbo",
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
	if transport.requests.size() == 1:
		var body := transport.requests[0].get("body", {}) as Dictionary
		_expect_equal(body.get("messages"), messages, "GLM visual content passes through unchanged")
		_expect_equal(body.get("thinking"), {"type": "disabled"}, "GLM visual model supports conservative thinking mode")
		_expect(not body.has("response_format"), "GLM visual model omits the text-only JSON Mode field")
