extends RefCounted

const OUTDOOR_SPACE_ID := "town_outdoor"
const OUTDOOR_COLLISION_PATH := "res://world/maps/town/generated/collision.json"
const MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)
const PORTAL_CATALOG := preload(
	"res://world/data/town/TownPortalCatalog.gd"
)
const VALID_NODE_KINDS := ["junction", "place_arrival", "portal_outside", "portal_inside"]


static func validate(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.is_empty():
		errors.append("World 静态数据为空")
		return errors
	var spaces := _required_array(data.get("mapSpaces"), "mapSpaces", errors)
	var places := _required_array(data.get("places"), "places", errors)
	var regions := _required_array(data.get("perceptionRegions"), "perceptionRegions", errors)
	var connections := _required_array(data.get("connections"), "connections", errors)
	var movement_value: Variant = data.get("movementNetwork")
	if not movement_value is Dictionary:
		errors.append("movementNetwork 必须为对象")
		return errors
	var movement := movement_value as Dictionary
	var nodes := _required_array(movement.get("nodes"), "movementNetwork.nodes", errors)
	var edges := _required_array(movement.get("edges"), "movementNetwork.edges", errors)
	var arrivals := _required_array(
		movement.get("arrivalNodes"),
		"movementNetwork.arrivalNodes",
		errors,
	)
	if not errors.is_empty():
		return errors

	var spaces_by_id := _index_by(spaces, "id", "地图空间", errors)
	var places_by_name := _index_by(places, "name", "地点", errors)
	var regions_by_id := _index_by(regions, "id", "感知区域", errors)
	var nodes_by_id := _index_by(nodes, "id", "路网节点", errors)
	var region_lookup := _build_region_lookup(data, regions, errors)
	var collision_records := MOVEMENT_CLEARANCE.collision_records(
		_load_json_array(OUTDOOR_COLLISION_PATH)
	)
	if collision_records.is_empty():
		errors.append("正式室外碰撞不可用，无法校验居民移动路线")

	if nodes.size() != 74:
		errors.append("固定路网必须包含 74 个节点，实际为 %d" % nodes.size())
	if edges.size() != 93:
		errors.append("固定路网必须包含 93 条折线边，实际为 %d" % edges.size())
	if arrivals.size() != 30:
		errors.append("30 个地点必须各有一个到达点，实际为 %d" % arrivals.size())
	if connections.size() != 23:
		errors.append("必须定义 23 条室内外连接，实际为 %d" % connections.size())

	for node_index in nodes.size():
		var node_value: Variant = nodes[node_index]
		if not node_value is Dictionary:
			errors.append("movementNetwork.nodes[%d] 必须为对象" % node_index)
			continue
		var node := node_value as Dictionary
		var node_id := _string_or_empty(node.get("id"))
		var kind := _required_string(node.get("kind"), "路网节点 %s.kind" % node_id, errors)
		if kind not in VALID_NODE_KINDS:
			errors.append("路网节点 %s 的 kind 无效：%s" % [node_id, kind])
		var space_id := _required_string(node.get("spaceId"), "路网节点 %s.spaceId" % node_id, errors)
		var place_name := _required_string(node.get("placeName"), "路网节点 %s.placeName" % node_id, errors)
		var region_id := _required_string(node.get("regionId"), "路网节点 %s.regionId" % node_id, errors)
		if not spaces_by_id.has(space_id):
			errors.append("路网节点 %s 引用了不存在的空间：%s" % [node_id, space_id])
		if not places_by_name.has(place_name):
			errors.append("路网节点 %s 引用了不存在的地点：%s" % [node_id, place_name])
		if not regions_by_id.has(region_id):
			errors.append("路网节点 %s 引用了不存在的区域：%s" % [node_id, region_id])
		var position := _validated_point(
			node.get("position"),
			"路网节点 %s.position" % node_id,
			errors,
		)
		if not position.is_finite():
			continue
		if (
			space_id == OUTDOOR_SPACE_ID
			and (
				collision_records.is_empty()
				or not MOVEMENT_CLEARANCE.body_origin_is_safe(
					position,
					collision_records,
				)
			)
		):
			errors.append(
				"路网节点 %s 不满足居民脚部碰撞净空：%s"
				% [node_id, position]
			)
		var is_exterior_portal := (
			kind == "portal_outside"
			and space_id == OUTDOOR_SPACE_ID
		)
		if (
			is_exterior_portal
			and not _portal_node_reaches_trigger(node_id, position)
		):
			errors.append("室外入口节点 %s 没有接触玩家门槛" % node_id)
		var membership := _membership_at(region_lookup, space_id, position)
		if membership.is_empty():
			errors.append("路网节点 %s 不在合法感知区域：%s" % [node_id, position])
		else:
			if str(membership.get("regionId", "")) != region_id:
				errors.append("路网节点 %s 的 regionId 与位置归属不一致" % node_id)
			if str(membership.get("placeName", "")) != place_name:
				errors.append("路网节点 %s 的 placeName 与位置归属不一致" % node_id)

	var edge_ids := {}
	for edge_index in edges.size():
		var edge_value: Variant = edges[edge_index]
		if not edge_value is Dictionary:
			errors.append("movementNetwork.edges[%d] 必须为对象" % edge_index)
			continue
		var edge := edge_value as Dictionary
		var edge_id := _required_string(edge.get("id"), "路线边 id", errors)
		_unique(edge_id, "路线边", edge_ids, errors)
		var from_id := _required_string(edge.get("fromNodeId"), "路线边 %s.fromNodeId" % edge_id, errors)
		var to_id := _required_string(edge.get("toNodeId"), "路线边 %s.toNodeId" % edge_id, errors)
		if not nodes_by_id.has(from_id) or not nodes_by_id.has(to_id) or from_id == to_id:
			errors.append("路线边 %s 的节点引用无效" % edge_id)
			continue
		if _required_string(edge.get("direction"), "路线边 %s.direction" % edge_id, errors) != "双向":
			errors.append("路线边 %s 必须为双向" % edge_id)
		var from_node := nodes_by_id[from_id] as Dictionary
		var to_node := nodes_by_id[to_id] as Dictionary
		if str(from_node.get("spaceId", "")) != OUTDOOR_SPACE_ID or str(to_node.get("spaceId", "")) != OUTDOOR_SPACE_ID:
			errors.append("固定折线路线 %s 只能连接室外节点" % edge_id)
		var polyline_value: Variant = edge.get("polyline")
		if not polyline_value is Array:
			errors.append("路线边 %s 的 polyline 必须为数组" % edge_id)
			continue
		var polyline := polyline_value as Array
		if polyline.size() < 2:
			errors.append("路线边 %s 至少需要两个折线点" % edge_id)
			continue
		var points := _polyline_points(polyline, "路线边 %s.polyline" % edge_id, errors)
		var length_value: Variant = edge.get("length")
		if not _is_finite_number(length_value):
			errors.append("路线边 %s 的 length 必须为有限数字" % edge_id)
		if not _points_are_finite(points):
			continue
		var from_position := _validated_point(
			from_node.get("position"),
			"路网节点 %s.position" % from_id,
			errors,
		)
		var to_position := _validated_point(
			to_node.get("position"),
			"路网节点 %s.position" % to_id,
			errors,
		)
		if not from_position.is_finite() or not to_position.is_finite():
			continue
		if not points[0].is_equal_approx(from_position):
			errors.append("路线边 %s 起点与 fromNode 不一致" % edge_id)
		if not points[-1].is_equal_approx(to_position):
			errors.append("路线边 %s 终点与 toNode 不一致" % edge_id)
		var measured_length := _polyline_length(points)
		if _is_finite_number(length_value) and absf(measured_length - float(length_value)) > 0.01:
			errors.append("路线边 %s 的 length 与折线长度不一致" % edge_id)
		_validate_polyline_membership(edge_id, points, region_lookup, errors)
		_validate_polyline_collision_clearance(
			edge_id,
			points,
			collision_records,
			errors,
		)

	var arrival_ids := {}
	var arrivals_by_place := {}
	for arrival_index in arrivals.size():
		var arrival_value: Variant = arrivals[arrival_index]
		if not arrival_value is Dictionary:
			errors.append("movementNetwork.arrivalNodes[%d] 必须为对象" % arrival_index)
			continue
		var arrival := arrival_value as Dictionary
		var arrival_id := _required_string(arrival.get("id"), "地点到达点 id", errors)
		_unique(arrival_id, "地点到达点", arrival_ids, errors)
		var place_name := _required_string(
			arrival.get("placeName"),
			"地点到达点 %s.placeName" % arrival_id,
			errors,
		)
		var node_id := _required_string(
			arrival.get("nodeId"),
			"地点到达点 %s.nodeId" % arrival_id,
			errors,
		)
		if not places_by_name.has(place_name):
			errors.append("地点到达点 %s 引用了不存在的地点：%s" % [arrival_id, place_name])
		if not nodes_by_id.has(node_id):
			errors.append("地点到达点 %s 引用了不存在的节点：%s" % [arrival_id, node_id])
		else:
			var node := nodes_by_id[node_id] as Dictionary
			if str(node.get("placeName", "")) != place_name:
				errors.append("地点到达点 %s 的地点与节点归属不一致" % arrival_id)
		var place_arrivals := arrivals_by_place.get(place_name, []) as Array
		place_arrivals.append(arrival_id)
		arrivals_by_place[place_name] = place_arrivals
	for place_name_value in places_by_name:
		var place_name := str(place_name_value)
		if (arrivals_by_place.get(place_name, []) as Array).is_empty():
			errors.append("地点 %s 没有可用到达点" % place_name)

	var connection_ids := {}
	for connection_index in connections.size():
		var connection_value: Variant = connections[connection_index]
		if not connection_value is Dictionary:
			errors.append("connections[%d] 必须为对象" % connection_index)
			continue
		var connection := connection_value as Dictionary
		var connection_id := _required_string(connection.get("id"), "地点连接 id", errors)
		_unique(connection_id, "地点连接", connection_ids, errors)
		if _required_string(
			connection.get("direction"),
			"地点连接 %s.direction" % connection_id,
			errors,
		) != "双向":
			errors.append("地点连接 %s 必须为双向" % connection_id)
		if not _is_exact_integer(connection.get("movementMinutes"), 1):
			errors.append("地点连接 %s 必须耗时 1 游戏分钟" % connection_id)
		for end_name in ["from", "to"]:
			var end_value: Variant = connection.get(end_name)
			if not end_value is Dictionary:
				errors.append("地点连接 %s.%s 必须为对象" % [connection_id, end_name])
				continue
			_validate_connection_end(
				connection_id,
				end_name,
				end_value as Dictionary,
				nodes_by_id,
				region_lookup,
				errors,
			)

	_validate_graph_connected(nodes_by_id, edges, connections, errors)
	return errors


static func _validate_polyline_collision_clearance(
	edge_id: String,
	points: PackedVector2Array,
	collision_records: Array[Dictionary],
	errors: PackedStringArray,
) -> void:
	if collision_records.is_empty():
		return
	for index in range(1, points.size()):
		if MOVEMENT_CLEARANCE.body_segment_is_safe(
			points[index - 1],
			points[index],
			collision_records,
		):
			continue
		var clearance := MOVEMENT_CLEARANCE.minimum_body_segment_clearance(
			points[index - 1],
			points[index],
			collision_records,
		)
		errors.append(
			(
				"路线边 %s 第 %d 段不满足居民脚部碰撞净空："
				+ "碰撞=%s，实际=%.3fpx，要求=%.3fpx"
			)
			% [
				edge_id,
				index - 1,
				String(clearance.get("collisionId", "")),
				float(clearance.get("clearancePx", 0.0)),
				float(clearance.get("requiredClearancePx", 0.0)),
			]
		)
		return


static func _build_region_lookup(
	data: Dictionary,
	regions: Array,
	errors: PackedStringArray
) -> Dictionary:
	var lookup := {"outdoorCells": {}, "rectsBySpace": {}}
	var grid_value: Variant = data.get("perceptionGrid")
	if not grid_value is Dictionary:
		errors.append("perceptionGrid 必须为对象")
		return lookup
	var grid := grid_value as Dictionary
	var cell_size_value: Variant = grid.get("cellSize")
	if not _is_positive_integer(cell_size_value):
		errors.append("perceptionGrid.cellSize 必须为正整数")
		return lookup
	var cell_size := int(cell_size_value)
	lookup["cellSize"] = cell_size
	for region_index in regions.size():
		var region_value: Variant = regions[region_index]
		if not region_value is Dictionary:
			errors.append("perceptionRegions[%d] 必须为对象" % region_index)
			continue
		var region := region_value as Dictionary
		var shape_value: Variant = region.get("shape")
		if not shape_value is Dictionary:
			errors.append("perceptionRegions[%d].shape 必须为对象" % region_index)
			continue
		var shape := shape_value as Dictionary
		var shape_type := _required_string(
			shape.get("type"),
			"perceptionRegions[%d].shape.type" % region_index,
			errors,
		)
		if shape_type == "grid_cells":
			var cells := _required_array(
				shape.get("cells"),
				"perceptionRegions[%d].shape.cells" % region_index,
				errors,
			)
			for cell_index in cells.size():
				var cell_value: Variant = cells[cell_index]
				if (
					not cell_value is Array
					or (cell_value as Array).size() != 2
					or not _is_integer_number((cell_value as Array)[0])
					or not _is_integer_number((cell_value as Array)[1])
				):
					errors.append(
						"perceptionRegions[%d].shape.cells[%d] 必须为整数坐标"
						% [region_index, cell_index]
					)
					continue
				var pair := cell_value as Array
				var key := _cell_key(int(pair[0]), int(pair[1]))
				(lookup["outdoorCells"] as Dictionary)[key] = {
					"regionId": str(region.get("id", "")),
					"placeName": str(region.get("placeName", "")),
				}
		elif shape_type == "rect":
			var space_id := str(region.get("spaceId", ""))
			var rect_is_valid := true
			for component in ["x", "y", "width", "height"]:
				if not _is_finite_number(shape.get(component)):
					errors.append(
						"perceptionRegions[%d].shape.%s 必须为有限数字"
						% [region_index, component]
					)
					rect_is_valid = false
			if not rect_is_valid:
				continue
			var entries := (lookup["rectsBySpace"] as Dictionary).get(space_id, []) as Array
			entries.append({"region": region, "rect": Rect2(
				float(shape.get("x", 0.0)),
				float(shape.get("y", 0.0)),
				float(shape.get("width", 0.0)),
				float(shape.get("height", 0.0))
			)})
			(lookup["rectsBySpace"] as Dictionary)[space_id] = entries
		else:
			errors.append("感知区域 %s 使用了不支持的 shape.type：%s" % [region.get("id", ""), shape_type])
	return lookup


static func _membership_at(lookup: Dictionary, space_id: String, position: Vector2) -> Dictionary:
	if space_id == OUTDOOR_SPACE_ID:
		var cell_size := int(lookup.get("cellSize", 0))
		if cell_size <= 0:
			return {}
		return (lookup.get("outdoorCells", {}) as Dictionary).get(
			_cell_key(floori(position.x / float(cell_size)), floori(position.y / float(cell_size))),
			{}
		) as Dictionary
	var result := {}
	for entry_value in (lookup.get("rectsBySpace", {}) as Dictionary).get(space_id, []) as Array:
		var entry := entry_value as Dictionary
		var rect := entry.get("rect") as Rect2
		if rect.has_point(position):
			if not result.is_empty():
				return {}
			var region := entry.get("region", {}) as Dictionary
			result = {
				"regionId": str(region.get("id", "")),
				"placeName": str(region.get("placeName", "")),
			}
	return result


static func _validate_polyline_membership(
	edge_id: String,
	points: PackedVector2Array,
	lookup: Dictionary,
	errors: PackedStringArray
) -> void:
	for index in range(1, points.size()):
		var start := points[index - 1]
		var finish := points[index]
		var length := start.distance_to(finish)
		var sample_count := maxi(1, ceili(length / 6.0))
		for sample_index in range(sample_count + 1):
			var position := start.lerp(finish, float(sample_index) / float(sample_count))
			if _membership_at(lookup, OUTDOOR_SPACE_ID, position).is_empty():
				errors.append("路线边 %s 穿过非法室外位置：%s" % [edge_id, position])
				return


static func _validate_connection_end(
	connection_id: String,
	label: String,
	end: Dictionary,
	nodes_by_id: Dictionary,
	lookup: Dictionary,
	errors: PackedStringArray
) -> void:
	var node_id := str(end.get("nodeId", ""))
	if not nodes_by_id.has(node_id):
		errors.append("地点连接 %s.%s 引用了不存在的节点：%s" % [connection_id, label, node_id])
		return
	var node := nodes_by_id[node_id] as Dictionary
	for key in ["spaceId", "regionId", "placeName"]:
		if str(end.get(key, "")) != str(node.get(key, "")):
			errors.append("地点连接 %s.%s.%s 与节点不一致" % [connection_id, label, key])
	var position := _validated_point(
		end.get("position"),
		"地点连接 %s.%s.position" % [connection_id, label],
		errors,
	)
	var node_position := _validated_point(
		node.get("position"),
		"路网节点 %s.position" % node_id,
		errors,
	)
	if not position.is_finite() or not node_position.is_finite():
		return
	if not position.is_equal_approx(node_position):
		errors.append("地点连接 %s.%s.position 与节点不一致" % [connection_id, label])
	if _membership_at(lookup, str(end.get("spaceId", "")), position).is_empty():
		errors.append("地点连接 %s.%s 不在合法区域" % [connection_id, label])


static func _portal_node_reaches_trigger(
	node_id: String,
	position: Vector2,
) -> bool:
	if (
		not node_id.begins_with("portal_")
		or not node_id.ends_with("_outside")
	):
		return false
	var portal_id := node_id.trim_suffix("_outside")
	var portal := PORTAL_CATALOG.definition(portal_id)
	return (
		not portal.is_empty()
		and MOVEMENT_CLEARANCE.body_origin_overlaps_rect(
			position,
			PORTAL_CATALOG.exterior_trigger_rect(portal),
		)
	)


static func _validate_graph_connected(
	nodes_by_id: Dictionary,
	edges: Array,
	connections: Array,
	errors: PackedStringArray
) -> void:
	var adjacency := {}
	for node_id in nodes_by_id:
		adjacency[node_id] = []
	for edge_value in edges:
		if not edge_value is Dictionary:
			continue
		var edge := edge_value as Dictionary
		_add_adjacency(adjacency, str(edge.get("fromNodeId", "")), str(edge.get("toNodeId", "")))
	for connection_value in connections:
		if not connection_value is Dictionary:
			continue
		var connection := connection_value as Dictionary
		var from_value: Variant = connection.get("from")
		var to_value: Variant = connection.get("to")
		if not from_value is Dictionary or not to_value is Dictionary:
			continue
		_add_adjacency(
			adjacency,
			str((from_value as Dictionary).get("nodeId", "")),
			str((to_value as Dictionary).get("nodeId", ""))
		)
	if nodes_by_id.is_empty():
		return
	var first_id := str(nodes_by_id.keys()[0])
	var visited := {first_id: true}
	var queue := [first_id]
	var cursor := 0
	while cursor < queue.size():
		var current := str(queue[cursor])
		cursor += 1
		for neighbor_value in adjacency.get(current, []) as Array:
			var neighbor := str(neighbor_value)
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	if visited.size() != nodes_by_id.size():
		errors.append(
			"固定路网存在孤立节点：已连通 %d / 总计 %d"
			% [visited.size(), nodes_by_id.size()]
		)


static func _add_adjacency(adjacency: Dictionary, left_id: String, right_id: String) -> void:
	if not adjacency.has(left_id) or not adjacency.has(right_id):
		return
	(adjacency[left_id] as Array).append(right_id)
	(adjacency[right_id] as Array).append(left_id)


static func _index_by(
	values: Array,
	key: String,
	label: String,
	errors: PackedStringArray
) -> Dictionary:
	var result := {}
	for index in values.size():
		var value: Variant = values[index]
		if not value is Dictionary:
			errors.append("%s[%d] 必须为对象" % [label, index])
			continue
		var dictionary := value as Dictionary
		var id := _required_string(dictionary.get(key), "%s标识" % label, errors)
		_unique(id, label, result, errors)
		if not id.is_empty():
			result[id] = dictionary
	return result


static func _unique(text: String, label: String, seen: Dictionary, errors: PackedStringArray) -> void:
	if text.is_empty():
		errors.append("%s标识不能为空" % label)
	elif seen.has(text):
		errors.append("%s标识重复：%s" % [label, text])
	else:
		seen[text] = true


static func _polyline_points(
	values: Array,
	path: String,
	errors: PackedStringArray,
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in values.size():
		result.append(_validated_point(values[index], "%s[%d]" % [path, index], errors))
	return result


static func _polyline_length(points: PackedVector2Array) -> float:
	var result := 0.0
	for index in range(1, points.size()):
		result += points[index - 1].distance_to(points[index])
	return result


static func _validated_point(
	value: Variant,
	path: String,
	errors: PackedStringArray,
) -> Vector2:
	if not value is Dictionary:
		errors.append("%s 必须为坐标对象" % path)
		return Vector2.INF
	var point := value as Dictionary
	if not _is_finite_number(point.get("x")) or not _is_finite_number(point.get("y")):
		errors.append("%s.x/y 必须为有限数字" % path)
		return Vector2.INF
	return Vector2(float(point.get("x")), float(point.get("y")))


static func _points_are_finite(points: PackedVector2Array) -> bool:
	for point in points:
		if not point.is_finite():
			return false
	return true


static func _required_string(
	value: Variant,
	path: String,
	errors: PackedStringArray,
) -> String:
	if not value is String:
		errors.append("%s 必须为字符串" % path)
		return ""
	return value as String


static func _string_or_empty(value: Variant) -> String:
	if not value is String:
		return ""
	return value as String


static func _required_array(
	value: Variant,
	path: String,
	errors: PackedStringArray,
) -> Array:
	if not value is Array:
		errors.append("%s 必须为数组" % path)
		return []
	return value as Array


static func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _is_integer_number(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) == roundf(float(value))


static func _is_positive_integer(value: Variant) -> bool:
	return _is_integer_number(value) and float(value) > 0.0


static func _is_exact_integer(value: Variant, expected: int) -> bool:
	return (
		_is_finite_number(value)
		and _is_integer_number(value)
		and float(value) == float(expected)
	)


static func _load_json_array(path: String) -> Array:
	if path.is_empty() or not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Array:
		return []
	return parsed as Array


static func _cell_key(x: int, y: int) -> String:
	return "%d:%d" % [x, y]
