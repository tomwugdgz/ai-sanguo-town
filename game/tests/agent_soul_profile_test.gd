extends SceneTree


const SOUL := preload("res://agent/soul/AgentSoulProfile.gd")
const AGENT_CONTRACT := preload("res://agent/AgentContract.gd")
const COMPILER := preload("res://agent/prompt/AgentPromptCompiler.gd")
const TEST_DATA := preload("res://tests/support/AgentMemoryTestData.gd")

var _failures: Array[String] = []


func _init() -> void:
	var residents := [
		{
			"residentId": "resident-a",
			"attributes": {
				"name": "阿青",
				"desire": "找到林岚这个仇人算账",
				"personality": "吸血鬼，爱凑热闹打架",
				"speech": "说话冷淡",
			},
		},
		{
			"residentId": "resident-b",
			"attributes": {
				"name": "林岚",
				"desire": "把手艺做好",
				"personality": "慢热",
				"speech": "说话简短",
			},
		},
	]
	var profiles := SOUL.analyze_all(residents)
	var profile := profiles["resident-a"] as Dictionary
	_expect((profile.get("special_identities", []) as Array).size() == 2, "开局应识别吸血鬼和好斗身份", _failures)
	var hints := profile.get("relationship_hints", []) as Array
	_expect(hints.size() == 1, "应识别对指定居民的关系线索", _failures)
	if not hints.is_empty():
		_expect(String((hints[0] as Dictionary).get("target_resident_id", "")) == "resident-b", "关系线索必须绑定稳定 resident_id", _failures)
		_expect(String((hints[0] as Dictionary).get("status", "")) == "unconfirmed", "关系线索不能冒充已发生事实", _failures)
	var initialization := TEST_DATA.initialization()
	(initialization["me"] as Dictionary)["soul_profile"] = profile.duplicate(true)
	_expect(AGENT_CONTRACT.validate_initialization(initialization).is_empty(), "带 soul_profile 的 Agent 初始化应通过合同", _failures)
	var compiler: RefCounted = COMPILER.new(initialization)
	var prompt_result := compiler.call("compile", TEST_DATA.wake_packet("soul-1"), "") as Dictionary
	var messages := prompt_result.get("messages", []) as Array
	var system_text := String((messages[0] as Dictionary).get("content", "")) if not messages.is_empty() else ""
	_expect(system_text.contains("吸血鬼") and system_text.contains("未确认线索"), "OC 私有资料应进入本人提示词", _failures)
	call_deferred("_finish")


func _finish() -> void:
	var exit_code := 0 if _failures.is_empty() else 1
	if _failures.is_empty():
		print("AGENT_SOUL_PROFILE_PASS")
	else:
		for failure in _failures:
			push_error(failure)
	# 该用例在 SceneTree 初始化阶段就完成断言；先让自动加载节点完成 _ready，
	# 再走与正式退出一致的音频释放流程。
	for _index in 5:
		await process_frame
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	await create_timer(0.3, true, false, true).timeout
	quit(exit_code)


func _expect(value: bool, message: String, failures: Array[String]) -> void:
	if not value:
		failures.append(message)
