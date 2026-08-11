extends Node


const SOUND_LIBRARY := preload("res://audio/TownProceduralSoundLibrary.gd")
const SETTINGS_PATH := "user://audio_settings.cfg"
const SETTINGS_SECTION := "audio"
const DAYLIFE_MUSIC_PATHS := [
	"res://assets/audio/music/music_town_daylife_gathering.wav",
	"res://assets/audio/music/music_town_daylife_market.wav",
	"res://assets/audio/music/music_town_daylife_corner_opening.wav",
	"res://assets/audio/music/music_town_daylife_window_afternoon.wav",
]
const EVENING_MUSIC_PATHS := [
	"res://assets/audio/music/music_town_evening_workshop_lights.wav",
	"res://assets/audio/music/music_town_evening_lane_breeze.wav",
	"res://assets/audio/music/music_town_evening_dusk_town.wav",
]
const RAIN_MUSIC_PATHS := [
	"res://assets/audio/music/music_town_rain_window_town_01.wav",
	"res://assets/audio/music/music_town_rain_window_town_02.wav",
]
const THUNDERSTORM_MUSIC_PATHS := [
	"res://assets/audio/music/music_town_thunderstorm_after_rain_01.wav",
	"res://assets/audio/music/music_town_thunderstorm_after_rain_02.wav",
]
const SLEEP_MUSIC_PATHS := [
	"res://assets/audio/music/music_town_sleep_belltower_01.wav",
	"res://assets/audio/music/music_town_sleep_belltower_02.wav",
]
const RAIN_AMBIENCE_PATH := "res://assets/audio/ambience/amb_town_rain_loop.ogg"
const SLEEP_NOISE_PATH := (
	"res://assets/audio/ambience/amb_sleep_soft_white_noise_loop.wav"
)
const THUNDER_SFX_PATH := "res://assets/audio/sfx/weather/sfx_thunder_generated.ogg"
const RECORDED_CUE_PATHS := {
	"sfx_avatar_descend": "res://assets/audio/sfx/avatar/sfx_avatar_descend.ogg",
	"footstep_outdoor_1": "res://assets/audio/sfx/footsteps/sfx_footstep_outdoor_01.ogg",
	"footstep_outdoor_2": "res://assets/audio/sfx/footsteps/sfx_footstep_outdoor_02.ogg",
	"footstep_outdoor_3": "res://assets/audio/sfx/footsteps/sfx_footstep_outdoor_03.ogg",
	"footstep_indoor_1": "res://assets/audio/sfx/footsteps/sfx_footstep_indoor_01.ogg",
	"footstep_indoor_2": "res://assets/audio/sfx/footsteps/sfx_footstep_indoor_02.ogg",
	"footstep_indoor_3": "res://assets/audio/sfx/footsteps/sfx_footstep_indoor_03.ogg",
	"footstep_wet_1": "res://assets/audio/sfx/footsteps/sfx_footstep_wet_01.ogg",
	"footstep_wet_2": "res://assets/audio/sfx/footsteps/sfx_footstep_wet_02.ogg",
	"footstep_wet_3": "res://assets/audio/sfx/footsteps/sfx_footstep_wet_03.ogg",
}
const CROSSFADE_SECONDS := 3.0
const SLEEP_CROSSFADE_SECONDS := 8.0
const INITIAL_FADE_SECONDS := 1.2
const AMBIENCE_FADE_SECONDS := 2.0
const SLEEP_NOISE_FADE_SECONDS := 4.0
const COVER_MUSIC_VOLUME_DB := -2.0
const EVENING_MUSIC_VOLUME_DB := -1.0
const RAIN_MUSIC_VOLUME_DB := -1.5
const THUNDERSTORM_MUSIC_VOLUME_DB := -2.5
const SLEEP_MUSIC_VOLUME_DB := -4.0
const SLEEP_NOISE_VOLUME_DB := -8.0
const SILENCE_DB := -60.0
const UI_SAMPLE_RATE := 48000
const UI_POOL_SIZE := 6
const SFX_POOL_SIZE := 8
const FRONTEND_CUE_IDS := [
	"ui_tap",
	"ui_select",
	"ui_deselect",
	"ui_back",
	"ui_page",
	"ui_tab",
	"ui_toggle_on",
	"ui_toggle_off",
	"ui_slider",
	"ui_confirm",
	"ui_success",
	"ui_warning",
	"ui_error",
	"ui_panel_open",
	"connection_check",
]
const TAP_COOLDOWN_MSEC := 45
const SLIDER_COOLDOWN_MSEC := 35

const BUS_DEFAULTS := {
	"Master": 80,
	"Music": 55,
	"Ambience": 45,
	"SFX": 70,
	"UI": 60,
}
const BUS_ALIASES := {
	"master": "Master",
	"music": "Music",
	"ambience": "Ambience",
	"sfx": "SFX",
	"ui": "UI",
}
const NIGHT_PERIODS := ["傍晚", "夜里"]
const RAIN_WEATHER := ["小雨", "中雨", "大雨", "雷暴"]
const RAIN_VOLUME_DB := {
	"小雨": -5.0,
	"中雨": -3.0,
	"大雨": -1.0,
	"雷暴": -3.0,
}
const SLEEP_START_MINUTE := 23 * 60
const SLEEP_END_MINUTE := 7 * 60
const THUNDER_FIRST_DELAY_RANGE := Vector2(0.25, 0.65)
const THUNDER_REPEAT_DELAY_RANGE := Vector2(7.0, 13.0)
const CONFIRM_LABEL_PARTS := [
	"确认", "开始", "继续", "保存", "发送", "发布", "进入", "应用", "完成", "重试",
]
const BACK_LABEL_PARTS := [
	"返回", "关闭", "取消", "放弃", "稍后", "退出预览", "back", "close", "cancel",
]
const WARNING_LABEL_PARTS := [
	"删除", "清空", "覆盖", "退出游戏", "回到开始", "断开", "移除", "delete", "quit",
]
const PAGE_LABEL_PARTS := [
	"上一", "下一", "更早", "较新", "翻页", "previous", "next", "older", "newer",
]
const SELECT_LABEL_PARTS := [
	"选择", "查看", "详情", "居民", "地点", "角色", "预设", "方向", "select", "view",
]
const TAB_LABEL_PARTS := [
	"分类", "筛选", "全部", "衣服", "发型", "帽子", "category", "filter", "tab",
]

var _music_stream_pools: Dictionary = {}
var _music_players: Array[AudioStreamPlayer] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _sfx_players: Array[AudioStreamPlayer] = []
var _cue_streams: Dictionary = {}
var _base_ambience_streams: Dictionary = {}
var _ambience_player: AudioStreamPlayer
var _base_ambience_player: AudioStreamPlayer
var _sleep_noise_player: AudioStreamPlayer
var _thunder_player: AudioStreamPlayer
var _active_music_index := -1
var _current_music_id := ""
var _current_music_pool_key := ""
var _current_music_variant_index := -1
var _current_ambience_id := ""
var _current_base_ambience_id := ""
var _current_sleep_noise_id := ""
var _current_weather := ""
var _current_period := "上午"
var _is_sleep_time := false
var _is_indoor := false
var _frontend_mode := true
var _music_override_id := ""
var _music_override_token := 0
var _fade_tween: Tween
var _ambience_tween: Tween
var _base_ambience_tween: Tween
var _sleep_noise_tween: Tween
var _ui_pool_cursor := 0
var _sfx_pool_cursor := 0
var _last_tap_msec := -TAP_COOLDOWN_MSEC
var _wired_button_count := 0
var _wired_slider_count := 0
var _slider_steps: Dictionary = {}
var _last_slider_msec := -SLIDER_COOLDOWN_MSEC
var _thunder_wait_seconds := -1.0
var _application_paused := false
var _rng := RandomNumberGenerator.new()
var _shutdown_prepared := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	_load_audio_settings()
	_build_sound_library()
	_build_music_players()
	_build_environment_players()
	_build_ui_players()
	_build_sfx_players()
	_rng.randomize()
	var tree := get_tree()
	if not tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.connect(_on_tree_node_added)
	call_deferred("_wire_existing_buttons")
	call_deferred("play_cover_music")


func _exit_tree() -> void:
	prepare_shutdown()


func prepare_shutdown() -> void:
	if _shutdown_prepared:
		return
	_shutdown_prepared = true
	set_process(false)
	# 脱树或从未入树时 get_tree() 会报引擎错误，先确认仍在树内。
	var tree: SceneTree = null
	if is_inside_tree():
		tree = get_tree()
	if tree != null and tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.disconnect(_on_tree_node_added)
	_slider_steps.clear()
	# Stop playback before the audio server is dismantled. Releasing only the
	# player Nodes at process exit can leave decoder/playback RefCounted objects
	# alive long enough for Godot to report ObjectDB leaks.
	for tween: Tween in [
		_fade_tween,
		_ambience_tween,
		_base_ambience_tween,
		_sleep_noise_tween,
	]:
		if tween != null and tween.is_valid():
			tween.kill()
	_fade_tween = null
	_ambience_tween = null
	_base_ambience_tween = null
	_sleep_noise_tween = null
	for player: AudioStreamPlayer in _music_players:
		_release_player(player)
	for player: AudioStreamPlayer in _ui_players:
		_release_player(player)
	for player: AudioStreamPlayer in _sfx_players:
		_release_player(player)
	_release_player(_ambience_player)
	_release_player(_base_ambience_player)
	_release_player(_sleep_noise_player)
	_release_player(_thunder_player)
	_music_players.clear()
	_ui_players.clear()
	_sfx_players.clear()
	_ambience_player = null
	_base_ambience_player = null
	_sleep_noise_player = null
	_thunder_player = null
	_music_stream_pools.clear()
	_cue_streams.clear()
	_base_ambience_streams.clear()

func _release_player(player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player):
		return
	player.stop()
	player.stream = null
	player.free()


func _process(delta: float) -> void:
	if _application_paused or _current_weather != "雷暴":
		return
	_thunder_wait_seconds -= maxf(delta, 0.0)
	if _thunder_wait_seconds <= 0.0:
		play_thunder()
		_thunder_wait_seconds = _rng.randf_range(
			THUNDER_REPEAT_DELAY_RANGE.x,
			THUNDER_REPEAT_DELAY_RANGE.y,
		)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_runtime_audio_paused(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_runtime_audio_paused(false)


func sync_environment(time: Dictionary, weather: String) -> void:
	var period := String(time.get("period", "上午"))
	var sleep_time := _time_is_sleep_time(time, period)
	var weather_changed := not _current_weather.is_empty() and weather != _current_weather
	_frontend_mode = false
	_current_period = period
	_is_sleep_time = sleep_time
	if _music_override_id.is_empty():
		_switch_music(_environment_music_id(weather))
	_sync_base_ambience()
	_sync_rain_ambience(weather)
	_sync_sleep_noise(weather)
	_sync_thunder_weather(weather)
	_current_weather = weather
	if weather_changed:
		play_cue("weather_change")


func play_cover_music() -> void:
	if _shutdown_prepared:
		return
	_frontend_mode = true
	_music_override_token += 1
	_music_override_id = ""
	_stop_environment_audio()
	_switch_music("cover")


func play_major_event_music(
	_duration_seconds: float = 0.0,
) -> void:
	if _frontend_mode:
		return
	_music_override_token += 1
	_music_override_id = ""
	# 公告只播放提示音，背景音乐继续跟随当前场景，避免临时事件曲成为正式依赖。
	_switch_music(_environment_music_id())


func set_indoor(indoor: bool) -> void:
	if _is_indoor == indoor:
		return
	_is_indoor = indoor
	_sync_base_ambience()


func play_cue(cue_id: String, volume_db: float = 0.0) -> void:
	var stream := _cue_streams.get(cue_id) as AudioStream
	if stream == null:
		stream = _load_cue_stream(cue_id)
		if stream != null:
			_cue_streams[cue_id] = stream
	if stream == null:
		return
	var pitch_range := _cue_pitch_range(cue_id)
	var cue_volume := volume_db + _cue_volume_db(cue_id)
	if cue_id.begins_with("ui_"):
		_play_pooled_stream(
			_ui_players,
			stream,
			pitch_range.x,
			pitch_range.y,
			cue_volume,
			true,
		)
	else:
		_play_pooled_stream(
			_sfx_players,
			stream,
			pitch_range.x,
			pitch_range.y,
			cue_volume,
			false,
		)


func play_footstep() -> void:
	var variant := _rng.randi_range(1, 3)
	if _is_indoor:
		play_cue("footstep_indoor_%d" % variant)
	elif RAIN_WEATHER.has(_current_weather):
		play_cue("footstep_wet_%d" % variant)
	else:
		play_cue("footstep_outdoor_%d" % variant)


func play_thunder() -> void:
	if _thunder_player == null or _thunder_player.stream == null:
		return
	if _thunder_player.playing:
		_thunder_player.stop()
	_thunder_player.pitch_scale = _rng.randf_range(0.93, 1.05)
	_thunder_player.play()


func play_ui_tap() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tap_msec < TAP_COOLDOWN_MSEC:
		return
	_last_tap_msec = now
	play_cue("ui_tap")


func play_ui_confirm() -> void:
	play_cue("ui_confirm")


func play_ui_error() -> void:
	play_cue("ui_error")


func save_settings() -> bool:
	var config := ConfigFile.new()
	for setting_id: String in BUS_ALIASES:
		var bus_name := String(BUS_ALIASES[setting_id])
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			continue
		config.set_value(
			SETTINGS_SECTION,
			"%s_percent" % setting_id,
			_db_to_percent(AudioServer.get_bus_volume_db(bus_index)),
		)
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		config.set_value(
			SETTINGS_SECTION,
			"muted",
			AudioServer.is_bus_mute(master_index),
		)
	return config.save(SETTINGS_PATH) == OK


func debug_snapshot() -> Dictionary:
	var players: Array[Dictionary] = []
	for player: AudioStreamPlayer in _music_players:
		players.append({
			"playing": player.playing,
			"paused": player.stream_paused,
			"position": player.get_playback_position(),
			"volumeDb": player.volume_db,
		})
	var loaded_music_pool_ids := PackedStringArray()
	for pool_id: String in _music_stream_pools:
		loaded_music_pool_ids.append(pool_id)
	loaded_music_pool_ids.sort()
	var loaded_base_ambience_ids := PackedStringArray()
	for ambience_id: String in _base_ambience_streams:
		loaded_base_ambience_ids.append(ambience_id)
	loaded_base_ambience_ids.sort()
	return {
		"musicId": _current_music_id,
		"musicPoolKey": _current_music_pool_key,
		"musicVariantIndex": _current_music_variant_index,
		"musicPoolSize": _music_pool_size(_current_music_id),
		"musicOverrideId": _music_override_id,
		"frontendMode": _frontend_mode,
		"ambienceId": _current_ambience_id,
		"baseAmbienceId": _current_base_ambience_id,
		"sleepNoiseId": _current_sleep_noise_id,
		"sleepTime": _is_sleep_time,
		"indoor": _is_indoor,
		"weather": _current_weather,
		"rainPlaying": _ambience_player.playing if _ambience_player != null else false,
		"sleepNoisePlaying": (
			_sleep_noise_player.playing
			if _sleep_noise_player != null
			else false
		),
		"thunderPlaying": _thunder_player.playing if _thunder_player != null else false,
		"activePlayer": _active_music_index,
		"players": players,
		"loadedMusicPoolIds": loaded_music_pool_ids,
		"loadedBaseAmbienceIds": loaded_base_ambience_ids,
		"rainStreamLoaded": (
			_ambience_player != null and _ambience_player.stream != null
		),
		"sleepNoiseStreamLoaded": (
			_sleep_noise_player != null and _sleep_noise_player.stream != null
		),
		"thunderStreamLoaded": (
			_thunder_player != null and _thunder_player.stream != null
		),
		"wiredButtons": _wired_button_count,
		"wiredSliders": _wired_slider_count,
		"cueCount": _cue_streams.size(),
	}


func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index("Master") < 0:
		return
	for bus_name: String in BUS_DEFAULTS:
		if bus_name == "Master" or AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var bus_index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_index, bus_name)
		AudioServer.set_bus_send(bus_index, "Master")


func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	var loaded := config.load(SETTINGS_PATH) == OK
	for setting_id: String in BUS_ALIASES:
		var bus_name := String(BUS_ALIASES[setting_id])
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			continue
		var default_percent := int(BUS_DEFAULTS.get(bus_name, 100))
		var percent := int(config.get_value(
			SETTINGS_SECTION,
			"%s_percent" % setting_id,
			default_percent,
		)) if loaded else default_percent
		AudioServer.set_bus_volume_db(bus_index, _percent_to_db(clampi(percent, 0, 100)))
	var master_index := AudioServer.get_bus_index("Master")
	if master_index >= 0:
		AudioServer.set_bus_mute(
			master_index,
			bool(config.get_value(SETTINGS_SECTION, "muted", false)) if loaded else false,
		)
	if not loaded:
		save_settings()


func _build_music_players() -> void:
	# The title loads only the daytime playlist. Night, rain, thunderstorm and
	# sleep tracks are still deferred until their routes are entered.
	_music_stream_pools.clear()
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "MusicPlayer%d" % (index + 1)
		player.bus = "Music"
		player.volume_db = SILENCE_DB
		player.finished.connect(_on_music_player_finished.bind(index))
		add_child(player)
		_music_players.append(player)


func _build_environment_players() -> void:
	_base_ambience_player = AudioStreamPlayer.new()
	_base_ambience_player.name = "BaseAmbiencePlayer"
	_base_ambience_player.bus = "Ambience"
	_base_ambience_player.volume_db = SILENCE_DB
	add_child(_base_ambience_player)

	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "RainAmbiencePlayer"
	_ambience_player.bus = "Ambience"
	_ambience_player.volume_db = SILENCE_DB
	add_child(_ambience_player)

	_sleep_noise_player = AudioStreamPlayer.new()
	_sleep_noise_player.name = "SleepWhiteNoisePlayer"
	_sleep_noise_player.bus = "Ambience"
	_sleep_noise_player.volume_db = SILENCE_DB
	add_child(_sleep_noise_player)

	_thunder_player = AudioStreamPlayer.new()
	_thunder_player.name = "ThunderSfxPlayer"
	_thunder_player.bus = "SFX"
	_thunder_player.volume_db = -2.0
	add_child(_thunder_player)


func _ensure_music_pool_loaded(music_id: String) -> void:
	if _music_stream_pools.has(music_id):
		return
	var streams: Array[AudioStream] = []
	if music_id == "cover":
		streams = _load_music_pool(DAYLIFE_MUSIC_PATHS)
	elif music_id == "day" and _music_stream_pools.has("cover"):
		# 主菜单与晴天白天共用同一组流，进入小镇时不重复载入四首音乐。
		streams = _music_stream_pools.get("cover", []) as Array[AudioStream]
	else:
		streams = _load_music_pool(
			_music_paths(music_id),
			music_id == "sleep",
		)
	_music_stream_pools[music_id] = streams


func _music_paths(music_id: String) -> Array:
	match music_id:
		"day":
			return DAYLIFE_MUSIC_PATHS
		"night":
			return EVENING_MUSIC_PATHS
		"rain":
			return RAIN_MUSIC_PATHS
		"thunderstorm":
			return THUNDERSTORM_MUSIC_PATHS
		"sleep":
			return SLEEP_MUSIC_PATHS
		_:
			return []


func _load_looping_music(path: String) -> AudioStream:
	return _load_looping_stream(path)


func _load_music_stream(path: String, loop: bool = false) -> AudioStream:
	var stream := _load_audio_stream(path)
	if loop:
		return _set_stream_loop(stream)
	return stream


func _load_music_pool(paths: Array, loop: bool = false) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for path: String in paths:
		var stream: AudioStream = _load_music_stream(path, loop)
		if stream != null:
			streams.append(stream)
	return streams


func _set_stream_loop(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
	return stream


func _load_looping_stream(path: String) -> AudioStream:
	var stream := _load_audio_stream(path)
	return _set_stream_loop(stream)


func _load_audio_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("声音资源不存在：%s" % path)
		return null
	var source := load(path) as AudioStream
	if source == null:
		push_warning("声音资源无法加载：%s" % path)
		return null
	return source.duplicate(true) as AudioStream


func _load_cue_stream(cue_id: String) -> AudioStream:
	if RECORDED_CUE_PATHS.has(cue_id):
		return _load_audio_stream(String(RECORDED_CUE_PATHS[cue_id]))
	return SOUND_LIBRARY.build_cue(cue_id, UI_SAMPLE_RATE)


func _sync_rain_ambience(weather: String) -> void:
	if _ambience_player == null:
		return
	if RAIN_WEATHER.has(weather) and _ambience_player.stream == null:
		_ambience_player.stream = _load_looping_stream(RAIN_AMBIENCE_PATH)
	if _ambience_player.stream == null:
		return
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	if RAIN_WEATHER.has(weather):
		_current_ambience_id = "rain"
		if not _ambience_player.playing:
			_ambience_player.volume_db = SILENCE_DB
			_ambience_player.play()
		_ambience_tween = create_tween()
		_ambience_tween.tween_property(
			_ambience_player,
			"volume_db",
			float(RAIN_VOLUME_DB.get(weather, -3.0)),
			AMBIENCE_FADE_SECONDS,
		)
		return
	_current_ambience_id = ""
	if not _ambience_player.playing:
		return
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(
		_ambience_player,
		"volume_db",
		SILENCE_DB,
		AMBIENCE_FADE_SECONDS,
	)
	_ambience_tween.finished.connect(_finish_rain_fade_out, CONNECT_ONE_SHOT)


func _sync_base_ambience() -> void:
	if _base_ambience_player == null:
		return
	var ambience_id := "indoor" if _is_indoor else (
		"night"
		if _is_sleep_time or NIGHT_PERIODS.has(_current_period)
		else "day"
	)
	if ambience_id == _current_base_ambience_id:
		return
	_current_base_ambience_id = ambience_id
	if _base_ambience_tween != null and _base_ambience_tween.is_valid():
		_base_ambience_tween.kill()
	if _base_ambience_player.playing:
		_base_ambience_tween = create_tween()
		_base_ambience_tween.tween_property(
			_base_ambience_player,
			"volume_db",
			SILENCE_DB,
			0.45,
		)
		_base_ambience_tween.tween_callback(
			_start_base_ambience.bind(ambience_id),
		)
		return
	_start_base_ambience(ambience_id)


func _start_base_ambience(ambience_id: String) -> void:
	if ambience_id != _current_base_ambience_id or _base_ambience_player == null:
		return
	var stream := _base_ambience_streams.get(ambience_id) as AudioStream
	if stream == null:
		stream = SOUND_LIBRARY.build_ambience(ambience_id)
		if stream != null:
			_base_ambience_streams[ambience_id] = stream
	if stream == null:
		return
	_base_ambience_player.stop()
	_base_ambience_player.stream = stream
	_base_ambience_player.volume_db = SILENCE_DB
	_base_ambience_player.play()
	_base_ambience_tween = create_tween()
	_base_ambience_tween.tween_property(
		_base_ambience_player,
		"volume_db",
		-3.0 if ambience_id == "indoor" else -1.0,
		0.8,
	)


func _finish_rain_fade_out() -> void:
	if not _current_ambience_id.is_empty() or _ambience_player == null:
		return
	_ambience_player.stop()


func _sync_sleep_noise(weather: String) -> void:
	if _sleep_noise_player == null:
		return
	var should_play := _is_sleep_time and not RAIN_WEATHER.has(weather)
	if should_play and _sleep_noise_player.stream == null:
		_sleep_noise_player.stream = _load_looping_stream(SLEEP_NOISE_PATH)
	if _sleep_noise_player.stream == null:
		return
	if _sleep_noise_tween != null and _sleep_noise_tween.is_valid():
		_sleep_noise_tween.kill()
	if should_play:
		_current_sleep_noise_id = "sleep_white_noise"
		if not _sleep_noise_player.playing:
			_sleep_noise_player.volume_db = SILENCE_DB
			_sleep_noise_player.play()
		_sleep_noise_tween = create_tween()
		_sleep_noise_tween.tween_property(
			_sleep_noise_player,
			"volume_db",
			SLEEP_NOISE_VOLUME_DB,
			SLEEP_NOISE_FADE_SECONDS,
		)
		return
	_current_sleep_noise_id = ""
	if not _sleep_noise_player.playing:
		return
	_sleep_noise_tween = create_tween()
	_sleep_noise_tween.tween_property(
		_sleep_noise_player,
		"volume_db",
		SILENCE_DB,
		SLEEP_NOISE_FADE_SECONDS,
	)
	_sleep_noise_tween.finished.connect(
		_finish_sleep_noise_fade_out,
		CONNECT_ONE_SHOT,
	)


func _finish_sleep_noise_fade_out() -> void:
	if not _current_sleep_noise_id.is_empty() or _sleep_noise_player == null:
		return
	_sleep_noise_player.stop()


func _sync_thunder_weather(weather: String) -> void:
	if weather == "雷暴":
		if _thunder_player != null and _thunder_player.stream == null:
			_thunder_player.stream = _load_audio_stream(THUNDER_SFX_PATH)
		if _current_weather != "雷暴":
			_thunder_wait_seconds = _rng.randf_range(
				THUNDER_FIRST_DELAY_RANGE.x,
				THUNDER_FIRST_DELAY_RANGE.y,
			)
		return
	_thunder_wait_seconds = -1.0
	if _thunder_player != null and _thunder_player.playing:
		_thunder_player.stop()


func _environment_music_id(weather: String = _current_weather) -> String:
	if _is_sleep_time:
		return "sleep"
	if weather == "雷暴":
		return "thunderstorm"
	if RAIN_WEATHER.has(weather):
		return "rain"
	if NIGHT_PERIODS.has(_current_period):
		return "night"
	return "day"


func _finish_music_override(expected_token: int) -> void:
	if (
		expected_token != _music_override_token
		or _music_override_id.is_empty()
		or _frontend_mode
	):
		return
	_music_override_id = ""
	_switch_music(_environment_music_id())


func _stop_environment_audio() -> void:
	for tween: Tween in [
		_ambience_tween,
		_base_ambience_tween,
		_sleep_noise_tween,
	]:
		if tween != null and tween.is_valid():
			tween.kill()
	_ambience_tween = null
	_base_ambience_tween = null
	_sleep_noise_tween = null
	for player: AudioStreamPlayer in [
		_ambience_player,
		_base_ambience_player,
		_sleep_noise_player,
	]:
		if player != null:
			player.stop()
			player.volume_db = SILENCE_DB
	if _thunder_player != null:
		_thunder_player.stop()
	_current_ambience_id = ""
	_current_base_ambience_id = ""
	_current_sleep_noise_id = ""
	_thunder_wait_seconds = -1.0
	_current_weather = ""


func _switch_music(music_id: String, force_restart: bool = false) -> void:
	if music_id == _current_music_id and not force_restart:
		return
	var stream := _select_music_stream(music_id)
	if stream == null or _music_players.is_empty():
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	var previous_music_id := _current_music_id
	var old_index := _active_music_index
	var target_index := 0 if old_index != 0 else 1
	var target := _music_players[target_index]
	target.stop()
	target.stream = stream
	target.volume_db = SILENCE_DB
	target.play()

	_active_music_index = target_index
	_current_music_id = music_id
	var fade_seconds := (
		SLEEP_CROSSFADE_SECONDS
		if music_id == "sleep" or previous_music_id == "sleep"
		else CROSSFADE_SECONDS
	)
	var target_volume_db := _music_volume_db(music_id)
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(
		target,
		"volume_db",
		target_volume_db,
		INITIAL_FADE_SECONDS if old_index < 0 else fade_seconds,
	)
	if old_index >= 0:
		var old_player := _music_players[old_index]
		_fade_tween.tween_property(
			old_player,
			"volume_db",
			SILENCE_DB,
			fade_seconds,
		)
	_fade_tween.finished.connect(
		_finish_crossfade.bind(old_index, target_index),
		CONNECT_ONE_SHOT,
	)


func _select_music_stream(music_id: String) -> AudioStream:
	_ensure_music_pool_loaded(music_id)
	var pool := _music_stream_pools.get(music_id, []) as Array
	if pool.is_empty():
		return null
	var pool_key := "daylife" if music_id in ["cover", "day"] else music_id
	var choices: Array[int] = []
	for index in pool.size():
		if pool.size() == 1 or pool_key != _current_music_pool_key or index != _current_music_variant_index:
			choices.append(index)
	var selected_index := choices[_rng.randi_range(0, choices.size() - 1)]
	_current_music_pool_key = pool_key
	_current_music_variant_index = selected_index
	return pool[selected_index] as AudioStream


func _music_pool_size(music_id: String) -> int:
	return (_music_stream_pools.get(music_id, []) as Array).size()


func _on_music_player_finished(player_index: int) -> void:
	if (
		_application_paused
		or player_index != _active_music_index
		or _current_music_id.is_empty()
	):
		return
	_switch_music(_current_music_id, true)


func _music_volume_db(music_id: String) -> float:
	match music_id:
		"cover":
			return COVER_MUSIC_VOLUME_DB
		"night":
			return EVENING_MUSIC_VOLUME_DB
		"rain":
			return RAIN_MUSIC_VOLUME_DB
		"thunderstorm":
			return THUNDERSTORM_MUSIC_VOLUME_DB
		"sleep":
			return SLEEP_MUSIC_VOLUME_DB
		_:
			return 0.0


func _finish_crossfade(old_index: int, expected_active_index: int) -> void:
	if old_index < 0 or _active_music_index != expected_active_index:
		return
	var old_player := _music_players[old_index]
	old_player.stop()
	old_player.stream = null


func _set_runtime_audio_paused(paused: bool) -> void:
	_application_paused = paused
	for player: AudioStreamPlayer in _music_players:
		player.stream_paused = paused
	if _ambience_player != null:
		_ambience_player.stream_paused = paused
	if _base_ambience_player != null:
		_base_ambience_player.stream_paused = paused
	if _sleep_noise_player != null:
		_sleep_noise_player.stream_paused = paused
	if _thunder_player != null:
		_thunder_player.stream_paused = paused
	for player: AudioStreamPlayer in _ui_players:
		player.stream_paused = paused
	for player: AudioStreamPlayer in _sfx_players:
		player.stream_paused = paused


func _time_is_sleep_time(time: Dictionary, period: String) -> bool:
	var clock := String(time.get("clock", ""))
	if clock.length() != 5 or clock.substr(2, 1) != ":":
		return period == "夜里"
	var parts := clock.split(":")
	if (
		parts.size() != 2
		or not String(parts[0]).is_valid_int()
		or not String(parts[1]).is_valid_int()
	):
		return period == "夜里"
	var hour := int(parts[0])
	var minute := int(parts[1])
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return period == "夜里"
	var minute_of_day := hour * 60 + minute
	return (
		minute_of_day >= SLEEP_START_MINUTE
		or minute_of_day < SLEEP_END_MINUTE
	)


func _build_ui_players() -> void:
	for index in UI_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "UiSfxPlayer%d" % (index + 1)
		player.bus = "UI"
		add_child(player)
		_ui_players.append(player)


func _build_sfx_players() -> void:
	for index in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "WorldSfxPlayer%d" % (index + 1)
		player.bus = "SFX"
		add_child(player)
		_sfx_players.append(player)


func _build_sound_library() -> void:
	_cue_streams = SOUND_LIBRARY.build_cues(
		UI_SAMPLE_RATE,
		FRONTEND_CUE_IDS,
	)
	_base_ambience_streams.clear()


func _play_pooled_stream(
	players: Array[AudioStreamPlayer],
	stream: AudioStream,
	min_pitch: float,
	max_pitch: float,
	volume_db: float,
	is_ui_pool: bool,
) -> void:
	if stream == null or players.is_empty():
		return
	var pool_size := players.size()
	var pool_cursor := _ui_pool_cursor if is_ui_pool else _sfx_pool_cursor
	var selected := -1
	for offset in pool_size:
		var index := (pool_cursor + offset) % pool_size
		if not players[index].playing:
			selected = index
			break
	if selected < 0:
		selected = pool_cursor
	var player := players[selected]
	player.stop()
	player.stream = stream
	player.pitch_scale = _rng.randf_range(min_pitch, max_pitch)
	player.volume_db = volume_db
	player.play()
	if is_ui_pool:
		_ui_pool_cursor = (selected + 1) % pool_size
	else:
		_sfx_pool_cursor = (selected + 1) % pool_size


func _wire_existing_buttons() -> void:
	_wire_buttons_below(get_tree().root)


func _wire_buttons_below(node: Node) -> void:
	_wire_control(node)
	for child: Node in node.get_children():
		_wire_buttons_below(child)


func _on_tree_node_added(node: Node) -> void:
	_wire_control(node)


func _wire_control(node: Node) -> void:
	_wire_button(node)
	_wire_slider(node)


func _wire_button(node: Node) -> void:
	if not node is BaseButton:
		return
	var button := node as BaseButton
	if button.is_in_group("audio_silent") or button.has_meta("town_audio_wired"):
		return
	button.set_meta("town_audio_wired", true)
	button.pressed.connect(_on_button_pressed.bind(button))
	_wired_button_count += 1


func _on_button_pressed(button: BaseButton) -> void:
	var cue_id := _cue_for_button(button)
	if cue_id == "ui_tap":
		play_ui_tap()
	else:
		play_cue(cue_id)


func _wire_slider(node: Node) -> void:
	if not node is Slider:
		return
	var slider := node as Slider
	if slider.is_in_group("audio_silent") or slider.has_meta("town_audio_wired"):
		return
	slider.set_meta("town_audio_wired", true)
	_slider_steps[slider.get_instance_id()] = _slider_step(slider)
	slider.value_changed.connect(_on_slider_value_changed.bind(slider))
	_wired_slider_count += 1


func _on_slider_value_changed(_value: float, slider: Slider) -> void:
	var instance_id := slider.get_instance_id()
	var step := _slider_step(slider)
	if int(_slider_steps.get(instance_id, step)) == step:
		return
	_slider_steps[instance_id] = step
	var now := Time.get_ticks_msec()
	if now - _last_slider_msec < SLIDER_COOLDOWN_MSEC:
		return
	_last_slider_msec = now
	play_cue("ui_slider")


func _slider_step(slider: Slider) -> int:
	var span := maxf(slider.max_value - slider.min_value, 0.001)
	return int(round((slider.value - slider.min_value) / span * 20.0))


func _cue_for_button(button: BaseButton) -> String:
	if button.has_meta("town_audio_cue"):
		return String(button.get_meta("town_audio_cue"))
	if button.toggle_mode:
		return "ui_toggle_on" if button.button_pressed else "ui_toggle_off"
	var search_text := String(button.name).to_lower()
	search_text += " " + button.tooltip_text.to_lower()
	if button is Button:
		search_text += " " + (button as Button).text.to_lower()
	# 取消/返回类先判：诸如"取消删除"是取消动作，不该播警告音。
	if _contains_any(search_text, BACK_LABEL_PARTS):
		return "ui_back"
	if _contains_any(search_text, WARNING_LABEL_PARTS):
		return "ui_warning"
	if _contains_any(search_text, PAGE_LABEL_PARTS):
		return "ui_page"
	if _contains_any(search_text, CONFIRM_LABEL_PARTS):
		return "ui_confirm"
	if _contains_any(search_text, TAB_LABEL_PARTS):
		return "ui_tab"
	if _contains_any(search_text, SELECT_LABEL_PARTS):
		return "ui_select"
	return "ui_tap"


func _contains_any(text: String, parts: Array) -> bool:
	for part_value: Variant in parts:
		if _matches_part(text, String(part_value).to_lower()):
			return true
	return false


func _matches_part(text: String, part: String) -> bool:
	if not _is_ascii_word(part):
		return text.contains(part)
	# 英文关键词按整词匹配，避免 "background" 命中 "back" 这类误判。
	var start := 0
	while true:
		var index := text.find(part, start)
		if index < 0:
			return false
		var before_ok := index == 0 or not _is_ascii_letter(text[index - 1])
		var after_index := index + part.length()
		var after_ok := after_index >= text.length() or not _is_ascii_letter(text[after_index])
		if before_ok and after_ok:
			return true
		start = index + 1
	return false


func _is_ascii_word(part: String) -> bool:
	for character: String in part:
		if not _is_ascii_letter(character):
			return false
	return not part.is_empty()


func _is_ascii_letter(character: String) -> bool:
	return character >= "a" and character <= "z"


func _cue_pitch_range(cue_id: String) -> Vector2:
	if cue_id.begins_with("footstep_"):
		return Vector2(0.975, 1.025)
	if cue_id == "sfx_avatar_descend":
		return Vector2.ONE
	if cue_id in ["ui_tap", "ui_slider", "ui_select", "ui_deselect"]:
		return Vector2(0.985, 1.015)
	if cue_id in ["prop_interact", "wardrobe_shuffle"]:
		return Vector2(0.96, 1.04)
	return Vector2(0.995, 1.005)


func _cue_volume_db(cue_id: String) -> float:
	if cue_id.begins_with("footstep_"):
		return -7.0
	if cue_id == "sfx_avatar_descend":
		return -1.0
	if cue_id in ["ui_slider", "ui_page"]:
		return -3.0
	if cue_id in ["dialogue_open", "message_reply", "camera_zoom"]:
		return -2.0
	if cue_id in ["weather_change", "event_notice"]:
		return -1.0
	return 0.0


func _percent_to_db(percent: int) -> float:
	if percent <= 0:
		return -80.0
	return linear_to_db(float(percent) / 100.0)


func _db_to_percent(db: float) -> int:
	if db <= -79.9:
		return 0
	return clampi(int(round(db_to_linear(db) * 100.0)), 0, 100)
