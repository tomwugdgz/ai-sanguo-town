extends RefCounted


static func remove_tree(path: String) -> Error:
	var absolute_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return OK
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return DirAccess.get_open_error()
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child_path := "%s/%s" % [path.trim_suffix("/"), name]
			var remove_error := OK
			if directory.current_is_dir():
				remove_error = remove_tree(child_path)
			else:
				remove_error = DirAccess.remove_absolute(
					ProjectSettings.globalize_path(child_path),
				)
			if remove_error != OK:
				directory.list_dir_end()
				return remove_error
		name = directory.get_next()
	directory.list_dir_end()
	# Windows can keep the directory locked until the DirAccess object itself is
	# released, even after list_dir_end() closes the enumeration.
	directory = null
	return DirAccess.remove_absolute(absolute_path)


static func remove_empty_directory(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var first_entry := directory.get_next()
	directory.list_dir_end()
	directory = null
	if first_entry.is_empty():
		DirAccess.remove_absolute(absolute_path)


static func is_safe_path_segment(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for character in value:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true
