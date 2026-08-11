class_name ResidentActionCloseButton
extends Button


const CLOSE_TEXTURE := preload(
	"res://assets/ui/resident_action_menu/final/"
	+ "resident_action_close_v3.png"
)


var _texture: TextureRect


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "关闭"
	accessibility_name = "关闭"
	custom_minimum_size = Vector2(64, 64)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_texture = TextureRect.new()
	_texture.name = "CloseTextureAsset"
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture.texture = CLOSE_TEXTURE
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture)
	# 视觉状态只随按压/焦点/悬停变化，信号驱动即可，无需逐帧刷新。
	button_down.connect(_update_asset_state)
	button_up.connect(_update_asset_state)
	focus_entered.connect(_update_asset_state)
	focus_exited.connect(_update_asset_state)
	mouse_entered.connect(_update_asset_state)
	mouse_exited.connect(_update_asset_state)
	_update_asset_state()


func set_action_enabled(action_enabled: bool) -> void:
	disabled = not action_enabled
	mouse_default_cursor_shape = (
		Control.CURSOR_ARROW
		if disabled
		else Control.CURSOR_POINTING_HAND
	)
	_update_asset_state()


func debug_asset_ownership() -> Dictionary:
	return {
		"operationControl": name,
		"outerFrameOwner": _texture.name,
		"symbolOwner": _texture.name,
		"duplicateOuterFrame": false,
		"componentType": "page_local_image_operation_control",
		"candidateId": "ui.resident-action-menu.textless-parts.candidate-v3",
		"goldFocusFrame": false,
	}


func _update_asset_state() -> void:
	if _texture == null:
		return
	var tint := Color.WHITE
	if disabled:
		tint = Color(0.62, 0.59, 0.52, 0.86)
	elif get_draw_mode() == BaseButton.DRAW_PRESSED:
		tint = Color(0.91, 0.80, 0.68, 1.0)
	elif has_focus():
		tint = Color(1.0, 1.0, 0.80, 1.0)
	elif is_hovered():
		tint = Color(1.0, 0.95, 0.84, 1.0)
	_texture.modulate = tint
