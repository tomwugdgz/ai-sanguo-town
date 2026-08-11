extends SceneTree


const HOST := preload("res://world/presentation/game_flow/GameFlowHost.gd")
const ASSIGNMENT_SERVICE := preload(
	"res://ui/resident_model_assignment/runtime/ResidentModelAssignmentService.gd"
)


class FakeGateway:
	extends Node
	var bindings: Array = []
	func update_resident_bindings(value: Variant) -> Dictionary:
		bindings = (value as Array).duplicate(true)
		return {"ok": true, "errorCode": "", "retryable": false, "changed": true}


class FakeRuntime:
	extends Node
	var bindings: Array = []
	func update_resident_bindings(value: Variant) -> Dictionary:
		bindings = (value as Array).duplicate(true)
		return {"ok": true, "errorCode": "", "retryable": false, "changed": true}


class FakeSessionService:
	extends RefCounted
	var bindings: Array = []
	var saved := false
	func update_resident_bindings(value: Variant) -> Dictionary:
		bindings = (value as Array).duplicate(true)
		return {"ok": true, "errorCode": "", "retryable": false, "changed": true}
	func create_save(_payload: Dictionary = {}) -> Dictionary:
		saved = true
		return {"ok": true, "errorCode": "", "retryable": false, "saveRevision": 2}


class FakeProviderService:
	extends RefCounted
	func get_health_snapshot() -> Dictionary:
		return {
			"ok": true,
			"formalReady": true,
			"capabilityMode": "formal",
			"source": "runtime",
			"providers": [{
				"providerId": "deepseek",
				"label": "DeepSeek",
				"status": "available",
			}],
		}
	func list_available_models() -> Array:
		return [{
			"providerId": "deepseek",
			"modelId": "deepseek-chat",
			"label": "DeepSeek Chat",
			"available": true,
		}]
	func validate_resident_bindings(_bindings: Variant) -> Dictionary:
		return {"ok": true, "errorCode": "", "retryable": false}


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := HOST.new()
	var gateway := FakeGateway.new()
	var runtime := FakeRuntime.new()
	var session := FakeSessionService.new()
	var previous := [{
		"residentId": "resident-a",
		"llmBinding": {"mode": "model", "providerId": "deepseek", "modelId": "old"},
	}]
	var updated := [{
		"residentId": "resident-a",
		"llmBinding": {"mode": "model", "providerId": "deepseek", "modelId": "new"},
	}]
	host.set("_gateway", gateway)
	host.set("_town_runtime", runtime)
	host.set("_session_ui_service", session)
	host.set("_active_session_config", {"residentBindings": previous})
	var result := host._apply_in_session_resident_model_bindings({}, updated)
	_expect(bool(result.get("ok", false)), "运行中居民模型改绑成功")
	_expect(gateway.bindings == updated, "Agent 网关收到新绑定")
	_expect(runtime.bindings == updated, "小镇运行时收到新绑定")
	_expect(session.bindings == updated and session.saved, "改绑会更新存档并立即保存")
	_test_single_resident_assignment_mode()
	host.set("_gateway", null)
	host.set("_town_runtime", null)
	host.set("_session_ui_service", null)
	host.free()
	gateway.free()
	runtime.free()
	session = null
	for _index in 5:
		await process_frame
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null:
		audio_controller.prepare_shutdown()
	await create_timer(0.3, true, false, true).timeout
	if _failures.is_empty():
		print("RESIDENT_MODEL_REBIND_PASS")
	else:
		for failure in _failures:
			printerr("RESIDENT_MODEL_REBIND_FAIL: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_single_resident_assignment_mode() -> void:
	var service := ASSIGNMENT_SERVICE.new()
	var configured := service.configure(
		FakeProviderService.new(),
		{"residents": [{
			"residentId": "resident-a",
			"attributes": {"name": "入镇测试居民"},
			"presentation": {},
		}]},
		{
			"schemaVersion": 1,
			"sourceScope": "resident_selection",
			"draftRevision": 1,
			"slots": [{
				"residentId": "resident-a",
				"spaceId": "home_01",
				"llmBinding": {},
			}],
		},
		{
			"revision": 1,
			"singleResidentMode": true,
			"allowedSpaceIds": ["home_01"],
		},
	) as Dictionary
	_expect(bool(configured.get("ok", false)), "单居民模型绑定可以配置")
	var view_model := service.get_view_model() as Dictionary
	var data := view_model.get("data", {}) as Dictionary
	var actions := view_model.get("actions", {}) as Dictionary
	_expect(int(data.get("residentCount", 0)) == 1, "入镇绑定页只显示一位居民")
	_expect(
		not bool((actions.get("setMode", {}) as Dictionary).get("enabled", true)),
		"入镇绑定页禁用多选模式",
	)
	_expect(
		not bool((actions.get("selectAllBatch", {}) as Dictionary).get("enabled", true)),
		"入镇绑定页禁用全选",
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
