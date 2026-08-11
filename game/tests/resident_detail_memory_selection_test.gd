extends SceneTree


const SCREEN_SCENE := preload("res://ui/resident_detail/ResidentDetailScreen.tscn")
const FIXTURE_PATH := "res://ui/resident_detail/mock/resident_detail_view_models_mock.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	if not parsed is Dictionary:
		_fail("居民详情 fixture 解析失败")
		return
	var view_model := _find_fixture(parsed as Dictionary, "memories_ready_idle")
	if view_model.is_empty():
		_fail("缺少 memories_ready_idle fixture")
		return
	var screen := SCREEN_SCENE.instantiate() as ResidentDetailScreen
	get_root().add_child(screen)
	await process_frame
	view_model["revision"] = 1
	if not screen.apply_view_model(view_model):
		_fail("居民详情 ViewModel 应用失败")
		return
	await process_frame

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	screen.call("_on_row_gui_input", release, 1)
	await process_frame
	await process_frame

	var selected := screen.call("_selected_memory_item") as Dictionary
	_expect(
		str(selected.get("title", "")) == "午前的一场争论",
		"点击第二条记忆后操作目标不是第一条",
	)
	_expect(
		screen.get_node_or_null(
			"ContentScroll/Content/ContentRow_1/SelectedMarker"
		) != null,
		"第二条记忆显示选中标记",
	)
	screen.call("_open_memory_change_dialog", "edit")
	await process_frame
	_expect(
		bool(screen.get("_memory_operation_visible")),
		"选中记忆后可以打开操作面板",
	)
	var operation_selected := screen.call("_selected_memory_item") as Dictionary
	_expect(
		str(operation_selected.get("title", "")) == "午前的一场争论",
		"记忆操作面板仍然锁定第二条记忆",
	)
	print("RESIDENT_DETAIL_MEMORY_SELECTION_PASS")
	quit(0)


func _find_fixture(source: Dictionary, fixture_id: String) -> Dictionary:
	for value: Variant in source.get("scenarios", []) as Array:
		if not value is Dictionary:
			continue
		var scenario := value as Dictionary
		if str(scenario.get("id", "")) == fixture_id:
			return (scenario.get("viewModel", {}) as Dictionary).duplicate(true)
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
