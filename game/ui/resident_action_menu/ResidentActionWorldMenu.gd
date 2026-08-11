class_name ResidentActionWorldMenu
extends "res://ui/resident_action_menu/ResidentActionMenu.gd"


const WORLD_BUBBLE_SCRIPT := preload(
	"res://ui/resident_action_menu/ResidentActionBubble.gd"
)
const WORLD_THEME := preload(
	"res://ui/common/components/ZhengGeTypography.tres"
)
const WORLD_BUBBLE_SIZE := Vector2(112.0, 112.0)
const WORLD_LABEL_FONT_SIZE := 22
const WORLD_ANCHOR := Vector2.ZERO
const WORLD_UP_CENTERS := {
	"follow": Vector2(0.0, -292.0),
	"status": Vector2(-142.0, -204.0),
	"relationship": Vector2(142.0, -204.0),
	"memory": Vector2(-142.0, -76.0),
	"inner": Vector2(142.0, -76.0),
	"kill": Vector2(0.0, 96.0),
}


func _ready() -> void:
	visible = false
	position = Vector2.ZERO
	size = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = WORLD_THEME
	z_index = 190
	z_as_relative = false
	_build_interface()
	if not _view_model.is_empty():
		_render(true)


func _build_interface() -> void:
	_bubble_layer = Control.new()
	_bubble_layer.name = "WorldBubbleLayer"
	_bubble_layer.position = Vector2.ZERO
	_bubble_layer.size = Vector2.ZERO
	_bubble_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble_layer)
	for item_id: String in MENU_ITEM_IDS:
		var bubble := WORLD_BUBBLE_SCRIPT.new() as ResidentActionBubble
		bubble.name = item_id.capitalize() + "Bubble"
		bubble.pressed.connect(_on_bubble_pressed.bind(item_id))
		bubble.visible = false
		_bubble_layer.add_child(bubble)
		_bubbles[item_id] = bubble


func _render(play_opening: bool) -> void:
	if _view_model.is_empty():
		return
	visible = true
	var data := _view_model.get("data", {}) as Dictionary
	_menu_order = FORMAL_MENU_ORDER.duplicate()
	_render_world_bubbles(data, play_opening and not _has_rendered)
	_has_rendered = true


func _render_world_bubbles(data: Dictionary, play_opening: bool) -> void:
	var focused_action_key := _focused_action_key()
	var item_by_id: Dictionary = {}
	for item_value: Variant in data.get("menuItems", []) as Array:
		if item_value is Dictionary:
			var item := item_value as Dictionary
			item_by_id[String(item.get("id", ""))] = item
	var motion := data.get("motion", {}) as Dictionary
	var operation := _view_model.get("operation", {}) as Dictionary
	var operation_status := String(operation.get("status", "idle"))
	var active_id := _active_item_id(operation)
	var actions := _view_model.get("actions", {}) as Dictionary
	var layout := _world_layout(data)
	var centers := layout.get("centers", {}) as Dictionary
	_current_orientation = String(layout.get("orientation", "up"))
	for bubble_value: Variant in _bubbles.values():
		var hidden_bubble := bubble_value as ResidentActionBubble
		if hidden_bubble != null:
			hidden_bubble.visible = false
	for index: int in _menu_order.size():
		var item_id := _menu_order[index]
		var bubble := _bubbles.get(item_id) as ResidentActionBubble
		var item := item_by_id.get(item_id, {}) as Dictionary
		if bubble == null or item.is_empty():
			continue
		bubble.configure(item, WORLD_BUBBLE_SIZE, false, motion)
		bubble.set_label_font_size(WORLD_LABEL_FONT_SIZE)
		var action_key := String(item.get("actionKey", ""))
		var action := actions.get(action_key, {}) as Dictionary
		bubble.apply_action_contract(action)
		var emphasized := item_id == active_id and operation_status != "idle"
		bubble.set_visual_state(
			operation_status if emphasized else "idle",
			emphasized,
			bool(action.get("enabled", false)),
		)
		var center := centers.get(item_id, Vector2.ZERO) as Vector2
		bubble.set_tail_side(_tail_toward_resident(center))
		var target_position := center - WORLD_BUBBLE_SIZE * 0.5
		if play_opening:
			bubble.play_open(
				target_position,
				WORLD_ANCHOR,
				float(motion.get("itemStaggerMs", 28)) / 1000.0 * index,
				float(motion.get("openingDurationMs", 280)) / 1000.0,
			)
		else:
			bubble.place_immediately(target_position)
	_rebuild_focus_controls()
	_restore_action_focus.call_deferred(focused_action_key)


func _world_layout(_data: Dictionary) -> Dictionary:
	var centers := WORLD_UP_CENTERS.duplicate(true)
	return {
		"orientation": "up",
		"centers": centers,
	}


func _tail_toward_resident(center: Vector2) -> String:
	var toward := -center
	var horizontal := (
		"right" if toward.x > 0.0 else "left"
	)
	var vertical := (
		"down" if toward.y > 0.0 else "up"
	)
	if absf(toward.x) > 52.0 and absf(toward.y) > 52.0:
		return "%s_%s" % [vertical, horizontal]
	if absf(toward.x) > absf(toward.y):
		return horizontal
	return vertical


func debug_world_anchor_snapshot() -> Dictionary:
	var bubble_rects: Dictionary = {}
	for item_id: String in _menu_order:
		var bubble := _bubbles.get(item_id) as ResidentActionBubble
		if bubble != null:
			bubble_rects[item_id] = Rect2(bubble.position, bubble.size)
	return {
		"coordinateSpace": "resident_local_world",
		"worldAnchored": true,
		"screenProjectionTracking": false,
		"orientation": _current_orientation,
		"bubbleSize": WORLD_BUBBLE_SIZE,
		"bubbleRects": bubble_rects,
		"parentClass": get_parent().get_class() if get_parent() != null else "",
	}
