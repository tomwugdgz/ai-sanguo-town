extends RefCounted


const WORLD_SCALARS := preload("res://world/data/town/TownWorldScalars.gd")
const VALIDATOR := preload("res://world/data/town/TownWorldCatalogValidator.gd")


static func build_from_source(source_dir: String) -> Dictionary:
	if not VALIDATOR.validate_source_directory(source_dir).is_empty():
		return {}
	var documents := VALIDATOR.load_source_documents(source_dir)
	if documents.is_empty():
		return {}
	return build_from_documents(
		documents.get("places", {}) as Dictionary,
		documents.get("spaces", {}) as Dictionary,
	)


static func build_from_documents(
	places_document: Dictionary,
	spaces_document: Dictionary,
) -> Dictionary:
	if not VALIDATOR.validate_documents(places_document, spaces_document).is_empty():
		return {}
	return {
		"schemaVersion": 1,
		"worldId": "town",
		"mapSpaces": _sorted_dictionaries(
			spaces_document.get("spaces", []) as Array,
			"id",
		),
		"places": _sorted_dictionaries(
			places_document.get("places", []) as Array,
			"name",
		),
	}


static func _sorted_dictionaries(values: Array, key: String) -> Array:
	return WORLD_SCALARS.sorted_dictionaries(values, key)
