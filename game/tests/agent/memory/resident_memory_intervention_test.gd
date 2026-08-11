extends "res://tests/agent/support/AgentTestCase.gd"


const EntryStoreScript := preload("res://agent/memory/ResidentMemoryEntryStore.gd")
const InterventionStoreScript := preload("res://agent/memory/ResidentMemoryInterventionStore.gd")
const InterventionServiceScript := preload("res://agent/memory/ResidentMemoryInterventionService.gd")
const UserTestDataCleanerScript := preload("res://tests/support/UserTestDataCleaner.gd")

const RESIDENT_ID := "resident-lin-lan"
const TEST_ROOT_BASE := "user://tests/resident-memory-intervention"

var _test_root := "%s/%d_%d" % [
	TEST_ROOT_BASE,
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


func _initialize() -> void:
	_test_edit_preserves_history_and_records_original_version()
	_test_delete_does_not_delete_history()
	_test_write_has_no_world_evidence_source()
	_test_cross_resident_and_invalid_hearsay_are_rejected()
	_test_legacy_internal_kind_is_normalized_for_player_history()
	_finish_suite("RESIDENT_MEMORY_INTERVENTION_PASS", [_test_root])


func _test_edit_preserves_history_and_records_original_version() -> void:
	var fixture := _fixture("edit")
	_expect_ok(
		fixture.entry_store.call("replace", _archive([_firsthand_entry()])),
		"firsthand entry seeds",
	)
	var result := fixture.service.call("apply", _request(
		"edit",
		"memory-1",
		"我相信对方是故意把我晾在那里。",
	)) as Dictionary
	_expect_ok(result, "edit applies")
	var changed := result.get("memory", {}) as Dictionary
	_expect_equal(
		changed.get("subject"),
		"我相信对方是故意把我晾在那里。",
		"edit replaces the player-visible memory text",
	)
	_expect_equal(
		changed.get("interpretation"),
		"",
		"edit does not keep a hidden duplicate interpretation",
	)
	var log := fixture.intervention_store.call("read") as Dictionary
	var item := (((log.get("log", {}) as Dictionary).get("interventions", []) as Array)[0] as Dictionary)
	_expect_equal(
		(item.get("original_version", {}) as Dictionary).get("interpretation"),
		"我还不知道她为什么没来。",
		"intervention retains the prior subjective version",
	)
	_expect_equal(item.get("operation"), "edit", "public operation remains edit")
	_expect_equal(item.get("kind"), "distort", "edit maps to an internal distortion event")
	_expect_equal(result.get("summary_refresh_required"), true, "summary refresh is explicit")


func _test_delete_does_not_delete_history() -> void:
	var fixture := _fixture("delete")
	_expect_ok(
		fixture.entry_store.call("replace", _archive([_firsthand_entry()])),
		"delete fixture seeds",
	)
	_expect_ok(
		fixture.service.call("apply", _request("delete", "memory-1", "")),
		"delete applies",
	)
	var archive_result := fixture.entry_store.call("read") as Dictionary
	var entries := (archive_result.get("archive", {}) as Dictionary).get("entries", []) as Array
	_expect_equal(entries.size(), 1, "suppression keeps the formal memory")
	_expect_equal((entries[0] as Dictionary).get("state"), "past", "suppressed memory exits ordinary influence")
	var log_result := fixture.intervention_store.call("read") as Dictionary
	var interventions := (log_result.get("log", {}) as Dictionary).get("interventions", []) as Array
	_expect_equal(interventions.size(), 1, "delete remains auditable")
	_expect_equal((interventions[0] as Dictionary).get("status"), "active", "delete remains the active intervention")
	_expect_equal((interventions[0] as Dictionary).get("operation"), "delete", "public operation remains delete")
	_expect_equal((interventions[0] as Dictionary).get("kind"), "suppress", "delete maps to internal suppression")


func _test_write_has_no_world_evidence_source() -> void:
	var fixture := _fixture("write")
	var result := fixture.service.call("apply", _request(
		"write",
		"memory-implanted",
		"我记得唐小满曾答应替我保守秘密。",
	)) as Dictionary
	_expect_ok(result, "write applies")
	var entry := result.get("memory", {}) as Dictionary
	_expect_equal(entry.get("source_kind"), "implanted", "implant stays explicitly subjective")
	_expect_equal(entry.get("source_resident_id"), "", "implant does not forge a speaker")
	_expect_equal((entry.get("evidence_refs", []) as Array).size(), 0, "implant does not forge World evidence")
	var log := fixture.intervention_store.call("read") as Dictionary
	var item := (((log.get("log", {}) as Dictionary).get("interventions", []) as Array)[0] as Dictionary)
	_expect_equal(item.get("operation"), "write", "public operation remains write")
	_expect_equal(item.get("kind"), "implant", "write maps to internal implantation")


func _test_cross_resident_and_invalid_hearsay_are_rejected() -> void:
	var fixture := _fixture("invalid")
	var wrong_resident := _request("write", "memory-wrong", "不该写入。")
	wrong_resident["resident_id"] = "resident-other"
	_expect_equal(
		(fixture.service.call("apply", wrong_resident) as Dictionary).get("ok"),
		false,
		"intervention cannot cross resident ownership",
	)
	var invalid := _firsthand_entry()
	invalid["source_kind"] = "hearsay"
	_expect_equal(
		(fixture.entry_store.call("replace", _archive([invalid])) as Dictionary).get("ok"),
		false,
		"hearsay requires its direct speaker",
	)


func _test_legacy_internal_kind_is_normalized_for_player_history() -> void:
	var fixture := _fixture("legacy-operation")
	var original := _memory_version("我记得那天没有等到她。", 80, "influencing", "memory-1-v1")
	var active := _memory_version("我对那次失约已经没有那么在意。", 45, "influencing", "memory-1-v2")
	_expect_ok(
		fixture.intervention_store.call("replace", {
			"state_version": 1,
			"resident_id": RESIDENT_ID,
			"revision": 2,
			"interventions": [{
				"intervention_id": "legacy-soften-1",
				"resident_id": RESIDENT_ID,
				"memory_id": "memory-1",
				"kind": "soften",
				"original_version": original,
				"active_version": active,
				"player_text": "",
				"created_world_time": {"day": 4, "clock": "09:10", "period": "上午"},
				"status": "active",
			}],
		}),
		"legacy intervention without public operation remains readable",
	)
	var read_result := fixture.intervention_store.call("read") as Dictionary
	_expect_ok(read_result, "normalized legacy intervention reads")
	var interventions := (read_result.get("log", {}) as Dictionary).get("interventions", []) as Array
	_expect_equal(interventions.size(), 1, "legacy intervention remains auditable")
	_expect_equal(
		(interventions[0] as Dictionary).get("operation"),
		"edit",
		"legacy internal kind projects to a player-facing operation",
	)
	_expect_equal(
		(interventions[0] as Dictionary).get("kind"),
		"soften",
		"legacy internal cognitive history is preserved",
	)


func _fixture(name: String) -> Dictionary:
	var root := _test_root.path_join(name)
	var entry_store: RefCounted = EntryStoreScript.new(
		root.path_join("resident_memory_entries.json"),
		RESIDENT_ID,
	)
	var intervention_store: RefCounted = InterventionStoreScript.new(
		root.path_join("resident_memory_interventions.json"),
		RESIDENT_ID,
	)
	_expect_ok(
		entry_store.call("replace", _archive([])),
		"formal memory fixture revision aligns",
	)
	_expect_ok(
		intervention_store.call("replace", {
			"state_version": 1,
			"resident_id": RESIDENT_ID,
			"revision": 1,
			"interventions": [],
		}),
		"intervention fixture revision aligns",
	)
	return {
		"entry_store": entry_store,
		"intervention_store": intervention_store,
		"service": InterventionServiceScript.new(
			RESIDENT_ID,
			entry_store,
			intervention_store,
		),
	}


func _archive(entries: Array) -> Dictionary:
	return {
		"state_version": 1,
		"resident_id": RESIDENT_ID,
		"revision": 1,
		"entries": entries,
	}


func _firsthand_entry() -> Dictionary:
	return {
		"memory_id": "memory-1",
		"resident_id": RESIDENT_ID,
		"subject": "我在第3天傍晚没有等到唐小满。",
		"interpretation": "我还不知道她为什么没来。",
		"people": ["resident-tang-xiao-man"],
		"places": ["花房咖啡馆"],
		"topics": ["失约"],
		"world_time": {"day": 3, "clock": "18:35", "period": "傍晚"},
		"source_kind": "firsthand",
		"source_resident_id": "",
		"claim_root_id": "claim-1",
		"confidence": 80,
		"state": "influencing",
		"active_version_id": "memory-1-v1",
		"evidence_refs": ["event:e-81"],
		"created_revision": 1,
		"updated_revision": 1,
	}


func _memory_version(subject: String, confidence: int, state: String, version_id: String) -> Dictionary:
	return {
		"subject": subject,
		"interpretation": "",
		"confidence": confidence,
		"state": state,
		"active_version_id": version_id,
	}


func _request(operation: String, memory_id: String, player_text: String) -> Dictionary:
	return {
		"resident_id": RESIDENT_ID,
		"memory_id": memory_id,
		"operation": operation,
		"player_text": player_text,
		"world_time": {"day": 4, "clock": "09:10", "period": "上午"},
		"expected_revision": 1,
	}
