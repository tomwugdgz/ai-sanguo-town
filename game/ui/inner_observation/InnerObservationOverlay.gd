class_name InnerObservationOverlay
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
signal snapshot_rejected(reason: String, revision: int)

const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")

const REQUIRED_SCOPE := "inner_observation"
const EXIT_INTENT := &"inner_observation.exit"
const RETRY_INTENT := &"inner_observation.retry"
const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const STABLE_RUNTIME_ASSETS := {
	"stable_1920x1080": {
		"panel": (
			"res://assets/ui/inner_observation/final/"
			+ "inner_observation_runtime_panel_1920x1080_v2.png"
		),
		"portraitFrame": (
			"res://assets/ui/inner_observation/final/"
			+ "inner_observation_runtime_portrait_frame_1920x1080_v2.png"
		),
	},
	"stable_1280x720": {
		"panel": (
			"res://assets/ui/inner_observation/final/"
			+ "inner_observation_runtime_panel_1280x720_v2.png"
		),
		"portraitFrame": (
			"res://assets/ui/inner_observation/final/"
			+ "inner_observation_runtime_portrait_frame_1280x720_v2.png"
		),
	},
}

const REFERENCE_VIEWPORT := Vector2(1920.0, 1080.0)
const REFERENCE_GLOBAL_SAFE_RECT := Rect2(48, 48, 1824, 984)
const REFERENCE_PANEL_RECT := Rect2(741, 101, 920, 852)
const REFERENCE_PORTRAIT_FRAME_RECT := Rect2(268, 194, 310, 610)
const REFERENCE_PORTRAIT_RECT := Rect2(295, 366, 256, 256)
const REFERENCE_WHISPER_RECT := Rect2(802, 152, 794, 48)
const REFERENCE_NAME_RECT := Rect2(822, 213, 754, 71)
const REFERENCE_MONOLOGUE_RECT := Rect2(822, 343, 754, 236)
const REFERENCE_REASON_RECT := Rect2(818, 677, 762, 124)
const REFERENCE_STATUS_RECT := Rect2(822, 866, 344, 48)
const REFERENCE_RETRY_RECT := Rect2(1182, 850, 82, 60)
const REFERENCE_EXIT_RECT := Rect2(1286, 850, 296, 60)
const STABLE_1280_GLOBAL_SAFE_RECT := Rect2(24, 24, 1232, 672)
const STABLE_1280_PANEL_RECT := Rect2(544, 24, 712, 672)
const STABLE_1280_PORTRAIT_FRAME_RECT := Rect2(125, 94, 270, 532)
const STABLE_1280_PORTRAIT_RECT := Rect2(160, 270, 200, 200)
const STABLE_1280_WHISPER_RECT := Rect2(591, 64, 615, 48)
const STABLE_1280_NAME_RECT := Rect2(607, 105, 584, 56)
const STABLE_1280_MONOLOGUE_RECT := Rect2(619, 214, 560, 200)
const STABLE_1280_REASON_RECT := Rect2(616, 476, 566, 110)
const STABLE_1280_STATUS_RECT := Rect2(607, 620, 300, 48)
const STABLE_1280_RETRY_RECT := Rect2(915, 616, 72, 60)
const STABLE_1280_EXIT_RECT := Rect2(967, 608, 221, 52)
const STABLE_1280_EXIT_WITH_RETRY_RECT := Rect2(995, 616, 209, 60)

const VALID_PHASES: Array[String] = [
	"hidden",
	"opening",
	"generating",
	"ready",
	"failed",
	"closing",
]
const VALID_VISIBILITIES: Array[String] = ["hidden", "visible"]
const VALID_GENERATION_STATUSES: Array[String] = [
	"idle",
	"generating",
	"ready",
	"error",
	"disabled",
]
const VALID_EXPRESSION_IDS: Array[String] = [
	"calm",
	"happy",
	"angry",
	"sad",
]
const VALID_PORTRAIT_SOURCE_KINDS: Array[String] = [
	"front_expression",
	"front_walk_frame",
	"true_bust_portrait",
	"avatar",
	"placeholder",
]
const VALID_PORTRAIT_STATUSES: Array[String] = [
	"ready",
	"missing",
	"placeholder",
]
const BANNED_RENDER_KEY_TOKENS: Array[String] = [
	"prompt",
	"systemprompt",
	"systeminstruction",
	"systeminstructions",
	"providerresponse",
	"providerrawresponse",
	"rawproviderresponse",
	"rawresponse",
	"modelresponse",
	"providerlog",
	"providerlogs",
	"modellog",
	"modellogs",
	"trace",
	"traceid",
	"modeltrace",
	"sourceeventids",
	"sourceid",
	"sourceids",
	"sourcememoryids",
	"sourceplanid",
	"sourcetraceid",
	"eventid",
	"eventids",
	"memoryid",
	"memoryids",
	"planid",
	"actionid",
	"decisionid",
	"reasoning",
	"candidatereasoning",
	"chainofthought",
	"thoughts",
	"currentthoughts",
	"rawemotion",
	"originalemotion",
	"confidence",
	"score",
	"agentstate",
	"worldstate",
	"residentstate",
	"memorystore",
	"privatestate",
	"providerobject",
	"agentnode",
	"worldnode",
	"objectreference",
]
const PLAYER_SAFE_RETRYABLE_ERROR_FALLBACK := "暂时没听清，可以重试。"
const PLAYER_SAFE_FINAL_ERROR_FALLBACK := "现在无法查看这名居民的内心。"
const PLAYER_SAFE_REJECTED_FALLBACK := "状态变化，保留。"
const PLAYER_SAFE_DISABLED_FALLBACK := "内心暂不可用。"
const BODY_FONT_SIZE := 32
const NAME_FONT_SIZE := 48
const BODY_LINE_SPACING := 4
const MONOLOGUE_MIN_FONT_SIZE := 18
const REASON_MIN_FONT_SIZE := 21
const INNER_SECTION_TITLE := "此刻的心声"
const CLOSED_REQUEST_HISTORY_LIMIT := 64
var _adapter: Object
var _highest_seen_revision := -1
var _confirmed_revision := -1
var _snapshot: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _actions: Dictionary = {}
var _closed_request_ids: Dictionary = {}
var _closed_request_order: Array[String] = []
var _closed_at_revision := -1
var _active_generation_request_id := ""
var _active_resident_id := ""
var _exit_pending := false
var _pending_action_keys: Dictionary = {}
var _layout_profile := "hidden"
var _safe_debug_enabled := false
var _last_layout: Dictionary = {}

var _font_file: FontFile
var _body_font: FontVariation
var _compact_font: FontVariation
var _reason_font: FontVariation
var _button_font: FontVariation

var _dimmer: ColorRect
var _focus_glow: Panel
var _portrait_frame: TextureRect
var _portrait: TextureRect
var _portrait_fallback: Label
var _panel: TextureRect
var _whisper: Label
var _resident_name: Label
var _monologue: Label
var _reason: Label
var _status: Label
var _retry: Button
var _exit: Button
var _safe_overlay: SafeAreaOverlay


class SafeAreaOverlay:
	extends Control

	var rects: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func set_rects(next_rects: Dictionary) -> void:
		rects = next_rects.duplicate(true)
		queue_redraw()

	func _draw() -> void:
		var colors := {
			"globalSafe": Color("39d9ff"),
			"panel": Color("ffd54d"),
			"portraitFrame": Color("72f28b"),
			"portrait": Color("7cf0ca"),
			"focusGlow": Color("ffe07a"),
			"whisper": Color("d685ff"),
			"name": Color("d685ff"),
			"monologue": Color("d685ff"),
			"reason": Color("d685ff"),
			"status": Color("d685ff"),
			"retry": Color("ff8d70"),
			"exit": Color("ff8d70"),
		}
		for key: String in rects:
			var value: Variant = rects[key]
			if typeof(value) != TYPE_RECT2:
				continue
			var color: Color = colors.get(key, Color.WHITE)
			draw_rect(value as Rect2, color, false, 2.0)


func _ready() -> void:
	_font_file = ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if _font_file == null:
		push_error("InnerObservationOverlay 缺少已锁定公共字体 v6")
		visible = false
		return
	_body_font = _font_variation(2, 0.0)
	_compact_font = _font_variation(0, 0.0)
	_reason_font = _font_variation(-1, 0.0)
	# Action labels share the exact startup main-menu face and weight.
	_button_font = _font_variation(2, 0.0)
	_build_controls()
	resized.connect(_on_resized)
	visible = false
	set_process_unhandled_input(false)
	_apply_initial_adapter_view_model()


func bind_town_ui_adapter(adapter: Object) -> void:
	_disconnect_adapter()
	_adapter = adapter
	if _adapter == null:
		if is_node_ready():
			_hide_without_input()
		return
	if not _adapter.has_signal("view_model_changed"):
		push_warning("InnerObservationOverlay 只接受 TownUiAdapter ViewModel 信号")
		_adapter = null
		if is_node_ready():
			_hide_without_input()
		return
	var callback := Callable(self, "_on_adapter_view_model_changed")
	if not _adapter.is_connected("view_model_changed", callback):
		_adapter.connect("view_model_changed", callback)
	if not is_node_ready():
		return
	_apply_initial_adapter_view_model()


func _apply_initial_adapter_view_model() -> void:
	if (
		not is_node_ready()
		or _adapter == null
		or not is_instance_valid(_adapter)
	):
		return
	if _adapter.has_method("get_view_model"):
		var initial: Variant = _adapter.call("get_view_model", REQUIRED_SCOPE)
		if (
			typeof(initial) == TYPE_DICTIONARY
			and not (initial as Dictionary).is_empty()
		):
			apply_view_model(initial as Dictionary)


func unbind_town_ui_adapter() -> void:
	_disconnect_adapter()
	_adapter = null
	_hide_without_input()


func apply_view_model(view_model: Dictionary) -> bool:
	var issues := _validate_snapshot(view_model)
	var incoming_revision := int(view_model.get("revision", -1))
	if not issues.is_empty():
		_reject_snapshot("; ".join(issues), incoming_revision)
		return false
	if incoming_revision < _highest_seen_revision:
		_reject_snapshot("stale_revision", incoming_revision)
		return false

	var incoming_data := view_model.get("data", {}) as Dictionary
	var operation_status := String(
		(view_model.get("operation", {}) as Dictionary).get(
			"status",
			"idle"
		)
	)
	var effective_data := incoming_data
	if operation_status == "rejected" and incoming_data.is_empty():
		effective_data = _last_confirmed_data
	var visibility := String(effective_data.get("visibility", "hidden"))
	var incoming_phase := String(effective_data.get("phase", "hidden"))
	var generation := effective_data.get("generation", {}) as Dictionary
	var incoming_request_id := String(generation.get("requestId", ""))
	var operation := view_model.get("operation", {}) as Dictionary
	var is_exit_resolution := (
		String(operation.get("intent", "")) == String(EXIT_INTENT)
		and operation_status in ["rejected", "error", "disabled"]
	)
	if visibility == "visible":
		if (
			not incoming_request_id.is_empty()
			and _closed_request_ids.has(incoming_request_id)
			and incoming_phase != "closing"
			and not is_exit_resolution
		):
			_reject_snapshot("late_closed_request", incoming_revision)
			return false
		if (
			_closed_at_revision >= 0
			and incoming_revision <= _closed_at_revision
		):
			_reject_snapshot("late_visible_revision", incoming_revision)
			return false

	_highest_seen_revision = maxi(_highest_seen_revision, incoming_revision)
	_snapshot = view_model.duplicate(true)
	_actions = (
		(view_model.get("actions", {}) as Dictionary).duplicate(true)
	)
	_release_completed_action(view_model)

	if operation_status == "rejected":
		_render_data = effective_data.duplicate(true)
	else:
		_render_data = incoming_data.duplicate(true)
		if not incoming_data.is_empty():
			_last_confirmed_data = incoming_data.duplicate(true)
			_confirmed_revision = incoming_revision
	if visibility == "hidden":
		_record_closed_session(incoming_request_id, incoming_revision)
		_hide_without_input()
		return true

	var next_resident := _render_data.get("resident", {}) as Dictionary
	var next_generation := _render_data.get("generation", {}) as Dictionary
	var next_request_id := String(next_generation.get("requestId", ""))
	if (
		_exit_pending
		and not next_request_id.is_empty()
		and next_request_id != _active_generation_request_id
		and incoming_revision > _closed_at_revision
	):
		_exit_pending = false
		_pending_action_keys.clear()
	_active_generation_request_id = next_request_id
	_active_resident_id = String(next_resident.get("residentId", ""))
	_apply_render_data()
	return true


func request_exit() -> bool:
	return _submit_action("exit", EXIT_INTENT)


func request_retry() -> bool:
	return _submit_action("retry", RETRY_INTENT)


func set_debug_safe_area(enabled: bool) -> void:
	_safe_debug_enabled = enabled
	if _safe_overlay != null:
		_safe_overlay.visible = enabled and visible
		_safe_overlay.set_rects(_last_layout)


func debug_state() -> Dictionary:
	return {
		"scope": String(_snapshot.get("scope", "")),
		"visible": visible,
		"inputBlocked": visible,
		"highestSeenRevision": _highest_seen_revision,
		"confirmedRevision": _confirmed_revision,
		"residentId": _active_resident_id,
		"generationRequestId": _active_generation_request_id,
		"exitPending": _exit_pending,
		"pageIndex": 0,
		"pageCount": 1 if visible else 0,
		"pageText": _monologue.text if _monologue != null else "",
		"reasonText": _reason.text if _reason != null else "",
		"layoutProfile": _layout_profile,
		"layout": _rect_dictionary_payload(_last_layout),
		"phase": String(_render_data.get("phase", "hidden")),
	}


func debug_reconstructed_content() -> Dictionary:
	return {
		"monologue": _monologue.tooltip_text.replace("\n", ""),
		"reason": _reason.tooltip_text.replace("\n", ""),
	}


func debug_focus_exit() -> void:
	if _exit != null and _exit.visible and not _exit.disabled:
		_exit.grab_focus()


func debug_apply_layout_for_viewport(viewport_size: Vector2) -> void:
	_update_layout_for_viewport(viewport_size)
	var content := _render_data.get("content", {}) as Dictionary
	_render_focus_content(content)


func _build_controls() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

	_dimmer = ColorRect.new()
	_dimmer.name = "WorldInputDimmer"
	_dimmer.color = Color(0.035, 0.027, 0.018, 0.70)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dimmer)

	_focus_glow = Panel.new()
	_focus_glow.name = "ResidentWarmFocus"
	_focus_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(1.0, 0.72, 0.28, 0.13)
	glow_style.corner_radius_top_left = 160
	glow_style.corner_radius_top_right = 160
	glow_style.corner_radius_bottom_left = 48
	glow_style.corner_radius_bottom_right = 48
	_focus_glow.add_theme_stylebox_override("panel", glow_style)
	add_child(_focus_glow)

	_portrait_frame = _make_texture_rect(
		"PortraitFrameComposite",
		String(
			(STABLE_RUNTIME_ASSETS["stable_1920x1080"] as Dictionary)[
				"portraitFrame"
			]
		)
	)
	add_child(_portrait_frame)

	_portrait = TextureRect.new()
	_portrait.name = "ResidentPortrait"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)

	_portrait_fallback = _make_label(
		"PortraitUnavailable",
		_body_font,
		NAME_FONT_SIZE,
		Color("76583d"),
		HORIZONTAL_ALIGNMENT_CENTER,
		VERTICAL_ALIGNMENT_CENTER,
		TextServer.AUTOWRAP_WORD_SMART
	)
	_portrait_fallback.text = ""
	add_child(_portrait_fallback)

	_panel = _make_texture_rect(
		"PanelComposite",
		String(
			(STABLE_RUNTIME_ASSETS["stable_1920x1080"] as Dictionary)[
				"panel"
			]
		)
	)
	add_child(_panel)

	_whisper = _make_label(
		"ObservationWhisper",
		_body_font,
		BODY_FONT_SIZE,
		Color("67442b"),
		HORIZONTAL_ALIGNMENT_CENTER,
		VERTICAL_ALIGNMENT_CENTER,
		TextServer.AUTOWRAP_OFF
	)
	add_child(_whisper)

	_resident_name = _make_label(
		"ResidentName",
		_body_font,
		NAME_FONT_SIZE,
		Color("3f2717"),
		HORIZONTAL_ALIGNMENT_CENTER,
		VERTICAL_ALIGNMENT_CENTER,
		TextServer.AUTOWRAP_OFF
	)
	add_child(_resident_name)

	_monologue = _make_label(
		"FormalFirstPersonSummary",
		_body_font,
		BODY_FONT_SIZE,
		Color("3f2717"),
		HORIZONTAL_ALIGNMENT_LEFT,
		VERTICAL_ALIGNMENT_TOP,
		TextServer.AUTOWRAP_ARBITRARY
	)
	add_child(_monologue)

	_reason = _make_label(
		"NaturalReason",
		_reason_font,
		BODY_FONT_SIZE,
		Color("5a3b25"),
		HORIZONTAL_ALIGNMENT_LEFT,
		VERTICAL_ALIGNMENT_TOP,
		TextServer.AUTOWRAP_ARBITRARY
	)
	add_child(_reason)

	_status = _make_label(
		"PlayerStatus",
		_compact_font,
		BODY_FONT_SIZE,
		Color("76583d"),
		HORIZONTAL_ALIGNMENT_LEFT,
		VERTICAL_ALIGNMENT_CENTER,
		TextServer.AUTOWRAP_OFF
	)
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_status)

	_retry = _make_action_button("RetryAction", "重试")
	_center_button_text_optically(_retry, 24.0)
	_retry.pressed.connect(request_retry)
	add_child(_retry)

	_exit = _make_action_button("ExitAction", "退出观察")
	_center_button_text_optically(_exit, 24.0)
	_exit.pressed.connect(request_exit)
	add_child(_exit)

	_safe_overlay = SafeAreaOverlay.new()
	_safe_overlay.name = "SafeAreaDiagnostics"
	_safe_overlay.visible = false
	add_child(_safe_overlay)


func _make_texture_rect(node_name: String, path: String) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = node_name
	texture_rect.texture = ResourceLoader.load(path, "Texture2D") as Texture2D
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect


func _make_label(
	node_name: String,
	font: Font,
	font_size: int,
	font_color: Color,
	horizontal_alignment: HorizontalAlignment,
	vertical_alignment: VerticalAlignment,
	autowrap_mode: TextServer.AutowrapMode
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.horizontal_alignment = horizontal_alignment
	label.vertical_alignment = vertical_alignment
	label.autowrap_mode = autowrap_mode
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_constant_override("line_spacing", BODY_LINE_SPACING)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_action_button(node_name: String, text_value: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _button_font)
	button.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	button.add_theme_color_override("font_color", Color("fff8e6"))
	button.add_theme_color_override("font_hover_color", Color("fff3bf"))
	button.add_theme_color_override("font_focus_color", Color("fff3bf"))
	button.add_theme_color_override("font_pressed_color", Color("ffe39a"))
	button.add_theme_color_override("font_disabled_color", Color("d7bf94"))
	button.add_theme_color_override("font_outline_color", Color("4a2115"))
	button.add_theme_constant_override("outline_size", 1)
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"disabled",
		"focus",
	]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return button


func _center_button_text_optically(button: Button, bottom_margin: float) -> void:
	for state: String in [
		"normal",
		"hover",
		"pressed",
		"disabled",
		"focus",
	]:
		var style := StyleBoxEmpty.new()
		style.content_margin_bottom = bottom_margin
		button.add_theme_stylebox_override(state, style)


func _font_variation(spacing_glyph: int, embolden: float) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = _font_file
	variation.spacing_glyph = spacing_glyph
	variation.spacing_space = 0
	variation.variation_embolden = embolden
	return variation


func _on_adapter_view_model_changed(
	scope: String,
	view_model: Dictionary
) -> void:
	if scope != REQUIRED_SCOPE:
		return
	apply_view_model(view_model)


func _disconnect_adapter() -> void:
	if _adapter == null or not is_instance_valid(_adapter):
		return
	if not _adapter.has_signal("view_model_changed"):
		return
	var callback := Callable(self, "_on_adapter_view_model_changed")
	if _adapter.is_connected("view_model_changed", callback):
		_adapter.disconnect("view_model_changed", callback)


func _validate_snapshot(view_model: Dictionary) -> PackedStringArray:
	var issues := UiViewModel.validate(
		view_model,
		"InnerObservationOverlay"
	)
	if String(view_model.get("scope", "")) != REQUIRED_SCOPE:
		issues.append("scope 必须为 inner_observation")
	var data_value: Variant = view_model.get("data", {})
	if typeof(data_value) != TYPE_DICTIONARY:
		return issues
	var data := data_value as Dictionary
	var banned_path := _find_banned_render_key(view_model, "viewModel")
	if not banned_path.is_empty():
		issues.append("玩家 ViewModel 含私有字段：%s" % banned_path)
	var operation_status := String(
		(view_model.get("operation", {}) as Dictionary).get(
			"status",
			"idle"
		)
	)
	var rejected_without_data := operation_status == "rejected" and data.is_empty()
	if not rejected_without_data:
		var formal_ready_value: Variant = data.get("formalReady", false)
		if (
			typeof(formal_ready_value) != TYPE_BOOL
			or not bool(formal_ready_value)
		):
			issues.append("formalReady 必须为 true")
		if (
			not _is_text_value(data.get("capabilityMode", ""))
			or String(data.get("capabilityMode", "")) != "formal"
		):
			issues.append("capabilityMode 必须为 formal")
		if (
			not _is_text_value(data.get("source", ""))
			or String(data.get("source", "")) != "town_ui_adapter"
		):
			issues.append("source 必须为 town_ui_adapter")
	if not rejected_without_data and not _is_text_value(
		data.get("visibility", "")
	):
		issues.append("visibility 必须为字符串")
	var visibility := String(data.get("visibility", ""))
	if not rejected_without_data and not VALID_VISIBILITIES.has(visibility):
		issues.append("visibility 无效")
	if not rejected_without_data and not _is_text_value(data.get("phase", "")):
		issues.append("phase 必须为字符串")
	var phase := String(data.get("phase", ""))
	if not rejected_without_data and not VALID_PHASES.has(phase):
		issues.append("phase 无效")
	var generation_status := ""
	var generation_retryable := false
	if visibility == "visible":
		var expected_view_status := String({
			"opening": "opening",
			"generating": "loading",
			"ready": "ready",
			"failed": "error",
			"closing": "loading",
		}.get(phase, ""))
		if (
			expected_view_status.is_empty()
			or String(view_model.get("status", "")) != expected_view_status
		):
			issues.append("可见页面 status 与 phase 不一致")
		if (
			not _is_text_value(data.get("pauseState", ""))
			or String(
				data.get("pauseState", "")
			) != "running"
		):
			issues.append("可见页面 pauseState 必须为 running")
		var background_value: Variant = data.get("background", {})
		if typeof(background_value) != TYPE_DICTIONARY:
			issues.append("background 必须为 Dictionary")
		else:
			var background := background_value as Dictionary
			if (
				not _is_text_value(background.get("mode", ""))
				or String(background.get("mode", "")) != "live_town_frame"
			):
				issues.append("正式页面 background.mode 必须为 live_town_frame")
			for boolean_key: String in [
				"available",
				"dimmed",
				"focusVisible",
			]:
				if typeof(background.get(boolean_key, false)) != TYPE_BOOL:
					issues.append(
						"background.%s 必须为布尔值" % boolean_key
					)
				elif not bool(background.get(boolean_key, false)):
					issues.append(
						"正式可见页面 background.%s 必须为 true"
						% boolean_key
					)
		var content_value: Variant = data.get("content", {})
		if typeof(content_value) != TYPE_DICTIONARY:
			issues.append("content 必须为 Dictionary")
		else:
			var content := content_value as Dictionary
			if phase == "failed" and not content.is_empty():
				issues.append("failed 不得渲染编造的居民内心内容")
			if phase != "failed":
				for text_key: String in [
					"contentKind",
					"monologueText",
					"reasonText",
					"playerStatusText",
				]:
					if not _is_text_value(content.get(text_key, "")):
						issues.append("content.%s 必须为字符串" % text_key)
				if (
					not _is_text_value(content.get("contentKind", ""))
					or String(
						content.get("contentKind", "")
					) != "resident_current_focus"
				):
					issues.append(
						"contentKind 必须为 resident_current_focus"
					)
				if (
					not content.has("empty")
					or typeof(content.get("empty")) != TYPE_BOOL
				):
					issues.append("content.empty 必须为布尔值")
			var monologue_text := String(
				content.get("monologueText", "")
			).strip_edges()
			var reason_text := String(
				content.get("reasonText", "")
			).strip_edges()
			var player_status_text := String(
				content.get("playerStatusText", "")
			).strip_edges()
			var content_empty := bool(content.get("empty", false))
			if (
				not player_status_text.is_empty()
				and not content_empty
				and not _status_text_fits_stable_profile(player_status_text)
			):
				issues.append(
					"content.playerStatusText 超出稳定状态槽，必须提供完整短句"
				)
			if phase == "ready":
				if content_empty and not monologue_text.is_empty():
					issues.append("empty ready 不得提供虚构的当前关注")
				elif not content_empty and monologue_text.is_empty():
					issues.append("非空 ready 必须提供真实 current_focus")
				if (
					content_empty
					and not reason_text.is_empty()
				):
					issues.append("empty ready 只显示玩家可读自然空状态")
				if content_empty and player_status_text.is_empty():
					issues.append("empty ready 必须提供玩家可读自然空状态")
			if (
				phase == "ready"
				and content.has("fallbackUsed")
				and bool(content.get("fallbackUsed", false))
			):
				issues.append("ready 不得标记 fallbackUsed")
			if (
				phase in ["opening", "generating", "closing"]
				and player_status_text.is_empty()
			):
				issues.append("%s 必须提供玩家可读状态短句" % phase)
			if (
				phase != "failed"
				and content.has("fallbackUsed")
				and typeof(content.get("fallbackUsed")) != TYPE_BOOL
			):
				issues.append("content.fallbackUsed 必须为布尔值")
		var resident_value: Variant = data.get("resident", {})
		if typeof(resident_value) != TYPE_DICTIONARY:
			issues.append("resident 必须为 Dictionary")
		else:
			var resident := resident_value as Dictionary
			for text_key: String in [
				"residentId",
				"displayName",
				"expressionId",
			]:
				if not _is_text_value(resident.get(text_key, "")):
					issues.append("resident.%s 必须为字符串" % text_key)
			if (
				not _is_text_value(resident.get("residentId", ""))
				or String(
					resident.get("residentId", "")
				).strip_edges().is_empty()
			):
				issues.append("resident.residentId 不能为空")
			if (
				not _is_text_value(resident.get("displayName", ""))
				or String(
					resident.get("displayName", "")
				).strip_edges().is_empty()
			):
				issues.append("resident.displayName 不能为空")
			if (
				not _is_text_value(resident.get("expressionId", ""))
				or not VALID_EXPRESSION_IDS.has(
					String(resident.get("expressionId", ""))
				)
			):
				issues.append("resident.expressionId 无效")
			issues.append_array(
				_validate_portrait_contract(
					resident.get("portrait", null)
				)
			)
		var generation_value: Variant = data.get("generation", {})
		if typeof(generation_value) != TYPE_DICTIONARY:
			issues.append("generation 必须为 Dictionary")
		else:
			var generation := generation_value as Dictionary
			if not _is_text_value(generation.get("status", "")):
				issues.append("generation.status 必须为字符串")
			elif not VALID_GENERATION_STATUSES.has(
				String(generation.get("status", ""))
			):
				issues.append("generation.status 无效")
			else:
				generation_status = String(generation.get("status", ""))
			if not _is_text_value(generation.get("requestId", "")):
				issues.append("generation.requestId 必须为字符串")
			elif (
				phase != "opening"
				and String(
					generation.get("requestId", "")
				).strip_edges().is_empty()
			):
				issues.append("可见页面 generation.requestId 不能为空")
			if typeof(generation.get("retryable", false)) != TYPE_BOOL:
				issues.append("generation.retryable 必须为布尔值")
			else:
				generation_retryable = bool(
					generation.get("retryable", false)
				)
			var generation_matches_phase := (
				(phase == "opening"
					and generation_status in ["idle", "generating"])
				or (phase == "generating"
					and generation_status == "generating")
					or (phase == "ready"
						and generation_status == "ready")
					or (phase == "failed"
						and generation_status == "error")
				or phase == "closing"
			)
			if not generation_matches_phase:
				issues.append("generation.status 与 phase 不一致")
		var motion_value: Variant = data.get("motion", {})
		if typeof(motion_value) != TYPE_DICTIONARY:
			issues.append("motion 必须为 Dictionary")
		elif typeof(
			(motion_value as Dictionary).get("reduceMotion", false)
		) != TYPE_BOOL:
			issues.append("motion.reduceMotion 必须为布尔值")
	for action_key: String in ["exit", "retry"]:
		var expected_intent := (
			String(EXIT_INTENT)
			if action_key == "exit"
			else String(RETRY_INTENT)
		)
		var action := UiViewModel.action(view_model, action_key)
		if action.is_empty():
			issues.append("actions.%s 缺失" % action_key)
			continue
		if (
			not _is_text_value(action.get("intent", ""))
			or String(action.get("intent", "")) != expected_intent
		):
			issues.append("actions.%s.intent 无效" % action_key)
		if typeof(action.get("enabled", false)) != TYPE_BOOL:
			issues.append("actions.%s.enabled 必须为布尔值" % action_key)
		if not _is_text_value(action.get("disabledReason", "")):
			issues.append(
				"actions.%s.disabledReason 必须为字符串" % action_key
			)
	if visibility == "visible":
		var exit_action := UiViewModel.action(view_model, "exit")
		var expected_exit_enabled := phase != "closing"
		if (
			not exit_action.is_empty()
			and bool(exit_action.get("enabled", false))
			!= expected_exit_enabled
		):
			issues.append("actions.exit.enabled 与 phase 不一致")
		var retry_action := UiViewModel.action(view_model, "retry")
		var expected_retry_enabled := (
			phase == "failed" and generation_retryable
		)
		if (
			not retry_action.is_empty()
			and bool(retry_action.get("enabled", false))
			!= expected_retry_enabled
		):
			issues.append("actions.retry.enabled 与回退状态不一致")
	return issues


func _validate_portrait_contract(
	portrait_value: Variant
) -> PackedStringArray:
	var issues := PackedStringArray()
	if typeof(portrait_value) != TYPE_DICTIONARY:
		issues.append("resident.portrait 必须为 Dictionary")
		return issues
	var portrait := portrait_value as Dictionary
	for text_key: String in ["assetPath", "sourceKind", "status"]:
		if not _is_text_value(portrait.get(text_key, "")):
			issues.append("resident.portrait.%s 必须为字符串" % text_key)
	var source_kind := String(portrait.get("sourceKind", ""))
	if not VALID_PORTRAIT_SOURCE_KINDS.has(source_kind):
		issues.append("resident.portrait.sourceKind 无效")
	var portrait_status := String(portrait.get("status", ""))
	if not VALID_PORTRAIT_STATUSES.has(portrait_status):
		issues.append("resident.portrait.status 无效")
	var asset_path := String(portrait.get("assetPath", ""))
	if (
		not asset_path.is_empty()
		and (
			not asset_path.begins_with("res://assets/")
			or asset_path.contains("..")
		)
	):
		issues.append("resident.portrait.assetPath 必须位于 res://assets/")
	if portrait_status == "ready" and asset_path.is_empty():
		issues.append("ready portrait 必须提供 assetPath")
	var region_value: Variant = portrait.get("atlasRegion", {})
	if typeof(region_value) != TYPE_DICTIONARY:
		issues.append("resident.portrait.atlasRegion 必须为 Dictionary")
		return issues
	var region := region_value as Dictionary
	for field: String in ["x", "y", "width", "height"]:
		var field_value: Variant = region.get(field, 0)
		if typeof(field_value) not in [TYPE_INT, TYPE_FLOAT]:
			issues.append(
				"resident.portrait.atlasRegion.%s 必须为数字" % field
			)
	return issues


func _is_text_value(value: Variant) -> bool:
	return typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]


func _status_text_fits_stable_profile(text_value: String) -> bool:
	if _compact_font == null:
		return false
	var measured_width := _compact_font.get_string_size(
		text_value,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		BODY_FONT_SIZE
	).x
	return measured_width <= STABLE_1280_STATUS_RECT.size.x


func _find_banned_render_key(value: Variant, path: String) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary := value as Dictionary
		for key_value: Variant in dictionary:
			var key := String(key_value)
			var next_path := "%s.%s" % [path, key]
			if BANNED_RENDER_KEY_TOKENS.has(_normalize_render_key(key)):
				return next_path
			var nested := _find_banned_render_key(dictionary[key_value], next_path)
			if not nested.is_empty():
				return nested
	elif typeof(value) == TYPE_ARRAY:
		var array := value as Array
		for index: int in array.size():
			var nested := _find_banned_render_key(
				array[index],
				"%s[%d]" % [path, index]
			)
			if not nested.is_empty():
				return nested
	return ""


func _normalize_render_key(key: String) -> String:
	return (
		key.to_lower()
		.replace("_", "")
		.replace("-", "")
		.replace(" ", "")
	)

func _reject_snapshot(reason: String, revision: int) -> void:
	snapshot_rejected.emit(reason, revision)


func _record_closed_session(request_id: String, revision: int) -> void:
	if not _active_generation_request_id.is_empty():
		_seal_closed_request(_active_generation_request_id)
	if not request_id.is_empty():
		_seal_closed_request(request_id)
	_closed_at_revision = maxi(_closed_at_revision, revision)
	_active_generation_request_id = ""
	_active_resident_id = ""
	_exit_pending = false
	_pending_action_keys.clear()


func _release_completed_action(view_model: Dictionary) -> void:
	var operation := view_model.get("operation", {}) as Dictionary
	var operation_status := String(operation.get("status", "idle"))
	if operation_status in ["success", "rejected", "error", "disabled"]:
		var operation_intent := String(operation.get("intent", ""))
		if not operation_intent.is_empty():
			_pending_action_keys.erase(operation_intent)
		if operation_intent == String(EXIT_INTENT) and operation_status != "success":
			_exit_pending = false
			if not _active_generation_request_id.is_empty():
				_closed_request_ids.erase(_active_generation_request_id)
				_closed_request_order.erase(
					_active_generation_request_id
				)


func _seal_closed_request(request_id: String) -> void:
	if request_id.is_empty() or _closed_request_ids.has(request_id):
		return
	_closed_request_ids[request_id] = true
	_closed_request_order.append(request_id)
	while _closed_request_order.size() > CLOSED_REQUEST_HISTORY_LIMIT:
		var expired_request_id: String = String(
			_closed_request_order.pop_front()
		)
		_closed_request_ids.erase(expired_request_id)


func _apply_render_data() -> void:
	var visibility := String(_render_data.get("visibility", "hidden"))
	if visibility != "visible":
		_hide_without_input()
		return
	visible = true
	set_process_unhandled_input(true)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var background := _render_data.get("background", {}) as Dictionary
	_dimmer.visible = bool(background.get("dimmed", true))
	_focus_glow.visible = bool(background.get("focusVisible", true))

	var resident := _render_data.get("resident", {}) as Dictionary
	var content := _render_data.get("content", {}) as Dictionary
	_whisper.text = INNER_SECTION_TITLE
	_whisper.tooltip_text = _whisper.text
	_whisper.mouse_filter = Control.MOUSE_FILTER_STOP
	_resident_name.text = String(resident.get("displayName", ""))
	_portrait_fallback.text = _resident_name.text
	_apply_portrait(resident.get("portrait", {}) as Dictionary)
	_apply_action_state()
	_update_layout()
	_render_focus_content(content)
	_focus_render_default()


func _apply_portrait(portrait_data: Dictionary) -> void:
	_portrait.texture = null
	var path := String(portrait_data.get("assetPath", ""))
	var status_value := String(portrait_data.get("status", "missing"))
	if status_value == "ready" and not path.is_empty():
		var loaded := ResourceLoader.load(path, "Texture2D") as Texture2D
		if loaded != null:
			var region_value: Variant = portrait_data.get("atlasRegion", {})
			if typeof(region_value) == TYPE_DICTIONARY:
				var region_data := region_value as Dictionary
				var region := Rect2(
					float(region_data.get("x", 0)),
					float(region_data.get("y", 0)),
					float(region_data.get("width", 0)),
					float(region_data.get("height", 0))
				)
				if region.size.x > 0.0 and region.size.y > 0.0:
					var atlas := AtlasTexture.new()
					atlas.atlas = loaded
					atlas.region = region
					_portrait.texture = atlas
				else:
					_portrait.texture = loaded
			else:
				_portrait.texture = loaded
	_portrait.visible = _portrait.texture != null
	_portrait_fallback.visible = not _portrait.visible


func _apply_action_state() -> void:
	var exit_action := _actions.get("exit", {}) as Dictionary
	var retry_action := _actions.get("retry", {}) as Dictionary
	_exit.visible = true
	_exit.disabled = (
		_exit_pending
		or not UiViewModel.action_enabled(exit_action)
	)
	var generation := _render_data.get("generation", {}) as Dictionary
	var retryable := bool(generation.get("retryable", false))
	var error_value: Variant = _snapshot.get("error", null)
	if typeof(error_value) == TYPE_DICTIONARY:
		retryable = retryable or bool(
			(error_value as Dictionary).get("retryable", false)
		)
	_retry.visible = retryable and UiViewModel.action_enabled(retry_action)
	_retry.disabled = (
		_pending_action_keys.has(String(RETRY_INTENT))
		or not UiViewModel.action_enabled(retry_action)
	)


func _render_focus_content(content: Dictionary) -> void:
	if bool(content.get("empty", false)):
		_monologue.text = String(content.get("playerStatusText", ""))
		_monologue.tooltip_text = _monologue.text
		_reason.text = ""
		_reason.tooltip_text = ""
		_reason.visible = false
		_status.visible = false
		_fit_label_text(
			_monologue,
			_body_font,
			BODY_FONT_SIZE,
			MONOLOGUE_MIN_FONT_SIZE,
			_last_layout.get("monologue", REFERENCE_MONOLOGUE_RECT) as Rect2,
		)
		return
	var monologue_text := String(content.get("monologueText", "")).strip_edges()
	var reason_text := String(content.get("reasonText", "")).strip_edges()
	var phase := String(_render_data.get("phase", ""))
	_monologue.text = (
		"“%s”" % monologue_text
		if phase == "ready" and not monologue_text.is_empty()
		else monologue_text
	)
	_monologue.tooltip_text = monologue_text
	_reason.visible = not reason_text.is_empty()
	_reason.text = (
		"为什么会这样想\n%s" % reason_text
		if _reason.visible
		else ""
	)
	_reason.tooltip_text = reason_text
	var player_status := _player_status_text()
	_status.visible = not player_status.is_empty()
	_status.text = player_status
	_fit_label_text(
		_monologue,
		_body_font,
		BODY_FONT_SIZE,
		MONOLOGUE_MIN_FONT_SIZE,
		_last_layout.get("monologue", REFERENCE_MONOLOGUE_RECT) as Rect2,
	)
	if _reason.visible:
		_fit_label_text(
			_reason,
			_reason_font,
			BODY_FONT_SIZE,
			REASON_MIN_FONT_SIZE,
			_last_layout.get("reason", REFERENCE_REASON_RECT) as Rect2,
		)


func _fit_label_text(
	label: Label,
	font: Font,
	preferred_size: int,
	minimum_size: int,
	target_rect: Rect2,
) -> void:
	var available_width := maxf(1.0, target_rect.size.x)
	var available_height := maxf(1.0, target_rect.size.y)
	var selected_size := minimum_size
	for candidate_size: int in range(preferred_size, minimum_size - 1, -1):
		var measured := font.get_multiline_string_size(
			label.text,
			HORIZONTAL_ALIGNMENT_LEFT,
			available_width,
			candidate_size,
			-1,
		)
		if measured.y <= available_height:
			selected_size = candidate_size
			break
	label.add_theme_font_size_override("font_size", selected_size)


func _player_status_text() -> String:
	var operation_status := String(
		(_snapshot.get("operation", {}) as Dictionary).get(
			"status",
			"idle"
		)
	)
	if operation_status == "rejected":
		return PLAYER_SAFE_REJECTED_FALLBACK
	if operation_status == "disabled":
		return PLAYER_SAFE_DISABLED_FALLBACK
	var content := _render_data.get("content", {}) as Dictionary
	var player_status := String(content.get("playerStatusText", ""))
	if not player_status.is_empty():
		return player_status
	if String(_render_data.get("phase", "")) == "failed":
		var error_value: Variant = _snapshot.get("error", null)
		var retryable := (
			error_value is Dictionary
			and bool((error_value as Dictionary).get("retryable", false))
		)
		return (
			PLAYER_SAFE_RETRYABLE_ERROR_FALLBACK
			if retryable
			else PLAYER_SAFE_FINAL_ERROR_FALLBACK
		)
	return ""


func _focus_render_default() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == _retry and _retry.visible and not _retry.disabled:
		return
	if focus_owner == _exit and _exit.visible and not _exit.disabled:
		return
	_focus_exit_if_available()


func _focus_exit_if_available() -> void:
	if _exit.visible and not _exit.disabled:
		_exit.grab_focus()


func _submit_action(action_key: String, expected_intent: StringName) -> bool:
	if not visible:
		action_blocked.emit(expected_intent, "page_hidden", _highest_seen_revision)
		return false
	var action_value: Variant = _actions.get(action_key, {})
	if typeof(action_value) != TYPE_DICTIONARY:
		action_blocked.emit(expected_intent, "action_missing", _highest_seen_revision)
		return false
	var action := action_value as Dictionary
	var intent := StringName(action.get("intent", ""))
	if intent != expected_intent:
		action_blocked.emit(expected_intent, "intent_mismatch", _highest_seen_revision)
		return false
	if not UiViewModel.action_enabled(action):
		action_blocked.emit(
			expected_intent,
			UiViewModel.disabled_reason(action),
			_highest_seen_revision
		)
		return false
	var dedupe_key := String(intent)
	if _pending_action_keys.has(dedupe_key):
		action_blocked.emit(expected_intent, "duplicate_request", _highest_seen_revision)
		return false
	var payload_value: Variant = action.get("payload", {})
	var payload: Dictionary = (
		(payload_value as Dictionary).duplicate(true)
		if typeof(payload_value) == TYPE_DICTIONARY
		else {}
	)
	payload["revision"] = _highest_seen_revision
	payload["residentId"] = _active_resident_id
	payload["generationRequestId"] = _active_generation_request_id
	var request_id := String(action.get("requestId", ""))
	if request_id.is_empty():
		request_id = "%s:%d:%s" % [
			dedupe_key,
			_highest_seen_revision,
			_active_generation_request_id,
		]
	payload["requestId"] = request_id
	_pending_action_keys[dedupe_key] = request_id
	if intent == EXIT_INTENT:
		_exit_pending = true
		_exit.disabled = true
		if not _active_generation_request_id.is_empty():
			_seal_closed_request(_active_generation_request_id)
	intent_requested.emit(
		intent,
		payload.duplicate(true),
		_highest_seen_revision,
		request_id
	)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		request_exit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()


func _on_resized() -> void:
	if String(_render_data.get("visibility", "hidden")) != "visible":
		return
	_update_layout()
	var content := _render_data.get("content", {}) as Dictionary
	_render_focus_content(content)


func _update_layout() -> void:
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	_update_layout_for_viewport(viewport_size)


func _update_layout_for_viewport(viewport_size: Vector2) -> void:
	var layout := _layout_for_viewport(viewport_size)
	_layout_profile = String(layout.get("profile", "unknown"))
	_last_layout = (layout.get("rects", {}) as Dictionary).duplicate(true)
	if _last_layout.is_empty():
		if String(_render_data.get("visibility", "hidden")) == "visible":
			visible = true
			set_process_unhandled_input(true)
			mouse_filter = Control.MOUSE_FILTER_STOP
			request_exit()
		else:
			_hide_without_input()
		return
	if String(_render_data.get("visibility", "hidden")) == "visible":
		visible = true
		set_process_unhandled_input(true)
	_apply_stable_runtime_assets(_layout_profile)
	_apply_rect(_focus_glow, _last_layout["focusGlow"] as Rect2)
	_apply_rect(_portrait_frame, _last_layout["portraitFrame"] as Rect2)
	_apply_rect(_portrait, _last_layout["portrait"] as Rect2)
	_apply_rect(_portrait_fallback, _last_layout["portrait"] as Rect2)
	_apply_rect(_panel, _last_layout["panel"] as Rect2)
	_apply_rect(_whisper, _last_layout["whisper"] as Rect2)
	_apply_rect(_resident_name, _last_layout["name"] as Rect2)
	_apply_rect(_monologue, _last_layout["monologue"] as Rect2)
	_apply_rect(_reason, _last_layout["reason"] as Rect2)
	_apply_rect(_status, _last_layout["status"] as Rect2)
	_apply_rect(_retry, _last_layout["retry"] as Rect2)
	_apply_rect(_exit, _last_layout["exit"] as Rect2)
	_safe_overlay.set_rects(_last_layout)
	_safe_overlay.visible = _safe_debug_enabled and visible


func _layout_for_viewport(viewport_size: Vector2) -> Dictionary:
	var physical_size := Vector2i(
		roundi(viewport_size.x),
		roundi(viewport_size.y)
	)
	if physical_size.x >= 1920 and physical_size.y >= 1080:
		return _reference_layout(viewport_size)
	if physical_size.x >= 1280 and physical_size.y >= 720:
		return _stable_1280_layout(viewport_size)
	return _scaled_1280_layout(viewport_size)


func _reference_layout(viewport_size: Vector2) -> Dictionary:
	var offset := Vector2(
		floor((viewport_size.x - REFERENCE_VIEWPORT.x) * 0.5),
		floor((viewport_size.y - REFERENCE_VIEWPORT.y) * 0.5)
	)
	var global_inset := 48.0
	var rects := {
		"globalSafe": Rect2(
			global_inset,
			global_inset,
			viewport_size.x - global_inset * 2.0,
			viewport_size.y - global_inset * 2.0
		),
		"panel": _translated_rect(REFERENCE_PANEL_RECT, offset),
		"portraitFrame": _translated_rect(
			REFERENCE_PORTRAIT_FRAME_RECT,
			offset
		),
		"portrait": _translated_rect(REFERENCE_PORTRAIT_RECT, offset),
		"whisper": _translated_rect(REFERENCE_WHISPER_RECT, offset),
		"name": _translated_rect(REFERENCE_NAME_RECT, offset),
		"monologue": _translated_rect(REFERENCE_MONOLOGUE_RECT, offset),
		"reason": _translated_rect(REFERENCE_REASON_RECT, offset),
		"status": _translated_rect(REFERENCE_STATUS_RECT, offset),
		"retry": _translated_rect(REFERENCE_RETRY_RECT, offset),
		"exit": _translated_rect(REFERENCE_EXIT_RECT, offset),
	}
	var portrait_frame := rects["portraitFrame"] as Rect2
	rects["focusGlow"] = portrait_frame.grow(22.0)
	return {
		"profile": "stable_1920x1080",
		"rects": _snap_rects(rects),
	}


func _stable_1280_layout(
	viewport_size: Vector2 = Vector2(1280, 720)
) -> Dictionary:
	var offset := Vector2(
		floor((viewport_size.x - 1280.0) * 0.5),
		floor((viewport_size.y - 720.0) * 0.5)
	)
	var rects := {
		"globalSafe": Rect2(
			24,
			24,
			viewport_size.x - 48.0,
			viewport_size.y - 48.0
		),
		"panel": _translated_rect(STABLE_1280_PANEL_RECT, offset),
		"portraitFrame": _translated_rect(
			STABLE_1280_PORTRAIT_FRAME_RECT,
			offset
		),
		"portrait": _translated_rect(STABLE_1280_PORTRAIT_RECT, offset),
		"focusGlow": _translated_rect(
			STABLE_1280_PORTRAIT_FRAME_RECT.grow(12.0),
			offset
		),
		"whisper": _translated_rect(STABLE_1280_WHISPER_RECT, offset),
		"name": _translated_rect(STABLE_1280_NAME_RECT, offset),
		"monologue": _translated_rect(STABLE_1280_MONOLOGUE_RECT, offset),
		"reason": _translated_rect(STABLE_1280_REASON_RECT, offset),
		"status": _translated_rect(STABLE_1280_STATUS_RECT, offset),
		"retry": _translated_rect(STABLE_1280_RETRY_RECT, offset),
			"exit": _translated_rect(
				STABLE_1280_EXIT_WITH_RETRY_RECT
				if _retry != null and _retry.visible
				else STABLE_1280_EXIT_RECT,
				offset,
			),
	}
	return {
		"profile": "stable_1280x720",
		"rects": _snap_rects(rects),
	}


func _scaled_1280_layout(viewport_size: Vector2) -> Dictionary:
	var base := _stable_1280_layout(Vector2(1280, 720))
	var base_rects := base.get("rects", {}) as Dictionary
	var scale_factor := minf(
		viewport_size.x / 1280.0,
		viewport_size.y / 720.0,
	)
	var offset := (
		viewport_size - Vector2(1280, 720) * scale_factor
	) * 0.5
	var rects := {}
	for key: String in base_rects:
		var rect := base_rects[key] as Rect2
		rects[key] = Rect2(
			offset + rect.position * scale_factor,
			rect.size * scale_factor,
		)
	return {
		"profile": "stable_1280x720",
		"rects": _snap_rects(rects),
	}


func _apply_stable_runtime_assets(profile_id: String) -> void:
	if not STABLE_RUNTIME_ASSETS.has(profile_id):
		_panel.texture = null
		_portrait_frame.texture = null
		return
	var assets := STABLE_RUNTIME_ASSETS[profile_id] as Dictionary
	var panel_path := String(assets.get("panel", ""))
	var portrait_path := String(assets.get("portraitFrame", ""))
	_panel.texture = ResourceLoader.load(panel_path, "Texture2D") as Texture2D
	_portrait_frame.texture = ResourceLoader.load(
		portrait_path,
		"Texture2D"
	) as Texture2D


func _snap_rects(rects: Dictionary) -> Dictionary:
	var snapped := {}
	for key: String in rects:
		var rect := rects[key] as Rect2
		snapped[key] = Rect2(
			floor(rect.position.x),
			floor(rect.position.y),
			floor(rect.size.x),
			floor(rect.size.y)
		)
	return snapped


func _translated_rect(rect: Rect2, offset: Vector2) -> Rect2:
	return Rect2(rect.position + offset, rect.size)


func _apply_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


func _hide_without_input() -> void:
	visible = false
	set_process_unhandled_input(false)
	if _safe_overlay != null:
		_safe_overlay.visible = false


func _rect_dictionary_payload(rects: Dictionary) -> Dictionary:
	var payload := {}
	for key: String in rects:
		var value: Variant = rects[key]
		if typeof(value) != TYPE_RECT2:
			continue
		var rect := value as Rect2
		payload[key] = {
			"x": rect.position.x,
			"y": rect.position.y,
			"width": rect.size.x,
			"height": rect.size.y,
		}
	return payload
