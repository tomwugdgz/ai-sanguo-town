class_name ResidentActionBubble
extends Button


const BUTTON_TEXTURES := {
	"follow": preload(
		"res://assets/ui/resident_action_menu/final/"
		+ "resident_action_button_follow_v3.png"
	),
	"status": preload(
		"res://assets/ui/resident_action_menu/final/"
		+ "resident_action_button_status_v3.png"
	),
	"relationship": preload(
		"res://assets/ui/resident_action_menu/final/"
		+ "resident_action_button_relationship_v3.png"
	),
	"memory": preload(
		"res://assets/ui/resident_action_menu/final/"
		+ "resident_action_button_memory_v3.png"
	),
	"inner": preload(
		"res://assets/ui/resident_action_menu/final/"
		+ "resident_action_button_inner_v3.png"
	),
	"kill": preload(
		"res://assets/ui/resident_action_menu/final/"
		+ "resident_action_button_kill_v3.png"
	),
}
const HALO_TEXTURE := preload(
	"res://assets/ui/resident_action_menu/final/"
	+ "resident_action_halo.png"
)
const APPROVED_TAIL_DIRECTIONS := {
	"follow": "down",
	"status": "right",
	"relationship": "left",
	"memory": "up_right",
	"inner": "up_left",
	"kill": "up",
}
const LABEL_RECTS_160 := {
	"follow": Rect2(28, 82, 104, 48),
	"status": Rect2(24, 84, 112, 48),
	"relationship": Rect2(24, 84, 112, 48),
	"memory": Rect2(24, 84, 112, 48),
	"inner": Rect2(24, 84, 112, 48),
	"kill": Rect2(24, 84, 112, 48),
}

const COLOR_HONEY := Color("e3aa38")
const COLOR_MOSS := Color("557b2a")
const COLOR_TERRACOTTA := Color("b94d2d")
const COLOR_ERROR := Color("a7352b")

const STATE_IDLE := "idle"
const STATE_LOADING := "loading"
const STATE_SUCCESS := "success"
const STATE_REJECTED := "rejected"
const STATE_ERROR := "error"
const STATE_DISABLED := "disabled"

const DISABLED_REASON_COPY := {
	"RESIDENT_IDENTITY_UNAVAILABLE": "居民身份暂不可用",
	"RESIDENT_DETAIL_INTERFACE_MISSING": "居民状态暂不可查看",
	"RESIDENT_RELATIONSHIP_PUBLIC_INTERFACE_MISSING": "关系资料暂不可查看",
	"RESIDENT_MEMORY_PUBLIC_INTERFACE_MISSING": "记忆资料暂不可查看",
	"AGENT_INNER_OBSERVATION_INTERFACE_MISSING": "内心观察暂不可用",
	"INNER_OBSERVATION_INTERFACE_MISSING": "内心观察暂不可用",
	"INNER_OBSERVATION_TEMPORARILY_UNAVAILABLE": "内心观察暂时没有准备好",
	"OPERATION_IN_PROGRESS": "上一项操作仍在处理中",
	"SCREEN_TRANSITIONING": "页面正在切换，请稍候",
	"ACTION_DISABLED": "此操作暂不可用",
}


var menu_id := ""
var action_key := ""
var icon_key := ""
var semantic_order := 0
var visual_state := STATE_IDLE
var state_emphasized := false
var reduce_motion := false
var breath_period_seconds := 2.1
var tail_side := ""
var action_enabled := false
var disabled_reason := ""

var _halo: TextureRect
var _art: TextureRect
var _label: Label
var _display_text := ""
var _breath_elapsed := 0.0
var _opening := false
var _opening_elapsed := 0.0
var _opening_delay := 0.0
var _opening_duration := 0.28
var _opening_start := Vector2.ZERO
var _opening_target := Vector2.ZERO
var _closing := false
var _closing_elapsed := 0.0
var _closing_delay := 0.0
var _closing_duration := 0.18
var _closing_start := Vector2.ZERO
var _closing_target := Vector2.ZERO


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	_halo = TextureRect.new()
	_halo.name = "HaloAsset"
	_halo.texture = HALO_TEXTURE
	_halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_halo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_halo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_halo)

	_art = TextureRect.new()
	_art.name = "ApprovedButtonArt"
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

	_label = Label.new()
	_label.name = "Label"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.clip_text = true
	_label.max_lines_visible = 1
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_label)
	_update_asset_geometry()
	# 几何只随尺寸与按压状态变化；逐帧工作只保留可见时的呼吸动画。
	resized.connect(_update_asset_geometry)
	button_down.connect(_update_asset_geometry)
	button_up.connect(_update_asset_geometry)
	visibility_changed.connect(_sync_process_state)
	_sync_process_state()


func _sync_process_state() -> void:
	set_process(is_visible_in_tree())


func configure(
	item: Dictionary,
	component_size: Vector2,
	multiline: bool,
	motion: Dictionary
) -> void:
	menu_id = str(item.get("id", ""))
	action_key = str(item.get("actionKey", ""))
	icon_key = str(item.get("iconKey", ""))
	tail_side = str(APPROVED_TAIL_DIRECTIONS.get(menu_id, ""))
	semantic_order = int(item.get("semanticOrder", 0))
	_display_text = str(item.get("label", ""))
	if multiline and _display_text.length() > 2:
		var split := int(ceil(_display_text.length() / 2.0))
		_display_text = (
			_display_text.substr(0, split)
			+ "\n"
			+ _display_text.substr(split)
		)
	reduce_motion = bool(motion.get("reduceMotion", false))
	breath_period_seconds = maxf(
		0.8,
		float(motion.get("breathPeriodMs", 2100)) / 1000.0
	)
	custom_minimum_size = component_size
	size = component_size
	visible = true
	if _label != null:
		_label.text = _display_text
		_label.autowrap_mode = (
			TextServer.AUTOWRAP_OFF
			if not multiline
			else TextServer.AUTOWRAP_WORD_SMART
		)
		_label.max_lines_visible = 1 if not multiline else 2
		_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_label.add_theme_constant_override("line_spacing", 8)
	if _art != null:
		_art.texture = BUTTON_TEXTURES.get(menu_id)
	tooltip_text = str(item.get("label", ""))
	accessibility_name = str(item.get("label", ""))
	_update_asset_geometry()
	queue_redraw()


func apply_action_contract(action: Dictionary) -> void:
	action_enabled = bool(action.get("enabled", false))
	disabled_reason = str(action.get("disabledReason", "")).strip_edges()
	var reason_copy := _disabled_reason_copy(disabled_reason)
	tooltip_text = _display_text
	accessibility_name = _display_text
	if not action_enabled and not reason_copy.is_empty():
		tooltip_text = "%s\n%s" % [_display_text, reason_copy]
		accessibility_name = "%s，已禁用：%s" % [_display_text, reason_copy]


func set_label_font_size(font_size: int) -> void:
	if _label == null:
		return
	_label.add_theme_font_size_override("font_size", maxi(font_size, 1))


func set_visual_state(
	state: String,
	emphasized: bool,
	is_action_enabled: bool
) -> void:
	visual_state = state
	state_emphasized = emphasized
	disabled = not is_action_enabled
	mouse_default_cursor_shape = (
		Control.CURSOR_ARROW
		if disabled
		else Control.CURSOR_POINTING_HAND
	)
	if _label != null:
		_label.modulate = (
			Color(0.62, 0.58, 0.49, 1.0)
			if disabled
			else Color.WHITE
		)
	_update_asset_visual_state()
	queue_redraw()


func set_tail_side(_side: String) -> void:
	# Every approved complete button texture owns exactly one tail. The World
	# layout selects a texture whose baked tail already points at the resident.
	tail_side = str(APPROVED_TAIL_DIRECTIONS.get(menu_id, ""))


func play_open(
	target_position: Vector2,
	screen_anchor: Vector2,
	delay_seconds: float,
	duration_seconds: float
) -> void:
	_opening_target = target_position.round()
	_opening_delay = maxf(0.0, delay_seconds)
	_opening_duration = clampf(
		0.12 if reduce_motion else duration_seconds,
		0.10,
		0.40
	)
	_opening_elapsed = 0.0
	_opening = true
	_closing = false
	_opening_start = (
		_opening_target
		if reduce_motion
		else (
			screen_anchor
			- size * 0.5
		).round()
	)
	position = _opening_start
	modulate.a = 0.0


func place_immediately(target_position: Vector2) -> void:
	_opening = false
	_closing = false
	_opening_target = target_position.round()
	position = _opening_target
	modulate.a = 1.0


func play_close(
	screen_anchor: Vector2,
	delay_seconds: float,
	duration_seconds: float
) -> void:
	_opening = false
	_closing = true
	_closing_elapsed = 0.0
	_closing_delay = maxf(0.0, delay_seconds)
	_closing_duration = clampf(
		0.12 if reduce_motion else duration_seconds,
		0.10,
		0.28
	)
	_closing_start = position.round()
	_closing_target = (
		_closing_start
		if reduce_motion
		else (screen_anchor - size * 0.5).round()
	)
	modulate.a = 1.0


func debug_text_rect() -> Rect2:
	if _label == null:
		return Rect2()
	return Rect2(_label.position, _label.size)


func debug_asset_ownership() -> Dictionary:
	return {
		"operationControl": name,
		"outerFrameOwner": _art.name,
		"iconSlotFrameOwner": "",
		"iconContentOwner": _art.name,
		"textOwner": _label.name,
		"tailOwner": _art.name,
		"haloOwner": _halo.name,
		"duplicateOuterFrame": false,
		"duplicateIconSlotFrame": false,
		"shellComponentType": "page_local_complete_operation_texture",
		"semanticSlotBakedIntoShell": true,
		"semanticIconBakedIntoArt": true,
		"singleTailBakedIntoArt": true,
		"approvedTailDirection": tail_side,
		"shellUsesAnisotropicFullImageResize": false,
		"programmaticFrameFallback": false,
		"commonApproximation": false,
		"goldFocusFrame": false,
		"iconSlotRect": Rect2(),
		"iconRect": Rect2(),
		"labelRect": Rect2(_label.position, _label.size),
	}


func debug_action_contract() -> Dictionary:
	return {
		"enabled": action_enabled,
		"disabledReason": disabled_reason,
		"disabledReasonCopy": _disabled_reason_copy(disabled_reason),
		"tooltip": tooltip_text,
		"accessibilityName": accessibility_name,
	}


func _process(delta: float) -> void:
	_breath_elapsed += delta
	if _opening:
		_opening_elapsed += delta
		if _opening_elapsed < _opening_delay:
			modulate.a = 0.0
		else:
			var elapsed := _opening_elapsed - _opening_delay
			var progress := clampf(elapsed / _opening_duration, 0.0, 1.0)
			var eased := 1.0 - pow(1.0 - progress, 3.0)
			position = _opening_start.lerp(
				_opening_target,
				eased
			).round()
			modulate.a = progress
			if progress >= 1.0:
				_opening = false
				position = _opening_target
				modulate.a = 1.0
	elif _closing:
		_closing_elapsed += delta
		if _closing_elapsed >= _closing_delay:
			var elapsed := _closing_elapsed - _closing_delay
			var progress := clampf(elapsed / _closing_duration, 0.0, 1.0)
			var eased := progress * progress
			position = _closing_start.lerp(
				_closing_target,
				eased
			).round()
			modulate.a = 1.0 - progress
			if progress >= 1.0:
				_closing = false
				visible = false
	_update_asset_visual_state()
	if state_emphasized and visual_state == STATE_LOADING:
		queue_redraw()


func _draw() -> void:
	if state_emphasized:
		_draw_state_badge(
			Rect2(
				Vector2(8, 10),
				Vector2(size.x - 16, size.y - 20)
			)
		)


func _update_asset_geometry() -> void:
	if _art == null:
		return
	var pressed_offset := (
		Vector2(0, 2)
		if get_draw_mode() == BaseButton.DRAW_PRESSED
		else Vector2.ZERO
	)
	_halo.position = Vector2(-6, -6)
	_halo.size = size + Vector2(12, 12)
	_art.position = pressed_offset
	_art.size = size
	var canonical_rect := LABEL_RECTS_160.get(
		menu_id,
		Rect2(24, 84, 112, 48)
	) as Rect2
	_label.position = Vector2(
		canonical_rect.position.x / 160.0 * size.x,
		canonical_rect.position.y / 160.0 * size.y
	).round() + pressed_offset
	_label.size = Vector2(
		maxf(1.0, canonical_rect.size.x / 160.0 * size.x),
		maxf(48.0, canonical_rect.size.y / 160.0 * size.y)
	).round()
func _update_asset_visual_state() -> void:
	if _art == null:
		return
	var art_tint := Color.WHITE
	if disabled or visual_state == STATE_DISABLED:
		art_tint = Color(0.64, 0.61, 0.55, 0.88)
	elif state_emphasized and visual_state == STATE_SUCCESS:
		art_tint = Color(0.88, 1.0, 0.78, 1.0)
	elif state_emphasized and visual_state == STATE_REJECTED:
		art_tint = Color(1.0, 0.86, 0.76, 1.0)
	elif state_emphasized and visual_state == STATE_ERROR:
		art_tint = Color(1.0, 0.76, 0.72, 1.0)
	elif has_focus():
		art_tint = Color(1.0, 0.98, 0.90, 1.0)
	elif is_hovered():
		art_tint = Color(1.0, 0.96, 0.88, 1.0)
	_art.modulate = art_tint

	var halo_alpha := 0.0
	var halo_tint := Color.WHITE
	if (
		not reduce_motion
		and not disabled
		and visual_state == STATE_IDLE
	):
		halo_alpha = (
			0.12
			+ (sin(_breath_elapsed / breath_period_seconds * TAU) + 1.0)
			* 0.055
		)
	if is_hovered():
		halo_alpha = maxf(halo_alpha, 0.24)
	if state_emphasized:
		match visual_state:
			STATE_LOADING:
				halo_alpha = 0.34
			STATE_SUCCESS:
				halo_alpha = 0.48
				halo_tint = Color("9bc45f")
			STATE_REJECTED:
				halo_alpha = 0.45
				halo_tint = Color("d77b45")
			STATE_ERROR:
				halo_alpha = 0.55
				halo_tint = Color("c84e3e")
	_halo.visible = halo_alpha > 0.0
	_halo.modulate = Color(
		halo_tint.r,
		halo_tint.g,
		halo_tint.b,
		halo_alpha
	)


func _disabled_reason_copy(reason: String) -> String:
	if reason.is_empty():
		return ""
	return str(DISABLED_REASON_COPY.get(reason, "此操作暂不可用"))


func _draw_state_badge(paper_rect: Rect2) -> void:
	var badge_rect := Rect2(
		paper_rect.end - Vector2(26, 22),
		Vector2(18, 18)
	)
	match visual_state:
		STATE_LOADING:
			var phase := int(_breath_elapsed * 6.0) % 3
			for index: int in 3:
				var color := COLOR_HONEY
				color.a = 1.0 if index == phase else 0.45
				draw_rect(
					Rect2(
						badge_rect.position + Vector2(index * 6, 7),
						Vector2(4, 4)
					),
					color,
					true
				)
		STATE_SUCCESS:
			draw_polyline(
				PackedVector2Array([
					badge_rect.position + Vector2(1, 9),
					badge_rect.position + Vector2(6, 14),
					badge_rect.position + Vector2(17, 2),
				]),
				COLOR_MOSS,
				4.0,
				false
			)
		STATE_REJECTED:
			draw_rect(badge_rect, COLOR_TERRACOTTA, false, 3.0, false)
			draw_line(
				badge_rect.position + Vector2(4, 9),
				badge_rect.end - Vector2(4, 9),
				COLOR_TERRACOTTA,
				3.0,
				false
			)
		STATE_ERROR:
			draw_line(
				badge_rect.position + Vector2(3, 3),
				badge_rect.end - Vector2(3, 3),
				COLOR_ERROR,
				4.0,
				false
			)
			draw_line(
				Vector2(badge_rect.end.x - 3, badge_rect.position.y + 3),
				Vector2(badge_rect.position.x + 3, badge_rect.end.y - 3),
				COLOR_ERROR,
				4.0,
				false
			)
