class_name TownReplacementResidentCandidatePool
extends RefCounted


var _used_names: Dictionary = {}
var _initial_name := ""
var _revision := 1


func configure(used_names: Array, initial_name: String) -> Dictionary:
	_used_names.clear()
	for value: Variant in used_names:
		var normalized := String(value).strip_edges()
		if not normalized.is_empty():
			_used_names[normalized] = true
	_initial_name = initial_name.strip_edges()
	return {"ok": true, "errorCode": "", "retryable": false}


func candidate_pool_revision() -> int:
	return _revision


func resident_name_available(value: String) -> bool:
	var normalized := value.strip_edges()
	return (
		not normalized.is_empty()
		and (
			normalized == _initial_name
			or not _used_names.has(normalized)
		)
	)


func create_candidate(source: Dictionary, expected_revision: int) -> Dictionary:
	if expected_revision != _revision:
		return _failure("CUSTOM_RESIDENT_CANDIDATE_POOL_REVISION_STALE")
	var attributes := source.get("attributes", {}) as Dictionary
	var resident_name := String(attributes.get("name", "")).strip_edges()
	if not resident_name_available(resident_name):
		return _failure("CUSTOM_RESIDENT_NAME_DUPLICATED")
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"changed": true,
		"candidatePoolRevision": _revision,
		"candidate": source.duplicate(true),
	}


func _failure(error_code: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"changed": false,
	}
