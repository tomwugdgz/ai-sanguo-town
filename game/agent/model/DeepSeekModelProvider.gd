class_name DeepSeekModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_ENDPOINT := "https://api.deepseek.com/chat/completions"
const V4_FLASH_MODEL := "deepseek-v4-flash"
const V4_PRO_MODEL := "deepseek-v4-pro"
const DEFAULT_MODEL := V4_FLASH_MODEL
const MODEL_DESCRIPTORS := [
	{"id": V4_FLASH_MODEL, "label": "DeepSeek V4 Flash", "input_modalities": ["text"]},
	{"id": V4_PRO_MODEL, "label": "DeepSeek V4 Pro", "input_modalities": ["text"]},
]


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	super(request_host, transport, config)


func _provider_id() -> String:
	return "deepseek"


func _provider_label() -> String:
	return "DeepSeek"


func _transport_label() -> String:
	return "DeepSeek API"


func _default_endpoint() -> String:
	return DEFAULT_ENDPOINT


func _default_model() -> String:
	return DEFAULT_MODEL


func _provider_request_options() -> Dictionary:
	return {
		"thinking": {"type": "disabled"},
		"response_format": {"type": "json_object"},
	}


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	var model_id := String(_config.get("model", DEFAULT_MODEL))
	if model_id not in [V4_FLASH_MODEL, V4_PRO_MODEL]:
		errors.append("DeepSeek Provider 不支持模型：%s" % model_id)
	return errors


func _api_key_environment_names() -> Array[String]:
	return ["DEEPSEEK_API_KEY"]


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 DEEPSEEK_API_KEY"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
