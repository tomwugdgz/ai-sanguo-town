class_name TownIndoorPropAuthoring
extends SceneTree


const WORLD_SCALARS := preload(
	"res://world/data/town/TownWorldScalars.gd"
)
const SOURCE_DIR := "res://world/data/town/source"
const AUTHORING_PATH := SOURCE_DIR + "/indoor_prop_authoring.json"
const OUTPUT_PATH := SOURCE_DIR + "/props.json"
const ACTIVITY_SLOTS_PATH := SOURCE_DIR + "/activity_slots.json"
const ROOMS_ROOT := "res://world/maps/town/interiors/redesign_v2/rooms"
const GEOMETRY := preload(
	"res://world/maps/town/interiors/redesign_v2/common/InteriorAssetGeometry.gd"
)
const ROOM_GEOMETRY := preload(
	"res://world/maps/town/interiors/InteriorRoomGeometry.gd"
)
const MOVEMENT_CLEARANCE := preload(
	"res://world/data/town/TownIndoorMovementClearance.gd"
)
const LAYOUT_CELL_SIZE := 32
const NAVIGATION_CELL_SIZE := 16
const MAX_SUPPORTED_GEOMETRY_COORDINATE_PX := 1_000_000
const DIRECTIONS := ["down", "right", "up", "left"]
const PUBLIC_FOOTPOINT_ROOMS := [
	"cafe",
	"clinic",
	"dining_hall",
	"library",
	"town_hall",
]
const STRICT_ASSET_DEFINITION_ROOMS := [
	"cafe",
	"clinic",
	"dining_hall",
	"home_template_a",
	"home_template_b",
	"library",
	"town_hall",
	"workshop",
]


func _initialize() -> void:
	var result := build_document(AUTHORING_PATH)
	if not bool(result.get("ok", false)):
		for error_value in result.get("errors", []) as Array:
			push_error(str(error_value))
		quit(1)
		return
	if "--check-only" in OS.get_cmdline_user_args():
		print(
			"TOWN_INDOOR_PROP_AUTHORING_PASS: %d props / %d indoor spaces"
			% [
				(result.get("document", {}) as Dictionary).get("props", []).size(),
				int(result.get("indoorSpaceCount", 0)),
			]
		)
		quit(0)
		return
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入 %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(result.get("document", {}), "  ", true) + "\n")
	var synchronized_slots := _synchronized_activity_slots(
		_load_json(ACTIVITY_SLOTS_PATH),
		result.get("document", {}) as Dictionary,
	)
	if synchronized_slots.is_empty():
		push_error("无法根据室内安全锚点同步 activity_slots.json")
		quit(1)
		return
	var slot_file := FileAccess.open(ACTIVITY_SLOTS_PATH, FileAccess.WRITE)
	if slot_file == null:
		push_error("无法写入 %s" % ACTIVITY_SLOTS_PATH)
		quit(1)
		return
	slot_file.store_string(JSON.stringify(synchronized_slots, "  ", true) + "\n")
	print(
		"TOWN_INDOOR_PROP_AUTHORING_PASS: %d props / %d indoor spaces"
		% [
			(result.get("document", {}) as Dictionary).get("props", []).size(),
			int(result.get("indoorSpaceCount", 0)),
		]
	)
	quit(0)


static func _synchronized_activity_slots(
	slot_document: Dictionary,
	props_document: Dictionary,
) -> Dictionary:
	if slot_document.is_empty() or props_document.is_empty():
		return {}
	var props_by_name := {}
	for prop_value: Variant in props_document.get("props", []) as Array:
		var prop := prop_value as Dictionary
		props_by_name[String(prop.get("name", ""))] = prop
	var result := slot_document.duplicate(true)
	for slot_value: Variant in result.get("slots", []) as Array:
		var slot := slot_value as Dictionary
		if String(slot.get("targetType", "")) != "prop":
			continue
		var target := slot.get("target", {}) as Dictionary
		var prop_name := String(target.get("propName", ""))
		if not props_by_name.has(prop_name):
			continue
		var interaction := (
			(props_by_name[prop_name] as Dictionary).get("interaction", {})
			as Dictionary
		)
		var positions_by_anchor := {}
		var base_anchor_id := String(interaction.get("anchorId", ""))
		if not base_anchor_id.is_empty():
			positions_by_anchor[base_anchor_id] = (
				interaction.get("position", []) as Array
			).duplicate(true)
		for member_value: Variant in interaction.get("memberAnchors", []) as Array:
			var member := member_value as Dictionary
			positions_by_anchor[String(member.get("anchorId", ""))] = (
				member.get("position", []) as Array
			).duplicate(true)
		for member_value: Variant in slot.get("memberAnchors", []) as Array:
			var member := member_value as Dictionary
			var anchor_id := String(member.get("anchorId", ""))
			if positions_by_anchor.has(anchor_id):
				member["position"] = (
					positions_by_anchor[anchor_id] as Array
				).duplicate(true)
	return result


static func build_document(
	authoring_path: String = AUTHORING_PATH,
	layout_overrides: Dictionary = {},
	definition_overrides: Dictionary = {},
	geometry_overrides: Dictionary = {},
) -> Dictionary:
	var errors: Array[String] = []
	var source := _load_json(authoring_path)
	if source.is_empty():
		return {"ok": false, "errors": ["室内道具 authoring 源为空"]}
	if not _is_exact_integer(source.get("schemaVersion"), 1):
		errors.append("indoor_prop_authoring.schemaVersion 必须为 1")
	if str(source.get("worldId", "")) != "town":
		errors.append("indoor_prop_authoring.worldId 必须为 town")

	var spaces_document := _load_json(SOURCE_DIR + "/spaces.json")
	var places_document := _load_json(SOURCE_DIR + "/places.json")
	var regions_document := _load_json(SOURCE_DIR + "/indoor_perception_regions.json")
	var indoor_spaces := {}
	for value in spaces_document.get("spaces", []) as Array:
		var space := value as Dictionary
		if str(space.get("type", "")) == "室内":
			indoor_spaces[str(space.get("id", ""))] = space
	var places_by_name := {}
	for value in places_document.get("places", []) as Array:
		var place := value as Dictionary
		places_by_name[str(place.get("name", ""))] = place
	var regions_by_id := {}
	for value in regions_document.get("regions", []) as Array:
		var region := value as Dictionary
		regions_by_id[str(region.get("id", ""))] = region

	var props := (source.get("outdoorProps", []) as Array).duplicate(true)
	var indoor_navigation := []
	var seen_names := {}
	for value in props:
		var prop := value as Dictionary
		_register_unique(str(prop.get("name", "")), "道具中文名", seen_names, errors)
	var seen_spaces := {}
	for room_value in source.get("rooms", []) as Array:
		if not room_value is Dictionary:
			errors.append("rooms 中存在非对象记录")
			continue
		var room := room_value as Dictionary
		var room_id := str(room.get("roomId", ""))
		var template_room_id := str(room.get("templateRoomId", room_id))
		var space_id := str(room.get("spaceId", ""))
		var place_name := str(room.get("placeName", ""))
		var region_id := str(room.get("regionId", ""))
		_register_unique(space_id, "室内空间绑定", seen_spaces, errors)
		_validate_room_identity(
			room_id,
			space_id,
			place_name,
			region_id,
			indoor_spaces,
			places_by_name,
			regions_by_id,
			errors
		)
		var room_root := ROOMS_ROOT.path_join(template_room_id)
		var manifest := _load_json(room_root.path_join("furniture_manifest.json"))
		var geometry := _load_json(room_root.path_join("room_geometry.json"))
		if geometry_overrides.has(template_room_id):
			var geometry_override: Variant = geometry_overrides.get(template_room_id)
			geometry = (
				(geometry_override as Dictionary).duplicate(true)
				if geometry_override is Dictionary
				else {}
			)
		var layout_file := str(room.get("layoutFile", "layout.json"))
		var layout := _load_json(room_root.path_join(layout_file))
		if layout_overrides.has(template_room_id):
			var layout_override: Variant = layout_overrides.get(template_room_id)
			layout = (
				(layout_override as Dictionary).duplicate(true)
				if layout_override is Dictionary
				else {}
			)
		if manifest.is_empty() or geometry.is_empty() or layout.is_empty():
			errors.append("%s 缺少正式 manifest/geometry/layout" % room_id)
			continue
		if STRICT_ASSET_DEFINITION_ROOMS.has(template_room_id):
			var geometry_errors := ROOM_GEOMETRY.validate_geometry(geometry)
			if geometry.get("room_id") != template_room_id:
				geometry_errors.append("room_id 必须匹配当前房间身份")
			for geometry_error in geometry_errors:
				errors.append(
					"%s 房间几何无效：%s" % [room_id, geometry_error]
				)
			if not geometry_errors.is_empty():
				continue
		var room_props := room.get("props", []) as Array
		if room_props.is_empty() and str(room.get("emptyReason", "")).strip_edges().is_empty():
			errors.append("%s 没有道具时必须登记 emptyReason" % room_id)
		var definitions := _load_definitions(
			manifest,
			template_room_id,
			errors,
			definition_overrides,
		)
		if STRICT_ASSET_DEFINITION_ROOMS.has(template_room_id):
			var layout_errors := validate_layout(
				layout,
				template_room_id,
				definitions,
				PUBLIC_FOOTPOINT_ROOMS.has(template_room_id),
			)
			errors.append_array(layout_errors)
			if not layout_errors.is_empty():
				continue
		var instances := _instances_by_id(layout, errors)
		var floor_cells := _cell_set(geometry.get("floor_cells", []) as Array)
		var walkable_cells := _walkable_cell_set(
			floor_cells,
			geometry,
			instances,
			definitions,
			errors,
		)
		indoor_navigation.append({
			"spaceId": space_id,
			"placeName": place_name,
			"regionId": region_id,
			"roomId": room_id,
			"cellSize": NAVIGATION_CELL_SIZE,
			"walkableCells": _serialized_cells(walkable_cells),
		})
		for binding_value in room_props:
			if not binding_value is Dictionary:
				errors.append("%s.props 中存在非对象记录" % room_id)
				continue
			var binding := binding_value as Dictionary
			var prop := _build_indoor_prop(
				room_id,
				space_id,
				place_name,
				region_id,
				binding,
				instances,
				definitions,
				walkable_cells,
				errors
			)
			if prop.is_empty():
				continue
			_register_unique(str(prop.get("name", "")), "道具中文名", seen_names, errors)
			props.append(prop)

	for space_id_value in indoor_spaces:
		var space_id := str(space_id_value)
		if not seen_spaces.has(space_id):
			errors.append("缺少室内空间道具制作声明：%s" % space_id)
	if seen_spaces.size() != indoor_spaces.size():
		errors.append(
			"室内道具制作声明必须覆盖 %d 个空间，实际为 %d"
			% [indoor_spaces.size(), seen_spaces.size()]
		)
	_project_fixed_indoor_props(props, indoor_navigation, errors)
	props.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("name", "")) < str((right as Dictionary).get("name", ""))
	)
	indoor_navigation.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary).get("spaceId", "")) < str(
			(right as Dictionary).get("spaceId", "")
		)
	)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"indoorSpaceCount": indoor_spaces.size(),
		"document": {
			"schemaVersion": 1,
			"worldId": "town",
			"props": props,
			"indoorNavigation": indoor_navigation,
		},
	}


static func _project_fixed_indoor_props(
	props: Array,
	indoor_navigation: Array,
	errors: Array[String],
) -> void:
	var walkable_by_space := {}
	for navigation_value: Variant in indoor_navigation:
		var navigation := navigation_value as Dictionary
		walkable_by_space[String(navigation.get("spaceId", ""))] = _cell_set(
			navigation.get("walkableCells", []) as Array
		)
	for prop_value: Variant in props:
		var prop := prop_value as Dictionary
		var interaction := prop.get("interaction", {}) as Dictionary
		var space_id := String(interaction.get("spaceId", ""))
		if space_id == "town_outdoor" or not walkable_by_space.has(space_id):
			continue
		var walkable := walkable_by_space[space_id] as Dictionary
		var source_position := _point(interaction.get("position", []))
		var safe_position := _nearest_floor_center(source_position, walkable)
		if (
			not safe_position.is_finite()
			or source_position.distance_to(safe_position) > 64.0
		):
			errors.append(
				"%s 的固定场景锚点无法投影到碰撞安全位置"
				% String(prop.get("name", ""))
			)
			continue
		interaction["sourceAnchorPosition"] = _pair(source_position)
		interaction["position"] = _pair(safe_position)
		interaction["anchorSnappedToFloor"] = not source_position.is_equal_approx(
			safe_position
		)
		for member_value: Variant in interaction.get("memberAnchors", []) as Array:
			var member := member_value as Dictionary
			var member_source := _point(member.get("position", []))
			var member_safe := _nearest_floor_center(member_source, walkable)
			if (
				not member_safe.is_finite()
				or member_source.distance_to(member_safe) > 64.0
			):
				errors.append(
					"%s.%s 的固定场景成员锚点无法投影到碰撞安全位置"
					% [
						String(prop.get("name", "")),
						String(member.get("anchorId", "")),
					]
				)
				continue
			member["position"] = _pair(member_safe)


static func _validate_room_identity(
	room_id: String,
	space_id: String,
	place_name: String,
	region_id: String,
	indoor_spaces: Dictionary,
	places_by_name: Dictionary,
	regions_by_id: Dictionary,
	errors: Array[String],
) -> void:
	if room_id.is_empty():
		errors.append("roomId 不能为空")
	if not indoor_spaces.has(space_id):
		errors.append("%s 引用了不存在的室内空间：%s" % [room_id, space_id])
	if not places_by_name.has(place_name):
		errors.append("%s 引用了不存在的地点：%s" % [room_id, place_name])
	elif str((places_by_name[place_name] as Dictionary).get("spaceId", "")) != space_id:
		errors.append("%s 的地点与空间不一致" % room_id)
	if not regions_by_id.has(region_id):
		errors.append("%s 引用了不存在的室内感知区域：%s" % [room_id, region_id])
	else:
		var region := regions_by_id[region_id] as Dictionary
		if str(region.get("spaceId", "")) != space_id or str(region.get("placeName", "")) != place_name:
			errors.append("%s 的感知区域与地点/空间不一致" % room_id)


static func _build_indoor_prop(
	room_id: String,
	space_id: String,
	place_name: String,
	region_id: String,
	binding: Dictionary,
	instances: Dictionary,
	definitions: Dictionary,
	floor_cells: Dictionary,
	errors: Array[String],
) -> Dictionary:
	var prop_name := str(binding.get("name", "")).strip_edges()
	var instance_id := str(binding.get("instanceId", ""))
	var asset_id := str(binding.get("assetId", ""))
	var anchor_id := str(binding.get("anchorId", ""))
	if not instances.has(instance_id):
		errors.append("%s.%s 引用了不存在的布局实例：%s" % [room_id, prop_name, instance_id])
		return {}
	var instance := instances[instance_id] as Dictionary
	if str(instance.get("asset_id", "")) != asset_id:
		errors.append("%s.%s 的 instanceId/assetId 不匹配" % [room_id, prop_name])
		return {}
	if not definitions.has(asset_id):
		errors.append("%s.%s 缺少家具定义：%s" % [room_id, prop_name, asset_id])
		return {}
	var definition := definitions[asset_id] as Dictionary
	var source_anchor := {}
	for value in definition.get("interaction_anchor", []) as Array:
		var anchor := value as Dictionary
		if str(anchor.get("id", "")) == anchor_id:
			source_anchor = anchor
			break
	if source_anchor.is_empty():
		errors.append("%s.%s 缺少家具交互锚点：%s" % [room_id, prop_name, anchor_id])
		return {}
	var direction := str(instance.get("direction", "down"))
	var instance_position := _point(instance.get("position_px"))
	var local_anchor := GEOMETRY.rotate_point(
		_point(source_anchor.get("position_px")),
		direction
	)
	var source_anchor_position := instance_position + local_anchor
	# 家具锚点只是期望站位；正式执行点必须落到经过真实脚部碰撞
	# 净空检查的导航点，不能仅因它位于同一逻辑格就原样保留。
	var interaction_position := _nearest_floor_center(
		source_anchor_position,
		floor_cells,
	)
	var containing_cell := _floor_cell_for_point(interaction_position, floor_cells)
	var snap_distance := source_anchor_position.distance_to(interaction_position)
	if (
		containing_cell == Vector2i(2147483647, 2147483647)
		or snap_distance > float(binding.get("maximumAnchorSnapPx", 64.0))
	):
		errors.append(
			"%s.%s 的家具锚点无法投影到相邻可行走格：%s（距离 %.2f）"
			% [room_id, prop_name, str(source_anchor_position), snap_distance]
		)
		return {}
	var actions := _build_binding_actions(
		room_id,
		prop_name,
		binding,
		errors,
	)
	return {
		"name": prop_name,
		"placeName": place_name,
		"interaction": {
			"spaceId": space_id,
			"regionId": region_id,
			"position": _pair(interaction_position),
			"roomId": room_id,
			"instanceId": instance_id,
			"assetId": asset_id,
			"anchorId": anchor_id,
			"anchorKind": str(source_anchor.get("kind", "")),
			"actorFacing": GEOMETRY.rotate_facing(
				str(source_anchor.get("actor_facing", "")),
				direction,
			),
			"sourceAnchorPosition": _pair(source_anchor_position),
			"anchorSnappedToFloor": not source_anchor_position.is_equal_approx(interaction_position),
			"instancePosition": _pair(instance_position),
			"direction": direction,
		},
		"actions": actions,
	}


static func _build_binding_actions(
	room_id: String,
	prop_name: String,
	binding: Dictionary,
	errors: Array[String],
) -> Array:
	var authored_actions: Array = []
	if binding.get("actions") is Array:
		authored_actions = binding.get("actions") as Array
	else:
		authored_actions = [{
			"verb": binding.get("verb", ""),
			"durationMinutes": binding.get("durationMinutes"),
			"effects": binding.get("effects", {}),
		}]
	if authored_actions.is_empty():
		errors.append("%s.%s 至少需要一个动作" % [room_id, prop_name])
		return []
	var actions: Array = []
	var seen_verbs := {}
	for index in authored_actions.size():
		var action_value: Variant = authored_actions[index]
		if not action_value is Dictionary:
			errors.append(
				"%s.%s.actions[%d] 必须为对象"
				% [room_id, prop_name, index]
			)
			continue
		var action := action_value as Dictionary
		var verb := str(action.get("verb", "")).strip_edges()
		if verb.is_empty():
			errors.append(
				"%s.%s.actions[%d].verb 不能为空"
				% [room_id, prop_name, index]
			)
		elif seen_verbs.has(verb):
			errors.append("%s.%s 的动作词重复：%s" % [room_id, prop_name, verb])
		else:
			seen_verbs[verb] = true
		var duration_value: Variant = action.get("durationMinutes")
		var duration_is_valid := (
			_is_integer_number(duration_value)
			and int(duration_value) > 0
		)
		if not duration_is_valid:
			errors.append(
				"%s.%s.%s 的 durationMinutes 必须为正整数"
				% [room_id, prop_name, verb]
			)
		var effects_value: Variant = action.get("effects", {})
		if not effects_value is Dictionary:
			errors.append(
				"%s.%s.%s 的 effects 必须为对象"
				% [room_id, prop_name, verb]
			)
		actions.append({
			"verb": verb,
			"durationMinutes": (
				int(duration_value) if duration_is_valid else 0
			),
			"effects": (
				(effects_value as Dictionary).duplicate(true)
				if effects_value is Dictionary
				else {}
			),
		})
	return actions


static func _load_definitions(
	manifest: Dictionary,
	expected_room_id: String,
	errors: Array[String],
	definition_overrides: Dictionary = {},
) -> Dictionary:
	var result := {}
	var manifest_errors := validate_manifest(manifest, expected_room_id)
	errors.append_array(manifest_errors)
	if not manifest_errors.is_empty():
		return result
	for value: Variant in manifest.get("assets", []) as Array:
		var record := value as Dictionary
		var asset_id := record.get("asset_id") as String
		var definition := _load_json(record.get("definition_path") as String)
		var override_key := "%s/%s" % [expected_room_id, asset_id]
		if definition_overrides.has(override_key):
			var definition_override: Variant = definition_overrides.get(override_key)
			definition = (
				(definition_override as Dictionary).duplicate(true)
				if definition_override is Dictionary
				else {}
			)
		if definition.is_empty():
			errors.append("家具 manifest 无法加载：%s" % asset_id)
			continue
		if STRICT_ASSET_DEFINITION_ROOMS.has(expected_room_id):
			var definition_errors := GEOMETRY.validate_definition(
				definition,
				expected_room_id,
				asset_id,
			)
			for definition_error in definition_errors:
				errors.append(
					"%s/%s 家具定义无效：%s"
					% [expected_room_id, asset_id, definition_error]
				)
			if not definition_errors.is_empty():
				continue
		result[asset_id] = definition
	return result


static func validate_manifest(
	manifest: Dictionary,
	expected_room_id: String,
) -> Array[String]:
	var errors: Array[String] = []
	var manifest_keys := manifest.keys()
	manifest_keys.sort()
	if manifest_keys != ["assets", "room_id", "schema_version", "source_revision"]:
		errors.append("%s 家具 manifest 字段必须匹配封闭结构" % expected_room_id)
	if not _is_exact_integer(manifest.get("schema_version"), 1):
		errors.append("%s 家具 manifest.schema_version 必须为 1" % expected_room_id)
	if (
		not manifest.get("room_id") is String
		or manifest.get("room_id") != expected_room_id
	):
		errors.append("%s 家具 manifest.room_id 必须匹配房间身份" % expected_room_id)
	if (
		not manifest.get("source_revision") is String
		or str(manifest.get("source_revision")).strip_edges().is_empty()
	):
		errors.append("%s 家具 manifest.source_revision 必须为非空字符串" % expected_room_id)
	var assets_value: Variant = manifest.get("assets")
	if not assets_value is Array:
		errors.append("%s 家具 manifest.assets 必须为数组" % expected_room_id)
		return errors
	var seen_asset_ids := {}
	for index in (assets_value as Array).size():
		var value: Variant = (assets_value as Array)[index]
		if not value is Dictionary:
			errors.append("%s 家具 manifest.assets[%d] 必须为对象" % [expected_room_id, index])
			continue
		var record := value as Dictionary
		var record_keys := record.keys()
		record_keys.sort()
		if record_keys != ["asset_id", "definition_path"]:
			errors.append(
				"%s 家具 manifest.assets[%d] 字段必须匹配封闭结构"
				% [expected_room_id, index]
			)
		var asset_id_value: Variant = record.get("asset_id")
		var definition_path_value: Variant = record.get("definition_path")
		var asset_id := (
			asset_id_value as String
			if asset_id_value is String
			else ""
		)
		var definition_path := (
			definition_path_value as String
			if definition_path_value is String
			else ""
		)
		if asset_id.strip_edges().is_empty():
			errors.append(
				"%s 家具 manifest.assets[%d].asset_id 必须为非空字符串"
				% [expected_room_id, index]
			)
			continue
		if seen_asset_ids.has(asset_id):
			errors.append("%s 家具 manifest 资产身份重复：%s" % [expected_room_id, asset_id])
			continue
		seen_asset_ids[asset_id] = true
		if (
			definition_path.strip_edges().is_empty()
			or not definition_path.begins_with("res://")
		):
			errors.append(
				"%s 家具 manifest.assets[%d].definition_path 必须为 res:// 路径"
				% [expected_room_id, index]
			)
			continue
		var definition := _load_json(definition_path)
		if definition.is_empty():
			errors.append(
				"%s 家具 manifest.assets[%d] 无法加载定义：%s"
				% [expected_room_id, index, definition_path]
			)
			continue
		if (
			not definition.get("asset_id") is String
			or definition.get("asset_id") != asset_id
		):
			errors.append(
				"%s 家具 manifest.assets[%d] 的 definition.asset_id 必须匹配 %s"
				% [expected_room_id, index, asset_id]
			)
		if (
			not definition.get("room_id") is String
			or definition.get("room_id") != expected_room_id
		):
			errors.append(
				"%s 家具 manifest.assets[%d] 的 definition.room_id 必须匹配房间身份"
				% [expected_room_id, index]
			)
	return errors


static func validate_layout(
	layout: Dictionary,
	expected_room_id: String,
	definitions: Dictionary,
	require_grid_center: bool = true,
) -> Array[String]:
	var errors: Array[String] = []
	var layout_keys := layout.keys()
	layout_keys.sort()
	if layout_keys != [
		"instances",
		"layout_revision",
		"projection_revision",
		"room_id",
		"schema_version",
		"source_revision",
	]:
		errors.append("%s 布局字段必须匹配封闭结构" % expected_room_id)
	if not _is_exact_integer(layout.get("schema_version"), 2):
		errors.append("%s 布局 schema_version 必须为 2" % expected_room_id)
	if (
		not layout.get("source_revision") is String
		or str(layout.get("source_revision")).strip_edges().is_empty()
	):
		errors.append("%s 布局 source_revision 必须为非空字符串" % expected_room_id)
	if (
		not layout.get("projection_revision") is String
		or layout.get("projection_revision") != "interior_projection_v1"
	):
		errors.append(
			"%s 布局 projection_revision 必须为 interior_projection_v1"
			% expected_room_id
		)
	if (
		not _is_integer_number(layout.get("layout_revision"))
		or float(layout.get("layout_revision")) <= 0.0
	):
		errors.append("%s 布局 layout_revision 必须为正整数" % expected_room_id)
	if (
		not layout.get("room_id") is String
		or layout.get("room_id") != expected_room_id
	):
		errors.append("%s 布局 room_id 必须匹配房间身份" % expected_room_id)
	var instances_value: Variant = layout.get("instances")
	if not instances_value is Array:
		errors.append("%s 布局 instances 必须为数组" % expected_room_id)
		return errors
	var seen_instance_ids := {}
	for index in (instances_value as Array).size():
		var value: Variant = (instances_value as Array)[index]
		if not value is Dictionary:
			errors.append("%s 布局 instances[%d] 必须为对象" % [expected_room_id, index])
			continue
		var instance := value as Dictionary
		var instance_keys := instance.keys()
		instance_keys.sort()
		if instance_keys != ["asset_id", "direction", "instance_id", "position_px"]:
			errors.append(
				"%s 布局 instances[%d] 字段必须匹配封闭结构"
				% [expected_room_id, index]
			)
		var instance_id_value: Variant = instance.get("instance_id")
		var instance_id := (
			instance_id_value as String
			if instance_id_value is String
			else ""
		)
		if instance_id.strip_edges().is_empty():
			errors.append(
				"%s 布局 instances[%d].instance_id 必须为非空字符串"
				% [expected_room_id, index]
			)
		elif seen_instance_ids.has(instance_id):
			errors.append("%s 布局实例身份重复：%s" % [expected_room_id, instance_id])
		else:
			seen_instance_ids[instance_id] = true
		var asset_id_value: Variant = instance.get("asset_id")
		if (
			not asset_id_value is String
			or (asset_id_value as String).strip_edges().is_empty()
		):
			errors.append(
				"%s 布局 instances[%d].asset_id 必须为非空字符串"
				% [expected_room_id, index]
			)
		elif not definitions.has(asset_id_value):
			errors.append(
				"%s 布局 instances[%d] 引用未知家具：%s"
				% [expected_room_id, index, asset_id_value]
			)
		var direction_value: Variant = instance.get("direction")
		if not direction_value is String or not DIRECTIONS.has(direction_value):
			errors.append(
				"%s 布局 instances[%d].direction 必须使用封闭方向集合"
				% [expected_room_id, index]
			)
		var position_value: Variant = instance.get("position_px")
		if not position_value is Array or position_value.size() != 2:
			errors.append(
				"%s 布局 instances[%d].position_px 必须包含两个坐标"
				% [expected_room_id, index]
			)
			continue
		for coordinate: Variant in position_value as Array:
			if (
				not _is_integer_number(coordinate)
				or absf(float(coordinate)) > MAX_SUPPORTED_GEOMETRY_COORDINATE_PX
			):
				errors.append(
					"%s 布局 instances[%d].position_px 必须使用有限整数坐标"
					% [expected_room_id, index]
				)
				break
			if (
				require_grid_center
				and (int(coordinate) % 32 + 32) % 32 != 16
			):
				errors.append(
					"%s 布局 instances[%d].position_px 必须使用 32px 格中心整数坐标"
					% [expected_room_id, index]
				)
				break
	return errors


static func _instances_by_id(layout: Dictionary, errors: Array[String]) -> Dictionary:
	var result := {}
	for value in layout.get("instances", []) as Array:
		var instance := value as Dictionary
		var instance_id := str(instance.get("instance_id", ""))
		if instance_id.is_empty() or result.has(instance_id):
			errors.append("布局实例身份为空或重复：%s" % instance_id)
			continue
		result[instance_id] = instance
	return result


static func _cell_set(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		var cell := Vector2i(int(value[0]), int(value[1]))
		result[cell] = true
	return result


static func _serialized_cells(cells: Dictionary) -> Array:
	var result := []
	for cell_value in cells:
		var cell := cell_value as Vector2i
		result.append([cell.x, cell.y])
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_pair := left as Array
		var right_pair := right as Array
		return int(left_pair[1]) < int(right_pair[1]) or (
			int(left_pair[1]) == int(right_pair[1])
			and int(left_pair[0]) < int(right_pair[0])
		)
	)
	return result


static func _walkable_cell_set(
	floor_cells: Dictionary,
	geometry: Dictionary,
	instances: Dictionary,
	definitions: Dictionary,
	errors: Array[String],
) -> Dictionary:
	var furniture_polygons: Array[PackedVector2Array] = []
	for instance_id_value in instances:
		var instance_id := str(instance_id_value)
		var instance := instances[instance_id_value] as Dictionary
		var asset_id := str(instance.get("asset_id", ""))
		if not definitions.has(asset_id):
			errors.append("布局实例 %s 缺少家具定义：%s" % [instance_id, asset_id])
			continue
		var definition := definitions[asset_id] as Dictionary
		var direction := str(instance.get("direction", "down"))
		var instance_position := _point(instance.get("position_px"))
		for polygon in GEOMETRY.rotated_ground_contact_polygons(definition, direction):
			var translated := PackedVector2Array()
			for point in polygon:
				translated.append(point + instance_position)
			furniture_polygons.append(translated)
	var boundary_rects: Array[Rect2] = ROOM_GEOMETRY.get_boundary_collision_rects(
		geometry
	)
	var navigation_candidates := MOVEMENT_CLEARANCE.subdivide_cells(
		floor_cells,
		LAYOUT_CELL_SIZE,
		NAVIGATION_CELL_SIZE,
	)
	var safe_cells := MOVEMENT_CLEARANCE.filter_walkable_cells(
		navigation_candidates,
		NAVIGATION_CELL_SIZE,
		boundary_rects,
		furniture_polygons,
	)
	return MOVEMENT_CLEARANCE.retain_reachable_cells(
		safe_cells,
		NAVIGATION_CELL_SIZE,
		ROOM_GEOMETRY.get_primary_entry_point(geometry),
	)


static func _cells_overlapping_polygon(polygon: PackedVector2Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if polygon.size() < 3:
		return result
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var first := Vector2i(
		floori(bounds.position.x / LAYOUT_CELL_SIZE),
		floori(bounds.position.y / LAYOUT_CELL_SIZE)
	)
	var last := Vector2i(
		ceili(bounds.end.x / LAYOUT_CELL_SIZE) - 1,
		ceili(bounds.end.y / LAYOUT_CELL_SIZE) - 1
	)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var top_left := Vector2(x, y) * LAYOUT_CELL_SIZE
			var cell_polygon := PackedVector2Array([
				top_left,
				top_left + Vector2(LAYOUT_CELL_SIZE, 0.0),
				top_left + Vector2(LAYOUT_CELL_SIZE, LAYOUT_CELL_SIZE),
				top_left + Vector2(0.0, LAYOUT_CELL_SIZE),
			])
			for intersection in Geometry2D.intersect_polygons(polygon, cell_polygon):
				if _polygon_area(intersection) > 0.01:
					result.append(Vector2i(x, y))
					break
	return result


static func _polygon_area(points: PackedVector2Array) -> float:
	return WORLD_SCALARS.polygon_area(points)


static func _floor_cell_for_point(point: Vector2, floor_cells: Dictionary) -> Vector2i:
	var candidates: Array[Vector2i] = []
	var base := Vector2i(
		floori(point.x / NAVIGATION_CELL_SIZE),
		floori(point.y / NAVIGATION_CELL_SIZE),
	)
	for offset_y in [-1, 0]:
		for offset_x in [-1, 0]:
			var cell := base + Vector2i(offset_x, offset_y)
			if not floor_cells.has(cell):
				continue
			var rect := Rect2(
				Vector2(cell) * NAVIGATION_CELL_SIZE,
				Vector2.ONE * NAVIGATION_CELL_SIZE,
			)
			if rect.has_point(point):
				candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(2147483647, 2147483647)
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := (_cell_center(left) - point).length_squared()
		var right_distance := (_cell_center(right) - point).length_squared()
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
	return candidates[0]


static func _nearest_floor_center(point: Vector2, floor_cells: Dictionary) -> Vector2:
	var best := Vector2(INF, INF)
	var best_distance := INF
	for value in floor_cells:
		var center := _cell_center(value as Vector2i)
		var distance := center.distance_squared_to(point)
		if distance < best_distance:
			best = center
			best_distance = distance
		elif is_equal_approx(distance, best_distance):
			if center.y < best.y or (is_equal_approx(center.y, best.y) and center.x < best.x):
				best = center
	return best


static func _cell_center(cell: Vector2i) -> Vector2:
	return MOVEMENT_CLEARANCE.body_origin_for_cell(cell, NAVIGATION_CELL_SIZE)


static func _register_unique(
	value: String,
	label: String,
	seen: Dictionary,
	errors: Array[String],
) -> void:
	if value.is_empty():
		errors.append("%s 不能为空" % label)
	elif seen.has(value):
		errors.append("%s 重复：%s" % [label, value])
	else:
		seen[value] = true


static func _load_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


static func _point(value: Variant) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


static func _pair(point: Vector2) -> Array:
	return [int(roundf(point.x)), int(roundf(point.y))]


static func _is_integer_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == roundf(float(value))
	)


static func _is_exact_integer(value: Variant, expected: int) -> bool:
	return _is_integer_number(value) and float(value) == float(expected)
