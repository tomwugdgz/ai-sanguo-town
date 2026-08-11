class_name AgentSaveTestFixture
extends RefCounted


static func create_orphan_staging(
	test_root: String,
	context: Dictionary,
	payload: PackedByteArray,
) -> bool:
	var staging_root := "%s.tmp-interrupted" % _snapshot_root(test_root, context)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging_root)) != OK:
		return false
	return _overwrite("%s/resident_0000.bin" % staging_root, payload)


static func overwrite_snapshot_manifest(
	test_root: String,
	context: Dictionary,
	contents: String,
) -> bool:
	return _overwrite(
		"%s/snapshot.json" % _snapshot_root(test_root, context),
		contents.to_utf8_buffer(),
	)


static func overwrite_first_payload(
	test_root: String,
	context: Dictionary,
	payload: PackedByteArray,
) -> bool:
	return _overwrite(
		"%s/resident_0000.bin" % _snapshot_root(test_root, context),
		payload,
	)


static func remove_last_manifest_resident(test_root: String, context: Dictionary) -> bool:
	var path := "%s/snapshot.json" % _snapshot_root(test_root, context)
	var manifest := _read_dictionary(path)
	if manifest.is_empty() or typeof(manifest.get("residents")) != TYPE_ARRAY:
		return false
	var residents := manifest["residents"] as Array
	if residents.is_empty():
		return false
	residents.pop_back()
	var resident_ids: Array = []
	for resident: Dictionary in residents:
		resident_ids.append(resident.get("resident_id"))
	resident_ids.sort()
	manifest["resident_count"] = resident_ids.size()
	manifest["resident_set_sha256"] = _sha256(
		JSON.stringify(resident_ids).to_utf8_buffer(),
	)
	return _overwrite(path, JSON.stringify(manifest).to_utf8_buffer())


static func swap_manifest_resident_ids(test_root: String, context: Dictionary) -> bool:
	var path := "%s/snapshot.json" % _snapshot_root(test_root, context)
	var manifest := _read_dictionary(path)
	if manifest.is_empty() or typeof(manifest.get("residents")) != TYPE_ARRAY:
		return false
	var residents := manifest["residents"] as Array
	if residents.size() != 2:
		return false
	var first := residents[0] as Dictionary
	var second := residents[1] as Dictionary
	var first_id: Variant = first.get("resident_id")
	first["resident_id"] = second.get("resident_id")
	second["resident_id"] = first_id
	return _overwrite(path, JSON.stringify(manifest).to_utf8_buffer())


static func _snapshot_root(test_root: String, context: Dictionary) -> String:
	return "%s/%s/sessions/%s/revisions/%d" % [
		test_root,
		context["slot_id"],
		context["session_id"],
		context["save_revision"],
	]


static func _overwrite(path: String, contents: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(contents)
	file.flush()
	var error := file.get_error()
	file = null
	return error == OK


static func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return parser.data as Dictionary


static func _sha256(payload: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(payload)
	return hashing.finish().hex_encode()
