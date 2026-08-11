class_name ProviderLiveTestCase
extends "res://tests/agent/support/AgentTestCase.gd"


const AgentContractScript := preload("res://agent/AgentContract.gd")
const AgentPromptCompilerScript := preload("res://agent/prompt/AgentPromptCompiler.gd")
const CatalogScript := preload("res://agent/model/ModelProviderCatalog.gd")
const TestCli := preload("res://tests/agent/support/AgentTestCli.gd")
const ValidationDataScript := preload("res://tests/support/ProviderLiveValidationData.gd")

var _live_options: Dictionary = {}
var _live_catalog: RefCounted
var _live_data: RefCounted
var _live_report: Dictionary = {}


class RequestCollector:
	extends RefCounted

	signal completed

	var has_value := false
	var value: Dictionary = {}

	func collect(result: Dictionary) -> void:
		has_value = true
		value = result.duplicate(true)
		completed.emit()


func _initialize() -> void:
	call_deferred("_run_live_suite")


func _live_provider_id() -> String:
	return ""


func _run_live_suite() -> void:
	_live_options = TestCli.parse_options(OS.get_cmdline_user_args())
	_live_catalog = CatalogScript.new()
	_live_data = ValidationDataScript.new()
	var provider_id := _live_provider_id()
	_live_report = {
		"schema": "agent-provider-live-test/v1",
		"provider_id": provider_id,
		"started_at": Time.get_datetime_string_from_system(),
		"connectivity": [],
		"behavior": [],
	}
	var descriptor: Dictionary = _live_catalog.call("descriptor", provider_id)
	_expect(not descriptor.is_empty(), "联网测试引用已注册的 Provider")
	_expect(descriptor.get("external") == true, "联网测试只运行外部 Provider")
	if descriptor.is_empty() or descriptor.get("external") != true:
		_finish_live_suite()
		return
	if _live_options.has("connectivity-only") and _live_options.has("behavior-only"):
		_expect(false, "--connectivity-only 与 --behavior-only 不能同时使用")
		_finish_live_suite()
		return
	if _live_options.has("list-only"):
		print("PROVIDER_LIVE_PLAN provider=%s models=%d" % [
			provider_id,
			(_live_catalog.call("list_models", provider_id) as Array).size(),
		])
		quit(0)
		return

	var selected_model_id := String(_live_options.get("model", "")).strip_edges()
	if not _live_options.has("behavior-only"):
		var matched_model := selected_model_id.is_empty()
		for model_value: Variant in _live_catalog.call("list_models", provider_id) as Array:
			var model := model_value as Dictionary
			if not selected_model_id.is_empty() and model.get("id") != selected_model_id:
				continue
			matched_model = true
			var connectivity: Dictionary = await _run_connectivity_case(provider_id, model)
			(_live_report["connectivity"] as Array).append(connectivity)
		_expect(matched_model, "--model 必须属于当前 Provider")

	var default_model_id := selected_model_id
	if default_model_id.is_empty():
		default_model_id = String(_live_catalog.call("default_model_id", provider_id))
	if not _live_options.has("connectivity-only") and not default_model_id.is_empty():
		await _run_behavior_cases(provider_id, default_model_id)
	_finish_live_suite()


func _run_connectivity_case(provider_id: String, model: Dictionary) -> Dictionary:
	var model_id := String(model.get("id", ""))
	_set_assertion_context({
		"provider_id": provider_id,
		"model_id": model_id,
		"stage": "connectivity",
	})
	var creation := _create_live_model(provider_id, model_id, 128)
	_expect_ok(creation, "Catalog 创建真实模型")
	if creation.get("ok") != true:
		return {"model_id": model_id, "ok": false, "errors": creation.get("errors", [])}
	var provider: RefCounted = creation["provider"]
	var configuration_errors: Array = provider.call("validate_configuration")
	_expect_equal(configuration_errors, [], "真实模型环境变量和端点配置完整")
	if not configuration_errors.is_empty():
		return {"model_id": model_id, "ok": false, "errors": configuration_errors}
	var request: Dictionary = _live_data.call("connectivity_request", provider_id, model_id)
	var result: Dictionary = await _request_live(provider, request)
	_expect_equal(result.get("ok"), true, "真实模型返回合法 JSON 对象")
	var response := result.get("decision", {}) as Dictionary
	_expect_equal(response.get("probe"), "ok", "真实模型返回连通性标记")
	_expect_equal(response.get("provider_id"), provider_id, "真实模型返回当前 Provider id")
	_expect_equal(response.get("model_id"), model_id, "真实模型返回当前 Model id")
	await _live_delay()
	return {
		"model_id": model_id,
		"ok": result.get("ok") == true
			and response.get("probe") == "ok"
			and response.get("provider_id") == provider_id
			and response.get("model_id") == model_id,
		"diagnostic": _diagnostic_summary(provider),
	}


func _run_behavior_cases(provider_id: String, model_id: String) -> void:
	var creation := _create_live_model(provider_id, model_id, 1024)
	_set_assertion_context({
		"provider_id": provider_id,
		"model_id": model_id,
		"stage": "behavior_setup",
	})
	_expect_ok(creation, "Catalog 创建行为验证模型")
	if creation.get("ok") != true:
		return
	var provider: RefCounted = creation["provider"]
	var configuration_errors: Array = provider.call("validate_configuration")
	_expect_equal(configuration_errors, [], "行为验证模型配置完整")
	if not configuration_errors.is_empty():
		return
	var initialization: Dictionary = _live_data.call("initialization")
	var compiler: RefCounted = AgentPromptCompilerScript.new(initialization)
	_expect_equal(compiler.call("get_load_errors"), [], "行为测试提示词加载成功")
	for case_value: Variant in _live_data.call("behavior_cases") as Array:
		var case_data := case_value as Dictionary
		var wake := case_data["wake_packet"] as Dictionary
		_set_assertion_context({
			"provider_id": provider_id,
			"model_id": model_id,
			"stage": "behavior",
			"case_id": case_data.get("id", ""),
		})
		var compiled := compiler.call("compile", wake, "") as Dictionary
		var compile_errors: Array = compiled.get("errors", []) as Array
		if compiled.get("ok") == false and compile_errors.is_empty():
			compile_errors.append("模型输入组装失败")
		_expect_equal(compile_errors, [], "真实模型行为用例提示词组装成功")
		if compiled.get("ok") == false:
			continue
		var result: Dictionary = await _request_live(provider, compiled)
		_expect_equal(result.get("ok"), true, "真实模型返回居民决定 JSON")
		var decision := result.get("decision", {}) as Dictionary
		var contract_errors: Array[String] = []
		if result.get("ok") == true:
			contract_errors = AgentContractScript.validate_decision(
				decision,
				initialization,
				wake,
				{},
			)
		_expect_equal(contract_errors, [], "真实模型决定通过 Agent JSON 契约")
		var expected := case_data.get("expected", {}) as Dictionary
		var expectation_mismatches := TestFormat.subset_differences(expected, decision)
		var contract_ok: bool = result.get("ok") == true and contract_errors.is_empty()
		(_live_report["behavior"] as Array).append({
			"case_id": case_data.get("id", ""),
			"ok": contract_ok,
			"contract_ok": contract_ok,
			"expectation_match": expectation_mismatches.is_empty(),
			"expected": expected.duplicate(true),
			"decision": decision.duplicate(true),
			"contract_errors": contract_errors,
			"expectation_mismatches": expectation_mismatches,
			"diagnostic": _diagnostic_summary(provider),
		})
		await _live_delay()


func _create_live_model(
	provider_id: String,
	model_id: String,
	max_tokens: int,
) -> Dictionary:
	var config := {
		"max_tokens": max_tokens,
		"record_limit": 2,
		"timeout_seconds": float(_live_options.get("timeout-seconds", 90.0)),
	}
	var env_file_path := String(_live_options.get("env-file", "")).strip_edges()
	if not env_file_path.is_empty():
		config["env_file_path"] = env_file_path
	return _live_catalog.call("create_model", provider_id, model_id, root, config) as Dictionary


func _request_live(provider: RefCounted, model_request: Dictionary) -> Dictionary:
	var collector := RequestCollector.new()
	provider.call("request_decision", model_request, collector.collect)
	if not collector.has_value:
		await collector.completed
	return collector.value.duplicate(true)


func _live_delay() -> void:
	var delay_ms := maxi(int(_live_options.get("delay-ms", 250)), 0)
	if delay_ms > 0:
		await create_timer(float(delay_ms) / 1000.0).timeout


func _diagnostic_summary(provider: RefCounted) -> Dictionary:
	var diagnostics: Array = provider.call("get_diagnostics")
	if diagnostics.is_empty():
		return {}
	var latest := diagnostics[-1] as Dictionary
	var result: Dictionary = {}
	for key: String in [
		"status_code",
		"elapsed_ms",
		"finish_reason",
		"error_type",
		"retryable",
		"provider_error_code",
		"usage",
	]:
		if latest.has(key):
			result[key] = latest[key]
	return result


func _finish_live_suite() -> void:
	_clear_assertion_context()
	_live_report["finished_at"] = Time.get_datetime_string_from_system()
	_live_report["failures"] = _failures.duplicate()
	var connectivity := _live_report.get("connectivity", []) as Array
	var behavior := _live_report.get("behavior", []) as Array
	_live_report["summary"] = {
		"connectivity_total": connectivity.size(),
		"connectivity_passed": _count_records(connectivity, "ok"),
		"behavior_total": behavior.size(),
		"behavior_contract_passed": _count_records(behavior, "contract_ok"),
		"behavior_expectation_matched": _count_records(behavior, "expectation_match"),
		"failed": _failures.size(),
	}
	_write_live_report()
	if _failures.is_empty():
		print("PROVIDER_LIVE_PASS provider=%s connectivity=%d behavior=%d expectation_matched=%d" % [
			_live_provider_id(),
			connectivity.size(),
			behavior.size(),
			int((_live_report["summary"] as Dictionary)["behavior_expectation_matched"]),
		])
		quit(0)
		return
	for failure: String in _failures:
		printerr(failure)
	quit(1)


func _count_records(records: Array, key: String) -> int:
	var count := 0
	for record_value: Variant in records:
		if (record_value as Dictionary).get(key) == true:
			count += 1
	return count


func _write_live_report() -> void:
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var output_path := project_root.path_join(
		".tmp/agent-tests/%s-live.json" % _live_provider_id()
	)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK:
		_record_failure(
			"联网测试报告目录创建失败",
			"write_report",
			OK,
			directory_error,
		)
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_record_failure(
			"联网测试报告文件打开失败",
			"write_report",
			OK,
			FileAccess.get_open_error(),
		)
		return
	file.store_string(JSON.stringify(_live_report, "  ") + "\n")
