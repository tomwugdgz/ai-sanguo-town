class_name CustomResidentCreatorTheme
extends RefCounted


const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)

const INK := Color("3f2818")
const MUTED_INK := Color("76583d")
const DISABLED_INK := Color("756652")
const LIGHT_TEXT := Color("fff4dd")
const TERRACOTTA := Color("b94d2d")


static func create() -> Theme:
	var result := Theme.new()
	var font_file := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if font_file == null:
		push_error("自定义居民创建页字体缺失：%s" % FONT_PATH)
		return result
	var font := FontVariation.new()
	font.base_font = font_file
	font.spacing_glyph = 2
	font.spacing_space = 0
	font.variation_embolden = 0.0
	result.default_font = font
	result.default_font_size = 24
	_configure_text(result)
	_configure_empty_control_fallbacks(result)
	return result


static func _configure_text(theme: Theme) -> void:
	for type_name in ["Label", "LineEdit", "TextEdit", "Button", "OptionButton"]:
		theme.set_color("font_color", type_name, INK)
		theme.set_color("font_hover_color", type_name, INK)
		theme.set_color("font_pressed_color", type_name, LIGHT_TEXT)
		theme.set_color("font_focus_color", type_name, INK)
		theme.set_color("font_disabled_color", type_name, DISABLED_INK)
		theme.set_color("font_placeholder_color", type_name, Color("8a735d"))
		theme.set_color("caret_color", type_name, TERRACOTTA)
		theme.set_color("font_shadow_color", type_name, Color.TRANSPARENT)
		theme.set_constant("shadow_offset_x", type_name, 0)
		theme.set_constant("shadow_offset_y", type_name, 0)
	theme.set_font_size("font_size", "LineEdit", 22)
	theme.set_font_size("font_size", "TextEdit", 21)
	theme.set_font_size("font_size", "Button", 24)
	theme.set_font_size("font_size", "OptionButton", 21)
	theme.set_font_size("font_size", "PopupMenu", 21)
	theme.set_constant("v_separation", "PopupMenu", 10)
	theme.set_constant("h_separation", "PopupMenu", 12)


static func _configure_empty_control_fallbacks(theme: Theme) -> void:
	# Visible chrome is supplied by approved bitmap state families in the page.
	# Empty fallbacks prevent a default vector/StyleBoxFlat frame from leaking in.
	for type_name in ["LineEdit", "TextEdit"]:
		for state in ["normal", "focus", "read_only"]:
			theme.set_stylebox(state, type_name, StyleBoxEmpty.new())
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "Button", StyleBoxEmpty.new())
		theme.set_stylebox(state, "OptionButton", StyleBoxEmpty.new())
