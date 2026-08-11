class_name UserTestDataCleaner
extends RefCounted


const AgentFileSystemScript := preload("res://agent/AgentFileSystem.gd")
const ALLOWED_ROOTS := [
	"user://tests/",
	"user://agent_debug/tests/",
	"user://agent-batch-runner-tests/",
]


static func remove_tree(path: String) -> bool:
	var normalized := path.trim_suffix("/")
	var allowed := false
	for root: String in ALLOWED_ROOTS:
		if normalized.begins_with(root):
			allowed = true
			break
	if not allowed or normalized.contains(".."):
		return false
	var remove_error := _remove_tree_unchecked(normalized)
	if remove_error != OK:
		return false
	for root: String in ALLOWED_ROOTS:
		if normalized.begins_with(root):
			AgentFileSystemScript.remove_empty_directory(normalized.get_base_dir())
			AgentFileSystemScript.remove_empty_directory(root.trim_suffix("/"))
			break
	return true


static func _remove_tree_unchecked(path: String) -> Error:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(absolute_path)
	return AgentFileSystemScript.remove_tree(path)
