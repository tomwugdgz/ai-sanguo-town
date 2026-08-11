extends "res://tests/agent/support/AgentTestCase.gd"


const AgingServiceScript := preload(
	"res://agent/memory/ResidentMemoryAgingService.gd",
)
const RESIDENT_ID := "resident-lin-lan"


func _initialize() -> void:
	_test_unconfirmed_hearsay_softens_once_per_interval()
	_test_old_hearsay_leaves_current_influence()
	_test_supported_and_player_changed_memories_are_preserved()
	_finish_suite("RESIDENT_MEMORY_AGING_SERVICE_PASS")


func _test_unconfirmed_hearsay_softens_once_per_interval() -> void:
	var service: RefCounted = AgingServiceScript.new(RESIDENT_ID)
	var archive := _archive([_entry("memory-hearsay", "hearsay", 58)])
	var first := service.call("evaluate", archive, _empty_log(), _time(10)) as Dictionary
	_expect_ok(first, "seven-day-old hearsay can be organized")
	_expect_equal(first.get("changed"), true, "eligible hearsay changes")
	var changed := _entry_from_result(first, "memory-hearsay")
	_expect_equal(changed.get("confidence"), 50, "one interval lowers confidence once")
	_expect_equal(changed.get("state"), "influencing", "recent hearsay remains influential")
	var audits := (
		(first.get("intervention_log", {}) as Dictionary).get("interventions", []) as Array
	)
	_expect_equal(audits.size(), 1, "automatic organization leaves an internal audit")
	_expect_equal((audits[0] as Dictionary).get("kind"), "soften", "audit uses internal soften kind")
	var repeated := service.call(
		"evaluate",
		first.get("archive"),
		first.get("intervention_log"),
		_time(10),
	) as Dictionary
	_expect_ok(repeated, "same-day reevaluation succeeds")
	_expect_equal(repeated.get("changed"), false, "same interval is idempotent")


func _test_old_hearsay_leaves_current_influence() -> void:
	var service: RefCounted = AgingServiceScript.new(RESIDENT_ID)
	var result := service.call(
		"evaluate",
		_archive([_entry("memory-old-hearsay", "hearsay", 58)]),
		_empty_log(),
		_time(24),
	) as Dictionary
	_expect_ok(result, "old hearsay can be organized")
	var changed := _entry_from_result(result, "memory-old-hearsay")
	_expect_equal(changed.get("confidence"), 34, "three elapsed intervals reach the floor")
	_expect_equal(changed.get("state"), "past", "weak hearsay no longer drives current decisions")


func _test_supported_and_player_changed_memories_are_preserved() -> void:
	var firsthand := _entry("memory-firsthand", "firsthand", 78)
	var supported := _entry("memory-supported", "hearsay", 66)
	supported["evidence_refs"] = ["conversation:a", "claim:supported", "conversation:b"]
	var intervened := _entry("memory-intervened", "hearsay", 58)
	var service: RefCounted = AgingServiceScript.new(RESIDENT_ID)
	var result := service.call(
		"evaluate",
		_archive([firsthand, supported, intervened]),
		_log_with_active_player_edit("memory-intervened"),
		_time(40),
	) as Dictionary
	_expect_ok(result, "protected memories can be inspected")
	_expect_equal(result.get("changed"), false, "stronger evidence and player edits do not auto-soften")


func _archive(entries: Array) -> Dictionary:
	return {
		"state_version": 1,
		"resident_id": RESIDENT_ID,
		"revision": 1,
		"entries": entries,
	}


func _entry(memory_id: String, source_kind: String, confidence: int) -> Dictionary:
	return {
		"memory_id": memory_id,
		"resident_id": RESIDENT_ID,
		"subject": "唐小满说钥匙放在柜台。",
		"interpretation": "我暂时把这件事当真。",
		"people": ["resident-tang-xiao-man"],
		"places": ["咖啡馆"],
		"topics": ["钥匙"],
		"world_time": _time(3),
		"source_kind": source_kind,
		"source_resident_id": "resident-tang-xiao-man" if source_kind == "hearsay" else "",
		"claim_root_id": "claim:%s" % memory_id,
		"confidence": confidence,
		"state": "influencing",
		"active_version_id": "%s-v1" % memory_id,
		"evidence_refs": ["conversation:a", "claim:%s" % memory_id],
		"created_revision": 1,
		"updated_revision": 1,
	}


func _empty_log() -> Dictionary:
	return {
		"state_version": 1,
		"resident_id": RESIDENT_ID,
		"revision": 1,
		"interventions": [],
	}


func _log_with_active_player_edit(memory_id: String) -> Dictionary:
	var version := {
		"subject": "唐小满说钥匙放在柜台。",
		"interpretation": "我暂时把这件事当真。",
		"confidence": 58,
		"state": "influencing",
		"active_version_id": "%s-v1" % memory_id,
	}
	return {
		"state_version": 1,
		"resident_id": RESIDENT_ID,
		"revision": 1,
		"interventions": [{
			"intervention_id": "player-edit-1",
			"resident_id": RESIDENT_ID,
			"memory_id": memory_id,
			"kind": "distort",
			"operation": "edit",
			"original_version": version,
			"active_version": version,
			"player_text": "钥匙其实在门口。",
			"created_world_time": _time(4),
			"status": "active",
		}],
	}


func _entry_from_result(result: Dictionary, memory_id: String) -> Dictionary:
	var entries := ((result.get("archive", {}) as Dictionary).get("entries", []) as Array)
	for value: Variant in entries:
		var entry := value as Dictionary
		if String(entry.get("memory_id", "")) == memory_id:
			return entry
	return {}


func _time(day: int) -> Dictionary:
	return {"day": day, "clock": "09:00", "period": "上午"}
