class_name TownSessionBootstrap
extends RefCounted


signal view_model_changed(view_model: Dictionary)
signal operation_completed(result: Dictionary)

const DRAFT := preload("res://world/presentation/session/TownNewGameDraft.gd")
const COMPILER := preload("res://world/presentation/session/TownNewGameOpeningCompiler.gd")
const WORLD := preload("res://world/runtime/TownWorldRuntime.gd")
const OPENING := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const PROVIDER_METHODS: Array[String] = [
	"get_health_snapshot",
	"list_available_models",
	"validate_resident_bindings",
	"check_entry_availability",
]
const GATEWAY_METHODS: Array[String] = [
	"configure_session",
	"discard_unpublished_new_game",
	"bind_world",
	"pump",
	"get_connected_resident_names",
	"get_errors",
]
const RUNTIME_METHODS: Array[String] = [
	"configure_agent_gateway",
	"configure_session",
]

var _revision := 1
var _request_sequence := 0
var _pending: Dictionary = {}
var _last_data: Dictionary = {
	"mode": "new_game",
	"sessionId": "",
	"residentCount": 0,
	"providerStatus": "unchecked",
	"canEnterTown": false,
}
var _operation: Dictionary = {
	"requestId": "",
	"intent": "",
	"status": "idle",
}
var _error: Variant = null


func get_view_model() -> Dictionary:
	return {
		"scope": "session",
		"status": _status(),
		"revision": _revision,
		"data": _last_data.duplicate(true),
		"actions": {
			"newGame": {
				"intent": "session.new_game",
				"enabled": _pending.is_empty(),
				"reason": "" if _pending.is_empty() else "SESSION_BOOTSTRAP_BUSY",
			},
		},
		"operation": _operation.duplicate(true),
		"error": _error if _error == null else (_error as Dictionary).duplicate(true),
	}


func begin_new_game(
	draft: Dictionary,
	world_data: Dictionary,
	opening_config: Dictionary,
	provider_service: Object,
	gateway: Node,
	runtime: Node,
	options: Dictionary = {},
	on_complete: Callable = Callable(),
) -> Dictionary:
	return _begin_new_game(
		draft,
		world_data,
		opening_config,
		_agent_bindings_from_opening(draft, world_data, opening_config),
		provider_service,
		gateway,
		runtime,
		options,
		on_complete,
	)


func begin_new_game_from_catalog(
	draft: Dictionary,
	world_data: Dictionary,
	resident_catalog: Dictionary,
	provider_service: Object,
	gateway: Node,
	runtime: Node,
	options: Dictionary = {},
	on_complete: Callable = Callable(),
) -> Dictionary:
	if not _pending.is_empty():
		return _failure("SESSION_BOOTSTRAP_BUSY", false)
	var compiled := COMPILER.compile(draft, world_data, resident_catalog) as Dictionary
	if not bool(compiled.get("ok", false)):
		_request_sequence += 1
		return _finish_immediate(
			"session-new-game-%d" % _request_sequence,
			compiled,
			on_complete,
		)
	return _begin_new_game(
		draft,
		world_data,
		compiled.get("openingConfig", {}) as Dictionary,
		compiled.get("residentBindings", []) as Array[Dictionary],
		provider_service,
		gateway,
		runtime,
		options,
		on_complete,
	)


func _begin_new_game(
	draft: Dictionary,
	world_data: Dictionary,
	opening_config: Dictionary,
	bindings: Array[Dictionary],
	provider_service: Object,
	gateway: Node,
	runtime: Node,
	options: Dictionary,
	on_complete: Callable,
) -> Dictionary:
	if not _pending.is_empty():
		return _failure("SESSION_BOOTSTRAP_BUSY", false)
	_request_sequence += 1
	var request_id := "session-new-game-%d" % _request_sequence
	var draft_validation := DRAFT.validate(draft)
	if not bool(draft_validation.get("ok", false)):
		return _finish_immediate(request_id, draft_validation, on_complete)
	var start_mode := String(options.get("worldStartMode", "formal"))
	if not ["development", "formal"].has(start_mode):
		return _finish_immediate(
			request_id,
			_failure("SESSION_WORLD_START_MODE_INVALID", false),
			on_complete,
		)
	var internal_playtest := bool(options.get("internalPlaytest", false))
	var internal_live_playtest := bool(options.get("internalLivePlaytest", false))
	if start_mode == "development" and not internal_playtest and not internal_live_playtest:
		return _finish_immediate(
			request_id,
			_failure("SESSION_DEVELOPMENT_MODE_NOT_EXPLICIT", false),
			on_complete,
		)
	var expected_bindings := _agent_bindings_from_opening(
		draft,
		world_data,
		opening_config,
	)
	if bindings != expected_bindings:
		return _finish_immediate(
			request_id,
			_failure(
				"SESSION_COMPILED_BINDINGS_MISMATCH",
				false,
				[{
					"expectedBindings": expected_bindings,
					"actualBindings": bindings,
				}],
			),
			on_complete,
		)
	var resident_names := _resident_names_from_bindings(bindings)
	var opening_names := _opening_resident_names(opening_config)
	if resident_names != opening_names:
		return _finish_immediate(
			request_id,
			_failure(
				"SESSION_OPENING_RESIDENT_SET_MISMATCH",
				false,
				[{
					"expectedResidentNames": resident_names,
					"actualResidentNames": opening_names,
				}],
			),
			on_complete,
		)
	var world_validator: RefCounted = WORLD.new()
	var startup := world_validator.call(
		"validate_startup",
		world_data,
		opening_config,
		start_mode == "formal",
		_resident_identities(bindings),
	) as Dictionary
	if not bool(startup.get("ok", false)):
		return _finish_immediate(
			request_id,
			{
				"ok": false,
				"errorCode": String(startup.get("errorCode", "WORLD_STARTUP_INVALID")),
				"retryable": bool(startup.get("retryable", false)),
				"errors": startup.get("errors", startup.get("issues", [])),
				"contentStatus": startup.get("contentStatus", {}),
			},
			on_complete,
		)
	if start_mode == "formal":
		var spawn_validation := world_validator.call(
			"validate_new_game_resident_spawns",
			world_data,
			opening_config,
		) as Dictionary
		if not bool(spawn_validation.get("ok", false)):
			return _finish_immediate(
				request_id,
				{
					"ok": false,
					"errorCode": String(
						spawn_validation.get(
							"errorCode",
							"WORLD_RESIDENT_SPAWN_INVALID",
						)
					),
					"retryable": bool(
						spawn_validation.get("retryable", false)
					),
					"errors": spawn_validation.get("errors", []),
				},
				on_complete,
			)
	var contract_error := _validate_contracts(provider_service, gateway, runtime)
	if not contract_error.is_empty():
		return _finish_immediate(request_id, contract_error, on_complete)
	var binding_validation := provider_service.call("validate_resident_bindings", bindings) as Dictionary
	if not bool(binding_validation.get("ok", false)):
		return _finish_immediate(request_id, binding_validation, on_complete)
	var session_id := String(options.get("sessionId", "")).strip_edges()
	if session_id.is_empty():
		return _finish_immediate(
			request_id,
			_failure("SESSION_ID_REQUIRED", false),
			on_complete,
		)
	var slot_id := String(options.get("slotId", "")).strip_edges()
	if slot_id.is_empty():
		return _finish_immediate(
			request_id,
			_failure("SESSION_SLOT_ID_REQUIRED", false),
			on_complete,
		)
	_pending = {
		"requestId": request_id,
		"draftRevision": int(draft.get("draftRevision", 0)),
		"bindings": bindings,
		"residentNames": resident_names,
		"openingConfig": opening_config.duplicate(true),
		"providerService": provider_service,
		"gateway": gateway,
		"runtime": runtime,
		"options": options.duplicate(true),
		"onComplete": on_complete,
		"nextData": {
			"mode": "new_game",
			"sessionId": session_id,
			"residentCount": resident_names.size(),
			"providerStatus": "checking",
			"canEnterTown": false,
			"capabilityMode": start_mode,
			"formalReady": start_mode == "formal",
			"internalPlaytest": internal_playtest,
			"internalLivePlaytest": internal_live_playtest,
		},
	}
	_operation = {
		"requestId": request_id,
		"intent": "session.new_game",
		"status": "loading",
	}
	_error = null
	if not bool(_last_data.get("canEnterTown", false)):
		_last_data = (_pending.get("nextData", {}) as Dictionary).duplicate(true)
	_emit_view_model()
	var availability := provider_service.call(
		"check_entry_availability",
		bindings,
		Callable(self, "_on_entry_availability").bind(request_id),
	) as Dictionary
	if not bool(availability.get("accepted", false)) and _is_pending(request_id):
		_complete(request_id, availability)
	return {
		"ok": bool(availability.get("ok", false)),
		"accepted": bool(availability.get("accepted", false)),
		"requestId": request_id,
		"errorCode": String(availability.get("errorCode", "")),
		"retryable": bool(availability.get("retryable", false)),
	}


func cancel() -> Dictionary:
	if _pending.is_empty():
		return {
			"ok": true,
			"changed": false,
			"errorCode": "",
			"retryable": false,
		}
	var request_id := String(_pending.get("requestId", ""))
	_complete(request_id, _failure("SESSION_BOOTSTRAP_CANCELLED", false))
	return {
		"ok": true,
		"changed": true,
		"requestId": request_id,
		"errorCode": "",
		"retryable": false,
	}


func _on_entry_availability(result: Dictionary, request_id: String) -> void:
	if not _is_pending(request_id):
		return
	if not bool(result.get("ok", false)):
		_complete(request_id, result)
		return
	var provider_status := String(result.get("status", "available"))
	if provider_status != "available":
		_complete(request_id, _failure("LLM_MODEL_UNAVAILABLE", false))
		return
	var capability_mode := String(result.get("capabilityMode", ""))
	var formal_ready := bool(result.get("formalReady", false))
	var source := String(result.get("source", "runtime"))
	var options := _pending.get("options", {}) as Dictionary
	var start_mode := String(options.get("worldStartMode", "formal"))
	var internal_playtest := bool(options.get("internalPlaytest", false))
	var internal_live_playtest := bool(options.get("internalLivePlaytest", false))
	if start_mode == "formal" and (capability_mode != "formal" or not formal_ready):
		_complete(request_id, _failure("PROVIDER_FORMAL_CAPABILITY_REQUIRED", false))
		return
	if start_mode == "development":
		if internal_live_playtest:
			if capability_mode != "formal" or not formal_ready or source != "runtime":
				_complete(request_id, _failure("SESSION_LIVE_PLAYTEST_CAPABILITY_INVALID", false))
				return
		elif (
			capability_mode != "development"
			or formal_ready
			or not internal_playtest
		):
			_complete(request_id, _failure("SESSION_DEVELOPMENT_CAPABILITY_INVALID", false))
			return
	var provider_service: Object = _pending.get("providerService")
	var gateway: Node = _pending.get("gateway")
	var runtime: Node = _pending.get("runtime")
	var bindings := _pending.get("bindings", []) as Array
	var resident_names := _pending.get("residentNames", []) as Array
	var session_id := String(options.get("sessionId", ""))
	var slot_id := String(options.get("slotId", ""))
	var gateway_result := gateway.call(
		"configure_session",
		{
			"sessionId": session_id,
			"slotId": slot_id,
			"saveRevision": 0,
			"residentIdentities": _resident_identities(bindings),
			"residentBindings": bindings.duplicate(true),
			"capabilityMode": capability_mode,
			"formalReady": formal_ready,
			"internalPlaytest": internal_playtest,
			"internalLivePlaytest": internal_live_playtest,
		},
		provider_service,
		options.get("requestHost") as Node,
	) as Dictionary
	if not bool(gateway_result.get("ok", false)):
		_complete(request_id, _normalize_failure(
			gateway_result,
			"AGENT_GATEWAY_SESSION_INVALID",
		))
		return
	var gateway_injection := runtime.call("configure_agent_gateway", gateway) as Dictionary
	if not bool(gateway_injection.get("ok", false)):
		_complete(
			request_id,
			_compensate_configured_gateway_failure(
				gateway,
				gateway_injection,
				"AGENT_GATEWAY_CONFIGURATION_FAILED",
			),
		)
		return
	var session_config := {
		"mode": "new_game",
		"sessionId": session_id,
		"slotId": slot_id,
		"saveRevision": 0,
		"openingConfig": (_pending.get("openingConfig", {}) as Dictionary).duplicate(true),
		"residentIdentities": _resident_identities(bindings),
		"residentBindings": bindings.duplicate(true),
		"connectedResidents": resident_names.duplicate(),
		"worldStartMode": start_mode,
		"capabilityMode": capability_mode,
		"source": source,
		"formalReady": start_mode == "formal" and formal_ready,
		"providerFormalReady": formal_ready,
		"internalPlaytest": internal_playtest,
		"internalLivePlaytest": internal_live_playtest,
		"requireAgentGateway": true,
		"useLiveModel": bool(options.get("useLiveModel", true)),
		"enablePlayerAvatar": bool(options.get("enablePlayerAvatar", true)),
		"enableTestUi": false,
	}
	var runtime_result := runtime.call("configure_session", session_config) as Dictionary
	if not bool(runtime_result.get("ok", false)):
		_complete(
			request_id,
			_compensate_configured_gateway_failure(
				gateway,
				runtime_result,
				"SESSION_RUNTIME_CONFIGURATION_FAILED",
			),
		)
		return
	_complete(request_id, {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"sessionId": session_id,
		"residentCount": resident_names.size(),
		"providerStatus": provider_status,
		"sessionConfig": session_config,
	})


func _complete(request_id: String, result: Dictionary) -> void:
	if not _is_pending(request_id):
		return
	var on_complete: Callable = _pending.get("onComplete", Callable())
	var next_data := (_pending.get("nextData", {}) as Dictionary).duplicate(true)
	var final_result := _normalize_failure(result, "SESSION_BOOTSTRAP_FAILED")
	final_result["requestId"] = request_id
	var ok := bool(final_result.get("ok", false))
	_operation = {
		"requestId": request_id,
		"intent": "session.new_game",
		"status": "success" if ok else (
			"error" if bool(final_result.get("retryable", false)) else "rejected"
		),
	}
	if ok:
		if not next_data.is_empty():
			_last_data = next_data
		_last_data["providerStatus"] = String(
			final_result.get("providerStatus", "available"),
		)
		_last_data["canEnterTown"] = true
	elif not bool(_last_data.get("canEnterTown", false)):
		_last_data["providerStatus"] = String(
			final_result.get("providerStatus", "unavailable"),
		)
		_last_data["canEnterTown"] = false
	_error = null if ok else _error_payload(final_result)
	_pending.clear()
	_emit_view_model()
	operation_completed.emit(final_result.duplicate(true))
	if on_complete.is_valid():
		on_complete.call(final_result.duplicate(true))


func _finish_immediate(
	request_id: String,
	result: Dictionary,
	on_complete: Callable,
) -> Dictionary:
	_pending = {
		"requestId": request_id,
		"onComplete": on_complete,
	}
	_complete(request_id, result)
	var response := result.duplicate(true)
	response["ok"] = false
	response["accepted"] = false
	response["requestId"] = request_id
	if String(response.get("errorCode", "")).is_empty():
		response["errorCode"] = "SESSION_BOOTSTRAP_FAILED"
	response["retryable"] = bool(response.get("retryable", false))
	return response


func _validate_contracts(provider_service: Object, gateway: Node, runtime: Node) -> Dictionary:
	var provider_missing := _missing_methods(provider_service, PROVIDER_METHODS)
	if not provider_missing.is_empty():
		return _failure(
			"PROVIDER_HEALTH_INTERFACE_MISSING",
			false,
			[{"missingMethods": provider_missing}],
		)
	var gateway_missing := _missing_methods(gateway, GATEWAY_METHODS)
	if not gateway_missing.is_empty():
		return _failure(
			"AGENT_GATEWAY_CONTRACT_MISSING",
			false,
			[{"missingMethods": gateway_missing}],
		)
	var runtime_missing := _missing_methods(runtime, RUNTIME_METHODS)
	if not runtime_missing.is_empty():
		return _failure(
			"SESSION_RUNTIME_CONTRACT_MISSING",
			false,
			[{"missingMethods": runtime_missing}],
		)
	return {}


func _missing_methods(target: Object, methods: Array[String]) -> Array[String]:
	var result: Array[String] = []
	if target == null:
		return methods.duplicate()
	for method in methods:
		if not target.has_method(method):
			result.append(method)
	return result


func _opening_resident_names(opening_config: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for resident_variant in opening_config.get("residents", []) as Array:
		var resident := resident_variant as Dictionary
		var name := String((resident.get("attributes", {}) as Dictionary).get("name", ""))
		if not name.is_empty():
			result.append(name)
	result.sort()
	return result


func _agent_bindings_from_opening(
	draft: Dictionary,
	world_data: Dictionary,
	opening_config: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_variant in draft.get("slots", []) as Array:
		var slot := slot_variant as Dictionary
		var resident_id := String(slot.get("residentId", ""))
		var resident := OPENING.resident_record(opening_config, resident_id) as Dictionary
		result.append({
			"residentId": resident_id,
			"residentName": String(resident.get("attributes", {}).get("name", "")),
			"llmBinding": (slot.get("llmBinding", {}) as Dictionary).duplicate(true),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	return result


func _resident_names_from_bindings(bindings: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for binding in bindings:
		var resident_name := String(binding.get("residentName", ""))
		if not resident_name.is_empty():
			result.append(resident_name)
	result.sort()
	return result


func _resident_identities(bindings: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in bindings:
		var binding := value as Dictionary
		result.append({
			"residentId": String(binding.get("residentId", "")),
			"residentName": String(binding.get("residentName", "")),
		})
	return result


func _is_pending(request_id: String) -> bool:
	return String(_pending.get("requestId", "")) == request_id


func _normalize_failure(result: Dictionary, fallback_code: String) -> Dictionary:
	var normalized := result.duplicate(true)
	if bool(normalized.get("ok", false)):
		normalized["errorCode"] = ""
		normalized["retryable"] = false
		return normalized
	normalized["ok"] = false
	if String(normalized.get("errorCode", "")).is_empty():
		normalized["errorCode"] = fallback_code
	normalized["retryable"] = bool(normalized.get("retryable", false))
	return normalized


func _compensate_configured_gateway_failure(
	gateway: Node,
	original_result: Dictionary,
	original_fallback_code: String,
) -> Dictionary:
	var original_failure := _normalize_failure(
		original_result,
		original_fallback_code,
	)
	var discard := gateway.call(
		"discard_unpublished_new_game",
		false,
	) as Dictionary
	if bool(discard.get("ok", false)):
		return original_failure
	var compensation_failure := _normalize_failure(
		discard,
		"AGENT_GATEWAY_DISCARD_FAILED",
	)
	var compensation_summary := {
		"stage": "gateway.discard_unpublished_new_game",
		"restorePhotoBlocker": false,
		"originalErrorCode": String(
			original_failure.get(
				"errorCode",
				original_fallback_code,
			)
		),
		"originalRetryable": bool(
			original_failure.get("retryable", false)
		),
		"compensationErrorCode": String(
			compensation_failure.get(
				"errorCode",
				"AGENT_GATEWAY_DISCARD_FAILED",
			)
		),
		"compensationRetryable": bool(
			compensation_failure.get("retryable", false)
		),
	}
	return {
		"ok": false,
		"errorCode": "SESSION_BOOTSTRAP_COMPENSATION_FAILED",
		"retryable": true,
		"errors": [compensation_summary.duplicate(true)],
		"compensation": compensation_summary,
	}


func _failure(
	error_code: String,
	retryable: bool,
	errors: Array = [],
) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"errors": errors.duplicate(true),
	}


func _error_payload(result: Dictionary) -> Dictionary:
	return {
		"kind": "transport" if bool(result.get("retryable", false)) else "rejected",
		"code": String(result.get("errorCode", "SESSION_BOOTSTRAP_FAILED")),
		"retryable": bool(result.get("retryable", false)),
		"message": String(result.get("message", "")),
		"details": (result.get("errors", []) as Array).duplicate(true),
	}


func _emit_view_model() -> void:
	_revision += 1
	view_model_changed.emit(get_view_model())


func _status() -> String:
	var operation_status := String(_operation.get("status", "idle"))
	if operation_status == "loading":
		return "loading"
	if operation_status == "success":
		return "ready"
	if operation_status in ["rejected", "error"]:
		return "error"
	return "ready"
