extends SceneTree


const SERVICE := preload(
	"res://world/presentation/ui/TownAudioDisplaySettingsService.gd"
)
const RESPONSIVE_VIEWPORT := preload(
	"res://ui/common/ResponsiveViewportPolicy.gd"
)
const INNER_OBSERVATION := preload(
	"res://ui/inner_observation/InnerObservationOverlay.gd"
)
const CONVERSATION_SCENE := preload(
	"res://ui/conversation_unified/UnifiedConversationScreen.tscn"
)
const RESIDENT_DETAIL := preload(
	"res://ui/resident_detail/ResidentDetailScreen.gd"
)
const WORLD_INTRO := preload("res://ui/world_intro/WorldIntroScreen.gd")
const RESIDENT_SELECTION := preload(
	"res://ui/resident_selection/ResidentSelectionScreen.gd"
)
const PROVIDER_SETTINGS := preload(
	"res://ui/provider_settings/ProviderSettingsScreen.gd"
)
const NEW_GAME_OVERWRITE := preload(
	"res://ui/new_game_overwrite/NewGameOverwriteScreen.gd"
)
const RESIDENT_MODEL_ASSIGNMENT := preload(
	"res://ui/resident_model_assignment/ResidentModelAssignmentScreen.gd"
)
const BULLETIN_BOARD := preload(
	"res://ui/bulletin_board/BulletinBoardPanel.gd"
)
const PLACE_FOCUS := preload(
	"res://ui/place_focus/runtime/PlaceFocusPanel.gd"
)
const HUD_TYPOGRAPHY := preload(
	"res://ui/town/hud/runtime/TownHudTypographyContract.gd"
)
const TOWN_HUD_SCENE := preload(
	"res://ui/town/hud/runtime/TownHudOverlay.tscn"
)
const SETTINGS_PATH := "user://town_windows_fullscreen_sync_test.json"


class FakeWindowsDisplayBackend:
	extends RefCounted

	var mode := DisplayServer.WINDOW_MODE_WINDOWED
	var server_name := "Windows"
	var size := Vector2i(1600, 900)
	var position := Vector2i(160, 90)
	var screen := 0
	var usable_rect := Rect2i(0, 0, 1920, 1040)

	func get_name() -> String:
		return server_name

	func window_get_mode() -> int:
		return mode

	func window_set_mode(value: int) -> void:
		mode = value

	func window_get_size() -> Vector2i:
		return size

	func window_set_size(value: Vector2i) -> void:
		size = value

	func window_get_position() -> Vector2i:
		return position

	func window_set_position(value: Vector2i) -> void:
		position = value

	func window_get_current_screen() -> int:
		return screen

	func screen_get_usable_rect(_screen: int) -> Rect2i:
		return usable_rect


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_settings_file()
	var backend := FakeWindowsDisplayBackend.new()
	var service := SERVICE.new()
	service.settings_path = SETTINGS_PATH
	var configured := service.call(
		"configure_display_backend_for_tests",
		backend,
	) as Dictionary
	_expect(bool(configured.get("ok", false)), "fake Windows display backend is accepted")
	root.add_child(service)
	await process_frame
	await process_frame
	_expect_window_constraints()
	_expect_global_shortcuts()
	_expect_responsive_viewport_matrix()
	_expect_formal_layout_matrix()
	await _expect_ultrawide_hud_layout()
	_expect_resident_detail_resize_stability()
	_expect_inner_observation_layout_matrix()
	await _expect_conversation_small_viewport()

	_expect(
		bool(service.call("toggle_fullscreen_from_global_shortcut")),
		"F11 request is accepted globally on Windows",
	)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		"F11 enters Godot borderless fullscreen instead of enlarging a window",
	)
	var fullscreen_vm := service.call("get_view_model") as Dictionary
	_expect_equal(
		(
			(fullscreen_vm.get("data", {}) as Dictionary).get(
				"display", {},
			) as Dictionary
		).get("windowModeId"),
		"borderless_fullscreen",
		"settings state follows the global fullscreen shortcut",
	)

	_expect(
		bool(service.call("toggle_fullscreen_from_global_shortcut")),
		"a second F11 request is accepted",
	)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"a second F11 returns to the saved window mode",
	)

	backend.mode = DisplayServer.WINDOW_MODE_MAXIMIZED
	backend.position = Vector2i.ZERO
	backend.size = backend.usable_rect.size
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		"maximize button, title double-click, and Win+Up promote to fullscreen",
	)

	_expect(
		bool(service.call("toggle_fullscreen_from_global_shortcut")),
		"fullscreen promoted from maximize can return to windowed mode",
	)
	backend.position = Vector2i(200, 100)
	backend.size = Vector2i(1500, 850)
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"a partial window is not promoted to fullscreen",
	)
	backend.usable_rect = Rect2i(0, 0, 1600, 900)
	backend.position = Vector2i.ZERO
	backend.size = Vector2i(1600, 900)
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"a deliberately managed screen-sized window remains windowed",
	)

	backend.usable_rect = Rect2i(0, 0, 1920, 1040)
	backend.position = Vector2i(-8, -8)
	backend.size = Vector2i(1936, 1096)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		"an external tool covering the current screen is promoted to fullscreen",
	)

	backend.mode = DisplayServer.WINDOW_MODE_WINDOWED
	backend.position = Vector2i(160, 90)
	backend.size = Vector2i(1600, 900)
	service.call("_process", 0.0)
	var exited_vm := service.call("get_view_model") as Dictionary
	_expect_equal(
		(
			(exited_vm.get("data", {}) as Dictionary).get(
				"display", {},
			) as Dictionary
		).get("windowModeId"),
		"windowed",
		"externally leaving fullscreen restores windowed settings state",
	)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"fullscreen exit grace prevents immediate accidental re-entry",
	)

	backend.screen = 1
	backend.usable_rect = Rect2i(1920, 0, 2560, 1400)
	backend.position = Vector2i(1920, 0)
	backend.size = Vector2i(2560, 1440)
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		"screen coverage detection uses the active monitor coordinates",
	)
	_expect(
		bool(service.call("toggle_fullscreen_from_global_shortcut")),
		"multi-monitor fullscreen can return to windowed mode",
	)
	backend.position = Vector2i.ZERO
	backend.size = Vector2i(2560, 1440)
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_WINDOWED,
		"screen-sized geometry on a different monitor is not promoted",
	)

	backend.mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	service.call("_process", 0.0)
	var exclusive_vm := service.call("get_view_model") as Dictionary
	_expect_equal(
		(
			(exclusive_vm.get("data", {}) as Dictionary).get(
				"display", {},
			) as Dictionary
		).get("windowModeId"),
		"exclusive_fullscreen",
		"externally requested exclusive fullscreen is adopted globally",
	)

	backend.server_name = "macOS"
	backend.mode = DisplayServer.WINDOW_MODE_MAXIMIZED
	service.set("_external_fullscreen_exit_grace_until_msec", 0)
	service.call("_process", 0.0)
	_expect_equal(
		backend.mode,
		DisplayServer.WINDOW_MODE_MAXIMIZED,
		"Windows normalization does not change other desktop platforms",
	)

	service.queue_free()
	await process_frame
	_remove_settings_file()
	var audio_controller := root.get_node_or_null("TownAudioController")
	if audio_controller != null and audio_controller.has_method("prepare_shutdown"):
		audio_controller.call("prepare_shutdown")
		await process_frame
		await create_timer(0.2).timeout
	_finish()


func _expect_window_constraints() -> void:
	_expect(
		not bool(ProjectSettings.get_setting(
			"display/window/size/resizable",
			true,
		)),
		"project disables mouse-driven window resizing",
	)
	_expect_equal(
		String(ProjectSettings.get_setting(
			"display/window/stretch/aspect",
			"",
		)),
		"expand",
		"ultrawide displays expand the logical town viewport",
	)


func _expect_global_shortcuts() -> void:
	var flow_host := root.get_node_or_null("GameFlowHost")
	_expect(flow_host != null, "global GameFlowHost exists")
	if flow_host == null:
		return
	var f11 := InputEventKey.new()
	f11.keycode = KEY_F11
	_expect(
		bool(flow_host.call("_is_fullscreen_toggle_shortcut", f11)),
		"F11 is recognized as a global fullscreen shortcut",
	)
	var alt_enter := InputEventKey.new()
	alt_enter.keycode = KEY_ENTER
	alt_enter.alt_pressed = true
	_expect(
		bool(flow_host.call("_is_fullscreen_toggle_shortcut", alt_enter)),
		"Alt+Enter is recognized as a global fullscreen shortcut",
	)
	var alt_keypad_enter := InputEventKey.new()
	alt_keypad_enter.keycode = KEY_KP_ENTER
	alt_keypad_enter.alt_pressed = true
	_expect(
		bool(
			flow_host.call(
				"_is_fullscreen_toggle_shortcut",
				alt_keypad_enter,
			)
		),
		"Alt+keypad Enter is recognized as a global fullscreen shortcut",
	)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	_expect(
		not bool(flow_host.call("_is_fullscreen_toggle_shortcut", enter)),
		"plain Enter remains gameplay input",
	)


func _expect_responsive_viewport_matrix() -> void:
	var cases: Array[Vector2i] = [
		Vector2i(960, 540),
		Vector2i(1024, 768),
		Vector2i(1280, 720),
		Vector2i(1280, 800),
		Vector2i(1280, 1024),
		Vector2i(1366, 768),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(1920, 1200),
		Vector2i(2160, 1440),
		Vector2i(2560, 1080),
		Vector2i(2560, 1440),
		Vector2i(2560, 1600),
		Vector2i(3440, 1440),
		Vector2i(3840, 1080),
		Vector2i(3840, 2160),
		Vector2i(5120, 1440),
	]
	var design := Vector2(RESPONSIVE_VIEWPORT.DESIGN_SIZE)
	for physical_size: Vector2i in cases:
		var metrics := RESPONSIVE_VIEWPORT.canvas_metrics(physical_size)
		_expect(
			bool(metrics.get("valid", false)),
			"responsive metrics accept %dx%d" % [
				physical_size.x,
				physical_size.y,
			],
		)
		var scale_factor := float(metrics.get("scale", 0.0))
		var logical_size := metrics.get("logicalSize", Vector2.ZERO) as Vector2
		var rendered_rect := metrics.get("renderedDesignRect", Rect2()) as Rect2
		_expect(scale_factor > 0.0, "responsive scale stays positive")
		_expect(
			logical_size.x + 0.01 >= design.x
			and logical_size.y + 0.01 >= design.y,
			"responsive logical canvas contains the 1920x1080 design",
		)
		_expect(
			rendered_rect.position.x >= -0.01
			and rendered_rect.position.y >= -0.01
			and rendered_rect.end.x <= physical_size.x + 0.01
			and rendered_rect.end.y <= physical_size.y + 0.01,
			"responsive design stays inside %dx%d" % [
				physical_size.x,
				physical_size.y,
			],
		)
		_expect(
			is_equal_approx(rendered_rect.size.x, float(physical_size.x))
			or is_equal_approx(rendered_rect.size.y, float(physical_size.y)),
			"responsive design fills one axis without cropping",
		)
	var invalid := RESPONSIVE_VIEWPORT.canvas_metrics(Vector2i.ZERO)
	_expect(
		not bool(invalid.get("valid", true)),
		"responsive metrics reject an empty viewport",
	)


func _expect_formal_layout_matrix() -> void:
	var world_intro := WORLD_INTRO.new()
	var resident_selection := RESIDENT_SELECTION.new()
	var provider_settings := PROVIDER_SETTINGS.new()
	var resident_detail := RESIDENT_DETAIL.new()
	var overwrite := NEW_GAME_OVERWRITE.new()
	var assignment := RESIDENT_MODEL_ASSIGNMENT.new()
	var bulletin := BULLETIN_BOARD.new()
	var place_focus := PLACE_FOCUS.new()
	var inner_observation := INNER_OBSERVATION.new()
	var physical_sizes: Array[Vector2i] = [
		Vector2i(1024, 768),
		Vector2i(1280, 1024),
		Vector2i(1280, 800),
		Vector2i(1920, 1080),
		Vector2i(2160, 1440),
		Vector2i(2560, 1080),
		Vector2i(3440, 1440),
		Vector2i(3840, 1080),
		Vector2i(5120, 1440),
	]
	for physical_size: Vector2i in physical_sizes:
		var metrics := RESPONSIVE_VIEWPORT.canvas_metrics(physical_size)
		var logical_size := metrics.get("logicalSize", Vector2.ZERO) as Vector2
		var label := "%dx%d" % [physical_size.x, physical_size.y]
		_expect_equal(
			int(world_intro.call("_layout_mode_for", logical_size)),
			0,
			"world intro keeps the 1920 formal layout at %s" % label,
		)
		_expect_equal(
			int(resident_selection.call("_layout_mode_for_size", logical_size)),
			0,
			"resident selection keeps the 1920 formal layout at %s" % label,
		)
		_expect(
			bool(provider_settings.call("_use_composite_desktop", logical_size)),
			"provider settings keeps its formal desktop layout at %s" % label,
		)
		_expect_equal(
			int(resident_detail.call("_select_layout_profile", logical_size)),
			0,
			"resident detail keeps its formal wide layout at %s" % label,
		)
		_expect_equal(
			int(overwrite.call("_select_layout_mode", logical_size)),
			0,
			"new-game confirmation keeps its formal wide layout at %s" % label,
		)
		_expect_equal(
			String(assignment.call("layout_profile_for_size", logical_size)),
			"wide",
			"resident model assignment keeps its formal layout at %s" % label,
		)
		var available := logical_size - Vector2(48.0, 48.0)
		_expect_equal(
			String(bulletin.call(
				"_layout_profile_for_available",
				available,
				available.x / maxf(1.0, available.y),
			)),
			"wide",
			"bulletin board keeps its formal wide layout at %s" % label,
		)
		_expect_equal(
			String(place_focus.call(
				"_profile_for_rect",
				Rect2(Vector2.ZERO, logical_size),
			)),
			"right_submenu_1920x1080",
			"place focus keeps its 1920 layout at %s" % label,
		)
		var inner_layout := inner_observation.call(
			"_layout_for_viewport",
			logical_size,
		) as Dictionary
		_expect_equal(
			String(inner_layout.get("profile", "")),
			"stable_1920x1080",
			"inner observation keeps its 1920 layout at %s" % label,
		)
		_expect_equal(
			String(HUD_TYPOGRAPHY.breakpoint_for(logical_size)),
			"desktop_wide",
			"town HUD keeps its formal desktop layout at %s" % label,
		)
	for screen: Node in [
		world_intro,
		resident_selection,
		provider_settings,
		resident_detail,
		overwrite,
		assignment,
		bulletin,
		place_focus,
		inner_observation,
	]:
		screen.free()


func _expect_ultrawide_hud_layout() -> void:
	for viewport_size: Vector2 in [
		Vector2(2560, 1080),
		Vector2(2580, 1080),
		Vector2(3840, 1080),
	]:
		var layout := HUD_TYPOGRAPHY.layout_for(viewport_size)
		var nav_rect := _target_rect(layout, "nav_residents")
		var camera_rect := _target_rect(layout, "camera_fit")
		var avatar_rect := _target_rect(layout, "avatar_toggle")
		var weather_rect := _target_rect(layout, "weatherChange")
		_expect(
			nav_rect.position.x <= 40.0,
			"ultrawide HUD keeps left navigation at the left edge",
		)
		_expect(
			camera_rect.end.x >= viewport_size.x - 44.0,
			"ultrawide HUD keeps camera controls at the right edge",
		)
		_expect(
			absf(avatar_rect.get_center().x - (
				viewport_size.x * 0.5
				+ (838.0 - 836.0) * (viewport_size.y / 941.0)
			)) <= 2.0,
			"ultrawide HUD keeps the avatar control centered",
		)
		_expect(
			avatar_rect.end.y >= viewport_size.y - 20.0,
			"ultrawide HUD keeps the avatar control at the bottom",
		)
		_expect(
			absf(weather_rect.get_center().x - (
				viewport_size.x * 0.5
				+ (1042.0 - 836.0) * (viewport_size.y / 941.0)
			)) <= 2.0,
			"ultrawide HUD keeps weather control in the centered status group",
		)
		_expect(
			nav_rect.size.x < 150.0 and camera_rect.size.x < 150.0,
			"ultrawide HUD controls keep their proportions instead of stretching",
		)

		var host := Control.new()
		host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		host.size = viewport_size
		root.add_child(host)
		var overlay := TOWN_HUD_SCENE.instantiate() as Control
		host.add_child(overlay)
		overlay.call("_apply_layout")
		var outer := overlay.find_child(
			"ConfirmedObserverV5StaticShell",
			true,
			false,
		) as NinePatchRect
		_expect(outer != null, "ultrawide HUD mounts its formal shell")
		if outer != null:
			_expect(
				(outer.size * outer.scale).distance_to(viewport_size) <= 1.1,
				"ultrawide HUD shell expands across the complete display",
			)
		host.queue_free()
		await process_frame


func _target_rect(layout: Dictionary, target_id: String) -> Rect2:
	for target_value: Variant in layout.get("targets", []) as Array:
		var target := target_value as Dictionary
		if String(target.get("id", "")) == target_id:
			return target.get("rect", Rect2()) as Rect2
	return Rect2()


func _expect_resident_detail_resize_stability() -> void:
	var screen := RESIDENT_DETAIL.new()
	var baseline_position := Vector2.ZERO
	var baseline_size := Vector2.ZERO
	var first := true
	for viewport_size: Vector2 in [
		Vector2(1920, 1080),
		Vector2(1920, 1110),
		Vector2(1920, 1140),
		Vector2(1920, 1170),
		Vector2(1920, 1200),
		Vector2(1760, 1100),
		Vector2(1600, 1000),
		Vector2(1600, 900),
	]:
		screen.call("_apply_wide_geometry", viewport_size)
		var scale_value := screen.get("_wide_layout_scale") as Vector2
		var origin := screen.get("_wide_layout_origin") as Vector2
		var name_rect := screen.get("_name_rect") as Rect2
		_expect(
			is_equal_approx(scale_value.x, scale_value.y),
			"resident detail keeps one uniform scale while resizing",
		)
		var normalized_position := (
			name_rect.position - origin
		) / scale_value.x
		var normalized_size := name_rect.size / scale_value.x
		if first:
			baseline_position = normalized_position
			baseline_size = normalized_size
			first = false
		else:
			_expect(
				normalized_position.distance_to(baseline_position) <= 1.5,
				"resident detail name position does not drift while resizing",
			)
			_expect(
				normalized_size.distance_to(baseline_size) <= 1.5,
				"resident detail name size does not distort while resizing",
			)
		var design_frame := RESPONSIVE_VIEWPORT.centered_design_rect(
			viewport_size,
			Vector2(RESPONSIVE_VIEWPORT.DESIGN_SIZE),
		)
		_expect(
			design_frame.get_center().distance_to(viewport_size * 0.5) <= 0.01,
			"resident detail design frame remains centered while resizing",
		)
	screen.free()


func _expect_inner_observation_layout_matrix() -> void:
	var overlay := INNER_OBSERVATION.new()
	for viewport_size: Vector2 in [
		Vector2(640, 360),
		Vector2(960, 540),
		Vector2(1024, 768),
		Vector2(1280, 720),
		Vector2(1920, 1080),
	]:
		var layout := overlay.call("_layout_for_viewport", viewport_size) as Dictionary
		var rects := layout.get("rects", {}) as Dictionary
		_expect(
			not rects.is_empty(),
			"inner observation supports %dx%d" % [
				int(viewport_size.x),
				int(viewport_size.y),
			],
		)
		for key: String in rects:
			var rect := rects[key] as Rect2
			_expect(
				rect.position.x >= -1.0
				and rect.position.y >= -1.0
				and rect.end.x <= viewport_size.x + 1.0
				and rect.end.y <= viewport_size.y + 1.0,
				"inner observation %s stays inside %dx%d" % [
					key,
					int(viewport_size.x),
					int(viewport_size.y),
				],
			)
	overlay.free()


func _expect_conversation_small_viewport() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 240)
	root.add_child(viewport)
	var screen := CONVERSATION_SCENE.instantiate()
	viewport.add_child(screen)
	await process_frame
	screen.call("_apply_layout")
	var stage := screen.get("_stage") as Control
	_expect(stage != null, "conversation stage is available for responsive layout")
	if stage != null:
		var rendered_rect := Rect2(stage.position, stage.size * stage.scale)
		_expect(
			rendered_rect.position.x >= -1.0
			and rendered_rect.position.y >= -1.0
			and rendered_rect.end.x <= viewport.size.x + 1.0
			and rendered_rect.end.y <= viewport.size.y + 1.0,
			"conversation stage keeps shrinking below its former 50 percent floor",
		)
	viewport.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s: expected=%s actual=%s" % [
		message,
		expected,
		actual,
	])


func _remove_settings_file() -> void:
	var absolute := ProjectSettings.globalize_path(SETTINGS_PATH)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(absolute)


func _finish() -> void:
	if _failures.is_empty():
		print("TOWN_WINDOWS_FULLSCREEN_SYNC_PASS")
		quit(0)
		return
	print("TOWN_WINDOWS_FULLSCREEN_SYNC_FAIL: %s" % str(_failures))
	quit(1)
