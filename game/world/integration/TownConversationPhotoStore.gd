class_name TownConversationPhotoStore
extends RefCounted


const MAX_FILE_BYTES := 10 * 1024 * 1024
const MAX_IMAGE_EDGE := 8192
const MAX_IMAGE_PIXELS := 36 * 1024 * 1024
const PREVIEW_EDGE := 256
const STORAGE_ROOT := "user://town_conversation_photos"
const TEST_STORAGE_ROOT := "user://tests/town_conversation_photos"
const PHOTO_WRITE_BLOCK_SCHEMA := "ai-town-conversation-photo-archive-block"
const SAVE_STORE := preload(
	"res://world/presentation/session/TownSessionSaveStore.gd"
)

# 内存中常驻照片字节的上限；已落盘且无 staged 引用的条目按最久未用淘汰，
# 需要时由 _load_persisted_entry 从磁盘重新加载。
const MAX_MEMORY_ENTRIES := 24

var _entries: Dictionary = {}
var _storage_root := STORAGE_ROOT
var _session_storage_root := ""
var _slot_id := ""
var _session_id := ""
var _save_store: RefCounted = SAVE_STORE.new()
var _entry_access_sequence := 0


func configure_test_roots(
	photo_storage_root: String,
	session_save_root: String,
) -> Dictionary:
	if (
		_storage_root != STORAGE_ROOT
		or not _session_storage_root.is_empty()
		or not _slot_id.is_empty()
		or not _session_id.is_empty()
	):
		return _failure("PHOTO_STORAGE_ALREADY_CONFIGURED")
	var normalized_photo_root := photo_storage_root.trim_suffix("/")
	if (
		normalized_photo_root.is_empty()
		or normalized_photo_root != photo_storage_root
		or not normalized_photo_root.begins_with("%s/" % TEST_STORAGE_ROOT)
		or normalized_photo_root.contains("..")
		or normalized_photo_root.contains("\\")
		or normalized_photo_root.trim_prefix(
			"%s/" % TEST_STORAGE_ROOT
		).contains("//")
	):
		return _failure("PHOTO_STORAGE_TEST_PATH_INVALID")
	var configured := _save_store.configure_test_root(session_save_root,) as Dictionary
	if configured.get("ok") != true:
		return _failure("PHOTO_STORAGE_TEST_PATH_INVALID")
	_storage_root = normalized_photo_root
	return {
		"ok": true,
		"errorCode": "",
	}


func configure_session(slot_id: String, session_id: String) -> Dictionary:
	var safe_slot := _safe_segment(slot_id)
	var safe_session := _safe_segment(session_id)
	if safe_slot.is_empty() or safe_session.is_empty():
		return _failure("PHOTO_STORAGE_CONTEXT_INVALID")
	var lease := _save_store.begin_slot_transaction(safe_slot,) as Dictionary
	if lease.get("ok") != true:
		return _lease_failure(lease)
	var candidate_root := "%s/%s/%s" % [
		_storage_root,
		safe_slot,
		safe_session,
	]
	var blocker_existed := FileAccess.file_exists(
		"%s/%s" % [_storage_root, safe_slot],
	)
	var prepared := (
		_remove_archive_blocker(safe_slot)
		and _make_directory(candidate_root)
	)
	if not prepared and blocker_existed:
		_restore_archive_blocker(safe_slot, candidate_root)
	var released := _save_store.end_slot_transaction(lease.get("leaseToken"),) as Dictionary
	if (
		prepared
		and blocker_existed
		and released.get("ok") != true
	):
		_restore_archive_blocker(safe_slot, candidate_root)
	if not prepared or released.get("ok") != true:
		return _failure("PHOTO_STORAGE_UNAVAILABLE")
	_entries.clear()
	_slot_id = safe_slot
	_session_id = safe_session
	_session_storage_root = candidate_root
	return {
		"ok": true,
		"errorCode": "",
		"storageScope": "session",
	}


func discard_unpublished_session(
	restore_archive_blocker: bool = false,
) -> Dictionary:
	if (
		_slot_id.is_empty()
		and _session_id.is_empty()
		and _session_storage_root.is_empty()
	):
		_entries.clear()
		return {
			"ok": true,
			"errorCode": "",
			"changed": false,
		}
	if not _configured_session_context_is_exact():
		return _failure("PHOTO_STORAGE_CONTEXT_INVALID")
	var lease := _save_store.begin_slot_transaction(_slot_id,) as Dictionary
	if lease.get("ok") != true:
		return _lease_failure(lease)
	var discarded := _remove_tree(_session_storage_root) == OK
	if discarded:
		discarded = (
			_restore_archive_blocker(_slot_id, _session_storage_root)
			if restore_archive_blocker
			else _remove_empty_slot_root(_slot_id)
		)
	var released := _save_store.end_slot_transaction(lease.get("leaseToken"),) as Dictionary
	if not discarded or released.get("ok") != true:
		return _failure("PHOTO_STORAGE_UNAVAILABLE")
	_entries.clear()
	_slot_id = ""
	_session_id = ""
	_session_storage_root = ""
	return {
		"ok": true,
		"errorCode": "",
		"changed": true,
	}


func stage_file(path: String, owner_id: String) -> Dictionary:
	var normalized_path := path.strip_edges()
	var normalized_owner := owner_id.strip_edges()
	if normalized_path.is_empty() or normalized_owner.is_empty():
		return _failure("PHOTO_SELECTION_INVALID")
	var file := FileAccess.open(normalized_path, FileAccess.READ)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return _failure(
			"PHOTO_PERMISSION_DENIED"
			if open_error == ERR_FILE_CANT_OPEN
			else "PHOTO_READ_FAILED"
		)
	var file_size := file.get_length()
	if file_size <= 0:
		return _failure("PHOTO_READ_FAILED")
	if file_size > MAX_FILE_BYTES:
		return _failure("PHOTO_FILE_TOO_LARGE")
	var bytes := file.get_buffer(file_size)
	if bytes.size() != file_size:
		return _failure("PHOTO_READ_FAILED")
	var mime_type := _detect_mime_type(bytes)
	if mime_type.is_empty():
		return _failure("PHOTO_FORMAT_UNSUPPORTED")
	var decoded := _decode_image(bytes, mime_type)
	if not bool(decoded.get("ok", false)):
		return decoded
	var image := decoded.get("image") as Image
	var width := image.get_width()
	var height := image.get_height()
	if (
		width <= 0
		or height <= 0
		or width > MAX_IMAGE_EDGE
		or height > MAX_IMAGE_EDGE
		or width * height > MAX_IMAGE_PIXELS
	):
		return _failure("PHOTO_DIMENSIONS_UNSUPPORTED")
	var ref := "chat-photo-sha256-%s" % _sha256(bytes)
	var entry := (_entries.get(ref, {}) as Dictionary).duplicate(true)
	if entry.is_empty():
		entry = {
			"mimeType": mime_type,
			"bytes": bytes,
			"committed": false,
			"preparedPersisted": false,
			"stagedOwners": {},
		}
	elif String(entry.get("mimeType", "")) != mime_type:
		return _failure("PHOTO_REF_COLLISION")
	var staged_owners := entry.get("stagedOwners", {}) as Dictionary
	staged_owners[normalized_owner] = (
		int(staged_owners.get(normalized_owner, 0)) + 1
	)
	entry["stagedOwners"] = staged_owners
	_entry_access_sequence += 1
	entry["lastAccess"] = _entry_access_sequence
	_entries[ref] = entry
	_evict_reloadable_entries()
	return {
		"ok": true,
		"errorCode": "",
		"ref": ref,
		"mimeType": mime_type,
		"byteSize": file_size,
		"width": width,
		"height": height,
		"previewImage": _preview_image(image),
	}


func has_staged_photo(ref: String, mime_type: String, owner_id: String) -> bool:
	var entry := _entries.get(ref, {}) as Dictionary
	if entry.is_empty() or String(entry.get("mimeType", "")) != mime_type:
		return false
	var owners := entry.get("stagedOwners", {}) as Dictionary
	return int(owners.get(owner_id, 0)) > 0


func prepare_photo_commit(
	ref: String,
	mime_type: String,
	owner_id: String,
) -> bool:
	if not has_staged_photo(ref, mime_type, owner_id):
		return false
	# A standalone/in-memory store is useful for previews and contract harnesses.
	# Formal sessions must persist the bytes before the World accepts the turn.
	if _session_storage_root.is_empty():
		return true
	if not _load_persisted_entry(ref, mime_type).is_empty():
		return true
	var lease := _save_store.begin_slot_transaction(_slot_id,) as Dictionary
	if lease.get("ok") != true:
		return false
	var persisted := _persist_entry(ref, _entries[ref] as Dictionary)
	var released := _save_store.end_slot_transaction(lease.get("leaseToken"),) as Dictionary
	if persisted:
		var prepared_entry := _entries[ref] as Dictionary
		prepared_entry["preparedPersisted"] = true
		_entries[ref] = prepared_entry
	return persisted and released.get("ok") == true


func commit_photo(ref: String, mime_type: String, owner_id: String) -> bool:
	if not prepare_photo_commit(ref, mime_type, owner_id):
		return false
	var entry := _entries[ref] as Dictionary
	_decrement_owner(entry, owner_id)
	entry["committed"] = true
	entry["preparedPersisted"] = false
	_entries[ref] = entry
	return true


func discard_staged_photo(ref: String, owner_id: String) -> bool:
	var entry := _entries.get(ref, {}) as Dictionary
	if entry.is_empty():
		return false
	var owners := entry.get("stagedOwners", {}) as Dictionary
	if int(owners.get(owner_id, 0)) <= 0:
		return false
	var removes_uncommitted_entry := (
		not bool(entry.get("committed", false))
		and int(owners.get(owner_id, 0)) == 1
		and owners.size() == 1
	)
	if (
		removes_uncommitted_entry
		and bool(entry.get("preparedPersisted", false))
		and not _remove_prepared_persisted_photo(ref)
	):
		return false
	_decrement_owner(entry, owner_id)
	if (
		not bool(entry.get("committed", false))
		and (entry.get("stagedOwners", {}) as Dictionary).is_empty()
	):
		_entries.erase(ref)
	else:
		_entries[ref] = entry
	return true


func _remove_prepared_persisted_photo(ref: String) -> bool:
	if _session_storage_root.is_empty():
		return true
	var path := _photo_path(ref)
	if not FileAccess.file_exists(path):
		return true
	var lease := _save_store.begin_slot_transaction(_slot_id,) as Dictionary
	if lease.get("ok") != true:
		return false
	var removed := (
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path)
		) == OK
	)
	var released := _save_store.end_slot_transaction(lease.get("leaseToken"),) as Dictionary
	return removed and released.get("ok") == true


func resolve_photo(ref: String, mime_type: String) -> Dictionary:
	var entry := _entries.get(ref, {}) as Dictionary
	if entry.is_empty():
		entry = _load_persisted_entry(ref, mime_type)
		if entry.is_empty():
			return _failure("PHOTO_REF_NOT_FOUND")
		_entries[ref] = entry
	if String(entry.get("mimeType", "")) != mime_type:
		return _failure("PHOTO_MIME_MISMATCH")
	# 先记录本次访问再淘汰，刚加载的条目才不会以默认序号把自己挤出去。
	_entry_access_sequence += 1
	entry["lastAccess"] = _entry_access_sequence
	_evict_reloadable_entries()
	var bytes_value: Variant = entry.get("bytes")
	if (
		typeof(bytes_value) != TYPE_PACKED_BYTE_ARRAY
		or (bytes_value as PackedByteArray).is_empty()
	):
		return _failure("PHOTO_CONTENT_UNAVAILABLE")
	return {
		"ok": true,
		"errors": [],
		"bytes": (bytes_value as PackedByteArray).duplicate(),
	}


func resolve_photo_preview(ref: String, mime_type: String) -> Dictionary:
	var resolved := resolve_photo(ref, mime_type)
	if not bool(resolved.get("ok", false)):
		return resolved
	var decoded := _decode_image(
		resolved.get("bytes", PackedByteArray()) as PackedByteArray,
		mime_type,
	)
	if not bool(decoded.get("ok", false)):
		return decoded
	var image := decoded.get("image") as Image
	if image == null or image.is_empty():
		return _failure("PHOTO_PREVIEW_FAILED")
	return {
		"ok": true,
		"errorCode": "",
		"previewImage": _preview_image(image),
	}


func clear() -> void:
	_entries.clear()


func _evict_reloadable_entries() -> void:
	if _entries.size() <= MAX_MEMORY_ENTRIES or _session_storage_root.is_empty():
		return
	var candidates: Array = []
	for ref_value: Variant in _entries:
		var ref := String(ref_value)
		var entry := _entries[ref] as Dictionary
		if (
			bool(entry.get("committed", false))
			and (entry.get("stagedOwners", {}) as Dictionary).is_empty()
			and FileAccess.file_exists(_photo_path(ref))
		):
			candidates.append([int(entry.get("lastAccess", 0)), ref])
	candidates.sort()
	for candidate: Variant in candidates:
		if _entries.size() <= MAX_MEMORY_ENTRIES:
			break
		_entries.erase((candidate as Array)[1])


func audit_snapshot() -> Dictionary:
	var committed_count := 0
	var staged_count := 0
	for value: Variant in _entries.values():
		var entry := value as Dictionary
		if bool(entry.get("committed", false)):
			committed_count += 1
		for count: Variant in (entry.get("stagedOwners", {}) as Dictionary).values():
			staged_count += int(count)
	return {
		"entryCount": _entries.size(),
		"committedCount": committed_count,
		"stagedCount": staged_count,
		"containsBytes": not _entries.is_empty(),
	}


func _decrement_owner(entry: Dictionary, owner_id: String) -> void:
	var owners := entry.get("stagedOwners", {}) as Dictionary
	var next_count := int(owners.get(owner_id, 0)) - 1
	if next_count <= 0:
		owners.erase(owner_id)
	else:
		owners[owner_id] = next_count
	entry["stagedOwners"] = owners


func _persist_entry(ref: String, entry: Dictionary) -> bool:
	if _session_storage_root.is_empty() or not _valid_ref(ref):
		return false
	var bytes_value: Variant = entry.get("bytes")
	if (
		typeof(bytes_value) != TYPE_PACKED_BYTE_ARRAY
		or (bytes_value as PackedByteArray).is_empty()
	):
		return false
	var destination := _photo_path(ref)
	var temporary := "%s.tmp" % destination
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes_value as PackedByteArray)
	file.flush()
	var write_error := file.get_error()
	file = null
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return false
	var absolute_temporary := ProjectSettings.globalize_path(temporary)
	var absolute_destination := ProjectSettings.globalize_path(destination)
	if FileAccess.file_exists(destination):
		var existing := _load_persisted_entry(
			ref,
			String(entry.get("mimeType", "")),
		)
		DirAccess.remove_absolute(absolute_temporary)
		return not existing.is_empty()
	var rename_error := DirAccess.rename_absolute(
		absolute_temporary,
		absolute_destination,
	)
	if rename_error != OK:
		DirAccess.remove_absolute(absolute_temporary)
		return false
	return true


func _load_persisted_entry(ref: String, mime_type: String) -> Dictionary:
	if (
		_session_storage_root.is_empty()
		or not _valid_ref(ref)
		or mime_type not in ["image/png", "image/jpeg", "image/webp"]
	):
		return {}
	var path := _photo_path(ref)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var length := file.get_length()
	if length <= 0 or length > MAX_FILE_BYTES:
		return {}
	var bytes := file.get_buffer(length)
	if bytes.size() != length or _detect_mime_type(bytes) != mime_type:
		return {}
	if "chat-photo-sha256-%s" % _sha256(bytes) != ref:
		return {}
	return {
		"mimeType": mime_type,
		"bytes": bytes,
		"committed": true,
		"stagedOwners": {},
	}


func _photo_path(ref: String) -> String:
	return "%s/%s.bin" % [_session_storage_root, ref]


func _remove_archive_blocker(slot_id: String) -> bool:
	var slot_path := "%s/%s" % [_storage_root, slot_id]
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(slot_path)):
		return true
	if not FileAccess.file_exists(slot_path):
		return true
	if not _archive_blocker_is_valid(slot_path, slot_id):
		return false
	return DirAccess.remove_absolute(
		ProjectSettings.globalize_path(slot_path)
	) == OK


func _archive_blocker_is_valid(slot_path: String, slot_id: String) -> bool:
	var file := FileAccess.open(slot_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var read_error := file.get_error()
	file = null
	if read_error != OK:
		return false
	if not parsed is Dictionary:
		return false
	var blocker := parsed as Dictionary
	var keys := blocker.keys()
	keys.sort()
	if keys != ["schema", "schema_version", "slot_id"]:
		return false
	if (
		blocker.get("schema") != PHOTO_WRITE_BLOCK_SCHEMA
		or blocker.get("schema_version") != 1
		or blocker.get("slot_id") != slot_id
	):
		return false
	return true


func _restore_archive_blocker(
	slot_id: String,
	candidate_root: String,
) -> bool:
	var slot_path := "%s/%s" % [_storage_root, slot_id]
	if FileAccess.file_exists(slot_path):
		return _archive_blocker_is_valid(slot_path, slot_id)
	if DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(candidate_root),
	):
		if _remove_tree(candidate_root) != OK:
			return false
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(slot_path)):
		if (
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(slot_path),
			)
			!= OK
		):
			return false
	var file := FileAccess.open(slot_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"schema": PHOTO_WRITE_BLOCK_SCHEMA,
		"schema_version": 1,
		"slot_id": slot_id,
	}, "\t"))
	file.flush()
	var write_error := file.get_error()
	file = null
	return write_error == OK


func _configured_session_context_is_exact() -> bool:
	if not _storage_root_is_allowed():
		return false
	var safe_slot := _safe_segment(_slot_id)
	var safe_session := _safe_segment(_session_id)
	if (
		safe_slot.is_empty()
		or safe_slot != _slot_id
		or safe_session.is_empty()
		or safe_session != _session_id
	):
		return false
	return (
		_session_storage_root
		== "%s/%s/%s" % [_storage_root, safe_slot, safe_session]
	)


func _storage_root_is_allowed() -> bool:
	if _storage_root == STORAGE_ROOT:
		return true
	return (
		_storage_root.begins_with("%s/" % TEST_STORAGE_ROOT)
		and not _storage_root.ends_with("/")
		and not _storage_root.contains("..")
		and not _storage_root.contains("\\")
		and not _storage_root.trim_prefix(
			"%s/" % TEST_STORAGE_ROOT
		).contains("//")
	)


func _remove_empty_slot_root(slot_id: String) -> bool:
	var slot_path := "%s/%s" % [_storage_root, slot_id]
	var absolute := ProjectSettings.globalize_path(slot_path)
	if not DirAccess.dir_exists_absolute(absolute):
		return not FileAccess.file_exists(slot_path)
	return DirAccess.remove_absolute(absolute) == OK


func _remove_tree(path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return DirAccess.get_open_error()
	directory.include_hidden = true
	for file_name: String in directory.get_files():
		var file_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path("%s/%s" % [path, file_name]),
		)
		if file_error != OK:
			return file_error
	for directory_name: String in directory.get_directories():
		var child_error := _remove_tree("%s/%s" % [path, directory_name])
		if child_error != OK:
			return child_error
	# Windows keeps the directory locked while this iterator owns its handle.
	directory = null
	return DirAccess.remove_absolute(absolute)


func _make_directory(path: String) -> bool:
	var error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path)
	)
	return error == OK or error == ERR_ALREADY_EXISTS


func _lease_failure(result: Dictionary) -> Dictionary:
	return _failure(
		"PHOTO_STORAGE_SLOT_BUSY"
		if result.get("errorCode") == "SESSION_SAVE_SLOT_BUSY"
		else "PHOTO_STORAGE_UNAVAILABLE"
	)


func _valid_ref(ref: String) -> bool:
	if not ref.begins_with("chat-photo-sha256-"):
		return false
	var digest := ref.trim_prefix("chat-photo-sha256-")
	if digest.length() != 64:
		return false
	for index in digest.length():
		var code := digest.unicode_at(index)
		if not (
			code >= "0".unicode_at(0) and code <= "9".unicode_at(0)
			or code >= "a".unicode_at(0) and code <= "f".unicode_at(0)
		):
			return false
	return true


func _safe_segment(value: String) -> String:
	var normalized := value.strip_edges()
	if (
		value != normalized
		or normalized.is_empty()
		or normalized.length() > 128
	):
		return ""
	for index in normalized.length():
		var code := normalized.unicode_at(index)
		var allowed := (
			code >= "0".unicode_at(0) and code <= "9".unicode_at(0)
			or code >= "A".unicode_at(0) and code <= "Z".unicode_at(0)
			or code >= "a".unicode_at(0) and code <= "z".unicode_at(0)
			or code == "-".unicode_at(0)
			or code == "_".unicode_at(0)
		)
		if not allowed:
			return ""
	return normalized


func _detect_mime_type(bytes: PackedByteArray) -> String:
	if (
		bytes.size() >= 8
		and bytes[0] == 0x89
		and bytes[1] == 0x50
		and bytes[2] == 0x4E
		and bytes[3] == 0x47
		and bytes[4] == 0x0D
		and bytes[5] == 0x0A
		and bytes[6] == 0x1A
		and bytes[7] == 0x0A
	):
		return "image/png"
	if (
		bytes.size() >= 3
		and bytes[0] == 0xFF
		and bytes[1] == 0xD8
		and bytes[2] == 0xFF
	):
		return "image/jpeg"
	if (
		bytes.size() >= 12
		and bytes.slice(0, 4).get_string_from_ascii() == "RIFF"
		and bytes.slice(8, 12).get_string_from_ascii() == "WEBP"
	):
		return "image/webp"
	return ""


func _decode_image(bytes: PackedByteArray, mime_type: String) -> Dictionary:
	var image := Image.new()
	var error := ERR_UNAVAILABLE
	match mime_type:
		"image/png":
			error = image.load_png_from_buffer(bytes)
		"image/jpeg":
			error = image.load_jpg_from_buffer(bytes)
		"image/webp":
			error = image.load_webp_from_buffer(bytes)
	if error != OK or image.is_empty():
		return _failure("PHOTO_DECODE_FAILED")
	return {"ok": true, "errorCode": "", "image": image}


func _preview_image(source: Image) -> Image:
	var preview := source.duplicate()
	var size: Vector2i = preview.get_size()
	var largest := maxi(size.x, size.y)
	if largest <= PREVIEW_EDGE:
		return preview
	var scale := float(PREVIEW_EDGE) / float(largest)
	preview.resize(
		maxi(1, int(round(size.x * scale))),
		maxi(1, int(round(size.y * scale))),
		Image.INTERPOLATE_LANCZOS,
	)
	return preview


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"errors": [],
	}
