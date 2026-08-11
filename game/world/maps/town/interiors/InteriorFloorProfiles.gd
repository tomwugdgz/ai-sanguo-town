# 正式空房间的 32px 地板格配置。
# 墙体碰撞、室内寻路和后续家具占格都从这里读取，不能再各自手画边界。
extends RefCounted

const GRID_SIZE := 32.0
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i.DOWN,
	Vector2i.UP,
]

# 所有矩形均按底图可见地板保守内缩，并严格对齐 32px 格。
const PROFILE_FLOOR_RECTS := {
	"indoor_library_shell_v1": [
		Rect2(-256.0, -224.0, 672.0, 96.0),
		Rect2(-448.0, -128.0, 896.0, 384.0),
		Rect2(-64.0, 256.0, 128.0, 160.0),
	],
	"indoor_town_hall_shell_v1": [
		Rect2(-256.0, -256.0, 512.0, 128.0),
		Rect2(-544.0, -128.0, 1088.0, 384.0),
		Rect2(-96.0, 256.0, 192.0, 192.0),
	],
	"indoor_clinic_shell_v1": [
		Rect2(-224.0, -192.0, 448.0, 416.0),
		Rect2(-512.0, -96.0, 224.0, 320.0),
		Rect2(288.0, -96.0, 224.0, 320.0),
		Rect2(-512.0, 64.0, 1024.0, 160.0),
		Rect2(-128.0, 224.0, 256.0, 192.0),
	],
	"indoor_market_shell_v1": [
		Rect2(-352.0, -160.0, 704.0, 64.0),
		Rect2(-384.0, -96.0, 768.0, 64.0),
		Rect2(-416.0, -32.0, 832.0, 64.0),
		Rect2(-448.0, 32.0, 896.0, 192.0),
		Rect2(-128.0, 224.0, 256.0, 160.0),
	],
	"indoor_dining_hall_shell_v1": [
		# 北侧高台没有画楼梯，保持为不可走区域；只开放两侧短翼和主厅。
		Rect2(-480.0, -128.0, 960.0, 448.0),
		Rect2(-448.0, -192.0, 96.0, 64.0),
		Rect2(352.0, -192.0, 96.0, 64.0),
		Rect2(-96.0, 320.0, 192.0, 128.0),
	],
	"indoor_riverside_inn_shell_v1": [
		Rect2(-320.0, -224.0, 576.0, 32.0),
		Rect2(-512.0, -192.0, 768.0, 448.0),
		Rect2(320.0, -128.0, 192.0, 352.0),
		# 隔墙金色门位对应的固定通道。
		Rect2(256.0, 32.0, 64.0, 96.0),
		Rect2(-224.0, 256.0, 320.0, 160.0),
	],
	"indoor_workshop_shell_v1": [
		Rect2(-544.0, -160.0, 800.0, 480.0),
		Rect2(320.0, -128.0, 224.0, 448.0),
		Rect2(256.0, 32.0, 64.0, 96.0),
		Rect2(-192.0, 320.0, 224.0, 96.0),
	],
	"indoor_dock_warehouse_shell_v1": [
		Rect2(-512.0, -256.0, 768.0, 576.0),
		Rect2(320.0, -32.0, 224.0, 352.0),
		Rect2(256.0, 64.0, 64.0, 96.0),
		Rect2(-288.0, 320.0, 416.0, 128.0),
	],
	"indoor_home_template_a_shell_v1": [
		Rect2(-192.0, -192.0, 512.0, 128.0),
		Rect2(-320.0, -64.0, 640.0, 320.0),
		Rect2(-96.0, 256.0, 192.0, 160.0),
	],
	"indoor_home_template_b_shell_v1": [
		Rect2(-480.0, -160.0, 800.0, 96.0),
		Rect2(-480.0, -64.0, 992.0, 288.0),
		Rect2(-160.0, 224.0, 256.0, 192.0),
	],
}


static func profile_id_from_shell_path(shell_path: String) -> String:
	return shell_path.get_file().get_basename()


static func has_profile(profile_id: String) -> bool:
	return PROFILE_FLOOR_RECTS.has(profile_id)


static func is_point_walkable(profile_id: String, local_point: Vector2) -> bool:
	for rect_value in PROFILE_FLOOR_RECTS.get(profile_id, []) as Array:
		if (rect_value as Rect2).has_point(local_point):
			return true
	return false


static func is_cell_walkable(profile_id: String, cell: Vector2i) -> bool:
	return is_point_walkable(profile_id, cell_to_local_center(cell))


static func cell_to_local_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_SIZE


static func local_position_to_cell(local_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(local_position.x / GRID_SIZE),
		floori(local_position.y / GRID_SIZE)
	)


static func get_walkable_cells(profile_id: String) -> Array[Vector2i]:
	var lookup := {}
	for rect_value in PROFILE_FLOOR_RECTS.get(profile_id, []) as Array:
		var rect := rect_value as Rect2
		var min_cell := Vector2i(
			floori(rect.position.x / GRID_SIZE),
			floori(rect.position.y / GRID_SIZE)
		)
		var max_cell := Vector2i(
			ceili(rect.end.x / GRID_SIZE),
			ceili(rect.end.y / GRID_SIZE)
		)
		for y in range(min_cell.y, max_cell.y):
			for x in range(min_cell.x, max_cell.x):
				var cell := Vector2i(x, y)
				if is_cell_walkable(profile_id, cell):
					lookup[cell] = true
	var cells: Array[Vector2i] = []
	for cell_value in lookup.keys():
		cells.append(cell_value as Vector2i)
	_sort_cells(cells)
	return cells


static func get_boundary_blocker_cells(profile_id: String) -> Array[Vector2i]:
	var blocker_lookup := {}
	for floor_cell in get_walkable_cells(profile_id):
		for offset in CARDINAL_OFFSETS:
			var candidate: Vector2i = floor_cell + offset
			if not is_cell_walkable(profile_id, candidate):
				blocker_lookup[candidate] = true
	var blockers: Array[Vector2i] = []
	for cell_value in blocker_lookup.keys():
		blockers.append(cell_value as Vector2i)
	_sort_cells(blockers)
	return blockers


static func get_boundary_collision_rects(profile_id: String) -> Array[Rect2]:
	# 把相邻墙格合并成矩形，保持转角精度，同时避免每间房创建上百个物理节点。
	var remaining := {}
	var sorted_cells := get_boundary_blocker_cells(profile_id)
	for cell in sorted_cells:
		remaining[cell] = true
	var collision_rects: Array[Rect2] = []
	for start in sorted_cells:
		if not remaining.has(start):
			continue
		var width := 1
		while remaining.has(start + Vector2i(width, 0)):
			width += 1
		var height := 1
		while _row_run_exists(remaining, start + Vector2i(0, height), width):
			height += 1
		for y in range(height):
			for x in range(width):
				remaining.erase(start + Vector2i(x, y))
		collision_rects.append(Rect2(
			Vector2(start) * GRID_SIZE,
			Vector2(width, height) * GRID_SIZE
		))
	return collision_rects


static func build_navigation_grid_data(
	profile_id: String,
	entry_point: Vector2,
	exit_point: Vector2
) -> Dictionary:
	var walkable_cells := get_walkable_cells(profile_id)
	if walkable_cells.is_empty():
		return {}
	var min_cell := walkable_cells[0]
	var max_cell := walkable_cells[0]
	var walkable_lookup := {}
	var serialized_walkable: Array = []
	for cell in walkable_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
		walkable_lookup[cell] = true
		serialized_walkable.append([cell.x, cell.y])
	var wall_cells: Array = []
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y)
			if not walkable_lookup.has(cell):
				wall_cells.append([cell.x, cell.y])
	var entry_cell := local_position_to_cell(entry_point)
	var exit_cell := local_position_to_cell(exit_point)
	return {
		"revision": 1,
		"profile_id": profile_id,
		"cell_size": int(GRID_SIZE),
		"origin_cell": [min_cell.x, min_cell.y],
		"size": [max_cell.x - min_cell.x + 1, max_cell.y - min_cell.y + 1],
		"entry_cell": [entry_cell.x, entry_cell.y],
		"exit_cell": [exit_cell.x, exit_cell.y],
		"walkable_cells": serialized_walkable,
		"wall_cells": wall_cells,
		"neighbor_mode": "cardinal_4",
	}


static func _row_run_exists(lookup: Dictionary, start: Vector2i, width: int) -> bool:
	for x in range(width):
		if not lookup.has(start + Vector2i(x, 0)):
			return false
	return true


static func _sort_cells(cells: Array[Vector2i]) -> void:
	cells.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
