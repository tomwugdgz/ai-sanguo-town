extends RefCounted


# 冲突起因/动机/空投影纯函数族(O 域迁移第七件乙)。

static func resident_conflict_cause_for_target(
	resident: Dictionary,
	target_id: String,
) -> Dictionary:
	var events := resident.get("inflightEvents", []) as Array
	for reverse_index in events.size():
		var value: Variant = events[events.size() - reverse_index - 1]
		if value is not Dictionary:
			continue
		var event := value as Dictionary
		var event_id := String(event.get("event_id", "")).strip_edges()
		if event_id.is_empty():
			continue
		var event_type := String(event.get("type", ""))
		var source_resident_id := ""
		var summary := ""
		var conversation_id := String(
			event.get("conversation_id", ""),
		).strip_edges()
		match event_type:
			"搭话", "对方答话":
				var turn := event.get("turn", {}) as Dictionary
				source_resident_id = String(
					turn.get("speaker_resident_id", ""),
				)
				summary = String(turn.get("say", "")).strip_edges()
			"对话结束":
				var turns := event.get("turns", []) as Array
				for turn_index in turns.size():
					var turn_value: Variant = turns[turns.size() - turn_index - 1]
					if turn_value is not Dictionary:
						continue
					var ended_turn := turn_value as Dictionary
					if String(ended_turn.get("speaker_resident_id", "")) != target_id:
						continue
					source_resident_id = target_id
					summary = String(ended_turn.get("say", "")).strip_edges()
					break
			"旁听":
				if (event.get("speaker_resident_ids", []) as Array).has(target_id):
					source_resident_id = target_id
					summary = String(
						(event.get("turn", {}) as Dictionary).get("say", ""),
					).strip_edges()
			"公告转告":
				source_resident_id = String(
					event.get("speaker_resident_id", ""),
				)
				summary = String(event.get("text", "")).strip_edges()
		if source_resident_id != target_id or summary.is_empty():
			continue
		return {
			"sourceEventIds": [event_id],
			"sourceKind": event_type,
			"summary": summary.replace("\n", " ").left(120),
			"conversationId": conversation_id,
		}
	return {}

static func resident_profile_conflict_motive(
	resident: Dictionary,
	target_id: String,
	soul_profile: Dictionary = {},
) -> Dictionary:
	if target_id.is_empty():
		return {}
	var attributes := resident.get("attributes", {}) as Dictionary
	var personality := String(attributes.get("personality", "")).strip_edges()
	var desire := String(attributes.get("desire", "")).strip_edges()
	if personality.is_empty() or desire.is_empty():
		return {}
	var identity_labels: Array[String] = []
	for value: Variant in soul_profile.get("special_identities", []) as Array:
		if value is Dictionary:
			var label := String((value as Dictionary).get("label", "")).strip_edges()
			if not label.is_empty():
				identity_labels.append(label)
	var identity_summary := ""
	if not identity_labels.is_empty():
		identity_summary = "；特殊身份：%s" % "、".join(identity_labels)
	return {
		"sourceEventIds": [],
		"sourceKind": "resident_profile_motive",
		"summary": (
			"性格：%s；欲望：%s%s" % [personality, desire, identity_summary]
		).replace("\n", " ").left(120),
		"conversationId": "",
	}

static func empty_conflict_projection() -> Dictionary:
	return {
		"revision": 0,
		"activeConflicts": [],
		"injuries": [],
		"tensions": [],
		"events": [],
	}
