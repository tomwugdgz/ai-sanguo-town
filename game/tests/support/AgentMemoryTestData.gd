class_name AgentMemoryTestData
extends RefCounted


static func empty_memory() -> Dictionary:
	return {
		"important_memories": "",
		"relationships": "",
		"current_thoughts": "",
		"long_term_goals": "",
		"short_term_goals": "",
	}


static func organized_memory() -> Dictionary:
	return {
		"important_memories": "唐小满（resident-tang-xiao-man）问木架何时完成，我答应明早送过去。",
		"relationships": "唐小满（resident-tang-xiao-man）：她信任我的手艺，我不能让她失望。",
		"current_thoughts": "今晚要把木架收尾。",
		"long_term_goals": "成为守信可靠的木匠。",
		"short_term_goals": "明早把木架送给唐小满。",
	}


static func initialization() -> Dictionary:
	return {
		"me": {
			"resident_id": "resident-lin-lan",
			"attributes": {
				"name": "林岚",
				"gender": "男",
				"age": 32,
				"desire": "把手艺做好",
				"personality": "话少，慢热",
				"speech": "说话简短",
			},
			"social_state": {
				"home": "林岚家",
				"job": "木匠",
				"workplace": "工作坊",
			},
		},
		"residents": [{
			"resident_id": "resident-tang-xiao-man",
			"name": "唐小满",
			"gender": "女",
			"age": 29,
			"job": "摆杂货摊的",
			"home": "唐小满家",
			"workplace": "市集",
		}],
		"places": [
			{
				"name": "中心广场",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "有公告栏、花坛和路灯的石板广场",
				"features": ["公告栏", "花坛", "路灯"],
			},
			{
				"name": "社区花园",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "围着花圃、花树、长椅和路灯的公共花园",
				"features": ["花圃", "花树", "长椅", "路灯"],
			},
		],
	}


static func wake_packet(
	decision_id: String,
	day: int = 1,
	weather: String = "晴天",
) -> Dictionary:
	return {
		"decision_id": decision_id,
		"snapshot": {
			"time": {"day": day, "clock": "08:10", "period": "上午"},
			"weather": weather,
			"me": {
				"doing": "站在中心广场上",
				"current_action": null,
				"body": {"困": "不困", "饿": "不饿", "累": "不累"},
			},
			"nearby": [],
			"place": {"name": "中心广场", "props": []},
			"conversation": null,
		},
		"events": [],
		"action_results": [],
	}


static func event_wake(
	decision_id: String,
	event_id: String,
	day: int = 1,
	event_type: String = "有人来了",
	clock: String = "08:11",
) -> Dictionary:
	var wake := wake_packet(decision_id, day)
	wake["events"] = [{
		"event_id": event_id,
		"time": {"day": day, "clock": clock, "period": "上午"},
		"type": event_type,
		"who_resident_id": "resident-tang-xiao-man",
		"who": "唐小满",
	}]
	return wake


static func conversation_end_wake() -> Dictionary:
	var wake := wake_packet("conversation-end")
	wake["events"] = [{
		"event_id": "conversation-ended-event",
		"time": {"day": 1, "clock": "08:20", "period": "上午"},
		"type": "对话结束",
		"conversation_id": "conversation-1",
		"turns": [
			{
				"turn_id": 1,
				"speaker_resident_id": "resident-tang-xiao-man",
				"speaker": "唐小满",
				"say": "木架明天能好吗？",
				"narration": "",
				"photos": [],
			},
			{
				"turn_id": 2,
				"speaker_resident_id": "resident-lin-lan",
				"speaker": "林岚",
				"say": "我明早送过去。",
				"narration": "",
				"photos": [],
			},
		],
		"reason": "主动结束",
	}]
	return wake


static func stay_decision(decision_id: String, action_id: String) -> Dictionary:
	return {
		"decision_id": decision_id,
		"handling": "replace_current",
		"action": {
			"action_id": action_id,
			"type": "待着",
			"line": "我先想一想。",
		},
	}
