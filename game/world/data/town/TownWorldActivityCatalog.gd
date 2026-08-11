class_name TownWorldActivityCatalog
extends RefCounted

const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const SOURCE_DIR := "res://world/data/town/source"
const VALIDATOR := preload(
	"res://world/data/town/TownWorldActivityValidator.gd"
)
const OCCUPATION_PATH := SOURCE_DIR + "/occupation_catalog.json"
const ACTIVITY_PATH := SOURCE_DIR + "/activity_definitions.json"
const SLOT_PATH := SOURCE_DIR + "/activity_slots.json"
const PLACES_PATH := SOURCE_DIR + "/places.json"
const PROPS_PATH := SOURCE_DIR + "/props.json"
const INDOOR_AUTHORING_PATH := SOURCE_DIR + "/indoor_prop_authoring.json"
const SCHEDULE_PATH := SOURCE_DIR + "/schedule_templates.json"

const STRUCTURAL_STATUS := "structural_only_unvalidated"
const FORMAL_STATUS := "formal_executable"
const PUBLIC_OPTION_FIELDS := [
	"activityId",
	"label",
	"placeId",
	"role",
	"available",
	"disabledReason",
	"preferredSlots",
]


static func load_default() -> Dictionary:
	return load_from_paths(
		OCCUPATION_PATH,
		ACTIVITY_PATH,
		SLOT_PATH,
		PLACES_PATH,
		PROPS_PATH,
		INDOOR_AUTHORING_PATH,
		SCHEDULE_PATH,
	)


static func load_from_paths(
	occupation_path: String,
	activity_path: String,
	slot_path: String,
	places_path: String,
	props_path: String,
	indoor_authoring_path: String,
	schedule_path: String,
) -> Dictionary:
	var errors := PackedStringArray()
	var occupation_document := _load_json_document(
		occupation_path,
		"occupation_catalog",
		errors,
	)
	var activity_document := _load_json_document(
		activity_path,
		"activity_definitions",
		errors,
	)
	var slot_document := _load_json_document(
		slot_path,
		"activity_slots",
		errors,
	)
	var places_document := _load_json_document(
		places_path,
		"places",
		errors,
	)
	var props_document := _load_json_document(
		props_path,
		"props",
		errors,
	)
	var indoor_authoring_document := _load_json_document(
		indoor_authoring_path,
		"indoor_prop_authoring",
		errors,
	)
	var schedule_document := _load_json_document(
		schedule_path,
		"schedule_templates",
		errors,
	)
	if not errors.is_empty():
		return _failure(errors)
	return from_documents(
		occupation_document,
		activity_document,
		slot_document,
		places_document,
		props_document,
		indoor_authoring_document,
		schedule_document,
	)


static func from_documents(
	occupation_document: Dictionary,
	activity_document: Dictionary,
	slot_document: Dictionary,
	places_document: Dictionary,
	props_document: Dictionary,
	indoor_authoring_document: Dictionary,
	schedule_document: Dictionary,
) -> Dictionary:
	var structural_errors := _validate_structural_documents(
		occupation_document,
		activity_document,
		slot_document,
		schedule_document,
	)
	if not structural_errors.is_empty():
		return _failure(structural_errors)
	var fingerprint := source_fingerprint(
		occupation_document,
		activity_document,
		slot_document,
		places_document,
		props_document,
		indoor_authoring_document,
		schedule_document,
	)
	if fingerprint.is_empty():
		return _failure(PackedStringArray([
			"Activity Catalog 无法生成 sourceFingerprint",
		]))

	var occupation_by_id: Dictionary = {}
	var activity_by_id: Dictionary = {}
	var slot_by_id: Dictionary = {}
	var schedule_by_id: Dictionary = {}
	var slots_by_activity: Dictionary = {}
	var slots_by_place: Dictionary = {}
	var legacy_activity_ids_by_key: Dictionary = {}

	for value: Variant in occupation_document.get("occupations", []) as Array:
		var occupation := (value as Dictionary).duplicate(true)
		var occupation_id := String(occupation.get("occupationId", ""))
		occupation_by_id[occupation_id] = occupation

	for value: Variant in activity_document.get("activities", []) as Array:
		var activity := (value as Dictionary).duplicate(true)
		var activity_id := String(activity.get("activityId", ""))
		activity_by_id[activity_id] = activity

	for value: Variant in slot_document.get("slots", []) as Array:
		var slot := (value as Dictionary).duplicate(true)
		var slot_id := String(slot.get("slotId", ""))
		var activity_id := String(slot.get("activityId", ""))
		var place_name := String(slot.get("placeName", ""))
		slot_by_id[slot_id] = slot
		var activity_slots := slots_by_activity.get(activity_id, []) as Array
		activity_slots.append(slot)
		slots_by_activity[activity_id] = activity_slots
		var place_slots := slots_by_place.get(place_name, []) as Array
		place_slots.append(slot)
		slots_by_place[place_name] = place_slots
		if String(slot.get("targetType", "")) == "prop":
			var target := slot.get("target", {}) as Dictionary
			var legacy_key := _legacy_key(
				place_name,
				String(target.get("propName", "")),
				String(target.get("actionVerb", "")),
			)
			if not legacy_key.is_empty():
				var mapped_ids := (
					legacy_activity_ids_by_key.get(legacy_key, []) as Array
				)
				if activity_id not in mapped_ids:
					mapped_ids.append(activity_id)
				legacy_activity_ids_by_key[legacy_key] = mapped_ids

	for value: Variant in schedule_document.get(
		"scheduleTemplates",
		[],
	) as Array:
		var schedule := (value as Dictionary).duplicate(true)
		schedule_by_id[String(
			schedule.get("scheduleTemplateId", "")
		)] = schedule

	_sort_slot_index(slots_by_activity)
	_sort_slot_index(slots_by_place)
	for key_value: Variant in legacy_activity_ids_by_key.keys():
		var key := String(key_value)
		var mapped_ids := legacy_activity_ids_by_key[key] as Array
		mapped_ids.sort()
		legacy_activity_ids_by_key[key] = mapped_ids

	return {
		"ok": true,
		"errorCode": "",
		"errors": PackedStringArray(),
		"worldId": "town",
		"structurallyValid": true,
		"validated": false,
		"formalExecutable": false,
		"validationStatus": STRUCTURAL_STATUS,
		"validationEvidence": {},
		"sourceFingerprint": fingerprint,
		"sourceDocumentFingerprints": (
			VALIDATOR.source_document_fingerprints(
				occupation_document,
				activity_document,
				slot_document,
				places_document,
				props_document,
				indoor_authoring_document,
				schedule_document,
			)
		),
		"occupationDocument": occupation_document.duplicate(true),
		"activityDocument": activity_document.duplicate(true),
		"slotDocument": slot_document.duplicate(true),
		"placesDocument": places_document.duplicate(true),
		"propsDocument": props_document.duplicate(true),
		"indoorAuthoringDocument": indoor_authoring_document.duplicate(true),
		"scheduleDocument": schedule_document.duplicate(true),
		"occupationById": occupation_by_id,
		"activityById": activity_by_id,
		"slotById": slot_by_id,
		"scheduleById": schedule_by_id,
		"slotsByActivity": slots_by_activity,
		"slotsByPlace": slots_by_place,
		"legacyActivityIdsByKey": legacy_activity_ids_by_key,
	}


static func source_fingerprint(
	occupation_document: Dictionary,
	activity_document: Dictionary,
	slot_document: Dictionary,
	places_document: Dictionary,
	props_document: Dictionary,
	indoor_authoring_document: Dictionary,
	schedule_document: Dictionary,
) -> String:
	return VALIDATOR.source_fingerprint(
		occupation_document,
		activity_document,
		slot_document,
		places_document,
		props_document,
		indoor_authoring_document,
		schedule_document,
	)


static func authorize_formal_consumption(
	catalog: Dictionary,
	validation_evidence: Dictionary,
) -> Dictionary:
	if not bool(catalog.get("ok", false)):
		return _failure(PackedStringArray([
			"不能授权加载失败的 Activity Catalog",
		]))
	if not bool(catalog.get("structurallyValid", false)):
		return _failure(PackedStringArray([
			"Activity Catalog 尚未通过基础 schema 门禁",
		]))
	var evidence_errors := _formal_evidence_errors(
		catalog,
		validation_evidence,
	)
	if not evidence_errors.is_empty():
		return _failure(evidence_errors)
	var authorized := catalog.duplicate(true)
	authorized["validated"] = true
	authorized["formalExecutable"] = true
	authorized["validationStatus"] = FORMAL_STATUS
	authorized["validationEvidence"] = validation_evidence.duplicate(true)
	return authorized


static func formal_consumption_ready(catalog: Dictionary) -> bool:
	var evidence_value: Variant = catalog.get("validationEvidence")
	if not evidence_value is Dictionary:
		return false
	return (
		bool(catalog.get("ok", false))
		and bool(catalog.get("structurallyValid", false))
		and bool(catalog.get("validated", false))
		and bool(catalog.get("formalExecutable", false))
		and String(catalog.get("validationStatus", "")) == FORMAL_STATUS
		and _formal_evidence_errors(
			catalog,
			evidence_value as Dictionary,
		).is_empty()
	)


static func validation_status(catalog: Dictionary) -> Dictionary:
	return {
		"structurallyValid": bool(
			catalog.get("structurallyValid", false)
		),
		"validated": bool(catalog.get("validated", false)),
		"formalExecutable": bool(
			catalog.get("formalExecutable", false)
		),
		"status": String(catalog.get("validationStatus", "")),
		"referenceStatus": static_reference_status(catalog),
	}


static func static_reference_status(catalog: Dictionary) -> Dictionary:
	var document := catalog.get("occupationDocument", {}) as Dictionary
	return (
		document.get("referenceStatus", {}) as Dictionary
	).duplicate(true)


static func occupation(
	catalog: Dictionary,
	occupation_id: String,
) -> Dictionary:
	if not formal_consumption_ready(catalog):
		return {}
	return occupation_template(catalog, occupation_id)


static func occupation_template(
	catalog: Dictionary,
	occupation_id: String,
) -> Dictionary:
	var index := catalog.get("occupationById", {}) as Dictionary
	return (index.get(occupation_id, {}) as Dictionary).duplicate(true)


static func activity(catalog: Dictionary, activity_id: String) -> Dictionary:
	if not formal_consumption_ready(catalog):
		return {}
	return activity_template(catalog, activity_id)


static func activity_template(
	catalog: Dictionary,
	activity_id: String,
) -> Dictionary:
	var index := catalog.get("activityById", {}) as Dictionary
	return (index.get(activity_id, {}) as Dictionary).duplicate(true)


static func slot(catalog: Dictionary, slot_id: String) -> Dictionary:
	if not formal_consumption_ready(catalog):
		return {}
	return slot_template(catalog, slot_id)


static func slot_template(
	catalog: Dictionary,
	slot_id: String,
) -> Dictionary:
	var index := catalog.get("slotById", {}) as Dictionary
	return (index.get(slot_id, {}) as Dictionary).duplicate(true)


static func occupations(catalog: Dictionary) -> Array:
	if not formal_consumption_ready(catalog):
		return []
	return occupation_templates(catalog)


static func occupation_templates(catalog: Dictionary) -> Array:
	return _sorted_index_values(
		catalog.get("occupationById", {}) as Dictionary,
		"occupationId",
	)


static func activities(catalog: Dictionary) -> Array:
	if not formal_consumption_ready(catalog):
		return []
	return activity_templates(catalog)


static func activity_templates(catalog: Dictionary) -> Array:
	return _sorted_index_values(
		catalog.get("activityById", {}) as Dictionary,
		"activityId",
	)


static func slots(catalog: Dictionary) -> Array:
	if not formal_consumption_ready(catalog):
		return []
	return slot_templates(catalog)


static func slot_templates(catalog: Dictionary) -> Array:
	return _sorted_index_values(
		catalog.get("slotById", {}) as Dictionary,
		"slotId",
	)


static func schedule_templates(catalog: Dictionary) -> Array:
	return _sorted_index_values(
		catalog.get("scheduleById", {}) as Dictionary,
		"scheduleTemplateId",
	)


static func schedules(catalog: Dictionary) -> Array:
	if not formal_consumption_ready(catalog):
		return []
	return schedule_templates(catalog)


static func slots_for_activity(
	catalog: Dictionary,
	activity_id: String,
) -> Array:
	if not formal_consumption_ready(catalog):
		return []
	return slot_templates_for_activity(catalog, activity_id)


static func slot_templates_for_activity(
	catalog: Dictionary,
	activity_id: String,
) -> Array:
	var index := catalog.get("slotsByActivity", {}) as Dictionary
	return _duplicate_dictionary_array(index.get(activity_id, []) as Array)


static func slots_for_place(
	catalog: Dictionary,
	place_name: String,
) -> Array:
	if not formal_consumption_ready(catalog):
		return []
	return slot_templates_for_place(catalog, place_name)


static func slot_templates_for_place(
	catalog: Dictionary,
	place_name: String,
) -> Array:
	var index := catalog.get("slotsByPlace", {}) as Dictionary
	return _duplicate_dictionary_array(index.get(place_name, []) as Array)


static func agent_contract(catalog: Dictionary) -> Dictionary:
	var document := catalog.get("activityDocument", {}) as Dictionary
	return (
		document.get("agentContract", {}) as Dictionary
	).duplicate(true)


static func activity_option_templates(
	catalog: Dictionary,
	place_name: String,
	role: String = "",
) -> Array:
	var grouped: Dictionary = {}
	for slot_value: Variant in slot_templates_for_place(catalog, place_name):
		var slot_record := slot_value as Dictionary
		var slot_role := String(slot_record.get("role", ""))
		if not role.is_empty() and slot_role != role:
			continue
		var activity_id := String(slot_record.get("activityId", ""))
		var definition := activity_template(catalog, activity_id)
		if definition.is_empty():
			continue
		var group_key := "%s|%s" % [activity_id, slot_role]
		if not grouped.has(group_key):
			grouped[group_key] = {
				"activityId": activity_id,
				"label": String(definition.get("label", "")),
				"placeId": place_name,
				"role": slot_role,
				"preferredSlots": [],
			}
		var option := grouped[group_key] as Dictionary
		var target := slot_record.get("target", {}) as Dictionary
		var preferred_slots := option.get("preferredSlots", []) as Array
		preferred_slots.append({
			"slotId": String(slot_record.get("slotId", "")),
			"label": _slot_public_label(slot_record, target),
		})
		option["preferredSlots"] = preferred_slots
		grouped[group_key] = option
	return _sort_option_templates(
		_duplicate_dictionary_array(grouped.values())
	)


static func runtime_availability_key(
	place_name: String,
	activity_id: String,
	role: String,
) -> String:
	if place_name.is_empty() or activity_id.is_empty() or role.is_empty():
		return ""
	return "%s\u001f%s\u001f%s" % [
		place_name,
		activity_id,
		role,
	]


static func public_activity_options(
	catalog: Dictionary,
	place_name: String,
	runtime_availability: Dictionary = {},
	role: String = "",
) -> Array:
	if not formal_consumption_ready(catalog):
		return []
	if runtime_availability.is_empty():
		return []
	var result := []
	for template_value: Variant in activity_option_templates(
		catalog,
		place_name,
		role,
	):
		var template := template_value as Dictionary
		var key := runtime_availability_key(
			place_name,
			String(template.get("activityId", "")),
			String(template.get("role", "")),
		)
		var availability_value: Variant = runtime_availability.get(key)
		if not availability_value is Dictionary:
			continue
		var availability := availability_value as Dictionary
		if not availability.get("available") is bool:
			continue
		if not availability.get("disabledReason") is String:
			continue
		var available := bool(availability.get("available", false))
		var disabled_reason := String(
			availability.get("disabledReason", "")
		)
		if available and not disabled_reason.is_empty():
			continue
		if not available and disabled_reason.strip_edges().is_empty():
			continue
		var option := template.duplicate(true)
		option["available"] = available
		option["disabledReason"] = disabled_reason
		if _has_exact_string_keys(option, PUBLIC_OPTION_FIELDS):
			result.append(option)
	return result


static func default_social_state_coverage(
	catalog: Dictionary,
) -> Dictionary:
	var document := catalog.get("occupationDocument", {}) as Dictionary
	return (
		document.get("defaultSocialStateCoverage", {}) as Dictionary
	).duplicate(true)


static func audit_default_social_state(
	catalog: Dictionary,
	resident_catalog_document: Dictionary,
) -> Dictionary:
	var coverage := default_social_state_coverage(catalog)
	var supported_by_key: Dictionary = {}
	var gaps_by_key: Dictionary = {}
	for value: Variant in coverage.get(
		"activityChainSupported",
		[],
	) as Array:
		if value is Dictionary:
			var record := value as Dictionary
			supported_by_key[_social_state_key(record)] = record
	for value: Variant in coverage.get("gaps", []) as Array:
		if value is Dictionary:
			var record := value as Dictionary
			gaps_by_key[_social_state_key(record)] = record

	var residents_value: Variant = resident_catalog_document.get("residents")
	if not residents_value is Array:
		return {
			"ok": false,
			"errorCode": "DEFAULT_SOCIAL_STATE_SOURCE_INVALID",
			"expectedCount": int(
				coverage.get("expectedDefaultCombinationCount", 0)
			),
			"actualCount": 0,
			"supported": [],
			"gaps": [],
			"unregistered": [],
			"declaredButAbsent": [],
		}
	var supported := []
	var gaps := []
	var unregistered := []
	var observed_keys: Dictionary = {}
	for resident_value: Variant in residents_value as Array:
		if not resident_value is Dictionary:
			continue
		var resident := resident_value as Dictionary
		var social := resident.get("occupation", {}) as Dictionary
		var record := {
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(resident.get("attributes", {}) as Dictionary).get(
					"name",
					"",
				)
			),
			"occupationName": String(social.get("name", "")),
			"workplacePlace": String(
				social.get("workplacePlace", "")
			),
		}
		var key := _social_state_key(record)
		observed_keys[key] = true
		if supported_by_key.has(key):
			var supported_record := (
				supported_by_key[key] as Dictionary
			).duplicate(true)
			supported_record.merge(record, true)
			supported.append(supported_record)
		elif gaps_by_key.has(key):
			var gap_record := (
				gaps_by_key[key] as Dictionary
			).duplicate(true)
			gap_record.merge(record, true)
			gaps.append(gap_record)
		else:
			unregistered.append(record)
	var declared_but_absent := []
	for declared_key_value: Variant in (
		supported_by_key.keys() + gaps_by_key.keys()
	):
		var declared_key := String(declared_key_value)
		if not observed_keys.has(declared_key):
			declared_but_absent.append(declared_key)
	var expected_count := int(
		coverage.get("expectedDefaultCombinationCount", 0)
	)
	var audit_ok := (
		(residents_value as Array).size() == expected_count
		and supported.size() == (
			coverage.get("activityChainSupported", []) as Array
		).size()
		and gaps.size() == (
			coverage.get("gaps", []) as Array
		).size()
		and unregistered.is_empty()
		and declared_but_absent.is_empty()
	)
	return {
		"ok": audit_ok,
		"errorCode": (
			"" if audit_ok
			else "DEFAULT_SOCIAL_STATE_COVERAGE_MISMATCH"
		),
		"expectedCount": expected_count,
		"actualCount": (residents_value as Array).size(),
		"supported": supported,
		"gaps": gaps,
		"unregistered": unregistered,
		"declaredButAbsent": declared_but_absent,
	}


static func resolve_unique_legacy_activity_template(
	catalog: Dictionary,
	place_name: String,
	prop_name: String,
	action_verb: String,
) -> Dictionary:
	var key := _legacy_key(place_name, prop_name, action_verb)
	if key.is_empty():
		return {}
	var index := catalog.get("legacyActivityIdsByKey", {}) as Dictionary
	var activity_ids := index.get(key, []) as Array
	if activity_ids.size() != 1:
		return {}
	var activity_id := String(activity_ids[0])
	var matching_slots := []
	for slot_value: Variant in slot_templates_for_activity(
		catalog,
		activity_id,
	):
		var slot_record := slot_value as Dictionary
		var target := slot_record.get("target", {}) as Dictionary
		if (
			String(slot_record.get("placeName", "")) == place_name
			and String(target.get("propName", "")) == prop_name
			and String(target.get("actionVerb", "")) == action_verb
		):
			matching_slots.append(slot_record.duplicate(true))
	if matching_slots.is_empty():
		return {}
	return {
		"activity": activity_template(catalog, activity_id),
		"slots": matching_slots,
	}


static func resolve_unique_legacy_activity(
	catalog: Dictionary,
	place_name: String,
	prop_name: String,
	action_verb: String,
) -> Dictionary:
	if not formal_consumption_ready(catalog):
		return {}
	return resolve_unique_legacy_activity_template(
		catalog,
		place_name,
		prop_name,
		action_verb,
	)


static func _validate_structural_documents(
	occupation_document: Dictionary,
	activity_document: Dictionary,
	slot_document: Dictionary,
	schedule_document: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	_validate_structural_document(
		occupation_document,
		"occupation_catalog",
		"occupations",
		"occupationId",
		errors,
	)
	_validate_structural_document(
		activity_document,
		"activity_definitions",
		"activities",
		"activityId",
		errors,
	)
	_validate_structural_document(
		slot_document,
		"activity_slots",
		"slots",
		"slotId",
		errors,
	)
	_validate_structural_document(
		schedule_document,
		"schedule_templates",
		"scheduleTemplates",
		"scheduleTemplateId",
		errors,
	)
	_validate_member_ids(slot_document, errors)
	_validate_coverage_structure(occupation_document, errors)
	return errors


static func _validate_structural_document(
	document: Dictionary,
	label: String,
	array_key: String,
	id_key: String,
	errors: PackedStringArray,
) -> void:
	var schema_value: Variant = document.get("schemaVersion")
	if not _is_integer_number(schema_value) or int(schema_value) != 1:
		errors.append("%s.schemaVersion 必须是整数 1" % label)
	var world_id_value: Variant = document.get("worldId")
	if (
		not world_id_value is String
		or String(world_id_value) != "town"
	):
		errors.append("%s.worldId 必须为 town" % label)
	var values_value: Variant = document.get(array_key)
	if not values_value is Array:
		errors.append("%s.%s 必须为数组" % [label, array_key])
		return
	var ids: Dictionary = {}
	for index in (values_value as Array).size():
		var value: Variant = (values_value as Array)[index]
		if not value is Dictionary:
			errors.append("%s.%s[%d] 必须为对象" % [
				label,
				array_key,
				index,
			])
			continue
		var stable_id_value: Variant = (value as Dictionary).get(id_key)
		if (
			not stable_id_value is String
			or String(stable_id_value).strip_edges().is_empty()
		):
			errors.append("%s.%s[%d].%s 必须为非空字符串" % [
				label,
				array_key,
				index,
				id_key,
			])
			continue
		var stable_id := String(stable_id_value)
		if ids.has(stable_id):
			errors.append("%s 重复：%s" % [id_key, stable_id])
		else:
			ids[stable_id] = true


static func _validate_member_ids(
	slot_document: Dictionary,
	errors: PackedStringArray,
) -> void:
	var ids: Dictionary = {}
	for slot_value: Variant in slot_document.get("slots", []) as Array:
		if not slot_value is Dictionary:
			continue
		var slot_record := slot_value as Dictionary
		for member_value: Variant in slot_record.get(
			"memberAnchors",
			[],
		) as Array:
			if not member_value is Dictionary:
				continue
			var member_id_value: Variant = (
				member_value as Dictionary
			).get("memberAnchorId")
			if (
				not member_id_value is String
				or String(member_id_value).strip_edges().is_empty()
			):
				errors.append("memberAnchorId 必须为非空字符串")
				continue
			var member_id := String(member_id_value)
			if ids.has(member_id):
				errors.append("memberAnchorId 重复：%s" % member_id)
			else:
				ids[member_id] = true


static func _validate_coverage_structure(
	occupation_document: Dictionary,
	errors: PackedStringArray,
) -> void:
	var coverage_value: Variant = occupation_document.get(
		"defaultSocialStateCoverage"
	)
	if not coverage_value is Dictionary:
		errors.append("defaultSocialStateCoverage 必须为对象")
		return
	var coverage := coverage_value as Dictionary
	var supported_value: Variant = coverage.get("activityChainSupported")
	var gaps_value: Variant = coverage.get("gaps")
	if not supported_value is Array or not gaps_value is Array:
		errors.append(
			"defaultSocialStateCoverage supported/gaps 必须为数组"
		)
		return
	var expected_value: Variant = coverage.get(
		"expectedDefaultCombinationCount"
	)
	if (
		not _is_integer_number(expected_value)
		or int(expected_value) <= 0
		or (
			(supported_value as Array).size()
			+ (gaps_value as Array).size()
		) != int(expected_value)
	):
		errors.append("defaultSocialStateCoverage 数量合同不一致")
	var ids: Dictionary = {}
	for value: Variant in (
		(supported_value as Array) + (gaps_value as Array)
	):
		if not value is Dictionary:
			errors.append("defaultSocialStateCoverage 条目必须为对象")
			continue
		var combination_id := String(
			(value as Dictionary).get("combinationId", "")
		)
		if combination_id.is_empty():
			errors.append("default social combinationId 不能为空")
		elif ids.has(combination_id):
			errors.append(
				"default social combinationId 重复：%s" % combination_id
			)
		else:
			ids[combination_id] = true


static func _is_integer_number(value: Variant) -> bool:
	return WORLD_SCALARS.is_integer_number(value)


static func _formal_evidence_errors(
	catalog: Dictionary,
	evidence: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if evidence.get("ok") != true:
		errors.append("正式验证证据 ok 必须为 true")
	if evidence.get("validated") != true:
		errors.append("正式验证证据 validated 必须为 true")
	if String(evidence.get("status", "")) != FORMAL_STATUS:
		errors.append("正式验证证据 status 必须为 formal_executable")
	for field in [
		"staticReferencesValidated",
		"activityChainVerified",
		"placeCapabilitiesVerified",
		"scheduleTemplatesResolved",
		"formalExecutable",
	]:
		if evidence.get(field) != true:
			errors.append("正式验证证据缺少 true 字段：%s" % field)
	if String(evidence.get("sourceWorldId", "")) != String(
		catalog.get("worldId", "")
	):
		errors.append("正式验证证据 worldId 不匹配")
	var catalog_fingerprint := String(
		catalog.get("sourceFingerprint", "")
	)
	var recomputed_fingerprint := source_fingerprint(
		catalog.get("occupationDocument", {}) as Dictionary,
		catalog.get("activityDocument", {}) as Dictionary,
		catalog.get("slotDocument", {}) as Dictionary,
		catalog.get("placesDocument", {}) as Dictionary,
		catalog.get("propsDocument", {}) as Dictionary,
		catalog.get("indoorAuthoringDocument", {}) as Dictionary,
		catalog.get("scheduleDocument", {}) as Dictionary,
	)
	var evidence_fingerprint := String(
		evidence.get("sourceFingerprint", "")
	)
	if catalog_fingerprint.is_empty():
		errors.append("Activity Catalog 缺少 sourceFingerprint")
	if recomputed_fingerprint.is_empty():
		errors.append("Activity Catalog 源文档无法重新生成 sourceFingerprint")
	elif catalog_fingerprint != recomputed_fingerprint:
		errors.append(
			"Activity Catalog sourceFingerprint 与当前源文档不匹配"
		)
	if evidence_fingerprint.is_empty():
		errors.append("正式验证证据缺少 sourceFingerprint")
	elif evidence_fingerprint != recomputed_fingerprint:
		errors.append(
			"正式验证证据 sourceFingerprint 与 Catalog 不匹配"
		)
	var catalog_document_fingerprints := catalog.get(
		"sourceDocumentFingerprints",
		{},
	) as Dictionary
	var recomputed_document_fingerprints := (
		VALIDATOR.source_document_fingerprints(
			catalog.get("occupationDocument", {}) as Dictionary,
			catalog.get("activityDocument", {}) as Dictionary,
			catalog.get("slotDocument", {}) as Dictionary,
			catalog.get("placesDocument", {}) as Dictionary,
			catalog.get("propsDocument", {}) as Dictionary,
			catalog.get("indoorAuthoringDocument", {}) as Dictionary,
			catalog.get("scheduleDocument", {}) as Dictionary,
		)
	)
	var evidence_document_fingerprints := evidence.get(
		"sourceDocumentFingerprints",
		{},
	) as Dictionary
	if catalog_document_fingerprints != recomputed_document_fingerprints:
		errors.append("Activity Catalog 单文档 fingerprints 与当前源文档不匹配")
	if evidence_document_fingerprints != recomputed_document_fingerprints:
		errors.append("正式验证证据未绑定 exact 七份源文档")
	var evidence_errors_value: Variant = evidence.get("errors", [])
	if (
		not evidence_errors_value is Array
		and not evidence_errors_value is PackedStringArray
	):
		errors.append("正式验证证据 errors 必须为数组")
	elif not evidence_errors_value.is_empty():
		errors.append("正式验证证据仍包含错误")
	return errors


static func _load_json_document(
	path: String,
	label: String,
	errors: PackedStringArray,
) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("%s 文件不存在：%s" % [label, path])
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("%s 文件无法读取：%s" % [label, path])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		errors.append("%s 必须是 JSON 对象：%s" % [label, path])
		return {}
	return (parsed as Dictionary).duplicate(true)


static func _sort_slot_index(index: Dictionary) -> void:
	for key_value: Variant in index.keys():
		var key := String(key_value)
		var values := index[key] as Array
		values.sort_custom(func(left: Variant, right: Variant) -> bool:
			return String((left as Dictionary).get("slotId", "")) < String(
				(right as Dictionary).get("slotId", "")
			)
		)
		index[key] = values


static func _sort_option_templates(values: Array) -> Array:
	for option_value: Variant in values:
		var option := option_value as Dictionary
		var preferred_slots := option.get("preferredSlots", []) as Array
		preferred_slots.sort_custom(func(left: Variant, right: Variant) -> bool:
			return String((left as Dictionary).get("slotId", "")) < String(
				(right as Dictionary).get("slotId", "")
			)
		)
	values.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_record := left as Dictionary
		var right_record := right as Dictionary
		var left_key := "%s|%s" % [
			String(left_record.get("activityId", "")),
			String(left_record.get("role", "")),
		]
		var right_key := "%s|%s" % [
			String(right_record.get("activityId", "")),
			String(right_record.get("role", "")),
		]
		return left_key < right_key
	)
	return values


static func _sorted_index_values(
	index: Dictionary,
	id_field: String,
) -> Array:
	var result := _duplicate_dictionary_array(index.values())
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		return String((left as Dictionary).get(id_field, "")) < String(
			(right as Dictionary).get(id_field, "")
		)
	)
	return result


static func _duplicate_dictionary_array(values: Array) -> Array:
	var result := []
	for value: Variant in values:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


static func _slot_public_label(
	slot_record: Dictionary,
	target: Dictionary,
) -> String:
	if String(slot_record.get("targetType", "")) == "prop":
		return String(target.get("propName", ""))
	return String(slot_record.get("slotId", ""))


static func _social_state_key(record: Dictionary) -> String:
	return "%s\u001f%s" % [
		String(record.get("occupationName", "")),
		String(record.get("workplacePlace", "")),
	]


static func _has_exact_string_keys(
	value: Dictionary,
	expected: Array,
) -> bool:
	var actual := []
	for key_value: Variant in value.keys():
		actual.append(String(key_value))
	var expected_copy := expected.duplicate()
	actual.sort()
	expected_copy.sort()
	return actual == expected_copy


static func _legacy_key(
	place_name: String,
	prop_name: String,
	action_verb: String,
) -> String:
	if place_name.is_empty() or prop_name.is_empty() or action_verb.is_empty():
		return ""
	return "%s\u001f%s\u001f%s" % [
		place_name,
		prop_name,
		action_verb,
	]


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {
		"ok": false,
		"errorCode": "ACTIVITY_CATALOG_LOAD_FAILED",
		"errors": errors,
		"structurallyValid": false,
		"validated": false,
		"formalExecutable": false,
		"validationStatus": "invalid",
	}
