extends RefCounted


# UiKit 种子(H 之 4):不可见扁平按钮工厂——热区/导航按钮的两对孪生收敛。
# 属性设置顺序与原实现存在无观察差异的重排(挂树前的独立属性赋值)。

static func invisible_flat_button(tooltip: String) -> Button:
	var button := Button.new()
	button.text = ""
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = tooltip
	var empty := StyleBoxEmpty.new()
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state_name, empty)
	return button


static func invisible_nav_button(
	canvas: Node,
	node_name: String,
	rect: Rect2,
	tooltip: String,
) -> Button:
	var button := invisible_flat_button(tooltip)
	button.name = StringName(node_name)
	button.position = rect.position.round()
	button.size = rect.size.round()
	canvas.add_child(button)
	return button


static func apply_disabled_state(control: Control, disabled: bool) -> void:
	control.focus_mode = (
		Control.FOCUS_NONE
		if disabled
		else Control.FOCUS_ALL
	)
	control.mouse_filter = Control.MOUSE_FILTER_STOP
