extends SceneTree


const RUN_ENV := "AI_TOWN_RUN_CURRENT_FORMAL_REAL_MULTIDAY"
const PHASE_ENV := "AI_TOWN_REAL_MULTIDAY_PHASE"
const SPEED_ENV := "AI_TOWN_REAL_MULTIDAY_SPEED"
const DAYS_ENV := "AI_TOWN_REAL_MULTIDAY_DAYS"
const WAIT_MSEC_ENV := "AI_TOWN_REAL_MULTIDAY_WAIT_MSEC"
const STARTUP_SCENE := preload("res://ui/startup/StartupScreen.tscn")
const POST_SAVE_SETTLE_MSEC := 12_000
const SHUTDOWN_DRAIN_MSEC := 45_000

var _failures: Array[String] = []
var _gateway: Node
var _real_results: Array[Dictionary] = []
var _active_conversation_max := 0
var _announcement_max := 0
var _conversation_follow_up_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment(RUN_ENV) != "1":
		print("TOWN_CURRENT_FORMAL_REAL_MULTIDAY_SKIP: set %s=1" % RUN_ENV)
		quit(0)
		return
	var host := root.get_node_or_null("GameFlowHost")
	_expect(host != null, "正式 GameFlowHost 已加载")
	if host == null:
		_finish()
		return
	var startup := STARTUP_SCENE.instantiate()
	root.add_child(startup)
	current_scene = startup
	host.call("_bind_current_scene")
	await _wait_frames(5)
	var catalog := host.call("_startup_catalog_snapshot") as Dictionary
	var continue_slot := catalog.get("continueSlot", {}) as Dictionary
	_expect(bool(catalog.get("ok", false)), "真实存档目录可读取")
	_expect(
		String(continue_slot.get("slotId", "")) == "town-main"
		and bool(continue_slot.get("continueAvailable", false)),
		"真实 town-main 可继续",
	)
	if not _failures.is_empty():
		_print_startup_failure(catalog)
		_finish()
		return
	var before_revision := int(
		(continue_slot.get("summary", {}) as Dictionary).get(
			"saveRevision",
			0,
		)
	)
	_expect(
		bool(startup.call("request_continue_to_host")),
		"正式启动页 Continue 发出真实 intent",
	)
	if not await _wait_for_town_and_gateway(host):
		_print_startup_failure(catalog)
		_finish()
		return
	var runtime := current_scene
	var world := runtime.call("get_world_runtime") as RefCounted
	var identities := runtime.call("get_resident_identity_snapshot") as Dictionary
	_expect(
		String((runtime.call("get_lifecycle_state") as Dictionary).get(
			"state",
			"",
		)) == "running",
		"真实存档恢复后 World 正在运行",
	)
	_expect(
		(identities.get("residents", []) as Array).size() == 15,
		"真实存档恢复 15 位居民",
	)
	_expect(
		(_gateway.call("get_connected_resident_ids") as Array).size() == 15,
		"真实存档恢复 15 个 Agent 连接",
	)
	var callback := Callable(self, "_on_real_decision_completed")
	if not _gateway.is_connected("debug_decision_completed", callback):
		_gateway.connect("debug_decision_completed", callback)
	var restored_time := world.call("get_time") as Dictionary
	var start_day := int(restored_time.get("day", 0))
	if OS.get_environment(PHASE_ENV) == "restore_check":
		_expect(start_day > 1, "自动存档后的新进程恢复到后续日")
		_print_report(host, world, before_revision, start_day, "restore_check")
		await _cleanup(host)
		call_deferred("_finish")
		return
	var simulation_speed := _environment_int(SPEED_ENV, 1, 1, 3)
	var day_count := _environment_int(DAYS_ENV, 1, 1, 30)
	var wait_msec := _environment_int(
		WAIT_MSEC_ENV,
		maxi(
			900_000,
			ceili(float(day_count * 1_800_000) / float(simulation_speed)),
		),
		60_000,
		86_400_000,
	)
	var speed_result := world.call(
		"set_simulation_speed",
		simulation_speed,
	) as Dictionary
	_expect(
		bool(speed_result.get("ok", false)),
		"正式真实链切换到 %d 倍速" % simulation_speed,
	)
	var target_day := start_day + day_count
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < wait_msec:
		_track_world_observations(world)
		if _has_final_gateway_error():
			break
		var auto_save := host.call("get_daily_auto_save_diagnostics") as Dictionary
		if (
			int(auto_save.get("lastSavedDay", -1)) >= target_day
			and (_gateway.get("_inflight") as Dictionary).is_empty()
		):
			break
		await process_frame
	var auto_save := host.call("get_daily_auto_save_diagnostics") as Dictionary
	if (auto_save.get("failures", []) as Array).size() > 0:
		print(
			"TOWN_CURRENT_FORMAL_REAL_MULTIDAY_AUTO_SAVE_FAILURES: %s"
			% JSON.stringify(auto_save.get("failures")),
		)
		if host != null:
			var service_value: Variant = host.get("_session_ui_service")
			if service_value is Node and is_instance_valid(service_value as Node):
				var service_state := (service_value as Node).call("get_state") as Dictionary
				print(
					"TOWN_CURRENT_FORMAL_REAL_MULTIDAY_AUTO_SAVE_LAST_RESULT: %s"
					% JSON.stringify(service_state.get("lastResult", {})),
				)
	_expect(
		(auto_save.get("failures", []) as Array).is_empty(),
		"每日自动存档没有失败记录：%s"
		% JSON.stringify(_safe_auto_save(auto_save)),
	)
	_expect(
		int(auto_save.get("lastRevision", 0)) > before_revision,
		"每日自动存档发布新 revision：before=%d after=%d"
		% [before_revision, int(auto_save.get("lastRevision", 0))],
	)
	await _wait_msec(POST_SAVE_SETTLE_MSEC)
	_track_world_observations(world)
	_print_report(host, world, before_revision, target_day, "run")
	await _cleanup(host)
	call_deferred("_finish")


func _wait_for_town_and_gateway(host: Node) -> bool:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < 150_000:
		var gateway_value: Variant = host.get("_gateway")
		if (
			_gateway == null
			and gateway_value is Node
			and is_instance_valid(gateway_value)
		):
			_gateway = gateway_value as Node
		if (
			current_scene != null
			and current_scene.name == "TownRuntime"
			and _gateway != null
		):
			return true
		await process_frame
	_failures.append("真实 Continue 未在等待窗口进入 Town")
	return false


func _on_real_decision_completed(trace: Dictionary) -> void:
	var agent_result := trace.get("agentResult", {}) as Dictionary
	var decision := agent_result.get("decision", {}) as Dictionary
	var action := decision.get("action", {}) as Dictionary
	var follow_up: Variant = decision.get("conversation_follow_up", {})
	if follow_up is Dictionary and not (follow_up as Dictionary).is_empty():
		_conversation_follow_up_count += 1
	_real_results.append({
		"residentId": String(trace.get("residentId", "")),
		"ok": bool(trace.get("ok", false)),
		"actionType": String(action.get("type", "")),
		"stale": bool(
			(trace.get("worldSubmission", {}) as Dictionary).get(
				"stale",
				false,
			)
		),
	})


func _track_world_observations(world: RefCounted) -> void:
	_active_conversation_max = maxi(
		_active_conversation_max,
		(world.call("get_active_conversations") as Array).size(),
	)
	_announcement_max = maxi(
		_announcement_max,
		(world.call("get_announcements") as Array).size(),
	)


func _print_report(
	host: Node,
	world: RefCounted,
	before_revision: int,
	target_day: int,
	phase: String,
) -> void:
	var auto_save := host.call("get_daily_auto_save_diagnostics") as Dictionary
	var gateway_errors := _gateway.call("get_errors") as Array
	var unhandled := 0
	var fallback_decision_ids: Dictionary = {}
	var gateway_error_codes := {}
	for value: Variant in gateway_errors:
		if not value is Dictionary:
			continue
		var error := value as Dictionary
		var code := String(error.get("errorCode", ""))
		gateway_error_codes[code] = int(gateway_error_codes.get(code, 0)) + 1
		if code == "AGENT_CONTINUITY_FALLBACK_APPLIED":
			fallback_decision_ids[String(error.get("decisionId", ""))] = true
	for value: Variant in gateway_errors:
		if value is Dictionary and bool((value as Dictionary).get("final", false)):
			unhandled += 1
	var fallback_count := fallback_decision_ids.size()
	if phase == "run":
		_expect(
			unhandled == 0,
			"真实运行没有未处理的最终错误：%d" % unhandled,
		)
	print(
		"TOWN_CURRENT_FORMAL_REAL_MULTIDAY_REPORT: %s"
		% JSON.stringify({
			"phase": phase,
			"beforeRevision": before_revision,
			"targetDay": target_day,
			"time": world.call("get_time"),
			"realDecisionCount": _real_results.size(),
			"realDecisionOkCount": _successful_real_result_count(),
			"worldSubmissionStaleCount": _stale_result_count(),
			"activeConversationMax": _active_conversation_max,
			"conversationFollowUpCount": _conversation_follow_up_count,
			"announcementMax": _announcement_max,
			"continuityFallbackCount": fallback_count,
			"continuityFallbackRate": (
				float(fallback_count) / float(maxi(_real_results.size(), 1))
			),
			"autoSave": _safe_auto_save(auto_save),
			"gatewayErrorCodes": gateway_error_codes,
			"requestMetrics": _gateway.call("get_request_metrics"),
			"unhandledFinalErrors": unhandled,
		})
	)


func _has_final_gateway_error() -> bool:
	if _gateway == null or not is_instance_valid(_gateway):
		return false
	for error_value: Variant in _gateway.call("get_errors") as Array:
		if error_value is Dictionary and bool((error_value as Dictionary).get("final", false)):
			return true
	return false


func _safe_auto_save(value: Dictionary) -> Dictionary:
	return {
		"lastSavedDay": int(value.get("lastSavedDay", -1)),
		"attempts": int(value.get("attempts", 0)),
		"successes": int(value.get("successes", 0)),
		"lastRevision": int(value.get("lastRevision", 0)),
		"failureCount": (value.get("failures", []) as Array).size(),
	}


func _successful_real_result_count() -> int:
	var count := 0
	for result: Dictionary in _real_results:
		if bool(result.get("ok", false)):
			count += 1
	return count


func _stale_result_count() -> int:
	var count := 0
	for result: Dictionary in _real_results:
		if bool(result.get("stale", false)):
			count += 1
	return count


func _cleanup(host: Node) -> void:
	if is_instance_valid(host) and host.has_method("request_quit_game"):
		# The auto-save has already been published. Do not create a second save or
		# expose a departure failure while the diagnostic process exits.
		host.set("_quit_departure_pending", false)
	if is_instance_valid(host) and host.has_method("_prepare_audio_shutdown"):
		host.call("_prepare_audio_shutdown")
	var runtime := current_scene
	if runtime != null and is_instance_valid(runtime):
		runtime.set_process(false)
		runtime.set_physics_process(false)
		var drain_started_at := Time.get_ticks_msec()
		while (
			_gateway != null
			and is_instance_valid(_gateway)
			and not (_gateway.get("_inflight") as Dictionary).is_empty()
			and Time.get_ticks_msec() - drain_started_at < SHUTDOWN_DRAIN_MSEC
		):
			await process_frame
	# This diagnostic process does not use the normal quit route because that
	# route intentionally performs another player departure save. Tear down the
	# runtime scene explicitly so its Gateway, HTTP requests and World refs leave
	# the tree before SceneTree.quit reports resource leaks.
	if runtime != null and is_instance_valid(runtime):
		runtime.queue_free()
	current_scene = null
	if is_instance_valid(host) and host.has_method("_discard_pending_runtime"):
		host.call("_discard_pending_runtime")
	if is_instance_valid(host):
		if host.has_method("_unmount_town_overlays"):
			host.call("_unmount_town_overlays")
		if host.has_method("_release_internal_session_refs"):
			host.call("_release_internal_session_refs")
	await _wait_frames(3)


func _wait_frames(count: int) -> void:
	for _index in count:
		await process_frame


func _wait_msec(duration: int) -> void:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < duration:
		await process_frame


func _environment_int(
	name: String,
	fallback: int,
	minimum: int,
	maximum: int,
) -> int:
	var text_value := OS.get_environment(name).strip_edges()
	if text_value.is_empty() or not text_value.is_valid_int():
		return fallback
	return clampi(int(text_value), minimum, maximum)


func _print_startup_failure(catalog: Dictionary) -> void:
	print("TOWN_CURRENT_FORMAL_REAL_MULTIDAY_STARTUP_FAILURE: %s" % JSON.stringify({
		"catalogOk": bool(catalog.get("ok", false)),
		"errorCode": String(catalog.get("errorCode", "")),
	}))


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error(label)


func _finish() -> void:
	if _failures.is_empty():
		print("TOWN_CURRENT_FORMAL_REAL_MULTIDAY_PASS")
		quit(0)
		return
	printerr("TOWN_CURRENT_FORMAL_REAL_MULTIDAY_FAIL: %s" % "; ".join(_failures))
	quit(1)
