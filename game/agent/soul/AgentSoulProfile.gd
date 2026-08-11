class_name AgentSoulProfile
extends RefCounted
## 开局一次性的 OC 分析结果。
##
## 这是 Agent 的私有资料，不是 World 的公共属性。特殊身份会影响本人的
## 行为倾向；关系只作为“未确认线索”，必须经过真实事件才能变成世界事实。


const ANALYSIS_VERSION := 1
const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const MAX_SOURCE_LENGTH := 1200
const MAX_EVIDENCE_LENGTH := 120
const IDENTITY_RULES := [
	{"id": "vampire", "label": "吸血鬼", "terms": ["吸血鬼", "吸血", "饮血", "血族"]},
	{"id": "sea_king", "label": "海王", "terms": ["海王", "暧昧成性", "同时和多人", "到处留情"]},
	{"id": "demon_hunter", "label": "猎魔人", "terms": ["猎魔人", "猎魔", "猎杀恶魔", "调查怪物"]},
	{"id": "priest", "label": "牧师", "terms": ["牧师", "祈祷", "神职", "主持弥撒"]},
	{"id": "dark_knight", "label": "暗黑骑士", "terms": ["暗黑骑士", "黑骑士", "骑士誓言", "守护誓言"]},
	{"id": "brawler", "label": "好斗者", "terms": ["只会打架", "爱打架", "凑热闹打架", "好斗", "好战", "拳头解决"]},
]
const RELATION_RULES := [
	{"stance": "hostile", "tags": ["仇人"], "terms": ["仇人", "死对头", "结仇", "有旧怨", "恨"]},
	{"stance": "affectionate", "tags": ["喜欢"], "terms": ["喜欢", "爱着", "暗恋", "心上人"]},
	{"stance": "protective", "tags": ["保护"], "terms": ["保护", "照顾", "欠他", "欠她"]},
	{"stance": "rival", "tags": ["竞争"], "terms": ["竞争对手", "宿敌", "不服", "看不顺眼"]},
]


static func analyze_all(residents: Array) -> Dictionary:
	var names_by_id: Dictionary = {}
	for value: Variant in residents:
		if not value is Dictionary:
			continue
		var resident := value as Dictionary
		var resident_id := String(resident.get("residentId", resident.get("resident_id", ""))).strip_edges()
		var attributes := resident.get("attributes", {}) as Dictionary
		var name := String(attributes.get("name", resident.get("name", ""))).strip_edges()
		if not resident_id.is_empty() and not name.is_empty():
			names_by_id[resident_id] = name
	var profiles: Dictionary = {}
	for value: Variant in residents:
		if not value is Dictionary:
			continue
		var resident := value as Dictionary
		var resident_id := String(resident.get("residentId", resident.get("resident_id", ""))).strip_edges()
		if resident_id.is_empty():
			continue
		var attributes := resident.get("attributes", {}) as Dictionary
		profiles[resident_id] = analyze(resident_id, attributes, names_by_id)
	return profiles


static func analyze(
	resident_id: String,
	attributes: Dictionary,
	names_by_id: Dictionary = {},
) -> Dictionary:
	var source_parts: Array[String] = []
	for field_name in ["name", "gender", "age", "desire", "personality", "speech"]:
		var text := str(attributes.get(field_name, "")).strip_edges()
		if not text.is_empty():
			source_parts.append("%s：%s" % [field_name, text])
	for field_name in ["interests", "customInterests"]:
		var values := attributes.get(field_name, []) as Array
		for value: Variant in values:
			var interest := str(value).strip_edges()
			if not interest.is_empty():
				source_parts.append("兴趣：%s" % interest)
	var source_text := "；".join(source_parts)
	if source_text.length() > MAX_SOURCE_LENGTH:
		source_text = source_text.substr(0, MAX_SOURCE_LENGTH)
	var identities: Array[Dictionary] = []
	for rule_value: Variant in IDENTITY_RULES:
		var rule := rule_value as Dictionary
		var matched_term := _first_term(source_text, rule.get("terms", []) as Array)
		if matched_term.is_empty():
			continue
		identities.append({
			"identity_id": String(rule.get("id", "")),
			"label": String(rule.get("label", "")),
			"evidence": _evidence(matched_term, source_text),
			"confidence": "high" if source_text.contains(matched_term) else "medium",
		})
	var relationship_hints: Array[Dictionary] = []
	for target_id: Variant in names_by_id:
		if String(target_id) == resident_id:
			continue
		var target_name := String(names_by_id[target_id])
		if target_name.is_empty() or not source_text.contains(target_name):
			continue
		for relation_value: Variant in RELATION_RULES:
			var relation := relation_value as Dictionary
			var matched_term := _first_term(source_text, relation.get("terms", []) as Array)
			if matched_term.is_empty():
				continue
			relationship_hints.append({
				"target_resident_id": String(target_id),
				"stance": String(relation.get("stance", "")),
				"tags": (relation.get("tags", []) as Array).duplicate(),
				"summary": "%s：%s" % [target_name, matched_term],
				"evidence": _evidence("%s%s" % [target_name, matched_term], source_text),
				"confidence": "high",
				"status": "unconfirmed",
			})
			break
	return {
		"analysis_version": ANALYSIS_VERSION,
		"source_text": source_text,
		"special_identities": identities,
		"relationship_hints": relationship_hints,
	}


static func validate(profile: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not profile is Dictionary:
		return ["soul_profile 必须是对象"]
	var value := profile as Dictionary
	for key: Variant in value:
		if key not in ["analysis_version", "source_text", "special_identities", "relationship_hints"]:
			errors.append("soul_profile.%s 不是允许字段" % String(key))
	if int(value.get("analysis_version", 0)) != ANALYSIS_VERSION:
		errors.append("soul_profile.analysis_version 不受支持")
	if not value.get("source_text", "") is String or String(value.get("source_text", "")).length() > MAX_SOURCE_LENGTH:
		errors.append("soul_profile.source_text 无效")
	for field_name in ["special_identities", "relationship_hints"]:
		if not value.get(field_name, null) is Array:
			errors.append("soul_profile.%s 必须是数组" % field_name)
	if value.get("special_identities", null) is Array:
		for index in (value.get("special_identities", []) as Array).size():
			var identity: Variant = (value.get("special_identities", []) as Array)[index]
			if not identity is Dictionary:
				errors.append("soul_profile.special_identities[%d] 必须是对象" % index)
				continue
			_validate_identity(identity as Dictionary, index, errors)
	if value.get("relationship_hints", null) is Array:
		for index in (value.get("relationship_hints", []) as Array).size():
			var hint: Variant = (value.get("relationship_hints", []) as Array)[index]
			if not hint is Dictionary:
				errors.append("soul_profile.relationship_hints[%d] 必须是对象" % index)
				continue
			_validate_relationship_hint(hint as Dictionary, index, errors)
	return errors


static func _validate_identity(value: Dictionary, index: int, errors: Array[String]) -> void:
	for key: Variant in value:
		if key not in ["identity_id", "label", "evidence", "confidence"]:
			errors.append("soul_profile.special_identities[%d].%s 不是允许字段" % [index, String(key)])
	for field_name in ["identity_id", "label", "evidence"]:
		if not value.get(field_name, "") is String or String(value.get(field_name, "")).strip_edges().is_empty():
			errors.append("soul_profile.special_identities[%d].%s 无效" % [index, field_name])
	if String(value.get("confidence", "")) not in ["high", "medium"]:
		errors.append("soul_profile.special_identities[%d].confidence 无效" % index)


static func _validate_relationship_hint(value: Dictionary, index: int, errors: Array[String]) -> void:
	for key: Variant in value:
		if key not in ["target_resident_id", "stance", "tags", "summary", "evidence", "confidence", "status"]:
			errors.append("soul_profile.relationship_hints[%d].%s 不是允许字段" % [index, String(key)])
	var target_id := String(value.get("target_resident_id", "")).strip_edges()
	if not WORLD_SCALARS.resident_id_is_safe(target_id):
		errors.append("soul_profile.relationship_hints[%d].target_resident_id 无效" % index)
	if String(value.get("stance", "")) not in ["hostile", "affectionate", "protective", "rival"]:
		errors.append("soul_profile.relationship_hints[%d].stance 无效" % index)
	if String(value.get("status", "")) != "unconfirmed":
		errors.append("soul_profile.relationship_hints[%d].status 必须是 unconfirmed" % index)
	for field_name in ["summary", "evidence"]:
		if not value.get(field_name, "") is String or String(value.get(field_name, "")).strip_edges().is_empty():
			errors.append("soul_profile.relationship_hints[%d].%s 无效" % [index, field_name])
	if not value.get("tags", null) is Array or (value.get("tags", []) as Array).is_empty():
		errors.append("soul_profile.relationship_hints[%d].tags 无效" % index)
	else:
		for tag_value: Variant in value.get("tags", []) as Array:
			if not tag_value is String or String(tag_value).strip_edges().is_empty():
				errors.append("soul_profile.relationship_hints[%d].tags 包含无效项" % index)


static func _first_term(text: String, terms: Array) -> String:
	for value: Variant in terms:
		var term := String(value)
		if not term.is_empty() and text.contains(term):
			return term
	return ""


static func _evidence(term: String, source: String) -> String:
	var index := source.find(term)
	if index < 0:
		return term
	var start := maxi(index - 18, 0)
	var length := mini(source.length() - start, MAX_EVIDENCE_LENGTH)
	return source.substr(start, length)
