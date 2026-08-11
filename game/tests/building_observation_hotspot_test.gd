extends SceneTree


const HOTSPOT := preload(
	"res://world/presentation/town_runtime/BuildingObservationHotspot.gd"
)
const INPUT_COLLISION_LAYER := 1 << 15

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	_test_configuration_and_hit_area(fixture)
	_test_activation_routes(fixture)
	fixture.queue_free()
	await process_frame
	_finish()


func _test_configuration_and_hit_area(fixture: Node2D) -> void:
	var hotspot := HOTSPOT.new() as Area2D
	fixture.add_child(hotspot)
	_expect_equal(
		hotspot.z_index,
		170,
		"building hotspot renders above an overlapping roof marker",
	)
	_expect_equal(
		hotspot.configure(
			"重叠房屋",
			Vector2(320.0, 240.0),
			Vector2(120.0, 96.0),
		),
		true,
		"building hotspot accepts its authored world footprint",
	)
	_expect_equal(
		hotspot.collision_layer,
		INPUT_COLLISION_LAYER,
		"building hotspot keeps the dedicated pointer collision layer",
	)
	_expect_equal(
		hotspot.collision_mask,
		0,
		"building hotspot does not scan resident bodies",
	)
	var input_shape := hotspot.get_node_or_null("InputShape") as CollisionShape2D
	var rectangle := input_shape.shape as RectangleShape2D if input_shape != null else null
	_expect(rectangle != null, "building hotspot owns a rectangular full-footprint hit shape")
	if rectangle != null:
		_expect_equal(
			rectangle.size,
			Vector2(120.0, 96.0),
			"building hotspot hit shape covers the complete authored footprint",
		)
	hotspot.set_available(true)
	_expect(hotspot.input_pickable, "available building hotspot accepts pointer input")
	hotspot.queue_free()


func _test_activation_routes(fixture: Node2D) -> void:
	var hotspot := HOTSPOT.new() as Area2D
	hotspot.configure("重叠房屋", Vector2(480.0, 360.0), Vector2(120.0, 96.0))
	fixture.add_child(hotspot)
	hotspot.set_available(true)
	var viewport := root.get_viewport()
	var activation := {"count": 0, "placeName": ""}
	hotspot.activated.connect(func(place_name: String) -> void:
		activation["count"] = int(activation["count"]) + 1
		activation["placeName"] = place_name
	)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	hotspot.call("_input_event", viewport, click, 0)
	_expect_equal(
		activation["count"],
		1,
		"a direct building click emits one activation",
	)
	_expect_equal(
		activation["placeName"],
		"重叠房屋",
		"building activation preserves the configured place name",
	)
	hotspot.call("activate_from_overlapping_marker", viewport, click)
	_expect_equal(
		activation["count"],
		2,
		"a roof marker overlap can delegate to the same building activation",
	)
	hotspot.set_available(false)
	hotspot.call("activate_from_overlapping_marker", viewport, click)
	_expect_equal(
		activation["count"],
		2,
		"a disabled building ignores delegated overlap activation",
	)
	hotspot.queue_free()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(
		actual == expected,
		"%s; expected=%s actual=%s" % [message, expected, actual],
	)


func _finish() -> void:
	if _failures.is_empty():
		print("BUILDING_OBSERVATION_HOTSPOT_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("BUILDING_OBSERVATION_HOTSPOT_FAIL: %s" % failure)
	print("BUILDING_OBSERVATION_HOTSPOT_FAIL checks=%d" % _checks)
	quit(1)
