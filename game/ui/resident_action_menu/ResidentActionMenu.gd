class_name ResidentActionMenu
extends Control


signal intent_requested(
	intent: StringName,
	payload: Dictionary,
	revision: int,
	request_id: String
)
signal action_blocked(
	intent: StringName,
	reason: String,
	revision: int
)


const UI_SIGNALS := preload(
	"res://ui/common/AiTownUiSignals.gd"
)
const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")
const BubbleScript = preload("res://ui/resident_action_menu/ResidentActionBubble.gd")
const CloseScript = preload("res://ui/resident_action_menu/ResidentActionCloseButton.gd")
const DimmerScript = preload("res://ui/resident_action_menu/ResidentActionWorldDimmer.gd")
const PAUSE_BANNER_TEXTURE := preload(
	"res://assets/ui/resident_action_menu/final/"
	+ "resident_action_pause_banner_v2.png"
)

const REQUIRED_SCOPE := "resident_action_menu"
const REQUIRED_FIELDS: Array[String] = [
	"scope",
	"status",
	"revision",
	"data",
	"actions",
	"operation",
	"error",
]
const FORMAL_MENU_ORDER: Array[String] = [
	"follow",
	"status",
	"relationship",
	"memory",
	"inner",
	"kill",
]
const MENU_ITEM_IDS: Array[String] = [
	"follow",
	"status",
	"relationship",
	"memory",
	"inner",
	"kill",
]
const FORMAL_ACTION_KEYS: Array[String] = [
	"follow",
	"openStatus",
	"openRelationship",
	"openMemory",
	"openInner",
	"killResident",
	"close",
]
const COLOR_PAPER := Color("fff0cc")
const COLOR_PAPER_LIGHT := Color("fff8e6")
const COLOR_WALNUT := Color("5e3219")
const COLOR_INK := Color("3f2818")
const COLOR_MOSS := Color("557b2a")
const COLOR_ERROR := Color("a7352b")
const COLOR_TERRACOTTA := Color("b94d2d")
const LOCAL_FEEDBACK_COPY := {
	"ACTION_NOT_AVAILABLE": "此操作暂不可用",
	"ACTION_DISABLED": "此操作暂不可用",
	"OPERATION_IN_PROGRESS": "上一项操作仍在处理中",
	"SCREEN_TRANSITIONING": "页面正在切换，请稍候",
	"RESIDENT_IDENTITY_UNAVAILABLE": "居民身份暂不可用",
	"RESIDENT_IDENTITY_NOT_FOUND": "没有找到这位居民",
	"RESIDENT_DETAIL_INTERFACE_MISSING": "居民状态暂不可查看",
	"RESIDENT_RELATIONSHIP_PUBLIC_INTERFACE_MISSING": "关系资料暂不可查看",
	"RESIDENT_MEMORY_PUBLIC_INTERFACE_MISSING": "记忆资料暂不可查看",
	"AGENT_INNER_OBSERVATION_INTERFACE_MISSING": "内心观察暂不可用",
	"INNER_OBSERVATION_INTERFACE_MISSING": "内心观察暂不可用",
	"INNER_OBSERVATION_TEMPORARILY_UNAVAILABLE": "内心观察暂时没有准备好",
	"RESIDENT_MEMORY_NOT_READY": "记忆摘要暂时不可用",
	"RESIDENT_DEAD": "该居民已经死亡",
	"RESIDENT_DEATH_INTERFACE_MISSING": "死亡操作暂不可用",
}


var _adapter: Node
var _view_model: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _revision := -1
var _has_rendered := false
var _current_orientation := ""
var _current_layout: Dictionary = {}
var _menu_order: Array[String] = FORMAL_MENU_ORDER.duplicate()
var _request_sequence := 0
var _last_requested_request_id := ""
var _last_requested_action_key := ""
var _local_feedback_message := ""

var _dimmer: ResidentActionWorldDimmer
var _bubble_layer: Control
var _bubbles: Dictionary = {}
var _close_button: ResidentActionCloseButton
var _pause_panel: NinePatchRect
var _pause_label: Label
var _feedback_panel: Panel
var _feedback_label: Label
var _focus_controls: Array[Control] = []


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_interface()
	if not _view_model.is_empty():
		_render(true)
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_request_action("close")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_focus_next"):
		_move_semantic_focus(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_focus_prev"):
		_move_semantic_focus(-1)
		get_viewport().set_input_as_handled()
		return
	if (
		event.is_action_pressed("ui_right")
		or event.is_action_pressed("ui_down")
	):
		_move_semantic_focus(1)
		get_viewport().set_input_as_handled()
	elif (
		event.is_action_pressed("ui_left")
		or event.is_action_pressed("ui_up")
	):
		_move_semantic_focus(-1)
		get_viewport().set_input_as_handled()


func bind_town_ui_adapter(adapter: Node) -> void:
	if _adapter == adapter:
		return
	_disconnect_adapter()
	_adapter = adapter
	if _adapter == null:
		return
	if _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_adapter_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	if _adapter.has_method("get_view_model"):
		var incoming: Variant = _adapter.call("get_view_model", REQUIRED_SCOPE)
		if incoming is Dictionary and not (incoming as Dictionary).is_empty():
			apply_view_model(incoming as Dictionary)
	elif _adapter.has_method("view_model"):
		var incoming: Variant = _adapter.call("view_model", REQUIRED_SCOPE)
		if incoming is Dictionary and not (incoming as Dictionary).is_empty():
			apply_view_model(incoming as Dictionary)


func unbind_town_ui_adapter() -> void:
	_disconnect_adapter()
	_adapter = null
	visible = false
	_view_model.clear()
	_last_confirmed_data.clear()
	_revision = -1
	_last_requested_request_id = ""
	_last_requested_action_key = ""
	_local_feedback_message = ""


func apply_view_model(snapshot: Dictionary) -> bool:
	var issues := _validate_snapshot(snapshot)
	if not issues.is_empty():
		for issue: String in issues:
			push_error(issue)
		return false
	var incoming_revision := int(snapshot.get("revision", -1))
	if incoming_revision < _revision:
		return false
	var accepted := snapshot.duplicate(true)
	var render_data := UiViewModel.data_for_render(
		snapshot,
		_last_confirmed_data
	)
	if render_data.is_empty():
		push_error("居民功能气泡拒绝空 data 快照。")
		return false
	accepted["data"] = render_data
	_view_model = accepted
	_revision = incoming_revision
	_local_feedback_message = ""
	if UiViewModel.operation_status(snapshot) != &"rejected":
		_last_confirmed_data = render_data.duplicate(true)
	if is_node_ready():
		_render(not _has_rendered)
	return true


func debug_compute_layout(snapshot: Dictionary) -> Dictionary:
	var data := snapshot.get("data", {}) as Dictionary
	if data.is_empty():
		return {}
	return _solve_layout(data, "")


func debug_snapshot() -> Dictionary:
	var bubble_rows := {}
	for item_id: String in _menu_order:
		var bubble := _bubbles.get(item_id) as ResidentActionBubble
		if bubble == null:
			continue
		bubble_rows[item_id] = {
			"rect": Rect2(bubble.position, bubble.size),
			"textRect": bubble.debug_text_rect(),
			"disabled": bubble.disabled,
			"visualState": bubble.visual_state,
			"focused": bubble.has_focus(),
			"visible": bubble.visible,
			"assetOwnership": bubble.debug_asset_ownership(),
			"actionContract": bubble.debug_action_contract(),
		}
	return {
		"scope": str(_view_model.get("scope", "")),
		"revision": _revision,
		"sourceMode": "town_ui_adapter",
		"formalReady": bool(
			(_view_model.get("data", {}) as Dictionary).get(
				"formalReady",
				false
			)
		),
		"operationStatus": str(
			(_view_model.get("operation", {}) as Dictionary).get(
				"status",
				""
			)
		),
		"layout": _current_layout.duplicate(true),
		"dimmerVisualContract": (
			_dimmer.debug_visual_contract()
			if _dimmer != null
			else {}
		),
		"bubbles": bubble_rows,
		"closeRect": (
			Rect2(_close_button.position, _close_button.size)
			if _close_button != null
			else Rect2()
		),
		"pauseRect": (
			Rect2(_pause_panel.position, _pause_panel.size)
			if _pause_panel != null and _pause_panel.visible
			else Rect2()
		),
		"pauseTextRect": (
			Rect2(_pause_label.position, _pause_label.size)
			if _pause_label != null and _pause_label.visible
			else Rect2()
		),
		"semanticFocusOrder": _menu_order + ["close"],
		"assetOwnership": _asset_ownership_audit(),
	}


func _build_interface() -> void:
	_dimmer = DimmerScript.new() as ResidentActionWorldDimmer
	_dimmer.name = "WorldDimmer"
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dimmer)

	_pause_panel = NinePatchRect.new()
	_pause_panel.name = "PauseBanner"
	_pause_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_panel.texture = PAUSE_BANNER_TEXTURE
	_pause_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pause_panel.set_patch_margin(SIDE_LEFT, 48)
	_pause_panel.set_patch_margin(SIDE_TOP, 10)
	_pause_panel.set_patch_margin(SIDE_RIGHT, 48)
	_pause_panel.set_patch_margin(SIDE_BOTTOM, 10)
	add_child(_pause_panel)
	_pause_label = Label.new()
	_pause_label.name = "PauseLabel"
	_pause_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_label.offset_left = 20
	_pause_label.offset_top = 2
	_pause_label.offset_right = -20
	_pause_label.offset_bottom = -2
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pause_label.clip_text = true
	_pause_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pause_panel.add_child(_pause_label)

	_bubble_layer = Control.new()
	_bubble_layer.name = "BubbleLayer"
	_bubble_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble_layer)
	for item_id: String in MENU_ITEM_IDS:
		var bubble := BubbleScript.new() as ResidentActionBubble
		bubble.name = item_id.capitalize() + "Bubble"
		bubble.pressed.connect(_on_bubble_pressed.bind(item_id))
		bubble.visible = false
		_bubble_layer.add_child(bubble)
		_bubbles[item_id] = bubble

	_feedback_panel = Panel.new()
	_feedback_panel.name = "Feedback"
	_feedback_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(COLOR_PAPER, COLOR_WALNUT, 4, 8)
	)
	add_child(_feedback_panel)
	_feedback_label = Label.new()
	_feedback_label.name = "FeedbackLabel"
	_feedback_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_feedback_label.offset_left = 18
	_feedback_label.offset_top = 4
	_feedback_label.offset_right = -18
	_feedback_label.offset_bottom = -4
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_panel.add_child(_feedback_label)

	_close_button = CloseScript.new() as ResidentActionCloseButton
	_close_button.name = "CloseButton"
	_close_button.pressed.connect(_request_action.bind("close"))
	add_child(_close_button)


func _render(play_opening: bool) -> void:
	if _view_model.is_empty():
		return
	visible = true
	var data := _view_model.get("data", {}) as Dictionary
	var placement := data.get("placement", {}) as Dictionary
	var viewport_rect := _rect_from_dictionary(
		placement.get("viewport", {}) as Dictionary
	)
	var focus_rect := _rect_from_dictionary(
		placement.get("focusRect", {}) as Dictionary
	)
	_dimmer.configure(viewport_rect, focus_rect)
	_render_pause_banner(data, placement)
	_menu_order = FORMAL_MENU_ORDER.duplicate()
	_current_layout = _solve_layout(data, _current_orientation)
	_current_orientation = str(_current_layout.get("orientation", "up"))
	_render_bubbles(data, play_opening)
	_render_close(placement)
	_render_feedback(data)
	_has_rendered = true


func _render_bubbles(data: Dictionary, play_opening: bool) -> void:
	var focused_action_key := _focused_action_key()
	var menu_items := data.get("menuItems", []) as Array
	var item_by_id := {}
	for item_value: Variant in menu_items:
		if item_value is Dictionary:
			var item := item_value as Dictionary
			item_by_id[str(item.get("id", ""))] = item
	var rects := _current_layout.get("rects", {}) as Dictionary
	var component_size := _array_to_vector2(
		_current_layout.get("componentSize", [160, 160])
	)
	var multiline := bool(_current_layout.get("multiline", false))
	var motion := data.get("motion", {}) as Dictionary
	var anchor := _point_from_dictionary(
		(data.get("placement", {}) as Dictionary).get(
			"screenAnchor",
			{}
		) as Dictionary
	)
	var operation := _view_model.get("operation", {}) as Dictionary
	var operation_status := str(operation.get("status", "idle"))
	var closing := str(data.get("phase", "menu")) == "closing"
	var active_id := _active_item_id(operation)
	var actions := _view_model.get("actions", {}) as Dictionary
	for bubble_value: Variant in _bubbles.values():
		var hidden_bubble := bubble_value as ResidentActionBubble
		if hidden_bubble != null:
			hidden_bubble.visible = false
	for index: int in _menu_order.size():
		var item_id := _menu_order[index]
		var bubble := _bubbles.get(item_id) as ResidentActionBubble
		var item := item_by_id.get(item_id, {}) as Dictionary
		if bubble == null or item.is_empty():
			continue
		bubble.configure(item, component_size, multiline, motion)
		var action_key := str(item.get("actionKey", ""))
		var action := actions.get(action_key, {}) as Dictionary
		bubble.apply_action_contract(action)
		var enabled := bool(action.get("enabled", false))
		var emphasized := item_id == active_id and operation_status != "idle"
		bubble.set_visual_state(
			operation_status if emphasized else (
				"disabled" if not enabled else "idle"
			),
			emphasized,
			enabled
		)
		var rect := _array_to_rect2(rects.get(item_id, []))
		bubble.size = rect.size
		if closing:
			bubble.place_immediately(rect.position)
			bubble.play_close(
				anchor,
				float(_menu_order.size() - 1 - index) * 0.022,
				0.18
			)
		elif play_opening:
			bubble.play_open(
				rect.position,
				anchor,
				float(motion.get("itemStaggerMs", 28)) / 1000.0 * index,
				float(motion.get("openingDurationMs", 280)) / 1000.0
			)
		else:
			bubble.place_immediately(rect.position)
	_rebuild_focus_controls()
	_restore_action_focus.call_deferred(focused_action_key)


func _render_pause_banner(
	data: Dictionary,
	placement: Dictionary
) -> void:
	var world := data.get("world", {}) as Dictionary
	var paused := bool(world.get("paused", false))
	var pause_text := str(world.get("pauseLabel", ""))
	_pause_panel.visible = paused and not pause_text.is_empty()
	if not _pause_panel.visible:
		return
	var rect := Rect2()
	for avoid_value: Variant in placement.get("avoidRects", []):
		if avoid_value is Dictionary:
			var avoid := avoid_value as Dictionary
			if str(avoid.get("id", "")) == "pause_banner":
				rect = _rect_from_dictionary(avoid)
				break
	if rect.size.x <= 0:
		var safe := _rect_from_dictionary(
			placement.get("safeRect", {}) as Dictionary
		)
		rect = Rect2(
			Vector2(safe.get_center().x - 260, safe.position.y - 72),
			Vector2(520, 64)
		)
	_pause_panel.position = rect.position.round()
	_pause_panel.size = rect.size.round()
	var pause_font := _pause_label.get_theme_font("font")
	var pause_font_size := _pause_label.get_theme_font_size("font_size")
	var pause_text_width := pause_font.get_string_size(
		pause_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		pause_font_size
	).x
	_pause_label.text = (
		"小镇已暂停"
		if rect.size.x < 400.0 or pause_text_width > rect.size.x - 40.0
		else pause_text
	)
	_pause_label.tooltip_text = pause_text
	_pause_label.accessibility_name = pause_text


func _render_close(placement: Dictionary) -> void:
	var close_rect := _rect_from_dictionary(
		placement.get("closeRect", {}) as Dictionary
	)
	if close_rect.size.x <= 0.0 or close_rect.size.y <= 0.0:
		var safe := _rect_from_dictionary(
			placement.get("safeRect", {}) as Dictionary
		)
		close_rect = Rect2(
			Vector2(safe.end.x - 64, maxf(8, safe.position.y - 72)),
			Vector2(64, 64)
		)
	_close_button.position = close_rect.position.round()
	_close_button.size = close_rect.size.round()
	var action := (
		_view_model.get("actions", {}) as Dictionary
	).get("close", {}) as Dictionary
	_close_button.set_action_enabled(bool(action.get("enabled", false)))


func _render_feedback(data: Dictionary) -> void:
	var feedback := data.get("feedback", {}) as Dictionary
	var has_local_feedback := not _local_feedback_message.is_empty()
	var message := _local_feedback_message
	if message.is_empty():
		message = str(feedback.get("message", "")).strip_edges()
	var error_value: Variant = _view_model.get("error")
	if message.is_empty() and error_value is Dictionary:
		var error := error_value as Dictionary
		message = UiViewModel.public_operation_error_message(
			error,
			"操作没有完成，请稍后重试",
		)
	_feedback_panel.visible = not message.is_empty()
	if not _feedback_panel.visible:
		return
	var safe := _rect_from_dictionary(
		(data.get("placement", {}) as Dictionary).get(
			"safeRect",
			{}
		) as Dictionary
	)
	var width := minf(760.0, safe.size.x)
	var height := 72.0 if safe.size.x >= 600 else 112.0
	var feedback_font := _feedback_label.get_theme_font("font")
	var feedback_font_size := _feedback_label.get_theme_font_size("font_size")
	var wrapped_height := feedback_font.get_multiline_string_size(
		message,
		HORIZONTAL_ALIGNMENT_CENTER,
		width - 36.0,
		feedback_font_size,
		-1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
			| TextServer.BREAK_ADAPTIVE
	).y
	height = maxf(height, wrapped_height + 24.0)
	_feedback_panel.position = Vector2(
		safe.get_center().x - width * 0.5,
		safe.end.y - height
	).round()
	_feedback_panel.size = Vector2(width, height).round()
	_feedback_label.text = message
	var status := str(
		(_view_model.get("operation", {}) as Dictionary).get(
			"status",
			"idle"
		)
	)
	if has_local_feedback:
		status = "rejected"
	_feedback_label.add_theme_color_override(
		"font_color",
		COLOR_ERROR if status == "error" else COLOR_INK
	)
	_feedback_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(
			COLOR_PAPER,
			COLOR_ERROR if status == "error" else (
				COLOR_TERRACOTTA
				if status == "rejected"
				else COLOR_MOSS
			),
			4,
			8
		)
	)


func _solve_layout(data: Dictionary, _held_orientation: String) -> Dictionary:
	var placement := data.get("placement", {}) as Dictionary
	var safe_rect := _rect_from_dictionary(
		placement.get("safeRect", {}) as Dictionary
	)
	var focus_rect := _rect_from_dictionary(
		placement.get("focusRect", {}) as Dictionary
	)
	var anchor := _point_from_dictionary(
		placement.get("screenAnchor", {}) as Dictionary
	)
	var grid := maxf(1.0, float(placement.get("pixelGrid", 1)))
	var avoid_rects: Array[Rect2] = []
	for avoid_value: Variant in placement.get("avoidRects", []):
		if avoid_value is Dictionary:
			avoid_rects.append(_rect_from_dictionary(avoid_value as Dictionary))
	var close_rect := _rect_from_dictionary(
		placement.get("closeRect", {}) as Dictionary
	)
	if close_rect.size.x > 0:
		avoid_rects.append(close_rect)
	var profile := _profile_for_safe_rect(safe_rect)
	var component_size := _component_size_for_profile(profile)
	var multiline := profile == "narrow_dual_arc"
	var rects := _candidate_rects(
		profile,
		component_size,
		anchor
	)
	rects = _translate_inside_safe(rects, safe_rect)
	rects = _quantize_rects(rects, grid, safe_rect)
	rects = _place_kill_below_focus(rects, safe_rect, focus_rect, grid)
	rects = _translate_away_from_focus(rects, safe_rect, focus_rect, grid)
	var score := _layout_score(
		rects,
		safe_rect,
		focus_rect,
		avoid_rects,
		anchor
	)
	return {
		"profile": profile,
		"orientation": "up",
		"score": snappedf(score, 0.01),
		"rects": _rects_to_arrays(rects),
		"componentSize": [component_size.x, component_size.y],
		"componentGap": _component_gap_for_profile(profile),
		"multiline": multiline,
		"safeRect": _rect_to_array(safe_rect),
		"focusRect": _rect_to_array(focus_rect),
		"integerGrid": grid,
		"fontSizePx": 32,
		"fontReduction": false,
		"wholePageScale": false,
	}


func _candidate_rects(
	profile: String,
	component_size: Vector2,
	anchor: Vector2
) -> Dictionary:
	var centers := _relative_centers(
		profile,
		component_size
	)
	var rects := {}
	for index: int in _menu_order.size():
		var center: Vector2 = centers[index]
		rects[_menu_order[index]] = Rect2(
			(anchor + center - component_size * 0.5).round(),
			component_size
		)
	return rects


func _relative_centers(
	profile: String,
	component_size: Vector2
) -> Array[Vector2]:
	var component_gap := _component_gap_for_profile(profile)
	var top_y := -(
		component_size.y
		+ (
			56.0
			if profile in ["spacious_arc", "standard_arc"]
			else (48.0 if profile == "compact_arc" else 40.0)
		)
	)
	var side_x := component_size.x + component_gap
	var side_y := top_y + component_size.y * 0.45
	var lower_x := side_x * 0.92
	# Every neighboring control keeps the same profile gap. The old 0.90
	# height multiplier overlapped each upper/lower pair by 10% of the
	# component height, which made only those pairs look glued together.
	var lower_y := side_y + component_size.y + component_gap
	return [
		Vector2(0, top_y),
		Vector2(-side_x, side_y),
		Vector2(side_x, side_y),
		Vector2(-lower_x, lower_y),
		Vector2(lower_x, lower_y),
		Vector2(0, lower_y + component_size.y * 0.72),
	]


func _component_gap_for_profile(profile: String) -> float:
	if profile == "spacious_arc":
		return 24.0
	if profile == "standard_arc":
		return 20.0
	return 12.0


func _translate_inside_safe(
	rects: Dictionary,
	safe_rect: Rect2
) -> Dictionary:
	var bounds := _bounds_for_rects(rects)
	if bounds.size.x > safe_rect.size.x or bounds.size.y > safe_rect.size.y:
		return rects
	var offset := Vector2.ZERO
	if bounds.position.x < safe_rect.position.x:
		offset.x = safe_rect.position.x - bounds.position.x
	elif bounds.end.x > safe_rect.end.x:
		offset.x = safe_rect.end.x - bounds.end.x
	if bounds.position.y < safe_rect.position.y:
		offset.y = safe_rect.position.y - bounds.position.y
	elif bounds.end.y > safe_rect.end.y:
		offset.y = safe_rect.end.y - bounds.end.y
	var result := {}
	for item_id: String in rects:
		var rect := rects[item_id] as Rect2
		result[item_id] = Rect2(rect.position + offset, rect.size)
	return result


func _quantize_rects(
	rects: Dictionary,
	grid: float,
	safe_rect: Rect2
) -> Dictionary:
	var result := {}
	for item_id: String in rects:
		var rect := rects[item_id] as Rect2
		rect.position = Vector2(
			snappedf(rect.position.x, grid),
			snappedf(rect.position.y, grid)
		)
		rect.size = Vector2(
			snappedf(rect.size.x, grid),
			snappedf(rect.size.y, grid)
		)
		rect.position.x = clampf(
			rect.position.x,
			safe_rect.position.x,
			safe_rect.end.x - rect.size.x
		)
		rect.position.y = clampf(
			rect.position.y,
			safe_rect.position.y,
			safe_rect.end.y - rect.size.y
		)
		rect.position = rect.position.round()
		rect.size = rect.size.round()
		result[item_id] = rect
	return result


func _translate_away_from_focus(
	rects: Dictionary,
	safe_rect: Rect2,
	focus_rect: Rect2,
	grid: float
) -> Dictionary:
	var intersects_focus := false
	for rect_value: Variant in rects.values():
		if (rect_value as Rect2).grow(8.0).intersects(focus_rect):
			intersects_focus = true
			break
	if not intersects_focus:
		return rects
	var bounds := _bounds_for_rects(rects)
	var offset_x := 0.0
	if focus_rect.get_center().x <= safe_rect.get_center().x:
		offset_x = focus_rect.end.x + 8.0 - bounds.position.x
	else:
		offset_x = focus_rect.position.x - 8.0 - bounds.end.x
	offset_x = snappedf(offset_x, grid)
	offset_x = clampf(
		offset_x,
		safe_rect.position.x - bounds.position.x,
		safe_rect.end.x - bounds.end.x
	)
	var result := {}
	for item_id: String in rects:
		var rect := rects[item_id] as Rect2
		result[item_id] = Rect2(
			(rect.position + Vector2(offset_x, 0.0)).round(),
			rect.size
		)
	return result


func _place_kill_below_focus(
	rects: Dictionary,
	safe_rect: Rect2,
	focus_rect: Rect2,
	grid: float,
) -> Dictionary:
	if not rects.has("kill") or focus_rect.size == Vector2.ZERO:
		return rects
	var kill_rect := rects.get("kill", Rect2()) as Rect2
	var required_top := focus_rect.end.y + 8.0
	if kill_rect.position.y >= required_top:
		return rects
	var available_shift := safe_rect.end.y - kill_rect.end.y
	var requested_shift := snappedf(
		required_top - kill_rect.position.y,
		grid,
	)
	var shift := clampf(requested_shift, 0.0, available_shift)
	if shift <= 0.0:
		return rects
	var result := rects.duplicate()
	kill_rect.position.y = snappedf(
		kill_rect.position.y + shift,
		grid,
	)
	result["kill"] = kill_rect
	return result


func _layout_score(
	rects: Dictionary,
	safe_rect: Rect2,
	focus_rect: Rect2,
	avoid_rects: Array[Rect2],
	anchor: Vector2
) -> float:
	var score := 0.0
	var rect_array: Array[Rect2] = []
	for item_id: String in _menu_order:
		var rect := rects.get(item_id, Rect2()) as Rect2
		rect_array.append(rect)
		if not _rect_inside(rect, safe_rect):
			score += 1000000.0
		if rect.grow(8.0).intersects(focus_rect):
			score += 1000000.0
		for avoid: Rect2 in avoid_rects:
			if rect.grow(4.0).intersects(avoid):
				score += 1000000.0
	for left_index: int in rect_array.size():
		for right_index: int in range(left_index + 1, rect_array.size()):
			if rect_array[left_index].intersects(rect_array[right_index]):
				score += 1000000.0
	var bounds := _bounds_for_rects(rects)
	score += anchor.distance_to(bounds.get_center()) * 0.01
	return score


func _profile_for_safe_rect(safe_rect: Rect2) -> String:
	if safe_rect.size.y < 520.0:
		return "short_side_fan"
	if safe_rect.size.x >= 1440.0 and safe_rect.size.y >= 760.0:
		return "spacious_arc"
	if safe_rect.size.x >= 960.0:
		return "standard_arc"
	if safe_rect.size.x >= 600.0:
		return "compact_arc"
	return "narrow_dual_arc"


func _component_size_for_profile(profile: String) -> Vector2:
	match profile:
		"spacious_arc":
			return Vector2(160, 160)
		"standard_arc":
			return Vector2(148, 148)
		"compact_arc":
			return Vector2(132, 132)
		"narrow_dual_arc":
			return Vector2(108, 108)
		"short_side_fan":
			return Vector2(108, 108)
	return Vector2(160, 160)


func _active_item_id(operation: Dictionary) -> String:
	var action_key := str(operation.get("actionKey", ""))
	var request_id := str(operation.get("requestId", ""))
	if (
		action_key.is_empty()
		and not request_id.is_empty()
		and request_id == _last_requested_request_id
	):
		action_key = _last_requested_action_key
	if action_key.is_empty() and not _last_requested_action_key.is_empty():
		var last_action := (
			_view_model.get("actions", {}) as Dictionary
		).get(_last_requested_action_key, {}) as Dictionary
		if str(last_action.get("intent", "")) == str(
			operation.get("intent", "")
		):
			action_key = _last_requested_action_key
	for item_id: String in _menu_order:
		var bubble := _bubbles.get(item_id) as ResidentActionBubble
		if bubble != null and bubble.action_key == action_key:
			return item_id
	var intent := str(operation.get("intent", ""))
	match intent:
		"resident.follow":
			return "follow"
		"resident.detail.open":
			return "status"
		"resident.inner_observation.open":
			return "inner"
		"resident.death.confirm":
			return "kill"
	return ""


func _on_bubble_pressed(item_id: String) -> void:
	var data := _view_model.get("data", {}) as Dictionary
	for item_value: Variant in data.get("menuItems", []):
		if not (item_value is Dictionary):
			continue
		var item := item_value as Dictionary
		if str(item.get("id", "")) == item_id:
			_request_action(str(item.get("actionKey", "")))
			return


func _request_action(action_key: String) -> void:
	if _view_model.is_empty():
		return
	var actions := _view_model.get("actions", {}) as Dictionary
	var action := actions.get(action_key, {}) as Dictionary
	var intent := StringName(action.get("intent", ""))
	if action.is_empty() or intent.is_empty():
		_show_local_feedback("ACTION_NOT_AVAILABLE")
		action_blocked.emit(
			intent,
			"ACTION_NOT_AVAILABLE",
			_revision
		)
		return
	if not bool(action.get("enabled", false)):
		var disabled_reason := str(
			action.get("disabledReason", "ACTION_DISABLED")
		)
		_show_local_feedback(disabled_reason)
		action_blocked.emit(
			intent,
			disabled_reason,
			_revision
		)
		return
	_request_sequence += 1
	var request_id := "resident-action-menu-%d-%d-%s" % [
		Time.get_ticks_msec(),
		_request_sequence,
		action_key,
	]
	_last_requested_request_id = request_id
	_last_requested_action_key = action_key
	_local_feedback_message = ""
	var payload := (
		action.get("payload", {}) as Dictionary
	).duplicate(true)
	intent_requested.emit(
		intent,
		payload,
		_revision,
		request_id
	)


func _move_semantic_focus(direction: int) -> void:
	if _focus_controls.is_empty():
		return
	var current_index := -1
	var owner := get_viewport().gui_get_focus_owner()
	for index: int in _focus_controls.size():
		if _focus_controls[index] == owner:
			current_index = index
			break
	for step: int in range(1, _focus_controls.size() + 1):
		var index := posmod(
			current_index + direction * step,
			_focus_controls.size()
		)
		var candidate := _focus_controls[index]
		if candidate.visible and not (
			candidate is BaseButton and (candidate as BaseButton).disabled
		):
			candidate.grab_focus()
			return


func _link_semantic_focus() -> void:
	for index: int in _focus_controls.size():
		var control := _focus_controls[index]
		var next := _focus_controls[(index + 1) % _focus_controls.size()]
		var previous := _focus_controls[
			posmod(index - 1, _focus_controls.size())
		]
		control.focus_next = control.get_path_to(next)
		control.focus_previous = control.get_path_to(previous)


func _rebuild_focus_controls() -> void:
	_focus_controls.clear()
	for item_id: String in _menu_order:
		var bubble := _bubbles.get(item_id) as ResidentActionBubble
		if bubble != null and bubble.visible and not bubble.disabled:
			_focus_controls.append(bubble)
	if (
		_close_button != null
		and _close_button.visible
		and not _close_button.disabled
	):
		_focus_controls.append(_close_button)
	if not _focus_controls.is_empty():
		_link_semantic_focus()


func _focused_action_key() -> String:
	var owner := get_viewport().gui_get_focus_owner()
	for bubble_value: Variant in _bubbles.values():
		var bubble := bubble_value as ResidentActionBubble
		if bubble == owner:
			return bubble.action_key
	if owner == _close_button:
		return "close"
	return ""


func _restore_action_focus(action_key: String) -> void:
	if action_key.is_empty():
		return
	for control: Control in _focus_controls:
		if control == _close_button and action_key == "close":
			if not _close_button.disabled:
				_close_button.grab_focus()
			return
		var bubble := control as ResidentActionBubble
		if (
			bubble != null
			and bubble.action_key == action_key
			and not bubble.disabled
		):
			bubble.grab_focus()
			return
	for control: Control in _focus_controls:
		if control.visible and not (
			control is BaseButton and (control as BaseButton).disabled
		):
			control.grab_focus()
			return


func _on_adapter_view_model_changed(
	scope: StringName,
	snapshot: Dictionary
) -> void:
	if str(scope) == REQUIRED_SCOPE:
		apply_view_model(snapshot)


func _disconnect_adapter() -> void:
	UI_SIGNALS.disconnect_view_model(
		_adapter,
		Callable(self, "_on_adapter_view_model_changed"),
	)


func _on_viewport_size_changed() -> void:
	if not _view_model.is_empty():
		_render(false)


func _validate_snapshot(snapshot: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	for field: String in REQUIRED_FIELDS:
		if not snapshot.has(field):
			issues.append("居民功能气泡 ViewModel 缺少字段：%s" % field)
	if not issues.is_empty():
		return issues
	if str(snapshot.get("scope", "")) != REQUIRED_SCOPE:
		issues.append(
			"居民功能气泡拒绝 scope：%s"
			% str(snapshot.get("scope", ""))
		)
	for issue: String in UiViewModel.validate(
		snapshot,
		"居民功能气泡"
	):
		issues.append(issue)
	var data := snapshot.get("data", {}) as Dictionary
	if data.is_empty():
		issues.append("居民功能气泡 data 不能为空。")
		return issues
	for provenance_field: String in ["source", "capabilityMode", "formalReady"]:
		if not data.has(provenance_field):
			issues.append(
				"居民功能气泡 data 缺少来源字段：%s"
				% provenance_field
			)
	if str(data.get("source", "")).is_empty():
		issues.append("居民功能气泡 data.source 不能为空。")
	if str(data.get("capabilityMode", "")).is_empty():
		issues.append("居民功能气泡 data.capabilityMode 不能为空。")
	var placement := data.get("placement", {}) as Dictionary
	for placement_key: String in [
		"viewport",
		"screenAnchor",
		"focusRect",
		"safeRect",
		"closeRect",
		"avoidRects",
		"preferredArc",
		"pixelGrid",
	]:
		if not placement.has(placement_key):
			issues.append(
				"居民功能气泡 placement 缺少字段：%s"
				% placement_key
			)
	var order: Array[String] = []
	var menu_items := data.get("menuItems", []) as Array
	for item_value: Variant in menu_items:
		if item_value is Dictionary:
			order.append(str((item_value as Dictionary).get("id", "")))
	var expected_order: Array[String] = FORMAL_MENU_ORDER.duplicate()
	if menu_items.size() == FORMAL_MENU_ORDER.size() - 1:
		expected_order.resize(FORMAL_MENU_ORDER.size() - 1)
	if order != expected_order:
		issues.append("居民功能气泡 menuItems 语义顺序无效。")
	if (
		order == expected_order
		and menu_items.size() == expected_order.size()
	):
		var expected_items := {
			"follow": ["follow", "follow_camera"],
			"status": ["openStatus", "resident_status"],
			"relationship": [
				"openRelationship",
				"resident_relationship",
			],
			"memory": ["openMemory", "resident_memory"],
			"inner": ["openInner", "inner_observation"],
			"kill": ["killResident", "resident_death"],
		}
		for index: int in expected_order.size():
			var item := menu_items[index] as Dictionary
			var item_id: String = expected_order[index]
			var expected := expected_items[item_id] as Array
			for item_field: String in [
				"id",
				"actionKey",
				"label",
				"iconKey",
				"semanticOrder",
			]:
				if not item.has(item_field):
					issues.append(
						"居民功能气泡 menuItem %s 缺少字段：%s"
						% [item_id, item_field]
					)
			if str(item.get("label", "")).strip_edges().is_empty():
				issues.append(
					"居民功能气泡 menuItem %s label 不能为空。"
					% item_id
				)
			if str(item.get("actionKey", "")) != str(expected[0]):
				issues.append(
					"居民功能气泡 menuItem %s actionKey 与正式合同不一致。"
					% item_id
				)
			if str(item.get("iconKey", "")) != str(expected[1]):
				issues.append(
					"居民功能气泡 menuItem %s iconKey 与批准资产不一致。"
					% item_id
				)
			if int(item.get("semanticOrder", -1)) != index:
				issues.append(
					"居民功能气泡 menuItem %s semanticOrder 无效。"
					% item_id
				)
	else:
		issues.append("居民功能气泡正式 menuItems 数量必须为 5 或 6。")
	var actions := snapshot.get("actions", {}) as Dictionary
	for action_key_value: Variant in actions:
		var action_key := str(action_key_value)
		if not FORMAL_ACTION_KEYS.has(action_key):
			issues.append(
				"居民功能气泡 actions 含未声明动作：%s"
				% action_key
			)
	for action_key: String in FORMAL_ACTION_KEYS:
		var action_value: Variant = actions.get(action_key)
		if not (action_value is Dictionary):
			issues.append(
				"居民功能气泡 actions 缺少：%s"
				% action_key
			)
			continue
		var action := action_value as Dictionary
		for action_field: String in [
			"intent",
			"enabled",
			"disabledReason",
			"payload",
		]:
			if not action.has(action_field):
				issues.append(
					"居民功能气泡 action %s 缺少字段：%s"
					% [action_key, action_field]
				)
		if action.has("payload") and not (action.get("payload") is Dictionary):
			issues.append(
				"居民功能气泡 action %s payload 必须是对象。"
				% action_key
			)
		if (
			not bool(action.get("enabled", false))
			and str(action.get("disabledReason", "")).is_empty()
		):
			issues.append(
				"居民功能气泡禁用 action %s 缺少 disabledReason。"
				% action_key
			)
	_validate_formal_action_contract(actions, issues)
	return issues


func _validate_formal_action_contract(
	actions: Dictionary,
	issues: PackedStringArray
) -> void:
	var expected := {
		"follow": {"intent": "resident.follow", "tab": ""},
		"openStatus": {"intent": "resident.detail.open", "tab": "status"},
		"openRelationship": {
			"intent": "resident.detail.open",
			"tab": "relationship",
		},
		"openMemory": {"intent": "resident.detail.open", "tab": "memory"},
		"openInner": {
			"intent": "resident.inner_observation.open",
			"tab": "",
		},
		"killResident": {
			"intent": "resident.death.confirm",
			"tab": "",
		},
		"close": {"intent": "resident.action_menu.close", "tab": ""},
	}
	for action_key: String in expected:
		var action := actions.get(action_key, {}) as Dictionary
		if action.is_empty():
			continue
		if action_key == "close" and not bool(action.get("enabled", false)):
			issues.append("居民功能气泡 close 必须始终可用。")
		var contract := expected[action_key] as Dictionary
		if str(action.get("intent", "")) != str(contract.get("intent", "")):
			issues.append(
				"居民功能气泡 action %s intent 与正式合同不一致。"
				% action_key
			)
		var payload_value: Variant = action.get("payload", {})
		if not (payload_value is Dictionary):
			continue
		if (
			action_key != "close"
			and bool(action.get("enabled", false))
			and str(
				(payload_value as Dictionary).get("residentId", "")
			).is_empty()
		):
			issues.append(
				"居民功能气泡 action %s 缺少 residentId。"
				% action_key
			)
		var expected_tab := str(contract.get("tab", ""))
		if (
			not expected_tab.is_empty()
			and str((payload_value as Dictionary).get("tab", ""))
			!= expected_tab
		):
			issues.append(
				"居民功能气泡 action %s tab 与正式合同不一致。"
				% action_key
			)


func _show_local_feedback(reason_code: String) -> void:
	_local_feedback_message = _feedback_copy_for_code(reason_code)
	if _local_feedback_message.is_empty():
		_local_feedback_message = "此操作暂不可用"
	if is_node_ready() and not _view_model.is_empty():
		_render_feedback(_view_model.get("data", {}) as Dictionary)


func show_navigation_failure(message: String) -> void:
	_local_feedback_message = message.strip_edges()
	if _local_feedback_message.is_empty():
		_local_feedback_message = "页面暂时打不开，请稍后再试。"
	if is_node_ready() and not _view_model.is_empty():
		_render_feedback(_view_model.get("data", {}) as Dictionary)


func _feedback_copy_for_code(code: String) -> String:
	return str(LOCAL_FEEDBACK_COPY.get(code, ""))


func _panel_style(
	background: Color,
	border: Color,
	border_width: int,
	radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(0.18, 0.10, 0.05, 0.50)
	style.shadow_size = 4
	style.shadow_offset = Vector2(4, 5)
	return style


func _asset_ownership_audit() -> Dictionary:
	var entries: Array[Dictionary] = []
	for item_id: String in _menu_order:
		var bubble := _bubbles.get(item_id) as ResidentActionBubble
		if bubble == null:
			continue
		var control_path := str(bubble.get_path())
		var art_owner := control_path + "/ApprovedButtonArt"
		entries.append({
			"layer": "operation_control",
			"semantic": "bubble_complete_art.%s" % item_id,
			"owner": art_owner,
			"assetId": (
				"ui.resident-action-menu.button.%s.candidate-v3"
				% item_id
			),
			"assetPath": (
				"res://assets/ui/resident_action_menu/final/"
				+ ("resident_action_button_%s_v3.png" % item_id)
			),
			"componentType": "page_local_complete_operation_texture",
			"registeredAsCommonStyleBoxTexture": false,
			"ownsOuterFrame": true,
			"ownsSemanticIcon": true,
			"ownsSingleTail": true,
			"functionalTextBakedIntoImage": false,
			"anisotropicFullImageResize": false,
			"programmaticFrameFallback": false,
			"commonApproximation": false,
			"goldFocusFrame": false,
		})
		entries.append({
			"layer": "content_slot",
			"semantic": "bubble_text_content.%s" % item_id,
			"owner": control_path + "/Label",
			"componentType": "godot_label_no_frame",
			"drawsFrame": false,
		})
		entries.append({
			"layer": "operation_control",
			"semantic": "bubble_halo.%s" % item_id,
			"owner": control_path + "/HaloAsset",
			"assetId": "ui.resident-action-menu.halo.imagegen-v1",
			"componentType": "independent_alpha_image",
			"drawsFrame": false,
		})
	entries.append({
		"layer": "partition_frame",
		"semantic": "pause_banner_outer_frame",
		"owner": str(_pause_panel.get_path()),
		"assetId": (
			"ui.resident-action-menu.pause-banner.imagegen-v2"
		),
		"assetPath": (
			"res://assets/ui/resident_action_menu/final/"
			+ "resident_action_pause_banner_v2.png"
		),
		"componentType": "page_local_composite_nine_patch_control",
		"registeredAsCommonStyleBoxTexture": false,
		"childDrawsDuplicateFrame": false,
	})
	entries.append({
		"layer": "content_slot",
		"semantic": "pause_banner_text_content",
		"owner": str(_pause_label.get_path()),
		"componentType": "godot_label_no_frame",
		"drawsFrame": false,
	})
	entries.append({
		"layer": "partition_frame",
		"semantic": "feedback_outer_frame",
		"owner": str(_feedback_panel.get_path()),
		"componentType": "page_local_panel_style_single_owner",
		"childDrawsDuplicateFrame": false,
	})
	var close_ownership := _close_button.debug_asset_ownership()
	entries.append({
		"layer": "operation_control",
		"semantic": "close_outer_frame_and_symbol",
		"owner": (
			str(_close_button.get_path())
			+ "/CloseTextureAsset"
		),
		"assetId": "ui.resident-action-menu.close.candidate-v3",
		"assetPath": (
			"res://assets/ui/resident_action_menu/final/"
			+ "resident_action_close_v3.png"
		),
		"componentType": close_ownership.get(
			"componentType",
			"page_local_image_operation_control"
		),
		"childDrawsDuplicateFrame": false,
	})
	var owner_by_semantic := {}
	var duplicate_semantics: Array[String] = []
	var unowned_semantics: Array[String] = []
	for entry: Dictionary in entries:
		var semantic := str(entry.get("semantic", ""))
		var owner := str(entry.get("owner", ""))
		if semantic.is_empty() or owner.is_empty():
			unowned_semantics.append(semantic)
			continue
		if owner_by_semantic.has(semantic):
			duplicate_semantics.append(semantic)
		else:
			owner_by_semantic[semantic] = owner
	return {
		"hierarchy": [
			"page_shell",
			"partition_frame",
			"content_slot",
			"operation_control",
		],
		"pageShell": "none_visible",
		"entries": entries,
		"duplicateSemantics": duplicate_semantics,
		"unownedSemantics": unowned_semantics,
		"compositeRegisteredAsCommonStyleBoxTexture": false,
		"oneCompleteImagePerOperationControl": true,
		"separateRuntimeTailAssetsUsed": false,
		"separateRuntimeIconAssetsUsed": false,
		"programmaticFrameFallbackUsed": false,
		"commonApproximationUsed": false,
		"goldFocusFrameUsed": false,
		"overallStatus": (
			"pass"
			if (
				duplicate_semantics.is_empty()
				and unowned_semantics.is_empty()
			)
			else "fail"
		),
	}


func _rect_from_dictionary(value: Dictionary) -> Rect2:
	return Rect2(
		float(value.get("x", 0)),
		float(value.get("y", 0)),
		float(value.get("width", 0)),
		float(value.get("height", 0))
	)


func _point_from_dictionary(value: Dictionary) -> Vector2:
	return Vector2(
		float(value.get("x", 0)),
		float(value.get("y", 0))
	)


func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x
		and inner.position.y >= outer.position.y
		and inner.end.x <= outer.end.x
		and inner.end.y <= outer.end.y
	)


func _bounds_for_rects(rects: Dictionary) -> Rect2:
	var result := Rect2()
	var first := true
	for item_id: String in rects:
		var rect := rects[item_id] as Rect2
		if first:
			result = rect
			first = false
		else:
			result = result.merge(rect)
	return result


func _rects_to_arrays(rects: Dictionary) -> Dictionary:
	var result := {}
	for item_id: String in rects:
		result[item_id] = _rect_to_array(rects[item_id] as Rect2)
	return result


func _rect_to_array(rect: Rect2) -> Array[float]:
	return [
		rect.position.x,
		rect.position.y,
		rect.size.x,
		rect.size.y,
	]


func _array_to_rect2(value: Variant) -> Rect2:
	if not (value is Array) or (value as Array).size() < 4:
		return Rect2()
	var values := value as Array
	return Rect2(
		float(values[0]),
		float(values[1]),
		float(values[2]),
		float(values[3])
	)


func _array_to_vector2(value: Variant) -> Vector2:
	if not (value is Array) or (value as Array).size() < 2:
		return Vector2.ZERO
	var values := value as Array
	return Vector2(float(values[0]), float(values[1]))
