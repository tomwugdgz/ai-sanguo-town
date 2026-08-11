extends RefCounted


const MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownIndoorMovementClearance.gd"
)
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP,
]
const INVALID_CELL := Vector2i(2147483647, 2147483647)
const SOURCE_CELL_SIZE := 32


static func find_path(
	navigation: Dictionary,
	start_position: Vector2,
	target_position: Vector2,
) -> Array[Vector2]:
	var contract := _validated_navigation(navigation)
	if contract.is_empty():
		return []
	var cell_size := float(contract.get("cellSize", 0))
	var walkable := contract.get("walkable", {}) as Dictionary
	var start_cell := _walkable_cell_for_point(start_position, cell_size, walkable)
	var target_cell := _walkable_cell_for_point(target_position, cell_size, walkable)
	if start_cell == INVALID_CELL or target_cell == INVALID_CELL:
		return []
	var cells := _simplified_cells(
		_shortest_cells(start_cell, target_cell, walkable)
	)
	if cells.is_empty():
		return []
	var points: Array[Vector2] = [start_position]
	for index in range(1, cells.size()):
		_append_distinct(
			points,
			MOVEMENT_CLEARANCE.body_origin_for_cell(cells[index], cell_size),
		)
	_append_distinct(points, target_position)
	return points


static func is_position_walkable(navigation: Dictionary, position: Vector2) -> bool:
	var contract := _validated_navigation(navigation)
	if contract.is_empty():
		return false
	var cell_size := float(contract.get("cellSize", 0))
	return _walkable_cell_for_point(
		position,
		cell_size,
		contract.get("walkable", {}) as Dictionary,
	) != INVALID_CELL


static func _validated_navigation(navigation: Dictionary) -> Dictionary:
	var cell_size_value: Variant = navigation.get("cellSize")
	if not _integer_number(cell_size_value):
		return {}
	var cell_size := int(cell_size_value)
	if (
		cell_size <= 0
		or cell_size > SOURCE_CELL_SIZE
		or SOURCE_CELL_SIZE % cell_size != 0
	):
		return {}
	var walkable := _walkable_lookup(navigation)
	if walkable.is_empty():
		return {}
	return {
		"cellSize": cell_size,
		"walkable": walkable,
	}


static func _shortest_cells(
	start_cell: Vector2i,
	target_cell: Vector2i,
	walkable: Dictionary,
) -> Array[Vector2i]:
	var previous := {start_cell: INVALID_CELL}
	var best_cost := {start_cell: 0}
	var open: Array[Dictionary] = []
	_heap_push(open, {
		"cell": start_cell,
		"cost": 0,
		"score": _manhattan(start_cell, target_cell),
	})
	while not open.is_empty():
		var record := _heap_pop(open)
		var current := record.get("cell", INVALID_CELL) as Vector2i
		var current_cost := int(record.get("cost", 0))
		if current_cost != int(best_cost.get(current, -1)):
			continue
		if current == target_cell:
			break
		for offset in CARDINAL_OFFSETS:
			var next: Vector2i = current + offset
			if not walkable.has(next):
				continue
			var next_cost := current_cost + 1
			if next_cost >= int(best_cost.get(next, 2147483647)):
				continue
			best_cost[next] = next_cost
			previous[next] = current
			_heap_push(open, {
				"cell": next,
				"cost": next_cost,
				"score": next_cost + _manhattan(next, target_cell),
			})
	if not previous.has(target_cell):
		return []
	var reversed: Array[Vector2i] = []
	var cell := target_cell
	while cell != INVALID_CELL:
		reversed.append(cell)
		cell = previous[cell] as Vector2i
	reversed.reverse()
	return reversed


static func _simplified_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= 2:
		return cells
	var result: Array[Vector2i] = [cells[0]]
	var direction := cells[1] - cells[0]
	for index in range(1, cells.size() - 1):
		var next_direction := cells[index + 1] - cells[index]
		if next_direction != direction:
			result.append(cells[index])
			direction = next_direction
	result.append(cells[-1])
	return result


static func _manhattan(left: Vector2i, right: Vector2i) -> int:
	return absi(left.x - right.x) + absi(left.y - right.y)


static func _heap_push(heap: Array[Dictionary], record: Dictionary) -> void:
	heap.append(record)
	var index := heap.size() - 1
	while index > 0:
		var parent := int((index - 1) / 2)
		if not _record_before(heap[index], heap[parent]):
			break
		var swap := heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent


static func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	var result := heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = tail
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var next := left
		if right < heap.size() and _record_before(heap[right], heap[left]):
			next = right
		if not _record_before(heap[next], heap[index]):
			break
		var swap := heap[index]
		heap[index] = heap[next]
		heap[next] = swap
		index = next
	return result


static func _record_before(left: Dictionary, right: Dictionary) -> bool:
	var left_score := int(left.get("score", 0))
	var right_score := int(right.get("score", 0))
	if left_score != right_score:
		return left_score < right_score
	var left_cost := int(left.get("cost", 0))
	var right_cost := int(right.get("cost", 0))
	if left_cost != right_cost:
		return left_cost > right_cost
	var left_cell := left.get("cell", INVALID_CELL) as Vector2i
	var right_cell := right.get("cell", INVALID_CELL) as Vector2i
	return left_cell.y < right_cell.y or (
		left_cell.y == right_cell.y and left_cell.x < right_cell.x
	)


static func _walkable_lookup(navigation: Dictionary) -> Dictionary:
	var result := {}
	var cells_value: Variant = navigation.get("walkableCells")
	if not cells_value is Array:
		return result
	for value: Variant in cells_value as Array:
		if not value is Array or (value as Array).size() != 2:
			return {}
		var pair := value as Array
		if not _integer_number(pair[0]) or not _integer_number(pair[1]):
			return {}
		var cell := Vector2i(int(pair[0]), int(pair[1]))
		if result.has(cell):
			return {}
		result[cell] = true
	return result


static func _integer_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number)


static func _walkable_cell_for_point(
	point: Vector2,
	cell_size: float,
	walkable: Dictionary,
) -> Vector2i:
	if not point.is_finite():
		return INVALID_CELL
	var base := Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
	var candidates: Array[Vector2i] = []
	for offset_y in [-1, 0]:
		for offset_x in [-1, 0]:
			var candidate := base + Vector2i(offset_x, offset_y)
			if not walkable.has(candidate):
				continue
			var rect := Rect2(Vector2(candidate) * cell_size, Vector2.ONE * cell_size)
			if rect.grow(0.01).has_point(point):
				candidates.append(candidate)
	if candidates.is_empty():
		return INVALID_CELL
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := MOVEMENT_CLEARANCE.body_origin_for_cell(
			left,
			cell_size,
		).distance_squared_to(point)
		var right_distance := MOVEMENT_CLEARANCE.body_origin_for_cell(
			right,
			cell_size,
		).distance_squared_to(point)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
	return candidates[0]


static func _append_distinct(points: Array[Vector2], point: Vector2) -> void:
	if points.is_empty() or not points[-1].is_equal_approx(point):
		points.append(point)
