extends RefCounted


const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const ACTIVITY_CAPABILITY_CONTRACT := preload(
	"res://world/data/town/TownPlaceActivityCapabilityContract.gd"
)
const VALID_SPACE_TYPES := ["室外", "室内"]
const VALID_PLACE_TYPES := ["公共地点", "住家", "铺面"]
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
const RETIRED_IDENTIFIERS := ["indoor_riverside_inn", "河畔旅店"]


static func validate_source_directory(source_dir: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var places_document: Variant = _load_document(
		source_dir.path_join("places.json"),
		"places.json",
		errors,
	)
	var spaces_document: Variant = _load_document(
		source_dir.path_join("spaces.json"),
		"spaces.json",
		errors,
	)
	if not errors.is_empty():
		return errors
	errors.append_array(validate_documents(places_document, spaces_document))
	return errors


static func validate_documents(
	places_document: Variant,
	spaces_document: Variant,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if not places_document is Dictionary:
		errors.append("places.json 必须为 JSON 对象")
	if not spaces_document is Dictionary:
		errors.append("spaces.json 必须为 JSON 对象")
	if not errors.is_empty():
		return errors

	var places_source := places_document as Dictionary
	var spaces_source := spaces_document as Dictionary
	_validate_envelope(places_source, "places.json", errors)
	_validate_envelope(spaces_source, "spaces.json", errors)

	var places_value: Variant = places_source.get("places")
	var spaces_value: Variant = spaces_source.get("spaces")
	if not places_value is Array:
		errors.append("places.json.places 必须为数组")
	if not spaces_value is Array:
		errors.append("spaces.json.spaces 必须为数组")
	if not errors.is_empty():
		return errors

	_validate_catalog(places_value as Array, spaces_value as Array, errors)
	return errors


static func load_source_documents(source_dir: String) -> Dictionary:
	var places_document := _load_json_object(source_dir.path_join("places.json"))
	var spaces_document := _load_json_object(source_dir.path_join("spaces.json"))
	if places_document.is_empty() or spaces_document.is_empty():
		return {}
	return {
		"places": places_document,
		"spaces": spaces_document,
	}


static func _validate_catalog(
	places: Array,
	spaces: Array,
	errors: PackedStringArray,
) -> void:
	var spaces_by_id := {}
	var seen_space_ids := {}
	var space_names := {}
	var indoor_space_ids := {}
	var outdoor_space_ids := {}
	for index in spaces.size():
		var value: Variant = spaces[index]
		if not value is Dictionary:
			errors.append("spaces[%d] 必须为对象" % index)
			continue
		var space := value as Dictionary
		var space_id := str(space.get("id", ""))
		var space_name := str(space.get("name", ""))
		_validate_unique_text(space_id, "地图空间 id", seen_space_ids, errors)
		if not space_id.is_empty() and not spaces_by_id.has(space_id):
			spaces_by_id[space_id] = space
		_validate_unique_text(space_name, "地图空间名字", space_names, errors)
		var space_type := str(space.get("type", ""))
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
	_validate_outdoor_bounds(spaces_by_id.get("town_outdoor"), errors)

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
		var place_name := str(place.get("name", ""))
		_validate_unique_text(place_name, "地点中文名", place_names, errors)
		if not _contains_cjk(place_name):
			errors.append("地点名字必须包含中文：%s" % place_name)
		if place.has("id"):
			errors.append("地点 %s 不应另设 id；中文 name 就是地点身份" % place_name)
		var place_type := str(place.get("type", ""))
		if place_type not in VALID_PLACE_TYPES:
			errors.append("地点 %s 的 type 无效：%s" % [place_name, place_type])
		var space_id := str(place.get("spaceId", ""))
		if not spaces_by_id.has(space_id):
			errors.append("地点 %s 引用了不存在的地图空间：%s" % [place_name, space_id])
		else:
			place_count_by_space[space_id] = int(place_count_by_space.get(space_id, 0)) + 1
			if outdoor_space_ids.has(space_id):
				outdoor_place_count += 1
		if str(place.get("summary", "")).strip_edges().is_empty():
			errors.append("地点 %s 缺少地点说明" % place_name)
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
			_validate_string_array(
				region_ids_value as Array,
				"%s.perceptionRegionIds" % place_name,
				errors,
			)

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

	_validate_dining_hall(places, spaces_by_id, errors)
	_validate_retired_identifiers(places, spaces, errors)
	_validate_forbidden_keys(
		{"mapSpaces": spaces, "places": places},
		"worldCatalog",
		errors,
	)


static func _validate_dining_hall(
	places: Array,
	spaces_by_id: Dictionary,
	errors: PackedStringArray,
) -> void:
	var dining_places: Array[Dictionary] = []
	for place_value in places:
		if place_value is Dictionary and str((place_value as Dictionary).get("name", "")) == "公共食堂":
			dining_places.append(place_value as Dictionary)
	if dining_places.size() != 1:
		errors.append("公共食堂必须且只能定义一次")
		return
	if str(dining_places[0].get("spaceId", "")) != "indoor_dining_hall":
		errors.append("公共食堂必须引用 indoor_dining_hall")
	var dining_space_value: Variant = spaces_by_id.get("indoor_dining_hall")
	if not dining_space_value is Dictionary:
		errors.append("缺少公共食堂室内空间 indoor_dining_hall")
	elif str((dining_space_value as Dictionary).get("type", "")) != "室内":
		errors.append("indoor_dining_hall 必须为室内空间")


static func _validate_retired_identifiers(
	places: Array,
	spaces: Array,
	errors: PackedStringArray,
) -> void:
	var serialized := JSON.stringify({"places": places, "spaces": spaces})
	for retired_identifier in RETIRED_IDENTIFIERS:
		if serialized.contains(retired_identifier):
			errors.append("地点与空间台账不得包含已退场标识：%s" % retired_identifier)


static func _validate_envelope(
	document: Dictionary,
	file_name: String,
	errors: PackedStringArray,
) -> void:
	if not _is_exact_integer(document.get("schemaVersion"), 1):
		errors.append("%s.schemaVersion 必须为 1" % file_name)
	if not document.get("worldId") is String or document.get("worldId") != "town":
		errors.append("%s.worldId 必须为 town" % file_name)


static func _validate_outdoor_bounds(value: Variant, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		return
	var bounds_value: Variant = (value as Dictionary).get("bounds")
	if not bounds_value is Dictionary:
		return
	var bounds := bounds_value as Dictionary
	if (
		float(bounds.get("x", -1.0)) != 0.0
		or float(bounds.get("y", -1.0)) != 0.0
		or float(bounds.get("width", 0.0)) != 6688.0
		or float(bounds.get("height", 0.0)) != 3764.0
	):
		errors.append("town_outdoor.bounds 必须精确覆盖 6688×3764 正式地图")


static func _validate_coordinate_system(
	space_id: String,
	value: Variant,
	errors: PackedStringArray,
) -> void:
	if not value is Dictionary:
		errors.append("地图空间 %s 缺少 coordinateSystem" % space_id)
		return
	var coordinate_system := value as Dictionary
	if str(coordinate_system.get("origin", "")).is_empty():
		errors.append("地图空间 %s 缺少坐标原点说明" % space_id)
	if str(coordinate_system.get("xAxis", "")) != "right":
		errors.append("地图空间 %s 的 xAxis 必须为 right" % space_id)
	if str(coordinate_system.get("yAxis", "")) != "down":
		errors.append("地图空间 %s 的 yAxis 必须为 down" % space_id)
	if str(coordinate_system.get("unit", "")) != "pixel":
		errors.append("地图空间 %s 的 unit 必须为 pixel" % space_id)
	if float(coordinate_system.get("pixelsPerUnit", 0.0)) != 1.0:
		errors.append("地图空间 %s 的 pixelsPerUnit 必须为 1" % space_id)


static func _validate_bounds(
	space_id: String,
	value: Variant,
	errors: PackedStringArray,
) -> void:
	if not value is Dictionary:
		errors.append("地图空间 %s 缺少 bounds" % space_id)
		return
	var bounds := value as Dictionary
	for key in ["x", "y", "width", "height"]:
		if not _is_number(bounds.get(key)):
			errors.append("地图空间 %s 的 bounds.%s 必须为数字" % [space_id, key])
	if float(bounds.get("width", 0.0)) <= 0.0 or float(bounds.get("height", 0.0)) <= 0.0:
		errors.append("地图空间 %s 的边界宽高必须大于 0" % space_id)


static func _validate_unique_text(
	text: String,
	label: String,
	seen: Dictionary,
	errors: PackedStringArray,
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
	errors: PackedStringArray,
) -> void:
	var seen := {}
	for index in values.size():
		var text := str(values[index])
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
	errors: PackedStringArray,
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


static func _load_document(
	path: String,
	file_name: String,
	errors: PackedStringArray,
) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("缺少源数据文件：%s" % file_name)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("源数据文件不是合法 JSON 对象：%s" % file_name)
		return null
	return parsed


static func _load_json_object(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func _contains_cjk(text: String) -> bool:
	return WORLD_SCALARS.contains_cjk(text)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_exact_integer(value: Variant, expected: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == float(expected)
