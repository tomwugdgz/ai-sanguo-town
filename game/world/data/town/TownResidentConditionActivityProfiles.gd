class_name TownResidentConditionActivityProfiles
extends RefCounted


const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const PROFILE_PATH := (
	"res://world/data/town/source/condition_activity_profiles.json"
)
const ACTIVITY_PATH := (
	"res://world/data/town/source/activity_definitions.json"
)
const CONDITION_CATALOG := preload(
	"res://world/data/town/TownResidentConditionCatalog.gd"
)
const PROFILE_FIELDS: Array[String] = [
	"activityId",
	"riskTags",
	"reliefTags",
]


static func load_profiles() -> Dictionary:
	return _load_json(PROFILE_PATH)


static func validate(
	document: Dictionary,
	activity_document: Dictionary = {},
	condition_catalog: Dictionary = {},
) -> PackedStringArray:
	var errors := PackedStringArray()
	if not _exact_keys(document, ["schemaVersion", "profiles"]):
		errors.append("临时状况活动规则字段不完整或包含未知字段")
	if document.get("schemaVersion") != 1:
		errors.append("临时状况活动规则版本无效")
	var profiles_value: Variant = document.get("profiles")
	if not profiles_value is Array:
		errors.append("临时状况活动规则 profiles 必须是数组")
		return errors
	var resolved_activities := (
		_load_json(ACTIVITY_PATH)
		if activity_document.is_empty()
		else activity_document.duplicate(true)
	)
	var resolved_catalog := (
		CONDITION_CATALOG.load_catalog()
		if condition_catalog.is_empty()
		else condition_catalog.duplicate(true)
	)
	var activity_ids: Dictionary = {}
	for value: Variant in resolved_activities.get("activities", []) as Array:
		if value is Dictionary:
			activity_ids[String((value as Dictionary).get("activityId", ""))] = true
	var known_risks := _string_set(
		resolved_catalog.get("riskTags", []) as Array,
	)
	var known_reliefs := _string_set(
		resolved_catalog.get("reliefTags", []) as Array,
	)
	var seen: Dictionary = {}
	for index in (profiles_value as Array).size():
		var value: Variant = (profiles_value as Array)[index]
		if not value is Dictionary:
			errors.append("临时状况活动规则 profiles[%d] 必须是对象" % index)
			continue
		var profile := value as Dictionary
		if not _exact_keys(profile, PROFILE_FIELDS):
			errors.append("临时状况活动规则 profiles[%d] 字段无效" % index)
		var activity_id := String(profile.get("activityId", "")).strip_edges()
		if activity_id.is_empty() or seen.has(activity_id):
			errors.append("临时状况活动编号为空或重复：%s" % activity_id)
		elif not activity_ids.has(activity_id):
			errors.append("临时状况活动引用不存在：%s" % activity_id)
		seen[activity_id] = true
		_validate_tags(
			profile.get("riskTags"),
			known_risks,
			"风险",
			activity_id,
			errors,
		)
		_validate_tags(
			profile.get("reliefTags"),
			known_reliefs,
			"缓解",
			activity_id,
			errors,
		)
		if (
			profile.get("riskTags") is Array
			and profile.get("reliefTags") is Array
			and (profile.get("riskTags") as Array).is_empty()
			and (profile.get("reliefTags") as Array).is_empty()
		):
			errors.append("临时状况活动规则不能同时没有风险和缓解：%s" % activity_id)
	return errors


static func profiles_by_activity(document: Dictionary = {}) -> Dictionary:
	var resolved := load_profiles() if document.is_empty() else document
	var result: Dictionary = {}
	for value: Variant in resolved.get("profiles", []) as Array:
		if not value is Dictionary:
			continue
		var profile := value as Dictionary
		result[String(profile.get("activityId", ""))] = profile.duplicate(true)
	return result


static func profile_for_activity(
	activity_id: String,
	document: Dictionary = {},
) -> Dictionary:
	return (
		profiles_by_activity(document).get(activity_id, {}) as Dictionary
	).duplicate(true)


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


static func _validate_tags(
	value: Variant,
	known: Dictionary,
	label: String,
	activity_id: String,
	errors: PackedStringArray,
) -> void:
	if not value is Array:
		errors.append("临时状况活动%s标签必须是数组：%s" % [label, activity_id])
		return
	var seen: Dictionary = {}
	for tag_value: Variant in value as Array:
		if not tag_value is String:
			errors.append("临时状况活动%s标签必须是字符串：%s" % [label, activity_id])
			continue
		var tag := String(tag_value).strip_edges()
		if tag.is_empty() or seen.has(tag):
			errors.append("临时状况活动%s标签为空或重复：%s" % [label, activity_id])
		elif not known.has(tag):
			errors.append("临时状况活动%s标签未知：%s.%s" % [label, activity_id, tag])
		seen[tag] = true


static func _string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in values:
		result[String(value)] = true
	return result


static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	return WORLD_SCALARS.exact_keys(value, expected)
