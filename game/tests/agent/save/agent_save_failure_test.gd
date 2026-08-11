extends "res://tests/agent/support/AgentSaveTestCase.gd"


func _initialize() -> void:
	if not _setup_save_test("failure"):
		_finish_save_test("AGENT_SAVE_FAILURE_PASS")
		return
	_test_failed_start_preserves_active_session()
	_test_failed_new_game_publish_preserves_active_session()
	_test_failed_restore_preserves_active_session()
	_test_failed_delete_preserves_active_session()
	_test_invalid_start_preserves_active_session()
	_test_corrupt_restore_preserves_active_session()
	_test_corrupt_payload_restore_preserves_active_session()
	_test_corrupt_delete_preserves_active_session()
	_test_same_slot_other_session_delete_invalidates()
	_test_successful_boundaries_mark_late_results_stale()
	_test_successful_new_game_publish_marks_late_results_stale()
	_finish_save_test("AGENT_SAVE_FAILURE_PASS")


func _test_failed_start_preserves_active_session() -> void:
	var context := _context("failed_start", "failed_start_session", 0)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	_expect_ok(system.call("finish_new_game"), "failed-start source publishes")
	var pending := _begin_pending_decision(system, "failed-start-decision", "failed-start-action")
	var failed: Dictionary = system.call("start_new_game", context)
	_expect(failed.get("ok") == false, "starting over an existing root fails")
	_expect_equal(system.call("get_save_context"), context, "failed start keeps active context")
	_complete_and_expect_delivery(pending, "failed start keeps active request valid")
	system.call("delete_game", context)

func _test_failed_new_game_publish_preserves_active_session() -> void:
	var source_context := _context(
		"failed_new_game_publish_source",
		"failed_new_game_publish_source_session",
		0,
	)
	var target_context := _context(
		"failed_new_game_publish_target",
		"failed_new_game_publish_target_session",
		0,
	)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", source_context)
	_expect_ok(system.call("finish_new_game"), "publish-failure source publishes")
	var pending := _begin_pending_decision(
		system,
		"failed-new-game-publish-decision",
		"failed-new-game-publish-action",
	)
	_expect_ok(
		system.call("start_new_game", target_context),
		"new game prepares before a competing writer publishes the slot",
	)
	_expect_ok(
		_store.call("create_new_game", target_context, {}),
		"competing writer publishes the target slot",
	)
	var failed: Dictionary = system.call("finish_new_game")
	_expect(failed.get("ok") == false, "new game publish collision fails")
	_expect_equal(
		system.call("get_save_context"),
		source_context,
		"failed new game publish keeps active context",
	)
	_complete_and_expect_delivery(
		pending,
		"failed new game publish keeps the prior request valid",
	)
	_expect_ok(system.call("cancel_new_game"), "failed new game transaction cancels")
	_expect_ok(_store.call("delete_slot", target_context), "competing target slot cleans up")
	system.call("delete_game", source_context)

func _test_failed_restore_preserves_active_session() -> void:
	var context := _context("failed_restore", "failed_restore_session", 0)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	_expect_ok(system.call("finish_new_game"), "failed-restore source publishes")
	var pending := _begin_pending_decision(system, "failed-restore-decision", "failed-restore-action")
	var wrong_context := context.duplicate(true)
	wrong_context["slot_id"] = "wrong_slot"
	var failed: Dictionary = system.call("restore_game", wrong_context)
	_expect(failed.get("ok") == false, "mismatched restore fails")
	_expect_equal(system.call("get_save_context"), context, "failed restore keeps active context")
	_complete_and_expect_delivery(pending, "failed restore keeps active request valid")
	system.call("delete_game", context)

func _test_failed_delete_preserves_active_session() -> void:
	var context := _context("failed_delete", "failed_delete_session", 0)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	_expect_ok(system.call("finish_new_game"), "failed-delete source publishes")
	var pending := _begin_pending_decision(system, "failed-delete-decision", "failed-delete-action")
	var wrong_revision := context.duplicate(true)
	wrong_revision["save_revision"] = 99
	var failed: Dictionary = system.call("delete_game", wrong_revision)
	_expect(failed.get("ok") == false, "delete with wrong revision fails")
	_expect_equal(system.call("get_save_context"), context, "failed delete keeps active context")
	_complete_and_expect_delivery(pending, "failed delete keeps active request valid")
	system.call("delete_game", context)

func _test_invalid_start_preserves_active_session() -> void:
	var context := _context("invalid_start", "invalid_start_session", 0)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	_expect_ok(system.call("finish_new_game"), "invalid-start source publishes")
	var pending := _begin_pending_decision(system, "invalid-start-decision", "invalid-start-action")
	var invalid_context := context.duplicate(true)
	invalid_context["slot_id"] = "../not-a-slot"
	var failed: Dictionary = system.call("start_new_game", invalid_context)
	_expect(failed.get("ok") == false, "invalid new-game context fails")
	_expect_equal(system.call("get_save_context"), context, "invalid start keeps active context")
	_complete_and_expect_delivery(pending, "invalid start keeps active request valid")
	system.call("delete_game", context)

func _test_corrupt_restore_preserves_active_session() -> void:
	var target_context := _context("corrupt_restore_target", "corrupt_restore_target_session", 0)
	var target_system: RefCounted = _new_agent_system()
	target_system.call("start_new_game", target_context)
	_expect_ok(target_system.call("finish_new_game"), "corrupt target publishes")
	target_system.call("close_game")
	_overwrite_snapshot_manifest(target_context, "not json")

	var source_context := _context("corrupt_restore_source", "corrupt_restore_source_session", 0)
	var source_system: RefCounted = _new_agent_system()
	source_system.call("start_new_game", source_context)
	_expect_ok(source_system.call("finish_new_game"), "corrupt-restore source publishes")
	var pending := _begin_pending_decision(source_system, "corrupt-restore-decision", "corrupt-restore-action")
	var failed: Dictionary = source_system.call("restore_game", target_context)
	_expect(failed.get("ok") == false, "corrupt restore target fails")
	_expect_equal(source_system.call("get_save_context"), source_context, "corrupt restore keeps source context")
	_complete_and_expect_delivery(pending, "corrupt restore keeps source request valid")
	source_system.call("delete_game", source_context)

func _test_corrupt_payload_restore_preserves_active_session() -> void:
	var target_context := _context("corrupt_payload_target", "corrupt_payload_target_session", 0)
	var store: RefCounted = _store
	store.call("create_new_game", target_context, {
		"resident-lin-lan": {
			"resident_name": "林岚",
			"payload": "original".to_utf8_buffer(),
		},
	})
	var fixture: Script = load(SAVE_FIXTURE_SCRIPT_PATH) as Script
	_expect(
		fixture.call(
			"overwrite_first_payload",
			_test_root,
			target_context,
			"tampered".to_utf8_buffer(),
		),
		"corrupt payload fixture is created",
	)

	var source_context := _context("corrupt_payload_source", "corrupt_payload_source_session", 0)
	var source_system: RefCounted = _new_agent_system()
	source_system.call("start_new_game", source_context)
	_expect_ok(source_system.call("finish_new_game"), "corrupt-payload source publishes")
	var pending := _begin_pending_decision(source_system, "corrupt-payload-decision", "corrupt-payload-action")
	var failed: Dictionary = source_system.call("restore_game", target_context)
	_expect(failed.get("ok") == false, "corrupt resident payload fails before codec restore")
	_expect_equal(source_system.call("get_save_context"), source_context, "corrupt payload keeps source context")
	_complete_and_expect_delivery(pending, "corrupt payload keeps source request valid")
	source_system.call("delete_game", source_context)

func _test_corrupt_delete_preserves_active_session() -> void:
	var context := _context("corrupt_delete", "corrupt_delete_session", 0)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", context)
	_expect_ok(system.call("finish_new_game"), "corrupt-delete source publishes")
	var pending := _begin_pending_decision(system, "corrupt-delete-decision", "corrupt-delete-action")
	_overwrite_snapshot_manifest(context, "not json")
	var failed: Dictionary = system.call("delete_game", context)
	_expect(failed.get("ok") == false, "delete rejects corrupt active snapshot")
	_expect_equal(system.call("get_save_context"), context, "corrupt delete keeps active context")
	_complete_and_expect_delivery(pending, "corrupt delete keeps active request valid")
	system.call("close_game")

func _test_same_slot_other_session_delete_invalidates() -> void:
	var active_context := _context("delete_session_scope", "active_session", 0)
	var other_session_context := _context("delete_session_scope", "other_session", 0)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", active_context)
	_expect_ok(system.call("finish_new_game"), "same-slot delete source publishes")
	var pending := _begin_pending_decision(
		system,
		"same-slot-delete-decision",
		"same-slot-delete-action",
	)
	_expect_ok(
		_store.call("save_snapshot", other_session_context, {}),
		"same slot receives another valid session snapshot",
	)
	_expect_ok(
		system.call("delete_game", other_session_context),
		"deleting another session removes the whole active slot",
	)
	_complete_and_expect_stale(
		pending,
		"whole-slot deletion invalidates active session regardless of session id",
	)
	_expect_equal(system.call("get_save_context"), {}, "whole-slot deletion closes active context")

func _test_successful_boundaries_mark_late_results_stale() -> void:
	var close_context := _context("close_slot", "close_session", 0)
	var close_system: RefCounted = _new_agent_system()
	close_system.call("start_new_game", close_context)
	_expect_ok(close_system.call("finish_new_game"), "close source publishes")
	var close_pending := _begin_pending_decision(close_system, "close-decision", "close-action")
	close_system.call("close_game")
	_complete_and_expect_stale(close_pending, "close returns an explicit stale result")
	_new_agent_system().call("delete_game", close_context)

	var target_context := _context("switch_target", "switch_target_session", 0)
	var target_system: RefCounted = _new_agent_system()
	target_system.call("start_new_game", target_context)
	_expect_ok(target_system.call("finish_new_game"), "switch target publishes")
	target_system.call("close_game")
	var source_context := _context("switch_source", "switch_source_session", 0)
	var switch_system: RefCounted = _new_agent_system()
	switch_system.call("start_new_game", source_context)
	_expect_ok(switch_system.call("finish_new_game"), "switch source publishes")
	var switch_pending := _begin_pending_decision(switch_system, "switch-decision", "switch-action")
	_expect_ok(switch_system.call("restore_game", target_context), "slot switch succeeds")
	_complete_and_expect_stale(switch_pending, "successful slot switch marks the late result stale")
	_new_agent_system().call("delete_game", source_context)
	switch_system.call("delete_game", target_context)

	var delete_context := _context("delete_slot", "delete_session", 0)
	var delete_system: RefCounted = _new_agent_system()
	delete_system.call("start_new_game", delete_context)
	_expect_ok(delete_system.call("finish_new_game"), "delete source publishes")
	var delete_pending := _begin_pending_decision(delete_system, "delete-decision", "delete-action")
	_expect_ok(delete_system.call("delete_game", delete_context), "active slot deletes")
	_complete_and_expect_stale(delete_pending, "successful delete marks the late result stale")
	_expect(_new_agent_system().call("restore_game", delete_context).get("ok") == false, "late result cannot recreate deleted slot")

func _test_successful_new_game_publish_marks_late_results_stale() -> void:
	var source_context := _context(
		"new_game_switch_source",
		"new_game_switch_source_session",
		0,
	)
	var target_context := _context(
		"new_game_switch_target",
		"new_game_switch_target_session",
		0,
	)
	var system: RefCounted = _new_agent_system()
	system.call("start_new_game", source_context)
	_expect_ok(system.call("finish_new_game"), "new-game switch source publishes")
	var pending := _begin_pending_decision(
		system,
		"new-game-switch-decision",
		"new-game-switch-action",
	)
	_expect_ok(system.call("start_new_game", target_context), "new-game switch prepares")
	_expect_ok(system.call("finish_new_game"), "new-game switch publishes")
	_complete_and_expect_stale(
		pending,
		"successful new-game publication marks the prior-session result stale",
	)
	_expect_equal(
		system.call("get_save_context"),
		target_context,
		"successful new-game publication activates target context",
	)
	_expect_ok(
		_new_agent_system().call("delete_game", source_context),
		"new-game switch source slot cleans up",
	)
	system.call("delete_game", target_context)
