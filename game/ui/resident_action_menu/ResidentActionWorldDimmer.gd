class_name ResidentActionWorldDimmer
extends Control


const SCRIM := Color(0.075, 0.055, 0.04, 0.48)
const RING_GLOW_RADIUS := Vector2(34.0, 12.0)
const RING_MID_RADIUS := Vector2(30.0, 10.0)
const RING_CORE_RADIUS := Vector2(27.0, 8.0)
const RING_GLOW_COLOR := Color(1.0, 0.73, 0.22, 0.10)
const RING_MID_COLOR := Color(1.0, 0.80, 0.31, 0.24)
const RING_CORE_COLOR := Color(1.0, 0.91, 0.58, 0.78)


var viewport_rect := Rect2()
var focus_ring_center := Vector2.ZERO
var focus_ring_visible := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(new_viewport_rect: Rect2, new_focus_rect: Rect2) -> void:
	viewport_rect = new_viewport_rect
	focus_ring_visible = (
		new_focus_rect.size.x > 0.0
		and new_focus_rect.size.y > 0.0
	)
	if focus_ring_visible:
		# The projection focus rect starts at the resident's world origin,
		# which is the feet anchor in viewport-logical coordinates.
		focus_ring_center = Vector2(
			new_focus_rect.get_center().x,
			new_focus_rect.position.y + 10.0
		).round()
	queue_redraw()


func debug_visual_contract() -> Dictionary:
	return {
		"drawMode": "uniform_scrim_with_screen_space_foot_ring",
		"visibleFocusRect": false,
		"createsResidentFocusRing": true,
		"focusRingOwner": "resident_action_menu_screen_space_ring",
		"cameraInvariant": true,
		"ringCenter": focus_ring_center,
		"ringGlowDiameter": RING_GLOW_RADIUS * 2.0,
		"ringCoreDiameter": RING_CORE_RADIUS * 2.0,
	}


func _draw() -> void:
	var canvas := viewport_rect
	if canvas.size.x <= 0.0 or canvas.size.y <= 0.0:
		canvas = Rect2(Vector2.ZERO, size)
	# The menu keeps focusRect for placement/clearance. The world resident
	# target uses a camera-invariant screen-space foot ring; focusRect itself
	# never becomes a rectangular bright hole or visible outline.
	draw_rect(canvas, SCRIM, true)
	if not focus_ring_visible:
		return
	_draw_ellipse_ring(
		focus_ring_center,
		RING_GLOW_RADIUS,
		RING_GLOW_COLOR,
		7.0
	)
	_draw_ellipse_ring(
		focus_ring_center,
		RING_MID_RADIUS,
		RING_MID_COLOR,
		4.0
	)
	_draw_ellipse_ring(
		focus_ring_center,
		RING_CORE_RADIUS,
		RING_CORE_COLOR,
		2.0
	)


func _draw_ellipse_ring(
	center: Vector2,
	radius: Vector2,
	color: Color,
	width: float
) -> void:
	var points := PackedVector2Array()
	for index: int in 49:
		var angle := TAU * float(index) / 48.0
		points.append(
			center
			+ Vector2(
				cos(angle) * radius.x,
				sin(angle) * radius.y
			)
		)
	draw_polyline(points, color, width, false)
