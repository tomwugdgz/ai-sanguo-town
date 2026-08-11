extends "res://tests/agent/support/AgentTestCase.gd"


const PROVIDER_SERVICE := preload(
	"res://world/integration/TownAgentProviderService.gd"
)


func _initialize() -> void:
	var service: RefCounted = PROVIDER_SERVICE.new()
	var request := service.call("_health_probe_request") as Dictionary
	_expect_equal(
		request.get("max_tokens"),
		256,
		"健康检查给思考模型保留足够的短回答输出空间",
	)
	_expect_equal(
		request.get("messages", []).size(),
		2,
		"健康检查仍使用最小提示词请求",
	)
	_finish_suite("PROVIDER_HEALTH_PROBE_BUDGET_PASS")
