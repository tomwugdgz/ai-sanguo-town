class_name ResidentProfileEditorService
extends RefCounted


signal view_model_changed(scope: String, view_model: Dictionary)
signal operation_completed(scope: String, operation: Dictionary)


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const SCOPE := "custom_resident_creator"
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const OCCUPATION_CATALOG_PATH := (
	"res://world/data/town/source/occupation_catalog.json"
)
const WARDROBE_ROOT := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1"
)
const WARDROBE_CATALOG_PATH := WARDROBE_ROOT + "/wardrobe_catalog.json"
const WARDROBE_SCHEMA := "ai-town.resident-wardrobe.v1"
const WARDROBE_SOURCE_DIRECTIONS: Array[String] = ["down", "right", "up"]
const WARDROBE_ALL_DIRECTIONS: Array[String] = [
	"down",
	"right",
	"up",
	"left",
]
const WARDROBE_SLOTS: Array[String] = [
	"hair",
	"top",
	"bottom",
	"shoes",
]
const EDITABLE_FIELDS: Array[String] = [
	"gender",
	"age",
	"desire",
	"personality",
	"speech",
	"interests",
	"customInterests",
	"occupationId",
	"workplaceId",
	"ownedPlaceId",
]
const INTENT_TO_ACTION := {
	"resident_profile_editor.update_fields": "updateFields",
	"resident_profile_editor.open_wardrobe": "openWardrobe",
	"resident_profile_editor.apply_wardrobe_result": "applyWardrobeResult",
	"resident_profile_editor.save_existing": "saveExisting",
	"resident_profile_editor.cancel": "cancel",
	"resident_profile_editor.retry": "retry",
}


var _adapter: Object
var _resident_id := ""
var _draft_id := ""
var _draft: Dictionary = {}
var _original_draft: Dictionary = {}
var _options: Dictionary = {}
var _resolved_appearance: Dictionary = {}
var _wardrobe_by_appearance_id: Dictionary = {}
var _wardrobe_by_selection: Dictionary = {}
var _wardrobe_by_loadout_id: Dictionary = {}
var _wardrobe_assignment_by_resident_id: Dictionary = {}
var _wardrobe_alias_by_appearance_id: Dictionary = {}
var _wardrobe_available := false
var _wardrobe_error := "RESIDENT_PROFILE_WARDROBE_CATALOG_MISSING"
var _revision := 0
var _request_sequence := 0
var _configured := false
var _operation := _idle_operation()
var _error: Variant = null
var _configuration_error := "RESIDENT_PROFILE_EDITOR_NOT_CONFIGURED"


func configure(adapter: Object, resident_id: String) -> Dictionary:
	_adapter = null
	_resident_id = resident_id.strip_edges()
	_draft_id = ""
	_draft.clear()
	_original_draft.clear()
	_options.clear()
	_resolved_appearance.clear()
	_wardrobe_by_appearance_id.clear()
	_wardrobe_by_selection.clear()
	_wardrobe_by_loadout_id.clear()
	_wardrobe_assignment_by_resident_id.clear()
	_wardrobe_alias_by_appearance_id.clear()
	_wardrobe_available = false
	_wardrobe_error = "RESIDENT_PROFILE_WARDROBE_CATALOG_MISSING"
	_revision = 1
	_request_sequence = 0
	_configured = false
	_operation = _idle_operation()
	_error = null
	_configuration_error = "RESIDENT_PROFILE_EDITOR_NOT_CONFIGURED"
	if (
		adapter == null
		or not adapter.has_method("get_view_model")
		or not adapter.has_method("dispatch")
	):
		return _configuration_failure("RESIDENT_PROFILE_EDITOR_ADAPTER_INVALID")
	if _resident_id.is_empty():
		return _configuration_failure("RESIDENT_IDENTITY_NOT_FOUND")
	var wardrobe_result := _load_wardrobe_catalog()
	if not bool(wardrobe_result.get("ok", false)):
		# Wardrobe is a child capability of resident editing. A missing or
		# temporarily invalid wardrobe catalog must not make the resident's
		# identity, personality, or social profile unreadable.
		_wardrobe_error = String(wardrobe_result.get(
			"errorCode",
			"RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID",
		))
	_adapter = adapter
	var loaded := _reload_from_overview()
	if not bool(loaded.get("ok", false)):
		_adapter = null
		return loaded
	_draft_id = "resident-profile:%s" % _resident_id
	_configured = true
	_configuration_error = ""
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"residentId": _resident_id,
		"draftId": _draft_id,
		"revision": _revision,
	}


func get_view_model() -> Dictionary:
	if not _configured:
		return _disabled_view_model()
	var validation := _validate_draft()
	return {
		"scope": SCOPE,
		"status": (
			"error"
			if String(_operation.get("status", "")) == "error"
			else "ready"
		),
		"revision": _revision,
		"data": {
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": true,
			"residentId": _resident_id,
			"draftId": _draft_id,
			"candidatePoolRevision": 0,
			"draft": _draft.duplicate(true),
			"dirty": _draft != _original_draft,
			"resolvedAppearance": _resolved_appearance.duplicate(true),
			"options": _options.duplicate(true),
			"editableFields": EDITABLE_FIELDS.duplicate(),
			"readOnlyFields": ["name"],
			"validation": validation,
		},
		"actions": _actions(validation),
		"operation": _operation.duplicate(true),
		"error": (
			null
			if _error == null
			else (_error as Dictionary).duplicate(true)
		),
	}


func dispatch(intent: String, payload: Dictionary = {}) -> Dictionary:
	var action_key := String(INTENT_TO_ACTION.get(intent, ""))
	var request_id := _next_request_id()
	if action_key.is_empty():
		return _dispatch_result(
			false,
			false,
			request_id,
			"UNKNOWN_RESIDENT_PROFILE_EDITOR_INTENT",
		)
	if not _configured:
		return _dispatch_result(
			false,
			false,
			request_id,
			_configuration_error,
		)
	if int(payload.get("revision", -1)) != _revision:
		return _publish(
			request_id,
			intent,
			_failure("RESIDENT_PROFILE_EDITOR_REVISION_STALE"),
		)
	if String(payload.get("draftId", "")) != _draft_id:
		return _publish(
			request_id,
			intent,
			_failure("RESIDENT_PROFILE_EDITOR_DRAFT_MISMATCH"),
		)
	var action := _actions(_validate_draft()).get(action_key, {}) as Dictionary
	if not bool(action.get("enabled", false)):
		return _publish(
			request_id,
			intent,
			_failure(String(action.get(
				"disabledReason",
				"RESIDENT_PROFILE_EDITOR_ACTION_DISABLED",
			))),
		)
	var result: Dictionary
	match intent:
		"resident_profile_editor.update_fields":
			var fields_value: Variant = payload.get("fields")
			result = (
				_update_fields(fields_value as Dictionary)
				if fields_value is Dictionary
				else _failure("RESIDENT_PROFILE_FIELDS_INVALID")
			)
		"resident_profile_editor.open_wardrobe":
			result = _open_wardrobe()
		"resident_profile_editor.apply_wardrobe_result":
			var selection_value: Variant = payload.get("selection", {})
			result = (
				_apply_wardrobe_result(
					selection_value as Dictionary,
					String(payload.get("loadoutId", "")),
				)
				if selection_value is Dictionary
				else _failure("RESIDENT_PROFILE_APPEARANCE_SELECTION_INVALID")
			)
		"resident_profile_editor.save_existing":
			result = _save_existing()
		"resident_profile_editor.cancel":
			result = _success(false)
		_:
			result = _failure("RESIDENT_PROFILE_EDITOR_ACTION_DISABLED")
	return _publish(request_id, intent, result)


func _reload_from_overview() -> Dictionary:
	if _adapter == null:
		return _configuration_failure("RESIDENT_PROFILE_EDITOR_ADAPTER_INVALID")
	var overview := _adapter.call(
		"get_view_model",
		"resident_overview",
	) as Dictionary
	var data := overview.get("data", {}) as Dictionary
	var selected: Dictionary = {}
	for value: Variant in data.get("residents", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("residentId", ""))
			== _resident_id
		):
			selected = (value as Dictionary).duplicate(true)
			break
	if selected.is_empty():
		return _configuration_failure("RESIDENT_IDENTITY_NOT_FOUND")
	var overview_options := data.get("options", {}) as Dictionary
	var appearance_id := String(selected.get("appearanceId", ""))
	_resolved_appearance = (
		_wardrobe_by_appearance_id.get(appearance_id, {}) as Dictionary
	).duplicate(true)
	if _resolved_appearance.is_empty():
		var aliased_loadout_id := String(
			_wardrobe_alias_by_appearance_id.get(appearance_id, ""),
		)
		if aliased_loadout_id.is_empty():
			aliased_loadout_id = String(
				_wardrobe_assignment_by_resident_id.get(_resident_id, ""),
			)
		_resolved_appearance = (
			_wardrobe_by_loadout_id.get(aliased_loadout_id, {}) as Dictionary
		).duplicate(true)
	if _resolved_appearance.is_empty():
		# Existing residents remain editable if an older save references an
		# appearance that the current formal wardrobe no longer knows.
		_resolved_appearance = {
			"appearanceId": appearance_id,
			"loadoutId": "",
			"displayName": "当前形象",
			"selection": {},
			"atlasRef": String(selected.get("portraitRef", "")),
			"formalReady": false,
			"directionSetReady": false,
		}
	var occupations := _occupation_options(
		overview_options.get("occupations", []) as Array,
	)
	var workplaces := _normalized_options(
		overview_options.get("workplaces", []) as Array,
	)
	var homes := _normalized_options(
		overview_options.get("homes", []) as Array,
	)
	_options = {
		"genders": [
			{"id": "女", "label": "女"},
			{"id": "男", "label": "男"},
		],
		"age": {"min": 1, "max": 120, "step": 1},
		"interests": INTERESTS.options(),
		"maxInterests": INTERESTS.max_interests(),
		"wardrobe": {
			"entryMode": "route_to_formal_wardrobe",
			"catalogPath": WARDROBE_CATALOG_PATH,
			"schema": "ai-town.resident-wardrobe.v1",
			"runtimeMode": "resident_2d_rig_v1",
			"slotOrder": WARDROBE_SLOTS.duplicate(),
			"available": _wardrobe_available,
			"disabledReason": "" if _wardrobe_available else _wardrobe_error,
		},
		"occupations": occupations,
		"workplaces": workplaces,
		# 兴趣继续使用原铺面栏。住所属于居民槽位保存的社会状态，
		# 在编辑现有居民时单独只读展示，不能再复用兴趣字段。
		"ownedPlaces": homes,
	}
	_draft = {
		"name": String(selected.get("displayName", "")),
		"gender": String(selected.get("genderLabel", "")),
		"age": int(selected.get("age", 0)),
		"appearanceSelection": (
			_resolved_appearance.get("selection", {}) as Dictionary
		).duplicate(true),
		"desire": String(selected.get("desire", "")),
		"personality": String(selected.get("personality", "")),
		"speech": String(selected.get("speech", "")),
		"interests": INTERESTS.normalize(
			selected.get("interests", []),
		),
		"customInterests": INTERESTS.normalize_custom(
			selected.get("customInterests", []),
		),
		"occupationId": "occupation:%s" % String(
			selected.get("occupationLabel", ""),
		),
		"workplaceId": String(selected.get("workplaceLabel", "")),
		"ownedPlaceId": String(selected.get("homeLabel", "")),
	}
	_original_draft = _draft.duplicate(true)
	return {"ok": true, "errorCode": "", "retryable": false}


func _open_wardrobe() -> Dictionary:
	if (
		not _wardrobe_available
		or _resolved_appearance.is_empty()
		or not bool(_resolved_appearance.get("formalReady", false))
	):
		return _failure(
			_wardrobe_error
			if not _wardrobe_available
			else "RESIDENT_PROFILE_APPEARANCE_NOT_READY"
		)
	var result := _success(false)
	result["wardrobeHandoff"] = {
		"sourceScope": SCOPE,
		"draftId": _draft_id,
		"returnRevision": _revision + 1,
		"returnIntent": "resident_profile_editor.apply_wardrobe_result",
		"cancelIntent": "resident_profile_editor.wardrobe_cancelled",
		"runtimeMode": "resident_2d_rig_v1",
		"catalogPath": WARDROBE_CATALOG_PATH,
		"slotOrder": WARDROBE_SLOTS.duplicate(),
		"selection": (
			_resolved_appearance.get("selection", {}) as Dictionary
		).duplicate(true),
		"loadoutId": String(_resolved_appearance.get("loadoutId", "")),
		"portraitPath": String(_resolved_appearance.get("portraitPath", "")),
		"spriteSheetPath": String(
			_resolved_appearance.get("spriteSheetPath", ""),
		),
		"restPath": String(_resolved_appearance.get("restPath", "")),
	}
	return result


func _apply_wardrobe_result(
	selection: Dictionary,
	loadout_id: String = "",
) -> Dictionary:
	if not _wardrobe_available:
		return _failure(_wardrobe_error)
	var normalized_loadout_id := loadout_id.strip_edges()
	var appearance: Dictionary = {}
	if not normalized_loadout_id.is_empty():
		appearance = (
			_wardrobe_by_loadout_id.get(normalized_loadout_id, {}) as Dictionary
		).duplicate(true)
	if appearance.is_empty():
		var selection_key := _selection_key(selection)
		appearance = (
			_wardrobe_by_selection.get(selection_key, {}) as Dictionary
		).duplicate(true)
	if (
		appearance.is_empty()
		or not bool(appearance.get("formalReady", false))
		or not bool(appearance.get("directionSetReady", false))
	):
		return _failure("RESIDENT_PROFILE_APPEARANCE_SELECTION_INVALID")
	var normalized := (
		appearance.get("selection", {}) as Dictionary
	).duplicate(true)
	var changed := normalized != (
		_draft.get("appearanceSelection", {}) as Dictionary
	)
	_draft["appearanceSelection"] = normalized
	_resolved_appearance = appearance
	var result := _success(changed)
	result["resolvedAppearance"] = appearance.duplicate(true)
	return result


func _update_fields(fields: Dictionary) -> Dictionary:
	if fields.is_empty():
		return _failure("RESIDENT_PROFILE_FIELDS_REQUIRED")
	var next := _draft.duplicate(true)
	for key_value: Variant in fields:
		var key := String(key_value)
		if key not in EDITABLE_FIELDS:
			return _failure("RESIDENT_PROFILE_FIELD_NOT_EDITABLE")
		match key:
			"age":
				var age := int(fields[key])
				if age < 1 or age > 120:
					return _failure("RESIDENT_PROFILE_AGE_INVALID")
				next[key] = age
			"gender":
				var gender := String(fields[key])
				if gender not in ["男", "女"]:
					return _failure("RESIDENT_PROFILE_GENDER_INVALID")
				next[key] = gender
			"occupationId":
				var occupation_id := String(fields[key])
				if not _option_has_id(
					_options.get("occupations", []) as Array,
					occupation_id,
				):
					return _failure("RESIDENT_PROFILE_OCCUPATION_UNKNOWN")
				next[key] = occupation_id
				var workplace_id := _workplace_for_occupation(
					occupation_id.trim_prefix("occupation:"),
				)
				if workplace_id.is_empty():
					return _failure("RESIDENT_PROFILE_WORKPLACE_UNKNOWN")
				next["workplaceId"] = workplace_id
			"workplaceId":
				var selected_workplace_id := String(fields[key]).strip_edges()
				if not _option_has_id(
					_options.get("workplaces", []) as Array,
					selected_workplace_id,
				):
					return _failure("RESIDENT_PROFILE_WORKPLACE_UNKNOWN")
				next[key] = selected_workplace_id
			"ownedPlaceId":
				var owned_place_id := String(fields[key]).strip_edges()
				if not _option_has_id(
					_options.get("ownedPlaces", []) as Array,
					owned_place_id,
				):
					return _failure("RESIDENT_PROFILE_HOME_UNKNOWN")
				next[key] = owned_place_id
			"interests":
				var interest_values := INTERESTS.normalize(fields[key])
				var interest_error := INTERESTS.profile_validation_error(
					interest_values,
					next.get("customInterests", []),
				)
				if not interest_error.is_empty():
					return _failure(interest_error)
				next[key] = interest_values
			"customInterests":
				var custom_interest_values := INTERESTS.normalize_custom(
					fields[key],
				)
				var custom_interest_error := (
					INTERESTS.profile_validation_error(
						next.get("interests", []),
						custom_interest_values,
					)
				)
				if not custom_interest_error.is_empty():
					return _failure(custom_interest_error)
				next[key] = custom_interest_values
			_:
				next[key] = String(fields[key]).strip_edges()
	var changed := next != _draft
	_draft = next
	return _success(changed)


func _save_existing() -> Dictionary:
	var validation := _validate_draft()
	if String(validation.get("status", "")) != "valid":
		return _failure(
			"RESIDENT_PROFILE_DRAFT_INVALID",
			validation.get("issues", []) as Array,
		)
	var occupation_id := String(_draft.get("occupationId", ""))
	var job := occupation_id.trim_prefix("occupation:")
	var dispatch_result := _adapter.call(
		"dispatch",
		"resident_overview.update_profile",
		{
			"residentId": _resident_id,
			"profile": {
				"home": String(_draft.get("ownedPlaceId", "")),
				"job": job,
				"workplace": String(_draft.get("workplaceId", "")),
				"attributes": {
					"gender": String(_draft.get("gender", "")),
					"age": int(_draft.get("age", 0)),
					"appearance": String(
						_resolved_appearance.get("appearanceId", ""),
					),
					"desire": String(_draft.get("desire", "")),
					"personality": String(_draft.get("personality", "")),
					"speech": String(_draft.get("speech", "")),
					"interests": INTERESTS.normalize(
						_draft.get("interests", []),
					),
					"customInterests": INTERESTS.normalize_custom(
						_draft.get("customInterests", []),
					),
				},
			},
		},
	) as Dictionary
	if not bool(dispatch_result.get("ok", false)):
		return _failure(String(dispatch_result.get(
			"errorCode",
			"RESIDENT_PROFILE_SAVE_REJECTED",
		)))
	var reloaded := _reload_from_overview()
	if not bool(reloaded.get("ok", false)):
		return reloaded
	var result := _success(bool(dispatch_result.get("changed", true)))
	result["residentId"] = _resident_id
	result["worldRequestId"] = String(dispatch_result.get("requestId", ""))
	return result


func _validate_draft() -> Dictionary:
	var issues: Array[Dictionary] = []
	var field_issues := {}
	for field in ["name", "desire", "personality", "speech"]:
		if String(_draft.get(field, "")).strip_edges().is_empty():
			_add_issue(
				field,
				"RESIDENT_PROFILE_%s_REQUIRED" % field.to_upper(),
				"此项不能为空。",
				issues,
				field_issues,
			)
	var age := int(_draft.get("age", 0))
	if age < 1 or age > 120:
		_add_issue(
			"age",
			"RESIDENT_PROFILE_AGE_INVALID",
			"年龄需在 1 到 120 岁之间。",
			issues,
			field_issues,
		)
	if String(_draft.get("gender", "")) not in ["男", "女"]:
		_add_issue(
			"gender",
			"RESIDENT_PROFILE_GENDER_INVALID",
			"性别仅支持男或女。",
			issues,
			field_issues,
		)
	var interest_error := INTERESTS.profile_validation_error(
		_draft.get("interests", []),
		_draft.get("customInterests", []),
	)
	if not interest_error.is_empty():
		_add_issue(
			"interests",
			interest_error,
			"兴趣合计最多三项；自定义兴趣需为 1 到 20 个字且不能重复。",
			issues,
			field_issues,
		)
	for pair in [
		["occupationId", "occupations", "RESIDENT_PROFILE_OCCUPATION_UNKNOWN"],
		["workplaceId", "workplaces", "RESIDENT_PROFILE_WORKPLACE_UNKNOWN"],
		["ownedPlaceId", "ownedPlaces", "RESIDENT_PROFILE_HOME_UNKNOWN"],
	]:
		var field := String(pair[0])
		if not _option_has_id(
			_options.get(String(pair[1]), []) as Array,
			String(_draft.get(field, "")),
		):
			_add_issue(
				field,
				String(pair[2]),
				"请选择本局可用资料。",
				issues,
				field_issues,
			)
	return {
		"status": "valid" if issues.is_empty() else "invalid",
		"summaryLabel": (
			"资料完整，可以保存"
			if issues.is_empty()
			else "请完成所有必填资料"
		),
		"issues": issues,
		"fieldIssues": field_issues,
	}


func _actions(validation: Dictionary) -> Dictionary:
	var valid := String(validation.get("status", "")) == "valid"
	return {
		"updateFields": _action("resident_profile_editor.update_fields", true),
		"openWardrobe": _action(
			"resident_profile_editor.open_wardrobe",
			(
				_wardrobe_available
				and bool(_resolved_appearance.get("formalReady", false))
			),
			(
				_wardrobe_error
				if not _wardrobe_available
				else "RESIDENT_PROFILE_APPEARANCE_NOT_READY"
			),
		),
		"applyWardrobeResult": _action(
			"resident_profile_editor.apply_wardrobe_result",
			_wardrobe_available,
			_wardrobe_error,
		),
		"saveExisting": _action(
			"resident_profile_editor.save_existing",
			valid,
			"RESIDENT_PROFILE_DRAFT_INVALID",
		),
		"cancel": _action("resident_profile_editor.cancel", true),
		"retry": _action(
			"resident_profile_editor.retry",
			false,
			"NO_RETRYABLE_ERROR",
		),
	}


func _load_wardrobe_catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(WARDROBE_CATALOG_PATH),
	)
	if not parsed is Dictionary:
		return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_MISSING")
	var parse_result := _parse_wardrobe_catalog(parsed as Dictionary)
	if not bool(parse_result.get("ok", false)):
		return _failure(
			String(parse_result.get(
				"errorCode",
				"RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID",
			)),
		)
	_wardrobe_by_appearance_id = (
		parse_result.get("appearances", {}) as Dictionary
	).duplicate(true)
	_wardrobe_by_selection.clear()
	_wardrobe_by_loadout_id.clear()
	_wardrobe_assignment_by_resident_id.clear()
	_wardrobe_alias_by_appearance_id.clear()
	for appearance_value: Variant in _wardrobe_by_appearance_id.values():
		if appearance_value is not Dictionary:
			continue
		var appearance := appearance_value as Dictionary
		var key := _selection_key(
			appearance.get("selection", {}) as Dictionary,
		)
		if key.is_empty() or _wardrobe_by_selection.has(key):
			_wardrobe_by_appearance_id.clear()
			_wardrobe_by_selection.clear()
			_wardrobe_by_loadout_id.clear()
			return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
		_wardrobe_by_selection[key] = appearance.duplicate(true)
		var loadout_id := String(appearance.get("loadoutId", "")).strip_edges()
		if loadout_id.is_empty() or _wardrobe_by_loadout_id.has(loadout_id):
			_wardrobe_by_appearance_id.clear()
			_wardrobe_by_selection.clear()
			_wardrobe_by_loadout_id.clear()
			return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
		_wardrobe_by_loadout_id[loadout_id] = appearance.duplicate(true)
	var catalog := parsed as Dictionary
	var assignments_value: Variant = catalog.get("residentAssignments", {})
	var aliases_value: Variant = catalog.get("legacyAppearanceAliases", {})
	if assignments_value is Dictionary:
		for resident_id_value: Variant in assignments_value:
			var resident_id := String(resident_id_value).strip_edges()
			var assigned_loadout_id := String(
				(assignments_value as Dictionary).get(resident_id_value, ""),
			).strip_edges()
			if (
				not resident_id.is_empty()
				and _wardrobe_by_loadout_id.has(assigned_loadout_id)
			):
				_wardrobe_assignment_by_resident_id[resident_id] = (
					assigned_loadout_id
				)
	if aliases_value is Dictionary:
		for appearance_id_value: Variant in aliases_value:
			var legacy_appearance_id := String(
				appearance_id_value,
			).strip_edges()
			var aliased_loadout_id := String(
				(aliases_value as Dictionary).get(appearance_id_value, ""),
			).strip_edges()
			if (
				not legacy_appearance_id.is_empty()
				and _wardrobe_by_loadout_id.has(aliased_loadout_id)
			):
				_wardrobe_alias_by_appearance_id[legacy_appearance_id] = (
					aliased_loadout_id
				)
	_wardrobe_available = not _wardrobe_by_selection.is_empty()
	_wardrobe_error = (
		""
		if _wardrobe_available
		else "RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID"
	)
	return {"ok": true, "errorCode": "", "retryable": false}


func _parse_wardrobe_catalog(catalog: Dictionary) -> Dictionary:
	var loadouts_value: Variant = catalog.get("loadouts")
	var head_ids := _wardrobe_catalog_entry_ids(catalog.get("heads"))
	var outfit_ids := _wardrobe_catalog_entry_ids(catalog.get("outfits"))
	if (
		_wardrobe_catalog_string(catalog, "schema") != WARDROBE_SCHEMA
		or catalog.get("directions") != WARDROBE_ALL_DIRECTIONS
		or loadouts_value is not Array
		or head_ids.is_empty()
		or outfit_ids.is_empty()
		or (loadouts_value as Array).size() != head_ids.size() * outfit_ids.size()
	):
		return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
	var appearances: Dictionary = {}
	var loadout_ids: Dictionary = {}
	var selections: Dictionary = {}
	for value: Variant in loadouts_value as Array:
		if not value is Dictionary:
			return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
		var loadout := value as Dictionary
		var loadout_id := _wardrobe_catalog_string(loadout, "id").strip_edges()
		var appearance_id := (
			_wardrobe_catalog_string(loadout, "appearanceId").strip_edges()
		)
		var expected_appearance_id := "resident_wardrobe_v1:%s" % loadout_id
		var head_id := _wardrobe_catalog_string(loadout, "headId").strip_edges()
		var outfit_id := (
			_wardrobe_catalog_string(loadout, "outfitId").strip_edges()
		)
		var portrait_path := _resource_path(
			_wardrobe_catalog_string(loadout, "portraitPath"),
		)
		var sprite_sheet_path := _resource_path(
			_wardrobe_catalog_string(loadout, "spriteSheetPath"),
		)
		var directions_value: Variant = loadout.get("directions")
		if directions_value is not Dictionary:
			return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
		var directions := directions_value as Dictionary
		if directions.size() != WARDROBE_SOURCE_DIRECTIONS.size():
			return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
		var direction_rest_paths: Dictionary = {}
		for direction_id: String in WARDROBE_SOURCE_DIRECTIONS:
			var direction_value: Variant = directions.get(direction_id)
			if direction_value is not Dictionary:
				return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
			var direction := direction_value as Dictionary
			var rest_path := _resource_path(
				_wardrobe_catalog_string(direction, "restPath"),
			)
			var expected_rest_path := (
				WARDROBE_ROOT
				+ "/loadouts/%s/%s/rest.png" % [loadout_id, direction_id]
			)
			if (
				rest_path != expected_rest_path
				or not ResourceLoader.exists(rest_path, "Texture2D")
			):
				return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
			direction_rest_paths[direction_id] = rest_path
		var selection := {
			"hair": head_id,
			"top": outfit_id,
			"bottom": outfit_id,
			"shoes": outfit_id,
		}
		var selection_key := "%s|%s" % [head_id, outfit_id]
		if (
			loadout_id.is_empty()
			or loadout_ids.has(loadout_id)
			or appearance_id != expected_appearance_id
			or not head_ids.has(head_id)
			or not outfit_ids.has(outfit_id)
			or selections.has(selection_key)
			or _wardrobe_catalog_string(loadout, "label").strip_edges().is_empty()
			or not portrait_path.begins_with(WARDROBE_ROOT + "/")
			or not ResourceLoader.exists(portrait_path, "Texture2D")
			or not sprite_sheet_path.begins_with(WARDROBE_ROOT + "/")
			or not ResourceLoader.exists(sprite_sheet_path, "Texture2D")
			or appearances.has(appearance_id)
		):
			return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
		loadout_ids[loadout_id] = true
		selections[selection_key] = true
		appearances[appearance_id] = {
			"appearanceId": appearance_id,
			"loadoutId": loadout_id,
			"displayName": _wardrobe_catalog_string(loadout, "label"),
			"selection": selection.duplicate(true),
			"portraitPath": portrait_path,
			"spriteSheetPath": sprite_sheet_path,
			"restPath": String(direction_rest_paths.get("down", "")),
			"formalReady": true,
			"directionSetReady": true,
		}
	if appearances.is_empty():
		return _failure("RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID")
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"appearances": appearances,
	}


func _wardrobe_catalog_string(source: Dictionary, key: String) -> String:
	var value: Variant = source.get(key)
	if value is not String:
		return ""
	return value as String


func _wardrobe_catalog_entry_ids(value: Variant) -> Dictionary:
	if value is not Array or (value as Array).is_empty():
		return {}
	var ids: Dictionary = {}
	for entry_value: Variant in value as Array:
		if entry_value is not Dictionary:
			return {}
		var entry := entry_value as Dictionary
		var entry_id := _wardrobe_catalog_string(entry, "id").strip_edges()
		if entry_id.is_empty() or ids.has(entry_id):
			return {}
		ids[entry_id] = true
	return ids


func _occupation_options(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _normalized_options(values):
		result.append({
			"id": "occupation:%s" % String(item.get("label", "")),
			"label": String(item.get("label", "")),
		})
	return result


func _workplace_for_occupation(occupation_label: String) -> String:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(OCCUPATION_CATALOG_PATH),
	)
	if not parsed is Dictionary:
		return ""
	for value: Variant in (parsed as Dictionary).get("occupations", []) as Array:
		if (
			value is Dictionary
			and String((value as Dictionary).get("occupationName", ""))
				== occupation_label
		):
			return String(
				(value as Dictionary).get("primaryWorkplacePlace", ""),
			)
	return ""


func _normalized_options(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for value: Variant in values:
		var label := (
			String((value as Dictionary).get("label", ""))
			if value is Dictionary
			else String(value)
		).strip_edges()
		if label.is_empty() or seen.has(label):
			continue
		seen[label] = true
		result.append({"id": label, "label": label})
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("label", "")) < String(right.get("label", ""))
	)
	return result


func _selection_key(selection: Dictionary) -> String:
	var parts := PackedStringArray()
	for slot_id: String in WARDROBE_SLOTS:
		var variant_id := String(selection.get(slot_id, "")).strip_edges()
		if variant_id.is_empty():
			return ""
		parts.append("%s=%s" % [slot_id, variant_id])
	return "|".join(parts)


func _option_has_id(values: Array, option_id: String) -> bool:
	for value: Variant in values:
		if (
			value is Dictionary
			and String((value as Dictionary).get("id", "")) == option_id
		):
			return true
	return false


func _add_issue(
	field: String,
	code: String,
	message: String,
	issues: Array[Dictionary],
	field_issues: Dictionary,
) -> void:
	var issue := {
		"field": field,
		"code": code,
		"message": message,
	}
	issues.append(issue)
	field_issues[field] = issue.duplicate(true)


func _publish(
	request_id: String,
	intent: String,
	result: Dictionary,
) -> Dictionary:
	var ok := bool(result.get("ok", false))
	var retryable := bool(result.get("retryable", false))
	_operation = {
		"requestId": request_id,
		"intent": intent,
		"status": "success" if ok else ("error" if retryable else "rejected"),
		"submittedAtMsec": Time.get_ticks_msec(),
		"completedAtMsec": Time.get_ticks_msec(),
	}
	_error = null if ok else {
		"kind": "transport" if retryable else "validation",
		"code": String(result.get(
			"errorCode",
			"RESIDENT_PROFILE_EDITOR_REJECTED",
		)),
		"retryable": retryable,
		"message": _error_message(String(result.get("errorCode", ""))),
		"details": (result.get("errors", []) as Array).duplicate(true),
	}
	_revision += 1
	var view_model := get_view_model()
	view_model_changed.emit(SCOPE, view_model)
	operation_completed.emit(SCOPE, _operation.duplicate(true))
	var response := _dispatch_result(
		ok,
		true,
		request_id,
		String(result.get("errorCode", "")),
		retryable,
		bool(result.get("changed", false)),
	)
	for key in ["wardrobeHandoff", "resolvedAppearance"]:
		if result.has(key):
			response[key] = (
				(result[key] as Dictionary).duplicate(true)
				if result[key] is Dictionary
				else result[key]
			)
	return response


func _configuration_failure(error_code: String) -> Dictionary:
	_configuration_error = error_code
	_error = {
		"kind": "unavailable",
		"code": error_code,
		"retryable": false,
		"message": _error_message(error_code),
		"details": [],
	}
	return _failure(error_code)


func _disabled_view_model() -> Dictionary:
	var action_keys := {
		"updateFields": "resident_profile_editor.update_fields",
		"openWardrobe": "resident_profile_editor.open_wardrobe",
		"applyWardrobeResult": "resident_profile_editor.apply_wardrobe_result",
		"saveExisting": "resident_profile_editor.save_existing",
		"cancel": "resident_profile_editor.cancel",
		"retry": "resident_profile_editor.retry",
	}
	var actions := {}
	for key: Variant in action_keys:
		actions[key] = _action(
			String(action_keys[key]),
			false,
			_configuration_error,
		)
	return {
		"scope": SCOPE,
		"status": "disabled",
		"revision": _revision,
		"data": {
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": false,
			"residentId": _resident_id,
			"draftId": "",
			"candidatePoolRevision": 0,
			"draft": {},
			"resolvedAppearance": {},
			"options": {
				"genders": [],
				"age": {"min": 1, "max": 120, "step": 1},
				"interests": [],
				"maxInterests": INTERESTS.max_interests(),
				"wardrobe": {
					"entryMode": "route_to_formal_wardrobe",
					"catalogPath": WARDROBE_CATALOG_PATH,
					"schema": "ai-town.resident-wardrobe.v1",
					"runtimeMode": "resident_2d_rig_v1",
					"slotOrder": WARDROBE_SLOTS.duplicate(),
				},
				"occupations": [],
				"workplaces": [],
				"ownedPlaces": [],
			},
			"validation": {
				"status": "unavailable",
				"summaryLabel": "居民资料尚未读取",
				"issues": [],
				"fieldIssues": {},
			},
		},
		"actions": actions,
		"operation": _operation.duplicate(true),
		"error": (
			_error
			if _error is Dictionary
			else {
				"kind": "unavailable",
				"code": _configuration_error,
				"retryable": false,
				"message": _error_message(_configuration_error),
				"details": [],
			}
		),
	}


func _resource_path(path: String) -> String:
	if path.is_empty() or path.begins_with("res://"):
		return path
	return "res://" + path


func _next_request_id() -> String:
	_request_sequence += 1
	return AiTownUiViewModel.request_id("resident-profile", _request_sequence)


func _action(intent: String, enabled: bool, disabled_reason := "") -> Dictionary:
	return AiTownUiViewModel.make_action(intent, enabled, disabled_reason)


func _success(changed: bool) -> Dictionary:
	return RESULT_SHAPES.success_changed(changed)


func _failure(error_code: String, errors: Array = []) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"errors": errors.duplicate(true),
		"changed": false,
	}


func _dispatch_result(
	ok: bool,
	accepted: bool,
	request_id: String,
	error_code: String,
	retryable := false,
	changed := false,
) -> Dictionary:
	return {
		"ok": ok,
		"accepted": accepted,
		"requestId": request_id,
		"errorCode": error_code,
		"retryable": retryable,
		"changed": changed,
	}


func _idle_operation() -> Dictionary:
	return AiTownUiViewModel.idle_operation()


func _error_message(error_code: String) -> String:
	return {
		"RESIDENT_IDENTITY_NOT_FOUND": "没有找到这位居民，请返回总览重新选择。",
			"RESIDENT_PROFILE_APPEARANCE_READ_ONLY": "本局居民外观暂时保持只读。",
			"RESIDENT_PROFILE_WARDROBE_CATALOG_MISSING": "正式衣柜资料暂不可用，其他居民资料仍可保存。",
			"RESIDENT_PROFILE_WARDROBE_CATALOG_INVALID": "正式衣柜资料暂不可用，其他居民资料仍可保存。",
			"RESIDENT_PROFILE_APPEARANCE_NOT_READY": "当前外观暂时不能进入衣柜。",
			"RESIDENT_PROFILE_APPEARANCE_SELECTION_INVALID": "这套外观没有通过正式衣柜检查。",
		"RESIDENT_PROFILE_DRAFT_INVALID": "请先补全居民资料。",
		"RESIDENT_PROFILE_EDITOR_REVISION_STALE": "资料已经更新，请按当前内容继续。",
		"RESIDENT_PROFILE_HOME_UNKNOWN": "请选择本局可用住所。",
		"RESIDENT_PROFILE_WORKPLACE_UNKNOWN": "请选择本局可用工作地点。",
		"RESIDENT_PROFILE_OCCUPATION_UNKNOWN": "请选择本局可用职业。",
	}.get(error_code, "居民资料没有保存，当前填写内容已保留。")
