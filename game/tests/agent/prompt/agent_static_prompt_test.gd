extends "res://tests/agent/support/AgentPromptTestCase.gd"


func _initialize() -> void:
	var compiler_script := _load_prompt_compiler()
	if compiler_script != null:
		_expect(_script_has_method(compiler_script, "get_load_errors"), "Prompt Compiler 暴露文件加载错误")
		_test_static_prompt_is_loaded_from_ordered_files(compiler_script)
		_test_project_prompt_covers_specs(compiler_script)
	_finish_prompt_test("AGENT_STATIC_PROMPT_PASS")


func _test_static_prompt_is_loaded_from_ordered_files(compiler_script: Script) -> void:
	_write_fixture("rules/20_second.md", "### 第二条规则\n\n第二条测试规则。")
	_write_fixture("rules/10_first.md", "### 第一条规则\n\n第一条测试规则。")
	_write_fixture("background/10_town.md", "### 测试背景\n\n测试小镇背景。")
	var compiler: RefCounted = compiler_script.new(_initialization(), _fixture_root)
	_expect_equal(compiler.call("get_load_errors"), [], "complete prompt file layers load without errors")
	var request: Dictionary = compiler.call("compile", _wake_packet("file-prompt-1", "晴天"), "")
	var messages := request.get("messages", []) as Array
	_expect_equal(messages.size(), 2, "file-backed prompt still compiles two messages")
	if messages.size() != 2:
		return
	var system_text := String(messages[0].get("content", ""))
	var first_rule_at := system_text.find("第一条测试规则。")
	var second_rule_at := system_text.find("第二条测试规则。")
	var background_at := system_text.find("测试小镇背景。")
	_expect(system_text.contains("# 居民决策基线"), "compiled baseline uses a Markdown document title")
	_expect(system_text.contains("## 行为与决策规则"), "rule files are grouped under a Markdown section")
	_expect(system_text.contains("## 小镇公共背景"), "background files are grouped under a Markdown section")
	_expect(system_text.contains("<rules>") and system_text.contains("</rules>"), "rules keep a stable XML boundary around their Markdown content")
	_expect(system_text.contains("<background>") and system_text.contains("</background>"), "background keeps a stable XML boundary around its Markdown content")
	_expect(first_rule_at >= 0 and first_rule_at < second_rule_at, "rule files are assembled by filename order")
	_expect(second_rule_at < background_at, "rules are assembled before stable background facts")
	_expect(not system_text.contains("你是住在这个小镇上的居民"), "injected file root replaces the project prompt assets")
	var missing_compiler: RefCounted = compiler_script.new(_initialization(), _fixture_root.path_join("missing"))
	_expect(not (missing_compiler.call("get_load_errors") as Array).is_empty(), "missing prompt layers expose initialization errors")
	var empty_root := _fixture_root.path_join("empty-file")
	_write_fixture_at(empty_root, "rules/10_empty.md", "")
	_write_fixture_at(empty_root, "background/10_town.md", "### 测试背景\n\n测试小镇背景。")
	var empty_compiler: RefCounted = compiler_script.new(_initialization(), empty_root)
	_expect(not (empty_compiler.call("get_load_errors") as Array).is_empty(), "empty prompt files expose initialization errors")

func _test_project_prompt_covers_specs(compiler_script: Script) -> void:
	var compiler: RefCounted = compiler_script.new(_initialization())
	var request: Dictionary = compiler.call("compile", _wake_packet("spec-prompt-1", "小雨"), "")
	var messages := request.get("messages", []) as Array
	_expect_equal(messages.size(), 2, "spec-backed prompt compiles system and dynamic messages")
	if messages.size() != 2:
		return
	var system_text := String(messages[0].get("content", ""))
	_expect(system_text.contains("镇上的每个居民你都认识"), "world background includes the complete familiar-town fact")
	_expect(
		system_text.contains("玩家或居民发布的公告会传到每个居民那里"),
		"world background defines global announcement delivery",
	)
	_expect(system_text.contains("想成为的自己"), "soul rules include desired self-image")
	_expect(system_text.contains("被戳穿"), "soul rules include accountability for prior speech")
	_expect(
		system_text.contains("不要机械重复同一句等待"),
		"life decisions explicitly avoid a repeated-wait dead loop",
	)
	_expect(
		system_text.contains("把这个机会纳入考虑"),
		"nearby relationship opportunities enter autonomous decisions",
	)
	_expect(
		system_text.contains("当作生活节律，不是强制日程表"),
		"home and work create a flexible daily rhythm instead of a scripted schedule",
	)
	_expect(
		system_text.contains("不要默认整天留在工作地"),
		"daily needs and rhythm explicitly reopen the choice of public places",
	)
	_expect(
		system_text.contains("天气明显变化时"),
		"weather changes explicitly enter resident action choices",
	)
	_expect(
		system_text.contains("不必总是友好客套"),
		"fact-grounded disagreement is part of ordinary resident conversation",
	)
	_expect(
		system_text.contains("只能引用其中已经确认的场景对象"),
		"environment descriptions and available props form a closed set of facts",
	)
	_expect(
		system_text.contains("待着”只表示不依赖场景对象"),
		"waiting cannot invent an environmental prop",
	)
	_expect(
		system_text.contains("收到“搭话”事件时"),
		"decision rules explain how an incoming conversation is handled",
	)
	_expect(system_text.contains("completed、interrupted、rejected、replaced"), "world-result rules explain every action result status")
	_expect(
		system_text.contains("不论 `say` 是否为空"),
		"conversation-ending narration rule matches the world contract",
	)
	_expect(system_text.contains("错误示例"), "rules include negative examples")
	_expect(system_text.contains("正确示例"), "rules include positive examples")
	_expect(system_text.contains("\"handling\":\"continue_current\""), "decision examples contain legal JSON")
	_expect(not system_text.contains("`{\""), "JSON object examples never use inline code")
	_expect(system_text.count("```json") >= 8, "every decision and result JSON example uses a fenced code block")
