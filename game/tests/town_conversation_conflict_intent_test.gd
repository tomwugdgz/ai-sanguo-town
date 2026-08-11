extends SceneTree


const SOURCE_DIR := "res://world/data/town/source"
const OPENING_PATH := "res://tests/fixtures/town_world_opening.json"
const BUILDER := preload("res://world/data/town/TownWorldDataBuilder.gd")
const OPENING := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const WORLD := preload("res://world/runtime/TownWorldRuntime.gd")
const CONTRACT := preload("res://agent/AgentContract.gd")
const PROMPT_COMPILER := preload("res://agent/prompt/AgentPromptCompiler.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := BUILDER.build_from_source(SOURCE_DIR)
	var opening_result := OPENING.load_config(OPENING_PATH, data) as Dictionary
	_expect(opening_result.get("ok") == true, "开局资料可加载")
	if opening_result.get("ok") != true:
		_finish()
		return
	var opening := (opening_result.get("config", {}) as Dictionary).duplicate(true)
	_set_resident_outdoor_state(opening, "唐小满", Vector2(3396.0, 2772.0))
	_set_resident_outdoor_state(opening, "阿禾", Vector2(3436.0, 2772.0))
	var world: RefCounted = WORLD.new()
	var started := world.call("start", data, opening) as Dictionary
	_expect(started.get("ok") == true, "World 可启动")
	if started.get("ok") != true:
		_finish()
		return
	var attacker_state := world.call("get_resident_state", "唐小满") as Dictionary
	var target_state := world.call("get_resident_state", "阿禾") as Dictionary
	var attacker_id := String(attacker_state.get("residentId", ""))
	var target_id := String(target_state.get("residentId", ""))
	var attacker_wake := _take_wake(world, "唐小满")
	var talk := {
		"decision_id": String(attacker_wake.get("decision_id", "")),
		"handling": "replace_current",
		"action": {
			"action_id": "talk-for-composite",
			"type": "搭话",
			"target_resident_id": target_id,
			"say": "你刚才是不是故意的？",
			"narration": "走近一步。",
			"photos": [],
		},
	}
	_expect(
		(CONTRACT.validate_decision(talk, world.call("get_agent_initialization", attacker_id) as Dictionary, attacker_wake, {}) as Array).is_empty(),
		"搭话决定符合合同",
	)
	_expect((world.call("submit_agent_decision", "唐小满", talk) as Dictionary).get("status") == "accepted", "World 接受搭话")
	_expire(world)
	var target_wake := _take_wake(world, "阿禾")
	var conversation := (target_wake.get("snapshot", {}) as Dictionary).get("conversation", {}) as Dictionary
	var target_reply := {
		"decision_id": String(target_wake.get("decision_id", "")),
		"handling": "replace_current",
		"action": {
			"action_id": "target-reply-for-composite",
			"type": "答话",
			"conversation_id": String(conversation.get("conversation_id", "")),
			"say": "我没空和你争。",
			"narration": "抬眼看了看。",
			"photos": [],
			"end": false,
		},
	}
	_expect((world.call("submit_agent_decision", "阿禾", target_reply) as Dictionary).get("status") == "accepted", "World 接受对方答话")
	_expire(world)
	var reply_wake := _take_wake(world, "唐小满")
	var reply_snapshot := reply_wake.get("snapshot", {}) as Dictionary
	var attack_option := _find_profile_attack(reply_snapshot.get("conflict_tension_options", []) as Array, target_id)
	_expect(not attack_option.is_empty(), "对话仍在继续时保留当前合法的人设攻击原因")
	var reply_prompt := (PROMPT_COMPILER.new(world.call("get_agent_initialization", attacker_id) as Dictionary) as RefCounted).call("compile", reply_wake, "") as Dictionary
	var reply_constraints := reply_prompt.get("derived_constraints", {}) as Dictionary
	_expect(not (reply_constraints.get("conflict_intent", {}) as Dictionary).is_empty(), "答话提示明确给出可选结构化攻击意图")
	var reply_action := {
		"action_id": "reply-and-attack-reply",
		"type": "答话",
		"conversation_id": String((reply_snapshot.get("conversation", {}) as Dictionary).get("conversation_id", "")),
		"say": "那就别怪我了。",
		"narration": "话说完便收住声音。",
		"photos": [],
		"end": true,
	}
	var composite := {
		"decision_id": String(reply_wake.get("decision_id", "")),
		"handling": "replace_current",
		"action": reply_action,
		"conflict_intent": {
			"action_id": "attack-after-composite-reply",
			"type": "攻击",
			"target_resident_id": target_id,
			"attack_kind": "unarmed",
			"cause_id": String(attack_option.get("option_id", "")),
			"line": "说完便扑上去。",
		},
	}
	var provider_shaped := composite.duplicate(true)
	(provider_shaped["conflict_intent"] as Dictionary)["attack_kind"] = "扑咬"
	(provider_shaped["conflict_intent"] as Dictionary)["cause_id"] = "opaque-cause"
	var normalized_provider := CONTRACT.normalize_model_decision_references(provider_shaped, reply_wake)
	_expect(String((normalized_provider["conflict_intent"] as Dictionary).get("attack_kind", "")) == "unarmed", "对话后的常见攻击说法归一到统一攻击字段")
	_expect(String((normalized_provider["conflict_intent"] as Dictionary).get("cause_id", "")) == String(attack_option.get("option_id", "")), "对话后的攻击原因归一到当前唯一权威选项")
	composite = normalized_provider
	var composite_errors := CONTRACT.validate_decision(
		composite,
		world.call("get_agent_initialization", attacker_id) as Dictionary,
		reply_wake,
		{},
	) as Array
	_expect(composite_errors.is_empty(), "对话收尾加攻击意图符合合同：%s" % JSON.stringify(composite_errors))
	var submitted := world.call("submit_agent_decision", "唐小满", composite) as Dictionary
	_expect(submitted.get("status") == "accepted", "World 接受对话收尾加攻击意图：%s" % JSON.stringify(submitted))
	_expire(world)
	var projection := world.call("get_public_conflict_projection") as Dictionary
	_expect((projection.get("activeConflicts", []) as Array).size() == 1, "对话结束后确实启动正式攻击冲突")
	var conversation_after := world.call("get_conversation", String(reply_action.get("conversation_id", ""))) as Dictionary
	var ended := String(conversation_after.get("status", "")) == "ended"
	_expect(ended, "攻击启动前对话已经原子收尾")
	world.call("stop")
	_finish()


func _find_profile_attack(options: Array, target_id: String) -> Dictionary:
	for value: Variant in options:
		if value is Dictionary and String((value as Dictionary).get("kind", "")) == "attack" and String((value as Dictionary).get("target_resident_id", "")) == target_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _take_wake(world: RefCounted, resident_name: String) -> Dictionary:
	var requests := world.call("take_pending_decision_requests", [resident_name]) as Array
	return {} if requests.is_empty() else ((requests[0] as Dictionary).get("wakePacket", {}) as Dictionary)


func _expire(world: RefCounted) -> void:
	for _step in 6:
		world.call("advance", 0.5)


func _set_resident_outdoor_state(opening: Dictionary, resident_name: String, position: Vector2) -> void:
	for value: Variant in opening.get("residents", []) as Array:
		var resident := value as Dictionary
		if String((resident.get("attributes", {}) as Dictionary).get("name", "")) != resident_name:
			continue
		resident["worldState"] = {
			"place": "社区花园",
			"spaceId": "town_outdoor",
			"regionId": "outdoor_garden_01",
			"position": [position.x, position.y],
			"doing": "在社区花园里",
			"body": {"困": "不困", "饿": "不饿", "累": "不累"},
		}
		return


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	var exit_code := 0 if _failures.is_empty() else 1
	if _failures.is_empty():
		print("TOWN_CONVERSATION_CONFLICT_INTENT_PASS")
	else:
		for failure in _failures:
			push_error(failure)
	for _index in 5:
		await process_frame
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout
	quit(exit_code)
