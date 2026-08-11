extends SceneTree


const POLICY := preload(
	"res://world/runtime/work/TownWorkActorSelectionPolicy.gd"
)


var _failures: Array[String] = []


func _initialize() -> void:
	var candidates: Array[String] = ["resident_a", "resident_b", "resident_c"]
	_expect_equal(
		POLICY.choose_from_candidates(candidates, 0),
		"resident_a",
		"轮换从候选列表第一位开始",
	)
	_expect_equal(
		POLICY.choose_from_candidates(candidates, 1),
		"resident_b",
		"第二次来源选择不会固定回到第一位",
	)
	_expect_equal(
		POLICY.choose_from_candidates(candidates, 2),
		"resident_c",
		"第三次来源选择能覆盖第三位候选人",
	)
	_expect_equal(
		POLICY.choose_from_candidates(candidates, 3),
		"resident_a",
		"轮换索引超过候选人数后能稳定回绕",
	)
	_expect_equal(
		POLICY.choose_from_candidates([], 0),
		"",
		"没有可用执行者时不伪造居民",
	)
	if _failures.is_empty():
		print("TOWN_WORK_ACTOR_SELECTION_POLICY_PASS")
		quit(0)
		return
	for failure: String in _failures:
		printerr("TOWN_WORK_ACTOR_SELECTION_POLICY_FAIL: %s" % failure)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(
			"%s；实际=%s，期望=%s" % [message, str(actual), str(expected)]
		)
