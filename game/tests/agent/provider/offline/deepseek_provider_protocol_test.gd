extends "res://tests/agent/support/AgentTestCase.gd"

const ProviderDoubles := preload("res://tests/agent/support/ProviderTestDoubles.gd")
const ResultCollector = ProviderDoubles.ResultCollector
const FakeTransport = ProviderDoubles.ImmediateTransport
const ManualTransport = ProviderDoubles.ManualTransport


const PROVIDER_PATH := "res://agent/model/DeepSeekModelProvider.gd"


class MutatingCollector:
	func collect(value: Dictionary) -> void:
		if typeof(value.get("decision")) == TYPE_DICTIONARY:
			(value["decision"] as Dictionary)["decision_id"] = "mutated-callback"


func _initialize() -> void:
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "DeepSeek provider script must exist")
	if provider_script != null:
		_test_valid_json(provider_script)
		_test_env_file_fallback(provider_script)
		_test_empty_content(provider_script)
		_test_authentication_failure(provider_script)
		_test_out_of_order_diagnostics(provider_script)
		_test_trace_snapshots_are_isolated(provider_script)
	_finish_suite("DEEPSEEK_PROVIDER_PROTOCOL_PASS")


func _test_valid_json(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	var decision := {
		"decision_id": "deepseek-1",
		"handling": "replace_current",
		"action": {
			"action_id": "deepseek-1-stay",
			"type": "待着",
			"line": "雨还没停，先在长椅边等等",
		},
	}
	transport.queue_response(_http_response(200, {
		"id": "chatcmpl-test",
		"model": "deepseek-v4-flash",
		"choices": [{
			"index": 0,
			"finish_reason": "stop",
			"message": {"role": "assistant", "content": JSON.stringify(decision)},
		}],
		"usage": {"prompt_tokens": 321, "completion_tokens": 64, "total_tokens": 385},
	}))
	var provider: RefCounted = provider_script.new(null, transport, {
		"api_key": "temporary-test-key",
		"model": "deepseek-v4-flash",
	})
	var collector := ResultCollector.new()
	var model_request := _model_input("deepseek-1")
	provider.call("request_decision", model_request, collector.collect)

	_expect_equal(collector.values.size(), 1, "valid response completes exactly once")
	if collector.values.size() == 1:
		_expect_equal(collector.values[0], {"ok": true, "decision": decision}, "provider returns a parsed decision result")
		_expect_equal(provider.call("get_results"), collector.values, "provider records the exact callback result")
	_expect_equal(transport.requests.size(), 1, "provider sends one HTTP request")
	if transport.requests.size() == 1:
		var request: Dictionary = transport.requests[0]
		var body := request["body"] as Dictionary
		_expect_equal(request["url"], "https://api.deepseek.com/chat/completions", "provider uses the official chat endpoint")
		_expect_equal(body.get("model"), "deepseek-v4-flash", "provider uses the configured current model")
		_expect_equal(body.get("response_format"), {"type": "json_object"}, "provider requests JSON output")
		_expect_equal(body.get("thinking"), {"type": "disabled"}, "provider keeps main's disabled thinking mode")
		_expect(not body.has("reasoning_effort"), "provider keeps main's DeepSeek request parameters")
		_expect_equal(body.get("messages"), model_request.get("messages"), "provider sends the compiled messages without rebuilding the prompt")
		_expect(not JSON.stringify(body).contains("temporary-test-key"), "API key never enters the request body")
	var diagnostics: Array = provider.call("get_diagnostics")
	_expect_equal(diagnostics.size(), 1, "provider records one diagnostic entry")
	if diagnostics.size() == 1:
		_expect_equal(diagnostics[0].get("finish_reason"), "stop", "diagnostics records finish reason")
		_expect_equal(diagnostics[0].get("usage", {}).get("total_tokens"), 385, "diagnostics records token usage")
		_expect(not JSON.stringify(diagnostics[0]).contains("temporary-test-key"), "diagnostics never records the API key")


func _test_env_file_fallback(provider_script: Script) -> void:
	var previous_api_key := OS.get_environment("DEEPSEEK_API_KEY")
	OS.unset_environment("DEEPSEEK_API_KEY")
	var env_path := OS.get_temp_dir().path_join("deepseek-provider-test.env")
	var env_file := FileAccess.open(env_path, FileAccess.WRITE)
	_expect(env_file != null, "test env file can be created")
	if env_file == null:
		_restore_api_key(previous_api_key)
		return
	env_file.store_string("# local development key\nexport DEEPSEEK_API_KEY=\"env-file-test-key\"\n")
	env_file.close()

	var transport := FakeTransport.new()
	transport.queue_response(_http_response(200, _success_envelope(
		"env-file-response",
		{
			"decision_id": "env-file-1",
			"handling": "replace_current",
			"action": {"action_id": "env-file-stay", "type": "待着", "line": "先等等"},
		},
	)))
	var provider: RefCounted = provider_script.new(null, transport, {"env_file_path": env_path})
	var collector := ResultCollector.new()
	provider.call("request_decision", _model_input("env-file-1"), collector.collect)

	_expect_equal(collector.values.size(), 1, "env file key completes the request")
	if collector.values.size() == 1:
		_expect_equal(collector.values[0].get("ok"), true, "env file key is accepted as a fallback")
	_expect_equal(transport.requests.size(), 1, "env file key starts one HTTP request")
	if transport.requests.size() == 1:
		var headers: PackedStringArray = transport.requests[0]["headers"]
		_expect(headers.has("Authorization: Bearer env-file-test-key"), "env file key reaches only the Authorization header")
	_expect(not JSON.stringify(provider.call("get_debug_snapshot")).contains("env-file-test-key"), "env file key never enters debug records")

	DirAccess.remove_absolute(env_path)
	_restore_api_key(previous_api_key)


func _restore_api_key(previous_api_key: String) -> void:
	if previous_api_key.is_empty():
		OS.unset_environment("DEEPSEEK_API_KEY")
	else:
		OS.set_environment("DEEPSEEK_API_KEY", previous_api_key)


func _test_empty_content(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.queue_response(_http_response(200, {
		"choices": [{"finish_reason": "stop", "message": {"content": ""}}],
	}))
	var provider: RefCounted = provider_script.new(null, transport, {"api_key": "test-key"})
	var collector := ResultCollector.new()
	provider.call("request_decision", _model_input("empty-1"), collector.collect)
	_expect_equal(collector.values.size(), 1, "empty response completes exactly once")
	if collector.values.size() == 1:
		_expect_equal(collector.values[0].get("ok"), false, "empty response is a provider failure")
		_expect_equal(collector.values[0].get("errors"), ["模型调用失败"], "world-facing failure stays provider-neutral")
	var diagnostics: Array = provider.call("get_diagnostics")
	if diagnostics.size() == 1:
		_expect(_errors_contain(diagnostics[0].get("errors", []), "空"), "diagnostics keeps the detailed empty-response failure")


func _test_authentication_failure(provider_script: Script) -> void:
	var transport := FakeTransport.new()
	transport.queue_response(_http_response(401, {
		"error": {"message": "Authentication Fails", "type": "authentication_error"},
	}))
	var provider: RefCounted = provider_script.new(null, transport, {"api_key": "test-key"})
	var collector := ResultCollector.new()
	provider.call("request_decision", _model_input("auth-1"), collector.collect)
	_expect_equal(collector.values.size(), 1, "HTTP error completes exactly once")
	if collector.values.size() == 1:
		_expect_equal(collector.values[0].get("ok"), false, "HTTP 401 is a provider failure")
		_expect_equal(collector.values[0].get("errors"), ["模型调用失败"], "HTTP details do not enter the world-facing result")
	var diagnostics: Array = provider.call("get_diagnostics")
	if diagnostics.size() == 1:
		_expect_equal(diagnostics[0].get("error_type"), "authentication", "HTTP 401 is classified for the debug UI")
		_expect(_errors_contain(diagnostics[0].get("errors", []), "401"), "diagnostics keeps the HTTP status")
		_expect_equal(diagnostics[0].get("provider_error_message"), "Authentication Fails", "diagnostics keeps the provider message")


func _test_out_of_order_diagnostics(provider_script: Script) -> void:
	var transport := ManualTransport.new()
	var provider: RefCounted = provider_script.new(null, transport, {"api_key": "test-key"})
	var first := ResultCollector.new()
	var second := ResultCollector.new()
	provider.call("request_decision", _model_input("parallel-first"), first.collect)
	provider.call("request_decision", _model_input("parallel-second"), second.collect)
	transport.complete(1, _http_response(200, _success_envelope(
		"response-second",
		{
			"decision_id": "parallel-second",
			"handling": "replace_current",
			"action": {"action_id": "parallel-second-stay", "type": "待着", "line": "第二个"},
		},
	)))
	transport.complete(0, _http_response(200, _success_envelope(
		"response-first",
		{
			"decision_id": "parallel-first",
			"handling": "replace_current",
			"action": {"action_id": "parallel-first-stay", "type": "待着", "line": "第一个"},
		},
	)))
	var diagnostics: Array = provider.call("get_diagnostics")
	_expect_equal(diagnostics.size(), 2, "both out-of-order responses are recorded")
	if diagnostics.size() == 2:
		_expect_equal(diagnostics[0].get("raw_response", {}).get("id"), "response-second", "second response completes first")
		_expect(String(diagnostics[0].get("request", {}).get("body", {}).get("messages", [])[1].get("content", "")).contains("parallel-second"), "second response stays paired with its own request")
		_expect_equal(diagnostics[1].get("raw_response", {}).get("id"), "response-first", "first response completes second")
		_expect(String(diagnostics[1].get("request", {}).get("body", {}).get("messages", [])[1].get("content", "")).contains("parallel-first"), "first response stays paired with its own request")


func _test_trace_snapshots_are_isolated(provider_script: Script) -> void:
	var transport := ManualTransport.new()
	var provider: RefCounted = provider_script.new(null, transport, {"api_key": "test-key"})
	var collector := MutatingCollector.new()
	var model_request := _model_input("trace-original")
	provider.call("request_decision", model_request, collector.collect)
	(model_request["messages"] as Array)[1]["content"] = "mutated-input"
	transport.complete(0, _http_response(200, _success_envelope(
		"trace-response",
		{
			"decision_id": "trace-original",
			"handling": "replace_current",
			"action": {"action_id": "trace-stay", "type": "待着", "line": "保持原样"},
		},
	)))
	var snapshot := provider.call("get_debug_snapshot") as Dictionary
	var model_requests := snapshot.get("model_requests", []) as Array
	var requests := snapshot.get("requests", []) as Array
	var diagnostics := snapshot.get("diagnostics", []) as Array
	var results := snapshot.get("results", []) as Array
	_expect(
		String((model_requests[0] as Dictionary).get("messages", [])[1].get("content", "")).contains("trace-original"),
		"trace keeps its model request snapshot after the caller mutates the input",
	)
	_expect(
		String((requests[0] as Dictionary).get("body", {}).get("messages", [])[1].get("content", "")).contains("trace-original"),
		"trace keeps its provider request snapshot after the caller mutates the input",
	)
	_expect_equal(
		(diagnostics[0] as Dictionary).get("parsed_decision", {}).get("decision_id"),
		"trace-original",
		"callback mutation does not alter diagnostic history",
	)
	_expect_equal(
		(results[0] as Dictionary).get("decision", {}).get("decision_id"),
		"trace-original",
		"callback mutation does not alter result history",
	)
	(snapshot["responses"] as Array)[0]["id"] = "mutated-snapshot"
	(snapshot["diagnostics"] as Array)[0]["parsed_decision"]["decision_id"] = "mutated-snapshot"
	var fresh_snapshot := provider.call("get_debug_snapshot") as Dictionary
	_expect_equal(
		(fresh_snapshot["responses"] as Array)[0].get("id"),
		"trace-response",
		"returned response snapshots cannot mutate provider history",
	)
	_expect_equal(
		(fresh_snapshot["results"] as Array)[0].get("decision", {}).get("decision_id"),
		"trace-original",
		"returned diagnostic snapshots cannot mutate shared result history",
	)


func _success_envelope(response_id: String, decision: Dictionary) -> Dictionary:
	return {
		"id": response_id,
		"model": "deepseek-v4-flash",
		"choices": [{
			"finish_reason": "stop",
			"message": {"role": "assistant", "content": JSON.stringify(decision)},
		}],
		"usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
	}


func _http_response(status_code: int, value: Dictionary) -> Dictionary:
	return {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": status_code,
		"headers": PackedStringArray(),
		"body": JSON.stringify(value).to_utf8_buffer(),
	}


func _model_input(decision_id: String) -> Dictionary:
	return {
		"messages": [
			{"role": "system", "content": "resident baseline; return one JSON decision"},
			{"role": "user", "content": "current wake packet: %s" % decision_id},
		],
		"initialization": {
			"me": {
				"resident_id": "resident-lin-lan",
				"attributes": {
					"name": "林岚",
					"gender": "男",
					"age": 32,
					"desire": "把手艺做好",
					"personality": "话少，慢热",
					"speech": "说话简短",
				},
				"social_state": {"home": "林岚家", "job": "木匠", "workplace": "工作坊"},
			},
			"residents": [{"resident_id": "resident-tang-xiao-man", "name": "唐小满", "gender": "女", "age": 29, "job": "摆杂货摊的", "home": "唐小满家", "workplace": "市集"}],
			"places": [{"name": "广场", "type": "公共地点", "owner": null, "owner_resident_id": null, "summary": "碰头和闲坐的地方"}],
		},
		"wake_packet": {
			"decision_id": decision_id,
			"snapshot": {
				"time": {"day": 1, "clock": "08:10", "period": "上午"},
				"weather": "小雨",
				"me": {"doing": "站在广场上", "current_action": null, "body": {"困": "不困", "饿": "不饿", "累": "不累"}},
				"nearby": [{"resident_id": "resident-tang-xiao-man", "name": "唐小满", "doing": "站在公告栏旁边"}],
				"place": {"name": "广场", "props": [{"name": "长椅", "verbs": ["歇着"]}]},
				"conversation": null,
			},
			"events": [],
			"action_results": [],
		},
	}
