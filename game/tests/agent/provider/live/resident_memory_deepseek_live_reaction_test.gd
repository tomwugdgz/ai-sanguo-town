extends SceneTree


const AGENT_SYSTEM := preload("res://agent/AgentSystem.gd")
const GATEWAY := preload("res://world/integration/TownWorldAgentGateway.gd")
const CATALOG := preload("res://agent/model/ModelProviderCatalog.gd")
const SETTINGS := preload(
	"res://world/presentation/ui/TownProviderSettingsService.gd"
)
const CLEANER := preload("res://tests/support/UserTestDataCleaner.gd")

const RESIDENT_ID := "resident-lin-lan"
const TANG_XIAOMAN_ID := "resident_tang_xiaoman_01"
const WIFE_MEMORY_KEY := "memory-deepseek-live-wife-reaction"
const CONTROL_MEMORY_KEY := "memory-deepseek-live-control-reaction"
const WIFE_MEMORY := "唐小满是我老婆"
const CONTROL_MEMORY := "你是个npc，被我操控着"

var _test_root := "user://tests/resident-memory-deepseek-live/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]
var _failures: Array[String] = []


class MemoryWorld:
	func get_time() -> Dictionary:
		return {"day": 4, "period": "下午", "clock": "15:20"}

	func get_world_revision() -> int:
		return 12

	func get_resident_state(_resident_id: String) -> Dictionary:
		return {"doing": "在工作坊整理木架"}


class DecisionCollector:
	signal completed

	var value: Dictionary = {}
	var has_value := false

	func collect(result: Dictionary) -> void:
		if has_value:
			return
		has_value = true
		value = result.duplicate(true)
		completed.emit()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var settings: RefCounted = SETTINGS.new()
	var saved := settings.call("load_saved_runtime_configuration") as Dictionary
	if saved.get("ok") != true:
		printerr("DEEPSEEK_MEMORY_REACTION_UNAVAILABLE: saved provider config unavailable")
		quit(2)
		return
	var provider_configs := saved.get("providerConfigs", {}) as Dictionary
	var deepseek_config := provider_configs.get("deepseek", {}) as Dictionary
	var model_id := "deepseek-v4-flash"
	if String(saved.get("providerId", "")) == "deepseek":
		model_id = String(saved.get("modelId", model_id))
	if deepseek_config.is_empty():
		printerr("DEEPSEEK_MEMORY_REACTION_UNAVAILABLE: DeepSeek is not configured")
		quit(2)
		return

	var request_host := Node.new()
	request_host.name = "DeepSeekMemoryReactionRequestHost"
	root.add_child(request_host)
	var catalog: RefCounted = CATALOG.new()
	var creation := catalog.call(
		"create_model",
		"deepseek",
		model_id,
		request_host,
		deepseek_config,
	) as Dictionary
	if creation.get("ok") != true:
		printerr("DEEPSEEK_MEMORY_REACTION_UNAVAILABLE: model creation failed")
		request_host.queue_free()
		quit(2)
		return
	var provider := creation.get("provider") as RefCounted
	var configuration_errors := provider.call("validate_configuration") as Array
	if not configuration_errors.is_empty():
		printerr("DEEPSEEK_MEMORY_REACTION_UNAVAILABLE: DeepSeek configuration invalid")
		request_host.queue_free()
		quit(2)
		return

	var agent: RefCounted = AGENT_SYSTEM.new()
	var storage := agent.call(
		"configure_test_runtime_storage",
		_test_root,
	) as Dictionary
	_expect_ok(storage, "real AgentSystem uses isolated live-test storage")
	var save_context := {
		"slot_id": "resident-memory-deepseek-live-%d" % Time.get_ticks_usec(),
		"session_id": "resident-memory-deepseek-live-%d" % Time.get_ticks_usec(),
		"save_revision": 0,
	}
	_expect_ok(agent.call("start_new_game", save_context) as Dictionary, "live Agent starts")
	_expect_ok(
		agent.call("initialize_resident", _initialization(), provider) as Dictionary,
		"live resident initializes with DeepSeek",
	)
	_expect_ok(agent.call("finish_new_game") as Dictionary, "live Agent session becomes ready")

	var gateway: Node = GATEWAY.new()
	gateway.set("_agent_system", agent)
	gateway.set("_world", MemoryWorld.new())
	gateway.set("_session_active", true)
	var connected_ids: Array[String] = [RESIDENT_ID]
	gateway.set("_connected_resident_ids", connected_ids)
	gateway.set("_resident_name_by_id", {RESIDENT_ID: "林岚"})

	_expect_ok(
		gateway.call("get_resident_memory", RESIDENT_ID) as Dictionary,
		"gateway reads the live resident memory",
	)
	_expect_ok(
		gateway.call(
			"apply_resident_memory_intervention",
			RESIDENT_ID,
			{
				"memoryKey": WIFE_MEMORY_KEY,
				"operation": "write",
				"playerText": "我认识唐小满。",
				"expectedRevision": 0,
			},
		) as Dictionary,
		"live memory write applies",
	)
	_expect_ok(
		gateway.call(
			"apply_resident_memory_intervention",
			RESIDENT_ID,
			{
				"memoryKey": WIFE_MEMORY_KEY,
				"operation": "edit",
				"playerText": WIFE_MEMORY,
				"expectedRevision": 1,
			},
		) as Dictionary,
		"live memory edit applies",
	)
	_expect_ok(
		gateway.call(
			"apply_resident_memory_intervention",
			RESIDENT_ID,
			{
				"memoryKey": CONTROL_MEMORY_KEY,
				"operation": "write",
				"playerText": CONTROL_MEMORY,
				"expectedRevision": 2,
			},
		) as Dictionary,
		"live control memory write applies",
	)

	var wake := {
		"decision_id": "deepseek-memory-reaction",
		"snapshot": {
			"time": {"day": 4, "period": "下午", "clock": "15:20"},
			"weather": "晴天",
			"me": {
				"doing": "在工作坊整理木架",
				"current_action": null,
				"body": {"困": "不困", "饿": "不饿", "累": "不累"},
			},
			"nearby": [{
				"resident_id": TANG_XIAOMAN_ID,
				"name": "唐小满",
				"doing": "站在工作坊门口等林岚",
			}],
			"place": {"name": "工作坊", "props": []},
			"conversation": {
				"conversation_id": "deepseek-memory-conversation",
				"with_resident_id": TANG_XIAOMAN_ID,
				"with": "唐小满",
				"turns": [{
					"turn_id": 1,
					"speaker_resident_id": TANG_XIAOMAN_ID,
					"speaker": "唐小满",
					"say": "林岚，你还记得我们是什么关系吗？",
					"narration": "她站在工作坊门口看着林岚",
					"photos": [],
				}],
			},
		},
		"events": [{
			"event_id": "deepseek-memory-conversation-turn",
			"time": {"day": 4, "clock": "15:20", "period": "下午"},
			"type": "搭话",
			"conversation_id": "deepseek-memory-conversation",
			"turn": {
				"turn_id": 1,
				"speaker_resident_id": TANG_XIAOMAN_ID,
				"speaker": "唐小满",
				"say": "林岚，你还记得我们是什么关系吗？",
				"narration": "她站在工作坊门口看着林岚",
				"photos": [],
			},
		}],
		"action_results": [],
	}
	var collector := DecisionCollector.new()
	var started := agent.call(
		"request_decision",
		RESIDENT_ID,
		wake,
		collector.collect,
	) as Dictionary
	_expect_ok(started, "real resident decision request starts")
	if not collector.has_value:
		await collector.completed
	if not collector.has_value:
		_failures.append("DeepSeek decision did not complete")
	else:
		var result := collector.value
		if result.get("ok") != true:
			_failures.append("DeepSeek decision failed: %s" % result)
		else:
			var decision := result.get("decision", {}) as Dictionary
			var action := decision.get("action", {}) as Dictionary
			var spoken := String(action.get("say", ""))
			print(
				"DEEPSEEK_NPC_REACTION: decision=%s actionType=%s place=%s say=%s narration=%s"
				% [
					String(decision.get("decision_id", "")),
					String(action.get("type", "")),
					String(action.get("place", "")),
					spoken,
					String(action.get("narration", "")),
				],
			)
			if action.is_empty():
				_failures.append("DeepSeek returned an empty NPC action")
			elif String(action.get("type", "")) != "答话":
				_failures.append(
					"DeepSeek did not react to Tang Xiaoman's conversation: %s" % action,
				)
			elif spoken.strip_edges().is_empty() and String(action.get("narration", "")).strip_edges().is_empty():
				_failures.append("DeepSeek returned an empty conversation reaction")
			var model_requests := provider.call("get_model_requests") as Array
			var prompt_text := JSON.stringify(model_requests[-1]) if not model_requests.is_empty() else ""
			for expected_memory: String in [WIFE_MEMORY, CONTROL_MEMORY]:
				if not prompt_text.contains(expected_memory):
					_failures.append(
						"DeepSeek request did not contain memory: %s" % expected_memory,
					)

			var natural_action_id := String(action.get("action_id", ""))
			var natural_wake := {
				"decision_id": "deepseek-memory-natural-reaction",
				"snapshot": {
					"time": {"day": 4, "period": "下午", "clock": "15:30"},
					"weather": "晴天",
					"me": {
						"doing": "在工作坊整理木架",
						"current_action": null,
						"body": {"困": "不困", "饿": "不饿", "累": "不累"},
					},
					"nearby": [{
						"resident_id": TANG_XIAOMAN_ID,
						"name": "唐小满",
						"doing": "站在工作坊门口等林岚",
					}],
					"place": {"name": "工作坊", "props": []},
					"conversation": null,
				},
				"events": [],
				"action_results": [{
					"action_id": natural_action_id,
					"status": "completed",
					"reason": "林岚回应了唐小满。",
					"time": {"day": 4, "period": "下午", "clock": "15:25"},
				}],
			}
			var natural_collector := DecisionCollector.new()
			var natural_started := agent.call(
				"request_decision",
				RESIDENT_ID,
				natural_wake,
				natural_collector.collect,
			) as Dictionary
			_expect_ok(natural_started, "natural memory reaction request starts")
			if not natural_collector.has_value:
				await natural_collector.completed
			if not natural_collector.has_value:
				_failures.append("DeepSeek natural memory decision did not complete")
			else:
				var natural_result := natural_collector.value
				if natural_result.get("ok") != true:
					_failures.append(
						"DeepSeek natural memory decision failed: %s" % natural_result,
					)
				else:
					var natural_decision := natural_result.get("decision", {}) as Dictionary
					var natural_action := natural_decision.get("action", {}) as Dictionary
					print(
						"DEEPSEEK_NATURAL_REACTION: actionType=%s target=%s place=%s line=%s say=%s narration=%s"
						% [
							String(natural_action.get("type", "")),
							String(natural_action.get("target_resident_id", "")),
							String(natural_action.get("place", "")),
							String(natural_action.get("line", "")),
							String(natural_action.get("say", "")),
							String(natural_action.get("narration", "")),
						],
					)
					if natural_action.is_empty():
						_failures.append("DeepSeek returned an empty natural memory action")
					var natural_requests := provider.call("get_model_requests") as Array
					var natural_prompt := JSON.stringify(natural_requests[-1]) if not natural_requests.is_empty() else ""
					for expected_memory: String in [WIFE_MEMORY, CONTROL_MEMORY]:
						if not natural_prompt.contains(expected_memory):
							_failures.append(
								"DeepSeek natural request did not contain memory: %s" % expected_memory,
							)

	if not CLEANER.remove_tree(_test_root):
		_failures.append("live test storage root was not removed")
	gateway.free()
	request_host.queue_free()
	agent.call("delete_game", save_context)
	agent.call("close_game")
	if _failures.is_empty():
		print("DEEPSEEK_MEMORY_REACTION_PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error("DEEPSEEK_MEMORY_REACTION_FAIL: %s" % failure)
	quit(1)


func _initialization() -> Dictionary:
	return {
		"me": {
			"resident_id": RESIDENT_ID,
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
			"resident_id": TANG_XIAOMAN_ID,
			"name": "唐小满",
			"gender": "女",
			"age": 29,
			"job": "杂货店主",
			"home": "唐小满家",
			"workplace": "独立市集",
		}],
		"places": [
			{
				"name": "市集",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "居民交换物品的地方",
			},
			{
				"name": "工作坊",
				"type": "公共地点",
				"owner": null,
				"owner_resident_id": null,
				"summary": "居民制作和整理木架的地方",
			},
		],
	}


func _expect_ok(result: Dictionary, message: String) -> void:
	if result.get("ok") != true:
		_failures.append("%s (actual=%s)" % [message, result])
