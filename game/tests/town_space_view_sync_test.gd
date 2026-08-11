extends "res://tests/support/TownWorldTestCase.gd"


const SYNC := preload(
	"res://world/presentation/town_runtime/TownSpaceViewSync.gd"
)


class FakeWorld:
	extends RefCounted

	func get_place_detail(place_name: String) -> Dictionary:
		if place_name == "诊所":
			return {"spaceId": "clinic_interior"}
		return {}


class FakePresentation:
	extends RefCounted
	var active_space_id := "town_outdoor"
	var observed_calls: Array[Dictionary] = []
	var clear_calls := 0

	func get_active_space_id() -> String:
		return active_space_id

	func set_observed_interior(place_name: String, origin: Vector2) -> Dictionary:
		observed_calls.append({"placeName": place_name, "origin": origin})
		active_space_id = "clinic_interior"
		return {"ok": true}

	func clear_observed_interior() -> Dictionary:
		clear_calls += 1
		active_space_id = "town_outdoor"
		return {"ok": true}


class FakeTown:
	extends RefCounted
	var _active_interior_id := ""
	var _active_exterior_portal_id := ""
	var _observed_place_name := ""
	var _interior_roots: Dictionary = {}
	var _world: FakeWorld = null

	func _is_inside_interior() -> bool:
		return not _active_interior_id.is_empty()

	func _place_name_for_portal_id(portal_id: String) -> String:
		if portal_id == "portal-clinic":
			return "诊所"
		return ""


func _initialize() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	_test_outdoor_consistent_no_change()
	_test_indoor_mismatch_switches_to_interior()
	_test_room_hidden_treated_as_outdoor()
	_test_indoor_uses_portal_mapping_over_observed_name()
	_test_unknown_place_skips()
	_test_outdoor_mismatch_clears()
	_finish_suite("TOWN_SPACE_VIEW_SYNC_PASS")


func _make_room(visible: bool) -> Node2D:
	var room := Node2D.new()
	room.visible = visible
	root.add_child(room)
	room.position = Vector2(640, 480)
	return room


func _test_outdoor_consistent_no_change() -> void:
	var town := FakeTown.new()
	town._world = FakeWorld.new()
	var presentation := FakePresentation.new()
	var result: Dictionary = SYNC.reconcile(town, presentation, "t")
	_expect_equal(result.get("changed"), false, "室外一致时不改动")
	_expect_equal(presentation.clear_calls, 0, "不触发clear")
	_expect_equal(presentation.observed_calls.size(), 0, "不触发observe")


func _test_indoor_mismatch_switches_to_interior() -> void:
	var town := FakeTown.new()
	town._world = FakeWorld.new()
	var room := _make_room(true)
	town._active_interior_id = "clinic"
	town._active_exterior_portal_id = "portal-clinic"
	town._interior_roots = {"clinic": room}
	var presentation := FakePresentation.new()
	var result: Dictionary = SYNC.reconcile(town, presentation, "portal_enter")
	_expect_equal(result.get("changed"), true, "失配时发生改动")
	_expect_equal(presentation.observed_calls.size(), 1, "调用一次室内观察")
	_expect_equal(
		presentation.observed_calls[0].get("placeName"),
		"诊所",
		"用portal映射出的地点名",
	)
	_expect_equal(
		presentation.observed_calls[0].get("origin"),
		Vector2(640, 480),
		"原点取房间位置",
	)
	room.queue_free()


func _test_room_hidden_treated_as_outdoor() -> void:
	var town := FakeTown.new()
	town._world = FakeWorld.new()
	var room := _make_room(false)
	town._active_interior_id = "clinic"
	town._active_exterior_portal_id = "portal-clinic"
	town._interior_roots = {"clinic": room}
	var presentation := FakePresentation.new()
	presentation.active_space_id = "clinic_interior"
	var result: Dictionary = SYNC.reconcile(town, presentation, "portal_exit")
	_expect_equal(result.get("changed"), true, "房间隐藏时改回室外")
	_expect_equal(presentation.clear_calls, 1, "清理一次室内观察")
	room.queue_free()


func _test_indoor_uses_portal_mapping_over_observed_name() -> void:
	var town := FakeTown.new()
	town._world = FakeWorld.new()
	var room := _make_room(true)
	town._active_interior_id = "clinic"
	town._active_exterior_portal_id = "portal-clinic"
	town._observed_place_name = "被UI写坏的名字"
	town._interior_roots = {"clinic": room}
	var desired: Dictionary = SYNC.desired_space(town)
	_expect_equal(
		desired.get("placeName"),
		"诊所",
		"portal映射优先于可能被改写的observed名",
	)
	room.queue_free()


func _test_unknown_place_skips() -> void:
	var town := FakeTown.new()
	town._world = FakeWorld.new()
	var room := _make_room(true)
	town._active_interior_id = "clinic"
	town._active_exterior_portal_id = "portal-unknown"
	town._interior_roots = {"clinic": room}
	var presentation := FakePresentation.new()
	var result: Dictionary = SYNC.reconcile(town, presentation, "periodic")
	_expect_equal(result.get("skipped"), true, "判定不出地点时跳过不动")
	_expect_equal(presentation.observed_calls.size(), 0, "不触发observe")
	room.queue_free()


func _test_outdoor_mismatch_clears() -> void:
	var town := FakeTown.new()
	town._world = FakeWorld.new()
	var presentation := FakePresentation.new()
	presentation.active_space_id = "clinic_interior"
	var result: Dictionary = SYNC.reconcile(town, presentation, "periodic")
	_expect_equal(result.get("changed"), true, "人在室外但表现层卡在室内时修正")
	_expect_equal(presentation.clear_calls, 1, "清理一次室内观察")
