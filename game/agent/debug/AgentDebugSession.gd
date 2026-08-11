class_name AgentDebugSession
extends Node


signal state_changed(snapshot: Dictionary)
signal trace_added(trace: Dictionary)
signal action_completed(result: Dictionary)

const INTERNAL_CATALOG := preload(
	"res://world/presentation/session/TownInternalPlaytestCatalog.gd"
)
const BOOTSTRAP := preload(
	"res://world/presentation/session/TownSessionBootstrap.gd"
)
const PROVIDER_SERVICE := preload(
	"res://world/integration/TownAgentProviderService.gd"
)
const PROVIDER_SETTINGS := preload(
	"res://world/presentation/ui/TownProviderSettingsService.gd"
)
const GATEWAY := preload(
	"res://world/integration/TownWorldAgentGateway.gd"
)
const SAVE_COORDINATOR := preload(
	"res://world/presentation/session/TownSessionSaveCoordinator.gd"
)
const SAVE_STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const RUNTIME_GATE := preload(
	"res://world/presentation/session/TownSessionRuntimeGate.gd"
)
const TOWN_RUNTIME_SCENE := preload(
	"res://world/presentation/town_runtime/TownRuntime.tscn"
)
const WORLD_DATA_PATH := "res://world/data/town/town_world.json"

var _runtime: Node
var _gateway: Node
var _provider_service: RefCounted
var _bootstrap: RefCounted
var _store: RefCounted
var _coordinator: RefCounted
var _gate: RefCounted
var _session_config: Dictionary = {}
var _world_data: Dictionary = {}
var _traces: Array[Dictionary] = []
var _status := "idle"
var _error: Dictionary = {}
var _last_restore_result: Dictionary = {}
var _pending_start: Dictionary = {}


func start_new(provider_id: String, model_id: String, slot_id := "") -> Dictionary:
	if _status in ["checking_provider", "starting", "running"]:
		return _failure("DEBUG_SESSION_ALREADY_RUNNING")
	_status = "starting"
	_error.clear()
	_traces.clear()
	_pending_start.clear()
	_world_data = _read_json(WORLD_DATA_PATH)
	if _world_data.is_empty():
		return _fail_start("DEBUG_WORLD_DATA_INVALID")
	var selection := INTERNAL_CATALOG.build_view_model(provider_id, model_id)
	var draft := (
		(selection.get("data", {}) as Dictionary).get(
			"confirmation_payload",
			{},
		) as Dictionary
	).duplicate(true)
	var catalog := INTERNAL_CATALOG.build_catalog(_world_data, selection)
	var identity := "%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var resolved_slot_id := (
		slot_id.strip_edges()
		if not slot_id.strip_edges().is_empty()
		else "agent-debug-%s" % identity
	)
	_provider_service = _create_provider_service()
	var saved_provider_runtime := _load_saved_provider_runtime()
	if not bool(saved_provider_runtime.get("ok", false)):
		return _fail_start(
			String(saved_provider_runtime.get(
				"errorCode",
				"DEBUG_PROVIDER_SETTINGS_INVALID",
			)),
			saved_provider_runtime,
		)
	var provider_config := _provider_service.call("configure", {
		"capabilityMode": "development",
		"source": "agent-debug",
		"allowFake": provider_id == "fake",
		"providerConfigs": (
			saved_provider_runtime.get("providerConfigs", {}) as Dictionary
		).duplicate(true),
	}, self) as Dictionary
	if not bool(provider_config.get("ok", false)):
		return _fail_start(
			String(provider_config.get("errorCode", "DEBUG_PROVIDER_INVALID")),
			provider_config,
		)
	_pending_start = {
		"draft": draft.duplicate(true),
		"catalog": catalog.duplicate(true),
		"identity": identity,
		"slotId": resolved_slot_id,
		"providerId": provider_id,
	}
	if provider_id != "fake":
		_status = "checking_provider"
		_emit_state()
		var health_started := _provider_service.call(
			"request_health_check",
			(draft.get("slots", []) as Array).duplicate(true),
			_on_start_provider_health_completed,
		) as Dictionary
		if not bool(health_started.get("accepted", false)):
			return _fail_start(
				String(health_started.get(
					"errorCode",
					"DEBUG_PROVIDER_HEALTH_REJECTED",
				)),
				health_started,
			)
		return health_started
	return _begin_configured_start()


func _on_start_provider_health_completed(result: Dictionary) -> void:
	if _status != "checking_provider":
		return
	if not bool(result.get("ok", false)):
		_fail_start(
			String(result.get("errorCode", "DEBUG_PROVIDER_HEALTH_FAILED")),
			result,
		)
		return
	var availability := _provider_service.call(
		"check_entry_availability",
		(_pending_start.get("draft", {}) as Dictionary).get("slots", []),
	) as Dictionary
	if not bool(availability.get("ok", false)):
		_fail_start(
			String(availability.get(
				"errorCode",
				"DEBUG_PROVIDER_UNAVAILABLE",
			)),
			availability,
		)
		return
	_status = "starting"
	_emit_state()
	_begin_configured_start()


func _begin_configured_start() -> Dictionary:
	if _pending_start.is_empty():
		return _fail_start("DEBUG_START_CONTEXT_INVALID")
	var draft := (
		_pending_start.get("draft", {}) as Dictionary
	).duplicate(true)
	var catalog := (
		_pending_start.get("catalog", {}) as Dictionary
	).duplicate(true)
	var identity := String(_pending_start.get("identity", ""))
	var resolved_slot_id := String(_pending_start.get("slotId", ""))
	var provider_id := String(_pending_start.get("providerId", ""))
	_gateway = GATEWAY.new()
	_gateway.debug_decision_dispatched.connect(_on_decision_dispatched)
	_gateway.debug_decision_completed.connect(_on_decision_completed)
	_runtime = TOWN_RUNTIME_SCENE.instantiate()
	_runtime.visible = false
	_bootstrap = BOOTSTRAP.new()
	var accepted := _bootstrap.call(
		"begin_new_game_from_catalog",
		draft,
		_world_data,
		catalog,
		_provider_service,
		_gateway,
		_runtime,
		{
			"worldStartMode": "development",
			"internalPlaytest": true,
			"sessionId": "agent-debug-session-%s" % identity,
			"slotId": resolved_slot_id,
			"requestHost": self,
			"useLiveModel": provider_id != "fake",
			"enablePlayerAvatar": true,
		},
		_on_bootstrap_completed,
	) as Dictionary
	if not bool(accepted.get("accepted", false)) and not bool(accepted.get("ok", false)):
		return _fail_start(
			String(accepted.get("errorCode", "DEBUG_BOOTSTRAP_REJECTED")),
			accepted,
		)
	_emit_state()
	return accepted


func stop() -> void:
	if is_instance_valid(_runtime):
		_runtime.queue_free()
	_runtime = null
	_gateway = null
	_provider_service = null
	_session_config.clear()
	_pending_start.clear()
	_status = "idle"
	_emit_state()


func snapshot() -> Dictionary:
	var residents: Array[Dictionary] = []
	if is_instance_valid(_gateway):
		for resident_id: String in _gateway.call("get_connected_resident_ids"):
			var debug := _gateway.call(
				"get_resident_debug_snapshot",
				resident_id,
			) as Dictionary
			residents.append({
				"residentId": resident_id,
				"residentName": String(debug.get("resident_name", "")),
				"binding": (debug.get("binding", {}) as Dictionary).duplicate(true),
				"memory": (debug.get("memory", {}) as Dictionary).duplicate(true),
				"lastSubmission": (
					debug.get("last_submission", {}) as Dictionary
				).duplicate(true),
			})
	return {
		"status": _status,
		"error": _error.duplicate(true),
		"sessionConfig": _session_config.duplicate(true),
		"residentCount": residents.size(),
		"residents": residents,
		"traceCount": _traces.size(),
		"save": save_snapshot(),
		"lastRestoreResult": _last_restore_result.duplicate(true),
	}


func traces(resident_id := "") -> Array[Dictionary]:
	if resident_id.is_empty():
		return _traces.duplicate(true)
	var result: Array[Dictionary] = []
	for trace: Dictionary in _traces:
		if String(trace.get("residentId", "")) == resident_id:
			result.append(trace.duplicate(true))
	return result


func trace_count() -> int:
	return _traces.size()


func traces_from(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trace_index in range(maxi(0, index), _traces.size()):
		result.append(_traces[trace_index].duplicate(true))
	return result


func pending_decision_count() -> int:
	if not is_instance_valid(_gateway):
		return 0
	return int(_gateway.call("get_debug_inflight_count"))


func resident_debug_snapshot(resident_id: String) -> Dictionary:
	if not is_instance_valid(_gateway):
		return {}
	return _gateway.call("get_resident_debug_snapshot", resident_id) as Dictionary


func conversation_adapter() -> Node:
	if not is_instance_valid(_runtime):
		return null
	return _runtime.call("get_ui_adapter") as Node


func begin_avatar_conversation(resident_id: String, say: String) -> Dictionary:
	if _status != "running":
		return _failure("DEBUG_SESSION_NOT_RUNNING")
	var world: RefCounted = _runtime.call("get_world_runtime")
	var resident := world.call("get_resident_state", resident_id) as Dictionary
	if resident.is_empty():
		return _failure("DEBUG_RESIDENT_NOT_FOUND")
	var active := _active_avatar_conversation(world)
	if not active.is_empty() and _conversation_has_resident(active, resident):
		return _runtime.call(
			"player_reply_conversation",
			String(active.get("conversationId", "")),
			say.strip_edges(),
			"旅行者继续交谈",
			false,
		) as Dictionary
	if not active.is_empty():
		var ended := _runtime.call(
			"player_end_conversation",
			String(active.get("conversationId", "")),
			"旅行者转向其他居民",
		) as Dictionary
		if not bool(ended.get("ok", false)):
			return ended
	# 居民可能站在区域边界上。由 World 计算附近可行走落点，避免直接复制
	# 居民坐标后把旅行者归到相邻区域。
	var avatar_move := world.call(
		"prepare_player_avatar_descent",
		String(resident.get("spaceId", "town_outdoor")),
		resident.get("position", Vector2.ZERO) as Vector2,
	) as Dictionary
	if not bool(avatar_move.get("ok", false)):
		return avatar_move
	var result := _runtime.call(
		"player_start_conversation",
		String(resident.get("name", "")),
		say.strip_edges(),
		"旅行者主动交谈",
	) as Dictionary
	action_completed.emit(result.duplicate(true))
	return result


func _active_avatar_conversation(world: RefCounted) -> Dictionary:
	var avatar := world.call("get_player_avatar_state") as Dictionary
	var avatar_id := String(avatar.get("residentId", ""))
	var avatar_name := String(avatar.get("name", "旅行者"))
	for value: Variant in world.call("get_active_conversations") as Array:
		var conversation := value as Dictionary
		var participants := conversation.get("participants", []) as Array
		var has_avatar := participants.has(avatar_id) or participants.has(avatar_name)
		if has_avatar:
			return conversation.duplicate(true)
	return {}


func _conversation_has_resident(
	conversation: Dictionary,
	resident: Dictionary,
) -> bool:
	var participants := conversation.get("participants", []) as Array
	return (
		participants.has(String(resident.get("residentId", "")))
		or participants.has(String(resident.get("name", "")))
	)


func perform_action(action: Dictionary) -> Dictionary:
	if _status != "running":
		return _failure("DEBUG_SESSION_NOT_RUNNING")
	var action_type := String(action.get("type", ""))
	var world: RefCounted = _runtime.call("get_world_runtime")
	var result: Dictionary
	match action_type:
		"conversation":
			result = begin_avatar_conversation(
				String(action.get("resident_id", "")),
				String(action.get("say", "")),
			)
		"conversation_reply":
			result = _runtime.call(
				"player_reply_conversation",
				String(action.get("conversation_id", "")),
				String(action.get("say", "")),
				"旅行者继续交谈",
				false,
			) as Dictionary
		"conversation_end":
			result = _runtime.call(
				"player_end_conversation",
				String(action.get("conversation_id", "")),
				"旅行者结束交谈",
			) as Dictionary
		"announcement":
			result = world.call(
				"publish_announcement",
				String(action.get("text", "")),
			) as Dictionary
			_gateway.call("pump")
		"advance_time":
			result = world.call(
				"advance",
				float(action.get("seconds", 1.0)),
			) as Dictionary
			_gateway.call("pump")
		"weather":
			result = world.call("set_weather", String(action.get("weather", ""))) as Dictionary
			_gateway.call("pump")
		_:
			result = _failure("DEBUG_ACTION_UNSUPPORTED")
	action_completed.emit(result.duplicate(true))
	return result


func create_save() -> Dictionary:
	if _coordinator == null:
		return _failure("DEBUG_SAVE_NOT_CONFIGURED")
	var result := _coordinator.call("save", {
		"slotId": _session_config.get("slotId"),
		"sessionId": _session_config.get("sessionId"),
		"residentIdentities": _session_config.get("residentIdentities", []),
		"sessionConfig": _manifest_session_config(),
		"savedAt": Time.get_datetime_string_from_system(false, false),
	}) as Dictionary
	_emit_state()
	return result


func restore_latest() -> Dictionary:
	if _coordinator == null or not is_instance_valid(_gateway):
		return _failure("DEBUG_SAVE_NOT_CONFIGURED")
	var discovered := _coordinator.call(
		"discover_latest",
		String(_session_config.get("slotId", "")),
	) as Dictionary
	if not bool(discovered.get("ok", false)):
		return discovered
	var manifest := discovered.get("manifest", {}) as Dictionary
	var loaded_config := _store.call(
		"read_reference",
		manifest.get("session_config_ref", ""),
		manifest.get("session_config_sha256", ""),
	) as Dictionary
	if not bool(loaded_config.get("ok", false)):
		return loaded_config
	var saved_config: Variant = loaded_config.get("value")
	if not saved_config is Dictionary:
		return _failure("DEBUG_SAVE_SESSION_CONFIG_INVALID")
	_status = "restoring"
	_last_restore_result.clear()
	_emit_state()
	call_deferred(
		"_restore_discovered",
		manifest.duplicate(true),
		(saved_config as Dictionary).duplicate(true),
	)
	var result := {
		"ok": true,
		"accepted": true,
		"errorCode": "",
		"retryable": false,
	}
	return result


func _restore_discovered(manifest: Dictionary, saved_config: Dictionary) -> void:
	if is_instance_valid(_runtime):
		_runtime.queue_free()
	await get_tree().process_frame
	var identities := (
		saved_config.get("residentIdentities", []) as Array
	).duplicate(true)
	var bindings := (
		saved_config.get("residentBindings", []) as Array
	).duplicate(true)
	var resident_names: Array[String] = []
	var allow_fake := false
	for identity_value: Variant in identities:
		resident_names.append(
			String((identity_value as Dictionary).get("residentName", "")),
		)
	for binding_value: Variant in bindings:
		var llm := (
			(binding_value as Dictionary).get("llmBinding", {}) as Dictionary
		)
		allow_fake = allow_fake or String(llm.get("providerId", "")) == "fake"
	_provider_service = _create_provider_service()
	var saved_provider_runtime := _load_saved_provider_runtime()
	if not bool(saved_provider_runtime.get("ok", false)):
		_complete_restore_failure(saved_provider_runtime)
		return
	var provider_config := _provider_service.call("configure", {
		"capabilityMode": "development",
		"source": "agent-debug",
		"allowFake": allow_fake,
		"providerConfigs": (
			saved_provider_runtime.get("providerConfigs", {}) as Dictionary
		).duplicate(true),
	}, self) as Dictionary
	if not bool(provider_config.get("ok", false)):
		_complete_restore_failure(provider_config)
		return
	if _bindings_require_health(bindings):
		var health_completion := {
			"done": false,
			"result": {},
		}
		var health_started := _provider_service.call(
			"request_health_check",
			bindings.duplicate(true),
			func(result: Dictionary) -> void:
				health_completion["result"] = result.duplicate(true)
				health_completion["done"] = true,
		) as Dictionary
		if not bool(health_started.get("accepted", false)):
			_complete_restore_failure(health_started)
			return
		while not bool(health_completion.get("done", false)):
			if _status != "restoring":
				return
			await get_tree().process_frame
		var health_result := (
			health_completion.get("result", {}) as Dictionary
		)
		if not bool(health_result.get("ok", false)):
			_complete_restore_failure(health_result)
			return
		var availability := _provider_service.call(
			"check_entry_availability",
			bindings.duplicate(true),
		) as Dictionary
		if not bool(availability.get("ok", false)):
			_complete_restore_failure(availability)
			return
	_gateway = GATEWAY.new()
	_gateway.debug_decision_dispatched.connect(_on_decision_dispatched)
	_gateway.debug_decision_completed.connect(_on_decision_completed)
	var slot_id := String(manifest.get("slot_id", ""))
	var session_id := String(manifest.get("session_id", ""))
	var revision := int(manifest.get("save_revision", 0))
	var gateway_config := {
		"sessionId": session_id,
		"slotId": slot_id,
		"saveRevision": revision,
		"restorePending": true,
		"residentIdentities": identities,
		"residentBindings": bindings,
		"capabilityMode": "development",
		"formalReady": false,
	}
	var gateway_result := _gateway.call(
		"configure_session",
		gateway_config,
		_provider_service,
		self,
	) as Dictionary
	if not bool(gateway_result.get("ok", false)):
		_complete_restore_failure(gateway_result)
		return
	_runtime = TOWN_RUNTIME_SCENE.instantiate()
	_runtime.visible = false
	var injection := _runtime.call("configure_agent_gateway", _gateway) as Dictionary
	if not bool(injection.get("ok", false)):
		_runtime.free()
		_complete_restore_failure(injection)
		return
	var restored_config := {
		"mode": "continue",
		"sessionId": session_id,
		"slotId": slot_id,
		"saveRevision": revision,
		"restorePending": true,
		"openingConfig": (
			saved_config.get("openingConfig", {}) as Dictionary
		).duplicate(true),
		"residentIdentities": identities,
		"residentBindings": bindings,
		"connectedResidents": resident_names,
		"worldStartMode": "development",
		"capabilityMode": "development",
		"source": "agent-debug",
		"formalReady": false,
		"providerFormalReady": false,
		"internalPlaytest": true,
		"internalLivePlaytest": false,
		"requireAgentGateway": true,
		"useLiveModel": bool(saved_config.get("useLiveModel", false)),
		"enablePlayerAvatar": true,
		"avatarInitialMode": "observer",
		"enableTestUi": false,
	}
	var runtime_config := _runtime.call(
		"configure_session",
		restored_config,
	) as Dictionary
	if not bool(runtime_config.get("ok", false)):
		_runtime.free()
		_complete_restore_failure(runtime_config)
		return
	add_child(_runtime)
	await get_tree().process_frame
	await get_tree().process_frame
	_runtime.visible = false
	var startup := _runtime.call("get_startup_result") as Dictionary
	if not bool(startup.get("ok", false)):
		_complete_restore_failure(startup)
		return
	_gate = RUNTIME_GATE.new()
	_gate.call("configure", _runtime)
	_coordinator = SAVE_COORDINATOR.new()
	var configured := _coordinator.call(
		"configure",
		_store,
		_runtime.call("get_world_runtime"),
		_gateway.call("get_agent_save_participant"),
		_gate,
		{"allowDevelopmentWorld": true},
	) as Dictionary
	if not bool(configured.get("ok", false)):
		_complete_restore_failure(configured)
		return
	var restored := _coordinator.call(
		"restore_revision",
		slot_id,
		session_id,
		revision,
		_world_data.duplicate(true),
		identities,
		_gateway,
	) as Dictionary
	if not bool(restored.get("ok", false)):
		_complete_restore_failure(restored)
		return
	var completion := _runtime.call(
		"complete_restored_session",
		restored.get("context", {}) as Dictionary,
	) as Dictionary
	if not bool(completion.get("ok", false)):
		_complete_restore_failure(completion)
		return
	restored_config["restorePending"] = false
	restored_config["saveRevision"] = revision
	_session_config = restored_config
	_last_restore_result = restored.duplicate(true)
	_status = "running"
	_emit_state()


func _complete_restore_failure(result: Dictionary) -> void:
	_last_restore_result = result.duplicate(true)
	_status = "error"
	_error = result.duplicate(true)
	_emit_state()


func save_snapshot() -> Dictionary:
	if _store == null or _session_config.is_empty():
		return {"configured": false, "manifests": [], "incomplete": []}
	var slot_id := String(_session_config.get("slotId", ""))
	var published := _store.call("list_published", slot_id) as Dictionary
	var incomplete := _store.call("list_incomplete", slot_id) as Dictionary
	return {
		"configured": true,
		"root": SAVE_STORE.DEFAULT_ROOT,
		"slotId": slot_id,
		"sessionId": String(_session_config.get("sessionId", "")),
		"agentContext": (
			_gateway.call("get_agent_save_context")
			if is_instance_valid(_gateway)
			else {}
		),
		"manifests": published.get("manifests", []),
		"invalid": published.get("invalid", []),
		"incomplete": incomplete.get("items", []),
	}


func _on_bootstrap_completed(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_fail_start(
			String(result.get("errorCode", "DEBUG_BOOTSTRAP_FAILED")),
			result,
		)
		return
	_pending_start.clear()
	_session_config = (result.get("sessionConfig", {}) as Dictionary).duplicate(true)
	add_child(_runtime)
	_runtime.visible = false
	call_deferred("_finish_runtime_start")


func _finish_runtime_start() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_runtime.visible = false
	var startup := _runtime.call("get_startup_result") as Dictionary
	if not bool(startup.get("ok", false)):
		_fail_start(
			String(startup.get("errorCode", "DEBUG_RUNTIME_START_FAILED")),
			startup,
		)
		return
	_store = SAVE_STORE.new()
	_gate = RUNTIME_GATE.new()
	_gate.call("configure", _runtime)
	_coordinator = SAVE_COORDINATOR.new()
	var configured := _coordinator.call(
		"configure",
		_store,
		_runtime.call("get_world_runtime"),
		_gateway.call("get_agent_save_participant"),
		_gate,
		{"allowDevelopmentWorld": true},
	) as Dictionary
	if not bool(configured.get("ok", false)):
		_fail_start(
			String(configured.get("errorCode", "DEBUG_SAVE_CONFIG_FAILED")),
			configured,
		)
		return
	_status = "running"
	_emit_state()


func _on_decision_dispatched(trace: Dictionary) -> void:
	var record := trace.duplicate(true)
	record["phase"] = "dispatched"
	_traces.append(record)
	trace_added.emit(record.duplicate(true))


func _on_decision_completed(trace: Dictionary) -> void:
	var record := trace.duplicate(true)
	record["phase"] = "completed"
	record["completedAtMsec"] = Time.get_ticks_msec()
	_traces.append(record)
	trace_added.emit(record.duplicate(true))


func _manifest_session_config() -> Dictionary:
	var result: Dictionary = {}
	for key: String in [
		"mode",
		"sessionId",
		"openingConfig",
		"residentIdentities",
		"residentBindings",
		"connectedResidents",
		"worldStartMode",
		"useLiveModel",
		"enablePlayerAvatar",
		"enableTestUi",
	]:
		if _session_config.has(key):
			result[key] = _session_config[key]
	var saved_bindings: Array[Dictionary] = []
	for value: Variant in result.get("residentBindings", []) as Array:
		var binding := value as Dictionary
		var llm := binding.get("llmBinding", {}) as Dictionary
		saved_bindings.append({
			"residentId": binding.get("residentId"),
			"llmBinding": {
				"mode": llm.get("mode"),
				"providerId": llm.get("providerId"),
				"modelId": llm.get("modelId"),
			},
		})
	result["residentBindings"] = saved_bindings
	return result.duplicate(true)


func _load_saved_provider_runtime() -> Dictionary:
	var settings: RefCounted = PROVIDER_SETTINGS.new()
	return settings.call("load_saved_runtime_configuration") as Dictionary


func _bindings_require_health(bindings: Array) -> bool:
	for binding_value: Variant in bindings:
		var llm := (
			(binding_value as Dictionary).get("llmBinding", {}) as Dictionary
		)
		if String(llm.get("providerId", "")) != "fake":
			return true
	return false


func _create_provider_service() -> RefCounted:
	return PROVIDER_SERVICE.new()


func _emit_state() -> void:
	state_changed.emit(snapshot())


func _fail_start(error_code: String, detail: Dictionary = {}) -> Dictionary:
	_status = "error"
	_pending_start.clear()
	_error = detail.duplicate(true)
	_error["errorCode"] = error_code
	_emit_state()
	return _failure(error_code, detail)


func _failure(error_code: String, detail: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"detail": detail.duplicate(true),
	}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value as Dictionary if value is Dictionary else {}
