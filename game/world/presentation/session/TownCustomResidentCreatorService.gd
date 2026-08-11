class_name TownCustomResidentCreatorService
extends RefCounted


signal view_model_changed(scope: String, view_model: Dictionary)
signal candidate_created(result: Dictionary)


const WHITEBODY_RIG := preload("res://world/presentation/residents/ResidentFrozenWhitebodyRig.gd")
const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const UI_VIEW_MODEL := preload(
	"res://ui/common/AiTownUiViewModel.gd"
)
const CATALOG := preload("res://world/presentation/session/TownResidentCatalog.gd")
const INTERESTS := preload(
	"res://world/data/town/TownInterestCatalog.gd"
)
const SCOPE := "custom_resident_creator"
const WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)
const WARDROBE_SLOTS: Array[String] = [
	"hair",
	"top",
	"bottom",
	"shoes",
]
const INTENT_TO_ACTION := {
	"custom_resident_creator.update_fields": "updateFields",
	"custom_resident_creator.open_wardrobe": "openWardrobe",
	"custom_resident_creator.apply_wardrobe_result": "applyWardrobeResult",
	"custom_resident_creator.create": "create",
	"custom_resident_creator.cancel": "cancel",
	"custom_resident_creator.retry": "retry",
}
const EDITABLE_FIELDS: Array[String] = [
	"name",
	"gender",
	"age",
	"desire",
	"personality",
	"speech",
	"interests",
	"customInterests",
	"occupationId",
]


var _candidate_pool: Object
var _base_catalog: Dictionary = {}
var _world_data: Dictionary = {}
var _configured := false
var _revision := 0
var _request_sequence := 0
var _draft_id := ""
var _draft: Dictionary = {}
var _wardrobe_catalog: Dictionary = {}
var _wardrobe_by_loadout_id: Dictionary = {}
var _wardrobe_by_selection: Dictionary = {}
var _occupation_options: Array[Dictionary] = []
var _occupation_by_id: Dictionary = {}
var _workplace_options: Array[Dictionary] = []
var _workplace_by_id: Dictionary = {}
var _operation := _idle_operation()
var _error: Variant = null
var _configuration_error := "CUSTOM_RESIDENT_CREATOR_NOT_CONFIGURED"


func configure(
	candidate_pool: Object,
	base_catalog: Dictionary,
	world_data: Dictionary,
	context: Dictionary = {},
) -> Dictionary:
	_reset()
	if candidate_pool == null:
		return _configuration_failure("CUSTOM_RESIDENT_CANDIDATE_POOL_NOT_BOUND")
	for method in [
		"candidate_pool_revision",
		"create_candidate",
		"resident_name_available",
	]:
		if not candidate_pool.has_method(method):
			return _configuration_failure("CUSTOM_RESIDENT_CANDIDATE_POOL_CONTRACT_INVALID")
	var catalog_validation := CATALOG.validate(base_catalog) as Dictionary
	if not bool(catalog_validation.get("ok", false)):
		return _configuration_failure(String(catalog_validation.get(
			"errorCode",
			"CUSTOM_RESIDENT_CREATOR_CATALOG_INVALID",
		)))
	if world_data.is_empty() or not world_data.get("places") is Array:
		return _configuration_failure("CUSTOM_RESIDENT_CREATOR_WORLD_DATA_INVALID")
	_candidate_pool = candidate_pool
	_base_catalog = base_catalog.duplicate(true)
	_world_data = world_data.duplicate(true)
	var wardrobe_result := _build_wardrobe_options()
	if not bool(wardrobe_result.get("ok", false)):
		return _configuration_failure(String(wardrobe_result.get(
			"errorCode",
			"CUSTOM_RESIDENT_WARDROBE_NOT_READY",
		)))
	_build_work_options()
	if _occupation_options.is_empty() or _workplace_options.is_empty():
		return _configuration_failure("CUSTOM_RESIDENT_CREATOR_OPTIONS_INCOMPLETE")
	var default_selection := _default_wardrobe_selection()
	if default_selection.is_empty():
		return _configuration_failure("CUSTOM_RESIDENT_WARDROBE_NOT_READY")
	var first_occupation := _occupation_options[0]
	_draft = {
		"name": "",
		"gender": "女",
		"age": 27,
		"appearanceSelection": default_selection,
		"desire": "",
		"personality": "",
		"speech": "",
		"interests": [],
		"customInterests": [],
		"occupationId": String(first_occupation.get("id", "")),
		"workplaceId": String(first_occupation.get("defaultWorkplaceId", "")),
		"relatedWorkplaceIds": (
			first_occupation.get(
				"relatedWorkplaceIds",
				[],
			) as Array
		).duplicate(),
	}
	var initial_source_value: Variant = context.get("initialSource", {})
	if initial_source_value is Dictionary and not (initial_source_value as Dictionary).is_empty():
		var initial_result := _apply_initial_source(
			initial_source_value as Dictionary,
		)
		if not bool(initial_result.get("ok", false)):
			return _configuration_failure(String(initial_result.get(
				"errorCode",
				"CUSTOM_RESIDENT_INITIAL_SOURCE_INVALID",
			)))
	_draft_id = String(context.get("draftId", "")).strip_edges()
	if _draft_id.is_empty():
		_draft_id = "custom-resident-%d" % Time.get_ticks_msec()
	_revision = maxi(int(context.get("revision", 1)), 1)
	_configured = true
	_configuration_error = ""
	_emit_view_model()
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"revision": _revision,
		"candidatePoolRevision": int(_candidate_pool.call("candidate_pool_revision")),
		"draftId": _draft_id,
	}


func _apply_initial_source(source: Dictionary) -> Dictionary:
	var attributes_value: Variant = source.get("attributes", {})
	if not attributes_value is Dictionary:
		return _failure("CUSTOM_RESIDENT_INITIAL_SOURCE_INVALID")
	var attributes := attributes_value as Dictionary
	var social_value: Variant = source.get("socialState", {})
	var social := social_value as Dictionary if social_value is Dictionary else {}
	var appearance_id := String(attributes.get("appearance", "")).strip_edges()
	var appearance_selection: Dictionary = {}
	for loadout_value: Variant in _wardrobe_by_loadout_id.values():
		if not loadout_value is Dictionary:
			continue
		var appearance := _appearance_from_loadout(loadout_value as Dictionary)
		if String(appearance.get("appearanceId", "")) == appearance_id:
			appearance_selection = (
				appearance.get("selection", {}) as Dictionary
			).duplicate(true)
			break
	if appearance_selection.is_empty():
		return _failure("CUSTOM_RESIDENT_APPEARANCE_NOT_READY")
	var occupation_label := String(social.get("job", "")).strip_edges()
	var occupation_id := ""
	var workplace_id := ""
	var related_workplace_ids: Array = []
	for option_value: Variant in _occupation_options:
		var option := option_value as Dictionary
		if String(option.get("label", "")) != occupation_label:
			continue
		occupation_id = String(option.get("id", ""))
		workplace_id = String(option.get("defaultWorkplaceId", ""))
		related_workplace_ids = (
			option.get("relatedWorkplaceIds", []) as Array
		).duplicate()
		break
	if occupation_id.is_empty():
		return _failure("CUSTOM_RESIDENT_OCCUPATION_UNKNOWN")
	_draft = {
		"name": String(attributes.get("name", "")).strip_edges(),
		"gender": String(attributes.get("gender", "女")),
		"age": int(attributes.get("age", 27)),
		"appearanceSelection": appearance_selection,
		"desire": String(attributes.get("desire", "")).strip_edges(),
		"personality": String(attributes.get("personality", "")).strip_edges(),
		"speech": String(attributes.get("speech", "")).strip_edges(),
		"interests": INTERESTS.normalize(attributes.get("interests", [])),
		"customInterests": INTERESTS.normalize_custom(
			attributes.get("customInterests", []),
		),
		"occupationId": occupation_id,
		"workplaceId": workplace_id,
		"relatedWorkplaceIds": related_workplace_ids,
	}
	return {"ok": true, "errorCode": "", "retryable": false}


func get_view_model() -> Dictionary:
	if not _configured:
		return _disabled_view_model()
	var validation := _validate_draft()
	return {
		"scope": SCOPE,
		"status": "error" if String(_operation.get("status", "")) == "error" else "ready",
		"revision": _revision,
		"data": _data_snapshot(validation),
		"actions": _actions_snapshot(validation),
		"operation": _operation.duplicate(true),
		"error": null if _error == null else (_error as Dictionary).duplicate(true),
	}


func dispatch(intent: String, payload: Dictionary = {}) -> Dictionary:
	var action_key := String(INTENT_TO_ACTION.get(intent, ""))
	var request_id := _next_request_id()
	if action_key.is_empty():
		return _dispatch_result(
			false,
			false,
			request_id,
			"UNKNOWN_CUSTOM_RESIDENT_CREATOR_INTENT",
			false,
		)
	if not _configured:
		return _dispatch_result(false, false, request_id, _configuration_error, false)
	if int(payload.get("revision", -1)) != _revision:
		return _publish_result(
			request_id,
			intent,
			_failure("CUSTOM_RESIDENT_CREATOR_REVISION_STALE"),
		)
	if String(payload.get("draftId", "")) != _draft_id:
		return _publish_result(
			request_id,
			intent,
			_failure("CUSTOM_RESIDENT_CREATOR_DRAFT_MISMATCH"),
		)
	var action := (_actions_snapshot(_validate_draft()).get(action_key, {}) as Dictionary)
	if not bool(action.get("enabled", false)):
		return _publish_result(
			request_id,
			intent,
			_failure(String(action.get(
				"disabledReason",
				"CUSTOM_RESIDENT_CREATOR_ACTION_DISABLED",
			))),
		)
	var result: Dictionary
	match intent:
		"custom_resident_creator.update_fields":
			var fields_value: Variant = payload.get("fields", {})
			result = (
				_update_fields(fields_value as Dictionary)
				if fields_value is Dictionary
				else _failure("CUSTOM_RESIDENT_FIELDS_INVALID")
			)
		"custom_resident_creator.open_wardrobe":
			result = _open_wardrobe()
		"custom_resident_creator.apply_wardrobe_result":
			var selection_value: Variant = payload.get("selection", {})
			result = (
				_apply_wardrobe_result(selection_value as Dictionary)
				if selection_value is Dictionary
				else _failure("CUSTOM_RESIDENT_APPEARANCE_SELECTION_INVALID")
			)
		"custom_resident_creator.create":
			result = _create_candidate(int(payload.get("candidatePoolRevision", -1)))
		"custom_resident_creator.cancel":
			result = _success(false)
		"custom_resident_creator.retry":
			result = _failure("NO_RETRYABLE_ERROR")
		_:
			result = _failure("UNKNOWN_CUSTOM_RESIDENT_CREATOR_INTENT")
	return _publish_result(request_id, intent, result)


func _update_fields(fields: Dictionary) -> Dictionary:
	if fields.is_empty():
		return _failure("CUSTOM_RESIDENT_FIELDS_REQUIRED")
	var next := _draft.duplicate(true)
	for key_value: Variant in fields:
		var key := String(key_value)
		if key not in EDITABLE_FIELDS:
			return _failure("CUSTOM_RESIDENT_FIELD_UNKNOWN")
		match key:
			"age":
				var age := int(fields[key])
				if age < 1 or age > 120:
					return _failure("CUSTOM_RESIDENT_AGE_INVALID")
				next[key] = age
			"gender":
				var gender := String(fields[key])
				if gender not in ["男", "女"]:
					return _failure("CUSTOM_RESIDENT_GENDER_INVALID")
				next[key] = gender
			"occupationId":
				var occupation_id := String(fields[key])
				if not _occupation_by_id.has(occupation_id):
					return _failure("CUSTOM_RESIDENT_OCCUPATION_UNKNOWN")
				var option := _occupation_by_id[occupation_id] as Dictionary
				next[key] = occupation_id
				next["workplaceId"] = String(option.get("defaultWorkplaceId", ""))
				next["relatedWorkplaceIds"] = (
					option.get(
						"relatedWorkplaceIds",
						[],
					) as Array
				).duplicate()
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


func _open_wardrobe() -> Dictionary:
	var appearance := _resolved_appearance()
	if appearance.is_empty() or not bool(appearance.get("formalReady", false)):
		return _failure("CUSTOM_RESIDENT_APPEARANCE_NOT_READY")
	var result := _success(false)
	result["wardrobeHandoff"] = {
		"sourceScope": SCOPE,
		"draftId": _draft_id,
		"returnRevision": _revision + 1,
		"returnIntent": "custom_resident_creator.apply_wardrobe_result",
		"cancelIntent": "custom_resident_creator.wardrobe_cancelled",
		"runtimeMode": "resident_2d_rig_v1",
		"catalogPath": WARDROBE_CATALOG_PATH,
		"slotOrder": WARDROBE_SLOTS.duplicate(),
		"selection": (appearance.get("selection", {}) as Dictionary).duplicate(true),
		"loadoutId": String(appearance.get("loadoutId", "")),
		"portraitPath": String(appearance.get("portraitPath", "")),
		"spriteSheetPath": String(appearance.get("spriteSheetPath", "")),
		"restPath": String(appearance.get("restPath", "")),
	}
	return result


func _apply_wardrobe_result(selection: Dictionary) -> Dictionary:
	var loadout := _resolve_wardrobe_selection(selection)
	if loadout.is_empty():
		return _failure("CUSTOM_RESIDENT_APPEARANCE_NOT_READY")
	var appearance := _appearance_from_loadout(loadout)
	if (
		appearance.is_empty()
		or not bool(appearance.get("formalReady", false))
		or not bool(appearance.get("directionSetReady", false))
	):
		return _failure("CUSTOM_RESIDENT_APPEARANCE_NOT_READY")
	var normalized := (appearance.get("selection", {}) as Dictionary).duplicate(true)
	var changed := normalized != (_draft.get("appearanceSelection", {}) as Dictionary)
	_draft["appearanceSelection"] = normalized
	var result := _success(changed)
	result["resolvedAppearance"] = appearance.duplicate(true)
	return result


func _create_candidate(expected_pool_revision: int) -> Dictionary:
	var validation := _validate_draft()
	if String(validation.get("status", "invalid")) != "valid":
		return _failure(
			"CUSTOM_RESIDENT_DRAFT_INVALID",
			validation.get("issues", []) as Array,
		)
	var result := _candidate_pool.call(
		"create_candidate",
		_candidate_source(),
		expected_pool_revision,
	) as Dictionary
	if bool(result.get("ok", false)):
		candidate_created.emit(result.duplicate(true))
	return result


func _candidate_source() -> Dictionary:
	var appearance := _resolved_appearance()
	var occupation := _occupation_by_id.get(
		String(_draft.get("occupationId", "")),
		{},
	) as Dictionary
	var workplace := _workplace_by_id.get(
		String(_draft.get("workplaceId", "")),
		{},
	) as Dictionary
	var personality := String(_draft.get("personality", "")).strip_edges()
	return {
		"source": "custom",
		"attributes": {
			"name": String(_draft.get("name", "")).strip_edges(),
			"gender": String(_draft.get("gender", "")),
			"age": int(_draft.get("age", 0)),
			"appearance": String(appearance.get("appearanceId", "")),
			"desire": String(_draft.get("desire", "")).strip_edges(),
			"personality": personality,
			"speech": String(_draft.get("speech", "")).strip_edges(),
			"interests": INTERESTS.normalize(
				_draft.get("interests", []),
			),
			"customInterests": INTERESTS.normalize_custom(
				_draft.get("customInterests", []),
			),
			"selectionSummary": _selection_summary_from_personality(personality),
		},
		"appearance": appearance,
		"occupation": {
			"name": String(occupation.get("label", "")),
			"workplacePlace": String(workplace.get("label", "")),
		},
		"presentation": {
			"spritePath": String(appearance.get("legacySpritePath", "")),
			"portraitPath": String(appearance.get("portraitPath", "")),
			"locationLabel": String(workplace.get("label", "")),
		},
	}


func _selection_summary_from_personality(personality: String) -> String:
	var normalized := personality.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return normalized.strip_edges().left(24)


func _validate_draft() -> Dictionary:
	var issues: Array[Dictionary] = []
	var field_issues: Dictionary = {}
	_validate_text("name", 24, issues, field_issues)
	var resident_name := String(_draft.get("name", "")).strip_edges()
	if (
		not resident_name.is_empty()
		and _candidate_pool != null
		and not bool(_candidate_pool.call("resident_name_available", resident_name))
	):
		_add_issue(
			"name",
			"CUSTOM_RESIDENT_NAME_DUPLICATED",
			"这个名字已经被其他居民使用。",
			issues,
			field_issues,
		)
	if String(_draft.get("gender", "")) not in ["男", "女"]:
		_add_issue(
			"gender",
			"CUSTOM_RESIDENT_GENDER_INVALID",
			"性别仅支持男或女。",
			issues,
			field_issues,
		)
	var age := int(_draft.get("age", 0))
	if age < 1 or age > 120:
		_add_issue(
			"age",
			"CUSTOM_RESIDENT_AGE_INVALID",
			"年龄需在 1 到 120 岁之间。",
			issues,
			field_issues,
		)
	for field in ["desire", "personality", "speech"]:
		_validate_text(field, 240, issues, field_issues)
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
	var appearance := _resolved_appearance()
	if (
		appearance.is_empty()
		or not bool(appearance.get("formalReady", false))
		or not bool(appearance.get("directionSetReady", false))
	):
		_add_issue(
			"appearanceSelection",
			"CUSTOM_RESIDENT_APPEARANCE_NOT_READY",
			"当前衣柜搭配没有可用的正式方向图集。",
			issues,
			field_issues,
		)
	if not _occupation_by_id.has(String(_draft.get("occupationId", ""))):
		_add_issue(
			"occupationId",
			"CUSTOM_RESIDENT_OCCUPATION_UNKNOWN",
			"请选择职业。",
			issues,
			field_issues,
		)
	if not _workplace_by_id.has(String(_draft.get("workplaceId", ""))):
		_add_issue(
			"workplaceId",
			"CUSTOM_RESIDENT_WORKPLACE_UNKNOWN",
			"请选择工作地。",
			issues,
			field_issues,
		)
	else:
		var selected_occupation := _occupation_by_id.get(
			String(_draft.get("occupationId", "")),
			{},
		) as Dictionary
		if (
			not selected_occupation.is_empty()
			and (
				String(_draft.get("workplaceId", ""))
					!= String(selected_occupation.get(
						"defaultWorkplaceId",
						"",
					))
				or _draft.get("relatedWorkplaceIds", [])
					!= selected_occupation.get(
						"relatedWorkplaceIds",
						[],
					)
			)
		):
			_add_issue(
				"workplaceId",
				"CUSTOM_RESIDENT_WORKPLACE_NOT_DERIVED",
				"工作范围必须由职业规则生成。",
				issues,
				field_issues,
			)
	return {
		"status": "valid" if issues.is_empty() else "invalid",
		"summaryLabel": "资料完整，可以创建" if issues.is_empty() else "请完成所有必填资料",
		"issues": issues,
		"fieldIssues": field_issues,
	}


func _validate_text(
	field: String,
	maximum: int,
	issues: Array[Dictionary],
	field_issues: Dictionary,
) -> void:
	var value := String(_draft.get(field, "")).strip_edges()
	if value.is_empty():
		_add_issue(
			field,
			"CUSTOM_RESIDENT_%s_REQUIRED" % field.to_upper(),
			"此项不能为空。",
			issues,
			field_issues,
		)
	elif value.length() > maximum:
		_add_issue(
			field,
			"CUSTOM_RESIDENT_%s_TOO_LONG" % field.to_upper(),
			"此项不能超过 %d 个字。" % maximum,
			issues,
			field_issues,
		)


func _add_issue(
	field: String,
	code: String,
	message: String,
	issues: Array[Dictionary],
	field_issues: Dictionary,
) -> void:
	var issue := {"field": field, "code": code, "message": message}
	issues.append(issue)
	field_issues[field] = issue.duplicate(true)


func _data_snapshot(validation: Dictionary) -> Dictionary:
	return {
		"capabilityMode": "formal",
		"source": "runtime",
		"formalReady": true,
		"draftId": _draft_id,
		"candidatePoolRevision": int(_candidate_pool.call("candidate_pool_revision")),
		"editableFields": EDITABLE_FIELDS.duplicate(),
		"draft": _draft.duplicate(true),
		"resolvedAppearance": _resolved_appearance(),
		"options": {
			"genders": [{"id": "女", "label": "女"}, {"id": "男", "label": "男"}],
			"age": {"min": 1, "max": 120, "step": 1},
			"interests": INTERESTS.options(),
			"maxInterests": INTERESTS.max_interests(),
			"wardrobe": {
				"entryMode": "route_to_formal_wardrobe",
				"catalogPath": WARDROBE_CATALOG_PATH,
				"schema": String(_wardrobe_catalog.get("schema", "")),
				"revision": String(_wardrobe_catalog.get("revision", "")),
				"runtimeMode": "resident_2d_rig_v1",
				"slotOrder": WARDROBE_SLOTS.duplicate(),
			},
			"occupations": _occupation_options.duplicate(true),
			"workplaces": _workplace_options.duplicate(true),
		},
		"validation": validation.duplicate(true),
	}


func _actions_snapshot(validation: Dictionary) -> Dictionary:
	var valid := String(validation.get("status", "invalid")) == "valid"
	var retryable := _error is Dictionary and bool((_error as Dictionary).get("retryable", false))
	return {
		"updateFields": _action("custom_resident_creator.update_fields", true),
		"openWardrobe": _action(
			"custom_resident_creator.open_wardrobe",
			bool(_resolved_appearance().get("formalReady", false)),
			"CUSTOM_RESIDENT_APPEARANCE_NOT_READY",
		),
		"applyWardrobeResult": _action(
			"custom_resident_creator.apply_wardrobe_result",
			true,
		),
		"create": _action(
			"custom_resident_creator.create",
			valid,
			"CUSTOM_RESIDENT_DRAFT_INVALID",
		),
		"cancel": _action("custom_resident_creator.cancel", true),
		"retry": _action(
			"custom_resident_creator.retry",
			retryable,
			"NO_RETRYABLE_ERROR",
		),
	}


func _build_wardrobe_options() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(WARDROBE_CATALOG_PATH)
	)
	if not parsed is Dictionary:
		return _failure("CUSTOM_RESIDENT_WARDROBE_CATALOG_MISSING")
	var catalog := parsed as Dictionary
	if (
		String(catalog.get("schema", "")) != "ai-town.resident-wardrobe.v1"
		or not _wardrobe_canvas_valid(catalog.get("canvasSize"))
		or catalog.get("directions", []) != ["down", "right", "up", "left"]
		or not catalog.get("loadouts") is Array
		or (catalog.get("loadouts", []) as Array).size() != 16
	):
		return _failure("CUSTOM_RESIDENT_WARDROBE_CATALOG_INVALID")
	_wardrobe_catalog = catalog.duplicate(true)
	for loadout_value: Variant in catalog.get("loadouts", []) as Array:
		if not loadout_value is Dictionary:
			return _failure("CUSTOM_RESIDENT_WARDROBE_CATALOG_INVALID")
		var loadout := (loadout_value as Dictionary).duplicate(true)
		var loadout_id := String(loadout.get("id", "")).strip_edges()
		var head_id := String(loadout.get("headId", "")).strip_edges()
		var outfit_id := String(loadout.get("outfitId", "")).strip_edges()
		if (
			loadout_id.is_empty()
			or head_id.is_empty()
			or outfit_id.is_empty()
			or _wardrobe_by_loadout_id.has(loadout_id)
		):
			return _failure("CUSTOM_RESIDENT_WARDROBE_CATALOG_INVALID")
		var selection := {
			"hair": head_id,
			"top": outfit_id,
			"bottom": outfit_id,
			"shoes": outfit_id,
		}
		loadout["loadoutId"] = loadout_id
		loadout["displayName"] = String(
			loadout.get("label", "小镇居民搭配"),
		).strip_edges()
		loadout["selection"] = selection
		var key := _selection_key(selection)
		if key.is_empty() or _wardrobe_by_selection.has(key):
			return _failure("CUSTOM_RESIDENT_WARDROBE_CATALOG_INVALID")
		_wardrobe_by_loadout_id[loadout_id] = loadout
		_wardrobe_by_selection[key] = loadout
	if _wardrobe_by_selection.size() != 16:
		return _failure("CUSTOM_RESIDENT_WARDROBE_NOT_READY")
	return {"ok": true, "errorCode": "", "retryable": false}


func _wardrobe_canvas_valid(value: Variant) -> bool:
	return WHITEBODY_RIG.wardrobe_canvas_valid(value)


func _build_work_options() -> void:
	for place_value: Variant in _world_data.get("places", []) as Array:
		if not place_value is Dictionary:
			continue
		var place := place_value as Dictionary
		var place_name := String(place.get("name", "")).strip_edges()
		if place_name.is_empty():
			continue
		var workplace := {"id": place_name, "label": place_name}
		_workplace_options.append(workplace)
		_workplace_by_id[place_name] = workplace
	for occupation_value: Variant in _world_data.get(
		"occupations",
		[],
	) as Array:
		if not occupation_value is Dictionary:
			continue
		var source := occupation_value as Dictionary
		var occupation_id := String(
			source.get("occupationId", ""),
		).strip_edges()
		var label := String(source.get("label", "")).strip_edges()
		var primary_workplace := String(
			source.get("primaryWorkplacePlace", ""),
		).strip_edges()
		var related_workplaces := (
			source.get("relatedWorkplacePlaces", []) as Array
		).duplicate()
		if (
			occupation_id.is_empty()
			or label.is_empty()
			or not _workplace_by_id.has(primary_workplace)
		):
			continue
		var related_labels: Array[String] = []
		for related_value: Variant in related_workplaces:
			var related_place := String(related_value)
			if _workplace_by_id.has(related_place):
				related_labels.append(related_place)
		var occupation := {
			"id": occupation_id,
			"label": label,
			"defaultWorkplaceId": primary_workplace,
			"primaryWorkplaceLabel": primary_workplace,
			"relatedWorkplaceIds": related_labels.duplicate(),
			"relatedWorkplaceLabels": related_labels.duplicate(),
			"dynamicWorkTargetRules": (
				source.get(
					"dynamicWorkTargetRules",
					[],
				) as Array
			).duplicate(),
			"fixedWorkAreaIds": (
				source.get(
					"fixedWorkAreaIds",
					[],
				) as Array
			).duplicate(),
		}
		_occupation_options.append(occupation)
		_occupation_by_id[occupation_id] = occupation
	_occupation_options.sort_custom(_option_before)
	_workplace_options.sort_custom(_option_before)


func _default_wardrobe_selection() -> Dictionary:
	var loadouts := _wardrobe_catalog.get("loadouts", []) as Array
	var default_id := (
		String((loadouts[0] as Dictionary).get("id", ""))
		if not loadouts.is_empty() and loadouts[0] is Dictionary
		else ""
	)
	var default_loadout := _wardrobe_by_loadout_id.get(default_id, {}) as Dictionary
	if not default_loadout.is_empty():
		var default_selection := default_loadout.get("selection", {}) as Dictionary
		if bool(_appearance_from_loadout(default_loadout).get("formalReady", false)):
			return default_selection.duplicate(true)
	for loadout_value: Variant in _wardrobe_by_loadout_id.values():
		var loadout := loadout_value as Dictionary
		if bool(_appearance_from_loadout(loadout).get("formalReady", false)):
			return (loadout.get("selection", {}) as Dictionary).duplicate(true)
	return {}


func _resolved_appearance() -> Dictionary:
	var selection_value: Variant = _draft.get("appearanceSelection", {})
	if not selection_value is Dictionary:
		return {}
	var loadout := _resolve_wardrobe_selection(selection_value as Dictionary)
	return _appearance_from_loadout(loadout) if not loadout.is_empty() else {}


func _resolve_wardrobe_selection(selection: Dictionary) -> Dictionary:
	var key := _selection_key(selection)
	return (_wardrobe_by_selection.get(key, {}) as Dictionary).duplicate(true)


func _appearance_from_loadout(loadout: Dictionary) -> Dictionary:
	if loadout.is_empty():
		return {}
	var loadout_id := String(loadout.get("loadoutId", ""))
	var portrait_path := _resource_path(String(loadout.get("portraitPath", "")))
	var sprite_sheet_path := _resource_path(
		String(loadout.get("spriteSheetPath", "")),
	)
	var directions_value: Variant = loadout.get("directions")
	var directions := (
		directions_value as Dictionary
		if directions_value is Dictionary
		else {}
	)
	var down_value: Variant = directions.get("down")
	var down := down_value as Dictionary if down_value is Dictionary else {}
	var rest_path := _resource_path(String(down.get("restPath", "")))
	var legacy_sprite_path := _legacy_sprite_path_for_appearance(loadout_id)
	var ready := (
		not loadout_id.is_empty()
		and not String(loadout.get("displayName", "")).is_empty()
		and ResourceLoader.exists(portrait_path, "Texture2D")
		and ResourceLoader.exists(rest_path, "Texture2D")
		and ResourceLoader.exists(sprite_sheet_path, "Texture2D")
		and ResourceLoader.exists(legacy_sprite_path, "Texture2D")
	)
	return {
		"appearanceId": "resident_wardrobe_v1:%s" % loadout_id,
		"loadoutId": loadout_id,
		"displayName": String(loadout.get("displayName", "小镇居民搭配")),
		"selection": (loadout.get("selection", {}) as Dictionary).duplicate(true),
		"portraitPath": portrait_path,
		"spriteSheetPath": sprite_sheet_path,
		"restPath": rest_path,
		"legacySpritePath": legacy_sprite_path,
		"formalReady": ready,
		"directionSetReady": ready,
	}


func _legacy_sprite_path_for_appearance(loadout_id: String) -> String:
	var appearance_id := "resident_wardrobe_v1:%s" % loadout_id
	for resident_value: Variant in _base_catalog.get("residents", []) as Array:
		if resident_value is not Dictionary:
			continue
		var resident := resident_value as Dictionary
		var attributes := resident.get("attributes", {}) as Dictionary
		if String(attributes.get("appearance", "")) != appearance_id:
			continue
		var presentation := resident.get("presentation", {}) as Dictionary
		return String(presentation.get("spritePath", ""))
	return (
		"res://assets/characters/paper_doll_64/compiled/"
		+ "neutral_hoodie_walk_64.png"
	)


func _selection_key(selection: Dictionary) -> String:
	var parts := PackedStringArray()
	for slot_id in WARDROBE_SLOTS:
		var variant_id := String(selection.get(slot_id, ""))
		if variant_id.is_empty():
			return ""
		parts.append("%s=%s" % [slot_id, variant_id])
	return "|".join(parts)


func _resource_path(path: String) -> String:
	if path.is_empty() or path.begins_with("res://"):
		return path
	return "res://" + path


func _option_before(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("label", "")) < String(right.get("label", ""))


func _publish_result(request_id: String, intent: String, result: Dictionary) -> Dictionary:
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
		"code": String(result.get("errorCode", "CUSTOM_RESIDENT_CREATOR_REJECTED")),
		"retryable": retryable,
		"message": _error_message(String(result.get("errorCode", ""))),
		"details": (result.get("errors", []) as Array).duplicate(true),
	}
	_revision += 1
	_emit_view_model()
	var response := _dispatch_result(
		ok,
		true,
		request_id,
		String(result.get("errorCode", "")),
		retryable,
		bool(result.get("changed", false)),
	)
	for key in [
		"candidatePoolRevision",
		"candidate",
		"selectionHandoff",
		"wardrobeHandoff",
		"resolvedAppearance",
	]:
		if result.has(key):
			response[key] = (
				(result[key] as Dictionary).duplicate(true)
				if result[key] is Dictionary
				else result[key]
			)
	return response


func _emit_view_model() -> void:
	view_model_changed.emit(SCOPE, get_view_model())


func _next_request_id() -> String:
	_request_sequence += 1
	return AiTownUiViewModel.request_id("custom-resident", _request_sequence)


func _action(intent: String, enabled: bool, disabled_reason := "") -> Dictionary:
	return AiTownUiViewModel.make_action(intent, enabled, disabled_reason)


func _success(changed: bool) -> Dictionary:
	return {"ok": true, "errorCode": "", "retryable": false, "changed": changed}


func _failure(error_code: String, errors: Array = []) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"errors": errors.duplicate(true),
	}


func _dispatch_result(
	ok: bool,
	accepted: bool,
	request_id: String,
	error_code: String,
	retryable: bool,
	changed := false,
) -> Dictionary:
	return UI_VIEW_MODEL.dispatch_result(ok, accepted, request_id, error_code, retryable, changed)


func _idle_operation() -> Dictionary:
	return AiTownUiViewModel.idle_operation()


func _error_message(error_code: String) -> String:
	match error_code:
		"CUSTOM_RESIDENT_NAME_DUPLICATED":
			return "这个名字已被本局候选使用，请换一个名字。"
		"CUSTOM_RESIDENT_CANDIDATE_POOL_REVISION_STALE":
			return "候选名单已经变化，请保留资料并重新确认。"
		"CUSTOM_RESIDENT_APPEARANCE_NOT_READY":
			return "当前衣柜搭配没有可用的正式方向图集。"
		"CUSTOM_RESIDENT_FIELD_UNKNOWN":
			return "外观只能在完整衣柜中调整。"
		"CUSTOM_RESIDENT_CREATOR_REVISION_STALE":
			return "页面资料已经更新，请按最新内容继续。"
	return "资料未通过检查，已经保留当前填写内容。"


func _configuration_failure(error_code: String) -> Dictionary:
	_configuration_error = error_code
	return RESULT_SHAPES.failure(error_code)


func _disabled_view_model() -> Dictionary:
	return {
		"scope": SCOPE,
		"status": "disabled",
		"revision": _revision,
		"data": {
			"capabilityMode": "formal",
			"source": "runtime",
			"formalReady": false,
			"draftId": "",
			"candidatePoolRevision": 0,
			"editableFields": [],
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
					"schemaVersion": 0,
					"runtimeMode": "",
					"slotOrder": WARDROBE_SLOTS.duplicate(),
				},
				"occupations": [],
				"workplaces": [],
			},
			"validation": {
				"status": "unavailable",
				"summaryLabel": "自定义居民创建服务尚未连接",
				"issues": [],
				"fieldIssues": {},
			},
		},
		"actions": {
			"updateFields": _action(
				"custom_resident_creator.update_fields",
				false,
				_configuration_error,
			),
			"openWardrobe": _action(
				"custom_resident_creator.open_wardrobe",
				false,
				_configuration_error,
			),
			"applyWardrobeResult": _action(
				"custom_resident_creator.apply_wardrobe_result",
				false,
				_configuration_error,
			),
			"create": _action(
				"custom_resident_creator.create",
				false,
				_configuration_error,
			),
			"cancel": _action(
				"custom_resident_creator.cancel",
				false,
				_configuration_error,
			),
			"retry": _action(
				"custom_resident_creator.retry",
				false,
				_configuration_error,
			),
		},
		"operation": _operation.duplicate(true),
		"error": {
			"kind": "unavailable",
			"code": _configuration_error,
			"retryable": false,
			"message": "自定义居民创建服务尚未连接。",
			"details": [],
		},
	}


func _reset() -> void:
	_candidate_pool = null
	_base_catalog.clear()
	_world_data.clear()
	_configured = false
	_revision = 0
	_request_sequence = 0
	_draft_id = ""
	_draft.clear()
	_wardrobe_catalog.clear()
	_wardrobe_by_loadout_id.clear()
	_wardrobe_by_selection.clear()
	_occupation_options.clear()
	_occupation_by_id.clear()
	_workplace_options.clear()
	_workplace_by_id.clear()
	_operation = _idle_operation()
	_error = null
	_configuration_error = "CUSTOM_RESIDENT_CREATOR_NOT_CONFIGURED"
