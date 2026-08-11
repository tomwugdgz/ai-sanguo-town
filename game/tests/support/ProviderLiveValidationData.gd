class_name ProviderLiveValidationData
extends RefCounted


const AgentDebugScenariosScript := preload("res://agent/debug/AgentDebugScenarios.gd")


func connectivity_request(provider_id: String, model_id: String) -> Dictionary:
	return {
		"request_kind": "provider_connectivity_probe",
		"messages": [
			{
				"role": "system",
				"content": "你是 API 连通性探针。只返回合法 JSON 对象，不要 Markdown。",
			},
			{
				"role": "user",
				"content": (
					"请原样返回：{\"probe\":\"ok\",\"provider_id\":\"%s\",\"model_id\":\"%s\"}"
					% [provider_id, model_id]
				),
			},
		],
		"max_tokens": 128,
	}


func initialization() -> Dictionary:
	var data: Dictionary = AgentDebugScenariosScript.new().initialization()
	(data["places"] as Array).append({
		"name": "林岚家",
		"type": "住家",
		"owner": "林岚",
		"owner_resident_id": "resident-lin-lan",
		"summary": "林岚休息、吃饭和躲避恶劣天气的住处",
	})
	return data


func behavior_cases() -> Array[Dictionary]:
	return [
		_reply_required_case(),
		_eat_when_hungry_case(),
		_seek_storm_shelter_case(),
		_continue_current_work_case(),
		_answer_workshop_notice_case(),
	]


func _reply_required_case() -> Dictionary:
	var packet := _base_packet("reply-required", "09:05", "上午")
	var turn := {
		"turn_id": 1,
		"speaker_resident_id": "resident-tang-xiao-man",
		"speaker": "唐小满",
		"say": "木架修好了吗？下午市集要用。",
		"narration": "唐小满看着林岚，等他回答。",
		"photos": [],
	}
	packet["snapshot"]["conversation"] = {
		"conversation_id": "conversation-live-reply",
		"with_resident_id": "resident-tang-xiao-man",
		"with": "唐小满",
		"turns": [turn.duplicate(true)],
	}
	packet["events"] = [{
		"event_id": "reply-required-event",
		"type": "对方答话",
		"conversation_id": "conversation-live-reply",
		"turn": turn,
		"time": packet["snapshot"]["time"].duplicate(true),
	}]
	return {
		"id": "reply_required",
		"title": "对方问话后必须答话",
		"wake_packet": packet,
		"expected": {
			"handling": "replace_current",
			"action": {
				"type": "答话",
				"conversation_id": "conversation-live-reply",
			},
		},
	}


func _eat_when_hungry_case() -> Dictionary:
	var packet := _base_packet("eat-when-hungry", "12:20", "中午")
	packet["snapshot"]["me"] = {
		"doing": "在工作坊收拾木料",
		"current_action": null,
		"body": {"困": "不困", "饿": "很饿", "累": "有点累"},
	}
	packet["snapshot"]["nearby"] = []
	packet["snapshot"]["place"] = {
		"name": "工作坊",
		"props": [{"name": "饭盒", "verbs": ["吃饭"]}],
	}
	return {
		"id": "eat_when_hungry",
		"title": "饥饿时使用眼前饭盒",
		"wake_packet": packet,
		"expected": {
			"handling": "replace_current",
			"action": {"type": "用道具", "prop": "饭盒", "verb": "吃饭"},
		},
	}


func _seek_storm_shelter_case() -> Dictionary:
	var packet := _base_packet("seek-storm-shelter", "15:10", "下午")
	packet["snapshot"]["weather"] = "雷暴"
	packet["snapshot"]["me"]["doing"] = "站在没有遮挡的广场上"
	packet["events"] = [{
		"event_id": "storm-event",
		"type": "天气变了",
		"weather": "雷暴",
		"time": packet["snapshot"]["time"].duplicate(true),
	}]
	return {
		"id": "seek_storm_shelter",
		"title": "雷暴时前往工作坊避雨",
		"wake_packet": packet,
		"expected": {
			"handling": "replace_current",
			"action": {"type": "去", "place": "工作坊"},
		},
	}


func _continue_current_work_case() -> Dictionary:
	var packet := _base_packet("continue-current-work", "10:00", "上午")
	packet["snapshot"]["me"] = {
		"doing": "在工作坊专心打磨木板",
		"current_action": {
			"action_id": "current-work-action",
			"type": "用道具",
			"prop": "刨子",
			"verb": "打磨木板",
		},
		"body": {"困": "不困", "饿": "不饿", "累": "不累"},
	}
	packet["snapshot"]["nearby"] = []
	packet["snapshot"]["place"] = {
		"name": "工作坊",
		"props": [{"name": "刨子", "verbs": ["打磨木板"]}],
	}
	return {
		"id": "continue_current_work",
		"title": "没有新事件时继续手头工作",
		"wake_packet": packet,
		"expected": {"handling": "continue_current"},
	}


func _answer_workshop_notice_case() -> Dictionary:
	var packet := _base_packet("answer-workshop-notice", "08:40", "上午")
	packet["events"] = [{
		"event_id": "workshop-notice-event",
		"type": "公告发布",
		"announcement_id": "workshop-rack-loose",
		"text": "工作坊的木架松动，请木匠林岚尽快前往检查。",
		"time": packet["snapshot"]["time"].duplicate(true),
	}]
	return {
		"id": "answer_workshop_notice",
		"title": "木匠响应工作坊公告",
		"wake_packet": packet,
		"expected": {
			"handling": "replace_current",
			"action": {"type": "去", "place": "工作坊"},
		},
	}


func _base_packet(decision_id: String, clock: String, period: String) -> Dictionary:
	var packet: Dictionary = AgentDebugScenariosScript.new().wake_packet(
		decision_id,
		1,
		clock,
	)
	packet["snapshot"]["time"]["period"] = period
	return packet
