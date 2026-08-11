class_name AgentModelProvider
extends RefCounted


# Provider 元信息供注册目录和调试观测使用，不进入世界接口。
func get_provider_descriptor() -> Dictionary:
	return {
		"id": "model-provider",
		"label": "ModelProvider",
		"transport_label": "Provider",
		"external": false,
	}


# 返回请求启动前能够确定的配置错误。
func validate_configuration() -> Array[String]:
	return []


# 接收含非空预编译 messages 的模型请求，返回决定或统一失败结果。
func request_decision(_model_request: Dictionary, _on_complete: Callable) -> void:
	push_error("ModelProvider.request_decision must be implemented by an adapter")


# 结构化 JSON 路线复用同一供应商传输，但不把结果解释为居民动作。
func request_json(model_request: Dictionary, on_complete: Callable) -> void:
	request_decision(model_request, _forward_json_result.bind(on_complete))


func _forward_json_result(result: Variant, on_complete: Callable) -> void:
	if typeof(result) != TYPE_DICTIONARY:
		on_complete.call({"ok": false, "errors": ["模型结构化结果不是对象"]})
		return
	var packet := result as Dictionary
	if packet.get("ok") != true:
		on_complete.call(packet.duplicate(true))
		return
	if not packet.has("decision") or typeof(packet.get("decision")) != TYPE_DICTIONARY:
		on_complete.call({"ok": false, "errors": ["模型结构化结果缺少 JSON 对象"]})
		return
	on_complete.call({
		"ok": true,
		"json": (packet["decision"] as Dictionary).duplicate(true),
	})


# 调试快照是适配器的可选观测接缝，不参与世界接口。
func get_debug_snapshot() -> Dictionary:
	return {
		"provider": get_provider_descriptor(),
		"model_requests": get_model_requests(),
		"requests": get_requests(),
		"responses": get_responses(),
		"results": get_results(),
		"diagnostics": get_diagnostics(),
	}


# 默认适配器直接把 Model Request 当作自身请求；有供应商协议转换时应覆写此方法。
func get_model_requests() -> Array[Dictionary]:
	return get_requests()


func get_requests() -> Array[Dictionary]:
	return []


func get_responses() -> Array[Dictionary]:
	return []


func get_results() -> Array[Dictionary]:
	return []


func get_diagnostics() -> Array[Dictionary]:
	return []
