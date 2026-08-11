extends RefCounted


const DESIGN_SIZE := Vector2i(1920, 1080)
const MINIMUM_WINDOW_SIZE := Vector2i(960, 540)


static func canvas_metrics(physical_size: Vector2i) -> Dictionary:
	if physical_size.x <= 0 or physical_size.y <= 0:
		return {
			"valid": false,
			"scale": 0.0,
			"logicalSize": Vector2.ZERO,
			"renderedDesignRect": Rect2(),
		}
	var physical := Vector2(physical_size)
	var design_rect := centered_design_rect(physical, Vector2(DESIGN_SIZE))
	var scale_factor := design_rect.size.x / float(DESIGN_SIZE.x)
	var logical_size := physical / scale_factor
	if absf(logical_size.x - DESIGN_SIZE.x) < 0.5:
		logical_size.x = DESIGN_SIZE.x
	if absf(logical_size.y - DESIGN_SIZE.y) < 0.5:
		logical_size.y = DESIGN_SIZE.y
	return {
		"valid": true,
		"scale": scale_factor,
		"logicalSize": logical_size,
		"renderedDesignRect": design_rect,
	}


static func centered_design_rect(
	available_size: Vector2,
	design_size: Vector2,
) -> Rect2:
	if (
		available_size.x <= 0.0
		or available_size.y <= 0.0
		or design_size.x <= 0.0
		or design_size.y <= 0.0
	):
		return Rect2()
	var scale_factor := minf(
		available_size.x / design_size.x,
		available_size.y / design_size.y,
	)
	var rendered_size := design_size * scale_factor
	return Rect2(
		(available_size - rendered_size) * 0.5,
		rendered_size,
	)
