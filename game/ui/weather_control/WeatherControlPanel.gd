class_name WeatherControlPanel
extends Control


signal closed
signal selected_weather_changed(weather_id: String)
signal dispatch_requested(intent: String, payload: Dictionary)

const ViewModel := preload("res://ui/common/AiTownUiViewModel.gd")
const FormalDialog := preload(
	"res://ui/common/formal_dialog/FormalConfirmationDialog.gd"
)
const COMPOSITE_PATH := (
	"res://assets/ui/weather_control/runtime/"
	+ "weather_control_panel_runtime_master_v2_alpha.png"
)
const WIDE_COMPOSITE_PATH := (
	"res://assets/ui/weather_control/runtime/"
	+ "weather_control_panel_runtime_wide_v1_alpha.png"
)
const MAIN_MENU_FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const ICON_ATLAS_PATH := (
	"res://assets/ui/weather_control/runtime/"
	+ "weather_control_icons_atlas_v1_alpha.png"
)
const SELECTED_OPTION_FRAME_PATHS := [
	"res://assets/ui/weather_control/runtime/weather_option_selected_desktop_0.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_desktop_1.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_desktop_2.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_desktop_3.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_desktop_4.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_desktop_5.png",
]
const WIDE_SELECTED_OPTION_FRAME_PATHS := [
	"res://assets/ui/weather_control/runtime/weather_option_selected_wide_0.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_wide_1.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_wide_2.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_wide_3.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_wide_4.png",
	"res://assets/ui/weather_control/runtime/weather_option_selected_wide_5.png",
]
const SCOPE := "weather_control"
const MINIMUM_KEY_FONT_SIZE := 20
const MINIMUM_SUPPORT_FONT_SIZE := 20

const INK := Color("#3f2818")
const INK_MUTED := Color("#68452b")
const PAPER := Color("#f6e5b6")
const PAPER_LIGHT := Color("#fff1c9")
const WOOD := Color("#6c3d20")
const WOOD_DARK := Color("#4a2a18")
const MOSS := Color("#4d681f")
const MOSS_BRIGHT := Color("#78952f")
const TERRACOTTA := Color("#a84f32")
const ERROR_COLOR := Color("#8d2f28")
const DISABLED_COLOR := Color("#806f5b")
const BUTTON_NORMAL_MODULATE := Color.WHITE
const BUTTON_HOVER_MODULATE := Color("#fff0c4")
const BUTTON_PRESSED_MODULATE := Color("#dfbf8f")
const BUTTON_FOCUS_MODULATE := Color("#dfeebd")
const BUTTON_DISABLED_MODULATE := Color("#d1c6b2")

const DESKTOP_PANEL_SIZE := Vector2(640, 1000)
const WIDE_PANEL_SIZE := Vector2(614, 688)
const DESKTOP_SUBMENU_SIZE := Vector2(512, 800)
const WIDE_SUBMENU_SIZE := Vector2(492, 552)
const DESKTOP_SUBMENU_MARGIN_RIGHT := 48.0
const WIDE_SUBMENU_MARGIN_RIGHT := 32.0
const DESKTOP_ATLAS_REGION := Rect2(79, 104, 885, 1384)
const WIDE_ATLAS_REGION := Rect2(203, 68, 942, 1055)
const ICON_ATLAS_REGIONS := {
	"weather_sunny": Rect2(145, 130, 285, 300),
	"weather_cloudy": Rect2(592, 120, 370, 320),
	"weather_light_rain": Rect2(1094, 120, 380, 330),
	"weather_heavy_rain": Rect2(130, 562, 340, 330),
	"weather_thunderstorm": Rect2(612, 562, 350, 350),
	"weather_snow": Rect2(1094, 562, 380, 350),
}

@export var adapter_path: NodePath
@export var safe_inset_left := 0
@export var safe_inset_top := 0
@export var safe_inset_right := 0
@export var safe_inset_bottom := 0

var _adapter: Node
var _view_model: Dictionary = {}
var _render_data: Dictionary = {}
var _last_confirmed_data: Dictionary = {}
var _revision := -1
var _latest_snapshot_revision := -1
var _operation_status := StringName("idle")
var _selected_weather_id := ""
var _draft_dirty := false
var _dispatch_guard := false
var _layout_mode := "desktop_composite"
var _local_dispatch_error := ""
var _last_submitted_intent := ""
var _last_submitted_weather_id := ""
var _failed_intent := ""
var _failed_weather_id := ""

var _backdrop: ColorRect
var _panel_root: Control
var _desktop_shell: TextureRect
var _wide_shell: TextureRect
var _title_label: Label
var _close_button: Button
var _current_section: Panel
var _current_icon: TextureRect
var _current_label: Label
var _mode_section: Panel
var _mode_label: Label
var _scroll: ScrollContainer
var _content: Control
var _option_buttons: Array[Button] = []
var _option_icons: Array[TextureRect] = []
var _option_selected_surfaces: Array[TextureRect] = []
var _option_labels: Array[Label] = []
var _description_section: Panel
var _description_label: Label
var _places_section: Panel
var _places_label: Label
var _resident_section: Panel
var _resident_label: Label
var _feedback_section: Panel
var _feedback_label: Label
var _cancel_mode_button: Button
var _confirm_button: Button
var _confirm_label: Label
var _runtime_atlas: Texture2D
var _wide_runtime_atlas: Texture2D
var _icon_atlas: Texture2D
var _selected_option_frames: Array[Texture2D] = []
var _wide_selected_option_frames: Array[Texture2D] = []
var _main_menu_font: FontVariation
var _exit_confirmation: FormalDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_menu_font = _create_main_menu_font()
	var page_theme := Theme.new()
	if _main_menu_font != null:
		page_theme.default_font = _main_menu_font
	page_theme.default_font_size = 32
	theme = page_theme
	_build_nodes()
	_build_exit_confirmation()
	resized.connect(_layout)
	_bind_initial_adapter()
	_layout()


func bind_adapter(adapter: Node) -> PackedStringArray:
	if adapter == null:
		return PackedStringArray(["WeatherControlPanel adapter 不能为空"])
	if not adapter.has_method("get_view_model"):
		return PackedStringArray(["WeatherControlPanel adapter 缺少 get_view_model"])
	if not adapter.has_method("dispatch"):
		return PackedStringArray(["WeatherControlPanel adapter 缺少 dispatch"])
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var old_callable := Callable(self, "_on_view_model_changed")
		if _adapter.is_connected("view_model_changed", old_callable):
			_adapter.disconnect("view_model_changed", old_callable)
	_adapter = adapter
	if _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if not _adapter.is_connected("view_model_changed", callback):
			_adapter.connect("view_model_changed", callback)
	var incoming: Variant = _adapter.call("get_view_model", SCOPE)
	if not incoming is Dictionary:
		return PackedStringArray([
			"WeatherControlPanel adapter.get_view_model 必须返回 Dictionary"
		])
	var incoming_dictionary := incoming as Dictionary
	var incoming_error := _as_dictionary(
		incoming_dictionary.get("error", null)
	)
	if str(incoming_error.get("code", "")) == "UNKNOWN_UI_SCOPE":
		return PackedStringArray([
			"TownUiAdapter 尚未交付 weather_control scope"
		])
	return configure(incoming_dictionary)


func bind_town_ui_adapter(adapter: Node) -> void:
	var issues := bind_adapter(adapter)
	for issue: String in issues:
		if not issue.contains("丢弃过期"):
			push_error(issue)


func unbind_town_ui_adapter() -> void:
	if _adapter != null and _adapter.has_signal("view_model_changed"):
		var callback := Callable(self, "_on_view_model_changed")
		if _adapter.is_connected("view_model_changed", callback):
			_adapter.disconnect("view_model_changed", callback)
	_adapter = null
	reset_revision()


func focus_default() -> void:
	if _close_button != null and _close_button.is_visible_in_tree():
		_close_button.grab_focus()


func configure(view_model: Dictionary) -> PackedStringArray:
	var issues := ViewModel.validate(view_model, "WeatherControlPanel")
	if String(view_model.get("scope", "")) != SCOPE:
		issues.append("WeatherControlPanel 只接受 weather_control scope")
	if not issues.is_empty():
		return issues
	var incoming_revision := ViewModel.revision(view_model)
	if incoming_revision < _revision:
		return PackedStringArray([
			"WeatherControlPanel 丢弃过期 revision=%d，当前=%d"
			% [incoming_revision, _revision]
		])
	_latest_snapshot_revision = maxi(_latest_snapshot_revision, incoming_revision)
	_view_model = view_model.duplicate(true)
	_operation_status = ViewModel.operation_status(_view_model)
	var incoming_data := ViewModel.data(_view_model)
	var can_confirm_snapshot := (
		_operation_status in [&"idle", &"success"]
		and not incoming_data.is_empty()
	)
	if can_confirm_snapshot:
		var previous_selected := _selected_weather_id
		_last_confirmed_data = incoming_data.duplicate(true)
		_render_data = incoming_data.duplicate(true)
		_revision = incoming_revision
		var current_id := _current_weather_id()
		if _operation_status == &"success" or previous_selected.is_empty():
			_selected_weather_id = current_id
			_draft_dirty = false
		elif not _draft_dirty:
			_selected_weather_id = current_id
		elif _selected_weather_id == current_id:
			_draft_dirty = false
	elif (
		_operation_status == &"loading"
		and incoming_revision > _revision
		and not incoming_data.is_empty()
	):
		_last_confirmed_data = incoming_data.duplicate(true)
		_render_data = incoming_data.duplicate(true)
		_revision = incoming_revision
	elif not _last_confirmed_data.is_empty():
		_render_data = _last_confirmed_data.duplicate(true)
	elif not incoming_data.is_empty():
		_last_confirmed_data = incoming_data.duplicate(true)
		_render_data = incoming_data.duplicate(true)
		_revision = incoming_revision
	else:
		_render_data = {}
	_update_failed_operation_state()
	if _operation_status != &"loading":
		_dispatch_guard = false
	_local_dispatch_error = ""
	_refresh_copy_and_state()
	return issues


func reset_revision() -> void:
	_revision = -1
	_latest_snapshot_revision = -1
	_last_confirmed_data.clear()
	_render_data.clear()
	_view_model.clear()
	_selected_weather_id = ""
	_draft_dirty = false
	_dispatch_guard = false
	_last_submitted_intent = ""
	_last_submitted_weather_id = ""
	_failed_intent = ""
	_failed_weather_id = ""


func debug_select_weather(weather_id: String) -> bool:
	for option: Dictionary in _weather_options():
		if str(option.get("id", "")) == weather_id:
			_select_weather(weather_id)
			return true
	return false


func debug_snapshot() -> Dictionary:
	return {
		"scope": SCOPE,
		"layoutMode": _layout_mode,
		"revision": _revision,
		"latestSnapshotRevision": _latest_snapshot_revision,
		"operationStatus": String(_operation_status),
		"currentWeatherId": _current_weather_id(),
		"selectedWeatherId": _selected_weather_id,
		"draftDirty": _draft_dirty,
		"requestId": ViewModel.operation_request_id(_view_model),
		"source": str(_view_model.get("source", "")),
		"capabilityMode": str(_view_model.get("capabilityMode", "")),
		"formalReady": bool(_view_model.get("formalReady", true)),
		"failedIntent": _failed_intent,
		"failedWeatherId": _failed_weather_id,
		"confirmDisabled": _confirm_button.disabled,
		"confirmText": _confirm_label.text,
		"feedbackText": _feedback_label.text,
		"backdropBlocksMouse": (
			_backdrop.mouse_filter == Control.MOUSE_FILTER_STOP
		),
		"renderData": _render_data.duplicate(true),
		"lastConfirmedData": _last_confirmed_data.duplicate(true),
		"textSlots": debug_text_layout_snapshot(),
		"desktopCompositeVisible": _desktop_shell.visible,
		"wideCompositeVisible": _wide_shell.visible,
		"flexibleNinePatchVisible": false,
		"panelDesignSize": [_panel_design_size().x, _panel_design_size().y],
		"panelEffectiveSize": [_panel_root.size.x, _panel_root.size.y],
		"panelRect": [
			_panel_root.position.x,
			_panel_root.position.y,
			_panel_root.size.x,
			_panel_root.size.y,
		],
	}


func debug_text_layout_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _panel_root == null:
		return result
	for node: Node in _panel_root.find_children("*", "Label", true, false):
		var label := node as Label
		if label == null or not label.visible:
			continue
		result.append({
			"id": str(_panel_root.get_path_to(label)),
			"text": label.text,
			"fontSize": label.get_theme_font_size("font_size"),
			"rect": [label.position.x, label.position.y, label.size.x, label.size.y],
			"fullTextFits": bool(label.get_meta("weather_text_fits", true)),
			"contained": bool(label.get_meta("weather_text_contained", true)),
			"adaptive": bool(label.get_meta("weather_text_adaptive", false)),
			"overrun": int(label.text_overrun_behavior),
			"maxLines": label.max_lines_visible,
		})
	return result


func debug_interaction_snapshot() -> Dictionary:
	var option_states: Array[Dictionary] = []
	for button: Button in _option_buttons:
		option_states.append(_button_interaction_snapshot(button))
	return {
		"close": _button_interaction_snapshot(_close_button),
		"confirm": _button_interaction_snapshot(_confirm_button),
		"cancelMode": _button_interaction_snapshot(_cancel_mode_button),
		"options": option_states,
	}


func _bind_initial_adapter() -> void:
	if not adapter_path.is_empty():
		var configured_adapter := get_node_or_null(adapter_path)
		if configured_adapter != null:
			var issues := bind_adapter(configured_adapter)
			if issues.is_empty():
				return
func _on_view_model_changed(scope: String, view_model: Dictionary) -> void:
	if scope != SCOPE:
		return
	var issues := configure(view_model)
	for issue: String in issues:
		if not issue.contains("丢弃过期"):
			push_error(issue)


func _build_nodes() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_runtime_atlas = ResourceLoader.load(COMPOSITE_PATH, "Texture2D") as Texture2D
	_wide_runtime_atlas = ResourceLoader.load(
		WIDE_COMPOSITE_PATH,
		"Texture2D"
	) as Texture2D
	_icon_atlas = ResourceLoader.load(ICON_ATLAS_PATH, "Texture2D") as Texture2D
	for path: String in SELECTED_OPTION_FRAME_PATHS:
		_selected_option_frames.append(
			ResourceLoader.load(path, "Texture2D") as Texture2D
		)
	for path: String in WIDE_SELECTED_OPTION_FRAME_PATHS:
		_wide_selected_option_frames.append(
			ResourceLoader.load(path, "Texture2D") as Texture2D
		)
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.08, 0.05, 0.02, 0.34)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	_panel_root = Control.new()
	_panel_root.name = "PanelRoot"
	_panel_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel_root)

	_desktop_shell = TextureRect.new()
	_desktop_shell.name = "DesktopCompositeShell"
	_desktop_shell.texture = _atlas_texture(DESKTOP_ATLAS_REGION)
	_desktop_shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_desktop_shell.stretch_mode = TextureRect.STRETCH_SCALE
	_desktop_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_desktop_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_desktop_shell)

	_wide_shell = TextureRect.new()
	_wide_shell.name = "WideCompositeShell"
	_wide_shell.texture = _wide_atlas_texture(WIDE_ATLAS_REGION)
	_wide_shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wide_shell.stretch_mode = TextureRect.STRETCH_SCALE
	_wide_shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_wide_shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_wide_shell)

	_title_label = _make_label(_panel_root, "Title", 48, INK)
	_title_label.text = "天气控制"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_close_button = _make_button(_panel_root, "CloseButton")
	_close_button.tooltip_text = "关闭天气控制"
	var close_label := _make_label(_close_button, "CloseGlyph", 48, INK)
	close_label.text = "×"
	close_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_close_button.pressed.connect(request_back)

	_current_section = _make_panel(_panel_root, "CurrentWeatherSection")
	_current_icon = TextureRect.new()
	_current_icon.name = "CurrentWeatherIcon"
	_current_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_current_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_current_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_current_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_current_section.add_child(_current_icon)
	_current_label = _make_label(
		_current_section,
		"CurrentWeatherLabel",
		32,
		INK
	)
	_current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_current_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_mode_section = _make_panel(_panel_root, "ModeSection")
	_mode_label = _make_label(_mode_section, "ModeLabel", 32, INK)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel_root.add_child(_scroll)
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_content)

	for index: int in range(6):
		var option_button := _make_button(
			_content,
			"WeatherOptionButton%d" % index
		)
		option_button.set_meta("option_index", index)
		option_button.clip_contents = false
		var selected_surface := TextureRect.new()
		selected_surface.name = "SelectedSurface"
		selected_surface.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		selected_surface.stretch_mode = TextureRect.STRETCH_SCALE
		selected_surface.texture = _selected_option_frames[index]
		selected_surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		selected_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		selected_surface.z_index = 0
		selected_surface.visible = false
		option_button.add_child(selected_surface)
		var option_icon := TextureRect.new()
		option_icon.name = "Icon"
		option_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		option_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		option_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		option_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		option_icon.z_index = 1
		option_icon.visible = false
		option_button.add_child(option_icon)
		var option_label := _make_label(
			option_button,
			"Label",
			32,
			INK
		)
		option_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		option_label.z_index = 1
		option_button.pressed.connect(
			_on_option_pressed.bind(index)
		)
		_option_buttons.append(option_button)
		_option_icons.append(option_icon)
		_option_selected_surfaces.append(selected_surface)
		_option_labels.append(option_label)

	_description_section = _make_panel(_content, "DescriptionSection")
	_description_label = _make_label(
		_description_section,
		"DescriptionLabel",
		32,
		INK
	)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_places_section = _make_panel(_content, "PlacesSection")
	_places_label = _make_label(_places_section, "PlacesLabel", 32, INK)
	_places_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_places_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_resident_section = _make_panel(_content, "ResidentSection")
	_resident_label = _make_label(
		_resident_section,
		"ResidentLabel",
		32,
		INK
	)
	_resident_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resident_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_feedback_section = _make_panel(_content, "FeedbackSection")
	_feedback_label = _make_label(
		_feedback_section,
		"FeedbackLabel",
		32,
		MOSS
	)
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_cancel_mode_button = _make_button(_content, "CancelModeButton")
	var cancel_label := _make_label(
		_cancel_mode_button,
		"CancelLabel",
		32,
		WOOD
	)
	cancel_label.text = "取消"
	cancel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cancel_mode_button.pressed.connect(request_back)

	_confirm_button = _make_button(_panel_root, "ConfirmButton")
	_confirm_label = _make_label(
		_confirm_button,
		"ConfirmLabel",
		48,
		PAPER_LIGHT
	)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirm_button.pressed.connect(_on_confirm_pressed)


func _create_main_menu_font() -> FontVariation:
	var font_file := (
		ResourceLoader.load(MAIN_MENU_FONT_PATH, "FontFile") as FontFile
	)
	if font_file == null:
		push_error("天气控制缺少主菜单字体：%s" % MAIN_MENU_FONT_PATH)
		return null
	var variation := FontVariation.new()
	variation.base_font = font_file
	variation.spacing_glyph = 2
	variation.spacing_space = 0
	variation.variation_embolden = 0.0
	return variation


func _make_label(
	parent: Node,
	node_name: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if _main_menu_font != null:
		label.add_theme_font_override("font", _main_menu_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_constant_override("line_spacing", 8)
	parent.add_child(label)
	return label


func _make_panel(parent: Node, node_name: String) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _make_button(parent: Node, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
	button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))
	button.focus_entered.connect(_on_button_focus_changed.bind(button))
	button.focus_exited.connect(_on_button_focus_changed.bind(button))
	parent.add_child(button)
	_apply_button_interaction_state(button)
	return button


func _atlas_texture(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = _runtime_atlas
	atlas.region = region
	atlas.filter_clip = true
	return atlas


func _wide_atlas_texture(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = _wide_runtime_atlas
	atlas.region = region
	atlas.filter_clip = true
	return atlas


func _icon_atlas_texture(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = _icon_atlas
	atlas.region = region
	atlas.filter_clip = true
	return atlas


func _layout() -> void:
	if _panel_root == null:
		return
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var viewport_size := size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = get_viewport_rect().size
	var available := Rect2(
		maxf(16.0, float(safe_inset_left)),
		maxf(16.0, float(safe_inset_top)),
		maxf(
			1.0,
			viewport_size.x
			- maxf(16.0, float(safe_inset_left))
			- maxf(16.0, float(safe_inset_right))
		),
		maxf(
			1.0,
			viewport_size.y
			- maxf(16.0, float(safe_inset_top))
			- maxf(16.0, float(safe_inset_bottom))
		)
	)
	if (
		available.size.x >= 1560.0
		and available.size.y >= 1000.0
	):
		_layout_mode = "desktop_composite"
	else:
		_layout_mode = "wide_composite"
	if _layout_mode == "desktop_composite":
		var panel_size := DESKTOP_SUBMENU_SIZE
		var panel_position := Vector2(
			available.end.x
			- panel_size.x
			- DESKTOP_SUBMENU_MARGIN_RIGHT,
			available.position.y
			+ (available.size.y - panel_size.y) * 0.5
		)
		_apply_rect(
			_panel_root,
			Rect2(panel_position, panel_size)
		)
		_layout_desktop()
	else:
		var panel_size := WIDE_SUBMENU_SIZE
		var panel_position := Vector2(
			available.end.x
			- panel_size.x
			- WIDE_SUBMENU_MARGIN_RIGHT,
			available.position.y
			+ (available.size.y - panel_size.y) * 0.5
		)
		_apply_rect(
			_panel_root,
			Rect2(panel_position, panel_size)
		)
		_layout_wide()
	_refresh_copy_and_state()


func _layout_desktop() -> void:
	var scale_factor := DESKTOP_SUBMENU_SIZE / DESKTOP_PANEL_SIZE
	_desktop_shell.visible = true
	_wide_shell.visible = false
	_apply_composite_font_tokens(false)
	_apply_rect(_desktop_shell, Rect2(Vector2.ZERO, DESKTOP_PANEL_SIZE), scale_factor)
	_apply_rect(_title_label, Rect2(72, 12, 496, 92), scale_factor)
	_apply_rect(_close_button, Rect2(564, 16, 60, 72), scale_factor)
	_apply_child_full_rect(_close_button.get_node("CloseGlyph") as Control)

	_apply_rect(_current_section, Rect2(34, 112, 402, 96), scale_factor)
	_apply_rect(_current_icon, Rect2(18, 12, 76, 72), scale_factor)
	_apply_rect(_current_label, Rect2(118, 4, 276, 88), scale_factor)
	_apply_rect(_mode_section, Rect2(452, 112, 154, 96), scale_factor)
	_apply_child_full_rect(_mode_label)

	_apply_rect(_scroll, Rect2(0, 216, 640, 666), scale_factor)
	_content.custom_minimum_size = (
		Vector2(640, 660) * scale_factor
	).round()
	_apply_rect(_content, Rect2(0, 0, 640, 660), scale_factor)
	var x_positions := [33.0, 224.0, 412.0]
	var selected_surface_rects := [
		Rect2(0, 0, 177, 158),
		Rect2(0, 0, 182, 158),
		Rect2(8, 0, 186, 158),
		Rect2(0, 0, 177, 160),
		Rect2(0, 0, 182, 160),
		Rect2(8, 0, 186, 160),
	]
	for index: int in range(_option_buttons.size()):
		var column := index % 3
		var row := index / 3
		_apply_rect(
			_option_buttons[index],
			Rect2(x_positions[column], 2 + row * 168, 178, 158),
			scale_factor
		)
		_option_selected_surfaces[index].texture = _selected_option_frames[index]
		_apply_rect(
			_option_selected_surfaces[index],
			selected_surface_rects[index],
			scale_factor
		)
		_apply_rect(_option_icons[index], Rect2(18, 8, 142, 96), scale_factor)
		_apply_rect(_option_labels[index], Rect2(8, 104, 162, 50), scale_factor)
	_apply_rect(_description_section, Rect2(33, 344, 572, 194), scale_factor)
	_apply_rect(_description_label, Rect2(22, 16, 528, 162), scale_factor)
	_apply_rect(_places_section, Rect2(33, 548, 276, 62), scale_factor)
	_apply_rect(_places_label, Rect2(12, 4, 252, 54), scale_factor)
	_apply_rect(_resident_section, Rect2(321, 548, 284, 62), scale_factor)
	_apply_rect(_resident_label, Rect2(12, 4, 260, 54), scale_factor)
	_apply_rect(_feedback_section, Rect2(33, 608, 572, 54), scale_factor)
	_apply_rect(_feedback_label, Rect2(12, 0, 548, 54), scale_factor)
	_apply_rect(_cancel_mode_button, Rect2(438, 602, 150, 60), scale_factor)
	_apply_child_full_rect(
		_cancel_mode_button.get_node("CancelLabel") as Control
	)
	_apply_rect(_confirm_button, Rect2(60, 888, 520, 96), scale_factor)
	_apply_child_full_rect(_confirm_label)
	_apply_baked_composite_owner_styles()


func _layout_wide() -> void:
	var scale_factor := WIDE_SUBMENU_SIZE / WIDE_PANEL_SIZE
	_desktop_shell.visible = false
	_wide_shell.visible = true
	_apply_composite_font_tokens(true)
	_apply_rect(_wide_shell, Rect2(Vector2.ZERO, WIDE_PANEL_SIZE), scale_factor)
	_apply_rect(_title_label, Rect2(32, 18, 492, 78), scale_factor)
	_apply_rect(_close_button, Rect2(538, 22, 60, 76), scale_factor)
	_apply_child_full_rect(_close_button.get_node("CloseGlyph") as Control)

	_apply_rect(_current_section, Rect2(33, 105, 416, 70), scale_factor)
	_apply_rect(_current_icon, Rect2(0, 6, 100, 58), scale_factor)
	_apply_rect(_current_label, Rect2(108, 0, 308, 70), scale_factor)
	_apply_rect(_mode_section, Rect2(462, 105, 119, 70), scale_factor)
	_apply_child_full_rect(_mode_label, 6.0)

	_apply_rect(_scroll, Rect2(0, 178, 614, 414), scale_factor)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.custom_minimum_size = (
		Vector2(614, 414) * scale_factor
	).round()
	_apply_rect(_content, Rect2(0, 0, 614, 414), scale_factor)
	var x_positions := [33.0, 220.0, 407.0]
	var selected_surface_rects := [
		Rect2(2, 0, 173, 114),
		Rect2(0, 0, 173, 114),
		Rect2(-1, 0, 174, 114),
		Rect2(2, -1, 173, 115),
		Rect2(0, -1, 173, 115),
		Rect2(-1, -1, 174, 115),
	]
	for index: int in range(_option_buttons.size()):
		var column := index % 3
		var row := index / 3
		_apply_rect(
			_option_buttons[index],
			Rect2(x_positions[column], 4 + row * 122, 174, 112),
			scale_factor
		)
		_option_selected_surfaces[index].texture = _wide_selected_option_frames[index]
		_apply_rect(
			_option_selected_surfaces[index],
			selected_surface_rects[index],
			scale_factor
		)
		_apply_rect(_option_icons[index], Rect2(18, 8, 138, 66), scale_factor)
		_apply_rect(_option_labels[index], Rect2(8, 72, 158, 36), scale_factor)
	_apply_rect(_description_section, Rect2(33, 247, 548, 80), scale_factor)
	_apply_rect(_description_label, Rect2(14, 3, 520, 74), scale_factor)
	_apply_rect(_places_section, Rect2(33, 334, 266, 41), scale_factor)
	_apply_rect(_places_label, Rect2(8, 1, 250, 39), scale_factor)
	_apply_rect(_resident_section, Rect2(315, 334, 266, 41), scale_factor)
	_apply_rect(_resident_label, Rect2(8, 1, 250, 39), scale_factor)
	_apply_rect(_feedback_section, Rect2(33, 382, 548, 32), scale_factor)
	_apply_rect(_feedback_label, Rect2(8, -2, 532, 36), scale_factor)
	_apply_rect(_cancel_mode_button, Rect2(447, 354, 126, 60), scale_factor)
	_apply_child_full_rect(
		_cancel_mode_button.get_node("CancelLabel") as Control
	)
	_apply_rect(_confirm_button, Rect2(66, 600, 482, 62), scale_factor)
	_apply_child_full_rect(_confirm_label)
	_apply_baked_composite_owner_styles()


func _apply_composite_font_tokens(wide: bool) -> void:
	_title_label.add_theme_font_size_override("font_size", 32 if wide else 40)
	_current_label.add_theme_font_size_override("font_size", 22 if wide else 26)
	_mode_label.add_theme_font_size_override("font_size", 20 if wide else 26)
	for label: Label in _option_labels:
		label.add_theme_font_size_override("font_size", 20 if wide else 26)
	_description_label.add_theme_font_size_override("font_size", 20 if wide else 26)
	_description_label.add_theme_constant_override("line_spacing", 0 if wide else 8)
	_places_label.add_theme_font_size_override("font_size", 20 if wide else 26)
	_places_label.add_theme_constant_override("line_spacing", 0 if wide else 8)
	_resident_label.add_theme_font_size_override("font_size", 20 if wide else 26)
	_resident_label.add_theme_constant_override("line_spacing", 0 if wide else 8)
	_feedback_label.add_theme_font_size_override("font_size", 20 if wide else 24)
	_feedback_label.add_theme_constant_override("line_spacing", 0 if wide else 8)
	_confirm_label.add_theme_font_size_override("font_size", 26 if wide else 40)
	var cancel_label := _cancel_mode_button.get_node("CancelLabel") as Label
	cancel_label.add_theme_font_size_override("font_size", 20 if wide else 26)
	var close_label := _close_button.get_node("CloseGlyph") as Label
	close_label.add_theme_font_size_override("font_size", 32 if wide else 40)


func _apply_baked_composite_owner_styles() -> void:
	var empty := StyleBoxEmpty.new()
	for panel: Panel in [
		_current_section,
		_mode_section,
		_description_section,
		_places_section,
		_resident_section,
		_feedback_section,
	]:
		panel.add_theme_stylebox_override("panel", empty)
	for button: Button in [
		_close_button,
		_confirm_button,
		_cancel_mode_button,
	]:
		for state: StringName in [
			&"normal",
			&"hover",
			&"pressed",
			&"focus",
			&"disabled",
		]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _refresh_copy_and_state() -> void:
	if _title_label == null:
		return
	var current := _render_data.get("currentWeather", {}) as Dictionary
	var mode := _render_data.get("mode", {}) as Dictionary
	if current.is_empty():
		_current_label.text = "当前天气不可用"
	elif _layout_mode in ["desktop_composite", "wide_composite"]:
		_current_label.text = "当前 · %s" % str(
			current.get("label", "—")
		)
	else:
		_current_label.text = str(current.get("label", "—"))
	var mode_copy := str(mode.get("label", "不可用"))
	if (
		_layout_mode in ["desktop_composite", "wide_composite"]
		and mode_copy.ends_with("模式")
	):
		mode_copy = mode_copy.trim_suffix("模式")
	_mode_label.text = mode_copy
	_set_icon(_current_icon, str(current.get("iconId", "")))

	var options := _weather_options()
	for index: int in range(_option_buttons.size()):
		var button := _option_buttons[index]
		if index >= options.size():
			button.visible = false
			continue
		button.visible = true
		var option := options[index]
		var option_id := str(option.get("id", ""))
		button.set_meta("weather_id", option_id)
		_option_labels[index].text = str(option.get("label", option_id))
		_set_icon(_option_icons[index], str(option.get("iconId", "")))

	if _selected_weather_id.is_empty() and not current.is_empty():
		_selected_weather_id = str(current.get("id", ""))
	var selected := _selected_option()
	var avatar_mode := str(mode.get("id", "")) == "avatar"
	if avatar_mode:
		_description_label.text = (
			"当前处于化身模式。切回俯瞰后，才能选择并确认小镇天气。"
		)
		_places_label.text = "当前天气 · %s" % str(
			current.get("label", "—")
		)
		_resident_label.text = "取消不会改变化身模式，也不会提交天气操作。"
	else:
		_description_label.text = (
			"天气效果 · %s" % str(selected.get("description", "暂无天气说明"))
		)
		var place_copy := _join_labels(
			selected.get("affectedPlaceLabels", [])
		)
		var resident_copy := str(
			selected.get("residentSummary", "暂无居民影响摘要")
		)
		if _layout_mode == "wide_composite":
			_places_label.text = place_copy
			_resident_label.text = resident_copy
		else:
			_places_label.text = "地点 · %s" % place_copy
			_resident_label.text = "居民 · %s" % resident_copy
	_apply_feedback_copy()

	var page_disabled := (
		str(_view_model.get("status", "")) == "disabled"
		or _render_data.is_empty()
	)
	var loading := _operation_status == &"loading"
	var error_retryable := _error_retryable()
	for index: int in range(_option_buttons.size()):
		if not _option_buttons[index].visible:
			continue
		var option := options[index]
		_option_buttons[index].disabled = (
			page_disabled
			or loading
			or avatar_mode
			or not bool(option.get("enabled", true))
		)
		_apply_option_style(index)

	var confirm_enabled := false
	if avatar_mode:
		var switch_action := ViewModel.action(
			_view_model,
			"switchToOverview"
		)
		var switch_intent := str(switch_action.get("intent", ""))
		var failed_switch := (
			_operation_status in [&"rejected", &"error"]
			and not switch_intent.is_empty()
			and _failed_intent == switch_intent
		)
		confirm_enabled = (
			not page_disabled
			and not loading
			and ViewModel.action_enabled(switch_action)
			and (
				not failed_switch
				or (_operation_status == &"error" and error_retryable)
			)
		)
		if loading:
			_confirm_label.text = "正在切回俯瞰……"
		elif failed_switch and _operation_status == &"error" and error_retryable:
			_confirm_label.text = "重试切回俯瞰"
		elif failed_switch:
			_confirm_label.text = "请取消后重试"
		else:
			_confirm_label.text = "切回俯瞰"
	else:
		var weather_action := ViewModel.action(_view_model, "weatherChange")
		var weather_intent := str(weather_action.get("intent", ""))
		var failed_same_draft := (
			_operation_status in [&"rejected", &"error"]
			and not weather_intent.is_empty()
			and _failed_intent == weather_intent
			and _failed_weather_id == _selected_weather_id
		)
		confirm_enabled = (
			not page_disabled
			and not loading
			and _draft_dirty
			and bool(selected.get("enabled", false))
			and ViewModel.action_enabled(weather_action)
			and (
				not failed_same_draft
				or (_operation_status == &"error" and error_retryable)
			)
		)
		if loading:
			_confirm_label.text = "正在确认……"
		elif failed_same_draft and _operation_status == &"error" and error_retryable:
			_confirm_label.text = "重试%s" % str(
				selected.get("label", "天气")
			)
		elif failed_same_draft:
			_confirm_label.text = "请选择其他天气"
		elif not _draft_dirty and not _selected_weather_id.is_empty():
			_confirm_label.text = "当前已是%s" % str(
				current.get("label", "该天气")
			)
		else:
			_confirm_label.text = "确认%s" % str(
				selected.get("label", "天气")
			)
	_confirm_button.disabled = not confirm_enabled
	_cancel_mode_button.visible = avatar_mode and not loading
	_confirm_label.add_theme_color_override(
		"font_color",
		PAPER_LIGHT if confirm_enabled else Color("#ead9b6")
	)
	_refresh_button_interaction_states()
	_fit_copy_to_slots()
	_wire_focus_neighbors()


func _apply_feedback_copy() -> void:
	var error_message := ViewModel.error_message(_view_model)
	var feedback := _as_dictionary(
		_render_data.get("lastConfirmedFeedback", null)
	)
	var copy := ""
	var color := MOSS
	match _operation_status:
		&"loading":
			copy = (
				"等待确认 · 当前天气保持不变"
				if _layout_mode == "wide_composite"
				else "正在等待确认；当前天气和 revision 保持不变。"
			)
			color = WOOD
		&"success":
			copy = str(feedback.get("summary", "天气操作已确认。"))
			var receipt := _as_dictionary(feedback.get("logReceipt", null))
			if bool(receipt.get("written", false)):
				copy += " · %s" % str(receipt.get("label", "已记入日志"))
		&"rejected":
			copy = "未修改 · %s" % (
				error_message if not error_message.is_empty() else "操作被拒绝。"
			)
			color = ERROR_COLOR
		&"error":
			copy = (
				error_message
				if not error_message.is_empty()
				else "暂时无法提交；当前天气保持不变。"
			)
			color = ERROR_COLOR
		&"disabled":
			copy = _disabled_copy()
			color = DISABLED_COLOR
		_:
			copy = (
				"请选择天气并查看影响说明。"
				if not _draft_dirty
				else "尚未提交 · 当前确认天气保持不变。"
			)
	if not _local_dispatch_error.is_empty():
		copy = _local_dispatch_error
		color = ERROR_COLOR
	if (
		not bool(_view_model.get("formalReady", true))
		and _layout_mode in ["desktop_composite", "wide_composite"]
	):
		copy = "占位数据 · %s" % copy
	_feedback_label.text = copy
	_feedback_label.add_theme_color_override("font_color", color)


func _disabled_copy() -> String:
	var action := ViewModel.action(_view_model, "weatherChange")
	var reason := ViewModel.disabled_reason(action)
	if reason.is_empty():
		reason = ViewModel.error_message(_view_model)
	return reason if not reason.is_empty() else "当前无法修改天气。"


func _fit_copy_to_slots() -> void:
	var wide := _layout_mode == "wide_composite"
	_fit_label_to_slot(
		_title_label,
		32 if wide else 40,
		MINIMUM_KEY_FONT_SIZE,
		Vector2(8, 4),
		false,
		wide,
	)
	_fit_label_to_slot(
		_current_label,
		22 if wide else 26,
		MINIMUM_KEY_FONT_SIZE,
		Vector2(8, 4),
		false,
		wide,
	)
	_fit_label_to_slot(
		_mode_label,
		20 if wide else 26,
		MINIMUM_KEY_FONT_SIZE,
		Vector2(6, 4),
		false,
		wide,
	)
	for index: int in range(_option_labels.size()):
		if not _option_buttons[index].visible:
			continue
		_fit_label_to_slot(
			_option_labels[index],
			20 if wide else 26,
			MINIMUM_KEY_FONT_SIZE,
			Vector2(4, 2),
			false,
			wide,
		)
	_fit_label_to_slot(
		_description_label,
		20 if wide else 26,
		MINIMUM_SUPPORT_FONT_SIZE if wide else MINIMUM_KEY_FONT_SIZE,
		Vector2(4, 3),
		true,
		wide,
	)
	_fit_label_to_slot(
		_places_label,
		20 if wide else 26,
		MINIMUM_SUPPORT_FONT_SIZE if wide else MINIMUM_KEY_FONT_SIZE,
		Vector2(2, 1),
		true,
		wide,
	)
	_fit_label_to_slot(
		_resident_label,
		20 if wide else 26,
		MINIMUM_SUPPORT_FONT_SIZE if wide else MINIMUM_KEY_FONT_SIZE,
		Vector2(2, 1),
		true,
		wide,
	)
	_fit_label_to_slot(
		_feedback_label,
		20 if wide else 24,
		MINIMUM_SUPPORT_FONT_SIZE if wide else MINIMUM_KEY_FONT_SIZE,
		Vector2(2, 1),
		true,
		wide,
	)
	_fit_label_to_slot(
		_confirm_label,
		26 if wide else 40,
		MINIMUM_KEY_FONT_SIZE,
		Vector2(8, 4),
		false,
		wide,
	)
	var cancel_label := _cancel_mode_button.get_node("CancelLabel") as Label
	_fit_label_to_slot(
		cancel_label,
		20 if wide else 26,
		MINIMUM_SUPPORT_FONT_SIZE if wide else MINIMUM_KEY_FONT_SIZE,
		Vector2(4, 2),
		false,
		wide,
	)
	var close_label := _close_button.get_node("CloseGlyph") as Label
	_fit_label_to_slot(
		close_label,
		32 if wide else 40,
		MINIMUM_KEY_FONT_SIZE,
		Vector2(4, 4),
		false,
		wide,
	)


func _fit_label_to_slot(
	label: Label,
	maximum_font_size: int,
	minimum_font_size: int,
	padding: Vector2,
	wrap: bool,
	layout_scaled: bool,
) -> void:
	if label == null:
		return
	label.clip_text = true
	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
		if wrap
		else TextServer.AUTOWRAP_OFF
	)
	label.max_lines_visible = -1
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var available_width := maxf(1.0, label.size.x - padding.x * 2.0)
	var available_height := maxf(1.0, label.size.y - padding.y * 2.0)
	var font := label.get_theme_font("font")
	var chosen_size := maximum_font_size
	var full_text_fits := label.text.is_empty()
	if font != null and not label.text.is_empty():
		for candidate_size: int in range(
			maximum_font_size,
			minimum_font_size - 1,
			-1
		):
			var measured := _measure_label_copy(
				label,
				font,
				candidate_size,
				available_width,
				wrap,
			)
			chosen_size = candidate_size
			if (
				measured.x <= available_width + 0.5
				and measured.y <= available_height + 0.5
			):
				full_text_fits = true
				break
	label.add_theme_font_size_override("font_size", chosen_size)
	if not full_text_fits:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if wrap and font != null:
			var line_spacing := label.get_theme_constant("line_spacing")
			var line_height := maxf(
				1.0,
				font.get_height(chosen_size) + float(line_spacing)
			)
			label.max_lines_visible = maxi(
				1,
				int(floor(available_height / line_height))
			)
		else:
			label.max_lines_visible = 1
		label.tooltip_text = label.text
	else:
		label.tooltip_text = ""
	label.set_meta("weather_text_fits", full_text_fits)
	label.set_meta(
		"weather_text_contained",
		full_text_fits
		or (
			label.clip_text
			and label.text_overrun_behavior
			== TextServer.OVERRUN_TRIM_ELLIPSIS
		)
	)
	label.set_meta(
		"weather_text_adaptive",
		layout_scaled or chosen_size < maximum_font_size,
	)


func _measure_label_copy(
	label: Label,
	font: Font,
	font_size: int,
	available_width: float,
	wrap: bool,
) -> Vector2:
	if not wrap:
		return Vector2(
			font.get_string_size(
				label.text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
			).x,
			font.get_height(font_size),
		)
	var measured := font.get_multiline_string_size(
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		available_width,
		font_size,
		-1,
	)
	var base_line_height := maxf(1.0, font.get_height(font_size))
	var line_count := maxi(1, int(ceil(measured.y / base_line_height)))
	measured.y += float(
		maxi(0, line_count - 1)
		* label.get_theme_constant("line_spacing")
	)
	return measured


func _apply_option_style(index: int) -> void:
	var button := _option_buttons[index]
	var selected := str(button.get_meta("weather_id", "")) == _selected_weather_id
	for state: StringName in [
		&"normal",
		&"hover",
		&"pressed",
		&"focus",
		&"disabled",
	]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_option_labels[index].add_theme_color_override(
		"font_color",
		DISABLED_COLOR if button.disabled else (PAPER_LIGHT if selected else INK)
	)
	_option_labels[index].add_theme_constant_override(
		"outline_size",
		0
	)
	_apply_button_interaction_state(button)


func _on_button_mouse_entered(button: Button) -> void:
	button.set_meta("weather_hovered", true)
	_apply_button_interaction_state(button)


func _on_button_mouse_exited(button: Button) -> void:
	button.set_meta("weather_hovered", false)
	_apply_button_interaction_state(button)


func _on_button_down(button: Button) -> void:
	button.set_meta("weather_pressed", true)
	_apply_button_interaction_state(button)


func _on_button_up(button: Button) -> void:
	button.set_meta("weather_pressed", false)
	_apply_button_interaction_state(button)


func _on_button_focus_changed(button: Button) -> void:
	_apply_button_interaction_state(button)


func _refresh_button_interaction_states() -> void:
	for button: Button in _option_buttons:
		_apply_button_interaction_state(button)
	for button: Button in [
		_close_button,
		_cancel_mode_button,
		_confirm_button,
	]:
		_apply_button_interaction_state(button)


func _apply_button_interaction_state(button: Button) -> void:
	if button == null:
		return
	var state := "normal"
	var modulation := BUTTON_NORMAL_MODULATE
	if button.disabled:
		state = "disabled"
		modulation = BUTTON_DISABLED_MODULATE
	elif bool(button.get_meta("weather_pressed", false)):
		state = "pressed"
		modulation = BUTTON_PRESSED_MODULATE
	elif button.has_focus():
		state = "focus"
		modulation = BUTTON_FOCUS_MODULATE
	elif bool(button.get_meta("weather_hovered", false)):
		state = "hover"
		modulation = BUTTON_HOVER_MODULATE
	button.self_modulate = modulation
	button.set_meta("weather_interaction_state", state)
	_sync_option_visual_state(button)


func _sync_option_visual_state(button: Button) -> void:
	var option_index := int(button.get_meta("option_index", -1))
	if option_index < 0 or option_index >= _option_buttons.size():
		return
	var selected := (
		str(button.get_meta("weather_id", "")) == _selected_weather_id
	)
	var highlighted := selected or bool(button.get_meta("weather_pressed", false))
	_option_selected_surfaces[option_index].visible = highlighted
	_option_icons[option_index].visible = false
	_option_labels[option_index].add_theme_color_override(
		"font_color",
		DISABLED_COLOR if button.disabled else (PAPER_LIGHT if highlighted else INK)
	)


func _button_interaction_snapshot(button: Button) -> Dictionary:
	if button == null:
		return {}
	return {
		"state": str(
			button.get_meta("weather_interaction_state", "normal")
		),
		"disabled": button.disabled,
		"modulate": button.self_modulate,
	}


func _on_option_pressed(index: int) -> void:
	if index < 0 or index >= _option_buttons.size():
		return
	var weather_id := str(
		_option_buttons[index].get_meta("weather_id", "")
	)
	if weather_id.is_empty():
		return
	_select_weather(weather_id)


func _select_weather(weather_id: String) -> void:
	_selected_weather_id = weather_id
	_draft_dirty = weather_id != _current_weather_id()
	_local_dispatch_error = ""
	_refresh_copy_and_state()
	selected_weather_changed.emit(weather_id)


func _on_confirm_pressed() -> void:
	if _dispatch_guard or _operation_status == &"loading":
		return
	var mode := _render_data.get("mode", {}) as Dictionary
	var intent := ""
	var payload: Dictionary = {}
	if str(mode.get("id", "")) == "avatar":
		var action := ViewModel.action(_view_model, "switchToOverview")
		if not ViewModel.action_enabled(action):
			return
		intent = str(action.get("intent", ""))
	else:
		if not _draft_dirty:
			return
		var action := ViewModel.action(_view_model, "weatherChange")
		if not ViewModel.action_enabled(action):
			return
		intent = str(action.get("intent", ""))
		payload = {"weatherId": _selected_weather_id}
	if intent.is_empty() or _adapter == null:
		return
	var source := str(
		_view_model.get("source", _render_data.get("source", ""))
	)
	var capability_mode := str(
		_view_model.get(
			"capabilityMode",
			_render_data.get("capabilityMode", ""),
		)
	)
	var internal_playtest := bool(_render_data.get("internalPlaytest", false))
	var runtime_development_allowed := (
		source == "runtime"
		and capability_mode == "development"
		and internal_playtest
	)
	if (
		not bool(_view_model.get("formalReady", true))
		and not runtime_development_allowed
	):
		_local_dispatch_error = (
			"开发运行数据缺少 internalPlaytest 授权，未向世界提交操作。"
			if source == "runtime"
			else "当前天气数据不可用，未向世界提交操作。"
		)
		_refresh_copy_and_state()
		return
	_last_submitted_intent = intent
	_last_submitted_weather_id = str(payload.get("weatherId", ""))
	_dispatch_guard = true
	dispatch_requested.emit(intent, payload.duplicate(true))
	var result: Variant = _adapter.call("dispatch", intent, payload)
	if result is Dictionary and not bool(
		(result as Dictionary).get("accepted", false)
	):
		_dispatch_guard = false
		_local_dispatch_error = ViewModel.player_reason(
			str(
				(result as Dictionary).get(
					"errorCode",
					"ACTION_REJECTED",
				)
			)
		)
		_refresh_copy_and_state()


func _update_failed_operation_state() -> void:
	var operation := ViewModel.operation(_view_model)
	var operation_intent := str(operation.get("intent", ""))
	match _operation_status:
		&"rejected", &"error":
			_failed_intent = operation_intent
			if operation_intent.begins_with("environment.weather_"):
				_failed_weather_id = (
					_last_submitted_weather_id
					if (
						_last_submitted_intent == operation_intent
						and not _last_submitted_weather_id.is_empty()
					)
					else _selected_weather_id
				)
			else:
				_failed_weather_id = ""
		&"idle", &"success", &"disabled":
			_failed_intent = ""
			_failed_weather_id = ""
			_last_submitted_intent = ""
			_last_submitted_weather_id = ""


func _error_retryable() -> bool:
	var error_value: Variant = _view_model.get("error", null)
	return (
		error_value is Dictionary
		and bool((error_value as Dictionary).get("retryable", false))
	)


func _close() -> void:
	request_back()


func _perform_close() -> void:
	closed.emit()
	hide()


func _weather_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for option_value: Variant in _render_data.get("weatherOptions", []):
		if option_value is Dictionary:
			result.append(option_value as Dictionary)
	return result


func _selected_option() -> Dictionary:
	for option: Dictionary in _weather_options():
		if str(option.get("id", "")) == _selected_weather_id:
			return option
	return {}


func _current_weather_id() -> String:
	var current := _render_data.get("currentWeather", {}) as Dictionary
	return str(current.get("id", ""))


func _set_icon(target: TextureRect, icon_id: String) -> void:
	if ICON_ATLAS_REGIONS.has(icon_id) and _icon_atlas != null:
		target.texture = _icon_atlas_texture(
			ICON_ATLAS_REGIONS[icon_id] as Rect2
		)
	else:
		target.texture = null


func _join_labels(value: Variant) -> String:
	var labels := PackedStringArray()
	if value is Array:
		for item: Variant in value:
			labels.append(str(item))
	return " · ".join(labels) if not labels.is_empty() else "暂无"


func _as_dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _wire_focus_neighbors() -> void:
	var visible_options: Array[Button] = []
	for button: Button in _option_buttons:
		if button.visible and not button.disabled:
			visible_options.append(button)
	var chain: Array[Control] = [_close_button]
	for button: Button in visible_options:
		chain.append(button)
	if _cancel_mode_button.visible:
		chain.append(_cancel_mode_button)
	if not _confirm_button.disabled:
		chain.append(_confirm_button)
	for index: int in range(chain.size()):
		var previous := chain[posmod(index - 1, chain.size())]
		var next := chain[(index + 1) % chain.size()]
		chain[index].focus_neighbor_top = chain[index].get_path_to(previous)
		chain[index].focus_neighbor_left = chain[index].get_path_to(previous)
		chain[index].focus_previous = chain[index].get_path_to(previous)
		chain[index].focus_neighbor_bottom = chain[index].get_path_to(next)
		chain[index].focus_neighbor_right = chain[index].get_path_to(next)
		chain[index].focus_next = chain[index].get_path_to(next)


func _panel_design_size() -> Vector2:
	return (
		DESKTOP_PANEL_SIZE
		if _layout_mode == "desktop_composite"
		else WIDE_PANEL_SIZE
	)


func _apply_rect(
	control: Control,
	rect: Rect2,
	layout_scale := Vector2.ONE,
) -> void:
	control.position = Vector2(
		roundf(rect.position.x * layout_scale.x),
		roundf(rect.position.y * layout_scale.y)
	)
	control.size = Vector2(
		roundf(maxf(1.0, rect.size.x * layout_scale.x)),
		roundf(maxf(1.0, rect.size.y * layout_scale.y))
	)


func _apply_child_full_rect(control: Control, inset := 0.0) -> void:
	_apply_rect(
		control,
		Rect2(
			inset,
			inset,
			maxf(1.0, control.get_parent().size.x - inset * 2.0),
			maxf(1.0, control.get_parent().size.y - inset * 2.0)
		)
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		request_back()
		get_viewport().set_input_as_handled()


func request_back() -> bool:
	if _draft_dirty:
		if is_instance_valid(_exit_confirmation) and not _exit_confirmation.visible:
			_exit_confirmation.popup_centered(Vector2i(620, 260))
		return true
	_perform_close()
	return true


func _build_exit_confirmation() -> void:
	if is_instance_valid(_exit_confirmation):
		return
	_exit_confirmation = FormalDialog.new()
	_exit_confirmation.name = "UnsavedWeatherConfirmation"
	_exit_confirmation.title = "放弃未确认的天气？"
	_exit_confirmation.dialog_text = "已经选择了新天气，但还没有确认应用。"
	_exit_confirmation.ok_button_text = "放弃并返回"
	_exit_confirmation.cancel_button_text = "继续选择"
	_exit_confirmation.confirmed.connect(_perform_close)
	add_child(_exit_confirmation)
