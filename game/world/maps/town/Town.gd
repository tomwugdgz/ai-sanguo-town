# 正式小镇地图。
# 已验收的局部修补已烘焙进单张正式底图，并接入功能建筑与住宅室内。
extends "res://world/maps/town/TownBase.gd"

const HOUSE_TEST_SPAWN := Vector2(2040.0, 3040.0)


func _runtime_map_id() -> String:
	return "town"


func _process(_delta: float) -> void:
	# 正式地图保持静态环境，但室内家具编辑仍需实时跟随鼠标和刷新脚点排序。
	_update_cafe_depth_order()
	_update_cafe_furniture_placement_preview()


func _build_water_animation() -> void:
	pass


func _build_environment_test() -> void:
	pass


func _build_ui() -> void:
	if not _allows_runtime_test_ui():
		return
	var layer := CanvasLayer.new()
	layer.name = "TownUi"
	layer.layer = 100
	add_child(layer)
	_build_camera_controls(layer)
	_build_cafe_furniture_panel(layer)


func _allows_runtime_test_ui() -> bool:
	return (
		OS.is_debug_build()
		and OS.get_environment("AI_TOWN_INTERNAL_PLAYTEST") == "1"
	)


func _build_camera_controls(layer: CanvasLayer) -> void:
	var controls := HBoxContainer.new()
	controls.name = "CameraControls"
	controls.anchor_top = 1.0
	controls.anchor_bottom = 1.0
	controls.offset_left = 20.0
	controls.offset_top = -70.0
	controls.offset_right = 580.0
	controls.offset_bottom = -18.0
	controls.add_theme_constant_override("separation", 10)
	layer.add_child(controls)

	var overview_button := Button.new()
	overview_button.name = "OverviewMapButton"
	overview_button.text = "全览地图  0"
	overview_button.custom_minimum_size = Vector2(176.0, 52.0)
	overview_button.add_theme_font_size_override("font_size", 18)
	overview_button.pressed.connect(_show_map_overview)
	controls.add_child(overview_button)

	var follow_button := Button.new()
	follow_button.name = "FollowPlayerButton"
	follow_button.text = "跟随人物  F"
	follow_button.custom_minimum_size = Vector2(176.0, 52.0)
	follow_button.add_theme_font_size_override("font_size", 18)
	follow_button.pressed.connect(_focus_player)
	controls.add_child(follow_button)

	var occlusion_debug_button := Button.new()
	occlusion_debug_button.name = "OcclusionDebugButton"
	occlusion_debug_button.text = "地图标记：关  O"
	occlusion_debug_button.custom_minimum_size = Vector2(176.0, 52.0)
	occlusion_debug_button.add_theme_font_size_override("font_size", 18)
	occlusion_debug_button.pressed.connect(_toggle_map_overlays)
	controls.add_child(occlusion_debug_button)


func _emit_footstep_effect() -> void:
	pass


func _update_status() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if (
		_allows_runtime_test_ui()
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_J
	):
		_teleport_to_house_entry()


func _teleport_to_house_entry() -> void:
	_player.position = HOUSE_TEST_SPAWN
	_update_camera_target(true)
