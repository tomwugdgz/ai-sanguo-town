extends "res://tests/agent/support/OpenAICompatibleProviderTestCase.gd"


const PROVIDER_PATH := "res://agent/model/GenericOpenAICompatibleModelProvider.gd"
const ENV_TEST_PATH := "user://openai_compatible_provider_robustness_test.env"


class SilentTransport:
	extends RefCounted

	var requests := 0
	var saved_callback := Callable()

	func request_json(
		_url: String,
		_headers: PackedStringArray,
		_body: Dictionary,
		on_complete: Callable,
	) -> int:
		requests += 1
		saved_callback = on_complete
		return OK


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var provider_script := load(PROVIDER_PATH) as Script
	_expect(provider_script != null, "通用 OpenAI Compatible Provider 脚本可加载")
	if provider_script != null:
		await _test_transport_watchdog_completes_hung_request(provider_script)
		_test_env_file_cache(provider_script)
	_finish_suite("OPENAI_COMPATIBLE_PROVIDER_ROBUSTNESS_PASS")


func _test_transport_watchdog_completes_hung_request(provider_script: Script) -> void:
	var host := Node.new()
	root.add_child(host)
	var transport := SilentTransport.new()
	var provider: RefCounted = provider_script.new(host, transport, {
		"api_key": "watchdog-test-key",
		"endpoint": "https://compatible.example/v1/chat/completions",
		"api_model": "vendor-model",
		"timeout_seconds": 0.05,
	})
	var collector := ResultCollector.new()
	provider.call(
		"request_decision",
		{"messages": [{"role": "user", "content": "决定"}]},
		collector.collect,
	)
	_expect_equal(transport.requests, 1, "挂起的注入 transport 收到请求")
	_expect_equal(collector.values.size(), 0, "看门狗触发前不应有结果")
	await create_timer(0.3).timeout
	_expect_equal(collector.values.size(), 1, "看门狗把挂起请求收敛为恰好一次完成")
	if collector.values.size() == 1:
		_expect_equal(
			collector.values[0],
			{"ok": false, "errors": ["模型调用失败"]},
			"看门狗返回中性失败包",
		)
	var diagnostics := provider.call("get_diagnostics") as Array
	var timeout_entries := diagnostics.filter(
		func(entry: Variant) -> bool:
			return String((entry as Dictionary).get("error_type", "")) == "timeout"
	)
	_expect_equal(timeout_entries.size(), 1, "看门狗记录一条 timeout 诊断")
	if timeout_entries.size() == 1:
		_expect_equal(
			(timeout_entries[0] as Dictionary).get("retryable"),
			true,
			"transport 超时标记为可重试供网关消费",
		)
	if transport.saved_callback.is_valid():
		transport.saved_callback.call(_success_response("late-decision"))
	# 结算 lambda 捕获 provider、provider 又持有 transport，若不断开保存的
	# 回调会形成 RefCounted 引用环并在退出时报资源泄漏。
	transport.saved_callback = Callable()
	_expect_equal(
		collector.values.size(),
		1,
		"看门狗之后迟到的 transport 回复不会二次完成",
	)
	_expect_equal(
		(provider.call("get_diagnostics") as Array).size(),
		1,
		"迟到回复不追加诊断记录",
	)
	_expect_equal(
		(provider.call("get_results") as Array).size(),
		1,
		"迟到回复不追加结果记录",
	)
	_expect_equal(
		(provider.call("get_responses") as Array).size(),
		0,
		"迟到回复不写入响应历史",
	)
	var final_diagnostics := provider.call("get_diagnostics") as Array
	if final_diagnostics.size() == 1:
		var only_diagnostic := final_diagnostics[0] as Dictionary
		_expect_equal(
			only_diagnostic.get("error_type"),
			"timeout",
			"唯一诊断仍是超时",
		)
		_expect_equal(
			only_diagnostic.get("retryable"),
			true,
			"唯一诊断保持可重试供网关消费",
		)
	host.free()


func _test_env_file_cache(provider_script: Script) -> void:
	var provider: RefCounted = provider_script.new(null, null, {})
	var env_file := FileAccess.open(ENV_TEST_PATH, FileAccess.WRITE)
	_expect(env_file != null, "能创建测试用 env 文件")
	if env_file == null:
		return
	env_file.store_string("# comment\nexport TEST_ROBUSTNESS_KEY=\"first-value\"\n")
	env_file.close()
	_expect_equal(
		provider.call("_read_env_value", ENV_TEST_PATH, "TEST_ROBUSTNESS_KEY"),
		"first-value",
		"首次读取解析 env 文件",
	)
	_expect_equal(
		provider.call("_read_env_value", ENV_TEST_PATH, "TEST_ROBUSTNESS_KEY"),
		"first-value",
		"二次读取命中缓存且值一致",
	)
	_expect_equal(
		provider.call("_read_env_value", ENV_TEST_PATH, "MISSING_KEY"),
		"",
		"缓存条目中不存在的键返回空串",
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ENV_TEST_PATH))
	_expect_equal(
		provider.call("_read_env_value", ENV_TEST_PATH, "TEST_ROBUSTNESS_KEY"),
		"",
		"文件删除后不再返回缓存值",
	)
