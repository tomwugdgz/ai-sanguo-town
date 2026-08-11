class_name ConversationSemanticSegmenter
extends RefCounted


const DEFAULT_SOFT_LIMIT := 72
const DEFAULT_HARD_LIMIT := 96
const MIN_FRAGMENT_LENGTH := 18

const STRONG_END := "。！？!?"
const SECONDARY_END := "；;：:"
const WEAK_END := "，,、"
const CLOSING_MARKS := "”’」』）】》〉\"'"


static func segment(
	text: String,
	soft_limit := DEFAULT_SOFT_LIMIT,
	hard_limit := DEFAULT_HARD_LIMIT
) -> Array[String]:
	var normalized := text.replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	if normalized.is_empty():
		return []
	var safe_soft := maxi(24, soft_limit)
	var safe_hard := maxi(safe_soft, hard_limit)
	var units := _semantic_units(normalized)
	var result: Array[String] = []
	var current := ""
	for unit: String in units:
		if unit == "\n":
			_flush(current, result)
			current = ""
			continue
		if current.is_empty():
			current = unit
			continue
		var combined := current + unit
		if combined.length() <= safe_soft:
			current = combined
			continue
		if current.length() < MIN_FRAGMENT_LENGTH and combined.length() <= safe_hard:
			current = combined
			continue
		_flush(current, result)
		current = ""
		if unit.length() <= safe_hard:
			current = unit
			continue
		var oversized := _split_oversized(unit, safe_hard)
		for index: int in oversized.size():
			if index == oversized.size() - 1:
				current = oversized[index]
			else:
				_flush(oversized[index], result)
	_flush(current, result)
	return result


static func segment_message(
	message: Dictionary,
	soft_limit := DEFAULT_SOFT_LIMIT,
	hard_limit := DEFAULT_HARD_LIMIT
) -> Array[Dictionary]:
	var copy := message.duplicate(true)
	var pieces := segment(str(copy.get("say", "")), soft_limit, hard_limit)
	if pieces.is_empty():
		pieces = [""]
	var result: Array[Dictionary] = []
	for index: int in pieces.size():
		var projected := copy.duplicate(true)
		projected["say"] = pieces[index]
		projected["segmentIndex"] = index
		projected["segmentCount"] = pieces.size()
		projected["showIdentity"] = index == 0
		projected["showNarration"] = index == pieces.size() - 1
		result.append(projected)
	return result


static func _semantic_units(text: String) -> Array[String]:
	var result: Array[String] = []
	var current := ""
	var index := 0
	while index < text.length():
		var character := text.substr(index, 1)
		if character == "\n":
			_flush(current, result)
			current = ""
			if result.is_empty() or result[-1] != "\n":
				result.append("\n")
			index += 1
			continue
		current += character
		if STRONG_END.contains(character) or SECONDARY_END.contains(character):
			index += 1
			while index < text.length():
				var following := text.substr(index, 1)
				if (
					STRONG_END.contains(following)
					or SECONDARY_END.contains(following)
					or CLOSING_MARKS.contains(following)
				):
					current += following
					index += 1
					continue
				break
			_flush(current, result)
			current = ""
			continue
		index += 1
	_flush(current, result)
	return result


static func _split_oversized(text: String, hard_limit: int) -> Array[String]:
	var result: Array[String] = []
	var remaining := text.strip_edges()
	while remaining.length() > hard_limit:
		var split_at := _last_semantic_boundary(remaining, hard_limit)
		if split_at < MIN_FRAGMENT_LENGTH:
			split_at = hard_limit
		var piece := remaining.substr(0, split_at).strip_edges()
		if not piece.is_empty():
			result.append(piece)
		remaining = remaining.substr(split_at).strip_edges()
	if not remaining.is_empty():
		result.append(remaining)
	return result


static func _last_semantic_boundary(text: String, hard_limit: int) -> int:
	var scan_limit := mini(hard_limit, text.length())
	for index: int in range(scan_limit - 1, MIN_FRAGMENT_LENGTH - 1, -1):
		var character := text.substr(index, 1)
		if (
			STRONG_END.contains(character)
			or SECONDARY_END.contains(character)
			or WEAK_END.contains(character)
		):
			var split_at := index + 1
			while split_at < text.length():
				var following := text.substr(split_at, 1)
				if not CLOSING_MARKS.contains(following):
					break
				split_at += 1
			return split_at
	return -1


static func _flush(value: String, target: Array[String]) -> void:
	var normalized := value.strip_edges()
	if not normalized.is_empty():
		target.append(normalized)
