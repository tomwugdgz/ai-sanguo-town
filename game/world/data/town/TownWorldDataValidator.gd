extends RefCounted

const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const ACTIVITY_CAPABILITY_CONTRACT := preload(
	"res://world/data/town/TownPlaceActivityCapabilityContract.gd"
)
const ACTIVITY_VALIDATOR := preload(
	"res://world/data/town/TownWorldActivityValidator.gd"
)
const OUTDOOR_MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)
const VALID_SPACE_TYPES := ["室外", "室内"]
const VALID_PLACE_TYPES := ["公共地点", "住家", "铺面"]
const REQUIRED_SOURCE_ARRAYS := {
	"settings.json": [],
	"spaces.json": ["spaces"],
	"places.json": ["places"],
	"perception_regions.json": ["regions"],
	"indoor_perception_regions.json": ["regions"],
	"connections.json": ["connections"],
	"place_observation_hotspots.json": [],
	"movement_network.json": ["nodes", "edges", "arrivalNodes"],
	"props.json": ["props", "indoorNavigation"],
	"indoor_prop_authoring.json": ["rooms", "outdoorProps"],
	"outdoor_perception_masks.json": ["masks"],
	"route_authoring.json": ["junctions"],
	"outdoor_navigation_grid.json": ["cells"],
	"occupation_catalog.json": ["occupations"],
	"activity_definitions.json": ["activities"],
	"activity_slots.json": ["slots"],
	"schedule_templates.json": ["scheduleTemplates"],
}
const FORBIDDEN_RUNTIME_KEYS := [
	"owner",
	"residentId",
	"nodePath",
	"scenePath",
	"collisionLayer",
	"collisionMask",
	"mapToolId",
	"triggerArea",
]


static func validate_source_directory(source_dir: String) -> PackedStringArray:
	var errors := PackedStringArray()
	for file_name in REQUIRED_SOURCE_ARRAYS:
		var path := source_dir.path_join(str(file_name))
		if not FileAccess.file_exists(path):
			errors.append("缺少源数据文件：%s" % file_name)
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("源数据文件不是合法 JSON 对象：%s" % file_name)
			continue
		var document := parsed as Dictionary
		if file_name == "outdoor_navigation_grid.json":
			errors.append_array(validate_outdoor_navigation_grid(document))
			continue
		if not _is_exact_integer(document.get("schemaVersion"), 1):
			errors.append("%s.schemaVersion 必须为 1" % file_name)
		if not document.get("worldId") is String or document.get("worldId") != "town":
			errors.append("%s.worldId 必须为 town" % file_name)
		if file_name == "settings.json":
			if not _is_positive_integer(document.get("dataVersion")):
				errors.append("settings.json.dataVersion 必须为正整数")
			if not _is_positive_number(document.get("perceptionRange")):
				errors.append("settings.json.perceptionRange 必须为有限正数")
			_validate_settings_source(document, errors)
		elif file_name == "perception_regions.json" and not document.get("grid") is Dictionary:
			errors.append("perception_regions.json.grid 必须为对象")
		for key_value in REQUIRED_SOURCE_ARRAYS[file_name] as Array:
			var key := key_value as String
			var array_value: Variant = document.get(key)
			if not array_value is Array:
				errors.append("%s.%s 必须为数组" % [file_name, key])
				continue
			_validate_object_array(array_value as Array, "%s.%s" % [file_name, key], errors)
			if file_name == "places.json" and key == "places":
				_validate_source_places(array_value as Array, errors)
	return errors


static func validate_outdoor_navigation_grid(
	document: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	var label := "outdoor_navigation_grid.json"
	if not _is_exact_integer(document.get("schemaVersion"), 1):
		errors.append("%s.schemaVersion 必须为 1" % label)
	if not document.get("worldId") is String or document.get("worldId") != "town":
		errors.append("%s.worldId 必须为 town" % label)
	var cell_size_value: Variant = document.get("cellSize")
	var width_value: Variant = document.get("width")
	var height_value: Variant = document.get("height")
	if (
		not _is_positive_integer(cell_size_value)
		or not _is_positive_integer(width_value)
		or not _is_positive_integer(height_value)
	):
		errors.append("%s 的 cellSize、width 和 height 必须为有限正整数" % label)
		return errors
	var cell_size := int(cell_size_value)
	var width := int(width_value)
	var height := int(height_value)
	var map_size := OUTDOOR_MOVEMENT_CLEARANCE.MAP_SIZE
	var expected_width := ceili(map_size.x / float(cell_size))
	var expected_height := ceili(map_size.y / float(cell_size))
	if (
		cell_size > ceili(maxf(map_size.x, map_size.y))
		or width != expected_width
		or height != expected_height
	):
		errors.append(
			"%s 的 width 和 height 必须准确覆盖正式地图尺寸" % label
		)
	var cells_value: Variant = document.get("cells")
	if not cells_value is Array or (cells_value as Array).is_empty():
		errors.append("%s.cells 必须为非空数组" % label)
		return errors
	var cells := cells_value as Array
	var cells_by_key := {}
	var masks_by_key := {}
	for index in cells.size():
		var value: Variant = cells[index]
		if value is not Array or (value as Array).size() != 3:
			errors.append("%s.cells[%d] 必须是 [x, y, 连接方向]" % [label, index])
			continue
		var pair := value as Array
		if (
			not _is_integer_number(pair[0])
			or not _is_integer_number(pair[1])
			or not _is_integer_number(pair[2])
		):
			errors.append("%s.cells[%d] 必须使用有限整数" % [label, index])
			continue
		var cell := Vector2i(int(pair[0]), int(pair[1]))
		var mask := int(pair[2])
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
			errors.append("%s.cells[%d] 超出 width/height 边界" % [label, index])
			continue
		if mask < 0 or mask > 15:
			errors.append("%s.cells[%d] 的连接方向必须在 0 到 15 之间" % [label, index])
			continue
		var key := _grid_cell_key(cell.x, cell.y)
		if cells_by_key.has(key):
			errors.append("%s.cells 包含重复格：%s" % [label, key])
			continue
		cells_by_key[key] = cell
		masks_by_key[key] = mask
	if not errors.is_empty():
		return errors
	var adjacency := {}
	for key_value: Variant in cells_by_key:
		adjacency[String(key_value)] = []
	for key_value: Variant in cells_by_key:
		var key := String(key_value)
		var cell := cells_by_key[key] as Vector2i
		var mask := int(masks_by_key.get(key, 0))
		for direction: Dictionary in [
			{"bit": 1, "offset": Vector2i.RIGHT},
			{"bit": 2, "offset": Vector2i.DOWN},
			{"bit": 4, "offset": Vector2i(1, 1)},
			{"bit": 8, "offset": Vector2i(-1, 1)},
		]:
			if mask & int(direction["bit"]) == 0:
				continue
			var offset := direction["offset"] as Vector2i
			var neighbor := cell + offset
			var neighbor_key := _grid_cell_key(neighbor.x, neighbor.y)
			if not cells_by_key.has(neighbor_key):
				errors.append("%s 的格 %s 连接到不存在的邻格" % [label, key])
				continue
			if (
				offset.x != 0
				and offset.y != 0
				and (
					not cells_by_key.has(_grid_cell_key(cell.x + offset.x, cell.y))
					or not cells_by_key.has(_grid_cell_key(cell.x, cell.y + offset.y))
				)
			):
				errors.append("%s 的格 %s 存在穿角对角连接" % [label, key])
				continue
			(adjacency[key] as Array).append(neighbor_key)
			(adjacency[neighbor_key] as Array).append(key)
	if not errors.is_empty():
		return errors
	var first_key := String(cells_by_key.keys()[0])
	var visited := {first_key: true}
	var queue: Array[String] = [first_key]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for neighbor: String in adjacency[current] as Array:
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	if visited.size() != cells_by_key.size():
		errors.append(
			"%s.cells 必须全部处于同一个连通区域（%d/%d）"
			% [label, visited.size(), cells_by_key.size()]
		)
	return errors


static func _validate_settings_source(
	document: Dictionary,
	errors: PackedStringArray,
) -> void:
	if not document.get("contentStage") is String:
		errors.append("settings.json.contentStage 必须为字符串")
	var pending_sections_value: Variant = document.get("pendingSections")
	if not pending_sections_value is Array:
		errors.append("settings.json.pendingSections 必须为数组")
	else:
		_validate_string_array(
			pending_sections_value as Array,
			"settings.json.pendingSections",
			errors,
		)
	if not document.get("distance") is Dictionary:
		errors.append("settings.json.distance 必须为对象")
	if not document.get("movementRules") is Dictionary:
		errors.append("settings.json.movementRules 必须为对象")


static func _validate_object_array(
	values: Array,
	path: String,
	errors: PackedStringArray,
) -> void:
	for index in values.size():
		if not values[index] is Dictionary:
			errors.append("%s[%d] 必须为对象" % [path, index])


static func _validate_source_places(
	places: Array,
	errors: PackedStringArray,
) -> void:
	for place_value: Variant in places:
		if not place_value is Dictionary:
			continue
		var place := place_value as Dictionary
		var place_name_value: Variant = place.get("name")
		var place_name := (
			place_name_value as String
			if place_name_value is String
			else ""
		)
		var capabilities_value: Variant = place.get("capabilities")
		if not capabilities_value is Dictionary:
			errors.append("地点 %s 缺少 capabilities" % place_name)
			continue
		var capabilities := capabilities_value as Dictionary
		_validate_capabilities(place_name, capabilities, errors)
		errors.append_array(
			ACTIVITY_CAPABILITY_CONTRACT.validate(place_name, capabilities)
		)
	errors.append_array(
		ACTIVITY_CAPABILITY_CONTRACT.validate_required_places(places)
	)


static func validate_foundation(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.is_empty():
		errors.append("World 静态数据为空")
		return errors

	_validate_settings(data, errors)
	var spaces_value: Variant = data.get("mapSpaces")
	var places_value: Variant = data.get("places")
	if not spaces_value is Array:
		errors.append("mapSpaces 必须为数组")
		return errors
	if not places_value is Array:
		errors.append("places 必须为数组")
		return errors

	var spaces := spaces_value as Array
	var places := places_value as Array
	var spaces_by_id := {}
	var space_names := {}
	var indoor_space_ids := {}
	var outdoor_space_ids := {}
	for index in spaces.size():
		var value: Variant = spaces[index]
		if not value is Dictionary:
			errors.append("mapSpaces[%d] 必须为对象" % index)
			continue
		var space := value as Dictionary
		var space_id := _string_value(space.get("id"), "mapSpaces[%d].id" % index, errors)
		var space_name := _string_value(space.get("name"), "mapSpaces[%d].name" % index, errors)
		_validate_unique_text(space_id, "地图空间 id", spaces_by_id, errors)
		_validate_unique_text(space_name, "地图空间名字", space_names, errors)
		var space_type := _string_value(space.get("type"), "mapSpaces[%d].type" % index, errors)
		if space_type not in VALID_SPACE_TYPES:
			errors.append("地图空间 %s 的 type 无效：%s" % [space_id, space_type])
		elif space_type == "室内":
			indoor_space_ids[space_id] = true
		else:
			outdoor_space_ids[space_id] = true
		_validate_coordinate_system(space_id, space.get("coordinateSystem"), errors)
		_validate_bounds(space_id, space.get("bounds"), errors)

	if spaces.size() != 24:
		errors.append("正式小镇必须定义 24 个地图空间，实际为 %d" % spaces.size())
	if indoor_space_ids.size() != 23:
		errors.append("正式小镇必须定义 23 个独立室内空间，实际为 %d" % indoor_space_ids.size())
	if outdoor_space_ids.size() != 1 or not outdoor_space_ids.has("town_outdoor"):
		errors.append("正式小镇必须且只能定义 town_outdoor 一个室外空间")

	var place_names := {}
	var place_count_by_space := {}
	var home_count := 0
	var shop_count := 0
	var workplace_count := 0
	var outdoor_place_count := 0
	for index in places.size():
		var value: Variant = places[index]
		if not value is Dictionary:
			errors.append("places[%d] 必须为对象" % index)
			continue
		var place := value as Dictionary
		var place_name := _string_value(place.get("name"), "places[%d].name" % index, errors)
		_validate_unique_text(place_name, "地点中文名", place_names, errors)
		if not _contains_cjk(place_name):
			errors.append("地点名字必须包含中文：%s" % place_name)
		if place.has("id"):
			errors.append("地点 %s 不应另设 id；中文 name 就是地点身份" % place_name)
		var place_type := _string_value(place.get("type"), "places[%d].type" % index, errors)
		if place_type not in VALID_PLACE_TYPES:
			errors.append("地点 %s 的 type 无效：%s" % [place_name, place_type])
		var space_id := _string_value(place.get("spaceId"), "places[%d].spaceId" % index, errors)
		if not spaces_by_id.has(space_id):
			errors.append("地点 %s 引用了不存在的地图空间：%s" % [place_name, space_id])
		else:
			place_count_by_space[space_id] = int(place_count_by_space.get(space_id, 0)) + 1
			if outdoor_space_ids.has(space_id):
				outdoor_place_count += 1
		var summary_value: Variant = place.get("summary")
		if not summary_value is String or (summary_value as String).strip_edges().is_empty():
			errors.append("地点 %s 的 summary 必须为非空字符串" % place_name)
		if place.has("visibleFeatures"):
			var visible_features_value: Variant = place.get("visibleFeatures")
			if not visible_features_value is Array:
				errors.append("地点 %s 的 visibleFeatures 必须为数组" % place_name)
			else:
				var seen_visible_features := {}
				for feature_index in (visible_features_value as Array).size():
					var feature_value: Variant = (
						visible_features_value as Array
					)[feature_index]
					if (
						not feature_value is String
						or String(feature_value).strip_edges().is_empty()
					):
						errors.append(
							"地点 %s 的 visibleFeatures[%d] 必须为非空字符串"
							% [place_name, feature_index]
						)
						continue
					var feature := String(feature_value).strip_edges()
					if seen_visible_features.has(feature):
						errors.append(
							"地点 %s 的 visibleFeatures 不能重复：%s"
							% [place_name, feature]
						)
					seen_visible_features[feature] = true
		var capabilities_value: Variant = place.get("capabilities")
		if not capabilities_value is Dictionary:
			errors.append("地点 %s 缺少 capabilities" % place_name)
			continue
		var capabilities := capabilities_value as Dictionary
		_validate_capabilities(place_name, capabilities, errors)
		errors.append_array(
			ACTIVITY_CAPABILITY_CONTRACT.validate(place_name, capabilities)
		)
		var assignable_value: Variant = capabilities.get("assignableWorkplace")
		var assignable_workplace := false
		if not assignable_value is bool:
			errors.append("地点 %s 的 assignableWorkplace 必须为布尔值" % place_name)
		else:
			assignable_workplace = assignable_value == true
		if assignable_workplace:
			workplace_count += 1
		if place_type == "住家":
			home_count += 1
			if not indoor_space_ids.has(space_id):
				errors.append("住家 %s 必须属于独立室内空间" % place_name)
			if assignable_workplace:
				errors.append("住家 %s 不应同时成为可分配工作地" % place_name)
		elif place_type == "铺面":
			shop_count += 1
			if not indoor_space_ids.has(space_id):
				errors.append("铺面 %s 必须属于室内空间" % place_name)
			if not assignable_workplace:
				errors.append("铺面 %s 必须同时是可分配工作地" % place_name)
		var region_ids_value: Variant = place.get("perceptionRegionIds")
		if not region_ids_value is Array:
			errors.append("地点 %s 的 perceptionRegionIds 必须为数组" % place_name)
		else:
			_validate_string_array(region_ids_value as Array, "%s.perceptionRegionIds" % place_name, errors)

	errors.append_array(
		ACTIVITY_CAPABILITY_CONTRACT.validate_required_places(places)
	)
	if places.size() != 30:
		errors.append("地点台账必须包含 30 个地点，实际为 %d" % places.size())
	if outdoor_place_count != 7:
		errors.append("室外空间必须包含 7 个公共地点，实际为 %d" % outdoor_place_count)
	if home_count != 15:
		errors.append("住家槽位必须为 15 个，实际为 %d" % home_count)
	if shop_count != 4:
		errors.append("铺面槽位必须为 4 个，实际为 %d" % shop_count)
	var expected_workplace_count := (
		ACTIVITY_CAPABILITY_CONTRACT.EXPECTED_ACTIVITY_CAPABILITIES.size()
	)
	if workplace_count != expected_workplace_count:
		errors.append(
			"可分配工作地必须为 %d 个，实际为 %d"
			% [expected_workplace_count, workplace_count]
		)

	for space_id in indoor_space_ids:
		var count := int(place_count_by_space.get(space_id, 0))
		if count != 1:
			errors.append("室内空间 %s 必须唯一对应一个地点，实际为 %d" % [space_id, count])

	_validate_place_observation_hotspots(data, errors)
	_validate_forbidden_keys(data, "world", errors)
	return errors


static func validate_activity_integration_source(
	source_dir: String,
) -> Dictionary:
	var occupation_document := _load_source_document(
		source_dir,
		"occupation_catalog.json",
	)
	var activity_document := _load_source_document(
		source_dir,
		"activity_definitions.json",
	)
	var slot_document := _load_source_document(
		source_dir,
		"activity_slots.json",
	)
	var places_document := _load_source_document(
		source_dir,
		"places.json",
	)
	var props_document := _load_source_document(
		source_dir,
		"props.json",
	)
	var indoor_authoring_document := _load_source_document(
		source_dir,
		"indoor_prop_authoring.json",
	)
	var schedule_document := _load_source_document(
		source_dir,
		"schedule_templates.json",
	)
	return ACTIVITY_VALIDATOR.validate_with_status(
		occupation_document,
		activity_document,
		slot_document,
		places_document,
		props_document,
		indoor_authoring_document,
		schedule_document,
	)


static func validate_activity_integration_receipt(
	data: Dictionary,
	source_dir: String,
) -> PackedStringArray:
	var errors := PackedStringArray()
	var report := validate_activity_integration_source(source_dir)
	if not bool(report.get("formalExecutable", false)):
		errors.append_array(
			report.get("errors", PackedStringArray()) as PackedStringArray
		)
		errors.append("Activity Integration 源数据未达到 formalExecutable")
		return errors
	if data.is_empty():
		errors.append("World 输出为空，未编译 Activity Integration")
		return errors
	var receipt_value: Variant = data.get("activityIntegrationReceipt")
	if not receipt_value is Dictionary:
		errors.append("World 输出缺少 activityIntegrationReceipt")
		return errors
	var receipt := receipt_value as Dictionary
	var expected_receipt := _activity_receipt_projection(report)
	if not _activity_receipt_matches(receipt, expected_receipt):
		errors.append(
			"activityIntegrationReceipt 必须精确等于 Validator 报告白名单投影"
		)
	var expected_document_fingerprints := report.get(
		"sourceDocumentFingerprints",
		{},
	) as Dictionary
	if int(receipt.get("receiptVersion", 0)) != 1:
		errors.append("activityIntegrationReceipt.receiptVersion 必须为 1")
	if String(receipt.get("validator", "")) != "TownWorldActivityValidator":
		errors.append("activityIntegrationReceipt.validator 非法")
	if String(receipt.get("sourceWorldId", "")) != "town":
		errors.append("activityIntegrationReceipt.sourceWorldId 必须为 town")
	if (
		receipt.get("ok") != true
		or receipt.get("validated") != true
		or String(receipt.get("status", "")) != "formal_executable"
	):
		errors.append("activityIntegrationReceipt 缺少正式 Validator 状态")
	var receipt_errors_value: Variant = receipt.get("errors")
	if (
		not receipt_errors_value is Array
		or not (receipt_errors_value as Array).is_empty()
	):
		errors.append("activityIntegrationReceipt.errors 必须为空数组")
	if (
		String(receipt.get("sourceFingerprint", ""))
		!= String(report.get("sourceFingerprint", ""))
	):
		errors.append("Activity Integration 收据与 exact source fingerprint 不匹配")
	var receipt_document_fingerprints: Variant = receipt.get(
		"sourceDocumentFingerprints"
	)
	if (
		not receipt_document_fingerprints is Dictionary
		or receipt_document_fingerprints != expected_document_fingerprints
	):
		errors.append("Activity Integration 收据未绑定 exact 七份源文档")
	for field in [
		"staticReferencesValidated",
		"activityChainVerified",
		"placeCapabilitiesVerified",
		"scheduleTemplatesResolved",
		"formalExecutable",
	]:
		var field_value: Variant = receipt.get(field)
		if typeof(field_value) != TYPE_BOOL or not bool(field_value):
			errors.append("activityIntegrationReceipt.%s 必须为 true" % field)
	var occupation_document := _load_source_document(
		source_dir,
		"occupation_catalog.json",
	)
	var activity_document := _load_source_document(
		source_dir,
		"activity_definitions.json",
	)
	var slot_document := _load_source_document(
		source_dir,
		"activity_slots.json",
	)
	var schedule_document := _load_source_document(
		source_dir,
		"schedule_templates.json",
	)
	var places_document := _load_source_document(
		source_dir,
		"places.json",
	)
	_validate_compiled_section(
		data.get("occupations"),
		occupation_document.get("occupations"),
		"occupationId",
		"occupations",
		errors,
	)
	_validate_compiled_section(
		data.get("activityDefinitions"),
		activity_document.get("activities"),
		"activityId",
		"activityDefinitions",
		errors,
	)
	_validate_compiled_section(
		data.get("activitySlots"),
		slot_document.get("slots"),
		"slotId",
		"activitySlots",
		errors,
	)
	_validate_compiled_section(
		data.get("scheduleTemplates"),
		schedule_document.get("scheduleTemplates"),
		"scheduleTemplateId",
		"scheduleTemplates",
		errors,
	)
	_validate_compiled_place_capabilities(
		data.get("places"),
		places_document.get("places"),
		errors,
	)
	return errors


static func _activity_receipt_projection(report: Dictionary) -> Dictionary:
	var result := {}
	for field in [
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
	]:
		var value: Variant = report.get(field)
		if value is Dictionary:
			result[field] = (value as Dictionary).duplicate(true)
		elif value is Array:
			result[field] = (value as Array).duplicate(true)
		elif value is PackedStringArray:
			result[field] = Array(value)
		else:
			result[field] = value
	return result


static func _activity_receipt_matches(
	receipt: Dictionary,
	expected: Dictionary,
) -> bool:
	if receipt.size() != expected.size():
		return false
	for key_value: Variant in expected.keys():
		if not receipt.has(key_value):
			return false
		var key := String(key_value)
		var actual_value: Variant = receipt.get(key_value)
		var expected_value: Variant = expected.get(key_value)
		var actual_type := typeof(actual_value)
		var expected_type := typeof(expected_value)
		if key == "receiptVersion":
			if (
				not _is_integer_number(actual_value)
				or not _is_integer_number(expected_value)
				or int(actual_value) != int(expected_value)
			):
				return false
		elif actual_type != expected_type:
			return false
		elif actual_value != expected_value:
			return false
	return true


static func _validate_compiled_place_capabilities(
	actual_value: Variant,
	source_value: Variant,
	errors: PackedStringArray,
) -> void:
	if not actual_value is Array or not source_value is Array:
		errors.append("places capabilities 必须由权威 places 源完整编译")
		return
	var actual_projection := _place_capability_projection(actual_value as Array)
	var source_projection := _place_capability_projection(source_value as Array)
	if actual_projection != source_projection:
		errors.append(
			"places capabilities 与收据绑定的 exact source places 不一致"
		)


static func _place_capability_projection(places: Array) -> Array:
	var result: Array = []
	for value: Variant in places:
		if not value is Dictionary:
			result.append({"invalid": true})
			continue
		var place := value as Dictionary
		result.append({
			"name": String(place.get("name", "")),
			"spaceId": String(place.get("spaceId", "")),
			"type": String(place.get("type", "")),
			"capabilities": (
				place.get("capabilities", {}) as Dictionary
			).duplicate(true),
		})
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_place := left as Dictionary
		var right_place := right as Dictionary
		return (
			"%s\u001f%s\u001f%s" % [
				String(left_place.get("name", "")),
				String(left_place.get("spaceId", "")),
				String(left_place.get("type", "")),
			]
			< "%s\u001f%s\u001f%s" % [
				String(right_place.get("name", "")),
				String(right_place.get("spaceId", "")),
				String(right_place.get("type", "")),
			]
		)
	)
	return result


static func validate_outdoor_perception(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.is_empty():
		errors.append("World 静态数据为空")
		return errors
	var grid_value: Variant = data.get("perceptionGrid")
	var regions_value: Variant = data.get("perceptionRegions")
	var places_value: Variant = data.get("places")
	if not grid_value is Dictionary:
		errors.append("perceptionGrid 必须为对象")
		return errors
	if not regions_value is Array:
		errors.append("perceptionRegions 必须为数组")
		return errors
	if not places_value is Array:
		errors.append("places 必须为数组")
		return errors

	var grid := grid_value as Dictionary
	var cell_size_value: Variant = grid.get("cellSize")
	var grid_width_value: Variant = grid.get("width")
	var grid_height_value: Variant = grid.get("height")
	var legal_cell_count_value: Variant = grid.get("legalCellCount")
	var cell_size_is_valid := _is_positive_integer(cell_size_value)
	var grid_width_is_valid := _is_positive_integer(grid_width_value)
	var grid_height_is_valid := _is_positive_integer(grid_height_value)
	var legal_cell_count_is_valid := _is_positive_integer(legal_cell_count_value)
	var cell_size := int(cell_size_value) if cell_size_is_valid else 0
	var grid_width := int(grid_width_value) if grid_width_is_valid else 0
	var grid_height := int(grid_height_value) if grid_height_is_valid else 0
	var legal_cell_count := int(legal_cell_count_value) if legal_cell_count_is_valid else 0
	if not cell_size_is_valid or not grid_width_is_valid or not grid_height_is_valid:
		errors.append("perceptionGrid 的 cellSize、width 和 height 必须为正整数")
	if not legal_cell_count_is_valid:
		errors.append("perceptionGrid.legalCellCount 必须为正整数")
	if not _is_nonnegative_integer(grid.get("excludedSampleCellCount")):
		errors.append("perceptionGrid.excludedSampleCellCount 必须为非负整数")
	if not _is_nonnegative_integer(grid.get("requiredPositionCellCount")):
		errors.append("perceptionGrid.requiredPositionCellCount 必须为非负整数")

	var places := places_value as Array
	var places_by_name := {}
	var expected_region_ids_by_place := {}
	var outdoor_place_names := {}
	for place_index in places.size():
		var place_value: Variant = places[place_index]
		if not place_value is Dictionary:
			errors.append("places[%d] 必须为对象" % place_index)
			continue
		var place := place_value as Dictionary
		var place_name := _string_value(place.get("name"), "places[%d].name" % place_index, errors)
		places_by_name[place_name] = place
		if _string_value(place.get("spaceId"), "places[%d].spaceId" % place_index, errors) == "town_outdoor":
			outdoor_place_names[place_name] = true
		expected_region_ids_by_place[place_name] = []

	var regions := regions_value as Array
	var region_ids := {}
	var cells_to_region := {}
	var actual_cell_count := 0
	for index in regions.size():
		var value: Variant = regions[index]
		if not value is Dictionary:
			errors.append("perceptionRegions[%d] 必须为对象" % index)
			continue
		var region := value as Dictionary
		var space_id := _string_value(
			region.get("spaceId"),
			"perceptionRegions[%d].spaceId" % index,
			errors,
		)
		if space_id != "town_outdoor":
			continue
		var region_id := _string_value(region.get("id"), "perceptionRegions[%d].id" % index, errors)
		_validate_unique_text(region_id, "感知区域 id", region_ids, errors)
		var place_name := _string_value(
			region.get("placeName"),
			"perceptionRegions[%d].placeName" % index,
			errors,
		)
		if not places_by_name.has(place_name):
			errors.append("感知区域 %s 引用了不存在的地点：%s" % [region_id, place_name])
		elif not outdoor_place_names.has(place_name):
			errors.append("室外感知区域 %s 必须属于室外地点：%s" % [region_id, place_name])
		else:
			var expected_ids := expected_region_ids_by_place.get(place_name, []) as Array
			expected_ids.append(region_id)
			expected_region_ids_by_place[place_name] = expected_ids
		var shape_value: Variant = region.get("shape")
		if not shape_value is Dictionary:
			errors.append("感知区域 %s 缺少 shape" % region_id)
			continue
		var shape := shape_value as Dictionary
		if not shape.get("type") is String or shape.get("type") != "grid_cells":
			errors.append("感知区域 %s 的 shape.type 必须为 grid_cells" % region_id)
		if not _is_exact_integer(shape.get("cellSize"), cell_size):
			errors.append("感知区域 %s 的 cellSize 与 perceptionGrid 不一致" % region_id)
		var origin_value: Variant = shape.get("origin")
		if not origin_value is Dictionary:
			errors.append("感知区域 %s 的 origin 必须为对象" % region_id)
		elif (
			not _is_exact_number((origin_value as Dictionary).get("x"), 0.0)
			or not _is_exact_number((origin_value as Dictionary).get("y"), 0.0)
		):
			errors.append("感知区域 %s 的网格原点必须为 (0, 0)" % region_id)
		var cells_value: Variant = shape.get("cells")
		if not cells_value is Array:
			errors.append("感知区域 %s 的 cells 必须为数组" % region_id)
			continue
		var cells := cells_value as Array
		if cells.size() < 3:
			errors.append("感知区域 %s 至少需要 3 个合法格" % region_id)
		var component_cells := {}
		for cell_index in cells.size():
			var cell_value: Variant = cells[cell_index]
			if not cell_value is Array or (cell_value as Array).size() != 2:
				errors.append("感知区域 %s 的 cells[%d] 必须为 [x, y]" % [region_id, cell_index])
				continue
			var pair := cell_value as Array
			if not _is_integer_number(pair[0]) or not _is_integer_number(pair[1]):
				errors.append("感知区域 %s 的 cells[%d] 必须使用整数格坐标" % [region_id, cell_index])
				continue
			var x := int(pair[0])
			var y := int(pair[1])
			if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
				errors.append("感知区域 %s 的格子越界：%d,%d" % [region_id, x, y])
				continue
			var key := _grid_cell_key(x, y)
			if component_cells.has(key):
				errors.append("感知区域 %s 内部格子重复：%s" % [region_id, key])
				continue
			component_cells[key] = Vector2i(x, y)
			if cells_to_region.has(key):
				errors.append(
					"合法位置格 %s 同时属于 %s 和 %s"
					% [key, cells_to_region[key], region_id]
				)
			else:
				cells_to_region[key] = region_id
				actual_cell_count += 1
		if not _is_eight_way_connected(component_cells):
			errors.append("感知区域 %s 的合法格不连续" % region_id)

	if actual_cell_count != legal_cell_count:
		errors.append(
			"perceptionGrid.legalCellCount 为 %d，实际唯一合法格为 %d"
			% [legal_cell_count, actual_cell_count]
		)
	for place_name_value in outdoor_place_names:
		var place_name := str(place_name_value)
		var place := places_by_name.get(place_name, {}) as Dictionary
		var actual_ids_value: Variant = place.get("perceptionRegionIds")
		if not actual_ids_value is Array:
			errors.append("室外地点 %s 的 perceptionRegionIds 必须为数组" % place_name)
			continue
		var actual_ids := (actual_ids_value as Array).duplicate()
		var expected_ids := (
			expected_region_ids_by_place.get(place_name, []) as Array
		).duplicate()
		actual_ids.sort()
		expected_ids.sort()
		if expected_ids.is_empty():
			errors.append("室外地点 %s 至少需要一个感知区域" % place_name)
		if actual_ids != expected_ids:
			errors.append("室外地点 %s 的感知区域引用与区域归属不一致" % place_name)
	return errors


static func validate_indoor_perception(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.is_empty():
		errors.append("World 静态数据为空")
		return errors
	var spaces_value: Variant = data.get("mapSpaces")
	var places_value: Variant = data.get("places")
	var regions_value: Variant = data.get("perceptionRegions")
	if not spaces_value is Array or not places_value is Array or not regions_value is Array:
		errors.append("室内感知校验需要 mapSpaces、places 和 perceptionRegions 数组")
		return errors

	var indoor_spaces := {}
	var spaces := spaces_value as Array
	for space_index in spaces.size():
		var space_value: Variant = spaces[space_index]
		if not space_value is Dictionary:
			errors.append("mapSpaces[%d] 必须为对象" % space_index)
			continue
		var space := space_value as Dictionary
		var space_type := _string_value(space.get("type"), "mapSpaces[%d].type" % space_index, errors)
		if space_type == "室内":
			var space_id := _string_value(space.get("id"), "mapSpaces[%d].id" % space_index, errors)
			indoor_spaces[space_id] = space

	var places_by_space := {}
	var places := places_value as Array
	for place_index in places.size():
		var place_value: Variant = places[place_index]
		if not place_value is Dictionary:
			errors.append("places[%d] 必须为对象" % place_index)
			continue
		var place := place_value as Dictionary
		var space_id := _string_value(place.get("spaceId"), "places[%d].spaceId" % place_index, errors)
		if indoor_spaces.has(space_id):
			places_by_space[space_id] = place

	var regions_by_space := {}
	var indoor_region_ids := {}
	var regions := regions_value as Array
	for region_index in regions.size():
		var region_value: Variant = regions[region_index]
		if not region_value is Dictionary:
			errors.append("perceptionRegions[%d] 必须为对象" % region_index)
			continue
		var region := region_value as Dictionary
		var space_id := _string_value(
			region.get("spaceId"),
			"perceptionRegions[%d].spaceId" % region_index,
			errors,
		)
		if space_id == "town_outdoor":
			continue
		var region_id := _string_value(region.get("id"), "perceptionRegions[%d].id" % region_index, errors)
		_validate_unique_text(region_id, "室内感知区域 id", indoor_region_ids, errors)
		if not indoor_spaces.has(space_id):
			errors.append("室内感知区域 %s 引用了不存在的室内空间：%s" % [region_id, space_id])
			continue
		if regions_by_space.has(space_id):
			errors.append("室内空间 %s 只能有一个完整感知区域" % space_id)
			continue
		regions_by_space[space_id] = region
		var place := places_by_space.get(space_id, {}) as Dictionary
		var region_place_name := _string_value(
			region.get("placeName"),
			"perceptionRegions[%d].placeName" % region_index,
			errors,
		)
		if place.is_empty() or region_place_name != place.get("name"):
			errors.append("室内感知区域 %s 的地点与空间台账不一致" % region_id)
		var shape_value: Variant = region.get("shape")
		if not shape_value is Dictionary:
			errors.append("室内感知区域 %s 缺少 shape" % region_id)
			continue
		var shape := shape_value as Dictionary
		if not shape.get("type") is String or shape.get("type") != "rect":
			errors.append("室内感知区域 %s 的 shape.type 必须为 rect" % region_id)
			continue
		var bounds_value: Variant = (indoor_spaces[space_id] as Dictionary).get("bounds")
		if not bounds_value is Dictionary:
			errors.append("室内空间 %s 的 bounds 必须为对象" % space_id)
			continue
		var bounds := bounds_value as Dictionary
		for component in ["x", "y", "width", "height"]:
			if (
					not _is_number(bounds.get(component))
					or not _is_exact_number(
						shape.get(component),
						float(bounds.get(component, NAN)),
					)
			):
				errors.append("室内感知区域 %s 的 %s 必须覆盖完整空间边界" % [region_id, component])

	for space_id_value: Variant in indoor_spaces:
		var space_id := str(space_id_value)
		if not regions_by_space.has(space_id):
			errors.append("室内空间 %s 缺少完整感知区域" % space_id)
			continue
		var place := places_by_space.get(space_id, {}) as Dictionary
		var region := regions_by_space[space_id] as Dictionary
		var actual_ids_value: Variant = place.get("perceptionRegionIds")
		if not actual_ids_value is Array:
			errors.append("室内地点 %s 的 perceptionRegionIds 必须为数组" % place.get("name", ""))
			continue
		var actual_ids := (actual_ids_value as Array).duplicate()
		var expected_ids := [str(region.get("id", ""))]
		actual_ids.sort()
		expected_ids.sort()
		if actual_ids != expected_ids:
			errors.append("室内地点 %s 的感知区域引用与完整区域不一致" % str(place.get("name", "")))
	return errors


static func _validate_settings(data: Dictionary, errors: PackedStringArray) -> void:
	if not _is_exact_integer(data.get("schemaVersion"), 1):
		errors.append("schemaVersion 必须为 1")
	if not _is_positive_integer(data.get("dataVersion")):
		errors.append("dataVersion 必须大于 0")
	if not data.get("worldId") is String or data.get("worldId") != "town":
		errors.append("worldId 必须为 town")
	var content_status_value: Variant = data.get("contentStatus")
	if not content_status_value is Dictionary:
		errors.append("contentStatus 必须为对象")
	else:
		var content_status := content_status_value as Dictionary
		if not content_status.get("stage") is String or content_status.get("stage") not in ["foundation", "outdoor_ready", "world_ready"]:
			errors.append("contentStatus.stage 必须为 foundation、outdoor_ready 或 world_ready")
		var pending_sections_value: Variant = content_status.get("pendingSections")
		var pending_sections_are_valid := pending_sections_value is Array
		if not pending_sections_are_valid:
			errors.append("contentStatus.pendingSections 必须为数组")
		else:
			_validate_string_array(
				pending_sections_value as Array,
				"contentStatus.pendingSections",
				errors,
			)
		var world_ready_value: Variant = content_status.get("worldReady")
		if not world_ready_value is bool:
			errors.append("contentStatus.worldReady 必须为布尔值")
		elif pending_sections_are_valid and (
			(pending_sections_value as Array).is_empty() != (world_ready_value == true)
		):
			errors.append("contentStatus.worldReady 必须且只能在 pendingSections 为空时为 true")
	var distance_value: Variant = data.get("distance")
	if not distance_value is Dictionary:
		errors.append("distance 必须为对象")
	else:
		var distance := distance_value as Dictionary
		if not distance.get("unit") is String or distance.get("unit") != "pixel":
			errors.append("distance.unit 必须为 pixel")
		if not _is_exact_number(distance.get("pixelsPerUnit"), 1.0):
			errors.append("distance.pixelsPerUnit 必须为 1")
	if not _is_positive_number(data.get("perceptionRange")):
		errors.append("perceptionRange 必须大于 0")
	var movement_value: Variant = data.get("movementRules")
	if not movement_value is Dictionary:
		errors.append("movementRules 必须为对象")
		return
	var movement := movement_value as Dictionary
	if not _is_positive_number(movement.get("outdoorDistancePerGameMinute")):
		errors.append("movementRules.outdoorDistancePerGameMinute 必须大于 0")
	if not _is_positive_integer(movement.get("connectionMinutes")):
		errors.append("movementRules.connectionMinutes 必须为正整数")
	if not movement.get("durationRounding") is String or movement.get("durationRounding") != "ceil":
		errors.append("movementRules.durationRounding 必须为 ceil")
	if not movement.get("edgeCost") is String or movement.get("edgeCost") != "polyline_length":
		errors.append("movementRules.edgeCost 必须为 polyline_length")
	var tie_break_value: Variant = movement.get("routeTieBreak")
	if not tie_break_value is Array:
		errors.append("movementRules.routeTieBreak 必须为数组")
	else:
		_validate_string_array(tie_break_value as Array, "movementRules.routeTieBreak", errors)


static func _validate_place_observation_hotspots(
	data: Dictionary,
	errors: PackedStringArray,
) -> void:
	var connections_value: Variant = data.get("connections")
	var hotspots_value: Variant = data.get("placeObservationHotspots")
	if not connections_value is Array:
		errors.append("建筑观察命中区校验需要 connections 数组")
		return
	if not hotspots_value is Dictionary:
		errors.append("placeObservationHotspots 必须为对象")
		return
	var expected_connection_ids := {}
	for value: Variant in connections_value as Array:
		if not value is Dictionary:
			continue
		var connection := value as Dictionary
		var connection_id := String(connection.get("id", "")).strip_edges()
		var left := connection.get("from", {}) as Dictionary
		var right := connection.get("to", {}) as Dictionary
		if (
			connection_id.is_empty()
			or (
				String(left.get("spaceId", "")) != "town_outdoor"
				and String(right.get("spaceId", "")) != "town_outdoor"
			)
		):
			continue
		expected_connection_ids[connection_id] = true
	var hotspots := hotspots_value as Dictionary
	for connection_id_value: Variant in expected_connection_ids:
		var connection_id := String(connection_id_value)
		if not hotspots.has(connection_id):
			errors.append("室外建筑连接 %s 缺少观察命中区" % connection_id)
	for connection_id_value: Variant in hotspots:
		var connection_id := String(connection_id_value)
		if not expected_connection_ids.has(connection_id):
			errors.append("建筑观察命中区引用了未知室外连接：%s" % connection_id)
			continue
		var spec_value: Variant = hotspots[connection_id_value]
		if not spec_value is Dictionary:
			errors.append("建筑观察命中区 %s 必须为对象" % connection_id)
			continue
		var spec := spec_value as Dictionary
		var offset_value: Variant = spec.get("offset")
		var size_value: Variant = spec.get("size")
		if not offset_value is Dictionary or not size_value is Dictionary:
			errors.append("建筑观察命中区 %s 必须包含 offset 与 size" % connection_id)
			continue
		var offset := offset_value as Dictionary
		var size := size_value as Dictionary
		for component in ["x", "y"]:
			if (
				not _is_number(offset.get(component))
				or not is_finite(float(offset.get(component, NAN)))
			):
				errors.append(
					"建筑观察命中区 %s 的 offset.%s 必须为有限数字"
					% [connection_id, component]
				)
		for component in ["width", "height"]:
			if (
				not _is_number(size.get(component))
				or not is_finite(float(size.get(component, NAN)))
				or float(size.get(component, 0.0)) <= 0.0
			):
				errors.append(
					"建筑观察命中区 %s 的 size.%s 必须为正有限数字"
					% [connection_id, component]
				)
static func _validate_coordinate_system(
	space_id: String,
	value: Variant,
	errors: PackedStringArray
) -> void:
	if not value is Dictionary:
		errors.append("地图空间 %s 缺少 coordinateSystem" % space_id)
		return
	var coordinate_system := value as Dictionary
	var origin_value: Variant = coordinate_system.get("origin")
	if not origin_value is String or (origin_value as String).strip_edges().is_empty():
		errors.append("地图空间 %s 的坐标原点说明必须为非空字符串" % space_id)
	if not coordinate_system.get("xAxis") is String or coordinate_system.get("xAxis") != "right":
		errors.append("地图空间 %s 的 xAxis 必须为 right" % space_id)
	if not coordinate_system.get("yAxis") is String or coordinate_system.get("yAxis") != "down":
		errors.append("地图空间 %s 的 yAxis 必须为 down" % space_id)
	if not coordinate_system.get("unit") is String or coordinate_system.get("unit") != "pixel":
		errors.append("地图空间 %s 的 unit 必须为 pixel" % space_id)
	if not _is_exact_number(coordinate_system.get("pixelsPerUnit"), 1.0):
		errors.append("地图空间 %s 的 pixelsPerUnit 必须为 1" % space_id)


static func _validate_bounds(space_id: String, value: Variant, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		errors.append("地图空间 %s 缺少 bounds" % space_id)
		return
	var bounds := value as Dictionary
	for key in ["x", "y", "width", "height"]:
		if not _is_number(bounds.get(key)):
			errors.append("地图空间 %s 的 bounds.%s 必须为数字" % [space_id, key])
	if not _is_positive_number(bounds.get("width")) or not _is_positive_number(bounds.get("height")):
		errors.append("地图空间 %s 的边界宽高必须大于 0" % space_id)


static func _string_value(
	value: Variant,
	path: String,
	errors: PackedStringArray,
) -> String:
	if not value is String:
		errors.append("%s 必须为字符串" % path)
		return ""
	return value as String


static func _validate_unique_text(
	text: String,
	label: String,
	seen: Dictionary,
	errors: PackedStringArray
) -> void:
	if text.strip_edges().is_empty():
		errors.append("%s 不能为空" % label)
		return
	if seen.has(text):
		errors.append("%s 重复：%s" % [label, text])
		return
	seen[text] = true


static func _validate_string_array(
	values: Array,
	path: String,
	errors: PackedStringArray
) -> void:
	var seen := {}
	for index in values.size():
		var value: Variant = values[index]
		if not value is String:
			errors.append("%s[%d] 必须为字符串" % [path, index])
			continue
		var text := value as String
		if text.strip_edges().is_empty():
			errors.append("%s[%d] 不能为空" % [path, index])
		elif seen.has(text):
			errors.append("%s 包含重复值：%s" % [path, text])
		else:
			seen[text] = true


static func _validate_capabilities(
	place_name: String,
	capabilities: Dictionary,
	errors: PackedStringArray,
) -> void:
	WORLD_SCALARS.validate_capabilities(place_name, capabilities, errors)


static func _validate_forbidden_keys(
	value: Variant,
	path: String,
	errors: PackedStringArray
) -> void:
	if value is Dictionary:
		var dictionary := value as Dictionary
		for key_value in dictionary:
			var key := str(key_value)
			if key in FORBIDDEN_RUNTIME_KEYS:
				errors.append("World 静态数据不得包含表现层或运行状态字段：%s.%s" % [path, key])
			_validate_forbidden_keys(dictionary[key_value], "%s.%s" % [path, key], errors)
	elif value is Array:
		var array := value as Array
		for index in array.size():
			_validate_forbidden_keys(array[index], "%s[%d]" % [path, index], errors)


static func _load_source_document(
	source_dir: String,
	file_name: String,
) -> Dictionary:
	var path := source_dir.path_join(file_name)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	return parsed as Dictionary if parsed is Dictionary else {}


static func _validate_compiled_section(
	actual_value: Variant,
	source_value: Variant,
	id_field: String,
	label: String,
	errors: PackedStringArray,
) -> void:
	if not actual_value is Array or not source_value is Array:
		errors.append("%s 必须由对应权威源完整编译" % label)
		return
	var expected := (source_value as Array).duplicate(true)
	expected.sort_custom(func(left: Variant, right: Variant) -> bool:
		return String((left as Dictionary).get(id_field, "")) < String(
			(right as Dictionary).get(id_field, "")
		)
	)
	if actual_value != expected:
		errors.append("%s 与收据绑定的权威源内容不一致" % label)


static func _contains_cjk(text: String) -> bool:
	return WORLD_SCALARS.contains_cjk(text)


static func _is_number(value: Variant) -> bool:
	return WORLD_SCALARS.is_number(value)


static func _is_integer_number(value: Variant) -> bool:
	if not _is_number(value):
		return false
	return float(value) == roundf(float(value))


static func _is_exact_number(value: Variant, expected: float) -> bool:
	return _is_number(value) and is_finite(expected) and float(value) == expected


static func _is_exact_integer(value: Variant, expected: int) -> bool:
	return _is_integer_number(value) and float(value) == float(expected)


static func _is_positive_number(value: Variant) -> bool:
	return _is_number(value) and float(value) > 0.0


static func _is_positive_integer(value: Variant) -> bool:
	return _is_integer_number(value) and float(value) > 0.0


static func _is_nonnegative_integer(value: Variant) -> bool:
	return _is_integer_number(value) and float(value) >= 0.0


static func _grid_cell_key(x: int, y: int) -> String:
	return "%d:%d" % [x, y]


static func _is_eight_way_connected(cells: Dictionary) -> bool:
	if cells.is_empty():
		return false
	var remaining := cells.duplicate()
	var first_key: Variant = remaining.keys()[0]
	var queue: Array[Vector2i] = [remaining[first_key] as Vector2i]
	remaining.erase(first_key)
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset: Vector2i in [
			Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
		]:
			var neighbor := current + offset
			var key := _grid_cell_key(neighbor.x, neighbor.y)
			if remaining.has(key):
				queue.append(remaining[key] as Vector2i)
				remaining.erase(key)
	return remaining.is_empty()
