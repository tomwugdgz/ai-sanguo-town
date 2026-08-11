class_name KimiModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_ENDPOINT := "https://api.moonshot.cn/v1/chat/completions"
const K2_5_MODEL := "kimi-k2.5"
const K2_6_MODEL := "kimi-k2.6"
const K2_7_CODE_HIGHSPEED_MODEL := "kimi-k2.7-code-highspeed"
const K3_MODEL := "kimi-k3"
const DEFAULT_MODEL := K3_MODEL
const MODEL_DESCRIPTORS := [
	{"id": K2_5_MODEL, "label": "Kimi K2.5", "deprecated": true, "input_modalities": ["text", "image"]},
	{"id": K2_6_MODEL, "label": "Kimi K2.6", "input_modalities": ["text", "image"]},
	{"id": K2_7_CODE_HIGHSPEED_MODEL, "label": "Kimi K2.7 Code Highspeed", "input_modalities": ["text", "image"]},
	{"id": K3_MODEL, "label": "Kimi K3", "input_modalities": ["text", "image"]},
]
const MODEL_OUTPUT_BUDGETS := {
	K2_5_MODEL: 32768,
	K2_6_MODEL: 32768,
	K2_7_CODE_HIGHSPEED_MODEL: 32768,
	K3_MODEL: 32768,
}


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	super(request_host, transport, config)


func _provider_id() -> String:
	return "kimi"


func _provider_label() -> String:
	return "Kimi"


func _transport_label() -> String:
	return "Kimi API"


func _default_endpoint() -> String:
	return DEFAULT_ENDPOINT


func _default_model() -> String:
	return DEFAULT_MODEL


func _default_max_tokens() -> int:
	return int(MODEL_OUTPUT_BUDGETS.get(_selected_model_id(), 1024))


func _build_request_body(model_request: Dictionary) -> Dictionary:
	var body := super._build_request_body(model_request)
	if _selected_model_id() == K3_MODEL:
		body["max_completion_tokens"] = body.get("max_tokens", MODEL_OUTPUT_BUDGETS[K3_MODEL])
		body.erase("max_tokens")
	return body


func _provider_request_options() -> Dictionary:
	match _selected_model_id():
		K2_5_MODEL, K2_6_MODEL:
			return {
				"thinking": {"type": String(_config.get("thinking_type", "disabled"))},
				"response_format": {"type": "json_object"},
			}
		K2_7_CODE_HIGHSPEED_MODEL:
			return {"response_format": {"type": "json_object"}}
		K3_MODEL:
			return {
				"reasoning_effort": "low",
				"response_format": {"type": "json_object"},
			}
	return {}


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	var model_id := _selected_model_id()
	if not MODEL_OUTPUT_BUDGETS.has(model_id):
		errors.append("Kimi Provider 不支持模型：%s" % model_id)
	elif model_id in [K2_5_MODEL, K2_6_MODEL]:
		var thinking_type := String(_config.get("thinking_type", "disabled"))
		if thinking_type not in ["enabled", "disabled"]:
			errors.append("Kimi thinking_type 只支持 enabled 或 disabled：%s" % thinking_type)
	return errors


func _selected_model_id() -> String:
	return String(_config.get("model", _default_model()))


func _api_key_environment_names() -> Array[String]:
	return ["KIMI-API-KEY", "MOONSHOT_API_KEY"]


func _billing_error_identifiers() -> Array[String]:
	return ["exceeded_current_quota_error", "insufficient_quota"]


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 KIMI-API-KEY（兼容 MOONSHOT_API_KEY）"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
