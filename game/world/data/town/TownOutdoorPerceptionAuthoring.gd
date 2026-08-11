extends SceneTree

const AUTHORING_FILES := preload(
	"res://world/data/town/TownAuthoringFiles.gd"
)
const NAVIGATION_REFERENCE_PATH := "res://world/maps/town/generated/navigation.json"
const OUTDOOR_NAVIGATION_GRID_PATH := (
	"res://world/data/town/source/outdoor_navigation_grid.json"
)
const MASKS_PATH := "res://world/data/town/source/outdoor_perception_masks.json"
const PLACES_PATH := "res://world/data/town/source/places.json"
const OUTPUT_PATH := "res://world/data/town/source/perception_regions.json"
const OUTDOOR_SPACE_ID := "town_outdoor"
const MAP_WIDTH := 6688
const MAP_HEIGHT := 3764
const MIN_REGION_CELL_COUNT := 3
const VALIDATOR := preload("res://world/data/town/TownOutdoorPerceptionValidator.gd")


func _initialize() -> void:
	var navigation := load_json_object(NAVIGATION_REFERENCE_PATH)
	var outdoor_navigation_grid := load_json_object(
		OUTDOOR_NAVIGATION_GRID_PATH,
	)
	var masks_document := load_json_object(MASKS_PATH)
	var places_document := load_json_object(PLACES_PATH)
	if (
		navigation.is_empty()
		or outdoor_navigation_grid.is_empty()
		or masks_document.is_empty()
		or places_document.is_empty()
	):
		_fail("无法读取室外通行参考或地点边界蒙版")
		return
	var document := build_document(
		navigation,
		masks_document,
		outdoor_navigation_grid,
	)
	if document.is_empty():
		_fail("无法从室外通行参考生成感知区域")
		return
	var validation_errors := VALIDATOR.validate_document(
		document,
		navigation,
		masks_document,
		places_document,
		outdoor_navigation_grid,
	)
	if not validation_errors.is_empty():
		_fail(str(validation_errors[0]))
		return
	if not write_document(OUTPUT_PATH, document):
		_fail("无法写入 %s" % OUTPUT_PATH)
		return
	print(
		"TOWN_OUTDOOR_PERCEPTION_AUTHORING_PASS: %d legal cells, %d regions"
		% [
			int((document.get("grid", {}) as Dictionary).get("legalCellCount", 0)),
			(document.get("regions", []) as Array).size(),
		]
	)
	quit(0)


static func build_document(
	navigation: Dictionary,
	masks_document: Dictionary,
	outdoor_navigation_grid: Dictionary = {},
) -> Dictionary:

	var cell_size := int(navigation.get("cellSize", 0))
	var grid_width := int(navigation.get("width", 0))
	var grid_height := int(navigation.get("height", 0))
	if cell_size <= 0 or grid_width <= 0 or grid_height <= 0:
		return {}

	var walkable_polygons := _walkable_polygons(navigation.get("regions", []) as Array)
	var masks := _masks(masks_document.get("masks", []) as Array)
	var default_place_name := str(masks_document.get("defaultPlaceName", ""))
	if walkable_polygons.is_empty() or default_place_name.is_empty():
		return {}

	var cells_by_place := _assign_cells(
		walkable_polygons,
		masks,
		default_place_name,
		cell_size,
		grid_width,
		grid_height
	)
	_apply_outdoor_navigation_grid(
		cells_by_place,
		outdoor_navigation_grid,
		masks,
		default_place_name,
		cell_size,
		grid_width,
		grid_height,
	)
	var required_position_cells := _apply_required_positions(
		cells_by_place,
		masks_document.get("requiredPositions", []) as Array,
		cell_size,
		grid_width,
		grid_height
	)
	var regions := _connected_regions(cells_by_place, cell_size)
	var legal_cell_count := 0
	for region_value in regions:
		var region := region_value as Dictionary
		legal_cell_count += ((region.get("shape", {}) as Dictionary).get("cells", []) as Array).size()
	var sampled_cell_count := 0
	for cells_value in cells_by_place.values():
		sampled_cell_count += (cells_value as Array).size()

	return {
		"schemaVersion": 1,
		"worldId": "town",
		"grid": {
			"origin": {"x": 0, "y": 0},
			"cellSize": cell_size,
			"width": grid_width,
			"height": grid_height,
			"legalCellCount": legal_cell_count,
			"excludedSampleCellCount": sampled_cell_count - legal_cell_count,
			"requiredPositionCellCount": required_position_cells,
		},
		"regions": regions,
	}


static func _apply_outdoor_navigation_grid(
	cells_by_place: Dictionary,
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
	var occupied := {}
	for place_name_value: Variant in cells_by_place:
		for cell_value: Variant in cells_by_place[place_name_value] as Array:
			occupied[_cell_key(cell_value as Vector2i)] = true
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
			or occupied.has(_cell_key(cell))
		):
			continue
		var center := (Vector2(cell) + Vector2(0.5, 0.5)) * float(cell_size)
		var place_name := _place_for_point(center, masks, default_place_name)
		var cells := cells_by_place.get(place_name, []) as Array
		cells.append(cell)
		cells_by_place[place_name] = cells
		occupied[_cell_key(cell)] = true


static func load_json_object(path: String) -> Dictionary:
	return AUTHORING_FILES.load_json_object(path)


static func serialize_document(document: Dictionary) -> String:
	return AUTHORING_FILES.serialize_document(document)


static func write_document(path: String, document: Dictionary) -> bool:
	return AUTHORING_FILES.write_document(path, document)


static func _walkable_polygons(region_values: Array) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for value in region_values:
		var region := value as Dictionary
		if not bool(region.get("enabled", true)) or str(region.get("type", "")) != "walkable":
			continue
		var polygon := _packed_polygon((region.get("shape", {}) as Dictionary).get("points", []) as Array)
		if polygon.size() >= 3:
			polygons.append(polygon)
	return polygons


static func _masks(mask_values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in mask_values:
		var mask := value as Dictionary
		var polygon := _packed_pair_polygon(mask.get("polygon", []) as Array)
		if str(mask.get("placeName", "")).is_empty() or polygon.size() < 3:
			continue
		result.append({
			"placeName": str(mask.get("placeName", "")),
			"polygon": polygon,
		})
	return result


static func _assign_cells(
	walkable_polygons: Array[PackedVector2Array],
	masks: Array[Dictionary],
	default_place_name: String,
	cell_size: int,
	grid_width: int,
	grid_height: int
) -> Dictionary:
	var cells_by_place := {}
	for y in grid_height:
		for x in grid_width:
			var center := Vector2(
				float(x * cell_size) + float(cell_size) * 0.5,
				float(y * cell_size) + float(cell_size) * 0.5
			)
			if center.x >= MAP_WIDTH or center.y >= MAP_HEIGHT:
				continue
			if not _inside_any(center, walkable_polygons):
				continue
			var place_name := _place_for_point(center, masks, default_place_name)
			var cells := cells_by_place.get(place_name, []) as Array
			cells.append(Vector2i(x, y))
			cells_by_place[place_name] = cells
	return cells_by_place


static func _connected_regions(cells_by_place: Dictionary, cell_size: int) -> Array:
	var regions := []
	var place_names := PackedStringArray()
	for place_name_value in cells_by_place:
		place_names.append(str(place_name_value))
	place_names.sort()
	for place_name in place_names:
		var components := _components(cells_by_place.get(place_name, []) as Array)
		components.sort_custom(func(left: Array, right: Array) -> bool:
			return _cell_key(left[0] as Vector2i) < _cell_key(right[0] as Vector2i)
		)
		var prefix := _region_prefix(place_name)
		for index in components.size():
			var component := components[index] as Array
			if component.size() < MIN_REGION_CELL_COUNT:
				continue
			var serialized_cells := []
			for cell_value in component:
				var cell := cell_value as Vector2i
				serialized_cells.append([cell.x, cell.y])
			regions.append({
				"id": "%s_%02d" % [prefix, index + 1],
				"placeName": place_name,
				"spaceId": OUTDOOR_SPACE_ID,
				"shape": {
					"type": "grid_cells",
					"origin": {"x": 0, "y": 0},
					"cellSize": cell_size,
					"cells": serialized_cells,
				},
			})
	regions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	return regions


static func _apply_required_positions(
	cells_by_place: Dictionary,
	position_values: Array,
	cell_size: int,
	grid_width: int,
	grid_height: int
) -> int:
	var added_count := 0
	for value in position_values:
		var required_position := value as Dictionary
		var place_name := str(required_position.get("placeName", ""))
		var pair := required_position.get("position", []) as Array
		if place_name.is_empty() or pair.size() < 2:
			continue
		var cell := Vector2i(
			floori(float(pair[0]) / float(cell_size)),
			floori(float(pair[1]) / float(cell_size))
		)
		if cell.x < 0 or cell.x >= grid_width or cell.y < 0 or cell.y >= grid_height:
			continue
		var already_present := false
		for existing_place_name in cells_by_place:
			var cells := cells_by_place[existing_place_name] as Array
			var existing_index := cells.find(cell)
			if existing_index >= 0:
				already_present = true
				if str(existing_place_name) != place_name:
					cells.remove_at(existing_index)
					cells_by_place[existing_place_name] = cells
				break
		var destination_cells := cells_by_place.get(place_name, []) as Array
		if not destination_cells.has(cell):
			destination_cells.append(cell)
			cells_by_place[place_name] = destination_cells
		if not already_present:
			added_count += 1
	return added_count


static func _components(cell_values: Array) -> Array:
	var remaining := {}
	for cell_value in cell_values:
		var cell := cell_value as Vector2i
		remaining[_cell_key(cell)] = cell
	var components := []
	while not remaining.is_empty():
		var keys := remaining.keys()
		keys.sort()
		var start_key := str(keys[0])
		var start := remaining[start_key] as Vector2i
		remaining.erase(start_key)
		var queue: Array[Vector2i] = [start]
		var component: Array[Vector2i] = []
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			component.append(current)
			for offset: Vector2i in [
				Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
				Vector2i(-1, 0), Vector2i(1, 0),
				Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
			]:
				var neighbor: Vector2i = current + offset
				var neighbor_key := _cell_key(neighbor)
				if remaining.has(neighbor_key):
					queue.append(remaining[neighbor_key] as Vector2i)
					remaining.erase(neighbor_key)
		component.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
			return _cell_key(left) < _cell_key(right)
		)
		components.append(component)
	return components


static func _inside_any(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


static func _place_for_point(point: Vector2, masks: Array[Dictionary], default_place_name: String) -> String:
	for mask in masks:
		if Geometry2D.is_point_in_polygon(point, mask.get("polygon") as PackedVector2Array):
			return str(mask.get("placeName", default_place_name))
	return default_place_name


static func _packed_polygon(point_values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value in point_values:
		var point := value as Dictionary
		result.append(Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))))
	return result


static func _packed_pair_polygon(point_values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value in point_values:
		var pair := value as Array
		if pair.size() >= 2:
			result.append(Vector2(float(pair[0]), float(pair[1])))
	return result


static func _region_prefix(place_name: String) -> String:
	return {
		"小镇道路": "outdoor_road",
		"中心广场": "outdoor_plaza",
		"市集": "outdoor_market",
		"社区花园": "outdoor_garden",
		"河岸公园": "outdoor_river_park",
		"南入口": "outdoor_south_gate",
		"渔港": "outdoor_harbor",
	}.get(place_name, "outdoor_region")


static func _cell_key(cell: Vector2i) -> String:
	return "%05d:%05d" % [cell.y, cell.x]


func _fail(message: String) -> void:
	printerr("TOWN_OUTDOOR_PERCEPTION_AUTHORING_FAIL: %s" % message)
	quit(1)
