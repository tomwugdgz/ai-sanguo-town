class_name TownIndoorMovementClearance
extends RefCounted


const FEET_CENTER_OFFSET := Vector2(0.0, -12.0)
const FEET_RADIUS := 18.0
const CLEARANCE_MARGIN := 1.0
const REQUIRED_CLEARANCE := FEET_RADIUS + CLEARANCE_MARGIN
const EPSILON := 0.001
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP,
]


static func body_origin_is_safe(
	body_origin: Vector2,
	boundary_rects: Array[Rect2],
	furniture_polygons: Array[PackedVector2Array],
) -> bool:
	if not body_origin.is_finite():
		return false
	var feet_center := body_origin + FEET_CENTER_OFFSET
	for rect in boundary_rects:
		if _point_rect_distance(feet_center, rect) <= REQUIRED_CLEARANCE:
			return false
	for polygon in furniture_polygons:
		if polygon.size() < 3:
			continue
		if (
			Geometry2D.is_point_in_polygon(feet_center, polygon)
			or _point_polygon_distance(feet_center, polygon) <= REQUIRED_CLEARANCE
		):
			return false
	return true


static func body_segment_is_safe(
	from_body_origin: Vector2,
	to_body_origin: Vector2,
	boundary_rects: Array[Rect2],
	furniture_polygons: Array[PackedVector2Array],
) -> bool:
	if not from_body_origin.is_finite() or not to_body_origin.is_finite():
		return false
	var start := from_body_origin + FEET_CENTER_OFFSET
	var finish := to_body_origin + FEET_CENTER_OFFSET
	for rect in boundary_rects:
		if _segment_rect_distance(start, finish, rect) <= REQUIRED_CLEARANCE:
			return false
	for polygon in furniture_polygons:
		if polygon.size() < 3:
			continue
		if (
			Geometry2D.is_point_in_polygon(start, polygon)
			or Geometry2D.is_point_in_polygon(finish, polygon)
			or _segment_polygon_distance(start, finish, polygon) <= REQUIRED_CLEARANCE
		):
			return false
	return true


static func filter_walkable_cells(
	cells: Dictionary,
	cell_size: float,
	boundary_rects: Array[Rect2],
	furniture_polygons: Array[PackedVector2Array],
) -> Dictionary:
	var result := {}
	for cell_value: Variant in cells:
		var cell := cell_value as Vector2i
		var body_origin := body_origin_for_cell(cell, cell_size)
		if body_origin_is_safe(body_origin, boundary_rects, furniture_polygons):
			result[cell] = true
	return result


static func subdivide_cells(
	source_cells: Dictionary,
	source_cell_size: int,
	navigation_cell_size: int,
) -> Dictionary:
	if (
		source_cells.is_empty()
		or source_cell_size <= 0
		or navigation_cell_size <= 0
		or source_cell_size % navigation_cell_size != 0
	):
		return {}
	var result := {}
	var divisions := int(source_cell_size / navigation_cell_size)
	for source_value: Variant in source_cells:
		var source_cell := source_value as Vector2i
		var first := source_cell * divisions
		for offset_y in divisions:
			for offset_x in divisions:
				result[first + Vector2i(offset_x, offset_y)] = true
	return result


static func retain_reachable_cells(
	cells: Dictionary,
	cell_size: float,
	preferred_body_origin: Vector2,
) -> Dictionary:
	if cells.is_empty() or cell_size <= 0.0:
		return {}
	var remaining := cells.duplicate()
	var best := {}
	var best_distance := INF
	while not remaining.is_empty():
		var seed := remaining.keys()[0] as Vector2i
		var component := {seed: true}
		var queue: Array[Vector2i] = [seed]
		remaining.erase(seed)
		var cursor := 0
		var component_distance := INF
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			component_distance = minf(
				component_distance,
				body_origin_for_cell(current, cell_size).distance_squared_to(
					preferred_body_origin
				),
			)
			for offset in CARDINAL_OFFSETS:
				var neighbor := current + offset
				if cells.has(neighbor) and not component.has(neighbor):
					component[neighbor] = true
					remaining.erase(neighbor)
					queue.append(neighbor)
		if (
			component.size() > best.size()
			or (
				component.size() == best.size()
				and component_distance < best_distance
			)
		):
			best = component
			best_distance = component_distance
	return best


static func body_origin_for_cell(cell: Vector2i, cell_size: float) -> Vector2:
	# 导航坐标始终表示人物根节点（地面落脚点）。细分网格负责找到
	# 能容纳偏移脚部碰撞体的位置，不能把碰撞体中心冒充人物位置。
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


static func _point_rect_distance(point: Vector2, rect: Rect2) -> float:
	if rect.has_point(point):
		return 0.0
	var closest := Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y),
	)
	return point.distance_to(closest)


static func _segment_rect_distance(start: Vector2, finish: Vector2, rect: Rect2) -> float:
	if rect.has_point(start) or rect.has_point(finish):
		return 0.0
	var corners := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	return _segment_polygon_distance(start, finish, corners)


static func _point_polygon_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for index in polygon.size():
		best = minf(
			best,
			_point_segment_distance(
				point,
				polygon[index],
				polygon[(index + 1) % polygon.size()],
			),
		)
	return best


static func _segment_polygon_distance(
	start: Vector2,
	finish: Vector2,
	polygon: PackedVector2Array,
) -> float:
	var best := INF
	for index in polygon.size():
		var edge_start := polygon[index]
		var edge_finish := polygon[(index + 1) % polygon.size()]
		if Geometry2D.segment_intersects_segment(
			start,
			finish,
			edge_start,
			edge_finish,
		) != null:
			return 0.0
		best = minf(
			best,
			_segment_distance(start, finish, edge_start, edge_finish),
		)
	return best


static func _segment_distance(
	first_start: Vector2,
	first_finish: Vector2,
	second_start: Vector2,
	second_finish: Vector2,
) -> float:
	return minf(
		minf(
			_point_segment_distance(first_start, second_start, second_finish),
			_point_segment_distance(first_finish, second_start, second_finish),
		),
		minf(
			_point_segment_distance(second_start, first_start, first_finish),
			_point_segment_distance(second_finish, first_start, first_finish),
		),
	)


static func _point_segment_distance(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= EPSILON:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)
