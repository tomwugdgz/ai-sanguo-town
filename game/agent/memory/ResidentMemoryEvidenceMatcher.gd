class_name AgentResidentMemoryEvidenceMatcher
extends RefCounted


func find_candidate_indices(entries: Array, evidence: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var claim_root := String(evidence.get("claim_root_id", ""))
	var people := evidence.get("people", []) as Array
	var places := evidence.get("places", []) as Array
	var topics := evidence.get("topics", []) as Array
	for index in range(entries.size()):
		var entry := entries[index] as Dictionary
		if not claim_root.is_empty() and String(entry.get("claim_root_id", "")) == claim_root:
			result.append(index)
			continue
		if (
			_shared_value(entry.get("people", []), people)
			and (
				_shared_value(entry.get("places", []), places)
				or _shared_value(entry.get("topics", []), topics)
			)
		):
			result.append(index)
	if result.is_empty() and _has_semantic_evidence(evidence):
		var minimum_score := 0.45 if _has_action_result_evidence(evidence) else 0.58
		var semantic_index := _best_semantic_candidate(entries, evidence, minimum_score)
		if semantic_index >= 0:
			result.append(semantic_index)
	return result


func _shared_value(left_value: Variant, right_value: Variant) -> bool:
	if typeof(left_value) != TYPE_ARRAY or typeof(right_value) != TYPE_ARRAY:
		return false
	for value: Variant in left_value as Array:
		if (right_value as Array).has(value):
			return true
	return false


func _has_semantic_evidence(evidence: Dictionary) -> bool:
	for reference_value: Variant in evidence.get("evidence_refs", []) as Array:
		var reference := String(reference_value)
		if reference.begins_with("photo:") or reference.begins_with("action_result:"):
			return true
	return false


func _has_action_result_evidence(evidence: Dictionary) -> bool:
	for reference_value: Variant in evidence.get("evidence_refs", []) as Array:
		if String(reference_value).begins_with("action_result:"):
			return true
	return false


func _best_semantic_candidate(
	entries: Array,
	evidence: Dictionary,
	minimum_score: float,
) -> int:
	var evidence_text := _claim_text(
		"%s %s" % [
			evidence.get("subject", ""),
			evidence.get("interpretation", ""),
		],
	)
	var best_index := -1
	var best_score := 0.0
	for index in range(entries.size()):
		var entry := entries[index] as Dictionary
		if String(entry.get("state", "")) not in [
			"influencing",
			"doubtful",
			"anomalous",
		]:
			continue
		var entry_text := _claim_text(
			"%s %s" % [
				entry.get("subject", ""),
				entry.get("interpretation", ""),
			],
		)
		var score := _claim_similarity(evidence_text, entry_text)
		if score > best_score:
			best_score = score
			best_index = index
	return best_index if best_score >= minimum_score else -1


func _claim_text(value: String) -> String:
	var result := value.to_lower().strip_edges()
	var speech_marker := result.find("说：")
	if speech_marker >= 0:
		result = result.substr(speech_marker + 2)
	for boilerplate: String in [
		"向我展示的照片显示",
		"向我展示了一张照片",
		"照片显示",
		"看过照片后",
		"我看到",
		"我进行的用道具已经完成",
		"我进行的用道具没有成功",
		"我进行的用道具被中断",
		"我进行的用道具被新的安排替代",
		"检查柜台后，我发现",
	]:
		result = result.replace(boilerplate, "")
	for separator: String in [
		" ", "\t", "\r", "\n", "，", "。", "！", "？", "：", "；",
		",", ".", "!", "?", ":", ";", "“", "”", "\"", "'",
	]:
		result = result.replace(separator, "")
	return result


func _claim_similarity(left: String, right: String) -> float:
	if left.is_empty() or right.is_empty():
		return 0.0
	if left.contains(right) or right.contains(left):
		return (
			float(mini(left.length(), right.length()))
			/ float(maxi(left.length(), right.length()))
		)
	var left_pairs := _bigrams(left)
	var right_pairs := _bigrams(right)
	var shared := 0
	for pair: Variant in left_pairs:
		if right_pairs.has(pair):
			shared += 1
	return float(shared) / float(maxi(1, mini(left_pairs.size(), right_pairs.size())))


func _bigrams(text: String) -> Dictionary:
	var result := {}
	for index in range(maxi(0, text.length() - 1)):
		result[text.substr(index, 2)] = true
	return result
