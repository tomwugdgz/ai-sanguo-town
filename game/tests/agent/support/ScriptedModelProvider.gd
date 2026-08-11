class_name ScriptedModelProvider
extends "res://agent/model/FakeModelProvider.gd"


var _queued_decisions: Array[Dictionary] = []
var _queued_json_responses: Array[Dictionary] = []
var _queued_failures: Array[Array] = []
var _pending: Array[Dictionary] = []
var _scripted_auto_complete := true


func get_provider_descriptor() -> Dictionary:
	return {
		"id": "fake",
		"label": "ScriptedModelProvider",
		"transport_label": "本地测试模型",
		"external": false,
	}


func queue_decision(decision: Dictionary) -> void:
	_queued_decisions.append(decision.duplicate(true))


func queue_json_response(response: Dictionary) -> void:
	_queued_json_responses.append(response.duplicate(true))


func queue_failure(errors: Array) -> void:
	_queued_failures.append(errors.duplicate())


func set_auto_complete(enabled: bool) -> void:
	_scripted_auto_complete = enabled


func complete_next(repeat_count: int = 1) -> bool:
	if _pending.is_empty():
		return false
	var pending: Dictionary = _pending.pop_front()
	var callback: Callable = pending["callback"]
	var result := (pending["result"] as Dictionary).duplicate(true)
	if bool(result.get("ok", false)) and typeof(result.get("decision")) == TYPE_DICTIONARY:
		_responses.append((result["decision"] as Dictionary).duplicate(true))
	for _index in max(1, repeat_count):
		callback.call(result.duplicate(true))
	return true


func request_decision(model_request: Dictionary, on_complete: Callable) -> void:
	_requests.append(model_request.duplicate(true))
	if not _queued_failures.is_empty():
		_pending.append({
			"result": {
				"ok": false,
				"errors": _queued_failures.pop_front().duplicate(),
			},
			"callback": on_complete,
		})
		if _scripted_auto_complete:
			complete_next()
		return
	var decision: Dictionary = {}
	if String(model_request.get("request_kind", "")) == "memory_organization":
		if _queued_json_responses.is_empty():
			decision = (model_request.get("old_memory", {}) as Dictionary).duplicate(true)
		else:
			decision = _queued_json_responses.pop_front()
	elif _queued_decisions.is_empty():
		decision = _build_default_decision(model_request)
	else:
		decision = _queued_decisions.pop_front()
	_pending.append({
		"result": {"ok": true, "decision": decision},
		"callback": on_complete,
	})
	if _scripted_auto_complete:
		complete_next()
