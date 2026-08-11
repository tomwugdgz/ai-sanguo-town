# 正式地图的通用室内壳。
# 具体底图、入口点和出口点由 TownBase.gd 的室内配置注入。
class_name InteriorRoom
extends Node2D

const FLOOR_PROFILES := preload("res://world/maps/town/interiors/InteriorFloorProfiles.gd")
const ROOM_GEOMETRY := preload("res://world/maps/town/interiors/InteriorRoomGeometry.gd")
const WALL_OCCLUSION_SCRIPT := preload("res://world/maps/town/interiors/InteriorWallOcclusion.gd")
const FURNITURE_RUNTIME_SCRIPT := preload(
	"res://world/maps/town/interiors/InteriorFurnitureRuntime.gd"
)

var _floor_profile_id := ""
var _geometry_path := ""
var _occlusion_path := ""
var _geometry_data: Dictionary = {}
var _navigation_grid_data: Dictionary = {}
var _base_navigation_grid_data: Dictionary = {}
var _walkable_cell_lookup := {}
var _geometry_debug_visible := false
var _wall_occlusion: InteriorWallOcclusion
var _furniture_manifest_path := ""
var _furniture_layout_path := ""
var _furniture_runtime: InteriorFurnitureRuntime


func configure(
	shell_path: String,
	entry_point: Vector2,
	exit_point: Vector2,
	geometry_path: String = "",
	occlusion_path: String = "",
	furniture_manifest_path: String = "",
	furniture_layout_path: String = ""
) -> void:
	var shell := get_node("RoomShell") as Sprite2D
	shell.texture = _load_texture(shell_path)
	if shell.texture == null:
		push_error("Interior shell is missing: %s" % shell_path)
	shell.position = Vector2.ZERO
	_geometry_path = geometry_path
	_geometry_data = ROOM_GEOMETRY.load_geometry(geometry_path)
	if not geometry_path.is_empty() and _geometry_data.is_empty():
		push_error("Interior room geometry is missing: %s" % geometry_path)
	if not _geometry_data.is_empty():
		shell.position = ROOM_GEOMETRY.shell_position(_geometry_data)
		entry_point = ROOM_GEOMETRY.get_primary_entry_point(_geometry_data)
		exit_point = ROOM_GEOMETRY.get_primary_exit_point(_geometry_data)
	(get_node("IndoorEntryPoint") as Marker2D).position = entry_point
	(get_node("IndoorExitPoint") as Marker2D).position = exit_point
	if not _geometry_data.is_empty():
		_floor_profile_id = str(_geometry_data.get("room_id", ""))
	else:
		_floor_profile_id = FLOOR_PROFILES.profile_id_from_shell_path(shell_path)
		if not FLOOR_PROFILES.has_profile(_floor_profile_id):
			push_error("Interior floor profile is missing: %s" % _floor_profile_id)
			return
	_build_wall_collision()
	if not _geometry_data.is_empty():
		_navigation_grid_data = ROOM_GEOMETRY.build_navigation_grid_data(
			_geometry_data,
			entry_point,
			exit_point
		)
	else:
		_navigation_grid_data = FLOOR_PROFILES.build_navigation_grid_data(
			_floor_profile_id,
			entry_point,
			exit_point
		)
	_base_navigation_grid_data = _navigation_grid_data.duplicate(true)
	_rebuild_navigation_lookup()
	_occlusion_path = _resolve_occlusion_path(geometry_path, occlusion_path)
	if not _occlusion_path.is_empty() and not _geometry_data.is_empty():
		_wall_occlusion = WALL_OCCLUSION_SCRIPT.new() as InteriorWallOcclusion
		add_child(_wall_occlusion)
		if not bool(_wall_occlusion.configure(shell,
			_geometry_data,
			_occlusion_path)):
			_wall_occlusion.queue_free()
			_wall_occlusion = null
	_furniture_manifest_path = furniture_manifest_path
	_furniture_layout_path = furniture_layout_path
	if not furniture_manifest_path.is_empty() and not furniture_layout_path.is_empty():
		_furniture_runtime = FURNITURE_RUNTIME_SCRIPT.new() as InteriorFurnitureRuntime
		_furniture_runtime.name = "FurnitureRuntime"
		add_child(_furniture_runtime)
		_furniture_runtime.connect(
			"layout_changed",
			_on_furniture_layout_changed
		)
		if not bool(_furniture_runtime.configure(furniture_manifest_path,
			furniture_layout_path)):
			push_error("Interior furniture layout could not be loaded: %s" % furniture_layout_path)
			for error in _furniture_runtime.get_errors() as PackedStringArray:
				push_error("Interior furniture: %s" % error)
		else:
			_apply_furniture_navigation_blockers()
	queue_redraw()


func get_floor_profile_id() -> String:
	return _floor_profile_id


func get_geometry_path() -> String:
	return _geometry_path


func get_occlusion_path() -> String:
	return _occlusion_path


func get_furniture_manifest_path() -> String:
	return _furniture_manifest_path


func get_furniture_layout_path() -> String:
	return _furniture_layout_path


func get_furniture_layout_snapshot() -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {}
	return _furniture_runtime.get_layout_snapshot() as Dictionary


func has_furniture_runtime() -> bool:
	return is_instance_valid(_furniture_runtime)


func get_furniture_instance_count() -> int:
	if not is_instance_valid(_furniture_runtime):
		return 0
	return int(_furniture_runtime.get_instance_count())


func get_furniture_collision_shape_count() -> int:
	if not is_instance_valid(_furniture_runtime):
		return 0
	return int(_furniture_runtime.get_collision_shape_count())


func get_furniture_errors() -> PackedStringArray:
	if not is_instance_valid(_furniture_runtime):
		return PackedStringArray()
	return _furniture_runtime.get_errors() as PackedStringArray


func set_furniture_layout_path(layout_path: String) -> bool:
	if layout_path.is_empty():
		return false
	if not is_instance_valid(_furniture_runtime):
		return false
	if layout_path == _furniture_layout_path:
		return true
	if not bool(_furniture_runtime.set_layout_path(layout_path)):
		return false
	_furniture_layout_path = layout_path
	return true


func apply_furniture_layout(layout: Dictionary) -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {
			"ok": false,
			"changed": false,
			"errors": PackedStringArray(["室内尚未加载家具运行时"]),
		}
	return _furniture_runtime.apply_layout(layout) as Dictionary


func upsert_furniture_instance(instance: Dictionary) -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {
			"ok": false,
			"changed": false,
			"errors": PackedStringArray(["室内尚未加载家具运行时"]),
		}
	return _furniture_runtime.upsert_instance(instance) as Dictionary


func remove_furniture_instance(instance_id: String) -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {
			"ok": false,
			"changed": false,
			"errors": PackedStringArray(["室内尚未加载家具运行时"]),
		}
	return _furniture_runtime.remove_instance(instance_id) as Dictionary


func create_world_layout_projection(base_projection: Dictionary) -> Dictionary:
	if not is_instance_valid(_furniture_runtime):
		return {
			"ok": false,
			"errors": PackedStringArray(["室内尚未加载家具运行时"]),
			"projection": {},
		}
	var navigation := (
		base_projection.get("navigation", {}) as Dictionary
	).duplicate(true)
	navigation["cellSize"] = int(_navigation_grid_data.get("cell_size", 0))
	navigation["walkableCells"] = (
		_navigation_grid_data.get("walkable_cells", []) as Array
	).duplicate(true)
	var identity := {
		"spaceId": str(base_projection.get("spaceId", "")),
		"placeName": str(base_projection.get("placeName", "")),
		"regionId": str(base_projection.get("regionId", "")),
		"roomId": str(base_projection.get("roomId", "")),
	}
	var prop_result := _furniture_runtime.create_agent_prop_projection(base_projection.get("props", []) as Array,
		identity,
		navigation.get("walkableCells", []) as Array,) as Dictionary
	if prop_result.get("ok") != true:
		return {
			"ok": false,
			"errors": prop_result.get("errors", PackedStringArray()),
			"projection": {},
		}
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"projection": {
			"spaceId": identity["spaceId"],
			"placeName": identity["placeName"],
			"regionId": identity["regionId"],
			"roomId": identity["roomId"],
			"navigation": navigation,
			"props": (prop_result.get("props", []) as Array).duplicate(true),
		},
	}


func uses_room_geometry() -> bool:
	return not _geometry_data.is_empty()


func get_navigation_grid_data() -> Dictionary:
	return _navigation_grid_data.duplicate(true)


func local_position_to_navigation_cell(local_position: Vector2) -> Vector2i:
	if not _geometry_data.is_empty():
		return ROOM_GEOMETRY.local_position_to_cell(local_position)
	return FLOOR_PROFILES.local_position_to_cell(local_position)


func is_local_position_walkable(local_position: Vector2) -> bool:
	return is_navigation_cell_walkable(local_position_to_navigation_cell(local_position))


func is_navigation_cell_walkable(cell: Vector2i) -> bool:
	return _walkable_cell_lookup.has(cell)


func get_walkable_navigation_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for offset in FLOOR_PROFILES.CARDINAL_OFFSETS:
		var candidate: Vector2i = cell + offset
		if is_navigation_cell_walkable(candidate):
			neighbors.append(candidate)
	return neighbors


func set_geometry_debug_visible(value: bool) -> void:
	_geometry_debug_visible = value
	if is_instance_valid(_wall_occlusion):
		_wall_occlusion.set_debug_visible(value)
	if is_instance_valid(_furniture_runtime):
		_furniture_runtime.set_debug_visible(value)
	queue_redraw()


func is_geometry_debug_visible() -> bool:
	return _geometry_debug_visible


func has_wall_occlusion() -> bool:
	return is_instance_valid(_wall_occlusion)


func get_floor_local_bounds() -> Rect2:
	if not _geometry_data.is_empty():
		return ROOM_GEOMETRY.get_floor_local_bounds(_geometry_data)
	var navigation_size := _navigation_grid_data.get("size", [0, 0]) as Array
	var origin_cell := _navigation_grid_data.get("origin_cell", [0, 0]) as Array
	if navigation_size.size() < 2 or origin_cell.size() < 2:
		return Rect2()
	return Rect2(
		Vector2(float(origin_cell[0]), float(origin_cell[1])) * FLOOR_PROFILES.GRID_SIZE,
		Vector2(float(navigation_size[0]), float(navigation_size[1])) * FLOOR_PROFILES.GRID_SIZE
	)


func get_shell_local_bounds() -> Rect2:
	if not _geometry_data.is_empty():
		return ROOM_GEOMETRY.get_shell_local_bounds(_geometry_data)
	var shell := get_node("RoomShell") as Sprite2D
	if shell.texture == null:
		return Rect2()
	var size := shell.texture.get_size()
	return Rect2(shell.position - size * 0.5, size)


func _draw() -> void:
	if not _geometry_debug_visible:
		return
	var grid_size := (
		ROOM_GEOMETRY.GRID_SIZE
		if not _geometry_data.is_empty()
		else FLOOR_PROFILES.GRID_SIZE
	)
	for serialized_cell in _navigation_grid_data.get("walkable_cells", []) as Array:
		var cell := Vector2i(int(serialized_cell[0]), int(serialized_cell[1]))
		var rect := Rect2(Vector2(cell) * grid_size, Vector2.ONE * grid_size)
		draw_rect(rect, Color(0.20, 0.82, 0.46, 0.18), true)
		draw_rect(rect, Color(0.28, 0.95, 0.60, 0.48), false, 1.0)
	var blocker_rects: Array[Rect2] = (
		ROOM_GEOMETRY.get_boundary_collision_rects(_geometry_data)
		if not _geometry_data.is_empty()
		else FLOOR_PROFILES.get_boundary_collision_rects(_floor_profile_id)
	)
	for rect in blocker_rects:
		draw_rect(rect, Color(0.93, 0.18, 0.22, 0.25), true)
		draw_rect(rect, Color(1.0, 0.28, 0.32, 0.72), false, 2.0)
	draw_circle(
		(get_node("IndoorEntryPoint") as Marker2D).position,
		11.0,
		Color(0.10, 0.88, 1.0, 0.95)
	)
	draw_circle(
		(get_node("IndoorExitPoint") as Marker2D).position,
		9.0,
		Color(1.0, 0.34, 0.72, 0.95)
	)


func _build_wall_collision() -> void:
	var wall := get_node("WallCollision") as StaticBody2D
	for child in wall.get_children():
		child.free()
	var index := 0
	var collision_rects: Array[Rect2] = (
		ROOM_GEOMETRY.get_boundary_collision_rects(_geometry_data)
		if not _geometry_data.is_empty()
		else FLOOR_PROFILES.get_boundary_collision_rects(_floor_profile_id)
	)
	for rect in collision_rects:
		var collision := CollisionShape2D.new()
		collision.name = "WallSection_%02d" % index
		collision.position = rect.get_center()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collision.shape = shape
		wall.add_child(collision)
		index += 1


func _rebuild_navigation_lookup() -> void:
	_walkable_cell_lookup.clear()
	for serialized_cell in _navigation_grid_data.get("walkable_cells", []) as Array:
		if serialized_cell is Array and serialized_cell.size() >= 2:
			_walkable_cell_lookup[Vector2i(
				int(serialized_cell[0]),
				int(serialized_cell[1])
			)] = true


func _apply_furniture_navigation_blockers() -> void:
	if not is_instance_valid(_furniture_runtime):
		return
	var blocked_lookup := {}
	for cell in _furniture_runtime.get_occupied_room_cells() as Array[Vector2i]:
		blocked_lookup[cell] = true
	var filtered_walkable: Array = []
	for serialized_cell in _navigation_grid_data.get("walkable_cells", []) as Array:
		var cell := Vector2i(int(serialized_cell[0]), int(serialized_cell[1]))
		if not blocked_lookup.has(cell):
			filtered_walkable.append(serialized_cell)
	var wall_cells: Array = (_navigation_grid_data.get("wall_cells", []) as Array).duplicate(true)
	var wall_lookup := {}
	for serialized_cell in wall_cells:
		wall_lookup["%d,%d" % [int(serialized_cell[0]), int(serialized_cell[1])]] = true
	for cell in blocked_lookup.keys():
		var typed_cell := cell as Vector2i
		var key := "%d,%d" % [typed_cell.x, typed_cell.y]
		if not wall_lookup.has(key):
			wall_cells.append([typed_cell.x, typed_cell.y])
	_navigation_grid_data["walkable_cells"] = filtered_walkable
	_navigation_grid_data["wall_cells"] = wall_cells
	_rebuild_navigation_lookup()


func _on_furniture_layout_changed(snapshot: Dictionary) -> void:
	_navigation_grid_data = _base_navigation_grid_data.duplicate(true)
	_apply_furniture_navigation_blockers()
	# 局部灯光、炉火和蒸汽必须读取家具资产中精确登记的效果锚点。
	# 在效果锚点合同落地前，不允许用家具根节点加猜测偏移生成视觉效果。
	@warning_ignore("unused_parameter")
	var _unused_snapshot := snapshot
	queue_redraw()


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _resolve_occlusion_path(geometry_path: String, configured_path: String) -> String:
	if not configured_path.is_empty():
		return configured_path
	if geometry_path.is_empty():
		return ""
	var sibling_path := geometry_path.get_base_dir().path_join("wall_occlusion.json")
	return sibling_path if FileAccess.file_exists(sibling_path) else ""
