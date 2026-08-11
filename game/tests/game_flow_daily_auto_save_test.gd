extends SceneTree


const GAME_FLOW_HOST := preload(
	"res://world/presentation/game_flow/GameFlowHost.gd"
)

var _failures: Array[String] = []


class DailyAutoSaveService:
	extends RefCounted
	var should_fail := false
	var calls: Array[Dictionary] = []
	var revision := 10

	func create_save(payload: Dictionary = {}) -> Dictionary:
		calls.append(payload.duplicate(true))
		if should_fail:
			return {
				"ok": false,
				"errorCode": "SESSION_SAVE_BUSY",
				"retryable": true,
			}
		revision += 1
		return {
			"ok": true,
			"errorCode": "",
			"retryable": false,
			"manifest": {"save_revision": revision},
		}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host: Node = GAME_FLOW_HOST.new()
	var service := DailyAutoSaveService.new()
	host.set("_session_ui_service", service)
	host.set("_daily_auto_save_day", 1)
	host.call("_on_town_environment_changed", {"day": 2}, "晴朗")
	var first := host.call("get_daily_auto_save_diagnostics") as Dictionary
	_expect_equal(service.calls.size(), 1, "day boundary performs one automatic save")
	_expect_equal(
		(service.calls[0] as Dictionary).get("reason"),
		"daily_auto_save",
		"automatic save uses the internal daily reason",
	)
	_expect_equal(first.get("lastSavedDay"), 2, "successful automatic save records the day")
	_expect_equal(first.get("successes"), 1, "successful automatic save is counted")
	_expect_equal(first.get("lastRevision"), 11, "successful automatic save records its revision")
	host.call("_on_town_environment_changed", {"day": 2}, "晴朗")
	_expect_equal(service.calls.size(), 1, "the same day is never saved twice")

	service.should_fail = true
	host.set("_daily_auto_save_day", 2)
	host.set("_daily_auto_save_last_attempt_msec", -100000)
	host.call("_on_town_environment_changed", {"day": 3}, "晴朗")
	var failed := host.call("get_daily_auto_save_diagnostics") as Dictionary
	_expect_equal(failed.get("lastSavedDay"), 2, "failed automatic save preserves the last confirmed day")
	_expect_equal(failed.get("failures", []).size(), 1, "automatic save failure stays in diagnostics")
	_expect_equal(
		(failed.get("failures", [])[0] as Dictionary).get("errorCode"),
		"SESSION_SAVE_BUSY",
		"automatic save keeps the internal failure code out of the player path",
	)
	service.should_fail = false
	host.set("_daily_auto_save_last_attempt_msec", -100000)
	host.call("_on_town_environment_changed", {"day": 3}, "晴朗")
	var recovered := host.call("get_daily_auto_save_diagnostics") as Dictionary
	_expect_equal(recovered.get("lastSavedDay"), 3, "a later retry publishes the missed day")
	_expect_equal(recovered.get("successes"), 2, "automatic save recovery is counted")
	host.free()
	_finish()


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failures.append("%s (actual=%s expected=%s)" % [label, actual, expected])
	push_error(_failures.back())


func _finish() -> void:
	var exit_code := 0 if _failures.is_empty() else 1
	if _failures.is_empty():
		print("GAME_FLOW_DAILY_AUTO_SAVE_PASS")
	else:
		printerr("GAME_FLOW_DAILY_AUTO_SAVE_FAIL: %s" % "; ".join(_failures))
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
	for _index in 5:
		await process_frame
	await create_timer(0.3, true, false, true).timeout
	quit(exit_code)
