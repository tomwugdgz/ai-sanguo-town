extends RefCounted


# 世界数据烘焙/铺设工具的 JSON 文档读写孪生收敛。

static func load_json_object(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func serialize_document(document: Dictionary) -> String:
	if document.is_empty():
		return ""
	return JSON.stringify(document, "  ", true) + "\n"


static func write_document(path: String, document: Dictionary) -> bool:
	var serialized := serialize_document(document)
	if path.is_empty() or serialized.is_empty():
		return false
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(serialized)
	return true
