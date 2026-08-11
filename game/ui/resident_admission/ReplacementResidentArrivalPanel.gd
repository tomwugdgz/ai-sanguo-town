class_name ReplacementResidentArrivalPanel
extends Control


signal edit_requested


const DESIGN_SIZE := Vector2(1386, 917)
const FRAME_TEXTURE := preload(
	"res://assets/ui/resident_admission/runtime/"
	+ "replacement_arrival_modal_frame.png"
)
const FONT_FILE := preload(
	"res://assets/ui/startup/fonts/noto_sans_cjk_sc_medium/"
	+ "NotoSansCJKsc-Medium.otf"
)
const WARDROBE_CATALOG_PATH := (
	"res://assets/characters/resident_2d_rig_v1/wardrobe_v1/"
	+ "wardrobe_catalog.json"
)

const INK := Color("3f2818")
const MUTED_INK := Color("76583d")
const LIGHT_TEXT := Color("fff4dd")


var _candidate: Dictionary = {}
var _font: Font
var _stage: Control
var _portrait: TextureRect
var _name_label: Label
var _profile_list: VBoxContainer
var _primary_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 2600
	var font_variation := FontVariation.new()
	font_variation.base_font = FONT_FILE
	font_variation.spacing_glyph = 2
	font_variation.spacing_space = 0
	_font = font_variation
	_build_interface()
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)
	_render_candidate()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		# 入镇流程会一直暂停世界；Escape 不能把待处理居民留在后台。
		get_viewport().set_input_as_handled()


func present(candidate: Dictionary) -> void:
	_candidate = candidate.duplicate(true)
	if is_node_ready():
		_render_candidate()
		visible = true
		move_to_front()
		_primary_button.grab_focus.call_deferred()


func _build_interface() -> void:
	var veil := ColorRect.new()
	veil.name = "ReplacementArrivalVeil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color("11140fd8")
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	_stage = Control.new()
	_stage.name = "ReplacementArrivalStage"
	_stage.size = DESIGN_SIZE
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stage)

	var frame := TextureRect.new()
	frame.name = "ReplacementArrivalFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.texture = FRAME_TEXTURE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(frame)

	var title := _label("新居民申请入镇", 36)
	title.name = "ReplacementArrivalTitle"
	title.position = Vector2(150, 148)
	title.size = Vector2(1086, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage.add_child(title)

	_portrait = TextureRect.new()
	_portrait.name = "ReplacementArrivalPortrait"
	_portrait.position = Vector2(112, 270)
	_portrait.size = Vector2(250, 285)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_portrait)

	_name_label = _label("新居民", 28)
	_name_label.name = "ReplacementArrivalResidentName"
	_name_label.position = Vector2(100, 555)
	_name_label.size = Vector2(275, 52)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage.add_child(_name_label)

	var generated_badge := _label("随机生成", 17)
	generated_badge.name = "ReplacementArrivalGeneratedBadge"
	generated_badge.position = Vector2(142, 615)
	generated_badge.size = Vector2(190, 42)
	generated_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	generated_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	generated_badge.add_theme_color_override("font_color", MUTED_INK)
	_stage.add_child(generated_badge)

	var scroll := ScrollContainer.new()
	scroll.name = "ReplacementArrivalProfileScroll"
	scroll.position = Vector2(432, 264)
	scroll.size = Vector2(840, 374)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.add_child(scroll)

	_profile_list = VBoxContainer.new()
	_profile_list.name = "ReplacementArrivalProfileList"
	_profile_list.custom_minimum_size = Vector2(804, 0)
	_profile_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_profile_list)

	var pause_message := _label(
		"世界时间已暂停，请完成这位居民的入镇流程。",
		22,
	)
	pause_message.name = "ReplacementArrivalPauseMessage"
	pause_message.position = Vector2(150, 680)
	pause_message.size = Vector2(1086, 54)
	pause_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage.add_child(pause_message)

	_primary_button = Button.new()
	_primary_button.name = "ReplacementArrivalEditButton"
	_primary_button.position = Vector2(205, 792)
	_primary_button.size = Vector2(976, 88)
	_primary_button.text = "编辑入镇"
	_primary_button.focus_mode = Control.FOCUS_ALL
	_primary_button.add_theme_font_override("font", _font)
	_primary_button.add_theme_font_size_override("font_size", 30)
	for color_name: String in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
	]:
		_primary_button.add_theme_color_override(color_name, LIGHT_TEXT)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		_primary_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_primary_button.pressed.connect(func() -> void: edit_requested.emit())
	_primary_button.mouse_entered.connect(
		func() -> void: _primary_button.modulate = Color("fff1cc")
	)
	_primary_button.mouse_exited.connect(
		func() -> void: _primary_button.modulate = Color.WHITE
	)
	_stage.add_child(_primary_button)


func _render_candidate() -> void:
	if _profile_list == null:
		return
	for child: Node in _profile_list.get_children():
		child.queue_free()
	var record := _candidate.get("record", {}) as Dictionary
	var identity := _candidate.get("identity", {}) as Dictionary
	var attributes := record.get("attributes", {}) as Dictionary
	var social := record.get("socialState", {}) as Dictionary
	var resident_name := String(
		identity.get("residentName", attributes.get("name", "新居民")),
	)
	_name_label.text = resident_name
	_portrait.texture = _portrait_texture(attributes)

	var basics := GridContainer.new()
	basics.name = "ReplacementArrivalBasicFields"
	basics.columns = 2
	basics.add_theme_constant_override("h_separation", 22)
	basics.add_theme_constant_override("v_separation", 8)
	_profile_list.add_child(basics)
	for pair: Array in [
		["姓名", resident_name],
		["性别", String(attributes.get("gender", "未填写"))],
		["年龄", "%d 岁" % int(attributes.get("age", 0))],
		["住所", String(social.get("home", "未填写"))],
		["职业", String(social.get("job", "未填写"))],
		["职业地点", String(social.get("workplace", "未填写"))],
		["外观", "已随机生成"],
	]:
		basics.add_child(_field_label(String(pair[0]), String(pair[1]), 384, 38))

	var interests := _joined_interests(attributes)
	for pair: Array in [
		["核心欲望", String(attributes.get("desire", "未填写"))],
		["性格", String(attributes.get("personality", "未填写"))],
		["说话方式", String(attributes.get("speech", "未填写"))],
		["兴趣爱好", interests],
	]:
		_profile_list.add_child(_field_label(
			String(pair[0]),
			String(pair[1]),
			804,
			68,
		))


func _field_label(
	field_name: String,
	value: String,
	width: float,
	minimum_height: float,
) -> RichTextLabel:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		normalized = "未填写"
	var label := RichTextLabel.new()
	label.name = "Field_%s" % field_name
	label.custom_minimum_size = Vector2(width, minimum_height)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.fit_content = true
	label.scroll_active = false
	label.bbcode_enabled = true
	label.text = "[color=#76583d]%s：[/color]%s" % [field_name, normalized]
	label.add_theme_font_override("normal_font", _font)
	label.add_theme_font_override("bold_font", _font)
	label.add_theme_font_size_override("normal_font_size", 20)
	label.add_theme_font_size_override("bold_font_size", 20)
	label.add_theme_color_override("default_color", INK)
	label.add_theme_constant_override("line_separation", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _joined_interests(attributes: Dictionary) -> String:
	var values: Array[String] = []
	for key: String in ["interests", "customInterests"]:
		var source: Variant = attributes.get(key, [])
		if not source is Array:
			continue
		for value: Variant in source as Array:
			var normalized := String(value).strip_edges()
			if not normalized.is_empty() and not values.has(normalized):
				values.append(normalized)
	return "、".join(values) if not values.is_empty() else "未填写"


func _portrait_texture(attributes: Dictionary) -> Texture2D:
	var appearance_id := String(attributes.get("appearance", ""))
	if appearance_id.is_empty() or not FileAccess.file_exists(WARDROBE_CATALOG_PATH):
		return null
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(WARDROBE_CATALOG_PATH),
	)
	if not parsed is Dictionary:
		return null
	for value: Variant in (parsed as Dictionary).get("loadouts", []) as Array:
		if not value is Dictionary:
			continue
		var loadout := value as Dictionary
		if String(loadout.get("appearanceId", "")) != appearance_id:
			continue
		var portrait_path := String(loadout.get("portraitPath", ""))
		if ResourceLoader.exists(portrait_path, "Texture2D"):
			return ResourceLoader.load(portrait_path, "Texture2D") as Texture2D
	return null


func _label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return label


func _apply_layout() -> void:
	if _stage == null:
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	var scale_value := minf(
		(viewport_size.x - 32.0) / DESIGN_SIZE.x,
		(viewport_size.y - 32.0) / DESIGN_SIZE.y,
	)
	scale_value = clampf(scale_value, 0.55, 1.0)
	_stage.scale = Vector2.ONE * scale_value
	_stage.position = (viewport_size - DESIGN_SIZE * scale_value) * 0.5
