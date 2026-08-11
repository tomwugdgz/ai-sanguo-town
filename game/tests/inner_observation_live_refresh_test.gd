extends SceneTree


const SERVICE := preload(
	"res://world/presentation/ui/TownUiPageProjectionService.gd"
)


class RefreshWorld:
	extends RefCounted

	signal world_revision_changed(revision: int)

	var revision := 1

	func get_world_revision() -> int:
		return revision

	func get_resident_identity_snapshot() -> Dictionary:
		return {
			"status": "confirmed",
			"residents": [{
				"residentId": "resident-lin-lan",
				"residentName": "林岚",
			}],
		}


class RefreshGateway:
	var latest_focus := "第一条最新想法。"
	var request_count := 0

	func request_resident_inner_observation(
		resident_id: String,
		request_id: String,
		_confirmed_world_revision: int,
		on_complete: Callable,
	) -> Dictionary:
		request_count += 1
		on_complete.call({
			"residentId": resident_id,
			"requestId": request_id,
			"status": "ready",
			"content": {
				"contentKind": "resident_current_focus",
				"monologueText": latest_focus,
				"reasonText": "",
				"playerStatusText": "",
				"empty": false,
				"fallbackUsed": false,
			},
			"errorCode": "",
			"retryable": false,
		})
		return {
			"ok": true,
			"accepted": true,
			"requestId": request_id,
			"errorCode": "",
			"retryable": false,
		}

	func cancel_resident_inner_observation(_request_id: String) -> bool:
		return true


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := RefreshWorld.new()
	var gateway := RefreshGateway.new()
	var service := SERVICE.new()
	var bind_result := service.bind(
		null,
		world,
		{
			"worldStartMode": "formal",
			"source": "runtime",
			"capabilityMode": "formal",
			"formalReady": true,
		},
		gateway,
	) as Dictionary
	_expect(bool(bind_result.get("ok", false)), "live refresh service binds")
	service.set_page_context("resident_action_menu", {
		"residentId": "resident-lin-lan",
		"open": true,
	})
	var open_result := service.dispatch(
		"resident.inner_observation.open",
		{"residentId": "resident-lin-lan"},
	) as Dictionary
	_expect(bool(open_result.get("ok", false)), "inner observation opens")
	var initial := service.get_view_model("inner_observation") as Dictionary
	_expect(
		String((initial.get("data", {}) as Dictionary).get("content", {})
			.get("monologueText", "")) == "第一条最新想法。",
		"inner observation shows the first current thought",
	)

	gateway.latest_focus = "第二条最新想法。"
	world.revision = 2
	world.world_revision_changed.emit(2)
	await process_frame
	var refreshed := service.get_view_model("inner_observation") as Dictionary
	var refreshed_content := (refreshed.get("data", {}) as Dictionary).get(
		"content",
		{},
	) as Dictionary
	_expect(gateway.request_count >= 2, "world revision requests a fresh inner snapshot")
	_expect_equal(
		refreshed_content.get("monologueText"),
		"第二条最新想法。",
		"inner observation replaces stale thought with the latest thought",
	)

	service.unbind()
	if _failures.is_empty():
		print("INNER_OBSERVATION_LIVE_REFRESH_PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("INNER_OBSERVATION_LIVE_REFRESH_FAIL: %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append(
			"%s (actual=%s expected=%s)" % [message, actual, expected]
		)
