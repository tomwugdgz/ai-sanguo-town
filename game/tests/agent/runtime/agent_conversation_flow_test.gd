extends "res://tests/agent/support/AgentTestCase.gd"


const AgentSystemScript := preload("res://agent/AgentSystem.gd")
const ScriptedModelProviderScript := preload("res://tests/agent/support/ScriptedModelProvider.gd")
const ScenariosScript := preload("res://agent/debug/AgentDebugScenarios.gd")
const UserTestDataCleanerScript := preload("res://tests/support/UserTestDataCleaner.gd")

var _system_index := 0
var _test_root := "user://tests/agent-issue11/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]
var _accepted_action_types: Array[String] = []


class ResultCollector:
	var values: Array[Dictionary] = []

	func collect(value: Dictionary) -> void:
		values.append(value.duplicate(true))


func _initialize() -> void:
	_test_five_atomic_actions_and_resident_conversation()
	_test_player_avatar_uses_opaque_world_identity()
	_finish_suite("AGENT_CONVERSATION_FLOW_PASS", [_test_root])


func _test_five_atomic_actions_and_resident_conversation() -> void:
	var scenarios: RefCounted = ScenariosScript.new()
	var simple_cases := [
		{
			"id": "go",
			"action": {
				"action_id": "issue11-go-action",
				"type": "去",
				"place": "工作坊",
				"line": "去工作坊开工",
			},
		},
		{
			"id": "use-prop",
			"action": {
				"action_id": "issue11-use-prop-action",
				"type": "用道具",
				"prop": "木工台",
				"verb": "加工木料",
				"line": "把松动的木料修好",
			},
		},
		{
			"id": "stay",
			"action": {
				"action_id": "issue11-stay-action",
				"type": "待着",
				"line": "先看看雨势",
			},
		},
		{
			"id": "start-talk",
			"action": {
				"action_id": "issue11-start-talk-action",
				"type": "搭话",
				"target_resident_id": "resident-tang-xiao-man",
				"say": "木板还要修吗？",
				"narration": "我看向唐小满手里的木板",
				"photos": [],
			},
		},
	]

	for case: Dictionary in simple_cases:
		var wake: Dictionary = scenarios.call("wake_packet", "issue11-%s" % case["id"])
		if case["id"] == "use-prop":
			wake["snapshot"]["place"] = {
				"name": "工作坊",
				"props": [{"name": "木工台", "verbs": ["加工木料"]}],
			}
		var decision := {
			"decision_id": wake["decision_id"],
			"handling": "replace_current",
			"action": (case["action"] as Dictionary).duplicate(true),
		}
		var result := _run_once(
			"atomic-%s" % case["id"],
			scenarios.call("initialization"),
			wake,
			decision,
		)
		_record_accepted_action(result, "原子动作 %s" % case["id"])

	var system: RefCounted = _new_system("resident-conversation")
	var model: RefCounted = ScriptedModelProviderScript.new()
	var initialization: Dictionary = scenarios.call("initialization")
	_expect_equal(
		system.call("initialize_resident", initialization, model).get("ok"),
		true,
		"居民对话验收初始化成功",
	)

	var first_turn := _turn(
		1,
		"resident-tang-xiao-man",
		"唐小满",
		"门板的榫头松了，你能看看吗？",
		"她把门板放到木工台旁",
	)
	var first_wake := _talk_wake(
		"issue11-resident-talk-1",
		"issue11-resident-conversation",
		"resident-tang-xiao-man",
		"唐小满",
		[first_turn],
		"搭话",
		first_turn,
		"08:10",
	)
	var first_decision := {
		"decision_id": "issue11-resident-talk-1",
		"handling": "replace_current",
		"action": {
			"action_id": "issue11-resident-reply-1",
			"type": "答话",
			"conversation_id": "issue11-resident-conversation",
			"say": "放到台子上，我看看。",
			"narration": "我走到木工台前",
			"photos": [],
			"end": false,
		},
	}
	model.call("queue_decision", first_decision)
	var first_result := _request(system, first_wake, "居民发起搭话后能够答话")
	_record_accepted_action(first_result, "居民首次答话")

	var second_turn := _turn(
		2,
		"resident-lin-lan",
		"林岚",
		"放到台子上，我看看。",
		"我走到木工台前",
	)
	var third_turn := _turn(
		3,
		"resident-tang-xiao-man",
		"唐小满",
		"就是这处接缝。",
		"她指了指松动的榫头",
	)
	var second_wake := _talk_wake(
		"issue11-resident-talk-2",
		"issue11-resident-conversation",
		"resident-tang-xiao-man",
		"唐小满",
		[first_turn, second_turn, third_turn],
		"对方答话",
		third_turn,
		"08:12",
	)
	second_wake["action_results"] = [{
		"action_id": "issue11-resident-reply-1",
		"status": "completed",
		"reason": "答话动作已提交",
		"time": {"day": 1, "clock": "08:11", "period": "上午"},
	}]
	var ending_decision := {
		"decision_id": "issue11-resident-talk-2",
		"handling": "replace_current",
		"action": {
			"action_id": "issue11-resident-reply-2",
			"type": "答话",
			"conversation_id": "issue11-resident-conversation",
			"say": "看清了，这处接缝确实松了。",
			"narration": "我点点头，转身拿起木工工具",
			"photos": [],
			"end": true,
		},
	}
	model.call("queue_decision", ending_decision)
	var ending_result := _request(system, second_wake, "收到对方答话后能够主动结束")
	_expect_equal(
		ending_result.get("decision", {}).get("action", {}).get("end"),
		true,
		"多轮对话以 end=true 主动结束",
	)

	_expect_equal(
		_accepted_action_types,
		["去", "用道具", "待着", "搭话", "答话"],
		"五种原子动作均通过 AgentSystem 正式接缝",
	)


func _test_player_avatar_uses_opaque_world_identity() -> void:
	var scenarios: RefCounted = ScenariosScript.new()
	var player_turn := _turn(
		1,
		"person-avatar-7",
		"阿澈",
		"这块木料能今天修好吗？",
		"阿澈把木料放到工作台边",
	)
	var wake := _talk_wake(
		"issue11-avatar-talk",
		"issue11-avatar-conversation",
		"person-avatar-7",
		"阿澈",
		[player_turn],
		"搭话",
		player_turn,
		"09:00",
	)
	var decision := {
		"decision_id": "issue11-avatar-talk",
		"handling": "replace_current",
		"action": {
			"action_id": "issue11-avatar-reply",
			"type": "答话",
			"conversation_id": "issue11-avatar-conversation",
			"say": "能，午前给你。",
			"narration": "我看了看木料的裂口",
			"photos": [],
			"end": false,
		},
	}
	var system: RefCounted = _new_system("player-avatar")
	var model: RefCounted = ScriptedModelProviderScript.new()
	_expect_equal(
		system.call("initialize_resident", scenarios.call("initialization"), model).get("ok"),
		true,
		"玩家化身对话验收初始化成功",
	)
	model.call("queue_decision", decision)
	var result := _request(system, wake, "玩家化身搭话沿用普通人物对话链")
	_expect_equal(result.get("decision"), decision, "玩家化身搭话得到规范答话")

	var requests: Array = model.call("get_requests")
	_expect_equal(requests.size(), 1, "玩家化身搭话只产生一次模型决定请求")
	if requests.size() == 1:
		var request_wake := (requests[0] as Dictionary).get("wake_packet", {}) as Dictionary
		var conversation := request_wake.get("snapshot", {}).get("conversation", {}) as Dictionary
		_expect_equal(
			conversation.get("with_resident_id"),
			"person-avatar-7",
			"模型只看到世界分配的不透明人物 ID",
		)
		_expect_equal(conversation.get("with"), "阿澈", "模型看到世界内名字")
		_expect(not request_wake.has("player_id"), "唤醒包不暴露玩家系统字段")
		_expect(
			not JSON.stringify(request_wake).contains("is_player"),
			"人物资料不携带玩家身份标记",
		)


func _run_once(
	suffix: String,
	initialization: Dictionary,
	wake: Dictionary,
	decision: Dictionary,
) -> Dictionary:
	var system: RefCounted = _new_system(suffix)
	var model: RefCounted = ScriptedModelProviderScript.new()
	_expect_equal(
		system.call("initialize_resident", initialization, model).get("ok"),
		true,
		"%s 初始化成功" % suffix,
	)
	model.call("queue_decision", decision)
	return _request(system, wake, "%s 决定通过" % suffix)


func _request(system: RefCounted, wake: Dictionary, message: String) -> Dictionary:
	var collector := ResultCollector.new()
	var acceptance: Dictionary = system.call(
		"request_decision",
		"resident-lin-lan",
		wake,
		collector.collect,
	)
	_expect_equal(
		acceptance.get("ok"),
		true,
		"%s：唤醒包被接受；%s" % [message, JSON.stringify(acceptance)],
	)
	_expect_equal(collector.values.size(), 1, "%s：世界只收到一次回调" % message)
	if collector.values.size() != 1:
		return {}
	var result := collector.values[0]
	_expect_equal(result.get("ok"), true, "%s：决定合法" % message)
	return result


func _record_accepted_action(result: Dictionary, message: String) -> void:
	var action: Dictionary = result.get("decision", {}).get("action", {})
	var action_type := String(action.get("type", ""))
	_expect(not action_type.is_empty(), "%s 返回动作" % message)
	if not action_type.is_empty() and not _accepted_action_types.has(action_type):
		_accepted_action_types.append(action_type)


func _talk_wake(
	decision_id: String,
	conversation_id: String,
	partner_id: String,
	partner_name: String,
	turns: Array,
	event_type: String,
	event_turn: Dictionary,
	clock: String,
) -> Dictionary:
	var scenarios: RefCounted = ScenariosScript.new()
	var wake: Dictionary = scenarios.call("wake_packet", decision_id, 1, clock)
	wake["snapshot"]["nearby"] = [{
		"resident_id": partner_id,
		"name": partner_name,
		"doing": "站在木工台旁",
	}]
	wake["snapshot"]["conversation"] = {
		"conversation_id": conversation_id,
		"with_resident_id": partner_id,
		"with": partner_name,
		"turns": turns.duplicate(true),
	}
	wake["events"] = [{
		"event_id": "%s-event" % decision_id,
		"time": {"day": 1, "clock": clock, "period": "上午"},
		"type": event_type,
		"conversation_id": conversation_id,
		"turn": event_turn.duplicate(true),
	}]
	return wake


func _turn(
	turn_id: int,
	speaker_resident_id: String,
	speaker: String,
	say: String,
	narration: String,
) -> Dictionary:
	return {
		"turn_id": turn_id,
		"speaker_resident_id": speaker_resident_id,
		"speaker": speaker,
		"say": say,
		"narration": narration,
		"photos": [],
	}


func _new_system(suffix: String) -> RefCounted:
	_system_index += 1
	var system: RefCounted = AgentSystemScript.new()
	var configured: Dictionary = system.call(
		"configure_test_runtime_storage",
		"%s/%02d-%s" % [_test_root, _system_index, suffix],
	)
	_expect_equal(configured.get("ok"), true, "%s 使用隔离测试目录" % suffix)
	return system


func _finalize() -> void:
	UserTestDataCleanerScript.remove_tree(_test_root)
