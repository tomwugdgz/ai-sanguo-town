extends "res://tests/agent/support/AgentTestCase.gd"


const STORE_SCRIPT_PATH := "res://agent/lifecycle/AgentSaveStore.gd"
const SAVE_FIXTURE_SCRIPT_PATH := "res://tests/support/AgentSaveTestFixture.gd"

var _run_id := ""
var _test_root := ""
var _store: RefCounted
var _test_store_configured := false


func _initialize() -> void:
	_run_id = "store_%d_%d" % [
		OS.get_process_id(),
		int(Time.get_unix_time_from_system() * 1000000.0),
	]
	_test_root = "user://agent_save_tests/%s" % _run_id
	_store = (load(STORE_SCRIPT_PATH) as Script).new()
	var configuration: Dictionary = _store.call("configure_test_root", _test_root)
	if not bool(configuration.get("ok", false)):
		_failures.append("test store root is isolated: %s" % configuration.get("errors", []))
		_finish()
		return
	_test_store_configured = true
	_test_same_resident_payload_is_isolated_between_slots()
	_test_resident_ids_reject_case_insensitive_path_collisions()
	_test_exact_revision_restore_and_non_overwrite()
	_test_incomplete_staging_is_not_visible()
	_test_identity_mismatch_fails()
	_test_missing_manifest_resident_fails()
	_test_payload_corruption_fails_digest_check()
	_finish()


func _test_same_resident_payload_is_isolated_between_slots() -> void:
	var store: RefCounted = _store
	var slot_a := _context("slot_a", "session_a", 0)
	var slot_b := _context("slot_b", "session_b", 0)
	_expect_ok(store.call("create_new_game", slot_a, _payloads("fixture A")), "slot A snapshot is created")
	_expect_ok(store.call("create_new_game", slot_b, _payloads("fixture B")), "slot B snapshot is created")
	_expect_equal(
		store.call("load_snapshot", slot_a).get("resident_payloads", {}).get(
			"resident-lin-lan",
			{},
		).get("payload"),
		_bytes("fixture A"),
		"slot A reads only its opaque fixture payload",
	)
	_expect_equal(
		store.call("load_snapshot", slot_b).get("resident_payloads", {}).get(
			"resident-lin-lan",
			{},
		).get("payload"),
		_bytes("fixture B"),
		"slot B reads only its opaque fixture payload",
	)
	store.call("delete_slot", slot_a)
	store.call("delete_slot", slot_b)


func _test_resident_ids_reject_case_insensitive_path_collisions() -> void:
	var context := _context("case_collision", "case_collision_session", 0)
	var result: Dictionary = _store.call(
		"create_new_game",
		context,
		{"Resident-A": _payload_record("林岚", "case collision")},
	)
	_expect_error_contains(
		result,
		"resident_id",
		"store rejects resident ids whose case variants can share one path",
	)


func _test_exact_revision_restore_and_non_overwrite() -> void:
	var store: RefCounted = _store
	var revision_0 := _context("revision_slot", "revision_session", 0)
	var revision_1 := _context("revision_slot", "revision_session", 1)
	var revision_2 := _context("revision_slot", "revision_session", 2)
	var revision_3 := _context("revision_slot", "revision_session", 3)
	store.call("create_new_game", revision_0, _payloads("revision 0"))
	store.call("save_snapshot", revision_1, _payloads("revision 1"))
	store.call("save_snapshot", revision_2, _payloads("revision 2"))

	_expect_equal(
		store.call("load_snapshot", revision_1).get("resident_payloads", {}).get(
			"resident-lin-lan",
			{},
		).get("payload"),
		_bytes("revision 1"),
		"an older revision restores exactly",
	)
	var overwrite: Dictionary = store.call("save_snapshot", revision_2, _payloads("overwrite"))
	_expect(overwrite.get("ok") == false, "an existing revision cannot be overwritten")
	_expect_equal(
		store.call("load_snapshot", revision_2).get("resident_payloads", {}).get(
			"resident-lin-lan",
			{},
		).get("payload"),
		_bytes("revision 2"),
		"failed overwrite preserves the complete existing snapshot",
	)
	_expect_ok(
		store.call("save_snapshot", revision_3, _payloads("continued after restore")),
		"a new unused revision can continue after restoring an older revision",
	)
	store.call("delete_slot", revision_3)


func _test_incomplete_staging_is_not_visible() -> void:
	var store: RefCounted = _store
	var revision_0 := _context("staging_slot", "staging_session", 0)
	var revision_1 := _context("staging_slot", "staging_session", 1)
	store.call("create_new_game", revision_0, _payloads("complete snapshot"))
	var staging_context := revision_1.duplicate(true)
	var fixture: Script = load(SAVE_FIXTURE_SCRIPT_PATH) as Script
	_expect(
		fixture.call("create_orphan_staging", _test_root, staging_context, _bytes("partial")),
		"interrupted staging fixture is created",
	)
	_expect_equal(
		store.call("load_snapshot", revision_0).get("resident_payloads", {}).get(
			"resident-lin-lan",
			{},
		).get("payload"),
		_bytes("complete snapshot"),
		"an interrupted staging directory cannot replace the last complete snapshot",
	)
	_expect_ok(
		store.call("save_snapshot", revision_1, _payloads("completed later")),
		"an orphan staging directory does not block a later atomic snapshot",
	)
	store.call("delete_slot", revision_1)


func _test_identity_mismatch_fails() -> void:
	var store: RefCounted = _store
	var context := _context("identity_slot", "identity_session", 0)
	store.call("create_new_game", context, {})
	var wrong_slot := context.duplicate(true)
	wrong_slot["slot_id"] = "other_slot"
	var wrong_session := context.duplicate(true)
	wrong_session["session_id"] = "other_session"
	var wrong_revision := context.duplicate(true)
	wrong_revision["save_revision"] = 99
	_expect_error_contains(store.call("load_snapshot", wrong_slot), "slot_id", "slot mismatch fails explicitly")
	_expect_error_contains(store.call("load_snapshot", wrong_session), "session_id", "session mismatch fails explicitly")
	_expect_error_contains(store.call("load_snapshot", wrong_revision), "save_revision", "revision mismatch fails explicitly")
	_expect(store.call("delete_slot", wrong_slot).get("ok") == false, "wrong slot identity cannot delete the root")
	store.call("delete_slot", context)


func _test_payload_corruption_fails_digest_check() -> void:
	var store: RefCounted = _store
	var context := _context("corrupt_slot", "corrupt_session", 0)
	store.call("create_new_game", context, _payloads("original bytes"))
	var fixture: Script = load(SAVE_FIXTURE_SCRIPT_PATH) as Script
	_expect(
		fixture.call("overwrite_first_payload", _test_root, context, _bytes("tampered bytes")),
		"corruption fixture can overwrite resident payload",
	)
	var result: Dictionary = store.call("load_snapshot", context)
	_expect(result.get("ok") == false, "tampered payload fails instead of loading")
	_expect(
		_errors_contain(result.get("errors", []), "byte_length") or _errors_contain(result.get("errors", []), "SHA-256"),
		"tampered payload reports length or digest mismatch",
	)
	# Corrupt fixtures cannot pass delete_slot identity validation, so cleanup is intentionally left to the test root.


func _test_missing_manifest_resident_fails() -> void:
	var store: RefCounted = _store
	var context := _context("missing_resident", "missing_resident_session", 0)
	store.call(
		"create_new_game",
		context,
		{
			"resident-lin-lan": _payload_record("林岚", "resident A"),
			"resident-tang-xiao-man": _payload_record("唐小满", "resident B"),
		},
	)
	var fixture: Script = load(SAVE_FIXTURE_SCRIPT_PATH) as Script
	_expect(
		fixture.call("remove_last_manifest_resident", _test_root, context),
		"manifest resident removal fixture is created",
	)
	_expect_error_contains(
		store.call("load_snapshot", context),
		"居民集合",
		"missing manifest resident fails aggregate identity validation",
	)


func _context(slot_id: String, session_id: String, save_revision: int) -> Dictionary:
	return {
		"slot_id": "%s_%s" % [_run_id, slot_id],
		"session_id": session_id,
		"save_revision": save_revision,
	}


func _bytes(value: String) -> PackedByteArray:
	return value.to_utf8_buffer()


func _payloads(value: String) -> Dictionary:
	return {"resident-lin-lan": _payload_record("林岚", value)}


func _payload_record(resident_name: String, value: String) -> Dictionary:
	return {
		"resident_name": resident_name,
		"payload": _bytes(value),
	}


func _finish() -> void:
	_cleanup_test_store()
	_prepare_project_shutdown()
	if _failures.is_empty():
		print("AGENT_SAVE_STORE_PASS")
		call_deferred("_quit_after_shutdown", 0)
		return
	for failure in _failures:
		printerr("AGENT_SAVE_STORE_FAIL: %s" % failure)
	call_deferred("_quit_after_shutdown", 1)


func _finalize() -> void:
	_cleanup_test_store()


func _cleanup_test_store() -> void:
	if not _test_store_configured:
		return
	var result: Dictionary = _store.call("cleanup_test_root")
	_expect_ok(result, "isolated store test root is removed")
	if bool(result.get("ok", false)):
		_test_store_configured = false
