# PROTOTYPE - NOT FOR PRODUCTION
# Question: Can every validation demo return to the shared launcher without modifying each demo?
# Date: 2026-07-14
extends Node

const LAUNCHER_PATH := "res://world/prototypes/demo_launcher/DemoLauncher.tscn"

var _navigation_layer := CanvasLayer.new()
var _back_button := Button.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_navigation_layer.name = "DemoNavigationOverlay"
	_navigation_layer.layer = 1000
	add_child(_navigation_layer)
	_back_button.name = "BackToDemoLauncher"
	_back_button.text = "返回入口  F10"
	_back_button.anchor_left = 1.0
	_back_button.anchor_right = 1.0
	_back_button.offset_left = -222.0
	_back_button.offset_top = 18.0
	_back_button.offset_right = -18.0
	_back_button.offset_bottom = 70.0
	_back_button.add_theme_font_size_override("font_size", 19)
	_back_button.pressed.connect(_return_to_launcher)
	_navigation_layer.add_child(_back_button)
	_update_back_button()


func _process(_delta: float) -> void:
	_update_back_button()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_tree().quit()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F10:
		_return_to_launcher()
		get_viewport().set_input_as_handled()


func _update_back_button() -> void:
	var current_scene := get_tree().current_scene
	_back_button.visible = current_scene != null and current_scene.scene_file_path != LAUNCHER_PATH


func _return_to_launcher() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null or current_scene.scene_file_path == LAUNCHER_PATH:
		return
	get_tree().change_scene_to_file(LAUNCHER_PATH)
