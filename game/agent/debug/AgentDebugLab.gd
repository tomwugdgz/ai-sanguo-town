class_name AgentDebugLab
extends Control


const SESSION := preload("res://agent/debug/AgentDebugSession.gd")
const BATCH := preload("res://agent/debug/DebugBatch.gd")
const MODEL_CATALOG := preload("res://agent/model/ModelProviderCatalog.gd")
const PROVIDER_SETTINGS := preload(
	"res://world/presentation/ui/TownProviderSettingsService.gd"
)
const TOWN_LOG_THEME := preload("res://ui/town_log/TownLogTheme.gd")
const CONVERSATION_SCENE := preload(
	"res://ui/conversation_unified/UnifiedConversationScreen.tscn"
)
const HEADER_TEXTURE := preload(
	"res://assets/ui/town_log/runtime/family/v4_reference_match/"
	+ "town_log_header_strip.png"
)
const JOURNAL_ICON := preload(
	"res://assets/ui/town_log/runtime/family/v3_imagegen/"
	+ "town_log_icon_journal.png"
)
const RESIDENT_ICON := preload(
	"res://assets/ui/town_log/runtime/family/v3_imagegen/"
	+ "town_log_icon_resident.png"
)
const PANEL_TEXTURE := preload(
	"res://assets/ui/town_log/runtime/family/v4_reference_match/"
	+ "town_log_panel_ninepatch.png"
)
const CONTROL_TEXTURE := preload(
	"res://assets/ui/town_log/runtime/family/v4_reference_match/"
	+ "town_log_control_normal.png"
)
const CONTROL_SELECTED_TEXTURE := preload(
	"res://assets/ui/town_log/runtime/family/v4_reference_match/"
	+ "town_log_control_selected.png"
)
const INK := Color("3f2818")
const MUTED_INK := Color("76583d")
const PAPER := Color("fff4d6")
const MAX_VISIBLE_TRACES := 500
const BATCH_SETTLE_TIMEOUT_MSEC := 120_000

var _catalog: RefCounted = MODEL_CATALOG.new()
var _batch: RefCounted = BATCH.new()
var _session: Node
var _providers: Array[Dictionary] = []
var _models: Array[Dictionary] = []
var _resident_rows: Array[Dictionary] = []
var _trace_rows: Array[Dictionary] = []
var _selected_resident_id := ""

var _provider_selector: OptionButton
var _model_selector: OptionButton
var _start_button: Button
var _status: Label
var _resident_list: ItemList
var _resident_count: Label
var _trace_list: ItemList
var _inspector: TextEdit
var _inspector_mode := "initialization"
var _manual_target: Label
var _manual_input: LineEdit
var _manual_button: Button
var _batch_editor: TextEdit
var _batch_result: TextEdit
var _batch_button: Button
var _save_view: TextEdit
var _save_button: Button
var _restore_button: Button
var _file_dialog: FileDialog
var _conversation: Control
var _batch_window: Window
var _save_window: Window
var _ui_host: Control


func _ready() -> void:
	get_window().title = "AI 小镇 · 居民观察台"
	theme = TOWN_LOG_THEME.create()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_interface()
	_load_providers()
	_batch_editor.text = JSON.stringify(_batch.call("example"), "\t")
	_set_status("尚未进入小镇")


func _build_interface() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 100
	add_child(ui_layer)
	_ui_host = Control.new()
	_ui_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_ui_host)
	var background := ColorRect.new()
	background.color = Color("302016")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_host.add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_ui_host.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	column.add_child(_build_header())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 330
	column.add_child(split)
	split.add_child(_build_resident_roster())
	split.add_child(_build_workspace())
	column.add_child(_build_action_dock())

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.json", "Campaign JSON")
	_file_dialog.file_selected.connect(_on_batch_file_selected)
	add_child(_file_dialog)
	_batch_window = _build_tool_window("文件批测", Vector2i(1320, 820), _build_batch_tab())
	add_child(_batch_window)
	_save_window = _build_tool_window("存档状态", Vector2i(1160, 760), _build_save_tab())
	add_child(_save_window)

	_conversation = CONVERSATION_SCENE.instantiate()
	_conversation.visible = false
	_conversation.close_requested.connect(func() -> void:
		_conversation.visible = false
	)
	_ui_host.add_child(_conversation)


func _build_header() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 92
	var header_style := StyleBoxTexture.new()
	header_style.texture = HEADER_TEXTURE
	header_style.texture_margin_left = 22
	header_style.texture_margin_top = 16
	header_style.texture_margin_right = 22
	header_style.texture_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", header_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = JOURNAL_ICON
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	var title := Label.new()
	title.text = "居民观察台"
	title.theme_type_variation = &"TownLogTitle"
	titles.add_child(title)
	_status = Label.new()
	_status.theme_type_variation = &"TownLogListTime"
	_status.add_theme_font_size_override("font_size", 15)
	titles.add_child(_status)
	_provider_selector = OptionButton.new()
	_provider_selector.custom_minimum_size.x = 180
	_provider_selector.item_selected.connect(_on_provider_selected)
	row.add_child(_provider_selector)
	_model_selector = OptionButton.new()
	_model_selector.custom_minimum_size.x = 220
	row.add_child(_model_selector)
	_start_button = Button.new()
	_start_button.theme_type_variation = &"TownLogAction"
	_start_button.text = "初始化 15 位居民"
	_start_button.pressed.connect(_start_session)
	row.add_child(_start_button)
	return panel


func _build_resident_roster() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	panel.add_theme_stylebox_override("panel", _paper_style(PANEL_TEXTURE, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var icon := TextureRect.new()
	icon.texture = RESIDENT_ICON
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading.add_child(icon)
	var label := Label.new()
	label.text = "居民名册"
	label.theme_type_variation = &"TownLogHeading"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	_resident_count = Label.new()
	_resident_count.text = "0 / 15"
	heading.add_child(_resident_count)
	_resident_list = ItemList.new()
	_resident_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_resident_list.allow_reselect = true
	_resident_list.item_selected.connect(_on_resident_selected)
	_style_item_list(_resident_list)
	column.add_child(_resident_list)
	return panel


func _build_workspace() -> Control:
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 430
	split.add_child(_build_trace_tab())
	split.add_child(_build_inspector())
	return split


func _build_inspector() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _paper_style(PANEL_TEXTURE, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "居民详情"
	heading.theme_type_variation = &"TownLogHeading"
	column.add_child(heading)
	var modes := HBoxContainer.new()
	column.add_child(modes)
	for mode_data: Dictionary in [
		{"id": "initialization", "label": "初始化"},
		{"id": "memory", "label": "记忆"},
		{"id": "wake", "label": "唤醒包"},
		{"id": "decision", "label": "Agent 返回"},
	]:
		var button := Button.new()
		button.text = String(mode_data["label"])
		button.theme_type_variation = &"TownLogFilter"
		button.custom_minimum_size.x = 92
		button.pressed.connect(_show_inspector.bind(String(mode_data["id"])))
		modes.add_child(button)
	_inspector = _code_view("选择居民或决策记录")
	column.add_child(_inspector)
	return panel


func _build_trace_tab() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 390
	panel.add_theme_stylebox_override("panel", _paper_style(PANEL_TEXTURE, 18))
	var column := VBoxContainer.new()
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "15 位居民决策时间线"
	heading.theme_type_variation = &"TownLogHeading"
	column.add_child(heading)
	_trace_list = ItemList.new()
	_trace_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_trace_list.item_selected.connect(_on_trace_selected)
	_style_item_list(_trace_list)
	column.add_child(_trace_list)
	return panel


func _build_action_dock() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 74
	panel.add_theme_stylebox_override("panel", _paper_style(PANEL_TEXTURE, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	_manual_target = Label.new()
	_manual_target.text = "先从左侧选择居民"
	_manual_target.theme_type_variation = &"TownLogHeading"
	_manual_target.custom_minimum_size.x = 240
	row.add_child(_manual_target)
	_manual_input = LineEdit.new()
	_manual_input.placeholder_text = "旅行者要说的话"
	_manual_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_manual_input.text_submitted.connect(func(_text: String) -> void:
		_begin_manual_conversation()
	)
	_style_line_edit(_manual_input)
	row.add_child(_manual_input)
	_manual_button = Button.new()
	_manual_button.theme_type_variation = &"TownLogAction"
	_manual_button.text = "打开游戏对话框"
	_manual_button.custom_minimum_size.x = 168
	_manual_button.disabled = true
	_manual_button.pressed.connect(_begin_manual_conversation)
	row.add_child(_manual_button)
	var batch_open := Button.new()
	batch_open.text = "文件批测"
	batch_open.theme_type_variation = &"TownLogAction"
	batch_open.custom_minimum_size.x = 108
	batch_open.pressed.connect(func() -> void: _batch_window.popup_centered())
	row.add_child(batch_open)
	var save_open := Button.new()
	save_open.text = "存档"
	save_open.theme_type_variation = &"TownLogAction"
	save_open.custom_minimum_size.x = 76
	save_open.pressed.connect(func() -> void: _save_window.popup_centered())
	row.add_child(save_open)
	return panel


func _build_tool_window(title_text: String, window_size: Vector2i, content: Control) -> Window:
	var window := Window.new()
	window.title = title_text
	window.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	window.size = window_size
	window.unresizable = false
	window.theme = theme
	window.visible = false
	window.close_requested.connect(window.hide)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(content)
	return window


func _build_batch_tab() -> Control:
	var column := VBoxContainer.new()
	column.name = "文件批测"
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var import_button := Button.new()
	import_button.theme_type_variation = &"TownLogAction"
	import_button.text = "选择 JSON"
	import_button.pressed.connect(func() -> void: _file_dialog.popup_centered_ratio(0.72))
	actions.add_child(import_button)
	_batch_button = Button.new()
	_batch_button.theme_type_variation = &"TownLogAction"
	_batch_button.text = "运行 Campaign"
	_batch_button.pressed.connect(_run_campaign)
	actions.add_child(_batch_button)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 350
	column.add_child(split)
	_batch_editor = _code_view("")
	_batch_editor.editable = true
	split.add_child(_labeled_view("输入", _batch_editor))
	_batch_result = _code_view("等待运行")
	split.add_child(_labeled_view("输出", _batch_result))
	return column


func _build_save_tab() -> Control:
	var column := VBoxContainer.new()
	column.name = "存档"
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_save_button = Button.new()
	_save_button.theme_type_variation = &"TownLogAction"
	_save_button.text = "保存当前世界"
	_save_button.disabled = true
	_save_button.pressed.connect(_create_save)
	actions.add_child(_save_button)
	_restore_button = Button.new()
	_restore_button.theme_type_variation = &"TownLogAction"
	_restore_button.text = "恢复最近保存"
	_restore_button.disabled = true
	_restore_button.pressed.connect(_restore_save)
	actions.add_child(_restore_button)
	_save_view = _code_view("尚未初始化会话")
	column.add_child(_save_view)
	return column


func _code_view(placeholder: String) -> TextEdit:
	var view := TextEdit.new()
	view.placeholder_text = placeholder
	view.editable = false
	view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.add_theme_color_override("font_color", INK)
	view.add_theme_color_override("font_readonly_color", INK)
	view.add_theme_color_override("font_placeholder_color", MUTED_INK)
	view.add_theme_color_override("caret_color", INK)
	view.add_theme_color_override("selection_color", Color("dca45c80"))
	view.add_theme_font_size_override("font_size", 15)
	view.add_theme_stylebox_override("normal", _flat_paper_style())
	view.add_theme_stylebox_override("read_only", _flat_paper_style())
	return view


func _style_item_list(list: ItemList) -> void:
	list.add_theme_color_override("font_color", INK)
	list.add_theme_color_override("font_selected_color", Color("fff8e6"))
	list.add_theme_font_size_override("font_size", 15)
	list.add_theme_stylebox_override("panel", _flat_paper_style())
	list.add_theme_stylebox_override(
		"selected",
		_paper_style(CONTROL_SELECTED_TEXTURE, 8),
	)
	list.add_theme_stylebox_override(
		"selected_focus",
		_paper_style(CONTROL_SELECTED_TEXTURE, 8),
	)


func _style_line_edit(line: LineEdit) -> void:
	line.add_theme_color_override("font_color", INK)
	line.add_theme_color_override("font_placeholder_color", MUTED_INK)
	line.add_theme_color_override("caret_color", INK)
	line.add_theme_font_size_override("font_size", 16)
	line.add_theme_stylebox_override("normal", _flat_paper_style(8))
	line.add_theme_stylebox_override("focus", _paper_style(CONTROL_SELECTED_TEXTURE, 8))


func _paper_style(texture: Texture2D, margin: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = margin
	style.texture_margin_top = margin
	style.texture_margin_right = margin
	style.texture_margin_bottom = margin
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	return style


func _flat_paper_style(margin := 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = Color("7f4c28")
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	return style


func _labeled_view(title_text: String, view: Control) -> Control:
	var column := VBoxContainer.new()
	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"TownLogHeading"
	column.add_child(title)
	column.add_child(view)
	return column


func _load_providers() -> void:
	_providers.assign(_catalog.call("list_providers"))
	_provider_selector.clear()
	for provider: Dictionary in _providers:
		_provider_selector.add_item(String(provider.get("label", provider.get("id", ""))))
		_provider_selector.set_item_metadata(
			_provider_selector.item_count - 1,
			String(provider.get("id", "")),
		)
	var settings: RefCounted = PROVIDER_SETTINGS.new()
	var saved_runtime := (
		settings.call("load_saved_runtime_configuration") as Dictionary
	)
	var default_id := String(saved_runtime.get("providerId", "")).strip_edges()
	if default_id.is_empty():
		default_id = String(_catalog.call("default_provider_id"))
	for index in _provider_selector.item_count:
		if String(_provider_selector.get_item_metadata(index)) == default_id:
			_provider_selector.select(index)
	_refresh_models(
		_selected_provider(),
		String(saved_runtime.get("modelId", "")),
	)


func _on_provider_selected(_index: int) -> void:
	_refresh_models(_selected_provider())


func _refresh_models(provider_id: String, preferred_model_id := "") -> void:
	_models.assign(_catalog.call("list_models", provider_id))
	_model_selector.clear()
	for model: Dictionary in _models:
		_model_selector.add_item(String(model.get("label", model.get("id", ""))))
		_model_selector.set_item_metadata(
			_model_selector.item_count - 1,
			String(model.get("id", "")),
		)
		if String(model.get("id", "")) == preferred_model_id:
			_model_selector.select(_model_selector.item_count - 1)


func _selected_provider() -> String:
	if _provider_selector.selected < 0:
		return ""
	return String(_provider_selector.get_item_metadata(_provider_selector.selected))


func _selected_model() -> String:
	if _model_selector.selected < 0:
		return ""
	return String(_model_selector.get_item_metadata(_model_selector.selected))


func _start_session(slot_id := "") -> void:
	if is_instance_valid(_session):
		_session.stop()
		_session.queue_free()
	_session = SESSION.new()
	_session.state_changed.connect(_on_session_state)
	_session.trace_added.connect(_on_trace_added)
	add_child(_session)
	_start_button.disabled = true
	_set_status("正在按游戏流程初始化世界…")
	var result := _session.call(
		"start_new",
		_selected_provider(),
		_selected_model(),
		slot_id,
	) as Dictionary
	if not bool(result.get("ok", false)) and not bool(result.get("accepted", false)):
		_set_status(_session_error_text(result), true)
		_start_button.disabled = false


func _on_session_state(snapshot: Dictionary) -> void:
	var status_value := String(snapshot.get("status", "idle"))
	var error := snapshot.get("error", {}) as Dictionary
	var status_text := String({
		"idle": "尚未进入小镇",
		"checking_provider": "正在检查 Provider 与模型连接…",
		"starting": "正在初始化世界与居民…",
		"restoring": "正在恢复 World 与 Agent 保存点…",
		"running": "世界运行中 · Agent 正式链路",
		"error": _session_error_text(error),
	}.get(status_value, status_value))
	_set_status(status_text, status_value == "error")
	var busy := status_value in ["checking_provider", "starting", "restoring"]
	_start_button.disabled = busy
	_start_button.text = (
		"正在检查连接…"
		if status_value == "checking_provider"
		else "正在初始化…"
		if status_value == "starting"
		else "初始化 15 位居民"
	)
	_resident_rows.assign(snapshot.get("residents", []))
	_resident_count.text = "%d / 15" % _resident_rows.size()
	_refresh_resident_list()
	_refresh_trace_list()
	var running := status_value == "running"
	_manual_button.disabled = not running or _selected_resident_id.is_empty()
	_save_button.disabled = not running
	var save := snapshot.get("save", {}) as Dictionary
	_restore_button.disabled = not running or (save.get("manifests", []) as Array).is_empty()
	_save_view.text = JSON.stringify(save, "\t")


func _refresh_resident_list() -> void:
	var previous := _selected_resident_id
	_resident_list.clear()
	var selected_index := -1
	for index in _resident_rows.size():
		var row := _resident_rows[index]
		var memory := row.get("memory", {}) as Dictionary
		var binding := row.get("binding", {}) as Dictionary
		var llm := binding.get("llmBinding", {}) as Dictionary
		_resident_list.add_item("%s\n%s · %s" % [
			String(row.get("residentName", row.get("residentId", ""))),
			String(llm.get("providerId", "")),
			_memory_badge(memory),
		])
		_resident_list.set_item_metadata(index, String(row.get("residentId", "")))
		if String(row.get("residentId", "")) == previous:
			selected_index = index
	if selected_index < 0 and not _resident_rows.is_empty():
		selected_index = 0
	if selected_index >= 0:
		_resident_list.select(selected_index)
		_on_resident_selected(selected_index)


func _memory_badge(memory: Dictionary) -> String:
	return "%d 条证据" % int(memory.get("evidence_item_count", 0))


func _on_resident_selected(index: int) -> void:
	if index < 0 or index >= _resident_rows.size():
		return
	_selected_resident_id = String(_resident_rows[index].get("residentId", ""))
	var debug := _session.call(
		"resident_debug_snapshot",
		_selected_resident_id,
	) as Dictionary
	_manual_target.text = "旅行者 → %s" % String(debug.get("resident_name", ""))
	_manual_button.disabled = String((_session.call("snapshot") as Dictionary).get("status", "")) != "running"
	_show_inspector(_inspector_mode)


func _on_trace_added(trace: Dictionary) -> void:
	_trace_rows.append(trace.duplicate(true))
	_trace_list.add_item(_trace_label(trace))
	if _trace_rows.size() > MAX_VISIBLE_TRACES:
		_trace_rows.pop_front()
		_trace_list.remove_item(0)
	var latest_index := _trace_rows.size() - 1
	_trace_list.select(latest_index)
	if String(trace.get("residentId", "")) == _selected_resident_id:
		_show_inspector(_inspector_mode)


func _refresh_trace_list() -> void:
	if not is_instance_valid(_session):
		return
	var all_traces: Array = _session.call("traces")
	var first := maxi(0, all_traces.size() - MAX_VISIBLE_TRACES)
	_trace_rows.assign(all_traces.slice(first))
	_trace_list.clear()
	for trace: Dictionary in _trace_rows:
		_trace_list.add_item(_trace_label(trace))
	if not _trace_rows.is_empty():
		_trace_list.select(_trace_rows.size() - 1)


func _trace_label(trace: Dictionary) -> String:
	return "%s  %s\n%s" % [
		"完成" if String(trace.get("phase", "")) == "completed" else "请求",
		String(trace.get("residentName", "")),
		String(trace.get("decisionId", "")),
	]


func _on_trace_selected(index: int) -> void:
	if index < 0 or index >= _trace_rows.size():
		return
	var trace := _trace_rows[index]
	_selected_resident_id = String(trace.get("residentId", ""))
	for resident_index in _resident_list.item_count:
		if String(_resident_list.get_item_metadata(resident_index)) == _selected_resident_id:
			_resident_list.select(resident_index)
			break
	_inspector_mode = "decision"
	_manual_target.text = "旅行者 → %s" % String(trace.get("residentName", ""))
	_show_inspector("decision")


func _show_inspector(mode: String) -> void:
	_inspector_mode = mode
	if _inspector == null or not is_instance_valid(_session) or _selected_resident_id.is_empty():
		return
	var debug := _session.call(
		"resident_debug_snapshot",
		_selected_resident_id,
	) as Dictionary
	var selected_trace: Dictionary = {}
	var selected := _trace_list.get_selected_items()
	if not selected.is_empty() and selected[0] < _trace_rows.size():
		var candidate := _trace_rows[selected[0]] as Dictionary
		if String(candidate.get("residentId", "")) == _selected_resident_id:
			selected_trace = candidate
	if selected_trace.is_empty():
		var resident_traces: Array = _session.call("traces", _selected_resident_id)
		if not resident_traces.is_empty():
			selected_trace = resident_traces.back() as Dictionary
	var value: Variant
	match mode:
		"memory":
			value = debug.get("memory", {})
		"wake":
			value = selected_trace.get("wakePacket", {})
		"decision":
			value = {
				"decisionId": selected_trace.get("decisionId", ""),
				"agentResult": selected_trace.get("agentResult", {}),
				"worldSubmission": selected_trace.get("worldSubmission", {}),
				"provider": (
					(selected_trace.get("debugSnapshot", {}) as Dictionary).get(
						"provider",
						debug.get("provider", {}),
					)
				),
			}
		_:
			value = debug.get("initialization", {})
	_inspector.text = JSON.stringify(value, "\t")


func _begin_manual_conversation() -> void:
	var say := _manual_input.text.strip_edges()
	if say.is_empty() or _selected_resident_id.is_empty():
		return
	var result := _session.call(
		"begin_avatar_conversation",
		_selected_resident_id,
		say,
	) as Dictionary
	if not bool(result.get("ok", false)):
		_set_status("对话未开始：%s" % String(result.get("errorCode", result.get("reason", ""))))
		return
	_manual_input.clear()
	var adapter: Node = _session.call("conversation_adapter")
	_conversation.call("bind_town_ui_adapter", adapter)
	_conversation.visible = true
	_conversation.call("focus_default_control")


func _on_batch_file_selected(path: String) -> void:
	var result := _batch.call("load_file", path) as Dictionary
	if not bool(result.get("ok", false)):
		_batch_result.text = JSON.stringify(result, "\t")
		return
	_batch_editor.text = JSON.stringify({
		"schema": BATCH.SCHEMA,
		"campaign_id": result.get("campaignId", ""),
		"mode": result.get("mode", "continuous"),
		"runs": result.get("runs", []),
	}, "\t")
	_batch_result.text = "已载入 %d 组测试" % (result.get("runs", []) as Array).size()


func _run_campaign() -> void:
	var value: Variant = JSON.parse_string(_batch_editor.text)
	var campaign := _batch.call("parse", value) as Dictionary
	if not bool(campaign.get("ok", false)):
		_batch_result.text = JSON.stringify(campaign, "\t")
		return
	_batch_button.disabled = true
	_execute_campaign(campaign)


func _execute_campaign(campaign: Dictionary) -> void:
	var mode := String(campaign.get("mode", "continuous"))
	var outputs: Array[Dictionary] = []
	for run_value: Variant in campaign.get("runs", []) as Array:
		var run := run_value as Dictionary
		if mode == "isolated":
			_start_session()
			if not await _wait_for_session():
				outputs.append({"id": run.get("id", ""), "ok": false, "error": "启动超时"})
				continue
		elif not is_instance_valid(_session) or (
			String((_session.call("snapshot") as Dictionary).get("status", "")) != "running"
		):
			_start_session()
			if not await _wait_for_session():
				outputs.append({"id": run.get("id", ""), "ok": false, "error": "启动超时"})
				continue
		if not await _wait_for_quiet():
			outputs.append({
				"id": run.get("id", ""),
				"ok": false,
				"errorCode": "DEBUG_BATCH_BASELINE_TIMEOUT",
				"actions": [],
				"traces": [],
			})
			continue
		var before := int(_session.call("trace_count"))
		var action_results: Array[Dictionary] = []
		var settled := true
		for action_value: Variant in run.get("actions", []) as Array:
			var action_result := _session.call(
				"perform_action",
				action_value as Dictionary,
			) as Dictionary
			action_results.append(action_result.duplicate(true))
			await get_tree().create_timer(0.15).timeout
			if not await _wait_for_quiet():
				settled = false
				break
		outputs.append({
			"id": run.get("id", ""),
			"ok": _all_ok(action_results) and settled,
			"errorCode": "" if settled else "DEBUG_BATCH_SETTLE_TIMEOUT",
			"actions": action_results,
			"traces": _session.call("traces_from", before),
		})
		_batch_result.text = "已完成 %d / %d 组测试" % [
			outputs.size(),
			(campaign.get("runs", []) as Array).size(),
		]
	_batch_result.text = JSON.stringify(outputs, "\t")
	_batch_button.disabled = false


func _wait_for_session() -> bool:
	for _index in 240:
		if not is_instance_valid(_session):
			return false
		var status_value := String(
			(_session.call("snapshot") as Dictionary).get("status", ""),
		)
		if status_value == "running":
			return true
		if status_value == "error":
			return false
		await get_tree().process_frame
	return false


func _wait_for_quiet() -> bool:
	var stable_frames := 0
	var previous_trace_count := -1
	var deadline := Time.get_ticks_msec() + BATCH_SETTLE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		var current := int(_session.call("trace_count"))
		var pending := int(_session.call("pending_decision_count"))
		if current == previous_trace_count and pending == 0:
			stable_frames += 1
		else:
			stable_frames = 0
			previous_trace_count = current
		if stable_frames >= 20:
			return true
		await get_tree().process_frame
	return false


func _all_ok(results: Array[Dictionary]) -> bool:
	for result: Dictionary in results:
		if not bool(result.get("ok", false)):
			return false
	return true


func _create_save() -> void:
	var result := _session.call("create_save") as Dictionary
	_save_view.text = JSON.stringify({
		"result": result,
		"status": _session.call("save_snapshot"),
	}, "\t")


func _restore_save() -> void:
	var result := _session.call("restore_latest") as Dictionary
	_save_view.text = JSON.stringify({
		"result": result,
		"status": _session.call("save_snapshot"),
	}, "\t")


func _set_status(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override(
		"font_color",
		Color("a6291e") if is_error else INK,
	)


func _session_error_text(error: Dictionary) -> String:
	var error_code := String(error.get("errorCode", "UNKNOWN_ERROR"))
	var message := String({
		"LLM_PROVIDER_CONFIGURATION_INVALID": "Provider 配置无效",
		"PROVIDER_HEALTH_UNAVAILABLE": "Provider 或模型连接失败",
		"SESSION_LLM_BINDINGS_INVALID": "居民模型绑定无效",
		"LLM_MODEL_UNKNOWN": "模型不在当前目录中",
	}.get(error_code, "会话启动失败"))
	return "%s（%s）" % [message, error_code]
