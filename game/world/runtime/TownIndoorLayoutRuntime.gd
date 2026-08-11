extends RefCounted


signal layout_changed(change: Dictionary)

const LAYOUT_PROJECTION := preload(
	"res://world/runtime/TownIndoorLayoutProjection.gd"
)
const PATH_QUERY := preload(
	"res://world/data/town/TownIndoorPropPathQuery.gd"
)

var _started := false
var _base_world_data: Dictionary = {}
var _world_data: Dictionary = {}
var _layout_overrides: Dictionary = {}
var _revision := 0


func start(world_data: Dictionary) -> Dictionary:
	var snapshots := LAYOUT_PROJECTION.all_snapshots(world_data) as Array
	if snapshots.is_empty():
		return _failure(
			"INDOOR_LAYOUTS_MISSING",
			["World 数据没有可运行的室内布局"],
		)
	var errors := PackedStringArray()
	for snapshot_value: Variant in snapshots:
		var snapshot := snapshot_value as Dictionary
		for error in LAYOUT_PROJECTION.validate(world_data, snapshot) as PackedStringArray:
			errors.append(str(error))
	if not errors.is_empty():
		return _failure("INDOOR_LAYOUTS_INVALID", Array(errors))
	_base_world_data = world_data.duplicate(true)
	_world_data = world_data.duplicate(true)
	_layout_overrides.clear()
	_revision = 0
	_started = true
	return {
		"ok": true,
		"revision": _revision,
		"spaceCount": snapshots.size(),
	}


func is_started() -> bool:
	return _started


func get_revision() -> int:
	return _revision


func get_world_data() -> Dictionary:
	return _world_data.duplicate(true)


func get_layout_projection(space_id: String) -> Dictionary:
	if not _started:
		return {}
	return LAYOUT_PROJECTION.snapshot_for_space(
		_world_data,
		space_id.strip_edges(),
	) as Dictionary


func get_layout_overrides() -> Array:
	var result := []
	var space_ids: Array = _layout_overrides.keys()
	space_ids.sort()
	for space_id_value: Variant in space_ids:
		result.append(
			(_layout_overrides[space_id_value] as Dictionary).duplicate(true)
		)
	return result


func apply_layout(
	projection: Dictionary,
	editor_paused: bool,
	occupants: Array,
) -> Dictionary:
	if not _started:
		return _failure("INDOOR_LAYOUT_RUNTIME_NOT_STARTED", ["室内布局运行时尚未启动"])
	if not editor_paused:
		return _failure(
			"FURNITURE_EDITOR_NOT_PAUSED",
			["更新室内道具布局前必须暂停家具编辑状态"],
		)
	var space_id := str(projection.get("spaceId", "")).strip_edges()
	var errors := LAYOUT_PROJECTION.validate(
		_world_data,
		projection,
	) as PackedStringArray
	var affected_resident_ids := PackedStringArray()
	if errors.is_empty():
		_validate_connection_endpoints(
			space_id,
			projection,
			errors,
		)
	if errors.is_empty():
		_validate_occupants(
			space_id,
			projection,
			occupants,
			errors,
			affected_resident_ids,
		)
	if not errors.is_empty():
		return _failure(
			"INDOOR_LAYOUT_PROJECTION_INVALID",
			Array(errors),
			{"projection": get_layout_projection(space_id)},
		)
	affected_resident_ids.sort()
	var previous := get_layout_projection(space_id)
	var next_data := LAYOUT_PROJECTION.apply(
		_world_data,
		projection,
	) as Dictionary
	var next_projection := LAYOUT_PROJECTION.snapshot_for_space(
		next_data,
		space_id,
	) as Dictionary
	if next_projection == previous:
		return {
			"ok": true,
			"changed": false,
			"revision": _revision,
			"projection": previous,
			"invalidatedResidentIds": [],
		}
	_world_data = next_data
	var baseline := LAYOUT_PROJECTION.snapshot_for_space(
		_base_world_data,
		space_id,
	) as Dictionary
	if next_projection == baseline:
		_layout_overrides.erase(space_id)
	else:
		_layout_overrides[space_id] = next_projection.duplicate(true)
	_revision += 1
	var invalidated := []
	for resident_id in affected_resident_ids:
		invalidated.append(str(resident_id))
	var change := {
		"spaceId": space_id,
		"revision": _revision,
		"projection": next_projection.duplicate(true),
		"invalidatedResidentIds": invalidated,
	}
	layout_changed.emit(change.duplicate(true))
	return {
		"ok": true,
		"changed": true,
		"revision": _revision,
		"projection": next_projection,
		"invalidatedResidentIds": invalidated,
	}


func _validate_connection_endpoints(
	space_id: String,
	projection: Dictionary,
	errors: PackedStringArray,
) -> void:
	var navigation := projection.get("navigation", {}) as Dictionary
	for connection_value: Variant in _world_data.get("connections", []) as Array:
		if not connection_value is Dictionary:
			continue
		var connection := connection_value as Dictionary
		for endpoint_key in ["from", "to"]:
			var endpoint_value: Variant = connection.get(endpoint_key)
			if not endpoint_value is Dictionary:
				continue
			var endpoint := endpoint_value as Dictionary
			if str(endpoint.get("spaceId", "")) != space_id:
				continue
			var position_value: Variant = endpoint.get("position")
			if not position_value is Dictionary:
				errors.append(
					"室内连接 %s 的 %s 端缺少位置" % [
						str(connection.get("id", "")),
						endpoint_key,
					]
				)
				continue
			var position := position_value as Dictionary
			if (
				typeof(position.get("x")) not in [TYPE_INT, TYPE_FLOAT]
				or typeof(position.get("y")) not in [TYPE_INT, TYPE_FLOAT]
			):
				errors.append("室内连接 %s 的位置无效" % str(connection.get("id", "")))
				continue
			if not PATH_QUERY.is_position_walkable(
				navigation,
				Vector2(float(position.get("x")), float(position.get("y"))),
			):
				errors.append(
					"新布局会堵住室内连接 %s" % str(connection.get("id", ""))
				)


func _validate_occupants(
	space_id: String,
	projection: Dictionary,
	occupants: Array,
	errors: PackedStringArray,
	affected_resident_ids: PackedStringArray,
) -> void:
	var navigation := projection.get("navigation", {}) as Dictionary
	var seen_ids := {}
	for index in occupants.size():
		var occupant_value: Variant = occupants[index]
		if not occupant_value is Dictionary:
			errors.append("布局占用者 occupants[%d] 必须为对象" % index)
			continue
		var occupant := occupant_value as Dictionary
		var person_id := str(occupant.get("personId", "")).strip_edges()
		var kind := str(occupant.get("kind", "")).strip_edges()
		if person_id.is_empty() or seen_ids.has(person_id):
			errors.append("布局占用者 personId 为空或重复：%s" % person_id)
			continue
		seen_ids[person_id] = true
		if kind not in ["resident", "player"]:
			errors.append("布局占用者 %s 的 kind 无效" % person_id)
			continue
		if str(occupant.get("spaceId", "")) != space_id:
			continue
		var position_value: Variant = occupant.get("position")
		if not position_value is Vector2:
			errors.append("布局占用者 %s 缺少 Vector2 位置" % person_id)
			continue
		var current_action_value: Variant = occupant.get("currentAction", {})
		if not current_action_value is Dictionary:
			errors.append("布局占用者 %s 的 currentAction 必须为对象" % person_id)
			continue
		if not (current_action_value as Dictionary).is_empty():
			errors.append("人物 %s 正在该室内执行动作，不能改动布局" % person_id)
		if not PATH_QUERY.is_position_walkable(
			navigation,
			position_value as Vector2,
		):
			errors.append("新布局会把人物 %s 压在碰撞内" % person_id)
		if kind == "resident":
			affected_resident_ids.append(person_id)


func _failure(
	error_code: String,
	errors: Array,
	extra: Dictionary = {},
) -> Dictionary:
	var result := {
		"ok": false,
		"errorCode": error_code,
		"errors": errors.duplicate(true),
		"revision": _revision,
	}
	for key: Variant in extra:
		result[key] = extra[key]
	return result
