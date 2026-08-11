class_name PaperDoll64Sprite
extends Sprite2D


signal catalog_loaded(catalog_path: String)
signal loadout_changed(loadout_id: String)


const DEFAULT_CATALOG_PATH := "res://assets/characters/paper_doll_64/wardrobe_catalog.json"
const FRAME_SEQUENCE: Array[int] = [0, 1, 2, 3]
const DIRECTION_NAMES: Array[String] = ["down", "right", "up", "left"]
const SLOT_NAMES: Array[String] = ["head", "top_hands", "bottom", "shoes"]
const DEFAULT_CYCLE_DISTANCE := 64.0
const DEFAULT_FRAME_DURATION_SECONDS := 0.2

@export_file("*.json") var catalog_path := DEFAULT_CATALOG_PATH
@export var cycle_distance := DEFAULT_CYCLE_DISTANCE

var _catalog: Dictionary = {}
var _loadout_by_id: Dictionary = {}
var _loadout_by_selection: Dictionary = {}
var _current_loadout_id := ""
var _direction_row := 0
var _frame_sequence_index := 0
var _distance_progress := 0.0
var _frame_duration_seconds := DEFAULT_FRAME_DURATION_SECONDS


func _ready() -> void:
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not catalog_path.is_empty():
		load_catalog(catalog_path)


func load_catalog(path: String) -> bool:
	var candidate := _read_json(path)
	if candidate.is_empty():
		push_error("PaperDoll64Sprite catalog is missing or invalid JSON: %s" % path)
		return false
	if not _validate_catalog(candidate):
		push_error("PaperDoll64Sprite catalog contract mismatch: %s" % path)
		return false

	var candidate_loadouts: Dictionary = {}
	var candidate_selections: Dictionary = {}
	for value in candidate["loadouts"] as Array:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var item := value as Dictionary
		var loadout_id := String(item.get("loadoutId", ""))
		var atlas_path := String(item.get("atlas", ""))
		if loadout_id.is_empty() or atlas_path.is_empty():
			return false
		candidate_loadouts[loadout_id] = item.duplicate(true)
		var selection_value: Variant = item.get("selection", {})
		if typeof(selection_value) == TYPE_DICTIONARY and not (selection_value as Dictionary).is_empty():
			var key := _selection_key(selection_value as Dictionary)
			if key.is_empty() or candidate_selections.has(key):
				return false
			candidate_selections[key] = loadout_id

	_catalog = candidate.duplicate(true)
	_loadout_by_id = candidate_loadouts
	_loadout_by_selection = candidate_selections
	catalog_path = path
	hframes = 4
	vframes = 4
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var root: Array = _catalog["root"]
	position = -Vector2(float(root[0]), float(root[1]))
	_direction_row = 0
	_frame_sequence_index = 0
	_distance_progress = 0.0
	_frame_duration_seconds = maxf(0.05, float(candidate.get("frameDurationMs", 200)) / 1000.0)
	var default_loadout_id := String(_catalog["defaultLoadoutId"])
	if not set_loadout(default_loadout_id):
		push_error("PaperDoll64Sprite default atlas failed to load: %s" % default_loadout_id)
		_catalog.clear()
		_loadout_by_id.clear()
		_loadout_by_selection.clear()
		return false
	catalog_loaded.emit(path)
	return true


func set_loadout(loadout_id: String) -> bool:
	if not _loadout_by_id.has(loadout_id):
		return false
	var atlas_path := String((_loadout_by_id[loadout_id] as Dictionary)["atlas"])
	if not atlas_path.begins_with("res://"):
		atlas_path = "res://" + atlas_path
	var atlas: Texture2D = _load_texture(atlas_path)
	if atlas == null or atlas.get_size() != Vector2(256, 320):
		return false
	var previous_coords := frame_coords
	texture = atlas
	hframes = 4
	vframes = 4
	frame_coords = previous_coords
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_current_loadout_id = loadout_id
	loadout_changed.emit(loadout_id)
	return true


func set_selection(selection: Dictionary) -> bool:
	var key := _selection_key(selection)
	if key.is_empty() or not _loadout_by_selection.has(key):
		return false
	return set_loadout(String(_loadout_by_selection[key]))


func get_current_selection() -> Dictionary:
	if not _loadout_by_id.has(_current_loadout_id):
		return {}
	var item := _loadout_by_id[_current_loadout_id] as Dictionary
	var selection_value: Variant = item.get("selection", {})
	return (selection_value as Dictionary).duplicate(true) if typeof(selection_value) == TYPE_DICTIONARY else {}


func get_slot_variants(slot_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not SLOT_NAMES.has(slot_id):
		return result
	var all_variants_value: Variant = _catalog.get("slotVariants", {})
	if typeof(all_variants_value) != TYPE_DICTIONARY:
		return result
	var values: Variant = (all_variants_value as Dictionary).get(slot_id, [])
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values as Array:
		if typeof(value) == TYPE_DICTIONARY:
			var variant := value as Dictionary
			result.append({
				"variantId": String(variant.get("variantId", "")),
				"displayName": String(variant.get("displayName", "")),
				"previewLoadoutId": String(
					variant.get("previewLoadoutId", ""),
				),
			})
	return result


func get_preset_loadout_ids() -> Array[String]:
	var result: Array[String] = []
	for value in _catalog.get("presetLoadoutIds", []) as Array:
		result.append(String(value))
	return result


func set_motion(direction: Vector2, distance_delta: float) -> void:
	if direction.length_squared() <= 0.000001:
		_frame_sequence_index = 0
		_distance_progress = 0.0
		_sync_frame()
		return

	_direction_row = _direction_row_from_vector(direction)
	if distance_delta > 0.0 and cycle_distance > 0.0:
		_distance_progress = fposmod(_distance_progress + distance_delta, cycle_distance)
		var segment_distance := cycle_distance / float(FRAME_SEQUENCE.size())
		_frame_sequence_index = int(floor(_distance_progress / segment_distance)) % FRAME_SEQUENCE.size()
	_sync_frame()


func configure_motion_speed(world_speed: float) -> void:
	if world_speed <= 0.0:
		return
	cycle_distance = world_speed * _frame_duration_seconds * float(FRAME_SEQUENCE.size())


func get_frame_duration_seconds() -> float:
	return _frame_duration_seconds


func set_preview_frame(frame_column: int) -> void:
	_frame_sequence_index = maxi(0, FRAME_SEQUENCE.find(clampi(frame_column, 0, 3)))
	_sync_frame()


func set_preview_direction(direction_row: int) -> void:
	_direction_row = clampi(direction_row, 0, 3)
	_sync_frame()


func get_loadout_ids() -> Array[String]:
	var result: Array[String] = []
	for value in _catalog.get("loadouts", []) as Array:
		if typeof(value) == TYPE_DICTIONARY:
			result.append(String((value as Dictionary).get("loadoutId", "")))
	return result


func get_current_loadout_id() -> String:
	return _current_loadout_id


func get_direction_row() -> int:
	return _direction_row


func get_direction_name() -> String:
	return DIRECTION_NAMES[_direction_row]


func is_catalog_ready() -> bool:
	return not _catalog.is_empty() and texture != null


func _sync_frame() -> void:
	frame_coords = Vector2i(FRAME_SEQUENCE[_frame_sequence_index], _direction_row)


func _direction_row_from_vector(direction: Vector2) -> int:
	if absf(direction.x) > absf(direction.y):
		return 1 if direction.x > 0.0 else 3
	return 0 if direction.y > 0.0 else 2


func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _validate_catalog(candidate: Dictionary) -> bool:
	if int(candidate.get("schemaVersion", 0)) != 2:
		return false
	if String(candidate.get("runtimeMode", "")) != "precompiled_single_sprite_atlas":
		return false
	if not _number_pair_matches(candidate.get("frame", []), 64, 80):
		return false
	if not _number_pair_matches(candidate.get("root", []), 32, 72):
		return false
	if not _number_pair_matches(candidate.get("sheet", []), 256, 320):
		return false
	if candidate.get("columnSequence", []) != ["neutral", "step_right", "neutral", "step_left"]:
		return false
	if int(candidate.get("frameDurationMs", 0)) <= 0:
		return false
	if typeof(candidate.get("loadouts")) != TYPE_ARRAY:
		return false
	if (candidate["loadouts"] as Array).is_empty():
		return false
	if typeof(candidate.get("presetLoadoutIds")) != TYPE_ARRAY:
		return false
	var loadout_by_id := {}
	for value: Variant in candidate["loadouts"] as Array:
		if not value is Dictionary:
			return false
		var loadout := value as Dictionary
		var loadout_id_value: Variant = loadout.get("loadoutId")
		var atlas_value: Variant = loadout.get("atlas")
		var preview_only_value: Variant = loadout.get("previewOnly")
		if (
			not loadout_id_value is String
			or (loadout_id_value as String).is_empty()
			or loadout_id_value != (loadout_id_value as String).strip_edges()
			or loadout_by_id.has(loadout_id_value)
			or not atlas_value is String
			or (atlas_value as String).is_empty()
			or atlas_value != (atlas_value as String).strip_edges()
			or not preview_only_value is bool
		):
			return false
		var atlas_path := _normalized_resource_path(atlas_value as String)
		if (
			not atlas_path.begins_with(
				"res://assets/characters/paper_doll_64/compiled/",
			)
			or atlas_path.contains("..")
		):
			return false
		loadout_by_id[loadout_id_value] = loadout
	var default_loadout_id_value: Variant = candidate.get("defaultLoadoutId")
	if (
		not default_loadout_id_value is String
		or not loadout_by_id.has(default_loadout_id_value)
		or bool(
			(loadout_by_id[default_loadout_id_value] as Dictionary).get(
				"previewOnly",
				true,
			)
		)
	):
		return false
	var default_atlas_path := _normalized_resource_path(
		String(
			(
				loadout_by_id[default_loadout_id_value] as Dictionary
			).get("atlas", ""),
		),
	)
	if not ResourceLoader.exists(default_atlas_path, "Texture2D"):
		return false
	var preset_ids := {}
	for preset_id_value: Variant in candidate["presetLoadoutIds"] as Array:
		if (
			not preset_id_value is String
			or (preset_id_value as String).is_empty()
			or preset_ids.has(preset_id_value)
			or not loadout_by_id.has(preset_id_value)
			or bool(
				(loadout_by_id[preset_id_value] as Dictionary).get(
					"previewOnly",
					true,
				)
			)
		):
			return false
		preset_ids[preset_id_value] = true
	var slot_variants_value: Variant = candidate.get("slotVariants")
	if not slot_variants_value is Dictionary:
		return false
	var slot_variants := slot_variants_value as Dictionary
	if not _has_exact_string_keys(slot_variants, SLOT_NAMES):
		return false
	for slot_id in SLOT_NAMES:
		var variants_value: Variant = slot_variants.get(slot_id)
		if not variants_value is Array or (variants_value as Array).is_empty():
			return false
		var variant_ids := {}
		for variant_value: Variant in variants_value as Array:
			if not variant_value is Dictionary:
				return false
			var variant := variant_value as Dictionary
			if not _has_exact_string_keys(
				variant,
				["variantId", "displayName", "previewLoadoutId"],
			):
				return false
			var variant_id_value: Variant = variant.get("variantId")
			var display_name_value: Variant = variant.get("displayName")
			var preview_loadout_id_value: Variant = variant.get(
				"previewLoadoutId",
			)
			if (
				not variant_id_value is String
				or (variant_id_value as String).is_empty()
				or variant_id_value
				!= (variant_id_value as String).strip_edges()
				or variant_ids.has(variant_id_value)
				or not display_name_value is String
				or (display_name_value as String).strip_edges().is_empty()
				or not preview_loadout_id_value is String
				or not loadout_by_id.has(preview_loadout_id_value)
			):
				return false
			var preview_loadout := (
				loadout_by_id[preview_loadout_id_value] as Dictionary
			)
			if bool(preview_loadout.get("previewOnly", true)):
				return false
			var preview_atlas_path := _normalized_resource_path(
				String(preview_loadout.get("atlas", "")),
			)
			if not ResourceLoader.exists(
				preview_atlas_path,
				"Texture2D",
			):
				return false
			var preview_selection_value: Variant = preview_loadout.get(
				"selection",
			)
			if (
				not preview_selection_value is Dictionary
				or (preview_selection_value as Dictionary).get(slot_id)
				!= variant_id_value
			):
				return false
			variant_ids[variant_id_value] = true
	return true


func _selection_key(selection: Dictionary) -> String:
	var parts := PackedStringArray()
	for slot_id in SLOT_NAMES:
		var variant_id := String(selection.get(slot_id, ""))
		if variant_id.is_empty():
			return ""
		parts.append("%s=%s" % [slot_id, variant_id])
	return "|".join(parts)


func _number_pair_matches(value: Variant, first: int, second: int) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return false
	var pair := value as Array
	return int(pair[0]) == first and int(pair[1]) == second


func _has_exact_string_keys(
	value: Dictionary,
	expected: Array[String],
) -> bool:
	if value.size() != expected.size():
		return false
	for key_value: Variant in value:
		if not key_value is String or not expected.has(key_value):
			return false
	return true


func _normalized_resource_path(path: String) -> String:
	return path if path.begins_with("res://") else "res://" + path


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)
