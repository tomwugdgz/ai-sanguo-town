extends SceneTree


const SOURCE_DIR := "res://world/data/town/source"
const BUILDER := preload("res://world/data/town/TownWorldDataBuilder.gd")
const RESIDENT_CATALOG := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)
const OPENING_COMPILER := preload(
	"res://world/presentation/session/TownNewGameOpeningCompiler.gd"
)
const PROVIDER_SETTINGS := preload(
	"res://world/presentation/ui/TownProviderSettingsService.gd"
)
const PROVIDER_SERVICE := preload(
	"res://world/integration/TownAgentProviderService.gd"
)
const AGENT_SYSTEM := preload("res://agent/AgentSystem.gd")
const GATEWAY := preload("res://world/integration/TownWorldAgentGateway.gd")
const WORLD := preload("res://world/runtime/TownWorldRuntime.gd")
const CLEANER := preload("res://tests/support/UserTestDataCleaner.gd")

const LIN_ID := "resident_lin_lan_01"
const TANG_ID := "resident_tang_xiaoman_01"
const WIFE_MEMORY_KEY := "memory-natural-world-wife-reaction"
const CONTROL_MEMORY_KEY := "memory-natural-world-control-reaction"
const WIFE_MEMORY := "唐小满是我老婆"
const CONTROL_MEMORY := "你是个npc，被我操控着"
const MAX_NATURAL_CALLS := 48
const MODEL_TIMEOUT_MSEC := 90_000

var _test_root := "user://tests/resident-memory-natural-world/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]
var _traces: Array[Dictionary] = []
var _failures: Array[String] = []
var _health_result: Dictionary = {}
var _agent_system_for_debug: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var saved := PROVIDER_SETTINGS.new().load_saved_runtime_configuration() as Dictionary
	if saved.get("ok") != true:
		printerr("NATURAL_MEMORY_WORLD_UNAVAILABLE: saved provider config unavailable")
		quit(2)
		return
	var provider_id := String(saved.get("providerId", ""))
	var model_id := String(saved.get("modelId", ""))
	if provider_id.is_empty() or model_id.is_empty():
		printerr("NATURAL_MEMORY_WORLD_UNAVAILABLE: provider/model not selected")
		quit(2)
		return
	print("NATURAL_MEMORY_WORLD_CONTEXT: provider=%s model=%s" % [provider_id, model_id])

	var world_data := BUILDER.build_from_source(SOURCE_DIR)
	var view_model := RESIDENT_CATALOG.build_view_model(
		provider_id,
		model_id,
		true,
		1,
	) as Dictionary
	var selection := (view_model.get("data", {}) as Dictionary).duplicate(true)
	selection["selected_resident_ids"] = (
		selection.get("recommended_resident_ids", []) as Array
	).duplicate()
	RESIDENT_CATALOG.update_confirmation_payload(
		selection,
		provider_id,
		model_id,
		2,
	)
	var compiled := OPENING_COMPILER.compile(
		selection.get("confirmation_payload", {}) as Dictionary,
		world_data,
		RESIDENT_CATALOG.load_catalog(),
	) as Dictionary
	_expect_ok(compiled, "formal resident selection compiles")
	if not _failures.is_empty():
		_finish(1)
		return
	var opening := compiled.get("openingConfig", {}) as Dictionary
	var bindings := compiled.get("residentBindings", []) as Array[Dictionary]
	var identities: Array[Dictionary] = []
	for binding: Dictionary in bindings:
		identities.append({
			"residentId": String(binding.get("residentId", "")),
			"residentName": String(binding.get("residentName", "")),
		})
	identities.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("residentId", "")) < String(right.get("residentId", ""))
	)

	var request_host := Node.new()
	request_host.name = "NaturalMemoryWorldRequestHost"
	root.add_child(request_host)
	var providers: RefCounted = PROVIDER_SERVICE.new()
	var provider_config := providers.call(
		"configure",
		{
			"capabilityMode": "formal",
			"source": "saved-settings",
			"allowFake": false,
			"providerConfigs": (saved.get("providerConfigs", {}) as Dictionary).duplicate(true),
		},
		request_host,
	) as Dictionary
	_expect_ok(provider_config, "real provider service configures")
	if not _failures.is_empty():
		request_host.queue_free()
		_finish(2)
		return
	var health_started := providers.call(
		"request_health_check",
		[{
			"providerId": provider_id,
			"modelId": model_id,
		}],
		Callable(self, "_on_provider_health_completed"),
	) as Dictionary
	_expect_ok(health_started, "formal Provider health check starts")
	var health := await _wait_for_provider_health()
	if health.get("status", "") != "available":
		_failures.append("DeepSeek health check did not pass: %s" % JSON.stringify(health))
		printerr("NATURAL_MEMORY_WORLD_SETUP_FAIL: %s" % _failures.back())
	if not _failures.is_empty():
		request_host.queue_free()
		_finish(2)
		return

	var world: RefCounted = WORLD.new()
	var started := world.call("start_formal", world_data, opening, identities) as Dictionary
	_expect_ok(started, "real World starts with Lin Lan and Tang Xiaoman")
	if not _failures.is_empty():
		request_host.queue_free()
		_finish(1)
		return

	var agent_system: RefCounted = AGENT_SYSTEM.new()
	_agent_system_for_debug = agent_system
	_expect_ok(
		agent_system.call("configure_test_runtime_storage", _test_root) as Dictionary,
		"real AgentSystem uses isolated natural-playtest storage",
	)
	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent_system)
	gateway.name = "NaturalMemoryWorldGateway"
	root.add_child(gateway)
	gateway.debug_decision_completed.connect(_on_decision_completed)
	print(
		"NATURAL_MEMORY_WORLD_SIGNAL_CONNECTIONS: %d"
		% gateway.debug_decision_completed.get_connections().size()
	)
	var configured := gateway.call(
		"configure_session",
		{
			"sessionId": "natural-memory-world-%d" % Time.get_ticks_usec(),
			"slotId": "natural-memory-world-%d" % OS.get_process_id(),
			"saveRevision": 0,
			"restorePending": false,
			"residentIdentities": identities.duplicate(true),
			"residentBindings": bindings.duplicate(true),
			"openingConfig": opening.duplicate(true),
			"capabilityMode": "formal",
			"formalReady": true,
		},
		providers,
		request_host,
	) as Dictionary
	var bound := gateway.call("bind_world", world) as Dictionary if configured.get("ok") == true else {}
	_expect_ok(configured, "natural Gateway configures")
	_expect_ok(bound, "natural Gateway binds the real World")
	if not _failures.is_empty():
		_cleanup(gateway, agent_system, world, request_host)
		_finish(1)
		return

	var memory_write := gateway.call(
		"apply_resident_memory_intervention",
		LIN_ID,
		{
			"memoryKey": WIFE_MEMORY_KEY,
			"operation": "write",
			"playerText": "我认识唐小满。",
			"expectedRevision": 0,
		},
	) as Dictionary
	_expect_ok(memory_write, "formal Gateway writes Lin Lan memory")
	var memory_edit := gateway.call(
		"apply_resident_memory_intervention",
		LIN_ID,
		{
			"memoryKey": WIFE_MEMORY_KEY,
			"operation": "edit",
			"playerText": WIFE_MEMORY,
			"expectedRevision": 1,
		},
	) as Dictionary
	_expect_ok(memory_edit, "formal Gateway edits Lin Lan memory")
	var control_memory := gateway.call(
		"apply_resident_memory_intervention",
		LIN_ID,
		{
			"memoryKey": CONTROL_MEMORY_KEY,
			"operation": "write",
			"playerText": CONTROL_MEMORY,
			"expectedRevision": 2,
		},
	) as Dictionary
	_expect_ok(control_memory, "formal Gateway writes control-memory test")
	if not _failures.is_empty():
		_cleanup(gateway, agent_system, world, request_host)
		_finish(1)
		return
	var memory_snapshot := agent_system.call(
		"get_memory_debug_snapshot",
		LIN_ID,
	) as Dictionary
	var memory_projection := memory_snapshot.get("memory", {}) as Dictionary
	var memory_text := JSON.stringify(memory_projection)
	print(
		"NATURAL_MEMORY_WORLD_MEMORY_READBACK: wifeMemoryStored=%s controlMemoryStored=%s"
		% [memory_text.contains(WIFE_MEMORY), memory_text.contains(CONTROL_MEMORY)]
	)
	if not memory_text.contains(WIFE_MEMORY) or not memory_text.contains(CONTROL_MEMORY):
		_failures.append("memory intervention readback did not contain exact test memories")
		printerr("NATURAL_MEMORY_WORLD_SETUP_FAIL: %s" % _failures.back())
		_cleanup(gateway, agent_system, world, request_host)
		_finish(1)
		return
	print("NATURAL_MEMORY_WORLD_MEMORY_APPLIED: resident=林岚 target=唐小满")

	var calls := 0
	var timed_out := false
	while calls < MAX_NATURAL_CALLS:
		var dispatched := int(gateway.call("pump", 2))
		if dispatched > 0:
			calls += dispatched
			if not await _wait_for_model(gateway):
				timed_out = true
				break
		world.call("advance", 10.0)
		await process_frame
		if dispatched == 0:
			world.call("advance", 10.0)

	var related := _related_trace_count()
	var final_memory_snapshot := agent_system.call(
		"get_memory_debug_snapshot",
		LIN_ID,
	) as Dictionary
	var report := {
		"modelCalls": calls,
		"time": world.call("get_time"),
		"linLanDecisions": _lin_traces(),
		"relatedBehaviorCount": related,
		"activeConversations": world.call("get_active_conversations"),
		"gatewayErrors": gateway.call("get_errors"),
		"memoryContextFields": final_memory_snapshot.get("context", []) as Array,
		"timedOut": timed_out,
	}
	print("NATURAL_MEMORY_WORLD_REPORT: %s" % JSON.stringify(report))
	if calls == 0:
		_failures.append("natural World produced no Agent decisions")
	if _lin_traces().is_empty():
		_failures.append("natural World produced no Lin Lan decision in the observation window")
	if timed_out:
		_failures.append("natural World model request timed out")
	_cleanup(gateway, agent_system, world, request_host)
	if _failures.is_empty():
		print("NATURAL_MEMORY_WORLD_PLAYTEST_PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("NATURAL_MEMORY_WORLD_PLAYTEST_FAIL: %s" % failure)
	quit(1)


func _on_decision_completed(trace: Dictionary) -> void:
	_traces.append(trace.duplicate(true))
	if String(trace.get("residentId", "")) != LIN_ID:
		return
	var memory_snapshot := _agent_system_for_debug.call(
		"get_memory_debug_snapshot",
		LIN_ID,
	) as Dictionary
	var result := trace.get("agentResult", {}) as Dictionary
	var decision := result.get("decision", {}) as Dictionary
	var action := decision.get("action", {}) as Dictionary
	print(
		"NATURAL_MEMORY_WORLD_LIN_DECISION: time=%s action=%s target=%s place=%s line=%s say=%s narration=%s"
		% [
			JSON.stringify(trace.get("worldTime", {})),
			String(action.get("type", "")),
			String(action.get("target_resident_id", "")),
			String(action.get("place", "")),
			String(action.get("line", "")),
			String(action.get("say", "")),
			String(action.get("narration", "")),
		],
	)
	print(
		"NATURAL_MEMORY_WORLD_LIN_MEMORY_CONTEXT: fields=%s"
		% JSON.stringify(memory_snapshot.get("context", []) as Array)
	)


func _on_provider_health_completed(result: Dictionary) -> void:
	_health_result = result.duplicate(true)


func _wait_for_provider_health() -> Dictionary:
	var started_at := Time.get_ticks_msec()
	while _health_result.is_empty():
		if Time.get_ticks_msec() - started_at >= MODEL_TIMEOUT_MSEC:
			return {
				"status": "timeout",
				"errorCode": "PROVIDER_HEALTH_TIMEOUT",
			}
		await process_frame
	return _health_result.duplicate(true)


func _lin_traces() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trace: Dictionary in _traces:
		if String(trace.get("residentId", "")) != LIN_ID:
			continue
		var decision := (trace.get("agentResult", {}) as Dictionary).get(
			"decision",
			{},
		) as Dictionary
		var action := decision.get("action", {}) as Dictionary
		result.append({
			"action": String(action.get("type", "")),
			"target": String(action.get("target_resident_id", "")),
			"place": String(action.get("place", "")),
			"line": String(action.get("line", "")),
			"say": String(action.get("say", "")),
			"narration": String(action.get("narration", "")),
		})
	return result


func _related_trace_count() -> int:
	var count := 0
	for value: Dictionary in _lin_traces():
		var text := JSON.stringify(value)
		if text.contains(TANG_ID) or text.contains("唐小满"):
			count += 1
	return count


func _wait_for_model(gateway: Node) -> bool:
	var started_at := Time.get_ticks_msec()
	while int(gateway.call("get_debug_inflight_count")) > 0:
		if Time.get_ticks_msec() - started_at >= MODEL_TIMEOUT_MSEC:
			return false
		await process_frame
	return true


func _cleanup(
	gateway: Node,
	agent_system: RefCounted,
	world: RefCounted,
	request_host: Node,
) -> void:
	if is_instance_valid(gateway):
		gateway.queue_free()
	if is_instance_valid(agent_system):
		agent_system.call("close_game")
	if is_instance_valid(world):
		world.call("stop")
	if is_instance_valid(request_host):
		request_host.queue_free()
	if not CLEANER.remove_tree(_test_root):
		_failures.append("natural test storage cleanup failed")


func _expect_ok(result: Dictionary, message: String) -> void:
	if result.get("ok") != true:
		var failure := "%s: %s" % [message, JSON.stringify(result)]
		_failures.append(failure)
		printerr("NATURAL_MEMORY_WORLD_SETUP_FAIL: %s" % failure)


func _finish(code: int) -> void:
	CLEANER.remove_tree(_test_root)
	quit(code)
