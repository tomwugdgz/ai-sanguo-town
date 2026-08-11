class_name TownInterestCatalog
extends RefCounted


const CATALOG_PATH := "res://world/data/town/interest_catalog.json"
const SCHEMA_VERSION := 1
const WORLD_ID := "town"
const DEFAULT_MAX_INTERESTS := 3
const MAX_CUSTOM_INTEREST_LENGTH := 20


static func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CATALOG_PATH)
	)
	if not parsed is Dictionary:
		return {}
	var catalog := (parsed as Dictionary).duplicate(true)
	return catalog if validate_catalog(catalog).is_empty() else {}


static func validate_catalog(catalog: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not _has_exact_keys(
		catalog,
		[
			"schemaVersion",
			"worldId",
			"maxInterestsPerResident",
			"interests",
		],
	):
		errors.append("兴趣目录字段无效")
	if int(catalog.get("schemaVersion", 0)) != SCHEMA_VERSION:
		errors.append("兴趣目录 schemaVersion 无效")
	if String(catalog.get("worldId", "")) != WORLD_ID:
		errors.append("兴趣目录 worldId 无效")
	var max_interests := int(
		catalog.get("maxInterestsPerResident", 0)
	)
	if max_interests <= 0:
		errors.append("兴趣目录 maxInterestsPerResident 无效")
	var values: Variant = catalog.get("interests")
	if not values is Array or values.is_empty():
		errors.append("兴趣目录 interests 必须是非空数组")
		return errors
	var seen: Dictionary = {}
	for value: Variant in values as Array:
		if not value is Dictionary:
			errors.append("兴趣目录条目必须是对象")
			continue
		var entry := value as Dictionary
		if not _has_exact_keys(
			entry,
			["interestId", "label", "activityTags"],
		):
			errors.append("兴趣目录条目字段无效")
		var interest_id := String(entry.get("interestId", "")).strip_edges()
		var label := String(entry.get("label", "")).strip_edges()
		if interest_id.is_empty() or not interest_id.begins_with("interest_"):
			errors.append("兴趣标识无效")
		elif seen.has(interest_id):
			errors.append("兴趣标识重复：%s" % interest_id)
		else:
			seen[interest_id] = true
		if label.is_empty():
			errors.append("兴趣名称不能为空")
		var tags: Variant = entry.get("activityTags")
		if not tags is Array:
			errors.append("兴趣 %s 的 activityTags 必须是数组" % interest_id)
			continue
		var tag_seen: Dictionary = {}
		for tag_value: Variant in tags as Array:
			var tag := String(tag_value).strip_edges()
			if tag.is_empty() or tag_seen.has(tag):
				errors.append("兴趣 %s 的 activityTags 无效" % interest_id)
				continue
			tag_seen[tag] = true
	return errors


static func max_interests(catalog: Dictionary = {}) -> int:
	var source := catalog if not catalog.is_empty() else load_catalog()
	return maxi(
		int(source.get("maxInterestsPerResident", DEFAULT_MAX_INTERESTS)),
		1,
	)


static func options(catalog: Dictionary = {}) -> Array[Dictionary]:
	var source := catalog if not catalog.is_empty() else load_catalog()
	var result: Array[Dictionary] = []
	for value: Variant in source.get("interests", []) as Array:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


static func ids(catalog: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	for option: Dictionary in options(catalog):
		result.append(String(option.get("interestId", "")))
	return result


static func matched_labels_for_activity(
	interest_value: Variant,
	activity_tags: Variant,
	catalog: Dictionary = {},
) -> Array[String]:
	if not activity_tags is Array:
		return []
	var selected := normalize(interest_value)
	var tags := activity_tags as Array
	var result: Array[String] = []
	for option: Dictionary in options(catalog):
		if not selected.has(String(option.get("interestId", ""))):
			continue
		var matches := false
		for tag_value: Variant in option.get("activityTags", []) as Array:
			if tags.has(String(tag_value)):
				matches = true
				break
		if matches:
			result.append(String(option.get("label", "")))
	return result


static func labels_for(
	value: Variant,
	catalog: Dictionary = {},
) -> Array[String]:
	var labels_by_id: Dictionary = {}
	for option: Dictionary in options(catalog):
		labels_by_id[String(option.get("interestId", ""))] = String(
			option.get("label", ""),
		)
	var result: Array[String] = []
	for interest_id: String in normalize(value):
		var label := String(labels_by_id.get(interest_id, "")).strip_edges()
		if not label.is_empty():
			result.append(label)
	return result


static func combined_labels_for(
	interest_value: Variant,
	custom_interest_value: Variant,
	catalog: Dictionary = {},
) -> Array[String]:
	var result := labels_for(interest_value, catalog)
	result.append_array(normalize_custom(custom_interest_value))
	return result


static func normalize(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		var interest_id := String(item).strip_edges()
		if not interest_id.is_empty() and not result.has(interest_id):
			result.append(interest_id)
	return result


static func normalize_custom(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		var label := String(item).strip_edges()
		if not label.is_empty() and not result.has(label):
			result.append(label)
	return result


static func validation_error(
	value: Variant,
	catalog: Dictionary = {},
) -> String:
	if not value is Array:
		return "RESIDENT_INTERESTS_INVALID"
	var normalized := normalize(value)
	if normalized.size() != (value as Array).size():
		return "RESIDENT_INTERESTS_INVALID"
	if normalized.size() > max_interests(catalog):
		return "RESIDENT_INTERESTS_TOO_MANY"
	var allowed := ids(catalog)
	for interest_id: String in normalized:
		if not allowed.has(interest_id):
			return "RESIDENT_INTEREST_UNKNOWN"
	return ""


static func custom_validation_error(
	value: Variant,
	catalog_interests: Variant = [],
	catalog: Dictionary = {},
) -> String:
	if not value is Array:
		return "RESIDENT_CUSTOM_INTERESTS_INVALID"
	var normalized := normalize_custom(value)
	if normalized.size() != (value as Array).size():
		return "RESIDENT_CUSTOM_INTERESTS_INVALID"
	var catalog_labels: Array[String] = []
	for label: String in labels_for(catalog_interests, catalog):
		catalog_labels.append(label.to_lower())
	var seen: Dictionary = {}
	for label: String in normalized:
		if not _valid_custom_label(label):
			return "RESIDENT_CUSTOM_INTEREST_INVALID"
		var folded := label.to_lower()
		if seen.has(folded) or catalog_labels.has(folded):
			return "RESIDENT_CUSTOM_INTERESTS_INVALID"
		seen[folded] = true
	return ""


static func profile_validation_error(
	interest_value: Variant,
	custom_interest_value: Variant,
	catalog: Dictionary = {},
) -> String:
	var interest_error := validation_error(interest_value, catalog)
	if not interest_error.is_empty():
		return interest_error
	var custom_error := custom_validation_error(
		custom_interest_value,
		interest_value,
		catalog,
	)
	if not custom_error.is_empty():
		return custom_error
	if (
		normalize(interest_value).size()
		+ normalize_custom(custom_interest_value).size()
		> max_interests(catalog)
	):
		return "RESIDENT_INTERESTS_TOO_MANY"
	return ""


static func migrate_attributes(attributes: Dictionary) -> Dictionary:
	var result := attributes.duplicate(true)
	result["interests"] = normalize(result.get("interests", []))
	result["customInterests"] = normalize_custom(
		result.get("customInterests", []),
	)
	return result


static func _valid_custom_label(label: String) -> bool:
	if (
		label.is_empty()
		or label.length() > MAX_CUSTOM_INTEREST_LENGTH
		or label != label.strip_edges()
	):
		return false
	for character: String in label:
		var code := character.unicode_at(0)
		if code < 32 or code == 127:
			return false
	return true


static func _has_exact_keys(
	value: Dictionary,
	expected: Array,
) -> bool:
	var actual := value.keys()
	var wanted := expected.duplicate()
	actual.sort()
	wanted.sort()
	return actual == wanted
