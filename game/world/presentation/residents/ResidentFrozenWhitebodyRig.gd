class_name ResidentFrozenWhitebodyRig
extends Node2D


const MOTION_FACING_CONFIRM_SECONDS := 0.08
const MOTION_FACING_CONFIRM_DISTANCE := 10.0

const ASSET_ROOT := (
	"res://assets/characters/resident_2d_rig_v1/direction_branches/"
	+ "identity_unification_v1_pending/turntable_strip_v1"
)
const FREEZE_MANIFEST_PATH := (
	ASSET_ROOT + "/production_frozen_v2/whitebody_freeze_manifest_v2.json"
)
const RIG_CONTRACT_PATH := ASSET_ROOT + "/rig_contract_v1.json"
const RIG_MANIFEST_PATTERN := ASSET_ROOT + "/rig_v1/%s/rig_manifest.json"
const WARDROBE_ROOT := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1"
)
const WARDROBE_CATALOG_PATH := WARDROBE_ROOT + "/wardrobe_catalog.json"
const WARDROBE_SCHEMA := "ai-town.resident-wardrobe.v1"
const RIG_MANIFEST_SCHEMA := "ai-town.direction-articulated-rig-manifest.v1"
const FREEZE_MANIFEST_SCHEMA := "ai-town.resident-whitebody-freeze.v2"
const RUNTIME_CONTRACT_STATUS := "runtime_contract_validated"
const SOURCE_DIRECTIONS: Array[String] = ["down", "right", "up"]
const ALL_DIRECTIONS: Array[String] = ["down", "right", "up", "left"]
const DISPLAY_HEIGHT := 152.0
const SOURCE_BODY_HEIGHT := 525.0
const DISPLAY_SCALE := DISPLAY_HEIGHT / SOURCE_BODY_HEIGHT
const WALK_CYCLE_DISTANCE := 128.0
const COMPLETE_SET_FRAME_SIZE := Vector2(512.0, 512.0)
const COMPLETE_SET_SHEET_SIZE := Vector2(1536.0, 2048.0)
const COMPLETE_SET_IDLE_FRAME := 1
const COMPLETE_SET_SOURCE_BODY_HEIGHT := 430.0
# The atlas alpha ends at source y=469. ResidentCharacterBody's authoritative
# ground point is the bottom of its feet collision, six display pixels below
# the body origin, so place the visible shoe sole on that same point.
const COMPLETE_SET_SOURCE_FOOT_Y := 452.0
const COMPLETE_SET_DISPLAY_SCALE := (
	DISPLAY_HEIGHT / COMPLETE_SET_SOURCE_BODY_HEIGHT
)
const IDLE_BREATH_CYCLE_SECONDS := 1.65
const IDLE_BREATH_DISPLAY_PIXELS := 2.0
const SLEEP_HEAD_BODY_FRACTION := 0.44

const BONE_SPECS: Array[Dictionary] = [
	{"id": "root", "parent": "", "joint": "root", "part": ""},
	{"id": "pelvis", "parent": "root", "joint": "pelvis", "part": "pelvis"},
	{"id": "torso", "parent": "pelvis", "joint": "torso", "part": "torso"},
	{"id": "head", "parent": "torso", "joint": "head", "part": "head"},
	{"id": "clavicle_l", "parent": "torso", "joint": "clavicle_l", "part": ""},
	{
		"id": "upper_arm_l",
		"parent": "clavicle_l",
		"joint": "shoulder_l",
		"part": "upper_arm_l",
	},
	{
		"id": "forearm_l",
		"parent": "upper_arm_l",
		"joint": "elbow_l",
		"part": "forearm_l",
	},
	{"id": "hand_l", "parent": "forearm_l", "joint": "wrist_l", "part": "hand_l"},
	{"id": "clavicle_r", "parent": "torso", "joint": "clavicle_r", "part": ""},
	{
		"id": "upper_arm_r",
		"parent": "clavicle_r",
		"joint": "shoulder_r",
		"part": "upper_arm_r",
	},
	{
		"id": "forearm_r",
		"parent": "upper_arm_r",
		"joint": "elbow_r",
		"part": "forearm_r",
	},
	{"id": "hand_r", "parent": "forearm_r", "joint": "wrist_r", "part": "hand_r"},
	{"id": "thigh_l", "parent": "pelvis", "joint": "hip_l", "part": "thigh_l"},
	{"id": "shin_l", "parent": "thigh_l", "joint": "knee_l", "part": "shin_l"},
	{"id": "foot_l", "parent": "shin_l", "joint": "ankle_l", "part": "foot_l"},
	{"id": "thigh_r", "parent": "pelvis", "joint": "hip_r", "part": "thigh_r"},
	{"id": "shin_r", "parent": "thigh_r", "joint": "knee_r", "part": "shin_r"},
	{"id": "foot_r", "parent": "shin_r", "joint": "ankle_r", "part": "foot_r"},
]

static var _texture_cache: Dictionary = {}
static var _sha256_cache: Dictionary = {}

var _direction_roots: Dictionary = {}
var _skeletons: Dictionary = {}
var _bones: Dictionary = {}
var _rest_positions: Dictionary = {}
var _head_anchors: Dictionary = {}
var _part_sprites: Dictionary = {}
var _source_state: Dictionary = {}
var _active_direction := "down"
var _walk_phase := 0.0
var _motion_blend := 0.0
var _activity_type := ""
var _activity_family := ""
var _activity_phase := 0.0
var _contract_valid := false
var _freeze_state: Dictionary = {}
var _wardrobe_catalog: Dictionary = {}
var _loadout_by_id: Dictionary = {}
var _resident_assignments: Dictionary = {}
var _appearance_aliases: Dictionary = {}
var _active_loadout_id := ""
var _motion_facing_candidate := ""
var _motion_facing_candidate_seconds := 0.0
var _motion_facing_candidate_distance := 0.0
var _runtime_built := false
var _complete_set_sprite: Sprite2D
var _complete_set_sheet_path := ""
var _complete_set_base_position := Vector2.ZERO
var _idle_breath_phase := 0.0
var _activity_effect: ResidentActivityEffect
var _sleep_head_sprite: Sprite2D
var _sleeping := false


func _ready() -> void:
	_build_runtime()
	if _contract_valid:
		_contract_valid = set_resident_appearance("", "")
	set_direction("down")


func set_direction(direction_id: String) -> bool:
	if direction_id not in ALL_DIRECTIONS:
		return false
	var changed := direction_id != _active_direction
	_active_direction = direction_id
	for source_direction: String in _direction_roots:
		var direction_root := _direction_roots[source_direction] as Node2D
		direction_root.visible = (
			not _sleeping
			and _complete_set_sprite == null
			and (
				source_direction == direction_id
				or (source_direction == "right" and direction_id == "left")
			)
		)
		if source_direction == "right":
			direction_root.scale = Vector2(
				-DISPLAY_SCALE if direction_id == "left" else DISPLAY_SCALE,
				DISPLAY_SCALE,
			)
	if _complete_set_sprite != null:
		_refresh_complete_set_frame()
	_refresh_activity_effect()
	if changed:
		_apply_pose(_motion_blend)
		if _motion_blend <= 0.01 and not _activity_type.is_empty():
			_apply_activity_pose()
	return true


func face_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.001:
		set_direction(_direction_from_vector(direction))


func set_motion(
	direction: Vector2,
	distance_delta: float,
	delta: float,
) -> void:
	var moving := distance_delta > 0.01
	_update_motion_facing(
		direction,
		distance_delta if moving else 0.0,
		delta,
	)
	var previous_blend := _motion_blend
	_motion_blend = move_toward(
		_motion_blend,
		1.0 if moving else 0.0,
		maxf(delta, 0.0) * 7.5,
	)
	if moving:
		_idle_breath_phase = 0.0
		_apply_complete_set_breathing(0.0)
		_walk_phase = fmod(
			_walk_phase + distance_delta / WALK_CYCLE_DISTANCE * TAU,
			TAU,
		)
	elif _activity_type in ["idle", "待着"]:
		_activity_phase = fmod(
			_activity_phase + maxf(delta, 0.0) * _activity_cycle_speed(),
			TAU,
		)
		if _motion_blend <= 0.01:
			_idle_breath_phase = fmod(
				_idle_breath_phase + maxf(delta, 0.0),
				IDLE_BREATH_CYCLE_SECONDS,
			)
			_apply_complete_set_breathing(_idle_breath_amount())
			if previous_blend <= 0.0:
				return
		else:
			_idle_breath_phase = 0.0
			_apply_complete_set_breathing(0.0)
	elif not _activity_type.is_empty():
		_idle_breath_phase = 0.0
		_apply_complete_set_breathing(0.0)
		_activity_phase = fmod(
			_activity_phase + maxf(delta, 0.0) * _activity_cycle_speed(),
			TAU,
		)
	elif previous_blend <= 0.0 and _motion_blend <= 0.0:
		_idle_breath_phase = fmod(
			_idle_breath_phase + maxf(delta, 0.0),
			IDLE_BREATH_CYCLE_SECONDS,
		)
		_apply_complete_set_breathing(_idle_breath_amount())
		return
	_refresh_complete_set_frame()
	_apply_pose(_motion_blend)
	if not moving and _motion_blend <= 0.01 and not _activity_type.is_empty():
		_apply_activity_pose()


func set_activity(action_type: String, activity_family: String = "") -> void:
	var normalized := action_type.strip_edges()
	if normalized not in ["用道具", "搭话", "答话", "待着", "idle"]:
		normalized = ""
	var normalized_family := ""
	if normalized == "用道具":
		normalized_family = activity_family.strip_edges()
		if normalized_family not in [
			"eat_drink",
			"rest",
			"sleep",
			"read_write",
			"service",
			"work",
		]:
			normalized_family = "prop_use"
	if (
		normalized == _activity_type
		and normalized_family == _activity_family
	):
		return
	_activity_type = normalized
	_activity_family = normalized_family
	_activity_phase = 0.0
	_idle_breath_phase = 0.0
	_apply_complete_set_breathing(0.0)
	_refresh_activity_effect()
	if _motion_blend <= 0.01:
		_apply_pose(0.0)
		if not _activity_type.is_empty():
			_apply_activity_pose()


func reset_motion() -> void:
	_activity_type = ""
	_activity_family = ""
	_activity_phase = 0.0
	_refresh_activity_effect()
	reset_locomotion()


func reset_locomotion() -> void:
	_motion_blend = 0.0
	_walk_phase = 0.0
	_idle_breath_phase = 0.0
	_apply_complete_set_breathing(0.0)
	_reset_motion_facing_candidate()
	_refresh_complete_set_frame()
	_apply_pose(0.0)
	if not _activity_type.is_empty():
		_apply_activity_pose()


func _update_motion_facing(
	direction: Vector2,
	distance_delta: float,
	delta: float,
) -> void:
	if direction.length_squared() <= 0.001 or distance_delta <= 0.01:
		_reset_motion_facing_candidate()
		return
	var next_direction := _direction_from_vector(direction)
	if _motion_blend <= 0.01:
		set_direction(next_direction)
		_reset_motion_facing_candidate()
		return
	if next_direction == _active_direction:
		_reset_motion_facing_candidate()
		return
	if next_direction != _motion_facing_candidate:
		_motion_facing_candidate = next_direction
		_motion_facing_candidate_seconds = 0.0
		_motion_facing_candidate_distance = 0.0
	_motion_facing_candidate_seconds += maxf(delta, 0.0)
	_motion_facing_candidate_distance += maxf(distance_delta, 0.0)
	if (
		_motion_facing_candidate_seconds < MOTION_FACING_CONFIRM_SECONDS
		or _motion_facing_candidate_distance
			< MOTION_FACING_CONFIRM_DISTANCE
	):
		return
	set_direction(next_direction)
	_reset_motion_facing_candidate()


func _reset_motion_facing_candidate() -> void:
	_motion_facing_candidate = ""
	_motion_facing_candidate_seconds = 0.0
	_motion_facing_candidate_distance = 0.0


func get_direction_name() -> String:
	return _active_direction


func set_resident_appearance(
	resident_id: String,
	appearance_id: String,
) -> bool:
	_build_runtime()
	var loadout_id := _resolved_resident_loadout_id(
		resident_id,
		appearance_id,
	)
	return not loadout_id.is_empty() and _apply_loadout(loadout_id)


func can_resolve_resident_appearance(
	resident_id: String,
	appearance_id: String,
) -> bool:
	_build_runtime()
	return not _resolved_resident_loadout_id(
		resident_id,
		appearance_id,
	).is_empty()


func _resolved_resident_loadout_id(
	resident_id: String,
	appearance_id: String,
) -> String:
	if not _contract_valid or _loadout_by_id.is_empty():
		return ""
	var normalized_appearance := appearance_id.strip_edges()
	var loadout_id := normalized_appearance
	if loadout_id.begins_with("resident_wardrobe_v1:"):
		loadout_id = loadout_id.trim_prefix("resident_wardrobe_v1:")
	if not _loadout_by_id.has(loadout_id):
		loadout_id = String(
			_appearance_aliases.get(normalized_appearance, "")
		)
	if (
		not _loadout_by_id.has(loadout_id)
		and not normalized_appearance.is_empty()
		and not normalized_appearance.begins_with("paper_doll_64:")
	):
		return ""
	if not _loadout_by_id.has(loadout_id):
		loadout_id = String(
			_resident_assignments.get(resident_id.strip_edges(), "")
		)
	if not _loadout_by_id.has(loadout_id):
		var loadouts := _wardrobe_catalog.get("loadouts", []) as Array
		if loadouts.is_empty() or loadouts[0] is not Dictionary:
			return ""
		loadout_id = String(
			(loadouts[0] as Dictionary).get("id", "")
		)
	return loadout_id if _loadout_by_id.has(loadout_id) else ""


func get_active_loadout_id() -> String:
	return _active_loadout_id


func get_head_global_position() -> Vector2:
	if _sleeping and _sleep_head_sprite != null:
		return _sleep_head_sprite.to_global(
			Vector2(
				0.0,
				-_sleep_head_sprite.region_rect.size.y
					* 0.5,
			)
		)
	if _complete_set_sprite != null:
		return to_global(Vector2(0.0, -DISPLAY_HEIGHT * 0.76))
	var source_direction := "right" if _active_direction == "left" else _active_direction
	var anchor := _head_anchors.get(source_direction) as Marker2D
	if anchor == null:
		return global_position
	return anchor.global_position


func get_head_screen_position() -> Vector2:
	if _sleeping and _sleep_head_sprite != null:
		return get_canvas_transform() * get_head_global_position()
	if _complete_set_sprite != null:
		return get_canvas_transform() * to_global(
			Vector2(0.0, -DISPLAY_HEIGHT * 0.76),
		)
	var source_direction := "right" if _active_direction == "left" else _active_direction
	var anchor := _head_anchors.get(source_direction) as Marker2D
	if anchor == null:
		return get_global_transform_with_canvas().origin
	return anchor.get_global_transform_with_canvas().origin


func is_contract_valid() -> bool:
	return _contract_valid


func get_rig_state() -> Dictionary:
	var source_direction := "right" if _active_direction == "left" else _active_direction
	var active_bones := _bones.get(source_direction, {}) as Dictionary
	var active_source_state := (
		_source_state.get(source_direction, {}) as Dictionary
	)
	var complete_set_frame := -1
	if _complete_set_sprite != null and _complete_set_sprite.region_enabled:
		complete_set_frame = int(
			_complete_set_sprite.region_rect.position.y
			/ COMPLETE_SET_FRAME_SIZE.y
		)
	return {
		"contractValid": _contract_valid,
		"activeDirection": _active_direction,
		"sourceDirection": source_direction,
		"leftMirrorsRight": _active_direction == "left",
		"boneCount": active_bones.size(),
		"skeletonCount": _skeletons.size(),
		"hasSkeleton2D": (
			_skeletons.has(source_direction)
			and _skeletons[source_direction] is Skeleton2D
		),
		"artworkPartCount": int(active_source_state.get("partCount", 0)),
		"walkPhase": _walk_phase,
		"motionBlend": _motion_blend,
		"activityType": _activity_type,
		"activityFamily": _activity_family,
		"activityPhase": _activity_phase,
		"displayHeight": DISPLAY_HEIGHT,
		"displayScale": DISPLAY_SCALE,
		"footAnchor": _freeze_state.get("footAnchor", {}),
		"sourceState": _source_state.duplicate(true),
		"wardrobeEnabled": not _active_loadout_id.is_empty(),
		"activeLoadoutId": _active_loadout_id,
		"loadedWardrobeTextureCount": _texture_cache.size(),
		"wardrobeCatalog": WARDROBE_CATALOG_PATH,
		"visualSource": "classic_resident_complete_set_v1",
		"renderMode": "complete_sprite_sheet",
		"spriteSheetPath": _complete_set_sheet_path,
		"completeSetFrame": complete_set_frame,
		"completeSetIdleFrame": COMPLETE_SET_IDLE_FRAME,
		"idleBreathingEnabled": _complete_set_sprite != null,
		"activityEffect": (
			_activity_effect.get_effect_kind()
			if _activity_effect != null
			else ""
		),
		"activityEffectVisible": (
			_activity_effect.visible
			if _activity_effect != null
			else false
		),
		"sleeping": _sleeping,
		"sleepHeadVisible": (
			_sleep_head_sprite.visible
			if _sleep_head_sprite != null
			else false
		),
	}


func set_sleep_pose(enabled: bool, head_global_position := Vector2.ZERO) -> bool:
	_build_runtime()
	if enabled:
		if not _refresh_sleep_head_texture():
			_sleeping = false
			_refresh_sleep_visibility()
			return false
		_sleeping = true
		_sleep_head_sprite.global_position = head_global_position
	else:
		_sleeping = false
	_refresh_sleep_visibility()
	return true


func get_contract_snapshot() -> Dictionary:
	return {
		"schema": "ai-town.resident-frozen-whitebody-runtime.v1",
		"sourceManifest": FREEZE_MANIFEST_PATH,
		"rigContract": RIG_CONTRACT_PATH,
		"directions": ALL_DIRECTIONS.duplicate(),
		"sourceDirections": SOURCE_DIRECTIONS.duplicate(),
		"leftPolicy": "exact_runtime_mirror_of_right",
		"canvasSize": {"x": 627, "y": 627},
		"footAnchor": _freeze_state.get("footAnchor", {}),
		"displayHeight": DISPLAY_HEIGHT,
		"displayScale": DISPLAY_SCALE,
		"textureFilter": "nearest",
		"wardrobeEnabled": not _wardrobe_catalog.is_empty(),
		"wardrobeCatalog": WARDROBE_CATALOG_PATH,
		"loadoutCount": _loadout_by_id.size(),
		"contractValid": _contract_valid,
	}


func _build_runtime() -> void:
	if _runtime_built:
		return
	_runtime_built = true
	var freeze_manifest := _load_json(FREEZE_MANIFEST_PATH)
	var rig_contract := _load_json(RIG_CONTRACT_PATH)
	_contract_valid = (
		_validate_rig_contract(rig_contract)
		and _validate_freeze_manifest(freeze_manifest)
	)
	if not _contract_valid:
		return
	for direction_id: String in SOURCE_DIRECTIONS:
		var manifest_path := RIG_MANIFEST_PATTERN % direction_id
		var manifest := _load_json(manifest_path)
		_build_direction(direction_id, manifest, manifest_path)
	_contract_valid = (
		_contract_valid
		and _all_sources_valid()
		and _load_wardrobe_catalog()
	)


func _load_wardrobe_catalog() -> bool:
	_wardrobe_catalog.clear()
	_loadout_by_id.clear()
	_resident_assignments.clear()
	_appearance_aliases.clear()
	var catalog := _load_json(WARDROBE_CATALOG_PATH)
	if not _wardrobe_catalog_structure_valid(catalog):
		return false
	var loadouts := catalog.get("loadouts", []) as Array
	for loadout_value: Variant in loadouts:
		var loadout := loadout_value as Dictionary
		var loadout_id := String(loadout.get("id", ""))
		_loadout_by_id[loadout_id] = loadout.duplicate(true)
	_resident_assignments = (
		catalog.get("residentAssignments", {}) as Dictionary
	).duplicate(true)
	_appearance_aliases = (
		catalog.get("legacyAppearanceAliases", {}) as Dictionary
	).duplicate(true)
	_wardrobe_catalog = catalog.duplicate(true)
	return true


func _wardrobe_catalog_structure_valid(catalog: Dictionary) -> bool:
	if (
		String(catalog.get("schema", "")) != WARDROBE_SCHEMA
		or String(catalog.get("revision", "")).strip_edges().is_empty()
		or not _wardrobe_canvas_valid(catalog.get("canvasSize"))
		or catalog.get("directions") != ALL_DIRECTIONS
		or String(catalog.get("textureFilter", "")) != "nearest"
		or catalog.get("loadouts") is not Array
		or catalog.get("residentAssignments") is not Dictionary
		or catalog.get("legacyAppearanceAliases") is not Dictionary
	):
		return false
	var loadouts := catalog.get("loadouts", []) as Array
	if loadouts.size() != 16:
		return false
	var known_ids: Dictionary = {}
	for loadout_value: Variant in loadouts:
		if loadout_value is not Dictionary:
			return false
		var loadout := loadout_value as Dictionary
		var loadout_id := String(loadout.get("id", "")).strip_edges()
		if (
			loadout_id.is_empty()
			or known_ids.has(loadout_id)
			or String(loadout.get("appearanceId", ""))
			!= "resident_wardrobe_v1:%s" % loadout_id
			or String(loadout.get("headId", "")).strip_edges().is_empty()
			or String(loadout.get("outfitId", "")).strip_edges().is_empty()
			or not _wardrobe_texture_reference_valid(
				String(loadout.get("spriteSheetPath", "")),
				String(loadout.get("spriteSheetSha256", "")),
				false,
			)
			or not _wardrobe_texture_reference_valid(
				String(loadout.get("portraitPath", "")),
				String(loadout.get("portraitSha256", "")),
				false,
			)
			or not _wardrobe_directions_valid(loadout_id, loadout)
		):
			return false
		known_ids[loadout_id] = true
	var assignments := catalog.get("residentAssignments", {}) as Dictionary
	if assignments.size() != 16:
		return false
	for resident_id_value: Variant in assignments:
		var resident_id := String(resident_id_value).strip_edges()
		var assigned_id := String(assignments[resident_id_value])
		if resident_id.is_empty() or not known_ids.has(assigned_id):
			return false
	var aliases := catalog.get("legacyAppearanceAliases", {}) as Dictionary
	for alias_value: Variant in aliases:
		var alias := String(alias_value).strip_edges()
		var aliased_id := String(aliases[alias_value])
		if alias.is_empty() or not known_ids.has(aliased_id):
			return false
	return true


func _wardrobe_canvas_valid(value: Variant) -> bool:
	return wardrobe_canvas_valid(value)


static func wardrobe_canvas_valid(value: Variant) -> bool:
	if value is not Array or (value as Array).size() != 2:
		return false
	for coordinate: Variant in value as Array:
		if (
			typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(coordinate))
			or float(coordinate) != 627.0
		):
			return false
	return true


func _wardrobe_directions_valid(
	loadout_id: String,
	loadout: Dictionary,
) -> bool:
	var directions_value: Variant = loadout.get("directions")
	if directions_value is not Dictionary:
		return false
	var directions := directions_value as Dictionary
	if directions.size() != SOURCE_DIRECTIONS.size():
		return false
	for direction_id: String in SOURCE_DIRECTIONS:
		var direction_value: Variant = directions.get(direction_id)
		if direction_value is not Dictionary:
			return false
		var direction := direction_value as Dictionary
		var expected_root := (
			WARDROBE_ROOT
			+ "/loadouts/%s/%s/parts" % [loadout_id, direction_id]
		)
		if (
			String(direction.get("partsRoot", "")).simplify_path()
			!= expected_root
			or not _wardrobe_texture_reference_valid(
				String(direction.get("restPath", "")),
				String(direction.get("restSha256", "")),
				false,
			)
			or direction.get("partSha256") is not Dictionary
		):
			return false
		var part_hashes := direction.get("partSha256", {}) as Dictionary
		var expected_part_count := 0
		for spec: Dictionary in BONE_SPECS:
			var part_id := String(spec.get("part", ""))
			if part_id.is_empty():
				continue
			expected_part_count += 1
			if (
				not part_hashes.has(part_id)
				or not _is_sha256(String(part_hashes.get(part_id, "")))
			):
				return false
		if part_hashes.size() != expected_part_count:
			return false
	return true


func _apply_loadout(loadout_id: String) -> bool:
	if not _loadout_by_id.has(loadout_id):
		return false
	if loadout_id == _active_loadout_id:
		return true
	var loadout := _loadout_by_id[loadout_id] as Dictionary
	if not _apply_complete_set_texture(loadout):
		return false
	_active_loadout_id = loadout_id
	if _sleeping and not _refresh_sleep_head_texture():
		return false
	return true


func _apply_complete_set_texture(loadout: Dictionary) -> bool:
	var sheet_path := String(loadout.get("spriteSheetPath", ""))
	var sheet_sha := String(loadout.get("spriteSheetSha256", ""))
	if not _wardrobe_texture_reference_valid(sheet_path, sheet_sha, true):
		return false
	var texture := _texture_for_path(sheet_path, sheet_sha)
	if texture == null or texture.get_size() != COMPLETE_SET_SHEET_SIZE:
		return false
	if _complete_set_sprite == null:
		_complete_set_sprite = Sprite2D.new()
		_complete_set_sprite.name = "CompleteResidentSet"
		_complete_set_sprite.centered = true
		_complete_set_sprite.region_enabled = true
		_complete_set_sprite.region_filter_clip_enabled = true
		_complete_set_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_complete_set_sprite.scale = Vector2.ONE * COMPLETE_SET_DISPLAY_SCALE
		_complete_set_sprite.position = Vector2(
			0.0,
			-(COMPLETE_SET_SOURCE_FOOT_Y - COMPLETE_SET_FRAME_SIZE.y * 0.5)
			* COMPLETE_SET_DISPLAY_SCALE,
		)
		_complete_set_base_position = _complete_set_sprite.position
		add_child(_complete_set_sprite)
		_activity_effect = ResidentActivityEffect.new()
		_activity_effect.name = "ResidentActivityEffect"
		_activity_effect.z_index = 2
		_activity_effect.scale = Vector2.ONE * 1.7
		add_child(_activity_effect)
	_complete_set_sprite.texture = texture
	_complete_set_sprite.visible = not _sleeping
	_complete_set_sheet_path = sheet_path
	for direction_root_value: Variant in _direction_roots.values():
		(direction_root_value as Node2D).visible = false
	_refresh_complete_set_frame()
	_refresh_activity_effect()
	return true


func _refresh_sleep_head_texture() -> bool:
	if _complete_set_sprite == null or _complete_set_sprite.texture == null:
		return false
	var texture := _complete_set_sprite.texture
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	var frame_rect := Rect2i(
		0,
		COMPLETE_SET_IDLE_FRAME * int(COMPLETE_SET_FRAME_SIZE.y),
		int(COMPLETE_SET_FRAME_SIZE.x),
		int(COMPLETE_SET_FRAME_SIZE.y),
	)
	var frame_image := image.get_region(frame_rect)
	var used_rect := frame_image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return false
	used_rect.size.y = maxi(
		1,
		ceili(float(used_rect.size.y) * SLEEP_HEAD_BODY_FRACTION),
	)
	var atlas_head_rect := Rect2(
		Vector2(
			used_rect.position.x,
			frame_rect.position.y + used_rect.position.y,
		),
		Vector2(used_rect.size),
	)
	if _sleep_head_sprite == null:
		_sleep_head_sprite = Sprite2D.new()
		_sleep_head_sprite.name = "SleepHead"
		_sleep_head_sprite.centered = true
		_sleep_head_sprite.region_enabled = true
		_sleep_head_sprite.region_filter_clip_enabled = true
		_sleep_head_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sleep_head_sprite.scale = (
			Vector2.ONE * COMPLETE_SET_DISPLAY_SCALE
		)
		_sleep_head_sprite.z_as_relative = false
		_sleep_head_sprite.z_index = 101
		add_child(_sleep_head_sprite)
		_sleep_head_sprite.set_as_top_level(true)
	_sleep_head_sprite.texture = texture
	_sleep_head_sprite.region_rect = atlas_head_rect
	return true


func _refresh_sleep_visibility() -> void:
	if _complete_set_sprite != null:
		_complete_set_sprite.visible = not _sleeping
	for direction_root_value: Variant in _direction_roots.values():
		(direction_root_value as Node2D).visible = false
	if _sleep_head_sprite != null:
		_sleep_head_sprite.visible = _sleeping
	if _activity_effect != null and _sleeping:
		_activity_effect.visible = false


func _refresh_complete_set_frame() -> void:
	if _complete_set_sprite == null or _complete_set_sprite.texture == null:
		return
	var column := 0
	match _active_direction:
		"left", "right":
			column = 1
		"up":
			column = 2
	var frame := COMPLETE_SET_IDLE_FRAME
	if _motion_blend > 0.05:
		frame = int(floor(_walk_phase / TAU * 4.0)) % 4
	_complete_set_sprite.region_rect = Rect2(
		Vector2(column, frame) * COMPLETE_SET_FRAME_SIZE,
		COMPLETE_SET_FRAME_SIZE,
	)
	_complete_set_sprite.flip_h = _active_direction == "right"


func _idle_breath_amount() -> float:
	var normalized := _idle_breath_phase / IDLE_BREATH_CYCLE_SECONDS
	return pow(maxf(0.0, sin(normalized * TAU)), 2.0)


func _apply_complete_set_breathing(amount: float) -> void:
	if _complete_set_sprite == null:
		return
	var display_height := COMPLETE_SET_SOURCE_BODY_HEIGHT * COMPLETE_SET_DISPLAY_SCALE
	var extra_scale := IDLE_BREATH_DISPLAY_PIXELS / display_height * clampf(amount, 0.0, 1.0)
	var next_scale_y := COMPLETE_SET_DISPLAY_SCALE * (1.0 + extra_scale)
	_complete_set_sprite.scale = Vector2(
		COMPLETE_SET_DISPLAY_SCALE,
		next_scale_y,
	)
	_complete_set_sprite.position = Vector2(
		_complete_set_base_position.x,
		-(COMPLETE_SET_SOURCE_FOOT_Y - COMPLETE_SET_FRAME_SIZE.y * 0.5)
		* next_scale_y,
	)


func _refresh_activity_effect() -> void:
	if _activity_effect == null:
		return
	_activity_effect.set_facing(_active_direction)
	_activity_effect.set_effect(
		"work_action_cloud"
		if _activity_type == "用道具" and _activity_family == "work"
		else ""
	)


func _wardrobe_texture_reference_valid(
	path: String,
	expected_sha: String,
	verify_file: bool,
) -> bool:
	var normalized_path := path.strip_edges()
	if (
		normalized_path.is_empty()
		or normalized_path.simplify_path() != normalized_path
		or not normalized_path.begins_with(WARDROBE_ROOT + "/")
		or not normalized_path.ends_with(".png")
		or not _is_sha256(expected_sha)
	):
		return false
	return (
		_reference_matches_sha(normalized_path, expected_sha, true)
		if verify_file
		else true
	)


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _validate_freeze_manifest(
	freeze_manifest: Dictionary,
) -> bool:
	if freeze_manifest.is_empty():
		return false
	if String(freeze_manifest.get("schema", "")) != FREEZE_MANIFEST_SCHEMA:
		return false
	if (
		freeze_manifest.get("canvas_size") is not Array
		or freeze_manifest.get("foot_anchor") is not Array
		or freeze_manifest.get("runtime_motion_policy") is not Dictionary
		or freeze_manifest.get("whitebody") is not Dictionary
		or freeze_manifest.get("rig_sources") is not Dictionary
	):
		return false
	var canvas := freeze_manifest.get("canvas_size", []) as Array
	var foot_anchor := freeze_manifest.get("foot_anchor", []) as Array
	if canvas != [627.0, 627.0] or foot_anchor != [314.5, 591.0]:
		return false
	var motion_policy := (
		freeze_manifest.get("runtime_motion_policy", {}) as Dictionary
	)
	if bool(motion_policy.get("use_old_18_bone_walk_experiment", true)):
		return false
	var whitebody := freeze_manifest.get("whitebody", {}) as Dictionary
	var whitebody_state: Dictionary = {}
	var valid := true
	var manifest_dir := FREEZE_MANIFEST_PATH.get_base_dir()
	for direction_id: String in ALL_DIRECTIONS:
		var record_value: Variant = whitebody.get(direction_id)
		if record_value is not Dictionary:
			valid = false
			continue
		var record := record_value as Dictionary
		var path := manifest_dir.path_join(String(record.get("path", ""))).simplify_path()
		var expected_sha := String(record.get("sha256", ""))
		var actual_sha := _file_sha256(path)
		var direction_valid := _reference_matches_sha(path, expected_sha, true)
		whitebody_state[direction_id] = {
			"path": path,
			"sha256": actual_sha,
			"valid": direction_valid,
		}
		valid = valid and direction_valid
	var rig_sources := freeze_manifest.get("rig_sources", {}) as Dictionary
	for source_id: String in ["contract", "down", "right", "up"]:
		var source_record_value: Variant = rig_sources.get(source_id)
		if source_record_value is not Dictionary:
			valid = false
			continue
		var source_record := source_record_value as Dictionary
		var source_path := (
			manifest_dir
			.path_join(String(source_record.get("path", "")))
			.simplify_path()
		)
		var source_sha := _file_sha256(source_path)
		valid = (
			valid
			and not source_sha.is_empty()
			and source_sha == String(source_record.get("sha256", ""))
		)
	_freeze_state = {
		"schema": String(freeze_manifest.get("schema", "")),
		"footAnchor": {"x": 314.5, "y": 591.0},
		"whitebody": whitebody_state,
	}
	return valid


func _validate_rig_contract(rig_contract: Dictionary) -> bool:
	if rig_contract.is_empty():
		return false
	if (
		String(rig_contract.get("schema", ""))
		!= "ai-town.four-direction-articulated-rig-contract.v1"
	):
		return false
	if (
		String(rig_contract.get("status", "")) != RUNTIME_CONTRACT_STATUS
		or String(rig_contract.get("approved_whitebody_root", ""))
		!= "production_frozen_v2/whitebody"
	):
		return false
	if (
		rig_contract.get("canvas_size") is not Array
		or rig_contract.get("foot_anchor") is not Array
		or rig_contract.get("pixel_scale_decision") is not Dictionary
		or rig_contract.get("bone_hierarchy") is not Array
	):
		return false
	var contract_canvas := rig_contract.get("canvas_size", []) as Array
	var contract_foot_anchor := rig_contract.get("foot_anchor", []) as Array
	if (
		contract_canvas != [627.0, 627.0]
		or contract_foot_anchor != [314.5, 591.0]
	):
		return false
	if String(rig_contract.get("left_policy", "")) != "exact_runtime_mirror_of_right":
		return false
	var scale_decision := rig_contract.get("pixel_scale_decision", {}) as Dictionary
	var bone_count_value: Variant = scale_decision.get("bone2d_count")
	var artwork_count_value: Variant = scale_decision.get(
		"artwork_part_count",
	)
	if (
		not _is_integral_number(bone_count_value)
		or not _is_integral_number(artwork_count_value)
		or int(bone_count_value) != BONE_SPECS.size()
		or int(artwork_count_value) != 15
	):
		return false
	var hierarchy := rig_contract.get("bone_hierarchy", []) as Array
	if hierarchy.size() != BONE_SPECS.size():
		return false
	for index in BONE_SPECS.size():
		var expected := BONE_SPECS[index] as Dictionary
		var actual_value: Variant = hierarchy[index]
		if actual_value is not Dictionary:
			return false
		var actual := actual_value as Dictionary
		var actual_parent := _optional_string(actual.get("parent"))
		if (
			_optional_string(actual.get("id")) != _optional_string(expected.get("id"))
			or actual_parent != _optional_string(expected.get("parent"))
			or _optional_string(actual.get("part")) != _optional_string(expected.get("part"))
		):
			return false
	return true


func _build_direction(
	direction_id: String,
	manifest: Dictionary,
	manifest_path: String,
) -> void:
	var direction_state := {
		"valid": false,
		"manifest": manifest_path,
		"partCount": 0,
		"boneCount": 0,
	}
	if manifest.is_empty():
		_source_state[direction_id] = direction_state
		return
	if not _direction_manifest_structure_valid(manifest, direction_id):
		_source_state[direction_id] = direction_state
		return
	var canvas := manifest.get("canvas_size", []) as Array
	var foot_anchor_array := manifest.get("foot_anchor", []) as Array
	if (
		String(manifest.get("schema", "")) != RIG_MANIFEST_SCHEMA
		or canvas != [627.0, 627.0]
		or foot_anchor_array != [314.5, 591.0]
	):
		_source_state[direction_id] = direction_state
		return
	var direction_root := Node2D.new()
	direction_root.name = "%sFrozenWhitebodyRig" % direction_id.capitalize()
	direction_root.scale = Vector2.ONE * DISPLAY_SCALE
	direction_root.visible = false
	add_child(direction_root)
	_direction_roots[direction_id] = direction_root
	var skeleton := Skeleton2D.new()
	skeleton.name = "%sSkeleton2D" % direction_id.capitalize()
	skeleton.position = -Vector2(314.5, 591.0)
	direction_root.add_child(skeleton)
	_skeletons[direction_id] = skeleton
	var direction_bones: Dictionary = {}
	var direction_rest: Dictionary = {}
	var global_joints: Dictionary = {}
	var joints := manifest.get("joints", {}) as Dictionary
	var bone_pivots := manifest.get("bone_pivots", {}) as Dictionary
	var parts := _parts_by_id(manifest.get("parts", {}))
	var valid := (
		parts.size() == 15
		and String(manifest.get("direction", "")) == direction_id
		and String(manifest.get("status", "")) == RUNTIME_CONTRACT_STATUS
		and _manifest_hierarchy_matches_contract(manifest)
		and _manifest_reference_valid(
			manifest,
			"source",
			"source_sha256",
			manifest_path.get_base_dir(),
			"",
			true,
		)
		and _manifest_reference_valid(
			manifest,
			"rest_reconstruction",
			"rest_reconstruction_sha256",
			manifest_path.get_base_dir(),
			"",
			true,
		)
		and _manifest_reference_valid(
			manifest,
			"contract",
			"contract_sha256",
			manifest_path.get_base_dir(),
			RIG_CONTRACT_PATH,
		)
	)
	var loaded_part_count := 0
	var direction_sprites: Dictionary = {}
	for spec: Dictionary in BONE_SPECS:
		var bone_id := String(spec.get("id", ""))
		var parent_id := String(spec.get("parent", ""))
		var joint_id := String(spec.get("joint", ""))
		var joint_value: Variant = (
			bone_pivots.get(bone_id)
			if bone_pivots.has(bone_id)
			else joints.get(joint_id)
		)
		if not _is_finite_vector2_value(joint_value):
			valid = false
			continue
		var global_joint := _vector_from_value(joint_value)
		var parent_joint := (
			global_joints.get(parent_id, Vector2.ZERO) as Vector2
			if not parent_id.is_empty()
			else Vector2.ZERO
		)
		var bone := Bone2D.new()
		bone.name = bone_id
		bone.set_autocalculate_length_and_angle(false)
		bone.position = global_joint - parent_joint
		if parent_id.is_empty():
			skeleton.add_child(bone)
		elif direction_bones.has(parent_id):
			(direction_bones[parent_id] as Bone2D).add_child(bone)
		else:
			valid = false
			continue
		bone.rest = bone.transform
		direction_bones[bone_id] = bone
		direction_rest[bone_id] = bone.position
		global_joints[bone_id] = global_joint
		var part_id := String(spec.get("part", ""))
		if part_id.is_empty() or not parts.has(part_id):
			continue
		var part_record := parts[part_id] as Dictionary
		var source_path := _resolve_part_path(
			String(part_record.get("source", part_record.get("path", ""))),
			manifest_path.get_base_dir(),
		)
		var expected_part_sha := String(part_record.get("sha256", ""))
		var texture := _texture_for_path(source_path, expected_part_sha)
		if (
			texture == null
			or texture.get_size() != Vector2(627.0, 627.0)
			or expected_part_sha.is_empty()
			or not _reference_matches_sha(source_path, expected_part_sha, true)
		):
			valid = false
			continue
		var sprite := Sprite2D.new()
		sprite.name = "%sPart" % part_id.capitalize()
		sprite.texture = texture
		sprite.centered = false
		sprite.position = -global_joint
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.z_index = _part_z(part_id, manifest)
		bone.add_child(sprite)
		direction_sprites[part_id] = sprite
		if part_id == "head":
			var alpha_rect := _part_alpha_rect(part_record)
			if not alpha_rect.has_area():
				valid = false
			else:
				var head_anchor := Marker2D.new()
				head_anchor.name = "HeadTopAnchor"
				head_anchor.position = Vector2(
					alpha_rect.position.x + alpha_rect.size.x * 0.5,
					alpha_rect.position.y,
				) - global_joint
				bone.add_child(head_anchor)
				_head_anchors[direction_id] = head_anchor
		loaded_part_count += 1
	_bones[direction_id] = direction_bones
	_part_sprites[direction_id] = direction_sprites
	_rest_positions[direction_id] = direction_rest
	direction_state["valid"] = (
		valid
		and direction_bones.size() == BONE_SPECS.size()
		and loaded_part_count == 15
		and _head_anchors.has(direction_id)
	)
	direction_state["partCount"] = loaded_part_count
	direction_state["boneCount"] = direction_bones.size()
	direction_state["manifestSha256"] = _file_sha256(manifest_path)
	_source_state[direction_id] = direction_state


func _direction_manifest_structure_valid(
	manifest: Dictionary,
	direction_id: String,
) -> bool:
	if manifest.get("canvas_size") is not Array:
		return false
	if manifest.get("foot_anchor") is not Array:
		return false
	if manifest.get("bone_hierarchy") is not Array:
		return false
	if manifest.get("joints") is not Dictionary:
		return false
	if manifest.get("bone_pivots", {}) is not Dictionary:
		return false
	var parts_value: Variant = manifest.get("parts")
	if parts_value is not Dictionary and parts_value is not Array:
		return false
	if (
		manifest.has("part_layer_order")
		and manifest.get("part_layer_order") is not Array
	):
		return false
	if parts_value is Dictionary:
		for part_value: Variant in (parts_value as Dictionary).values():
			if part_value is not Dictionary:
				return false
	else:
		for part_value: Variant in parts_value as Array:
			if part_value is not Dictionary:
				return false
	if not _is_finite_vector2_value(manifest.get("canvas_size")):
		return false
	if not _is_finite_vector2_value(manifest.get("foot_anchor")):
		return false
	for hierarchy_value: Variant in manifest.get("bone_hierarchy", []) as Array:
		if hierarchy_value is not Dictionary:
			return false
	var joints := manifest.get("joints", {}) as Dictionary
	var bone_pivots := manifest.get("bone_pivots", {}) as Dictionary
	for spec: Dictionary in BONE_SPECS:
		var bone_id := String(spec.get("id", ""))
		var joint_id := String(spec.get("joint", ""))
		var joint_value: Variant = (
			bone_pivots.get(bone_id)
			if bone_pivots.has(bone_id)
			else joints.get(joint_id)
		)
		if not _is_finite_vector2_value(joint_value):
			return false
	return (
		String(manifest.get("schema", "")) == RIG_MANIFEST_SCHEMA
		and String(manifest.get("direction", "")) == direction_id
	)


func _manifest_hierarchy_matches_contract(manifest: Dictionary) -> bool:
	var hierarchy := manifest.get("bone_hierarchy", []) as Array
	if hierarchy.size() != BONE_SPECS.size():
		return false
	for index in BONE_SPECS.size():
		var expected := BONE_SPECS[index] as Dictionary
		var actual := hierarchy[index] as Dictionary
		var actual_parent := _optional_string(actual.get("parent"))
		if (
			_optional_string(actual.get("id")) != _optional_string(expected.get("id"))
			or actual_parent != _optional_string(expected.get("parent"))
			or _optional_string(actual.get("part")) != _optional_string(expected.get("part"))
		):
			return false
	return true


func _manifest_reference_valid(
	manifest: Dictionary,
	path_key: String,
	sha_key: String,
	base_dir: String,
	expected_path: String = "",
	imported_texture: bool = false,
) -> bool:
	var declared_path := String(manifest.get(path_key, "")).strip_edges()
	var declared_sha := String(manifest.get(sha_key, "")).strip_edges()
	if declared_path.is_empty() or declared_sha.is_empty():
		return false
	var resolved_path := _resolve_part_path(declared_path, base_dir)
	if not expected_path.is_empty() and resolved_path != expected_path:
		return false
	return _reference_matches_sha(resolved_path, declared_sha, imported_texture)


func _apply_pose(blend: float) -> void:
	# The approved complete resident sheet is the only visible character layer.
	# Keep the articulated source rigs mounted for contract/debug inspection,
	# but do not spend every motion frame posing nodes hidden behind that sheet.
	if _complete_set_sprite != null:
		return
	var stride := sin(_walk_phase)
	var double_step := absf(sin(_walk_phase))
	var source_direction := (
		"right" if _active_direction == "left" else _active_direction
	)
	_reset_direction(source_direction)
	_pose_bone(
		source_direction,
		"root",
		0.0,
		Vector2(stride * 1.2, -double_step * 3.0) * blend,
	)
	if source_direction == "right":
		_apply_side_gait(source_direction, stride, blend)
	else:
		_apply_front_back_gait(source_direction, stride, blend)


func _apply_activity_pose() -> void:
	if _complete_set_sprite != null:
		return
	var pulse := sin(_activity_phase)
	var source_direction := (
		"right" if _active_direction == "left" else _active_direction
	)
	match _activity_type:
		"用道具":
			_apply_prop_activity_pose(source_direction, pulse)
		"搭话", "答话":
			_pose_bone(
				source_direction,
				"head",
				deg_to_rad(pulse * 1.8),
				Vector2(0.0, -absf(pulse) * 0.8),
			)
			_pose_bone(
				source_direction,
				"upper_arm_r",
				deg_to_rad(-10.0 + pulse * 4.0),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"forearm_r",
				deg_to_rad(-14.0 + pulse * 6.0),
				Vector2.ZERO,
			)
		"待着", "idle":
			_pose_bone(
				source_direction,
				"root",
				0.0,
				Vector2(0.0, -0.8 - pulse * 0.8),
			)
			_pose_bone(
				source_direction,
				"head",
				deg_to_rad(pulse * 0.7),
				Vector2.ZERO,
			)


func _activity_cycle_speed() -> float:
	match _activity_type:
		"用道具":
			match _activity_family:
				"sleep":
					return 0.7
				"rest":
					return 1.0
				"read_write":
					return 2.0
				"eat_drink":
					return 2.6
				"service":
					return 2.8
				_:
					return 4.0
		"搭话", "答话":
			return 3.0
		"待着":
			return 1.4
		"idle":
			return 0.9
		_:
			return 0.0


func _apply_prop_activity_pose(
	source_direction: String,
	pulse: float,
) -> void:
	match _activity_family:
		"eat_drink":
			_pose_bone(
				source_direction,
				"head",
				deg_to_rad(-1.5 + pulse * 0.7),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"upper_arm_r",
				deg_to_rad(-16.0 + pulse * 2.0),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"forearm_r",
				deg_to_rad(-28.0 - pulse * 4.0),
				Vector2(0.0, -4.0 - pulse),
			)
			_pose_bone(
				source_direction,
				"hand_r",
				deg_to_rad(-10.0),
				Vector2(0.0, -5.0 - pulse),
			)
		"rest":
			_pose_bone(
				source_direction,
				"root",
				0.0,
				Vector2(0.0, 3.0 - pulse * 0.8),
			)
			_pose_bone(
				source_direction,
				"torso",
				deg_to_rad(pulse * 0.6),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"head",
				deg_to_rad(pulse * 0.8),
				Vector2.ZERO,
			)
		"sleep":
			_pose_bone(
				source_direction,
				"root",
				0.0,
				Vector2(0.0, 4.0 - pulse * 1.1),
			)
			_pose_bone(
				source_direction,
				"torso",
				deg_to_rad(3.0 + pulse * 0.7),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"head",
				deg_to_rad(5.0 + pulse * 1.0),
				Vector2(0.0, 1.5),
			)
			_pose_bone(
				source_direction,
				"forearm_l",
				deg_to_rad(8.0),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"forearm_r",
				deg_to_rad(-8.0),
				Vector2.ZERO,
			)
		"read_write":
			_pose_bone(
				source_direction,
				"head",
				deg_to_rad(3.0 + pulse * 0.5),
				Vector2(0.0, 1.0),
			)
			_pose_bone(
				source_direction,
				"forearm_l",
				deg_to_rad(15.0 + pulse * 2.0),
				Vector2(1.5, -2.0),
			)
			_pose_bone(
				source_direction,
				"forearm_r",
				deg_to_rad(-15.0 - pulse * 2.0),
				Vector2(-1.5, -2.0),
			)
			_pose_bone(
				source_direction,
				"hand_r",
				deg_to_rad(-pulse * 4.0),
				Vector2(0.0, pulse * 1.2),
			)
		"service":
			_pose_bone(
				source_direction,
				"head",
				deg_to_rad(pulse * 1.0),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"upper_arm_r",
				deg_to_rad(-10.0 + pulse * 3.0),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"forearm_r",
				deg_to_rad(-18.0 + pulse * 5.0),
				Vector2.ZERO,
			)
		_:
			_pose_bone(
				source_direction,
				"torso",
				deg_to_rad(pulse * 1.0),
				Vector2(0.0, absf(pulse) * 1.2),
			)
			_pose_bone(
				source_direction,
				"forearm_l",
				deg_to_rad(8.0 + pulse * 7.0),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"forearm_r",
				deg_to_rad(-8.0 - pulse * 7.0),
				Vector2.ZERO,
			)
			_pose_bone(
				source_direction,
				"hand_l",
				deg_to_rad(pulse * 5.0),
				Vector2(0.0, pulse * 1.5),
			)
			_pose_bone(
				source_direction,
				"hand_r",
				deg_to_rad(-pulse * 5.0),
				Vector2(0.0, -pulse * 1.5),
			)


func _apply_front_back_gait(
	direction_id: String,
	stride: float,
	blend: float,
) -> void:
	var facing_sign := 1.0 if direction_id == "down" else -1.0
	var left_forward := stride * facing_sign * blend
	var right_forward := -left_forward
	var cycle_velocity := cos(_walk_phase)
	var left_lift := maxf(0.0, cycle_velocity) * blend
	var right_lift := maxf(0.0, -cycle_velocity) * blend
	var left_arm_forward := -left_forward
	var right_arm_forward := -right_forward
	_pose_bone(direction_id, "pelvis", deg_to_rad(stride * 0.25) * blend, Vector2.ZERO)
	_pose_bone(direction_id, "torso", deg_to_rad(-stride * 0.18) * blend, Vector2.ZERO)
	_pose_bone(direction_id, "head", deg_to_rad(stride * 0.08) * blend, Vector2.ZERO)
	_pose_bone(direction_id, "clavicle_l", 0.0, Vector2(0.0, left_arm_forward * 0.18))
	_pose_bone(direction_id, "clavicle_r", 0.0, Vector2(0.0, right_arm_forward * 0.18))
	_pose_bone(direction_id, "forearm_l", 0.0, Vector2(0.0, left_arm_forward * 0.55))
	_pose_bone(direction_id, "forearm_r", 0.0, Vector2(0.0, right_arm_forward * 0.55))
	_pose_bone(direction_id, "hand_l", 0.0, Vector2(0.0, left_arm_forward * 2.25))
	_pose_bone(direction_id, "hand_r", 0.0, Vector2(0.0, right_arm_forward * 2.25))
	_pose_bone(
		direction_id,
		"shin_l",
		0.0,
		Vector2(0.0, left_forward * 0.55 - left_lift * 0.45),
	)
	_pose_bone(
		direction_id,
		"shin_r",
		0.0,
		Vector2(0.0, right_forward * 0.55 - right_lift * 0.45),
	)
	_pose_bone(
		direction_id,
		"foot_l",
		deg_to_rad(-left_forward * 1.2),
		Vector2(0.0, left_forward * 2.85 - left_lift * 1.15),
	)
	_pose_bone(
		direction_id,
		"foot_r",
		deg_to_rad(-right_forward * 1.2),
		Vector2(0.0, right_forward * 2.85 - right_lift * 1.15),
	)


func _apply_side_gait(
	direction_id: String,
	stride: float,
	blend: float,
) -> void:
	var passing := absf(cos(_walk_phase))
	_pose_bone(direction_id, "pelvis", deg_to_rad(stride * 0.45) * blend, Vector2.ZERO)
	_pose_bone(direction_id, "torso", deg_to_rad(-stride * 0.30) * blend, Vector2.ZERO)
	_pose_bone(direction_id, "head", deg_to_rad(stride * 0.12) * blend, Vector2.ZERO)
	_pose_bone(direction_id, "clavicle_l", 0.0, Vector2.ZERO)
	_pose_bone(direction_id, "upper_arm_l", deg_to_rad(-stride * 7.0) * blend, Vector2.ZERO)
	_pose_bone(direction_id, "forearm_l", deg_to_rad(-passing * 1.4) * blend, Vector2.ZERO)
	_pose_bone(direction_id, "thigh_l", deg_to_rad(stride * 6.0) * blend, Vector2.ZERO)
	_pose_bone(
		direction_id,
		"shin_l",
		deg_to_rad(-maxf(0.0, -cos(_walk_phase)) * 4.2) * blend,
		Vector2.ZERO,
	)
	_pose_bone(
		direction_id,
		"foot_l",
		deg_to_rad(maxf(0.0, -cos(_walk_phase)) * 2.0) * blend,
		Vector2.ZERO,
	)


func _reset_direction(direction_id: String) -> void:
	for bone_id: String in (_bones.get(direction_id, {}) as Dictionary):
		var bone := (_bones[direction_id] as Dictionary)[bone_id] as Bone2D
		bone.position = (_rest_positions[direction_id] as Dictionary)[bone_id] as Vector2
		bone.rotation = 0.0


func _pose_bone(
	direction_id: String,
	bone_id: String,
	rotation_value: float,
	offset: Vector2,
) -> void:
	var direction_bones := _bones.get(direction_id, {}) as Dictionary
	if not direction_bones.has(bone_id):
		return
	var bone := direction_bones[bone_id] as Bone2D
	bone.position = (
		(_rest_positions[direction_id] as Dictionary)[bone_id] as Vector2
	) + offset
	bone.rotation = rotation_value


func _all_sources_valid() -> bool:
	for direction_id: String in SOURCE_DIRECTIONS:
		if not bool((_source_state.get(direction_id, {}) as Dictionary).get("valid", false)):
			return false
	return true


func _parts_by_id(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	var result: Dictionary = {}
	if value is Array:
		for item_value: Variant in value:
			if item_value is not Dictionary:
				continue
			var item := item_value as Dictionary
			var part_id := String(item.get("id", ""))
			if not part_id.is_empty():
				result[part_id] = item
	return result


func _part_alpha_rect(part_record: Dictionary) -> Rect2:
	var alpha_bounds_value: Variant = part_record.get("alpha_bounds", [])
	if alpha_bounds_value is not Array:
		return Rect2()
	var alpha_bounds := alpha_bounds_value as Array
	if alpha_bounds.size() == 4:
		if not _all_finite_numbers(alpha_bounds):
			return Rect2()
		return Rect2(
			float(alpha_bounds[0]),
			float(alpha_bounds[1]),
			float(alpha_bounds[2]),
			float(alpha_bounds[3]),
		)
	var bounds_value: Variant = part_record.get("bounds", [])
	if bounds_value is not Array:
		return Rect2()
	var bounds := bounds_value as Array
	if bounds.size() != 4:
		return Rect2()
	if not _all_finite_numbers(bounds):
		return Rect2()
	if bool(part_record.get("visible_in_source", false)):
		return Rect2(
			float(bounds[0]),
			float(bounds[1]),
			float(bounds[2]) - float(bounds[0]),
			float(bounds[3]) - float(bounds[1]),
		)
	return Rect2(
		float(bounds[0]),
		float(bounds[1]),
		float(bounds[2]),
		float(bounds[3]),
	)


func _resolve_part_path(path: String, base_dir: String) -> String:
	if path.begins_with("res://"):
		return path
	if path.begins_with("/"):
		return "res://" + path.trim_prefix("/")
	return base_dir.path_join(path).simplify_path()


static func _reference_matches_sha(
	path: String,
	expected_sha: String,
	imported_texture: bool = false,
) -> bool:
	if expected_sha.is_empty():
		return false
	if imported_texture and not OS.has_feature("editor"):
		return ResourceLoader.exists(path, "Texture2D")
	return _file_sha256(path) == expected_sha


static func _file_sha256(path: String) -> String:
	if _sha256_cache.has(path):
		return String(_sha256_cache[path])
	if not FileAccess.file_exists(path):
		return ""
	var sha256 := FileAccess.get_sha256(path)
	if not sha256.is_empty():
		_sha256_cache[path] = sha256
	return sha256


static func _texture_for_path(path: String, content_sha256: String) -> Texture2D:
	var cache_key := content_sha256 if content_sha256.length() == 64 else path
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var texture: Texture2D = null
	if OS.has_feature("editor"):
		var image_bytes := FileAccess.get_file_as_bytes(path)
		if not image_bytes.is_empty():
			var source_image := Image.new()
			if source_image.load_png_from_buffer(image_bytes) == OK:
				texture = ImageTexture.create_from_image(source_image)
	else:
		texture = ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture != null:
		_texture_cache[cache_key] = texture
	return texture


func _vector_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	var values := value as Array
	return Vector2(float(values[0]), float(values[1]))


func _is_finite_vector2_value(value: Variant) -> bool:
	if value is Vector2:
		var vector := value as Vector2
		return is_finite(vector.x) and is_finite(vector.y)
	if value is not Array:
		return false
	var values := value as Array
	if values.size() != 2:
		return false
	for component: Variant in values:
		if component is not int and component is not float:
			return false
		if not is_finite(float(component)):
			return false
	return true


func _all_finite_numbers(values: Array) -> bool:
	for value: Variant in values:
		if value is not int and value is not float:
			return false
		if not is_finite(float(value)):
			return false
	return true


func _is_integral_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is not float:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number)


func _optional_string(value: Variant) -> String:
	return "" if value == null else str(value)


func _part_z(part_id: String, manifest: Dictionary) -> int:
	var layer_order_value: Variant = manifest.get("part_layer_order", [])
	var layer_order := (
		layer_order_value as Array
		if layer_order_value is Array
		else []
	)
	var ordered_index := layer_order.find(part_id)
	if ordered_index >= 0:
		return ordered_index
	if part_id == "head":
		return 30
	if part_id.begins_with("hand_"):
		return 18
	if part_id.begins_with("forearm_") or part_id.begins_with("upper_arm_"):
		return 16
	if part_id == "torso":
		return 14
	if part_id == "pelvis":
		return 12
	if part_id.begins_with("foot_"):
		return 9
	return 8


func _direction_from_vector(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "right" if direction.x > 0.0 else "left"
	return "down" if direction.y > 0.0 else "up"


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
