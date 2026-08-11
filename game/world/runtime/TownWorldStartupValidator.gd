class_name TownWorldStartupValidator
extends RefCounted


const DATA_VALIDATOR := preload("res://world/data/town/TownWorldDataValidator.gd")
const MOVEMENT_VALIDATOR := preload("res://world/data/town/TownWorldMovementValidator.gd")
const PROP_VALIDATOR := preload("res://world/data/town/TownWorldPropValidator.gd")
const OPENING_CONFIG := preload("res://world/runtime/TownWorldOpeningConfig.gd")
const ACTIVITY_SOURCE_DIR := "res://world/data/town/source"


static func validate(
	world_data: Dictionary,
	opening_config: Dictionary,
	require_world_ready := true,
) -> Dictionary:
	var issues: Array[Dictionary] = []
	var catalog_shape_errors := _catalog_shape_errors(world_data)
	_append_issues(
		issues,
		"world.shape",
		"WORLD_DATA_SHAPE_INVALID",
		catalog_shape_errors,
	)
	var foundation_errors := PackedStringArray()
	if catalog_shape_errors.is_empty():
		foundation_errors = DATA_VALIDATOR.validate_foundation(world_data)
		_append_issues(issues, "world.foundation", "WORLD_DATA_FOUNDATION_INVALID", foundation_errors)
	var data_error_count := issues.size()
	if catalog_shape_errors.is_empty() and foundation_errors.is_empty():
		_append_issues(
			issues,
			"world.outdoorPerception",
			"WORLD_DATA_OUTDOOR_PERCEPTION_INVALID",
			DATA_VALIDATOR.validate_outdoor_perception(world_data),
		)
		_append_issues(
			issues,
			"world.indoorPerception",
			"WORLD_DATA_INDOOR_PERCEPTION_INVALID",
			DATA_VALIDATOR.validate_indoor_perception(world_data),
		)
		_append_issues(
			issues,
			"world.movement",
			"WORLD_DATA_MOVEMENT_INVALID",
			MOVEMENT_VALIDATOR.validate(world_data),
		)
		_append_issues(
			issues,
			"world.props",
			"WORLD_DATA_PROPS_INVALID",
			PROP_VALIDATOR.validate(world_data),
		)
		_append_issues(
			issues,
			"world.activityIntegration",
			"WORLD_DATA_ACTIVITY_INTEGRATION_INVALID",
			DATA_VALIDATOR.validate_activity_integration_receipt(
				world_data,
				ACTIVITY_SOURCE_DIR,
			),
		)
		data_error_count = issues.size()

	var readiness_start := issues.size()
	if require_world_ready and catalog_shape_errors.is_empty():
		_append_readiness_issues(issues, world_data)
	var readiness_error_count := issues.size() - readiness_start

	var opening_start := issues.size()
	var opening_shape_errors := _opening_shape_errors(opening_config)
	_append_issues(issues, "opening.shape", "OPENING_CONFIG_SHAPE_INVALID", opening_shape_errors)
	if catalog_shape_errors.is_empty() and opening_shape_errors.is_empty():
		_append_issues(
			issues,
			"opening",
			"OPENING_CONFIG_INVALID",
			OPENING_CONFIG.validate(opening_config, world_data),
		)
	var opening_error_count := issues.size() - opening_start
	var errors: Array[String] = []
	for issue in issues:
		errors.append(String(issue.get("message", "")))

	var error_code := ""
	if data_error_count > 0:
		error_code = "WORLD_DATA_INVALID"
	elif readiness_error_count > 0:
		error_code = "WORLD_DATA_INCOMPLETE"
	elif opening_error_count > 0:
		error_code = "OPENING_CONFIG_INVALID"
	var content_status := {}
	if typeof(world_data.get("contentStatus")) == TYPE_DICTIONARY:
		content_status = world_data.get("contentStatus", {}) as Dictionary
	var pending_sections: Array = []
	if typeof(content_status.get("pendingSections")) == TYPE_ARRAY:
		pending_sections = (content_status.get("pendingSections", []) as Array).duplicate()
	var world_id := (
		world_data.get("worldId") as String
		if world_data.get("worldId") is String
		else ""
	)
	var data_version := 0
	if _is_integer_number(world_data.get("dataVersion")):
		data_version = int(world_data.get("dataVersion"))
	var content_stage := (
		content_status.get("stage") as String
		if content_status.get("stage") is String
		else ""
	)
	var content_ready := (
		content_status.get("worldReady") as bool
		if typeof(content_status.get("worldReady")) == TYPE_BOOL
		else false
	)
	return {
		"ok": issues.is_empty(),
		"errorCode": error_code,
		"retryable": false,
		"errors": errors,
		"issues": issues,
		"validationMode": "formal" if require_world_ready else "development",
		"worldId": world_id,
		"dataVersion": data_version,
		"contentStatus": {
			"stage": content_stage,
			"worldReady": content_ready,
			"pendingSections": pending_sections,
		},
	}


static func _append_readiness_issues(
	issues: Array[Dictionary],
	world_data: Dictionary,
) -> void:
	var content_status := world_data.get("contentStatus", {}) as Dictionary
	var stage := String(content_status.get("stage", ""))
	var world_ready := bool(content_status.get("worldReady", false))
	var pending_sections := content_status.get("pendingSections", []) as Array
	if stage != "world_ready":
		issues.append({
			"code": "WORLD_CONTENT_STAGE_NOT_READY",
			"scope": "world.contentStatus.stage",
			"subject": stage,
			"message": "正式世界内容阶段必须为 world_ready，当前为 %s" % stage,
		})
	if not world_ready:
		issues.append({
			"code": "WORLD_NOT_READY",
			"scope": "world.contentStatus.worldReady",
			"subject": "worldReady",
			"message": "正式世界数据尚未标记为 worldReady",
		})
	for section_value: Variant in pending_sections:
		var section := String(section_value)
		issues.append({
			"code": "WORLD_DATA_SECTION_PENDING",
			"scope": "world.contentStatus.pendingSections",
			"subject": section,
			"message": "正式世界数据仍缺少内容分区：%s" % section,
		})


static func _catalog_shape_errors(world_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if world_data.is_empty():
		errors.append("World 静态数据为空")
		return errors
	var allowed_top_level := [
		"schemaVersion", "dataVersion", "worldId", "contentStatus", "distance",
		"perceptionRange", "movementRules", "mapSpaces", "places", "perceptionGrid",
		"perceptionRegions", "connections", "placeObservationHotspots",
		"movementNetwork", "props", "indoorNavigation", "occupations",
		"activityDefinitions", "activitySlots", "scheduleTemplates",
		"activityIntegrationReceipt",
	]
	for key_value: Variant in world_data:
		if not key_value is String or not allowed_top_level.has(key_value):
			errors.append("世界数据包含未知顶层字段：%s" % str(key_value))
	if not _is_integer_number(world_data.get("schemaVersion")):
		errors.append("世界数据 schemaVersion 必须为整数")
	if not _is_integer_number(world_data.get("dataVersion")):
		errors.append("世界数据 dataVersion 必须为整数")
	if not world_data.get("worldId") is String or String(world_data.get("worldId")).strip_edges().is_empty():
		errors.append("世界数据 worldId 必须为非空文本")
	if typeof(world_data.get("perceptionRange")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(world_data.get("perceptionRange", NAN))):
		errors.append("世界数据 perceptionRange 必须为有限数字")
	for key in ["mapSpaces", "places", "perceptionRegions", "connections", "props"]:
		if typeof(world_data.get(key)) != TYPE_ARRAY:
			errors.append("世界数据 %s 必须为数组" % key)
	for key in [
		"occupations",
		"activityDefinitions",
		"activitySlots",
		"scheduleTemplates",
	]:
		if typeof(world_data.get(key)) != TYPE_ARRAY:
			errors.append("世界数据 %s 必须为数组" % key)
	for key in [
		"contentStatus",
		"distance",
		"movementRules",
		"perceptionGrid",
		"placeObservationHotspots",
		"movementNetwork",
	]:
		if typeof(world_data.get(key)) != TYPE_DICTIONARY:
			errors.append("世界数据 %s 必须为对象" % key)
	if typeof(world_data.get("activityIntegrationReceipt")) != TYPE_DICTIONARY:
		errors.append("世界数据 activityIntegrationReceipt 必须为对象")
	if typeof(world_data.get("contentStatus")) == TYPE_DICTIONARY:
		var content_status := world_data.get("contentStatus", {}) as Dictionary
		for key_value: Variant in content_status:
			if not key_value is String or not ["stage", "worldReady", "pendingSections"].has(key_value):
				errors.append("世界数据 contentStatus 包含未知字段：%s" % str(key_value))
		if not content_status.get("stage") is String:
			errors.append("世界数据 contentStatus.stage 必须为文本")
		if typeof(content_status.get("worldReady")) != TYPE_BOOL:
			errors.append("世界数据 contentStatus.worldReady 必须为布尔值")
		if typeof(content_status.get("pendingSections")) != TYPE_ARRAY:
			errors.append("世界数据 contentStatus.pendingSections 必须为数组")
		else:
			for section_value: Variant in content_status.get("pendingSections") as Array:
				if not section_value is String or String(section_value).strip_edges().is_empty():
					errors.append("世界数据 contentStatus.pendingSections 必须只包含非空文本")
	if typeof(world_data.get("movementNetwork")) == TYPE_DICTIONARY:
		var movement := world_data.get("movementNetwork", {}) as Dictionary
		for key_value: Variant in movement:
			if not key_value is String or not ["nodes", "edges", "arrivalNodes"].has(key_value):
				errors.append("世界数据 movementNetwork 包含未知字段：%s" % str(key_value))
		for key in ["nodes", "edges", "arrivalNodes"]:
			if typeof(movement.get(key)) != TYPE_ARRAY:
				errors.append("世界数据 movementNetwork.%s 必须为数组" % key)
	if (
		typeof(world_data.get("placeObservationHotspots"))
		== TYPE_DICTIONARY
	):
		var hotspots := (
			world_data.get("placeObservationHotspots", {}) as Dictionary
		)
		var connection_ids := {}
		var connections_value: Variant = world_data.get("connections")
		var connections := (
			connections_value as Array
			if connections_value is Array
			else []
		)
		for connection_value: Variant in connections:
			if not connection_value is Dictionary:
				continue
			var connection := connection_value as Dictionary
			var connection_id := String(connection.get("id", ""))
			if connection_id.is_empty():
				continue
			connection_ids[connection_id] = true
			if not hotspots.has(connection_id):
				errors.append(
					"世界连接 %s 缺少地点观察命中范围" % connection_id
				)
		for connection_id_value: Variant in hotspots:
			var connection_id := (
				connection_id_value as String
				if connection_id_value is String
				else ""
			)
			if not connection_ids.has(connection_id):
				errors.append(
					"地点观察命中范围引用未知连接：%s" % connection_id
				)
				continue
			var hotspot_value: Variant = hotspots.get(connection_id)
			if not hotspot_value is Dictionary:
				errors.append(
					"地点观察命中范围 %s 必须为对象" % connection_id
				)
				continue
			var hotspot := hotspot_value as Dictionary
			var offset_value: Variant = hotspot.get("offset")
			var size_value: Variant = hotspot.get("size")
			if not offset_value is Dictionary:
				errors.append(
					"地点观察命中范围 %s.offset 必须为对象" % connection_id
				)
			else:
				var offset := offset_value as Dictionary
				for key in ["x", "y"]:
					if not _is_finite_number(offset.get(key)):
						errors.append(
							"地点观察命中范围 %s.offset.%s 必须为有限数字"
							% [connection_id, key]
						)
			if not size_value is Dictionary:
				errors.append(
					"地点观察命中范围 %s.size 必须为对象" % connection_id
				)
			else:
				var size := size_value as Dictionary
				for key in ["width", "height"]:
					if (
						not _is_finite_number(size.get(key))
						or float(size.get(key, 0.0)) <= 0.0
					):
						errors.append(
							"地点观察命中范围 %s.size.%s 必须为正有限数字"
							% [connection_id, key]
						)
	return errors


static func _is_finite_number(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
	)


static func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and float(value) == floor(float(value))
	)


static func _opening_shape_errors(opening_config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["environment", "ownerAssignments", "playerAvatar"]:
		if typeof(opening_config.get(key)) != TYPE_DICTIONARY:
			errors.append("世界开局配置 %s 必须为对象" % key)
	if typeof(opening_config.get("residents")) != TYPE_ARRAY:
		errors.append("世界开局配置 residents 必须为数组")
	else:
		for index in (opening_config.get("residents", []) as Array).size():
			var resident_value: Variant = (opening_config.get("residents", []) as Array)[index]
			if typeof(resident_value) != TYPE_DICTIONARY:
				continue
			var resident := resident_value as Dictionary
			for key in ["attributes", "socialState", "worldState"]:
				if typeof(resident.get(key)) != TYPE_DICTIONARY:
					errors.append("世界开局配置 residents[%d].%s 必须为对象" % [index, key])
	if typeof(opening_config.get("playerAvatar")) == TYPE_DICTIONARY:
		var avatar := opening_config.get("playerAvatar", {}) as Dictionary
		if typeof(avatar.get("worldState")) != TYPE_DICTIONARY:
			errors.append("世界开局配置 playerAvatar.worldState 必须为对象")
	return errors


static func _append_issues(
	issues: Array[Dictionary],
	scope: String,
	code: String,
	errors: Variant,
) -> void:
	for message_value: Variant in errors:
		issues.append({
			"code": code,
			"scope": scope,
			"subject": "",
			"message": String(message_value),
		})
