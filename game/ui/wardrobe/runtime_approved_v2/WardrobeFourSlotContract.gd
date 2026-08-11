class_name WardrobeFourSlotContract
extends RefCounted


const SLOT_ORDER: Array[String] = ["hair", "top", "bottom", "shoes"]
const RIG_PROVIDER_ID := "resident_2d_rig_v1"


func configure_handoff(input: Dictionary) -> Dictionary:
	var required_fields: Array[String] = [
		"sourceScope",
		"draftId",
		"returnRevision",
		"returnIntent",
		"selection",
		"loadoutId",
		"slotOrder",
		"catalogPath",
	]
	for field_id: String in required_fields:
		if not input.has(field_id):
			return _failure("WARDROBE_HANDOFF_FIELD_MISSING", {"field": field_id})

	var slot_order_value: Variant = input.get("slotOrder", [])
	if not slot_order_value is Array:
		return _failure("WARDROBE_SLOT_ORDER_INVALID")
	var slot_order: Array = slot_order_value as Array
	if slot_order != SLOT_ORDER:
		return _failure(
			"WARDROBE_SLOT_ORDER_UNSUPPORTED",
			{"expected": SLOT_ORDER.duplicate(), "actual": slot_order.duplicate(true)},
		)

	var selection_value: Variant = input.get("selection", {})
	if not selection_value is Dictionary:
		return _failure("WARDROBE_SELECTION_INVALID")
	var selection: Dictionary = (selection_value as Dictionary).duplicate(true)
	var selection_error: String = _selection_error(selection)
	if not selection_error.is_empty():
		return _failure(selection_error)

	var source_scope: String = String(input.get("sourceScope", "")).strip_edges()
	var draft_id: String = String(input.get("draftId", "")).strip_edges()
	var return_intent: String = String(input.get("returnIntent", "")).strip_edges()
	var catalog_path: String = String(input.get("catalogPath", "")).strip_edges()
	var provider_id: String = String(
		input.get("assetProviderId", RIG_PROVIDER_ID)
	).strip_edges()
	var cancel_intent: String = String(
		input.get("cancelIntent", "wardrobe.cancel")
	).strip_edges()
	if source_scope.is_empty() or draft_id.is_empty() or return_intent.is_empty():
		return _failure("WARDROBE_HANDOFF_IDENTITY_INVALID")
	if provider_id != RIG_PROVIDER_ID:
		return _failure("WARDROBE_ASSET_PROVIDER_UNSUPPORTED")
	if (
		catalog_path.contains("paper_doll_64")
		or catalog_path.contains("player_avatar_white")
	):
		return _failure("WARDROBE_LEGACY_ASSET_REJECTED")

	var normalized: Dictionary = {
		"sourceScope": source_scope,
		"draftId": draft_id,
		"returnRevision": int(input.get("returnRevision", 0)),
		"returnIntent": return_intent,
		"cancelIntent": cancel_intent,
		"selection": selection,
		"loadoutId": String(input.get("loadoutId", "")),
		"slotOrder": SLOT_ORDER.duplicate(),
		"catalogPath": catalog_path,
		"assetProviderId": RIG_PROVIDER_ID,
	}
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"handoff": normalized,
		"selection": selection.duplicate(true),
	}


func build_save_payload(handoff: Dictionary, selection: Dictionary) -> Dictionary:
	var handoff_result: Dictionary = configure_handoff(handoff)
	if not bool(handoff_result.get("ok", false)):
		return handoff_result
	var selection_error: String = _selection_error(selection)
	if not selection_error.is_empty():
		return _failure(selection_error)

	var normalized: Dictionary = handoff_result.get("handoff", {}) as Dictionary
	var payload: Dictionary = {
		"sourceScope": String(normalized.get("sourceScope", "")),
		"draftId": String(normalized.get("draftId", "")),
		"returnRevision": int(normalized.get("returnRevision", 0)),
		"revision": int(normalized.get("returnRevision", 0)),
		"selection": selection.duplicate(true),
		"loadoutId": String(normalized.get("loadoutId", "")),
		"slotOrder": SLOT_ORDER.duplicate(),
		"catalogPath": String(normalized.get("catalogPath", "")),
		"assetProviderId": RIG_PROVIDER_ID,
		"formalReady": true,
	}
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"returnIntent": String(normalized.get("returnIntent", "")),
		"payload": payload,
	}


func build_cancel_payload(handoff: Dictionary) -> Dictionary:
	var handoff_result: Dictionary = configure_handoff(handoff)
	if not bool(handoff_result.get("ok", false)):
		return handoff_result
	var normalized: Dictionary = handoff_result.get("handoff", {}) as Dictionary
	var original_selection: Dictionary = (
		normalized.get("selection", {}) as Dictionary
	).duplicate(true)
	return {
		"ok": true,
		"errorCode": "",
		"retryable": false,
		"cancelIntent": String(normalized.get("cancelIntent", "wardrobe.cancel")),
		"payload": {
			"sourceScope": String(normalized.get("sourceScope", "")),
			"draftId": String(normalized.get("draftId", "")),
			"returnRevision": int(normalized.get("returnRevision", 0)),
			"selection": original_selection,
			"loadoutId": String(normalized.get("loadoutId", "")),
			"slotOrder": SLOT_ORDER.duplicate(),
			"catalogPath": String(normalized.get("catalogPath", "")),
			"assetProviderId": RIG_PROVIDER_ID,
			"cancelled": true,
			"formalReady": true,
		},
	}


func _selection_error(selection: Dictionary) -> String:
	if selection.size() < SLOT_ORDER.size():
		return "WARDROBE_SELECTION_INCOMPLETE"
	for slot_id: String in SLOT_ORDER:
		if not selection.has(slot_id):
			return "WARDROBE_SELECTION_SLOT_MISSING"
		if String(selection.get(slot_id, "")).strip_edges().is_empty():
			return "WARDROBE_SELECTION_VALUE_INVALID"
	return ""


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"retryable": false,
		"details": details.duplicate(true),
	}
