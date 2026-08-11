class_name TownResidentReplacementAdmission
extends RefCounted


const AGENT_SOUL_PROFILE := preload("res://agent/soul/AgentSoulProfile.gd")


static func world_absolute_minute(world) -> int:
	return (
		int(world._environment.get_absolute_minute())
		if world != null and world._environment != null
		else -1
	)


static func living_resident_count(world) -> int:
	if world == null:
		return 0
	var count := 0
	for resident_id: String in world._resident_order:
		count += 1 if world._resident_is_alive(resident_id) else 0
	return count


static func validate(
	world,
	record_value: Variant,
	replacement_for_resident_id: String,
) -> Dictionary:
	if not world._running or not record_value is Dictionary:
		return world._command_failure(
			"RESIDENT_REPLACEMENT_RECORD_INVALID",
			["新居民资料无效"],
		)
	var record := record_value as Dictionary
	var resident_id := String(record.get("residentId", "")).strip_edges()
	var attributes := record.get("attributes", {}) as Dictionary
	var resident_name := String(attributes.get("name", "")).strip_edges()
	var world_state := record.get("worldState", {}) as Dictionary
	var position_value: Variant = world_state.get("position", [])
	var name_owner_id := String(world._resident_id_by_name.get(resident_name, ""))
	if (
		resident_id.is_empty()
		or resident_name.is_empty()
		or resident_id != replacement_for_resident_id.strip_edges()
		or not world._residents.has(resident_id)
		or world._resident_lifecycle.is_alive(resident_id)
		or (
			world._resident_id_by_name.has(resident_name)
			and name_owner_id != resident_id
		)
		or not position_value is Array
		or (position_value as Array).size() != 2
		or String(world_state.get("spaceId", "")).strip_edges().is_empty()
		or String(world_state.get("regionId", "")).strip_edges().is_empty()
	):
		return world._command_failure(
			"RESIDENT_REPLACEMENT_RECORD_INVALID",
			["新居民缺少稳定身份、外观或入镇位置"],
		)
	return world._decorate_command_result({
		"ok": true,
		"changed": false,
		"residentId": resident_id,
		"residentName": resident_name,
	})


static func preview_agent_initialization(
	world,
	record_value: Variant,
	replacement_for_resident_id: String,
) -> Dictionary:
	var checked := validate(
		world,
		record_value,
		replacement_for_resident_id,
	) as Dictionary
	if not bool(checked.get("ok", false)):
		return checked
	var record := (record_value as Dictionary).duplicate(true)
	var resident_id := String(record.get("residentId", ""))
	var attributes := (record.get("attributes", {}) as Dictionary).duplicate(true)
	attributes.erase("appearance")
	var profiles := AGENT_SOUL_PROFILE.analyze_all([record]) as Dictionary
	var me := {
		"resident_id": resident_id,
		"attributes": attributes,
		"social_state": (
			record.get("socialState", {}) as Dictionary
		).duplicate(true),
	}
	var soul_profile := profiles.get(resident_id, {}) as Dictionary
	if not soul_profile.is_empty():
		me["soul_profile"] = soul_profile.duplicate(true)
	var others: Array[Dictionary] = []
	for other_id: String in world._resident_order:
		if other_id == resident_id:
			continue
		var other := world._residents[other_id] as Dictionary
		var other_attributes := other.get("attributes", {}) as Dictionary
		var other_social := other.get("socialState", {}) as Dictionary
		others.append({
			"resident_id": other_id,
			"name": String(other_attributes.get("name", "")),
			"gender": String(other_attributes.get("gender", "")),
			"age": int(other_attributes.get("age", 0)),
			"job": String(other_social.get("job", "")),
			"home": String(other_social.get("home", "")),
			"workplace": String(other_social.get("workplace", "")),
			"lifecycle_status": String(
				(world._resident_lifecycle.get_resident_state(
					other_id,
				) as Dictionary).get("status", "alive")
			),
		})
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"initialization": {
			"me": me,
			"residents": others,
			"places": world._agent_places(),
		},
	}


static func admit(
	world,
	record_value: Variant,
	replacement_for_resident_id: String,
) -> Dictionary:
	var checked := validate(
		world,
		record_value,
		replacement_for_resident_id,
	) as Dictionary
	if not bool(checked.get("ok", false)):
		return checked
	var record := (record_value as Dictionary).duplicate(true)
	var resident_id := String(record.get("residentId", "")).strip_edges()
	var attributes := record.get("attributes", {}) as Dictionary
	var resident_name := String(attributes.get("name", "")).strip_edges()
	var world_state := record.get("worldState", {}) as Dictionary
	var resident_runtime: Dictionary = world._resident_runtime(
		record,
		world_state,
		resident_id,
	) as Dictionary
	var old_name := String(world._resident_name_by_id.get(resident_id, ""))
	var lifecycle_result := world._resident_lifecycle.replace_deceased_resident(
		resident_id,
		resident_name,
		world._resident_home_anchor(world._world_data, resident_runtime),
	) as Dictionary
	if not bool(lifecycle_result.get("ok", false)):
		return world._decorate_command_result(lifecycle_result)
	var condition_result := world._resident_conditions.reset_resident(
		resident_id,
		world.RESTORE_PEOPLE.resident_condition_seed(resident_id),
	) as Dictionary
	if not bool(condition_result.get("ok", false)):
		return world._decorate_command_result(condition_result)
	var sleep_result := world._resident_sleep.reset_resident(
		resident_id,
	) as Dictionary
	if not bool(sleep_result.get("ok", false)):
		return world._decorate_command_result(sleep_result)
	world._residents[resident_id] = resident_runtime
	world._resident_id_by_name.erase(old_name)
	world._resident_name_by_id[resident_id] = resident_name
	world._resident_id_by_name[resident_name] = resident_id
	var opening_residents := world._opening.get("residents", []) as Array
	for resident_index in opening_residents.size():
		if String((opening_residents[resident_index] as Dictionary).get("residentId", "")) == resident_id:
			opening_residents[resident_index] = record.duplicate(true)
			break
	world._opening["residents"] = opening_residents
	world._opening["agentSoulProfiles"] = AGENT_SOUL_PROFILE.analyze_all(
		opening_residents,
	)
	world._activity_routines.erase(resident_id)
	world._staffing.rebuild(
		world._living_residents_for_staffing(),
		int(world._environment.get_absolute_minute()),
	)
	world._refresh_place_service_staffing()
	world.PERCEPTION_RUNTIME._refresh_perception(world, false)
	world._schedule_decision(resident_id, false)
	world._bump_world_revision(false)
	world._sync_staffing_matters()
	world._notify_world_revision()
	world._emit_resident_state_changed(resident_id)
	return world._decorate_command_result({
		"ok": true,
		"changed": true,
		"residentId": resident_id,
		"residentName": resident_name,
		"worldRevision": world._world_revision,
	})
