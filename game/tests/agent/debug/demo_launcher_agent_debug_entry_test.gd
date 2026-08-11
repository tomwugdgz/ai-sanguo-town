extends "res://tests/agent/support/AgentTestCase.gd"

const DEBUG_SCENE := "res://agent/debug/AgentDebugLab.tscn"
const LAUNCHER_SCENE := "res://world/prototypes/demo_launcher/DemoLauncher.tscn"
const DEMO_NAVIGATION := preload(
	"res://world/prototypes/demo_launcher/DemoNavigation.gd"
)



func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var existing_orphan_ids: Array[int] = Node.get_orphan_node_ids()
	_expect(
		root.get_node_or_null("DemoNavigation") == null,
		"正式项目不注册 prototype DemoNavigation autoload",
	)
	var navigation: Node = DEMO_NAVIGATION.new()
	navigation.name = "DemoNavigation"
	root.add_child(navigation)
	var open_error := change_scene_to_file(LAUNCHER_SCENE)
	_expect_equal(open_error, OK, "可以打开 Demo 验证入口")
	await process_frame
	await process_frame

	var debug_button := _find_button("Agent DEBUGUI")
	_expect(debug_button != null, "Demo 验证入口包含 Agent DEBUGUI")
	if debug_button != null:
		debug_button.pressed.emit()
		await process_frame
		await process_frame
		_expect_equal(
			current_scene.scene_file_path if current_scene != null else "",
			DEBUG_SCENE,
			"第三入口可以打开 Agent DEBUGUI",
		)

		var back_button: Button = null
		if navigation != null:
			navigation.call("_update_back_button")
			back_button = navigation.get_node_or_null(
				"DemoNavigationOverlay/BackToDemoLauncher",
			) as Button
		_expect(back_button != null and back_button.visible, "DEBUGUI 可以返回 Demo 验证入口")
		if back_button != null:
			back_button.pressed.emit()
			await process_frame
			await process_frame
			_expect_equal(
				current_scene.scene_file_path if current_scene != null else "",
				LAUNCHER_SCENE,
				"DEBUGUI 返回按钮回到 Demo 验证入口",
			)
			_expect(_find_button("Agent DEBUGUI") != null, "返回后仍可再次进入 DEBUGUI")

	var final_scene := current_scene
	current_scene = null
	if final_scene != null and is_instance_valid(final_scene):
		final_scene.free()
	if is_instance_valid(navigation):
		navigation.free()
	await process_frame
	await process_frame
	var remaining_fixture_orphans := _free_fixture_orphan_buttons(
		existing_orphan_ids,
	)
	_expect(
		remaining_fixture_orphans.is_empty(),
		"Demo 验证夹具不会留下未释放节点：%s"
		% JSON.stringify(remaining_fixture_orphans),
	)
	await process_frame
	await process_frame
	_finish_suite("DEMO_LAUNCHER_AGENT_DEBUG_ENTRY_TEST_PASS")


func _find_button(text_fragment: String) -> Button:
	if current_scene == null:
		return null
	for node: Node in _descendants(current_scene):
		if node is Button and text_fragment in (node as Button).text:
			return node as Button
	return null


func _descendants(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in parent.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _free_fixture_orphan_buttons(existing_ids: Array[int]) -> Array[int]:
	for orphan_id: int in Node.get_orphan_node_ids():
		if existing_ids.has(orphan_id):
			continue
		var orphan := instance_from_id(orphan_id)
		if orphan is Button and (orphan as Button).get_parent() == null:
			(orphan as Button).free()
	var remaining: Array[int] = []
	for orphan_id: int in Node.get_orphan_node_ids():
		if not existing_ids.has(orphan_id):
			remaining.append(orphan_id)
	return remaining
