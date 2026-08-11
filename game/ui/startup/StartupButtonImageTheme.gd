class_name StartupButtonImageTheme
extends RefCounted


const REVISION := (
	"ui.startup.button-image-states.exact-geometry-v2."
	+ "commercial-typography-v9-responsive-scale-user-approved"
)
const BUTTON_STATE_DIRECTORY := (
	"res://assets/ui/startup/runtime/button_states"
)
const MAIN_MENU_FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const DETAIL_FONT_PATH := (
	"res://assets/fonts/zheng_ge_dian_hei_16/"
	+ "ZhengGeDianHei-16.ttf"
)
# Compatibility alias for child-page themes that still consume the former
# shared detail-font constant. Startup main-menu roles use MAIN_MENU_FONT_PATH.
const FONT_PATH := DETAIL_FONT_PATH
const PRIMARY := 0
const SECONDARY := 1
const QUIET := 2

const FAMILY_NAMES: Array[String] = ["primary", "secondary", "quiet"]
const FAMILY_DESIGN_SIZES: Array[Vector2i] = [
	Vector2i(459, 70),
	Vector2i(222, 69),
	Vector2i(456, 65),
]
const STATE_NAMES: Array[String] = [
	"normal",
	"hover",
	"pressed",
	"focus",
	"disabled",
	"loading_a",
	"loading_b",
	"loading_c",
]

const INK := Color("3f2818")
const PAPER := Color("fff0cc")
const PAPER_LIGHT := Color("fff8e6")
const PAPER_DISABLED := Color("cfc4ab")
const MUTED_INK := Color("756652")


static func create(
	action_embolden: float = 0.0,
	ui_scale: float = 1.0,
) -> Theme:
	var resolved_scale := maxf(ui_scale, 0.5)
	var result := Theme.new()
	var main_menu_font_file := (
		ResourceLoader.load(MAIN_MENU_FONT_PATH, "FontFile") as FontFile
	)
	if main_menu_font_file == null:
		push_error("启动主菜单字体缺失：%s" % MAIN_MENU_FONT_PATH)
		return result
	var detail_font_file := (
		ResourceLoader.load(DETAIL_FONT_PATH, "FontFile") as FontFile
	)
	if detail_font_file == null:
		push_error("启动子页面字体缺失：%s" % DETAIL_FONT_PATH)
		return result
	var main_menu_font := _font_variation(
		main_menu_font_file,
		action_embolden,
		maxi(1, roundi(2.0 * resolved_scale)),
	)
	var detail_body_font := _font_variation(
		detail_font_file,
		0.125,
		maxi(1, roundi(2.0 * resolved_scale)),
	)
	var detail_strong_font := _font_variation(
		detail_font_file,
		0.25,
		maxi(1, roundi(2.0 * resolved_scale)),
	)
	result.default_font = main_menu_font
	result.default_font_size = _scaled_size(32, resolved_scale)
	_register_button_family(
		result,
		main_menu_font,
		&"StartupPrimaryButton",
		&"StartupPrimaryLoadingButton",
		PRIMARY,
		PAPER_LIGHT,
		PAPER_DISABLED,
		resolved_scale,
	)
	_register_button_family(
		result,
		main_menu_font,
		&"StartupSecondaryButton",
		&"StartupSecondaryLoadingButton",
		SECONDARY,
		INK,
		MUTED_INK,
		resolved_scale,
	)
	_register_button_family(
		result,
		main_menu_font,
		&"StartupQuietButton",
		&"StartupQuietLoadingButton",
		QUIET,
		PAPER_LIGHT,
		PAPER_DISABLED,
		resolved_scale,
	)
	_register_label(result, main_menu_font, &"StartupSaveSummary", 32, INK, resolved_scale)
	_register_label(result, detail_strong_font, &"StartupLoadTitle", 64, INK, resolved_scale)
	_register_label(result, detail_body_font, &"StartupLoadSubtitle", 32, MUTED_INK, resolved_scale)
	_register_label(result, detail_strong_font, &"StartupLoadSlotTitle", 48, INK, resolved_scale)
	_register_label(result, detail_body_font, &"StartupLoadSlotBody", 32, MUTED_INK, resolved_scale)
	_register_label(
		result,
		detail_body_font,
		&"StartupLoadSlotDamage",
		32,
		Color("8d3526"),
		resolved_scale,
	)
	return result


static func _font_variation(
	font_file: FontFile,
	embolden: float,
	spacing_glyph: int = 2,
) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = font_file
	variation.spacing_glyph = spacing_glyph
	variation.spacing_space = 0
	variation.variation_embolden = embolden
	return variation


static func _register_button_family(
	theme: Theme,
	font: Font,
	variation: StringName,
	loading_variation: StringName,
	row: int,
	font_color: Color,
	disabled_font_color: Color,
	ui_scale: float,
) -> void:
	theme.set_type_variation(variation, &"Button")
	theme.set_type_variation(loading_variation, &"Button")
	for type_name: StringName in [variation, loading_variation]:
		theme.set_font(&"font", type_name, font)
		theme.set_font_size(&"font_size", type_name, _scaled_size(32, ui_scale))
		theme.set_color(&"font_color", type_name, font_color)
		theme.set_color(
			&"font_hover_color",
			type_name,
			INK.darkened(0.08) if row == SECONDARY else Color.WHITE,
		)
		theme.set_color(
			&"font_pressed_color",
			type_name,
			MUTED_INK if row == SECONDARY else PAPER,
		)
		theme.set_color(
			&"font_focus_color",
			type_name,
			INK if row == SECONDARY else PAPER_LIGHT,
		)
		theme.set_color(&"font_disabled_color", type_name, disabled_font_color)
		theme.set_color(&"font_outline_color", type_name, Color("3a261a"))
		theme.set_constant(
			&"outline_size",
			type_name,
			0,
		)
		theme.set_color(
			&"font_shadow_color",
			type_name,
			Color.TRANSPARENT,
		)
		theme.set_constant(
			&"shadow_offset_x",
			type_name,
			0,
		)
		theme.set_constant(
			&"shadow_offset_y",
			type_name,
			0,
		)
		theme.set_constant(&"shadow_outline_size", type_name, 0)
	_register_state(theme, variation, &"normal", row, "normal", ui_scale)
	_register_state(theme, variation, &"hover", row, "hover", ui_scale)
	_register_state(theme, variation, &"pressed", row, "pressed", ui_scale)
	_register_state(theme, variation, &"focus", row, "focus", ui_scale)
	_register_state(theme, variation, &"disabled", row, "disabled", ui_scale)
	var working_texture := _working_texture(row)
	var working_style := _texture_style(working_texture, row, ui_scale)
	for state: StringName in [
		&"normal", &"hover", &"pressed", &"focus", &"disabled",
	]:
		theme.set_stylebox(state, loading_variation, working_style)


static func _register_state(
	theme: Theme,
	variation: StringName,
	state: StringName,
	row: int,
	asset_state: String,
	ui_scale: float,
) -> void:
	var texture := _load_state_texture(row, asset_state)
	theme.set_stylebox(
		state,
		variation,
		_texture_style(texture, row, ui_scale),
	)


static func _working_texture(row: int) -> AnimatedTexture:
	var animated := AnimatedTexture.new()
	animated.frames = 3
	animated.speed_scale = 4.0
	animated.set_frame_texture(0, _load_state_texture(row, "loading_a"))
	animated.set_frame_texture(1, _load_state_texture(row, "loading_b"))
	animated.set_frame_texture(2, _load_state_texture(row, "loading_c"))
	animated.set_frame_duration(0, 0.22)
	animated.set_frame_duration(1, 0.22)
	animated.set_frame_duration(2, 0.22)
	return animated


static func _load_state_texture(row: int, state: String) -> Texture2D:
	var family := FAMILY_NAMES[row]
	var path := "%s/%s_%s.png" % [BUTTON_STATE_DIRECTORY, family, state]
	var texture := (
		ResourceLoader.load(path, "Texture2D") as Texture2D
		if ResourceLoader.exists(path, "Texture2D")
		else null
	)
	if texture == null:
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		push_error("启动按钮状态图片缺失：%s" % path)
		return null
	var actual_size := Vector2i(texture.get_size())
	var expected_size := FAMILY_DESIGN_SIZES[row]
	if actual_size != expected_size:
		push_error(
			"启动按钮状态图片尺寸错误：%s expected=%s actual=%s"
			% [path, expected_size, actual_size]
		)
		return null
	return texture


static func _texture_style(
	texture: Texture2D,
	row: int,
	ui_scale: float,
) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	var horizontal_margin := (23.0 if row == SECONDARY else 24.0) * ui_scale
	var vertical_margin := (7.0 if row == QUIET else 8.0) * ui_scale
	style.content_margin_left = horizontal_margin
	style.content_margin_top = vertical_margin
	style.content_margin_right = horizontal_margin
	style.content_margin_bottom = vertical_margin
	# The complete texture scales as one image. Patch margins remain zero so no
	# border segment can be stretched independently from the approved artwork.
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.draw_center = true
	return style


static func _register_label(
	theme: Theme,
	font: Font,
	variation: StringName,
	font_size: int,
	color: Color,
	ui_scale: float,
) -> void:
	theme.set_type_variation(variation, &"Label")
	theme.set_font(&"font", variation, font)
	theme.set_font_size(
		&"font_size",
		variation,
		_scaled_size(font_size, ui_scale),
	)
	theme.set_color(&"font_color", variation, color)
	theme.set_color(&"font_outline_color", variation, Color("3a261a"))
	theme.set_constant(&"outline_size", variation, 0)


static func _scaled_size(value: int, ui_scale: float) -> int:
	return maxi(1, roundi(float(value) * ui_scale))
