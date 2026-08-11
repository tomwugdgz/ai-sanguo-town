# PROTOTYPE - NOT FOR PRODUCTION
# Question: Can reviewers enter the Agent debug lab from one stable title screen?
# Date: 2026-07-14
extends Control

const AGENT_DEBUG_PATH := "res://agent/debug/AgentDebugLab.tscn"

var _agent_debug_button := Button.new()
var _status_label := Label.new()


func _ready() -> void:
	_build_ui()
	_update_availability()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_1:
		_open_demo(AGENT_DEBUG_PATH, "Agent DEBUGUI")


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("101820")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var accent := ColorRect.new()
	accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	accent.size.y = 8.0
	accent.color = Color("55c795")
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(accent)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(1660.0, 760.0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)

	var title := Label.new()
	title.text = "AI 小镇 · Demo 验证入口"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color("f4fbf7"))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Agent 调试从这里进入"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color("aebfba"))
	column.add_child(subtitle)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 28)
	column.add_child(cards)
	_agent_debug_button = _make_demo_button(
		"1　Agent DEBUGUI\n\n调试存档 · 连续唤醒 · 文件批处理\n模型调用 · 记忆整理 · 历史与检查点",
		Color("c4874e")
	)
	_agent_debug_button.pressed.connect(_open_demo.bind(AGENT_DEBUG_PATH, "Agent DEBUGUI"))
	cards.add_child(_agent_debug_button)

	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 19)
	_status_label.add_theme_color_override("font_color", Color("f3d486"))
	column.add_child(_status_label)

	var exit_button := Button.new()
	exit_button.text = "退出游戏"
	exit_button.custom_minimum_size = Vector2(260.0, 54.0)
	exit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	exit_button.add_theme_font_size_override("font_size", 20)
	exit_button.pressed.connect(_quit_game)
	column.add_child(exit_button)

	var footer := Label.new()
	footer.text = "点击卡片或按 1 进入　·　F10 或右上角按钮返回　·　Esc 退出游戏"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 18)
	footer.add_theme_color_override("font_color", Color("81918d"))
	column.add_child(footer)


func _make_demo_button(text_value: String, accent_color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(520.0, 270.0)
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", Color("f4fbf7"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("66706d"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("1a2826")
	normal.border_color = accent_color
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(18)
	normal.content_margin_left = 34.0
	normal.content_margin_right = 34.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent_color.darkened(0.42)
	hover.border_color = accent_color.lightened(0.18)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = accent_color.darkened(0.58)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("171d1c")
	disabled.border_color = Color("424b49")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	return button


func _update_availability() -> void:
	_agent_debug_button.disabled = not ResourceLoader.exists(AGENT_DEBUG_PATH, "PackedScene")
	if _agent_debug_button.disabled:
		_status_label.text = "不可用的入口会自动禁用"
	else:
		_status_label.text = "Agent 调试入口已就绪"


func _open_demo(scene_path: String, display_name: String) -> void:
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		_status_label.text = "%s 尚未合入当前分支" % display_name
		return
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		_status_label.text = "%s 启动失败：%s" % [display_name, error_string(error)]


func _quit_game() -> void:
	get_tree().quit()
