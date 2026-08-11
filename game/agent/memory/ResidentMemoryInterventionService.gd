class_name AgentResidentMemoryInterventionService
extends RefCounted


const SUPPORTED_OPERATIONS: Array[String] = ["edit", "delete", "write"]

var _resident_id: String
var _entry_store: RefCounted
var _intervention_store: RefCounted


func _init(resident_id: String, entry_store: RefCounted, intervention_store: RefCounted) -> void:
	_resident_id = resident_id
	_entry_store = entry_store
	_intervention_store = intervention_store


func apply(request: Variant) -> Dictionary:
	var request_result := _validate_request(request)
	if not bool(request_result.get("ok", false)):
		return request_result
	var command := request_result["request"] as Dictionary
	var entry_read := _entry_store.call("read") as Dictionary
	if not bool(entry_read.get("ok", false)):
		return entry_read
	var intervention_read := _intervention_store.call("read") as Dictionary
	if not bool(intervention_read.get("ok", false)):
		return intervention_read
	var old_archive := (entry_read["archive"] as Dictionary).duplicate(true)
	var old_log := (intervention_read["log"] as Dictionary).duplicate(true)
	if (
		int(command.get("expected_revision", -1)) != int(old_archive.get("revision", -2))
		or int(old_archive.get("revision", -1)) != int(old_log.get("revision", -2))
	):
		return _failure("居民记忆页面已经过期，请刷新后再操作")
	var new_revision := maxi(int(old_archive["revision"]), int(old_log["revision"])) + 1
	var entries: Array = (old_archive["entries"] as Array).duplicate(true)
	var memory_index := _find_memory(entries, String(command["memory_id"]))
	var operation := String(command["operation"])
	var kind := _internal_kind(operation)
	if kind == "implant":
		if memory_index >= 0:
			return _failure("植入记忆不能复用已有 memory_id")
		entries.append(_implanted_entry(command, new_revision))
		memory_index = entries.size() - 1
	elif memory_index < 0:
		return _failure("目标正式记忆不存在或已变化")
	var original_entry := (entries[memory_index] as Dictionary).duplicate(true)
	var active_entry := original_entry.duplicate(true)
	if kind != "implant":
		active_entry = _changed_entry(original_entry, command, new_revision)
		entries[memory_index] = active_entry
	var intervention_id := "intervention-%s-%d" % [_resident_id, new_revision]
	var intervention := {
		"intervention_id": intervention_id,
		"resident_id": _resident_id,
		"memory_id": String(active_entry["memory_id"]),
		"kind": kind,
		"operation": operation,
		"original_version": _version_projection(original_entry),
		"active_version": _version_projection(active_entry),
		"player_text": String(command["player_text"]),
		"created_world_time": (command["world_time"] as Dictionary).duplicate(true),
		"status": "active",
	}
	var interventions: Array = (old_log["interventions"] as Array).duplicate(true)
	for index in range(interventions.size()):
		var previous := interventions[index] as Dictionary
		if (
			String(previous.get("memory_id", "")) == String(active_entry["memory_id"])
			and String(previous.get("status", "")) == "active"
		):
			var superseded := previous.duplicate(true)
			superseded["status"] = "superseded"
			interventions[index] = superseded
	interventions.append(intervention)
	var new_archive := old_archive.duplicate(true)
	new_archive["revision"] = new_revision
	new_archive["entries"] = entries
	var new_log := old_log.duplicate(true)
	new_log["revision"] = new_revision
	new_log["interventions"] = interventions
	var archive_validation := _entry_store.call("validate", new_archive) as Dictionary
	if not bool(archive_validation.get("ok", false)):
		return archive_validation
	var log_validation := _intervention_store.call("validate", new_log) as Dictionary
	if not bool(log_validation.get("ok", false)):
		return log_validation
	var entry_write := _entry_store.call("replace", archive_validation["archive"]) as Dictionary
	if not bool(entry_write.get("ok", false)):
		return entry_write
	var intervention_write := _intervention_store.call("replace", log_validation["log"]) as Dictionary
	if not bool(intervention_write.get("ok", false)):
		var rollback := _entry_store.call("replace", old_archive) as Dictionary
		if not bool(rollback.get("ok", false)):
			var errors: Array = intervention_write.get("errors", []).duplicate()
			errors.append_array(rollback.get("errors", []))
			return {"ok": false, "errors": errors, "rollback_failed": true}
		return intervention_write
	return {
		"ok": true,
		"revision": new_revision,
		"memory": active_entry.duplicate(true),
		"intervention": intervention.duplicate(true),
		"summary_refresh_required": true,
	}


func _validate_request(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民记忆介入命令必须是对象")
	var request := value as Dictionary
	var fields := [
		"resident_id", "memory_id", "operation", "player_text", "world_time",
		"expected_revision",
	]
	if not _has_exact_fields(request, fields):
		return _failure("居民记忆介入命令字段不完整或包含未知字段")
	var operation := String(request.get("operation", ""))
	var memory_id := String(request.get("memory_id", "")).strip_edges()
	var player_text := String(request.get("player_text", "")).strip_edges()
	if (
		request.get("resident_id") != _resident_id
		or operation not in SUPPORTED_OPERATIONS
		or memory_id.is_empty()
		or typeof(request.get("player_text")) != TYPE_STRING
		or player_text.length() > 480
		or (operation in ["edit", "write"] and player_text.is_empty())
		or typeof(request.get("world_time")) != TYPE_DICTIONARY
		or typeof(request.get("expected_revision")) != TYPE_INT
		or int(request.get("expected_revision")) < 0
	):
		return _failure("居民记忆介入命令归属、类型或内容损坏")
	return {
		"ok": true,
		"request": {
			"resident_id": _resident_id,
			"memory_id": memory_id,
			"operation": operation,
			"player_text": player_text,
			"world_time": (request["world_time"] as Dictionary).duplicate(true),
			"expected_revision": int(request["expected_revision"]),
		},
	}


func _implanted_entry(command: Dictionary, revision: int) -> Dictionary:
	var memory_id := String(command["memory_id"])
	return {
		"memory_id": memory_id,
		"resident_id": _resident_id,
		"subject": String(command["player_text"]),
		"interpretation": "",
		"people": [],
		"places": [],
		"topics": [],
		"world_time": (command["world_time"] as Dictionary).duplicate(true),
		"source_kind": "implanted",
		"source_resident_id": "",
		"claim_root_id": memory_id,
		"confidence": 65,
		"state": "influencing",
		"active_version_id": "%s-v1" % memory_id,
		"evidence_refs": [],
		"created_revision": revision,
		"updated_revision": revision,
	}


func _changed_entry(entry: Dictionary, command: Dictionary, revision: int) -> Dictionary:
	var changed := entry.duplicate(true)
	var kind := _internal_kind(String(command["operation"]))
	match kind:
		"soften":
			changed["confidence"] = maxi(0, int(changed["confidence"]) - 25)
			if int(changed["confidence"]) <= 30:
				changed["state"] = "doubtful"
		"distort":
			changed["subject"] = String(command["player_text"])
			changed["interpretation"] = ""
		"suppress":
			changed["state"] = "past"
	changed["active_version_id"] = "%s-v%d" % [changed["memory_id"], revision]
	changed["updated_revision"] = revision
	return changed


func _internal_kind(operation: String) -> String:
	match operation:
		"edit":
			return "distort"
		"delete":
			return "suppress"
		"write":
			return "implant"
	return ""


func _version_projection(entry: Dictionary) -> Dictionary:
	return {
		"subject": String(entry["subject"]),
		"interpretation": String(entry["interpretation"]),
		"confidence": int(entry["confidence"]),
		"state": String(entry["state"]),
		"active_version_id": String(entry["active_version_id"]),
	}


func _find_memory(entries: Array, memory_id: String) -> int:
	for index in range(entries.size()):
		if String((entries[index] as Dictionary).get("memory_id", "")) == memory_id:
			return index
	return -1


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_name: Variant in fields:
		if not value.has(field_name):
			return false
	return true


func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
