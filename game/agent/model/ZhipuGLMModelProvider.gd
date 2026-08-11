class_name ZhipuGLMModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_ENDPOINT := "https://open.bigmodel.cn/api/paas/v4/chat/completions"
const DEFAULT_MODEL := "glm-5.2"
const MODEL_DESCRIPTORS := [
	{"id": "glm-4.7", "label": "GLM-4.7", "input_modalities": ["text"]},
	{"id": "glm-5", "label": "GLM-5", "input_modalities": ["text"]},
	{"id": "glm-5.1", "label": "GLM-5.1", "input_modalities": ["text"]},
	{"id": DEFAULT_MODEL, "label": "GLM-5.2", "input_modalities": ["text"]},
	{"id": "glm-5v-turbo", "label": "GLM-5V-Turbo", "input_modalities": ["text", "image"]},
]


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	super(request_host, transport, config)


func _provider_id() -> String:
	return "zhipu-glm"


func _provider_label() -> String:
	return "智谱 GLM"


func _transport_label() -> String:
	return "智谱 API"


func _default_endpoint() -> String:
	return DEFAULT_ENDPOINT


func _default_model() -> String:
	return DEFAULT_MODEL


func _provider_request_options() -> Dictionary:
	var model_id := String(_config.get("model", DEFAULT_MODEL))
	var thinking_type := String(_config.get("thinking_type", "disabled"))
	var options := {"thinking": {"type": thinking_type}}
	if model_id != "glm-5v-turbo":
		options["response_format"] = {"type": "json_object"}
	if thinking_type == "enabled" and model_id == DEFAULT_MODEL:
		options["reasoning_effort"] = String(_config.get("reasoning_effort", "high"))
	return options


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	var model_id := String(_config.get("model", DEFAULT_MODEL))
	if not _supports_model(model_id):
		errors.append("GLM Provider 不支持模型：%s" % model_id)
	return errors


func _supports_model(model_id: String) -> bool:
	for descriptor: Dictionary in MODEL_DESCRIPTORS:
		if descriptor.get("id") == model_id:
			return true
	return false


func _api_key_environment_names() -> Array[String]:
	return ["GLM-API-KEY", "ZAI_API_KEY"]


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 GLM-API-KEY（兼容 ZAI_API_KEY）"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
