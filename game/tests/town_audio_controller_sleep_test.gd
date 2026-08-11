extends SceneTree


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var audio := root.get_node_or_null("TownAudioController")
	_expect(audio != null, "formal audio controller autoload exists")
	if audio == null:
		_finish()
		return

	var cover := audio.call("debug_snapshot") as Dictionary
	_expect_equal(cover.get("musicId"), "cover", "startup uses its own cover music")
	_expect_equal(cover.get("musicPoolSize"), 4, "startup cycles the four approved daytime tracks")
	_expect_equal(cover.get("frontendMode"), true, "startup begins in cover mode")
	_expect_equal(
		cover.get("loadedMusicPoolIds"),
		PackedStringArray(["cover"]),
		"startup does not decode Town weather and time music pools",
	)
	_expect_equal(
		cover.get("loadedBaseAmbienceIds"),
		PackedStringArray(),
		"startup does not synthesize Town ambience beds",
	)
	_expect_equal(cover.get("rainStreamLoaded"), false, "startup leaves rain audio unloaded")
	_expect_equal(
		cover.get("sleepNoiseStreamLoaded"),
		false,
		"startup leaves sleep noise unloaded",
	)
	_expect_equal(
		cover.get("thunderStreamLoaded"),
		false,
		"startup leaves thunder audio unloaded",
	)
	var expected_music_paths := PackedStringArray([
		"res://assets/audio/music/music_town_daylife_gathering.wav",
		"res://assets/audio/music/music_town_daylife_market.wav",
		"res://assets/audio/music/music_town_daylife_corner_opening.wav",
		"res://assets/audio/music/music_town_daylife_window_afternoon.wav",
		"res://assets/audio/music/music_town_evening_workshop_lights.wav",
		"res://assets/audio/music/music_town_evening_lane_breeze.wav",
		"res://assets/audio/music/music_town_evening_dusk_town.wav",
		"res://assets/audio/music/music_town_rain_window_town_01.wav",
		"res://assets/audio/music/music_town_rain_window_town_02.wav",
		"res://assets/audio/music/music_town_thunderstorm_after_rain_01.wav",
		"res://assets/audio/music/music_town_thunderstorm_after_rain_02.wav",
		"res://assets/audio/music/music_town_sleep_belltower_01.wav",
		"res://assets/audio/music/music_town_sleep_belltower_02.wav",
	])
	for music_path: String in expected_music_paths:
		_expect(
			FileAccess.file_exists(music_path),
			"collaboration music is bundled: %s" % music_path,
		)
	var bundled_music_paths := PackedStringArray()
	for file_name: String in DirAccess.get_files_at("res://assets/audio/music"):
		if file_name.get_extension().to_lower() in ["wav", "ogg", "mp3"]:
			bundled_music_paths.append("res://assets/audio/music/%s" % file_name)
	expected_music_paths.sort()
	bundled_music_paths.sort()
	_expect_equal(
		bundled_music_paths,
		expected_music_paths,
		"music directory contains only the approved formal tracks",
	)
	_expect_equal(
		cover.get("baseAmbienceId"),
		"",
		"cover mode does not leak the Town environment bed",
	)
	var first_cover_variant := int(cover.get("musicVariantIndex", -1))
	audio.call("_switch_music", "cover", true)
	var next_cover := audio.call("debug_snapshot") as Dictionary
	_expect(
		int(next_cover.get("musicVariantIndex", -1)) != first_cover_variant,
		"title daytime playlist does not immediately repeat the same track",
	)

	audio.call(
		"sync_environment",
		{"day": 1, "clock": "18:30", "period": "傍晚"},
		"晴天",
	)
	var evening := audio.call("debug_snapshot") as Dictionary
	_expect_equal(evening.get("musicId"), "night", "evening keeps the selected work music")
	_expect_equal(evening.get("musicPoolSize"), 3, "evening uses the three-track work pool")
	_expect_equal(evening.get("frontendMode"), false, "Town time exits cover mode")
	_expect_equal(evening.get("sleepTime"), false, "evening is not sleep time")
	_expect_equal(evening.get("sleepNoiseId"), "", "evening has no sleep white noise")

	audio.call(
		"sync_environment",
		{"day": 1, "clock": "22:59", "period": "夜里"},
		"晴天",
	)
	var return_home := audio.call("debug_snapshot") as Dictionary
	_expect_equal(
		return_home.get("musicId"),
		"night",
		"the return-home hour still uses evening work music",
	)
	_expect_equal(
		return_home.get("sleepNoiseId"),
		"",
		"white noise waits until the formal sleep boundary",
	)

	audio.call(
		"sync_environment",
		{"day": 1, "clock": "23:00", "period": "夜里"},
		"晴天",
	)
	var sleep := audio.call("debug_snapshot") as Dictionary
	_expect_equal(sleep.get("musicId"), "sleep", "23:00 switches to the sleep music")
	_expect_equal(sleep.get("musicPoolSize"), 2, "sleep uses the two-track belltower pool")
	_expect_equal(sleep.get("sleepTime"), true, "23:00 enters sleep time")
	_expect_equal(
		sleep.get("sleepNoiseId"),
		"sleep_white_noise",
		"sleep time starts the independent white-noise ambience",
	)
	_expect_equal(
		sleep.get("baseAmbienceId"),
		"night",
		"sleep time keeps the quiet night environment bed",
	)

	audio.call(
		"sync_environment",
		{"day": 2, "clock": "05:30", "period": "清晨"},
		"晴天",
	)
	var early_sleep := audio.call("debug_snapshot") as Dictionary
	_expect_equal(
		early_sleep.get("musicId"),
		"sleep",
		"early morning remains quiet while residents are still resting",
	)
	_expect_equal(
		early_sleep.get("baseAmbienceId"),
		"night",
		"early sleep does not introduce daytime birds",
	)

	audio.call(
		"sync_environment",
		{"day": 2, "clock": "05:30", "period": "清晨"},
		"中雨",
	)
	var rainy_sleep := audio.call("debug_snapshot") as Dictionary
	_expect_equal(rainy_sleep.get("musicId"), "sleep", "rain does not replace sleep music")
	_expect_equal(rainy_sleep.get("ambienceId"), "rain", "medium rain uses rain ambience")
	_expect_equal(
		rainy_sleep.get("sleepNoiseId"),
		"",
		"recorded rain replaces white noise instead of stacking with it",
	)

	audio.call(
		"sync_environment",
		{"day": 2, "clock": "07:00", "period": "清晨"},
		"晴天",
	)
	var awake := audio.call("debug_snapshot") as Dictionary
	_expect_equal(awake.get("musicId"), "day", "07:00 returns to daytime music")
	_expect_equal(awake.get("musicPoolSize"), 4, "Town daytime reuses the title playlist")
	_expect_equal(awake.get("sleepTime"), false, "07:00 leaves sleep time")
	_expect_equal(awake.get("sleepNoiseId"), "", "07:00 fades out white noise")

	audio.call(
		"sync_environment",
		{"day": 2, "clock": "12:00", "period": "中午"},
		"中雨",
	)
	var rainy_day := audio.call("debug_snapshot") as Dictionary
	_expect_equal(rainy_day.get("musicId"), "rain", "rain has its own background music")
	_expect_equal(rainy_day.get("musicPoolSize"), 2, "ordinary rain uses the two-track rain pool")
	_expect_equal(rainy_day.get("ambienceId"), "rain", "rain ambience remains independent")

	audio.call(
		"sync_environment",
		{"day": 2, "clock": "12:00", "period": "中午"},
		"雷暴",
	)
	var thunderstorm := audio.call("debug_snapshot") as Dictionary
	_expect_equal(
		thunderstorm.get("musicId"),
		"thunderstorm",
		"thunderstorm uses its quieter dedicated music route",
	)
	_expect_equal(
		thunderstorm.get("musicPoolSize"),
		2,
		"thunderstorm uses the two-track after-rain pool",
	)
	_expect_equal(
		thunderstorm.get("ambienceId"),
		"rain",
		"thunderstorm keeps the independent rain ambience",
	)

	audio.call("play_major_event_music", 0.05)
	var event_music := audio.call("debug_snapshot") as Dictionary
	_expect_equal(
		event_music.get("musicId"),
		"thunderstorm",
		"major announcements keep the current weather music",
	)
	_expect_equal(
		event_music.get("musicOverrideId"),
		"",
		"major announcements do not create a dedicated music override",
	)
	audio.call(
		"sync_environment",
		{"day": 2, "clock": "19:30", "period": "傍晚"},
		"晴天",
	)
	var event_during_transition := audio.call("debug_snapshot") as Dictionary
	_expect_equal(
		event_during_transition.get("musicId"),
		"night",
		"time changes switch the normal scene music during an announcement",
	)
	await create_timer(0.08).timeout
	var event_finished := audio.call("debug_snapshot") as Dictionary
	_expect_equal(
		event_finished.get("musicId"),
		"night",
		"announcement keeps the latest formal period music",
	)
	_expect_equal(
		event_finished.get("musicOverrideId"),
		"",
		"major event override clears after its duration",
	)

	var flow_host := root.get_node_or_null("GameFlowHost")
	_expect(flow_host != null, "formal GameFlowHost autoload exists")
	if flow_host != null:
		flow_host.call("_play_cover_music")
	else:
		audio.call("play_cover_music")
	var returned_cover := audio.call("debug_snapshot") as Dictionary
	_expect_equal(returned_cover.get("musicId"), "cover", "returning to title restores cover music")
	_expect_equal(returned_cover.get("frontendMode"), true, "returning to title restores cover mode")
	_expect_equal(
		returned_cover.get("ambienceId"),
		"",
		"returning to title stops rain ambience",
	)

	audio.call("prepare_shutdown")
	await process_frame
	await create_timer(0.2).timeout
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("TOWN_AUDIO_CONTROLLER_SLEEP_PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
