extends "res://tests/agent/support/AgentSaveTestCase.gd"


func _initialize() -> void:
	if not _setup_save_test("restore"):
		_finish_save_test("AGENT_SAVE_RESTORE_PASS")
		return
	_test_public_lifecycle_only_exchanges_context()
	_test_new_game_initial_revision_contains_initialized_residents()
	_test_restore_old_revision_can_continue_at_unused_revision()
	_test_resident_state_restores_and_rehydrates()
	_test_same_id_rename_preserves_identity()
	_test_same_name_residents_restore_by_id_after_propagated_rename()
	_test_initialization_equivalence_rejects_malformed_nested_state()
	_test_pending_request_is_not_saved()
	_test_restore_hydration_requires_exact_resident_set()
	_test_swapped_resident_payload_identity_fails()
	_test_same_name_runtime_state_isolated_between_slots()
	_finish_save_test("AGENT_SAVE_RESTORE_PASS")


func _test_public_lifecycle_only_exchanges_context() -> void:
	var context := _context("public_slot", "public_session", 7)
	var system: RefCounted = _new_agent_system()
	var injected_context := context.duplicate(true)
	injected_context["resident_payloads"] = {"林岚": PackedByteArray([1, 2, 3])}
	var injected: Dictionary = system.call("start_new_game", injected_context)
	_expect(
		injected.get("ok") == false,
		"world lifecycle context cannot smuggle resident payloads",
	)
	var started: Dictionary = system.call("start_new_game", context)
	_expect_ok(started, "new game starts from context")
	_expect(not started.has("resident_payloads"), "new game does not expose resident payloads")
	_expect_ok(system.call("finish_new_game"), "empty new game publishes explicitly")
	system.call("close_game")
	var restored: Dictionary = system.call("restore_game", context)
	_expect_ok(restored, "game restores from context")
	_expect(not restored.has("resident_payloads"), "restore does not expose resident payloads")
	system.call("delete_game", context)

func _test_new_game_initial_revision_contains_initialized_residents() -> void:
	var context := _context("initial_residents", "initial_residents_session", 0)
	var system: RefCounted = _new_agent_system()
	var started: Dictionary = system.call("start_new_game", context)
	_expect_ok(started, "new game preparation succeeds")
	_expect_equal(
		started.get("status"),
		"pending_initialization",
		"new game does not publish its immutable revision before residents initialize",
	)
	var model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	_expect_ok(
		system.call("initialize_resident", _initialization(), model),
		"new game resident initializes in the pending transaction",
	)
	var before_commit: Dictionary = _new_agent_system().call("restore_game", context)
	_expect(
		before_commit.get("ok") == false,
		"initial revision is not readable before the complete resident set commits",
	)
	if not system.has_method("finish_new_game"):
		_expect(false, "AgentSystem exposes finish_new_game for initial revision publication")
		system.call("delete_game", context)
		return
	_expect_ok(system.call("finish_new_game"), "complete new game resident set commits")
	_expect_equal(
		(
			system.call("get_active_resident_ids") as Dictionary
		).get("resident_ids"),
		["resident-lin-lan"],
		"world can verify the active Agent resident ID set without private state",
	)
	system.call("close_game")

	var restored_system: RefCounted = _new_agent_system()
	var restored: Dictionary = restored_system.call("restore_game", context)
	_expect_ok(restored, "committed initial revision restores")
	_expect_equal(
		restored.get("resident_ids"),
		["resident-lin-lan"],
		"initial revision contains the complete initialized resident set",
	)
	var restored_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	_expect_ok(
		restored_system.call(
			"hydrate_restored_resident",
			_initialization(),
			restored_model,
		),
		"initial resident rehydrates from revision zero",
	)
	_expect_ok(restored_system.call("finish_restore"), "initial revision restore commits")
	_expect_equal(
		restored_system.call("get_save_context"),
		context,
		"restored initial revision keeps its save identity",
	)
	restored_system.call("delete_game", context)

func _test_restore_old_revision_can_continue_at_unused_revision() -> void:
	var revision_0 := _context("continue_slot", "continue_session", 0)
	var revision_1 := _context("continue_slot", "continue_session", 1)
	var revision_2 := _context("continue_slot", "continue_session", 2)
	var revision_3 := _context("continue_slot", "continue_session", 3)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", revision_0)
	_expect_ok(system.call("finish_new_game"), "revision zero publishes")
	_expect_ok(system.call("save_game", revision_2), "revision 2 saves")
	_expect_ok(system.call("save_game", revision_3), "revision 3 saves")
	_expect_ok(system.call("restore_game", revision_2), "older revision restores")
	var occupied: Dictionary = system.call("save_game", revision_3)
	_expect(occupied.get("ok") == false, "occupied revision remains immutable")
	_expect_equal(system.call("get_save_context"), revision_2, "failed save keeps restored revision active")
	_expect_ok(
		system.call("save_game", revision_1),
		"any unused world-assigned revision continues the session",
	)
	system.call("delete_game", revision_1)

func _test_resident_state_restores_and_rehydrates() -> void:
	var context := _context("codec_restore", "codec_restore_session", 0)
	var saved_context := _context("codec_restore", "codec_restore_session", 1)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	var model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	model.call("queue_decision", _stay_decision("before-save", "saved-action"))
	_expect_ok(system.call("initialize_resident", _initialization(), model), "resident initializes before save")
	_expect_ok(system.call("finish_new_game"), "initialized new game publishes")
	var before_save := ResultCollector.new()
	system.call("request_decision", "resident-lin-lan", _wake_packet("before-save"), before_save.collect)
	_expect_equal(before_save.values.size(), 1, "pre-save runtime state changes")
	_expect_ok(system.call("save_game", saved_context), "initialized resident saves")

	model.call("queue_decision", _stay_decision("after-save", "after-save-action"))
	var after_save := ResultCollector.new()
	system.call("request_decision", "resident-lin-lan", _wake_packet("after-save"), after_save.collect)
	_expect_equal(after_save.values.size(), 1, "runtime changes after save point")

	var restored_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	var prepared: Dictionary = system.call("restore_game", saved_context)
	_expect_ok(prepared, "resident snapshot prepares for restore")
	_expect_equal(prepared.get("status"), "pending_hydration", "non-empty restore waits for hydration")
	_expect_ok(
		system.call("hydrate_restored_resident", _initialization(), restored_model),
		"saved resident reconnects provider",
	)
	_expect_ok(system.call("finish_restore"), "hydrated restore commits")
	var restored_snapshot: Dictionary = system.call("get_memory_debug_snapshot", "resident-lin-lan")
	_expect_equal(
		restored_snapshot.get("active_item_count"),
		1,
		"restore rebuilds the exact active memory present at the save point",
	)

	restored_model.call("queue_decision", _stay_decision("restored-new", "after-save-action"))
	var restored_new := ResultCollector.new()
	system.call("request_decision", "resident-lin-lan", _wake_packet("restored-new"), restored_new.collect)
	_expect_equal(
		restored_new.values,
		[_accepted_decision_result(_stay_decision("restored-new", "after-save-action"))],
		"state added after the save point is absent after restore",
	)
	var restored_requests: Array = restored_model.call("get_requests")
	if not restored_requests.is_empty():
		_expect_equal(
			(restored_requests[0] as Dictionary).has("memory_context"),
			false,
			"pending actions restore for result pairing without a parallel memory payload",
		)

	restored_model.call("queue_decision", _stay_decision("restored-duplicate", "saved-action"))
	var restored_duplicate := ResultCollector.new()
	system.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("restored-duplicate"),
		restored_duplicate.collect,
	)
	_expect_equal(restored_duplicate.values.size(), 1, "保存点动作编号冲突产生一次明确结果")
	if restored_duplicate.values.size() == 1:
		var repaired := restored_duplicate.values[0]
		_expect_equal(repaired.get("ok"), true, "保存点动作编号冲突会被安全修复")
		_expect_equal(repaired.get("actionIdRepaired"), true, "修复状态会明确返回")
		_expect(
			String(((repaired.get("decision", {}) as Dictionary).get("action", {}) as Dictionary).get("action_id", ""))
			!= "saved-action",
			"修复后的动作编号不会重用保存点编号",
		)
	system.call("delete_game", saved_context)

func _test_same_id_rename_preserves_identity() -> void:
	var context := _context("rename_identity", "rename_identity_session", 0)
	var saved_context := _context("rename_identity", "rename_identity_session", 1)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	var original_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	original_model.call("queue_decision", _stay_decision("before-rename", "identity-action"))
	_expect_ok(
		system.call("initialize_resident", _initialization_for("林岚", "resident-stable"), original_model),
		"resident initializes before rename",
	)
	_expect_ok(system.call("finish_new_game"), "rename fixture publishes")
	var original_results := ResultCollector.new()
	system.call(
		"request_decision",
		"resident-stable",
		_wake_packet("before-rename"),
		original_results.collect,
	)
	_expect_equal(original_results.values.size(), 1, "resident records state before rename")
	_expect_ok(system.call("save_game", saved_context), "resident identity saves before rename")

	var restored: Dictionary = system.call("restore_game", saved_context)
	_expect_equal(
		restored.get("resident_ids"),
		["resident-stable"],
		"restore exposes the stable id rather than the saved display name",
	)
	var renamed_initialization := _initialization_for("林岚新名", "resident-stable")
	var renamed_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	_expect_ok(
		system.call("hydrate_restored_resident", renamed_initialization, renamed_model),
		"same resident id hydrates after a display-name change",
	)
	_expect_ok(system.call("finish_restore"), "renamed resident restore commits")
	var renamed_snapshot: Dictionary = system.call(
		"get_memory_debug_snapshot",
		"resident-stable",
	)
	_expect_equal(renamed_snapshot.get("resident"), "林岚新名", "debug output uses the current display name")
	_expect_equal(
		renamed_snapshot.get("active_item_count"),
		1,
		"same id retains its saved memory after rename",
	)
	system.call("delete_game", saved_context)

func _test_same_name_residents_restore_by_id_after_propagated_rename() -> void:
	var context := _context("same_name_ids", "same_name_ids_session", 0)
	var saved_context := _context("same_name_ids", "same_name_ids_session", 1)
	var first_id := "resident-same-name-a"
	var second_id := "resident-same-name-b"
	var original_name := "林岚"
	var renamed_name := "林岚新名"
	var first_initialization := _paired_initialization(
		first_id,
		original_name,
		second_id,
		original_name,
		second_id,
		original_name,
	)
	var second_initialization := _paired_initialization(
		second_id,
		original_name,
		first_id,
		original_name,
		second_id,
		original_name,
	)
	var system: RefCounted = _new_agent_system()
	_expect_ok(system.call("start_new_game", context), "same-name new game starts")
	var first_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	var second_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	first_model.call("queue_decision", _stay_decision("same-name-a", "same-name-action-a"))
	second_model.call("queue_decision", _stay_decision("same-name-b", "same-name-action-b"))
	_expect_ok(
		system.call("initialize_resident", first_initialization, first_model),
		"first same-name resident initializes by id",
	)
	_expect_ok(
		system.call("initialize_resident", second_initialization, second_model),
		"second same-name resident initializes by id",
	)
	_expect_ok(system.call("finish_new_game"), "same-name resident set publishes")
	system.call(
		"request_decision",
		first_id,
		_wake_packet("same-name-a"),
		ResultCollector.new().collect,
	)
	system.call(
		"request_decision",
		second_id,
		_wake_packet("same-name-b"),
		ResultCollector.new().collect,
	)
	_expect_ok(system.call("save_game", saved_context), "same-name resident states save by id")

	var prepared: Dictionary = system.call("restore_game", saved_context)
	_expect_equal(
		prepared.get("resident_ids"),
		[first_id, second_id],
		"same-name restore exposes both stable ids",
	)
	var current_first := _paired_initialization(
		first_id,
		original_name,
		second_id,
		renamed_name,
		second_id,
		renamed_name,
	)
	var current_second := _paired_initialization(
		second_id,
		renamed_name,
		first_id,
		original_name,
		second_id,
		renamed_name,
	)
	var restored_first_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	var restored_second_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	_expect_ok(
		system.call(
			"hydrate_restored_resident",
			current_first,
			restored_first_model,
		),
		"unchanged resident accepts the other resident's propagated display-name change",
	)
	_expect_ok(
		system.call(
			"hydrate_restored_resident",
			current_second,
			restored_second_model,
		),
		"renamed resident hydrates under the same stable id",
	)
	_expect_ok(system.call("finish_restore"), "same-name renamed resident set commits")
	_expect_equal(
		system.call("get_memory_debug_snapshot", first_id).get("resident"),
		original_name,
		"first stable id retains its display name",
	)
	_expect_equal(
		system.call("get_memory_debug_snapshot", second_id).get("resident"),
		renamed_name,
		"second stable id uses its current display name",
	)
	_expect_equal(
		system.call("get_memory_debug_snapshot", first_id).get("active_item_count"),
		1,
		"first same-name id restores only its memory",
	)
	_expect_equal(
		system.call("get_memory_debug_snapshot", second_id).get("active_item_count"),
		1,
		"second same-name id restores only its memory",
	)
	restored_first_model.call(
		"queue_decision",
		_stay_decision("same-name-a-after", "same-name-action-a-after"),
	)
	restored_second_model.call(
		"queue_decision",
		_stay_decision("same-name-b-after", "same-name-action-b-after"),
	)
	system.call(
		"request_decision",
		first_id,
		_wake_packet("same-name-a-after"),
		ResultCollector.new().collect,
	)
	system.call(
		"request_decision",
		second_id,
		_wake_packet("same-name-b-after"),
		ResultCollector.new().collect,
	)
	var first_request := (
		(restored_first_model.call("get_requests") as Array)[0] as Dictionary
	)
	var second_request := (
		(restored_second_model.call("get_requests") as Array)[0] as Dictionary
	)
	_expect(not first_request.has("memory_context"), "first same-name id has no parallel memory payload")
	_expect(not second_request.has("memory_context"), "second same-name id has no parallel memory payload")
	system.call("delete_game", saved_context)

func _test_initialization_equivalence_rejects_malformed_nested_state() -> void:
	var codec: RefCounted = (load(CODEC_SCRIPT_PATH) as Script).new()
	_expect_equal(
		codec.call(
			"equivalent_initialization",
			{"me": 7, "residents": [], "places": []},
			_initialization(),
		),
		false,
		"malformed saved initialization is rejected without an invalid nested method call",
	)

func _test_pending_request_is_not_saved() -> void:
	var context := _context("pending_not_saved", "pending_not_saved_session", 0)
	var saved_context := _context("pending_not_saved", "pending_not_saved_session", 1)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	var old_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	old_model.call("set_auto_complete", false)
	old_model.call("queue_decision", _stay_decision("pending-before-save", "pending-action"))
	system.call("initialize_resident", _initialization(), old_model)
	_expect_ok(system.call("finish_new_game"), "pending-request new game publishes")
	var old_results := ResultCollector.new()
	system.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("pending-before-save"),
		old_results.collect,
	)
	_expect_ok(system.call("save_game", saved_context), "save succeeds with a pending request")

	var restored_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	_expect_ok(system.call("restore_game", saved_context), "pending-request snapshot prepares")
	_expect_ok(
		system.call("hydrate_restored_resident", _initialization(), restored_model),
		"pending-request snapshot hydrates",
	)
	_expect_ok(system.call("finish_restore"), "pending-request snapshot commits")
	old_model.call("complete_next")
	_expect_equal(old_results.values.size(), 1, "pre-save pending result is explicit after restore")
	if old_results.values.size() == 1:
		_expect_equal(old_results.values[0].get("stale"), true, "pre-save pending result is stale after restore")

	restored_model.call("queue_decision", _stay_decision("after-pending-restore", "pending-action"))
	var restored_results := ResultCollector.new()
	system.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("after-pending-restore"),
		restored_results.collect,
	)
	_expect_equal(
		restored_results.values.size(),
		1,
		"action from a pending request was not persisted",
	)
	var restored_snapshot: Dictionary = system.call("get_memory_debug_snapshot", "resident-lin-lan")
	_expect_equal(
		restored_snapshot.get("active_item_count"),
		1,
		"only the post-restore accepted action enters resident memory",
	)
	system.call("delete_game", saved_context)

func _test_restore_hydration_requires_exact_resident_set() -> void:
	var context := _context("hydrate_set", "hydrate_set_session", 0)
	var saved_context := _context("hydrate_set", "hydrate_set_session", 1)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	system.call(
		"initialize_resident",
		_initialization_for("林岚"),
		(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
	)
	system.call(
		"initialize_resident",
		_initialization_for("唐小满"),
		(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
	)
	_expect_ok(system.call("finish_new_game"), "two-resident new game publishes")
	_expect_ok(system.call("save_game", saved_context), "two-resident snapshot saves")
	_expect_ok(system.call("restore_game", saved_context), "two-resident restore prepares")

	var extra: Dictionary = system.call(
		"hydrate_restored_resident",
		_initialization_for("阿禾"),
		(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
	)
	_expect(extra.get("ok") == false, "extra resident hydration aborts the transaction")
	_expect(
		system.call("finish_restore").get("ok") == false,
		"aborted extra-resident transaction cannot commit",
	)

	_expect_ok(system.call("restore_game", saved_context), "duplicate-resident attempt prepares again")
	_expect_ok(
		system.call(
			"hydrate_restored_resident",
			_initialization_for("林岚"),
			(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
		),
		"first saved resident hydrates",
	)
	var duplicate: Dictionary = system.call(
		"hydrate_restored_resident",
		_initialization_for("林岚"),
		(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
	)
	_expect(duplicate.get("ok") == false, "duplicate hydration aborts the transaction")
	_expect(
		system.call("finish_restore").get("ok") == false,
		"aborted duplicate transaction cannot commit",
	)

	_expect_ok(system.call("restore_game", saved_context), "identity-mismatch attempt prepares again")
	var mismatched_initialization := _initialization_for("唐小满")
	mismatched_initialization["me"]["attributes"]["age"] = 44
	var mismatch: Dictionary = system.call(
		"hydrate_restored_resident",
		mismatched_initialization,
		(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
	)
	_expect(mismatch.get("ok") == false, "initialization mismatch aborts the transaction")
	_expect(
		system.call("finish_restore").get("ok") == false,
		"aborted identity transaction cannot commit",
	)

	_expect_ok(system.call("restore_game", saved_context), "missing-resident attempt prepares again")
	_expect_ok(
		system.call(
			"hydrate_restored_resident",
			_initialization_for("林岚"),
			(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
		),
		"one resident hydrates before missing-set failure",
	)
	var missing: Dictionary = system.call("finish_restore")
	_expect(missing.get("ok") == false, "missing resident aborts restore commit")
	_expect(
		system.call(
			"hydrate_restored_resident",
			_initialization_for("唐小满"),
			(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
		).get("ok") == false,
		"missing-resident transaction cannot be repaired after failure",
	)
	_expect_equal(
		system.call("get_save_context"),
		saved_context,
		"failed hydration keeps the active session",
	)
	var current_results := ResultCollector.new()
	_expect_ok(
		system.call(
			"request_decision",
			"resident-lin-lan",
			_wake_packet("after-failed-hydration"),
			current_results.collect,
		),
		"failed hydration keeps the current resident usable",
	)
	_expect_equal(current_results.values.size(), 1, "failed hydration keeps current callbacks active")

	_expect_ok(system.call("restore_game", saved_context), "clean exact-set attempt prepares")
	_expect_ok(
		system.call(
			"hydrate_restored_resident",
			_initialization_for("林岚"),
			(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
		),
		"first resident hydrates in clean transaction",
	)
	_expect_ok(
		system.call(
			"hydrate_restored_resident",
			_initialization_for("唐小满"),
			(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
		),
		"remaining saved resident hydrates",
	)
	_expect_ok(system.call("finish_restore"), "exact resident set commits")
	var reapplied: Dictionary = system.call(
		"hydrate_restored_resident",
		_initialization_for("唐小满"),
		(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
	)
	_expect(reapplied.get("ok") == false, "committed restored state cannot be applied again")
	system.call("delete_game", saved_context)

func _test_swapped_resident_payload_identity_fails() -> void:
	var context := _context("swapped_identity", "swapped_identity_session", 0)
	var saved_context := _context("swapped_identity", "swapped_identity_session", 1)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	system.call(
		"initialize_resident",
		_initialization_for("林岚"),
		(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
	)
	system.call(
		"initialize_resident",
		_initialization_for("唐小满"),
		(load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new(),
	)
	_expect_ok(system.call("finish_new_game"), "identity fixture new game publishes")
	system.call("save_game", saved_context)
	var fixture: Script = load(SAVE_FIXTURE_SCRIPT_PATH) as Script
	_expect(
		fixture.call("swap_manifest_resident_ids", _test_root, saved_context),
		"swapped resident identity fixture is created",
	)
	var failed: Dictionary = system.call("restore_game", saved_context)
	_expect(
		failed.get("ok") == false and _errors_contain(failed.get("errors", []), "身份串用"),
		"manifest ids cannot redirect valid resident payloads",
	)
	_expect_equal(
		system.call("get_save_context"),
		saved_context,
		"identity failure keeps active residents and context",
	)

func _test_same_name_runtime_state_isolated_between_slots() -> void:
	var slot_a_start := _context("runtime_slot_a", "runtime_session_a", 0)
	var slot_a_save := _context("runtime_slot_a", "runtime_session_a", 1)
	var slot_b_start := _context("runtime_slot_b", "runtime_session_b", 0)
	var slot_b_save := _context("runtime_slot_b", "runtime_session_b", 1)
	var slot_a_system: RefCounted = _new_agent_system()
	slot_a_system.call("start_new_game", slot_a_start)
	var slot_a_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	slot_a_model.call("queue_decision", _stay_decision("slot-a-shared", "shared-action"))
	slot_a_model.call("queue_decision", _stay_decision("slot-a-before-save", "slot-a-action"))
	slot_a_system.call("initialize_resident", _initialization(), slot_a_model)
	_expect_ok(slot_a_system.call("finish_new_game"), "slot A new game publishes")
	var slot_a_shared := ResultCollector.new()
	slot_a_system.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("slot-a-shared"),
		slot_a_shared.collect,
	)
	_expect(
		slot_a_shared.values.size() == 1 and slot_a_shared.values[0].get("ok") == true,
		"slot A accepts the shared action id",
	)
	slot_a_system.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("slot-a-before-save"),
		ResultCollector.new().collect,
	)
	_expect_ok(slot_a_system.call("save_game", slot_a_save), "slot A resident state saves")
	slot_a_system.call("close_game")

	var slot_b_system: RefCounted = _new_agent_system()
	slot_b_system.call("start_new_game", slot_b_start)
	var slot_b_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	slot_b_model.call("queue_decision", _stay_decision("slot-b-shared", "shared-action"))
	slot_b_model.call("queue_decision", _stay_decision("slot-b-before-save", "slot-b-action"))
	slot_b_system.call("initialize_resident", _initialization(), slot_b_model)
	_expect_ok(slot_b_system.call("finish_new_game"), "slot B new game publishes")
	var slot_b_shared := ResultCollector.new()
	slot_b_system.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("slot-b-shared"),
		slot_b_shared.collect,
	)
	_expect(
		slot_b_shared.values.size() == 1 and slot_b_shared.values[0].get("ok") == true,
		"slot B can reuse the same resident action id without reading slot A",
	)
	slot_b_system.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("slot-b-before-save"),
		ResultCollector.new().collect,
	)
	_expect_ok(slot_b_system.call("save_game", slot_b_save), "slot B resident state saves")
	slot_b_system.call("close_game")

	var restore_a: RefCounted = _new_agent_system()
	var restored_a_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	_expect_ok(restore_a.call("restore_game", slot_a_save), "slot A prepares independently")
	_expect_ok(
		restore_a.call("hydrate_restored_resident", _initialization(), restored_a_model),
		"slot A resident hydrates",
	)
	_expect_ok(restore_a.call("finish_restore"), "slot A commits")
	_expect_equal(
		restore_a.call("get_memory_debug_snapshot", "resident-lin-lan").get("active_item_count"),
		2,
		"slot A restores only its own legacy memory",
	)
	restored_a_model.call("queue_decision", _stay_decision("slot-a-cross-check", "slot-b-action"))
	var slot_a_cross_result := ResultCollector.new()
	restore_a.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("slot-a-cross-check"),
		slot_a_cross_result.collect,
	)
	_expect(
		slot_a_cross_result.values.size() == 1
			and slot_a_cross_result.values[0].get("ok") == true,
		"slot A does not inherit slot B action ids",
	)

	var restore_b: RefCounted = _new_agent_system()
	var restored_b_model: RefCounted = (load(SCRIPTED_MODEL_SCRIPT_PATH) as Script).new()
	_expect_ok(restore_b.call("restore_game", slot_b_save), "slot B prepares independently")
	_expect_ok(
		restore_b.call("hydrate_restored_resident", _initialization(), restored_b_model),
		"slot B resident hydrates",
	)
	_expect_ok(restore_b.call("finish_restore"), "slot B commits")
	_expect_equal(
		restore_b.call("get_memory_debug_snapshot", "resident-lin-lan").get("active_item_count"),
		2,
		"slot B restores only its own legacy memory",
	)
	restored_b_model.call("queue_decision", _stay_decision("slot-b-cross-check", "slot-a-action"))
	var slot_b_cross_result := ResultCollector.new()
	restore_b.call(
		"request_decision",
		"resident-lin-lan",
		_wake_packet("slot-b-cross-check"),
		slot_b_cross_result.collect,
	)
	_expect(
		slot_b_cross_result.values.size() == 1
			and slot_b_cross_result.values[0].get("ok") == true,
		"slot B does not inherit slot A action ids",
	)
	restore_a.call("delete_game", slot_a_save)
	_expect(
		_new_agent_system().call("restore_game", slot_a_save).get("ok") == false,
		"deleted slot A resident state cannot restore",
	)
	restore_b.call("delete_game", slot_b_save)
