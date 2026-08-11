extends SceneTree


const SOURCE_DIR := "res://world/data/town/source"
const SETTINGS_PATH := SOURCE_DIR + "/settings.json"
const SPACES_PATH := SOURCE_DIR + "/spaces.json"
const PLACES_PATH := SOURCE_DIR + "/places.json"
const PERCEPTION_PATH := SOURCE_DIR + "/perception_regions.json"
const AUTHORING_PATH := SOURCE_DIR + "/route_authoring.json"
const MOVEMENT_OUTPUT_PATH := SOURCE_DIR + "/movement_network.json"
const CONNECTIONS_OUTPUT_PATH := SOURCE_DIR + "/connections.json"
const INDOOR_REGIONS_OUTPUT_PATH := SOURCE_DIR + "/indoor_perception_regions.json"
const OUTDOOR_NAVIGATION_OUTPUT_PATH := SOURCE_DIR + "/outdoor_navigation_grid.json"
const BUILDER := preload("res://world/data/town/TownRouteNetworkBuilder.gd")
const VALIDATOR := preload("res://world/data/town/TownWorldMovementValidator.gd")


func _initialize() -> void:
	var settings := BUILDER.load_json_object(SETTINGS_PATH)
	var spaces := BUILDER.load_json_object(SPACES_PATH)
	var places := BUILDER.load_json_object(PLACES_PATH)
	var perception := BUILDER.load_json_object(PERCEPTION_PATH)
	var authoring := BUILDER.load_json_object(AUTHORING_PATH)
	if (
		settings.is_empty()
		or spaces.is_empty()
		or places.is_empty()
		or perception.is_empty()
		or authoring.is_empty()
	):
		_fail("无法读取路网生成所需的正式源数据")
		return

	var build_result: Dictionary = BUILDER.new().build_documents(
		perception,
		spaces,
		authoring,
	)
	if not bool(build_result.get("ok", false)):
		for error_value in build_result.get("errors", []) as Array:
			printerr("TOWN_ROUTE_NETWORK_AUTHORING_FAIL: %s" % error_value)
		quit(1)
		return

	var documents := build_result.get("documents", {}) as Dictionary
	var data := BUILDER.assemble_validation_data(
		settings,
		spaces,
		places,
		perception,
		documents,
	)
	var validation_errors := VALIDATOR.validate(data)
	if not validation_errors.is_empty():
		for error in validation_errors:
			printerr("TOWN_ROUTE_NETWORK_AUTHORING_FAIL: %s" % error)
		quit(1)
		return

	if not OS.get_cmdline_user_args().has("--check-only"):
		if not _write_outputs(documents):
			_fail("无法写入冻结路网、地点连接或室内入口区域")
			return

	var movement := documents.get("movement", {}) as Dictionary
	var connections := documents.get("connections", {}) as Dictionary
	print(
		"TOWN_ROUTE_NETWORK_AUTHORING_PASS: %d nodes, %d edges, %d connections"
		% [
			(movement.get("nodes", []) as Array).size(),
			(movement.get("edges", []) as Array).size(),
			(connections.get("connections", []) as Array).size(),
		]
	)
	quit(0)


func _write_outputs(documents: Dictionary) -> bool:
	return (
		BUILDER.write_document(
			MOVEMENT_OUTPUT_PATH,
			documents.get("movement", {}) as Dictionary,
		)
		and BUILDER.write_document(
			CONNECTIONS_OUTPUT_PATH,
			documents.get("connections", {}) as Dictionary,
		)
		and BUILDER.write_document(
			INDOOR_REGIONS_OUTPUT_PATH,
			documents.get("indoorRegions", {}) as Dictionary,
		)
		and BUILDER.write_document(
			OUTDOOR_NAVIGATION_OUTPUT_PATH,
			documents.get("outdoorNavigation", {}) as Dictionary,
		)
	)


func _fail(message: String) -> void:
	printerr("TOWN_ROUTE_NETWORK_AUTHORING_FAIL: %s" % message)
	quit(1)
