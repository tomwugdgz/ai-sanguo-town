extends "res://tests/agent/support/AgentTestCase.gd"


const SessionScript := preload("res://agent/debug/AgentDebugSession.gd")


class HealthGateProvider:
	extends RefCounted

	var health_requested := false

	func configure(_config: Variant, _host: Variant = null) -> Dictionary:
		return {"ok": true, "errorCode": "", "retryable": false}

	func request_health_check(
		_targets: Variant,
		_callback: Variant = Callable(),
	) -> Dictionary:
		health_requested = true
		return {
			"ok": true,
			"accepted": true,
			"status": "checking",
			"errorCode": "",
			"retryable": false,
		}

	func get_health_snapshot() -> Dictionary:
		return {"ok": true, "providers": []}

	func list_available_models() -> Array[Dictionary]:
		return []

	func validate_resident_bindings(_bindings: Variant) -> Dictionary:
		return (
			{"ok": true, "errorCode": "", "retryable": false}
			if health_requested
			else {
				"ok": false,
				"errorCode": "SESSION_LLM_BINDINGS_INVALID",
				"retryable": false,
			}
		)

	func check_entry_availability(
		_bindings: Variant,
		_callback: Variant = Callable(),
	) -> Dictionary:
		return {"ok": true, "errorCode": "", "retryable": false}


class HealthGateSession:
	extends AgentDebugSession

	var provider := HealthGateProvider.new()

	func _create_provider_service() -> RefCounted:
		return provider

	func _load_saved_provider_runtime() -> Dictionary:
		return {
			"ok": true,
			"errorCode": "",
			"providerConfigs": {
				"deepseek": {"api_key": "test-key"},
			},
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live_session := HealthGateSession.new()
	root.add_child(live_session)
	var live_started := live_session.start_new(
		"deepseek",
		"deepseek-v4-flash",
		"agent-debug-health-gate",
	) as Dictionary
	_expect_equal(
		live_started.get("accepted"),
		true,
		"真实 Provider 初始化先进入健康检查而不是被绑定校验立即拒绝",
	)
	_expect_equal(
		live_session.provider.health_requested,
		true,
		"真实 Provider 初始化调用正式健康检查",
	)
	live_session.stop()
	live_session.queue_free()
	await process_frame

	var session: Node = SessionScript.new()
	root.add_child(session)
	var accepted := session.call(
		"start_new",
		"fake",
		"fake",
		"agent-debug-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()],
	) as Dictionary
	_expect_equal(accepted.get("accepted"), true, "DEBUGUI 通过正式 Bootstrap 启动")
	for _frame in 180:
		if String((session.call("snapshot") as Dictionary).get("status", "")) != "starting":
			break
		await process_frame
	var snapshot := session.call("snapshot") as Dictionary
	_expect_equal(snapshot.get("status"), "running", "正式 Town Runtime 启动完成")
	_expect_equal(snapshot.get("residentCount"), 15, "观察台连接全部 15 位居民")
	var residents := snapshot.get("residents", []) as Array
	if not residents.is_empty():
		var resident_id := String((residents[0] as Dictionary).get("residentId", ""))
		var debug := session.call("resident_debug_snapshot", resident_id) as Dictionary
		_expect(not (debug.get("initialization", {}) as Dictionary).is_empty(), "可查看 World 初始化资料")
		_expect(debug.get("memory") is Dictionary, "可查看正式 Memory System 快照")
		_expect(debug.get("provider") is Dictionary, "可查看居民正式 Provider 记录")
		var conversation := session.call(
			"begin_avatar_conversation",
			resident_id,
			"今天过得怎么样？",
		) as Dictionary
		_expect_ok(conversation, "人工测试由旅行者化身通过正式对话命令发起")
		for _frame in 120:
			if int(session.call("pending_decision_count")) == 0:
				break
			await process_frame
		var reply := session.call(
			"begin_avatar_conversation",
			resident_id,
			"那你接下来有什么计划？",
		) as Dictionary
		_expect_ok(reply, "同居民下一轮等待正式 Agent 回复后继续")
		for _frame in 120:
			if int(session.call("pending_decision_count")) == 0:
				break
			await process_frame
		if residents.size() > 1:
			var another_id := String(
				(residents[1] as Dictionary).get("residentId", ""),
			)
			var switched := session.call(
				"begin_avatar_conversation",
				another_id,
				"也来听听你的想法。",
			) as Dictionary
			_expect_ok(switched, "切换居民时通过正式命令收束上一段对话")
			for _frame in 120:
				if int(session.call("pending_decision_count")) == 0:
					break
				await process_frame
	snapshot = session.call("snapshot") as Dictionary
	_expect(
		int(snapshot.get("traceCount", 0)) > 0,
		"初始 World WakePacket 产生可观察决策记录",
	)
	var completed_trace: Dictionary = {}
	for trace_value: Variant in session.call("traces") as Array:
		var trace := trace_value as Dictionary
		if String(trace.get("phase", "")) == "completed":
			completed_trace = trace
			break
	_expect(
		not (completed_trace.get("wakePacket", {}) as Dictionary).is_empty(),
		"已完成记录仍保留对应 WakePacket",
	)
	_expect_equal(
		session.call("pending_decision_count"),
		0,
		"Fake Provider 决策完成后无在途请求",
	)
	var saved := session.call("create_save") as Dictionary
	_expect_ok(saved, "调试会话使用正式 World/Agent 双组件存档")
	var save_snapshot := session.call("save_snapshot") as Dictionary
	_expect_equal(
		(save_snapshot.get("manifests", []) as Array).size(),
		1,
		"观察台显示已发布存档清单",
	)
	var restored := session.call("restore_latest") as Dictionary
	_expect_ok(restored, "调试会话接受最近存档恢复请求")
	for _frame in 180:
		if String((session.call("snapshot") as Dictionary).get("status", "")) != "restoring":
			break
		await process_frame
	var restored_snapshot := session.call("snapshot") as Dictionary
	_expect_equal(restored_snapshot.get("status"), "running", "恢复后正式 World 重新运行")
	_expect_ok(
		restored_snapshot.get("lastRestoreResult", {}) as Dictionary,
		"World 与 15 位居民 Agent 保存点成对恢复",
	)
	session.call("stop")
	await process_frame
	_finish_suite("AGENT_DEBUG_LAB_TEST_PASS")
