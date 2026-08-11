class_name TownConversationBubblePlayback
extends RefCounted


## 居民对话气泡的表现层播放状态。
##
## World 的 turns 是唯一事实来源；本模块只记录“已经播到哪一句”和当前
## 气泡的停留时间，不修改对话、事件或日志。这样打开聊天页、关闭聊天页，
## 或 World 在播放最后一句时结束，都不会丢掉气泡播放进度。

const BUBBLE_HOLD_MSEC: int = 1200
const MAX_BUBBLE_DISPLAY_UNITS: float = 18.0
const STRONG_END_MARKS: String = "。！？!?；;"
const CLOSING_MARKS: String = "”’」』）】》〉\"'"

var _states: Dictionary = {}
var _paused: bool = false


func clear() -> void:
	_states.clear()
	_paused = false


func set_paused(value: bool, now_msec: int = -1) -> void:
	var effective_now: int = _effective_now(now_msec)
	if value == _paused:
		return
	if value:
		_paused = true
		for key_value: Variant in _states.keys():
			var conversation_id: String = String(key_value)
			var state: Dictionary = _states.get(conversation_id, {}) as Dictionary
			state["pausedAtMsec"] = effective_now
			_states[conversation_id] = state
		return
	for key_value: Variant in _states.keys():
		var conversation_id: String = String(key_value)
		var state: Dictionary = _states.get(conversation_id, {}) as Dictionary
		var started_at: int = int(state.get("currentStartedAtMsec", 0))
		if started_at > 0:
			state["currentStartedAtMsec"] = started_at + maxi(
				0,
				effective_now - int(state.get("pausedAtMsec", effective_now)),
			)
		state.erase("pausedAtMsec")
		_states[conversation_id] = state
	_paused = false


func ingest(conversation: Dictionary, now_msec: int = -1) -> bool:
	var conversation_id: String = _conversation_id(conversation)
	if conversation_id.is_empty():
		return false
	var effective_now: int = _effective_now(now_msec)
	var state: Dictionary = _states.get(conversation_id, {}) as Dictionary
	var is_new: bool = state.is_empty()
	if is_new:
		state = {
			"conversationId": conversation_id,
			"participantIds": _string_array(conversation.get("participants", [])),
			"participantNames": [],
			"conversationStartedAtMsec": effective_now,
			"segments": [],
			"nextIndex": 0,
			"current": {},
			"currentStartedAtMsec": 0,
			"ended": false,
		}
	else:
		var participants: Array[String] = _string_array(
			conversation.get("participants", [])
		)
		if not participants.is_empty():
			state["participantIds"] = participants

	var new_segments: Array[Dictionary] = _segments_for_conversation(conversation)
	var old_segments: Array = state.get("segments", []) as Array
	var current: Dictionary = state.get("current", {}) as Dictionary
	var current_key: String = String(current.get("key", ""))
	state["segments"] = new_segments
	if not current_key.is_empty():
		var current_index: int = _index_of_segment(new_segments, current_key)
		if current_index >= 0:
			state["current"] = (new_segments[current_index] as Dictionary).duplicate(true)
		else:
			# 正常情况下 turns 只会追加；若恢复数据被截短，按已播放数量
			# 继续，避免重复从第一句开始。
			state["current"] = {}
			state["nextIndex"] = mini(
				int(state.get("nextIndex", 0)),
				new_segments.size(),
			)
	else:
		# 保留已有的 nextIndex，只在首次建立或数据确实变短时夹紧。
		state["nextIndex"] = mini(
			int(state.get("nextIndex", 0)),
			new_segments.size(),
		)
	state["ended"] = String(conversation.get("status", "active")) == "ended"
	if not _paused:
		_start_next_if_needed(state, effective_now)
	_states[conversation_id] = state
	return is_new or old_segments != new_segments or bool(state.get("ended", false))


func advance(now_msec: int = -1) -> bool:
	if _paused:
		return false
	var effective_now: int = _effective_now(now_msec)
	var changed: bool = false
	for key_value: Variant in _states.keys().duplicate():
		var conversation_id: String = String(key_value)
		if not _states.has(conversation_id):
			continue
		var state: Dictionary = _states[conversation_id] as Dictionary
		_start_next_if_needed(state, effective_now)
		var current: Dictionary = state.get("current", {}) as Dictionary
		var started_at: int = int(state.get("currentStartedAtMsec", 0))
		if (
			not current.is_empty()
			and started_at > 0
			and effective_now - started_at >= BUBBLE_HOLD_MSEC
		):
			state["current"] = {}
			state["currentStartedAtMsec"] = 0
			_start_next_if_needed(state, effective_now)
			changed = true
		if (
			bool(state.get("ended", false))
			and (state.get("current", {}) as Dictionary).is_empty()
			and int(state.get("nextIndex", 0)) >= (state.get("segments", []) as Array).size()
		):
			_states.erase(conversation_id)
			changed = true
		else:
			_states[conversation_id] = state
	return changed


func visible_items(now_msec: int = -1) -> Array[Dictionary]:
	advance(now_msec)
	var result: Array[Dictionary] = []
	for key_value: Variant in _states.keys():
		var state: Dictionary = _states.get(String(key_value), {}) as Dictionary
		var current: Dictionary = state.get("current", {}) as Dictionary
		var text: String = String(current.get("text", "")).strip_edges()
		if text.is_empty():
			# 没有可展示的已确认发言时，直接不生成气泡，不显示省略号。
			continue
		var item: Dictionary = {
			"conversationId": String(state.get("conversationId", "")),
			"participantIds": (state.get("participantIds", []) as Array).duplicate(),
			"participantNames": (state.get("participantNames", []) as Array).duplicate(),
			"bubbleText": text,
			"speakerId": String(current.get("speakerId", "")),
			"speakerName": String(current.get("speakerName", "")),
			"turnId": int(current.get("turnId", 0)),
			"segmentIndex": int(current.get("segmentIndex", 0)),
			"bubbleStartedAtMsec": int(state.get("currentStartedAtMsec", 0)),
			"conversationStartedAtMsec": int(state.get("conversationStartedAtMsec", 0)),
			"status": "ended" if bool(state.get("ended", false)) else "active",
		}
		result.append(item)
	return result


func debug_snapshot(conversation_id: String) -> Dictionary:
	return ( _states.get(conversation_id, {}) as Dictionary ).duplicate(true)


func _start_next_if_needed(state: Dictionary, now_msec: int) -> void:
	if not (state.get("current", {}) as Dictionary).is_empty():
		return
	var segments: Array = state.get("segments", []) as Array
	var next_index: int = int(state.get("nextIndex", 0))
	if next_index < 0 or next_index >= segments.size():
		return
	state["current"] = (segments[next_index] as Dictionary).duplicate(true)
	state["nextIndex"] = next_index + 1
	state["currentStartedAtMsec"] = now_msec


func _segments_for_conversation(conversation: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var turns: Array = conversation.get("turns", []) as Array
	for turn_index: int in turns.size():
		if not turns[turn_index] is Dictionary:
			continue
		var turn: Dictionary = turns[turn_index] as Dictionary
		var text: String = String(turn.get("say", "")).strip_edges()
		if text.is_empty():
			continue
		var speaker_name: String = String(turn.get("speaker", "")).strip_edges()
		var speaker_id: String = String(turn.get("speaker_resident_id", "")).strip_edges()
		var turn_id: int = int(turn.get("turn_id", turn_index + 1))
		var pieces: Array[String] = _split_speech(text)
		for segment_index: int in pieces.size():
			result.append({
				"key": "%d:%d:%d" % [turn_index, turn_id, segment_index],
				"turnId": turn_id,
				"segmentIndex": segment_index,
				"speakerId": speaker_id,
				"speakerName": speaker_name,
				"text": pieces[segment_index],
			})
	return result


func _split_speech(value: String) -> Array[String]:
	var normalized: String = value.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
	normalized = normalized.strip_edges()
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	if normalized.is_empty():
		return []
	var sentences: Array[String] = []
	var current: String = ""
	var index: int = 0
	while index < normalized.length():
		var character: String = normalized.substr(index, 1)
		current += character
		if STRONG_END_MARKS.contains(character):
			var next_index: int = index + 1
			while next_index < normalized.length():
				var following: String = normalized.substr(next_index, 1)
				if not CLOSING_MARKS.contains(following):
					break
				current += following
				next_index += 1
				index = next_index - 1
			_flush_sentence(current, sentences)
			current = ""
		index += 1
	_flush_sentence(current, sentences)
	var result: Array[String] = []
	for sentence: String in sentences:
		result.append_array(_split_long_sentence(sentence))
	return result


func _split_long_sentence(value: String) -> Array[String]:
	var result: Array[String] = []
	var current: String = ""
	var units: float = 0.0
	for index: int in value.length():
		var character: String = value.substr(index, 1)
		var character_units: float = 1.0 if value.unicode_at(index) > 0x2E7F else 0.5
		if not current.is_empty() and units + character_units > MAX_BUBBLE_DISPLAY_UNITS:
			result.append(current.strip_edges())
			current = ""
			units = 0.0
		current += character
		units += character_units
	if not current.strip_edges().is_empty():
		result.append(current.strip_edges())
	return result


func _flush_sentence(value: String, target: Array[String]) -> void:
	var normalized: String = value.strip_edges()
	if not normalized.is_empty():
		target.append(normalized)


func _index_of_segment(segments: Array, key: String) -> int:
	for index: int in segments.size():
		var segment: Dictionary = segments[index] as Dictionary
		if String(segment.get("key", "")) == key:
			return index
	return -1


func _conversation_id(conversation: Dictionary) -> String:
	var value: String = String(conversation.get("conversationId", "")).strip_edges()
	if value.is_empty():
		value = String(conversation.get("conversation_id", "")).strip_edges()
	return value


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		var text: String = String(item).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _effective_now(now_msec: int) -> int:
	return now_msec if now_msec >= 0 else Time.get_ticks_msec()
