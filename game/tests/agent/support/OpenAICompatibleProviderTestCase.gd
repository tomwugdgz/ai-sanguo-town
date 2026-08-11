class_name OpenAICompatibleProviderTestCase
extends "res://tests/agent/support/AgentTestCase.gd"


const ProviderDoubles := preload(
	"res://tests/agent/support/ProviderTestDoubles.gd"
)
const ResultCollector = ProviderDoubles.ResultCollector
const FakeTransport = ProviderDoubles.ImmediateTransport


func _success_response(decision_id: String) -> Dictionary:
	return _http_response(200, {
		"choices": [{
			"finish_reason": "stop",
			"message": {"content": JSON.stringify(_decision(decision_id))},
		}],
	})


func _http_response(status_code: int, body: Dictionary) -> Dictionary:
	return {
		"result": HTTPRequest.RESULT_SUCCESS,
		"status_code": status_code,
		"body": JSON.stringify(body).to_utf8_buffer(),
	}


func _decision(decision_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": "%s-stay" % decision_id,
			"type": "待着",
			"line": "先看看。",
		},
	}
