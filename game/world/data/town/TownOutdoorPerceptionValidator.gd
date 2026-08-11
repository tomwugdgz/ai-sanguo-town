extends RefCounted


const OUTDOOR_SPACE_ID := "town_outdoor"
const MAP_WIDTH := 6688
const MAP_HEIGHT := 3764
const MIN_REGION_CELL_COUNT := 3


static func validate_document(
	document: Variant,
	navigation: Variant,
	masks_document: Variant,
	places_document: Variant,
	outdoor_navigation_grid: Variant = {},
) -> PackedStringArray:
	var errors := PackedStringArray()
	if not document is Dictionary:
		errors.append("室外感知数据必须为 JSON 对象")
	if not navigation is Dictionary:
		errors.append("室外导航参考必须为 JSON 对象")
	if not masks_document is Dictionary:
		errors.append("室外地点蒙版必须为 JSON 对象")
	if not places_document is Dictionary:
		errors.append("地点台账必须为 JSON 对象")
	if not errors.is_empty():
		return errors

	var data := document as Dictionary
	var nav := navigation as Dictionary
	var masks_source := masks_document as Dictionary
	var places_source := places_document as Dictionary
	_validate_envelope(data, "室外感知数据", errors)
	_validate_envelope(masks_source, "室外地点蒙版", errors)
	_validate_envelope(places_source, "地点台账", errors)

	var outdoor_places := _outdoor_place_names(places_source, errors)
	var masks := _validated_masks(masks_source, outdoor_places, errors)
	var default_place_name := str(masks_source.get("defaultPlaceName", ""))
	if not outdoor_places.has(default_place_name):
		errors.append("默认室外地点不存在于地点台账：%s" % default_place_name)

	var expected_result := _expected_cells(
		nav,
		masks_source,
		masks,
		default_place_name,
		errors,
		outdoor_navigation_grid,
	)
	var expected_cells := expected_result.get("cells", {}) as Dictionary
	var expected_required_count := int(expected_result.get("requiredPositionCellCount", 0))
	_validate_regions(
		data,
		nav,
		masks_source,
		outdoor_places,
		expected_cells,
		expected_required_count,
		errors,
	)
	return errors


static func _validate_envelope(
	document: Dictionary,
	label: String,
	errors: PackedStringArray,
) -> void:
	if int(document.get("schemaVersion", 0)) != 1:
		errors.append("%s.schemaVersion 必须为 1" % label)
	if str(document.get("worldId", "")) != "town":
		errors.append("%s.worldId 必须为 town" % label)


static func _outdoor_place_names(
	places_document: Dictionary,
	errors: PackedStringArray,
) -> PackedStringArray:
	var result := PackedStringArray()
	var places_value: Variant = places_document.get("places")
	if not places_value is Array:
		errors.append("地点台账 places 必须为数组")
		return result
	for index in (places_value as Array).size():
		var value: Variant = (places_value as Array)[index]
		if not value is Dictionary:
			errors.append("地点台账 places[%d] 必须为对象" % index)
			continue
		var place := value as Dictionary
		if str(place.get("spaceId", "")) != OUTDOOR_SPACE_ID:
			continue
		var place_name := str(place.get("name", ""))
		if place_name.is_empty():
			errors.append("室外地点名字不能为空")
		elif result.has(place_name):
			errors.append("室外地点名字重复：%s" % place_name)
		else:
			result.append(place_name)
	result.sort()
	if result.size() != 7:
		errors.append("正式室外地点必须为 7 个，实际为 %d" % result.size())
	return result


static func _validated_masks(
	masks_document: Dictionary,
	outdoor_places: PackedStringArray,
	errors: PackedStringArray,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var masks_value: Variant = masks_document.get("masks")
	if not masks_value is Array:
		errors.append("室外地点蒙版 masks 必须为数组")
		return result
	for index in (masks_value as Array).size():
		var value: Variant = (masks_value as Array)[index]
		if not value is Dictionary:
			errors.append("室外地点蒙版 masks[%d] 必须为对象" % index)
			continue
		var mask := value as Dictionary
		var place_name := str(mask.get("placeName", ""))
		if not outdoor_places.has(place_name):
			errors.append("室外地点蒙版引用了不存在的地点：%s" % place_name)
		var polygon := _packed_pair_polygon(mask.get("polygon", []) as Array)
		if polygon.size() < 3:
			errors.append("室外地点蒙版 %s 至少需要 3 个点" % place_name)
			continue
		result.append({"placeName": place_name, "polygon": polygon})
	return result


static func _expected_cells(
	navigation: Dictionary,
	masks_document: Dictionary,
	masks: Array[Dictionary],
	default_place_name: String,
	errors: PackedStringArray,
	outdoor_navigation_grid: Variant = {},
) -> Dictionary:
	var cell_size := int(navigation.get("cellSize", 0))
	var grid_width := int(navigation.get("width", 0))
	var grid_height := int(navigation.get("height", 0))
	if cell_size <= 0 or grid_width <= 0 or grid_height <= 0:
		errors.append("室外导航参考的网格尺寸无效")
		return {}

	var polygons: Array[PackedVector2Array] = []
	var regions_value: Variant = navigation.get("regions")
	if not regions_value is Array:
		errors.append("室外导航参考 regions 必须为数组")
		return {}
	for value in regions_value as Array:
		if not value is Dictionary:
			continue
		var region := value as Dictionary
		if not bool(region.get("enabled", true)) or str(region.get("type", "")) != "walkable":
			continue
		var shape_value: Variant = region.get("shape")
		if not shape_value is Dictionary:
			continue
		var polygon := _packed_dictionary_polygon((shape_value as Dictionary).get("points", []) as Array)
		if polygon.size() >= 3:
			polygons.append(polygon)
	if polygons.is_empty():
		errors.append("室外导航参考没有合法 walkable 区域")
		return {}

	var expected_cells := {}
	for y in grid_height:
		for x in grid_width:
			var center := Vector2(
				float(x * cell_size) + float(cell_size) * 0.5,
				float(y * cell_size) + float(cell_size) * 0.5,
			)
			if center.x >= MAP_WIDTH or center.y >= MAP_HEIGHT:
				continue
			if not _inside_any(center, polygons):
				continue
			expected_cells[_cell_key(Vector2i(x, y))] = _place_for_point(
				center,
				masks,
				default_place_name,
			)
	if outdoor_navigation_grid is Dictionary:
		_append_outdoor_navigation_cells(
			expected_cells,
			outdoor_navigation_grid as Dictionary,
			masks,
			default_place_name,
			cell_size,
			grid_width,
			grid_height,
		)

	var required_position_cell_count := 0
	var required_values: Variant = masks_document.get("requiredPositions", [])
	if not required_values is Array:
		errors.append("室外地点蒙版 requiredPositions 必须为数组")
		return {}
	for index in (required_values as Array).size():
		var value: Variant = (required_values as Array)[index]
		if not value is Dictionary:
			errors.append("requiredPositions[%d] 必须为对象" % index)
			continue
		var required_position := value as Dictionary
		var place_name := str(required_position.get("placeName", ""))
		var pair_value: Variant = required_position.get("position")
		if not pair_value is Array or (pair_value as Array).size() < 2:
			errors.append("requiredPositions[%d].position 必须为二维坐标" % index)
			continue
		var pair := pair_value as Array
		var cell := Vector2i(
			floori(float(pair[0]) / float(cell_size)),
			floori(float(pair[1]) / float(cell_size)),
		)
		if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
			errors.append("requiredPositions[%d] 超出导航网格" % index)
			continue
		var key := _cell_key(cell)
		if not expected_cells.has(key):
			required_position_cell_count += 1
		expected_cells[key] = place_name
	return {
		"cells": expected_cells,
		"requiredPositionCellCount": required_position_cell_count,
	}


static func _append_outdoor_navigation_cells(
	expected_cells: Dictionary,
	outdoor_navigation_grid: Dictionary,
	masks: Array[Dictionary],
	default_place_name: String,
	cell_size: int,
	grid_width: int,
	grid_height: int,
) -> void:
	var navigation_cell_size := int(outdoor_navigation_grid.get("cellSize", 0))
	if navigation_cell_size <= 0:
		return
	for value: Variant in outdoor_navigation_grid.get("cells", []) as Array:
		if value is not Array or (value as Array).size() < 2:
			continue
		var source := value as Array
		var body_origin := Vector2(
			(float(source[0]) + 0.5) * float(navigation_cell_size),
			(float(source[1]) + 0.5) * float(navigation_cell_size),
		)
		var cell := Vector2i(
			floori(body_origin.x / float(cell_size)),
			floori(body_origin.y / float(cell_size)),
		)
		if (
			cell.x < 0
			or cell.x >= grid_width
			or cell.y < 0
			or cell.y >= grid_height
		):
			continue
		var key := _cell_key(cell)
		if expected_cells.has(key):
			continue
		var center := (Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size)
		expected_cells[key] = _place_for_point(
			center,
			masks,
			default_place_name,
		)


static func _validate_regions(
	document: Dictionary,
	navigation: Dictionary,
	masks_document: Dictionary,
	outdoor_places: PackedStringArray,
	expected_cells: Dictionary,
	expected_required_count: int,
	errors: PackedStringArray,
) -> void:
	var grid_value: Variant = document.get("grid")
	var regions_value: Variant = document.get("regions")
	if not grid_value is Dictionary:
		errors.append("室外感知数据 grid 必须为对象")
		return
	if not regions_value is Array:
		errors.append("室外感知数据 regions 必须为数组")
		return
	var grid := grid_value as Dictionary
	var regions := regions_value as Array
	var cell_size := int(navigation.get("cellSize", 0))
	var grid_width := int(navigation.get("width", 0))
	var grid_height := int(navigation.get("height", 0))
	if int(grid.get("cellSize", 0)) != cell_size:
		errors.append("感知网格 cellSize 与导航参考不一致")
	if int(grid.get("width", 0)) != grid_width or int(grid.get("height", 0)) != grid_height:
		errors.append("感知网格尺寸与导航参考不一致")
	var origin := grid.get("origin", {}) as Dictionary
	if int(origin.get("x", -1)) != 0 or int(origin.get("y", -1)) != 0:
		errors.append("感知网格 origin 必须为 (0, 0)")
	if int(grid.get("requiredPositionCellCount", -1)) != expected_required_count:
		errors.append("requiredPositionCellCount 与制作源不一致")
	if regions.size() != 8:
		errors.append("正式室外感知区域必须为 8 个，实际为 %d" % regions.size())

	var region_ids := {}
	var places_with_regions := {}
	var actual_cells := {}
	var previous_region_id := ""
	for region_index in regions.size():
		var region_value: Variant = regions[region_index]
		if not region_value is Dictionary:
			errors.append("regions[%d] 必须为对象" % region_index)
			continue
		var region := region_value as Dictionary
		var region_id := str(region.get("id", ""))
		if region_id.is_empty():
			errors.append("感知区域 id 不能为空")
		elif region_ids.has(region_id):
			errors.append("感知区域 id 重复：%s" % region_id)
		else:
			region_ids[region_id] = true
		if not previous_region_id.is_empty() and region_id < previous_region_id:
			errors.append("感知区域必须按稳定 id 排序")
		previous_region_id = region_id
		var place_name := str(region.get("placeName", ""))
		if not outdoor_places.has(place_name):
			errors.append("感知区域 %s 引用了不存在的室外地点：%s" % [region_id, place_name])
		else:
			places_with_regions[place_name] = true
		if str(region.get("spaceId", "")) != OUTDOOR_SPACE_ID:
			errors.append("感知区域 %s 必须属于 town_outdoor" % region_id)
		var shape_value: Variant = region.get("shape")
		if not shape_value is Dictionary:
			errors.append("感知区域 %s 缺少 shape" % region_id)
			continue
		var shape := shape_value as Dictionary
		if str(shape.get("type", "")) != "grid_cells":
			errors.append("感知区域 %s 的 shape.type 必须为 grid_cells" % region_id)
		if int(shape.get("cellSize", 0)) != cell_size:
			errors.append("感知区域 %s 的 cellSize 与导航参考不一致" % region_id)
		var shape_origin := shape.get("origin", {}) as Dictionary
		if int(shape_origin.get("x", -1)) != 0 or int(shape_origin.get("y", -1)) != 0:
			errors.append("感知区域 %s 的 origin 必须为 (0, 0)" % region_id)
		var cells_value: Variant = shape.get("cells")
		if not cells_value is Array:
			errors.append("感知区域 %s 的 cells 必须为数组" % region_id)
			continue
		var cells := cells_value as Array
		if cells.size() < MIN_REGION_CELL_COUNT:
			errors.append("感知区域 %s 少于 %d 个合法格" % [region_id, MIN_REGION_CELL_COUNT])
		var previous_cell_key := ""
		for cell_index in cells.size():
			var pair_value: Variant = cells[cell_index]
			if not pair_value is Array or (pair_value as Array).size() < 2:
				errors.append("感知区域 %s 的 cells[%d] 不是二维格坐标" % [region_id, cell_index])
				continue
			var pair := pair_value as Array
			var x := int(pair[0])
			var y := int(pair[1])
			if float(pair[0]) != float(x) or float(pair[1]) != float(y):
				errors.append("感知区域 %s 的 cells[%d] 必须为整数格坐标" % [region_id, cell_index])
				continue
			if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
				errors.append("感知区域 %s 的格坐标越界：[%d, %d]" % [region_id, x, y])
				continue
			var key := _cell_key(Vector2i(x, y))
			if not previous_cell_key.is_empty() and key < previous_cell_key:
				errors.append("感知区域 %s 的格坐标必须稳定排序" % region_id)
			previous_cell_key = key
			if actual_cells.has(key):
				errors.append("合法位置格重复归属：%s" % key)
				continue
			actual_cells[key] = place_name
			if not expected_cells.has(key):
				errors.append("感知区域包含导航与制作源之外的位置格：%s" % key)
			elif str(expected_cells.get(key, "")) != place_name:
				errors.append(
					"位置格 %s 应属于 %s，实际属于 %s"
					% [key, expected_cells.get(key, ""), place_name]
				)

	for place_name in outdoor_places:
		if not places_with_regions.has(place_name):
			errors.append("室外地点缺少感知区域：%s" % place_name)
	var actual_count := actual_cells.size()
	if int(grid.get("legalCellCount", -1)) != actual_count:
		errors.append("legalCellCount 与实际唯一位置格数量不一致")
	var missing_count := expected_cells.size() - actual_count
	if missing_count < 0:
		missing_count = 0
	if int(grid.get("excludedSampleCellCount", -1)) != missing_count:
		errors.append("excludedSampleCellCount 与导航采样差额不一致")
	_validate_required_positions(masks_document, navigation, actual_cells, errors)


static func _validate_required_positions(
	masks_document: Dictionary,
	navigation: Dictionary,
	actual_cells: Dictionary,
	errors: PackedStringArray,
) -> void:
	var cell_size := int(navigation.get("cellSize", 0))
	for value in masks_document.get("requiredPositions", []) as Array:
		if not value is Dictionary:
			continue
		var required_position := value as Dictionary
		var pair := required_position.get("position", []) as Array
		if pair.size() < 2 or cell_size <= 0:
			continue
		var cell := Vector2i(
			floori(float(pair[0]) / float(cell_size)),
			floori(float(pair[1]) / float(cell_size)),
		)
		var key := _cell_key(cell)
		var expected_place_name := str(required_position.get("placeName", ""))
		if str(actual_cells.get(key, "")) != expected_place_name:
			errors.append(
				"必要位置 %s 必须唯一属于 %s"
				% [required_position.get("name", key), expected_place_name]
			)


static func _packed_dictionary_polygon(point_values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value in point_values:
		if not value is Dictionary:
			continue
		var point := value as Dictionary
		result.append(Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))))
	return result


static func _packed_pair_polygon(point_values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value in point_values:
		if not value is Array:
			continue
		var pair := value as Array
		if pair.size() >= 2:
			result.append(Vector2(float(pair[0]), float(pair[1])))
	return result


static func _inside_any(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


static func _place_for_point(
	point: Vector2,
	masks: Array[Dictionary],
	default_place_name: String,
) -> String:
	for mask in masks:
		if Geometry2D.is_point_in_polygon(point, mask.get("polygon") as PackedVector2Array):
			return str(mask.get("placeName", default_place_name))
	return default_place_name


static func _cell_key(cell: Vector2i) -> String:
	return "%05d:%05d" % [cell.y, cell.x]
