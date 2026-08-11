class_name StartupLoadGameImageTheme
extends RefCounted


const BASE_THEME := preload("res://ui/startup/StartupButtonImageTheme.gd")
const REVISION := "ui.startup.load-game.image-atlas-runtime-v2-open-paper"
const ATLAS_PATH := (
	"res://assets/ui/startup/final/load_game/"
	+ "load_game_open_paper_1672x941.png"
)
const HEALTHY_ACTION_REGION := Rect2(1044.0, 311.0, 162.0, 79.0)
const RECOVERABLE_ACTION_REGION := Rect2(1044.0, 469.0, 162.0, 79.0)
const DISABLED_ACTION_REGION := Rect2(1044.0, 628.0, 162.0, 79.0)
const BACK_ACTION_REGION := Rect2(425.0, 764.0, 181.0, 87.0)
const DELETE_ICON_PATH := (
	"res://assets/ui/resident_selection/icons_v2/trash.png"
)
const DELETE_BADGE_NORMAL_PATH := (
	"res://assets/ui/settings/final/controls/v2/button_square_sized/normal.png"
)
const DELETE_BADGE_HOVER_PATH := (
	"res://assets/ui/settings/final/controls/v2/button_square_sized/hover.png"
)
const DELETE_BADGE_PRESSED_PATH := (
	"res://assets/ui/settings/final/controls/v2/button_square_sized/pressed.png"
)
const DELETE_BADGE_FOCUS_PATH := (
	"res://assets/ui/settings/final/controls/v2/button_square_sized/focus.png"
)
const DELETE_BADGE_DISABLED_PATH := (
	"res://assets/ui/settings/final/controls/v2/button_square_sized/disabled.png"
)

const INK := Color("3f2818")
const PAPER_LIGHT := Color("fff8e6")
const PAPER_DISABLED := Color("f3dfb7")


static func create() -> Theme:
	var result := BASE_THEME.create()
	var atlas := ResourceLoader.load(ATLAS_PATH, "Texture2D") as Texture2D
	if atlas == null:
		push_error("加载游戏页图像图集缺失：%s" % ATLAS_PATH)
		return result
	_register_button(
		result,
		atlas,
		&"StartupLoadHealthyAction",
		HEALTHY_ACTION_REGION,
		DISABLED_ACTION_REGION,
		PAPER_LIGHT,
		PAPER_DISABLED,
	)
	_register_button(
		result,
		atlas,
		&"StartupLoadRecoverableAction",
		RECOVERABLE_ACTION_REGION,
		DISABLED_ACTION_REGION,
		PAPER_LIGHT,
		PAPER_DISABLED,
	)
	_register_button(
		result,
		atlas,
		&"StartupLoadBackAction",
		BACK_ACTION_REGION,
		BACK_ACTION_REGION,
		INK,
		Color("756652"),
	)
	_register_delete_badge_button(
		result,
		&"StartupLoadDeleteBadgeAction",
	)
	return result


static func _register_delete_badge_button(
	theme: Theme,
	variation: StringName,
) -> void:
	var normal := _load_texture(DELETE_BADGE_NORMAL_PATH)
	var hover := _load_texture(DELETE_BADGE_HOVER_PATH)
	var pressed := _load_texture(DELETE_BADGE_PRESSED_PATH)
	var focus := _load_texture(DELETE_BADGE_FOCUS_PATH)
	var disabled := _load_texture(DELETE_BADGE_DISABLED_PATH)
	if normal == null or hover == null or pressed == null or focus == null or disabled == null:
		push_error("加载游戏页删除方牌状态图像缺失。")
		return
	theme.set_type_variation(variation, &"Button")
	theme.set_font(
		&"font",
		variation,
		theme.get_font(&"font", &"StartupPrimaryButton"),
	)
	theme.set_font_size(&"font_size", variation, 1)
	for color_name: StringName in [
		&"font_color",
		&"font_hover_color",
		&"font_pressed_color",
		&"font_focus_color",
	]:
		theme.set_color(color_name, variation, PAPER_LIGHT)
	theme.set_color(&"font_disabled_color", variation, Color.TRANSPARENT)
	theme.set_color(&"icon_normal_color", variation, Color.WHITE)
	theme.set_color(&"icon_hover_color", variation, Color("fff2bd"))
	theme.set_color(&"icon_pressed_color", variation, Color("cbb58e"))
	theme.set_color(&"icon_focus_color", variation, Color.WHITE)
	theme.set_color(&"icon_disabled_color", variation, Color("7a7368"))
	theme.set_constant(&"outline_size", variation, 0)
	theme.set_constant(&"icon_max_width", variation, 36)
	theme.set_stylebox(
		&"normal",
		variation,
		_badge_style(normal),
	)
	theme.set_stylebox(
		&"hover",
		variation,
		_badge_style(hover),
	)
	theme.set_stylebox(
		&"pressed",
		variation,
		_badge_style(pressed),
	)
	theme.set_stylebox(
		&"focus",
		variation,
		_badge_style(focus),
	)
	theme.set_stylebox(
		&"disabled",
		variation,
		_badge_style(disabled),
	)


static func _load_texture(path: String) -> Texture2D:
	return ResourceLoader.load(path, "Texture2D") as Texture2D


static func _register_button(
	theme: Theme,
	atlas: Texture2D,
	variation: StringName,
	normal_region: Rect2,
	disabled_region: Rect2,
	font_color: Color,
	disabled_font_color: Color,
) -> void:
	theme.set_type_variation(variation, &"Button")
	theme.set_font(
		&"font",
		variation,
		theme.get_font(&"font", &"StartupPrimaryButton"),
	)
	theme.set_font_size(&"font_size", variation, 24)
	theme.set_color(&"font_color", variation, font_color)
	theme.set_color(&"font_hover_color", variation, font_color)
	theme.set_color(&"font_pressed_color", variation, font_color)
	theme.set_color(&"font_focus_color", variation, font_color)
	theme.set_color(&"font_disabled_color", variation, disabled_font_color)
	theme.set_constant(&"outline_size", variation, 0)
	theme.set_stylebox(
		&"normal",
		variation,
		_style(atlas, normal_region, Color.WHITE, false),
	)
	theme.set_stylebox(
		&"hover",
		variation,
		_style(atlas, normal_region, Color("fff2bd"), false),
	)
	theme.set_stylebox(
		&"pressed",
		variation,
		_style(atlas, normal_region, Color("cbb58e"), true),
	)
	theme.set_stylebox(
		&"focus",
		variation,
		_style(atlas, normal_region, Color("fff2bd"), false),
	)
	theme.set_stylebox(
		&"disabled",
		variation,
		_style(atlas, disabled_region, Color.WHITE, false),
	)


static func _style(
	atlas: Texture2D,
	region: Rect2,
	modulate: Color,
	pressed: bool,
) -> StyleBoxTexture:
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = region
	texture.filter_clip = true
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.content_margin_left = 12.0
	style.content_margin_top = 9.0 if pressed else 7.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 5.0 if pressed else 7.0
	style.modulate_color = modulate
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.draw_center = true
	return style


static func _badge_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.content_margin_left = 8.0
	style.content_margin_top = 7.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.draw_center = true
	return style
