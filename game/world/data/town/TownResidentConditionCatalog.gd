class_name TownResidentConditionCatalog
extends RefCounted


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const CATALOG_PATH := "res://world/data/town/source/condition_catalog.json"
const CONDITION_FIELDS: Array[String] = [
	"kind",
	"labels",
	"baseChanceByTrigger",
	"riskTags",
	"reliefTags",
	"sourceKinds",
	"cooldownMinutes",
	"nextChangeMinutes",
	"maxSeverity",
	"needKinds",
	"eligibilityAny",
	"requiresConditionKinds",
]
const NEED_FIELDS: Array[String] = [
	"kind",
	"label",
	"responseRequirements",
]
const ELIGIBILITY_FIELDS: Array[String] = [
	"field",
	"operator",
	"value",
]
const ALLOWED_ELIGIBILITY_FIELDS := [
	"energy",
	"satiety",
	"stress",
	"socialNeed",
	"solitudeNeed",
	"actualSleepMinutes",
	"durationMinutes",
]
const ALLOWED_OPERATORS := ["lte", "gte"]


static func load_catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CATALOG_PATH),
	)
	if not parsed is Dictionary:
		return {}
	var catalog := (parsed as Dictionary).duplicate(true)
	return catalog if validate(catalog).is_empty() else {}


static func validate(catalog: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not _exact_keys(
		catalog,
		[
			"schemaVersion",
			"worldId",
			"severityOrder",
			"states",
			"triggerKinds",
			"sourceKinds",
			"riskTags",
			"reliefTags",
			"processedTriggerLimit",
			"ambientCheckMinutes",
			"needs",
			"conditions",
		],
	):
		errors.append("居民临时状况目录字段无效")
	if not _is_integer_number(catalog.get("schemaVersion")):
		errors.append("居民临时状况目录 schemaVersion 必须是整数")
	elif int(catalog.get("schemaVersion", 0)) != 1:
		errors.append("居民临时状况目录 schemaVersion 必须为 1")
	if String(catalog.get("worldId", "")) != "town":
		errors.append("居民临时状况目录 worldId 无效")
	var severities := _string_array(
		catalog.get("severityOrder"),
		"severityOrder",
		errors,
	)
	if severities != ["minor", "noticeable", "serious"]:
		errors.append("居民临时状况程度顺序无效")
	var states := _string_array(catalog.get("states"), "states", errors)
	if states != ["active", "recovering"]:
		errors.append("居民临时状况状态无效")
	var trigger_kinds := _string_array(
		catalog.get("triggerKinds"),
		"triggerKinds",
		errors,
	)
	var source_kinds := _string_array(
		catalog.get("sourceKinds"),
		"sourceKinds",
		errors,
	)
	var risk_tags := _string_array(
		catalog.get("riskTags"),
		"riskTags",
		errors,
	)
	var relief_tags := _string_array(
		catalog.get("reliefTags"),
		"reliefTags",
		errors,
	)
	if trigger_kinds != ["wake", "action_result", "ambient_exposure"]:
		errors.append("居民临时状况触发类型无效")
	if source_kinds.is_empty() or risk_tags.is_empty() or relief_tags.is_empty():
		errors.append("居民临时状况目录缺少来源或行为标签")
	var limit_value: Variant = catalog.get("processedTriggerLimit")
	if not _is_integer_number(limit_value) or int(limit_value) < 32:
		errors.append("居民临时状况已处理触发上限无效")
	_validate_range(
		catalog.get("ambientCheckMinutes"),
		"ambientCheckMinutes",
		errors,
	)
	var needs_by_kind: Dictionary = {}
	var needs_value: Variant = catalog.get("needs")
	if not needs_value is Array:
		errors.append("居民临时状况 needs 必须是数组")
	else:
		for value: Variant in needs_value as Array:
			if not value is Dictionary:
				errors.append("居民临时状况需要条目必须是对象")
				continue
			var need := value as Dictionary
			if not _exact_keys(need, NEED_FIELDS):
				errors.append("居民临时状况需要条目字段无效")
			var kind := String(need.get("kind", "")).strip_edges()
			if kind.is_empty() or needs_by_kind.has(kind):
				errors.append("居民临时状况需要编号无效：%s" % kind)
			else:
				needs_by_kind[kind] = true
			if String(need.get("label", "")).strip_edges().is_empty():
				errors.append("居民临时状况需要缺少说明：%s" % kind)
			if _string_array(
				need.get("responseRequirements"),
				"needs.%s.responseRequirements" % kind,
				errors,
			).is_empty():
				errors.append("居民临时状况需要缺少处理要求：%s" % kind)
	var conditions_value: Variant = catalog.get("conditions")
	if not conditions_value is Array:
		errors.append("居民临时状况 conditions 必须是数组")
		return errors
	var conditions_by_kind: Dictionary = {}
	for value: Variant in conditions_value as Array:
		if not value is Dictionary:
			errors.append("居民临时状况条目必须是对象")
			continue
		var condition := value as Dictionary
		if not _exact_keys(condition, CONDITION_FIELDS):
			errors.append("居民临时状况条目字段无效")
		var kind := String(condition.get("kind", "")).strip_edges()
		if kind.is_empty() or conditions_by_kind.has(kind):
			errors.append("居民临时状况种类无效：%s" % kind)
			continue
		conditions_by_kind[kind] = condition
		var labels_value: Variant = condition.get("labels")
		if not labels_value is Dictionary or not _exact_keys(
			labels_value as Dictionary,
			severities,
		):
			errors.append("居民临时状况程度文字无效：%s" % kind)
		else:
			for severity: String in severities:
				if String((labels_value as Dictionary).get(severity, "")).strip_edges().is_empty():
					errors.append("居民临时状况程度文字为空：%s.%s" % [kind, severity])
		var chances_value: Variant = condition.get("baseChanceByTrigger")
		if not chances_value is Dictionary or (chances_value as Dictionary).is_empty():
			errors.append("居民临时状况缺少触发概率：%s" % kind)
		else:
			for trigger_value: Variant in (chances_value as Dictionary):
				var trigger_kind := String(trigger_value)
				var chance_value: Variant = (chances_value as Dictionary).get(trigger_value)
				if (
					not trigger_kinds.has(trigger_kind)
					or typeof(chance_value) not in [TYPE_INT, TYPE_FLOAT]
					or not is_finite(float(chance_value))
					or float(chance_value) <= 0.0
					or float(chance_value) > 0.5
				):
					errors.append("居民临时状况触发概率无效：%s.%s" % [kind, trigger_kind])
		var condition_risks := _string_array(
			condition.get("riskTags"),
			"conditions.%s.riskTags" % kind,
			errors,
			true,
		)
		for tag: String in condition_risks:
			if not risk_tags.has(tag):
				errors.append("居民临时状况引用未知风险标签：%s.%s" % [kind, tag])
		var condition_reliefs := _string_array(
			condition.get("reliefTags"),
			"conditions.%s.reliefTags" % kind,
			errors,
		)
		for tag: String in condition_reliefs:
			if not relief_tags.has(tag):
				errors.append("居民临时状况引用未知缓解标签：%s.%s" % [kind, tag])
		var condition_sources := _string_array(
			condition.get("sourceKinds"),
			"conditions.%s.sourceKinds" % kind,
			errors,
		)
		for source_kind: String in condition_sources:
			if not source_kinds.has(source_kind):
				errors.append("居民临时状况引用未知来源：%s.%s" % [kind, source_kind])
		var cooldown_value: Variant = condition.get("cooldownMinutes")
		if not _is_integer_number(cooldown_value) or int(cooldown_value) <= 0:
			errors.append("居民临时状况冷却无效：%s" % kind)
		_validate_range(
			condition.get("nextChangeMinutes"),
			"conditions.%s.nextChangeMinutes" % kind,
			errors,
		)
		if String(condition.get("maxSeverity", "")) not in severities:
			errors.append("居民临时状况最高程度无效：%s" % kind)
		for need_kind: String in _string_array(
			condition.get("needKinds"),
			"conditions.%s.needKinds" % kind,
			errors,
		):
			if not needs_by_kind.has(need_kind):
				errors.append("居民临时状况引用未知当前需要：%s.%s" % [kind, need_kind])
		_validate_eligibility(
			condition.get("eligibilityAny"),
			"conditions.%s.eligibilityAny" % kind,
			errors,
		)
		_string_array(
			condition.get("requiresConditionKinds"),
			"conditions.%s.requiresConditionKinds" % kind,
			errors,
			true,
		)
	for kind_value: Variant in conditions_by_kind:
		var condition := conditions_by_kind.get(kind_value, {}) as Dictionary
		for required_kind: String in condition.get("requiresConditionKinds", []) as Array:
			if not conditions_by_kind.has(required_kind) or required_kind == String(kind_value):
				errors.append("居民临时状况前置种类无效：%s.%s" % [String(kind_value), required_kind])
	return errors


static func condition_by_kind(catalog: Dictionary, kind: String) -> Dictionary:
	for value: Variant in catalog.get("conditions", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("kind", "")) == kind:
			return (value as Dictionary).duplicate(true)
	return {}


static func need_by_kind(catalog: Dictionary, kind: String) -> Dictionary:
	for value: Variant in catalog.get("needs", []) as Array:
		if value is Dictionary and String((value as Dictionary).get("kind", "")) == kind:
			return (value as Dictionary).duplicate(true)
	return {}


static func _validate_eligibility(
	value: Variant,
	path: String,
	errors: PackedStringArray,
) -> void:
	if not value is Array:
		errors.append("%s 必须是数组" % path)
		return
	for item_value: Variant in value as Array:
		if not item_value is Dictionary:
			errors.append("%s 条目必须是对象" % path)
			continue
		var item := item_value as Dictionary
		if not _exact_keys(item, ELIGIBILITY_FIELDS):
			errors.append("%s 条目字段无效" % path)
		if String(item.get("field", "")) not in ALLOWED_ELIGIBILITY_FIELDS:
			errors.append("%s 使用未知字段" % path)
		if String(item.get("operator", "")) not in ALLOWED_OPERATORS:
			errors.append("%s 使用未知比较方式" % path)
		var number_value: Variant = item.get("value")
		if (
			typeof(number_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(number_value))
		):
			errors.append("%s 比较值无效" % path)


static func _validate_range(
	value: Variant,
	path: String,
	errors: PackedStringArray,
) -> void:
	if not value is Dictionary or not _exact_keys(value as Dictionary, ["min", "max"]):
		errors.append("%s 范围字段无效" % path)
		return
	var minimum_value: Variant = (value as Dictionary).get("min")
	var maximum_value: Variant = (value as Dictionary).get("max")
	if (
		not _is_integer_number(minimum_value)
		or not _is_integer_number(maximum_value)
		or int(minimum_value) <= 0
		or int(maximum_value) < int(minimum_value)
	):
		errors.append("%s 范围无效" % path)


static func _string_array(
	value: Variant,
	path: String,
	errors: PackedStringArray,
	allow_empty := false,
) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		errors.append("%s 必须是数组" % path)
		return result
	for item_value: Variant in value as Array:
		if not item_value is String:
			errors.append("%s 只能包含文本" % path)
			continue
		var item := String(item_value).strip_edges()
		if item.is_empty() or result.has(item):
			errors.append("%s 包含空值或重复值" % path)
			continue
		result.append(item)
	if result.is_empty() and not allow_empty:
		errors.append("%s 不能为空" % path)
	return result


static func _is_integer_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == floor(float(value))
	)


static func _exact_keys(value: Dictionary, fields: Array) -> bool:
	return WORLD_SCALARS.exact_keys(value, fields)
