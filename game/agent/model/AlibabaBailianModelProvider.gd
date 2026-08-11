class_name AlibabaBailianModelProvider
extends "res://agent/model/OpenAICompatibleModelProvider.gd"


const DEFAULT_ENDPOINT := "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
const DEFAULT_MODEL := "qwen3.7-plus"
const MODEL_DESCRIPTORS := [
	{"id": "qwen3.5-plus", "label": "Qwen3.5 Plus", "input_modalities": ["text", "image"]},
	{"id": "qwen3.5-flash", "label": "Qwen3.5 Flash", "input_modalities": ["text", "image"]},
	{"id": "qwen3.5-397b-a17b", "label": "Qwen3.5 397B A17B", "input_modalities": ["text", "image"]},
	{"id": "qwen3.5-122b-a10b", "label": "Qwen3.5 122B A10B", "input_modalities": ["text", "image"]},
	{"id": "qwen3.5-35b-a3b", "label": "Qwen3.5 35B A3B", "input_modalities": ["text", "image"]},
	{"id": "qwen3.5-27b", "label": "Qwen3.5 27B", "input_modalities": ["text", "image"]},
	{"id": "qwen3.6-max-preview", "label": "Qwen3.6 Max Preview", "input_modalities": ["text"]},
	{"id": "qwen3.6-plus", "label": "Qwen3.6 Plus", "input_modalities": ["text", "image"]},
	{"id": "qwen3.6-flash", "label": "Qwen3.6 Flash", "input_modalities": ["text", "image"]},
	{"id": "qwen3.7-max", "label": "Qwen3.7 Max", "input_modalities": ["text"]},
	{"id": DEFAULT_MODEL, "label": "Qwen3.7 Plus", "input_modalities": ["text", "image"]},
]
const MODELS_WITH_JSON_MODE := [
	"qwen3.5-plus",
	"qwen3.5-flash",
	"qwen3.5-397b-a17b",
	"qwen3.5-122b-a10b",
	"qwen3.5-35b-a3b",
	"qwen3.5-27b",
	"qwen3.6-max-preview",
	"qwen3.6-plus",
	"qwen3.6-flash",
	DEFAULT_MODEL,
]


func _init(
	request_host: Node = null,
	transport: Object = null,
	config: Dictionary = {},
) -> void:
	super(request_host, transport, config)


func _provider_id() -> String:
	return "aliyun-bailian"


func _provider_label() -> String:
	return "阿里云百炼"


func _transport_label() -> String:
	return "百炼 OpenAI-compatible API"


func _default_endpoint() -> String:
	return DEFAULT_ENDPOINT


func _default_model() -> String:
	return DEFAULT_MODEL


func _build_request_body(model_request: Dictionary) -> Dictionary:
	var body := super._build_request_body(model_request)
	body.erase("max_tokens")
	return body


func _provider_request_options() -> Dictionary:
	var options := {"enable_thinking": false}
	if String(_config.get("model", DEFAULT_MODEL)) in MODELS_WITH_JSON_MODE:
		options["response_format"] = {"type": "json_object"}
	return options


func validate_configuration() -> Array[String]:
	var errors := super.validate_configuration()
	var model_id := String(_config.get("model", DEFAULT_MODEL))
	if not _supports_model(model_id):
		errors.append("百炼 Provider 不支持模型：%s" % model_id)
	return errors


func _supports_model(model_id: String) -> bool:
	for descriptor: Dictionary in MODEL_DESCRIPTORS:
		if descriptor.get("id") == model_id:
			return true
	return false


func _api_key_environment_names() -> Array[String]:
	return ["DASHSCOPE_API_KEY"]


func _billing_error_identifiers() -> Array[String]:
	return [
		"Arrearage",
		"CommodityNotPurchased",
		"PrepaidBillOverdue",
		"PostpaidBillOverdue",
	]


func _missing_api_key_message(include_hint: bool) -> String:
	var message := "缺少 DASHSCOPE_API_KEY"
	if include_hint:
		message += "；可写入项目 .tmp/.env"
	return message
