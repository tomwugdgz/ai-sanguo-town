extends RefCounted


const META_KEY := &"provider_settings_button_motion"
const HOVER_SCALE := Vector2(1.015, 1.015)
const PRESS_SCALE := Vector2(0.97, 0.97)
const RELEASE_SCALE := Vector2(1.025, 1.025)
const REST_MODULATE := Color.WHITE
const HOVER_MODULATE := Color(1.04, 1.04, 1.02, 1.0)
const PRESS_MODULATE := Color(0.90, 0.90, 0.88, 1.0)
const LOADING_MODULATE := Color(1.0, 1.0, 1.0, 0.72)
const HOVER_SECONDS := 0.08
const PRESS_SECONDS := 0.045
const RELEASE_SECONDS := 0.07
const REST_SECONDS := 0.10
const LOADING_HALF_CYCLE_SECONDS := 0.46


static func attach(button: BaseButton) -> Dictionary:
	if button == null:
		return {}
	var current: Variant = button.get_meta(META_KEY, {})
	if current is Dictionary and bool(current.get("bound", false)):
		return current
	var state := {
		"bound": true,
		"hovered": false,
		"pressed": false,
		"focused": false,
		"loading": false,
		"reduced_motion": _prefers_reduced_motion(),
		"motion_tween": null,
		"loading_tween": null,
	}
	button.set_meta(META_KEY, state)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.mouse_entered.connect(_on_mouse_entered.bind(button))
	button.mouse_exited.connect(_on_mouse_exited.bind(button))
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))
	button.focus_entered.connect(_on_focus_entered.bind(button))
	button.focus_exited.connect(_on_focus_exited.bind(button))
	button.resized.connect(_update_pivot.bind(button))
	button.tree_exiting.connect(_on_tree_exiting.bind(button))
	_update_pivot(button)
	return state


static func set_loading_state(button: BaseButton, active: bool) -> void:
	attach(button)
	_set_loading(button, active)


static func loading_active(button: BaseButton) -> bool:
	return bool(_get_state(button).get("loading", false))


static func _on_mouse_entered(button: BaseButton) -> void:
	var state := _get_state(button)
	if state.is_empty() or bool(state.get("loading", false)) or button.disabled:
		return
	state["hovered"] = true
	_store_state(button, state)
	_animate_state(button, HOVER_SECONDS)


static func _on_mouse_exited(button: BaseButton) -> void:
	var state := _get_state(button)
	if state.is_empty() or bool(state.get("loading", false)):
		return
	state["hovered"] = false
	state["pressed"] = false
	_store_state(button, state)
	_animate_state(button, REST_SECONDS)


static func _on_button_down(button: BaseButton) -> void:
	var state := _get_state(button)
	if state.is_empty() or bool(state.get("loading", false)) or button.disabled:
		return
	state["pressed"] = true
	_store_state(button, state)
	_animate_state(button, PRESS_SECONDS)


static func _on_button_up(button: BaseButton) -> void:
	var state := _get_state(button)
	if state.is_empty() or bool(state.get("loading", false)) or button.disabled:
		return
	state["pressed"] = false
	_store_state(button, state)
	if bool(state.get("reduced_motion", false)) or not button.is_inside_tree():
		_apply_state_immediately(button)
		return
	_stop_motion_tween(button, state)
	_update_pivot(button)
	var target_scale := (
		HOVER_SCALE
		if bool(state.get("hovered", false))
		else Vector2.ONE
	)
	var target_modulate := (
		HOVER_MODULATE
		if bool(state.get("hovered", false)) or bool(state.get("focused", false))
		else REST_MODULATE
	)
	var tween := button.create_tween()
	state["motion_tween"] = tween
	_store_state(button, state)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", RELEASE_SCALE, RELEASE_SECONDS)
	tween.parallel().tween_property(
		button,
		"modulate",
		target_modulate,
		RELEASE_SECONDS,
	)
	tween.tween_property(button, "scale", target_scale, REST_SECONDS)


static func _on_focus_entered(button: BaseButton) -> void:
	var state := _get_state(button)
	if state.is_empty() or bool(state.get("loading", false)) or button.disabled:
		return
	state["focused"] = true
	_store_state(button, state)
	_animate_state(button, HOVER_SECONDS)


static func _on_focus_exited(button: BaseButton) -> void:
	var state := _get_state(button)
	if state.is_empty() or bool(state.get("loading", false)):
		return
	state["focused"] = false
	state["pressed"] = false
	_store_state(button, state)
	_animate_state(button, REST_SECONDS)


static func _animate_state(button: BaseButton, duration: float) -> void:
	var state := _get_state(button)
	if state.is_empty():
		return
	var target_scale := Vector2.ONE
	var target_modulate := REST_MODULATE
	if bool(state.get("pressed", false)):
		target_scale = PRESS_SCALE
		target_modulate = PRESS_MODULATE
	elif bool(state.get("hovered", false)) or bool(state.get("focused", false)):
		target_scale = (
			HOVER_SCALE if bool(state.get("hovered", false)) else Vector2.ONE
		)
		target_modulate = HOVER_MODULATE
	if bool(state.get("reduced_motion", false)):
		button.scale = Vector2.ONE
		button.modulate = target_modulate
		return
	if not button.is_inside_tree():
		button.scale = target_scale
		button.modulate = target_modulate
		return
	_stop_motion_tween(button, state)
	_update_pivot(button)
	var tween := button.create_tween()
	state["motion_tween"] = tween
	_store_state(button, state)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, duration)
	tween.tween_property(button, "modulate", target_modulate, duration)


static func _apply_state_immediately(button: BaseButton) -> void:
	var state := _get_state(button)
	if bool(state.get("reduced_motion", false)):
		button.scale = Vector2.ONE
		if bool(state.get("pressed", false)):
			button.modulate = PRESS_MODULATE
		elif bool(state.get("hovered", false)) or bool(state.get("focused", false)):
			button.modulate = HOVER_MODULATE
		else:
			button.modulate = REST_MODULATE
		return
	if bool(state.get("pressed", false)):
		button.scale = PRESS_SCALE
		button.modulate = PRESS_MODULATE
	elif bool(state.get("hovered", false)) or bool(state.get("focused", false)):
		button.scale = (
			HOVER_SCALE if bool(state.get("hovered", false)) else Vector2.ONE
		)
		button.modulate = HOVER_MODULATE
	else:
		button.scale = Vector2.ONE
		button.modulate = REST_MODULATE


static func _set_loading(button: BaseButton, active: bool) -> void:
	var state := _get_state(button)
	if state.is_empty() or bool(state.get("loading", false)) == active:
		return
	state["loading"] = active
	state["hovered"] = false
	state["pressed"] = false
	state["focused"] = false
	_stop_motion_tween(button, state)
	_stop_loading_tween(button, state)
	_store_state(button, state)
	_update_pivot(button)
	button.scale = Vector2.ONE
	button.modulate = REST_MODULATE
	if not active or bool(state.get("reduced_motion", false)) or not button.is_inside_tree():
		return
	var tween := button.create_tween()
	state["loading_tween"] = tween
	_store_state(button, state)
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		button,
		"modulate",
		LOADING_MODULATE,
		LOADING_HALF_CYCLE_SECONDS,
	)
	tween.parallel().tween_property(
		button,
		"scale",
		HOVER_SCALE,
		LOADING_HALF_CYCLE_SECONDS,
	)
	tween.tween_property(
		button,
		"modulate",
		REST_MODULATE,
		LOADING_HALF_CYCLE_SECONDS,
	)
	tween.parallel().tween_property(
		button,
		"scale",
		Vector2.ONE,
		LOADING_HALF_CYCLE_SECONDS,
	)


static func _update_pivot(button: BaseButton) -> void:
	if button != null:
		button.pivot_offset = button.size * 0.5


static func _stop_motion_tween(button: BaseButton, state: Dictionary) -> void:
	var tween: Variant = state.get("motion_tween", null)
	if tween is Tween:
		(tween as Tween).kill()
	state["motion_tween"] = null
	_store_state(button, state)


static func _stop_loading_tween(button: BaseButton, state: Dictionary) -> void:
	var tween: Variant = state.get("loading_tween", null)
	if tween is Tween:
		(tween as Tween).kill()
	state["loading_tween"] = null
	_store_state(button, state)


static func _on_tree_exiting(button: BaseButton) -> void:
	var state := _get_state(button)
	if state.is_empty():
		return
	_stop_motion_tween(button, state)
	_stop_loading_tween(button, state)
	button.remove_meta(META_KEY)


static func _get_state(button: BaseButton) -> Dictionary:
	if button == null:
		return {}
	var state: Variant = button.get_meta(META_KEY, {})
	return state if state is Dictionary else {}


static func _store_state(button: BaseButton, state: Dictionary) -> void:
	if button != null:
		button.set_meta(META_KEY, state)


static func _prefers_reduced_motion() -> bool:
	var environment := OS.get_environment(
		"AI_TOWN_REDUCED_MOTION"
	).strip_edges().to_lower()
	return (
		bool(ProjectSettings.get_setting(
			"accessibility/reduced_motion",
			false,
		))
		or environment in ["1", "true", "yes", "on"]
	)
