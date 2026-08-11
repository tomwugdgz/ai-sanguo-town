extends RefCounted


const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const INDOOR_PATH_QUERY := preload(
	"res://world/data/town/TownIndoorPropPathQuery.gd"
)
const OUTDOOR_CLEARANCE := preload(
	"res://world/data/town/TownOutdoorMovementClearance.gd"
)
const OUTDOOR_COLLISION_PATH := "res://world/maps/town/generated/collision.json"

const BODY_STATES := ["困", "饿", "累"]
const REQUIRED_OUTDOOR_PROPS := {
	"社区花园长椅": "社区花园",
	"河岸公园长椅": "河岸公园",
}
const VALID_DIRECTIONS := ["down", "right", "up", "left"]


static func validate(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.is_empty():
		errors.append("World 静态数据为空")
		return errors
	var places_by_name := {}
	var spaces_by_id := {}
	var regions_by_id := {}
	for space_value in data.get("mapSpaces", []) as Array:
		var space := space_value as Dictionary
		spaces_by_id[str(space.get("id", ""))] = space
	for region_value in data.get("perceptionRegions", []) as Array:
		var region := region_value as Dictionary
		regions_by_id[str(region.get("id", ""))] = region
	for place_value in data.get("places", []) as Array:
		var place := place_value as Dictionary
		places_by_name[str(place.get("name", ""))] = place
	var navigation_by_space: Dictionary = _validate_indoor_navigation(
		data,
		spaces_by_id,
		places_by_name,
		errors,
	)
	var outdoor_collision_records := OUTDOOR_CLEARANCE.collision_records(
		_load_json_array(OUTDOOR_COLLISION_PATH)
	)
	if outdoor_collision_records.is_empty():
		errors.append("正式室外碰撞不可用，无法校验室外道具路径")
	var props_value: Variant = data.get("props")
	if not props_value is Array:
		errors.append("props 必须为数组")
		return errors
	var props := props_value as Array
	var props_by_name := {}
	var props_by_place := {}
	var indoor_anchor_keys := {}
	var interaction_position_owners := {}
	for index in props.size():
		var value: Variant = props[index]
		if not value is Dictionary:
			errors.append("props[%d] 必须为对象" % index)
			continue
		var prop := value as Dictionary
		var prop_name := str(prop.get("name", ""))
		if (
			prop.has("agentVisible")
			and not prop.get("agentVisible") is bool
		):
			errors.append(
				"道具 %s 的 agentVisible 必须为布尔值"
				% prop_name
			)
		var duplicate_prop_name := props_by_name.has(prop_name)
		_validate_unique_text(prop_name, "道具中文名", props_by_name, errors)
		if not prop_name.is_empty() and not duplicate_prop_name:
			props_by_name[prop_name] = prop
		if places_by_name.has(prop_name):
			errors.append("道具中文名不得与地点中文名重复：%s" % prop_name)
		if not _contains_cjk(prop_name):
			errors.append("道具名字必须包含中文：%s" % prop_name)
		var place_name := str(prop.get("placeName", ""))
		if not places_by_name.has(place_name):
			errors.append("道具 %s 引用了不存在的地点：%s" % [prop_name, place_name])
		else:
			var place_props := props_by_place.get(place_name, []) as Array
			place_props.append(prop)
			props_by_place[place_name] = place_props
		_validate_interaction(
			prop,
			place_name,
			places_by_name,
			spaces_by_id,
			regions_by_id,
			navigation_by_space,
			outdoor_collision_records,
			indoor_anchor_keys,
			errors
		)
		_validate_unique_interaction_position(
			prop,
			interaction_position_owners,
			errors,
		)
		var actions_value: Variant = prop.get("actions")
		if not actions_value is Array:
			errors.append("道具 %s 的 actions 必须为数组" % prop_name)
			continue
		var actions := actions_value as Array
		if actions.is_empty():
			errors.append("道具 %s 至少需要一个动作" % prop_name)
		var verbs := {}
		for action_index in actions.size():
			var action_value: Variant = actions[action_index]
			if not action_value is Dictionary:
				errors.append("道具 %s 的 actions[%d] 必须为对象" % [prop_name, action_index])
				continue
			var action := action_value as Dictionary
			var verb := str(action.get("verb", ""))
			_validate_unique_text(verb, "道具 %s 的动作词" % prop_name, verbs, errors)
			var duration: Variant = action.get("durationMinutes")
			if not _is_integer_number(duration) or int(duration) <= 0:
				errors.append("道具 %s 的动作 %s 必须使用正整数 durationMinutes" % [prop_name, verb])
			var effects_value: Variant = action.get("effects", {})
			if not effects_value is Dictionary:
				errors.append("道具 %s 的动作 %s 的 effects 必须为对象" % [prop_name, verb])
				continue
			var effects := effects_value as Dictionary
			for state_value in effects:
				var state := str(state_value)
				if state not in BODY_STATES:
					errors.append("道具 %s 的动作 %s 使用了未知身体状态：%s" % [prop_name, verb, state])
				if not _is_integer_number(effects[state_value]):
					errors.append("道具 %s 的动作 %s 的 %s 效果必须为整数" % [prop_name, verb, state])

	for prop_name_value in REQUIRED_OUTDOOR_PROPS:
		var prop_name := str(prop_name_value)
		if not props_by_name.has(prop_name):
			errors.append("缺少室外长椅道具：%s" % prop_name)
			continue
		var prop := props_by_name[prop_name] as Dictionary
		var expected_place := str(REQUIRED_OUTDOOR_PROPS[prop_name_value])
		if str(prop.get("placeName", "")) != expected_place:
			errors.append("道具 %s 必须属于 %s" % [prop_name, expected_place])
		_validate_bench_action(prop, errors)

	for place_name_value in places_by_name:
		var place_name := str(place_name_value)
		var place := places_by_name[place_name_value] as Dictionary
		var space_id := str(place.get("spaceId", ""))
		if space_id == "town_outdoor":
			continue
		var place_props := props_by_place.get(place_name, []) as Array
		if place_props.is_empty():
			errors.append("室内地点缺少可用道具：%s" % place_name)
			continue
		if str(place.get("type", "")) == "住家" and not _has_sleep_action(place_props):
			errors.append("住家必须提供睡觉动作：%s" % place_name)
	return errors


static func _validate_unique_interaction_position(
	prop: Dictionary,
	owners: Dictionary,
	errors: PackedStringArray,
) -> void:
	var interaction := prop.get("interaction", {}) as Dictionary
	var position: Variant = interaction.get("position")
	if not _is_number_pair(position):
		return
	var pair := position as Array
	var key := "%s|%.3f|%.3f" % [
		str(interaction.get("spaceId", "")),
		float(pair[0]),
		float(pair[1]),
	]
	var prop_name := str(prop.get("name", ""))
	if owners.has(key):
		errors.append(
			"道具交互位置重复：%s 与 %s"
			% [str(owners[key]), prop_name]
		)
	else:
		owners[key] = prop_name


static func _validate_interaction(
	prop: Dictionary,
	place_name: String,
	places_by_name: Dictionary,
	spaces_by_id: Dictionary,
	regions_by_id: Dictionary,
	navigation_by_space: Dictionary,
	outdoor_collision_records: Array[Dictionary],
	indoor_anchor_keys: Dictionary,
	errors: PackedStringArray,
) -> void:
	var prop_name := str(prop.get("name", ""))
	var interaction_value: Variant = prop.get("interaction")
	if not interaction_value is Dictionary:
		errors.append("道具 %s 缺少世界交互点" % prop_name)
		return
	var interaction := interaction_value as Dictionary
	var space_id := str(interaction.get("spaceId", ""))
	if not spaces_by_id.has(space_id):
		errors.append("道具 %s 的交互点引用了不存在的空间：%s" % [prop_name, space_id])
	var expected_space_id := ""
	if places_by_name.has(place_name):
		expected_space_id = str((places_by_name[place_name] as Dictionary).get("spaceId", ""))
	if space_id != expected_space_id:
		errors.append("道具 %s 的交互空间不属于地点 %s" % [prop_name, place_name])
	var region_id := str(interaction.get("regionId", ""))
	var region := regions_by_id.get(region_id, {}) as Dictionary
	if (
		region.is_empty()
		or str(region.get("placeName", "")) != place_name
		or str(region.get("spaceId", "")) != space_id
	):
		errors.append("道具 %s 的交互区域不属于 %s" % [prop_name, place_name])
	var position: Variant = interaction.get("position")
	if not _is_number_pair(position):
		errors.append("道具 %s 的 interaction.position 必须是数值坐标" % prop_name)
	elif not region.is_empty() and not _region_contains_point(region, position as Array):
		errors.append("道具 %s 的交互点不在感知区域 %s 内" % [prop_name, region_id])
	if space_id == "town_outdoor":
		_validate_outdoor_approach(
			prop_name,
			interaction,
			region,
			outdoor_collision_records,
			errors,
		)
	else:
		if not navigation_by_space.has(space_id):
			errors.append("室内道具 %s 缺少当前碰撞导航网格" % prop_name)
		elif _is_number_pair(position) and not INDOOR_PATH_QUERY.is_position_walkable(
			navigation_by_space[space_id] as Dictionary,
			Vector2(float((position as Array)[0]), float((position as Array)[1])),
		):
			errors.append("室内道具 %s 的交互点不在当前可行走网格" % prop_name)
		_validate_indoor_binding(prop_name, interaction, indoor_anchor_keys, errors)


static func _validate_outdoor_approach(
	prop_name: String,
	interaction: Dictionary,
	region: Dictionary,
	collision_records: Array[Dictionary],
	errors: PackedStringArray,
) -> void:
	var position: Variant = interaction.get("position")
	var polyline_value: Variant = interaction.get("approachPolyline")
	if not polyline_value is Array or (polyline_value as Array).size() < 2:
		errors.append("室外道具 %s 的 approachPolyline 至少需要两个坐标" % prop_name)
		return
	var previous := Vector2.INF
	for point_index in (polyline_value as Array).size():
		var point_value: Variant = (polyline_value as Array)[point_index]
		if not _is_number_pair(point_value):
			errors.append("道具 %s 的 approachPolyline[%d] 必须是数值坐标" % [prop_name, point_index])
			continue
		var point_pair := point_value as Array
		var point := Vector2(
			float(point_pair[0]),
			float(point_pair[1]),
		)
		if not region.is_empty() and not _region_contains_point(region, point_pair):
			errors.append("道具 %s 的 approachPolyline[%d] 不在交互区域内" % [prop_name, point_index])
		if (
			collision_records.is_empty()
			or not OUTDOOR_CLEARANCE.body_origin_is_safe(
				point,
				collision_records,
			)
		):
			errors.append("道具 %s 的 approachPolyline[%d] 不满足脚部碰撞净空" % [prop_name, point_index])
		if (
			previous.is_finite()
			and not collision_records.is_empty()
			and not OUTDOOR_CLEARANCE.body_segment_is_safe(
				previous,
				point,
				collision_records,
			)
		):
			errors.append("道具 %s 的 approachPolyline[%d] 路段穿过正式碰撞" % [prop_name, point_index])
		previous = point
	if _is_number_pair(position) and _is_number_pair((polyline_value as Array)[-1]):
		var position_pair := position as Array
		var last_pair := (polyline_value as Array)[-1] as Array
		if (
			float(position_pair[0]) != float(last_pair[0])
			or float(position_pair[1]) != float(last_pair[1])
		):
			errors.append("道具 %s 的交互点必须是 approachPolyline 终点" % prop_name)


static func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	return value as Array if value is Array else []


static func _validate_indoor_binding(
	prop_name: String,
	interaction: Dictionary,
	indoor_anchor_keys: Dictionary,
	errors: PackedStringArray,
) -> void:
	for key in [
		"roomId",
		"instanceId",
		"assetId",
		"anchorId",
		"anchorKind",
		"actorFacing",
		"direction",
	]:
		if str(interaction.get(key, "")).strip_edges().is_empty():
			errors.append("室内道具 %s 缺少 %s" % [prop_name, key])
	for key in ["instancePosition", "sourceAnchorPosition"]:
		if not _is_number_pair(interaction.get(key)):
			errors.append("室内道具 %s 的 %s 必须是数值坐标" % [prop_name, key])
	if not interaction.get("anchorSnappedToFloor") is bool:
		errors.append("室内道具 %s 的 anchorSnappedToFloor 必须为布尔值" % prop_name)
	var direction := str(interaction.get("direction", ""))
	if direction not in VALID_DIRECTIONS:
		errors.append("室内道具 %s 的 direction 无效：%s" % [prop_name, direction])
	var actor_facing := str(interaction.get("actorFacing", ""))
	if actor_facing not in VALID_DIRECTIONS:
		errors.append(
			"室内道具 %s 的 actorFacing 无效：%s"
			% [prop_name, actor_facing]
		)
	var anchor_key := "%s/%s/%s" % [
		str(interaction.get("spaceId", "")),
		str(interaction.get("instanceId", "")),
		str(interaction.get("anchorId", "")),
	]
	if indoor_anchor_keys.has(anchor_key):
		errors.append("室内道具交互锚点重复：%s" % anchor_key)
	else:
		indoor_anchor_keys[anchor_key] = true


static func _validate_indoor_navigation(
	data: Dictionary,
	spaces_by_id: Dictionary,
	places_by_name: Dictionary,
	errors: PackedStringArray,
) -> Dictionary:
	var result := {}
	var value: Variant = data.get("indoorNavigation")
	if not value is Array:
		errors.append("indoorNavigation 必须为数组")
		return result
	for index in (value as Array).size():
		var record_value: Variant = (value as Array)[index]
		if not record_value is Dictionary:
			errors.append("indoorNavigation[%d] 必须为对象" % index)
			continue
		var record := record_value as Dictionary
		var space_id := str(record.get("spaceId", ""))
		if result.has(space_id):
			errors.append("室内导航空间重复：%s" % space_id)
			continue
		var space := spaces_by_id.get(space_id, {}) as Dictionary
		if space.is_empty() or str(space.get("type", "")) != "室内":
			errors.append("室内导航引用了非室内空间：%s" % space_id)
			continue
		var place_name := str(record.get("placeName", ""))
		var place := places_by_name.get(place_name, {}) as Dictionary
		if place.is_empty() or str(place.get("spaceId", "")) != space_id:
			errors.append("室内导航地点与空间不一致：%s/%s" % [space_id, place_name])
		var cell_size_value: Variant = record.get("cellSize")
		var cell_size_is_valid := _is_integer_number(cell_size_value)
		var cell_size := int(cell_size_value) if cell_size_is_valid else 0
		if (
			not cell_size_is_valid
			or cell_size <= 0
			or cell_size > 32
			or 32 % cell_size != 0
		):
			errors.append("室内导航 %s 必须使用 32px 网格的正整数约数" % space_id)
		var cells_value: Variant = record.get("walkableCells")
		if not cells_value is Array or (cells_value as Array).is_empty():
			errors.append("室内导航 %s 缺少可行走格" % space_id)
			continue
		var cell_keys := {}
		var cell_lookup := {}
		for cell_index in (cells_value as Array).size():
			var cell_value: Variant = (cells_value as Array)[cell_index]
			if not _is_integer_pair(cell_value):
				errors.append("室内导航 %s 的 walkableCells[%d] 无效" % [space_id, cell_index])
				continue
			var key := "%d,%d" % [int((cell_value as Array)[0]), int((cell_value as Array)[1])]
			if cell_keys.has(key):
				errors.append("室内导航 %s 的可行走格重复：%s" % [space_id, key])
			cell_keys[key] = true
			cell_lookup[Vector2i(
				int((cell_value as Array)[0]),
				int((cell_value as Array)[1]),
			)] = true
		if not _cells_connected(cell_lookup):
			errors.append("室内导航 %s 的可行走网格不连通" % space_id)
		result[space_id] = record
	for space_id_value in spaces_by_id:
		var space_id := str(space_id_value)
		var space := spaces_by_id[space_id_value] as Dictionary
		if str(space.get("type", "")) == "室内" and not result.has(space_id):
			errors.append("缺少室内空间当前导航：%s" % space_id)
	return result


static func _cells_connected(cells: Dictionary) -> bool:
	if cells.is_empty():
		return false
	var start := cells.keys()[0] as Vector2i
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = current + offset
			if cells.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == cells.size()


static func _region_contains_point(region: Dictionary, point: Array) -> bool:
	var shape := region.get("shape", {}) as Dictionary
	var shape_type := str(shape.get("type", ""))
	var x := float(point[0])
	var y := float(point[1])
	if shape_type == "rect":
		return (
			x >= float(shape.get("x", 0.0))
			and y >= float(shape.get("y", 0.0))
			and x <= float(shape.get("x", 0.0)) + float(shape.get("width", 0.0))
			and y <= float(shape.get("y", 0.0)) + float(shape.get("height", 0.0))
		)
	if shape_type == "grid_cells":
		var cell_size_value: Variant = shape.get("cellSize")
		if not _is_integer_number(cell_size_value) or float(cell_size_value) <= 0.0:
			return false
		var cell_size := int(cell_size_value)
		var origin := shape.get("origin", {}) as Dictionary
		var cell := Vector2i(
			floori((x - float(origin.get("x", 0.0))) / float(cell_size)),
			floori((y - float(origin.get("y", 0.0))) / float(cell_size))
		)
		for cell_value in shape.get("cells", []) as Array:
			if (
				_is_integer_pair(cell_value)
				and int((cell_value as Array)[0]) == cell.x
				and int((cell_value as Array)[1]) == cell.y
			):
				return true
	return false


static func _has_sleep_action(props: Array) -> bool:
	for prop_value in props:
		for action_value in (prop_value as Dictionary).get("actions", []) as Array:
			if str((action_value as Dictionary).get("verb", "")) == "睡觉":
				return true
	return false


static func _validate_bench_action(prop: Dictionary, errors: PackedStringArray) -> void:
	var prop_name := str(prop.get("name", ""))
	var actions := prop.get("actions", []) as Array
	if actions.size() != 1:
		errors.append("室外长椅 %s 当前必须且只能提供一个动作" % prop_name)
		return
	var action := actions[0] as Dictionary
	if str(action.get("verb", "")) != "歇着":
		errors.append("室外长椅 %s 的动作词必须为歇着" % prop_name)
	if not _is_exact_number(action.get("durationMinutes"), 30.0):
		errors.append("室外长椅 %s 的歇着动作必须持续 30 游戏分钟" % prop_name)
	var effects := action.get("effects", {}) as Dictionary
	if effects.size() != 1 or not _is_exact_number(effects.get("累"), -1.0):
		errors.append("室外长椅 %s 的歇着效果必须且只能为累 -1" % prop_name)


static func _validate_unique_text(
	value: String,
	label: String,
	seen: Dictionary,
	errors: PackedStringArray
) -> void:
	if value.strip_edges().is_empty():
		errors.append("%s 不能为空" % label)
	elif seen.has(value):
		errors.append("%s 重复：%s" % [label, value])
	else:
		seen[value] = true


static func _contains_cjk(text: String) -> bool:
	return WORLD_SCALARS.contains_cjk(text)


static func _is_integer_number(value: Variant) -> bool:
	if not _is_finite_number(value):
		return false
	return float(value) == roundf(float(value))


static func _is_exact_number(value: Variant, expected: float) -> bool:
	return _is_finite_number(value) and float(value) == expected


static func _is_finite_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
	)


static func _is_number_pair(value: Variant) -> bool:
	return (
		value is Array
		and (value as Array).size() == 2
		and _is_finite_number((value as Array)[0])
		and _is_finite_number((value as Array)[1])
	)


static func _is_integer_pair(value: Variant) -> bool:
	return (
		value is Array
		and (value as Array).size() == 2
		and _is_integer_number((value as Array)[0])
		and _is_integer_number((value as Array)[1])
	)
