class_name XiaomiMiMoModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_ENDPOINT := "https://api.xiaomimimo.com/v1/chat/completions"
const PRO_MODEL := "mimo-v2.5-pro"
const OMNI_MODEL := "mimo-v2.5"
const DEFAULT_MODEL := PRO_MODEL
const MODEL_DESCRIPTORS := [
	{"id": PRO_MODEL, "label": "MiMo V2.5 Pro", "input_modalities": ["text"]},
	{"id": OMNI_MODEL, "label": "MiMo V2.5", "input_modalities": ["text", "image"]},
]


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	super(request_host, transport, config)


func _provider_id() -> String:
	return "xiaomi-mimo"


func _provider_label() -> String:
	return "小米 MiMo"


func _transport_label() -> String:
	return "Xiaomi MiMo API"


func _default_endpoint() -> String:
	return DEFAULT_ENDPOINT


func _default_model() -> String:
	return DEFAULT_MODEL


func _build_request_body(model_request: Dictionary) -> Dictionary:
	var body := super._build_request_body(model_request)
	body["max_completion_tokens"] = body.get("max_tokens", _default_max_tokens())
	body.erase("max_tokens")
	return body


func _provider_request_options() -> Dictionary:
	return {
		"thinking": {"type": String(_config.get("thinking_type", "disabled"))},
		"response_format": {"type": "json_object"},
	}


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	var model_id := String(_config.get("model", DEFAULT_MODEL))
	if model_id not in [PRO_MODEL, OMNI_MODEL]:
		errors.append("小米 MiMo Provider 不支持模型：%s" % model_id)
	var thinking_type := String(_config.get("thinking_type", "disabled"))
	if thinking_type not in ["enabled", "disabled"]:
		errors.append("小米 MiMo thinking_type 只支持 enabled 或 disabled：%s" % thinking_type)
	return errors


func _api_key_environment_names() -> Array[String]:
	return ["XIAOMI_API_KEY", "MIMO_API_KEY"]


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 XIAOMI_API_KEY（兼容 MIMO_API_KEY）"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
