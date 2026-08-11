class_name TownOutdoorMovementClearance
extends RefCounted


const COLLISION_LAYER := 1
const MAP_SIZE := Vector2(6688.0, 3764.0)
const BODY_ORIGIN_BOUNDS := Rect2(
	Vector2(48.0, 192.0),
	Vector2(MAP_SIZE.x - 96.0, MAP_SIZE.y - 216.0),
)
const FEET_CENTER_OFFSET := Vector2(0.0, -12.0)
const FEET_RADIUS := 18.0
const CLEARANCE_MARGIN := 0.0
const REQUIRED_CLEARANCE := FEET_RADIUS + CLEARANCE_MARGIN
const EPSILON := 0.001


static func collision_records(values: Array) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for value: Variant in values:
		if value is not Dictionary:
			return []
		var entry := value as Dictionary
		if entry.get("enabled", true) != true:
			continue
		if int(entry.get("collisionLayer", 0)) & COLLISION_LAYER == 0:
			continue
		var shape_value: Variant = entry.get("shape")
		if shape_value is not Dictionary:
			return []
		var shape := shape_value as Dictionary
		if String(shape.get("type", "")) != "polygon":
			return []
		var point_values: Variant = shape.get("points")
		if point_values is not Array or (point_values as Array).size() < 3:
			return []
		var points := PackedVector2Array()
		for point_value: Variant in (point_values as Array):
			if point_value is not Dictionary:
				return []
			var point_data := point_value as Dictionary
			var x_value: Variant = point_data.get("x")
			var y_value: Variant = point_data.get("y")
			if (
				typeof(x_value) not in [TYPE_INT, TYPE_FLOAT]
				or typeof(y_value) not in [TYPE_INT, TYPE_FLOAT]
			):
				return []
			var point := Vector2(float(x_value), float(y_value))
			if not point.is_finite():
				return []
			points.append(point)
		records.append({
			"id": String(entry.get("id", "")),
			"points": points,
			"bounds": _polygon_bounds(points),
		})
	return records


static func body_origin_is_safe(
	body_origin: Vector2,
	records: Array[Dictionary],
) -> bool:
	return body_origin_has_clearance(
		body_origin,
		records,
		REQUIRED_CLEARANCE,
	)


static func body_origin_overlaps_rect(
	body_origin: Vector2,
	target: Rect2,
) -> bool:
	if not body_origin.is_finite() or not target.has_area():
		return false
	var feet_center := body_origin + FEET_CENTER_OFFSET
	var closest := Vector2(
		clampf(feet_center.x, target.position.x, target.end.x),
		clampf(feet_center.y, target.position.y, target.end.y),
	)
	return feet_center.distance_to(closest) <= FEET_RADIUS + EPSILON


static func body_origin_has_clearance(
	body_origin: Vector2,
	records: Array[Dictionary],
	required_clearance: float,
) -> bool:
	if (
		not body_origin.is_finite()
		or records.is_empty()
		or not is_finite(required_clearance)
		or required_clearance < REQUIRED_CLEARANCE
	):
		return false
	var feet_center := body_origin + FEET_CENTER_OFFSET
	for record: Dictionary in records:
		var bounds := record.get("bounds", Rect2()) as Rect2
		# Rect2.has_point excludes its right and bottom edges. Grow the broad
		# phase slightly so exact tangency still reaches the precise distance
		# check below, matching Godot physics where touching shapes overlap.
		if not bounds.grow(required_clearance + EPSILON).has_point(feet_center):
			continue
		var polygon := record.get("points", PackedVector2Array()) as PackedVector2Array
		if (
			Geometry2D.is_point_in_polygon(feet_center, polygon)
			or _point_polygon_distance(feet_center, polygon)
				<= required_clearance + EPSILON
		):
			return false
	return true


static func body_segment_is_safe(
	from_body_origin: Vector2,
	to_body_origin: Vector2,
	records: Array[Dictionary],
) -> bool:
	if (
		not from_body_origin.is_finite()
		or not to_body_origin.is_finite()
		or records.is_empty()
	):
		return false
	var start := from_body_origin + FEET_CENTER_OFFSET
	var finish := to_body_origin + FEET_CENTER_OFFSET
	var segment_bounds := Rect2(start, Vector2.ZERO).expand(finish).grow(REQUIRED_CLEARANCE)
	for record: Dictionary in records:
		var bounds := record.get("bounds", Rect2()) as Rect2
		if not segment_bounds.intersects(bounds.grow(REQUIRED_CLEARANCE), true):
			continue
		var polygon := record.get("points", PackedVector2Array()) as PackedVector2Array
		if (
			Geometry2D.is_point_in_polygon(start, polygon)
			or Geometry2D.is_point_in_polygon(finish, polygon)
			or _segment_polygon_distance(start, finish, polygon)
				<= REQUIRED_CLEARANCE + EPSILON
		):
			return false
	return true


static func minimum_body_segment_clearance(
	from_body_origin: Vector2,
	to_body_origin: Vector2,
	records: Array[Dictionary],
) -> Dictionary:
	if (
		not from_body_origin.is_finite()
		or not to_body_origin.is_finite()
		or records.is_empty()
	):
		return {}
	var start := from_body_origin + FEET_CENTER_OFFSET
	var finish := to_body_origin + FEET_CENTER_OFFSET
	var best_distance := INF
	var best_id := ""
	for record: Dictionary in records:
		var polygon := record.get("points", PackedVector2Array()) as PackedVector2Array
		var distance := (
			0.0
			if (
				Geometry2D.is_point_in_polygon(start, polygon)
				or Geometry2D.is_point_in_polygon(finish, polygon)
			)
			else _segment_polygon_distance(start, finish, polygon)
		)
		if distance < best_distance:
			best_distance = distance
			best_id = String(record.get("id", ""))
	return {
		"collisionId": best_id,
		"clearancePx": best_distance,
		"requiredClearancePx": REQUIRED_CLEARANCE,
	}


static func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for index in range(1, points.size()):
		bounds = bounds.expand(points[index])
	return bounds


static func _point_polygon_distance(
	point: Vector2,
	polygon: PackedVector2Array,
) -> float:
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
		if _segments_intersect(start, finish, edge_start, edge_finish):
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


static func _point_segment_distance(
	point: Vector2,
	start: Vector2,
	finish: Vector2,
) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= EPSILON:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


static func _segments_intersect(
	first_start: Vector2,
	first_finish: Vector2,
	second_start: Vector2,
	second_finish: Vector2,
) -> bool:
	var first_a := _orientation(first_start, first_finish, second_start)
	var first_b := _orientation(first_start, first_finish, second_finish)
	var second_a := _orientation(second_start, second_finish, first_start)
	var second_b := _orientation(second_start, second_finish, first_finish)
	if (
		(first_a > EPSILON and first_b < -EPSILON
			or first_a < -EPSILON and first_b > EPSILON)
		and (second_a > EPSILON and second_b < -EPSILON
			or second_a < -EPSILON and second_b > EPSILON)
	):
		return true
	return (
		(
			absf(first_a) <= EPSILON
			and _point_on_segment(second_start, first_start, first_finish)
		)
		or (
			absf(first_b) <= EPSILON
			and _point_on_segment(second_finish, first_start, first_finish)
		)
		or (
			absf(second_a) <= EPSILON
			and _point_on_segment(first_start, second_start, second_finish)
		)
		or (
			absf(second_b) <= EPSILON
			and _point_on_segment(first_finish, second_start, second_finish)
		)
	)


static func _orientation(start: Vector2, finish: Vector2, point: Vector2) -> float:
	return (finish - start).cross(point - start)


static func _point_on_segment(
	point: Vector2,
	start: Vector2,
	finish: Vector2,
) -> bool:
	return (
		point.x >= minf(start.x, finish.x) - EPSILON
		and point.x <= maxf(start.x, finish.x) + EPSILON
		and point.y >= minf(start.y, finish.y) - EPSILON
		and point.y <= maxf(start.y, finish.y) + EPSILON
	)
