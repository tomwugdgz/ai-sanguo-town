class_name AgentContractWake
extends RefCounted
## AgentContract 拆分模块(批次C之4,纯搬运+跨模块调用改类前缀)。


static func _initialization_has_place(initialization: Dictionary, place_name: String) -> bool:
	var places: Variant = initialization.get("places", [])
	if typeof(places) != TYPE_ARRAY:
		return false
	for value: Variant in places:
		if typeof(value) == TYPE_DICTIONARY and String((value as Dictionary).get("name", "")) == place_name:
			return true
	return false


static func _initialization_has_resident(
	initialization: Dictionary,
	resident_id: String,
) -> bool:
	for resident_value: Variant in initialization.get("residents", []) as Array:
		if (
			resident_value is Dictionary
			and String((resident_value as Dictionary).get(
				"resident_id",
				"",
			)) == resident_id
		):
			return true
	return false


static func _wake_has_prop_verb(wake_packet: Dictionary, prop_name: String, verb: String) -> bool:
	var snapshot: Dictionary = wake_packet.get("snapshot", {})
	var place: Dictionary = snapshot.get("place", {})
	var props: Array = place.get("props", [])
	for value: Variant in props:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var prop := value as Dictionary
		if String(prop.get("name", "")) == prop_name and verb in (prop.get("verbs", []) as Array):
			return true
	return false


static func _wake_has_activity(
	wake_packet: Dictionary,
	activity_id: String,
) -> bool:
	var snapshot: Dictionary = wake_packet.get("snapshot", {})
	var place: Dictionary = snapshot.get("place", {})
	for value: Variant in place.get("activities", []) as Array:
		if (
			typeof(value) == TYPE_DICTIONARY
			and String(
				(value as Dictionary).get("activity_id", "")
			) == activity_id
		):
			return true
	return false


static func _wake_has_nearby_person(wake_packet: Dictionary, target_resident_id: String) -> bool:
	var snapshot: Dictionary = wake_packet.get("snapshot", {})
	var nearby: Array = snapshot.get("nearby", [])
	for value: Variant in nearby:
		if (
			typeof(value) == TYPE_DICTIONARY
			and String((value as Dictionary).get("resident_id", "")) == target_resident_id
		):
			return true
	return false


static func _current_conversation_id(wake_packet: Dictionary) -> String:
	var snapshot: Dictionary = wake_packet.get("snapshot", {})
	var conversation: Variant = snapshot.get("conversation")
	if typeof(conversation) != TYPE_DICTIONARY:
		return ""
	return String((conversation as Dictionary).get("conversation_id", ""))


static func _current_action_id(wake_packet: Dictionary) -> String:
	var snapshot: Dictionary = wake_packet.get("snapshot", {})
	var me: Dictionary = snapshot.get("me", {})
	var current_action: Variant = me.get("current_action")
	if typeof(current_action) != TYPE_DICTIONARY:
		return ""
	return String((current_action as Dictionary).get("action_id", ""))


static func _wake_requires_reply(wake_packet: Dictionary) -> bool:
	var current_conversation_id := _current_conversation_id(wake_packet)
	if current_conversation_id.is_empty():
		return false
	var requires_reply := false
	var events: Array = wake_packet.get("events", [])
	for value: Variant in events:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event := value as Dictionary
		if String(event.get("conversation_id", "")) != current_conversation_id:
			continue
		if event.get("type") == "搭话" and bool(event.get("response_required", true)):
			requires_reply = true
		elif event.get("type") == "对方答话":
			requires_reply = true
		elif event.get("type") == "对话结束":
			requires_reply = false
	return requires_reply


static func _wake_requires_initial_invitation_reply(wake_packet: Dictionary) -> bool:
	var current_conversation_id := _current_conversation_id(wake_packet)
	if current_conversation_id.is_empty():
		return false
	for value: Variant in wake_packet.get("events", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event := value as Dictionary
		if (
			String(event.get("conversation_id", "")) == current_conversation_id
			and String(event.get("type", "")) == "搭话"
			and bool(event.get("response_required", true))
		):
			return true
	return false


static func _wake_allows_reply(wake_packet: Dictionary) -> bool:
	var current_conversation_id := _current_conversation_id(wake_packet)
	if current_conversation_id.is_empty():
		return false
	var allows_reply := false
	var events: Array = wake_packet.get("events", [])
	for value: Variant in events:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var event := value as Dictionary
		if String(event.get("conversation_id", "")) != current_conversation_id:
			continue
		var event_type := String(event.get("type", ""))
		if event_type in ["搭话", "对方答话"]:
			allows_reply = true
		elif event_type == "对话结束":
			allows_reply = false
	return allows_reply


static func _available_photo_refs(wake_packet: Dictionary) -> Dictionary:
	var refs := {}
	var snapshot: Dictionary = wake_packet.get("snapshot", {})
	var conversation: Variant = snapshot.get("conversation")
	if typeof(conversation) == TYPE_DICTIONARY:
		_collect_photo_refs_from_turns((conversation as Dictionary).get("turns", []), refs)
	var events: Array = wake_packet.get("events", [])
	for event_value: Variant in events:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event := event_value as Dictionary
		if typeof(event.get("turn")) == TYPE_DICTIONARY:
			_collect_photo_refs_from_turns([event["turn"]], refs)
		if typeof(event.get("turns")) == TYPE_ARRAY:
			_collect_photo_refs_from_turns(event["turns"], refs)
	return refs


static func _collect_photo_refs_from_turns(turns_value: Variant, refs: Dictionary) -> void:
	if typeof(turns_value) != TYPE_ARRAY:
		return
	for turn_value: Variant in turns_value as Array:
		if typeof(turn_value) != TYPE_DICTIONARY:
			continue
		var photos: Variant = (turn_value as Dictionary).get("photos", [])
		if typeof(photos) != TYPE_ARRAY:
			continue
		for photo_value: Variant in photos as Array:
			if typeof(photo_value) == TYPE_DICTIONARY:
				var ref := String((photo_value as Dictionary).get("ref", ""))
				if not ref.is_empty():
					refs[ref] = true


static func _is_valid_clock(clock: String) -> bool:
	if clock.length() != 5 or clock[2] != ":":
		return false
	if not clock.substr(0, 2).is_valid_int() or not clock.substr(3, 2).is_valid_int():
		return false
	var hour := int(clock.substr(0, 2))
	var minute := int(clock.substr(3, 2))
	return hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59
