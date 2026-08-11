class_name AgentResidentMemoryReappraiser
extends RefCounted


const NEGATION_TERMS: Array[String] = [
	"没有", "并未", "并不", "不是", "不在", "未曾", "失败", "拒绝", "取消", "中断", "无法",
]


func compare(entry: Dictionary, evidence: Dictionary, intervention_active: bool) -> String:
	var old_text := "%s %s" % [
		String(entry.get("subject", "")),
		String(entry.get("interpretation", "")),
	]
	var new_text := String(evidence.get("subject", ""))
	if String(entry.get("claim_root_id", "")) == String(evidence.get("claim_root_id", "")):
		if _contradictory(old_text, new_text):
			if intervention_active:
				return "discover_anomaly"
			if (
				String(entry.get("state", "")) == "doubtful"
				and String(evidence.get("source_kind", "")) == "firsthand"
			):
				return "correct"
			return "doubt"
		return "reinforce"
	if _contradictory(old_text, new_text):
		if intervention_active:
			return "discover_anomaly"
		if String(entry.get("state", "")) == "doubtful" and String(evidence.get("source_kind", "")) == "firsthand":
			return "correct"
		return "doubt"
	return "keep"


func apply_result(
	entry: Dictionary,
	evidence: Dictionary,
	result_kind: String,
	revision: int,
) -> Dictionary:
	var changed := entry.duplicate(true)
	var evidence_refs := (changed.get("evidence_refs", []) as Array).duplicate()
	for source_ref: Variant in evidence.get("evidence_refs", []) as Array:
		if not evidence_refs.has(source_ref):
			evidence_refs.append(source_ref)
	changed["evidence_refs"] = evidence_refs
	match result_kind:
		"reinforce":
			changed["confidence"] = mini(100, int(changed.get("confidence", 0)) + 8)
			if String(changed.get("state", "")) == "doubtful":
				changed["state"] = "influencing"
		"doubt":
			changed["confidence"] = maxi(10, int(changed.get("confidence", 0)) - 20)
			changed["state"] = "doubtful"
		"discover_anomaly":
			changed["confidence"] = maxi(10, int(changed.get("confidence", 0)) - 30)
			changed["state"] = "anomalous"
		"correct":
			changed["subject"] = String(evidence.get("subject", changed.get("subject", "")))
			changed["interpretation"] = "后来得到的亲历证据修正了我原先的理解。"
			changed["confidence"] = 72
			changed["state"] = "corrected"
		_:
			return changed
	changed["active_version_id"] = "%s-v%d" % [changed.get("memory_id", "memory"), revision]
	changed["updated_revision"] = revision
	return changed


func _contradictory(left: String, right: String) -> bool:
	var left_negative := _contains_any(left, NEGATION_TERMS)
	var right_negative := _contains_any(right, NEGATION_TERMS)
	return left_negative != right_negative


func _contains_any(text: String, terms: Array[String]) -> bool:
	for term: String in terms:
		if text.contains(term):
			return true
	return false
