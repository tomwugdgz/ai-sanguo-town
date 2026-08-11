class_name PauseMenuTheme
extends RefCounted


const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const PANEL_TEXTURE_PATH := (
	"res://assets/ui/pause_menu/final/ninepatch/"
	+ "pause_menu_panel_frame_v1.png"
)

const COLOR_INK := Color("3f2818")
const COLOR_MUTED := Color("76583d")
const COLOR_PAPER := Color("fff0cc")
const COLOR_PAPER_ALT := Color("f3ddb3")
const COLOR_WOOD := Color("6c3d20")
const COLOR_DISABLED := Color("cbbd9f")


static func create() -> Theme:
	var page_theme := Theme.new()
	var font_file := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if font_file != null:
		var font := FontVariation.new()
		font.base_font = font_file
		font.spacing_glyph = 2
		font.spacing_space = 0
		font.variation_embolden = 0.0
		page_theme.default_font = font
		page_theme.default_font_size = 32
	else:
		push_error("暂停菜单字体加载失败：%s" % FONT_PATH)

	page_theme.set_color("font_color", "Label", COLOR_INK)
	page_theme.set_color("font_outline_color", "Label", COLOR_PAPER)
	page_theme.set_constant("outline_size", "Label", 0)
	page_theme.set_constant("line_spacing", "Label", 8)
	page_theme.set_color("font_color", "Button", COLOR_INK)
	page_theme.set_color("font_hover_color", "Button", COLOR_INK)
	page_theme.set_color("font_pressed_color", "Button", COLOR_INK)
	page_theme.set_color("font_focus_color", "Button", COLOR_INK)
	page_theme.set_color("font_disabled_color", "Button", COLOR_INK)
	page_theme.set_font_size("font_size", "Button", 32)

	page_theme.set_type_variation(
		&"PauseMenuShellDesktop",
		&"PanelContainer"
	)
	page_theme.set_type_variation(
		&"PauseMenuShellCompact",
		&"PanelContainer"
	)
	page_theme.set_stylebox(
		"panel",
		"PauseMenuShellDesktop",
		_desktop_panel()
	)
	page_theme.set_stylebox(
		"panel",
		"PauseMenuShellCompact",
		_compact_panel()
	)
	return page_theme


static func _desktop_panel() -> StyleBox:
	var texture := ResourceLoader.load(
		PANEL_TEXTURE_PATH,
		"Texture2D"
	) as Texture2D
	if texture == null:
		push_error("暂停菜单九宫格外框加载失败：%s" % PANEL_TEXTURE_PATH)
		return _compact_panel()
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 176.0
	style.texture_margin_top = 192.0
	style.texture_margin_right = 176.0
	style.texture_margin_bottom = 200.0
	style.content_margin_left = 150.0
	style.content_margin_top = 48.0
	style.content_margin_right = 150.0
	style.content_margin_bottom = 48.0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.draw_center = true
	return style


static func _compact_panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PAPER
	style.border_color = COLOR_WOOD
	style.border_width_left = 6
	style.border_width_top = 6
	style.border_width_right = 6
	style.border_width_bottom = 6
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 20.0
	style.content_margin_top = 16.0
	style.content_margin_right = 20.0
	style.content_margin_bottom = 16.0
	return style
