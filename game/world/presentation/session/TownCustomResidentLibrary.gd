class_name TownCustomResidentLibrary
extends RefCounted


const DEFAULT_PATH := "user://town_custom_resident_library.json"
const TEST_ROOT := "user://tests/town_custom_resident_library"
const SCHEMA := "town-custom-resident-library"
const SCHEMA_VERSION := TownSaveSchemaRegistry.CUSTOM_RESIDENT_LIBRARY_SCHEMA_VERSION


var _path := DEFAULT_PATH
var _configured := false


func configure(path := DEFAULT_PATH) -> Dictionary:
	if _configured:
		return _failure("CUSTOM_RESIDENT_LIBRARY_ALREADY_CONFIGURED", false)
	var normalized := String(path).strip_edges()
	if not _path_is_allowed(normalized):
		return _failure("CUSTOM_RESIDENT_LIBRARY_PATH_INVALID", false)
	_path = normalized
	_configured = true
	return _success(1, [])


func load_library() -> Dictionary:
	if not _configured:
		return _failure("CUSTOM_RESIDENT_LIBRARY_NOT_CONFIGURED", false)
	var recovery := _recover_interrupted_replace()
	if not bool(recovery.get("ok", false)):
		return recovery
	if not FileAccess.file_exists(_path):
		return _success(1, [])
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return _failure("CUSTOM_RESIDENT_LIBRARY_READ_FAILED", true)
	var raw := file.get_as_text()
	var read_error := file.get_error()
	file = null
	if read_error != OK:
		return _failure("CUSTOM_RESIDENT_LIBRARY_READ_FAILED", true)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return _failure("CUSTOM_RESIDENT_LIBRARY_INVALID", false)
	var payload := parsed as Dictionary
	if (
		String(payload.get("schema", "")) != SCHEMA
		or int(payload.get("schemaVersion", 0)) != SCHEMA_VERSION
		or int(payload.get("libraryRevision", 0)) < 1
		or not payload.get("candidates") is Array
	):
		return _failure("CUSTOM_RESIDENT_LIBRARY_INVALID", false)
	var validation := _validate_candidates(payload.get("candidates", []) as Array)
	if not bool(validation.get("ok", false)):
		return validation
	return _success(
		int(payload.get("libraryRevision", 1)),
		payload.get("candidates", []) as Array,
	)


func replace_candidates(
	candidates: Array,
	expected_revision: int,
	target_revision: int,
) -> Dictionary:
	if not _configured:
		return _failure("CUSTOM_RESIDENT_LIBRARY_NOT_CONFIGURED", false)
	var current := load_library()
	if not bool(current.get("ok", false)):
		return current
	if expected_revision != int(current.get("libraryRevision", 0)):
		return _failure("CUSTOM_RESIDENT_LIBRARY_REVISION_STALE", false)
	if target_revision != expected_revision + 1:
		return _failure("CUSTOM_RESIDENT_LIBRARY_REVISION_INVALID", false)
	var validation := _validate_candidates(candidates)
	if not bool(validation.get("ok", false)):
		return validation
	var payload := {
		"schema": SCHEMA,
		"schemaVersion": SCHEMA_VERSION,
		"libraryRevision": target_revision,
		"candidates": candidates.duplicate(true),
	}
	var parent_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_path.get_base_dir()),
	)
	if parent_error != OK:
		return _failure("CUSTOM_RESIDENT_LIBRARY_WRITE_FAILED", true)
	var temporary := "%s.tmp-%d" % [_path, Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("CUSTOM_RESIDENT_LIBRARY_WRITE_FAILED", true)
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _failure("CUSTOM_RESIDENT_LIBRARY_WRITE_FAILED", true)
	var absolute_path := ProjectSettings.globalize_path(_path)
	var absolute_temporary := ProjectSettings.globalize_path(temporary)
	var backup := "%s.bak" % _path
	var absolute_backup := ProjectSettings.globalize_path(backup)
	if FileAccess.file_exists(backup):
		var stale_backup_remove := DirAccess.remove_absolute(absolute_backup)
		if stale_backup_remove != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return _failure("CUSTOM_RESIDENT_LIBRARY_WRITE_FAILED", true)
	var moved_previous := false
	if FileAccess.file_exists(_path):
		var backup_error := DirAccess.rename_absolute(
			absolute_path,
			absolute_backup,
		)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return _failure("CUSTOM_RESIDENT_LIBRARY_WRITE_FAILED", true)
		moved_previous = true
	var rename_error := DirAccess.rename_absolute(
		absolute_temporary,
		absolute_path,
	)
	if rename_error != OK:
		DirAccess.remove_absolute(absolute_temporary)
		if moved_previous:
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		return _failure("CUSTOM_RESIDENT_LIBRARY_WRITE_FAILED", true)
	if moved_previous:
		# The new primary file is already durable. A leftover backup is harmless
		# and is cleaned on the next load if this cleanup itself is interrupted.
		DirAccess.remove_absolute(absolute_backup)
	return _success(target_revision, candidates)


func storage_path() -> String:
	return _path


func _recover_interrupted_replace() -> Dictionary:
	var backup := "%s.bak" % _path
	if not FileAccess.file_exists(backup):
		return {"ok": true, "errorCode": "", "retryable": false}
	var absolute_backup := ProjectSettings.globalize_path(backup)
	var absolute_path := ProjectSettings.globalize_path(_path)
	if FileAccess.file_exists(_path):
		var cleanup_error := DirAccess.remove_absolute(absolute_backup)
		if cleanup_error != OK:
			return _failure("CUSTOM_RESIDENT_LIBRARY_RECOVERY_FAILED", true)
		return {"ok": true, "errorCode": "", "retryable": false}
	var restore_error := DirAccess.rename_absolute(
		absolute_backup,
		absolute_path,
	)
	if restore_error != OK:
		return _failure("CUSTOM_RESIDENT_LIBRARY_RECOVERY_FAILED", true)
	return {"ok": true, "errorCode": "", "retryable": false}


func _validate_candidates(candidates: Array) -> Dictionary:
	var resident_ids: Dictionary = {}
	for value: Variant in candidates:
		if not value is Dictionary:
			return _failure("CUSTOM_RESIDENT_LIBRARY_INVALID", false)
		var candidate := value as Dictionary
		var resident_id := String(candidate.get("residentId", "")).strip_edges()
		if (
			resident_id.is_empty()
			or resident_ids.has(resident_id)
			or String(candidate.get("source", "custom")) != "custom"
		):
			return _failure("CUSTOM_RESIDENT_LIBRARY_INVALID", false)
		resident_ids[resident_id] = true
	return {"ok": true, "errorCode": "", "retryable": false}


func _path_is_allowed(path: String) -> bool:
	return (
		path == DEFAULT_PATH
		or (
			path.begins_with("%s/" % TEST_ROOT)
			and not path.contains("..")
			and path.ends_with(".json")
		)
	)


func _success(revision: int, candidates: Array) -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"libraryRevision": revision,
		"candidates": candidates.duplicate(true),
		"storagePath": _path,
	}


func _failure(error_code: String, retryable: bool) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": retryable,
		"storagePath": _path,
	}
