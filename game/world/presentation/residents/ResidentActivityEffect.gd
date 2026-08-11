class_name ResidentActivityEffect
extends Node2D


const WORK_CLOUD_CYCLE_SECONDS := 0.72
const WORK_CLOUD_FRAME_COUNT := 8
const WORK_CLOUD_FRAME_SIZE := 288.0
const WORK_CLOUD_DISPLAY_SIZE := Vector2(58.0, 58.0)
const WORK_CLOUD_SHEET := preload(
	"res://assets/effects/resident_activity/work_action_cloud_sheet_v1.png"
)

var _effect_kind := ""
var _phase := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	visible = false


func set_effect(effect_kind: String) -> void:
	if effect_kind == _effect_kind:
		return
	_effect_kind = effect_kind
	_phase = 0.0
	visible = not _effect_kind.is_empty()
	set_process(visible)
	queue_redraw()


func set_facing(direction_id: String) -> void:
	var side := -1.0 if direction_id == "left" else 1.0
	if direction_id in ["up", "down"]:
		side = 1.0
	position = Vector2(42.0 * side, -73.0)
	queue_redraw()


func get_effect_kind() -> String:
	return _effect_kind


func _process(delta: float) -> void:
	_phase = fmod(_phase + maxf(delta, 0.0), WORK_CLOUD_CYCLE_SECONDS)
	queue_redraw()


func _draw() -> void:
	if _effect_kind != "work_action_cloud":
		return
	var frame_index := mini(
		int(
			floor(
				_phase
				/ WORK_CLOUD_CYCLE_SECONDS
				* float(WORK_CLOUD_FRAME_COUNT)
			)
		),
		WORK_CLOUD_FRAME_COUNT - 1,
	)
	var source_rect := Rect2(
		Vector2(float(frame_index) * WORK_CLOUD_FRAME_SIZE, 0.0),
		Vector2.ONE * WORK_CLOUD_FRAME_SIZE,
	)
	var target_rect := Rect2(
		-WORK_CLOUD_DISPLAY_SIZE * 0.5,
		WORK_CLOUD_DISPLAY_SIZE,
	)
	draw_texture_rect_region(
		WORK_CLOUD_SHEET,
		target_rect,
		source_rect,
		Color.WHITE,
		false,
	)
