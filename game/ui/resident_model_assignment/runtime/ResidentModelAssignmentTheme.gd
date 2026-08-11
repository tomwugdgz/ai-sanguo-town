class_name ResidentModelAssignmentTheme
extends RefCounted


const FONT_PATH := (
	"res://assets/fonts/zheng_ge_dian_hei_16/"
	+ "ZhengGeDianHei-16.ttf"
)

const INK := Color("3f2818")
const INK_MUTED := Color("72563e")
const PAPER := Color("f4d59e")
const PAPER_LIGHT := Color("ffe8b9")
const PAPER_DARK := Color("d5ad72")
const WOOD := Color("6e3e20")
const WOOD_DARK := Color("2f1b10")
const WOOD_LIGHT := Color("a86832")
const MOSS := Color("5f722b")
const MOSS_DARK := Color("36431d")
const TERRACOTTA := Color("a93e25")
const TERRACOTTA_DARK := Color("632416")
const HONEY := Color("e0a23e")
const BLUE := Color("2e6885")
const BLUE_DARK := Color("173d51")
const DISABLED := Color("aa9674")
const OVERLAY := Color("16100bd0")
const SHADOW := Color("170d0866")


static func create() -> Theme:
	var result := Theme.new()
	var font := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if font != null:
		result.default_font = font
	result.default_font_size = 18
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "Button", INK)
	result.set_color("font_hover_color", "Button", INK)
	result.set_color("font_pressed_color", "Button", INK)
	result.set_color("font_focus_color", "Button", INK)
	result.set_color("font_disabled_color", "Button", Color(INK_MUTED, 0.82))
	result.set_constant("outline_size", "Label", 0)
	result.set_constant("line_spacing", "Label", 4)
	return result


static func page_shell() -> StyleBoxFlat:
	var style := _style(PAPER, WOOD_DARK, 8, 24)
	style.shadow_color = SHADOW
	style.shadow_size = 12
	style.shadow_offset = Vector2(8, 10)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


static func section(accent: Color = WOOD) -> StyleBoxFlat:
	var style := _style(Color("e8c386"), accent, 4, 16)
	style.shadow_color = Color(SHADOW, 0.35)
	style.shadow_size = 3
	style.shadow_offset = Vector2(3, 3)
	return style


static func inset(tone := "normal") -> StyleBoxFlat:
	var border := WOOD
	var background := PAPER_LIGHT
	match tone:
		"success":
			border = MOSS
			background = Color("e4d89a")
		"warning":
			border = TERRACOTTA
			background = Color("efc08b")
		"selected":
			border = HONEY
			background = Color("f7daa2")
		"disabled":
			border = DISABLED
			background = Color("cbb58e")
	return _style(background, border, 3, 12)


static func button(variant := "paper", state := "normal") -> StyleBoxFlat:
	var background := PAPER_LIGHT
	var border := WOOD
	match variant:
		"primary":
			background = TERRACOTTA
			border = TERRACOTTA_DARK
		"success":
			background = MOSS
			border = MOSS_DARK
		"blue":
			background = BLUE
			border = BLUE_DARK
		"quiet":
			background = Color("e3c28d")
			border = WOOD_LIGHT
	match state:
		"hover":
			background = background.lightened(0.09)
			border = HONEY
		"pressed":
			background = background.darkened(0.11)
		"focus":
			border = HONEY
		"disabled":
			background = Color("b9a17c")
			border = DISABLED
	var style := _style(background, border, 3 if state != "focus" else 5, 10)
	if state == "pressed":
		style.content_margin_top = 13
		style.content_margin_bottom = 7
	return style


static func progress_background() -> StyleBoxFlat:
	return _style(PAPER_DARK, WOOD_DARK, 3, 0)


static func progress_fill() -> StyleBoxFlat:
	return _style(MOSS, MOSS_DARK, 3, 0)


static func apply_button(button_control: Button, variant := "paper") -> void:
	button_control.add_theme_stylebox_override("normal", button(variant, "normal"))
	button_control.add_theme_stylebox_override("hover", button(variant, "hover"))
	button_control.add_theme_stylebox_override("pressed", button(variant, "pressed"))
	button_control.add_theme_stylebox_override("focus", button(variant, "focus"))
	button_control.add_theme_stylebox_override("disabled", button(variant, "disabled"))
	button_control.add_theme_color_override(
		"font_color",
		Color.WHITE if variant in ["primary", "success", "blue"] else INK,
	)
	button_control.add_theme_color_override(
		"font_hover_color",
		Color.WHITE if variant in ["primary", "success", "blue"] else INK,
	)
	button_control.add_theme_color_override(
		"font_pressed_color",
		Color.WHITE if variant in ["primary", "success", "blue"] else INK,
	)
	button_control.add_theme_color_override("font_disabled_color", Color("756750"))


static func _style(
	background: Color,
	border: Color,
	border_width: int,
	content_margin: int,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(2)
	style.anti_aliasing = false
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style
