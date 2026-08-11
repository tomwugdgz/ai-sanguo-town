class_name AudioDisplaySettingsImageLayout
extends Control


signal action_requested(action_key: String, payload: Dictionary)

const UiViewModel = preload("res://ui/common/AiTownUiViewModel.gd")
const FONT_FILE := preload(
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const APPROVED_RUNTIME_SHELL := preload(
	"res://assets/ui/settings/final/shell/"
	+ "audio_display_settings_runtime_shell_approved_v1.png"
)
const LEGACY_SLIDER_TRACK := preload(
	"res://assets/ui/settings/final/controls/slider_track_empty.png"
)
const LEGACY_SLIDER_THUMB := preload(
	"res://assets/ui/settings/final/controls/slider_thumb.png"
)
const LEGACY_SWITCH_OFF := preload(
	"res://assets/ui/settings/final/controls/switch_off.png"
)
const LEGACY_SWITCH_ON := preload(
	"res://assets/ui/settings/final/controls/switch_on.png"
)
const RESOLUTION_ARROW_CLEAR_PATCH := preload(
	"res://assets/ui/settings/final/controls/resolution_arrow_clear_patch.png"
)
const LEGACY_MODE_NORMAL := preload(
	"res://assets/ui/settings/final/controls/window_mode_normal.png"
)
const LEGACY_MODE_SELECTED := preload(
	"res://assets/ui/settings/final/controls/window_mode_selected.png"
)

const BUTTON_FAMILY_TEXTURES := {
	"mode": {
		"normal": preload("res://assets/ui/settings/final/controls/v2/button_mode/normal.png"),
		"hover_1": preload("res://assets/ui/settings/final/controls/v2/button_mode/hover_1.png"),
		"hover_2": preload("res://assets/ui/settings/final/controls/v2/button_mode/hover_2.png"),
		"pressed_1": preload("res://assets/ui/settings/final/controls/v2/button_mode/pressed_1.png"),
		"pressed_2": preload("res://assets/ui/settings/final/controls/v2/button_mode/pressed_2.png"),
		"focus": preload("res://assets/ui/settings/final/controls/v2/button_mode/focus.png"),
		"disabled": preload("res://assets/ui/settings/final/controls/v2/button_mode/disabled.png"),
	},
	"action": {
		"normal": preload("res://assets/ui/settings/final/controls/v2/button_action/normal.png"),
		"hover_1": preload("res://assets/ui/settings/final/controls/v2/button_action/hover_1.png"),
		"hover_2": preload("res://assets/ui/settings/final/controls/v2/button_action/hover_2.png"),
		"pressed_1": preload("res://assets/ui/settings/final/controls/v2/button_action/pressed_1.png"),
		"pressed_2": preload("res://assets/ui/settings/final/controls/v2/button_action/pressed_2.png"),
		"focus": preload("res://assets/ui/settings/final/controls/v2/button_action/focus.png"),
		"disabled": preload("res://assets/ui/settings/final/controls/v2/button_action/disabled.png"),
	},
	"dialog": {
		"normal": preload("res://assets/ui/settings/final/controls/v2/button_dialog/normal.png"),
		"hover_1": preload("res://assets/ui/settings/final/controls/v2/button_dialog/hover_1.png"),
		"hover_2": preload("res://assets/ui/settings/final/controls/v2/button_dialog/hover_2.png"),
		"pressed_1": preload("res://assets/ui/settings/final/controls/v2/button_dialog/pressed_1.png"),
		"pressed_2": preload("res://assets/ui/settings/final/controls/v2/button_dialog/pressed_2.png"),
		"focus": preload("res://assets/ui/settings/final/controls/v2/button_dialog/focus.png"),
		"disabled": preload("res://assets/ui/settings/final/controls/v2/button_dialog/disabled.png"),
	},
	"list": {
		"normal": preload("res://assets/ui/settings/final/controls/v2/button_list/normal.png"),
		"hover_1": preload("res://assets/ui/settings/final/controls/v2/button_list/hover_1.png"),
		"hover_2": preload("res://assets/ui/settings/final/controls/v2/button_list/hover_2.png"),
		"pressed_1": preload("res://assets/ui/settings/final/controls/v2/button_list/pressed_1.png"),
		"pressed_2": preload("res://assets/ui/settings/final/controls/v2/button_list/pressed_2.png"),
		"focus": preload("res://assets/ui/settings/final/controls/v2/button_list/focus.png"),
		"disabled": preload("res://assets/ui/settings/final/controls/v2/button_list/disabled.png"),
	},
}
const BUTTON_SQUARE_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/button_square_sized/normal.png"
)
const BUTTON_SQUARE_HOVER := preload(
	"res://assets/ui/settings/final/controls/v2/button_square_sized/hover.png"
)
const BUTTON_SQUARE_PRESSED := preload(
	"res://assets/ui/settings/final/controls/v2/button_square_sized/pressed.png"
)
const BUTTON_SQUARE_FOCUS := preload(
	"res://assets/ui/settings/final/controls/v2/button_square_sized/focus.png"
)
const BUTTON_SQUARE_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/button_square_sized/disabled.png"
)
const BUTTON_RETRY_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/button_retry_sized/normal.png"
)
const BUTTON_RETRY_HOVER := preload(
	"res://assets/ui/settings/final/controls/v2/button_retry_sized/hover.png"
)
const BUTTON_RETRY_PRESSED := preload(
	"res://assets/ui/settings/final/controls/v2/button_retry_sized/pressed.png"
)
const BUTTON_RETRY_FOCUS := preload(
	"res://assets/ui/settings/final/controls/v2/button_retry_sized/focus.png"
)
const BUTTON_RETRY_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/button_retry_sized/disabled.png"
)
const DROPDOWN_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field/normal.png"
)
const DROPDOWN_HOVER := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field/hover.png"
)
const DROPDOWN_PRESSED := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field/pressed.png"
)
const DROPDOWN_FOCUS := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field/focus.png"
)
const DROPDOWN_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field/disabled.png"
)
const DROPDOWN_COMPACT_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field_compact/normal.png"
)
const DROPDOWN_COMPACT_HOVER := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field_compact/hover.png"
)
const DROPDOWN_COMPACT_PRESSED := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field_compact/pressed.png"
)
const DROPDOWN_COMPACT_FOCUS := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field_compact/focus.png"
)
const DROPDOWN_COMPACT_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_field_compact/disabled.png"
)
const CHEVRON_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_chevron_sized/normal.png"
)
const CHEVRON_HIGHLIGHT := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_chevron_sized/highlight.png"
)
const CHEVRON_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/dropdown_chevron_sized/disabled.png"
)
const TOGGLE_OFF_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/off_normal.png"
)
const TOGGLE_OFF_HOVER := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/off_hover.png"
)
const TOGGLE_OFF_PRESSED := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/off_pressed.png"
)
const TOGGLE_OFF_FOCUS := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/off_focus.png"
)
const TOGGLE_OFF_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/off_disabled.png"
)
const TOGGLE_ON_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/on_normal.png"
)
const TOGGLE_ON_HOVER := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/on_hover.png"
)
const TOGGLE_ON_PRESSED := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/on_pressed.png"
)
const TOGGLE_ON_FOCUS := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/on_focus.png"
)
const TOGGLE_ON_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/toggle_sized/on_disabled.png"
)
const SLIDER_EMPTY_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/slider_track_sized/empty_normal.png"
)
const SLIDER_EMPTY_FOCUS := preload(
	"res://assets/ui/settings/final/controls/v2/slider_track_sized/empty_focus.png"
)
const SLIDER_EMPTY_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/slider_track_sized/empty_disabled.png"
)
const SLIDER_FILL_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/slider_track_sized/fill_normal.png"
)
const SLIDER_FILL_FOCUS := preload(
	"res://assets/ui/settings/final/controls/v2/slider_track_sized/fill_focus.png"
)
const SLIDER_FILL_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/slider_track_sized/fill_disabled.png"
)
const SLIDER_THUMB_NORMAL := preload(
	"res://assets/ui/settings/final/controls/v2/slider_thumb/normal.png"
)
const SLIDER_THUMB_HOVER := preload(
	"res://assets/ui/settings/final/controls/v2/slider_thumb/hover.png"
)
const SLIDER_THUMB_PRESSED := preload(
	"res://assets/ui/settings/final/controls/v2/slider_thumb/pressed.png"
)
const SLIDER_THUMB_FOCUS := preload(
	"res://assets/ui/settings/final/controls/v2/slider_thumb/focus.png"
)
const SLIDER_THUMB_DISABLED := preload(
	"res://assets/ui/settings/final/controls/v2/slider_thumb/disabled.png"
)
const FOCUS_FRAMES := [
	preload("res://assets/ui/settings/final/controls/v2/focus_animation_sized/frame_1.png"),
	preload("res://assets/ui/settings/final/controls/v2/focus_animation_sized/frame_2.png"),
	preload("res://assets/ui/settings/final/controls/v2/focus_animation_sized/frame_3.png"),
]
const UNSAVED_DIALOG_SHELL := preload(
	"res://assets/ui/settings/final/overlays/v2/unsaved_dialog_shell.png"
)
const CONFIRMATION_DIALOG_SHELL := preload(
	"res://assets/ui/settings/final/overlays/v2/confirmation_dialog_shell.png"
)
const COUNTDOWN_BADGE := preload(
	"res://assets/ui/settings/final/overlays/v2/countdown_badge.png"
)
const STATUS_NORMAL := preload(
	"res://assets/ui/settings/final/overlays/v2/status_normal.png"
)
const STATUS_SUCCESS := preload(
	"res://assets/ui/settings/final/overlays/v2/status_success.png"
)
const STATUS_WARNING := preload(
	"res://assets/ui/settings/final/overlays/v2/status_warning.png"
)
const STATUS_ERROR := preload(
	"res://assets/ui/settings/final/overlays/v2/status_error.png"
)

const REFERENCE_SIZE := Vector2(1920, 1080)
const SOURCE_SIZE := Vector2(1672, 941)
const INK := Color("3f2818")
const INK_MUTED := Color("76583d")
const INK_DISABLED := Color("756652")
const LIGHT_TEXT := Color("fff2d5")
const ERROR_DARK := Color("69251f")
const MOSS_DARK := Color("36511e")
const ANIMATION_INTERVAL := 0.13

const AUDIO_ROWS := [
	{"id": "master", "dataKey": "masterPercent", "label": "总音量", "y": 429.0},
	{"id": "music", "dataKey": "musicPercent", "label": "音乐", "y": 506.0},
	{"id": "ambience", "dataKey": "ambiencePercent", "label": "环境", "y": 583.0},
	{"id": "sfx", "dataKey": "sfxPercent", "label": "音效", "y": 662.0},
	{"id": "ui", "dataKey": "uiPercent", "label": "界面", "y": 740.0},
]
const STATUS_COPY := {
	"idle": "设置已载入",
	"loading": "正在处理……",
	"success": "设置已更新",
	"rejected": "这项设置未生效",
	"error": "设置保存失败",
	"disabled": "设置服务暂不可用",
}

var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _internal_update := false
var _slider_dragging: Dictionary = {}
var _audio_sliders: Dictionary = {}
var _audio_values: Dictionary = {}
var _audio_slider_thumbs: Dictionary = {}
var _audio_timers: Dictionary = {}
var _toggle_visuals: Dictionary = {}
var _window_buttons: Dictionary = {}
var _animated_buttons: Array[Button] = []
var _resolution_options: Array[Dictionary] = []
var _resolution_option_buttons: Array[Button] = []
var _animation_frame := 0
var _leave_after_discard := false

var _status_panel: TextureRect
var _status_label: Label
var _retry_button: Button
var _back_button: Button
var _mute_button: Button
var _resolution_button: Button
var _resolution_value_label: Label
var _resolution_chevron: TextureRect
var _resolution_arrow_clear_patch: TextureRect
var _resolution_dropdown: Control
var _resolution_dropdown_frame: NinePatchRect
var _resolution_dropdown_value_label: Label
var _resolution_dropdown_chevron: TextureRect
var _resolution_separators: Array[ColorRect] = []
var _ui_scale_button: Button
var _pixel_button: Button
var _flashing_button: Button
var _restore_button: Button
var _discard_button: Button
var _apply_button: Button
var _unsaved_dialog: Control
var _confirmation_dialog: Control
var _countdown_label: Label
var _focus_indicator: TextureRect
var _animation_timer: Timer


func _ready() -> void:
	custom_minimum_size = REFERENCE_SIZE
	size = REFERENCE_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = _create_font_theme()
	_build()
	if not get_viewport().gui_focus_changed.is_connected(_on_gui_focus_changed):
		get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	if not _view_model.is_empty():
		_render()


func apply_snapshot(view_model: Dictionary, render_data: Dictionary) -> void:
	_view_model = view_model.duplicate(true)
	_render_data = render_data.duplicate(true)
	if is_node_ready():
		_render()


func handle_cancel() -> void:
	if _confirmation_dialog.visible:
		(_confirmation_dialog.get_meta("revert_button") as Button).grab_focus()
		return
	if _unsaved_dialog.visible:
		_hide_unsaved_dialog()
		return
	if _resolution_dropdown.visible:
		_set_resolution_dropdown_visible(false)
		_resolution_button.grab_focus()
		return
	_on_back_pressed()


func dropdown_expanded() -> bool:
	return _resolution_dropdown != null and _resolution_dropdown.visible


func unsaved_dialog_visible() -> bool:
	return _unsaved_dialog != null and _unsaved_dialog.visible


func confirmation_dialog_visible() -> bool:
	return _confirmation_dialog != null and _confirmation_dialog.visible


func animation_frame() -> int:
	return _animation_frame


func _build() -> void:
	var background := TextureRect.new()
	background.name = "ApprovedRuntimeAssetShell"
	background.position = Vector2.ZERO
	background.size = REFERENCE_SIZE
	background.texture = APPROVED_RUNTIME_SHELL
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_register_region(self, "settings_board")
	_build_header()
	_build_audio()
	_build_display()
	_build_page_actions()
	_build_resolution_dropdown()
	_build_unsaved_dialog()
	_build_confirmation_dialog()
	_build_focus_indicator()

	_animation_timer = Timer.new()
	_animation_timer.name = "ControlAssetAnimationTimer"
	_animation_timer.wait_time = ANIMATION_INTERVAL
	_animation_timer.autostart = true
	_animation_timer.timeout.connect(_advance_asset_animation)
	add_child(_animation_timer)


func _build_header() -> void:
	var header_region := Control.new()
	header_region.name = "HeaderRegion"
	header_region.position = _source_point(190, 55)
	header_region.size = _source_point(1270, 160)
	header_region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_register_region(header_region, "header")
	add_child(header_region)

	_back_button = _asset_button(
		"返回",
		_source_rect(238, 93, 118, 102),
		"back",
		"square"
	)
	_back_button.pressed.connect(_on_back_pressed)
	_add_text(
		"page_title",
		"声音与画面设置",
		_source_rect(560, 88, 552, 105),
		54,
		INK
	)

	_status_panel = _texture_rect(
		"StatusBanner",
		_source_rect(1172, 86, 292, 98),
		STATUS_NORMAL
	)
	_status_panel.visible = false
	_status_label = _add_text(
		"operation_status_text",
		"设置已载入",
		_source_rect(1157, 96, 276, 49),
		25,
		INK_MUTED
	)
	_retry_button = _asset_button(
		"重试",
		_source_rect(1172, 135, 292, 49),
		"retry",
		"retry"
	)
	_retry_button.visible = false
	_retry_button.pressed.connect(func() -> void: action_requested.emit("retry", {}))


func _build_audio() -> void:
	var region := Control.new()
	region.name = "AudioPanelRegion"
	region.position = _source_point(214, 228)
	region.size = _source_point(608, 590)
	region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_register_region(region, "audio_panel")
	add_child(region)

	_add_text("audio_heading", "声音", _source_rect(410, 235, 220, 70), 46, INK)
	_add_text("mute_label", "一键静音", _source_rect(274, 297, 370, 68), 31, INK)
	_mute_button = _toggle_button(_source_rect(672, 303, 96, 56), "mute")
	_mute_button.pressed.connect(_on_mute_pressed)

	for row_data: Dictionary in AUDIO_ROWS:
		_build_slider_row(row_data)


func _build_slider_row(row_data: Dictionary) -> void:
	var row_id := str(row_data["id"])
	var y := float(row_data["y"])
	_add_text(
		"%s_label" % row_id,
		str(row_data["label"]),
		_source_rect(257, y - 27, 110, 54),
		29,
		INK
	)
	var value_label := _add_text(
		"%s_value" % row_id,
		"0%",
		_source_rect(686, y - 27, 82, 54),
		28,
		INK
	)
	_audio_values[row_id] = value_label

	_texture_rect(
		"%sSliderTrack" % row_id.capitalize(),
		_source_rect(386, y - 28, 280, 56),
		LEGACY_SLIDER_TRACK
	)
	var thumb := _texture_rect(
		"%sSliderThumb" % row_id.capitalize(),
		_source_rect(386, y - 30.5, 44, 61),
		LEGACY_SLIDER_THUMB
	)
	_audio_slider_thumbs[row_id] = thumb

	var slider := HSlider.new()
	slider.name = "%sAssetSlider" % row_id.capitalize()
	var rect := _source_rect(386, y - 28, 280, 56)
	slider.position = rect.position
	slider.size = rect.size
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.focus_mode = Control.FOCUS_ALL
	_apply_slider_skin(slider, "normal")
	_register_touch(slider, "%s_slider" % row_id)
	slider.drag_started.connect(
		func() -> void:
			_slider_dragging[row_id] = true
			(_audio_timers[row_id] as Timer).stop()
			_apply_slider_skin(slider, "pressed")
	)
	slider.drag_ended.connect(
		func(value_changed: bool) -> void:
			_slider_dragging[row_id] = false
			_apply_slider_skin(slider, "focus" if slider.has_focus() else "normal")
			if value_changed:
				_commit_slider(row_id)
	)
	slider.value_changed.connect(
		func(value: float) -> void:
			(value_label as Label).text = "%d%%" % roundi(value)
			_position_slider_thumb(row_id, value)
			if not _internal_update and not bool(_slider_dragging.get(row_id, false)):
				(_audio_timers[row_id] as Timer).start()
	)
	slider.focus_entered.connect(func() -> void: _apply_slider_skin(slider, "focus"))
	slider.focus_exited.connect(func() -> void: _apply_slider_skin(slider, "normal"))
	slider.mouse_entered.connect(
		func() -> void:
			if not slider.has_focus():
				_apply_slider_skin(slider, "hover")
	)
	slider.mouse_exited.connect(
		func() -> void:
			if not slider.has_focus():
				_apply_slider_skin(slider, "normal")
	)
	add_child(slider)
	_audio_sliders[row_id] = slider
	_slider_dragging[row_id] = false

	var timer := Timer.new()
	timer.name = "%sPreviewCommitTimer" % row_id.capitalize()
	timer.one_shot = true
	timer.wait_time = 0.18
	timer.timeout.connect(_commit_slider.bind(row_id))
	add_child(timer)
	_audio_timers[row_id] = timer


func _build_display() -> void:
	var region := Control.new()
	region.name = "DisplayPanelRegion"
	region.position = _source_point(849, 228)
	region.size = _source_point(602, 590)
	region.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_register_region(region, "display_panel")
	add_child(region)

	_add_text("display_heading", "画面", _source_rect(1035, 235, 230, 70), 46, INK)
	_add_text("resolution_label", "分辨率", _source_rect(895, 294, 190, 76), 31, INK)
	_resolution_value_label = _add_text(
		"resolution_value",
		"—",
		_source_rect(1080, 294, 235, 76),
		30,
		INK
	)
	_resolution_button = _dropdown_button(
		_source_rect(1315, 294, 80, 76),
		"resolution"
	)
	_resolution_button.pressed.connect(_toggle_resolution_dropdown)
	_resolution_arrow_clear_patch = _texture_rect(
		"ResolutionArrowClearPatch",
		_source_rect(1315, 299, 77, 64),
		RESOLUTION_ARROW_CLEAR_PATCH
	)
	_resolution_arrow_clear_patch.visible = false

	var mode_specs := [
		{"id": "windowed", "label": "窗口", "x": 895.0},
		{"id": "borderless_fullscreen", "label": "无边框", "x": 1068.0},
		{"id": "exclusive_fullscreen", "label": "独占全屏", "x": 1243.0},
	]
	for spec: Dictionary in mode_specs:
		var mode_id := str(spec["id"])
		var button := _asset_button(
			str(spec["label"]),
			_source_rect(float(spec["x"]), 396, 154, 72),
			"window_mode_%s" % mode_id,
			"mode"
		)
		button.pressed.connect(_on_window_mode_pressed.bind(mode_id))
		_window_buttons[mode_id] = button

	_add_text("ui_scale_label", "界面缩放", _source_rect(895, 498, 230, 74), 31, INK)
	_ui_scale_button = _dropdown_button(
		_source_rect(1120, 498, 275, 74),
		"ui_scale"
	)
	_ui_scale_button.text = "100%"
	_ui_scale_button.disabled = true
	_ui_scale_button.tooltip_text = "界面会随窗口和分辨率自动重排。"
	_add_text("pixel_rendering_label", "像素渲染", _source_rect(895, 602, 360, 74), 31, INK)
	_pixel_button = _toggle_button(_source_rect(1300, 611, 96, 56), "pixel_rendering")
	_pixel_button.disabled = true
	_pixel_button.tooltip_text = "像素渲染由项目策略固定开启。"
	_add_text("reduced_flashing_label", "减少闪烁", _source_rect(895, 703, 360, 74), 31, INK)
	_flashing_button = _toggle_button(
		_source_rect(1300, 712, 96, 56),
		"reduced_flashing"
	)
	_flashing_button.pressed.connect(_on_flashing_pressed)


func _build_page_actions() -> void:
	_restore_button = _asset_button(
		"恢复默认",
		_source_rect(475, 803, 220, 80),
		"restore_defaults",
		"action"
	)
	_restore_button.pressed.connect(func() -> void: action_requested.emit("restoreDefaults", {}))
	_discard_button = _asset_button(
		"取消更改",
		_source_rect(726, 803, 220, 80),
		"discard_changes",
		"action"
	)
	_discard_button.pressed.connect(func() -> void: action_requested.emit("discardChanges", {}))
	_apply_button = _asset_button(
		"应用设置",
		_source_rect(977, 803, 220, 80),
		"apply",
		"action"
	)
	_apply_button.pressed.connect(func() -> void: action_requested.emit("apply", {}))


func _build_resolution_dropdown() -> void:
	_resolution_dropdown = Control.new()
	_resolution_dropdown.name = "ResolutionDropdown"
	_resolution_dropdown.position = Vector2.ZERO
	_resolution_dropdown.size = REFERENCE_SIZE
	_resolution_dropdown.z_index = 30
	_resolution_dropdown.visible = false
	_resolution_dropdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_resolution_dropdown)

	_resolution_dropdown_frame = NinePatchRect.new()
	_resolution_dropdown_frame.name = "ResolutionExpandedField"
	_resolution_dropdown_frame.position = _source_point(895, 294)
	_resolution_dropdown_frame.size = _source_point(500, 274)
	_resolution_dropdown_frame.texture = DROPDOWN_NORMAL
	_resolution_dropdown_frame.patch_margin_left = 28
	_resolution_dropdown_frame.patch_margin_top = 26
	_resolution_dropdown_frame.patch_margin_right = 28
	_resolution_dropdown_frame.patch_margin_bottom = 26
	_resolution_dropdown_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resolution_dropdown.add_child(_resolution_dropdown_frame)
	_register_region(_resolution_dropdown_frame, "resolution_dropdown")

	_add_text(
		"resolution_dropdown_label",
		"分辨率",
		_source_rect(895, 294, 190, 76),
		31,
		INK,
		_resolution_dropdown
	)
	_resolution_dropdown_value_label = _add_text(
		"resolution_dropdown_value",
		"—",
		_source_rect(1080, 294, 235, 76),
		30,
		INK,
		_resolution_dropdown
	)
	_resolution_dropdown_chevron = _texture_rect(
		"ResolutionExpandedChevron",
		_source_rect(1322, 301, 62, 62),
		CHEVRON_HIGHLIGHT,
		_resolution_dropdown
	)


func _build_unsaved_dialog() -> void:
	_unsaved_dialog = _modal_root("UnsavedChangesDialog")
	_texture_rect(
		"UnsavedDialogShell",
		_source_rect(511, 230, 650, 470),
		UNSAVED_DIALOG_SHELL,
		_unsaved_dialog
	)
	_add_text(
		"unsaved_dialog_title",
		"还有未应用的更改",
		_source_rect(630, 247, 410, 76),
		39,
		INK,
		_unsaved_dialog
	)
	_add_text(
		"unsaved_dialog_body",
		"离开将放弃本页的声音与画面调整。",
		_source_rect(585, 370, 500, 112),
		29,
		INK_MUTED,
		_unsaved_dialog
	)
	var discard := _asset_button(
		"放弃更改",
		_source_rect(610, 563, 220, 94),
		"unsaved_discard",
		"dialog",
		_unsaved_dialog
	)
	var stay := _asset_button(
		"留在此页",
		_source_rect(842, 563, 220, 94),
		"unsaved_stay",
		"dialog",
		_unsaved_dialog
	)
	discard.pressed.connect(_discard_and_leave)
	stay.pressed.connect(_hide_unsaved_dialog)
	_unsaved_dialog.set_meta("discard_button", discard)
	_unsaved_dialog.set_meta("stay_button", stay)


func _build_confirmation_dialog() -> void:
	_confirmation_dialog = _modal_root("DisplayConfirmationDialog")
	_texture_rect(
		"ConfirmationDialogShell",
		_source_rect(511, 230, 650, 470),
		CONFIRMATION_DIALOG_SHELL,
		_confirmation_dialog
	)
	_add_text(
		"confirmation_dialog_title",
		"保留新的显示设置吗？",
		_source_rect(620, 257, 430, 76),
		38,
		INK,
		_confirmation_dialog
	)
	_texture_rect(
		"ConfirmationCountdownBadge",
		_source_rect(794, 348, 83, 82),
		COUNTDOWN_BADGE,
		_confirmation_dialog
	)
	_countdown_label = _add_text(
		"confirmation_countdown",
		"15",
		_source_rect(797, 351, 77, 74),
		38,
		ERROR_DARK,
		_confirmation_dialog
	)
	_add_text(
		"confirmation_dialog_body",
		"若未确认，画面将在倒计时结束后自动恢复。",
		_source_rect(570, 438, 530, 84),
		27,
		INK_MUTED,
		_confirmation_dialog
	)
	var revert := _asset_button(
		"恢复原设置",
		_source_rect(610, 563, 220, 94),
		"display_revert",
		"dialog",
		_confirmation_dialog
	)
	var keep := _asset_button(
		"保留设置",
		_source_rect(842, 563, 220, 94),
		"display_confirm",
		"dialog",
		_confirmation_dialog
	)
	revert.pressed.connect(func() -> void: action_requested.emit("revertDisplay", {}))
	keep.pressed.connect(func() -> void: action_requested.emit("confirmDisplay", {}))
	_confirmation_dialog.set_meta("revert_button", revert)
	_confirmation_dialog.set_meta("keep_button", keep)


func _build_focus_indicator() -> void:
	_focus_indicator = TextureRect.new()
	_focus_indicator.name = "IndependentFocusAnimation"
	_focus_indicator.size = _source_point(100, 98)
	_focus_indicator.texture = FOCUS_FRAMES[0]
	_focus_indicator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_focus_indicator.stretch_mode = TextureRect.STRETCH_SCALE
	_focus_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_indicator.z_index = 45
	_focus_indicator.visible = false
	add_child(_focus_indicator)


func _render() -> void:
	_internal_update = true
	var audio := _render_data.get("audio", {}) as Dictionary
	var display := _render_data.get("display", {}) as Dictionary
	var options := _render_data.get("options", {}) as Dictionary
	var operation_status := str(UiViewModel.operation_status(_view_model))
	var error_value: Variant = _view_model.get("error", null)
	var error := error_value as Dictionary if error_value is Dictionary else {}
	var feedback := _render_data.get("feedback", {}) as Dictionary
	var message := (
		UiViewModel.public_operation_error_message(
			error,
			"设置没有完成，请稍后重试",
		)
		if not error.is_empty()
		else str(feedback.get("message", ""))
	)
	var confirmation_active := bool(
		(_render_data.get("confirmation", {}) as Dictionary).get("active", false)
	)
	var dirty := bool(_render_data.get("dirty", false))
	_status_label.text = (
		"等待确认新画面"
		if confirmation_active
		else "更改待应用"
		if dirty and operation_status not in ["rejected", "error", "disabled"]
		else message
		if operation_status in ["rejected", "error", "disabled"] and not message.is_empty()
		else str(STATUS_COPY.get(operation_status, STATUS_COPY.disabled))
	)
	_status_label.tooltip_text = message
	_status_panel.texture = _status_texture(operation_status)
	_status_label.add_theme_color_override("font_color", _status_color(operation_status))
	_retry_button.visible = (
		operation_status in ["rejected", "error"]
		and bool(error.get("retryable", false))
		and _action_enabled("retry")
	)
	_retry_button.disabled = not _action_enabled("retry")
	_back_button.disabled = not _action_enabled("back")

	_style_toggle(_mute_button, bool(audio.get("muted", false)))
	_mute_button.disabled = not _action_enabled("toggleMute")
	for row_data: Dictionary in AUDIO_ROWS:
		var row_id := str(row_data["id"])
		var value := clampi(int(audio.get(str(row_data["dataKey"]), 0)), 0, 100)
		var slider := _audio_sliders[row_id] as HSlider
		slider.editable = _action_enabled("setAudioValue")
		slider.value = value
		(_audio_values[row_id] as Label).text = "%d%%" % value
		_apply_slider_skin(slider, "normal" if slider.editable else "disabled")

	_populate_resolution(
		options.get("resolutions", []) as Array,
		str(display.get("resolutionId", ""))
	)
	var windowed_resolution := str(display.get("windowModeId", "windowed")) == "windowed"
	_resolution_value_label.size = _source_rect(
		1080,
		294,
		235 if windowed_resolution else 315,
		76
	).size
	# Opening the list is a local UI action. Keep the arrow clickable even when
	# the current runtime cannot apply display changes (for example, an editor-
	# embedded game); each option still carries the real capability decision.
	_resolution_button.visible = windowed_resolution
	_resolution_button.disabled = (
		not windowed_resolution
		or _resolution_options.is_empty()
		or confirmation_active
	)
	_resolution_arrow_clear_patch.visible = not windowed_resolution
	if not windowed_resolution:
		_set_resolution_dropdown_visible(false)
	_resolution_button.tooltip_text = _disabled_reason_text(
		UiViewModel.disabled_reason(UiViewModel.action(_view_model, "selectResolution"))
	)
	_update_dropdown_chevron()
	_render_window_buttons(
		options.get("windowModes", []) as Array,
		str(display.get("windowModeId", ""))
	)
	_ui_scale_button.text = "100%"
	_ui_scale_button.disabled = true
	_style_toggle(_pixel_button, true)
	_style_toggle(_flashing_button, bool(display.get("reducedFlashingEnabled", false)))
	_flashing_button.disabled = not _action_enabled("toggleReducedFlashing")

	_restore_button.disabled = not _action_enabled("restoreDefaults")
	_discard_button.disabled = not _action_enabled("discardChanges")
	_apply_button.disabled = not _action_enabled("apply")

	var confirmation := _render_data.get("confirmation", {}) as Dictionary
	_confirmation_dialog.visible = confirmation_active
	if confirmation_active:
		_set_resolution_dropdown_visible(false)
		_hide_unsaved_dialog()
		_countdown_label.text = str(maxi(0, int(confirmation.get("remainingSeconds", 0))))
		var revert := _confirmation_dialog.get_meta("revert_button") as Button
		var keep := _confirmation_dialog.get_meta("keep_button") as Button
		revert.disabled = not _action_enabled("revertDisplay")
		keep.disabled = not _action_enabled("confirmDisplay")
		if not _confirmation_dialog.is_ancestor_of(get_viewport().gui_get_focus_owner()):
			keep.call_deferred("grab_focus")

	if _leave_after_discard and not bool(_render_data.get("dirty", false)):
		_leave_after_discard = false
		_hide_unsaved_dialog()
		call_deferred("_emit_back_after_discard")
	_internal_update = false


func _populate_resolution(options: Array, selected_id: String) -> void:
	_resolution_options.clear()
	var unavailable_options: Array[Dictionary] = []
	for option_value: Variant in options:
		if not option_value is Dictionary:
			continue
		var option := option_value as Dictionary
		var copied := option.duplicate(true) as Dictionary
		unavailable_options.append(copied)
		if bool(option.get("enabled", true)):
			_resolution_options.append(copied)
	# In an editor-embedded run every display option is intentionally marked
	# unavailable, but the arrow must still open so the player can see why.
	if _resolution_options.is_empty():
		_resolution_options.assign(unavailable_options)
	var selected_label := "—"
	for option: Dictionary in _resolution_options:
		if str(option.get("id", "")) == selected_id:
			selected_label = str(option.get("label", option.get("id", "—")))
			break
	if selected_id == "desktop":
		selected_label = "跟随桌面"
	_resolution_value_label.text = selected_label
	_resolution_dropdown_value_label.text = selected_label
	_rebuild_resolution_options(selected_id)


func _rebuild_resolution_options(selected_id: String) -> void:
	for button: Button in _resolution_option_buttons:
		_animated_buttons.erase(button)
		button.queue_free()
	_resolution_option_buttons.clear()
	for separator: ColorRect in _resolution_separators:
		separator.queue_free()
	_resolution_separators.clear()
	var option_count := mini(_resolution_options.size(), 4)
	_resolution_dropdown_frame.size = _source_point(
		500,
		94 + option_count * 61
	)
	var selected_button: Button
	for index: int in range(option_count):
		var option := _resolution_options[index]
		var button := _asset_button(
			str(option.get("label", option.get("id", "—"))),
			_source_rect(915, 374 + index * 61, 460, 58),
			"resolution_option_%s" % str(option.get("id", index)),
			"list",
			_resolution_dropdown
		)
		button.disabled = (
			not bool(option.get("enabled", true))
			or not _action_enabled("selectResolution")
		)
		button.tooltip_text = UiViewModel.player_reason(
			str(option.get("disabledReason", ""))
		)
		if str(option.get("id", "")) == selected_id:
			_set_wide_selected(button, true)
			selected_button = button
		button.pressed.connect(_select_resolution.bind(option.duplicate(true)))
		_resolution_option_buttons.append(button)
		var separator := ColorRect.new()
		separator.name = "ResolutionSeparator%d" % (index + 1)
		separator.position = _source_point(920, 370 + index * 61)
		separator.size = _source_point(450, 2)
		separator.color = Color("a46a32")
		separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resolution_dropdown.add_child(separator)
		_resolution_dropdown.move_child(separator, 3 + index)
		_resolution_separators.append(separator)
	_resolution_dropdown.set_meta("selected_button", selected_button)


func _render_window_buttons(options: Array, selected_id: String) -> void:
	var by_id := {}
	for option_value: Variant in options:
		if option_value is Dictionary:
			var option := option_value as Dictionary
			by_id[str(option.get("id", ""))] = option
	for mode_id: String in _window_buttons:
		var button := _window_buttons[mode_id] as Button
		var option := by_id.get(mode_id, {}) as Dictionary
		button.disabled = (
			not _action_enabled("selectWindowMode")
			or option.is_empty()
			or not bool(option.get("enabled", true))
		)
		button.tooltip_text = _disabled_reason_text(
			str(option.get("disabledReason", ""))
		)
		if not button.disabled:
			button.tooltip_text = "选择后点击“应用设置”生效。"
		_set_wide_selected(button, mode_id == selected_id)


func _commit_slider(row_id: String) -> void:
	if _internal_update:
		return
	action_requested.emit(
		"setAudioValue",
		{
			"settingId": row_id,
			"percent": roundi((_audio_sliders[row_id] as HSlider).value),
		}
	)


func _position_slider_thumb(row_id: String, value: float) -> void:
	var row_index := -1
	for index: int in range(AUDIO_ROWS.size()):
		if str((AUDIO_ROWS[index] as Dictionary).get("id", "")) == row_id:
			row_index = index
			break
	if row_index < 0 or not _audio_slider_thumbs.has(row_id):
		return
	var row_y := float((AUDIO_ROWS[row_index] as Dictionary)["y"])
	var thumb_x := 386.0 + clampf(value, 0.0, 100.0) / 100.0 * (280.0 - 44.0)
	var rect := _source_rect(thumb_x, row_y - 30.5, 44, 61)
	var thumb := _audio_slider_thumbs[row_id] as TextureRect
	thumb.position = rect.position
	thumb.size = rect.size


func _on_mute_pressed() -> void:
	var audio := _render_data.get("audio", {}) as Dictionary
	action_requested.emit("toggleMute", {"muted": not bool(audio.get("muted", false))})


func _toggle_resolution_dropdown() -> void:
	_set_resolution_dropdown_visible(not _resolution_dropdown.visible)
	if _resolution_dropdown.visible and not _resolution_option_buttons.is_empty():
		var selected: Variant = _resolution_dropdown.get_meta("selected_button", null)
		if selected is Button:
			(selected as Button).grab_focus()
		else:
			(_resolution_option_buttons[0] as Button).grab_focus()


func _set_resolution_dropdown_visible(should_show: bool) -> void:
	_resolution_dropdown.visible = should_show and not _confirmation_dialog.visible
	_update_dropdown_chevron()


func _select_resolution(option: Dictionary) -> void:
	_set_resolution_dropdown_visible(false)
	_resolution_button.grab_focus()
	action_requested.emit("selectResolution", {"resolutionId": str(option.get("id", ""))})


func _on_window_mode_pressed(mode_id: String) -> void:
	action_requested.emit("selectWindowMode", {"windowModeId": mode_id})


func _on_flashing_pressed() -> void:
	var display := _render_data.get("display", {}) as Dictionary
	action_requested.emit(
		"toggleReducedFlashing",
		{"enabled": not bool(display.get("reducedFlashingEnabled", false))}
	)


func _on_back_pressed() -> void:
	if bool((_render_data.get("confirmation", {}) as Dictionary).get("active", false)):
		_confirmation_dialog.visible = true
		(_confirmation_dialog.get_meta("keep_button") as Button).grab_focus()
		return
	if bool(_render_data.get("dirty", false)):
		_set_resolution_dropdown_visible(false)
		_unsaved_dialog.visible = true
		(_unsaved_dialog.get_meta("stay_button") as Button).grab_focus()
		return
	action_requested.emit("back", {})


func _discard_and_leave() -> void:
	_leave_after_discard = true
	action_requested.emit("discardChanges", {})


func _emit_back_after_discard() -> void:
	action_requested.emit("back", {})


func _hide_unsaved_dialog() -> void:
	if _unsaved_dialog == null:
		return
	_unsaved_dialog.visible = false
	_leave_after_discard = false
	_back_button.grab_focus()


func _asset_button(
	text_value: String,
	rect: Rect2,
	gate_id: String,
	family: String,
	parent: Control = self
) -> Button:
	var button := Button.new()
	button.name = "%sAssetButton" % gate_id.to_pascal_case()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_ALL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", LIGHT_TEXT)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", INK_DISABLED)
	if family in ["square", "retry", "list"]:
		_apply_empty_button_styles(button)
		button.set_meta("asset_family", family)
	elif family == "mode":
		_apply_button_styles(
			button,
			LEGACY_MODE_NORMAL,
			LEGACY_MODE_SELECTED,
			LEGACY_MODE_SELECTED,
			LEGACY_MODE_SELECTED,
			LEGACY_MODE_NORMAL
		)
		button.set_meta("asset_family", family)
	else:
		var textures := _button_family_textures(family)
		_apply_button_styles(
			button,
			textures["normal"],
			textures["hover_1"],
			textures["pressed_1"],
			textures["hover_1"],
			textures["disabled"]
		)
		button.set_meta("asset_family", family)
		_animated_buttons.append(button)
	_register_touch(button, gate_id)
	_register_text(button, "%s_text" % gate_id)
	parent.add_child(button)
	return button


func _dropdown_button(rect: Rect2, gate_id: String) -> Button:
	var button := Button.new()
	button.name = "%sDropdownButton" % gate_id.to_pascal_case()
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_ALL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_constant_override("outline_size", 0)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", INK_DISABLED)
	_apply_empty_button_styles(button)
	_register_touch(button, gate_id)
	if gate_id != "resolution":
		_register_text(button, "%s_value" % gate_id)
	add_child(button)

	var chevron := TextureRect.new()
	chevron.name = "%sIndependentChevron" % gate_id.to_pascal_case()
	chevron.position = Vector2(rect.size.x - _source_point(75, 0).x, _source_point(6, 0).x)
	chevron.size = _source_point(68, 68)
	chevron.texture = CHEVRON_NORMAL
	chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chevron.stretch_mode = TextureRect.STRETCH_SCALE
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron.visible = false
	button.add_child(chevron)
	if gate_id == "resolution":
		_resolution_chevron = chevron
	button.mouse_entered.connect(_update_dropdown_chevron)
	button.mouse_exited.connect(_update_dropdown_chevron)
	button.focus_entered.connect(_update_dropdown_chevron)
	button.focus_exited.connect(_update_dropdown_chevron)
	return button


func _toggle_button(rect: Rect2, gate_id: String) -> Button:
	var visual_inset := _source_point(7, 4)
	var visual := _texture_rect(
		"%sToggleVisual" % gate_id.to_pascal_case(),
		Rect2(
			rect.position - visual_inset,
			rect.size + visual_inset * 2.0
		),
		TOGGLE_OFF_NORMAL
	)
	var button := Button.new()
	button.name = "%sToggleButton" % gate_id.to_pascal_case()
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_ALL
	_register_touch(button, gate_id)
	add_child(button)
	_toggle_visuals[button.get_instance_id()] = visual
	_style_toggle(button, false)
	return button


func _style_toggle(button: Button, enabled: bool) -> void:
	button.text = ""
	button.tooltip_text = "开启" if enabled else "关闭"
	_apply_empty_button_styles(button)
	var visual := _toggle_visuals.get(button.get_instance_id(), null) as TextureRect
	if visual != null:
		visual.texture = TOGGLE_ON_NORMAL if enabled else TOGGLE_OFF_NORMAL


func _apply_slider_skin(slider: HSlider, _state: String) -> void:
	# The approved shell contains a baked preview position, so the clean track
	# and live thumb are separate TextureRects. This HSlider remains the native
	# keyboard/pointer input target but must not draw another visual layer.
	slider.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	slider.add_theme_stylebox_override("slider", StyleBoxEmpty.new())
	slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	slider.add_theme_icon_override("grabber", LEGACY_SLIDER_THUMB)
	slider.add_theme_icon_override("grabber_highlight", LEGACY_SLIDER_THUMB)
	slider.add_theme_icon_override("grabber_disabled", LEGACY_SLIDER_THUMB)


func _apply_button_styles(
	button: Button,
	normal: Texture2D,
	hover: Texture2D,
	pressed: Texture2D,
	focus: Texture2D,
	disabled: Texture2D
) -> void:
	button.add_theme_stylebox_override("normal", _texture_style(normal))
	button.add_theme_stylebox_override("hover", _texture_style(hover))
	button.add_theme_stylebox_override("pressed", _texture_style(pressed))
	button.add_theme_stylebox_override("focus", _texture_style(focus))
	button.add_theme_stylebox_override("disabled", _texture_style(disabled))


func _apply_empty_button_styles(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _set_wide_selected(button: Button, selected: bool) -> void:
	button.set_meta("selected", selected)
	var family := str(button.get_meta("asset_family", "mode"))
	if family == "mode":
		button.add_theme_stylebox_override(
			"normal",
			_texture_style(LEGACY_MODE_SELECTED if selected else LEGACY_MODE_NORMAL)
		)
		button.add_theme_color_override("font_color", MOSS_DARK if selected else INK)
		return
	if family == "list":
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_color_override("font_color", MOSS_DARK if selected else INK)
		return
	var textures := _button_family_textures(family)
	button.add_theme_stylebox_override(
		"normal",
		_texture_style(textures["hover_1"] if selected else textures["normal"])
	)
	button.add_theme_color_override("font_color", MOSS_DARK if selected else INK)


func _advance_asset_animation() -> void:
	_animation_frame = (_animation_frame + 1) % 6
	for button: Button in _animated_buttons:
		if not is_instance_valid(button):
			continue
		var family := str(button.get_meta("asset_family", ""))
		var textures := _button_family_textures(family)
		var hover_texture: Texture2D = (
			textures["hover_1"] if _animation_frame % 2 == 0 else textures["hover_2"]
		)
		var pressed_texture: Texture2D = (
			textures["pressed_1"] if _animation_frame % 2 == 0 else textures["pressed_2"]
		)
		button.add_theme_stylebox_override("hover", _texture_style(hover_texture))
		button.add_theme_stylebox_override("pressed", _texture_style(pressed_texture))
	if _focus_indicator.visible:
		_focus_indicator.texture = FOCUS_FRAMES[_animation_frame % FOCUS_FRAMES.size()]


func _button_family_textures(family: String) -> Dictionary:
	assert(BUTTON_FAMILY_TEXTURES.has(family), "未知的独立按钮资产族：%s" % family)
	return BUTTON_FAMILY_TEXTURES[family] as Dictionary


func _on_gui_focus_changed(_control: Control) -> void:
	_focus_indicator.visible = false


func _update_dropdown_chevron() -> void:
	if _resolution_chevron == null:
		return
	if _resolution_button.disabled:
		_resolution_chevron.texture = CHEVRON_DISABLED
	elif _resolution_dropdown.visible or _resolution_button.has_focus():
		_resolution_chevron.texture = CHEVRON_HIGHLIGHT
	else:
		_resolution_chevron.texture = CHEVRON_NORMAL


func _action_enabled(action_key: String) -> bool:
	return UiViewModel.action_enabled(UiViewModel.action(_view_model, action_key))


func _texture_rect(
	node_name: String,
	rect: Rect2,
	texture: Texture2D,
	parent: Control = self
) -> TextureRect:
	var result := TextureRect.new()
	result.name = node_name
	result.position = rect.position
	result.size = rect.size
	result.texture = texture
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_SCALE
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result


func _modal_root(node_name: String) -> Control:
	var modal := Control.new()
	modal.name = node_name
	modal.position = Vector2.ZERO
	modal.size = REFERENCE_SIZE
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 50
	modal.visible = false
	add_child(modal)
	return modal


func _add_text(
	gate_id: String,
	text_value: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	parent: Control = self
) -> Label:
	var label := Label.new()
	label.name = "%sText" % gate_id.to_pascal_case()
	label.position = rect.position.round()
	label.size = rect.size.round()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", maxi(font_size, 30))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_register_text(label, gate_id)
	parent.add_child(label)
	return label


func _source_rect(x: float, y: float, width: float, height: float) -> Rect2:
	var scale_factor := REFERENCE_SIZE / SOURCE_SIZE
	return Rect2(
		Vector2(roundf(x * scale_factor.x), roundf(y * scale_factor.y)),
		Vector2(roundf(width * scale_factor.x), roundf(height * scale_factor.y))
	)


func _source_point(x: float, y: float) -> Vector2:
	var scale_factor := REFERENCE_SIZE / SOURCE_SIZE
	return Vector2(roundf(x * scale_factor.x), roundf(y * scale_factor.y))


func _texture_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.draw_center = true
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return style


func _status_texture(status: String) -> Texture2D:
	match status:
		"success":
			return STATUS_SUCCESS
		"rejected":
			return STATUS_WARNING
		"error", "disabled":
			return STATUS_ERROR
	return STATUS_NORMAL


func _status_color(status: String) -> Color:
	match status:
		"success":
			return MOSS_DARK
		"rejected", "error", "disabled":
			return ERROR_DARK
	return INK_MUTED


func _disabled_reason_text(reason: String) -> String:
	match reason:
		"RESOLUTION_FOLLOWS_DESKTOP":
			return "全屏模式跟随当前桌面分辨率。"
		"RESOLUTION_EXCEEDS_DISPLAY":
			return "这个分辨率超出当前显示器可用范围。"
		"EXCLUSIVE_FULLSCREEN_UNAVAILABLE":
			return "当前平台不支持独占全屏。"
		"DISPLAY_SERVER_UNAVAILABLE":
			return "当前环境无法调整窗口显示。"
		"DISPLAY_CHANGES_UNSUPPORTED_WHILE_EMBEDDED":
			return "Godot 编辑器内嵌运行不支持窗口或全屏切换；请用独立游戏窗口测试。"
		"DISPLAY_CONFIRMATION_REQUIRED":
			return "请先保留或恢复当前显示设置。"
	return ""


func _create_font_theme() -> Theme:
	var result := Theme.new()
	var main_menu_font := FontVariation.new()
	main_menu_font.base_font = FONT_FILE
	main_menu_font.spacing_glyph = 2
	main_menu_font.spacing_space = 0
	main_menu_font.variation_embolden = 0.0
	result.default_font = main_menu_font
	result.default_font_size = 28
	return result


func _register_touch(control: Control, gate_id: String) -> void:
	control.add_to_group("audio_display_settings_touch_target")
	control.set_meta("gate_touch_id", gate_id)


func _register_text(control: Control, gate_id: String) -> void:
	control.add_to_group("audio_display_settings_text_slot")
	control.set_meta("gate_text_id", gate_id)


func _register_region(control: Control, gate_id: String) -> void:
	control.add_to_group("audio_display_settings_region")
	control.set_meta("gate_region_id", gate_id)
