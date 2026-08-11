class_name TownResidentConditionRuntime
extends RefCounted


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const CATALOG := preload(
	"res://world/data/town/TownResidentConditionCatalog.gd"
)
const ACTIVITY_PROFILES := preload(
	"res://world/data/town/TownResidentConditionActivityProfiles.gd"
)
const RANDOM_MODULUS := 2147483647
const RANDOM_MULTIPLIER := 48271
const CONDITION_FIELDS: Array[String] = [
	"conditionId",
	"kind",
	"label",
	"severity",
	"sourceKind",
	"sourceRef",
	"startedAtMinute",
	"lastChangedAtMinute",
	"state",
	"nextChangeAtMinute",
]
const TRIGGER_FIELDS: Array[String] = [
	"triggerId",
	"triggerKind",
	"sourceKind",
	"sourceRef",
	"occurredAtMinute",
	"durationMinutes",
	"riskTags",
	"reliefTags",
	"facts",
]
const EXPOSURE_FIELDS: Array[String] = [
	"exposureId",
	"sourceKind",
	"sourceRef",
	"startedAtMinute",
	"riskTags",
	"facts",
]
const RESIDENT_FIELDS: Array[String] = [
	"residentId",
	"conditions",
	"conditionRollState",
	"activeExposure",
	"revision",
]
const ROLL_STATE_FIELDS: Array[String] = [
	"randomState",
	"processedTriggerIds",
	"kindCooldowns",
	"nextAmbientCheckAtMinute",
	"lastCompletedSleepActionId",
]
const EVENT_TYPES := [
	"condition_started",
	"condition_changed",
	"condition_recovering",
	"condition_resolved",
]
const RAIN_OR_SNOW := ["小雨", "中雨", "大雨", "雷暴", "下雪"]
const LIFE_STATE_FIELDS := [
	"energy",
	"satiety",
	"stress",
	"social",
	"solitude",
]


var _catalog: Dictionary = {}
var _conditions_by_kind: Dictionary = {}
var _needs_by_kind: Dictionary = {}
var _known_risk_tags: Dictionary = {}
var _known_relief_tags: Dictionary = {}
var _known_source_kinds: Dictionary = {}
var _known_trigger_kinds: Dictionary = {}
var _activity_profiles_by_id: Dictionary = {}
var _residents: Dictionary = {}
var _condition_sequence := 0
var _event_sequence := 0
var _configured := false


func configure(
	catalog: Dictionary = {},
	activity_profiles: Dictionary = {},
) -> Dictionary:
	if _configured:
		return _failure("CONDITION_RUNTIME_ALREADY_CONFIGURED")
	var resolved_catalog := (
		CATALOG.load_catalog()
		if catalog.is_empty()
		else catalog.duplicate(true)
	)
	var errors := CATALOG.validate(resolved_catalog)
	if not errors.is_empty():
		return _failure(
			"CONDITION_CATALOG_INVALID",
			{"errors": Array(errors)},
		)
	var resolved_profiles := (
		ACTIVITY_PROFILES.load_profiles()
		if activity_profiles.is_empty()
		else activity_profiles.duplicate(true)
	)
	var profile_errors := ACTIVITY_PROFILES.validate(
		resolved_profiles,
		{},
		resolved_catalog,
	)
	if not profile_errors.is_empty():
		return _failure(
			"CONDITION_ACTIVITY_PROFILES_INVALID",
			{"errors": Array(profile_errors)},
		)
	_catalog = resolved_catalog
	_activity_profiles_by_id = ACTIVITY_PROFILES.profiles_by_activity(
		resolved_profiles,
	)
	for value: Variant in _catalog.get("conditions", []) as Array:
		var definition := value as Dictionary
		_conditions_by_kind[String(definition.get("kind", ""))] = (
			definition.duplicate(true)
		)
	for value: Variant in _catalog.get("needs", []) as Array:
		var definition := value as Dictionary
		_needs_by_kind[String(definition.get("kind", ""))] = (
			definition.duplicate(true)
		)
	_index_strings(_catalog.get("riskTags", []) as Array, _known_risk_tags)
	_index_strings(
		_catalog.get("reliefTags", []) as Array,
		_known_relief_tags,
	)
	_index_strings(
		_catalog.get("sourceKinds", []) as Array,
		_known_source_kinds,
	)
	_index_strings(
		_catalog.get("triggerKinds", []) as Array,
		_known_trigger_kinds,
	)
	_configured = true
	return {
		"ok": true,
		"errorCode": "",
		"conditionKindCount": _conditions_by_kind.size(),
		"needKindCount": _needs_by_kind.size(),
		"activityProfileCount": _activity_profiles_by_id.size(),
	}


func initialize_resident(
	resident_id: String,
	random_seed: int,
) -> Dictionary:
	if not _configured:
		return _failure("CONDITION_RUNTIME_NOT_CONFIGURED")
	var normalized_id := resident_id.strip_edges()
	if normalized_id.is_empty() or _residents.has(normalized_id):
		return _failure("CONDITION_RESIDENT_ID_INVALID")
	var random_state := posmod(random_seed, RANDOM_MODULUS - 1) + 1
	_residents[normalized_id] = {
		"residentId": normalized_id,
		"conditions": [],
		"conditionRollState": {
			"randomState": random_state,
			"processedTriggerIds": [],
			"kindCooldowns": {},
			"nextAmbientCheckAtMinute": null,
			"lastCompletedSleepActionId": "",
		},
		"activeExposure": {},
		"revision": 1,
	}
	return _success(normalized_id, {"created": true})


func reset_resident(resident_id: String, random_seed: int) -> Dictionary:
	var normalized_id := resident_id.strip_edges()
	if not _residents.has(normalized_id):
		return _failure("CONDITION_RESIDENT_ID_INVALID")
	_residents.erase(normalized_id)
	return initialize_resident(normalized_id, random_seed)


func has_resident(resident_id: String) -> bool:
	return _residents.has(resident_id)


func resident_ids() -> Array[String]:
	var result: Array[String] = []
	for resident_id_value: Variant in _residents:
		result.append(String(resident_id_value))
	result.sort()
	return result


func submit_sleep_result(
	resident_id: String,
	sleep_result: Dictionary,
	life_state: Dictionary,
) -> Dictionary:
	if not _configured:
		return _failure("CONDITION_RUNTIME_NOT_CONFIGURED")
	if not _residents.has(resident_id):
		return _failure("CONDITION_RESIDENT_UNKNOWN")
	var errors := _validate_sleep_result_input(sleep_result, life_state)
	if not errors.is_empty():
		return _failure(
			"CONDITION_SLEEP_RESULT_INVALID",
			{"errors": errors},
		)
	if not bool(sleep_result.get("wakeEligible", false)):
		return _success(
			resident_id,
			{
				"processed": false,
				"duplicate": false,
				"candidateKinds": [],
				"outcome": {},
				"events": [],
				"reason": "SLEEP_TOO_SHORT_FOR_WAKE_CHECK",
			},
		)
	var action_id := String(sleep_result.get("actionId", ""))
	return submit_trigger(
		resident_id,
		{
			"triggerId": "wake:%s" % action_id,
			"triggerKind": "wake",
			"sourceKind": "sleep_action",
			"sourceRef": action_id,
			"occurredAtMinute": int(
				sleep_result.get("completedAtMinute", 0),
			),
			"durationMinutes": int(
				sleep_result.get("actualSleepMinutes", 0),
			),
			"riskTags": [],
			"reliefTags": ["sleep"],
			"facts": {
				"actualSleepMinutes": int(
					sleep_result.get("actualSleepMinutes", 0),
				),
				"sleepInterrupted": bool(
					sleep_result.get("interrupted", false),
				),
				"lifeState": life_state.duplicate(true),
			},
		},
	)


func submit_world_action_result(
	resident_id: String,
	action_result: Dictionary,
	life_state: Dictionary,
) -> Dictionary:
	if not _configured:
		return _failure("CONDITION_RUNTIME_NOT_CONFIGURED")
	if not _residents.has(resident_id):
		return _failure("CONDITION_RESIDENT_UNKNOWN")
	var errors := _validate_world_action_result_input(
		action_result,
		life_state,
	)
	if not errors.is_empty():
		return _failure(
			"CONDITION_ACTION_RESULT_INVALID",
			{"errors": errors},
		)
	var status := String(action_result.get("status", ""))
	var started_at := int(action_result.get("startedAtMinute", 0))
	var occurred_at := int(action_result.get("occurredAtMinute", 0))
	var facts := (
		action_result.get("context", {}) as Dictionary
	).duplicate(true)
	facts["completed"] = status == "completed"
	facts["interrupted"] = status == "interrupted"
	facts["status"] = status
	facts["lifeState"] = life_state.duplicate(true)
	return submit_trigger(
		resident_id,
		{
			"triggerId": "action-result:%s" % String(
				action_result.get("resultId", ""),
			),
			"triggerKind": "action_result",
			"sourceKind": String(
				action_result.get("sourceKind", ""),
			),
			"sourceRef": String(
				action_result.get("sourceRef", ""),
			),
			"occurredAtMinute": occurred_at,
			"durationMinutes": occurred_at - started_at,
			"riskTags": (
				action_result.get("riskTags", []) as Array
			).duplicate(),
			"reliefTags": (
				action_result.get("reliefTags", []) as Array
			).duplicate(),
			"facts": facts,
		},
	)


func submit_activity_execution_result(
	resident_id: String,
	execution_result: Dictionary,
	life_state: Dictionary,
) -> Dictionary:
	if not _configured:
		return _failure("CONDITION_RUNTIME_NOT_CONFIGURED")
	if not _residents.has(resident_id):
		return _failure("CONDITION_RESIDENT_UNKNOWN")
	var errors := _validate_activity_execution_result(execution_result)
	if not errors.is_empty():
		return _failure(
			"CONDITION_ACTIVITY_EXECUTION_INVALID",
			{"errors": errors},
		)
	var activity_id := String(execution_result.get("activityId", ""))
	if activity_id == "activity_home_sleep":
		return _failure("CONDITION_SLEEP_REQUIRES_SLEEP_RESULT")
	var profile := _activity_profiles_by_id.get(activity_id, {}) as Dictionary
	if profile.is_empty():
		return _success(
			resident_id,
			{
				"processed": false,
				"duplicate": false,
				"candidateKinds": [],
				"outcome": {},
				"events": [],
				"reason": "ACTIVITY_HAS_NO_CONDITION_PROFILE",
			},
		)
	return submit_world_action_result(
		resident_id,
		{
			"resultId": String(execution_result.get("resultId", "")),
			"sourceKind": "formal_activity",
			"sourceRef": String(execution_result.get("actionId", "")),
			"startedAtMinute": int(
				execution_result.get("startedAtMinute", 0),
			),
			"occurredAtMinute": int(
				execution_result.get("occurredAtMinute", 0),
			),
			"status": String(execution_result.get("status", "")),
			"riskTags": (
				profile.get("riskTags", []) as Array
			).duplicate(),
			"reliefTags": (
				profile.get("reliefTags", []) as Array
			).duplicate(),
			"context": {
				"activityId": activity_id,
				"placeId": String(execution_result.get("placeId", "")),
				"weather": String(execution_result.get("weather", "")),
				"outdoors": bool(execution_result.get("outdoors", false)),
			},
		},
		life_state,
	)


func submit_trigger(
	resident_id: String,
	trigger: Dictionary,
) -> Dictionary:
	if not _configured:
		return _failure("CONDITION_RUNTIME_NOT_CONFIGURED")
	var resident := _residents.get(resident_id, {}) as Dictionary
	if resident.is_empty():
		return _failure("CONDITION_RESIDENT_UNKNOWN")
	var validation := _validate_trigger(trigger)
	if not validation.is_empty():
		return _failure(
			"CONDITION_TRIGGER_INVALID",
			{"errors": validation},
		)
	var trigger_id := String(trigger.get("triggerId", ""))
	var roll_state := resident.get("conditionRollState", {}) as Dictionary
	var processed_ids := (
		roll_state.get("processedTriggerIds", []) as Array
	)
	var repeats_completed_sleep := (
		String(trigger.get("triggerKind", "")) == "wake"
		and String(trigger.get("sourceRef", ""))
		== String(roll_state.get("lastCompletedSleepActionId", ""))
	)
	if processed_ids.has(trigger_id) or repeats_completed_sleep:
		return _success(
			resident_id,
			{
				"processed": false,
				"duplicate": true,
				"outcome": {},
				"events": [],
			},
		)
	var events: Array[Dictionary] = []
	var occurred_at := int(trigger.get("occurredAtMinute", 0))
	var relief_events := _apply_immediate_relief(
		resident,
		_effective_relief_tags(trigger),
		occurred_at,
		String(trigger.get("sourceRef", "")),
		(
			(trigger.get("facts", {}) as Dictionary).get(
				"targetConditionIds",
				[],
			) as Array
		).duplicate(),
	)
	for event: Dictionary in relief_events:
		events.append(event)
	var candidates := _collect_candidates(resident, trigger)
	var outcome: Dictionary = {}
	if not candidates.is_empty():
		var roll := _take_random(resident)
		var cumulative := 0.0
		for candidate: Dictionary in candidates:
			cumulative += float(candidate.get("chance", 0.0))
			if roll < cumulative:
				outcome = _apply_candidate(resident, candidate, trigger)
				if not outcome.is_empty():
					events.append(outcome.get("event", {}) as Dictionary)
				break
	_mark_trigger_processed(resident, trigger_id)
	if String(trigger.get("triggerKind", "")) == "wake":
		roll_state["lastCompletedSleepActionId"] = String(
			trigger.get("sourceRef", ""),
		)
	resident["conditionRollState"] = roll_state
	resident["revision"] = int(resident.get("revision", 0)) + 1
	_residents[resident_id] = resident
	return _success(
		resident_id,
		{
			"processed": true,
			"duplicate": false,
			"candidateKinds": _candidate_kinds(candidates),
			"outcome": outcome.get("condition", {}) as Dictionary,
			"events": events,
		},
	)


func begin_ambient_exposure(
	resident_id: String,
	exposure: Dictionary,
) -> Dictionary:
	if not _configured:
		return _failure("CONDITION_RUNTIME_NOT_CONFIGURED")
	var resident := _residents.get(resident_id, {}) as Dictionary
	if resident.is_empty():
		return _failure("CONDITION_RESIDENT_UNKNOWN")
	var errors := _validate_exposure(exposure)
	if not errors.is_empty():
		return _failure(
			"CONDITION_EXPOSURE_INVALID",
			{"errors": errors},
		)
	var current := resident.get("activeExposure", {}) as Dictionary
	if not current.is_empty():
		if String(current.get("exposureId", "")) == String(
			exposure.get("exposureId", ""),
		):
			return _success(
				resident_id,
				{"created": false, "exposure": current.duplicate(true)},
			)
		return _failure("CONDITION_EXPOSURE_ALREADY_ACTIVE")
	resident["activeExposure"] = exposure.duplicate(true)
	_schedule_next_ambient_check(
		resident,
		int(exposure.get("startedAtMinute", 0)),
	)
	resident["revision"] = int(resident.get("revision", 0)) + 1
	_residents[resident_id] = resident
	return _success(
		resident_id,
		{
			"created": true,
			"exposure": exposure.duplicate(true),
			"nextAmbientCheckAtMinute": (
				resident.get("conditionRollState", {}) as Dictionary
			).get("nextAmbientCheckAtMinute"),
		},
	)


func begin_world_weather_exposure(
	resident_id: String,
	exposure_fact: Dictionary,
) -> Dictionary:
	if not _configured:
		return _failure("CONDITION_RUNTIME_NOT_CONFIGURED")
	if not _residents.has(resident_id):
		return _failure("CONDITION_RESIDENT_UNKNOWN")
	var errors := _validate_world_weather_exposure(exposure_fact)
	if not errors.is_empty():
		return _failure(
			"CONDITION_WEATHER_EXPOSURE_INVALID",
			{"errors": errors},
		)
	return begin_ambient_exposure(
		resident_id,
		{
			"exposureId": String(exposure_fact.get("exposureId", "")),
			"sourceKind": String(exposure_fact.get("sourceKind", "")),
			"sourceRef": String(exposure_fact.get("sourceRef", "")),
			"startedAtMinute": int(
				exposure_fact.get("startedAtMinute", 0),
			),
			"riskTags": (
				exposure_fact.get("riskTags", []) as Array
			).duplicate(),
			"facts": {
				"outdoors": true,
				"weather": String(exposure_fact.get("weather", "")),
				"placeId": String(exposure_fact.get("placeId", "")),
			},
		},
	)


func end_ambient_exposure(
	resident_id: String,
	exposure_id: String,
) -> Dictionary:
	var resident := _residents.get(resident_id, {}) as Dictionary
	if resident.is_empty():
		return _failure("CONDITION_RESIDENT_UNKNOWN")
	var active := resident.get("activeExposure", {}) as Dictionary
	if (
		active.is_empty()
		or String(active.get("exposureId", "")) != exposure_id
	):
		return _failure("CONDITION_EXPOSURE_NOT_ACTIVE")
	resident["activeExposure"] = {}
	var roll_state := resident.get("conditionRollState", {}) as Dictionary
	roll_state["nextAmbientCheckAtMinute"] = null
	resident["conditionRollState"] = roll_state
	resident["revision"] = int(resident.get("revision", 0)) + 1
	_residents[resident_id] = resident
	return _success(resident_id, {"ended": true})


func advance_resident(
	resident_id: String,
	now: int,
	context: Dictionary = {},
) -> Dictionary:
	if not _configured:
		return _failure("CONDITION_RUNTIME_NOT_CONFIGURED")
	var resident := _residents.get(resident_id, {}) as Dictionary
	if resident.is_empty():
		return _failure("CONDITION_RESIDENT_UNKNOWN")
	if now < 0 or not _validate_due_context(context).is_empty():
		return _failure("CONDITION_ADVANCE_INVALID")
	var events: Array[Dictionary] = []
	var ambient_results: Array[Dictionary] = []
	var ambient_guard := 0
	while ambient_guard < 32:
		ambient_guard += 1
		var active := resident.get("activeExposure", {}) as Dictionary
		var roll_state := resident.get("conditionRollState", {}) as Dictionary
		var next_value: Variant = roll_state.get(
			"nextAmbientCheckAtMinute",
		)
		if active.is_empty() or next_value == null or int(next_value) > now:
			break
		var check_at := int(next_value)
		var trigger := {
			"triggerId": "%s:%d" % [
				String(active.get("exposureId", "")),
				check_at,
			],
			"triggerKind": "ambient_exposure",
			"sourceKind": String(active.get("sourceKind", "")),
			"sourceRef": String(active.get("sourceRef", "")),
			"occurredAtMinute": check_at,
			"durationMinutes": check_at - int(
				active.get("startedAtMinute", check_at),
			),
			"riskTags": (active.get("riskTags", []) as Array).duplicate(),
			"reliefTags": [],
			"facts": (active.get("facts", {}) as Dictionary).duplicate(true),
		}
		if context.get("lifeState") is Dictionary:
			(trigger.get("facts", {}) as Dictionary)["lifeState"] = (
				context.get("lifeState", {}) as Dictionary
			).duplicate(true)
		var result := submit_trigger(resident_id, trigger)
		if result.get("ok") != true:
			return result
		ambient_results.append(result)
		for event_value: Variant in result.get("events", []) as Array:
			if event_value is Dictionary:
				events.append((event_value as Dictionary).duplicate(true))
		resident = _residents.get(resident_id, {}) as Dictionary
		_schedule_next_ambient_check(resident, check_at)
		resident["revision"] = int(resident.get("revision", 0)) + 1
		_residents[resident_id] = resident
	var due_guard := 0
	while due_guard < 64:
		due_guard += 1
		var due_index := _next_due_condition_index(resident, now)
		if due_index < 0:
			break
		var due_events := _process_condition_due(
			resident,
			due_index,
			context,
		)
		for event: Dictionary in due_events:
			events.append(event)
	if not events.is_empty():
		resident["revision"] = int(resident.get("revision", 0)) + 1
	_residents[resident_id] = resident
	return _success(
		resident_id,
		{
			"advancedToMinute": now,
			"ambientResults": ambient_results,
			"events": events,
		},
	)


func get_conditions(resident_id: String) -> Array[Dictionary]:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var result: Array[Dictionary] = []
	for value: Variant in resident.get("conditions", []) as Array:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("conditionId", "")) < String(
				b.get("conditionId", ""),
			)
	)
	return result


func condition_accepts_relief(
	resident_id: String,
	condition_id: String,
	relief_tag: String,
) -> bool:
	if not _residents.has(resident_id) or relief_tag.strip_edges().is_empty():
		return false
	for condition_value: Variant in (
		(_residents.get(resident_id, {}) as Dictionary).get(
			"conditions",
			[],
		) as Array
	):
		if not condition_value is Dictionary:
			continue
		var condition := condition_value as Dictionary
		if String(condition.get("conditionId", "")) != condition_id:
			continue
		var definition := _conditions_by_kind.get(
			String(condition.get("kind", "")),
			{},
		) as Dictionary
		return (definition.get("reliefTags", []) as Array).has(
			relief_tag.strip_edges(),
		)
	return false


func get_active_needs(resident_id: String) -> Array[Dictionary]:
	var resident := _residents.get(resident_id, {}) as Dictionary
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for condition_value: Variant in resident.get("conditions", []) as Array:
		if not condition_value is Dictionary:
			continue
		var condition := condition_value as Dictionary
		var definition := _conditions_by_kind.get(
			String(condition.get("kind", "")),
			{},
		) as Dictionary
		for need_value: Variant in definition.get("needKinds", []) as Array:
			var need_kind := String(need_value)
			var dedupe_key := "%s:%s" % [
				String(condition.get("conditionId", "")),
				need_kind,
			]
			if seen.has(dedupe_key):
				continue
			seen[dedupe_key] = true
			var need_definition := _needs_by_kind.get(need_kind, {}) as Dictionary
			result.append({
				"needId": "need-%s-%s" % [
					String(condition.get("conditionId", "")),
					need_kind,
				],
				"kind": need_kind,
				"label": String(need_definition.get("label", "")),
				"urgency": _urgency_for_severity(
					String(condition.get("severity", "minor")),
				),
				"conditionId": String(condition.get("conditionId", "")),
				"conditionKind": String(condition.get("kind", "")),
				"responseRequirements": (
					need_definition.get("responseRequirements", []) as Array
				).duplicate(),
			})
	return result


func get_roll_state(resident_id: String) -> Dictionary:
	var resident := _residents.get(resident_id, {}) as Dictionary
	return (
		resident.get("conditionRollState", {}) as Dictionary
	).duplicate(true)


func get_active_exposure(resident_id: String) -> Dictionary:
	var resident := _residents.get(resident_id, {}) as Dictionary
	return (
		resident.get("activeExposure", {}) as Dictionary
	).duplicate(true)


func get_resident_revision(resident_id: String) -> int:
	return int(
		(_residents.get(resident_id, {}) as Dictionary).get("revision", 0),
	)


func create_save_snapshot() -> Dictionary:
	return {
		"schemaVersion": 1,
		"conditionSequence": _condition_sequence,
		"eventSequence": _event_sequence,
		"residents": _residents.duplicate(true),
	}


func restore_from_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONDITION_RUNTIME_NOT_CONFIGURED")
	var validation := _validate_snapshot(snapshot)
	if not validation.get("errors", []).is_empty():
		return _failure(
			"CONDITION_SNAPSHOT_INVALID",
			{"errors": validation.get("errors", [])},
		)
	_condition_sequence = int(snapshot.get("conditionSequence", 0))
	_event_sequence = int(snapshot.get("eventSequence", 0))
	_residents = (snapshot.get("residents", {}) as Dictionary).duplicate(true)
	return {
		"ok": true,
		"errorCode": "",
		"residentCount": _residents.size(),
	}


func _collect_candidates(
	resident: Dictionary,
	trigger: Dictionary,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _trigger_had_real_effect(trigger):
		return result
	var trigger_kind := String(trigger.get("triggerKind", ""))
	var source_kind := String(trigger.get("sourceKind", ""))
	var risk_tags := trigger.get("riskTags", []) as Array
	var now := int(trigger.get("occurredAtMinute", 0))
	var cooldowns := (
		resident.get("conditionRollState", {}) as Dictionary
	).get("kindCooldowns", {}) as Dictionary
	for kind_value: Variant in _conditions_by_kind:
		var kind := String(kind_value)
		var definition := _conditions_by_kind.get(kind, {}) as Dictionary
		var chances := definition.get("baseChanceByTrigger", {}) as Dictionary
		if not chances.has(trigger_kind):
			continue
		if not (definition.get("sourceKinds", []) as Array).has(source_kind):
			continue
		if trigger_kind != "wake" and not _arrays_intersect(
			definition.get("riskTags", []) as Array,
			risk_tags,
		):
			continue
		if not _required_conditions_present(resident, definition):
			continue
		if not _eligibility_matches(definition, trigger):
			continue
		if not _weather_risk_is_grounded(definition, trigger):
			continue
		var existing_index := _condition_index_by_kind(resident, kind)
		if existing_index >= 0 and _condition_at_maximum(
			resident,
			existing_index,
			definition,
		):
			continue
		var cooldown_key := _cooldown_key(kind, source_kind)
		if int(cooldowns.get(cooldown_key, 0)) > now:
			continue
		var chance := _adjusted_chance(
			float(chances.get(trigger_kind, 0.0)),
			kind,
			trigger,
		)
		if chance <= 0.0:
			continue
		result.append({
			"kind": kind,
			"chance": chance,
			"definition": definition,
		})
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("kind", "")) < String(b.get("kind", ""))
	)
	var total := 0.0
	for candidate: Dictionary in result:
		total += float(candidate.get("chance", 0.0))
	if total > 0.75:
		var scale := 0.75 / total
		for candidate: Dictionary in result:
			candidate["chance"] = float(candidate.get("chance", 0.0)) * scale
	return result


func _apply_candidate(
	resident: Dictionary,
	candidate: Dictionary,
	trigger: Dictionary,
) -> Dictionary:
	var kind := String(candidate.get("kind", ""))
	var definition := candidate.get("definition", {}) as Dictionary
	var now := int(trigger.get("occurredAtMinute", 0))
	var conditions := resident.get("conditions", []) as Array
	var existing_index := _condition_index_by_kind(resident, kind)
	var event_type := "condition_started"
	var condition: Dictionary
	if existing_index >= 0:
		condition = (conditions[existing_index] as Dictionary).duplicate(true)
		condition["severity"] = _next_severity(
			String(condition.get("severity", "minor")),
			String(definition.get("maxSeverity", "serious")),
		)
		condition["state"] = "active"
		condition["lastChangedAtMinute"] = now
		condition["sourceKind"] = String(trigger.get("sourceKind", ""))
		condition["sourceRef"] = String(trigger.get("sourceRef", ""))
		event_type = "condition_changed"
	else:
		_condition_sequence += 1
		condition = {
			"conditionId": "condition-%s-%06d" % [
				String(resident.get("residentId", "resident")),
				_condition_sequence,
			],
			"kind": kind,
			"label": "",
			"severity": "minor",
			"sourceKind": String(trigger.get("sourceKind", "")),
			"sourceRef": String(trigger.get("sourceRef", "")),
			"startedAtMinute": now,
			"lastChangedAtMinute": now,
			"state": "active",
			"nextChangeAtMinute": now,
		}
	condition["label"] = _label_for(definition, String(condition["severity"]))
	_schedule_condition_change(resident, condition, now, definition)
	if existing_index >= 0:
		conditions[existing_index] = condition
	else:
		conditions.append(condition)
	resident["conditions"] = conditions
	var roll_state := resident.get("conditionRollState", {}) as Dictionary
	var cooldowns := roll_state.get("kindCooldowns", {}) as Dictionary
	cooldowns[_cooldown_key(
		kind,
		String(trigger.get("sourceKind", "")),
	)] = now + int(definition.get("cooldownMinutes", 0))
	roll_state["kindCooldowns"] = cooldowns
	resident["conditionRollState"] = roll_state
	var event := _condition_event(
		resident,
		condition,
		event_type,
		now,
		String(trigger.get("triggerId", "")),
	)
	return {"condition": condition.duplicate(true), "event": event}


func _apply_immediate_relief(
	resident: Dictionary,
	relief_tags: Array,
	now: int,
	source_ref: String,
	target_condition_ids: Array = [],
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if relief_tags.is_empty():
		return events
	var conditions := resident.get("conditions", []) as Array
	for index in range(conditions.size() - 1, -1, -1):
		var condition := (conditions[index] as Dictionary).duplicate(true)
		if (
			not target_condition_ids.is_empty()
			and not target_condition_ids.has(
				String(condition.get("conditionId", "")),
			)
		):
			continue
		var definition := _conditions_by_kind.get(
			String(condition.get("kind", "")),
			{},
		) as Dictionary
		if not _arrays_intersect(
			definition.get("reliefTags", []) as Array,
			relief_tags,
		):
			continue
		if (
			String(condition.get("kind", "")) == "wet"
			and relief_tags.has("indoor_dry")
		):
			conditions.remove_at(index)
			events.append(_condition_event(
				resident,
				condition,
				"condition_resolved",
				now,
				source_ref,
			))
			continue
		var previous_state := String(condition.get("state", "active"))
		if previous_state == "recovering":
			conditions.remove_at(index)
			events.append(_condition_event(
				resident,
				condition,
				"condition_resolved",
				now,
				source_ref,
			))
			continue
		condition["state"] = "recovering"
		condition["lastChangedAtMinute"] = now
		var change_range := definition.get("nextChangeMinutes", {}) as Dictionary
		condition["nextChangeAtMinute"] = now + maxi(
			15,
			int(change_range.get("min", 30)) / 2,
		)
		conditions[index] = condition
		events.append(_condition_event(
			resident,
			condition,
			"condition_recovering",
			now,
			source_ref,
		))
	resident["conditions"] = conditions
	return events


func _process_condition_due(
	resident: Dictionary,
	condition_index: int,
	context: Dictionary,
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var conditions := resident.get("conditions", []) as Array
	var condition := (conditions[condition_index] as Dictionary).duplicate(true)
	var definition := _conditions_by_kind.get(
		String(condition.get("kind", "")),
		{},
	) as Dictionary
	var due_at := int(condition.get("nextChangeAtMinute", 0))
	var relief_tags := context.get("reliefTags", []) as Array
	var risk_tags := context.get("riskTags", []) as Array
	var has_relief := _arrays_intersect(
		definition.get("reliefTags", []) as Array,
		relief_tags,
	)
	var has_risk := _arrays_intersect(
		definition.get("riskTags", []) as Array,
		risk_tags,
	)
	if has_relief or String(condition.get("state", "")) == "recovering":
		if String(condition.get("state", "")) == "recovering":
			conditions.remove_at(condition_index)
			events.append(_condition_event(
				resident,
				condition,
				"condition_resolved",
				due_at,
				"condition_due",
			))
		else:
			condition["state"] = "recovering"
			condition["lastChangedAtMinute"] = due_at
			_schedule_condition_change(resident, condition, due_at, definition)
			conditions[condition_index] = condition
			events.append(_condition_event(
				resident,
				condition,
				"condition_recovering",
				due_at,
				"condition_due",
			))
	elif has_risk:
		var previous_severity := String(condition.get("severity", "minor"))
		condition["severity"] = _next_severity(
			previous_severity,
			String(definition.get("maxSeverity", "serious")),
		)
		condition["label"] = _label_for(
			definition,
			String(condition.get("severity", "minor")),
		)
		condition["state"] = "active"
		condition["lastChangedAtMinute"] = due_at
		_schedule_condition_change(resident, condition, due_at, definition)
		conditions[condition_index] = condition
		if String(condition.get("severity", "")) != previous_severity:
			events.append(_condition_event(
				resident,
				condition,
				"condition_changed",
				due_at,
				"condition_due",
			))
	else:
		if String(condition.get("severity", "")) == "minor":
			condition["state"] = "recovering"
			condition["lastChangedAtMinute"] = due_at
			events.append(_condition_event(
				resident,
				condition,
				"condition_recovering",
				due_at,
				"condition_due",
			))
		_schedule_condition_change(resident, condition, due_at, definition)
		conditions[condition_index] = condition
	resident["conditions"] = conditions
	return events


func _validate_trigger(trigger: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _exact_keys(trigger, TRIGGER_FIELDS):
		errors.append("触发字段不完整或包含未知字段")
	var trigger_id := String(trigger.get("triggerId", "")).strip_edges()
	var trigger_kind := String(trigger.get("triggerKind", ""))
	var source_kind := String(trigger.get("sourceKind", ""))
	var source_ref := String(trigger.get("sourceRef", "")).strip_edges()
	if trigger_id.is_empty() or source_ref.is_empty():
		errors.append("触发编号和来源引用不能为空")
	if not _known_trigger_kinds.has(trigger_kind):
		errors.append("触发类型未知：%s" % trigger_kind)
	if not _known_source_kinds.has(source_kind):
		errors.append("触发来源未知：%s" % source_kind)
	if trigger_kind == "wake" and source_kind != "sleep_action":
		errors.append("睡醒触发必须引用睡眠动作")
	var occurred_value: Variant = trigger.get("occurredAtMinute")
	var duration_value: Variant = trigger.get("durationMinutes")
	if typeof(occurred_value) != TYPE_INT or int(occurred_value) < 0:
		errors.append("触发时间必须是非负整数")
	if typeof(duration_value) != TYPE_INT or int(duration_value) < 0:
		errors.append("触发持续时间必须是非负整数")
	_validate_known_tags(
		trigger.get("riskTags"),
		_known_risk_tags,
		"风险",
		errors,
	)
	_validate_known_tags(
		trigger.get("reliefTags"),
		_known_relief_tags,
		"缓解",
		errors,
	)
	if not trigger.get("facts") is Dictionary:
		errors.append("触发事实必须是对象")
	else:
		var facts := trigger.get("facts", {}) as Dictionary
		_validate_optional_fact_fields(facts, "触发事实", errors)
		if trigger_kind == "wake":
			var sleep_value: Variant = facts.get("actualSleepMinutes")
			if typeof(sleep_value) != TYPE_INT or int(sleep_value) < 0:
				errors.append("睡醒触发必须包含实际睡眠分钟")
		if trigger_kind == "action_result":
			if typeof(facts.get("completed")) != TYPE_BOOL:
				errors.append("行动结果必须说明是否完成")
			if typeof(facts.get("interrupted")) != TYPE_BOOL:
				errors.append("行动结果必须说明是否中断")
	return errors


func _validate_sleep_result_input(
	sleep_result: Dictionary,
	life_state: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	var expected_fields := [
		"actionId",
		"startedAtMinute",
		"completedAtMinute",
		"plannedDurationMinutes",
		"actualSleepMinutes",
		"interrupted",
		"endReason",
		"classification",
		"wakeEligible",
	]
	if not _exact_keys(sleep_result, expected_fields):
		errors.append("睡眠结果字段不完整或包含未知字段")
	var action_id := String(sleep_result.get("actionId", "")).strip_edges()
	var started_value: Variant = sleep_result.get("startedAtMinute")
	var completed_value: Variant = sleep_result.get("completedAtMinute")
	var planned_value: Variant = sleep_result.get("plannedDurationMinutes")
	var actual_value: Variant = sleep_result.get("actualSleepMinutes")
	if action_id.is_empty():
		errors.append("睡眠动作编号不能为空")
	if (
		typeof(started_value) != TYPE_INT
		or typeof(completed_value) != TYPE_INT
		or typeof(planned_value) != TYPE_INT
		or typeof(actual_value) != TYPE_INT
	):
		errors.append("睡眠时间字段必须是整数")
	else:
		if (
			int(started_value) < 0
			or int(completed_value) < int(started_value)
			or int(planned_value) <= 0
			or int(actual_value) != int(completed_value) - int(started_value)
		):
			errors.append("睡眠实际时长与开始结束时间不一致")
	if typeof(sleep_result.get("interrupted")) != TYPE_BOOL:
		errors.append("睡眠结果必须说明是否中断")
	if String(sleep_result.get("endReason", "")).strip_edges().is_empty():
		errors.append("睡眠结束原因不能为空")
	var classification := String(sleep_result.get("classification", ""))
	if not ["brief_rest", "effective_sleep", "full_sleep"].has(
		classification,
	):
		errors.append("睡眠分类无效")
	elif typeof(actual_value) == TYPE_INT and typeof(
		sleep_result.get("interrupted"),
	) == TYPE_BOOL:
		var actual_minutes := int(actual_value)
		var expected_classification := "brief_rest"
		if actual_minutes >= 360 and not bool(
			sleep_result.get("interrupted", false),
		):
			expected_classification = "full_sleep"
		elif actual_minutes >= 90:
			expected_classification = "effective_sleep"
		if classification != expected_classification:
			errors.append("睡眠分类与实际时长或中断状态不一致")
	if typeof(sleep_result.get("wakeEligible")) != TYPE_BOOL:
		errors.append("睡眠结果必须说明是否达到睡醒判断时长")
	elif typeof(actual_value) == TYPE_INT and bool(
		sleep_result.get("wakeEligible", false),
	) != (int(actual_value) >= 90):
		errors.append("睡醒判断资格与实际睡眠时长不一致")
	for field in ["energy", "satiety", "stress"]:
		var value: Variant = life_state.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("睡醒生活状态缺少数值：%s" % field)
		elif float(value) < 0.0 or float(value) > 100.0:
			errors.append("睡醒生活状态超出范围：%s" % field)
	return errors


func _validate_world_action_result_input(
	action_result: Dictionary,
	life_state: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	var expected_fields := [
		"resultId",
		"sourceKind",
		"sourceRef",
		"startedAtMinute",
		"occurredAtMinute",
		"status",
		"riskTags",
		"reliefTags",
		"context",
	]
	if not _exact_keys(action_result, expected_fields):
		errors.append("World 行为结果字段不完整或包含未知字段")
	if String(action_result.get("resultId", "")).strip_edges().is_empty():
		errors.append("World 行为结果编号不能为空")
	if String(action_result.get("sourceRef", "")).strip_edges().is_empty():
		errors.append("World 行为来源引用不能为空")
	var source_kind := String(action_result.get("sourceKind", ""))
	if source_kind not in [
		"formal_activity",
		"generic_action",
		"route",
		"place_event",
	]:
		errors.append("World 行为来源类型无效")
	var started_value: Variant = action_result.get("startedAtMinute")
	var occurred_value: Variant = action_result.get("occurredAtMinute")
	if (
		typeof(started_value) != TYPE_INT
		or typeof(occurred_value) != TYPE_INT
	):
		errors.append("World 行为起止时间必须是整数")
	elif int(started_value) < 0 or int(occurred_value) < int(started_value):
		errors.append("World 行为起止时间无效")
	var status := String(action_result.get("status", ""))
	if status not in ["completed", "interrupted", "failed", "rejected"]:
		errors.append("World 行为结果状态无效")
	if (
		status == "rejected"
		and typeof(started_value) == TYPE_INT
		and typeof(occurred_value) == TYPE_INT
		and int(occurred_value) != int(started_value)
	):
		errors.append("被拒绝的行为不能包含已经发生的持续时间")
	if not action_result.get("context") is Dictionary:
		errors.append("World 行为上下文必须是对象")
	_validate_known_tags(
		action_result.get("riskTags"),
		_known_risk_tags,
		"World 行为风险",
		errors,
	)
	_validate_known_tags(
		action_result.get("reliefTags"),
		_known_relief_tags,
		"World 行为缓解",
		errors,
	)
	var risk_value: Variant = action_result.get("riskTags")
	var relief_value: Variant = action_result.get("reliefTags")
	if (
		status == "rejected"
		and risk_value is Array
		and relief_value is Array
		and (
			not (risk_value as Array).is_empty()
			or not (relief_value as Array).is_empty()
		)
	):
		errors.append("被拒绝的行为不能产生风险或缓解效果")
	for field in ["energy", "satiety", "stress"]:
		var value: Variant = life_state.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("行为结算生活状态缺少数值：%s" % field)
		elif float(value) < 0.0 or float(value) > 100.0:
			errors.append("行为结算生活状态超出范围：%s" % field)
	return errors


func _validate_activity_execution_result(
	execution_result: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	var expected_fields := [
		"resultId",
		"activityId",
		"actionId",
		"startedAtMinute",
		"occurredAtMinute",
		"status",
		"placeId",
		"weather",
		"outdoors",
	]
	if not _exact_keys(execution_result, expected_fields):
		errors.append("正式活动结果字段不完整或包含未知字段")
	for field in ["resultId", "activityId", "actionId", "placeId"]:
		if String(execution_result.get(field, "")).strip_edges().is_empty():
			errors.append("正式活动结果字段不能为空：%s" % field)
	var started_value: Variant = execution_result.get("startedAtMinute")
	var occurred_value: Variant = execution_result.get("occurredAtMinute")
	if (
		typeof(started_value) != TYPE_INT
		or typeof(occurred_value) != TYPE_INT
		or int(started_value) < 0
		or int(occurred_value) < int(started_value)
	):
		errors.append("正式活动结果起止时间无效")
	var status := String(execution_result.get("status", ""))
	if status not in ["completed", "interrupted", "failed", "rejected"]:
		errors.append("正式活动结果状态无效")
	if (
		status == "rejected"
		and typeof(started_value) == TYPE_INT
		and typeof(occurred_value) == TYPE_INT
		and int(started_value) != int(occurred_value)
	):
		errors.append("被拒绝的正式活动不能包含持续时间")
	if not execution_result.get("weather") is String:
		errors.append("正式活动天气必须是字符串")
	if typeof(execution_result.get("outdoors")) != TYPE_BOOL:
		errors.append("正式活动必须说明是否在室外")
	return errors


func _validate_world_weather_exposure(
	exposure_fact: Dictionary,
) -> Array[String]:
	var errors: Array[String] = []
	var expected_fields := [
		"exposureId",
		"sourceKind",
		"sourceRef",
		"startedAtMinute",
		"weather",
		"outdoors",
		"placeId",
		"riskTags",
	]
	if not _exact_keys(exposure_fact, expected_fields):
		errors.append("World 天气暴露字段不完整或包含未知字段")
	if String(exposure_fact.get("exposureId", "")).strip_edges().is_empty():
		errors.append("World 天气暴露编号不能为空")
	if String(exposure_fact.get("sourceRef", "")).strip_edges().is_empty():
		errors.append("World 天气暴露来源不能为空")
	if String(exposure_fact.get("placeId", "")).strip_edges().is_empty():
		errors.append("World 天气暴露地点不能为空")
	var source_kind := String(exposure_fact.get("sourceKind", ""))
	if source_kind not in [
		"formal_activity",
		"generic_action",
		"route",
		"weather_exposure",
	]:
		errors.append("World 天气暴露来源类型无效")
	var started_value: Variant = exposure_fact.get("startedAtMinute")
	if typeof(started_value) != TYPE_INT or int(started_value) < 0:
		errors.append("World 天气暴露开始时间无效")
	if exposure_fact.get("outdoors") != true:
		errors.append("World 天气暴露必须已经确认居民在室外")
	if String(exposure_fact.get("weather", "")) not in RAIN_OR_SNOW:
		errors.append("World 天气暴露必须引用当时的雨雪事实")
	_validate_known_tags(
		exposure_fact.get("riskTags"),
		_known_risk_tags,
		"World 天气暴露风险",
		errors,
	)
	var risk_value: Variant = exposure_fact.get("riskTags")
	if risk_value is Array and not (risk_value as Array).has(
		"weather_exposure",
	):
		errors.append("World 天气暴露缺少 weather_exposure 风险")
	return errors


func _validate_exposure(exposure: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _exact_keys(exposure, EXPOSURE_FIELDS):
		errors.append("暴露字段不完整或包含未知字段")
	if String(exposure.get("exposureId", "")).strip_edges().is_empty():
		errors.append("暴露编号不能为空")
	if String(exposure.get("sourceRef", "")).strip_edges().is_empty():
		errors.append("暴露来源引用不能为空")
	if not _known_source_kinds.has(String(exposure.get("sourceKind", ""))):
		errors.append("暴露来源未知")
	var started_value: Variant = exposure.get("startedAtMinute")
	if typeof(started_value) != TYPE_INT or int(started_value) < 0:
		errors.append("暴露开始时间无效")
	_validate_known_tags(
		exposure.get("riskTags"),
		_known_risk_tags,
		"暴露风险",
		errors,
	)
	if not exposure.get("facts") is Dictionary:
		errors.append("暴露事实必须是对象")
	else:
		_validate_optional_fact_fields(
			exposure.get("facts", {}) as Dictionary,
			"暴露事实",
			errors,
		)
	return errors


func _validate_optional_fact_fields(
	facts: Dictionary,
	path: String,
	errors: Array[String],
) -> void:
	if facts.has("targetConditionIds"):
		var targets_value: Variant = facts.get("targetConditionIds")
		if not targets_value is Array:
			errors.append("%s.targetConditionIds 必须是数组" % path)
		else:
			var seen_targets: Dictionary = {}
			for target_value: Variant in targets_value as Array:
				var target_id := String(target_value).strip_edges()
				if (
					not target_value is String
					or target_id.is_empty()
					or seen_targets.has(target_id)
				):
					errors.append(
						"%s.targetConditionIds 包含无效编号" % path,
					)
					continue
				seen_targets[target_id] = true
	if not facts.has("lifeState"):
		return
	var life_state_value: Variant = facts.get("lifeState")
	if not life_state_value is Dictionary:
		errors.append("%s.lifeState 必须是对象" % path)
		return
	var life_state := life_state_value as Dictionary
	for field: String in ["energy", "satiety", "stress"]:
		if not life_state.has(field):
			continue
		var value: Variant = life_state.get(field)
		if (
			typeof(value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(value))
			or float(value) < 0.0
			or float(value) > 100.0
		):
			errors.append("%s.lifeState.%s 数值无效" % [path, field])


func _validate_due_context(context: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key_value: Variant in context:
		if String(key_value) not in ["reliefTags", "riskTags", "lifeState"]:
			errors.append("状况到期上下文字段无效")
	if context.has("reliefTags"):
		_validate_known_tags(
			context.get("reliefTags"),
			_known_relief_tags,
			"到期缓解",
			errors,
		)
	if context.has("riskTags"):
		_validate_known_tags(
			context.get("riskTags"),
			_known_risk_tags,
			"到期风险",
			errors,
		)
	if context.has("lifeState"):
		var life_state_value: Variant = context.get("lifeState")
		if not life_state_value is Dictionary:
			errors.append("状况到期生活状态必须是对象")
		else:
			var life_state := life_state_value as Dictionary
			for field_value: Variant in life_state:
				var field := String(field_value)
				if field not in LIFE_STATE_FIELDS:
					errors.append("状况到期生活状态字段无效：%s" % field)
					continue
				var value: Variant = life_state.get(field)
				if (
					typeof(value) not in [TYPE_INT, TYPE_FLOAT]
					or float(value) < 0.0
					or float(value) > 100.0
				):
					errors.append("状况到期生活状态数值无效：%s" % field)
	return errors


func _validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if not _exact_keys(
		snapshot,
		["schemaVersion", "conditionSequence", "eventSequence", "residents"],
	):
		errors.append("临时状况存档字段不完整或包含未知字段")
	for field: String in ["schemaVersion", "conditionSequence", "eventSequence"]:
		if typeof(snapshot.get(field)) != TYPE_INT:
			errors.append("临时状况存档 %s 必须是整数" % field)
	if int(snapshot.get("schemaVersion", 0)) != 1:
		errors.append("临时状况存档版本无效")
	if int(snapshot.get("conditionSequence", -1)) < 0:
		errors.append("临时状况编号序列无效")
	if int(snapshot.get("eventSequence", -1)) < 0:
		errors.append("临时状况事件序列无效")
	var residents_value: Variant = snapshot.get("residents")
	if not residents_value is Dictionary:
		errors.append("临时状况居民存档必须是对象")
		return {"errors": errors}
	var condition_ids: Dictionary = {}
	for resident_key: Variant in residents_value as Dictionary:
		var resident_id := String(resident_key)
		var resident_value: Variant = (residents_value as Dictionary).get(resident_key)
		if not resident_value is Dictionary:
			errors.append("临时状况居民条目必须是对象：%s" % resident_id)
			continue
		var resident := resident_value as Dictionary
		if not _exact_keys(resident, RESIDENT_FIELDS):
			errors.append("临时状况居民字段无效：%s" % resident_id)
		if resident_id.is_empty() or String(resident.get("residentId", "")) != resident_id:
			errors.append("临时状况居民编号不一致：%s" % resident_id)
		if typeof(resident.get("revision")) != TYPE_INT or int(resident.get("revision", 0)) < 1:
			errors.append("临时状况居民修订无效：%s" % resident_id)
		_validate_saved_conditions(
			resident_id,
			resident,
			condition_ids,
			int(snapshot.get("conditionSequence", 0)),
			errors,
		)
		_validate_saved_roll_state(resident_id, resident, errors)
		var exposure_value: Variant = resident.get("activeExposure")
		if not exposure_value is Dictionary:
			errors.append("临时状况暴露存档必须是对象：%s" % resident_id)
		elif not (exposure_value as Dictionary).is_empty():
			for error: String in _validate_exposure(exposure_value as Dictionary):
				errors.append("%s: %s" % [resident_id, error])
			var roll_state := resident.get("conditionRollState", {}) as Dictionary
			if roll_state.get("nextAmbientCheckAtMinute") == null:
				errors.append("活动暴露缺少下次判断时间：%s" % resident_id)
		else:
			var roll_state := resident.get("conditionRollState", {}) as Dictionary
			if roll_state.get("nextAmbientCheckAtMinute") != null:
				errors.append("没有活动暴露却保存了下次判断时间：%s" % resident_id)
	return {"errors": errors}


func _validate_saved_conditions(
	resident_id: String,
	resident: Dictionary,
	condition_ids: Dictionary,
	condition_sequence: int,
	errors: Array[String],
) -> void:
	var conditions_value: Variant = resident.get("conditions")
	if not conditions_value is Array:
		errors.append("临时状况列表必须是数组：%s" % resident_id)
		return
	var kinds: Dictionary = {}
	for value: Variant in conditions_value as Array:
		if not value is Dictionary:
			errors.append("临时状况记录必须是对象：%s" % resident_id)
			continue
		var condition := value as Dictionary
		if not _exact_keys(condition, CONDITION_FIELDS):
			errors.append("临时状况记录字段无效：%s" % resident_id)
		var condition_id := String(condition.get("conditionId", ""))
		var kind := String(condition.get("kind", ""))
		if condition_id.is_empty() or condition_ids.has(condition_id):
			errors.append("临时状况编号重复或为空：%s" % condition_id)
		else:
			condition_ids[condition_id] = true
		var expected_prefix := "condition-%s-" % resident_id
		var sequence_text := condition_id.trim_prefix(expected_prefix)
		if (
			not condition_id.begins_with(expected_prefix)
			or sequence_text.length() != 6
			or not sequence_text.is_valid_int()
			or int(sequence_text) <= 0
			or int(sequence_text) > condition_sequence
		):
			errors.append("临时状况编号与存档序列不一致：%s" % condition_id)
		if not _conditions_by_kind.has(kind) or kinds.has(kind):
			errors.append("临时状况种类未知或重复：%s.%s" % [resident_id, kind])
		else:
			kinds[kind] = true
		var definition := _conditions_by_kind.get(kind, {}) as Dictionary
		var severity := String(condition.get("severity", ""))
		var severity_order := _catalog.get("severityOrder", []) as Array
		if severity not in severity_order:
			errors.append("临时状况程度无效：%s" % condition_id)
		elif String(condition.get("label", "")) != _label_for(definition, severity):
			errors.append("临时状况公开文字不匹配：%s" % condition_id)
		var allowed_states := _catalog.get("states", []) as Array
		if String(condition.get("state", "")) not in allowed_states:
			errors.append("临时状况状态无效：%s" % condition_id)
		if not _known_source_kinds.has(String(condition.get("sourceKind", ""))):
			errors.append("临时状况来源无效：%s" % condition_id)
		if String(condition.get("sourceRef", "")).strip_edges().is_empty():
			errors.append("临时状况来源引用为空：%s" % condition_id)
		for field: String in [
			"startedAtMinute",
			"lastChangedAtMinute",
			"nextChangeAtMinute",
		]:
			if typeof(condition.get(field)) != TYPE_INT or int(condition.get(field, -1)) < 0:
				errors.append("临时状况时间无效：%s.%s" % [condition_id, field])
		if int(condition.get("lastChangedAtMinute", -1)) < int(condition.get("startedAtMinute", 0)):
			errors.append("临时状况变化时间早于开始时间：%s" % condition_id)
		if int(condition.get("nextChangeAtMinute", -1)) <= int(condition.get("lastChangedAtMinute", 0)):
			errors.append("临时状况下次变化时间无效：%s" % condition_id)


func _validate_saved_roll_state(
	resident_id: String,
	resident: Dictionary,
	errors: Array[String],
) -> void:
	var roll_value: Variant = resident.get("conditionRollState")
	if not roll_value is Dictionary:
		errors.append("临时状况随机状态必须是对象：%s" % resident_id)
		return
	var roll_state := roll_value as Dictionary
	if not _exact_keys(roll_state, ROLL_STATE_FIELDS):
		errors.append("临时状况随机状态字段无效：%s" % resident_id)
	var random_value: Variant = roll_state.get("randomState")
	if (
		typeof(random_value) != TYPE_INT
		or int(random_value) <= 0
		or int(random_value) >= RANDOM_MODULUS
	):
		errors.append("临时状况随机状态无效：%s" % resident_id)
	var processed_value: Variant = roll_state.get("processedTriggerIds")
	if not processed_value is Array:
		errors.append("临时状况已处理触发必须是数组：%s" % resident_id)
	else:
		var seen: Dictionary = {}
		for value: Variant in processed_value as Array:
			var trigger_id := String(value).strip_edges()
			if not value is String or trigger_id.is_empty() or seen.has(trigger_id):
				errors.append("临时状况已处理触发无效：%s" % resident_id)
			else:
				seen[trigger_id] = true
		if (processed_value as Array).size() > int(_catalog.get("processedTriggerLimit", 0)):
			errors.append("临时状况已处理触发超过上限：%s" % resident_id)
	var cooldowns_value: Variant = roll_state.get("kindCooldowns")
	if not cooldowns_value is Dictionary:
		errors.append("临时状况冷却必须是对象：%s" % resident_id)
	else:
		for key_value: Variant in cooldowns_value as Dictionary:
			var key := String(key_value)
			var parts := key.split("|")
			var minute_value: Variant = (cooldowns_value as Dictionary).get(key_value)
			if (
				parts.size() != 2
				or not _conditions_by_kind.has(parts[0])
				or not _known_source_kinds.has(parts[1])
				or typeof(minute_value) != TYPE_INT
				or int(minute_value) < 0
			):
				errors.append("临时状况冷却条目无效：%s.%s" % [resident_id, key])
	var ambient_value: Variant = roll_state.get("nextAmbientCheckAtMinute")
	if ambient_value != null and (
		typeof(ambient_value) != TYPE_INT or int(ambient_value) < 0
	):
		errors.append("临时状况下次暴露判断时间无效：%s" % resident_id)
	if not roll_state.get("lastCompletedSleepActionId") is String:
		errors.append("临时状况最近睡眠动作编号无效：%s" % resident_id)


func _trigger_had_real_effect(trigger: Dictionary) -> bool:
	var trigger_kind := String(trigger.get("triggerKind", ""))
	if trigger_kind != "action_result":
		return true
	var facts := trigger.get("facts", {}) as Dictionary
	return (
		bool(facts.get("completed", false))
		or int(trigger.get("durationMinutes", 0)) > 0
	)


func _effective_relief_tags(trigger: Dictionary) -> Array:
	var result: Array = []
	var requested := trigger.get("reliefTags", []) as Array
	if requested.is_empty():
		return result
	var trigger_kind := String(trigger.get("triggerKind", ""))
	var duration := int(trigger.get("durationMinutes", 0))
	var facts := trigger.get("facts", {}) as Dictionary
	if trigger_kind == "wake":
		if int(facts.get("actualSleepMinutes", 0)) >= 90 and requested.has("sleep"):
			result.append("sleep")
		return result
	if trigger_kind != "action_result":
		return result
	var completed := bool(facts.get("completed", false))
	var interrupted := bool(facts.get("interrupted", false))
	if not completed and not interrupted:
		return result
	for value: Variant in requested:
		var tag := String(value)
		match tag:
			"sleep":
				if duration >= 90:
					result.append(tag)
			"quiet_rest":
				if duration >= 15:
					result.append(tag)
			"indoor_dry":
				if duration >= 5:
					result.append(tag)
			"meal":
				if completed and duration >= 10:
					result.append(tag)
			"care_consult", "care_examine", "basic_care":
				if completed and duration > 0:
					result.append(tag)
	return result


func _eligibility_matches(
	definition: Dictionary,
	trigger: Dictionary,
) -> bool:
	var eligibility := definition.get("eligibilityAny", []) as Array
	if eligibility.is_empty():
		return true
	var facts := trigger.get("facts", {}) as Dictionary
	var life_state := facts.get("lifeState", {}) as Dictionary
	for value: Variant in eligibility:
		var rule := value as Dictionary
		var field := String(rule.get("field", ""))
		var actual_value: Variant
		if field == "durationMinutes":
			actual_value = trigger.get("durationMinutes")
		elif field == "actualSleepMinutes":
			actual_value = facts.get(field)
		else:
			actual_value = life_state.get(field)
		if typeof(actual_value) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var actual := float(actual_value)
		var expected := float(rule.get("value", 0.0))
		if String(rule.get("operator", "")) == "lte" and actual <= expected:
			return true
		if String(rule.get("operator", "")) == "gte" and actual >= expected:
			return true
	return false


func _required_conditions_present(
	resident: Dictionary,
	definition: Dictionary,
) -> bool:
	for kind_value: Variant in definition.get("requiresConditionKinds", []) as Array:
		if _condition_index_by_kind(resident, String(kind_value)) < 0:
			return false
	return true


func _weather_risk_is_grounded(
	definition: Dictionary,
	trigger: Dictionary,
) -> bool:
	var condition_risks := definition.get("riskTags", []) as Array
	var trigger_risks := trigger.get("riskTags", []) as Array
	var shared_risks: Array[String] = []
	for value: Variant in condition_risks:
		if trigger_risks.has(value):
			shared_risks.append(String(value))
	if not shared_risks.has("weather_exposure"):
		return true
	if shared_risks.size() > 1:
		return true
	var facts := trigger.get("facts", {}) as Dictionary
	return (
		bool(facts.get("outdoors", false))
		and RAIN_OR_SNOW.has(String(facts.get("weather", "")))
	)


func _adjusted_chance(
	base_chance: float,
	kind: String,
	trigger: Dictionary,
) -> float:
	var chance := base_chance
	var duration := int(trigger.get("durationMinutes", 0))
	if duration >= 60:
		chance *= 1.0 + minf(0.75, float(duration - 60) / 240.0)
	var facts := trigger.get("facts", {}) as Dictionary
	var life_state := facts.get("lifeState", {}) as Dictionary
	var energy := float(life_state.get("energy", 50.0))
	var satiety := float(life_state.get("satiety", 50.0))
	var stress := float(life_state.get("stress", 50.0))
	if energy <= 25.0 and kind in ["overfatigue", "strain", "malaise", "headache"]:
		chance *= 1.5
	if satiety <= 25.0 and kind in ["malaise", "headache", "overfatigue"]:
		chance *= 1.3
	if stress >= 70.0 and kind in ["headache", "malaise", "strain"]:
		chance *= 1.5
	var weather := String(facts.get("weather", ""))
	if kind in ["wet", "chilled"]:
		if weather in ["中雨", "大雨", "雷暴"]:
			chance *= 1.5
		elif weather == "下雪":
			chance *= 1.25
	return clampf(chance, 0.0, 0.45)


func _schedule_next_ambient_check(
	resident: Dictionary,
	from_minute: int,
) -> void:
	var check_range := _catalog.get("ambientCheckMinutes", {}) as Dictionary
	var delay := _random_range(
		resident,
		int(check_range.get("min", 25)),
		int(check_range.get("max", 70)),
	)
	var roll_state := resident.get("conditionRollState", {}) as Dictionary
	roll_state["nextAmbientCheckAtMinute"] = from_minute + delay
	resident["conditionRollState"] = roll_state


func _schedule_condition_change(
	resident: Dictionary,
	condition: Dictionary,
	from_minute: int,
	definition: Dictionary,
) -> void:
	var change_range := definition.get("nextChangeMinutes", {}) as Dictionary
	condition["nextChangeAtMinute"] = from_minute + _random_range(
		resident,
		int(change_range.get("min", 30)),
		int(change_range.get("max", 60)),
	)


func _take_random(resident: Dictionary) -> float:
	var roll_state := resident.get("conditionRollState", {}) as Dictionary
	var state := int(roll_state.get("randomState", 1))
	state = int((state * RANDOM_MULTIPLIER) % RANDOM_MODULUS)
	if state <= 0:
		state = 1
	roll_state["randomState"] = state
	resident["conditionRollState"] = roll_state
	return float(state - 1) / float(RANDOM_MODULUS - 1)


func _random_range(
	resident: Dictionary,
	minimum: int,
	maximum: int,
) -> int:
	if maximum <= minimum:
		return minimum
	var roll := _take_random(resident)
	return minimum + mini(
		maximum - minimum,
		int(floor(roll * float(maximum - minimum + 1))),
	)


func _mark_trigger_processed(
	resident: Dictionary,
	trigger_id: String,
) -> void:
	var roll_state := resident.get("conditionRollState", {}) as Dictionary
	var processed := (
		roll_state.get("processedTriggerIds", []) as Array
	).duplicate()
	processed.append(trigger_id)
	var limit := int(_catalog.get("processedTriggerLimit", 128))
	while processed.size() > limit:
		processed.pop_front()
	roll_state["processedTriggerIds"] = processed
	resident["conditionRollState"] = roll_state


func _condition_event(
	resident: Dictionary,
	condition: Dictionary,
	event_type: String,
	at_minute: int,
	source_ref: String,
) -> Dictionary:
	if event_type not in EVENT_TYPES:
		return {}
	_event_sequence += 1
	return {
		"eventId": "condition-event-%06d" % _event_sequence,
		"eventType": event_type,
		"residentId": String(resident.get("residentId", "")),
		"conditionId": String(condition.get("conditionId", "")),
		"conditionKind": String(condition.get("kind", "")),
		"label": String(condition.get("label", "")),
		"severity": String(condition.get("severity", "")),
		"state": String(condition.get("state", "")),
		"atMinute": at_minute,
		"sourceRef": source_ref,
	}


func _next_due_condition_index(
	resident: Dictionary,
	now: int,
) -> int:
	var conditions := resident.get("conditions", []) as Array
	var found_index := -1
	var found_time := 0
	for index in range(conditions.size()):
		var condition := conditions[index] as Dictionary
		var due_at := int(condition.get("nextChangeAtMinute", 0))
		if due_at > now:
			continue
		if found_index < 0 or due_at < found_time:
			found_index = index
			found_time = due_at
	return found_index


func _condition_at_maximum(
	resident: Dictionary,
	index: int,
	definition: Dictionary,
) -> bool:
	var conditions := resident.get("conditions", []) as Array
	var condition := conditions[index] as Dictionary
	return (
		String(condition.get("severity", ""))
		== String(definition.get("maxSeverity", "serious"))
		and String(condition.get("state", "")) == "active"
	)


func _condition_index_by_kind(
	resident: Dictionary,
	kind: String,
) -> int:
	var conditions := resident.get("conditions", []) as Array
	for index in range(conditions.size()):
		if String((conditions[index] as Dictionary).get("kind", "")) == kind:
			return index
	return -1


func _next_severity(current: String, maximum: String) -> String:
	var order := _catalog.get("severityOrder", []) as Array
	var current_index := order.find(current)
	var maximum_index := order.find(maximum)
	if current_index < 0 or maximum_index < 0:
		return current
	return String(order[mini(current_index + 1, maximum_index)])


func _label_for(definition: Dictionary, severity: String) -> String:
	return String(
		(definition.get("labels", {}) as Dictionary).get(severity, ""),
	)


func _urgency_for_severity(severity: String) -> String:
	match severity:
		"serious":
			return "high"
		"noticeable":
			return "medium"
		_:
			return "low"


func _candidate_kinds(candidates: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for candidate: Dictionary in candidates:
		result.append(String(candidate.get("kind", "")))
	return result


func _cooldown_key(kind: String, source_kind: String) -> String:
	return "%s|%s" % [kind, source_kind]


func _arrays_intersect(first: Array, second: Array) -> bool:
	for value: Variant in first:
		if second.has(value):
			return true
	return false


func _validate_known_tags(
	value: Variant,
	known: Dictionary,
	label: String,
	errors: Array[String],
) -> void:
	if not value is Array:
		errors.append("%s标签必须是数组" % label)
		return
	var seen: Dictionary = {}
	for tag_value: Variant in value as Array:
		var tag := String(tag_value)
		if not tag_value is String or tag.is_empty() or seen.has(tag) or not known.has(tag):
			errors.append("%s标签无效：%s" % [label, tag])
		else:
			seen[tag] = true


func _index_strings(values: Array, target: Dictionary) -> void:
	for value: Variant in values:
		target[String(value)] = true


func _exact_keys(value: Dictionary, fields: Array) -> bool:
	return WORLD_SCALARS.exact_keys(value, fields)


func _success(
	resident_id: String,
	value: Dictionary = {},
) -> Dictionary:
	var result := {
		"ok": true,
		"errorCode": "",
		"residentId": resident_id,
		"conditions": get_conditions(resident_id),
		"activeNeeds": get_active_needs(resident_id),
		"rollState": get_roll_state(resident_id),
	}
	for key_value: Variant in value:
		result[key_value] = value.get(key_value)
	return result


func _failure(
	error_code: String,
	details: Dictionary = {},
) -> Dictionary:
	var result := {
		"ok": false,
		"errorCode": error_code,
	}
	for key_value: Variant in details:
		result[key_value] = details.get(key_value)
	return result
