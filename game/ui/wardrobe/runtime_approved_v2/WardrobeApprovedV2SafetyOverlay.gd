extends Control


const PLATFORM_MARGIN := 32.0
const SAFE_COLOR := Color(0.18, 0.95, 0.55, 0.95)
const HIT_COLOR := Color(1.0, 0.25, 0.42, 0.95)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var runtime := get_parent()
	if runtime == null or not runtime.has_method("get_hit_target_rects_in_viewport"):
		return
	var safe_rect := Rect2(
		Vector2(PLATFORM_MARGIN, PLATFORM_MARGIN),
		Vector2(
			maxf(0.0, size.x - PLATFORM_MARGIN * 2.0),
			maxf(0.0, size.y - PLATFORM_MARGIN * 2.0)
		)
	)
	draw_rect(safe_rect, SAFE_COLOR, false, 3.0)
	var hit_rects := runtime.get_hit_target_rects_in_viewport() as Dictionary
	for target_id: String in hit_rects:
		draw_rect(hit_rects[target_id] as Rect2, HIT_COLOR, false, 2.0)
