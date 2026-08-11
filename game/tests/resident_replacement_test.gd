extends "res://tests/support/TownWorldTestCase.gd"


const AGENT_SOUL_PROFILE := preload("res://agent/soul/AgentSoulProfile.gd")
const AGENT_CONTRACT := preload("res://agent/AgentContract.gd")
const GAME_FLOW_HOST := preload(
	"res://world/presentation/game_flow/GameFlowHost.gd"
)
const RESIDENT_REPLACEMENT := preload(
	"res://world/runtime/lifecycle/TownResidentReplacementAdmission.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := _build_data()
	var opening := _load_opening(data)
	var identities: Array[Dictionary] = []
	for resident_value: Variant in opening.get("residents", []) as Array:
		var resident := resident_value as Dictionary
		identities.append({
			"residentId": String(resident.get("residentId", "")),
			"residentName": String(
				(resident.get("attributes", {}) as Dictionary).get("name", "")
			),
		})
	var world := WORLD.new()
	var started := world.start(data, opening, identities) as Dictionary
	_expect(
		bool(started.get("ok", false)),
		"世界可以启动：%s" % JSON.stringify(started.get("errors", [])),
	)
	var deceased := identities[0]
	var deceased_name := String(deceased.get("residentName", ""))
	var death := world.confirm_resident_death(
		String(deceased.get("residentId", "")),
		"测试确认的死亡原因",
	) as Dictionary
	_expect(bool(death.get("ok", false)), "居民死亡可以确认")
	var death_event_id := String(
		(death.get("event", {}) as Dictionary).get("event_id", "")
	)
	var record := ((opening.get("residents", []) as Array)[0] as Dictionary).duplicate(true)
	record["residentId"] = String(deceased.get("residentId", ""))
	var attributes := (record.get("attributes", {}) as Dictionary).duplicate(true)
	attributes["name"] = "补位测试居民"
	record["attributes"] = attributes
	var host := GAME_FLOW_HOST.new()
	host.set("_pending_replacement_candidate", {
		"record": record.duplicate(true),
		"identity": {
			"residentId": String(deceased.get("residentId", "")),
			"residentName": "补位测试居民",
		},
		"binding": {
			"residentId": String(deceased.get("residentId", "")),
			"residentName": "补位测试居民",
		},
	})
	var editor_attributes := attributes.duplicate(true)
	editor_attributes["selectionSummary"] = "UI 列表摘要"
	host.call("_merge_replacement_editor_source", {
		"attributes": editor_attributes,
		"occupation": {},
		"presentation": {},
	})
	var merged_record := (
		(host.get("_pending_replacement_candidate") as Dictionary)
		.get("record", {}) as Dictionary
	)
	_expect(
		not (merged_record.get("attributes", {}) as Dictionary).has(
			"selectionSummary",
		),
		"入镇编辑不会把 UI 专用摘要带入正式居民资料",
	)
	host.free()
	var invalid_record := record.duplicate(true)
	var invalid_attributes := (
		invalid_record.get("attributes", {}) as Dictionary
	).duplicate(true)
	invalid_attributes["selectionSummary"] = "UI 列表摘要"
	invalid_record["attributes"] = invalid_attributes
	var invalid_preview := RESIDENT_REPLACEMENT.preview_agent_initialization(
		world,
		invalid_record,
		String(deceased.get("residentId", "")),
	) as Dictionary
	_expect(bool(invalid_preview.get("ok", false)), "World 可以无副作用预览补位 Agent 资料")
	_expect(
		not AGENT_CONTRACT.validate_initialization(
			invalid_preview.get("initialization", {}),
		).is_empty(),
		"Agent 预检会拒绝泄漏的 UI 字段",
	)
	_expect_equal(RESIDENT_REPLACEMENT.living_resident_count(world), 14, "预检失败前 World 不会提前补位")
	var same_name_record := record.duplicate(true)
	var same_name_attributes := (
		same_name_record.get("attributes", {}) as Dictionary
	).duplicate(true)
	same_name_attributes["name"] = deceased_name
	same_name_record["attributes"] = same_name_attributes
	var same_name_validation := RESIDENT_REPLACEMENT.validate(
		world,
		same_name_record,
		String(deceased.get("residentId", "")),
	) as Dictionary
	_expect(
		bool(same_name_validation.get("ok", false)),
		"补位可以复用已经死亡居民的姓名",
	)
	var admitted := RESIDENT_REPLACEMENT.admit(
		world,
		record,
		String(deceased.get("residentId", "")),
	) as Dictionary
	_expect(bool(admitted.get("ok", false)), "补位居民可以进入运行中的世界")
	_expect_equal(RESIDENT_REPLACEMENT.living_resident_count(world), 15, "补位后恢复十五名在世居民")
	_expect_equal(world.get_resident_ids().size(), 15, "新居民接替原有住宅席位")
	_expect_equal(
		(world.get_resident_state(String(deceased.get("residentId", ""))) as Dictionary).get("name"),
		"补位测试居民",
		"同一住宅席位已换成新居民身份",
	)
	_expect_equal(world.get_public_death_events(), [], "完成补位后不再重复处理同一死亡事件")
	var historical_death_name := ""
	for event_value: Variant in world.get_public_event_log():
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		if String(event.get("eventId", "")) == death_event_id:
			historical_death_name = String(event.get("residentName", ""))
			break
	_expect_equal(
		historical_death_name,
		deceased_name,
		"补位后的死亡历史仍保留死者姓名",
	)
	_expect(
		not world.get_agent_initialization_by_id(
			String(deceased.get("residentId", "")),
		).is_empty(),
		"新居民具备 Agent 初始化资料",
	)
	var save_result := world.create_save_snapshot() as Dictionary
	_expect(bool(save_result.get("ok", false)), "补位后的世界可以保存")
	var restored_opening := opening.duplicate(true)
	var restored_residents := (
		(restored_opening.get("residents", []) as Array).duplicate(true)
	)
	restored_residents[0] = record.duplicate(true)
	restored_opening["residents"] = restored_residents
	restored_opening["agentSoulProfiles"] = AGENT_SOUL_PROFILE.analyze_all(
		restored_residents,
	)
	var restored_identities := identities.duplicate(true)
	restored_identities[0] = {
		"residentId": String(deceased.get("residentId", "")),
		"residentName": "补位测试居民",
	}
	world.stop()
	var restored_world := WORLD.new()
	var restored := restored_world.restore_from_snapshot(
		data,
		restored_opening,
		(save_result.get("snapshot", {}) as Dictionary).duplicate(true),
		restored_identities,
	) as Dictionary
	_expect(
		bool(restored.get("ok", false)),
		"补位后的世界存档可以恢复：%s" % JSON.stringify(restored),
	)
	_expect_equal(RESIDENT_REPLACEMENT.living_resident_count(restored_world), 15, "读档后仍保持十五名在世居民")
	_expect_equal(
		(restored_world.get_resident_state(String(deceased.get("residentId", ""))) as Dictionary).get("name"),
		"补位测试居民",
		"读档后保留新居民身份",
	)
	restored_world.stop()
	_finish_suite("RESIDENT_REPLACEMENT_PASS")
