class_name NewGameOverwriteTheme
extends RefCounted


const FONT_PATH := (
	"res://assets/fonts/zheng_ge_dian_hei_16/"
	+ "ZhengGeDianHei-16.ttf"
)
const ASSET_DIR := "res://assets/ui/new_game_overwrite/final"
const BASE_ASSET_DIR := ASSET_DIR + "/base"
const ACTION_ASSET_DIR := ASSET_DIR + "/actions"

const INK := Color("3f2818")
const MUTED_INK := Color("76583d")
const PAPER_LIGHT := Color("fff0cc")
const ERROR := Color("8d3526")
const SUCCESS := Color("41672b")
const DISABLED := Color("756c5c")
const BODY_EMBOLDEN := 0.125
const TITLE_EMBOLDEN := 0.25
const ACTION_EMBOLDEN := 0.25


static func create() -> Theme:
	var result := Theme.new()
	var font_file := ResourceLoader.load(FONT_PATH, "FontFile") as FontFile
	if font_file == null:
		push_error("新游戏覆盖确认字体加载失败：%s" % FONT_PATH)
		return result
	var body_font := _font_variation(font_file, BODY_EMBOLDEN)
	var title_font := _font_variation(font_file, TITLE_EMBOLDEN)
	var action_font := _font_variation(font_file, ACTION_EMBOLDEN)
	result.default_font = body_font
	result.default_font_size = 24
	result.set_color(&"font_color", &"Label", INK)
	result.set_color(&"font_outline_color", &"Label", PAPER_LIGHT)
	result.set_constant(&"outline_size", &"Label", 0)
	result.set_constant(&"line_spacing", &"Label", 5)

	_register_label(
		result,
		&"OverwriteKicker",
		body_font,
		28,
		MUTED_INK,
		0,
		6
	)
	_register_label(
		result,
		&"OverwriteTitle",
		title_font,
		48,
		INK,
		0,
		6
	)
	_register_label(
		result,
		&"OverwriteBody",
		body_font,
		32,
		INK,
		0,
		8
	)
	_register_label(
		result,
		&"OverwriteMuted",
		body_font,
		32,
		MUTED_INK,
		0,
		8
	)
	_register_label(
		result,
		&"OverwriteFeedback",
		body_font,
		32,
		MUTED_INK,
		0,
		8
	)
	_register_label(
		result,
		&"OverwriteError",
		body_font,
		32,
		ERROR,
		0,
		8
	)
	_register_label(
		result,
		&"OverwriteSuccess",
		body_font,
		32,
		SUCCESS,
		0,
		8
	)
	_register_label(
		result,
		&"OverwriteDisabled",
		body_font,
		32,
		DISABLED,
		0,
		8
	)

	result.set_type_variation(&"OverwritePaperSlot", &"PanelContainer")
	result.set_stylebox(
		&"panel",
		&"OverwritePaperSlot",
			_texture_style(
				BASE_ASSET_DIR + "/paper_slot_9patch.png",
				[14.0, 14.0, 14.0, 14.0],
				[18.0, 12.0, 18.0, 12.0],
				Color.WHITE
			)
	)

	_register_button(
		result,
		&"OverwriteCancel",
		action_font,
		ACTION_ASSET_DIR + "/button_cancel.png"
	)
	_register_button(
		result,
		&"OverwriteRecovery",
		action_font,
		ACTION_ASSET_DIR + "/button_recovery.png"
	)
	_register_button(
		result,
		&"OverwriteDestructive",
		action_font,
		ACTION_ASSET_DIR + "/button_overwrite.png"
	)
	return result


static func _font_variation(
	font_file: FontFile,
	embolden: float
) -> FontVariation:
	var result := FontVariation.new()
	result.base_font = font_file
	result.spacing_glyph = 2
	result.spacing_space = 0
	result.variation_embolden = embolden
	return result


static func _register_label(
	theme: Theme,
	variation: StringName,
	font: Font,
	font_size: int,
	color: Color,
	outline: int,
	line_spacing: int
) -> void:
	theme.set_type_variation(variation, &"Label")
	theme.set_font(&"font", variation, font)
	theme.set_font_size(&"font_size", variation, font_size)
	theme.set_color(&"font_color", variation, color)
	theme.set_color(&"font_outline_color", variation, PAPER_LIGHT)
	theme.set_constant(&"outline_size", variation, outline)
	theme.set_constant(&"line_spacing", variation, line_spacing)


static func _register_button(
	theme: Theme,
	variation: StringName,
	font: Font,
	texture_path: String
) -> void:
	theme.set_type_variation(variation, &"Button")
	theme.set_font(&"font", variation, font)
	theme.set_font_size(&"font_size", variation, 32)
	for color_name: StringName in [
		&"font_color",
		&"font_hover_color",
		&"font_pressed_color",
		&"font_focus_color",
	]:
		theme.set_color(color_name, variation, PAPER_LIGHT)
	theme.set_color(
		&"font_disabled_color",
		variation,
		Color("d6cdb8")
	)
	theme.set_color(
		&"font_outline_color",
		variation,
		Color("3a261a")
	)
	theme.set_constant(&"outline_size", variation, 1)
	theme.set_stylebox(
		&"normal",
		variation,
		_texture_style(
			texture_path,
			[20.0, 18.0, 20.0, 18.0],
			[14.0, 10.0, 14.0, 10.0],
			Color.WHITE
		)
	)
	theme.set_stylebox(
		&"hover",
		variation,
		_texture_style(
			texture_path,
			[20.0, 18.0, 20.0, 18.0],
			[14.0, 10.0, 14.0, 10.0],
			Color("fff2bd")
		)
	)
	theme.set_stylebox(
		&"pressed",
		variation,
		_texture_style(
			texture_path,
			[20.0, 18.0, 20.0, 18.0],
			[14.0, 12.0, 14.0, 8.0],
			Color("cbb58e")
		)
	)
	theme.set_stylebox(
		&"disabled",
		variation,
		_texture_style(
			texture_path,
			[20.0, 18.0, 20.0, 18.0],
			[14.0, 10.0, 14.0, 10.0],
			Color("8f877a")
		)
	)
	theme.set_stylebox(
		&"focus",
		variation,
		_texture_style(
			texture_path,
			[20.0, 18.0, 20.0, 18.0],
			[14.0, 10.0, 14.0, 10.0],
			Color("fff2bd")
		)
	)


static func _texture_style(
	path: String,
	texture_margins: Array[float],
	content_margins: Array[float],
	modulate: Color
) -> StyleBoxTexture:
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture == null:
		push_error("新游戏覆盖确认运行纹理缺失：%s" % path)
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = texture_margins[0]
	style.texture_margin_top = texture_margins[1]
	style.texture_margin_right = texture_margins[2]
	style.texture_margin_bottom = texture_margins[3]
	style.content_margin_left = content_margins[0]
	style.content_margin_top = content_margins[1]
	style.content_margin_right = content_margins[2]
	style.content_margin_bottom = content_margins[3]
	style.modulate_color = modulate
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.draw_center = true
	return style
