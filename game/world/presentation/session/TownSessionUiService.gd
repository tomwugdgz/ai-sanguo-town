class_name TownSessionUiService
extends RefCounted


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)
const RUNTIME_GATE := preload(
	"res://world/presentation/session/TownSessionRuntimeGate.gd"
)
const COORDINATOR := preload(
	"res://world/presentation/session/TownSessionSaveCoordinator.gd"
)
const MANIFEST := preload(
	"res://world/presentation/session/TownSessionSaveManifest.gd"
)

const FORMAL_WORLD_REQUIRED := "SESSION_SAVE_FORMAL_WORLD_REQUIRED"
const SERVICE_NOT_CONFIGURED := "SESSION_SAVE_SERVICE_NOT_CONFIGURED"

var _runtime: Node
var _world: Object
var _agent: Object
var _session_config: Dictionary = {}
var _store: RefCounted
var _gate: RefCounted
var _coordinator: RefCounted
var _configuration_error: Dictionary = {}
var _last_result: Dictionary = {}
var _test_store_root := ""


func configure_test_store_root(path: String) -> Dictionary:
	if _coordinator != null or _store != null:
		return _failure("SESSION_SAVE_SERVICE_ALREADY_CONFIGURED", false)
	var candidate: RefCounted = STORE.new()
	var configured := candidate.call("configure_test_root", path) as Dictionary
	if configured.get("ok") != true:
		return configured
	_test_store_root = path.trim_suffix("/")
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
	}


func configure(
	runtime: Node,
	world: Object,
	agent: Object,
	session_config: Dictionary,
) -> Dictionary:
	_runtime = runtime
	_world = world
	_agent = agent
	_session_config = session_config.duplicate(true)
	_configuration_error.clear()
	_last_result.clear()
	if (
		runtime == null
		or world == null
		or agent == null
		or not is_instance_valid(runtime)
		or not is_instance_valid(world)
		or not is_instance_valid(agent)
	):
		return _remember_configuration_failure(
			"SESSION_SAVE_RUNTIME_DEPENDENCY_MISSING",
		)
	if not agent.has_method("get_save_context"):
		return _remember_configuration_failure(
			"SESSION_SAVE_AGENT_PARTICIPANT_MISSING",
		)
	if not runtime.has_method("get_resident_identity_snapshot"):
		return _remember_configuration_failure(
			"SESSION_SAVE_RUNTIME_DEPENDENCY_MISSING",
		)
	_store = STORE.new()
	if not _test_store_root.is_empty():
		var store_configuration := _store.call(
			"configure_test_root",
			_test_store_root,
		) as Dictionary
		if store_configuration.get("ok") != true:
			return _remember_configuration_result(store_configuration)
	_gate = RUNTIME_GATE.new()
	var gate_result := _gate.call("configure", runtime) as Dictionary
	if gate_result.get("ok") != true:
		return _remember_configuration_result(gate_result)
	_coordinator = COORDINATOR.new()
	var configured := _coordinator.call(
		"configure",
		_store,
		world,
		agent,
		_gate,
	) as Dictionary
	if configured.get("ok") != true:
		return _remember_configuration_result(configured)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
	}


func get_save_snapshot() -> Dictionary:
	var blocker := _save_blocker()
	var slots: Array[Dictionary] = []
	var selected_save_id := ""
	var slot_id := _session_slot_id()
	if blocker.is_empty() and _coordinator != null and not slot_id.is_empty():
		var discovered := _coordinator.call("discover_latest", slot_id) as Dictionary
		if discovered.get("ok") == true:
			var summary := (
				discovered.get("summary", {}) as Dictionary
			).duplicate(true)
			selected_save_id = "%s:%d" % [
				String(summary.get("slotId", slot_id)),
				int(summary.get("saveRevision", 0)),
			]
			summary["saveId"] = selected_save_id
			slots.append(summary)
		elif String(discovered.get("errorCode", "")) != (
			"SESSION_SAVE_NO_PUBLISHED_REVISION"
		):
			blocker = String(
				discovered.get(
					"errorCode",
					"SESSION_SAVE_STORE_FAILED",
				),
			)
	var can_save := blocker.is_empty()
	var can_continue := can_save and not slots.is_empty()
	return {
		"configured": _coordinator != null and _configuration_error.is_empty(),
		"canSave": can_save,
		"canContinue": can_continue,
		"disabledReason": blocker,
		"continueDisabledReason": (
			"" if can_continue else (
				"SESSION_SAVE_NO_PUBLISHED_REVISION" if can_save else blocker
			)
		),
		"slots": slots,
		"selectedSaveId": selected_save_id,
		"source": String(_session_config.get("source", "runtime")),
		"capabilityMode": String(
			_session_config.get("capabilityMode", "development"),
		),
		"formalReady": bool(_session_config.get("formalReady", false)),
		"lastResult": _last_result.duplicate(true),
	}


func update_resident_bindings(bindings_value: Variant) -> Dictionary:
	if not bindings_value is Array:
		return _failure("SESSION_LLM_BINDINGS_INVALID", false)
	var identities_value: Variant = _session_config.get("residentIdentities", [])
	if not identities_value is Array:
		return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
	var expected_ids: Dictionary = {}
	for identity_value: Variant in identities_value as Array:
		if not identity_value is Dictionary:
			return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
		var resident_id := String(
			(identity_value as Dictionary).get("residentId", "")
		).strip_edges()
		if resident_id.is_empty() or expected_ids.has(resident_id):
			return _failure("SESSION_RESIDENT_IDENTITIES_INVALID", false)
		expected_ids[resident_id] = true
	var seen_ids: Dictionary = {}
	var normalized: Array[Dictionary] = []
	for binding_value: Variant in bindings_value as Array:
		if not binding_value is Dictionary:
			return _failure("SESSION_LLM_BINDINGS_INVALID", false)
		var binding := binding_value as Dictionary
		var resident_id := String(binding.get("residentId", "")).strip_edges()
		if (
			resident_id.is_empty()
			or not expected_ids.has(resident_id)
			or seen_ids.has(resident_id)
			or not binding.get("llmBinding", {}) is Dictionary
		):
			return _failure("SESSION_LLM_BINDINGS_INVALID", false)
		seen_ids[resident_id] = true
		normalized.append({
			"residentId": resident_id,
			"llmBinding": (
				binding.get("llmBinding", {}) as Dictionary
			).duplicate(true),
		})
	if seen_ids.size() != expected_ids.size():
		return _failure("SESSION_LLM_BINDINGS_INVALID", false)
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("residentId", "")) < String(b.get("residentId", ""))
	)
	var previous := (
		_session_config.get("residentBindings", []) as Array
	).duplicate(true)
	_session_config["residentBindings"] = normalized.duplicate(true)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": normalized != previous,
		"previousBindings": previous,
		"residentBindings": normalized,
	}


func update_resident_roster(
	identities_value: Variant,
	bindings_value: Variant,
	opening_config_value: Variant,
) -> Dictionary:
	if (
		not identities_value is Array
		or not bindings_value is Array
		or not opening_config_value is Dictionary
	):
		return _failure("SESSION_RESIDENT_ROSTER_INVALID", false)
	var identities := (identities_value as Array).duplicate(true)
	var bindings := (bindings_value as Array).duplicate(true)
	if identities.is_empty() or identities.size() != bindings.size():
		return _failure("SESSION_RESIDENT_ROSTER_INVALID", false)
	_session_config["residentIdentities"] = identities
	_session_config["residentBindings"] = bindings
	_session_config["openingConfig"] = (
		opening_config_value as Dictionary
	).duplicate(true)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"residentCount": identities.size(),
	}


func create_save(payload: Dictionary = {}) -> Dictionary:
	var blocker := _save_blocker()
	if not blocker.is_empty():
		_last_result = _failure(blocker, false)
		return _last_result.duplicate(true)
	var identities_value: Variant = _session_config.get("residentIdentities")
	var identities: Array = (
		(identities_value as Array).duplicate(true)
		if identities_value is Array
		else []
	)
	var result := _coordinator.call("save", {
		"slotId": _session_config.get("slotId"),
		"sessionId": _session_config.get("sessionId"),
		"residentIdentities": identities,
		"sessionConfig": _manifest_session_config(),
		"savedAt": Time.get_datetime_string_from_system(false, false),
		"residentMessages": (
			(payload.get("residentMessages", []) as Array).duplicate(true)
			if payload.get("residentMessages", []) is Array
			else payload.get("residentMessages")
		),
	}) as Dictionary
	_last_result = result.duplicate(true)
	return result


func continue_latest(
	world_data: Dictionary,
	resident_identities: Array,
	agent_hydrator: Object,
) -> Dictionary:
	if not _configuration_error.is_empty() or _coordinator == null:
		_last_result = _failure(SERVICE_NOT_CONFIGURED, false)
		return _last_result.duplicate(true)
	if not _formal_world_ready():
		_last_result = _failure(FORMAL_WORLD_REQUIRED, false)
		return _last_result.duplicate(true)
	var slot_id := _session_slot_id()
	if slot_id.is_empty():
		_last_result = _failure("SESSION_SAVE_CONTEXT_INVALID", false)
		return _last_result.duplicate(true)
	var result := _coordinator.call(
		"restore_latest",
		slot_id,
		world_data.duplicate(true),
		resident_identities.duplicate(true),
		agent_hydrator,
	) as Dictionary
	_last_result = result.duplicate(true)
	return result


func continue_revision(
	session_id: String,
	save_revision: int,
	world_data: Dictionary,
	resident_identities: Array,
	agent_hydrator: Object,
) -> Dictionary:
	if not _configuration_error.is_empty() or _coordinator == null:
		_last_result = _failure(SERVICE_NOT_CONFIGURED, false)
		return _last_result.duplicate(true)
	if not _formal_world_ready():
		_last_result = _failure(FORMAL_WORLD_REQUIRED, false)
		return _last_result.duplicate(true)
	var slot_id := _session_slot_id()
	var normalized_session_id := session_id.strip_edges()
	if (
		slot_id.is_empty()
		or normalized_session_id.is_empty()
		or normalized_session_id != session_id
		or save_revision <= 0
	):
		_last_result = _failure("SESSION_SAVE_CONTEXT_INVALID", false)
		return _last_result.duplicate(true)
	var result := _coordinator.call(
		"restore_revision",
		slot_id,
		normalized_session_id,
		save_revision,
		world_data.duplicate(true),
		resident_identities.duplicate(true),
		agent_hydrator,
	) as Dictionary
	_last_result = result.duplicate(true)
	return result


func _save_blocker() -> String:
	if not _configuration_error.is_empty():
		return String(
			_configuration_error.get("errorCode", SERVICE_NOT_CONFIGURED),
		)
	if _coordinator == null:
		return SERVICE_NOT_CONFIGURED
	if not _formal_world_ready():
		return FORMAL_WORLD_REQUIRED
	if _session_slot_id().is_empty() or _session_id().is_empty():
		return "SESSION_SAVE_CONTEXT_INVALID"
	if (
		_runtime == null
		or not is_instance_valid(_runtime)
		or not _runtime.has_method("get_resident_identity_snapshot")
	):
		return "SESSION_SAVE_IDENTITY_NOT_CONFIRMED"
	var snapshot_value: Variant = _runtime.call(
		"get_resident_identity_snapshot",
	)
	var snapshot_status_value: Variant = (
		(snapshot_value as Dictionary).get("status")
		if snapshot_value is Dictionary
		else null
	)
	if (
		not snapshot_value is Dictionary
		or not snapshot_status_value is String
		or snapshot_status_value != "confirmed"
		or not _identity_snapshot_matches(
			snapshot_value as Dictionary,
			_session_config.get("residentIdentities"),
		)
	):
		return "SESSION_SAVE_IDENTITY_NOT_CONFIRMED"
	if _agent == null or not is_instance_valid(_agent):
		return "SESSION_SAVE_AGENT_CONTEXT_MISMATCH"
	var context_value: Variant = _agent.call("get_save_context")
	if not context_value is Dictionary:
		return "SESSION_SAVE_AGENT_CONTEXT_MISMATCH"
	var context := context_value as Dictionary
	if MANIFEST.validate_context(context).get("ok") != true:
		return "SESSION_SAVE_AGENT_CONTEXT_MISMATCH"
	if (
		context.get("slot_id") != _session_config.get("slotId")
		or context.get("session_id") != _session_config.get("sessionId")
	):
		return "SESSION_SAVE_AGENT_CONTEXT_MISMATCH"
	return ""


func _manifest_session_config() -> Dictionary:
	var filtered := {}
	for field_name in [
		"mode",
		"sessionId",
		"openingConfig",
		"residentIdentities",
		"connectedResidents",
		"worldStartMode",
		"useLiveModel",
		"enablePlayerAvatar",
		"enableTestUi",
	]:
		if _session_config.has(field_name):
			filtered[field_name] = _duplicate_value(
				_session_config.get(field_name),
			)
	if _session_config.has("residentBindings"):
		# The runtime binding also carries presentation-only residentName. A save
		# only needs the stable Agent routing identity; rebuild the allow-listed
		# shape here so no future runtime/provider metadata can leak into a
		# published session config.
		var bindings_value: Variant = _session_config.get("residentBindings")
		if not bindings_value is Array:
			filtered["residentBindings"] = _duplicate_value(bindings_value)
		else:
			var saved_bindings: Array = []
			for value: Variant in bindings_value as Array:
				if not value is Dictionary:
					saved_bindings.append(_duplicate_value(value))
					continue
				var binding := value as Dictionary
				var llm_value: Variant = binding.get("llmBinding")
				var saved_binding := {
					"residentId": binding.get("residentId"),
					"llmBinding": _duplicate_value(llm_value),
				}
				if llm_value is Dictionary:
					var llm := llm_value as Dictionary
					saved_binding["llmBinding"] = {
						"mode": llm.get("mode"),
						"providerId": llm.get("providerId"),
						"modelId": llm.get("modelId"),
					}
				saved_bindings.append(saved_binding)
			filtered["residentBindings"] = saved_bindings
	return filtered


func _formal_world_ready() -> bool:
	return (
		_session_config.get("worldStartMode") is String
		and _session_config.get("worldStartMode") == "formal"
		and _session_config.get("capabilityMode") is String
		and _session_config.get("capabilityMode") == "formal"
		and _session_config.get("formalReady") is bool
		and _session_config.get("formalReady") == true
	)


func _session_slot_id() -> String:
	var value: Variant = _session_config.get("slotId")
	if not value is String:
		return ""
	var slot_id := value as String
	return slot_id if slot_id == slot_id.strip_edges() else ""


func _session_id() -> String:
	var value: Variant = _session_config.get("sessionId")
	if not value is String:
		return ""
	var session_id := value as String
	return session_id if session_id == session_id.strip_edges() else ""


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


func _identity_snapshot_matches(
	snapshot: Dictionary,
	expected_identities: Variant,
) -> bool:
	var expected_result := MANIFEST.resident_ids(expected_identities)
	if expected_result.get("ok") != true:
		return false
	var residents_value: Variant = snapshot.get("residents")
	if not residents_value is Array:
		return false
	var actual_ids: Array[String] = []
	for resident_value: Variant in residents_value as Array:
		if not resident_value is Dictionary:
			return false
		var resident_id_value: Variant = (
			resident_value as Dictionary
		).get("residentId")
		if not resident_id_value is String:
			return false
		var resident_id := resident_id_value as String
		if (
			resident_id.is_empty()
			or resident_id != resident_id.strip_edges()
			or actual_ids.has(resident_id)
		):
			return false
		actual_ids.append(resident_id)
	actual_ids.sort()
	return actual_ids == (
		expected_result.get("residentIds", []) as Array
	)


func _remember_configuration_failure(error_code: String) -> Dictionary:
	return _remember_configuration_result(_failure(error_code, false))


func _remember_configuration_result(result: Dictionary) -> Dictionary:
	_configuration_error = result.duplicate(true)
	_last_result = result.duplicate(true)
	return result


func _failure(error_code: String, retryable: bool) -> Dictionary:
	return RESULT_SHAPES.failure_retryable(error_code, retryable)
