class_name AgentPromptTestCase
extends "res://tests/agent/support/AgentTestCase.gd"


const COMPILER_PATH := "res://agent/prompt/AgentPromptCompiler.gd"
const TestData := preload("res://tests/support/AgentMemoryTestData.gd")

var _fixture_root := "user://tests/prompt-compiler-files/%d_%d" % [
	OS.get_process_id(),
	Time.get_ticks_usec(),
]


class FakePhotoContentResolver:
	var calls: Array[Dictionary] = []

	func resolve_photo(ref: String, mime_type: String) -> Dictionary:
		calls.append({"ref": ref, "mime_type": mime_type})
		return {
			"ok": true,
			"bytes": "fake-photo-content".to_utf8_buffer(),
		}


func _load_prompt_compiler() -> Script:
	var compiler_script := load(COMPILER_PATH) as Script
	_expect(compiler_script != null, "Prompt Compiler 脚本可加载")
	return compiler_script


func _finish_prompt_test(pass_label: String) -> void:
	_finish_suite(pass_label, [_fixture_root])


func _finalize() -> void:
	_BaseUserTestDataCleaner.remove_tree(_fixture_root)


func _write_fixture(relative_path: String, content: String) -> void:
	_write_fixture_at(_fixture_root, relative_path, content)

func _write_fixture_at(root: String, relative_path: String, content: String) -> void:
	var path := root.path_join(relative_path)
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if error != OK and error != ERR_ALREADY_EXISTS:
		_record_failure("提示词夹具目录创建失败", "write_fixture", OK, error)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_record_failure("提示词夹具文件创建失败", "write_fixture", true, {"path": path, "opened": false})
		return
	file.store_string(content)

func _script_has_method(script: Script, method_name: String) -> bool:
	for method: Dictionary in script.get_script_method_list():
		if String(method.get("name", "")) == method_name:
			return true
	return false

func _initialization() -> Dictionary:
	return TestData.initialization()

func _wake_packet(decision_id: String, weather: String) -> Dictionary:
	var wake := TestData.wake_packet(decision_id, 1, weather)
	wake["snapshot"]["me"]["activityNeeds"] = {
		"energy": 38,
		"satiety": 31,
		"stress": 54,
		"socialNeed": 72,
		"solitudeNeed": 18,
	}
	wake["snapshot"]["rhythm"] = {
		"id": "midday_free",
		"label": "午饭、午休和自由活动",
		"flexible": true,
		"work_expected": false,
		"workplace": "花房咖啡馆",
		"schedule_label": "日间接待服务",
	}
	wake["snapshot"]["nearby"] = [{
		"resident_id": "resident-tang-xiao-man",
		"name": "唐小满",
		"doing": "站在花圃旁观察花朵",
	}]
	wake["snapshot"]["place"] = {
		"name": "社区花园",
		"props": [{"name": "社区花园长椅", "verbs": ["歇着"]}],
	}
	return wake
