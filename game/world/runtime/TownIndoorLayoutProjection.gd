extends RefCounted


const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const PATH_QUERY := preload(
	"res://world/data/town/TownIndoorPropPathQuery.gd"
)
const BODY_STATES := ["困", "饿", "累"]
const DIRECTIONS := ["down", "right", "up", "left"]
const CARDINAL_OFFSETS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP,
]


static func snapshot_for_space(data: Dictionary, space_id: String) -> Dictionary:
	var navigation := {}
	for value: Variant in data.get("indoorNavigation", []) as Array:
		var candidate := value as Dictionary
		if str(candidate.get("spaceId", "")) == space_id:
			navigation = candidate.duplicate(true)
			break
	if navigation.is_empty():
		return {}
	var props := []
	for value: Variant in data.get("props", []) as Array:
		var prop := value as Dictionary
		if str((prop.get("interaction", {}) as Dictionary).get("spaceId", "")) == space_id:
			props.append(prop.duplicate(true))
	props.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("name", "")) < str(
			(right as Dictionary).get("name", "")
		)
	)
	return {
		"spaceId": space_id,
		"placeName": str(navigation.get("placeName", "")),
		"regionId": str(navigation.get("regionId", "")),
		"roomId": str(navigation.get("roomId", "")),
		"navigation": navigation,
		"props": props,
	}


static func all_snapshots(data: Dictionary) -> Array:
	var result := []
	for value: Variant in data.get("indoorNavigation", []) as Array:
		var space_id := str((value as Dictionary).get("spaceId", ""))
		var snapshot := snapshot_for_space(data, space_id)
		if not snapshot.is_empty():
			result.append(snapshot)
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("spaceId", "")) < str(
			(right as Dictionary).get("spaceId", "")
		)
	)
	return result


static func validate(data: Dictionary, projection: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var space_id := str(projection.get("spaceId", "")).strip_edges()
	var place_name := str(projection.get("placeName", "")).strip_edges()
	var region_id := str(projection.get("regionId", "")).strip_edges()
	var room_id := str(projection.get("roomId", "")).strip_edges()
	var space := _record_by_key(data.get("mapSpaces", []) as Array, "id", space_id)
	var place := _record_by_key(data.get("places", []) as Array, "name", place_name)
	var region := _record_by_key(data.get("perceptionRegions", []) as Array, "id", region_id)
	var formal_navigation := _record_by_key(
		data.get("indoorNavigation", []) as Array,
		"spaceId",
		space_id,
	)
	if space.is_empty() or str(space.get("type", "")) != "室内":
		errors.append("布局投影必须引用正式室内空间：%s" % space_id)
	if place.is_empty() or str(place.get("spaceId", "")) != space_id:
		errors.append("布局投影地点与空间不一致：%s/%s" % [space_id, place_name])
	if (
		region.is_empty()
		or str(region.get("spaceId", "")) != space_id
		or str(region.get("placeName", "")) != place_name
	):
		errors.append("布局投影感知区域与地点不一致：%s" % region_id)
	var navigation_value: Variant = projection.get("navigation")
	if not navigation_value is Dictionary:
		errors.append("布局投影 navigation 必须为对象")
		return errors
	var navigation := navigation_value as Dictionary
	for key in ["spaceId", "placeName", "regionId"]:
		if str(navigation.get(key, "")) != str(projection.get(key, "")):
			errors.append("布局投影 navigation.%s 与投影身份不一致" % key)
	if room_id.is_empty() or str(navigation.get("roomId", "")) != room_id:
		errors.append("布局投影 roomId 与 navigation.roomId 不一致")
	if (
		formal_navigation.is_empty()
		or room_id != str(formal_navigation.get("roomId", "")).strip_edges()
	):
		errors.append("布局投影 roomId 与正式室内导航房间不一致")
	var cell_size_value: Variant = navigation.get("cellSize")
	var cell_size := int(cell_size_value) if _integer_number(cell_size_value) else 0
	if (
		cell_size <= 0
		or cell_size > 32
		or 32 % cell_size != 0
	):
		errors.append("布局投影必须使用 32px 网格的正整数约数")
	elif (
		not formal_navigation.is_empty()
		and cell_size != int(formal_navigation.get("cellSize", 0))
	):
		errors.append("布局投影导航网格尺寸必须与正式室内导航一致")
	var space_bounds := _rect_from_fields(space.get("bounds"))
	if space_bounds.size.x <= 0.0 or space_bounds.size.y <= 0.0:
		errors.append("布局投影正式室内空间缺少合法边界：%s" % space_id)
	var region_shape := region.get("shape", {}) as Dictionary
	var region_bounds := Rect2()
	if str(region_shape.get("type", "")) == "rect":
		region_bounds = _rect_from_fields(region_shape)
	if region_bounds.size.x <= 0.0 or region_bounds.size.y <= 0.0:
		errors.append("布局投影正式感知区域缺少合法矩形边界：%s" % region_id)
	_validate_walkable_cells(
		navigation,
		float(cell_size),
		space_bounds,
		region_bounds,
		errors,
	)
	_validate_connection_endpoints(data, space_id, navigation, errors)

	var props_value: Variant = projection.get("props")
	if not props_value is Array:
		errors.append("布局投影 props 必须为数组")
		return errors
	var reserved_names := {}
	for place_value: Variant in data.get("places", []) as Array:
		reserved_names[str((place_value as Dictionary).get("name", ""))] = true
	for prop_value: Variant in data.get("props", []) as Array:
		var prop := prop_value as Dictionary
		if str((prop.get("interaction", {}) as Dictionary).get("spaceId", "")) != space_id:
			reserved_names[str(prop.get("name", ""))] = true
	var instance_contracts := {}
	var anchor_keys := {}
	for index in (props_value as Array).size():
		var prop_value: Variant = (props_value as Array)[index]
		if not prop_value is Dictionary:
			errors.append("布局投影 props[%d] 必须为对象" % index)
			continue
		_validate_prop(
			prop_value as Dictionary,
			space_id,
			place_name,
			region_id,
			navigation,
			space_bounds,
			region_bounds,
			reserved_names,
			instance_contracts,
			anchor_keys,
			errors,
		)
	return errors


static func apply(data: Dictionary, projection: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	var normalized := _canonical_projection(projection)
	var space_id := str(normalized.get("spaceId", ""))
	var props := []
	for value: Variant in result.get("props", []) as Array:
		var prop := value as Dictionary
		if str((prop.get("interaction", {}) as Dictionary).get("spaceId", "")) != space_id:
			props.append(prop)
	for value: Variant in normalized.get("props", []) as Array:
		props.append((value as Dictionary).duplicate(true))
	props.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("name", "")) < str(
			(right as Dictionary).get("name", "")
		)
	)
	result["props"] = props
	var navigation_records := []
	for value: Variant in result.get("indoorNavigation", []) as Array:
		var navigation := value as Dictionary
		if str(navigation.get("spaceId", "")) != space_id:
			navigation_records.append(navigation)
	navigation_records.append((normalized.get("navigation", {}) as Dictionary).duplicate(true))
	navigation_records.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("spaceId", "")) < str(
			(right as Dictionary).get("spaceId", "")
		)
	)
	result["indoorNavigation"] = navigation_records
	return result


static func _canonical_projection(projection: Dictionary) -> Dictionary:
	var result := projection.duplicate(true)
	var navigation := result.get("navigation", {}) as Dictionary
	navigation["cellSize"] = _canonical_number(navigation.get("cellSize"))
	var cells := (navigation.get("walkableCells", []) as Array).duplicate(true)
	for cell_value: Variant in cells:
		var cell := cell_value as Array
		cell[0] = _canonical_number(cell[0])
		cell[1] = _canonical_number(cell[1])
	cells.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_pair := left as Array
		var right_pair := right as Array
		return int(left_pair[1]) < int(right_pair[1]) or (
			int(left_pair[1]) == int(right_pair[1])
			and int(left_pair[0]) < int(right_pair[0])
		)
	)
	navigation["walkableCells"] = cells
	result["navigation"] = navigation
	var props := (result.get("props", []) as Array).duplicate(true)
	for prop_value: Variant in props:
		var prop := prop_value as Dictionary
		var interaction := prop.get("interaction", {}) as Dictionary
		for key in ["instancePosition", "position", "sourceAnchorPosition"]:
			if interaction.get(key) is Array:
				var point := interaction.get(key) as Array
				point[0] = _canonical_number(point[0])
				point[1] = _canonical_number(point[1])
		var actions := (prop.get("actions", []) as Array).duplicate(true)
		for action_value: Variant in actions:
			var action := action_value as Dictionary
			action["durationMinutes"] = _canonical_number(
				action.get("durationMinutes")
			)
			var effects := action.get("effects", {}) as Dictionary
			for state_value: Variant in effects:
				effects[state_value] = _canonical_number(effects[state_value])
		actions.sort_custom(func(left: Variant, right: Variant) -> bool:
			return str((left as Dictionary).get("verb", "")) < str(
				(right as Dictionary).get("verb", "")
			)
		)
		prop["actions"] = actions
	props.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("name", "")) < str(
			(right as Dictionary).get("name", "")
		)
	)
	result["props"] = props
	return result


static func _validate_walkable_cells(
	navigation: Dictionary,
	cell_size: float,
	space_bounds: Rect2,
	region_bounds: Rect2,
	errors: PackedStringArray,
) -> void:
	var cells_value: Variant = navigation.get("walkableCells")
	if not cells_value is Array or (cells_value as Array).is_empty():
		errors.append("布局投影缺少可行走格")
		return
	var lookup := {}
	for index in (cells_value as Array).size():
		var pair: Variant = (cells_value as Array)[index]
		if (
			not _number_pair(pair)
			or not _integer_number((pair as Array)[0])
			or not _integer_number((pair as Array)[1])
		):
			errors.append("布局投影 walkableCells[%d] 无效" % index)
			continue
		var cell := Vector2i(int((pair as Array)[0]), int((pair as Array)[1]))
		if lookup.has(cell):
			errors.append("布局投影可行走格重复：%s" % str(cell))
		lookup[cell] = true
		var cell_bounds := Rect2(
			Vector2(cell) * cell_size,
			Vector2.ONE * cell_size,
		)
		if (
			space_bounds.size.x > 0.0
			and space_bounds.size.y > 0.0
			and not _rect_contains_rect(space_bounds, cell_bounds)
		):
			errors.append("布局投影可行走格不在正式室内空间边界：%s" % str(cell))
		if (
			region_bounds.size.x > 0.0
			and region_bounds.size.y > 0.0
			and not _rect_contains_rect(region_bounds, cell_bounds)
		):
			errors.append("布局投影可行走格不在正式感知区域边界：%s" % str(cell))
	if lookup.is_empty():
		return
	var seen := {lookup.keys()[0]: true}
	var queue: Array[Vector2i] = [lookup.keys()[0] as Vector2i]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for offset in CARDINAL_OFFSETS:
			var next: Vector2i = current + offset
			if lookup.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	if seen.size() != lookup.size():
		errors.append("布局投影可行走网格必须保持连通")


static func _validate_connection_endpoints(
	data: Dictionary,
	space_id: String,
	navigation: Dictionary,
	errors: PackedStringArray,
) -> void:
	var endpoint_count := 0
	for connection_value: Variant in data.get("connections", []) as Array:
		var connection := connection_value as Dictionary
		for key in ["from", "to"]:
			var endpoint := connection.get(key, {}) as Dictionary
			if str(endpoint.get("spaceId", "")) != space_id:
				continue
			endpoint_count += 1
			var position_value: Variant = endpoint.get("position")
			if not _number_point(position_value):
				errors.append(
					"布局投影正式连接端点坐标无效：%s/%s"
					% [str(connection.get("id", "")), key]
				)
				continue
			var position := _point_from_dictionary(position_value as Dictionary)
			if not PATH_QUERY.is_position_walkable(navigation, position):
				errors.append(
					"布局投影正式连接端点不在当前可行走网格：%s/%s"
					% [str(connection.get("id", "")), key]
				)
	if endpoint_count == 0:
		errors.append("布局投影室内空间没有正式连接端点：%s" % space_id)


static func _validate_prop(
	prop: Dictionary,
	space_id: String,
	place_name: String,
	region_id: String,
	navigation: Dictionary,
	space_bounds: Rect2,
	region_bounds: Rect2,
	reserved_names: Dictionary,
	instance_contracts: Dictionary,
	anchor_keys: Dictionary,
	errors: PackedStringArray,
) -> void:
	var prop_name := str(prop.get("name", "")).strip_edges()
	if prop_name.is_empty() or not _contains_cjk(prop_name):
		errors.append("动态道具必须有中文唯一名")
	elif reserved_names.has(prop_name):
		errors.append("动态道具名字重复：%s" % prop_name)
	else:
		reserved_names[prop_name] = true
	if str(prop.get("placeName", "")) != place_name:
		errors.append("动态道具 %s 不属于投影地点" % prop_name)
	var interaction_value: Variant = prop.get("interaction")
	if not interaction_value is Dictionary:
		errors.append("动态道具 %s 的 interaction 必须为对象" % prop_name)
		return
	var interaction := interaction_value as Dictionary
	if (
		str(interaction.get("spaceId", "")) != space_id
		or str(interaction.get("regionId", "")) != region_id
	):
		errors.append("动态道具 %s 的交互身份与投影不一致" % prop_name)
	var position: Variant = interaction.get("position")
	if not _number_pair(position):
		errors.append("动态道具 %s 的交互点必须是数值坐标" % prop_name)
	else:
		var interaction_position := Vector2(
			float((position as Array)[0]),
			float((position as Array)[1]),
		)
		if not space_bounds.has_point(interaction_position):
			errors.append("动态道具 %s 的交互点不在正式室内空间边界" % prop_name)
		if not region_bounds.has_point(interaction_position):
			errors.append("动态道具 %s 的交互点不在正式感知区域边界" % prop_name)
		if not PATH_QUERY.is_position_walkable(navigation, interaction_position):
			errors.append("动态道具 %s 的交互点不在当前可行走网格" % prop_name)
	if interaction.has("approachPolyline"):
		errors.append("动态室内道具 %s 不得保存固定 approachPolyline" % prop_name)
	var instance_id := str(interaction.get("instanceId", "")).strip_edges()
	if instance_id.is_empty():
		errors.append("动态道具 %s 的 instanceId 为空" % prop_name)
	else:
		var instance_contract := {
			"assetId": interaction.get("assetId"),
			"direction": interaction.get("direction"),
			"instancePosition": interaction.get("instancePosition"),
		}
		if (
			instance_contracts.has(instance_id)
			and instance_contracts.get(instance_id) != instance_contract
		):
			errors.append("动态道具 %s 的家具实例身份发生漂移" % prop_name)
		else:
			instance_contracts[instance_id] = instance_contract
	for key in ["roomId", "assetId", "anchorId", "direction"]:
		if str(interaction.get(key, "")).strip_edges().is_empty():
			errors.append("动态道具 %s 缺少 %s" % [prop_name, key])
	if str(interaction.get("roomId", "")) != str(navigation.get("roomId", "")):
		errors.append("动态道具 %s 的 roomId 与布局投影不一致" % prop_name)
	if str(interaction.get("direction", "")) not in DIRECTIONS:
		errors.append("动态道具 %s 的方向无效" % prop_name)
	for key in ["instancePosition", "sourceAnchorPosition"]:
		if not _number_pair(interaction.get(key)):
			errors.append("动态道具 %s 的 %s 必须是数值坐标" % [prop_name, key])
	if not interaction.get("anchorSnappedToFloor") is bool:
		errors.append("动态道具 %s 缺少锚点投影状态" % prop_name)
	var anchor_key := "%s/%s" % [instance_id, str(interaction.get("anchorId", ""))]
	if anchor_keys.has(anchor_key):
		errors.append("动态道具交互锚点重复：%s" % anchor_key)
	anchor_keys[anchor_key] = true
	var actions_value: Variant = prop.get("actions")
	if not actions_value is Array or (actions_value as Array).is_empty():
		errors.append("动态道具 %s 至少需要一个 Agent 动作" % prop_name)
		return
	var verbs := {}
	for action_value: Variant in actions_value as Array:
		if not action_value is Dictionary:
			errors.append("动态道具 %s 的动作必须为对象" % prop_name)
			continue
		var action := action_value as Dictionary
		var verb := str(action.get("verb", "")).strip_edges()
		if verb.is_empty() or verbs.has(verb):
			errors.append("动态道具 %s 的动作词为空或重复" % prop_name)
		verbs[verb] = true
		if not _integer_number(action.get("durationMinutes")) or int(action.get("durationMinutes", 0)) <= 0:
			errors.append("动态道具 %s 的动作时长必须为正整数" % prop_name)
		var effects_value: Variant = action.get("effects")
		if not effects_value is Dictionary:
			errors.append("动态道具 %s 的身体效果必须为对象" % prop_name)
			continue
		var effects := effects_value as Dictionary
		for state_value: Variant in effects:
			if str(state_value) not in BODY_STATES or not _integer_number(effects[state_value]):
				errors.append("动态道具 %s 的身体效果无效" % prop_name)


static func _record_by_key(values: Array, key: String, expected: String) -> Dictionary:
	for value: Variant in values:
		var record := value as Dictionary
		if str(record.get(key, "")) == expected:
			return record
	return {}


static func _number_pair(value: Variant) -> bool:
	return (
		value is Array
		and (value as Array).size() == 2
		and _number((value as Array)[0])
		and _number((value as Array)[1])
	)


static func _number_point(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var point := value as Dictionary
	return _number(point.get("x")) and _number(point.get("y"))


static func _number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
	)


static func _point_from_dictionary(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))


static func _rect_from_fields(value: Variant) -> Rect2:
	if not value is Dictionary:
		return Rect2()
	var fields := value as Dictionary
	for key in ["x", "y", "width", "height"]:
		if not _number(fields.get(key)):
			return Rect2()
	return Rect2(
		float(fields.get("x", 0.0)),
		float(fields.get("y", 0.0)),
		float(fields.get("width", 0.0)),
		float(fields.get("height", 0.0)),
	)


static func _rect_contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x
		and inner.position.y >= outer.position.y
		and inner.end.x <= outer.end.x
		and inner.end.y <= outer.end.y
	)


static func _integer_number(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


static func _canonical_number(value: Variant) -> Variant:
	if _integer_number(value):
		return int(value)
	return float(value) if _number(value) else value


static func _contains_cjk(text: String) -> bool:
	return WORLD_SCALARS.contains_cjk(text)
