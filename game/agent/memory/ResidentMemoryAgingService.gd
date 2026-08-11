class_name AgentResidentMemoryAgingService
extends RefCounted


const HEARSAY_INTERVAL_DAYS := 7
const HEARSAY_CONFIDENCE_LOSS := 8
const HEARSAY_PAST_THRESHOLD := 34
const MAX_INTERVENTIONS := 512

var _resident_id: String


func _init(resident_id: String) -> void:
	_resident_id = resident_id


func evaluate(
	archive_value: Variant,
	log_value: Variant,
	world_time_value: Variant,
) -> Dictionary:
	if typeof(archive_value) != TYPE_DICTIONARY or typeof(log_value) != TYPE_DICTIONARY:
		return _failure("居民记忆自动整理输入损坏")
	if typeof(world_time_value) != TYPE_DICTIONARY:
		return _failure("居民记忆自动整理缺少世界时间")
	var archive := (archive_value as Dictionary).duplicate(true)
	var log := (log_value as Dictionary).duplicate(true)
	var world_time := (world_time_value as Dictionary).duplicate(true)
	var current_day := int(world_time.get("day", 0))
	if (
		archive.get("resident_id") != _resident_id
		or log.get("resident_id") != _resident_id
		or int(archive.get("revision", -1)) != int(log.get("revision", -2))
		or current_day < 1
	):
		return _failure("居民记忆自动整理归属、版本或世界时间损坏")
	var entries := (archive.get("entries", []) as Array).duplicate(true)
	var interventions := (log.get("interventions", []) as Array).duplicate(true)
	var candidates: Array[Dictionary] = []
	for index in range(entries.size()):
		var entry := entries[index] as Dictionary
		var steps := _eligible_steps(entry, interventions, current_day)
		if steps > 0:
			candidates.append({"index": index, "steps": steps})
	var available_audits := MAX_INTERVENTIONS - interventions.size()
	if available_audits <= 0:
		return {
			"ok": true,
			"changed": false,
			"archive": archive,
			"intervention_log": log,
			"changes": [],
		}
	if candidates.size() > available_audits:
		candidates.resize(available_audits)
	if candidates.is_empty():
		return {
			"ok": true,
			"changed": false,
			"archive": archive,
			"intervention_log": log,
			"changes": [],
		}
	var new_revision := int(archive.get("revision", 0)) + 1
	var changes: Array[Dictionary] = []
	for candidate_index in range(candidates.size()):
		var candidate := candidates[candidate_index]
		var entry_index := int(candidate.get("index", -1))
		var original := (entries[entry_index] as Dictionary).duplicate(true)
		var changed := original.duplicate(true)
		changed["confidence"] = maxi(
			HEARSAY_PAST_THRESHOLD,
			int(original.get("confidence", 0))
				- int(candidate.get("steps", 0)) * HEARSAY_CONFIDENCE_LOSS,
		)
		if int(changed["confidence"]) <= HEARSAY_PAST_THRESHOLD:
			changed["state"] = "past"
		changed["active_version_id"] = "%s-v%d" % [
			String(changed.get("memory_id", "memory")),
			new_revision,
		]
		changed["updated_revision"] = new_revision
		entries[entry_index] = changed
		var audit := {
			"intervention_id": "aging-%s-%d-%d" % [
				_resident_id,
				new_revision,
				candidate_index + 1,
			],
			"resident_id": _resident_id,
			"memory_id": String(changed.get("memory_id", "")),
			"kind": "soften",
			"operation": "edit",
			"original_version": _version_projection(original),
			"active_version": _version_projection(changed),
			"player_text": "",
			"created_world_time": world_time,
			"status": "superseded",
		}
		interventions.append(audit)
		changes.append({
			"memory_id": String(changed.get("memory_id", "")),
			"confidence_before": int(original.get("confidence", 0)),
			"confidence_after": int(changed.get("confidence", 0)),
			"state_after": String(changed.get("state", "")),
		})
	archive["revision"] = new_revision
	archive["entries"] = entries
	log["revision"] = new_revision
	log["interventions"] = interventions
	return {
		"ok": true,
		"changed": true,
		"revision": new_revision,
		"archive": archive,
		"intervention_log": log,
		"changes": changes,
	}


func _eligible_steps(entry: Dictionary, interventions: Array, current_day: int) -> int:
	if (
		String(entry.get("source_kind", "")) != "hearsay"
		or String(entry.get("state", "")) != "influencing"
		or int(entry.get("confidence", 0)) <= HEARSAY_PAST_THRESHOLD
		or (entry.get("evidence_refs", []) as Array).size() > 2
		or _has_active_player_intervention(interventions, String(entry.get("memory_id", "")))
	):
		return 0
	var reference_day := int((entry.get("world_time", {}) as Dictionary).get("day", 0))
	for intervention_value: Variant in interventions:
		if typeof(intervention_value) != TYPE_DICTIONARY:
			continue
		var intervention := intervention_value as Dictionary
		if (
			String(intervention.get("memory_id", "")) == String(entry.get("memory_id", ""))
			and String(intervention.get("kind", "")) == "soften"
		):
			reference_day = maxi(
				reference_day,
				int((intervention.get("created_world_time", {}) as Dictionary).get("day", 0)),
			)
	var elapsed_days := current_day - reference_day
	return (
		floori(float(elapsed_days) / float(HEARSAY_INTERVAL_DAYS))
		if elapsed_days >= HEARSAY_INTERVAL_DAYS
		else 0
	)


func _has_active_player_intervention(interventions: Array, memory_id: String) -> bool:
	for intervention_value: Variant in interventions:
		if typeof(intervention_value) != TYPE_DICTIONARY:
			continue
		var intervention := intervention_value as Dictionary
		if (
			String(intervention.get("memory_id", "")) == memory_id
			and String(intervention.get("status", "")) == "active"
			and String(intervention.get("kind", "")) != "soften"
		):
			return true
	return false


func _version_projection(entry: Dictionary) -> Dictionary:
	return {
		"subject": String(entry.get("subject", "")),
		"interpretation": String(entry.get("interpretation", "")),
		"confidence": int(entry.get("confidence", 0)),
		"state": String(entry.get("state", "past")),
		"active_version_id": String(entry.get("active_version_id", "")),
	}


func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}
