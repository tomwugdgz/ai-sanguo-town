class_name TownLogTheme
extends RefCounted


const MAIN_MENU_FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const ASSET_ROOT := (
	"res://assets/ui/world_log/runtime/reference_table_v2/"
)
const CONTROL_ASSET_ROOT := (
	"res://assets/ui/world_log/runtime/reference_table_v4/"
)
const REFERENCE_CONTROL_ROOT := (
	"res://assets/ui/world_log/runtime/reference_table_v5/"
)
const REFERENCE_DETAIL_ROOT := (
	"res://assets/ui/world_log/runtime/reference_table_v6/"
)
const ICON_ROOT := (
	"res://assets/ui/town_log/runtime/family/v3_imagegen/"
)
const PANEL_PATH := ASSET_ROOT + "world_log_paper_v2.png"
const OUTER_FRAME_PATH := ASSET_ROOT + "world_log_outer_frame_v2.png"
const FLYOUT_PATH := ASSET_ROOT + "world_log_detail_panel_v2.png"
const HEADER_PATH := REFERENCE_DETAIL_ROOT + "header_frame_v6.png"
const TABLE_CELL_PATHS := {
	"header": ASSET_ROOT + "world_log_cell_header_single_v3.png",
	"normal_a": ASSET_ROOT + "world_log_cell_normal_a_single_v3.png",
	"normal_b": ASSET_ROOT + "world_log_cell_normal_b_single_v3.png",
	"unread": ASSET_ROOT + "world_log_cell_unread_single_v3.png",
	"selected": ASSET_ROOT + "world_log_cell_selected_single_v3.png",
}
const CONTROL_PATHS := {
	"normal": REFERENCE_CONTROL_ROOT + "filter_normal_v5.png",
	"selected": REFERENCE_CONTROL_ROOT + "filter_hover_v5.png",
	"hover": REFERENCE_CONTROL_ROOT + "filter_hover_v5.png",
	"disabled": REFERENCE_CONTROL_ROOT + "filter_normal_v5.png",
}
const BUTTON_PATHS := {
	"normal": CONTROL_ASSET_ROOT + "button_normal_v4.png",
	"selected": CONTROL_ASSET_ROOT + "button_selected_v4.png",
	"hover": CONTROL_ASSET_ROOT + "button_hover_v4.png",
	"disabled": CONTROL_ASSET_ROOT + "button_disabled_v4.png",
}
const ICON_BUTTON_PATHS := {
	"normal": CONTROL_ASSET_ROOT + "icon_button_normal_v4.png",
	"hover": CONTROL_ASSET_ROOT + "icon_button_hover_v4.png",
	"selected": CONTROL_ASSET_ROOT + "icon_button_selected_v4.png",
}
const DETAIL_PATHS := {
	"title": CONTROL_ASSET_ROOT + "detail_title_banner_v4.png",
	"summary": CONTROL_ASSET_ROOT + "event_summary_strip_v4.png",
	"process": CONTROL_ASSET_ROOT + "event_summary_strip_v4.png",
	"message": CONTROL_ASSET_ROOT + "message_letter_box_v4.png",
	"pagination": CONTROL_ASSET_ROOT + "pagination_button_v4.png",
}
const CHIP_PATHS := {
	"neutral": CONTROL_ASSET_ROOT + "chip_neutral_v4.png",
	"completed": CONTROL_ASSET_ROOT + "chip_completed_v4.png",
	"waiting": CONTROL_ASSET_ROOT + "chip_waiting_v4.png",
	"important": CONTROL_ASSET_ROOT + "chip_important_v4.png",
}
const TOGGLE_PATHS := {
	"off": REFERENCE_CONTROL_ROOT + "checkbox_off_v5.png",
	"on": REFERENCE_CONTROL_ROOT + "checkbox_on_v5.png",
}
const ICON_PATHS := {
	"journal": ICON_ROOT + "town_log_icon_journal.png",
	"player": ICON_ROOT + "town_log_icon_announcement.png",
	"announcement": ICON_ROOT + "town_log_icon_announcement.png",
	"resident": REFERENCE_CONTROL_ROOT + "filter_resident_v5.png",
	"weather": ICON_ROOT + "town_log_icon_weather.png",
	"hot": ICON_ROOT + "town_log_icon_hot.png",
	"player_related": ICON_ROOT + "town_log_icon_player_related.png",
	"causal": ICON_ROOT + "town_log_icon_causal.png",
	"location": ICON_ROOT + "town_log_icon_location.png",
	"story": ICON_ROOT + "town_log_icon_story.png",
	"close": REFERENCE_CONTROL_ROOT + "close_v5.png",
	"back": REFERENCE_CONTROL_ROOT + "back_v5.png",
	"refresh": CONTROL_ASSET_ROOT + "icon_refresh_v4.png",
	"mail": CONTROL_ASSET_ROOT + "icon_mail_v4.png",
	"kind": REFERENCE_CONTROL_ROOT + "filter_kind_v5.png",
	"calendar": REFERENCE_CONTROL_ROOT + "filter_calendar_v5.png",
	"unread_filter": CONTROL_ASSET_ROOT + "icon_unread_v4.png",
	"dropdown": REFERENCE_CONTROL_ROOT + "dropdown_arrow_v5.png",
	"unread": REFERENCE_CONTROL_ROOT + "unread_dot_v5.png",
	"selected_unread": ASSET_ROOT + "world_log_selected_dot_v2.png",
}
const CONNECTOR_PATH := ICON_ROOT + "town_log_causal_connector.png"
const HUD_CONNECTOR_PATH := ICON_ROOT + "town_log_hud_connector.png"
const CAUSAL_NODE_PATH := ASSET_ROOT + "world_log_filter_v2.png"
const SCROLLBAR_TRACK_PATH := (
	"res://assets/ui/common/scrollbar/wood_v1/"
	+ "scrollbar_track_wood_v1.png"
)
const SCROLLBAR_THUMB_PATH := (
	"res://assets/ui/common/scrollbar/wood_v1/"
	+ "scrollbar_thumb_wood_v1.png"
)

const INK := Color("3f2818")
const INK_MUTED := Color("68452b")
const PAPER := Color("fff0cc")
const PAPER_LIGHT := Color("fff8e6")
const WALNUT := Color("5e3219")
const WALNUT_DARK := Color("321d12")
const TERRACOTTA := Color("d9481f")
const TERRACOTTA_DARK := Color("742b1b")
const HONEY := Color("e5a84b")
const MOSS := Color("557b2a")
const COURIER_BLUE := Color("2d70a3")
const ERROR := Color("a7352b")
const DISABLED := Color("746b5e")

const PANEL_PATCH := [14, 14, 14, 14]
const CONTROL_PATCH := [8, 8, 8, 8]


static func create() -> Theme:
	var theme := Theme.new()
	var source_font := load(MAIN_MENU_FONT_PATH) as Font
	var body_font := FontVariation.new()
	body_font.base_font = source_font
	body_font.spacing_glyph = 2
	body_font.spacing_space = 0
	var emphasis_font := FontVariation.new()
	emphasis_font.base_font = source_font
	emphasis_font.spacing_glyph = 2
	emphasis_font.spacing_space = 0
	if body_font != null:
		theme.default_font = body_font
	theme.default_font_size = 20

	_set_label(theme, &"TownLogTitle", emphasis_font, 25, INK, 0)
	_set_label(theme, &"TownLogHeading", emphasis_font, 22, INK, 0)
	_set_label(theme, &"TownLogBody", body_font, 19, INK, 0)
	_set_label(theme, &"TownLogListTime", body_font, 16, INK_MUTED, 0)
	_set_label(theme, &"TownLogListTitle", body_font, 17, INK, 0)
	_set_label(theme, &"TownLogListPreview", body_font, 14, INK_MUTED, 0)
	_set_label(theme, &"TownLogListPlace", body_font, 16, INK_MUTED, 0)
	_set_label(
		theme,
		&"TownLogBodyMuted",
		body_font,
		19,
		INK_MUTED,
		0
	)
	_set_label(theme, &"TownLogBodyLight", body_font, 19, PAPER_LIGHT, 0)
	_set_label(theme, &"TownLogError", body_font, 19, ERROR, 0)
	_set_label(theme, &"TownLogDisabled", body_font, 19, DISABLED, 0)

	_set_button(
		theme,
		&"TownLogFilter",
		emphasis_font,
		19,
		INK,
		false
	)
	_set_button(
		theme,
		&"TownLogFilterSelected",
		emphasis_font,
		19,
		PAPER_LIGHT,
		true
	)
	_set_button(
		theme,
		&"TownLogAction",
		body_font,
		19,
		INK,
		false
	)
	_set_button(
		theme,
		&"TownLogActionSelected",
		body_font,
		19,
		PAPER_LIGHT,
		true
	)
	_set_button(
		theme,
		&"TownLogCausalNode",
		body_font,
		17,
		INK,
		false
	)
	_set_button(
		theme,
		&"TownLogCausalNodeSelected",
		body_font,
		17,
		TERRACOTTA,
		true
	)
	for type_name: StringName in [
		&"TownLogCausalNode",
		&"TownLogCausalNodeSelected",
	]:
		theme.set_stylebox(
			&"normal",
			type_name,
			transparent_style()
		)
		theme.set_stylebox(&"hover", type_name, transparent_style())
		theme.set_stylebox(&"pressed", type_name, transparent_style())
		theme.set_stylebox(&"focus", type_name, transparent_style())
		theme.set_stylebox(&"disabled", type_name, transparent_style())
	_set_button(
		theme,
		&"TownLogMenuItem",
		body_font,
		19,
		INK,
		false
	)
	theme.set_stylebox(
		&"normal",
		&"TownLogMenuItem",
		transparent_style()
	)
	theme.set_stylebox(
		&"disabled",
		&"TownLogMenuItem",
		transparent_style()
	)
	_set_button(
		theme,
		&"TownLogMenuItemSelected",
		body_font,
		19,
		PAPER_LIGHT,
		true
	)
	_set_vertical_scrollbar(theme)
	_set_popup_menu(theme, body_font)
	return theme


static func panel_texture() -> Texture2D:
	return load(PANEL_PATH) as Texture2D


static func outer_frame_texture() -> Texture2D:
	return load(OUTER_FRAME_PATH) as Texture2D


static func flyout_texture() -> Texture2D:
	return load(FLYOUT_PATH) as Texture2D


static func header_texture() -> Texture2D:
	return load(HEADER_PATH) as Texture2D


static func header_divider_texture() -> Texture2D:
	var divider := AtlasTexture.new()
	divider.atlas = load(HEADER_PATH) as Texture2D
	divider.region = Rect2(0, 54, 1718, 8)
	return divider


static func control_texture(state: String) -> Texture2D:
	var path := str(CONTROL_PATHS.get(state, CONTROL_PATHS["normal"]))
	return load(path) as Texture2D


static func button_texture(state: String) -> Texture2D:
	var path := str(BUTTON_PATHS.get(state, BUTTON_PATHS["normal"]))
	return load(path) as Texture2D


static func icon_texture(icon_id: String) -> Texture2D:
	var normalized := icon_id
	match icon_id:
		"player_action":
			normalized = "player"
		"resident_action", "social", "relationship", "photo":
			normalized = "resident"
		"weather_thunderstorm":
			normalized = "weather"
	if not ICON_PATHS.has(normalized):
		normalized = "resident"
	return load(str(ICON_PATHS[normalized])) as Texture2D


static func connector_texture() -> Texture2D:
	return load(CONNECTOR_PATH) as Texture2D


static func hud_connector_texture() -> Texture2D:
	return load(HUD_CONNECTOR_PATH) as Texture2D


static func scrollbar_track_texture() -> Texture2D:
	return load(SCROLLBAR_TRACK_PATH) as Texture2D


static func scrollbar_thumb_texture() -> Texture2D:
	return load(SCROLLBAR_THUMB_PATH) as Texture2D


static func control_style(state: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = control_texture(state)
	# 整张参考图等比铺进控件，保留素材自带箭头，不切开箭头所在像素。
	style.texture_margin_left = 0
	style.texture_margin_top = 0
	style.texture_margin_right = 0
	style.texture_margin_bottom = 0
	style.content_margin_left = 52
	style.content_margin_top = 5
	style.content_margin_right = 72
	style.content_margin_bottom = 5
	return style


static func button_style(state: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = button_texture(state)
	style.texture_margin_left = 18
	style.texture_margin_top = 16
	style.texture_margin_right = 18
	style.texture_margin_bottom = 16
	style.content_margin_left = 14
	style.content_margin_top = 5
	style.content_margin_right = 14
	style.content_margin_bottom = 5
	return style


static func icon_button_style(state: String) -> StyleBoxTexture:
	var normalized := state if ICON_BUTTON_PATHS.has(state) else "normal"
	var style := StyleBoxTexture.new()
	style.texture = load(String(ICON_BUTTON_PATHS[normalized])) as Texture2D
	style.texture_margin_left = 20
	style.texture_margin_top = 20
	style.texture_margin_right = 20
	style.texture_margin_bottom = 20
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	return style


static func detail_style(kind: String) -> StyleBoxTexture:
	var normalized := kind if DETAIL_PATHS.has(kind) else "summary"
	var style := StyleBoxTexture.new()
	style.texture = load(String(DETAIL_PATHS[normalized])) as Texture2D
	style.texture_margin_left = 20
	style.texture_margin_top = 18
	style.texture_margin_right = 20
	style.texture_margin_bottom = 18
	style.content_margin_left = 20
	style.content_margin_top = 7 if normalized == "process" else 12
	style.content_margin_right = 20
	style.content_margin_bottom = 7 if normalized == "process" else 12
	return style


static func chip_style(state: String) -> StyleBoxTexture:
	var normalized := state if CHIP_PATHS.has(state) else "neutral"
	var style := StyleBoxTexture.new()
	style.texture = load(String(CHIP_PATHS[normalized])) as Texture2D
	style.texture_margin_left = 12
	style.texture_margin_top = 12
	style.texture_margin_right = 12
	style.texture_margin_bottom = 12
	style.content_margin_left = 12
	style.content_margin_top = 5
	style.content_margin_right = 12
	style.content_margin_bottom = 5
	return style


static func toggle_style(selected: bool) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(String(TOGGLE_PATHS["on" if selected else "off"])) as Texture2D
	style.texture_margin_left = 20
	style.texture_margin_top = 20
	style.texture_margin_right = 20
	style.texture_margin_bottom = 20
	style.content_margin_left = 14
	style.content_margin_top = 6
	style.content_margin_right = 14
	style.content_margin_bottom = 6
	return style


static func toggle_texture(selected: bool) -> Texture2D:
	return load(String(TOGGLE_PATHS["on" if selected else "off"])) as Texture2D


static func separator_texture(dashed := true) -> Texture2D:
	return load(
		REFERENCE_CONTROL_ROOT
		+ ("separator_dashed_v5.png" if dashed else "separator_solid_v5.png")
	) as Texture2D


static func timeline_node_texture() -> Texture2D:
	return load(REFERENCE_DETAIL_ROOT + "timeline_node_v6.png") as Texture2D


static func timeline_connector_texture() -> Texture2D:
	return load(REFERENCE_DETAIL_ROOT + "timeline_connector_v6.png") as Texture2D


static func reference_button_style(kind: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(
		REFERENCE_CONTROL_ROOT
		+ ("back_v5.png" if kind == "back" else "close_v5.png")
	) as Texture2D
	style.texture_margin_left = 22
	style.texture_margin_top = 22
	style.texture_margin_right = 22
	style.texture_margin_bottom = 22
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	return style


static func table_cell_style(state: String) -> StyleBoxTexture:
	var normalized := state if TABLE_CELL_PATHS.has(state) else "normal_a"
	var style := StyleBoxTexture.new()
	style.texture = load(String(TABLE_CELL_PATHS[normalized])) as Texture2D
	style.texture_margin_left = 0
	style.texture_margin_top = 0
	style.texture_margin_right = 1
	style.texture_margin_bottom = 1
	style.content_margin_left = 7
	style.content_margin_top = 2
	style.content_margin_right = 7
	style.content_margin_bottom = 2
	return style


static func transparent_style() -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style


static func _scrollbar_track_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = scrollbar_track_texture()
	style.texture_margin_left = 20
	style.texture_margin_top = 32
	style.texture_margin_right = 20
	style.texture_margin_bottom = 32
	return style


static func _scrollbar_thumb_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = scrollbar_thumb_texture()
	style.texture_margin_left = 42
	style.texture_margin_top = 24
	style.texture_margin_right = 42
	style.texture_margin_bottom = 24
	return style


static func _set_vertical_scrollbar(theme: Theme) -> void:
	theme.set_type_variation(&"TownLogVerticalScrollBar", &"VScrollBar")
	for style_name: StringName in [&"scroll", &"scroll_focus"]:
		theme.set_stylebox(
			style_name,
			&"TownLogVerticalScrollBar",
			_scrollbar_track_style()
		)
	for style_name: StringName in [
		&"grabber",
		&"grabber_highlight",
		&"grabber_pressed",
	]:
		theme.set_stylebox(
			style_name,
			&"TownLogVerticalScrollBar",
			_scrollbar_thumb_style()
		)
	theme.set_constant(
		&"minimum_grabber_size",
		&"TownLogVerticalScrollBar",
		72
	)


static func _set_popup_menu(theme: Theme, font: Font) -> void:
	if font != null:
		theme.set_font(&"font", &"PopupMenu", font)
	theme.set_font_size(&"font_size", &"PopupMenu", 18)
	theme.set_color(&"font_color", &"PopupMenu", INK)
	theme.set_color(&"font_hover_color", &"PopupMenu", PAPER_LIGHT)
	theme.set_stylebox(&"panel", &"PopupMenu", detail_style("summary"))
	# 弹出菜单只使用单层选中行，不复用带下拉箭头的筛选框本体。
	theme.set_stylebox(&"hover", &"PopupMenu", table_cell_style("selected"))
	theme.set_stylebox(&"separator", &"PopupMenu", transparent_style())
	theme.set_constant(&"item_start_padding", &"PopupMenu", 12)
	theme.set_constant(&"item_end_padding", &"PopupMenu", 12)


static func configure_nine_patch(
	patch: NinePatchRect,
	texture: Texture2D,
	margins: Array = PANEL_PATCH
) -> void:
	patch.texture = texture
	patch.patch_margin_left = int(margins[0])
	patch.patch_margin_top = int(margins[1])
	patch.patch_margin_right = int(margins[2])
	patch.patch_margin_bottom = int(margins[3])
	patch.axis_stretch_horizontal = (
		NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	)
	patch.axis_stretch_vertical = (
		NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	)
	patch.draw_center = true
	patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func _set_label(
	theme: Theme,
	type_name: StringName,
	font: Font,
	font_size: int,
	color: Color,
	outline_size: int
) -> void:
	theme.set_type_variation(type_name, &"Label")
	if font != null:
		theme.set_font(&"font", type_name, font)
	theme.set_font_size(&"font_size", type_name, font_size)
	theme.set_color(&"font_color", type_name, color)
	theme.set_color(&"font_outline_color", type_name, WALNUT_DARK)
	theme.set_constant(&"outline_size", type_name, outline_size)
	theme.set_constant(
		&"line_spacing",
		type_name,
		12 if font_size >= 64 else (10 if font_size >= 48 else 8)
	)


static func _set_button(
	theme: Theme,
	type_name: StringName,
	font: Font,
	font_size: int,
	font_color: Color,
	selected: bool
) -> void:
	theme.set_type_variation(type_name, &"Button")
	if font != null:
		theme.set_font(&"font", type_name, font)
	theme.set_font_size(&"font_size", type_name, font_size)
	for color_name: StringName in [
		&"font_color",
		&"font_hover_color",
		&"font_pressed_color",
		&"font_focus_color",
	]:
		theme.set_color(color_name, type_name, font_color)
	theme.set_color(&"font_disabled_color", type_name, DISABLED)
	var base_state := "selected" if selected else "normal"
	theme.set_stylebox(
		&"normal",
		type_name,
		button_style(base_state)
	)
	theme.set_stylebox(
		&"hover",
		type_name,
		button_style("selected" if selected else "hover")
	)
	theme.set_stylebox(
		&"pressed",
		type_name,
		button_style("selected")
	)
	theme.set_stylebox(
		&"focus",
		type_name,
		button_style("selected" if selected else "hover")
	)
	theme.set_stylebox(
		&"disabled",
		type_name,
		button_style("disabled")
	)
	theme.set_constant(&"outline_size", type_name, 0)
	theme.set_constant(&"line_spacing", type_name, 8)
