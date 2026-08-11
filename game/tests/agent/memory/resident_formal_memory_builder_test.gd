extends "res://tests/agent/support/AgentTestCase.gd"


const BuilderScript := preload("res://agent/memory/ResidentFormalMemoryBuilder.gd")
const RESIDENT_ID := "resident-lin-lan"


func _initialize() -> void:
	_test_conversation_forms_firsthand_and_hearsay_memories()
	_test_repeated_claim_updates_in_place()
	_test_unrelated_reply_from_same_speaker_stays_separate()
	_test_intervened_claim_can_be_discovered_by_conflicting_evidence()
	_test_photo_only_turn_forms_traceable_memory()
	_test_photo_evidence_reappraises_matching_memory()
	_test_spoken_claim_with_photo_remains_hearsay()
	_test_item_clue_can_make_a_conflicting_memory_doubtful()
	_test_weather_change_forms_persistent_memory()
	_test_witnessed_conflict_forms_firsthand_memory()
	_test_reported_conflict_stays_hearsay()
	_test_capacity_converges_oldest_settled_memory()
	_test_capacity_protects_key_old_memories()
	_test_capacity_fails_when_every_memory_is_protected()
	_finish_suite("RESIDENT_FORMAL_MEMORY_BUILDER_PASS")


func _test_conversation_forms_firsthand_and_hearsay_memories() -> void:
	var result := _build(_empty_archive(), _empty_log(), _conversation_evidence(
		"conversation-1",
		"木架明天能好吗？",
		"我明早送过去。",
	))
	_expect_ok(result, "conversation evidence builds formal memories")
	var entries := ((result.get("archive", {}) as Dictionary).get("entries", []) as Array)
	_expect_equal(entries.size(), 2, "each meaningful spoken turn forms one formal memory")
	var hearsay := _entry_for_source(entries, "hearsay")
	var firsthand := _entry_for_source(entries, "firsthand")
	_expect_equal(
		hearsay.get("source_resident_id"),
		"resident-tang-xiao-man",
		"heard speech keeps its direct speaker",
	)
	_expect_equal(
		firsthand.get("source_resident_id"),
		"",
		"own spoken experience remains firsthand",
	)


func _test_repeated_claim_updates_in_place() -> void:
	var first := _build(_empty_archive(), _empty_log(), _conversation_evidence(
		"conversation-repeat",
		"我会把钥匙放在柜台。",
		"我记住了。",
		"claim-key-on-counter",
	))
	_expect_ok(first, "first claim builds")
	var second := _build(
		first.get("archive", {}) as Dictionary,
		first.get("intervention_log", {}) as Dictionary,
		_conversation_evidence(
			"conversation-repeat-later",
			"我会把钥匙放在柜台。",
			"我记住了。",
			"claim-key-on-counter",
		),
	)
	_expect_ok(second, "repeated claim builds")
	var first_entries := ((first.get("archive", {}) as Dictionary).get("entries", []) as Array)
	var second_entries := ((second.get("archive", {}) as Dictionary).get("entries", []) as Array)
	_expect_equal(
		_entries_for_claim_root(second_entries, "claim-key-on-counter").size(),
		1,
		"same claim root does not duplicate the repeated claim",
	)
	_expect(
		int((_entries_for_claim_root(second_entries, "claim-key-on-counter")[0] as Dictionary).get("confidence", 0))
			> int((_entries_for_claim_root(first_entries, "claim-key-on-counter")[0] as Dictionary).get("confidence", 0)),
		"repeated supporting evidence raises confidence",
	)


func _test_intervened_claim_can_be_discovered_by_conflicting_evidence() -> void:
	var first := _build(_empty_archive(), _empty_log(), _conversation_evidence(
		"conversation-conflict",
		"我答应明天来。",
		"我会等你。",
	))
	_expect_ok(first, "conflict fixture builds")
	var archive := (first.get("archive", {}) as Dictionary).duplicate(true)
	var entries := archive.get("entries", []) as Array
	var target := _entry_for_source(entries, "hearsay")
	var target_id := String(target.get("memory_id", ""))
	var log := (first.get("intervention_log", {}) as Dictionary).duplicate(true)
	log["interventions"] = [{
		"memory_id": target_id,
		"status": "active",
	}]
	var conflicting := _conversation_evidence(
		"conversation-conflict",
		"我没有答应明天来。",
		"我听见了。",
	)
	var result := _build(archive, log, conflicting)
	_expect_ok(result, "conflicting evidence is reappraised")
	var changed_entries := ((result.get("archive", {}) as Dictionary).get("entries", []) as Array)
	var changed := _entry_for_id(changed_entries, target_id)
	_expect_equal(changed.get("state"), "anomalous", "active intervention becomes anomalous after contradiction")
	var interventions := ((result.get("intervention_log", {}) as Dictionary).get("interventions", []) as Array)
	_expect_equal((interventions[0] as Dictionary).get("status"), "discovered", "intervention audit records discovery")


func _test_unrelated_reply_from_same_speaker_stays_separate() -> void:
	var first := _build(_empty_archive(), _empty_log(), _conversation_evidence(
		"conversation-key",
		"备用钥匙并不在咖啡馆柜台。",
		"我知道了。",
	))
	var second := _build(
		first.get("archive", {}) as Dictionary,
		first.get("intervention_log", {}) as Dictionary,
		_conversation_evidence(
			"conversation-neutral",
			"明白了。",
			"那先这样。",
		),
	)
	var entries := ((second.get("archive", {}) as Dictionary).get("entries", []) as Array)
	_expect_equal(entries.size(), 4, "same speaker's unrelated reply forms a separate memory")
	var key_memory := entries[0] as Dictionary
	_expect_equal(
		key_memory.get("subject"),
		"唐小满说：备用钥匙并不在咖啡馆柜台。",
		"speaker attribution is not reused as a semantic topic",
	)


func _test_photo_only_turn_forms_traceable_memory() -> void:
	var evidence := _conversation_evidence("conversation-photo", "", "")
	var turn := (
		(((evidence["wake_packet"] as Dictionary)["events"] as Array)[0] as Dictionary)["turns"] as Array
	)[0] as Dictionary
	turn["photos"] = [{"ref": "photo-market-clock", "mime_type": "image/png"}]
	var result := _build(_empty_archive(), _empty_log(), evidence)
	_expect_ok(result, "photo-only conversation evidence builds")
	var entries := ((result.get("archive", {}) as Dictionary).get("entries", []) as Array)
	var heard := _entry_for_source(entries, "firsthand")
	_expect(
		(heard.get("evidence_refs", []) as Array).has("photo:photo-market-clock"),
		"photo evidence reference remains traceable without exposing image data",
	)
	_expect_equal(
		heard.get("claim_root_id"),
		"photo:photo-market-clock",
		"photo-only evidence keeps a stable photo claim root",
	)


func _test_photo_evidence_reappraises_matching_memory() -> void:
	var first := _build(
		_empty_archive(),
		_empty_log(),
		_conversation_evidence(
			"conversation-false-key",
			"储物间的备用钥匙在咖啡馆柜台。",
			"我记住了。",
		),
	)
	_expect_ok(first, "false key claim fixture builds")
	var archive := (first.get("archive", {}) as Dictionary).duplicate(true)
	var entries := archive.get("entries", []) as Array
	var target := _entry_for_source(entries, "hearsay")
	var target_id := String(target.get("memory_id", ""))
	var log := (first.get("intervention_log", {}) as Dictionary).duplicate(true)
	log["interventions"] = [{
		"memory_id": target_id,
		"status": "active",
	}]
	var evidence := _conversation_evidence("conversation-photo-proof", "", "")
	var turn := (
		(((evidence["wake_packet"] as Dictionary)["events"] as Array)[0] as Dictionary)["turns"] as Array
	)[0] as Dictionary
	turn["photos"] = [{"ref": "photo-empty-counter", "mime_type": "image/png"}]
	var result := _build(
		archive,
		log,
		evidence,
		{
			"important_memories": "",
			"relationships": "",
			"current_thoughts": "储物间的备用钥匙并不在咖啡馆柜台。",
			"long_term_goals": "",
			"short_term_goals": "",
		},
	)
	_expect_ok(result, "photo evidence is reappraised")
	var changed_entries := (
		(result.get("archive", {}) as Dictionary).get("entries", []) as Array
	)
	var changed := _entry_for_id(changed_entries, target_id)
	_expect_equal(
		changed.get("state"),
		"anomalous",
		"a semantically matching contradictory photo can expose an intervention",
	)
	_expect(
		(changed.get("evidence_refs", []) as Array).has(
			"photo:photo-empty-counter",
		),
		"the cognitive change keeps the photo as its evidence",
	)


func _test_spoken_claim_with_photo_remains_hearsay() -> void:
	var evidence := _conversation_evidence(
		"conversation-spoken-photo",
		"钟楼上的钟已经停了。",
		"我会去看看。",
	)
	var turn := (
		(((evidence["wake_packet"] as Dictionary)["events"] as Array)[0] as Dictionary)["turns"] as Array
	)[0] as Dictionary
	turn["photos"] = [{"ref": "photo-stopped-clock", "mime_type": "image/png"}]
	var result := _build(_empty_archive(), _empty_log(), evidence)
	_expect_ok(result, "spoken claim with a photo builds")
	var entries := ((result.get("archive", {}) as Dictionary).get("entries", []) as Array)
	var heard := _entry_for_source(entries, "hearsay")
	_expect_equal(
		heard.get("source_resident_id"),
		"resident-tang-xiao-man",
		"a photo attached to another resident's statement does not turn hearsay into firsthand memory",
	)
	var photo_memory := _entry_for_source(entries, "firsthand")
	_expect(
		(photo_memory.get("evidence_refs", []) as Array).has("photo:photo-stopped-clock"),
		"the attached photo forms independent firsthand evidence instead of changing the spoken claim's source",
	)


func _test_item_clue_can_make_a_conflicting_memory_doubtful() -> void:
	var first := _build(
		_empty_archive(),
		_empty_log(),
		_conversation_evidence(
			"conversation-key-location",
			"备用钥匙在咖啡馆柜台。",
			"我记住了。",
		),
	)
	_expect_ok(first, "item clue fixture builds")
	var initial_entries := (
		(first.get("archive", {}) as Dictionary).get("entries", []) as Array
	)
	var target := _entry_for_source(initial_entries, "hearsay")
	var target_id := String(target.get("memory_id", ""))
	var clue_evidence := {
		"wake_packet": {
			"events": [],
			"action_results": [{
				"action_id": "inspect-counter-with-key",
				"status": "completed",
				"reason": "检查柜台后，我发现备用钥匙并不在咖啡馆柜台。",
				"time": {"day": 3, "clock": "18:40", "period": "傍晚"},
			}],
			"snapshot": {"time": {"day": 3, "clock": "18:40", "period": "傍晚"}},
		},
		"matched_intents": [{
			"action_id": "inspect-counter-with-key",
			"type": "用道具",
			"item_id": "spare-key",
			"target_place_id": "咖啡馆柜台",
		}],
	}
	var result := _build(
		first.get("archive", {}) as Dictionary,
		first.get("intervention_log", {}) as Dictionary,
		clue_evidence,
		{
			"important_memories": "",
			"relationships": "",
			"current_thoughts": "备用钥匙并不在咖啡馆柜台。",
			"long_term_goals": "",
			"short_term_goals": "",
		},
	)
	_expect_ok(result, "item clue evidence builds")
	var changed_entries := (
		(result.get("archive", {}) as Dictionary).get("entries", []) as Array
	)
	var changed := _entry_for_id(changed_entries, target_id)
	_expect_equal(
		changed.get("state"),
		"doubtful",
		"a firsthand item clue can make a conflicting hearsay memory doubtful",
	)
	_expect(
		(changed.get("evidence_refs", []) as Array).has(
			"action_result:inspect-counter-with-key",
		),
		"the cognitive change keeps the item action result as evidence",
	)


func _test_weather_change_forms_persistent_memory() -> void:
	var evidence := _conversation_evidence("weather-change", "", "")
	(evidence["wake_packet"] as Dictionary)["events"] = [{
		"event_id": "event-weather-rain",
		"time": {"day": 3, "clock": "18:35", "period": "傍晚"},
		"type": "天气变了",
		"weather": "小雨",
	}]
	var result := _build(_empty_archive(), _empty_log(), evidence)
	_expect_ok(result, "weather evidence builds")
	var entries := ((result.get("archive", {}) as Dictionary).get("entries", []) as Array)
	_expect_equal(entries.size(), 1, "weather change forms one persistent memory")
	if entries.is_empty():
		return
	var weather_memory := entries[0] as Dictionary
	_expect_equal(weather_memory.get("subject"), "天气变为小雨", "weather meaning is explicit")
	_expect_equal(weather_memory.get("source_kind"), "firsthand", "received weather remains firsthand")
	_expect(
		(weather_memory.get("evidence_refs", []) as Array).has("event:event-weather-rain"),
		"weather memory keeps the World event reference",
	)


func _test_witnessed_conflict_forms_firsthand_memory() -> void:
	var evidence := _conflict_evidence(
		"event-conflict-witnessed",
		"witness",
		"",
		"我亲眼看见唐小满攻击了花子，花子受了轻伤。",
	)
	var result := _build(_empty_archive(), _empty_log(), evidence)
	_expect_ok(result, "witnessed conflict evidence builds")
	var entries := (
		(result.get("archive", {}) as Dictionary).get("entries", []) as Array
	)
	_expect_equal(entries.size(), 1, "one witnessed conflict forms one memory")
	if entries.is_empty():
		return
	var memory := entries[0] as Dictionary
	_expect_equal(
		memory.get("source_kind"),
		"firsthand",
		"a direct witness keeps firsthand knowledge",
	)
	_expect_equal(
		memory.get("people"),
		["resident-tang-xiao-man", "resident-hanako"],
		"conflict memory keeps the confirmed participants",
	)
	_expect(
		(memory.get("evidence_refs", []) as Array).has(
			"conflict:conflict-000001:conflict-event-000003",
		),
		"conflict memory keeps a stable conflict fact reference",
	)


func _test_reported_conflict_stays_hearsay() -> void:
	var evidence := _conflict_evidence(
		"event-conflict-heard",
		"hearsay",
		"resident-tang-xiao-man",
		"唐小满告诉我，她看见花子在码头仓库附近受了伤。",
	)
	var result := _build(_empty_archive(), _empty_log(), evidence)
	_expect_ok(result, "reported conflict evidence builds")
	var entries := (
		(result.get("archive", {}) as Dictionary).get("entries", []) as Array
	)
	_expect_equal(entries.size(), 1, "one reported conflict forms one memory")
	if entries.is_empty():
		return
	var memory := entries[0] as Dictionary
	_expect_equal(
		memory.get("source_kind"),
		"hearsay",
		"a relayed conflict never becomes firsthand",
	)
	_expect_equal(
		memory.get("source_resident_id"),
		"resident-tang-xiao-man",
		"hearsay keeps the resident who relayed it",
	)


func _test_capacity_converges_oldest_settled_memory() -> void:
	var entries: Array = []
	for index in range(256):
		entries.append(_capacity_entry(index, "past"))
	var archive := _empty_archive()
	archive["revision"] = 256
	archive["entries"] = entries
	var result := _build(
		archive,
		_empty_log(),
		_weather_evidence("capacity-weather"),
	)
	_expect_ok(result, "257th memory converges an ordinary settled past memory")
	var result_entries := (
		(result.get("archive", {}) as Dictionary).get("entries", []) as Array
	)
	_expect_equal(result_entries.size(), 256, "formal archive remains bounded at 256 entries")
	_expect_equal(
		_entry_for_id(result_entries, "memory-capacity-000").is_empty(),
		true,
		"the oldest ordinary settled memory converges first",
	)
	_expect_equal(
		(result.get("convergence", {}) as Dictionary).get("removed_memory_ids"),
		["memory-capacity-000"],
		"capacity convergence reports the removed memory explicitly",
	)


func _test_capacity_protects_key_old_memories() -> void:
	var protected_states: Array[String] = [
		"influencing", "doubtful", "anomalous", "corrected",
	]
	var entries: Array = []
	for index in range(protected_states.size()):
		entries.append(_capacity_entry(index, protected_states[index]))
	entries.append(_capacity_entry(4, "past"))
	for index in range(5, 256):
		entries.append(_capacity_entry(index, "past"))
	var archive := _empty_archive()
	archive["revision"] = 256
	archive["entries"] = entries
	var log := _empty_log()
	log["interventions"] = [{
		"intervention_id": "intervention-capacity-audit",
		"memory_id": "memory-capacity-004",
		"kind": "reinterpret",
		"operation": "edit",
		"player_text": "这段记忆被玩家改写过。",
		"status": "active",
	}]
	var result := _build(
		archive,
		log,
		_weather_evidence("capacity-protected-weather"),
	)
	_expect_ok(result, "capacity convergence preserves key old memories")
	var result_entries := (
		(result.get("archive", {}) as Dictionary).get("entries", []) as Array
	)
	for index in range(5):
		_expect_equal(
			_entry_for_id(
				result_entries,
				"memory-capacity-%03d" % index,
			).is_empty(),
			false,
			"protected old memory %d remains in the archive" % index,
		)
	_expect_equal(
		_entry_for_id(result_entries, "memory-capacity-005").is_empty(),
		true,
		"the first unprotected settled memory converges instead",
	)


func _test_capacity_fails_when_every_memory_is_protected() -> void:
	var entries: Array = []
	for index in range(256):
		entries.append(_capacity_entry(index, "influencing"))
	var archive := _empty_archive()
	archive["revision"] = 256
	archive["entries"] = entries
	var result := _build(
		archive,
		_empty_log(),
		_weather_evidence("capacity-blocked-weather"),
	)
	_expect_equal(result.get("ok"), false, "all-protected capacity refuses silent deletion")
	_expect_equal(result.get("capacity_blocked"), true, "capacity failure is explicit to its caller")
	_expect(
		String((result.get("errors", []) as Array)[0]).contains("不能静默删除"),
		"capacity failure explains why the old archive was preserved",
	)


func _conflict_evidence(
	event_id: String,
	knowledge_kind: String,
	source_resident_id: String,
	summary: String,
) -> Dictionary:
	return {
		"wake_packet": {
			"events": [{
				"event_id": event_id,
				"time": {"day": 3, "clock": "18:35", "period": "傍晚"},
				"type": "冲突见闻",
				"conflict_id": "conflict-000001",
				"conflict_event_id": "conflict-event-000003",
				"conflict_event_type": "injury_applied",
				"knowledge_kind": knowledge_kind,
				"source_resident_id": source_resident_id,
				"actor_ids": [
					"resident-tang-xiao-man",
					"resident-hanako",
				],
				"place_id": "码头仓库",
				"severity": "light",
				"summary": summary,
			}],
			"action_results": [],
			"snapshot": {
				"time": {"day": 3, "clock": "18:35", "period": "傍晚"},
			},
		},
		"matched_intents": [],
	}


func _weather_evidence(event_id: String) -> Dictionary:
	return {
		"wake_packet": {
			"events": [{
				"event_id": event_id,
				"time": {"day": 300, "clock": "12:00", "period": "中午"},
				"type": "天气变了",
				"weather": "小雨",
			}],
			"action_results": [],
			"snapshot": {
				"time": {"day": 300, "clock": "12:00", "period": "中午"},
			},
		},
		"matched_intents": [],
	}


func _capacity_entry(index: int, state: String) -> Dictionary:
	var memory_id := "memory-capacity-%03d" % index
	return {
		"memory_id": memory_id,
		"resident_id": RESIDENT_ID,
		"subject": "第%d段普通往事" % index,
		"interpretation": "这是一段已经沉淀的普通经历。",
		"people": [],
		"places": [],
		"topics": ["旧事-%03d" % index],
		"world_time": {"day": index + 1, "clock": "12:00", "period": "中午"},
		"source_kind": "firsthand",
		"source_resident_id": "",
		"claim_root_id": "event:capacity-%03d" % index,
		"confidence": 70,
		"state": state,
		"active_version_id": "%s-v1" % memory_id,
		"evidence_refs": ["event:capacity-%03d" % index],
		"created_revision": index + 1,
		"updated_revision": index + 1,
	}


func _build(
	archive: Dictionary,
	log: Dictionary,
	evidence: Dictionary,
	summary: Dictionary = {},
) -> Dictionary:
	var builder: RefCounted = BuilderScript.new(RESIDENT_ID)
	var effective_summary := summary
	if effective_summary.is_empty():
		effective_summary = {
			"important_memories": "",
			"relationships": "",
			"current_thoughts": "我正在理解刚才的对话。",
			"long_term_goals": "",
			"short_term_goals": "",
		}
	return builder.call(
		"build",
		archive,
		log,
		[evidence],
		effective_summary,
	) as Dictionary


func _conversation_evidence(
	conversation_id: String,
	heard_say: String,
	self_say: String,
	claim_root_id: String = "",
) -> Dictionary:
	var heard_turn := {
		"turn_id": 1,
		"speaker_resident_id": "resident-tang-xiao-man",
		"speaker": "唐小满",
		"say": heard_say,
		"narration": "",
	}
	if not claim_root_id.is_empty():
		heard_turn["memory_claim_root_id"] = claim_root_id
	return {
		"wake_packet": {
			"events": [{
				"event_id": "%s-event" % conversation_id,
				"time": {"day": 3, "clock": "18:35", "period": "傍晚"},
				"type": "对话结束",
				"conversation_id": conversation_id,
				"turns": [
					heard_turn,
					{
						"turn_id": 2,
						"speaker_resident_id": RESIDENT_ID,
						"speaker": "林岚",
						"say": self_say,
						"narration": "",
					},
				],
			}],
			"action_results": [],
			"snapshot": {"time": {"day": 3, "clock": "18:35", "period": "傍晚"}},
		},
		"matched_intents": [],
	}


func _empty_archive() -> Dictionary:
	return {
		"state_version": 1,
		"resident_id": RESIDENT_ID,
		"revision": 0,
		"entries": [],
	}


func _empty_log() -> Dictionary:
	return {
		"state_version": 1,
		"resident_id": RESIDENT_ID,
		"revision": 0,
		"interventions": [],
	}


func _entry_for_source(entries: Array, source_kind: String) -> Dictionary:
	for value: Variant in entries:
		var entry := value as Dictionary
		if String(entry.get("source_kind", "")) == source_kind:
			return entry
	return {}


func _entry_for_id(entries: Array, memory_id: String) -> Dictionary:
	for value: Variant in entries:
		var entry := value as Dictionary
		if String(entry.get("memory_id", "")) == memory_id:
			return entry
	return {}


func _entries_for_claim_root(entries: Array, claim_root_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry_value: Variant in entries:
		var entry := entry_value as Dictionary
		if String(entry.get("claim_root_id", "")) == claim_root_id:
			result.append(entry)
	return result
