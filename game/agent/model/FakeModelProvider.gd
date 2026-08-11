class_name FakeModelProvider
extends "res://agent/model/ModelProvider.gd"


var _requests: Array[Dictionary] = []
var _responses: Array[Dictionary] = []
var _config: Dictionary
var _queued_results: Array[Dictionary] = []
var _pending_completions: Array[Dictionary] = []
var _auto_complete := true

const DEFAULT_WAIT_LINE := "先看看周围的情况"
const DEFAULT_REPLY_SAY := "我听着呢。"
const DEFAULT_REPLY_NARRATION := "轻轻点了点头"


func _init(config: Dictionary = {}) -> void:
	_config = config.duplicate(true)


func get_provider_descriptor() -> Dictionary:
	return {
		"id": "fake",
		"label": "FakeModelProvider",
		"transport_label": "本地模型",
		"external": false,
		"model_id": String(_config.get("model", "fake")),
		"input_modalities": _input_modalities(),
	}


func _input_modalities() -> Array:
	var configured: Variant = _config.get("input_modalities", ["text", "image"])
	if typeof(configured) != TYPE_ARRAY:
		return ["text", "image"]
	return (configured as Array).duplicate()


func get_requests() -> Array[Dictionary]:
	return _requests.duplicate(true)


func get_responses() -> Array[Dictionary]:
	return _responses.duplicate(true)


func queue_decision(decision: Dictionary) -> void:
	_queued_results.append({
		"ok": true,
		"decision": decision.duplicate(true),
	})


func queue_json_response(value: Dictionary) -> void:
	queue_decision(value)


func queue_failure(errors: Array) -> void:
	_queued_results.append({
		"ok": false,
		"errors": errors.duplicate(true),
	})


func set_auto_complete(enabled: bool) -> void:
	_auto_complete = enabled


func complete_next(repeat_count := 1) -> bool:
	if _pending_completions.is_empty():
		return false
	var pending := _pending_completions.pop_front() as Dictionary
	var callback := pending.get("callback", Callable()) as Callable
	if not callback.is_valid():
		return false
	var result := pending.get("result", {}) as Dictionary
	for _index in maxi(1, int(repeat_count)):
		callback.call(result.duplicate(true))
	return true


func request_decision(model_request: Dictionary, on_complete: Callable) -> void:
	_requests.append(model_request.duplicate(true))
	var result: Dictionary
	if not _queued_results.is_empty():
		result = (_queued_results.pop_front() as Dictionary).duplicate(true)
	else:
		result = {
			"ok": true,
			"decision": _default_result_value(model_request),
		}
	if bool(result.get("ok", false)):
		_responses.append(
			(result.get("decision", {}) as Dictionary).duplicate(true),
		)
	if _auto_complete:
		if on_complete.is_valid():
			on_complete.call(result.duplicate(true))
		return
	_pending_completions.append({
		"callback": on_complete,
		"result": result.duplicate(true),
	})


func _default_result_value(model_request: Dictionary) -> Dictionary:
	var request_kind := String(model_request.get("request_kind", ""))
	if request_kind == "memory_organization":
		return (model_request.get("old_memory", {}) as Dictionary).duplicate(true)
	if request_kind == "avatar_memory_organization":
		var old_avatar := model_request.get("old_memory", {}) as Dictionary
		return {
			"summary": String(old_avatar.get("summary", "")),
			"memories": (
				old_avatar.get("memories", []) as Array
			).duplicate(true),
			"open_loops": (
				old_avatar.get("open_loops", []) as Array
			).duplicate(true),
			"message_updates": [],
		}
	if request_kind == "departure_message":
		return {"write": false, "message": ""}
	return _build_default_decision(model_request)


func _build_default_decision(model_request: Dictionary) -> Dictionary:
	var wake_packet := model_request.get("wake_packet", {}) as Dictionary
	var decision_id := String(wake_packet.get("decision_id", "fake-decision"))
	var action_id := _next_default_action_id(decision_id, wake_packet)
	var action := {
		"action_id": action_id,
		"type": "待着",
		"line": DEFAULT_WAIT_LINE,
	}
	var activities := (
		(wake_packet.get("snapshot", {}) as Dictionary)
		.get("place", {})
		.get("activities", []) as Array
	)
	if not activities.is_empty() and activities[0] is Dictionary:
		var activity_id := String(
			(activities[0] as Dictionary).get("activity_id", "")
		)
		if not activity_id.is_empty():
			action = {
				"action_id": action_id,
				"type": "做活动",
				"activity_id": activity_id,
				"line": "做点眼前能做的事",
			}
	var conversation: Variant = (wake_packet.get("snapshot", {}) as Dictionary).get("conversation")
	if _requires_reply(wake_packet) and typeof(conversation) == TYPE_DICTIONARY:
		action = {
			"action_id": action_id,
			"type": "答话",
			"conversation_id": String((conversation as Dictionary).get("conversation_id", "")),
			"say": DEFAULT_REPLY_SAY,
			"narration": DEFAULT_REPLY_NARRATION,
			"photos": [],
			"end": false,
		}
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": action,
	}


func _next_default_action_id(decision_id: String, wake_packet: Dictionary) -> String:
	var base_id := "fake-%s" % decision_id
	var candidate := base_id
	var suffix := 2
	var current_action: Variant = (wake_packet.get("snapshot", {}) as Dictionary) \
		.get("me", {}).get("current_action")
	var current_action_id := ""
	if typeof(current_action) == TYPE_DICTIONARY:
		current_action_id = String((current_action as Dictionary).get("action_id", ""))
	while candidate == current_action_id or _response_has_action_id(candidate):
		candidate = "%s-%d" % [base_id, suffix]
		suffix += 1
	return candidate


func _response_has_action_id(action_id: String) -> bool:
	for response: Dictionary in _responses:
		var action: Variant = response.get("action")
		if typeof(action) == TYPE_DICTIONARY and String((action as Dictionary).get("action_id", "")) == action_id:
			return true
	return false


func _requires_reply(wake_packet: Dictionary) -> bool:
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	var conversation: Variant = snapshot.get("conversation")
	if typeof(conversation) != TYPE_DICTIONARY:
		return false
	var conversation_id := String((conversation as Dictionary).get("conversation_id", ""))
	var requires_reply := false
	for value: Variant in wake_packet.get("events", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event := value as Dictionary
		if String(event.get("conversation_id", "")) != conversation_id:
			continue
		if event.get("type") == "搭话":
			requires_reply = bool(event.get("response_required", true))
		elif event.get("type") == "对方答话":
			requires_reply = true
		elif event.get("type") == "对话结束":
			requires_reply = false
	return requires_reply
