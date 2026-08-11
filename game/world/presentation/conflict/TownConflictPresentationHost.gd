class_name TownConflictPresentationHost
extends Node


signal conflict_visuals_changed(snapshot: Dictionary)
signal conflict_visual_error(error: Dictionary)

const CONFLICT_PRESENTATION := preload(
	"res://world/presentation/conflict/TownConflictPresentation.gd"
)

var _controller: Object
var _resident_presentation: Object
var _effect_layer: Node2D
var _conflict_presentation: Node2D
var _registered_resident_ids: Dictionary = {}
var _registered_external_actor_ids: Dictionary = {}
var _conflict_paused_actor_ids: Dictionary = {}
var _configured := false
var _projection_method := &""


func _ready() -> void:
	process_physics_priority = -1000
	set_physics_process(false)


func configure(
	controller: Object,
	resident_presentation: Object,
	effect_layer: Node2D,
	options: Dictionary = {},
) -> Dictionary:
	if _configured:
		return _failure("CONFLICT_PRESENTATION_HOST_ALREADY_CONFIGURED")
	if controller == null or resident_presentation == null or effect_layer == null:
		return _failure("CONFLICT_PRESENTATION_HOST_BINDING_REQUIRED")
	var projection_method := &"get_public_projection"
	if not controller.has_method(projection_method):
		projection_method = &"get_public_conflict_projection"
	if not controller.has_method(projection_method):
		return _failure(
			"CONFLICT_PRESENTATION_HOST_CONTROLLER_INTERFACE_MISSING",
			{
				"methods": [
					"get_public_projection",
					"get_public_conflict_projection",
				],
			},
		)
	for method_name: StringName in [
		&"get_resident_ids",
		&"get_body",
		&"get_presentation_snapshot",
	]:
		if not resident_presentation.has_method(method_name):
			return _failure(
				"CONFLICT_PRESENTATION_HOST_RESIDENT_INTERFACE_MISSING",
				{"method": String(method_name)},
			)
	if not controller.has_signal("conflict_projection_changed"):
		return _failure(
			"CONFLICT_PRESENTATION_HOST_CONTROLLER_SIGNAL_MISSING"
		)
	if (
		not resident_presentation.has_signal("resident_body_created")
		or not resident_presentation.has_signal("resident_body_removed")
	):
		return _failure("CONFLICT_PRESENTATION_HOST_RESIDENT_SIGNAL_MISSING")

	var presentation := CONFLICT_PRESENTATION.new()
	presentation.name = "TownConflictPresentation"
	effect_layer.add_child(presentation)
	var configured_result := presentation.configure(options) as Dictionary
	if configured_result.get("ok") != true:
		presentation.queue_free()
		return configured_result
	presentation.connect(
		"effect_started",
		_on_presentation_effect_state_changed,
	)
	presentation.connect(
		"effect_finished",
		_on_presentation_effect_state_changed,
	)

	_controller = controller
	_projection_method = projection_method
	_resident_presentation = resident_presentation
	_effect_layer = effect_layer
	_conflict_presentation = presentation
	_controller.connect(
		"conflict_projection_changed",
		_on_conflict_projection_changed,
	)
	_resident_presentation.connect(
		"resident_body_created",
		_on_resident_body_created,
	)
	_resident_presentation.connect(
		"resident_body_removed",
		_on_resident_body_removed,
	)
	_register_existing_residents()
	_configured = true
	set_physics_process(true)
	return sync_now()


func unconfigure() -> void:
	if _controller != null:
		var projection_callable := Callable(
			self,
			"_on_conflict_projection_changed",
		)
		if _controller.is_connected(
			"conflict_projection_changed",
			projection_callable,
		):
			_controller.disconnect(
				"conflict_projection_changed",
				projection_callable,
			)
	if _resident_presentation != null:
		var created_callable := Callable(self, "_on_resident_body_created")
		if _resident_presentation.is_connected(
			"resident_body_created",
			created_callable,
		):
			_resident_presentation.disconnect(
				"resident_body_created",
				created_callable,
			)
		var removed_callable := Callable(self, "_on_resident_body_removed")
		if _resident_presentation.is_connected(
			"resident_body_removed",
			removed_callable,
		):
			_resident_presentation.disconnect(
				"resident_body_removed",
				removed_callable,
			)
	_release_all_conflict_pauses()
	if _conflict_presentation != null:
		_conflict_presentation.call("clear_all")
		_conflict_presentation.queue_free()
	_controller = null
	_projection_method = &""
	_resident_presentation = null
	_effect_layer = null
	_conflict_presentation = null
	_registered_resident_ids.clear()
	_registered_external_actor_ids.clear()
	_conflict_paused_actor_ids.clear()
	_configured = false
	set_physics_process(false)


func sync_now() -> Dictionary:
	if not _configured and _controller == null:
		return _failure("CONFLICT_PRESENTATION_HOST_NOT_CONFIGURED")
	var projection_value: Variant = _controller.call(_projection_method)
	if projection_value is not Dictionary:
		return _failure("CONFLICT_PRESENTATION_HOST_PROJECTION_INVALID")
	return _apply_projection(projection_value as Dictionary)


func debug_snapshot() -> Dictionary:
	var paused_actor_ids := _sorted_dictionary_keys(
		_conflict_paused_actor_ids,
	)
	var paused_resident_ids: Array[String] = []
	for actor_id: String in paused_actor_ids:
		if _registered_resident_ids.has(actor_id):
			paused_resident_ids.append(actor_id)
	var registered_ids: Array[String] = []
	for resident_id_value: Variant in _registered_resident_ids:
		registered_ids.append(String(resident_id_value))
	registered_ids.sort()
	return {
		"configured": _configured,
		"registeredResidentIds": registered_ids,
		"registeredExternalActorIds": _sorted_dictionary_keys(
			_registered_external_actor_ids,
		),
		"conflictPausedActorIds": paused_actor_ids,
		"conflictPausedResidentIds": paused_resident_ids,
		"residentWorldPaused": _resident_world_paused(),
		"visuals": (
			_conflict_presentation.call("debug_snapshot")
			if _conflict_presentation != null
			else {}
		),
	}


func _exit_tree() -> void:
	unconfigure()


func _physics_process(_delta: float) -> void:
	# Resident authority snapshots can refresh while a brawl is active. Reapply
	# the conflict-owned pause before resident bodies take their physics step.
	for actor_id_value: Variant in _conflict_paused_actor_ids:
		var body := _actor_body(String(actor_id_value))
		if body != null:
			_set_body_paused(body, true)


func register_external_actor(
	actor_id: String,
	authority_node: Node2D,
	visual_root: CanvasItem = null,
) -> Dictionary:
	if not _configured or _conflict_presentation == null:
		return _failure("CONFLICT_PRESENTATION_HOST_NOT_CONFIGURED")
	var normalized_id := actor_id.strip_edges()
	if normalized_id.is_empty() or authority_node == null:
		return _failure("CONFLICT_PRESENTATION_HOST_EXTERNAL_ACTOR_INVALID")
	if (
		_registered_resident_ids.has(normalized_id)
		or _registered_external_actor_ids.has(normalized_id)
	):
		return _failure("CONFLICT_PRESENTATION_HOST_ACTOR_ALREADY_REGISTERED")
	var resolved_visual := visual_root
	if resolved_visual == null:
		resolved_visual = authority_node
	var result := _conflict_presentation.call(
		"register_actor",
		normalized_id,
		authority_node,
		resolved_visual,
		"avatar",
	) as Dictionary
	if result.get("ok") != true:
		return result
	_registered_external_actor_ids[normalized_id] = {
		"authority": authority_node,
		"visual": resolved_visual,
	}
	if _conflict_paused_actor_ids.has(normalized_id):
		_set_body_paused(authority_node, true)
	return sync_now()


func unregister_external_actor(actor_id: String) -> void:
	var normalized_id := actor_id.strip_edges()
	if not _registered_external_actor_ids.has(normalized_id):
		return
	if _conflict_presentation != null:
		_conflict_presentation.call("unregister_actor", normalized_id)
	_registered_external_actor_ids.erase(normalized_id)
	_conflict_paused_actor_ids.erase(normalized_id)


func _register_existing_residents() -> void:
	var ids_value: Variant = _resident_presentation.call("get_resident_ids")
	if ids_value is not Array:
		return
	for resident_id_value: Variant in ids_value as Array:
		var resident_id := String(resident_id_value)
		var body_value: Variant = _resident_presentation.call(
			"get_body",
			resident_id,
		)
		if body_value is Node2D:
			_register_resident_body(resident_id, body_value as Node2D)


func _register_resident_body(resident_id: String, body: Node2D) -> void:
	var normalized_id := resident_id.strip_edges()
	if (
		normalized_id.is_empty()
		or body == null
		or _registered_resident_ids.has(normalized_id)
	):
		return
	var visual_root: CanvasItem = body
	if body.has_method("get_character_rig"):
		var rig_value: Variant = body.call("get_character_rig")
		if rig_value is CanvasItem:
			visual_root = rig_value as CanvasItem
	var result := _conflict_presentation.call(
		"register_actor",
		normalized_id,
		body,
		visual_root,
		"resident",
	) as Dictionary
	if result.get("ok") != true:
		conflict_visual_error.emit(result.duplicate(true))
		return
	_registered_resident_ids[normalized_id] = true
	if _conflict_paused_actor_ids.has(normalized_id):
		_set_body_paused(body, true)


func _on_resident_body_created(resident_id: String, body: Node2D) -> void:
	if not _configured:
		return
	_register_resident_body(resident_id, body)
	# Equal revisions are intentionally accepted by the renderer so a rebuilt
	# body immediately inherits the active cloud/hidden state.
	var result := sync_now()
	if result.get("ok") != true:
		conflict_visual_error.emit(result.duplicate(true))


func _on_resident_body_removed(resident_id: String) -> void:
	if not _configured:
		return
	var normalized_id := resident_id.strip_edges()
	if _conflict_presentation != null:
		_conflict_presentation.call("unregister_actor", normalized_id)
	_registered_resident_ids.erase(normalized_id)
	# Keep the active participant fact. If the resident body is rebuilt during
	# the same conflict, resident_body_created must immediately pause the new body.


func _on_conflict_projection_changed(projection: Dictionary) -> void:
	if not _configured:
		return
	var result := _apply_projection(projection)
	if result.get("ok") != true:
		conflict_visual_error.emit(result.duplicate(true))


func _apply_projection(projection: Dictionary) -> Dictionary:
	var result := _conflict_presentation.call(
		"apply_public_projection",
		projection,
	) as Dictionary
	if result.get("ok") != true:
		return result
	_sync_conflict_pauses(_presentation_paused_actor_ids())
	var snapshot := debug_snapshot()
	conflict_visuals_changed.emit(snapshot.duplicate(true))
	return {
		"ok": true,
		"errorCode": "",
		"confirmedRevision": int(result.get("confirmedRevision", -1)),
		"snapshot": snapshot,
	}


func _on_presentation_effect_state_changed(
	_effect_kind: String,
	_subject_id: String,
) -> void:
	if not _configured or _conflict_presentation == null:
		return
	_sync_conflict_pauses(_presentation_paused_actor_ids())
	conflict_visuals_changed.emit(debug_snapshot().duplicate(true))


func _presentation_paused_actor_ids() -> Dictionary:
	var result: Dictionary = {}
	if _conflict_presentation == null:
		return result
	var visuals := _conflict_presentation.call("debug_snapshot") as Dictionary
	for brawl_value: Variant in visuals.get("brawls", []) as Array:
		if brawl_value is not Dictionary:
			continue
		for actor_id_value: Variant in (
			(brawl_value as Dictionary).get("participantIds", []) as Array
		):
			var actor_id := String(actor_id_value).strip_edges()
			if not actor_id.is_empty():
				result[actor_id] = true
	for attack_value: Variant in visuals.get("avatarAttacks", []) as Array:
		if attack_value is not Dictionary:
			continue
		var attacker_id := String(
			(attack_value as Dictionary).get("attackerId", "")
		).strip_edges()
		if not attacker_id.is_empty():
			result[attacker_id] = true
	return result


func _sync_conflict_pauses(next_paused_ids: Dictionary) -> void:
	var previous_ids := _sorted_dictionary_keys(_conflict_paused_actor_ids)
	for actor_id: String in previous_ids:
		if next_paused_ids.has(actor_id):
			continue
		var body := _actor_body(actor_id)
		if body != null:
			_set_body_paused(body, _resident_world_paused())
	for actor_id_value: Variant in next_paused_ids:
		var actor_id := String(actor_id_value)
		var body := _actor_body(actor_id)
		if body != null:
			_set_body_paused(body, true)
	_conflict_paused_actor_ids = next_paused_ids.duplicate()


func _release_all_conflict_pauses() -> void:
	var restore_paused := _resident_world_paused()
	for actor_id_value: Variant in _conflict_paused_actor_ids:
		var body := _actor_body(String(actor_id_value))
		if body != null:
			_set_body_paused(body, restore_paused)
	_conflict_paused_actor_ids.clear()


func _actor_body(actor_id: String) -> Node2D:
	if _registered_external_actor_ids.has(actor_id):
		var record := _registered_external_actor_ids[actor_id] as Dictionary
		var authority := record.get("authority") as Node2D
		if authority != null and is_instance_valid(authority):
			return authority
	return _resident_body(actor_id)


func _resident_body(resident_id: String) -> Node2D:
	if _resident_presentation == null:
		return null
	var body_value: Variant = _resident_presentation.call(
		"get_body",
		resident_id,
	)
	if body_value is Node2D:
		return body_value as Node2D
	return null


func _set_body_paused(body: Node2D, paused: bool) -> void:
	if body != null and body.has_method("set_presentation_paused"):
		body.call("set_presentation_paused", paused)


func _resident_world_paused() -> bool:
	if _resident_presentation == null:
		return false
	var snapshot_value: Variant = _resident_presentation.call(
		"get_presentation_snapshot"
	)
	if snapshot_value is Dictionary:
		return bool((snapshot_value as Dictionary).get("worldPaused", false))
	return false


func _failure(error_code: String, meta: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"meta": meta.duplicate(true),
	}


func _sorted_dictionary_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key_value: Variant in values:
		result.append(String(key_value))
	result.sort()
	return result
