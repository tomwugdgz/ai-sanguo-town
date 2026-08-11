class_name TownSessionRuntimeGate
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
var _runtime: Node
var _active: Dictionary = {}
var _sequence := 0
var _generation := 1
var _last_ended_token := ""


func configure(runtime_value: Variant) -> Dictionary:
	if not _active.is_empty():
		return _failure("SESSION_SAVE_BUSY", true)
	if not runtime_value is Node or not is_instance_valid(runtime_value):
		return _failure("SESSION_SAVE_GATE_INVALID", false)
	_runtime = runtime_value as Node
	_last_ended_token = ""
	return _success()


func begin_session_transaction(
	kind_value: Variant,
	context_value: Variant,
) -> Dictionary:
	if _runtime == null or not is_instance_valid(_runtime):
		return _failure("SESSION_SAVE_GATE_INVALID", false)
	if not _active.is_empty():
		return _failure("SESSION_SAVE_BUSY", true)
	if (
		not kind_value is String
		or not ["save", "restore"].has(kind_value)
		or not context_value is Dictionary
	):
		return _failure("SESSION_SAVE_GATE_INVALID", false)
	var kind := kind_value as String
	var context := context_value as Dictionary
	_sequence += 1
	var token := "session-%s-g%d-t%d" % [kind, _generation, _sequence]
	_active = {
		"token": token,
		"kind": kind,
		"context": context.duplicate(true),
		"generation": _generation,
		"process": _runtime.is_processing(),
		"physics": _runtime.is_physics_processing(),
		"input": _runtime.is_processing_input(),
		"unhandledInput": _runtime.is_processing_unhandled_input(),
	}
	_runtime.set_process(false)
	_runtime.set_physics_process(false)
	_runtime.set_process_input(false)
	_runtime.set_process_unhandled_input(false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"token": token,
		"generation": _generation,
	}


func validate_session_transaction(token_value: Variant) -> Dictionary:
	if not token_value is String or (token_value as String).is_empty():
		return _failure("SESSION_SAVE_GATE_STALE", false)
	var token := token_value as String
	if (
		_active.is_empty()
		or String(_active.get("token", "")) != token
		or _runtime == null
		or not is_instance_valid(_runtime)
		or int(_active.get("generation", 0)) != _generation
	):
		return _failure("SESSION_SAVE_GATE_STALE", false)
	if (
		_runtime.is_processing()
		or _runtime.is_physics_processing()
		or _runtime.is_processing_input()
		or _runtime.is_processing_unhandled_input()
	):
		return _failure("SESSION_SAVE_GATE_STALE", false)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"token": token,
		"generation": int(_active.get("generation", 0)),
	}


func end_session_transaction(token_value: Variant) -> Dictionary:
	if not token_value is String or (token_value as String).is_empty():
		return _failure("SESSION_SAVE_GATE_STALE", false)
	var token := token_value as String
	if _active.is_empty():
		if token == _last_ended_token:
			return {
				"ok": true,
				"changed": false,
				"errorCode": "",
				"retryable": false,
			}
		return _failure("SESSION_SAVE_GATE_STALE", false)
	if String(_active.get("token", "")) != token:
		return _failure("SESSION_SAVE_GATE_STALE", false)
	var ended_generation := int(_active.get("generation", 0))
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.set_process(bool(_active.get("process", true)))
		_runtime.set_physics_process(bool(_active.get("physics", true)))
		_runtime.set_process_input(bool(_active.get("input", true)))
		_runtime.set_process_unhandled_input(
			bool(_active.get("unhandledInput", true)),
		)
	else:
		_active.clear()
		_last_ended_token = ""
		return _failure("SESSION_SAVE_GATE_INVALID", false)
	_active.clear()
	_last_ended_token = token if ended_generation == _generation else ""
	return {
		"ok": true,
		"changed": true,
		"errorCode": "",
		"retryable": false,
	}


func advance_generation() -> int:
	_generation += 1
	_last_ended_token = ""
	return _generation


func get_generation() -> int:
	return _generation


func _success() -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false}


func _failure(error_code: String, retryable: bool) -> Dictionary:
	return RESULT_SHAPES.failure_retryable(error_code, retryable)
