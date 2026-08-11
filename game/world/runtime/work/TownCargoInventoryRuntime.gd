class_name TownCargoInventoryRuntime
extends RefCounted


const RESULT_SHAPES := preload("res://world/contract/TownWorldResultShapes.gd")
const CHAIN_CATALOG := preload(
	"res://world/data/town/TownWorkChainCatalog.gd"
)
const LOT_STATES := [
	"awaiting_release",
	"available",
	"in_transit",
	"awaiting_receipt",
	"delivered",
	"cancelled",
]
const ORIGIN_KINDS := [
	"local_inventory",
	"external_supply",
	"world_result",
]
const TERMINAL_LOT_STATES := ["delivered", "cancelled"]
const MAX_TERMINAL_LOTS := 128


var _configured := false
var _known_places: Dictionary = {}
var _known_items: Dictionary = {}
var _base_supply_items: Dictionary = {}
var _base_service_items: Dictionary = {}
var _specialty_cargo_items: Dictionary = {}
var _external_supply_items: Dictionary = {}
var _external_supply_place_id := ""
var _opening_inventory: Dictionary = {}
var _inventories: Dictionary = {}
var _cargo_lots: Dictionary = {}
var _lot_sequence := 0
var _archive_summary := {
	"terminalLotCount": 0,
	"deliveredLotCount": 0,
	"cancelledLotCount": 0,
	"quantityByItem": {},
}


func configure(
	world_data: Dictionary,
	catalog: Dictionary = {},
) -> Dictionary:
	if _configured:
		return _failure("CARGO_RUNTIME_ALREADY_CONFIGURED")
	var resolved_catalog := (
		CHAIN_CATALOG.load_catalog()
		if catalog.is_empty()
		else catalog.duplicate(true)
	)
	if not CHAIN_CATALOG.validate(resolved_catalog).is_empty():
		return _failure("CARGO_CATALOG_INVALID")
	for place_value: Variant in world_data.get("places", []) as Array:
		if place_value is Dictionary:
			_known_places[String(
				(place_value as Dictionary).get("name", ""),
			)] = true
	for item_value: Variant in resolved_catalog.get(
		"itemKinds",
		[],
	) as Array:
		_known_items[String(item_value)] = true
	for item_value: Variant in resolved_catalog.get(
		"baseSupplyItems",
		[],
	) as Array:
		_base_supply_items[String(item_value)] = true
	for item_value: Variant in resolved_catalog.get(
		"baseServiceItems",
		[],
	) as Array:
		_base_service_items[String(item_value)] = true
	for item_value: Variant in resolved_catalog.get(
		"specialtyCargoItems",
		[],
	) as Array:
		_specialty_cargo_items[String(item_value)] = true
	var opening_inputs := (
		resolved_catalog.get("openingInputs", {}) as Dictionary
	)
	_external_supply_place_id = String(
		opening_inputs.get("externalSupplyPlaceId", ""),
	)
	for item_value: Variant in opening_inputs.get(
		"externalSupplyItems",
		[],
	) as Array:
		_external_supply_items[String(item_value)] = true
	_opening_inventory = (
		opening_inputs.get(
			"openingInventoryByPlace",
			{},
		) as Dictionary
	).duplicate(true)
	if (
		_known_places.is_empty()
		or _known_items.is_empty()
		or _specialty_cargo_items.is_empty()
		or not _known_places.has(_external_supply_place_id)
	):
		return _failure("CARGO_WORLD_DATA_INVALID")
	_configured = true
	return {
		"ok": true,
		"errorCode": "",
		"placeCount": _known_places.size(),
		"itemCount": _known_items.size(),
	}


func initialize_opening_stock() -> Dictionary:
	if not _configured:
		return _failure("CARGO_RUNTIME_NOT_CONFIGURED")
	if not _inventories.is_empty() or not _cargo_lots.is_empty():
		return _failure("CARGO_OPENING_STOCK_ALREADY_INITIALIZED")
	for place_value: Variant in _opening_inventory:
		var place_id := String(place_value)
		var source := (
			_opening_inventory.get(place_value, {}) as Dictionary
		)
		var inventory: Dictionary = {}
		for item_value: Variant in source:
			inventory[String(item_value)] = int(source.get(item_value, 0))
		_inventories[place_id] = inventory
	return {
		"ok": true,
		"errorCode": "",
		"snapshot": snapshot(),
	}


func create_local_lot(spec: Dictionary) -> Dictionary:
	return _create_lot(spec, "local_inventory")


func create_world_result_lot(spec: Dictionary) -> Dictionary:
	return _create_lot(spec, "world_result")


func create_external_supply_lot(spec: Dictionary) -> Dictionary:
	var prepared := spec.duplicate(true)
	prepared["sourcePlaceId"] = _external_supply_place_id
	return _create_lot(prepared, "external_supply")


func _create_lot(
	spec: Dictionary,
	origin_kind: String,
) -> Dictionary:
	if not _configured:
		return _failure("CARGO_RUNTIME_NOT_CONFIGURED")
	var item_id := String(spec.get("itemId", "")).strip_edges()
	var source_place_id := String(
		spec.get("sourcePlaceId", ""),
	).strip_edges()
	var destination_place_id := String(
		spec.get("destinationPlaceId", ""),
	).strip_edges()
	var quantity_value: Variant = spec.get("quantity")
	var created_at_value: Variant = spec.get("createdAtMinute")
	if (
		origin_kind not in ORIGIN_KINDS
		or not _known_items.has(item_id)
		or not _specialty_cargo_items.has(item_id)
		or not _known_places.has(source_place_id)
		or not _known_places.has(destination_place_id)
		or source_place_id == destination_place_id
		or typeof(quantity_value) != TYPE_INT
		or int(quantity_value) <= 0
		or typeof(created_at_value) != TYPE_INT
		or int(created_at_value) < 0
	):
		return _failure("CARGO_LOT_SPEC_INVALID")
	if (
		origin_kind == "external_supply"
		and not _external_supply_items.has(item_id)
	):
		return _failure("CARGO_EXTERNAL_ITEM_INVALID")
	var quantity := int(quantity_value)
	var awaiting_warehouse_release := (
		origin_kind == "local_inventory"
		and source_place_id == "码头仓库"
	)
	if origin_kind == "local_inventory":
		var source_quantity := inventory_quantity(
			source_place_id,
			item_id,
		)
		if source_quantity < quantity:
			return _failure("CARGO_SOURCE_STOCK_INSUFFICIENT")
		if not awaiting_warehouse_release:
			_set_inventory_quantity(
				source_place_id,
				item_id,
				source_quantity - quantity,
			)
	var requested_id := String(spec.get("lotId", "")).strip_edges()
	var lot_id := requested_id
	if lot_id.is_empty():
		_lot_sequence += 1
		lot_id = "cargo-lot-%06d" % _lot_sequence
	elif _cargo_lots.has(lot_id):
		return _failure("CARGO_LOT_ID_CONFLICT")
	var lot := {
		"lotId": lot_id,
		"itemId": item_id,
		"quantity": quantity,
		"sourcePlaceId": source_place_id,
		"destinationPlaceId": destination_place_id,
		"originKind": origin_kind,
		"state": (
			"awaiting_release"
			if awaiting_warehouse_release
			else "available"
		),
		"carrierResidentId": "",
		"releasedByResidentId": "",
		"releasedAtMinute": -1,
		"createdAtMinute": int(created_at_value),
		"pickedUpAtMinute": -1,
		"deliveredAtMinute": -1,
		"cancelledAtMinute": -1,
		"receivedByResidentId": "",
		"receivedAtMinute": -1,
	}
	_cargo_lots[lot_id] = lot
	return _success(lot)


func release(
	lot_id: String,
	resident_id: String,
	current_place_id: String,
	now: int,
) -> Dictionary:
	var lot := _cargo_lots.get(lot_id, {}) as Dictionary
	var source_place_id := String(lot.get("sourcePlaceId", ""))
	var item_id := String(lot.get("itemId", ""))
	var quantity := int(lot.get("quantity", 0))
	if (
		lot.is_empty()
		or String(lot.get("state", "")) != "awaiting_release"
		or String(lot.get("originKind", "")) != "local_inventory"
		or source_place_id != "码头仓库"
		or current_place_id != source_place_id
		or resident_id.strip_edges().is_empty()
		or now < int(lot.get("createdAtMinute", 0))
		or (
			_specialty_cargo_items.has(item_id)
			and inventory_quantity(source_place_id, item_id) < quantity
		)
	):
		return _failure("CARGO_RELEASE_INVALID")
	if _specialty_cargo_items.has(item_id):
		_set_inventory_quantity(
			source_place_id,
			item_id,
			inventory_quantity(source_place_id, item_id) - quantity,
		)
	var updated := lot.duplicate(true)
	updated["state"] = "available"
	updated["releasedByResidentId"] = resident_id.strip_edges()
	updated["releasedAtMinute"] = now
	_cargo_lots[lot_id] = updated
	return _success(updated)


func pickup(
	lot_id: String,
	resident_id: String,
	current_place_id: String,
	now: int,
) -> Dictionary:
	var lot := _cargo_lots.get(lot_id, {}) as Dictionary
	if (
		lot.is_empty()
		or String(lot.get("state", "")) != "available"
		or resident_id.strip_edges().is_empty()
		or current_place_id != String(lot.get("sourcePlaceId", ""))
		or now < int(lot.get("createdAtMinute", 0))
	):
		return _failure("CARGO_PICKUP_INVALID")
	var updated := lot.duplicate(true)
	updated["state"] = "in_transit"
	updated["carrierResidentId"] = resident_id.strip_edges()
	updated["pickedUpAtMinute"] = now
	_cargo_lots[lot_id] = updated
	return _success(updated)


func deliver(
	lot_id: String,
	resident_id: String,
	current_place_id: String,
	now: int,
) -> Dictionary:
	var lot := _cargo_lots.get(lot_id, {}) as Dictionary
	if (
		lot.is_empty()
		or String(lot.get("state", "")) != "in_transit"
		or String(lot.get("carrierResidentId", ""))
		!= resident_id.strip_edges()
		or current_place_id
		!= String(lot.get("destinationPlaceId", ""))
		or now < int(lot.get("pickedUpAtMinute", 0))
	):
		return _failure("CARGO_DELIVERY_INVALID")
	var updated := lot.duplicate(true)
	updated["state"] = "awaiting_receipt"
	updated["deliveredAtMinute"] = now
	_cargo_lots[lot_id] = updated
	return _success(updated)


func receive(
	lot_id: String,
	resident_id: String,
	current_place_id: String,
	now: int,
) -> Dictionary:
	var lot := _cargo_lots.get(lot_id, {}) as Dictionary
	if (
		lot.is_empty()
		or String(lot.get("state", "")) != "awaiting_receipt"
		or resident_id.strip_edges().is_empty()
		or current_place_id
		!= String(lot.get("destinationPlaceId", ""))
		or now < int(lot.get("deliveredAtMinute", 0))
	):
		return _failure("CARGO_RECEIPT_INVALID")
	var destination_place := String(
		lot.get("destinationPlaceId", ""),
	)
	var item_id := String(lot.get("itemId", ""))
	if _specialty_cargo_items.has(item_id):
		_set_inventory_quantity(
			destination_place,
			item_id,
			inventory_quantity(destination_place, item_id)
				+ int(lot.get("quantity", 0)),
		)
	var updated := lot.duplicate(true)
	updated["state"] = "delivered"
	updated["receivedByResidentId"] = resident_id.strip_edges()
	updated["receivedAtMinute"] = now
	_cargo_lots[lot_id] = updated
	_compact_terminal_lots()
	return _success(updated)


func cancel_available_lot(
	lot_id: String,
	now: int,
) -> Dictionary:
	var lot := _cargo_lots.get(lot_id, {}) as Dictionary
	if (
		lot.is_empty()
		or String(lot.get("state", "")) not in [
			"awaiting_release",
			"available",
		]
		or now < int(lot.get("createdAtMinute", 0))
	):
		return _failure("CARGO_CANCEL_INVALID")
	if (
		String(lot.get("state", "")) == "available"
		and _specialty_cargo_items.has(
			String(lot.get("itemId", "")),
		)
		and String(lot.get("originKind", "")) in [
			"local_inventory",
			"world_result",
		]
	):
		var source_place := String(lot.get("sourcePlaceId", ""))
		var item_id := String(lot.get("itemId", ""))
		_set_inventory_quantity(
			source_place,
			item_id,
			inventory_quantity(source_place, item_id)
				+ int(lot.get("quantity", 0)),
		)
	var updated := lot.duplicate(true)
	updated["state"] = "cancelled"
	updated["cancelledAtMinute"] = now
	_cargo_lots[lot_id] = updated
	_compact_terminal_lots()
	return _success(updated)


func inventory_quantity(place_id: String, item_id: String) -> int:
	return int(
		(_inventories.get(place_id, {}) as Dictionary).get(
			item_id,
			0,
		)
	)


func is_base_supply_item(item_id: String) -> bool:
	return _base_supply_items.has(item_id)


func is_base_service_item(item_id: String) -> bool:
	return _base_service_items.has(item_id)


func is_specialty_cargo_item(item_id: String) -> bool:
	return _specialty_cargo_items.has(item_id)


func apply_inventory_recipe(
	place_id: String,
	inputs: Dictionary,
	outputs: Dictionary,
) -> Dictionary:
	if (
		not _configured
		or not _known_places.has(place_id)
		or (inputs.is_empty() and outputs.is_empty())
	):
		return _failure("INVENTORY_RECIPE_INVALID")
	for item_value: Variant in inputs:
		var item_id := String(item_value)
		var quantity_value: Variant = inputs.get(item_value)
		if (
			not _specialty_cargo_items.has(item_id)
			or typeof(quantity_value) != TYPE_INT
			or int(quantity_value) <= 0
			or inventory_quantity(place_id, item_id)
			< int(quantity_value)
		):
			return _failure("INVENTORY_RECIPE_INPUT_INSUFFICIENT")
	for item_value: Variant in outputs:
		var item_id := String(item_value)
		var quantity_value: Variant = outputs.get(item_value)
		if (
			not _specialty_cargo_items.has(item_id)
			or typeof(quantity_value) != TYPE_INT
			or int(quantity_value) <= 0
		):
			return _failure("INVENTORY_RECIPE_INVALID")
	for item_value: Variant in inputs:
		var item_id := String(item_value)
		_set_inventory_quantity(
			place_id,
			item_id,
			inventory_quantity(place_id, item_id)
			- int(inputs.get(item_value, 0)),
		)
	for item_value: Variant in outputs:
		var item_id := String(item_value)
		_set_inventory_quantity(
			place_id,
			item_id,
			inventory_quantity(place_id, item_id)
			+ int(outputs.get(item_value, 0)),
		)
	return {
		"ok": true,
		"errorCode": "",
		"placeId": place_id,
		"consumed": inputs.duplicate(true),
		"produced": outputs.duplicate(true),
		"snapshot": snapshot(),
	}


func cargo_lot(lot_id: String) -> Dictionary:
	return (
		(_cargo_lots.get(lot_id, {}) as Dictionary).duplicate(true)
		if _cargo_lots.has(lot_id)
		else {}
	)


func lots_for_resident(resident_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for lot_value: Variant in _cargo_lots.values():
		var lot := lot_value as Dictionary
		if (
			String(lot.get("state", "")) == "in_transit"
			and String(lot.get("carrierResidentId", ""))
			== resident_id
		):
			result.append(lot.duplicate(true))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("lotId", "")) < String(
				right.get("lotId", "")
			)
	)
	return result


func snapshot() -> Dictionary:
	var inventory_projection: Dictionary = {}
	var place_ids: Array[String] = []
	for place_value: Variant in _inventories:
		place_ids.append(String(place_value))
	place_ids.sort()
	for place_id: String in place_ids:
		inventory_projection[place_id] = (
			_inventories.get(place_id, {}) as Dictionary
		).duplicate(true)
	var lots: Array[Dictionary] = []
	var lot_ids: Array[String] = []
	for lot_value: Variant in _cargo_lots:
		lot_ids.append(String(lot_value))
	lot_ids.sort()
	for lot_id: String in lot_ids:
		lots.append(
			(_cargo_lots.get(lot_id, {}) as Dictionary).duplicate(true),
		)
	return {
		"schemaVersion": 1,
		"inventories": inventory_projection,
		"cargoLots": lots,
		"lotSequence": _lot_sequence,
		"archiveSummary": _archive_summary.duplicate(true),
	}


func restore_snapshot(value: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CARGO_RUNTIME_NOT_CONFIGURED")
	if (
		int(value.get("schemaVersion", 0)) != 1
		or not value.get("inventories") is Dictionary
		or not value.get("cargoLots") is Array
		or typeof(value.get("lotSequence")) != TYPE_INT
		or int(value.get("lotSequence", -1)) < 0
		or not value.get("archiveSummary", {}) is Dictionary
	):
		return _failure("CARGO_SAVE_INVALID")
	var inventories: Dictionary = {}
	for place_value: Variant in (
		value.get("inventories", {}) as Dictionary
	):
		var place_id := String(place_value)
		var inventory_value: Variant = (
			value.get("inventories", {}) as Dictionary
		).get(place_value)
		if (
			not _known_places.has(place_id)
			or not inventory_value is Dictionary
		):
			return _failure("CARGO_SAVE_INVALID")
		var inventory: Dictionary = {}
		for item_value: Variant in inventory_value as Dictionary:
			var item_id := String(item_value)
			var quantity_value: Variant = (
				inventory_value as Dictionary
			).get(item_value)
			if not _specialty_cargo_items.has(item_id):
				# Older saves may contain exact counts for what are now infinite
				# base supplies. They are intentionally discarded during restore.
				continue
			if (
				typeof(quantity_value) != TYPE_INT
				or int(quantity_value) < 0
			):
				return _failure("CARGO_SAVE_INVALID")
			inventory[item_id] = int(quantity_value)
		inventories[place_id] = inventory
	var cargo_lots: Dictionary = {}
	for lot_value: Variant in value.get("cargoLots", []) as Array:
		if not lot_value is Dictionary:
			return _failure("CARGO_SAVE_INVALID")
		var lot := (lot_value as Dictionary).duplicate(true)
		if not lot.has("releasedByResidentId"):
			lot["releasedByResidentId"] = ""
		if not lot.has("releasedAtMinute"):
			lot["releasedAtMinute"] = -1
		if not _valid_saved_lot(lot) or cargo_lots.has(
			String(lot.get("lotId", "")),
		):
			return _failure("CARGO_SAVE_INVALID")
		cargo_lots[String(lot.get("lotId", ""))] = lot
	_inventories = inventories
	_cargo_lots = cargo_lots
	_lot_sequence = int(value.get("lotSequence", 0))
	_archive_summary = _normalized_archive_summary(
		value.get("archiveSummary", {}) as Dictionary,
	)
	if _archive_summary.is_empty():
		return _failure("CARGO_SAVE_INVALID")
	_compact_terminal_lots()
	return {
		"ok": true,
		"errorCode": "",
		"snapshot": snapshot(),
	}


func _compact_terminal_lots() -> void:
	var terminal_lots: Array[Dictionary] = []
	for value: Variant in _cargo_lots.values():
		var lot := value as Dictionary
		if String(lot.get("state", "")) in TERMINAL_LOT_STATES:
			terminal_lots.append(lot)
	terminal_lots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_minute := _terminal_lot_minute(a)
		var b_minute := _terminal_lot_minute(b)
		if a_minute != b_minute:
			return a_minute > b_minute
		return String(a.get("lotId", "")) > String(b.get("lotId", ""))
	)
	for index in range(MAX_TERMINAL_LOTS, terminal_lots.size()):
		var lot := terminal_lots[index] as Dictionary
		_archive_terminal_lot(lot)
		_cargo_lots.erase(String(lot.get("lotId", "")))


func _terminal_lot_minute(lot: Dictionary) -> int:
	if String(lot.get("state", "")) == "delivered":
		return int(lot.get("receivedAtMinute", -1))
	return int(lot.get("cancelledAtMinute", -1))


func _archive_terminal_lot(lot: Dictionary) -> void:
	_archive_summary["terminalLotCount"] = int(
		_archive_summary.get("terminalLotCount", 0),
	) + 1
	var state := String(lot.get("state", ""))
	var state_key := (
		"deliveredLotCount" if state == "delivered" else "cancelledLotCount"
	)
	_archive_summary[state_key] = int(
		_archive_summary.get(state_key, 0),
	) + 1
	var quantity_by_item := (
		_archive_summary.get("quantityByItem", {}) as Dictionary
	).duplicate(true)
	var item_id := String(lot.get("itemId", ""))
	quantity_by_item[item_id] = int(quantity_by_item.get(item_id, 0)) + int(
		lot.get("quantity", 0),
	)
	_archive_summary["quantityByItem"] = quantity_by_item


func _normalized_archive_summary(value: Dictionary) -> Dictionary:
	var result := {
		"terminalLotCount": 0,
		"deliveredLotCount": 0,
		"cancelledLotCount": 0,
		"quantityByItem": {},
	}
	for key: String in [
		"terminalLotCount",
		"deliveredLotCount",
		"cancelledLotCount",
	]:
		var count_value: Variant = value.get(key, 0)
		if typeof(count_value) != TYPE_INT or int(count_value) < 0:
			return {}
		result[key] = int(count_value)
	var quantity_value: Variant = value.get("quantityByItem", {})
	if not quantity_value is Dictionary:
		return {}
	var quantity_by_item: Dictionary = {}
	for item_value: Variant in quantity_value as Dictionary:
		var item_id := String(item_value)
		var quantity: Variant = (quantity_value as Dictionary).get(item_value)
		if (
			not _known_items.has(item_id)
			or typeof(quantity) != TYPE_INT
			or int(quantity) < 0
		):
			return {}
		quantity_by_item[item_id] = int(quantity)
	result["quantityByItem"] = quantity_by_item
	return result


func _valid_saved_lot(lot: Dictionary) -> bool:
	return (
		not String(lot.get("lotId", "")).is_empty()
		and _known_items.has(String(lot.get("itemId", "")))
		and _known_places.has(String(lot.get("sourcePlaceId", "")))
		and _known_places.has(
			String(lot.get("destinationPlaceId", "")),
		)
		and String(lot.get("sourcePlaceId", ""))
		!= String(lot.get("destinationPlaceId", ""))
		and typeof(lot.get("quantity")) == TYPE_INT
		and int(lot.get("quantity", 0)) > 0
		and String(lot.get("originKind", "")) in ORIGIN_KINDS
		and String(lot.get("state", "")) in LOT_STATES
		and typeof(lot.get("carrierResidentId")) == TYPE_STRING
		and typeof(lot.get("releasedByResidentId", "")) == TYPE_STRING
		and typeof(lot.get("releasedAtMinute", -1)) == TYPE_INT
		and typeof(lot.get("createdAtMinute")) == TYPE_INT
		and typeof(lot.get("pickedUpAtMinute")) == TYPE_INT
		and typeof(lot.get("deliveredAtMinute")) == TYPE_INT
		and typeof(lot.get("cancelledAtMinute")) == TYPE_INT
		and typeof(lot.get("receivedByResidentId")) == TYPE_STRING
		and typeof(lot.get("receivedAtMinute")) == TYPE_INT
	)


func _set_inventory_quantity(
	place_id: String,
	item_id: String,
	quantity: int,
) -> void:
	var inventory := (
		_inventories.get(place_id, {}) as Dictionary
	).duplicate(true)
	inventory[item_id] = maxi(quantity, 0)
	_inventories[place_id] = inventory


func _success(lot: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"errorCode": "",
		"lot": lot.duplicate(true),
		"snapshot": snapshot(),
	}


func _failure(error_code: String) -> Dictionary:
	return RESULT_SHAPES.failure_minimal(error_code)
