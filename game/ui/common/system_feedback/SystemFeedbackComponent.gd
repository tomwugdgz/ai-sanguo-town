class_name SystemFeedbackComponent
extends Control


signal action_requested(action_key: StringName)
signal dismiss_requested

const ViewModel := preload(
	"res://ui/common/AiTownUiViewModel.gd"
)
const UiNodeRetirement := preload("res://ui/common/AiTownUiNodeRetirement.gd")
const THEME_PATH := (
	"res://ui/common/system_feedback/SystemFeedbackTheme.tres"
)
const BASE_PANEL_TEXTURE_PATH := (
	"res://assets/ui/common/system_feedback/runtime_panel_v3/"
	+ "system_feedback_panel_base_1024x512.png"
)
const PLACEHOLDER_PANEL_TEXTURE_PATH := (
	"res://assets/ui/common/system_feedback/runtime_strip_v3/"
	+ "system_feedback_strip_base_1024x96.png"
)
const TOAST_TEXTURE_PATH := (
	"res://assets/ui/common/system_feedback/runtime_toast_v3/"
	+ "system_feedback_toast_base_1024x256.png"
)
const STRIP_TEXTURE_PATH := (
	"res://assets/ui/common/system_feedback/runtime_strip_v3/"
	+ "system_feedback_strip_base_1024x96.png"
)
const INPUT_FRAME_TEXTURE_PATH := (
	"res://assets/ui/common/formal_dialog_v1/runtime/"
	+ "formal_dialog_input_frame_v1_1024x192.png"
)
const ERROR_ICON_TEXTURE_PATH := (
	"res://assets/ui/common/formal_dialog_v1/runtime/"
	+ "formal_dialog_error_icon_v1_128x128.png"
)
const ICON_ROOT := (
	"res://assets/ui/common/system_feedback/icons/"
)
const SEMANTIC_ICON_SIZE := 40.0
const COMPACT_ICON_SIZE := 36.0
const VALIDATION_ICON_SIZE := 32.0
const PLACEHOLDER_ICON_SIZE := 64.0
const ICON_PATHS := {
	"success": ICON_ROOT + "success.svg",
	"warning": ICON_ROOT + "warning.svg",
	"error": ERROR_ICON_TEXTURE_PATH,
	"info": ICON_ROOT + "info.svg",
	"close": ICON_ROOT + "close.svg",
	"loading": ICON_ROOT + "loading.svg",
	"disabled": ICON_ROOT + "disabled.svg",
	"missing_asset": ICON_ROOT + "missing_asset.svg",
	"target_unreachable": ICON_ROOT + "target_unreachable.svg",
}
const TONE_COLORS := {
	"success": Color("#557b2a"),
	"warning": Color("#e5a84b"),
	"error": Color("#a7352b"),
	"info": Color("#4f7790"),
}
const ACTION_LABELS := {
	"retry": "重试",
	"end": "结束",
	"dismiss": "关闭",
	"confirm": "确认",
	"cancel": "取消",
	"continueEditing": "继续编辑",
	"publish": "发布",
	"discard": "放弃",
	"openSettings": "设置",
	"continueObserving": "继续观察",
	"selectTarget": "重选目标",
	"newGame": "进入小镇",
	"create": "创建存档",
	"continue": "继续",
}

@export_enum(
	"auto",
	"dialog",
	"toast",
	"loading_overlay",
	"disabled_reason",
	"validation",
	"asset_placeholder",
	"map_anchor"
)
var surface_kind := "auto"
@export var expanded := false
@export var reduced_motion := false

var _theme: Theme
var _frame: NinePatchRect
var _tone_bar: ColorRect
var _icon: TextureRect
var _title: Label
var _body: Label
var _compact: Label
var _progress: ProgressBar
var _actions: GridContainer
var _close: Button
var _field_surface: NinePatchRect
var _field_value: Label
var _counter: Label
var _current_surface := "toast"
var _feedback: Dictionary = {}
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _revision := -1
var _previous_focus: Control
var _loading_elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_ensure_nodes()
	_layout()


func _process(delta: float) -> void:
	if (
		reduced_motion
		or _icon == null
		or _current_surface != "loading_overlay"
	):
		return
	_loading_elapsed += delta
	var quarter_turn := int(floor(_loading_elapsed * 4.0)) % 4
	_icon.rotation = float(quarter_turn) * PI * 0.5


func configure(
	view_model: Dictionary,
	surface_override: String = surface_kind
) -> PackedStringArray:
	_ensure_nodes()
	var issues := ViewModel.validate(
		view_model,
		"SystemFeedbackComponent"
	)
	if not issues.is_empty():
		return issues
	if not ViewModel.accepts_revision(_revision, view_model):
		return PackedStringArray([
			"SystemFeedbackComponent 收到过期 revision"
		])
	var incoming_data := ViewModel.data(view_model)
	var operation_status := ViewModel.operation_status(view_model)
	_render_data = ViewModel.data_for_render(
		view_model,
		_last_confirmed_data
	)
	if (
		not incoming_data.is_empty()
		and operation_status in [&"idle", &"success"]
	):
		_last_confirmed_data = incoming_data.duplicate(true)
	var feedback_value: Variant = _render_data.get("feedback", null)
	if typeof(feedback_value) != TYPE_DICTIONARY:
		return PackedStringArray([
			"SystemFeedbackComponent.data.feedback 必须是 Dictionary"
		])
	_feedback = (feedback_value as Dictionary).duplicate(true)
	_view_model = view_model.duplicate(true)
	_revision = ViewModel.revision(view_model)
	_current_surface = (
		surface_override
		if surface_override != "auto"
		else _resolve_surface(_feedback)
	)
	if not [
		"dialog",
		"toast",
		"loading_overlay",
		"disabled_reason",
		"validation",
		"asset_placeholder",
		"map_anchor",
	].has(_current_surface):
		return PackedStringArray([
			"SystemFeedbackComponent 组件类型无效：" + _current_surface
		])
	if bool(_feedback.get("blocking", false)):
		_previous_focus = get_viewport().gui_get_focus_owner()
	_apply_content()
	_layout()
	_focus_safe_action.call_deferred()
	return PackedStringArray()


func dedupe_identity() -> String:
	var feedback_id := str(_feedback.get("feedbackId", ""))
	if not feedback_id.is_empty():
		return feedback_id
	return (
		str(_view_model.get("scope", ""))
		+ "|"
		+ ViewModel.operation_request_id(_view_model)
		+ "|"
		+ str(ViewModel.operation_status(_view_model))
	)


func restore_previous_focus() -> void:
	if is_instance_valid(_previous_focus):
		_previous_focus.grab_focus()


func _ensure_nodes() -> void:
	if _frame != null:
		return
	_theme = ResourceLoader.load(THEME_PATH, "Theme") as Theme
	if _theme == null:
		push_error("SystemFeedbackComponent 无法加载公共 Theme")
		return
	theme = _theme
	_frame = NinePatchRect.new()
	_frame.name = "NinePatchFrame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_tone_bar = ColorRect.new()
	_tone_bar.name = "SemanticToneBar"
	_tone_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tone_bar)
	_icon = TextureRect.new()
	_icon.name = "SemanticIcon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_title = _make_label("Title", "FeedbackDialogTitle")
	_body = _make_label("Body", "FeedbackBody")
	_compact = _make_label("Compact", "FeedbackCompact")
	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress)
	_actions = GridContainer.new()
	_actions.name = "Actions"
	_actions.columns = 3
	_actions.add_theme_constant_override("h_separation", 16)
	_actions.add_theme_constant_override("v_separation", 12)
	add_child(_actions)
	_close = Button.new()
	_close.name = "Close"
	_close.custom_minimum_size = Vector2(48, 48)
	_close.icon = _load_icon("close")
	_close.expand_icon = true
	_close.add_theme_constant_override("icon_max_width", 32)
	_close.focus_mode = Control.FOCUS_ALL
	_close.theme_type_variation = &"FeedbackIconButton"
	_close.pressed.connect(_on_close_pressed)
	add_child(_close)
	_field_surface = NinePatchRect.new()
	_field_surface.name = "FieldSurface"
	_field_surface.texture = ResourceLoader.load(
		INPUT_FRAME_TEXTURE_PATH,
		"Texture2D"
	) as Texture2D
	_field_surface.patch_margin_left = 52
	_field_surface.patch_margin_top = 48
	_field_surface.patch_margin_right = 52
	_field_surface.patch_margin_bottom = 48
	_field_surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_field_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_field_surface)
	_field_value = _make_label(
		"FieldValue",
		"FeedbackCompact"
	)
	_counter = _make_label("Counter", "FeedbackCompactError")


func _make_label(node_name: String, variation: StringName) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(label)
	return label


func _resolve_surface(feedback: Dictionary) -> String:
	var component := str(feedback.get("component", ""))
	var anchor := str(feedback.get("anchor", ""))
	if component == "toast" and anchor == "map_target":
		return "map_anchor"
	match component:
		"confirmation_dialog", "error_dialog":
			return "dialog"
		"toast":
			return "toast"
		"loading_overlay":
			return "loading_overlay"
		"disabled_reason":
			return "disabled_reason"
		"input_validation":
			return "validation"
		"asset_placeholder":
			return "asset_placeholder"
		_:
			return component


func _apply_content() -> void:
	var tone := str(_feedback.get("tone", "info"))
	var icon_id := tone
	match _current_surface:
		"loading_overlay":
			icon_id = "loading"
		"disabled_reason":
			icon_id = "disabled"
		"validation":
			icon_id = "error"
		"asset_placeholder":
			icon_id = "missing_asset"
		"map_anchor":
			icon_id = "target_unreachable"
	_icon.texture = _load_icon(icon_id)
	_icon.pivot_offset = _icon.size * 0.5
	_icon.rotation = 0.0
	_tone_bar.color = TONE_COLORS.get(
		tone,
		TONE_COLORS["info"]
	)
	_title.text = str(_feedback.get("title", ""))
	_body.text = str(_feedback.get("message", ""))
	_compact.text = (
		str(_feedback.get("title", ""))
		if not str(_feedback.get("title", "")).is_empty()
		else str(_feedback.get("message", ""))
	)
	_progress.value = (
		clampf(float(_feedback.get("progress", 0.0)), 0.0, 1.0)
		* 100.0
	)
	_field_value.text = str(_render_data.get("draft", ""))
	var count_value: Variant = _render_data.get(
		"characterCount",
		null
	)
	var limit_value: Variant = _render_data.get(
		"characterLimit",
		null
	)
	_counter.text = (
		"%d / %d" % [int(count_value), int(limit_value)]
		if (
			typeof(count_value) in [TYPE_INT, TYPE_FLOAT]
			and typeof(limit_value) in [TYPE_INT, TYPE_FLOAT]
		)
		else ""
	)
	_configure_actions()


func _configure_actions() -> void:
	UiNodeRetirement.retire_children(_actions)
	var actions: Dictionary = _view_model.get("actions", {})
	var retryable := false
	var error_value: Variant = _view_model.get("error", null)
	if typeof(error_value) == TYPE_DICTIONARY:
		retryable = bool((error_value as Dictionary).get(
			"retryable",
			false
		))
	var keys: Array[String] = []
	for key: String in actions:
		if _current_surface == "loading_overlay" and key != "cancel":
			continue
		if key == "retry" and not retryable:
			continue
		keys.append(key)
	var order := [
		"retry",
		"confirm",
		"publish",
		"openSettings",
		"continueEditing",
		"continueObserving",
		"selectTarget",
		"cancel",
		"end",
		"discard",
		"dismiss",
	]
	keys.sort_custom(func(left: String, right: String) -> bool:
		var left_index := order.find(left)
		var right_index := order.find(right)
		if left_index < 0:
			left_index = 999
		if right_index < 0:
			right_index = 999
		return left_index < right_index
	)
	for key: String in keys:
		var action_data: Dictionary = actions[key]
		var button := Button.new()
		button.name = "Action_" + key
		button.text = ACTION_LABELS.get(key, key)
		button.custom_minimum_size = Vector2(178, 54)
		button.focus_mode = Control.FOCUS_ALL
		var operation_loading := (
			ViewModel.operation_status(_view_model) == &"loading"
			and str(action_data.get("intent", "")) == str(
				_view_model.get("operation", {}).get("intent", "")
			)
		)
		button.disabled = (
			not ViewModel.action_enabled(action_data)
			or operation_loading
		)
		button.tooltip_text = ViewModel.player_reason(
			ViewModel.disabled_reason(action_data)
		)
		if operation_loading:
			button.text = "处理中…"
			button.icon = _load_icon("loading")
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 28)
			button.theme_type_variation = &"FeedbackLoadingButton"
		elif key in ["discard"]:
			button.theme_type_variation = &"FeedbackDangerButton"
		elif key in ["cancel", "end", "dismiss", "continueEditing"]:
			button.theme_type_variation = &"FeedbackSecondaryButton"
		else:
			button.theme_type_variation = &"FeedbackActionButton"
		button.set_meta("action_key", key)
		button.pressed.connect(
			_on_action_button_pressed.bind(button)
		)
		_actions.add_child(button)
	_link_focus_ring()


func _link_focus_ring() -> void:
	var buttons: Array[Button] = []
	for child: Node in _actions.get_children():
		if child is Button and not (child as Button).disabled:
			buttons.append(child as Button)
	if buttons.is_empty():
		return
	for index: int in range(buttons.size()):
		var current := buttons[index]
		var previous := buttons[
			(index - 1 + buttons.size()) % buttons.size()
		]
		var next := buttons[(index + 1) % buttons.size()]
		current.focus_neighbor_left = current.get_path_to(previous)
		current.focus_neighbor_right = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)


func _focus_safe_action() -> void:
	if not bool(_feedback.get("blocking", false)):
		return
	var safe_names := [
		"Action_cancel",
		"Action_continueEditing",
		"Action_dismiss",
		"Action_end",
	]
	for safe_name: String in safe_names:
		var candidate := _actions.get_node_or_null(safe_name) as Button
		if candidate != null and not candidate.disabled:
			candidate.grab_focus()
			return
	for child: Node in _actions.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).grab_focus()
			return


func _layout() -> void:
	if _frame == null:
		return
	_title.theme_type_variation = &"FeedbackDialogTitle"
	_body.theme_type_variation = &"FeedbackBody"
	_compact.theme_type_variation = &"FeedbackCompact"
	_counter.theme_type_variation = &"FeedbackCompactError"
	for control: Control in [
		_icon,
		_title,
		_body,
		_compact,
		_progress,
		_actions,
		_close,
		_field_surface,
		_field_value,
		_counter,
		_tone_bar,
	]:
		control.visible = false
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	match _current_surface:
		"dialog":
			_layout_dialog()
		"loading_overlay":
			_layout_loading()
		"disabled_reason":
			_layout_disabled_reason()
		"validation":
			_layout_validation()
		"asset_placeholder":
			_layout_asset_placeholder()
		"map_anchor":
			_layout_map_anchor()
		_:
			_layout_toast()


func _set_frame(
	texture_path: String,
	left: int,
	top: int,
	right: int,
	bottom: int
) -> void:
	_frame.texture = ResourceLoader.load(
		texture_path,
		"Texture2D"
	) as Texture2D
	_frame.patch_margin_left = left
	_frame.patch_margin_top = top
	_frame.patch_margin_right = right
	_frame.patch_margin_bottom = bottom
	_frame.axis_stretch_horizontal = (
		NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	)
	_frame.axis_stretch_vertical = (
		NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	)


func _layout_dialog() -> void:
	_set_frame(BASE_PANEL_TEXTURE_PATH, 96, 72, 96, 72)
	_tone_bar.position = Vector2(56, 56)
	_tone_bar.size = Vector2(4, size.y - 112)
	_tone_bar.visible = false
	if size.x < 600.0:
		_layout_dialog_narrow()
		return
	_icon.position = Vector2(76, 60)
	_icon.size = Vector2(SEMANTIC_ICON_SIZE, SEMANTIC_ICON_SIZE)
	_icon.visible = true
	_place_label(
		_title,
		Rect2(136, 36, size.x - 208, 92),
		1,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	var action_count := maxi(1, _actions.get_child_count())
	var column_count := mini(3, action_count)
	var row_count := ceili(float(action_count) / float(column_count))
	var actions_height := float(row_count * 54 + (row_count - 1) * 12)
	for child: Node in _actions.get_children():
		if child is Button:
			(child as Button).custom_minimum_size.x = 178.0
	var actions_y := size.y - actions_height - 58.0
	_place_label(
		_body,
		Rect2(
			72,
			132,
			size.x - 144,
			maxf(0.0, actions_y - 144.0),
		),
		4,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_actions.position = Vector2(72, actions_y)
	_actions.size = Vector2(size.x - 144, actions_height)
	_actions.columns = column_count
	_actions.visible = true


func _layout_dialog_narrow() -> void:
	_icon.position = Vector2(28, 28)
	_icon.size = Vector2(SEMANTIC_ICON_SIZE, SEMANTIC_ICON_SIZE)
	_icon.visible = true
	_place_label(
		_title,
		Rect2(84, 16, size.x - 108, 108),
		2,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	var action_count := maxi(1, _actions.get_child_count())
	var column_count := 2 if action_count > 3 else 1
	var row_count := ceili(float(action_count) / float(column_count))
	var actions_height := float(row_count * 54 + (row_count - 1) * 12)
	for child: Node in _actions.get_children():
		if child is Button:
			(child as Button).custom_minimum_size.x = 0.0
	var actions_y := size.y - actions_height - 20.0
	_place_label(
		_body,
		Rect2(
			24,
			128,
			size.x - 48,
			maxf(0.0, actions_y - 144.0)
		),
		4,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_actions.position = Vector2(24, actions_y)
	_actions.size = Vector2(size.x - 48, actions_height)
	_actions.columns = column_count
	_actions.add_theme_constant_override("v_separation", 12)
	_actions.visible = true


func _layout_toast() -> void:
	_set_frame(TOAST_TEXTURE_PATH, 64, 48, 64, 48)
	_tone_bar.position = Vector2(20, 20)
	_tone_bar.size = Vector2(4, size.y - 40)
	_tone_bar.visible = false
	_icon.position = Vector2(
		32,
		(size.y - SEMANTIC_ICON_SIZE) * 0.5
	)
	_icon.size = Vector2(SEMANTIC_ICON_SIZE, SEMANTIC_ICON_SIZE)
	_icon.visible = true
	_close.position = Vector2(size.x - 64, (size.y - 48) * 0.5)
	_close.size = Vector2(48, 48)
	_close.visible = _toast_close_required()
	var content_right := 72.0 if _close.visible else 28.0
	if expanded or size.y >= 148:
		_place_label(
			_compact,
			Rect2(88, 48, size.x - 88 - content_right, 40),
			1,
			HORIZONTAL_ALIGNMENT_LEFT
		)
		_place_label(
			_body,
			Rect2(
				88,
				88,
				size.x - 88 - content_right,
				size.y - 136
			),
			2,
			HORIZONTAL_ALIGNMENT_LEFT
		)
		_body.theme_type_variation = &"FeedbackCompact"
	else:
		_place_label(
			_compact,
			Rect2(
				88,
				22,
				size.x - 88 - content_right,
				68
			),
			1,
			HORIZONTAL_ALIGNMENT_LEFT
		)


func _layout_loading() -> void:
	_set_frame(BASE_PANEL_TEXTURE_PATH, 96, 72, 96, 72)
	_tone_bar.position = Vector2(56, 56)
	_tone_bar.size = Vector2(4, size.y - 112)
	_tone_bar.visible = false
	_icon.position = Vector2(
		(size.x - SEMANTIC_ICON_SIZE) * 0.5,
		52
	)
	_icon.size = Vector2(SEMANTIC_ICON_SIZE, SEMANTIC_ICON_SIZE)
	_icon.pivot_offset = Vector2(
		SEMANTIC_ICON_SIZE * 0.5,
		SEMANTIC_ICON_SIZE * 0.5
	)
	_icon.visible = true
	_place_label(
		_title,
		Rect2(56, 102, size.x - 112, 58),
		1,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_title.theme_type_variation = &"FeedbackBody"
	_place_label(
		_body,
		Rect2(56, 156, size.x - 112, 90),
		2,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	var show_progress := bool(_feedback.get("showProgress", false))
	if show_progress:
		_progress.position = Vector2(56, 248)
		_progress.size = Vector2(size.x - 112, 24)
		_progress.visible = true
	_actions.position = Vector2(
		(size.x - 229) * 0.5,
		size.y - 104
	)
	_actions.size = Vector2(229, 54)
	_actions.columns = 1
	_actions.visible = _actions.get_child_count() > 0


func _layout_disabled_reason() -> void:
	_set_frame(STRIP_TEXTURE_PATH, 48, 32, 48, 32)
	_icon.position = Vector2(
		18,
		(size.y - COMPACT_ICON_SIZE) * 0.5
	)
	_icon.size = Vector2(COMPACT_ICON_SIZE, COMPACT_ICON_SIZE)
	_icon.visible = true
	_place_label(
		_compact,
		Rect2(64, 8, size.x - 76, size.y - 16),
		2,
		HORIZONTAL_ALIGNMENT_LEFT
	)


func _layout_validation() -> void:
	_set_frame(STRIP_TEXTURE_PATH, 48, 32, 48, 32)
	_field_surface.position = Vector2(24, 12)
	_field_surface.size = Vector2(size.x - 48, 48)
	_field_surface.visible = true
	_place_label(
		_field_value,
		Rect2(36, 12, size.x - 248, 48),
		1,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_icon.position = Vector2(22, 70)
	_icon.size = Vector2(
		VALIDATION_ICON_SIZE,
		VALIDATION_ICON_SIZE
	)
	_icon.visible = true
	_compact.theme_type_variation = &"FeedbackCompactError"
	_place_label(
		_compact,
		Rect2(64, 64, size.x - 84, 52),
		1,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	if not _counter.text.is_empty():
		_place_label(
			_counter,
			Rect2(size.x - 196, 12, 160, 48),
			1,
			HORIZONTAL_ALIGNMENT_RIGHT
		)


func _layout_asset_placeholder() -> void:
	_set_frame(
		PLACEHOLDER_PANEL_TEXTURE_PATH,
		48,
		32,
		48,
		32
	)
	_icon.position = Vector2(
		36,
		(size.y - PLACEHOLDER_ICON_SIZE) * 0.5
	)
	_icon.size = Vector2(
		PLACEHOLDER_ICON_SIZE,
		PLACEHOLDER_ICON_SIZE
	)
	_icon.visible = true
	_place_label(
		_compact,
		Rect2(124, 32, size.x - 148, 40),
		1,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_place_label(
		_body,
		Rect2(124, 72, size.x - 148, size.y - 104),
		2,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_body.theme_type_variation = &"FeedbackCompact"


func _layout_map_anchor() -> void:
	_set_frame(STRIP_TEXTURE_PATH, 48, 32, 48, 32)
	_icon.position = Vector2(
		16,
		(size.y - SEMANTIC_ICON_SIZE) * 0.5
	)
	_icon.size = Vector2(SEMANTIC_ICON_SIZE, SEMANTIC_ICON_SIZE)
	_icon.visible = true
	_place_label(
		_compact,
		Rect2(68, 12, size.x - 84, size.y - 24),
		1,
		HORIZONTAL_ALIGNMENT_LEFT
	)


func _place_label(
	label: Label,
	rect: Rect2,
	max_lines: int,
	alignment: HorizontalAlignment
) -> void:
	label.position = rect.position.floor()
	label.size = rect.size.floor()
	label.max_lines_visible = max_lines
	label.horizontal_alignment = alignment
	label.text_overrun_behavior = (
		TextServer.OVERRUN_NO_TRIMMING
		if max_lines > 1
		else TextServer.OVERRUN_TRIM_ELLIPSIS
	)
	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
		if max_lines > 1
		else TextServer.AUTOWRAP_OFF
	)
	label.visible = true


func _toast_close_required() -> bool:
	var policy := str(_feedback.get("dismissPolicy", ""))
	var tone := str(_feedback.get("tone", "info"))
	return (
		policy in ["manual", "persistent", "action"]
		or tone in ["warning", "error"]
		or int(_feedback.get("durationMsec", 0)) <= 0
	)


func _load_icon(icon_id: String) -> Texture2D:
	var path := str(ICON_PATHS.get(icon_id, ICON_PATHS["info"]))
	return ResourceLoader.load(path, "Texture2D") as Texture2D


func _on_close_pressed() -> void:
	dismiss_requested.emit()
	restore_previous_focus()


func _on_action_button_pressed(button: Button) -> void:
	action_requested.emit(
		StringName(button.get_meta("action_key", ""))
	)
