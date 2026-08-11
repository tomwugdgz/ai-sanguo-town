class_name BulletinBoardTheme
extends RefCounted


const PROVIDER_THEME := preload(
	"res://ui/provider_settings/ProviderSettingsTheme.gd"
)
const FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const SECONDARY_BUTTON_TEXTURE := preload(
	"res://assets/ui/bulletin_board/final/primitives/"
	+ "secondary_button_nine_slice_v1.png"
)

const INK := Color("3b271b")
const INK_MUTED := Color("68432c")
const PAPER := Color("f4d29a")
const PAPER_LIGHT := Color("fff0cc")
const PAPER_SOFT := Color("f7dfae")
const PAPER_DISABLED := Color("cbbd9f")
const WOOD := Color("6c3d20")
const WOOD_DARK := Color("321d12")
const WOOD_LIGHT := Color("a96a35")
const TERRACOTTA := Color("b94d2d")
const TERRACOTTA_DARK := Color("742b1b")
const MOSS := Color("557b2a")
const MOSS_DARK := Color("36511e")
const HONEY := Color("e5a84b")
const ERROR := Color("a7352b")
const ERROR_DARK := Color("69251f")
const BUTTON_INK := Color("fff2d2")
const SHADOW := Color("1e120b78")


static func create() -> Theme:
	var page_theme := Theme.new()
	var font_file := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if font_file == null:
		push_error("公告栏字体加载失败：%s" % FONT_PATH)
		return page_theme
	var body_font := font_variation(font_file, 0.0, 2)
	page_theme.default_font = body_font
	page_theme.default_font_size = 32

	page_theme.set_color("font_color", "Label", INK)
	page_theme.set_color("font_outline_color", "Label", PAPER_LIGHT)
	page_theme.set_constant("outline_size", "Label", 0)
	page_theme.set_constant("line_spacing", "Label", 8)

	for type_name: StringName in [&"Button", &"TextEdit"]:
		page_theme.set_font_size("font_size", type_name, 32)
		page_theme.set_color("font_color", type_name, INK)
		page_theme.set_color("font_hover_color", type_name, INK)
		page_theme.set_color("font_pressed_color", type_name, INK)
		page_theme.set_color("font_focus_color", type_name, INK)
		page_theme.set_color("font_disabled_color", type_name, Color("5b4b39"))

	for state: StringName in [
		&"normal",
		&"hover",
		&"pressed",
		&"focus",
		&"disabled",
	]:
		page_theme.set_stylebox(
			state,
			"Button",
			button_style("quiet", str(state))
		)

	page_theme.set_color("font_placeholder_color", "TextEdit", INK_MUTED)
	page_theme.set_color("font_readonly_color", "TextEdit", INK_MUTED)
	page_theme.set_color("caret_color", "TextEdit", INK)
	page_theme.set_color("selection_color", "TextEdit", Color(HONEY, 0.42))
	page_theme.set_constant("line_spacing", "TextEdit", 8)
	page_theme.set_stylebox("normal", "TextEdit", input_style("normal"))
	page_theme.set_stylebox("focus", "TextEdit", input_style("focus"))
	page_theme.set_stylebox("read_only", "TextEdit", input_style("disabled"))
	page_theme.set_stylebox("panel", "PanelContainer", section_panel())
	page_theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return page_theme


# 样式与字体是共享 Resource，按参数缓存；三种字体配置相同，共用一份字形缓存。
static var _style_cache: Dictionary = {}
static var _shared_font: FontVariation


static func font_variation(
	base_font: Font,
	embolden: float,
	glyph_spacing: int = 2
) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base_font
	font.spacing_glyph = glyph_spacing
	font.spacing_space = 0
	font.variation_embolden = embolden
	return font


static func _load_shared_font() -> FontVariation:
	if _shared_font != null:
		return _shared_font
	var font_file := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if font_file == null:
		return null
	_shared_font = font_variation(font_file, 0.0, 2)
	return _shared_font


static func load_heading_font() -> FontVariation:
	return _load_shared_font()


static func load_button_font() -> FontVariation:
	return _load_shared_font()


static func load_metadata_font() -> FontVariation:
	return _load_shared_font()


static func board_panel() -> StyleBoxFlat:
	var key := "board_panel"
	if _style_cache.has(key):
		return _style_cache[key]
	var style := _flat(Color(PAPER, 0.985), WOOD_DARK, 10, 24)
	style.border_color = WOOD
	style.shadow_color = SHADOW
	style.shadow_size = 12
	style.shadow_offset = Vector2(8, 10)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 4
	_style_cache[key] = style
	return style


static func section_panel(
	accent: Color = WOOD_LIGHT,
	margin: int = 20
) -> StyleBoxFlat:
	var key := "section_panel|%s|%d" % [accent.to_html(), margin]
	if _style_cache.has(key):
		return _style_cache[key]
	var style := _flat(PAPER_LIGHT, accent, 6, margin)
	style.shadow_color = Color(SHADOW, 0.42)
	style.shadow_size = 5
	style.shadow_offset = Vector2(4, 5)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 4
	_style_cache[key] = style
	return style


static func card_panel() -> StyleBoxFlat:
	var key := "card_panel"
	if _style_cache.has(key):
		return _style_cache[key]
	var style := _flat(PAPER_SOFT, WOOD_LIGHT, 4, 16)
	_style_cache[key] = style
	return style


static func status_style(status: String) -> StyleBoxFlat:
	var key := "status|%s" % status
	if _style_cache.has(key):
		return _style_cache[key]
	var background := Color("fff4d7")
	var accent := WOOD_LIGHT
	match status:
		"loading":
			background = Color("f8e4ae")
			accent = Color("8a611d")
		"success":
			background = Color("eef0c4")
			accent = MOSS
		"rejected", "error":
			background = Color("f6d0b7")
			accent = ERROR
		"disabled":
			background = PAPER_DISABLED
			accent = Color("756956")
	var style := _flat(background, accent, 4, 10)
	_style_cache[key] = style
	return style


static func button_style(variant: String, state: String) -> StyleBoxFlat:
	var key := "button|%s|%s" % [variant, state]
	if _style_cache.has(key):
		return _style_cache[key]
	var background := PAPER_LIGHT
	var border := WOOD
	var ink_light := false
	match variant:
		"primary":
			background = TERRACOTTA
			border = TERRACOTTA_DARK
			ink_light = true
		"wood":
			background = Color("5c351f")
			border = Color("c78a4d")
			ink_light = true
		"danger":
			background = Color("c45a3e")
			border = ERROR_DARK
			ink_light = true
		"success":
			background = MOSS
			border = MOSS_DARK
			ink_light = true
		_:
			background = PAPER_LIGHT
			border = WOOD
	match state:
		"hover":
			background = background.lightened(0.08)
			border = HONEY
		"pressed":
			background = background.darkened(0.10)
		"focus":
			border = HONEY
		"disabled":
			background = PAPER_DISABLED
			border = Color("756956")
	var border_width := 7 if state == "focus" else 4
	var style := _flat(background, border, border_width, 10)
	style.set_meta("uses_light_ink", ink_light)
	style.shadow_color = Color(SHADOW, 0.38)
	style.shadow_size = 4
	style.shadow_offset = Vector2(3, 4)
	if state == "pressed":
		style.content_margin_top += 3
		style.content_margin_bottom = maxf(
			4.0,
			style.content_margin_bottom - 3.0
		)
	_style_cache[key] = style
	return style


static func secondary_button_asset_style(state: String) -> StyleBoxTexture:
	var key := "secondary_button|%s" % state
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxTexture.new()
	style.texture = SECONDARY_BUTTON_TEXTURE
	style.texture_margin_left = 12.0
	style.texture_margin_top = 12.0
	style.texture_margin_right = 12.0
	style.texture_margin_bottom = 12.0
	style.content_margin_left = 12.0
	style.content_margin_top = 10.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 10.0
	match state:
		"hover", "focus":
			style.modulate_color = Color("fff0c7")
		"pressed":
			style.modulate_color = Color("d8aa78")
		"disabled":
			style.modulate_color = Color("8d8376")
		_:
			style.modulate_color = Color.WHITE
	_style_cache[key] = style
	return style


static func input_style(state: String) -> StyleBoxFlat:
	var key := "input|%s" % state
	if _style_cache.has(key):
		return _style_cache[key]
	var background := Color(PAPER_LIGHT, 0.92)
	var border := WOOD_LIGHT
	if state == "focus":
		border = HONEY
	elif state == "disabled":
		background = Color(PAPER_DISABLED, 0.94)
		border = Color("756956")
	var style := _flat(
		background,
		border,
		7 if state == "focus" else 4,
		12
	)
	_style_cache[key] = style
	return style


static func composite_content_style(
	content_margin: int = 0
) -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style


static func _flat(
	background: Color,
	border: Color,
	border_width: int,
	content_margin: int
) -> StyleBoxFlat:
	return PROVIDER_THEME.shared_flat(background, border, border_width, content_margin)
