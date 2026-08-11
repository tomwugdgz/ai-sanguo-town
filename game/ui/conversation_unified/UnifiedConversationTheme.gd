class_name UnifiedConversationTheme
extends RefCounted


const MAIN_MENU_FONT_PATH := (
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const RESIDENT_BUBBLE_PATH := (
	"res://assets/ui/conversation_unified/runtime/bubbles/"
	+ "unified_chat_resident_bubble_v1_1x.png"
)
const PLAYER_BUBBLE_PATH := (
	"res://assets/ui/conversation_unified/runtime/bubbles/"
	+ "unified_chat_player_bubble_v1_1x.png"
)

const INK := Color("3f2818")
const MUTED := Color("76583d")
const ERROR := Color("a7352b")
const SUCCESS := Color("557b2a")
const BODY_FONT_SIZE := 26
const SPEAKER_FONT_SIZE := 16
const NARRATION_FONT_SIZE := 18
const HEADER_TITLE_FONT_SIZE := 30
const HEADER_STATUS_FONT_SIZE := 16
const INPUT_FONT_SIZE := 22
const INPUT_CONTENT_MARGINS := Vector4(12, 7, 12, 7)


static func create() -> Theme:
	var result := Theme.new()
	var font_file := ResourceLoader.load(MAIN_MENU_FONT_PATH, "FontFile") as FontFile
	if font_file == null:
		push_error("统一聊天无法加载主菜单字体：%s" % MAIN_MENU_FONT_PATH)
		return result
	var main_menu_font := FontVariation.new()
	main_menu_font.base_font = font_file
	main_menu_font.spacing_glyph = 2
	main_menu_font.spacing_space = 0
	result.default_font = main_menu_font
	result.default_font_size = BODY_FONT_SIZE
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "TextEdit", INK)
	result.set_color("font_placeholder_color", "TextEdit", MUTED)
	result.set_color("caret_color", "TextEdit", Color("b94d2d"))
	result.set_font_size("font_size", "TextEdit", INPUT_FONT_SIZE)
	result.set_constant("line_spacing", "Label", 5)
	result.set_constant("line_spacing", "TextEdit", 1)
	result.set_stylebox("normal", "TextEdit", _text_edit_content_box())
	result.set_stylebox("focus", "TextEdit", _text_edit_content_box())
	result.set_stylebox("read_only", "TextEdit", _text_edit_content_box())
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		result.set_stylebox(state, "Button", StyleBoxEmpty.new())
	result.set_stylebox(
		"panel",
		"UnifiedResidentBubble",
		_body_texture_box(
			RESIDENT_BUBBLE_PATH,
			Rect2(10, 0, 396, 107),
			[16, 18, 16, 18],
			[22, 16, 18, 16],
		)
	)
	result.set_type_variation("UnifiedResidentBubble", "PanelContainer")
	result.set_stylebox(
		"panel",
		"UnifiedPlayerBubble",
		_body_texture_box(
			PLAYER_BUBBLE_PATH,
			Rect2(0, 0, 374, 79),
			[16, 16, 16, 16],
			[18, 14, 20, 14],
		)
	)
	result.set_type_variation("UnifiedPlayerBubble", "PanelContainer")
	return result


static func bubble_tail_texture(resident_side: bool) -> AtlasTexture:
	var source_path := RESIDENT_BUBBLE_PATH if resident_side else PLAYER_BUBBLE_PATH
	var source := ResourceLoader.load(source_path, "Texture2D") as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = (
		Rect2(0, 25, 18, 57)
		if resident_side
		else Rect2(366, 20, 18, 40)
	)
	return atlas


static func conversation_font(theme: Theme) -> Font:
	return theme.default_font if theme != null else null


static func _text_edit_content_box() -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.content_margin_left = INPUT_CONTENT_MARGINS.x
	style.content_margin_top = INPUT_CONTENT_MARGINS.y
	style.content_margin_right = INPUT_CONTENT_MARGINS.z
	style.content_margin_bottom = INPUT_CONTENT_MARGINS.w
	return style


static func _body_texture_box(
	path: String,
	region: Rect2,
	texture_margins: Array,
	content_margins: Array
) -> StyleBoxTexture:
	var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	var style := StyleBoxTexture.new()
	style.texture = atlas
	style.texture_margin_left = float(texture_margins[0])
	style.texture_margin_top = float(texture_margins[1])
	style.texture_margin_right = float(texture_margins[2])
	style.texture_margin_bottom = float(texture_margins[3])
	style.content_margin_left = float(content_margins[0])
	style.content_margin_top = float(content_margins[1])
	style.content_margin_right = float(content_margins[2])
	style.content_margin_bottom = float(content_margins[3])
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return style
