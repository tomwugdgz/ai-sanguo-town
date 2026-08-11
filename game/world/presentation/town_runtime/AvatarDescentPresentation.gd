class_name AvatarDescentPresentation
extends Node2D


signal timeline_completed
signal input_unlocked
signal cue_requested(cue_id: String)


const CAMERA_GLIDE_MSEC := 250.0
const BEAM_START_MSEC := 300.0
const BEAM_IMPACT_MSEC := 480.0
const AVATAR_APPEAR_MSEC := 600.0
const LANDING_MSEC := 1000.0
const INPUT_UNLOCK_MSEC := 1100.0
const TOTAL_MSEC := 1450.0
const TARGET_ZOOM := Vector2.ONE
const AVATAR_LIFT_DISTANCE := 80.0
const REDUCED_FLASHING_SETTING := "application/accessibility/reduced_flashing"
const MAX_TRANSFORM_COMPONENT := 1_000_000.0
const MAX_INITIAL_SCALE_COMPONENT := MAX_TRANSFORM_COMPONENT / 1.15
const MAX_INITIAL_ZOOM_COMPONENT := MAX_TRANSFORM_COMPONENT / 1.05

var _visual_root: Node2D
var _shadow: CanvasItem
var _camera: Camera2D
var _dim_layer: CanvasLayer
var _dim_overlay: ColorRect
var _elapsed_msec := 0.0
var _active := false
var _cue_emitted := false
var _unlock_emitted := false
var _generation := 0
var _camera_start_global_position := Vector2.ZERO
var _camera_start_zoom := Vector2.ONE
var _camera_smoothing_enabled := true
var _shadow_start_visible := true
var _visual_start_position := Vector2.ZERO
var _visual_start_scale := Vector2.ONE
var _visual_start_modulate := Color.WHITE


func _ready() -> void:
	z_index = 2
	_dim_layer = CanvasLayer.new()
	_dim_layer.name = "AvatarDescentDimLayer"
	_dim_layer.layer = 40
	add_child(_dim_layer)
	_dim_overlay = ColorRect.new()
	_dim_overlay.name = "DimOverlay"
	_dim_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_overlay.color = Color(0.03, 0.04, 0.08, 0.0)
	_dim_overlay.visible = false
	_dim_layer.add_child(_dim_overlay)
	visible = false
	set_process(false)


func start(
	visual_root_value: Variant,
	shadow_value: Variant,
	camera_value: Variant,
) -> Dictionary:
	if (
		not is_node_ready()
		or not is_instance_valid(_dim_overlay)
		or not visual_root_value is Node2D
		or not camera_value is Camera2D
		or (shadow_value != null and not shadow_value is CanvasItem)
	):
		return {"ok": false, "errorCode": "AVATAR_DESCENT_PRESENTATION_NOT_READY"}
	var visual_root := visual_root_value as Node2D
	var shadow := shadow_value as CanvasItem
	var camera := camera_value as Camera2D
	if (
		not is_instance_valid(visual_root)
		or not is_instance_valid(camera)
		or visual_root == self
		or visual_root == camera
		or (
			shadow != null
			and (shadow == visual_root or shadow == camera)
		)
		or not _bounded_vector(global_position, MAX_TRANSFORM_COMPONENT)
		or not _bounded_vector(
			visual_root.position,
			MAX_TRANSFORM_COMPONENT - AVATAR_LIFT_DISTANCE,
		)
		or not _bounded_vector(
			visual_root.scale,
			MAX_INITIAL_SCALE_COMPONENT,
		)
		or not _finite_color(visual_root.modulate)
		or not _bounded_vector(camera.global_position, MAX_TRANSFORM_COMPONENT)
		or not _valid_zoom(camera.zoom)
	):
		return {"ok": false, "errorCode": "AVATAR_DESCENT_PRESENTATION_NOT_READY"}
	if shadow != null and not is_instance_valid(shadow):
		return {"ok": false, "errorCode": "AVATAR_DESCENT_PRESENTATION_NOT_READY"}
	if _active:
		cancel()
	_generation += 1
	_visual_root = visual_root
	_shadow = shadow
	_camera = camera
	_elapsed_msec = 0.0
	_active = true
	_cue_emitted = false
	_unlock_emitted = false
	_camera_start_global_position = _camera.global_position
	_camera_start_zoom = _camera.zoom
	_camera_smoothing_enabled = _camera.position_smoothing_enabled
	_camera.position_smoothing_enabled = false
	_visual_start_position = _visual_root.position
	_visual_start_scale = _visual_root.scale
	_visual_start_modulate = _visual_root.modulate
	_shadow_start_visible = _shadow.visible if _shadow != null else true
	_visual_root.position = _visual_start_position - Vector2(0.0, AVATAR_LIFT_DISTANCE)
	_visual_root.scale = _visual_start_scale * 1.15
	_visual_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if _shadow != null:
		_shadow.visible = false
	_dim_overlay.visible = true
	visible = true
	set_process(true)
	queue_redraw()
	return {"ok": true, "durationMsec": int(TOTAL_MSEC)}


func cancel() -> void:
	if not _active:
		return
	_restore_targets_before_unlock()
	_active = false
	_generation += 1
	visible = false
	set_process(false)
	_clear_targets()
	queue_redraw()


func _exit_tree() -> void:
	if _active:
		_restore_targets_before_unlock()
		_active = false
		_generation += 1
	_clear_targets()


func is_input_locked() -> bool:
	return _active and _elapsed_msec < INPUT_UNLOCK_MSEC


func debug_snapshot() -> Dictionary:
	return {
		"active": _active,
		"elapsedMsec": int(_elapsed_msec),
		"cueEmitted": _cue_emitted,
		"unlockEmitted": _unlock_emitted,
		"inputLocked": is_input_locked(),
	}


func _process(delta: float) -> void:
	if not _active:
		return
	if not is_finite(delta) or delta < 0.0:
		return
	if not _unlock_emitted and not _required_targets_are_valid():
		cancel()
		return
	var process_generation := _generation
	_elapsed_msec = minf(_elapsed_msec + delta * 1000.0, TOTAL_MSEC)
	if not _cue_emitted and _elapsed_msec >= BEAM_START_MSEC:
		_cue_emitted = true
		cue_requested.emit("sfx_avatar_descend")
		if not _active or _generation != process_generation:
			return
		if not _required_targets_are_valid():
			cancel()
			return
	if not _unlock_emitted:
		_update_camera()
		_update_avatar()
	if not _unlock_emitted and _elapsed_msec >= INPUT_UNLOCK_MSEC:
		_unlock_emitted = true
		_release_targets_to_consumer()
		input_unlocked.emit()
		if not _active or _generation != process_generation:
			return
	_update_dim()
	queue_redraw()
	if _elapsed_msec >= TOTAL_MSEC:
		_hide_overlay()
		_active = false
		_generation += 1
		visible = false
		set_process(false)
		_clear_targets()
		timeline_completed.emit()


func _update_camera() -> void:
	if _camera == null:
		return
	var progress := _ease_in_out_cubic(_progress(0.0, CAMERA_GLIDE_MSEC))
	var zoom_boost := 1.0 + 0.05 * sin(PI * _progress(0.0, CAMERA_GLIDE_MSEC))
	_camera.global_position = _camera_start_global_position.lerp(
		global_position,
		progress,
	)
	_camera.zoom = _camera_start_zoom.lerp(TARGET_ZOOM, progress) * zoom_boost
	if _elapsed_msec >= BEAM_IMPACT_MSEC and _elapsed_msec < 660.0:
		var shake_progress := _progress(BEAM_IMPACT_MSEC, 660.0)
		var amplitude := 5.0 * (1.0 - shake_progress)
		_camera.global_position += Vector2(
			sin(_elapsed_msec * 0.11),
			0.6 * cos(_elapsed_msec * 0.13),
		) * amplitude / maxf(_camera.zoom.x, 0.01)


func _update_avatar() -> void:
	if not is_instance_valid(_visual_root):
		return
	var alpha := 0.0
	if _elapsed_msec >= AVATAR_APPEAR_MSEC:
		alpha = _progress(AVATAR_APPEAR_MSEC, 720.0)
	var settle := _ease_out_back(_progress(AVATAR_APPEAR_MSEC, 880.0))
	_visual_root.position = _visual_start_position - Vector2(
		0.0,
		AVATAR_LIFT_DISTANCE * (1.0 - settle),
	)
	_visual_root.scale = _visual_start_scale * (1.15 - 0.15 * _ease_out_cubic(
		_progress(AVATAR_APPEAR_MSEC, 880.0)
	))
	_visual_root.modulate = Color(1.0, 1.0, 1.0, alpha)
	if is_instance_valid(_shadow):
		_shadow.visible = _elapsed_msec >= LANDING_MSEC


func _update_dim() -> void:
	if not is_instance_valid(_dim_overlay):
		return
	var alpha := 0.0
	if _elapsed_msec < BEAM_START_MSEC:
		alpha = 0.34 * _ease_in_out_cubic(_progress(0.0, BEAM_START_MSEC))
	elif _elapsed_msec < AVATAR_APPEAR_MSEC:
		alpha = 0.34
	elif _elapsed_msec < LANDING_MSEC:
		alpha = 0.34 * (1.0 - _ease_in_out_cubic(
			_progress(AVATAR_APPEAR_MSEC, LANDING_MSEC)
		))
	_dim_overlay.color = Color(0.03, 0.04, 0.08, alpha)


func _draw() -> void:
	if not _active:
		return
	var halo_alpha := _halo_alpha()
	if halo_alpha > 0.0:
		var halo_radius := 118.0 * (0.8 + 0.2 * _ease_in_out_cubic(
			_progress(0.0, BEAM_START_MSEC)
		))
		draw_arc(Vector2(0.0, -3.0), halo_radius, 0.0, TAU, 64, Color(0.72, 0.91, 1.0, halo_alpha), 5.0)
		draw_arc(Vector2(0.0, -3.0), halo_radius * 0.72, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, halo_alpha * 0.65), 2.0)
	var beam_alpha := _beam_alpha()
	if beam_alpha > 0.0:
		var half_width := 68.0 * _beam_width_factor()
		var bottom_y := lerpf(-1500.0, -8.0, _ease_in_cubic(
			_progress(BEAM_START_MSEC, BEAM_IMPACT_MSEC)
		))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-half_width * 0.38, -1500.0),
			Vector2(half_width * 0.38, -1500.0),
			Vector2(half_width, bottom_y),
			Vector2(-half_width, bottom_y),
		]), Color(0.78, 0.92, 1.0, beam_alpha * 0.7))
	var flash_alpha := _flash_alpha()
	if flash_alpha > 0.0:
		draw_circle(Vector2(0.0, -42.0), 150.0, Color(1.0, 1.0, 1.0, flash_alpha))
	if _elapsed_msec >= LANDING_MSEC and _elapsed_msec < 1320.0:
		var ripple := _ease_out_cubic(_progress(LANDING_MSEC, 1320.0))
		draw_arc(Vector2(0.0, -3.0), lerpf(24.0, 150.0, ripple), 0.0, TAU, 64, Color(0.75, 0.94, 1.0, 1.0 - ripple), 6.0)
		_draw_motes()


func _draw_motes() -> void:
	for index in 7:
		var start_msec := LANDING_MSEC + float(index * 35)
		if _elapsed_msec < start_msec or _elapsed_msec >= start_msec + 400.0:
			continue
		var progress := _progress(start_msec, start_msec + 400.0)
		var side := _stable_hash(index * 3 + 1) - 0.5
		var position := Vector2(
			side * 150.0 * (0.4 + 0.6 * progress),
			-20.0 - progress * (100.0 + 55.0 * _stable_hash(index * 3 + 2)),
		)
		draw_circle(position, 4.0 + 3.0 * _stable_hash(index * 3 + 3), Color(0.86, 0.96, 1.0, 1.0 - _ease_in_cubic(progress)))


func _restore_targets_before_unlock() -> void:
	if _unlock_emitted:
		_hide_overlay()
		return
	if is_instance_valid(_visual_root):
		_visual_root.position = _visual_start_position
		_visual_root.scale = _visual_start_scale
		_visual_root.modulate = _visual_start_modulate
	if is_instance_valid(_shadow):
		_shadow.visible = _shadow_start_visible
	if is_instance_valid(_camera):
		_camera.global_position = _camera_start_global_position
		_camera.zoom = _camera_start_zoom
		_camera.position_smoothing_enabled = _camera_smoothing_enabled
	_hide_overlay()


func _release_targets_to_consumer() -> void:
	if is_instance_valid(_visual_root):
		_visual_root.position = _visual_start_position
		_visual_root.scale = _visual_start_scale
		_visual_root.modulate = _visual_start_modulate
	if is_instance_valid(_shadow):
		_shadow.visible = _shadow_start_visible
	if is_instance_valid(_camera):
		_camera.position_smoothing_enabled = _camera_smoothing_enabled
	_clear_targets()


func _hide_overlay() -> void:
	if is_instance_valid(_dim_overlay):
		_dim_overlay.visible = false


func _clear_targets() -> void:
	_visual_root = null
	_shadow = null
	_camera = null


func _required_targets_are_valid() -> bool:
	return (
		is_instance_valid(_visual_root)
		and is_instance_valid(_camera)
		and _bounded_vector(global_position, MAX_TRANSFORM_COMPONENT)
	)


func _halo_alpha() -> float:
	if _elapsed_msec < BEAM_START_MSEC:
		return _ease_in_out_cubic(_progress(0.0, BEAM_START_MSEC))
	if _elapsed_msec < 900.0:
		return 1.0
	return 1.0 - _ease_in_out_cubic(_progress(900.0, 1150.0))


func _beam_alpha() -> float:
	if _elapsed_msec < BEAM_START_MSEC:
		return 0.0
	if _elapsed_msec < 390.0:
		return maxf(0.35, _progress(BEAM_START_MSEC, 390.0))
	if _elapsed_msec < 620.0:
		return 1.0
	return 1.0 - _ease_in_out_cubic(_progress(620.0, 900.0))


func _beam_width_factor() -> float:
	if _elapsed_msec < 620.0:
		return 1.0
	return 1.0 - 0.78 * _ease_in_out_cubic(_progress(620.0, 900.0))


func _flash_alpha() -> float:
	if _elapsed_msec < BEAM_IMPACT_MSEC or _elapsed_msec >= 570.0:
		return 0.0
	if bool(ProjectSettings.get_setting(REDUCED_FLASHING_SETTING, false)):
		return 0.0
	return 0.85 * (1.0 - _progress(BEAM_IMPACT_MSEC, 570.0))


func _progress(start_msec: float, end_msec: float) -> float:
	return clampf((_elapsed_msec - start_msec) / (end_msec - start_msec), 0.0, 1.0)


func _ease_in_out_cubic(value: float) -> float:
	return 4.0 * value * value * value if value < 0.5 else 1.0 - pow(-2.0 * value + 2.0, 3.0) / 2.0


func _ease_in_cubic(value: float) -> float:
	return value * value * value


func _ease_out_cubic(value: float) -> float:
	return 1.0 - pow(1.0 - value, 3.0)


func _ease_out_back(value: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var shifted := value - 1.0
	return 1.0 + c3 * shifted * shifted * shifted + c1 * shifted * shifted


func _stable_hash(seed: int) -> float:
	var value := sin(float(seed) * 12.9898) * 43758.5453
	return value - floorf(value)


func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


func _bounded_vector(value: Vector2, maximum: float) -> bool:
	return (
		_finite_vector(value)
		and absf(value.x) <= maximum
		and absf(value.y) <= maximum
	)


func _finite_color(value: Color) -> bool:
	return (
		is_finite(value.r)
		and is_finite(value.g)
		and is_finite(value.b)
		and is_finite(value.a)
	)


func _valid_zoom(value: Vector2) -> bool:
	return (
		_bounded_vector(value, MAX_INITIAL_ZOOM_COMPONENT)
		and value.x > 0.0
		and value.y > 0.0
	)
