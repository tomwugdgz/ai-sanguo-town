extends "res://tests/agent/support/AgentTestCase.gd"


const ReappraiserScript := preload(
	"res://agent/memory/ResidentMemoryReappraiser.gd",
)


func _initialize() -> void:
	_test_repeated_support_reinforces_memory()
	_test_contradiction_creates_doubt_then_firsthand_correction()
	_test_same_claim_natural_negation_can_correct_doubt()
	_test_conflict_exposes_active_intervention()
	_finish_suite("RESIDENT_MEMORY_REAPPRAISER_PASS")


func _test_repeated_support_reinforces_memory() -> void:
	var reappraiser: RefCounted = ReappraiserScript.new()
	var entry := _entry("influencing", 58)
	var evidence := _evidence("claim-key-counter", "钥匙放在柜台。", "hearsay")
	var result_kind := String(reappraiser.call("compare", entry, evidence, false))
	_expect_equal(result_kind, "reinforce", "same claim supports existing memory")
	var changed := reappraiser.call("apply_result", entry, evidence, result_kind, 2) as Dictionary
	_expect_equal(changed.get("confidence"), 66, "support raises confidence")
	_expect_equal(changed.get("state"), "influencing", "supported memory remains influential")


func _test_contradiction_creates_doubt_then_firsthand_correction() -> void:
	var reappraiser: RefCounted = ReappraiserScript.new()
	var entry := _entry("influencing", 58)
	var contradiction := _evidence(
		"claim-key-not-counter",
		"钥匙没有放在柜台。",
		"hearsay",
	)
	var doubt_kind := String(reappraiser.call("compare", entry, contradiction, false))
	_expect_equal(doubt_kind, "doubt", "conflicting hearsay creates doubt")
	var doubtful := reappraiser.call(
		"apply_result",
		entry,
		contradiction,
		doubt_kind,
		2,
	) as Dictionary
	_expect_equal(doubtful.get("confidence"), 38, "doubt lowers confidence")
	_expect_equal(doubtful.get("state"), "doubtful", "memory enters doubtful state")
	var firsthand := _evidence(
		"claim-key-personally-found",
		"我亲眼看见钥匙没有放在柜台。",
		"firsthand",
	)
	var correction_kind := String(
		reappraiser.call("compare", doubtful, firsthand, false)
	)
	_expect_equal(correction_kind, "correct", "firsthand conflict corrects a doubtful memory")
	var corrected := reappraiser.call(
		"apply_result",
		doubtful,
		firsthand,
		correction_kind,
		3,
	) as Dictionary
	_expect_equal(corrected.get("state"), "corrected", "memory records correction")
	_expect_equal(corrected.get("confidence"), 72, "firsthand correction restores grounded confidence")
	_expect_equal(corrected.get("subject"), firsthand.get("subject"), "corrected memory uses firsthand account")


func _test_conflict_exposes_active_intervention() -> void:
	var reappraiser: RefCounted = ReappraiserScript.new()
	var entry := _entry("influencing", 58)
	var contradiction := _evidence(
		"claim-key-not-counter",
		"钥匙没有放在柜台。",
		"firsthand",
	)
	var result_kind := String(reappraiser.call("compare", entry, contradiction, true))
	_expect_equal(result_kind, "discover_anomaly", "conflict can expose an active player intervention")
	var changed := reappraiser.call("apply_result", entry, contradiction, result_kind, 2) as Dictionary
	_expect_equal(changed.get("state"), "anomalous", "discovered intervention leaves an anomaly trace")
	_expect_equal(changed.get("confidence"), 28, "anomaly sharply lowers confidence")


func _test_same_claim_natural_negation_can_correct_doubt() -> void:
	var reappraiser: RefCounted = ReappraiserScript.new()
	var doubtful := _entry("doubtful", 38)
	var firsthand := _evidence(
		"claim-key-counter",
		"我亲眼确认备用钥匙并不在咖啡馆柜台。",
		"firsthand",
	)
	var result_kind := String(
		reappraiser.call("compare", doubtful, firsthand, false)
	)
	_expect_equal(
		result_kind,
		"correct",
		"same claim root accepts natural Chinese negation as firsthand correction",
	)


func _entry(state: String, confidence: int) -> Dictionary:
	return {
		"memory_id": "memory-key-counter",
		"subject": "唐小满说钥匙放在柜台。",
		"interpretation": "我暂时把这件事当真。",
		"claim_root_id": "claim-key-counter",
		"confidence": confidence,
		"state": state,
		"active_version_id": "memory-key-counter-v1",
		"evidence_refs": ["conversation:first"],
		"updated_revision": 1,
	}


func _evidence(claim_root_id: String, subject: String, source_kind: String) -> Dictionary:
	return {
		"claim_root_id": claim_root_id,
		"subject": subject,
		"source_kind": source_kind,
		"evidence_refs": ["evidence:%s" % claim_root_id],
	}
