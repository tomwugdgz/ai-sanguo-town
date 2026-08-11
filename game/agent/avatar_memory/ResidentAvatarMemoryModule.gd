class_name AgentResidentAvatarMemoryModule
extends RefCounted


const AgentJsonScript := preload("res://agent/AgentJson.gd")
const EvidenceQueueScript := preload(
	"res://agent/avatar_memory/ResidentAvatarEvidenceQueue.gd"
)
const MemoryStoreScript := preload(
	"res://agent/avatar_memory/ResidentAvatarMemoryStore.gd"
)
const OrganizerScript := preload(
	"res://agent/avatar_memory/AvatarMemoryOrganizer.gd"
)
const RetrieverScript := preload(
	"res://agent/avatar_memory/AvatarMemoryRetriever.gd"
)
const PromptTextScript := preload("res://agent/prompt/PromptText.gd")
const MEMORY_STATE_VERSION := 1
const ORGANIZATION_BATCH_SIZE := 4
const DEPARTURE_PROMPT := (
	"res://prompts/avatar_memory/20_departure_message.md"
)
const FORBIDDEN_MESSAGE_TERMS: Array[String] = [
	"system prompt",
	"提示词",
	"模型",
	"provider",
	"json",
	"memory_id",
	"source_ref",
	"存档",
]

var _initialization: Dictionary
var _resident_id: String
var _resident_name: String
var _avatar_person_id: String
var _avatar_name: String
var _module_root: String
var _memory_path: String
var _evidence_path: String
var _store: RefCounted
var _evidence_queue: RefCounted
var _organizer: RefCounted
var _retriever: RefCounted
var _memory: Dictionary = {}
var _unorganized_since_day := 0
var _storage_initialized := false
var _last_retrieval: Dictionary = {
	"mode": "ordinary_life",
	"memory_ids": [],
}
var _last_update: Dictionary = {"status": "idle"}
var _last_organization: Dictionary = {"status": "idle", "errors": []}
var _last_errors: Array[String] = []


func _init(
	initialization: Dictionary,
	memory_root: String,
	avatar_person_id: String,
	avatar_name: String,
) -> void:
	# initialization 为共享只读数据（约定不可变），各组件持引用不再各存深拷贝。
	_initialization = initialization
	var me := _initialization.get("me", {}) as Dictionary
	_resident_id = String(me.get("resident_id", ""))
	_resident_name = String(
		(me.get("attributes", {}) as Dictionary).get("name", ""),
	)
	_avatar_person_id = avatar_person_id
	_avatar_name = avatar_name
	var resident_root := memory_root.trim_suffix("/").path_join(_resident_id)
	_module_root = resident_root.path_join("avatar_memory")
	_memory_path = _module_root.path_join("avatar_memory.json")
	_evidence_path = _module_root.path_join("avatar_evidence.json")
	_store = MemoryStoreScript.new(
		_memory_path,
		_resident_id,
		_avatar_person_id,
	)
	_evidence_queue = EvidenceQueueScript.new(
		_evidence_path,
		_resident_id,
		_avatar_person_id,
		_avatar_name,
	)
	_memory = _store.call("empty_memory")
	_organizer = OrganizerScript.new(
		_initialization,
		_avatar_person_id,
		_avatar_name,
		_store,
	)
	_retriever = RetrieverScript.new(_avatar_person_id, _avatar_name)


func prepare_context(wake_packet: Dictionary) -> Dictionary:
	_last_organization = {"status": "idle", "errors": []}
	var load_result := _load_current_state(true)
	if not bool(load_result.get("ok", false)):
		return _remember_failure(load_result)
	var ingestion := _evidence_queue.call(
		"append_wake",
		wake_packet,
	) as Dictionary
	if not bool(ingestion.get("ok", false)):
		return _remember_failure(ingestion)
	if bool(ingestion.get("added", false)) and _unorganized_since_day == 0:
		_unorganized_since_day = _wake_day(wake_packet)
	var context := _context_result(wake_packet)
	if not bool(context.get("ok", false)):
		return _remember_failure(context)
	var response := {
		"ok": true,
		"avatar_prompt": context["avatar_prompt"],
	}
	var plan := _build_organization_plan(wake_packet, ingestion)
	if not bool(plan.get("ok", false)):
		record_organization_failure(plan.get("errors", []))
		return response
	if bool(plan.get("triggered", false)):
		response["organization_request"] = plan["request"]
		response["organization_token"] = plan["token"]
	_last_errors = []
	return response


func prepare_departure_organization() -> Dictionary:
	var load_result := _load_current_state(true)
	if not bool(load_result.get("ok", false)):
		return _remember_failure(load_result)
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return _remember_failure(queue_result)
	if int(queue_result.get("new_items_since_organization", 0)) <= 0:
		return {"ok": true, "triggered": false}
	var evidence_items := queue_result.get("items", []) as Array
	var relevant_evidence := _avatar_relevant_evidence(evidence_items)
	if relevant_evidence.is_empty():
		return {"ok": true, "triggered": false}
	var request := _organizer.call(
		"build_request",
		_memory,
		relevant_evidence,
	) as Dictionary
	if not bool(request.get("ok", false)):
		return _remember_failure(request)
	return {
		"ok": true,
		"triggered": true,
		"request": request,
		"token": _organization_token(
			evidence_items,
			int(queue_result.get("new_items_since_organization", 0)),
		),
	}


func retrieve_context(wake_packet: Dictionary) -> Dictionary:
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return _remember_failure(load_result)
	return _context_result(wake_packet)


func accept_organization(token_value: Variant, candidate: Variant) -> Dictionary:
	var context := _organization_context(token_value)
	if not bool(context.get("ok", false)):
		return _organization_failure(
			context,
			bool(context.get("safe_to_continue", false)),
		)
	var validation := _organizer.call(
		"validate_candidate",
		candidate,
		context["old_memory"],
		context["evidence_items"],
	) as Dictionary
	if not bool(validation.get("ok", false)):
		if bool(validation.get("retryable", false)):
			var retry_request := _organizer.call(
				"build_retry_request",
				context["old_memory"],
				context["evidence_items"],
				validation,
			) as Dictionary
			if bool(retry_request.get("ok", false)):
				var failure := _organization_failure(validation, true)
				failure["retry_request"] = retry_request
				return failure
		return _organization_failure(validation, true)
	var replacement := _store.call(
		"replace",
		validation["memory"],
	) as Dictionary
	if not bool(replacement.get("ok", false)):
		return _organization_failure(replacement, true)
	var mark_result := _evidence_queue.call("mark_organized") as Dictionary
	if not bool(mark_result.get("ok", false)):
		var rollback := _store.call(
			"replace",
			context["old_memory"],
		) as Dictionary
		if not bool(rollback.get("ok", false)):
			var errors: Array = mark_result.get("errors", []).duplicate()
			errors.append_array(rollback.get("errors", []))
			return _organization_failure(
				{"ok": false, "errors": errors},
				false,
			)
		return _organization_failure(mark_result, true)
	_memory = (replacement["memory"] as Dictionary).duplicate(true)
	_unorganized_since_day = 0
	_last_update = {
		"status": "organized",
		"revision": int(_memory.get("revision", 0)),
	}
	_last_organization = {"status": "organized", "errors": []}
	_last_errors = []
	return {"ok": true, "memory": _memory.duplicate(true)}


func record_organization_failure(errors: Variant) -> Dictionary:
	var messages: Array[String] = []
	if typeof(errors) == TYPE_ARRAY:
		for error_value: Variant in errors as Array:
			messages.append(String(error_value))
	if messages.is_empty():
		messages.append("居民化身记忆整理失败")
	return _organization_failure(
		{"ok": false, "errors": messages},
		true,
	)


func has_departure_context() -> Dictionary:
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return load_result
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var marker := _departure_context_marker(
		_avatar_relevant_evidence(
			queue_result.get("items", []) as Array,
		),
	)
	return {
		"ok": true,
		"eligible": _departure_marker_has_unscreened_context(marker),
		"unscreened_source_count": (
			marker.get("unscreened_source_refs", []) as Array
		).size(),
	}


func build_departure_message_request(departure_id: String) -> Dictionary:
	if departure_id.strip_edges().is_empty():
		return _failure("退出留言需要稳定 departure_id")
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return load_result
	for message_value: Variant in _memory.get("sent_messages", []) as Array:
		var message := message_value as Dictionary
		if String(message.get("departure_id", "")) == departure_id:
			return {
				"ok": true,
				"already_completed": true,
				"message": _public_message(message),
			}
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var evidence_items := _avatar_relevant_evidence(
		queue_result.get("items", []) as Array,
	)
	var marker := _departure_context_marker(evidence_items)
	if not _departure_marker_has_unscreened_context(marker):
		return {"ok": true, "eligible": false}
	var departure_context := _departure_unscreened_context(
		marker,
		evidence_items,
	)
	var retrieved := _retriever.call(
		"retrieve",
		departure_context.get("memory", {}) as Dictionary,
		departure_context.get("evidence_items", []) as Array,
		"departure_message",
		{},
	) as Dictionary
	if not bool(retrieved.get("ok", false)):
		return retrieved
	var context := String(retrieved.get("text", "")).strip_edges()
	if context.is_empty():
		return {"ok": true, "eligible": false}
	var prompt_result := _read_prompt(DEPARTURE_PROMPT)
	if not bool(prompt_result.get("ok", false)):
		return prompt_result
	var attributes := (
		(_initialization.get("me", {}) as Dictionary)
		.get("attributes", {}) as Dictionary
	)
	var system_text := "%s\n\n## 居民本人\n姓名：%s\n性格：%s\n说话方式：%s\n化身当前称呼：%s" % [
		prompt_result["content"],
		_safe(_resident_name),
		_safe(attributes.get("personality", "")),
		_safe(attributes.get("speech", "")),
		_safe(_avatar_name),
	]
	return {
		"ok": true,
		"eligible": true,
		"request": {
			"request_kind": "departure_message",
			"max_tokens": 256,
			"messages": [
				{"role": "system", "content": system_text},
				{
					"role": "user",
					"content": "[你对化身的私人记忆]\n%s" % context,
				},
			],
		},
		"token": {
				"departure_id": departure_id,
				"resident_id": _resident_id,
				"memory_revision": int(_memory.get("revision", 0)),
				"context_digest": String(marker.get("digest", "")),
				"screening_source_refs": (
					marker.get("source_refs", []) as Array
				).duplicate(),
				"screening_summary_sha256": String(
					marker.get("summary_sha256", ""),
				),
				"world_time": _latest_world_time(
					evidence_items,
				),
			},
		}


func accept_departure_message(
	token_value: Variant,
	candidate: Variant,
) -> Dictionary:
	var reviewed := review_departure_message(
		token_value,
		candidate,
	) as Dictionary
	if (
		not bool(reviewed.get("ok", false))
		or not bool(reviewed.get("wrote", false))
		or not reviewed.has("proposal")
	):
		return reviewed
	return commit_departure_message(
		reviewed.get("proposal"),
	)


func review_departure_message(
	token_value: Variant,
	candidate: Variant,
) -> Dictionary:
	if typeof(token_value) != TYPE_DICTIONARY:
		return _failure("退出留言 token 损坏")
	var token := token_value as Dictionary
	if (
		String(token.get("resident_id", "")) != _resident_id
		or String(token.get("departure_id", "")).strip_edges().is_empty()
	):
		return _failure("退出留言 token 归属损坏")
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return load_result
	var departure_id := String(token["departure_id"])
	for message_value: Variant in _memory.get("sent_messages", []) as Array:
		var existing := message_value as Dictionary
		if String(existing.get("departure_id", "")) == departure_id:
			return {
				"ok": true,
				"wrote": true,
				"message": _public_message(existing),
			}
	if int(token.get("memory_revision", -1)) != int(
		_memory.get("revision", 0),
	):
		return _failure("退出留言依据的化身记忆已经变化")
	if typeof(candidate) != TYPE_DICTIONARY:
		return _model_output_failure("退出留言模型结果必须是对象")
	var output := candidate as Dictionary
	if not _has_exact_fields(output, ["write", "message"]):
		return _model_output_failure("退出留言模型结果字段损坏")
	if (
		typeof(output.get("write")) != TYPE_BOOL
		or typeof(output.get("message")) != TYPE_STRING
	):
		return _model_output_failure("退出留言模型结果类型损坏")
	var should_write := bool(output["write"])
	var content := String(output["message"]).strip_edges()
	if not should_write:
		if not content.is_empty():
			return _model_output_failure("居民决定不写时 message 必须为空")
		var screened := mark_departure_context_screened(token)
		if not bool(screened.get("ok", false)):
			return screened
		return {"ok": true, "wrote": false, "screened": true}
	var message_error := _message_error(content)
	if not message_error.is_empty():
		return _model_output_failure(message_error)
	return {
		"ok": true,
		"wrote": true,
		"proposal": {
			"token": token.duplicate(true),
			"content": content,
		},
	}


func commit_departure_message(proposal_value: Variant) -> Dictionary:
	if typeof(proposal_value) != TYPE_DICTIONARY:
		return _failure("退出留言提案损坏")
	var proposal := proposal_value as Dictionary
	if (
		not proposal.get("token") is Dictionary
		or typeof(proposal.get("content")) != TYPE_STRING
	):
		return _failure("退出留言提案字段损坏")
	var token := proposal.get("token", {}) as Dictionary
	if (
		String(token.get("resident_id", "")) != _resident_id
		or String(token.get("departure_id", "")).strip_edges().is_empty()
	):
		return _failure("退出留言提案归属损坏")
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return load_result
	var departure_id := String(token["departure_id"])
	for message_value: Variant in _memory.get("sent_messages", []) as Array:
		var existing := message_value as Dictionary
		if String(existing.get("departure_id", "")) == departure_id:
			return {
				"ok": true,
				"wrote": true,
				"message": _public_message(existing),
			}
	if int(token.get("memory_revision", -1)) != int(
		_memory.get("revision", 0),
	):
		return _failure("退出留言提案依据的化身记忆已经变化")
	var content := String(proposal["content"]).strip_edges()
	var message_error := _message_error(content)
	if not message_error.is_empty():
		return _failure(message_error)
	var message_id := "resident-message-%s" % (
		AgentJsonScript.content_sha256({
			"resident_id": _resident_id,
			"departure_id": departure_id,
			"content": content,
		}).left(24)
	)
	var message := {
		"message_id": message_id,
		"content": content,
		"world_time": (
			token.get("world_time", {}) as Dictionary
		).duplicate(true),
		"departure_id": departure_id,
		"status": "unconfirmed",
	}
	var next := _memory.duplicate(true)
	var messages := (next.get("sent_messages", []) as Array).duplicate(true)
	messages.append(message)
	while messages.size() > MemoryStoreScript.MESSAGE_LIMIT_COUNT:
		messages.pop_front()
	next["sent_messages"] = messages
	next["revision"] = int(next.get("revision", 0)) + 1
	next["departure_screening"] = _screening_from_token(token)
	var replacement := _store.call("replace", next) as Dictionary
	if not bool(replacement.get("ok", false)):
		return replacement
	_memory = (replacement["memory"] as Dictionary).duplicate(true)
	_last_update = {
		"status": "message_written",
		"message_id": message_id,
		"departure_id": departure_id,
	}
	return {
		"ok": true,
		"wrote": true,
		"message": _public_message(message),
	}


func mark_departure_context_screened(token_value: Variant) -> Dictionary:
	if typeof(token_value) != TYPE_DICTIONARY:
		return _failure("居民留言筛查 token 损坏")
	var token := token_value as Dictionary
	if (
		String(token.get("resident_id", "")) != _resident_id
		or String(token.get("departure_id", "")).strip_edges().is_empty()
		or typeof(token.get("screening_source_refs")) != TYPE_ARRAY
		or typeof(token.get("screening_summary_sha256")) != TYPE_STRING
	):
		return _failure("居民留言筛查 token 归属或字段损坏")
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return load_result
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var marker := _departure_context_marker(
		_avatar_relevant_evidence(
			queue_result.get("items", []) as Array,
		),
	)
	if (
		int(token.get("memory_revision", -1))
			!= int(_memory.get("revision", 0))
		or String(token.get("context_digest", ""))
			!= String(marker.get("digest", ""))
	):
		return _failure("居民留言筛查依据已经变化")
	var next := _memory.duplicate(true)
	next["departure_screening"] = _screening_from_token(token)
	var replacement := _store.call("replace", next) as Dictionary
	if not bool(replacement.get("ok", false)):
		return replacement
	_memory = (replacement["memory"] as Dictionary).duplicate(true)
	_last_update = {
		"status": "departure_context_screened",
		"departure_id": String(token.get("departure_id", "")),
	}
	return {"ok": true, "screened": true}


func capture_persistent_state() -> Dictionary:
	var load_result := _load_current_state(true)
	if not bool(load_result.get("ok", false)):
		return load_result
	var queue_capture := _evidence_queue.call("capture_state") as Dictionary
	if not bool(queue_capture.get("ok", false)):
		return queue_capture
	return {
		"ok": true,
		"avatar_memory_state": {
			"avatar_memory_state_version": MEMORY_STATE_VERSION,
			"resident_id": _resident_id,
			"avatar_person_id": _avatar_person_id,
			"memory": _memory.duplicate(true),
			"evidence_queue": (
				queue_capture["queue_state"] as Dictionary
			).duplicate(true),
			"unorganized_since_day": _unorganized_since_day,
		},
	}


func apply_persistent_state(value: Variant) -> Dictionary:
	if FileAccess.file_exists(_memory_path) or FileAccess.file_exists(_evidence_path):
		return _failure("居民化身记忆恢复目标不是空目录")
	var validation := _validate_persistent_state(value)
	if not bool(validation.get("ok", false)):
		return validation
	var state := validation["avatar_memory_state"] as Dictionary
	var replacement := _store.call("replace", state["memory"]) as Dictionary
	if not bool(replacement.get("ok", false)):
		return replacement
	var queue_application := _evidence_queue.call(
		"apply_state",
		state["evidence_queue"],
	) as Dictionary
	if not bool(queue_application.get("ok", false)):
		_clear_storage()
		return queue_application
	_memory = (replacement["memory"] as Dictionary).duplicate(true)
	_unorganized_since_day = int(state["unorganized_since_day"])
	_storage_initialized = true
	_last_update = {"status": "restored"}
	_last_errors = []
	return {"ok": true}


func empty_persistent_state() -> Dictionary:
	return {
		"avatar_memory_state_version": MEMORY_STATE_VERSION,
		"resident_id": _resident_id,
		"avatar_person_id": _avatar_person_id,
		"memory": _store.call("empty_memory"),
		"evidence_queue": {
			"queue_state_version": EvidenceQueueScript.STATE_VERSION,
			"resident_id": _resident_id,
			"avatar_person_id": _avatar_person_id,
			"items": [],
			"known_source_hashes": {},
			"new_items_since_organization": 0,
		},
		"unorganized_since_day": 0,
	}


func get_debug_snapshot() -> Dictionary:
	var memory_result := _store.call("read") as Dictionary
	var evidence_result := _evidence_queue.call("read") as Dictionary
	return {
		"resident_id": _resident_id,
		"resident": _resident_name,
		"avatar_person_id": _avatar_person_id,
		"avatar_name": _avatar_name,
		"source": _memory_path,
		"evidence_source": _evidence_path,
		"memory": (
			(memory_result.get("memory", {}) as Dictionary).duplicate(true)
			if bool(memory_result.get("ok", false))
			else {}
		),
		"evidence": (
			(evidence_result.get("items", []) as Array).duplicate(true)
			if bool(evidence_result.get("ok", false))
			else []
		),
		"last_retrieval": _last_retrieval.duplicate(true),
		"last_update": _last_update.duplicate(true),
		"last_organization": _last_organization.duplicate(true),
		"errors": _last_errors.duplicate(),
		"limits": {
			"organization_batch": ORGANIZATION_BATCH_SIZE,
			"evidence_queue": EvidenceQueueScript.MAX_ITEMS,
			"memory": _store.call("capacity"),
		},
	}


func _context_result(wake_packet: Dictionary) -> Dictionary:
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var mode := String(_retriever.call("mode_for_wake", wake_packet))
	var retrieval := _retriever.call(
		"retrieve",
		_memory,
		_avatar_relevant_evidence(
			queue_result.get("items", []) as Array,
		),
		mode,
		wake_packet,
	) as Dictionary
	if not bool(retrieval.get("ok", false)):
		return retrieval
	_last_retrieval = {
		"mode": mode,
		"memory_ids": (
			retrieval.get("memory_ids", []) as Array
		).duplicate(),
	}
	return {
		"ok": true,
		"avatar_prompt": String(retrieval.get("text", "")),
		"mode": mode,
	}


func _departure_context_marker(evidence_items: Array) -> Dictionary:
	var source_ref_set: Dictionary = {}
	for field_name: String in ["memories", "open_loops"]:
		for item_value: Variant in _memory.get(field_name, []) as Array:
			if typeof(item_value) != TYPE_DICTIONARY:
				continue
			for source_ref_value: Variant in (
				item_value as Dictionary
			).get("source_refs", []) as Array:
				var source_ref := String(source_ref_value).strip_edges()
				if not source_ref.is_empty():
					source_ref_set[source_ref] = true
	for evidence_value: Variant in evidence_items:
		if typeof(evidence_value) != TYPE_DICTIONARY:
			continue
		var source_ref := String(
			(evidence_value as Dictionary).get("source_ref", ""),
		).strip_edges()
		if not source_ref.is_empty():
			source_ref_set[source_ref] = true
	var source_refs: Array[String] = []
	for source_ref_value: Variant in source_ref_set:
		source_refs.append(String(source_ref_value))
	source_refs.sort()
	var summary := String(_memory.get("summary", "")).strip_edges()
	var summary_sha256 := (
		AgentJsonScript.content_sha256(summary)
		if not summary.is_empty()
		else ""
	)
	var screening := (
		_memory.get("departure_screening", {}) as Dictionary
	)
	var screened_refs := {}
	for source_ref_value: Variant in screening.get("source_refs", []) as Array:
		screened_refs[String(source_ref_value)] = true
	var unscreened_source_refs: Array[String] = []
	for source_ref: String in source_refs:
		if not screened_refs.has(source_ref):
			unscreened_source_refs.append(source_ref)
	var summary_unscreened := (
		not summary_sha256.is_empty()
		and summary_sha256
			!= String(screening.get("summary_sha256", ""))
	)
	return {
		"source_refs": source_refs,
		"unscreened_source_refs": unscreened_source_refs,
		"summary_sha256": summary_sha256,
		"summary_unscreened": summary_unscreened,
		"digest": AgentJsonScript.content_sha256({
			"source_refs": source_refs,
			"summary_sha256": summary_sha256,
		}),
	}


func _departure_marker_has_unscreened_context(marker: Dictionary) -> bool:
	return (
		not (
			marker.get("unscreened_source_refs", []) as Array
		).is_empty()
		or bool(marker.get("summary_unscreened", false))
	)


func _departure_unscreened_context(
	marker: Dictionary,
	evidence_items: Array,
) -> Dictionary:
	var unscreened_refs := {}
	for source_ref_value: Variant in (
		marker.get("unscreened_source_refs", []) as Array
	):
		unscreened_refs[String(source_ref_value)] = true
	var filtered_memory := _memory.duplicate(true)
	for field_name: String in ["memories", "open_loops"]:
		var filtered_items: Array[Dictionary] = []
		for item_value: Variant in _memory.get(field_name, []) as Array:
			if typeof(item_value) != TYPE_DICTIONARY:
				continue
			var item := item_value as Dictionary
			if _item_has_any_source_ref(
				item.get("source_refs", []) as Array,
				unscreened_refs,
			):
				filtered_items.append(item.duplicate(true))
		filtered_memory[field_name] = filtered_items
	if not bool(marker.get("summary_unscreened", false)):
		filtered_memory["summary"] = ""
	var filtered_evidence: Array[Dictionary] = []
	for evidence_value: Variant in evidence_items:
		if typeof(evidence_value) != TYPE_DICTIONARY:
			continue
		var evidence := evidence_value as Dictionary
		if unscreened_refs.has(String(evidence.get("source_ref", ""))):
			filtered_evidence.append(evidence.duplicate(true))
	return {
		"memory": filtered_memory,
		"evidence_items": filtered_evidence,
	}


func _item_has_any_source_ref(
	source_refs: Array,
	allowed_refs: Dictionary,
) -> bool:
	for source_ref_value: Variant in source_refs:
		if allowed_refs.has(String(source_ref_value)):
			return true
	return false


func _screening_from_token(token: Dictionary) -> Dictionary:
	var source_refs: Array[String] = []
	for source_ref_value: Variant in (
		token.get("screening_source_refs", []) as Array
	):
		var source_ref := String(source_ref_value).strip_edges()
		if not source_ref.is_empty() and not source_refs.has(source_ref):
			source_refs.append(source_ref)
	source_refs.sort()
	return {
		"source_refs": source_refs,
		"summary_sha256": String(
			token.get("screening_summary_sha256", ""),
		),
		"departure_id": String(token.get("departure_id", "")).strip_edges(),
	}


func _build_organization_plan(
	wake_packet: Dictionary,
	ingestion: Dictionary,
) -> Dictionary:
	if not bool(ingestion.get("added", false)):
		return {"ok": true, "triggered": false}
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var new_count := int(
		queue_result.get("new_items_since_organization", 0),
	)
	var day_crossed := (
		_unorganized_since_day > 0
		and _wake_day(wake_packet) > _unorganized_since_day
	)
	var direct_end := bool(
		ingestion.get("direct_avatar_conversation_ended", false),
	)
	var snapshot := wake_packet.get("snapshot", {}) as Dictionary
	var conversation_active := (
		snapshot.get("conversation") is Dictionary
		and not direct_end
	)
	if (
		conversation_active
		or (
			not direct_end
			and new_count < ORGANIZATION_BATCH_SIZE
			and not day_crossed
		)
	):
		return {"ok": true, "triggered": false}
	var evidence_items := queue_result.get("items", []) as Array
	var relevant_evidence := _avatar_relevant_evidence(evidence_items)
	if relevant_evidence.is_empty():
		return {"ok": true, "triggered": false}
	var request := _organizer.call(
		"build_request",
		_memory,
		relevant_evidence,
	) as Dictionary
	if not bool(request.get("ok", false)):
		return request
	return {
		"ok": true,
		"triggered": true,
		"request": request,
		"token": _organization_token(evidence_items, new_count),
	}


func _organization_context(token_value: Variant) -> Dictionary:
	if typeof(token_value) != TYPE_DICTIONARY:
		return _failure("化身记忆整理 token 损坏")
	var token := token_value as Dictionary
	if String(token.get("resident_id", "")) != _resident_id:
		return _failure("化身记忆整理 token 归属不一致")
	var load_result := _load_current_state()
	if not bool(load_result.get("ok", false)):
		return load_result
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var evidence_items := queue_result.get("items", []) as Array
	if (
		int(token.get("memory_revision", -1))
			!= int(_memory.get("revision", 0))
		or int(token.get("evidence_count", -1)) != evidence_items.size()
		or String(token.get("evidence_digest", ""))
			!= AgentJsonScript.content_sha256(evidence_items)
	):
		return {
			"ok": false,
			"errors": ["化身记忆整理结果已经过期"],
			"safe_to_continue": true,
		}
	return {
		"ok": true,
		"old_memory": _memory.duplicate(true),
		"evidence_items": _avatar_relevant_evidence(evidence_items),
	}


func _validate_persistent_state(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("居民化身记忆持久状态必须是对象")
	var state := value as Dictionary
	if not _has_exact_fields(
		state,
		[
			"avatar_memory_state_version",
			"resident_id",
			"avatar_person_id",
			"memory",
			"evidence_queue",
			"unorganized_since_day",
		],
	):
		return _failure("居民化身记忆持久状态字段损坏")
	if (
		state.get("avatar_memory_state_version") != MEMORY_STATE_VERSION
		or state.get("resident_id") != _resident_id
		or state.get("avatar_person_id") != _avatar_person_id
		or typeof(state.get("unorganized_since_day")) != TYPE_INT
		or int(state.get("unorganized_since_day")) < 0
	):
		return _failure("居民化身记忆持久状态版本、归属或类型损坏")
	var memory_validation := _store.call(
		"validate",
		state.get("memory"),
	) as Dictionary
	if not bool(memory_validation.get("ok", false)):
		return memory_validation
	var queue_validation := _evidence_queue.call(
		"validate_state",
		state.get("evidence_queue"),
	) as Dictionary
	if not bool(queue_validation.get("ok", false)):
		return queue_validation
	return {
		"ok": true,
		"avatar_memory_state": {
			"avatar_memory_state_version": MEMORY_STATE_VERSION,
			"resident_id": _resident_id,
			"avatar_person_id": _avatar_person_id,
			"memory": (
				memory_validation["memory"] as Dictionary
			).duplicate(true),
			"evidence_queue": (
				queue_validation["queue_state"] as Dictionary
			).duplicate(true),
			"unorganized_since_day": int(state["unorganized_since_day"]),
		},
	}


func _load_current_state(initialize_missing: bool = false) -> Dictionary:
	var memory_result := _store.call("read") as Dictionary
	if not bool(memory_result.get("ok", false)):
		return memory_result
	var queue_result := _evidence_queue.call("read") as Dictionary
	if not bool(queue_result.get("ok", false)):
		return queue_result
	var memory_exists := FileAccess.file_exists(_memory_path)
	var evidence_exists := FileAccess.file_exists(_evidence_path)
	if memory_exists != evidence_exists:
		return _failure("居民化身记忆与证据文件不完整")
	if not memory_exists:
		if _storage_initialized or DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(_module_root),
		):
			return _failure("居民化身记忆与证据文件缺失")
		if initialize_missing:
			var replacement := _store.call(
				"replace",
				_store.call("empty_memory"),
			) as Dictionary
			if not bool(replacement.get("ok", false)):
				return replacement
			var queue_initialization := _evidence_queue.call(
				"initialize_empty",
			) as Dictionary
			if not bool(queue_initialization.get("ok", false)):
				_clear_storage()
				return queue_initialization
	_memory = (memory_result["memory"] as Dictionary).duplicate(true)
	if initialize_missing or memory_exists:
		_storage_initialized = true
	return {"ok": true}


func _organization_token(
	evidence_items: Array,
	new_item_count: int,
) -> Dictionary:
	return {
		"resident_id": _resident_id,
		"memory_revision": int(_memory.get("revision", 0)),
		"evidence_digest": AgentJsonScript.content_sha256(evidence_items),
		"evidence_count": evidence_items.size(),
		"new_item_count": new_item_count,
	}


func _avatar_relevant_evidence(evidence_items: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for evidence_value: Variant in evidence_items:
		if typeof(evidence_value) != TYPE_DICTIONARY:
			continue
		var evidence := (evidence_value as Dictionary).duplicate(true)
		var payload_value: Variant = evidence.get("payload")
		if typeof(payload_value) == TYPE_DICTIONARY:
			var payload := (payload_value as Dictionary).duplicate(true)
			if payload.has("speaker_resident_id"):
				var speaker_id := String(
					payload.get("speaker_resident_id", ""),
				).strip_edges()
				if speaker_id != _avatar_person_id:
					payload["narration"] = ""
				var say := String(payload.get("say", "")).strip_edges()
				var narration := String(
					payload.get("narration", ""),
				).strip_edges()
				var photos := payload.get("photos", []) as Array
				if say.is_empty() and narration.is_empty() and photos.is_empty():
					continue
			evidence["payload"] = payload
		result.append(evidence)
	return result


func _latest_world_time(evidence_items: Array) -> Dictionary:
	if not evidence_items.is_empty():
		var latest := evidence_items.back() as Dictionary
		return (
			latest.get("world_time", {}) as Dictionary
		).duplicate(true)
	for field_name: String in ["open_loops", "memories"]:
		var items := _memory.get(field_name, []) as Array
		if not items.is_empty():
			return (
				(items.back() as Dictionary).get("world_time", {}) as Dictionary
			).duplicate(true)
	return {"day": 0, "clock": "00:00", "period": "未知"}


func _public_message(message: Dictionary) -> Dictionary:
	return {
		"message_id": String(message.get("message_id", "")),
		"resident_id": _resident_id,
		"resident_name": _resident_name,
		"content": String(message.get("content", "")),
	}


func _message_error(content: String) -> String:
	if content.is_empty():
		return "居民留言不能为空"
	if content.length() > MemoryStoreScript.MESSAGE_LIMIT_LENGTH:
		return "居民留言超过代码容量上限"
	if content.contains("\n") or content.contains("\r"):
		return "居民留言必须是一句话"
	var lowered := content.to_lower()
	for term in FORBIDDEN_MESSAGE_TERMS:
		if lowered.contains(term.to_lower()):
			return "居民留言包含内部系统用语"
	return ""


func _organization_failure(
	result: Dictionary,
	safe_to_continue: bool,
) -> Dictionary:
	var errors: Array = result.get("errors", ["居民化身记忆整理失败"]).duplicate()
	_last_organization = {
		"status": "failed",
		"errors": errors.duplicate(),
		"safe_to_continue": safe_to_continue,
	}
	_last_errors = []
	for value: Variant in errors:
		_last_errors.append(String(value))
	return {
		"ok": false,
		"errors": errors,
		"safe_to_continue": safe_to_continue,
	}


func _remember_failure(result: Dictionary) -> Dictionary:
	_last_errors = []
	for value: Variant in result.get("errors", []) as Array:
		_last_errors.append(String(value))
	return result


func _wake_day(wake_packet: Dictionary) -> int:
	return int(
		(
			(wake_packet.get("snapshot", {}) as Dictionary)
			.get("time", {}) as Dictionary
		).get("day", 0),
	)


# 提示词文件是静态内容，进程级缓存一份。
static var _prompt_text_cache: Dictionary = {}


func _read_prompt(path: String) -> Dictionary:
	if _prompt_text_cache.has(path):
		return {"ok": true, "content": _prompt_text_cache[path]}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法读取居民留言提示词：%s" % path)
	var content := file.get_as_text().strip_edges()
	file = null
	if content.is_empty():
		return _failure("居民留言提示词为空：%s" % path)
	_prompt_text_cache[path] = content
	return {"ok": true, "content": content}


func _clear_storage() -> void:
	_store.call("erase_storage")
	_evidence_queue.call("erase_storage")
	_storage_initialized = false
	_memory = _store.call("empty_memory")


func _safe(value: Variant) -> String:
	return PromptTextScript.escape_dynamic(String(value))


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_name: Variant in fields:
		if not value.has(field_name):
			return false
	return true


func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}


func _model_output_failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"errors": [message],
		"failure_kind": "model_output",
	}
