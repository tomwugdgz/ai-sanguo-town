class_name PauseMenuNavigationHost
extends Control


signal intent_requested(intent: StringName, payload: Dictionary)
signal action_blocked(intent: StringName, reason: String)
signal route_changed(route: StringName)

const AUDIO_DISPLAY_SETTINGS_SCENE := preload(
	"res://ui/settings/AudioDisplaySettingsScreen.tscn"
)
const LOAD_GAME_SCENE := preload(
	"res://ui/startup/StartupLoadGameScreen.tscn"
)
const ROUTE_PAUSE := &"pause_menu"
const ROUTE_AUDIO_DISPLAY := &"audio_display_settings"
const ROUTE_LOAD_GAME := &"load_game"
const OPEN_AUDIO_DISPLAY_INTENT := &"pause_menu.open_audio_video"
const OPEN_LOAD_GAME_INTENT := &"pause_menu.open_load_game"
const BACK_AUDIO_DISPLAY_INTENT := &"audio_display_settings.back"
const BACK_LOAD_GAME_INTENT := &"startup.close_load_game"

var _adapter: Node
var _pause_screen: Control
var _settings_screen: Control
var _retiring_settings_screen: Control
var _load_game_screen: Control
var _retiring_load_game_screen: Control
var _route := ROUTE_PAUSE
var _route_generation := 0
var _focus_return_path := NodePath()
var _settings_intent_callback := Callable()
var _settings_blocked_callback := Callable()
var _load_game_intent_callback := Callable()
var _load_game_blocked_callback := Callable()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_root_to_viewport()
	get_viewport().size_changed.connect(_fit_root_to_viewport)
	_pause_screen = get_node_or_null("PauseMenuScreen") as Control
	if _pause_screen == null:
		push_error("暂停导航宿主缺少 PauseMenuScreen。")
		return
	_connect_pause_screen()
	_apply_adapter(_pause_screen)
	_sync_pause_input_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		_sync_pause_input_state()


func _fit_root_to_viewport() -> void:
	# GameFlowHost mounts this Control below TownRuntime (Node2D), where
	# full-rect anchors do not receive a Control parent size.
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _exit_tree() -> void:
	_route_generation += 1
	_disconnect_settings_screen()
	_disconnect_load_game_screen()
	_disconnect_pause_screen()


func bind_town_ui_adapter(adapter: Node) -> void:
	_adapter = adapter if is_instance_valid(adapter) else null
	if not is_node_ready():
		return
	_apply_adapter(_pause_screen)
	_apply_adapter(_settings_screen)


func unbind_town_ui_adapter() -> void:
	bind_town_ui_adapter(null)


func pause_screen() -> Control:
	return _pause_screen


func current_settings_screen() -> Control:
	return _settings_screen if is_instance_valid(_settings_screen) else null


func current_load_game_screen() -> Control:
	return _load_game_screen if is_instance_valid(_load_game_screen) else null


func current_route() -> StringName:
	return _route


func request_back() -> bool:
	match _route:
		ROUTE_AUDIO_DISPLAY:
			if (
				is_instance_valid(_settings_screen)
				and _settings_screen.has_method("request_back")
			):
				return bool(_settings_screen.call("request_back"))
			return false
		ROUTE_LOAD_GAME:
			if (
				is_instance_valid(_load_game_screen)
				and _load_game_screen.has_method("request_back")
			):
				return bool(_load_game_screen.call("request_back"))
			return false
	return false


func present_host_result(intent: String, result: Dictionary) -> void:
	if (
		is_instance_valid(_pause_screen)
		and _pause_screen.has_method("present_host_result")
	):
		_pause_screen.call(
			"present_host_result",
			intent,
			result.duplicate(true)
		)


func open_audio_display_settings() -> bool:
	if (
		_route == ROUTE_AUDIO_DISPLAY
		and is_instance_valid(_settings_screen)
		and _settings_screen.is_inside_tree()
	):
		return false
	if (
		is_instance_valid(_retiring_settings_screen)
		and _retiring_settings_screen.is_inside_tree()
	):
		return false
	if _pause_screen == null or not is_instance_valid(_pause_screen):
		return false

	_capture_pause_focus()
	_route_generation += 1
	var generation := _route_generation
	_pause_screen.set_process_unhandled_input(false)
	_pause_screen.hide()

	var settings := AUDIO_DISPLAY_SETTINGS_SCENE.instantiate() as Control
	if settings == null:
		_restore_pause_after_open_failure(generation)
		return false
	settings.name = "AudioDisplaySettingsRoute"
	settings.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_screen = settings
	_route = ROUTE_AUDIO_DISPLAY
	_settings_intent_callback = Callable(
		self,
		"_on_settings_intent_requested"
	).bind(generation)
	_settings_blocked_callback = Callable(
		self,
		"_on_settings_action_blocked"
	).bind(generation)
	settings.connect("intent_requested", _settings_intent_callback)
	settings.connect("action_blocked", _settings_blocked_callback)
	_apply_adapter(settings)
	add_child(settings)
	route_changed.emit(_route)
	return true


func close_audio_display_settings() -> bool:
	if _route != ROUTE_AUDIO_DISPLAY:
		return false
	_route_generation += 1
	var restore_generation := _route_generation
	var settings := _settings_screen
	_settings_screen = null
	_disconnect_settings_instance(settings)
	if is_instance_valid(settings):
		settings.set_process_unhandled_input(false)
		settings.hide()
		if settings.has_method("unbind_town_ui_adapter"):
			settings.call("unbind_town_ui_adapter")
		_retiring_settings_screen = settings
		settings.tree_exited.connect(
			_on_retiring_settings_tree_exited.bind(
				settings.get_instance_id()
			),
			CONNECT_ONE_SHOT
		)
		settings.queue_free()

	_route = ROUTE_PAUSE
	if is_instance_valid(_pause_screen):
		_pause_screen.show()
	_sync_pause_input_state()
	route_changed.emit(_route)
	call_deferred(
		"_restore_pause_focus",
		_focus_return_path,
		restore_generation
	)
	return true


func open_load_game(view_model: Dictionary) -> bool:
	if (
		_route == ROUTE_LOAD_GAME
		and is_instance_valid(_load_game_screen)
		and _load_game_screen.is_inside_tree()
	):
		return false
	if (
		is_instance_valid(_retiring_load_game_screen)
		and _retiring_load_game_screen.is_inside_tree()
	):
		return false
	if _route != ROUTE_PAUSE or not is_instance_valid(_pause_screen):
		return false

	var page := LOAD_GAME_SCENE.instantiate() as Control
	if page == null or not bool(page.call("apply_view_model", view_model)):
		if page != null:
			page.free()
		return false
	_capture_pause_focus()
	_route_generation += 1
	var generation := _route_generation
	_pause_screen.set_process_unhandled_input(false)
	_pause_screen.hide()
	page.name = "InSessionLoadGameRoute"
	page.process_mode = Node.PROCESS_MODE_ALWAYS
	_load_game_screen = page
	_route = ROUTE_LOAD_GAME
	_load_game_intent_callback = Callable(
		self,
		"_on_load_game_intent_requested"
	).bind(generation)
	_load_game_blocked_callback = Callable(
		self,
		"_on_load_game_action_blocked"
	).bind(generation)
	page.connect("intent_requested", _load_game_intent_callback)
	page.connect("action_blocked", _load_game_blocked_callback)
	add_child(page)
	route_changed.emit(_route)
	return true


func close_load_game() -> bool:
	if _route != ROUTE_LOAD_GAME:
		return false
	_route_generation += 1
	var restore_generation := _route_generation
	var page := _load_game_screen
	_load_game_screen = null
	_disconnect_load_game_instance(page)
	if is_instance_valid(page):
		page.call("deactivate_modal_ownership")
		_retiring_load_game_screen = page
		page.tree_exited.connect(
			_on_retiring_load_game_tree_exited.bind(page.get_instance_id()),
			CONNECT_ONE_SHOT,
		)
		page.queue_free()
	_route = ROUTE_PAUSE
	if is_instance_valid(_pause_screen):
		_pause_screen.show()
	_sync_pause_input_state()
	route_changed.emit(_route)
	call_deferred(
		"_restore_pause_focus",
		_focus_return_path,
		restore_generation,
	)
	return true


func debug_snapshot() -> Dictionary:
	var settings_snapshot := {}
	if (
		is_instance_valid(_settings_screen)
		and _settings_screen.has_method("runtime_gate_snapshot")
	):
		settings_snapshot = _settings_screen.call(
			"runtime_gate_snapshot"
		) as Dictionary
	var focus_owner := get_viewport().gui_get_focus_owner()
	return {
		"route": str(_route),
		"routeGeneration": _route_generation,
		"pauseVisible": (
			is_instance_valid(_pause_screen)
			and _pause_screen.visible
		),
		"pauseUnhandledInput": (
			is_instance_valid(_pause_screen)
			and _pause_screen.is_processing_unhandled_input()
		),
		"settingsInstanceCount": _settings_instance_count(),
		"loadGameInstanceCount": _load_game_instance_count(),
		"loadGameVisible": (
			is_instance_valid(_load_game_screen)
			and _load_game_screen.visible
		),
		"settingsSourceMode": str(
			settings_snapshot.get("sourceMode", "")
		),
		"settingsSource": str(
			settings_snapshot.get("source", "")
		),
		"settingsCapabilityMode": str(
			settings_snapshot.get("capabilityMode", "")
		),
		"settingsFormalReady": bool(
			settings_snapshot.get("formalReady", false)
		),
		"focusReturnPath": str(_focus_return_path),
		"focusOwner": (
			str(focus_owner.name)
			if is_instance_valid(focus_owner)
			else ""
		),
		"treePaused": get_tree().paused,
		"adapterBound": is_instance_valid(_adapter),
	}


func _connect_pause_screen() -> void:
	var intent_callback := Callable(
		self,
		"_on_pause_intent_requested"
	)
	if not _pause_screen.is_connected(
		"intent_requested",
		intent_callback
	):
		_pause_screen.connect(
			"intent_requested",
			intent_callback
		)
	var blocked_callback := Callable(
		self,
		"_on_pause_action_blocked"
	)
	if not _pause_screen.is_connected(
		"action_blocked",
		blocked_callback
	):
		_pause_screen.connect(
			"action_blocked",
			blocked_callback
		)


func _disconnect_pause_screen() -> void:
	if not is_instance_valid(_pause_screen):
		return
	var intent_callback := Callable(
		self,
		"_on_pause_intent_requested"
	)
	if _pause_screen.is_connected(
		"intent_requested",
		intent_callback
	):
		_pause_screen.disconnect(
			"intent_requested",
			intent_callback
		)
	var blocked_callback := Callable(
		self,
		"_on_pause_action_blocked"
	)
	if _pause_screen.is_connected(
		"action_blocked",
		blocked_callback
	):
		_pause_screen.disconnect(
			"action_blocked",
			blocked_callback
		)


func _on_pause_intent_requested(
	intent_value: Variant,
	payload: Dictionary
) -> void:
	var intent := StringName(intent_value)
	if intent == OPEN_AUDIO_DISPLAY_INTENT:
		open_audio_display_settings()
		return
	if intent == OPEN_LOAD_GAME_INTENT:
		intent_requested.emit(intent, payload.duplicate(true))
		return
	intent_requested.emit(intent, payload.duplicate(true))


func _on_pause_action_blocked(
	intent_value: Variant,
	reason: String
) -> void:
	action_blocked.emit(StringName(intent_value), reason)


func _on_settings_intent_requested(
	intent_value: Variant,
	payload: Dictionary,
	generation: int
) -> void:
	if not _is_current_settings_callback(generation):
		return
	var intent := StringName(intent_value)
	if intent == BACK_AUDIO_DISPLAY_INTENT:
		close_audio_display_settings()
		return
	intent_requested.emit(intent, payload.duplicate(true))


func _on_settings_action_blocked(
	intent_value: Variant,
	reason: String,
	generation: int
) -> void:
	if not _is_current_settings_callback(generation):
		return
	action_blocked.emit(StringName(intent_value), reason)


func _on_load_game_intent_requested(
	intent_value: Variant,
	payload: Dictionary,
	generation: int,
) -> void:
	if not _is_current_load_game_callback(generation):
		return
	var intent := StringName(intent_value)
	if intent == BACK_LOAD_GAME_INTENT:
		close_load_game()
		return
	intent_requested.emit(intent, payload.duplicate(true))


func _on_load_game_action_blocked(
	intent_value: Variant,
	reason: String,
	generation: int,
) -> void:
	if not _is_current_load_game_callback(generation):
		return
	action_blocked.emit(StringName(intent_value), reason)


func _is_current_settings_callback(generation: int) -> bool:
	return (
		generation == _route_generation
		and _route == ROUTE_AUDIO_DISPLAY
		and is_instance_valid(_settings_screen)
		and _settings_screen.is_inside_tree()
	)


func _is_current_load_game_callback(generation: int) -> bool:
	return (
		generation == _route_generation
		and _route == ROUTE_LOAD_GAME
		and is_instance_valid(_load_game_screen)
		and _load_game_screen.is_inside_tree()
	)


func _capture_pause_focus() -> void:
	_focus_return_path = NodePath()
	var focus_owner := get_viewport().gui_get_focus_owner()
	if (
		not is_instance_valid(focus_owner)
		or not _pause_screen.is_ancestor_of(focus_owner)
	):
		return
	_focus_return_path = _pause_screen.get_path_to(focus_owner)
	(focus_owner as Control).release_focus()


func _restore_pause_focus(
	focus_path: NodePath,
	generation: int
) -> void:
	if (
		generation != _route_generation
		or _route != ROUTE_PAUSE
		or not is_instance_valid(_pause_screen)
		or not _pause_screen.visible
	):
		return
	var target := _focus_target_from_path(focus_path)
	if target == null:
		target = _default_pause_focus_target()
	if target != null:
		target.grab_focus()


func _focus_target_from_path(path: NodePath) -> Control:
	if path.is_empty() or not _pause_screen.has_node(path):
		return null
	var target := _pause_screen.get_node(path) as Control
	if not _is_focusable(target):
		return null
	return target


func _default_pause_focus_target() -> Control:
	for node_name: String in [
		"DesktopEntry_return_game",
		"CompactEntry_return_game",
	]:
		var target := _pause_screen.find_child(
			node_name,
			true,
			false
		) as Control
		if _is_focusable(target):
			return target
	return null


func _is_focusable(control: Control) -> bool:
	if (
		control == null
		or not control.is_visible_in_tree()
		or control.focus_mode == Control.FOCUS_NONE
	):
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	return true


func _apply_adapter(screen: Control) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	if is_instance_valid(_adapter):
		if screen.has_method("bind_town_ui_adapter"):
			screen.call("bind_town_ui_adapter", _adapter)
	elif screen.has_method("unbind_town_ui_adapter"):
		screen.call("unbind_town_ui_adapter")


func _disconnect_settings_screen() -> void:
	var settings := _settings_screen
	_settings_screen = null
	_disconnect_settings_instance(settings)


func _disconnect_load_game_screen() -> void:
	var page := _load_game_screen
	_load_game_screen = null
	_disconnect_load_game_instance(page)


func _disconnect_load_game_instance(page: Control) -> void:
	if not is_instance_valid(page):
		_load_game_intent_callback = Callable()
		_load_game_blocked_callback = Callable()
		return
	if (
		_load_game_intent_callback.is_valid()
		and page.is_connected("intent_requested", _load_game_intent_callback)
	):
		page.disconnect("intent_requested", _load_game_intent_callback)
	if (
		_load_game_blocked_callback.is_valid()
		and page.is_connected("action_blocked", _load_game_blocked_callback)
	):
		page.disconnect("action_blocked", _load_game_blocked_callback)
	_load_game_intent_callback = Callable()
	_load_game_blocked_callback = Callable()


func _disconnect_settings_instance(settings: Control) -> void:
	if not is_instance_valid(settings):
		_settings_intent_callback = Callable()
		_settings_blocked_callback = Callable()
		return
	if (
		_settings_intent_callback.is_valid()
		and settings.is_connected(
			"intent_requested",
			_settings_intent_callback
		)
	):
		settings.disconnect(
			"intent_requested",
			_settings_intent_callback
		)
	if (
		_settings_blocked_callback.is_valid()
		and settings.is_connected(
			"action_blocked",
			_settings_blocked_callback
		)
	):
		settings.disconnect(
			"action_blocked",
			_settings_blocked_callback
		)
	_settings_intent_callback = Callable()
	_settings_blocked_callback = Callable()


func _restore_pause_after_open_failure(generation: int) -> void:
	if generation != _route_generation:
		return
	_route = ROUTE_PAUSE
	_pause_screen.show()
	_sync_pause_input_state()
	call_deferred(
		"_restore_pause_focus",
		_focus_return_path,
		generation
	)


func _on_retiring_settings_tree_exited(instance_id: int) -> void:
	if (
		is_instance_valid(_retiring_settings_screen)
		and _retiring_settings_screen.get_instance_id() == instance_id
	):
		_retiring_settings_screen = null


func _on_retiring_load_game_tree_exited(instance_id: int) -> void:
	if (
		is_instance_valid(_retiring_load_game_screen)
		and _retiring_load_game_screen.get_instance_id() == instance_id
	):
		_retiring_load_game_screen = null


func _settings_instance_count() -> int:
	var count := 0
	for child: Node in get_children():
		if (
			child == _settings_screen
			or child == _retiring_settings_screen
		):
			count += 1
	return count


func _load_game_instance_count() -> int:
	var count := 0
	for child: Node in get_children():
		if child == _load_game_screen or child == _retiring_load_game_screen:
			count += 1
	return count


func _sync_pause_input_state() -> void:
	if not is_instance_valid(_pause_screen):
		return
	_pause_screen.set_process_unhandled_input(
		is_visible_in_tree()
		and _route == ROUTE_PAUSE
		and _pause_screen.visible
	)
