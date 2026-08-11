@tool
extends Node2D

signal runtime_layers_reloaded(map_id: String)
signal runtime_layers_reload_failed(message: String)

@export_file("*.json") var runtime_json_path := ""
@export_file("*.tscn") var layers_scene_path := ""
@export var load_on_ready := true
@export var clear_existing_runtime_layers := true
@export var runtime_layer_node_name := "MapRuntimeLayers"
@export_group("Live Reload")
@export var watch_generated_files := false
@export_range(0.1, 5.0, 0.1) var watch_interval_seconds := 0.5
@export var print_reload_messages := false

var runtime_data: Dictionary = {}
var runtime_layers: Node2D
var _watch_elapsed := 0.0
var _known_runtime_modified_time := 0
var _known_layers_modified_time := 0

func _ready() -> void:
	set_process(not Engine.is_editor_hint() and watch_generated_files)
	if load_on_ready:
		call_deferred("reload_runtime_layers")
	else:
		call_deferred("_remember_current_file_state")

func _process(delta: float) -> void:
	if not watch_generated_files:
		return
	_watch_elapsed += delta
	if _watch_elapsed < watch_interval_seconds:
		return
	_watch_elapsed = 0.0
	if _generated_files_changed():
		reload_runtime_layers()

func reload_runtime_layers() -> bool:
	var resolved_runtime_path := _resolved_runtime_json_path()
	var resolved_layers_path := _resolved_layers_scene_path()
	if resolved_runtime_path.is_empty():
		return _fail("MapRuntimeLayerLoader has no runtime.json path.")
	if resolved_layers_path.is_empty():
		return _fail("MapRuntimeLayerLoader has no layers.tscn path.")
	if not FileAccess.file_exists(resolved_runtime_path):
		return _fail("Map runtime data not found: %s" % resolved_runtime_path)
	if not ResourceLoader.exists(resolved_layers_path):
		return _fail("Map runtime layer scene not found: %s" % resolved_layers_path)

	var loaded_data := _load_runtime_json(resolved_runtime_path)
	if loaded_data.is_empty():
		return false

	var packed_scene := ResourceLoader.load(resolved_layers_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed_scene == null:
		return _fail("Map runtime layer scene is invalid: %s" % resolved_layers_path)
	var instance := packed_scene.instantiate()
	if not instance is Node2D:
		instance.queue_free()
		return _fail("Map runtime layer scene root must be Node2D: %s" % resolved_layers_path)

	if clear_existing_runtime_layers:
		_remove_existing_runtime_layers()

	runtime_data = loaded_data
	runtime_layers = instance as Node2D
	runtime_layers.name = runtime_layer_node_name
	runtime_layers.set_meta("runtime_json_path", resolved_runtime_path)
	runtime_layers.set_meta("layers_scene_path", resolved_layers_path)
	runtime_layers.set_meta("map_id", String(runtime_data.get("mapId", "")))
	add_child(runtime_layers)
	_remember_current_file_state(resolved_runtime_path, resolved_layers_path)
	if print_reload_messages:
		print("Map runtime layers reloaded: %s" % String(runtime_data.get("mapId", "")))
	runtime_layers_reloaded.emit(String(runtime_data.get("mapId", "")))
	return true

func unload_runtime_layers() -> void:
	_remove_existing_runtime_layers()
	runtime_layers = null
	runtime_data.clear()

func get_runtime_data() -> Dictionary:
	return runtime_data.duplicate(true)

func get_runtime_layer_node() -> Node2D:
	if runtime_layers != null and is_instance_valid(runtime_layers):
		return runtime_layers
	var node := get_node_or_null(runtime_layer_node_name)
	if node is Node2D:
		runtime_layers = node as Node2D
		return runtime_layers
	return null

func _load_runtime_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _fail_dictionary("Map runtime data is empty: %s" % path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail_dictionary("Map runtime data is invalid JSON object: %s" % path)
	return parsed as Dictionary

func _remove_existing_runtime_layers() -> void:
	var node := get_node_or_null(runtime_layer_node_name)
	if node == null:
		return
	remove_child(node)
	node.queue_free()
	if node == runtime_layers:
		runtime_layers = null

func _resolved_runtime_json_path() -> String:
	if not runtime_json_path.is_empty():
		return runtime_json_path
	return _default_generated_path("runtime.json")

func _resolved_layers_scene_path() -> String:
	if not layers_scene_path.is_empty():
		return layers_scene_path
	return _default_generated_path("layers.tscn")

func _default_generated_path(file_name: String) -> String:
	var base_scene_path := _owner_scene_path()
	if base_scene_path.is_empty():
		return ""
	return "%s/generated/%s" % [base_scene_path.get_base_dir(), file_name]

func _owner_scene_path() -> String:
	if not scene_file_path.is_empty():
		return scene_file_path
	if owner != null and not owner.scene_file_path.is_empty():
		return owner.scene_file_path
	return ""

func _generated_files_changed() -> bool:
	var resolved_runtime_path := _resolved_runtime_json_path()
	var resolved_layers_path := _resolved_layers_scene_path()
	var runtime_modified_time := _file_modified_time(resolved_runtime_path)
	var layers_modified_time := _file_modified_time(resolved_layers_path)
	if runtime_modified_time == 0 or layers_modified_time == 0:
		return false
	if _known_runtime_modified_time == 0 and _known_layers_modified_time == 0:
		_known_runtime_modified_time = runtime_modified_time
		_known_layers_modified_time = layers_modified_time
		return false
	return runtime_modified_time != _known_runtime_modified_time or layers_modified_time != _known_layers_modified_time

func _remember_current_file_state(runtime_path: String = "", layers_path: String = "") -> void:
	var resolved_runtime_path: String = runtime_path if not runtime_path.is_empty() else _resolved_runtime_json_path()
	var resolved_layers_path: String = layers_path if not layers_path.is_empty() else _resolved_layers_scene_path()
	_known_runtime_modified_time = _file_modified_time(resolved_runtime_path)
	_known_layers_modified_time = _file_modified_time(resolved_layers_path)

func _file_modified_time(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	return int(FileAccess.get_modified_time(path))

func _fail(message: String) -> bool:
	push_warning(message)
	runtime_layers_reload_failed.emit(message)
	return false

func _fail_dictionary(message: String) -> Dictionary:
	push_warning(message)
	runtime_layers_reload_failed.emit(message)
	return {}
