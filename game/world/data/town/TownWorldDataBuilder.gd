extends RefCounted

const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const AUTHORING_FILES := preload(
	"res://world/data/town/TownAuthoringFiles.gd"
)
const ACTIVITY_VALIDATOR := preload(
	"res://world/data/town/TownWorldActivityValidator.gd"
)
const SETTINGS_FILE := "settings.json"
const SPACES_FILE := "spaces.json"
const PLACES_FILE := "places.json"
const REGIONS_FILE := "perception_regions.json"
const INDOOR_REGIONS_FILE := "indoor_perception_regions.json"
const CONNECTIONS_FILE := "connections.json"
const OBSERVATION_HOTSPOTS_FILE := "place_observation_hotspots.json"
const MOVEMENT_FILE := "movement_network.json"
const PROPS_FILE := "props.json"
const INDOOR_PROP_AUTHORING_FILE := "indoor_prop_authoring.json"
const OCCUPATION_FILE := "occupation_catalog.json"
const ACTIVITY_DEFINITIONS_FILE := "activity_definitions.json"
const ACTIVITY_SLOTS_FILE := "activity_slots.json"
const SCHEDULE_TEMPLATES_FILE := "schedule_templates.json"
const ACTIVITY_RECEIPT_FIELDS := [
	"receiptVersion",
	"validator",
	"ok",
	"validated",
	"status",
	"sourceWorldId",
	"sourceFingerprint",
	"sourceDocumentFingerprints",
	"staticReferencesValidated",
	"activityChainVerified",
	"placeCapabilitiesVerified",
	"scheduleTemplatesResolved",
	"formalExecutable",
	"errors",
]


static func build_from_source(source_dir: String) -> Dictionary:
	var settings := load_json_object(source_dir.path_join(SETTINGS_FILE))
	var spaces_document := load_json_object(source_dir.path_join(SPACES_FILE))
	var places_document := load_json_object(source_dir.path_join(PLACES_FILE))
	var regions_document := load_json_object(source_dir.path_join(REGIONS_FILE))
	var indoor_regions_document := load_json_object(source_dir.path_join(INDOOR_REGIONS_FILE))
	var connections_document := load_json_object(source_dir.path_join(CONNECTIONS_FILE))
	var observation_hotspots_document := load_json_object(
		source_dir.path_join(OBSERVATION_HOTSPOTS_FILE)
	)
	var movement_document := load_json_object(source_dir.path_join(MOVEMENT_FILE))
	var props_document := load_json_object(source_dir.path_join(PROPS_FILE))
	var indoor_authoring_document := load_json_object(
		source_dir.path_join(INDOOR_PROP_AUTHORING_FILE)
	)
	var occupation_document := load_json_object(
		source_dir.path_join(OCCUPATION_FILE)
	)
	var activity_document := load_json_object(
		source_dir.path_join(ACTIVITY_DEFINITIONS_FILE)
	)
	var slot_document := load_json_object(
		source_dir.path_join(ACTIVITY_SLOTS_FILE)
	)
	var schedule_document := load_json_object(
		source_dir.path_join(SCHEDULE_TEMPLATES_FILE)
	)
	if (
		settings.is_empty()
		or spaces_document.is_empty()
		or places_document.is_empty()
		or regions_document.is_empty()
		or indoor_regions_document.is_empty()
		or connections_document.is_empty()
		or observation_hotspots_document.is_empty()
		or movement_document.is_empty()
		or props_document.is_empty()
		or indoor_authoring_document.is_empty()
		or occupation_document.is_empty()
		or activity_document.is_empty()
		or slot_document.is_empty()
		or schedule_document.is_empty()
		or not _is_town_source_document(settings)
		or not _is_town_source_document(spaces_document)
		or not _is_town_source_document(places_document)
		or not _is_town_source_document(regions_document)
		or not _is_town_source_document(indoor_regions_document)
		or not _is_town_source_document(connections_document)
		or not _is_town_source_document(observation_hotspots_document)
		or not _is_town_source_document(movement_document)
		or not _is_town_source_document(props_document)
		or not _is_town_source_document(indoor_authoring_document)
		or not _is_town_source_document(occupation_document)
		or not _is_town_source_document(activity_document)
		or not _is_town_source_document(slot_document)
		or not _is_town_source_document(schedule_document)
		or not _is_exact_integer(settings.get("schemaVersion"), 1)
		or not _is_positive_integer(settings.get("dataVersion"))
		or not _is_positive_number(settings.get("perceptionRange"))
		or not settings.get("contentStage") is String
		or not _is_string_array(settings.get("pendingSections"))
		or not settings.get("distance") is Dictionary
		or not settings.get("movementRules") is Dictionary
		or not _is_dictionary_array(spaces_document.get("spaces"))
		or not _is_dictionary_array(places_document.get("places"))
		or not _is_dictionary_array(regions_document.get("regions"))
		or not regions_document.get("grid") is Dictionary
		or not _is_dictionary_array(indoor_regions_document.get("regions"))
		or not _is_dictionary_array(connections_document.get("connections"))
		or not observation_hotspots_document.get("hotspots") is Dictionary
		or not _is_dictionary_array(movement_document.get("nodes"))
		or not _is_dictionary_array(movement_document.get("edges"))
		or not _is_dictionary_array(movement_document.get("arrivalNodes"))
		or not _is_dictionary_array(props_document.get("props"))
		or not _is_dictionary_array(props_document.get("indoorNavigation"))
		or not _is_dictionary_array(indoor_authoring_document.get("rooms"))
		or not _is_dictionary_array(indoor_authoring_document.get("outdoorProps"))
		or not _is_dictionary_array(occupation_document.get("occupations"))
		or not _is_dictionary_array(activity_document.get("activities"))
		or not _is_dictionary_array(slot_document.get("slots"))
		or not _is_dictionary_array(schedule_document.get("scheduleTemplates"))
	):
		return {}
	var activity_report := ACTIVITY_VALIDATOR.validate_with_status(
		occupation_document,
		activity_document,
		slot_document,
		places_document,
		props_document,
		indoor_authoring_document,
		schedule_document,
	) as Dictionary
	if not bool(activity_report.get("formalExecutable", false)):
		return {}

	var region_values := (regions_document.get("regions", []) as Array).duplicate(true)
	region_values.append_array(indoor_regions_document.get("regions", []) as Array)
	var regions := _sorted_dictionaries(region_values, "id")
	var places := _attach_region_ids(
		_sorted_dictionaries(places_document.get("places", []) as Array, "name"),
		regions
	)
	var pending_sections := []
	for section_value in settings.get("pendingSections", []) as Array:
		var section := section_value as String
		if not section.is_empty() and section not in pending_sections:
			pending_sections.append(section)
	if regions.is_empty():
		pending_sections.append("perceptionRegions")
	if (connections_document.get("connections", []) as Array).is_empty():
		pending_sections.append("connections")
	if (movement_document.get("nodes", []) as Array).is_empty():
		pending_sections.append("movementNetwork")
	if (props_document.get("props", []) as Array).is_empty():
		pending_sections.append("props")
	pending_sections.sort()
	var content_stage := settings.get("contentStage") as String
	var world_ready := content_stage == "world_ready" and pending_sections.is_empty()

	return {
		"schemaVersion": int(settings.get("schemaVersion", 0)),
		"dataVersion": int(settings.get("dataVersion", 0)),
		"worldId": settings.get("worldId") as String,
		"contentStatus": {
			"stage": content_stage,
			"worldReady": world_ready,
			"pendingSections": pending_sections,
		},
		"distance": (settings.get("distance", {}) as Dictionary).duplicate(true),
		"perceptionRange": float(settings.get("perceptionRange", 0.0)),
		"movementRules": (settings.get("movementRules", {}) as Dictionary).duplicate(true),
		"mapSpaces": _sorted_dictionaries(spaces_document.get("spaces", []) as Array, "id"),
		"places": places,
		"perceptionGrid": (regions_document.get("grid", {}) as Dictionary).duplicate(true),
		"perceptionRegions": regions,
		"connections": _sorted_dictionaries(
			connections_document.get("connections", []) as Array,
			"id"
		),
		"placeObservationHotspots": (
			observation_hotspots_document.get("hotspots", {}) as Dictionary
		).duplicate(true),
		"movementNetwork": {
			"nodes": _sorted_dictionaries(movement_document.get("nodes", []) as Array, "id"),
			"edges": _sorted_dictionaries(movement_document.get("edges", []) as Array, "id"),
			"arrivalNodes": _sorted_dictionaries(
				movement_document.get("arrivalNodes", []) as Array,
				"id"
			),
		},
		"props": _sorted_dictionaries(props_document.get("props", []) as Array, "name"),
		"indoorNavigation": _sorted_dictionaries(
			props_document.get("indoorNavigation", []) as Array,
			"spaceId"
		),
		"occupations": _sorted_dictionaries(
			occupation_document.get("occupations", []) as Array,
			"occupationId",
		),
		"activityDefinitions": _sorted_dictionaries(
			activity_document.get("activities", []) as Array,
			"activityId",
		),
		"activitySlots": _sorted_dictionaries(
			slot_document.get("slots", []) as Array,
			"slotId",
		),
		"scheduleTemplates": _sorted_dictionaries(
			schedule_document.get("scheduleTemplates", []) as Array,
			"scheduleTemplateId",
		),
		"activityIntegrationReceipt": _activity_receipt(activity_report),
	}


static func write_catalog(path: String, data: Dictionary) -> bool:
	if path.is_empty() or data.is_empty():
		return false
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "  ", true) + "\n")
	return true


static func load_json_object(path: String) -> Dictionary:
	return AUTHORING_FILES.load_json_object(path)


static func _is_town_source_document(document: Dictionary) -> bool:
	return (
		_is_exact_integer(document.get("schemaVersion"), 1)
		and document.get("worldId") is String
		and document.get("worldId") == "town"
	)


static func _is_dictionary_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for item in value as Array:
		if not item is Dictionary:
			return false
	return true


static func _is_string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen := {}
	for item in value as Array:
		if not item is String or (item as String).strip_edges().is_empty():
			return false
		if seen.has(item):
			return false
		seen[item] = true
	return true


static func _sorted_dictionaries(values: Array, key: String) -> Array:
	return WORLD_SCALARS.sorted_dictionaries(values, key)


static func _attach_region_ids(places: Array, regions: Array) -> Array:
	var ids_by_place := {}
	for region_value in regions:
		var region := region_value as Dictionary
		var place_name := str(region.get("placeName", ""))
		var ids := ids_by_place.get(place_name, []) as Array
		ids.append(str(region.get("id", "")))
		ids_by_place[place_name] = ids
	for place_value in places:
		var place := place_value as Dictionary
		var place_name := str(place.get("name", ""))
		var ids := ids_by_place.get(place_name, []) as Array
		ids.sort()
		place["perceptionRegionIds"] = ids
	return places


static func _activity_receipt(report: Dictionary) -> Dictionary:
	var receipt := {}
	for field_value: Variant in ACTIVITY_RECEIPT_FIELDS:
		var field := String(field_value)
		var value: Variant = report.get(field)
		if value is Dictionary:
			receipt[field] = (value as Dictionary).duplicate(true)
		elif value is Array:
			receipt[field] = (value as Array).duplicate(true)
		elif value is PackedStringArray:
			receipt[field] = Array(value)
		else:
			receipt[field] = value
	return receipt


static func _is_number(value: Variant) -> bool:
	return WORLD_SCALARS.is_number(value)


static func _is_integer_number(value: Variant) -> bool:
	return _is_number(value) and float(value) == roundf(float(value))


static func _is_exact_integer(value: Variant, expected: int) -> bool:
	return _is_integer_number(value) and float(value) == float(expected)


static func _is_positive_integer(value: Variant) -> bool:
	return _is_integer_number(value) and float(value) > 0.0


static func _is_positive_number(value: Variant) -> bool:
	return _is_number(value) and float(value) > 0.0
