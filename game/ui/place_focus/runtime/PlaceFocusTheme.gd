class_name PlaceFocusTheme
extends RefCounted


const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)

const INK := Color("#3b2418")
const MUTED_INK := Color("#5f4938")
const HONEY := Color("#f0b94b")
const ERROR := Color("#8b3329")


static func create() -> Theme:
	var theme := Theme.new()
	var base_font := load(FONT_PATH) as Font
	if base_font == null:
		push_error("PlaceFocusTheme 无法加载公共字体 v6。")
		return theme
	var regular := _font(base_font, 0.0)
	var medium := _font(base_font, 0.125)
	var strong := _font(base_font, 0.25)
	theme.default_font = regular
	theme.default_font_size = 20

	_label(theme, &"PlaceFocus1080Title", strong, 48, INK, 4)
	_label(theme, &"PlaceFocus1080Event", medium, 28, INK, 4)
	_label(theme, &"PlaceFocus1080Section", medium, 24, INK, 2)
	_label(theme, &"PlaceFocus1080Body", regular, 24, INK, 2)
	_label(theme, &"PlaceFocus1080Compact", regular, 20, INK, 2)
	_label(theme, &"PlaceFocus1080Muted", regular, 20, MUTED_INK, 2)
	_label(theme, &"PlaceFocus1080Enter", medium, 32, MUTED_INK, 2)
	_label(theme, &"PlaceFocus1080Error", medium, 20, ERROR, 2)

	_label(theme, &"PlaceFocus720Title", strong, 32, INK, 3)
	_label(theme, &"PlaceFocus720Event", medium, 20, INK, 2)
	_label(theme, &"PlaceFocus720Section", medium, 18, INK, 2)
	_label(theme, &"PlaceFocus720Body", regular, 18, INK, 2)
	_label(theme, &"PlaceFocus720Compact", regular, 16, INK, 2)
	_label(theme, &"PlaceFocus720Enter", medium, 24, MUTED_INK, 2)
	_rich_text(theme, &"PlaceFocus1080Feedback", regular, 20, MUTED_INK)
	_rich_text(theme, &"PlaceFocus1080FeedbackError", medium, 20, ERROR)
	_rich_text(theme, &"PlaceFocus720Feedback", regular, 16, MUTED_INK)
	_rich_text(theme, &"PlaceFocus720FeedbackError", medium, 16, ERROR)

	_button(theme, &"PlaceFocusRightSubmenuHit", regular, 20)
	_toggle_button(theme, &"PlaceFocusPanelToggle", medium, 18)
	return theme


static func _font(base_font: Font, embolden: float) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base_font
	variation.spacing_glyph = 2
	variation.variation_embolden = embolden
	return variation


static func _label(
	theme: Theme,
	type_name: StringName,
	font: Font,
	font_size: int,
	color: Color,
	line_spacing: int
) -> void:
	theme.set_type_variation(type_name, &"Label")
	theme.set_font(&"font", type_name, font)
	theme.set_font_size(&"font_size", type_name, font_size)
	theme.set_color(&"font_color", type_name, color)
	theme.set_constant(&"outline_size", type_name, 0)
	theme.set_constant(&"line_spacing", type_name, line_spacing)


static func _button(theme: Theme, type_name: StringName, font: Font, font_size: int) -> void:
	theme.set_type_variation(type_name, &"Button")
	theme.set_font(&"font", type_name, font)
	theme.set_font_size(&"font_size", type_name, font_size)
	theme.set_color(&"font_color", type_name, Color.TRANSPARENT)
	theme.set_color(&"font_hover_color", type_name, Color.TRANSPARENT)
	theme.set_color(&"font_pressed_color", type_name, Color.TRANSPARENT)
	theme.set_color(&"font_focus_color", type_name, Color.TRANSPARENT)
	theme.set_stylebox(&"normal", type_name, _hit_style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	theme.set_stylebox(&"disabled", type_name, _hit_style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	# These Buttons are transparent interaction owners placed over artwork.
	# Drawing any state box exposes the full hit rectangle as a yellow
	# "safe-area" frame, so every state stays visually empty.
	for state: StringName in [
		&"normal",
		&"disabled",
		&"hover",
		&"pressed",
		&"focus",
	]:
		theme.set_stylebox(state, type_name, StyleBoxEmpty.new())


static func _toggle_button(
	theme: Theme,
	type_name: StringName,
	font: Font,
	font_size: int,
) -> void:
	theme.set_type_variation(type_name, &"Button")
	theme.set_font(&"font", type_name, font)
	theme.set_font_size(&"font_size", type_name, font_size)
	theme.set_color(&"font_color", type_name, Color("#fff2cf"))
	theme.set_color(&"font_hover_color", type_name, Color.WHITE)
	theme.set_color(&"font_pressed_color", type_name, HONEY)
	theme.set_color(&"font_focus_color", type_name, Color.WHITE)
	theme.set_color(&"font_outline_color", type_name, Color("#4a2e20"))
	theme.set_constant(&"outline_size", type_name, 2)
	var state_colors := {
		&"normal": Color("#6a4a32"),
		&"hover": Color("#7d5a3e"),
		&"pressed": Color("#57391f"),
		&"focus": Color("#7d5a3e"),
		&"disabled": Color("#5a4633"),
	}
	for state: StringName in state_colors:
		var tab := StyleBoxFlat.new()
		tab.bg_color = state_colors[state]
		tab.border_color = Color("#4a2e20")
		tab.set_border_width_all(2)
		tab.corner_radius_top_left = 10
		tab.corner_radius_bottom_left = 10
		tab.content_margin_left = 6
		tab.content_margin_right = 6
		theme.set_stylebox(state, type_name, tab)


static func _rich_text(
	theme: Theme,
	type_name: StringName,
	font: Font,
	font_size: int,
	color: Color
) -> void:
	theme.set_type_variation(type_name, &"RichTextLabel")
	theme.set_font(&"normal_font", type_name, font)
	theme.set_font(&"bold_font", type_name, font)
	theme.set_font_size(&"normal_font_size", type_name, font_size)
	theme.set_font_size(&"bold_font_size", type_name, font_size)
	theme.set_color(&"default_color", type_name, color)
	theme.set_constant(&"outline_size", type_name, 0)


static func _hit_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	return style
