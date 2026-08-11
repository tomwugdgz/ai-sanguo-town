class_name TownCustomResidentCandidatePool
extends RefCounted


signal candidate_pool_changed(candidate_pool_revision: int, candidates: Array)


const CATALOG := preload("res://world/presentation/session/TownResidentCatalog.gd")
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)
const REQUIRED_ATTRIBUTE_FIELDS: Array[String] = [
	"name",
	"gender",
	"age",
	"appearance",
	"desire",
	"personality",
	"speech",
	"interests",
	"customInterests",
	"selectionSummary",
]


var _base_catalog: Dictionary = {}
var _custom_candidates: Array[Dictionary] = []
var _candidate_pool_revision := 0
var _configured := false
var _identity_sequence := 0
var _persistence: Object


func configure(base_catalog: Dictionary, context: Dictionary = {}) -> Dictionary:
	var validation := CATALOG.validate(base_catalog) as Dictionary
	if not bool(validation.get("ok", false)):
		return validation
	var persistence_value: Variant = context.get("persistence")
	if persistence_value != null and (
		not persistence_value is Object
		or not (persistence_value as Object).has_method("replace_candidates")
	):
		return _failure("CUSTOM_RESIDENT_LIBRARY_CONTRACT_INVALID")
	var custom_candidates_value: Variant = context.get("customCandidates", [])
	if not custom_candidates_value is Array:
		return _failure("CUSTOM_RESIDENT_LIBRARY_INVALID")
	_base_catalog = base_catalog.duplicate(true)
	_custom_candidates.clear()
	_candidate_pool_revision = maxi(
		int(context.get("candidatePoolRevision", 1)),
		1,
	)
	_identity_sequence = 0
	_persistence = persistence_value as Object if persistence_value is Object else null
	for value: Variant in custom_candidates_value as Array:
		if not value is Dictionary:
			return _configuration_failure("CUSTOM_RESIDENT_LIBRARY_INVALID")
		var candidate := _migrate_legacy_candidate(
			(value as Dictionary).duplicate(true),
		)
		var resident_id := String(candidate.get("residentId", "")).strip_edges()
		if resident_id.is_empty() or _resident_id_exists(resident_id):
			return _configuration_failure("CUSTOM_RESIDENT_LIBRARY_INVALID")
		var candidate_validation := _validate_candidate_source(candidate)
		if not bool(candidate_validation.get("ok", false)):
			return _configuration_failure(String(candidate_validation.get(
				"errorCode",
				"CUSTOM_RESIDENT_LIBRARY_INVALID",
			)))
		candidate["residentId"] = resident_id
		candidate["residentName"] = String(
			(candidate.get("attributes", {}) as Dictionary).get("name", ""),
		).strip_edges()
		candidate["source"] = "custom"
		_custom_candidates.append(candidate)
	_configured = true
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"candidatePoolRevision": _candidate_pool_revision,
		"presetCount": (_base_catalog.get("residents", []) as Array).size(),
		"customCount": _custom_candidates.size(),
	}


func create_candidate(candidate_source: Dictionary, expected_revision: int) -> Dictionary:
	if not _configured:
		return _failure("CUSTOM_RESIDENT_CANDIDATE_POOL_NOT_CONFIGURED")
	if expected_revision != _candidate_pool_revision:
		return _failure("CUSTOM_RESIDENT_CANDIDATE_POOL_REVISION_STALE")
	var normalized_source := _migrate_legacy_candidate(
		candidate_source.duplicate(true),
	)
	var validation := _validate_candidate_source(normalized_source)
	if not bool(validation.get("ok", false)):
		return validation
	var candidate := normalized_source.duplicate(true)
	var attributes := (candidate.get("attributes", {}) as Dictionary).duplicate(true)
	var resident_name := String(attributes.get("name", "")).strip_edges()
	if not resident_name_available(resident_name):
		return _failure("CUSTOM_RESIDENT_NAME_DUPLICATED")
	var resident_id := _allocate_resident_id()
	if resident_id.is_empty():
		return _failure("CUSTOM_RESIDENT_ID_ALLOCATION_FAILED")
	candidate["residentId"] = resident_id
	candidate["residentName"] = resident_name
	candidate["source"] = "custom"
	candidate["attributes"] = attributes
	var next_candidates := _custom_candidates.duplicate(true)
	next_candidates.append(candidate)
	var target_revision := _candidate_pool_revision + 1
	var persisted := _persist_candidates(next_candidates, target_revision)
	if not bool(persisted.get("ok", false)):
		return persisted
	_custom_candidates = next_candidates
	_candidate_pool_revision = target_revision
	var selection_entry := _selection_entry(candidate)
	var catalog_entry := _catalog_entry(candidate)
	candidate_pool_changed.emit(
		_candidate_pool_revision,
		get_custom_candidates(),
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"candidatePoolRevision": _candidate_pool_revision,
		"candidate": candidate.duplicate(true),
		"selectionHandoff": {
			"candidatePoolRevision": _candidate_pool_revision,
			"residentId": resident_id,
			"focusedResidentId": resident_id,
			"appendCatalogEntry": catalog_entry,
			"appendSelectionEntry": selection_entry,
		},
	}


func delete_candidate(resident_id: String, expected_revision: int) -> Dictionary:
	var result := delete_candidates([resident_id], expected_revision)
	if not bool(result.get("ok", false)):
		return result
	var deleted_ids := result.get("deletedResidentIds", []) as Array
	var deleted_candidates := result.get("deletedCandidates", []) as Array
	result["deletedResidentId"] = (
		String(deleted_ids[0]) if not deleted_ids.is_empty() else ""
	)
	result["deletedCandidate"] = (
		(deleted_candidates[0] as Dictionary).duplicate(true)
		if not deleted_candidates.is_empty()
		else {}
	)
	return result


func delete_candidates(resident_ids: Array, expected_revision: int) -> Dictionary:
	if not _configured:
		return _failure("CUSTOM_RESIDENT_CANDIDATE_POOL_NOT_CONFIGURED")
	if expected_revision != _candidate_pool_revision:
		return _failure("CUSTOM_RESIDENT_CANDIDATE_POOL_REVISION_STALE")
	var normalized_ids: Array[String] = []
	var requested_ids: Dictionary = {}
	for value: Variant in resident_ids:
		var normalized_id := String(value).strip_edges()
		if normalized_id.is_empty() or requested_ids.has(normalized_id):
			continue
		requested_ids[normalized_id] = true
		normalized_ids.append(normalized_id)
	if normalized_ids.is_empty():
		return _failure("CUSTOM_RESIDENT_ID_REQUIRED")
	var candidate_by_id: Dictionary = {}
	for candidate: Dictionary in _custom_candidates:
		candidate_by_id[String(candidate.get("residentId", ""))] = candidate
	var deleted_candidates: Array[Dictionary] = []
	for normalized_id: String in normalized_ids:
		if not candidate_by_id.has(normalized_id):
			return _failure("CUSTOM_RESIDENT_CANDIDATE_NOT_FOUND")
		deleted_candidates.append(
			(candidate_by_id[normalized_id] as Dictionary).duplicate(true),
		)
	var next_candidates: Array[Dictionary] = []
	for candidate: Dictionary in _custom_candidates:
		if not requested_ids.has(String(candidate.get("residentId", ""))):
			next_candidates.append(candidate.duplicate(true))
	var target_revision := _candidate_pool_revision + 1
	var persisted := _persist_candidates(next_candidates, target_revision)
	if not bool(persisted.get("ok", false)):
		return persisted
	_custom_candidates = next_candidates
	_candidate_pool_revision = target_revision
	candidate_pool_changed.emit(
		_candidate_pool_revision,
		get_custom_candidates(),
	)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"candidatePoolRevision": _candidate_pool_revision,
		"deletedResidentIds": normalized_ids.duplicate(),
		"deletedCandidates": deleted_candidates.duplicate(true),
	}


func candidate_pool_revision() -> int:
	return _candidate_pool_revision


func resident_name_available(resident_name: String) -> bool:
	var normalized := resident_name.strip_edges()
	return not normalized.is_empty() and not _resident_name_exists(normalized)


func get_custom_candidates() -> Array[Dictionary]:
	return _custom_candidates.duplicate(true)


func get_merged_catalog() -> Dictionary:
	if not _configured:
		return {}
	var merged := _base_catalog.duplicate(true)
	var residents := (merged.get("residents", []) as Array).duplicate(true)
	for candidate in _custom_candidates:
		residents.append(_catalog_entry(candidate))
	merged["residents"] = residents
	return merged


func get_selection_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate in _custom_candidates:
		result.append(_selection_entry(candidate))
	return result


func get_resident_selection_projection() -> Dictionary:
	var catalog_entries: Array[Dictionary] = []
	for candidate in _custom_candidates:
		catalog_entries.append(_catalog_entry(candidate))
	return {
		"ok": _configured,
		"errorCode": "" if _configured else "CUSTOM_RESIDENT_CANDIDATE_POOL_NOT_CONFIGURED",
		"retryable": false,
		"candidatePoolRevision": _candidate_pool_revision,
		"catalogEntries": catalog_entries,
		"selectionEntries": get_selection_entries(),
	}


func _validate_candidate_source(candidate: Dictionary) -> Dictionary:
	if String(candidate.get("source", "custom")) != "custom":
		return _failure("CUSTOM_RESIDENT_SOURCE_INVALID")
	var attributes_value: Variant = candidate.get("attributes")
	var appearance_value: Variant = candidate.get("appearance")
	var occupation_value: Variant = candidate.get("occupation")
	var presentation_value: Variant = candidate.get("presentation")
	if (
		not attributes_value is Dictionary
		or not appearance_value is Dictionary
		or not occupation_value is Dictionary
		or not presentation_value is Dictionary
	):
		return _failure("CUSTOM_RESIDENT_PROFILE_INVALID")
	var attributes := attributes_value as Dictionary
	var attribute_keys := attributes.keys()
	var expected_attribute_keys := REQUIRED_ATTRIBUTE_FIELDS.duplicate()
	attribute_keys.sort()
	expected_attribute_keys.sort()
	if attribute_keys != expected_attribute_keys:
		return _failure("CUSTOM_RESIDENT_PROFILE_INVALID")
	for field in REQUIRED_ATTRIBUTE_FIELDS:
		if field == "age":
			var age_value: Variant = attributes.get(field)
			if (
				typeof(age_value) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(age_value))
				or float(age_value) != floor(float(age_value))
				or int(age_value) < 1
				or int(age_value) > 120
			):
				return _failure("CUSTOM_RESIDENT_AGE_INVALID")
		elif field == "interests":
			var interest_error := INTERESTS.profile_validation_error(
				attributes.get("interests", []),
				attributes.get("customInterests", []),
			)
			if not interest_error.is_empty():
				return _failure(interest_error)
		elif field == "customInterests":
			continue
		else:
			var text_value: Variant = attributes.get(field)
			if (
				not text_value is String
				or (text_value as String).strip_edges().is_empty()
				or text_value != (text_value as String).strip_edges()
			):
				return _failure("CUSTOM_RESIDENT_ATTRIBUTE_REQUIRED")
	var name := String(attributes.get("name", "")).strip_edges()
	if name.length() > 24:
		return _failure("CUSTOM_RESIDENT_NAME_TOO_LONG")
	if (
		not attributes.get("gender") is String
		or attributes.get("gender") not in ["男", "女"]
	):
		return _failure("CUSTOM_RESIDENT_GENDER_INVALID")
	for field in ["desire", "personality", "speech"]:
		if String(attributes.get(field, "")).length() > 240:
			return _failure("CUSTOM_RESIDENT_TEXT_TOO_LONG")
	var selection_summary := String(attributes.get("selectionSummary", "")).strip_edges()
	if selection_summary.is_empty() or selection_summary.length() > 24:
		return _failure("CUSTOM_RESIDENT_SELECTION_SUMMARY_INVALID")
	var appearance := appearance_value as Dictionary
	if (
		appearance.size() != 10
		or not appearance.get("appearanceId") is String
		or String(appearance.get("appearanceId", "")).strip_edges().is_empty()
		or not appearance.get("loadoutId") is String
		or String(appearance.get("loadoutId", "")).strip_edges().is_empty()
		or not appearance.get("selection") is Dictionary
		or not appearance.get("formalReady") is bool
		or appearance.get("formalReady") != true
		or not appearance.get("directionSetReady") is bool
		or appearance.get("directionSetReady") != true
		or not appearance.get("displayName") is String
		or String(appearance.get("displayName", "")).strip_edges().is_empty()
		or not appearance.get("portraitPath") is String
		or not appearance.get("spriteSheetPath") is String
		or not appearance.get("restPath") is String
		or not appearance.get("legacySpritePath") is String
	):
		return _failure("CUSTOM_RESIDENT_APPEARANCE_NOT_READY")
	var appearance_id := String(appearance.get("appearanceId", ""))
	var loadout_id := String(appearance.get("loadoutId", ""))
	if (
		appearance_id != "resident_wardrobe_v1:%s" % loadout_id
		or String(attributes.get("appearance", "")) != appearance_id
	):
		return _failure("CUSTOM_RESIDENT_APPEARANCE_NOT_READY")
	var selection := appearance.get("selection", {}) as Dictionary
	if selection.size() != 4:
		return _failure("CUSTOM_RESIDENT_APPEARANCE_NOT_READY")
	for slot_id in ["hair", "top", "bottom", "shoes"]:
		if String(selection.get(slot_id, "")).strip_edges().is_empty():
			return _failure("CUSTOM_RESIDENT_APPEARANCE_NOT_READY")
	var loadout := _wardrobe_loadout(loadout_id)
	var directions := loadout.get("directions", {}) as Dictionary
	var down := directions.get("down", {}) as Dictionary
	var portrait_path := String(appearance.get("portraitPath", ""))
	var rest_path := String(appearance.get("restPath", ""))
	var legacy_sprite_path := String(appearance.get("legacySpritePath", ""))
	if (
		loadout.is_empty()
		or selection.get("hair") != loadout.get("headId")
		or selection.get("top") != loadout.get("outfitId")
		or selection.get("bottom") != loadout.get("outfitId")
		or selection.get("shoes") != loadout.get("outfitId")
		or portrait_path != String(loadout.get("portraitPath", ""))
		or rest_path != String(down.get("restPath", ""))
		or not _texture_path_is_ready(portrait_path)
		or not _texture_path_is_ready(rest_path)
		or not _texture_path_is_ready(legacy_sprite_path)
	):
		return _failure("CUSTOM_RESIDENT_APPEARANCE_NOT_READY")
	var occupation := occupation_value as Dictionary
	if (
		occupation.keys().size() != 2
		or not occupation.has("name")
		or not occupation.has("workplacePlace")
		or not occupation.get("name") is String
		or String(occupation.get("name", "")).strip_edges().is_empty()
		or not occupation.get("workplacePlace") is String
		or String(occupation.get("workplacePlace", "")).strip_edges().is_empty()
	):
		return _failure("CUSTOM_RESIDENT_OCCUPATION_REQUIRED")
	var presentation := presentation_value as Dictionary
	if (
		presentation.size() != 3
		or presentation.get("spritePath") != legacy_sprite_path
		or presentation.get("portraitPath") != portrait_path
		or not presentation.get("locationLabel") is String
		or String(presentation.get("locationLabel", "")).strip_edges()
		!= String(occupation.get("workplacePlace", "")).strip_edges()
	):
		return _failure("CUSTOM_RESIDENT_PRESENTATION_NOT_READY")
	return {"ok": true, "errorCode": "", "retryable": false}


func _migrate_legacy_candidate(candidate: Dictionary) -> Dictionary:
	var attributes_value: Variant = candidate.get("attributes")
	var appearance_value: Variant = candidate.get("appearance")
	var occupation_value: Variant = candidate.get("occupation")
	var presentation_value: Variant = candidate.get("presentation")
	if (
		attributes_value is not Dictionary
		or appearance_value is not Dictionary
		or occupation_value is not Dictionary
		or presentation_value is not Dictionary
	):
		return candidate
	var attributes := attributes_value as Dictionary
	var migrated_interest_attributes := INTERESTS.migrate_attributes(
		attributes,
	)
	candidate["attributes"] = migrated_interest_attributes
	attributes = migrated_interest_attributes
	var migrated_occupation := (
		(occupation_value as Dictionary).duplicate(true)
	)
	migrated_occupation.erase("ownedPlace")
	candidate["occupation"] = migrated_occupation
	var legacy_appearance := appearance_value as Dictionary
	var legacy_appearance_id := String(
		legacy_appearance.get("appearanceId", ""),
	).strip_edges()
	if (
		attributes.has("appearance")
		or not legacy_appearance_id.begins_with("paper_doll_64:")
	):
		return candidate
	var catalog := _wardrobe_catalog()
	var aliases := catalog.get("legacyAppearanceAliases", {}) as Dictionary
	var loadout_id := String(aliases.get(legacy_appearance_id, ""))
	if loadout_id.is_empty():
		loadout_id = _legacy_mixed_loadout_id(legacy_appearance_id, catalog)
	var loadout := _wardrobe_loadout_from_catalog(loadout_id, catalog)
	var directions := loadout.get("directions", {}) as Dictionary
	var down := directions.get("down", {}) as Dictionary
	var portrait_path := String(loadout.get("portraitPath", ""))
	var sprite_sheet_path := String(loadout.get("spriteSheetPath", ""))
	var rest_path := String(down.get("restPath", ""))
	var legacy_sprite_path := String(
		(presentation_value as Dictionary).get("spritePath", ""),
	)
	if (
		loadout.is_empty()
		or legacy_sprite_path.is_empty()
		or not _texture_path_is_ready(portrait_path)
		or not _texture_path_is_ready(rest_path)
		or not _texture_path_is_ready(legacy_sprite_path)
	):
		return candidate
	var appearance_id := "resident_wardrobe_v1:%s" % loadout_id
	var migrated_attributes := attributes.duplicate(true)
	migrated_attributes["appearance"] = appearance_id
	var migrated_presentation := (
		(presentation_value as Dictionary).duplicate(true)
	)
	migrated_presentation["portraitPath"] = portrait_path
	candidate["attributes"] = migrated_attributes
	candidate["appearance"] = {
		"appearanceId": appearance_id,
		"loadoutId": loadout_id,
		"displayName": String(loadout.get("label", "小镇居民搭配")),
		"selection": {
			"hair": String(loadout.get("headId", "")),
			"top": String(loadout.get("outfitId", "")),
			"bottom": String(loadout.get("outfitId", "")),
			"shoes": String(loadout.get("outfitId", "")),
		},
		"portraitPath": portrait_path,
		"spriteSheetPath": sprite_sheet_path,
		"restPath": rest_path,
		"legacySpritePath": legacy_sprite_path,
		"formalReady": true,
		"directionSetReady": true,
	}
	candidate["presentation"] = migrated_presentation
	return candidate


func _legacy_mixed_loadout_id(
	legacy_appearance_id: String,
	catalog: Dictionary,
) -> String:
	var loadouts := catalog.get("loadouts", []) as Array
	if loadouts.is_empty():
		return ""
	var checksum := 5381
	for byte: int in legacy_appearance_id.to_utf8_buffer():
		checksum = int((checksum * 33 + byte) & 0x7fffffff)
	var selected_value: Variant = loadouts[checksum % loadouts.size()]
	if selected_value is not Dictionary:
		return ""
	return String((selected_value as Dictionary).get("id", ""))


func _wardrobe_loadout(loadout_id: String) -> Dictionary:
	return _wardrobe_loadout_from_catalog(loadout_id, _wardrobe_catalog())


func _wardrobe_catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(WARDROBE_CATALOG_PATH),
	)
	if (
		parsed is not Dictionary
		or String((parsed as Dictionary).get("schema", ""))
		!= "ai-town.resident-wardrobe.v1"
	):
		return {}
	return (parsed as Dictionary).duplicate(true)


func _wardrobe_loadout_from_catalog(
	loadout_id: String,
	catalog: Dictionary,
) -> Dictionary:
	for loadout_value: Variant in (
		catalog.get("loadouts", []) as Array
	):
		if (
			loadout_value is Dictionary
			and String((loadout_value as Dictionary).get("id", ""))
			== loadout_id
		):
			return (loadout_value as Dictionary).duplicate(true)
	return {}


func _texture_path_is_ready(path: String) -> bool:
	return (
		not path.is_empty()
		and path.begins_with("res://")
		and ResourceLoader.exists(path, "Texture2D")
		and load(path) is Texture2D
	)


func _resident_name_exists(resident_name: String) -> bool:
	for value: Variant in _base_catalog.get("residents", []) as Array:
		var attributes := (value as Dictionary).get("attributes", {}) as Dictionary
		if String(attributes.get("name", "")).strip_edges() == resident_name:
			return true
	for candidate in _custom_candidates:
		var attributes := candidate.get("attributes", {}) as Dictionary
		if String(attributes.get("name", "")).strip_edges() == resident_name:
			return true
	return false


func _allocate_resident_id() -> String:
	for _attempt in 16:
		_identity_sequence += 1
		var random_bytes := Crypto.new().generate_random_bytes(12)
		if random_bytes.is_empty():
			continue
		var candidate_id := "custom_resident_%s_%04d" % [
			random_bytes.hex_encode(),
			_identity_sequence,
		]
		if not _resident_id_exists(candidate_id):
			return candidate_id
	return ""


func _resident_id_exists(resident_id: String) -> bool:
	for value: Variant in _base_catalog.get("residents", []) as Array:
		if String((value as Dictionary).get("residentId", "")) == resident_id:
			return true
	for candidate in _custom_candidates:
		if String(candidate.get("residentId", "")) == resident_id:
			return true
	return false


func _persist_candidates(
	candidates: Array,
	target_revision: int,
) -> Dictionary:
	if _persistence == null:
		return {"ok": true, "errorCode": "", "retryable": false}
	var result := _persistence.call(
		"replace_candidates",
		candidates,
		_candidate_pool_revision,
		target_revision,
	) as Dictionary
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"errorCode": String(result.get(
				"errorCode",
				"CUSTOM_RESIDENT_LIBRARY_WRITE_FAILED",
			)),
			"retryable": bool(result.get("retryable", false)),
			"candidatePoolRevision": _candidate_pool_revision,
		}
	if int(result.get("libraryRevision", 0)) != target_revision:
		return _failure("CUSTOM_RESIDENT_LIBRARY_REVISION_INVALID")
	return {"ok": true, "errorCode": "", "retryable": false}


func _configuration_failure(error_code: String) -> Dictionary:
	_custom_candidates.clear()
	_base_catalog.clear()
	_persistence = null
	_configured = false
	return _failure(error_code)


func _catalog_entry(candidate: Dictionary) -> Dictionary:
	return {
		"residentId": String(candidate.get("residentId", "")),
		"attributes": (
			candidate.get("attributes", {}) as Dictionary
		).duplicate(true),
		"occupation": (candidate.get("occupation", {}) as Dictionary).duplicate(true),
		"presentation": (candidate.get("presentation", {}) as Dictionary).duplicate(true),
		"source": "custom",
	}


func _selection_entry(candidate: Dictionary) -> Dictionary:
	var attributes := candidate.get("attributes", {}) as Dictionary
	var occupation := candidate.get("occupation", {}) as Dictionary
	var presentation := candidate.get("presentation", {}) as Dictionary
	var portrait_path := String(presentation.get("portraitPath", ""))
	return {
		"resident_id": String(candidate.get("residentId", "")),
		"display_name": String(attributes.get("name", "")),
		"occupation": String(occupation.get("name", "")),
		"selection_summary": String(attributes.get("selectionSummary", "")),
		"one_line_role": String(attributes.get("selectionSummary", "")),
		"personality": String(attributes.get("personality", "")),
		"desire": String(attributes.get("desire", "")),
		"interests": INTERESTS.normalize(attributes.get("interests", [])),
		"custom_interests": INTERESTS.normalize_custom(
			attributes.get("customInterests", []),
		),
		"interest_labels": INTERESTS.combined_labels_for(
			attributes.get("interests", []),
			attributes.get("customInterests", []),
		),
		"location": String(presentation.get("locationLabel", "")),
		"sprite_path": String(presentation.get("spritePath", "")),
		"portrait_path": portrait_path,
		"portrait_frame_mode": "full_texture",
		"source": "custom",
	}


func _failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"candidatePoolRevision": _candidate_pool_revision,
	}
