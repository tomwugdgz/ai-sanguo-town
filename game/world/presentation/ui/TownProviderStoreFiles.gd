extends RefCounted


# Provider 凭据/配置双 Store 的文件操作孪生收敛(备份换名式原子替换、
# 存在即删、user:// 路径校验)。Audio store 的同名删除函数是不同实现,不并。

static func replace_validated_file(
	temporary_path: String,
	final_path: String,
	backup_path: String,
) -> Error:
	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var final_absolute := ProjectSettings.globalize_path(final_path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	var had_final := FileAccess.file_exists(final_path)
	remove_file_if_present(backup_path)
	if had_final:
		var backup_error := DirAccess.rename_absolute(
			final_absolute,
			backup_absolute,
		)
		if backup_error != OK:
			return backup_error
	var replace_error := DirAccess.rename_absolute(
		temporary_absolute,
		final_absolute,
	)
	if replace_error != OK:
		if had_final and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_absolute, final_absolute)
		return replace_error
	remove_file_if_present(backup_path)
	return OK

static func remove_file_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func user_storage_path_is_valid(path: String) -> bool:
	if (
		not path.begins_with("user://")
		or path == "user://"
		or path.ends_with("/")
		or path.contains("..")
		or path.contains("\\")
	):
		return false
	return not path.trim_prefix("user://").contains("//")
