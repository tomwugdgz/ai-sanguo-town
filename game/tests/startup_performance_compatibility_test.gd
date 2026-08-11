extends SceneTree


const STARTUP_SCENE_PATH := "res://ui/startup/StartupScreen.tscn"
const STARTUP_BACKGROUND_PATH := (
	"res://assets/ui/startup/final/startup_town_background.png"
)
const ENVIRONMENT_RENDERER := preload(
	"res://world/presentation/environment/TownEnvironmentPresentation.gd"
)
const DEFERRED_UI_RESOURCE_PATHS := [
	"res://world/presentation/town_runtime/TownRuntime.tscn",
	"res://world/presentation/ui/TownUiRuntimeHost.gd",
	"res://ui/startup/StartupLoadGameScreen.tscn",
	"res://ui/world_intro/WorldIntroScreen.tscn",
	"res://ui/avatar_mode/runtime/AvatarModeHud.tscn",
	"res://ui/pause_menu/PauseMenuNavigationHost.tscn",
	"res://ui/provider_settings/ProviderSettingsScreen.tscn",
	"res://ui/settings/AudioDisplaySettingsScreen.tscn",
	"res://ui/resident_model_assignment/ResidentModelAssignmentScreen.tscn",
]

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_expect_equal(
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"gl_compatibility",
		"desktop defaults to the compatibility renderer",
	)
	_expect_equal(
		ProjectSettings.get_setting("rendering/gl_compatibility/driver.windows"),
		"opengl3_angle",
		"Windows compatibility rendering prefers ANGLE over Direct3D 11",
	)
	_expect_equal(
		ProjectSettings.get_setting("rendering/gl_compatibility/fallback_to_native"),
		true,
		"Windows compatibility rendering keeps native OpenGL fallback",
	)

	var flow_host := root.get_node_or_null("GameFlowHost")
	_expect(flow_host != null, "game flow host autoload exists")
	if flow_host != null:
		_expect_equal(
			flow_host.get("_town_entry_loading_overlay"),
			null,
			"hidden Town-entry artwork is not decoded on the title screen",
		)
		_expect_equal(
			flow_host.get("_town_runtime_scene"),
			null,
			"formal Town runtime stays unloaded on the title screen",
		)
	for path: String in DEFERRED_UI_RESOURCE_PATHS:
		_expect(
			not ResourceLoader.has_cached(path),
			"title screen keeps deferred UI resource unloaded: %s" % path,
		)

	var audio := root.get_node_or_null("TownAudioController")
	_expect(audio != null, "audio controller autoload exists")
	if audio != null:
		var audio_snapshot := audio.call("debug_snapshot") as Dictionary
		_expect_equal(
			audio_snapshot.get("loadedMusicPoolIds"),
			PackedStringArray(["cover"]),
			"title screen loads only the daytime title music pool",
		)
		_expect_equal(
			audio_snapshot.get("musicPoolSize"),
			4,
			"title screen cycles all four approved daytime tracks",
		)
		_expect_equal(
			audio_snapshot.get("loadedBaseAmbienceIds"),
			PackedStringArray(),
			"title screen does not synthesize Town ambience",
		)

	var packed := load(STARTUP_SCENE_PATH) as PackedScene
	var startup := packed.instantiate() as Control if packed != null else null
	_expect(startup != null, "startup screen can be instantiated")
	if startup != null:
		root.add_child(startup)
		await process_frame
		var preview := startup.get_node_or_null("StartupTownPreview")
		var map_sprite := (
			preview.get_node_or_null("TownMap") as Sprite2D
			if preview != null
			else null
		)
		_expect(map_sprite != null, "startup screen owns one lightweight map image")
		if map_sprite != null and map_sprite.texture != null:
			_expect_equal(
				map_sprite.texture.resource_path,
				STARTUP_BACKGROUND_PATH,
				"startup screen uses the dedicated background asset",
			)
			_expect_equal(
				map_sprite.texture.get_size(),
				Vector2(1920.0, 1080.0),
				"startup background stays within the reference viewport",
			)
		_expect_equal(
			startup.find_child("FormalRuntimeLayers", true, false),
			null,
			"startup screen does not instantiate formal map runtime layers",
		)
		_expect_equal(
			startup.find_child("AmbientResidentLayer", true, false),
			null,
			"startup screen does not create a dormant resident layer",
		)
		var weather := startup.get_node_or_null("WeatherOverlay") as ColorRect
		_expect(
			weather != null and not weather.visible,
			"clear title weather skips the full-screen weather pass",
		)
		startup.queue_free()

	_expect_equal(
		ENVIRONMENT_RENDERER.snow_particle_budget_for_rendering_method(
			"gl_compatibility",
		),
		1400,
		"compatibility rendering uses the reduced snowfall budget",
	)
	_expect_equal(
		ENVIRONMENT_RENDERER.snow_particle_budget_for_rendering_method(
			"forward_plus",
		),
		2600,
		"modern rendering keeps the authored snowfall budget",
	)

	if audio != null:
		audio.call("prepare_shutdown")
	await process_frame
	await create_timer(0.2).timeout
	_finish()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("STARTUP_PERFORMANCE_COMPATIBILITY_PASS checks=%d" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
