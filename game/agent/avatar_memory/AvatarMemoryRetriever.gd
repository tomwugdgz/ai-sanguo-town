class_name AgentAvatarMemoryRetriever
extends RefCounted


const PromptTextScript := preload("res://agent/prompt/PromptText.gd")
const TARGET_LENGTH := 1800
const LIMIT_LENGTH := 2200
const COMMON_TERMS: Array[String] = [
	"这个", "那个", "这里", "那里", "今天", "明天", "昨天", "现在",
	"已经", "正在", "还是", "可以", "不能", "没有", "一个", "一些",
	"居民", "化身", "对方", "自己",
]

var _avatar_person_id: String
var _avatar_name: String


func _init(avatar_person_id: String, avatar_name: String) -> void:
	_avatar_person_id = avatar_person_id
	_avatar_name = avatar_name


func mode_for_wake(wake_packet: Dictionary) -> String:
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	var conversation_value: Variant = snapshot.get("conversation")
	if typeof(conversation_value) == TYPE_DICTIONARY:
		var conversation := conversation_value as Dictionary
		if (
			String(conversation.get("with_resident_id", ""))
			== _avatar_person_id
		):
			return "avatar_interaction"
		return "resident_social"
	for nearby_value: Variant in snapshot.get("nearby", []) as Array:
		if typeof(nearby_value) != TYPE_DICTIONARY:
			continue
		var nearby := nearby_value as Dictionary
		if String(nearby.get("resident_id", "")) == _avatar_person_id:
			return "avatar_interaction"
	for event_value: Variant in wake_packet.get("events", []) as Array:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event := event_value as Dictionary
		if JSON.stringify(event, "", true).contains(_avatar_person_id):
			return "avatar_interaction"
		if [
			"搭话",
			"对方答话",
			"旁听",
			"对话结束",
		].has(String(event.get("type", ""))):
			return "resident_social"
	if not (snapshot.get("nearby", []) as Array).is_empty():
		return "resident_social"
	return "ordinary_life"


func retrieve(
	memory: Dictionary,
	evidence_items: Array,
	mode: String,
	wake_packet: Dictionary = {},
) -> Dictionary:
	if not [
		"avatar_interaction",
		"resident_social",
		"ordinary_life",
		"departure_message",
	].has(mode):
		return {"ok": false, "errors": ["化身记忆检索模式无效：%s" % mode]}
	var sections: Array[String] = []
	var summary := String(memory.get("summary", "")).strip_edges()
	var loops := _active_open_loops(memory.get("open_loops", []) as Array)
	if not loops.is_empty():
		sections.append("[与%s尚未说完或做完的事]\n%s" % [
			_safe(_avatar_name),
			_render_open_loops(loops),
		])
	if mode == "ordinary_life":
		return _bounded(sections, mode, [])
	if ["avatar_interaction", "departure_message"].has(mode):
		var messages := memory.get("sent_messages", []) as Array
		var recent_messages: Array = messages.slice(
			maxi(0, messages.size() - 3),
			messages.size(),
		)
		if not recent_messages.is_empty():
			sections.append("[你留过的话]\n%s" % _render_messages(recent_messages))
	if not summary.is_empty():
		sections.append("[总体认识]\n%s" % _safe(summary))
	var anchors := _anchors(wake_packet)
	var memories := _ranked_memories(
		memory.get("memories", []) as Array,
		anchors,
	)
	var memory_limit := 3 if mode == "resident_social" else 8
	if memories.size() > memory_limit:
		memories.resize(memory_limit)
	if not memories.is_empty():
		sections.append("[具体记忆]\n%s" % _render_memories(memories))
	if ["avatar_interaction", "departure_message"].has(mode):
		var recent_evidence := _recent_unorganized_evidence(evidence_items, 4)
		if not recent_evidence.is_empty():
			sections.append("[还没整理的近期经历]\n%s" % _render_evidence(
				recent_evidence,
			))
	return _bounded(sections, mode, memories)


func _bounded(
	sections: Array[String],
	mode: String,
	ranked_memories: Array,
) -> Dictionary:
	var text := "\n\n".join(sections).strip_edges()
	if text.length() <= LIMIT_LENGTH:
		return {
			"ok": true,
			"mode": mode,
			"text": text,
			"memory_ids": _memory_ids(ranked_memories),
		}
	var retained: Array[String] = []
	var remaining := LIMIT_LENGTH
	for section in sections:
		if remaining <= 0:
			break
		var candidate := section
		if candidate.length() > remaining:
			candidate = candidate.left(remaining).strip_edges()
		if not candidate.is_empty():
			retained.append(candidate)
			remaining -= candidate.length() + 2
	return {
		"ok": true,
		"mode": mode,
		"text": "\n\n".join(retained).strip_edges(),
		"memory_ids": _memory_ids(ranked_memories),
	}


func _ranked_memories(memories: Array, anchors: Array[String]) -> Array:
	var ranked: Array[Dictionary] = []
	for value: Variant in memories:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var item := (value as Dictionary).duplicate(true)
		if String(item.get("status", "")) == "superseded":
			continue
		var score := int(item.get("salience", 1)) * 10
		if ["active", "disputed"].has(String(item.get("status", ""))):
			score += 20
		var content := String(item.get("content", ""))
		for anchor in anchors:
			if content.contains(anchor):
				score += 6
		var time := item.get("world_time", {}) as Dictionary
		score += mini(9, int(time.get("day", 0)))
		item["_score"] = score
		ranked.append(item)
	ranked.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score := int(left.get("_score", 0))
		var right_score := int(right.get("_score", 0))
		if left_score != right_score:
			return left_score > right_score
		return String(left.get("memory_id", "")) < String(
			right.get("memory_id", ""),
		)
	)
	for item in ranked:
		item.erase("_score")
	return ranked


func _active_open_loops(open_loops: Array) -> Array:
	var active: Array[Dictionary] = []
	for value: Variant in open_loops:
		if (
			typeof(value) == TYPE_DICTIONARY
			and ["active", "disputed"].has(
				String((value as Dictionary).get("status", "")),
			)
		):
			active.append((value as Dictionary).duplicate(true))
	active.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_salience := int(left.get("salience", 1))
		var right_salience := int(right.get("salience", 1))
		if left_salience != right_salience:
			return left_salience > right_salience
		return String(left.get("loop_id", "")) < String(
			right.get("loop_id", ""),
		)
	)
	return active


func _recent_unorganized_evidence(items: Array, count: int) -> Array:
	var result: Array = []
	var start := maxi(0, items.size() - count)
	for index in range(start, items.size()):
		if typeof(items[index]) == TYPE_DICTIONARY:
			result.append((items[index] as Dictionary).duplicate(true))
	return result


func _render_memories(items: Array) -> String:
	var lines: Array[String] = []
	for value: Variant in items:
		var item := value as Dictionary
		lines.append("- %s（来源：%s；状态：%s）" % [
			_safe(item.get("content", "")),
			_source_label(item),
			_safe(item.get("status", "")),
		])
	return "\n".join(lines)


func _render_open_loops(items: Array) -> String:
	var lines: Array[String] = []
	for value: Variant in items:
		var item := value as Dictionary
		var progress := String(item.get("progress", "")).strip_edges()
		var line := "- %s" % _safe(item.get("content", ""))
		if not progress.is_empty():
			line += "；目前：%s" % _safe(progress)
		lines.append(line)
	return "\n".join(lines)


func _render_messages(items: Array) -> String:
	var lines: Array[String] = []
	for value: Variant in items:
		var item := value as Dictionary
		lines.append("- “%s”（%s）" % [
			_safe(item.get("content", "")),
			_safe(item.get("status", "")),
		])
	return "\n".join(lines)


func _render_evidence(items: Array) -> String:
	var lines: Array[String] = []
	for value: Variant in items:
		var item := value as Dictionary
		var payload := item.get("payload", {}) as Dictionary
		var speaker := String(payload.get("speaker", "")).strip_edges()
		var say := String(payload.get("say", "")).strip_edges()
		var narration := String(payload.get("narration", "")).strip_edges()
		var parts: Array[String] = []
		if not say.is_empty():
			parts.append("%s说：“%s”" % [
				_safe(speaker),
				_safe(say),
			])
		if not narration.is_empty():
			parts.append(_safe(narration))
		if parts.is_empty():
			parts.append(_safe(JSON.stringify(payload, "", true)))
		lines.append("- %s（来源：%s）" % [
			"；".join(parts),
			_safe(item.get("source_ref", "")),
		])
	return "\n".join(lines)


func _source_label(item: Dictionary) -> String:
	var source_type := String(item.get("source_type", ""))
	var person_id := String(item.get("source_person_id", ""))
	match source_type:
		"direct_dialogue":
			return "亲耳听见 %s" % _safe(person_id)
		"direct_observation":
			return "亲眼所见"
		"hearsay":
			return "%s 告诉我的" % _safe(person_id)
		"inference":
			return "自己的推测"
	return _safe(source_type)


func _anchors(wake_packet: Dictionary) -> Array[String]:
	var text := JSON.stringify(wake_packet, "", true)
	var anchors: Array[String] = []
	for segment in text.split(" ", false):
		var clean := segment.strip_edges()
		if clean.length() < 2:
			continue
		if clean.length() <= 8 and not COMMON_TERMS.has(clean) and not anchors.has(clean):
			anchors.append(clean)
	if not _avatar_name.is_empty() and not anchors.has(_avatar_name):
		anchors.append(_avatar_name)
	if not anchors.has(_avatar_person_id):
		anchors.append(_avatar_person_id)
	return anchors


func _memory_ids(items: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in items:
		if typeof(value) == TYPE_DICTIONARY:
			result.append(String((value as Dictionary).get("memory_id", "")))
	return result


func _safe(value: Variant) -> String:
	return PromptTextScript.escape_dynamic(String(value))
