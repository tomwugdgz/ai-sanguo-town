class_name TownConflictPresentation
extends Node2D


signal effect_started(effect_kind: String, subject_id: String)
signal effect_finished(effect_kind: String, subject_id: String)


const RESULT_SHAPES := preload(
	"res://world/contract/TownWorldResultShapes.gd"
)
const UNARMED_FRAME_PATHS: Array[String] = [
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_unarmed_v1/frame_00.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_unarmed_v1/frame_01.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_unarmed_v1/frame_02.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_unarmed_v1/frame_03.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_unarmed_v1/frame_04.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_unarmed_v1/frame_05.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_unarmed_v1/frame_06.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_unarmed_v1/frame_07.png",
]
const IMPROVISED_FRAME_PATHS: Array[String] = [
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_improvised_v1/frame_00.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_improvised_v1/frame_01.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_improvised_v1/frame_02.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_improvised_v1/frame_03.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_improvised_v1/frame_04.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_improvised_v1/frame_05.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_improvised_v1/frame_06.png",
	"res://assets/effects/conflict/runtime/v1/brawl_cloud_improvised_v1/frame_07.png",
]
const LIGHT_INJURY_FRAME_PATHS: Array[String] = [
	"res://assets/effects/conflict/runtime/v1/injury_light_v1/frame_00.png",
	"res://assets/effects/conflict/runtime/v1/injury_light_v1/frame_01.png",
	"res://assets/effects/conflict/runtime/v1/injury_light_v1/frame_02.png",
	"res://assets/effects/conflict/runtime/v1/injury_light_v1/frame_03.png",
	"res://assets/effects/conflict/runtime/v1/injury_light_v1/frame_04.png",
	"res://assets/effects/conflict/runtime/v1/injury_light_v1/frame_05.png",
]
const HEAVY_INJURY_FRAME_PATHS: Array[String] = [
	"res://assets/effects/conflict/runtime/v1/injury_heavy_v1/frame_00.png",
	"res://assets/effects/conflict/runtime/v1/injury_heavy_v1/frame_01.png",
	"res://assets/effects/conflict/runtime/v1/injury_heavy_v1/frame_02.png",
	"res://assets/effects/conflict/runtime/v1/injury_heavy_v1/frame_03.png",
	"res://assets/effects/conflict/runtime/v1/injury_heavy_v1/frame_04.png",
	"res://assets/effects/conflict/runtime/v1/injury_heavy_v1/frame_05.png",
]
const AVATAR_RISING_UPPERCUT_FRAME_PATHS: Array[String] = [
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_00.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_01.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_02.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_03.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_04.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_05.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_06.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_07.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_08.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_09.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_10.png",
	"res://assets/effects/conflict/runtime/v1/avatar_rising_uppercut_v1/frame_11.png",
]
const AVATAR_SUSANOO_FRAME_COUNT := 23
const AVATAR_RASENGAN_FRAME_COUNT := 22
const AVATAR_KAMEHAMEHA_FRAME_COUNT := 21
const AVATAR_RISING_UPPERCUT_LIFT_PX: Array[float] = [
	0.0, 5.0, 14.0, 28.0, 44.0, 62.0, 78.0, 90.0, 96.0, 62.0, 30.0, 0.0,
]
const AVATAR_RISING_UPPERCUT_FORWARD_PX: Array[float] = [
	0.0, 4.0, 8.0, 12.0, 18.0, 22.0, 26.0, 28.0, 28.0, 20.0, 10.0, 0.0,
]

const DEFAULT_BRAWL_FPS := 10.0
const DEFAULT_INJURY_FPS := 8.0
const DEFAULT_BRAWL_SCALE := 0.75
const DEFAULT_INJURY_SCALE := 0.35
const DEFAULT_AVATAR_ATTACK_DURATION_SECONDS := 3.0
const DEFAULT_AVATAR_ATTACK_SCALE := 1.1
const DEFAULT_AVATAR_ATTACK_FOOT_OFFSET := 104.0
const DEFAULT_RESIDENT_ATTACK_DURATION_SECONDS := 0.42
const DEFAULT_RESIDENT_ATTACK_FORWARD_PIXELS := 28.0
const DEFAULT_HIT_DURATION_SECONDS := 0.18
const DEFAULT_HIT_SHAKE_PIXELS := 4.0
const DEFAULT_LIGHT_CYCLE_SECONDS := 2.4
const DEFAULT_HEAVY_CYCLE_SECONDS := 1.2
const DEFAULT_INJURY_OFFSET := Vector2(0.0, -76.0)

var _configured := false
var _last_revision := -1
var _brawl_fps := DEFAULT_BRAWL_FPS
var _injury_fps := DEFAULT_INJURY_FPS
var _brawl_scale := DEFAULT_BRAWL_SCALE
var _injury_scale := DEFAULT_INJURY_SCALE
var _avatar_attack_duration_seconds := DEFAULT_AVATAR_ATTACK_DURATION_SECONDS
var _avatar_attack_scale := DEFAULT_AVATAR_ATTACK_SCALE
var _avatar_attack_foot_offset := DEFAULT_AVATAR_ATTACK_FOOT_OFFSET
var _hit_duration_seconds := DEFAULT_HIT_DURATION_SECONDS
var _hit_shake_pixels := DEFAULT_HIT_SHAKE_PIXELS
var _light_cycle_seconds := DEFAULT_LIGHT_CYCLE_SECONDS
var _heavy_cycle_seconds := DEFAULT_HEAVY_CYCLE_SECONDS
var _injury_offset := DEFAULT_INJURY_OFFSET
var _actors: Dictionary = {}
var _brawl_effects: Dictionary = {}
var _resident_attack_effects: Dictionary = {}
var _avatar_attack_effects: Dictionary = {}
var _completed_avatar_attack_ids: Dictionary = {}
var _injury_effects: Dictionary = {}
var _hit_reactions: Dictionary = {}
var _seen_event_ids: Dictionary = {}
var _frame_cache: Dictionary = {}


func _ready() -> void:
	set_process(true)


func _exit_tree() -> void:
	clear_all()


func _process(delta: float) -> void:
	advance_presentation(delta)


func configure(options: Dictionary = {}) -> Dictionary:
	if _configured:
		return _failure("CONFLICT_PRESENTATION_ALREADY_CONFIGURED")
	var allowed: Array[String] = [
		"brawlFps",
		"injuryFps",
		"brawlScale",
		"injuryScale",
		"avatarAttackDurationSeconds",
		"avatarAttackScale",
		"avatarAttackFootOffset",
		"hitDurationSeconds",
		"hitShakePixels",
		"lightCycleSeconds",
		"heavyCycleSeconds",
		"injuryOffset",
	]
	for key_value: Variant in options:
		if not allowed.has(String(key_value)):
			return _failure("CONFLICT_PRESENTATION_OPTIONS_INVALID")
	_brawl_fps = float(options.get("brawlFps", DEFAULT_BRAWL_FPS))
	_injury_fps = float(options.get("injuryFps", DEFAULT_INJURY_FPS))
	_brawl_scale = float(options.get("brawlScale", DEFAULT_BRAWL_SCALE))
	_injury_scale = float(options.get("injuryScale", DEFAULT_INJURY_SCALE))
	_avatar_attack_duration_seconds = float(
		options.get(
			"avatarAttackDurationSeconds",
			DEFAULT_AVATAR_ATTACK_DURATION_SECONDS,
		)
	)
	_avatar_attack_scale = float(
		options.get("avatarAttackScale", DEFAULT_AVATAR_ATTACK_SCALE)
	)
	_avatar_attack_foot_offset = float(
		options.get(
			"avatarAttackFootOffset",
			DEFAULT_AVATAR_ATTACK_FOOT_OFFSET,
		)
	)
	_hit_duration_seconds = float(
		options.get("hitDurationSeconds", DEFAULT_HIT_DURATION_SECONDS)
	)
	_hit_shake_pixels = float(
		options.get("hitShakePixels", DEFAULT_HIT_SHAKE_PIXELS)
	)
	_light_cycle_seconds = float(
		options.get("lightCycleSeconds", DEFAULT_LIGHT_CYCLE_SECONDS)
	)
	_heavy_cycle_seconds = float(
		options.get("heavyCycleSeconds", DEFAULT_HEAVY_CYCLE_SECONDS)
	)
	var offset_value: Variant = options.get(
		"injuryOffset",
		DEFAULT_INJURY_OFFSET,
	)
	if (
		_brawl_fps <= 0.0
		or _injury_fps <= 0.0
		or _brawl_scale <= 0.0
		or _injury_scale <= 0.0
		or _avatar_attack_duration_seconds <= 0.0
		or _avatar_attack_scale <= 0.0
		or _avatar_attack_foot_offset < 0.0
		or _hit_duration_seconds <= 0.0
		or _hit_shake_pixels < 0.0
		or _light_cycle_seconds <= 0.0
		or _heavy_cycle_seconds <= 0.0
		or offset_value is not Vector2
	):
		return _failure("CONFLICT_PRESENTATION_OPTIONS_INVALID")
	_injury_offset = offset_value as Vector2
	var load_result := _ensure_frames_loaded()
	if not bool(load_result.get("ok", false)):
		return load_result
	_configured = true
	return {
		"ok": true,
		"errorCode": "",
		"storageMode": "variable_size_png_per_frame",
		"unarmedFrames": UNARMED_FRAME_PATHS.size(),
		"improvisedFrames": IMPROVISED_FRAME_PATHS.size(),
		"lightInjuryFrames": LIGHT_INJURY_FRAME_PATHS.size(),
		"heavyInjuryFrames": HEAVY_INJURY_FRAME_PATHS.size(),
		"avatarRisingUppercutFrames": (
			AVATAR_RISING_UPPERCUT_FRAME_PATHS.size()
		),
	}


func register_actor(
	actor_id: String,
	authority_node: Node2D,
	visual_root: CanvasItem = null,
	actor_kind: String = "resident",
) -> Dictionary:
	var normalized_id := actor_id.strip_edges()
	if normalized_id.is_empty() or authority_node == null:
		return _failure("CONFLICT_PRESENTATION_ACTOR_INVALID")
	if _actors.has(normalized_id):
		return _failure("CONFLICT_PRESENTATION_ACTOR_ALREADY_REGISTERED")
	var resolved_visual := visual_root
	if resolved_visual == null:
		resolved_visual = authority_node
	var visual_position := Vector2.ZERO
	if resolved_visual is Node2D:
		visual_position = (resolved_visual as Node2D).position
	_actors[normalized_id] = {
		"authority": authority_node,
		"visual": resolved_visual,
		"baseVisible": resolved_visual.visible,
		"baseModulate": resolved_visual.self_modulate,
		"basePosition": visual_position,
		"hiddenByConflictId": "",
		"kind": actor_kind,
	}
	return {"ok": true, "errorCode": "", "actorId": normalized_id}


func unregister_actor(actor_id: String) -> void:
	var normalized_id := actor_id.strip_edges()
	if not _actors.has(normalized_id):
		return
	_restore_actor(normalized_id)
	_remove_injury_effect(normalized_id)
	_hit_reactions.erase(normalized_id)
	_actors.erase(normalized_id)


func apply_public_projection(projection: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("CONFLICT_PRESENTATION_NOT_CONFIGURED")
	var revision_value: Variant = projection.get("revision")
	if revision_value is not int or int(revision_value) < 0:
		return _failure("CONFLICT_PRESENTATION_PROJECTION_INVALID")
	var revision := int(revision_value)
	if revision < _last_revision:
		return {
			"ok": false,
			"errorCode": "CONFLICT_PRESENTATION_STALE_PROJECTION",
			"stale": true,
			"confirmedRevision": _last_revision,
		}
	if (
		projection.get("activeConflicts") is not Array
		or projection.get("injuries") is not Array
		or projection.get("events") is not Array
	):
		return _failure("CONFLICT_PRESENTATION_PROJECTION_INVALID")
	_consume_new_events(projection.get("events", []) as Array)
	_sync_avatar_attacks(projection.get("activeConflicts", []) as Array)
	_sync_brawls(projection.get("activeConflicts", []) as Array)
	_sync_injuries(projection.get("injuries", []) as Array)
	_last_revision = revision
	return {
		"ok": true,
		"errorCode": "",
		"confirmedRevision": revision,
		"brawlCount": _brawl_effects.size(),
		"avatarAttackCount": _avatar_attack_effects.size(),
		"injuryCount": _injury_effects.size(),
		"hitReactionCount": _hit_reactions.size(),
	}


func advance_presentation(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	_advance_brawls(safe_delta)
	_advance_resident_attacks(safe_delta)
	_advance_avatar_attacks(safe_delta)
	_advance_injuries(safe_delta)
	_advance_hit_reactions(safe_delta)


func clear_all() -> void:
	var actor_ids: Array[String] = []
	for actor_id_value: Variant in _actors:
		actor_ids.append(String(actor_id_value))
	for actor_id: String in actor_ids:
		_restore_actor(actor_id)
	for conflict_value: Variant in _brawl_effects.values():
		var effect := conflict_value as Dictionary
		var sprite := effect.get("sprite") as Sprite2D
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
	for attack_value: Variant in _avatar_attack_effects.values():
		var attack_effect := attack_value as Dictionary
		var attack_id := String(attack_effect.get("conflictId", ""))
		_restore_actor_if_owned(
			String(attack_effect.get("attackerId", "")),
			attack_id,
		)
		var attack_sprite := attack_effect.get("sprite") as Sprite2D
		if attack_sprite != null and is_instance_valid(attack_sprite):
			attack_sprite.queue_free()
	for attack_value: Variant in _resident_attack_effects.values():
		_stop_resident_attack(String((attack_value as Dictionary).get("conflictId", "")))
	for injury_value: Variant in _injury_effects.values():
		var effect := injury_value as Dictionary
		var sprite := effect.get("sprite") as Sprite2D
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
	_brawl_effects.clear()
	_resident_attack_effects.clear()
	_avatar_attack_effects.clear()
	_completed_avatar_attack_ids.clear()
	_injury_effects.clear()
	_hit_reactions.clear()
	_seen_event_ids.clear()
	_last_revision = -1


func debug_snapshot() -> Dictionary:
	var brawls: Array[Dictionary] = []
	var conflict_ids: Array[String] = []
	for conflict_id_value: Variant in _brawl_effects:
		conflict_ids.append(String(conflict_id_value))
	conflict_ids.sort()
	for conflict_id: String in conflict_ids:
		var effect := _brawl_effects[conflict_id] as Dictionary
		var sprite := effect.get("sprite") as Sprite2D
		var texture_size := Vector2.ZERO
		if sprite != null and sprite.texture != null:
			texture_size = sprite.texture.get_size()
		brawls.append({
			"conflictId": conflict_id,
			"participantIds": (effect.get("participantIds", []) as Array).duplicate(),
			"attackKind": String(effect.get("attackKind", "")),
			"frame": int(effect.get("frame", 0)),
			"textureSize": [texture_size.x, texture_size.y],
		})
	var resident_attacks: Array[Dictionary] = []
	for conflict_id: String in _sorted_dictionary_keys(_resident_attack_effects):
		var attack := _resident_attack_effects[conflict_id] as Dictionary
		var visual := attack.get("visual") as Node2D
		resident_attacks.append({
			"conflictId": conflict_id,
			"attackerId": String(attack.get("attackerId", "")),
			"targetId": String(attack.get("targetId", "")),
			"elapsedSeconds": float(attack.get("elapsed", 0.0)),
			"durationSeconds": DEFAULT_RESIDENT_ATTACK_DURATION_SECONDS,
			"forwardPixels": float(attack.get("forwardPixels", 0.0)),
			"position": (
				[visual.position.x, visual.position.y]
				if visual != null and is_instance_valid(visual)
				else []
			),
		})
	var avatar_attacks: Array[Dictionary] = []
	for conflict_id: String in _sorted_dictionary_keys(_avatar_attack_effects):
		var attack := _avatar_attack_effects[conflict_id] as Dictionary
		var attack_sprite := attack.get("sprite") as Sprite2D
		avatar_attacks.append({
			"conflictId": conflict_id,
			"attackerId": String(attack.get("attackerId", "")),
				"targetId": String(attack.get("targetId", "")),
				"hitTargetIds": (
					attack.get("hitTargetIds", []) as Array
				).duplicate(),
			"attackKind": String(attack.get("attackKind", "unarmed")),
			"frame": int(attack.get("frame", 0)),
			"frameCount": _avatar_attack_frames(
				String(attack.get("attackKind", "unarmed"))
			).size(),
			"elapsedSeconds": float(attack.get("elapsed", 0.0)),
			"durationSeconds": _avatar_attack_duration_seconds,
			"hitStarted": bool(attack.get("hitStarted", false)),
			"direction": float(attack.get("direction", 1.0)),
			"flipH": bool(attack_sprite.flip_h) if attack_sprite != null else false,
			"position": (
				[attack_sprite.global_position.x, attack_sprite.global_position.y]
				if attack_sprite != null
				else []
			),
		})
	var injuries: Array[Dictionary] = []
	var injury_ids: Array[String] = []
	for actor_id_value: Variant in _injury_effects:
		injury_ids.append(String(actor_id_value))
	injury_ids.sort()
	for actor_id: String in injury_ids:
		var effect := _injury_effects[actor_id] as Dictionary
		var sprite := effect.get("sprite") as Sprite2D
		var texture_size := Vector2.ZERO
		if sprite != null and sprite.texture != null:
			texture_size = sprite.texture.get_size()
		injuries.append({
			"actorId": actor_id,
			"severity": String(effect.get("severity", "")),
			"frame": int(effect.get("frame", 0)),
			"visible": sprite != null and sprite.visible,
			"textureSize": [texture_size.x, texture_size.y],
		})
	return {
		"configured": _configured,
		"confirmedRevision": _last_revision,
		"registeredActorIds": _sorted_dictionary_keys(_actors),
		"brawls": brawls,
		"residentAttacks": resident_attacks,
		"avatarAttacks": avatar_attacks,
		"injuries": injuries,
		"hitReactionActorIds": _sorted_dictionary_keys(_hit_reactions),
		"storageMode": "variable_size_png_per_frame",
	}


func _ensure_frames_loaded() -> Dictionary:
	var required_lists: Array[Array] = [
		UNARMED_FRAME_PATHS,
		IMPROVISED_FRAME_PATHS,
		LIGHT_INJURY_FRAME_PATHS,
		HEAVY_INJURY_FRAME_PATHS,
		AVATAR_RISING_UPPERCUT_FRAME_PATHS,
		_avatar_generated_frame_paths("avatar_susanoo_strike", AVATAR_SUSANOO_FRAME_COUNT),
		_avatar_generated_frame_paths("avatar_rasengan", AVATAR_RASENGAN_FRAME_COUNT),
		_avatar_generated_frame_paths("avatar_kamehameha", AVATAR_KAMEHAMEHA_FRAME_COUNT),
	]
	for untyped_path_list: Array in required_lists:
		var path_list: Array[String] = []
		for path_value: Variant in untyped_path_list:
			path_list.append(String(path_value))
		for path: String in path_list:
			var resource := ResourceLoader.load(path)
			if resource is not Texture2D:
				return _failure(
					"CONFLICT_PRESENTATION_ASSET_UNAVAILABLE",
					{"path": path},
				)
			_frame_cache[path] = resource
	return {"ok": true, "errorCode": ""}


func _consume_new_events(events: Array) -> void:
	for event_value: Variant in events:
		if event_value is not Dictionary:
			continue
		var event := event_value as Dictionary
		var event_id := String(event.get("eventId", "")).strip_edges()
		if event_id.is_empty() or _seen_event_ids.has(event_id):
			continue
		if _consume_event(event):
			_seen_event_ids[event_id] = true


func _consume_event(event: Dictionary) -> bool:
	var event_type := String(event.get("type", ""))
	if event_type == "avatar_area_attack_cast":
		var conflict_id := String(event.get("conflictId", "")).strip_edges()
		var source_id := String(event.get("sourceActorId", "")).strip_edges()
		var actor_ids_value: Variant = event.get("actorIds", [])
		if conflict_id.is_empty() or source_id.is_empty() or actor_ids_value is not Array:
			return true
		if not _actors.has(source_id):
			return false
		var hit_target_ids: Array[String] = []
		var hit_target_ids_value: Variant = event.get("hitTargetIds", [])
		if hit_target_ids_value is Array:
			hit_target_ids = _string_array(hit_target_ids_value as Array)
		if hit_target_ids.is_empty():
			for actor_id: String in _string_array(actor_ids_value as Array):
				if actor_id != source_id:
					hit_target_ids.append(actor_id)
		var attack_kind := String(
			event.get("attackKind", event.get("reason", "unarmed"))
		)
		_start_avatar_rising_uppercut(
			conflict_id,
			source_id,
			hit_target_ids[0] if not hit_target_ids.is_empty() else "",
			attack_kind,
			true,
			hit_target_ids,
		)
		return (
			_avatar_attack_effects.has(conflict_id)
			or _completed_avatar_attack_ids.has(conflict_id)
		)
	if event_type == "unilateral_hit_confirmed":
		var subject_id := String(event.get("subjectId", "")).strip_edges()
		if subject_id.is_empty():
			return true
		var source_id := String(event.get("sourceActorId", "")).strip_edges()
		var conflict_id := String(event.get("conflictId", "")).strip_edges()
		if _actor_kind(source_id) == "avatar":
			if conflict_id.is_empty():
				return true
			_start_avatar_rising_uppercut(
				conflict_id,
				source_id,
				subject_id,
				String(event.get("reason", "unarmed")),
				true,
			)
			return (
				_avatar_attack_effects.has(conflict_id)
				or _completed_avatar_attack_ids.has(conflict_id)
			)
		if not _actors.has(subject_id):
			return false
		if not source_id.is_empty() and _actor_kind(source_id) == "resident":
			_start_resident_attack(source_id, subject_id, conflict_id)
		_start_hit_reaction(subject_id)
		return _hit_reactions.has(subject_id)
	return true


func _sync_avatar_attacks(conflicts: Array) -> void:
	var active_ids: Dictionary = {}
	for conflict_value: Variant in conflicts:
		if conflict_value is not Dictionary:
			continue
		var conflict := conflict_value as Dictionary
		var conflict_id := String(
			conflict.get("conflictId", "")
		).strip_edges()
		var presentation := conflict.get("presentation", {}) as Dictionary
		if (
			conflict_id.is_empty()
			or String(presentation.get("mode", ""))
			!= "avatar_rising_uppercut"
			or String(conflict.get("sourceKind", "")) != "avatar_intent"
		):
			continue
		active_ids[conflict_id] = true
		if (
			not _avatar_attack_effects.has(conflict_id)
			and not _completed_avatar_attack_ids.has(conflict_id)
		):
			_start_avatar_rising_uppercut(
				conflict_id,
				String(conflict.get("attackerId", "")),
				String(conflict.get("targetId", "")),
				String(conflict.get("attackKind", "unarmed")),
			)
	for conflict_id: String in _sorted_dictionary_keys(_avatar_attack_effects):
		var effect := _avatar_attack_effects[conflict_id] as Dictionary
		if (
			not active_ids.has(conflict_id)
			and not bool(effect.get("eventDriven", false))
		):
			_stop_avatar_rising_uppercut(conflict_id, false)
	for conflict_id: String in _sorted_dictionary_keys(
		_completed_avatar_attack_ids
	):
		if not active_ids.has(conflict_id):
			_completed_avatar_attack_ids.erase(conflict_id)


func _start_avatar_rising_uppercut(
	conflict_id: String,
	attacker_id: String,
	target_id: String,
	attack_kind := "unarmed",
	event_driven := false,
	hit_target_ids: Array[String] = [],
) -> void:
	if (
		conflict_id.is_empty()
		or _avatar_attack_effects.has(conflict_id)
		or _completed_avatar_attack_ids.has(conflict_id)
	):
		return
	if not _actors.has(attacker_id):
		return
	var attacker := _actors[attacker_id] as Dictionary
	var attacker_authority := attacker.get("authority") as Node2D
	if (
		attacker_authority == null
		or not is_instance_valid(attacker_authority)
	):
		return
	var resolved_hit_target_ids := hit_target_ids.duplicate()
	if resolved_hit_target_ids.is_empty() and not target_id.is_empty():
		resolved_hit_target_ids.append(target_id)
	var direction_name := _horizontal_direction_name_for_actor(attacker_id)
	var direction := -1.0 if direction_name == "left" else 1.0
	if direction_name.is_empty() and not target_id.is_empty() and _actors.has(target_id):
		var target := _actors[target_id] as Dictionary
		var target_authority := target.get("authority") as Node2D
		if target_authority != null and is_instance_valid(target_authority):
			direction = (
				-1.0
				if target_authority.global_position.x
				< attacker_authority.global_position.x
				else 1.0
			)
	var sprite := Sprite2D.new()
	var normalized_attack_kind := _normalized_avatar_attack_kind(attack_kind)
	sprite.name = "AvatarSkillAttack_%s" % conflict_id
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 1002
	var skill_scale := _avatar_attack_scale_for_kind(normalized_attack_kind)
	sprite.scale = Vector2.ONE * skill_scale
	# Attack frames are authored facing right. Mirror from the attacker's
	# CharacterSprite direction instead of using the target position.
	sprite.flip_h = direction < 0.0
	add_child(sprite)
	_avatar_attack_effects[conflict_id] = {
		"conflictId": conflict_id,
		"attackerId": attacker_id,
		"targetId": target_id,
		"hitTargetIds": resolved_hit_target_ids,
		"attackKind": normalized_attack_kind,
		"sprite": sprite,
		"direction": direction,
		"elapsed": 0.0,
		"frame": 0,
		"hitStarted": false,
		"eventDriven": event_driven,
	}
	_hide_actor_for_brawl(attacker_id, conflict_id)
	_set_avatar_attack_frame(conflict_id, 0)
	_update_avatar_attack_anchor(conflict_id, 0)
	effect_started.emit(_avatar_attack_effect_kind(normalized_attack_kind), conflict_id)


func _stop_avatar_rising_uppercut(
	conflict_id: String,
	completed: bool,
) -> void:
	if not _avatar_attack_effects.has(conflict_id):
		return
	var effect := _avatar_attack_effects[conflict_id] as Dictionary
	_restore_actor_if_owned(
		String(effect.get("attackerId", "")),
		conflict_id,
	)
	var sprite := effect.get("sprite") as Sprite2D
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
	_avatar_attack_effects.erase(conflict_id)
	if completed:
		_completed_avatar_attack_ids[conflict_id] = true
	effect_finished.emit(
		_avatar_attack_effect_kind(String(effect.get("attackKind", "unarmed"))),
		conflict_id,
	)


func _horizontal_direction_name_for_actor(actor_id: String) -> String:
	if not _actors.has(actor_id):
		return ""
	var actor := _actors[actor_id] as Dictionary
	var visual := actor.get("visual") as Node
	if visual == null or not is_instance_valid(visual):
		return ""
	var character_sprite := visual.find_child("CharacterSprite", true, false)
	if (
		character_sprite != null
		and character_sprite.has_method("get_direction_name")
	):
		var direction_name := String(
			character_sprite.call("get_direction_name")
		).strip_edges()
		if direction_name == "left" or direction_name == "right":
			return direction_name
	return ""


func _start_resident_attack(
	attacker_id: String,
	target_id: String,
	conflict_id: String,
) -> void:
	if (
		conflict_id.is_empty()
		or _resident_attack_effects.has(conflict_id)
		or not _actors.has(attacker_id)
	):
		return
	var attacker := _actors[attacker_id] as Dictionary
	var target := _actors.get(target_id, {}) as Dictionary
	var authority := attacker.get("authority") as Node2D
	var visual := attacker.get("visual") as Node2D
	if authority == null or visual == null or not is_instance_valid(authority):
		return
	var target_authority := target.get("authority") as Node2D
	var direction := Vector2.RIGHT
	if target_authority != null and is_instance_valid(target_authority):
		direction = target_authority.global_position - authority.global_position
		if direction.length_squared() <= 0.001:
			direction = Vector2.RIGHT
		else:
			direction = direction.normalized()
	var forward_pixels := minf(
		DEFAULT_RESIDENT_ATTACK_FORWARD_PIXELS,
		authority.global_position.distance_to(target_authority.global_position) * 0.35
		if target_authority != null and is_instance_valid(target_authority)
		else DEFAULT_RESIDENT_ATTACK_FORWARD_PIXELS,
	)
	var original_direction := ""
	if authority.has_method("get_direction_name"):
		original_direction = String(authority.call("get_direction_name"))
	if authority.has_method("face_direction"):
		authority.call("face_direction", direction)
	_resident_attack_effects[conflict_id] = {
		"conflictId": conflict_id,
		"attackerId": attacker_id,
		"targetId": target_id,
		"visual": visual,
		"basePosition": visual.position,
		"direction": direction,
		"forwardPixels": forward_pixels,
		"originalDirection": original_direction,
		"elapsed": 0.0,
	}
	effect_started.emit("resident_attack", conflict_id)


func _advance_resident_attacks(delta: float) -> void:
	for conflict_id: String in _sorted_dictionary_keys(_resident_attack_effects):
		if not _resident_attack_effects.has(conflict_id):
			continue
		var effect := _resident_attack_effects[conflict_id] as Dictionary
		var visual := effect.get("visual") as Node2D
		if visual == null or not is_instance_valid(visual):
			_stop_resident_attack(conflict_id)
			continue
		var elapsed := float(effect.get("elapsed", 0.0)) + delta
		var phase := clampf(elapsed / DEFAULT_RESIDENT_ATTACK_DURATION_SECONDS, 0.0, 1.0)
		var forward := sin(phase * PI) * float(effect.get("forwardPixels", 0.0))
		visual.position = effect.get("basePosition", Vector2.ZERO) as Vector2 + effect.get("direction", Vector2.RIGHT) as Vector2 * forward
		effect["elapsed"] = elapsed
		_resident_attack_effects[conflict_id] = effect
		if phase >= 1.0:
			_stop_resident_attack(conflict_id)


func _stop_resident_attack(conflict_id: String) -> void:
	if not _resident_attack_effects.has(conflict_id):
		return
	var effect := _resident_attack_effects[conflict_id] as Dictionary
	var visual := effect.get("visual") as Node2D
	if visual != null and is_instance_valid(visual):
		visual.position = effect.get("basePosition", Vector2.ZERO) as Vector2
	var attacker_id := String(effect.get("attackerId", ""))
	if _actors.has(attacker_id):
		var authority := (_actors[attacker_id] as Dictionary).get("authority") as Node2D
		var original_direction := String(effect.get("originalDirection", ""))
		if authority != null and is_instance_valid(authority) and not original_direction.is_empty() and authority.has_method("set_direction"):
			authority.call("set_direction", original_direction)
	_resident_attack_effects.erase(conflict_id)
	effect_finished.emit("resident_attack", conflict_id)


func _sync_brawls(conflicts: Array) -> void:
	var active_ids: Dictionary = {}
	for conflict_value: Variant in conflicts:
		if conflict_value is not Dictionary:
			continue
		var conflict := conflict_value as Dictionary
		var conflict_id := String(conflict.get("conflictId", "")).strip_edges()
		var presentation := conflict.get("presentation", {}) as Dictionary
		if (
			conflict_id.is_empty()
			or String(presentation.get("mode", "")) != "shared_brawl_cloud"
			or not bool(presentation.get("hideParticipantSprites", false))
		):
			continue
		active_ids[conflict_id] = true
		var participants := _string_array(
			conflict.get("participantIds", []) as Array
		)
		if not _brawl_effects.has(conflict_id):
			_start_brawl(
				conflict_id,
				participants,
				String(conflict.get("attackKind", "unarmed")),
			)
		else:
			_update_brawl_participants(conflict_id, participants)
	var existing_ids := _sorted_dictionary_keys(_brawl_effects)
	for conflict_id: String in existing_ids:
		if not active_ids.has(conflict_id):
			_stop_brawl(conflict_id)


func _sync_injuries(injuries: Array) -> void:
	var active_ids: Dictionary = {}
	for injury_value: Variant in injuries:
		if injury_value is not Dictionary:
			continue
		var injury := injury_value as Dictionary
		var actor_id := String(injury.get("actorId", "")).strip_edges()
		var severity := String(injury.get("severity", ""))
		if actor_id.is_empty() or severity not in ["light", "heavy"]:
			continue
		active_ids[actor_id] = true
		if not _injury_effects.has(actor_id):
			_start_injury_effect(actor_id, severity)
		elif String(
			(_injury_effects[actor_id] as Dictionary).get("severity", "")
		) != severity:
			_remove_injury_effect(actor_id)
			_start_injury_effect(actor_id, severity)
	var existing_ids := _sorted_dictionary_keys(_injury_effects)
	for actor_id: String in existing_ids:
		if not active_ids.has(actor_id):
			_remove_injury_effect(actor_id)


func _start_brawl(
	conflict_id: String,
	participant_ids: Array[String],
	attack_kind: String,
) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "BrawlCloud_%s" % conflict_id
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 1000
	sprite.scale = Vector2.ONE * _brawl_scale
	add_child(sprite)
	var normalized_kind := (
		"improvised" if attack_kind == "improvised" else "unarmed"
	)
	_brawl_effects[conflict_id] = {
		"sprite": sprite,
		"participantIds": participant_ids.duplicate(),
		"attackKind": normalized_kind,
		"elapsed": 0.0,
		"frame": 0,
	}
	_update_brawl_participants(conflict_id, participant_ids)
	_set_brawl_frame(conflict_id, 0)
	effect_started.emit("brawl", conflict_id)


func _update_brawl_participants(
	conflict_id: String,
	participant_ids: Array[String],
) -> void:
	if not _brawl_effects.has(conflict_id):
		return
	var effect := _brawl_effects[conflict_id] as Dictionary
	var previous := _string_array(effect.get("participantIds", []) as Array)
	for actor_id: String in previous:
		if not participant_ids.has(actor_id):
			_restore_actor_if_owned(actor_id, conflict_id)
	for actor_id: String in participant_ids:
		_hide_actor_for_brawl(actor_id, conflict_id)
	effect["participantIds"] = participant_ids.duplicate()
	_brawl_effects[conflict_id] = effect


func _stop_brawl(conflict_id: String) -> void:
	if not _brawl_effects.has(conflict_id):
		return
	var effect := _brawl_effects[conflict_id] as Dictionary
	for actor_id: String in _string_array(
		effect.get("participantIds", []) as Array
	):
		_restore_actor_if_owned(actor_id, conflict_id)
	var sprite := effect.get("sprite") as Sprite2D
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
	_brawl_effects.erase(conflict_id)
	effect_finished.emit("brawl", conflict_id)


func _start_injury_effect(actor_id: String, severity: String) -> void:
	if not _actors.has(actor_id):
		return
	var sprite := Sprite2D.new()
	sprite.name = "Injury_%s" % actor_id
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 1001
	sprite.scale = Vector2.ONE * _injury_scale
	add_child(sprite)
	_injury_effects[actor_id] = {
		"sprite": sprite,
		"severity": severity,
		"elapsed": 0.0,
		"frame": 0,
	}
	_set_injury_frame(actor_id, 0)
	effect_started.emit("injury_%s" % severity, actor_id)


func _remove_injury_effect(actor_id: String) -> void:
	if not _injury_effects.has(actor_id):
		return
	var effect := _injury_effects[actor_id] as Dictionary
	var severity := String(effect.get("severity", ""))
	var sprite := effect.get("sprite") as Sprite2D
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
	_injury_effects.erase(actor_id)
	effect_finished.emit("injury_%s" % severity, actor_id)


func _start_hit_reaction(actor_id: String, launch_upward := false) -> void:
	if not _actors.has(actor_id):
		return
	var actor := _actors[actor_id] as Dictionary
	var visual := actor.get("visual") as CanvasItem
	if visual == null or not is_instance_valid(visual):
		return
	_restore_hit_reaction(actor_id)
	var base_position := Vector2.ZERO
	if visual is Node2D:
		base_position = (visual as Node2D).position
	_hit_reactions[actor_id] = {
		"elapsed": 0.0,
		"pendingFirstAdvance": true,
		"baseModulate": visual.self_modulate,
		"basePosition": base_position,
		"launchUpward": launch_upward,
		"durationSeconds": 0.55 if launch_upward else _hit_duration_seconds,
	}
	effect_started.emit("unilateral_hit", actor_id)


func _advance_brawls(delta: float) -> void:
	for conflict_id: String in _sorted_dictionary_keys(_brawl_effects):
		var effect := _brawl_effects[conflict_id] as Dictionary
		var elapsed := float(effect.get("elapsed", 0.0)) + delta
		var frames := _brawl_frames(String(effect.get("attackKind", "")))
		var frame_index := floori(elapsed * _brawl_fps) % frames.size()
		effect["elapsed"] = elapsed
		effect["frame"] = frame_index
		_brawl_effects[conflict_id] = effect
		_set_brawl_frame(conflict_id, frame_index)
		_update_brawl_anchor(conflict_id)


func _advance_avatar_attacks(delta: float) -> void:
	for conflict_id: String in _sorted_dictionary_keys(
		_avatar_attack_effects
	):
		var effect := _avatar_attack_effects[conflict_id] as Dictionary
		var attack_kind := String(effect.get("attackKind", "unarmed"))
		var frames := _avatar_attack_frames(attack_kind)
		var animation_seconds := _avatar_attack_duration_seconds
		var skill_fps := float(frames.size()) / animation_seconds
		var elapsed := float(effect.get("elapsed", 0.0)) + delta
		if elapsed >= animation_seconds:
			_stop_avatar_rising_uppercut(conflict_id, true)
			continue
		var frame_index := mini(
			floori(elapsed * skill_fps),
			frames.size() - 1,
		)
		effect["elapsed"] = elapsed
		effect["frame"] = frame_index
		if (
			frame_index >= _avatar_attack_contact_frame(attack_kind)
			and not bool(effect.get("hitStarted", false))
		):
			for target_id: String in _string_array(
				effect.get("hitTargetIds", []) as Array
			):
				_start_hit_reaction(
					target_id,
					attack_kind == "unarmed",
				)
			effect["hitStarted"] = true
		_avatar_attack_effects[conflict_id] = effect
		_set_avatar_attack_frame(conflict_id, frame_index)
		_update_avatar_attack_anchor(conflict_id, frame_index)


func _advance_injuries(delta: float) -> void:
	for actor_id: String in _sorted_dictionary_keys(_injury_effects):
		if not _actors.has(actor_id):
			_remove_injury_effect(actor_id)
			continue
		var effect := _injury_effects[actor_id] as Dictionary
		var severity := String(effect.get("severity", ""))
		var elapsed := float(effect.get("elapsed", 0.0)) + delta
		var frames := _injury_frames(severity)
		var animation_seconds := float(frames.size()) / _injury_fps
		var cycle_seconds := (
			_heavy_cycle_seconds
			if severity == "heavy"
			else _light_cycle_seconds
		)
		cycle_seconds = maxf(cycle_seconds, animation_seconds)
		var cycle_elapsed := fmod(elapsed, cycle_seconds)
		var sprite := effect.get("sprite") as Sprite2D
		if sprite != null:
			var actor := _actors.get(actor_id, {}) as Dictionary
			var authority := actor.get("authority") as Node2D
			var actor_is_visible := (
				authority != null
				and is_instance_valid(authority)
				and authority.visible
				and String(actor.get("hiddenByConflictId", "")).is_empty()
			)
			sprite.visible = (
				actor_is_visible
				and cycle_elapsed < animation_seconds
			)
			if sprite.visible:
				var frame_index := mini(
					floori(cycle_elapsed * _injury_fps),
					frames.size() - 1,
				)
				effect["frame"] = frame_index
				_set_injury_frame(actor_id, frame_index)
			_update_injury_anchor(actor_id)
		effect["elapsed"] = elapsed
		_injury_effects[actor_id] = effect


func _advance_hit_reactions(delta: float) -> void:
	for actor_id: String in _sorted_dictionary_keys(_hit_reactions):
		if not _actors.has(actor_id):
			_hit_reactions.erase(actor_id)
			continue
		var reaction := _hit_reactions[actor_id] as Dictionary
		var pending_first_advance := bool(
			reaction.get("pendingFirstAdvance", false)
		)
		var elapsed := float(reaction.get("elapsed", 0.0))
		if pending_first_advance:
			reaction["pendingFirstAdvance"] = false
		else:
			elapsed += delta
		var actor := _actors[actor_id] as Dictionary
		var visual := actor.get("visual") as CanvasItem
		if visual == null or not is_instance_valid(visual):
			_hit_reactions.erase(actor_id)
			continue
		var duration_seconds := float(
			reaction.get("durationSeconds", _hit_duration_seconds)
		)
		if elapsed >= duration_seconds:
			_restore_hit_reaction(actor_id)
			effect_finished.emit("unilateral_hit", actor_id)
			continue
		var phase := elapsed / duration_seconds
		visual.self_modulate = Color(1.0, 0.18, 0.18, 1.0)
		if visual is Node2D:
			var shake_sign := -1.0 if floori(phase * 8.0) % 2 == 0 else 1.0
			var launch_y := 0.0
			if bool(reaction.get("launchUpward", false)):
				launch_y = -maxf(sin(phase * PI) * 42.0, 1.0)
			(visual as Node2D).position = (
				reaction.get("basePosition", Vector2.ZERO) as Vector2
				+ Vector2(shake_sign * _hit_shake_pixels, launch_y)
			)
		reaction["elapsed"] = elapsed
		_hit_reactions[actor_id] = reaction


func _restore_hit_reaction(actor_id: String) -> void:
	if not _hit_reactions.has(actor_id) or not _actors.has(actor_id):
		_hit_reactions.erase(actor_id)
		return
	var reaction := _hit_reactions[actor_id] as Dictionary
	var actor := _actors[actor_id] as Dictionary
	var visual := actor.get("visual") as CanvasItem
	if visual != null and is_instance_valid(visual):
		visual.self_modulate = reaction.get(
			"baseModulate",
			actor.get("baseModulate", Color.WHITE),
		) as Color
		if visual is Node2D:
			(visual as Node2D).position = reaction.get(
				"basePosition",
				actor.get("basePosition", Vector2.ZERO),
			) as Vector2
	_hit_reactions.erase(actor_id)


func _hide_actor_for_brawl(actor_id: String, conflict_id: String) -> void:
	if not _actors.has(actor_id):
		return
	var actor := _actors[actor_id] as Dictionary
	var owner := String(actor.get("hiddenByConflictId", ""))
	if owner == conflict_id:
		return
	if not owner.is_empty():
		return
	var visual := actor.get("visual") as CanvasItem
	if visual != null and is_instance_valid(visual):
		actor["baseVisible"] = visual.visible
		visual.visible = false
	actor["hiddenByConflictId"] = conflict_id
	_actors[actor_id] = actor


func _restore_actor_if_owned(actor_id: String, conflict_id: String) -> void:
	if not _actors.has(actor_id):
		return
	var actor := _actors[actor_id] as Dictionary
	if String(actor.get("hiddenByConflictId", "")) != conflict_id:
		return
	var visual := actor.get("visual") as CanvasItem
	if visual != null and is_instance_valid(visual):
		visual.visible = bool(actor.get("baseVisible", true))
	actor["hiddenByConflictId"] = ""
	_actors[actor_id] = actor


func _restore_actor(actor_id: String) -> void:
	if not _actors.has(actor_id):
		return
	_restore_hit_reaction(actor_id)
	var actor := _actors[actor_id] as Dictionary
	var visual := actor.get("visual") as CanvasItem
	if visual != null and is_instance_valid(visual):
		visual.visible = bool(actor.get("baseVisible", true))
		visual.self_modulate = actor.get("baseModulate", Color.WHITE) as Color
		if visual is Node2D:
			(visual as Node2D).position = actor.get(
				"basePosition",
				Vector2.ZERO,
			) as Vector2
	actor["hiddenByConflictId"] = ""
	_actors[actor_id] = actor


func _set_brawl_frame(conflict_id: String, frame_index: int) -> void:
	if not _brawl_effects.has(conflict_id):
		return
	var effect := _brawl_effects[conflict_id] as Dictionary
	var sprite := effect.get("sprite") as Sprite2D
	var frames := _brawl_frames(String(effect.get("attackKind", "")))
	if sprite != null and not frames.is_empty():
		sprite.texture = frames[clampi(frame_index, 0, frames.size() - 1)]


func _set_injury_frame(actor_id: String, frame_index: int) -> void:
	if not _injury_effects.has(actor_id):
		return
	var effect := _injury_effects[actor_id] as Dictionary
	var sprite := effect.get("sprite") as Sprite2D
	var frames := _injury_frames(String(effect.get("severity", "")))
	if sprite != null and not frames.is_empty():
		sprite.texture = frames[clampi(frame_index, 0, frames.size() - 1)]


func _set_avatar_attack_frame(conflict_id: String, frame_index: int) -> void:
	if not _avatar_attack_effects.has(conflict_id):
		return
	var effect := _avatar_attack_effects[conflict_id] as Dictionary
	var sprite := effect.get("sprite") as Sprite2D
	var frames := _avatar_attack_frames(String(effect.get("attackKind", "unarmed")))
	if sprite != null and not frames.is_empty():
		sprite.texture = frames[clampi(frame_index, 0, frames.size() - 1)]


func _update_avatar_attack_anchor(conflict_id: String, frame_index: int) -> void:
	if not _avatar_attack_effects.has(conflict_id):
		return
	var effect := _avatar_attack_effects[conflict_id] as Dictionary
	var attacker_id := String(effect.get("attackerId", ""))
	if not _actors.has(attacker_id):
		return
	var attacker := _actors[attacker_id] as Dictionary
	var authority := attacker.get("authority") as Node2D
	var sprite := effect.get("sprite") as Sprite2D
	if authority == null or sprite == null or not is_instance_valid(authority):
		return
	var direction := float(effect.get("direction", 1.0))
	var attack_kind := String(effect.get("attackKind", "unarmed"))
	var lift := 0.0
	var forward := 0.0
	if attack_kind == "unarmed":
		var index := clampi(
			frame_index,
			0,
			AVATAR_RISING_UPPERCUT_LIFT_PX.size() - 1,
		)
		lift = AVATAR_RISING_UPPERCUT_LIFT_PX[index]
		forward = AVATAR_RISING_UPPERCUT_FORWARD_PX[index]
	sprite.global_position = authority.global_position + Vector2(
		forward * direction,
		-_avatar_attack_foot_offset - lift,
	)


func _avatar_generated_frame_paths(folder: String, count: int) -> Array[String]:
	var paths: Array[String] = []
	for index: int in count:
		paths.append(
			"res://assets/effects/conflict/runtime/v1/%s/frame_%02d.png"
			% [folder, index]
		)
	return paths


func _normalized_avatar_attack_kind(attack_kind: String) -> String:
	return attack_kind if attack_kind in [
		"unarmed",
		"avatar_susanoo_strike",
		"avatar_rasengan",
		"avatar_kamehameha",
	] else "unarmed"


func _avatar_attack_frames(attack_kind: String) -> Array[Texture2D]:
	match _normalized_avatar_attack_kind(attack_kind):
		"avatar_susanoo_strike":
			return _textures_for_paths(_avatar_generated_frame_paths("avatar_susanoo_strike", AVATAR_SUSANOO_FRAME_COUNT))
		"avatar_rasengan":
			return _textures_for_paths(_avatar_generated_frame_paths("avatar_rasengan", AVATAR_RASENGAN_FRAME_COUNT))
		"avatar_kamehameha":
			return _textures_for_paths(_avatar_generated_frame_paths("avatar_kamehameha", AVATAR_KAMEHAMEHA_FRAME_COUNT))
		_:
			return _textures_for_paths(AVATAR_RISING_UPPERCUT_FRAME_PATHS)


func _avatar_attack_contact_frame(attack_kind: String) -> int:
	match _normalized_avatar_attack_kind(attack_kind):
		"avatar_susanoo_strike":
			return 10
		"avatar_rasengan", "avatar_kamehameha":
			return 15
		_:
			return 2


func _avatar_attack_scale_for_kind(attack_kind: String) -> float:
	return _avatar_attack_scale if attack_kind == "unarmed" else 1.0


func _avatar_attack_effect_kind(attack_kind: String) -> String:
	return "avatar_rising_uppercut" if attack_kind == "unarmed" else attack_kind


func _update_brawl_anchor(conflict_id: String) -> void:
	if not _brawl_effects.has(conflict_id):
		return
	var effect := _brawl_effects[conflict_id] as Dictionary
	var total := Vector2.ZERO
	var count := 0
	for actor_id: String in _string_array(
		effect.get("participantIds", []) as Array
	):
		if not _actors.has(actor_id):
			continue
		var actor := _actors[actor_id] as Dictionary
		var authority := actor.get("authority") as Node2D
		if authority == null or not is_instance_valid(authority):
			continue
		total += authority.global_position
		count += 1
	var sprite := effect.get("sprite") as Sprite2D
	if sprite != null and count > 0:
		sprite.global_position = total / float(count) + Vector2(0.0, -60.0)


func _update_injury_anchor(actor_id: String) -> void:
	if not _injury_effects.has(actor_id) or not _actors.has(actor_id):
		return
	var effect := _injury_effects[actor_id] as Dictionary
	var sprite := effect.get("sprite") as Sprite2D
	var actor := _actors[actor_id] as Dictionary
	var authority := actor.get("authority") as Node2D
	if sprite != null and authority != null and is_instance_valid(authority):
		sprite.global_position = authority.global_position + _injury_offset


func _brawl_frames(attack_kind: String) -> Array[Texture2D]:
	return _textures_for_paths(
		IMPROVISED_FRAME_PATHS
		if attack_kind == "improvised"
		else UNARMED_FRAME_PATHS
	)


func _injury_frames(severity: String) -> Array[Texture2D]:
	return _textures_for_paths(
		HEAVY_INJURY_FRAME_PATHS
		if severity == "heavy"
		else LIGHT_INJURY_FRAME_PATHS
	)


func _actor_kind(actor_id: String) -> String:
	if not _actors.has(actor_id):
		return ""
	return String((_actors[actor_id] as Dictionary).get("kind", "resident"))


func _textures_for_paths(paths: Array[String]) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for path: String in paths:
		textures.append(_frame_cache[path] as Texture2D)
	return textures


func _string_array(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		var text := String(value).strip_edges()
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result


func _sorted_dictionary_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key_value: Variant in values:
		result.append(String(key_value))
	result.sort()
	return result


func _failure(error_code: String, extra: Dictionary = {}) -> Dictionary:
	var result := RESULT_SHAPES.failure(error_code)
	for key_value: Variant in extra:
		result[key_value] = extra[key_value]
	return result
