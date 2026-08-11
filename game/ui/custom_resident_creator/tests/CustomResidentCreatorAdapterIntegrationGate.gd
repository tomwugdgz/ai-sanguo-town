extends SceneTree


const PAGE_SCENE := preload(
	"res://ui/custom_resident_creator/CustomResidentCreatorScreen.tscn"
)
const TownUiAdapter := preload(
	"res://world/presentation/ui/TownUiAdapter.gd"
)
const CandidatePool := preload(
	"res://world/presentation/session/TownCustomResidentCandidatePool.gd"
)
const CreatorService := preload(
	"res://world/presentation/session/TownCustomResidentCreatorService.gd"
)
const ResidentCatalog := preload(
	"res://world/presentation/session/TownResidentCatalog.gd"
)

const WORLD_PATH := "res://world/data/town/town_world.json"

var _failures: Array[String] = []
var _routed_intent := ""
var _routed_payload: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var catalog := ResidentCatalog.load_catalog() as Dictionary
	var original_catalog := catalog.duplicate(true)
	var pool := CandidatePool.new()
	_expect(
		bool((pool.configure(catalog, {"candidatePoolRevision": 11}) as Dictionary).get("ok", false)),
		"candidate pool configures",
	)
	var service := CreatorService.new()
	_expect(
		bool((service.configure(
			pool,
			catalog,
			_read_json(WORLD_PATH),
			{"draftId": "adapter-integration-gate"},
		) as Dictionary).get("ok", false)),
		"creator service configures",
	)

	var adapter := TownUiAdapter.new()
	root.add_child(adapter)
	adapter.set_custom_resident_creator_route_capabilities({"wardrobe": true})
	_expect(
		bool((adapter.bind_custom_resident_creator_service(service) as Dictionary).get("ok", false)),
		"formal TownUiAdapter binds the creator service",
	)

	var page := PAGE_SCENE.instantiate() as Control
	page.navigation_back_available = true
	root.add_child(page)
	page.bind_town_ui_adapter(adapter)
	page.intent_requested.connect(_on_page_intent_requested)
	await process_frame
	await process_frame
	_expect(
		String((page.current_view_model() as Dictionary).get("scope", ""))
		== "custom_resident_creator",
		"page receives creator ViewModel through TownUiAdapter",
	)
	var gender_option := page.find_child("GenderOption", true, false) as Button
	_expect(gender_option != null, "gender dropdown is present")
	if gender_option != null:
		gender_option.pressed.emit()
		await process_frame
		await process_frame
		var male_item := page.find_child("DropdownItem_1", true, false) as Button
		_expect(male_item != null, "gender dropdown renders the male choice")
		if male_item != null:
			male_item.pressed.emit()
			await process_frame
			await process_frame
	var workplace_option := page.find_child(
		"WorkplaceOption",
		true,
		false,
	) as Button
	_expect(
		workplace_option != null and workplace_option.disabled,
		"occupation-derived workplace is visible but cannot be edited",
	)
	var interest_option := page.find_child(
		"InterestOption",
		true,
		false,
	) as Button
	_expect(
		interest_option != null and not interest_option.disabled,
		"interest asset frame is available",
	)
	if interest_option != null:
		interest_option.pressed.emit()
		await process_frame
		await process_frame
		var catalog_interest := page.find_child(
			"InterestDropdownItem_0",
			true,
			false,
		) as Button
		_expect(catalog_interest != null, "interest popup renders catalog choices")
		if catalog_interest != null:
			catalog_interest.pressed.emit()
			await process_frame
			await process_frame
		var custom_edit := page.find_child(
			"CustomInterestEdit",
			true,
			false,
		) as LineEdit
		var add_custom := page.find_child(
			"AddCustomInterestButton",
			true,
			false,
		) as Button
		_expect(
			custom_edit != null and add_custom != null,
			"interest popup renders custom text input",
		)
		if custom_edit != null and add_custom != null:
			custom_edit.text = "收集旧邮戳"
			add_custom.pressed.emit()
			await process_frame
			await process_frame
	var interest_draft := (
		(service.get_view_model().get("data", {}) as Dictionary).get(
			"draft",
			{},
		) as Dictionary
	)
	_expect(
		(interest_draft.get("interests", []) as Array).size() == 1,
		"catalog interest selection reaches the creator service",
	)
	_expect(
		interest_draft.get("customInterests", []) == ["收集旧邮戳"],
		"custom interest text reaches the creator service",
	)

	var selection := {
		"hair": "side_swept_brown",
		"top": "navy_field_jacket",
		"bottom": "navy_field_jacket",
		"shoes": "navy_field_jacket",
	}
	_expect(
		bool((_dispatch(adapter, "custom_resident_creator.apply_wardrobe_result", {
			"selection": selection,
		}) as Dictionary).get("ok", false)),
		"formal wardrobe result returns through TownUiAdapter",
	)
	_expect(
		bool((_dispatch(adapter, "custom_resident_creator.update_fields", {
			"fields": {
				"name": "桥禾",
				"gender": "女",
				"age": 29,
				"desire": "把小镇里被忽略的故事记录下来",
				"personality": "细心温和，遇到疑点会认真求证",
				"speech": "语速平缓，会先说明观察到的事实",
			},
		}) as Dictionary).get("ok", false)),
		"complete draft updates through TownUiAdapter",
	)
	await process_frame
	await process_frame

	var create_button := page.find_child("CreateButton", true, false) as Button
	_expect(create_button != null and not create_button.disabled, "create action becomes operable")
	if create_button != null and not create_button.disabled:
		create_button.pressed.emit()
	await process_frame
	await process_frame
	_expect(
		_routed_intent == "custom_resident_creator.create",
		"page routes create intent to its host",
	)
	var dispatch_result := _routed_payload.get("dispatchResult", {}) as Dictionary
	_expect(bool(dispatch_result.get("ok", false)), "TownUiAdapter dispatch creates the candidate")
	_expect(
		int(dispatch_result.get("candidatePoolRevision", -1)) == 12,
		"candidate pool revision advances exactly once",
	)
	var handoff := dispatch_result.get("selectionHandoff", {}) as Dictionary
	var focused_resident_id := String(handoff.get("focusedResidentId", ""))
	_expect(not focused_resident_id.is_empty(), "selection handoff identifies the new focus")
	_expect(
		int(handoff.get("candidatePoolRevision", -1)) == 12,
		"selection handoff carries the advanced revision",
	)
	var projection := pool.get_resident_selection_projection() as Dictionary
	var selection_entries := projection.get("selectionEntries", []) as Array
	_expect(selection_entries.size() == 1, "new candidate enters the session selection projection")
	if selection_entries.size() == 1:
		_expect(
			String((selection_entries[0] as Dictionary).get("resident_id", ""))
			== focused_resident_id,
			"selection projection and focus use the same stable residentId",
		)
	_expect(catalog == original_catalog, "adapter route never mutates the 16 preset catalog")

	page.queue_free()
	adapter.bind_custom_resident_creator_service(null)
	adapter.queue_free()
	await process_frame
	if _failures.is_empty():
		print("CUSTOM_RESIDENT_CREATOR_ADAPTER_INTEGRATION_GATE: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("CUSTOM_RESIDENT_CREATOR_ADAPTER_INTEGRATION_GATE: %s" % failure)
		quit(1)


func _dispatch(adapter: Node, intent: String, extra: Dictionary) -> Dictionary:
	var view_model := adapter.call("get_view_model", "custom_resident_creator") as Dictionary
	var data := view_model.get("data", {}) as Dictionary
	var payload := {
		"revision": int(view_model.get("revision", 0)),
		"draftId": String(data.get("draftId", "")),
	}
	payload.merge(extra, true)
	return adapter.call("dispatch", intent, payload) as Dictionary


func _on_page_intent_requested(intent: String, payload: Dictionary) -> void:
	_routed_intent = intent
	_routed_payload = payload.duplicate(true)


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
