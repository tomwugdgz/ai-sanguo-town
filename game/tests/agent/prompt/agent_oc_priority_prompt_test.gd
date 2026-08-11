extends "res://tests/agent/support/AgentPromptTestCase.gd"


func _initialize() -> void:
	var compiler_script := _load_prompt_compiler()
	if compiler_script == null:
		_finish_prompt_test("AGENT_OC_PRIORITY_PROMPT_PASS")
		return
	var initialization := _initialization()
	var me := initialization.get("me", {}) as Dictionary
	var attributes := me.get("attributes", {}) as Dictionary
	attributes["gender"] = "女"
	attributes["desire"] = "想把夜间花房经营成只接待熟客的地方"
	attributes["personality"] = "警惕陌生人，但会保护答应过的人"
	attributes["speech"] = "说话简短，先问对方有没有证据"
	attributes["interests"] = ["园艺"]
	attributes["customInterests"] = ["夜间观星", "旧地图"]
	me["social_state"] = {"home": "林岚的住家", "job": "花房店员", "workplace": "花房咖啡馆"}
	me["soul_profile"] = {
		"analysis_version": 1,
		"source_text": "牧师；保护唐小满",
		"special_identities": [{"identity_id": "priest", "label": "牧师", "evidence": "牧师", "confidence": "high"}],
		"relationship_hints": [{
			"target_resident_id": "resident-tang-xiao-man",
			"stance": "protective",
			"tags": ["保护"],
			"summary": "唐小满：保护",
			"evidence": "保护唐小满",
			"confidence": "high",
			"status": "unconfirmed",
		}],
	}
	var compiler: RefCounted = compiler_script.new(initialization)
	var request: Dictionary = compiler.call("compile", _wake_packet("oc-priority-1", "晴天"), "")
	var messages := request.get("messages", []) as Array
	_expect_equal(messages.size(), 2, "OC priority request has system and dynamic messages")
	if messages.size() == 2:
		var user_text := String(messages[1].get("content", ""))
		_expect(user_text.contains("<oc_priority>") and user_text.contains("</oc_priority>"), "每次决策都有独立 OC 优先区")
		_expect(user_text.contains("夜间观星") and user_text.contains("旧地图"), "玩家自定义兴趣进入每次行为判断")
		_expect(user_text.contains("职业：花房店员") and user_text.contains("性别：女"), "职业和性别进入每次行为判断")
		_expect(user_text.contains("说话方式：说话简短") and user_text.contains("开局识别的特殊身份：牧师"), "三条设定和特殊身份进入每次行为判断")
		_expect(user_text.contains("必须优先参考的完整 OC"), "提示词明确要求 OC 优先于普通默认行为")
	_finish_prompt_test("AGENT_OC_PRIORITY_PROMPT_PASS")
